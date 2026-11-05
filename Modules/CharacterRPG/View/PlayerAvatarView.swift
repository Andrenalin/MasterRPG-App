// @copyright André Trettin

import CoreRPG
import SwiftUI

/// A player's picture in a player list: the Character's photo, or a symbol of the same size
/// when the player has no Character or the Character has no photo, so the rows line up.
struct PlayerAvatarView: View {
    let characterId: UUID?
    let placeholderSystemImage: String

    @Environment(CharacterRootModel.self) private var root

    var body: some View {
        if let characterId, root.itemController.itemSync(for: characterId)?.photoId != nil {
            ThumbnailPhotoRow(itemId: characterId)
        } else {
            let size = root.listDisplayModel.imageHeight
            Image(systemName: placeholderSystemImage)
                .font(.title)
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(.fill.tertiary, in: .rect(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

public extension ViewController {
    /// The picture of a player row: the Character's photo or a placeholder of the same size.
    @MainActor func playerAvatar(for characterId: UUID?, placeholderSystemImage: String) -> some View {
        PlayerAvatarView(characterId: characterId, placeholderSystemImage: placeholderSystemImage)
    }
}

#Preview(traits: .mockData) {
    PlayerAvatarView(characterId: nil, placeholderSystemImage: "eye")
}
