// @copyright André Trettin

import CoreRPG
import SwiftUI

struct FilledImageCanvas: View {
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

#Preview {
    FilledImageCanvas(
        image: AKImage(systemName: "photo")!,
        geometry: ImageViewportGeometry(
            configuration: ImageViewportConfiguration(
                id: PhotoModel.previewId,
                imageSize: CGSize(width: 800, height: 600),
                containerSize: CGSize(width: 600, height: 400),
                degrees: 15
            )
        )
    )
}
