// @copyright André Trettin

import StoreKit
import SwiftUI

struct PackageProducts: View {
    var body: some View {
        VStack {
            Text("Welcome to RPG Pacakges")
                .font(.title)

            StoreView(ids: ["de.andretrettin.free.dungeonslayers.german", "de.andretrettin.free.dungeonslayers.english"])
        }
    }
}

#Preview {
    PackageProducts()
}
