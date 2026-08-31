import Foundation
import Testing
@testable import SuperRightCore

@Suite("Codex Here terminal preference")
struct CodexHereTerminalTests {
    @Test("Every selectable terminal has a stable bundle identifier")
    func terminalMetadata() {
        #expect(CodexHereTerminal.defaultValue == .tabby)
        #expect(Set(CodexHereTerminal.allCases.map(\.bundleIdentifier)).count == 3)
        #expect(CodexHereTerminal.terminal.bundleIdentifier == "com.apple.Terminal")
        #expect(CodexHereTerminal.ghostty.bundleIdentifier == "com.mitchellh.ghostty")
        #expect(CodexHereTerminal.tabby.bundleIdentifier == "org.tabby")
    }

    @Test("The preference survives persistence")
    func codableRoundTrip() throws {
        for terminal in CodexHereTerminal.allCases {
            let data = try JSONEncoder().encode(terminal)
            #expect(try JSONDecoder().decode(CodexHereTerminal.self, from: data) == terminal)
        }
    }
}
