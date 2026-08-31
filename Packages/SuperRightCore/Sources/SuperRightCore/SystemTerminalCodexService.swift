import Foundation

public enum SystemTerminalCodexError: Error, Equatable, LocalizedError, Sendable {
    case automationDenied
    case invalidFileURL
    case launchFailed

    public var errorDescription: String? {
        switch self {
        case .automationDenied:
            "Magic Right 没有控制系统终端的权限。请在系统设置的“隐私与安全性 > 自动化”中允许一次。"
        case .invalidFileURL:
            "Codex Here 的目录或 Codex 可执行文件无效。"
        case .launchFailed:
            "无法在系统终端中启动 Codex。"
        }
    }
}

public struct SystemTerminalCodexService: Sendable {
    private let commandRunner: any StructuredCommandRunning

    public init() {
        commandRunner = LocalStructuredCommandRunner()
    }

    init(commandRunner: any StructuredCommandRunning) {
        self.commandRunner = commandRunner
    }

    public func launch(
        directoryURL: URL,
        codexExecutableURL: URL
    ) throws {
        guard directoryURL.isFileURL,
              codexExecutableURL.isFileURL,
              directoryURL.path.hasPrefix("/"),
              codexExecutableURL.path.hasPrefix("/") else {
            throw SystemTerminalCodexError.invalidFileURL
        }

        let result = try commandRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: Self.commandArguments(
                directoryPath: directoryURL.path,
                codexExecutablePath: codexExecutableURL.path
            ),
            currentDirectoryURL: nil
        )
        guard result.terminationStatus == 0 else {
            let standardError = String(
                data: result.standardError,
                encoding: .utf8
            ) ?? ""
            if standardError.contains("-1743")
                || standardError.localizedCaseInsensitiveContains("not authorized") {
                throw SystemTerminalCodexError.automationDenied
            }
            throw SystemTerminalCodexError.launchFailed
        }
    }

    static func commandArguments(
        directoryPath: String,
        codexExecutablePath: String
    ) -> [String] {
        [
            "-l", "AppleScript",
            "-e", "on run argv",
            "-e", "set workingDirectory to item 1 of argv",
            "-e", "set codexExecutable to item 2 of argv",
            "-e", "set commandText to \"cd -- \" & quoted form of workingDirectory & \" && exec \" & quoted form of codexExecutable",
            "-e", "tell application \"Terminal\"",
            "-e", "if (count windows) is 0 then",
            "-e", "do script commandText",
            "-e", "else",
            "-e", "do script commandText in front window",
            "-e", "end if",
            "-e", "activate",
            "-e", "end tell",
            "-e", "end run",
            directoryPath,
            codexExecutablePath
        ]
    }
}
