import Foundation
import Testing
@testable import SuperRightCore

@Suite("Toolbox configuration")
struct ToolboxConfigurationTests {
    @Test("Presets only enable implemented actions")
    func presetsOnlyEnableAvailableActions() {
        let developer = ToolboxConfiguration(preset: .developer)
        let file = ToolboxConfiguration(preset: .file)
        let all = ToolboxConfiguration(preset: .all)

        #expect(developer.preference(for: .newJSON)?.isEnabled == true)
        #expect(developer.preference(for: .moveTo)?.isEnabled == true)
        #expect(developer.preference(for: .copyTo)?.isEnabled == true)
        #expect(developer.preference(for: .codexHere)?.isEnabled == true)
        #expect(developer.preference(for: .newRichText)?.isEnabled == false)
        #expect(file.preference(for: .newRichText)?.isEnabled == true)
        #expect(file.preference(for: .copyShellPath)?.isEnabled == false)
        #expect(all.enabledActions().map(\.action) == ToolboxAction.availableActions)

        for preset in ToolboxPreset.allCases {
            let configuration = ToolboxConfiguration(preset: preset)
            let enabledAreImplemented = configuration.enabledActions()
                .allSatisfy { $0.action.isImplemented }
            let unavailableAreDisabled = configuration.actions
                .filter { !$0.action.isImplemented }
                .allSatisfy { !$0.isEnabled }
            #expect(enabledAreImplemented)
            #expect(unavailableAreDisabled)
        }
    }

