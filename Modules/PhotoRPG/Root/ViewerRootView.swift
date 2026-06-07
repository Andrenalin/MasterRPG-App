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
    @State private var cacheItemListModel = CacheItemListModel()

    var body: some View {
        Group {
            if configuration.addToolbar && !configuration.isGame {
                contentView
                    .toolbar { toolbarContent }
                    .navigationTitle(model.name)
                    .navigationBarTitleDisplayModeAll(.inline)
            } else if configuration.isGame {
                contentView
                    .overlay(alignment: .bottomLeading) {
                        rotateButton
#if !os(visionOS)
                            .buttonStyle(.glass)
#endif
                            .padding()
                    }
            } else {
                contentView
            }
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
#if !os(visionOS)
        .background(Color.black.gradient)
#endif
        .environment(cacheItemListModel)
    }
}

// MARK: - Content

private extension ViewerRootView {
    var contentView: some View {
        GeometryReader { geo in
            AsyncImageViewer(
                model: model,
                size: geo.size,
                toolBarModel: toolBarModel
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
#if !os(visionOS)
            .background(Color.black.gradient)
#endif
        }
    }
}

// MARK: - Toolbar

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
}

// MARK: - Buttons

private extension ViewerRootView {
    var closeButton: some View {
        let tintColor = root.config.module.tint
        return Button {
            if let dismissAction {
                dismissAction()
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "xmark.circle")
        }
#if os(macOS)
        .foregroundStyle(tintColor)
#else
        .tint(tintColor)
#endif
    }
    
    var rotateButton: some View {
        let tintColor = root.config.module.tint
        return Button {
            withAnimation {
                toolBarModel.degrees += 90
            }
        } label: {
            Image(systemName: "rotate.right")
                .rotationEffect(Angle(degrees: model.degrees))
        }
        .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
#if os(macOS)
        .foregroundStyle(tintColor)
#else
        .tint(tintColor)
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(PhotoRootModel.self) var root
    
    NavigationStack {
        ViewerRootView(
            model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]),
            configuration: ViewerConfiguration()
        )
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
        .environment(PhotoRootModel.previewWithData)
    }
}
