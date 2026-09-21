# Gateway/runtime repair — September 21, 2026

## Result and scope

The reproduced gateway trace failure is repaired at the command-startup boundary in
`/Users/kobrien/git/defenseclaw-runtime-repair`, branch
`kobrien/gateway-runtime-repair`. Changes are uncommitted. The existing Mac repairs
were preserved; all **32 Mac regression scripts** and a fresh Debug build pass.

This is a **source repair, not an installed-runtime or all-features sign-off**.
Podman/Splunk remain explicitly excluded and untouched. No installed service was started,
no live configuration/database was modified, and no installed executable was
replaced. No release, commit or pull request was created.

## Exact identities and concurrent installation changes

| Target | Verified identity/state |
| --- | --- |
| Mac checkout | `/Users/kobrien/git/defenseclaw_mac`, `5fc61cdf6e286bdee595714d514cc31152b040e5`, branch `kobrien/runtime-compat-d4b9a01`; existing repairs preserved |
| Runtime repair base / official main | `85029e57e9094debd9366a7d5a9f7e6d5c3ef6fc`, fetched from `cisco-ai-defense/defenseclaw` |
| Runtime toolchain | Go `1.26.4`, as declared by this revision |
| Installed CLI at the start | `0.8.10`, `/Users/kobrien/.local/bin/defenseclaw` → `/Users/kobrien/.defenseclaw/.venv/bin/defenseclaw` |
| Installed gateway at the start | `0.8.10`, `bf45995c7fa691f34ffa89b6f0468c93a6207dea`, built `2026-07-29T23:23:27Z` |
| Final selected-installation preflight | CLI and gateway executable absent; audit database absent; no TCP listener at the previously selected loopback port `18970` |

The main runtime checkout was recreated during verification, changing its HEAD
from `30181ea5dec2a202c6486c00b1cfbf9b7466898d` to `85029e57…` and removing the
Git metadata that registered the repair worktree. The repair source files were
intact. They were retained in place and given independent Git metadata against
the exact verified base. The broken pointer is preserved inside that checkout's
`.git/retired-worktree-link`. The recreated main checkout was not altered.

The installed executable paths and audit database subsequently disappeared.
The user was asked whether another task/installer was reinstalling DefenseClaw.
Earlier live observations therefore cannot be treated as the current installation
state. The final read-only preflight reports unavailable runtime/database/transport;
it is not evidence of database corruption. Do not deploy over a concurrent install.

## Verified defect and repair

Existing receive/normalize trace tests reproduced
`canonical normalize trace completion failed` on current main, including malformed
payload handling, routing, and generation reload. The minimal reload test also
failed with the pinned Go toolchain, so this was not merely a compiler-version issue.

Temporary content-free diagnostics narrowed the failure to canonical/physical
resource parity: the physical SDK span had an additional `defenseclaw.connector`
attribute. Names, timestamps, kind, flags, parent, status, control attributes and
scope matched. Registration was rejected as `handoff_not_consumed` and surfaced as
`registration_failed`. No payload or attribute value was printed by that diagnostic.

The pinned SDK's `WithResource` implementation merges environment
resources even when given an explicit resource. This is also required by the
[OpenTelemetry resource specification](https://opentelemetry.io/docs/specs/otel/resource/sdk/).
DefenseClaw's config-v8 canonical resource intentionally excludes that ambient
agent metadata, making the SDK and canonical records disagree.

The repair:

- Clears only `OTEL_RESOURCE_ATTRIBUTES` and `OTEL_SERVICE_NAME` from the gateway
  command's process at startup, before config loading, SDK construction and workers.
- Prevents `.env` loading from reintroducing those two resource-control variables.
  Custom metadata remains configurable through `observability.resource.attributes`.
- Preserves unrelated credentials and exporter settings. It does not edit the
  parent shell, agent settings or live `.env` file.
- Keeps strict canonical/physical parity intact; no SDK patch, resource-check
  relaxation, global temporary environment mutation during reload, or diagnostic
  suppression was used.
- Adds closed-vocabulary failure codes to all four receive/normalize warning
  sites. Wrapped error text and request content cannot cross that boundary.

The new command-entry regression failed before the fix for both actual SDK trace
and metric resources, and passes after it. It also checks `.env` reintroduction
and preservation of unrelated settings. Privacy tests cover known, wrapped,
unknown, zero-code and typed-nil errors. All temporary diagnostics were removed.

This explains the **reproduced failure mode**, not conclusively every historical
warning from the old installed gateway. Its generic warning can also cover other
registration failures. A repaired-runtime live check is still required.

## Verification

| Check | Result |
| --- | --- |
| New startup regression | FAIL before, PASS after; actual SDK trace and metric resources checked |
| Startup/config-loading/bootstrap tests with race detector | PASS |
| Full telemetry package with race detector | PASS |
| Full observability runtime package | PASS |
| Full audit package | PASS |
| Gateway OTLP, health and Runtime API/observability compatibility tests | PASS |
| Focused runtime/audit/gateway race reruns | PASS; no race reports |
| Mac standalone scripts | PASS, 32/32 |
| Fresh Mac Debug compile | PASS; local ad-hoc signature verifies |
| Development gateway build | PASS; version/help commands succeed without starting a service |
| Source whitespace checks | PASS in both repair and Mac checkouts |
| Final installed-runtime check | BLOCKED by missing installation paths and stopped/unavailable transport |

The original broad race runs reached their **total five-minute package budgets**
while individual tests were constructing fresh SQLite fixtures. They did not
report an assertion failure before timeout. Smaller race groups include the
interrupted cases; the full runtime/audit suites also passed without race
instrumentation. Direct package tests run with `OTEL_RESOURCE_ATTRIBUTES` and
`OTEL_SERVICE_NAME` unset because they bypass the repaired command entry point.
The new entry-point regression deliberately sets both to synthetic values.

Upstream main already includes the signed-commit SQLite-health recovery and
whole-transaction contention handling absent from the old installed build.
Those paths were tested, not modified or masked by the Mac app. The new Runtime
API is likewise in the selected mainline base; restoring it requires a coordinated
runtime/CLI deployment, not a Mac-only change or a piecemeal dependency update.

## Build evidence and remaining deployment boundary

Evidence directory:
`/private/tmp/defenseclaw-runtime-repair-20260921.3CdAQz`.
Temporary evidence may be removed by macOS; this report and the repair sources
are retained in the repositories.

- Gateway candidate: `defenseclaw-gateway-candidate`, marked
  `0.8.10-dev.runtime-repair`, base commit suffixed `-dirty`.
  SHA-256: `d4e1d7c73f867a9672cf973abaa8b2440694a5a20265f6a2a47c70f0894a7fe3`.
- Mac development app: `MacDerivedData/Build/Products/Debug/DefenseClawMac.app`.
  Launcher SHA-256: `05aac4eaa8b998af445b30583e76ff783c1d310d27dbab574a59e859c157138c`.
  Neither artifact is a notarized distribution release; neither was published.

At the start, the runtime's read-only source-install preflight correctly refused
to overwrite the release-managed installation. The official latest release was
still `0.8.10`, published July 30, so reinstalling that artifact would not provide
the newer Runtime implementation or this repair. That guard was not bypassed.
After the concurrent installation changes, the old preflight result is historical,
not authorization to install into the now-missing paths.

Next: establish the final intended runtime installation with the user, preserve
the independent repair, and use the appropriate authenticated build/upgrade
workflow. Then verify live gateway health, canonical receive/normalize traces,
SQLite recovery, and the Mac Runtime panel. Other previously unexercised live
mutations/integrations retain the limits documented in the September 18 report.
