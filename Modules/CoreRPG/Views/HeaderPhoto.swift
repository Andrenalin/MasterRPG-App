// @copyright André Trettin

import SwiftUI

public struct HeaderPhoto: View {
    public init(itemId: Binding<UUID?>, image: AKImage?, degrees: Double, size: CGSize, topMargin: CGFloat) {
        self.itemId = itemId
        self.image = image
        self.degrees = degrees
        self.size = size
        self.topMargin = topMargin
    }

    let itemId: Binding<UUID?>
    let image: AKImage?
    let degrees: Double
    let size: CGSize
    let topMargin: CGFloat

    @State private var fadeIn: Bool = false

    public var body: some View {
        VStack {
            if let image {
                Image(akImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .rotationEffect(Angle(degrees: degrees))
                    .blur(radius: fadeIn ? 8 : 0)
                    .overlay(alignment: .bottom) {
                        Group {
                            Image(akImage: image)
                                .resizable()
                                .aspectRatio(contentMode: fadeIn ? .fit : .fill)
                                .frame(width: imageSize(from: image).width, height: imageSize(from: image).height)
                                .rotationEffect(Angle(degrees: degrees))
                        }
                        .frame(width: containerSize(from: image).width, height: containerSize(from: image).height)
                        .clipShape(.rect(topLeadingRadius: 12, topTrailingRadius: 12))
                        .padding(.top, valueFor(iOS: topMargin, macOS: 0, tvOS: topMargin, visionOS: topMargin))
                    }
            } else {
                VStack {
                    Image(systemName: "photo")
                        .font(.system(size: 96))
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
#if !os(macOS)
        .ignoresSafeArea(.container)
#endif
        .frame(width: minSize.width, height: minSize.height, alignment: .bottom)
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous))
        .animation(.bouncy, value: degrees)
        .onChange(of: itemId.wrappedValue, initial: true) {
            if fadeIn == true {
                fadeIn = false
                Task {
                    try await Task.sleep(for: .seconds(0.5))
                    withAnimation(.snappy(duration: 0.5)) { fadeIn = true }
                }
            } else {
                withAnimation(.snappy(duration: 0.5).delay(0.25)) { fadeIn = true }
            }
        }
    }
    
    private var minSize: CGSize {
        size.width < 10 || size.height < 10 ? CGSize(width: 320, height: 200) : size
    }

    private var imageWidth: CGFloat {
        ((degrees == 0 || degrees == 180) ? image?.size.width : image?.size.height) ?? 300
    }

    private var imageHeight: CGFloat {
        ((degrees == 0 || degrees == 180) ? image?.size.height : image?.size.width) ?? 250
    }

    private func containerSize(from image: AKImage) -> CGSize {
        let imageSize = CGSize(width: imageWidth, height: imageHeight)
        let wf = size.width / imageSize.width
        let wh = (size.height - valueFor(iOS: topMargin, macOS: 0, tvOS: topMargin, visionOS: topMargin)) / imageSize.height
        let f = min(wf, wh)
        let width = max(f * imageSize.width, 64)
        let height = max(f * imageSize.height, 64)
        return CGSize(width: width, height: height)
    }

    private func imageSize(from image: AKImage) -> CGSize {
        let imageSize = CGSize(width: imageWidth, height: imageHeight)
        let wf = size.width / imageSize.width
        let wh = (size.height - valueFor(iOS: topMargin, macOS: 0, tvOS: topMargin, visionOS: topMargin)) / imageSize.height
        let f = min(wf, wh)
        let width = max(f * imageSize.width, 64)
        let height = max(f * imageSize.height, 64)
    
        return CGSize(width: width, height: height)
    }
}
