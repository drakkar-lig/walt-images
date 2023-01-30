
setenv walt_init "/bin/walt-init"

# compute the full list of kernel command line args
setenv ip_param "ip=${ipaddr}:${serverip}:${gatewayip}:${netmask}:${hostname}::off"
setenv ip_conf "${ip_param} BOOTIF=01-${ethaddr}"
setenv other_bootargs "init=${walt_init} panic=15 net.ifnames=0 biosdevname=0"
setenv bootargs "$preserved_bootargs $fs_bootargs $ip_conf $other_bootargs"
