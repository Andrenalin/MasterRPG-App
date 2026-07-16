// @copyright André Trettin

import SwiftUI

public extension View {
    func hideKeyboardView(show: Bool = true) -> some View {
#if os(iOS)
        HStack(alignment: .top, spacing: 0) {
            self
            
            HideKeyboardView(show: show)
                .fixedSize()
        }
#else
        self
#endif
    }
    
    func hideKeyboardView<Value: Hashable>(enabled: Bool, focusedField: FocusState<Value?>.Binding) -> some View {
#if os(iOS)
        VStack(alignment: .leading, spacing: 8) {
            HideKeyboardFocusView(enabled: enabled, focusedField: focusedField)
            
            self
        }
#else
        self
#endif
    }
}

#if os(iOS)

struct HideKeyboardFocusView<Value: Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let enabled: Bool
    var focusedField: FocusState<Value?>.Binding
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            
            Button {
                withAnimation(accessibilityReduceMotion ? nil : .default) {
                    focusedField.wrappedValue = nil
                }
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .tint(.secondary)
            }
            .frame(minWidth: 44, minHeight: 44)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0)
            .accessibilityHidden(!enabled)
            .accessibilityLabel(Text("Hide Keyboard", bundle: .module))
        }
    }
}

#Preview("Focus control") {
    @Previewable @FocusState var focus: Int?
    HideKeyboardFocusView(enabled: true, focusedField: $focus)
        .padding()
}
#endif
