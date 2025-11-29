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
    
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel
    
#if os(visionOS)
    @Environment(WindowStateModel.self) private var windowStateModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
#endif
    
    @State private var selected: URL?
    
    var body: some View {
        ImageOverlayButton(icon: root.itemController.itemDataModel.networkModule.icon) {
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
            if windowStateModel.spaceImmersiveView {
                await dismissImmersiveSpace()
            }
            
            await openImmersiveSpace(id: WindowIdentifier.spaceViewer.rawValue, value: item)
            windowStateModel.spaceImmersiveView = true
        }
#elseif os(tvOS)
        // nothing
#else
        selectionSheetLinkModel.selectionFullView = AnyView(
            SpaceViewer(root: root, id: item.itemId, isModal: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        selectionSheetLinkModel.selectionFullScreen = true
#endif
    }
}
