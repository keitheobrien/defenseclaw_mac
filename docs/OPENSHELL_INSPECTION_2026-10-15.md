# OpenShell inspection and monitoring — phases 1 and 2

## Scope and behavior

Selecting a sandbox opens **Overview**, **Policy**, **Network**, and **Activity & Logs**. Existing reviewed lifecycle actions remain in Overview. This addition reads policy and monitoring state; it does not edit policies, change gateway configuration, install software, or start sandboxes.

- **Overview:** sandbox health, observed policy enforcement, recent failures, provider-login guidance, and project-copy reminders.
- **Policy:** effective OpenShell policy, base policy, resolved DefenseClaw settings with source/organization provenance, gateway-global policy when readable, and stored revision comparisons against the current base. Search includes setting names, values, and sources; selecting a field reveals its full displayed value.
- **Network:** observed destinations and their returned metadata, related DefenseClaw events, and effective OpenShell network permissions. A destination observation is distinct from permission to reach it.
- **Activity & Logs:** DefenseClaw activity and OpenShell sandbox/gateway logs with source, severity, decision, time, and text filters; event details and related-policy navigation; pause/resume; redacted filtered diagnostic export.

OpenShell requests name the gateway, workspace, and sandbox explicitly. Missing identities disable reads. Calls use argument arrays through the existing runner and stop after 12 seconds. Selection/installation changes invalidate old replies. Reads yield to runtime upgrades. Background inspection output is not retained as raw Activity command output.

Logs are limited to the last 15 minutes and 200 lines per OpenShell source, polled every five seconds while the inspector is mounted and not paused. Policy, history, and destinations refresh every 30 seconds. History pages contain 20 revisions, capped at 200. Failed reads retain the last successful snapshot with a stale warning; enforcement is labeled **Last observed**. Different effective/base revision numbers are marked inconsistent until refreshed. Unknown or unavailable policy state is not presented as successful enforcement or an empty policy.

Structured logs use an allowlisted projection. Known credential fields, URL credentials/query strings, private-key blocks, environment dumps, and request/response payloads are redacted or omitted before display/export. Free-form log redaction recognizes patterns; it cannot promise to detect an arbitrary unlabeled secret. Export includes source freshness and coverage limits and is not a complete audit history.

## Verified targets

| Target | Identity |
| --- | --- |
| Mac checkout | `kobrien/openshell-policy-monitoring`, based on `755cec0ca8cd77da0f086f0ca80d62320b9e9921` |
| App version/build | 1.1.29 / 1; no release version change |
| Selected runtime | `/Users/kobrien/.local/bin/defenseclaw`, resolving to `/Users/kobrien/.defenseclaw/.venv/bin/defenseclaw`; 1.0.1 |
| App selection | No binary/config preference overrides; default local installation |
| OpenShell | 0.1.3, `/opt/homebrew/bin/openshell` |
| Live read target | Existing sandbox `docs-9240`, gateway `openshell`, workspace `default` |
| Runtime release source | `00ef714b8a47f3ba90dad69b91dc8aa40c735057`, fetched into a disposable checkout; source metadata says 1.0.0 while released executable/package says 1.0.1 |
| Upstream main observed | `14f245d2023e53a01574d1000b23371d333990c7`; this is not a full compatibility certification for that newer commit |
| User runtime source checkout | `1173ebed4f9bc30036a039ace8eb8f58dbd40884`, preserved unchanged |
| Compiler | Xcode 27.0, build 27A266a; standard Debug app build succeeded for arm64 and x86_64 |

## Verification matrix

