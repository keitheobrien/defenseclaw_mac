#!/usr/bin/env bash
# Build both release artifacts:
#   DefenseClawMac-<ver>.zip — the traditional app-only build (no runtime
#     payload; also the self-update asset, so updates stay small), and
#   DefenseClawMac-<ver>.dmg — the unified installer whose app embeds the
#     latest DefenseClaw runtime release as an install payload
#     (Contents/Resources/RuntimePayload).
# Both signed + notarized + stapled (three notary submissions).
#
# See docs/UNIFIED_INSTALLER_PLAN.md. Publishes nothing — artifacts land in
# build/unified/out/.
#
# Env overrides:
#   RUNTIME_TAG=0.8.4    pin the runtime release (default: latest)
#   SKIP_NOTARIZE=1      skip notarization/stapling/spctl (iteration builds)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_REPO="cisco-ai-defense/defenseclaw"
IDENTITY="Developer ID Application: Keith OBrien (9R236BB67S)"
TEAM_ID="9R236BB67S"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool}"
ARCH="arm64"
APP_NAME="DefenseClawMac"

WORK="$REPO_ROOT/build/unified"
RUNTIME_DIR="$WORK/runtime"
# Un-notarized iteration builds must never share the publishable directory —
# the artifacts are byte-identically named, and one mixed-up upload would ship
# a Gatekeeper-rejected app to every new install.
if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
    OUT="$WORK/out-unnotarized"
else
    OUT="$WORK/out"
fi

step() { printf '\n==> %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# notarytool's exit code on an Invalid verdict is not reliable across
# versions — require an explicit "status: Accepted" in the output.
notarize() {
    local artifact="$1" out
    out="$(xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || {
        printf '%s\n' "$out" >&2
        die "notarytool submit failed for $artifact"
    }
    printf '%s\n' "$out"
    grep -q "status: Accepted" <<< "$out" || die "notarization NOT accepted for $artifact (see log above; run 'xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE')"
}

command -v gh >/dev/null || die "gh CLI is required"
command -v cosign >/dev/null || die "cosign is required (brew install cosign) — checksums.txt provenance is verified fail-closed"
command -v python3 >/dev/null || die "python3 is required"
command -v curl >/dev/null || die "curl is required"
command -v uv >/dev/null || die "uv is required to produce the hash-locked runtime dependency set"

rm -rf "$WORK"
mkdir -p "$RUNTIME_DIR" "$OUT"

# ── 1. Resolve + download the runtime release ────────────────────────────────
RUNTIME_TAG="${RUNTIME_TAG:-$(gh release view --repo "$RUNTIME_REPO" --json tagName -q .tagName)}"
[[ -n "$RUNTIME_TAG" ]] || die "could not resolve latest $RUNTIME_REPO release tag"
RUNTIME_VERSION="${RUNTIME_TAG#v}"
step "Runtime release: $RUNTIME_TAG"

# DefenseClaw 0.8.4+ deliberately publishes refusal bytes under the legacy
# wheel/gateway names. Only the protocol-2 artifacts selected by the signed
# upgrade policy contain installable runtime bytes.
PROTECTED_GATEWAY="$RUNTIME_DIR/defenseclaw_${RUNTIME_VERSION}_protocol2_darwin_${ARCH}.dcgateway"
WHEEL="$RUNTIME_DIR/defenseclaw-${RUNTIME_VERSION}-2-py3-none-any.dcwheel"
UPGRADE_MANIFEST="$RUNTIME_DIR/upgrade-manifest.json"
RELEASE_SOURCE_MAP="$RUNTIME_DIR/release-source-map.json"
RUNTIME_ATTESTATION="$RUNTIME_DIR/runtime-candidate-checksums.txt"
gh release download "$RUNTIME_TAG" --repo "$RUNTIME_REPO" --dir "$RUNTIME_DIR" \
    --pattern "$(basename "$PROTECTED_GATEWAY")" \
    --pattern "$(basename "$WHEEL")" \
    --pattern "upgrade-manifest.json" \
    --pattern "release-source-map.json" \
    --pattern "checksums.txt" \
    --pattern "checksums.txt.sig" \
    --pattern "checksums.txt.pem"

[[ -f "$PROTECTED_GATEWAY" && -f "$WHEEL" && -f "$UPGRADE_MANIFEST" && -f "$RELEASE_SOURCE_MAP" ]] \
    || die "release $RUNTIME_TAG did not provide its protected macOS runtime and upgrade policy"
