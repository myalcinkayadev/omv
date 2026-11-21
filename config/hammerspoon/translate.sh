#!/bin/sh
# Usage: translate.sh detect | translate.sh <from> <to>, with the text on stdin.
# Finds the text's language, or translates it on the Mac, through a small Swift helper
# built from translate.swift the first time and cached; translate.swift says what it prints.

PATH="$PATH:/usr/bin:/bin"

source_file=$(dirname "$0")/translate.swift
helper=$HOME/.cache/omv/translate

build_helper() {
  [ -x "$helper" ] && [ "$helper" -nt "$source_file" ] && return 0
  mkdir -p "$(dirname "$helper")"
  swiftc -O "$source_file" -o "$helper" >/dev/null 2>&1 || {
    echo "Couldn't build the translate helper" >&2
    exit 1
  }
}

build_helper
exec "$helper" "$@"
