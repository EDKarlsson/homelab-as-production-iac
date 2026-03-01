#!/usr/bin/env bash

grep -E '\[\w+-url\]:' README.md | grep -v '<!' | awk '{print $1}' | tr -d "[]:" | cut -d "-" -f 1 > required-dirs.txt
