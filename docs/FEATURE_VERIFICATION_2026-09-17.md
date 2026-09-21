# DefenseClawMac compatibility and feature verification — 2026-09-17

## Outcome

**The build and all 31 regression scripts pass, but the app does not pass full functional verification.**

The Mac is unlocked, the compiler works, and the selected gateway is running. All 13 existing sidebar panels, all four preferences tabs, and all 22 native setup forms have now been visited across the two audit sessions. The fresh checkout build also launches and reads live data. However:

- **Existing feature failure:** Verdicts and Otel remain empty because the app reads a retired event file, while the runtime has current events in its canonical audit database. The fresh build reproduces the Verdicts failure.
- **Mainline parity gap:** upstream has an AI Runtime panel and three additional commands that this checkout lacks; the installed gateway also lacks the required Runtime API.
- **Live integration failure:** the configured Splunk HEC destination reports failed delivery. Its underlying cause is not established.

This is not an all-features or release-readiness sign-off. Form previews and unit tests do not establish that every write, external integration, installation, or upgrade works. This report supersedes the environment blockers and updates the findings in the [September 16 report](/Users/kobrien/git/defenseclaw_mac/docs/FEATURE_VERIFICATION_2026-09-16.md).

No production app source, compatibility baseline, runtime packages, credentials, configuration, or enforcement settings were changed. No release was published. The reusable verification skill was updated to catch the event-source mismatch in future audits.

## Exact targets

| Target | Verified identity |
| --- | --- |
| Checkout | `/Users/kobrien/git/defenseclaw_mac` |
| Branch / commit | `kobrien/runtime-compat-d4b9a01` / `5fc61cdf6e286bdee595714d514cc31152b040e5` |
| Starting worktree | Only the untracked September 16 audit report |
| Current upstream main snapshot | `85029e57e9094debd9366a7d5a9f7e6d5c3ef6fc`; remote identity rechecked before completion |
| Reviewed baseline, unchanged | `d4b9a01fe8f9e9d725e5e885a90aef1b13075957` |
| Installed app | `/Applications/DefenseClawMac.app`, version `1.1.21`, build `1` |
| Fresh checkout build | Debug app under `/private/tmp/defenseclawmac-feature-audit-20260917.9VKWDy/DerivedData/Build/Products/Debug/DefenseClawMac.app` |
| Selected CLI | `/Users/kobrien/.local/bin/defenseclaw`, resolving into `/Users/kobrien/.defenseclaw/.venv/bin/defenseclaw` |
| Runtime / upstream declared version | Both `0.8.10`; labels do not establish capability parity |
| Selected installation | Default `/Users/kobrien/.defenseclaw`; no app path override; unmanaged |
| Config schema / endpoint | Schema `8`; `http://127.0.0.1:18970` |

The fresh app's running process was checked against its exact build path. It was quit after testing; the installed app and user-started gateway were left running. Installed release signature/notarization checks passed on September 16; they were not repeated or substituted for fresh-build provenance today.

## Verified failures and risks

### 1. Verdicts and Otel use a retired event source

The installed app shows zero total rows for Verdicts and Otel and names `gateway.jsonl` as their source. That file is absent. The freshly compiled app also shows an empty Verdicts stream despite an active gateway and live Overview data.

This is not simply an unconfigured log file. The installed runtime's `tui/services/v8_event_history.py` explicitly uses bounded read-only projections of canonical SQLite `audit_events` and identifies the production JSONL side channel as retired. Current upstream confirms that the legacy writer cannot be re-enabled by configuration. A bounded read through the installed canonical reader returned **500 current events**, including 44 guardrail evaluations, 57 tool-activity events, 343 telemetry-ingest events, 8 asset scans, 32 security findings, 11 model-I/O events, and 5 discovery events. These are categorized projection counts, not an assertion that every event belongs in each log tab. The newest timestamp in that sample was `2026-09-18T00:06:51.892631Z`.

