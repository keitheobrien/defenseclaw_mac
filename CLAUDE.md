# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Native macOS menu-bar companion app (SwiftUI + Swift Charts, macOS 14+, Xcode 16+, arm64) for the DefenseClaw runtime ([cisco-ai-defense/defenseclaw](https://github.com/cisco-ai-defense/defenseclaw)). It replicates the `defenseclaw tui` terminal dashboard. Single Xcode target and scheme (`DefenseClawMac`), no external package dependencies — SQLite comes from the SDK's `SQLite3` module, YAML from a minimal built-in parser.

## Commands

Development build + launch (Debug by default; kills any running instance first):

```bash
./script/build_and_run.sh            # build and open
./script/build_and_run.sh --debug    # run under lldb
./script/build_and_run.sh --logs     # launch + stream process logs
./script/build_and_run.sh --verify   # launch + assert process is alive
CONFIGURATION=Release ./script/build_and_run.sh
```

Plain build (the project's Release config demands the Developer ID cert; use
ad-hoc overrides for compile checks on any machine):

```bash
xcodebuild -project DefenseClawMac.xcodeproj -scheme DefenseClawMac \
  -configuration Debug -destination 'generic/platform=macOS' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
```

Tests — there is **no XCTest target**. Unit tests are standalone `swiftc` executables:

```bash
./script/test_connector_onboarding.sh
```

That script compiles `DefenseClawMac/DataLayer/ConnectorOnboarding.swift` + `Tests/ConnectorOnboardingTests.swift` into one binary and runs it. Tests are a `@main` struct calling test functions with a custom `expect()` assertion. Follow this pattern (new script + test file) to test other pure-logic DataLayer modules.

Release artifacts (requires the Developer ID Application cert, `gh`, `cosign`,
and a notarytool keychain profile — default name `notarytool`, override with
`NOTARY_PROFILE=`; makes three notarization submissions per run):

```bash
scripts/build_unified_dmg.sh                 # app-only zip + unified DMG (bundled runtime)
SKIP_NOTARIZE=1 scripts/build_unified_dmg.sh # iteration builds (separate out-unnotarized dir)
RUNTIME_TAG=0.8.3 scripts/build_unified_dmg.sh   # pin bundled runtime release
```

Artifacts land in `build/unified/out/`. Release process: bump
`MARKETING_VERSION` (two occurrences in the pbxproj), commit as
`Release DefenseClawMac x.y.z`, run the pipeline, then publish tag `vX.Y.Z`
with **both** assets. The zip is the self-update asset — `UpdateChecker`
downloads the **first `.zip` asset** of the latest release, so never add
another zip ahead of it and never publish `SKIP_NOTARIZE` output.

Note: `script/` (dev helpers) and `scripts/` (release build) are different directories.

## Architecture

**Core invariant:** everything the app *reads* is unauthenticated or read-only; **all state changes go through the `defenseclaw` CLI**, and every invocation is recorded in the Activity panel with its exact argv, live output, and exit status. Secrets are passed to the CLI over hidden stdin (`keys set`), never on the command line.

Backend surfaces the app consumes: Go gateway REST API (`http://127.0.0.1:<gateway.api_port>`, default 18970), `~/.defenseclaw/audit.db` (read-only SQLite), `~/.defenseclaw/gateway.jsonl` (tail), plain-text logs, doctor cache, and `config.yaml` + `.env`.

