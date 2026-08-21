// @copyright André Trettin

import SwiftUI
#if os(visionOS)
import GroupActivities
#endif

#if os(visionOS)

public extension View {
    /// Marks this view's scene as the primary SharePlay scene while the game is
    /// presented in a 2D window or an immersive space, so spatial Personas
    /// gather around the game window (side-by-side template).
    func gameWindowActivityAssociation(root: GameRoot, sceneId: String) -> some View {
        modifier(GameActivityAssociationModifier(root: root, sceneId: sceneId, modes: [.window, .immersive]))
    }

    /// Marks this view's scene as the primary SharePlay scene while the game is
    /// presented on the TabletopKit volume, so `TabletopGame
    /// .coordinateWithSession(_:)` seats participants around the table
    /// itself (see `RPGSharePlayController.applyShareState()`'s own doc for
    /// why that's left to TabletopKit rather than a manual
    /// `spatialTemplatePreference` override).
    func gameTableActivityAssociation(root: GameRoot, sceneId: String) -> some View {
        modifier(GameActivityAssociationModifier(root: root, sceneId: sceneId, modes: [.tabletop]))
    }
}

// The association must follow GameShareStateModel.mode dynamically: when the
// presentation mode switches, the system re-anchors spatial Personas to the
// most recently associated primary scene.
struct GameActivityAssociationModifier: ViewModifier {
    let root: GameRoot
    let sceneId: String
    let modes: [GameShareStateModel.PresentationMode]

    func body(content: Content) -> some View {
        content
            .groupActivityAssociation(modes.contains(root.gameModel.shareState.mode) ? .primary(sceneId) : nil)
    }
}

#else

public extension View {
    func gameWindowActivityAssociation(root: GameRoot, sceneId: String) -> some View {
        self
    }
}

#endif
