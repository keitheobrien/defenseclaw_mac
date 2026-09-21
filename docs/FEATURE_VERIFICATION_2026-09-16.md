# DefenseClawMac compatibility and feature verification — 2026-09-16

Follow-up: the [September 17 report](/Users/kobrien/git/defenseclaw_mac/docs/FEATURE_VERIFICATION_2026-09-17.md) resolves the compiler, lock-screen and gateway prerequisites, completes broader UI coverage, and records newly reproduced failures. The historical results below are preserved.

## Outcome

**Partial verification; not an all-features or release-readiness sign-off.**

The command registry and core schema contracts still match the checked upstream snapshot. Existing installed-app read paths were exercised, including a successful CLI command through the UI. Current upstream adds an AI Runtime feature absent from this checkout and from the installed CLI. A fresh build and 28 Swift-based test scripts are blocked by the Xcode license; live gateway integration is blocked by connection refusal; native UI testing stopped when the Mac locked.

No production app source, compatibility baseline, runtime packages, gateway configuration, credentials, or enforcement settings were changed. No release was built or published. Opening panels and running the harmless version command changed normal UI/session activity only; catalog panels invoke the app's existing loading behavior.

## Exact targets

| Target | Verified identity |
| --- | --- |
| Mac checkout | `/Users/kobrien/git/defenseclaw_mac` |
| Branch / commit | `kobrien/runtime-compat-d4b9a01` / `5fc61cdf6e286bdee595714d514cc31152b040e5` |
| Initial worktree | Clean |
| Standalone main | `4a7ede91c0aecbd8582c074b10ad8381d1515bee`; no content diff from the checkout commit |
| Upstream DefenseClaw main | `4321abd52204d9240b2dba84a6d04db801b06437`; fetched into a clean temporary clone and rechecked remotely at the end |
| Previous reviewed baseline | `d4b9a01fe8f9e9d725e5e885a90aef1b13075957`; left unchanged |
| Source app version | `1.1.21` |
| App used for native UI checks | `/Applications/DefenseClawMac.app`, version `1.1.21`, build `1` |
| CLI | `/Users/kobrien/.local/bin/defenseclaw`, resolving to `/Users/kobrien/.defenseclaw/.venv/bin/defenseclaw` |
| Installed CLI / upstream declared version | Both `0.8.10`; matching labels do not imply identical capabilities |
| Config schema | Installed config `8`; upstream supports `8` |
| Probed local installation | `/Users/kobrien/.defenseclaw`; loopback gateway port `18970` |

The installed app was tested directly, not rebuilt from this checkout. Its version and signature were checked, but a version label alone is not binary-to-source provenance proof. Preference-based installation selection could not be revisited after the screen locked; direct probes targeted the identified local installation and agreed with the app's offline gateway display.

## Verified findings and residual risks

### 1. New upstream AI Runtime feature is not available locally

Upstream adds `AIRuntimeModels.swift`, `AIRuntimeView.swift`, the `Runtime` sidebar entry, and gateway operations for `GET /api/v1/ai-usage/runtime` and `POST /api/v1/ai-usage/runtime/scan`. The standalone checkout has 13 sidebar panels, without this new one.

The installed CLI also rejects `defenseclaw agent discovery runtime --help` with exit `2`, reporting that `runtime` is not a command. The current upstream source defines the new command group. Thus importing the new view alone would not establish a working feature on the installed runtime. Any implementation should detect actual capability and handle older/offline gateways explicitly.

The source-baseline check reports five newly differing paths: `App/AppState.swift`, `DataLayer/AIRuntimeModels.swift`, `DataLayer/GatewayClient.swift`, `Features/AIRuntimeView.swift`, and `Features/MainWindow.swift`. These were inspected. This is a feature-parity gap, not evidence that an existing panel regressed.

