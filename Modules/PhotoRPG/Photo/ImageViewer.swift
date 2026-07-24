// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ImageViewer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let id: UUID
    let image: AKImage
    let photoDegrees: Double
    let containerSize: CGSize
    let contentMode: ContentMode
    let accessibilityLabel: String
    let accessibilityHint: String?
    let toolBarModel: GameToolBarModel?

    @State private var viewportModel: ViewportModel
    @State private var configuredImageViewport: ImageViewportConfiguration?
#if !os(tvOS)
    @GestureState private var gestureSession = ImageViewportGestureSession()
#endif

    private var currentDegrees: Double {
        toolBarModel?.degrees(for: id, fallback: photoDegrees)
            ?? ViewportGeometry.normalize(rotationDegrees: photoDegrees)
    }

    private var imageViewportConfiguration: ImageViewportConfiguration {
        ImageViewportConfiguration(
            id: id,
            imageSize: image.fixedSize,
            containerSize: containerSize,
            degrees: currentDegrees
        )
    }

    private var geometry: ImageViewportGeometry {
        ImageViewportGeometry(configuration: imageViewportConfiguration)
    }

    private var displayedTransform: ViewportTransform {
#if os(tvOS)
        viewportModel.transform
#else
        geometry.viewportGeometry.interacting(
            from: viewportModel.transform,
            translation: gestureSession.translation,
            magnification: gestureSession.magnification,
            anchor: gestureSession.anchor ?? geometry.viewportGeometry.containerCenter
        )
#endif
    }

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

        let imageConfiguration = ImageViewportConfiguration(
            id: id,
            imageSize: image.fixedSize,
            containerSize: containerSize,
            degrees: photoDegrees
        )
        let geometry = ImageViewportGeometry(configuration: imageConfiguration)
        _viewportModel = State(initialValue: ViewportModel(
            configuration: geometry.viewportConfiguration
        ))
    }

    var body: some View {
        Group {
            if contentMode == .fill {
                FilledImageCanvas(image: image, geometry: geometry)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: accessibilityLabel))
                    .accessibilityHint(Text(verbatim: accessibilityHint ?? ""))
                    .accessibilityAddTraits(.isImage)
            } else {
                InteractiveImageCanvas(
                    image: image,
                    geometry: geometry,
                    viewport: displayedTransform
                )
#if !os(tvOS)
                .simultaneousGesture(viewportGesture)
                .highPriorityGesture(doubleTapGesture)
#endif
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: accessibilityLabel))
                .accessibilityHint(Text(verbatim: accessibilityHint ?? ""))
                .accessibilityValue(
                    Text(
                        "Zoom \(viewportModel.transform.scale / geometry.fitScale, format: .percent)",
                        bundle: .module
                    )
                )
                .accessibilityAddTraits(.isImage)
                .accessibilityAction(named: Text("Zoom in", bundle: .module), zoomIn)
                .accessibilityAction(named: Text("Zoom out", bundle: .module), zoomOut)
                .accessibilityAction(named: Text("Reset zoom", bundle: .module), resetZoom)
                .accessibilityAdjustableAction(adjustZoom(_:))
            }
        }
        .frame(width: geometry.containerSize.width, height: geometry.containerSize.height)
        .clipped()
        .onChange(of: imageViewportConfiguration, initial: true) { _, configuration in
            configureViewport(for: configuration)
        }
    }
}

// MARK: - Viewport updates

