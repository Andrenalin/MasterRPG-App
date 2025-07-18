// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

public struct PhotoRootView: View {
    public init(modelContext: ModelContext, withoutNavigation: Bool) {
        self.withoutNavigation = withoutNavigation
        self._rootModel = State(wrappedValue: PhotoRootModel(modelContext: modelContext))
    }
    let withoutNavigation: Bool

    @State private var rootModel: PhotoRootModel
    @State private var selectionModel = ListSelectionModel<PhotoDataModel>()

    public var body: some View {
        RootView(module: .space, selectionModel: selectionModel, withoutNavigation: withoutNavigation, list: {
            ListView()
        }, detail: {
            if let selected = selectionModel.selectedItem {
                DetailView(model: selected)
            }
        })
        .environment(rootModel)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PhotoDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    ManagedNavigationStack {
        PhotoRootView(modelContext: modelContext, withoutNavigation: true)
            .environment(CacheItemListModel())
            .environment(SearchModel.preview)
            .environment(TabTitleModel())
            .environment(DeviceRotationModel())
    }
    .environment(PhotoRootModel(modelContext: modelContext))
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PhotoDataModel]
    @Previewable @Environment(\.modelContext) var modelContext

    PhotoRootView(modelContext: modelContext, withoutNavigation: false)
        .environment(CacheItemListModel())
        .environment(SearchModel.preview)
        .environment(TabTitleModel())
        .environment(DeviceRotationModel())
}

