import Foundation

@MainActor
enum SharedDefaults {
    static let suiteName = "group.dev.superright.app"
    static let applicationPreferencesKey = "applicationPreferences.v1"
    static let store = UserDefaults(suiteName: suiteName) ?? .standard
}
