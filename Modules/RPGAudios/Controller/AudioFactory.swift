// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftData
import SwiftUI

public enum AudioFactory {
    @MainActor
    public static func root(container: ModelContainer) -> AudioRoot {
        AudioRoot(container: container)
    }

    @MainActor
    public static func rootView(for root: AudioRoot, tabId: UUID) -> some View {
        RootList(root: root, tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }

    @MainActor
    public static func rootExtendedView(for root: AudioRoot, tabId: UUID) -> some View {
        RootExtendedList(editController: root.editController(type: .main), tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
            .navigationAutoReceive(AudioRoute.self)
    }

    @MainActor @ViewBuilder public static func detailView(root: AudioRoot) -> some View {
        ExternalDetailView()
    }
}

struct ExternalDetailView: View {
    @Environment(AudioRoot.self) private var root
    
    var body: some View {
        if let itemId = root.listController(tabId: KnownRoutes.mainTabId).model.selectedItem?.model.itemId {
            AudioRoute.detail(itemId)
                .environment(root.listController(tabId: KnownRoutes.mainTabId).model)
        } else {
            SplitContentUnavailable(module: .audio)
        }
    }
}


public enum AudioRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension AudioRoute: RawRepresentable {
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

extension AudioRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DetailRouteDestinationView(itemId: itemId)
        }
    }
}

struct DetailRouteDestinationView: View {
    let itemId: UUID
    @Environment(AudioRoot.self) private var root
    
    var body: some View {
        RootExtendedDetail(itemRowTreeModel: ItemRowTreeModel(itemId: itemId, typeId: .audio), tabId: KnownRoutes.mainTabId)
        //DetailRootView(selectedId: itemId)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
          //  .environment(root.rootController)
    }
}
