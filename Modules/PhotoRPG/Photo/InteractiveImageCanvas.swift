// @copyright André Trettin

import CoreRPG
import SwiftUI

struct InteractiveImageCanvas: View {
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

#Preview {
    let geometry = ImageViewportGeometry(
        configuration: ImageViewportConfiguration(
            id: PhotoModel.previewId,
            imageSize: CGSize(width: 800, height: 600),
            containerSize: CGSize(width: 600, height: 400),
            degrees: 15
        )
    )
    InteractiveImageCanvas(
        image: AKImage(systemName: "photo")!,
        geometry: geometry,
        viewport: geometry.fitViewport
    )
}
