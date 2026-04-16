# rtw89 USB TX Flow Control Fix

Fixes a mac80211 TX flow control contract violation in the rtw89 USB driver, where available TX resources were reported inaccurately, preventing backpressure and causing USB TX overcommit under load.

**Author:** Lucid Duck &lt;lucid_duck@justthetip.ca&gt;
**Status:** **Merged to mainline** as commit [`80119a77e5b0`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=80119a77e5b0) on 2026-04-02. Acked-by + Signed-off-by: Ping-Ke Shih (Realtek rtw89 maintainer). Reported-by: morrownr.
**Hardware:** D-Link DWA-X1850 (RTL8832AU) on kernel 6.19.8, Fedora 43

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

## Patch History

The repo captures the iterative development across five local patches. The squashed v4 posted to linux-wireless on 2026-04-02 (Message-ID `20260402052216.207858-1-lucid_duck@justthetip.ca`) is what Ping-Ke Shih Acked and applied to the rtw89 tree. That single commit is what landed in mainline as `80119a77e5b0`.

| Stage | Purpose |
|-------|---------|
| Basic accounting | Core `tx_inflight[]` counters and flow control logic |
| Debug instrumentation | Temporary warnings used for validation (removed before merge) |
| CH12 handling | Exclude firmware command channel from tracking |
| Submit/completion race fix | Pre-increment before submit to prevent race |
| `atomic_dec_return` in completion | Race-free underflow detection |

The final merged commit also raised `MAX_TX_URBS` from 64 to 128 per channel to provide headroom for RTL8832CU at 160 MHz bandwidth.

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

- **v1:** [2026-01-25](https://lore.kernel.org/linux-wireless/20260125221943.36001-1-lucid_duck@justthetip.ca/) -- reviewed by Ping-Ke Shih (Realtek), Bitterblue Smith
- **v2:** [2026-01-29](https://lore.kernel.org/linux-wireless/20260130040252.67686-1-lucid_duck@justthetip.ca/) -- addressed reviewer feedback, added test results
- **Reply to Ping-Ke's v2 review:** 2026-03-23 (Message-ID: `20260323233334.158678-1-lucid_duck@justthetip.ca`) -- comprehensive test data addressing uplink, URB scaling, small packets, multi-stream, and soak tests
- **v3:** 2026-03-23 (Message-ID: `20260323233347.158745-1-lucid_duck@justthetip.ca`) -- MAX_TX_URBS changed from 32 to 64, comments removed, test data in commit message
- **v4 (final):** 2026-04-02 (Message-ID: `20260402052216.207858-1-lucid_duck@justthetip.ca`, [patch.msgid.link](https://patch.msgid.link/20260402052216.207858-1-lucid_duck@justthetip.ca)) -- `MAX_TX_URBS` raised to 128 for RTL8832CU 160 MHz headroom. Acked-by: Ping-Ke Shih.
- **Merged:** 2026-04-02 as mainline commit [`80119a77e5b0`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=80119a77e5b0).

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
