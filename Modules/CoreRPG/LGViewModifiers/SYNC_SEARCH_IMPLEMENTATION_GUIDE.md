# Synchronous Search Implementation Guide

## Overview
This guide explains how to implement the new `syncResults(text:)` method in your search controllers to support the dual-path search architecture.

## Required Changes

### For Each Search Controller (SearchListController, SearchLinkController, etc.)

You need to add a synchronous version of your search that uses only `itemSync` calls (no `await`).

#### Example Pattern:

```swift
extension YourSearchController: SearchRootControllable {
    
    // Existing async version
    @MainActor func results(text: String) async -> [SearchResult] {
        // ... uses await item(for:) ...
    }
    
    // NEW: Synchronous version  
    @MainActor func syncResults(text: String) -> [SearchResult] {
        guard !text.isEmpty else { return [] }
        
        let itemIds = itemControllable.itemDataModel.items
        var foundResults: [SearchResult] = []
        
        for itemId in itemIds {
            // Use itemSync instead of await item(for:)
            guard let item = itemControllable.itemSync(for: itemId),
                  item.groupId == nil,
                  item.displayState == 0 else { continue }
            
            // ... same filtering logic as async version ...
            // ... but use synchronous methods only ...
            
            if item.name.localizedCaseInsensitiveContains(text) {
                foundResults.append(SearchResult(...))
            }
            
            // For entries: iterate synchronously
            for entry in item.entries {
                if entry.filter(with: text) {
                    foundResults.append(SearchResult(...))
                }
            }
        }
        
        return foundResults.sortedByRelevance()
    }
}
```

### Key Differences from Async Version:

1. **No `async` keyword** in function signature
2. **Use `itemSync(for:)`** instead of `await item(for:)`
3. **No `await` calls** anywhere in the function
4. **No `Task.isCancelled` checks** (function completes immediately)
5. **Direct iteration** over collections (no async stream)

### Controllers That Need Updates:

Based on the project structure, you likely need to implement this in:

- `SearchListController` (for folder/collection searching)
- `SearchLinkController` (for character/link searching)
- Any module-specific search controllers (Adventure, Character, Map, Table, Photo, etc.)

## Testing Strategy

### Before & After Timing Comparison

With the logging in place, you can now compare:

```
// OLD (all async):
🔍 [Search] Starting ASYNC search - source: 'listMode.onChange', text: '', displayMode: 1
✅ [Search] Completed ASYNC - duration: 0.007269292 seconds

🔍 [Search] Starting ASYNC search - source: 'update', text: '', displayMode: 1
✅ [Search] Completed ASYNC - duration: 0.002463167 seconds

// NEW (sync for updates):
🔍 [Search] Starting SYNC search - source: 'listMode.onChange.initial', text: '', displayMode: 1
✅ [Search] Completed SYNC - duration: 0.000123456 seconds  ← Much faster!

🔍 [Search] Starting SYNC search - source: 'update', text: '', displayMode: 1
✅ [Search] Completed SYNC - duration: 0.000098765 seconds  ← Much faster!
```

### Expected Performance Gains

- **Initial module load**: Should drop from ~7ms to <1ms
- **Observation updates**: Should drop from ~2.5ms to <0.5ms
- **Mode switches**: Should be nearly instant

### When Async is Still Used

Async search is still used for:
- `scheduleSearch()` - called by `resetParent()` (folder navigation)
- `resetItemOnce()` - initial data load if needed
- Search text changes (not yet implemented, but would go through async path)

## Rollback Plan

If sync search causes issues, you can easily roll back by changing one line in `ListModelUpdatesViewModifier.swift`:

```swift
// Change this:
listControllable.performSyncSearch(source: "listMode.onChange")

// Back to this:
Task { await listControllable.performSearch(source: "listMode.onChange") }
```

And in `FolderListControllable.swift`:

```swift
// Change this:
performSyncSearch(source: "update")

// Back to this:
await performSearch(source: "update")
```

## Next Steps

1. **Implement `syncResults`** in all search controllers
2. **Test** with the new logging to measure improvements
3. **Monitor** for any issues with data not being in memory
4. **Consider** adding sync path for search text changes too (if search is always on in-memory data)

## Notes

- Sync search assumes data is already in `itemDataModel` (loaded from Core Data)
- If you have lazy-loading or pagination, stick with async for those cases
- The sync path is only for filtering already-loaded data
