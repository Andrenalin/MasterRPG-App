# Code Audit — `ItemControllable` / `EditControllable` and their usage

**Scope:** This is a *scoped* audit, not a full-repository audit. The target was every file that conforms to, extends, or directly calls into `Modules/CoreRPG/Controllable/ItemControllable.swift` and `Modules/CoreRPG/Controllable/EditControllable.swift` — the two shared protocols behind create/replace/delete/duplicate/restore/move for every RPG module (Photo, Map, Character, Pdf, Dice, Weather, Adventure, Rule, Generator, Space, Table, Audio). That's ~90 files: the two protocol files themselves, the shared CoreRPG infrastructure they depend on (link register, game-session memory, sync, import/export), all 12 modules' `ItemController`/`EditController` conformances and root wiring, and the 7 SwiftUI editor views that drive them directly.

**Ground truth:** A full clean build (`xcodebuild clean build`, `MasterRPG` scheme, iPhone 17 Pro simulator) completed with **zero warnings, zero errors** under Swift 6.3 `SWIFT_STRICT_CONCURRENCY = complete`. Every concurrency finding below is therefore a logic/ordering issue found by reading isolation and `Task` usage directly, not a compiler-caught one. (An initial build attempt failed with undefined-symbol linker errors — a known stale-EagerLinkingTBD artifact, not a code defect; a clean rebuild resolved it.)

**Method:** Three parallel deep-read passes (concurrency/API modernity; dead code/duplication/refactor; bugs/logic/security/performance), plus a manual SwiftUI pass over the editor views, plus direct verification of every Critical and several High claims by opening the cited files myself.

---

## 1. Executive summary

1. **[Critical] Batch "group edit" tag save silently replaces every selected item's tags instead of merging** — §5.6 — `Modules/CoreRPG/LGViews/GroupEditorView.swift:13-19,35-68,70-89`
2. **[Critical] Duplicating a folder that contains a nested folder shares (aliases) the grandchildren; deleting the duplicate deletes the original's children** — §5.1 — `Modules/CoreRPG/Controllable/EditControllable.swift:415-473`, plus per-module entry models
3. **[Critical] Deleting an item during a live game session leaves it resolvable via `gameItemData`; a later network-pushed edit can permanently resurrect it into CoreData/CloudKit** — §5.5 — `Modules/CoreRPG/ItemList/ItemDataModel.swift:42-45,69-74`, `Modules/CoreRPG/Persistence/CoreDataController.swift:152-175`
4. **[High] The same nested-folder-duplicate defect breaks child references outright (data loss confined to the copy) in Pdf/Dice/Map/Table/Rule, and AdventureRPG's override has no folder-copy logic at any depth** — §5.2, §5.3
5. **[High] Root-model wiring (~150-250 lines × 12 modules) is duplicated verbatim; `GeneratorRootModel` is missing the `listItems`/`itemDataCleanup`/`checkFolders`/`validateLinks` block entirely, and a magic-number `displayState == 2` has already drifted from the one module using the named constant** — §9.3
6. **[High] Link-register startup rehydration spawns one unstructured `Task` per persisted link row with no completion barrier, racing any edit made immediately after launch** — §3.1
7. **[High] A file/photo/PDF picker failure silently clears the item's existing file reference to `nil` instead of surfacing an error** — §5.7
8. **[Medium] `GenericEditController<Model>` — the edit-side sibling of the already-adopted `GenericItemController<Model>` — doesn't exist, so Dice/Space/Audio/Pdf/Generator hand-copy the same boilerplate `EditController`** — §9.1
9. **[Medium] The same ~30-line entry-merge algorithm is independently reimplemented (with already-diverging behavior) in Character/Map/Adventure/Table** — §9.2
10. **[Medium] `insertIntoItems`/`resortItem`/`updates(_:)` — the shared list-maintenance primitives every module's every edit goes through — are O(n) or O(n²) per call** — §7.1

---

## 2. Quick wins

- Delete the 9 redundant `fileUrlDataController` overrides and the 1 redundant `linkRegisterController` override that just repeat the protocol's own default (§9.4).
- Delete the stale, uncompilable-if-uncommented dead comment in `CharacterRPG/Controller/EditController.swift:330-335` (§9.6).
- Remove (or fix, once intent is confirmed) the unreachable guard at `EditControllable.swift:231-233` — `parentItem.isFolder && parentItem.category == .item` can never be true (§5.10).
- Add the missing `Logger.syncDataControllable.error(...)` call to `SyncDataControllable.fetchUpdates()` — its sibling `updateFromSync` already logs the identical failure class (§5.9).
- Route `ItemControllable.addNew(type:)`'s swallowed `try? await dataControllable?.replace(...)` through the same `ItemPersistenceFailureScope.reporter?.record(error)` path every sibling mutation already uses (§5.8).
- Use `DisplayStateMask.totalHidden.rawValue` instead of the bare literal `2` in the 10 root models that still hardcode it, matching `RuleRootModel` (§9.3).

---

## 3. Concurrency

