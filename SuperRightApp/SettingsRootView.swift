import AppKit
import SwiftUI
import SuperRightCore

private enum ToolboxTheme {
    static let electricCyan = Color(nsColor: .controlAccentColor)
    static let graphite = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let secondaryText = Color.secondary
}

private enum ToolboxPage: String, CaseIterable, Identifiable {
    case overview
    case openWith
    case newFile
    case directories
    case pathsAndGit
    case fileTools
    case archives
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Finder 菜单"
        case .openWith: "应用动作"
        case .newFile: "创建文件"
        case .directories: "智能目录"
        case .pathsAndGit: "路径与仓库"
        case .fileTools: "文件操作"
        case .archives: "归档"
        case .settings: "偏好设置"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "查看菜单构成与动作状态"
        case .openWith: "编辑器、终端与开发工具"
        case .newFile: "七种内置文件模板"
        case .directories: "固定、常用、最近目的地"
        case .pathsAndGit: "路径复制与仓库上下文"
        case .fileTools: "安全移动、复制与操作记录"
        case .archives: "系统归档格式"
        case .settings: "扩展、预设和权限"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .openWith: "macwindow"
        case .newFile: "doc.badge.plus"
        case .directories: "folder.badge.gearshape"
        case .pathsAndGit: "point.bottomleft.forward.to.point.topright.scurvepath"
        case .fileTools: "wrench.and.screwdriver"
        case .archives: "archivebox"
        case .settings: "gearshape"
        }
    }

    var actions: [ToolboxAction] {
        switch self {
        case .overview, .settings:
            []
        case .openWith:
            [.openWith, .codexHere]
        case .newFile:
            [
                .newMarkdown, .newPlainText, .newRichText, .newXML,
                .newJSON, .newYAML, .newGitignore
            ]
        case .directories:
            [.frequentDirectories]
        case .pathsAndGit:
            [
                .copyAbsolutePath, .copyShellPath,
                .copyGitRelativePath, .openGitRoot, .openGitRootInEditor,
                .openOrigin, .copyOriginURL
            ]
        case .fileTools:
            [.moveTo, .copyTo, .cut, .paste, .fileInfo, .createAlias]
        case .archives:
            [.archive, .unarchive]
        }
    }

    static let featurePages: [ToolboxPage] = [
        .openWith, .newFile, .directories, .pathsAndGit, .fileTools, .archives
    ]
}

struct SettingsRootView: View {
    @State private var selectedPage: ToolboxPage? = .overview
    @StateObject private var applicationRegistry = ApplicationRegistryModel()
    @EnvironmentObject private var directoryHistory: DirectoryHistoryModel
    @EnvironmentObject private var toolbox: ToolboxConfigurationModel
    @EnvironmentObject private var loginItem: LoginItemModel

    var body: some View {
        NavigationSplitView {
            List(ToolboxPage.allCases, selection: $selectedPage) { page in
                SidebarPageRow(
                    page: page,
                    counts: counts(for: page)
                )
                .tag(page)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 185, ideal: 200, max: 225)
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
        } detail: {
            ZStack {
                ToolboxTheme.graphite
                    .ignoresSafeArea()

                ScrollView {
                    pageContent(selectedPage ?? .overview)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 22)
                }
            }
        }
        .tint(ToolboxTheme.electricCyan)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            toolbox.reload()
            applicationRegistry.scan()
            loginItem.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            loginItem.refresh()
        }
    }

    @ViewBuilder
    private func pageContent(_ page: ToolboxPage) -> some View {
        switch page {
        case .overview:
            OverviewPage(
                selectedPage: Binding(
                    get: { selectedPage ?? .overview },
                    set: { selectedPage = $0 }
                ),
                toolbox: toolbox,
                applications: applicationRegistry
            )
        case .openWith:
            OpenWithPage(
                toolbox: toolbox,
                applications: applicationRegistry
            )
        case .newFile, .pathsAndGit, .fileTools, .archives:
            ToolboxActionListPage(page: page, model: toolbox)
        case .directories:
            DirectoryLearningPage(model: directoryHistory, toolbox: toolbox)
        case .settings:
            GeneralSettingsPage(toolbox: toolbox, loginItem: loginItem)
        }
    }

    private func counts(for page: ToolboxPage) -> FeatureCounts? {
        guard page != .overview, page != .settings else { return nil }
        if page == .openWith {
            let enabledApps = applicationRegistry.applications.filter(
                applicationRegistry.isEnabled
            ).count
            return FeatureCounts(
                enabled: enabledApps + (toolbox.isEnabled(.codexHere) ? 1 : 0),
                available: applicationRegistry.applications.count + 1
            )
        }
        return FeatureCounts(
            enabled: toolbox.enabledCount(in: page.actions),
            available: toolbox.availableCount(in: page.actions)
        )
    }
}

