// @copyright André Trettin

import CoreRPG
import SwiftUI

@Observable
final class ImageListModel {
    var images: [ImageItem] = []
}

struct PhotoSection: View {
    let imageList: ImageListModel
    let size: CGSize
    
    var body: some View {
        Group {
            if !imageList.images.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(imageList.images, id: \.self) { image in
                            if let image = AKImage(data: image.imageData) {
                                Image(akImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: size.width - 30)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .frame(height: 300)
                .scrollIndicators(.hidden)
                .transition(.push(from: .top))
            }
        }
    }
}
