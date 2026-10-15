# Compatibility audit failed

- **PASS** upstream mainline 00ef714b8a47f3ba90dad69b91dc8aa40c735057 reports runtime 1.0.0
- **PASS** upstream supports config_version 9; Mac app version is 1.1.29
- **PASS** command palette matches all 251 upstream entries
- **PASS** removed config-v7 flags, keys, and commands are absent
- **PASS** legacy protected runtime protocol remains supported
- **PASS** 1.x flat release includes authenticated gateway, ACP, wheel, lock, and installer metadata
- **WARN** installed runtime 1.0.1 differs from source metadata 1.0.0 (/Users/kobrien/.local/bin/defenseclaw); validating executable contracts and installed package metadata
- **PASS** runtime help contract is available for setup observability
- **PASS** runtime help contract is available for agent discovery enable
- **PASS** runtime help contract is available for setup provider add
- **PASS** runtime help contract is available for setup webhook add
- **PASS** installed runtime dependencies satisfy packaged runtime requirements
- **WARN** upstream resolver overrides were not compared across the source-version skew
- **PASS** runtime setup catalog exposes 24 sections
- **FAIL** unreviewed source differences: App/AppState.swift, DataLayer/SandboxInspection.swift, DataLayer/SandboxInspectionStore.swift, DataLayer/SandboxModels.swift, Features/SandboxInspectorView.swift, Features/SandboxesView.swift
