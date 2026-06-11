# DefenseClaw for macOS — Application Specification

| | |
|---|---|
| **Document status** | Draft v1.0 — for review before implementation |
| **Date** | 2026-06-10 |
| **Target** | Native macOS desktop companion app for [cisco-ai-defense/defenseclaw](https://github.com/cisco-ai-defense/defenseclaw) |
| **Upstream version studied** | `main` as of 2026-06-10 (TUI: Python Textual, `cli/defenseclaw/tui/`) |

---

## 1. Product Overview

### 1.1 What it is

**DefenseClaw for macOS** is a native menu-bar-resident desktop application that replicates the full functionality of the DefenseClaw terminal UI (`defenseclaw tui`). It is a *companion frontend*: it assumes DefenseClaw (Python CLI + Go gateway sidecar) is already installed and connects to the same three local data sources the TUI uses. It adds what a terminal cannot: an always-on menu bar status item, live auto-refresh, native notifications, Swift Charts visualizations, and a macOS-native settings experience — all in a Cisco-branded design system.

### 1.2 Goals

1. **Full functional parity with the TUI** — every panel, every filter, every read view, and every mutating action (toggle skills/MCPs/plugins, block/allow tools, acknowledge alerts, trigger scans, apply setup wizards) available in the TUI is available in the app.
2. **Menu bar residency** — the app lives in the menu bar; the icon reflects gateway/alert state at a glance; closing or minimizing the main window can hide the app entirely from the Dock (user-configurable).
3. **Live monitoring** — unlike the TUI's manual `r`-to-refresh model, the app polls continuously (tiered cadence) so the Overview, menu bar icon, and alerts are near-real-time.
4. **Modern macOS frameworks** — SwiftUI throughout, Swift Charts for all graphing, `MenuBarExtra` for the status item, `UserNotifications` for alerting. No web views, no Electron.
5. **Cisco visual identity** — color system derived from the Cisco brand / Cisco UI Kit palette, adapted for macOS light and dark appearances.

### 1.3 Non-Goals (v1)

- Does **not** install, bundle, launch, or manage the DefenseClaw backend. If the gateway is down, the app shows a degraded/offline state with guidance (it may *offer* to copy the relevant CLI command, but does not execute lifecycle commands itself — exception: §9.13 Setup applies config via the `defenseclaw` CLI exactly as the TUI does).
- Not sandboxed for App Store distribution (it must read `~/.defenseclaw/` and talk to localhost). Personal/local build; no signing or notarization pipeline in v1.
- No remote gateways. Localhost (`127.0.0.1`) only, matching the gateway's security model.
- No iOS/iPadOS/Catalyst.

### 1.4 Users

DefenseClaw operators on macOS: security engineers and developers governing OpenClaw / agentic-AI runtimes who currently keep a terminal open running `defenseclaw tui`.

---

## 2. Source System Summary (what we are replicating)

The TUI is a Python **Textual** app (`cli/defenseclaw/tui/`) with **14 panels** (13 navigable + first-run onboarding) plus modal screens, a command palette, and a help overlay. It is a pure frontend over three local data sources:

| Source | Location | Used for |
|---|---|---|
| **Go gateway REST API** | `http://127.0.0.1:18970` (port configurable via `gateway.api_port` in config) | Health, status, skills/MCPs/plugins/tools catalogs, enforcement (block/allow), AI-usage discovery, guardrail config, config patching, scans |
| **SQLite audit DB** | `~/.defenseclaw/audit.db` | `audit_events`, `scan_results`, `findings`, `actions`, `activity_events`, `network_egress_events`, `target_snapshots` |
| **JSONL event stream** | `~/.defenseclaw/gateway.jsonl` | Logs (gateway/verdicts/otel/watchdog streams), scan findings, activity mutations, egress decisions |
| **Config file** | `~/.defenseclaw/config.yaml` | Gateway port/token, connector mode, LLM/guardrail/notification/privacy/observability settings, registry sources |

**Auth:** all state-changing endpoints require `Authorization: Bearer <token>` (token stored at `gateway.token` in `config.yaml`) plus `X-DefenseClaw-Client` header. Read-only `/health` is exempt. Gateway is localhost-only.

**TUI panel inventory** (the parity checklist): Overview, Alerts, Skills, MCPs, Plugins, Inventory, Logs, Audit, Activity, Tools, AI Discovery, Registries, Setup, First-Run.

---

## 3. Architecture

### 3.1 High-level

```
┌─────────────────────────── DefenseClaw.app ───────────────────────────┐
│                                                                        │
│  UI Layer (SwiftUI)                                                    │
│   ├─ MenuBarExtra (status item + popover)                              │
│   ├─ Main Window (NavigationSplitView: sidebar → panel views)          │
│   ├─ Sheets/Inspectors (detail, diff, wizards, confirmations)          │
│   └─ Settings Scene (app behavior, not DefenseClaw config)             │
│                                                                        │
│  ViewModel Layer (@Observable, one store per panel + AppState)         │
│                                                                        │
│  Data Layer (Swift actors)                                             │
│   ├─ GatewayClient        — async REST client, bearer auth, retries    │
│   ├─ AuditStore           — read-only SQLite (GRDB.swift)              │
│   ├─ EventStreamReader    — incremental JSONL tailer (DispatchSource)  │
│   ├─ ConfigStore          — config.yaml reader/watcher (Yams)          │
│   ├─ CLIRunner            — runs `defenseclaw setup …` (Setup apply)   │
│   └─ RefreshEngine        — tiered polling scheduler + staleness       │
└────────────────────────────────────────────────────────────────────────┘
            │ HTTP :18970          │ read-only           │ read (tail)
            ▼                      ▼                      ▼
     Go gateway sidecar      ~/.defenseclaw/audit.db   ~/.defenseclaw/gateway.jsonl
```

### 3.2 Data layer contracts

**GatewayClient** (actor)
- Base URL from `ConfigStore` (`http://127.0.0.1:<gateway.api_port|18970>`).
- Headers on every request: `X-DefenseClaw-Client: macos-app`; `Authorization: Bearer <token>` on all POST/PATCH and token-guarded GETs.
- Timeouts mirroring the TUI: 5 s default, 90 s for plugin enable/disable, 120 s for skill/MCP/AI-usage scans.
- Typed endpoint inventory in **Appendix A**.
- Error taxonomy surfaced to UI: `.offline` (connection refused), `.unauthorized` (401/403 → token problem), `.degraded` (5xx), `.timeout`.

**AuditStore** (actor, GRDB.swift)
- Opens `~/.defenseclaw/audit.db` **read-only** (`SQLITE_OPEN_READONLY`) — the gateway owns writes; the app never writes to the DB.
- WAL-safe reads; tolerate `SQLITE_BUSY` with bounded retry.
- Schema-tolerant decoding: columns read by name, missing tables (older schema versions) degrade the dependent feature with an inline notice rather than crashing. Schema reference in **Appendix B**.

**EventStreamReader** (actor)
- Tails `gateway.jsonl` incrementally: remembers byte offset, reads appended data on file-change events (`DispatchSource.makeFileSystemObjectSource`) plus a polling fallback.
- Handles truncation/rotation (offset > file size → reset to reading last 512 KiB, matching the TUI/Go reader budget).
- Parses the four row types (`event`, `scan_finding`, `activity`, `egress`) and fans out to per-stream ring buffers: gateway / verdicts / otel / watchdog (classification rules ported from `load_gateway_log_views()`).
- Ring buffer cap: 20,000 rows per stream in memory; older rows dropped (Logs panel offers "load older from disk" which re-reads a larger window on demand).

**ConfigStore** (actor)
- Parses `~/.defenseclaw/config.yaml` with Yams; watches for external edits and republishes.
- Exposes: gateway host/port/token, connector list & modes, registry sources, privacy flags, notification settings.
- The app **reads** the token from config.yaml (matching the TUI). Optionally caches it in the macOS Keychain so the file can be locked down later — but config.yaml remains the source of truth in v1.
- Writes go through the gateway (`PATCH /config/patch`) or `CLIRunner`, never by editing the YAML directly — same discipline as the TUI.

**CLIRunner** (actor)
- Thin `Process` wrapper that locates the `defenseclaw` binary (config-overridable path; default search: `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `$PATH`).
- Used **only** by Setup wizard "Apply" (e.g., `defenseclaw setup connector --connector=… --mode=… --yes`) and the optional Doctor deep-dive (`defenseclaw doctor`), mirroring exactly what the TUI shells out to.
- Streams stdout/stderr into the wizard's progress sheet; exit code drives success/failure UI.

**RefreshEngine**
- Tiered cadence (all user-tunable in app Settings):

| Tier | Default cadence | Feeds |
|---|---|---|
| **Pulse** | 5 s | `GET /health`, JSONL tail delta → menu bar icon, Overview health card, new-alert detection |
| **Active panel** | 15 s | Whatever panel is frontmost (its REST/SQLite query re-runs) |
| **Background** | 60 s | Audit counts for Overview bars, AI-usage snapshot |
| **On-demand** | manual | Full inventory scans, AI-usage scan, registry sync, doctor |

- Polling pauses when: machine sleeps, app hidden *and* "background monitoring" disabled in Settings. Pulse continues while hidden if background monitoring is on (that's the point of a menu bar app).
- Staleness: any dataset older than **15 minutes** (TUI's `STALENESS_WINDOW`) gets a "stale" badge with relative timestamp.

### 3.3 Concurrency & state

- Swift Concurrency throughout (`actor` data layer, `@Observable` view models, `@MainActor` UI).
- One `AppState` root object: gateway reachability, active connector set, unacknowledged alert counts by severity, current panel, menu-bar icon state machine.
- Panel stores are lazy — instantiated on first navigation, retained for the session (matches TUI's lazy panel mount).

---

## 4. Technology Stack

| Concern | Choice | Notes |
|---|---|---|
| Language | Swift 5.10+ | |
| Min OS | **macOS 14 (Sonoma)** | Needed for `@Observable`, modern `MenuBarExtra`, Swift Charts maturity |
| UI | SwiftUI (AppKit bridges only where required: activation policy, pasteboard) | |
| Charts | **Swift Charts** | Bars, sparklines, confidence-trend lines, donut (sector marks) |
| Menu bar | `MenuBarExtra` (window style popover) | |
| SQLite | **GRDB.swift** (SPM) | Read-only access, value observation |
| YAML | **Yams** (SPM) | config.yaml |
| Notifications | `UserNotifications` | CRITICAL/HIGH alert delivery |
| Persistence (app prefs) | `UserDefaults` + `@AppStorage` | Window/panel state, polling cadence, hide-on-close |
| Build | Xcode project, Swift Package Manager deps only | No CocoaPods/Carthage |
| License compliance | Apache-2.0 headers on ported logic; NOTICE entry for DefenseClaw | |

Justification: the user requirement is "modern mac osx frameworks for graphing and display" — Swift Charts + SwiftUI is the canonical answer; GRDB and Yams are the de-facto standard SPM libraries for their domains.

---

## 5. App Shell & Window Model

### 5.1 Menu bar presence (`MenuBarExtra`)

The app is **menu-bar-first**. The status item is always present while the app runs.

**Icon states** (template images, with color badge where noted):

| State | Icon | Trigger |
|---|---|---|
| Healthy | shield (outline) | Gateway healthy, no unacked HIGH/CRITICAL |
| Active alerts | shield + red badge dot & count | ≥1 unacknowledged HIGH/CRITICAL alert |
| Degraded | shield + amber overlay | Gateway reachable but a subsystem reports warn/error |
| Offline | shield, slashed, dimmed | Gateway unreachable |
| Scanning | shield + animated progress arc | Long-running scan in flight |

**Popover content** (click; ~360 pt wide):
1. Header: gateway state pill + uptime + active connector count.
2. Per-connector one-liners: name · mode (observe/enforce) · calls/blocks last 24 h.
3. "Last 24h" micro bar trio: Allowed / Blocked / Scanned (mini Swift Charts).
4. Most recent 5 unacknowledged alerts (severity dot, target, relative time) — click → opens main window on Alerts with that row selected.
5. Footer buttons: **Open DefenseClaw** · **Acknowledge all** · **Pause monitoring** · **Quit**.

Right-click (or ⌥-click) → compact NSMenu: Open, Pause Monitoring, Settings…, Quit.

### 5.2 Main window

`NavigationSplitView`:
- **Sidebar** (left): sections mirroring the TUI panels, grouped:
  - *Monitor*: Overview, Alerts, Logs, Audit, Activity
  - *Govern*: Skills, MCPs, Plugins, Tools
  - *Discover*: Inventory, AI Discovery, Registries
  - *Configure*: Setup
  - Sidebar badges: Alerts shows unacked count; Overview shows ⚠ when degraded.
- **Detail** (right): the selected panel view. Panels with master-detail (Alerts, Audit, AI Discovery, Registries) use an inspector pane or `NavigationSplitView` third column.
- Toolbar (per panel): search field, filter menus, refresh button (with last-refreshed relative time), panel-specific actions.
- Window restores size/position/last panel between launches.

### 5.3 Dock & hide behavior (explicit requirement)

App Settings → General:

- **"Show Dock icon"** (default ON): toggles `NSApp.setActivationPolicy(.regular / .accessory)` live.
- **"Hide app when window closes"** (default ON): closing/minimizing the main window does not quit; the window is released and the app continues in the menu bar. With Dock icon OFF, the app becomes a pure menu-bar agent when the window closes.
- **"Launch at login"** via `SMAppService.mainApp` toggle.
- Reopen path: clicking the menu bar icon → "Open DefenseClaw", or Dock icon click (if visible) restores the window on the last panel.
- Quit is only via menu bar menu, app menu, or ⌘Q.

### 5.4 Global commands & shortcuts

Faithful translations of TUI bindings into macOS idiom:

| TUI | macOS app |
|---|---|
| `1–0`, `A,T,V,R` panel keys | ⌘1…⌘9 + sidebar; ⌘⇧P "Go to Panel…" palette |
| `:` / Ctrl+K command palette | ⌘K command palette (actions: refresh, scans, toggles, navigation) |
| `?` help overlay | Help menu + ⌘/ shortcut cheat sheet sheet |
| `/` search | ⌘F focuses panel search field |
| `r` refresh | ⌘R refresh active panel |
| `c` copy | ⌘C copies selected row detail |
| `e` export | File ▸ Export… (⌘E) |
| Shift+D doctor probe | Overview toolbar "Run Health Check" |
| Ctrl+\ theme picker | App Settings ▸ Appearance |

---

## 6. Design System (Cisco)

### 6.1 Palette

Derived from the Cisco brand / Cisco UI Kit, replacing the TUI's slate/cyan palette. Defined as asset-catalog colors with light/dark variants.

**Brand & chrome**

| Token | Light | Dark | Use |
|---|---|---|---|
| `ciscoBlue` | `#049FD9` | `#04AEED` | Primary accent, selection, links, active borders, default chart series |
| `ciscoMidnight` | `#0D274D` | `#0D274D` | Sidebar tint (light), headers, brand surfaces |
| `ciscoSky` | `#64BBE3` | `#64BBE3` | Secondary/info accents |
| `surfaceBase` | `systemBackground` | `#0B121E` (midnight-derived) | Window background |
| `surfacePanel` | `#F5F7FA` | `#111B2C` | Cards |
| `surfaceRaised` | `#FFFFFF` | `#16233A` | Elevated cards, popover |
| `textPrimary/secondary/muted` | system label hierarchy | system label hierarchy | |

**Severity** (replaces TUI `SEVERITY_STYLES`)

| Severity | Color | Hex |
|---|---|---|
| CRITICAL | Cisco Red | `#E2231A` |
| HIGH | Cisco Orange | `#FBAB18` |
| MEDIUM | Cisco Yellow | `#EED202` (dark text on chip) |
| LOW | Cisco Sky | `#64BBE3` |
| INFO | Neutral gray | `secondaryLabel` |

**State** (replaces TUI `STATE_STYLES`)

| State | Color |
|---|---|
| active / running / enabled / clean / pass | Cisco Green `#6ABF4B` |
| blocked / error / rejected / stopped / fail | Cisco Red `#E2231A` |
| warn / reconnecting / starting / stale | Cisco Orange `#FBAB18` |
| quarantined | Magenta `#BF4B8B` |
| disabled / offline / unknown | Gray (`tertiaryLabel`) |

Accessibility: every chip/badge pairs color with a text label or SF Symbol — color is never the sole signal. All pairs checked for WCAG AA contrast in both appearances.

### 6.2 Typography & components

- System font (SF Pro); SF Mono for log lines, JSON, hashes, run IDs.
- Reusable components: `SeverityBadge`, `StatePill`, `StatCard` (big number + delta + sparkline), `MiniBars` (the ▰▱ enforcement bars reborn as Swift Charts `BarMark`), `FilterChipRow` (the TUI's cycling filter chips as toggleable chips), `KeyValueGrid`, `DiffView` (red/green before/after JSON), `EmptyState`, `StaleBadge`.
- Charts: Cisco Blue primary series; severity charts use the severity palette; gridlines/axes use muted tokens; no chartjunk.

---

## 7. Refresh, Notifications & Alerting

- Live model per §3.2 RefreshEngine.
- **Native notifications** (`UserNotifications`): posted when the JSONL tail / audit poll surfaces a *new* event meeting the user's threshold (default: CRITICAL+HIGH blocks and scan findings). Notification actions: **View** (opens Alerts at row), **Acknowledge**. Per-severity opt-in in Settings; respects Focus/DND automatically.
- Dedupe: notification key = event id; never re-notify on restart for already-seen ids (persisted high-water-mark timestamp + id set).
- "Pause monitoring" (menu bar) suspends polling and notifications, shows paused glyph.

---

## 8. Offline / Degraded / Error States

| Condition | App behavior |
|---|---|
| Gateway unreachable | Menu bar = offline icon. Overview shows offline hero card with: last-seen time, config'd port, copyable `defenseclaw gateway start` hint. SQLite/JSONL panels (Audit, Logs, Alerts history, Activity) **keep working** — they're file-based. Catalog/mutation panels disable their write controls with explanation. |
| 401/403 from gateway | Banner: "Gateway token rejected — config.yaml token may have been rotated." Offers reload-config action. |
| `audit.db` missing | Audit/Alerts-history sections show EmptyState with the expected path. |
| `gateway.jsonl` missing | Logs/Activity show EmptyState; pulse falls back to REST-only. |
| `defenseclaw` binary not found | Setup wizard "Apply" disabled with locate-binary affordance (file picker → stored path). |
| Schema version older than expected | Per-feature inline notice ("activity_events table not present — requires DefenseClaw ≥ 0.x"). |

Every panel must define its EmptyState, LoadingState, and ErrorState explicitly (no blank views).

---

## 9. Functional Specification — Panels

Conventions: every panel has toolbar search (⌘F, case-insensitive substring — parity with TUI `/`), ⌘R refresh, ⌘C copy-row, sortable columns where tabular, and a stale badge. "Write" rows list every mutation with its exact backend call.

### 9.1 Overview (dashboard)

Replicates `overview_state.py` content with native presentation. Scrollable card grid:

1. **System Health card** — gateway state pill, uptime, last error, watcher/API/guardrail/telemetry/AI-discovery/sink/sandbox subsystem states (from `GET /health`). Degraded subsystems listed with amber pills.
2. **Connector Health table** — Connector · Mode · Rule pack · Last activity · Calls · Blocks · Alerts. Status-colored rows. (Source: `/health` ConnectorHealth + audit counts.)
3. **Enforcement (last 24 h)** — horizontal `BarMark` trio: Allowed / Blocked / Scanned with counts; tapping a bar deep-links to Audit pre-filtered to that action class. **Enhancement over TUI:** a 24 h hourly stacked mini-histogram (allowed vs blocked) beneath the bars, from `audit_events` grouped by hour.
4. **Doctor card** — last health-check results bucketed pass/warn/fail with ✓/⚠/✕ rows. Toolbar: **Run Health Check** (lightweight probe ≈ TUI Shift+D) and **Doctor deep-dive** (streams `defenseclaw doctor` output into a sheet ≈ TUI `d`).
5. **AI Discovery card** (when enabled) — top 8 recent detections: `ecosystem/name vX.Y.Z` + confidence gauge, sorted by confidence desc; "See all →" → AI Discovery panel.
6. **Keys/Credentials card** — active API key counts, unused counts, service account rotation age; overflow warning >10 active.

Data: pulse + background tiers. Writes: none (doctor runs are diagnostics).

### 9.2 Alerts

Unified findings table (audit blocks ∪ scan findings ∪ egress bypasses), columns: Time · Kind (audit/scan/finding/egress) · Action · Target · Severity · Run · Details. Scan rows expand (disclosure) to nested findings — `DisclosureGroup` rows.

- **Filters:** severity chip row (All/CRITICAL/HIGH/MEDIUM/LOW — single-select, parity with `f` cycling), kind filter menu, free-text search.
- **Selection:** multi-select (⌘-click/⇧-click ≈ space/Shift+A/Shift+D).
- **Detail inspector:** full event JSON, related findings, consequence summary (port of consequence screen).
- **Header strip:** count-by-severity `StatCard`s + 24 h alert sparkline (enhancement).

Writes:
| Action | Backend |
|---|---|
| Acknowledge (single/bulk) | `POST /enforce/allow` |
| Dismiss | local state only (persisted in app prefs, parity with TUI) |
| Clear acknowledged | local state |
| Export selection | JSON file via save panel |

Data: SQLite `audit_events` (block-class actions) + JSONL `scan_finding`/`egress` rows. Tier: pulse-fed (new rows appear live).

### 9.3 Skills

Table: Enabled (Toggle) · Name · Version · Source (bundled/custom). Search, refresh.
Data: `GET /skills`. Writes: toggle → `POST /skill/enable` / `/skill/disable` (`{"skillKey": …}`); optimistic UI with rollback + error toast on failure. Destructive-feeling disables get no confirmation (parity), but failures surface clearly.

### 9.4 MCPs

Table: Enabled (Toggle) · Name · Transport (stdio/http) · Endpoint · Version.
Writes: toggle → `POST /mcp/enable|disable`; **Edit Config…** row action → form sheet (port of `MCPSetFormScreen`) → `PATCH /config/patch` per field (`{"path": "mcps.<name>.<field>", "value": …}`).

### 9.5 Plugins

Table: Enabled (Toggle) · Name · Version · Category. Toggle shows confirmation dialog (parity) then `POST /plugin/enable|disable` with **90 s** timeout and inline progress spinner on the row.

### 9.6 Tools

Table: Name · Description · State (allow/block/observe segmented control) · Usage count. Detail inspector: full signature + usage history.
Data: `GET /tools/catalog` + SQLite `actions` overrides (target_type="tool").
Writes: state change → `POST /enforce/block` / `POST /enforce/allow`.

### 9.7 Inventory

Segmented subtabs (parity with TUI subtabs): **Agents · MCPs · Plugins · Skills · Memories · Model Providers**, plus a Summary header with per-category counts and last-scan time.
Actions: **Scan category** (per-tab) and **Rescan all** → `POST /v1/skill/scan` / `POST /v1/mcp/scan` (async, 120 s, progress shown in toolbar + menu bar scanning state). Respects privacy/redaction settings from config.
Data tier: on-demand.

### 9.8 Logs

The TUI's multi-stream viewer, native:
- **Source tabs:** gateway · verdicts · otel · watchdog.
- **Filter chip rows:** Severity (CRITICAL…INFO) · Action (block/allow/reject/scan/verdict/hook) · Event type (audit/scan/hook/skill/mcp/plugin) · **Presets** (all, no-noise, important, errors, warnings+, scan, drift, guardrail, hooks) — preset list and matching rules ported verbatim from `FILTER_PRESETS`.
- Monospaced rows: `time · stream · severity · message`, severity-colored gutter. Auto-scroll toggle (pin-to-bottom), pauses on user scroll-up.
- Row actions: copy line, copy JSON, open verdict detail (judge history port).
- **Redaction indicator:** badge showing whether `DEFENSECLAW_DISABLE_REDACTION` is in effect (read-only display + explanation, parity with `m`).
- Live: tail-fed (pulse tier). "Load older" re-reads larger window from disk.

### 9.9 Audit

Immutable trail table: Time · Action · Type · [Connector] · Target · Severity · Run · Details. Connector column auto-appears in multi-connector deployments (parity).
- **Preset filters:** All · Risk (HIGH/CRITICAL) · Blocks · Scans · Credentials (port of `AUDIT_COMMON_FILTER_LABELS`), plus connector picker, plus search.
- **Enhancements:** date-range picker; severity-over-time stacked bar chart header (collapsible).
- Detail inspector: full event + structured JSON + related findings.
- **Export:** selected or filtered set → JSON via save panel (schema identical to TUI export).
Data: SQLite `audit_events`, paged query (`ORDER BY timestamp DESC LIMIT/OFFSET`, infinite scroll). Writes: none (export only).

### 9.10 Activity

Config-mutation feed: Time · Actor · Action · Target · Version from→to · Reason. Detail inspector: **DiffView** — before/after JSON, red deletions / green additions (parity with TUI diff styling).
Data: JSONL `activity` rows + SQLite `activity_events`. Read-only.

### 9.11 AI Discovery

Master table: Component (ecosystem/name) · Version · **Confidence** (numeric + linear gauge) · State (detected/uncertain/trusted) · Last seen. Summary header: total components, average confidence, last scan time.
Detail inspector: filesystem locations list + **confidence history line chart** (Swift Charts `LineMark`, 50-snapshot series from `…/history`) — this is the TUI's drill-down, finally with a real chart.
Actions: **Scan now** → `POST /api/v1/ai-usage/scan` (120 s, async); confidence-policy viewer (`GET /api/v1/ai-usage/confidence/policy`) with YAML validate (`POST …/policy/validate`) and apply via `PATCH /config/patch`.

### 9.12 Registries

Two-pane: **Sources** (URL · enabled toggle · last sync · model count · error) → **Models** of selected source (Name · Provider · Type · Capabilities), searchable.
Writes: enable/disable source → `PATCH /config/patch`; **Sync** (selected) and **Sync All** fetch remote catalogs and update `registry-cache.json` semantics via gateway/CLI parity. Sync errors shown inline on the source row.

### 9.13 Setup (full parity)

Two modes, like the TUI:

**A. Wizards** — each TUI wizard becomes a native multi-step sheet (`NavigationStack` in sheet):
1. **Connector** — pick framework (OpenClaw/Codex/…), mode (observe/enforce), rule pack, restart option.
2. **LLM** — provider picker → conditional fields (model, API key [SecureField with reveal ≈ Ctrl+T], base URL, region/auth-mode for bedrock-style providers). Conditional reveal rules ported from `_SETUP_DRIVER_FLAGS/_LABELS`.
3. **Custom Providers** — add/edit custom LLM endpoints.
4. **Guardrail** — mode, scanner, judge model (model picker fed by Registries).
5. **Notifications** — desktop/Slack/email/webhook destinations (multi-select + per-destination fields).
6. **AI Discovery** — enable, cadence, scope, privacy/redaction toggles.
7. **Observability** — OTEL exporter / audit sinks editor (port of resource editor screen).

Each wizard ends with a **Review step**: shows the exact `defenseclaw setup … --yes` command and a config **DiffView** (port of config-diff screen). **Apply** runs the command via `CLIRunner` with streamed output in the sheet; success/failure clearly reported; relevant panels refresh after apply.

**B. Config Editor** — form-based editor with the TUI's 8 tabs: Connector · LLM · Guardrail · Notifications · Privacy · Gateway · Observability · Enforcement. Field types: toggle, picker, secure text, multi-select. **Apply** / **Revert (reload from disk)** / delete-custom-entry, parity with TUI `a`/`r`/`d`. Unsaved-changes indicator and confirm-on-navigate.

Secrets handling: SecureField, reveal toggle, copy button (≈ Ctrl+Y); never logged.

### 9.14 First-Run / Onboarding

Port of `first_run.py` intent, shown when config or gateway is absent on first launch:
1. Detect installation (config.yaml? gateway reachable? CLI on PATH?).
2. If missing → guidance screen with the install one-liner and docs links (app does not install anything).
3. If present → confirm connection, request notification permission, explain menu bar behavior, land on Overview.

### 9.15 Command Palette (⌘K)

Port of the TUI command palette + panel jumper: fuzzy list of navigation targets and actions (refresh, run health check, scan inventory, sync registries, acknowledge all alerts, open setup wizard X…). Mutating entries show their consequence in the subtitle.

---

## 10. App Settings (the app's own preferences — distinct from DefenseClaw Setup)

- **General:** Show Dock icon · Hide app when window closes · Launch at login · Show in menu bar (always on; informational).
- **Monitoring:** polling cadences per tier · background monitoring while hidden · pause schedules.
- **Notifications:** per-severity toggles · sounds · notify on gateway offline/recovered.
- **Appearance:** system/light/dark override · accent (Cisco Blue fixed; option for system accent) · monospace size for logs.
- **Connection:** detected gateway URL/port (read-only from config) · `defenseclaw` binary path override · reload config now.
- **Data:** seen-alert reset · export app diagnostics.

---

## 11. Security Considerations

- Gateway token read from `config.yaml`; held in memory; optional Keychain mirror. Never written to logs, never displayed unmasked without explicit reveal.
- All gateway traffic is localhost HTTP (upstream design); the app refuses non-loopback hosts.
- `audit.db` opened read-only; JSONL opened read-only; the app's only filesystem writes are its own prefs and user-initiated exports.
- `CLIRunner` executes only the fixed `defenseclaw` verb set assembled from validated wizard fields — no shell interpolation (direct `Process` argv).
- Respect DefenseClaw redaction: the app displays what the backend provides and surfaces redaction status; it adds no de-redaction capability.
- Notifications contain target + severity only, not payload contents (payloads may hold sensitive prompt data).

---

## 12. Performance Budgets

- Idle (window hidden, pulse polling): < 1% average CPU, < 80 MB RSS.
- JSONL tail processing: incremental only; never re-read whole file on pulse.
- Tables virtualized (SwiftUI `List`/`Table` lazy); Audit paged at 200 rows/page.
- Cold launch to populated Overview (gateway healthy): < 2 s.

---

## 13. Project Structure

```
DefenseClawMac/
├─ DefenseClawMac.xcodeproj
├─ App/                    # @main, AppState, MenuBarExtra scene, main window scene
├─ DesignSystem/           # Colors.xcassets, SeverityBadge, StatePill, StatCard, MiniBars,
│                          # FilterChipRow, DiffView, EmptyState, chart styles
├─ DataLayer/
│  ├─ GatewayClient/       # endpoints, DTOs (Codable), errors
│  ├─ AuditStore/          # GRDB records, queries
│  ├─ EventStream/         # JSONL tailer, row models, stream classification
│  ├─ ConfigStore/         # Yams models, file watcher
│  ├─ CLIRunner/
│  └─ RefreshEngine/
├─ Features/               # one folder per panel: View + Store (+ tests)
│  ├─ Overview/ Alerts/ Skills/ MCPs/ Plugins/ Tools/ Inventory/
│  ├─ Logs/ Audit/ Activity/ AIDiscovery/ Registries/
│  ├─ Setup/               # Wizards/ (7) + ConfigEditor/
│  ├─ FirstRun/ CommandPalette/ SettingsScene/ MenuBarPopover/
└─ Tests/                  # unit: stores, parsers, filter presets; fixture JSONL/SQLite
```

Testing strategy: the TUI's service layer is pure state machines with good tests — port their fixtures (sample `gateway.jsonl`, seeded `audit.db`, sample `/health` JSON) and assert identical classification/filter behavior (especially `FILTER_PRESETS`, severity mapping, egress parsing, staleness logic).

---

## 14. Build Plan (milestones)

| # | Milestone | Contents | Exit criteria |
|---|---|---|---|
| M1 | **Skeleton + data layer** | App shell, menu bar icon w/ state machine, GatewayClient, ConfigStore, AuditStore, EventStreamReader, RefreshEngine; design system tokens | Menu bar reflects live gateway state against a real local DefenseClaw install |
| M2 | **Monitor panels** | Overview (full), Alerts, Logs, Audit, Activity; notifications; offline states | Side-by-side parity check vs TUI on same machine |
| M3 | **Govern + Discover panels** | Skills, MCPs, Plugins, Tools (all mutations), Inventory, AI Discovery, Registries | Every TUI write action verified end-to-end (toggle → gateway → reflected in TUI too) |
| M4 | **Setup parity** | 7 wizards + config editor + CLIRunner + diff/review | Each wizard produces byte-identical CLI invocations to the TUI's |
| M5 | **Polish** | Command palette, first-run, settings, keyboard shortcuts, perf budget pass, accessibility audit | Full parity checklist (Appendix D) signed off |

---

## 15. Risks & Open Questions

1. **Upstream API drift** — DefenseClaw is active; endpoint shapes may change. Mitigation: DTOs decode leniently; version surfaced from `/health`; parity pinned to the studied commit, re-verify at build start.
2. **Setup wizard fidelity** — 5,000 lines of conditional wizard logic is the highest-effort, highest-drift area. Mitigation: generate wizard field definitions from a single table per wizard; review-step shows the exact CLI command so users can verify.
3. **JSONL scale** — very chatty gateways could grow gateway.jsonl large; tail-only strategy + bounded "load older" handles it, but rotation behavior should be tested against upstream's writer.
4. **Schema versioning** — `activity_events` is v7+; need graceful degradation on older DBs (specified §8).
5. **Open:** should "Acknowledge" semantics (POST /enforce/allow) get a stronger confirmation in the app than the TUI's, since allow-listing has enforcement consequences? **Proposed: yes — confirmation dialog with consequence text for bulk acknowledge.**
6. **Open:** Sparkle-based auto-update is out of scope for a personal build but trivially addable later.

---

## Appendix A — Gateway Endpoint Inventory (used by the app)

**Read:** `GET /health`, `GET /status`, `GET /skills`, `GET /mcps`, `GET /tools/catalog`, `GET /enforce/blocked`, `GET /enforce/allowed`, `GET /api/v1/ai-usage`, `GET /api/v1/ai-usage/components`, `GET /api/v1/ai-usage/components/{eco}/{name}/locations`, `GET /api/v1/ai-usage/components/{eco}/{name}/history`, `GET /api/v1/ai-usage/confidence/policy`, `GET /v1/guardrail/config`.

**Write:** `POST /skill/enable|disable`, `POST /mcp/enable|disable`, `POST /plugin/enable|disable` (90 s), `POST /enforce/block`, `POST /enforce/allow`, `PATCH /config/patch`, `POST /policy/reload`, `POST /policy/evaluate[/firewall]`, `POST /v1/skill/scan`, `POST /v1/mcp/scan` (120 s), `POST /api/v1/ai-usage/scan` (120 s), `POST /api/v1/ai-usage/confidence/policy/validate`, `POST /v1/guardrail/evaluate`.

Headers: `Authorization: Bearer <token>` (all writes), `X-DefenseClaw-Client: macos-app`.

## Appendix B — SQLite Tables Read

`audit_events` (id, timestamp✱, action✱, target, actor, details, structured_json, severity, run_id) · `scan_results` · `findings` (scan_id FK, severity✱) · `actions` (target_type, target_name, actions_json, reason) · `activity_events` (v7+) · `network_egress_events` · `target_snapshots`. ✱ = indexed; all access read-only.

## Appendix C — JSONL Row Types

`event` (generic audit/log) · `scan_finding` (nested under scans) · `activity` (before/after/diff JSON) · `egress` (target, decision, reason, looks_like_llm, branch). Stream classification: gateway / verdicts / otel / watchdog per TUI `load_gateway_log_views()` rules.

## Appendix D — Parity Checklist (acceptance)

For each of the 14 TUI panels: ☐ all displayed fields present ☐ all filters present ☐ all sorts/search present ☐ all mutations present and verified against gateway ☐ empty/error/stale states ☐ keyboard access. Plus: ☐ command palette ☐ help/cheat-sheet ☐ export formats identical ☐ severity/state color mapping reviewed ☐ menu bar states ☐ hide-on-close behavior ☐ notifications.
