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
                ViewerContentView(model: model, toolBarModel: toolBarModel)
                    .toolbar { toolbarContent }
                    .navigationTitle(model.name)
                    .navigationBarTitleDisplayModeAll(.inline)
            } else if configuration.isGame {
                ViewerContentView(model: model, toolBarModel: toolBarModel)
                    .overlay(alignment: .bottomLeading) {
                        ViewerRotateButton(toolBarModel: toolBarModel, model: model)
#if !os(visionOS)
                            .buttonStyle(.glass)
#endif
                            .padding()
                    }
            } else {
                ViewerContentView(model: model, toolBarModel: toolBarModel)
            }
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
#if !os(visionOS)
        .background(Color.black.gradient)
#endif
        .environment(cacheItemListModel)
    }
}

// MARK: - Toolbar

private extension ViewerRootView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if configuration.closeButton {
            ToolbarItem(placement: .cancellationAction) {
                ViewerCloseButton(dismissAction: dismissAction)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            ViewerRotateButton(toolBarModel: toolBarModel, model: model)
        }
    }
}

// MARK: - Content

private struct ViewerContentView: View {
    let model: PhotoModel
    let toolBarModel: GameToolBarModel

    var body: some View {
        GeometryReader { geo in
            AsyncImageViewer(
                model: model,
                size: geo.size,
                toolBarModel: toolBarModel
            )
#if !os(visionOS)
            .background(Color.black.gradient)
#endif
        }
    }
}

// MARK: - Buttons

private struct ViewerCloseButton: View {
    let dismissAction: (() -> Void)?

    @Environment(PhotoRootModel.self) private var root
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let tintColor = root.config.module.tint
        Button {
            if let dismissAction {
                dismissAction()
            } else {
                dismiss()
            }
        } label: {
            Label {
                Text("Close", bundle: .module)
            } icon: {
                Image(systemName: "xmark.circle")
            }
        }
        .labelStyle(.iconOnly)
#if os(macOS)
        .foregroundStyle(tintColor)
#else
        .tint(tintColor)
#endif
    }
}

private struct ViewerRotateButton: View {
    let toolBarModel: GameToolBarModel
    let model: PhotoModel

    @Environment(PhotoRootModel.self) private var root

    var body: some View {
        let tintColor = root.config.module.tint
        Button {
            withAnimation {
                toolBarModel.degrees += 90
            }
        } label: {
            Label {
                Text("Rotate", bundle: .module)
            } icon: {
                Image(systemName: "rotate.right")
                    .rotationEffect(Angle(degrees: model.degrees))
            }
        }
        .labelStyle(.iconOnly)
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
