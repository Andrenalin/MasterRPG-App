// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameSetupRoleContent: View {
    let root: GameRoot
    let selection: GameSetupRole

    var body: some View {
        VStack {
            switch selection {
#if !os(tvOS)
            case .player:
                SelectedPlayerView(root: root)
                PlayerStartView(root: root)
            case .master:
                SelectedAdventureView(root: root)
                MasterStartView(root: root)
#endif
            case .join:
                SearchProxyView(root: root)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Shared · Role content", traits: .mockData) {
    GameSetupRoleContent(
        root: .preview,
        selection: .previewPlayer
    )
    .padding()
}
