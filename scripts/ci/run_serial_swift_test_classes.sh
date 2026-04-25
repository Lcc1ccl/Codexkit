#!/usr/bin/env bash

set -euo pipefail

if ! command -v swift >/dev/null 2>&1; then
  echo "swift is required to run test classes" >&2
  exit 1
fi

swift_test_timeout_seconds="${CODEXKIT_SWIFT_TEST_TIMEOUT_SECONDS:-300}"

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

run_swift_test() {
  local pattern="$1"

  python3 - "$pattern" "$swift_test_timeout_seconds" <<'PY'
import os
import signal
import subprocess
import sys
pattern = sys.argv[1]
timeout_seconds = int(sys.argv[2])
command = ["swift", "test", "--filter", pattern, "--no-parallel"]
process = subprocess.Popen(command, start_new_session=True)
try:
    raise SystemExit(process.wait(timeout=timeout_seconds))
except subprocess.TimeoutExpired:
    print(
        f"swift test timed out after {timeout_seconds}s for filter: {pattern}",
        file=sys.stderr,
        flush=True,
    )
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=10)
    except Exception:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except Exception:
            pass
        process.wait()
    raise SystemExit(124)
PY
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
  run_swift_test "${pattern}"
}

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

run_batch "release-critical classes" "${early_classes[@]}"
run_batch "isolated CLIProxyAPI probe suite" "${isolated_classes[@]}"

for class_name in "${remaining_classes[@]}"; do
  run_batch "suite ${class_name}" "$class_name"
done
