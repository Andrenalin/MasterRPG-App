// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import StoreKit

/// Raw values must be literals; they are `BundleIds.product` + `.supporter.<tier>` as registered
/// in App Store Connect.
enum SupporterProduct: String, CaseIterable, Sendable {
    case bronze = "de.andretrettin.gamemaster.supporter.bronze"
    case silver = "de.andretrettin.gamemaster.supporter.silver"
    case gold = "de.andretrettin.gamemaster.supporter.gold"

    static var productIDs: [Product.ID] {
        allCases.map(\.rawValue)
    }

    var tier: SupporterTier {
        switch self {
        case .bronze: .bronze
        case .silver: .silver
        case .gold: .gold
        }
    }

    init?(productID: Product.ID) {
        self.init(rawValue: productID)
    }
}

@MainActor @Observable
final class InAppModel {
    var activeProductIDs: Set<Product.ID> = []
    var hasPrepared = false
    var isPreparing = false
    var isRestoring = false
    var message: String?
    @ObservationIgnored var transactionUpdatesTask: Task<Void, Never>?

    var isLoading: Bool {
        isPreparing || isRestoring
    }

    var supporterTier: SupporterTier {
        activeProductIDs
            .compactMap { SupporterProduct(productID: $0)?.tier }
            .max() ?? .none
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }
}

@MainActor
public struct InAppController {
    typealias EntitlementProductIDs = @MainActor @Sendable () async -> Set<Product.ID>
    typealias StoreSynchronizer = @MainActor @Sendable () async throws -> Void

    let model: InAppModel
    private let entitlementProductIDs: EntitlementProductIDs
    private let synchronizeStore: StoreSynchronizer

    init(
        model: InAppModel,
        entitlementProductIDs: @escaping EntitlementProductIDs = Self.currentEntitlementProductIDs,
        synchronizeStore: @escaping StoreSynchronizer = Self.synchronizeAppStore
    ) {
        self.model = model
        self.entitlementProductIDs = entitlementProductIDs
        self.synchronizeStore = synchronizeStore
    }

    func prepare() async {
        guard !model.hasPrepared, !model.isPreparing else { return }
        model.isPreparing = true
        defer { model.isPreparing = false }

        await fetchActiveTransactions()
        guard !Task.isCancelled else { return }
        model.hasPrepared = true
    }

    /// Idempotent. Started from `App.init` so transactions are observed from launch on, even
    /// before (or without) a window — StoreKit warns when `Transaction.updates` isn't observed
    /// early. The window's `.task` call remains as a no-op fallback. See CODE_AUDIT_18 §3.20.
    public func startObservingTransactionUpdates() {
        guard model.transactionUpdatesTask == nil else { return }
        model.transactionUpdatesTask = Task { @MainActor [weak model] in
            for await update in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                guard let model else { return }

                switch update {
                case .verified(let transaction):
                    await InAppController.fetchActiveTransactions(
                        in: model,
                        entitlementProductIDs: InAppController.currentEntitlementProductIDs
                    )
                    await transaction.finish()
                case .unverified:
                    model.message = String(
                        localized: "A purchase could not be verified.",
                        bundle: .module
                    )
                }
            }
        }
    }

    private static func currentEntitlementProductIDs() async -> Set<Product.ID> {
        var productIDs: Set<Product.ID> = []
        for await entitlement in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  SupporterProduct(productID: transaction.productID) != nil
            else { continue }

            if transaction.revocationDate == nil {
                productIDs.insert(transaction.productID)
            }
        }
        return productIDs
    }

    private static func synchronizeAppStore() async throws {
        try await AppStore.sync()
    }

    private static func fetchActiveTransactions(
        in model: InAppModel,
        entitlementProductIDs: EntitlementProductIDs
    ) async {
        let productIDs = await entitlementProductIDs()
        guard !Task.isCancelled else { return }
        model.activeProductIDs = productIDs
    }

    public func fetchActiveTransactions() async {
        await InAppController.fetchActiveTransactions(
            in: model,
            entitlementProductIDs: entitlementProductIDs
        )
    }

    func handlePurchaseResult(_ result: Result<Product.PurchaseResult, any Error>) async {
        switch result {
        case .success(let purchaseResult):
            switch purchaseResult {
            case .success(.verified(let transaction)):
                await fetchActiveTransactions()
                await transaction.finish()
                model.message = nil
            case .success(.unverified):
                model.message = String(
                    localized: "A purchase could not be verified.",
                    bundle: .module
                )
            case .userCancelled:
                break
            case .pending:
                model.message = String(
                    localized: "This purchase is waiting for approval.",
                    bundle: .module
                )
            @unknown default:
                break
            }
        case .failure(let error):
            model.message = error.localizedDescription
        }
    }

    func restorePurchases() async {
        guard !model.isRestoring else { return }
        model.isRestoring = true
        defer { model.isRestoring = false }

        do {
            try await synchronizeStore()
            await fetchActiveTransactions()
            model.message = String(
                localized: "Purchases restored.",
                bundle: .module
            )
        } catch {
            model.message = error.localizedDescription
        }
    }
}