private struct FeatureCounts {
    let enabled: Int
    let available: Int
}

private struct SidebarPageRow: View {
    let page: ToolboxPage
    let counts: FeatureCounts?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: page.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ToolboxTheme.electricCyan)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(page.title)
                    .font(.system(size: 14, weight: .semibold))
                if let counts {
                    Text("\(counts.enabled) 已启用 / \(counts.available) 可用")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
        }
        .frame(minHeight: 38)
        .contentShape(Rectangle())
    }
}

private struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 26, weight: .semibold))
            Text(subtitle)
                .foregroundStyle(ToolboxTheme.secondaryText)
                .font(.callout)
        }
    }
}

private struct OverviewPage: View {
    @Binding var selectedPage: ToolboxPage
    @ObservedObject var toolbox: ToolboxConfigurationModel
    @ObservedObject var applications: ApplicationRegistryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "Finder 菜单",
                subtitle: "启用的动作直接显示在 Finder 右键第一级；不适用的动作会自动隐藏。"
            )

            VStack(spacing: 0) {
                ForEach(ToolboxPage.featurePages) { page in
                    Button {
                        selectedPage = page
                    } label: {
                        GroupSummaryCard(
                            page: page,
                            counts: counts(for: page)
                        )
                    }
                    .buttonStyle(.plain)
                    if page != ToolboxPage.featurePages.last {
                        Divider()
                    }
                }
            }
            .background(ToolboxTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(ToolboxTheme.border, lineWidth: 1)
            }

            if let errorMessage = toolbox.errorMessage {
                ErrorLabel(message: errorMessage)
            }
        }
    }

    private func counts(for page: ToolboxPage) -> FeatureCounts {
        if page == .openWith {
            let enabledApps = applications.applications.filter(
                applications.isEnabled
            ).count
            return FeatureCounts(
                enabled: enabledApps + (toolbox.isEnabled(.codexHere) ? 1 : 0),
                available: applications.applications.count + 1
            )
        }
        return FeatureCounts(
            enabled: toolbox.enabledCount(in: page.actions),
            available: toolbox.availableCount(in: page.actions)
        )
    }
}

private struct GroupSummaryCard: View {
    let page: ToolboxPage
    let counts: FeatureCounts

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: page.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ToolboxTheme.electricCyan)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(page.subtitle)
                    .font(.caption)
                    .foregroundStyle(ToolboxTheme.secondaryText)
            }
            Spacer()
            Text("\(counts.enabled) / \(counts.available)")
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(counts.enabled > 0 ? ToolboxTheme.electricCyan : .secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

private struct ToolboxActionListPage: View {
    let page: ToolboxPage
    @ObservedObject var model: ToolboxConfigurationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ActionGroupHeader(
                title: page.title,
                subtitle: page.subtitle,
                enabledCount: model.enabledCount(in: page.actions),
                availableCount: model.availableCount(in: page.actions),
                enableAll: { model.setEnabled(true, for: page.actions) },
                disableAll: { model.setEnabled(false, for: page.actions) }
            )

            ActionRowsContainer(actions: page.actions, model: model)

            if let errorMessage = model.errorMessage {
                ErrorLabel(message: errorMessage)
            }
        }
    }
}

private struct ActionGroupHeader: View {
    let title: String
    let subtitle: String
    let enabledCount: Int
    let availableCount: Int
    let enableAll: () -> Void
    let disableAll: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            PageHeader(title: title, subtitle: subtitle)
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Text("\(enabledCount) 已启用 / \(availableCount) 可用")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ToolboxTheme.secondaryText)
                HStack(spacing: 8) {
                    Button("启用全部可用", action: enableAll)
                        .disabled(availableCount == 0 || enabledCount == availableCount)
                    Button("全部关闭", action: disableAll)
                        .disabled(enabledCount == 0)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }
}

