# Core A (Controllable, Import, Links, LinkRenderer, CRDT, Parser, Route, Concurrency) - audit 2026-11-14

Files read: all of Modules/CoreRPG/Controllable (39 files, ~9.0k LOC; the big ones whole: ItemControllable, EditControllable, EditControllable+File, ImportControllable, ExportControllable, GameControllable, LinkControllable, FolderList*, Search*, Sync*, TagController, ConvertController), Import/ (1.8k, whole), Links/ (1.1k), LinkRenderer/ (0.85k), CRDT/ (0.67k), Parser, Route, Concurrency: ~13.7k LOC in total. Overall health is very good: the many earlier audit fixes are visible in the code, there are no force unwraps or `try!` on reachable paths, CRDT merge is deterministic, import framing is bounded, rollback paths are careful. Remaining issues are one real data-loss path (file replacement during a running game), one missing hydration guard (tags), and a set of Low items. Nothing here is Critical.

### File replacement during a running game deletes the file the library item still references
- Category: Bug
- Location: Modules/CoreRPG/Controllable/EditControllable+File.swift:131-187 (`replaceFile`, esp. 177-181), 239-280 (`writeFile`, 276-279); callers without forceSave: Modules/CoreRPG/FileViews/FileReplacementConfirmation.swift:69, Modules/PhotoRPG/Controller/EditController.swift:73
- What: `replaceFile` / `writeFile` store the new `FileUrl` with `reset(fileUrl:itemId:)` (forceSave false), which in game mode lands in game memory only (`ItemControllable.replace` -> `replaceInGameMemory`), and then delete the old stored file via `deleteReplaced`; the "used elsewhere" check (`isFileUsedElsewhere(..., excluding: itemId)`) deliberately excludes the item itself, so the library copy that still points at the old file is not considered.
- Why: GM replaces a photo/PDF/3D file of an item in the editor while a game runs -> the new file is only in game memory, the old file is removed from disk/iCloud; when the game ends (game memory dropped) the library item references a deleted file (data loss). Only the Intents path passes `forceSave: true` (writeFile) and knows about this; `resetFile(url:)` has no forceSave parameter at all and FileImporterView/ItemDetailContentView/InlineImporterView do not gate on `isGameMode`. Not reproduced at runtime.
- Action: In game mode either persist the new file on the library item (`persistFileUrl`, as `copyFile` and `movedFileTree` already do) or skip deleting the old file until the library item references the new one; add a `forceSave` parameter to `resetFile(url:)`. Add a test with `isGameMode = true`.
- Severity: High
- Status: NEW

### Full reconciliation can drop an item added while it awaits
- Category: Bug
- Location: Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:114-157
- What: `unsavedInsertIds` is snapshotted before the `await delete(...)` loop and the `await invalidateCacheForChangedFile` loop; an `addNew` that completes during those suspensions is neither in the fetched models nor in the snapshot, so `resetItems(updatedItems)` removes it from `itemDataModel.items` while its model stays in memory.
- Why: Only on full reconciliation (launch, store swap, failed sync batch), so narrow; the item then is missing from lists/exports until the next relaunch (later sync notifications merge it but never re-list it).
- Action: Re-read `dataControllable.unsavedInsertIds()` and the current `items` after the last suspension and union them into `updatedItems`.
- Severity: Low
- Status: NEW

### `ItemGameModel.append/insert` are not idempotent
- Category: Bug
- Location: Modules/CoreRPG/Controllable/GameControllable.swift:82-90, callers 214-219 (`hasItem`), 225-236 (`setCurrent`)
- What: Both callers check "not present" before an `await` and add afterwards without re-checking; two interleaved calls for the same id add it twice to `gameItems`.
- Why: Duplicate ids in the game list (two rows / wrong `currentItemId` semantics) when e.g. two availability checks for one shared pin photo overlap. Not reproduced.
- Action: Make `append`/`insert` skip an id that is already in `items` (and move to front for insert).
- Severity: Low
- Status: NEW

### Imported file name derived with `replacing(ext, with: "")` removes every occurrence
- Category: Bug
- Location: Modules/CoreRPG/Controllable/EditControllable+File.swift:162-164
- What: The item name from a picked file is `lastPathComponent.replacing(".pdf", with: "")`, which strips the extension text everywhere in the name, not only the suffix.
- Why: "Rules.pdf v2.pdf" becomes "Rules v2"; "a.png.png" becomes "a".
- Action: Use `deletingPathExtension` (or `URL.deletingPathExtension().lastPathComponent`).
- Severity: Low
- Status: NEW

