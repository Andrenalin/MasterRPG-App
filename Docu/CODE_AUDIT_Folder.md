# MasterRPG Code Audit — Folder / Item, Import, Game Import, Folder Operations

Generated 2026-10-02. This is a **scoped** audit, not a full-codebase one (the codebase is ~197,600 LOC in 1,824 Swift files under `Modules/` and `Sources/`). Scope, as requested: the folder/item subsystem, file import, game-time imports and every folder operation.

Files in scope:

- **CoreRPG:** `Controllable/` (FolderList*, Item*, Edit*, Import*, Game*, ConvertController, ContextMenuMultiController, Search*), `Model/FolderListModel.swift`, `ItemList/`, `CRDT/`, `Import/`, `Foundry/`, `FileViews/Import*`, `LGViews/` (list, context menu, delete panel, file importer), `LGViewModifiers/ListModelUpdatesViewModifier.swift`, `Menu/` (folder buttons), `Files/` (file create/move/coordination).
- **Per module (12 modules):** `Controller/{FolderListController,ImportController,EditController*,ItemController,GameController*}.swift`, `View/DetailFolderListView.swift`, the item model's `merge` / `duplicate` / `replace(with:)`.
- **Other:** `RolePlayGameKit` import views and Foundry mapper, the `GameRPG` call sites of `importNetwork` / `updateGame` / `reveal`, and `Sources/RPGShare`.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made. Nothing was executed apart from one clean build; every finding comes from reading the code, and anything not traced end to end says "unverified" in its Why line.

---

## 1. Executive summary

Top items to address, in priority order:

1. **[Critical] Children the delete panel keeps are hard-deleted at the next launch** — §5.1 — `Modules/CoreRPG/Controllable/EditControllable.swift:442-466`. Deleting a folder keeps any child that is linked elsewhere, but the trashed folder still lists it, and the launch-time cleanup deletes every listed child with its file.
2. **[Critical] Imported file bytes overwrite an unrelated local file at the same relative path** — §5.2 — `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:52-58`. A backup, a friend's export, a game delivery or a saved game replaces a different item's file when the names match.
3. **[Critical] The Rule module never leaves game mode** — §5.3 — `Modules/AdventureRPG/Controller/GameController.swift:75-83`. After any game, Rule edits are written to game memory only and are gone after relaunch.
4. **[High] Cancelling a folder delete flattens the folder** — §5.4 — `Modules/CoreRPG/Controllable/EditControllable.swift:552-584`. The folder is restored first and detaches its children, so they all end up at root.
5. **[High] Children of a duplicated folder never get their `parentId` persisted** — §5.5 — `Modules/CoreRPG/Controllable/EditControllable.swift:533-535`. The copy looks right until relaunch, then its children sit at root or point at the original folder.
6. **[High] `repairFolder` aborts at the first folder that does not contain the item** — §5.6 — `Modules/CoreRPG/Controllable/EditControllable.swift:224-234`. The post-import folder repair almost never runs, and an Overwrite import of a subset export truncates the local folder (§5.8).
7. **[High] Multi-select actions use row ids as item ids** — §5.7 — `Modules/CoreRPG/Model/FolderListModel.swift:215-217`. Move, duplicate, export and delete silently skip every selected row inside an expanded folder.
8. **[High] Manual review deletes without the trash and runs no repair** — §5.9 — `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:304-318`. Folder children become invisible and links, tags and parent entries are left dangling.
9. **[High] Player packages reach the master with no import policy, and the policy is keyed by bare UUID** — §6.1, §6.2 — `Modules/GameRPG/Controller/MasterController+PhotoMessages.swift:87-107`. A connected player can replace arbitrary items in the game master's session and library.
10. **[High] Cancelling a Foundry commit makes its own rollback fail, and a multi-file drop creates one item** — §3.1, §3.2 — `Modules/CoreRPG/Import/ExternalImportReviewSession.swift:301-332`, `Modules/CoreRPG/Controllable/FolderListControllable.swift:321`.

---

## 2. Quick wins (≤30 min each)

These deliver outsized value relative to effort and have no architectural ripples.

- **Change the inner `return` to `continue` in `repairFolder` and delete its trailing no-op guard** — `Modules/CoreRPG/Controllable/EditControllable.swift:228-229, 233`. Fixes §5.6.
- **Reset the Rule root in `resetGame()`** — `Modules/AdventureRPG/Controller/GameController.swift:80`. Iterate the same root list that `startGame()` sets. Fixes §5.3.
- **Skip children whose `parentId` is not the folder when hard-deleting a folder** — `Modules/CoreRPG/Controllable/EditControllable.swift:451-455`. Closes the data-loss half of §5.1.
- **Restore children before their folder on Cancel** — `Modules/CoreRPG/LGViews/AffectedLinkActionPanelView.swift:60`. Reverse the restore order. Fixes §5.4.
- **Map row ids to `source.itemId` in `selectionItemIds`** — `Modules/CoreRPG/Model/FolderListModel.swift:215-217`. Fixes §5.7.
- **Make "Close parent folder" behave like the close branch of `toggleFolder`** — `Modules/CoreRPG/Controllable/FolderListControllable+FolderLogic.swift:81-89`. Set `lastIsOpen`, `wasExplicitlyClosed` and rebuild. Fixes §5.13.
- **Return an empty list when an empty-text search has no results** — `Modules/CoreRPG/Controllable/FolderListControllable+Search.swift:25, 57`. Fixes §5.14.
- **Call `tagController.remove` in `updateTags`, and guard `markForDeletion` on the item not being trashed already** — `Modules/CoreRPG/Controllable/EditControllable.swift:165-167, 545-550`. Fixes §5.19.
- **Use `category.isCollection` for the Delete menu's disabled state** — `Modules/CoreRPG/LGViews/ListRootContextMenu.swift:287`. Today only `.collection` is covered; albums, playlists, dice bags, bookshelves and model sets are not.
- **Call `update(debounce: false)` from the menu-bar Move/Add buttons** — `Modules/CoreRPG/Menu/MoveItemIntoButton.swift:15`, `Modules/CoreRPG/Menu/AddItemIntoButton.swift:15`. They call `resetFilter()`, which rebuilds from stale results.
- **Pass the live `selectionGeneration` instead of `0`** — `Modules/CoreRPG/LGViews/ListRootView.swift:297`. The on-appear selection restore becomes a no-op after the first navigation reset.
- **Fix the Photo importer's toggle tint (`module: .space`)** — `Modules/PhotoRPG/Photo/InlineImporterView.swift:135`.
- **Delete `EditControllable.update(id:name:…)`** — `Modules/CoreRPG/Controllable/EditControllable.swift:81-87`. No callers, and it calls `reset(name:)` twice.
- **Correct "groupped" in the two undo titles** — `Modules/CoreRPG/Controllable/EditControllable.swift:253, 264`. The text shows in the Undo menu.
- **Add `interactiveDismissDisabled` to the delete panel** — `Modules/CoreRPG/LGViews/AffectedLinkActionPanelView.swift:19-79`. Stops a swipe from leaving items trashed (§5.12).

---

## 3. Concurrency

Compiler ground truth: a full clean build of scheme `MasterRPG` (iOS Simulator, Xcode 27.1, separate DerivedData) finished with **zero Swift compiler warnings**. The only two warnings in the log are `appintentsmetadataprocessor` notices for targets without App Intents. Everything below is what strict concurrency checking cannot see: reentrancy across `await`, untracked tasks and cancellation.

### 3.1 Cancelling a Foundry commit makes its own rollback fail to delete installed attachments
- **Location:** `Modules/CoreRPG/Import/ExternalImportReviewSession.swift:301-332`; `Modules/CoreRPG/Import/ExternalImportReviewSession+Internals.swift:389-401`; `Modules/CoreRPG/Files/FileManager+Coordination.swift:115-122, 258-259`; `Modules/RolePlayGameKit/Import/Foundry/FoundryImportView.swift:87-90, 110-112`
- **What:** Cancel and `onDisappear` cancel `commitTask`; `commit()` then runs `rollback()` inside that cancelled task, and every created file is removed through coordinated access, which begins with `CoordinatedAccessLimiter.acquire()` → `Task.checkCancellation()`.
- **Why:** Once any attachment is installed, a user cancel throws `CancellationError` on every file removal. The files and bookmarks stay in the iCloud documents folder and the user sees "rollback was incomplete" instead of a clean cancel. Whether the Core Data half of the rollback also fails under cancellation is unverified.
- **Action:** Run rollback and superseded-file cleanup shielded from the caller's cancellation, and give cleanup deletes a path that does not consult `Task.isCancelled`.
- **Severity:** High

### 3.2 Dropping several files on the list creates only one item
- **Location:** `Modules/CoreRPG/Controllable/FolderListControllable.swift:320-363` (guard at 321, sleeps at 332 and 344); `Modules/CoreRPG/LGViews/ListRootView.swift:103-105, 174-176`; `Modules/CoreRPG/Files/FileDropDelegate.swift:31-47`
- **What:** `receiveDrop` calls `updateFile(url)` once per dropped provider; each call lands in `add(type:url:root:)`, which returns immediately while `listModel.addItemTask` is set. That task stays set for the file copy plus 1.25 s of fixed sleeps.
- **Why:** A drop of N files creates one item and discards the other N-1 with no log or error.
- **Action:** Replace the "ignore while in flight" guard with a serial queue of add requests or a batch add, and keep double-tap protection at the button.
- **Severity:** High

### 3.3 A cancelled or failed native import keeps a half-applied module with no repair, and can report success
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:159, 195-288` (250, 251-264, 277-287), `345-366`, `647-661`; `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:158-175`
- **What:** Items are applied one at a time. On cancellation or a framing error the function leaves before the deferred folder items, `repairImportedItems` and `finalImport` run, and the `Task.isCancelled` exits at 159, 195 and 250 return normally, so `performImport` calls `finishImport`.
- **Why:** Items whose `parentId` points to a folder later in the stream stay orphaned and invisible in folder mode until the user runs Validate. A cancel that lands between items is shown as "finished", or produces a partial manual review without deletion candidates.
- **Action:** Throw `CancellationError` at every cancellation exit and run the targeted repair for the already-imported ids on the cancel and error paths.
- **Severity:** Medium

### 3.4 One imported item is spread over about ten main-actor hops, so merge and write are not atomic
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:216-230, 418-460, 747-771`; `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:17-24`; `Modules/CoreRPG/Controllable/ItemControllable.swift:176-209, 236-248`
- **What:** `addItem` runs off the main actor and awaits `importMode`, `normalizedImportedItem`, `gameModeImportedItem`, `merge`, `replaceImportedModel`, `repairFolder` and the progress counter as separate hops; `merge`, `gameModeImportedItem` and `replace` each re-read `isGameMode`.
- **Why:** A CloudKit `mergeUpdates` or a user edit between `merge` and `replaceImportedModel` is overwritten by the stale merge result. If the game ends mid-package, a memory-only delivery can be merged and persisted into the library (unverified whether teardown cancels the in-flight handler).
- **Action:** Collapse the per-item read-merge-write-repair into one synchronous `@MainActor` function and capture the memory-only versus persist policy once per import.
- **Severity:** Medium

### 3.5 Several mutation paths bypass `DataMutationCoordinator`
- **Location:** `Modules/CoreRPG/Import/DataMutationCoordinator.swift:10-37`; non-users: `Modules/RolePlayGameKit/Model/AppModel.swift:338-349`, `Modules/CoreRPG/Controllable/GameControllable.swift:372-417`, `Modules/CharacterRPG/Controller/GameController+Sync.swift:54-58`, `Modules/CoreRPG/Controllable/SyncDataControllable.swift:46-134`
- **What:** The coordinator is a try-lock taken only by the file-import panel, the Foundry commit and Validate/Repair. The first-launch example import, game network imports (including `forceSave: true` character packages), CloudKit sync application and direct edits never consult it.
- **Why:** Two imports can interleave on one module, and a repair's `cleanFolder` can strip folder entries for children that a concurrent uncoordinated import has not inserted yet.
- **Action:** Route every bulk writer through the coordinator or a per-module serial mutation queue, and decide explicitly how game-time and sync writes behave during an exclusive mutation.
- **Severity:** Medium

