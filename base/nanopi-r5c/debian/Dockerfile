# -- 1st stage: builder_A, run with host arch
FROM debian:bookworm as builder_A
ARG OS_TYPE
ARG OS_VERSION
ENV MODEL "r5c"
ENV KERNEL_FW_URL "https://mirrors.edge.kernel.org/pub/linux/kernel/firmware/linux-firmware-20230210.tar.xz"
ENV RELEASE_URL "https://github.com/inindev/nanopi-r5/releases/download/v12.0.1"
ENV OS_MIRROR "https://deb.debian.org/debian/"
RUN mkdir /root/rootfs
WORKDIR /root
RUN apt update && apt install -y wget xz-utils debootstrap
RUN mkdir -p downloads rootfs/usr/lib/firmware && \
    wget -nv "$KERNEL_FW_URL" -P "downloads" && \
    lfw=$(ls downloads/linux-firmware*.tar.xz) && \
    lfwn=$(basename "$lfw") && \
    lfwbn="${lfwn%%.*}" && \
    tar -C "rootfs/usr/lib/firmware" --strip-components=1 --wildcards -xavf "$lfw" \
        "$lfwbn/rockchip" \
        "$lfwbn/rtl_bt" \
        "$lfwbn/rtl_nic" \
        "$lfwbn/rtlwifi" \
        "$lfwbn/rtw88" \
        "$lfwbn/rtw89" && \
    rm -rf downloads
RUN wget -nv "${RELEASE_URL}/rk3568-nanopi-${MODEL}.dtb" -P "rootfs/boot/" && \
    chmod 644 rootfs/boot/*.dtb
RUN debootstrap --foreign --variant=minbase --arch arm64 \
        ${OS_VERSION} "rootfs" ${OS_MIRROR}
COPY overlays/generic overlays/${OS_TYPE} overlays/nanopi-r5c \
     overlays/spec-nbfs overlays/walt-node rootfs/

## -- 2nd stage: finalize rootfs, run with arm64 arch transparently emulated by qemu
FROM --platform=linux/arm64/v8 scratch as rootfs_finalizer
COPY --from=builder_A /root/rootfs /
RUN /root/customize.sh nanopi-r5c
# specify which node models this image can handle
LABEL walt.node.models=nanopi-r5c
# set an entrypoint (handy when debugging)
ENTRYPOINT /bin/sh
