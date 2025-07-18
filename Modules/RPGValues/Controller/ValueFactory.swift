// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import RPGDie
import RPGPdfs
import RPGPhotos
import RPGTables
import CoreData
import SwiftUI

public enum ValueFactory {
    @MainActor
    public static func root(for context: NSManagedObjectContext, diceRoot: DiceRoot, pdfRoot: PdfRoot, photoRoot: PhotoRoot, tableRoot: TableRoot) -> ValueRoot {
        ValueRoot(context: context, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
    }
    
    @MainActor
    public static func rootView(for root: ValueRoot, tabId: UUID) -> some View {
        let _ = root.listController(tabId: tabId, config: true)
        return RootList(root: root, tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
    
    @MainActor
    public static func rootExtendedView(for root: ValueRoot, tabId: UUID) -> some View {
        RootExtendedList(editController: root.editController(type: .main), tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
}

public enum ValueRoute: Hashable, Codable {
    case detail(ItemRowTreeModel?, UUID)
}

extension ValueRoute: NavigationDestination {
    public var body: some View {
        switch self {
            case .detail(let itemRowTreeModel, let tabId):
                if let itemRowTreeModel {
                    RootExtendedDetail(itemRowTreeModel: itemRowTreeModel, tabId: tabId)
                } else {
                    SplitContentUnavailable(module: .value)
                }
        }
    }
}
