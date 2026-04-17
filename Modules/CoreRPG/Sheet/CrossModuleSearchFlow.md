# Cross-Module Search Flow Diagram

## Search Flow: "Bathroom" Example

```
┌─────────────────────────────────────────────────────────────────────┐
│ User searches "Bathroom" in Adventure Module                        │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ TableFirstSheetModel.performSheetSearch()                                │
│ - itemId: Adventure Item UUID                                       │
│ - module: .adventure                                                │
│ - searchText: "Bathroom"                                            │
│ - rootManager: RootManager instance                                 │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Adventure SearchControllable.searchInSheet()                        │
│                                                                     │
│ Step 1: Search in Adventure entries                                │
│   ✓ Entry "Tavern"                                                 │
│     - Name: No match                                                │
│     - Content: No match                                             │
│     - Extract links from content...                                 │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ extractLinksWithModules(from: entry.content)                        │
│                                                                     │
│ Found links in "Tavern" entry:                                      │
│   - LinkInfo(itemId: mapItemId, module: .map) ← Different module!  │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Determine which SearchControllable to use                           │
│                                                                     │
│ if link.module == .map (different from .adventure):                 │
│   searchControllable = rootManager.mapRoot                          │
│                       .rootController                               │
│                       .searchControllable                           │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Map SearchControllable: searchInLinkedItem()                        │
│                                                                     │
│ Search in Map Item "Tavern Floor Plan":                             │
│   - Item name: "Tavern Floor Plan" → No match                      │
│   - Item description: "..." → No match                              │
│   - Entry "Kitchen": No match                                       │
│   - Entry "Bathroom": ✓ MATCH! (name contains "Bathroom")          │
│   - Entry "Storage": No match                                       │
│                                                                     │
│ Returns: LinkedItemMatchResult(                                     │
│   matchedInItemName: false,                                         │
│   matchedInItemDescription: false,                                  │
│   matchedEntryIds: [bathroomEntryId]                                │
│ )                                                                   │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Build Search Results                                                │
│                                                                     │
│ SheetSearchResult(                                                  │
│   matchedEntries: [                                                 │
│     SheetEntryMatch(                                                │
│       entryId: tavernEntryId,                                       │
│       entryName: "Tavern",                                          │
│       matchLocations: [                                             │
│         .link(mapItemId, .map)  ← Cross-module match!              │
│       ],                                                            │
│       relevanceScore: 25                                            │
│     )                                                               │
│   ],                                                                │
│   expandedLinks: [                                                  │
│     tavernEntryId: [mapItemId]  ← Auto-expand this link            │
│   ],                                                                │
│   crossModuleMatches: [                                             │
│     tavernEntryId: [                                                │
│       CrossModuleMatch(                                             │
│         linkedItemId: mapItemId,                                    │
│         linkedModule: .map,                                         │
│         matchedInItemName: false,                                   │
│         matchedInItemDescription: false,                            │
│         matchedEntryIds: [bathroomEntryId]                          │
│       )                                                             │
│     ]                                                               │
│   ]                                                                 │
│ )                                                                   │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ TableFirstSheetModel.applySearchResults()                                │
│                                                                     │
│ - Filter entries to show only "Tavern" entry                        │
│ - Call expandLinksWithMatches()                                     │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ TableFirstSheetModel.expandLinksWithMatches()                            │
│                                                                     │
│ For "Tavern" entry:                                                 │
│   - Get cross-module match info                                     │
│   - linkedModule = .map (from CrossModuleMatch)                     │
│   - Create ItemRowModel(itemId: mapItemId, typeId: .map)           │
│   - Get Map's ItemControllable via itemControllable(for:)           │
│   - Create sub-TableFirstSheetModel with:                                │
│     * module: .map ← Correct module!                                │
│     * searchText: "Bathroom"                                        │
│     * level: entry.level + 1                                        │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ UI Display                                                          │
│                                                                     │
│ Adventure Sheet:                                                    │
│ ┌─────────────────────────────────────────┐                        │
│ │ ▼ Tavern                                │ ← Expanded             │
│ │   └─ [Map Link] 🗺️ Tavern Floor Plan   │ ← Cross-module link    │
│ │      ┌──────────────────────────────┐   │                        │
│ │      │ Map Sheet:                   │   │                        │
│ │      │ • Bathroom ← MATCH FOUND!    │   │                        │
│ │      │ • Kitchen                    │   │                        │
│ │      │ • Storage                    │   │                        │
│ │      └──────────────────────────────┘   │                        │
│ └─────────────────────────────────────────┘                        │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Points

1. **Module Detection**: Links carry their module information (`.map`, `.adventure`, etc.)

2. **Dynamic Controller Selection**: The search automatically routes to the correct module's `SearchControllable`

3. **Recursive Search**: The expanded Map sheet can have its own links, which could point to other modules

4. **Context Preservation**: Each `TableFirstSheetModel` maintains its module context for proper display and interaction

5. **Relevance Scoring**: Cross-module matches get slightly lower scores (25) vs same-module matches (30)

## Code Path

```swift
// 1. User initiates search
TableFirstSheetModel.performSheetSearch(searchControllable: adventureSearch, searchText: "Bathroom")

// 2. Adventure search finds links
let links = extractLinksWithModules(from: tavernEntry.content)
// → [LinkInfo(itemId: mapId, module: .map)]

// 3. Get Map's search controller
let mapSearch = rootManager.rootModel(for: .map)?.rootController.searchControllable

// 4. Search in Map
let result = await mapSearch.searchInLinkedItem(mapItem, searchText: "Bathroom")
// → LinkedItemMatchResult(matchedEntryIds: [bathroomId])

// 5. Create cross-module match info
CrossModuleMatch(
    linkedItemId: mapId,
    linkedModule: .map,
    matchedEntryIds: [bathroomId]
)

// 6. Expand with correct module
TableFirstSheetModel(
    linkControllable: linkControllable,
    parent: self,
    model: mapItem,
    level: 1,
    module: .map  // ← Uses Map module, not Adventure!
)
```

## Data Flow Summary

```
User Input
    ↓
TableFirstSheetModel (Adventure)
    ↓
SearchControllable (Adventure)
    ↓
Extract Links → Detect .map module
    ↓
RootManager → Get Map's SearchControllable
    ↓
SearchControllable (Map)
    ↓
Find "Bathroom" in Map entries
    ↓
Return CrossModuleMatch
    ↓
TableFirstSheetModel creates sub-sheet with .map module
    ↓
UI displays nested results with module context
```