private struct ActionRowsContainer: View {
    let actions: [ToolboxAction]
    @ObservedObject var model: ToolboxConfigurationModel
    var onChange: ((ToolboxAction, Bool) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                ToolboxActionRow(
                    action: action,
                    model: model,
                    onChange: onChange
                )
                if index < actions.count - 1 {
                    Divider().opacity(0.35)
                }
            }
        }
        .background(ToolboxTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(ToolboxTheme.border, lineWidth: 1)
        }
    }
}

private struct ToolboxActionRow: View {
    let action: ToolboxAction
    @ObservedObject var model: ToolboxConfigurationModel
    var onChange: ((ToolboxAction, Bool) -> Void)? = nil

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { action.isImplemented && model.isEnabled(action) },
            set: { newValue in
                model.setEnabled(newValue, for: action)
                onChange?(action, newValue)
            }
        )
    }

    var body: some View {
        Toggle(isOn: isEnabled) {
            HStack(spacing: 12) {
                Image(systemName: action.presentationSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        action.isImplemented
                            ? ToolboxTheme.electricCyan
                            : Color.secondary
                    )
                    .frame(width: 32, height: 32)
                    .background(
                        action.isImplemented
                            ? ToolboxTheme.electricCyan.opacity(0.11)
                            : Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 8)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(action.presentationName)
                        .font(.system(size: 15, weight: .semibold))
                    Text(action.presentationDescription)
                        .font(.caption)
                        .foregroundStyle(ToolboxTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 16)
                ActionStatusBadge(
                    isImplemented: action.isImplemented,
                    isEnabled: model.isEnabled(action)
                )
            }
            .contentShape(Rectangle())
        }
        .toggleStyle(.switch)
        .controlSize(.regular)
        .disabled(!action.isImplemented)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct ActionStatusBadge: View {
    let isImplemented: Bool
    let isEnabled: Bool
    var isBlockedByParent = false

    private var title: String {
        if !isImplemented { return "开发中" }
        if isEnabled && isBlockedByParent { return "待总开关" }
        return isEnabled ? "已启用" : "已关闭"
    }

    private var color: Color {
        if !isImplemented { return .secondary }
        if isEnabled && isBlockedByParent { return ToolboxTheme.secondaryText }
        return isEnabled ? ToolboxTheme.electricCyan : ToolboxTheme.secondaryText
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .frame(minWidth: 52, alignment: .trailing)
    }
}

private struct OpenWithPage: View {
    @ObservedObject var toolbox: ToolboxConfigurationModel
    @ObservedObject var applications: ApplicationRegistryModel

    private var enabledCount: Int {
        applications.applications.filter(applications.isEnabled).count
            + (toolbox.isEnabled(.codexHere) ? 1 : 0)
    }

    private var availableCount: Int {
        applications.applications.count + 1
    }

    private var isMenuEnabled: Binding<Bool> {
        Binding(
            get: { toolbox.isEnabled(.openWith) },
            set: { toolbox.setEnabled($0, for: .openWith) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ActionGroupHeader(
                title: ToolboxPage.openWith.title,
                subtitle: ToolboxPage.openWith.subtitle,
                enabledCount: enabledCount,
                availableCount: availableCount,
                enableAll: enableAll,
                disableAll: disableAll
            )

            CodexHereToggleRow(toolbox: toolbox)

            Toggle(isOn: isMenuEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("在 Finder 中显示应用动作")
                        .font(.system(size: 15, weight: .semibold))
                    Text("关闭时保留下面每个 App 的选择，重新开启即可恢复。")
                        .font(.caption)
                        .foregroundStyle(ToolboxTheme.secondaryText)
                }
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(ToolboxTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(ToolboxTheme.border, lineWidth: 1)
            }

            HStack {
                Text("应用")
                    .font(.headline)
                Spacer()
                Button("重新扫描") {
                    applications.scan(userInitiated: true)
                }
                .help("重新查询 Launch Services 中的预置 App 和手动添加的 App")
                Button {
                    applications.chooseAndAddApplication()
                } label: {
                    Label("添加其他 App…", systemImage: "plus")
                }
            }

            if let scanMessage = applications.lastScanMessage {
                Label(scanMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(ToolboxTheme.secondaryText)
            }

            VStack(spacing: 0) {
                if applications.applications.isEmpty {
                    ContentUnavailableView(
                        "没有发现可用 App",
                        systemImage: "app.dashed",
                        description: Text("安装编辑器或终端，或手动选择任意 App。")
                    )
                    .padding(26)
                } else {
                    ForEach(
                        Array(applications.applications.enumerated()),
                        id: \.element.id
                    ) { index, application in
                        ApplicationToggleRow(
                            application: application,
                            model: applications,
                            isMenuEnabled: toolbox.isEnabled(.openWith)
                        )
                        if index < applications.applications.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
            .background(ToolboxTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(ToolboxTheme.border, lineWidth: 1)
            }

            if let errorMessage = applications.errorMessage ?? toolbox.errorMessage {
                ErrorLabel(message: errorMessage)
            }
        }
    }

    private func enableAll() {
        toolbox.setEnabled(true, for: ToolboxPage.openWith.actions)
        for application in applications.applications {
            applications.setEnabled(true, for: application)
        }
    }

    private func disableAll() {
        toolbox.setEnabled(false, for: ToolboxPage.openWith.actions)
        disableApplications()
    }

    private func disableApplications() {
        for application in applications.applications {
            applications.setEnabled(false, for: application)
        }
    }
}

private struct CodexHereToggleRow: View {
    @ObservedObject var toolbox: ToolboxConfigurationModel
    @AppStorage(
        SharedDefaults.codexHereTerminalKey,
        store: SharedDefaults.store
    ) private var selectedTerminalRaw = CodexHereTerminal.defaultValue.rawValue

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { toolbox.isEnabled(.codexHere) },
            set: { toolbox.setEnabled($0, for: .codexHere) }
        )
    }

    private var selectedTerminal: CodexHereTerminal {
        let configured = CodexHereTerminal(rawValue: selectedTerminalRaw)
            ?? .defaultValue
        return CodexHerePresentation.isAvailable(configured)
            ? configured
            : .terminal
    }

    private var terminalSelection: Binding<CodexHereTerminal> {
        Binding(
            get: { selectedTerminal },
            set: { terminal in
                selectedTerminalRaw = terminal.rawValue
                SharedDefaults.store.synchronize()
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Toggle(isOn: isEnabled) {
                HStack(spacing: 12) {
                    Image(nsImage: CodexHerePresentation.icon(size: 32))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Codex Here!")
                            .font(.system(size: 15, weight: .semibold))
                        Text(CodexHerePresentation.statusDescription(
                            terminal: selectedTerminal
                        ))
                            .font(.caption)
                            .foregroundStyle(ToolboxTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 16)
                    ActionStatusBadge(
                        isImplemented: true,
                        isEnabled: toolbox.isEnabled(.codexHere)
                    )
                }
                .contentShape(Rectangle())
            }
            .toggleStyle(.switch)
            .controlSize(.regular)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.35)

            HStack(spacing: 12) {
                Label("运行终端", systemImage: "terminal")
                    .font(.callout.weight(.medium))
                Spacer()
                Picker("运行终端", selection: terminalSelection) {
                    ForEach(CodexHereTerminal.allCases) { terminal in
                        Text(
                            CodexHerePresentation.isAvailable(terminal)
                                ? terminal.displayName
                                : "\(terminal.displayName)（未安装）"
                        )
                        .tag(terminal)
                        .disabled(!CodexHerePresentation.isAvailable(terminal))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(ToolboxTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(ToolboxTheme.border, lineWidth: 1)
        }
        .onAppear {
            guard selectedTerminalRaw != selectedTerminal.rawValue else { return }
            selectedTerminalRaw = selectedTerminal.rawValue
            SharedDefaults.store.synchronize()
        }
    }
}

private enum CodexHerePresentation {
    private static let codexBundleIdentifier = "com.openai.codex"

    static func statusDescription(terminal: CodexHereTerminal) -> String {
        guard codexCLIExists else { return "未检测到 Codex CLI" }
        guard isAvailable(terminal) else { return "\(terminal.displayName) 未安装" }
        return "在当前目录用 \(terminal.displayName) 启动 Codex"
    }

    static func isAvailable(_ terminal: CodexHereTerminal) -> Bool {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: terminal.bundleIdentifier
        ) != nil
    }

    static func icon(size: CGFloat) -> NSImage {
        let fallback = NSImage(
            systemSymbolName: "terminal",
            accessibilityDescription: "Codex"
        ) ?? NSImage(size: NSSize(width: size, height: size))
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: codexBundleIdentifier
        ) else {
            fallback.size = NSSize(width: size, height: size)
            return fallback
        }

        let resourcesURL = applicationURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        for resourceName in ["icon-codex-dark-color.png", "icon-codex-light.png"] {
            if let image = NSImage(
                contentsOf: resourcesURL.appendingPathComponent(resourceName)
            ) {
                image.size = NSSize(width: size, height: size)
                return image
            }
        }

        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    private static var codexCLIExists: Bool {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            home.appendingPathComponent(".local/bin/codex"),
            home.appendingPathComponent(".npm-global/bin/codex"),
            home.appendingPathComponent(".volta/bin/codex")
        ]
        return candidates.contains {
            fileManager.isExecutableFile(atPath: $0.path)
        }
    }
}

private struct ApplicationToggleRow: View {
    let application: DetectedApplication
    @ObservedObject var model: ApplicationRegistryModel
    let isMenuEnabled: Bool

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { model.isEnabled(application) },
            set: { model.setEnabled($0, for: application) }
        )
    }

    var body: some View {
        Toggle(isOn: isEnabled) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(
                    forFile: application.currentApplicationURL.path
                ))
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(application.menuDisplayName)
                        .font(.system(size: 15, weight: .semibold))
                    Text(application.bundleIdentifier)
                        .font(.caption)
                        .foregroundStyle(ToolboxTheme.secondaryText)
                }
                Spacer(minLength: 16)
                ActionStatusBadge(
                    isImplemented: true,
                    isEnabled: model.isEnabled(application),
                    isBlockedByParent: !isMenuEnabled
                )
            }
            .contentShape(Rectangle())
        }
        .toggleStyle(.switch)
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct DirectoryLearningPage: View {
    @ObservedObject var model: DirectoryHistoryModel
    @ObservedObject var toolbox: ToolboxConfigurationModel
    @AppStorage(SharedDefaults.directoryLearningEnabledKey, store: SharedDefaults.store)
    private var directoryLearningEnabled = true
    @State private var searchText = ""
    @State private var showsClearConfirmation = false

    private var actions: [ToolboxAction] { ToolboxPage.directories.actions }
    private var sections: DirectoryHistorySections { model.sections }
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
        VStack(alignment: .leading, spacing: 22) {
            ActionGroupHeader(
                title: ToolboxPage.directories.title,
                subtitle: ToolboxPage.directories.subtitle,
                enabledCount: toolbox.enabledCount(in: actions),
                availableCount: toolbox.availableCount(in: actions),
                enableAll: { toolbox.setEnabled(true, for: actions) },
                disableAll: { toolbox.setEnabled(false, for: actions) }
            )

            ActionRowsContainer(actions: actions, model: toolbox)

            Text("本地学习")
                .font(.headline)
            Toggle(isOn: learningToggle) {
                HStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ToolboxTheme.electricCyan)
                        .frame(width: 32, height: 32)
                        .background(
                            ToolboxTheme.electricCyan.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("学习目录访问")
                            .font(.system(size: 15, weight: .semibold))
                        Text("路径、次数和时间只保存在本机；不扫描内容，也不联网。")
                            .font(.caption)
                            .foregroundStyle(ToolboxTheme.secondaryText)
                    }
                    Spacer()
                    ActionStatusBadge(
                        isImplemented: true,
                        isEnabled: SharedDefaults.isSharedStorageAvailable
                            && directoryLearningEnabled
                    )
                }
                .contentShape(Rectangle())
            }
            .toggleStyle(.switch)
            .controlSize(.regular)
            .disabled(!SharedDefaults.isSharedStorageAvailable)
            .help(
                SharedDefaults.isSharedStorageAvailable
                    ? "暂停后保留现有固定、常用与最近目录"
                    : "共享存储不可用，目录学习已关闭"
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(ToolboxTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(ToolboxTheme.border, lineWidth: 1)
            }

            DirectorySummaryStrip(sections: sections)

            DirectorySectionList(
                title: "固定",
                entries: matching(sections.pinned),
                model: model
            )
            DirectorySectionList(
                title: "常用",
                entries: matching(sections.frequent),
                model: model
            )
            DirectorySectionList(
                title: "最近",
                entries: matching(sections.recent),
                model: model
            )

            if !model.excludedEntries.isEmpty {
                DirectorySectionList(
                    title: "已排除",
                    entries: matching(model.excludedEntries),
                    model: model,
                    showsRestore: true
                )
            }

            HStack {
                Spacer()
                Button("清空全部历史…", role: .destructive) {
                    showsClearConfirmation = true
                }
                .disabled(model.history.entries.isEmpty)
            }

            if let errorMessage = model.errorMessage ?? toolbox.errorMessage {
                ErrorLabel(message: errorMessage)
            }
        }
        .onAppear { model.reload() }
        .searchable(text: $searchText, prompt: "搜索目录名称或路径")
        .confirmationDialog(
            "清空全部目录历史？",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空全部历史", role: .destructive) {
                model.removeAll()
            }
        } message: {
            Text("固定、常用、最近和排除记录都会被删除，且无法撤销。")
        }
    }

    private func matching(
        _ entries: [DirectoryHistoryEntry]
    ) -> [DirectoryHistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            entry.displayName.localizedStandardContains(query)
                || entry.normalizedPath.localizedStandardContains(query)
        }
    }
}

