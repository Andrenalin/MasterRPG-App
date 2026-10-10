// @copyright André Trettin

import CoreRPG
import Testing
@testable import GameRPG

@Suite("Delivery receipt type matching")
struct DeliveryReceiptTypeTests {
    @Test("a store receipt completes a targeted audio reveal rewritten by the journal")
    func audioStoreReceiptMatchesLoggedReveal() {
        #expect(MasterController.deliveryTypeMatches(logged: .reveal, receipt: .store, module: .audio))
    }

    @Test("identical types always match")
    func identicalTypesMatch() {
        #expect(MasterController.deliveryTypeMatches(logged: .reveal, receipt: .reveal, module: .photo))
        #expect(MasterController.deliveryTypeMatches(logged: .store, receipt: .store, module: .audio))
    }

    @Test("other modules do not accept a store receipt for a reveal")
    func otherModulesStayStrict() {
        #expect(!MasterController.deliveryTypeMatches(logged: .reveal, receipt: .store, module: .photo))
        #expect(!MasterController.deliveryTypeMatches(logged: .reveal, receipt: .store, module: .map))
    }

    @Test("audio does not accept the opposite rewrite")
    func audioStoreIsNotAcceptedAsReveal() {
        #expect(!MasterController.deliveryTypeMatches(logged: .store, receipt: .reveal, module: .audio))
    }
}
