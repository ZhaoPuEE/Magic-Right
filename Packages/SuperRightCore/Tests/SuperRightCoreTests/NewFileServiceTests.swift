import Foundation
import Testing
@testable import SuperRightCore

@Suite("Built-in new files")
struct NewFileServiceTests {
    @Test("Every preset has the expected initial filename and valid contents")
    func presetNamesAndContents() throws {
        #expect(NewFilePreset.markdown.defaultFileName == "未命名.md")
        #expect(NewFilePreset.plainText.defaultFileName == "未命名.txt")
        #expect(NewFilePreset.richText.defaultFileName == "未命名.rtf")
        #expect(NewFilePreset.xml.defaultFileName == "未命名.xml")
        #expect(NewFilePreset.json.defaultFileName == "未命名.json")
        #expect(NewFilePreset.yaml.defaultFileName == "未命名.yaml")
        #expect(NewFilePreset.gitignore.defaultFileName == ".gitignore")

        #expect(NewFilePreset.markdown.initialContents.isEmpty)
        #expect(NewFilePreset.plainText.initialContents.isEmpty)
        #expect(NewFilePreset.gitignore.initialContents.isEmpty)
        #expect(String(decoding: NewFilePreset.richText.initialContents, as: UTF8.self)
            == "{\\rtf1\\ansi\n}\n")
        #expect(String(decoding: NewFilePreset.xml.initialContents, as: UTF8.self)
            == "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root />\n")

        let jsonObject = try JSONSerialization.jsonObject(
            with: NewFilePreset.json.initialContents
        ) as? [String: String]
        #expect(jsonObject == [:])
        #expect(String(decoding: NewFilePreset.yaml.initialContents, as: UTF8.self)
            == "---\n{}\n")
    }

    @Test("Creates each preset with exact contents")
    func createsPresetContents() throws {
        try withTemporaryDirectory { directory in
            let service = NewFileService()

            for preset in NewFilePreset.allCases {
                let result = try service.createFile(
                    for: NewFileRequest(
                        preset: preset,
                        destinationDirectory: directory
                    )
                )
                #expect(result.lastPathComponent == preset.defaultFileName)
                #expect(try Data(contentsOf: result) == preset.initialContents)
            }
        }
    }

    @Test("Existing files get Finder-style suffixes and are never overwritten")
    func resolvesConflictsWithoutOverwriting() throws {
        try withTemporaryDirectory { directory in
            let existing = directory.appendingPathComponent("未命名.json")
            let sentinel = Data("keep me".utf8)
            try sentinel.write(to: existing)

            let result = try NewFileService().createFile(
                for: NewFileRequest(
                    preset: .json,
                    destinationDirectory: directory
                )
            )

            #expect(result.lastPathComponent == "未命名 2.json")
            #expect(try Data(contentsOf: existing) == sentinel)
            #expect(try Data(contentsOf: result) == NewFilePreset.json.initialContents)
        }
    }

    @Test("Multiple creations keep allocating increasing names")
    func multipleCreations() throws {
        try withTemporaryDirectory { directory in
            let service = NewFileService()
            let request = NewFileRequest(
                preset: .markdown,
                destinationDirectory: directory
            )

            let names = try (0..<4).map { _ in
                try service.createFile(for: request).lastPathComponent
            }

            #expect(names == [
                "未命名.md",
                "未命名 2.md",
                "未命名 3.md",
                "未命名 4.md"
            ])
        }
    }

    @Test("gitignore remains a hidden filename when conflicts occur")
    func hiddenFileNaming() throws {
        try withTemporaryDirectory { directory in
            let service = NewFileService()
            let request = NewFileRequest(
                preset: .gitignore,
                destinationDirectory: directory
            )

            let first = try service.createFile(for: request)
            let second = try service.createFile(for: request)

            #expect(first.lastPathComponent == ".gitignore")
            #expect(second.lastPathComponent == ".gitignore 2")
            #expect(FileManager.default.fileExists(atPath: first.path))
            #expect(FileManager.default.fileExists(atPath: second.path))
        }
    }

    @Test("Missing destination is rejected without creating it")
    func missingDestination() throws {
        try withTemporaryDirectory { parent in
            let missing = parent.appendingPathComponent("missing", isDirectory: true)
            let request = NewFileRequest(
                preset: .plainText,
                destinationDirectory: missing
            )

            #expect(throws: NewFileServiceError.destinationDoesNotExist(missing)) {
                try NewFileService().createFile(for: request)
            }
            #expect(!FileManager.default.fileExists(atPath: missing.path))
        }
    }

    @Test("A regular file cannot be used as the destination directory")
    func destinationMustBeDirectory() throws {
        try withTemporaryDirectory { directory in
            let regularFile = directory.appendingPathComponent("target")
            try Data().write(to: regularFile)
            let request = NewFileRequest(
                preset: .xml,
                destinationDirectory: regularFile
            )

            #expect(throws: NewFileServiceError.destinationIsNotDirectory(regularFile)) {
                try NewFileService().createFile(for: request)
            }
            #expect(try Data(contentsOf: regularFile).isEmpty)
        }
    }

    @Test("An exclusive-create collision retries instead of overwriting")
    func retriesRaceCollision() throws {
        let directory = URL(fileURLWithPath: "/virtual/destination", isDirectory: true)
        let fileSystem = CollisionFileSystem()
        let result = try NewFileService(fileSystem: fileSystem).createFile(
            for: NewFileRequest(
                preset: .plainText,
                destinationDirectory: directory
            )
        )

        #expect(result.lastPathComponent == "未命名 2.txt")
    }
}

private struct CollisionFileSystem: NewFileFileSystem {
    func itemKind(at url: URL) throws -> NewFileItemKind? {
        .directory
    }

    func createFileExclusively(at url: URL, contents: Data) throws -> Bool {
        url.lastPathComponent != "未命名.txt"
    }
}

private func withTemporaryDirectory(
    _ body: (URL) throws -> Void
) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}
