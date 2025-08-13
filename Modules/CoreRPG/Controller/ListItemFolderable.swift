// @copyright André Trettin

import SwiftUI

public protocol ListItemFolderable: Identifiable {
    var isFolder: Bool { get }
    @MainActor var subItems: ([Self], [UUID: UUID]) { get }
    
    @MainActor static var dropItem: Self { get }
    @MainActor static var collectionCategory: ItemListCategory { get }
}

