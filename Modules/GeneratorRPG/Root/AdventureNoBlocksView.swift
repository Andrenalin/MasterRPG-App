// @copyright André Trettin

import SwiftUI

struct AdventureNoBlocksView: View {
    var body: some View {
        ContentUnavailableView(
            LocalizedStringResource("No Blocks", bundle: .module),
            systemImage: "square.stack.3d.up",
            description: Text("Sheet blocks and generated blocks will appear here.", bundle: .module)
        )
    }
}

#Preview {
    AdventureNoBlocksView()
}
