import Foundation

@main
struct ConnectorInventoryCompatibilityTests {
    static func main() {
        skillDirectoriesMatchCurrentConnectors()
        mcpSourcesMatchCurrentConnectors()
        retiredConnectorsHaveNoInventorySources()
        print("ConnectorInventoryCompatibilityTests passed")
    }

    private static func skillDirectoriesMatchCurrentConnectors() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        expect(
            SkillScanner.skillDirs(connector: "devin")
                == ["\(home)/.config/devin/skills", "\(home)/.agents/skills"],
            "Devin skill directories match the current runtime contract"
        )
        expect(
            SkillScanner.skillDirs(connector: "antigravity")
                == ["\(home)/.gemini/config/skills", "\(home)/.gemini/antigravity-cli/skills"],
            "Antigravity skill directories match the current runtime contract"
        )
        expect(
            SkillScanner.skillDirs(connector: "amp")
                == [
                    "\(home)/.config/agents/skills",
                    "\(home)/.agents/skills",
                    "\(home)/.config/amp/skills",
                    "\(home)/.claude/skills",
                ],
            "Amp skill directories match the current runtime contract"
        )
        let codex = SkillScanner.skillDirs(connector: "codex")
        expect(codex.first == "\(home)/.agents/skills", "Codex shared skill directory is retained")
        expect(codex.count == 2 && codex.last?.hasSuffix("/skills") == true, "Codex home skill directory is retained")
    }

    private static func mcpSourcesMatchCurrentConnectors() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        expect(
            MCPScanner.sources(connector: "devin").map(\.path)
                == [
                    "\(home)/.config/devin/mcp_config.json",
                    "\(home)/.config/devin/config.json",
                ],
            "Devin MCP sources match the current runtime contract"
        )
        expect(
            MCPScanner.sources(connector: "antigravity").map(\.path)
                == ["\(home)/.gemini/config/mcp_config.json"],
            "Antigravity MCP source matches the current runtime contract"
        )
        expect(
            MCPScanner.sources(connector: "amp").map(\.path)
                == [
                    "\(home)/.config/amp/settings.json",
                    "\(home)/.config/amp/settings.jsonc",
                ],
            "Amp MCP sources match the current runtime contract"
        )
        let opencode = MCPScanner.sources(connector: "opencode").map(\.path)
        expect(
            opencode == [
                "\(home)/.config/opencode/config.json",
                "\(home)/.config/opencode/opencode.json",
                "\(home)/.config/opencode/opencode.jsonc",
                "\(home)/.opencode/opencode.json",
                "\(home)/.opencode/opencode.jsonc",
            ],
            "OpenCode MCP sources match the current runtime contract"
        )
        expect(
            MCPScanner.sources(connector: "codex").first?.path.hasSuffix("/.codex/config.toml") == true,
            "Codex MCP source uses config.toml"
        )
    }

    private static func retiredConnectorsHaveNoInventorySources() {
        expect(SkillScanner.skillDirs(connector: "windsurf").isEmpty, "Windsurf skills are retired")
        expect(SkillScanner.skillDirs(connector: "geminicli").isEmpty, "Gemini CLI skills are retired")
        expect(MCPScanner.sources(connector: "windsurf").isEmpty, "Windsurf MCP sources are retired")
        expect(MCPScanner.sources(connector: "geminicli").isEmpty, "Gemini CLI MCP sources are retired")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAILED: \(message)\n", stderr)
            exit(1)
        }
    }
}
