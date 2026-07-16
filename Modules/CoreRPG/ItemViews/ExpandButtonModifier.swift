// @copyright André Trettin

import SwiftUI

public extension View {
    func expandChildren(isActive: Bool = true, isExpanded: Bool, isSelected: Bool, action: @escaping () -> Void) -> some View {
        modifier(ExpandChildrenViewModifier(isActive: isActive, isExpanded: isExpanded, isSelected: isSelected, action: action))
    }
}

struct ExpandChildrenViewModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let isActive: Bool
    let isExpanded: Bool
    let isSelected: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
#if os(macOS)
            Button {
                withAnimation(accessibilityReduceMotion ? nil : .easeInOut) { action() }
            } label: {
                Image(systemName: "chevron.right.circle")
                    .rotationEffect(isExpanded ? Angle(degrees: 90) : Angle(degrees: 0))
                    .imageScale(.large)
                    .foregroundStyle(Color.teal)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(!isActive)
            .opacity(isActive ? 1 : 0)
            .accessibilityHidden(!isActive)
            .accessibilityLabel(
                isExpanded
                    ? Text("Collapse children", bundle: .module)
                    : Text("Expand children", bundle: .module)
            )
            .offset(x: 7, y: 4)
#else
            Button {
                withAnimation(accessibilityReduceMotion ? nil : .easeInOut) { action() }
            } label: {
                Image(systemName: "chevron.right.circle")
                    .rotationEffect(isExpanded ? Angle(degrees: 90) : Angle(degrees: 0))
                    .foregroundStyle(.tint)
            }
            .borderLessTVBottonStyle()
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .disabled(!isActive)
            .opacity(isActive ? 1 : 0)
            .accessibilityHidden(!isActive)
            .accessibilityLabel(
                isExpanded
                    ? Text("Collapse children", bundle: .module)
                    : Text("Expand children", bundle: .module)
            )
#if os(visionOS)
            .offset(x: 20, y: 2)
#else
            .offset(x: 30, y: 2)
#endif
#endif
        }
    }
}
