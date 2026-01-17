# Findings & Decision Log

## 2026-01-17: Initial Investigation

### Discovery

Plugged BARROT Bluetooth 6.0 USB dongle into Raspberry Pi 3 (pi3.local).

**What we observed:**

```bash
$ lsusb
Bus 001 Device 009: ID 33fa:0012  BARROT Bluetooth 6.0 Adapter
```

Device detected at USB level. Good sign.

```bash
$ hciconfig -a
hci1: Type: Primary  Bus: USB
      BD Address: 04:7F:1E:00:AE:52  ACL MTU: 0:0  SCO MTU: 0:0
      DOWN
```

Bluetooth interface created. Driver loaded.

```bash
$ sudo hciconfig hci1 up
Can't init device hci1: Connection timed out (110)
```

**Failed.** Device won't initialize.

### Kernel Logs Analysis

```
Bluetooth: hci1: command 0x1005 tx timeout
Bluetooth: hci1: Opcode 0x1005 failed: -110
```

**Opcode 0x1005** = `HCI_OP_READ_BUFFER_SIZE` - reads HCI buffer sizes. The device times out on this fundamental initialization command.

### Troubleshooting Attempted

| Action | Result |
|--------|--------|
| Disable built-in BT (hci0 down) | No effect |
| USB unbind/rebind reset | Brief "INIT RUNNING" state, then timeout |
| Wait for init to complete | Still times out |

### Root Cause Research

Web search revealed this is a **known issue** with Barrot BR8554 chipset:

- Affects UGREEN CM748/CM749 (33fa:0010)
- Affects BARROT 6.0 (33fa:0012, 33fa:0013)
- Same chipset family, same bug
- Works on Windows (driver auto-downloads)
- No official Linux driver from Barrot
- No kernel maintainer interest in obscure Chinese chips

**The bug:** Device times out or responds incorrectly when Linux sends `Read_Local_Extended_Features` HCI command during initialization.

### Solution Options Evaluated

| Option | Effort | Risk | Chosen? |
|--------|--------|------|---------|
| 1. Recompile full kernel | 4-8 hours on Pi | High (can brick) | No |
| 2. Patch btusb module only (DKMS) | ~10 min compile | Low | **Yes** |
| 3. Wait for upstream fix | Forever | None | No |
| 4. Buy different dongle | 10-15 EUR | None | Backup plan |
| 5. Use built-in Pi BT | Free | None | Current workaround |

### Why Option 2 (DKMS Module Patch)

**Rejected Option 1 (full kernel):**
- Pi 3 has slow single-core ARM CPU
- 4-8 hours compile time
- Must redo on every kernel update
- Higher risk of unbootable system

**Rejected Option 3 (wait for upstream):**
- Barrot is obscure Chinese manufacturer
- No Linux community presence
- No kernel maintainer incentive
- Realistically will never happen

**Chose Option 2 because:**
- Only need to compile single .ko file (~10 min)
- DKMS auto-rebuilds on kernel updates
- Lower risk: bad module = no BT, but system boots
- Can cross-compile on faster Mac hardware

### Build Environment Decision

**Question:** Compile on Pi or cross-compile on Mac?

| Approach | Pros | Cons |
|----------|------|------|
| Compile on Pi | Native, no setup | Slow (ARM), needs headers |
| Cross-compile on Mac | Fast (Apple Silicon) | Needs Docker/toolchain |
| SD card + airi.local | Direct file access | Needs ext4 driver, card shuffling |

**Decision:** Cross-compile on Mac using Docker

**Reasoning:**
- Mac is much faster than Pi 3
- Docker can emulate ARM natively on Apple Silicon
- No need to install kernel headers on Pi
- Deploy via SSH (simpler than SD card swapping)

### Deployment Strategy

**Primary:** SSH direct deployment
```
Mac (build) → scp → Pi:/tmp/btusb.ko → sudo cp to /lib/modules/
```

**Fallback:** SD card via airi.local
- Only if SSH deploy bricks the system
- airi.local has SD card reader
- Can mount ext4 and restore original module

### USB ID Clarification

Research articles mention `33fa:0010` but our device is `33fa:0012`.

**Meaning:**
- `33fa` = Vendor ID (Barrot Technology Co., Ltd)
- `0010`, `0012`, `0013` = Product variants (antenna, reseller, casing)

Same chipset (BR8554), same bug. Patch must include all known product IDs:

```c
if (id_vendor == 0x33fa &&
    (id_product == 0x0010 || id_product == 0x0012 || id_product == 0x0013))
```

### Project Setup

Created dedicated project at `~/usr/code/pi3-ble-boot/` because:
- Separates kernel work from temperature monitoring project
- Clean environment for Docker builds
- Easier to track git history of patches
- Can be reused for other Pi kernel module work

