import Foundation

public enum FinderNavigationError: Error, Equatable, LocalizedError, Sendable {
    case automationDenied
    case invalidDirectoryURL
    case navigationFailed

    public var errorDescription: String? {
        switch self {
        case .automationDenied:
            "Magic Right 没有控制 Finder 的权限。请在系统设置的“隐私与安全性 > 自动化”中允许一次。"
        case .invalidDirectoryURL:
            "Finder 跳转目标不是有效的本地目录。"
        case .navigationFailed:
            "Finder 无法转到目标目录。"
        }
    }
}

/// Changes the target of Finder's current front window without interpolating
/// Finder-controlled paths into AppleScript source. macOS attributes the one-
/// time Automation consent to the responsible Magic Right host process.
public struct FinderNavigationService: Sendable {
    private let commandRunner: any StructuredCommandRunning

    public init() {
        commandRunner = LocalStructuredCommandRunner()
    }

    init(commandRunner: any StructuredCommandRunning) {
        self.commandRunner = commandRunner
    }

    public func navigateCurrentWindow(to directoryURL: URL) throws {
        guard directoryURL.isFileURL, directoryURL.path.hasPrefix("/") else {
            throw FinderNavigationError.invalidDirectoryURL
        }

        let result = try commandRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: Self.commandArguments(directoryPath: directoryURL.path),
            currentDirectoryURL: nil
        )
        guard result.terminationStatus == 0 else {
            let standardError = String(
                data: result.standardError,
                encoding: .utf8
            ) ?? ""
            if standardError.contains("-1743")
                || standardError.localizedCaseInsensitiveContains("not authorized") {
                throw FinderNavigationError.automationDenied
            }
            throw FinderNavigationError.navigationFailed
        }
    }

    static func commandArguments(directoryPath: String) -> [String] {
        [
            "-l", "AppleScript",
            "-e", "on run argv",
            "-e", "set destinationPath to item 1 of argv",
            "-e", "tell application \"Finder\"",
            "-e", "if (count windows) is 0 then",
            "-e", "make new Finder window",
            "-e", "end if",
            "-e", "set target of front window to POSIX file destinationPath",
            "-e", "end tell",
            "-e", "end run",
            directoryPath
        ]
    }
}
