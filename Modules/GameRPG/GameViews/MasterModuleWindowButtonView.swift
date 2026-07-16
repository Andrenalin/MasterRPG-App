// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MasterModuleWindowButtonView: View {
    let valueType: NetworkModules

    var body: some View {
        GameWindowButtonView(
            title: valueType.title,
            systemImage: valueType.icon,
            tint: valueType.tint,
            sceneId: SceneId.sceneId(for: valueType)
        )
    }
}

#Preview(traits: .mockData) {
    MasterModuleWindowButtonView(valueType: .map)
}
