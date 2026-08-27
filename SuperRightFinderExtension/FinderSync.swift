import AppKit
import FinderSync
import SuperRightCore

final class FinderSync: FIFinderSync {
    private enum Constants {
        static let hostBundleIdentifier = "dev.superright.app"
        static let appGroupSuiteName = "group.dev.superright.app"
        static let applicationPreferencesKey = "applicationPreferences.v1"
        static let directoryHistoryKey = "directoryHistory.v1"
        static let directoryLearningEnabledKey = "directoryLearningEnabled"
    }

    private var observationStartDates: [String: Date] = [:]

    override init() {
        super.init()

        // Finder Sync only supplies menus and observation callbacks inside
        // watched locations. File access is still governed by the sandbox.
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/", isDirectory: true)
        ]
    }

    override func beginObservingDirectory(at url: URL) {
        guard isDirectoryLearningEnabled else { return }
        observationStartDates[DirectoryPathIdentity.normalize(url)] = Date()
    }

    override func endObservingDirectory(at url: URL) {
        let identity = DirectoryPathIdentity.normalize(url)
        guard let startedAt = observationStartDates.removeValue(forKey: identity),
              isDirectoryLearningEnabled else { return }

        recordDirectoryVisit(
            url,
            dwellDuration: max(0, Date().timeIntervalSince(startedAt))
        )
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "Super Right")
        let rootItem = NSMenuItem(title: "Super Right", action: nil, keyEquivalent: "")
        let rootMenu = NSMenu(title: "Super Right")

        rootMenu.addItem(newFileMenuItem())
        rootMenu.addItem(directoryMenuItem())
        rootMenu.addItem(openWithMenuItem())
        rootMenu.addItem(toolsMenuItem())
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

    private func newFileMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "新建文件")

        for preset in NewFilePreset.allCases {
            let item = NSMenuItem(
                title: displayName(for: preset),
                action: #selector(createNewFile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset.rawValue
            item.image = NSImage(
                systemSymbolName: symbolName(for: preset),
                accessibilityDescription: nil
            )
            menu.addItem(item)
        }

        rootItem.submenu = menu
        return rootItem
    }

    private func directoryMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "目录", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "目录")
        let sections = loadDirectoryHistory().sections(
            recentLimit: 10,
            pathExists: directoryExists
        )

        appendDirectorySection("固定", entries: sections.pinned, to: menu)
        appendDirectorySection("常用", entries: sections.frequent, to: menu)
        appendDirectorySection("最近", entries: sections.recent, to: menu)

        if menu.items.isEmpty {
            let emptyItem = NSMenuItem(title: "尚无目录记录", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        }

        rootItem.submenu = menu
        return rootItem
    }

    private func openWithMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "打开方式", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "打开方式")
        let enabledApplications = applicationRegistry().visibleEnabledApplications()

        if enabledApplications.isEmpty {
            let emptyItem = NSMenuItem(title: "尚未启用 App", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for application in enabledApplications {
                let item = NSMenuItem(
                    title: "在 \(application.menuDisplayName) 中打开",
                    action: #selector(openSelectionInApplication(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = application.bundleIdentifier

                let icon = NSWorkspace.shared.icon(
                    forFile: application.currentApplicationURL.path
                )
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let configureItem = NSMenuItem(
            title: "配置打开方式…",
            action: #selector(openHostSettings),
            keyEquivalent: ""
        )
        configureItem.target = self
        menu.addItem(configureItem)

        rootItem.submenu = menu
        return rootItem
    }

    private func toolsMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "工具", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "工具")

        let actions: [(String, Selector)] = [
            ("复制绝对路径", #selector(copyAbsolutePaths)),
            ("复制 file:// URL", #selector(copyFileURLs)),
            ("复制 Shell 安全路径", #selector(copyShellSafePaths))
        ]
        for (title, action) in actions {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        rootItem.submenu = menu
        return rootItem
    }

    private func appendDirectorySection(
        _ title: String,
        entries: [DirectoryHistoryEntry],
        to menu: NSMenu
    ) {
        guard !entries.isEmpty else { return }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }

        let heading = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        for entry in entries {
            let item = NSMenuItem(
                title: entry.displayName,
                action: #selector(openLearnedDirectory(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = entry.normalizedPath
            item.toolTip = entry.normalizedPath
            item.image = NSImage(
                systemSymbolName: entry.isPinned ? "folder.fill" : "folder",
                accessibilityDescription: nil
            )
            menu.addItem(item)
        }
    }

    @objc private func createNewFile(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let preset = NewFilePreset(rawValue: rawValue),
              let destinationDirectory = newFileDestinationDirectory() else {
            NSSound.beep()
            return
        }

        do {
            let createdURL = try NewFileService().createFile(
                for: NewFileRequest(
                    preset: preset,
                    destinationDirectory: destinationDirectory
                )
            )
            NSWorkspace.shared.activateFileViewerSelecting([createdURL])
        } catch {
            NSSound.beep()
        }
    }

    @objc private func openLearnedDirectory(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard directoryExists(url) else { return }

        NSWorkspace.shared.open(url)
        recordDirectoryVisit(
            url,
            dwellDuration: DirectoryHistoryPolicy.default.minimumDwellDuration
        )
    }

    @objc private func copyAbsolutePaths() {
        writeToPasteboard(targetURLs().map(\.path).joined(separator: "\n"))
    }

    @objc private func copyFileURLs() {
        writeToPasteboard(
            targetURLs()
                .map(\.absoluteString)
                .joined(separator: "\n")
        )
    }

    @objc private func copyShellSafePaths() {
        writeToPasteboard(
            targetURLs()
                .map { shellQuoted($0.path) }
                .joined(separator: " ")
        )
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
              ), execute(request) else { return }

        var recordedPaths = Set<String>()
        for url in urls {
            let directoryURL = directoryContext(for: url)
            let identity = DirectoryPathIdentity.normalize(directoryURL)
            guard recordedPaths.insert(identity).inserted else { continue }
            recordDirectoryVisit(
                directoryURL,
                dwellDuration: DirectoryHistoryPolicy.default.minimumDwellDuration
            )
        }
    }

    @discardableResult
    private func execute(_ request: ApplicationOpenRequest) -> Bool {
        let locator = NSWorkspaceApplicationLocator()
        guard let application = locator.locateApplication(
            bundleIdentifier: request.applicationBundleIdentifier
        ) else { return false }

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
        return true
    }

    private var isDirectoryLearningEnabled: Bool {
        guard let defaults = UserDefaults(suiteName: Constants.appGroupSuiteName) else {
            return true
        }
        return defaults.object(
            forKey: Constants.directoryLearningEnabledKey
        ) as? Bool ?? true
    }

    private func recordDirectoryVisit(
        _ directoryURL: URL,
        dwellDuration: TimeInterval
    ) {
        guard isDirectoryLearningEnabled else { return }

        var history = loadDirectoryHistory()
        let result = history.recordVisit(
            to: directoryURL,
            dwellDuration: dwellDuration
        )
        guard result != .ignoredShortDwell,
              let data = try? JSONEncoder().encode(history),
              let defaults = UserDefaults(suiteName: Constants.appGroupSuiteName) else {
            return
        }

        defaults.set(data, forKey: Constants.directoryHistoryKey)
    }

    private func loadDirectoryHistory() -> DirectoryHistory {
        guard let defaults = UserDefaults(suiteName: Constants.appGroupSuiteName) else {
            return DirectoryHistory()
        }
        defaults.synchronize()
        guard let data = defaults.data(forKey: Constants.directoryHistoryKey),
              let history = try? JSONDecoder().decode(DirectoryHistory.self, from: data) else {
            return DirectoryHistory()
        }
        return history
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

    private func newFileDestinationDirectory() -> URL? {
        let controller = FIFinderSyncController.default()
        if let selected = controller.selectedItemURLs(), selected.count == 1,
           let selectedURL = selected.first, directoryExists(selectedURL) {
            return selectedURL
        }

        if let targetedURL = controller.targetedURL() {
            return directoryContext(for: targetedURL)
        }

        if let selectedURL = controller.selectedItemURLs()?.first {
            return directoryContext(for: selectedURL)
        }
        return nil
    }

    private func directoryContext(for url: URL) -> URL {
        if directoryExists(url) || url.hasDirectoryPath {
            return url
        }
        return url.deletingLastPathComponent()
    }

    private func writeToPasteboard(_ value: String) {
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func shellQuoted(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func displayName(for preset: NewFilePreset) -> String {
        switch preset {
        case .markdown: "Markdown (.md)"
        case .plainText: "文本 (.txt)"
        case .richText: "富文本 (.rtf)"
        case .xml: "XML"
        case .json: "JSON"
        case .yaml: "YAML"
        case .gitignore: ".gitignore"
        }
    }

    private func symbolName(for preset: NewFilePreset) -> String {
        switch preset {
        case .markdown, .plainText: "doc.plaintext"
        case .richText: "doc.richtext"
        case .xml: "chevron.left.forwardslash.chevron.right"
        case .json, .yaml: "curlybraces"
        case .gitignore: "eye.slash"
        }
    }
}

private func directoryExists(_ url: URL) -> Bool {
    var isDirectory = ObjCBool(false)
    return FileManager.default.fileExists(
        atPath: url.path,
        isDirectory: &isDirectory
    ) && isDirectory.boolValue
}
