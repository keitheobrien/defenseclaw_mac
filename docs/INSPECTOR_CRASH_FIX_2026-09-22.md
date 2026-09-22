# Inspector crash investigation and revised correction — DefenseClawMac 1.1.24

The first merged 1.1.24 candidate passed Debug and synthetic inspector checks
but still crashed in the optimized production app. Release publication remains
held. Flexible and fixed-width native inspector variants have all failed
optimized full-app verification. The revised candidate combines a shared inline
detail pane with a non-observable Logs scroll-follow tracker. An optimized
full-app run passed with populated Logs and repeated Logs-to-Alerts transitions.
A fresh-launch repeat, Audit, and Activity checks also passed. The final signed
production artifact still requires verification before publication.

## Reproduction and evidence

The published 1.1.23 app reproduced the submitted recording's failure: open
Alerts, close the inspector, resize to 1180 × 760, and select another alert.
AppKit threw `NSGenericException` after excessive Update Constraints passes.
The original stack includes
`SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)` and
`NSHostingView.SizeConstraints.update(from:)`.

The initial correction added a flexible zero-minimum main-pane frame before
`.inspector` on Alerts, Audit, Logs, and Activity. Its Debug checks and synthetic
native regression passed. That correction was merged as
`1426a6fa04682bbe346dbaf0933bf4c508b07573`, but subsequent optimized full-app
verification reproduced the constraint exception at 12:25, 12:31, and 12:43 on
September 22. These are real application failures; successful keyboard or
synthetic runs do not invalidate the accessibility-driven reproductions.

The first post-fix log starts with an NSTableView reentrancy warning. The later
exception stacks include hosting-view layout and SwiftUI graph transactions.
Evidence includes `/private/tmp/defenseclawmac-1.1.24-production-ui.log` and
`DefenseClawMac-2026-09-22-123120.ips` / `DefenseClawMac-2026-09-22-124334.ips`
in the local DiagnosticReports directory. Unconditional inspector containers
and flexible frames on both panes also failed the optimized full-app sequence.

## Revised candidate and rejected alternatives

A fixed-width native inspector passed one full previously failing sequence,
including a 20-second observation period. A second fresh launch nevertheless
failed during Close Details cycle 5 after resizing to 980 points. That approach
is rejected along with the earlier native sizing variants; its initial pass
is not evidence that the crash is resolved.

The current candidate replaces per-panel native `.inspector` presentation with
a shared `dcInspector` modifier in `InspectorLayoutPolicy.swift`. An ordinary
SwiftUI `HStack` lays out flexible main content, a divider, and a 320-point
detail pane. This removes the nested native inspector split controller rather
than adding another size negotiation constraint.

Alerts, Audit, Logs, and Activity keep their local selection, detail loading,
and existing Close Details actions. Escape closes the pane through the same
presentation binding. The detail region has an accessible Details label.
The pane is fixed-width rather than user-resizable between 250 and 380 points;
that is an intentional behavior change. The outer native navigation sidebar,
window minimum of 980 × 640, and scrolling remain in place. No inspector-driven
sidebar collapsing or programmatic window resizing was added.

Logs also keeps its imperative “at bottom” flag in a private non-observable
reference retained by `@State`. Row `onAppear` and `onDisappear` callbacks
update that flag without publishing a view-state change during native row reuse.
The existing auto-scroll guard, row layout, and visible controls are preserved.
The flag is not rendered in the view, so it does not need observation.

This tracker change is a precaution supported by the observed callback path,
not proof that Logs alone caused the crash. A sample of an inline-only hang
showed native table row removal entering Logs' `onDisappear` closure; the
sampled leaf was an identifier comparison, not an observed state write. A
bounded synthetic Logs fixture did not reproduce a crash or establish that
the tracker alone eliminates reentrancy warnings. A later optimized full-app
retry with the native resizable inspector and the tracker still crashed in
Close Details cycle 2 after resizing to 980 points. The final candidate therefore
retains both the inline presentation and the non-observable tracker.