    @Test("Implementation status exactly matches the V1 surface")
    func implementationStatus() {
        let implemented: Set<ToolboxAction> = [
            .newMarkdown, .newPlainText, .newRichText, .newXML,
            .newJSON, .newYAML, .newGitignore,
            .moveTo, .copyTo, .cut, .paste, .frequentDirectories,
            .archive, .unarchive, .openWith, .codexHere,
            .copyAbsolutePath, .copyShellPath, .copyGitRelativePath,
            .openGitRoot, .openGitRootInEditor, .openOrigin, .copyOriginURL,
            .fileInfo, .createAlias
        ]

        #expect(Set(ToolboxAction.availableActions) == implemented)
        #expect(ToolboxAction.allCases.allSatisfy {
            $0.isImplemented == implemented.contains($0)
        })
    }

    @Test("Schema 2 configurations enable Codex Here once during migration")
    func codexHereMigration() throws {
        let oldJSON = """
        {
          "schemaVersion" : 2,
          "actions" : [
            { "action" : "openWith", "isEnabled" : false, "order" : 0 }
          ]
        }
        """

        let decoded = try JSONDecoder().decode(
            ToolboxConfiguration.self,
            from: Data(oldJSON.utf8)
        )

        #expect(decoded.preference(for: .openWith)?.isEnabled == false)
        #expect(decoded.preference(for: .codexHere)?.isEnabled == true)
    }

    @Test("Removed file URL action stays decodable but cannot be re-enabled")
    func removedFileURLActionMigratesDisabled() throws {
        let oldJSON = """
        {
          "schemaVersion" : 2,
          "actions" : [
            { "action" : "copyFileURL", "isEnabled" : true, "order" : 0 }
          ]
        }
        """

        var decoded = try JSONDecoder().decode(
            ToolboxConfiguration.self,
            from: Data(oldJSON.utf8)
        )

        #expect(decoded.preference(for: .copyFileURL)?.isEnabled == false)
        #expect(!ToolboxAction.availableActions.contains(.copyFileURL))
        decoded.setEnabled(true, for: .copyFileURL)
        #expect(decoded.preference(for: .copyFileURL)?.isEnabled == false)
    }

    @Test("Group toggle and counts only consider implemented actions available")
    func groupToggleAndCounts() {
        var configuration = ToolboxConfiguration(preset: .developer)

        configuration.setGroupEnabled(true, for: .transfer)
        #expect(configuration.enabledActions(in: .transfer).map(\.action) == [
            .moveTo, .copyTo, .cut, .paste
        ])
        #expect(configuration.preference(for: .moveTo)?.isEnabled == true)

        configuration.setGroupEnabled(false, for: .newFile)
        var counts = configuration.counts(in: .newFile)
        #expect(counts.declaredActionCount == 8)
        #expect(counts.availableActionCount == 7)
        #expect(counts.enabledActionCount == 0)
        #expect(!counts.isFullyEnabled)
        #expect(!counts.isPartiallyEnabled)

        configuration.setGroupEnabled(true, for: .newFile)
        counts = configuration.counts(in: .newFile)
        #expect(counts.enabledActionCount == 7)
        #expect(counts.isFullyEnabled)
        #expect(configuration.preference(for: .newFile)?.isEnabled == false)
        #expect(configuration.availableActions(in: .newFile).count == 7)
    }

    @Test("An unavailable action cannot be enabled directly")
    func unavailableActionCannotBeEnabled() {
        var configuration = ToolboxConfiguration(preset: .all)
        configuration.setEnabled(true, for: .copyFileURL)
        #expect(configuration.preference(for: .copyFileURL)?.isEnabled == false)
    }

    @Test("User state controls enablement ordering and names")
    func userOverrides() {
        var configuration = ToolboxConfiguration(preset: .developer)
        configuration.setEnabled(true, for: .newRichText)
        configuration.setOrder(-1, for: .newRichText)
        configuration.setCustomName("Rich note", for: .newRichText)

        #expect(configuration.enabledActions().first?.action == .newRichText)
        #expect(configuration.preference(for: .newRichText)?.displayName == "Rich note")
    }

    @Test("Old Codable configuration gains typed new-file actions")
    func legacyCodableMigration() throws {
        let oldJSON = """
        {
          "actions" : [
            { "action" : "newFile", "isEnabled" : true, "order" : 0 },
            { "action" : "moveTo", "isEnabled" : true, "order" : 1 },
            { "action" : "copyAbsolutePath", "isEnabled" : true, "order" : 2,
              "customName" : "Path" }
          ]
        }
        """

        let decoded = try JSONDecoder().decode(
            ToolboxConfiguration.self,
            from: Data(oldJSON.utf8)
        )

        #expect(decoded.actions.count == ToolboxAction.allCases.count)
        #expect(decoded.preference(for: .newFile)?.isEnabled == false)
        #expect(decoded.preference(for: .moveTo)?.isEnabled == true)
        #expect(decoded.preference(for: .copyTo)?.isEnabled == true)
        #expect(decoded.preference(for: .copyAbsolutePath)?.displayName == "Path")
        for preset in NewFilePreset.allCases {
            #expect(decoded.preference(for: preset.toolboxAction)?.isEnabled == true)
        }
    }

    @Test("Unknown and malformed future actions do not discard known settings")
    func lossyFutureActionDecode() throws {
        let futureJSON = """
        {
          "actions" : [
            { "action" : "copyAbsolutePath", "isEnabled" : false, "order" : 2 },
            { "action" : "futureAction", "isEnabled" : true, "order" : 0 },
            { "action" : "newJSON", "isEnabled" : true, "order" : 1 },
            { "action" : 42, "isEnabled" : true, "order" : 3 }
          ]
        }
        """

        let decoded = try JSONDecoder().decode(
            ToolboxConfiguration.self,
            from: Data(futureJSON.utf8)
        )

        #expect(decoded.preference(for: .copyAbsolutePath)?.isEnabled == false)
        #expect(decoded.preference(for: .copyAbsolutePath)?.order == 2)
        #expect(decoded.preference(for: .newJSON)?.isEnabled == true)
        #expect(decoded.preference(for: .newJSON)?.order == 1)
        #expect(decoded.actions.count == ToolboxAction.allCases.count)
    }

    @Test("Fail-closed configuration disables every action")
    func allDisabledConfiguration() {
        let configuration = ToolboxConfiguration.allDisabled
        #expect(configuration.enabledActions().isEmpty)
        #expect(configuration.actions.count == ToolboxAction.allCases.count)
    }

    @Test("Every new-file preset maps to one unique toolbox action")
    func newFileMapping() {
        let mappedActions = NewFilePreset.allCases.map(\.toolboxAction)

        #expect(Set(mappedActions).count == NewFilePreset.allCases.count)
        for preset in NewFilePreset.allCases {
            #expect(preset.toolboxAction.newFilePreset == preset)
            #expect(preset.toolboxAction.group == .newFile)
            #expect(preset.toolboxAction.isImplemented)
        }
        #expect(ToolboxAction.newFile.newFilePreset == nil)
    }

    @Test("Configuration remains Codable after normalization")
    func codableRoundTrip() throws {
        var configuration = ToolboxConfiguration(preset: .file)
        configuration.setCustomName("Structured data", for: .newJSON)

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(ToolboxConfiguration.self, from: data)

        #expect(decoded == configuration)
    }
}
