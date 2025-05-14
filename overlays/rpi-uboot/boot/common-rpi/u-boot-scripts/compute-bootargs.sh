
setenv walt_init "/bin/walt-init"

# compute bootargs related to the network filesystem
if test "$fs_proto" = ""; then setenv fs_proto "nfs"; fi  # default is "nfs"
setenv fs_root "${serverip}:/var/lib/walt/nodes/${ipaddr}/fs"
setenv fs_bootargs "root=/dev/${fs_proto} boot=walt rootfstype=walt"
if test "$fs_proto" = "nbfs"
then
    setenv fs_bootargs "$fs_bootargs nbfsroot=${fs_root}"
else
    setenv nfs_ac_opts "acregmin=157680000,acregmax=157680000,acdirmin=157680000,acdirmax=157680000"
    if test "$fs_proto" = "nfs4"
    then
        setenv nfs_opts "ro,nocto,${nfs_ac_opts}"
    else    # fs_proto = "nfs"
        setenv nfs_opts "ro,vers=3,nolock,nocto,${nfs_ac_opts}"
    fi
    setenv fs_bootargs "$fs_bootargs nfsroot=${fs_root},${nfs_opts}"
fi

# compute the full list of kernel command line args
setenv ip_param "ip=${ipaddr}:${serverip}:${gatewayip}:${netmask}:${hostname}::off"
setenv ip_conf "${ip_param} BOOTIF=01-${ethaddr}"
setenv other_bootargs "init=${walt_init} panic=15 net.ifnames=0 biosdevname=0"
setenv bootargs "$preserved_bootargs $fs_bootargs $ip_conf $other_bootargs"
