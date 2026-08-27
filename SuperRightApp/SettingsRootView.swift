import AppKit
import SwiftUI
import SuperRightCore

private enum ToolboxTheme {
    static let electricCyan = Color(red: 0.12, green: 0.9, blue: 1)
    static let graphite = Color(red: 0.075, green: 0.085, blue: 0.1)
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
        case .overview: "总览"
        case .openWith: "打开方式"
        case .newFile: "新建文件"
        case .directories: "常用目录"
        case .pathsAndGit: "路径与 Git"
        case .fileTools: "文件工具"
        case .archives: "压缩解压"
        case .settings: "设置"
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
}

struct SettingsRootView: View {
    @State private var selectedPage: ToolboxPage? = .overview
    @StateObject private var applicationRegistry = ApplicationRegistryModel()

    var body: some View {
        NavigationSplitView {
            List(ToolboxPage.allCases, selection: $selectedPage) { page in
                Label(page.title, systemImage: page.symbol)
                    .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 176, ideal: 192, max: 230)
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
        } detail: {
            ZStack {
                ToolboxTheme.graphite
                    .opacity(0.97)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [ToolboxTheme.electricCyan.opacity(0.08), .clear],
                    startPoint: .topTrailing,
                    endPoint: .center
                )
                .ignoresSafeArea()

                ScrollView {
                    pageContent(selectedPage ?? .overview)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(28)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(ToolboxTheme.electricCyan)
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder
    private func pageContent(_ page: ToolboxPage) -> some View {
        switch page {
        case .overview:
            OverviewPage()
        case .openWith:
            OpenWithPage(model: applicationRegistry)
        case .newFile:
            FeaturePage(
                title: "新建文件",
                subtitle: "从 Finder 直接创建真正可打开的文件和自己的模板。",
                features: [
                    ("Markdown / 文本", "doc.plaintext", "启用"),
                    ("JSON / YAML / XML", "curlybraces", "启用"),
                    ("Word / Excel / PowerPoint", "doc.richtext", "规划中"),
                    ("自定义模板", "square.stack.3d.up", "规划中")
                ]
            )
        case .directories:
            DirectoryLearningPage()
        case .pathsAndGit:
            FeaturePage(
                title: "路径与 Git",
                subtitle: "复制安全路径，并让仓库相关动作只在合适的位置出现。",
                features: [
                    ("复制绝对路径", "link", "启用"),
                    ("复制 Shell 安全路径", "terminal", "规划中"),
                    ("打开仓库根目录", "arrow.up.left.and.arrow.down.right", "规划中"),
                    ("打开 origin 页面", "network", "规划中")
                ]
            )
        case .fileTools:
            FeaturePage(
                title: "文件工具",
                subtitle: "首版聚焦安全、可撤销且不会静默覆盖的文件操作。",
                features: [
                    ("文件信息与哈希", "info.circle", "规划中"),
                    ("移动 / 复制到", "folder.badge.plus", "规划中"),
                    ("剪切 / 粘贴", "scissors", "规划中"),
                    ("撤销上次移动", "arrow.uturn.backward", "规划中")
                ]
            )
        case .archives:
            FeaturePage(
                title: "压缩解压",
                subtitle: "优先使用系统格式；解压前验证路径，避免归档穿越。",
                features: [
                    ("压缩为 ZIP", "doc.zipper", "规划中"),
                    ("压缩为 tar.gz", "archivebox", "规划中"),
                    ("解压到当前目录", "arrow.down.doc", "规划中"),
                    ("解压到同名目录", "folder.badge.plus", "规划中")
                ]
            )
        case .settings:
            GeneralSettingsPage()
        }
    }
}

private struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(subtitle)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(.bottom, 8)
    }
}

private struct OverviewPage: View {
    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                title: "Super Right 工具箱",
                subtitle: "把常用开发和文件动作放进 Finder 右键，同时保持菜单干净。"
            )

            HStack(spacing: 12) {
                StatusPill(title: "Finder 扩展", value: "待启用", symbol: "puzzlepiece.extension")
                StatusPill(title: "已启用动作", value: "2", symbol: "checkmark.circle")
                StatusPill(title: "目录学习", value: "开启", symbol: "brain.head.profile")
            }

            Text("功能概览")
                .font(.headline)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ActionCard(title: "打开方式", detail: "动态发现编辑器与终端", symbol: "macwindow", status: "接入中")
                ActionCard(title: "新建文件", detail: "文本、Office 与自定义模板", symbol: "doc.badge.plus", status: "1 项启用")
                ActionCard(title: "智能目录", detail: "固定、常用、最近与搜索", symbol: "folder.badge.gearshape", status: "开启")
                ActionCard(title: "路径与 Git", detail: "安全路径与仓库上下文动作", symbol: "point.bottomleft.forward.to.point.topright.scurvepath", status: "1 项启用")
                ActionCard(title: "文件工具", detail: "安全移动、复制与撤销", symbol: "wrench.and.screwdriver", status: "规划中")
                ActionCard(title: "压缩解压", detail: "ZIP、tar 与 tar.gz", symbol: "archivebox", status: "规划中")
            }
        }
    }
}

