# Instructions for Kali VM: Patching rtw89 USB Driver

These instructions will patch the morrownr/rtw89 driver with TX flow control fixes for reliable hcxdumptool operation.

---

## Prerequisites

- Kali Linux VM with morrownr/rtw89 driver installed
- RTL8832AU/RTL8852AU USB adapter (e.g., D-Link DWA-X1850)
- Git and build tools (`build-essential`, `linux-headers-$(uname -r)`)

---

## Step 1: Clone or Update the Driver Source

If you don't have the driver source:
```bash
cd ~
git clone https://github.com/morrownr/rtw89.git
cd rtw89
```

If you already have it:
```bash
cd ~/rtw89
git pull
```

---

## Step 2: Get the Patches

Option A - Clone the patch repo:
```bash
cd ~
git clone https://github.com/Lucid-Duck/tx-resources-flow-control.git
```

Option B - Download patches directly:
```bash
cd ~/rtw89
curl -O https://raw.githubusercontent.com/Lucid-Duck/tx-resources-flow-control/main/patches/0001-usb-implement-tx-flow-control.patch
curl -O https://raw.githubusercontent.com/Lucid-Duck/tx-resources-flow-control/main/patches/0002-usb-add-debug-instrumentation.patch
curl -O https://raw.githubusercontent.com/Lucid-Duck/tx-resources-flow-control/main/patches/0003-usb-fix-ch12-tracking-skip.patch
curl -O https://raw.githubusercontent.com/Lucid-Duck/tx-resources-flow-control/main/patches/0004-usb-fix-increment-race-condition.patch
curl -O https://raw.githubusercontent.com/Lucid-Duck/tx-resources-flow-control/main/patches/0005-usb-use-atomic_dec_return-for-underflow-detection.patch
```

---

## Step 3: Apply the Patches

```bash
cd ~/rtw89

# Apply patches in order
patch -p1 < ../tx-resources-flow-control/patches/0001-usb-implement-tx-flow-control.patch
patch -p1 < ../tx-resources-flow-control/patches/0002-usb-add-debug-instrumentation.patch
patch -p1 < ../tx-resources-flow-control/patches/0003-usb-fix-ch12-tracking-skip.patch
patch -p1 < ../tx-resources-flow-control/patches/0004-usb-fix-increment-race-condition.patch
patch -p1 < ../tx-resources-flow-control/patches/0005-usb-use-atomic_dec_return-for-underflow-detection.patch
```

If using Option B (patches in current dir):
```bash
patch -p1 < 0001-usb-implement-tx-flow-control.patch
patch -p1 < 0002-usb-add-debug-instrumentation.patch
patch -p1 < 0003-usb-fix-ch12-tracking-skip.patch
patch -p1 < 0004-usb-fix-increment-race-condition.patch
patch -p1 < 0005-usb-use-atomic_dec_return-for-underflow-detection.patch
```

**If patches fail**: The driver source may have changed. Check the reject files (`.rej`) and apply changes manually to `usb.c` and `usb.h`.

---

## Step 4: Rebuild the Driver

```bash
cd ~/rtw89

# Unload current driver if loaded
sudo rmmod rtw89_8852au 2>/dev/null
sudo rmmod rtw89_usb 2>/dev/null
sudo rmmod rtw89_core 2>/dev/null

# Clean and rebuild
make clean
make

# Install
sudo make install

# Reload
sudo modprobe rtw89_8852au
```

---

## Step 5: Verify the Driver Loaded

```bash
# Check module loaded
lsmod | grep rtw89

# Check interface exists
ip link show | grep wl

# Check dmesg for errors
sudo dmesg | tail -20 | grep rtw89
```

---

## Step 6: Test with hcxdumptool

```bash
# Find your interface name (e.g., wlan0 or wlp0s20f0u1)
IFACE=$(iw dev | grep Interface | awk '{print $2}')

# Put in monitor mode
sudo ip link set $IFACE down
sudo iw dev $IFACE set type monitor
sudo ip link set $IFACE up

# Run hcxdumptool (15 second test on 2.4GHz channels)
sudo timeout 15 hcxdumptool -i $IFACE -w /tmp/test.pcapng -c 1a,6a,11a

# Check results
echo "Packets captured:"
sudo hcxpcapngtool -o /tmp/test.hc22000 /tmp/test.pcapng 2>&1 | head -5
```

---

## Expected Results

**Before patch:**
- hcxdumptool reports "ERROR(s) during runtime (broken driver)"
- Low packet counts (4-70 packets)
- Dropped packets

**After patch:**
- Zero or minimal errors
- Higher packet counts (hundreds to thousands)
- Zero dropped packets
- dmesg shows no UNDERFLOW/OVERFLOW warnings

---

## Troubleshooting

### Patches won't apply
The upstream driver may have changed. Check:
```bash
# See what changed
git log --oneline -5

# Check usb.c for the TODO line
grep -n "return 42" usb.c
```

If `return 42` is no longer there, the upstream may have fixed it differently.

### Module won't load
```bash
# Check for errors
sudo dmesg | grep -i error | tail -10

# Make sure old module is removed
sudo rmmod rtw89_8852au rtw89_usb rtw89_core 2>/dev/null
sudo modprobe rtw89_8852au
```

### hcxdumptool still shows errors
Check dmesg for TX flow control messages:
```bash
sudo dmesg | grep -i "flow\|underflow\|overflow"
```

If you see UNDERFLOW warnings, the patches may not have applied correctly.

---

## Quick Verification Commands

```bash
# Confirm patch applied (should show tx_inflight)
grep -n "tx_inflight" usb.c usb.h

# Should see:
# usb.c: atomic_read(&rtwusb->tx_inflight
# usb.c: atomic_inc(&rtwusb->tx_inflight
# usb.c: atomic_dec_return(&rtwusb->tx_inflight
# usb.h: atomic_t tx_inflight[RTW89_TXCH_NUM]
```

---

*Good hunting.*
