// @copyright André Trettin

import SwiftUI

/// The show/hide button of a game overlay. The caller names the overlay: the title for the
/// state it would switch to, and the symbol, which is filled while the overlay is shown.
struct GameOverlayToggleButton: View {
    @Binding var isShown: Bool
    let symbol: String
    let title: Text

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button {
            withAnimation(accessibilityReduceMotion ? nil : .default) {
                isShown.toggle()
            }
        } label: {
            Label {
                title
            } icon: {
                Image(systemName: "\(symbol)\(isShown ? ".fill" : "")")
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
            }
            .labelStyle(.iconOnly)
        }
        .help(title)
    }
}
