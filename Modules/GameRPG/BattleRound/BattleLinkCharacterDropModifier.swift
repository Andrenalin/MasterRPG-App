// @copyright André Trettin

import CoreRPG
import SwiftUI

/// A drop target for a Character or one of its values, dragged from the
/// Character list. While a drag hovers over it the target is outlined, so the
/// small "Ini:" / "HP:" labels and the avatar show where a drop will land.
struct BattleLinkCharacterDropModifier<Outline: InsettableShape>: ViewModifier {
    let outline: Outline
    let action: @MainActor ([LinkCharacterData], CGPoint) -> Bool

    @State private var isTargeted = false

    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        content
            .dropDestination(for: LinkCharacterData.self, action: action) { isTargeted in
                self.isTargeted = isTargeted
            }
            .overlay {
                if isTargeted {
                    outline
                        .strokeBorder(.tint, lineWidth: 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
#endif
    }
}

extension View {
    func battleLinkCharacterDropDestination(
        action: @MainActor @escaping ([LinkCharacterData], CGPoint) -> Bool
    ) -> some View {
        modifier(
            BattleLinkCharacterDropModifier(
                outline: .rect(cornerRadius: BattleRoundSpacing.compact),
                action: action
            )
        )
    }

    func battleLinkCharacterDropDestination(
        outline: some InsettableShape,
        action: @MainActor @escaping ([LinkCharacterData], CGPoint) -> Bool
    ) -> some View {
        modifier(BattleLinkCharacterDropModifier(outline: outline, action: action))
    }
}
