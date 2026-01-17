# ARM cross-compile environment for Raspberry Pi 3 kernel modules
# Target: Linux 6.1.21-v7+ (ARMv7)

FROM debian:bookworm

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies and ARM cross-compiler
RUN apt-get update && apt-get install -y \
    build-essential \
    bc \
    bison \
    flex \
    libssl-dev \
    libncurses-dev \
    git \
    wget \
    kmod \
    crossbuild-essential-armhf \
    && rm -rf /var/lib/apt/lists/*

# Set cross-compile environment variables
ENV ARCH=arm
ENV CROSS_COMPILE=arm-linux-gnueabihf-
ENV KERNEL=kernel7

# Working directory
WORKDIR /build

# Download Raspberry Pi kernel source (6.1.y branch for 6.1.21)
RUN git clone --depth 1 --branch rpi-6.1.y \
    https://github.com/raspberrypi/linux.git /build/linux

# Copy Pi's kernel config and prepare build
# We'll mount the actual config at runtime from the Pi
RUN cd /build/linux && \
    make bcm2709_defconfig && \
    make modules_prepare

# Create output directory
RUN mkdir -p /build/output

# Default command: show help
CMD ["echo", "Usage: docker run -v $(pwd)/patches:/patches -v $(pwd)/build:/build/output pi3-ble-boot make -C /build/linux M=/build/linux/drivers/bluetooth modules"]
