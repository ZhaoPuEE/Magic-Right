import Testing
@testable import SuperRightCore

@Suite("Finder menu action tokens")
struct MenuActionRegistryTests {
    @Test("Scalar tokens recover registered action context")
    func resolvesActions() throws {
        let registry = MenuActionRegistry<String>()
        registry.beginBatch()

        let first = registry.register("open-tabby")
        let second = registry.register("copy-to-frequent")

        #expect(first > 0)
        #expect(second != first)
        #expect(registry.action(for: first) == "open-tabby")
        #expect(registry.action(for: second) == "copy-to-frequent")
        #expect(registry.action(for: 0) == nil)
    }

    @Test("Old menu batches are bounded without invalidating recent menus")
    func boundsRetainedBatches() {
        let registry = MenuActionRegistry<Int>(retainedBatchCount: 2)

        registry.beginBatch()
        let first = registry.register(1)
        registry.beginBatch()
        let second = registry.register(2)
        registry.beginBatch()
        let third = registry.register(3)

        #expect(registry.action(for: first) == nil)
        #expect(registry.action(for: second) == 2)
        #expect(registry.action(for: third) == 3)
    }
}
