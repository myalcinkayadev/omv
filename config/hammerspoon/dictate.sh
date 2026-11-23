#!/bin/sh
# Usage: dictate.sh locales | install <locale> <engine> | listen <locale> <engine>
# Hears speech on the Mac, through a small Swift helper built from dictate.swift the first
# time and cached; dictate.swift says what it prints.

PATH="$PATH:/usr/bin:/bin"

source_file=$(dirname "$0")/dictate.swift
helper=$HOME/.cache/omv/dictate

build_helper() {
  [ -x "$helper" ] && [ "$helper" -nt "$source_file" ] && return 0
  mkdir -p "$(dirname "$helper")"
  swiftc -O "$source_file" -o "$helper" >/dev/null 2>&1 || {
    echo "Couldn't build the dictation helper" >&2
    exit 1
  }
}

build_helper
exec "$helper" "$@"
