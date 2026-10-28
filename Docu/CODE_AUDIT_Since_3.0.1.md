# MasterRPG Code Audit — changes since 3.0.1

Generated 2026-10-27. Scope: every Swift change from tag `3.0.1` to `HEAD` (`3fef072ac`, 23 commits, `develop`): 200 non-test Swift files, +7,245 / −2,989 lines, plus 59 test files. Main areas: the App Intents / Siri / Spotlight layer in all 12 modules, the Quick Dice overlay, the returning Quick Link, the duplicate-link fix, map photo replacement with resize, iPad layout restore, the macOS external player window, and the Space inline viewer.

Findings cite `path/to/file.swift:LINE`. No code was changed. Earlier audits of the same code are not repeated: `CODE_AUDIT_AppIntents.md`, `CODE_AUDIT_AppIntents2.md`, `CODE_AUDIT_AppIntents3.md` and `CODE_AUDIT_QuickDice.md` (their §0 tables were checked against the current code; their fixes hold except where noted in §3.1, §5.6 and §7.1).

**Compiler ground truth.** A clean `xcodebuild build` of the `MasterRPG` scheme (iOS Simulator, separate DerivedData) produced 16 warning lines. They group into three root causes: 1 Swift warning (§4.4), 2 benign "metadata extraction skipped" notes for resource bundles, and 12 App Shortcuts NLU warnings that are new in this range (§4.3). No concurrency warnings.

**Verification.** Both High findings and most Medium findings were confirmed by reading the cited lines (§12). Findings marked *unverified at runtime* look right in the code but were not seen in a running app.

---

## 0. Status

Updated 2026-10-28. Findings not listed are open.

| § | Status | Fix | Tests |
|---|---|---|---|
| 3.1 | Fixed | `setItem` no longer marks ids. New `AppEntityIndexLedger` (`Modules/CoreRPG/App/AppEntityIndexLedger.swift`) keeps, per module, the ids the index covers in Application Support/AppEntityIndex. `reindexIntentEntities` looks only at marked ids plus ids added or removed since the ledger, and waits until every initial load has finished. The ledger file's absence replaces the `AppEntityIndexPruned.*` flag, so each install prunes and fully indexes once more after updating. Items the share extension added while the app was closed are new to the ledger and are indexed. | `IndexDirtyTrackingTests.swift`: `AppEntityIndexPassTests`, `AppEntityIndexLedgerTests`, and the initial-load test in `IndexDirtyTrackingTests` |
| 3.2 | Fixed | `EntitySummaryExport.pdf` is `async` and renders through `runOffCallerExecutor`. `intentFileData` is `async` and reads `IntentFile.data` off the caller's actor. Updated 10 call sites. | `EntityPdfExportTests`, `IntentFileIntakeTests` (now async) |
| 3.3 | Fixed | The reindex runs in its own `reindexTask`, started synchronously after the debounce sleep, so `invalidate()` cancels only the sleep. | `AppIntentContentInvalidatorTests` now also checks that the running reindex is not cancelled |
| 3.4 | Fixed | `requireReadyDatabase()` calls `Task.checkCancellation()` after the wait. | `DatabaseGateCancellationTests` |
| 3.5 | Fixed | `donateStartGame(of:)` is synchronous and donates in a `Task`. `startMaster` calls it last, after the controllers exist and the game has started. | None: the donation goes to the system. |
| 4.1 | Fixed | New `IntentDialog.verbatim(_:)` / `LocalizedStringResource.verbatim(_:)` (`Modules/CoreRPG/Controllable/IntentDialog+Bundle.swift`). The resource looks in the `IntentVerbatim` table, which no catalog has. It is built without a literal, so Xcode extracts nothing, and it always resolves to the text as is. Replaced all 15 `dialog: "\(…)"` sites: 12 Delete intents, `RollTableIntent`, and the two in `RunGeneratorIntent`. | `IntentDialogVerbatimTests` |
| 4.2 | Fixed | `ExternalPlayerWindow` uses `bundle: .module`. The German and Thai translations moved from the app catalog (stale entry removed) into the RolePlayGameKit catalog. | None: the unit tests are not hosted in the app on iOS, so they can't load RolePlayGameKit's bundle. |
| 4.3 | Fixed; worse than reported | Not benign. With the four parameterized phrases, the App Intents training step logged `error: Could not archive SSU artifacts`, and the app shipped without `Metadata.appintents/root.ssu.yaml`, which is the flexible-matching data for all 10 App Shortcuts. A build without those phrases had no warnings and shipped the file. With the user's agreement, the phrases were removed (from the code and from the `AppShortcuts.xcstrings` sets in de, en and th). Each shortcut got a fixed second wording instead: "Show an adventure", "Play an adventure". The parameter refresh (`updateAppShortcutParameters`, `AdventureIntentSupport.shortcutNames`) was removed with them. Open and Start now ask which adventure. | None: a clean build showing no NLU warnings and the shipped `root.ssu.yaml` is the check. |
| 5.1 | Fixed | Both safeguards, as the user asked. (1) Quick Link links only entry content. The new `QuickLinkScanner.applyToContent` uses `EntryTextParser.transformingContent(of:_:)`, which follows `parse` line by line and leaves title lines and empty lines alone; the quick editor calls it. (2) Matching always goes through `withoutLink()`. `entriesMatchedByName` (Adventure, Character, Map, Table) and Rule's name fallback in `mergeEntries` compare names without link markup. A matched entry takes the edited name, so a link typed into a title by hand is kept along with the entry's id, outline, dice and formula. The table being edited stays in the picker. Choosing it skips the scan (`QuickLinkScanner.scan` returns `.sameTable`), and the Quick Link alert explains why (de and th added). | `QuickLinkScannerTests` (content only, parsed names unchanged for five layouts, CRLF untouched, same table ignored); Map `EditControllerTests.quickLinkThenApplyKeepsRooms` / `linkedTitleKeepsRoom` (ids and outlines kept); `RuleModelTests.linkedNameFallback` |
| 5.2 | Fixed | User decision: persist when the item isn't in the game. Every intent write passes `forceSave: true`, so Create (12), Add Entry (6), Add Die, Append Note/Description (5), Update (12, `updateIntentItem`) and Delete (12, `trashIntentItems`) write to the library during a game. A Create's file goes there too: `resetFile`/`resetPhoto`/`reset(fileUrl:)`, `markForDeletion` and Dice `add(die:)` gained a `forceSave` parameter defaulting to `false`. An item the game has loaded (it has a game copy in `gameItemData`) is refused with the spoken `ItemInGameError` ("This is part of the current game. Change it after the game has ended.", de and th added) before anything changes, so the session state of that copy (HP, revealed rooms) never leaks into the library or gets overwritten. `requireOutsideGame(_:in:)` in `IntentEntityHelpers.swift`. A Delete of several items is refused as a whole when one of them is in the game. | `TableRPGTests/IntentGameModeWriteTests` (create persists versus old memory-only path, update/add/trash persist, update and trash refused for game items, no-game unchanged); `PhotoRPGTests/IntentGameModeFileTests` (file on the library item with `forceSave`, default unchanged) |
| 4.4 | Fixed | The warning came from `Transcript.Entry.data`, which is new in the 27.2 SDK; the existing `@unknown default` didn't cover it. A plain `default` takes it. Naming `.data` would break the build on Xcode 27.1. | None: compiler warning; the clean build is warning-free. |

