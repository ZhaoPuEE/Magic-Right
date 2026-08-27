import AppKit
import SwiftUI
import SuperRightCore

@main
struct SuperRightApp: App {
    @StateObject private var directoryHistory = DirectoryHistoryModel()

    var body: some Scene {
        MenuBarExtra("Super Right", image: "MenuBarIcon") {
            MenuBarContentView()
                .environmentObject(directoryHistory)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsRootView()
                .environmentObject(directoryHistory)
        }
    }
}

private struct MenuBarContentView: View {
    @EnvironmentObject private var directoryHistory: DirectoryHistoryModel
    @AppStorage(SharedDefaults.directoryLearningEnabledKey, store: SharedDefaults.store)
    private var directoryLearningEnabled = true

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

        Toggle("学习常用目录", isOn: $directoryLearningEnabled)

        SettingsLink {
            Label("设置…", systemImage: "gearshape")
        }

        Divider()

        Button("退出 Super Right") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
        .onAppear {
            directoryHistory.reload()
        }
    }

    @Environment(\.openSettings) private var openSettings

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
}
