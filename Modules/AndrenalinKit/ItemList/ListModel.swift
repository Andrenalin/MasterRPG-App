// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor @Observable
public final class ListModel: Sendable {
    public init(searchToken: ItemListCategory, categoryTags: [ItemListCategory], listStoreName: String, hasChildren: Bool) {
        self.searchToken = searchToken
        self.categoryTags = categoryTags
        self.listTitleName = listStoreName
        self.hasChildren = hasChildren
    }

    // items
    public var filteredItems: [ItemRowTreeModel] = []
    var unfilteredItems: [ItemRowTreeModel] = []
    var idItems: [UUID: Int] = [:]

    // Selection
    public var selectedItem: ItemRowTreeModel?
    public var selectedItems: [ItemRowTreeModel] = []
    public var gameSelectedItem: ItemRowTreeModel?

    // scroll
    public var scrollItem: ItemRowTreeModel?
    public var scrollEntryId: UUID?
    
    // edit
    public var activeEdit: Bool = false
    public var allowEditing: Bool = false

    // search / filter
    var isSearching: Bool = false
    public var searchText: String = ""
    public var searchToken: ItemListCategory = .all
    public var selectedTokens: [SearchTags] = []
    
    public var categoryTags: [ItemListCategory] = []
    public var isHiddenItems: Bool = true
    
    @ObservationIgnored
    var lastSearchText: String = ""
    
    // cache
    @ObservationIgnored
    public let cacheItemList: CacheItemList = CacheItemList()

    // options
    public var expandNewItems: Bool = false
    public var filterModel: ItemRowModel?
    public var selectionMode: SelectionMode?
    public var onlyItems: Bool = false
    public var onlyEntries: Bool = false

    // configuration
    public var listTitleName: String = ""
    public var hasChildren: Bool = false
    public var hideChildrenHeader: Bool = false

    public var showGeneratorItem: ItemRowModel?
    
    var actionSelection: [ItemRowTreeModel] = []
}

// MARK: - Search Tags

public struct SearchTags: Hashable, Equatable, Identifiable, Sendable {
    public let tag: String
    public var id: String { tag }

    static public let allCategory = SearchTags(tag: "All")
}

public struct SelectionMode {
    public init(selectionId: UUID = UUID(), selected: @escaping () -> [ItemRowModel], toggle: @escaping (ItemRowModel, Bool) -> Void) {
        self.selectionId = selectionId
        self.selected = selected
        self.toggle = toggle
    }
    public let selectionId: UUID
    public let selected: () -> [ItemRowModel]
    public let toggle: (ItemRowModel, Bool) -> Void
}
