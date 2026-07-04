# Unified macOS Installer — Plan

One installer artifact that installs both the Mac app and the DefenseClaw
runtime; after install they run separately and update separately (app via its
self-updater, runtime via `defenseclaw upgrade`).

## Hard constraints (verified 2026-07-04)

| Constraint | Consequence |
|---|---|
| Keychain has **only** "Developer ID Application" (verified: `pkgbuild --sign` fails with "installer signing identity required") | A signed `.pkg` is **impossible today**. DMG is signed with `codesign`, which the existing cert handles — the full sign→notarize→staple pipeline works with the cert that exists. |
| Upstream `defenseclaw-gateway` Go binary is **ad-hoc signed** (verified via `codesign -dvv`) | Embedding the upstream tarball as-is would fail notarization (the notary service descends into archives). The gateway must be re-signed with the Application cert during the unified build. |
| Mac app policy: **never executes remote scripts automatically** | The installer flow must be native Swift steps, not `curl \| bash`. |
| Runtime needs `uv` + CPython 3.12 (~40 MB) + venv at `~/.defenseclaw/.venv` | A fully-offline embed balloons the DMG to ~100 MB. Hybrid is the sweet spot: embed the runtime (20.5 MB tarball + 1.7 MB wheel), fetch uv/Python only if missing — as **verified binary downloads**, never scripts. |
| No launchd for user installs — the gateway self-daemonizes with its own watchdog/pid | The installer needs no LaunchAgents. |
| Upstream publishes `checksums.txt` + Sigstore sig + `upgrade-manifest.json` | Build-time verification of what we embed is free; post-install upgrades stay on the runtime's own cosign-verified `defenseclaw upgrade` path, untouched. |

## Architecture: notarized DMG with embedded, re-signed runtime payload

**Artifact:** `DefenseClawMac-<appver>.dmg` (≈35 MB) — drag-to-/Applications
DMG, codesigned + notarized + stapled with the existing cert. Inside the app
bundle:

```
DefenseClawMac.app/Contents/Resources/RuntimePayload/
├── defenseclaw-gateway          # extracted from upstream tarball, re-signed
│                                #   Developer ID + --timestamp -o runtime
├── defenseclaw-X.Y.Z-py3-none-any.whl
└── payload-manifest.json        # runtime version, upstream sha256s,
                                 # upstream tag, build date
```

Each unified build snapshots whatever runtime version is latest upstream at
build time, verifies it (SHA-256 fail-closed; Sigstore via cosign, mirroring
`cmd_upgrade.py::_verify_checksums_sigstore` — identity regexp
`^https://github.com/cisco-ai-defense/defenseclaw/.+`, issuer
`token.actions.githubusercontent.com`), and embeds it. First launch on a
machine with no runtime offers **one-click install from the embedded
payload** — offline for the core, no remote script ever executed.

**Update separation is already built** and stays untouched: `UpdateChecker`
polls both repos independently; app updates swap the .app from the release
**zip** (still published alongside the DMG — the self-updater picks the first
`.zip` asset, so adding a DMG breaks nothing); runtime updates go through
`defenseclaw upgrade`. The embedded payload is used **only for first install /
repair** — once the runtime is installed, upstream owns its update track.

## Phase 1 — Unified build pipeline (`scripts/build_unified_dmg.sh`)

1. Download latest `cisco-ai-defense/defenseclaw` release assets:
   darwin_arm64 tarball, wheel, `checksums.txt` (+ `.sig`/`.pem`).
2. Verify sha256 against `checksums.txt`; cosign-verify `checksums.txt`
   itself. **Fail closed.**
3. Extract the gateway;
   `codesign -f -o runtime --timestamp -s "Developer ID Application"` it.
4. Stage `RuntimePayload/` into the exported app's Resources (binary
   extracted, not tarred — so notarization and the bundle seal cover it
   directly), write `payload-manifest.json`, re-sign the outer app.
5. Staple .app → `hdiutil create` (app + `/Applications` symlink) →
   `codesign` the DMG → `notarytool submit` DMG → staple DMG.
6. Release publishes **both** assets: the DMG (unified installer, the
   headline download) and the zip (self-update track).

## Phase 2 — In-app runtime installer

- New `RuntimeInstaller` actor: native Swift port of `install.sh`'s anatomy
  (venv creation via uv, wheel install, gateway →
  `~/.local/bin/defenseclaw-gateway`, `defenseclaw` symlink, gateway firstboot
  to mint the `.env` token — which the app's existing `diskSignature` watcher
  picks up automatically). Every step surfaces in the Activity panel like any
  CLI run.
- **FirstRunView rework:** when `installDetected == false`, the primary button
  becomes *"Install DefenseClaw Runtime vX.Y.Z (bundled)"* — user-initiated,
  offline, no remote script. The existing download-and-review-install.sh path
  stays as the secondary option.
- **Settings ▸ General:** "Install / Repair Runtime" action (repair = re-lay
  binaries/venv without touching `config.yaml`, `.env`, or `audit.db`).
- **uv/Python bootstrap:** use uv from PATH if present; otherwise download the
  uv binary from astral-sh GitHub releases with sha256 verification (a file
  download, not a script), then `uv python install 3.12`. Clearly badge the
  one step that needs network.

## Phase 3 — Edge cases

- Partial/broken installs (venv exists but wheel import fails; gateway binary
  missing) → repair flow.
- **Dev-install detection**: a source-checkout-style install (symlinks into a
  dev venv) must be detected and never clobbered — clear message instead.
- arm64-only for now (matches the app itself); amd64 machines get pointed at
  `install.sh`.
- Payload-older-than-installed guard: if an installed runtime is newer than
  the payload, offer repair-only, never downgrade.

## Phase 4 — Verification + release

- Clean-slate test in a fresh macOS user account: mount DMG → drag →
  first-run install → gateway healthy → wizard flow.
- Gatekeeper: `spctl -a -t open --context context:primary-signature` on the
  DMG, `spctl -a -t install` on the app, launch with quarantine intact.
- Confirm the hardened-runtime re-sign didn't break the Go gateway
  (start/stop, token firstboot). *Main technical risk — tested first, in
  Phase 1.*
- Update-separation test: bump app via self-updater, confirm runtime
  untouched; run `defenseclaw upgrade`, confirm app untouched.
- Cut as **v1.1.0**.

## Explicitly rejected

- **.pkg** — blocked by the missing Developer ID Installer cert; even with
  it, root-context postinstall into a user-home install is a minefield
  (wrong HOME, no proxy config, frozen Installer.app progress during ~60 MB
  of downloads). If MDM distribution ever matters, the Installer cert is a
  ~10-minute account-holder task — noted for later.
- **`.command` script on the DMG** — Gatekeeper-blocked (scripts can't be
  stapled).
- **Separate helper app** — strictly dominated by a first-run flow in the
  main app.
- **Fully-offline embed (uv + CPython included)** — 3× the DMG size to save
  one verified binary download; remains a follow-on option if an air-gapped
  story is ever needed.
