#!/bin/sh
# Try a parallel build.
# If it succeeds, exit successfully.
# If it fails:
# 1. Run a sequential build, to make sure we stop just after
#    the error messages are printed.
# 2. Create an empty file ".error_detected".
nice make -j$(nproc) "$@" || \
    nice make -j1 V=s "$@" || \
    touch .error_detected

# Since creating the file ".error_detected" will succeed, the script
# exits successfully too, which allows docker to validate this
# Dockerfile step.
# Next step of the Dockerfile should be to fail if this file exists.

# This technique allows to ease further investigation in case of
# failure:
# a. comment all Dockerfile steps after this one
# b. run a build again -- this will be near-instantaneous since
#    all previous build steps and this one were successful, so
#    they were recorded in the build cache. 
# c. start a container on this partial image, and debug it.
