// @copyright André Trettin

import SwiftUI

public struct MenuWindowButtonView: View {
    public init(valueType: NetworkModules) {
        self.valueType = valueType
    }
    
    let valueType: NetworkModules
    
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    public var body: some View {
        Button {
            withAnimation(accessibilityReduceMotion ? nil : .easeInOut) {
                if scenesManager.getSceneState(for: SceneId.sceneId(for: valueType)) == .opened {
                    scenesManager.dismissWindow(SceneId.sceneId(for: valueType))
                } else {
                    scenesManager.openWindow(SceneId.sceneId(for: valueType))
                }
            }
        } label: {
            Image(systemName: valueType.icon)
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(Text(valueType.localizedTitle))
        #if !os(visionOS)
        .selectedBorderedStype(isSelected: scenesManager.getSceneState(for: SceneId.sceneId(for: valueType)) == .opened)
        #endif
    }
}

#Preview {
    MenuWindowButtonView(valueType: .adventure)
        .environment(ScenesManager())
}
