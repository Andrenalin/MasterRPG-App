// @copyright André Trettin

import SwiftUI

extension View {
    func sheetBorderColor(level: Int) -> some View {
        self.modifier(SheetBorderViewModifier(level: level))
    }
}

struct SheetBorderViewModifier: ViewModifier {
    let level: Int
    
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 8).fill(rowColor(for: level))
            }
    }
    
    func rowColor(for level: Int) -> Color {
        if level.isMultiple(of: 2) {
            return .secondary.opacity(0.2)
        } else {
            return .secondary.opacity(0.4)
        }
    }
}
