import Foundation
import Testing
@testable import SuperRightCore

@Suite("Shared storage fallback")
struct SharedStorageManagerTests {
    @Test("Pure selection prefers a complete App Group backend")
    func prefersAppGroup() throws {
        let appGroupURL = URL(fileURLWithPath: "/groups/magic-right", isDirectory: true)
        let fallbackURL = URL(fileURLWithPath: "/fallback/shared", isDirectory: true)

        let location = try #require(
            SharedStorageLocation.preferred(
                appGroupSuiteName: "group.test.magic-right",
                appGroupContainerURL: appGroupURL,
                isAppGroupSuiteAvailable: true,
                fallbackSuiteName: "test.magic-right.shared",
                fallbackContainerURL: fallbackURL,
                isFallbackSuiteAvailable: true
            )
        )

        #expect(location.kind == .appGroup)
        #expect(location.suiteName == "group.test.magic-right")
        #expect(location.containerURL == appGroupURL)
    }

    @Test("Pure selection requires both App Group parts and falls back")
    func incompleteAppGroupFallsBack() throws {
        let fallbackURL = URL(fileURLWithPath: "/fallback/shared", isDirectory: true)

        let missingContainer = try #require(
            SharedStorageLocation.preferred(
                appGroupSuiteName: "group.test.magic-right",
                appGroupContainerURL: nil,
                isAppGroupSuiteAvailable: true,
                fallbackSuiteName: "test.magic-right.shared",
                fallbackContainerURL: fallbackURL,
                isFallbackSuiteAvailable: true
            )
        )
        let missingSuite = try #require(
            SharedStorageLocation.preferred(
                appGroupSuiteName: "group.test.magic-right",
                appGroupContainerURL: URL(fileURLWithPath: "/group", isDirectory: true),
                isAppGroupSuiteAvailable: false,
                fallbackSuiteName: "test.magic-right.shared",
                fallbackContainerURL: fallbackURL,
                isFallbackSuiteAvailable: true
            )
        )

        #expect(missingContainer.kind == .applicationSupportFallback)
        #expect(missingSuite.kind == .applicationSupportFallback)
        #expect(missingContainer.containerURL == fallbackURL)
    }

    @Test("Manager creates and exposes the Application Support fallback")
    func createsFallbackDirectory() throws {
        try withTemporaryDirectory { root in
            let suiteName = "dev.magicright.tests.\(UUID().uuidString)"
            defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

            let manager = SharedStorageManager(
                appGroupSuiteName: "group.unavailable",
                fallbackSuiteName: suiteName,
                applicationSupportURL: root,
                appGroupContainerProvider: { _ in nil }
            )

            let expectedURL = root
                .appendingPathComponent("Magic Right", isDirectory: true)
                .appendingPathComponent("Shared", isDirectory: true)
            #expect(manager.isAvailable)
            #expect(!manager.isAppGroupAvailable)
            #expect(manager.location?.kind == .applicationSupportFallback)
            #expect(manager.containerURL == expectedURL)
            #expect(manager.defaults != nil)
            var isDirectory = ObjCBool(false)
            #expect(
                FileManager.default.fileExists(
                    atPath: expectedURL.path,
                    isDirectory: &isDirectory
                )
            )
            #expect(isDirectory.boolValue)
        }
    }

    @Test("A valid App Group does not create the fallback directory")
    func appGroupSkipsFallbackCreation() throws {
        let appGroupURL = URL(fileURLWithPath: "/group/container", isDirectory: true)
        var createdDirectories: [URL] = []

        let manager = SharedStorageManager(
            appGroupSuiteName: "group.available",
            fallbackSuiteName: "fallback.unused",
            applicationSupportURL: URL(fileURLWithPath: "/fallback", isDirectory: true),
            appGroupContainerProvider: { _ in appGroupURL },
            defaultsProvider: { _ in UserDefaults.standard },
            directoryCreator: { createdDirectories.append($0) }
        )

        #expect(manager.isAvailable)
        #expect(manager.isAppGroupAvailable)
        #expect(manager.containerURL == appGroupURL)
        #expect(createdDirectories.isEmpty)
    }

    @Test("Fallback directory creation failure reports unavailable storage")
    func failedFallbackCreationIsUnavailable() {
        let manager = SharedStorageManager(
            appGroupSuiteName: "group.unavailable",
            fallbackSuiteName: "fallback.unavailable",
            applicationSupportURL: URL(fileURLWithPath: "/unavailable", isDirectory: true),
            appGroupContainerProvider: { _ in nil },
            defaultsProvider: { _ in UserDefaults.standard },
            directoryCreator: { _ in throw CocoaError(.fileWriteNoPermission) }
        )

        #expect(!manager.isAvailable)
        #expect(!manager.isAppGroupAvailable)
        #expect(manager.containerURL == nil)
        #expect(manager.defaults == nil)
    }
}

private func withTemporaryDirectory(
    _ body: (URL) throws -> Void
) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}
