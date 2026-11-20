# Code Audit — MasterRPG (2026-11-20)

Snapshot of `main` at `4a8b92666`. Read-only audit by folder: 12 scopes covering all of `Modules/` and `Sources/` (about 215k Swift lines excluding `Tests/`, `Snapshots/`, preview fixtures), at most 4 agents in parallel. Each scope was read by one agent against the same brief (concurrency, API modernity, bugs, security, performance, SwiftUI, dead code). All four High findings, the security Medium §6.1, the regression §5.5 and the Pdf/Space image Medium §5.9 were re-opened and confirmed by the lead (see §12). Everything else is the agents' finding, confidence stated per finding.

**Overall verdict:** no Critical issue. The code base has been audited about 26 times (`Docu/CODE_AUDIT_*.md`) and the earlier fixes mostly hold; the GM-only data defences (hidden rooms, pin visibility, external screen, player export audience) were re-traced in four scopes and are closed. The remaining risk is in less-travelled features (undo/redo, batch edit, table dice ranges, Foundry import, statistics), in fixes that landed on one sibling module but not its twins, and in two "fixed" items that do not work (§5.5, §5.2).

Previous `CODE_AUDIT.md` files are archived as `Docu/CODE_AUDIT_*.md`; this file replaces nothing that is not already there. Findings that earlier audits already list as open are marked "known open".

**Status 2026-11-20:** the four High findings §5.1–§5.4 are fixed, each with tests that fail on the old code (redo: `Tests/TableRPGTests/UndoRedoTests.swift`; group tags: `GroupEditorSaveTests`; table ranges: `TableGenerationControllerTests`; Adventure import: `Tests/RolePlayGameKitTests/FoundryVTTDomainMapperAdventureTests.swift`). All other findings are open. User decisions: ranges apply when a Dice is linked (§5.3); a group edit over items with different tags adds the tag to each and keeps their own (§5.2).

## 1. Executive summary

1. **[High] Redo re-applies the pre-edit state and discards the user's last edit** — §5.1 — `Modules/CoreRPG/App/UndoManaged.swift:8-57`, `Modules/CoreRPG/Controllable/EditControllable.swift:452`
2. **[High] Batch group edit with different tags replaces every item's tags with the single tag added** — §5.2 — `Modules/CoreRPG/LGViews/GroupEditorController.swift:91-119` (earlier "fix" only covered the shared-tags case)
3. **[High] Table range entries ("1-5", "6-10") only work when `tableType == .dice`, which no editor path sets** — §5.3 — `Modules/TableRPG/Controller/TableGenerationController.swift:253`
4. **[High] Foundry Adventure import links every hidden field-group value and rule duplicate, in per-process random order** — §5.4 — `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Documents.swift:489-515`
5. **[Medium] Asset requests and player "show" are not limited to items the GM has shown (only Map is)** — §6.1 — `Modules/GameRPG/Controller/MasterController+FileMessageSupport.swift:66-71, 94-110, 128-146`
6. **[Medium] Folder-cycle guard from an earlier audit never detects a cycle (canonical vs raw id)** — §5.5 — `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Indexes.swift:277-296`
7. **[Medium] Weather edited during a game never reaches players (version covers only the photo)** — §5.7 — `Modules/WeatherRPG/Controller/GameController.swift:88-125`
8. **[Medium] "Refresh Shared Map" in the editor bypasses the ordered content-send queue** — §5.6 — `Modules/MapRPG/Map/EditMapToolBarButtons.swift:264-268`
9. **[Medium] Statistics: player sessions record the wrong adventure/master; orphaned sessions are closed at the next game's start (inflated durations, irrevocable Game Center progress)** — §5.11, §5.12 — `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:89-108`
10. **[Medium] Pdf and Space "image" exports throw every time; Space viewer ignores iCloud download** — §5.9, §5.10

Counts: Critical 0 · High 4 · Medium 22 · Low ≈ 50 (grouped).

## 2. Quick wins (≤ 30 min each)

- §5.14 Use the packaged-path planner for UniversalVTT image conversion instead of building a path from the user's file name.
- §5.5 Key `visited`/`declarationsByID` lookups by the same id in `cycleSafeParentID` (add a two-folder-cycle test).
- §5.6 Route the editor's Refresh button through `enqueueMapContentSend` like the three other call sites.
- §5.12 Close a leftover session at its own `lastActivityAt`, not at the new game's start.
- §5.9 Serve the cached thumbnail for Pdf/Space `.image`, or drop that representation.
- §3.2 Replace the `isLoading` re-entrancy guard in `ThumbnailRowPhotoView` with the token pattern from `CachePhotoView`.
- §3.5 Cancel `SheetRootModel` pending tasks in `reset(itemId:)`.
- §7.5 Cap the undo stack (the library-scoped list is already capped at 64).
- §7.9 Make `TextIntEditor` save on editing end like `TextDoubleEditor`.
- §6.10 Remove the unused `fetch` background mode from `Resources/InfoTV.plist`.
- §9.3 Delete the listed dead Navigator/Sheet symbols; §9.4 wire or delete `playerMode`.
- §4.1 Replace the force-unwrapped constant UUID/URL literals; drop the unused `IOKit.ps` import.

## 3. Concurrency

**Compiler ground truth.** A clean `xcodebuild clean build` of scheme `MasterRPG` (iOS Simulator, Debug, `SWIFT_STRICT_CONCURRENCY=complete`) succeeded with **zero Swift warnings**; the only two warning lines are "Metadata extraction skipped, no AppIntents.framework dependency found". Therefore no finding below is a compiler-visible concurrency warning; they are logic/lifecycle issues found by reading. macOS, tvOS and visionOS schemes were not built in this audit (see §11).

### 3.1 `revealWeather` joins an in-flight reveal and drops a newer payload
- **Location:** `Modules/WeatherRPG/Controller/GameController.swift:137-176`
- **What:** A second call for the same item returns the in-flight task's value without comparing its own version/data; the in-flight entry is cleared by an unstructured Task in a `defer`, so a later call can also join an already finished task, and a completed task can stay registered until `reset()`.
- **Why:** Reveal A (old photo version) running, reveal B with the new package arrives: B returns A's result, the new package is never imported; players keep the old photo until rejoin.
- **Action:** Chain instead of join (run the second reveal after the first when versions differ, as `TableReceiveSerializer` does) and clear the entry inside the task's completion path guarded by a token.
- **Severity:** Medium (confidence: likely)

### 3.2 `ThumbnailRowPhotoView` can skip loading the new file when a load is in flight
- **Location:** `Modules/CoreRPG/LGViews/ThumbnailRowPhotoView.swift` (`.task(id: model.fileUrl)` + `loadImage()` guard on `isLoading`)
- **What:** `.task(id:)` cancels the old task and starts the new one immediately, but the old task still holds `isLoading == true`, so the new task returns at the guard; nothing loads the new file. `CachePhotoView` in the same folder already solved this with a per-load token.
- **Why:** A row whose `fileUrl` changes during a slow iCloud thumbnail load keeps the placeholder/old thumbnail until the row is recreated.
- **Action:** Drop the guard in favour of `.task(id:)` cancellation, or use the token pattern.
- **Severity:** Medium (likely)

### 3.3 Fog render and map change can interleave on the no-map branches
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+MapSync.swift:19-26, 48-75, 153-158, 200-218`
- **What:** The map-change and fog tasks each cancel only their own predecessor; the no-map branches of `performMapChange` clear the board without bumping `boardRenderGeneration`.
- **Why:** After "clear map" a still-decoding fog render for the old map can paint onto the emptied table until the next map change. Short window, not runtime-confirmed.
- **Action:** Bump the render generation (or cancel the fog task) in every board-clearing branch.
- **Severity:** Low (speculative)

### 3.4 SharePlay messenger loop awaits handling inline (head-of-line blocking)
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift` (receive loop calling `handleUpdate`), `RPGSharePlayController+ChunkedTransport.swift`
- **What:** One receive loop awaits the handling of each completed package before pulling the next message.
- **Why:** A slow import delays dice rolls and pin updates behind it (latency only; ordering is preserved).
- **Action:** Hand completed packages to the pipeline's ordered drain worker and return immediately.
- **Severity:** Low (likely)

### 3.5 Pending tasks not cancelled: `SheetRootModel.reset`, handshake/dial deadlines
- **Location:** `Modules/CoreRPG/Sheet/SheetRootModel.swift:208-230`; `Modules/GameRPG/Master/MasterNetworkController+Listener.swift:87-95`, `MasterNetworkController+Browser.swift:121-129`
- **What:** `reset(itemId:)` leaves `pendingParentReconcileTasks`/`pendingGroupMoveTask` running (a debounced task for the old item can write back to the previous item). Handshake/dial deadline tasks are never stored, so they cannot be cancelled on authenticate/remove (short-lived buildup under churn).
- **Action:** Cancel and clear in `reset`; keep deadline tasks keyed by connection id and cancel them.
- **Severity:** Low (likely)

### 3.6 Game Center reporting can run twice at once
- **Location:** `Modules/GameRPG/GameCenter/GameCenterController.swift:131-146`; callers `GameStatisticsModel.swift:77-80, 283-285`
- **What:** `reportAchievements` has no in-flight guard; overlapping calls report the same updates twice and the first `finishReporting` clears the progress flag early.
- **Action:** Serialize with a stored task or drop the call while one runs; make the flag a counter.
- **Severity:** Low (likely)