### Export id collection is quadratic for large folders
- Category: Performance
- Location: Modules/CoreRPG/Controllable/ExportControllable.swift:126-141 (`exportingFolder` rebuilds the parent's valid child list per processed child), 172-190 (`bfsExportResults` uses `checkIds.contains` on an array)
- What: Both loops do an O(n) scan per element.
- Why: Exporting/sharing a folder of thousands of items does millions of `itemSync` lookups / comparisons on the main actor before the export starts.
- Action: Count children per folder once (dictionary of remaining ids) and keep a `queued` Set next to `checkIds`.
- Severity: Low
- Status: NEW

### Import progress never reaches the total when items fail or are rejected
- Category: Bug
- Location: Modules/CoreRPG/Controllable/ImportControllable.swift:280-289 (peer folder / policy-rejected `continue`), 315-320 (per-item catch); `importedItems` is only incremented in `applyImportedItem`
- What: A failed, undecodable, rejected or never-admitted peer-folder item counts toward `counter` but not toward `importedItems`.
- Why: `isFinalizingImport` (`importedItems >= totalImportingItems`) stays false and the progress bar stops short for a partly failed file; cosmetic, `failedItems` is reported separately.
- Action: Increment a processed counter (or `importedItems`) in the failure/rejection paths too.
- Severity: Low
- Status: NEW

### Folder membership sort looks up names per comparison
- Category: Performance
- Location: Modules/CoreRPG/Controllable/EditControllable.swift:410-416
- What: Adding an item to a folder re-sorts all entries with a comparator that does two `nameSync` lookups per comparison.
- Why: n log n dictionary lookups plus `localizedStandardCompare` per single add; an import of n items into one folder repeats it n times.
- Action: Map to (name, entry) once, or insert at the binary-search position.
- Severity: Low
- Status: NEW

### Export fallback loads the whole finished export into memory
- Category: Performance
- Location: Modules/CoreRPG/Controllable/ExportControllable.swift:292-297
- What: When `replaceItemAt` fails, `Data(contentsOf: finished).write(...)` reads the entire export (can contain GBs of PDFs/USDZ).
- Why: Memory spike / jetsam on the fallback path.
- Action: Use `copyItem` after removing the destination, or stream with a FileHandle.
- Severity: Low
- Status: NEW


### Tag register has no hydration-failure guard and can overwrite in-memory edits when it loads
- Category: Bug
- Location: Modules/CoreRPG/Controllable/TagController.swift:26-60 (`setup`), 134-189 (`savePendingTags`)
- What: A failed or non-castable fetch in `setup` returns an empty dictionary (`catch { return [:] }`), so the in-memory tag table is empty and `savePendingTags` then treats every persisted row of an affected module as stale and deletes it (CloudKit-mirrored, so on all devices). `LinkRegisterController` got a `hydrationFailed` guard for exactly this (CODE_AUDIT_23 §5.12); `TagController` did not. The hydration also merges with `{ _, new in new }`, so persisted counts replace counts of tags added in memory before the fetch finished.
- Why: One transient fetch error followed by any tag edit wipes that module's tag suggestions on every device; counts drift after a slow first fetch. Rare, but silent and replicated.
- Action: Mirror the link register: track `hydrationFailed`, retry the fetch before saving, skip the save while it is failing; merge by adding persisted counts only for tags not touched in memory (or apply hydration before accepting edits).
- Severity: Medium
- Status: NEW

### Files over 500 LOC that split cleanly
- Category: Refactor
- Location: Modules/CoreRPG/Controllable/ImportControllable.swift (1145), EditControllable.swift (1029), ItemControllable.swift (810), GameControllable.swift (550)
- What: ImportControllable holds the import model, `PeerImportPolicy`, the stream loop, manual-review logging (722-852, ~130 LOC of log-only diffing) and the `InputStream` framing extension (1067-1145). EditControllable mixes basic properties, groups, folder/collection membership (328-517), delete/duplicate/restore/remove (574-879) and undo. ItemControllable mixes CRUD with the whole game-to-library persistence set (`persistFromGame`, `persistMissingFolders`, `persistMembershipChange`, file settle helpers, 282-455). GameControllable carries `ItemGameModel` (6-148) next to the protocol.
- Why: The three files are the shared core of every module; each unrelated change touches a 1000-line file and its merge surface.
- Action: Move `PeerImportPolicy`/`ItemDataImportModel` and the `InputStream` extension to `ImportModels.swift`/`InputStream+GmzFraming.swift`, the review-log helpers to `ImportControllable+ReviewLog.swift`; split EditControllable into `+Folders`, `+Delete`, `+Undo` (EditControllable+File is the precedent); move the game persistence block to `ItemControllable+GamePersistence.swift`; move `ItemGameModel` to its own file.
- Severity: Medium
- Status: NEW

### Folder-entry merge order depends on the device locale
- Category: Bug
- Location: Modules/CoreRPG/CRDT/FolderEntryMerge.swift:29-35
- What: The merged entries are sorted with `localizedCompare` although the doc comment claims a deterministic order on every device; `localizedCompare` follows the device's locale (e.g. German vs. English collation of umlauts, case, punctuation).
- Why: Two devices merging the same two replicas can end with different entry orders (and, via the `childId` de-duplication that keeps the first in that order, a different surviving entry id when names differ), so equality checks/`isSame` differ between replicas and a repair may rewrite and re-sync the folder.
- Action: Sort by a locale-independent key (`name.compare(_, options: [.literal])` or the raw string, then `uuidString`).
- Severity: Low
- Status: NEW

### Strings not localized through the module bundle
- Category: API
- Location: Modules/CoreRPG/Controllable/ContextMenuMultiController.swift:30-36 (`"\(model.name) and \(selection.count - 1) more"`, shown as menu/dialog title via FolderPlacementMenu.swift:15, ListRootContextMenu.swift:68); Modules/CoreRPG/Controllable/EditControllable.swift:140 (`"Change to \(hidden ? "hide" : "show")"` interpolates raw English words into a localized key)
- What: A user-visible title is built from an English literal; the undo title localizes only the prefix.
- Why: German (and other) users see English "and 3 more" / "Change to hide".
- Action: Use `String(localized: "\(name) and \(count) more", bundle: .module)` with plural variations; use two localized keys for hide/show.
- Severity: Low
- Status: NEW

### `ImportItemRepair.normalizedTags` writes a localized title into persisted tags and can duplicate it
- Category: Bug
- Location: Modules/CoreRPG/Controllable/ImportItemRepair.swift:20-23
- What: The legacy category's `title` (localized for the importing device's language) is prepended to the tags without a duplicate check.
- Why: The same legacy item imported on an English and a German device gets different tags; an item that already carries that tag gets it twice.
- Action: Use a stable (non-localized) tag name or de-duplicate before sorting.
- Severity: Low
- Status: NEW

