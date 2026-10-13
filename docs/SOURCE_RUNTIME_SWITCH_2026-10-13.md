# Explicit source-to-release runtime switching

## Diagnosis

The 1.1.28 app correctly detected the active source launcher, which resolved into the development checkout's venv and reported 1.0.0. A separate release venv still reported 0.8.10. The existing source marker disabled ordinary in-app upgrades even when GitHub advertised runtime 1.0.1. This was an ownership restriction, not a missing app update.

The authenticated 1.0.1 installer supports replacing the active launchers from a source installation and intentionally leaves the checkout alone. It does not delete the historical source marker. The old app would therefore keep treating the runtime as source-owned even after a successful external switch.

## Change

Settings and the main runtime banner now offer **Switch to Published Runtime…** for supported 1.x source installations when a strictly newer release is available. In Settings the action is beside the Available version, above the fold. Confirmation names the target version, preserved checkout, replaced release venv, launcher changes, migrations and service restarts. Ordinary updates and Install Available Updates still preserve active source installations; conversion is explicit.

The confirmed request is bound to the release, installed version, selected installation, CLI override, and validated source plan. Before mutation those values are checked again. Unsafe/malformed source markers, managed installations, pinned source-venv environments, changed selections, equal/newer versions and destinations within the checkout cannot authorize a switch.

The app invokes the selected 1.x CLI with argv `upgrade --yes --version <release>` and the release destination venv, preserving the Mac app with `DEFENSECLAW_APP_PATH=none`. The runtime's authenticated installer owns mutation, backup, migration, rollback and service handling. The app neither deletes the source marker nor edits runtime state directly.

After success the release CLI must report the target version or newer, and the public launcher must point to that release venv outside the checkout. Only then does the app update a source CLI override, invalidate its command cache and rebind readers. Progress stays active through that final refresh. An old source marker stops blocking upgrades only when both the selected CLI and public launcher point to the release venv. A release venv sitting beside an active source launcher is still protected.

## Verification

- All **42** regression scripts passed against the published 1.0.1 wheel and exact authenticated source `00ef714b8a47f3ba90dad69b91dc8aa40c735057` (schema 9, 251 registry entries, 24 setup sections). The five intentional source changes are recorded in the reviewed 1.1.29 compatibility baseline. Its source/package version skew warning remains: source project metadata says 1.0.0, published artifacts report 1.0.1.
- Filesystem regressions cover valid source plans, checkout/config destination refusal, inactive release preservation, completed launcher detection, explicit source selection, marker preservation, writable markers and symlink markers.
- **11 native scenarios passed:** normal upgrade success/failure/cancellation/unverified version/equal/newer/source preservation; explicit source switch success/failure/missing launcher swap/stale consent. These exercise production AppState with an isolated CLI fixture, including duplicate requests, command exclusion, source file preservation, and detection by a new AppState after completion. Settings screenshots were visually reviewed; the confirmation action is tested through its production handler rather than an automated mouse click.
- App-state signal, MainWindow lifecycle, protected artifact and runtime UI checks passed; the final Debug app built successfully; Python syntax and `git diff --check` passed.

Evidence: [native tests](source-runtime-switch/native-tests.log), [audit](source-runtime-switch/compatibility-audit.md), [visible switch](../images/source-runtime-switch/source-runtime-switch-ready.png), [completed switch](../images/source-runtime-switch/source-runtime-switch-complete.png).

Development build: `/private/tmp/DefenseClawMac-source-switch-build/Build/Products/Debug/DefenseClawMac.app`. Prepared for release 1.1.29 with bundled runtime 1.0.1. No live runtime migration, administrator service restart, checkout update, source-marker removal, or installed-app replacement was performed. Those host-specific integrations are not claimed by the fixture tests.