| Feature/check | Result and evidence |
| --- | --- |
| Identity validation, decoder bounds, policy scope, provenance, revision status/diff | **PASS** focused tests, including different-sandbox refusal and effective/base revision mismatch |
| History pagination, cancellation, target changes, upgrade read guard | **PASS** focused store/process tests plus source review of AppState guard |
| Redaction and diagnostic serialization | **PASS** known-secret, escaped-quote, structured-payload, URL, coverage and stale-status tests |
| Filtering, log classification, pause | **PASS** model/store tests; unknown timestamps excluded from finite time ranges; hostname text does not change allowed/blocked classification |
| Native screens/details | **PASS** eight Xcode-built fixture renders: four tabs, DefenseClaw/Base/History layers, and stale policy; native table row selection and window resize exercised |
| Fixture policy/history/network/log integration | **PASS** distinct base/effective rules, stored revision diff, two destinations, allowed/blocked/error logs, partial outage and recovery |
| Installed runtime read contracts | **PASS** actual policy explanation, effective/base policy, revision list/get, destination response, and bounded logs for the selected sandbox |
| Gateway-global policy on this host | **BLOCKED** command returned exit 1; shown as unavailable. This does not establish that no global policy exists. Available global policy decoding is fixture-covered |
| Existing sandbox regression | **PASS** against the matching release source; the older user checkout has a pre-existing no-asks wording mismatch |
| CLI cancellation, AppState signal safety, main-window lifecycle | **PASS** existing regression scripts |
| Normal Xcode build | **PASS** universal Debug app, ad-hoc signed for development; no Swift compiler errors or warnings. Xcode emitted the existing no-AppIntents metadata-extraction warning |
| Compatibility contract audit | Registry **251**, schema **9**, setup sections **24**, installed dependencies and probed help contracts **PASS**. Overall audit **FAIL** only for six intentional source differences awaiting baseline review; baseline was not rewritten |
| Live policy mutation or controlled allow/block traffic | **NOT TESTED**; outside these read-only phases |
| User-driven filter/pause/export-save interactions | **NOT TESTED** end-to-end; underlying filtering, pause, and export serialization are tested, native controls rendered |
| Installed release replacement, release packaging/notarization | **NOT TESTED**; no installation or release requested |

The phases 1 and 2 scope was reverified after removing the policy editor: the focused suite passed **63 checks**, including six live read checks, all eight native fixture renders passed, and the universal Debug build succeeded. The inspector requires no new runtime policy-write interface. The native fixture uses a separate bundle identity, synthetic CLI/gateway, and disabled automatic gateway start. It does not certify behavior of the installed `/Applications/DefenseClawMac.app`.

The intentional app-source changes are `App/AppState.swift`, `DataLayer/SandboxModels.swift`, `DataLayer/SandboxInspection.swift`, `DataLayer/SandboxInspectionStore.swift`, `Features/SandboxesView.swift`, and `Features/SandboxInspectorView.swift`. The compatibility baseline remains the last reviewed release baseline. The audit's source-version warning is the previously documented 1.0.0 source metadata / 1.0.1 release skew, not evidence that the installed executable was downgraded.

## Reproduction

```bash
# Pure tests; omit the environment variable to avoid live integration reads.
DEFENSECLAW_INSPECTION_LIVE_SANDBOX=docs-9240 ./script/test_sandbox_inspection.sh

DEFENSECLAW_UPSTREAM_ROOT=/path/to/exact-release-source ./script/test_sandbox_models.sh
./script/test_cli_cancellation.sh
./script/test_app_state_signal_safety.sh
./script/test_main_window_lifecycle.sh

DEFENSECLAW_TEST_VENV=/Users/kobrien/.defenseclaw/.venv \
  python3 script/test_panel_native_smoke.py --run-inspection-gui

xcodebuild -project DefenseClawMac.xcodeproj -scheme DefenseClawMac \
  -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath /private/tmp/DefenseClawMac-openshell-Xcode-DerivedData \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build

git diff --check
```

Development app: `/private/tmp/DefenseClawMac-openshell-Xcode-DerivedData/Build/Products/Debug/DefenseClawMac.app`. No installed app, selected runtime, live policy, source checkout, or gateway lifecycle was changed.

## Retained evidence

- [Focused and live checks](openshell-inspection/inspection-tests.log), [native checks](openshell-inspection/native-tests.log), [compatibility audit](openshell-inspection/compatibility-audit.md).
- [Sandbox regression](openshell-inspection/sandbox-regression.log), [cancellation](openshell-inspection/cancellation.log), [state safety](openshell-inspection/state-safety.log), [window lifecycle](openshell-inspection/lifecycle.log).
- [Before: user-supplied sandbox screen](../images/openshell-inspection/before.png).
- After, synthetic native fixtures: [policy](../images/openshell-inspection/policy.png), [provenance](../images/openshell-inspection/provenance.png), [history](../images/openshell-inspection/history.png), [network](../images/openshell-inspection/network.png), [activity](../images/openshell-inspection/activity.png), [stale state](../images/openshell-inspection/stale.png).
