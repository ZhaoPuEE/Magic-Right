import Foundation

public enum ApplicationOpenIntent: Hashable, Sendable {
    /// Files and/or directories selected in Finder. Ordering is preserved.
    case selection([URL])
    /// The directory represented by Finder's current context.
    case currentDirectory(URL)
    /// A repository root already resolved by the caller.
    case gitRoot(URL)
}

/// A process argument with an explicit semantic type.
///
/// These values are flattened to an argument array and must be passed directly
/// to `NSWorkspace.OpenConfiguration.arguments` (or equivalent). They must
/// never be concatenated into a shell command.
public enum StructuredLaunchArgument: Codable, Hashable, Sendable {
    case flag(String)
    case path(URL)
    case paths([URL])
    case pathOption(name: String, url: URL)

    public var argumentValues: [String] {
        switch self {
        case let .flag(value):
            [value]
        case let .path(url):
            [url.path]
        case let .paths(urls):
            urls.map(\.path)
        case let .pathOption(name, url):
            ["\(name)=\(url.path)"]
        }
    }
}

public struct OpenURLsRequest: Codable, Hashable, Sendable {
    public let applicationBundleIdentifier: String
    public let urls: [URL]

    public init(applicationBundleIdentifier: String, urls: [URL]) {
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.urls = urls
    }
}

public struct StructuredLaunchRequest: Codable, Hashable, Sendable {
    public let applicationBundleIdentifier: String
    public let arguments: [StructuredLaunchArgument]

    public init(
        applicationBundleIdentifier: String,
        arguments: [StructuredLaunchArgument]
    ) {
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.arguments = arguments
    }

    public var argumentValues: [String] {
        arguments.flatMap(\.argumentValues)
    }
}

/// An execution-neutral request. The host resolves the bundle identifier at
/// execution time and then invokes NSWorkspace with URLs or argument arrays.
public enum ApplicationOpenRequest: Codable, Hashable, Sendable {
    case openURLs(OpenURLsRequest)
    case structuredLaunch(StructuredLaunchRequest)

    public var applicationBundleIdentifier: String {
        switch self {
        case let .openURLs(request): request.applicationBundleIdentifier
        case let .structuredLaunch(request): request.applicationBundleIdentifier
        }
    }
}

public enum ApplicationOpenRequestError: Error, Equatable, Sendable {
    case emptySelection
    case invalidTabbyURL
    case unsupportedCodexTerminal
}

public enum ApplicationOpenRequestBuilder {
    public static func makeRequest(
        for application: ApplicationDescriptor,
        intent: ApplicationOpenIntent
    ) throws -> ApplicationOpenRequest {
        let urls = try urls(for: intent)

        switch application.adapterKind {
        case .tabby:
            // The URL form is delivered to Tabby's existing single instance,
            // so an already-open window receives a new local tab instead of
            // macOS creating another application window.
            let directoryURL = directoryContextURL(
                for: intent,
                firstURL: urls[0]
            )
            return .openURLs(
                OpenURLsRequest(
                    applicationBundleIdentifier: application.bundleIdentifier,
                    urls: [try tabbyURL(
                        command: "open",
                        queryItems: [
                            URLQueryItem(name: "directory", value: directoryURL.path)
                        ]
                    )]
                )
            )
        case .terminal:
            let directoryURL = directoryContextURL(
                for: intent,
                firstURL: urls[0]
            )
            return .openURLs(
                OpenURLsRequest(
                    applicationBundleIdentifier: application.bundleIdentifier,
                    urls: [directoryURL]
                )
            )
        case .ghostty:
            let directoryURL = directoryContextURL(
                for: intent,
                firstURL: urls[0]
            )
            // Ghostty's macOS application delegate handles directory file-open
            // events by creating a surface with an explicit working directory.
            // Delivering the directory URL also reuses Ghostty's running process,
            // so the new surface inherits the user's loaded theme and appearance
            // instead of starting a separate CLI-configured app instance.
            return .openURLs(
                OpenURLsRequest(
                    applicationBundleIdentifier: application.bundleIdentifier,
                    urls: [directoryURL]
                )
            )
        case .genericURLs, .zed, .visualStudioCode:
            return .openURLs(
                OpenURLsRequest(
                    applicationBundleIdentifier: application.bundleIdentifier,
                    urls: urls
                )
            )
        }
    }

