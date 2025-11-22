// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import RPGDie
import RPGPdfs
import PhotoRPG
import RPGTables
import SwiftData
import SwiftUI

public enum ValueFactory {
    @MainActor
    public static func root(container: ModelContainer, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel) -> CharacterRootModel {
        CharacterRootModel(container: container, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
    }
    
    @MainActor
    public static func rootView(for root: CharacterRootModel, tabId: UUID) -> some View {
        let _ = root.listController(tabId: tabId, config: true)
        return RootList(root: root, tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
    
    @MainActor
    public static func rootExtendedView(for root: CharacterRootModel, tabId: UUID) -> some View {
        RootExtendedList(editController: root.editController(type: .main), tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
            .navigationAutoReceive(CharacterRoute.self)
    }

    @MainActor @ViewBuilder public static func detailView(root: CharacterRootModel) -> some View {
        ExternalDetailView()
    }
}

struct ExternalDetailView: View {
    @Environment(CharacterRootModel.self) private var root
    
    var body: some View {
        if let itemId = root.listController(tabId: KnownRoutes.mainTabId).model.selectedItem?.model.itemId {
            CharacterRoute.detail(itemId)
                .environment(root.listController(tabId: KnownRoutes.mainTabId).model)
        } else {
            SplitContentUnavailable(module: .value)
        }
    }
}


public enum CharacterRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension CharacterRoute: RawRepresentable {
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

extension CharacterRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DetailRouteDestinationView(itemId: itemId)
        }
    }
}

struct DetailRouteDestinationView: View {
    let itemId: UUID
    @Environment(CharacterRootModel.self) private var root
    
    var body: some View {
        RootExtendedDetail(itemRowTreeModel: ItemRowTreeModel(itemId: itemId, typeId: .value), tabId: KnownRoutes.mainTabId)
        //DetailRootView(selectedId: itemId)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
          //  .environment(root.rootController)
    }
}
