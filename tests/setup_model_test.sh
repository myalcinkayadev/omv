#!/usr/bin/env bash
# Builds the setup assistant's logic with its tests, with the real swiftc, and runs them.

source "$(dirname "$0")/lib.sh"

build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
swiftc -parse-as-library "$REPO_DIR/install/setup/SetupModel.swift" "$REPO_DIR/install/setup/InstallRun.swift" \
  "$REPO_DIR/tests/setup_model_test.swift" \
  -o "$build/tests" 2>&1 || { echo "FAIL - the setup model didn't build"; exit 1; }
"$build/tests"
