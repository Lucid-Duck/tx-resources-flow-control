#!/bin/bash
# Pre-test validation script
# Run BEFORE every single test. No exceptions.

set -e

EXPECTED_BAND="${1:-any}"  # "2.4" or "5" or "any"
EXPECTED_DRIVER="${2:-any}"  # "patched" or "unpatched" or "any"

echo "=== PRE-TEST VALIDATION ==="
echo "Expected band: $EXPECTED_BAND"
echo "Expected driver: $EXPECTED_DRIVER"
echo ""

echo "=== 1. Verify D-Link interface exists ==="
if ! ip link show wlp0s13f0u4 &>/dev/null; then
    echo "FAIL: D-Link interface wlp0s13f0u4 missing"
    exit 1
fi
echo "OK: wlp0s13f0u4 exists"

echo ""
echo "=== 2. Verify correct driver loaded ==="
if ! lsmod | grep -q rtw89_8852au_git; then
    echo "FAIL: rtw89_8852au_git not loaded"
    exit 1
fi
echo "OK: rtw89_8852au_git loaded"

# Check if patched or unpatched by looking at loaded module path
LOADED_MODULE=$(modinfo -F filename rtw89_usb_git 2>/dev/null)
echo "Loaded module: $LOADED_MODULE"

echo ""
echo "=== 3. Verify D-Link is connected (not Alfa) ==="
CONNECTED_IFACE=$(ip route get 192.168.1.70 2>/dev/null | grep -oP 'dev \K\S+' || echo "unknown")
if [ "$CONNECTED_IFACE" != "wlp0s13f0u4" ]; then
    echo "FAIL: Traffic routing through $CONNECTED_IFACE, not D-Link"
    exit 1
fi
echo "OK: Routing through wlp0s13f0u4"

echo ""
echo "=== 4. Verify correct band ==="
CURRENT_FREQ=$(iw dev wlp0s13f0u4 link 2>/dev/null | grep freq | awk '{print $2}' | cut -d. -f1)
if [ -z "$CURRENT_FREQ" ]; then
    echo "FAIL: Cannot get current frequency"
    exit 1
fi
echo "Current frequency: $CURRENT_FREQ MHz"

if [ "$EXPECTED_BAND" = "2.4" ]; then
    if [ "$CURRENT_FREQ" -lt 2400 ] || [ "$CURRENT_FREQ" -gt 2500 ]; then
        echo "FAIL: Expected 2.4GHz but got $CURRENT_FREQ MHz"
        exit 1
    fi
    echo "OK: On 2.4GHz band"
elif [ "$EXPECTED_BAND" = "5" ]; then
    if [ "$CURRENT_FREQ" -lt 5000 ] || [ "$CURRENT_FREQ" -gt 6000 ]; then
        echo "FAIL: Expected 5GHz but got $CURRENT_FREQ MHz"
        exit 1
    fi
    echo "OK: On 5GHz band"
else
    if [ "$CURRENT_FREQ" -ge 2400 ] && [ "$CURRENT_FREQ" -le 2500 ]; then
        echo "INFO: On 2.4GHz band"
    elif [ "$CURRENT_FREQ" -ge 5000 ] && [ "$CURRENT_FREQ" -le 6000 ]; then
        echo "INFO: On 5GHz band"
    else
        echo "WARN: Unknown frequency $CURRENT_FREQ MHz"
    fi
fi

echo ""
echo "=== 5. Verify correct BSSID ==="
CURRENT_BSSID=$(iw dev wlp0s13f0u4 link 2>/dev/null | grep Connected | awk '{print $3}')
echo "Connected to BSSID: $CURRENT_BSSID"

echo ""
echo "=== 6. Verify iperf3 server reachable ==="
if ! ping -c 1 -W 2 -I wlp0s13f0u4 192.168.1.70 &>/dev/null; then
    echo "FAIL: Cannot reach iperf3 server at 192.168.1.70"
    exit 1
fi
echo "OK: iperf3 server reachable"

echo ""
echo "=== 7. Verify Alfa is NOT on test network ==="
ALFA_IP=$(ip addr show wlp0s13f0u2i3 2>/dev/null | grep -oP 'inet \K[\d.]+' || echo "none")
if [[ "$ALFA_IP" =~ ^192\.168\.1\. ]]; then
    echo "FAIL: Alfa is on test network ($ALFA_IP)"
    exit 1
fi
echo "OK: Alfa not on test network (IP: $ALFA_IP)"

echo ""
echo "=== 8. Record driver version ==="
modinfo rtw89_usb_git 2>/dev/null | grep -E "^(filename|vermagic)"

echo ""
echo "=========================================="
echo "=== ALL VALIDATION CHECKS PASSED ==="
echo "=========================================="
