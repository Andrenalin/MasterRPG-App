// @copyright André Trettin

import SwiftUI

public extension View {
    func rowColorBackground(isSelected: Bool, backgroundColor: Color = .blue) -> some View {
        modifier(ColoredBackgroundRowViewModifier(isSelected: isSelected, backgroundColor: backgroundColor))
    }
}

struct ColoredBackgroundRowViewModifier: ViewModifier {
    let isSelected: Bool
    let backgroundColor: Color

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.primary)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.6)))
            .padding(4)
    }

    private var color: Color {
        isSelected ? (colorScheme == .dark ? .mint : .cyan) : backgroundColor
    }
}
