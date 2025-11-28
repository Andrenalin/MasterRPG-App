// @copyright André Trettin

import SwiftUI
import MapRPG
import AndrenalinKit

struct OverlayToolBar: View {
    let root: GameRoot
    let playerController: PlayerController
    let isMaster: Bool
    
    var body: some View {
        switch playerController.gameModel.gameUpdateType {
        case .map:
            root.mapRoot.viewController.gameToolBarView(root: root.mapRoot, isMaster: isMaster)
        case .photo:
            //root.photoRoot.viewController.gameToolBarView()
            EmptyView()
        case .space, .table, .weather:
            EmptyView()
        default:
            EmptyView()
        }
    }
}

#Preview {
    OverlayToolBar(root: .preview, playerController: .preview, isMaster: true)
}
