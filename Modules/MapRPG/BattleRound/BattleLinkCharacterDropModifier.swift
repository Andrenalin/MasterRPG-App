// @copyright André Trettin

import CoreRPG
import SwiftUI

struct BattleLinkCharacterDropModifier: ViewModifier {
    let action: @MainActor ([LinkCharacterData], CGPoint) -> Bool

    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        content.dropDestination(for: LinkCharacterData.self, action: action)
#endif
    }
}

extension View {
    func battleLinkCharacterDropDestination(
        action: @MainActor @escaping ([LinkCharacterData], CGPoint) -> Bool
    ) -> some View {
        modifier(BattleLinkCharacterDropModifier(action: action))
    }
}