for f in checksums.txt checksums.txt.sig checksums.txt.pem; do
    [[ -f "$RUNTIME_DIR/$f" ]] || die "release is missing $f — refusing to trust unsigned/unverifiable checksums"
done

# ── 2. Verify provenance (fail closed) ───────────────────────────────────────
# Mirrors the runtime's own cmd_upgrade.py::_verify_checksums_sigstore, but
# strict: this is a build pipeline, not an end-user install.
step "Verifying checksums.txt Sigstore signature (cosign)"
cosign verify-blob \
    --certificate "$RUNTIME_DIR/checksums.txt.pem" \
    --signature "$RUNTIME_DIR/checksums.txt.sig" \
    --certificate-identity "https://github.com/${RUNTIME_REPO}/.github/workflows/release.yaml@refs/heads/main" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    "$RUNTIME_DIR/checksums.txt" \
    || die "Sigstore verification of checksums.txt FAILED"

verify_sha256() {
    local file="$1" name expected actual
    name="$(basename "$file")"
    # checksums.txt lines: "<hash>  <name>" (optionally "*<name>" binary marker)
    expected="$(awk -v f="$name" '{ n=$NF; sub(/^\*/, "", n); if (n==f) print $1 }' "$RUNTIME_DIR/checksums.txt")"
    [[ -n "$expected" ]] || die "no checksum entry for $name in checksums.txt"
    [[ "$(printf '%s' "$expected" | wc -l)" -eq 0 ]] || die "multiple checksum entries for $name"
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    [[ "$expected" == "$actual" ]] || die "sha256 mismatch for $name: expected $expected got $actual"
    printf '    ok  %s  %s\n' "$actual" "$name"
}
step "Verifying artifact checksums"
verify_sha256 "$PROTECTED_GATEWAY"
verify_sha256 "$WHEEL"
verify_sha256 "$UPGRADE_MANIFEST"
verify_sha256 "$RELEASE_SOURCE_MAP"
WHEEL_SHA="$(shasum -a 256 "$WHEEL" | awk '{print $1}')"

# The signed release source map binds the public release version to the exact
# source commit that produced it. Any supplemental source input must be fetched
# by that authenticated commit, never by a mutable/movable release tag.
SOURCE_COMMIT="$(python3 - "$RELEASE_SOURCE_MAP" "$RUNTIME_VERSION" <<'PYEOF'
import json
import re
from pathlib import Path
import sys

source_map = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
version = sys.argv[2]
commit = source_map.get("source_commit", "")
tree = source_map.get("source_tree", "")
if (
    source_map.get("schema_version") != 1
    or source_map.get("release_version") != version
    or re.fullmatch(r"[0-9a-f]{40}", commit) is None
    or re.fullmatch(r"[0-9a-f]{40}", tree) is None
):
    raise SystemExit("authenticated release source map is invalid")
print(commit)
PYEOF
)"
[[ -n "$SOURCE_COMMIT" ]] || die "release source map did not identify an authenticated source commit"
printf '    source commit  %s\n' "$SOURCE_COMMIT"

# The public signed checksum manifest is the release attestation available to
# downstream packagers. Preserve it in the app under the name expected by the
# upstream macOS release verifier.
cp "$RUNTIME_DIR/checksums.txt" "$RUNTIME_ATTESTATION"

# Validate the signed policy before decoding either protected artifact, then
# extract only the regular gateway binary from the authenticated archive.
step "Validating schema-2 runtime policy and protected artifacts"
GATEWAY="$RUNTIME_DIR/defenseclaw-gateway"
DECODED_WHEEL="$RUNTIME_DIR/defenseclaw-${RUNTIME_VERSION}-py3-none-any.whl"
python3 - "$UPGRADE_MANIFEST" "$RUNTIME_ATTESTATION" "$PROTECTED_GATEWAY" "$WHEEL" "$RUNTIME_VERSION" "$GATEWAY" "$DECODED_WHEEL" <<'PYEOF'
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import sys
import tarfile
import zipfile

manifest_path, checksums_path, gateway_path, wheel_path = map(Path, sys.argv[1:5])
version = sys.argv[5]
output_path = Path(sys.argv[6])
decoded_wheel_path = Path(sys.argv[7])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
expected_wheel = f"defenseclaw-{version}-2-py3-none-any.dcwheel"
expected_gateway = f"defenseclaw_{version}_protocol2_darwin_arm64.dcgateway"
gateways = manifest.get("release_artifacts", {}).get("gateways", {})
if (
    manifest.get("schema_version") != 2
    or manifest.get("release_version") != version
    or manifest.get("release_artifacts", {}).get("wheel") != expected_wheel
    or gateways.get("darwin", {}).get("arm64") != expected_gateway
):
    raise SystemExit("signed upgrade manifest does not select the expected protocol-2 macOS runtime")