private struct DirectorySummaryStrip: View {
    let sections: DirectoryHistorySections

    var body: some View {
        HStack(spacing: 12) {
            summary("固定", count: sections.pinned.count, symbol: "pin.fill")
            summary("常用", count: sections.frequent.count, symbol: "chart.line.uptrend.xyaxis")
            summary("最近", count: sections.recent.count, symbol: "clock.fill")
        }
    }

    private func summary(_ title: String, count: Int, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(ToolboxTheme.electricCyan)
            Text(title)
                .font(.callout.weight(.semibold))
            Spacer()
            Text("\(count)")
                .font(.title3.bold())
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(ToolboxTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(ToolboxTheme.border, lineWidth: 1)
        }
    }
}

private struct DirectorySectionList: View {
    let title: String
    let entries: [DirectoryHistoryEntry]
    @ObservedObject var model: DirectoryHistoryModel
    var showsRestore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(entries.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if entries.isEmpty {
                Text("暂无目录")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(20)
                    .background(ToolboxTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        DirectoryHistoryRow(
                            entry: entry,
                            model: model,
                            showsRestore: showsRestore
                        )
                        if index < entries.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
                .background(ToolboxTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(ToolboxTheme.border, lineWidth: 1)
                }
            }
        }
    }
}

private struct DirectoryHistoryRow: View {
    let entry: DirectoryHistoryEntry
    @ObservedObject var model: DirectoryHistoryModel
    let showsRestore: Bool
    @State private var showsRenameDialog = false
    @State private var proposedName = ""

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: entry.isPinned ? "folder.fill" : "folder")
                .font(.title3)
                .foregroundStyle(ToolboxTheme.electricCyan)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName)
                    .font(.system(size: 14, weight: .semibold))
                Text(entry.normalizedPath)
                    .font(.caption)
                    .foregroundStyle(ToolboxTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if showsRestore {
                Button("恢复") {
                    model.setExcluded(false, entry: entry)
                }
            } else {
                Button {
                    model.openInFinder(entry)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("在 Finder 中打开")
                .accessibilityLabel("在 Finder 中打开 \(entry.displayName)")

                Button {
                    model.togglePinned(entry)
                } label: {
                    Image(systemName: entry.isPinned ? "pin.slash" : "pin")
                }
                .buttonStyle(.borderless)
                .help(entry.isPinned ? "取消固定" : "固定")
                .accessibilityLabel(
                    entry.isPinned
                        ? "取消固定 \(entry.displayName)"
                        : "固定 \(entry.displayName)"
                )
            }

            Menu {
                if !showsRestore {
                    Button("重命名…") {
                        proposedName = entry.customName ?? entry.displayName
                        showsRenameDialog = true
                    }
                    Button(entry.isPinned ? "取消固定" : "固定") {
                        model.togglePinned(entry)
                    }
                    Button("排除此目录") {
                        model.setExcluded(true, entry: entry)
                    }
                }
                Button("删除记录", role: .destructive) {
                    model.remove(entry)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .alert("重命名目录", isPresented: $showsRenameDialog) {
            TextField("显示名称", text: $proposedName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                model.setCustomName(proposedName, entry: entry)
            }
            Button("恢复默认名称") {
                model.setCustomName(nil, entry: entry)
            }
        } message: {
            Text(entry.normalizedPath)
        }
    }
}

private struct GeneralSettingsPage: View {
    @ObservedObject var toolbox: ToolboxConfigurationModel
    @ObservedObject var loginItem: LoginItemModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                title: "设置",
                subtitle: "管理 Finder 扩展、启动与版本信息。"
            )

            GroupBox("Finder 扩展") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("启用状态") {
                        Text("由 macOS 系统设置管理")
                            .foregroundStyle(ToolboxTheme.secondaryText)
                    }
                    Text("在系统设置中启用或停用 Finder 右键扩展。")
                        .font(.callout)
                        .foregroundStyle(ToolboxTheme.secondaryText)
                    Button("打开扩展设置") {
                        guard let url = URL(
                            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
                        ) else { return }
                        NSWorkspace.shared.open(url)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            .groupBoxStyle(GraphiteGroupBoxStyle())

            GroupBox("启动") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        "登录时自动启动 Magic Right",
                        isOn: Binding(
                            get: { loginItem.isRegistered },
                            set: { loginItem.setEnabled($0) }
                        )
                    )
                    .disabled(!loginItem.canChangeRegistration)
                    Text(loginItem.statusDescription)
                        .font(.callout)
                        .foregroundStyle(ToolboxTheme.secondaryText)

                    if loginItem.requiresApproval {
                        Button("打开登录项设置") {
                            loginItem.openSystemSettings()
                        }
                        .buttonStyle(.bordered)
                    }

                    if let errorMessage = loginItem.errorMessage {
                        ErrorLabel(message: errorMessage)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            .groupBoxStyle(GraphiteGroupBoxStyle())

            GroupBox("快速配置") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("预设只影响内置动作；新发现的 App 始终由你单独选择。")
                        .foregroundStyle(ToolboxTheme.secondaryText)
                    HStack {
                        Button("开发") { toolbox.apply(.developer) }
                        Button("文件") { toolbox.apply(.file) }
                        Button("全部内置") { toolbox.apply(.all) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            .groupBoxStyle(GraphiteGroupBoxStyle())

            GroupBox("权限") {
                Text("首次访问受保护目录或使用当前窗口跳转时，macOS 会请求相应权限。")
                .foregroundStyle(ToolboxTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            .groupBoxStyle(GraphiteGroupBoxStyle())

            GroupBox("关于") {
                HStack(spacing: 16) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 72, height: 72)
                        .accessibilityLabel("Magic Right 图标")
                        .shadow(color: .black.opacity(0.14), radius: 5, y: 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Magic Right")
                            .font(.title3.weight(.semibold))
                        Text("开源的 Finder 右键工具箱")
                            .font(.callout)
                            .foregroundStyle(ToolboxTheme.secondaryText)
                        HStack(spacing: 7) {
                            Text("版本 \(AppVersionPresentation.version)")
                            Text("•")
                                .foregroundStyle(ToolboxTheme.secondaryText)
                            Text("构建 \(AppVersionPresentation.build)")
                        }
                        .font(.callout)
                        .monospacedDigit()
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            .groupBoxStyle(GraphiteGroupBoxStyle())

            if let errorMessage = toolbox.errorMessage {
                ErrorLabel(message: errorMessage)
            }
        }
    }
}

private enum AppVersionPresentation {
    static let version = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "0.1.0"

    static let build = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleVersion"
    ) as? String ?? "1"
}

private struct GraphiteGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.headline)
            configuration.content
        }
        .padding(18)
        .background(ToolboxTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(ToolboxTheme.border, lineWidth: 1)
        }
    }
}

