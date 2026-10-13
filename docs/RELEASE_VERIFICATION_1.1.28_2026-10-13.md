# DefenseClawMac 1.1.28 release verification

## Scope and provenance

This release includes complete Sandbox setup and in-app runtime upgrades, with the official **DefenseClaw 1.0.1** payload for fresh installations. The authenticated release certificate binds that payload to source **00ef714b8a47f3ba90dad69b91dc8aa40c735057**; configuration schema remains **9**. The tag source retains `1.0.0` in project metadata, while the published wheel, gateway, ACP, and VERSION report **1.0.1**. Verification used those actual published artifacts and their signed dependency lock, not the user's older source installation.

The standalone app identity, administrator helper, existing-runtime preservation, and app-only update ZIP remain intact. The compatibility baseline retains documented reasons for 43 standalone differences against the exact release source. This is not a claim about unseen later mainline changes.

## Behavior

- Sandbox setup defaults to verified prerequisite installation, selected Claude Code/Codex image builds, and Doctor, with streamed per-step Activity output and stop-on-failure behavior. Installation/build opt-outs and optional shell wrappers remain available.
- Runtime 1.0.1 telemetry control and host-port guidance are reflected in the sandbox UI. Activity feed epochs detect daemon restarts even after sequence numbers overtake the previous feed; older gateways retain the event-based fallback. Retired sandbox legacy-cleanup guidance is removed.
- Upgrade Runtime executes the selected runtime's authenticated built-in updater with explicit installation paths and app preservation. It rechecks ownership/version, excludes concurrent commands, pauses audit readers, reports progress, verifies the installed version, and restores access on failure/cancellation. Equal/newer, source-owned, and managed installations remain protected.

## Completed checks

- Full compatibility audit: **42 regression scripts passed**, 251 registry entries and 24 setup catalog sections aligned, reviewed baseline matched, and Debug compilation passed. The inspector native layout script is opt-in and was not repeated for this scoped release.
- Real fresh installation of signed runtime 1.0.1 into a disposable HOME: CLI, gateway, ACP, installer, and VERSION checked; activation journal retired; repeat installation refused.
- Final Sandbox native UI: success and errors at each of setup, image build, and Doctor; live output, exact sequence, Activity, and stopping after failure verified. Updated telemetry form visually inspected.
- In-app runtime upgrade native fixtures: success, failure, cancellation, zero exit without version advancement, equal/newer versions, and source ownership. Verified exact argv/environment, duplicate prevention, command exclusion, audit suspension/recovery, background version suppression, and recorded output. The production action was exercised directly; Settings was rendered separately.
- Python syntax checks and `git diff --check` passed.

Evidence: [compatibility audit](release-1.1.28/compatibility-audit.md), [real fresh install](release-1.1.28/fresh-install.log), [sandbox native checks](release-1.1.28/sandbox-native.log), [runtime upgrade details](RUNTIME_UPGRADE_VERIFICATION_2026-10-13.md), [sandbox details](SANDBOX_SETUP_VERIFICATION_2026-10-12.md).

Screenshots: [sandbox form](../images/sandbox-setup/sandbox-form.png), [review](../images/sandbox-setup/sandbox-review.png), [upgrade progress](../images/runtime-upgrade/runtime-upgrade-progress.png).

## Limits and distribution gates

No live user-runtime migration, Homebrew/OpenShell reprovisioning, or privileged service restart was performed. Fixture tests do not certify those host-specific integrations. The audit reports source/package version skew described above; source resolver overrides were not compared across that skew. Published dependencies were authenticated by the signed release lock and successfully installed.

Production artifacts are built from merged mainline. Publication requires Developer ID signing, three accepted Apple notarization submissions (app-only, unified app, DMG), stapling, Gatekeeper, strict payload/helper checks, and fresh GitHub downloads matching local SHA-256 hashes. Final publication evidence, source commit, and digests are recorded in the GitHub release notes.
