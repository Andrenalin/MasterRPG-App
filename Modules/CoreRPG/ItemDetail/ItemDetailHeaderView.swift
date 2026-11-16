// @copyright André Trettin

import SwiftUI

struct ItemDetailHeaderView: View {
    let module: NetworkModules
    let model: any ItemDataAccessible
    let cacheItemListModel: CacheItemListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel

    /// How far the header is pulled up into the title area; scales with Dynamic Type.
    @ScaledMetric private var titleOverlap: CGFloat = 64

    var body: some View {
        ZStack(alignment: .bottom) {
            ItemDetailOverlayView(
                model: model,
                cacheItemListModel: cacheItemListModel,
                listDisplayModel: listDisplayModel,
                searchModel: searchModel
            )
            .padding()
        }
        .overlay(alignment: .top) {
            navigationHeader
                .font(.title)
                .padding(.top, -titleOverlap)
        }
    }
    
    private var navigationHeader: Text {
        Text("\(Image(systemName: module.icon)) \(module.title)", bundle: .module)
    }
}

#Preview("Item Detail Header") {
    ItemDetailHeaderView(
        module: .none,
        model: FakeItemModel.empty,
        cacheItemListModel: CacheItemListModel(),
        listDisplayModel: ListDisplayModel(),
        searchModel: FakeSearchController.fake.searchModel
    )
    .padding()
}
