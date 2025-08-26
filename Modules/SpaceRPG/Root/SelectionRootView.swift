//// @copyright André Trettin
//
//import CoreExternalRPG
//import CoreRPG
//import SwiftData
//import SwiftUI
//import UniformTypeIdentifiers
//
//struct SelectionRootView: View {
//    @Environment(\.modelContext) private var modelContext
//    @State private var cacheItemListModel = CacheItemListModel()
//
//    var body: some View {
//        NavigationStack {
//            SelectionListView()
//        }
//        .environment(cacheItemListModel)
//    }
//}
//
//struct SelectionListView: View {
//    @Environment(\.modelContext) private var modelContext
//    @Environment(SpaceRootModel.self) private var root
//
//    @Query(filter: #Predicate<SpaceDataModel>{ $0.displayState == 0 }, sort: \SpaceDataModel.name, animation: .smooth) private var items: [SpaceDataModel]
//    
//    var body: some View {
//        ItemSelectionListView(listController: root.listLinkController, parentModel: nil, module: SpaceDataModel.typeId) { id in
//            SpaceRoute.detail(id)
//        } row: { itemId in
//            if let model = root.itemController.modelSync(for: itemId) {
//                MainRowView(model: model)
//            }
//        }
//    }
//}
//
//#Preview(traits: .mockData) {
//    @Previewable @Query var models: [SpaceDataModel]
//    
//    ManagedNavigationStack {
//        SelectionRootView()
//    }
//}
