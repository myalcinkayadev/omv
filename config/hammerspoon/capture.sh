#!/bin/sh
# Usage: capture.sh text|qr|color|record <file>
# text: select a region, read its text with the Vision framework, and copy it.
# qr: select a region, read the QR code in it with the Vision framework, and copy it.
# color: pick a color with the macOS color sampler, and copy it as #RRGGBB.
# record: select a region, then record it to <file> until interrupted (SIGINT), showing clicks.
# All need a small Swift helper, built from capture.swift the first time and cached.

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

read_qr() {
  image=$(mktemp -t omv-capture).png
  screencapture -i "$image" || exit 1
  [ -s "$image" ] || exit 1
  build_helper
  code=$("$helper" qr "$image")
  rm -f "$image"
  if [ -z "$code" ]; then
    echo "No QR code found" >&2
    exit 1
  fi
  printf '%s' "$code" | pbcopy
  printf '%s\n' "$code"
}

# exec, so the interrupt that stops the recording reaches screencapture, which then saves.
record_region() {
  file=${1:-}
  if [ -z "$file" ]; then
    echo "usage: capture.sh record <file>" >&2
    exit 2
  fi
  build_helper
  rect=$("$helper" select) || exit 1
  [ -n "$rect" ] || exit 1
  exec screencapture -v -k -R"$rect" "$file"
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
  qr) read_qr ;;
  color) pick_color ;;
  record) record_region "${2:-}" ;;
  *)
    echo "usage: capture.sh text|qr|color|record <file>" >&2
    exit 2
    ;;
esac
