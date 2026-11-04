# DefenseClawMac / runtime 1.0.5 TUI audit

Date: 30 October 2026 (America/New_York)

## Result and limits

The audit found and repaired nine confirmed native-app contract or reporting gaps. The final standalone regression run has **45 PASS, 0 FAIL, 1 SKIP**; the final production-source Debug build succeeds. All **249** command-registry entries match the published 1.0.5 TUI registry, and the native configuration editor loads all **25** sections from the installed 1.0.5 runtime. The supported setup connector roster now includes Kiro and excludes retired OpenHands and OmniGent setup.

This is a tested source patch, not a signed release or proof that every live integration works. The historical source-baseline gate still fails, and the live local-observability destination reports degraded delivery. Those are explicit remaining findings; neither is hidden by the passing functional tests.

## Exact targets

| Target | Identity |
| --- | --- |
| Runtime release/tag | `1.0.5`, commit `ede59bd77ff633f5014dff7964631e42088697e7` |
| Installed CLI | `/Users/kobrien/.local/bin/defenseclaw` → `/Users/kobrien/.defenseclaw/.venv/bin/defenseclaw`, 1.0.5 |
| Installed gateway | 1.0.5, same release commit, built `2026-10-30T15:46:18Z` |
| Latest upstream main checked | `54ad050a00e62d9d1d65c5e96c820443686e32e7` |
| Release versus current main | No file differences in `cli/defenseclaw/tui` or `macos/DefenseClawMac` at these two commits |
| Current Mac app main / audit starting point | `6ce825fc9022477b371455d87834b732c1343210` |
| Installed release app | `/Applications/DefenseClawMac.app`, 1.1.34, build 1; preserved |
| Audit branch | `kobrien/audit/runtime-1.0.5` |
| Audit checkout | `/Users/kobrien/git/defenseclawmac-runtime-1.0.5` |
| Selected live installation | User default; `~/.defenseclaw/config.yaml`, `~/.defenseclaw/audit.db`, loopback API port 18970 |
| Config schema | 9 |
| Native test target | Separate ad-hoc Debug bundle `com.keitheobrien.DefenseClawMac.ParityAudit` |

The source tag's `pyproject.toml` still declares 1.0.0. The executable reports 1.0.5 and its gateway commit matches the published tag. The release workflow stamps artifact versions separately. The audit tool correctly warns about this source-metadata skew and checks the installed distribution's own dependency metadata; it must not infer an installed downgrade from the source version field.

The original checkout was on `kobrien/security-gateway-listener-1.1.33`, commit `bcfd05b1d4054a8b177590e15fd7a0357d0de673`, with pre-existing Runtime-view edits, deleted compatibility-skill files, and an untracked reinstall report. All were preserved. An isolated branch from current Mac main was used instead. The runtime source checkout's unrelated changes were also preserved; an exact detached release worktree supplied the comparison source.

## Confirmed fixes

1. **Current command registry.** Regenerated the registry from the exact 1.0.5 TUI source: 249 entries. Removed the retired `setup openhands` and `setup omnigent` commands. Runtime capability filtering remains in place; the synthetic runtime exposes 247 palette entries, which is distinct from the full source registry count.
2. **Kiro setup and discovery.** Added Kiro to native first-run selection, Connector Setup, the offline config editor, and the fallback connector roster. Removed the retired setup choices from those rosters. Added Kiro's read-only user MCP source, `~/.kiro/settings/mcp.json`. Kiro steering/spec documents remain distinct from SKILL.md inventories; no skill directories are invented. Historical readers and display names remain available for older configurations.
3. **Runtime coverage truth.** Matched the TUI's OFF, STARTING, WATCHING, DEGRADED, and HEALTHY interpretation. A running plane with a stated coverage limit is `partial`; a plane that was not selected is `off`. Coverage reasons are visible, including for running planes. A genuinely unavailable selected plane remains degraded.
4. **Observability health decoding.** The old app assumed legacy string signals and routing/delivery objects. Current health uses a destination kind, signal array, real health state, counters, queue, and circuit state. The app now distinguishes healthy SQLite from degraded OTLP, enabled policy from actual delivery health, and shows delivered/dropped/rejected/retried counts plus queue occupancy and failure context. Configured endpoints remain redacted; unreported endpoints are explicit. Routine recovery reasons do not remain warnings.
5. **Human approval consequences.** Native previews now reuse the selected runtime's `hilt_change_modal`. Broad approval changes inspect every affected connector when deciding whether protection is weakened. A global default already set to off no longer conceals a connector override that would lose approval. Per-connector commands remain scoped.
6. **Refused sandbox stops.** Exit 5 now explicitly reports that the sandbox keeps running. An unsynced disk and a full disk receive different recovery guidance. The app does not silently discard unsynced work. CLI output remains in Activity, and the snapshot is refreshed after the result.
7. **Connector drift notices.** Alias spelling/case differences and a live primary connector that belongs to the configured multi-connector roster no longer create false drift warnings. A different unregistered connector still warns.
8. **Applied configuration generation.** Overview now uses `policy.config_generation`, as the TUI does. It no longer displays the gateway-local `policy.generation`, which resets on restart. Unknown config generations are omitted instead of substituting that unrelated counter.
9. **Activity side effects.** Successful read-only commands no longer infer configuration/state changes from a `setup` or `config` command prefix. Explicit caller-supplied read effects still work, and successful mutations retain their effects. Native verification reproduced the old false “Configuration updated” label for `setup redaction status` and confirmed it is absent after the fix.

