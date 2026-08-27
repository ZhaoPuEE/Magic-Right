import Foundation

/// Stable groups used to build Finder submenus. Presentation and localization
/// remain the responsibility of the host app and Finder extension.
public enum ToolboxGroup: String, Codable, CaseIterable, Hashable, Sendable {
    case newFile
    case transfer
    case directories
    case archive
    case openWith
    case git
    case tools
}

/// Stable identifiers for V1 toolbox capabilities. This is configuration only;
/// no file-system operation is implemented in SuperRightCore.
public enum ToolboxAction: String, Codable, CaseIterable, Hashable, Sendable {
    case newFile
    case moveTo
    case copyTo
    case cut
    case paste
    case frequentDirectories
    case archive
    case unarchive
    case openWith
    case copyAbsolutePath
    case copyShellPath
    case copyFileURL
    case copyGitRelativePath
    case openGitRoot
    case openGitRootInEditor
    case openOrigin
    case copyOriginURL
    case fileInfo
    case createAlias

    public var group: ToolboxGroup {
        switch self {
        case .newFile:
            .newFile
        case .moveTo, .copyTo, .cut, .paste:
            .transfer
        case .frequentDirectories:
            .directories
        case .archive, .unarchive:
            .archive
        case .openWith:
            .openWith
        case .copyGitRelativePath, .openGitRoot, .openGitRootInEditor, .openOrigin, .copyOriginURL:
            .git
        case .copyAbsolutePath, .copyShellPath, .copyFileURL, .fileInfo, .createAlias:
            .tools
        }
    }

    /// A non-localized fallback. UI clients should localize by `rawValue`.
    public var defaultName: String {
        switch self {
        case .newFile: "New File"
        case .moveTo: "Move To"
        case .copyTo: "Copy To"
        case .cut: "Cut"
        case .paste: "Paste"
        case .frequentDirectories: "Directories"
        case .archive: "Compress"
        case .unarchive: "Extract"
        case .openWith: "Open With"
        case .copyAbsolutePath: "Copy Absolute Path"
        case .copyShellPath: "Copy Shell-safe Path"
        case .copyFileURL: "Copy file URL"
        case .copyGitRelativePath: "Copy Path Relative to Git Root"
        case .openGitRoot: "Open Git Root"
        case .openGitRootInEditor: "Open Git Root in Editor"
        case .openOrigin: "Open origin"
        case .copyOriginURL: "Copy origin URL"
        case .fileInfo: "File Info"
        case .createAlias: "Create Alias"
        }
    }
}

public enum ToolboxPreset: String, Codable, CaseIterable, Hashable, Sendable {
    case developer
    case file
    case all

    public var enabledActions: Set<ToolboxAction> {
        switch self {
        case .developer:
            [
                .newFile, .frequentDirectories, .openWith,
                .copyAbsolutePath, .copyShellPath, .copyFileURL,
                .copyGitRelativePath, .openGitRoot, .openGitRootInEditor,
                .openOrigin, .copyOriginURL, .fileInfo
            ]
        case .file:
            [
                .newFile, .moveTo, .copyTo, .cut, .paste,
                .frequentDirectories, .archive, .unarchive,
                .openWith, .fileInfo, .createAlias
            ]
        case .all:
            Set(ToolboxAction.allCases)
        }
    }
}

public struct ToolboxActionPreference: Codable, Hashable, Identifiable, Sendable {
    public var id: ToolboxAction { action }

    public let action: ToolboxAction
    public var isEnabled: Bool
    public var order: Int
    public var customName: String?

    public init(
        action: ToolboxAction,
        isEnabled: Bool,
        order: Int,
        customName: String? = nil
    ) {
        self.action = action
        self.isEnabled = isEnabled
        self.order = order
        self.customName = customName
    }

    public var displayName: String {
        guard let customName, !customName.isEmpty else { return action.defaultName }
        return customName
    }
}

public struct ToolboxConfiguration: Codable, Hashable, Sendable {
    public private(set) var actions: [ToolboxActionPreference]

    public init(preset: ToolboxPreset) {
        let enabled = preset.enabledActions
        actions = ToolboxAction.allCases.enumerated().map { index, action in
            ToolboxActionPreference(
                action: action,
                isEnabled: enabled.contains(action),
                order: index
            )
        }
    }

    public init(actions: [ToolboxActionPreference]) {
        var seen = Set<ToolboxAction>()
        self.actions = actions.filter { seen.insert($0.action).inserted }
    }

    public func preference(for action: ToolboxAction) -> ToolboxActionPreference? {
        actions.first { $0.action == action }
    }

    public func enabledActions(in group: ToolboxGroup? = nil) -> [ToolboxActionPreference] {
        actions
            .filter { preference in
                preference.isEnabled && (group == nil || preference.action.group == group)
            }
            .sorted { lhs, rhs in
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                return lhs.action.rawValue < rhs.action.rawValue
            }
    }

    public mutating func setEnabled(_ isEnabled: Bool, for action: ToolboxAction) {
        update(action) { $0.isEnabled = isEnabled }
    }

    public mutating func setOrder(_ order: Int, for action: ToolboxAction) {
        update(action) { $0.order = order }
    }

    public mutating func setCustomName(_ customName: String?, for action: ToolboxAction) {
        update(action) { $0.customName = customName }
    }

    public mutating func apply(_ preset: ToolboxPreset) {
        let enabled = preset.enabledActions
        for index in actions.indices {
            actions[index].isEnabled = enabled.contains(actions[index].action)
        }
        for action in ToolboxAction.allCases where preference(for: action) == nil {
            actions.append(
                ToolboxActionPreference(
                    action: action,
                    isEnabled: enabled.contains(action),
                    order: actions.count
                )
            )
        }
    }

    private mutating func update(
        _ action: ToolboxAction,
        change: (inout ToolboxActionPreference) -> Void
    ) {
        if let index = actions.firstIndex(where: { $0.action == action }) {
            change(&actions[index])
        } else {
            var preference = ToolboxActionPreference(
                action: action,
                isEnabled: false,
                order: actions.count
            )
            change(&preference)
            actions.append(preference)
        }
    }
}