Sources: [upstream snapshot](https://github.com/cisco-ai-defense/defenseclaw/tree/4321abd52204d9240b2dba84a6d04db801b06437), [upstream Runtime view](https://github.com/cisco-ai-defense/defenseclaw/blob/4321abd52204d9240b2dba84a6d04db801b06437/macos/DefenseClawMac/DefenseClawMac/Features/AIRuntimeView.swift), [local navigation](/Users/kobrien/git/defenseclaw_mac/DefenseClawMac/Features/MainWindow.swift:27).

### 2. Dependency drift exists, but the installed dependency set is consistent

| Package | Installed | Current upstream requirement |
| --- | --- | --- |
| cryptography | `48.0.1` | `>=50.0.0,<51` |
| openai | `2.50.0` | `==2.30.0` |

A separate check evaluated **251 active dependency requirements** from installed distribution metadata, with **zero conflicts or missing required packages**. Optional extras not activated by those markers are not covered. The installed DefenseClaw wheel itself accepts the older cryptography series. Consequently, the compatibility audit's dependency failures identify wheel/mainline drift, not a reproduced broken installation. No packages were changed to force agreement. `pip` is absent from this runtime, so metadata inspection was used instead of installing tooling.

### 3. Compilation and Swift regression tests are blocked

The fresh Debug build exits `69` with the Xcode/Apple SDK license requirement. All 28 Swift-based standalone scripts hit that same prerequisite. They are **BLOCKED**, not 28 demonstrated code failures. The compatibility tool's raw output labels them `FAIL`; this report corrects that classification.

The user must review and accept the license through Xcode or `sudo xcodebuild -license`. No license was accepted or bypassed during this audit.

### 4. Gateway-backed operations cannot currently be verified

The app shows the gateway offline. Independent bounded requests to `/health` and `/api/v1/ai-usage` at `127.0.0.1:18970` both fail with connection refusal, consistent with a TCP preflight. No credential failure was observed because a connection could not be established. Requests did not follow redirects or use proxies; no token or response body was emitted.

AI Discovery, live connector state, sensor coverage, policy reload, scan execution, acknowledgement writes, and downstream telemetry delivery are therefore not end-to-end verified. Starting the gateway was not treated as an innocent test prerequisite: it can activate configured monitoring, hooks, scans, and telemetry, so it was left unchanged.

### 5. Cached and local data do not prove current runtime health

The doctor cache is approximately **22.1 days old** (46 pass, 3 fail, 3 warn, 9 skip). Its old failures are not presented as freshly reproduced problems.

Read-only SQLite probes successfully accessed recent audit rows and found `audit_events`, `scan_results`, `actions`, and `alert_acknowledgement_projection`. The database is **1,739,497,472 bytes**. A 10-second bounded `quick_check` was interrupted (`SQLITE_INTERRUPT`); whole-database integrity is **inconclusive**, not failed. No repair, migration, or audit-history deletion was attempted.

### 6. Two README promises do not match current source

- The README says uncatalogued configuration keys remain editable. The current dynamic catalog deliberately makes them read-only because the runtime writer cannot persist unmodelled keys. See [README](/Users/kobrien/git/defenseclaw_mac/README.md:85) and [catalog implementation](/Users/kobrien/git/defenseclaw_mac/DefenseClawMac/DataLayer/DynamicConfigCatalog.swift:121).
- The README advertises a Logs redaction kill-switch/RAW badge, which is not present in the current Logs view. See [README](/Users/kobrien/git/defenseclaw_mac/README.md:95) and [Logs view](/Users/kobrien/git/defenseclaw_mac/DefenseClawMac/Features/LogsView.swift).

These are documentation discrepancies. They are not a reason to restore unsupported controls or weaken redaction. No documentation promises were silently treated as implemented features.

## Installed-app feature coverage

**PASS** applies only to the operation named below. **BLOCKED** means an environment prerequisite prevented completion. **NOT TESTED** is not a success claim. Source review is not a substitute for runtime testing.

Nine of the thirteen sidebar panels were opened before the Mac locked. The first six had useful observable behavior checked; the final three catalog panels had only their initial UI observed, not confirmed asynchronous results.

| Feature | Result and evidence | Residual coverage |
| --- | --- | --- |
| Overview | **PASS, read display:** configured connector roster, local counters and explicit offline gateway state render; stale doctor cache shown | Live connector health, fresh diagnostics, gateway lifecycle, delivery to external services **BLOCKED / NOT TESTED** |
| Alerts | **PASS:** 500-item bounded queue; HIGH severity filter selects; detail inspector opens and dismisses; filter restored to All | Other filter combinations and acknowledgement persistence **NOT TESTED** |
| Logs | **PASS:** Gateway, Verdicts, Otel and Watchdog tabs select; synthetic no-match search displays 0 matching / 0 shown against 8,586 total gateway lines; search cleared | Individual stream freshness, continuous follow/pause, detail inspector and all filter combinations **NOT TESTED** |
| Audit | **PASS:** 200 loaded events; Load older events increases the count to 400 | Export, all filters and detail interactions **NOT TESTED** |
| Activity | **PASS:** command history and result inspector show successful version command, exit 0 and runtime 0.8.10 | Cancellation and mutation-history persistence **NOT TESTED** |
| Skills | **PASS, limited:** host skill rows render after refresh | Install control was disabled in the observed state; cause and action availability were not fully resolved. Enable/disable/install/scan **NOT TESTED** |
| MCPs | **PASS, shell only:** panel and expected columns open | Asynchronous data completion and all actions **BLOCKED** by screen lock before verification |
| Plugins | **PASS, shell only:** panel and expected columns open | Asynchronous data completion and all actions **BLOCKED** by screen lock before verification |
| Tools | **PASS, shell only:** panel and policy columns open | Whether final empty/content state is correct, filter and policy writes **BLOCKED** by screen lock |
| Inventory | **BLOCKED / source reviewed:** not opened before lock. Source can run `aibom scan --json` automatically on entry when mutations are allowed | Requires an approved scanning scope or disposable installation; category counts, warnings and inspector not exercised |
| AI Discovery | **BLOCKED:** backing API refuses connections; source retry/action gating reviewed | Panel UI, live products/models, enable/scan and external evidence not exercised |
| Registries | **BLOCKED / source reviewed:** cached-source loader inspected; UI not reached | Source/entry detail, sync/test/install and policy edits not exercised |
| Setup | **BLOCKED / partial contract checks:** installed runtime catalog exposes 24 sections; source defines 22 native wizards | Individual form/review/cancel, save/apply and external provider/observability/webhook integrations not exercised. Linux-only Sandbox cannot be certified on macOS |
| Command palette | **PASS:** search for `version`, run, completed output and Activity record | 230 visible commands is intentional filtering of unsupported `setup amp`; generated registry still matches all 231 upstream entries. Other command executions not certified |
| Preferences | **BLOCKED:** screen lock prevented General, Monitoring, Notifications and Connection UI checks | Selected-installation controls, settings changes and update actions not exercised |
| Lifecycle / menus | **PASS, limited:** installed app launches and panel navigation works | Close/reopen, login launch, menu-bar-only mode, keyboard shortcuts and notification delivery not exercised |
| Installed artifact | **PASS:** strict/deep code signature verification; Gatekeeper accepts it as Notarized Developer ID | Fresh-install, update, rollback, unified-DMG validation and binary/source provenance not repeated in this audit |
| New upstream Runtime panel | **FAIL, feature parity:** absent from checkout; required CLI command group absent from installed runtime | Capability-gated implementation and a compatible runtime needed before functional testing |

No crash was observed in the exercised paths. That is not a claim that untested paths are crash-free. UI automation initially failed to select an alert by accessibility index; a screenshot-based selection succeeded and its inspector was verified. The automation failure was not counted as an app defect.

## Automated checks

| Check | Result |
| --- | --- |
| Exact upstream command registry | **PASS**, 231 entries |
| Removed config-v7 flags/keys/commands | **PASS**, absent from audited surfaces |
| Signed schema-2 protected-runtime packaging contract | **PASS**, source contract only |
| Installed CLI version and four targeted help surfaces | **PASS**: setup observability, agent discovery enable, setup provider add, setup webhook add |
| Installed runtime setup metadata | **PASS**, 24 sections |
| New Runtime CLI group | **FAIL, capability parity**, no such command |
| Source baseline | **FAIL, review required**, upstream advanced and five new path differences; baseline not rewritten |
| Installed dependencies vs current upstream source | **FAIL, drift**, two differing packages |
| Installed distributions' own active requirements | **PASS**, 251 requirements, zero conflicts |
| Existing non-Swift standalone tests | **PASS**, 3 scripts |
| Existing Swift-based standalone tests | **BLOCKED**, 28 scripts require Xcode license acceptance |
| Fresh Debug build | **BLOCKED**, same Xcode license prerequisite |
| New skill validation and fixture tests | **PASS**, valid skill and 8 tests |

Passing repository scripts:

```text
script/test_dependency_lock_validator.sh
script/test_runtime_compat_audit.sh
script/test_supply_chain_safety.sh
```

The other 28 `script/test_*.sh` scripts were attempted by the full audit and stopped at the license gate. Earlier release test results were not substituted for current results.

## Reproduce and finish

The working evidence directory for this run is `/private/tmp/defenseclawmac-feature-audit-20260916.jLDF3Z`. It contains the clean upstream snapshot and `compatibility.md` raw audit output; temporary evidence may be removed by macOS, so the conclusions and coverage matrix are retained in this report.

Audit invocation used:

```bash
python3 .codex/skills/defenseclaw-runtime-compat/scripts/audit_compatibility.py \
  --mac-root /Users/kobrien/git/defenseclaw_mac \
  --upstream /private/tmp/defenseclawmac-feature-audit-20260916.jLDF3Z/upstream \
  --run-tests \
  --report /private/tmp/defenseclawmac-feature-audit-20260916.jLDF3Z/compatibility.md
```

Fresh build invocation used (outside the restricted sandbox):

```bash
xcodebuild -quiet -project DefenseClawMac.xcodeproj -scheme DefenseClawMac \
  -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath /private/tmp/defenseclawmac-feature-audit-20260916.jLDF3Z/DerivedData \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
```

To complete coverage:

1. Unlock the Mac and review/accept the Xcode license, then rerun the 28 blocked tests and fresh build.
2. Confirm the selected installation in Connection preferences. Authorize starting its gateway, or provide an isolated test installation with a running gateway. Recheck authenticated API response shapes and feature operations without sending secrets to output.
3. Complete the unvisited panels, preferences, catalog loading and interactions. Exercise mutation paths only with explicitly disposable targets or approved live changes. Include real external-service checks only when their credential/data/cost scope is approved.
4. Scope any AI Runtime feature implementation separately, with graceful handling for this older same-version runtime. Resolve the README discrepancies without reintroducing unavailable controls. Do not advance the compatibility baseline until the resulting contracts and tests are verified.

## Reusable skill delivered

Installed personal skill: [defenseclaw-feature-verification](/Users/kobrien/.codex/skills/defenseclaw-feature-verification/SKILL.md).

Invoke it as `$defenseclaw-feature-verification`. It combines the existing repository compatibility workflow with a current-source-derived feature checklist, native UI verification, explicit mutation boundaries, and PASS/FAIL/BLOCKED/NOT TESTED reporting. Its read-only preflight detects compiler/license, runtime version, selected audit-store access and loopback connectivity before expensive testing. Eight fixture tests verify no absent database is created, no record content is emitted, non-loopback targets are rejected, and interrupted checks are not misreported as corruption.
