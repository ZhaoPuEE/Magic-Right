import Foundation
import Testing
@testable import SuperRightCore

@Suite("Finder bookmark aliases")
struct FinderAliasServiceTests {
    @Test("Creates a Finder-resolvable alias without overwriting a collision")
    func createsResolvableCollisionSafeAlias() throws {
        try withAliasDirectories { sourceDirectory, destinationDirectory in
            let target = sourceDirectory.appendingPathComponent("report.txt")
            try Data("target".utf8).write(to: target)
            let collision = destinationDirectory.appendingPathComponent(
                "report Alias.txt"
            )
            try Data("keep".utf8).write(to: collision)

            let result = try FinderAliasService().createAlias(
                to: target,
                in: destinationDirectory,
                aliasLabel: "Alias"
            )

            #expect(result.aliasURL.lastPathComponent == "report Alias 2.txt")
            #expect(try Data(contentsOf: collision) == Data("keep".utf8))
            #expect(FileManager.default.fileExists(atPath: target.path))

            let bookmarkData = try URL.bookmarkData(
                withContentsOf: result.aliasURL
            )
            var isStale = false
            let resolved = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            #expect(resolved.standardizedFileURL == target.standardizedFileURL)
            #expect(!isStale)
        }
    }

    @Test("Directory aliases use a stable suffix and validate endpoints")
    func directoryAliasAndValidation() throws {
        try withAliasDirectories { sourceDirectory, destinationDirectory in
            let target = sourceDirectory.appendingPathComponent(
                "Project",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: target,
                withIntermediateDirectories: false
            )
            let result = try FinderAliasService().createAlias(
                to: target,
                in: destinationDirectory
            )
            #expect(result.aliasURL.lastPathComponent == "Project 替身")

            let missing = sourceDirectory.appendingPathComponent("missing")
            #expect(
                throws: FinderAliasServiceError.targetDoesNotExist(missing)
            ) {
                try FinderAliasService().createAlias(
                    to: missing,
                    in: destinationDirectory
                )
            }
            #expect(throws: FinderAliasServiceError.invalidAliasLabel) {
                try FinderAliasService().createAlias(
                    to: target,
                    in: destinationDirectory,
                    aliasLabel: "  "
                )
            }
        }
    }

    @Test("A broken symbolic link is treated as an existing Finder item")
    func aliasesBrokenSymbolicLink() throws {
        try withAliasDirectories { sourceDirectory, destinationDirectory in
            let missingTarget = sourceDirectory.appendingPathComponent("missing")
            let brokenLink = sourceDirectory.appendingPathComponent("broken-link")
            try FileManager.default.createSymbolicLink(
                at: brokenLink,
                withDestinationURL: missingTarget
            )

            let result = try FinderAliasService().createAlias(
                to: brokenLink,
                in: destinationDirectory
            )

            #expect(
                (try? URL.bookmarkData(withContentsOf: result.aliasURL)) != nil
            )
        }
    }
}

private func withAliasDirectories(
    _ body: (URL, URL) throws -> Void
) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let source = root.appendingPathComponent("source", isDirectory: true)
    let destination = root.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(source, destination)
}
