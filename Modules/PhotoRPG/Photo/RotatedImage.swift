// @copyright André Trettin

import CoreRPG
import SwiftUI

struct RotatedImage: View {
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

#if !os(macOS)
#Preview {
    RotatedImage(
        image: AKImage(systemName: "photo")!,
        originalSize: CGSize(width: 400, height: 300),
        rotatedSize: CGSize(width: 500, height: 500),
        degrees: 45
    )
}
#endif
