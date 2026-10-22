# DefenseClaw TUI alignment — 22 October 2026

The branch `kobrien/fix/runtime-1.0.3-contracts` brings the Mac app back to parity with the DefenseClaw runtime and TUI at 1.0.3, the version this machine runs. Every panel and every Settings tab was rendered against the live install, the runtime's contracts were probed read-only, the TUI source delta since the last audit was diffed cluster by cluster, and every candidate gap was adversarially verified against both code bases before it was fixed. This verifies the app and its contracts; it does **not** certify live execution of every external integration (sandboxes are not set up on this machine, AI Discovery is disabled).

## Exact targets

| Target | Identity |
| --- | --- |
| DefenseClaw runtime source | `a4e0e587f` on `origin/main` of cisco-ai-defense/defenseclaw, tag `1.0.3` (the only commit past the tag is docs-site only) |
| Installed runtime | `defenseclaw, version 1.0.3`; gateway commit `46f444a78`; `~/.defenseclaw/VERSION` still says 1.0.2 (informational drift, the CLI and gateway agree on 1.0.3) |
| Previous Mac audit baseline | runtime `95159fdb` (1.0.0), `docs/TUI_PARITY_VERIFICATION_2026-10-07.md` |
| Mac app starting point | `057b265` (release 1.1.31) |
| Mac app result | `7841bbb`, 17 commits on the branch above, not pushed |
| Installed app | `/Applications/DefenseClawMac.app` 1.1.31, relaunched after the walkthrough; not replaced |
| Live installation read checks | `~/.defenseclaw/config.yaml`, `audit.db` (read-only), loopback port 18970, `defenseclaw status --json` |

The runtime checkout, installed app, gateway, credentials, hooks, enforcement policy, and config.yaml were preserved (config.yaml mtime unchanged after the walkthrough). The pre-existing untracked `POST_REINSTALL_VERIFICATION_2026-09-21.md` was left untouched.

## Contract probe (runtime 1.0.3)

30 Mac-consumed surfaces were probed read-only: 22 unchanged, 5 changed and now handled, 1 broken and fixed, 1 unverifiable here, 1 informational.

- **Fixed:** `setup galileo test --direct` was removed upstream (0.8.5); the wizard emitted it. `keys set` now documents `--value-stdin`; the app appends it on 1.x runtimes so the secret transport is explicit.
- **Informational:** the legacy proxy REST routes (`/skills`, `/mcps`, `/plugins`, `/tools/catalog`) return 404 on 1.0.x (502 on 0.8.x); the catalog panels already use `defenseclaw <resource> list --json`. `gateway.jsonl` and `doctor_cache.json` are absent on a 1.0.x install; the app's canonical SQLite history covers them.

## Confirmed gaps and what changed

The focused extraction ran four cluster reviewers (setup, monitor/govern, discover/shell, sandboxes) over the TUI delta `95159fdb..origin/main` and 32 verifiers over their 32 candidates; all 32 were confirmed, none refuted. Each is addressed below unless listed under "Remaining".

### Critical

| Gap | Fix |
| --- | --- |
| Overview enforcement counters read audit.db `actions`; 1.0.x operator block/allow decisions live in config.yaml `asset_policy` (both monitor and discover clusters flagged it; the live Overview showed 0 blocked after `skill block`) | `OperatorAssetLists` mirrors `enforce/asset_lists.py` (install_counts, merge_operator_entries, asset_name_key, connector normalization, Secure Client exemption via `_enterprise_profile`); the Overview folds the lists into the journal. Live check: Overview now shows 1 blocked skill, 2 blocked MCPs, matching `defenseclaw status --json`. |
| Skill Scanner wizard offered the retired policy `none`, defaulted to `balanced`, and could not select `quiet`/`low-noise`; an untouched apply moved a stock install from quiet to balanced | Policies now `strict, balanced, permissive, low-noise, quiet` (default quiet); the wizard follows the TUI form rule (a field left at its opening value emits no flag). Live check: untouched Review shows `defenseclaw setup skill-scanner --verify --non-interactive`. |

### Major

