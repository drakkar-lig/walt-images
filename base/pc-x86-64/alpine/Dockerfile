# Target image
# ------------

ARG OS_TYPE
ARG OS_VERSION
FROM ${OS_TYPE}:${OS_VERSION}
ARG OS_TYPE

# specify which node models this image can handle
LABEL walt.node.models=pc-x86-64

# specify min walt server version needed
LABEL walt.server.minversion=5

# prepare and run customization
COPY overlays/generic overlays/${OS_TYPE} overlays/ipxe \
     overlays/pc overlays/pc-${OS_TYPE} overlays/pc-x86-64 /
RUN /root/customize.sh pc-x86-64

# set an entrypoint (handy when debugging)
ENTRYPOINT /bin/sh
