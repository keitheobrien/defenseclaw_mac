# DefenseClaw TUI alignment — 7 October 2026

The working branch `kobrien/tui-parity-2026-10-07` adds the missing current TUI surfaces to the standalone Mac app. All 16 panels have been rendered with disposable data, all 23 native wizard forms have opened, and the full automated suite and a fresh Debug build pass. This verifies the app and its contracts; it does **not** certify live execution of every external integration.

## Exact targets

| Target | Identity |
| --- | --- |
| DefenseClaw main, local and GitHub | `95159fdb849d265f31e31a0ef92eff5e40ebbee0` (remote rechecked during verification) |
| Runtime | `1.0.0`, configuration schema `8` |
| Terminal CLI checked initially | `/Users/kobrien/.local/bin/defenseclaw`, resolving to `/Users/kobrien/git/defenseclaw/.venv/bin/defenseclaw`; see the post-launch correction below |
| Runtime source | Clean `/Users/kobrien/git/defenseclaw`, same commit as above |
| Standalone app starting point | `893487e804a343cc266c2625ebf82a5df80c8367` |
| Release candidate | Version `1.1.26`, build `1`, on the branch above |
| Installed release | `/Applications/DefenseClawMac.app`, bundle `com.keitheobrien.DefenseClawMac`; not replaced |
| Native test build | Ad-hoc Debug, disposable source copy, separate bundle ID `com.keitheobrien.DefenseClawMac.ParityTest` |
| Live installation read checks | `/Users/kobrien/.defenseclaw/config.yaml`, default canonical `audit.db`, loopback port 18970 |

The compatibility and feature-verification skills were used. The runtime checkout, installed app, gateway settings, credentials, hooks, enforcement policy, and release assets were preserved. The pre-existing untracked `POST_REINSTALL_VERIFICATION_2026-09-21.md` was left untouched.

## Implemented coverage

- **Policies:** native panel backed by the selected runtime's actual TUI policy model. All seven views are available: posture, opt-in packs, chains, rule families, named policies, rule packs, and sandbox packs. Scope, inherited values, full details, and action consequences come from that model. Tool-call thresholds remain distinct from LLM policy thresholds. Reductions in protection require acknowledgement; rule packs must validate before switching. Mutations use CLI argument arrays and Activity. Stale/failed catalogs cannot authorize changes.
- **Sandboxes:** status, sandbox list/detail, pending asks, activity, approve/reject/unblock, stop/undo confirmation, review and copy-mode pull commands, Overview summary, menu-bar section, and optional notifications. Decisions use CLI plus Activity. Unavailable reads retain the last snapshot and show an error; stale data disables decisions even if cached gateway health is still good. Malformed responses cannot appear as an empty or disabled service.
- **Local models:** AI Discovery now separates products from identified local models. Model browsing includes recommended/all, modality, relevance, discovery confidence, owner, status/format, sources, runtime details, and lineage metadata. Legacy observations remain readable. Detail panes use the app's existing layout fix.
- **Setup:** ACP Guard enrollment; redaction entry points in Setup and Logs; all 21 advanced redaction operations; current OpenShell configuration and macOS MicroVM setup workflow. Redaction is capability-gated for older runtimes. Advanced changes default to dry-run; previews cannot restart the gateway. Managed ACP uses administrator-provisioned file paths instead of secret values in arguments. Sandbox setup no longer incorrectly excludes macOS.
- **Commands and persistence:** regenerated all **253** registry entries; corrected the audit helper's schema-8 detection and Swift Unicode escaping; preserved canonical SQLite event history and added the upstream unchanged-snapshot optimization. An oversized first database row is unavailable data, not a successful empty history.

## Verification performed

**PASS:** 41 standalone test scripts, fresh Debug compile, and `git diff --check`. The aggregate inspector script reports **SKIP/WARN** by default; it was separately run with `--run-gui`, and both native and accessibility selection cases passed. Those cases exercise selection, deselection, close/reopen, resizing, asynchronous detail hydration, parent refreshes, and a 20-second open-inspector dwell.

The native smoke runner creates an isolated SQLite/config/log fixture, a mock CLI, and a loopback API server. It compiles the actual production views into a temporary native window host. It renders every panel, selects available table rows, captures detail views, and resizes from 1180 to 980 points. It also opens all four Settings tabs, all 23 wizard forms, redaction, and the command palette. A harmless fixture version command completes through AppState/CLIRunner and appears in Activity. A fixture sandbox unblock reaches the mock CLI; an HTTP 503 then preserves rows, disables actions, refuses another command, and recovers after a successful refresh.

