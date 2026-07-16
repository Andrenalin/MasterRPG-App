// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: PhotoModel
    let configuration: ViewerConfiguration
    var dismissAction: (() -> Void)? = nil

    @Environment(PhotoRootModel.self) private var root
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
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
        .onChange(of: toolbarConfiguration, initial: true) { _, configuration in
            toolBarModel.configure(
                photoId: configuration.photoId,
                degrees: configuration.degrees
            )
        }
    }

    private var toolbarConfiguration: PhotoToolbarConfiguration {
        PhotoToolbarConfiguration(photoId: model.id, degrees: model.degrees)
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
            Label {
                Text("Close", bundle: .module)
            } icon: {
                Image(systemName: "xmark.circle")
            }
            .labelStyle(.iconOnly)
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
            withAnimation(reduceMotion ? nil : .default) {
                toolBarModel.configure(photoId: model.id, degrees: model.degrees)
                toolBarModel.rotateClockwise()
            }
        } label: {
            Label {
                Text("Rotate image", bundle: .module)
            } icon: {
                Image(systemName: "rotate.right")
                    .rotationEffect(.degrees(
                        toolBarModel.degrees(for: model.id, fallback: model.degrees)
                    ))
            }
            .labelStyle(.iconOnly)
        }
        .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
#if os(macOS)
        .foregroundStyle(tintColor)
#else
        .tint(tintColor)
#endif
    }
}

private struct PhotoToolbarConfiguration: Equatable {
    let photoId: UUID
    let degrees: Double
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
