// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ImageViewer: View {
    init(
        id: UUID,
        image: AKImage,
        photoDegrees: Double,
        containerSize: CGSize,
        contentMode: ContentMode,
        accessibilityLabel: String,
        accessibilityHint: String?,
        toolBarModel: GameToolBarModel?
    ) {
        self.id = id
        self.image = image
        self.photoDegrees = photoDegrees
        self.containerSize = containerSize
        self.contentMode = contentMode
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.toolBarModel = toolBarModel
    }

    let id: UUID
    let image: AKImage
    let photoDegrees: Double
    let containerSize: CGSize
    let contentMode: ContentMode
    let accessibilityLabel: String
    let accessibilityHint: String?
    let toolBarModel: GameToolBarModel?

    @State private var viewerState = ImageViewerState()

    private var currentDegrees: Double {
        toolBarModel?.degrees(for: id, fallback: photoDegrees)
            ?? ImageViewportGeometry.normalize(photoDegrees)
    }

    private var viewportConfiguration: ImageViewportConfiguration {
        ImageViewportConfiguration(
            id: id,
            imageSize: image.fixedSize,
            containerSize: containerSize,
            degrees: currentDegrees
        )
    }

    private var geometry: ImageViewportGeometry {
        ImageViewportGeometry(configuration: viewportConfiguration)
    }

    var body: some View {
        Group {
            if contentMode == .fill {
                FilledImageCanvas(
                    image: image,
                    geometry: geometry
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            } else {
                InteractiveImageCanvas(
                    image: image,
                    geometry: geometry,
                    viewport: viewerState.viewport
                )
#if !os(tvOS)
                .dragTapGesture(
                    doubleTapAction: doubleTapAction(_:),
                    dragStartAction: dragStartAction(_:),
                    dragAction: dragAction(_:),
                    magnifierAction: magnifierAction(_:isFirst:)
                )
#endif
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: accessibilityLabel))
                .accessibilityHint(Text(verbatim: accessibilityHint ?? ""))
                .accessibilityAddTraits(.isImage)
                .accessibilityAction(named: Text("Zoom in", bundle: .module), zoomIn)
                .accessibilityAction(named: Text("Zoom out", bundle: .module), zoomOut)
                .accessibilityAction(named: Text("Reset zoom", bundle: .module), resetZoom)
            }
        }
        .frame(
            width: geometry.containerSize.width,
            height: geometry.containerSize.height
        )
        .clipped()
        .onChange(of: viewportConfiguration, initial: true) { _, configuration in
            configureViewport(for: configuration)
        }
    }
}

// MARK: - Viewport updates

private extension ImageViewer {
    func configureViewport(for configuration: ImageViewportConfiguration) {
        guard viewerState.configuration != configuration else {
            return
        }

        let previousConfiguration = viewerState.configuration
        let newGeometry = ImageViewportGeometry(configuration: configuration)
        let shouldAnimate = previousConfiguration?.id == configuration.id
            && previousConfiguration?.imageSize == configuration.imageSize
            && previousConfiguration?.containerSize == configuration.containerSize
            && previousConfiguration?.degrees != configuration.degrees

        var newState = ImageViewerState(
            configuration: configuration,
            viewport: newGeometry.fitViewport
        )
        newState.dragStartOffset = newState.viewport.offset

        if shouldAnimate {
            withAnimation(.snappy) {
                viewerState = newState
            }
        } else {
            viewerState = newState
        }
    }

    func apply(_ viewport: ImageViewport, animated: Bool) {
        guard viewerState.viewport != viewport else {
            return
        }

        if animated {
            withAnimation(.snappy) {
                viewerState.viewport = viewport
            }
        } else {
            viewerState.viewport = viewport
        }
    }

    func resetZoom() {
        apply(geometry.fitViewport, animated: true)
    }

    func zoomIn() {
        zoom(by: 2)
    }

    func zoomOut() {
        zoom(by: 0.5)
    }

    func zoom(by factor: CGFloat) {
        let targetScale = geometry.clampedScale(viewerState.viewport.scale * factor)
        let targetViewport = geometry.zoomedViewport(
            from: viewerState.viewport,
            toScale: targetScale,
            anchor: CGPoint(
                x: geometry.containerSize.width / 2,
                y: geometry.containerSize.height / 2
            )
        )
        apply(targetViewport, animated: true)
    }
}

#if !os(tvOS)
// MARK: - Gesture handlers

private extension ImageViewer {
    func doubleTapAction(_ value: DragGesture.Value) {
        let targetViewport = geometry.doubleTapViewport(
            from: viewerState.viewport,
            at: value.location
        )
        apply(targetViewport, animated: true)
    }

    func dragStartAction(_: DragGesture.Value) {
        viewerState.dragStartOffset = viewerState.viewport.offset
    }

    func dragAction(_ value: DragGesture.Value) {
        let proposedOffset = CGPoint(
            x: viewerState.dragStartOffset.x + value.translation.width,
            y: viewerState.dragStartOffset.y + value.translation.height
        )
        let clampedOffset = geometry.clampedOffset(
            proposedOffset,
            at: viewerState.viewport.scale
        )
        viewerState.viewport = ImageViewport(
            scale: viewerState.viewport.scale,
            offset: clampedOffset
        )
    }

    func magnifierAction(_ value: MagnifyGesture.Value, isFirst: Bool) {
        if isFirst || viewerState.magnificationStartViewport == nil {
            viewerState.magnificationStartViewport = viewerState.viewport
        }
        guard let startViewport = viewerState.magnificationStartViewport else {
            return
        }

        viewerState.viewport = geometry.zoomedViewport(
            from: startViewport,
            toScale: startViewport.scale * value.magnification,
            anchor: value.startLocation
        )
    }
}
#endif

private struct ImageViewerState: Equatable {
    var configuration: ImageViewportConfiguration?
    var viewport = ImageViewport(scale: 1, offset: .zero)
    var dragStartOffset = CGPoint.zero
    var magnificationStartViewport: ImageViewport?
}

private struct InteractiveImageCanvas: View {
    let image: AKImage
    let geometry: ImageViewportGeometry
    let viewport: ImageViewport

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            RotatedImage(
                image: image,
                originalSize: geometry.originalImageSize,
                rotatedSize: geometry.rotatedImageSize,
                degrees: geometry.normalizedDegrees
            )
            .scaleEffect(viewport.scale, anchor: .topLeading)
            .offset(x: viewport.offset.x, y: viewport.offset.y)
        }
        .frame(
            width: geometry.containerSize.width,
            height: geometry.containerSize.height,
            alignment: .topLeading
        )
        .contentShape(.rect)
        .clipped()
    }
}

private struct FilledImageCanvas: View {
    let image: AKImage
    let geometry: ImageViewportGeometry

    var body: some View {
        ZStack {
            Image(akImage: image)
                .resizable()
                .frame(
                    width: geometry.originalImageSize.width * geometry.fillScale,
                    height: geometry.originalImageSize.height * geometry.fillScale
                )
                .rotationEffect(.degrees(geometry.normalizedDegrees))
        }
        .frame(
            width: geometry.containerSize.width,
            height: geometry.containerSize.height
        )
        .clipped()
    }
}

private struct RotatedImage: View {
    let image: AKImage
    let originalSize: CGSize
    let rotatedSize: CGSize
    let degrees: Double

    var body: some View {
        ZStack {
            Image(akImage: image)
                .resizable()
                .frame(width: originalSize.width, height: originalSize.height)
                .rotationEffect(.degrees(degrees))
        }
        .frame(width: rotatedSize.width, height: rotatedSize.height)
    }
}
