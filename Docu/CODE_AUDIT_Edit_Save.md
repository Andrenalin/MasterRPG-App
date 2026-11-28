# MasterRPG Code Audit — Editing inside and outside a game (links, save, sync, game-edit specials)

Generated 2026-11-28 against `develop` at `64f359ee0` ("changed: all modules allow edits during the game"). **Scoped audit**: the item/entry edit pipeline — `EditControllable*`, `ItemControllable*` (replace, game persistence, sync, delete), `ItemDataAccessible+ApplyEdit` (forced game-copy diff), `EntryDataEditable`, `GroupableEntryEditing`, `ItemEditorModel`/undo, `SyncDataControllable`, `LinkRegisterController`/`LinkControllable`/module `LinkController.validateLinks`, every module `EditController` and `*+ApplyEdit`, the sheet editor (`SheetRootModel+*`), entry/quick editors, and the GameRPG paths that carry GM and player edits.

**Compiler ground truth:** `xcodebuild clean build` (MasterRPG scheme, iPhone 18 Pro, Swift 6.3, `SWIFT_STRICT_CONCURRENCY = complete`) succeeded with **zero Swift warnings** (only two `appintentsmetadataprocessor` "no AppIntents dependency" notices). Every concurrency finding below is therefore an ordering/logic issue found by reading, not a compiler diagnostic.

**Method:** three parallel deep-read passes (concurrency & save/undo/sync ordering; forceSave threading, duplication & dead code; bugs in links/save/sync/game specials), plus my own read of the core path. Every High was re-opened and verified by me (see §12). No code was changed. Findings already marked fixed in `Docu/CODE_AUDIT_EditItem.md` and `Docu/CODE_AUDIT_29.md` are not repeated.

**Positive baseline (checked and correct):** `writeForcedEditOfGameCopy` diffs the register against the stored library value and applies `libraryWriteFilter`; `applyModuleEdit` covers every persisted module property (Pdf/Audio need none; Map content is session-only by decision); `persistsEdit` gates tags and register in `saveChanges`/`reset`; game memory always gets a `copy()`; sync batches are applied in order by one consumer; `delete` leaves memory before its first suspension; the per-item file queue serializes move/replace/copy; no `try!`/`as!`/`fatalError`/`DispatchQueue`/`nonisolated(unsafe)` in the edit path.

---

## 0. Status (2026-11-28)

Fixed on `develop` (uncommitted). User decisions: undo as scoped delta steps; §5.10 package version including metadata (no protocol change, players download the package once more); all four refactors (required write policy, isolated conformances, dedupe, split files); §5.24 re-announce the Character.

