import Foundation
import Testing
@testable import SuperRightCore

@Suite("Current Finder window navigation")
struct FinderNavigationServiceTests {
    @Test("A Finder path remains a positional argument instead of script source")
    func pathIsNeverAppleScriptSource() {
        let path = "/Users/example/Project \"name\"; $(touch nope)"
        let arguments = FinderNavigationService.commandArguments(
            directoryPath: path
        )

        #expect(arguments.last == path)
        #expect(!arguments.dropLast().contains(where: { $0.contains(path) }))
        #expect(arguments.contains(
            "set target of front window to POSIX file destinationPath"
        ))
    }

    @Test("A missing Finder window is created before setting its target")
    func noWindowFallback() {
        let arguments = FinderNavigationService.commandArguments(
            directoryPath: "/Users/example"
        )
        let scriptStatements = arguments.enumerated().compactMap { index, value in
            index > 0 && arguments[index - 1] == "-e" ? value : nil
        }

        #expect(scriptStatements.contains("if (count windows) is 0 then"))
        #expect(scriptStatements.contains("make new Finder window"))
    }

    @Test("Automation denial has a specific user-facing error")
    func automationDenial() throws {
        let service = FinderNavigationService(
            commandRunner: StubCommandRunner(
                result: StructuredCommandResult(
                    terminationStatus: 1,
                    standardOutput: Data(),
                    standardError: Data("Not authorized (-1743)".utf8)
                )
            )
        )

        #expect(throws: FinderNavigationError.automationDenied) {
            try service.navigateCurrentWindow(
                to: URL(fileURLWithPath: "/Users/example", isDirectory: true)
            )
        }
    }
}

private struct StubCommandRunner: StructuredCommandRunning {
    let result: StructuredCommandResult

    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?
    ) throws -> StructuredCommandResult {
        result
    }
}
