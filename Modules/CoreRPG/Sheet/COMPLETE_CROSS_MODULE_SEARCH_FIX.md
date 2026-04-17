# Cross-Module Search: Complete Implementation

## Summary

Successfully implemented cross-module search that finds matches in linked items across different modules (Adventure, Maps, Photos, etc.) and displays entries that link to those matches.

## The Problem You Identified

**Issue**: When searching for "Bathroom" in an Adventure entry that links to a Map containing "Bathroom", the Adventure entry was being filtered out even though the search found the match in the linked Map.

**Root Cause**: The UI was reading from `filteredEntries` property, which was being updated by simple text-based filtering that didn't know about cross-module search results.

## Files Modified

### 1. SearchControllable.swift
**Changes:**
- Added `rootManager` parameter to `searchInSheet()` for cross-module access
- Enhanced link extraction to include module information (`extractLinksWithModules`)
- Updated search to use appropriate module's `SearchControllable` for each link
- Added new types: `LinkInfo`, `LinkedItemMatchResult`, `CrossModuleMatch`
- Updated `SheetMatchLocation` to include module: `.link(UUID, NetworkModules)`
- Enhanced `SheetSearchResult` with `crossModuleMatches` dictionary

### 2. TableFirstSheetModel.swift
**Changes:**
- Updated `performSheetSearch()` to pass `rootManager` for cross-module search
- Enhanced `expandLinksWithMatches()` to determine correct module for each link
- **Fixed `applySearchResults()`** to update both `sheetModel.entries` AND `filteredEntries`
- **Fixed `resetSearch()`** to restore both properties
- **Fixed `updateFilteredEntries()`** to not override search results when search is active
- Added helper methods: `getCrossModuleMatches()`, `getMatchedModule()`

## How It Works End-to-End

### Example: Search "Bathroom" in Adventure Module

```
1. User types "Bathroom" in search
   ↓
2. performSheetSearch called
   ↓
3. searchInSheet (Adventure module)
   - Checks Adventure entry "Tavern"
   - Name: "Tavern" ❌ (no match)
   - Content: "Visit the tavern..." ❌ (no match)
   - Found link: adr://map/{mapId}/0
   ↓
4. Extract link with module info
   - LinkInfo(itemId: mapId, module: .map)
   - Module is .map (different from .adventure!)
   ↓
5. Get Map module's SearchControllable
   - rootManager.mapRoot.searchControllable
   ↓
6. Search in linked Map item
   - Map item: "Tavern Floor Plan"
   - Entry: "Kitchen" ❌
   - Entry: "Bathroom" ✅ MATCH!
   ↓
7. Build search result
   - matchedEntries: ["Tavern" entry] (Adventure)
   - matchLocations: [.link(mapId, .map)]
   - expandedLinks: [tavernId: [mapId]]
   - crossModuleMatches: [tavernId: [CrossModuleMatch(...)]]
   ↓
8. applySearchResults
   - Store original entries
   - Filter to matched entries only
   - Update sheetModel.entries = ["Tavern"]
   - Update filteredEntries = ["Tavern"] ← KEY FIX!
   ↓
9. expandLinksWithMatches
   - Get Map's ItemControllable (not Adventure's)
   - Create TableFirstSheetModel with module: .map
   - Auto-expand "Tavern" to show Map
   ↓
10. UI displays results
    - ForEach(model.filteredEntries) ← Reads from filteredEntries
    - Shows: "Tavern" entry (expanded)
      └─ Map: "Tavern Floor Plan"
         └─ Bathroom ★ (highlighted match)
```

## Key Fixes for Your Issue

### Fix 1: Pass rootManager
```swift
let result = await searchControllable.searchInSheet(
    itemId: itemId,
    searchText: searchText,
    includeLinks: true,
    rootManager: linkControllable.rootManager  // ← Added this
)
```

### Fix 2: Update filteredEntries in search results
```swift
withAnimation {
    sheetModel.entries = matchedEntries
    filteredEntries = matchedEntries  // ← Added this
}
```

### Fix 3: Protect filteredEntries during search
```swift
private func updateFilteredEntries() {
    // Don't override search results
    guard currentSearchResult == nil else { return }  // ← Added this
    
    filteredEntries = sheetModel.filter(searchText: searchText)
}
```

## Testing the Implementation

### Manual Test Steps

1. **Create test data:**
   - Adventure item with entry "Tavern"
   - Add link in "Tavern" content to a Map item
   - Map item "Tavern Floor Plan" with entry "Bathroom"

