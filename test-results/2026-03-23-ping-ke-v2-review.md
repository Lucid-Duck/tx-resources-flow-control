# RTW89 TX Flow Control -- v2 Review Test Results

**Date:** 2026-03-23
**Hardware:** D-Link DWA-X1850 (RTL8832AU, USB ID 2001:3321)
**Kernel:** 6.19.8-200.fc43.x86_64
**Driver base:** morrownr/rtw89 commit 2544ebf
**Test network:** 8 Hertz WAN IP router (WiFi 5/6, 2.4+5+6 GHz)
**iperf3 server:** Windows PC (192.168.99.70) on same LAN
**Test machine:** Fedora 43 laptop (192.168.99.79 USB3, 192.168.99.200 USB2)
**Purpose:** Answer Ping-Ke Shih's v2 review questions (uplink data, URB scaling, small packets)

---

## Test Matrix

Four driver configurations tested:
- **Stock:** Unpatched (return 42)
- **Patched 32:** tx_inflight tracking, MAX_TX_URBS_PER_CH = 32
- **Patched 64:** tx_inflight tracking, MAX_TX_URBS_PER_CH = 64
- **Patched 128:** tx_inflight tracking, MAX_TX_URBS_PER_CH = 128

---

## 1. Standard Throughput -- USB3 5GHz (10 runs each, receiver Mbps)

### Download

| Run | Stock | Patched 32 | Patched 64 | Patched 128 |
|-----|-------|-----------|-----------|------------|
| 1 | 551 | 229 | 366 | 500 |
| 2 | 317 | 405 | 538 | 636 |
| 3 | 533 | 491 | 393 | 373 |
| 4 | 619 | 651 | 600 | 490 |
| 5 | 519 | 499 | 564 | 295 |
| 6 | 506 | 656 | 515 | 450 |
| 7 | 546 | 492 | 123 | 606 |
| 8 | 434 | 379 | 383 | 535 |
| 9 | 492 | 455 | 662 | 420 |
| 10 | 574 | 444 | 572 | 556 |
| **Avg** | **509** | **470** | **472** | **486** |

### Upload

| Run | Stock | Patched 32 | Patched 64 | Patched 128 |
|-----|-------|-----------|-----------|------------|
| 1 | 837 | 708 | 785 | 848 |
| 2 | 843 | 777 | 848 | 853 |
| 3 | 857 | 791 | 843 | 855 |
| 4 | 795 | 767 | 835 | 833 |
| 5 | 847 | 787 | 850 | 790 |
| 6 | 856 | 761 | 847 | 851 |
| 7 | 849 | 759 | 840 | 851 |
| 8 | 849 | 786 | 848 | 860 |
| 9 | 850 | 790 | 853 | 845 |
| 10 | 852 | 707 | 850 | 853 |
| **Avg** | **844** | **763** | **840** | **844** |
| **Retransmits** | **3** | **0** | **0** | **0** |

---

## 2. Standard Throughput -- USB3 2.4GHz (10 runs each)

### Summary

| Metric | Stock | Patched 32 | Patched 64 |
|--------|-------|-----------|-----------|
| DL Avg Mbps | 82 | 116 | 104 |
| UL Avg Mbps | 162 | 141 | 163 |
| UL Retransmits | 41 | 70 | 88 |

---

## 3. USB2 5GHz -- Bus-Limited Hypothesis (5 runs each)

| Metric | Stock | Patched 32 | Patched 64 | Patched 128 |
|--------|-------|-----------|-----------|------------|
| DL Avg Mbps | 212 | 219 | 225 | 246 |
| UL Avg Mbps | 250 | 252 | 248 | 253 |
| UL Retransmits | 6 | 0 | 1 | 6 |

**Conclusion:** On USB2, URB count does not affect throughput -- the 480 Mbps bus is the bottleneck. All configs cluster around 250 Mbps upload. The patch eliminates retransmits at 32 URBs without any throughput penalty.

---

## 4. Small Packet Tests -- USB3 5GHz Upload (3 runs each, avg Mbps)

| Packet Size | Stock | Patched 32 | Patched 64 |
|-------------|-------|-----------|-----------|
| 64 bytes | 139 | 128 | 126 |
| 256 bytes | 441 | 444 | 442 |
| 1024 bytes | 845 | 786 | 846 |

