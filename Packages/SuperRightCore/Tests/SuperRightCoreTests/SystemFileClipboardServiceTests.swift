import AppKit
import Foundation
import Testing
@testable import SuperRightCore

@Suite("Interoperable system file clipboard")
struct SystemFileClipboardServiceTests {
    @MainActor
    @Test("Cut remains a standard NSURL file clipboard and retains cut intent")
    func standardFileURLCut() throws {
        try withClipboardFixture { pasteboard, sourceDirectory, _ in
            let source = sourceDirectory.appendingPathComponent("report.txt")
            try Data("report".utf8).write(to: source)
            let service = SystemFileClipboardService(pasteboard: pasteboard)

            do {
                try service.write(fileURLs: [source], operation: .cut)
            } catch SystemFileClipboardError.unableToWritePasteboard {
                // Some command-line CI sessions have no pasteboard server.
                // The same assertions execute in Xcode and GUI test sessions.
                return
            }

            let externalReader = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [NSURL]
            #expect(externalReader?.map { $0 as URL } == [source])
            #expect(pasteboard.types?.contains(.fileURL) == true)
            #expect(
                pasteboard.propertyList(
                    forType: SystemFileClipboardService.legacyFilenamesPasteboardType
                ) as? [String] == [source.path]
            )
            #expect(service.read()?.operation == .cut)
            #expect(service.read()?.fileURLs == [source])
        }
    }

    @MainActor
    @Test("Replacing the pasteboard removes Magic Right cut semantics")
    func externalClipboardReplacementDefaultsToCopy() throws {
        try withClipboardFixture { pasteboard, sourceDirectory, _ in
            let original = sourceDirectory.appendingPathComponent("original.txt")
            let replacement = sourceDirectory.appendingPathComponent("replacement.txt")
            try Data().write(to: original)
            try Data().write(to: replacement)
            let service = SystemFileClipboardService(pasteboard: pasteboard)

            do {
                try service.write(fileURLs: [original], operation: .cut)
            } catch SystemFileClipboardError.unableToWritePasteboard {
                return
            }
            pasteboard.clearContents()
            #expect(pasteboard.writeObjects([replacement as NSURL]))

            #expect(service.read()?.fileURLs == [replacement])
            #expect(service.read()?.operation == .copy)
        }
    }

    @MainActor
    @Test("Copy paste allocates a safe name and leaves the clipboard intact")
    func copyPasteIsCollisionSafe() async throws {
        try await withClipboardFixture { pasteboard, sourceDirectory, destination in
            let source = sourceDirectory.appendingPathComponent("report.txt")
            try Data("new".utf8).write(to: source)
            try Data("keep".utf8).write(
                to: destination.appendingPathComponent("report.txt")
            )
            let service = SystemFileClipboardService(pasteboard: pasteboard)
            do {
                try service.write(fileURLs: [source], operation: .copy)
            } catch SystemFileClipboardError.unableToWritePasteboard {
                return
            }

            let results = try await service.paste(into: destination)

            #expect(results.map(\.destinationURL.lastPathComponent) == ["report 2.txt"])
            #expect(FileManager.default.fileExists(atPath: source.path))
            #expect(service.read()?.fileURLs == [source])
            #expect(service.read()?.operation == .copy)
        }
    }

    @MainActor
    @Test("Successful cut paste moves all sources and consumes the marker")
    func cutPasteClearsClipboard() async throws {
        try await withClipboardFixture { pasteboard, sourceDirectory, destination in
            let source = sourceDirectory.appendingPathComponent("move-me.txt")
            try Data("move".utf8).write(to: source)
            let service = SystemFileClipboardService(pasteboard: pasteboard)
            do {
                try service.write(fileURLs: [source], operation: .cut)
            } catch SystemFileClipboardError.unableToWritePasteboard {
                return
            }

            let results = try await service.paste(into: destination)

            #expect(results.count == 1)
            #expect(!FileManager.default.fileExists(atPath: source.path))
            #expect(service.read() == nil)
            #expect(
                pasteboard.availableType(from: [
                    SystemFileClipboardService.cutMarkerPasteboardType
                ]) == nil
            )
        }
    }

    @MainActor
    @Test("Partial cut finalization keeps only sources that were not moved")
    func partialCutKeepsRemainingSources() throws {
        try withClipboardFixture { pasteboard, sourceDirectory, destination in
            let first = sourceDirectory.appendingPathComponent("first.txt")
            let second = sourceDirectory.appendingPathComponent("second.txt")
            try Data("first".utf8).write(to: first)
            try Data("second".utf8).write(to: second)
            let service = SystemFileClipboardService(pasteboard: pasteboard)
            let original: FileClipboardContents
            do {
                original = try service.write(
                    fileURLs: [first, second],
                    operation: .cut
                )
            } catch SystemFileClipboardError.unableToWritePasteboard {
                return
            }
            let completed = try FileTransferService().transfer(
                FileTransferRequest(
                    kind: .move,
                    sourceURL: first,
                    destinationDirectory: destination
                )
            )

            try service.finalizeCutPaste(
                original: original,
                completedResults: [completed]
            )

            #expect(service.read()?.operation == .cut)
            #expect(service.read()?.fileURLs == [second])
            #expect(FileManager.default.fileExists(atPath: second.path))
        }
    }

    @MainActor
    @Test("Finalization never clears a clipboard replaced by another app")
    func preservesNewerExternalClipboard() throws {
        try withClipboardFixture { pasteboard, sourceDirectory, destination in
            let originalURL = sourceDirectory.appendingPathComponent("original.txt")
            let externalURL = sourceDirectory.appendingPathComponent("external.txt")
            try Data().write(to: originalURL)
            try Data().write(to: externalURL)
            let service = SystemFileClipboardService(pasteboard: pasteboard)
            let original: FileClipboardContents
            do {
                original = try service.write(
                    fileURLs: [originalURL],
                    operation: .cut
                )
            } catch SystemFileClipboardError.unableToWritePasteboard {
                return
            }
            pasteboard.clearContents()
            #expect(pasteboard.writeObjects([externalURL as NSURL]))
            let completed = FileTransferResult(
                kind: .move,
                sourceURL: originalURL,
                destinationURL: destination.appendingPathComponent("original.txt")
            )

            try service.finalizeCutPaste(
                original: original,
                completedResults: [completed]
            )

            #expect(service.read()?.operation == .copy)
            #expect(service.read()?.fileURLs == [externalURL])
        }
    }

    @MainActor
    @Test("Partial paste reports a cut-clipboard rewrite failure")
    func partialPasteReportsCutClipboardRewriteFailure() async throws {
        try await withClipboardFixture { pasteboard, sourceDirectory, destination in
            let first = sourceDirectory.appendingPathComponent("first.txt")
            let second = sourceDirectory.appendingPathComponent("second.txt")
            try Data("first".utf8).write(to: first)
            try Data("second".utf8).write(to: second)

            var pasteboardWriteCount = 0
            let service = SystemFileClipboardService(
                pasteboard: pasteboard,
                transferOperation: { request in
                    if request.sourceURL == second {
                        throw FileTransferServiceError.sourceDoesNotExist(second)
                    }
                    return try FileTransferService().transfer(request)
                },
                pasteboardItemWriter: { pasteboard, items in
                    pasteboardWriteCount += 1
                    guard pasteboardWriteCount < 2 else { return false }
                    return pasteboard.writeObjects(items)
                }
            )
            do {
                try service.write(fileURLs: [first, second], operation: .cut)
            } catch SystemFileClipboardError.unableToWritePasteboard {
                return
            }

            do {
                _ = try await service.paste(into: destination)
                Issue.record("Expected the second transfer to fail")
            } catch let error as FileClipboardPartialTransferError {
                #expect(error.failedSourceURL == second)
                #expect(error.completedResults.count == 1)
                #expect(error.completedResults.first?.sourceURL == first)
                #expect(error.cutClipboardFinalizationErrorDescription != nil)
            }
        }
    }

    @MainActor
    @Test("Completed cut paste retains results when clipboard clearing fails")
    func completedCutPasteReportsClipboardFinalizationFailure() async throws {
        try await withClipboardFixture { pasteboard, sourceDirectory, destination in
            let source = sourceDirectory.appendingPathComponent("move-me.txt")
            try Data("move".utf8).write(to: source)
            let service = SystemFileClipboardService(
                pasteboard: pasteboard,
                transferOperation: { request in
                    try FileTransferService().transfer(request)
                },
                pasteboardContentsClearer: { pasteboard in
                    pasteboard.changeCount
                },
                pasteboardItemWriter: { pasteboard, items in
                    pasteboard.writeObjects(items)
                }
            )
            do {
                try service.write(fileURLs: [source], operation: .cut)
            } catch SystemFileClipboardError.unableToWritePasteboard {
                return
            }

            do {
                _ = try await service.paste(into: destination)
                Issue.record("Expected cut-clipboard finalization to fail")
            } catch let error as FileClipboardPasteFinalizationError {
                #expect(error.completedResults.count == 1)
                #expect(error.completedResults.first?.sourceURL == source)
                #expect(
                    error.completedResults.first?.destinationURL
                        == destination.appendingPathComponent("move-me.txt")
                )
                #expect(
                    error.underlyingErrorDescription.contains(
                        "unableToClearPasteboard"
                    )
                )
            }

            #expect(!FileManager.default.fileExists(atPath: source.path))
            #expect(
                FileManager.default.fileExists(
                    atPath: destination.appendingPathComponent("move-me.txt").path
                )
            )
        }
    }

    @MainActor
    @Test("A broken symbolic link can travel through the system file clipboard")
    func pastesBrokenSymbolicLink() async throws {
        try await withClipboardFixture { pasteboard, sourceDirectory, destination in
            let missingTarget = sourceDirectory.appendingPathComponent("missing")
            let brokenLink = sourceDirectory.appendingPathComponent("broken-link")
            try FileManager.default.createSymbolicLink(
                at: brokenLink,
                withDestinationURL: missingTarget
            )
            let service = SystemFileClipboardService(pasteboard: pasteboard)
            do {
                try service.write(fileURLs: [brokenLink], operation: .copy)
            } catch SystemFileClipboardError.unableToWritePasteboard {
                return
            }

            let results = try await service.paste(into: destination)
            let copiedLink = try #require(results.first?.destinationURL)

            #expect(
                try FileManager.default.destinationOfSymbolicLink(
                    atPath: copiedLink.path
                ) == missingTarget.path
            )
        }
    }
}

@MainActor
private func withClipboardFixture(
    _ body: (NSPasteboard, URL, URL) throws -> Void
) throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer {
        pasteboard.clearContents()
        pasteboard.releaseGlobally()
    }
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let source = root.appendingPathComponent("source", isDirectory: true)
    let destination = root.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(pasteboard, source, destination)
}

@MainActor
private func withClipboardFixture(
    _ body: (NSPasteboard, URL, URL) async throws -> Void
) async throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer {
        pasteboard.clearContents()
        pasteboard.releaseGlobally()
    }
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let source = root.appendingPathComponent("source", isDirectory: true)
    let destination = root.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(pasteboard, source, destination)
}
