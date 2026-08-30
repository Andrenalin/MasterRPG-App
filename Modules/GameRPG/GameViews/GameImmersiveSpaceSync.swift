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

    /// `coordinator.groupImmersionStyle` (see `RPGSharePlayController
    /// .configureSystemCoordinator`) can flicker — style, then a transient
    /// `nil`, then the real style again — while the system renegotiates group
    /// immersion alignment, which happens specifically once a second
    /// participant needs to be aligned into the shared space. Reacting to
    /// every flip called the real `openSpaceViewer`/`dismissSpaceViewer` on
    /// each toggle: a genuine scene teardown/rebuild, not a rendering
    /// glitch, and both participants saw it as the object briefly
    /// appearing then disappearing. Debouncing here means a flicker that
    /// resolves within this window never reaches `ScenesManager` at
    /// all — `.task(id:)` cancels this sleep and starts fresh the moment
    /// `groupImmersionActive` changes again, so only a value that actually
    /// holds gets acted on.
    private static let groupImmersionDebounce: Duration = .milliseconds(750)

    func body(content: Content) -> some View {
        content
            .task(id: root.gameModel.shareState.groupImmersionActive) {
                guard root.networkStore.sharePlayStore.isActive else { return }
                let isActive = root.gameModel.shareState.groupImmersionActive
                try? await Task.sleep(for: Self.groupImmersionDebounce)
                guard !Task.isCancelled, root.gameModel.shareState.groupImmersionActive == isActive else { return }
                if isActive {
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