The combined candidate passed an optimized full-app check with about 5,556 log
rows, selection at 980 points, six Logs-to-Alerts transition cycles across
980/1180/1677-point widths, and a 20-second observation period. A fresh normal
relaunch then passed 20 selections, 10 close/resize cycles, and a 20-second
observation period. Audit selection and Activity's command detail
pane also passed at 980 points, including Escape dismissal and reopening.
The corresponding final-check and Logs-transition logs contain no constraint
exception or reentrancy warning. These results are limited to the exercised
sequences; the final signed production artifact still requires verification.
A second fresh instance completed five additional Logs-to-Alerts cycles. A
sixth cycle encountered a temporarily absent row during asynchronous loading;
the app remained accessible and a manual Logs-to-Alerts retry succeeded. That
batch is not counted as six uninterrupted automated cycles.

## Verification status

| Candidate / check | Result |
|---|---|
| Published 1.1.23, full app at 1180 × 760 | Original constraint exception reproduced |
| First 1.1.24 correction, Debug and synthetic native checks | Passed those checks; insufficient to certify production |
| First 1.1.24 optimized production candidate | Failed with three observed post-fix crashes |
| Unconditional roots plus flexible frames on both panes | Failed optimized full-app selection/resize sequence |
| Fixed-width native inspector | First full run passed; second fresh launch failed after 980-point resize; rejected |
| Native resizable inspector plus Logs tracker | Failed optimized full-app Close Details cycle 2 after 980-point resize; rejected |
| Inline detail pane plus Logs tracker, populated optimized full app | Passed log selection and six Logs-to-Alerts transition cycles, then a fresh-launch 20-selection/10-close-and-resize sequence; each included a 20-second observation period |
| Final candidate Audit and Activity command panes | Passed at 980 points; Activity Escape and reopening also passed |
| Upgraded native GUI regression controls | Passed; evidence is recorded in the release verification report |
| Final automated compatibility checks and source-baseline refresh | 35 headless suites and Debug build passed; 32 reviewed source differences recorded; installed-runtime gap retained |
| Final signed production artifact UI verification | Pending; release remains held |

The failing production sequence uses accessibility mass-deselect/select cycles
at widths 1180, 980, 1677, and 980 points: deselect all rows, resize the window,
select row 2, then row 3. It also uses actual Close Details/select-row-2/select-
row-3 cycles across 1180, 980, 1677, 1180, 980, and 1180, followed by at least a
20-second observation period. A fresh launch repeat is required because the
fixed-width native candidate passed its first run and failed its second.

The upgraded opt-in native GUI test covers native table and accessibility
selection with the actual shared inline presentation modifier. Its controls
passed. It uses an external watchdog and checks completed selection, hydration,
close, and resize steps; process survival alone is insufficient. The earlier
synthetic results apply only to earlier candidates, and native-fixture success
does not replace verification of the full optimized app.

```bash
./script/test_inspector_native_layout.sh --run-gui --verify-reproducer
```

Without `--run-gui`, the script explicitly skips GUI testing during headless
runs. The baseline control needs an affected macOS version to establish the
before/after comparison.

The final candidate's live checks cover Alerts, populated Logs, Audit, and
Activity's command detail pane. The Activity check ran the read-only
`defenseclaw version` command successfully, opened its details at 980 points,
closed with Escape, and reopened on selection. Activity's mutation detail pane
was not separately exercised. Narrow tables retain horizontal scrolling.

![Final candidate Activity detail pane at 980 points](../images/inspector-crash-fixed-activity.png)

See [release verification](RELEASE_VERIFICATION_1.1.24_2026-09-22.md) for exact
identities, current and historical check results, remaining gates, and the
preserved installed-runtime source mismatch. No installed runtime was replaced for this
layout investigation.
