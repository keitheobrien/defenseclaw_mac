#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_PYTHON="${DEFENSECLAW_RUNTIME_PYTHON:-$ROOT/../defenseclaw/.venv/bin/python}"
if [[ ! -x "$RUNTIME_PYTHON" ]]; then
  echo 'Set DEFENSECLAW_RUNTIME_PYTHON to the selected DefenseClaw runtime interpreter.' >&2
  exit 1
fi
"$RUNTIME_PYTHON" "$ROOT/Tests/PolicyCatalogBridgeTests.py"
