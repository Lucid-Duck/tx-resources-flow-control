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

- [ ] Observe actual backpressure (return 0) under extreme TX load
- [ ] Teardown-under-load test (unplug during active TX)
- [ ] 3x repeated identical stress tests

---

*Audit performed per ChatGPT's rigorous verification framework.*