Not verified at runtime: the launch behavior of §3.1 (no Spotlight indexing on a launch without changes) was not measured in a running app. §4.3: Siri's flexible matching was not tried by voice on a device.

---

## 1. Executive summary

1. **[High] Quick Link turns entry titles into links, so on Apply those entries are re-created and lose their data** — §5.1 — `Modules/CoreRPG/Links/QuickLinkScanner.swift:38-63`, `Modules/CoreRPG/ItemList/EntryDataEditable.swift:244`. Map rooms lose their polygons, and character values lose their type, dice and formula.
2. **[High] During a running game, Create, Update and Delete intents write only to game memory but tell Siri they succeeded** — §5.2 — `Modules/CoreRPG/Controllable/ItemControllable.swift:231-233`. A character created by voice during a session is gone when the game ends.
3. **[Medium] The Generator module lost all its menu commands on every platform** — §5.3 — `Sources/MasterRPG/Menu/MenuCommandList.swift:37-43`.
4. **[Medium] Every cold launch re-indexes every App Entity of all 12 modules on the main actor** — §3.1 — `Modules/CoreRPG/ItemList/ItemDataModel.swift:105-108`. This partly undoes the fix for AppIntents §7.1.
5. **[Medium] "Delete folder X" from Siri trashes the folder but not its children** — §5.4 — `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:296-306`.
6. **[Medium] Spotlight results for trashed items still open the item** — §5.6 — `Modules/CoreRPG/Persistence/SpotlightActivityRoute.swift:54-64`.
7. **[Medium] Write intents report success when the save failed** — §5.5 — `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:83-96`.
8. **[Medium] Join Game by Siri fails unless the player-setup view has appeared in this run** — §5.7 — `Modules/GameRPG/Intent/GameIntents.swift:154`.
9. **[Medium] The PDF export and intent file reads run synchronously on the main actor** — §3.2 — `Modules/CoreRPG/Intent/EntitySummaryExport.swift:43-79`.
10. **[Medium] About 83% of the per-module intent code is copy-paste, and the new Update intent was added 12 times** — §9.1.

---

## 2. Quick wins (≤30 min each)

- **Put `GeneratorCommands` back in `MenuCommandList` with the new "j" key**, then check the iPad keyboard issue again — §5.3.
- **Use `bundle: .module` in `ExternalPlayerWindow`** — `Modules/RolePlayGameKit/View/ExternalPlayerWindow.swift:25` — §4.2.
- **Call `Task.checkCancellation()` after the wait in `requireReadyDatabase()`** — `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:124-126` — §3.4.
- **Remove the `DatabaseReadiness.wait()` from the Pause, Resume and Next Track intents** — `Modules/AudioRPG/Intent/AudioPlaybackIntents.swift:63,84,113` — §5.22.
- **In `DiceExpression`, replace `w`→`d` before `d%`** — `Modules/DiceRPG/Model/DiceExpression.swift:72-80` — §5.21.
- **Apply the `> 0` rule in `setManualValue` too** — `Modules/CoreRPG/Model/QuickDiceSlotsModel.swift:147-152` — §5.12.
- **Lower the map photo-replacement `.info` log to `.debug`** — `Modules/MapRPG/Model/MapModel+Geometry.swift:80` — §9.11.
- **Delete the dead `removeLinks(for:)` / `updateLinks(for:)` and the QuickLinkEditor leftovers** — §9.4, §9.5.
- **Remove the 25 stale string-catalog keys and the unused imports** — §9.6, §9.7.
- **Add the missing `default` to the switch in `TranscriptTokenCounting.swift:8`** — §4.4.

---

## 3. Concurrency

### 3.1 Every cold launch re-indexes every App Entity of all 12 modules on the main actor
- **Location:** `Modules/CoreRPG/ItemList/ItemDataModel.swift:105-108` (`setItem` → `markIndexDirty`); `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:144-158` (launch reconciliation calls `setModel(with:)` for every item, then `AppIntentContentInvalidator.invalidate()`); `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:317-341`; `Sources/MasterRPG/MasterRPGSpotlightIndexer.swift:48-66`.
- **What:** `setItem` now marks every item dirty. At launch, `knownIds` is empty, so every item goes through `setModel` → `setItem`. One second later `reindexIntentEntities` builds a full entity for every item and indexes all of them. A full entity includes the 2,000-character excerpt, the folder subtitle and, for characters, `LinkController.calculate` per entry. The doc comment says "A run without changes does nothing. The first run per module covers every item". The first run is meant to be once per install (the `AppEntityIndexPruned` flag). In practice it happens on every launch.
- **Why:** This is a full Spotlight write plus main-actor CPU work about one second after launch, when the user starts working. Large libraries (rule compendiums, imported campaigns) feel it most. It is the churn that AppIntents §7.1 was meant to remove.
- **Action:** Don't mark ids dirty while a module does its initial load. Mark them only in the replace, merge, delete and insert paths, which already call `markIndexDirty`. Let the pruning pass that is gated by the flag handle the one-time full index. Consider yielding between batches in the per-module loop.
- **Severity:** Medium

