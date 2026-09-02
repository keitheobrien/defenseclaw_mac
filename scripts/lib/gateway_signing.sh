#!/usr/bin/env bash

GATEWAY_IDENTIFIER="com.cisco.defenseclaw.gateway"
GATEWAY_IDENTIFIER_REQUIREMENT="=identifier \"$GATEWAY_IDENTIFIER\""

verify_gateway_signature() {
    local gateway_path="$1"
    local expected_team_id="${2:-}"
    local details

    if [[ ! -f "$gateway_path" ]]; then
        printf 'Gateway executable is missing: %s\n' "$gateway_path" >&2
        return 1
    fi

    if ! /usr/bin/codesign --verify --strict --verbose=4 \
        -R "$GATEWAY_IDENTIFIER_REQUIREMENT" "$gateway_path"; then
        printf 'Gateway signature or identifier is invalid: %s\n' "$gateway_path" >&2
        return 1
    fi

    if ! details="$(/usr/bin/codesign -dvvv "$gateway_path" 2>&1)"; then
        printf 'Gateway signing metadata is unreadable: %s\n' "$gateway_path" >&2
        return 1
    fi

    if ! grep -Fqx "Identifier=$GATEWAY_IDENTIFIER" <<<"$details"; then
        printf 'Gateway has the wrong signing identifier: %s\n' "$gateway_path" >&2
        return 1
    fi

    if ! grep -Eq '^CodeDirectory .* flags=.*\([^)]*runtime[^)]*\)' <<<"$details"; then
        printf 'Gateway is not signed with hardened runtime: %s\n' "$gateway_path" >&2
        return 1
    fi

    if [[ -n "$expected_team_id" ]] \
        && ! grep -Fqx "TeamIdentifier=$expected_team_id" <<<"$details"; then
        printf 'Gateway is not signed by Team ID %s: %s\n' "$expected_team_id" "$gateway_path" >&2
        return 1
    fi
}

verify_gateway_sha256() {
    local gateway_path="$1"
    local expected_sha256="$2"
    local actual_sha256

    actual_sha256="$(/usr/bin/shasum -a 256 "$gateway_path" | /usr/bin/awk '{print $1}')"
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        printf 'Gateway SHA-256 mismatch for %s: expected %s, got %s\n' \
            "$gateway_path" "$expected_sha256" "$actual_sha256" >&2
        return 1
    fi
}
