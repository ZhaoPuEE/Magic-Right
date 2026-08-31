import AppKit
import FinderSync
import OSLog
import SuperRightCore

final class FinderSync: FIFinderSync {
    private enum Constants {
        static let hostBundleIdentifier = "dev.magicright.app"
        static let codexApplicationBundleIdentifier = "com.openai.codex"
        static let appGroupSuiteName = "group.dev.magicright.app"
        static let applicationPreferencesKey = "applicationPreferences.v1"
        static let directoryHistoryKey = "directoryHistory.v1"
        static let directoryLearningEnabledKey = "directoryLearningEnabled"
        static let toolboxConfigurationKey = "toolboxConfiguration.v1"
        static let codexHereTerminalKey = "codexHereTerminal.v1"
        static let fileOperationJournalKey = "fileOperationJournal.v1"
    }

    private struct MenuContext {
        let actionURLs: [URL]
        let transferSourceURLs: [URL]
        let newFileDestination: URL?
    }

    private struct DestinationSection {
        let title: String
        let entries: [DirectoryHistoryEntry]
    }

    private enum CapturedMenuAction {
        case archive(sourceURLs: [URL], destinationDirectory: URL)
        case clipboardFiles([URL])
        case copyOrigin(URL)
        case createFile(preset: NewFilePreset, destinationDirectory: URL)
        case createAliases([URL])
        case copyURLs([URL])
        case codexHere(directoryURL: URL, terminal: CodexHereTerminal)
        case extract([URL])
        case fileInfo([URL])
        case gitRelativePaths([URL])
        case jump(directoryURL: URL)
        case openApplication(bundleIdentifier: String, urls: [URL])
        case openGitRoot(URL)
        case openGitRootInEditor(URL)
        case openOrigin(URL)
        case paste(destinationDirectory: URL)
        case transfer(
            kind: FileTransferKind,
            sourceURLs: [URL],
            destinationDirectory: URL
        )
    }

    private var observationStartDates: [String: Date] = [:]
    private let observationLock = NSLock()
    private let historyLogger = Logger(
        subsystem: Constants.hostBundleIdentifier,
        category: "DirectoryHistory"
    )
    private static let actionLogger = Logger(
        subsystem: Constants.hostBundleIdentifier,
        category: "FinderActions"
    )
    private static let sharedStorage = SharedStorageManager(
        appGroupSuiteName: Constants.appGroupSuiteName
    )
    private static let applicationIconCache = ApplicationMenuIconCache()
    private let fileOperationQueue = DispatchQueue(
        label: "dev.magicright.finder.file-operations",
        qos: .userInitiated
    )
    private let menuActionRegistry = MenuActionRegistry<CapturedMenuAction>()

    override init() {
        super.init()

        // Finder Sync only supplies menus and observation callbacks inside
        // watched locations. Keep these roots aligned with the extension's
        // declared sandbox exceptions; watching "/" can leave Finder with no
        // eligible directory when the extension cannot access that root.
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/Users", isDirectory: true),
            URL(fileURLWithPath: "/Volumes", isDirectory: true),
            URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        ]
        let storageKind = Self.sharedStorage.location?.kind.rawValue ?? "unavailable"
        Self.actionLogger.info(
            "Finder extension initialized for supported roots with \(storageKind, privacy: .public) storage"
        )
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
        guard hostApplicationIsRunning else {
            Self.actionLogger.info(
                "Magic Right host is not running; suppressing Finder menu"
            )
            return nil
        }
        Self.actionLogger.info("Building first-level Finder menu")
        menuActionRegistry.beginBatch()
        let menu = NSMenu(title: "Magic Right")
        let attributionItem = NSMenuItem(
            title: "Magic Right 扩展功能",
            action: #selector(openHostSettings),
            keyEquivalent: ""
        )
        attributionItem.target = self
        attributionItem.image = magicRightMenuIcon()
        attributionItem.toolTip = "打开 Magic Right 设置"
        menu.addItem(attributionItem)

        // Finder serializes these menu items into its own process. Explicitly
        // target the extension principal object so every selector is routed
        // back to this instance; scalar tags carry captured context because
        // representedObject does not survive the boundary reliably.
        let configuration = loadToolboxConfiguration()
        let context = captureMenuContext(for: menuKind)
        let destinationSections = learnedDestinationSections()

        appendSection(
            openWithMenuItems(
                configuration: configuration,
                context: context
            ),
            to: menu
        )

        if let newFile = newFileMenuItem(
            configuration: configuration,
            context: context
        ) {
            appendSection([newFile], to: menu)
        }

        var destinationItems: [NSMenuItem] = []
        if isEnabled(.moveTo, in: configuration),
           !context.transferSourceURLs.isEmpty,
           let item = transferMenuItem(
            title: "移动到",
            kind: .move,
            sourceURLs: context.transferSourceURLs,
            destinationSections: destinationSections
           ) {
            destinationItems.append(item)
        }
        if isEnabled(.copyTo, in: configuration),
           !context.transferSourceURLs.isEmpty,
           let item = transferMenuItem(
            title: "复制到",
            kind: .copy,
            sourceURLs: context.transferSourceURLs,
            destinationSections: destinationSections
           ) {
            destinationItems.append(item)
        }
        if isEnabled(.frequentDirectories, in: configuration),
           let item = jumpMenuItem(destinationSections: destinationSections) {
            destinationItems.append(item)
        }
        appendSection(destinationItems, to: menu)

        appendSection(
            fileOperationMenuItems(
                configuration: configuration,
                context: context
            ),
            to: menu
        )

        appendSection(
            archiveMenuItems(
                configuration: configuration,
                context: context
            ),
            to: menu
        )

        appendSection(
            gitMenuItems(
                configuration: configuration,
                context: context
            ),
            to: menu
        )

        appendSection(
            toolsMenuItems(
                configuration: configuration,
                context: context
            ),
            to: menu
        )

