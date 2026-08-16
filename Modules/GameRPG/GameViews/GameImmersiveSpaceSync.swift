// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import SpaceRPG
import SwiftUI

/// Keeps the space viewer immersive space in sync with SharePlay group
/// immersion. Follows the SharePlay group in and out of the shared immersive
/// space (`groupImmersionStyle` drives `shareState.groupImmersionActive`).
///
/// Deliberately never touches `shareState.mode`/the spatial-template seating:
/// opening or closing the space viewer used to force `.immersive` (sideBySide)
/// here, which would silently drop a game table's `.tabletop` (surround)
/// seating whenever a Space item was revealed. The space viewer now opens
/// without changing the current seating.
struct GameImmersiveSpaceSyncModifier: ViewModifier {
    let root: GameRoot

    @Environment(ScenesManager.self) private var scenesManager

    func body(content: Content) -> some View {
        content
            .task(id: root.gameModel.shareState.groupImmersionActive) {
                guard root.networkStore.sharePlayStore.isActive else { return }
                if root.gameModel.shareState.groupImmersionActive {
                    await scenesManager.openSpaceViewer(selection: ItemSelection(itemId: root.spaceRoot.gameControllable.currentId, entryId: nil))
                } else {
                    await scenesManager.dismissSpaceViewer()
                }
            }
    }
}

extension View {
    func gameImmersiveSpaceSync(root: GameRoot) -> some View {
        modifier(GameImmersiveSpaceSyncModifier(root: root))
    }
}
#endif
