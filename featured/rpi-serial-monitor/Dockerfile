FROM waltplatform/rpi-debian:latest

COPY overlays/rpi-serial-monitor /
# remove console=.* kernel arguments
WORKDIR /boot/common-rpi
RUN sed -i -e \
    's/^setenv excluded_bootargs .*/setenv excluded_bootargs "root kgdboc console"/' \
    u-boot-scripts/analyse-given-bootargs.sh && \
    ./generate-boot-files.sh
# install rpi-serial-monitor service
RUN systemctl enable rpi-serial-monitor && \
    apt update && \
    apt install -y screen minicom
