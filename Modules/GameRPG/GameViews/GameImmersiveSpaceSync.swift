// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import SpaceRPG
import SwiftUI

/// Keeps the share state in sync with the space viewer immersive space.
///
/// - Follows the SharePlay group in and out of the shared immersive space
///   (`groupImmersionStyle` drives `shareState.groupImmersionActive`).
/// - Switches the presentation mode when the space opens or closes; the
///   `modeChanged` observer in RPGSharePlayController then reconfigures the
///   spatial template, so this works on master and player screens alike.
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
            .task(id: scenesManager.getSceneState(for: SceneId.spaceViewer)) {
                switch scenesManager.getSceneState(for: SceneId.spaceViewer) {
                case .opened:
                    root.gameModel.shareState.mode <=> .immersive
                case .closed:
                    if root.gameModel.shareState.mode == .immersive {
                        root.gameModel.shareState.mode = .window
                    }
                case .opening, .closing:
                    break
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
