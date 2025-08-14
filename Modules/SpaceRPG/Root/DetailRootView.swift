// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let model: SpaceDataModel
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListModel.self) private var listModel
    @Environment(SearchModel.self) private var searchModel
    
    var body: some View {
        DetailView(model: model)
            .navigationDestination(for: DetailRoute.self) { route in
                route
                    .environment(cacheItemListModel)
                    .environment(listModel.lastSubListModel())
                    .environment(searchModel)
            }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [SpaceDataModel]
    
    DetailRootView(model: models[0])
}
