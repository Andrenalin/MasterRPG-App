// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: PhotoModel
    let configuration: ViewerConfiguration
    var dismissAction: (() -> Void)? = nil
    var trailingViewportReservation: CGFloat = 0

    @Environment(PhotoRootModel.self) private var root
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var toolBarModel: GameToolBarModel = GameToolBarModel()
    @State private var cacheItemListModel = CacheItemListModel()
    @State private var containerSize: CGSize = .zero

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
                            .selectedRoundButton(title: String(localized: "Rotate image", bundle: .module), module: .photo, isSelected: false)
                            .padding()
                    }
            } else {
                contentView
            }
        }
        .ignoresSafeArea(.container, edges: ignoredSafeAreaEdges)
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

    private var ignoredSafeAreaEdges: Edge.Set {
        configuration.addToolbar || configuration.isGame ? [.top, .bottom] : .bottom
    }
}

// MARK: - Content

private extension ViewerRootView {
    var contentView: some View {
        let viewportSize = PhotoViewportReservation.effectiveContainerSize(
            measuredSize: containerSize,
            trailingReservation: trailingViewportReservation
        )
        return Color.clear
            .overlay(alignment: .topLeading) {
                AsyncImageViewer(
                    model: model,
                    size: viewportSize,
                    toolBarModel: toolBarModel
                )
                .frame(width: viewportSize.width, height: viewportSize.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#if !os(visionOS)
                .background(Color.black.gradient)
#endif
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newValue in
                containerSize = newValue
            }
    }
}

struct PhotoViewportReservation {
    static func effectiveContainerSize(
        measuredSize: CGSize,
        trailingReservation: CGFloat
    ) -> CGSize {
        guard measuredSize.width.isFinite,
              measuredSize.height.isFinite,
              measuredSize.width > 0,
              measuredSize.height > 0 else {
            return .zero
        }

        let reservation = trailingReservation.isFinite
            ? max(0, trailingReservation)
            : 0
        let minimumRecoverableWidth = min(44, measuredSize.width)
        return CGSize(
            width: max(minimumRecoverableWidth, measuredSize.width - reservation),
            height: measuredSize.height
        )
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
        let tintColor = theme.tint(for: root.config.module)
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
        let tintColor = theme.tint(for: root.config.module)
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
