# Extended Verification Campaign

**Date:** 2026-01-12 (Tomorrow)
**Goal:** Eliminate all doubt through exhaustive testing

---

## Tests to Run

### 1. Stress Loop (100 iterations)
- [ ] 10-second flood ping per iteration
- [ ] Automated script, no human intervention
- [ ] Track total warnings across all 100 runs
- [ ] **Pass criteria:** ZERO warnings in 100 runs

```bash
for i in {1..100}; do
    echo "=== Run $i/100 ==="
    timeout 10s sudo ping -f -I wlp0s13f0u2 -s 1400 <GATEWAY>
    sudo dmesg | grep -c "UNDERFLOW\|OVERFLOW" || true
done
```

---

### 2. Software Teardown Loop (50 iterations)
- [ ] Start flood ping in background
- [ ] rmmod driver under active load
- [ ] modprobe driver back
- [ ] Reconnect to network
- [ ] Check dmesg for panics/oops/warnings
- [ ] **Pass criteria:** 50 clean teardowns, no kernel complaints

```bash
for i in {1..50}; do
    echo "=== Teardown $i/50 ==="
    sudo ping -f -I wlp0s13f0u2 <GATEWAY> &
    sleep 2
    sudo rmmod rtw89_8852au_git
    sudo modprobe rtw89_8852au_git
    # reconnect and verify
done
```

---

### 3. Multi-Channel Stress
- [ ] Generate traffic on multiple TX channels simultaneously
- [ ] Data frames (CH0) + management frames (CH12)
- [ ] Verify per-channel accounting stays correct
- [ ] **Pass criteria:** All channels balanced, no cross-contamination

---

### 4. Long Soak Test (30 minutes)
- [ ] Continuous flood ping for 30 minutes
- [ ] Monitor memory usage (check for leaks)
- [ ] Monitor counter values (check for drift)
- [ ] **Pass criteria:** Stable operation, counters return to 0 when idle

```bash
timeout 1800s sudo ping -f -I wlp0s13f0u2 -s 1400 <GATEWAY>
# Then verify: cat /sys/... or dmesg for final counter state
```

---

### 5. Varied Packet Sizes
- [ ] Test with 64, 512, 1024, 1400, 1472 byte packets
- [ ] Verify backpressure triggers correctly at all sizes
- [ ] **Pass criteria:** Consistent behavior regardless of packet size

---

### 6. Edge Cases
- [ ] Rapid connect/disconnect cycles (10x)
- [ ] Channel switching under load
- [ ] Monitor mode → managed mode transitions under load

---

## Success Criteria

**ALL of these must pass:**

| Test | Iterations | Pass Criteria |
|------|------------|---------------|
| Stress Loop | 100 | 0 warnings total |
| Teardown Loop | 50 | 0 panics/oops |
| Multi-Channel | 1 | All channels balanced |
| Soak Test | 30 min | No drift, no leaks |
| Packet Sizes | 5 sizes | Consistent behavior |
| Edge Cases | Various | No crashes |

---

## After Testing

- [ ] Update AUDIT-REPORT.md with extended test results
- [ ] Generate final consolidated patch for upstream
- [ ] Draft PR description for morrownr/rtw89
- [ ] Consider linux-wireless mailing list submission

---

*"Trust, but verify. Then verify again. Then automate the verification."*
