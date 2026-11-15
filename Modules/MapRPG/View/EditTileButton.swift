// @copyright André Trettin

import CoreRPG
import SwiftUI

struct EditTileButton: View {
    let model: MapModel

    @Environment(\.navigator) private var navigator
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(MapRootModel.self) private var root

    var body: some View {
        Button {
            MapEditorKind.tile.open(model: model, root: root, navigator: navigator, scenesManager: scenesManager)
        } label: {
            Label {
                Text("Edit Tile", bundle: .module)
            } icon: {
                Image(systemName: "skew")
            }
        }
#if os(iOS)
        // Opens the same editor cover, which renders empty without a photo.
        .disabled(model.photoId == nil)
#endif
    }
}

#Preview(traits: .mockData) {
    EditTileButton(model: .preview)
}
