
# compute bootargs related to the network filesystem (nbfs here)
setenv nbfs_root "${serverip}:/var/lib/walt/nodes/${ipaddr}/fs"
setenv fs_bootargs "root=/dev/nbfs boot=netroot rootfstype=netroot nbfsroot=${nbfs_root}"
