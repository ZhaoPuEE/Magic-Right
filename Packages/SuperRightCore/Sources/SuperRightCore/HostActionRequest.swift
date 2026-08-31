import Foundation

public enum HostAction: Codable, Hashable, Sendable {
    case archive(sourceURLs: [URL], destinationDirectory: URL)
    case codexHere(
        directoryURL: URL,
        codexExecutableURL: URL,
        terminal: CodexHereTerminal
    )
    case copyGitRelativePaths(itemURLs: [URL])
    case copyOriginURL(itemURL: URL)
    case extract(archiveURLs: [URL])
    case navigateFinder(directoryURL: URL)
    case openGitRoot(itemURL: URL)
    case openGitRootInEditor(itemURL: URL)
    case openOrigin(itemURL: URL)
}

public struct HostActionRequest: Codable, Hashable, Identifiable, Sendable {
    public static let storageKeyPrefix = "hostActionRequest.v1."

    public let id: UUID
    public let createdAt: Date
    public let action: HostAction

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        action: HostAction
    ) {
        self.id = id
        self.createdAt = createdAt
        self.action = action
    }

    public var storageKey: String {
        Self.storageKey(for: id)
    }

    public static func storageKey(for id: UUID) -> String {
        storageKeyPrefix + id.uuidString.lowercased()
    }

    public func isFresh(
        at date: Date = Date(),
        maximumAge: TimeInterval = 60
    ) -> Bool {
        let age = date.timeIntervalSince(createdAt)
        return age >= -5 && age <= maximumAge
    }
}
