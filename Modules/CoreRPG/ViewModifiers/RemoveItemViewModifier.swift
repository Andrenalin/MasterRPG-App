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

    func body(content: Content) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            content
                .padding(.top, 4)
                .padding(.leading, isLeading ? 12 : 0)
                .padding(.trailing, isLeading ? 0 : 12)
                .overlay(alignment: isLeading ? .topLeading : .topTrailing) {
                    Image(systemName: "minus.circle.fill")
                        .offset(x: isLeading ? -4 : 4, y: -8)
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
                print("Removed")
            }

        Text(verbatim: "Hello World")
            .removeItemImage(isLeading: true) {
                print("Removed")
            }
    }
}
