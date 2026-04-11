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
    
    @Environment(ScenesManager.self) private var scenesManager

    var body: some View {
        Button {
            withAnimation(.easeInOut) {
#if os(macOS) || os(visionOS)
                showType = if alwaysSet { valueType } else { (showType == valueType ? .none : valueType) }
#else
                if showType == valueType {
                    showType = .none
                }
                showType = valueType
#endif
            }
        } label: {
            Image(systemName: valueType.icon)
        }
        #if os(macOS) || os(visionOS)
        .selectedBorderedStype(isSelected: scenesManager.getSceneState(for: SceneId.sceneId(for: valueType)) == .opened)
        #else
        .selectedBorderedStype(isSelected: showType == valueType)
        #endif
    }
}
