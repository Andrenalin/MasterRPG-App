// @copyright André Trettin

import SwiftUI

extension View {
    /// The battle round screen brings its own header (`BattleRoundHeader`), so
    /// the navigation bar only costs height. macOS keeps its window toolbar,
    /// which hosts the turn actions and the inspector button.
    @ViewBuilder
    func battleHiddenNavigationBar() -> some View {
#if os(macOS)
        self
#else
        toolbar(.hidden, for: .navigationBar)
#endif
    }
}
