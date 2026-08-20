// @copyright André Trettin

import SwiftUI
import MapRPG
import CoreRPG

struct OverlayToolBar: View {
    let root: GameRoot
    let playerController: PlayerController
    let isMaster: Bool

#if os(iOS) || os(macOS)
    @Environment(AppSettingsModel.self) private var appSettingsModel
#endif
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        switch playerController.gameModel.gameUpdateType {
        case .map:
#if os(iOS) || os(macOS)
            if appSettingsModel.showGameTableVolume {
                if root.mapRoot.gameControllable.gameModel.currentItemId == nil {
                    EmptyView()
                } else if let game = root.gameModel.gameTableModel {
                    GameTableToolbar(root: root, game: game)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(Text("Loading 3D Table", bundle: .module))
                }
            } else {
                HStack {
                    GameTableWindowButton(root: root, isMaster: isMaster)
                    root.mapRoot.viewController.gameToolBarView(root: root.mapRoot, isMaster: isMaster)
                }
            }
#else
            root.mapRoot.viewController.gameToolBarView(root: root.mapRoot, isMaster: isMaster)
#endif
        case .photo, .space, .table, .weather:
            EmptyView()
        default:
            EmptyView()
        }
    }
}

#Preview(traits: .mockData) {
    OverlayToolBar(root: .preview, playerController: .preview, isMaster: true)
}