private struct ErrorLabel: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

private extension ToolboxAction {
    var presentationName: String {
        switch self {
        case .newFile: "新建文件（旧配置）"
        case .newMarkdown: "Markdown 文件"
        case .newPlainText: "文本文件"
        case .newRichText: "富文本文件"
        case .newXML: "XML 文件"
        case .newJSON: "JSON 文件"
        case .newYAML: "YAML 文件"
        case .newGitignore: ".gitignore"
        case .moveTo: "移动到"
        case .copyTo: "复制到"
        case .cut: "剪切"
        case .paste: "粘贴"
        case .frequentDirectories: "在菜单中显示“跳转到”"
        case .archive: "压缩"
        case .unarchive: "解压"
        case .openWith: "在菜单中显示打开方式"
        case .codexHere: "Codex Here!"
        case .copyAbsolutePath: "复制绝对路径"
        case .copyShellPath: "复制 Shell 安全路径"
        case .copyFileURL: "已移除的旧版动作"
        case .copyGitRelativePath: "复制 Git 相对路径"
        case .openGitRoot: "打开 Git 根目录"
        case .openGitRootInEditor: "在编辑器中打开仓库"
        case .openOrigin: "打开 origin 页面"
        case .copyOriginURL: "复制 origin URL"
        case .fileInfo: "文件信息"
        case .createAlias: "创建替身"
        }
    }

