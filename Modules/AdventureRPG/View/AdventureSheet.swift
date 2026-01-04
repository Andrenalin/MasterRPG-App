// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AdventureSheet: View {
    let model: AdventureModel
    let dismissAction: (() -> Void)?

    @Environment(AdventureRootModel.self) private var root

    var body: some View {
        TableRootSheet(root: root.rootController, itemId: model.id, module: root.config.module, dismissAction: dismissAction)
    }
}
