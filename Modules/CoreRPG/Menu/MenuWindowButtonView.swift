// @copyright André Trettin

import SwiftUI

public struct MenuWindowButtonView: View {
    public init(valueType: NetworkModules) {
        self.valueType = valueType
    }
    
    let valueType: NetworkModules
    
    @Environment(ScenesManager.self) private var scenesManager

    public var body: some View {
        Button {
            withAnimation(.easeInOut) {
                if scenesManager.getSceneState(for: SceneId.sceneId(for: valueType)) == .opened {
                    scenesManager.dismissWindow(SceneId.sceneId(for: valueType))
                } else {
                    scenesManager.openWindow(SceneId.sceneId(for: valueType))
                }
            }
        } label: {
            Image(systemName: valueType.icon)
        }
        #if !os(visionOS)
        .selectedBorderedStype(isSelected: scenesManager.getSceneState(for: SceneId.sceneId(for: valueType)) == .opened)
        #endif
    }
}
