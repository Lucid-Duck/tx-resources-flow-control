# Pull Request Draft for morrownr/rtw89

---

## Title

**usb: fix mac80211 TX flow control contract violation**

---

## Description

### Summary

This restores correct mac80211 TX backpressure semantics for rtw89 USB.

### The Bug

The current USB implementation returns a hardcoded value:

```c
return 42; /* TODO some kind of calculation? */
```

mac80211 calls this function to determine available TX resources. Drivers must honestly report capacity so mac80211 can throttle submission when resources are exhausted. Returning a constant non-zero value violates this contract:

- mac80211 never throttles TX submission
- URBs accumulate uncontrollably in the USB subsystem
- Observable failures under sustained TX load

### The Fix

Add per-channel atomic counters (`tx_inflight[]`) that track in-flight URBs:

- **Increment** before `usb_submit_urb()` with rollback on failure
- **Decrement** in the completion callback via `atomic_dec_return()`
- **Return** `(MAX_URBS - inflight)` to mac80211, or 0 when at capacity

When inflight reaches the maximum (32 per channel), the function returns 0, signaling mac80211 to pause TX submission. When completions arrive, resources become available again.

### Key Implementation Details

1. **Race condition prevention**: The increment happens *before* URB submission with rollback on failure. This prevents a race where the completion callback fires before the increment (the USB core may complete inline or on another CPU).

2. **CH12 exclusion**: The firmware command channel (RTW89_TXCH_CH12) is intentionally excluded from tracking. It has different semantics and must not be throttled.

3. **Underflow detection**: Uses `atomic_dec_return()` to atomically detect counter underflow, which would indicate an accounting bug.

---

## Patches (For Merge)

| # | Patch | Description |
|---|-------|-------------|
| 1 | `usb: implement TX flow control` | Core implementation: atomic counters, increment/decrement, return calculation |
| 3 | `usb: fix CH12 tracking skip` | Exclude firmware command channel from tracking |
| 4 | `usb: fix increment race condition` | Move increment before submit to prevent race |
| 5 | `usb: use atomic_dec_return()` | Race-free underflow detection |

For final submission, these four patches can be squashed into a single commit.

### Not For Merge

| # | Patch | Purpose |
|---|-------|---------|
| 2 | `usb: add debug instrumentation` | Used during development to verify accounting correctness. Not intended for upstream. |

---

## Testing

Tested on Fedora 43 (kernel 6.18.3) with D-Link DWA-X1850 (RTL8832AU, USB ID 2001:3321).

### Verification Summary

| Category | Method | Result |
|----------|--------|--------|
| Accounting Correctness | Path audit, instrumented runtime | Every inc has exactly one dec |
| Backpressure Observation | Constrained MAX_URBS=4, observed return 0 | mac80211 pauses/resumes correctly |
| Stress & Soak | 100 iterations flood ping, 30-minute soak | Counters return to zero at idle |
| Teardown Safety | 50 rmmod cycles, 10 hot-unplug under load | No panic, no counter imbalance |

### Verification Details

- **Zero UNDERFLOW warnings** across all tests
- **Zero OVERFLOW warnings** across all tests
- **Backpressure observed**: With MAX_URBS=4, driver correctly returned 0 at capacity
- **Counter balance verified**: After traffic stops, counters return to exactly 0
- **Hot-unplug safe**: URB cancellation via `usb_kill_anchored_urbs()` triggers completion callbacks, maintaining counter balance

---

## Hardware Tested

- D-Link DWA-X1850 (RTL8832AU / WiFi 6)

Additional testing on RTL8852BU and RTL8851BU devices would be valuable.

---

## Scope

This patch specifically addresses TX flow control accounting. It does not address:

- RX path behavior
- Firmware correctness
- Power management
- Error recovery mechanisms (e.g., `rtw89_usb_ops_lv1_rcvy`)
- USB issues unrelated to TX backpressure

---

## Files Changed

- `usb.c` - Core implementation
- `usb.h` - Add `tx_inflight[]` array and `RTW89_USB_MAX_TX_URBS_PER_CH` define

---

## Checklist

- [x] Builds without warnings
- [x] Module loads/unloads cleanly
- [x] Basic functionality verified (scan, connect, data transfer)
- [x] Stress tested (100 iterations)
- [x] Hot-unplug tested (10 cycles)
- [x] Soak tested (30 minutes)
- [x] Counter balance verified at idle
- [ ] Tested on multiple hardware variants
- [ ] Reviewed by maintainer

---

## References

- PCI implementation: `pci.c:rtw89_pci_ops_check_and_reclaim_tx_resource()`
- USB URB lifecycle: `usb_submit_urb()` guarantees exactly one completion callback on success
- mac80211 TX flow control contract

---

*Patch series against morrownr/rtw89 main branch.*