### 3.7 `nonisolated(unsafe)` left on Dice and Character entity query statics
- **Location:** `Modules/DiceRPG/Intent/DiceEntity.swift:164, 190`; `Modules/CharacterRPG/Intent/CharacterEntity.swift:128, 154`
- **What:** CODE_AUDIT_26 §3.11 fixed `AdventureEntity` and left these twins (immutable values, hygiene only).
- **Action:** Apply the `AdventureEntity` pattern.
- **Severity:** Low (verified)

### 3.8 Small lifecycle issues in Audio, Space and Generator
- **Location:** `Modules/AudioRPG/Controller/AudioPlayerSession.swift:258-263` (interruption resume calls `setActive` directly, bypassing the queued session-change task so it can reorder against a queued `deactivate`), `:210-222` (`audioSessionObservers` never cleared after a media-services reset); `Modules/AudioRPG/Audio/PlayerTime.swift:28` (`Int(ceil(time))` traps for a finite value ≥ 2^63, e.g. a corrupt duration header); `Modules/SpaceRPG/Space/SpaceViewer+Loading.swift:341-349` (close-button subscription closure keeps a copy of the view value until it fires); `Modules/GeneratorRPG/Controller/GeneratorController.swift:301-303` (`isExtracting` derived from `session.isResponding` on exit can stay true, so the controller is never evicted)
- **Action:** Route resume through `enqueueSessionChange`, clamp before `Int`, cancel/clear observers, use `[weak]`/relay pattern, set `isExtracting = false` for the owning generation.
- **Severity:** Low (likely/speculative)

## 4. API modernity

Pattern greps for the CLAUDE.md rules (`foregroundColor`, `cornerRadius()`, `tabItem`, 1-parameter `onChange`, `onTapGesture`, `DateFormatter`/`NumberFormatter`, `String(format:)`, `replacingOccurrences`, `DispatchQueue`, `Task.sleep(nanoseconds:)`, `GeometryReader`, `ScrollViewReader`, `UIScreen.main`, `NavigationView`, `try!`, `ObservableObject`) came back clean in all scopes except the items below. No deprecated-API-being-removed findings.

### 4.1 Force unwraps that cannot fail today
- **Location:** `Modules/GameRPG/GameViews/GameRootViewer.swift:259` (`UUID(uuidString:)!`), `Modules/CoreRPG/Controllable/ItemGameModel.swift:72-73`, `Modules/CoreRPG/Extensions/String+Highlight.swift:14`, `Modules/CoreRPG/Controllable/EditControllable+File.swift:264`, `Modules/CoreRPG/Files/CloudDocumentController.swift:88` (`URL(string: "/")!`), `Modules/GameRPG/GameViews/BatteryView.swift:11` (unused `IOKit.ps` import)
- **Action:** Use `[key, default: []]`, `if let`, `URL(filePath:)`; drop the import after a build check.
- **Severity:** Low

### 4.2 Hard-coded padding, spacing and fixed sizes (known open: CODE_AUDIT_20 §8.10)
- **Location:** about 28+ sites in `Modules/GameRPG/GameViews` and `Table3D` (e.g. `GameRootViewer.swift:222-223, 342`, `OverlayGameMenu.swift:445`, `PlayerSideMenu.swift:13, 33`), `Modules/DiceRPG/Game/Detail/DiceRoll.swift:17`, `DicePlayer.swift:13, 36`, `Sources/DiceRollerWidget/DiceRollerWidgetView.swift:35, 61, 103` (+≈6), `Modules/MapRPG/View/DisplayConfigEditor.swift:152, 163, 179`, `Modules/RolePlayGameKit/View/SplitVisionNavigation.swift:51, 55` (+4 files), `Modules/CoreRPG/Sheet/SheetView.swift:171-173`
- **Action:** Introduce shared spacing tokens (as `BattleRoundSpacing` does) and migrate when touching each file.
- **Severity:** Low

### 4.3 Image-only buttons and other small CLAUDE.md deviations
- **Location:** `Modules/CoreRPG/LGViewModifiers/ToolbarItemListViewModifier.swift:252-257`, `Modules/CoreRPG/ItemDetail/ItemDetailContentView.swift:104-114`, `Modules/CoreRPG/Views/HideKeyboardFocusView.swift:30-36`, `Modules/CoreRPG/Menu/MenuWindowButtonView.swift` (fixed 44 pt); `AnyView` in `Modules/CoreRPG/Route/InternalRoute.swift:42`, `Sheet/SheetEntryView.swift:151-165`; `Circle()` instead of `.circle` at `Modules/MapRPG/Map/MapEditorOverlayLayer.swift:351`; `locale.identifier.hasPrefix("de")` in `Modules/RolePlayGameKit/View/DestinationReadyView.swift:70`
- **Action:** `Label` + `.labelStyle(.iconOnly)`; static member lookup; `locale.language.languageCode`.
- **Severity:** Low

## 5. Bugs / logic errors

### 5.1 Redo restores the pre-edit state because `UndoManaged.value` is never advanced after a save
- **Location:** `Modules/CoreRPG/App/UndoManaged.swift:8-57`, `Modules/CoreRPG/Controllable/EditControllable.swift:452` (also `:428`, `:478`), `Modules/CoreRPG/Controllable/EditControllable+Undo.swift:19-54`
- **What:** `value` is set only by `resetValue` (item selected) and by the library-scoped branch in `undo()`/`redo()`. `saveChanges` pushes the previous copy onto the undo stack but never records the saved model as `value`, so `undo()` moves the stale `value` onto the redo stack.
- **Why:** Select item (V0), edit A, edit B: undo applies A, redo applies V0 and persists it via `replace` — edit B is lost with no way back. Even a single edit followed by undo then redo leaves the item at V0. No test exercises `redo()` through `EditControllable`.
- **Action:** After every successful save record a copy of the saved model as the current undo value (or snapshot the live item in `undo()`/`redo()` as the library-scoped branch already does); add an edit-edit-undo-redo test.
- **Severity:** High (verified by lead, §12)

### 5.2 Batch group edit wipes every selected item's own tags when the items have different tags
- **Location:** `Modules/CoreRPG/LGViews/GroupEditorController.swift:79-119` (seed `tags` as `[]` at `:91`, replace at `:118`), `GroupEditorView.swift:168-190`, `Modules/CoreRPG/Controllable/EditControllable.swift:158-167` (`reset(tags:)` is a full replace)
- **What:** The CODE_AUDIT_EditItem §5.6 fix seeds the editor with tags only when all items share them. When the sets differ the editor starts empty, adding one tag sets `tagsChanged`, and `save()` calls `reset(tags:)` on every item with just that tag. The audit's own recommendation (additive path or disabled editor) was not implemented.
- **Why:** Three NPCs tagged {Boss, Undead}, {Elf}, {Boss}; add "Act2" and Save: all three end with only {Act2}; tag counts are decremented accordingly. No confirmation.
- **Action:** When tags differ switch to additive semantics (union per item; removals only for tags explicitly removed from a shown shared list) or disable the tag section with an explanation.
- **Severity:** High (verified by lead, §12)

### 5.3 Table range matching is only active for `tableType == .dice`, which no editor path sets
- **Location:** `Modules/TableRPG/Controller/TableGenerationController.swift:245-261` (condition at `:253`); only setter of `.dice`: `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Documents.swift:398`; `Modules/TableRPG/Controller/EditController.swift:77-81` (`add(diceId:)` sets only `diceId`); `Docu/TABLE_GENERATOR.md:236-262` still documents range matching for every table
- **What:** CODE_AUDIT_21 §5.18 restricted numeric range lookup to `.dice` so that "2 Wolves" is not read as a range, but nothing in the UI/edit path ever sets `.dice` (repo grep: the only write is the Foundry mapper).
- **Why:** A user drags a d20 onto a table with entries "1-5 / 6-10 / 11-15 / 16-20" and rolls: 17 → positional index → "Roll 17 does not match an entry"; a roll of 3 selects "11-15". Auto Roll and player-rolled results are equally wrong.
- **Action:** Derive the type from data (apply range lookup when `diceId != nil`, with positional fallback) or let the editor set `.dice` on linking a Dice or expose it; update `TABLE_GENERATOR.md`. Related: positional fallback also fires for a dice table with a gap (§5.28).
- **Severity:** High (verified by lead that the setter is absent; runtime not run)