The original app entry point did not expose a window in the isolated launch, and external System Events inspection stalled. The disposable native host avoids that environment limitation. Therefore the test establishes native view behavior, not installed-app launch/reopen behavior. Native tests produced an existing Charts anchor warning and a palette table delegate reentrancy warning without a crash; future SDK behavior remains a follow-up risk.

### Per-panel matrix

“Native PASS” below means the stated fixture behavior was exercised. External writes and real services are listed separately.

| Panel | Tested operation and result | Additional automated evidence | Unverified live behavior |
| --- | --- | --- | --- |
| Overview | Native PASS: synthetic gateway/connector status and summary table render; selection/resize | App-state safety, overview read-only guidance, gateway auto-start contracts | Real gateway start/stop/restart and telemetry delivery |
| Alerts | Native PASS: synthetic finding loads; selection/detail/deselection/resize | Alert queue projection, canonical history, native inspector regression | Persisting an acknowledgement in the user's database |
| Logs | Native PASS: fixture gateway rows and detail; new redaction entry present | Canonical SQLite event history, output safety, resource bounds, structured detail parser | New real runtime events and downstream redaction delivery |
| Audit | Native PASS: four fixture canonical events load; detail/resize | Canonical history, bounded database reads, resource tests | User-data export; manual pagination through a large live history |
| Activity | Native PASS: completed fixture command recorded, output/detail/resize | CLI cancellation, command activity/output safety | Cancelling a real long-running external operation |
| Skills | Native PASS: fixture catalog row and detail/resize | Catalog action safety, connector inventory compatibility, onboarding | Installing, enabling, disabling or scanning a real skill |
| MCPs | Native PASS: fixture catalog row and detail/resize | Catalog action safety, connector inventory compatibility | Real server installation/scanning and connection |
| Plugins | Native PASS: fixture catalog row and detail/resize | Catalog action safety, connector inventory compatibility | Real plugin installation/scanning |
| Tools | Native PASS: fixture policy row and detail/resize | Catalog action safety and resource contracts | Persisting real allow/block policy |
| Policies | Native PASS: two scopes, effective posture, selected detail and action menus | Real runtime reader tests for all seven views, thresholds/inheritance, weakening, partial errors; Swift decoder/action gate | Applying a real policy/pack or changing enforcement; individual menu actions tested at contract level |
| Sandboxes | Native PASS: sandbox row/detail, one ask and activity; mock unblock; stale state, blocked decisions and recovery | Sandbox model/admin-lock/feed tests; strict API shape and 403 tests | Starting a real OpenShell VM/session, approvals, pull/undo effects, notifications |
| Inventory | Native PASS: entry-triggered scan intercepted by mock CLI; fixture inventory and detail | All connector category/capability contracts | Scanning actual user content or external services |
| AI Discovery | Native PASS: product table and separate one-row model table; selected details/resize | Grouping, legacy metadata, provenance, modality/relevance filters, action contracts | Actual host discovery, model detector completeness, external provenance lookups |
| Runtime | Native PASS: fixture coverage/empty-findings presentation | Runtime route/shape/degraded-state tests, numeric and output safety | Live sensors, elevated Endpoint Security, finding generation; service disabled live |
| Registries | Native PASS: intentional no-configured-sources state | Index limits, inventory capabilities, supply-chain tests | Registry synchronization, remote trust checks and installs |
| Setup | Native PASS: setup/config sections and 23 wizard forms plus redaction | Setup definitions, secret transport, current options, sandbox and ACP argument builders | Applying real setup, credentials, provider/webhook connectivity, hooks or restarts |

Search/filter logic is covered by the relevant pure-logic tests; a manual interaction sweep of every filter and pagination control was **NOT TESTED**. The palette's version row could be selected, but its Run button was unavailable through the test host's accessibility tree; that button click is **NOT TESTED**, separately from the successful AppState/CLI/Activity version check. Empty fixture states are recorded above rather than counted as loaded real data.

### Setup and auxiliary surfaces

The current TUI has 22 canonical setup areas. The native app covers them through 23 wizard forms plus a dedicated redaction sheet; standalone Cisco AI Defense and Galileo forms remain available.

