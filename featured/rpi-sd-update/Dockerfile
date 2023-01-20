FROM waltplatform/rpi-debian:latest

COPY overlays/rpi-sd-update /
COPY --from=waltplatform/rpi-boot-builder \
     /opt/boot_files /opt/walt/rpi-sd
RUN systemctl enable rpi-sd-update && \
    apt update && \
    apt install -y gdisk fdisk
