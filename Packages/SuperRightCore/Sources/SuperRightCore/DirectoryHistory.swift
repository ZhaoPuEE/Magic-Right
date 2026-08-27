import Foundation

/// Tuning values for local directory learning.
///
/// The defaults implement the V1 product policy: a visit must last two
/// seconds, repeated visits within thirty minutes only refresh recency, and
/// frequency decays with a thirty-day half-life.
public struct DirectoryHistoryPolicy: Codable, Hashable, Sendable {
    public static let `default` = DirectoryHistoryPolicy()

    public let minimumDwellDuration: TimeInterval
    public let deduplicationInterval: TimeInterval
    public let scoreHalfLife: TimeInterval
    public let frequentDirectoryLimit: Int

    public init(
        minimumDwellDuration: TimeInterval = 2,
        deduplicationInterval: TimeInterval = 30 * 60,
        scoreHalfLife: TimeInterval = 30 * 24 * 60 * 60,
        frequentDirectoryLimit: Int = 8
    ) {
        self.minimumDwellDuration = max(0, minimumDwellDuration)
        self.deduplicationInterval = max(0, deduplicationInterval)
        self.scoreHalfLife = max(.leastNonzeroMagnitude, scoreHalfLife)
        self.frequentDirectoryLimit = max(0, frequentDirectoryLimit)
    }
}

/// A normalized path identity used without inspecting directory contents.
public enum DirectoryPathIdentity {
    /// Normalizes dot components and trailing separators without resolving
    /// symbolic links or changing case, both of which can change identity on
    /// case-sensitive volumes.
    public static func normalize(_ directoryURL: URL) -> String {
        directoryURL.standardizedFileURL.path
    }

    public static func normalize(_ path: String) -> String {
        let expandedPath = (path as NSString).expandingTildeInPath
        return normalize(URL(fileURLWithPath: expandedPath, isDirectory: true))
    }
}

public struct DirectoryHistoryEntry: Codable, Hashable, Identifiable, Sendable {
    /// The normalized path is the stable identity. Display names never affect
    /// identity, so renaming a menu item cannot split its history.
    public var id: String { normalizedPath }

    public let normalizedPath: String
    public private(set) var customName: String?
    public private(set) var isPinned: Bool
    public private(set) var isExcluded: Bool
    public private(set) var visitCount: Int
    public private(set) var firstVisitedAt: Date
    public private(set) var lastVisitedAt: Date
    public private(set) var lastCountedVisitAt: Date

    public init(
        directoryURL: URL,
        visitedAt: Date,
        customName: String? = nil,
        isPinned: Bool = false,
        isExcluded: Bool = false
    ) {
        normalizedPath = DirectoryPathIdentity.normalize(directoryURL)
        self.customName = Self.cleanedName(customName)
        self.isPinned = isPinned
        self.isExcluded = isExcluded
        visitCount = 1
        firstVisitedAt = visitedAt
        lastVisitedAt = visitedAt
        lastCountedVisitAt = visitedAt
    }

    public var directoryURL: URL {
        URL(fileURLWithPath: normalizedPath, isDirectory: true)
    }

    public var displayName: String {
        if let customName {
            return customName
        }

        let fallback = directoryURL.lastPathComponent
        return fallback.isEmpty ? normalizedPath : fallback
    }

    /// Frequency with exponential recency decay. A record with the same visit
    /// count has exactly half its score after one configured half-life.
    public func score(
        at date: Date,
        halfLife: TimeInterval = DirectoryHistoryPolicy.default.scoreHalfLife
    ) -> Double {
        let validHalfLife = max(.leastNonzeroMagnitude, halfLife)
        let age = max(0, date.timeIntervalSince(lastVisitedAt))
        let recencyDecay = pow(0.5, age / validHalfLife)
        return Double(visitCount) * recencyDecay
    }

    fileprivate mutating func registerVisit(
        at date: Date,
        deduplicationInterval: TimeInterval
    ) -> Bool {
        firstVisitedAt = min(firstVisitedAt, date)
        lastVisitedAt = max(lastVisitedAt, date)

        guard date.timeIntervalSince(lastCountedVisitAt) >= deduplicationInterval else {
            return false
        }

        visitCount += 1
        lastCountedVisitAt = date
        return true
    }

