# yarikOS build orchestration.
#
#   make app     cross-compile custom apps (Bazel, in ./apps) -> dist/
#   make image   build the Pi image with pi-gen (embeds dist/) -> deploy/
#   make         both, in order
#
# `make image` depends on `app`, so the apps are always (re)built and staged
# into dist/ before the image. Bazel is incremental, so this is a no-op when the
# sources are unchanged. Running `./build-docker.sh` directly skips this and will
# hard-fail in stage2/05-yarik-httpd if dist/ is missing.

.PHONY: all app image clean help
.DEFAULT_GOAL := all

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

all: image ## Build the apps and then the image

app: ## Cross-compile custom apps with Bazel into dist/
	./scripts/build-apps.sh

image: app ## Build the Raspberry Pi OS image (builds the apps first)
	./build-docker.sh

clean: ## Remove build artifacts and Bazel symlinks (keeps caches)
	rm -rf dist apps/bazel-*