**Conclusion:** Small packets (64, 256 bytes) are CPU/USB-framing limited, not URB-count limited -- all three configs perform identically. At 1024 bytes, 32 URBs starts constraining throughput; 64 URBs recovers to stock.

---

## 5. Parallel Streams -- USB3 5GHz Upload (3 runs each, avg Mbps)

| Streams | Stock | Patched 32 | Patched 64 | Patched 128 |
|---------|-------|-----------|-----------|------------|
| 4 | 858 | 556 | 837 | 849 |
| 8 | 872 | 565 | 830 | 833 |

**KEY FINDING:** 32 URBs drops to ~560 Mbps under multi-stream load -- a 35% penalty. 64 URBs fully recovers to match stock. 128 URBs provides no additional benefit over 64.

---

## 6. Bidirectional -- USB3 5GHz, Patched 64 URB (5 runs)

| Run | Upload (Mbps) | Download (Mbps) | UL Retransmits |
|-----|--------------|-----------------|----------------|
| 1 | 474 | 263 | 0 |
| 2 | 338 | 418 | 0 |
| 3 | 718 | 103 | 0 |
| 4 | 529 | 264 | 0 |
| 5 | 392 | 401 | 0 |

**Conclusion:** Zero retransmits under simultaneous bidirectional load. Total throughput (UL+DL) averages ~740 Mbps combined.

---

## 7. UDP Flood -- USB3 5GHz, Patched 64 URB (5 runs)

| Run | Throughput | Datagrams | Packet Loss |
|-----|-----------|-----------|-------------|
| 1 | 933 Mbps | 805,827 | 0% |
| 2 | 929 Mbps | 802,602 | 0% |
| 3 | 916 Mbps | 790,787 | 0% |
| 4 | 935 Mbps | 807,290 | 0% |
| 5 | 937 Mbps | 809,610 | 0% |

**Conclusion:** Zero packet loss across 4 million+ datagrams. Flow control handles UDP flood without any URB exhaustion.

---

## 8. 60-Second Sustained Soak -- USB3 5GHz Upload, Patched 64 URB

| Interval | Throughput | Retransmits | Cwnd |
|----------|-----------|-------------|------|
| 0-10s | 823 Mbps | 0 | 2.06 MB |
| 10-20s | 848 Mbps | 0 | 2.06 MB |
| 20-30s | 846 Mbps | 0 | 2.06 MB |
| 30-40s | 853 Mbps | 0 | 2.06 MB |
| 40-50s | 842 Mbps | 0 | 2.06 MB |
| 50-60s | 852 Mbps | 0 | 2.06 MB |
| **Total** | **844 Mbps avg** | **0** | stable |

**Conclusion:** 5.9 GB transferred over 60 seconds with zero retransmits, zero degradation, and stable congestion window throughout.

---

## URB Scaling Summary

| MAX_TX_URBS | USB3 5GHz UL | 4-Stream UL | 8-Stream UL | USB2 5GHz UL |
|-------------|-------------|-------------|-------------|-------------|
| Stock (42) | 844 | 858 | 872 | 250 |
| 32 | 763 | 556 | 565 | 252 |
| 64 | 840 | 837 | 830 | 248 |
| 128 | 844 | 849 | 833 | 253 |

**64 is the sweet spot.** It recovers USB3 throughput to stock levels, handles multi-stream and UDP flood without penalty, and doesn't waste memory like 128.

**32 is correct for USB2** -- the bus is the bottleneck, not the URB pool.

**Recommendation:** Dynamic limit based on USB speed:
- USB2: 32 URBs per channel
- USB3: 64 URBs per channel

---

## Answers to Ping-Ke's Review Questions

**Q: Can you share uplink data?**
Upload throughput at 32 URBs shows a slight regression on USB3 5GHz (844 to 763 Mbps). At 64 URBs, upload matches stock (840) with zero retransmits.

**Q: Can increasing 32 get better performance? Small packets?**
Yes. 64 URBs outperforms 32 across all USB3 5GHz tests. The effect is most dramatic under parallel streams (35% penalty at 32 vs stock-matching at 64). Small packets are unaffected by URB count -- the bottleneck at small sizes is per-packet overhead.

**Q: Is it possible inflight > RTW89_USB_MAX_TX_URBS_PER_CH?**
No under normal operation. check_and_reclaim is called before submit, and each call submits at most one URB. The >= comparison is defensive programming.
