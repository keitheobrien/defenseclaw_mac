# Compatibility audit failed

- **PASS** upstream mainline ede59bd77ff633f5014dff7964631e42088697e7 reports runtime 1.0.0
- **PASS** upstream supports config_version 9; Mac app version is 1.1.34
- **PASS** command palette matches all 249 upstream entries
- **PASS** removed config-v7 flags, keys, and commands are absent
- **PASS** legacy protected runtime protocol remains supported
- **PASS** 1.x flat release includes authenticated gateway, ACP, wheel, lock, and installer metadata
- **WARN** installed runtime 1.0.5 differs from source metadata 1.0.0 (/Users/kobrien/.local/bin/defenseclaw); validating executable contracts and installed package metadata
- **PASS** runtime help contract is available for setup observability
- **PASS** runtime help contract is available for agent discovery enable
- **PASS** runtime help contract is available for setup provider add
- **PASS** runtime help contract is available for setup webhook add
- **PASS** installed runtime dependencies satisfy packaged runtime requirements
- **WARN** upstream resolver overrides were not compared across the source-version skew
- **PASS** runtime setup catalog exposes 25 sections
- **FAIL** upstream moved from 00ef714b8a47f3ba90dad69b91dc8aa40c735057 to ede59bd77ff633f5014dff7964631e42088697e7; perform a fresh compatibility review
- **FAIL** unreviewed source differences: App/AppState.swift, App/DefenseClawApp.swift, DataLayer/AIRuntimeModels.swift, DataLayer/AuditStore.swift, DataLayer/CatalogCLI.swift, DataLayer/CommandActivityStore.swift, DataLayer/CommandRegistry.swift, DataLayer/ConfigStore.swift, DataLayer/ConnectorOnboarding.swift, DataLayer/GatewayClient.swift, DataLayer/Models.swift, DataLayer/OperatorAssetLists.swift, DataLayer/OperatorAssetListsConfig.swift, DataLayer/PolicyCatalog.swift, DataLayer/RedactionCommands.swift, DataLayer/RuntimeV1Alerts.swift, DataLayer/RuntimeV1Inventory.swift, DataLayer/SandboxInspection.swift, DataLayer/SandboxInspectionStore.swift, DataLayer/SandboxModels.swift, DataLayer/SkillScanner.swift, DataLayer/UpdateChecker.swift, Features/AIRuntimeView.swift, Features/AlertsView.swift, Features/CatalogViews.swift, Features/ConfigEditorDefinitions.swift, Features/DiscoverViews.swift, Features/FirstRunView.swift, Features/LocalModelsView.swift, Features/LogsView.swift, Features/MainWindow.swift, Features/OverviewView.swift, Features/PoliciesView.swift, Features/RedactionPolicyView.swift, Features/SandboxInspectorView.swift, Features/SandboxesView.swift, Features/SetupDefinitions.swift, Features/SetupView.swift, Resources/policy_catalog_bridge.py
- **WARN** baseline differences no longer present: DataLayer/CLIRunner.swift, DataLayer/InstallationContext.swift, DataLayer/InventoryOutputParser.swift
