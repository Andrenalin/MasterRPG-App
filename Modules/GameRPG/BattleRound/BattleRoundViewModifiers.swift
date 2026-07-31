// @copyright André Trettin

import SwiftUI

extension View {
    @ViewBuilder
    func battleInitiativeTextFieldStyle() -> some View {
#if os(tvOS)
        self
#else
        textFieldStyle(.roundedBorder)
#endif
    }

    @ViewBuilder
    func battleInlineNavigationTitle() -> some View {
#if os(iOS) || os(visionOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }

    @ViewBuilder
    func battleNumberKeyboard() -> some View {
#if os(iOS)
        keyboardType(.numberPad)
#else
        self
#endif
    }
}
