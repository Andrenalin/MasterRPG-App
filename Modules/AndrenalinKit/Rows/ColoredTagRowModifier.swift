// @copyright André Trettin

import SwiftUI

public extension View {
    func rowColoredTag(backgroundColor: Color = .blue) -> some View {
        modifier(ColoredTagRowViewModifier(backgroundColor: backgroundColor))
    }
}

struct ColoredTagRowViewModifier: ViewModifier {
    var backgroundColor: Color = .blue

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.primary)
            .font(.caption2)
            .bold()
            .textCase(.uppercase)
            .lineLimit(1)
#if !os(tvOS)
            .textSelection(.enabled)
#endif
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 4).fill(backgroundColor.opacity(0.8)))
    }
}