private extension ImageViewer {
    func configureViewport(for configuration: ImageViewportConfiguration) {
        guard configuredImageViewport != configuration else {
            return
        }

        let previousConfiguration = configuredImageViewport
        let geometry = ImageViewportGeometry(configuration: configuration)
        let shouldAnimate = previousConfiguration?.id == configuration.id
            && previousConfiguration?.imageSize == configuration.imageSize
            && previousConfiguration?.containerSize == configuration.containerSize
            && previousConfiguration?.degrees != configuration.degrees

        let update = {
            if viewportModel.configuration == geometry.viewportConfiguration {
                // A 180-degree rotation (or a 90-degree rotation of square content) keeps the
                // same bounding size, but ImageViewer has always reset zoom after rotation.
                viewportModel.reset()
            } else if let previousConfiguration,
                      previousConfiguration.id == configuration.id,
                      previousConfiguration.imageSize == configuration.imageSize,
                      previousConfiguration.degrees == configuration.degrees {
                // Sidebar changes resize the usable photo viewport without replacing the
                // full-window game surface. Preserve the same logical center and zoom just
                // like the map viewport does when its trailing reservation changes.
                viewportModel.resize(to: geometry.viewportConfiguration)
            } else {
                viewportModel.configure(geometry.viewportConfiguration)
            }
            configuredImageViewport = configuration
        }
        if shouldAnimate && !reduceMotion {
            withAnimation(.snappy, update)
        } else {
            update()
        }
    }

    func apply(_ transform: ViewportTransform, animated: Bool) {
        guard viewportModel.transform != transform else {
            return
        }

        if animated && !reduceMotion {
            withAnimation(.snappy) {
                viewportModel.commit(transform)
            }
        } else {
            viewportModel.commit(transform)
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
        let targetScale = geometry.clampedScale(viewportModel.transform.scale * factor)
        let targetTransform = geometry.viewportGeometry.zoomed(
            from: viewportModel.transform,
            toScale: targetScale,
            anchor: geometry.viewportGeometry.containerCenter
        )
        apply(targetTransform, animated: true)
    }

    func adjustZoom(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            zoomIn()
        case .decrement:
            zoomOut()
        @unknown default:
            break
        }
    }
}

#if !os(tvOS)
// MARK: - Gesture session

private extension ImageViewer {
    typealias ViewportGesture = SimultaneousGesture<MagnifyGesture, DragGesture>

    var viewportGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .simultaneously(with: DragGesture(minimumDistance: 3, coordinateSpace: .local))
            .updating($gestureSession, body: updateGestureSession(_:state:transaction:))
            .onEnded(commitGestureSession(_:))
    }

    var doubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2, coordinateSpace: .local)
            .onEnded(doubleTap(_:))
    }

    func updateGestureSession(
        _ value: ViewportGesture.Value,
        state: inout ImageViewportGestureSession,
        transaction _: inout Transaction
    ) {
        if let magnify = value.first {
            state.magnification = magnify.magnification
            state.anchor = magnify.startLocation
        }
        if let drag = value.second {
            state.translation = drag.translation
        }
    }

    func commitGestureSession(_ value: ViewportGesture.Value) {
        let transform = geometry.viewportGeometry.interacting(
            from: viewportModel.transform,
            translation: value.second?.translation ?? gestureSession.translation,
            magnification: value.first?.magnification ?? gestureSession.magnification,
            anchor: value.first?.startLocation
                ?? gestureSession.anchor
                ?? geometry.viewportGeometry.containerCenter
        )
        apply(transform, animated: false)
    }

    func doubleTap(_ value: SpatialTapGesture.Value) {
        let transform = geometry.viewportGeometry.doubleTapped(
            from: viewportModel.transform,
            at: value.location
        )
        apply(transform, animated: true)
    }
}

private struct ImageViewportGestureSession: Equatable {
    var translation = CGSize.zero
    var magnification: CGFloat = 1
    var anchor: CGPoint?
}
#endif

#if !os(macOS)
#Preview {
    ImageViewer(
        id: PhotoModel.previewId,
        image: AKImage(systemName: "photo")!,
        photoDegrees: 0,
        containerSize: CGSize(width: 600, height: 400),
        contentMode: .fit,
        accessibilityLabel: "Preview photo",
        accessibilityHint: nil,
        toolBarModel: nil
    )
}
#endif