### 3.1 Link-register startup rehydration races edits made right after launch
- **Location:** `Modules/CoreRPG/Links/LinkRegisterController.swift:22-67` (`setup(context:)`), `:193-198` (`nonisolated func updateLink(addedModel:)`)
- **What:** `setup(context:)` fetches every persisted `LinkReferenceDataModel` row inside one `Task(priority:) { await context.perform { ... } }`, and for *each* row calls the `nonisolated` `updateLink(addedModel:)` — which itself opens a brand-new unstructured `Task { @MainActor in model.append(addedModel) }`. One throwaway `Task` per link row, and `setup(context:)` returns without waiting for any of them.
- **Why:** If the user edits and saves an item within the first moments after launch (plausible — the app doesn't block interaction on link-register rehydration), `register(links:)`'s synchronous dedup check runs against a **partially populated** `model.items`, so a link that CloudKit already persisted can be re-registered as a duplicate before its own startup `Task` gets around to appending it — `savePendingLinks()`'s `NSBatchInsertRequest` has no dedup and will happily persist both rows. Verified directly: `updateLink(addedModel:)` is confirmed `nonisolated` and unconditionally opens `Task { @MainActor in ... }` per call (line 194-198).
- **Action:** Collect the parsed `LinkRegisterModel`s inside the single `context.perform` closure into an array, then apply them with one `await MainActor.run { ... }` hop instead of one `Task` per row; have `setup(context:)` return (or be) awaitable so a caller can block edits that register links until rehydration finishes.
- **Severity:** High

### 3.2 Overlapping CloudKit sync notifications aren't coalesced
- **Location:** `Modules/CoreRPG/Controllable/SyncDataControllable.swift:41-83` (`updateFromSync(deletedIds:insertedIds:updatedIds:)`)
- **What:** Spawns a new `Task(priority: .userInitiated) { ... }` on every invocation with no stored handle, no cancellation of a prior in-flight run, and no serialization against overlapping calls.
- **Why:** If change notifications for the same item(s) arrive in quick succession (a bulk pull, or a burst of remote edits), independently-scheduled Tasks race to `delete`/`resetModel`/`mergeUpdates` the same ids with no ordering guarantee — a later notification's effect can be clobbered by an earlier one resolving late. The codebase already has the fix pattern elsewhere: `FolderListControllable.runSearch`/`update(debounce:)` cancel-and-replace via a stored `currentTask`.
- **Action:** Store the returned task and cancel-and-replace it the same way, or otherwise serialize overlapping `updateFromSync` calls.
- **Severity:** Medium

### 3.3 `GameControllable.updateGame` computes its "previously visible" baseline before an await gap
- **Location:** `Modules/CoreRPG/Controllable/GameControllable.swift:347-372`
- **What:** `beforeIds = await gameModel.items` is read, then `try await importNetwork(...)` runs (several actor hops), and only afterward is `beforeIds` used in `gameModel.apply(itemId:item:hide:previousIds:)` to compute newly-revealed items.
- **Why:** `updateGame` isn't itself actor-isolated; a second `updateGame` call landing between the read and the `apply` (two network messages processed back-to-back) can mutate `gameModel.items` in between, making `beforeIds` stale and skewing which items get treated as "newly revealed" and persisted via `replaceForGame`.
- **Action:** Re-read `gameModel.items` immediately before `apply`, eliminating the `await` gap between snapshot and use.
- **Severity:** Medium

### 3.4 Repeated hand-copied fire-and-forget diagnostic `Task {}` boilerplate
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:389-394, 416-421, 483-488, 667-672`; `Modules/CoreRPG/Controllable/ExportControllable.swift:152-155`
- **What:** Five separate sites each open an unawaited `Task { await CloudKitOperationCounter.shared.recordOperation(...) }` (or an equivalent logging call) purely to hop to an async counter/logger from a sync function.
- **Why:** Purely diagnostic, so not itself a correctness bug — but hand-copied five times with no shared helper, and unawaited even at function exit, so under fast app termination the counter update can simply never run.
- **Action:** Factor into one small helper (e.g. `EditControllable.trackOperation(_:)`); have callers that are already `async` (like `delete(itemId:)`) `await` it directly instead of detaching.
- **Severity:** Low

### 3.5 MapRPG's `validateBeforeSave` races its own save with an unawaited cache-invalidation `Task`
- **Location:** `Modules/MapRPG/Controller/EditController.swift:218-228`
- **What:** Spawns `Task { for entryId in changedEntryIds { await root.cacheController?.remove(itemId: entryId) } }` and returns immediately, while `EditControllable.save(with:currentModel:forceSave:)` calls `validateBeforeSave` synchronously and proceeds straight to `saveChanges`.
- **Why:** A render reading the room-thumbnail cache between the save and the Task's completion can briefly show a stale thumbnail for a room whose coordinates just changed. Cosmetic, not data-threatening.
- **Action:** Await the cache removal before returning if ordering matters, or document the fire-and-forget as intentional.
- **Severity:** Low

### 3.6 `EffectedLinkActionPanelView`'s link-tree rebuild has no cancellation
- **Location:** `Modules/CoreRPG/LGViews/EffectedLinkActionPanelView.swift:72-76`
- **What:** `.onChange(of: removeEntryList.removeItems, initial: true) { Task { removeEntryList.linkTree = await ... } }` opens a new unstructured `Task` per change with no cancellation of a previous in-flight one.
- **Why:** Two rapid selection changes (user backs out and re-triggers a different multi-delete before the first async link-scan finishes) can have their completions land out of order, showing `linkTree` for the wrong selection.
- **Action:** Store and cancel the previous Task, or switch to `.task(id: removeEntryList.removeItems)`, which cancels automatically on identity change.
- **Severity:** Low

---

## 4. API modernity

No findings. The 27-file core-infrastructure set was checked line-by-line against this project's house style (no `DispatchQueue.main.async`, no `Task.sleep(nanoseconds:)`, no legacy `Formatter` subclasses, no `String(format:)`, no `.replacingOccurrences`, no `try!`, `localizedStandardContains` used correctly for all user-input filtering, `Id`/`Url` casing followed throughout) and came back clean. This matches the zero-warning clean build.

---

## 5. Bugs / logic errors

### 5.1 Nested-folder duplicate aliases grandchildren; deleting the duplicate destroys the original's children
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:415-473` (`duplicate(item:)`), `:388-413` (`delete(itemId:)`'s recursive folder cascade); `Modules/CoreRPG/Model/ChildEntryModel.swift:30-40`; `Modules/PhotoRPG/Model/PhotoEntryModel.swift:29,40`; `Modules/AudioRPG/Model/AudioEntryModel.swift:29,39`; `Modules/SpaceRPG/Model/SpaceEntryModel.swift:28,39`; `Modules/WeatherRPG/Model/WeatherModel.swift:12,290`; `Modules/GeneratorRPG/Model/GeneratorModel.swift:11`
- **What:** `duplicate(item:)` only rebuilds entries for the *immediate* children of the folder being duplicated (`Model.Entry.newChild(id: dupChild.id)`). If a direct child is itself a folder, that nested folder is copied via the plain `childModel.duplicate()`, which never rebuilds its own `entries`. For Photo/Audio/Space (and everything using the shared `ChildEntryModel`, i.e. Weather/Generator), the entry's `childId` is a **separate stored field** — confirmed directly (e.g. `PhotoEntryModel.duplicate()` mints a new entry `id` but keeps the same `photoId`). So the duplicated nested folder ends up pointing at the exact same real grandchild items as the original.
- **Why:** Sequence: duplicate folder A (containing nested folder B → real grandchildren C/D) → the copy's nested folder B′ still lists the *original* C/D as children → user deletes only the duplicate of A → `EditControllable.delete(itemId:)`'s `if item.category == .folder { await delete(itemId: entry.childId) }` recursion reaches B′ and deletes C and D — permanently destroying the untouched original folder A's real content. This is ordinary, easily-reached usage (duplicate a folder, tweak or discard the copy).
- **Action:** Make the folder-copy step in `duplicate(item:)` recurse into any child that is itself a folder (deep copy, not one level) for both the shared default and every override that reimplements it (§5.3, §5.4).
- **Severity:** Critical

### 5.2 Same defect, different failure mode in Pdf/Dice/Map/Table/Rule: the copy's nested folder is silently emptied
- **Location:** `Modules/PdfRPG/Model/PdfEntryModel.swift:42-43,53-55`; `Modules/DiceRPG/Model/DieModel.swift:104-105,114-116`; `Modules/MapRPG/Model/MapEntryModel.swift:130-131,143-145`; `Modules/TableRPG/Model/TableEntryModel.swift:36-37,46-48`; `Modules/RuleRPG/Model/RuleEntryModel.swift:77-79,89-93`
- **What:** In these modules `Entry.childId` is a *computed property returning the entry's own `id`* (`newChild(id:)` sets `.id` to the target's id directly). `duplicate()` mints a brand-new random `id` — which also changes `childId` to a value matching no real item.
- **Why:** A nested folder's grandchildren aren't aliased to the real originals here (so the original is never corrupted by a later delete of the duplicate) — but the copy's nested folder loses its child references outright, appearing empty after duplication. Confirmed directly by reading each model's `duplicate()`/`childId` definitions.
- **Action:** Same fix as §5.1 — recurse the folder-copy step into nested folders.
- **Severity:** High

### 5.3 AdventureRPG's `duplicate(item:)` override has no folder-copy logic at all — breaks at depth 1, not just depth 2+
- **Location:** `Modules/AdventureRPG/Controller/EditController.swift:226-263` (`duplicate(item:)`/`duplicateSubAdventure`); `Modules/AdventureRPG/Model/AdventureEntryModel.swift:48-60` (`childId { id }`, `duplicate()` mints a new `id`)
- **What:** Unlike the CoreRPG default (§5.1) and CharacterRPG's own override (§5.4), this override completely replaces the base implementation and never checks `model.isFolder` to rebuild folder-membership entries. `duplicateSubAdventure` only fixes up entries with a set `adventureId` (an unrelated "convert to group" feature); a plain folder-membership entry is passed through `entry.duplicate()`, which mints a random `id`, permanently disconnecting it.
- **Why:** Duplicating *any* Adventure folder — even a flat one — produces a copy whose entries all point at nonexistent ids; the duplicate appears completely empty immediately, not just when nesting is involved.
- **Action:** Give AdventureRPG's `duplicate(item:)` the same `if model.isFolder { rebuild via Model.Entry.newChild(id:) }` treatment CharacterRPG has, then extend it to recurse (§5.1's fix) so it doesn't just move the bug one level down.
- **Severity:** High

