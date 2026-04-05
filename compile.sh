#!/bin/sh
odin build . -debug -linker:mold -o:minimal && ./oi
# odin build . -no-bounds-check -linker:mold -o:size && ./oi

