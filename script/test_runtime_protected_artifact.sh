#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-runtime-artifact-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
MODULE_CACHE="$BUILD_DIR/ModuleCache"
mkdir -p "$MODULE_CACHE"

# RuntimePayload is intentionally kept in RuntimeInstaller.swift beside its
# only consumer. Compile that production type without the AppState extension.
sed '/^enum RuntimeInstallState:/,$d' \
  "$ROOT/DefenseClawMac/DataLayer/RuntimeInstaller.swift" \
  > "$BUILD_DIR/RuntimePayload.swift"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" xcrun swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$BUILD_DIR/RuntimePayload.swift" \
  "$ROOT/Tests/RuntimeProtectedArtifactTests.swift" \
  -o "$BUILD_DIR/RuntimeProtectedArtifactTests"

"$BUILD_DIR/RuntimeProtectedArtifactTests"

# Exercise the exact packaging preflight without downloading or packaging.
python3 - "$ROOT/scripts/build_unified_dmg.sh" <<'PYTEST'
from pathlib import Path
import subprocess
import sys

source = Path(sys.argv[1]).read_text()
marker = "python3 - \"$RUNTIME_VERSION\" <<'ACP_PROTOCOL_CHECK'\n"
start = source.index(marker)
code = source[start + len(marker):].split("\nACP_PROTOCOL_CHECK\n", 1)[0]
assert start < source.index('gh release download'), "unsupported payloads must fail before download"
for version, allowed in [
    ("0.8.10", True), ("0.8.9", True), ("0.8.11", False), ("0.9.0", False),
    ("1.0.0", False), ("0.8.11-rc1", False), ("0.8.10+source", False),
    ("0.08.10", False), ("0.8", False), ("0.8.10\n", False),
]:
    result = subprocess.run([sys.executable, "-", version], input=code, text=True, capture_output=True)
    assert (result.returncode == 0) == allowed, f"incorrect packaging protocol acceptance: {version!r}"
    if version == "0.8.11":
        assert "requires ACP installer support" in result.stderr
print("Runtime payload packaging protocol tests passed")
PYTEST
