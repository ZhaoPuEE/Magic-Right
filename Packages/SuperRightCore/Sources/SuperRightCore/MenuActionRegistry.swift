import Foundation

/// Keeps action context in the extension process while Finder rebuilds the
/// corresponding `NSMenuItem` objects across its XPC boundary.
///
/// Finder reliably preserves scalar menu-item tags, but it does not preserve
/// arbitrary Swift objects stored in `representedObject`. Clients register a
/// payload here, assign the returned token to `NSMenuItem.tag`, and resolve the
/// payload again when the action callback arrives.
public final class MenuActionRegistry<Action>: @unchecked Sendable {
    private let retainedBatchCount: Int
    private let lock = NSLock()
    private var actionsByToken: [Int: Action] = [:]
    private var tokenBatches: [[Int]] = []
    private var nextToken = 1

    public init(retainedBatchCount: Int = 8) {
        self.retainedBatchCount = max(1, retainedBatchCount)
    }

    /// Starts one menu-construction batch and evicts the oldest retained batch.
    /// Several batches are retained because Finder can request a new menu while
    /// an older contextual menu is still waiting to dispatch its callback.
    public func beginBatch() {
        lock.lock()
        defer { lock.unlock() }

        tokenBatches.append([])
        while tokenBatches.count > retainedBatchCount {
            let expiredTokens = tokenBatches.removeFirst()
            for token in expiredTokens {
                actionsByToken.removeValue(forKey: token)
            }
        }
    }

    /// Registers one action and returns a positive scalar token suitable for
    /// `NSMenuItem.tag`.
    public func register(_ action: Action) -> Int {
        lock.lock()
        defer { lock.unlock() }

        if tokenBatches.isEmpty {
            tokenBatches.append([])
        }
        if nextToken == Int.max {
            actionsByToken.removeAll(keepingCapacity: true)
            tokenBatches = [[]]
            nextToken = 1
        }

        let token = nextToken
        nextToken += 1
        actionsByToken[token] = action
        tokenBatches[tokenBatches.count - 1].append(token)
        return token
    }

    public func action(for token: Int) -> Action? {
        lock.lock()
        defer { lock.unlock() }
        return actionsByToken[token]
    }
}
