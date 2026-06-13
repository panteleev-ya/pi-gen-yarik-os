#!/usr/bin/env bash
#
# Cross-compile all custom apps (in ./apps) to static aarch64 binaries with
# Bazel, inside a builder container, and stage them in ./dist for pi-gen to
# embed. Bazel and download caches land in ./.cache so they persist between runs.
#
# Run this before building the image (`make app`, then `make image`).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

IMAGE="${APP_BUILDER_IMAGE:-yarik-app-builder}"
BAZEL_TARGET="${BAZEL_TARGET:-//yarik-httpd:yarik-app}"
DIST_NAME="${DIST_NAME:-yarik-app}"

echo ">> Building app builder image (${IMAGE})…"
docker build -t "${IMAGE}" apps/docker

# Allocate a TTY only when attached to one (CI has none). Avoid bash arrays for
# macOS's bundled bash 3.x.
DOCKER_TTY=""
[ -t 1 ] && DOCKER_TTY="-t"

echo ">> Cross-compiling ${BAZEL_TARGET} (static aarch64) with Bazel…"
# Run as the host user so the bind-mounted outputs keep correct ownership. HOME
# points inside the mount since this UID has no /etc/passwd entry.
#
# The build *and* the copy happen inside the container: Bazel's output symlinks
# use the container's /work path, so the artifact must be staged into dist/ from
# within the container (cquery resolves the exact output file).
BAZEL="bazelisk --output_user_root=/work/.cache/bazel"
docker run --rm ${DOCKER_TTY} \
	-v "${PWD}:/work" -w /work/apps \
	--user "$(id -u):$(id -g)" \
	-e USER=builder \
	-e HOME=/work/.cache/home \
	-e XDG_CACHE_HOME=/work/.cache \
	"${IMAGE}" \
	bash -euc "
		${BAZEL} build ${BAZEL_TARGET}
		out=\$(${BAZEL} cquery --output=files ${BAZEL_TARGET} 2>/dev/null | tail -n1)
		mkdir -p /work/dist
		install -m 0755 \"\$out\" /work/dist/${DIST_NAME}
	"

echo ">> Staged dist/${DIST_NAME}:"
file "dist/${DIST_NAME}"
