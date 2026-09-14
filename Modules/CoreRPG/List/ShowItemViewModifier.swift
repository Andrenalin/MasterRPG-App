// @copyright André Trettin

import SwiftUI

struct ShowItemViewModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

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
                        ShowItemViewModifierShowButtonView(isShown: isShown, action: action).buttonStyle(.borderedProminent)
                    } else {
                        ShowItemViewModifierShowButtonView(isShown: isShown, action: action).buttonStyle(.bordered)
                    }
                }
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
                .animation(accessibilityReduceMotion ? nil : .default, value: isShown)
            }
        }
        .animation(accessibilityReduceMotion ? nil : .default, value: isActive)
    }
}

public extension View {
    func showListItem(isActive: Bool = false, isShown: Bool, action: @escaping () -> Void) -> some View {
        modifier(ShowItemViewModifier(isActive: isActive, isShown: isShown, action: action))
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct ShowItemViewModifierShowButtonView: View {
    let isShown: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "eye\(isShown ? "" : ".slash")")
                .imageScale(.large)
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(
            isShown
                ? Text("Hide", bundle: .module)
                : Text("Show", bundle: .module)
        )
    }
}
