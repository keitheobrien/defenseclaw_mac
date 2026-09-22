# Run the gateway as administrator

Administrator mode gives a compatible installed runtime the permissions needed to observe activity across the machine. It is off by default and requires a signed installation of DefenseClawMac. Unsigned development builds cannot use this mode.

Administrator mode does not add sensors to an older runtime. The published DefenseClaw 0.8.10 payload predates the new Runtime planes and root access to operator-owned configuration; those features require a compatible newer/source runtime. The Mac app preserves the runtime you installed.

1. In **Settings → Connection**, enable **Run gateway as administrator**. The same switch is available in **Overview → Quick Actions**.
2. Choose **Start Gateway as Administrator** or **Restart Gateway as Administrator** in Overview. Complete the macOS background-service approval if requested. Once the service is approved, each action requests native administrator authorization.
3. If macOS requests background-service approval, use **Background Service Settings…**, allow DefenseClaw, and retry Start or Restart. Connection settings show the service's current approval status.
4. For Runtime **agent actions**, open **Full Disk Access…** and add `/usr/bin/eslogger`. Use the add button and **⌘⇧G** to enter that path. Full Disk Access granted to iTerm does not transfer to the background gateway. Restart the gateway after granting access.
5. Check Runtime coverage again:

   ```bash
   defenseclaw agent discovery runtime selftest
   ```

After startup, use the Runtime self-test to confirm that every selected plane is running. Permission approval alone does not enable unselected Runtime planes or prove that findings and telemetry are being delivered.

Use **Overview → Diagnostics → Stop Gateway as Administrator** to stop the gateway. After a runtime update, use **Restart Gateway as Administrator** (also in Diagnostics) to activate the updated executable. Start refuses a changed installed gateway when a previous private copy exists, so it cannot silently switch a running service. Starting, stopping, and restarting continue to appear in Activity with their result and any required next step. Changing the administrator-mode switch does not itself start, stop, or restart a gateway, or remove its approved background service. Keep administrator mode enabled when stopping a gateway that ran as root. Turning it off does not migrate root-owned state back to user ownership; the app explains when that state requires administrator mode.

Administrator mode keeps the selected DefenseClaw home and configuration. It uses your existing `~/.local/bin/defenseclaw-gateway`; it never substitutes the older runtime bundled for fresh installation. The privileged service accepts only gateway start, stop, and restart operations. After macOS authorization, it validates the installed executable and prepares a private, root-owned copy isolated to your macOS account before changing the running service. Restart stops the previous private copy before activating the newly validated one; Stop can still use the previous copy if the installed executable is unavailable. It does not execute arbitrary commands or request passwords inside the app. Both the app-only and unified distributions include the signed helper. The gateway itself remains managed by the runtime installer/updater. Administrator authorization trusts the operator’s installed runtime and configuration, like running that gateway with sudo; signature integrity checks permit valid ad-hoc signatures used by source builds and do not certify their publisher. Missing gateways, scripts, symlinks, shared-writable paths, changed copies, and invalid signatures are refused.

The app compares the installed runtime with the latest published DefenseClaw release. An older runtime shows an upgrade prompt that uses the authenticated runtime updater. Equal or newer runtimes stay in place, including newer source builds carrying the same release number. Source-managed installations can show release availability but remain protected from replacement by the app. Unknown versions never trigger replacement.

Managed installations remain read-only in the app; their administrator controls the system service. Do not change ownership of your home directory or `.defenseclaw` to enable Runtime monitoring.

## Local development verification

The signed development build is available at `build/gateway-administrator/DefenseClawMac.app`. The tested runtime is the locally repaired gateway (0.8.10, commit `85029e57+runtime-repair`). This is a local test build, not a notarized release. The installed `/Applications/DefenseClawMac.app` and `~/.local/bin/defenseclaw-gateway` are preserved.

The new app was launched and the Overview controls and Connection permission links were checked. Before/after screenshots are in `images/gateway-administrator-before.png` and `images/gateway-administrator-after.png`. Administrator mode is enabled and the background helper is registered and approved. The first live requests exposed an authorization handoff bug: the app preauthorized a zero-timeout right, then the helper checked it without requesting an actual grant. macOS returned success for that preflight without granting the right, so the helper immediately rejected the action. Existing root gateway processes were left running.

Checks passed:

- `script/test_gateway_administrator.sh`: exact action routing, installation identity, read-only restrictions, invalid arguments/environment, cancellation and selection changes.
- `script/test_gateway_admin_helper.sh`: 110 checks covering authorization rules, no execution after denial or cancellation, per-account isolation, source-copy race detection, lifecycle ordering, unchanged installed executables, scanner lookup, signatures and idle shutdown.
- `script/test_gateway_admin_packaging.sh` and `script/test_supply_chain_safety.sh`.
- Existing CLI cancellation, installation-context, output-safety and catalog-action suites.
- Signed arm64 app build, arm64/Intel helper compilation, strict app/helper signatures and packaging checks, and operator gateway signature-integrity checks.

The corrected helper requests actual native authorization immediately before gateway work, while retaining the zero-timeout rule and all signature/path checks. Cancelling the macOS prompt is recorded as Cancelled in Activity. A noninteractive macOS probe reproduced the original failure: preauthorization returned success with the `CannotPreAuthorize` flag, the original helper check returned `errAuthorizationDenied`, and requesting actual authorization without UI returned `errAuthorizationInteractionNotAllowed`. Regression tests cover the grant and cancellation boundaries. The corrected signed app was rebuilt, verified, and reopened at the already-approved development path. Background-service approval and a successful native-authorized restart were verified by the user on September 22. The subsequent release review changed runtime selection from an app-bundled gateway to the existing installed gateway to preserve newer/source runtime features. The final native-authorized restart succeeded at 10:23 AM on September 22: the gateway and watchdog ran from the account-specific private copy, all three selected planes started, and the installed gateway SHA-256 remained unchanged. Full Disk Access is independent of administrator approval; the Runtime self-test is the authority for sensor coverage.

Apple documents the distinction between preauthorization and actual authorization in [Authorization Services](https://developer.apple.com/library/archive/documentation/Security/Conceptual/authorization_concepts/03authtasks/authtasks.html).

The helper uses [Apple's SMAppService API](https://developer.apple.com/documentation/servicemanagement/smappservice). [LaunchDaemon registration requires administrator approval](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29). App updates must preserve the signed helper. Ad-hoc app builds deliberately cannot authorize it. Runtime updates stay separate and administrator Start/Restart validate a fresh copy of the installed gateway before use.
