// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: PhotoModel
    var toolBarModel: GameToolBarModel = GameToolBarModel()
    var windowMode: Bool = false
    var externalViewer: Bool = true
    var isGame: Bool = false
    var dismissAction: (() -> Void)? = nil

    @Environment(PhotoRootModel.self) private var root
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appSizeMode) private var appSizeMode
    
#if os(visionOS)
    @Environment(\.openImmersiveSpace) private var openSpace
    @Environment(\.dismissImmersiveSpace) private var dismissSpace
#endif

    var body: some View {
        let _ = Self._printChanges()
        VStack {
            GeometryReader { geo in
                RootImageViewer(model: model, size: geo.size, toolBarModel: toolBarModel, isGame: isGame) {
                    if let dismissAction {
                        dismissAction()
                    } else {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: root.gameController.photoGameModel.openPhotoSpace, initial: false) {
#if os(visionOS)
            Task {
                if root.gameController.photoGameModel.openPhotoSpace {
                    await openSpace(id: "PhotoWorld", value: PhotoWorldSelection(id: model.id, rotationDegrees: 67))
                } else {
                    await dismissSpace()
                }
            }
#endif
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .applyIf(externalViewer && !isGame) {
            $0.toolbar {
                toolbarContent
            }
            .navigationTitle(Text(model.name))
#if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
        .applyIf(isGame) {
            $0.overlay(alignment: .bottomLeading)  {
                rotateButton
#if !os(visionOS)
                    .buttonStyle(.glass)
#endif
                    .padding()
            }
        }
#if !os(visionOS)
        .background(.black.gradient)
#endif
        .environment(CacheItemListModel())
    }
}

private extension ViewerRootView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if shouldShowCloseButton {
            ToolbarItem(placement: .cancellationAction) {
                closeButton
            }
        }
        
        ToolbarItem(placement: .primaryAction) {
            rotateButton
        }
    }
    
    var shouldShowCloseButton: Bool {
        valueFor(iOS: appSizeMode == .compact || dismissAction != nil, macOS: false, tvOS: dismissAction != nil, visionOS: dismissAction != nil)
    }

    var closeButton: some View {
        Button {
            if let dismissAction {
                dismissAction()
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "xmark.circle")
        }
    }
    
    var rotateButton: some View {
        Button {
            withAnimation { model.degrees += 90 }
        } label: {
            Image(systemName: "rotate.right")
                .rotationEffect(Angle(degrees: model.degrees))
        }
        .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
    }

}

#Preview(traits: .mockData) {
    @Previewable @Environment(PhotoRootModel.self) var root
    
    NavigationStack {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]), externalViewer: false)
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
            .environment(PhotoRootModel.previewWithData)
    }
}
