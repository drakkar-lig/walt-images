# Target image
# ------------

ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION}

# specify which node models this image can handle
LABEL walt.node.models=pc-x86-64

# specify min walt server version needed
LABEL walt.server.minversion=5

# prepare and run customization
COPY overlay /
RUN /root/customize.sh pc-x86-64
