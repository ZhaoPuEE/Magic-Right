import Foundation
import Testing
@testable import SuperRightCore

@Suite("Codex Here in system Terminal")
struct SystemTerminalCodexServiceTests {
    @Test("Paths are positional arguments and AppleScript quotes them as data")
    func pathsRemainData() {
        let directory = "/Users/example/project's name; touch danger"
        let executable = "/opt/homebrew/bin/codex"
        let arguments = SystemTerminalCodexService.commandArguments(
            directoryPath: directory,
            codexExecutablePath: executable
        )

        #expect(Array(arguments.suffix(2)) == [directory, executable])
        #expect(!arguments.dropLast(2).contains(where: {
            $0.contains(directory) || $0.contains(executable)
        }))
        #expect(arguments.contains(where: { $0.contains("quoted form of workingDirectory") }))
        #expect(arguments.contains(where: { $0.contains("quoted form of codexExecutable") }))
    }

    @Test("An existing Terminal window receives a new command tab")
    func existingWindowBehavior() {
        let arguments = SystemTerminalCodexService.commandArguments(
            directoryPath: "/Users/example/project",
            codexExecutablePath: "/usr/local/bin/codex"
        )

        #expect(arguments.contains("do script commandText in front window"))
        #expect(arguments.contains("do script commandText"))
    }

    @Test("Terminal automation denial has a specific error")
    func automationDenial() {
        let service = SystemTerminalCodexService(
            commandRunner: TerminalStubCommandRunner(
                result: StructuredCommandResult(
                    terminationStatus: 1,
                    standardOutput: Data(),
                    standardError: Data("Not authorized (-1743)".utf8)
                )
            )
        )

        #expect(throws: SystemTerminalCodexError.automationDenied) {
            try service.launch(
                directoryURL: URL(fileURLWithPath: "/Users/example"),
                codexExecutableURL: URL(fileURLWithPath: "/usr/local/bin/codex")
            )
        }
    }
}

private struct TerminalStubCommandRunner: StructuredCommandRunning {
    let result: StructuredCommandResult

    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?
    ) throws -> StructuredCommandResult {
        result
    }
}
