# (appended to tests/checks/common.sh, see this file)
check "k3s-agent service" "systemctl is-active k3s-agent"
