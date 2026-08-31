import Foundation
import Testing
@testable import SuperRightCore

@Suite("Structured application open requests")
struct ApplicationOpenRequestTests {
    @Test("Zed receives every selected URL in order")
    func zedMultiSelection() throws {
        let zed = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "dev.zed.Zed"
            )
        )
        let urls = [
            URL(fileURLWithPath: "/tmp/first file.swift"),
            URL(fileURLWithPath: "/tmp/second.swift")
        ]

        let request = try ApplicationOpenRequestBuilder.makeRequest(
            for: zed,
            intent: .selection(urls)
        )

        #expect(request == .openURLs(
            OpenURLsRequest(
                applicationBundleIdentifier: "dev.zed.Zed",
                urls: urls
            )
        ))
    }

    @Test("Git root is an explicit URL request")
    func gitRootRequest() throws {
        let vscode = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "com.microsoft.VSCode"
            )
        )
        let root = URL(fileURLWithPath: "/Users/test/repository")

        let request = try ApplicationOpenRequestBuilder.makeRequest(
            for: vscode,
            intent: .gitRoot(root)
        )

        #expect(request == .openURLs(
            OpenURLsRequest(
                applicationBundleIdentifier: "com.microsoft.VSCode",
                urls: [root]
            )
        ))
    }

    @Test("Tabby uses its URL handler so an existing window receives a new tab")
    func tabbyUsesExistingInstanceURL() throws {
        let tabby = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "org.tabby"
            )
        )
        let directory = URL(fileURLWithPath: "/tmp/a folder; touch danger")

        let request = try ApplicationOpenRequestBuilder.makeRequest(
            for: tabby,
            intent: .currentDirectory(directory)
        )

        guard case let .openURLs(openRequest) = request,
              let url = openRequest.urls.first,
              let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
              ) else {
            Issue.record("Expected a Tabby URL request")
            return
        }
        #expect(openRequest.applicationBundleIdentifier == "org.tabby")
        #expect(components.scheme == "tabby")
        #expect(components.host == "open")
        #expect(
            components.queryItems?.first(where: { $0.name == "directory" })?.value
                == directory.path
        )
    }

    @Test("Tabby converts a selected file to its parent directory")
    func tabbySelectedFileUsesParentDirectory() throws {
        let tabby = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "org.tabby"
            )
        )
        let file = URL(fileURLWithPath: "/tmp/Magic Right/project/main.swift")
        let parent = file.deletingLastPathComponent()

        let request = try ApplicationOpenRequestBuilder.makeRequest(
            for: tabby,
            intent: .selection([file])
        )

        guard case let .openURLs(openRequest) = request,
              let url = openRequest.urls.first,
              let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
              ) else {
            Issue.record("Expected a Tabby URL request")
            return
        }
        #expect(components.host == "open")
        #expect(
            components.queryItems?.first(where: { $0.name == "directory" })?.value
                == parent.path
        )
    }

    @Test("Tabby preserves a selected directory")
    func tabbySelectedDirectoryIsPreserved() throws {
        let tabby = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "org.tabby"
            )
        )
        let directory = URL(
            fileURLWithPath: "/tmp/Magic Right/project",
            isDirectory: true
        )

        let request = try ApplicationOpenRequestBuilder.makeRequest(
            for: tabby,
            intent: .selection([directory])
        )

        guard case let .openURLs(openRequest) = request,
              let url = openRequest.urls.first,
              let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
              ) else {
            Issue.record("Expected a Tabby URL request")
            return
        }
        #expect(components.host == "open")
        #expect(
            components.queryItems?.first(where: { $0.name == "directory" })?.value
                == directory.path
        )
    }

    @Test("Codex Here requests a new local zsh tab in Tabby's existing window")
    func codexHereLocalZshURL() throws {
        let directory = URL(
            fileURLWithPath: "/tmp/a folder; touch danger",
            isDirectory: true
        )
        let codex = URL(fileURLWithPath: "/opt/homebrew/bin/codex")

        let request = try ApplicationOpenRequestBuilder.makeCodexHereRequest(
            codexExecutableURL: codex,
            intent: .currentDirectory(directory)
        )

        guard case let .openURLs(openRequest) = request,
              let url = openRequest.urls.first,
              let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
              ) else {
            Issue.record("Expected a Tabby URL request")
            return
        }
        let command = components.queryItems?.first {
            $0.name == "command"
        }?.value
        #expect(openRequest.applicationBundleIdentifier == "org.tabby")
        #expect(components.scheme == "tabby")
        #expect(components.host == "run")
        #expect(command == [
            "'/bin/zsh'",
            "'-l'",
            "'-i'",
            "'-c'",
            #"'cd -- "$1" && exec "$2"'"#,
            "'magic-right'",
            "'\(directory.path)'",
            "'\(codex.path)'"
        ].joined(separator: " "))
    }

    @Test("Codex Here converts a selected file to its parent directory")
    func codexHereSelectedFileUsesParentDirectory() throws {
        let file = URL(fileURLWithPath: "/tmp/Magic Right/project/main.swift")
        let codex = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")

        let request = try ApplicationOpenRequestBuilder.makeCodexHereRequest(
            codexExecutableURL: codex,
            intent: .selection([file])
        )

        guard case let .openURLs(openRequest) = request,
              let url = openRequest.urls.first,
              let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
              ) else {
            Issue.record("Expected a Tabby URL request")
            return
        }
        let command = components.queryItems?.first {
            $0.name == "command"
        }?.value
        #expect(command?.contains("'\(file.deletingLastPathComponent().path)'") == true)
        #expect(command?.hasSuffix("'\(codex.path)'") == true)
    }

    @Test("Codex Here shell-word serialization preserves apostrophes as data")
    func codexHereApostrophePath() throws {
        let directory = URL(
            fileURLWithPath: "/tmp/user's project; touch danger",
            isDirectory: true
        )
        let codex = URL(fileURLWithPath: "/opt/homebrew/bin/codex")

        let request = try ApplicationOpenRequestBuilder.makeCodexHereRequest(
            codexExecutableURL: codex,
            intent: .currentDirectory(directory)
        )

        guard case let .openURLs(openRequest) = request,
              let url = openRequest.urls.first,
              let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
              ) else {
            Issue.record("Expected a Tabby URL request")
            return
        }
        let command = components.queryItems?.first {
            $0.name == "command"
        }?.value
        #expect(command?.contains("'/tmp/user'\"'\"'s project; touch danger'") == true)
    }

    @Test("Codex Here launches Ghostty with a working directory and executable argv")
    func codexHereGhosttyRequest() throws {
        let directory = URL(
            fileURLWithPath: "/tmp/a folder; touch danger",
            isDirectory: true
        )
        let codex = URL(fileURLWithPath: "/opt/homebrew/bin/codex")

        let request = try ApplicationOpenRequestBuilder.makeCodexHereRequest(
            terminal: .ghostty,
            codexExecutableURL: codex,
            intent: .currentDirectory(directory)
        )

        #expect(request == .structuredLaunch(
            StructuredLaunchRequest(
                applicationBundleIdentifier: "com.mitchellh.ghostty",
                arguments: [
                    .pathOption(name: "--working-directory", url: directory),
                    .flag("-e"),
                    .path(codex)
                ]
            )
        ))
    }

    @Test("System Terminal Codex Here uses its automation service")
    func codexHereTerminalRequestIsSeparated() {
        #expect(throws: ApplicationOpenRequestError.unsupportedCodexTerminal) {
            try ApplicationOpenRequestBuilder.makeCodexHereRequest(
                terminal: .terminal,
                codexExecutableURL: URL(fileURLWithPath: "/usr/local/bin/codex"),
                intent: .currentDirectory(
                    URL(fileURLWithPath: "/tmp/project", isDirectory: true)
                )
            )
        }
    }

    @Test("Terminal converts a selected file to its parent directory")
    func terminalSelectedFileUsesParentDirectory() throws {
        let terminal = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "com.apple.Terminal"
            )
        )
        let file = URL(fileURLWithPath: "/tmp/Magic Right/project/main.swift")
        let parent = file.deletingLastPathComponent()

        let request = try ApplicationOpenRequestBuilder.makeRequest(
            for: terminal,
            intent: .selection([file])
        )

        #expect(request == .openURLs(
            OpenURLsRequest(
                applicationBundleIdentifier: "com.apple.Terminal",
                urls: [parent]
            )
        ))
    }

    @Test("Ghostty opens a selected file's parent with one safe argument")
    func ghosttySelectedFileUsesParentDirectory() throws {
        let ghostty = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "com.mitchellh.ghostty"
            )
        )
        let file = URL(
            fileURLWithPath: "/tmp/Magic Right/a folder; touch danger/main.swift"
        )
        let parent = file.deletingLastPathComponent()

        let request = try ApplicationOpenRequestBuilder.makeRequest(
            for: ghostty,
            intent: .selection([file])
        )

        let expected = StructuredLaunchRequest(
            applicationBundleIdentifier: "com.mitchellh.ghostty",
            arguments: [
                .pathOption(name: "--working-directory", url: parent)
            ]
        )
        #expect(request == .structuredLaunch(expected))
        #expect(expected.argumentValues == [
            "--working-directory=\(parent.path)"
        ])
    }

    @Test("Ghostty preserves a selected directory")
    func ghosttySelectedDirectoryIsPreserved() throws {
        let ghostty = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "com.mitchellh.ghostty"
            )
        )
        let directory = URL(
            fileURLWithPath: "/tmp/Magic Right/project",
            isDirectory: true
        )

        let request = try ApplicationOpenRequestBuilder.makeRequest(
            for: ghostty,
            intent: .selection([directory])
        )

        #expect(request == .structuredLaunch(
            StructuredLaunchRequest(
                applicationBundleIdentifier: "com.mitchellh.ghostty",
                arguments: [
                    .pathOption(name: "--working-directory", url: directory)
                ]
            )
        ))
    }

    @Test("Empty selection is rejected")
    func rejectsEmptySelection() throws {
        let terminal = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "com.apple.Terminal"
            )
        )

        #expect(throws: ApplicationOpenRequestError.emptySelection) {
            try ApplicationOpenRequestBuilder.makeRequest(
                for: terminal,
                intent: .selection([])
            )
        }
    }

    @Test("Open requests are Codable")
    func requestsCodableRoundTrip() throws {
        let request = ApplicationOpenRequest.structuredLaunch(
            StructuredLaunchRequest(
                applicationBundleIdentifier: "com.mitchellh.ghostty",
                arguments: [
                    .pathOption(
                        name: "--working-directory",
                        url: URL(fileURLWithPath: "/tmp/a project")
                    )
                ]
            )
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ApplicationOpenRequest.self, from: data)

        #expect(decoded == request)
    }
}
