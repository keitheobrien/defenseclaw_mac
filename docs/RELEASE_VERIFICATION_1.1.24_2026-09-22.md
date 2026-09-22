# DefenseClawMac 1.1.24 verification — September 22, 2026

The inspector crash patch passed all 35 executed standalone test suites and an
isolated Debug macOS build. The separate native GUI regression reproduced the
original constraint exception and passed with the production fix. The full
compatibility audit is **not fully green**: its only remaining failure records
the deliberately preserved installed runtime's 76 source-contract differences
from current upstream. The UI baseline update does not suppress that failure.

## Verified identities

| Item | Identity |
|---|---|
| Mac candidate | 1.1.24, based on `a324c1be664fd00d8c06000b6c0d765a625688cf` |
| Freshly checked upstream mainline | `f05a9d3cb115c18f2c7903590a82dadf8835f2ae` |
| Upstream version / config schema | 0.8.10 / 8 |
| Installed CLI | `/Users/kobrien/.local/bin/defenseclaw`, resolving to `/Users/kobrien/git/defenseclaw/.venv/bin/defenseclaw` |
| Installed runtime source | `85029e57e9094debd9366a7d5a9f7e6d5c3ef6fc`, with existing local repairs preserved |
| Installed gateway | 0.8.10, `85029e57+runtime-repair`, built September 21, 2026 |
| Installed gateway SHA-256 | `5dabbe93e6d3260b5b7f35ae2bc708ca374414f8e59d272164309fb775fd70d9` |
| Native regression host | macOS 27.0 |

A fresh `git ls-remote` check confirmed that upstream mainline still matched the
clean snapshot used by the prior release audit. The installed gateway digest
and source identity were checked again using read-only commands; no runtime,
configuration, reporting floor, or gateway service was changed for this audit.

## Scoped source review

The production change adds one shared zero-minimum flexible frame before the
native inspector on Alerts, Audit, Logs, and Activity. This breaks the
intrinsic-size feedback that reproduced AppKit's repeated constraint-update
exception. Inspector width limits remain 250/320/380 points. Data queries,
selection, filters, recorded commands, gateway controls, and runtime behavior
are unchanged.

The baseline now records 31 intentional standalone differences: two existing
records were updated for `InspectorLayoutPolicy.swift` and `LogsView.swift`,
and three were added for `AlertsView.swift`, `AuditView.swift`, and
`ActivityView.swift`. Each of these five records has an explicit review reason.
All other recorded hashes and reasons were preserved. Only the app-version
metadata changed to 1.1.24; upstream identity, runtime version, and schema remain
unchanged. No command-registry regeneration or runtime-contract update was needed.

Independent source review found no blocking issue. A more compressible main
pane can crowd fixed-width controls at narrow sizes; live testing confirmed
that table columns remain accessible through the native horizontal scrollbar.
See [the crash fix and live verification](INSPECTOR_CRASH_FIX_2026-09-22.md).

## Automated verification

The full compatibility skill audit ran with `--run-tests --build` against the
verified snapshot before the reviewed baseline was written.

- All 35 non-GUI `script/test_*.sh` suites passed, including the inspector layout
  policy, gateway administrator/helper, runtime preservation, signing, update,
  output safety, and contract suites.
- The aggregate discovered 36 scripts. `test_inspector_native_layout.sh`
  deliberately returns a documented SKIP unless `--run-gui` is supplied; its
  zero exit in the aggregate is not counted as a GUI pass.
- The isolated Debug macOS build passed with temporary DerivedData and ad-hoc
  signing. This verifies compilation, not production signing or notarization.
- The 235-entry command registry, retired-surface checks, schema-2 release
  protocol, selected runtime help contracts, installed dependencies, and
  24-section runtime setup catalog passed.
- After independent review and successful tests/build, `--write-baseline`
  recorded the exact hashes. Existing detailed reasons were restored, and the
  five scoped reasons were added. A subsequent read-only audit confirmed all
  31 reviewed source differences and retained only the installed-runtime failure.
- `git diff --check` passed for the candidate and these release records.

The initial full audit exited 1 for the known installed-runtime difference and
the five pending inspector baseline entries. The final confirmation also
exited 1, solely for the installed runtime's 76 changed contract files; its
warning about existing local runtime changes remains visible. Equal 0.8.10
version labels do not establish installed/mainline feature equivalence. The
[1.1.23 verification](RELEASE_VERIFICATION_2026-09-22.md) records the earlier
review of that preserved runtime gap and the existing ACP installation guard.

Local audit evidence is retained under
`/private/tmp/defenseclaw-1.1.24-compat.vivlixgh/`: `pre-baseline-audit.md`,
`baseline-write-audit.md`, `final-baseline-audit.md`, `prior-baseline.json`, and
`reviewed-source-hashes.json`.

## Native GUI and live application evidence

The opt-in [native regression](../script/test_inspector_native_layout.sh) was
run with `--run-gui --verify-reproducer` on macOS 27.0. Its fixture uses the actual
production sizing modifier and keeps the failing version as a control.

- Baseline at 980 points reproduced `NSGenericException` with the repeated
  Update Constraints message and a `SplitViewChildController` stack, exiting 90.
- Fixed cases at 980 and 1180 points exited 0. Each completed eight selections,
  asynchronous detail hydration, four close cycles, and final window checks.
- The native results JSON and logs were independently inspected at
  `/var/folders/r9/6nkm3f8s4_j2fbgvxrzx3rxh0000gn/T/defenseclaw-inspector-native-tests.YQza12/`.

Separate live application testing reproduced the released app's exception at
1180 points, then exercised the fixed Alerts inspector at 980, 1180, and 1677
points, including ten selections and five close cycles. Logs and Audit
inspectors remained responsive at 980 points. The Activity command inspector
also opened successfully at 980 after a read-only version command; the mutation
inspector was not separately exercised. These checks observed no corresponding
layout exception in the fixed app. The linked crash report contains the live
UI evidence and its scope.

## Release boundary

This report certifies the reviewed source, automated checks, and stated native
UI observations. The final merged commit, signed release artifact digests,
notarization, fresh-download verification, and release URL must be recorded by
the release pipeline before publication. No release artifact is certified by
the Debug build or this compatibility baseline alone.
