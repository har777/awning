.PHONY: all build run install test clean

all: build

build:
	./build.sh

run:
	./build.sh run

install:
	./build.sh install

test:
	swift test

clean:
	rm -rf .build build
