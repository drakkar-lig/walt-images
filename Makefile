
all: build

build.%:
	python3 build.py $*

build:
	$(MAKE) $(shell ./get_make_steps.sh build)

publish.%:
	python3 publish.py $*

publish:
	$(MAKE) $(shell ./get_make_steps.sh publish)
