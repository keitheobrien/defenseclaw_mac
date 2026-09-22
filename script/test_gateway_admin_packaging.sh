#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gateway-admin-packaging.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
source "$ROOT/scripts/lib/gateway_admin_signing.sh"
APP="$WORK/DefenseClawMac.app"
TOOLS="$APP/Contents/Library/LaunchServices"
PLIST="$APP/Contents/Library/LaunchDaemons/$GATEWAY_ADMIN_IDENTIFIER.plist"
mkdir -p "$TOOLS" "$(dirname "$PLIST")"
printf 'unsigned helper fixture\n' > "$TOOLS/DefenseClawGatewayHelper"
chmod 755 "$TOOLS/DefenseClawGatewayHelper"
python3 - "$PLIST" <<'PYEOF'
import plistlib
import sys
identifier = "com.keitheobrien.DefenseClawMac.GatewayAdmin"
with open(sys.argv[1], "wb") as output:
    plistlib.dump({
        "Label": identifier,
        "BundleProgram": "Contents/Library/LaunchServices/DefenseClawGatewayHelper",
        "ProgramArguments": ["DefenseClawGatewayHelper"],
        "MachServices": {identifier: True},
        "AssociatedBundleIdentifiers": ["com.keitheobrien.DefenseClawMac"],
        "UserName": "root",
    }, output)
PYEOF
verify_gateway_admin_layout "$APP"
if verify_gateway_admin_bundle "$APP" 9R236BB67S 2>/dev/null; then
    printf 'Unsigned helper bundle passed release verification\n' >&2; exit 1
fi
mv "$TOOLS/DefenseClawGatewayHelper" "$WORK/helper"
if verify_gateway_admin_layout "$APP" 2>/dev/null; then
    printf 'Missing helper passed layout verification\n' >&2; exit 1
fi
ln -s "$WORK/helper" "$TOOLS/DefenseClawGatewayHelper"
if verify_gateway_admin_layout "$APP" 2>/dev/null; then
    printf 'Symlinked helper passed layout verification\n' >&2; exit 1
fi
rm "$TOOLS/DefenseClawGatewayHelper"
mv "$WORK/helper" "$TOOLS/DefenseClawGatewayHelper"
printf 'obsolete bundled runtime\n' > "$TOOLS/defenseclaw-gateway"
if verify_gateway_admin_layout "$APP" 2>/dev/null; then
    printf 'Bundled replacement runtime passed layout verification\n' >&2; exit 1
fi
rm "$TOOLS/defenseclaw-gateway"
python3 - "$PLIST" <<'PYEOF'
import plistlib
import sys
with open(sys.argv[1], "rb") as source:
    data = plistlib.load(source)
data["Program"] = "/bin/sh"
with open(sys.argv[1], "wb") as output:
    plistlib.dump(data, output)
PYEOF
if verify_gateway_admin_layout "$APP" 2>/dev/null; then
    printf 'Alternate privileged program passed layout verification\n' >&2; exit 1
fi
printf 'Gateway administrator packaging checks passed\n'
