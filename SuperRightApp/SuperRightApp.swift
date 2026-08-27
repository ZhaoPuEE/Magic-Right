import AppKit
import SwiftUI
import SuperRightCore

@main
struct SuperRightApp: App {
    @StateObject private var directoryHistory = DirectoryHistoryModel()
    @StateObject private var toolboxConfiguration = ToolboxConfigurationModel()

    var body: some Scene {
        MenuBarExtra("Magic Right", image: "MenuBarIcon") {
            MenuBarContentView()
                .environmentObject(directoryHistory)
                .environmentObject(toolboxConfiguration)
        }
        .menuBarExtraStyle(.menu)

        WindowGroup("Magic Right", id: "settings") {
            SettingsRootView()
                .environmentObject(directoryHistory)
                .environmentObject(toolboxConfiguration)
        }
        .handlesExternalEvents(matching: ["settings"])
        .defaultSize(width: 1120, height: 760)
    }
}

private struct MenuBarContentView: View {
    @EnvironmentObject private var directoryHistory: DirectoryHistoryModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SharedDefaults.directoryLearningEnabledKey, store: SharedDefaults.store)
    private var directoryLearningEnabled = true

    private var learningToggle: Binding<Bool> {
        Binding(
            get: {
                SharedDefaults.isAppGroupAvailable && directoryLearningEnabled
            },
            set: { isEnabled in
                guard SharedDefaults.isAppGroupAvailable else { return }
                directoryLearningEnabled = isEnabled
            }
        )
    }

    var body: some View {
        let sections = directoryHistory.sections

        directorySection("固定", entries: sections.pinned)
        directorySection("常用", entries: sections.frequent)
        directorySection("最近", entries: sections.recent)

        Section {
            Button("搜索目录…") {
                openSettings()
            }
            .keyboardShortcut("k", modifiers: [.command])
        }

        Divider()

        Toggle("学习常用目录", isOn: learningToggle)
            .disabled(!SharedDefaults.isAppGroupAvailable)
            .help(
                SharedDefaults.isAppGroupAvailable
                    ? "只记录目录路径、访问次数和时间"
                    : "App Group 不可用，目录学习已关闭"
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
        .onAppear {
            directoryHistory.reload()
        }
    }

    @ViewBuilder
    private func directorySection(
        _ title: String,
        entries: [DirectoryHistoryEntry]
    ) -> some View {
        if !entries.isEmpty {
            Section(title) {
                ForEach(entries) { entry in
                    Button {
                        directoryHistory.openInFinder(entry)
                    } label: {
                        Label(entry.displayName, systemImage: "folder")
                    }
                    .help(entry.normalizedPath)
                }
            }
        }
    }

    private func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }
}
