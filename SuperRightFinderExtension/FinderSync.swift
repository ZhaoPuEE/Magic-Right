import AppKit
import FinderSync
import SuperRightCore

final class FinderSync: FIFinderSync {
    private enum Constants {
        static let hostBundleIdentifier = "dev.superright.app"
        static let appGroupSuiteName = "group.dev.superright.app"
        static let applicationPreferencesKey = "applicationPreferences.v1"
    }

    override init() {
        super.init()

        // Finder Sync only supplies menus inside observed locations. Watching the
        // file-system root makes the menu available for normal Finder locations;
        // actual access remains governed by the sandbox and user permissions.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "Super Right")
        let rootItem = NSMenuItem(title: "Super Right", action: nil, keyEquivalent: "")
        let rootMenu = NSMenu(title: "Super Right")

        let openWithItem = NSMenuItem(title: "打开方式", action: nil, keyEquivalent: "")
        let openWithMenu = NSMenu(title: "打开方式")
        let enabledApplications = applicationRegistry().visibleEnabledApplications()
        if enabledApplications.isEmpty {
            let emptyItem = NSMenuItem(title: "尚未启用 App", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            openWithMenu.addItem(emptyItem)
        } else {
            for application in enabledApplications {
                let item = NSMenuItem(
                    title: "在 \(application.menuDisplayName) 中打开",
                    action: #selector(openSelectionInApplication(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = application.bundleIdentifier
                let icon = NSWorkspace.shared.icon(forFile: application.currentApplicationURL.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                openWithMenu.addItem(item)
            }
            openWithMenu.addItem(.separator())
        }

        let configureItem = NSMenuItem(
            title: "配置打开方式…",
            action: #selector(openHostSettings),
            keyEquivalent: ""
        )
        configureItem.target = self
        openWithMenu.addItem(configureItem)
        openWithItem.submenu = openWithMenu
        rootMenu.addItem(openWithItem)

        let copyPathItem = NSMenuItem(
            title: "复制绝对路径",
            action: #selector(copyAbsolutePaths),
            keyEquivalent: ""
        )
        copyPathItem.target = self
        rootMenu.addItem(copyPathItem)

        rootMenu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(openHostSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        rootMenu.addItem(settingsItem)

        rootItem.submenu = rootMenu
        menu.addItem(rootItem)
        return menu
    }

    @objc private func copyAbsolutePaths() {
        let paths = targetURLs().map(\.path)
        guard !paths.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }

    @objc private func openHostSettings() {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Constants.hostBundleIdentifier
        ) else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration,
            completionHandler: nil
        )
    }

    @objc private func openSelectionInApplication(_ sender: NSMenuItem) {
        guard let bundleIdentifier = sender.representedObject as? String else { return }

        let registry = applicationRegistry()
        guard let descriptor = registry.descriptor(
            forBundleIdentifier: bundleIdentifier
        ) else { return }

        let urls = targetURLs()
        guard !urls.isEmpty,
              let request = try? ApplicationOpenRequestBuilder.makeRequest(
                for: descriptor,
                intent: .selection(urls)
              ) else { return }

        execute(request)
    }

    private func execute(_ request: ApplicationOpenRequest) {
        let locator = NSWorkspaceApplicationLocator()
        guard let application = locator.locateApplication(
            bundleIdentifier: request.applicationBundleIdentifier
        ) else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        switch request {
        case let .openURLs(openRequest):
            NSWorkspace.shared.open(
                openRequest.urls,
                withApplicationAt: application.applicationURL,
                configuration: configuration,
                completionHandler: nil
            )
        case let .structuredLaunch(launchRequest):
            configuration.arguments = launchRequest.argumentValues
            NSWorkspace.shared.openApplication(
                at: application.applicationURL,
                configuration: configuration,
                completionHandler: nil
            )
        }
    }

    private func applicationRegistry() -> ApplicationRegistry<NSWorkspaceApplicationLocator> {
        let preferences: ApplicationPreferences
        if let data = UserDefaults(suiteName: Constants.appGroupSuiteName)?.data(
            forKey: Constants.applicationPreferencesKey
        ), let decoded = try? JSONDecoder().decode(ApplicationPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = ApplicationPreferences()
        }

        return ApplicationRegistry(
            preferences: preferences,
            locator: NSWorkspaceApplicationLocator()
        )
    }

    private func targetURLs() -> [URL] {
        let controller = FIFinderSyncController.default()
        if let selectedURLs = controller.selectedItemURLs(), !selectedURLs.isEmpty {
            return selectedURLs
        }
        if let targetedURL = controller.targetedURL() {
            return [targetedURL]
        }
        return []
    }
}
