# DefenseClawMac 1.1.30 release verification

## Release scope

Read-only OpenShell policy visibility and monitoring from PR #35. Effective/base policy, DefenseClaw provenance, revision comparisons, destinations, filtered logs, pause, and redacted export are included. Policy editing and companion runtime changes are excluded.

The app version is 1.1.30, build 1. The unified installer targets the latest published DefenseClaw runtime, 1.0.1. The app-only updater ZIP preserves the existing runtime.

## Targets and evidence

- Feature commit: `043937afdb8195e34acae317c13a56f174789365`; release metadata and baseline changes follow on the same PR.
- Runtime executable: `/Users/kobrien/.local/bin/defenseclaw`, resolving to `/Users/kobrien/.defenseclaw/.venv/bin/defenseclaw`, reporting 1.0.1.
- Exact runtime release source: `00ef714b8a47f3ba90dad69b91dc8aa40c735057`. Its source metadata reports 1.0.0; the released wheel and executable report 1.0.1. Installed dependencies were checked against the installed package metadata.
- OpenShell: 0.1.3. Live read checks used sandbox `docs-9240`, gateway `openshell`, workspace `default`.
- Latest upstream main observed separately: `a1b914493e746c080a9526401baf01267d90eae3`. The release is certified against the published runtime, not unreleased mainline changes.
- Xcode 27.0 (27A266a).

## Results

| Check | Result |
| --- | --- |
| Published-runtime compatibility audit | PASS: 251 command entries, schema 9, 24 setup sections, installed dependencies, help contracts and packaging protocols |
| Standalone regression scripts | PASS: 43 scripts; the additional opt-in native script was run separately |
| Native window layout | PASS: native and accessibility selection, close/reopen, resize, asynchronous hydration and 20-second dwell scenarios; see native-layout.log |
| Inspection checks | PASS: 63 checks including six live reads; see the linked inspection report |
| Native inspection screens | PASS: eight fixture renders including policy layers/history, network, logs, stale state and recovery |
| Universal Debug compile | PASS |
| Unreleased mainline comparison | BLOCKED by source-download timeouts; see mainline-comparison.md. No claim of parity with unreleased main |
| Source differences | Reviewed all six additions/changes from PR #35; recorded explicit reasons and exact hashes; 46 total standalone differences match the published-release baseline |
| Live policy mutation and controlled allow/block traffic | NOT TESTED; excluded from the read-only scope |
| Fresh installation or replacing the installed app/runtime | NOT TESTED; release preparation preserves live state |

The global-policy command returned exit 1 on this host and is shown as unavailable; a failed read is not proof of an absent global policy. Native test compilation emitted pre-existing deprecated AppKit accessibility API warnings; both scenarios passed.

Signing, notarization, strict payload validation, publication and fresh-download verification are performed on merged mainline before the release is marked latest. Their artifact hashes and distribution details are retained in the GitHub release notes.

[Compatibility audit](compatibility-audit.md) · [Phase 1 and 2 evidence and screenshots](../OPENSHELL_INSPECTION_2026-10-15.md)
