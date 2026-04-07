// @copyright André Trettin

import SwiftUI

struct AlbumArtworkView: View {
    let artwork: Image?
    let fallbackImage: Image
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let artwork {
                artwork
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                fallbackImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .shadow(radius: 2, y: 1)
        .accessibilityLabel("Album Artwork")
        .accessibilityHidden(true) // Decorative image
    }
}