### 3.2 PDF export and intent file reads run synchronously on the main actor
- **Location:** `Modules/CoreRPG/Intent/EntitySummaryExport.swift:43-79` (`@MainActor static func pdf`, called from the entities' `FileRepresentation`, e.g. `Modules/AdventureRPG/Intent/AdventureEntity.swift:96-98`, 6 call sites); `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:157-164` (`intentFileData` reads `IntentFile.data`), called from the `@MainActor` Create intents (e.g. `Modules/PhotoRPG/Intent/PhotoManagementIntents.swift:46`).
- **What:** `renderPdf` lays out up to 50,000 characters with CoreText across many pages and writes the file, all on the main actor. `IntentFile.data` loads the whole file synchronously, which can be a large audio, PDF or USDZ file passed from Shortcuts.
- **Why:** CLAUDE.md asks for CPU and I/O work to be `@concurrent` or to go through `runOffCallerExecutor`. Sharing a long rule as PDF, or creating a Space or Audio item from a big file, blocks the UI while the app is in the foreground.
- **Action:** Read the text on the main actor, then render and write through `runOffCallerExecutor`. Read the file bytes off the main actor, or pass the `fileURL` through to the store step.
- **Severity:** Medium

### 3.3 `AppIntentContentInvalidator.invalidate()` cancels a reindex that is already running, although its doc says it never does
- **Location:** `Modules/CoreRPG/App/AppIntentContentInvalidator.swift:16-29`
- **What:** `debounceTask?.cancel()` also cancels a task that has finished its one-second sleep and is now inside `await reindex()`. The `isReindexing`/`reindexAgain` loop then keeps running in a cancelled task.
- **Why:** If CoreSpotlight's async calls honor cancellation, each pass during a burst of saves fails and re-marks its ids (`IntentEntityHelpers.swift:350,364`). Nothing is lost, but work repeats and the index lags. The comment promises behavior the code does not have.
- **Action:** Keep the debounce sleep in its own task, separate from the running reindex, and cancel only the sleep.
- **Severity:** Low

### 3.4 A write intent cancelled during the cold-launch wait still writes
- **Location:** `Modules/CoreRPG/App/DatabaseReadiness.swift:69-83`; `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:124-126`
- **What:** On cancellation, `wait()` resumes and returns `canSave`. `requireReadyDatabase()` throws only when `canSave` is false.
- **Why:** If the user dismisses Siri while it waits, the Create, Update or Delete still runs once the store is ready.
- **Action:** Check for cancellation in `requireReadyDatabase()` after the wait.
- **Severity:** Low

### 3.5 Starting a game as master awaits the Siri donation before the game controllers exist
- **Location:** `Modules/GameRPG/Root/GameRoot.swift:375-380`
- **What:** `await adventureRoot.donateStartGame(of:)` sits between `startGame` and the creation of `PlayerController` and `gameConfig.state = .started`.
- **Why:** The system donation call delays the game start. It also opens a suspension point in which other main-actor code sees `gameConfig.master` set but no controllers yet.
- **Action:** Donate fire-and-forget at the end, as `donateRoll` and `donatePlay` already do.
- **Severity:** Low

---

## 4. API modernity

### 4.1 Already-localized values wrapped in a plain `IntentDialog` literal
- **Location:** `Modules/AdventureRPG/Intent/DeleteAdventureIntent.swift:39`; the same `.result(dialog: "\(message)")` in the Delete intents of Character `:232`, Dice `:220`, Generator `:222`, Map `:225`, Pdf `:236`, Photo `:234`, Rule `:218`, Space `:238`, Table `:223` and Weather `:223` (`*ManagementIntents.swift`); `Modules/TableRPG/Intent/RollTableIntent.swift:47`; `Modules/GeneratorRPG/Intent/RunGeneratorIntent.swift:47,65`.
- **What:** Each dialog becomes an app-bundle resource with the key `%@`. It works today only because that lookup misses.
- **Why:** This bypasses the `.localized(…, bundle: .module)` rule that AppIntents3 §5.1 marks as fixed "at every dialog". It breaks if a `%@` key ever appears in the app catalog.
- **Action:** Build these dialogs from a `LocalizedStringResource` with `bundle: .module`, or add an explicit verbatim helper.
- **Severity:** Low

### 4.2 `ExternalPlayerWindow` moved into a module but still uses `bundle: .main`
- **Location:** `Modules/RolePlayGameKit/View/ExternalPlayerWindow.swift:25`
- **What:** `Text("Game is not running", bundle: .main)`. The key exists in both the app catalog and the RolePlayGameKit catalog, and the module copy is unused.
- **Why:** This breaks the module-bundle rule, and the two copies can drift apart.
- **Action:** Use `bundle: .module` and drop the key from the app catalog.
- **Severity:** Low

### 4.3 App Shortcuts NLU build warnings for the parameterized adventure phrases
- **Location:** `Sources/MasterRPG/MasterRPGShortcuts.swift:37-55` (Open and Start phrases with `\(\.$target)`); build output `warning: unresolved variable(s) found: AdventureEntity # nlu.shortcuts.intents.{1,2}.corpuses.training.{0,1,2}.utterances.{1,2}` (12 lines).
- **What:** These warnings are new in this range. They point at exactly the two parameterized phrases of Open Adventure and Start Adventure Game, in all three languages. The parameter values come from `suggestedEntities()` at runtime, refreshed by `updateAppShortcutParameters()` (`MasterRPGSpotlightIndexer.swift:53`).
- **Why:** The warnings are probably expected for entity parameters, whose values are not known at build time. This is unverified: if they mean the phrases were not trained, "Open Moonlit Keep in MasterRPG" would fall back to the unparameterized phrase.
- **Action:** Test both phrases by voice on a device with existing adventures, and test whether Shortcuts lists the parameterized variants. If they work, record the warning as expected so it is not mistaken for a regression later.
- **Severity:** Low

### 4.4 Non-exhaustive `switch` in `TranscriptTokenCounting`
- **Location:** `Modules/GeneratorRPG/BasicAI/Engine/TranscriptTokenCounting.swift:8`
- **What:** This is the only Swift compiler warning ("switch must be exhaustive"). The file was edited in this range when the compiler switches were removed (`99b9de2f4`).
- **Why:** In a future Swift mode this warning can become an error, and it hides any new transcript entry kinds.
- **Action:** Handle the remaining cases explicitly, or add an `@unknown default` that counts them conservatively.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Quick Link turns entry titles into links, so on Apply those entries are re-created and lose their data
- **Location:** `Modules/CoreRPG/Links/QuickLinkScanner.swift:38-63` (scans the whole text); `Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:172-181` (`applyQuickLink`), `:219-224` (Apply → `merge`); `Modules/CoreRPG/Text/EntryTextParser.swift:32-33` (the first line of a block is the entry name, kept verbatim); `Modules/CoreRPG/ItemList/EntryDataEditable.swift:244` (`available.firstIndex(where: { $0.name == entry.name })`); `Modules/MapRPG/Controller/EditController.swift:115-116` (`MapEntryModel(id: UUID(), …, coordinates: [])`), `:436-457`. The test `Tests/CoreRPGTests/QuickLinkScannerTests.swift:42-47` relies on names being linked.
- **What:** Quick Link also replaces matches in the title lines. A room "Goblin Den" becomes `[Goblin](RPG://…) Den`. On Apply, entries are matched to the existing ones by exact name, so the renamed entry matches nothing. It is created new through `create(name:content:)`, and the old entry is removed. The affected-links alert appears only when something links to the old entry.
- **Why:** This is data loss. Map "Cave" has rooms "Goblin Den" and "Wolf Pit", and Table "Monsters" has "Goblin" and "Wolf". After Quick Link → Monsters → Apply, both rooms come back without a polygon and their fog state is gone. Character entries lose value type, dice and HP formula the same way. The editor shows a link as plain text, so the user cannot see that a title changed. Undo covers only the editor session.
- **Action:** Scan only entry content and skip title lines. Alternatively, match names through `withoutLink()` so that an entry keeps its identity when only link markup was added. Leave the table being edited out of the picker.
- **Severity:** High

### 5.2 During a running game, Create, Update and Delete intents write only to game memory but report success
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:229-234` (`if itemDataModel.isGameMode == true && forceSave == false { replaceInGameMemory(…); return }`); `Modules/AdventureRPG/Root/AdventureRootModel.swift:340-342` (game start sets `isGameMode` on every module); Create intents at `CreateAdventureIntent.swift:42`, `AudioManagementIntents.swift:52`, `CharacterManagementIntents.swift:50`, `DiceManagementIntents.swift:52`, `GeneratorManagementIntents.swift:49`, `MapManagementIntents.swift:48`, `PdfManagementIntents.swift:52`, `PhotoManagementIntents.swift:52`, `RuleManagementIntents.swift:48`, `SpaceManagementIntents.swift:53`, `TableManagementIntents.swift:49`, `WeatherManagementIntents.swift:47`; `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:214-253` (`updateIntentItem` saves with `forceSave: false`); `:296-306` → `EditControllable.swift:730-739` (`markForDeletion` saves without `forceSave`).
- **What:** The intents call `replace(model:isInsert: true)` and `reset(…, forceSave: false)`. In game mode that path only writes `gameItemData`. The new item is not added to `items` and not written to Core Data. The intent then indexes it and answers "Created" or "Updated". The app's own insert paths use `forceSave: true` (`EditControllable.swift:714`, `persistFromGame`).
- **Why:** For example, the game master says "Create a character named Goblin King" during a session. Siri answers "Created", but the character is not in the list, does not sync, and disappears when the game stops. Spotlight keeps a dangling entity. Renames, tag changes and trashing by intent during a game are also dropped at game end. The Create line predates 3.0.1, but the new Update intents and `ReturnsValue` entities depend on it.
- **Action:** Make the intents persist to the library (`forceSave: true`, as duplicate and import do) and also update a loaded game copy. If edits during a session are meant to stay session-only, refuse with a dialog instead of reporting success.
- **Severity:** High

### 5.3 The Generator module lost all its menu commands; `GeneratorCommands` is now dead code
- **Location:** `Sources/MasterRPG/Menu/MenuCommandList.swift:37-43` (line removed in `5979e8b0d`); `Modules/GeneratorRPG/Menu/GeneratorCommands.swift:20` (key changed "-" → "j"; no remaining caller).
- **What:** The "keyboard issue on iPad" commit changed the shortcut key and also removed the only instantiation. `MenuCommandList` is compiled into the iOS, macOS and visionOS targets.
- **Why:** On Mac and on iPad with a keyboard, Generator no longer has New Item, New Folder, Edit, Duplicate, Export, Delete, Navigate or the link-window command, which every other module gets from `ModuleCommands`. The "j" change has no effect.
- **Action:** Restore the `GeneratorCommands` line with the "j" key and retest the iPad keyboard issue. If removing it was intended, delete the file.
- **Severity:** Medium

### 5.4 Delete intents trash a folder but not its children
- **Location:** `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:296-306`; compare `Modules/CoreRPG/Controllable/EditControllable.swift:517` (`collectionItemsForRemoval`, used by `ListRootView.swift:212` and `ListRootContextMenu.swift:263`).
- **What:** `trashIntentItems` calls `markForDeletion` on each id. The UI first expands folders recursively.
- **Why:** After "Delete folder X", the children stay live with a trashed parent. Lists and folder trees disagree with what the UI's delete would produce, and purging the trash later orphans the children.
- **Action:** Expand ids with `collectionItemsForRemoval` before trashing, and remove the children from the index too.
- **Severity:** Medium

### 5.5 Write intents report success when the save failed
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:83-96` (`save()` records the error in `lastPersistenceError` and `PersistenceIssueCenter`); `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:250-253`; every Create, Add, Append, Update and Delete `perform()`.
- **What:** No intent reads the persistence error after `save()`.
- **Why:** This is the same silent success that the `DatabaseNotReadyError` fix (AppIntents §5.1) removed, now on the save path. With a full disk, a broken migration or a bad CloudKit state, Siri confirms a write that is not on disk.
- **Action:** Add a throwing save variant for intents, or check `lastPersistenceError`, in the shared helpers (`updateIntentItem`, `trashIntentItems`, plus a shared create/append tail). Throw a localized error from there.
- **Severity:** Medium

### 5.6 Spotlight results for trashed items still open the item
- **Location:** `Modules/CoreRPG/Persistence/SpotlightActivityRoute.swift:54-64`; `Modules/CharacterRPG/Model/DataModel+Extensions.swift:27-43` (same `attributeSet()` pattern in all 12 `DataModel+Extensions.swift`).
- **What:** The Core Data `attributeSet()` ignores `displayState`, so trashed items stay in the Core Data index (this predates 3.0.1). New in this range: the AppIntents2 §4.1 fix routes such a tap through `existingObject(with:)` without a trash check, and `relate(to:itemId:)` links the trashed text to an entity id that the queries hide.
- **Why:** Trashed content can still be searched, opened and used as Siri context. `IntentDonations.forget` cleans only the App Entity index.
- **Action:** Return no attribute set for trashed items, or at least drop `totalHidden` objects and their entry parents in `SpotlightActivityRoute`.
- **Severity:** Medium

### 5.7 Join Game by Siri fails unless the player-setup view has appeared in this run
- **Location:** `Modules/GameRPG/Intent/GameIntents.swift:147-157` (`validateLink(itemId: root.gameModel.selectedCharacter ?? UUID())`); `Modules/GameRPG/SetupViews/SelectedPlayerView.swift:11-12,67-68` (the only place that copies `@AppStorage(lastPlayerUUID)` into `selectedCharacter`); `Modules/GameRPG/Root/GameRoot.swift:310`. Related: `Modules/CharacterRPG/Intent/ChangeCharacterValueIntent.swift:151-158` (`CharacterValueNameOptions.results()` reads without `DatabaseReadiness.wait()`).
- **What:** The saved character is loaded into the model only by a view's `.task`. The intent also does not wait for the database.
- **Why:** On a cold launch, or in any session where that view has not appeared, Siri answers "Choose your character on the game screen first." even though a character was chosen and saved. Shortcuts can show an empty Value list on a cold launch.
- **Action:** Seed `selectedCharacter` from `UserDefaults` in `GameRoot` at launch, and wait for the database in both places.
- **Severity:** Medium

### 5.8 Replacing a map photo during a game moves rooms and pins on the master only
- **Location:** `Modules/MapRPG/Controller/EditController.swift:184-189` (`apply(_:adaptContent:)` → `save(updated:message:)`); `Modules/MapRPG/Model/MapModel+Geometry.swift:63-95`; compare `Modules/MapRPG/Map/MapEditorSession+Content.swift:188-198` (`broadcastMapEdit`).
- **What:** In game mode the save goes to game memory, and nothing calls `broadcastMapEdit`. Before this change, `add(photoId:)` already skipped the broadcast. The new path also rescales geometry.
- **Why:** If the game master picks "Adapt to New Size" during a game, polygons, pins, walls and fog tiles change scale on the master but not on players until "Refresh Shared Map". CLAUDE.md requires every game-master map edit to be broadcast. *Unverified at runtime.*
- **Action:** When a game is running, send the replacement through the map's broadcast path. If the item editor is meant to be exempt, document that.
- **Severity:** Medium

### 5.9 Quick Link has no minimum name length, forces the table's casing, and has no undo of its own
- **Location:** `Modules/CoreRPG/Links/QuickLinkScanner.swift:23-36` (candidates), `:42-50` (case-insensitive match); `Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:179-180`.
- **What:** Single-letter or very common entry names ("A", "I", "Orc") are linked everywhere they appear in prose. The link name always uses the table's spelling ("wolf" becomes "[Wolf](…)"). `reset(text:)` replaces the editor text in one step that cannot be undone.
- **Why:** One tap can add hundreds of unwanted links. The only way back is to cancel the whole quick-editor session.
- **Action:** Skip names below a minimum length. Keep the matched text's casing as the link label. Make the step undoable, or confirm it with the match count before applying.
- **Severity:** Medium

### 5.10 "Adapt to New Size" scales x and y independently
- **Location:** `Modules/MapRPG/Model/MapModel+Geometry.swift:120-125`
- **What:** Points are scaled by width and height ratios separately. Hex-grid entries get the same transform, and pin and border sizes are not scaled.
- **Why:** If the new photo has a different aspect ratio, rooms are skewed and hex cells stop being regular. The dialog does not warn about this.
- **Action:** When the aspect ratio changes, offer uniform scaling with an offset, or say so in the dialog. Rebuild hex grids instead of transforming their points.
- **Severity:** Low

### 5.11 Dismissing the "Adapt Rooms and Pins?" dialog without Cancel leaves the picker on the rejected photo
- **Location:** `Modules/MapRPG/View/DetailSelectionEditorView.swift:46-49` (setter only clears `photoReplacement`); `Modules/MapRPG/Controller/EditController.swift:192-195` (`cancel` resets the selection).
- **What:** A dismissal by tapping outside the iPad popover or pressing Esc does not reset `selectionPhoto`.
- **Why:** The picker shows the new photo while the map keeps the old one. Picking that same photo again changes no `itemId`, so nothing happens. *Unverified* whether outside-dismissal runs the cancel action.
- **Action:** Reset the selection in the binding's dismiss path too (make `cancel` idempotent and call it there).
- **Severity:** Low

### 5.12 Quick Dice: a manual value of 0 is saved, and rejected values give no feedback
- **Location:** `Modules/CoreRPG/Model/QuickDiceSlotsModel.swift:147-152` vs `:164-168`; `Modules/DiceRPG/Game/Editor/DiceQuickEditor.swift:52-60`.
- **What:** The editor sends `Int(value) ?? 0`. `setOverride` rejects values ≤ 0, but `setManualValue` persists them, and `validateForValue` then ignores them.
- **Why:** A base-dice slot stores a meaningless value, and in both slot types the popover closes with no visible change.
- **Action:** Use the same `> 0` rule in `setManualValue`, and disable Apply in the editor while the value is invalid.
- **Severity:** Low

### 5.13 A Quick Dice override can return while the overlay is hidden
- **Location:** `Modules/GameRPG/GameViews/QuickDice/QuickDiceSlotView.swift:130-132`; `Modules/CoreRPG/Model/QuickDiceSlotsModel.swift:172-189`.
- **What:** Only the overlay's slot view calls `linkedValueChanged`. The sheet row reads `effectiveValue` but never drops an override.
- **Why:** With the overlay hidden, a linked value that changes A→B→A brings the stale override back, which the model comment says should not happen.
- **Action:** Invalidate overrides inside the model (for example when `effectiveValue` sees a different linked value), not from a view.
- **Severity:** Low

### 5.14 visionOS reserves space at the bottom of the window for an overlay that lives in the ornament
- **Location:** `Modules/GameRPG/GameViews/QuickDice/QuickDiceOverlay.swift:35-39`; `Modules/GameRPG/GameViews/GameScreenOrnaments.swift:40-43`; `Modules/GameRPG/GameViews/OnlyPlayerGameView.swift:24`.
- **What:** The ornament-hosted overlay still reports its height, and the window pads by `quickDiceBottomReservation`.
- **Why:** The character panel ends early and leaves an empty band. *Unverified visually.*
- **Action:** Skip the height report or the reservation when the overlay is in an ornament.
- **Severity:** Low

### 5.15 The scanner relaunch guard only knows about `SpaceViewer`'s `RealityView`
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:550-552`; `Modules/SpaceRPG/View/InlineImporterView.swift:180-186`; `Modules/GameRPG/Table3D/GameTableView+PlatformFlat.swift` (iOS `RealityView`).
- **What:** `liveViewerWasShown` is set only in `SpaceViewer.loadEntity`, but the documented cause is that any `RealityView` existed earlier in the process.
- **Why:** After a game with the iOS 3D table, the scanner skips the relaunch alert and can hang on "Move iPhone to start". *Unverified at runtime.*
- **Action:** Set the flag from every iOS `RealityView`, for example with a shared modifier.
- **Severity:** Low

### 5.16 Layout restore re-navigates on every size-class change, including on macOS and visionOS
- **Location:** `Modules/RolePlayGameKit/View/TabRootView.swift:17-26`; `Modules/RolePlayGameKit/Model/AppModel.swift:675-694`.
- **What:** `rememberRouteForLayoutChange` runs on any `appSizeModel.mode` change. On Mac and visionOS the layout does not actually swap, but the remembered route is performed again 200 ms later.
- **Why:** Resizing a Mac window across the threshold can pop a pushed detail. The old `resetNavigation` did the same, so this is not a regression, but the new code keeps the behavior.
- **Action:** Remember and restore only when the old and new modes produce different layouts.
- **Severity:** Low

### 5.17 `ChangeCharacterValueIntent` can trap on extreme input
- **Location:** `Modules/CharacterRPG/Intent/ChangeCharacterValueIntent.swift:111-116`
- **What:** `Int(wanted.rounded())` traps when `amount` is near `Int.max`, or when a decimal value parses as `inf`.
- **Why:** Another shortcut passing a bad value crashes the app. A spoken request cannot trigger this.
- **Action:** Clamp the result, or use `Int(exactly:)` with a finite check and re-prompt.
- **Severity:** Low

### 5.18 Disambiguation by label picks the first match when labels repeat
- **Location:** `Modules/CharacterRPG/Intent/ChangeCharacterValueIntent.swift:97-104`; `Modules/GameRPG/Intent/GameIntents.swift:176-181`.
- **What:** Both use `labels.firstIndex(of: chosen) ?? 0`.
- **Why:** With two "HP" entries, or two game-master devices that have the same name, the second one can never be chosen, and the wrong one is changed or joined.
- **Action:** Make the labels unique (group path, index or device id), or disambiguate over values instead of strings.
- **Severity:** Low

### 5.19 Battle intents give misleading answers
- **Location:** `Modules/GameRPG/Intent/GameIntents.swift:31-34, 54-56, 82-84`
- **What:** A `false` from `nextAttacker()`, which also happens when nobody can act, is reported as "Only the game master can do that." `EndBattleIntent` asks for confirmation before it checks whether this device is the master.
- **Why:** The answer is wrong, but no data is affected.
- **Action:** Check `isMaster` first, then answer separately when nobody can take a turn.
- **Severity:** Low

### 5.20 Pause Audio reports success when nothing is playing
- **Location:** `Modules/AudioRPG/Intent/AudioPlaybackIntents.swift:62-66`
- **What:** "Paused the audio." is returned unconditionally, while Resume and Next Track check the player state.
- **Why:** Siri reports an action that did nothing.
- **Action:** Answer "Nothing is playing" when nothing is playing.
- **Severity:** Low

### 5.21 `DiceExpression` misses "W%" and spoken number words
- **Location:** `Modules/DiceRPG/Model/DiceExpression.swift:72-80`
- **What:** `d%` is normalized before `w`→`d`, so the German "W%" is rejected. Number words ("two d six") are rejected too. The bounds hold: at most 100 dice, d2–d1000, saturating arithmetic.
- **Why:** Some valid requests get a re-prompt.
- **Action:** Swap the order of the two replacements. Consider mapping small en/de number words to digits.
- **Severity:** Low

### 5.22 Playback-only audio intents wait for the database
- **Location:** `Modules/AudioRPG/Intent/AudioPlaybackIntents.swift:63,84,113`
- **What:** Pause, Resume and Next call `DatabaseReadiness.wait()` but use only `audioController`.
- **Why:** On a cold launch, for example while an iCloud alert is pending, Pause can take up to the 20 s timeout to answer.
- **Action:** Remove the wait from these three intents.
- **Severity:** Low

---

## 6. Security

### 6.1 Generator content is placed in the model's instructions, not in the prompt
- **Location:** `Modules/GeneratorRPG/Intent/RunGeneratorIntent.swift:95-103, 128`
- **What:** The generator's description and entries, which can come from imported or shared campaigns, are appended to the `instructions:` of the `LanguageModelSession`, although the comment says they "stay guidance, not instructions to obey".
- **Why:** Text inside a shared generator can override the fixed rules. The impact is limited to the text that is generated and spoken.
- **Action:** Keep the instructions fixed, and pass the generator text in the prompt, clearly delimited.
- **Severity:** Low

Checked with no finding: the Spotlight route accepts only `x-coredata` URIs of the app's own coordinator; `authenticationPolicy` is set on all 12 Update intents, all 12 Delete intents and Stop Game; `DiceExpression` input is bounded. The privacy side of trashed content is covered in §5.6.

---

## 7. Performance

### 7.1 The "O(limit)" excerpt still scans each whole entry
- **Location:** `Modules/CoreRPG/Controllable/IntentEntityText.swift:26-38, 78-87, 103-108`
- **What:** `readable(part)` runs a regex and two `replacing` passes over the full entry before `BoundedText` cuts it to the remaining space. AppIntents3 §4.3 added `readable`, which regressed the AppIntents2 §7.1 claim.
- **Why:** One long pasted chapter is scanned in full every time its entity is built. Combined with §3.1 that happens on every launch, and on every Find and `allEntities` call.
- **Action:** Cut a bounded prefix of the raw entry, with slack for link syntax, before calling `readable`. Fix the doc comment.
- **Severity:** Low

### 7.2 Find and full re-index build every entity before filtering
- **Location:** `Modules/CoreRPG/Controllable/ItemEntityQuery+Find.swift:24-36`; `Modules/CoreRPG/Controllable/ItemEntityQuery.swift:127-135`
- **What:** `findEntities` builds every entity, including the excerpt and subtitle, before it checks the predicates and the limit.
- **Why:** The Shortcuts Find action costs main-actor work proportional to the whole library and its text.
- **Action:** Apply the predicates to the model first, and build entities only for the matches, up to the limit.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 Fixed sizes and styling literals in new views
- **Location:** `Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:85` (`CGSize(width: 500, height: 700)`); `Modules/GameRPG/GameViews/QuickDice/QuickDiceSlotView.swift:36-37` (`cornerRadius: 12`, `opacity(0.4)`)
- **What:** Hard-coded frame and styling values in views that run on four platforms.
- **Why:** These values do not adapt to Dynamic Type or to window sizes, and they drift from the theme.
- **Action:** Use the theme's radius and highlight, and size the editor relative to its container (`containerRelativeFrame`) or with an ideal size.
- **Severity:** Low

### 8.2 Layout restore waits a fixed 200 ms instead of reacting to the settled layout
- **Location:** `Modules/RolePlayGameKit/View/TabRootView.swift:21-26`
- **What:** The delay before `restoreRouteAfterLayoutChange` is a fixed sleep. `NavigationTiming` exists for exactly this kind of delay.
- **Why:** On a slow device the new layout may not have settled within 200 ms, so the restore is lost. On a fast device the user sees a visible jump.
- **Action:** Trigger the restore from the new layout's `onAppear` or navigator registration. If a delay stays, name it in `NavigationTiming`.
- **Severity:** Low

No other SwiftUI issues were found in the changed views: no `onTapGesture`, no one-parameter `onChange`, no `AnyView`, and no `GeometryReader` were added. The icon-only buttons in the new Quick Dice and Quick Link views have accessibility labels.

---

## 9. Dead code / duplication / refactor

### 9.1 About 83% of the per-module intent code is copy-paste
- **Location:** `Modules/{Adventure,Audio,Character,Dice,Generator,Map,Pdf,Photo,Rule,Space,Table,Weather}RPG/Intent/` — `*ManagementIntents.swift`, `Open*Intent.swift`, `*IntentSupport.swift`, `*Entity.swift`. Reference copy: `Modules/MapRPG/Intent/MapManagementIntents.swift:1-233`.
- **What:** After normalizing the module names, 4,536 of 5,463 lines in the other 11 modules are identical to Map. New in this range:
  - (a) `Update<X>Intent` in 12 copies (`MapManagementIntents.swift:113-166`).
  - (b) The Add-intent tail, which calls `requiredIntentTarget` twice with the same prompt (`:95,105`).
  - (c) The target-prompt literal repeated up to 6 times per file.
  - (d) `registerDonations`/`reindexChanged` in 12 `*IntentSupport.swift`.
  - (e) The `IndexedEntityQuery` bodies (`MapEntity.swift:117-131`, ×12).
  - (f) `siriOpenIntent(for:)` and the identical `perform` of the legacy and schema Open intents.
- **Why:** Every behavior change needs 12 edits, and the copies have already drifted (Character's Add differs in comments and wording).
- **Action:** Keep in each module only what metadata extraction needs: the structs, static title, description and summary, `@Parameter`s, a `perform()` declared in the struct, and the module-bundle dialogs. Move the bodies into CoreRPG generics: an update/refresh helper for (a)+(b), a per-module `targetPrompt` for (c), and one registration helper for (d). Use an `@available(iOS 27…)` default extension on `ItemEntityQuery` for (e) and a shared route function for (f). Do not rely on a protocol-extension default `perform()`; whether the metadata processor resolves its result type is not verified.
- **Severity:** Medium

### 9.2 Two dice-notation parsers
- **Location:** `Modules/DiceRPG/Model/DiceExpression.swift:24-80` (new) vs `Modules/DiceRPG/Model/RawDice.swift:30-34,107-127` and `RawDieCounter.swift:15-29`.
- **What:** The two parsers have different grammars, limits and canonical text. `RawDice(text:)` has no app callers, only `Tests/DiceRPGTests/RawDiceLimitsTests.swift:59`.
- **Why:** The rules for the same notation will drift (`d%`, negative dice, limits).
- **Action:** Make `DiceExpression` the single parser, have it build `RawDice`, and share the limits.
- **Severity:** Low

### 9.3 Four markdown-link patterns and two splice loops
- **Location:** `Modules/CoreRPG/Controllable/IntentEntityText.swift:78-87`; `Modules/CoreRPG/Links/QuickLinkScanner.swift:39`; `Modules/CoreRPG/Extensions/String+MarkDown.swift:28ff` (`withoutLink()`); `Modules/CoreRPG/Links/LinkReplaceController.swift:110-117`. Splice loops: `QuickLinkScanner.swift:54-62` and `LinkReplaceController.swift:81-96`.
- **What:** The link patterns differ slightly; one allows whitespace in the target and another does not. The range-splice loop exists twice.
- **Why:** A change to the link grammar has to be found in four places. `LinkBuilder` was introduced to prevent exactly this.
- **Action:** Put one link matcher next to `LinkBuilder`/`ReferenceScanner`, and extract one `replacing(ranges:)` helper.
- **Severity:** Low

### 9.4 Dead link helpers
- **Location:** `Modules/CoreRPG/Links/LinkReplaceController.swift:110-132` (`removeLinks(for:)`, `updateLinks(for:)`)
- **What:** Neither function has a caller in Modules, Sources or Tests. `updateLinks` also builds a link string by hand, without `LinkBuilder`.
- **Action:** Delete both.
- **Severity:** Low

### 9.5 Leftovers of the removed QuickLinkEditor
- **Location:** `Modules/CharacterRPG/Model/ValueEntryModel.swift:227-232` (`entryText(otherValue:)`, 0 references); `Modules/TableRPG/Model/TableEntryModel.swift:104-110` (`entryLinkText`, referenced only by `Tests/TableRPGTests/TableEntryModelTests.swift:67-73`); `Modules/AdventureRPG/Model/AdventureEntryModel.swift:87-92` (`entryLinkText()`, 0 references).
- **What:** These are near-identical "**name**: content" formatters whose callers were deleted in `dea30b30f`.
- **Action:** Delete the three methods and the test.
- **Severity:** Low

### 9.6 25 newly stale localization keys
- **Location:** for example `Modules/CoreRPG/Resources/Localizable.xcstrings:3547,4680`; `Modules/AdventureRPG/Resources/Localizable.xcstrings:110,1473`; `Modules/DiceRPG/Resources/Localizable.xcstrings` (12 keys, e.g. `:1520`); `Modules/SpaceRPG/Resources/Localizable.xcstrings:198,1896`; `Modules/AudioRPG/…:1026,1139`; `Modules/RuleRPG/…:1351`; `Resources/Localizable.xcstrings` (4 keys).
- **What:** These keys are marked `stale` after the ShortcutCatalogs, the QuickLinkEditor and old intent titles were removed. `grep` finds no Swift literal for any of them.
- **Why:** Translators keep maintaining de and th strings that nobody sees.
- **Action:** Remove the stale strings, after checking that no App Intents title still uses one of them as a key.
- **Severity:** Low

### 9.7 Unused imports after code moved to CoreRPG
- **Location:** `import os.log` in all 12 `Open*Intent.swift` (e.g. `OpenMapIntent.swift:9`); `import CoreSpotlight` in 11 `*IntentSupport.swift` and 11 `*ManagementIntents.swift` (e.g. `MapManagementIntents.swift:6`); `import PDFKit` in 9 `*Entity.swift` (e.g. `MapEntity.swift:10`).
- **Action:** Remove them.
- **Severity:** Low

### 9.8 Three copies of the "donate a throttled UI action" wrapper
- **Location:** `Modules/DiceRPG/Intent/RollSpecificDiceIntent.swift:191-204`; `Modules/TableRPG/Intent/RollTableIntent.swift:88-100`; `Modules/AudioRPG/Intent/AudioPlaybackIntents.swift:126-138`.
- **Action:** Add one fire-and-forget overload to `IntentDonations`.
- **Severity:** Low

### 9.9 Quick Dice value bound defined twice
- **Location:** `Modules/CoreRPG/Model/QuickDiceSlotsModel.swift:26-27` vs `Modules/DiceRPG/Model/DiceModel.swift:347`
- **What:** The comment says "the same bound a dice model accepts", but the value is written as a second literal.
- **Action:** Define it once in CoreRPG.
- **Severity:** Low

### 9.10 Magic delays and limits
- **Location:** `Modules/RolePlayGameKit/View/TabRootView.swift:23` (200 ms, see §8.2); `Modules/GameRPG/Intent/GameIntents.swift:210` (250 ms poll); `Modules/GeneratorRPG/Intent/RunGeneratorIntent.swift:108` (`prefix(1_000)`).
- **Action:** Name each value next to its existing siblings (`NavigationTiming`, `searchTimeout`, `guidanceLimit`).
- **Severity:** Low

### 9.11 Diagnostic `.info` log on every map photo replacement
- **Location:** `Modules/MapRPG/Model/MapModel+Geometry.swift:80`
- **What:** The log was left from the resize work and is not behind a DEBUG gate. The `.warning` on `:78` is worth keeping.
- **Action:** Lower it to `.debug` or remove it.
- **Severity:** Low

### 9.12 Changed files that grew past 500 lines
- **`Modules/RolePlayGameKit/Model/AppModel.swift` (763 lines, was 693)** — move the Routing extension (`:491-731`, including `LayoutRestoreTarget`) to `AppModel+Routing.swift` and the intent wiring to `AppModel+Intents.swift`. Severity: Low.
- **`Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift` (502 lines, was 417)** — move the Quick Link state, action and views to `QuickEntryEditorView+QuickLink.swift`. Severity: Low.

### 9.13 Intent types outside the file pattern
- **Location:** `UpdateAdventureIntent` is in `Modules/AdventureRPG/Intent/AppendAdventureSectionIntent.swift:56-108`; `CoreFrameworkPackage` is in `Modules/CoreRPG/Controllable/NextTurnControlIntent.swift:31-39`; `registerDonations` (all `*IntentSupport.swift`, `MasterRPGSpotlightIndexer.swift:25`) now registers more than donations.
- **Action:** Move each type into its own file, and rename the function to `registerIntentSupport`.
- **Severity:** Low

### 9.14 Small duplicates, including two Quick Dice rules
- **Location:** `Modules/CharacterRPG/Intent/ChangeCharacterValueIntent.swift:108-110` and `:117-119`; `Modules/GameRPG/Intent/GameIntents.swift:58` and `:237`; `Modules/CharacterRPG/View/QuickDiceFavoriteMenu.swift:19-20` vs `Modules/GameRPG/GameViews/QuickDice/GameRoot+QuickDice.swift:10-12`.
- **What:** The favorite menu checks `isGameRunning && gameModus == .player`. `offersQuickDice` checks `!isMaster && gameType != .observer`. QuickDice §9.2 calls `offersQuickDice` "the one rule", but CharacterRPG cannot see it.
- **Why:** The two rules can disagree, for example for an observer.
- **Action:** Express the rule once in CoreRPG. Add small helpers for the two other duplicates.
- **Severity:** Low

No TODO, FIXME, `print`, `#if false`, leftover `#if compiler`/`#if swift`, or `ID`/`URL` naming drift was found in the changed lines.

---

## 10. Cross-cutting recommendations

1. **Intents must use the same persistence path as the UI.** §5.2, §5.4 and §5.5 share one root cause: intents call low-level controller methods (`replace`, `reset`, `markForDeletion`, `save`) and skip what the UI action around them does (force-save during a game, folder expansion, error surfacing). Add one CoreRPG "intent write" layer that wraps these with the UI's semantics and throws on failure. The §9.1 refactor is the natural place for it.
2. **Don't derive "changed" from "loaded".** §3.1 and §7.1/§7.2 come from treating every model that passes through `setItem` as new work. Mark index dirtiness only on real mutations, and keep indexing work bounded per entity.
3. **Bulk text transforms need a preview or an undo.** §5.1 and §5.9 come from Quick Link rewriting text that the user cannot see as changed, inside an editor whose Apply re-matches entries by name. Any future bulk rewrite (Quick Link, link repair, numbering) should show a count or diff before applying, and should never touch entry titles.
4. **State a feature needs from a view belongs in the model.** §5.7 (selected character) and §5.13 (override invalidation) both depend on a view having appeared. Intents and hidden overlays run without that view.
5. **One grammar per notation.** §9.2 and §9.3: keep dice notation in `DiceExpression`, and links in `LinkBuilder` plus one matcher.

---

## 11. What was NOT audited

- Code outside the `3.0.1..HEAD` diff, except where a changed line depends on it (e.g. `ItemControllable.replace`, `EditControllable.markForDeletion`).
- Test code (59 changed test files): checked only for how tests pin behavior (§5.1, §9.5). Test coverage and quality were not assessed.
- Runtime behavior. Nothing was run in the simulator or on a device. Siri phrases (§4.3), Spotlight taps on iOS 26 and 27, Quick Dice in a real game, the map dialog's dismissal (§5.11), visionOS layout (§5.14) and the scanner guard (§5.15) are code-read only.
- The `swiftui-expert-skill` was not run as a separate pass. The SwiftUI review was done inside the feature-bug pass and by reading `QuickDiceSlotView`, `DetailSelectionEditorView`, `TabRootView` and `SearchItemListViewModifier` directly.
- Build settings, the scheme change (`MasterRPG.xcscheme`), `Resources/Info.plist` and `skills-lock.json`.
- The `.agents/skills/app-store-screenshots` TypeScript template changes.
- Localization wording. Only stale and misplaced keys were checked.
- The FoundationModels generator output quality, and on-device App Intents metadata beyond the build warnings.
- Builds for macOS, visionOS and tvOS. Only the iOS Simulator build was used for warnings.

---

## 12. Verification

- **§5.1** — Open `Modules/CoreRPG/Links/QuickLinkScanner.swift:38-50`: it scans the whole text with no title-line exclusion. `Modules/CoreRPG/Text/EntryTextParser.swift:32-33` keeps the first line verbatim as the name. `Modules/CoreRPG/ItemList/EntryDataEditable.swift:244` matches on `$0.name == entry.name`. `Modules/MapRPG/Controller/EditController.swift:116` creates a room with `coordinates: []`, and `:439` computes the removed ids from the unmatched ones.
- **§5.2** — Open `Modules/CoreRPG/Controllable/ItemControllable.swift:231-233` (game-mode early return into `replaceInGameMemory`), `Modules/AdventureRPG/Root/AdventureRootModel.swift:340-342` (sets `isGameMode` on every root), and `Modules/CharacterRPG/Intent/CharacterManagementIntents.swift:50` (no `forceSave`). `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:227` passes `forceSave: false`.
- **§5.3** — `grep -rn "GeneratorCommands(" Modules Sources` finds only the declaration. `Sources/MasterRPG/Menu/MenuCommandList.swift:37-43` lists the other 11 modules.
- **§5.4** — `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:302-304` loops `markForDeletion` only. `EditControllable.swift:730-739` does not expand folders.
- **§5.5** — `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:83-96` catches the error and stores it. No intent reads `lastPersistenceError`.
- **§5.6** — `Modules/CoreRPG/Persistence/SpotlightActivityRoute.swift:54-64` checks only `existingObject(with:)`.
- **§5.7** — `grep -rn "resetSelectedCharacter" Modules` finds only `SelectedPlayerView.swift:68` and the definition in `GameRoot.swift:310`.
- **§5.8** — `Modules/MapRPG/Controller/EditController.swift:184-189` saves without a broadcast. Compare `MapEditorSession+Content.swift:188`.
- **§5.9** — `QuickLinkScanner.swift:26-30` excludes only empty names, bracket names and roll ranges.
- **§3.1** — `Modules/CoreRPG/ItemList/ItemDataModel.swift:105-108` (`setItem` marks dirty); `ItemControllable+Sync.swift:146-158` (the launch path calls `setModel` for unknown ids, then `invalidate()`); `IntentEntityHelpers.swift:328-330` (any dirty id triggers the pass).
- **§3.2** — `Modules/CoreRPG/Intent/EntitySummaryExport.swift:43` is `@MainActor` and calls `renderPdf` synchronously.
- **§9.1** — Normalize `Map`→`X` and diff any `*ManagementIntents.swift` against `MapManagementIntents.swift`.

If a finding doesn't reproduce when you open the cited line, name the § number and I'll re-check it.
