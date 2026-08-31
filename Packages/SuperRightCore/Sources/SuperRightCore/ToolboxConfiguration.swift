import Foundation

/// Stable groups used to build the settings sidebar and Finder submenus.
/// Presentation and localization remain the responsibility of UI clients.
public enum ToolboxGroup: String, Codable, CaseIterable, Hashable, Sendable {
    case newFile
    case transfer
    case directories
    case archive
    case openWith
    case git
    case tools

    /// Every declared action in the group, including legacy and future actions
    /// that are not currently available in the product.
    public var actions: [ToolboxAction] {
        ToolboxAction.allCases.filter { $0.group == self }
    }

    /// Actions that have a real V1 implementation and can be shown as toggles.
    public var availableActions: [ToolboxAction] {
        actions.filter(\.isImplemented)
    }
}

/// Stable identifiers for toolbox capabilities.
///
/// Existing raw values are retained for Codable compatibility. `newFile` is a
/// legacy aggregate identifier; the seven typed new-file actions replace it in
/// the action list while allowing old configurations to migrate safely.
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
    case codexHere
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

    case newMarkdown
    case newPlainText
    case newRichText
    case newXML
    case newJSON
    case newYAML
    case newGitignore

    public var group: ToolboxGroup {
        switch self {
        case .newFile, .newMarkdown, .newPlainText, .newRichText,
             .newXML, .newJSON, .newYAML, .newGitignore:
            .newFile
        case .moveTo, .copyTo, .cut, .paste:
            .transfer
        case .frequentDirectories:
            .directories
        case .archive, .unarchive:
            .archive
        case .openWith, .codexHere:
            .openWith
        case .copyGitRelativePath, .openGitRoot, .openGitRootInEditor,
             .openOrigin, .copyOriginURL:
            .git
        case .copyAbsolutePath, .copyShellPath, .copyFileURL,
             .fileInfo, .createAlias:
            .tools
        }
    }

    /// Whether this action has an end-to-end implementation in the current V1
    /// build. Settings and presets use this as the source of truth.
    public var isImplemented: Bool {
        switch self {
        case .newMarkdown, .newPlainText, .newRichText, .newXML, .newJSON,
             .newYAML, .newGitignore, .moveTo, .copyTo, .cut, .paste,
             .frequentDirectories, .archive, .unarchive, .openWith, .codexHere,
             .copyAbsolutePath, .copyShellPath, .copyGitRelativePath,
             .openGitRoot, .openGitRootInEditor, .openOrigin, .copyOriginURL,
             .fileInfo, .createAlias:
            true
        case .newFile, .copyFileURL:
            false
        }
    }

    public static var availableActions: [ToolboxAction] {
        allCases.filter(\.isImplemented)
    }

    /// The file preset represented by this action, if it is a typed new-file
    /// action. The legacy aggregate `newFile` action deliberately returns nil.
    public var newFilePreset: NewFilePreset? {
        switch self {
        case .newMarkdown: .markdown
        case .newPlainText: .plainText
        case .newRichText: .richText
        case .newXML: .xml
        case .newJSON: .json
        case .newYAML: .yaml
        case .newGitignore: .gitignore
        default: nil
        }
    }

    /// A non-localized fallback. UI clients should localize by `rawValue`.
    public var defaultName: String {
        switch self {
        case .newFile: "New File"
        case .newMarkdown: "Markdown"
        case .newPlainText: "Text File"
        case .newRichText: "Rich Text File"
        case .newXML: "XML"
        case .newJSON: "JSON"
        case .newYAML: "YAML"
        case .newGitignore: ".gitignore"
        case .moveTo: "Move To"
        case .copyTo: "Copy To"
        case .cut: "Cut"
        case .paste: "Paste"
        case .frequentDirectories: "Directories"
        case .archive: "Compress"
        case .unarchive: "Extract"
        case .openWith: "Open With"
        case .codexHere: "Codex Here!"
        case .copyAbsolutePath: "Copy Absolute Path"
        case .copyShellPath: "Copy Shell-safe Path"
        case .copyFileURL: "Removed Legacy Action"
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

public extension NewFilePreset {
    var toolboxAction: ToolboxAction {
        switch self {
        case .markdown: .newMarkdown
        case .plainText: .newPlainText
        case .richText: .newRichText
        case .xml: .newXML
        case .json: .newJSON
        case .yaml: .newYAML
        case .gitignore: .newGitignore
        }
    }
}

public enum ToolboxPreset: String, Codable, CaseIterable, Hashable, Sendable {
    case developer
    case file
    case all

    /// Presets never enable actions that lack an end-to-end implementation.
    public var enabledActions: Set<ToolboxAction> {
        let requested: Set<ToolboxAction>
        switch self {
        case .developer:
            requested = [
                .newMarkdown, .newPlainText, .newXML, .newJSON, .newYAML,
                .newGitignore, .moveTo, .copyTo, .frequentDirectories, .openWith,
                .codexHere,
                .copyAbsolutePath, .copyShellPath, .copyGitRelativePath,
                .openGitRoot, .openGitRootInEditor, .openOrigin, .copyOriginURL
            ]
        case .file:
            requested = [
                .newMarkdown, .newPlainText, .newRichText, .newXML, .newJSON,
                .newYAML, .newGitignore, .moveTo, .copyTo, .cut, .paste,
                .frequentDirectories, .openWith, .codexHere,
                .copyAbsolutePath, .archive, .unarchive, .fileInfo, .createAlias
            ]
        case .all:
            requested = Set(ToolboxAction.availableActions)
        }
        return requested.filter(\.isImplemented)
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

public struct ToolboxGroupCounts: Codable, Hashable, Sendable {
    public let declaredActionCount: Int
    public let availableActionCount: Int
    public let enabledActionCount: Int

    public init(
        declaredActionCount: Int,
        availableActionCount: Int,
        enabledActionCount: Int
    ) {
        self.declaredActionCount = declaredActionCount
        self.availableActionCount = availableActionCount
        self.enabledActionCount = enabledActionCount
    }

    public var isFullyEnabled: Bool {
        availableActionCount > 0 && enabledActionCount == availableActionCount
    }

    public var isPartiallyEnabled: Bool {
        enabledActionCount > 0 && enabledActionCount < availableActionCount
    }
}

public struct ToolboxConfiguration: Codable, Hashable, Sendable {
    private static let currentSchemaVersion = 3

    private var schemaVersion: Int
    public private(set) var actions: [ToolboxActionPreference]

    /// A fail-closed configuration used when persisted data is present but
    /// cannot be trusted. This is intentionally different from first-run
    /// defaults, which use a product preset.
    public static var allDisabled: ToolboxConfiguration {
        ToolboxConfiguration(actions: [])
    }

    public init(preset: ToolboxPreset) {
        schemaVersion = Self.currentSchemaVersion
        let enabled = preset.enabledActions
        actions = ToolboxAction.allCases.enumerated().map { index, action in
            ToolboxActionPreference(
                action: action,
                isEnabled: enabled.contains(action) && action.isImplemented,
                order: index
            )
        }
    }

    /// Normalizes incomplete or legacy lists by deduplicating actions, disabling
    /// unavailable actions, and appending newly declared actions. If an old
    /// configuration enabled aggregate `newFile`, its missing typed actions are
    /// enabled during migration.
    public init(actions: [ToolboxActionPreference]) {
        schemaVersion = Self.currentSchemaVersion
        let legacyNewFileWasEnabled = actions.first {
            $0.action == .newFile
        }?.isEnabled == true
        let originallyPresent = Set(actions.map(\.action))
        var seen = Set<ToolboxAction>()

        self.actions = actions.compactMap { preference in
            guard seen.insert(preference.action).inserted else { return nil }
            var normalized = preference
            normalized.isEnabled = preference.isEnabled && preference.action.isImplemented
            return normalized
        }

        var nextOrder = (self.actions.map(\.order).max() ?? -1) + 1
        for action in ToolboxAction.allCases where !seen.contains(action) {
            let migrateEnabledNewFile = legacyNewFileWasEnabled
                && action.newFilePreset != nil
                && !originallyPresent.contains(action)
            self.actions.append(
                ToolboxActionPreference(
                    action: action,
                    isEnabled: migrateEnabledNewFile && action.isImplemented,
                    order: nextOrder
                )
            )
            nextOrder += 1
        }
    }

    public func preference(for action: ToolboxAction) -> ToolboxActionPreference? {
        actions.first { $0.action == action }
    }

    /// Enabled and implemented actions, optionally filtered to one group.
    public func enabledActions(in group: ToolboxGroup? = nil) -> [ToolboxActionPreference] {
        sortedActions { preference in
            preference.isEnabled
                && preference.action.isImplemented
                && (group == nil || preference.action.group == group)
        }
    }

    /// Every implemented action available to the settings action list.
    public func availableActions(in group: ToolboxGroup? = nil) -> [ToolboxActionPreference] {
        sortedActions { preference in
            preference.action.isImplemented
                && (group == nil || preference.action.group == group)
        }
    }

    public func counts(in group: ToolboxGroup) -> ToolboxGroupCounts {
        ToolboxGroupCounts(
            declaredActionCount: group.actions.count,
            availableActionCount: group.availableActions.count,
            enabledActionCount: enabledActions(in: group).count
        )
    }

    /// An unavailable action cannot be enabled through the centralized model.
    public mutating func setEnabled(_ isEnabled: Bool, for action: ToolboxAction) {
        update(action) { $0.isEnabled = isEnabled && action.isImplemented }
    }

    /// Enables or disables every available action in a group. Unimplemented
    /// actions are explicitly kept disabled.
    public mutating func setGroupEnabled(_ isEnabled: Bool, for group: ToolboxGroup) {
        for index in actions.indices where actions[index].action.group == group {
            actions[index].isEnabled = isEnabled && actions[index].action.isImplemented
        }
    }

    public mutating func setOrder(_ order: Int, for action: ToolboxAction) {
        update(action) { $0.order = order }
    }

    public mutating func setCustomName(_ customName: String?, for action: ToolboxAction) {
        update(action) { $0.customName = customName }
    }

    public mutating func apply(_ preset: ToolboxPreset) {
        ensureAllActionsArePresent()
        let enabled = preset.enabledActions
        for index in actions.indices {
            actions[index].isEnabled = enabled.contains(actions[index].action)
                && actions[index].action.isImplemented
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case actions
    }

    /// Lets newer action identifiers survive a downgrade. Unknown or malformed
    /// entries are ignored while known entries keep their state.
    private struct LossyActionPreference: Decodable {
        let value: ToolboxActionPreference?

        init(from decoder: Decoder) throws {
            value = try? ToolboxActionPreference(from: decoder)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? 1
        let decoded = try container.decode(
            [LossyActionPreference].self,
            forKey: .actions
        )
        self.init(actions: decoded.compactMap(\.value))
        if decodedSchemaVersion < Self.currentSchemaVersion {
            if decodedSchemaVersion < 2 {
                // Move and copy were visible as planned rows in schema 1 but could
                // not be enabled. Turning them on during this one-time migration
                // gives existing installs the newly completed destination menus.
                setEnabled(true, for: .moveTo)
                setEnabled(true, for: .copyTo)
            }
            if decodedSchemaVersion < 3 {
                // Codex Here is on by default for existing installs while still
                // remaining an independent switch in the application-actions page.
                setEnabled(true, for: .codexHere)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(actions, forKey: .actions)
    }

    private func sortedActions(
        matching predicate: (ToolboxActionPreference) -> Bool
    ) -> [ToolboxActionPreference] {
        actions
            .filter(predicate)
            .sorted { lhs, rhs in
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                return lhs.action.rawValue < rhs.action.rawValue
            }
    }

    private mutating func ensureAllActionsArePresent() {
        let known = Set(actions.map(\.action))
        var nextOrder = (actions.map(\.order).max() ?? -1) + 1
        for action in ToolboxAction.allCases where !known.contains(action) {
            actions.append(
                ToolboxActionPreference(
                    action: action,
                    isEnabled: false,
                    order: nextOrder
                )
            )
            nextOrder += 1
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
                order: (actions.map(\.order).max() ?? -1) + 1
            )
            change(&preference)
            actions.append(preference)
        }
    }
}
