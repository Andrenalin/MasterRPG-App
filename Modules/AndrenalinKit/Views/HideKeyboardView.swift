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
    let enabled: Bool
    var focusedField: FocusState<Value?>.Binding
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            
            Button {
                withAnimation {
                    focusedField.wrappedValue = nil
                }
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .tint(.secondary)
            }
            .disabled(!enabled)
        }
    }
}


struct HideKeyboardView: View {
    let show: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            
            Button {
                hideKeyboard()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .tint(.secondary)
            }
            .opacity(show ? 1 : 0)
        }
    }
    
    @MainActor
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#endif