| Native form/surface | Native result | Execution coverage |
| --- | --- | --- |
| Connector Setup | PASS render | Existing onboarding, roster, argument and safety tests |
| Credentials | PASS render | Hidden secret transport tests; no credential changes |
| Cisco AI Defense | PASS render | Existing masked-review/secret rules; external request NOT TESTED |
| LLM | PASS render | Provider/default/region argument tests |
| Local OTel | PASS render | Setup/catalog contracts; collector delivery NOT TESTED |
| Galileo | PASS render | Observability arguments; ingestion NOT TESTED |
| Token Rotation | PASS render | No live rotation |
| Custom Providers | PASS render | Provider family/URL/secret validation tests |
| Skill Scanner | PASS render | No live external scan |
| MCP Scanner | PASS render | No live external scan |
| Gateway | PASS render | Lifecycle/signed-helper/auto-start tests; live control NOT TESTED |
| Guardrail | PASS render | Current connector and threshold contracts |
| Splunk | PASS render | Verified-TLS default test; HEC delivery NOT TESTED |
| Observability | PASS render | Preset arguments and absence of unsupported connector flag |
| Webhooks | PASS render | Provider-specific arguments and credential validation |
| Sandbox | PASS render | Current harness/wrapper/image-skip arguments and validation; no VM install |
| Registries | PASS render | Current CLI/config contracts; no trust-policy changes |
| Notifications Routing | PASS render | No real destination delivery |
| AI Discovery | PASS render | Enabled/disabled arguments, config defaults and range validation |
| Splunk Dashboards | PASS render | No dashboard installation |
| Trusted Paths | PASS render | No changes to trusted filesystem scope |
| Guardrail Actions | PASS render | No live enforcement changes |
| ACP Guard | PASS render | Client/agent/profile, observe/action and managed-path argument tests |
| Redaction Policy | PASS render | All 21 advanced action builders, dry-run/restart, validation and literal argv tests |
| Settings: General / Monitoring / Notifications / Connection | PASS render, all four | Installation, update and helper contracts; login launch and actual notification delivery NOT TESTED |
| Command palette | PASS native list/render and selection | All 253 source entries match; fixture capability filtering shows 251; baseline showed 233 of 235 |

### Live read-only checks

The selected SQLite database has the required canonical events, scan results, actions and acknowledgement projection tables; a bounded row read passed. Authenticated loopback reads returned HTTP 200 for health, AI usage, runtime and sandbox status. AI Discovery and Runtime reported `enabled=false`; Sandbox reported `enabled=false, available=false`. Sandbox list/approval reads returned HTTP 503. These are **disabled services**, not a clean-host security result or successful sandbox integration. Credentials stayed in memory; report artifacts contain no tokens or raw user records.

## Evidence and reproduction

- [Full automated audit](tui-parity-2026-10-07/automated-audit.md)
- [Native panel/form run](tui-parity-2026-10-07/native-panels.log)
- [Native inspector regression](tui-parity-2026-10-07/native-inspector-results.json)
- [Source differences and hashes for review](tui-parity-2026-10-07/source-deltas.json)
- [Before: AI Discovery](../images/tui-parity-2026-10-07/before-ai-discovery.png), [after: products](../images/tui-parity-2026-10-07/after-ai-products.png), [after: model details](../images/tui-parity-2026-10-07/after-ai-models.png)
- [Before: Setup](../images/tui-parity-2026-10-07/before-setup.png), [after: Setup](../images/tui-parity-2026-10-07/after-setup.png)
- [Policies](../images/tui-parity-2026-10-07/after-policies.png), [Sandboxes](../images/tui-parity-2026-10-07/after-sandboxes.png), [unavailable Sandbox](../images/tui-parity-2026-10-07/after-sandboxes-unavailable.png)
- [ACP form](../images/tui-parity-2026-10-07/after-acp.png), [Redaction form](../images/tui-parity-2026-10-07/after-redaction.png)

All screenshots show synthetic fixtures in a native test host. Before images use the starting commit listed above. Individual hosted views can retain a toolbar from the preceding test view; the host does not establish full-window navigation fidelity.

```bash
python3 .codex/skills/defenseclaw-runtime-compat/scripts/audit_compatibility.py \
  --mac-root "$PWD" --upstream /Users/kobrien/git/defenseclaw \
  --runtime-bin /Users/kobrien/.local/bin/defenseclaw --run-tests --build
./script/test_inspector_native_layout.sh --run-gui
python3 script/test_panel_native_smoke.py --run-gui
git diff --check
```

The native runner requires a logged-in macOS desktop and Xcode. Its CLI and API write only disposable fixture data. It never launches the real gateway. Native output logs and all screenshots are retained in the temporary artifact directory printed by the runner.

## Review and remaining gates

### Post-launch correction: default runtime selection

