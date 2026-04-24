#!/usr/bin/env bash

set -euo pipefail

if ! command -v swift >/dev/null 2>&1; then
  echo "swift is required to run test classes" >&2
  exit 1
fi

test_classes=()
while IFS= read -r line; do
  test_classes+=("$line")
done < <(swift test list | cut -d/ -f1 | sort -u)

if [[ "${#test_classes[@]}" -eq 0 ]]; then
  echo "No Swift test classes were discovered." >&2
  exit 1
fi

for i in "${!test_classes[@]}"; do
  class_name="${test_classes[$i]}"
  run_number=$((i + 1))

  echo
  echo "==> [${run_number}/${#test_classes[@]}] ${class_name}"

  if [[ "$i" -eq 0 ]]; then
    swift test --filter "${class_name}" --no-parallel
  else
    swift test --skip-build --filter "${class_name}" --no-parallel
  fi
done
