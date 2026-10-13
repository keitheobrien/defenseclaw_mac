# Complete Sandbox setup

Setup → Sandbox now defaults to installing OpenShell prerequisites, configuring the local gateway, building the selected harness images, and running Doctor. The form and command review disclose installation consent before Apply. Users can turn off dependency installation or image builds; Doctor alone remains read-only.

The default sequence is:

```text
defenseclaw sandbox setup --non-interactive --install-openshell --harness claudecode --harness codex --no-wrappers --skip-images
defenseclaw sandbox image build claudecode codex
defenseclaw sandbox doctor
```

Each step runs through the selected runtime and Activity. Progress is shown while the command runs, keyed to that command's run ID rather than whichever Activity row the user selects. A failed, cancelled, or truncated result stops the sequence and cannot be reported as success. Shell wrappers remain optional and off by default.

The app delegates installation to the runtime's verified installer, including Homebrew OpenShell, e2fsprogs, and MicroVM signature repair where needed. It does not use sudo or blanket `--yes`, force a restart of active sandboxes, or bypass legacy migration confirmation. Running Docker and a usable Homebrew installation are prerequisites. VM disk preparation still occurs on the first sandbox session; project changes are retrieved with `sandbox pull`.

## Runtime identities

- Released runtime tested: 1.0.0, commit `57698deb67c902e563ed10114a20dbab010f8922`, config schema 9.
- Selected source runtime inspected: 1.0.0, commit `1173ebed4f9bc30036a039ace8eb8f58dbd40884`, launcher `/Users/kobrien/.local/bin/defenseclaw`.
- Upstream main observed: `13ec9bf343e767b265aec38678023c35c5308023`; this scoped change does not claim a full audit of that newer revision.
- App: development changes based on 1.1.27, branch `kobrien/sandbox-complete-setup`.

## Verification

- `script/test_setup_definitions_parity.sh`: passed. Default flow, explicit opt-outs, selected-harness builds, read-only Doctor, form/review agreement, and absence of forced restart/blanket answers.
- Full runtime compatibility audit: 41 regression scripts passed; the existing supply-chain assertion expected an obsolete identifier-only signature requirement. Updated that assertion to require the already-shipped Apple anchor, identifier, and team, then reran `script/test_supply_chain_safety.sh`: passed (42 total).
- Debug app compile: passed, including a standalone development app build.
- The audit still reports the two intentionally changed setup sources as unreviewed baseline hashes. The baseline has not been overwritten to hide those differences. The opt-in inspector layout script remains outside this scoped test.

- `python3 script/test_panel_native_smoke.py --run-sandbox-gui`: passed using the actual SwiftUI Review and Apply default actions against a disposable fixture. Verified the default install/build/doctor sequence reaches Activity, live output appears before completion, and an error at each of the three stages stops further commands. Screenshots visually confirm review, in-progress output, success, and failure states.
- `git diff --check`: passed.

Screenshots: [before](../images/sandbox-setup/before.png), [updated form](../images/sandbox-setup/sandbox-form.png), [review](../images/sandbox-setup/sandbox-review.png), [live progress](../images/sandbox-setup/sandbox-progress.png), [success](../images/sandbox-setup/sandbox-success.png), [setup failure](../images/sandbox-setup/sandbox-failed-setup.png), [image failure](../images/sandbox-setup/sandbox-failed-image.png), [Doctor failure](../images/sandbox-setup/sandbox-failed-doctor.png).

The development app is at `/private/tmp/DefenseClawMac-sandbox-setup-build/Build/Products/Debug/DefenseClawMac.app`. No new release was published during this development verification. Subsequent runtime 1.0.1 and release validation is recorded in RELEASE_VERIFICATION_1.1.28_2026-10-13.md. The installation workflow is exercised with a disposable CLI fixture; it does not uninstall or reinstall the user's working Homebrew/OpenShell installation. A new clean-machine dependency installation is not claimed.
