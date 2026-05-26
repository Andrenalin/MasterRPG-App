// @copyright André Trettin

import CoreRPG
import SwiftUI

#if !os(tvOS)
import QuickLook
#endif

struct SpaceQuickLook: View {
    let root: SpaceRootModel
    let item: ItemSelection
    let startLoading: Bool
    let gameMode: Bool
    let dismiss: (() -> Void)?
        
    @Environment(ScenesManager.self) private var scenesManager
    
    @State private var selected: URL?
    
    var body: some View {
        ImageOverlayButton(icon: root.itemController.config.module.icon) {
            loader()
        }
        .opacity(gameMode ? 0.01 : 1)
        .onChange(of: startLoading, initial: true) {
            guard startLoading == true else { return }
            loader()
        }
#if !os(tvOS)
        .quickLookPreview($selected)
#endif
        .onChange(of: selected, initial: false) {
            guard selected == nil else { return }
            dismiss?()
        }
    }
    
    @MainActor
    func loader() {
#if os(visionOS)
        Task {
            await scenesManager.toggleSpaceViewer(selection: item)
        }
#endif
    }
}
