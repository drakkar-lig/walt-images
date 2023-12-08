FROM waltplatform/pc-x86-64-debian:latest

RUN echo /local /var/lib/rancher none defaults,bind 0 0 > /etc/fstab
RUN apt update && apt install -y fuse-overlayfs policycoreutils curl uidmap
# install k3s
RUN curl -sfL https://get.k3s.io | \
    sed -e 's/\(systemctl daemon-reload\)/echo "(bypassed)" \1/g' | \
    sed -e 's/\(systemctl restart\)/echo "(bypassed)" \1/g' \
    > install.sh
RUN K3S_TOKEN="K3S_ON_WALT_TOKEN" sh -s - server < install.sh && rm install.sh
# Modify k3s service definition so that it really stops everything on exit
RUN echo "ExecStopPost=/usr/local/bin/k3s-killall.sh" >> \
            /etc/systemd/system/k3s.service && \
    sed -i -e "s/systemctl stop/echo systemctl stop/" \
            /usr/local/bin/k3s-killall.sh
