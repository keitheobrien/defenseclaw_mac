# DefenseClawMac 1.1.24 verification — September 22, 2026

**Release publication is held.** The first merged candidate passed 35 headless
suites, an isolated Debug build, and preliminary native UI checks, but later
crashed in the optimized production app. Those results do not certify the
current candidate. All native inspector sizing variants, including fixed width,
have failed optimized full-app verification. The revised candidate uses a shared
inline detail pane and a non-observable Logs scroll-follow tracker. A populated optimized full-app run and upgraded
native regression controls passed. The final candidate also passed all 35
headless suites, an isolated Debug build, a fresh-launch full-app repeat, and
Audit/Activity pane checks. Final signed-production verification remains pending.

The compatibility audit also retains a separate known failure: the deliberately
preserved installed runtime differs from upstream in 76 contract files. App UI
baseline updates must not suppress that runtime identity difference.

## Identities and scope

| Item | Identity |
|---|---|
| First merged Mac candidate | 1.1.24, `1426a6fa04682bbe346dbaf0933bf4c508b07573` |
| Revised Mac candidate | Shared inline detail pane and private Logs tracker based on that commit; final merged identity pending |
| Upstream rechecked for this revision | `f05a9d3cb115c18f2c7903590a82dadf8835f2ae` |
| Upstream version / config schema | 0.8.10 / 8 |
| Installed CLI checked | `/Users/kobrien/.local/bin/defenseclaw`, resolving to `/Users/kobrien/git/defenseclaw/.venv/bin/defenseclaw` |
| Installed runtime source checked | `85029e57e9094debd9366a7d5a9f7e6d5c3ef6fc`, with existing local repairs preserved |
| Installed gateway checked | 0.8.10, `85029e57+runtime-repair`, built September 21, 2026 |
| Installed gateway SHA-256 checked | `5dabbe93e6d3260b5b7f35ae2bc708ca374414f8e59d272164309fb775fd70d9` |
| Native regression host | macOS 27.0 |

The final-candidate audit freshly checked upstream mainline again and confirmed
it remains at the SHA above. It reused the clean snapshot at
`/private/tmp/defenseclaw-release-compat.AI0G8H/upstream`. Installed runtime
identities were verified through read-only commands earlier in this investigation.
No runtime, configuration, reporting floor, or gateway service was changed for
that audit or this layout revision.

## Reviewed candidate behavior

The first correction relaxed the main pane's minimum size before native
inspector presentation. It addressed the original synthetic reproduction but
proved insufficient in optimized full-app testing. Keeping unconditional
inspector roots and flexible frames on both panes also failed. A fixed-width
native inspector passed an initial full run, then failed during cycle 5 of the
second fresh-launch Close Details sequence after resizing to 980 points. None
of these native sizing variants is accepted as the final correction.

The current candidate replaces the four nested native inspectors with one
shared `dcInspector` implementation. A SwiftUI `HStack` contains flexible main
content, a divider, and an explicit 320-point detail pane. Existing local
selection, hydration, and Close Details actions remain in place; Escape closes
through the presentation binding. The detail region retains scrolling and an
accessible Details label. The pane is no longer user-resizable across the
previous 250–380-point range. Native outer navigation, the window minimum, and
sidebar behavior are unchanged.

Logs now retains its imperative scroll-follow flag in a private non-observable
reference. Native row appearance/disappearance callbacks update that flag
without invalidating the SwiftUI view. The last-row checks, count-change
observer, auto-scroll guard, and row geometry are unchanged. This removes an
unnecessary observed-state write during row reuse; it is not a claim that Logs
alone caused the inspector failures. The native-inspector retry with this
tracker still failed, so both changes remain in the candidate.

