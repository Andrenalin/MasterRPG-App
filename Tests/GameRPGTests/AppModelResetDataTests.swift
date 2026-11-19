// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import RolePlayGameKit

/// CODE_AUDIT_26 §5.41: Reset Data takes the exclusive data-mutation token like import and repair.
///
/// The token is process-wide (`DataMutationCoordinator.shared`) and other suites take it while the
/// tests run in parallel, so these tests wait for it to be free instead of assuming it is.
@MainActor
@Suite("AppModel reset data")
struct AppModelResetDataTests {
    private func acquireToken(_ appModel: AppModel) async throws -> UUID {
        var token: UUID?
        let acquired = await awaitCondition(pollInterval: .milliseconds(20)) {
            token = appModel.beginExclusiveDataMutation()
            return token != nil
        }
        guard acquired, let token else { throw TokenUnavailable() }
        return token
    }

    private struct TokenUnavailable: Error {}

    @Test("A reset is refused while another operation holds the data-mutation token")
    func resetIsBusyWhileAnotherOperationMutatesData() async throws {
        let appModel = AppModel.preview
        let token = try await acquireToken(appModel)

        let outcome = await appModel.resetData()

        #expect(outcome == .busy)
        appModel.endExclusiveDataMutation(token)
    }

    @Test("A completed reset releases the token and the save deferral")
    func resetReleasesItsToken() async throws {
        let appModel = AppModel.preview
        var outcome = await appModel.resetData()
        _ = await awaitCondition(pollInterval: .milliseconds(20)) {
            guard outcome == .busy else { return true }
            outcome = await appModel.resetData()
            return outcome != .busy
        }

        #expect(outcome == .completed)
        let token = try await acquireToken(appModel)
        appModel.endExclusiveDataMutation(token)
        #expect(appModel.saveIsDeferred == false)
    }
}
