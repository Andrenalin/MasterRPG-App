// @copyright André Trettin

import CoreRPG
import SwiftUI

struct EditTileButton: View {
    let model: MapModel

    @Environment(\.navigator) private var navigator
    @Environment(ScenesManager.self) private var scenesManager

    var body: some View {
        Button {
#if os(visionOS) || os(macOS)
            scenesManager.openWindow(.mapEditor)
#else
            navigator.navigate(to: MapEditorRoute.mapEditor(model.id))
#endif
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
