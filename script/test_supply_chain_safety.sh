#!/bin/bash
# Copyright 2026 Cisco Systems, Inc. and its affiliates
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

bash -n \
    "$ROOT/scripts/build_unified_dmg.sh" \
    "$ROOT/scripts/lib/gateway_signing.sh" \
    "$ROOT/scripts/verify_unified_release_artifact.sh"

python3 - "$ROOT" <<'PYEOF'
from pathlib import Path
import sys

root = Path(sys.argv[1])
build = (root / "scripts/build_unified_dmg.sh").read_text(encoding="utf-8")
gateway_signing = (root / "scripts/lib/gateway_signing.sh").read_text(encoding="utf-8")
runtime = (root / "DefenseClawMac/DataLayer/RuntimeInstaller.swift").read_text(encoding="utf-8")
first_run = (root / "DefenseClawMac/Features/FirstRunView.swift").read_text(encoding="utf-8")
updater = (root / "DefenseClawMac/DataLayer/UpdateChecker.swift").read_text(encoding="utf-8")

checks = {
    "release source map is downloaded": 'release-source-map.json' in build,
    "release source map is checksum verified": 'verify_sha256 "$RELEASE_SOURCE_MAP"' in build,
    "pyproject is read from the authenticated source commit": '${SOURCE_COMMIT}:pyproject.toml' in build,
    "mutable runtime tag does not select pyproject": '${RUNTIME_TAG}/pyproject.toml' not in build,
    "dependency lock includes artifact hashes": '--generate-hashes' in build,
    "dependency lock authenticates approved direct references": 'validate_dependency_lock.py' in build,
    "dependency lock no longer uses a blanket URL ban": "untrusted direct URL or local path" not in build,
    "dependency lock excludes the separately authenticated root wheel": '--no-emit-package defenseclaw' in build,
    "dependency lock is embedded": 'runtime-requirements.lock' in build,
    "runtime requires dependency hashes": '"--require-hashes"' in runtime,
    "runtime installs only from the signed dependency lock": '"--requirements", materializedDependencyLock' in runtime,
    "runtime installs authenticated root wheel without re-resolving dependencies": '"--no-deps", materializedWheel' in runtime,
    "runtime does not apply unlocked overrides": 'wheelArguments += ["--overrides"' not in runtime,
    "runtime retains authenticated override provenance": 'destination: materializedDependencyOverrides' in runtime,
    "runtime verifies override provenance before retaining it": 'expectedSourceSHA256: overridesSHA256' in runtime,
    "runtime cleans override provenance when fresh installation fails": (
        'if !retainMaterializedDependencyOverrides,' in runtime
        and 'let materializedDependencyOverridesIdentity {' in runtime
        and 'materializedDependencyOverrides,\n' in runtime
    ),
    "first-run no longer references mutable main": 'defenseclaw/main/scripts' not in first_run,
    "updater pins Apple Team ID": 'expectedTeamIdentifier = "9R236BB67S"' in updater,
    "updater enforces designated requirement": '"-R=\\(Self.expectedCodeRequirement)"' in updater,
    "self-update ZIP omits AppleDouble companion root": 'ditto -c -k --norsrc --keepParent "$APP_PLAIN" "$RELEASE_ZIP"' in build,
    "self-update ZIP validates its single-root layout": 'validate_self_update_zip "$RELEASE_ZIP" "$APP_NAME.app"' in build,
    "self-update ZIP validates its notarization ticket after extraction": 'xcrun stapler validate "$ZIP_CHECK/$APP_NAME.app"' in build,
    "self-update ZIP passes Gatekeeper after extraction": 'spctl -a -t install -vv "$ZIP_CHECK/$APP_NAME.app"' in build,
    "gateway signing helper fixes the installer-required identifier": 'GATEWAY_IDENTIFIER="com.cisco.defenseclaw.gateway"' in gateway_signing,
    "runtime installer uses the exact release gateway requirement": '#"=identifier "com.cisco.defenseclaw.gateway""#' in runtime,
    "gateway signer assigns the fixed identifier": '--identifier "$GATEWAY_IDENTIFIER"' in gateway_signing,
    "release build uses the shared gateway signer": 'sign_gateway_for_release "$GATEWAY" "$IDENTITY"' in build,
    "decoded gateway is contract verified": 'verify_gateway_signature "$GATEWAY" "$TEAM_ID"' in build,
    "embedded gateway is contract verified": 'verify_gateway_signature "$PAYLOAD/defenseclaw-gateway" "$TEAM_ID"' in build,
    "staged gateway is contract verified": 'verify_gateway_signature "$STAGED_GATEWAY" "$TEAM_ID"' in build,
    "finished DMG payload is verified": 'verify_unified_release_artifact.sh" "$DMG"' in build,
}

failed = [label for label, ok in checks.items() if not ok]
if failed:
    for label in failed:
        print(f"FAILED: {label}", file=sys.stderr)
    raise SystemExit(1)
print("Supply-chain safety tests passed")
PYEOF
