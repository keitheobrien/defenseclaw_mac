import Foundation
import Observation

enum CommandActivityStatus: String, Sendable {
    case running
    case cancelling
    case finishing
    case succeeded
    case failed
    case cancelled

    var isActive: Bool {
        switch self {
        case .running, .cancelling, .finishing: true
        case .succeeded, .failed, .cancelled: false
        }
    }
}

struct CommandActivityEntry: Identifiable, Sendable {
    let id: UUID
    var title: String
    var command: String
    var category: String
    var origin: String
    var startedAt: Date
    var finishedAt: Date?
    var exitCode: Int32?
    var status: CommandActivityStatus
    var output: String
    var sideEffects: [String]
    var suggestedNextAction: String

    var duration: TimeInterval {
        (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var statusLabel: String {
        switch status {
        case .running: "Running"
        case .cancelling: "Cancelling..."
        case .finishing: "Finishing..."
        case .succeeded: "Exit 0"
        case .failed: "Exit \(exitCode ?? -1)"
        case .cancelled: "Cancelled"
        }
    }
}

@Observable
@MainActor
final class CommandActivityStore {
    private static let maximumOutputCharacters = 300_000

    @ObservationIgnored private let runner: CLIRunner
    var entries: [CommandActivityEntry] = []
    var selectedID: UUID?

    init(runner: CLIRunner) {
        self.runner = runner
    }

    @discardableResult
    func run(
        id: UUID = UUID(),
        title: String,
        binary: String = "defenseclaw",
        arguments: [String],
        standardInput: String? = nil,
        category: String = "other",
        origin: String,
        successEffects: [String] = [],
        suggestedNextAction: String = ""
    ) async -> CLIResult {
        guard await runner.reserve(runID: id) else {
            return CLIResult(
                exitCode: 125,
                output: "A command with this run identifier is already active.\n"
            )
        }
        entries.insert(
            CommandActivityEntry(
                id: id,
                title: title,
                command: Self.displayCommand(binary: binary, arguments: arguments),
                category: category,
                origin: origin,
                startedAt: Date(),
                status: .running,
                output: "",
                sideEffects: [],
                suggestedNextAction: ""
            ),
            at: 0
        )
        selectedID = id

        let result = await runner.run(
            binary: binary,
            arguments: arguments,
            standardInput: standardInput,
            runID: id
        ) { [weak self] line in
            Task { @MainActor in self?.append(line: line, to: id) }
        }

        guard let index = entries.firstIndex(where: { $0.id == id }) else { return result }
        if entries[index].output.isEmpty { entries[index].output = result.output }
        entries[index].finishedAt = Date()
        entries[index].exitCode = result.exitCode
        entries[index].status = result.cancelled ? .cancelled : (result.succeeded ? .succeeded : .failed)
        if result.succeeded {
            entries[index].sideEffects = successEffects.isEmpty
                ? Self.inferredEffects(binary: binary, arguments: arguments, category: category)
                : successEffects
        }
        entries[index].suggestedNextAction = result.succeeded ? suggestedNextAction : "Review the output, then run DefenseClaw Doctor."
        return result
    }

    func cancel(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].status == .running else { return }
        entries[index].status = .cancelling
        Task {
            let disposition = await runner.cancel(runID: id)
            guard let index = entries.firstIndex(where: { $0.id == id }),
                  entries[index].status == .cancelling else { return }
            switch disposition {
            case .requested, .alreadyRequested:
                break
            case .finishing:
                entries[index].status = .finishing
            case .notFound:
                entries[index].finishedAt = Date()
                entries[index].status = .cancelled
                if entries[index].output.isEmpty {
                    entries[index].output = "Cancellation requested after the command process was no longer active.\n"
                }
                entries[index].suggestedNextAction = "Refresh the affected view to verify its final state."
            }
        }
    }

    func clearCompleted() {
        entries.removeAll { !$0.status.isActive }
        if let selectedID, !entries.contains(where: { $0.id == selectedID }) {
            self.selectedID = entries.first?.id
        }
    }

    private func append(line: String, to id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].output += line + "\n"
        if entries[index].output.count > Self.maximumOutputCharacters {
            entries[index].output = "[Earlier output omitted]\n" + entries[index].output.suffix(Self.maximumOutputCharacters)
        }
    }

    private static func displayCommand(binary: String, arguments: [String]) -> String {
        ([binary] + arguments).map { value in
            value.contains(where: { $0.isWhitespace }) ? "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'" : value
        }.joined(separator: " ")
    }

    private static func inferredEffects(binary: String, arguments: [String], category: String) -> [String] {
        guard let command = arguments.first else { return [] }
        if binary == "defenseclaw-gateway" {
            if command == "restart" { return ["Gateway restarted"] }
            if command == "start" { return ["Gateway started"] }
            if command == "stop" { return ["Gateway stopped"] }
        }
        if command == "init" { return ["Configuration initialized"] }
        if command == "setup" || command == "config" { return ["Configuration updated"] }
        if command == "doctor" { return ["Diagnostic results refreshed"] }
        if command == "aibom" || category == "scan" { return ["Inventory or scan data refreshed"] }
        if command == "alerts" { return ["Alert state updated"] }
        if ["skill", "mcp", "plugin", "registry", "registries", "tool"].contains(command), category != "info" {
            return ["\(command.capitalized) state updated"]
        }
        return category == "info" ? [] : ["DefenseClaw state updated"]
    }
}