### 3.6 External import commit writes from a pre-await snapshot, and rollback restores whole-module snapshots
- **Location:** `Modules/CoreRPG/Import/ExternalImportReviewSession.swift:144-241, 245-276`; `Modules/CoreRPG/Import/ExternalImportReviewSession+Internals.swift:337-387`; `Modules/CoreRPG/Controllable/ItemControllable.swift:253-310`
- **What:** `existing`/`previous` are captured before the suspension in `attach` and then drive `replaceForExternalImport` and the rollback record. The repair phase snapshots every non-imported model of the module and rewrites all of them on rollback.
- **Why:** A sync or game write to the in-flight item during `attach` is overwritten, and a rollback reverts any item of the module that changed between snapshot and failure (unverified; needs a write arriving during a commit).
- **Action:** Re-read the current model after `attach` and merge or abort if it changed; snapshot only the items the repair touches and compare versions before restoring.
- **Severity:** Medium

### 3.7 The first-launch example import is fire-and-forget and reports success before it runs
- **Location:** `Modules/RolePlayGameKit/Model/AppModel.swift:338-349`; `Modules/RolePlayGameKit/View/DestinationReadyView.swift:72-77`; `Modules/CoreRPG/Controllable/ImportControllable.swift:151-156`
- **What:** `installExampleData` starts `importUrl(from:)`, watches it in an untracked task that only reacts to `.success`, and the caller shows the "data installed" alert on the next main-actor turn.
- **Why:** A failed or still-running import is presented as installed, the error is never surfaced, and it runs without save deferral or the mutation lock.
- **Action:** Make it `async throws`, hold the mutation lock, and show the alert from its real result.
- **Severity:** Medium

### 3.8 `movedFile(itemId:)` runs each file move as an unordered, untracked task
- **Location:** `Modules/CoreRPG/Controllable/EditControllable+File.swift:22-31`; callers `Modules/CoreRPG/Controllable/EditControllable.swift:318-320, 362-366`
- **What:** Every folder add or remove spawns a task that reads the item's `fileUrl`, awaits `folderPath` and the move, then writes the new `FileUrl` back without re-checking the item.
- **Why:** Two quick moves of one item both start from the same old path, so the file ends up where the first move put it, not in the final folder. A move finishing after the item was deleted leaves an orphaned file, and move errors are only logged.
- **Action:** Serialise moves per item, re-read the item after the await, and route failures to `PersistenceIssueCenter`.
- **Severity:** Medium

### 3.9 `ItemControllable.delete` purges pending operations before its suspension points
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:133-169` (purge 147, awaits 150-161, in-memory removal 167)
- **What:** The pending-operation purge runs first; the function then awaits the counter actor, the database delete and the cache actor, and only then removes the item from `itemDataModel`.
- **Why:** A `replace(model:)` that reaches the still-present item in that window queues an upsert that the next flush writes back, resurrecting the deleted row (unverified; the comment at 141-146 describes this failure class).
- **Action:** Remove the item from the in-memory model before the first await, or purge again after the database delete.
- **Severity:** Medium

### 3.10 Sync reconciliation reads two snapshots across an await and can duplicate ids
- **Location:** `Modules/CoreRPG/Controllable/SyncDataControllable.swift:82-95, 105-115, 136-140`; `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:101-118, 141-146`
- **What:** `updateFromSync` awaits `fetchIds()` and then `unsavedInsertIds()`, treating every in-memory id missing from both as remotely deleted. Its "inserted" path applies `resetModel(with:)`, which replaces the stored instance and inserts the id without checking whether it is already listed.
- **Why:** A local insert that commits between the two reads is removed from memory until relaunch. An inserted record whose id is already in memory produces a duplicate id in `items` and leaves open views with a detached instance. Both are unverified at runtime.
- **Action:** Read `unsavedInsertIds` before the fetch, and apply the same known-id check as `updates(_:)` on the inserted path.
- **Severity:** Medium

### 3.11 Game reveal and update act on state read before real suspensions
- **Location:** `Modules/CoreRPG/Controllable/GameControllable.swift:303-317, 334-350, 372-396`; `Modules/CoreRPG/Controllable/FileVersionGameControllable.swift:125-170`
- **What:** `reveal` decides through `hasItem` and then awaits file checks and `updateGame` before `setCurrent`; `updateGame` applies and persists after the off-main `importNetwork`; `backfillContentHashIfNeeded` rebuilds `fileUrl` from the value read before `loadData`.
- **Why:** A game reset during a large delivery is followed by `apply` and `.persist` re-populating the cleared game model, and a file replaced during the backfill load is pointed back at the old URL (unverified; inbound messages are serialised, so the interleaving comes from UI, reset and sync).
- **Action:** Re-validate game mode and item existence after each real suspension.
- **Severity:** Medium

### 3.12 `nonisolated` async helpers run on the caller's actor under approachable concurrency
- **Location:** `Sources/RPGShare/ItemProviderImporter.swift:100-106, 125-131, 210-228`; `MasterRPG.xcodeproj/project.pbxproj:8835, 8909`; `CLAUDE.md:26-29`
- **What:** The project sets `SWIFT_APPROACHABLE_CONCURRENCY = YES`, so a `nonisolated` async function inherits its caller's actor unless marked `@concurrent`. The share extension's in-memory image branch therefore decodes and downsamples on the main actor. `CLAUDE.md` does not mention the setting.
- **Why:** Sharing a large in-memory image hitches the extension UI, and readers following `CLAUDE.md` will assume `importStream`, `updateGame` and `reveal` leave the main actor when their executor depends on the caller.
- **Action:** Mark CPU and I/O helpers `@concurrent`, and add the setting and its convention to the Tech Stack section.
- **Severity:** Medium

### 3.13 Coordinated file access cannot be cancelled once started and shares four slots
- **Location:** `Modules/CoreRPG/Files/FileManager+Coordination.swift:115-148, 156-230, 246-287`
- **What:** `performCoordinatedFileAccess` takes a limiter slot and resumes only when the blocking `NSFileCoordinator` call returns; no cancellation handler calls `coordinator.cancel()`.
- **Why:** A coordinated read stuck on an iCloud download keeps its caller suspended and its slot held; once all slots are held every other coordinated operation waits (unverified how long the coordinator blocks offline).
- **Action:** Keep the coordinator reachable from an `onCancel` handler and cancel it there; consider a separate slot pool for reads that may trigger downloads.
- **Severity:** Medium

### 3.14 Normal edit paths drop persistence errors because no failure reporter is installed
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:34-36, 116-123, 154-158, 186-190, 199-204`
- **What:** `addNew`, `delete` and `replace` catch persistence errors and pass them to `ItemPersistenceFailureScope.reporter?`, a task-local that is set only during the external import's repair pass.
- **Why:** Outside that pass a failed `replaceSync` or `delete` leaves no log, no `lastPersistenceError` and no `PersistenceIssueCenter` entry, so the UI shows an edit that never reached the store.
- **Action:** When no reporter is installed, log and record the error the way `save()` does.
- **Severity:** Medium

### 3.15 Sleeps are used as synchronisation in the add-item flow
- **Location:** `Modules/CoreRPG/Controllable/FolderListControllable.swift:200-214, 326-351`; `Modules/CoreRPG/Controllable/ListSearchTiming.swift:20-30`
- **What:** `add` waits a fixed 1 s before `save()` and 0.25 s before `openHeaderEditor = true`; `applyPostUpdateSelection` sleeps 50 ms in an untracked task before writing `listSelection`.
- **Why:** A selection the user changes during the delays is overwritten, and the header editor opens over whatever item is then selected.
- **Action:** Await the real completion signal, and re-check that the new item is still selected before presenting the editor.
- **Severity:** Medium

### 3.16 A view-capturing closure is stored on the import session model
- **Location:** `Modules/RolePlayGameKit/View/AppImportView.swift:14, 56-66`; `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:46-52, 233-235, 391-413`
- **What:** `saveDeferredHandler` reads and writes `AppImportView`'s `@State nativeImportSaveDeferral`, is stored in `ImportMutationSession`, and is called from the background release task that `onDisappear` starts.
- **Why:** If the state read returns nil after teardown, `endSaveDeferral` is never called and `AppModel.save()` returns early for the rest of the session (unverified). `CLAUDE.md` states this no-view-capture rule for Table3D only.
- **Action:** Keep the deferral token in the session model or `AppModel` and pass closures that capture only the model.
- **Severity:** Medium

### 3.17 Manual review apply can lose its final save and writes parse-time merge results
- **Location:** `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:233-235, 240-268, 304-318`; `Modules/CoreRPG/Controllable/ImportControllable.swift:453-455, 484-513`; `Modules/CoreRPG/FileViews/ImportReviewSplitView.swift:90-92`
- **What:** `applyReview` iterates items with awaits inside an untracked task while `onDisappear` can run the final save and lock release concurrently. Each apply writes `materializedItem()` built from the merged snapshot taken at parse time.
- **Why:** A dismissal mid-apply performs the consolidated save before the remaining items are written, and any sync or other-window change made while the review sheet was open is overwritten (both unverified in practice).
- **Action:** Have the session own the apply as a tracked task that release awaits, and re-merge against the current model at apply time.
- **Severity:** Medium

### 3.18 Folder duplication is unguarded against double invocation, and unique naming is check-then-act
- **Location:** `Modules/CoreRPG/LGViews/ListRootContextMenu.swift:243-247`; `Modules/CoreRPG/Controllable/EditControllable.swift:468-543`; `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:90-134`
- **What:** Each Duplicate press starts an untracked task with no in-flight guard, and `copyFile` picks a "unique" name and then copies with replace semantics.
- **Why:** Two overlapping duplicates of one item can choose the same destination; the second replaces the first's file, and deleting either copy removes the file for both (unverified).
- **Action:** Track the duplicate task per list model, and make name allocation and copy one coordinated step that fails on collision.
- **Severity:** Medium

### 3.19 Smaller reentrancy and task-hygiene issues
- **Location:**
  - `Modules/CoreRPG/Controllable/EditControllable+File.swift:33-88` — `resetFile(url:itemId:)` works on a copy taken before its awaits; two overlapping picks orphan the first new file.
  - `Modules/CoreRPG/Controllable/FolderListControllable.swift:69-92, 246-250` — `performSearch` has no staleness guard when called outside `currentTask`; `performDetailSearch` has one (153-154).
  - `Modules/CoreRPG/Controllable/ItemControllable.swift:356-360` — `mergeUpdates` removes the stale image cache in a follow-up task after the model already changed.
  - `Modules/CoreRPG/Controllable/SyncDataControllable.swift:46-62` — batch ordering relies on outer tasks running FIFO, and a queued batch still applies after `resetData()`.
  - `Modules/CoreRPG/LGViews/ListRootContextMenu.swift:103-105, 374-376, 406-408` — `Task {}` wrappers around the synchronous `update(debounce: false)`.
  - `Modules/CoreRPG/Controllable/ImportControllable.swift:144-156, 166-174, 647-661` — blocking `InputStream` reads on the cooperative pool with no file coordination, and no cancellation check in the header scan and `skip` loops.
- **What:** Six single-site issues of the same family as §3.3 to §3.18.
- **Why:** Each is low-probability on its own; together they explain intermittent "wrong file kept" and "stale list" reports.
- **Action:** Re-read state after each suspension, call synchronous functions directly, and add cancellation checks to the scan loops.
- **Severity:** Low

