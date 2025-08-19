// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let model: PdfDataModel
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(SearchModel.self) private var searchModel
    
    var body: some View {
        DetailView(model: model)
            .navigationDestination(for: DetailRoute.self) { route in
                route
                    .environment(cacheItemListModel)
                    .environment(searchModel)
            }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PdfDataModel]
    
    DetailRootView(model: models[0])
}
