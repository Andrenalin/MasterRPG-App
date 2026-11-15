// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SpaceQuickLook: View {
    let root: SpaceRootModel
    let item: ItemSelection
    let startLoading: Bool
    let gameMode: Bool
    /// Kept for the call sites; the preview that called it was never presented.
    let dismiss: (() -> Void)?
        
    @Environment(ScenesManager.self) private var scenesManager
    
    var body: some View {
        ImageOverlayButton(
            icon: root.itemController.config.module.icon,
            accessibilityLabel: LocalizedStringResource("Open 3D Object", bundle: .module)
        ) {
            loader()
        }
        .opacity(gameMode ? 0.01 : 1)
        .allowsHitTesting(!gameMode)
        .accessibilityHidden(gameMode)
        .onChange(of: startLoading, initial: true) {
            guard startLoading == true else { return }
            loader()
        }
    }
    
    @MainActor
    func loader() {
#if os(visionOS)
        Task {
            if gameMode {
                // A network reveal is an idempotent presentation request.
                // SharePlay may already be opening or displaying this same
                // immersive scene, so toggling here would close it again.
                await scenesManager.openSpaceViewer(selection: item)
            } else {
                await scenesManager.toggleSpaceViewer(selection: item)
            }
        }
#endif
    }
}

#Preview {
    SpaceQuickLook(
        root: .preview,
        item: ItemSelection(itemId: SpaceModel.previewId, entryId: nil),
        startLoading: false,
        gameMode: false,
        dismiss: nil
    )
    .environment(ScenesManager())
}
