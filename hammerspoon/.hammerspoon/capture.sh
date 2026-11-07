#!/bin/sh
# Usage: capture.sh text|color
# text: select a region, read its text with the Vision framework, and copy it.
# color: pick a color with the macOS color sampler, and copy it as #RRGGBB.
# Both need a small Swift helper, built from capture.swift the first time and cached.

PATH="$PATH:/usr/bin:/bin:/usr/sbin"

source_file=$(dirname "$0")/capture.swift
helper=$HOME/.cache/omv/capture

build_helper() {
  [ -x "$helper" ] && [ "$helper" -nt "$source_file" ] && return 0
  mkdir -p "$(dirname "$helper")"
  swiftc -O "$source_file" -o "$helper" >/dev/null 2>&1 || {
    echo "Couldn't build the capture helper" >&2
    exit 1
  }
}

read_text() {
  image=$(mktemp -t omv-capture).png
  screencapture -i "$image" || exit 1
  [ -s "$image" ] || exit 1
  build_helper
  text=$("$helper" ocr "$image")
  rm -f "$image"
  if [ -z "$text" ]; then
    echo "No text found" >&2
    exit 1
  fi
  printf '%s' "$text" | pbcopy
}

pick_color() {
  build_helper
  color=$("$helper" color) || exit 1
  [ -n "$color" ] || exit 1
  printf '%s' "$color" | pbcopy
  printf '%s\n' "$color"
}

case ${1:-} in
  text) read_text ;;
  color) pick_color ;;
  *)
    echo "usage: capture.sh text|color" >&2
    exit 2
    ;;
esac
