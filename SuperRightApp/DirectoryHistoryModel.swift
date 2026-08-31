import AppKit
import Combine
import Foundation
import SuperRightCore

@MainActor
final class DirectoryHistoryModel: ObservableObject {
    @Published private(set) var history: DirectoryHistory
    @Published private(set) var errorMessage: String?

    init() {
        history = DirectoryHistory()
        if !SharedDefaults.isSharedStorageAvailable {
            errorMessage = "共享存储不可用，目录记录无法与 Finder 同步。"
            return
        }

        do {
            history = try Self.loadHistory()
        } catch {
            errorMessage = Self.corruptHistoryMessage
        }
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
        guard SharedDefaults.isSharedStorageAvailable else {
            errorMessage = "共享存储不可用，目录记录无法与 Finder 同步。"
            return
        }
        guard let lockURL = SharedDefaults.directoryHistoryLockURL else { return }
        do {
            try CrossProcessFileLock.withLock(at: lockURL) {
                SharedDefaults.store.synchronize()
                history = try Self.loadHistory()
            }
            errorMessage = nil
        } catch is DecodingError {
            errorMessage = Self.corruptHistoryMessage
        } catch {
            errorMessage = "目录记录正忙，请稍后再试。"
        }
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
        guard ensureAppGroupAvailable(), learningEnabled else { return }
        mutateHistory { latest in
            latest.recordVisit(
                to: directoryURL,
                dwellDuration: latest.policy.minimumDwellDuration
            )
        }
    }

    func togglePinned(_ entry: DirectoryHistoryEntry) {
        guard ensureAppGroupAvailable() else { return }
        mutateHistory { latest in
            let isCurrentlyPinned = latest.entry(for: entry.directoryURL)?.isPinned
                ?? entry.isPinned
            latest.setPinned(!isCurrentlyPinned, for: entry.directoryURL)
        }
    }

    func setExcluded(_ isExcluded: Bool, entry: DirectoryHistoryEntry) {
        guard ensureAppGroupAvailable() else { return }
        mutateHistory { $0.setExcluded(isExcluded, for: entry.directoryURL) }
    }

    func setCustomName(_ customName: String?, entry: DirectoryHistoryEntry) {
        guard ensureAppGroupAvailable() else { return }
        mutateHistory { $0.setCustomName(customName, for: entry.directoryURL) }
    }

    func remove(_ entry: DirectoryHistoryEntry) {
        guard ensureAppGroupAvailable() else { return }
        mutateHistory { $0.remove(entry.directoryURL) }
    }

    func removeAll() {
        guard ensureAppGroupAvailable() else { return }
        mutateHistory { $0.removeAll() }
    }

    private var learningEnabled: Bool {
        guard SharedDefaults.isSharedStorageAvailable else { return false }
        return SharedDefaults.store.object(
            forKey: SharedDefaults.directoryLearningEnabledKey
        ) as? Bool ?? true
    }

    private func ensureAppGroupAvailable() -> Bool {
        guard SharedDefaults.isSharedStorageAvailable else {
            errorMessage = "共享存储不可用，目录记录没有保存。"
            return false
        }
        return true
    }

    private func mutateHistory(_ change: (inout DirectoryHistory) -> Void) {
        guard let lockURL = SharedDefaults.directoryHistoryLockURL else {
            errorMessage = "共享存储不可用，目录记录没有保存。"
            return
        }
        do {
            try CrossProcessFileLock.withLock(at: lockURL) {
                SharedDefaults.store.synchronize()
                var latest = try Self.loadHistory()
                change(&latest)
                let data = try JSONEncoder().encode(latest)
                SharedDefaults.store.set(data, forKey: SharedDefaults.directoryHistoryKey)
                SharedDefaults.store.synchronize()
                history = latest
            }
            errorMessage = nil
        } catch is DecodingError {
            errorMessage = Self.corruptHistoryMessage
        } catch {
            errorMessage = "目录历史保存失败，请稍后重试。"
        }
    }

    private static let corruptHistoryMessage =
        "目录历史数据无法读取；原始数据已保留，历史写入已暂停。"

    private static func loadHistory() throws -> DirectoryHistory {
        try DirectoryHistory.decodeStoredData(
            SharedDefaults.store.data(forKey: SharedDefaults.directoryHistoryKey)
        )
    }

    nonisolated private static func pathExists(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}
