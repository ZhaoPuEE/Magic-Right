import Combine
import Foundation
import SuperRightCore

@MainActor
final class ToolboxConfigurationModel: ObservableObject {
    @Published private(set) var configuration: ToolboxConfiguration
    @Published private(set) var errorMessage: String?

    init() {
        let loaded = Self.loadConfiguration()
        configuration = loaded.configuration
        errorMessage = loaded.errorMessage
    }

    func reload() {
        SharedDefaults.store.synchronize()
        let loaded = Self.loadConfiguration()
        configuration = loaded.configuration
        errorMessage = loaded.errorMessage
    }

    func isEnabled(_ action: ToolboxAction) -> Bool {
        configuration.preference(for: action)?.isEnabled == true
    }

    func setEnabled(_ isEnabled: Bool, for action: ToolboxAction) {
        guard action.isImplemented, ensureAppGroupAvailable() else { return }
        configuration.setEnabled(isEnabled, for: action)
        persist()
    }

    func setEnabled(_ isEnabled: Bool, for actions: [ToolboxAction]) {
        guard ensureAppGroupAvailable() else { return }
        for action in actions where action.isImplemented {
            configuration.setEnabled(isEnabled, for: action)
        }
        persist()
    }

    func enabledCount(in actions: [ToolboxAction]) -> Int {
        actions.lazy.filter { $0.isImplemented && self.isEnabled($0) }.count
    }

    func availableCount(in actions: [ToolboxAction]) -> Int {
        actions.lazy.filter(\.isImplemented).count
    }

    func apply(_ preset: ToolboxPreset) {
        guard ensureAppGroupAvailable() else { return }
        configuration.apply(preset)
        persist()
    }

    private func ensureAppGroupAvailable() -> Bool {
        guard SharedDefaults.isAppGroupAvailable else {
            errorMessage = "App Group 不可用，设置没有保存；请检查签名与扩展权限。"
            return false
        }
        return true
    }

    private func persist() {
        guard SharedDefaults.isAppGroupAvailable else {
            errorMessage = "App Group 不可用，设置没有保存；请检查签名与扩展权限。"
            return
        }
        do {
            let data = try JSONEncoder().encode(configuration)
            SharedDefaults.store.set(data, forKey: SharedDefaults.toolboxConfigurationKey)
            errorMessage = nil
        } catch {
            errorMessage = "右键动作设置保存失败。"
        }
    }

    private static func loadConfiguration() -> (
        configuration: ToolboxConfiguration,
        errorMessage: String?
    ) {
        guard SharedDefaults.isAppGroupAvailable else {
            return (
                .allDisabled,
                "App Group 不可用，Finder 与 App 无法共享设置；请检查签名与扩展权限。"
            )
        }
        guard let data = SharedDefaults.store.data(
            forKey: SharedDefaults.toolboxConfigurationKey
        ) else {
            return (ToolboxConfiguration(preset: .developer), nil)
        }
        do {
            return (
                try JSONDecoder().decode(ToolboxConfiguration.self, from: data),
                nil
            )
        } catch {
            return (
                .allDisabled,
                "右键动作配置已损坏。为安全起见，所有动作已临时关闭。"
            )
        }
    }
}
