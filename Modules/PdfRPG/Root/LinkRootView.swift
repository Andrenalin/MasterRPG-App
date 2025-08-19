// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct LinkRootView: View {
    let isInspector: Bool
    @Environment(PdfRootModel.self) private var root
    @Query(filter: #Predicate<PdfDataModel>{ $0.displayState == 0 }, sort: \PdfDataModel.name, animation: .smooth) private var items: [PdfDataModel]
    
    var body: some View {
        LinkItemListView(listController: root.listLinkController, parentModel: selectedModel, isInspector: isInspector) { itemId in
            if let model = root.itemController.modelSync(for: itemId) {
                MainRowView(model: model)
            }
        }
        .environment(DeviceRotationModel())
        .environment(CacheItemListModel())
        .onChange(of: items, initial: true) {
            withAnimation { root.listLinkController.update(items: items) }
        }
    }
    
    var selectedModel: PdfDataModel? {
        guard let itemId = root.currentSelectedItemId else { return nil }
        return root.itemController.modelSync(for: itemId)
    }
}

#Preview(traits: .mockData) {
    LinkRootView(isInspector: false)
}
