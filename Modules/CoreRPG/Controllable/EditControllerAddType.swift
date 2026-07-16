// @copyright André Trettin

import Foundation
import SwiftData

public enum EditControllerAddType: Equatable, Hashable, Sendable {
    case item
    case folder
    case collection
    
    var title: String {
        String(localized: localizedTitle)
    }
    
    private var localizedTitle: LocalizedStringResource {
        switch self {
        case .item:
            return LocalizedStringResource("Add Item", bundle: .module)
        case .folder:
            return LocalizedStringResource("Add Folder", bundle: .module)
        case .collection:
            return LocalizedStringResource("Add Collection", bundle: .module)
        }
    }
    
    func icon(collection: String) -> String {
        switch self {
        case .item:
            return "plus"
        case .folder:
            return "folder.badge.plus"
        case .collection:
            return collection
        }
    }
}
