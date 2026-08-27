import AppKit
import Combine
import Foundation
import SuperRightCore

@MainActor
final class DirectoryHistoryModel: ObservableObject {
    @Published private(set) var history: DirectoryHistory
    @Published private(set) var errorMessage: String?

    init() {
        history = Self.loadHistory()
    }

    var sections: DirectoryHistorySections {
        history.sections(
            recentLimit: 10,
            pathExists: Self.pathExists
        )
    }

    var excludedEntries: [DirectoryHistoryEntry] {
        history.entries
            .filter(\.isExcluded)
            .sorted { lhs, rhs in
                if lhs.lastVisitedAt != rhs.lastVisitedAt {
                    return lhs.lastVisitedAt > rhs.lastVisitedAt
                }
                return lhs.normalizedPath < rhs.normalizedPath
            }
    }

    func reload() {
        SharedDefaults.store.synchronize()
        history = Self.loadHistory()
    }

    func openInFinder(_ entry: DirectoryHistoryEntry) {
        let url = entry.directoryURL
        guard Self.pathExists(url) else {
            errorMessage = "目录不存在，历史记录已保留。"
            return
        }

        NSWorkspace.shared.open(url)
        recordVisit(to: url)
    }

    func recordVisit(to directoryURL: URL) {
        guard learningEnabled else { return }
        reload()
        history.recordVisit(
            to: directoryURL,
            dwellDuration: history.policy.minimumDwellDuration
        )
        persist()
    }

    func togglePinned(_ entry: DirectoryHistoryEntry) {
        reload()
        let isCurrentlyPinned = history.entry(for: entry.directoryURL)?.isPinned
            ?? entry.isPinned
        history.setPinned(!isCurrentlyPinned, for: entry.directoryURL)
        persist()
    }

    func setExcluded(_ isExcluded: Bool, entry: DirectoryHistoryEntry) {
        reload()
        history.setExcluded(isExcluded, for: entry.directoryURL)
        persist()
    }

    func setCustomName(_ customName: String?, entry: DirectoryHistoryEntry) {
        reload()
        history.setCustomName(customName, for: entry.directoryURL)
        persist()
    }

    func remove(_ entry: DirectoryHistoryEntry) {
        reload()
        history.remove(entry.directoryURL)
        persist()
    }

    func removeAll() {
        reload()
        history.removeAll()
        persist()
    }

    private var learningEnabled: Bool {
        SharedDefaults.store.object(
            forKey: SharedDefaults.directoryLearningEnabledKey
        ) as? Bool ?? true
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(history)
            SharedDefaults.store.set(data, forKey: SharedDefaults.directoryHistoryKey)
            errorMessage = nil
        } catch {
            errorMessage = "目录历史保存失败。"
        }
    }

    private static func loadHistory() -> DirectoryHistory {
        guard let data = SharedDefaults.store.data(
            forKey: SharedDefaults.directoryHistoryKey
        ) else {
            return DirectoryHistory()
        }
        return (try? JSONDecoder().decode(DirectoryHistory.self, from: data))
            ?? DirectoryHistory()
    }

    nonisolated private static func pathExists(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}
