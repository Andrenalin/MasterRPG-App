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

    let imageList: ImageListModel
    let size: CGSize
    
    var body: some View {
        Group {
            if !imageList.images.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(imageList.images.enumerated(), id: \.element.id) { index, image in
                            if let image = AKImage(data: image.imageData) {
                                Image(akImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: size.width - 30)
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
                .frame(height: 300)
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

    PhotoSection(
        imageList: imageList,
        size: CGSize(width: 390, height: 300)
    )
}
