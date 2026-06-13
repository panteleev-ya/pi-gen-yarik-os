# yarikOS build orchestration.
#
# Build the repo into a flashable image with a single command:
#
#   make              compile apps/ -> dist/, then build the image -> deploy/
#   make app          only cross-compile the custom apps (Bazel) -> dist/
#   make image        only build the Pi image (builds apps first) -> deploy/
#   make CONTINUE=1   resume a previous/interrupted build (reuse pigen_work)
#
# `make image` depends on `app`, so the apps are always (re)built and staged
# into dist/ before the image. Bazel is incremental, so this is a no-op when the
# sources are unchanged. By default a leftover pigen_work container is removed
# for a clean build; CONTINUE=1 reuses it to resume. Running `./build-docker.sh`
# directly skips the app build and hard-fails in stage2/05-yarik-httpd if dist/
# is missing.

.PHONY: all app image clean help
.DEFAULT_GOAL := all

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

all: image ## Build the apps and then the image

app: ## Cross-compile custom apps with Bazel into dist/
	./scripts/build-apps.sh

image: app ## Build the Raspberry Pi OS image (builds the apps first)
	CONTINUE=$(CONTINUE) ./build-docker.sh

clean: ## Remove build artifacts and Bazel symlinks (keeps caches)
	rm -rf dist apps/bazel-*
