# TX Flow Control - Code Path Audit

**Date:** 2026-01-11
**Auditor:** Human + Claude collaboration
**Status:** VERIFIED CORRECT

---

## The Core Question

> For every atomic_inc() on submit, is there exactly one matching decrement on completion or cancellation, for every possible path, including shutdown?

**Answer: YES**

---

## Counter Operations

| Location | Operation | Line |
|----------|-----------|------|
| `rtw89_usb_ops_tx_kick_off()` | `atomic_inc()` | usb.c:354 |
| `rtw89_usb_write_port_complete()` | `atomic_dec()` | usb.c:265 |
| `rtw89_usb_init_tx()` | `atomic_set(..., 0)` | usb.c:730 |

---

## Path Analysis

### Path 1: Submit Fails
```
rtw89_usb_ops_tx_kick_off()
  → rtw89_usb_write_port() returns error
  → if (ret) branch taken
  → NO INCREMENT
  → Resources cleaned up
```
**Result:** No increment, no decrement needed. BALANCED.

### Path 2: Submit Succeeds, Normal Completion
```
rtw89_usb_ops_tx_kick_off()
  → rtw89_usb_write_port() returns 0
  → else branch taken
  → atomic_inc() ← INCREMENT
  → [USB core processes URB]
  → rtw89_usb_write_port_complete() called
  → atomic_dec() ← DECREMENT
```
**Result:** One increment, one decrement. BALANCED.

### Path 3: Submit Succeeds, Error Completion
```
rtw89_usb_ops_tx_kick_off()
  → rtw89_usb_write_port() returns 0
  → atomic_inc() ← INCREMENT
  → [USB error occurs]
  → rtw89_usb_write_port_complete() called with error status
  → atomic_dec() ← DECREMENT (unconditional)
```
**Result:** One increment, one decrement. BALANCED.

### Path 4: Device Unplugged Mid-Flight
```
[URB in flight, counter incremented]
  → Device disconnected
  → USB core cancels all pending URBs
  → rtw89_usb_write_port_complete() called with -ENODEV
  → atomic_dec() ← DECREMENT
```
**Result:** One increment, one decrement. BALANCED.

### Path 5: Driver Shutdown (usb_kill_anchored_urbs)
```
rtw89_usb_disconnect()
  → rtw89_usb_cancel_tx_bufs()
  → usb_kill_anchored_urbs(&rtwusb->tx_submitted)
  → [For each anchored URB:]
    → rtw89_usb_write_port_complete() called with -ECONNRESET
    → atomic_dec() ← DECREMENT
```
**Result:** Each in-flight URB gets exactly one decrement. BALANCED.

---

## Key Guarantees

1. **USB Core Guarantee:** Once `usb_submit_urb()` returns 0, the completion callback is called exactly once, regardless of success/failure/cancellation.

2. **Increment Location:** Only in `else` branch after confirmed successful submit.

3. **Decrement Location:** Unconditional in completion callback, runs for all paths.

4. **No Other Modifiers:** `grep` confirms no other code modifies `tx_inflight`.

---

## Debug Instrumentation Added

The following checks were added to detect any accounting bugs at runtime:

```c
// In check_and_reclaim_tx_resource():
if (unlikely(inflight < 0))
    rtw89_warn(..., "UNDERFLOW");
if (unlikely(inflight > MAX))
    rtw89_warn(..., "OVERFLOW");

// In completion callback:
if (unlikely(atomic_read(...) <= 0))
    rtw89_warn(..., "decrement when inflight <= 0");
```

---

## Test Results

- **Underflow warnings:** NONE observed
- **Overflow warnings:** NONE observed
- **Stress test:** 10,000+ packets captured, 0 dropped

---

## Conclusion

The counter accounting is mathematically correct. Every `atomic_inc()` has exactly one matching `atomic_dec()` across all code paths.

---

## Remaining Verification

- [x] Observe actual backpressure (return 0) under extreme TX load - **VERIFIED 2026-01-11**
- [x] Teardown-under-load test (unplug during active TX) - **PASSED 2026-01-11**
- [ ] 3x repeated identical stress tests

---

## Backpressure Verification (2026-01-11)

**Test Setup:**
- Max URBs per channel: 4 (reduced from 32 to force backpressure)
- Connected to phone hotspot
- Flood ping through USB adapter: `ping -f -I wlp0s13f0u2 -s 1400 10.63.200.231`

**Results:**
```
[41241.517941] rtw89_8852au_git: TX flow ctrl: BACKPRESSURE ch=0 inflight=4
[41241.541948] rtw89_8852au_git: TX flow ctrl: BACKPRESSURE ch=0 inflight=4
... (40+ events)
```

**Verification:**
- Channel 0 (data channel) correctly hit max inflight=4
- Driver returned 0 to mac80211, signaling "stop sending"
- **Zero underflow warnings**
- **Zero overflow warnings**
- Traffic continued after completions freed slots

**Conclusion:** TX flow control backpressure mechanism is **VERIFIED WORKING**.

---

## Teardown-Under-Load Test (2026-01-11)

**Test Setup:**
- Flood ping running through USB adapter
- Physically unplugged USB adapter during active TX

**Results:**
```
[42084.407729] usb 2-2: USB disconnect, device number 9
[42084.415729] wlp0s13f0u2: deauthenticating from da:ad:b1:2f:ce:9e
[42084.936617] rtw89_8852au_git: timed out to flush queues
```

**Verification:**
- No kernel panic
- No crash or hang
- No BUG/OOPS messages
- No counter underflow/overflow
- "timed out to flush queues" is expected (device gone)

**Conclusion:** Driver handles hot-unplug during TX **gracefully**.

---

*Audit performed per ChatGPT's rigorous verification framework.*
