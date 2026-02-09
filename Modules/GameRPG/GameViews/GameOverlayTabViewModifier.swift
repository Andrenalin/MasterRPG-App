// @copyright André Trettin

import CoreRPG
import SwiftUI

extension NetworkModules: @retroactive AppRouter {}

extension View {
    func gameOverlayTabBarView<Tag: Hashable>(value: Tag) -> some View where Tag: Codable, Tag: AppRouter {
        modifier(GameOverlayTabViewModifier(value: value))
    }
}

struct GameOverlayTabViewModifier<Tag: Hashable>: ViewModifier where Tag: Codable, Tag: AppRouter {
    let value: Tag

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

struct GameToolBarButtonView: View {
    let valueType: NetworkModules
    var alwaysSet: Bool = false
    @Binding var showType: NetworkModules

    var body: some View {
        Button {
            withAnimation(.easeInOut) {
                showType = if alwaysSet { valueType } else { (showType == valueType ? .none : valueType) }
            }
        } label: {
            Image(systemName: valueType.icon)
        }
        .selectedBorderedStype(isSelected: showType == valueType)
    }
}
