// @copyright André Trettin

import Combine
import SwiftUI

struct NumericOnlyViewModifier: ViewModifier {
    @Binding var text: String
    let includeDecimal: Bool

    func body(content: Content) -> some View {
        content
        #if !os(macOS)
        .keyboardType(includeDecimal ? .decimalPad : .numberPad)
        #endif
        .onReceive(Just(text)) { newValue in
            var numbers = "-0123456789"
            let decimnalSeparator: String = Locale.current.decimalSeparator ?? "."
            if includeDecimal {
                numbers += decimnalSeparator
            }
            if newValue.components(separatedBy: decimnalSeparator).count - 1 > 1 {
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
