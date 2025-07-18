
SHELL := /bin/bash		# needed for "read -s" (silent read for passwords)

all:
	nice make build-featured

parallel:
	nice make -j $(shell nproc) build-featured

build.%:
	python3 build.py $*

build-featured: build-base
	$(MAKE) $(shell ./get_make_steps.sh build featured)

build-base:
	$(MAKE) $(shell ./get_make_steps.sh build base)

publish.%:
	python3 publish.py $*

publish:
	read -p 'docker hub user: ' DOCKER_USER && \
	read -s -p 'docker hub password: ' DOCKER_PASSWORD && echo && \
	export DOCKER_USER DOCKER_PASSWORD && \
	$(MAKE) $(shell ./get_make_steps.sh publish)
