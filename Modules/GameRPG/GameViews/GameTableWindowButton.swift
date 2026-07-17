// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI

/// Opens the platform's 3D table scene: a TabletopKit volume on visionOS and
/// a camera-based RealityView window on iOS and macOS.
@MainActor
struct GameTableWindowButton: View {
    @Environment(ScenesManager.self) private var scenesManager
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
        switch scenesManager.getSceneState(for: SceneId.gameTable) {
        case .opening, .opened:
            true
        case .closing, .closed:
            false
        }
    }

    private var actionTitle: LocalizedStringResource {
#if os(visionOS)
        isPresented
            ? LocalizedStringResource("Hide Table Volume", bundle: .module)
            : LocalizedStringResource("Show Table Volume", bundle: .module)
#else
        isPresented
            ? LocalizedStringResource("Hide 3D Table", bundle: .module)
            : LocalizedStringResource("Show 3D Table", bundle: .module)
#endif
    }

    private func toggleTable() {
        let shouldOpen = !isPresented
        appSettingsModel.showGameTableVolume = shouldOpen
        if shouldOpen {
            scenesManager.openWindow(SceneId.gameTable)
        } else {
            scenesManager.dismissWindow(SceneId.gameTable)
        }
    }
}

#Preview(traits: .mockData) {
    GameTableWindowButton()
}
#endif
