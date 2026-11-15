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
        for _ in 0..<200 {
            if let token = appModel.beginExclusiveDataMutation() { return token }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw TokenUnavailable()
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
        for _ in 0..<200 where outcome == .busy {
            try await Task.sleep(for: .milliseconds(50))
            outcome = await appModel.resetData()
        }

        #expect(outcome == .completed)
        let token = try await acquireToken(appModel)
        appModel.endExclusiveDataMutation(token)
        #expect(appModel.saveIsDeferred == false)
    }
}
