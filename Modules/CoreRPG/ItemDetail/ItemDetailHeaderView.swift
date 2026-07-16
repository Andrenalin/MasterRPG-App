// @copyright André Trettin

import SwiftUI

struct ItemDetailHeaderView: View {
    let module: NetworkModules
    let model: any ItemDataAccessable
    let cacheItemListModel: CacheItemListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    
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
                .padding(.top, -64)
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
