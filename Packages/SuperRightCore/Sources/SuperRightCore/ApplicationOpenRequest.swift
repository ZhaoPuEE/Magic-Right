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

    public var argumentValues: [String] {
        switch self {
        case let .flag(value):
            [value]
        case let .path(url):
            [url.path]
        case let .paths(urls):
            urls.map(\.path)
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
}

public enum ApplicationOpenRequestBuilder {
    public static func makeRequest(
        for application: ApplicationDescriptor,
        intent: ApplicationOpenIntent
    ) throws -> ApplicationOpenRequest {
        let urls = try urls(for: intent)

        switch application.adapterKind {
        case .tabby:
            // Tabby uses one directory context and accepts it as a structured
            // argument pair: --directory <path>.
            let directoryURL = directoryContextURL(
                for: intent,
                firstURL: urls[0]
            )
            return .structuredLaunch(
                StructuredLaunchRequest(
                    applicationBundleIdentifier: application.bundleIdentifier,
                    arguments: [.flag("--directory"), .path(directoryURL)]
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
        case .genericURLs, .zed, .visualStudioCode:
            return .openURLs(
                OpenURLsRequest(
                    applicationBundleIdentifier: application.bundleIdentifier,
                    urls: urls
                )
            )
        }
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
