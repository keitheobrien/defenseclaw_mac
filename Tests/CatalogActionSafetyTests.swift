// Copyright 2026 Cisco Systems, Inc. and its affiliates
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// SPDX-License-Identifier: Apache-2.0

import Foundation

@main
struct CatalogActionSafetyTests {
    static func main() {
        CLIProcessGroupLauncher.execIfRequested()
        scanActionsRemainOneClickButAreMutations()
        informationalActionsRemainNonMutating()
        print("CatalogActionSafetyTests passed")
    }

    private static func scanActionsRemainOneClickButAreMutations() {
        let skill = SkillItem(
            key: "codex/example",
            name: "example",
            version: "1",
            source: "/tmp/example",
            enabled: true,
            connector: "codex"
        )
        let mcp = MCPItem(
            name: "example",
            transport: "stdio",
            endpoint: "example",
            version: "1",
            enabled: true,
            connector: "codex"
        )
        let plugin = PluginItem(
            name: "example",
            version: "1",
            category: "command",
            enabled: true,
            connector: "codex",
            commandID: "example"
        )

        let checks: [(CatalogResourceAction, CatalogInvocation)] = [
            actionAndInvocation(CatalogActions.skills(skill), skill: skill),
            actionAndInvocation(CatalogActions.mcps(mcp), mcp: mcp),
            actionAndInvocation(CatalogActions.plugins(plugin), plugin: plugin),
        ]
        for (action, invocation) in checks {
            expect(action.readOnly, "scan remains a one-click action")
            expect(action.changesState, "scan explicitly changes installation state")
            expect(!invocation.requiresConfirmation, "scan does not gain an unrelated confirmation")
            expect(invocation.changesState, "scan invocation reaches the mutation gate")
        }
    }

    private static func informationalActionsRemainNonMutating() {
        let skill = SkillItem(
            key: "codex/example",
            name: "example",
            version: "1",
            source: "/tmp/example",
            enabled: true,
            connector: "codex"
        )
        guard let info = CatalogActions.skills(skill).first(where: { $0.verb == "info" }) else {
            fail("skill info action is missing")
        }
        let invocation = CatalogActions.invocation(info, skill: skill)
        expect(info.readOnly, "info remains one-click")
        expect(!info.changesState, "info remains non-mutating")
        expect(!invocation.changesState, "info invocation bypasses only the mutation gate")
    }

    private static func actionAndInvocation(
        _ actions: [CatalogResourceAction],
        skill: SkillItem
    ) -> (CatalogResourceAction, CatalogInvocation) {
        guard let action = actions.first(where: { $0.verb == "scan" }) else {
            fail("skill scan action is missing")
        }
        return (action, CatalogActions.invocation(action, skill: skill))
    }

    private static func actionAndInvocation(
        _ actions: [CatalogResourceAction],
        mcp: MCPItem
    ) -> (CatalogResourceAction, CatalogInvocation) {
        guard let action = actions.first(where: { $0.verb == "scan" }) else {
            fail("MCP scan action is missing")
        }
        return (action, CatalogActions.invocation(action, mcp: mcp))
    }

    private static func actionAndInvocation(
        _ actions: [CatalogResourceAction],
        plugin: PluginItem
    ) -> (CatalogResourceAction, CatalogInvocation) {
        guard let action = actions.first(where: { $0.verb == "scan" }) else {
            fail("plugin scan action is missing")
        }
        return (action, CatalogActions.invocation(action, plugin: plugin))
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        Foundation.exit(1)
    }
}