checksums = {}
for line_number, raw in enumerate(checksums_path.read_text(encoding="utf-8").splitlines(), 1):
    match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9._-]+)", raw)
    if not match:
        raise SystemExit(f"invalid signed checksum line {line_number}")
    digest, name = match.groups()
    if name in checksums:
        raise SystemExit(f"duplicate signed checksum entry: {name}")
    checksums[name] = digest
for path in (manifest_path, gateway_path, wheel_path):
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if checksums.get(path.name) != actual:
        raise SystemExit(f"signed checksums do not authenticate {path.name}")

magic = b"DEFENSECLAW-PROTECTED-ARTIFACT-V1\n"
def decode(path):
    outer = path.read_bytes()
    if not outer.startswith(magic) or len(outer) == len(magic):
        raise SystemExit(f"invalid protected artifact envelope: {path.name}")
    return bytes(value ^ 0xA5 for value in outer[len(magic):])

wheel = decode(wheel_path)
if not zipfile.is_zipfile(io.BytesIO(wheel)):
    raise SystemExit("protected runtime wheel payload is invalid")
decoded_wheel_path.write_bytes(wheel)

gateway_archive = decode(gateway_path)
with tarfile.open(fileobj=io.BytesIO(gateway_archive), mode="r:gz") as archive:
    candidates = []
    for member in archive.getmembers():
        name = PurePosixPath(member.name)
        if member.isfile() and name.name in {"defenseclaw", "defenseclaw-gateway"}:
            candidates.append(member)
    if len(candidates) != 1:
        raise SystemExit("protected gateway archive must contain exactly one gateway binary")
    member = candidates[0]
    source = archive.extractfile(member)
    if source is None:
        raise SystemExit("protected gateway binary is unreadable")
    payload = source.read()
    if not payload or len(payload) > 256 * 1024 * 1024:
        raise SystemExit("protected gateway binary size is invalid")
    output_path.write_bytes(payload)
    output_path.chmod(0o755)
PYEOF

# The upstream binary is ad-hoc signed; notarization requires Developer ID
# with hardened runtime on every Mach-O inside the bundle.
file "$GATEWAY" | grep -q "Mach-O 64-bit executable arm64" \
    || die "unexpected gateway binary type: $(file "$GATEWAY")"

step "Re-signing gateway: Developer ID + hardened runtime"
codesign -f -o runtime --timestamp -s "$IDENTITY" "$GATEWAY"
codesign --verify --strict --verbose=2 "$GATEWAY"

# ── 3b. Authenticated overrides + hash-locked dependencies ───────────────────
# The wheel alone does not resolve to upstream's tested dependency set: their
# pyproject's [tool.uv] override-dependencies carries CVE-driven floors
# (cryptography, litellm, aiohttp, ...) AND the textual>=8.2.7 override that
# the wheel's skill-scanner pin (textual<8) would otherwise defeat — without
# it a fresh install's TUI crashes (Tabs.get_tab AttributeError). Resolve with
# the authenticated override list during the release build, then ship both the
# list and the resulting hash lock as signed payload provenance.
step "Extracting dependency overrides from authenticated source $SOURCE_COMMIT"
PYPROJECT="$RUNTIME_DIR/pyproject.toml"
curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 \
    -o "$PYPROJECT" "https://raw.githubusercontent.com/${RUNTIME_REPO}/${SOURCE_COMMIT}/pyproject.toml" \
    || die "could not fetch pyproject.toml for authenticated source commit $SOURCE_COMMIT"
OVERRIDES="$RUNTIME_DIR/overrides.txt"
python3 - "$PYPROJECT" > "$OVERRIDES" <<'PYEOF'
import re, sys
text = open(sys.argv[1]).read()
block = re.search(r'override-dependencies\s*=\s*\[(.*?)\n\]', text, re.S)
if not block:
    sys.exit("no override-dependencies block in pyproject.toml")
for line in block.group(1).splitlines():
    line = line.strip()
    if line.startswith('#') or not line:
        continue
    m = re.match(r'"([^"]+)"', line)
    if m:
        print(m.group(1))
PYEOF
grep -q '^textual' "$OVERRIDES" \
    || die "override extraction produced no textual pin — check pyproject format: $(head -3 "$OVERRIDES")"
