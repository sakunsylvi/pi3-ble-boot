#!/bin/bash
# Deploy btusb module to Raspberry Pi 3
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PI_HOST="pi"  # SSH alias for ex-keittio.local
MODULE="btusb.ko"

cd "$PROJECT_DIR"

if [[ ! -f "build/$MODULE" ]]; then
    echo "Error: build/$MODULE not found. Run ./scripts/build.sh first."
    exit 1
fi

# Get kernel version from Pi
KERNEL_VER=$(ssh "$PI_HOST" "uname -r")
MODULE_PATH="/lib/modules/$KERNEL_VER/kernel/drivers/bluetooth"

echo "Target: $PI_HOST"
echo "Kernel: $KERNEL_VER"
echo "Path:   $MODULE_PATH"
echo ""

# Backup original module
echo "Backing up original module..."
ssh "$PI_HOST" "sudo cp $MODULE_PATH/$MODULE $MODULE_PATH/$MODULE.backup 2>/dev/null || true"

# Copy new module
echo "Copying new module..."
scp "build/$MODULE" "$PI_HOST:/tmp/$MODULE"

# Install and reload
echo "Installing module..."
ssh "$PI_HOST" "sudo cp /tmp/$MODULE $MODULE_PATH/ && sudo depmod -a"

echo ""
echo "Module installed. To test:"
echo "  ssh $PI_HOST 'sudo modprobe -r btusb && sudo modprobe btusb && sudo hciconfig hci1 up && hciconfig'"
echo ""
echo "To restore original:"
echo "  ssh $PI_HOST 'sudo cp $MODULE_PATH/$MODULE.backup $MODULE_PATH/$MODULE && sudo depmod -a'"
