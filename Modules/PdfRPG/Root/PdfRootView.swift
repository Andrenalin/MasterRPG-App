// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct PdfRootView: View {
    let withoutNavigation: Bool

    @Environment(PdfRootModel.self) private var root
    
    @SceneStorage("PdfRoute") private var route: PdfRoute?
    @SceneStorage("PdfDisplayModel") private var displayMode: ListModel.DisplayMode = .medium
    @SceneStorage("PdfListModel") private var listMode: ListModel.ListMode = .list

    var body: some View {
        RootView(module: PdfDataModel.typeId, listModel: root.listModel, displayMode: $displayMode, listMode: $listMode, withoutNavigation: withoutNavigation, route: $route) {
            .detail($0)
        } detailId: {
            switch $0 {
            case .detail(let itemId): itemId
            default: nil
            }
        } list: {
            ListView()
        }
        .environment(root.searchModel)
    }
}

#Preview("Small", traits: .mockData) {
    @Previewable @Query var models: [PdfDataModel]

    ManagedNavigationStack {
        PdfRootView(withoutNavigation: true)
    }
}


#Preview("Split", traits: .mockData) {
    @Previewable @Query var models: [PdfDataModel]

    PdfRootView(withoutNavigation: false)
}
