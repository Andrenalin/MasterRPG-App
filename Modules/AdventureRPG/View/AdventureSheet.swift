// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

struct AdventureSheet: View {
    let model: AdventureModel
    let dismissAction: (() -> Void)?

    @Environment(AdventureRootModel.self) private var root

    @State private var sheetModel: SheetModel = SheetModel.empty

    var body: some View {
        TableRootSheet(root: root.rootController, model: sheetModel, dismissAction: dismissAction)
            .onChange(of: model, initial: true) {
                resetModels()
            }
    }

    func resetModels() {
        withAnimation {
            sheetModel = SheetController(itemController: root.itemController).sheet(for: model.id)
        }
    }
}
