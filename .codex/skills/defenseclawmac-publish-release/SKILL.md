---
name: defenseclawmac-publish-release
description: Commit DefenseClawMac changes through a GitHub pull request and publish a signed, notarized macOS release when the user explicitly requests a release. Use for app releases, not ordinary Debug builds.
---

# Publish a DefenseClawMac release

Work from the canonical repository path, `/Users/kobrien/git/defenseclaw_mac`; `/Users/kobrien/DefenseClawMac` can be a symlink that breaks sandboxed builds. Preserve unrelated worktree changes. Use a clean branch or isolated worktree based on live `origin/main`, and stage only the requested change and release metadata. Follow repository `AGENTS.md` rules for focused checks, an app compile, and `git diff --check`.

## Commit and merge

- Verify live GitHub mainline, current tag/release, intended next app version, and the selected DefenseClaw runtime release. Confirm compatibility before building. Do not infer freshness from local tracking refs alone.
- Use `keitheobrien@gmail.com` for Git commit email and the authenticated `keitheobrien` GitHub account for the PR. Never use `codex` as the commit or PR identity. Check the resulting commit identity and PR author.
- Push the branch, open a PR with behavior, TUI parity, runtime version, verification commands, issue links if applicable, and screenshots for visible UI changes. Merge only after the requested change and relevant checks are reviewable. Build the release from the resulting `origin/main` commit, then verify the tag resolves to that commit.

## Build and publish

- Keep `~/.defenseclaw` runtime state and secrets untouched. Check the Developer ID identity and `notarytool` profile without printing credentials. Run the production `scripts/build_unified_dmg.sh` with an explicit `RUNTIME_TAG`; never publish `SKIP_NOTARIZE=1` output.
- Require accepted Apple notarization and stapling for both app variants and the DMG. Verify the app-only ZIP contains one top-level app and survives `ditto` and `unzip` extraction with strict code-signature, helper, stapler, and Gatekeeper checks. Require `scripts/verify_unified_release_artifact.sh <dmg>` and `spctl -a -t open --context context:primary-signature -vv <dmg>`.
- Record SHA-256 digests, create the version tag on merged mainline, and upload the updater ZIP before the unified DMG to a draft GitHub release. Download and validate the draft assets, then publish the release only after every gate passes.
- Freshly download both GitHub assets to a separate temporary directory before and after publication. Compare SHA-256 digests with build outputs and repeat ZIP extraction and unified DMG signature, stapler, Gatekeeper, and strict payload checks. Report the release URL, commit, runtime tag, artifact digests, and any checks that could not be performed.

Stop before publication when mainline provenance, signing, notarization, strict verification, or fresh-download validation fails. Report the exact blocker; do not label an unnotarized build as released.
