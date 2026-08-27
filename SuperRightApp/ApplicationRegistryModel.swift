import AppKit
import Combine
import Foundation
import SuperRightCore
import UniformTypeIdentifiers

@MainActor
final class ApplicationRegistryModel: ObservableObject {
    @Published private(set) var applications: [DetectedApplication] = []
    @Published private(set) var errorMessage: String?

    private var registry: ApplicationRegistry<NSWorkspaceApplicationLocator>

    init() {
        let preferences = Self.loadPreferences()
        registry = ApplicationRegistry(
            preferences: preferences,
            locator: NSWorkspaceApplicationLocator()
        )
        scan()
    }

    func scan() {
        applications = registry.detectedApplications()
    }

    func isEnabled(_ application: DetectedApplication) -> Bool {
        registry.preferences.isEnabled(bundleIdentifier: application.bundleIdentifier)
    }

    func setEnabled(_ isEnabled: Bool, for application: DetectedApplication) {
        registry.setEnabled(isEnabled, bundleIdentifier: application.bundleIdentifier)
        persistAndRefresh()
    }

    func chooseAndAddApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择要添加到 Super Right 的 App"
        panel.prompt = "添加 App"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let applicationURL = panel.url else { return }

        do {
            try registry.addManualApplication(at: applicationURL, enabled: true)
            errorMessage = nil
            persistAndRefresh()
        } catch {
            errorMessage = "无法读取这个 App 的 Bundle 信息。"
        }
    }

    private func persistAndRefresh() {
        do {
            let data = try JSONEncoder().encode(registry.preferences)
            SharedDefaults.store.set(data, forKey: SharedDefaults.applicationPreferencesKey)
            errorMessage = nil
        } catch {
            errorMessage = "应用菜单设置保存失败。"
        }
        scan()
    }

    private static func loadPreferences() -> ApplicationPreferences {
        guard let data = SharedDefaults.store.data(
            forKey: SharedDefaults.applicationPreferencesKey
        ) else {
            return ApplicationPreferences()
        }
        return (try? JSONDecoder().decode(ApplicationPreferences.self, from: data))
            ?? ApplicationPreferences()
    }
}