printf '    %s overrides (incl. %s)\n' "$(wc -l < "$OVERRIDES" | tr -d ' ')" "$(grep '^textual' "$OVERRIDES")"

# Resolve once in the trusted release build, include hashes for every accepted
# distribution, and omit the root package because its separately authenticated
# protected wheel is installed locally with --no-deps. End-user installation
# may download only artifacts whose hashes are sealed into this app bundle.
step "Generating hash-locked macOS arm64 dependency set"
DEPENDENCY_LOCK="$RUNTIME_DIR/runtime-requirements.lock"
RUNTIME_REQUIREMENTS_IN="$RUNTIME_DIR/runtime-requirements.in"
printf 'defenseclaw @ file://%s\n' "$DECODED_WHEEL" > "$RUNTIME_REQUIREMENTS_IN"
uv pip compile "$RUNTIME_REQUIREMENTS_IN" \
    --overrides "$OVERRIDES" \
    --no-emit-package defenseclaw \
    --python-version 3.12 \
    --generate-hashes \
    --no-header \
    --no-annotate \
    --output-file "$DEPENDENCY_LOCK"
grep -q -- '--hash=sha256:' "$DEPENDENCY_LOCK" \
    || die "dependency lock contains no authenticated distribution hashes"
grep -q '^defenseclaw==' "$DEPENDENCY_LOCK" \
    && die "dependency lock unexpectedly contains the separately authenticated root wheel"
grep -Eq '(^|[[:space:]])(@|https?://|file:)' "$DEPENDENCY_LOCK" \
    && die "dependency lock contains an untrusted direct URL or local path"
printf '    %s locked dependency lines\n' "$(grep -c '==' "$DEPENDENCY_LOCK")"

# ── 4. Archive + export the app ──────────────────────────────────────────────
APP_VERSION="$(sed -n 's/.*MARKETING_VERSION = \([0-9.]*\);.*/\1/p' "$REPO_ROOT/$APP_NAME.xcodeproj/project.pbxproj" | head -1)"
[[ -n "$APP_VERSION" ]] || die "could not read MARKETING_VERSION"
step "Building $APP_NAME $APP_VERSION (archive + developer-id export)"

ARCHIVE="$WORK/$APP_NAME.xcarchive"
xcodebuild archive \
    -project "$REPO_ROOT/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -derivedDataPath "$WORK/DerivedData" \
    -quiet

EXPORT_OPTS="$WORK/ExportOptions.plist"
cat > "$EXPORT_OPTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>9R236BB67S</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$WORK/export" \
    -exportOptionsPlist "$EXPORT_OPTS" \
    -quiet
APP_PLAIN="$WORK/export/$APP_NAME.app"
[[ -d "$APP_PLAIN" ]] || die "export did not produce $APP_PLAIN"

# ── 5. Traditional app-only artifact (self-update track) ─────────────────────
if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
    step "Notarizing app-only build"
    PLAIN_ZIP="$WORK/$APP_NAME-plain-notarize.zip"
    ditto -c -k --keepParent "$APP_PLAIN" "$PLAIN_ZIP"
    notarize "$PLAIN_ZIP"
    xcrun stapler staple "$APP_PLAIN"
    spctl -a -t install -vv "$APP_PLAIN"
fi
step "Creating release zip (app-only)"
RELEASE_ZIP="$OUT/$APP_NAME-$APP_VERSION.zip"
ditto -c -k --keepParent "$APP_PLAIN" "$RELEASE_ZIP"

