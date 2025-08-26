// @copyright André Trettin

import SwiftUI

public extension View {
    func selectListItem(isActive: Bool = true, hide: Bool = false, action: @escaping () -> Void, isSelected: @escaping () -> Bool) -> some View {
        modifier(SelectListItemViewModifier(isActive: isActive, hide: hide, action: action, isSelected: isSelected))
    }
}

struct SelectListItemViewModifier: ViewModifier {
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
                .borderLessTVBottonStyle()
                .padding(.horizontal, 8)
                .contentShape(.rect)
                #if os(macOS)
                    .focusable(false)
                #endif
                    .disabled(hide)
            }

            content
        }
        .animation(.default, value: isActive)
    }
}
