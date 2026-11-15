// @copyright André Trettin

import CoreRPG
import Testing

@testable import RolePlayGameKit

/// CODE_AUDIT_26 §5.41: Reset Data takes the exclusive data-mutation token like import and repair.
@MainActor
@Suite("AppModel reset data")
struct AppModelResetDataTests {
    @Test("A reset is refused while another operation holds the data-mutation token")
    func resetIsBusyWhileAnotherOperationMutatesData() async throws {
        let appModel = AppModel.preview
        let token = try #require(appModel.beginExclusiveDataMutation())

        let outcome = await appModel.resetData()

        #expect(outcome == .busy)
        appModel.endExclusiveDataMutation(token)
    }

    @Test("A completed reset releases the token and the save deferral")
    func resetReleasesItsToken() async throws {
        let appModel = AppModel.preview

        let outcome = await appModel.resetData()

        #expect(outcome == .completed)
        let token = try #require(appModel.beginExclusiveDataMutation())
        appModel.endExclusiveDataMutation(token)
        #expect(appModel.saveIsDeferred == false)
    }
}
