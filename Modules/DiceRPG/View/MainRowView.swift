//// @copyright André Trettin
//
//import CoreRPG
//import SwiftData
//import SwiftUI
//
//struct MainRowView: View {
//    let model: DiceDataModel
//
//    @Environment(CacheItemListModel.self) private var cacheModel
//
//    var body: some View {
//        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheModel, isSelected: false, thumbnail: {
//            if let die = model.config.dice.first {
//                ThumbnailDice(die: die)
//            }
//        })
//#if !os(tvOS)
//        .draggable(LinkData(itemId: model.id, module: DiceDataModel.typeId, name: model.name))
//#endif
//    }
//}
//
//#Preview(traits: .mockData) {
//    @Previewable @Query var models: [DiceDataModel]
//    
//    MainRowView(model: models[0])
//}
