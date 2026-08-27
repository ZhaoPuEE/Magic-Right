import Foundation
import Testing
@testable import SuperRightCore

@Suite("Smart directory history")
struct DirectoryHistoryTests {
    private let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("Path normalization merges equivalent directory URLs")
    func normalizedPathIsIdentity() throws {
        let canonical = URL(fileURLWithPath: "/tmp/SuperRight/work", isDirectory: true)
        let equivalent = URL(
            fileURLWithPath: "/tmp/SuperRight/project/../work/",
            isDirectory: true
        )
        var history = DirectoryHistory()

        #expect(history.recordVisit(
            to: equivalent,
            dwellDuration: 2,
            at: referenceDate
        ) == .addedDirectory)
        #expect(history.recordVisit(
            to: canonical,
            dwellDuration: 2,
            at: referenceDate.addingTimeInterval(30 * 60)
        ) == .countedVisit)

        let entry = try #require(history.entry(for: canonical))
        #expect(history.entries.count == 1)
        #expect(entry.normalizedPath == canonical.standardizedFileURL.path)
        #expect(entry.visitCount == 2)
    }

    @Test("A visit must dwell for at least two seconds")
    func dwellThreshold() {
        let directory = URL(fileURLWithPath: "/tmp/brief", isDirectory: true)
        var history = DirectoryHistory()

        #expect(history.recordVisit(
            to: directory,
            dwellDuration: 1.999,
            at: referenceDate
        ) == .ignoredShortDwell)
        #expect(history.entries.isEmpty)

        #expect(history.recordVisit(
            to: directory,
            dwellDuration: 2,
            at: referenceDate
        ) == .addedDirectory)
        #expect(history.entry(for: directory)?.visitCount == 1)
    }

    @Test("Thirty-minute deduplication preserves frequency and refreshes recency")
    func deduplicationWindow() throws {
        let directory = URL(fileURLWithPath: "/tmp/deduplicated", isDirectory: true)
        var history = DirectoryHistory()

        history.recordVisit(to: directory, dwellDuration: 5, at: referenceDate)
        #expect(history.recordVisit(
            to: directory,
            dwellDuration: 5,
            at: referenceDate.addingTimeInterval(29 * 60)
        ) == .refreshedRecentVisit)

        var entry = try #require(history.entry(for: directory))
        #expect(entry.visitCount == 1)
        #expect(entry.lastVisitedAt == referenceDate.addingTimeInterval(29 * 60))
        #expect(entry.lastCountedVisitAt == referenceDate)

        #expect(history.recordVisit(
            to: directory,
            dwellDuration: 5,
            at: referenceDate.addingTimeInterval(30 * 60)
        ) == .countedVisit)
        entry = try #require(history.entry(for: directory))
        #expect(entry.visitCount == 2)
        #expect(entry.lastCountedVisitAt == referenceDate.addingTimeInterval(30 * 60))
    }

    @Test("Frequency score uses an exact thirty-day half-life")
    func scoreHalfLife() throws {
        let directory = URL(fileURLWithPath: "/tmp/scored", isDirectory: true)
        let entry = DirectoryHistoryEntry(
            directoryURL: directory,
            visitedAt: referenceDate
        )
        let thirtyDays = 30.0 * 24 * 60 * 60

        #expect(entry.score(at: referenceDate) == 1)
        #expect(abs(entry.score(
            at: referenceDate.addingTimeInterval(thirtyDays)
        ) - 0.5) < 0.000_000_1)
        #expect(abs(entry.score(
            at: referenceDate.addingTimeInterval(2 * thirtyDays)
        ) - 0.25) < 0.000_000_1)
    }

    @Test("A new visit does not make all old visits recent again")
    func newVisitOnlyAddsItsOwnWeight() throws {
        let directory = URL(fileURLWithPath: "/tmp/aged-frequency", isDirectory: true)
        let policy = DirectoryHistoryPolicy(deduplicationInterval: 0)
        let halfLife = policy.scoreHalfLife
        var history = DirectoryHistory(policy: policy)

        for _ in 0..<10 {
            history.recordVisit(to: directory, dwellDuration: 2, at: referenceDate)
        }

        let twoHalfLivesLater = referenceDate.addingTimeInterval(2 * halfLife)
        #expect(history.recordVisit(
            to: directory,
            dwellDuration: 2,
            at: twoHalfLivesLater
        ) == .countedVisit)

        let entry = try #require(history.entry(for: directory))
        #expect(entry.visitCount == 11)
        #expect(abs(entry.score(at: twoHalfLivesLater, halfLife: halfLife) - 3.5) < 0.000_000_1)
    }

    @Test("Legacy history migrates without reviving old visit weight")
    func legacyScoreMigration() throws {
        let directory = URL(fileURLWithPath: "/tmp/legacy-frequency", isDirectory: true)
        let policy = DirectoryHistoryPolicy(deduplicationInterval: 0)
        let halfLife = policy.scoreHalfLife
        var original = DirectoryHistory(policy: policy)
        for _ in 0..<8 {
            original.recordVisit(to: directory, dwellDuration: 2, at: referenceDate)
        }

        let encoded = try JSONEncoder().encode(original)
        var root = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var entries = try #require(root["entries"] as? [[String: Any]])
        entries[0].removeValue(forKey: "decayedVisitScore")
        entries[0].removeValue(forKey: "scoreUpdatedAt")
        root["entries"] = entries
        let legacyData = try JSONSerialization.data(withJSONObject: root)

        var decoded = try DirectoryHistory.decodeStoredData(legacyData)
        let twoHalfLivesLater = referenceDate.addingTimeInterval(2 * halfLife)
        decoded.recordVisit(to: directory, dwellDuration: 2, at: twoHalfLivesLater)

        let entry = try #require(decoded.entry(for: directory))
        #expect(entry.visitCount == 9)
        #expect(abs(entry.score(at: twoHalfLivesLater, halfLife: halfLife) - 3) < 0.000_000_1)
    }

    @Test("Stored history distinguishes absence from corrupt data")
    func storedDataDecodeIsFailClosed() throws {
        #expect(try DirectoryHistory.decodeStoredData(nil).entries.isEmpty)
        #expect(throws: DecodingError.self) {
            try DirectoryHistory.decodeStoredData(Data("not-json".utf8))
        }
    }

    @Test("Frequent directories default to the top eight")
    func frequentTopEight() {
        let policy = DirectoryHistoryPolicy(deduplicationInterval: 0)
        var history = DirectoryHistory(policy: policy)

        for index in 0..<10 {
            let url = URL(fileURLWithPath: "/tmp/frequent-\(index)", isDirectory: true)
            for visit in 0...index {
                history.recordVisit(
                    to: url,
                    dwellDuration: 2,
                    at: referenceDate.addingTimeInterval(TimeInterval(visit))
                )
            }
        }

        let frequent = history.frequentDirectories(at: referenceDate.addingTimeInterval(20))
        #expect(frequent.count == 8)
        #expect(frequent.first?.normalizedPath == "/tmp/frequent-9")
        #expect(frequent.last?.normalizedPath == "/tmp/frequent-2")
        #expect(history.entries.count == 10)
    }

    @Test("Pinned, frequent, and recent sections respect user state")
    func categorizedSections() {
        let pinned = URL(fileURLWithPath: "/tmp/pinned", isDirectory: true)
        let older = URL(fileURLWithPath: "/tmp/older", isDirectory: true)
        let newest = URL(fileURLWithPath: "/tmp/newest", isDirectory: true)
        let excluded = URL(fileURLWithPath: "/tmp/excluded", isDirectory: true)
        var history = DirectoryHistory()

        history.recordVisit(to: pinned, dwellDuration: 2, at: referenceDate)
        history.recordVisit(to: older, dwellDuration: 2, at: referenceDate.addingTimeInterval(60))
        history.recordVisit(to: newest, dwellDuration: 2, at: referenceDate.addingTimeInterval(120))
        history.recordVisit(to: excluded, dwellDuration: 2, at: referenceDate.addingTimeInterval(180))
        history.setPinned(true, for: pinned)
        history.setCustomName("  Favorite  ", for: pinned)
        history.setExcluded(true, for: excluded)

        let sections = history.sections(at: referenceDate.addingTimeInterval(180))
        #expect(sections.pinned.map(\.displayName) == ["Favorite"])
        #expect(sections.frequent.map(\.normalizedPath) == [newest.path, older.path])
        #expect(sections.recent.map(\.normalizedPath) == [newest.path, older.path])
        #expect(history.entries.count == 4)
    }

    @Test("Missing directories are hidden by an injected check but retained")
    func missingDirectoryVisibilityDoesNotDeleteHistory() {
        let present = URL(fileURLWithPath: "/tmp/present", isDirectory: true)
        let missing = URL(fileURLWithPath: "/tmp/missing", isDirectory: true)
        var history = DirectoryHistory()
        history.recordVisit(to: present, dwellDuration: 2, at: referenceDate)
        history.recordVisit(to: missing, dwellDuration: 2, at: referenceDate)

        let visible = history.recentDirectories { url in
            url.standardizedFileURL != missing.standardizedFileURL
        }

        #expect(visible.map(\.normalizedPath) == [present.path])
        #expect(history.entries.count == 2)
        #expect(history.entry(for: missing) != nil)
    }

    @Test("System, hidden, and temporary paths are learned without default filters")
    func noImplicitPathFilters() {
        let paths = [
            "/System/Library",
            "/tmp/.hidden-project",
            "/private/var/tmp/transient-project"
        ]
        var history = DirectoryHistory()

        for path in paths {
            history.recordVisit(
                to: URL(fileURLWithPath: path, isDirectory: true),
                dwellDuration: 2,
                at: referenceDate
            )
        }

        #expect(Set(history.entries.map(\.normalizedPath)) == Set(paths))
        #expect(history.recentDirectories().count == 3)
    }

    @Test("Records can be renamed, pinned, excluded, removed, and cleared")
    func recordManagement() throws {
        let first = URL(fileURLWithPath: "/tmp/first", isDirectory: true)
        let second = URL(fileURLWithPath: "/tmp/second", isDirectory: true)
        var history = DirectoryHistory()
        history.recordVisit(to: first, dwellDuration: 2, at: referenceDate)
        history.recordVisit(to: second, dwellDuration: 2, at: referenceDate)

        let didRename = history.setCustomName("Work", for: first)
        let didPin = history.setPinned(true, for: first)
        let didExclude = history.setExcluded(true, for: second)
        #expect(didRename)
        #expect(didPin)
        #expect(didExclude)
        #expect(history.entry(for: first)?.displayName == "Work")
        #expect(history.entry(for: first)?.isPinned == true)
        #expect(history.entry(for: second)?.isExcluded == true)
        let didRemove = history.remove(second)
        let didRemoveAgain = history.remove(second)
        #expect(didRemove)
        #expect(!didRemoveAgain)
        #expect(history.entries.count == 1)

        history.removeAll()
        #expect(history.entries.isEmpty)
    }

    @Test("History survives a Codable round trip")
    func codableRoundTrip() throws {
        let directory = URL(fileURLWithPath: "/tmp/persisted", isDirectory: true)
        var history = DirectoryHistory()
        history.recordVisit(to: directory, dwellDuration: 2, at: referenceDate)
        history.setCustomName("Persisted", for: directory)
        history.setPinned(true, for: directory)

        let data = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(DirectoryHistory.self, from: data)

        #expect(decoded == history)
    }
}
