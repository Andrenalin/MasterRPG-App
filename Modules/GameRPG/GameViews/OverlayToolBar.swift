// @copyright André Trettin

import SwiftUI
import MapRPG
import CoreRPG

struct OverlayToolBar: View {
    let root: GameRoot
    let playerController: PlayerController
    let isMaster: Bool
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        switch playerController.gameModel.gameUpdateType {
        case .map:
            root.mapRoot.viewController.gameToolBarView(root: root.mapRoot, isMaster: isMaster)
        case .photo, .space, .table, .weather:
            EmptyView()
        default:
            EmptyView()
        }
    }
}

#Preview {
    OverlayToolBar(root: .preview, playerController: .preview, isMaster: true)
}
