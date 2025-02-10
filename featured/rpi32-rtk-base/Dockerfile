FROM waltplatform/rpi32-debian:bookworm

COPY overlays/featured /
WORKDIR /root
# see installation steps at https://github.com/Stefal/rtkbase
RUN apt update && apt install -y sudo wget lsb-release
RUN wget https://raw.githubusercontent.com/Stefal/rtkbase/master/tools/install.sh -O install.sh && chmod +x install.sh
RUN ./install.sh --user root --dependencies
RUN ./install.sh --user root --rtkbase-release
# according to the source code of install.sh --rtklib:
RUN cd rtkbase/tools/bin/rtklib_*/armv7l && cp convbin rtkrcv str2str /usr/local/bin
RUN ./install.sh --user root --unit-files
RUN ./install.sh --user root --gpsd-chrony
# prepare a script which will be called by an ExecStartPre directive
# of rtkbase_web.service.
# * it will ensure settings and data are preserved accross reboots;
# * on first boot, this script will also configure the GPS receiver
#   (a part of the setup we cannot do right now when building the image)
# * it will run /persist/rpi32-rtk-base/on-bootup allowing the user
#   to automate other actions on bootup. The default version of this script
#   is given by "rtk-base-user-on-bootup".
ADD featured/rpi32-rtk-base/rtk-base-on-bootup /usr/local/bin/
ADD featured/rpi32-rtk-base/rtk-base-user-on-bootup /usr/local/bin/
RUN chmod +x /usr/local/bin/rtk-base-on-bootup \
             /usr/local/bin/rtk-base-user-on-bootup && \
    sed -i "/^ExecStart=.*/i ExecStartPre=\/usr\/local\/bin\/rtk-base-on-bootup" \
    /etc/systemd/system/rtkbase_web.service
# disable those services when virtualization is detected (e.g. in walt image shell)
RUN sed -i '/^Description=.*/i ConditionVirtualization=false' \
    /etc/systemd/system/rtkbase_web.service && \
    sed -i '/^Description=.*/i ConditionVirtualization=false' \
    /etc/systemd/system/gpsd.service
# allow apt install to start services (on node, or in walt image shell)
RUN rm /usr/sbin/policy-rc.d
