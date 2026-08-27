import AppKit
import SwiftUI
import SuperRightCore

@main
struct SuperRightApp: App {
    var body: some Scene {
        MenuBarExtra("Super Right", image: "MenuBarIcon") {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsRootView()
        }
    }
}

private struct MenuBarContentView: View {
    @AppStorage("directoryLearningEnabled", store: SharedDefaults.store)
    private var directoryLearningEnabled = true

    var body: some View {
        Section("快速目录") {
            Button("搜索目录…") {
                openSettings()
            }
            .keyboardShortcut("k", modifiers: [.command])

            Text("固定、常用和最近目录将在这里显示")
                .foregroundStyle(.secondary)
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
    }

    @Environment(\.openSettings) private var openSettings
}
