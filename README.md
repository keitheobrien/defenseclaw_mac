# DefenseClaw for macOS

Native menu-bar companion app for [cisco-ai-defense/defenseclaw](https://github.com/cisco-ai-defense/defenseclaw), replicating the `defenseclaw tui` terminal dashboard with SwiftUI and Swift Charts.

![Overview dashboard](images/overview.png)

The app lives in the menu bar: the shield icon shows live gateway/alert state, and the popover gives an at-a-glance summary with recent findings — even while the main window is closed or minimized.

<p align="center">
  <img src="images/menubar-popover.png" width="420" alt="Menu bar popover">
</p>

The General settings view shows app visibility controls plus independent update status and actions for the Mac app and the DefenseClaw runtime.

<p align="center">
  <img src="images/settings-general.png" width="420" alt="General settings with Mac app and DefenseClaw runtime update controls">
</p>

## Install

Every release on [Releases](https://github.com/keitheobrien/defenseclaw_mac/releases) ships two artifacts (arm64, macOS 14+), each signed with Developer ID, hardened-runtime, and notarized by Apple with a stapled ticket:

- **`DefenseClawMac-<version>.dmg` — unified installer (recommended).** The app with the matching DefenseClaw runtime release bundled inside, verified against the upstream artifacts (SHA-256 + Sigstore) at build time. Mount, drag `DefenseClawMac.app` to Applications, open it, and click **Install DefenseClaw Runtime** on first run — the app lays the bundled runtime into `~/.defenseclaw` and `~/.local/bin` natively, with every step recorded in the Activity panel. No remote script is ever executed; network is used to fetch the CLI's Python dependencies from PyPI, plus uv and Python 3.12 only if this Mac doesn't have them. Settings ▸ General also offers **Install / Repair Runtime** (configuration, tokens, and the audit database are never touched, and a source-checkout dev install is never overwritten).
- **`DefenseClawMac-<version>.zip` — app only.** The traditional build for Macs that already have (or separately manage) the DefenseClaw runtime. Unzip, move `DefenseClawMac.app` to `/Applications`, open normally.

Gateway Start, Stop, and Restart can use macOS administrator authorization when **Run gateway as administrator** is enabled in Overview or Settings → Connection. The signed background helper is registered on first use; macOS controls administrator approval. See [administrator gateway setup](docs/GATEWAY_ADMINISTRATOR.md) for background-service approval and Runtime Full Disk Access requirements.

The app self-updates: Settings ▸ General checks GitHub Releases for a newer Mac-app build (the small app-only zip) and can download, swap, and relaunch in place, and it separately tracks the installed DefenseClaw runtime (`defenseclaw upgrade`). The two update tracks stay independent — the DMG's bundled payload is used only for first install or repair. Both check paths are throttled to respect GitHub's unauthenticated rate limit.

## Build & run

Build from source — no prebuilt binary ships in the git tree itself (`build/` is gitignored):

- Open `DefenseClawMac.xcodeproj` in Xcode (16+) and Run, **or** from the command line:
  ```
  xcodebuild -project DefenseClawMac.xcodeproj -scheme DefenseClawMac -configuration Release build
  ```
  then copy the app out of derived data:
  ```
  open "$(xcodebuild -project DefenseClawMac.xcodeproj -scheme DefenseClawMac -configuration Release -showBuildSettings | awk '/BUILT_PRODUCTS_DIR/{print $3; exit}')/DefenseClawMac.app"
  ```
- Requires macOS 14+ and Xcode 16+. No external dependencies (SQLite via the SDK's `SQLite3` module; YAML via a built-in minimal parser). Local source builds are for development; distribution releases are built separately with Developer ID signing and Apple notarization.

## What it connects to

A local DefenseClaw installation (companion app — it does not manage the backend):

| Source | Path / address |
|---|---|
| Go gateway REST API | `http://127.0.0.1:<gateway.api_port>` (default 18970) |
| Audit DB (read-only) | `~/.defenseclaw/audit.db` |
| Event stream (tail) | `~/.defenseclaw/gateway.jsonl` |
| Plain-text logs (tail) | `~/.defenseclaw/gateway.log`, `~/.defenseclaw/watchdog.log` |
| Doctor cache | `~/.defenseclaw/doctor_cache.json` |
| Config | `~/.defenseclaw/config.yaml` + `~/.defenseclaw/.env` |
| CLI (writes / actions) | `defenseclaw`, `defenseclaw-gateway` (path override in Settings ▸ Connection) |

**Token resolution** matches the Python CLI's ladder (`config.py::resolved_token`): env var named by `gateway.token_env` → `DEFENSECLAW_GATEWAY_TOKEN` → `OPENCLAW_GATEWAY_TOKEN` → literal `gateway.token`, with `~/.defenseclaw/.env` consulted because GUI apps inherit no shell environment. `config.yaml` / `.env` are watched for changes so a rotated token is re-resolved live without a relaunch.

Everything the app reads is unauthenticated (`/health`) or read-only; all state changes go through the `defenseclaw` CLI, and each invocation is recorded in the Activity panel with its exact argv, live output, and exit status. Secrets are delivered to the CLI over hidden stdin (`keys set`), never on the command line.

## Panels

Sidebar groups mirror the TUI's 13 panels:

- **Monitor** — Overview, Alerts, Logs, Audit, Activity
- **Govern** — Skills, MCPs, Plugins, Tools
- **Discover** — Inventory, AI Discovery, Registries
- **Configure** — Setup

⌘1–⌘9, ⌘0, and ⌘⇧1–⌘⇧3 jump between panels; ⌘R refreshes; ⌘F searches. A command palette (⌘⇧P) exposes the full DefenseClaw command registry, and ⌃M cycles the shared connector filter across every view.

### Overview

The dashboard is a faithful port of the TUI's boxes:

- **What Needs Attention** — the runtime's notice rules (gateway offline, guardrail unconfigured, missing API keys, connector drift, silent LLM bypass, doctor findings, and more).
- **Services** — all nine subsystems (Gateway, Agent, Watchdog, Guardrail, API, Sinks, Telemetry, AI Discovery, Sandbox) with state and per-service detail.
- **Scanners**, **Enforcement** tiles (Hook Calls / Blocks / Findings / Guardrail), **Configuration**, **Connectors**, **Observability Destinations · Runtime** (loaded OTel exporters and audit sinks with delivery stats), **Doctor** (hydrated from the on-disk cache with staleness and live-health reconciliation), and **Discovered AI Agents**.

Select a connector (the roster chip, a Connectors-table row, or ⌃M) and the Configuration, Enforcement, and Scanners boxes rescope to that connector — including per-connector AIBOM coverage.

### Setup

**22 native setup wizards** covering the runtime's setup surface — connector (single / batch / remove), credentials, LLM, guardrail, guardrail actions, skill & MCP scanners, gateway, Cisco AI Defense, Splunk, Splunk dashboards, Galileo, local observability, observability destinations, webhooks, notification routing, custom providers, registries, trusted paths, token rotation, AI discovery, and sandbox. Each wizard is a native form that ends in a review step showing the exact `defenseclaw …` command before it runs, prefills from your live config where relevant so an untouched apply never resets current settings, and validates required fields before Run.

**Config editor** — a typed, sectioned editor whose catalog comes from the installed runtime. A built-in catalog is the offline fallback. Uncatalogued keys remain read-only until the runtime exposes a supported writer. Edits are diff-reviewed with secrets masked, saved through the runtime CLI, and queue a gateway restart.

The menu bar shield reflects live state (healthy / alert count / degraded / offline / scanning / paused) on a 5-second pulse, with native notifications for new CRITICAL/HIGH findings. Settings ▸ General controls Dock-icon visibility and hide-on-close (pure menu-bar-agent mode).

## Verified TUI parity

The app targets DefenseClaw's schema-8 contracts and probes the selected runtime's capabilities. Matching version labels alone do not establish feature parity. Automated tests and source alignment do not certify untested external integrations; see the dated reports in `docs/` for actual coverage.

- **Enforcement counts** — Hook Calls and Blocks use audit history. Findings use the audit alert queue; legacy installations also group file-backed scan blocks. Canonical findings are not counted again as legacy scan blocks. Per-connector totals can fall back to all-time aggregates.
- **Alerts** — an audit-backed queue with legacy scan/egress compatibility. Acknowledgement runs through the selected runtime's CLI; the runtime owns persistence. Stream-only entries can be hidden locally.
- **Logs** — Gateway and Watchdog read plain log files; Verdicts and Otel use bounded canonical audit-database projections on v8, with legacy fallback for older schemas. Unavailable history is explicitly marked stale. Sensitive fields remain redacted; there is no RAW/redaction-off switch.
- **Runtime** — coverage planes, findings, provider attribution and inventory correlation from the Runtime API. Missing coverage is not a clean-host result. Unsupported gateways show upgrade guidance; CLI commands are exposed only when the selected runtime reports support.
- **Session-scoped** scans and alerts, silent-bypass counting, doctor cache staleness, connector-filter propagation, and the shared latest-500 / oldest-200 windowing all mirror the runtime.

## Known notes

- `GET /skills` and `GET /tools/catalog` return **HTTP 502** when no OpenClaw agent is running behind the gateway (hook-based connectors like claudecode/codex/cursor don't serve these catalogs); catalog panels read `defenseclaw <resource> list --json` instead. AI Discovery and other authenticated endpoints (`/api/v1/ai-usage`) require a valid gateway token — a stale token surfaces only there since `/health` is unauthenticated, and the app re-resolves it automatically when `config.yaml` / `.env` change.
- If you run a window manager with ⌘-number shortcuts (e.g. Magnet), those keys may never reach the app; use the sidebar or the Go menu instead.
- The Sandbox setup wizard is Linux-only (surfaced in the wizard); it cannot complete on macOS.
