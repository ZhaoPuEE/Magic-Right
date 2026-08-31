import Foundation

public enum CodexHereTerminal: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case terminal
    case ghostty
    case tabby

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .terminal: "系统终端"
        case .ghostty: "Ghostty"
        case .tabby: "Tabby"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .ghostty: "com.mitchellh.ghostty"
        case .tabby: "org.tabby"
        }
    }

    public static let defaultValue: CodexHereTerminal = .tabby
}
