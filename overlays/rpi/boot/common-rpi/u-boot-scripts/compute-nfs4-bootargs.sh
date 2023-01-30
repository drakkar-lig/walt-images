
# compute bootargs related to the network filesystem (nfs v4 here)
setenv nfs_root "${serverip}:/var/lib/walt/nodes/${ipaddr}/fs"
setenv nfs_opts "ro,nocto,acregmin=157680000,acregmax=157680000,acdirmin=157680000,acdirmax=157680000"
setenv fs_bootargs "root=/dev/nfs4 boot=netroot rootfstype=netroot nfsroot=${nfs_root},${nfs_opts}"
