// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftData
import SwiftUI

public enum PhotoFactory {
    @MainActor
    public static func root(container: ModelContainer) -> PhotoRoot {
        PhotoRoot(container: container)
    }

    @MainActor
    public static func rootView(for root: PhotoRoot, tabId: UUID) -> some View {
        RootList(root: root, tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
    
    @MainActor
    public static func rootExtendedView(for root: PhotoRoot, tabId: UUID) -> some View {
        RootExtendedList(editController: root.editController(type: .main), tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
            .navigationAutoReceive(PhotoRoute.self)
    }
    @MainActor @ViewBuilder public static func detailView(root: PhotoRoot) -> some View {
        ExternalDetailView()
    }
}

struct ExternalDetailView: View {
    @Environment(PhotoRoot.self) private var root
    
    var body: some View {
        if let itemId = root.listController(tabId: KnownRoutes.mainTabId).model.selectedItem?.model.itemId {
            PhotoRoute.detail(itemId)
                .environment(root.listController(tabId: KnownRoutes.mainTabId).model)
        } else {
            SplitContentUnavailable(module: .photo)
        }
    }
}

public enum PhotoRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension PhotoRoute: RawRepresentable {
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

extension PhotoRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DetailRouteDestinationView(itemId: itemId)
        }
    }
}

struct DetailRouteDestinationView: View {
    let itemId: UUID
    @Environment(PhotoRoot.self) private var root
    
    var body: some View {
        //DetailRootView(selectedId: itemId)
        RootExtendedDetail(itemRowTreeModel: ItemRowTreeModel(itemId: itemId, typeId: .photo), tabId: KnownRoutes.mainTabId)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
//            .environment(root.rootController)
    }
}
