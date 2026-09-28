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
                // `showSpaceViewer`, not `openSpaceViewer`: after a flicker
                // longer than the debounce (true → nil → true, e.g. while
                // opening the game-table volume re-templates the session), the
                // space is already open on this item and `openSpaceViewer`'s
                // toggle closed it.
                let revealedId = root.spaceRoot.gameControllable.gameModel.currentItemId
                if isActive {
                    guard let revealedId, scenesManager.explicitlyDismissedSpaceItemId != revealedId else { return }
                    await scenesManager.showSpaceViewer(selection: ItemSelection(itemId: revealedId, entryId: nil))
                } else {
                    // The GM's reveal owns an open Space item — a lapse in
                    // group immersion (the system renegotiates it when the
                    // game table becomes the primary scene) must not close it.
                    guard revealedId == nil else { return }
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
