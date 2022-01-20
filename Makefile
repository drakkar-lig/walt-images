
# note: if changing alpine version, also change
# the kernel archive URL in rpi/Dockerfile to match
# the same linux kernel version for qemu arm nodes.
ALPINE_VERSION = 3.13.7

build.%:
	docker build --build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
			-f $*/Dockerfile \
			--tag=waltplatform/$*-alpine:latest .
	docker tag waltplatform/$*-alpine:latest \
				waltplatform/$*-alpine:$(ALPINE_VERSION)

build-all: build.pc-x86-64 build.pc-x86-32 build.rpi

publish.%:
	docker push waltplatform/$*-alpine:latest
	docker push waltplatform/$*-alpine:$(ALPINE_VERSION)

publish-all: publish.pc-x86-64 publish.pc-x86-32 publish.rpi

all: build-all
