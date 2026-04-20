// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class TableFirstSheetModel: Sendable {
    public init(linkControllable: any LinkControllable, parent: TableFirstSheetModel?, model: any ItemDataAccessable, entryId: UUID? = nil, level: Int, module: NetworkModules, searchText: String = "", maxDepth: Int = 20) {
        self.linkControllable = linkControllable
        self.parent = parent
        self.model = model
        self.itemId = model.id
        self.entryId = entryId
        self.level = level
        self.module = module
        self.maxDepth = maxDepth
        self.sheetModel = linkControllable.toggleSheet(itemId: itemId, entryId: entryId, level: level, module: module)
        self.searchText = searchText
        id = model.id
        updateFilteredEntries()
    }

    @ObservationIgnored let linkControllable: any LinkControllable
    let parent: TableFirstSheetModel?
    let model: any ItemDataAccessable
    let id: UUID
    let itemId: UUID
    let entryId: UUID?
    let level: Int
    let module: NetworkModules
    let maxDepth: Int

    var sheetModel: SheetFirstModel
    var searchText: String = "" {
        didSet {
            updateFilteredEntries()
        }
    }

    private(set) var filteredEntries: [SheetFirstModel] = []

    @ObservationIgnored var sheets: [ItemRowModel: TableFirstSheetModel] = [:]
    @ObservationIgnored private var linkTextModel: [LinkHighlightTextModelId: LinkHighlightTextModel] = [:]
    @ObservationIgnored private var originalEntries: [SheetFirstModel] = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var currentSearchResult: SheetSearchResult?

    var isAtMaxDepth: Bool {
        level >= maxDepth
    }

    private func updateFilteredEntries() {
        // Don't override if we have active search results
        guard currentSearchResult == nil else { return }
        filteredEntries = sheetModel.filter(searchText: searchText)
    }

    func description(for sheetModel: SheetFirstModel) -> String? {
        guard !searchText.isEmpty else { return sheetModel.description }
        return sheetModel.description.localizedCaseInsensitiveContains(searchText) ? sheetModel.description : nil
    }
    
    func linkTextModel(for id: LinkHighlightTextModelId, text: String, shareResults: ShareValueResult? = nil) -> LinkHighlightTextModel {
        guard let model = linkTextModel[id] else {
            let model = LinkHighlightTextModel(linkControllable: linkControllable, text: text, highlightedText: searchText, toggler: { self.toggle(id: id, itemId: $0, module: $1) }, shareResult: shareResults)
            linkTextModel[id] = model
            return model
        }
        return model
    }
    
    func updateSearch() {
        linkTextModel.forEach {
            $0.value.reset(highlightedText: searchText)
        }
        sheets.forEach {
            $0.value.updateSearch()
        }
    }
    
    func reset() {
        resetModel(model: linkControllable.toggleSheet(itemId: itemId, entryId: entryId, level: level, module: module))
    }

    func resetModel(model: SheetFirstModel) {
        linkTextModel.removeAll()
        sheets.removeAll()
        sheetModel = model
        updateFilteredEntries()
    }

    func update(with model: any ItemDataAccessable) {
        // Update the model reference
        guard model.id != self.model.id else {
            // Same model, just reset to reload data
            reset()
            return
        }

        // Model changed, need full reset
        reset()
    }

    func entry(entryId: String) -> SheetFirstModel? {
        sheetModel.entries.first { $0.id == entryId }
    }

    func hasEntry(entryId: UUID) -> Bool {
        sheetModel.entries.first { $0.source.entryId == entryId } != nil 
    }

    
    func toggle(id: LinkHighlightTextModelId, itemId: UUID, module: NetworkModules) {
        withAnimation {
            let rowModel = ItemRowModel(itemId: itemId, typeId: module)
            
            switch id {
            case .item(_):
                break
            case .name:
                break
            case .description:
                let sheets = linkControllable.toggleSheet(itemId: itemId, entryId: entryId, level: 0, module: module)
                sheetModel.entries.insert(contentsOf: sheets.entries, at: 0)
            case .entry(let uuid):
                guard let entryIndex = sheetModel.entries.firstIndex(where: { $0.id == uuid }) else { return }
                var entry = sheetModel.entries[entryIndex]
                if entry.sheetIds.contains(rowModel) {
                    entry.sheetIds.removeAll(where: { $0 == rowModel })
                } else {
                    let model = linkControllable.itemControllable.itemOrEmpty(for: itemId)
                    let TableFirstSheetModel = TableFirstSheetModel(linkControllable: linkControllable, parent: self, model: model, level: entry.level + 1, module: module, searchText: searchText, maxDepth: maxDepth)

                    sheets[rowModel] = TableFirstSheetModel
                    entry.sheetIds.append(rowModel)
                }
                sheetModel.entries[entryIndex] = entry
                updateFilteredEntries()
            }
        }
    }

    func add(entryId: UUID) {
        let updatedModel = linkControllable.toggleSheet(itemId: itemId, entryId: entryId, level: level, module: module)
        if let entryIndex = updatedModel.entries.firstIndex(where: { $0.source.entryId == entryId }) {
            let entry = updatedModel.entries[entryIndex]
            if entryIndex < sheetModel.entries.count {
                sheetModel.entries.insert(entry, at: entryIndex)
            } else {
                sheetModel.entries.append(entry)
            }
            updateFilteredEntries()
        }
    }
    
    func subTableModel(source: ItemRowModel) -> TableFirstSheetModel? {
        if let subModel = sheets[source] {
            return subModel
        }
        for subModel in sheets.values {
            if let model = subModel.subTableModel(source: source) {
                return model
            }
        }
        return nil
    }

    func move(itemId: UUID, entryId: UUID, into source: ItemRowModel) {
        let otherSource = ItemRowModel(itemId: itemId, entryId: nil, typeId: source.typeId)
        if let subSheetModel = subTableModel(source: otherSource) {
            if let entry = subSheetModel.sheetModel.entries.first(where: { $0.source.entryId == entryId }) {
                subSheetModel.remove(entry: entry)
            }
        }
        add(entryId: entryId)
    }

    func move(itemId: UUID, indexSet: IndexSet, to: Int) {
        sheetModel.entries.move(fromOffsets: indexSet, toOffset: to)
    }

    func move(entryDataEditable: (any EntryDataEditable)?, indexSet: IndexSet, to index: Int) {
        guard let entryDataEditable else { return }
        move(itemId: sheetModel.source.itemId, indexSet: indexSet, to: index)
        entryDataEditable.move(itemId: sheetModel.source.itemId, entryIds: sheetModel.entries.compactMap { $0.source.entryId })
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            updateParent()
        }
    }

    func moveEntries(indexSet: IndexSet, to index: Int) {
        guard let editable = entryDataEditable(for: sheetModel.source) else { return }
        move(itemId: sheetModel.source.itemId, indexSet: indexSet, to: index)
        editable.move(itemId: sheetModel.source.itemId, entryIds: sheetModel.entries.compactMap { $0.source.entryId })
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            updateParent()
        }
    }
    
    func groupFolders(entryDataEditable: (any EntryDataEditable), entry: SheetFirstModel) -> [FolderRepresentable] {
        guard let entryId = entry.source.entryId else { return [] }
        return entryDataEditable.groupFolders(itemId: entry.source.itemId, sourceEntryId: entryId)
    }

    func move(entryDataEditable: (any EntryDataEditable), entry: SheetFirstModel, into folder: FolderRepresentable) {
        guard let entryId = entry.source.entryId else { return }
        entryDataEditable.move(itemId: entry.source.itemId, sourceEntryId: entryId, into: folder)

        Task {
            try? await Task.sleep(for: .milliseconds(100))
            updateParent()
        }

    }

    func parentGroup(entryDataEditable: (any EntryDataEditable)) -> FolderRepresentable? {
        return entryDataEditable.parentFolder(itemId: sheetModel.source.itemId)
    }

    func moveOutOfGroup(entryDataEditable: (any EntryDataEditable), entry: SheetFirstModel, parent: FolderRepresentable) {
        guard let entryId = entry.source.entryId else { return }
        entryDataEditable.moveOutOfGroup(itemId: entry.source.itemId, sourceEntryId: entryId, parent: parent)

        Task {
            try? await Task.sleep(for: .milliseconds(100))
            updateParent()
        }
    }

    func update(entryId: UUID) {
        let updatedModel = linkControllable.toggleSheet(itemId: itemId, entryId: entryId, level: level, module: module)
        if let entryIndex = updatedModel.entries.firstIndex(where: { $0.source.entryId == entryId }) {
            let entry = updatedModel.entries[entryIndex]
            if entryIndex < sheetModel.entries.count {
                sheetModel.entries[entryIndex] = entry
                linkTextModel[.entry(entry.id)] = nil
                updateFilteredEntries()
            }
        } else if updatedModel.source.entryId == entryId, let entryIndex = sheetModel.entries.firstIndex(where: { $0.source.entryId == entryId }) {
            var updatedEntry = sheetModel.entries[entryIndex]
            if updatedEntry.description != updatedModel.description || updatedEntry.name != updatedModel.name {
                updatedEntry.description = updatedModel.description
                updatedEntry.name = updatedModel.name
                sheetModel.entries[entryIndex] = updatedEntry
                linkTextModel[.entry(updatedEntry.id)] = nil
                updateFilteredEntries()
            }
        }
    }
    
    func updateParent() {
        guard parent == nil else {
            parent?.updateParent()
            return
        }
        updateModels()
    }
    
    func updateModels() {
        let updatedModel = linkControllable.toggleSheet(itemId: itemId, entryId: entryId, level: level, module: module)

        // Update root sheet model properties if they changed
        if sheetModel.name != updatedModel.name || sheetModel.description != updatedModel.description {
            sheetModel.name = updatedModel.name
            sheetModel.description = updatedModel.description
            linkTextModel[.name] = nil
            linkTextModel[.description] = nil
        }

        let entries = updatedModel.entries.map {
            var entry = $0
            guard let localIndex = sheetModel.entries.firstIndex(where: { $0.source == entry.source }) else { return entry }
            let localEntry = sheetModel.entries[localIndex]
            if entry.name != localEntry.name || entry.description != localEntry.description {
                linkTextModel[.entry(entry.id)] = nil
            }
            entry.sheetIds = localEntry.sheetIds
            return entry
        }
        sheetModel.entries <=> entries
        updateFilteredEntries()
        sheets.values.forEach {
            $0.updateModels()
        }
    }

    func remove(entry: SheetFirstModel) {
        sheetModel.entries.removeAll(where: { $0.id == entry.id })
        linkTextModel[.entry(entry.id)] = nil
        updateFilteredEntries()
    }
    
    // Quick Editor
    func toggleEdit(entry: SheetFirstModel) {
        guard let entryIndex = sheetModel.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var entry = entry
        let rowModel = ItemRowModel(itemId: itemId, typeId: module)
        if entry.sheetIds.contains(rowModel) {
            entry.sheetIds.removeAll(where: { $0 == rowModel })
        } else {
            let model = linkControllable.itemControllable.itemOrEmpty(for: itemId)
            let TableFirstSheetModel = TableFirstSheetModel(linkControllable: linkControllable, parent: self, model: model, entryId: entry.source.entryId, level: entry.level + 1, module: module, searchText: searchText, maxDepth: maxDepth)

            sheets[rowModel] = TableFirstSheetModel
            entry.sheetIds.append(rowModel)
        }
        sheetModel.entries[entryIndex] = entry
        updateFilteredEntries()
    }
    
    func isEditing(entry: SheetFirstModel) -> Bool {
        entry.sheetIds.contains(ItemRowModel(itemId: itemId, typeId: module))
    }

    // MARK: - Search Functionality

    func performSheetSearch(searchControllable: SearchControllable, searchText: String) {
        // Cancel any existing search task
        searchTask?.cancel()

        // If search is empty, reset to original entries
        guard !searchText.isEmpty else {
            resetSearch()
            return
        }

        // Start new search task with cross-module support
        searchTask = Task { @MainActor in
            let result = await searchControllable.searchInSheet(
                itemId: itemId,
                searchText: searchText,
                includeLinks: true,
                rootManager: linkControllable.rootManager
            )

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            // Apply search results
            await applySearchResults(result, searchText: searchText)
            
            sheets.values.forEach {
                $0.performSheetSearch(searchControllable: searchControllable, searchText: searchText)
            }
        }
    }

    @MainActor
    private func applySearchResults(_ result: SheetSearchResult, searchText: String) async {
        // Store original entries if this is the first search
        if originalEntries.isEmpty {
            originalEntries = sheetModel.entries
        }

        // Store current search result
        currentSearchResult = result

        // Get matched entry IDs
        let matchedIds = Set(result.matchedEntries.map { $0.entryId })

        // Filter entries to only show matches
        let matchedEntries = originalEntries.filter { entry in
            guard let entryId = entry.source.entryId else { return false }
            return matchedIds.contains(entryId)
        }

        // Update displayed entries with animation
        withAnimation {
            sheetModel.entries = matchedEntries
            // CRITICAL: Update filteredEntries property that UI reads from
            self.filteredEntries = matchedEntries
        }

        // Auto-expand links with matches
        await expandLinksWithMatches(result: result, searchText: searchText)

        // Update search highlighting in link text models
        updateSearch()
    }

    @MainActor
    private func expandLinksWithMatches(result: SheetSearchResult, searchText: String) async {
        for (entryId, linkedItemIds) in result.expandedLinks {
            // Find the entry in our sheet
            guard let entryIndex = sheetModel.entries.firstIndex(where: { $0.source.entryId == entryId }) else {
                continue
            }

            var entry = sheetModel.entries[entryIndex]

            // Get cross-module match info for this entry
            let crossModuleMatches = result.crossModuleMatches[entryId] ?? []

            // Expand each linked item
            for linkedItemId in linkedItemIds {
                // Determine the module for this linked item
                let linkedModule: NetworkModules
                if let crossMatch = crossModuleMatches.first(where: { $0.linkedItemId == linkedItemId }) {
                    linkedModule = crossMatch.linkedModule
                } else {
                    // Same module as current
                    linkedModule = module
                }

                let rowModel = ItemRowModel(itemId: linkedItemId, typeId: linkedModule)

                // Check if link is already expanded
                guard !entry.sheetIds.contains(rowModel) else { continue }

                // Get the correct item controllable for the linked module
                let linkedItemControllable = itemControllable(for: rowModel)
                let linkedModel = linkedItemControllable.itemOrEmpty(for: linkedItemId)

                // Create sub-sheet model for the linked item with the correct module
                let TableFirstSheetModel = TableFirstSheetModel(
                    linkControllable: linkControllable,
                    parent: self,
                    model: linkedModel,
                    level: entry.level + 1,
                    module: linkedModule,  // Use correct module
                    searchText: searchText,
                    maxDepth: maxDepth
                )

                // Store the sub-sheet
                sheets[rowModel] = TableFirstSheetModel

                // Add to entry's expanded sheets
                entry.sheetIds.append(rowModel)
                
                // Trigger search on the sub-sheet to filter its entries
                if let linkedSearchControllable = rootController(for: linkedModule)?.searchControllable {
                    TableFirstSheetModel.performSheetSearch(
                        searchControllable: linkedSearchControllable,
                        searchText: searchText
                    )
                }
            }

            // Update the entry with expanded links
            sheetModel.entries[entryIndex] = entry
        }
    }

    private func performSimpleSearch(searchText: String) {
        // Store original entries if this is the first search
        if originalEntries.isEmpty {
            originalEntries = sheetModel.entries
        }

        // Simple filter by name and description
        let filtered = originalEntries.filter { entry in
            entry.name.localizedStandardContains(searchText) ||
            entry.description.localizedStandardContains(searchText)
        }

        withAnimation {
            sheetModel.entries = filtered
        }

        // Update search highlighting
        updateSearch()
    }

    private func resetSearch() {
        // Cancel any ongoing search
        searchTask?.cancel()
        searchTask = nil
        currentSearchResult = nil

        // Restore original entries if we have them
        if !originalEntries.isEmpty {
            withAnimation {
                sheetModel.entries = originalEntries
                // Also restore filteredEntries that UI reads from
                filteredEntries = originalEntries
            }
            originalEntries.removeAll()
        }

        // Update highlighting (removes highlights)
        updateSearch()
    }

    func getMatchLocations(for entryId: UUID) -> [SheetMatchLocation] {
        guard let searchResult = currentSearchResult else { return [] }
        return searchResult.matchedEntries.first(where: { $0.entryId == entryId })?.matchLocations ?? []
    }

    func hasLinkMatch(for entry: SheetFirstModel) -> Bool {
        guard let entryId = entry.source.entryId else { return false }
        let locations = getMatchLocations(for: entryId)
        return locations.contains { location in
            if case .link = location { return true }
            return false
        }
    }

    // MARK: - Action Methods (Module-Aware)

    /// Add a new entry to the specified source
    func addNewEntry(to source: ItemRowModel) -> UUID? {
        guard let editable = entryDataEditable(for: source) else { return nil }
        return editable.addNewEntry(itemId: source.itemId)
    }

    /// Remove an entry from the specified source
    func removeEntry(source: ItemRowModel) {
        guard let editable = entryDataEditable(for: source) else { return }
        editable.removeEntry(source: source)
    }

    /// Set the current item in the edit controller
    func setCurrentItem(source: ItemRowModel, entryId: UUID?) {
        guard let editController = editControllable(for: source) else { return }
        editController.setCurrentItem(to: ItemRowTreeModel(itemId: source.itemId, entryId: entryId, typeId: source.typeId))
    }

    /// Set the current entry ID in the editor model
    func setCurrentEntryId(source: ItemRowModel, entryId: UUID?) {
        guard let editController = editControllable(for: source) else { return }
        editController.editorModel.currentEntryId = entryId
    }

    /// Set the scroll entry ID in the editor model
    func setScrollEntryId(source: ItemRowModel, entryId: UUID?) {
        guard let editController = editControllable(for: source) else { return }
        editController.editorModel.scrollEntryId = entryId
    }

    /// Add a link to a destination entry
    func addLink(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, to destination: ItemRowModel) {
        guard let editable = entryDataEditable(for: destination),
              let destinationEntryId = destination.entryId else { return }
        editable.add(link: link, module: module, itemId: itemId, entryId: entryId, destinationItemId: destination.itemId, destinationEntryId: destinationEntryId)
    }

    /// Get the item name for a source
    func getItemName(for source: ItemRowModel) -> String {
        let item = itemControllable(for: source).itemOrEmpty(for: source.itemId)
        return item.name
    }

    /// Get the item description for a source
    func getItemDescription(for source: ItemRowModel) -> String {
        let item = itemControllable(for: source).itemOrEmpty(for: source.itemId)
        return item.description
    }

    /// Get the current entry ID from the editor model
    func getCurrentEntryId(for source: ItemRowModel) -> UUID? {
        editControllable(for: source)?.editorModel.currentEntryId
    }

    /// Get the current item ID from the editor model
    func getCurrentItemId(for source: ItemRowModel) -> UUID? {
        editControllable(for: source)?.editorModel.currentItemId
    }

    /// Check if the editor has changed entries
    func hasChangedEntries(for source: ItemRowModel) -> Int {
        editControllable(for: source)?.editorModel.hasChangedEntries ?? 0
    }

    /// Check if the editor has any changes (boolean for more efficient onChange observation)
    func hasAnyChanges(for source: ItemRowModel) -> Bool {
        hasChangedEntries(for: source) > 0
    }

    /// Move an item/entry into a new parent
    func moveItem(itemId: UUID, entryId: UUID, into destination: ItemRowModel) -> Bool {
        guard let editable = entryDataEditable(for: destination) else { return false }
        return editable.move(itemId: itemId, entryId: entryId, into: destination)
    }

    // MARK: - Module-Aware Controllable Resolution

    /// Get the correct ItemRootController for a given module
    func rootController(for module: NetworkModules) -> ItemRootController? {
        linkControllable.rootManager.itemRootController(for: module)
    }

    /// Get the correct ItemControllable for a source (handles cross-module)
    func itemControllable(for source: ItemRowModel) -> any ItemControllable {
        if let root = rootController(for: source.typeId) {
            return root.itemControllable
        }
        // Fallback to current module's controllable
        return linkControllable.itemControllable
    }

    /// Get the correct EditControllable for a source (handles cross-module)
    func editControllable(for source: ItemRowModel) -> (any EditControllable)? {
        rootController(for: source.typeId)?.editControllable
    }

    /// Get the correct EntryDataEditable for a source (handles cross-module)
    func entryDataEditable(for source: ItemRowModel) -> (any EntryDataEditable)? {
        editControllable(for: source) as? (any EntryDataEditable)
    }

    /// Get the correct ViewControllable for a source (handles cross-module)
    func viewControllable(for source: ItemRowModel) -> (any ViewControllable)? {
        rootController(for: source.typeId)?.viewControllable
    }

    /// Get the search controllable (uses root since search is cross-module)
    var searchControllable: any SearchControllable {
        linkControllable.rootManager.adventureRoot.searchControllable
    }

    /// Get the module tint color
    var moduleTint: Color {
        rootController(for: module)?.configurable.module.tint ?? .blue
    }
}
