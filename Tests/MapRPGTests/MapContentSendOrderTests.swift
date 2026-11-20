// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import MapRPG

/// CODE_AUDIT §5.6: every game-master content send, including the editor's "Refresh Shared Map",
/// goes through one chain so a slow earlier send cannot arrive after a later one.
@MainActor
struct MapContentSendOrderTests {
    @Test func laterSendWaitsForSlowerEarlierSend() async throws {
        let sut = RootModel()
        var delivered: [String] = []

        sut.enqueueMapContentSend {
            try? await Task.sleep(for: .milliseconds(150))
            delivered.append("first")
        }
        sut.enqueueMapContentSend {
            delivered.append("second")
        }

        #expect(await awaitCondition { delivered.count == 2 })
        #expect(delivered == ["first", "second"])
    }
}
#endif