The user's subsequent native Policies test exposed a gap in the original fixture verification: without a `DEFENSECLAW_VENV` override, the app selected the leftover `~/.defenseclaw/.venv` runtime (0.8.10). Its Python lacked `defenseclaw.tui.policy_panel`, although the terminal's published launcher selected source runtime 1.0.0. The initial terminal/runtime check did not prove the GUI selected that same executable.

The resolver now follows a user's published `~/.local/bin/defenseclaw` symlink into a verified venv layout for the default unmanaged installation, preserving config/data paths. Explicit config/home/venv choices and managed installations stay pinned. Catalog Python resolution prefers the interpreter adjacent to the selected CLI, including a Settings CLI override. Unsupported policy modules produce actionable guidance rather than a traceback.

Regression checks cover simultaneous old/new runtimes, unchanged config/data paths, explicit venv/home choices, managed configuration, missing/non-venv launchers, CLI/Python ordering, and friendly errors for old runtimes. Installation-context and output-safety suites, all four policy bridge tests, and a fresh Debug build passed. The development app was rebuilt and reopened for native confirmation. The earlier fixture logs and full-suite audit remain historical evidence, not results for these subsequent changes.

Native confirmation **PASS**: the rebuilt normal application, without fixture overrides, loaded five posture scopes (global and four connectors) in Policies with no module error. The existing config and data paths were preserved; neither runtime was upgraded or deleted. The actual-installation screenshot is retained only in `/private/tmp/defenseclawmac-policies-fixed.png`, outside the publishable synthetic screenshots.

### Post-launch correction: partial MCP discovery

The user's MCP panel exposed a separate live permissions failure. `~/.claude/settings.json` was root-owned with mode `0600`, so the normal user could not read it. DefenseClaw emitted valid MCP JSON for readable sources, then an unreadable-source diagnostic on stderr and exit status 1. The app rendered the JSON as its error, obscuring that diagnostic.

The catalog now recognizes only the runtime's explicit MCP source-discovery partial-result contract: complete valid JSON, exit 1, no cancellation/truncation, and known source diagnostics. It displays readable entries with an incomplete-discovery warning and disables catalog actions. Other command failures remain failures; their diagnostic is separated from the JSON. Source-discovery errors no longer offer the unrelated audit-database repair action.

With explicit user approval, ownership of that single Claude Code settings file was restored to UID 501. Its contents were not changed and mode remains `0600`. The real MCP listing subsequently returned exit 0, no stderr, four connector groups and two entries. Catalog action-safety regression tests and the fresh Debug build passed, and the app was reopened for the user. No broad directory ownership/permission changes were made.

The initial automated audit exited **1** solely because its compatibility baseline recorded an older upstream commit and source hashes. Its 41 executed test scripts and Debug build passed. The default native-test skip was separately resolved by the explicit GUI run. A new complete release-candidate audit includes both post-launch fixes; its report is recorded separately below.

The [runtime compatibility skill](../.codex/skills/defenseclaw-runtime-compat/SKILL.md) requires: “After human review, record the exact known-good commit and intentional source deltas”. Following the user's local development testing and explicit request to commit and publish this build, the baseline records runtime commit `95159fdb849d265f31e31a0ef92eff5e40ebbee0` and 38 reviewed source differences. Each difference includes a specific rationale covering standalone identity, runtime installation/updating safeguards, catalog fallback protections, helper signing, or the new native TUI surfaces.

Signed packaging and notarization are separate release gates. Clean-machine install/upgrade, root-helper authorization, live provider/telemetry delivery, real sandbox lifecycle and runtime sensor coverage remain separate integration checks. No live service was enabled merely to turn an untested case into a pass.

### Runtime distribution boundary

The latest published runtime checked on 7 October 2026 is `0.8.10`; current source main identifies itself as `1.0.0`. The unified installer uses the authenticated published `0.8.10` payload. Existing newer or source-managed runtimes are preserved. Newer Policies, Sandbox, ACP and redaction capabilities require a compatible runtime; the app update alone does not add those capabilities to `0.8.10`. Policies displays an actionable unsupported-runtime message when its model is absent. The app-only ZIP does not replace the installed runtime.

### Release-candidate rerun

The [1.1.26 release-candidate audit](tui-parity-2026-10-07/release-1.1.26-audit.md) passed after both post-launch fixes: all 41 executed test scripts, the fresh Debug build, runtime probes, and the 38-difference reviewed baseline. The native inspector runner remains opt-in; its earlier explicit GUI results are linked above. `git diff --check` also passed.
