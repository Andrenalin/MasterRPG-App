// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import RPGAudios
import RPGDie
import RPGPdfs
import RPGPhotos
import RPGTables
import RPGValues
import SwiftData
import SwiftUI

public enum MapFactory {
    @MainActor
    public static func root(container: ModelContainer, audioRoot: AudioRoot, diceRoot: DiceRoot, pdfRoot: PdfRoot, photoRoot: PhotoRoot, tableRoot: TableRoot, valueRoot: ValueRoot) -> MapRoot {
        MapRoot(container: container, audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, valueRoot: valueRoot)
    }

    @MainActor
    public static func rootView(for root: MapRoot, tabId: UUID) -> some View {
        RootList(root: root, tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
    
    @MainActor
    public static func rootExtendedView(for root: MapRoot, tabId: UUID) -> some View {
        RootExtendedList(editController: root.editController(type: .main), tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
}

public enum MapRoute: Hashable, Codable {
    case detail(ItemRowTreeModel?, UUID)
}

extension MapRoute: NavigationDestination {
    public var body: some View {
        switch self {
            case .detail(let itemRowTreeModel, let tabId):
                if let itemRowTreeModel {
                    RootExtendedDetail(itemRowTreeModel: itemRowTreeModel, tabId: tabId)
                } else {
                    SplitContentUnavailable(module: .map)
                }
        }
    }
}
