#!/bin/bash
set -euo pipefail

# Native windows require a logged-in macOS desktop session. Ordinary aggregate
# test runs remain headless; explicitly opt in to this separate GUI regression.
if [[ $# -eq 0 ]]; then
  echo 'SKIP InspectorNativeLayoutTests: use --run-gui in a macOS desktop session.'
  exit 0
fi

NATIVE_RUN_GUI=false
NATIVE_VERIFY_REPRODUCER=false
for NATIVE_ARGUMENT in "$@"; do
  case "$NATIVE_ARGUMENT" in
    --run-gui) NATIVE_RUN_GUI=true ;;
    --verify-reproducer) NATIVE_VERIFY_REPRODUCER=true ;;
    *) echo "Usage: $0 --run-gui [--verify-reproducer]" >&2; exit 2 ;;
  esac
done
if [[ "$NATIVE_RUN_GUI" != true ]]; then
  echo '--verify-reproducer also requires explicit --run-gui.' >&2
  exit 2
fi
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'InspectorNativeLayoutTests requires macOS and a logged-in desktop session.' >&2
  exit 2
fi

NATIVE_REPOSITORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-inspector-native-tests.XXXXXX")"
NATIVE_MODULE_CACHE="$NATIVE_BUILD_DIR/ModuleCache"
mkdir -p "$NATIVE_MODULE_CACHE"
echo "Native inspector regression artifacts: $NATIVE_BUILD_DIR"

CLANG_MODULE_CACHE_PATH="$NATIVE_MODULE_CACHE" xcrun swiftc \
  -O -parse-as-library \
  -target "$(uname -m)-apple-macos14.0" \
  -module-cache-path "$NATIVE_MODULE_CACHE" \
  "$NATIVE_REPOSITORY_ROOT/DefenseClawMac/DesignSystem/InspectorLayoutPolicy.swift" \
  "$NATIVE_REPOSITORY_ROOT/Tests/InspectorNativeLayoutTests.swift" \
  -o "$NATIVE_BUILD_DIR/DefenseClawLayoutProbe"

# Preserve logs on both success and failure. A failed native layout may wedge
# the main thread, so the watchdog must live outside the SwiftUI process.
python3 - "$NATIVE_BUILD_DIR" "$NATIVE_VERIFY_REPRODUCER" <<'PY'
import json
import pathlib
import platform
import subprocess
import sys
import time

root = pathlib.Path(sys.argv[1])
verify_reproducer = sys.argv[2] == "true"
cases = [("fixed", "native", 980), ("fixed", "accessibility", 1180)]
if verify_reproducer:
    cases.insert(0, ("baseline", "native", 980))
results = []
failed = False
for variant, input_mode, width in cases:
    name = f"{variant}-{input_mode}-{width}"
    log_path = root / f"{name}.log"
    started = time.monotonic()
    with log_path.open("w") as output:
        try:
            process = subprocess.run(
                [str(root / "DefenseClawLayoutProbe"), "--variant", variant, "--input", input_mode, "--width", str(width)],
                stdout=output,
                stderr=subprocess.STDOUT,
                timeout=45,
                check=False,
            )
            status = process.returncode
        except subprocess.TimeoutExpired:
            status = "watchdog timeout"
    output = log_path.read_text(errors="replace")
    if variant == "baseline":
        passed = (
            status == 90
            and "EXCEPTION NSGenericException: The window has been marked as needing another Update Constraints" in output
        )
        expectation = "known native constraint exception reproduced"
    else:
        passed = (
            status == 0
            and "SEQUENCE COMPLETE" in output
            and "FINAL WINDOW" in output
            and "PASS survived" in output
            and "EXCEPTION" not in output
            and "FAIL " not in output
            and output.count(" SELECT ") == 13
            and output.count(" CLOSE ACTION") == 4
            and output.count(" DESELECT") == 4
            and output.count(" HYDRATE APPLIED") >= 2
            and output.count(" HYDRATE DISCARDED") >= 1
            and output.count(" PARENT PULSE") >= 4
            and output.count(" DETAILS APPEARED") >= 2
            and output.count(" DETAILS DISAPPEARED") >= 1
            and "DWELL inspector open for 20 seconds" in output
            and (input_mode != "accessibility" or output.count(" AX SELECTION") == 17)
        )
        expectation = "native inputs, close/open resize cycles, variable hydration, parent updates, and 20-second open-details dwell completed"
    result = {
        "case": name,
        "passed": passed,
        "exit_status": status,
        "duration_seconds": round(time.monotonic() - started, 2),
        "expectation": expectation,
        "log": str(log_path),
    }
    results.append(result)
    failed |= not passed
    print(f"{'PASS' if passed else 'FAIL'} {name}: {expectation}; exit={status}", flush=True)
    if not passed:
        print(f"See {log_path}", file=sys.stderr)
        if variant == "baseline":
            print("The optional baseline control must reproduce on this OS to establish the before/after comparison.", file=sys.stderr)

(root / "results.json").write_text(json.dumps({"macos": platform.mac_ver()[0], "optimization": "-O", "cases": results}, indent=2) + "\n")
print(f"Native inspector regression report: {root / 'results.json'}", flush=True)
sys.exit(1 if failed else 0)
PY
