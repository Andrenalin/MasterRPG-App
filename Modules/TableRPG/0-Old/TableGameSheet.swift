// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableGameSheet: View {
    @Environment(TableRootModel.self) private var root

    @State private var model: TableModel = .empty

    var body: some View {
        ViewerRootView(model: model, dismissAction: nil)
            .padding(32)
            .onChange(of: root.gameController.gameModel.currentItemId) {
                guard let id = root.gameController.gameModel.currentItemId else { return }
                withAnimation {
                    model = root.gameController.gameItem(for: id)
                }
        }
    }
}

#Preview {
    TableGameSheet()
        .environment(TableRootModel.previewWithData)
}
