// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableSheet: View {
    let model: TableDataModel
    let showTopImage: Bool
    let dismissAction: (() -> Void)?

    @Environment(LinkRegisterController.self) private var linkController
    @Environment(TableRootModel.self) private var root

    @State private var sheetModel: SheetModel = SheetModel(id: UUID())

    var body: some View {
        TableRootSheet(linkController: linkController, model: sheetModel, showImage: showTopImage, dismissAction: dismissAction)
            .onChange(of: model, initial: true) {
                resetModels()
            }
    }

    func resetModels() {
        withAnimation {
            sheetModel = SheetController(itemController: root.itemController).sheet(for: model.itemId)
        }
    }
}
