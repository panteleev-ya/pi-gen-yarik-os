# yarikOS build orchestration.
#
#   make app     cross-compile custom apps (Bazel, in ./apps) -> dist/
#   make image   build the Pi image with pi-gen (embeds dist/) -> deploy/
#   make         both, in order
#
# `app` and `image` are decoupled so you can iterate on either independently;
# `make image` will hard-fail early if dist/ artifacts are missing.

.PHONY: all app image clean help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

all: app image ## Build the apps, then the image

app: ## Cross-compile custom apps with Bazel into dist/
	./scripts/build-apps.sh

image: ## Build the Raspberry Pi OS image (run `make app` first)
	./build-docker.sh

clean: ## Remove build artifacts and Bazel symlinks (keeps caches)
	rm -rf dist apps/bazel-*
