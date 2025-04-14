// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct TableGameSheet: View {
    @Environment(TableRoot.self) private var root

    @State private var model: TableModel = .empty

    var body: some View {
        TableSheet(model: model, showTopImage: true, dismissAction: nil)
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
        .environment(TableRoot.previewWithData)
}
