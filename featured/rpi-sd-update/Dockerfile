FROM waltplatform/rpi-debian:latest

COPY overlays/featured /
COPY overlays/rpi-sd-update /
COPY --from=waltplatform/rpi-boot-builder \
     /opt/boot_files /opt/walt/rpi-sd
RUN systemctl enable rpi-sd-update && \
    apt update && \
    apt install -y gdisk fdisk
# allow apt install to start services (on node, or in walt image shell)
RUN rm /usr/sbin/policy-rc.d
