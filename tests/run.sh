#!/usr/bin/env bash
# Runs every test file and exits non-zero if any of them failed.
# The files run in parallel, since each works in its own temporary folders. Each file's
# output is printed whole and in name order, so the report reads the same as one by one.

cd "$(dirname "$0")" || exit 1

output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT

for test_file in *_test.sh; do
  ( "./$test_file" > "$output/$test_file.log" 2>&1; echo $? > "$output/$test_file.status" ) &
done
wait

status=0
for test_file in *_test.sh; do
  echo "== $test_file"
  cat "$output/$test_file.log"
  [ "$(cat "$output/$test_file.status")" = 0 ] || status=1
done

echo "== config_contract_test.py"
python3 -I config_contract_test.py || status=1

exit "$status"
