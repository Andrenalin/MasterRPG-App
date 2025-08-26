//// @copyright André Trettin
//
//import CoreRPG
//import SwiftData
//import SwiftUI
//
//struct MainRowView: View {
//    let model: PdfDataModel
//
//    @Environment(CacheItemListModel.self) private var cacheModel
//    @Environment(PdfRootModel.self) private var root
//
//    var body: some View {
//        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheModel, thumbnail: {
//            OldThumbnailRowPhotoView(cacheController: root.cacheController, model: model)
//        })
//#if !os(tvOS)
//        .draggable(LinkData(itemId: model.id, module: PdfDataModel.typeId, name: model.name))
//#endif
//    }
//}
//
//#Preview(traits: .mockData) {
//    @Previewable @Query var models: [PdfDataModel]
//    
//    MainRowView(model: models[0])
//}
//
