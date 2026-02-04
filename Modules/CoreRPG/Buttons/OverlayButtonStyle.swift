// @copyright André Trettin

import SwiftUI

public struct ImageOverlayButtonStyle: ButtonStyle {
    public init() {}
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.largeTitle)
            .padding()
#if os(visionOS)
            .glassBackgroundEffect()
            .hoverEffect(.highlight, isEnabled: true)
#else
            .background(.ultraThinMaterial)
            .shadow(radius: 10)
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0 : 0.2), radius: 10, x: 10, y: 10)
#endif
    }
}

public extension ButtonStyle where Self == ImageOverlayButtonStyle {
    static var imageOverlay: ImageOverlayButtonStyle {
        ImageOverlayButtonStyle()
    }
}

#Preview {
    Button {} label: {
        Image(systemName: "skew")
    }
    .buttonStyle(.imageOverlay)
    .borderLessTVBottonStyle()
    .tint(Color.accentColor)
    .accentColor(Color.teal)
}
