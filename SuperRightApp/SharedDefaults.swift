import Foundation

@MainActor
enum SharedDefaults {
    static let suiteName = "group.dev.magicright.app"
    static let applicationPreferencesKey = "applicationPreferences.v1"
    static let directoryHistoryKey = "directoryHistory.v1"
    static let directoryLearningEnabledKey = "directoryLearningEnabled"
    static let toolboxConfigurationKey = "toolboxConfiguration.v1"
    static let appGroupStore = UserDefaults(suiteName: suiteName)
    // SwiftUI requires a nonoptional store. Shared-data reads and mutations
    // still guard `isAppGroupAvailable`; this fallback is never treated as a
    // successful cross-process save.
    static let store = appGroupStore ?? .standard

    static var isAppGroupAvailable: Bool {
        appGroupStore != nil && appGroupContainerURL != nil
    }

    static var appGroupContainerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: suiteName
        )
    }

    static var directoryHistoryLockURL: URL? {
        appGroupContainerURL?.appendingPathComponent(
            "directory-history.lock",
            isDirectory: false
        )
    }
}