## Verification

### Automated

- [Final test results](runtime-1.0.5/evidence/test-results.json): all 46 `script/test_*.sh` scripts were invoked with the installed 1.0.5 Python interpreter selected for runtime-backed tests. 45 pass; `test_inspector_native_layout.sh` intentionally skips without its separate `--run-gui` opt-in. Its automated dwell/resize cases were not run in this audit.
- [Final Debug build](runtime-1.0.5/evidence/debug-build.log): production sources compile with ad-hoc signing and temporary DerivedData.
- Regression coverage exercises destination health/counters/queues and endpoint redaction, runtime partial/off/degraded states, broad versus scoped approval weakening, persistent versus gateway-local generation, Kiro selection and MCP paths, retired commands, alias/roster drift, refused stops, and read-only Activity effects.
- Runtime package dependencies satisfy the installed distribution's declared requirements. CLI help contracts, current setup catalog, legacy protected packaging, and authenticated 1.x flat-payload packaging checks pass.
- `git diff --check` passes.

The compatibility report is retained verbatim: [contract audit](runtime-1.0.5/evidence/contract-audit.md). Its remaining failures are the historical source-baseline checks described below; it is not presented as an overall green audit.

### Native UI and disposable state

Native UI interactions used computer-use automation. The test app was built from a temporary source copy with a separate bundle ID. Only that copy injects the existing listener-trust test seam to accept the synthetic Python gateway; production listener validation remains unchanged. The fixture supplies a temporary config, SQLite database, log files, mock CLI, and loopback API. Automatic gateway startup and notifications were disabled. The installed runtime interpreter supplies read-only catalog/model behavior. No real setup or enforcement mutation was applied.

- All 16 panels opened. The fixture supplies normal, empty, and degraded states; an empty fixture is not counted as successful integration.
- All 23 setup forms opened. Twenty valid default forms reached Review; LLM, Webhooks, and Registries remained blocked by required inputs. A separate Kiro selection reached a correct `setup kiro` review. No Apply button was pressed.
- The config editor loaded `runtime catalog 1.0.5 · 25 sections`. Admission Defaults appeared with Allow List Bypass on by default.
- All seven policy views opened. The real runtime-backed bridge regression suite separately verifies broad/scoped approval consequences and weakening flags.
- All four Preferences tabs opened. The live installed app's Connection tab also confirmed the selected user installation and port before probing it.
- Gateway, Verdicts, Otel, and Watchdog log tabs displayed 2, 2, 4, and 1 fixture rows respectively. A no-match search produced zero matching rows; clearing it restored the rows.
- A fixture `version` command ran from the palette, displayed 1.0.5, exited 0, and appeared with its output in Activity.
- Alerts and Audit row selection opened their details. Catalog rows and action surfaces rendered; execution of their individual modifying actions was not exercised.
- Final native observations confirmed WATCHING/partial/off runtime labels, healthy SQLite versus degraded OTLP with queue/loss information, config generation 9 while the fixture's gateway-local counter is 1, Kiro setup choices, and the corrected read-only Activity effect.

[Panel checks](runtime-1.0.5/evidence/fixture-checks.json), [form checks](runtime-1.0.5/evidence/form-checks.json), [policy views](runtime-1.0.5/evidence/policy-checks.json), [Preferences](runtime-1.0.5/evidence/preferences.json), and [log checks](runtime-1.0.5/evidence/log-checks.json) retain the scoped observations.

### Per-feature matrix

PASS applies only to the stated operation. “Native fixture” does not certify a real external service or mutation.

