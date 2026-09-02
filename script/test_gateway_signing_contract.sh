#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-gateway-signing-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
MODULE_CACHE="$BUILD_DIR/ModuleCache"
mkdir -p "$MODULE_CACHE"

source "$ROOT/scripts/lib/gateway_signing.sh"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" xcrun swiftc \
    -module-cache-path "$MODULE_CACHE" \
    -parse-as-library \
    "$ROOT/Tests/GatewaySigningFixture.swift" \
    -o "$BUILD_DIR/gateway-fixture"

cp "$BUILD_DIR/gateway-fixture" "$BUILD_DIR/correct-gateway"
cp "$BUILD_DIR/gateway-fixture" "$BUILD_DIR/wrong-gateway"

/usr/bin/codesign -f -s - -o runtime \
    --identifier "$GATEWAY_IDENTIFIER" "$BUILD_DIR/correct-gateway"
/usr/bin/codesign -f -s - -o runtime \
    --identifier "com.example.wrong-gateway" "$BUILD_DIR/wrong-gateway"

verify_gateway_signature "$BUILD_DIR/correct-gateway"
CORRECT_SHA256="$(shasum -a 256 "$BUILD_DIR/correct-gateway" | awk '{print $1}')"
verify_gateway_sha256 "$BUILD_DIR/correct-gateway" "$CORRECT_SHA256"
if verify_gateway_signature "$BUILD_DIR/wrong-gateway" 2>/dev/null; then
    printf 'Gateway verifier accepted the wrong signing identifier\n' >&2
    exit 1
fi
if verify_gateway_sha256 "$BUILD_DIR/correct-gateway" \
    "0000000000000000000000000000000000000000000000000000000000000000" 2>/dev/null; then
    printf 'Gateway verifier accepted the wrong SHA-256\n' >&2
    exit 1
fi

printf 'Gateway signing contract tests passed\n'
