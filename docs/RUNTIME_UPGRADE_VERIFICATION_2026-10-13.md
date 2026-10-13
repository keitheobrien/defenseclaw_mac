# In-app runtime upgrades

The runtime update banner and Settings → General now offer **Upgrade Runtime** for supported 1.x releases. Previously these actions only generated a terminal command. The app now invokes the selected runtime directly with `upgrade --yes --version <displayed version>` through CLIRunner and Activity. It passes the selected `DEFENSECLAW_HOME`, `DEFENSECLAW_CONFIG`, and `DEFENSECLAW_VENV` in the child environment, plus `DEFENSECLAW_APP_PATH=none` to preserve the standalone Mac app. No shell evaluates the display command, and no user-specific path or target version is hardcoded.

The runtime remains responsible for authenticating release artifacts, migrations, rollback, service restarts, and health checks. Legacy releases retain the authenticated external resolver workflow. Release 1.0.1 was verified as a published, non-draft, non-prerelease GitHub release; the installed CLI's help confirms `upgrade --yes --version` support.

The app rechecks provenance and installed version immediately before execution. Source/development and administrator-managed installations cannot be upgraded this way; equal/newer installed versions remain unchanged. Invalid release identifiers and paths are rejected. Existing commands must finish before an upgrade can begin. A runner-level exclusive operation prevents other CLI commands from racing venv replacement, while audit readers, polling, installation rebinding, and background version probes pause. Duplicate clicks cannot start another upgrade. The owning upgrade can verify the replaced CLI without releasing exclusivity first.

Progress streams through Activity and Settings. Failure and cancellation retain output and restore command/audit access. Exit zero alone is insufficient: the app also verifies the installed version is the requested release or newer. Configuration/panels refresh after verified success. “Install Available Updates” does not restart the Mac app after a failed runtime upgrade.

## Verification

- `script/test_runtime_protected_artifact.sh`: passed. Exact executable/argv/environment for 1.0.1, paths containing quotes/spaces, app preservation, and invalid path/version rejection.
- `script/test_cli_cancellation.sh`: passed. Added exclusivity tests covering another operation, unrelated commands, ownership of lock release, reserved commands, and resuming access.
- `script/test_runtime_ui_compatibility.sh`: passed.
- Compatibility audit against released runtime 1.0.0 source `57698deb67c902e563ed10114a20dbab010f8922`: all 42 regression scripts passed. The audit continues to flag the deliberately changed source hashes as unreviewed; the baseline was not rewritten to hide changes. The inspector native layout test is a separate opt-in check.
- `python3 script/test_panel_native_smoke.py --run-upgrade-gui`: passed in a disposable home with a fake updater. Exercised the production AppState upgrade action for success, failure, cancellation, successful exit without version advancement, equal version, newer version, and source ownership. Assertions cover exact argv/environment, duplicate clicks, blocked concurrent changes, audit suspension/recovery, background-version-check suppression, Activity output, lock release, and verified success. Settings screens were rendered and visually checked; the test invokes the AppState action directly rather than clicking a button that performs a live GitHub lookup.
- Debug app build and `git diff --check`: passed.

Screenshots: [update available](../images/runtime-upgrade/runtime-upgrade-ready.png), [live progress](../images/runtime-upgrade/runtime-upgrade-progress.png), [verified version](../images/runtime-upgrade/runtime-upgrade-complete.png).

Development app: `/private/tmp/DefenseClawMac-runtime-upgrade-build/Build/Products/Debug/DefenseClawMac.app`. This includes the earlier complete Sandbox setup changes. At this development verification stage, no new release had been published and no upgrade of the user's installed runtime was performed. Release validation is recorded separately in RELEASE_VERIFICATION_1.1.28_2026-10-13.md. A real download, migration, rollback, or privileged service restart is not claimed by these fixture tests.
