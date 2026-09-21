# Compatibility repairs — September 18, 2026

## Result

The confirmed Mac-app defects are repaired in this checkout. A fresh Debug build and a fresh run of all **32 standalone test scripts** pass. Final native UI testing confirms that Verdicts and Otel display canonical runtime events, the new Runtime panel handles the installed gateway's missing API without presenting it as a clean host, and the palette records a successful version command in Activity.

**This is not an all-runtime or all-features sign-off.** Splunk is explicitly excluded: the user confirmed it is hosted by the stopped Podman environment. The installed runtime still lacks the newer mainline Runtime capability. Final checks also observed recurring gateway trace-completion warnings and a retained SQLite-write health warning; their relationship is not established. The installed app in `/Applications` was not replaced, and no release, commit or pull request was created.

## Exact comparison

| Target | Identity |
| --- | --- |
| Checkout | `/Users/kobrien/git/defenseclaw_mac`, branch `kobrien/runtime-compat-d4b9a01` |
| Starting commit | `5fc61cdf6e286bdee595714d514cc31152b040e5`; repairs are uncommitted |
| DefenseClaw main | `85029e57e9094debd9366a7d5a9f7e6d5c3ef6fc`, refreshed over the network |
| App / installed runtime | App `1.1.21`; runtime `0.8.10`, selected CLI `/Users/kobrien/.local/bin/defenseclaw` |
| Installed gateway build | `bf45995c7fa691f34ffa89b6f0468c93a6207dea`, built `2026-07-29T23:23:27Z`; reported by the version command and exact source commit fetched for diagnostic review |
| Installation | `/Users/kobrien/.defenseclaw`, schema 8, loopback gateway port 18970 |
| Official latest runtime release | `0.8.10`, published July 30; release provenance/source-map assets also dated July 30 |

The September 16 and 17 reports present at the start were preserved. No unrelated changes were discarded.

## Implemented repairs

### Canonical event feeds

- AuditStore reads immutable v8 log projections from `audit_events` using its existing read-only, identity-aware SQLite connection. It never creates or migrates the live database.
- The read is limited to 1,000 rows, 64 KiB per JSON field and 4 MiB aggregate materialized row data. Existing stream retention/count limits still apply.
- Verdicts uses the runtime's verdict/judge/scan/finding/error categories; Otel includes canonical log events. Repeated polls replace a bounded snapshot with stable IDs instead of duplicating events.
- Canonical compliance/enforcement mutations feed Activity; canonical network-egress events feed existing egress/bypass projections. Canonical findings are not duplicated as legacy scan blocks.
- Empty successful reads clear old rows. Unavailable reads retain the last good snapshot with an explicit warning. Manual Reload obtains a fresh canonical read. Plain Gateway/Watchdog files reload independently even when the database is unavailable, including same-size file replacements. Older schemas retain the legacy reader.
- Sensitive payload keys and recognizable credential assignments are redacted before display. Follow-up regressions reproduced and repaired plain `token`/camel-case `apiKey` omissions and authorization-header scheme masking. Shared redaction now handles those forms, quoted/unterminated values and values crossing the display limit, before truncation. This is defense in depth for supported patterns, not a guarantee that arbitrary free text contains no secrets. Oversized evidence is omitted rather than loaded unboundedly.

Sources: [AuditStore](/Users/kobrien/git/defenseclaw_mac/DefenseClawMac/DataLayer/AuditStore.swift), [EventStreamReader](/Users/kobrien/git/defenseclaw_mac/DefenseClawMac/DataLayer/EventStreamReader.swift), [LogsView](/Users/kobrien/git/defenseclaw_mac/DefenseClawMac/Features/LogsView.swift).

### Runtime feature parity with capability gating

- Added the upstream Runtime models and panel, including coverage planes, findings, provider attribution, correlation, filtering and details.
- Added Runtime API methods with bounded responses, required response-shape validation and the existing loopback/mutation protections.
- Missing routes are shown as unsupported, not disabled or healthy. Failed coverage reads preserve stale results with an error; installation switches clear old coverage.
- Runtime polling requires both gateway support and the specific CLI command. The panel runs polling through the CLI and records it in Activity; managed/read-only installations cannot bypass the mutation gate.
- Polling pins the selected installation before the command task is scheduled and rejects concurrent scans. Request identities prevent an old installation's request from clearing a newer request's loading state; cancelled/stale requests cannot publish coverage.
- Coverage strips are hidden until a valid snapshot exists. A search with no matching findings is distinguished from a detector reporting no findings. Reconnection and panel refresh retry the read.
- The generated registry now exactly matches **234 upstream entries**. Runtime commands are independently filtered by actual CLI help output, not the shared `0.8.10` label. Unsupported commands remain hidden on this installed runtime.
- Added bounded/deduplicated display identities, credential redaction for command lines/evidence and safe percentage handling for malformed counters.

Sources: [Runtime view](/Users/kobrien/git/defenseclaw_mac/DefenseClawMac/Features/AIRuntimeView.swift), [Runtime models](/Users/kobrien/git/defenseclaw_mac/DefenseClawMac/DataLayer/AIRuntimeModels.swift), [command registry](/Users/kobrien/git/defenseclaw_mac/DefenseClawMac/DataLayer/CommandRegistry.swift).

### Documentation

README now states that uncatalogued config keys are read-only and that there is no RAW/redaction-off switch. It describes canonical event sources, capability-gated Runtime support and the limits of verification instead of treating all same-version installations as equivalent.

## Verification performed

