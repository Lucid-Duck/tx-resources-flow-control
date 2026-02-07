# rtw89 USB TX Flow Control Fix

Fixes a mac80211 TX flow control contract violation in the rtw89 USB driver, where available TX resources were reported inaccurately, preventing backpressure and causing USB TX overcommit under load.

**Author:** Lucid Duck &lt;lucid_duck@justthetip.ca&gt;
**Status:** Submitted to linux-wireless ([v2 on lore](https://lore.kernel.org/linux-wireless/20260130040252.67686-1-lucid_duck@justthetip.ca/)) — awaiting maintainer response
**Hardware:** D-Link DWA-X1850 (RTL8832AU) on kernel 6.18.3, Fedora 43

---

## Problem

`rtw89_usb_ops_check_and_reclaim_tx_resource()` returns a hardcoded placeholder:

```c
return 42; /* TODO some kind of calculation? */
```

mac80211 relies on this function to apply TX backpressure. When drivers honestly report TX capacity, mac80211 can throttle submission when resources are exhausted. Returning a constant non-zero value defeats this mechanism, causing USB URBs to accumulate faster than they complete.

**Symptoms:**
- Monitor mode tools report driver errors
- Degraded performance under sustained TX load
- USB subsystem instability during high-throughput operations

This is a **mac80211 contract violation**, not a tool-specific or use-case-specific bug.

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
| 0002 | Add debug instrumentation | Temporary warnings for validation (not for upstream merge) |
| 0003 | Correct CH12 handling | Exclude firmware command channel from tracking |
| 0004 | Fix submit/completion race | Pre-increment before submit to prevent race |
| 0005 | Use `atomic_dec_return()` | Race-free underflow detection in completion path |

Patches 0003-0005 fix correctness issues discovered during validation. Patch 0002 is debug instrumentation used to verify accounting; it should be removed or gated behind `CONFIG_RTW89_DEBUG` for production.

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

This patch implements TX backpressure accounting only. It does not claim to fix all rtw89 USB issues.

It does **not** address:
- RX path behavior
- Firmware correctness
- Power management
- Error recovery mechanisms
- RTL8922A L1 recovery (`rtw89_usb_ops_lv1_rcvy`)
- Error status dumping (`rtw89_usb_ops_dump_err_status`)
- USB issues unrelated to TX backpressure

---

## Throughput (iperf3)

Measured before and after the patch on the same hardware:

```
                     Unpatched -> Patched
USB3 5GHz:
  Download:          494 -> 709 Mbps (+44%)
  Upload:            757 -> 753 Mbps (same)
  Retransmits:       8 -> 1 (-88%)

USB3 2.4GHz:
  Download:          54 -> 68 Mbps (+25%)
  Upload:            128 -> 137 Mbps (+6%)

USB2 5GHz:
  Download:          196 -> 225 Mbps (+15%)
  Upload:            255 -> 255 Mbps (same)

USB2 2.4GHz:
  Download:          123 -> 131 Mbps (+6%)
  Upload:            153 -> 152 Mbps (same)
```

---

## Hardware Tested

- D-Link DWA-X1850 (RTL8832AU, USB ID 2001:3321)
- Kernel 6.18.3, Fedora 43

Additional testing on RTL8852BU and RTL8851BU devices would be valuable.

---

## Mailing List

- **v1:** [2026-01-25](https://lore.kernel.org/linux-wireless/20260125221943.36001-1-lucid_duck@justthetip.ca/) — reviewed by Ping-Ke Shih (Realtek), Bitterblue Smith
- **v2:** [2026-01-29](https://lore.kernel.org/linux-wireless/20260130040252.67686-1-lucid_duck@justthetip.ca/) — addressed reviewer feedback, added test results
- Awaiting maintainer response

---

## Files

```
patches/
  0000-usb-fix-mac80211-tx-flow-control-SQUASHED.patch   # Single squashed commit
  0001-usb-implement-tx-flow-control.patch                # Core accounting
  0002-usb-add-debug-instrumentation.patch                # Debug only (not for merge)
  0003-usb-fix-ch12-tracking-skip.patch                   # Exclude firmware channel
  0004-usb-fix-increment-race-condition.patch              # Pre-increment race fix
  0005-usb-use-atomic_dec_return-for-underflow-detection.patch
docs/
  testing-summary.md                                       # Full verification results
```

---

This change restores correct TX backpressure semantics for rtw89 USB and is intended to make existing workloads behave correctly under sustained load, without altering unrelated driver behavior.
