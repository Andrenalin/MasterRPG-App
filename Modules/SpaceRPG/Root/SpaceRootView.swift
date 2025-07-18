// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

public struct SpaceRootView: View {
    public init(modelContext: ModelContext, withoutNavigation: Bool) {
        self.withoutNavigation = withoutNavigation
        self._rootModel = State(wrappedValue: SpaceRootModel(modelContext: modelContext))
    }
    let withoutNavigation: Bool
    
    @State private var rootModel: SpaceRootModel
    @State private var selectionModel = ListSelectionModel<SpaceDataModel>()

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

#Preview("Embed", traits: .mockData) {
    @Previewable @Query var models: [SpaceDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    ManagedNavigationStack {
        SpaceRootView(modelContext: modelContext, withoutNavigation: true)
            .environment(CacheItemListModel())
            .environment(SearchModel.preview)
            .environment(TabTitleModel())
            .environment(DeviceRotationModel())
    }
    .environment(SpaceRootModel(modelContext: modelContext))
}

#Preview("Split", traits: .mockData) {
    @Previewable @Query var models: [SpaceDataModel]
    @Previewable @Environment(\.modelContext) var modelContext

    SpaceRootView(modelContext: modelContext, withoutNavigation: false)
        .environment(CacheItemListModel())
        .environment(SearchModel.preview)
        .environment(TabTitleModel())
        .environment(DeviceRotationModel())
}

