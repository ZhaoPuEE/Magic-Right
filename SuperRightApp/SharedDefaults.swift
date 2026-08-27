import Foundation

@MainActor
enum SharedDefaults {
    static let suiteName = "group.dev.superright.app"
    static let applicationPreferencesKey = "applicationPreferences.v1"
    static let directoryHistoryKey = "directoryHistory.v1"
    static let directoryLearningEnabledKey = "directoryLearningEnabled"
    static let store = UserDefaults(suiteName: suiteName) ?? .standard
}
