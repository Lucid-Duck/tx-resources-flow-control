# TX Resource Flow Control - Research Compilation

**Project:** rtw89 USB Driver TX Flow Control Implementation
**Created:** 2026-01-11
**Purpose:** Knowledge base for multi-session, multi-AI continuity

---

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Background & Context](#background--context)
3. [Existing Implementations (Reference)](#existing-implementations-reference)
4. [Key People & Resources](#key-people--resources)
5. [Technical Deep Dive](#technical-deep-dive)
6. [Related Issues & Discussions](#related-issues--discussions)
7. [Sources](#sources)

---

## Problem Statement

The rtw89 USB driver has a placeholder function that returns a hardcoded value instead of actual TX resource availability:

```c
// usb.c:165-173
static u32 rtw89_usb_ops_check_and_reclaim_tx_resource(struct rtw89_dev *rtwdev, u8 txch)
{
    if (txch == RTW89_TXCH_CH12)
        return 1;
    return 42; /* TODO some kind of calculation? */
}
```

**Impact:**
- mac80211 stack overwhelms USB subsystem with packets
- Tools like hcxdumptool report driver errors
- Low packet capture rates in monitor mode
- `continual_io_error` counter increments during high TX load

---

## Background & Context

### rtw89 Driver History

- **Original Driver:** PCI-only, in mainline kernel since 5.16 (Jan 2022)
- **USB Support Added:** 2024-2025, primarily by Bitterblue Smith
- **Based On:** rtw88_usb, rtw89_pci, official Realtek rtl8851bu driver

### USB Support Status

From [LWN Article](https://lwn.net/Articles/1024668/):
- Started with RTL8851BU
- Extended to RTL8832AU, RTL8852AU, RTL8852BU, RTL8852CU, RTL8922AU
- Some chips (RTL8852CU) have connection stability issues

### TX Architecture Differences: PCI vs USB

**PCI (three-layer DMA):**
```
TX BD (Buffer Descriptor) → TX WD (WiFi Descriptor) → SKB
```

**USB:**
```
SKB → URB (USB Request Block) → USB Bulk Endpoint
```

**Firmware Command Queue (TXCH 12):**
```
TX BD → Firmware Command (no WD layer)
```

This architectural difference is why the PCI implementation can't be directly copied — USB needs its own tracking mechanism.

---

## Existing Implementations (Reference)

### rtw89 PCI Implementation (pci.c:1256-1319)

The PCI version properly tracks resources:

```c
static u32 __rtw89_pci_check_and_reclaim_tx_resource(struct rtw89_dev *rtwdev, u8 txch)
{
    // Get available buffer descriptors
    bd_cnt = rtw89_pci_get_avail_txbd_num(tx_ring);
    // Get available work descriptors
    wd_cnt = wd_ring->curr_num;

    // If low, reclaim completed transmissions
    if (wd_cnt == 0 || bd_cnt == 0) {
        cnt = rtw89_pci_rxbd_recalc(rtwdev, rx_ring);
        if (cnt)
            rtw89_pci_release_tx(rtwdev, rx_ring, cnt);
    }

    // Return minimum of both resources
    return min(bd_cnt, wd_cnt);
}
```

**Key insight:** TXCH 12 (firmware commands) doesn't use WD, so it's handled separately.

### rtw88 USB Implementation

From [ulli-kroll/rtw88-usb](https://github.com/ulli-kroll/rtw88-usb):
- **No explicit `check_and_reclaim_tx_resource`**
- Relies on kernel SKB queue management
- Uses work queue with iteration limits (200 per cycle)
- Flow control delegated to mac80211 and USB subsystem

### mt76 USB Driver (MediaTek)

From [openwrt/mt76](https://github.com/openwrt/mt76):
- Uses `atomic_t non_aql_packets` per WCID (Wireless Client ID)
- Increments on queue, decrements on completion
- Sets stop flag when `pending >= MT_MAX_NON_AQL_PKT`
- More sophisticated: tracks per-station, not just per-channel

```c
// Queue packet
pending = atomic_inc_return(&wcid->non_aql_packets);
if (stop && pending >= MT_MAX_NON_AQL_PKT)
    *stop = true;

// Complete packet
pending = atomic_dec_return(&wcid->non_aql_packets);
if (pending < 0)
    atomic_cmpxchg(&wcid->non_aql_packets, pending, 0);
```

### ath9k_htc USB Driver

From [Patchwork](https://patchwork.kernel.org/patch/5767661/):
- Implements "adaptive USB flow control"
- Uses `usb_anchor` for tracking submitted URBs
- Has `aurfc_submit_delay` atomic for delayed submission
- Addresses soft lockup issues in monitor mode

---

## Key People & Resources

### Primary Developer

**Bitterblue Smith** (@dubhater)
- Author of rtw89 USB support
- Contact: rtl8821cerfe2@gmail.com
- Active on linux-wireless mailing list

### Realtek Maintainer

**Ping-Ke Shih** (pkshih@realtek.com)
- Maintains rtw89 in kernel
- Reviews and merges patches

### Community Resources

- **morrownr** - Maintains out-of-tree repos, community coordination
- **Larry Finger** (deceased May 2024) - Original rtw88/rtw89 contributor

---

## Technical Deep Dive

### URB Lifecycle in Linux

From [Kernel Documentation](https://docs.kernel.org/driver-api/usb/URB.html):

1. **Allocation:** `usb_alloc_urb()`
2. **Setup:** `usb_fill_bulk_urb()` with completion callback
3. **Submission:** `usb_submit_urb()` — asynchronous, returns immediately
4. **Completion:** Callback fires in interrupt/atomic context
5. **Cleanup:** `usb_free_urb()`

**Critical:** Completion handlers run in atomic context — cannot sleep, must be fast.

### Current rtw89 USB TX Flow

```
mac80211 calls tx_write()
    ↓
SKB queued to rtwusb->tx_queue[txch]
    ↓
tx_kick_off() called
    ↓
SKB dequeued, URB created
    ↓
usb_anchor_urb() to tx_submitted
    ↓
usb_submit_urb()
    ↓
[hardware transmits]
    ↓
rtw89_usb_write_port_complete() callback
    ↓
Report status to mac80211
```

### What's Missing

1. **Per-channel tracking:** `tx_submitted` anchor is global, not per-channel
2. **Count of in-flight URBs:** No atomic counter
3. **Backpressure signal:** Always returns 42, never signals "full"

### Proposed Solution Architecture

```c
struct rtw89_usb {
    // ... existing fields ...

    // NEW: Per-channel in-flight URB tracking
    atomic_t tx_inflight[RTW89_TXCH_NUM];
};

#define RTW89_USB_MAX_TX_URBS_PER_CH  32

static u32 rtw89_usb_ops_check_and_reclaim_tx_resource(...)
{
    if (txch == RTW89_TXCH_CH12)
        return 1;

    inflight = atomic_read(&rtwusb->tx_inflight[txch]);
    return max(0, RTW89_USB_MAX_TX_URBS_PER_CH - inflight);
}
```

---

## Related Issues & Discussions

### hcxdumptool Driver Errors

From [GitHub Issue #221](https://github.com/ZerBea/hcxdumptool/issues/221):
- USB WiFi adapters report "ERROR(s) during runtime (mostly caused by a broken driver)"
- Low packet capture rates
- Related to driver not supporting full packet injection

### PCI TX Resource Fix (2024)

From [Patchwork](https://patchwork.kernel.org/project/linux-wireless/patch/20240410011316.9906-1-pkshih@realtek.com/):
- Fixed firmware command drops during power state transitions
- Added check: `if (txch != RTW89_TXCH_CH12) cnt = min(cnt, wd_ring->curr_num);`
- Shows Realtek actively maintains TX resource logic

### mt7921u Pending TX Issues

From [GitHub Issue #410](https://github.com/morrownr/USB-WiFi/issues/410):
- "timed out waiting for pending tx" errors
- Similar symptoms to what we're seeing
- USB WiFi drivers commonly struggle with TX flow control

---

## Sources

### Official Documentation
- [Linux Kernel URB Documentation](https://docs.kernel.org/driver-api/usb/URB.html)
- [mac80211 Subsystem Documentation](https://www.kernel.org/doc/html/v4.9/80211/mac80211.html)
- [Linux Wireless Documentation](https://wireless.docs.kernel.org/)

### Code Repositories
- [morrownr/rtw89](https://github.com/morrownr/rtw89) - Out-of-tree development
- [lwfinger/rtw89](https://github.com/lwfinger/rtw89) - Larry Finger's repo
- [ulli-kroll/rtw88-usb](https://github.com/ulli-kroll/rtw88-usb) - rtw88 USB reference
- [openwrt/mt76](https://github.com/openwrt/mt76) - MediaTek reference driver
- [torvalds/linux](https://github.com/torvalds/linux) - Mainline kernel

### Mailing Lists & Patches
- [LWN: rtw89 USB Support](https://lwn.net/Articles/1024668/)
- [Patchwork: TX Resource Fix](https://patchwork.kernel.org/project/linux-wireless/patch/20240410011316.9906-1-pkshih@realtek.com/)
- [Patchwork: ath9k_htc Flow Control](https://patchwork.kernel.org/patch/5767661/)

### Community Discussions
- [morrownr/USB-WiFi Issue #628](https://github.com/morrownr/USB-WiFi/issues/628) - USB support announcement
- [ZerBea/hcxdumptool Issues](https://github.com/ZerBea/hcxdumptool/issues) - Tool compatibility

---

## Next Steps

1. **Implement minimal tracking** — atomic counters per channel
2. **Test basic functionality** — ensure WiFi still works
3. **Stress test** — high throughput, packet injection
4. **Submit to morrownr/rtw89** — community review
5. **Iterate based on feedback**
6. **Submit to linux-wireless** — mainline inclusion

---

*This document is a living knowledge base. Update as research continues.*
