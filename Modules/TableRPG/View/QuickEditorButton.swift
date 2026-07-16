// @copyright André Trettin

import CoreRPG
import SwiftUI

struct QuickEditorButton: View {
    let root: TableRootModel
    let model: TableModel

    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            navigator.navigate(to: TableEditorRoute.quickEditor(model.id))
        } label: {
            Label {
                Text("Quick Editor", bundle: .module)
            } icon: {
                Image(systemName: "table.badge.more")
            }
        }
    }
}

#Preview(traits: .mockData) {
    QuickEditorButton(root: .preview, model: .preview)
}
