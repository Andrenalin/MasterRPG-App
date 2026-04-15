# UI Enhancement Ideas for Cross-Module Search

## Visual Indicators for Cross-Module Matches

### 1. Module Badge on Search Results

Show which module contains the match:

```swift
// In your entry row view
HStack {
    VStack(alignment: .leading) {
        Text(entry.name)
            .font(.headline)
        
        // Show match information
        if let crossMatches = tableSheetModel.getCrossModuleMatches(for: entry) {
            ForEach(crossMatches, id: \.linkedItemId) { match in
                HStack(spacing: 4) {
                    Image(systemName: match.linkedModule.icon)
                    Text("Match in \(match.linkedModule.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(match.linkedModule.tint.opacity(0.1))
                .foregroundStyle(match.linkedModule.tint)
                .clipShape(Capsule())
            }
        }
    }
    
    Spacer()
}
```

**Result:**
```
┌──────────────────────────────────────┐
│ Tavern                               │
│ 🗺️ Match in Maps                    │ ← Module badge
└──────────────────────────────────────┘
```

### 2. Match Detail Popover

Show exactly where in the linked item the match was found:

```swift
Button {
    showMatchDetail.toggle()
} label: {
    HStack {
        Image(systemName: "info.circle")
        Text("\(matchCount) matches")
    }
}
.popover(isPresented: $showMatchDetail) {
    VStack(alignment: .leading, spacing: 12) {
        Text("Cross-Module Matches")
            .font(.headline)
        
        ForEach(crossMatches, id: \.linkedItemId) { match in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: match.linkedModule.icon)
                    Text(match.linkedModule.title)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(match.linkedModule.tint)
                
                if match.matchedInItemName {
                    Label("Item name", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                }
                
                if match.matchedInItemDescription {
                    Label("Item description", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                }
                
                if !match.matchedEntryIds.isEmpty {
                    Label("\(match.matchedEntryIds.count) entries", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)
        }
    }
    .padding()
}
```

**Result:**
```
┌─────────────────────────────────┐
│ Cross-Module Matches            │
├─────────────────────────────────┤
│ 🗺️ Maps                         │
│   ✓ Item name                   │
│   ✓ 2 entries                   │
├─────────────────────────────────┤
│ 📸 Photos                       │
│   ✓ Item description            │
└─────────────────────────────────┘
```

### 3. Colored Link Indicators

Color-code expanded links by their module:

```swift
HStack {
    // Module color indicator
    Rectangle()
        .fill(linkedModule.tint)
        .frame(width: 3)
    
    VStack(alignment: .leading) {
        HStack {
            Image(systemName: linkedModule.icon)
                .foregroundStyle(linkedModule.tint)
            Text(linkedItemName)
        }
        
        // Show nested content
        if isExpanded {
            // Nested sheet content...
        }
    }
}
```

**Result:**
```
Adventure Entry
├─ | 🗺️ Tavern Floor Plan          ← Blue bar = Map module
│  └─ Bathroom ★ Match found!
│
└─ | 📸 Tavern Photo Gallery        ← Purple bar = Photo module
   └─ Front entrance
```

### 4. Search Result Summary

Show module distribution of results:

```swift
struct SearchResultSummary: View {
    let result: SheetSearchResult
    let tableSheetModel: TableSheetModel
    
    var moduleSummary: [NetworkModules: Int] {
        var summary: [NetworkModules: Int] = [:]
        
        for (_, matches) in result.crossModuleMatches {
            for match in matches {
                summary[match.linkedModule, default: 0] += 1
            }
        }
        
        return summary
    }
    
    var body: some View {
        if !moduleSummary.isEmpty {
            HStack(spacing: 12) {
                Text("Matches across modules:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                ForEach(Array(moduleSummary.keys), id: \.self) { module in
                    HStack(spacing: 4) {
                        Image(systemName: module.icon)
                        Text("\(moduleSummary[module] ?? 0)")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(module.tint.opacity(0.15))
                    .foregroundStyle(module.tint)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        }
    }
}
```

**Result:**
```
┌─────────────────────────────────────────────────┐
│ Matches across modules:  🗺️ 3  📸 1  🎵 2     │
└─────────────────────────────────────────────────┘
```

### 5. Breadcrumb Navigation

Show the module path when viewing nested results:

