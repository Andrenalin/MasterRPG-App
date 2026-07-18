// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI

/// Toggles the platform's 3D table presentation. visionOS keeps its independent
/// TabletopKit volume; iOS and macOS replace the 2D map canvas in place.
@MainActor
struct GameTableWindowButton: View {
#if os(visionOS)
    @Environment(ScenesManager.self) private var scenesManager
#endif
    @Environment(AppSettingsModel.self) private var appSettingsModel

    var body: some View {
        Button(action: toggleTable) {
            Label {
                Text(actionTitle)
            } icon: {
                Image(systemName: "cube.transparent")
            }
        }
        .labelStyle(.iconOnly)
        .selectedBorderedStype(isSelected: isPresented)
        .help(Text(actionTitle))
        .accessibilityLabel(Text(actionTitle))
    }

    private var isPresented: Bool {
#if os(visionOS)
        switch scenesManager.getSceneState(for: SceneId.gameTable) {
        case .opening, .opened:
            true
        case .closing, .closed:
            false
        }
#else
        appSettingsModel.showGameTableVolume
#endif
    }

    private var actionTitle: LocalizedStringResource {
#if os(visionOS)
        isPresented
            ? LocalizedStringResource("Hide Table Volume", bundle: .module)
            : LocalizedStringResource("Show Table Volume", bundle: .module)
#else
        isPresented
            ? LocalizedStringResource("Show 2D Map", bundle: .module)
            : LocalizedStringResource("Show 3D Table", bundle: .module)
#endif
    }

    private func toggleTable() {
        let shouldShow = !isPresented
        appSettingsModel.showGameTableVolume = shouldShow
#if os(visionOS)
        if shouldShow {
            scenesManager.openWindow(SceneId.gameTable)
        } else {
            scenesManager.dismissWindow(SceneId.gameTable)
        }
#endif
    }
}

#Preview(traits: .mockData) {
    GameTableWindowButton()
}
#endif
