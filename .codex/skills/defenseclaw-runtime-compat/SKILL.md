---
name: defenseclaw-runtime-compat
description: Audit DefenseClawMac against the latest cisco-ai-defense/defenseclaw mainline and the locally installed DefenseClaw runtime. Use after a runtime/mainline update, before a Mac app release, or when CLI flags, config schema, setup wizards, inventory, audit data, gateway APIs, or release packaging may have drifted.
---

# DefenseClaw Runtime Compatibility

## Workflow

1. Start from a clean Mac-app branch. Do not modify unrelated changes in either checkout.
2. Resolve three identities: latest upstream commit, installed `defenseclaw` path/version, and Mac app version.
3. Run the audit from the Mac-app repository:

```bash
python3 .codex/skills/defenseclaw-runtime-compat/scripts/audit_compatibility.py \
  --mac-root "$PWD" --upstream /path/to/defenseclaw --run-tests --build
```

Omit `--upstream` to shallow-clone current GitHub mainline. Network access may require approval.

4. Read [contract-surfaces.md](references/contract-surfaces.md) before fixing failures. Treat command-table, removed-key, runtime-version, dynamic-catalog, and build failures as incompatibilities.
5. If only the command palette drifted, regenerate it from DefenseClaw's Python registry, then inspect the diff:

```bash
python3 .codex/skills/defenseclaw-runtime-compat/scripts/audit_compatibility.py \
  --mac-root "$PWD" --upstream /path/to/defenseclaw --sync-command-registry
```

6. Fix production code using current runtime contracts. Preserve standalone bundle ID, release repository, verified asset naming, and any local hardening unless upstream deliberately replaces them.
7. Re-run the full audit. After human review, record the exact known-good commit and intentional source deltas:

```bash
python3 .codex/skills/defenseclaw-runtime-compat/scripts/audit_compatibility.py \
  --mac-root "$PWD" --upstream /path/to/defenseclaw --run-tests --build --write-baseline
```

## Safety Rules

- Invoke subprocesses with argv arrays; never interpolate shell strings.
- Do not print environment values, config contents, credentials, or request bodies.
- Use only non-mutating runtime probes (`--version`, `--help`, and catalog imports).
- Do not claim compatibility with unseen future commits. A green result applies only to the reported upstream SHA, runtime version, and app revision.
- Never update the baseline merely to silence a failure. Inspect every changed hash and explain intentional divergence.

## Report

State the exact upstream SHA, installed runtime path/version, config schema, Mac app version, fixes made, tests/build run, and residual packaging or managed-install risks.
