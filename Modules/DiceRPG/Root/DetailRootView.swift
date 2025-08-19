// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let model: DiceDataModel
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListDisplayModel.self) private var listDisplayModel
    @Environment(SearchModel.self) private var searchModel

    var body: some View {
        DetailView(model: model)
            .navigationDestination(for: DetailRoute.self) { route in
                route
                    .environment(cacheItemListModel)
                    .environment(listDisplayModel)
                    .environment(searchModel)
            }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [DiceDataModel]
    
    DetailRootView(model: models[0])
}
