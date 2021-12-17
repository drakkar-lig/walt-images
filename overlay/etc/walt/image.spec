{
    # files that need to be updated by the server
    # when the image is mounted
    # -------------------------------------------
    "templates": [
        "/boot/common-ipxe/server-params.ipxe"
    ],
    # features that may be enabled if available
    # on server too
    # -----------------------------------------
    "features": {
        "nbfs": "/usr/bin/activate-nbfs.sh"
    }
}
