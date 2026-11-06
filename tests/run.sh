#!/usr/bin/env bash
# Runs every test file and exits non-zero if any of them failed.

cd "$(dirname "$0")" || exit 1

status=0
for test_file in *_test.sh; do
  echo "== $test_file"
  "./$test_file" || status=1
done

echo "== config_contract_test.py"
python3 -I config_contract_test.py || status=1

exit "$status"
