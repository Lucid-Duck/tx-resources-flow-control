# Pull Request Draft for morrownr/rtw89

---

## Title

**usb: implement TX flow control for mac80211 backpressure**

---

## Description

### Summary

This patch series implements proper TX resource tracking for USB devices, replacing the placeholder `return 42` in `rtw89_usb_ops_check_and_reclaim_tx_resource()` with actual per-channel URB accounting.

### The Problem

The current USB implementation returns a hardcoded value to mac80211 when asked how many TX resources are available:

```c
return 42; /* TODO some kind of calculation? */
```

This violates mac80211's flow control contract. The stack assumes drivers will honestly report TX capacity so it can apply backpressure when resources are exhausted. Without accurate reporting:

- mac80211 never throttles TX submission
- URBs pile up uncontrollably in the USB subsystem
- Tools like hcxdumptool report "broken driver" errors
- Packet injection and capture performance suffers

### The Solution

Add per-channel atomic counters (`tx_inflight[]`) that track in-flight URBs:

- **Increment** before `usb_submit_urb()` succeeds
- **Decrement** unconditionally in the completion callback
- **Return** `(max_urbs - inflight)` to mac80211

When inflight reaches the maximum (32 per channel), the function returns 0, signaling mac80211 to stop queueing. When completions arrive, resources become available again.

### Key Implementation Details

1. **Race condition handling**: The increment happens *before* URB submission with rollback on failure. This prevents a race where the completion callback fires before the increment.

2. **CH12 exclusion**: The firmware command channel (RTW89_TXCH_CH12) is excluded from tracking as it has different semantics.

3. **Underflow detection**: Uses `atomic_dec_return()` in the completion callback to atomically detect counter underflow (indicates accounting bugs).

---

## Patches

| # | Patch | Description |
|---|-------|-------------|
| 1 | `usb: implement TX flow control` | Core implementation: atomic counters, increment/decrement, return calculation |
| 2 | `usb: add debug instrumentation` | Temporary debug warnings for backpressure and underflow (can be removed for production) |
| 3 | `usb: fix CH12 tracking skip` | Exclude firmware command channel from tracking |
| 4 | `usb: fix increment race condition` | Move increment before submit to prevent race with completion |
| 5 | `usb: use atomic_dec_return()` | Race-free underflow detection |

**Note**: For final submission, patches 1-5 could be squashed into a single clean patch. The separate patches show the development/debugging process.

---

## Testing

Tested on Fedora 43 (kernel 6.18.3) with D-Link DWA-X1850 (RTL8832AU, USB ID 2001:3321).

### Test Results Summary

| Test | Iterations | Result |
|------|------------|--------|
| Stress test (flood ping) | 100 | PASS - 0 warnings |
| Software teardown (rmmod/modprobe under load) | 50 | PASS - 0 kernel complaints |
| Physical hot-unplug under TX load | 10 | PASS - 0 panics, graceful recovery |
| 30-minute soak test | 1800s | PASS - counters balanced at idle |

### Verification Details

- **Zero UNDERFLOW warnings** across all tests
- **Zero OVERFLOW warnings** across all tests
- **Backpressure observed**: When `MAX_TX_URBS=4` (reduced for testing), driver correctly returned 0 to mac80211 at capacity
- **Memory stable**: No leaks detected during 30-minute soak
- **Counter balance verified**: After all traffic stopped, counters returned to exactly 0

### Edge Cases Tested

- Hot-unplug during active flood ping (URB cancellation path)
- Slow USB disconnect causing EPROTO errors (graceful handling)
- Rapid rmmod/modprobe cycles under load

---

## Hardware Tested

- D-Link DWA-X1850 (RTL8832AU / WiFi 6)

Additional testing on RTL8852BU and RTL8851BU devices would be valuable.

---

## What This Patch Does NOT Fix

This patch specifically addresses TX flow control accounting. It does not claim to fix:

- RX path issues
- Firmware bugs
- Power management issues
- Monitor mode quirks unrelated to TX congestion
- All possible USB WiFi problems

---

## Files Changed

- `usb.c` - Core implementation
- `usb.h` - Add `tx_inflight[]` array and `RTW89_USB_MAX_TX_URBS_PER_CH` define

---

## Checklist

- [x] Builds without warnings
- [x] Module loads/unloads cleanly
- [x] Basic functionality verified (scan, connect, data transfer)
- [x] Stress tested
- [x] Hot-unplug tested
- [x] Soak tested
- [x] Counter balance verified at idle
- [ ] Tested on multiple hardware variants
- [ ] Reviewed by maintainer

---

## References

- PCI implementation for comparison: `pci.c:rtw89_pci_ops_check_and_reclaim_tx_resource()`
- USB URB lifecycle: `usb_submit_urb()` guarantees exactly one completion callback on success
- mac80211 TX flow control expectations

---

*Patch series against morrownr/rtw89 main branch.*
