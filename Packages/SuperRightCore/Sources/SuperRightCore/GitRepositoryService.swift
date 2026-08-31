import Foundation

public struct GitRepositoryDescription: Equatable, Sendable {
    public let rootURL: URL
    public let selectedItemURL: URL
    public let relativePath: String
    public let origin: String
    public let openableOriginURL: URL

    public var originRemote: String { origin }
    public var normalizedRemoteWebURL: URL { openableOriginURL }

    public init(
        rootURL: URL,
        selectedItemURL: URL,
        relativePath: String,
        origin: String,
        openableOriginURL: URL
    ) {
        self.rootURL = rootURL
        self.selectedItemURL = selectedItemURL
        self.relativePath = relativePath
        self.origin = origin
        self.openableOriginURL = openableOriginURL
    }
}

public enum GitRepositoryServiceError: Error, Equatable, Sendable {
    case itemDoesNotExist(URL)
    case repositoryNotFound(URL)
    case selectedItemOutsideRepository(item: URL, repositoryRoot: URL)
    case originNotConfigured(URL)
    case unsupportedOrigin(String)
    case commandCouldNotRun
    case invalidCommandOutput
}

/// Finds Git context without passing Finder paths through a shell.
public struct GitRepositoryService: Sendable {
    private static let gitExecutableURL = URL(fileURLWithPath: "/usr/bin/git")

    private let commandRunner: any StructuredCommandRunning

    public init() {
        commandRunner = LocalStructuredCommandRunner()
    }

    init(commandRunner: any StructuredCommandRunning) {
        self.commandRunner = commandRunner
    }

    /// Performs the lightweight check used while Finder is constructing a
    /// context menu. Path strings are used deliberately: comparing parent
    /// `URL` values can trigger resource resolution inside a sandboxed Finder
    /// extension and, for inaccessible file-reference URLs, may never reach a
    /// stable root value.
    public static func containsGitMetadata(
        atOrAbove directoryURL: URL,
        fileExists: (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        }
    ) -> Bool {
        guard directoryURL.isFileURL else { return false }
        var candidatePath = (
            resolvedStandardizedFileURL(directoryURL).path as NSString
        )
            .standardizingPath
        guard candidatePath.hasPrefix("/") else { return false }

        while true {
            let markerPath = (candidatePath as NSString)
                .appendingPathComponent(".git")
            if fileExists(markerPath) {
                return true
            }

            let parentPath = (candidatePath as NSString)
                .deletingLastPathComponent
            guard !parentPath.isEmpty, parentPath != candidatePath else {
                return false
            }
            candidatePath = parentPath
        }
    }

