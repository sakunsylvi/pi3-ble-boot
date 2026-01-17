# pi3-ble-boot

Patching Linux btusb module to support BARROT Bluetooth 6.0 adapter on Raspberry Pi 3.

## Target Hardware

- **Pi**: pi3.local (Raspberry Pi 3)
- **Kernel**: 6.1.21-v7+
- **BLE Dongle**: BARROT Bluetooth 6.0 (33fa:0012)

## Project Structure

```
pi3-ble-boot/
├── README.md          # Full documentation of the problem
├── CLAUDE.md          # This file
├── Dockerfile         # ARM cross-compile environment
├── docs/              # Investigation findings and decision log
├── patches/           # Kernel source patches
│   └── 0001-btusb-add-barrot-br8554-support.patch
├── scripts/           # Build and deploy scripts
│   ├── build.sh       # Build patched module via Docker
│   └── deploy.sh      # Deploy to Pi via SSH
└── build/             # Compiled output (gitignored)
```

## The Patch

`patches/0001-btusb-add-barrot-br8554-support.patch` adds:

1. **BTUSB_BARROT** quirk flag (BIT 28)
2. Device IDs: 33fa:0010, 33fa:0012, 33fa:0013
3. **btusb_setup_barrot()** function with quirks:
   - HCI_QUIRK_BROKEN_STORED_LINK_KEY
   - HCI_QUIRK_BROKEN_ERR_DATA_REPORTING
   - HCI_QUIRK_BROKEN_LOCAL_COMMANDS
   - Clear RESET_ON_CLOSE, SIMULTANEOUS_DISCOVERY

## Workflow

1. Docker builds ARM cross-compile environment
2. Fetch kernel source matching Pi's version (6.1.21)
3. Apply patch to btusb or hci_sync.c
4. Compile btusb.ko module only
5. Deploy via: `scp build/btusb.ko pi:/tmp/ && ssh pi "sudo cp /tmp/btusb.ko /lib/modules/$(uname -r)/kernel/drivers/bluetooth/ && sudo depmod -a"`
6. Test: `ssh pi "sudo modprobe -r btusb && sudo modprobe btusb && sudo hciconfig hci1 up"`

## SSH Access

```bash
ssh pi                 # alias for pi3.local
```

## Fallback Recovery

If module bricks boot:
1. Remove SD card from Pi
2. Insert into airi.local (has SD reader)
3. Mount ext4 partition
4. Restore original btusb.ko from backup