### Link register: empty arrays stay in the dictionaries and hydration is quadratic per destination
- Category: Performance
- Location: Modules/CoreRPG/Links/LinkRegisterListModel.swift:157-186 (`append` scans `items[destination]` for each link; `remove` uses `default: []` which inserts empty keys), Modules/CoreRPG/Links/LinkRegisterController.swift:80-82
- What: Hydrating N links to one hot destination does N linear `isSameOccurrence` scans, and `remove`/`removeLinks` leave `[]` entries behind in `items`/`sourceItems`.
- Why: A destination with thousands of incoming links makes launch hydration O(N^2) on the main actor; empty keys are a small leak and make `isUsed` rely on the `isEmpty` check.
- Action: Keep a `Set` of occurrence ids per destination for the dedup check; remove a key when its array becomes empty.
- Severity: Low
- Status: NEW

### `WallclockTimestamp.<` allocates two strings per comparison
- Category: Performance
- Location: Modules/CoreRPG/CRDT/WallclockTimestamp.swift:104-106 (`(lhs.clock, lhs.id) < (rhs.clock, rhs.id)` where `id` is `description`)
- What: The tie-break compares `description` strings (`"[clock-actor]"`) built on each call instead of the `actorId`.
- Why: Every field merge of every item allocates; semantics are the same as comparing `actorId` because equal clocks print identically.
- Action: Compare `(lhs.clock, lhs.actorId) < (rhs.clock, rhs.actorId)`.
- Severity: Low
- Status: NEW

