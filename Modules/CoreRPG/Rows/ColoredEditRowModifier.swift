// @copyright André Trettin

import SwiftUI

public extension View {
    func rowEditColor(backgroundColor: Color = .black) -> some View {
        modifier(ColoredEditRowViewModifier(backgroundColor: backgroundColor))
    }

}

struct ColoredEditRowViewModifier: ViewModifier {
    var backgroundColor: Color = .black

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// The text is always white, so the fill must stay dark enough under it: more opaque on the
    /// light surface, where the colour is blended with a light row, and solid with Increase Contrast.
    private var fillOpacity: Double {
        if colorSchemeContrast == .increased { return 1 }
        return colorScheme == .light ? 0.85 : 0.7
    }

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(backgroundColor.opacity(fillOpacity)))
    }
}

