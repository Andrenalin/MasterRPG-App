// @copyright André Trettin

import SwiftUI

public struct RotatePhotoView<Overlay: View>: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    public init(image: AKImage? = nil, degrees: Double, size: CGSize? = nil, useFullWidth: Bool = false, @ViewBuilder overlay: @escaping () -> Overlay) {
        self.image = image
        self.degrees = degrees
        self.size = size
        self.useFullWidth = useFullWidth
        overlayView = overlay
    }

    public init(image: AKImage? = nil, degrees: Double, size: CGSize? = nil, useFullWidth: Bool = false) where Overlay == EmptyView {
        self.image = image
        self.degrees = degrees
        self.size = size
        self.useFullWidth = useFullWidth
        overlayView = { EmptyView() }
    }

    let image: AKImage?
    let degrees: Double
    let size: CGSize?
    let useFullWidth: Bool
    let overlayView: () -> Overlay

    /// Only tracks live geometry when `size == nil` — see `effectiveWidth`, which is
    /// what `body` actually reads. See CODE_AUDIT_9 §5.5.
    @State private var imageWidth: CGFloat = 320

    /// The width driving layout: `size`'s width read live (not just seeded once at
    /// init, which went stale if the same view identity was later passed a
    /// different `size`) when the caller supplies one, otherwise the
    /// geometry-tracked `imageWidth`. See CODE_AUDIT_9 §5.5.
    private var effectiveWidth: CGFloat {
        size?.width ?? imageWidth
    }

    public var body: some View {
        VStack {
            if let image {
                Image(akImage: image)
                    .resizable()
                    .aspectRatio(contentMode: useFullWidth ? .fill : .fit)
                    .overlay(alignment: .topLeading) {
                        overlayView()
                            .scaleEffect(scale(for: effectiveWidth) ?? 1)
                    }
                    .rotationEffect(Angle(degrees: degrees))
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 96, maxHeight: 96)
                    .accessibilityLabel(Text("Photo", bundle: .module))
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
        .frame(height: height(for: effectiveWidth) ?? 220.0)
        .animation(nil, value: effectiveWidth)
        .animation(accessibilityReduceMotion ? nil : .bouncy, value: degrees)
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