- `App/AppState.swift` (~1700 lines) — root `@Observable @MainActor` object owning all data-layer singletons, plus the tiered refresh engine: a 5-second "pulse" feeds the menu-bar icon, Overview health, and new-alert notifications; panel-level refreshes (selection / ⌘R) layer on top. Cross-panel state (shared connector filter, panel routing, update/install state) lives here.
- `App/DefenseClawApp.swift` — menu-bar-first lifecycle: `MenuBarExtra` is the persistent anchor; closing the main window never terminates the process (only Quit/⌘Q); Dock-icon visibility is a runtime setting via `NSApp.setActivationPolicy`.
- `DataLayer/` — one module per backend surface:
  - `GatewayClient` (actor) — localhost REST, mirrors the Python TUI's `OrchestratorClient`; Bearer token attached from config.
  - `ConfigStore` — reads `config.yaml`/`.env` (never writes — config writes go through the runtime's own writer: the venv python `apply_config_field` + `cfg.save()` script in `SetupView`, or the CLI; the gateway's config-patch endpoint is dead legacy RPC, don't use it). Token resolution replicates the Python CLI ladder: `gateway.token_env` → `DEFENSECLAW_GATEWAY_TOKEN` → `OPENCLAW_GATEWAY_TOKEN` → literal `gateway.token`; files are watched so rotated tokens apply without relaunch.
  - `CLIRunner` — the **only** process-execution path: `Process` with `executableURL` + argv arrays, never a shell string; locates `defenseclaw` via PATH candidates with a Settings override; output streams into `CommandActivityStore`.
  - `EventStreamReader` — tails `gateway.jsonl` and the plain-text logs.
  - `RuntimeInstaller` — lays the DMG's bundled runtime payload into `~/.defenseclaw` / `~/.local/bin` natively; no remote script is ever executed. The payload's `overrides.txt` (upstream pyproject's `[tool.uv] override-dependencies`, extracted at DMG build time) is mandatory for the wheel install: without `--overrides`, dependency resolution honors the scanner's `textual<8` cap and the runtime TUI crashes. The venv is built in a staging path and swapped only after the wheel install succeeds, so a failed repair never destroys a working runtime.
  - `ConnectorOnboarding` — pure first-run registration planning (the unit-tested module).
- `Features/` — one view file per sidebar panel (13 panels in Monitor / Govern / Discover / Configure groups). `SetupDefinitions.swift` declaratively defines the 22 setup wizards — each ends in a review step showing the exact `defenseclaw …` command before it runs. `ConfigEditorDefinitions.swift` backs the typed config editor whose section catalog is generated from the installed runtime (`build_setup_sections`) with a built-in offline fallback.
- `DesignSystem/` — `CiscoTheme` + shared components.

## Conventions and invariants

- **TUI parity is the spec.** Features are ported feature-for-feature from `defenseclaw tui` and share its semantics (latest-500/oldest-200 windowing, severity buckets, session-scoped scans, silent-bypass counting). Code comments cite spec sections (`spec §…`) and explain the runtime behavior being matched — keep that style, and match runtime/TUI semantics rather than inventing new behavior. Compare against the runtime source (`cli/defenseclaw/tui/` in cisco-ai-defense/defenseclaw) at the version the target machine actually runs.
- **Every mutation is recorded.** Anything that changes disk or runtime state runs through `AppState.runCommand` / `CommandActivityStore` — including plain file operations, which shell through `/bin/ln`, `/bin/cp`, etc. rather than `FileManager` — so the Activity panel shows real argv and exit status. Decision logic (what to touch, what to skip) stays in Swift as a planning pass; only the approved mutations execute.
- **Multiple autonomous agents commit here.** Always `git fetch` and rescan before editing — files may have changed since the last read, and origin/main may be ahead. Do not push or publish releases unless explicitly asked.
- The development machine typically runs a **live DefenseClaw install**: treat `~/.defenseclaw` and `~/.local/bin` as read-only while building or verifying (read-only CLI commands and GETs only; never restart the gateway or rebuild the venv as a "test").
- **Untrusted input → static allowlist before argv.** Connector names arriving from gateway JSON or `agent discover` output must pass static allowlists (`TUIWizards.hookConnectors`; `ConnectorOnboarding` filters against the caller's `supportedOrder`) before appearing in CLI arguments. New CLI-invoking flows should be gated behind explicit user clicks, not fired automatically from fetched data.
- GitHub Releases checks (app self-update + runtime update) are throttled and persisted across launches because the unauthenticated API allows 60 requests/hour — don't add unthrottled checks.
- `GET /skills` and `GET /tools/catalog` return HTTP 502 when no OpenClaw agent is running behind the gateway; catalog panels use `defenseclaw <resource> list --json` instead.