    fileprivate mutating func setCustomName(_ customName: String?) {
        self.customName = Self.cleanedName(customName)
    }

    fileprivate mutating func setPinned(_ isPinned: Bool) {
        self.isPinned = isPinned
    }

    fileprivate mutating func setExcluded(_ isExcluded: Bool) {
        self.isExcluded = isExcluded
    }

    private static func cleanedName(_ name: String?) -> String? {
        guard let cleaned = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cleaned.isEmpty else {
            return nil
        }
        return cleaned
    }
}

public enum DirectoryVisitResult: String, Codable, Hashable, Sendable {
    /// The visit was shorter than the configured dwell threshold. No stored
    /// state changed.
    case ignoredShortDwell
    /// The path was not previously known and now has one counted visit.
    case addedDirectory
    /// The path was counted because it was outside the deduplication window.
    case countedVisit
    /// Recency changed, while frequency remained unchanged.
    case refreshedRecentVisit
}

public struct DirectoryHistorySections: Codable, Hashable, Sendable {
    public let pinned: [DirectoryHistoryEntry]
    public let frequent: [DirectoryHistoryEntry]
    public let recent: [DirectoryHistoryEntry]

    public init(
        pinned: [DirectoryHistoryEntry],
        frequent: [DirectoryHistoryEntry],
        recent: [DirectoryHistoryEntry]
    ) {
        self.pinned = pinned
        self.frequent = frequent
        self.recent = recent
    }
}

/// Persistable, local-only history for directories observed by Finder or
/// opened through Super Right.
///
/// This type performs no file-system scan and never removes stale records on
/// its own. Callers inject a lightweight existence check when constructing a
/// visible menu.
public struct DirectoryHistory: Codable, Hashable, Sendable {
    public let policy: DirectoryHistoryPolicy
    public private(set) var entries: [DirectoryHistoryEntry]

    public init(
        entries: [DirectoryHistoryEntry] = [],
        policy: DirectoryHistoryPolicy = .default
    ) {
        self.policy = policy
        self.entries = Self.deduplicated(entries)
    }

    @discardableResult
    public mutating func recordVisit(
        to directoryURL: URL,
        dwellDuration: TimeInterval,
        at date: Date = Date()
    ) -> DirectoryVisitResult {
        guard dwellDuration >= policy.minimumDwellDuration else {
            return .ignoredShortDwell
        }

        let identity = DirectoryPathIdentity.normalize(directoryURL)
        guard let index = index(forIdentity: identity) else {
            entries.append(
                DirectoryHistoryEntry(directoryURL: directoryURL, visitedAt: date)
            )
            return .addedDirectory
        }

        let didCount = entries[index].registerVisit(
            at: date,
            deduplicationInterval: policy.deduplicationInterval
        )
        return didCount ? .countedVisit : .refreshedRecentVisit
    }

    public func entry(for directoryURL: URL) -> DirectoryHistoryEntry? {
        let identity = DirectoryPathIdentity.normalize(directoryURL)
        return entries.first { $0.normalizedPath == identity }
    }

    @discardableResult
    public mutating func setCustomName(
        _ customName: String?,
        for directoryURL: URL
    ) -> Bool {
        update(directoryURL) { $0.setCustomName(customName) }
    }

    @discardableResult
    public mutating func setPinned(
        _ isPinned: Bool,
        for directoryURL: URL
    ) -> Bool {
        update(directoryURL) { $0.setPinned(isPinned) }
    }

    @discardableResult
    public mutating func setExcluded(
        _ isExcluded: Bool,
        for directoryURL: URL
    ) -> Bool {
        update(directoryURL) { $0.setExcluded(isExcluded) }
    }

