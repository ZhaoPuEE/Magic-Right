import Foundation
import Testing
@testable import SuperRightCore

@Suite("Collision-safe file transfer")
struct FileTransferServiceTests {
    @Test("Copy preserves the source and allocates a collision-safe name")
    func copyWithoutOverwrite() throws {
        try withTransferDirectories { sourceDirectory, destinationDirectory in
            let source = sourceDirectory.appendingPathComponent("report.txt")
            try Data("new".utf8).write(to: source)
            try Data("keep".utf8).write(
                to: destinationDirectory.appendingPathComponent("report.txt")
            )

            let result = try FileTransferService().transfer(
                FileTransferRequest(
                    kind: .copy,
                    sourceURL: source,
                    destinationDirectory: destinationDirectory
                )
            )

            #expect(result.destinationURL.lastPathComponent == "report 2.txt")
            #expect(try String(contentsOf: source, encoding: .utf8) == "new")
            #expect(try String(
                contentsOf: destinationDirectory.appendingPathComponent("report.txt"),
                encoding: .utf8
            ) == "keep")
        }
    }

    @Test("Move relocates the source without overwriting")
    func moveWithoutOverwrite() throws {
        try withTransferDirectories { sourceDirectory, destinationDirectory in
            let source = sourceDirectory.appendingPathComponent("Folder", isDirectory: true)
            try FileManager.default.createDirectory(
                at: source,
                withIntermediateDirectories: false
            )
            try FileManager.default.createDirectory(
                at: destinationDirectory.appendingPathComponent("Folder", isDirectory: true),
                withIntermediateDirectories: false
            )

            let result = try FileTransferService().transfer(
                FileTransferRequest(
                    kind: .move,
                    sourceURL: source,
                    destinationDirectory: destinationDirectory
                )
            )

            #expect(result.destinationURL.lastPathComponent == "Folder 2")
            #expect(!FileManager.default.fileExists(atPath: source.path))
            #expect(FileManager.default.fileExists(atPath: result.destinationURL.path))
        }
    }

    @Test("Moving into the current parent is rejected instead of renaming")
    func rejectsMoveToCurrentParent() throws {
        try withTransferDirectories { sourceDirectory, _ in
            let source = sourceDirectory.appendingPathComponent("report.txt")
            try Data("original".utf8).write(to: source)

            #expect(
                throws: FileTransferServiceError.moveDestinationIsCurrentParent(
                    source: source,
                    destination: sourceDirectory
                )
            ) {
                try FileTransferService().transfer(
                    FileTransferRequest(
                        kind: .move,
                        sourceURL: source,
                        destinationDirectory: sourceDirectory
                    )
                )
            }

            #expect(try String(contentsOf: source, encoding: .utf8) == "original")
            #expect(
                !FileManager.default.fileExists(
                    atPath: sourceDirectory.appendingPathComponent("report 2.txt").path
                )
            )
        }
    }

    @Test("Copying into the current parent creates a collision-safe duplicate")
    func copiesToCurrentParent() throws {
        try withTransferDirectories { sourceDirectory, _ in
            let source = sourceDirectory.appendingPathComponent("report.txt")
            try Data("original".utf8).write(to: source)

            let result = try FileTransferService().transfer(
                FileTransferRequest(
                    kind: .copy,
                    sourceURL: source,
                    destinationDirectory: sourceDirectory
                )
            )

            #expect(result.destinationURL.lastPathComponent == "report 2.txt")
            #expect(try String(contentsOf: source, encoding: .utf8) == "original")
            #expect(
                try String(contentsOf: result.destinationURL, encoding: .utf8)
                    == "original"
            )
        }
    }

    @Test("A folder cannot be moved or copied to itself or a descendant")
    func rejectsRecursiveDestination() throws {
        try withTransferDirectories { sourceDirectory, _ in
            let source = sourceDirectory.appendingPathComponent("source", isDirectory: true)
            let nested = source.appendingPathComponent("nested", isDirectory: true)
            try FileManager.default.createDirectory(
                at: nested,
                withIntermediateDirectories: true
            )

            let requests = [source, nested].flatMap { destination in
                [FileTransferKind.move, .copy].map { kind in
                    FileTransferRequest(
                        kind: kind,
                        sourceURL: source,
                        destinationDirectory: destination
                    )
                }
            }
            for request in requests {
                #expect(throws: FileTransferServiceError.destinationIsInsideSource(
                    source: source,
                    destination: request.destinationDirectory
                )) {
                    try FileTransferService().transfer(request)
                }
            }
            #expect(FileManager.default.fileExists(atPath: source.path))
        }
    }

    @Test("A symlink cannot disguise a destination inside the source")
    func rejectsSymlinkedRecursiveDestination() throws {
        try withTransferDirectories { sourceDirectory, _ in
            let source = sourceDirectory.appendingPathComponent("source", isDirectory: true)
            let nested = source.appendingPathComponent("nested", isDirectory: true)
            let disguisedDestination = sourceDirectory.appendingPathComponent(
                "destination-link",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: nested,
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                at: disguisedDestination,
                withDestinationURL: nested
            )

            #expect(throws: FileTransferServiceError.destinationIsInsideSource(
                source: source,
                destination: disguisedDestination
            )) {
                try FileTransferService().transfer(
                    FileTransferRequest(
                        kind: .copy,
                        sourceURL: source,
                        destinationDirectory: disguisedDestination
                    )
                )
            }
            #expect(
                !FileManager.default.fileExists(
                    atPath: nested.appendingPathComponent("source").path
                )
            )
        }
    }

    @Test("Broken symbolic links remain movable and copyable Finder items")
    func transfersBrokenSymbolicLinks() throws {
        try withTransferDirectories { sourceDirectory, destinationDirectory in
            for kind in [FileTransferKind.copy, .move] {
                let source = sourceDirectory.appendingPathComponent(
                    "broken-\(kind.rawValue)"
                )
                let missingTarget = sourceDirectory.appendingPathComponent(
                    "missing-\(kind.rawValue)"
                )
                try FileManager.default.createSymbolicLink(
                    at: source,
                    withDestinationURL: missingTarget
                )

                let result = try FileTransferService().transfer(
                    FileTransferRequest(
                        kind: kind,
                        sourceURL: source,
                        destinationDirectory: destinationDirectory
                    )
                )

                #expect(
                    try FileManager.default.destinationOfSymbolicLink(
                        atPath: result.destinationURL.path
                    ) == missingTarget.path
                )
                let sourceStillExists = (
                    try? FileManager.default.attributesOfItem(atPath: source.path)
                ) != nil
                #expect(sourceStillExists == (kind == .copy))
            }
        }
    }

    @Test("Missing sources and invalid destinations fail before mutation")
    func validatesEndpointsBeforeMutation() throws {
        try withTransferDirectories { sourceDirectory, destinationDirectory in
            let missingSource = sourceDirectory.appendingPathComponent("missing.txt")
            let missingDestination = destinationDirectory.appendingPathComponent(
                "missing",
                isDirectory: true
            )
            let destinationFile = destinationDirectory.appendingPathComponent("file.txt")
            try Data("destination".utf8).write(to: destinationFile)

            #expect(throws: FileTransferServiceError.sourceDoesNotExist(missingSource)) {
                try FileTransferService().transfer(
                    FileTransferRequest(
                        kind: .move,
                        sourceURL: missingSource,
                        destinationDirectory: destinationDirectory
                    )
                )
            }

            let source = sourceDirectory.appendingPathComponent("source.txt")
            try Data("source".utf8).write(to: source)
            #expect(
                throws: FileTransferServiceError.destinationDoesNotExist(
                    missingDestination
                )
            ) {
                try FileTransferService().transfer(
                    FileTransferRequest(
                        kind: .move,
                        sourceURL: source,
                        destinationDirectory: missingDestination
                    )
                )
            }
            #expect(
                throws: FileTransferServiceError.destinationIsNotDirectory(
                    destinationFile
                )
            ) {
                try FileTransferService().transfer(
                    FileTransferRequest(
                        kind: .copy,
                        sourceURL: source,
                        destinationDirectory: destinationFile
                    )
                )
            }

            #expect(try String(contentsOf: source, encoding: .utf8) == "source")
            #expect(
                try String(contentsOf: destinationFile, encoding: .utf8)
                    == "destination"
            )
        }
    }

    @Test("Operation journal stays bounded and Codable")
    func boundedJournal() throws {
        var journal = FileOperationJournal()
        for index in 0..<4 {
            let result = FileTransferResult(
                kind: .copy,
                sourceURL: URL(fileURLWithPath: "/source/\(index)"),
                destinationURL: URL(fileURLWithPath: "/destination/\(index)")
            )
            journal.append(
                FileOperationRecord(result: result),
                maximumRecordCount: 3
            )
        }

        #expect(journal.records.count == 3)
        #expect(journal.records.first?.result.sourceURL.lastPathComponent == "1")
        let decoded = try JSONDecoder().decode(
            FileOperationJournal.self,
            from: JSONEncoder().encode(journal)
        )
        #expect(decoded == journal)
    }
}

private func withTransferDirectories(
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