---

## 2026-01-17: Patch Development

### Kernel Source Analysis

Fetched `drivers/bluetooth/btusb.c` from raspberrypi/linux rpi-6.1.y branch.

**Key findings:**
- BTUSB_* quirk flags defined as BIT(0) through BIT(27)
- BIT(28) available for new BTUSB_BARROT flag
- USB device IDs in `blacklist_table[]` array
- Setup functions like `btusb_setup_csr()` handle quirky devices
- HCI_QUIRK_* flags control which HCI commands are skipped

### Patch Strategy

Chose to patch **btusb.c only** (not hci_sync.c) because:
- Contained within Bluetooth driver (no core changes)
- Follows existing pattern for broken devices (CSR fakes, Actions Semi)
- Can be built as standalone module
- Lower risk than modifying core Bluetooth stack

### Patch Implementation

Created `patches/0001-btusb-add-barrot-br8554-support.patch`:

1. **New quirk flag:** `BTUSB_BARROT` = BIT(28)

2. **Device IDs added to blacklist_table[]:**
   ```c
   { USB_DEVICE(0x33fa, 0x0010), .driver_info = BTUSB_BARROT },
   { USB_DEVICE(0x33fa, 0x0012), .driver_info = BTUSB_BARROT },
   { USB_DEVICE(0x33fa, 0x0013), .driver_info = BTUSB_BARROT },
   ```

3. **Setup function:** `btusb_setup_barrot()` applies quirks:
   - `HCI_QUIRK_BROKEN_STORED_LINK_KEY` - skip link key ops
   - `HCI_QUIRK_BROKEN_ERR_DATA_REPORTING` - skip error reporting
   - `HCI_QUIRK_BROKEN_LOCAL_COMMANDS` - skip local commands read
   - Clear `HCI_QUIRK_RESET_ON_CLOSE` - don't reset on disconnect
   - Clear `HCI_QUIRK_SIMULTANEOUS_DISCOVERY` - no simultaneous scan

4. **Probe function:** Sets up handler when Barrot device detected

### Open Questions Resolved

- [x] Is the patch needed in btusb.c or hci_sync.c? → **btusb.c** (USB driver level)
- [x] Should we patch at USB quirk level or HCI command level? → **USB quirk level** (BTUSB_BARROT flag)
- [x] Do we need full kernel headers or just Bluetooth subsystem? → **Full headers** (for module build)

### Next Steps

1. [x] Build Docker image with cross-compile toolchain
2. [x] Apply patch and compile btusb.ko
3. [x] Backup original btusb.ko on Pi
4. [x] Deploy patched module via SSH
5. [x] Test: `sudo hciconfig hci1 up`
6. [x] If fails, iterate on quirk combinations

---

## 2026-01-18: Build and Test Iterations

### Docker Cross-Compile Attempt

Built Docker container with ARM cross-compile toolchain. Successfully compiled btusb.ko.

**Problem:** Module failed to load with "disagrees about version of symbol" error.

```
btusb: disagrees about version of symbol btintel_bootup
```

**Root cause:** Docker-built module used kernel 6.1.y headers (latest), but Pi runs 6.1.21-v7+ #1642 (April 2023).

**Decision:** Abandoned Docker cross-compile. Build directly on Pi with matching headers.

### Native Pi Build

Installed kernel headers on Pi:
```bash
sudo apt-get install raspberrypi-kernel-headers
```

Verified Module.symvers exists at `/lib/modules/6.1.21-v7+/build/Module.symvers`.

**Build process:**
1. Fetched btusb.c from `raspberrypi/linux` tag `1.20230405` (matches kernel build date)
2. Applied patch manually using sed
3. Compiled with local kernel headers
4. Deployed to Pi

**Result:** Module loaded successfully! Quirks applied:
```
Bluetooth: hci1: Barrot: Initializing BR8554 adapter (product=0x0012, bcdDevice=0x8891)
Bluetooth: hci1: Barrot: Quirks applied for BR8554 chipset
Bluetooth: hci1: HCI Read Local Supported Commands not supported
Bluetooth: hci1: HCI Delete Stored Link Key command is advertised, but not supported.
Bluetooth: hci1: HCI Read Default Erroneous Data Reporting command is advertised, but not supported.
```

**But still failed:** `command 0x1005 tx timeout` (READ_BUFFER_SIZE)

### The Real Problem

The HCI quirks we set skip **optional** commands:
- STORED_LINK_KEY - skipped
- ERR_DATA_REPORTING - skipped
- LOCAL_COMMANDS - skipped

