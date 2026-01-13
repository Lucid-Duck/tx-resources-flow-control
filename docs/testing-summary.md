# Testing Summary

**Hardware:** D-Link DWA-X1850 (RTL8832AU, USB ID 2001:3321)
**Kernel:** 6.18.3-200.fc43.x86_64
**Driver:** morrownr/rtw89 out-of-tree

---

## 1. Accounting Correctness

**Goal:** Verify every `atomic_inc()` has exactly one corresponding `atomic_dec()`.

**Method:**
- Code path audit of submit/completion/failure paths
- Debug instrumentation to detect counter underflow
- Runtime monitoring via `pr_warn_ratelimited()` on underflow

**Results:**
- Zero UNDERFLOW warnings across all tests
- Zero OVERFLOW warnings across all tests
- All increment paths have corresponding decrements
- Failure paths correctly roll back pre-incremented counters

---

## 2. Backpressure Observation

**Goal:** Confirm mac80211 receives accurate resource availability and pauses TX when at capacity.

**Method:**
- Reduced `RTW89_USB_MAX_TX_URBS_PER_CH` to 4 (from 32) to force backpressure
- Monitored `check_and_reclaim_tx_resource()` return values via debug output
- Observed mac80211 queue pause/resume behavior under load

**Results:**
- Function returns 0 when inflight equals max URBs
- mac80211 correctly pauses queue when driver signals 0 resources
- Queue resumes when completions free capacity
- No queue stalls after backpressure release

---

## 3. Stress & Soak

**Goal:** Verify stability under sustained TX load and long-duration operation.

**Method:**
- 100-iteration flood ping stress test (continuous TX pressure)
- 30-minute soak test with periodic TX bursts
- Counter balance verification at idle after load

**Results:**

| Test | Iterations/Duration | Warnings | Counter Balance |
|------|---------------------|----------|-----------------|
| Stress (flood ping) | 100 iterations | 0 | Verified |
| Soak | 30 minutes | 0 | Verified |

Counters return to exactly 0 when traffic stops.

---

## 4. Teardown Safety

**Goal:** Verify correct behavior during driver unload and device removal.

**Method:**
- 50-iteration software teardown (rmmod/modprobe cycles under TX load)
- 10x physical hot-unplug during active flood ping
- Monitor for panics, hangs, and counter imbalance

**Results:**

| Test | Iterations | Kernel Panics | Counter Imbalance | URB Errors |
|------|------------|---------------|-------------------|------------|
| Software teardown | 50 | 0 | 0 | 0 |
| Hot-unplug | 10 | 0 | 0 | Expected EPROTO |

USB subsystem cancels in-flight URBs via `usb_kill_anchored_urbs()`. Completion callbacks fire for cancelled URBs, maintaining counter balance.

---

## Before / After Comparison

Same hardware, same kernel, same workload (monitor mode TX stress):

| Driver State | Duration | Packets TX'd | Errors |
|--------------|----------|--------------|--------|
| Stock (return 42) | 35s | 4 | 6 |
| Stock (return 42) | 50s | 70 | 8 |
| Patched | 45s | 840 | 0 |
| Patched | 60s | 1804 | 0 |

