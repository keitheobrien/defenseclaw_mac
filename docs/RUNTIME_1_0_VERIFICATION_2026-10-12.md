# DefenseClaw runtime 1.0 compatibility and release verification

## Target and boundaries

- Mac app: **1.1.27**, Apple silicon, standalone bundle/release identity retained.
- Runtime: official **1.0.0** release, source **57698deb67c902e563ed10114a20dbab010f8922**, configuration schema **9**.
- Release wheel tested in an isolated Python 3.12 environment. Dependencies were installed from the release's complete hash-locked requirements file without resolving a replacement dependency set.
- Local runtime main/source installation was **1173ebed4f9bc30036a039ace8eb8f58dbd40884**, newer than the release. It was inspected for differences but was neither replaced nor used as a substitute for testing the published wheel.
- Existing installed app, gateway process, live configuration, audit database, credentials, and connector hooks were preserved. The unrelated pre-existing `POST_REINSTALL_VERIFICATION_2026-09-21.md` was excluded.

The compatibility, feature-verification, security, and signed-release workflows were used. The reviewed baseline records reasons for each retained standalone difference; it applies to this exact release commit, not unseen future mainline changes.

## Changes

- Match all **251 TUI registry entries** and the selected runtime's **24 setup-catalog sections**. Preserve runtime capability filtering and secret transport.
- Adopt schema-9 admission actions, rule-pack names, scanner keys, and current CLI flags. Remove retired registry sync settings and unused catalog mutation endpoints.
- Use the 1.x canonical `alerts --json` queue, including compatibility findings, non-allow decisions, actionable errors, and user/agent/session facts. Failed reads remain visibly unavailable/stale. Legacy runtime support remains separate.
- Add IDE extension inventory, connector-independent enablement/AI filters, stable agent identities, bounded-list notices, and scans without configured connectors. Ignore results from a previously selected installation.
- Show applied policy digest/generation, account profile, and configured admission overrides separately from base configuration. Profile resolution uses the authenticated loopback API and a one-minute refresh limit.
- Active-policy threshold changes affect tool calls, prompts, completions, and LLM traffic. Inactive-policy changes retain their named-policy target until activation.
- Support the official flat release assets. Verify the Sigstore checksum bundle with an exact workflow identity and OIDC issuer; bind source identity to the verified Fulcio certificate. Verify every required artifact checksum before use.
- Sign both gateway and ACP with Developer ID. The fresh-install transaction includes Python CLI, gateway, CLI link, ACP, the release-owned installer, and VERSION metadata. All six activation boundaries use existing inode-bound no-replace rollback/recovery.
- Existing installations use the selected runtime's upgrader. `DEFENSECLAW_APP_PATH=none` preserves the independently released Mac app. Equal/newer and source-owned runtimes are not replaced.

## Verification

**Passed:** 42 standalone regression scripts; Debug compilation; shell/Python packaging validation; `git diff --check`. The inspector GUI script is opt-in in the aggregate suite and was separately run successfully in both native and accessibility modes. Focused tests were rerun after later parser/filter changes.

**Passed:** real fresh installation into a disposable HOME using the signed 1.0 payload. The installed CLI, gateway, and ACP each reported 1.0.0; installer/VERSION metadata was present; activation journal was retired; a second installation was refused. This test found and fixed ACP's executable-name version parsing. A failed attempt rolled back before activation. The harness's temporary-path alias and explicit-missing-config checks were corrected without weakening production guards.

**Passed:** disposable native host built from the production views using the published wheel for dynamic catalogs, synthetic CLI/API/audit fixtures, all 16 panels, IDE/agent detail views, four settings tabs, 23 wizard forms, redaction, and the palette. It exercised Activity recording, a sandbox decision, stale-state refusal, recovery, detail selection, and resizing. The palette's native accessibility Run button was not exposed in this environment; the harmless command-to-Activity path was exercised directly. Existing Charts/accessibility/table warnings did not crash the host. This establishes view behavior, not a clean-machine installed-app certification.

| Surface | Verified behavior | Integration limits |
| --- | --- | --- |
| Overview | Native dashboard/configuration; profile/digest response projection and failure tests | Real directory-service profile matching not changed or exercised |
| Alerts | Canonical JSON projection, compatibility rows, agent facts, block/scan filters, error state and inspector | Live acknowledgement intentionally not sent |
| Logs | Canonical event history, bounded readers, source tabs and native detail | External telemetry delivery not exercised |
| Audit | Read-only SQLite projection, bounds, replacement handling and native rows | No live audit export or migration |
| Activity | Version command completion/recording, cancellation regressions and native inspector | Privileged live lifecycle not repeated |
| Skills / MCPs / Plugins | Runtime catalog parsing, read-only fallback/action guards, native rows/detail | No real asset installation/removal |
| Tools | Runtime CLI policy catalog, action guards and native rows | No live enforcement changes |
| Policies | All seven bridge views and actions; active/inactive threshold regression; native posture | No live policy activation or weakened protection |
| Sandboxes | Fixture status/list/asks/activity, recorded decision, stale/error refusal and recovery | Real Linux/MicroVM/cloud sandbox provisioning not exercised |
| Inventory | Connector projection, IDE and stable-agent parsing, native IDE/agent detail, generation guard | No new scan against live connector homes |
| AI Discovery | Product/local-model grouping, capability actions, metadata and native detail | Real external detectors not reconfigured |
| Runtime | Coverage/degraded/malformed-response regressions and native empty state | Endpoint Security/root/Full Disk Access remains host-dependent |
| Registries | Bounded source/index parsing, current schema, native empty state | No external registry sync/install |
| Setup | Published dynamic catalog and current argument builders; native forms, masking and validation | Provider credentials, webhook delivery, and real hook enrollment not submitted |
| Settings / lifecycle | Native tabs; update/version preservation, startup/helper and lifecycle regressions | Launch-at-login and privileged authorization not changed |
| Distribution | Verified inputs and real isolated six-component fresh install | Apple notarization and fresh-download verification recorded in the GitHub release notes |

Evidence: [automated audit](runtime-1.0/automated-audit.md), [native renders](runtime-1.0/native-panels.log), [fresh install](runtime-1.0/fresh-install.log). Screenshots: [IDE inventory](../images/runtime-1.0/inventory-ide.png), [agent detail](../images/runtime-1.0/inventory-identities-detail.png), [alert attribution](../images/runtime-1.0/alerts-detail.png), [policy posture](../images/runtime-1.0/policies.png).

## Upgrade considerations

The runtime's 1.0 upgrader owns configuration migration and rollback. Migration to schema 9 preserves the old audit database in its rollback snapshot, starts new audit history, and defaults retention to seven days. The app displays that consequence before providing an upgrade command. It does not migrate a user's installation during app replacement.

The shipped payload is the published 1.0.0 release. Later upstream-main fixes, including upgrade-after-rollback changes, are not silently substituted into the release. External providers, managed enterprise deployment, and host-specific runtime sensors require separate integration verification.
