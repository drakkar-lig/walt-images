FROM waltplatform/pc-x86-64-debian:latest

COPY overlays/featured /
RUN echo /local /var/lib/rancher none defaults,bind 0 0 > /etc/fstab
RUN apt update && apt install -y fuse-overlayfs policycoreutils curl uidmap
# install k3s
RUN curl -sfL https://get.k3s.io | \
    sed -e 's/\(systemctl daemon-reload\)/echo "(bypassed)" \1/g' | \
    sed -e 's/\(systemctl restart\)/echo "(bypassed)" \1/g' \
    > install.sh
RUN K3S_TOKEN="K3S_ON_WALT_TOKEN" K3S_URL="https://k3s-server.walt:6443" \
    sh -s - agent < install.sh
# Add comment on top of /etc/systemd/system/k3s-agent.service.env
RUN echo "# We assume the walt node running K3S server is named: k3s-server" \
            "\n$(cat /etc/systemd/system/k3s-agent.service.env)" > \
            /etc/systemd/system/k3s-agent.service.env
# Modify k3s service definition so that it really stops everything on exit
RUN echo "ExecStopPost=/usr/local/bin/k3s-killall.sh" >> \
            /etc/systemd/system/k3s-agent.service && \
    sed -i -e "s/systemctl stop/echo systemctl stop/" \
            /usr/local/bin/k3s-killall.sh
# disable the service when running in a container (e.g. in walt image shell),
# but allow it to run in a virtual node
RUN sed -i '/^Description=.*/i ConditionVirtualization=!container' \
    /etc/systemd/system/k3s-agent.service
# allow apt install to start services (on node, or in walt image shell)
RUN rm /usr/sbin/policy-rc.d
