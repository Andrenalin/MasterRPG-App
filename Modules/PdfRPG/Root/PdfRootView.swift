// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct PdfRootView: View {
    let withoutNavigation: Bool

    @Environment(PdfRootModel.self) private var root
    
    @SceneStorage("PdfRoute") private var route: PdfRoute?
    @SceneStorage("PdfDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("PdfListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        RootView(module: PdfDataModel.typeId, listController: root.listController, displayMode: $displayMode, listMode: $listMode, withoutNavigation: withoutNavigation, route: $route) {
            .detail($0)
        } detailId: {
            switch $0 {
            case .detail(let itemId): itemId
            }
        } list: {
            ListView()
        }
        .environment(root.listDisplayModel)
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