    public func repositoryRoot(containing itemURL: URL) throws -> URL {
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(
            atPath: itemURL.path,
            isDirectory: &isDirectory
        ) else {
            throw GitRepositoryServiceError.itemDoesNotExist(itemURL)
        }
        let resolvedItemURL = Self.resolvedStandardizedFileURL(itemURL)
        let workingDirectory = isDirectory.boolValue
            ? resolvedItemURL
            : resolvedItemURL.deletingLastPathComponent().standardizedFileURL

        let result: StructuredCommandResult
        do {
            result = try commandRunner.run(
                executableURL: Self.gitExecutableURL,
                arguments: [
                    "-C",
                    workingDirectory.path,
                    "rev-parse",
                    "--show-toplevel"
                ],
                currentDirectoryURL: nil
            )
        } catch {
            throw GitRepositoryServiceError.commandCouldNotRun
        }
        guard result.terminationStatus == 0 else {
            throw GitRepositoryServiceError.repositoryNotFound(itemURL)
        }
        guard let output = String(data: result.standardOutput, encoding: .utf8) else {
            throw GitRepositoryServiceError.invalidCommandOutput
        }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw GitRepositoryServiceError.invalidCommandOutput
        }
        return Self.resolvedStandardizedFileURL(
            URL(fileURLWithPath: path, isDirectory: true)
        )
    }

    public func relativePath(of itemURL: URL, in repositoryRoot: URL) throws -> String {
        let itemComponents = Self.resolvedStandardizedFileURL(itemURL).pathComponents
        let rootComponents = Self.resolvedStandardizedFileURL(repositoryRoot).pathComponents
        guard itemComponents.count >= rootComponents.count,
              itemComponents.prefix(rootComponents.count)
                .elementsEqual(rootComponents) else {
            throw GitRepositoryServiceError.selectedItemOutsideRepository(
                item: itemURL,
                repositoryRoot: repositoryRoot
            )
        }
        let relativeComponents = itemComponents.dropFirst(rootComponents.count)
        return relativeComponents.isEmpty ? "." : relativeComponents.joined(separator: "/")
    }

    private static func resolvedStandardizedFileURL(_ url: URL) -> URL {
        url.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    public func origin(forRepositoryAt repositoryRoot: URL) throws -> String {
        let result: StructuredCommandResult
        do {
            result = try commandRunner.run(
                executableURL: Self.gitExecutableURL,
                arguments: [
                    "-C",
                    repositoryRoot.standardizedFileURL.path,
                    "config",
                    "--get",
                    "remote.origin.url"
                ],
                currentDirectoryURL: nil
            )
        } catch {
            throw GitRepositoryServiceError.commandCouldNotRun
        }
        guard result.terminationStatus == 0 else {
            throw GitRepositoryServiceError.originNotConfigured(repositoryRoot)
        }
        guard let output = String(data: result.standardOutput, encoding: .utf8) else {
            throw GitRepositoryServiceError.invalidCommandOutput
        }
        let origin = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !origin.isEmpty else {
            throw GitRepositoryServiceError.originNotConfigured(repositoryRoot)
        }
        return origin
    }

    public func openableOriginURL(for origin: String) throws -> URL {
        guard let result = Self.normalizedOpenableOriginURL(for: origin) else {
            throw GitRepositoryServiceError.unsupportedOrigin(origin)
        }
        return result
    }

    public func describe(itemAt itemURL: URL) throws -> GitRepositoryDescription {
        let rootURL = try repositoryRoot(containing: itemURL)
        let origin = try origin(forRepositoryAt: rootURL)
        return GitRepositoryDescription(
            rootURL: rootURL,
            selectedItemURL: itemURL,
            relativePath: try relativePath(of: itemURL, in: rootURL),
            origin: origin,
            openableOriginURL: try openableOriginURL(for: origin)
        )
    }

    public func repository(for itemURL: URL) throws -> GitRepositoryDescription {
        try describe(itemAt: itemURL)
    }

    public func relativePath(for itemURL: URL) throws -> String {
        let rootURL = try repositoryRoot(containing: itemURL)
        return try relativePath(of: itemURL, in: rootURL)
    }

    /// Converts common HTTPS, SSH, SCP-style, and git origins into a browser
    /// URL. Credentials, query strings, fragments, and a trailing `.git` are
    /// removed from the result.
    public static func normalizedOpenableOriginURL(for origin: String) -> URL? {
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let scpParts = scpStyleOriginParts(trimmed) {
            return makeWebURL(host: scpParts.host, path: scpParts.path, port: nil)
        }

        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty else {
            return nil
        }
        switch scheme {
        case "http", "https":
            components.scheme = scheme
            components.user = nil
            components.password = nil
            components.query = nil
            components.fragment = nil
            components.path = normalizedRepositoryPath(components.path)
            guard !components.path.isEmpty else { return nil }
            return components.url
        case "ssh", "git":
            return makeWebURL(host: host, path: components.path, port: nil)
        default:
            return nil
        }
    }

    private static func scpStyleOriginParts(
        _ origin: String
    ) -> (host: String, path: String)? {
        guard !origin.contains("://"),
              let colonIndex = origin.firstIndex(of: ":") else {
            return nil
        }
        let authority = String(origin[..<colonIndex])
        let path = String(origin[origin.index(after: colonIndex)...])
        guard !authority.isEmpty,
              !path.isEmpty,
              !authority.contains("/"),
              !authority.contains("\\") else {
            return nil
        }
        let host = authority.split(separator: "@").last.map(String.init) ?? ""
        guard !host.isEmpty,
              !host.contains(where: { $0.isWhitespace }) else {
            return nil
        }
        if authority.count == 1, authority.first?.isLetter == true {
            return nil
        }
        return (host, path)
    }

    private static func makeWebURL(
        host: String,
        path: String,
        port: Int?
    ) -> URL? {
        let normalizedPath = normalizedRepositoryPath(path)
        guard !normalizedPath.isEmpty else { return nil }
        if host.lowercased() == "ssh.dev.azure.com" {
            let pathParts = normalizedPath
                .split(separator: "/")
                .map(String.init)
            if pathParts.count == 4, pathParts[0].lowercased() == "v3" {
                var azureComponents = URLComponents()
                azureComponents.scheme = "https"
                azureComponents.host = "dev.azure.com"
                azureComponents.path = "/\(pathParts[1])/\(pathParts[2])/_git/\(pathParts[3])"
                return azureComponents.url
            }
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = port
        components.path = normalizedPath
        return components.url
    }

    private static func normalizedRepositoryPath(_ path: String) -> String {
        var result = path
        while result.hasSuffix("/") {
            result.removeLast()
        }
        if result.lowercased().hasSuffix(".git") {
            result.removeLast(4)
        }
        while result.hasPrefix("/") {
            result.removeFirst()
        }
        return result.isEmpty ? "" : "/" + result
    }
}