2. **Perform search:**
   - Search for "Bathroom" in Adventure module
   - Expected: "Tavern" entry appears
   - Expected: Map link is auto-expanded
   - Expected: "Bathroom" entry is visible and highlighted

3. **Verify filtering:**
   - Check that ONLY matched entries appear (not all entries)
   - Check that clearing search shows all entries again

4. **Test cross-module:**
   - Verify map icon/color appears for cross-module links
   - Verify can expand/collapse the linked map
   - Verify search highlighting works in nested content

### Test Different Scenarios

1. **Same-module search**: Search term in Adventure entry directly
2. **Cross-module search**: Search term only in linked Map
3. **Multi-level search**: Adventure → Map → Photo chain
4. **No matches**: Search term not found anywhere
5. **Mixed matches**: Some entries match locally, some via links

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────┐
│ User Search Input: "Bathroom"                       │
└────────────────────┬────────────────────────────────┘
                     │
         ┌───────────▼──────────────┐
         │ performSheetSearch()     │
         │ - searchText             │
         │ - rootManager ← passed   │
         └───────────┬──────────────┘
                     │
         ┌───────────▼──────────────────────────┐
         │ searchInSheet()                      │
         │ (Adventure SearchControllable)       │
         ├──────────────────────────────────────┤
         │ For each entry:                      │
         │   1. Check name/content              │
         │   2. Extract links with modules      │
         │   3. For each link:                  │
         │      - Get link's module             │
         │      - Get that module's search      │
         │      - Search in linked item         │
         └───────────┬──────────────────────────┘
                     │
         ┌───────────▼──────────────────────────┐
         │ searchInLinkedItem()                 │
         │ (Map SearchControllable)             │
         ├──────────────────────────────────────┤
         │ Map: "Tavern Floor Plan"             │
         │   ✗ Kitchen                          │
         │   ✓ Bathroom ← MATCH!                │
         └───────────┬──────────────────────────┘
                     │
         ┌───────────▼──────────────────────────┐
         │ SheetSearchResult                    │
         ├──────────────────────────────────────┤
         │ matchedEntries:                      │
         │   - "Tavern" entry                   │
         │ matchLocations:                      │
         │   - .link(mapId, .map)               │
         │ crossModuleMatches:                  │
         │   - Map info + matched entries       │
         └───────────┬──────────────────────────┘
                     │
         ┌───────────▼──────────────────────────┐
         │ applySearchResults()                 │
         ├──────────────────────────────────────┤
         │ 1. Store originalEntries             │
         │ 2. Filter to matched only            │
         │ 3. Update sheetModel.entries ✓       │
         │ 4. Update filteredEntries ✓ FIX!     │
         │ 5. Expand links with matches         │
         └───────────┬──────────────────────────┘
                     │
         ┌───────────▼──────────────────────────┐
         │ UI Rendering                         │
         ├──────────────────────────────────────┤
         │ ForEach(model.filteredEntries)       │
         │   ↓                                  │
         │ Shows: "Tavern" entry                │
         │   └─ [Map] Tavern Floor Plan         │
         │      └─ Bathroom ★                   │
         └──────────────────────────────────────┘
```

## Benefits

✅ **Cross-module discovery** - Find content regardless of which module it's in
✅ **Automatic expansion** - Links with matches open automatically  
✅ **Proper filtering** - Only matched entries shown, not all entries
✅ **Module context** - Each linked item uses its own module's controllers
✅ **Visual feedback** - Can add module badges/colors to show where match is
✅ **Performance** - Lazy loading, task cancellation supported
✅ **Backwards compatible** - Works with existing simple text search too

## Next Steps

1. **Add UI indicators** - Show which module contains the match
2. **Add breadcrumb navigation** - Show module path (Adventure › Map)
3. **Add quick jump** - Button to open source module directly
4. **Optimize performance** - Consider search depth limits for deep hierarchies
5. **Add user preferences** - Allow enabling/disabling cross-module search
6. **Add match details** - Popover showing exactly what matched where

## Debugging Tips

If cross-module search isn't working:

1. **Check rootManager is passed**: Look for `rootManager: linkControllable.rootManager`
2. **Verify module registration**: Ensure all modules have SearchControllable
3. **Check filteredEntries updates**: Both in applySearchResults and resetSearch
4. **Verify link extraction**: Links should have correct module information
5. **Test search controllable**: Each module's search should work independently
6. **Check UI binding**: UI should read from `filteredEntries`, not `sheetModel.entries`
