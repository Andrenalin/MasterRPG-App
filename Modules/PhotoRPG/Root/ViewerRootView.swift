// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: PhotoModel
    let configuration: ViewerConfiguration
    var dismissAction: (() -> Void)? = nil

    @Environment(PhotoRootModel.self) private var root
    @Environment(\.dismiss) private var dismiss
    
#if os(visionOS)
    @Environment(\.openImmersiveSpace) private var openSpace
    @Environment(\.dismissImmersiveSpace) private var dismissSpace
#endif

    @State private var toolBarModel: GameToolBarModel = GameToolBarModel()

    var body: some View {
        VStack {
            GeometryReader { geo in
                AsyncImageViewer(model: model, size: geo.size, toolBarModel: toolBarModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.gradient)
            }
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .applyIf(configuration.addToolbar && !configuration.isGame) {
            $0.toolbar {
                toolbarContent
            }
            .navigationTitle(Text(model.name))
            .navigationBarTitleDisplayModeAll(.inline)
        }
        .applyIf(configuration.isGame) {
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
        if configuration.closeButton {
            ToolbarItem(placement: .cancellationAction) {
                closeButton
            }
        }
        
        ToolbarItem(placement: .primaryAction) {
            rotateButton
        }
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
#if os(macOS)
                .foregroundStyle(root.config.module.tint)
#else
                .tint(root.config.module.tint)
#endif
    }
    
    var rotateButton: some View {
        Button {
            withAnimation { toolBarModel.degrees += 90 }
        } label: {
            Image(systemName: "rotate.right")
                .rotationEffect(Angle(degrees: model.degrees))
        }
        .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
#if os(macOS)
                .foregroundStyle(root.config.module.tint)
#else
                .tint(root.config.module.tint)
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(PhotoRootModel.self) var root
    
    NavigationStack {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]), configuration: ViewerConfiguration())
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
            .environment(PhotoRootModel.previewWithData)
    }
}
