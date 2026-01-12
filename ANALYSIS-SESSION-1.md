# TX Resource Flow Control - Analysis Session 1

**Date:** 2026-01-11
**Focus:** Understanding the USB TX path and what needs to change

---

## The Problem Restated

```c
// usb.c:165-173
static u32 rtw89_usb_ops_check_and_reclaim_tx_resource(struct rtw89_dev *rtwdev, u8 txch)
{
    if (txch == RTW89_TXCH_CH12)
        return 1;
    return 42; /* TODO some kind of calculation? */
}
```

This function lies to mac80211. It always says "42 slots available" regardless of actual USB resource state. The mac80211 stack trusts this and keeps pushing packets, overwhelming the USB subsystem.

---

## TX Channel Architecture

From `txrx.h:638-654`:

| Channel | Name | Purpose |
|---------|------|---------|
| 0-7 | RTW89_TXCH_ACH0-7 | Access channels (data traffic) |
| 8 | RTW89_TXCH_CH8 | Management Band 0 |
| 9 | RTW89_TXCH_CH9 | HI Band 0 |
| 10 | RTW89_TXCH_CH10 | Management Band 1 |
| 11 | RTW89_TXCH_CH11 | HI Band 1 |
| 12 | RTW89_TXCH_CH12 | FW Command (special) |

**Total: 13 channels (RTW89_TXCH_NUM)**

Channel 12 is special — it's for firmware commands, low volume, returns 1.

---

## Current USB TX Flow

### 1. tx_write (usb.c:370-415)
- Receives TX request from mac80211
- Builds TX descriptor, prepends to SKB
- Queues to `rtwusb->tx_queue[txch]`
- **Does NOT submit URB yet**

### 2. tx_kick_off (usb.c:290-326)
- Called to flush queued packets
- Dequeues from `tx_queue[txch]`
- Creates `rtw89_usb_tx_ctrl_block` for each packet
- Calls `rtw89_usb_write_port()` to submit URB

### 3. write_port (usb.c:240-279)
- Allocates URB with `usb_alloc_urb()`
- Fills bulk URB with completion callback
- Anchors URB to `rtwusb->tx_submitted`
- Submits with `usb_submit_urb()`

### 4. write_port_complete (usb.c:175-238)
- Completion callback when URB finishes
- Processes TX status, frees resources
- Reports status to mac80211

---

## Current Data Structures (usb.h)

```c
struct rtw89_usb {
    // ...
    struct usb_anchor tx_submitted;           // All submitted URBs (not per-channel!)
    struct sk_buff_head tx_queue[RTW89_TXCH_NUM];  // Per-channel pre-submit queues
};
```

**What's Missing:**
- No per-channel counter for in-flight URBs
- No max URBs per channel definition
- No way to know how many URBs are currently submitted per channel

---

## PCI Reference (pci.c:1256-1319)

The PCI version tracks:
1. **Buffer Descriptors (BD)** — hardware ring buffer slots
2. **Work Descriptors (WD)** — software tracking structures

```c
bd_cnt = rtw89_pci_get_avail_txbd_num(tx_ring);
wd_cnt = wd_ring->curr_num;
min_cnt = min(bd_cnt, wd_cnt);
return min_cnt;
```

It also has **reclamation logic** — when resources are low, it checks the completion ring and frees completed descriptors.

---

## Proposed USB Solution

### New Fields in `struct rtw89_usb`:

```c
struct rtw89_usb {
    // ... existing fields ...

    // NEW: Per-channel in-flight URB tracking
    atomic_t tx_inflight[RTW89_TXCH_NUM];
};
```

### New Constant:

```c
#define RTW89_USB_MAX_TX_URBS_PER_CH  32  // Tunable
```

### Modified check_and_reclaim:

```c
static u32 rtw89_usb_ops_check_and_reclaim_tx_resource(struct rtw89_dev *rtwdev, u8 txch)
{
    struct rtw89_usb *rtwusb = rtw89_usb_priv(rtwdev);
    int inflight;

    if (txch == RTW89_TXCH_CH12)
        return 1;  // FW command channel stays as-is

    inflight = atomic_read(&rtwusb->tx_inflight[txch]);

    if (inflight >= RTW89_USB_MAX_TX_URBS_PER_CH)
        return 0;  // No resources available

    return RTW89_USB_MAX_TX_URBS_PER_CH - inflight;
}
```

### Modified write_port (on successful submit):

```c
ret = usb_submit_urb(urb, GFP_ATOMIC);
if (ret == 0) {
    atomic_inc(&rtwusb->tx_inflight[txcb->txch]);
}
```

### Modified write_port_complete:

```c
static void rtw89_usb_write_port_complete(struct urb *urb)
{
    struct rtw89_usb_tx_ctrl_block *txcb = urb->context;
    struct rtw89_dev *rtwdev = txcb->rtwdev;
    struct rtw89_usb *rtwusb = rtw89_usb_priv(rtwdev);

    // Decrement in-flight counter
    atomic_dec(&rtwusb->tx_inflight[txcb->txch]);

    // ... rest of existing completion handling ...
}
```

### Initialization:

```c
static void rtw89_usb_init_tx(struct rtw89_dev *rtwdev)
{
    struct rtw89_usb *rtwusb = rtw89_usb_priv(rtwdev);
    int i;

    for (i = 0; i < ARRAY_SIZE(rtwusb->tx_queue); i++) {
        skb_queue_head_init(&rtwusb->tx_queue[i]);
        atomic_set(&rtwusb->tx_inflight[i], 0);  // NEW
    }
}
```

---

## Complexity Analysis

| Change | Location | Risk |
|--------|----------|------|
| Add atomic counter array | usb.h | Low |
| Initialize counters | usb.c init_tx | Low |
| Increment on submit | usb.c write_port | Low |
| Decrement on complete | usb.c write_port_complete | Low |
| Return actual count | usb.c check_and_reclaim | Low |

**Overall: Low-Medium complexity, high impact.**

---

## Testing Strategy

1. **Basic Functionality**
   - Does WiFi still connect?
   - Can we browse the web?

2. **Stress Testing**
   - iperf3 throughput tests
   - Large file transfers

3. **Packet Injection**
   - hcxdumptool (the original failure case)
   - Monitor mode capture rates

4. **Error Conditions**
   - What happens when we hit the limit?
   - Does backpressure work correctly?

---

## Open Questions

1. **What's the right value for RTW89_USB_MAX_TX_URBS_PER_CH?**
   - Too low = unnecessary throttling
   - Too high = back to overwhelming USB
   - Start with 32, tune based on testing

2. **Should different channels have different limits?**
   - ACH0-7 (data) might need more than CH8-11 (mgmt)
   - Start uniform, optimize later

3. **Do we need reclamation logic like PCI?**
   - USB completion callbacks already handle this
   - Atomic decrement in callback should suffice

---

## Next Steps

1. Create a patch with the minimal changes
2. Build and test on Fedora host
3. Test with hcxdumptool in Kali VM
4. Tune RTW89_USB_MAX_TX_URBS_PER_CH based on results
5. Submit to morrownr/rtw89 for review

---

## Test Environment

| System | Role |
|--------|------|
| Fedora 43 Host | Primary development, bare metal testing |
| Kali VM | Packet injection testing, hcxdumptool |
| Windows 11 VM | Comparative testing if needed |
| Android Galaxy S22 | Additional perspective |

---

*This crusade just got a roadmap.*
