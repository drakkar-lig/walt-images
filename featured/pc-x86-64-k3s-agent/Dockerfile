FROM waltplatform/pc-x86-64-debian:latest

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