| Check | Result |
| --- | --- |
| Full standalone suite | **PASS, 32/32**, rerun after the final repairs; canonical-history cases include missing/partial database, classification, stable IDs, empty/unavailable snapshots, independent plain-log reload, credential spellings/header schemes/quoted values, truncation and memory limits |
| Runtime API regression cases | **PASS**: 404 distinction, malformed payload rejection, coverage decoding, severity order, duplicate identities, credential redaction, numeric limits and read-only mutation denial |
| Fresh Debug build | **PASS**, isolated temporary DerivedData with ad-hoc signing; not a distribution artifact |
| Live read-only event-reader probe | **PASS**, final sample: 967 canonical events produced 128 Verdicts rows and 967 Otel rows within the byte/row budgets; no record contents emitted |
| Native UI | **PASS**: final rebuilt process verified against its exact binary path; live sample displayed 102 Verdicts and 952 Otel rows; Verdicts Reload, search/no-match and reset verified |
| Runtime unsupported behavior | **PASS**, final rebuild: missing route gives explicit unsupported guidance, Poll now is disabled, Refresh works, and the misleading empty-plane strip is absent |
| Palette / Activity | **PASS**: 230 supported commands visible, Runtime search returns zero commands on this installation, harmless `version` completes and Activity shows completed/exit-zero evidence |
| Registry/schema/help/packaging source contracts | **PASS**: all 234 entries, schema 8, 24 setup sections, four targeted help probes and protected-runtime packaging checks |
| Installed distribution requirements | **PASS**, refreshed check of 251 active requirements, zero conflicts |
| Read-only database integrity | **PASS**, fresh time-bounded `quick_check` completed; this does not prove every concurrent writer succeeds |
| Whitespace validation | **PASS**, `git diff --check` |

Before/after native screenshots were captured in the task. The after screenshot intentionally uses a no-match filter while retaining the nonzero total, so live event contents are not exposed. The row rendering itself was observed before applying that filter. Automated fixtures—not secrets from live records—test redaction.

The earlier lock-screen blocker is resolved. The previous temporary test app was quit and the final app rebuilt from the repaired checkout, launched and verified. Screenshots confirm the final Runtime unavailable state and privacy-preserving Logs filter test. The final temporary Debug app was left open after user window changes were observed; the installed app remains unchanged. Other panels retain the explicitly scoped September 16/17 coverage, supplemented by today's full regression suite, not a claim that every live write was exercised again.

Final build, test and audit evidence is under `/private/tmp/defenseclawmac-final-check-20260918.xhxjLz` (`build.log`, `tests.log`, `compatibility.md`). The final Debug app is in `DerivedData/Build/Products/Debug/DefenseClawMac.app` beneath that directory. Its executable SHA-256 is `9ebb19f094505b36e07cd6df89f99e952acd371e7998a661b0e5d6d1d84b8c39`; its local ad-hoc signature verifies. This is not Developer-ID/notarized release evidence. Earlier repair evidence remains under `/private/tmp/defenseclawmac-fixes-20260918.fW7Jrb`. Temporary evidence can be removed by macOS.

## Residual environment issues

### Splunk receiver: explicitly excluded

The configured loopback HEC endpoint uses HTTPS port 8088. An empty-body diagnostic request failed with **ConnectionRefusedError, errno 61** before authentication or ingestion. Current gateway counters still show zero delivered events. This establishes that the receiver is not listening; it does **not** establish a bad token.

The user confirmed that Podman hosts Splunk and it is currently unavailable, then asked to finish everything else. No VM/container was started, no credentials were changed, and no test event was ingested. Splunk was not re-probed in the final follow-up. It remains outside the current completion criteria; no receiver-restoration action is pending approval in this task.

### Installed runtime versus newer mainline

The installed runtime still lacks the Runtime command group/API. The Mac app now handles that honestly and is ready for a compatible runtime, but it cannot supply a missing gateway sensor implementation. The official latest release remains `0.8.10`; no newer release was installed or an unverified source build substituted.

Mainline dependency requirements remain different: installed `cryptography 48.0.1` versus `>=50,<51`, and `openai 2.50.0` versus `==2.30.0`. The installed wheel's own dependency requirements are consistent. Isolated package replacement would not provide the missing gateway feature and was not used to force agreement. A coordinated, provenance-verified runtime upgrade is needed.

The compatibility audit therefore still exits nonzero for that dependency drift and the old source-baseline hashes. The baseline was not rewritten to hide the newly modified files; advance it only after review of these deliberate standalone changes.

### Gateway tracing and retained event-history warning

Final native log inspection exposed `[otel-ingest] canonical normalize trace completion failed`. A bounded file-tail check observed **14 new occurrences** after a recorded byte boundary; this is not merely an old cached doctor result. The authenticated, loopback-only health check reported `event_history_failure=sqlite_write_failed`, while its SQLite destination and retention were healthy. No raw records, credentials, endpoint values or request bodies were printed. Splunk destinations were excluded from the diagnostic summary and no receiver request was sent.

Review of the **exact installed gateway source commit** shows that this version retains the last event-history failure without a recovery transition and does not expose the newer bounded SQLite failure class/code. Thus the health flag does not prove a present database outage, and the generic trace warning cannot establish that the two share a cause. Current canonical log timestamps continue to advance (observed `2026-09-18T22:36:03.201903Z`); the database is readable, its fresh read-only `quick_check` passed within the 45-second budget, and the volume has approximately 89 GiB free. No evidence justifies attributing this warning to Splunk, claiming database corruption, or altering the database.

This remains a runtime diagnostic risk, not a repaired Mac-app defect. A focused runtime investigation or coordinated, provenance-verified runtime update is needed for a complete tracing sign-off. No gateway replacement/restart, database migration/repair or monitoring suppression was performed to hide the warning.

No live enforcement changes, setup Apply/Save, credential rotation, external provider scans, notification delivery, clean-machine installation, upgrade/rollback or signed-release workflow was executed. Passing the checked paths does not certify those untested operations.
