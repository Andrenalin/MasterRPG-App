// © André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct UpdateDataModeVliew: View {
    internal init(model: AppModel) {
        self.model = model
        let predicate = #Predicate<ItemDataModel> { $0.displayState == 0 }
        let sort = SortDescriptor(\ItemDataModel.name, comparator: .localizedStandard)
        self._items = Query(filter: predicate, sort: [sort])
    }
    
    let model: AppModel

    @Query private var items: [ItemDataModel]
    
    var body: some View {
        let _ = Self._printChanges()
        
        Color.clear
            .onChange(of: items, initial: true) {
                model.update(items: items)
            }
    }
}