| Surface | Verified result | Not tested / remaining limit |
| --- | --- | --- |
| Overview | PASS native fixture status, roster, destination delivery, applied generation; live read-only health also inspected | Gateway lifecycle, live collector repair, full remote delivery |
| Alerts | PASS fixture rows and selected detail; live panel loads; canonical queue tests pass | Acknowledging a real alert; every live filter combination |
| Logs | PASS four fixture sources, no-match search and restoration; live panel loads | Continuous long-duration follow, every live preset, downstream export |
| Audit | PASS fixture rows and selected detail; bounded live SQLite schema/row read | Exporting user data, large-history pagination, every filter |
| Activity | PASS palette version execution/output/exit status; read-only side-effect regression and native verification | Real external command cancellation; subprocess cancellation is tested separately |
| Skills | PASS fixture catalog/action surface and live read-only load; catalog safety tests | Real install/block/allow/scan/quarantine |
| MCPs | PASS fixture catalog/action surface, Kiro fallback paths, and live read-only load | Real server changes or connections |
| Plugins | PASS fixture catalog/action surface and parser/safety tests | A complete live asynchronous load was not separately established; real changes/scans |
| Tools | PASS fixture policy table/action surface and policy contracts | Persisting real block/allow rules |
| Policies | PASS seven native views and selected-runtime bridge regression tests | Applying real policy, pack, threshold, or approval changes |
| Sandboxes | PASS fixture list/status/asks/activity; models, inspection, stop-refusal handling and stale-state contracts | Real OpenShell VM run/connect/stop/pull/undo/approval; no unsynced VM was stopped |
| Inventory | PASS fixture entry-triggered scan and summary; connector/IDE/identity parsers | A live rescan was intentionally avoided because entry can trigger scanning |
| AI Discovery | PASS fixture product/model rendering and action/parser contracts; live panel loads | A real rescan, detector completeness, online model provenance |
| Runtime | PASS final native partial/off/WATCHING states, reasons, error and capability tests; live sensor report read | Enabling planes, elevated Endpoint Security permissions, new real finding generation |
| Registries | PASS intentional no-sources fixture state and registry/supply-chain tests | Remote sync, trust changes and installs |
| Setup | PASS 23 forms, valid review previews, Kiro, redaction status, 25 runtime sections, Admission Defaults | Applying real setup, credentials, hooks, provider/webhook/Splunk/Galileo connectivity |
| Preferences/lifecycle | PASS four tabs, palette command, selection, separate native app launch/quit | Login launch, permission changes, update/install/rollback execution |
| Distribution | PASS source packaging-contract tests and Debug compile | Signed/notarized artifacts, fresh install, publication and release verification |

## Live finding outside the app patch

The selected live gateway's health endpoint returned a healthy `local-sqlite` destination and a degraded `local-observability` destination. At one bounded sample, OTLP reported 1,231 accepted records, zero delivered, 150 dropped, 181 rejected, 2,572 retries, and 1,050 queued records. These are time-specific counters, not a final incident total. A later read still showed degraded delivery. The old Mac app mislabeled the destinations as merely enabled and lost their signal arrays; that app decoder is repaired.

The underlying Collector/export failure was not diagnosed or repaired in this audit. No collector settings, live routing, credentials, gateway process, or enforcement policy were changed. Treat successful live Grafana delivery as **FAIL at the observed sample**, independently of the app's corrected display. A focused collector/export investigation is needed before claiming that integration works.

## Historical source-baseline gate

The tracked compatibility baseline still targets runtime source `00ef714b8a47f3ba90dad69b91dc8aa40c735057` (1.0.1). It has not been rewritten merely to make this audit green. [The difference manifest](runtime-1.0.5/evidence/source-differences.json) records 50 differences between this standalone app and the release's embedded Mac sources, including retained standalone identity/update/security work, license headers, and this audit's changes. It also identifies local files unchanged from the historical review.

The helper's upstream-SHA and source-hash checks therefore remain **FAIL / review required**. Its workflow calls for human review before replacing the baseline. Passing tests, matching command rows, and native fixture checks do not substitute for that gate. No full source-baseline or signed-release certification is claimed.

## Screenshots

The before Runtime screenshot is the installed 1.1.34 app reading live state; the after screenshot is the corrected Debug view with explicit synthetic partial/off states. Their data sources differ and are labeled here to avoid presenting them as an identical live replay.

| Evidence | Image |
| --- | --- |
| Runtime before: unselected plane labeled idle, coverage labeled DEGRADED | [Before](runtime-1.0.5/screenshots/runtime-before.png) |
| Runtime after: WATCHING, partial and off with reasons | [After](runtime-1.0.5/screenshots/runtime-after.png) |
| Overview service health (top of page) | [Overview](runtime-1.0.5/screenshots/overview-after.png) |
| Native Kiro setup review | [Kiro](runtime-1.0.5/screenshots/kiro-review.png) |
| Successful palette command in Activity | [Activity](runtime-1.0.5/screenshots/activity-version.png) |

An additional attempt to capture the scrolled destination table was **BLOCKED** when macOS locked at the end of UI verification. The Overview image shows the top-level service health; the destination table and applied-generation values are retained in the accessibility evidence. No further UI interaction was attempted after the lock.

## Reproduction

Run from the audit checkout:

```sh
DEFENSECLAW_RUNTIME_PYTHON=/Users/kobrien/.defenseclaw/.venv/bin/python ./script/test_policy_catalog.sh
./script/test_resource_boundaries.sh
./script/test_connector_onboarding.sh
./script/test_first_run_connector_selection.sh
./script/test_connector_inventory_compatibility.sh
./script/test_setup_definitions_parity.sh
./script/test_config_editor_contracts.sh
./script/test_sandbox_models.sh
./script/test_cli_cancellation.sh
./script/test_runtime_contract_surfaces.sh
```

The complete suite consists of all `script/test_*.sh` scripts. Compile production sources with:

```sh
xcodebuild -project DefenseClawMac.xcodeproj -scheme DefenseClawMac \
  -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath /private/tmp/DefenseClawMac-1.0.5-audit-DerivedData \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
git diff --check
```

No commit, PR, release, installed-app replacement, live runtime upgrade, or live configuration change was performed. The fixes and evidence remain reviewable on the isolated audit branch.
