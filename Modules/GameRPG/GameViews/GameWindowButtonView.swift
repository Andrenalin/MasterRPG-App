// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameWindowButtonView: View {
    let title: String
    let systemImage: String
    let module: NetworkModules
    let sceneId: SceneId

    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        let isWindowPresented = scenesManager.getSceneState(for: sceneId).isPresentedInGameMenu

        Button {
            toggleWindow(sceneId, isPresented: isWindowPresented)
        } label: {
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: systemImage)
            }
        }
        .labelStyle(.iconOnly)
        .imageScale(.large)
        .padding(8)
        .contentShape(.circle)
        .modifier(
            GameWindowButtonAppearance(
                module: module,
                isWindowPresented: isWindowPresented
            )
        )
        .help(title)
        .accessibilityValue(
            Text(isWindowPresented ? "Window open" : "Window closed", bundle: .module)
        )
    }

    private func toggleWindow(_ sceneId: SceneId, isPresented: Bool) {
        withAnimation(accessibilityReduceMotion ? nil : .easeInOut) {
            if isPresented {
                scenesManager.dismissWindow(sceneId)
            } else {
                scenesManager.openWindow(sceneId)
            }
        }
    }
}

#Preview {
    GameWindowButtonView(
        title: NetworkModules.map.title,
        systemImage: NetworkModules.map.icon,
        module: .map,
        sceneId: SceneId.sceneId(for: .map)
    )
    .environment(ScenesManager())
}
