# TX Resource Flow Control

**Project:** Implementing proper TX resource tracking for the rtw89 USB WiFi driver
**Status:** Research & Planning Phase
**Created:** 2026-01-11

---

## The Problem

The rtw89 USB driver has a placeholder that lies to mac80211:

```c
return 42; /* TODO some kind of calculation? */
```

This causes:
- USB subsystem overwhelmed with packets
- hcxdumptool errors ("broken driver")
- Poor packet injection performance
- Low capture rates in monitor mode

## The Goal

Implement proper per-channel URB tracking so the driver can signal backpressure to mac80211 when TX resources are exhausted.

---

## Documentation

| File | Purpose |
|------|---------|
| [RESEARCH.md](RESEARCH.md) | Compiled research, references, prior art |
| [TECHNICAL-ASSESSMENT.md](TECHNICAL-ASSESSMENT.md) | Original problem statement and all three issues |
| [ANALYSIS-SESSION-1.md](ANALYSIS-SESSION-1.md) | Code analysis and proposed solution |

## Code

| Directory | Contents |
|-----------|----------|
| `rtw89/` | Cloned morrownr/rtw89 for development |

---

## Quick Context for New AI Sessions

1. **Hardware:** D-Link DWA-X1850 (RTL8832AU, WiFi 6)
2. **Driver:** rtw89 (morrownr out-of-tree, targets mainline)
3. **Issue:** `usb.c:166-173` returns hardcoded `42` instead of actual resource count
4. **Solution:** Add `atomic_t tx_inflight[RTW89_TXCH_NUM]` tracking
5. **Testing:** Fedora host, Kali VM, hcxdumptool

Read [RESEARCH.md](RESEARCH.md) for full context.

---

## Session Log

| Date | Summary |
|------|---------|
| 2026-01-11 | Project created, cloned rtw89, analyzed USB TX path, compiled research |

---

## Test Environment

- **Fedora 43 Host** (kernel 6.18.3) — Primary development
- **Kali Linux VM** — Packet injection testing
- **Windows 11 VM** — Comparative testing
- **Android Galaxy S22** — Additional perspective

## Related Repos

- [morrownr/rtw89](https://github.com/morrownr/rtw89) — Development target
- [Lucid-Duck/tx-resources-flow-control](https://github.com/Lucid-Duck/tx-resources-flow-control) — This project

---

## Project Philosophy

**Work in silence. Arrive with solutions.**

This project operates independently until we have:
- Working, tested implementations
- Comprehensive documentation
- Proven results

Only then do we engage with upstream maintainers. The goal is twofold:
1. Contribute meaningful fixes to the Linux WiFi ecosystem
2. Demonstrate what focused AI+human collaboration can achieve

No RFCs. No "what do you think?" No permission-seeking. Just results.
