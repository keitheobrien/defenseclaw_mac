#!/usr/bin/env bash
# Release checks for the on-demand SMAppService helper.

GATEWAY_ADMIN_IDENTIFIER="com.keitheobrien.DefenseClawMac.GatewayAdmin"
GATEWAY_ADMIN_APP_IDENTIFIER="com.keitheobrien.DefenseClawMac"

verify_gateway_admin_layout() {
    python3 - "$1" <<'PYEOF'
import os
from pathlib import Path
import plistlib
import stat
import sys

app = Path(sys.argv[1])
identifier = "com.keitheobrien.DefenseClawMac.GatewayAdmin"
helper_relative = "Contents/Library/LaunchServices/DefenseClawGatewayHelper"
for relative in ("", "Contents", "Contents/Library", "Contents/Library/LaunchServices", "Contents/Library/LaunchDaemons"):
    directory = app / relative
    if directory.is_symlink() or not directory.is_dir():
        raise SystemExit(f"helper bundle directory must be a regular directory: {directory}")
for relative in (helper_relative, f"Contents/Library/LaunchDaemons/{identifier}.plist"):
    artifact = app / relative
    try:
        metadata = artifact.lstat()
    except FileNotFoundError:
        raise SystemExit(f"required helper artifact is missing: {artifact}")
    if not stat.S_ISREG(metadata.st_mode):
        raise SystemExit(f"helper artifact must be a regular file: {artifact}")
    if not relative.endswith(".plist") and not os.access(artifact, os.X_OK):
        raise SystemExit(f"helper executable is not executable: {artifact}")

# Never silently replace an installed/source gateway through app packaging.
if os.path.lexists(app / "Contents/Library/LaunchServices/defenseclaw-gateway"):
    raise SystemExit("administrator bundle must not contain a replacement gateway")

plist_path = app / f"Contents/Library/LaunchDaemons/{identifier}.plist"
with plist_path.open("rb") as source:
    actual = plistlib.load(source)
expected = {
    "Label": identifier,
    "BundleProgram": helper_relative,
    "ProgramArguments": ["DefenseClawGatewayHelper"],
    "MachServices": {identifier: True},
    "AssociatedBundleIdentifiers": ["com.keitheobrien.DefenseClawMac"],
    "UserName": "root",
}
if actual != expected:
    raise SystemExit("bundled LaunchDaemon differs from the approved on-demand helper contract")
PYEOF
}

verify_gateway_admin_bundle() {
    local app="$1" expected_team="$2"
    local helper="$app/Contents/Library/LaunchServices/DefenseClawGatewayHelper"
    local developer_requirement details
    [[ "$expected_team" =~ ^[A-Z0-9]{10}$ ]] || {
        printf 'A valid Developer ID team is required for helper verification\n' >&2
        return 1
    }
    verify_gateway_admin_layout "$app" || return 1
    developer_requirement="anchor apple generic and certificate leaf[subject.OU] = \"$expected_team\" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
    /usr/bin/codesign --verify --strict --deep --verbose=4 \
        -R "=$developer_requirement and identifier \"$GATEWAY_ADMIN_APP_IDENTIFIER\"" "$app" || return 1
    /usr/bin/codesign --verify --strict --verbose=4 \
        -R "=$developer_requirement and identifier \"$GATEWAY_ADMIN_IDENTIFIER\"" "$helper" || return 1
    details="$(/usr/bin/codesign -dvvv "$helper" 2>&1)" || return 1
    if ! grep -Eq '^CodeDirectory .* flags=.*\([^)]*runtime[^)]*\)' <<< "$details"; then
        printf 'Gateway administrator helper is missing hardened runtime\n' >&2
        return 1
    fi
}
