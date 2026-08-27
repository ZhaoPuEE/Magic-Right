import Foundation
import Testing
@testable import SuperRightCore

@Suite("Toolbox configuration")
struct ToolboxConfigurationTests {
    @Test("Developer and File presets emphasize different actions")
    func presetDifferences() {
        let developer = ToolboxConfiguration(preset: .developer)
        let file = ToolboxConfiguration(preset: .file)

        #expect(developer.preference(for: .openGitRoot)?.isEnabled == true)
        #expect(file.preference(for: .openGitRoot)?.isEnabled == false)
        #expect(developer.preference(for: .moveTo)?.isEnabled == false)
        #expect(file.preference(for: .moveTo)?.isEnabled == true)
    }

    @Test("All preset enables every declared action")
    func allPreset() {
        let configuration = ToolboxConfiguration(preset: .all)
        #expect(configuration.enabledActions().count == ToolboxAction.allCases.count)
    }

    @Test("User state controls enablement ordering and names")
    func userOverrides() {
        var configuration = ToolboxConfiguration(preset: .developer)
        configuration.setEnabled(true, for: .moveTo)
        configuration.setOrder(-1, for: .moveTo)
        configuration.setCustomName("Move safely", for: .moveTo)

        #expect(configuration.enabledActions().first?.action == .moveTo)
        #expect(configuration.preference(for: .moveTo)?.displayName == "Move safely")
    }

    @Test("Configuration is Codable")
    func codableRoundTrip() throws {
        var configuration = ToolboxConfiguration(preset: .file)
        configuration.setCustomName("Inspect", for: .fileInfo)

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(ToolboxConfiguration.self, from: data)

        #expect(decoded == configuration)
    }
}
