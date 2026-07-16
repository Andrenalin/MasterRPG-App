// @copyright André Trettin

import SwiftUI

#if os(iOS)
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
            .frame(minWidth: 44, minHeight: 44)
            .disabled(!show)
            .opacity(show ? 1 : 0)
            .accessibilityHidden(!show)
            .accessibilityLabel(Text("Hide Keyboard", bundle: .module))
        }
    }

    @MainActor
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview("Keyboard control") {
    HideKeyboardView(show: true)
        .padding()
}
#endif
