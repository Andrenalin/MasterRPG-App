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
            let filtered = Self.filtered(newValue, includeDecimal: includeDecimal, decimalSeparator: Locale.current.decimalSeparator ?? ".")
            if filtered != newValue {
                text = filtered
            }
        }
    }

    /// Keeps digits, a minus only as the first character and, when decimals are allowed, the first
    /// decimal separator; everything else is dropped. See CODE_AUDIT_26 §5.78.
    static func filtered(_ input: String, includeDecimal: Bool, decimalSeparator: String) -> String {
        var result = ""
        var hasSeparator = false
        for character in input {
            if character.isASCII, character.isNumber {
                result.append(character)
            } else if character == "-", result.isEmpty {
                result.append(character)
            } else if includeDecimal, String(character) == decimalSeparator, !hasSeparator {
                hasSeparator = true
                result.append(character)
            }
        }
        return result
    }
}

public extension View {
    func numericInput(_ text: Binding<String>, includeDecimal: Bool = false) -> some View {
        modifier(NumericOnlyViewModifier(text: text, includeDecimal: includeDecimal))
    }
}
