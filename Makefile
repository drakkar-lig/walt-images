
# notes:
# * for image consistency the version of the default kernel package in the
#   repositories identified by ALPINE_VERSION and DEBIAN_VERSION should be
#   the same as KERNEL_VERSION (at least major and minor numbers).
ALPINE_VERSION = 3.13.7
DEBIAN_VERSION = bullseye
KERNEL_VERSION = 5.10.63
KERNEL_ARCHIVE = "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-${KERNEL_VERSION}.tar.xz"

COMMON_VARS = $(KERNEL_VERSION) $(KERNEL_ARCHIVE)

all: build-all

build.alpine.%:
	./build.sh alpine $(ALPINE_VERSION) $* $(COMMON_VARS)

build.debian.%:
	./build.sh debian $(DEBIAN_VERSION) $* $(COMMON_VARS)

b.%:
	$(MAKE) build.$*.rpi build.$*.pc-x86-32 build.$*.pc-x86-64

build-all:
	$(MAKE) b.debian b.alpine

publish.alpine.%:
	docker push waltplatform/$*-alpine:latest
	docker push waltplatform/$*-alpine:$(ALPINE_VERSION)

# note: debian images are also the default image for each node model
publish.debian.%:
	docker push waltplatform/$*-debian:latest
	docker push waltplatform/$*-debian:$(DEBIAN_VERSION)
	docker tag waltplatform/$*-debian:latest waltplatform/$*-default:latest
	docker push waltplatform/$*-default:latest

p.%:
	$(MAKE) publish.$*.pc-x86-64 publish.$*.pc-x86-32 publish.$*.rpi

publish-all:
	$(MAKE) p.alpine p.debian
