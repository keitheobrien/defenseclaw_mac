#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# No bytecode: a __pycache__ written into the Codex skill directory makes the
# runtime's skill scanner fail closed (BYTECODE_ANALYSIS_UNAVAILABLE) and the
# codex watcher quarantines the repo's own skill.
exec env PYTHONDONTWRITEBYTECODE=1 python3 -B "$ROOT/Tests/RuntimeCompatibilityAuditTests.py"
