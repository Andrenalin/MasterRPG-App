// @copyright André Trettin

import Foundation
import StoreKit

@MainActor @Observable
final class InAppModel {
    var products: [Product] = []
    var activeTransactions: Set<StoreKit.Transaction> = []
}

@MainActor
public struct InAppController {
    let model: InAppModel
    
    private var updates: Task<Void, Never>?
    
    init(model: InAppModel) {
        self.model = model
//        updates = Task {
//            for await update in StoreKit.Transaction.updates {
//                if let transaction = try? update.payloadValue {
//                    await InAppController.fetchActiveTransactions(in: model)
//                    await transaction.finish()
//                }
//            }
//        }
    }
    
    static func fetchActiveTransactions(in model: InAppModel) async {
        var activeTransactions: Set<StoreKit.Transaction> = []
        
        for await entitlement in StoreKit.Transaction.currentEntitlements {
            if let transaction = try? entitlement.payloadValue {
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
            model.products = try await Product.products(for: [
                "01SILVER"
            ])
        } catch {
            model.products = []
        }
    }

    #if !os(visionOS)
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verificationResult):
            if let transaction = try? verificationResult.payloadValue {
                model.activeTransactions.insert(transaction)
                await transaction.finish()
            }
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }
    #endif
}
