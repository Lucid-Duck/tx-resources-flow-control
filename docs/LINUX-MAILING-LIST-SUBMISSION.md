# Submitting to linux-wireless Mailing List

This guide covers submitting the rtw89 USB TX flow control fix to the Linux kernel.

---

## Prerequisites

### 1. Install git-send-email

```bash
# Fedora
sudo dnf install git-email

# Ubuntu/Debian
sudo apt install git-email

# Arch
sudo pacman -S git
```

### 2. Configure git send-email

Add to `~/.gitconfig`:

```ini
[user]
    name = Lucid Duck
    email = lucid_duck@justthetip.ca

[sendemail]
    smtpEncryption = tls
    smtpServer = smtp.gmail.com
    smtpServerPort = 587
    smtpUser = lucid_duck@justthetip.ca
    # For Gmail: Create App Password at https://myaccount.google.com/apppasswords
    # Then either set smtpPass here or let git prompt you
```

**Gmail Users (Important):** As of January 2025, you MUST use an App Password, not your regular password. Create one at [Google App Passwords](https://myaccount.google.com/apppasswords).

---

## Submission Targets

| Target | Email | CC |
|--------|-------|-----|
| **Mailing List** | linux-wireless@vger.kernel.org | |
| **rtw89 Maintainer** | Ping-Ke Shih <pkshih@realtek.com> | Yes |
| **Realtek Team** | Larry.Finger@lwfinger.net | Optional |

---

## Step-by-Step Submission

### 1. Clone wireless-next tree (the correct base)

```bash
git clone git://git.kernel.org/pub/scm/linux/kernel/git/wireless/wireless-next.git
cd wireless-next
```

### 2. Create a branch and apply your changes

```bash
git checkout -b rtw89-usb-tx-flow-control
# Apply your changes to drivers/net/wireless/realtek/rtw89/usb.c and usb.h
```

### 3. Commit with proper format

```bash
git add drivers/net/wireless/realtek/rtw89/usb.c drivers/net/wireless/realtek/rtw89/usb.h
git commit -s  # -s adds Signed-off-by automatically
```

Use this commit message:

```
wifi: rtw89: usb: fix mac80211 TX flow control contract violation

rtw89_usb_ops_check_and_reclaim_tx_resource() returns a hardcoded
placeholder value (42) instead of actual TX resource availability.
This violates mac80211's flow control contract, preventing backpressure
and causing uncontrolled URB accumulation under sustained TX load.

Fix by adding per-channel atomic counters (tx_inflight[]) that track
in-flight URBs:

- Increment before usb_submit_urb() with rollback on failure
- Decrement in completion callback
- Return (MAX_URBS - inflight) to mac80211, or 0 when at capacity
- Exclude firmware command channel (CH12) from tracking

The pre-increment pattern prevents a race condition where the USB core
completes the URB (possibly on another CPU) before the submitting code
increments the counter.

Tested on D-Link DWA-X1850 (RTL8832AU) with:
- 100-iteration stress test (flood ping): PASS
- 50-iteration teardown test (rmmod/modprobe under load): PASS
- 10x hot-unplug during active TX: PASS
- 30-minute soak test: PASS, counters balanced at idle

Signed-off-by: Lucid Duck <lucid_duck@justthetip.ca>
```

### 4. Generate the patch

```bash
git format-patch -1 -o /tmp/patches/
```

### 5. Run checkpatch (optional but recommended)

```bash
./scripts/checkpatch.pl /tmp/patches/0001-wifi-rtw89-usb-fix-mac80211-TX-flow-control-contract-violation.patch
```

### 6. Send test email to yourself first

```bash
git send-email \
    --to="your-personal-email@example.com" \
    /tmp/patches/0001-*.patch
```

Review it in your email client to make sure formatting is correct.

### 7. Send to linux-wireless

```bash
git send-email \
    --to="linux-wireless@vger.kernel.org" \
    --cc="pkshih@realtek.com" \
    /tmp/patches/0001-*.patch
```

---

## Alternative: Using the Pre-Made Patch

If you want to use the patch file directly without rebasing on wireless-next:

```bash
git send-email \
    --to="linux-wireless@vger.kernel.org" \
    --cc="pkshih@realtek.com" \
    patches/0001-wifi-rtw89-usb-fix-mac80211-TX-flow-control.patch
```

---

## What to Expect

1. **Auto-reply:** You'll get an automated acknowledgment from vger.kernel.org
2. **Review:** Ping-Ke Shih or other maintainers may reply with feedback
3. **Possible requests:**
   - Code style changes
   - Additional testing on other hardware
   - Splitting into multiple patches
   - Rebasing on a different tree
4. **Acceptance:** If accepted, it goes into wireless-next → Linus' tree

---

## Common Issues

### "Patch does not apply"
Your patch may be based on an older version. Rebase on current wireless-next.

### "Missing Signed-off-by"
Add `-s` to your `git commit` command.

### "Wrong subject prefix"
Use `wifi: rtw89: usb:` not `rtw89/usb:` or `usb:`

### Gmail authentication failure
Create an App Password at https://myaccount.google.com/apppasswords

---

## References

- [Linux Wireless - Submitting Patches](https://wireless.docs.kernel.org/en/latest/en/developers/documentation/submittingpatches.html)
- [Kernel Submitting Patches Guide](https://www.kernel.org/doc/html/latest/process/submitting-patches.html)
- [git-send-email Documentation](https://git-scm.com/docs/git-send-email)

---

*Created: 2026-01-22*
