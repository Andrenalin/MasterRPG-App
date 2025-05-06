// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGPhotos

struct MapReader: View {
    let map: MapModel

    @Environment(MapRoot.self) private var root

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var size: CGSize = .zero

    var body: some View {
        ZStack {
            Color.clear
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: {
                    size = $0
                }

            Group {
                if size.height > size.width {
                    VStack {
                        imageView(size: CGSize(width: size.width, height: 256))
                        textView()
                    }
                } else {
                    HStack {
                        imageView(size: CGSize(width: 256, height: size.height))
                        textView()
                    }
                }
            }
        }
#if !os(visionOS)
        .background(colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea())
#endif
    }
}

private extension MapReader {
    func imageView(size _: CGSize = .zero) -> some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle")
                }
                .borderLessTVBottonStyle()
                Text(map.name)
                    .lineLimit(4)
            }
            .font(.largeTitle)
            .padding(.top, 8)

            root.photoRoot.viewController.photoView(for: map.photoId, useGame: false) { image, photoDegrees in
                Image(akImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .rotationEffect(Angle(degrees: photoDegrees))
                    .cornerRadius(16)
                    .frame(width: 256, height: 256, alignment: .center)
            }
        }
    }

    func textView() -> some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                Text(map.description.markDown())

                ForEach(map.entries) { entry in
                    Text(entry.name.markDown(asBold: true)).font(.title)
                    if !entry.content.isEmpty {
                        Text(entry.content.markDown())
                    }
                }
            }
            .font(.body)
            .padding()
        }
    }
}
