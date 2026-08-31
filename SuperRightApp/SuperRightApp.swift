import AppKit
import SwiftUI
import SuperRightCore

@main
struct SuperRightApp: App {
    @NSApplicationDelegateAdaptor(MagicRightApplicationDelegate.self)
    private var applicationDelegate
    @StateObject private var settingsWindowRoute = SettingsWindowRoute.shared
    @StateObject private var directoryHistory = DirectoryHistoryModel()
    @StateObject private var toolboxConfiguration = ToolboxConfigurationModel()
    @StateObject private var loginItem = LoginItemModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(toolboxConfiguration)
        } label: {
            MenuBarRouteLabel(route: settingsWindowRoute)
        }
        .menuBarExtraStyle(.menu)

        WindowGroup("Magic Right", id: "settings") {
            SettingsRootView()
                .environmentObject(directoryHistory)
                .environmentObject(toolboxConfiguration)
                .environmentObject(loginItem)
        }
        .handlesExternalEvents(matching: ["settings"])
        .defaultSize(width: 1120, height: 760)
        .defaultLaunchBehavior(.suppressed)
    }
}

@MainActor
private final class MagicRightApplicationDelegate: NSObject, NSApplicationDelegate {
    private var hostActionTail: Task<Void, Never>?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let currentApplication = NSRunningApplication.current
        let otherApplications = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).filter {
            $0.processIdentifier != currentApplication.processIdentifier && !$0.isTerminated
        }
        guard !otherApplications.isEmpty else { return }

        let winner = (otherApplications + [currentApplication]).max {
            launchPriority(for: $0) < launchPriority(for: $1)
        }

        guard winner?.processIdentifier == currentApplication.processIdentifier else {
            currentApplication.terminate()
            return
        }

        for application in otherApplications {
            application.terminate()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "magicright" {
            switch url.host {
            case "settings":
                SettingsWindowRoute.shared.requestOpen()
            case "action":
                consumeHostAction(from: url)
            default:
                continue
            }
        }
    }

    private func consumeHostAction(from url: URL) {
        guard let identifier = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems?.first(where: { $0.name == "id" })?.value,
              let id = UUID(uuidString: identifier) else {
            presentHostActionFailure("请求标识无效。")
            return
        }

        let key = HostActionRequest.storageKey(for: id)
        SharedDefaults.store.synchronize()
        guard let data = SharedDefaults.store.data(forKey: key),
              let request = try? JSONDecoder().decode(
                HostActionRequest.self,
                from: data
              ),
              request.id == id,
              request.isFresh() else {
            SharedDefaults.store.removeObject(forKey: key)
            presentHostActionFailure("请求不存在或已经过期。")
            return
        }
        SharedDefaults.store.removeObject(forKey: key)
        SharedDefaults.store.synchronize()

        let predecessor = hostActionTail
        let action = request.action
        hostActionTail = Task { [weak self] in
            await predecessor?.value
            guard let self else { return }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try Self.performHostAction(action)
                }.value
                self.presentHostActionResult(result)
            } catch {
                let message = (error as? any LocalizedError)?.errorDescription
                    ?? String(describing: error)
                self.presentHostActionFailure(message)
            }
        }
    }

    nonisolated private static func performHostAction(
        _ action: HostAction
    ) throws -> HostActionResult {
        switch action {
        case let .archive(sourceURLs, destinationDirectory):
            let validatedSources = try validateSupportedFileURLs(sourceURLs)
            let validatedDestination = try validateSupportedDirectoryURL(
                destinationDirectory
            )
            let result = try ArchiveService().archive(
                urls: validatedSources,
                destinationDirectory: validatedDestination
            )
            let validatedArchiveURL = try validateSupportedFileURLs(
                [result.archiveURL]
            )[0]
            return .reveal([validatedArchiveURL], failureMessages: [])

        case let .codexHere(directoryURL, codexExecutableURL, terminal):
            let validatedDirectory = try validateSupportedDirectoryURL(directoryURL)
            let validatedCodex = try validateCodexExecutableURL(codexExecutableURL)
            switch terminal {
            case .terminal:
                try SystemTerminalCodexService().launch(
                    directoryURL: validatedDirectory,
                    codexExecutableURL: validatedCodex
                )
                return .completed
            case .ghostty, .tabby:
                return .openApplication(
                    try ApplicationOpenRequestBuilder.makeCodexHereRequest(
                        terminal: terminal,
                        codexExecutableURL: validatedCodex,
                        intent: .currentDirectory(validatedDirectory)
                    )
                )
            }

        case let .extract(archiveURLs):
            let validatedArchives = try validateSupportedFileURLs(archiveURLs)
            var destinations: [URL] = []
            var failureMessages: [String] = []
            for archiveURL in validatedArchives {
                do {
                    let destinationDirectory = try validateSupportedDirectoryURL(
                        archiveURL.deletingLastPathComponent()
                    )
                    let result = try ArchiveService().extract(
                        url: archiveURL,
                        destinationDirectory: destinationDirectory
                    )
                    destinations.append(
                        try validateSupportedDirectoryURL(
                            result.destinationDirectoryURL
                        )
                    )
                } catch {
                    let description = (error as? any LocalizedError)?.errorDescription
                        ?? String(describing: error)
                    failureMessages.append(
                        "\(archiveURL.lastPathComponent)：\(description)"
                    )
                }
            }
            guard !destinations.isEmpty else {
                throw HostActionExecutionError.allOperationsFailed(failureMessages)
            }
            return .reveal(
                destinations,
                failureMessages: failureMessages
            )

        case let .copyGitRelativePaths(itemURLs):
            let validatedItems = try validateSupportedFileURLs(itemURLs)
            let service = GitRepositoryService()
            let values = try validatedItems.map { itemURL in
                let rootURL = try validateSupportedDirectoryURL(
                    service.repositoryRoot(containing: itemURL)
                )
                return try service.relativePath(of: itemURL, in: rootURL)
            }
            return .copyText(values.joined(separator: "\n"))

        case let .copyOriginURL(itemURL):
            let validatedItem = try validateSupportedFileURLs([itemURL])[0]
            let service = GitRepositoryService()
            let rootURL = try validateSupportedDirectoryURL(
                service.repositoryRoot(containing: validatedItem)
            )
            return .copyText(try service.origin(forRepositoryAt: rootURL))

        case let .navigateFinder(directoryURL):
            let validatedDirectory = try validateSupportedDirectoryURL(directoryURL)
            try FinderNavigationService().navigateCurrentWindow(
                to: validatedDirectory
            )
            return .completed

        case let .openGitRoot(itemURL):
            let validatedItem = try validateSupportedFileURLs([itemURL])[0]
            return .open(try validateSupportedDirectoryURL(
                GitRepositoryService().repositoryRoot(containing: validatedItem)
            ))

        case let .openGitRootInEditor(itemURL):
            let validatedItem = try validateSupportedFileURLs([itemURL])[0]
            return .openInEditor(try validateSupportedDirectoryURL(
                GitRepositoryService().repositoryRoot(containing: validatedItem)
            ))

        case let .openOrigin(itemURL):
            let validatedItem = try validateSupportedFileURLs([itemURL])[0]
            let service = GitRepositoryService()
            let rootURL = try validateSupportedDirectoryURL(
                service.repositoryRoot(containing: validatedItem)
            )
            let origin = try service.origin(forRepositoryAt: rootURL)
            return .open(try service.openableOriginURL(for: origin))
        }
    }

    nonisolated private static func validateSupportedFileURLs(
        _ urls: [URL]
    ) throws -> [URL] {
        guard !urls.isEmpty else { throw HostActionExecutionError.emptySelection }
        return try urls.map { url in
            guard url.isFileURL else {
                throw HostActionExecutionError.unsupportedPath(url)
            }
            let resolvedURL = url.standardizedFileURL
                .resolvingSymlinksInPath()
                .standardizedFileURL
            guard fileSystemItemExistsIncludingSymbolicLink(resolvedURL),
                  isSupportedResolvedFileURL(resolvedURL) else {
                throw HostActionExecutionError.unsupportedPath(url)
            }
            return resolvedURL
        }
    }

    nonisolated private static func validateSupportedDirectoryURL(
        _ url: URL
    ) throws -> URL {
        let resolvedURL = try validateSupportedFileURLs([url])[0]
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(
            atPath: resolvedURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw HostActionExecutionError.unsupportedPath(url)
        }
        return resolvedURL
    }

    nonisolated private static func validateCodexExecutableURL(
        _ url: URL
    ) throws -> URL {
        let candidate = url.standardizedFileURL
        guard candidate.isFileURL,
              FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw HostActionExecutionError.unsupportedPath(url)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        var trustedPaths = Set([
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            home.appendingPathComponent(".local/bin/codex").path,
            home.appendingPathComponent(".npm-global/bin/codex").path,
            home.appendingPathComponent(".volta/bin/codex").path
        ])
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            trustedPaths.formUnion(path.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true)
                    .appendingPathComponent("codex", isDirectory: false)
                    .standardizedFileURL.path
            })
        }
        if trustedPaths.contains(candidate.path) {
            return candidate
        }

        var ancestor = candidate.deletingLastPathComponent()
        while ancestor.path != "/" {
            if ancestor.pathExtension == "app" {
                let bundledCodex = ancestor
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent("codex", isDirectory: false)
                if Bundle(url: ancestor)?.bundleIdentifier == "com.openai.codex",
                   candidate.path == bundledCodex.path {
                    return candidate
                }
                break
            }
            ancestor.deleteLastPathComponent()
        }
        throw HostActionExecutionError.unsupportedPath(url)
    }

    nonisolated private static func isSupportedResolvedFileURL(
        _ url: URL
    ) -> Bool {
        let components = url.pathComponents
        return supportedFileRootComponents.contains {
            components.count >= $0.count
                && components.prefix($0.count).elementsEqual($0)
        }
    }

    nonisolated private static func fileSystemItemExistsIncludingSymbolicLink(
        _ url: URL
    ) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    nonisolated private static let supportedFileRootComponents = [
        URL(fileURLWithPath: "/Users", isDirectory: true),
        URL(fileURLWithPath: "/Volumes", isDirectory: true),
        URL(fileURLWithPath: "/private/tmp", isDirectory: true)
    ].map(\.standardizedFileURL.pathComponents)

    private func presentHostActionResult(_ result: HostActionResult) {
        switch result {
        case let .reveal(urls, failureMessages):
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            if !failureMessages.isEmpty {
                presentPartialHostActionFailure(failureMessages)
            }
        case let .open(url):
            guard NSWorkspace.shared.open(url) else {
                presentHostActionFailure("系统无法打开目标。")
                return
            }
        case let .copyText(value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        case let .openInEditor(rootURL):
            openRepositoryInPreferredEditor(rootURL)
        case let .openApplication(request):
            openApplicationRequest(request)
        case .completed:
            break
        }
    }

    private func openRepositoryInPreferredEditor(_ rootURL: URL) {
        guard let descriptor = preferredEditorDescriptor() else {
            presentHostActionFailure("请先在“应用动作”中启用一个编辑器。")
            return
        }
        do {
            let request = try ApplicationOpenRequestBuilder.makeRequest(
                for: descriptor,
                intent: .selection([rootURL])
            )
            openApplicationRequest(request)
        } catch {
            presentHostActionFailure(String(describing: error))
        }
    }

    private func openApplicationRequest(_ request: ApplicationOpenRequest) {
        guard let application = NSWorkspaceApplicationLocator().locateApplication(
            bundleIdentifier: request.applicationBundleIdentifier
        ) else {
            presentHostActionFailure("找不到所选终端或编辑器。")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        switch request {
        case let .openURLs(openRequest):
            NSWorkspace.shared.open(
                openRequest.urls,
                withApplicationAt: application.applicationURL,
                configuration: configuration
            )
        case let .structuredLaunch(launchRequest):
            configuration.arguments = launchRequest.argumentValues
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(
                at: application.applicationURL,
                configuration: configuration
            )
        }
    }

    private func preferredEditorDescriptor() -> ApplicationDescriptor? {
        let preferences: ApplicationPreferences
        if let data = SharedDefaults.store.data(
            forKey: SharedDefaults.applicationPreferencesKey
        ), let decoded = try? JSONDecoder().decode(
            ApplicationPreferences.self,
            from: data
        ) {
            preferences = decoded.addingMissingDeveloperDefaults()
        } else {
            preferences = .developerDefaults
        }
        let registry = ApplicationRegistry(
            preferences: preferences,
            locator: NSWorkspaceApplicationLocator()
        )
        let enabled = registry.visibleEnabledApplications()
        let identifiers = [
            "dev.zed.Zed", "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92", "com.vscodium",
            "com.sublimetext.4", "com.panic.Nova",
            "com.jetbrains.intellij", "com.jetbrains.intellij.ce",
            "com.jetbrains.pycharm", "com.jetbrains.pycharm.ce",
            "com.jetbrains.WebStorm", "com.jetbrains.CLion",
            "com.jetbrains.goland", "com.jetbrains.rider"
        ]
        for identifier in identifiers {
            if let application = enabled.first(where: {
                $0.bundleIdentifier == identifier
            }) {
                return application.descriptor
            }
        }
        return nil
    }

    private func presentHostActionFailure(_ message: String) {
        NSSound.beep()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Magic Right 操作失败"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func presentPartialHostActionFailure(_ messages: [String]) {
        guard !messages.isEmpty else { return }
        NSSound.beep()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "部分项目未完成"
        alert.informativeText = messages.joined(separator: "\n")
        alert.addButton(withTitle: "好")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func launchPriority(
        for application: NSRunningApplication
    ) -> LaunchPriority {
        let executableDate = application.executableURL.flatMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        } ?? .distantPast

        return LaunchPriority(
            executableDate: executableDate,
            // For identical binaries, keep the process that was already running.
            inverseProcessIdentifier: -application.processIdentifier
        )
    }
}

private enum HostActionResult: Sendable {
    case reveal([URL], failureMessages: [String])
    case open(URL)
    case copyText(String)
    case openInEditor(URL)
    case openApplication(ApplicationOpenRequest)
    case completed
}

private enum HostActionExecutionError: Error, Sendable {
    case emptySelection
    case allOperationsFailed([String])
    case preferredEditorUnavailable
    case unsupportedPath(URL)
}

extension HostActionExecutionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptySelection:
            "没有可处理的 Finder 项目。"
        case let .allOperationsFailed(messages):
            messages.isEmpty
                ? "所有操作均未完成。"
                : messages.joined(separator: "\n")
        case .preferredEditorUnavailable:
            "请先在“应用动作”中启用一个编辑器。"
        case let .unsupportedPath(url):
            "该路径不存在、不可访问或不在 Magic Right 支持的范围内：\(url.path)"
        }
    }
}