| § | Status |
|---|---|
| 3.1 | Fixed: the sync insert/update paths merge with a queued or in-flight local edit (`hasPendingOperation(for:)`, `mergeUpdates(model:keepingLocalEdit:)`). Test `EditSaveAuditTests.syncMergeKeepsQueuedLocalEdit`. |
| 3.2 | Fixed: `convertToGroup` creates the group first, then reads the host inside one undo step. |
| 3.3 | Fixed: Photo `convert` runs on the per-item file queue and drops its result when the file changed meanwhile. |
| 3.4 | Fixed: the replaced-file removal re-checks use (also the game copy) on the main actor before deleting. |
| 3.5 | Partly: `ItemDataModel.stopSyncConsumer()` exists; no teardown hook calls it yet (roots live for the app's lifetime). |
| 3.6 | Fixed: Map `validateBeforeSave` returns early without changed entries; `save` validates only after the equality guard. |
| 3.7 | Fixed: the sheet group actions re-check the shown item after the await. |
| 4.1 | Partly: every model conforms plainly to the `@MainActor` protocols `ItemDiffComparable`/`ItemDuplicatable` (no `assumeIsolated`). `Equatable`/`Comparable`/`Hashable` stay `nonisolated`: `ItemDataAccessible` refines `Sendable`, which rules out isolated conformances (would need `Sendable` dropped from `ItemDataAccessible`). |
| 5.1–5.7 | Fixed: undo steps are per-item before/after deltas with scope (current/forced/library) and game generation, applied with the three-way `applyEdit` (no `fileUrl`); a step from another game generation is dropped; a deleted item is skipped; one user action = one step (`asOneUndoStep`, `beginUndoGroup`); forced undo updates tag counts. Tests `EditSaveAuditTests`, `UndoManagedDepthTests`. |
| 5.8 | Fixed: the folder detach takes the operation's write policy. Tests `moveIntoGroup…`. |
| 5.9 | Fixed: `addNew(type:forceSave:)`/`insertNew` follow the write policy (memory-only create during a game). |
| 5.10 | Fixed: Photo/Pdf/Space publish a package version (file version + name, description, rotation, entries; not tags/category) as `version`, the file version as `assetVersion`; `hasItem`, `item(for:version:)` and the package cache use it, transfers/receipts keep the asset version. Test `PhotoPackageVersionTests`. |
| 5.11, 5.12 | Fixed: per-field entry `applyEdit` (Map, Character) and a field-preserving quick-editor merge. |
| 5.13 | Fixed: `hasSessionOnlyEntries` (Map): a forced save during a game persists only metadata, with or without a game copy; a header edit of an unloaded map makes no game copy. |
| 5.14–5.16 | Fixed: forced single-field edits compare with the library (`forcedBase`), file edits read the library name and forward `forceSave`, `persist(fileUrl:)` goes through `persistFileUrl`. |
| 5.17–5.20 | Fixed: list trash/restore, import-review deletion, link repair, batch extraction and post-import repair take the operation's write policy. |
| 5.21, 5.22, 5.25 | Fixed: persisted imports, Character duplicate and `delete` read `noGame: true`. |
| 5.23 | Fixed: the inline quick editor saves forced through the shared game-copy diff (seeding the game copy first during a game); `saveGameDataToPermanent` removed. |
| 5.24 | Fixed: a persisted edit of the player's own or companion Character during a game re-announces it (`persistedGameEditHandler`). Not runtime-verified across devices. |
| 5.26 | Fixed: `removeGroup`/`willRepairOrphan` take `forceSave` and use `DisplayStateMask`. |
| 5.27 | Fixed: the register is written only on persisted writes. |
| 7.1 | Fixed: Pdf/Photo extraction and the group editor use one combined `reset` per item, one undo step. |
| 8.1 | Fixed: `TextEditModel` tracks a dirty state; a stored change while the user types keeps the typing (`sync(entry:source:)`). Not UI-verified. |
| 8.2 | Fixed: while a text input in the entry editor, quick editor or item header editor has focus, Undo/Redo go to the window's `UndoManager` (`textInputUndo()`, reusing `editorUndoActions`). Not UI-verified; the items stay enabled while editing (`canUndo` is not observable). |
| 8.3 | Fixed: Remove Line Breaks works on `textEditModel.text` through `replaceText` (undoable). |
| 8.4 | Fixed: Dice toggles and the Weather rain direction go through EditController setters; Character's overlay already did. |
| 8.5 | Fixed: doc updated; Character's game sheet uses `resolveGameSheetRootModel`. |
| 9.1, 9.2 | Fixed: `forceSave` is required on editor and file APIs (no `= false` defaults, test-only overloads removed). Remaining defaults are on `ItemControllable.replace`/`importNetwork`, not editor APIs. |
| 9.3 | Fixed: one merge skeleton; modules vary the matching step and `entriesReplacedUndoTitle` (Map/Rule copies deleted). |
| 9.4 | Fixed: `attachAsGroup` and `updateGroupItem` (one save) shared; Adventure keeps writing only the group item, Character also the entry. |
| 9.5 | Fixed: `saveField` is the shared single-field setter (Dice, Weather, `add(diceId:)`/`add(photoId:)`). |
| 9.6 | Fixed: `PdfQuickEntryEditor` (PdfRPG) and `DiceDropSelectionEditor` (DiceRPG) replace 4 + 3 copies. The Photo drop sections differ in behaviour (Character carousel) and stay. |
| 9.7 | Fixed: `trackOperation`, `save(updated: any Observable)`, `addGroup`, `quickEditEntries`, Generator `add(referenceId:model:)` removed. |
| 9.8 | Fixed: `EditControllable+Persistence.swift` split out (EditControllable.swift 431 lines); `EntryDataEditable.swift` is 470 lines after the removals. `ListRootContextMenu.swift` (508) untouched. |
| 9.9 | Fixed: `DisplayStateMask`, `DebounceDelay.quickEntryEditor`, `UndoTitleLimits.entryNameLength`. |

---

## 1. Executive summary

1. **[High] The undo stack survives game start and game end; undo then writes game-session snapshots into the library (or a library undo only into game memory)** — §5.1 — `Modules/CoreRPG/Controllable/EditControllable+Undo.swift:59-83`, `EditControllable.swift:458-480`
2. **[High] Undo restores whole-item snapshots: it reverts every sync merge and game change made since, and a forced undo persists those reverts into the library** — §5.2 — `EditControllable+Undo.swift:59-81`, `EditControllable.swift:488-499`
3. **[High] Undo of a file replacement or file move points the item at a file that was deleted or moved** — §5.3 — `Modules/CoreRPG/Controllable/EditControllable+File.swift:154-185`
4. **[High] "Convert to group" / "Move into group" during a game: the folder detach stays memory-only and the forced diff then misses it — the library item stays in its folder** — §5.8 — `Modules/CoreRPG/ItemList/GroupableEntryEditing.swift:48-57,90-97`
5. **[High] "Save outcome as value" (and any `addNew` + non-forced fill) during a game leaves an empty, nameless item in the library** — §5.9 — `Modules/TableRPG/Controller/TableGenerationController+OutcomeEditing.swift:76-80`, `ItemControllable.swift:130-151`
6. **[High] Metadata edits (name, description, rotation, entries/bookmarks) of Photo/Pdf/Space never reach players who already hold the file** — §5.10 — `Modules/PhotoRPG/Model/PhotoModel.swift:155-157`, `Modules/CoreRPG/Controllable/GameControllable.swift:175-178`
7. **[High] A CloudKit update arriving before the periodic flush overwrites a queued local edit in memory, then the flush overwrites the remote change in the store** — §3.1 — `Modules/CoreRPG/Controllable/SyncDataControllable.swift:144-155`, `ItemControllable.swift:384-408`
8. **[Medium] The forced game-copy diff replaces changed entries whole, carrying per-entry session state (Map room `isShown`, Character values) into the library; the Quick Entry Editor re-stamps every entry so *all* entries count as changed** — §5.11, §5.12 — `Modules/CoreRPG/Controllable/ItemDataAccessible+ApplyEdit.swift:34-48`, `EntryDataEditable.swift:298-310`
9. **[Medium] Link repair (`validateLinks`) during a game writes memory-only while it resets the *persisted* link register — after deletes, entry moves and Validate, the library keeps dead links the register no longer lists** — §5.18 — `Modules/CoreRPG/ItemList/EntryDataEditable.swift:452-454`, module `LinkController.validateLinks`
10. **[Medium] Parsing text registers links in the persistent register: unsaved typing, cancelled editors and memory-only game edits leave synced phantom links** — §5.27 — `Modules/CoreRPG/Links/LinkRegisterController.swift:348-377`

---

## 2. Quick wins (≤30 min each)

- **Forward `forceSave` to the auto-name in `replaceFile`** — `Modules/CoreRPG/Controllable/EditControllable+File.swift:164-168`. A file picked for an unnamed item during a game leaves the library item nameless (§5.15).
- **Call `updateTagCounts` in the forced undo branch with a game copy** — `EditControllable+Undo.swift:64-72` (§5.7).
- **Pass `forceSave: true` in `addOutcomeToCharacter`** — `TableGenerationController+OutcomeEditing.swift:79` (immediate mitigation of §5.9).
- **Read the duplicate source with `noGame: true` in Character `duplicateSubValue`** — `Modules/CharacterRPG/Controller/EditController+Duplication.swift:39-62` (§5.22).
- **Use `DisplayStateMask.groupHidden.rawValue` instead of the literal `1`** — `EditControllable+Folders.swift:108`, `Modules/CharacterRPG/Root/CharacterRootModel.swift:252` (§9.9).
- **Delete dead members**: `trackOperation` alias, `save(updated: any Observable)`, `ValueModel.quickEditEntries` (§9.7).
- **Fix the stale `isGameEditor` doc** (Adventure sets it too) — `Modules/CoreRPG/Sheet/SheetRootModel.swift:160-171` (§8.5).
- **Rename the inverted `affectedLinks` flag** in the shared merge — `EntryDataEditable.swift:328-335` (§9.3).

---

## 3. Concurrency

### 3.1 Sync merge discards local edits that are queued but not yet flushed
- **Location:** `Modules/CoreRPG/Controllable/SyncDataControllable.swift:144-155`; `Modules/CoreRPG/Controllable/ItemControllable.swift:248-256, 384-408`; `Modules/CoreRPG/Controllable/CoreDataSnapshotPersistable.swift:33-38`; `Modules/CoreRPG/Persistence/CoreDataController.swift:56-67, 167-172`
- **What:** `replace` only queues a snapshot (`queueReplace`); an incoming update batch fetches the row from the context (`fetchSnapshot`, which ignores the pending queue) and `applyMergedUpdate` overwrites the in-memory instance field by field (`<=>` assignment, not a CRDT merge).
- **Why:** Device A renames X (queued) → device B's description edit of X arrives before A's flush → memory takes B's row (A's rename disappears from the UI) → A's flush writes its queued snapshot (new name, old description) over B's row. Store and UI disagree; B's description is lost on all devices.
- **Action:** Skip or defer batch ids that have pending/in-flight operations (expose `hasPendingOperation(for:)`), or flush before fetching, or CRDT-merge the fetched row instead of replacing.
- **Severity:** High (sequence verified in code; timing not reproduced at runtime)

### 3.2 `convertToGroup` saves a host copy read before a suspension
- **Location:** `Modules/CoreRPG/ItemList/GroupableEntryEditing.swift:40-71`
- **What:** `item = editModel(for: itemId)` (line 41), then `await itemControllable.addNew` (DB replace + save), then `save(updated: item)` (line 70) writes the stale copy.
- **Why:** A sync merge or another window's edit of the host landing during the await is overwritten.
- **Action:** Do the awaits first, then re-read the host and apply the entry change synchronously.
- **Severity:** Medium

