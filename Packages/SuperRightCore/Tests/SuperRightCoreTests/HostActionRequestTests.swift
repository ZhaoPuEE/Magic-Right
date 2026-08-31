import Foundation
import Testing
@testable import SuperRightCore

@Suite("Structured host actions")
struct HostActionRequestTests {
    @Test("Every action survives Codable without turning paths into shell source")
    func codableRoundTrip() throws {
        let unusual = URL(
            fileURLWithPath: "/tmp/Project name; $(touch nope)",
            isDirectory: true
        )
        let actions: [HostAction] = [
            .archive(sourceURLs: [unusual], destinationDirectory: unusual),
            .codexHere(
                directoryURL: unusual,
                codexExecutableURL: unusual.appendingPathComponent("codex"),
                terminal: .ghostty
            ),
            .copyGitRelativePaths(itemURLs: [unusual]),
            .copyOriginURL(itemURL: unusual),
            .extract(archiveURLs: [unusual.appendingPathComponent("a.zip")]),
            .navigateFinder(directoryURL: unusual),
            .openGitRoot(itemURL: unusual),
            .openGitRootInEditor(itemURL: unusual),
            .openOrigin(itemURL: unusual)
        ]

        for action in actions {
            let request = HostActionRequest(action: action)
            let decoded = try JSONDecoder().decode(
                HostActionRequest.self,
                from: JSONEncoder().encode(request)
            )
            #expect(decoded == request)
            #expect(decoded.storageKey.hasPrefix(HostActionRequest.storageKeyPrefix))
        }
    }

    @Test("Stale and future requests fail closed")
    func freshness() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(HostActionRequest(createdAt: now, action: .openGitRoot(
            itemURL: URL(fileURLWithPath: "/tmp")
        )).isFresh(at: now))
        #expect(!HostActionRequest(
            createdAt: now.addingTimeInterval(-61),
            action: .openGitRoot(itemURL: URL(fileURLWithPath: "/tmp"))
        ).isFresh(at: now))
        #expect(!HostActionRequest(
            createdAt: now.addingTimeInterval(6),
            action: .openGitRoot(itemURL: URL(fileURLWithPath: "/tmp"))
        ).isFresh(at: now))
    }
}
