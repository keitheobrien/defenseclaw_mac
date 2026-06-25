# Codex Project Setup

This directory contains repo-local Codex configuration that is safe to share
with other developers.

Included:

- `environments/environment.toml` wires the Codex Run action to
  `./script/build_and_run.sh`.
- `skills/pdf` is the project-shared PDF skill copied from the local Codex
  skill directory.

Intentionally excluded:

- Global Codex auth, history, SQLite state, memories, browser state, cache
  files, plugin cache, archived sessions, and machine-specific settings.
- System-managed Codex skills under `~/.codex/skills/.system`.

Developers can run the app from Codex with the Run action or directly with:

```bash
./script/build_and_run.sh
```

Use `CONFIGURATION=Release ./script/build_and_run.sh --verify` to build and
launch a Release configuration locally.
