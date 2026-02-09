// @copyright André Trettin

import SwiftUI

public extension View {
    func expandChildren(isActive: Bool = true, isExpanded: Bool, isSelected: Bool, action: @escaping () -> Void) -> some View {
        modifier(ExpandChildrenViewModifier(isActive: isActive, isExpanded: isExpanded, isSelected: isSelected, action: action))
    }
}

struct ExpandChildrenViewModifier: ViewModifier {
    let isActive: Bool
    let isExpanded: Bool
    let isSelected: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
#if os(macOS)
            Button {
                withAnimation(.easeInOut) { action() }
            } label: {
                Image(systemName: "chevron.right.circle")
                    .rotationEffect(isExpanded ? Angle(degrees: 90) : Angle(degrees: 0))
                    .imageScale(.large)
                    .foregroundStyle(Color.teal)
            }
            .buttonStyle(.plain)
            .opacity(isActive ? 1 : 0)
            .offset(x: 7, y: 4)
#else
            Button {
                withAnimation(.easeInOut) { action() }
            } label: {
                Image(systemName: "chevron.right.circle")
                    .rotationEffect(isExpanded ? Angle(degrees: 90) : Angle(degrees: 0))
                    .foregroundStyle(.tint)
            }
            .borderLessTVBottonStyle()
            .contentShape(Rectangle())
            .opacity(isActive ? 1 : 0)
#if os(visionOS)
            .offset(x: 20, y: 2)
#else
            .offset(x: 30, y: 2)
#endif
#endif
        }
    }
}