### 5.4 CharacterRPG's `duplicate(item:)` folder fix-up only covers the outermost level
- **Location:** `Modules/CharacterRPG/Controller/EditController.swift:240-285` (`duplicate(item:)`, `duplicate(itemId:withCopy:)`, `duplicateSubValue`); `Modules/CharacterRPG/Model/ValueEntryModel.swift:216-217`
- **What:** The override explicitly rebuilds `copyFolder.entries` via `Model.Entry.newChild(id:)` — but only once, for the `item` passed directly in. A direct child that is itself a folder is duplicated via `duplicate(itemId:withCopy:false)` → `duplicateSubValue`, which never re-enters that rebuild branch. `ValueEntryModel.childId == id`, and `duplicate()` mints a new `id`, so the nested folder's own children are orphaned in the copy exactly as in §5.2/§5.3.
- **Why:** CharacterRPG mitigates the outermost level only — a Character folder containing a nested folder still produces a copy whose nested folder is silently empty.
- **Action:** Recurse the "rebuild via `newChild`" fix-up into any nested folder found during `duplicate(item:)`.
- **Severity:** High

### 5.5 Deleting an item during a live game leaves a ghost that a later network push can permanently resurrect
- **Location:** `Modules/CoreRPG/ItemList/ItemDataModel.swift:42-45` (`item(for:noGame:)`), `:69-74` (`resetModel(id:)`); `Modules/CoreRPG/Controllable/ItemControllable.swift:121-149` (`delete`), `:156-188` (`replace`), `:207-210` (`syncGameMemoryIfLoaded`), `:284-291` (`replaceForGame`); `Modules/CoreRPG/Controllable/GameControllable.swift:175-184` (`hasItem`), `:206-210` (`reset()`), `:309-372` (`reveal`/`updateGame`); `Modules/CoreRPG/Controllable/CoreDataSnapshotPersistable.swift:33-37` (`replaceSync`); `Modules/CoreRPG/Persistence/CoreDataController.swift:152-175` (`flushPendingOperations`)
- **What:** `ItemDataModel.resetModel(id:)` — the primitive behind every delete — clears `itemData`/`items` but never touches `gameItemData`/`gameItems`. `item(for:noGame:)` prefers `gameItemData` by default, which nearly every read path uses. So `ItemControllable.delete(itemId:...)` can fully remove an item's database row, cache, and file while it's still fully resolvable (with stale data) via every default read path for the rest of the current game session. Verified further, precisely: a subsequent `.persist`-policy network call (`reveal(itemId:data:save:true)` or `updateGame(data:hide:false,...)` — both real production call sites, e.g. `PlayerController+Dice.swift:24`, `PlayerController+Space.swift:79`, `MasterController.swift:1303,1787,1932,2215`) resolves the ghost from `gameItemData`, then calls `replace(model:isInsert:true,forceSave:true)`. Inside `replace`, `itemSync(for:model.id,noGame:true)` reads `itemData` directly (now `nil` since the row is gone) and takes the insert branch: `dataControllable?.replaceSync(...)` → `CoreDataController.queueReplace`. On the next flush, `existingUUIDs` (checked via `batchExists`) does not contain the deleted id, so `flushPendingOperations()` (line 170) creates a **brand-new `DataType(context:)`** and applies the ghost's data to it — confirmed directly: no guard anywhere in this path refuses to re-insert a previously-deleted id.
- **Why:** A GM who deletes a Photo/Pdf/Audio/Space/Character item mid-session (e.g. cleaning up the library while playing), where that item is still loaded from earlier in the session, can have it permanently reappear in the CloudKit-backed store — indistinguishable from an item that was never deleted — the moment any peer resends or a reconnect resync replays a reveal/update message for that id. `gameItemData` is only ever cleared in bulk by `GameControllable.reset()` at explicit game-end, so this window spans the entire remainder of the session.
- **Action:** Have `ItemDataModel.resetModel(id:)` also clear the matching entry from `gameItemData`/`gameItems`. Separately, `replace`'s insert branch should not treat "absent from `itemData`" as sufficient evidence an id is new — track deliberately-deleted ids for the session, or require insert callers to positively confirm the id predates the session.
- **Severity:** Critical

