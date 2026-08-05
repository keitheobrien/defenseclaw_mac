# Compatibility Surfaces

Review these contracts whenever DefenseClaw mainline moves:

1. **CLI tree and arguments**: `cli/defenseclaw/tui/registry_data.py`, setup builders, catalog actions, onboarding, diagnostics, and upgrade commands. Removed flags must never remain in Swift builders.
2. **Configuration schema**: supported `config_version`, renamed/removed keys, typed setup fields, secret references, and mutation rules. Runtime-generated setup metadata is preferred; the offline fallback must target the same schema.
3. **Installation identity**: `DEFENSECLAW_HOME`, `DEFENSECLAW_CONFIG`, `DEFENSECLAW_VENV`, managed read-only mode, PATH/source installs, and symlink handling.
4. **Gateway and persistence**: health/status JSON, connector roster, audit SQLite columns, event JSONL schema, acknowledgements, inventory JSON, and observability destination state.
5. **Process behavior**: bounded output, cancellation escalation, mutation gating, hidden stdin for secrets, and environment protection.
6. **Upgrade/distribution**: runtime payload protocol, minimum/target versions, app-only asset name, GitHub SHA-256 digest, code signature, notarization, bundle identifier, and rollback.
7. **UI parity**: setup areas, command palette, activity lifecycle, alerts/details, catalog actions, overview counters, and TUI terminology.

The compatibility baseline records exact hashes for reviewed standalone differences. Any upstream or local hash change requires a fresh review even when the pathname was previously accepted.

Known runtime-backed normalization: DefenseClaw 0.8.5 accepts webhook type as the positional `setup webhook add <type>` argument. The upstream TUI registry's `--type`/Teams usage hint is stale; the Mac registry generator substitutes `<slack|pagerduty|webex|generic> [flags]` while retaining the upstream command row.