### 5.4 Foundry Adventure import links every hidden field-group item and rule duplicate, in random order
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Documents.swift:489-515` (`mapAdventure`, `:502`), `FoundryVTTDomainMapper+SharedHelpers.swift:59-95` (`add` always calls `recordMapping`, `:70`/`:92`), `FoundryVTTDomainMapper+DiceAndValues.swift:164-169`, `FoundryVTTDomainMapper.swift:245` (`[String: Set<FoundryImportMappingReference>]`)
- **What:** `mapAdventure` builds one entry per element of the `Set` of references recorded under a child's source id. That set also contains every auxiliary model emitted under it (one hidden `groupHidden` Value per nested `system` object of an Actor/Item) and both the `.value` and `.rule` projection of a standalone Item.
- **Why:** An Adventure with an embedded Actor whose `system` has ~30 nested objects gets ~31 entries named after the actor (one real link, ~30 to internal hidden values); entry order differs per process (hash seed), so a re-import reports "Changes existing item" for an unchanged Adventure and Merge/Replace reorders entries. No test covers `mapAdventure`.
- **Action:** Build entries from the child's primary destination only, skip auxiliary items (those with a `decisionOwnerID`), order references deterministically with `mappingOrder`; add an Adventure test embedding an Actor and an Item.
- **Severity:** High (verified by lead, §12)

### 5.5 Folder cycle guard from an earlier audit never detects a cycle (key mismatch) — regression of a "fixed" item
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Indexes.swift:188, 198, 210-247, 277-296`; id formats at `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:791, 794`
- **What:** `declarationsByID` is keyed by the canonical id (`foundry://…/Folder/<docId>`) and `visited` is seeded with it, but `folder.parentID` is the raw Foundry id, so `declarationsByID[current]` never matches: the walk ends after one step and returns the parent unchanged. CODE_AUDIT §5.13 (earlier audit 7) is marked fixed.
- **Why:** Folders A and B naming each other as `folder` (or a self-parent) become a circular `parentId` chain in Value, Map, Adventure and other modules; breadcrumbs, move validation and cascade delete can loop or hang. Input is untrusted import data.
- **Action:** Key the lookup, `visited` and the walk by the same (scoped) id, as `resolveFolder` does; test a two-folder cycle and a self-parent.
- **Severity:** Medium (verified by lead, §12)

### 5.6 "Refresh Shared Map" bypasses the ordered content-send queue
- **Location:** `Modules/MapRPG/Map/EditMapToolBarButtons.swift:264-268` (compare `Modules/MapRPG/Root/MapRootModel.swift:36-48`, `Map/GameToolBar.swift:389-390`, `Map/RootGameMapViewer.swift:75-76`, `Modules/GameRPG/Table3D/GameTableModel+Broadcast.swift:80-81`)
- **What:** The documented rule is that every GM content send goes through `enqueueMapContentSend`; the editor's Refresh button builds and sends from a bare Task and does not flush `mapsWithUnsharedStructure`.
- **Why:** Refresh (async export in flight) followed by a toolbar reshare or hex toggle can deliver the older update last; players end on stale fog until the next full update (a different `contentVersion` prevents duplicate rejection).
- **Action:** Route through `enqueueMapContentSend`; add an ordering test.
- **Severity:** Medium (verified by reading, agent)

### 5.7 Weather edits during a game never reach players (version covers only the linked photo)
- **Location:** `Modules/WeatherRPG/Controller/GameController.swift:88-97, 121-125`; `Modules/GameRPG/Controller/MasterController+WeatherMessages.swift:10-28`; `MasterController+PackageCache.swift:53-60`; no game-mode edit guard in `Modules/WeatherRPG/Controller/EditController.swift:37-112`
- **What:** `weatherVersion` is the photo's version (0 without a photo); `.update` is declared unsupported ("immutable for the lifetime of a game") but nothing blocks editing.
- **Why:** GM shows "Storm" (version 0), then changes rain/time of day and reshows: the cached package fingerprint is unchanged and players keep the old weather while the GM sees the new one.
- **Action:** Include a digest of the weather fields in `weatherVersion`, or block edits while it is the current game item.
- **Severity:** Medium (likely)

