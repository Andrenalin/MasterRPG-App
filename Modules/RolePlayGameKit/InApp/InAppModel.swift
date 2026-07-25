// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import StoreKit

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
    var products: [Product] = []
    var activeTransactions: Set<StoreKit.Transaction> = []
    var isLoading = false
    var message: String?
    @ObservationIgnored var transactionUpdatesTask: Task<Void, Never>?

    var supporterTier: SupporterTier {
        activeTransactions
            .compactMap { SupporterProduct(productID: $0.productID)?.tier }
            .max() ?? .none
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }
}

@MainActor
public struct InAppController {
    let model: InAppModel

    init(model: InAppModel) {
        self.model = model
    }

    func prepare() async {
        model.isLoading = true
        async let products: Void = fetchProducts()
        async let entitlements: Void = fetchActiveTransactions()
        _ = await (products, entitlements)
        model.isLoading = false
    }

    func observeTransactionUpdates() async {
        for await update in StoreKit.Transaction.updates {
            guard !Task.isCancelled else { return }
            switch update {
            case .verified(let transaction):
                await fetchActiveTransactions()
                await transaction.finish()
            case .unverified:
                model.message = String(
                    localized: "A purchase could not be verified.",
                    bundle: .module
                )
            }
        }
    }

    func startObservingTransactionUpdates() {
        guard model.transactionUpdatesTask == nil else { return }
        model.transactionUpdatesTask = Task { @MainActor [weak model] in
            guard let model else { return }
            await InAppController(model: model).observeTransactionUpdates()
        }
    }

    static func fetchActiveTransactions(in model: InAppModel) async {
        var activeTransactions: Set<StoreKit.Transaction> = []

        for await entitlement in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  SupporterProduct(productID: transaction.productID) != nil
            else { continue }

            if transaction.revocationDate == nil {
                activeTransactions.insert(transaction)
            }
        }

        model.activeTransactions = activeTransactions
    }

    public func fetchActiveTransactions() async {
        await InAppController.fetchActiveTransactions(in: model)
    }

    func fetchProducts() async {
        do {
            let products = try await Product.products(for: SupporterProduct.productIDs)
            model.products = products.sorted {
                let left = SupporterProduct(productID: $0.id)?.tier ?? .none
                let right = SupporterProduct(productID: $1.id)?.tier ?? .none
                return left < right
            }
            model.message = nil
        } catch {
            model.products = []
            model.message = error.localizedDescription
        }
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
        model.isLoading = true
        defer { model.isLoading = false }
        do {
            try await AppStore.sync()
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
