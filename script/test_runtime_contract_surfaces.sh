#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-runtime-contract-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
MODULE_CACHE="$BUILD_DIR/ModuleCache"
mkdir -p "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" xcrun swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT/DefenseClawMac/DataLayer/AlertDispositionCommand.swift" \
  "$ROOT/DefenseClawMac/DataLayer/CommandRegistry.swift" \
  "$ROOT/Tests/RuntimeContractSurfaceTests.swift" \
  -o "$BUILD_DIR/RuntimeContractSurfaceTests"

"$BUILD_DIR/RuntimeContractSurfaceTests"

if grep -Fq 'key: "otel.' "$ROOT/DefenseClawMac/Features/ConfigEditorDefinitions.swift"; then
  echo "Legacy config-v7 otel.* editor fields remain" >&2
  exit 1
fi

if grep -Fq 'migrate-splunk' "$ROOT/DefenseClawMac/DataLayer/CommandRegistry.swift"; then
  echo "Retired migrate-splunk command remains" >&2
  exit 1
fi

if grep -Fq 'Search 226 commands' "$ROOT/DefenseClawMac/Features/CommandPaletteView.swift"; then
  echo "Command palette still contains a stale hard-coded count" >&2
  exit 1
fi

if ! grep -Fq 'DEFENSECLAW_SETUP_OBSERVABILITY_TOKEN' "$ROOT/DefenseClawMac/Features/SetupDefinitions.swift"; then
  echo "Observability token is not using the runtime 0.8.9 secret environment contract" >&2
  exit 1
fi

if ! sed -n '/case \.secure:/,/default:/p' "$ROOT/DefenseClawMac/Features/SetupView.swift" \
    | grep -Fq 'continue'; then
  echo "Generic setup fields no longer fail closed for secure values" >&2
  exit 1
fi

if ! grep -Fq 'commandEnvironment.keys.sorted().map' "$ROOT/DefenseClawMac/Features/SetupView.swift"; then
  echo "Setup review no longer displays masked child-environment keys" >&2
  exit 1
fi

for secret_key in SPLUNK_ACCESS_TOKEN DEFENSECLAW_SPLUNK_HEC_TOKEN SFX_AUTH_TOKEN; do
  if ! grep -Fq "$secret_key" "$ROOT/DefenseClawMac/Features/SetupDefinitions.swift"; then
    echo "Setup secret is missing its child-environment transport: $secret_key" >&2
    exit 1
  fi
done

if sed -n '/func observabilityCommands/,/func observabilityValidation/p' \
    "$ROOT/DefenseClawMac/Features/SetupDefinitions.swift" | grep -Fq -- '--connector'; then
  echo "Observability command still emits the removed runtime --connector option" >&2
  exit 1
fi

for required in release-provenance.json release-source-map.json \
    "FETCH_HEAD^{tree}" '"runtime_source":' strip_stale_provenance app-only-zip-check; do
  if ! grep -Fq "$required" "$ROOT/scripts/build_unified_dmg.sh"; then
    echo "Unified packaging is missing authenticated source binding: $required" >&2
    exit 1
  fi
done

if grep -Fq 'raw.githubusercontent.com' "$ROOT/scripts/build_unified_dmg.sh"; then
  echo "Unified packaging still accepts unverified raw source bytes" >&2
  exit 1
fi
