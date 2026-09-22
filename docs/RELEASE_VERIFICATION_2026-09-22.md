# DefenseClawMac 1.1.23 verification — September 22, 2026

The release candidate passed all 35 standalone test scripts and an isolated
Debug macOS build. The compatibility audit is **not fully green**: its one
remaining failure records the deliberately preserved installed runtime's
source differences from current upstream mainline. This report does not claim
that identical `0.8.10` version labels imply identical runtime features.

## Verified identities

| Item | Identity |
|---|---|
| Mac candidate | 1.1.23, changes based on `4a9754422770c71cc5b72f628d0b304d58d63dfc` |
| Fresh upstream mainline snapshot | `f05a9d3cb115c18f2c7903590a82dadf8835f2ae` |
| Upstream version / config schema | 0.8.10 / 8 |
| Installed CLI | `/Users/kobrien/.local/bin/defenseclaw`, resolving into `/Users/kobrien/git/defenseclaw/.venv/bin/defenseclaw` |
| Installed runtime source | `85029e57e9094debd9366a7d5a9f7e6d5c3ef6fc`, with existing local repairs preserved |
| Installed gateway identity | 0.8.10, `85029e57+runtime-repair`, built September 21, 2026 |
| Installed gateway SHA-256 | `5dabbe93e6d3260b5b7f35ae2bc708ca374414f8e59d272164309fb775fd70d9` |
| Published 0.8.10 payload source metadata | `bf45995c7fa691f34ffa89b6f0468c93a6207dea` |

The published payload source above comes from the release provenance and source
map used by packaging. The release pipeline must authenticate those artifacts
again before publication. That older published payload is for fresh runtime
installation; administrator gateway control uses the existing installed
runtime and must not substitute it.

## Compatibility changes reviewed

- Regenerated the exact 235-entry upstream command registry. Its single new
  command is `setup kiro --yes`; it remains hidden unless the selected runtime
  advertises Kiro support. Unknown capabilities fail closed.
- Recorded 28 intentional standalone source differences against the exact
  upstream SHA. All 12 new or changed entries have explicit review reasons,
  including native administrator routing and cancellation, installation
  identity, source-runtime preservation, and independent runtime updates.
- Reviewed the 76 changed runtime contract files. Changes are predominantly
  additive Kiro/ACP surfaces and setup-readiness fixes, with preserved local
  runtime repairs also contributing to the difference. No live runtime was
  replaced or modified to make the audit pass.
- Runtime version parsing now accepts explicit DefenseClaw version lines, so
  Go/Sonic warnings cannot be mistaken for the installed version. Older
  installed versions show the published upgrade; equal/newer and source
  installations remain preserved.
- Upstream introduces a required ACP guard transaction starting at 0.8.11.
  Until complete ACP activation and rollback are implemented, packaging
  rejects 0.8.11 or newer before downloading runtime assets, and the app rejects
  ACP payload manifests. A remaining `defenseclaw-acp` file or dangling link
  counts as an existing partial runtime and blocks fresh installation.

## Checks completed

- All 35 `script/test_*.sh` suites passed in the final aggregate audit.
- Administrator helper suite: 110 security checks, including authorization,
  cancellation before execution, account isolation, installed-runtime copying,
  signature integrity, same-runtime Start, explicit Restart, and idle shutdown.
- Runtime manifest tests exercised accepted 0.8.10 payloads and rejected future,
  malformed, and ACP-bearing payloads. The exact packaging preflight was
  executed against supported and unsupported versions.
- Runtime preservation tests covered ACP-only files and dangling symlinks.
- Debug macOS build passed using a temporary DerivedData directory and ad-hoc
  signing; this compile does not certify administrator-service use or release
  notarization.
- `git diff --check` passed. Selected runtime help contracts, dependencies, and
  the 24-section setup catalog passed the audit's read-only probes.

The full audit ran with `--run-tests --build --write-baseline` against the fresh
snapshot. It exited 1 solely because the installed source differs from upstream
in 76 contract files. The warning about local runtime repairs is retained.
Updating the reviewed app-source baseline does not suppress this runtime
identity check or establish full installed-mainline equivalence.

## Live verification and remaining release evidence

A read-only Runtime self-test reported inference heartbeat, shadow egress, and
Endpoint Security agent actions running, with every selected plane running.
That check observed zero classified kernel events and one excluded event; it
establishes sensor startup, not successful end-to-end detection of every kind
of activity. The installed gateway digest above remained unchanged.

The final native-authorized restart succeeded on September 22 at 10:23 AM.
macOS granted the actual administrator right; the gateway and watchdog moved
to the account-specific `uid-501` private directory. Gateway status reported a
running API and agents, and the Runtime self-test reported all three selected
planes running. The installed gateway SHA-256 remained unchanged. This verifies
the final installed-runtime selection path, beyond the earlier authorization
handoff test.

A separate read-only investigation explains the zero-findings Runtime panel:
the default reporting floor is 30, above a compute-only heartbeat score of 25.
The installed runtime also has two coverage issues: omitted `ai_discovery.home_dirs`
is not expanded to the documented HOME default for macOS file-event watching,
and `dns_capture: false` is still described by a static BPF mechanism label.
Green plane status establishes startup, not complete intended coverage. No
runtime configuration, reporting floor, or installed runtime was changed to
hide these issues. The published 0.8.10 fresh-install payload predates these
new Runtime planes; identical version strings do not establish parity.

Final merged commit, signed release artifacts, notarization, fresh-download
verification, and release URL must be recorded after publication. No release
artifact is certified by this source/test report alone.