    /// Removes one normalized identity. This is the only automatic-looking
    /// API that actually deletes a record; visibility queries never do.
    @discardableResult
    public mutating func remove(_ directoryURL: URL) -> Bool {
        let identity = DirectoryPathIdentity.normalize(directoryURL)
        guard let index = index(forIdentity: identity) else { return false }
        entries.remove(at: index)
        return true
    }

    public mutating func removeAll() {
        entries.removeAll(keepingCapacity: false)
    }

    public func pinnedDirectories(
        pathExists: @Sendable (URL) -> Bool = { _ in true }
    ) -> [DirectoryHistoryEntry] {
        visibleEntries(pathExists: pathExists)
            .filter(\.isPinned)
            .sorted(by: Self.pinnedSort)
    }

    public func frequentDirectories(
        at date: Date = Date(),
        limit: Int? = nil,
        pathExists: @Sendable (URL) -> Bool = { _ in true }
    ) -> [DirectoryHistoryEntry] {
        let resolvedLimit = max(0, limit ?? policy.frequentDirectoryLimit)
        return Array(
            visibleEntries(pathExists: pathExists)
                .filter { !$0.isPinned }
                .sorted { lhs, rhs in
                    let lhsScore = lhs.score(at: date, halfLife: policy.scoreHalfLife)
                    let rhsScore = rhs.score(at: date, halfLife: policy.scoreHalfLife)
                    if lhsScore != rhsScore { return lhsScore > rhsScore }
                    if lhs.lastVisitedAt != rhs.lastVisitedAt {
                        return lhs.lastVisitedAt > rhs.lastVisitedAt
                    }
                    return lhs.normalizedPath < rhs.normalizedPath
                }
                .prefix(resolvedLimit)
        )
    }

    public func recentDirectories(
        limit: Int? = nil,
        pathExists: @Sendable (URL) -> Bool = { _ in true }
    ) -> [DirectoryHistoryEntry] {
        let sorted = visibleEntries(pathExists: pathExists)
            .filter { !$0.isPinned }
            .sorted { lhs, rhs in
                if lhs.lastVisitedAt != rhs.lastVisitedAt {
                    return lhs.lastVisitedAt > rhs.lastVisitedAt
                }
                return lhs.normalizedPath < rhs.normalizedPath
            }

        guard let limit else { return sorted }
        return Array(sorted.prefix(max(0, limit)))
    }

    public func sections(
        at date: Date = Date(),
        frequentLimit: Int? = nil,
        recentLimit: Int? = nil,
        pathExists: @Sendable (URL) -> Bool = { _ in true }
    ) -> DirectoryHistorySections {
        DirectoryHistorySections(
            pinned: pinnedDirectories(pathExists: pathExists),
            frequent: frequentDirectories(
                at: date,
                limit: frequentLimit,
                pathExists: pathExists
            ),
            recent: recentDirectories(
                limit: recentLimit,
                pathExists: pathExists
            )
        )
    }

    private func visibleEntries(
        pathExists: @Sendable (URL) -> Bool
    ) -> [DirectoryHistoryEntry] {
        entries.filter { entry in
            !entry.isExcluded && pathExists(entry.directoryURL)
        }
    }

    @discardableResult
    private mutating func update(
        _ directoryURL: URL,
        change: (inout DirectoryHistoryEntry) -> Void
    ) -> Bool {
        let identity = DirectoryPathIdentity.normalize(directoryURL)
        guard let index = index(forIdentity: identity) else { return false }
        change(&entries[index])
        return true
    }

    private func index(forIdentity identity: String) -> Int? {
        entries.firstIndex { $0.normalizedPath == identity }
    }

    private static func deduplicated(
        _ entries: [DirectoryHistoryEntry]
    ) -> [DirectoryHistoryEntry] {
        var identities = Set<String>()
        return entries.filter { identities.insert($0.normalizedPath).inserted }
    }

    private static func pinnedSort(
        _ lhs: DirectoryHistoryEntry,
        _ rhs: DirectoryHistoryEntry
    ) -> Bool {
        if lhs.displayName != rhs.displayName {
            return lhs.displayName < rhs.displayName
        }
        return lhs.normalizedPath < rhs.normalizedPath
    }
}