Six production files were independently reviewed against the prior baseline:
`Components.swift`, `InspectorLayoutPolicy.swift`, and the Activity, Alerts,
Audit, and Logs panels. Five existing intentional entries received updated
hashes and reasons; the removed native column-width helper in `Components.swift`
added one entry.
The current baseline contains 32 reviewed differences. All 26 unchanged entries,
including their review reasons, were preserved exactly from the prior baseline.
The five obsolete native-inspector rationales were replaced by reasons describing
the final inline presentation and the scoped Logs tracker change. No command
registry regeneration, runtime replacement, or configuration-schema change is
part of this UI revision.
See [the crash investigation](INSPECTOR_CRASH_FIX_2026-09-22.md) for exact failure
sequences and the current candidate's scope.

## Historical automated checks: first candidate

The compatibility skill audit ran with `--run-tests --build` before the initial
reviewed baseline was written.

- All 35 non-GUI `script/test_*.sh` suites passed, including administrator/helper,
  runtime preservation, signing, update, output safety, and contract checks.
- The aggregate discovered 36 scripts. The native inspector script deliberately
  returned SKIP without `--run-gui`; its zero exit was not a GUI pass.
- The isolated Debug macOS build passed with temporary DerivedData and ad-hoc
  signing. It did not certify optimized production behavior.
- The 235-entry registry, retired-surface checks, schema-2 release protocol,
  selected runtime help contracts, dependencies, and 24-section setup catalog passed.
- The original baseline recorded 31 reviewed differences with preserved reasons.
  A subsequent read-only audit confirmed those initial hashes and retained the
  installed-runtime mismatch as its only failure.
- `git diff --check` passed for that candidate and its release records.

The initial full audit exited 1 for the installed-runtime difference and five
pending inspector baseline entries. After those entries were reviewed, the
confirmation exited 1 solely for the installed runtime's 76 changed contract
files, retaining its local-change warning. Equal 0.8.10 version labels do not
establish installed/mainline feature equivalence. The
[1.1.23 verification](RELEASE_VERIFICATION_2026-09-22.md) records the earlier
review of that gap and the existing ACP installation guard.

Historical audit evidence remains under
`/private/tmp/defenseclaw-1.1.24-compat.vivlixgh/`: `pre-baseline-audit.md`,
`baseline-write-audit.md`, `final-baseline-audit.md`, `prior-baseline.json`, and
`reviewed-source-hashes.json`. These files precede the inline detail-pane revision.

## Native and optimized full-app evidence

The first candidate's opt-in synthetic native regression reproduced the original
exception at 980 points and passed the main-pane-frame variant at 980 and 1180.
The inspected results remain at
`/var/folders/r9/6nkm3f8s4_j2fbgvxrzx3rxh0000gn/T/defenseclaw-inspector-native-tests.YQza12/`.
Preliminary Debug testing also exercised Alerts, Logs, Audit, and Activity's
command inspector. Activity's mutation inspector was not separately exercised.

Later optimized full-app testing superseded the apparent success: three
post-fix production crashes were observed. The first log includes NSTableView
reentrancy before the constraint exception; later diagnostic stacks include
SwiftUI graph transactions and hosting-view layout. Earlier passing keyboard
and synthetic runs do not dismiss the failing accessibility-driven sequences.

The fixed-width native candidate passed one optimized full-app run containing
four mass-deselect/select cycles across 1180/980/1677/980-point widths, six Close
Details/select cycles across 1180/980/1677/1180/980/1180, and a 20-second observation
period. It then failed during the second fresh-launch run. That experiment is
rejected; its initial clean log does not support a completion claim.

The inline-only investigation also encountered a native-table/layout hang
around Logs. The sample at
`/private/tmp/defenseclawmac-inline-sample.txt` shows native row removal entering
Logs' `onDisappear` closure. It does not directly show the conditional state
assignment executing. A separate synthetic Logs fixture did not reproduce a
crash or establish tracker-only causality. Its results do not justify changing
the row's leading strip geometry, which remains unchanged.

The combined inline-detail-pane and non-observable-tracker candidate passed an
optimized full-app run with approximately 5,556 log rows, selection at 980
points, six Logs-to-Alerts cycles across 980/1180/1677-point widths, and a
20-second observation period. Its recorded transition log contains no constraint
exception or reentrancy warning. A native resizable inspector retry with the same tracker failed Close Details cycle 2 after a
980-point resize; it was rejected and the inline candidate restored.

