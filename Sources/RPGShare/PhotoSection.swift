// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

@Observable @MainActor
final class ImageListModel {
    var images: [ImageItem] = []
}

struct PhotoSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var photoHeight: CGFloat = 300

    let imageList: ImageListModel
    
    var body: some View {
        Group {
            if !imageList.images.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(imageList.images.enumerated(), id: \.element.id) { index, image in
                            if let preview = image.preview {
                                Image(decorative: preview, scale: 1)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    // Nine tenths of the scroll view, so the next photo peeks in.
                                    .containerRelativeFrame(.horizontal, count: 10, span: 9, spacing: 0)
                                    .clipShape(.rect(cornerRadius: 10))
                                    .accessibilityLabel(Text("Shared image", bundle: .main))
                                    .accessibilityValue(
                                        Text("\(index + 1) of \(imageList.images.count)", bundle: .main)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .frame(height: photoHeight)
                .scrollIndicators(.hidden)
                .transition(reduceMotion ? .opacity : .push(from: .top))
            }
        }
    }
}

#Preview("Shared photo") {
    let imageList: ImageListModel = {
        let imageList = ImageListModel()
        let imageData = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2fH0AAAAASUVORK5CYII="
        ) ?? Data()
        imageList.images = [ImageItem(imageData: imageData)]
        return imageList
    }()

    PhotoSection(imageList: imageList)
}
