// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import CoreGraphics
import Foundation
import Testing

@testable import PhotoRPG

/// CODE_AUDIT_TestGaps §8.5: the box that creates the image viewer's viewport model once. An
/// `init` that built it ran on every parent render and measured the image each time.
@MainActor
@Suite("Viewport model store")
struct ViewportModelStoreTests {
    private func model(side: CGFloat = 100) -> ViewportModel {
        ViewportModel(configuration: ViewportConfiguration(id: UUID(), contentSize: CGSize(width: side, height: side), containerSize: CGSize(width: 200, height: 200)))
    }

    @Test("The model is made on the first request and returned for every later one")
    func madeOnce() {
        let store = ViewportModelStore()
        var made = 0
        #expect(!store.hasModel)

        let first = store.model { made += 1; return model() }
        let second = store.model { made += 1; return model(side: 500) }

        #expect(made == 1)
        #expect(first === second)
        #expect(store.hasModel)
    }

    @Test("Each store owns its model")
    func storesAreIndependent() {
        let first = ViewportModelStore()
        let second = ViewportModelStore()

        let one = first.model { model() }
        let two = second.model { model() }

        #expect(one !== two)
    }
}
#endif
