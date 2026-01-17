# BARROT Bluetooth 6.0 Adapter on Linux (Raspberry Pi 3)

## Device Information

| Property | Value |
|----------|-------|
| Product Name | BARROT Bluetooth 6.0 Adapter |
| USB Vendor ID | `33fa` |
| USB Product ID | `0012` |
| Chipset | Barrot BR8554 (likely) |
| bcdDevice | 88.91 |
| Linux interface | hci1 (when plugged in) |

## The Problem

When plugged into a Raspberry Pi 3 running Raspberry Pi OS, the adapter is detected but fails to initialize:

```
$ sudo hciconfig hci1 up
Can't init device hci1: Connection timed out (110)
```

Kernel logs show:
```
Bluetooth: hci1: command 0x1005 tx timeout
Bluetooth: hci1: Opcode 0x1005 failed: -110
```

**Opcode 0x1005** = `HCI_Read_Local_Version` - the most basic HCI command to query device info.

## Root Cause

The Barrot BR8554 chipset has a firmware/hardware bug where it either:
1. Times out on `Read_Local_Extended_Features` HCI command
2. Responds improperly during initialization

The Linux `btusb` driver misidentifies it as a "CSR clone" and applies workarounds that don't work for this chip.

## What Works

- **Windows 10/11**: Driver downloads automatically, works fine
- **Built-in Pi 3 Bluetooth (hci0)**: Works normally (uses BCM43430 chip)

## What Doesn't Work

- Any Linux distribution (tested on Raspberry Pi OS, Linux Mint, Arch, Deepin, Ubuntu)
- No official Linux driver exists from Barrot
- The `btusb` kernel module cannot initialize the device

## Affected Devices (Same Chipset Family)

| VID:PID | Product |
|---------|---------|
| 33fa:0010 | UGREEN CM748 (no antenna) |
| 33fa:0012 | BARROT Bluetooth 6.0 Adapter |
| 33fa:0013 | BARROT variant |

**USB ID Breakdown:**
- `33fa` = Vendor ID (BARROT / Barrot Technology Co., Ltd)
- `0010`, `0012`, `0013` = Product IDs (different SKUs/variants)

All share the same BR8554 chipset internally. Different product IDs represent variants (with/without antenna, different resellers like UGREEN, different casings). Same chipset = same Linux bug = same fix needed.

Existing kernel patches typically target `0x0010` only. For other variants, the patch must be extended:

```c
// Original patch:
if (id_vendor == 0x33fa && id_product == 0x0010)

// Extended for all variants:
if (id_vendor == 0x33fa && (id_product == 0x0010 || id_product == 0x0012 || id_product == 0x0013))
```

## Potential Fixes

### Option 1: Patch & Recompile Full Kernel

**What it means:**
- Download full Linux kernel source (~1GB)
- Apply patch to `net/bluetooth/hci_sync.c`
- Compile entire kernel on Pi 3 (4-8 hours on single-core ARM)
- Replace system kernel, risk breaking boot
- Must redo after every kernel update

**Verdict:** Masochism on a Pi 3. Not recommended.

### Option 2: Patch Just the btusb Module (DKMS)

**What it means:**
- Download only Bluetooth module source
- Patch and compile single `.ko` file (~5-10 min)
- Use DKMS (Dynamic Kernel Module Support) to auto-rebuild on kernel updates
- Less risky - bad module = no Bluetooth, but system still boots
- Still requires kernel headers installed

**Verdict:** Only practical DIY route if you must use this dongle.

### Option 3: Wait for Upstream Fix

**What it means:**
- Hope someone submits patch to Linux kernel maintainers
- Hope it gets accepted and merged
- Hope it trickles down to Raspberry Pi OS updates

**Reality:**
- Barrot is an obscure Chinese chip manufacturer
- No Linux developer community around these chips
- No incentive for kernel maintainers to add quirks for unknown hardware

**Verdict:** Wishful thinking. Realistically never happening.

---

### The Conceptual Kernel Patch

For reference, this is the patch that would fix the issue in `net/bluetooth/hci_sync.c`:

```c
// In hci_read_local_ext_features_sync()
if (hdev->bus == HCI_USB &&
    hdev->bus.id_vendor == 0x33fa &&
    (hdev->bus.id_product == 0x0010 ||
     hdev->bus.id_product == 0x0012 ||
     hdev->bus.id_product == 0x0013)) {
    bt_dev_warn(hdev, "Skipping Read_Local_Extended_Features for Barrot BR8554");
    return 0;
}
```

This skips the problematic HCI command that causes the timeout.

### Option 4: Use Different Hardware (Recommended)

Buy a USB BLE adapter with known Linux support:

| Chipset | Example Products | Linux Support |
|---------|------------------|---------------|
| Realtek RTL8761B | TP-Link UB500 | Good |
| Intel AX200/AX210 | Intel WiFi+BT cards | Excellent |
| CSR (genuine) | Older Bluetooth 4.0 dongles | Good |
| Broadcom BCM20702 | Various | Good |

**Verdict:** Best option. Spend 10-15 EUR, save hours of debugging.

### Option 5: Use Built-in Pi 3 Bluetooth

The Pi 3 has onboard Bluetooth (BCM43430A1) that works out of the box:

```bash
sudo hciconfig hci0 up
hciconfig hci0
# Shows: UP RUNNING
```

**Verdict:** Free, already works. Use this if range is sufficient.

## Commands Reference

```bash
# List USB devices
lsusb

# Check Bluetooth adapters
hciconfig -a

# Bring adapter up
sudo hciconfig hci0 up

# Check kernel messages
dmesg | grep -i bluetooth

# Reset USB device (unbind/bind)
echo '1-1.1.2' | sudo tee /sys/bus/usb/drivers/usb/unbind
sleep 2
echo '1-1.1.2' | sudo tee /sys/bus/usb/drivers/usb/bind
```

## Sources

- [iifx.dev - Barrot BR8554 Kernel Workaround](https://iifx.dev/en/articles/460057614/workaround-for-barrot-br8554-chipset-issue-conditional-hci-command-skip-in-linux)
- [Deepin Forum - Barrot chipset support](https://bbs.deepin.org/en/post/269703)
- [Linux Mint Forums - Bluetooth not working](https://forums.linuxmint.com/viewtopic.php?t=421944)
- [Home Assistant OS Issue #3703](https://github.com/home-assistant/operating-system/issues/3703)

## Conclusion

The BARROT Bluetooth 6.0 Adapter (33fa:0012) is **not compatible with Linux** without kernel modifications. For Raspberry Pi projects requiring BLE, use either the built-in Bluetooth or purchase a Linux-compatible USB adapter.

---
*Document created: 2026-01-17*
*Hardware tested: Raspberry Pi 3, pi3.local*
