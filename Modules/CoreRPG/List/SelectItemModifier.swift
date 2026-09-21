// @copyright André Trettin

import SwiftUI

public extension View {
    func selectListItem(isActive: Bool = true, hide: Bool = false, action: @escaping () -> Void, isSelected: @escaping () -> Bool) -> some View {
        modifier(SelectListItemViewModifier(isActive: isActive, hide: hide, action: action, isSelected: isSelected))
    }
}

struct SelectListItemViewModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let isActive: Bool
    let hide: Bool
    let action: () -> Void
    let isSelected: () -> Bool

    init(isActive: Bool, hide: Bool, action: @escaping () -> Void, isSelected: @escaping () -> Bool) {
        self.action = action
        self.hide = hide
        self.isSelected = isSelected
        self.isActive = isActive
    }

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            if isActive {
                Button {
                    action()
                } label: {
                    Image(systemName: isSelected() ? "checkmark.circle.fill" : "circle")
                        .font(.headline)
                        .imageScale(.large)
                        .foregroundStyle(.tint)
                        .opacity(hide ? 0 : 1)
                }
                .borderLessTVButtonStyle()
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, 8)
                .contentShape(.rect)
                .disabled(hide)
                .accessibilityHidden(hide)
                .accessibilityLabel(
                    isSelected()
                        ? Text("Deselect item", bundle: .module)
                        : Text("Select item", bundle: .module)
                )
            }

            content
        }
        .animation(accessibilityReduceMotion ? nil : .default, value: isActive)
    }
}
