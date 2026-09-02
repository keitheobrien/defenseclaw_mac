#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/gateway_signing.sh"

EXPECTED_TEAM_ID="9R236BB67S"

if [[ $# -ne 1 ]]; then
    printf 'Usage: %s <DefenseClawMac.dmg>\n' "$0" >&2
    exit 2
fi

DMG="$1"
[[ -f "$DMG" ]] || { printf 'DMG not found: %s\n' "$DMG" >&2; exit 1; }

MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-release-verify.XXXXXX")"
ATTACHED=0
cleanup() {
    if [[ "$ATTACHED" == "1" ]]; then
        hdiutil detach "$MOUNT_POINT" -quiet || true
    fi
    rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$DMG" >/dev/null
ATTACHED=1

shopt -s nullglob
apps=("$MOUNT_POINT"/*.app)
shopt -u nullglob
if [[ ${#apps[@]} -ne 1 ]]; then
    printf 'Unified DMG must contain exactly one top-level app; found %d\n' "${#apps[@]}" >&2
    exit 1
fi

APP="${apps[0]}"
PAYLOAD="$APP/Contents/Resources/RuntimePayload"
GATEWAY="$PAYLOAD/defenseclaw-gateway"
MANIFEST="$PAYLOAD/payload-manifest.json"

/usr/bin/codesign --verify --strict --deep --verbose=4 "$APP"
verify_gateway_signature "$GATEWAY" "$EXPECTED_TEAM_ID"

python3 - "$MANIFEST" "$GATEWAY" <<'PYEOF'
import hashlib
import json
from pathlib import Path
import sys

manifest_path = Path(sys.argv[1])
gateway_path = Path(sys.argv[2])

if not manifest_path.is_file():
    raise SystemExit(f"payload manifest is missing: {manifest_path}")
if not gateway_path.is_file():
    raise SystemExit(f"gateway is missing: {gateway_path}")

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
gateway = manifest.get("gateway")
if not isinstance(gateway, dict):
    raise SystemExit("payload manifest gateway entry is missing")
if gateway.get("file") != "defenseclaw-gateway":
    raise SystemExit("payload manifest names an unexpected gateway file")

expected_sha = gateway.get("sha256")
actual_sha = hashlib.sha256(gateway_path.read_bytes()).hexdigest()
if expected_sha != actual_sha:
    raise SystemExit(
        f"payload manifest gateway SHA-256 mismatch: expected {expected_sha}, got {actual_sha}"
    )
PYEOF

printf 'Verified unified release payload: %s\n' "$DMG"
