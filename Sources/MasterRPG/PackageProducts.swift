// @copyright André Trettin

import StoreKit
import SwiftUI

struct PackageProducts: View {
    var body: some View {
        VStack {
            Text(verbatim: "Welcome to RPG Packages")
                .font(.title)
                .accessibilityAddTraits(.isHeader)

            StoreView(ids: ["de.andretrettin.free.dungeonslayers.german", "de.andretrettin.free.dungeonslayers.english"])
        }
    }
}

#Preview {
    PackageProducts()
}