| Gap | Fix |
| --- | --- |
| Tools panel fell back to leftover 0.x `actions` tool rows the gateway no longer enforces | Audit rows only on Secure Client; otherwise config.yaml `asset_policy.tool` rules (`tool_rule_entries`). |
| Skill Scanner wizard lacked Block At, Review From, OSV checks, LLM base URL; scanner wizards reset the judge to anthropic on every untouched Run (and blanked `llm.base_url` on 1.0.3) | Fields added; providers widened to `WIZARD_LLM_PROVIDERS + openai-compatible`; analyzer toggles open on the configured value and can turn an analyzer off (`_cfg_bool_field`); MCP wizard gains API endpoint/key-env/timeout. |
| Observability add had no `--allow-private-networks`; the default localhost Splunk HEC add fails on 1.0.3 | Toggle added for splunk-hec (TUI) and the other typed-endpoint presets. |
| First-run hook fail mode defaulted to open and was sent in every profile | Defaults to closed; action profile only, with the TUI's hint. |
| Config editor dropped the draft on refresh, never rebased it onto a changed config.yaml, never marked keys another writer changed | Draft rebase (`_rebase_config_draft`), "(changed on disk; saving replaces it)" marker, rebase on the pulse's disk reload. |
| Alerts never said how many detection-only findings were not listed | `count_detection_only_findings` ported; the TUI sentence renders under the header and in the empty state (none in the last 24 h on this machine, so the line is correctly absent). |
| AI Discovery folded a sandbox's signal into the host row and printed its frozen uptime | `sandbox_name` joins the group key; rows read "product (sandbox NAME)"; uptime counts from `started_at`. |
| Invalid config.yaml was not detected; the lenient parser's guesses were rendered | The pulse runs `config validate` when the file changes on disk; a parse error keeps the last valid snapshot and raises "config.yaml line N is invalid; run defenseclaw config validate". |
| Sandboxes: another account's OpenShell gateway still said "Run Setup" | `gateway_elsewhere` decoded; headline and empty state send the user to `sandbox doctor`. |
| Sandboxes: process tree not shown | `GET …/processes` rendered like `process_tree_lines` (12 lines, children under parents, daemon's sampling interval). |
| Sandboxes: credential-placeholder refusals misattributed to "DefenseClaw answered HTTP 400"; no recovery line | Placeholder attribution, persistent alert with the `sandbox connect NAME` remedy, "hooks answered again since HH:MM:SS". |
| Sandboxes: Alerts column ignored the alerts a sandbox raised | Alerts panel rows counted per sandbox since `created_at` in the column, detail and Overview metric. |
| Sandboxes: no AI destination counts | Sites shows model providers, harness vendor hosts, shadow AI; detail gets a Sites row. |

### Minor

| Gap | Fix |
| --- | --- |
| SSH (port 22) blocks showed a raw token | "SSH does not leave a sandbox: use an HTTPS remote"; never offers Unblock. |
| Blocked-destination reason tokens shown raw; repeats and host alias unworded | The runtime's reason table ported; metadata/link-local text; "(and N more like it)"; "(port N on this machine)". |
| Repo policy row, harness image (not the MicroVM run image), detached-run outcome, pull to a named branch | All added, mirroring `detail_pairs`, `detached_run_text`, `branch_name_problem`. |
| Config diff sheet always said "Save and queue restart" | "Save" unless a changed key is in `config_writer.RESTART_KEYS` (Secure Client always). Live check: a `quarantine_dir` draft shows "Save". |
| Sandbox wizard pre-checked `--install-openshell`, which 1.0.x turns into an in-place upgrade plus gateway restart | Opt-in, with the consequence named. |
| IDE plugins showed raw `enabled`/`remote_kind` values, no "(N+)", no count summary | Worded like `agent ide-plugins`; exact chip matching; partial marker; "N (X AI, Y disabled, Z users)". |
| Audit, alert, scan, activity and egress reads ordered by timestamp alone | `rowid DESC` tie-break on every ordered read, as db.py. |
| Static fallback config catalog stale for the scanner section | Policy presets, Block At, Review From, Judge Source, Use OSV added. |

### Remaining (minor, documented, not changed)

- Overview guardrail tile, SCANNERS and SERVICES rows show config.yaml mode/pack rather than the resolved guardrail profile when `guardrail.profiles` assigns a different mode to the operator's account (the Effective policy card on the same page is correct).
- The admission-overrides card lists config.yaml rows verbatim where the TUI resolves per-type defaults against the built-in tables and the scanner gate.
- The static fallback config catalog still lists the retired `binary` rows and lacks some v9 keys outside the scanner section; the runtime-generated catalog (the normal path) is unaffected.
- The config editor uses the ported restart-key table rather than the `cfg.save()` result; the two agree as of 1.0.3.

## Verification performed

**PASS:** 46 standalone test scripts (four new: operator asset lists, config editor contracts, plus extended setup, sandbox, inventory, discovery and connector suites), fresh Debug compile after every commit, `git diff --check`, and the native panel smoke runner with `--run-gui` (49 renders, 0 failures, 1 not-tested palette Run button as before).

**Live walkthrough** of the Debug build against the running 1.0.3 install (computer-use, read-only; the installed app was quit for the duration and relaunched afterwards): Overview (counts cross-checked with `defenseclaw status --json`), Alerts (342 unacknowledged, no detection-only findings so no footnote), Setup > Skill Scanner (form opens on quiet; untouched Review emits only `--verify --non-interactive`), Sandboxes (off on this machine, ordinary off state), Inventory (47 items after the panel's scan; IDE Plugins card), AI Discovery (disabled state), Config Editor (draft of `quarantine_dir` → Review shows "Save"; Cancel and Revert restored the on-disk value; config.yaml untouched). Tools shows "No tool policy rows", matching the TUI's empty list on an install without `asset_policy.tool` rules.

Earlier in the same session (release 1.1.31 on 1.0.3): all 16 panels and all 4 Settings tabs rendered correctly, the in-app runtime updater was exercised (1.0.1 → 1.0.3 visible in Activity), catalog first loads took 10–15 s during app warm-up and about 1 s afterwards (the loading strip in `a4d4363` covers that), and Inventory requires Rescan by design.

## Environment finding (not an app defect)

While building, `swift-frontend` failed to spawn (EAGAIN): the user's process table held ~3,100 `~/.defenseclaw/notify-bridge.sh` and ~1,600 `SkyComputerUseClient` processes against the 4,000 per-user limit. The runtime's generated Codex notify bridge calls the previously configured notify hook, which is Codex Computer Use's `SkyComputerUseClient turn-ended --previous-notify ["bash", notify-bridge.sh]`, which calls the bridge again: a mutual recursion per Codex turn that only stops at the process limit and unwinds over a few minutes. Codex `config.toml` has `notify = ['bash', '~/.defenseclaw/notify-bridge.sh']`. This is a runtime bridge-generation bug (it captured a wrapper that already chains back to the bridge); nothing was changed, the storm was allowed to unwind, and the builds were retried.