    var presentationDescription: String {
        switch self {
        case .newFile: "旧版总开关，仅用于迁移历史设置。"
        case .newMarkdown: "创建空白 .md 文件并自动避让重名。"
        case .newPlainText: "创建空白 .txt 文件并在 Finder 中选中。"
        case .newRichText: "创建可被文本编辑器打开的有效 .rtf 文件。"
        case .newXML: "创建包含声明和根节点的有效 XML 文件。"
        case .newJSON: "创建有效的空 JSON 对象。"
        case .newYAML: "创建有效的 YAML 文档。"
        case .newGitignore: "创建隐藏的 .gitignore，已存在时安全编号。"
        case .moveTo: "移动到固定、常用或最近目录；自动避让重名并记录结果。"
        case .copyTo: "复制到固定、常用或最近目录；绝不静默覆盖。"
        case .cut: "把标准文件 URL 写入 macOS 系统剪贴板，其他 App 也能识别。"
        case .paste: "读取系统文件剪贴板；Magic Right 剪切时移动，其他来源按复制处理。"
        case .frequentDirectories: "显示“跳转到”，并与“移动到”“复制到”共用同一套目录。"
        case .archive: "使用系统 ZIP 或 tar.gz 格式压缩。"
        case .unarchive: "验证归档路径后解压到安全目录。"
        case .openWith: "显示已启用的编辑器、终端和开发工具。"
        case .codexHere: "使用设置中选择的终端，在当前目录启动 Codex。"
        case .copyAbsolutePath: "复制所选文件或目录的完整路径。"
        case .copyShellPath: "复制经过单引号转义的安全命令行路径。"
        case .copyFileURL: "仅用于读取旧配置，不再显示或执行。"
        case .copyGitRelativePath: "复制相对于当前仓库根目录的路径。"
        case .openGitRoot: "在 Finder 中定位当前仓库根目录。"
        case .openGitRootInEditor: "用首选编辑器打开整个仓库。"
        case .openOrigin: "在浏览器打开当前仓库的远程页面。"
        case .copyOriginURL: "复制仓库 origin 的远程 URL。"
        case .fileInfo: "查看类型、大小、时间和按需哈希。"
        case .createAlias: "为所选项目创建 Finder 替身。"
        }
    }

    var presentationSymbol: String {
        switch self {
        case .newFile, .newMarkdown, .newPlainText: "doc.badge.plus"
        case .newRichText: "doc.richtext"
        case .newXML: "chevron.left.forwardslash.chevron.right"
        case .newJSON, .newYAML: "curlybraces"
        case .newGitignore: "eye.slash"
        case .moveTo: "folder.badge.minus"
        case .copyTo: "folder.badge.plus"
        case .cut: "scissors"
        case .paste: "doc.on.clipboard"
        case .frequentDirectories: "folder.badge.gearshape"
        case .archive: "archivebox"
        case .unarchive: "arrow.down.doc"
        case .openWith: "macwindow"
        case .codexHere: "terminal"
        case .copyAbsolutePath: "link"
        case .copyShellPath: "terminal"
        case .copyFileURL: "nosign"
        case .copyGitRelativePath: "point.bottomleft.forward.to.point.topright.scurvepath"
        case .openGitRoot: "folder"
        case .openGitRootInEditor: "curlybraces.square"
        case .openOrigin: "network"
        case .copyOriginURL: "link.badge.plus"
        case .fileInfo: "info.circle"
        case .createAlias: "arrowshape.turn.up.right"
        }
    }
}
