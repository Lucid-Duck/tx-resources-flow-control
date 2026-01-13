# rtw89 USB Driver Contribution Project - Technical Assessment

## Project Overview

The Linux kernel's rtw89 WiFi driver has incomplete USB support. Three specific functions in drivers/net/wireless/realtek/rtw89/usb.c are placeholders awaiting implementation. These exist in both mainline Linux and out-of-tree forks (morrownr/rtw89).

---

## Issue #1: TX Resource Flow Control

**File:** usb.c line 166-173
**Function:** `rtw89_usb_ops_check_and_reclaim_tx_resource()`

### Current Implementation:
```c
static u32 rtw89_usb_ops_check_and_reclaim_tx_resource(struct rtw89_dev *rtwdev, u8 txch)
{
    if (txch == RTW89_TXCH_CH12)
        return 1;
    return 42; /* TODO some kind of calculation? */
}
```

### What It Should Do:
- Return the number of available TX buffer slots for a given TX channel
- Prevent the mac80211 stack from overwhelming the USB subsystem with packets
- Reclaim completed URBs and update available slot count

### Reference Implementation (PCI version, pci.c:1256-1319):
- Tracks TX buffer descriptors (BD) and TX work descriptors (WD)
- Checks completion ring for finished transmissions
- Returns min(available_bd_count, available_wd_count)
- Triggers reclamation when resources run low

### What USB Implementation Would Require:
- Track submitted URBs per TX channel
- Track completed URBs via completion callbacks
- Implement counter for in-flight URBs
- Return (max_urbs_per_channel - in_flight_urbs)
- Possibly implement URB pooling for efficiency

### Skills Needed:
- Linux USB subsystem (URB lifecycle, usb_submit_urb, completion callbacks)
- Kernel memory management (atomic operations for counters)
- Understanding of mac80211 TX flow control
- Lock-free or spinlock-protected counter updates

**Estimated Complexity:** Medium
**Testing Required:** High-throughput TX scenarios, packet injection, stress testing

---

## Issue #2: Error Status Dumping

**File:** usb.c line 857-860
**Function:** `rtw89_usb_ops_dump_err_status()`

### Current Implementation:
```c
static void rtw89_usb_ops_dump_err_status(struct rtw89_dev *rtwdev)
{
    rtw89_warn(rtwdev, "%s TODO\n", __func__);
}
```

### What It Should Do:
- Read hardware debug/error registers when errors occur
- Print diagnostic information to kernel log
- Aid debugging of driver issues

### Reference Implementation (PCI version, pci.c:4461-4479):
```c
static void rtw89_pci_ops_dump_err_status(struct rtw89_dev *rtwdev)
{
    if (rtwdev->chip->chip_gen == RTW89_CHIP_BE)
        return;

    if (rtwdev->chip->chip_id == RTL8852C) {
        rtw89_info(rtwdev, "R_AX_DBG_ERR_FLAG=0x%08x\n",
                   rtw89_read32(rtwdev, R_AX_DBG_ERR_FLAG_V1));
        rtw89_info(rtwdev, "R_AX_LBC_WATCHDOG=0x%08x\n",
                   rtw89_read32(rtwdev, R_AX_LBC_WATCHDOG_V1));
    } else {
        rtw89_info(rtwdev, "R_AX_RPQ_RXBD_IDX=0x%08x\n",
                   rtw89_read32(rtwdev, R_AX_RPQ_RXBD_IDX));
        // ... more register dumps
    }
}
```

### What USB Implementation Would Require:
- Identify which debug registers are accessible via USB vendor requests
- Read USB-specific error status (possibly from atomic_read(&rtwusb->continual_io_error))
- Dump relevant chip registers via rtw89_read32()
- Handle chip-specific register variations (RTL8852A vs RTL8852C vs RTL8922A)

### Skills Needed:
- Reading Realtek chip datasheets/register maps
- USB control transfers for register access
- Kernel logging best practices

**Estimated Complexity:** Low-Medium
**Testing Required:** Trigger various error conditions, verify useful output

---

## Issue #3: RTL8922A Level-1 Recovery

**File:** usb.c line 818-855
**Function:** `rtw89_usb_ops_lv1_rcvy()`

### Current Implementation:
```c
case RTL8922A:
    return 0; /* TODO ? */
```

### What It Should Do:
- Perform USB TX/RX reset for error recovery without full device reset
- Step 1: Stop USB DMA/transfers
- Step 2: Restart USB DMA/transfers

### Reference (other chips in same function):
```c
case RTL8852A:
case RTL8852B:
    reg = R_AX_USB_WLAN0_1;
    mask = B_AX_USBRX_RST | B_AX_USBTX_RST;
    // write set then clear to reset
```

### What RTL8922A Implementation Would Require:
- Find correct reset register for RTL8922A (likely in reg.h as R_BE_* variant)
- Verify reset sequence from Realtek documentation or by examining BE-generation chip handling
- Test recovery from induced errors

### Skills Needed:
- Chip generation differences (AX vs BE series)
- Register map knowledge for RTL8922A
- USB device reset sequencing

**Estimated Complexity:** Low (if register is documented) to Medium (if reverse engineering needed)
**Testing Required:** Induce recoverable errors, verify recovery works

---

## Hardware Available for Testing

- D-Link DWA-X1850 (RTL8832AU / WiFi 6)
- Alfa AWUS036AXML (pending arrival)
- Kali Linux VM environment

## Existing Test Results Showing Impact

- hcxdumptool reported "8 ERROR(s) during runtime (mostly caused by a broken driver)"
- Low packet capture rates (4-70 packets vs expected thousands)
- continual_io_error counter in usb.c tracks these failures

## Code References

- Out-of-tree repo: https://github.com/morrownr/rtw89
- Mainline kernel: drivers/net/wireless/realtek/rtw89/usb.c
- PCI reference: drivers/net/wireless/realtek/rtw89/pci.c

## Submission Path

1. Develop and test against morrownr/rtw89 (easier iteration)
2. Submit patches to linux-wireless mailing list
3. Patches would go through Realtek maintainer (Ping-Ke Shih)

---

## Summary Table

| Issue             | Complexity | Impact                                | Dependencies       |
|-------------------|------------|---------------------------------------|--------------------|
| TX Flow Control   | Medium     | High (fixes packet loss, tool compat) | USB URB internals  |
| Error Dumping     | Low-Medium | Medium (debugging aid)                | Register knowledge |
| RTL8922A Recovery | Low-Medium | Medium (newest chip support)          | Register knowledge |

---

*The TX Flow Control issue is the meatiest and most impactful - it's likely the root cause of the hcxdumptool errors observed.*
