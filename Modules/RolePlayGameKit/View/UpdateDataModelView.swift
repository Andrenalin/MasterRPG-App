// © André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct UpdateDataModeVliew: View {
    let model: AppModel

    @Query(filter: #Predicate<ItemDataModel>{ $0.displayState == 0 }, sort: \ItemDataModel.name) private var items: [ItemDataModel]
    
    var body: some View {
        let _ = Self._printChanges()
        
        Color.clear
            .onChange(of: items, initial: true) {
                model.update(items: items)
            }
    }
}
