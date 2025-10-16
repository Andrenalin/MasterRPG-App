// @copyright André Trettin

import Foundation
import SwiftData

public enum EditControllerAddType: Equatable, Hashable, Sendable {
    case item
    case folder
    case collection
    
    var title: String {
        String(localized: localizedTitle).localizedString
    }
    
    private var localizedTitle: LocalizedStringResource {
        switch self {
        case .item:
            return "Add Item"
        case .folder:
            return "Add Folder"
        case .collection:
            return "Add Collection"
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
