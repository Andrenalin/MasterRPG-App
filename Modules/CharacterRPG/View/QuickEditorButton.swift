// @copyright André Trettin

import CoreRPG
import SwiftUI

struct QuickEditorButton: View {
    let root: CharacterRootModel
    let model: ValueModel

    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            navigator.navigate(to: CharacterEditorRoute.quickEditor(model.id))
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
