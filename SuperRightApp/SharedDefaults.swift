import Foundation
import SuperRightCore

@MainActor
enum SharedDefaults {
    static let suiteName = "group.dev.magicright.app"
    static let applicationPreferencesKey = "applicationPreferences.v1"
    static let directoryHistoryKey = "directoryHistory.v1"
    static let directoryLearningEnabledKey = "directoryLearningEnabled"
    static let toolboxConfigurationKey = "toolboxConfiguration.v1"
    static let codexHereTerminalKey = "codexHereTerminal.v1"
    static let storage = SharedStorageManager(appGroupSuiteName: suiteName)
    // SwiftUI requires a nonoptional store. Shared-data reads and mutations
    // still guard `isSharedStorageAvailable`; `.standard` is only a UI-safe
    // last resort when neither cross-process backend can be created.
    static let store = storage.defaults ?? .standard

    static var isAppGroupAvailable: Bool {
        storage.isAppGroupAvailable
    }

    static var isSharedStorageAvailable: Bool {
        storage.isAvailable
    }

    static var containerURL: URL? {
        storage.containerURL
    }

    static var directoryHistoryLockURL: URL? {
        containerURL?.appendingPathComponent(
            "directory-history.lock",
            isDirectory: false
        )
    }
}
