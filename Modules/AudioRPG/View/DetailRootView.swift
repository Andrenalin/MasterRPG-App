// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let model: AudioDataModel

    @Environment(AudioRootModel.self) private var root
    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListModel.self) private var listModel
    @Environment(SearchModel.self) private var searchModel
    
    var body: some View {
        DetailView(model: model)
        .navigationDestination(for: AudioDetailRoute.self) { route in
            route
                .environment(listModel.lastSubListModel())
                .environment(searchModel)
                .environment(cacheItemListModel)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]

    DetailRootView(model: models[0])
}
