IMAGE_PREFIX ?= isc-kea
TAG ?= latest
DOCKER ?= docker

.PHONY: build build-dhcp4 build-ddns test test-dhcp4 test-ddns shellcheck clean help

help:
	@echo "Targets:"
	@echo "  build        Build both container images"
	@echo "  build-dhcp4  Build kea-dhcp4 image"
	@echo "  build-ddns   Build kea-dhcp-ddns image"
	@echo "  test         Build and smoke-test both images"
	@echo "  shellcheck   Lint shell scripts"
	@echo "  clean        Remove local test images"

build: build-dhcp4 build-ddns

build-dhcp4:
	$(DOCKER) build -f Dockerfile.kea-dhcp4 -t $(IMAGE_PREFIX)/kea-dhcp4:$(TAG) .

build-ddns:
	$(DOCKER) build -f Dockerfile.kea-dhcp-ddns -t $(IMAGE_PREFIX)/kea-dhcp-ddns:$(TAG) .

test: test-dhcp4 test-ddns

test-dhcp4: build-dhcp4
	./tests/test-container.sh $(IMAGE_PREFIX)/kea-dhcp4:$(TAG) kea-dhcp4

test-ddns: build-ddns
	./tests/test-container.sh $(IMAGE_PREFIX)/kea-dhcp-ddns:$(TAG) kea-dhcp-ddns

shellcheck:
	shellcheck entrypoint.sh.kea-dhcp4 entrypoint.sh.kea-dhcp-ddns
	shellcheck build-latest.sh scripts/*.sh tests/*.sh

clean:
	-$(DOCKER) rmi $(IMAGE_PREFIX)/kea-dhcp4:$(TAG) $(IMAGE_PREFIX)/kea-dhcp-ddns:$(TAG)