A fresh normal launch of the final inline candidate passed 20 selections,
10 close/resize cycles, and a 20-second observation period. Audit selection at
980 points passed. Activity's read-only `defenseclaw version` command completed
with exit 0, its detail pane opened at 980 points, Escape cleared the selection,
and reselecting reopened it. Activity's mutation detail pane was not separately
exercised. The final candidate screenshot is recorded in
[the crash investigation](INSPECTOR_CRASH_FIX_2026-09-22.md).

Full-app evidence is retained at
`/private/tmp/defenseclawmac-inline-log-final-check.log` and
`/private/tmp/defenseclawmac-log-follow-transitions.log`. Targeted read-only
inspection found zero constraint-exception or reentrancy-warning matches in
those logs. In a second fresh app instance, five further Logs-to-Alerts cycles
completed. The sixth automation cycle could not find a row while Logs loaded
asynchronously. This was not observed as an app crash: the immediate
accessibility check still found the Logs window at 980 × 760, and a manual
retry selected Logs row 2 and then Alerts row 2 successfully. The earlier
populated six-cycle batch remains the completed uninterrupted six-cycle check;
the second batch is not represented as six uninterrupted automated cycles.

The upgraded native regression controls passed on macOS 27.0 with `-O`:

- The native-inspector baseline at 980 points reproduced the known exception
  and exited 90 as expected.
- The actual shared inline modifier with native table input at 980 points
  completed its assertions and exited 0.
- The actual shared inline modifier with accessibility input at 1180 points
  completed its assertions and exited 0.
- Passing cases include selection, variable hydration, parent updates,
  close/open resize cycles, and a 20-second open-details observation period.
  An external watchdog enforces completion.

Results are recorded at
`/var/folders/r9/6nkm3f8s4_j2fbgvxrzx3rxh0000gn/T/defenseclaw-inspector-native-tests.9ryIrI/results.json`.
These tests compile the final production layout helper. They are separate from
the default headless skip and do not certify untested full-app paths or replace
final signed-artifact validation.

## Current automated verification

The new full compatibility audit completed with `--run-tests --build` against
the independently reviewed six-file production revision:

- All 35 headless suites passed. The aggregate discovered 36 scripts; the native
  GUI script deliberately skipped without `--run-gui` and is not counted as an
  executed headless suite or an aggregate GUI pass.
- The isolated Debug macOS build passed. Optimized native and full-app checks
  are recorded separately above.
- The 235-entry command registry, removed-surface checks, protected schema-2
  installer contract, runtime help, dependencies, and 24-section catalog passed.
- The full audit exited 1 for exactly two expected categories: the existing
  76-file installed-runtime source difference and the six reviewed UI files
  awaiting baseline refresh. No test or build failed.
- The baseline was written only after the checks and independent review. It
  records 32 intentional source differences and preserves every unchanged
  entry and review reason. The final read-only audit confirms all 32 reviewed
  hashes and exits 1 solely for the known 76-file installed-runtime mismatch;
  its existing local-change warning is also retained.
- `git diff --check` passed after the baseline and verification records changed.

Evidence is retained under
`/private/tmp/defenseclaw-1.1.24-inline-compat.l0pv9now/`: `pre-baseline-audit.md`,
`baseline-write-audit.md`, `final-baseline-audit.md`, `prior-baseline.json`, and
`reviewed-source-hashes.json`. No installed runtime or live configuration was
changed, and the known source mismatch was not added to an allowed baseline.

## Pending release checks

- Record the final merged commit and rebuild signed release artifacts from it.
  Artifacts from the earlier crashing candidate are not approved for publication.
- Complete notarization, strict artifact checks, fresh-download verification,
  and final UI verification of the actual signed production app.
- Record the final artifact digests and release URL only after those gates pass.

No current release-completion claim is made by this report. The installed-runtime
source gap remains independent of the inspector correction and must stay visible
in the final compatibility result.
