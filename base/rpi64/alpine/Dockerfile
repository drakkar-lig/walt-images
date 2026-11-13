# arguments needed in FROM statements
ARG OS_TYPE
ARG OS_VERSION

# Alpine base
# -----------
# we use the official aarch64 alpine image. Its "linux-rpi" kernel
# supports models 3B+, 4B (it includes the BCMGENET ethernet driver)
# and 5B.
# The platform of this stage must be specified, otherwise docker looks
# for a variant of the image for the build host platform (e.g.,
# linux/amd64), and arm64v8/alpine has none. The target image retrieves
# the content of this stage ("COPY --from=alpine_base / /"), so this
# does not change the platform declared in the metadata of the final
# image (see "Image architecture" in README.md).
FROM --platform=linux/arm64 arm64v8/alpine:${OS_VERSION} as alpine_base

# Target image
# ------------
FROM --platform=linux/arm64 scratch
ARG OS_TYPE

# specify which node models this image can handle
LABEL walt.node.models=rpi-3-b-plus,rpi-4-b,rpi-5-b

# specify min walt server version needed
LABEL walt.server.minversion=5

# prepare and run customization
# note: like rpi64-debian, the firmware boots the kernel and initramfs
# directly, without u-boot (see overlays/rpi64-alpine/boot).
COPY --from=alpine_base / /
COPY overlays/generic overlays/${OS_TYPE} overlays/rpi \
     overlays/rpi64-${OS_TYPE} overlays/mount.nbfs.arm64 \
     overlays/spec-nbfs /
RUN nice /root/customize.sh rpi64

# set an entrypoint (handy when debugging)
ENTRYPOINT /bin/sh