# ── 6. Unified variant: copy, inject RuntimePayload, re-sign ─────────────────
step "Injecting RuntimePayload (runtime $RUNTIME_VERSION)"
APP="$WORK/unified-app/$APP_NAME.app"
mkdir -p "$WORK/unified-app"
ditto "$APP_PLAIN" "$APP"
# The payload variant is re-signed and re-notarized below; drop the app-only
# staple so the unified bundle carries its own ticket, not a stale one.
rm -rf "$APP/Contents/CodeResources" 2>/dev/null || true
PAYLOAD="$APP/Contents/Resources/RuntimePayload"
mkdir -p "$PAYLOAD"
cp "$GATEWAY" "$PAYLOAD/defenseclaw-gateway"
cp "$WHEEL" "$PAYLOAD/$(basename "$WHEEL")"
GATEWAY_SIGNED_SHA="$(shasum -a 256 "$PAYLOAD/defenseclaw-gateway" | awk '{print $1}')"
cp "$OVERRIDES" "$PAYLOAD/overrides.txt"
cp "$DEPENDENCY_LOCK" "$PAYLOAD/runtime-requirements.lock"
cp "$UPGRADE_MANIFEST" "$PAYLOAD/upgrade-manifest.json"
cp "$RUNTIME_ATTESTATION" "$PAYLOAD/runtime-candidate-checksums.txt"
OVERRIDES_SHA="$(shasum -a 256 "$PAYLOAD/overrides.txt" | awk '{print $1}')"
DEPENDENCY_LOCK_SHA="$(shasum -a 256 "$PAYLOAD/runtime-requirements.lock" | awk '{print $1}')"
UPGRADE_MANIFEST_SHA="$(shasum -a 256 "$PAYLOAD/upgrade-manifest.json" | awk '{print $1}')"
RUNTIME_ATTESTATION_SHA="$(shasum -a 256 "$PAYLOAD/runtime-candidate-checksums.txt" | awk '{print $1}')"
python3 - "$PAYLOAD/payload-manifest.json" "$RUNTIME_VERSION" "$RUNTIME_TAG" "$ARCH" \
    "$GATEWAY_SIGNED_SHA" "$(basename "$WHEEL")" "$WHEEL_SHA" "$OVERRIDES_SHA" "$DEPENDENCY_LOCK_SHA" \
    "$UPGRADE_MANIFEST_SHA" "$RUNTIME_ATTESTATION_SHA" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" <<'PYEOF'
import json
from pathlib import Path
import sys

(
    path, version, tag, arch, gateway_sha, wheel_name, wheel_sha,
    overrides_sha, dependency_lock_sha, policy_sha, attestation_sha, built_at,
) = sys.argv[1:]
payload = {
    "runtime_version": version,
    "runtime_tag": tag,
    "arch": arch,
    "gateway": {
        "file": "defenseclaw-gateway",
        "sha256": gateway_sha,
    },
    "wheel": {"file": wheel_name, "sha256": wheel_sha},
    "overrides": {"file": "overrides.txt", "sha256": overrides_sha},
    "dependency_lock": {
        "file": "runtime-requirements.lock",
        "sha256": dependency_lock_sha,
    },
    "upgrade_manifest": {"file": "upgrade-manifest.json", "sha256": policy_sha},
    "runtime_attestation": {
        "file": "runtime-candidate-checksums.txt",
        "sha256": attestation_sha,
    },
    "built_at": built_at,
}
Path(path).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PYEOF

step "Re-signing app bundle over the injected payload"
# Preserve entitlements if the export produced any (currently none).
ENTITLEMENTS="$WORK/app-entitlements.plist"
if codesign -d --entitlements - --xml "$APP" > "$ENTITLEMENTS" 2>/dev/null && [[ -s "$ENTITLEMENTS" ]]; then
    codesign -f -o runtime --timestamp --entitlements "$ENTITLEMENTS" -s "$IDENTITY" "$APP"
else
    codesign -f -o runtime --timestamp -s "$IDENTITY" "$APP"
fi
codesign --verify --strict --deep --verbose=2 "$APP"

# ── 7. Notarize + staple the unified app ─────────────────────────────────────
if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
    step "Notarizing unified app"
    APP_ZIP="$WORK/$APP_NAME-unified-notarize.zip"
    ditto -c -k --keepParent "$APP" "$APP_ZIP"
    notarize "$APP_ZIP"
    xcrun stapler staple "$APP"
    spctl -a -t install -vv "$APP"
fi

# ── 8. DMG: stage, create, sign, notarize, staple ────────────────────────────
step "Creating DMG"
STAGE="$WORK/dmg-stage"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/$APP_NAME-$APP_VERSION.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --timestamp -s "$IDENTITY" "$DMG"

if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
    step "Notarizing DMG"
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    spctl -a -t open --context context:primary-signature -vv "$DMG"
fi

step "Done"
printf 'App version   : %s\n' "$APP_VERSION"
printf 'Runtime       : %s\n' "$RUNTIME_TAG"
printf 'DMG           : %s (%s)\n' "$DMG" "$(du -h "$DMG" | cut -f1)"
printf 'Release zip   : %s (%s)\n' "$RELEASE_ZIP" "$(du -h "$RELEASE_ZIP" | cut -f1)"
if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
    printf '\nWARNING: SKIP_NOTARIZE=1 — artifacts in %s are NOT notarized/stapled. DO NOT PUBLISH.\n' "$OUT"
else
    shasum -a 256 "$DMG" "$RELEASE_ZIP"
fi
