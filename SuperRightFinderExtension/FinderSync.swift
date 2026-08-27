import AppKit
import FinderSync
import OSLog
import SuperRightCore

final class FinderSync: FIFinderSync {
    private enum Constants {
        static let hostBundleIdentifier = "dev.magicright.app"
        static let appGroupSuiteName = "group.dev.magicright.app"
        static let applicationPreferencesKey = "applicationPreferences.v1"
        static let directoryHistoryKey = "directoryHistory.v1"
        static let directoryLearningEnabledKey = "directoryLearningEnabled"
        static let toolboxConfigurationKey = "toolboxConfiguration.v1"
    }

    private var observationStartDates: [String: Date] = [:]
    private let observationLock = NSLock()
    private let historyLogger = Logger(
        subsystem: Constants.hostBundleIdentifier,
        category: "DirectoryHistory"
    )

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
        observationLock.lock()
        observationStartDates[DirectoryPathIdentity.normalize(url)] = Date()
        observationLock.unlock()
    }

    override func endObservingDirectory(at url: URL) {
        let identity = DirectoryPathIdentity.normalize(url)
        observationLock.lock()
        let startedAt = observationStartDates.removeValue(forKey: identity)
        observationLock.unlock()
        guard let startedAt,
              isDirectoryLearningEnabled else { return }

        recordDirectoryVisit(
            url,
            dwellDuration: max(0, Date().timeIntervalSince(startedAt))
        )
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "Magic Right")
        let rootItem = NSMenuItem(title: "Magic Right", action: nil, keyEquivalent: "")
        let rootMenu = NSMenu(title: "Magic Right")
        let configuration = loadToolboxConfiguration()

        let availableMenuItems = [
            newFileMenuItem(configuration: configuration),
            directoryMenuItem(configuration: configuration),
            openWithMenuItem(configuration: configuration),
            toolsMenuItem(configuration: configuration)
        ].compactMap { $0 }

        for item in availableMenuItems {
            rootMenu.addItem(item)
        }
        if !availableMenuItems.isEmpty {
            rootMenu.addItem(.separator())
        }

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

    private func newFileMenuItem(
        configuration: ToolboxConfiguration
    ) -> NSMenuItem? {
        let preferences = configuration.enabledActions(in: .newFile)
            .compactMap { preference -> (ToolboxActionPreference, NewFilePreset)? in
                guard let preset = preference.action.newFilePreset else { return nil }
                return (preference, preset)
            }
        guard !preferences.isEmpty else { return nil }

        let rootItem = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "新建文件")

        for (preference, preset) in preferences {
            let item = NSMenuItem(
                title: configuredTitle(
                    preference.customName,
                    fallback: displayName(for: preset)
                ),
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

    private func directoryMenuItem(
        configuration: ToolboxConfiguration
    ) -> NSMenuItem? {
        guard isEnabled(.frequentDirectories, in: configuration) else { return nil }

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

    private func openWithMenuItem(
        configuration: ToolboxConfiguration
    ) -> NSMenuItem? {
        guard isEnabled(.openWith, in: configuration) else { return nil }

        let rootItem = NSMenuItem(title: "打开方式", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "打开方式")
        let enabledApplications = applicationRegistry().visibleEnabledApplications()
        guard !enabledApplications.isEmpty else { return nil }

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

        rootItem.submenu = menu
        return rootItem
    }

    private func toolsMenuItem(
        configuration: ToolboxConfiguration
    ) -> NSMenuItem? {
        let preferences = configuration.enabledActions(in: .tools)
        guard !preferences.isEmpty else { return nil }

        let rootItem = NSMenuItem(title: "工具", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "工具")

        for preference in preferences {
            guard let tool = implementedTool(for: preference.action) else { continue }
            let title = configuredTitle(preference.customName, fallback: tool.title)
            let item = NSMenuItem(title: title, action: tool.selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        guard !menu.items.isEmpty else { return nil }
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
              isToolboxActionEnabled(preset.toolboxAction),
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
        guard isToolboxActionEnabled(.frequentDirectories),
              let path = sender.representedObject as? String else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard directoryExists(url) else { return }

        NSWorkspace.shared.open(url)
        recordDirectoryVisit(
            url,
            dwellDuration: DirectoryHistoryPolicy.default.minimumDwellDuration
        )
    }

    @objc private func copyAbsolutePaths() {
        guard isToolboxActionEnabled(.copyAbsolutePath) else { return }
        writeToPasteboard(targetURLs().map(\.path).joined(separator: "\n"))
    }

    @objc private func copyFileURLs() {
        guard isToolboxActionEnabled(.copyFileURL) else { return }
        writeToPasteboard(
            targetURLs()
                .map(\.absoluteString)
                .joined(separator: "\n")
        )
    }

    @objc private func copyShellSafePaths() {
        guard isToolboxActionEnabled(.copyShellPath) else { return }
        writeToPasteboard(
            targetURLs()
                .map { shellQuoted($0.path) }
                .joined(separator: " ")
        )
    }

    @objc private func openHostSettings() {
        guard let settingsURL = URL(string: "magicright://settings"),
              let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Constants.hostBundleIdentifier
        ) else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [settingsURL],
            withApplicationAt: appURL,
            configuration: configuration,
            completionHandler: nil
        )
    }

    @objc private func openSelectionInApplication(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.openWith),
              let bundleIdentifier = sender.representedObject as? String else { return }

        let registry = applicationRegistry()
        guard registry.preferences.isEnabled(bundleIdentifier: bundleIdentifier),
              let descriptor = registry.descriptor(
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
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Constants.appGroupSuiteName
        ), let defaults = UserDefaults(suiteName: Constants.appGroupSuiteName) else {
            return
        }

        let lockURL = containerURL.appendingPathComponent(
            "directory-history.lock",
            isDirectory: false
        )
        do {
            try CrossProcessFileLock.withLock(at: lockURL) {
                defaults.synchronize()
                let storedData = defaults.data(forKey: Constants.directoryHistoryKey)
                var history: DirectoryHistory
                do {
                    history = try DirectoryHistory.decodeStoredData(storedData)
                } catch {
                    historyLogger.error(
                        "Directory history decode failed; original data was preserved and this visit was not recorded: \(String(describing: error), privacy: .public)"
                    )
                    return
                }

                let result = history.recordVisit(
                    to: directoryURL,
                    dwellDuration: dwellDuration
                )
                guard result != .ignoredShortDwell else { return }
                let data = try JSONEncoder().encode(history)
                defaults.set(data, forKey: Constants.directoryHistoryKey)
                defaults.synchronize()
            }
        } catch {
            historyLogger.error(
                "Directory history update failed; stored data was left unchanged: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func loadDirectoryHistory() -> DirectoryHistory {
        guard let defaults = UserDefaults(suiteName: Constants.appGroupSuiteName) else {
            return DirectoryHistory()
        }
        defaults.synchronize()
        do {
            return try DirectoryHistory.decodeStoredData(
                defaults.data(forKey: Constants.directoryHistoryKey)
            )
        } catch {
            historyLogger.error(
                "Directory history decode failed while building the menu; original data was preserved: \(String(describing: error), privacy: .public)"
            )
            return DirectoryHistory()
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

    private func loadToolboxConfiguration() -> ToolboxConfiguration {
        guard FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Constants.appGroupSuiteName
        ) != nil,
        let defaults = UserDefaults(suiteName: Constants.appGroupSuiteName) else {
            return .allDisabled
        }
        defaults.synchronize()
        guard let data = defaults.data(forKey: Constants.toolboxConfigurationKey) else {
            return ToolboxConfiguration(preset: .developer)
        }
        guard let configuration = try? JSONDecoder().decode(
                ToolboxConfiguration.self,
                from: data
              ) else {
            return .allDisabled
        }
        return configuration
    }

    private func isToolboxActionEnabled(_ action: ToolboxAction) -> Bool {
        isEnabled(action, in: loadToolboxConfiguration())
    }

    private func isEnabled(
        _ action: ToolboxAction,
        in configuration: ToolboxConfiguration
    ) -> Bool {
        action.isImplemented
            && configuration.preference(for: action)?.isEnabled == true
    }

    private func implementedTool(
        for action: ToolboxAction
    ) -> (title: String, selector: Selector)? {
        switch action {
        case .copyAbsolutePath:
            ("复制绝对路径", #selector(copyAbsolutePaths))
        case .copyFileURL:
            ("复制 file:// URL", #selector(copyFileURLs))
        case .copyShellPath:
            ("复制 Shell 安全路径", #selector(copyShellSafePaths))
        default:
            nil
        }
    }

    private func configuredTitle(_ customName: String?, fallback: String) -> String {
        guard let customName = customName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !customName.isEmpty else {
            return fallback
        }
        return customName
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