private struct LaunchPriority: Comparable {
    let executableDate: Date
    let inverseProcessIdentifier: pid_t

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.executableDate != rhs.executableDate {
            return lhs.executableDate < rhs.executableDate
        }
        return lhs.inverseProcessIdentifier < rhs.inverseProcessIdentifier
    }
}

@MainActor
private final class SettingsWindowRoute: ObservableObject {
    static let shared = SettingsWindowRoute()

    @Published private(set) var pendingRequestID: UUID?

    private init() {}

    func requestOpen() {
        pendingRequestID = UUID()
    }

    func consume(_ requestID: UUID) {
        guard pendingRequestID == requestID else { return }
        pendingRequestID = nil
    }
}

private struct MenuBarRouteLabel: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var route: SettingsWindowRoute

    var body: some View {
        Image("MenuBarIcon")
            .accessibilityLabel("Magic Right")
            .onChange(of: route.pendingRequestID, initial: true) { _, requestID in
                guard let requestID else { return }
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
                route.consume(requestID)
            }
    }
}

private struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SharedDefaults.directoryLearningEnabledKey, store: SharedDefaults.store)
    private var directoryLearningEnabled = true

    private var learningToggle: Binding<Bool> {
        Binding(
            get: {
                SharedDefaults.isSharedStorageAvailable && directoryLearningEnabled
            },
            set: { isEnabled in
                guard SharedDefaults.isSharedStorageAvailable else { return }
                directoryLearningEnabled = isEnabled
            }
        )
    }

    var body: some View {
        Toggle("学习常用目录", isOn: learningToggle)
            .disabled(!SharedDefaults.isSharedStorageAvailable)
            .help(
                SharedDefaults.isSharedStorageAvailable
                    ? "只记录目录路径、访问次数和时间"
                    : "共享存储不可用，目录学习已关闭"
            )

        Button {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        } label: {
            Label("设置…", systemImage: "gearshape")
        }

        Divider()

        Button("退出 Magic Right") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}
