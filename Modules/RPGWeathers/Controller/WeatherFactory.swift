// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import RPGPhotos
import SwiftData
import SwiftUI

public enum WeatherFactory {
    @MainActor
    public static func root(container: ModelContainer, photoRoot: PhotoRoot) -> WeatherRoot {
        WeatherRoot(container: container, photoRoot: photoRoot)
    }

    @MainActor
    public static func rootView(for root: WeatherRoot, tabId: UUID) -> some View {
        RootList(root: root, tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
    
    @MainActor
    public static func rootExtendedView(for root: WeatherRoot, tabId: UUID) -> some View {
        RootExtendedList(editController: root.editController(type: .main), tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }

    @MainActor @ViewBuilder public static func detailView(root: WeatherRoot) -> some View {
        ExternalDetailView()
    }
}

struct ExternalDetailView: View {
    @Environment(WeatherRoot.self) private var root
    
    var body: some View {
        if let itemId = root.listController(tabId: KnownRoutes.mainTabId).model.selectedItem?.model.itemId {
            WeatherRoute.detail(itemId)
                .environment(root.listController(tabId: KnownRoutes.mainTabId).model)
        } else {
            SplitContentUnavailable(module: .weather)
        }
    }
}

public enum WeatherRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension WeatherRoute: RawRepresentable {
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

extension WeatherRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DetailRouteDestinationView(itemId: itemId)
        }
    }
}

struct DetailRouteDestinationView: View {
    let itemId: UUID
    @Environment(WeatherRoot.self) private var root
    
    var body: some View {
        RootExtendedDetail(itemRowTreeModel: ItemRowTreeModel(itemId: itemId, typeId: .weather), tabId: KnownRoutes.mainTabId)
        //DetailRootView(selectedId: itemId)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            //.environment(root.rootController)
    }
}
