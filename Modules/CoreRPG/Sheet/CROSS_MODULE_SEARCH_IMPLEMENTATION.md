# Cross-Module Search Implementation

## Overview

This implementation enables **cross-module search** in TableFirstSheetModel, allowing searches to find matches in linked items across different modules (e.g., searching in Adventure and finding matches in linked Maps).

## Changes Made

### 1. SearchControllable.swift

#### Enhanced `searchInSheet` Method
- **Added parameter**: `rootManager: RootManager?` to enable cross-module search
- **New logic**: Extracts links with module information, then uses the appropriate `SearchControllable` for each module
- **Cross-module support**: When a link points to a different module, the search uses that module's `SearchControllable`

#### New Helper Methods
- `extractLinksWithModules(from:)`: Returns links with their module information
- `searchInLinkedItem(_:searchText:searchControllable:)`: Returns detailed match information (item name, description, entry IDs)

#### Updated Types

**LinkInfo** (new)
```swift
struct LinkInfo: Sendable {
    let itemId: UUID
    let module: NetworkModules
}
```

**LinkedItemMatchResult** (new)
```swift
struct LinkedItemMatchResult: Sendable {
    let matchedInItemName: Bool
    let matchedInItemDescription: Bool
    let matchedEntryIds: [UUID]
    var hasMatch: Bool { ... }
}
```

**SheetSearchResult** (enhanced)
```swift
public struct SheetSearchResult: Sendable {
    public let matchedEntries: [SheetEntryMatch]
    public let expandedLinks: [UUID: [UUID]]
    public let crossModuleMatches: [UUID: [CrossModuleMatch]]  // NEW
}
```

**CrossModuleMatch** (new)
```swift
public struct CrossModuleMatch: Sendable {
    public let linkedItemId: UUID
    public let linkedModule: NetworkModules
    public let matchedInItemName: Bool
    public let matchedInItemDescription: Bool
    public let matchedEntryIds: [UUID]
}
```

**SheetMatchLocation** (updated)
```swift
public enum SheetMatchLocation: Equatable, Sendable {
    case name
    case content
    case link(UUID, NetworkModules)  // Now includes module information
}
```

### 2. TableFirstSheetModel.swift

#### Updated `performSheetSearch`
- Now passes `linkControllable.rootManager` to `searchInSheet`
- Enables the search to access other modules' search controllers

#### Enhanced `expandLinksWithMatches`
- Determines the correct module for each linked item
- Uses `itemControllable(for:)` to get the right controllable for cross-module items
- Creates `TableFirstSheetModel` with the correct module

#### New Helper Methods
```swift
func getCrossModuleMatches(for entry: SheetModel) -> [CrossModuleMatch]
func getMatchedModule(for entry: SheetModel, linkedItemId: UUID) -> NetworkModules?
```

## How It Works

### Example: Searching "Bathroom" in Adventure Module

1. **Initial Search**: Adventure module searches its own items/entries
   - No direct match in Adventure items

2. **Link Detection**: For each entry, extract all links with module info
   - Entry "Tavern" contains link to Map item "Tavern Floor Plan"

3. **Cross-Module Search**: 
   - Detects link is to Map module (different from Adventure)
   - Gets Map module's `SearchControllable` via `rootManager`
   - Searches in "Tavern Floor Plan" map using Map's search controller
   - Finds entry "Bathroom" in the map

4. **Result Assembly**:
   - Adventure entry "Tavern" is included in results
   - Match location: `.link(mapItemId, .map)`
   - Cross-module match info stored with details about what matched

5. **Auto-Expansion**:
   - "Tavern" entry expanded to show linked map
   - Map item "Tavern Floor Plan" shown with correct module context
   - Search continues recursively in the map's entries

## Benefits

✅ **Cross-Module Discovery**: Find content regardless of which module it's in
✅ **Proper Module Context**: Each linked item uses its own module's controllers
✅ **Detailed Match Info**: Know exactly what matched (item name, description, entries)
✅ **Recursive Search**: Searches follow links through multiple levels
✅ **Module Awareness**: UI can display module-specific styling/colors

## Usage

### Basic Search (Automatic)
```swift
TableFirstSheetModel.performSheetSearch(
    searchControllable: searchControllable,
    searchText: "Bathroom"
)
```

The cross-module search happens automatically when:
- `linkControllable.rootManager` is available
- Links point to different modules
- Those modules have registered `SearchControllable` implementations

### Accessing Cross-Module Results
```swift
// Get cross-module matches for an entry
let crossMatches = TableFirstSheetModel.getCrossModuleMatches(for: entry)

for match in crossMatches {
    print("Found in \(match.linkedModule)")
    print("Item name match: \(match.matchedInItemName)")
    print("Matched entries: \(match.matchedEntryIds)")
}
```

## Backwards Compatibility

All changes are **backwards compatible**:
- `rootManager` parameter is optional (defaults to `nil`)
- When `nil`, search only uses current module (original behavior)
- `crossModuleMatches` defaults to empty dictionary
- Legacy helper methods still available

## Performance Considerations

- **Lazy Loading**: Only searches linked modules when links are found
- **Task Cancellation**: Supports cancellation for long-running searches
- **Module Caching**: Uses existing `rootManager` structure (no extra lookups)
- **Relevance Scoring**: Cross-module matches get slightly lower scores than same-module

## Future Enhancements

Potential improvements:
- **Search depth limit**: Prevent infinite recursion in circular links
- **Module filtering**: Allow users to include/exclude specific modules
- **Match highlighting**: Visual indicators for cross-module matches
- **Performance optimization**: Parallel searches across modules
