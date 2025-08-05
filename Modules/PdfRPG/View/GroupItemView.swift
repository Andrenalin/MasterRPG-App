// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct GroupItemView: View {
    let model: PdfDataModel

    @Environment(\.modelContext) var modelContext
    @Environment(GroupItemSelectionModel.self) var selection
    @Environment(PdfRootModel.self) private var root

    var body: some View {
        PlainPhotoView(cacheController: root.cacheController, model: selectedModel, highResolution: false)
    }

    var selectedModel: PdfDataModel {
        item ?? model
    }

    var item: PdfDataModel? {
        guard let id = selection.selectedItem else { return nil }
        return PdfDataModel.model(modelContext: modelContext, id: id)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PdfDataModel]
    @Previewable @Environment(\.modelContext) var modelContext

    GroupItemView(model: models[0])
        .environment(GroupItemSelectionModel())
        .environment(CacheItemListModel())
}

