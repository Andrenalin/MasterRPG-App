// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The buttons over a full-screen photo the game master showed while the map was on screen:
/// Close, then back to the popover on the map, in the popover's order. On the game master's
/// device the change goes to every player; on a player's or observer's device it stays local.
struct MapPhotoFullScreenControls: View {
    let onShowOnMap: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack {
            Button(action: onClose) {
                Label {
                    Text("Close", bundle: .module)
                } icon: {
                    Image(systemName: "xmark")
                }
            }
            .selectedRoundButton(
                title: String(localized: "Close", bundle: .module),
                module: .photo,
                isSelected: false
            )

            Button(action: onShowOnMap) {
                Label {
                    Text("Show on Map", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                }
            }
            .selectedRoundButton(
                title: String(localized: "Show on Map", bundle: .module),
                module: .photo,
                isSelected: false
            )
        }
    }
}

#Preview {
    MapPhotoFullScreenControls(onShowOnMap: {}, onClose: {})
        .padding()
        .background(Color.black.gradient)
}
