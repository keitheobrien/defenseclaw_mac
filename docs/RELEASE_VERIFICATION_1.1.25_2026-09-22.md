# DefenseClawMac 1.1.25 release verification — September 22, 2026

## Scope and source evidence

This release enables **Start gateway automatically** by default after successful setup and on each application launch, including relaunch after an app update. Startup also runs when the restored main window is minimized. A healthy gateway is preserved, explicit opt-out is remembered, and administrator mode keeps the existing macOS authorization flow. Setup defers gateway startup until its structured initialization report confirms readiness. The change does not install, upgrade, replace, or downgrade an existing runtime.

The implementation and local UI evidence are documented in [Automatic gateway startup](GATEWAY_AUTO_START.md). [PR #27](https://github.com/keitheobrien/defenseclaw_mac/pull/27) was merged as `22e1aeb38cc37546976ab98a725d1c8194d3f523`. The signed release artifacts were built successfully from that exact mainline commit and published as [v1.1.25](https://github.com/keitheobrien/defenseclaw_mac/releases/tag/v1.1.25). Independent verification passed for both the local artifacts and fresh copies downloaded from the published release.

## Refreshed identities

| Component | Verified identity |
| --- | --- |
| Published Mac release | 1.1.25 at `22e1aeb38cc37546976ab98a725d1c8194d3f523` |
| Current upstream mainline | `f05a9d3cb115c18f2c7903590a82dadf8835f2ae` |
| Upstream runtime / configuration schema | 0.8.10 / 8 |
| Selected CLI | `/Users/kobrien/.local/bin/defenseclaw`, resolving to `/Users/kobrien/.defenseclaw/.venv/bin/defenseclaw` |
| Selected CLI version | 0.8.10 |
| Selected gateway version / source commit | 0.8.10 / `bf45995c7fa691f34ffa89b6f0468c93a6207dea` |
| Selected gateway SHA-256 | `8b752507bd911c5d38af24a0e8eef42230e088ee701e2b1528933603d69abfc3` |

The upstream tip and installed CLI/gateway identities above were refreshed read-only for this release on September 22. Runtime probes used version/help/catalog reads. No setup, gateway lifecycle, runtime update, or dependency mutation was performed by the compatibility audit.

## Source, tests, and UI verification

- All **36 headless test suites** and an isolated Debug build passed for the eight-file production candidate. The native GUI script explicitly skipped by default and is not counted as a GUI pass.
- A later application-launch callback fixed the restored-minimized-window case. The focused lifecycle regression test and a final Debug build passed after this ninth-file change. The full 36-suite run was not repeated after that focused lifecycle addition.
- The final implementation audit confirmed **35 reviewed source differences**, the 235-entry command registry, runtime help, the 24-section setup catalog, configuration schema, and protected installer contracts. The final merged-tree read-only audit confirmed the same 35 reviewed differences for version 1.1.25. All nine reviewed production-file hashes still match the tested implementation; the version bump changes metadata only.
- Coordinator tests cover default-on preferences, opt-out, running/offline/inconclusive health, configuration and managed-installation guards, concurrent triggers, stale state, canceled and failed startup, and fresh application launches. Onboarding tests cover structured setup-result validation. Administrator/CLI tests cover cancellation before dispatch.
- The final Debug app showed the first-run startup switch on in an isolated missing-configuration fixture. That fixture was read-only; a fresh runtime installation was not performed.
- Against the existing installation, Settings → Connection showed the startup switch on and enabled. The gateway PID stayed unchanged and its health endpoint returned HTTP 200 before and after app launch. Root startup was not repeated during this UI check; automated tests cover dispatch and authorization routing.

Final merged-tree audit evidence is retained under `/private/tmp/defenseclawmac-1.1.25-compat.5ua2luz5/` (read-only audit exit 1, with only the dependency difference below). Prior candidate evidence is retained under `/private/tmp/defenseclaw-gateway-autostart-compat.ur4qopzw/`, with the final lifecycle build log at `/private/tmp/defenseclawmac-gateway-autostart-final-build.log`. See the linked implementation document for before/after UI screenshots.

## Separate runtime dependency difference

The selected published 0.8.10 runtime has cryptography **48.0.1**, matching its authenticated release requirement `>=48.0.1,<49`. Current upstream mainline requires `>=50.0.0,<51`. The compatibility audit therefore reports this release/mainline dependency difference and exits 1; it is not a green aggregate audit. No dependency was changed and the failure was not suppressed. This difference is separate from the gateway-startup change and is not evidence of a Mac CLI or API contract failure.

The earlier 76-file source-checkout difference belongs to a previously selected runtime and is not current evidence about the selected published runtime installation.

## Signed production build and launch smoke check

The production packaging workflow completed successfully from merged commit `22e1aeb38cc37546976ab98a725d1c8194d3f523`. It authenticated the runtime release provenance, built the app-only ZIP and unified runtime DMG, verified strict app/helper/gateway signatures, and passed both supported ZIP extraction checks and the unified artifact verifier.

Apple accepted all three notarization submissions; stapling, ticket validation, and Gatekeeper assessment passed:

| Submission | Accepted notarization ID |
| --- | --- |
| App-only build | `5c342723-7203-4b55-a4d6-86077c8cb77c` |
| Unified app | `e0bdbe26-421b-4151-b590-b0640a979e92` |
| Unified DMG | `a02752a6-2aec-4cd7-90a3-067c79f083dc` |

| Local and published release artifact | SHA-256 |
| --- | --- |
| `DefenseClawMac-1.1.25.zip` | `248eb2eba357416a4c995198faabc828af0773557ef3441d15cb9b2056ac9ff5` |
| `DefenseClawMac-1.1.25.dmg` | `98462606cc6cce8801662c28fe5b0a74456c90ac0ffff3460bfe66d00a71b992` |

The signed app extracted from the app-only ZIP reported version 1.1.25 and remained running for 15 seconds with zero output-log bytes. This smoke check used an isolated missing-configuration fixture, created no fixture configuration, and left the existing gateway process IDs unchanged. It verifies launch of the signed artifact, not a fresh runtime installation or live administrator startup.

Build evidence is `/private/tmp/defenseclawmac-1.1.25-build.log`; the signed-app smoke result is `/private/tmp/defenseclawmac-1125-smoke-result.json`.

## Independent artifact and publication verification

[DefenseClawMac v1.1.25](https://github.com/keitheobrien/defenseclaw_mac/releases/tag/v1.1.25) was published at `2026-09-22T19:07:07Z`. The GitHub latest-release endpoint identifies it as the latest release, with `draft=false` and `prerelease=false`. Tag `v1.1.25` resolves to the exact merged and built commit `22e1aeb38cc37546976ab98a725d1c8194d3f523`.

An independent verifier passed against the built ZIP and DMG, then repeated the same checks against freshly downloaded published copies. The checks cover ZIP structure and extraction, strict app/helper/gateway signatures and expected signing identity, notarization tickets, Gatekeeper acceptance, DMG integrity, all runtime payload component hashes, authenticated source binding, and 124 hash-locked dependencies with authenticated direct references. Both fresh-download SHA-256 values and GitHub's asset digests match the table above exactly.

The unified payload contains runtime 0.8.10 from authenticated source commit `bf45995c7fa691f34ffa89b6f0468c93a6207dea`, source tree `e100109c00f297d2e15d50a8949a2a3664aafaa6`. Its Developer ID-signed gateway digest is `ad7e167dfbcaafe0cad384f73ea9c5be7d36a3da273201eb18dda976816d26a5`; this packaged signed binary is distinct from the preexisting selected gateway recorded above.

Evidence:

- Local independent verification: `/private/tmp/defenseclawmac-1125-independent-verify.log`.
- Published-copy independent verification: `/private/tmp/defenseclawmac-1125-published-independent-verify.log`.
- Fresh downloads: `/private/tmp/defenseclawmac-1.1.25-published-downloads/`.

### Asset-order exception

The intended ZIP-before-DMG upload order was not achieved: the GitHub CLI uploaded both assets concurrently, and the REST release asset list shows the DMG before the ZIP. An optional attempt to reupload identical DMG bytes solely to change that ordering was rejected by automatic approval review because it would replace a published artifact without explicit authorization for that replacement. No reupload or published-byte replacement occurred.

This ordering exception does not block the release or the app updater: `UpdateChecker.selectSelfUpdateAsset` selects the exact versioned ZIP name (`DefenseClawMac-1.1.25.zip`), independently of its position in the asset list. Both assets are present, notarized, and independently verified. The exception is retained here rather than claiming the intended upload order passed.

Publication and fresh-download verification are complete. The separate runtime dependency difference remains disclosed above; live fresh-install and administrator startup were not repeated as part of artifact verification.
