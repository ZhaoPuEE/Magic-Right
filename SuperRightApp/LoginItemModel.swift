import Combine
import Foundation
import ServiceManagement

@MainActor
final class LoginItemModel: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorMessage: String?

    private let service: SMAppService
    private var errorStatus: SMAppService.Status?

    init(service: SMAppService = .mainApp) {
        self.service = service
        refresh()
    }

    var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    var canChangeRegistration: Bool {
        switch status {
        case .enabled, .requiresApproval, .notRegistered:
            true
        case .notFound:
            false
        @unknown default:
            false
        }
    }

    var statusDescription: String {
        switch status {
        case .enabled:
            "已启用；下次登录后 Magic Right 会自动运行。"
        case .requiresApproval:
            "已申请启用，仍需在系统设置的“登录项”中允许。"
        case .notRegistered:
            "未启用；Magic Right 不会随登录自动运行。"
        case .notFound:
            "当前安装位置或签名无法注册登录项；正式版请放入“应用程序”。"
        @unknown default:
            "无法读取登录项状态。"
        }
    }

    func refresh() {
        let newStatus = service.status
        if let errorStatus, errorStatus != newStatus {
            errorMessage = nil
            self.errorStatus = nil
        }
        status = newStatus
    }

    func setEnabled(_ isEnabled: Bool) {
        guard canChangeRegistration else {
            errorMessage = "当前 App 位置或签名不支持登录项注册。"
            errorStatus = status
            return
        }
        guard isEnabled != isRegistered else { return }
        do {
            if isEnabled {
                try service.register()
            } else {
                try service.unregister()
            }
            errorMessage = nil
            errorStatus = nil
        } catch {
            errorMessage = isEnabled
                ? "登录时自动启动启用失败：\(error.localizedDescription)"
                : "登录时自动启动关闭失败：\(error.localizedDescription)"
            errorStatus = service.status
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