        let settingsItem = NSMenuItem(
            title: "Magic Right 设置…",
            action: #selector(openHostSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        appendSection([settingsItem], to: menu)
        return menu
    }

    private func newFileMenuItem(
        configuration: ToolboxConfiguration,
        context: MenuContext
    ) -> NSMenuItem? {
        guard let destinationDirectory = context.newFileDestination else {
            return nil
        }
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
            capture(
                .createFile(
                    preset: preset,
                    destinationDirectory: destinationDirectory
                ),
                for: item
            )
            item.image = Self.menuSymbolImage(symbolName(for: preset))
            menu.addItem(item)
        }

        rootItem.submenu = menu
        return rootItem
    }

    private func openWithMenuItems(
        configuration: ToolboxConfiguration,
        context: MenuContext
    ) -> [NSMenuItem] {
        guard let firstURL = context.actionURLs.first else { return [] }
        var items: [NSMenuItem] = []

        let codexTerminal = selectedCodexHereTerminal()
        if isEnabled(.codexHere, in: configuration),
           NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: codexTerminal.bundleIdentifier
           ) != nil,
           codexExecutableURL() != nil {
            let item = NSMenuItem(
                title: "Codex Here!",
                action: #selector(openCodexHere(_:)),
                keyEquivalent: ""
            )
            capture(
                .codexHere(
                    directoryURL: directoryContext(for: firstURL),
                    terminal: codexTerminal
                ),
                for: item
            )
            item.image = codexMenuIcon()
            item.toolTip = "在当前目录用 \(codexTerminal.displayName) 启动 Codex"
            items.append(item)
        }

        guard isEnabled(.openWith, in: configuration) else { return items }
        let enabledApplications = applicationRegistry().visibleEnabledApplications()
        items.append(contentsOf: enabledApplications.map { application in
            let item = NSMenuItem(
                title: "在 \(application.menuDisplayName) 中打开",
                action: #selector(openSelectionInApplication(_:)),
                keyEquivalent: ""
            )
            capture(
                .openApplication(
                    bundleIdentifier: application.bundleIdentifier,
                    urls: context.actionURLs
                ),
                for: item
            )

            item.image = applicationMenuIcon(for: application)
            return item
        })
        return items
    }

    private func fileOperationMenuItems(
        configuration: ToolboxConfiguration,
        context: MenuContext
    ) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if isEnabled(.cut, in: configuration),
           !context.transferSourceURLs.isEmpty {
            let item = NSMenuItem(
                title: "剪切到系统剪贴板",
                action: #selector(cutSelection(_:)),
                keyEquivalent: ""
            )
            item.image = Self.menuSymbolImage("scissors")
            capture(.clipboardFiles(context.transferSourceURLs), for: item)
            items.append(item)
        }

        if isEnabled(.paste, in: configuration),
           let destinationDirectory = context.newFileDestination,
           systemPasteboardContainsFileURLs {
            let item = NSMenuItem(
                title: "粘贴到此处",
                action: #selector(pasteSelection(_:)),
                keyEquivalent: ""
            )
            item.image = Self.menuSymbolImage("doc.on.clipboard")
            capture(.paste(destinationDirectory: destinationDirectory), for: item)
            items.append(item)
        }

        if isEnabled(.fileInfo, in: configuration),
           !context.actionURLs.isEmpty {
            let item = NSMenuItem(
                title: "文件信息",
                action: #selector(showFileInfo(_:)),
                keyEquivalent: ""
            )
            item.image = Self.menuSymbolImage("info.circle")
            capture(.fileInfo(context.actionURLs), for: item)
            items.append(item)
        }

        if isEnabled(.createAlias, in: configuration),
           !context.transferSourceURLs.isEmpty {
            let item = NSMenuItem(
                title: "创建替身",
                action: #selector(createAliases(_:)),
                keyEquivalent: ""
            )
            item.image = Self.menuSymbolImage("arrowshape.turn.up.right")
            capture(.createAliases(context.transferSourceURLs), for: item)
            items.append(item)
        }

        return items
    }

    private func archiveMenuItems(
        configuration: ToolboxConfiguration,
        context: MenuContext
    ) -> [NSMenuItem] {
        let sourceURLs = context.transferSourceURLs
        guard !sourceURLs.isEmpty else { return [] }
        var items: [NSMenuItem] = []

        if isEnabled(.archive, in: configuration),
           let destinationDirectory = sourceURLs.first?.deletingLastPathComponent() {
            let item = NSMenuItem(
                title: "压缩为 ZIP",
                action: #selector(archiveSelection(_:)),
                keyEquivalent: ""
            )
            item.image = Self.menuSymbolImage("archivebox")
            capture(
                .archive(
                    sourceURLs: sourceURLs,
                    destinationDirectory: destinationDirectory
                ),
                for: item
            )
            items.append(item)
        }

        if isEnabled(.unarchive, in: configuration),
           sourceURLs.allSatisfy({ ArchiveService().canExtract($0) }) {
            let item = NSMenuItem(
                title: sourceURLs.count == 1 ? "解压" : "分别解压",
                action: #selector(extractSelection(_:)),
                keyEquivalent: ""
            )
            item.image = Self.menuSymbolImage("arrow.down.doc")
            capture(.extract(sourceURLs), for: item)
            items.append(item)
        }

        return items
    }

    private func gitMenuItems(
        configuration: ToolboxConfiguration,
        context: MenuContext
    ) -> [NSMenuItem] {
        guard !configuration.enabledActions(in: .git).isEmpty else { return [] }
        guard let firstURL = context.actionURLs.first else { return [] }
        guard isInsideGitRepository(firstURL) else { return [] }

        var items: [NSMenuItem] = []
        if isEnabled(.copyGitRelativePath, in: configuration) {
            let item = NSMenuItem(
                title: "复制 Git 相对路径",
                action: #selector(copyGitRelativePaths(_:)),
                keyEquivalent: ""
            )
            capture(.gitRelativePaths(context.actionURLs), for: item)
            items.append(item)
        }
        if isEnabled(.openGitRoot, in: configuration) {
            let item = NSMenuItem(
                title: "打开 Git 根目录",
                action: #selector(openGitRoot(_:)),
                keyEquivalent: ""
            )
            capture(.openGitRoot(firstURL), for: item)
            items.append(item)
        }
        if isEnabled(.openGitRootInEditor, in: configuration),
           preferredEditorDescriptor() != nil {
            let item = NSMenuItem(
                title: "在首选编辑器中打开仓库",
                action: #selector(openGitRootInEditor(_:)),
                keyEquivalent: ""
            )
            capture(.openGitRootInEditor(firstURL), for: item)
            items.append(item)
        }

        if isEnabled(.openOrigin, in: configuration) {
            let item = NSMenuItem(
                title: "打开 origin 页面",
                action: #selector(openOrigin(_:)),
                keyEquivalent: ""
            )
            capture(.openOrigin(firstURL), for: item)
            items.append(item)
        }
        if isEnabled(.copyOriginURL, in: configuration) {
            let item = NSMenuItem(
                title: "复制 origin URL",
                action: #selector(copyOriginURL(_:)),
                keyEquivalent: ""
            )
            capture(.copyOrigin(firstURL), for: item)
            items.append(item)
        }

        return items
    }

    private func toolsMenuItems(
        configuration: ToolboxConfiguration,
        context: MenuContext
    ) -> [NSMenuItem] {
        guard !context.actionURLs.isEmpty else { return [] }
        let preferences = configuration.enabledActions(in: .tools)
        return preferences.compactMap { preference in
            guard let tool = implementedTool(for: preference.action) else {
                return nil
            }
            let title = configuredTitle(preference.customName, fallback: tool.title)
            let item = NSMenuItem(title: title, action: tool.selector, keyEquivalent: "")
            capture(.copyURLs(context.actionURLs), for: item)
            return item
        }
    }

    private func transferMenuItem(
        title: String,
        kind: FileTransferKind,
        sourceURLs: [URL],
        destinationSections: [DestinationSection]
    ) -> NSMenuItem? {
        guard destinationSections.contains(where: { !$0.entries.isEmpty }) else {
            return nil
        }
        let rootItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        appendDestinationSections(destinationSections, to: menu) { entry in
            let item = NSMenuItem(
                title: entry.displayName,
                action: #selector(self.transferSelection(_:)),
                keyEquivalent: ""
            )
            capture(
                .transfer(
                    kind: kind,
                    sourceURLs: sourceURLs,
                    destinationDirectory: entry.directoryURL
                ),
                for: item
            )
            return item
        }
        rootItem.submenu = menu
        return rootItem
    }

    private func jumpMenuItem(
        destinationSections: [DestinationSection]
    ) -> NSMenuItem? {
        guard destinationSections.contains(where: { !$0.entries.isEmpty }) else {
            return nil
        }
        let rootItem = NSMenuItem(title: "跳转到", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "跳转到")
        appendDestinationSections(destinationSections, to: menu) { entry in
            let item = NSMenuItem(
                title: entry.displayName,
                action: #selector(self.openLearnedDirectory(_:)),
                keyEquivalent: ""
            )
            capture(.jump(directoryURL: entry.directoryURL), for: item)
            return item
        }
        rootItem.submenu = menu
        return rootItem
    }

    private func appendDestinationSections(
        _ sections: [DestinationSection],
        to menu: NSMenu,
        makeItem: (DirectoryHistoryEntry) -> NSMenuItem
    ) {
        for section in sections where !section.entries.isEmpty {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            let heading = NSMenuItem(
                title: section.title,
                action: nil,
                keyEquivalent: ""
            )
            heading.isEnabled = false
            menu.addItem(heading)

            for entry in section.entries {
                let item = makeItem(entry)
                item.toolTip = entry.normalizedPath
                item.image = Self.menuSymbolImage(
                    entry.isPinned ? "folder.fill" : "folder"
                )
                menu.addItem(item)
            }
        }
    }

    private func appendSection(_ items: [NSMenuItem], to menu: NSMenu) {
        guard !items.isEmpty else { return }
        for item in items {
            menu.addItem(item)
        }
    }

    private func capture(_ action: CapturedMenuAction, for item: NSMenuItem) {
        item.target = self
        item.tag = menuActionRegistry.register(action)
    }

    private func capturedAction(for sender: NSMenuItem) -> CapturedMenuAction? {
        menuActionRegistry.action(for: sender.tag)
    }

    @objc private func createNewFile(_ sender: NSMenuItem) {
        guard case let .createFile(preset, destinationDirectory)? = capturedAction(
            for: sender
        ), isToolboxActionEnabled(preset.toolboxAction) else {
            Self.actionLogger.error("New-file action lost its captured context")
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
            Self.actionLogger.info(
                "Created file at \(createdURL.path, privacy: .private)"
            )
            NSWorkspace.shared.activateFileViewerSelecting([createdURL])
        } catch {
            Self.actionLogger.error(
                "New-file action failed: \(String(describing: error), privacy: .public)"
            )
            NSSound.beep()
        }
    }

    @objc private func openLearnedDirectory(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.frequentDirectories),
              case let .jump(directoryURL)? = capturedAction(for: sender) else {
            Self.reportActionFailure("Jump action lost its captured destination")
            return
        }
        Self.actionLogger.info("Requesting current-window Finder navigation")
        submitHostAction(.navigateFinder(directoryURL: directoryURL))
        recordDirectoryVisit(
            directoryURL,
            dwellDuration: DirectoryHistoryPolicy.default.minimumDwellDuration
        )
    }

    @objc private func copyAbsolutePaths(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.copyAbsolutePath),
              case let .copyURLs(urls)? = capturedAction(for: sender) else {
            Self.actionLogger.error("Copy-path action lost its captured selection")
            return
        }
        Self.writeToPasteboard(urls.map(\.path).joined(separator: "\n"))
    }

    @objc private func copyShellSafePaths(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.copyShellPath),
              case let .copyURLs(urls)? = capturedAction(for: sender) else {
            Self.actionLogger.error("Shell-path action lost its captured selection")
            return
        }
        Self.writeToPasteboard(
            urls
                .map { shellQuoted($0.path) }
                .joined(separator: " ")
        )
    }

    @objc private func cutSelection(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.cut),
              case let .clipboardFiles(urls)? = capturedAction(for: sender),
              !urls.isEmpty else {
            Self.reportActionFailure("Cut action lost its captured selection")
            return
        }
        Task { @MainActor in
            do {
                try SystemFileClipboardService().write(
                    fileURLs: urls,
                    operation: .cut
                )
                Self.actionLogger.info(
                    "Wrote \(urls.count) standard file URLs to the system pasteboard"
                )
            } catch {
                Self.reportActionFailure(
                    "Cut action failed: \(String(describing: error))"
                )
            }
        }
    }

    @objc private func pasteSelection(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.paste),
              case let .paste(destinationDirectory)? = capturedAction(for: sender) else {
            Self.reportActionFailure("Paste action lost its destination")
            return
        }

        Task { @MainActor in
            do {
                let results = try await SystemFileClipboardService().paste(
                    into: destinationDirectory
                )
                Self.recordAndRevealPasteResults(results)
            } catch let error as FileClipboardPasteFinalizationError {
                Self.recordAndRevealPasteResults(error.completedResults)
                Self.reportActionFailure(
                    "Paste completed, but the cut clipboard could not be updated: "
                        + error.underlyingErrorDescription
                )
            } catch let error as FileClipboardPartialTransferError {
                Self.recordAndRevealPasteResults(error.completedResults)
                var message = "Paste partially completed: "
                    + "\(error.completedResults.count) item(s) succeeded; "
                    + "\(error.failedSourceURL.path) failed: "
                    + error.underlyingErrorDescription
                if let finalizationError =
                    error.cutClipboardFinalizationErrorDescription {
                    message += "; cut clipboard update also failed: "
                        + finalizationError
                }
                Self.reportActionFailure(message)
            } catch {
                Self.reportActionFailure(
                    "Paste action failed: \(String(describing: error))"
                )
            }
        }
    }

    @MainActor
    private static func recordAndRevealPasteResults(
        _ results: [FileTransferResult]
    ) {
        for result in results {
            persistOperationRecord(FileOperationRecord(result: result))
        }
        let destinationURLs = results.map(\.destinationURL)
        if !destinationURLs.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(destinationURLs)
        }
    }

    @objc private func showFileInfo(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.fileInfo),
              case let .fileInfo(urls)? = capturedAction(for: sender),
              !urls.isEmpty else {
            Self.reportActionFailure("File-info action lost its selection")
            return
        }

        fileOperationQueue.async {
            do {
                let information = try urls.map {
                    try FileInformationService().information(for: $0)
                }
                DispatchQueue.main.async {
                    Self.presentFileInformation(information)
                }
            } catch {
                Self.reportActionFailure(
                    "File-info action failed: \(String(describing: error))"
                )
            }
        }
    }

    @objc private func createAliases(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.createAlias),
              case let .createAliases(urls)? = capturedAction(for: sender),
              !urls.isEmpty else {
            Self.reportActionFailure("Create-alias action lost its selection")
            return
        }

        fileOperationQueue.async {
            var aliasURLs: [URL] = []
            var failureCount = 0
            for url in urls {
                do {
                    let result = try FinderAliasService().createAlias(
                        to: url,
                        in: url.deletingLastPathComponent()
                    )
                    aliasURLs.append(result.aliasURL)
                } catch {
                    failureCount += 1
                    Self.actionLogger.error(
                        "Create-alias action failed: \(String(describing: error), privacy: .public)"
                    )
                }
            }
            DispatchQueue.main.async {
                if failureCount > 0 { NSSound.beep() }
                if !aliasURLs.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(aliasURLs)
                }
            }
        }
    }

    @objc private func copyGitRelativePaths(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.copyGitRelativePath),
              case let .gitRelativePaths(urls)? = capturedAction(for: sender),
              !urls.isEmpty else {
            Self.reportActionFailure("Git-relative-path action lost its selection")
            return
        }

        submitHostAction(.copyGitRelativePaths(itemURLs: urls))
    }

    @objc private func openGitRoot(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.openGitRoot),
              case let .openGitRoot(itemURL)? = capturedAction(for: sender) else {
            Self.reportActionFailure("Open-Git-root action lost its item")
            return
        }
        submitHostAction(.openGitRoot(itemURL: itemURL))
    }

    @objc private func openGitRootInEditor(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.openGitRootInEditor),
              case let .openGitRootInEditor(itemURL)? = capturedAction(for: sender) else {
            Self.reportActionFailure("Open-Git-root-in-editor action lost its item")
            return
        }
        submitHostAction(.openGitRootInEditor(itemURL: itemURL))
    }

    @objc private func openOrigin(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.openOrigin),
              case let .openOrigin(itemURL)? = capturedAction(for: sender) else {
            Self.reportActionFailure("Open-origin action lost its item")
            return
        }
        submitHostAction(.openOrigin(itemURL: itemURL))
    }

    @objc private func copyOriginURL(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.copyOriginURL),
              case let .copyOrigin(itemURL)? = capturedAction(for: sender) else {
            Self.reportActionFailure("Copy-origin action lost its item")
            return
        }
        submitHostAction(.copyOriginURL(itemURL: itemURL))
    }

    @objc private func archiveSelection(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.archive),
              case let .archive(sourceURLs, destinationDirectory)? = capturedAction(
                for: sender
              ),
              !sourceURLs.isEmpty else {
            Self.reportActionFailure("Archive action lost its selection")
            return
        }

        submitHostAction(
            .archive(
                sourceURLs: sourceURLs,
                destinationDirectory: destinationDirectory
            )
        )
    }

    @objc private func extractSelection(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.unarchive),
              case let .extract(archiveURLs)? = capturedAction(for: sender),
              !archiveURLs.isEmpty else {
            Self.reportActionFailure("Extract action lost its selection")
            return
        }

        submitHostAction(.extract(archiveURLs: archiveURLs))
    }

    @objc private func transferSelection(_ sender: NSMenuItem) {
        guard case let .transfer(kind, sources, destination)? = capturedAction(
            for: sender
        ) else {
            Self.actionLogger.error("Transfer action lost its captured context")
            NSSound.beep()
            return
        }
        let requiredAction: ToolboxAction = kind == .move ? .moveTo : .copyTo
        guard isToolboxActionEnabled(requiredAction) else { return }

        let queue = fileOperationQueue
        queue.async {
            var completedURLs: [URL] = []
            var failureCount = 0
            for source in sources {
                do {
                    let result = try FileTransferService().transfer(
                        FileTransferRequest(
                            kind: kind,
                            sourceURL: source,
                            destinationDirectory: destination
                        )
                    )
                    completedURLs.append(result.destinationURL)
                    Self.persistOperationRecord(FileOperationRecord(result: result))
                    Self.actionLogger.info(
                        "Completed \(kind.rawValue, privacy: .public) operation"
                    )
                } catch {
                    failureCount += 1
                    Self.actionLogger.error(
                        "File transfer failed: \(String(describing: error), privacy: .public)"
                    )
                }
            }

            guard !completedURLs.isEmpty else {
                DispatchQueue.main.async { NSSound.beep() }
                return
            }
            let revealedURLs = completedURLs
            let shouldSignalPartialFailure = failureCount > 0
            DispatchQueue.main.async {
                if shouldSignalPartialFailure {
                    NSSound.beep()
                }
                NSWorkspace.shared.activateFileViewerSelecting(revealedURLs)
            }
        }
    }

    @objc private func openHostSettings() {
        guard let settingsURL = URL(string: "magicright://settings") else {
            Self.reportActionFailure("Magic Right settings URL is invalid")
            return
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Constants.hostBundleIdentifier
        ) else {
            Self.reportActionFailure("Magic Right host application could not be located")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [settingsURL],
            withApplicationAt: appURL,
            configuration: configuration,
            completionHandler: Self.logApplicationOpenCompletion
        )
    }

    @objc private func openSelectionInApplication(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.openWith),
              case let .openApplication(bundleIdentifier, urls)? = capturedAction(
                for: sender
              ) else {
            Self.reportActionFailure("Open-app action lost its captured selection")
            return
        }

        let registry = applicationRegistry()
        guard registry.preferences.isEnabled(bundleIdentifier: bundleIdentifier) else {
            Self.reportActionFailure("The selected application is no longer enabled")
            return
        }
        guard let descriptor = registry.descriptor(
            forBundleIdentifier: bundleIdentifier
        ) else {
            Self.reportActionFailure("The selected application could not be located")
            return
        }

        guard !urls.isEmpty else {
            Self.reportActionFailure("Open-app action has no captured Finder items")
            return
        }
        let request: ApplicationOpenRequest
        do {
            request = try ApplicationOpenRequestBuilder.makeRequest(
                for: descriptor,
                intent: .selection(urls)
            )
        } catch {
            Self.reportActionFailure(
                "Open-app request could not be built: \(String(describing: error))"
            )
            return
        }
        guard execute(request) else { return }

        Self.actionLogger.info(
            "Submitted open request for \(bundleIdentifier, privacy: .public)"
        )

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

    @objc private func openCodexHere(_ sender: NSMenuItem) {
        guard isToolboxActionEnabled(.codexHere),
              case let .codexHere(directoryURL, terminal)? = capturedAction(
                for: sender
              ) else {
            Self.reportActionFailure("Codex Here action lost its captured directory")
            return
        }
        guard directoryExists(directoryURL) else {
            Self.reportActionFailure("Codex Here directory no longer exists")
            return
        }
        guard let codexExecutableURL = codexExecutableURL() else {
            Self.reportActionFailure("Codex executable could not be located")
            return
        }

        submitHostAction(
            .codexHere(
                directoryURL: directoryURL,
                codexExecutableURL: codexExecutableURL,
                terminal: terminal
            )
        )

        Self.actionLogger.info(
            "Submitted Codex Here request for \(terminal.rawValue, privacy: .public)"
        )
        recordDirectoryVisit(
            directoryURL,
            dwellDuration: DirectoryHistoryPolicy.default.minimumDwellDuration
        )
    }

    @discardableResult
    private func execute(_ request: ApplicationOpenRequest) -> Bool {
        let locator = NSWorkspaceApplicationLocator()
        guard let application = locator.locateApplication(
            bundleIdentifier: request.applicationBundleIdentifier
        ) else {
            Self.reportActionFailure("Application executable could not be located")
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        switch request {
        case let .openURLs(openRequest):
            NSWorkspace.shared.open(
                openRequest.urls,
                withApplicationAt: application.applicationURL,
                configuration: configuration,
                completionHandler: Self.logApplicationOpenCompletion
            )
        case let .structuredLaunch(launchRequest):
            configuration.arguments = launchRequest.argumentValues
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(
                at: application.applicationURL,
                configuration: configuration,
                completionHandler: Self.logApplicationOpenCompletion
            )
        }
        return true
    }

    private static func logApplicationOpenCompletion(
        _ application: NSRunningApplication?,
        _ error: (any Error)?
    ) {
        if let error {
            reportActionFailure(
                "Application open failed: \(String(describing: error))"
            )
        } else if let application {
            actionLogger.info(
                "Application open completed for process \(application.processIdentifier)"
            )
        } else {
            reportActionFailure("Application open completed without a running application")
        }
    }

    private static func reportActionFailure(_ message: String) {
        actionLogger.error("\(message, privacy: .public)")
        if Thread.isMainThread {
            NSSound.beep()
        } else {
            DispatchQueue.main.async {
                NSSound.beep()
            }
        }
    }

    private var isDirectoryLearningEnabled: Bool {
        guard let defaults = Self.sharedStorage.defaults else {
            return true
        }
        return defaults.object(
            forKey: Constants.directoryLearningEnabledKey
        ) as? Bool ?? true
    }

    /// Finder Sync extensions are hosted independently by macOS and can remain
    /// alive after their containing app quits. Keep the extension registered,
    /// but expose no actions unless the Magic Right host process is running.
    /// This also avoids persisting a separate heartbeat that could become stale
    /// after a crash or force quit.
    private var hostApplicationIsRunning: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: Constants.hostBundleIdentifier
        ).isEmpty
    }

    private func recordDirectoryVisit(
        _ directoryURL: URL,
        dwellDuration: TimeInterval
    ) {
        guard isDirectoryLearningEnabled else { return }
        guard let containerURL = Self.sharedStorage.containerURL,
              let defaults = Self.sharedStorage.defaults else {
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
        guard let defaults = Self.sharedStorage.defaults else {
            return DirectoryHistory()
        }
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
        if let data = Self.sharedStorage.defaults?.data(
            forKey: Constants.applicationPreferencesKey
        ), let decoded = try? JSONDecoder().decode(ApplicationPreferences.self, from: data),
           !decoded.applications.isEmpty {
            preferences = decoded.addingMissingDeveloperDefaults()
        } else {
            preferences = .developerDefaults
        }

        return ApplicationRegistry(
            preferences: preferences,
            locator: NSWorkspaceApplicationLocator()
        )
    }

    private func selectedCodexHereTerminal() -> CodexHereTerminal {
        let configured = Self.sharedStorage.defaults
            .flatMap { $0.string(forKey: Constants.codexHereTerminalKey) }
            .flatMap(CodexHereTerminal.init(rawValue:))
            ?? .defaultValue
        if NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: configured.bundleIdentifier
        ) != nil {
            return configured
        }
        return .terminal
    }

    /// Resolves an installed Codex executable without invoking a shell. A
    /// separately installed CLI is preferred so Codex Here follows the user's
    /// current CLI update channel. Launch Services locates the desktop app even
    /// if its visible name changes, and its bundled executable is the fallback.
    private func codexExecutableURL() -> URL? {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            homeDirectory.appendingPathComponent(".local/bin/codex"),
            homeDirectory.appendingPathComponent(".npm-global/bin/codex"),
            homeDirectory.appendingPathComponent(".volta/bin/codex")
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true)
                    .appendingPathComponent("codex", isDirectory: false)
            })
        }
        if let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Constants.codexApplicationBundleIdentifier
        ) {
            candidates.append(
                applicationURL
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent("codex", isDirectory: false)
            )
        }

        var seen = Set<String>()
        return candidates.first { candidate in
            let path = candidate.standardizedFileURL.path
            return seen.insert(path).inserted
                && FileManager.default.isExecutableFile(atPath: path)
        }?.standardizedFileURL
    }

    private func codexMenuIcon() -> NSImage? {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Constants.codexApplicationBundleIdentifier
        ) else {
            return Self.menuSymbolImage(
                "terminal",
                accessibilityDescription: "Codex"
            )
        }

        let resourcesURL = applicationURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        for resourceName in ["icon-codex-dark-color.png", "icon-codex-light.png"] {
            let resourceURL = resourcesURL.appendingPathComponent(resourceName)
            if let image = NSImage(contentsOf: resourceURL) {
                image.size = NSSize(width: 16, height: 16)
                image.isTemplate = false
                return image
            }
        }

        return Self.menuSymbolImage(
            "terminal",
            accessibilityDescription: "Codex"
        )
    }

    private func magicRightMenuIcon() -> NSImage? {
        Self.menuSymbolImage(
            "cursorarrow.click.2",
            accessibilityDescription: "Magic Right"
        )
    }

    private func applicationMenuIcon(
        for application: DetectedApplication
    ) -> NSImage? {
        let cacheKey = application.bundleIdentifier
            + "|"
            + application.currentApplicationURL.standardizedFileURL.path
        if let cached = Self.applicationIconCache.image(forKey: cacheKey) {
            return cached
        }

        let icon = directBundleIcon(at: application.currentApplicationURL)
            ?? NSWorkspace.shared.icon(
                forFile: application.currentApplicationURL.path
            )
        icon.size = NSSize(width: 16, height: 16)
        icon.isTemplate = false
        Self.applicationIconCache.insert(icon, forKey: cacheKey)
        return icon
    }

    private func directBundleIcon(at applicationURL: URL) -> NSImage? {
        guard let bundle = Bundle(url: applicationURL) else { return nil }
        let declaredName = (
            bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String
        ) ?? (
            bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String
        )
        guard let declaredName, !declaredName.isEmpty else { return nil }

        let resourcesURL = applicationURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        let names = declaredName.lowercased().hasSuffix(".icns")
            ? [declaredName]
            : [declaredName, declaredName + ".icns"]
        for name in names {
            if let image = NSImage(
                contentsOf: resourcesURL.appendingPathComponent(name)
            ) {
                return image
            }
        }
        return nil
    }

    private static func menuSymbolImage(
        _ name: String,
        accessibilityDescription: String? = nil
    ) -> NSImage? {
        let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: accessibilityDescription
        )
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)
        return image
    }

    private func loadToolboxConfiguration() -> ToolboxConfiguration {
        guard Self.sharedStorage.isAvailable,
              let defaults = Self.sharedStorage.defaults else {
            return .allDisabled
        }
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
            ("复制绝对路径", #selector(copyAbsolutePaths(_:)))
        case .copyShellPath:
            ("复制 Shell 安全路径", #selector(copyShellSafePaths(_:)))
        default:
            nil
        }
    }

    private func preferredEditorDescriptor() -> ApplicationDescriptor? {
        let preferredEditorIdentifiers = [
            "dev.zed.Zed",
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92",
            "com.vscodium",
            "com.sublimetext.4",
            "com.panic.Nova",
            "com.jetbrains.intellij",
            "com.jetbrains.intellij.ce",
            "com.jetbrains.pycharm",
            "com.jetbrains.pycharm.ce",
            "com.jetbrains.WebStorm",
            "com.jetbrains.CLion",
            "com.jetbrains.goland",
            "com.jetbrains.rider"
        ]
        let applications = applicationRegistry().visibleEnabledApplications()
        for identifier in preferredEditorIdentifiers {
            if let application = applications.first(where: {
                $0.bundleIdentifier == identifier
            }) {
                return application.descriptor
            }
        }
        return nil
    }

    private func isInsideGitRepository(_ itemURL: URL) -> Bool {
        GitRepositoryService.containsGitMetadata(
            atOrAbove: directoryContext(for: itemURL)
        )
    }

    private func submitHostAction(_ action: HostAction) {
        guard let defaults = Self.sharedStorage.defaults else {
            Self.reportActionFailure("Host-action shared storage is unavailable")
            return
        }
        let request = HostActionRequest(action: action)
        do {
            let requestData = try JSONEncoder().encode(request)
            Self.removeInvalidOrExpiredHostActionRequests(from: defaults)
            defaults.set(requestData, forKey: request.storageKey)
            defaults.synchronize()
        } catch {
            Self.reportActionFailure(
                "Host action could not be encoded: \(String(describing: error))"
            )
            return
        }

        var components = URLComponents()
        components.scheme = "magicright"
        components.host = "action"
        components.queryItems = [
            URLQueryItem(name: "id", value: request.id.uuidString.lowercased())
        ]
        guard let actionURL = components.url,
              let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: Constants.hostBundleIdentifier
              ) else {
            Self.removeHostActionRequest(
                storageKey: request.storageKey,
                from: defaults
            )
            Self.reportActionFailure("Magic Right host application is unavailable")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        let storageKey = request.storageKey
        NSWorkspace.shared.open(
            [actionURL],
            withApplicationAt: appURL,
            configuration: configuration
        ) { _, error in
            if let error {
                if let callbackDefaults = Self.sharedStorage.defaults {
                    Self.removeHostActionRequest(
                        storageKey: storageKey,
                        from: callbackDefaults
                    )
                }
                Self.reportActionFailure(
                    "Host action could not be delivered: \(String(describing: error))"
                )
            }
        }
    }

    private static func removeInvalidOrExpiredHostActionRequests(
        from defaults: UserDefaults,
        at date: Date = Date()
    ) {
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix(HostActionRequest.storageKeyPrefix) {
            guard let data = defaults.data(forKey: key),
                  let request = try? JSONDecoder().decode(
                    HostActionRequest.self,
                    from: data
                  ),
                  request.isFresh(at: date) else {
                defaults.removeObject(forKey: key)
                continue
            }
        }
    }

    private static func removeHostActionRequest(
        storageKey: String,
        from defaults: UserDefaults
    ) {
        defaults.removeObject(forKey: storageKey)
        defaults.synchronize()
    }

    private func configuredTitle(_ customName: String?, fallback: String) -> String {
        guard let customName = customName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !customName.isEmpty else {
            return fallback
        }
        return customName
    }

    private func captureMenuContext(for menuKind: FIMenuKind) -> MenuContext {
        let controller = FIFinderSyncController.default()
        let selectedURLs = controller.selectedItemURLs() ?? []
        let targetedURL = controller.targetedURL()
        let actionURLs: [URL]
        switch menuKind {
        case .contextualMenuForItems:
            actionURLs = selectedURLs
        case .contextualMenuForContainer, .contextualMenuForSidebar:
            actionURLs = targetedURL.map { [$0] } ?? []
        case .toolbarItemMenu:
            actionURLs = selectedURLs.isEmpty
                ? targetedURL.map { [$0] } ?? []
                : selectedURLs
        @unknown default:
            actionURLs = selectedURLs.isEmpty
                ? targetedURL.map { [$0] } ?? []
                : selectedURLs
        }
        let transferSourceURLs: [URL]
        switch menuKind {
        case .contextualMenuForItems:
            transferSourceURLs = selectedURLs
        default:
            transferSourceURLs = []
        }

        let newFileDestination: URL?
        switch menuKind {
        case .contextualMenuForItems, .toolbarItemMenu:
            if selectedURLs.count == 1,
               let selectedURL = selectedURLs.first,
               directoryExists(selectedURL) || selectedURL.hasDirectoryPath {
                newFileDestination = selectedURL
            } else if let targetedURL {
                newFileDestination = directoryContext(for: targetedURL)
            } else if let selectedURL = selectedURLs.first {
                newFileDestination = directoryContext(for: selectedURL)
            } else {
                newFileDestination = nil
            }
        case .contextualMenuForContainer, .contextualMenuForSidebar:
            newFileDestination = targetedURL.map(directoryContext(for:))
        @unknown default:
            newFileDestination = targetedURL.map(directoryContext(for:))
        }

        return MenuContext(
            actionURLs: actionURLs,
            transferSourceURLs: transferSourceURLs,
            newFileDestination: newFileDestination
        )
    }

    private func learnedDestinationSections() -> [DestinationSection] {
        let sections = loadDirectoryHistory().sections(
            recentLimit: 10,
            pathExists: directoryExists
        )
        var seen = Set<String>()
        func unique(_ entries: [DirectoryHistoryEntry]) -> [DirectoryHistoryEntry] {
            entries.filter { seen.insert($0.normalizedPath).inserted }
        }
        return [
            DestinationSection(title: "固定", entries: unique(sections.pinned)),
            DestinationSection(title: "常用", entries: unique(sections.frequent)),
            DestinationSection(title: "最近", entries: unique(sections.recent))
        ]
    }

    private static func persistOperationRecord(_ record: FileOperationRecord) {
        guard let containerURL = sharedStorage.containerURL,
              let defaults = sharedStorage.defaults else {
            actionLogger.error("File-operation journal is unavailable")
            return
        }

        let lockURL = containerURL.appendingPathComponent(
            "file-operation-journal.lock",
            isDirectory: false
        )
        do {
            try CrossProcessFileLock.withLock(at: lockURL) {
                defaults.synchronize()
                var journal: FileOperationJournal
                if let data = defaults.data(forKey: Constants.fileOperationJournalKey) {
                    guard let decoded = try? JSONDecoder().decode(
                        FileOperationJournal.self,
                        from: data
                    ) else {
                        actionLogger.error(
                            "File-operation journal decode failed; stored data was preserved"
                        )
                        return
                    }
                    journal = decoded
                } else {
                    journal = FileOperationJournal()
                }

                journal.append(record)
                defaults.set(
                    try JSONEncoder().encode(journal),
                    forKey: Constants.fileOperationJournalKey
                )
                defaults.synchronize()
            }
        } catch {
            actionLogger.error(
                "File-operation journal update failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func directoryContext(for url: URL) -> URL {
        if directoryExists(url) || url.hasDirectoryPath {
            return url
        }
        return url.deletingLastPathComponent()
    }

    private var systemPasteboardContainsFileURLs: Bool {
        NSPasteboard.general.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

    private static func writeToPasteboard(_ value: String) {
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    @MainActor
    private static func presentFileInformation(
        _ information: [FileItemInformation]
    ) {
        guard !information.isEmpty else { return }
        let report = information.map(Self.fileInformationReport).joined(
            separator: "\n\n"
        )
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = information.count == 1
            ? information[0].name
            : "\(information.count) 个项目"
        alert.informativeText = report
        alert.addButton(withTitle: "完成")
        alert.addButton(withTitle: "复制信息")
        let canHash = information.count == 1 && information[0].kind == .regularFile
        if canHash {
            alert.addButton(withTitle: "计算 SHA-256")
        }

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            Self.writeToPasteboard(report)
        } else if response == .alertThirdButtonReturn,
                  canHash,
                  let url = information.first?.url {
            Task { @MainActor in
                do {
                    let hashed = try await Task.detached(priority: .userInitiated) {
                        try FileInformationService().information(
                            for: url,
                            options: FileInformationOptions(calculateSHA256: true)
                        )
                    }.value
                    guard let digest = hashed.sha256 else { return }
                    Self.presentSHA256(digest, for: hashed.name)
                } catch {
                    Self.reportActionFailure(
                        "SHA-256 calculation failed: \(String(describing: error))"
                    )
                }
            }
        }
    }

    @MainActor
    private static func presentSHA256(_ digest: String, for name: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "\(name) 的 SHA-256"
        alert.informativeText = digest
        alert.addButton(withTitle: "完成")
        alert.addButton(withTitle: "复制哈希")
        if alert.runModal() == .alertSecondButtonReturn {
            Self.writeToPasteboard(digest)
        }
    }

    private static func fileInformationReport(
        _ information: FileItemInformation
    ) -> String {
        var lines = [
            "路径：\(information.url.path)",
            "种类：\(displayName(for: information.kind))"
        ]
        if let type = information.localizedTypeDescription {
            lines.append("类型：\(type)")
        }
        if let identifier = information.contentTypeIdentifier {
            lines.append("UTI：\(identifier)")
        }
        if let size = information.logicalSizeInBytes {
            lines.append(
                "大小：\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
            )
        }
        if let allocated = information.allocatedSizeInBytes {
            lines.append(
                "占用空间：\(ByteCountFormatter.string(fromByteCount: allocated, countStyle: .file))"
            )
        }
        if let creationDate = information.creationDate {
            lines.append("创建：\(localizedDate(creationDate))")
        }
        if let modificationDate = information.modificationDate {
            lines.append("修改：\(localizedDate(modificationDate))")
        }
        if let permissions = information.posixPermissions {
            lines.append("权限：\(String(format: "%04o", permissions))")
        }
        lines.append("可读：\(information.isReadable ? "是" : "否")")
        lines.append("可写：\(information.isWritable ? "是" : "否")")
        if let digest = information.sha256 {
            lines.append("SHA-256：\(digest)")
        }
        return lines.joined(separator: "\n")
    }

    private static func displayName(for kind: FileItemKind) -> String {
        switch kind {
        case .regularFile: "文件"
        case .directory: "目录"
        case .symbolicLink: "符号链接"
        case .alias: "Finder 替身"
        case .other: "其他"
        }
    }

    private static func localizedDate(_ date: Date) -> String {
        DateFormatter.localizedString(
            from: date,
            dateStyle: .medium,
            timeStyle: .medium
        )
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

private final class ApplicationMenuIconCache: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [String: NSImage] = [:]

    func image(forKey key: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return images[key]
    }

    func insert(_ image: NSImage, forKey key: String) {
        lock.lock()
        images[key] = image
        lock.unlock()
    }
}

private func directoryExists(_ url: URL) -> Bool {
    var isDirectory = ObjCBool(false)
    return FileManager.default.fileExists(
        atPath: url.path,
        isDirectory: &isDirectory
    ) && isDirectory.boolValue
}
