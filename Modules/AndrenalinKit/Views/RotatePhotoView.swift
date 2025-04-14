// @copyright André Trettin

import SwiftUI

public struct RotatePhotoView<Overlay: View>: View {
    public init(image: AKImage? = nil, degrees: Double, size: CGSize? = nil, useFullWidth: Bool = false, @ViewBuilder overlay: @escaping () -> Overlay) {
        self.image = image
        self.degrees = degrees
        self.size = size
        self.useFullWidth = useFullWidth
        if let width = size?.width {
            self._imageWidth = State(wrappedValue: width)
        } else {
            self._imageWidth = State(wrappedValue: 320)
        }
        overlayView = overlay
    }
    
    public init(image: AKImage? = nil, degrees: Double, size: CGSize? = nil, useFullWidth: Bool = false) where Overlay == EmptyView {
        self.image = image
        self.degrees = degrees
        self.size = size
        self.useFullWidth = useFullWidth
        if let width = size?.width {
            self._imageWidth = State(wrappedValue: width)
        } else {
            self._imageWidth = State(wrappedValue: 320)
        }
        overlayView = { EmptyView() }
    }
    
    let image: AKImage?
    let degrees: Double
    let size: CGSize?
    let useFullWidth: Bool
    let overlayView: () -> Overlay
    
    @State private var imageWidth: CGFloat
    
    public var body: some View {
        VStack {
            if let image {
                Image(akImage: image)
                    .resizable()
                    .aspectRatio(contentMode: useFullWidth ? .fill : .fit)
                    .overlay(alignment: .topLeading) {
                        overlayView()
                            .scaleEffect(scale(for: imageWidth) ?? 1)
                    }
                    .rotationEffect(Angle(degrees: degrees))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 96))
            }
        }
        .frame(maxWidth: .infinity)        
        .applyIf(size == nil) { content in
            content
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { 
                    if $0 < imageWidth - 1 || $0 > imageWidth + 1 {
                        imageWidth = $0.rounded(.toNearestOrAwayFromZero)
                    }
                }
        }
        .applyIf(size != nil) { content in
            content.frame(width: size?.width ?? 320)
        }
        .frame(height: height(for: imageWidth) ?? 220.0)
        .animation(nil, value: imageWidth)
        .animation(.bouncy, value: degrees)
    }
    
    private func height(for width: CGFloat) -> CGFloat? {
        if let size {
            return size.height
        }
        guard let image else { return nil }
        let factor = width / image.fixedSize.width
        if degrees == 0 || degrees == 180 {
            return (image.fixedSize.height * factor).rounded(.toNearestOrAwayFromZero)
        } else {
            return (image.fixedSize.width * factor).rounded(.toNearestOrAwayFromZero)
        }
    }
    
    private func scale(for width: CGFloat) -> CGFloat? {
        guard let image else { return nil }
        return width / image.fixedSize.width
    }
}

#Preview {
    RotatePhotoView(image: nil, degrees: 0, size: CGSize(width: 40, height: 300)) {
        Image(systemName: "square.and.arrow.up")
    }
}
