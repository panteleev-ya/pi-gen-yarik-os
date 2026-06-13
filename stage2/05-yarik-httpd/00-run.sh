#!/bin/bash -e

# Bake in the yarik-os C++ HTTP server (source copied from ~/Projects/yarik-os).
#
# Instead of shipping a pre-built binary, we compile it natively inside the
# target rootfs using the build-essential/g++ toolchain that Raspberry Pi OS
# Lite already provides. That guarantees the binary matches the image's glibc
# and arch (arm64), with no host cross-toolchain needed. It is then exposed as
# a systemd service that starts on boot.

install -v -d "${ROOTFS_DIR}/usr/local/src/yarik-app"
install -v -m 644 files/main.cpp "${ROOTFS_DIR}/usr/local/src/yarik-app/main.cpp"
install -v -m 644 files/yarik-app.service "${ROOTFS_DIR}/etc/systemd/system/yarik-app.service"

on_chroot << 'EOF'
set -e
g++ -O2 -Wall -o /usr/local/bin/yarik-app /usr/local/src/yarik-app/main.cpp
strip /usr/local/bin/yarik-app
systemctl enable yarik-app.service
EOF