But `READ_BUFFER_SIZE` (0x1005) is **mandatory**. No HCI_QUIRK exists to skip it.

The device simply doesn't respond to this fundamental HCI command. Without buffer sizes, the stack can't function.

### Quirks Attempted

| Quirk | Effect |
|-------|--------|
| HCI_QUIRK_BROKEN_STORED_LINK_KEY | Skipped - working |
| HCI_QUIRK_BROKEN_ERR_DATA_REPORTING | Skipped - working |
| HCI_QUIRK_BROKEN_LOCAL_COMMANDS | Skipped - working |
| HCI_QUIRK_BROKEN_FILTER_CLEAR_ALL | Skipped - working |
| HCI_QUIRK_FIXUP_BUFFER_SIZE | Pre-set values, but command still sent |
| HCI_QUIRK_RAW_DEVICE | Tried, no effect on READ_BUFFER_SIZE |
| Pre-set hdev->acl_mtu/sco_mtu | Values used but command still times out |

### Research: iifx.dev Article

Found [workaround documentation](https://iifx.dev/en/articles/460057614/workaround-for-barrot-br8554-chipset-issue-conditional-hci-command-skip-in-linux):

> The fix involves modifying `net/bluetooth/hci_sync.c` to check the device's VID/PID before sending the `Read_Local_Extended_Features` command.

**Key insight:** The fix must be in `hci_sync.c` (core Bluetooth stack), not `btusb.c` (USB driver).

### hci_sync.c Patch Attempt

Modified `hci_read_buffer_size_sync()` in `hci_sync.c`:

```c
static int hci_read_buffer_size_sync(struct hci_dev *hdev)
{
    /* Skip for Barrot BR8554 - device times out on this command */
    if (hdev->manufacturer == 0x33fa) {
        bt_dev_info(hdev, "Barrot: Skipping READ_BUFFER_SIZE");
        return 0;
    }
    return __hci_cmd_sync_status(hdev, HCI_OP_READ_BUFFER_SIZE,
                                 0, NULL, HCI_CMD_TIMEOUT);
}
```

Built `bluetooth.ko` from source. Deployed.

**Problem:** Symbol version mismatch broke the entire Bluetooth stack.

```
btbcm: disagrees about version of symbol __hci_cmd_sync
btbcm: Unknown symbol __hci_cmd_sync (err -22)
```

**Why:** Our patched `bluetooth.ko` has different symbol versions than the pre-built `btbcm.ko`, `btintel.ko`, `btrtl.ko` modules that ship with the kernel.

### Current Status

**What works:**
- btusb.ko patch loads and detects Barrot device
- Quirks for optional HCI commands work correctly
- Pre-set buffer sizes are used (ACL MTU: 1021:8, SCO MTU: 64:1)
- BD Address and Features are read from device

**What doesn't work:**
- Device still times out on READ_BUFFER_SIZE (0x1005)
- Interface cannot be brought up
- hci_sync.c patch causes symbol version hell

### Options Going Forward

| Option | Complexity | Success Chance |
|--------|------------|----------------|
| 1. Build ALL bluetooth modules from source | High | Medium |
| 2. Use DKMS with proper symbol handling | Medium | Unknown |
| 3. Submit kernel patch upstream (wait years) | Low effort | Very low |
| 4. Give up on this dongle, use different hardware | Zero | 100% |
| 5. Use Pi built-in BT + this dongle as paperweight | Zero | Already working |

### Technical Deep Dive: Why READ_BUFFER_SIZE?

The HCI initialization sequence:

1. `hci_reset_sync()` - Reset adapter
2. `hci_read_local_version_sync()` - Get firmware version
3. `hci_read_bd_addr_sync()` - Get Bluetooth address
4. **`hci_read_buffer_size_sync()` - Get ACL/SCO MTU sizes**
5. `hci_read_local_features_sync()` - Get supported features
6. ... more init commands ...

The Barrot device responds to steps 1-3 and 5, but completely ignores step 4. Without buffer sizes, the kernel doesn't know how large packets can be, so it refuses to activate the interface.

The device probably has a minimal firmware that implements just enough HCI for basic Windows operation but skips "optional" commands that Linux considers mandatory.

### References

- [GitHub: UGREEN Bluetooth troubleshooting notes](https://github.com/aamnah/notes/blob/main/sysadmin/troubleshoot-ugreen-bluetooth-5.4-ubuntu-linux.md)
- [Home Assistant: Operating System issue #3703](https://github.com/home-assistant/operating-system/issues/3703)
- [iifx.dev: Barrot BR8554 workaround article](https://iifx.dev/en/articles/460057614/workaround-for-barrot-br8554-chipset-issue-conditional-hci-command-skip-in-linux)
