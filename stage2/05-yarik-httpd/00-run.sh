#!/bin/bash -e

# Embed the yarik-os HTTP server into the image.
#
# The binary is built separately by Bazel (see ../../apps and `make app`), which
# cross-compiles a static aarch64 binary into ./dist. This stage only *consumes*
# that artifact — no source code or compiler toolchain lives in the image layers.

APP_BIN="${BASE_DIR}/dist/yarik-app"

if [ ! -f "${APP_BIN}" ]; then
	echo "ERROR: ${APP_BIN} is missing." >&2
	echo "Build the custom apps first:  make app   (or ./scripts/build-apps.sh)" >&2
	exit 1
fi

install -v -D -m 0755 "${APP_BIN}" "${ROOTFS_DIR}/usr/local/bin/yarik-app"
install -v -m 644 files/yarik-app.service "${ROOTFS_DIR}/etc/systemd/system/yarik-app.service"

on_chroot << EOF
systemctl enable yarik-app.service
EOF
