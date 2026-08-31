import Foundation
import Testing
@testable import SuperRightCore

@Suite("File information")
struct FileInformationServiceTests {
    @Test("Reads type, size, timestamps, permissions, and an on-demand SHA-256")
    func regularFileInformationAndHash() throws {
        try withInformationDirectory { directory in
            let file = directory.appendingPathComponent("sample.txt")
            try Data("abc".utf8).write(to: file)

            let information = try FileInformationService().information(
                for: file,
                options: FileInformationOptions(calculateSHA256: true)
            )

            #expect(information.url == file.standardizedFileURL)
            #expect(information.name == "sample.txt")
            #expect(information.kind == .regularFile)
            #expect(information.logicalSizeInBytes == 3)
            #expect(information.creationDate != nil)
            #expect(information.modificationDate != nil)
            #expect(information.posixPermissions != nil)
            #expect(
                information.sha256
                    == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            )

            let decoded = try JSONDecoder().decode(
                FileItemInformation.self,
                from: JSONEncoder().encode(information)
            )
            #expect(decoded == information)
        }
    }

    @Test("Directory size is calculated only when requested")
    func optionalDirectorySize() throws {
        try withInformationDirectory { directory in
            let nested = directory.appendingPathComponent("nested", isDirectory: true)
            try FileManager.default.createDirectory(
                at: nested,
                withIntermediateDirectories: false
            )
            try Data("one".utf8).write(
                to: directory.appendingPathComponent("one.txt")
            )
            try Data("three".utf8).write(
                to: nested.appendingPathComponent("three.txt")
            )

            let fast = try FileInformationService().information(for: directory)
            let calculated = try FileInformationService().information(
                for: directory,
                options: FileInformationOptions(calculateDirectorySize: true)
            )

            #expect(fast.kind == .directory)
            #expect(fast.logicalSizeInBytes == nil)
            #expect(calculated.logicalSizeInBytes == 8)
            #expect(calculated.allocatedSizeInBytes != nil)
        }
    }

    @Test("Missing items and directory hashes fail explicitly")
    func rejectsInvalidRequests() throws {
        try withInformationDirectory { directory in
            let missing = directory.appendingPathComponent("missing")
            #expect(
                throws: FileInformationServiceError.itemDoesNotExist(missing)
            ) {
                try FileInformationService().information(for: missing)
            }
            #expect(
                throws: FileInformationServiceError.sha256RequiresRegularFile(
                    directory.standardizedFileURL
                )
            ) {
                try FileInformationService().information(
                    for: directory,
                    options: FileInformationOptions(calculateSHA256: true)
                )
            }
        }
    }

    @Test("Broken symbolic links still expose entry information")
    func brokenSymbolicLinkInformation() throws {
        try withInformationDirectory { directory in
            let missingTarget = directory.appendingPathComponent("missing")
            let link = directory.appendingPathComponent("broken-link")
            try FileManager.default.createSymbolicLink(
                at: link,
                withDestinationURL: missingTarget
            )

            let information = try FileInformationService().information(for: link)

            #expect(information.kind == .symbolicLink)
            #expect(information.name == "broken-link")
            #expect(information.logicalSizeInBytes != nil)
            #expect(throws: FileInformationServiceError.sha256RequiresRegularFile(link)) {
                try FileInformationService().information(
                    for: link,
                    options: FileInformationOptions(calculateSHA256: true)
                )
            }
        }
    }
}

private func withInformationDirectory(
    _ body: (URL) throws -> Void
) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}
