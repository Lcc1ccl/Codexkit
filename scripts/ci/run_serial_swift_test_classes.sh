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

escape_regex() {
  printf '%s' "$1" | sed 's/[.[\\*^$()+?{|]/\\&/g'
}

run_batch() {
  local label="$1"
  shift
  local specs=("$@")

  if [[ "${#specs[@]}" -eq 0 ]]; then
    return
  fi

  local pattern=""
  local first=1
  local spec escaped
  for spec in "${specs[@]}"; do
    escaped="$(escape_regex "$spec")"
    if [[ "$first" -eq 1 ]]; then
      pattern="${escaped}"
      first=0
    else
      pattern="${pattern}|${escaped}"
    fi
  done

  echo
  echo "==> ${label}"
  if [[ -n "${XCTEST_BUNDLE_PATH:-}" ]]; then
    local selector
    selector="$(IFS=,; echo "${specs[*]}")"
    xcrun xctest -XCTest "${selector}" "${XCTEST_BUNDLE_PATH}"
  else
    swift test --filter "${pattern}" --no-parallel
  fi
}

if [[ "$(uname -s)" == "Darwin" ]] && command -v xcrun >/dev/null 2>&1; then
  swift build --build-tests
  bin_path="$(swift build --build-tests --show-bin-path)"
  candidate_bundle="${bin_path}/CodexkitPackageTests.xctest"
  if [[ -d "${candidate_bundle}" ]]; then
    XCTEST_BUNDLE_PATH="${candidate_bundle}"
    export XCTEST_BUNDLE_PATH
    echo "Using direct XCTest runner: ${XCTEST_BUNDLE_PATH}"
  fi
fi

early_classes=(
  "CodexkitAppTests.APIServiceRoutingEnableTests"
  "CodexkitAppTests.AppLifecycleDiagnosticsTests"
  "CodexkitAppTests.CLIProxyAPIAuthExporterTests"
  "CodexkitAppTests.CLIProxyAPIManagementServiceTests"
)

isolated_classes=(
  "CodexkitAppTests.CLIProxyAPIProbeServiceTests"
)

remaining_classes=()
for class_name in "${test_classes[@]}"; do
  skip=0
  for reserved in "${early_classes[@]}" "${isolated_classes[@]}"; do
    if [[ "$class_name" == "$reserved" ]]; then
      skip=1
      break
    fi
  done
  if [[ "$skip" -eq 0 ]]; then
    remaining_classes+=("$class_name")
  fi
done

half=$(( (${#remaining_classes[@]} + 1) / 2 ))
batch_three=("${remaining_classes[@]:0:$half}")
batch_four=("${remaining_classes[@]:$half}")

run_batch "batch 1/4 early release-critical classes" "${early_classes[@]}"
run_batch "batch 2/4 isolated CLIProxyAPI probe suite" "${isolated_classes[@]}"
run_batch "batch 3/4 remaining suites (part 1)" "${batch_three[@]}"
run_batch "batch 4/4 remaining suites (part 2)" "${batch_four[@]}"
