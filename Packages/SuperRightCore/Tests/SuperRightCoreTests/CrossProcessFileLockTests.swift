import Darwin
import Foundation
import Testing
@testable import SuperRightCore

@Suite("Cross-process file lock")
struct CrossProcessFileLockTests {
    private enum ExpectedFailure: Error {
        case operation
    }

    @Test("A thrown operation releases the lock")
    func releasesAfterThrow() throws {
        try withTemporaryLockURL { lockURL in
            #expect(throws: ExpectedFailure.operation) {
                try CrossProcessFileLock.withLock(at: lockURL) {
                    throw ExpectedFailure.operation
                }
            }

            var didRunAgain = false
            try CrossProcessFileLock.withLock(at: lockURL) {
                didRunAgain = true
            }
            #expect(didRunAgain)
        }
    }

    @Test("Concurrent callers enter the critical section one at a time")
    func serializesConcurrentCallers() throws {
        try withTemporaryLockURL { lockURL in
            let probe = CriticalSectionProbe()
            let group = DispatchGroup()
            var workers: [Thread] = []

            for _ in 0..<4 {
                group.enter()
                let worker = Thread {
                    defer { group.leave() }
                    do {
                        try CrossProcessFileLock.withLock(at: lockURL) {
                            probe.enter()
                            usleep(25_000)
                            probe.leave()
                        }
                        probe.recordCompletion()
                    } catch {
                        probe.recordFailure()
                    }
                }
                workers.append(worker)
                worker.start()
            }

            #expect(group.wait(timeout: .now() + 10) == .success)
            #expect(probe.maximumConcurrentCount == 1)
            #expect(probe.completionCount == 4)
            #expect(probe.failureCount == 0)

            // Retain explicit workers until all four finish. A global dispatch
            // queue can be starved when Swift Testing runs many suites in
            // parallel on a small CI runner, which tests scheduling instead of
            // the advisory lock itself.
            let allWorkersFinished = workers.allSatisfy { $0.isFinished }
            #expect(allWorkersFinished)
        }
    }

    @Test("An unavailable parent reports the open error")
    func reportsOpenError() throws {
        try withTemporaryLockURL { lockURL in
            let missingParentLock = lockURL
                .deletingLastPathComponent()
                .appendingPathComponent("missing", isDirectory: true)
                .appendingPathComponent("history.lock", isDirectory: false)

            #expect(throws: CrossProcessFileLockError.cannotOpen(ENOENT)) {
                try CrossProcessFileLock.withLock(at: missingParentLock) {}
            }
        }
    }
}

private final class CriticalSectionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private var maximum = 0
    private var completions = 0
    private var failures = 0

    var maximumConcurrentCount: Int {
        lock.withLock { maximum }
    }

    var completionCount: Int {
        lock.withLock { completions }
    }

    var failureCount: Int {
        lock.withLock { failures }
    }

    func enter() {
        lock.withLock {
            current += 1
            maximum = max(maximum, current)
        }
    }

    func leave() {
        lock.withLock {
            current -= 1
        }
    }

    func recordCompletion() {
        lock.withLock {
            completions += 1
        }
    }

    func recordFailure() {
        lock.withLock {
            failures += 1
        }
    }
}

private func withTemporaryLockURL(
    _ operation: (URL) throws -> Void
) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "MagicRight-LockTests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    try operation(directory.appendingPathComponent("history.lock"))
}
