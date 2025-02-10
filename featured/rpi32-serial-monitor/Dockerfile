FROM waltplatform/rpi32-debian:latest

COPY overlays/featured /
COPY overlays/rpi32-serial-monitor /
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
# allow apt install to start services (on node, or in walt image shell)
RUN rm /usr/sbin/policy-rc.d
