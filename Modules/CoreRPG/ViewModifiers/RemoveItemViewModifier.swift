// @copyright André Trettin

import SwiftUI

public extension View {
    func removeItemImage(isLeading: Bool = false, _ action: @escaping () async -> Void) -> some View {
        modifier(RemoveItemViewModifier(isLeading: isLeading, action: action))
    }
}

struct RemoveItemViewModifier: ViewModifier {
    let isLeading: Bool
    let action: () async -> Void

    /// The room left for the badge, scaled with Dynamic Type like the badge symbol itself; the
    /// fixed points kept a large badge overlapping the content. See CODE_AUDIT_Folder §8.4.
    @ScaledMetric(relativeTo: .body) private var badgeInset: CGFloat = 12

    func body(content: Content) -> some View {
        Button {
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