### 5.8 Rebuilding table children reuses one child twice when an entry links the same table more than once
- **Location:** `Modules/TableRPG/Controller/TableGenerationController.swift:298-331` (lookup `:309-314`)
- **What:** Existing children are matched by `(sourceEntryId, tableId)`; with two links to the same table the second build matches the first child for both links.
- **Why:** Selecting a sibling entry duplicates the first child (duplicate `ForEach` identity, doubled outcome text, double-counted occurrences, second child's choices lost).
- **Action:** Match by position within the entry's link list (consume each existing child once) or de-duplicate links per entry.
- **Severity:** Medium (verified by reading, agent)

### 5.9 Pdf and Space "image" exports always throw (full-image cache is never filled)
- **Location:** `Modules/PdfRPG/Intent/PdfEntity+Image.swift:13-17`, `PdfEntity.swift:108-110`, `Modules/SpaceRPG/Intent/SpaceEntity+Image.swift:9-15`, `SpaceEntity.swift:106-108`; cause `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:46-57` (empty default `createImage`; `photo(for:)` reads only the memory cache)
- **What:** Only PhotoRPG's cache creates full images; Pdf/Space only produce QuickLook thumbnails, so `photo(for:)` returns nil and `AKImageEncodingError` is thrown on every request.
- **Why:** A Shortcut/share-sheet request for `.image` of a PDF or 3D object always fails.
- **Action:** Encode the thumbnail (`thumbnail(for:)` falls back to disk) or generate the QuickLook thumbnail on demand; or drop the representation.
- **Severity:** Medium (verified by lead, §12)

### 5.10 Space viewer opens the model file without starting the iCloud download
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer+Loading.swift:42-64` via `Modules/CoreRPG/Controllable/ItemControllable+Viewer.swift:46-49`
- **What:** `loadableUrl` only resolves a URL; Pdf and Photo call `download(fileUrl:)` first, Space goes straight to `Entity(contentsOf:)`.
- **Why:** A 3D object imported on another device opens as "could not be loaded" or stalls while the same item as PDF/photo works (whether `Entity(contentsOf:)` materialises a placeholder itself is unverified).
- **Action:** Download/wait with a bounded timeout before loading, showing the existing loading state.
- **Severity:** Medium (likely)

### 5.11 Player statistics sessions take adventure, master and roster before the master's state has arrived
- **Location:** `Modules/GameRPG/Root/GameRoot+Player.swift:93-139`; `Modules/GameRPG/Statistics/Controller/GameRoot+Statistics.swift:14-70`; `GameStatisticsDataController.swift:68-86` (`checkpointSession` never updates session fields); `Modules/CoreRPG/Model/GameModel.swift:38`
- **What:** `joinGame` calls `beginStatisticsSession` possibly before the first master broadcast was applied; it reads `gameConfig.master` (`.empty`) and falls back to the player's own `selectedAdventure`. Session fields are written once.
- **Why:** A user who also GMs adventure A and joins a friend's game can have the game stored as adventure A with empty title/master, skewing the Adventures chart and distinct-adventure achievements.
- **Action:** For players do not fall back to `selectedAdventure`; fill adventure/master in `checkpointSession` once known, or defer `beginSession` until the first master broadcast.
- **Severity:** Medium (likely)

### 5.12 A session that is still "active" when the next game starts is closed at the next game's start time
- **Location:** `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:89-108, 271-289`; `Modules/GameRPG/Root/GameRoot+Master.swift:75-77`; `GameRoot+Player.swift:139`; `GameRoot+Stop.swift:68-69`; contrast `GameStatisticsDataController.swift:16-39` (recovery closes at `lastActivityAt`)
- **What:** `beginSession` completes a leftover `activeSessionID` at the *new* game's start with reason `.interrupted`. A leftover arises when `stopGame()` runs while `beginSession` is suspended in Core Data, or when `finishSession` throws.
- **Why:** An orphan closed two days later gets ~48 h duration, counts as "longest game", and feeds the 8 h / 100 h achievements reported to Game Center (cannot be revoked).
- **Action:** Close a leftover at its own `lastActivityAt`; re-check the stop generation after `beginStatisticsSession`; retry/clear `activeSessionID` after a failed `finishSession`.
- **Severity:** Medium (verified by reading; stop race narrow, save-failure path real)

### 5.13 Party chart keys the game master (and character-less participants) by a per-game random id
- **Location:** `Modules/GameRPG/Statistics/Controller/GameStatisticsController.swift:311-326`; id source `Modules/GameRPG/Root/GameRoot+Master.swift:34-43`, `GameRoot+Player.swift:49-52`; `Statistics/View/GameStatisticsCategoryBarChart.swift:16` (`prefix(8)`)
- **What:** Participants without a character are aggregated by a fresh `UUID()` per game.
- **Why:** A player with 30 games sees up to 30 "GameMaster" points; `prefix(8)` shows only 8 of them.
- **Action:** Key by role+name (or exclude name-less roles) and aggregate before `prefix`.
- **Severity:** Medium (likely)

### 5.14 Universal VTT import fails for file names containing `#` or `?`
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/UniversalVTTDomainMapper.swift:30-39`; `FoundryMediaNormalizer.swift:80-86, 129-133`
- **What:** The plan is built from `"\(sourceName).\(imageExtension)"` and `plan(for:)` cuts at the first `?`/`#`, losing the extension; `plan(forPackagedPath:)` exists for this (audit 26 §5.40) but is not used.
- **Why:** `Crypt #2.dd2vtt` fails with "image could not be decoded".
- **Action:** Plan from the image resource's own path or use `plan(forPackagedPath:)`.
- **Severity:** Medium (verified by reading, agent)

### 5.15 Imported item text embeds locale- and time-zone-dependent formatting
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Documents.swift:309-310, 406, 415, 569`; `FoundryVTTDomainMapper+SharedHelpers.swift:405`; `UniversalVTTDomainMapper.swift:66`
- **What:** `.formatted()` writes numbers and dates into persisted entry content using the device locale/time zone.
- **Why:** The same world imported on English and German devices differs (`1,000–1,500` vs `1.000–1.500`, `2.5` vs `2,5`, chat names), so conflict preflight reports changes and Merge/Replace rewrites CloudKit-synced items.
- **Action:** Fixed locale-independent formatting for stored text (POSIX number style, ISO-8601 dates); locale formatting only for review UI.
- **Severity:** Medium (verified by reading, agent)

### 5.16 Percent dice ignore modifier, rerolls and per-die maximum
- **Location:** `Modules/DiceRPG/Controller/GameController+DiceResult.swift:69-77, 112-113` (compare `:78-87`); `DiceOptionEditor.swift:19-23`
- **What:** With `percentDice` the sum skips `item.modifier`, `rerollOptions` and `maxValuePerDice`, while the editor still offers those and `diceSuccess` marks every percent die a success.
- **Why:** A d100 with modifier +10 and a compare value shows a total and check that ignore the +10, unlike the same dice with percent off.
- **Action:** Decide the semantics: apply them in the percent branch (clamped to 1…100) or disable the editors and document.
- **Severity:** Medium (likely; may be deliberate, not in any prior audit)

### 5.17 `canBecomeGroup` / `convertToGroup` accept the item itself, folders, hidden items and cycles
- **Location:** `Modules/CoreRPG/ItemList/GroupableEntryEditing.swift:27-58`; candidates from `Modules/CoreRPG/Sheet/SheetRootModel+Editor.swift:66-77`
- **What:** `canMoveIntoGroup` requires `itemId != targetId`, no special category, no group, fully visible; the convert path checks only `groupId == nil`.
- **Why:** An entry linking to its own character, then Convert-to-Group, hides the character and parents it to itself; a loop hides both and makes the group tree unreachable.
- **Action:** Apply the `canMoveIntoGroup` predicate (plus ancestor check) in `canBecomeGroup` and `convertToGroup`.
- **Severity:** Medium (likely)

### 5.18 List refresh stream watches a stale `parentModel`
- **Location:** `Modules/CoreRPG/LGViewModifiers/ListModelUpdatesViewModifier.swift:54-72`; host `Modules/CoreRPG/ItemDetail/ItemEditorForegroundView.swift:48-53`
- **What:** One observation task starts on first appear (no id) and captures `parentModel` once; a reused detail view keeps observing the first folder.
- **Why:** Detail shows folder A, user selects folder B, a sync adds an item to B: the list stays stale until another search trigger.
- **Action:** Key the task on the observed model identity or give the host view `.id(parentModel.id)`.
- **Severity:** Medium (likely)

### 5.19 Foundry ZIP open counts all entries (assets included) against the rule-data budget
- **Location:** `Modules/CoreRPG/Foundry/FoundryZIPArchive.swift:178-186`; `FoundryRuleModels.swift:736-759`
- **What:** The sum of uncompressed sizes (images, audio) is compared with the platform rule-data limit (128 MiB iOS/tvOS/visionOS); entries are inflated lazily and already capped at 64 MiB each.
- **Why:** A legitimate package with 200 MiB of artwork is rejected on an iPhone though only a few MiB of JSON would be read.
- **Action:** Apply the aggregate limit to entries selected for decoding, or use the 1 GiB archive limit for the total.
- **Severity:** Medium (likely)

### 5.20 Character-based input limits for PDF/table analysis ignore token density
- **Location:** `Modules/GeneratorRPG/BasicAI/Providers/PdfSummaryAnalyzer.swift:19-27`, `TableSummaryAnalyzer.swift:12`, `PdfContentExtractor.swift:27-35, 144-158`, `Engine/FoundationModelInputLimiter.swift:14-66`
- **What:** Prompts are cut at 7000 characters (tuned for Latin text) although real token counting exists in the module.
- **Why:** A Japanese/Chinese/Korean PDF or table always fails as "too large", and the extractor reports every page failed.
- **Action:** Size by tokens (binary-search a prefix with `tokenCount`) with a script-aware fallback; retry once with half the limit on `exceededContextWindowSize`.
- **Severity:** Medium (likely)

### 5.21 Merge and duplicate id-handling gaps
- **Location:** `Modules/MapRPG/Model/MapEntryModel.swift:135-144` (merge drops `focused`, `displayState`); `Modules/WeatherRPG/Model/WeatherModel+Sync.swift:7-36`, `WeatherModel.swift:306-345` (photoId picked by a stamp photo edits never move); `Modules/MapRPG/Model/MapModel+DataAccess.swift:24-29` (duplicated map keeps pin/wall/display-config ids); `Modules/CharacterRPG/Controller/EditController+Duplication.swift:59-84` (group referenced twice leaves an orphan copy)
- **Why:** A merged hex cell loses its `groupHidden` state; a concurrent weather edit reverts a linked photo; duplicated maps share pin ids across maps; a duplicated character gets a stray group.
- **Action:** Carry fields explicitly in the merge and test it; make `photoId` a CRDT register or part of the stamp; re-id (and remap references of) pins/walls on duplicate; keep an old→new map during character duplication.
- **Severity:** Low (likely/speculative)

### 5.22 Locale- and iteration-order-dependent ordering that is persisted or shown
- **Location:** `Modules/CharacterRPG/Controller/EditController+Repair.swift:62-66` (`localizedCompare`, persisted and CloudKit-synced); `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:314-316`; `Modules/GameRPG/Statistics/Controller/GameStatisticsController.swift:235-340`, `Statistics/View/GameStatisticsScheduleChart.swift:17, 43-46` (ties follow `Dictionary` order; heat map buckets in the viewer's current time zone, Sunday-first)
- **Why:** Two devices with different languages running Validate Folders can flip a CRDT order back and forth; chart categories reorder between launches.
- **Action:** Locale-independent comparison with an id tiebreak for anything persisted; deterministic secondary sort for charts.
- **Severity:** Low (speculative/verified)

### 5.23 Dice model persistence and arithmetic edges
- **Location:** `Modules/DiceRPG/Controller/DataController.swift:62-77, 129-149` (modifier/compareValue stored as Float, die UUIDs regenerated per load); `Modules/DiceRPG/Model/DiceModel.swift:140-161, 201-210` + `DiceModel+ItemData.swift:72-96` (`didSet { resetDice() }` runs inside `replace(with:)`); `Modules/DiceRPG/Model/RawDice.swift:73-79`, `RawDieCounter.swift:31-37` (min/max invert for negative counts); `Modules/CharacterRPG/Controller/EditController+InlineEditor.swift:86-100, 122-138` (zero modifier persisted as "base|0")
- **Why:** Compare values above 2^24 read back different on a synced device; a synced edit can cause a spurious CRDT bump; an inverted range can trap; nudging HP and back leaves "12|0" and syncs as a change.
- **Action:** Store Doubles (CloudKit-safe migration) or clamp at the edit boundary; suppress observers during replace; order bounds after multiplying; normalise zero modifiers away.
- **Severity:** Low (likely/speculative)

### 5.24 Error and store-setup handling in CoreRPG data layer
- **Location:** `Modules/CoreRPG/Controllable/GameControllable.swift:322-326` (every non-cancellation import error mapped to `networkDecoding`, hiding disk-full/write errors); `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:148-155, 203-207`, `CloudKitCoreDataPersistenceController.swift:34-42, 103-106` (folder-creation error overwritten by the load completion); `Modules/CoreRPG/Model/StableVersionDigest.swift:19` (`try?` encode failure collapses to version 1; speculative non-finite Double)
- **Action:** Keep the underlying error; return early after a failed `createDirectory`; give the digest encoder a non-conforming-float strategy.
- **Severity:** Low

### 5.25 Link evaluation memo caches depth-limited results
- **Location:** `Modules/CharacterRPG/Controller/LinkController.swift:190-247`
- **What:** A value evaluated near `maxValueLinkDepth` is memoized in its truncated form and reused for a shorter path in the same calculation.
- **Why:** The same entry can yield different HP/modifier depending on evaluation order.
- **Action:** Do not memoize depth-limited results (or key by remaining depth).
- **Severity:** Low (speculative)

### 5.26 Save Game mutates the running game's maps
- **Location:** `Modules/MapRPG/Controller/GameController+Metadata.swift:466-478` (via `Modules/AdventureRPG/Controller/GameController.swift:91-93`)
- **What:** `saveAll()` strips player pins and clears `isPhotoShared` on the live game maps without broadcasting (pin stripping is accepted in CODE_AUDIT_24 §303; `isPhotoShared` is not).
- **Why:** After Save Game the GM's item loses `isPhotoShared` while players' popovers stay open until the next pin sync.
- **Action:** Export from a filtered snapshot and leave live items untouched, or re-broadcast.
- **Severity:** Low (speculative)

### 5.27 Per-game state in `GameRootModel` is never reset in production
- **Location:** `Modules/GameRPG/Root/GameRootModel.swift:86-92, 197-207, 361-383`; `GameRoot+Stop.swift:56-83` (reset called only from tests)
- **What:** `latestValueUpdateCounters`, `latestValueUpdateOrder`, `peerIntroducedItemIds` persist across games; the order list is not cleared even by the test-only reset.
- **Why:** Memory only today (random per-game sender ids); if sender ids ever become stable, a restarted counter would drop value updates silently.
- **Action:** Clear them in `performStopGame`/`MasterController.stop()` and make tests use the production path.
- **Severity:** Low (verified)

### 5.28 Table roll edges and export
- **Location:** `Modules/TableRPG/Controller/TableGenerationController.swift:253-260` (positional fallback picks an unrelated entry when ranges leave a gap); `Modules/TableRPG/Controller/ExportController.swift:56-72` (photo/rule links not exported, error log per link)
- **Action:** Positional fallback only if no entry has a parsable range; handle `.photo` like Character or downgrade the log.
- **Severity:** Low

### 5.29 Foundry importer smaller issues
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:697-715` (orphan child records dropped silently); `FoundrySystemCompendiumDecoding.swift:22-35` + `FoundryVTTDecoder+CollectionDecoding.swift:292-322` (re-implemented merger, keyed by `_id` alone: an Item and an Actor with one `_id` overwrite each other); `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Scenes.swift:187-197` (token names not sanitized), `FoundryVTTDomainMapper+Documents.swift:540-572` etc. (English literals in stored content), `+SharedHelpers.swift:146-160` (`@Item[...]` resolves to the Rule copy even if the user kept the Value); `Modules/CoreRPG/Menu/SpaceActionButton.swift` (verb not localized)
- **Action:** Count and report orphans; reuse the shared merger keyed by (type, id); sanitize token names; decide on localized vs data literals.
- **Severity:** Low (likely)

### 5.30 Join intent and quick-edit inconsistencies
- **Location:** `Modules/GameRPG/Intent/GameIntents.swift:226-239` (reports "couldn't reach" when its start was ignored as already running, and can overwrite `IntentGameContext`); `Modules/CoreRPG/EntryEditor/EntryEditorContent.swift:68-72` (focus after cancelled sleep); `Modules/CoreRPG/EntryEditor/EntryEditorHeaderView.swift:76-105` (dropped link saved with `forceSave: false` next to a force-saved text); `Modules/CoreRPG/Views/CloudKitSyncStatusView.swift:85-110` (`isExpired` never reset)
- **Action:** Check the starting flags first; add cancellation guard; thread `forceSave`; reset `isExpired`.
- **Severity:** Low (likely)

### 5.31 Positional `isSame` in Audio/Photo where Pdf compares by id
- **Location:** `Modules/AudioRPG/Model/AudioModel.swift:149-153`, `Modules/PhotoRPG/Model/PhotoModel.swift` (same shape probably in `SpaceModel.swift`, not opened); fixed for Pdf in CODE_AUDIT_Pdf §5.5
- **Why:** Same entry set in different order after a union merge reads as "changed" → extra saves and sync churn.
- **Action:** Compare by id (first-wins dictionary) plus count.
- **Severity:** Low (likely)

### 5.32 Widget load path writes to the App Group; Spatial 3D conversion outside its security scope
- **Location:** `Modules/DiceRPG/Widget/DiceConfiguration.swift:176-184`, `Sources/DiceRollerWidget/AccessoryDiceView.swift:29`; `Modules/PhotoRPG/Space/Spatial3DImageState.swift:57-67, 109-137`
- **What:** `loadFromUserDefaults()` writes a migrated snapshot from a timeline call (can overwrite a concurrent app roll; empty circular accessory shows "0"); `generate()` may re-read a file after the security scope ended.
- **Action:** Make the load side-effect free and show a placeholder; hold the scope for create-and-generate.
- **Severity:** Low (likely/speculative)

### 5.33 `preconditionFailure` when a root manager is not yet wired
- **Location:** `Modules/AdventureRPG/Root/AdventureRootModel.swift:116-118, 197-219`, `Modules/AdventureRPG/View/AdventureSheet.swift:102-104`, `Modules/CharacterRPG/Root/ViewerRootView.swift`; `Modules/RuleRPG/Controller/ExportController.swift:23-29`, `LinkController.swift:31-37`
- **Why:** A deep link/intent/Spotlight launch before `setUp` terminates the app instead of failing gracefully (only reachable by an ordering regression; two-phase init is tracked as open in CODE_AUDIT_26 §3.10).
- **Action:** Return an empty result/no-op with a log, or await readiness as the intents do (`requireReadyDatabase`).
- **Severity:** Low (speculative)

### 5.34 Weather/Generator polish
- **Location:** `Modules/WeatherRPG/Weather/Lightning.swift:96-135`, `LightningView.swift:36-57` (unclamped frame delta; seeded RNG consumed per frame, so bolts differ across devices despite the comment); `Modules/GeneratorRPG/BasicAI/Errors/FoundationModelsError.swift:8-31, 68-79` (framework `debugDescription` shown to users); `Modules/GeneratorRPG/BasicAI/Model/PdfSummaryAnalysisModel.swift:35-40`, `PdfContentExtractionModel.swift:36-47`, `TableSummaryAnalysisModel.swift:27-32` (cancellation shown as an error, no re-entrancy guard)
- **Action:** Clamp delta and precompute the bolt path; map errors to localized sentences; handle `CancellationError` first.
- **Severity:** Low (likely)

## 6. Security

No exposure that a player can use to reach GM-only data in a way earlier audits did not already accept. Importers of untrusted ZIP/LevelDB/NeDB/NDJSON/UVTT data were read in full by one agent (no zip-slip, no unbounded allocation from declared sizes, capped recursion).

### 6.1 Asset requests and player "show" of file-backed items are not limited to what the GM has shown
- **Location:** `Modules/GameRPG/Controller/MasterController+FileMessageSupport.swift:66-71, 94-110, 128-146`; `MasterController+AudioMessages.swift:39-49`, `+DiceMessages.swift:28-29`, `+TableMessages.swift:22-23`, `+WeatherMessages.swift:23`; `Modules/CoreRPG/Controllable/GameControllable.swift:136` (`createGameData` checks only that the item exists in the library)
- **What:** Only Map asset requests are restricted to the shown map (CODE_AUDIT_26 §5.82). For Photo, Pdf, Space, Audio, Dice, Table and Weather the master answers a request for any library id (waits for local data, then returns the cached players-audience package), and a player-originated `show` of an existing library id calls `share(id:)` for any id the player names.
- **Why:** A joined player (or modified client) that learns an id (UUIDs leak through shared links, character sheets, exported adventures, the Journal) can pull an unshown secret handout, and make the GM show it to the table. Prior decision "players are trusted" (CODE_AUDIT_26 §6.5) covers items already shown, not requests for never-shown items — confirm whether it was meant to.
- **Action:** Mirror §5.82 for the other modules: answer only for the item currently shown or published in this session (a small "offered ids per module" set maintained in `show`/`sendPresentation`); accept player shows of an existing id only when in that set or explicitly allowed; test that an unshown id returns `.failed`. Do it in one shared entry point (§9.2).
- **Severity:** Medium (verified by lead that the check is absent, §12)

### 6.2 Foundry template decoder has no cap on subtypes or total fields
- **Location:** `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:435-476`
- **What:** Template count and recursion depth are capped, but each subtype receives its own flattened schema.
- **Why:** A crafted `template.json` of a few MiB with thousands of subtypes × thousands of fields yields millions of entries and a jetsam kill during import.
- **Action:** Add a total-field budget and subtype cap failing with the existing import error; share flattened schemas between subtypes with identical template lists.
- **Severity:** Medium (likely)

### 6.3 Player update to a foreign pin is authorized by `isShown`, not full visibility
- **Location:** `Modules/MapRPG/Controller/GameController+Pins.swift:349-351` (rule at `Modules/MapRPG/Model/MapModel+Geometry.swift:30-53`)
- **What:** A highlight toggle on another's pin is accepted when `currentPin.isShown`, not when `isPinVisibleToPlayers` (which also requires no unrevealed room over it).
- **Why:** After the GM hides a revealed room again, a player who knows the pin id can still flip its highlight flag for everyone (flag only, no location/metadata).
- **Action:** Use `isPinVisibleToPlayers` on the receive side.
- **Severity:** Low (verified)

### 6.4 `isBelowFileRoot` treats all of Documents and tmp as deletable roots
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:491-505`, `FileUrl.swift:193-207`
- **What:** An imported/peer-delivered file reference pointing into another module's local file (or the Foundry import database) passes the root check, so deleting that item can remove the other file when nothing references it.
- **Action:** Restrict deletable roots to the module's own folder and the remote cache (mitigated by the trusted-player model and the unreferenced check).
- **Severity:** Low (likely)

### 6.5 `PdfContentExtractor` puts raw page text into the prompt without the untrusted-material fence
- **Location:** `Modules/GeneratorRPG/BasicAI/Providers/PdfContentExtractor.swift:160-175` (contrast `PdfSummaryAnalyzer.swift:63, 136`, `UntrustedPromptText.swift`)
- **Why:** Page text claiming to be instructions can produce fake blocks the GM may accept (review view limits impact).
- **Action:** Fence the page text and append the instruction; skip the unused prewarmed session after the last page (`:101-103`).
- **Severity:** Low (verified)

### 6.6 `.direct(nil)` asset answer broadcasts to every connection
- **Location:** `Modules/GameRPG/Network/GameNetworkController+Delivery.swift:89-90`
- **What:** Falls back to `sendPlayer(data:)` (all connections) though the doc comment says "requester only". No production caller found.
- **Action:** Treat like `.proxy(nil)` or assert it never carries a player request.
- **Severity:** Low (speculative)

### 6.7 Statistics privacy footer understates what is stored and synced
- **Location:** `Modules/GameRPG/Statistics/View/GameStatisticsCustomizationView.swift:35-37`; `GameStatisticsDataController.swift:166-192, 416-431`
- **What:** Event rows keep sender display names, dice result values and ids; participant rows keep other players' and character names; all entities sync to the user's private CloudKit database; the footer says "Message contents and media files are never stored".
- **Action:** Reword the footer (and App Store privacy answers) or stop persisting `actorName`/`resultValues`.
- **Severity:** Low (verified)

### 6.8 `RuleEntryTree` recursion and visited-set copies are unbounded for imported hierarchies
- **Location:** `Modules/RuleRPG/Model/RuleEntryTree.swift:192-204, 233-253`
- **Why:** A rule with a ~30k-long parent chain costs O(depth²) and recurses depth-deep (freeze/stack overflow).
- **Action:** Cap depth and traverse iteratively with one shared visited set.
- **Severity:** Low (speculative)

### 6.9 macOS sandbox likely lacks `files.bookmarks.app-scope`
- **Location:** `Resources/MasterRPG-Mac-Debug.entitlements`, `MasterRPG-Mac-Release.entitlements`; consumer `Modules/CoreRPG/Files/FileBookmarkController.swift:163-205`
- **What:** macOS creates security-scoped bookmarks; the key was in the Info plists (no effect) and removed without moving it to an entitlements file (b60d4cfed/4c21602bc).
- **Why:** `saveBookmark` throws and the failure is logged and ignored: bookmark re-resolution of moved/iCloud files silently never works on Mac.
- **Action:** Check the signed build with `codesign -d --entitlements -`; add the key or drop the bookmark attempt on macOS.
- **Severity:** Low (speculative)

### 6.10 tvOS declares background modes and entitlements nothing uses
- **Location:** `Resources/InfoTV.plist` (`fetch`, `remote-notification`), `MasterTV-*.entitlements` (`aps-environment`, CloudKit), `Modules/RolePlayGameKit/Model/AppModel.swift:197, 222` (tvOS Core Data is local-only)
- **Why:** App Review can ask (guideline 2.5.4); no functional bug.
- **Action:** Remove `fetch`; drop push/CloudKit entitlements if tvOS will not sync, or document.
- **Severity:** Low (likely)

### 6.11 Share extension: no total text cap, no save re-entrancy guard
- **Location:** `Sources/RPGShare/ItemProviderImporter.swift:67-82`, `SharingView.swift:137-146, 328-345`, `ShareViewController.swift:73-100` (macOS branch not shipped)
- **Why:** ~20 large text files can exceed the extension's ~120 MB limit; a fast double tap can save twice.
- **Action:** Total text budget like the image path; `guard !isSaving`; remove the dead macOS branch.
- **Severity:** Low (likely)

## 7. Performance

### 7.1 Full-map equality compared in a view body and on every history checkpoint
- **Location:** `Modules/MapRPG/Map/EditMapToolBar.swift:343-349` (read at `:246`), `MapEditorPinHistory.swift:23-24, 62-63`, `Model/MapModel+Codable.swift:15`, `RootEditCanvasMap.swift:93-94`
- **What:** `sharedMapHasChanges` compares every entry and pin whenever the toolbar re-evaluates; snapshot `==` repeats it before each `record`. Up to 20,000 hex cells.
- **Why:** On a capped hex map the editor hitches on pan/selection/pin drag.
- **Action:** Dirty flag or revision counter, or a debounced fingerprint comparison.
- **Severity:** Medium (likely)

### 7.2 Hex grid is regenerated with fresh ids on every slider change
- **Location:** `Modules/MapRPG/Map/EditMapToolBar.swift:110-114`, `MapEditController+HexGrid.swift:41-62`, `MapHexGridGeometry.swift:81-110` (new `UUID()` per cell at `:101`)
- **Why:** Dragging the hex size allocates and diffs up to 20k entries per tick; after commit all ids differ, so a running game sends all cells and loses any id-keyed state.
- **Action:** Rebuild at the end of the drag; derive hex ids deterministically from grid position.
- **Severity:** Medium (likely)

### 7.3 Photo thumbnails and geometry probes read the whole file into memory before decoding
- **Location:** `Modules/PhotoRPG/Controller/FileUrlDataController+ImageResolve.swift:20-33` (used by `CacheController.swift:62-70`, `PhotoRootModel+PhotoAccess.swift:19-33, 49-58, 75-81`, `EditController.swift:55-68`)
- **Why:** Scrolling a library of 40 MB photos loads 40 MB per uncached 256 px thumbnail (up to 3 at once); map repair reads every full file for a header.
- **Action:** Prefer `CGImageSourceCreateWithURL` for downsample/size-probe/thumbnail callers; fall back to `Data`.
- **Severity:** Medium (verified by reading; not measured)

### 7.4 Statistics reload, achievements and event recording scale with the whole event history (known open)
- **Location:** `Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift:134-282, 356-407`; `Model/GameStatisticsModel.swift:291-319, 443-458`; `Controller/GameStatisticsController.swift:64-158`; model has no index on `deduplicationKey`
- **Why:** After a year of play (tens of thousands of event rows) opening the dashboard or ending a game loads all rows and runs ~10 linear passes on the main actor. CODE_AUDIT_12 §7.3 and CODE_AUDIT_26 §7.50 name this as open.
- **Action:** Run `summary` off the main actor, aggregate in the store, fetch participants once per batch, add an index, consider event retention.
- **Severity:** Medium (likely)

### 7.5 Undo stack is unbounded and keeps a full deep copy per save
- **Location:** `Modules/CoreRPG/App/UndoManaged.swift:30-35`; `Modules/CoreRPG/Controllable/EditControllable.swift:452`; cap exists only for library-scoped entries (`Modules/CoreRPG/ItemList/ItemEditorModel.swift:61-66`, 64)
- **Why:** A long edit session on a large Character/Adventure retains every intermediate copy until another item is selected.
- **Action:** Cap the stack (e.g. 100) and keep the library-scoped cap in step.
- **Severity:** Medium (verified by reading)

### 7.6 Rule sheet rebuild re-projects the whole entry tree and every link on each update
- **Location:** `Modules/RuleRPG/Controller/SheetController.swift:51, 122-153`; `Modules/RuleRPG/View/RuleQuickEntryEditor.swift:15-18`
- **Why:** Typing in a 500-entry rule's description re-projects all entries and links per debounce.
- **Action:** Diff by entry id/content first; build editor state lazily.
- **Severity:** Medium (speculative)

### 7.7 Foundry import parsing overheads
- **Location:** `Modules/CoreRPG/Foundry/FoundryRuleModels.swift:50-87` (`try?` type cascade allocates `DecodingError`s); `FoundrySystemPackageReader.swift:530-615` (six `range(of:)` per string); `FoundryVTTDataSource.swift:86-93` (plain-file SHA-256 recomputed per access, up to 1 GiB); `FoundryZIPArchive.swift:428` (inflate buffer copied again); `FoundryArtifactDetector.swift:107-111` (large JSON fully parsed to detect kind)
- **Action:** Single-value container dispatch; single scan; cache the hash; return the buffer directly; peek a bounded prefix.
- **Severity:** Low (likely)

### 7.8 PhotosPicker import loads the complete original as `Data`
- **Location:** `Modules/PhotoRPG/Photo/InlineImporterView.swift:105`; `EditController.swift:157-163`
- **Why:** ProRAW/HEIC originals of 25–80 MB spike memory (data plus decoded bitmap).
- **Action:** File-based transferable and ImageIO from the URL with a pixel cap.
- **Severity:** Low (likely)

### 7.9 `TextIntEditor` still saves on every slider tick
- **Location:** `Modules/CoreRPG/Editors/TextIntEditor.swift:54-57`; used at `Modules/DiceRPG/Dice/SpecialOptionEditor.swift:55`
- **Why:** CODE_AUDIT_26 §7.45 fixed only `TextDoubleEditor`; dragging across a range saves dozens of times.
- **Action:** Mirror `TextDoubleEditor`'s editing-end save.
- **Severity:** Low (verified)

### 7.10 Minor and carried-over performance items
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:495-538` (staged temp copies never cleaned); `Modules/CoreRPG/Links/ReferenceScanner.swift:27, 48` (quadratic backtracking on long unterminated link text, speculative); `Modules/RuleRPG/Model/RuleModel.swift:200-210, 307-308, 377-381` (`isSame` deep-compares the Foundry source payload, speculative); `Modules/WeatherRPG/Weather/StormView.swift:26-43` (up to 1000 drops with a context copy each per frame); `Modules/CoreRPG/Intent/IntentDonations.swift:47` (ledger pruned only on forget); `Modules/GameRPG/Table3D/GameTableModel+DiceResults.swift` (per-frame `updateDiceResults`, unmeasured); `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:281-316` (O(n) LRU touch); carried-over open items from CODE_AUDIT_26: `ItemList/CacheItemListModel.swift` (§7.44, search iterates all cached link models), `Navigator/Core/NavigationAction.swift:25-40` (§5.67), `Editors/TextIntEditor.swift:5-26` (§8.15)
- **Action:** As listed per site; measure before optimizing the speculative ones.
- **Severity:** Low

## 8. SwiftUI / UI

### 8.1 Fixed-size containers clip at accessibility Dynamic Type sizes
- **Location:** `Modules/CoreRPG/LGViews/ItemHeaderEditorView.swift:~306-315` (single-line name editor capped at 44 pt via `AttributedTextEditorSurface`), `Modules/CoreRPG/EntryEditor/TextEditorLinkView.swift`, `EntryNameEditor.swift`, `Modules/CoreRPG/Editors/TextIntEditor.swift:39` (`maxWidth: 64`), `Modules/CoreRPG/LGViews/UnavailableGlassOverlay.swift:31` (200×400), `Modules/CoreRPG/LGViews/GridLabelView.swift:33` (50×50 icon beside `.title`), `Modules/DiceRPG/Game/Detail/DieViewerView.swift:34` (44×44 dice)
- **Why:** At AX3+ the name field shows half a line, a 3-digit Int value is truncated, the "No Results" description is cut off.
- **Action:** `@ScaledMetric` minimums, no fixed maximum for single-line layout, `containerRelativeFrame`/`fixedSize` for the overlay.
- **Severity:** Medium (likely)

### 8.2 `ManagedPresentationView` registers its navigator from `body`; removal-by-deinit can leave `isPresenting` stale
- **Location:** `Modules/CoreRPG/Navigator/Views/ManagedPresentationView.swift:~62-66`; `Navigator/Core/Navigator.swift` (`deinit`/`removeChild`)
- **Why:** After a swiped-away sheet `navigator.isPresenting` can stay true, which keeps the "start or join game" tip hidden (`PlayerStartView.swift:91`, `MasterStartView.swift:57`). Second half not reproduced.
- **Action:** Register once (as `CreateNavigationStack` does) and reset the parent's flag from the stored `parent` in `deinit`.
- **Severity:** Low (speculative)

### 8.3 Mutating setters on `GameTableModel` do not check the game-master role
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+ToolBar.swift:31-38, 48-64`
- **What:** `pinScale` and `commitHexScale()` write the map without `isGameMaster` and without `broadcastMapEdit(for:)`; only the GM-only toolbar binds them today.
- **Action:** One `isGameMaster` guard and broadcast through `broadcastMapEdit(for:)` so the CLAUDE.md rule holds by construction.
- **Severity:** Low (speculative)

### 8.4 App shell nits
- **Location:** `Modules/RolePlayGameKit/Route/SettingsRouteDestinationView.swift:20-21` (new `ValidateRepairModel()` created in `body`; a re-evaluation during a repair shows a fresh empty model while the old one advances); `Model/AppModel.swift:48-52` (identical `databaseModel` in both `#if os(tvOS)` branches), `:197-212` (tvOS passes `adventureRoot` as `generatorRoot`); `View/SplitNavigation.swift:12` (`scenesManager` environment only used on macOS)
- **Action:** Own the model as `@State` in the view; remove the duplicated `#if`.
- **Severity:** Low (likely)

### 8.5 Global search module order is a locale-prefix special case and starts empty
- **Location:** `Modules/GameRPG/Search/SearchListView.swift:23-25, 59-64`
- **Why:** The first frame after `showSearchResults(for:)` shows no sections; other locales get no tuned order.
- **Action:** Compute the order as a pure function of the locale (or init `@State` in `init`).
- **Severity:** Low

### 8.6 Smaller view-logic and structure nits
- **Location:** `Modules/MapRPG/View/DisplayConfigEditor.swift:35-40` (border editor hidden with opacity 0 and a 1 pt frame instead of conditional content); `Modules/DiceRPG/Game/DiceOverlay.swift` (`diceLayout` returns `any Layout`; `DiceOverlayActionBarView` is a pass-through), `DieViewerView` (mutates the game item from a delayed Task in a leaf view); `Modules/PhotoRPG/View/CarouselPhotoItemView.swift:19-27` (allocates a selection model per parent re-init); `Modules/PhotoRPG/Root/ViewerRootView.swift:15-47` (three near-identical branches); `Modules/CoreRPG/Menu/ModuleCommands.swift` (zoom shortcuts "+"/"-" do not fire where "+" needs Shift)
- **Action:** Conditional content; move the rotation reset into the dice controller; merge branches.
- **Severity:** Low

## 9. Dead code / duplication / refactor

### 9.1 Four drifted copies of the drop-area views
- **Location:** `Modules/{Adventure,Character,Dice,Photo}RPG/View/DropChooseView.swift` (76/76/71/67 lines), `EmptyDropButton.swift` (50/50/51/48), plus `PhotoDropSection.swift`/`DiceDropSection.swift` in Adventure and Character
- **What:** Listed in CODE_AUDIT_22/23 as "do now (4 exact copies)"; they are no longer identical (constants and padding diverged).
- **Why:** A hit-area or contrast fix applied to one module misses the others.
- **Action:** One CoreRPG generic view parameterised by module and drop handler.
- **Severity:** Medium (verified by reading)

### 9.2 Per-module master message boilerplate
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:39-49`, `+DiceMessages.swift:28-29`, `+TableMessages.swift:22-23`, `+WeatherMessages.swift:23`, plus Photo/Pdf/Space (already unified via `FileBackedModuleAccess`)
- **Why:** The §6.1 authorization fix has to be applied in 4–7 places and one is easily missed.
- **Action:** One shared "answer asset request" entry point with a module-specific check closure.
- **Severity:** Low (verified)

### 9.3 Dead code in the vendored Navigator and nearby views
- **Location:** `Modules/CoreRPG/Navigator/Protocols/NavigationViewRouting.swift:1-61` (+ `Route/KnownRoutes.swift:47` `EnvironmentValues.router`, which silently defaults to a mock that drops every route); unused members `Navigator.childNavigators`, `nameOrId`, `parentNavigator`, `rootNavigator` (`Navigator/Core/Navigator.swift:191, 306-326`), `navigationAutoDestinationMode` (`Core/AnyNavigationDestination.swift:127`), `navigationDestinationAutoReceive` (`Core/NavigationDestination.swift:201`), `navigationProviders` (`Navigator.swift:125`), `recursiveFindParent` (`Core/NavigationFind.swift:36`); `sceneTracker(onOpen:onDismiss:)` callbacks; `EntryDataEditable.remove(itemId:entryIndexSet:)` (`ItemList/EntryDataEditable.swift:216-220`, would index `item.entries` with visible-list indices); unused `@Environment(\.dismiss)` in `LGViewModifiers/ToolbarItemListViewModifier.swift:20`
- **What:** Single-reference symbols (whole-repo word count of 1). CODE_AUDIT_26 §9.16 is listed fixed but these survived.
- **Action:** Delete the listed symbols.
- **Severity:** Low (verified)

### 9.4 Dead flags that look like behaviour
- **Location:** `Modules/GameRPG/Search/GlobalSearchModel.swift:30` + `SearchGlobalController.swift:61` (`playerMode` is never set true, so the branch hiding Adventure/Map/Weather results from players never runs); `Modules/GameRPG/Statistics/Model/GameStatisticsTypes.swift:48-64` (`.connectionFailed`, `.participantJoined`, `.participantLeft` never produced; raw values persisted); `GameCenterAchievementEvaluator` (`loyalHero` and `hundredHourClub` share the same 100 h goal)
- **Why:** `playerMode` looks like a privacy gate that is not wired; a future change relying on it would silently not work.
- **Action:** Wire `playerMode` from `gameType` or delete it; mark persisted unused cases as reserved.
- **Severity:** Low (verified)

### 9.5 Other dead code and stale comments
- **Location:** `Modules/CoreRPG/Sheet/SheetEntryConvertToGroupView.swift:29-33, 103-130` (`alreadyGroup` step never assigned, hard-coded placeholder text); `Modules/WeatherRPG/Weather/StormDrop.swift:20, 39, 46` (`rotationSpeed` never advances); `Modules/SpaceRPG/Record/AppDataModel.swift:452` (`loadShots()` of the dead snapshot gallery, already CODE_AUDIT_Space §9.2); `Modules/GameRPG/Table3D/GameTableView+PlatformFlat.swift:382-386` (misplaced doc comment merges two doc blocks)
- **Action:** Delete or finish.
- **Severity:** Low (verified)

### 9.6 Duplicated constants and logic
- **Location:** needle geometry literals (88/22/110) in `Modules/MapRPG/Map/MapEditorOverlayLayer.swift:224-229, 285` and `NeedleMapPin.swift:22`; `Modules/CoreRPG/ViewModifiers/LinkDragViewModifier.swift:29-130` (11-way module switch repeated four times, CODE_AUDIT_26 §9.23); compendium decoding re-implements the LevelDB merger (§5.29)
- **Action:** Named needle metrics next to `NeedleMapPin`; one shared dispatch.
- **Severity:** Low

## 10. Cross-cutting recommendations

1. **Fixes that land on one sibling and not its twins.** This audit found it five times: `TextDoubleEditor` fixed, `TextIntEditor` not (§7.9); `CachePhotoView` token vs `ThumbnailRowPhotoView` (§3.2); `PdfModel.isSame` by id vs Audio/Photo positional (§5.31); Map-only asset authorization vs seven other modules (§6.1); `AdventureEntity` vs Dice/Character `nonisolated(unsafe)` (§3.7). When closing an audit item, grep for the sibling pattern in all modules, or move the logic into the shared generic (as `FileBackedModuleAccess` already does for Photo/Pdf/Space).
2. **"Fixed" items need a regression test or they rot.** §5.5 (cycle guard) and §5.2 (group tags) are marked fixed in earlier audits but the fix does not cover real data; §5.4 (`mapAdventure`) and §5.1 (redo) have no test at all. Add one failing-input test per closed Critical/High.
3. **Persisted text and order must be locale-independent.** Foundry mapper stored text (§5.15), `localizedCompare` in Character repair (§5.22), import sort (§5.22), plus the `Dictionary` iteration-order ties in statistics. Rule: anything written to Core Data or CloudKit uses fixed-locale formatting and a deterministic tiebreak; locale formatting only for display. Cross-device idempotence is the product's central invariant.
4. **Authorize by session state, not by existence.** Receive-side checks for pins (§6.3), asset requests and player shows (§6.1) should reuse the same predicates as the send-side redaction instead of re-deriving weaker ones.
5. **Orders of async work.** Several bugs are two writers racing without a queue or generation token (§5.6, §3.1, §3.3, §5.12). Adopt the cancel-then-replace/ordered-chain pattern from CLAUDE.md for every GM-originated broadcast and every "latest wins" task.
6. **Optional-dependency traps.** `preconditionFailure` on unwired root managers (§5.33) and force unwraps (§4.1) should become guarded no-ops with a log, given App Intents/Spotlight can launch a module before `setUp`.

## 11. What was NOT audited

- **Excluded by design:** `Tests/` (113k LOC), `Snapshots/`, `#Preview` bodies and preview fixtures (`Fake*`, `PreviewData`, `MockData`; compiled into Release, known CODE_AUDIT_26 §9.31), third-party packages, Xcode project/scheme/build settings beyond reading the entitlements and Info plists, localization wording, Metal (none in repo), runtime profiling.
- **Not compiled:** only the iOS `MasterRPG` scheme was built (clean, zero warnings). macOS, tvOS and visionOS targets were read for `#if os` correctness but not built; visionOS-only TabletopKit code was not run.
- **Nothing was run or verified at runtime** (no tests, no simulator, no device). Every finding is from reading; confidence is stated per finding.
- **Coverage per scope** (agents read most but not all files; unread files are the audit's main residual risk):
  - GameRPG network/controllers: ~12k of 16.5k LOC; not read: tail of `MasterController+AudioMessages.swift` (after ~330 lines), `JoinCodeStorage.swift`, `ListenerRestartScheduler.swift`.
  - GameRPG Table3D/BattleRound/GameViews: ~16k of 19.5k; not read: dice mesh/geometry helpers (`TableDie10/12/20/8*`), several small BattleRound leaf views; `GameTableView+VisionOS.swift`, `+PlatformFlat.swift` and `GameTableModel.swift` not re-verified after a context reset.
  - GameRPG misc (Statistics, Root, Setup, Browser, Search, Intent, GameCenter, ExternalScreen, TablePlayers, QuickDice): ~11.5k of ~12k; `Preview/` skipped.
  - MapRPG: ~13k of ~21k; gesture/canvas files (`MapEditorCanvas*.swift`, `MapRoomCanvas.swift`, `MapOverlayGeometry*`, `MapPencilStroke*`) read partly; Apple Pencil on iOS 27 unverified.
  - CoreRPG data layer: ~19k of ~28k; partly read or skimmed: `CloudFolderScan.swift`, `FileVersionGameControllable.swift`, `ItemControllable+GamePersistence.swift`, `EditControllable+Folders.swift`, `FolderListControllable*`, `TagController`, `ExternalImportReviewSession*`, `Simple/*`, `LinkRenderer/*`, `FolderListModel.swift`.
  - CoreRPG Foundry/Sheet/Intent/Menu/Route: ~12.5k of 15.5k; not read: small `SheetEntry*Button` files, `Review*` views, `FoundryRuleModels.swift` from line 850.
  - CoreRPG UI: ~14k of ~24k LOC read in full (95 of 213 files), the rest grepped; skimmed: ~40 `FileViews` import-review views, Tips extensions, `AppThemeCatalog`, most of `Inspector/` pickers, `Buttons/`, `Editors/` small editors.
  - Character/Dice/Adventure/DiceRollerWidget: ~14.5k of ~21k; not read: Dice list/editor views, most Character sheet/entry views and routes, Adventure views other than the sheet and drop views. No Live Activity code exists in scope.
  - Audio/Pdf/Photo/Space: ~14k of ~25k; skimmed: Audio player bar/volume/route views, `PdfRootModel`, summary views, Photo viewport/canvas/intent files, `SpaceModel.swift`, second half of `SpaceViewerSubviews.swift`, Space onboarding/tutorial views, all module `Intent/*`.
  - Table/Weather/Rule/Generator: ~13k of ~23k; skimmed: Table views other than the generation panel, Route/Menu, entity/query intents, Weather editors and `WeatherSpace*`, Rule views other than the quick editor, remaining Generator views, `GeneratorModel/DataController`.
  - RolePlayGameKit + Sources + Resources: ~12.9k of 12.9k plus plists/entitlements; `Sources/DiceRollerWidget` read only for plist/entitlements here (covered by the Character/Dice scope).
- **Specific questions left open:** whether `Entity(contentsOf:)` materialises an iCloud placeholder (§5.10); whether the signed Mac build carries the bookmark entitlement (§6.9); whether the player-stats ordering race of §5.11 is reachable in practice; the PCC cloud path was found gated off in every shipping target and was not exercised.
- Suggested follow-up: a second pass limited to the "skimmed or not read" lists above, starting with the CoreRPG UI import-review views, the CoreRPG data layer's folder/file controllers, and the Character sheet/entry views.

## 12. Verification

Re-opened by the lead (Critical: none exist; all four High, one security Medium and two Mediums checked):

- **§5.1** — `Modules/CoreRPG/App/UndoManaged.swift`, lines 8-57: `value` is assigned only in `init`, `resetValue` (18-24), `updateValue` (26-28) and by `undo()`/`redo()` themselves (37-57). `undo()` moves `value` onto `redoStack` (39-41). `Modules/CoreRPG/Controllable/EditControllable.swift:452` (`saveChanges`) calls `previousValue(...)` and never `updateValue`. `updateValue` has only two other callers, `EditControllable+Undo.swift:25, 36`, both inside the library-scoped branch. Repo grep for `undoManaged.updateValue|resetValue` shows `resetValue` only at `EditControllable.swift:428, 478`. Trace: select V0; save A (undoStack [V0]); save B (undoStack [V0, A], value V0); undo → value A, redoStack [V0]; redo → value V0. No test in `Tests/` references `undoManaged`.
- **§5.2** — `Modules/CoreRPG/LGViews/GroupEditorController.swift:79-92`: when `tagsIsDifferent`, `sharedTags` is `[]` (line 91); `:102` `tagsChanged = model.tags != model.originalTags`; `:117-118` `reset(tags: model.tags, itemId:, forceSave: true)` for every id; `EditControllable.swift:158-167` is a full replace (per agent, signature confirmed by the call).
- **§5.3** — `Modules/TableRPG/Controller/TableGenerationController.swift:253`: `if occurrence.tableType == .dice, …`; repo grep of `tableType` outside tests shows the only write at `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Documents.swift:398` (plus decode/persistence plumbing in `TableRPG/Controller/DataController.swift:29, 46` and the fixed `.list` default at `TableGenerationController.swift:48`).
- **§5.4** — `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Documents.swift:489-515` iterates `mappingReferences[child.id]` (`:502`); `FoundryVTTDomainMapper.swift:245` declares it `[String: Set<FoundryImportMappingReference>]`; `FoundryVTTDomainMapper+SharedHelpers.swift:59-70` — `add()` calls `recordMapping(sourceID:module:itemId:)` for every emitted model before the dedup guard, and `:92` inserts into the set.
- **§5.5** — `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Indexes.swift:277-296`: `visited = Set([folder.id])` (282), walk continues with `declarationsByID[current]?.parentID` (289); declarations keyed by `$0.id` (188); `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:791` sets `id: canonicalTopLevelID(...)` and `:794` `parentID: raw["folder"]?.foundryIdentifier` (raw id), so the lookup key never matches a declaration id.
- **§5.9** — `Modules/PdfRPG/Intent/PdfEntity+Image.swift:13-17` reads `cacheController?.photo(for:)`; `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:46` default `createImage` is empty and `:48-57` `photo(for:)` returns only the memory cache; repo grep for `createImage` in `PdfRPG`/`SpaceRPG` returns nothing.
- **§6.1** — `Modules/GameRPG/Controller/MasterController+FileMessageSupport.swift:66-71` (asset request → `answerAssetRequest`), `:94-110` (`answerAssetRequest` checks only `hasLocalFileData`, then returns the cached package), `:128-146` (`showPlayerContribution` calls `share(id:)` for any id that exists locally); contrast `Docu/CODE_AUDIT_26.md:615` (§5.82 restricted to Map only).

Findings not re-opened by the lead are marked with the agent's own confidence ("verified by reading", "likely", "speculative") in each entry; none of them is rated Critical or High.
