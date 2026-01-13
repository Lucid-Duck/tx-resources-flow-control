# rtw89 USB TX Flow Control Fix

This work fixes a mac80211 TX flow control contract violation in the rtw89 USB driver, where available TX resources were reported inaccurately, preventing backpressure and causing USB TX overcommit under load.

---

## Problem

`rtw89_usb_ops_check_and_reclaim_tx_resource()` returns a hardcoded placeholder:

```c
return 42; /* TODO some kind of calculation? */
```

mac80211 relies on this function to apply TX backpressure. Returning a constant non-zero value prevents throttling, causing USB URBs to accumulate faster than they complete.

**Symptoms:**
- Tool-visible errors (e.g., hcxdumptool "broken driver")
- Degraded capture under sustained TX load
- USB instability during high-throughput operations

This is a **transport correctness issue**, not a tool-specific bug.

---

## Solution

Implement per-channel atomic tracking of in-flight URBs:

```
Submit Path:
  atomic_inc(&tx_inflight[ch])  ->  usb_submit_urb()
  (rollback on failure)

Completion Path:
  urb_complete()  ->  atomic_dec_return(&tx_inflight[ch])

Query Path:
  check_and_reclaim_tx_resource():
    return (MAX_URBS - inflight)   // 0 signals backpressure
```

- Increment exactly once per successful URB submission
- Decrement exactly once per URB completion or cancellation
- Return remaining capacity to mac80211
- Return `0` when at capacity to signal backpressure
- Exclude CH12 (firmware command channel) from tracking

---

## Patch Series

| # | Patch | Purpose |
|---|-------|---------|
| 0001 | Implement basic accounting | Core `tx_inflight[]` counters and flow control logic |
| 0002 | Add debug instrumentation | Temporary warnings for backpressure/underflow events |
| 0003 | Correct CH12 handling | Exclude firmware command channel from tracking |
| 0004 | Fix submit/completion race | Pre-increment before submit to prevent race |
| 0005 | Use `atomic_dec_return()` | Race-free underflow detection in completion path |

Patches 0002-0005 exist to guarantee correctness under concurrency and teardown, not to add features.

---

## Verification

See [docs/testing-summary.md](docs/testing-summary.md) for full details.

### Summary

| Category | Method | Result |
|----------|--------|--------|
| Accounting Correctness | Path audit, instrumented runtime | Every inc has exactly one dec |
| Backpressure Observation | Constrained max URBs, observed `return 0` | mac80211 pauses/resumes correctly |
| Stress & Soak | Sustained TX, 30-minute soak | Counters return to zero at idle |
| Teardown Safety | Hot-unplug during active TX | No panic, no counter imbalance |

### Before / After

Same hardware (RTL8832AU), same environment, same tool:

| Driver State | Duration | Packets Captured | Errors |
|--------------|----------|------------------|--------|
| Stock | 35s | 4 | 6 |
| Stock | 50s | 70 | 8 |
| Patched | 45s | 840 | 0 |
| Patched | 60s | 1804 | 0 |

---

## Scope and Non-Goals

This work addresses **TX flow control accounting only**.

It does **not** address:
- RX path behavior
- Firmware correctness
- Power management
- Error recovery mechanisms
- RTL8922A L1 recovery (`rtw89_usb_ops_lv1_rcvy`)
- Error status dumping (`rtw89_usb_ops_dump_err_status`)
- USB issues unrelated to TX backpressure

---

## Hardware Tested

- D-Link DWA-X1850 (RTL8832AU, USB ID 2001:3321)
- Kernel 6.18.3, Fedora 43

Additional testing on RTL8852BU and RTL8851BU devices would be valuable.

---

## Files

```
patches/
  0001-usb-implement-tx-flow-control.patch
  0002-usb-add-debug-instrumentation.patch
  0003-usb-fix-ch12-tracking-skip.patch
  0004-usb-fix-increment-race-condition.patch
  0005-usb-use-atomic_dec_return-for-underflow-detection.patch
docs/
  testing-summary.md
```

---

This change restores correct TX backpressure semantics for rtw89 USB and is intended to make existing workloads behave correctly under sustained load, without altering unrelated driver behavior.
