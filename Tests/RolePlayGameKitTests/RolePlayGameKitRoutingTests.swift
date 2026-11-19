// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import RolePlayGameKit

/// CODE_AUDIT_26 §10.6: app-level routing, database error recovery and the Validate/Repair lock.
@MainActor
@Suite("RolePlayGameKit routing and setup")
struct RolePlayGameKitRoutingTests {

    // MARK: - External route dedupe

    @Test("The same external route twice within a second is admitted once")
    func sameExternalRouteIsDeduplicated() {
        let appModel = AppModel.preview
        let itemId = UUID()

        #expect(appModel.admitsExternalRoute(.dice, itemId: itemId))
        #expect(appModel.admitsExternalRoute(.dice, itemId: itemId) == false)
    }

    @Test("A different external route right after another one is admitted")
    func differentExternalRouteIsAdmitted() {
        let appModel = AppModel.preview

        #expect(appModel.admitsExternalRoute(.dice, itemId: UUID()))
        #expect(appModel.admitsExternalRoute(.dice, itemId: UUID()))
        #expect(appModel.admitsExternalRoute(.map, itemId: UUID()))
    }

    @Test("The same external route is admitted again once the second has passed")
    func expiredExternalRouteIsAdmittedAgain() {
        let appModel = AppModel.preview
        let itemId = UUID()

        #expect(appModel.admitsExternalRoute(.dice, itemId: itemId))
        appModel.lastExternalRouteDate = .distantPast
        #expect(appModel.admitsExternalRoute(.dice, itemId: itemId))
    }

    // MARK: - Database error and recovery

    @Test("A migration failure is recoverable and shows a message")
    func migrationErrorIsRecoverable() {
        let model = DataBaseModel.previewWithOutSetup()

        model.apply(initializationError: .migration(message: "broken"))

        #expect(model.hasError)
        #expect(model.canRecover)
        #expect(model.errorMessage?.contains("broken") == true)
        #expect(model.hasContextSet == false)
    }

    @Test("Errors that destroy nothing offer no destructive recovery")
    func unrecoverableErrorsOfferNoRecovery() {
        let model = DataBaseModel.previewWithOutSetup()

        for error: CoreDataInitError in [.loadModel, .removeFile(message: "a"), .creation(message: "b")] {
            model.apply(initializationError: error)
            #expect(model.hasError)
            #expect(model.canRecover == false)
            #expect(model.errorMessage != nil)
        }
    }

    @Test("A successful retry clears the earlier error")
    func successClearsEarlierError() {
        let model = DataBaseModel.previewWithOutSetup()
        model.apply(initializationError: .migration(message: "broken"))

        model.apply(initializationError: .none)

        #expect(model.hasError == false)
        #expect(model.canRecover == false)
        #expect(model.errorMessage == nil)
        #expect(model.hasContextSet)
    }

    @Test("A later error replaces recoverability of the earlier one")
    func laterErrorReplacesEarlierRecoverability() {
        let model = DataBaseModel.previewWithOutSetup()
        model.apply(initializationError: .migration(message: "first"))
        #expect(model.canRecover)

        model.apply(initializationError: .creation(message: "second"))

        #expect(model.canRecover == false)
        #expect(model.errorMessage?.contains("second") == true)
    }

    // MARK: - Validate / Repair lock

    @Test("Validate and Repair refuses to start while another operation holds the data-mutation token")
    func validateRepairIsBusyWhileTokenIsHeld() async throws {
        let appModel = AppModel.preview
        var held: UUID?
        _ = await awaitCondition(pollInterval: .milliseconds(20)) {
            held = appModel.beginExclusiveDataMutation()
            return held != nil
        }
        let token = try #require(held)
        defer { appModel.endExclusiveDataMutation(token) }

        let controller = ValidateRepairController(appModel: appModel, model: ValidateRepairModel())
        let outcome = await controller.startWithExclusiveDataAccess()

        #expect(outcome == .busy)
    }

    // MARK: - Window router

#if os(iOS)
    @Test("The game route is a single action in every layout")
    func gameRouteIsOneAction() {
        let appModel = AppModel.preview
        let router = WindowRouter(appModel: appModel, role: .game)

        appModel.isCompactGameWindow = true
        #expect(router.actions(for: .game).count == 1)
        appModel.isCompactGameWindow = false
        #expect(router.actions(for: .game).count == 1)
    }

    @Test("A module route without an item has fewer actions than one with a detail")
    func detailRouteAddsActions() {
        let appModel = AppModel.preview
        let router = WindowRouter(appModel: appModel, role: .game)

        for compact in [true, false] {
            appModel.isCompactGameWindow = compact
            let withoutItem = router.actions(for: .dice(nil, nil))
            let withItem = router.actions(for: .dice(UUID(), nil))
            #expect(withItem.count > withoutItem.count)
        }
    }
#endif
}