---

## 4. API modernity

No `ObservableObject`, `@Published`, GCD, `Task.sleep(nanoseconds:)`, `Formatter` subclasses, `String(format:)`, `try!`, `Task.detached`, `nonisolated(unsafe)` or `@unchecked Sendable` in the scope files. Every `@Observable` class in scope is `@MainActor`, and user-text filters use `localizedStandardContains`.

### 4.1 Legacy Foundation and callback APIs
- **Location:** `Modules/CoreRPG/Files/FileManager+Coordination.swift:11`; `Modules/CoreRPG/Import/ExternalImportSourceRegistry.swift:139`; `Modules/CoreRPG/Import/ExternalImportSourceRegistry+Matching.swift:307, 315`; `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:1226, 1260`; `Modules/CoreRPG/Foundry/FoundryTextDecoder.swift:33-41`; `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+DiceAndValues.swift:27, 35`; `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:3, 306, 336-338`; `Modules/CoreRPG/Files/FileDropDelegate.swift:31-47`; `Sources/RPGShare/ItemProviderImporter.swift:230-246`; `Modules/CoreRPG/Controllable/FolderListControllable.swift:212, 217`
- **What:** The scope uses `URL.path`, `components(separatedBy:)`, `NSRegularExpression` compiled on every call, `JSONSerialization`, `NSError` code checks without a domain, an unused `import Combine`, callback-based `NSItemProvider.loadObject`, and `Set(arrayLiteral:)`.
- **Why:** These go against the `CLAUDE.md` modern-Foundation rule. The per-call regex compilation is paid for every decoded HTML string and dice expression, and the domain-less check at `Create:306` treats any error with code 4 as "file already gone".
- **Action:** Move to `path(percentEncoded:)`, `split(separator:)`, static `Regex` values, `CocoaError` matching, `dropDestination(for: URL.self)` and typed item-provider loading; delete the unused imports.
- **Severity:** Low

