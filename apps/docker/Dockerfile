# Builder image for the custom apps: Bazelisk + the Debian aarch64 cross
# compiler that the Bazel toolchain (//toolchain) wraps.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        git \
        gcc-aarch64-linux-gnu \
        g++-aarch64-linux-gnu \
    && rm -rf /var/lib/apt/lists/*

# Bazelisk launches the exact Bazel pinned in apps/.bazelversion.
# TARGETARCH (amd64 / arm64) is set by BuildKit so the image is native to the
# build host — important on Apple Silicon, where an amd64 Bazel would be
# Rosetta-emulated and would then fail to run.
ARG BAZELISK_VERSION=1.20.0
ARG TARGETARCH
RUN wget -qO /usr/local/bin/bazelisk \
        "https://github.com/bazelbuild/bazelisk/releases/download/v${BAZELISK_VERSION}/bazelisk-linux-${TARGETARCH}" \
    && chmod +x /usr/local/bin/bazelisk \
    && ln -sf /usr/local/bin/bazelisk /usr/local/bin/bazel

WORKDIR /work
