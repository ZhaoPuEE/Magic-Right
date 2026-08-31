import AppKit
import Combine
import Foundation
import SuperRightCore
import UniformTypeIdentifiers

@MainActor
final class ApplicationRegistryModel: ObservableObject {
    @Published private(set) var applications: [DetectedApplication] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastScanMessage: String?

    private var registry: ApplicationRegistry<NSWorkspaceApplicationLocator>

    init() {
        let preferences = SharedDefaults.isSharedStorageAvailable
            ? Self.loadPreferences()
            : ApplicationPreferences()
        registry = ApplicationRegistry(
            preferences: preferences,
            locator: NSWorkspaceApplicationLocator()
        )
        if !SharedDefaults.isSharedStorageAvailable {
            errorMessage = "共享存储不可用，应用动作设置无法与 Finder 同步。"
        }
        scan()
    }

    func scan(userInitiated: Bool = false) {
        // Rebuild the Launch Services-backed locator instead of only assigning
        // the current list again. This makes the button a real rescan after an
        // application is installed, removed, or moved.
        registry = ApplicationRegistry(
            catalog: registry.catalog,
            preferences: registry.preferences,
            locator: NSWorkspaceApplicationLocator()
        )
        applications = registry.detectedApplications()
        if userInitiated {
            let timestamp = Date.now.formatted(date: .omitted, time: .standard)
            lastScanMessage = "扫描完成 · \(timestamp) · 发现 \(applications.count) 个预置或已添加 App"
        }
    }

    func isEnabled(_ application: DetectedApplication) -> Bool {
        registry.preferences.isEnabled(bundleIdentifier: application.bundleIdentifier)
    }

    func setEnabled(_ isEnabled: Bool, for application: DetectedApplication) {
        guard ensureAppGroupAvailable() else { return }
        registry.setEnabled(isEnabled, bundleIdentifier: application.bundleIdentifier)
        persistAndRefresh()
    }

    func chooseAndAddApplication() {
        guard ensureAppGroupAvailable() else { return }
        let panel = NSOpenPanel()
        panel.title = "选择要添加到 Magic Right 的 App"
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
        guard SharedDefaults.isSharedStorageAvailable else {
            errorMessage = "共享存储不可用，应用动作设置没有保存。"
            scan()
            return
        }
        do {
            let data = try JSONEncoder().encode(registry.preferences)
            SharedDefaults.store.set(data, forKey: SharedDefaults.applicationPreferencesKey)
            SharedDefaults.store.synchronize()
            errorMessage = nil
        } catch {
            errorMessage = "应用菜单设置保存失败。"
        }
        scan()
    }

    private func ensureAppGroupAvailable() -> Bool {
        guard SharedDefaults.isSharedStorageAvailable else {
            errorMessage = "共享存储不可用，应用动作设置没有保存。"
            return false
        }
        return true
    }

    private static func loadPreferences() -> ApplicationPreferences {
        guard let data = SharedDefaults.store.data(
            forKey: SharedDefaults.applicationPreferencesKey
        ) else {
            return .developerDefaults
        }
        guard let decoded = try? JSONDecoder().decode(
            ApplicationPreferences.self,
            from: data
        ) else {
            return ApplicationPreferences()
        }
        return decoded.addingMissingDeveloperDefaults()
    }
}
