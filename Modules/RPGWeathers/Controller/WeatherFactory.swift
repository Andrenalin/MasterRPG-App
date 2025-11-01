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
}

public enum WeatherRoute: Hashable, Codable {
    case detail(ItemRowTreeModel?, UUID)
}

extension WeatherRoute: NavigationDestination {
    public var body: some View {
        switch self {
            case .detail(let itemRowTreeModel, let tabId):
                if let itemRowTreeModel {
                    RootExtendedDetail(itemRowTreeModel: itemRowTreeModel, tabId: tabId)
                } else {
                    SplitContentUnavailable(module: .weather)
                }
        }
    }
}