The Mac app still binds `EventStreamReader` to the legacy JSONL path and renders structured log buffers populated by that file reader. Plain Gateway and Watchdog logs do load; their success does not validate the two structured streams.

Evidence: [runtime canonical reader](https://github.com/cisco-ai-defense/defenseclaw/blob/85029e57e9094debd9366a7d5a9f7e6d5c3ef6fc/cli/defenseclaw/tui/services/v8_event_history.py), [retired writer contract](https://github.com/cisco-ai-defense/defenseclaw/blob/85029e57e9094debd9366a7d5a9f7e6d5c3ef6fc/internal/audit/logger.go), [app reader binding](/Users/kobrien/git/defenseclaw_mac/DefenseClawMac/App/AppState.swift:285), [file polling](/Users/kobrien/git/defenseclaw_mac/DefenseClawMac/DataLayer/EventStreamReader.swift:182), [displayed buffers](/Users/kobrien/git/defenseclaw_mac/DefenseClawMac/Features/LogsView.swift:402).

**Recommended repair:** add bounded, redacted, schema-tolerant canonical v8 projections with regression tests, installation rebinding, and deliberate legacy compatibility. Do not restore the retired runtime writer. Review stream-derived scan-block/egress signals and [legacy Activity loading](/Users/kobrien/git/defenseclaw_mac/DefenseClawMac/Features/ActivityView.swift:293) as related risks. Their source dependence was identified; every downstream failure has not been independently reproduced.

### 2. Upstream Runtime feature and three commands are missing locally

The latest upstream registry has **234 entries** versus **231** locally. The additions are `agent discovery runtime enable`, `agent discovery runtime scan`, and `agent discovery runtime permissions`. The existing palette exposes 230 local commands because unsupported `setup amp` is intentionally filtered; that is a separate, expected count difference.

Upstream also adds the Runtime panel, models, navigation, and gateway methods. The selected live gateway returns **404** for authenticated `GET /api/v1/ai-usage/runtime`, while ordinary status/discovery routes work. The installed CLI rejected the Runtime command group in the September 16 check. Blind registry synchronization or copying the panel would therefore expose unsupported operations.

The compatibility audit reports five newly differing paths: `App/AppState.swift`, `DataLayer/AIRuntimeModels.swift`, `DataLayer/GatewayClient.swift`, `Features/AIRuntimeView.swift`, and `Features/MainWindow.swift`. The baseline was not advanced merely to silence these results.

**Recommended next step:** implement capability-gated Runtime support alongside a compatible runtime; verify absent-route and older same-version behavior. This is an upstream feature gap, distinct from the existing log-stream failure. [Upstream snapshot](https://github.com/cisco-ai-defense/defenseclaw/tree/85029e57e9094debd9366a7d5a9f7e6d5c3ef6fc).

### 3. Splunk telemetry is accepted locally but not delivered

The authenticated health/status response reports a failing `splunk_hec` destination with reason `delivery_failed`. At `2026-09-17T23:51:06.802016Z`, its counters were **2,178 accepted, 0 delivered, 2,175 rejected, and 4,350 retried**. The SQLite destination and retention health were healthy. The configured network destination is loopback; endpoint details and credentials were not emitted.

The gateway's API, guardrail, watcher, AI Discovery, config, and connector components report running. The standalone setup's disabled OpenClaw fleet component is not evidence that the local gateway is stopped.

**Root cause remains unresolved.** Bounded log inspection did not establish an authentication, TLS, reachability, or receiver-configuration cause. No credential or service settings were changed. Investigate the actual HEC receiver response separately before claiming a fix; old failures and audit records containing this check's own command text are not reliable causal evidence.

### 4. Dependency and documentation drift remain

The current upstream requires `cryptography >=50.0.0,<51` and `openai ==2.30.0`; installed versions are `48.0.1` and `2.50.0`. September 16's check of 251 active installed-distribution requirements found no conflicts. That check was not repeated today. This remains wheel/mainline drift, not a reproduced dependency crash, and packages were not changed to force agreement.

The prior README discrepancies remain: uncatalogued configuration keys are read-only in the implementation despite the editing promise, and the described Logs RAW/redaction switch is absent. The old doctor cache is not a fresh diagnosis. Update-check UI reported offline/rate-limited status; actual upgrade behavior was not verified.

## Feature coverage

**PASS** below covers only the named operation. **FAIL** means reproduced failure. **NOT TESTED** is not a success claim. September 16 evidence is explicitly labeled; it was not silently rerun.

| Feature | Verified behavior | Remaining coverage |
| --- | --- | --- |
| Overview | **PASS:** live health, connector roster, hook counters and local alerts; fresh build also reads live state | Start/stop/restart, new diagnostics and every counter's source-to-display accuracy **NOT TESTED** |
| Alerts | **PASS, September 16:** bounded queue, severity filter, detail/dismissal; fresh Overview reads current alert counts | Acknowledgement persistence, all filters and newly generated alert delivery **NOT TESTED** |
| Logs | **PASS:** plain Gateway/Watchdog streams load; September 16 search/no-match/reset. **FAIL:** structured Verdicts/Otel empty against current canonical events; fresh-build Verdicts reproduces | Follow/pause, every detail/filter, downstream egress/scan projections **NOT TESTED** |
| Audit | **PASS, September 16:** 200 rows then pagination to 400; current read-only store access and integrity check succeed | Export, all filters/details **NOT TESTED** |
| Activity | **PASS, September 16:** version command completed, exit 0, output/inspector; user gateway-start entry visible today | Live v8 mutation-history parity and cancellation in the UI **NOT TESTED** |
| Skills | **PASS:** 13 catalog rows, completed load, enabled install control; blank install form correctly prevents review and cancels | Install/remove/enable/scan **NOT TESTED** |
| MCPs | **PASS:** 2 catalog rows, completed load, enabled action; blank required-name form prevents review and cancels | Enable/disable/scan/connectivity **NOT TESTED** |
| Plugins | **PASS:** 23 catalog rows, completed load, enabled install control; blank required-source form prevents review and cancels | Install/remove/scan **NOT TESTED** |
| Tools | **PASS:** empty policy table agrees with zero policy rows in the backing store | Policy changes, connector filters and persistence **NOT TESTED** |
| Inventory | **PASS:** local scan returns 35 items across 4 connectors, 0 errors; all eight category/summary tabs visited. Counts: MCP 2, plugins 23, skills 10, other categories 0 | Detailed item actions and other connector types **NOT TESTED** |
| AI Discovery | **PASS:** 74 signals; authenticated API, search/no-match/reset and selection/inspector. Components API returns an empty list | Enable/scan, runtime sensors, fresh model detections **NOT TESTED** |
| Registries | **PASS:** empty Sources/Entries/Approved agree with zero configured sources; add-source form gates missing fields and cancels | Sync/test/install and external registries **NOT TESTED** |
| Setup | **PASS, form behavior:** all 22 native forms open/cancel; 17 reach review; 5 correctly remain gated. Dynamic runtime catalog exposes 24 sections and zero pending edits | No Apply/Save or external integration executed; Linux-only Sandbox unsupported on this Mac |
| Preferences | **PASS, display:** General, Monitoring, Notifications and Connection; correct versions, selected installation and loopback endpoint | Settings changes, permissions, update/install actions and notification delivery **NOT TESTED** |
| Palette / lifecycle | **PASS:** prior harmless version invocation; installed and fresh app launch/navigation; fresh process path verified and temporary app quit | All shortcuts, close/reopen, menu-bar-only mode and login launch **NOT TESTED** |
| Upstream Runtime panel | **FAIL, feature parity:** panel/actions absent; required live route returns 404 | Needs coordinated capability-gated app/runtime work |
| Telemetry delivery | **FAIL:** authenticated live status reports HEC delivery failure with zero delivered | Receiver root cause and successful recovery **NOT TESTED** |
| Distribution | **PASS, September 16:** installed signature/Gatekeeper; current source packaging checks pass | Fresh install, upgrade, rollback, signed release and unified-DMG validation **NOT TESTED** in this follow-up |

The 17 setup review previews were Connector Setup, Credentials, Cisco AI Defense, Local OTel, Galileo, Token Rotation, Custom Providers, Skill Scanner, MCP Scanner, Gateway, Splunk, Observability, Notifications Routing, AI Discovery, Splunk Dashboards, Trusted Paths, and Guardrail Actions. LLM, Guardrail, Webhooks and Registries require missing values; Sandbox is Linux-only. No review was applied, no secret was entered, and sensitive fields remained masked.

## Automated and backing-service checks

| Check | Result |
| --- | --- |
| All `script/test_*.sh` scripts | **PASS, 31/31**, each completed successfully; no timeout retry needed |
| Fresh Debug compile | **PASS**, temporary DerivedData, ad-hoc signing; not a distribution artifact |
| Fresh Debug launch | **PASS**, exact binary process path verified; live Overview and discovery data visible |
| Runtime/schema/setup contracts | **PASS**, runtime label `0.8.10`, schema `8`, 24 setup sections, four targeted help probes |
| Removed v7 flags/keys/commands | **PASS**, absent from audited surfaces |
| Protected-runtime packaging | **PASS**, source contract only |
| Registry/source baseline | **FAIL / drift**, 234 versus 231 commands, five newly differing source paths |
| SQLite integrity | **PASS**, read-only `PRAGMA quick_check(1)` returned `ok` in about 21.5 seconds within a 45-second budget; resolves yesterday's inconclusive 10-second timeout |
| Live API reads | **PASS**, `/health` and authenticated `/status`, `/api/v1/ai-usage`, `/api/v1/ai-usage/components` return 200 |
| Runtime API | **FAIL, capability parity**, authenticated `/api/v1/ai-usage/runtime` returns 404 |
| Reusable skill | Updated with canonical-event-source reconciliation; validation and eight preflight fixture tests pass |

The build used the repository's documented `xcodebuild` configuration with `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=`. A benign destination-selection diagnostic appeared, but the build exited successfully. `build_and_run.sh --verify` was not run because it would terminate existing app instances; exact-path native launch and process verification were used instead.

The current source snapshot and sanitized raw compatibility summary are in `/private/tmp/defenseclawmac-feature-audit-20260917.9VKWDy`; temporary files may be removed by macOS. The repository test scripts are the reproducible test list rather than frozen copied test output. No raw audit records, request bodies, configuration values or credentials are retained in this report.

## Side effects and next steps

Opening Inventory executed the app's normal local inventory scan after its side effects were reviewed; it records a normal local audit/activity snapshot. Catalog loading can invoke existing CLI audit-store initialization. Initial unauthenticated API probes produced expected authentication failures; authenticated probes were then used, and these probe-generated failures were not treated as product defects. The user, not this audit, started the gateway. No enforcement, telemetry configuration, secret, runtime package, or production source changes were made.

1. Repair and regression-test canonical event projection for Logs, then check dependent Activity/scan/egress paths against actual fresh events.
2. Plan Runtime feature support with explicit capability detection and a suitable runtime; do not automatically expose the three unsupported commands.
3. Diagnose the local HEC receiver failure using a bounded, credential-safe request and receiver evidence, then verify actual delivery.
4. Use a disposable installation or separately approved targets for setup Apply/Save, enforcement, connector changes, scans that invoke external services, notification delivery, and installation/upgrade/rollback tests.

Reusable skill: [defenseclaw-feature-verification](/Users/kobrien/.codex/skills/defenseclaw-feature-verification/SKILL.md), invoked as `$defenseclaw-feature-verification`. It distinguishes source parity, tests, real UI behavior and live integrations; the added event-source check prevents empty retired-file tabs from being mistaken for working features.
