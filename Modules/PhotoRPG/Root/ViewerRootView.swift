// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: PhotoModel
    let configuration: ViewerConfiguration
    var dismissAction: (() -> Void)? = nil
    var trailingViewportReservation: CGFloat = 0
    var bottomViewportReservation: CGFloat = 0

    @State private var toolBarModel: GameToolBarModel = GameToolBarModel()
    @State private var cacheItemListModel = CacheItemListModel()
    @State private var containerSize: CGSize = .zero

    var body: some View {
        Group {
            if configuration.addToolbar && !configuration.isGame {
                PhotoContentView(
                    model: model,
                    trailingViewportReservation: trailingViewportReservation,
                    bottomViewportReservation: bottomViewportReservation,
                    toolBarModel: toolBarModel,
                    containerSize: $containerSize
                )
                    .toolbar { toolbarContent }
                    .navigationTitle(model.name)
                    .navigationBarTitleDisplayModeAll(.inline)
            } else if configuration.isGame {
                PhotoContentView(
                    model: model,
                    trailingViewportReservation: trailingViewportReservation,
                    bottomViewportReservation: bottomViewportReservation,
                    toolBarModel: toolBarModel,
                    containerSize: $containerSize
                )
                    .overlay(alignment: .bottomLeading) {
                        PhotoRotateButtonView(model: model, toolBarModel: toolBarModel)
                            .selectedRoundButton(title: String(localized: "Rotate image", bundle: .module), module: .photo, isSelected: false)
                            .padding()
                            // Above a bottom sidebar panel, which the viewport leaves free.
                            .padding(.bottom, bottomViewportReservation)
                    }
            } else {
                PhotoContentView(
                    model: model,
                    trailingViewportReservation: trailingViewportReservation,
                    bottomViewportReservation: bottomViewportReservation,
                    toolBarModel: toolBarModel,
                    containerSize: $containerSize
                )
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

private struct PhotoContentView: View {
    let model: PhotoModel
    let trailingViewportReservation: CGFloat
    let bottomViewportReservation: CGFloat
    let toolBarModel: GameToolBarModel
    @Binding var containerSize: CGSize

    var body: some View {
        let viewportSize = PhotoViewportReservation.effectiveContainerSize(
            measuredSize: containerSize,
            trailingReservation: trailingViewportReservation,
            bottomReservation: bottomViewportReservation
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
        trailingReservation: CGFloat,
        bottomReservation: CGFloat = 0
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
        let bottom = bottomReservation.isFinite
            ? max(0, bottomReservation)
            : 0
        let minimumRecoverableWidth = min(44, measuredSize.width)
        let minimumRecoverableHeight = min(44, measuredSize.height)
        return CGSize(
            width: max(minimumRecoverableWidth, measuredSize.width - reservation),
            height: max(minimumRecoverableHeight, measuredSize.height - bottom)
        )
    }
}

// MARK: - Toolbar

private extension ViewerRootView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if configuration.closeButton {
            ToolbarItem(placement: .cancellationAction) {
                PhotoCloseButtonView(dismissAction: dismissAction)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            PhotoRotateButtonView(model: model, toolBarModel: toolBarModel)
        }
    }
}

// MARK: - Buttons

private struct PhotoCloseButtonView: View {
    var dismissAction: (() -> Void)?

    @Environment(PhotoRootModel.self) private var root
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
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
}

private struct PhotoRotateButtonView: View {
    let model: PhotoModel
    let toolBarModel: GameToolBarModel

    @Environment(PhotoRootModel.self) private var root
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
