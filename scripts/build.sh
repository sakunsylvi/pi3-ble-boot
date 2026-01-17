#!/bin/bash
# Build patched btusb module for Raspberry Pi 3
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE_NAME="pi3-ble-boot"

cd "$PROJECT_DIR"

# Build Docker image if not exists
if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo "Building Docker image (this takes a while first time)..."
    docker build -t "$IMAGE_NAME" .
fi

# Run build
echo "Building btusb module..."
docker run --rm \
    -v "$PROJECT_DIR/patches:/patches:ro" \
    -v "$PROJECT_DIR/build:/build/output" \
    "$IMAGE_NAME" \
    bash -c '
        cd /build/linux

        # Apply patches if any exist
        if ls /patches/*.patch 1>/dev/null 2>&1; then
            echo "Applying patches..."
            for patch in /patches/*.patch; do
                echo "  Applying: $patch"
                patch -p1 < "$patch"
            done
        fi

        # Build only bluetooth modules
        echo "Compiling bluetooth modules..."
        make -j$(nproc) M=drivers/bluetooth modules

        # Copy output
        echo "Copying built modules..."
        cp drivers/bluetooth/*.ko /build/output/

        echo "Done! Modules in build/"
        ls -la /build/output/*.ko
    '

echo ""
echo "Build complete. Output in: $PROJECT_DIR/build/"
ls -la "$PROJECT_DIR/build/"
