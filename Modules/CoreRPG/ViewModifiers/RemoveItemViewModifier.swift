// @copyright André Trettin

import SwiftUI

public extension View {
    /// - Parameter accessibilityName: what is removed ("Dungeon"); VoiceOver then announces
    ///   "Remove Dungeon" instead of the bare content. See CODE_AUDIT_26 §8.1.
    func removeItemImage(isLeading: Bool = false, accessibilityName: String? = nil, _ action: @escaping () async -> Void) -> some View {
        modifier(RemoveItemViewModifier(isLeading: isLeading, accessibilityName: accessibilityName, action: action))
    }
}

struct RemoveItemViewModifier: ViewModifier {
    let isLeading: Bool
    let accessibilityName: String?
    let action: () async -> Void

    /// The room left for the badge, scaled with Dynamic Type like the badge symbol itself; the
    /// fixed points kept a large badge overlapping the content. See CODE_AUDIT_Folder §8.4.
    @ScaledMetric(relativeTo: .body) private var badgeInset: CGFloat = 12

    func body(content: Content) -> some View {
        Button(role: .destructive) {
            Task {
                await action()
            }
        } label: {
            content
                .padding(.top, badgeInset / 3)
                .padding(.leading, isLeading ? badgeInset : 0)
                .padding(.trailing, isLeading ? 0 : badgeInset)
                .overlay(alignment: isLeading ? .topLeading : .topTrailing) {
                    Image(systemName: "minus.circle.fill")
                        .offset(x: (isLeading ? -badgeInset : badgeInset) / 3, y: -badgeInset * 2 / 3)
                        .foregroundStyle(.white, .red)
                        .accessibilityHidden(true)
                }
        }
        .buttonStyle(.plain)
        .applyIf(accessibilityName != nil) {
            $0.accessibilityLabel(Text("Remove \(accessibilityName ?? "")", bundle: .module))
        }
        .accessibilityHint(Text("Removes it from the list", bundle: .module))
    }
}

#Preview {
    VStack {
        Text(verbatim: "Hello World")
            .removeItemImage {
            }

        Text(verbatim: "Hello World")
            .removeItemImage(isLeading: true) {
            }
    }
}
