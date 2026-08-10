// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import StoreKit
import Testing

@testable import RolePlayGameKit

@MainActor
private final class SupporterEntitlementFixture {
    var productIDs: Set<Product.ID> = []
    var fetchCount = 0
    var syncCount = 0

    func fetchProductIDs() async -> Set<Product.ID> {
        fetchCount += 1
        await Task.yield()
        return productIDs
    }

    func synchronize() async throws {
        syncCount += 1
        await Task.yield()
    }
}

private struct StoreKitConfiguration: Decodable {
    struct ProductConfiguration: Decodable {
        let productID: String
        let type: String
    }

    let products: [ProductConfiguration]
}

@Suite("Supporter purchases", .serialized)
@MainActor
struct InAppControllerTests {
    @Test("Preparation is single-flight across windows")
    func preparationIsSingleFlight() async {
        let fixture = SupporterEntitlementFixture()
        fixture.productIDs = [SupporterProduct.silver.rawValue]
        let model = InAppModel()
        let controller = InAppController(
            model: model,
            entitlementProductIDs: fixture.fetchProductIDs
        )

        async let first: Void = controller.prepare()
        async let second: Void = controller.prepare()
        async let third: Void = controller.prepare()
        _ = await (first, second, third)

        #expect(fixture.fetchCount == 1)
        #expect(model.hasPrepared)
        #expect(!model.isLoading)
        #expect(model.supporterTier == .silver)
    }

    @Test("Restore is single-flight and refreshes the entitlement")
    func restoreIsSingleFlight() async {
        let fixture = SupporterEntitlementFixture()
        fixture.productIDs = [SupporterProduct.gold.rawValue]
        let model = InAppModel()
        let controller = InAppController(
            model: model,
            entitlementProductIDs: fixture.fetchProductIDs,
            synchronizeStore: fixture.synchronize
        )

        async let first: Void = controller.restorePurchases()
        async let second: Void = controller.restorePurchases()
        _ = await (first, second)

        #expect(fixture.syncCount == 1)
        #expect(fixture.fetchCount == 1)
        #expect(!model.isLoading)
        #expect(model.supporterTier == .gold)
    }

    @Test("Transaction observation does not retain the model")
    func transactionObservationDoesNotRetainModel() async {
        weak var weakModel: InAppModel?

        do {
            let model = InAppModel()
            weakModel = model
            InAppController(model: model).startObservingTransactionUpdates()
        }

        await Task.yield()

        #expect(weakModel == nil)
    }

    @Test("Upgrades and revocations resolve the highest active tier")
    func entitlementLifecycle() async {
        let fixture = SupporterEntitlementFixture()
        let model = InAppModel()
        let controller = InAppController(
            model: model,
            entitlementProductIDs: fixture.fetchProductIDs
        )

        fixture.productIDs = [SupporterProduct.bronze.rawValue]
        await controller.fetchActiveTransactions()
        #expect(model.supporterTier == .bronze)

        fixture.productIDs = [
            SupporterProduct.bronze.rawValue,
            SupporterProduct.gold.rawValue,
        ]
        await controller.fetchActiveTransactions()
        #expect(model.supporterTier == .gold)

        fixture.productIDs = [SupporterProduct.bronze.rawValue]
        await controller.fetchActiveTransactions()
        #expect(model.supporterTier == .bronze)
    }

//    @Test("StoreKit configuration contains three non-consumable supporter products")
//    func storeKitConfigurationIsValid() throws {
//        let configurationURL = URL(filePath: #filePath)
//            .deletingLastPathComponent()
//            .deletingLastPathComponent()
//            .deletingLastPathComponent()
//            .appending(path: "Modules")
//            .appending(path: "RolePlayGameKit")
//            .appending(path: "InApp")
//            .appending(path: "MasterRPG.storekit")
//
//        _ = try SKTestSession(contentsOf: configurationURL)
//        let data = try Data(contentsOf: configurationURL)
//        let configuration = try JSONDecoder().decode(
//            StoreKitConfiguration.self,
//            from: data
//        )
//
//        #expect(Set(configuration.products.map(\.productID)) == Set(SupporterProduct.productIDs))
//        #expect(configuration.products.allSatisfy { $0.type == "NonConsumable" })
//    }
}
#endif
