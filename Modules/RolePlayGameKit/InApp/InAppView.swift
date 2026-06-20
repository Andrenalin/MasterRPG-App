// @copyright André Trettin

import SwiftUI
import StoreKit

public struct InAppView: View {
    public init(inAppController: InAppController) {
        self.inAppController = inAppController
    }
    
    public let inAppController: InAppController
    
    public var body: some View {
        VStack {
            Text("Purchased items: \(inAppController.model.activeTransactions.count)")
            
            if inAppController.model.products.isEmpty {
                ProgressView()
            } else {
                if inAppController.model.activeTransactions.isEmpty {
                    ForEach(inAppController.model.products, id: \.id) { product in
                        Button {
                            #if !os(visionOS)
                            Task {
                                try? await inAppController.purchase(product)
                            }
                            #endif
                        } label: {
                            VStack {
                                Text(verbatim: product.displayName)
                                    .font(.headline)
                                Text(verbatim: product.displayPrice)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .task {
            await inAppController.fetchProducts()
        }
        
    }
}

#Preview {
    InAppView(inAppController: InAppController(model: InAppModel()))
}