```swift
struct ModuleBreadcrumb: View {
    let tableSheetModel: TableSheetModel
    
    var modulePath: [NetworkModules] {
        var path: [NetworkModules] = [tableSheetModel.module]
        var current = tableSheetModel.parent
        
        while let parent = current {
            path.insert(parent.module, at: 0)
            current = parent.parent
        }
        
        return path
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(modulePath.enumerated()), id: \.offset) { index, module in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: module.icon)
                    Text(module.title)
                }
                .font(.caption)
                .foregroundStyle(module.tint)
            }
        }
    }
}
```

**Result:**
```
🎭 Adventure › 🗺️ Maps › 📸 Photos
```

### 6. Quick Jump to Source Module

Allow users to jump directly to the source module:

```swift
Menu {
    ForEach(crossMatches, id: \.linkedItemId) { match in
        Button {
            // Navigate to the source module
            openModule(match.linkedModule, itemId: match.linkedItemId)
        } label: {
            Label {
                VStack(alignment: .leading) {
                    Text(itemName(for: match.linkedItemId))
                    Text(match.linkedModule.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: match.linkedModule.icon)
            }
        }
    }
} label: {
    Label("Open in Module", systemImage: "arrow.up.forward.app")
}
```

### 7. Match Highlighting in Expanded Links

When a link is auto-expanded, highlight the specific entries that matched:

```swift
ForEach(expandedSheetModel.filteredEntries) { entry in
    let isMatchEntry = crossMatch.matchedEntryIds.contains(entry.source.entryId ?? UUID())
    
    EntryRow(entry: entry)
        .overlay(alignment: .trailing) {
            if isMatchEntry {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .padding(.trailing, 8)
            }
        }
        .background(isMatchEntry ? Color.yellow.opacity(0.1) : Color.clear)
}
```

**Result:**
```
Map: Tavern Floor Plan
├─ Kitchen
├─ Bathroom ★            ← Highlighted match
└─ Storage
```

## Example: Complete Search Result Row

Putting it all together:

```swift
struct CrossModuleSearchResultRow: View {
    let entry: SheetModel
    let tableSheetModel: TableSheetModel
    @State private var showDetails = false
    
    var crossMatches: [CrossModuleMatch] {
        tableSheetModel.getCrossModuleMatches(for: entry)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main entry name
            HStack {
                Text(entry.name)
                    .font(.headline)
                
                Spacer()
                
                if !crossMatches.isEmpty {
                    Button {
                        showDetails.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Module badges for cross-module matches
            if !crossMatches.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(crossMatches, id: \.linkedItemId) { match in
                            CrossModuleBadge(match: match)
                        }
                    }
                }
            }
            
            // Expanded link content (if auto-expanded)
            if tableSheetModel.isExpanded(entry: entry) {
                ForEach(entry.sheetIds, id: \.self) { sheetId in
                    if let subModel = tableSheetModel.sheets[sheetId] {
                        ExpandedLinkView(
                            sheetModel: subModel,
                            highlightedEntries: matchedEntryIds(for: sheetId)
                        )
                        .padding(.leading, 16)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .popover(isPresented: $showDetails) {
            MatchDetailsView(crossMatches: crossMatches)
        }
    }
    
    func matchedEntryIds(for sheetId: ItemRowModel) -> Set<UUID> {
        guard let match = crossMatches.first(where: { $0.linkedItemId == sheetId.itemId }) else {
            return []
        }
        return Set(match.matchedEntryIds)
    }
}

struct CrossModuleBadge: View {
    let match: CrossModuleMatch
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: match.linkedModule.icon)
            Text(matchDescription)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(match.linkedModule.tint.opacity(0.15))
        .foregroundStyle(match.linkedModule.tint)
        .clipShape(Capsule())
    }
    
    var matchDescription: String {
        var parts: [String] = []
        
        if match.matchedInItemName {
            parts.append("name")
        }
        
        if !match.matchedEntryIds.isEmpty {
            parts.append("\(match.matchedEntryIds.count) entries")
        }
        
        return parts.joined(separator: ", ")
    }
}
```

## Accessibility Considerations

1. **VoiceOver Support**:
```swift
.accessibilityLabel("Match found in \(module.title)")
.accessibilityHint("Contains \(matchCount) matching entries")
```

2. **Dynamic Type**:
```swift
.font(.caption)
.dynamicTypeSize(...(.accessibility3))
```

3. **Color Blindness**:
- Use icons alongside colors
- Ensure sufficient contrast
- Provide text alternatives

## Performance Tips

1. **Lazy Loading**: Only load cross-module details when row is visible
2. **Caching**: Cache module icons and colors
3. **Virtualization**: Use `LazyVStack` for large result sets
4. **Debouncing**: Delay search updates to reduce work
