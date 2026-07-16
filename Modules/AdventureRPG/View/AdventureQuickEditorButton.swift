// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AdventureQuickEditorButton: View {
    let model: AdventureModel
    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            navigator.navigate(to: AdventureEditorRoute.quickEditor(model.id))
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
    AdventureQuickEditorButton(model: .preview)
}