### 4.2 `ID`/`URL`-cased identifiers break the house `Id`/`Url` rule
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:304-306` (`excludedIDs`); `Modules/CoreRPG/Import/*.swift` (`sourceScopeID`, `fileID`, `attachmentID`, `currentItemID`, `importedIDs`, `directoryURL`, `sourceURL` and others); `Modules/CoreRPG/Files/FileManager+Coordination.swift` (`fileURL`, `fromURL`, `toURL`); `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift` (`initialURL`); `Modules/CoreRPG/LGViews/FileImporterView.swift` (`remoteURL`, `showRemoteURLImporter`); `Modules/RolePlayGameKit/View/AppImportView.swift` (`pendingImportURL`); `Modules/RolePlayGameKit/Import/Foundry/*.swift` (about 400 lines); `Modules/CoreRPG/Foundry/*.swift` (about 240 lines)
- **What:** The whole external-import and Foundry subsystem and parts of the file layer use `…ID`/`…URL`, sometimes beside the house style in the same type (`explicitDirectoryUrl` next to `directoryURL`).
- **Why:** It breaks the explicit `CLAUDE.md` naming rule and makes cross-module call sites inconsistent.
- **Action:** Rename in one mechanical pass per subsystem, keeping `CodingKeys` raw values for persisted and wire names such as `sourceScopeID` and `fileID`.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Children the delete panel keeps are hard-deleted at the next launch
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:442-466` (recursion at 451-455), `552-584` (child branch 572-579), `387-414`; `Modules/CoreRPG/LGViews/AffectedLinkActionPanelView.swift:39-48, 185-196`; `Modules/RolePlayGameKit/Model/AppModel.swift:332-336`; `Modules/RolePlayGameKit/View/DestinationReadyView.swift:48-50`; per-module `itemDataCleanup()`, e.g. `Modules/PdfRPG/Root/PdfRootModel.swift:190-197`
- **What:** Deleting a folder marks the folder and all children as trashed. The panel defaults every item that is linked elsewhere to "not removed" and restores it on Remove; `restore` moves that child to root but leaves it in the trashed folder's `entries`. Five seconds after the next launch `cleanDatabase()` hard-deletes every trashed item through `EditControllable.delete`, which recurses into every entry of a folder without checking the child's `displayState` or `parentId`.
- **Why:** An item the app itself decided to keep because it is in use is permanently deleted, with its file, at the next launch. The trigger is ordinary: delete a folder that contains a photo linked from an adventure and press Remove. The existing test `deleteFolderWithSelectiveChildRemoval` asserts the kept children end at root but never runs the cleanup.
- **Action:** Remove a restored child from its former parent's `entries`, and make the folder delete recurse only into children that still point at the folder and are themselves trashed.
- **Severity:** Critical

### 5.2 Imported file bytes overwrite an unrelated local file at the same relative path
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:220-224, 663-707` (697-701); `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:35-58`; `Modules/CoreRPG/Files/CloudDocumentController.swift:111-121`
- **What:** `addFile` hands every incoming file block to `createNewFileUrl`, which derives the destination from the imported `rawUrl` and writes the data there. The only check is "a file with the same hash is already at that path"; the reuse lookup before it is keyed by the same item id.
- **Why:** A different item with the same file name replaces the local file, and the store is the iCloud container, so the damage syncs. It affects four paths:
  - A friend's export, a backup or a saved game containing `Map.jpg` replaces the local `Map.jpg` of another item.
  - Game deliveries (`forceSave: false`) and the "memory only" saved-game load both write to library storage.
  - In manual review the write happens during parsing, so choosing "existing" or cancelling does not undo it.
  - In merge mode a newer local file at the same path is replaced by the backup's bytes while the model keeps the newer `contentHash`.
- **Action:** Write imported bytes to a collision-free destination, as the external import's `attach` does, only after the item is admitted and the merge or review decision is known. Keep game-memory deliveries off library storage.
- **Severity:** Critical

### 5.3 The Rule module never leaves game mode
- **Location:** `Modules/AdventureRPG/Root/AdventureRootModel.swift:339-344`; `Modules/AdventureRPG/Controller/GameController.swift:75-83`; `Modules/AdventureRPG/Root/AdventureModuleRoot.swift:45-57`; `Modules/CoreRPG/Controllable/ItemControllable.swift:176-181`
- **What:** `startGame()` sets `isGameMode = true` on `siblingModuleRoots`, which includes `ruleRoot`. `resetGame()` iterates `siblingModuleRootsExcludingRule`, and nothing else calls `resetGame()` on the Rule data model.
- **Why:** After any session as game master or player, every Rule edit with the default `forceSave: false` goes to `replaceInGameMemory` only. It looks saved and is gone after relaunch. No call in `Modules/RuleRPG` passes `forceSave: true`. Rule's `gameItemData` is also never cleared, so reads keep preferring it.
- **Action:** Reset the Rule root's game state in `resetGame()` so start and reset iterate the same set of roots.
- **Severity:** Critical

### 5.4 Cancelling a folder delete flattens the folder
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:552-584` (558-571); `Modules/CoreRPG/LGViews/AffectedLinkActionPanelView.swift:59-62, 93-98`; `Modules/CoreRPG/Controllable/EditControllable.swift:387-414`
- **What:** Cancel restores items in list order, folder first. `restore` on a folder sets `parentId = nil` on every child that is still trashed, which at that moment is all of them. Each child is then restored at root.
- **Why:** After Cancel the folder is back but its children sit at root, while the folder's `entries` still list them, so they show in both places. The next repair's `cleanFolder` then empties the folder. Nested folders flatten at every level. The test `restoreFolderWithChildren` asserts the detach as expected behaviour.
- **Action:** Restore children before their folder, or have the folder branch keep `parentId` for children that are about to be restored.
- **Severity:** High

### 5.5 Mutating the live model and passing it to `replace` never persists the change
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:505-543` (533-535); `Modules/CoreRPG/Controllable/GameControllable.swift:303-317`; `Modules/CoreRPG/Controllable/ItemControllable.swift:183-208`
- **What:** `duplicateRecursively` sets `dupChild.parentId` on the instance that is already stored in `itemDataModel`, then calls `replace`. Inside, `original.replace(with: model)` compares the object with itself, returns false, and `replaceSync` is skipped. `backfillContentHashIfNeeded` does the same with `item.fileUrl`.
- **Why:** Children of a duplicated folder have the right parent only in memory. After relaunch, or on other devices, they sit at root (Photo, Pdf and the other models whose `duplicate()` resets `parentId`) or point at the original folder (Audio, Space, Dice, Weather, Generator, Map, whose `duplicate()` copies it), and a later repair empties the copy. The "persisted" content hash is recomputed from the whole file on every launch.
- **Action:** Mutate a `copy()` or `editModel(for:)` and save that, as the surrounding edit operations do.
- **Severity:** High

### 5.6 `repairFolder` returns at the first folder that does not contain the item
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:224-234`; callers `Modules/CoreRPG/Controllable/ImportControllable.swift:446, 451`, `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:317`
- **What:** Inside the loop over all items, the guard on line 228 exits the function instead of continuing. It also returns immediately when the imported `parentId` is nil, and the trailing guard on line 233 does nothing.
- **Why:** After an Overwrite, manual or game import that moves an item, the stale entry in the old folder is removed only if that folder happens to be the first non-parent folder in name order. The item then stays listed in two folders, and deleting the old folder deletes it (see §5.1's recursion).
- **Action:** Continue on a miss, handle the moved-to-root case, and delete the dead guard.
- **Severity:** High

### 5.7 Multi-select context actions use row ids as item ids
- **Location:** `Modules/CoreRPG/Model/FolderListModel.swift:98-106, 194-222`; `Modules/CoreRPG/Controllable/ContextMenuMultiController.swift:21-29, 61-75, 112-141`; `Modules/CoreRPG/LGViews/ListRowItemView.swift:66, 95-106`; `Modules/CoreRPG/Controllable/SearchListController.swift:45`
- **What:** In selection mode the context menu passes `currentSelected: nil`, so the controller uses `selectionItemIds`, an identity pass-through over `selection`. That array holds `FolderListItemModel.id` values, which for rows inside an expanded folder are entry ids or the XOR `childPath` id, not item ids.
- **Why:** `itemSync(for:)` returns nil for those ids, so move, duplicate, add to collection, remove from folder, copy link and the group editor skip them without any feedback. Export silently omits them, and `deleteItems(ids:)` matches nothing. Root-level rows work because their row id equals the item id.
- **Action:** Make `selectionItemIds` map row ids to `source.itemId`, and delete the pass-through helpers.
- **Severity:** High

### 5.8 Overwrite import of a partial folder truncates the local folder and hides its other children
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable+Viewer.swift:25-33`; `Modules/CoreRPG/Controllable/ExportControllable.swift:117-132, 193-199`; `Modules/CoreRPG/Controllable/ImportControllable.swift:449-451`; `Modules/CoreRPG/Controllable/ConvertController.swift:30-34`
- **What:** A subset export writes ancestor folders as partial copies with entries filtered to the exported children. Nothing in the format marks them partial, and Overwrite replaces the local folder with that copy.
- **Why:** Export one item from a folder of ten and import it with Overwrite, or choose "New" in manual review: the folder's entries become that one child. The other nine keep their `parentId`, are not in `importedIds` so are not repaired, and vanish from the folder-mode list until Validate Folders is run.
- **Action:** Mark partial folders in the stream or always union folder entries on import, and extend repair to the previous children of every overwritten folder.
- **Severity:** High

### 5.9 Manual review applies deletions as hard deletes and runs no folder repair
- **Location:** `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:240-268, 304-318`; `Modules/CoreRPG/Controllable/ImportControllable.swift:266-280, 316-336`; `Modules/CoreRPG/Controllable/ItemControllable.swift:133-169`
- **What:** A deletion with decision `.imported` calls `itemControllable.delete(itemId:)` directly, and `applyReview` never calls `repairImportedItems`.
- **Why:** That delete skips the trash and `EditControllable.delete`: the file is removed, the parent folder keeps a dangling entry, a deleted folder's children keep its `parentId` and become invisible, and link register and tags are not cleaned. A subset file also lists every other local item of each module as a "Changed" row whose "New" choice means delete. Decisions default to `.merge` and there is no bulk action, so nothing is deleted without an explicit per-item choice.
- **Action:** Route reviewed deletions through the trash, run the targeted repair over applied ids, and show deletion candidates in their own section or drop them for subset files.
- **Severity:** High

### 5.10 Re-delivery of a Table already in game memory is treated as "nothing imported"
- **Location:** `Modules/TableRPG/Controller/GameController.swift:186-203, 246-254`; `Modules/CoreRPG/Controllable/ItemControllable.swift:328-335`
- **What:** `receiveTableSerialized` detects imported tables by a change of `ObjectIdentifier`, but `replaceInGameMemory` mutates an already-loaded instance in place.
- **Why:** The master edits a table it already revealed this session and reveals it again. The player imports the new package in place, the identity is unchanged, the function returns false, and the new version is never marked available or made current. No test covers a second full package.
- **Action:** Detect imports by id set or version returned from the import, not by object identity.
- **Severity:** High

### 5.11 The share extension stores every image of one share under the same file name
- **Location:** `Sources/RPGShare/ShareExtensionSaveController.swift:45-49`; `Modules/PhotoRPG/Controller/ShareImportPhotoController.swift:19-33`
- **What:** Each image calls `addNewPhoto(… name: name …)`, which builds `/<name>.<ext>` and writes through `createNewFileUrl`; a failure is swallowed by `try?`.
- **Why:** Sharing three images creates three photo items pointing at one path that holds only the last image. It also replaces any library photo already at that name, and an empty name gives `.jpg`. If the write fails, the item is still saved and the extension reports success.
- **Action:** Derive a unique, sanitised file name per image and surface a failed write instead of saving the item.
- **Severity:** High

### 5.12 Delete marks items as trashed before the user confirms
- **Location:** `Modules/CoreRPG/LGViews/ListRootContextMenu.swift:270-277`; `Modules/CoreRPG/LGViews/ListRootView.swift:202-211`; `Modules/CoreRPG/LGViews/AffectedLinkActionPanelView.swift:19-79`
- **What:** The Delete action removes the rows and calls `markCollectionItemsForRemoval`, which sets every item to trashed, and only then opens the confirmation panel. The panel has no `interactiveDismissDisabled`. The context-menu path also navigates to the panel when nothing was removed, because its `guard … else { return }` only leaves the `withAnimation` closure.
- **Why:** Swiping the sheet away on iOS leaves everything trashed with no confirmation, including linked items the panel would have kept; they are hard-deleted at the next launch. Opening the panel with an empty selection shows the previous deletion's list, and Cancel there restores items the user deleted earlier.
- **Action:** Mark items only on Remove, or restore on every dismissal path; clear `removeItems` when the panel closes and skip navigation when nothing was selected.
- **Severity:** High

### 5.13 "Close parent folder" flips the chevron but leaves the children listed, then reopens
- **Location:** `Modules/CoreRPG/Controllable/FolderListControllable+FolderLogic.swift:81-89` (compare 12-18, 29-34); `Modules/CoreRPG/Menu/CloseFolderButton.swift:11`; `Modules/CoreRPG/LGViews/ListRootContextMenu.swift:225`
- **What:** `closeParentFolder(of:)` sets only `isOpen = false` and the selection. It does not set `lastIsOpen`, `wasExplicitlyClosed` or call `resetFilter()`.
- **Why:** The child rows stay in `listModel.list`, and the next rebuild restores `isOpen` from `lastIsOpen`, which is still true. The existing test checks only `isOpen`.
- **Action:** Share the close branch of `toggleFolder(item:)`.
- **Severity:** Medium

### 5.14 A list that becomes empty keeps showing its last rows
- **Location:** `Modules/CoreRPG/Controllable/FolderListControllable+Search.swift:23-25, 54-57`; `Modules/CoreRPG/LGViews/ItemRowsView.swift:16-18`
- **What:** `buildList` and `buildDetailListItems` return the previous list whenever the search returns nothing, to avoid flicker during a text search. The same branch runs for an empty-text search.
- **Why:** Removing or moving the last child out of a folder's detail list leaves that row on screen, and the "Drop here" placeholder never returns. The root list does the same when the last item disappears through sync or an import rollback.
- **Action:** Keep the previous list only while search text is non-empty.
- **Severity:** Medium

### 5.15 Display indexes are used as `entries` indexes
- **Location:** `Modules/CoreRPG/LGViews/ListRowItemView.swift:118-126`; `Modules/CoreRPG/LGViews/ListRootView.swift:202-205`; `Modules/CoreRPG/Controllable/EditControllable.swift:586-612`; `Modules/CoreRPG/Controllable/SearchControllable.swift:99-113`
- **What:** Drag-reorder in a collection and the delete command in a detail list take positions in `listModel.list` and pass them to `moveItems` / `removeItem(offsets:)`, which apply them to the parent's `entries`.
- **Why:** The two orders differ whenever a filter text is active, a child is trashed or missing, a nested collection is expanded, or the same item appears twice (`firstIndex` finds the first one). The wrong entry is then moved. The delete branch is close to unreachable today because detail lists clear `selected` right after navigation.
- **Action:** Resolve rows to entry ids and move or remove by id.
- **Severity:** Medium

### 5.16 A duplicate of a collection member is created hidden
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:241-254, 480-489`; `Modules/AdventureRPG/Controller/EditController.swift:215-222`; `Modules/CharacterRPG/Controller/EditController+Duplication.swift:38-47`
- **What:** All three `duplicate(item:)` implementations add the copy to each collection through `addGroup`, which sets the child's `displayState` to 1 (group-hidden). The context menu's "Add into" and drag-and-drop use `addItem`, which leaves the child visible.
- **Why:** For a member added through the menu, the duplicate does not appear in the root list or in the expanded collection, because both require `fullVisible`. If the original was also in a folder, the copy has a parent and is never picked up by the orphan repair. Design intent is unclear: the tests add collection members with `addGroup` too, so confirm which visibility is intended.
- **Action:** Decide on one visibility rule for collection members and use one function for both paths.
- **Severity:** Medium

### 5.17 A collection accepts the same item twice, producing duplicate row ids
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:287-301`; `Modules/CoreRPG/Controllable/SearchListController.swift:45`; `Modules/CoreRPG/Controllable/SearchControllable.swift:101`
- **What:** `addItem` de-duplicates by `childId` only for folders. In modules where the entry id equals the child id (Adventure, Character, Rule, Pdf, Map, Table, Dice) a second add creates two entries with the same id.
- **Why:** Both rows get the same XOR `childPath` id, so `ForEach` sees duplicate identifiers and both rows share one cached row model.
- **Action:** Reject a second add for those modules, or give collection entries their own id.
- **Severity:** Medium

### 5.18 Folder-entry merge unions by entry id, not by child
- **Location:** `Modules/CoreRPG/CRDT/FolderEntryMerge.swift:11-38`; `Modules/PhotoRPG/Model/PhotoModel.swift:124`; `Modules/AudioRPG/Model/AudioModel.swift:132`; `Modules/SpaceRPG/Model/SpaceModel.swift:125`
- **What:** The union is keyed by `entry.id`. In Photo, Audio and Space the entry id is random and a move creates a new entry, so one child can have two entries with different ids.
- **Why:** Move a photo out of a folder and back, then merge-import an older backup: the folder lists the photo twice, and `cleanFolder` keeps both because the child's `parentId` matches.
- **Action:** De-duplicate folder entries by `childId` after the union.
- **Severity:** Medium

### 5.19 Tag counts drift on every edit and every delete
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:119-128, 155-167, 410-412, 461, 545-550`; `Modules/CoreRPG/LGViews/AffectedLinkActionPanelView.swift:40-46, 87-91`
- **What:** `updateTags(addedTags:removedTags:)` only calls `tagController.add`. `markForDeletion` decrements unconditionally and runs twice per confirmed delete (once in `markCollectionItemsForRemoval`, once in the panel), and `delete(itemId:)` decrements a third time at purge.
- **Why:** Removed tags never lose their count, so stale tags stay in suggestions; confirmed deletes under-count.
- **Action:** Decrement in `updateTags`, and make `markForDeletion` a no-op for an item that is already trashed.
- **Severity:** Medium

### 5.20 Merge import cannot restore a trashed item
- **Location:** `Modules/PhotoRPG/Model/PhotoModel.swift:118-159` (136, 139) and the same block in the other models
- **What:** `merge` always takes `displayState` and `parentId` from the local copy, and `isSame` does not compare `displayState`.
- **Why:** There is no trash UI, so re-importing a backup is the only way to get a deleted item back. In the default merge mode the item stays trashed and is purged at the next launch. Overwrite works.
- **Action:** Treat an imported visible copy as a restore when the local copy is trashed, or tell the user to choose Overwrite.
- **Severity:** Medium

### 5.21 Folder operations during a running game are memory-only, but their file side effects are not
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:176-181`; `Modules/CoreRPG/Controllable/EditControllable+File.swift:22-31`; `Modules/CoreRPG/Controllable/EditControllable.swift:505-522`
- **What:** With `isGameMode` set, `addItem`, `removeItemFromParent` and `duplicate` save into game memory because they pass no `forceSave`. `movedFile` still moves the file on disk and `resetFile(copying:)` still copies it.
- **Why:** A game master who reorganises folders during a session loses the changes at game end, while the library item's `fileUrl` still names the old path of a file that was moved, and duplicated files are left with no item (unverified whether bookmark resolution rescues the moved file).
- **Action:** Either persist library folder operations during a game or skip their file side effects.
- **Severity:** Medium

### 5.22 `updateGame` never persists dependent items
- **Location:** `Modules/CoreRPG/Controllable/GameControllable.swift:106-127, 372-395`
- **What:** `ItemGameModel.apply` computes the newly visible ids after changing only `itemId`, so the result is always empty, the loop persisting `otherItems` never runs, and `deep` is unused.
- **Why:** A `save: true` reveal of a playlist or a character with grouped values persists only the primary item. Children stay in game memory and vanish at game end, leaving a library item that references missing ids.
- **Action:** Have the import report the ids it wrote and persist those, or delete the dead branch and the parameter.
- **Severity:** Medium

### 5.23 `.persist` reveals write the sender's raw snapshot over the player's own library item
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:17-18`; `Modules/CoreRPG/Controllable/GameControllable.swift:334-350, 384-391`; `Modules/CoreRPG/Controllable/ImportControllable.swift:759-771`
- **What:** In game mode `merge` returns the imported model unchanged, and `.persist` then writes it with `forceSave: true`.
- **Why:** A player who already owns the item in an older version loses local edits and takes the master's `parentId`, so the persisted item ends up at root while the player's folder still lists it. Only TableRPG merges before persisting.
- **Action:** Merge against the library copy before persisting and always keep the local `parentId` and `displayState`.
- **Severity:** Medium

### 5.24 Version 0 means "any version", so reveals never refresh modules without a version
- **Location:** `Modules/CoreRPG/Controllable/ItemDiffComparable.swift:16-20`; `Modules/CoreRPG/Controllable/GameControllable.swift:208-217, 334-346`; `Modules/CoreRPG/Controllable/ItemControllable+Viewer.swift:35-39`
- **What:** `hasItem` returns true when `version == 0`, and models without their own `version` (Dice, Adventure, Generator, Weather's default) report 0.
- **Why:** A reveal whose package differs from the player's copy is treated as already present; the payload is dropped and the stale copy persisted (unverified which master actions send changed dice as a reveal).
- **Action:** Give those models a content-digest version and treat 0 as unknown.
- **Severity:** Medium

### 5.25 A loaded saved game shadows the library and leaks into it
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:435-439, 462-474`; `Modules/CoreRPG/ItemList/ItemDataModel.swift:47-50`; `Modules/CoreRPG/Controllable/EditControllable.swift:631-633`; `Modules/GameRPG/SetupViews/SelectedAdventureView.swift:177-182`; `Modules/GameRPG/Root/GameRoot.swift:417-431, 441-469`
- **What:** `gameMemoryOnly` fills `gameItemData` in every module while `isGameMode` stays false; `item(for:)` prefers game data regardless of mode, and the setup screen's clear resets only the map module. Separately, the player controller starts processing messages before `joinGame` calls `startGame()`.
- **Why:** Load a saved game without starting it: every view and export shows the saved versions, and the first ordinary edit writes the whole saved state into the permanent item. Game packages processed during connect are written to the library (unverified timing).
- **Action:** Gate the game-memory preference on `isGameMode` or a loaded-save flag, clear all modules when setup is left, and set game mode before messages can be processed.
- **Severity:** Medium

### 5.26 Imports leave superseded files behind and accept a write that never reached disk
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:691-705`; `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:59-69`; `Modules/CoreRPG/Controllable/GameControllable.swift:229-233`
- **What:** `addFile` never calls `deleteReplaced` for the previous local file, and game end only clears game memory. On a write error `createNewFileUrl` returns a `FileUrl` that carries the bytes in memory; persistence stores the raw value, which drops them.
- **Why:** Files written for hidden deliveries, saved-game loads and declined review items stay in the iCloud container with no item referencing them. With the container full, an import counts the item as imported; it works until the app quits and then points at a file that was never written.
- **Action:** Delete the superseded file after a successful replace, track and remove files written for non-persisted items, and require durable storage for library imports.
- **Severity:** Medium

### 5.27 `duplicate()` carries different fields per model
- **Location:** `Modules/AudioRPG/Model/AudioModel.swift:175-181`; `Modules/SpaceRPG/Model/SpaceModel.swift:178-184`; `Modules/DiceRPG/Model/DiceModel.swift:506-513`; `Modules/AdventureRPG/Model/AdventureModel.swift:219-231`; `Modules/PhotoRPG/Model/PhotoModel.swift:170-176`; and the other seven models
- **What:** Six models copy `parentId` (Audio, Space, Dice, Weather, Generator, Map) and six reset it. Adventure's `duplicate()` omits `diceId`, and Dice's omits `resultCategory`.
- **Why:** The shared duplicate flow then calls `addItem` on a copy that may or may not already claim a parent, and two fields are lost on duplicate.
- **Action:** Define the contract once (parent reset, all persisted fields carried) and bring the twelve implementations in line.
- **Severity:** Medium

### 5.28 MapRPG's item controller stores a cache controller it never exposes
- **Location:** `Modules/MapRPG/Controller/ItemController.swift:14, 18, 23-27`; `Modules/CoreRPG/Controllable/ItemControllable.swift:68, 136-139, 160-161`
- **What:** The controller creates `cacheController` but does not implement `cacheControllable`, so the protocol default `nil` applies.
- **Why:** The shared delete and file-reset paths evict caches through `itemControllable.cacheControllable`, so map thumbnails are never evicted there. This may be an omission.
- **Action:** Expose the controller through `cacheControllable`, or remove the stored property and document where maps evict.
- **Severity:** Medium

### 5.29 Menu-bar commands diverge from the context menu
- **Location:** `Modules/CoreRPG/Menu/MoveItemIntoButton.swift:13-16`; `Modules/CoreRPG/Menu/AddItemIntoButton.swift:13-16`; `Modules/CoreRPG/LGViews/ListRowItemView.swift:132-141`; `Modules/CoreRPG/LGViews/ItemRowsView.swift:42-52`; `Modules/CoreRPG/Menu/AddFolderButton.swift:12-14`; `Modules/CoreRPG/LGViews/ListRootContextMenu.swift:287`
- **What:** The menu-bar Move and the drag-and-drop paths call `resetFilter()`, which rebuilds from stale results; the context menu calls `update(debounce: false)`. `AddFolderButton` calls `addNew` directly and skips `add(type:url:root:)`. Delete is disabled only for `.collection`.
- **Why:** After a menu-bar move the item stays at root and also shows inside the folder until the next search. A new folder from the menu bar is always created at root with no double-tap guard. In an album or playlist detail list, Delete removes the item itself.
- **Action:** Use one implementation per action from both menus (see §9.7).
- **Severity:** Medium

### 5.30 Smaller folder and list inconsistencies
- **Location:**
  - `Modules/CoreRPG/Controllable/EditControllable.swift:339-369` — `remove(itemId:parentId:oneUp:)` ignores the passed parent for folders and uses the item's own `parentId`, so a stale entry in another folder cannot be removed from the UI.
  - `Modules/CoreRPG/Controllable/EditControllable+File.swift:12-20` — `folderPath` recurses up the `parentId` chain with no cycle guard, unlike the walkers that use `FolderTreeDepthLimit`.
  - `Modules/CoreRPG/Controllable/EditControllable+File.swift:22-31`; `Modules/CoreRPG/Controllable/EditControllable.swift:586-604` — only the moved item's own file is moved; moving or renaming a folder leaves descendants' files at the old path, and `removeItem(offsets:)` moves no file.
  - `Modules/CoreRPG/Controllable/FolderListControllable+Search.swift:81-83` (compare 204-208) — children built from search results never get `parentId`, so "Close parent folder" is disabled for them.
  - `Modules/CoreRPG/LGViews/ListRootView.swift:292-298` — the on-appear restore passes a row id where an item id is expected and a literal generation `0`.
  - `Modules/CoreRPG/Controllable/ItemControllable.swift:270-275`; `Modules/CoreRPG/Controllable/FolderListControllable+Search.swift:139-146` — the external import replaces the stored instance of an existing item, while cached rows refresh `model` only when it is nil (unverified at runtime).
  - `Modules/CoreRPG/Controllable/EditControllable.swift:387-414` — the removal list contains a child twice when a folder and its child are both selected.
  - `Modules/CharacterRPG/Controller/GameController+Sync.swift:81-84` — the game-memory refresh assigns an object to itself.
- **What:** Eight single-site issues around folder membership and list state.
- **Why:** Each produces a stale row, a disabled command or a file in an unexpected place.
- **Action:** Fix alongside the related findings above.
- **Severity:** Low

---

## 6. Security

Checked and found sound: the Foundry ZIP reader validates paths, caps sizes, bounds inflate and rejects symlinks; directory sources skip symlinks and check the canonical prefix; `GuardedRemoteDownload` checks redirects, connected addresses and size; block sizes in the native format are capped at 512 MB; the share extension has per-file and total caps.

### 6.1 Player asset packages are imported on the master with no `PeerImportPolicy`
- **Location:** `Modules/GameRPG/Controller/MasterController+PhotoMessages.swift:87-107`; `MasterController+PdfMessages.swift:94`; `MasterController+SpaceMessages.swift:108`; `MasterController+AudioMessages.swift:50-53`; `Modules/CoreRPG/Controllable/GameControllable.swift:372-396, 409-417`
- **What:** When the master does not have the revealed item, it calls `updateGame(data:hide:deep:)`, which runs `importNetwork` with `peerPolicy: nil` over the full module fan-out.
- **Why:** A connected player can send a reveal with a fresh id and a package holding items for any module and any existing id. Each one replaces the master's game-memory copy, which every reader prefers; the file blocks are written to disk (§5.2); the master then re-exports the tampered copies as canonical. Reaching this needs a connected peer (LAN PIN or a FaceTime call), which is the trust model already accepted for the player's own character.
- **Action:** Build a module-restricted policy for every package from a non-master sender, and check package contents against the envelope's id and type before applying.
- **Severity:** High

### 6.2 `PeerImportPolicy` is keyed by bare UUID, capped per package, and its folder repair is memory-only
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:24-52, 409-415`; `Modules/GameRPG/Root/GameRootModel.swift:310-316`; `Modules/CoreRPG/Controllable/EditControllable.swift:371-381`
- **What:** `admit` allows an item the sender introduced before or one that does not exist locally, where existence is checked only in the module being imported and introduced ids are stored per sender without a module. The 256-item cap is created fresh per message.
- **Why:** Three gaps follow:
  - **Cross-module overwrite.** A first package carries a game-master-owned id in a module where it does not exist, so it is admitted and recorded; a second package carries the same id in its real module and overwrites the item persistently.
  - **No session cap.** Repeated packages create unlimited persistent, CloudKit-synced items.
  - **Planted folder.** An admitted new folder may list game-master-owned ids. `cleanFolder` strips them only in game memory, so after the game the library folder still lists them, and deleting it deletes them (§5.1).
- **Action:** Key ownership by module and id, cap per sender per session, strip unadmitted child ids from admitted folders before applying, and run post-import repair with the import's own `forceSave`.
- **Severity:** High

### 6.3 Percent-encoded slashes may pass the traversal filter on read paths
- **Location:** `Modules/CoreRPG/Files/CloudDocumentController.swift:67-85, 270-277`; `Modules/CoreRPG/Files/FileUrl.swift:180-184`
- **What:** The traversal filter compares whole `pathComponents` to `..`, and `fullUrl(fileUrl:)` then re-appends each component as a path.
- **Why:** Unverified: this assumes `pathComponents` yields `../../x` as one component for `..%2F..%2Fx`. If so, a metadata-only item resolves outside the module folder for reads, and a later `createGameData` would send that file to players. Writes are re-split and stay inside. `UntrustedImportTests` has no encoded-slash case. If confirmed this is High.
- **Action:** Reject or split components containing a slash after decoding, assert the standardised result stays under the module root, and add a test.
- **Severity:** Medium

### 6.4 Foundry image normalisation allows 400-megapixel decodes
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryMediaNormalizer.swift:124-133, 172-207`
- **What:** `makeJPEG` accepts up to 20,000 × 20,000 pixels, decodes immediately and redraws into a four-byte-per-pixel context.
- **Why:** A small, highly compressible image declaring that size needs about 1.6 GB twice, which kills the app on iOS during commit; an out-of-memory kill bypasses rollback.
- **Action:** Lower the pixel budget and downsample with ImageIO thumbnailing.
- **Severity:** Medium

### 6.5 Logs publish file error text and user tag names
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:235, 245, 262, 303`; `Modules/CoreRPG/Controllable/EditControllable+File.swift:84`; `Modules/CoreRPG/Controllable/EditControllable.swift:45-51, 152, 162, 518`; `Modules/CoreRPG/Files/CloudDocumentController.swift:42-45`
- **What:** `error.localizedDescription` from file operations is logged as public, and `trackOperation` embeds the save message (for example "Add <tag>") in a string the operation counter logs as public.
- **Why:** Cocoa file errors include the user's file name or path, and tag names are user-authored; both land unredacted in the system log.
- **Action:** Log error domain and code as public with the description private, and pass a fixed operation identifier.
- **Severity:** Low

---

## 7. Performance

### 7.1 Large blobs are hashed on the main actor and held in memory several times
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:663-668, 697, 728-729, 861-881`; `Modules/CoreRPG/Controllable/GameControllable.swift:273-281, 409-412`; `Modules/CoreRPG/Import/ExternalImportReviewSession+Internals.swift:254-255, 298, 318-319`; `Modules/CoreRPG/Files/PeerFileDataStore.swift:50-72`
- **What:** `@MainActor addFile` hashes the incoming bytes, `resetData` hashes them again, and `reusableExistingFileUrl` loads and hashes the existing file. Game packages go through an in-memory output stream and an in-memory input stream.
- **Why:** A 300 to 500 MB PDF or USDZ costs two to three full SHA-256 passes on the main thread during import or mid-game, and exists as file data, memory stream, payload and read buffer at once.
- **Action:** Hash once off the main actor, streamed where a file exists, and stream file blocks between disk and the network payload.
- **Severity:** Medium

### 7.2 External import commit retains every attachment's bytes and snapshots whole modules
- **Location:** `Modules/CoreRPG/Import/ExternalImportReviewSession.swift:141, 255-262`; `Modules/CoreRPG/Import/ExternalImportReviewSession+Internals.swift:254-257, 268-305`; `Modules/CoreRPG/Controllable/ItemControllable.swift:304-310`
- **What:** Each normalised attachment is kept in `loadedAttachments` for the whole commit, `attach` re-reads each installed file to hash it, and repair snapshots copy every item of each touched module.
- **Why:** Attachment ids are unique per item, so the cache is never hit yet holds all converted bytes. A large Foundry world can exhaust memory mid-commit, which bypasses rollback.
- **Action:** Drop or evict the cache after each item, verify with the streamed hash, and snapshot only models the repair can touch.
- **Severity:** Medium

### 7.3 Per-item repair and review work scales with library size
- **Location:** `Modules/CoreRPG/Controllable/ConvertController.swift:74-88`; `Modules/CoreRPG/Controllable/EditControllable.swift:224-234`; `Modules/CoreRPG/Controllable/ImportControllable.swift:271-275, 418-460`; `Modules/CoreRPG/FileViews/ImportReviewModels.swift:103-110, 132-175`
- **What:** `resetLinkRegister` scans every link list per imported item, `repairFolder` walks all items per imported item, and the review rebuilds a signature over all items and copies all of them on every decision change.
- **Why:** A full-library import is O(items × links) on the main actor, and a subset manual import builds a review row for every other local item and re-materialises all of them on each tap.
- **Action:** Look links up through the per-source index, repair once per batch, and compute review memory only for the selected item.
- **Severity:** Medium

### 7.4 List rows are found by linear scans, and row equality walks the subtree
- **Location:** `Modules/CoreRPG/Model/FolderListModel.swift:204-213, 315-325`; `Modules/CoreRPG/Controllable/FolderListControllable+FolderLogic.swift:82, 93, 101, 108, 113-118`; `Modules/CoreRPG/Menu/OpenFolderButton.swift:18-36`; `Modules/CoreRPG/Controllable/ItemControllable.swift:91-97`
- **What:** `selectedItemId`, `folderItem(itemId:)` and friends call `list.first(where:)`; `OpenFolderButton`'s body performs three such scans; `FolderListItemModel.==` compares `children` recursively; `collections(isFolder:in:)` walks all items each time a Move/Add menu body is evaluated.
- **Why:** Cost grows with list length on every body evaluation of the menu commands and every selection read.
- **Action:** Keep an id-to-row index in the list model and compare rows by id plus the fields the row renders.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 Detail routes build a new list model and controller inside `body`
- **Location:** `Modules/PhotoRPG/Route/PhotoDetailRoute.swift:62, 67` and the same two lines in the Adventure, Character, Dice, Map, Pdf, Space and Weather detail routes (20 call sites)
- **What:** The route destination's body calls `root.folderListController.copy(listModel: FolderListModel(…))` and passes the result to the detail view.
- **Why:** The body reads the item dictionaries through `itemSync`, so any item insert or removal in the module re-evaluates it and hands the detail view a fresh, empty list model, search model and display model. Open folders, selection, scroll position and filter text reset.
- **Action:** Own the detail controller in `@State` on the destination view, created once per route value.
- **Severity:** Medium

### 8.2 `ImportProgressPanelView` allocates its session object on every init
- **Location:** `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:21-53`
- **What:** Both initialisers evaluate `State(initialValue: ImportMutationSession(…))` eagerly.
- **Why:** A new `@Observable` object with its handler closures is created and discarded each time the parent body runs; only the first is kept.
- **Action:** Create the session lazily, for example in a task or through an optional state filled on first appearance.
- **Severity:** Low

### 8.3 View content is split into functions instead of `View` structs
- **Location:** `Modules/CoreRPG/LGViews/ListRootContextMenu.swift:64-71, 100-113`; `Modules/CoreRPG/LGViews/AffectedLinkActionPanelView.swift:124-158`
- **What:** `removeActions(parent:)`, `removeItemView(oneUp:)` and `linkHeaderView(for:)` return view content from functions.
- **Why:** `CLAUDE.md` asks for separate `View` structs; the rest of the context menu already follows that.
- **Action:** Extract three small view structs.
- **Severity:** Low

### 8.4 Hard-coded padding, spacing and offsets
- **Location:** `Modules/CoreRPG/ViewModifiers/RemoveItemViewModifier.swift:22-27`; `Modules/CoreRPG/LGViews/ListRowItemView.swift:46-47, 78`; `Modules/CoreRPG/ItemDetail/ItemFileImporterView.swift:50, 73, 100`
- **What:** Fixed point values for padding, the indent per level, badge offsets and spacer minimums.
- **Why:** `CLAUDE.md` asks to avoid hard-coded padding and spacing; the fixed 16-point indent and badge offsets do not scale with Dynamic Type.
- **Action:** Use scaled metrics or default spacing where the value is not a deliberate design constant.
- **Severity:** Low

### 8.5 Accessibility and wording gaps in the delete panel and folder chevron
- **Location:** `Modules/CoreRPG/LGViews/SpecialCategoryFolderIndicator.swift:26`; `Modules/CoreRPG/LGViews/AffectedLinkActionPanelView.swift:36, 111-121`
- **What:** The chevron's label is always "Toggle Folder" with no expanded or collapsed state. The panel title is "Mark for remove N Item" with no plural form, and affected rows use fixed black, white and red backgrounds.
- **Why:** VoiceOver users cannot tell whether a folder is open, the title reads wrong for any count but one, and the fixed colours ignore the theme and increased-contrast settings.
- **Action:** Add an accessibility value for the open state, use a plural-aware string, and take the colours from the theme.
- **Severity:** Low

### 8.6 File picker results are dropped or cannot be retried
- **Location:** `Modules/CoreRPG/LGViews/FileImporterView.swift:52-57`; `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:132, 180-192`
- **What:** `FileImporterView` discards a picker failure with `try?`. The import panel starts its work from `.task(id: loadUrl)`, and its `catch is CancellationError` branch is not reached by a cancelled picker.
- **Why:** A failed pick looks like nothing happened, and picking the same file again after a failed import does not restart the task because the id is unchanged.
- **Action:** Surface picker errors, and key the import task on an attempt counter as well as the URL.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

No `#if false`, `TODO`, `FIXME`, `HACK`, `XXX`, `#warning` or `print()` in the scope files. The only commented-out code is two typealiases at `Modules/CoreRPG/CRDT/LWWRegister.swift:133-134`.

### 9.1 Unreferenced symbols
- **Location:**
  - `Modules/CoreRPG/Controllable/EditControllable.swift:81-87, 144-163` — `update(id:name:…)`, `add(tag:itemId:)`, `remove(tag:itemId:)`.
  - `Modules/CoreRPG/Controllable/FolderListControllable.swift:226-244, 252-262, 285-287` — `copyModel(parentModel:)`, `selectedModel(for:)`; `resetParent(model:)` is called only from tests.
  - `Modules/CoreRPG/Model/FolderListModel.swift:29, 38, 134-137, 143-145, 239-260, 327-329` — `parentItemId`, `level`, `item(itemId:)`, `model(root:)`; `isHidden`, `isFolded` and `destination` are only stored and compared.
  - `Modules/CoreRPG/Controllable/ContextMenuMultiController.swift:5-9, 41-49, 82-98` — `itemCategory`, `generateLink`, and with them the AppKit/UIKit imports.
  - `Modules/CoreRPG/Controllable/ItemControllable.swift:61-62`; `Modules/CharacterRPG/Controller/ItemController.swift:30-36` — `children(itemId:)`, `subChildren(itemId:entryId:)` and the Character override.
  - `Modules/CoreRPG/Controllable/GameControllable.swift:63-72, 91-100` — `append(itemId:)`, `insert(itemId:at:removeIndex:)`, the `onlyItem` parameter.
  - `Modules/CoreRPG/Controllable/ImportControllable.swift:26, 97, 127, 237, 269, 290-296` — `withOverwrite`, `fileWithoutItem`, the two-argument `importStream`, a redundant `break` and `if`.
  - `Modules/CoreRPG/FileViews/ImportReviewModels.swift:27-39, 72-74, 117-119, 211-226` — the three status strings (assigned, never read) and four unused methods.
  - `Modules/CoreRPG/ItemList/ItemEditorModel.swift:17, 38-43`; `Modules/CoreRPG/Model/RemoveEntryListModel.swift:13`; `Modules/CoreRPG/ItemList/ItemDataModel.swift:11, 38` — `reset()`, `hasChangedEntries`, `showDeleteAlert`, `categoryTags`.
  - `Modules/CoreRPG/CRDT/DeltaCRDT.swift:16-46`; `Modules/CoreRPG/CRDT/LWWRegister.swift:105-108, 132-208`; `Modules/CoreRPG/CRDT/ApproxSizeable.swift` — delta-state scaffolding with no callers.
  - `Modules/CoreRPG/Import/ExternalImport.swift:195`; `Modules/CoreRPG/Import/ExternalImportReviewSession.swift:24, 43-48, 73, 81` — test-only API and a write-only `currentItemID`.
- **Action:** Delete; move the test-only API into test support.
- **Severity:** Low

### 9.2 Dead stored state and init parameters in per-module controllers
- **Locations:** `Modules/AdventureRPG/Controller/EditController.swift:62-63, 72`; `Modules/CharacterRPG/Controller/EditController.swift:18, 37`; `Modules/MapRPG/Controller/EditController.swift:14, 17, 21`; `Modules/GeneratorRPG/Controller/EditController.swift:7, 13, 19`; `Modules/TableRPG/Controller/EditController.swift:35-36, 46`; `Modules/CharacterRPG/Controller/ItemController.swift:8, 14, 21`
- **What:** All seven bespoke `EditController` inits take `linkController` and `sheetController` and never use them; several other stored properties are never read.
- **Action:** Remove the parameters and properties and update the seven root-model call sites. This is also what stops some modules from using the generic controllers.
- **Severity:** Medium

### 9.3 Bespoke controllers that now equal the generic ones
- **Locations:** `Modules/RuleRPG/Controller/ImportController.swift:5-19`; `Modules/RuleRPG/Controller/EditController.swift:41-57`; `Modules/PhotoRPG/Controller/EditController.swift:11-30`; `Modules/GeneratorRPG/Controller/EditController.swift:6-28`
- **Action:** Replace the four structs with typealiases plus extensions, as PdfRPG does, and fix the two generic doc comments that say Rule and Generator need their own.
- **Severity:** Low

### 9.4 Twelve near-identical `FolderListController` files
- **Locations:** `Modules/{Adventure,Audio,Character,Dice,Generator,Map,Pdf,Photo,Rule,Space,Table,Weather}RPG/Controller/FolderListController.swift` (30-31 lines each)
- **What:** The files differ only in four route expressions.
- **Action:** Add a generic controller in CoreRPG parameterised by a small per-module routes type. About 360 lines removed.
- **Severity:** Medium

### 9.5 Wrapper and typealias files
- **Locations:** eleven `Modules/*/View/DetailFolderListView.swift`; ten `Modules/*/Controller/ImportController.swift` and five `ItemController.swift` typealias files; `Modules/{Audio,Pdf,Photo,Space}RPG/Controller/ItemController.swift`
- **What:** Audio, Dice and Weather bypass the shared `DetailFolderList` skeleton because it has no bottom-overlay parameter; fifteen files hold one typealias each; four file-backed item controllers repeat the same init.
- **Action:** Add the overlay builder to `DetailFolderList`, collect each module's typealiases in one file, and extract a shared file-backed controller factory.
- **Severity:** Low

### 9.6 Two diverged `InlineImporterView` copies
- **Locations:** `Modules/PhotoRPG/Photo/InlineImporterView.swift:14-93, 127-135, 230-273`; `Modules/SpaceRPG/View/InlineImporterView.swift:7-110, 144-152, 201-233`
- **What:** The fan button, toggle button and offset maths are duplicated. Photo tints its toggle with `.space`, lacks the `.id(preopen)` fix that Space's comment calls necessary, and never reads `supportsImagePlayground`; Space ignores picker failures and never reads `canScan`.
- **Why:** A fix landed in one copy only, and the playground and scanner buttons show on devices that do not support them.
- **Action:** Move the fan container and button into CoreRPG and gate the two buttons on the capability values.
- **Severity:** Medium

### 9.7 Menu-bar buttons duplicate context-menu items
- **Locations:** `Modules/CoreRPG/Menu/MoveItemIntoButton.swift:6-42`; `Modules/CoreRPG/Menu/AddItemIntoButton.swift:6-42`; `Modules/CoreRPG/LGViews/ListRootContextMenu.swift:186-235, 363-428`; `Modules/CoreRPG/Menu/OpenFolderButton.swift`; `Modules/CoreRPG/Menu/CloseFolderButton.swift`
- **What:** Four copies of each action, already drifted ("Close Parent Folder" versus "Close parent folder", `resetFilter()` versus `update`). In the controller, `moveItem` and `addItem` have identical bodies.
- **Action:** Build one parameterised view per action and use it from both places.
- **Severity:** Low

### 9.8 Folder-entry merge copied into nine models, with three models merging differently
- **Locations:** `Modules/AudioRPG/Model/AudioModel.swift:127-148`; `Modules/PhotoRPG/Model/PhotoModel.swift:118-143`; `Modules/SpaceRPG/Model/SpaceModel.swift:119-143`; `Modules/CharacterRPG/Model/ValueModel.swift:132-159`; `Modules/MapRPG/Model/MapModel+Sync.swift:97-137`; `Modules/AdventureRPG/Model/AdventureModel.swift:160-184`; `Modules/DiceRPG/Model/DiceModel.swift:405-439`; `Modules/PdfRPG/Model/PdfModel.swift:114-147`; and four more
- **What:** Nine models repeat the "union for folders, last-writer-wins otherwise" block. Adventure uses last-writer-wins for folders on purpose (its comment says the union resurrects offline deletions), Dice has no folder case and keeps its own `displayState`, and Pdf unions every category.
- **Why:** Folder membership merges with different semantics per module, and the problem Adventure's comment describes still applies to the nine union copies.
- **Action:** Put the entries-merge policy in one CoreRPG helper and choose the policy per module deliberately.
- **Severity:** Medium

### 9.9 Three `duplicate(item:)` implementations and duplicated group management
- **Locations:** `Modules/CoreRPG/Controllable/EditControllable.swift:468-543`; `Modules/AdventureRPG/Controller/EditController.swift:118-187, 193-277`; `Modules/CharacterRPG/Controller/EditController+Duplication.swift:10-123`; `Modules/CharacterRPG/Controller/EditController.swift:220-233, 277-340`
- **What:** The "re-add to parent, then add to every collection" tail and `duplicateFolderEntries` are repeated; only the Core version copies the file. `addNewGroup`, `convertToGroup` and four more group functions are line-for-line copies between Adventure and Character.
- **Why:** Recursion guards differ across the three, and §5.5 and §5.16 have to be fixed three times.
- **Action:** Expose the Core folder walk and collection tail as reusable steps, and move the group functions into a `GroupableModel`-constrained extension.
- **Severity:** Medium

### 9.10 Entry merge-by-name copied four times, fixed in one copy
- **Locations:** `Modules/AdventureRPG/Controller/EditController.swift:303-320`; `Modules/MapRPG/Controller/EditController.swift:372-412`; `Modules/TableRPG/Controller/EditController.swift:112-119`; `Modules/CharacterRPG/Controller/EditController+InlineEditor.swift:147-154`
- **What:** Adventure consumes each existing entry at most once; Map, Table and Character still match with `first(where:)` on the name.
- **Why:** Two same-named entries collapse onto one id in the three unfixed copies.
- **Action:** Move the consume-once match into `EntryDataEditable`.
- **Severity:** Medium

### 9.11 Repeated blocks inside `ItemControllable` and the list code
- **Locations:** `Modules/CoreRPG/Controllable/ItemControllable.swift:133-169, 239-245, 284-300, 337-366`; `Modules/CoreRPG/Controllable/ConvertController.swift:80-88`; `Modules/CoreRPG/Controllable/EditControllable.swift:259-261, 344-346, 357-359, 588-591, 621-623`; `Modules/CoreRPG/Controllable/EditControllable+File.swift:94-101, 123-132`; `Modules/CoreRPG/Controllable/SearchListController.swift:39-60, 113-131`; `Modules/CoreRPG/Controllable/GameControllable.swift:82-89, 112-116`
- **What:** Cache and bookmark cleanup is written three times, the link-register diff three times, the "copy entries, remove, assign back" block five times, the file-name construction twice (once with a force unwrap), and the folder branch of `syncExpandResults` twice.
- **Action:** Extract one helper for each and call it from every path.
- **Severity:** Medium

### 9.12 Raw `displayState` literals mixed with bitmask semantics
- **Locations:** `Modules/CoreRPG/Controllable/EditControllable.swift:252, 263, 307, 457, 548, 567, 582`; `Modules/CharacterRPG/Controller/EditController+Repair.swift:139, 181`; `Modules/PdfRPG/Controller/EditController.swift:69, 111`
- **What:** These sites write `0`, `1` or `2` and assign or compare whole values, while `isGroupHiddenToggle` sets and resets a bit on the same field.
- **Why:** `DisplayStateMask` is a bitmask, so whole-value writes drop other bits and equality checks miss combined states.
- **Action:** Replace the literals with named helpers and decide on one semantics.
- **Severity:** Medium

### 9.13 Oversized files (>500 LOC)
- **`Modules/CoreRPG/Controllable/ImportControllable.swift:884`** — split into models (7-129), protocol and stream loop (131-515), review-diff logging (516-643), file handling (645-781) and the binary reader (806-884). Severity: Medium.
- **`Modules/CoreRPG/Controllable/EditControllable.swift:741`** — split along the existing MARKs; give the folder section (238-415) its own file. Severity: Medium.
- **`Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:1282`** — split into reader and caches, decoder, document decoder, type inference and validation. Severity: Low.
- **Others:** `FoundryRuleModels.swift` (847), `FoundryImportView.swift` (712), `FoundrySystemPackageReader.swift` (705), `DiceModel.swift` (687), `FoundryVTTDomainMapper+Documents.swift` (584), `UniversalVTTReader.swift` (573), `FoundryVTTArchiveSanitizer.swift` (501). Severity: Low.

### 9.14 Comments that no longer match the code
- **Locations:** `Modules/CoreRPG/Model/FolderListModel.swift:286`; `Modules/CoreRPG/Controllable/FolderListControllable.swift:54-59, 112-113, 126-128, 143, 279-280`; `Modules/CoreRPG/Controllable/SearchRootControllable.swift:10, 17, 20`; `Modules/CoreRPG/Controllable/ImportControllable.swift:290`; `Modules/CoreRPG/Controllable/GenericImportController.swift:13-14`; `Modules/CoreRPG/ItemList/ItemDataModel.swift:33-36`
- **What:** References to `resetDetailLink` and `results(text:focusId:)`, which do not exist; a doc comment saying `Self` construction is not hoisted when it is; caller lists that are out of date; "SwiftData" where items load through Core Data; a "cancel-and-replace" comment on a property that is chained, not cancelled.
- **Action:** Update or delete.
- **Severity:** Low

### 9.15 Misspelled and misleading names; types in the wrong files
- **Locations:** `Modules/CoreRPG/ItemList/EntryDataEditable.swift:40, 142, 297-299` (`additioanlEnrtryViewType`); `Modules/CoreRPG/ItemList/EntryDataAccessible.swift:39-51` (`EmtpyEntryViewModel`); `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:27-28` (`oldFileUlr`); `Modules/CoreRPG/Model/RemoveEntryListModel.swift:20` (`canRemoved`); `Modules/CoreRPG/Model/FolderListModel.swift:239-245` (`isShown` assigned to `isOpen`); `Modules/CoreRPG/Controllable/EditControllable.swift:241-265` (`addGroup` adds to a collection); `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:7-18, 321-414` (session model and URL provider in a view file); `Modules/CoreRPG/CRDT/UnequalAssignment.swift` (the `<=>` operator under `CRDT/`)
- **Action:** Rename, and give each type its own file in the matching folder.
- **Severity:** Low

### 9.16 Hard-coded English and inconsistent user-visible strings
- **Locations:** `Modules/CoreRPG/Import/ExternalImport.swift:269-294`; `Modules/CoreRPG/Import/ExternalImportReviewSession+Internals.swift:349-398`; `Modules/CoreRPG/Foundry/FoundryRuleModels.swift:801-846`; `Modules/CoreRPG/Controllable/ItemControllable.swift:41-46`; `Modules/CoreRPG/Controllable/ContextMenuMultiController.swift:55`; `Modules/CoreRPG/Controllable/EditControllable.swift:134`; `Modules/CoreRPG/Model/ChildEntryModel.swift:20`; `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:102, 212`
- **What:** Every `errorDescription` for external and Foundry imports, the rollback messages, "\(name) and N more", the "hide"/"show" words inside a localised undo title and the constant entry names are English literals. "OK" and "Ok" are separate keys. Undo titles are built with a second `.localizedString` lookup keyed by the already-translated text.
- **Why:** The error text reaches the import failure UI, and the menu and undo titles are shown directly.
- **Action:** Wrap in `String(localized:bundle:)` with a plural-aware key, pick one spelling per string, and drop the second lookup.
- **Severity:** Medium

### 9.17 Importer-neutral registry is tied to Foundry; module order is defined three times
- **Locations:** `Modules/CoreRPG/Import/ExternalImportSourceRegistry.swift:106-111`; `Modules/CoreRPG/Import/ExternalImportReviewSession+Internals.swift:21-34`; `Modules/RolePlayGameKit/Model/ModuleFolderRepairable.swift:44-58`; `Modules/AdventureRPG/Controller/ImportController.swift:40-46`
- **What:** The registry stores its index under a hard-coded "foundry/sources" path. The module processing order exists as three separate lists, and Generator is in the import order but not in the repair steps.
- **Action:** Use importer-neutral names and derive the three orders from one shared list.
- **Severity:** Low

### 9.18 Magic constants
- Fixed sleeps of 1 s, 0.25 s and 50 ms at `Modules/CoreRPG/Controllable/ListSearchTiming.swift:20-30` are named but act as synchronisation (§3.15).
- The 5 s cleanup delay at `Modules/RolePlayGameKit/View/DestinationReadyView.swift:23` decides when trashed items are purged (§5.1).
- The 20,000-pixel limit at `Modules/RolePlayGameKit/Import/Foundry/FoundryMediaNormalizer.swift:124-133` (§6.4).
- **Severity:** Low

---

## 10. Cross-cutting recommendations

Patterns worth applying across the subsystem rather than one finding at a time:

1. **Make folder membership single-sourced.** A folder's `entries` and each child's `parentId` are written separately and repaired after the fact. §5.1, §5.4, §5.6, §5.8, §5.9, §5.18 and §6.2 are all the same failure: one side changed and the other did not, and a later delete or repair trusted the stale side. Treat `parentId` as the truth for folders, derive `entries` from it (or validate against it in every reader), and make the recursive delete check it.
2. **Stop mutating before deciding.** The delete panel trashes items before confirmation (§5.12), manual review writes files before the user chooses (§5.2), and the native import applies item by item with no rollback (§3.3). The external import already has the right shape: stage, then commit, with rollback. Reuse it.
3. **Never mutate a live model instance and then save it.** `replace` compares the stored object with the argument, so in-place mutation is silently not persisted (§5.5). Every write should go through `editModel(for:)` or `copy()`. A debug assertion in `replace` that the argument is not the stored instance would catch the remaining sites.
4. **Give game memory one switch.** `isGameMode` is set and reset over different root lists (§5.3), game data is preferred regardless of the flag (§5.25), library edits during a game are memory-only while their file effects are real (§5.21), and game deliveries write library files (§5.2). One per-session object that owns "is a game running", start and reset for all modules, and file staging would cover all four.
5. **Keep row ids and item ids as different types.** §5.7, §5.15, §5.17 and parts of §5.30 come from passing a row id where an item id is expected, or a display index where an entry index is expected. A small wrapper type for the row id would turn these into compile errors.
6. **Import files to collision-free destinations.** §5.2 and §5.11 are the same missing uniqueness check; `copyFile` and the external import already allocate unique names.
7. **Collapse the per-module copies.** The folder list controller (§9.4), duplicate (§9.9), merge (§9.8) and menu actions (§9.7) exist in three to twelve copies each, and several findings above are a fix that reached only one copy.

---

## 11. What was NOT audited

- Everything outside the folder/item/import scope listed at the top: the game network transport, SharePlay, Table3D, the dice widget, the sheet editor, link rendering, PDF extraction and Generator. `Docu/CODE_AUDIT_Network.md`, `Docu/CODE_AUDIT_Import.md` and `Docu/CODE_AUDIT_EditItem.md` cover adjacent areas; findings fixed there were not re-checked.
- The Foundry directories (`Modules/CoreRPG/Foundry`, `Modules/RolePlayGameKit/Import/Foundry`) were read for security, cancellation and size limits; the dead-code pass only outlined them. Mapping correctness from Foundry documents to domain models was not assessed.
- Runtime behaviour. Nothing was run apart from one clean build of scheme `MasterRPG` for the iOS Simulator; the macOS, tvOS and visionOS schemes were not built.
- Core Data and CloudKit internals (`CoreDataPersistenceController`, the snapshot persistence layer) beyond the calls the item controller makes into them.
- Tests under `Tests/` — read only to check whether a behaviour is asserted; no coverage review.
- Build settings and project structure, apart from confirming `SWIFT_APPROACHABLE_CONCURRENCY`.
- Localization wording and the string catalogs; only untranslated literals in scope were noted.
- Performance profiling. §7 lists potential hot paths from reading; no Instruments trace was taken.

---

## 12. Verification

Spot-check pattern: open Xcode and command-click the `path:line` reference; it should land on the cited line. I opened and traced every Critical and High item below myself after the agents reported.

- **§5.1** — open `Modules/CoreRPG/Controllable/EditControllable.swift`, lines `451-455`: the folder branch calls `delete(itemId: entry.childId, …)` for every entry with no check on the child. Lines `572-579`: restoring a non-folder only clears `item.parentId`; the parent's `entries` are untouched. `Modules/CoreRPG/LGViews/AffectedLinkActionPanelView.swift`, line `189`: `canRemoved: links.isEmpty`. `Modules/RolePlayGameKit/View/DestinationReadyView.swift`, lines `48-50`: the cleanup runs after a 5 s sleep on every launch.
- **§5.2** — open `Modules/CoreRPG/Files/FileUrlDataController+Create.swift`, lines `35-58`: the only skip is an equal hash at the same path; line `52` derives the destination from the imported `rawUrl` and line `58` writes. `Modules/CoreRPG/Controllable/ImportControllable.swift`, lines `220-224`: `addFile` runs before `addItem`, in every mode.
- **§5.3** — open `Modules/AdventureRPG/Root/AdventureRootModel.swift`, lines `339-344` (loop over `siblingModuleRoots`), then `Modules/AdventureRPG/Controller/GameController.swift`, line `80` (loop over `siblingModuleRootsExcludingRule`). A repo-wide search for `resetGame(` and `isGameMode =` shows no other reset.
- **§5.4** — open `Modules/CoreRPG/Controllable/EditControllable.swift`, lines `558-565`: a still-trashed child gets `parentId = nil`. `Modules/CoreRPG/LGViews/AffectedLinkActionPanelView.swift`, line `60`: Cancel restores `linkTree` in order, and `markCollectionItemsForRemoval` (`387-414`) puts the folder first.
- **§5.5** — open `Modules/CoreRPG/Controllable/EditControllable.swift`, lines `533-535`, then `Modules/CoreRPG/Controllable/ItemControllable.swift`, lines `183-196` and `206`: the inserted instance is the stored instance, and `Modules/PhotoRPG/Model/PhotoModel.swift`, line `224` returns false for a self-comparison.
- **§5.6** — open `Modules/CoreRPG/Controllable/EditControllable.swift`, line `228`: `else { return }` inside the `for` loop.
- **§5.7** — open `Modules/CoreRPG/Model/FolderListModel.swift`, lines `194-217`: `selection` is filled from `listSelection` (row ids) and `selectionItemIds` returns it unchanged. `Modules/CoreRPG/Controllable/SearchListController.swift`, line `45`: a folder child's row id is the entry id or the `childPath` id.
- **§5.8** — open `Modules/CoreRPG/Controllable/ItemControllable+Viewer.swift`, lines `25-33` (entries filtered for partial folders) and `Modules/CoreRPG/Controllable/ImportControllable.swift`, lines `449-451` (Overwrite replaces the model).
- **§5.9** — open `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift`, lines `304-318`: the deletion branch calls `itemControllable.delete`, and `applyReview` (`240-268`) has no repair call.
- **§5.10** — open `Modules/TableRPG/Controller/GameController.swift`, lines `246-254` (identity comparison) and `Modules/CoreRPG/Controllable/ItemControllable.swift`, lines `328-335` (in-place mutation).
- **§5.11** — open `Sources/RPGShare/ShareExtensionSaveController.swift`, lines `45-49`: the same `name` for every image; `Modules/PhotoRPG/Controller/ShareImportPhotoController.swift`, line `27`: the path is built from it.
- **§5.12** — open `Modules/CoreRPG/LGViews/ListRootContextMenu.swift`, lines `270-277`: marking happens before navigation, and navigation runs even when the guard returned.
- **§3.1** — open `Modules/CoreRPG/Files/FileManager+Coordination.swift`, line `259` (`try Task.checkCancellation()` at the top of `acquire`) and `Modules/CoreRPG/Import/ExternalImportReviewSession.swift`, lines `301-309` (rollback runs in the same task).
- **§3.2** — open `Modules/CoreRPG/Files/FileDropDelegate.swift`, lines `31-47` (one call per provider) and `Modules/CoreRPG/Controllable/FolderListControllable.swift`, line `321` (the in-flight guard).
- **§6.1** — open `Modules/GameRPG/Controller/MasterController+PhotoMessages.swift`, line `95`: `updateGame` is called with the player's package and no policy.
- **§6.2** — open `Modules/CoreRPG/Controllable/ImportControllable.swift`, lines `42-52` and `Modules/GameRPG/Root/GameRootModel.swift`, lines `310-316`: a new policy per message, seeded with ids stored per sender without a module. The three-step exploit chain was traced by the audit agent; I confirmed the policy code, not the chain.

Medium and Low findings from the three audit agents were not all re-opened; those I could not confirm, or that depend on timing, say "unverified" in their Why line. If a finding does not reproduce when you visit the line, tell me the reference and I will re-investigate.

---

## 13. Remediation status (2026-10-03)

Status of §3 after the remediation pass. **Fixed** = changed, and the iOS, macOS, tvOS and visionOS apps build with zero warnings; the `MasterRPG` unit test plan passes (1,830 tests). Regression tests added: `Tests/CoreRPGTests/FolderAuditConcurrencyTests.swift` (§3.5, §3.11, §3.19) and `cancelledImportThrows` in `Tests/TableRPGTests/ImportControllerTests.swift` (§3.3). Timing-dependent races were fixed by reading the code; they are *not runtime-verified*.

| § | Status | Notes |
|---|---|---|
| 3.1 | Fixed | Rollback, its consolidated save, and the superseded-file cleanup run in unstructured tasks, which do not inherit the cancellation. |
| 3.2 | Fixed | A plain Add still ignores a double tap; adds that carry a dropped file queue behind the running one, so a drop of N files creates N items. |
| 3.3 | Fixed | Every cancellation exit throws; the targeted folder repair runs for the already-applied ids on cancel and error, shielded from the cancellation. |
| 3.4 | Fixed | One synchronous `@MainActor` `applyImportedItem` per item (normalise, merge, write, repair). Game-memory vs. library is captured once per module stream (`ImportApplyPolicy`); a memory-only delivery arriving after the game ended is dropped. |
| 3.5 | Fixed | Decision: sync batches and game network imports `waitUntilIdle()` and then apply; bulk writers take the lock; direct UI edits stay uncoordinated. The example install takes the lock (§3.7). |
| 3.6 | Fixed | After the `attach` suspension the library item is compared with the pre-read copy; a change aborts and rolls back (`itemChangedDuringImport`). Repair snapshots cover only the items the repair can reach and are restored only if they still look as the repair left them. |
| 3.7 | Fixed | `installExampleData` is `async throws`, holds the mutation lock and save deferral; the first-launch alert shows the real result, with a new failure alert (de/th translations added). |
| 3.8 | Fixed | File operations are queued per item (`enqueueFileOperation`); the item is re-read after the move; a file moved for a deleted item is removed; move errors reach `PersistenceIssueCenter`. |
| 3.9 | Fixed | The item leaves memory before the first suspension; pending operations are purged again after the database delete. |
| 3.10 | Fixed | Unsaved-insert ids are read before and after each fetch and combined; an "inserted" id already in memory is merged like an update. |
| 3.11 | Fixed | `ItemGameModel.resetGeneration` is re-checked after the import in `updateGame` and in `reveal`; the apply and persist run in one main-actor step. The hash backfill re-checks the file after loading and writes through `persistFileUrl`. Ledger scans merge per item (`apply(scanned:for:startedFrom:)`). |
| 3.12 | Fixed | The share extension's in-memory image branch decodes through `runOffCallerExecutor`; `CLAUDE.md` documents approachable concurrency. |
| 3.13 | Partly | Cancelling the caller now cancels the `NSFileCoordinator` it is blocked in. A separate slot pool for download-triggering reads was not added. |
| 3.14 | Fixed | `recordPersistenceFailure` logs and surfaces the error when no transaction reporter is installed. |
| 3.15 | Fixed | The 1 s settle and 0.25 s editor delays are gone: the add awaits the file attach, the save and the list refresh, and opens the header editor only if the new item is still selected. The 50 ms render delay stays, with a re-check of the user's selection. |
| 3.16 | Fixed | The import session owns the save-deferral token; `AppImportView` passes closures that capture only the app model. |
| 3.17 | Fixed | The review apply is a session-owned task that release waits for. The parse-time existing item is now a copy; if the library item changed while the sheet was open, the reviewed result is merged onto it. |
| 3.18 | Partly | Duplicate is ignored while one is running (both menus). File copies never replace an existing file and retry the next free name. The in-memory-bytes branch of `copyFile` still writes with overwrite. |
| 3.19 | Fixed | `resetFile(url:)` is queued and re-reads the item; root searches discard superseded results; `mergeUpdates` drops the cache before the model changes; sync batches use one ordered stream consumer and batches queued before `resetData()` are skipped; the `Task {}` wrappers are removed; the import scans check cancellation and a picked file gets a coordinated read first. |
