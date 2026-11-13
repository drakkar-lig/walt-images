# Raspberry Pi boot files built by walt-node-boot (git submodule);
# build.py sets this argument (see get_rpi_boot_builder() there).
ARG RPI_BOOT_BUILDER
FROM ${RPI_BOOT_BUILDER} AS rpi-boot-files

FROM waltplatform/rpi32-debian:latest

COPY overlays/featured /
COPY overlays/rpi32-sd-update /
COPY --from=rpi-boot-files \
     /opt/boot_files /opt/walt/rpi-sd
RUN systemctl enable rpi-sd-update && \
    apt update && \
    apt install -y gdisk fdisk
# allow apt install to start services (on node, or in walt image shell)
RUN rm /usr/sbin/policy-rc.d
