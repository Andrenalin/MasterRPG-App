// @copyright André Trettin

import SwiftUI

struct OverlayStrokeStyle: ViewModifier {
    var cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    .linearGradient(
                        colors: [
                            .white.opacity(colorScheme == .dark ? 0.6 : 0.3),
                            .black.opacity(colorScheme == .dark ? 0.3 : 1),
                        ], startPoint: .top, endPoint: .bottom
                    )
                )
                .blendMode(.overlay)
        )
    }
}

public extension View {
    func strokeStyle(cornerRadius: CGFloat = 30) -> some View {
        modifier(OverlayStrokeStyle(cornerRadius: cornerRadius))
    }
}
