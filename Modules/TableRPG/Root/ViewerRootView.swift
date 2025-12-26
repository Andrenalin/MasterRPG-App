// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: TableModel
    var windowMode: Bool = false
    var dismissAction: (() -> Void)? = nil

    @Environment(TableRootModel.self) private var root

    @State private var sheetModel: SheetModel = SheetModel.empty

    var body: some View {
        TableRootSheet(root: root.rootController, model: sheetModel, windowMode: windowMode, dismissAction: dismissAction)
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

#Preview(traits: .mockData) {
    @Previewable @Environment(TableRootModel.self) var root
    ManagedNavigationStack {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? TableModel.previewId), dismissAction: nil)
    }
}
