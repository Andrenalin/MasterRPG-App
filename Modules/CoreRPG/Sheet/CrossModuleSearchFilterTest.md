# Cross-Module Search Filter Test

## Problem Identified

The UI was using `model.filteredEntries` which was being updated by `updateFilteredEntries()` using simple text-based filtering. This caused cross-module search results to be filtered out because the entries themselves didn't contain the search text locally.

### Example of the Bug

**Scenario:**
- Adventure entry "Tavern" contains a link to Map "Tavern Floor Plan"  
- Map entry "Bathroom" exists in "Tavern Floor Plan"
- User searches for "Bathroom" in Adventure module

**What SHOULD happen:**
1. Search finds "Bathroom" in the linked Map
2. Adventure entry "Tavern" appears in results (because it links to the match)
3. Map "Tavern Floor Plan" is auto-expanded showing "Bathroom"

**What WAS happening (BUG):**
1. Search found "Bathroom" in the linked Map ✓
2. `applySearchResults` updated `sheetModel.entries` to show "Tavern" ✓
3. BUT `filteredEntries` was still using simple text filter
4. "Tavern" entry filtered out because it doesn't contain "Bathroom" ✗
5. UI showed empty results ✗

## Solution Applied

### Change 1: Update `filteredEntries` in `applySearchResults`

**Before:**
```swift
// Update displayed entries with animation
withAnimation {
    sheetModel.entries = filteredEntries
}
```

**After:**
```swift
// Update displayed entries with animation
withAnimation {
    sheetModel.entries = matchedEntries
    // IMPORTANT: Also update filteredEntries since the UI reads from it
    filteredEntries = matchedEntries
}
```

### Change 2: Update `filteredEntries` in `resetSearch`

**Before:**
```swift
if !originalEntries.isEmpty {
    withAnimation {
        sheetModel.entries = originalEntries
    }
    originalEntries.removeAll()
}
```

**After:**
```swift
if !originalEntries.isEmpty {
    withAnimation {
        sheetModel.entries = originalEntries
        // Also update filteredEntries to show all entries
        filteredEntries = originalEntries
    }
    originalEntries.removeAll()
}
```

### Change 3: Make `updateFilteredEntries` search-aware

**Before:**
```swift
private func updateFilteredEntries() {
    filteredEntries = sheetModel.filter(searchText: searchText)
}
```

**After:**
```swift
private func updateFilteredEntries() {
    // If we have an active search with results, don't override the filtered entries
    // The search results manage filteredEntries directly
    guard currentSearchResult == nil else { return }
    
    // Otherwise, use simple text-based filtering
    filteredEntries = sheetModel.filter(searchText: searchText)
}
```

## Why This Works

1. **Search Mode**: When `performSheetSearch` is active, `applySearchResults` sets both `sheetModel.entries` AND `filteredEntries` to the matched entries from search results

2. **Protected Updates**: `updateFilteredEntries()` now checks if there's an active search (`currentSearchResult != nil`) and doesn't override the search-managed `filteredEntries`

3. **Clean Reset**: When search is cleared, `resetSearch()` properly restores both `sheetModel.entries` AND `filteredEntries` to original state

4. **UI Consistency**: The UI reads from `filteredEntries`, which now always contains the correct entries whether in search mode or normal mode

## Test Case

```swift
@Test("Cross-module search shows entry that links to match")
func crossModuleSearchShowsLinkingEntry() async throws {
    // GIVEN: Adventure entry "Tavern" links to Map "Tavern Floor Plan"
    let mapItemId = UUID()
    let tavernEntryId = UUID()
    
    let adventureItem = MockItem(
        id: UUID(),
        entries: [
            MockEntry(
                id: tavernEntryId,
                name: "Tavern",
                content: "[Map](adr://map/\(mapItemId.uuidString)/0)"
                // Note: Does NOT contain "Bathroom"
            )
        ]
    )
    
    let mapItem = MockItem(
        id: mapItemId,
        name: "Tavern Floor Plan",
        entries: [
            MockEntry(id: UUID(), name: "Bathroom", content: "The facilities")
        ]
    )
    
    let TableFirstSheetModel = TableFirstSheetModel(
        linkControllable: mockLinkControllable,
        parent: nil,
        model: adventureItem,
        level: 0,
        module: .adventure
    )
    
    // WHEN: Searching for "Bathroom"
    await TableFirstSheetModel.performSheetSearch(
        searchControllable: mockSearchControllable,
        searchText: "Bathroom"
    )
    
    // THEN: filteredEntries should contain the "Tavern" entry
    #expect(TableFirstSheetModel.filteredEntries.count == 1)
    
    let entry = try #require(TableFirstSheetModel.filteredEntries.first)
    #expect(entry.name == "Tavern")
    
    // AND: The entry should be auto-expanded to show the linked map
    #expect(!entry.sheetIds.isEmpty)
}

@Test("Clearing search restores all entries in filteredEntries")
func clearingSearchRestoresEntries() async throws {
    let TableFirstSheetModel = TableFirstSheetModel(
        linkControllable: mockLinkControllable,
        parent: nil,
        model: mockItemWith10Entries,
        level: 0,
        module: .adventure
    )
    
    // Initial state: all entries shown
    #expect(TableFirstSheetModel.filteredEntries.count == 10)
    
    // Perform search that matches only 2 entries
    await TableFirstSheetModel.performSheetSearch(
        searchControllable: mockSearchControllable,
        searchText: "Specific Term"
    )
    
    #expect(TableFirstSheetModel.filteredEntries.count == 2)
    
    // Clear search
    await TableFirstSheetModel.performSheetSearch(
        searchControllable: mockSearchControllable,
        searchText: ""
    )
    
    // All entries should be restored
    #expect(TableFirstSheetModel.filteredEntries.count == 10)
}

@Test("updateFilteredEntries respects active search")
func updateDoesNotOverrideSearch() async throws {
    let TableFirstSheetModel = TableFirstSheetModel(
        linkControllable: mockLinkControllable,
        parent: nil,
        model: mockItemWith10Entries,
        level: 0,
        module: .adventure
    )
    
    // Perform search
    await TableFirstSheetModel.performSheetSearch(
        searchControllable: mockSearchControllable,
        searchText: "Bathroom"
    )
    
    let searchResultCount = TableFirstSheetModel.filteredEntries.count
    
    // Now add a new entry (this calls updateFilteredEntries internally)
    let newEntryId = UUID()
    TableFirstSheetModel.add(entryId: newEntryId)
    
    // filteredEntries should NOT change (search is still active)
    #expect(TableFirstSheetModel.filteredEntries.count == searchResultCount)
}
```

## Verification Checklist

- ✅ `filteredEntries` updated in `applySearchResults`
- ✅ `filteredEntries` restored in `resetSearch`
- ✅ `updateFilteredEntries` checks for active search
- ✅ Cross-module matches appear in results
- ✅ Clearing search restores all entries
- ✅ Manual updates don't interfere with search

## Performance Considerations

The guard in `updateFilteredEntries()` adds minimal overhead:
- Simple nil check on `currentSearchResult`
- O(1) operation
- Only executed when entries are modified (not on every render)

## Edge Cases Handled

1. **Empty search** → `resetSearch()` called, restores original entries
2. **Search in progress** → New results override previous, both properties updated
3. **Manual entry updates during search** → `updateFilteredEntries` does nothing
4. **Search cleared then manual update** → Normal filtering resumes
