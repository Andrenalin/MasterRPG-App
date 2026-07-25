// @copyright André Trettin

import CoreRPG
import SwiftUI
import StoreKit

public struct InAppView: View {
    public init(inAppController: InAppController) {
        self.inAppController = inAppController
    }
    
    public let inAppController: InAppController
    
    public var body: some View {
        ScrollView {
            VStack {
                SupporterStatusView(tier: inAppController.model.supporterTier)

                StoreView(ids: SupporterProduct.productIDs) { product in
                    SupporterCrownView(
                        tier: SupporterProduct(productID: product.id)?.tier ?? .none
                    )
                }
                .productViewStyle(.large)
                .storeButton(.hidden, for: .restorePurchases)
                .onInAppPurchaseCompletion { _, result in
                    await inAppController.handlePurchaseResult(result)
                }

                Text(
                    "Bronze, Silver, and Gold are one-time support purchases. Every feature remains available to everyone; the only benefit is a colored crown beside your player name.",
                    bundle: .module
                )
                .foregroundStyle(.secondary)

                Button("Restore Purchases", systemImage: "arrow.clockwise") {
                    Task {
                        await inAppController.restorePurchases()
                    }
                }

                if inAppController.model.isLoading {
                    ProgressView {
                        Text("Loading purchases", bundle: .module)
                    }
                }

                if let message = inAppController.model.message {
                    Text(verbatim: message)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(Text("Support MasterRPG", bundle: .module))
        .task {
            await inAppController.prepare()
        }
        .themedSurface()
    }
}

private struct SupporterStatusView: View {
    let tier: SupporterTier

    var body: some View {
        VStack {
            SupporterCrownView(tier: tier)
                .font(.largeTitle)

            if tier == .none {
                Text("Support the Adventure", bundle: .module)
                    .font(.title)
                    .bold()
                Text(
                    "Every MasterRPG feature is available to everyone. Choose a supporter level only if the app supports your adventures.",
                    bundle: .module
                )
            } else {
                Text("Welcome back, \(Text(tier.localizedName)).", bundle: .module)
                    .font(.title)
                    .bold()
                Text(
                    "Thank you for helping keep the adventure going.",
                    bundle: .module
                )
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    InAppView(inAppController: InAppController(model: InAppModel()))
}
