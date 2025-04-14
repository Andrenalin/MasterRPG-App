// @copyright André Trettin

import SwiftUI

struct ShowItemViewModifier: ViewModifier {
    let isActive: Bool
    let isShown: Bool
    let action: () -> Void

    init(isActive: Bool, isShown: Bool, action: @escaping () -> Void) {
        self.action = action
        self.isShown = isShown
        self.isActive = isActive
    }

    func body(content: Content) -> some View {
        HStack(spacing: 8) {
            content
                .contentShape(Rectangle())

            if isActive {
                Group {
                    if isShown {
                        showButton.buttonStyle(.borderedProminent)
                    } else {
                        showButton.buttonStyle(.bordered)
                    }
                }
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
                .animation(.default, value: isShown)
            }
        }
        .animation(.default, value: isActive)
    }

    var showButton: some View {
        Button(action: action) {
            Image(systemName: "eye\(isShown ? "" : ".slash")")
                .imageScale(.large)
        }
    }
}

public extension View {
    func showListItem(isActive: Bool = false, isShown: Bool, action: @escaping () -> Void) -> some View {
        modifier(ShowItemViewModifier(isActive: isActive, isShown: isShown, action: action))
    }
}