### 3.3 Photo `convert` bypasses the per-item file queue
- **Location:** `Modules/PhotoRPG/Controller/EditController.swift:23-45`
- **What:** Reads `item.fileUrl`, awaits download/encode/`createNewFileUrl`, then `reset(fileUrl:)` without `enqueueFileOperation` or a re-check that the file is unchanged.
- **Why:** Convert and Replace Photo on the same item race; the loser's file is orphaned or the converted old photo replaces the new one.
- **Action:** Wrap in `enqueueFileOperation(itemId:)` and guard `editModel(for:)?.fileUrl == fileUrl` before writing.
- **Severity:** Medium

### 3.4 Removal of a replaced game file is an unqueued Task
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable+GamePersistence.swift:144-152`
- **What:** `deleteReplaced` runs in a fire-and-forget `Task` after the "still referenced" check, outside `fileOperationTails`.
- **Why:** A delivery or edit referencing the same file between check and deletion loses its file.
- **Action:** Route through the per-item file queue and re-check references inside the operation.
- **Severity:** Low

### 3.5 Sync consumer Task retains its `ItemDataModel` forever
- **Location:** `Modules/CoreRPG/Controllable/SyncDataControllable.swift:58-71`; `Modules/CoreRPG/ItemList/ItemDataModel.swift:68-73`
- **What:** The consumer captures `dataModel` strongly and iterates a stream that is never finished.
- **Why:** Every rebuilt root / test / preview leaks its model and consumer.
- **Action:** Capture weakly inside the loop, or finish the continuation and cancel the consumer on teardown.
- **Severity:** Low

### 3.6 Map `validateBeforeSave` spawns an untracked Task on every save attempt
- **Location:** `Modules/MapRPG/Controller/EditController.swift:286-300`; `Modules/CoreRPG/Controllable/EditControllable.swift:581-585`
- **What:** Runs before the `isEqual` guard and starts a `Task` even for no-op saves.
- **Why:** Needless Tasks per map interaction; thumbnail invalidation can land after the next render.
- **Action:** Return early when no entry coordinates changed; make the invalidation a synchronous cache mark.
- **Severity:** Low

### 3.7 Sheet group creation targets the editor at an item that may no longer be shown
- **Location:** `Modules/CoreRPG/Sheet/SheetRootModel+Editor.swift:52-60, 75-82`
- **What:** After `await addNewGroup`/`convertToGroup` the editor's `itemId`/`entryId` are set without checking the sheet still shows that item.
- **Why:** Switching items during group creation opens the entry editor of the old item over the new one.
- **Action:** Guard the sheet's source id after the await.
- **Severity:** Low

---

## 4. API modernity

### 4.1 Model conformances use `nonisolated` + `MainActor.assumeIsolated` instead of isolated conformances
- **Location:** `Modules/CoreRPG/Concurrency/MainActorIsolationAssumption.swift:5-29`; `Modules/CoreRPG/Controllable/ItemDiffComparable.swift:5-13`; e.g. `Modules/AdventureRPG/Model/AdventureModel.swift:204-282` (≈35 conformances, ≈62 `assumeMainActorIsolated` sites)
- **What:** `ItemDiffComparable`/`ItemDuplicatable` are already `@MainActor`, yet models conform `nonisolated` and assume isolation at runtime.
- **Why:** An off-main caller traps at runtime instead of failing to compile.
- **Action:** Conform plainly to the `@MainActor` protocols; use Swift 6.2 isolated conformances (`@MainActor Comparable/Equatable`); delete the shim.
- **Severity:** Medium

---

## 5. Bugs / logic errors

### 5.1 Undo/redo stacks survive game start and game end and write into the wrong scope
- **Location:** `Modules/CoreRPG/Controllable/EditControllable+Undo.swift:40-83`; `Modules/CoreRPG/Controllable/EditControllable.swift:458-480, 571-579`; `Modules/CoreRPG/Controllable/GameControllable.swift:97-102`; `Modules/CoreRPG/ItemList/ItemEditorModel.swift:56-90`; `Modules/CoreRPG/Controllable/ItemControllable.swift:236-246, 265-279`
- **What:** `undoManaged` is reset only by `setCurrentItem` (new id) and `removeFromEditors`; game start/end never reset it, and `applyUndoValue` decides the write scope (`persistsEdit`, `gameCopy(of:)`) at undo time, not edit time.
- **Why:** (a) In-game save pushes the game copy (HP modifiers, Map player pins, battle-clone `characterId`s) → game ends → Cmd+Z → `replace` now persists → session state lands in library and CloudKit, unfiltered (`libraryWriteFilter` only runs in game mode); a game-only item is even inserted via the new-id branch. (b) Library edit → start game → Cmd+Z → memory-only; the "undone" edit reappears after the game.
- **Action:** Reset every module's `undoManaged` plus the forced/library-scoped marker lists on game start, game end and saved-game staging — or tag each step with its game generation and refuse cross-generation steps.
- **Severity:** High

### 5.2 Undo restores whole snapshots, reverting later sync merges and game changes
- **Location:** `Modules/CoreRPG/Controllable/EditControllable+Undo.swift:59-81`; `Modules/CoreRPG/Controllable/EditControllable.swift:463-470, 488-499`; `Modules/CoreRPG/Controllable/ItemDataAccessible+ApplyEdit.swift:14-29`
- **What:** An undo step is a full `copy()`; the non-forced path writes it whole, the forced path diffs *current game copy → snapshot*, so every change since the step counts as part of the undo.
- **Why:** GM renames a Character in the editor window (forced) → player `.valueUpdate` lowers HP 10→5 → Cmd+Z for the rename → library *and* game copy go back to HP 10, and the player is not told. Outside a game: edit X, another device's description change merges, Cmd+Z → the remote change is reverted and persisted.
- **Action:** Store steps as field/entry deltas (before/after of what the step changed) and apply them with the three-way `applyEdit`, using the step's own after-state as base; at minimum drop an item's steps when a sync merge or session write changes it.
- **Severity:** High

### 5.3 Undo restores `fileUrl` values whose files were deleted or moved
- **Location:** `Modules/CoreRPG/Controllable/EditControllable+File.swift:154-185` (replace: `reset(fileUrl:)` at 180, `deleteReplaced` at 181-183), `:62-94` (moves); `Modules/CoreRPG/Controllable/EditControllable+Folders.swift:104-121, 169-182`; `Modules/CoreRPG/Controllable/ItemControllable+ImportedFiles.swift:99-114`
- **What:** `reset(fileUrl:)` is an undo step, but the replaced file is deleted right after and file moves change the disk without a step; undo never restores or moves files.
- **Why:** Replace a photo/PDF → Cmd+Z → item references a deleted file and the new file is orphaned. Drag a photo into a folder (file moved) → undo twice → item points at a path that no longer exists.
- **Action:** Exclude `fileUrl` from undo snapshots (carry the live value forward in `recordLiveValue`/`applyUndoValue`), or clear the steps holding the old URL; if file undo is wanted, keep the replaced file until the step drops off the stack.
- **Severity:** High

### 5.4 Undo can resurrect an item hard-deleted in the meantime
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:265-279`; `Modules/CoreRPG/Controllable/EditControllable.swift:447-456`; `Modules/CoreRPG/Controllable/SyncDataControllable.swift:107-112`
- **What:** The stack holds values of every edited item; `removeFromEditors` clears it only when the deleted item is the current value (and then wipes everyone's history); `replace(isInsert:false)` of an unknown id inserts.
- **Why:** Item X edited, then purged on another device or via the Delete intent → Cmd+Z re-inserts and re-uploads X, possibly referencing a deleted file.
- **Action:** Skip/drop steps whose id is no longer in the library; on delete remove only that item's steps.
- **Severity:** Medium

### 5.5 One user action produces several saves and undo steps
- **Location:** `Modules/CoreRPG/ItemList/EntryDataEditable.swift:427-467` (cross-item move, move into/out of group); `Modules/CharacterRPG/Controller/EditController.swift:176-191, 307-320` (link add, group-entry update: up to 4 saves); `Modules/CoreRPG/Controllable/EditControllable.swift:348-377` (`addGroup`/`removeGroup`); `Modules/CoreRPG/ItemList/GroupableEntryEditing.swift:14-25` (`addNewGroup`: 3 saves); `Modules/CoreRPG/EntryEditor/EntryEditorHeaderView.swift:83-109` (drop = update + link); `Modules/AdventureRPG/Controller/EditController.swift:95-105`
- **What:** Each `save` is its own undo step and its own broadcast/CloudKit export.
- **Why:** One Cmd+Z after moving an entry restores only the target item — the entry is in neither item until a second undo; undoing half a Character group-entry edit leaves entry and group item out of sync.
- **Action:** Add an undo-group API to `UndoManaged` (one step holding several item values) and build compound edits on one edit model where possible (as Map's `appendLink` does).
- **Severity:** Medium

### 5.6 Forced/library-scoped undo marks are trimmed separately from the stacks and never cleared
- **Location:** `Modules/CoreRPG/ItemList/ItemEditorModel.swift:61-90`; `Modules/CoreRPG/App/UndoManaged.swift:18-45`
- **What:** Marker arrays keep the newest 100 identities; every undo/redo appends, the redo stack is not trimmed, `resetValue` doesn't clear marks.
- **Why:** After many undo/redo cycles a forced step loses its mark and is undone memory-only.
- **Action:** Store the scope next to each stack entry inside `UndoManaged`.
- **Severity:** Low

### 5.7 Forced undo with a game copy skips the tag-count update
- **Location:** `Modules/CoreRPG/Controllable/EditControllable+Undo.swift:64-72`; `Modules/CoreRPG/Controllable/EditControllable.swift:488-499`
- **What:** When `writeForcedEditOfGameCopy` succeeds, `updateTagCounts` is not called (only the no-game-copy branch calls it).
- **Why:** Undoing an editor-window tag edit during a game leaves persisted tag counts wrong.
- **Action:** Update tag counts against the library value inside `writeForcedEditOfGameCopy` or in the branch.
- **Severity:** Low

### 5.8 Group conversion / "Move into group" lose the folder detach during a game
- **Location:** `Modules/CoreRPG/ItemList/GroupableEntryEditing.swift:48-57, 90-97`; `Modules/CoreRPG/Controllable/EditControllable+Folders.swift:37-39, 169-172`; `Modules/CoreRPG/Controllable/EditControllable.swift:488-499`
- **What:** Both call the 3-argument `removeItemFromParent` (scope `.current` → plain non-forced save → memory-only, creating a game copy with `parentId == nil`); the following forced save diffs that game copy (nil) against the edit (nil), so the library never gets the detach and the folder keeps listing the item.
- **Why:** List "Move into group" (`ListRootContextMenu.swift:430`, forced) or sheet "Convert to group" during a game → after the game a hidden group item still sits in its old folder (CODE_AUDIT_26 §5.73 returns).
- **Action:** Thread the operation's write policy into every helper it calls (scope `.library` + game-copy mirror when `forceSave`), or capture the diff base once at the start of the operation. Add a during-game test starting from an item inside a folder.
- **Severity:** High

### 5.9 `addNew` always persists while the fill is memory-only → empty items in the library
- **Location:** `Modules/TableRPG/Controller/TableGenerationController+OutcomeEditing.swift:76-80`; `Modules/CoreRPG/Controllable/EditControllable.swift:81-83`; `Modules/CharacterRPG/Controller/EditController.swift:374-390`; `Modules/CoreRPG/Controllable/ItemControllable.swift:130-151`; `Modules/CoreRPG/ItemList/GroupableEntryEditing.swift:14-25, 59-66`
- **What:** `addOutcomeToCharacter` uses the 1-argument `addItem(sheet:)` (`forceSave: false`); `addNew` writes an empty item to the store immediately, then name/description/entries are saved memory-only. Same split in the non-forced `addNewGroup`/`convertToGroup` overloads.
- **Why:** "Save outcome as value" from the generation panel in the game sheet (`TableRootSheet.swift:110`) → after the game the library has a nameless empty Character and the outcome is gone.
- **Action:** Pass `forceSave: true` for explicit user saves and remove the 1-argument overload; structurally, give `addNew` the caller's write policy (memory-only creates via `replaceInGameMemory`) or build the full item and insert once.
- **Severity:** High

### 5.10 Metadata edits of Photo/Pdf/Space never reach players who already hold the file
- **Location:** `Modules/PhotoRPG/Model/PhotoModel.swift:155-157`; `Modules/PdfRPG/Model/PdfModel.swift:166-168`; `Modules/SpaceRPG/Model/SpaceModel.swift:150-152`; `Modules/CoreRPG/Controllable/GameControllable.swift:175-178`; `Modules/GameRPG/Controller/MasterController+PackageCache.swift:28-40`; `Modules/GameRPG/Model/MasterPackageCache.swift:24-29`; `Modules/GameRPG/Controller/MasterController+Show.swift:157-180`
- **What:** `version` of file-backed items is only the file content version; rename, description, `degrees`, entries/bookmarks leave it unchanged, so the package-cache fingerprint matches, `playersMissing` is empty and a player's `hasItem(id:version:)` is true.
- **Why:** GM rotates or renames a shown Photo in the editor window (forced, persisted) → re-show → reference-only reveal → players keep the old rotation/name; a late joiner gets the stale cached package.
- **Action:** Add a metadata digest (name, description, degrees, entries) to the network fingerprint/version, separate from the asset version so file bytes are not re-sent.
- **Severity:** High

### 5.11 The forced diff replaces changed entries whole, carrying per-entry session state into the library
- **Location:** `Modules/CoreRPG/Controllable/ItemDataAccessible+ApplyEdit.swift:34-48` (`result[existing] = entry`); `Modules/CoreRPG/ItemList/EntryDataEditable.swift:371-405`; `Modules/MapRPG/Model/MapEntryModel.swift:43-51`; `Modules/MapRPG/Controller/DataController.swift:135, 192`
- **What:** An edited entry comes from the game copy (`editModel(for:)`), so its session fields travel with it: Map room `isShown`/`focused` (both stored in Core Data), Character entry values/`displayState`.
- **Why:** GM reveals a room, then fixes its description in the room editor → the room is stored revealed and starts visible in the next game. Renaming a Character entry persists its in-game value.
- **Action:** Diff per field inside a changed entry (base vs edited onto the library entry), or let modules strip session-only entry fields (`applyModuleEdit`/`libraryWriteFilter`).
- **Severity:** Medium

### 5.12 Quick Entry Editor "Apply" marks every entry changed and reverts concurrent updates
- **Location:** `Modules/CoreRPG/ItemList/EntryDataEditable.swift:298-310, 321-344`; `Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:210-218, 291-300`; `Modules/CoreRPG/CRDT/CRDT.swift:68-74`; `Modules/CoreRPG/CRDT/LWWRegister.swift:60-74`
- **What:** `entriesMatchedByName` always assigns `matched.name`/`matched.content`; the LWW setter re-stamps the clock even for identical values and entry `==` includes the clock, so `mergedEntries` copies *all* entries — from the text snapshot taken when the editor opened.
- **Why:** GM fixes one line in the editor window during a game → every entry's game-only state is persisted, and entries changed while the editor was open (player `.valueUpdate`, CloudKit sync) are reverted in library and game copy without telling players. Outside a game it still produces needless CRDT clock bumps on every entry (sync churn).
- **Action:** Assign only when the plain value differs (`<=>`); compare entries without clocks in `mergedEntries` (like `isSame`).
- **Severity:** Medium

### 5.13 The Map "content is memory-only" decision is enforced per method and leaks
- **Location:** `Modules/MapRPG/Controller/EditController.swift:94-113, 449-471`; `Modules/CoreRPG/EntryEditor/EntryEditorHeaderView.swift:83-109`; `Modules/CoreRPG/ItemList/EntryDataEditable.swift:215-467`
- **What:** Map `add(link:)` and `merge` ignore `forceSave`, but Map inherits the generic `update`/`remove`/`copy`/`move`/`addNewEntry`/`insertEntry`/`removeEntry`, which forward it.
- **Why:** One entry-editor drop persists the room text but not the link; the next forced edit of that room carries the link (and §5.11 session state) into the library anyway; room add/delete/reorder persist against the decision.
- **Action:** Enforce the decision once — a module write policy consulted by Map's `persistsEdit`/`saveChanges` (metadata passes, entries/content don't).
- **Severity:** Medium

### 5.14 The `isEqual` short-circuit compares with the game copy
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:97-128, 581-585`; `Modules/CoreRPG/Controllable/ItemControllable.swift:224-227`
- **What:** `reset…` guards and `save(with:)` compare with `itemSync(for:)` (game copy); a forced save equal to the game copy but different from the library is dropped.
- **Why:** GM edits a value in the game view (memory-only), then re-enters the same value in the editor window to keep it → nothing is saved; lost at game end.
- **Action:** For forced saves, compare against the library copy too.
- **Severity:** Low

### 5.15 File edits during a game use game-copy names and an unforced auto-name
- **Location:** `Modules/CoreRPG/Controllable/EditControllable+File.swift:23-33, 65-92, 164-168`
- **What:** `folderPath` walks `editModel(for:)` (game copies), and `replaceFile` calls `reset(name:)` without `forceSave` before the forced `reset(fileUrl:)`.
- **Why:** Files are persisted under folder names renamed only in game memory; an unnamed item that gets a file stays nameless in the library (the first save creates a game copy holding the name, so the forced diff carries only the file).
- **Action:** Use `noGame: true` in `folderPath`; forward `forceSave` to the name reset (or one combined `reset`).
- **Severity:** Low

### 5.16 `persist(fileUrl:)` overwrites a loaded game copy with the library state
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable+Files.swift:129-134`; `Modules/CoreRPG/Controllable/ItemControllable.swift:262-264, 299-302`
- **What:** Writes a library copy with `forceSave: true` and the default `syncGameMemory: true`, so `syncGameMemoryIfLoaded(with: original)` replaces the whole game copy.
- **Why:** A forced import that reuses an existing file during a game reverts that item's session state on the GM.
- **Action:** Pass `syncGameMemory: false` and mirror only `fileUrl` (as `ItemControllable+ImportedFiles.swift:112` does).
- **Severity:** Low

### 5.17 List trash/restore and import-review deletions are memory-only during a game, but tag counts change permanently
- **Location:** `Modules/CoreRPG/Controllable/EditControllable+Delete.swift:53-58, 222-231, 249-298`; `Modules/CoreRPG/LGViews/ListRootContextMenu.swift:287`; `Modules/CoreRPG/LGViews/AffectedLinkActionPanelView.swift:57`; `Modules/CoreRPG/FileViews/ImportReviewApplyController.swift:37-50`
- **What:** `confirmRemoval`/`markForDeletion`/`restore` save without `forceSave` but always call `tagController.remove/add`; the import review persists its adds (`:99`) but trashes memory-only (`:50`).
- **Why:** Items deleted from the library list during a game reappear afterwards with permanently decremented tag counts; a backup review applied mid-game keeps items it should have trashed.
- **Action:** Treat library-UI trash/restore and review deletions as library-scoped (forced + mirror `displayState`), and gate tag counts on `persistsEdit`.
- **Severity:** Medium

### 5.18 Link repair runs memory-only during a game while the persisted register is reset
- **Location:** `Modules/CoreRPG/ItemList/EntryDataEditable.swift:427-467` (repair at 452-454); `Modules/CoreRPG/Links/LinkRegisterController.swift:130-150`; `Modules/CoreRPG/Controllable/EditControllable+Delete.swift:80-109`; `Modules/CoreRPG/Controllable/LinkControllable.swift:330-335`; every module's `validateLinks(on:)`, e.g. `Modules/PdfRPG/Controller/LinkController.swift:52-67`, `Modules/CharacterRPG/Controller/LinkController.swift:129-134`
- **What:** `validateLinks` reads the game copy, writes the repaired item with non-forced `replace` (memory-only in a game), then calls `resetLinkRegister` unconditionally; `delete(itemId:)` also unhides grouped children with non-forced `reset(displayState:)` while the row delete itself is permanent.
- **Why:** Delete a linked item, or move an entry (forced), during a game → referring items keep dead/stale `rpg://` links in the library while the register no longer lists them, so nothing repairs them later; grouped carousel children stay hidden orphans.
- **Action:** Run delete/move side effects with the operation's persistence (forced, library scope), or re-run link validation and orphan repair on the library at game end; rebuild the register from `itemSync(for:noGame:true)`.
- **Severity:** Medium

### 5.19 Batch "Extract Information" is memory-only during a game
- **Location:** `Modules/GeneratorRPG/View/BatchPdfSummaryExtractionView.swift:189`; `BatchPhotoSummaryExtractionView.swift:182`; `BatchTextSummaryExtractionView.swift:290`; `Modules/PdfRPG/Controller/EditController.swift:128-138`
- **What:** Batch views call `reset(name:description:tags:itemId:)` and `addExtractedBookmarks` without `forceSave`; single-item extraction passes `true`.
- **Why:** Generated titles, descriptions, tags and bookmarks from a batch run during a game vanish at game end.
- **Action:** Pass `forceSave: true` from the batch runner; add `forceSave` to `addExtractedBookmarks`.
- **Severity:** Medium

### 5.20 Post-import folder/orphan repair is memory-only even for persisted imports
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:195-218`; `Modules/CoreRPG/Controllable/ImportControllable+Apply.swift:14-22, 132-136, 156-164`; `Modules/CoreRPG/Controllable/EditControllable.swift:282-337`; `Modules/CoreRPG/Controllable/ConvertController.swift:30-87`
- **What:** `repairFolders` and `repairImportedItems` save through non-forced paths although the import itself persisted.
- **Why:** A backup import or a player's reconnect resync during a game leaves folder membership and category normalisation unrepaired in the library.
- **Action:** Thread the import's write policy into the repair pass.
- **Severity:** Medium

### 5.21 Persisted imports during a game merge against the game copy
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable+Apply.swift:57-75`; `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:24-31`; `Modules/CoreRPG/Controllable/ItemControllable.swift:323-331`; `Modules/CharacterRPG/Controller/GameController+Sync.swift:53-58`
- **What:** `applyImportedItem` calls `mergeSync` without `noGame: true`; `registerImportedLinks` diffs against the game copy (unlike `persistFromGame`).
- **Why:** Player reconnect → `updatePlayer` → `importNetwork(forceSave:true)` merges with the master's game copy: the master's session-only changes get persisted, and an `isSame` result skips the library update entirely.
- **Action:** Use `noGame: true` for persist-mode merges and register diffs; mirror into the game copy separately.
- **Severity:** Medium

### 5.22 Character duplicate during a game copies game copies into the library
- **Location:** `Modules/CharacterRPG/Controller/EditController+Duplication.swift:39-62`
- **What:** `duplicateSubValue` builds copies from `itemSync(for:)` (game copy preferred) and persists them with `forceSave: true`, group values included; the generic `duplicate(item:)` correctly uses `.library`.
- **Why:** Duplicating a Character in game memory creates a permanent Character with in-game HP/edits.
- **Action:** Read the source with library scope.
- **Severity:** Medium

### 5.23 The Character inline quick editor has its own persistence path and its undo is not forced
- **Location:** `Modules/CharacterRPG/Controller/EditController+InlineEditor.swift:63-70, 122-145`; `Modules/CoreRPG/Controllable/EditControllable+Undo.swift:59-81`
- **What:** `applyEntryUpdate` saves memory-only then copies the entry to the library via `saveGameDataToPermanent`, never calling `markForcedUndo`.
- **Why:** Undo of an inline value change during a game reverts only game memory; the library keeps the new value, which returns after the game. A second "persist during game" mechanism to maintain.
- **Action:** Route through `save(…, forceSave: true)` (entry-scoped `writeForcedEditOfGameCopy`) and delete `saveGameDataToPermanent`.
- **Severity:** Medium

### 5.24 A player's Character edits outside the inline editor never reach the master during the game
- **Location:** `Modules/CoreRPG/Sheet/SheetEntryRowViews.swift:117-145`; `Modules/GameRPG/Controller/PlayerController+SendMessages.swift:18-36`; `Modules/CharacterRPG/View/CharacterAddEntryOverlay.swift:152-164`; `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:70-75`
- **What:** Only `InlineEditorView` sends `.valueUpdate`, for existing entries; editor-window edits, header/entry editors and the add-entry overlay send nothing; the package is re-announced only on reconnect.
- **Why:** A player adds an entry or edits a formula mid-game → persisted on the player, invisible on the GM's sheet, battle round and health ring until reconnect.
- **Action:** Re-announce the Character after forced edits in game mode (`scheduleSendCharacter`), or add structured entry add/remove/update messages.
- **Severity:** Medium

### 5.25 `ItemControllable.delete` works on the game copy
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:157-222`
- **What:** Reads `itemSync(for:)` (game copy), announces/deletes that copy's `fileUrl`, and on a failed DB delete restores the game copy as the library instance (`resetModel(with: item)`).
- **Why:** Deleting a library Photo whose game copy carries a delivered newer file removes the game file and orphans the library file; on failure session state becomes the library object.
- **Action:** Use `noGame: true` for the persisted item and its file; clean up the game copy separately.
- **Severity:** Low

### 5.26 `removeGroup` and `willRepairOrphan` cannot persist during a game and overwrite the display mask
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:234-239, 348-377`; caller `Modules/CoreRPG/Controllable/ConvertController.swift:78`
- **What:** No `forceSave` parameter (memory-only during a game, unlike `addGroup`); `addGroup`/`removeGroup` hide/show by assigning `displayState` 1/0, wiping other mask bits, unlike `isGroupHiddenToggle` in `GroupableEntryEditing`.
- **Why:** Group removal/repair during a game is lost at game end; a trashed or otherwise flagged child can be made fully visible.
- **Action:** Add `forceSave`; switch to `isGroupHiddenToggle`; delete the test-only `addGroup`.
- **Severity:** Low

### 5.27 Parsing text registers links in the persistent register
- **Location:** `Modules/CoreRPG/Links/LinkRegisterController.swift:348-377`; `Modules/CoreRPG/EntryEditor/TextEditModel.swift:141-152`; `Modules/CoreRPG/ItemList/EntryDataEditable.swift:377, 394`; `Modules/CoreRPG/Controllable/ItemControllable.swift:317-331`
- **What:** `linkRegisterModel(in:for:)` registers every unseen link it parses — on every debounced keystroke, when rendering editor text, and in `updateDefault` (which also registers duplicated links before the save is known) — regardless of `forceSave`/`isGameMode`; `replaceImportedModel(policy: .memoryOnly)` registers game deliveries' links.
- **Why:** Typing a link then cancelling, any memory-only game edit, or a player receiving revealed items leaves synced `LinkReferenceDataModel` rows for links the library lacks: phantom "used by", spurious affected-link prompts, entries that cannot be removed by `merge` (`used(for:)`), rows pointing at game-only items. Contradicts CODE_AUDIT_29 §5.3.
- **Action:** Make parsing side-effect free (look up only); register only from `saveChanges`/persisted imports.
- **Severity:** Medium

---

## 6. Security

_No findings._ (Peer-import trust gaps were decided won't-fix earlier — see `Docu/CODE_AUDIT_Folder.md` §6.1/§6.2.)

---

## 7. Performance

### 7.1 Single-item extraction and the group editor save up to three times per item
- **Location:** `Modules/PdfRPG/Controller/EditController.swift:92-109`; `Modules/PhotoRPG/Controller/EditController.swift:173-183`; `Modules/CoreRPG/LGViews/GroupEditorController.swift:121-135`
- **What:** Separate `reset(name:)`, `reset(description:)`, `reset(tags:)` calls (twins of CODE_AUDIT_29 §7.8 / §5.5).
- **Why:** 3 saves, 3 CloudKit exports, 3 undo steps per item (3×N for the group editor); a sync can observe a half-applied item.
- **Action:** Use the combined `reset(name:description:tags:itemId:forceSave:)`.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 The entry editor overwrites unsaved typing when the stored entry changes
- **Location:** `Modules/CoreRPG/EntryEditor/EntryEditorContent.swift:35-53, 75-77`; `Modules/CoreRPG/EntryEditor/TextEditModel.swift:61-74`
- **What:** `.onChange(of: entry.content/name)` calls `editModel.reset(entry:)`, replacing the in-progress text and cancelling the debounce.
- **Why:** A sync merge, game network update or menu Undo touching the entry silently discards what the user typed; Save then writes the external value.
- **Action:** Track a dirty flag in `TextEditModel`; when dirty keep local text and surface the conflict; reset only when the source item/entry changes.
- **Severity:** Medium

### 8.2 Replacing the `.undoRedo` command group routes Cmd+Z away from text fields
- **Location:** `Modules/CoreRPG/Menu/ModuleCommands.swift:71-80`; `Modules/CoreRPG/Menu/UndoButton.swift:8-21`; `Modules/CoreRPG/EntryEditor/TextEditModel.swift:44-59`
- **What:** System Undo/Redo (first-responder `undo:`) is replaced by buttons calling `editControllable.undo()`.
- **Why:** On macOS, Cmd+Z while typing undoes the last persisted item edit (possibly another item) and, via §8.1, can wipe the typing.
- **Action:** Keep system undo when a text input is focused (focused-value check, or `CommandGroup(after: .undoRedo)`), or bridge `UndoManaged` into the window's `UndoManager`.
- **Severity:** Medium

### 8.3 Quick editor "Remove Line Breaks" uses the debounced value and doesn't update the editor
- **Location:** `Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:213, 301-310, 342-347, 416`
- **What:** Writes `referenceText.input = removeLineBreak(referenceText.output)`; `output` lags `input` by 1 s and `textEditModel` is seeded only on appear.
- **Why:** The last second of typing is dropped, the editor shows old text, Apply saves something different from what is displayed.
- **Action:** Operate on `textEditModel.text` and push through `replaceText(...)` as Quick Link does.
- **Severity:** Medium

### 8.4 Views edit models and save directly
- **Location:** `Modules/DiceRPG/Dice/ToggleDiceValue.swift:44-47`; `Modules/WeatherRPG/View/WeatherStormEditor.swift:79-83`; `Modules/CharacterRPG/View/CharacterAddEntryOverlay.swift:154-159`
- **What:** Views call `editModel(for:)`, mutate, and `save(…forceSave:)` themselves.
- **Why:** Untestable, and each new edit must remember `forceSave` (against the MVC rule in CLAUDE.md).
- **Action:** Move each edit into an EditController method.
- **Severity:** Low

### 8.5 `isGameEditor` doc is stale and the game sheet is built twice
- **Location:** `Modules/CoreRPG/Sheet/SheetRootModel.swift:160-171`; `Modules/CharacterRPG/Root/CharacterRootModel.swift:210-224`; `Modules/CoreRPG/Controllable/ItemRootControllable.swift:47-63`
- **What:** Doc says only Character sets `isGameEditor`; Adventure does too (`AdventureSheet.swift:59`). Character's `startGameSheetRootModel` duplicates `resolveGameSheetRootModel`.
- **Why:** Readers misjudge which live game views persist edits.
- **Action:** Fix the doc; have Character call `resolveGameSheetRootModel`.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Editor-only APIs default to `forceSave: false`; non-forced overloads are test-only
- **Location:** `Modules/AdventureRPG/Controller/EditController.swift:182, 189`; `Modules/CharacterRPG/Controller/EditController.swift:201, 242, 250, 293`; `Modules/TableRPG/Controller/EditController.swift:78`; `Modules/WeatherRPG/Controller/EditController.swift:40-100`; `Modules/DiceRPG/Controller/EditController.swift:18-129`; `Modules/RuleRPG/Controller/EditController.swift:205`; `Modules/PhotoRPG/Controller/EditController.swift:23, 173`; `Modules/PdfRPG/Controller/EditController.swift:55, 88`; `Modules/CoreRPG/ItemList/EntryDataEditable.swift:24-27, 133-136, 163-175, 269-289, 364-369`; `Modules/CoreRPG/Controllable/EditControllable.swift:78-83`
- **What:** Every production caller passes `true`; the `= false` defaults and convenience overloads are used only by tests (`addNewGroup(itemId:)` ×90, `convertToGroup` ×9, `moveIntoGroup` ×8) or not at all (6-arg `add(link:)`, 3-arg `updateSheetEditType`) — except the two real bugs §5.9/§5.19.
- **Why:** A new editor control that forgets the argument silently becomes memory-only during a game — the bug class the last commit fixed.
- **Action:** Make the write policy a required parameter on editor APIs; remove the test-only overloads after updating tests.
- **Severity:** Medium

### 9.2 File replacement APIs disagree on the default `forceSave`
- **Location:** `Modules/CoreRPG/Controllable/EditControllable+File.swift:105, 236`; `Modules/PhotoRPG/Controller/EditController.swift:117-138`
- **What:** `resetFile(url:)` defaults `true`, `resetFile(data:)` `false`, `resetPhoto(data:)` `true`, `resetPhoto(image:)` hard-codes `true`.
- **Why:** Persistence during a game depends on which overload a caller picks.
- **Action:** One required parameter across file APIs.
- **Severity:** Low

### 9.3 The entry merge skeleton exists three times; the shared one keeps an inverted flag
- **Location:** `Modules/CoreRPG/ItemList/EntryDataEditable.swift:320-344`; `Modules/MapRPG/Controller/EditController.swift:453-471`; `Modules/RuleRPG/Controller/EditController.swift:177-201`
- **What:** All implement "removed ids → check link usage → replace or report"; the default's `affectedLinks = true` means "no linked entries" (Map renamed it `hasNoLinkedEntries`).
- **Why:** Three copies and a misleading name in the one most modules use.
- **Action:** Make the default generic over the matching step and persistence; rename the flag.
- **Severity:** Low

### 9.4 Group-entry wiring diverges between Adventure and Character
- **Location:** `Modules/AdventureRPG/Controller/EditController.swift:95-105`; `Modules/CharacterRPG/Controller/EditController.swift:293-303, 307-320`; `Modules/CoreRPG/ItemList/GroupableEntryEditing.swift:14-25`
- **What:** Adventure writes only the group item's name/description; Character writes the entry (`nameWithLink: true`) and the group item; `addItemAsGroup` re-implements `addNewGroup` (using `valueId` instead of `groupItemId`).
- **Why:** Same concept, two behaviours; the copies drift.
- **Action:** One "update group entry" and one "attach existing item as group" rule in the `GroupableModel` extension.
- **Severity:** Low

### 9.5 Per-module setter boilerplate
- **Location:** `Modules/AdventureRPG/Controller/EditController.swift:182-193`; `Modules/CharacterRPG/Controller/EditController.swift:250-254`; `Modules/TableRPG/Controller/EditController.swift:78-82`; `Modules/WeatherRPG/Controller/EditController.swift:40-44, 104-114`; `Modules/DiceRPG/Controller/EditController.swift:104-129`
- **What:** `add(diceId:)` ×3, `add(photoId:)` ×2 (+Map), differing undo titles; Dice repeats the read-assign-save Weather already factored into a keyPath helper.
- **Action:** A shared keyPath setter on `EditControllable` with a write-policy parameter.
- **Severity:** Low

### 9.6 Duplicated editor view wrappers
- **Location:** `Modules/{Adventure,Character,Map,Table}RPG/View/QuickEntryEditor.swift`; `Modules/{Adventure,Character}RPG/View/DiceDropSection.swift`, `Modules/TableRPG/View/DetailSelectionEditorView.swift:14-31`; `Modules/{Adventure,Character}RPG/View/PhotoDropSection.swift`
- **What:** Wrappers differ only in types, route and selection model.
- **Why:** Every fix (forceSave, debounce) must be repeated 3–4 times.
- **Action:** Generic CoreRPG views taking the selection model, route and setter.
- **Severity:** Low

### 9.7 Dead or test-only edit code
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:55-57` (`trackOperation`), `:552-555` (`save(updated: any Observable)`, no caller), `:348-366` (`addGroup`, test-only); `Modules/CharacterRPG/Model/ValueModel.swift:131` (`quickEditEntries`, never read/written/persisted); `Modules/GeneratorRPG/Controller/EditController.swift:13-19` (`add(referenceId:model:)`, test-only, mutates the passed model)
- **Action:** Delete; see §5.26 for `removeGroup`.
- **Severity:** Low

### 9.8 Files over 500 lines in scope
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift` (586); `Modules/CoreRPG/ItemList/EntryDataEditable.swift` (522); `Modules/CoreRPG/LGViews/ListRootContextMenu.swift` (508)
- **Action:** Move forced-save/undo/register helpers (`EditControllable.swift:458-550`) to `EditControllable+Persistence.swift`; move entry move/copy (`EntryDataEditable.swift:408-467`) and `EntryOrder` to their own file. No TODO/FIXME markers in scope.
- **Severity:** Low

### 9.9 Magic constants in the edit path
- **Location:** `Modules/CoreRPG/Controllable/EditControllable+Folders.swift:108`, `Modules/CharacterRPG/Root/CharacterRootModel.swift:252` (`displayState <=> 1`); `Modules/{Adventure,Map,Table}RPG/View/QuickEntryEditor.swift:12-13` (`delay: 2`, named only in Character); `Modules/CoreRPG/ItemList/EntryDataEditable.swift:251` (`prefix(16)`)
- **Action:** Use `DisplayStateMask`; one shared debounce constant; a named undo-title length.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **One write policy per user operation, threaded through every helper.** Most game-edit bugs (§5.8, §5.9, §5.15, §5.17–§5.20, §5.26) are a forced operation that calls a helper which saves with the default — the memory-only helper step also creates a game copy that corrupts the forced diff base. Replace the scattered `forceSave: Bool` (+ `FolderEditScope`) with a single `EditWritePolicy` value (memory-only / persist / library-scoped) that is a required parameter (§9.1) and is passed down — including into `addNew`, `removeItemFromParent`, `validateLinks`, repair passes and tag counting.
2. **Undo as scoped deltas.** §5.1–§5.7 share one root: undo steps are whole-item identities with side tables. Store per step: item id, scope/game generation, and before/after of only the changed fields/entries (no `fileUrl`), grouped per user action. Apply with the same three-way `applyEdit`. Clear on game start/end.
3. **Field-level entry diff.** §5.11, §5.12 and part of §5.13 disappear if `mergedEntries` diffs inside an entry (clock-free comparison) and modules declare session-only entry fields.
4. **The link register describes the library only.** Make parsing side-effect free, register only on persisted writes, rebuild from `noGame: true` (§5.18, §5.27, §5.21).
5. **Library reads use `noGame: true` whenever the result is persisted.** Duplicate, delete, folder paths, persisted imports and the forced-save equality check (§5.14, §5.15, §5.21, §5.22, §5.25) all read the game copy and persist it.
6. **Network versions must cover metadata.** File-backed items need a metadata digest separate from the asset version (§5.10); add a during-game test that edits a shown Photo and asserts players receive it.

---

## 11. What was NOT audited

- Modules and code outside the edit pipeline (rendering, 3D table, battle round, audio playback, App Intents beyond their `replace` calls, widgets).
- The full GameRPG transport (SharePlay/LAN framing, journal, pipeline) — only how edits enter it.
- CRDT algorithm correctness beyond the LWW setter behaviour relevant to §5.12.
- Core Data model/CloudKit schema and migrations; `PersistentHistoryTrackerManager` internals beyond author filtering.
- Runtime verification: nothing was run on a device or simulator; §3.1, §5.10 and §5.24 are verified by reading the call chains, not reproduced. visionOS/macOS-specific editor windows were read, not run.
- Tests: the 11 `<Module>EditorWindowDuringGameTests` suites and `GameEditorHarness` were not reviewed in depth (note they do not cover items inside folders — §5.8 — nor undo across game end — §5.1).
- Localization, accessibility and visual design of the editor views.
- Third-party packages (`swift-snapshot-testing`, `RPGTabletopGameContent`, Navigator).

---

## 12. Verification

Command-click the `path:line` references in Xcode. For each High:

- **§5.1** — `Modules/CoreRPG/Controllable/EditControllable.swift:449, 574`: the only two `undoManaged.resetValue` call sites in the repo (grep confirms none in game start/end). `EditControllable+Undo.swift:62-81`: scope is chosen from `persistsEdit`/`writeForcedEditOfGameCopy` at undo time. `ItemControllable.swift:245`: `libraryWriteFilter` only applies while `isGameMode`.
- **§5.2** — `EditControllable.swift:463` pushes `itemOrEmpty(for:).copy()` (whole item); `:489-492` builds `libraryValue.applyEdit(from: gameCopy, to: newValue)` with `gameCopy` = the *current* game copy, so on undo every difference since the step is applied; `EditControllable+Undo.swift:80` writes the snapshot whole in the non-forced path.
- **§5.3** — `EditControllable+File.swift:180` `reset(fileUrl:)` (an undo step via `saveChanges`), `:181-183` `deleteReplaced(replacedFileUrl…)` removes the old file immediately; `EditControllable+Undo.swift:59-83` restores the snapshot (with the old `fileUrl`) and never touches files.
- **§5.8** — `GroupableEntryEditing.swift:55` and `:95` call the 3-arg `removeItemFromParent`; `EditControllable+Folders.swift:37-39` maps it to `scope: .current`; `:169-172` `.current` → `save(updated:message:)` without `forceSave`; `ItemControllable.swift:238-240` → memory-only. The later forced save diffs against that game copy (`EditControllable.swift:489-492`), whose `parentId` is already nil.
- **§5.9** — `TableGenerationController+OutcomeEditing.swift:79` calls `addItem(sheet:)`; `EditControllable.swift:81-83` maps it to `forceSave: false`; `ItemControllable.swift:139-149` (`addNew`) writes the empty item to the store unconditionally.
- **§5.10** — `PhotoModel.swift:155-157`: `version` = `fileUrl?.contentVersion`; `GameControllable.swift:175-178`: `networkVersion` returns `item.version`; `MasterController+PackageCache.swift:28-40`: the file-backed fingerprint is that version only.
- **§3.1** — `CoreDataSnapshotPersistable.swift:33-38` (`replaceSync` → `queueReplace`, no flush); `CoreDataController.swift:167-172` (`fetchSnapshot` reads the context only); `SyncDataControllable.swift:144-150` → `ItemControllable.swift:385-394` (`original.replace(with:)`, field assignment, e.g. `PhotoModel.swift:214-226`). Timing against the periodic flush is not reproduced — treat as High-plausible.

If any reference doesn't reproduce when you open it, name the § number and it will be re-investigated.
