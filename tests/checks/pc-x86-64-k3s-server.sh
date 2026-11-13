# (appended to tests/checks/common.sh, see this file)
check "k3s service" "systemctl is-active k3s"
check "k3s node ready" "k3s kubectl get nodes --no-headers | grep -w Ready"
