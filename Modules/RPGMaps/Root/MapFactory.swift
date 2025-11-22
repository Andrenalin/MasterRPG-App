// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import AudioRPG
import RPGDie
import RPGPdfs
import PhotoRPG
import RPGTables
import RPGValues
import SwiftData
import SwiftUI

public enum MapFactory {
    @MainActor
    public static func root(container: ModelContainer, audioRoot: AudioRootModel, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, valueRoot: CharacterRootModel) -> MapRootModel {
        MapRootModel(container: container, audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, valueRoot: valueRoot)
    }
    
    @MainActor
    public static func rootView(for root: MapRootModel, tabId: UUID) -> some View {
        RootList(root: root, tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
    
    @MainActor
    public static func rootExtendedView(for root: MapRootModel, tabId: UUID) -> some View {
        RootExtendedList(editController: root.editController(type: .main), tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
            .navigationAutoReceive(MapRoute.self)
    }
    
    @MainActor @ViewBuilder public static func detailView(root: MapRootModel) -> some View {
        ExternalDetailView()
    }
}

struct ExternalDetailView: View {
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        if let itemId = root.listController(tabId: KnownRoutes.mainTabId).model.selectedItem?.model.itemId {
            MapRoute.detail(itemId)
                .environment(root.listController(tabId: KnownRoutes.mainTabId).model)
        } else {
            SplitContentUnavailable(module: .map)
        }
    }
}

public enum MapRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension MapRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
            case .detail(let id): "detail/\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
            case "detail": self = .detail(uuid)
            default: return nil
        }
    }
}

extension MapRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DetailRouteDestinationView(itemId: itemId)
        }
    }
}

struct DetailRouteDestinationView: View {
    let itemId: UUID
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        RootExtendedDetail(itemRowTreeModel: ItemRowTreeModel(itemId: itemId, typeId: .map), tabId: KnownRoutes.mainTabId)
        //DetailRootView(selectedId: itemId)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            //.environment(root.rootController)
    }
}
