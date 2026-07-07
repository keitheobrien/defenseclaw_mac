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
#   RUNTIME_TAG=v0.8.3   pin the runtime release (default: latest)
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

rm -rf "$WORK"
mkdir -p "$RUNTIME_DIR" "$OUT"

# ── 1. Resolve + download the runtime release ────────────────────────────────
RUNTIME_TAG="${RUNTIME_TAG:-$(gh release view --repo "$RUNTIME_REPO" --json tagName -q .tagName)}"
[[ -n "$RUNTIME_TAG" ]] || die "could not resolve latest $RUNTIME_REPO release tag"
RUNTIME_VERSION="${RUNTIME_TAG#v}"
step "Runtime release: $RUNTIME_TAG"

# Exact goreleaser-deterministic names, not globs: the version-embedded
# basename is what binds the pinned tag to the signed checksums.txt entries —
# a genuinely-signed triplet replayed from an older release carries the old
# version in its filenames and can't satisfy these names or their checksum
# lookups.
TARBALL="$RUNTIME_DIR/defenseclaw_${RUNTIME_VERSION}_darwin_${ARCH}.tar.gz"
WHEEL="$RUNTIME_DIR/defenseclaw-${RUNTIME_VERSION}-py3-none-any.whl"
gh release download "$RUNTIME_TAG" --repo "$RUNTIME_REPO" --dir "$RUNTIME_DIR" \
    --pattern "$(basename "$TARBALL")" \
    --pattern "$(basename "$WHEEL")" \
    --pattern "checksums.txt" \
    --pattern "checksums.txt.sig" \
    --pattern "checksums.txt.pem"

[[ -f "$TARBALL" && -f "$WHEEL" ]] \
    || die "release $RUNTIME_TAG did not provide $(basename "$TARBALL") + $(basename "$WHEEL") — version/name mismatch"
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
    --certificate-identity-regexp "^https://github.com/${RUNTIME_REPO}/.+" \
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
verify_sha256 "$TARBALL"
verify_sha256 "$WHEEL"
TARBALL_SHA="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
WHEEL_SHA="$(shasum -a 256 "$WHEEL" | awk '{print $1}')"

# ── 3. Extract + re-sign the gateway ─────────────────────────────────────────
# The upstream Go binary is ad-hoc signed; notarization requires Developer ID
# with hardened runtime on every Mach-O inside the bundle.
step "Extracting gateway from tarball"
EXTRACT="$RUNTIME_DIR/extract"
mkdir -p "$EXTRACT"
tar -xzf "$TARBALL" -C "$EXTRACT"
GATEWAY="$(find "$EXTRACT" -maxdepth 2 -type f \( -name defenseclaw -o -name defenseclaw-gateway \) | head -1)"
[[ -n "$GATEWAY" ]] || die "no defenseclaw gateway binary found in tarball"
file "$GATEWAY" | grep -q "Mach-O 64-bit executable arm64" \
    || die "unexpected gateway binary type: $(file "$GATEWAY")"

step "Re-signing gateway: Developer ID + hardened runtime"
codesign -f -o runtime --timestamp -s "$IDENTITY" "$GATEWAY"
codesign --verify --strict --verbose=2 "$GATEWAY"

# ── 3b. Dependency overrides from the upstream pyproject ─────────────────────
# The wheel alone does not resolve to upstream's tested dependency set: their
# pyproject's [tool.uv] override-dependencies carries CVE-driven floors
# (cryptography, litellm, aiohttp, ...) AND the textual>=8.2.7 override that
# the wheel's skill-scanner pin (textual<8) would otherwise defeat — without
# it a fresh install's TUI crashes (Tabs.get_tab AttributeError). Ship the
# tag's override list in the payload; the installer applies it via
# `uv pip install --overrides`, reproducing upstream's own resolution.
step "Extracting dependency overrides from upstream pyproject ($RUNTIME_TAG)"
PYPROJECT="$RUNTIME_DIR/pyproject.toml"
curl -fsSL --proto '=https' --tlsv1.2 \
    -o "$PYPROJECT" "https://raw.githubusercontent.com/${RUNTIME_REPO}/${RUNTIME_TAG}/pyproject.toml" \
    || die "could not fetch pyproject.toml for $RUNTIME_TAG"
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
OVERRIDES_SHA="$(shasum -a 256 "$PAYLOAD/overrides.txt" | awk '{print $1}')"
cat > "$PAYLOAD/payload-manifest.json" <<JSON
{
  "runtime_version": "$RUNTIME_VERSION",
  "runtime_tag": "$RUNTIME_TAG",
  "arch": "$ARCH",
  "gateway": {
    "file": "defenseclaw-gateway",
    "sha256": "$GATEWAY_SIGNED_SHA",
    "upstream_tarball_sha256": "$TARBALL_SHA"
  },
  "wheel": {
    "file": "$(basename "$WHEEL")",
    "sha256": "$WHEEL_SHA"
  },
  "overrides": {
    "file": "overrides.txt",
    "sha256": "$OVERRIDES_SHA"
  },
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON

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
