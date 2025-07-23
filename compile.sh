#!/bin/sh
clear
odin run . -o:none -linker:lld -debug -show-timings