### 5.6 Batch "group edit" tag save replaces instead of merging, silently destroying every selected item's existing tags
- **Location:** `Modules/CoreRPG/LGViews/GroupEditorView.swift:13-19` (`GroupEditorModel.tags` defaults to `[]`), `:35-68` (`processEditorModel` computes a `tagsPlaceHolder` from the items' shared tags but never seeds `GroupEditorModel.tags` with them — there is no `tags:` parameter on `GroupEditorModel.init` at all), `:70-89` (`save()` calls `editController.reset(tags: model.tags, itemId: itemId, forceSave: true)` for every selected id); `Modules/CoreRPG/Controllable/EditControllable.swift:103-112` (`reset(tags:)` — confirmed full-replace semantics: `item.tags = sortedTags`, not a union); `Modules/CoreRPG/Editors/RemoveTagsEditor.swift`, `Modules/CoreRPG/Editors/AddTagsEditor.swift` (confirmed: both operate purely on the bound `tags` array with no independent seeding logic of their own)
- **What:** When the user multi-selects items and opens the batch tag editor, `GroupEditorModel.tags` starts empty regardless of what tags the selected items already share — the placeholder text (`"Boss Undead"`-style joined string) implies existing tags, but the actual editable/removable array is empty. If the user adds even one new tag via `AddTagsEditor` and saves, `GroupEditorController.save()` calls `editController.reset(tags:)` for each selected item, which fully replaces `item.tags` with `model.tags` — i.e. **just the one newly-typed tag** — discarding every tag each selected item previously had.
- **Why:** This is the opposite of the intended editing affordance: `RemoveTagsEditor` is present specifically to let the user review and remove individual existing tags, but it's bound to an array that was never populated with them, so a user has no way to see what they're about to destroy. Contrast with `BatchTextSummaryExtractionView.applyResult(_:to:)` (`Modules/GeneratorRPG/View/BatchTextSummaryExtractionView.swift:245-255`), which also calls `reset(tags:)` with full-replace semantics but explicitly documents "tags replaced" as the intended AI-extraction behavior for that different feature — no such intent is documented or plausible here.
- **Action:** Seed `GroupEditorModel.tags` from the shared/common tag set computed in `processEditorModel` (when `!tagsIsDifferent`), so `RemoveTagsEditor` reflects what's actually there; if items have different tag sets, either disable the remove-based editing for that case or fall back to an explicit "add tags to all" affordance instead of a destructive full replace.
- **Severity:** Critical

### 5.7 Silent file-attach failure clears the item's file reference instead of surfacing an error
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:616-617`
- **What:** `resetFile(url:itemId:)` swallows `fileUrlDataController.createFileUrl(...)`'s thrown error via `try?`, then unconditionally calls `reset(fileUrl: updatedFileUrl, itemId: itemId)` — on failure `updatedFileUrl` is `nil`, explicitly nil-ing the item's `fileUrl`.
- **Why:** A user who just picked a photo/PDF/audio/3D file silently ends up with no file attached and zero indication anything failed — worse than a no-op, since it actively discards the reference the user just created (and, if an old file was already being replaced, that old file was already deleted a few lines earlier in the same function). The sibling `ImportControllable.addFile(data:to:forceSave:)` (`Modules/CoreRPG/Controllable/ImportControllable.swift:601-609`) wraps the equivalent call in `do/catch`, logs, and falls back to the original `fileUrl` instead.
- **Action:** Wrap the `createFileUrl` call in `do/catch`, log the failure, and keep the previous `fileUrl` (or surface an error the header editor can display) instead of nil-ing the reference.
- **Severity:** High

### 5.8 Inconsistent error-swallowing on item creation
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:111`
- **What:** `addNew(type:)` discards any error from `try? await dataControllable?.replace(id: model.id, with: model)` and proceeds unconditionally to add the item to in-memory state.
- **Why:** Every sibling mutation in the same file (`replace`, `delete`, `replaceForExternalImport`, `deleteForExternalImport`) records the error via `ItemPersistenceFailureScope.reporter?.record(error)` or surfaces it via `throws`/`lastPersistenceError`; this is the one silent exception, and it's on the "create a brand new item" path — a transient Core Data failure here leaves an item that looks created in the UI but was never actually written.
- **Action:** Route through the same `ItemPersistenceFailureScope.reporter?.record(error)` pattern the sibling methods already use.
- **Severity:** Medium

### 5.9 `fetchUpdates()` swallows sync failure with no logging, unlike its sibling in the same file
- **Location:** `Modules/CoreRPG/Controllable/SyncDataControllable.swift:85-88`
- **What:** `guard let newItems = try? await dataControllable.fetchAll() else { return }` — any thrown error vanishes with zero logging.
- **Why:** `updateFromSync(deletedIds:insertedIds:updatedIds:)`, in the same file, explicitly logs the identical failure class via `Logger.syncDataControllable.error(...)` specifically so a repeatedly-failing merge is diagnosable. `fetchUpdates()` (the full-table reconciliation run at `start()`) has no such trace — a launch-time sync failure leaves no record of why items never loaded.
- **Action:** Log the caught error the same way `updateFromSync` does.
- **Severity:** Medium

### 5.10 `EditControllable.addItem(itemId:parentId:)` guard can never fire
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:231-233`
- **What:** `if (parentItem.isFolder && parentItem.category == .item) && item.parentId == parentId { return }` — `isFolder` is defined as `category == .folder` (`Modules/CoreRPG/ItemList/ItemDataAccessable.swift:119-121`), so `isFolder && category == .item` requires `category` to equal two different enum cases at once. Confirmed directly: this branch is unreachable.
- **Why:** Whatever early-return this was meant to provide never happens. No concrete resulting failure was found (nearby guards appear to cover the practical cases), but it reads as either a stale condition from a refactor or a typo for a different intended check.
- **Action:** Determine the intended condition and fix it, or delete the dead guard.
- **Severity:** Low

### 5.11 AudioRPG's folder-tree walk has no cycle/depth guard
- **Location:** `Modules/AudioRPG/Controller/ItemController.swift:30-45` (`hasAudio`/`audioList`)
- **What:** Both recurse through `model.entries` via `childId` with no visited-set, unlike the shared `FolderTreeDepthLimit` (`Modules/CoreRPG/Controllable/FolderTreeDepthLimit.swift`) other tree-walkers (`buildFolderTreeNode`, `appendToFlat`, `flattenCachedChildren`) already apply as defense-in-depth.
- **Why:** Should a cycle ever form — including as a side effect of the aliasing in §5.1 corrupting parent/child links — these two functions would recurse indefinitely instead of stopping at a bounded depth like their siblings.
- **Action:** Apply the same depth/visited-set guard used elsewhere.
- **Severity:** Low

---

## 6. Security

No findings. File-path handling in `resetFile(url:)`/`resetFile(data:itemId:path:)` (`EditControllable.swift:587-643`) was checked directly: `baseName` (user-editable item name) is passed through `.appending(component:)`, which percent-encodes rather than risking a malformed/traversal-capable `URL(string:)` construction. Security-scoped resource access (`startAccessingSecurityScopedResource`/`stopAccessingSecurityScopedResource`) is balanced with `defer` on every path checked, including early returns. `FileImporterView`'s remote-URL import path validates against `url.isSupportedRemoteFileURL` before use. No use of user-controlled strings in unsanitized file-path construction was found in the audited set.

---

## 7. Performance

### 7.1 Shared list-maintenance primitives are O(n) or O(n²) per edit
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:527-541` (`insertIntoItems`, `resortItem`), `:408-421` (`updates(_ models:)`)
- **What:** `insertIntoItems` does a linear scan comparing `localizedCompare` against every existing item to find an insertion point; `resortItem` calls `itemDataModel.removeItem` (another linear scan) and then `insertIntoItems` again. Both run on every single edit that changes an item's `name`, in every module, via the shared `replace(model:...)`/`replaceForExternalImport` paths. `updates(_ models:)` (used by `SyncDataController` to reconcile a full CloudKit pull) computes `itemDataModel.items.filter { id in !sortedModels.contains { $0.id == id } }` — an `O(n·m)` nested scan over the full item set.
- **Why:** These are the single most call-frequent primitives behind the two audited protocols. For modules with large libraries (a long-running campaign's Character/Map/Photo collections), every rename becomes an O(n) re-sort, and every cloud sync reconciliation becomes O(n²).
- **Action:** Maintain `itemDataModel.items` as (or alongside) a structure with O(log n) sorted insertion, or keep a `Set<UUID>` index for membership checks so `updates(_:)`'s diff is O(n) instead of O(n·m).
- **Severity:** Medium

*(The link-register startup swarm in §3.1 also has a performance dimension — a few thousand individually-scheduled MainActor hops instead of one at launch — but is filed there since its primary defect is a correctness race, not raw cost.)*

---

## 8. SwiftUI / UI

All 7 editor views wired directly to `ItemControllable`/`EditControllable` (`ItemHeaderEditorView`, `GroupEditorView`, `GroupedPhotoView`, `EffectedLinkActionPanelView`, `FileImporterView`, `CharacterAddEntryOverlay`, `BatchTextSummaryExtractionView`) were read in full. General SwiftUI hygiene is good and consistent with this project's prior audit pass (view extraction into dedicated `View` structs is already done, referenced inline as "CODE_AUDIT §8.2"/"§9.14" from a previous — now-superseded — audit round; accessibility labels are present on icon-only buttons; Dynamic Type is respected; no `GeometryReader`, no misused `onTapGesture`, no hardcoded font sizes; `.scrollIndicators(.hidden)` and modern `FocusState`/`.task` patterns are used correctly).

The two real defects found while reading these views are filed elsewhere by impact: the batch tag editor's data loss is §5.6 (Bugs, since the impact is data destruction, not a UI-only issue), and the two Task-ordering issues in `EffectedLinkActionPanelView` and MapRPG's editor are §3.5/§3.6 (Concurrency).

---

## 9. Dead code / duplication / refactor

### 9.1 `GenericEditController<Model>` — the edit-side sibling of the already-adopted `GenericItemController<Model>` — doesn't exist
- **Location:** `Modules/DiceRPG/Controller/EditController.swift:1-32`, `Modules/SpaceRPG/Controller/EditController.swift:1-26`, `Modules/AudioRPG/Controller/EditController.swift:1-25`, `Modules/GeneratorRPG/Controller/EditController.swift:1-28`, `Modules/PdfRPG/Controller/EditController.swift:23-35`, `Modules/CoreRPG/Controllable/GenericItemController.swift:1-32`
- **What:** `GenericItemController<Model>` exists specifically to eliminate the near-identical per-module `ItemController` struct for modules with no extra stored state (adopted via a one-line `typealias` by Weather/Adventure/Rule/Generator/Table) — but no equivalent was ever built for the edit side, so DiceRPG, SpaceRPG, AudioRPG (and the boilerplate portion of Pdf/Generator) each hand-write the same `EditController` struct: identical stored properties (`itemController`, `tagController`, `editorModel`), identical init, identical `itemControllable`/`fileUrlDataController` computed vars.
- **Why:** The precedent and rationale already exist on the item side but weren't extended to its sibling, so this exact duplication keeps getting re-copied for every new simple module.
- **Action:** Add `GenericEditController<Model>` mirroring `GenericItemController<Model>`; adopt via `typealias EditController = GenericEditController<DiceModel>` etc.; module-specific extras (Pdf's bookmark helpers, Generator's `selectionReference`) can live in a same-file `extension GenericEditController<PdfModel> { ... }`.
- **Severity:** Medium

### 9.2 The same ~30-line entry-merge algorithm is reimplemented (and already diverging) in 4 modules
- **Location:** `Modules/CharacterRPG/Controller/EditController.swift:623-655`, `Modules/MapRPG/Controller/EditController.swift:456-496`, `Modules/AdventureRPG/Controller/EditController.swift:288-325`, `Modules/TableRPG/Controller/EditController.swift:113-149`
- **What:** All four `merge(itemId:entries:...)` bodies implement the same algorithm — match imported entries to existing ones by name, diff removed ids, check `linkRegisterController.used(for:)` on each removed row, then replace-and-save or return the affected rows. `EntryDataEditable` declares both the 3-arg and 4-arg forms as protocol requirements with no default implementation for the 4-arg version (only the 3-arg convenience overload forwards into it).
- **Why:** A bug fix or behavior change (e.g. to the link-safety check) has to be hand-applied 4 times, and drift has already started: AdventureRPG resolves its module via `root.itemController.config.module` instead of the `itemController.config.module` every other copy uses (`AdventureRPG/Controller/EditController.swift:306`), and MapRPG deliberately doesn't thread `forceSave` into its `save(...)` call (documented as intentional at `MapRPG/Controller/EditController.swift:465-468`) while Character/Adventure/Table do. RuleRPG's own `merge` is a genuinely different, better (stable-identity + hierarchy-fallback) algorithm and is not part of this duplication.
- **Action:** Hoist the common "match by name → diff removed ids → check link usage → replace-or-report" skeleton into a default `EntryDataEditable` extension parameterized by a `matches(existing:incoming:)` hook (default: name equality); let Character/Map/Adventure/Table drop their copies, RuleRPG keep its override.
- **Severity:** Medium

### 9.3 Root-model wiring and its cleanup/validation block are duplicated across all 12 modules; one module is silently missing it
- **Location:** `Modules/PdfRPG/Root/PdfRootModel.swift:14-207`, `Modules/DiceRPG/Root/DiceRootModel.swift:8-214`, `Modules/WeatherRPG/Root/WeatherRootModel.swift:10-204`, `Modules/PhotoRPG/Root/PhotoRootModel.swift:8-265`, `Modules/SpaceRPG/Root/SpaceRootModel.swift:8-208`, `Modules/AudioRPG/Root/AudioRootModel.swift:8-200`, `Modules/GeneratorRPG/Root/GeneratorRootModel.swift:8-166`, `Modules/RuleRPG/Root/RuleRootModel.swift:8-248`, `Modules/MapRPG/Root/MapRootModel.swift:30-270`, `Modules/TableRPG/Root/TableRootModel.swift:13-242`, `Modules/CharacterRPG/Root/CharacterRootModel.swift:15-274`, `Modules/AdventureRPG/Root/AdventureRootModel.swift:21-377`
- **What:** Every root model repeats the identical construction sequence (config → navigation/selection models → item/edit/link/export/game/import/search/view/folder-list controllers → `ItemRootController(...)` with the same 16 named arguments), plus near-identical `listItems()`/`itemDataCleanup()`/`checkFolders(reportModel:)`/`validateLinks(reportModel:)` bodies. Confirmed directly: `CharacterRootModel.swift:214` hardcodes `model.displayState == 2` while `RuleRootModel.swift:231` alone uses `DisplayStateMask.totalHidden.rawValue` for the same check — same value today, silent trap for the next edit. Also confirmed directly: `GeneratorRootModel.swift` (187 lines total) has **no** `listItems`/`itemDataCleanup`/`checkFolders`/`validateLinks` block at all.
- **Why:** The largest duplicated surface in the audited set (~150-250 lines × 12 files). The `GeneratorRootModel` gap means Generator items never participate in the app-wide repair/validate/cleanup passes every other module's items get for free — worth confirming with the team whether that's deliberate.
- **Action:** Extract a shared root-builder (a `ModuleRootBuilding` protocol extension keyed on the module's controller types) for the constructor wiring, and a single generic default for the cleanup/validate block using `DisplayStateMask.totalHidden`.
- **Severity:** High

### 9.4 No-op protocol-default overrides
- **Location:** `Modules/PdfRPG/Controller/EditController.swift:41`, `Modules/DiceRPG/Controller/EditController.swift:28-30`, `Modules/AdventureRPG/Controller/EditController.swift:90-92`, `Modules/CharacterRPG/Controller/EditController.swift:62`, `Modules/PhotoRPG/Controller/EditController.swift:30`, `Modules/MapRPG/Controller/EditController.swift:67-69`, `Modules/SpaceRPG/Controller/EditController.swift:25`, `Modules/TableRPG/Controller/EditController.swift:57`, `Modules/AudioRPG/Controller/EditController.swift:24`, `Modules/RuleRPG/Controller/EditController.swift:64-67`
- **What:** `EditControllable`'s own extension already provides `fileUrlDataController` (`EditControllable.swift:39`) and `linkRegisterController` (`:43`) defaults. Nine modules re-declare `fileUrlDataController` with the byte-identical body, and RuleRPG separately re-declares `linkRegisterController` identically. Only Weather/Rule(partially)/Generator correctly rely on the default.
- **Why:** Pure copy-paste noise — a reader has to check whether each override actually differs from the default rather than trusting that anything present is a real customization.
- **Action:** Delete all 10 redundant overrides.
- **Severity:** Low

### 9.5 CharacterRPG and AdventureRPG duplicate their entire "group orphan-handling" trio line-for-line
- **Location:** `Modules/CharacterRPG/Controller/EditController.swift:344-353` vs `Modules/AdventureRPG/Controller/EditController.swift:184-192` (`isOrphanedHidden`); `:355-360` vs `:194-199` (`willRepairOrphan`); `:362-374` vs `:201-211` (`willRestore`)
- **What:** These are the only two modules in the whole codebase that override these three hooks (confirmed via repo-wide grep), and all three bodies are identical except for the concrete model type — same `groupId`-based orphan logic, same repair-on-parent-loss rule, same restore-time cleanup.
- **Why:** Two modules independently reinvented the same "groupable item" concept; a future fix to this orphan-handling logic has to be applied twice, and a third module adding grouping would likely copy-paste a third time.
- **Action:** Introduce a shared `GroupableModel { var groupId: UUID? { get set } }` protocol both models already structurally satisfy, and hoist the three methods into an `EditControllable`/`EntryDataEditable` extension constrained to it.
- **Severity:** Medium

### 9.6 Stale dead comment in CharacterRPG
- **Location:** `Modules/CharacterRPG/Controller/EditController.swift:330-335`
- **What:** `//root.gameController.resetGameDiceId(itemId: model.id, entryId: entryId)` is commented out and references `model`/`entryId`, neither of which exists in this function's scope (only `item`/`itemId` do) — confirming it's leftover from an earlier refactor.
- **Why:** Dead, uncompilable-if-uncommented code adds confusion about whether a dice-reset side effect belongs here.
- **Action:** Delete the comment.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

- **Add a "duplicate a folder-of-folders" regression test, once, at the protocol level.** §5.1-§5.4 are one systemic defect (the `duplicate()`/`childId` contract isn't recursive and isn't uniformly honored) expressed four different ways across modules. A single shared test that duplicates a 2-level-deep folder in each module and asserts the grandchildren survive independently would have caught all four as one issue instead of four separate patches — and would guard against a fifth module reintroducing it.
- **Design-review the `gameItemData`/`itemData` split once, rather than patching call sites.** §5.5 is the same class of bug this codebase's own history already shows recurring (per project memory: battle-round health sync, "highlight resets health to nil") — game-session memory silently diverging from permanent state. Worth a deliberate answer to "what happens to game-memory state when the permanent item is deleted/edited mid-session," not another one-off fix.
- **Pick one persistence-error convention and apply it everywhere.** The audited files show three different patterns side by side: `throws` + `lastPersistenceError`, `ItemPersistenceFailureScope.reporter?.record(error)`, and silent `try?` (§5.7, §5.8, §5.9). New code has no clear default to reach for.
- **Extend the `GenericItemController<Model>` precedent to the edit side and to root-model wiring** (§9.1, §9.3) — the pattern already exists and is already trusted for the item controllers; not using it for the two even-larger duplicated surfaces looks like an oversight rather than a deliberate choice.
- **A lint-style "does this override actually differ from the default?" pass** would catch §9.4-class duplication automatically going forward, given how much of it accumulated silently.

---

## 11. What was NOT audited

- The rest of the app beyond `ItemControllable`/`EditControllable` usage: GameRPG's Table3D/visionOS scene code, MapEditor's room-carving canvas, FoundationModels-based generation logic in GeneratorRPG beyond the one batch-extraction view, the widget extension, and CloudKit conflict-resolution internals not reached through these two protocols.
- Algorithmic correctness of Metal/RealityKit rendering code.
- Xcode project/build settings and scheme configuration, beyond confirming the clean build.
- Third-party SPM package internals (`RPGTabletopGameContent`).
- Localization wording quality (only structural `bundle: .module` usage was checked).
- Full test-suite review — test files that reference these protocols were identified (`Tests/GameRPGTests/PlayerControllerTests.swift`, `Tests/CharacterRPGTests/EditControllerTests.swift`, `Tests/MapRPGTests/EditControllerTests.swift`, `Tests/PhotoRPGTests/FolderListControllerTests.swift`, `Tests/CoreRPGTests/LinkHighlightTextModelTests.swift`) but not deeply reviewed for coverage gaps against the bugs found in §5.
- Views and gameplay UI not directly wired to these two protocols (most live game-mode screens, the 3D map table view, the map editor canvas).
- `Modules/CoreRPG/Simple/*` and `Modules/CoreRPG/Fake/*` beyond a dead-code check — confirmed intentionally-trivial test doubles, not reviewed as production logic.

---

## 12. Verification

- **§5.1** — open `Modules/CoreRPG/Controllable/EditControllable.swift:415-473` (one-level-only recursion), `Modules/CoreRPG/Model/ChildEntryModel.swift:38-40` and `Modules/PhotoRPG/Model/PhotoEntryModel.swift:40-41` (duplicate keeps `childId`/`photoId` unchanged) — confirmed by direct read.
- **§5.2** — open `Modules/PdfRPG/Model/PdfEntryModel.swift:42-43,53-55` and `Modules/AdventureRPG/Model/AdventureEntryModel.swift:48-60` (`childId { id }`, `duplicate()` mints a new `id`) — confirmed by direct read.
- **§5.3** — open `Modules/AdventureRPG/Controller/EditController.swift:226-263` — no `isFolder` branch present — confirmed by direct read.
- **§5.4** — open `Modules/CharacterRPG/Controller/EditController.swift:240-285` — rebuild happens once, not on recursive calls — confirmed by direct read.
- **§5.5** — open `Modules/CoreRPG/ItemList/ItemDataModel.swift:42-45,69-74` (gameItemData never cleared by resetModel), `Modules/CoreRPG/Persistence/CoreDataController.swift:152-175` (line 165-172: `existingUUIDs.contains` false → `DataType(context:)` created fresh, no guard against a previously-deleted id) — confirmed by direct read, including tracing `replaceSync` → `queueReplace` → `flushPendingOperations` end to end.
- **§5.6** — open `Modules/CoreRPG/LGViews/GroupEditorView.swift:13-19,35-68` (no `tags` parameter on `GroupEditorModel.init`, `processEditorModel` never assigns the computed `tags` local into the model) and `Modules/CoreRPG/Controllable/EditControllable.swift:103-112` (`reset(tags:)` sets `item.tags = sortedTags`, a full replace) — confirmed by direct read, including `RemoveTagsEditor.swift`/`AddTagsEditor.swift` to rule out independent seeding.
- **§5.7** — open `Modules/CoreRPG/Controllable/EditControllable.swift:605-618` — `try?` immediately followed by an unconditional `reset(fileUrl: updatedFileUrl, ...)` — confirmed by direct read.
- **§3.1** — open `Modules/CoreRPG/Links/LinkRegisterController.swift:22-67,193-198` — `nonisolated func updateLink` opens `Task { @MainActor in model.append(...) }` per call, invoked once per fetched row inside `setup(context:)`'s loop — confirmed by direct read.
- **§9.3** — open `Modules/GeneratorRPG/Root/GeneratorRootModel.swift` (187 lines, no `listItems`/`itemDataCleanup`/`checkFolders`/`validateLinks`) and compare `Modules/CharacterRPG/Root/CharacterRootModel.swift:214` (`displayState == 2`) against `Modules/RuleRPG/Root/RuleRootModel.swift:231` (`DisplayStateMask.totalHidden.rawValue`) — confirmed by direct read/grep.
- Build ground truth — `xcodebuild -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 17 Pro' clean build` → `** BUILD SUCCEEDED **`; a follow-up Xcode MCP build and `GetBuildLog`/`XcodeListNavigatorIssues` pass at `warning`/`remark` severity returned zero entries.
