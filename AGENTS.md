# Repository Guidelines

## Project Structure & Module Organization

`DefenseClawMac/` contains the SwiftUI application. `App/` owns lifecycle and shared `AppState`; `DataLayer/` contains gateway, SQLite, file-tail, parser, installer, and CLI integrations; `Features/` contains one view area per sidebar panel; `DesignSystem/` provides shared Cisco styling and components; and `Assets.xcassets/` stores icons. Pure-logic tests live in `Tests/`. Use `script/` for development helpers and `scripts/` for release packaging. Documentation and screenshots belong in `docs/` and `images/`. Generated `build/` and `DerivedData/` content is ignored.

## Build, Test, and Development Commands

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
./script/test_connector_onboarding.sh
xcodebuild -project DefenseClawMac.xcodeproj -scheme DefenseClawMac \
  -configuration Debug -destination 'generic/platform=macOS' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
```

The first command builds and launches a Debug app; `--verify` also confirms it remains running. The test script compiles and runs the standalone onboarding tests. Use the explicit `xcodebuild` form for compile-only validation on machines without a distribution certificate. Maintainers produce the signed app-only ZIP and unified runtime DMG with `scripts/build_unified_dmg.sh`.

## Coding Style & Naming Conventions

Use four-space Swift indentation. Name types and SwiftUI views in `UpperCamelCase`; use `lowerCamelCase` for methods, properties, and enum cases. Keep UI state on `@MainActor`, isolate I/O in actors where practical, and prefer small helpers over duplicated view logic. There is no repository formatter or linter, so match surrounding Swift and keep Xcode warnings clean. Pass subprocess arguments as arrays through `CLIRunner`; never construct shell command strings.

## Testing Guidelines

There is no XCTest target. Add pure-logic tests as `Tests/<Feature>Tests.swift` with a matching `script/test_<feature>.sh`, following `ConnectorOnboardingTests`. Run focused tests, an app compile, and `git diff --check` before opening a PR. For visible SwiftUI changes, launch locally and include before/after screenshots.

## Commit & Pull Request Guidelines

Use concise, imperative subjects such as `Overview: reconcile connector roster`; release commits use `Release DefenseClawMac x.y.z`. Keep commits scoped. PRs should explain behavior and TUI parity, identify the tested DefenseClaw runtime version, list verification commands, link relevant issues, and include screenshots for UI changes.

## Security & Configuration Tips

Treat `~/.defenseclaw` as live user state. Reads may use the data-layer stores, but mutations must go through the `defenseclaw` CLI and activity recording. Never place secrets in source, argv, logs, fixtures, or screenshots; sensitive values must travel through hidden stdin. Do not publish unnotarized release artifacts.