    /// Builds a terminal-specific request for Codex Here.
    ///
    /// Tabby's URL handler and single-instance handoff open a new local tab. An
    /// explicit launch also makes Tabby create a window before handling the URL
    /// when its process is running without one. The tab starts the system zsh
    /// as an interactive login shell, changes directory through positional
    /// parameters, and runs the already-resolved Codex binary as its foreground
    /// child. When Codex exits or is interrupted, the tab replaces the launcher
    /// with a normal interactive login zsh in the same directory. The small zsh
    /// program is constant; Finder-controlled paths never become shell source.
    public static func makeCodexHereRequest(
        terminal: CodexHereTerminal = .defaultValue,
        codexExecutableURL: URL,
        intent: ApplicationOpenIntent
    ) throws -> ApplicationOpenRequest {
        let urls = try urls(for: intent)
        let directoryURL = directoryContextURL(
            for: intent,
            firstURL: urls[0]
        )
        switch terminal {
        case .tabby:
            let command = [
                "/bin/zsh",
                "-l",
                "-i",
                "-c",
                #"cd -- "$1" || exit 1; "$2"; exec /bin/zsh -l -i"#,
                "magic-right",
                directoryURL.path,
                codexExecutableURL.path
            ]
            let url = try tabbyURL(
                command: "run",
                queryItems: [
                    URLQueryItem(
                        name: "command",
                        value: command.map(tabbyShellQuote).joined(separator: " ")
                    )
                ]
            )
            return .structuredLaunch(
                StructuredLaunchRequest(
                    applicationBundleIdentifier: terminal.bundleIdentifier,
                    arguments: [.flag(url.absoluteString)]
                )
            )

        case .ghostty:
            return .structuredLaunch(
                StructuredLaunchRequest(
                    applicationBundleIdentifier: terminal.bundleIdentifier,
                    arguments: [
                        .pathOption(name: "--working-directory", url: directoryURL),
                        .flag("-e"),
                        .path(codexExecutableURL)
                    ]
                )
            )

        case .terminal:
            throw ApplicationOpenRequestError.unsupportedCodexTerminal
        }
    }

    private static func tabbyURL(
        command: String,
        queryItems: [URLQueryItem]
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = "tabby"
        components.host = command
        components.queryItems = queryItems
        guard let url = components.url else {
            throw ApplicationOpenRequestError.invalidTabbyURL
        }
        return url
    }

    /// Tabby's URL parser uses `shell-quote` only to recover an argv array; it
    /// does not execute this serialized value as shell source. Single-quoting
    /// each token preserves whitespace and metacharacters, including literal
    /// apostrophes, before the constant zsh program receives paths as `$1/$2`.
    private static func tabbyShellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func urls(for intent: ApplicationOpenIntent) throws -> [URL] {
        switch intent {
        case let .selection(urls):
            guard !urls.isEmpty else { throw ApplicationOpenRequestError.emptySelection }
            return urls
        case let .currentDirectory(url), let .gitRoot(url):
            return [url]
        }
    }

    /// Finder selections can be files, while terminal adapters need one
    /// directory context. Context and Git-root intents are already semantically
    /// directories; only a selected regular file is converted to its parent.
    /// No directory contents are inspected.
    private static func directoryContextURL(
        for intent: ApplicationOpenIntent,
        firstURL: URL
    ) -> URL {
        guard case .selection = intent else { return firstURL }
        if firstURL.hasDirectoryPath {
            return firstURL
        }

        if let values = try? firstURL.resourceValues(forKeys: [.isDirectoryKey]),
           values.isDirectory == true {
            return firstURL
        }
        return firstURL.deletingLastPathComponent()
    }
}
