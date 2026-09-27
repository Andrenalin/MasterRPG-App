// @copyright André Trettin

import SwiftUI

public extension View {
    func rowEditColor(backgroundColor: Color = .black) -> some View {
        modifier(ColoredEditRowViewModifier(backgroundColor: backgroundColor))
    }

}

struct ColoredEditRowViewModifier: ViewModifier {
    var backgroundColor: Color = .black

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(backgroundColor.opacity(0.7)))
            .rainbowDebug()
    }
}