private struct OpenWithPage: View {
    @ObservedObject var model: ApplicationRegistryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                PageHeader(
                    title: "打开方式",
                    subtitle: "按 Bundle ID 识别 App；应用移动、升级或重装后仍能恢复配置。"
                )
                Spacer()
                Button("重新扫描") {
                    model.scan()
                }
                    .buttonStyle(.borderedProminent)
            }

            CalloutCard(
                symbol: "sparkle.magnifyingglass",
                title: "自动发现新安装的 App",
                detail: "Zed、Cursor、Warp 等新应用会进入“可用应用”，由你决定是否加入 Finder 菜单。"
            )

            VStack(spacing: 0) {
                if model.applications.isEmpty {
                    ContentUnavailableView(
                        "没有发现支持的 App",
                        systemImage: "app.dashed",
                        description: Text("可以安装编辑器或终端，也可以手动选择任意 App。")
                    )
                    .padding(24)
                } else {
                    ForEach(Array(model.applications.enumerated()), id: \.element.id) { index, application in
                        ApplicationRow(
                            application: application,
                            isEnabled: Binding(
                                get: { model.isEnabled(application) },
                                set: { model.setEnabled($0, for: application) }
                            )
                        )
                        if index < model.applications.count - 1 {
                            Divider().opacity(0.25)
                        }
                    }
                }
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            Button {
                model.chooseAndAddApplication()
            } label: {
                Label("添加其他 App…", systemImage: "plus")
            }
        }
    }
}

private struct DirectoryLearningPage: View {
    @AppStorage("directoryLearningEnabled", store: SharedDefaults.store)
    private var directoryLearningEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "常用目录",
                subtitle: "根据访问频率和最近使用时间，建立只保存在本机的快速目录列表。"
            )

            Toggle(isOn: $directoryLearningEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("学习目录访问")
                        .font(.headline)
                    Text("不扫描目录内容、不联网；可以随时暂停、排除或清空。")
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(18)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 14) {
                ActionCard(title: "固定", detail: "手动保留的重要目录", symbol: "pin", status: "0 个")
                ActionCard(title: "常用", detail: "默认显示得分最高的 8 个", symbol: "chart.line.uptrend.xyaxis", status: "等待学习")
                ActionCard(title: "最近", detail: "按最近访问时间快速返回", symbol: "clock", status: "等待学习")
            }

            CalloutCard(
                symbol: "hand.raised",
                title: "隐私边界",
                detail: "只有目录路径、访问次数和时间保存在 App Group 数据中，数据不会离开这台 Mac。"
            )
        }
    }
}

private struct FeaturePage: View {
    let title: String
    let subtitle: String
    let features: [(String, String, String)]

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: title, subtitle: subtitle)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                    ActionCard(title: feature.0, detail: "Finder 右键动作", symbol: feature.1, status: feature.2)
                }
            }
        }
    }
}

private struct GeneralSettingsPage: View {
    @AppStorage("finderExtensionEnabled", store: SharedDefaults.store)
    private var finderExtensionEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "设置",
                subtitle: "管理 Finder 扩展、菜单配置和按需文件权限。"
            )

            GroupBox("Finder 右键菜单") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("启用 Super Right 菜单", isOn: $finderExtensionEnabled)
                    Text("需要在系统设置的“登录项与扩展”中允许 Finder 扩展。")
                        .foregroundStyle(.secondary)
                    Button("打开扩展设置") {
                        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
                        NSWorkspace.shared.open(url)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            .groupBoxStyle(GraphiteGroupBoxStyle())

            GroupBox("权限原则") {
                Text("Super Right 只在实际需要时请求目录访问，不会在首次启动时要求完全磁盘访问。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .groupBoxStyle(GraphiteGroupBoxStyle())
        }
    }
}

private struct StatusPill: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(ToolboxTheme.electricCyan)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
    }
}

private struct ActionCard: View {
    let title: String
    let detail: String
    let symbol: String
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(ToolboxTheme.electricCyan)
                Spacer()
                Text(status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(status == "规划中" ? .secondary : ToolboxTheme.electricCyan)
            }
            Text(title).font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(ToolboxTheme.electricCyan.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct CalloutCard: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(ToolboxTheme.electricCyan)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(ToolboxTheme.electricCyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(ToolboxTheme.electricCyan.opacity(0.2), lineWidth: 1)
        }
    }
}

private struct ApplicationRow: View {
    let application: DetectedApplication
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.currentApplicationURL.path))
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(application.menuDisplayName).font(.headline)
                Text(application.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct GraphiteGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
                .font(.headline)
            configuration.content
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}
