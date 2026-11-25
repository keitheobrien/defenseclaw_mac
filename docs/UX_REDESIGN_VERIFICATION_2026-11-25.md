# UX redesign verification — branch `kobrien/ux/mac-native-design`

Date: 2026-11-25. Base: `origin/main` at `185f20a`. Host: macOS 27.2.1,
Xcode 27.2, Debug build with ad-hoc signing, against a live DefenseClaw
install (runtime 1.0.10). No push, no release.

Scope of the branch: layout, labels, shortcuts and accessibility only. Panel
features, notice rules, counts, CLI commands and runtime/TUI semantics are
unchanged; the one behavioral addition is a confirmation before stopping the
gateway.

## Automated tests

All 50 `script/test_*` scripts were run on the branch and on `origin/main`
(`185f20a`) on the same machine.

| Result | Count | Notes |
| --- | --- | --- |
| Pass on branch | 45 | Includes every UI contract test (main window lifecycle, toolbar help, Overview read-only guidance, runtime UI compatibility, inspector layout policy, first-run connector selection, setup definitions parity). |
| Fail on branch | 5 | The same 5 fail identically on `origin/main`; none is caused by this branch. |

The five scripts that fail on both:

- `test_dependency_lock_validator.sh` — 4 failures.
- `test_policy_catalog.sh` — expects "global default stays" in the Python
  policy bridge output for an unscoped approval preview.
- `test_runtime_compat_audit.sh` — `No module named 'tomllib'`; the shell
  used here resolves `python3` to a version older than 3.11.
- `test_runtime_fresh_install.py` — opt-in; needs `--payload`.
- `test_sandbox_models.sh` — the app's no-asks text differs from the TUI's.

Not run: the opt-in native GUI harnesses (`test_panel_native_smoke.py
--run-gui` and variants). They drive a fixture app through System Events,
which was not available to the session that ran this pass.

## Visual walkthrough (Debug build, live install, dark mode)

Seen on screen, nothing mutating pressed:

- Sidebar grouping and all 18 panels: Overview, Alerts, Logs, Audit,
  Policies, Sandboxes, Skills, MCP Servers, Plugins, Tools, Inventory,
  AI Discovery, Runtime Sensors, Registries, Setup, Model Routing, Agent
  Substrate, Activity.
- Overview: status header, Gateway menu, actionable notices, Show More /
  Show Fewer, four-across Enforcement tiles, collapsible sections.
  "Open Setup" on a notice navigates to Setup.
- Stop Gateway… from the Gateway menu shows the confirmation; Cancel leaves
  the gateway running.
- Alerts and Audit with the detail pane open: Details stays readable; the
  close button closes the pane.
- Policies: row selection opens the shared pane with settings, Actions and
  runtime detail.
- Setup: Essentials / Protection / Integrations / Policy and Runtime groups;
  searching "splunk" leaves the two Splunk wizards.
- Banners (token, app update, runtime update) via the Debug-only
  `dcPreviewBanners` switch: they sit in the layout and push the panel down
  on every panel checked, including panels with the detail pane.
- First-run assistant via the Debug-only `dcPreviewFirstRun` switch: Agents →
  Protection (Observe / Action, advanced options) → Review (summary, finish
  toggles, exact `defenseclaw init …` command), Back / Continue, and
  "Continue Without Setup". Initialize and Detect Installed Agents were not
  pressed.
- Light mode (`-NSRequiresAquaSystemAppearance YES`): Overview, Setup and
  Alerts with the detail pane.

Found and fixed during this pass:

- Panels with short content (Sandboxes off, Inventory scanning, Runtime
  Sensors, Policies loading) floated to the middle of the window; the detail
  column is now pinned to the top.
- White text on tinted glass banners was hard to read; banners now use
  neutral glass with adaptive text, a colored icon and a colored border.
- The first-run Advanced `DisclosureGroup` did not expand inside the grouped
  form; it is now a "Show advanced options" switch.
- Medium / Low headline counts in Alerts were too pale in light mode.

## Not verified

- The menu bar popover (inline Acknowledge All confirmation, More menu). The
  status item could not be reached from the test session; the code compiles
  and the confirmation is a local state toggle in front of the existing
  `acknowledge` call.
- Escape closing the detail pane (the key could not be delivered to the app
  in the background; the handler is unchanged from `main`).
- VoiceOver, Increase Contrast and Reduce Motion by ear/eye. Labels, heading
  traits, values and the Reduce Motion checks are in the code and visible in
  the accessibility tree ("Close details", "Dismiss app update", …), but no
  one has listened to them.
- macOS 14/15 fallbacks for the Liquid Glass surfaces (the test host runs
  macOS 27).
- Any mutating action: acknowledge, gateway start/stop/restart, policy
  actions, wizards' Apply, Initialize, upgrades.

## Side effects of the walkthrough on the live install

Opening Model Routing and Agent Substrate runs their read-only loaders
(`defenseclaw routing status --json`, `defenseclaw substrate list --json`);
both were cancelled by navigating away and are recorded as Cancelled in
Activity. The two preview defaults were deleted after use. The Debug build
replaced the running DefenseClawMac instance for the duration.
