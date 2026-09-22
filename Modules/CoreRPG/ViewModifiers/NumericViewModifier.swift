// @copyright André Trettin

import SwiftUI

struct NumericOnlyViewModifier: ViewModifier {
    @Binding var text: String
    let includeDecimal: Bool

    func body(content: Content) -> some View {
        content
        #if !os(macOS)
        .keyboardType(includeDecimal ? .decimalPad : .numberPad)
        #endif
        // Two-parameter `onChange` fires only when `text` actually changes, unlike
        // `onReceive(Just(text))`, which re-fired on every body evaluation. See
        // CODE_AUDIT_17 §4.4.
        .onChange(of: text) { _, newValue in
            var numbers = "-0123456789"
            let decimalSeparator: String = Locale.current.decimalSeparator ?? "."
            if includeDecimal {
                numbers += decimalSeparator
            }
            if newValue.components(separatedBy: decimalSeparator).count - 1 > 1 {
                let filtered = newValue
                text = String(filtered.dropLast())
            } else {
                let filtered = newValue.filter { numbers.contains($0) }
                if filtered != newValue {
                    text = filtered
                }
            }
        }
    }
}

public extension View {
    func numericInput(_ text: Binding<String>, includeDecimal: Bool = false) -> some View {
        modifier(NumericOnlyViewModifier(text: text, includeDecimal: includeDecimal))
    }
}