### Duplicated helpers
- Category: Duplication
- Location: Modules/CoreRPG/Controllable/SearchListController.swift:45-66 vs 126-147 (`syncExpandResults` folder branch, identical); Modules/CoreRPG/Controllable/GenericGameController.swift:26-42 vs 69-85 (`gameItem`/`setGame`/`currentItem` twice)
- What: Two copies each of the folder/collection child expansion and of the three game helpers.
- Why: A fix (e.g. the stale-entry rule: expansion lists `entries`, delete only children whose `parentId` matches) has to be applied twice.
- Action: Extract the folder branch to a shared function on `SearchControllable`; let `GenericGameController` adopt `ModuleGameControllable`'s defaults or move the helpers onto `ItemGameModel`.
- Severity: Low
- Status: NEW

### Dead parameter and style-rule violations in link views
- Category: Dead code
- Location: Modules/CoreRPG/Links/DragOverlayViewModifier.swift:11,23-25 (`isMove` is accepted by both `draggableWithOverlay` overloads and never forwarded; no caller passes it), :33-35 (hard-coded `.padding(.horizontal, 12)`/`.padding(.vertical, 6)`); Modules/CoreRPG/LinkRenderer/LinkHighlightTextView.swift:36 (`.lineSpacing(4)`); Modules/CoreRPG/Controllable/ViewControllable.swift:58-94 and Modules/CoreRPG/Route/InternalRoute.swift:34-38 (`AnyView` factories)
- What: Unused API parameter; hard-coded spacing and `AnyView` contrary to CLAUDE.md.
- Why: Misleading API; style rules.
- Action: Remove `isMove` from the two overloads; use default padding; replace the `AnyView` returns with `some View`/generic or accept them as a documented erasure boundary.
- Severity: Low
- Status: NEW

### Text renderer posts a Task on every draw pass
- Category: Performance
- Location: Modules/CoreRPG/LinkRenderer/LinkHighlightTextRenderer.swift:95-97
- What: `draw(layout:in:)` creates `Task { @MainActor }` for every pass, including every animation frame of the expand effect, to publish the link measurements.
- Why: A task per frame per visible link text; the equality guard in `LinkHighLightLocations.replace` makes it cheap but still allocates and hops.
- Action: Skip the task when the measurements equal the last published ones (compare before dispatching).
- Severity: Low
- Status: NEW

### User text containing the expansion marker emoji is treated as markup
- Category: Bug
- Location: Modules/CoreRPG/LinkRenderer/LinkHighLightLocations.swift:104-110 (`begin = "➡️"`, `end = "⬅️"`), Modules/CoreRPG/LinkRenderer/String+Link.swift:27-47, LinkHighlightTextModel.swift:155-175
- What: Expanded link content is stored inline in the text between the two emoji; a user who types a balanced "➡️ ... ⬅️" pair in a description gets it rendered as an expanded link block, and `toggleLink` may cut text that follows a link.
- Why: Rare, cosmetic/data-visible; collapsing can delete user text after a link.
- Action: Use private-use or otherwise unlikely marker characters, or escape user occurrences on load.
- Severity: Low
- Status: NEW

### Test gaps
- Category: Test gap
- Location: Tests/ (no test covers `EditControllable.resetFile(url:)`/`writeFile` with `isGameMode == true`; `TagController.setup` failure path; `FolderEntryMerge` under a non-English locale; `ItemControllable.updates` racing an `addNew`)
- What: The risky paths of the findings above are untested (`Tests/PhotoRPGTests/FolderAuditPhotoTests.swift:121` is the only game-mode test touching files and covers moves).
- Why: Regressions in the shared core hit all 12 modules.
- Action: Add a CoreRPG test for file replacement in game mode (library item keeps a valid file), a tag hydration-failure test, and a locale-pinned folder merge test.
- Severity: Medium
- Status: NEW

Not audited in this area: view-level behaviour of FileViews/ItemList/EntryEditor (outside the listed folders), `SearchControllable+Inspector.swift` and `ViewControllable.swift`/`SheetControllable.swift`/`GenericItem*` (skimmed only), `LinkRegisterModel` consumers in other modules, the 12 module-specific `merge` implementations, runtime behaviour (nothing was run or built).
