# DefenseClawMac / runtime 1.0.7 TUI audit

Date: 4 November 2026 (America/New_York)

## Result and limits

The installed runtime moved from 1.0.3 to 1.0.7. This audit adopted the uncommitted 1.0.5 audit (registry 249, Kiro roster, runtime coverage states, destination health, approval previews, refused stops, drift, config generation, read-only Activity effects), ported the 1.0.3→1.0.7 contract changes, and then ran a four-cluster adversarial review (setup/config, monitor/govern, discover/shell, sandboxes; three verifiers per gap) that confirmed **12** further gaps and refuted 2. All 12 are fixed here, plus one divergence found during the live walkthrough (the connector wizard's guardrail mode). The final standalone regression run is **46 PASS, 0 FAIL** across every `script/test_*.sh`, the production-source Debug build succeeds, `git diff --check` is clean, and every wizard, registry, catalog and sandbox argv shape the app can emit was accepted by the installed 1.0.7 command-line parser.

This is a tested source patch on an isolated branch, not a release. Two limits are explicit: the Splunk enterprise pipeline and the Runtime Permissions button were verified by tests and fixture, not against a live Splunk or a degraded host; and the live gateway-backed panels could not be observed in the Debug app because of a pre-existing listener-trust limitation described under "Live finding outside the app patch". That limitation also affects the installed 1.1.34 app and is independent of runtime 1.0.7.

## Exact targets

| Target | Identity |
| --- | --- |
| Runtime release/tag | `1.0.7`, commit `574fc32c0` (detached worktree `/Users/kobrien/git/defenseclaw-1.0.7`) |
| Installed CLI and gateway | `/Users/kobrien/.local/bin/defenseclaw` → `~/.defenseclaw/.venv`, 1.0.7; gateway 1.0.7 (`~/.defenseclaw/VERSION` still says 1.0.2, harmless) |
| Upstream main checked | `6b6888d75`; no `cli/defenseclaw/tui`, daemon API or setup changes after the tag |
| Mac app main / starting point | `6ce825f` (v1.1.34) |
| Audit branch / checkout | `kobrien/audit/runtime-1.0.7` at `/Users/kobrien/git/defenseclawmac-runtime-1.0.7` |
| Commits | `d5695f7` adopted 1.0.5 audit · `825a466` 1.0.7 contract changes · final commit: the 12 confirmed gaps + wizard mode |
| Installed release app | `/Applications/DefenseClawMac.app`, 1.1.34; preserved, not replaced |
| Live installation | `~/.defenseclaw` (config schema 9; one connector, `opencode`, in action mode; gateway on 127.0.0.1:18970 running as root from the administrator-mode helper) |

The canonical clone `~/git/defenseclaw_mac` stays on `kobrien/security-gateway-listener-1.1.33` with its pre-existing uncommitted edits; the 1.0.5 audit worktree keeps its uncommitted state. Neither was modified.

## Runtime 1.0.3 → 1.0.7 changes ported (commit `825a466`)

- First-run fail mode offers `policy` (default, sends no `--fail-mode`), `open`, `closed`.
- Config editor: `Decision Model` section (enabled, model, base URL, API key env, timeout, thresholds, on-confident-block, hook connectors) with the runtime's float/URL validation; `guardrail.protected_files` queues a restart.
- Operator asset names fold like Go `EqualFold` (`sigma` ≡ `Sigma` ≡ `SIGMA`, `Kelvin`).
- Sandboxes: no-asks text suffix ("approve that ask to open the port"), 1.0.7 refusal wording (`stop --discard-unsynced`, `exec NAME -- df -h /`, `pull --apply`/`--branch`), `warnings`/`violations`/`old_supervisor` rows.
- `claw.mode` has no `openclaw` default; the connector wizard preselects nothing when nothing is configured.
- Services guardrail detail shows judge fallbacks and a failing/degraded judge state; the effective-policy card explains a user-lookup failure instead of showing a blank profile.
- Approval previews pass `secure_client` to `hilt_change_modal`.

## Confirmed fixes (final commit)

1. **Splunk Enterprise secrets (critical).** 1.0.4 stopped reading `DEFENSECLAW_SPLUNK_HEC_TOKEN`; the wizard now exports the click envvars `DEFENSECLAW_SETUP_SPLUNK_HEC_TOKEN` and `DEFENSECLAW_SETUP_SPLUNK_ACCESS_TOKEN` as well as the legacy names, so the token stays off argv on every supported runtime. Without this, an enterprise apply on 1.0.7 failed with "--hec-token required".
2. **Skip the HEC probe.** 1.0.7 probes the HEC endpoint before saving and saves nothing on failure; the enterprise form gained the `--skip-test` toggle.
3. **Gateway token ladder.** Every rung (`gateway.token_env`, `DEFENSECLAW_GATEWAY_TOKEN`, `OPENCLAW_GATEWAY_TOKEN`, literal `gateway.token`) now skips SecretRef text (`{'source': …}`) that 1.0.5/1.0.6 wrote to `.env`, as `config.resolved_token` does (`GatewayTokenLadder`).
4. **Connector wizard preselection** follows `config.active_connector()`: `guardrail.connector`, else the roster (claw.mode when listed, else its first sorted name), else `claw.mode`; and the Guardrail mode seeds from that connector's effective mode (override, else `guardrail.mode`), re-seeded when the connector or action changes, so an untouched apply no longer downgrades an action-mode connector to observe.
5. **Admission overrides** are the runtime's effective summary (`format_scanner_overrides_summary(admission_action_overrides(cfg))`) shown as the TUI's `overrides` row in Scanners; the raw-YAML card that contradicted enforcement under the 1.0.7 MCP balanced-default compatibility is gone.
6. **Observability storage line.** "Local SQLite · retention=… · controller=… · judge capture=…" and "Event history: … · Judge bodies: …" above the destination table; retention/judge/paths from `inspect_v8_operator_status`, the controller from `/health` `telemetry.details.retention_state`/`retention_failure` with the runtime's token bounds, and "offline (gateway not running)" while the gateway is down.
7. **Scanner availability.** 1.0.7 resolves scanner binaries from its own venv first; a copy next to the `defenseclaw` entry point that is not linked into PATH is now "installed (runtime venv) — not in PATH" with the Fix link kept, and no longer raises the "skill-scanner unavailable" notice.
8. **Runtime Permissions.** While coverage is degraded or partial the Runtime header offers Permissions, which runs the read-only `agent discovery runtime permissions` and shows its output (gated on the installed runtime advertising the subcommand).
9. **Sandbox stop-anyway and delete.** After a stop refused for an unsynced MicroVM disk (exit 5) the row offers "Stop anyway…" → `sandbox stop NAME --yes --discard-unsynced` behind a confirmation; every row has "Delete…" → `sandbox delete NAME --yes` behind a confirmation that says what a copy loses.

Refuted by the verifiers (no change): registry sync partial-sync reporting; AI Discovery disable turning off the Runtime planes.

## Verification

### Automated

- Full standalone suite with `DEFENSECLAW_RUNTIME_PYTHON=~/.defenseclaw/.venv/bin/python` and `DEFENSECLAW_UPSTREAM_ROOT=/Users/kobrien/git/defenseclaw-1.0.7`: 46 PASS, 0 FAIL ([log](runtime-1.0.7/regress.log)). The two Python runners need their opt-ins (`--run-gui`, `--payload`) and were run separately (below).
- New or extended tests: Splunk child-environment names and `--skip-test` (enterprise only); SecretRef token ladder; `active_connector()` and effective guardrail mode; unlinked venv scanner availability; runtime Overview summary parsing (sentinel, bounds, validator error); `/health` retention controller decoding (normalized, unknown state dropped); sandbox stop-anyway/delete argv and dialogs.
- Debug build of production sources with ad-hoc signing: succeeds.
- Runtime dump script run read-only against the installed 1.0.7 interpreter: `{"admission_overrides": "", "storage": {"retention": "7 days", "judge_capture": "enabled", "local_path": "…/audit.db", "judge_bodies_path": "…/judge_bodies.db"}}` in 1.8 s.
- Argv probes against the installed 1.0.7 parser: 110 distinct wizard argv (runtime majors 1 and 0) and all 233 `defenseclaw` registry entries accepted by `--help`; catalog, sandbox, alert and init argv accepted.
- Live `/health` (unauthenticated GET): `telemetry.details.retention_state = healthy`, `retention_days = 7`.

### Native

- Fixture-backed native smoke suite (`script/test_panel_native_smoke.py --run-gui`): PASS, 49 panel/form renders including every setup wizard, the redaction status and the palette (247 runtime-filtered entries); the palette Run button remains the known untested control ([log](runtime-1.0.7/native-smoke.log)). The window-capture bitmap fallbacks in that log are the usual headless-capture notes.
- Debug build launched against the live install (installed app not running): Overview renders the new storage lines ("Local SQLite · retention=7 days · controller=offline (gateway not running) · judge capture=enabled", "Event history: /Users/kobrien/.defenseclaw/audit.db · Judge bodies: /Users/kobrien/.defenseclaw/judge_bodies.db"), the Connectors table (OpenCode, action), and the Scanners card with skill-scanner/mcp-scanner installed and no overrides row (none configured). Setup › Splunk opens on the O11y pipeline; Setup › Connector Setup preselects `opencode` and its review step showed `defenseclaw setup opencode --yes --mode observe` before the mode fix. After the fix the rebuilt Debug app opens the same wizard with Framework `opencode` and Guardrail mode `action` (the connector's live mode). No Apply was pressed.
- Not exercised natively: the Splunk enterprise pop-up (the toggle and argv are covered by `test_setup_definitions_parity.sh`), the Runtime Permissions button and sandbox actions against a live daemon (gateway-backed panels were offline in the Debug app; see below).

## Live finding outside the app patch

The live gateway runs as root from `/Library/PrivilegedHelperTools/DefenseClawMacGatewayAdmin/uid-501/defenseclaw-gateway` (administrator mode was used earlier; the toggle is now off but that process is still the listener). `GatewayListenerTrust.isTrusted` (v1.1.33) verifies the loopback listener with an unprivileged `lsof`, which on macOS lists only the login user's sockets, so the root-owned listener is invisible, the client refuses it as untrusted, and every panel reports "Gateway unreachable on port 18970" although `curl http://127.0.0.1:18970/health` returns 200. Control check: the installed 1.1.34 app launched against the same gateway shows the identical "Gateway unreachable on port 18,970" Overview (its config editor does load the 1.0.7 catalog: 28 sections). `netstat -anv -p tcp` does expose the listener's pid (`defenseclaw-gate:36347`), so the check can be repaired by resolving the pid there and verifying owner and executable from it. A follow-up task was filed; nothing about the gateway was changed.

## Pre-release review (4 November 2026)

Before the branch was merged for release 1.1.35 an adversarial review ran over its source diff (four dimensions — correctness, 1.0.7 contract, security, state/concurrency — times two file groups; every finding re-checked by a tracing verifier and a skeptic). 19 raw findings, 13 confirmed by both verifiers, 6 refuted. The confirmed ones collapse into eight defects, all fixed in the review commit with tests:

1. Sandbox **Policy clamp** rows never rendered: the daemon's `violations` are `sandboxapi.Violation` objects and the decoder kept only strings. The row now shows each violation's `message`, else `detail`, as `sandbox_state.py` does (major).
2. `assetNameKey` used Foundation's full case folding (ß → ss, ﬁ → fi); the runtime's `asset_name_key` is Go's simple `EqualFold` table. The runtime's `FOLD_RUNS` is embedded (`GoCaseFold`) and the expected values were checked against the installed 1.0.7 interpreter.
3. `claw.mode` had lost the loader's `openclaw` default on the false premise that 1.0.7 dropped it; 1.0.7 keeps the default and gates it with `has_connector_configured()` / `_mark_openclaw_not_installed` (loopback gateway, no fleet link, no openclaw.json or binary). The app now mirrors both (`hasConnectorConfigured`, `displayClawMode`, `OpenClawPresence`); an explicitly empty mode (what `setup remove` persists) stays empty.
4. The Overview dump dropped the TUI's generic "telemetry status could not be loaded; run defenseclaw observability validate" line for non-validator failures.
5. A summary dump SwiftUI cancelled (task id changed) blanked the storage and overrides rows.
6. The skill-scanner notice read the probe paths before the first pulse resolved them, so a venv-only install could flash "unavailable" at launch.
7. The Runtime Permissions button had no in-flight guard and the sheet was not reset on installation change.
8. The sandbox "Stop anyway…" offer was keyed on the name alone, so a later sandbox created under the same `--name` inherited it; it is keyed on name and creation time and pruned with every snapshot.

Refuted (no change): destination `enabled` fallback, positional sandbox name shape, applied-policy `lookup_error` bounds, the Decision Model URL validator (two findings), and the Overview dump's temp config copy.

## Remaining known gaps

- Setup panel status/summary column (off connectors, last check passed/failed, redaction profile) is a 1.0.7 TUI addition that was never ported (minor).
- Overview tile guardrail-profile and static-catalog leftovers from the 1.0.3 report remain as listed there.

## Reproduction

```sh
export DEFENSECLAW_RUNTIME_PYTHON=/Users/kobrien/.defenseclaw/.venv/bin/python
export DEFENSECLAW_UPSTREAM_ROOT=/Users/kobrien/git/defenseclaw-1.0.7
./script/test_setup_definitions_parity.sh
./script/test_config_editor_contracts.sh
./script/test_resource_boundaries.sh
./script/test_sandbox_models.sh
for s in script/test_*.sh; do "$s" >/dev/null 2>&1 && echo "PASS $s" || echo "FAIL $s"; done
xcodebuild -project DefenseClawMac.xcodeproj -scheme DefenseClawMac \
  -configuration Debug -destination 'generic/platform=macOS' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
git diff --check
```

No push, PR, release, installed-app replacement, runtime change, gateway restart or live configuration change was performed.
