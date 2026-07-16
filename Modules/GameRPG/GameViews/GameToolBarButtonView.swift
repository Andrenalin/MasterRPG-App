// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameToolBarButtonView: View {
    let valueType: NetworkModules
    var alwaysSet = false
    @Binding var showType: NetworkModules

    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button {
            withAnimation(accessibilityReduceMotion ? nil : .easeInOut) {
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
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(Text(valueType.localizedTitle))
#if os(macOS) || os(visionOS)
        .selectedBorderedStype(
            isSelected: scenesManager.getSceneState(for: SceneId.sceneId(for: valueType)) == .opened
        )
#else
        .selectedBorderedStype(isSelected: showType == valueType)
#endif
    }
}

#Preview {
    @Previewable @State var showType = NetworkModules.none
    GameToolBarButtonView(valueType: .adventure, showType: $showType)
        .environment(ScenesManager())
}
