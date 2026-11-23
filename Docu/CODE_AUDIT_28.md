# Code Audit — MasterRPG (2026-11-21)

Snapshot of `develop` at `345a83273` (clean tree). Read-only audit of every target under `Modules/` (15 modules) and `Sources/` (MasterRPG, MasterTV, RPGShare, DiceRollerWidget): about 224k Swift lines in about 2,000 files, excluding `Tests/` and `Snapshots/`. 15 scopes, each read by one agent against one shared brief, at most 3 agents in parallel. A clean iOS build (`MasterRPG` scheme, iOS Simulator, Xcode 27.2) succeeded with **zero Swift compiler warnings** (only two AppIntents metadata notices), so no finding is derived from compiler output. The concurrency and API-modernity findings come from reading the code.

The previous report (audit 27, 2026-11-20) was copied unchanged to `Docu/CODE_AUDIT_27.md` before this file replaced it. Findings that an earlier audit already listed are marked "Known: <audit> §<n>"; each was re-checked in today's code and is still present. Items that earlier audits fixed are not repeated.

**Overall verdict:** 0 Critical, 1 High, 52 Medium, and about 115 individual Low items folded into 17 grouped Low findings. The code base has been audited about 27 times and it shows: the transport/pipeline code (§3 scope S05), the GM-only data defences (hidden rooms, pin visibility, external screen, player export audience, `libraryWriteFilter`) and the concurrency boundaries were traced again by several agents and held. The remaining risk sits in three places:

1. **Seams between a fix and its siblings** — a fix landed in one module or one path but not the twin (undo/redo skipping what `saveChanges` does §5.3, CRDT decode fallback fixed only for table players §5.4, collection duplicates fixed only in the row id §5.2, Foundry text neutralisation done in the factory but undone by the mapper §6.2).
2. **Hostile or odd imported data** (Foundry / UniversalVTT packages, shared items): one path-resolution hole (§6.1), two import-freeze/crash shapes (§6.3, §6.4), live links in imported text (§6.2).
3. **Features that are one level off the main path** — the Siri "Start Adventure Game" intent (§5.1, the only High), the GM "preview as player" lens, statistics/Game Center, SharePlay audio route changes.

**Confidence note:** nothing in this audit was run on a device. Each finding states Verified / Likely / Unverified. The one High and six other findings were re-opened by the lead (see §12); everything else is the scope agent's finding with its stated confidence.

## 1. Executive summary

1. **[High] Siri / Shortcuts "Start Adventure Game" puts every module into game mode without starting a game and ignores the chosen adventure; later edits go to game memory only and are lost at relaunch** — §5.1 — `Modules/AdventureRPG/Intent/StartAdventureGameIntent.swift:33-37`
2. **[Medium, security] An imported `.local` file reference resolves to any absolute path in the app sandbox, and in game mode the bytes are sent to players** — §6.1 — `Modules/CoreRPG/Files/FileUrl.swift:193-222`, `LocationFileManager.swift:76-86`
3. **[Medium, security] Foundry text neutralisation in the rule factory is undone by the mapper, so link syntax in imported text becomes live links (regression of audit 22 §6.5)** — §6.2 — `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Rules.swift:167-215`
4. **[Medium] A hostile Foundry package can freeze the import for minutes (quadratic tag regex on the main actor) or crash it (unbounded dotted-path recursion)** — §6.3, §6.4 — `Modules/CoreRPG/Foundry/FoundryTextDecoder.swift:42-56`, `FoundryValueHierarchy.swift:75-118`
5. **[Medium] An undecodable stored CRDT register is replaced by a default stamped "now" and wins the next merge on every device (mixed app versions under CloudKit)** — §5.4 — `Modules/CoreRPG/CRDT/CRDT.swift:25-27, 61-66`
6. **[Medium] A collection that lists a member twice is persisted as two rows with one uuid and loses one on the next save** — §5.2 — `Modules/CoreRPG/Persistence/CoreDataRelationship.swift:21-53`
7. **[Medium] Undo/redo skip the link register and tag counts** — §5.3 — `Modules/CoreRPG/Controllable/EditControllable+Undo.swift:56-64`
8. **[Medium] Pins added without a location are drawn in the first (possibly hidden) room but judged by their raw location for player visibility, redaction, photo sharing and battle membership** — §5.6 — `Modules/MapRPG/Map/MapPinPlacement.swift:20-28`, `GameController+Pins.swift:566-580`
9. **[Medium] The observable full-image cache is bounded by count (120), not bytes, and pins of 160 pt or more decode full bitmaps; no memory-warning handling exists** — §7.1 — `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:259-316`
10. **[Medium] Foundation Models error handling matches only the deprecated `GenerationError`; iOS 27 throws `LanguageModelError`, so the tailored messages are dead** — §4.1 — `Modules/GeneratorRPG/BasicAI/Errors/FoundationModelsError.swift:6-104`

Counts: Critical 0 · High 1 · Medium 52 · Low 17 grouped findings (about 115 items).

## 2. Quick wins (≤ 30 min each)

- §5.12 Give Weather another shortcut (Cmd-0 is also the map editor's "Fit to Window").
- §5.13 Gate Cmd-Delete "Delete item" on list focus like Space and Return.
- §5.21 Make `FoundryImportView`'s load a no-op unless the state is `.notStarted`.
- §5.18 Route the audio detail toolbar Play button through the game like every other play entry point.
- §5.15 Call the pin sync after the fog task in the GM preview-lens `didSet`.
- §5.5 Drop the queued deletion in the failure branch of `ItemControllable.delete`.
- §5.9 Treat empty content as "keep the current type" in `termineType`.
- §5.19 Add Adventure `diceId` to the link register diff.
- §6.1 Relocate every `.local` import reference that has no `Documents` component.
- §8.2 Pass the module bundle for the Rule entry-kind titles and source-metadata labels.
- §9.1, §9.2, §9.3 Delete the unreachable visionOS 2D game-screen code, the unreachable `OverlayGameMenu` variants and the dead PDF-selection plumbing (about 700 lines).
- §3.1 Store and cancel the handshake/dial deadline tasks (fixed 2026-11-22).

## 3. Concurrency

### 3.1 Handshake and dial deadline tasks are fire-and-forget
- **Location:** `Modules/GameRPG/Master/MasterNetworkController+Listener.swift:87-95`, `Modules/GameRPG/Master/MasterNetworkController+Browser.swift:121-129`
- **What:** `enforceHandshakeDeadline` and `enforceDialDeadline` start an unstructured `Task` that sleeps 15 s and is never stored or cancelled; after the weak self is resolved it holds the controller for the whole sleep.
- **Why:** Under connection churn every attempt leaves a sleeping task; they are unbounded in number and do not stop on `stopStreaming`. The guards re-check state, so correctness holds.
- **Action:** Keep the tasks in a dictionary keyed by connection id, cancel on authenticate/remove/stop, clear in the hosting teardown.
- **Severity:** Medium
- **Status 2026-11-22:** fixed. `deadlineTasks` per connection id; cancelled on authenticate (`readyConnection`), `removeConnection` and `resetConnections`. Test: `MasterNetworkControllerTests.handshakeDeadlineTaskIsCancelledWithConnection`.
- **Known:** audit 27 §3.5 (deadline part), still open.

### 3.2 Audio route-change pause and interruption auto-resume act on the coordinated player, so under SharePlay they affect the whole group
- **Location:** `Modules/AudioRPG/Controller/AudioPlayerSession.swift:228-241, 254-263`, `Modules/AudioRPG/Controller/AudioController.swift:363-367, 384-390`, coordinator wiring `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:319-323`
- **What:** An `oldDeviceUnavailable` route change calls `pause()` and an interruption that ends with `.shouldResume` calls `play()` directly on the local `AVPlayer`. In a SharePlay game both master and players have the playback coordinator attached, so a participant's local transport action is sent to the group.
- **Why:** One player's Bluetooth headset disconnecting pauses the music for the GM and everyone; after a phone call the auto-resume restarts music the GM had paused. LAN play behaves correctly, so it is easy to miss in testing.
- **Action:** In a running game on a player/observer device, suspend or mute locally instead of using the coordinated transport, or route the pause through the game. Verify on two devices in a SharePlay session.
- **Severity:** Medium (Likely; AVPlayerPlaybackCoordinator propagation not tested on device)
- **Status 2026-11-22:** fixed in code, not verified on two devices. With other SharePlay participants (`AudioPlayerModel.isPlaybackShared`) a route change mutes locally (`volume = 0`) instead of pausing, an interruption does not pause explicitly, and its end does not call `play()`. Unverified: that the playback coordinator rejoins a suspended device by itself; no automatic unmute when the route returns. Test: `AudioControllerTests.routeChangesAndInterruptionsStayLocalInSharedPlayback`.

### 3.3 The whole Foundry mapping pass runs on the main actor
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift:179-200, 265-271, 339-346`, `UniversalVTTDomainMapper.swift:10-19`, per-item work in `FoundryVTTDomainMapper+Documents.swift`, `+SharedHelpers.swift:303-335`
- **What:** `FoundryMappingState` is `@MainActor`; the only relief is `Task.yield()` every 16 work units. The doc comment cites "CODE_AUDIT.md §3.7", an unrelated finding.
- **Why:** A package with tens of thousands of documents does regex link rewriting, HTML sanitising, id hashing and index building on the UI thread during "Preparing import review"; total main-thread time is large and animation stutters.
- **Action:** Keep model construction on the main actor but move the pure parts (text sanitising, id derivation, value-hierarchy flattening, alias indexing) into a nonisolated pre-pass; fix the stale comment.
- **Severity:** Medium (Likely)
- **Status 2026-11-22:** partly fixed. `FoundryTextPrepass` converts the document and rule description HTML to plain text off the main actor (`@concurrent`) before the models are built; the stale comment is fixed. Still on the main actor: link rewriting (needs the destinations indexed during mapping), id hashing, value-hierarchy flattening and model construction; rule-entry text only exists after the factory built the models. Not measured on a large package.

### 3.4 Unowned fire-and-forget tasks (grouped)
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:421-465` (message loop awaits `handleUpdate` inline, Known audit 27 §3.4); `Modules/MapRPG/Root/MapRootModel.swift:36-46` (content-send chain never cancelled); `Modules/MapRPG/Controller/EditController.swift:310-314`, `MapEditorCanvasGestures.swift:214-218`; `Modules/CoreRPG/Sheet/SheetEntryAddGroupButton.swift:14-22`, `SheetEntryConvertToGroupView.swift:103, 118`, `LGViews/GameShareView.swift:156-171`, `LGViews/FileImporterView.swift:59, 153` (button `Task {}` allows double-fire); `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:131-184` (flush tasks pile up while a save is slow), `GameCenter/GameCenterController.swift:131-146` (overlapping achievement reports, Known §3.6); `Modules/SpaceRPG/Record/AppDataModel.swift:103, 452`, `Space/SpaceViewer+Handoff.swift:70-85`, `Modules/PdfRPG/Pdf/PdfWrapperView.swift:68-71`; `Modules/GameRPG/Root/GameRoot.swift:352-367` (one hung operation blocks the serial network-action chain, partly Known)
- **What:** Unstructured tasks with no stored handle or cancellation, or buttons that start a task without a re-entry guard.
- **Why:** Rare double actions and unbounded task buildup under slow I/O; none is a data race.
- **Action:** Store the handle where a second start is possible (as the sibling Summary views already do), cancel on teardown, add a timeout to the serial action chain.
- **Severity:** Low
- **Status 2026-11-22:** partly fixed. Fixed: map content-send chain cancelled with the game (`cancelMapContentSends`, called from `GameRoot.cancelOwnedTasks`); one full-buffer statistics flush task at a time; Game Center reports serialized; re-entry guards on `SheetEntryAddGroupButton` and `GameShareView.shareAction`. Not changed on purpose: the SharePlay message loop (inline `handleUpdate` keeps the message order, Known 27 §3.4); `EditController` thumbnail invalidation (documented as intentional); `SheetEntryConvertToGroupView` (already guarded by `isConverting`); `FileImporterView` (picker and alert close on the first tap); `AppDataModel`, `SpaceViewer+Handoff`, `PdfWrapperView` (harmless); a timeout on the `GameRoot` action chain (a hung `@MainActor` operation cannot be timed out; the chain is cancelled with the game).

### 3.5 Redundant `Sendable` conformances and `async` functions that never suspend (grouped)
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:104-108`, `PlayerController.swift:57-61`, `Player/PlayerNetworkModel.swift:11-15`, `Master/MasterNetworkModel.swift:11-16`; `Modules/GameRPG/Controller/PlayerController+Character.swift:14-16`, `PlayerController+Proxy.swift:57-59`; `Modules/GameRPG/Network/GameNetworkController+MasterDelegate.swift:30-36` (acceptance check runs twice per LAN message)
- **What:** `@MainActor` classes carry explicit `Sendable`; some `async` funcs only call synchronous code.
- **Why:** Noise, extra hops, a duplicated check per message.
- **Action:** Drop the redundant conformances and `async`; run the acceptance check once.
- **Severity:** Low
- **Status 2026-11-22:** partly fixed, and the finding was partly wrong. **Do not remove or move the `extension MasterController: MasterNetworkStoreDelegate {}` and `extension PlayerController: PlayerNetworkStoreDelegate {}` in `MasterController.swift` / `PlayerController.swift`.** They are not redundant `Sendable` declarations: the class gets `Sendable` through the protocol, and Swift requires that conformance in the class's own file (moving it compiles but warns "Conformance to 'Sendable' must occur in the same source file", an error in a future language mode). The `Sendable & AnyObject` on `MasterNetworkControllerDelegate`/`PlayerNetworkControllerDelegate`/`MasterNetworkControllable`/`PlayerNetworkControllable` is also needed (the build fails without it: non-Sendable existential leaves the main actor). Fixed: `scheduleSendCharacter` and `scheduleProxyFocus` are no longer `async`; the acceptance check runs once per LAN/SharePlay message (`receivedAccepted`; `received` still checks first for other callers).

## 4. API modernity

### 4.1 Foundation Models error handling matches only the deprecated `GenerationError`
- **Location:** `Modules/GeneratorRPG/BasicAI/Errors/FoundationModelsError.swift:6-104`, `BasicAI/Providers/PdfSummaryAnalyzer.swift:100-108`, `TableSummaryAnalyzer.swift:46-56`, `PdfContentExtractor.swift:~140-150`, `Controller/GeneratorController.swift:~214-225, ~335-355`, `Intent/RunGeneratorIntent.swift:~67-70`
- **What:** The iOS 27 SDK marks `LanguageModelSession.GenerationError` deprecated and adds `LanguageModelError` (context size exceeded, rate limited, guardrail violation, refusal, unsupported language, timeout). `ConversationEngine` and `PhotoAnalysisFallbackPolicy` already match the new type; the error handler and every catch site above match only the old one.
- **Why:** On iOS 27 the tailored messages are dead; users see the raw description or "Unexpected error", and `RunGeneratorIntent` lets the error escape as an intent failure instead of the spoken dialog. No deprecation warning shows because the deployment target is 26.
- **Action:** Add a `LanguageModelError` overload under an iOS 27 availability check, route every catch site through one `handle(any Error)` helper, extend the intent.
- **Severity:** Medium (the new type is present in the iOS 27.2 SDK interface, verified by the lead; which type the runtime throws per call was not exercised)

### 4.2 Global `UINavigationController` override and gesture-delegate hijack
- **Location:** `Modules/CoreRPG/Extensions/NavigationController+Back.swift:6-31`
- **What:** An extension overrides `viewDidLoad` of every `UINavigationController` in the process (no defined precedence against the class's own) and makes simultaneous-recognition delegate methods return true once the stack has more than one controller.
- **Why:** It reaches system-owned and sheet navigation controllers and can change gesture winners against horizontal scroll views and swipe actions; it can break silently with an OS update.
- **Action:** Re-test swipe-back with a hidden navigation bar on iOS 26/27; if still needed, scope it to a representable's own navigation controller, otherwise delete it.
- **Severity:** Medium
- **Known:** audit 26 §4.6, still open.

### 4.3 Locale-dependent text handling (grouped)
- **Location:** `Modules/CoreRPG/ViewModifiers/NumericViewModifier.swift:17-35` with `Editors/TextDoubleEditor.swift:116`, `TextIntEditor.swift:49, 53` (the numeric filter strips Arabic digits and the Swedish U+2212 minus that the editors' own formatting produces); `Modules/CoreRPG/Editors/AddTagsEditor.swift:82`, `Model/TagFilterList.swift:24, 26` (locale-dependent uppercase, "WİZARD" under Turkish); `Modules/CoreRPG/Files/CloudDocumentController.swift:236-269` (a real name ending in "-N" is read as a de-duplication counter)
- **What:** Filters and normalisation assume ASCII digits and the current locale's casing.
- **Why:** Wrong or lost input and non-matching tags for users in several locales.
- **Action:** Parse with the locale's number format style, use invariant casing for tag keys, mark generated suffixes unambiguously.
- **Severity:** Low

### 4.4 Configuration and modernisation leftovers (grouped)
- **Location:** `Sources/DiceRollerWidget/ContentWidgets.swift:29-46` (closure-based `TimelineProvider`); `Sources/MasterRPG/iOS/iOSAppDelegate.swift:6`, `iOSSceneDelegate.swift` (`@Observable` on delegates); `Resources/Info.plist`, `Resources/InfoTV.plist` (`NSAllowsArbitraryLoads=false` is the default); unused camera/photo usage strings on MasterTV and MasterMac and unused extension entitlements (project build settings); naming `ID`/`URL` against CLAUDE.md in `Modules/CoreRPG/Settings/Theme*.swift`
- **What:** Placebo or unused entries and older patterns.
- **Why:** Review-surface noise; the unused camera/photo strings can draw App Review questions.
- **Action:** Move the content widgets to `AppIntentTimelineProvider`/async provider, delete the placebo entries, remove unused usage strings and entitlements.
- **Severity:** Low

## 5. Bugs / logic errors

### 5.1 Siri "Start Adventure Game" enters game mode everywhere without starting a game
- **Location:** `Modules/AdventureRPG/Intent/StartAdventureGameIntent.swift:33-37`, `Modules/AdventureRPG/Root/AdventureRootModel.swift:339-344`, `Modules/AdventureRPG/Controller/GameController.swift:66-69`, compare `Modules/GameRPG/Root/GameRoot+Master.swift:23-75`
- **What:** The intent calls the adventure's `startGame(with:)` (focus the item, put Map into master mode) and then `root.startGame()`, which sets `isGameMode` on the Adventure root and all ten sibling roots, then navigates to the Game tab. It never goes through `GameRoot`'s master start, so there is no game config, network or master controller, and the selected adventure is not set. `root.startGame()` has only three callers: `GameRoot+Master`, `GameRoot+Player` and this intent.
- **Why:** `isGameMode` stays true until a game is started and stopped; `ItemControllable.replace` then routes non-`forceSave` edits to game memory only, so a GM who triggers the intent and edits without tapping Start loses those edits at relaunch. Map is left streaming in master mode with no game, and the chosen target is ignored.
- **Action:** Make the intent only select the adventure and open the Game tab, or have it call the same start path as the Start button. Do not call module game-mode setters from outside the game root. Add a test that `isGameMode` is false after the intent when no game started.
- **Severity:** High (Verified by reading the call chain; not run on device)

### 5.2 Collection entries with an equal id are persisted as two rows with one uuid, then one is dropped
- **Location:** `Modules/CoreRPG/Persistence/CoreDataRelationship.swift:21-53`, `Modules/CoreRPG/Controllable/EditControllable+Folders.swift:63-85`, DataControllers with `childId: { $0.id }` in Adventure (`DataController.swift:53-58`), Character, Rule, Pdf, Map, Table, Dice
- **What:** A collection may list one member several times (product decision). In seven modules the entry id equals the member id, so a second add yields two entries with one id; `syncEntries` looks existing children up only in the pre-load rows, so both create a row, and the next save matches both to the first and deletes the second.
- **Why:** The "listed twice" state exists in memory and the CRDT value but is not durable; after relaunch the collection lists the member once, and CloudKit carries two rows with one uuid in between.
- **Action:** Look up already-created children inside the loop (accepting that duplicates collapse), or give entries their own id in those seven modules as Photo/Audio/Space already do, or reject the second add. Decide with the user; add a save/reload regression test.
- **Severity:** Medium (Likely)
- **Known:** Docu/CODE_AUDIT_Folder.md §5.17 (marked Fixed, but only the row-id part).
- **Status 2026-11-22:** fixed for new adds: `EditControllable.addItem` rejects a second add of the same member to a collection (user decision). A duplicate that arrives by sync or an old file is still handled by row id; the Core Data relationship mapping (`CoreDataRelationship.swift`) was not changed. Tests: `CollectionDuplicateMemberTests`; `FolderOperationAuditTests.collectionMembersByRowId` now builds its duplicate directly.

### 5.3 Undo and redo skip the side effects of `saveChanges`
- **Location:** `Modules/CoreRPG/Controllable/EditControllable+Undo.swift:56-64`, versus `EditControllable.swift:447-464` (`saveChanges`) and `:168-177`, `EditControllable+Delete.swift:222-231, 242-298`
- **What:** `saveChanges` re-derives the link register and adjusts tag counts; `undo()`/`redo()` restore a stored model through `replace` which does neither.
- **Why:** Add a link then undo: "used by" and the delete-impact panel still list the removed link. Trash an item then undo: it is visible again but its tags no longer count and drop out of suggestions. The error survives until Validate & Repair or relaunch.
- **Action:** Route the restored value through the same register-diff and tag-count step as `saveChanges` (extract it so the two cannot drift). Test add-link/add-tag, undo, check register and counts.
- **Severity:** Medium (Verified: both paths read, no other register update on the undo path)
- **Status 2026-11-22:** fixed. `applyUndoValue` now runs `updateLinkRegister(to:)` and the new `updateTagCounts(to:)` (a trashed item counts no tags), the same pieces `saveChanges` uses. Test: `UndoSideEffectsTests` (red before).

### 5.4 An unreadable stored CRDT register becomes a default stamped "now" and wins the next merge
- **Location:** `Modules/CoreRPG/CRDT/CRDT.swift:25-27, 61-66`; about 113 call sites, e.g. `Modules/PdfRPG/Controller/DataController.swift:29-33`, `Modules/DiceRPG/Controller/DataController.swift:26-42`, `Modules/WeatherRPG/Controller/DataController.swift:26-27`
- **What:** When stored text does not decode as that register type, the wrapper invents one with the module default, a random actor id and the current time. The validating initializer exists but is used only for Adventure table players.
- **Why:** A register written by a newer build (for example a list category case unknown to an older build) is replaced by a default on the older device at its next save; CloudKit then carries the fresh timestamp to every device where it beats the real value. Mixed-version devices are normal under CloudKit.
- **Action:** At the DataController mapping boundary treat "non-empty but undecodable" as unreadable: keep the raw string and the epoch-stamped state, do not write it back, log once. Keep the legacy plain-text tag fallback as the migration path.
- **Severity:** Medium (Likely; cross-version scenario not reproduced)
- **Known:** audit 24 §5.9 (fixed only for table players).
- **Status 2026-11-22:** fixed. A string that is a serialized register but cannot be decoded as `T` becomes an epoch-stamped default (loses every merge) and keeps its raw text (`unreadableRawValue`), which `rawValue` writes back until the value is set again; plain legacy text keeps the old fallback. Test: `CRDTUnreadableRegisterTests` (red before).

### 5.5 A failed database delete leaves its deletion queued, so the next save removes the row the item was restored for
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:187-198`, `Modules/CoreRPG/Persistence/CoreDataController.swift:229-232, 261-304`
- **What:** The failure branch of `delete` restores the item in memory and withdraws the file deletion but does not call `removePendingOperations(for:)`; the flush puts the drained deletion back in the queue.
- **Why:** The UI shows the item kept, but the next `save()` deletes its row: orphan file, item missing after relaunch. Needs a failing flush (a store problem), so it is rare.
- **Action:** Drop the queued deletion for the id in the failure branch (and mirror it in `deleteForExternalImport`); test with a flush that throws.
- **Severity:** Medium (Likely)
- **Known:** audit 23 §5.6 fixed the file half only.
- **Status 2026-11-22:** fixed. The failed-delete branch and `deleteForExternalImport` call `removePendingOperations(for:)` before the model is restored. Test: `FailedDeleteQueuedDeletionTests` (red before).

### 5.6 Unplaced pins are drawn in the first room but judged by their raw location
- **Location:** `Modules/MapRPG/Map/MapPinPlacement.swift:20-28`, `Modules/MapRPG/Model/MapModel+Geometry.swift:48-53`, `MapSnapshot.swift:168`, `Controller/GameController+Sync.swift:44`, `GameController+Pins.swift:402, 428, 566-580`, `GameController+Battle.swift:31-34`, `Map/ChooseMapPinsButton.swift:80-114`
- **What:** A pin added from the game toolbar with no focused room keeps location zero. Both renderers draw it in the map's first entry, even a hidden one. The player filter, the redacted snapshot, photo prefetch, the "may share photo" rule and battle-start membership test the raw zero location. The 3D table filters after placement and is correct, so 2D and 3D disagree.
- **Why:** A monster the GM placed (visually) in an unrevealed first room is sent to players with name, portrait id and character link; the 2D player view hides it only through fog layering, and the shared-photo layer above fog can show it. Battle start skips pins that look like they are inside the room.
- **Action:** Resolve the display location once (or persist a real location when a pin is added in game mode) and use it in every rule.
- **Severity:** Medium (Likely: the display placement was read by the lead; the player-side rules were traced by the agent)
- **Status 2026-11-22:** fixed. `MapPinModel.isVisibleToPlayers` judges a pin at `.zero` by the first room; `MapModel.isPin(_:in:)` gives the same rule to battle membership (`battleStartPins`). Not changed: `ChooseMapPinsButton`. Two existing fixtures that relied on the old behaviour were updated (`ExportControllerTests.playerExportDataIsRedacted`, `MapMasterMessageFlowTests.proxyMapRepairRejectsMissingPinPhotoData`). Test: `UnplacedPinRoomTests`.

### 5.7 Save Game keeps battle-clone Character ids in the saved pins and mutates the live maps
- **Location:** `Modules/MapRPG/Controller/GameController+Metadata.swift:463-477` (`saveAll`) versus `:297-330` (library path restores source ids)
- **What:** `saveAll` strips only player pins and the shared-photo flag; monster pins still point at the runtime clone Character, and the live maps are mutated.
- **Why:** A saved game written during or after a battle links monsters to Characters that do not exist after loading; a cancelled save leaves the running game without its player/companion pins until the next roster sync.
- **Action:** Build the saved copy from the library-pin function on copies of the maps; share one function between library write and Save Game.
- **Severity:** Medium
- **Status 2026-11-22:** fixed. Save Game no longer mutates the live map: `ExportControllable.savedGameExportData(for:)` (new requirement, default nil) encodes a copy with library pins (`GameController.libraryPins`, `isPhotoShared = false`); `saveAll()` only exports. Tests: `GameControllerTests`, `PinPhotoShareAndPlacementTests` (`saveGameWritesLibraryPinsOnACopy`). The tests use the new API, so the red check was compile-level only.

### 5.8 Weather's linked photo is merged by a stamp a photo edit never moves
- **Location:** `Modules/WeatherRPG/Model/WeatherModel+Sync.swift:7-36`, `WeatherModel.swift:279-314`, `Controller/EditController.swift:36-40`
- **What:** The stamp moves only when a weather value changes; linking, changing or removing the photo does not, yet merge decides `photoId` by comparing stamps, local wins on equal.
- **Why:** Device A links a photo; device B keeps its old or nil value and can revert the link on its next save.
- **Action:** Make `photoId` its own register or include it in the stamp-moving comparison; add a photo-only merge test.
- **Severity:** Medium
- **Known:** audit 27 §5.21, still open.
- **Status 2026-11-22:** fixed. `WeatherModel.hasDifferentWeather` includes `photoId`, so a photo edit moves the stamp that `merge` decides the photo by. Test: `WeatherModelTests.linkingAPhotoWinsTheMergeOverADeviceThatKeptNoPhoto` (red before).

### 5.9 Blank text entries silently become number entries and show "= 0 Error"
- **Location:** `Modules/CharacterRPG/Controller/EditController.swift:301-327` (`update`, `termineType`), `EditController+InlineEditor.swift:144-146`, callers `Modules/CoreRPG/EntryEditor/EntryEditorHeaderView.swift:53-62, 88-97`, `CharacterRPG/View/CharacterAddEntryOverlay.swift:127-131`, `Intent/CharacterManagementIntents.swift:99-102`
- **What:** `termineType` returns `.number` when the content is empty or only whitespace and the current type is text (line 323). Clearing a text note, or creating an entry with no content, flips the type; the calculator then yields nil and the sheet appends "= 0 Error".
- **Why:** The type change is synced, invisible, and later prose stays in a number entry.
- **Action:** Treat empty content as "keep the current type"; give number entries an explicit "0" base on create; test blank save and blank create.
- **Severity:** Medium (Verified for the type flip; the "= 0 Error" display traced, not seen)
- **Status 2026-11-22:** fixed. `termineType` keeps the type for blank content (a quick entry without content is text). Test: `BlankEntryTypeTests` (red before).

### 5.10 Item or entry names with balanced square brackets generate links nothing recognises
- **Location:** `Modules/CoreRPG/ItemList/ItemDataAccessible.swift:139-153`, `ItemList/EntryDataEditable.swift:157`, `Inspector/InspectorRowView.swift:62-67, 110-115`, `Model/EditorLinkModel.swift:159`
- **What:** A name such as "Dragon [Ancient]" is interpolated raw into `[name](address)`. Neither the link builder pattern nor the reference scanner matches a bracketed label (probed by the agent). The Foundry importer escapes brackets, the manual, drag and picker paths do not.
- **Why:** The user sees raw markdown instead of a link chip, and the link is not registered, so usage tracking and deletion warnings do not apply.
- **Action:** Decide one grammar for bracketed names (sanitise at creation or accept escaped brackets in both patterns) and use a single builder entry point everywhere, including the Foundry mapper; add a round-trip test.
- **Severity:** Medium (Verified for the pattern behaviour; Likely end to end)
- **Status 2026-11-22:** fixed (user decision: escape at the builder). `LinkBuilder.markdown` escapes `\`, `[` and `]` through `escapedLabel`; `markdownLinkPattern`, the reference scanner and `LinkBuilder.labels` read the escapes back (`unescapedLabel`). `ItemDataAccessible.url(...)`, `ReferenceLink.markDown`, the intent text helper, the Quick Link relabel and the Foundry mapper (`markdownLink` no longer escapes itself) use the one entry point. Not changed: `EditorLinkModel`/`InspectorRowView` only read names. Tests: `BracketedLinkNameTests` (red before).

### 5.11 Link toggles act on the first occurrence when the same item appears twice in a sheet tree
- **Location:** `Modules/CoreRPG/Sheet/SheetRootModel+Links.swift:11-121`, keys built at `Sheet/SheetEntryRowViews.swift:189, 206, 268`, `Sheet/SheetView.swift:151, 236`
- **What:** Link text models are cached by item/entry id and their togglers search the tree depth-first for the first sheet with that id, though the model explicitly allows the same item in several branches.
- **Why:** Tapping a link inside the second copy expands or collapses the first copy (maybe off-screen) and both rows share one cached model, so the second looks dead.
- **Action:** Key the cache and togglers by occurrence id (`SheetModel.id`) and resolve the target by it.
- **Severity:** Medium (Likely)
- **Status 2026-11-22:** fixed. `LinkHighlightTextModelId` carries the `SheetModel.id` of the row it is shown in (`occurrence`); a link tap acts on that row (`toggleLink(in:)`); cache resets and cleanups go by source id and reach every occurrence. Tests: `SheetRootModelSelectionTests.linkTapActsOnTheOccurrenceItWasTappedIn` (red before), `cachedLinkTextOfEveryOccurrenceIsReset`.

### 5.12 Cmd-0 is bound twice: "Show Weather" and the map editor's "Fit to Window"
- **Location:** `Modules/CoreRPG/Menu/ModuleCommands.swift:30-32, 95-100`, `Menu/NavigateButton.swift:17`, `Modules/WeatherRPG/Menu/WeatherCommands.swift:20`
- **What:** Every module registers its navigate command unconditionally; Weather uses key "0"; the map's commands add the zoom reset on Cmd-0 while the editor is focused.
- **Why:** With the map editor focused two menu items own the shortcut; either Fit to Window does nothing or the app jumps to Weather.
- **Action:** Give Weather another key or move the zoom reset.
- **Severity:** Medium (Verified by reading both declarations; runtime pick not tested)
- **Status 2026-11-22:** fixed in code, menu pick not verified at runtime. "Fit to Window" moved to Command-Option-0 (`ModuleMenuPolicy`), Command-0 stays "Show Weather". Test: `ModuleMenuPolicyTests` (guards the two modifier sets).

### 5.13 Cmd-Delete "Delete item" is not gated by list focus
- **Location:** `Modules/CoreRPG/Menu/DeleteItemButton.swift:19-20`, `Menu/ModuleCommands.swift:58`
- **What:** Space and Return take `isListFocused`; Delete keeps its shortcut and is only disabled when nothing is selected.
- **Why:** On macOS and iPad with a keyboard, Cmd-Delete is also "delete to start of line"; with an item selected and the cursor in a detail text field the menu command runs first and opens the removal panel.
- **Action:** Disable unless the module list is focused, as `SpaceActionButton` does.
- **Severity:** Medium (Likely)
- **Status 2026-11-22:** fixed. `DeleteItemButton` is enabled only with a selection and the module list focused (`ModuleMenuPolicy.isDeleteEnabled`). Test: `ModuleMenuPolicyTests`.

### 5.14 `ScenesManager.openWindow` cannot raise an open window and has no way out of a stuck `.opening`
- **Location:** `Modules/CoreRPG/ScenesManager/ScenesManager.swift:230-244, 275-286`, `Menu/LinkWindowCommandView.swift:21-23`, `Menu/MenuWindowButtonView.swift:17-23`
- **What:** `.opening` is set before calling SwiftUI and only left on activation or end; a call in `.opening`/`.opened` only logs; there is no failure path or timeout.
- **Why:** The menu command does nothing for a window open behind others; a scene that never activates leaves the state stuck so later opens are ignored and the game menu shows the window as open until restart.
- **Action:** For single-instance scenes always forward to `openWindow(id:)`, guard only same-turn double calls, and clear `.opening` on a timeout or inactive phase.
- **Severity:** Medium (Likely)
- **Status 2026-11-22:** fixed. `openWindow(_:)` asks SwiftUI again for an `.opened` scene (raises it), ignores only a second call within `openingTimeout` (3 s) and asks again for a scene stuck in `.opening`. Not changed: the clearing of `.opening` on an inactive phase (no signal available). Tests: `ScenesManagerOpenWindowTests`. Not run on a device; multi-instance `WindowGroup` scenes opened without a selection would now open a further window while open (none found).

### 5.15 GM "preview as player" toggle does not re-sync the pin tokens
- **Location:** `Modules/GameRPG/Table3D/GameTableModel.swift:141-150`, `GameTableProjection.swift:249-262`, `GameTableModel+MapSync.swift:226-228`, toggle at `Modules/MapRPG/Map/GameToolBar.swift:99`
- **What:** `displayMode.didSet` re-renders the board texture only; the pin filter in `syncPawnsWithMapPins()` also reads the render role but nothing runs it when the mode flips.
- **Why:** After switching to the player lens the fog is the players' but hidden pins stay on the table until an unrelated sync, so the lens shows a mix of roles. Local to the GM device; nothing is leaked.
- **Action:** Call the pin sync after scheduling the fog task; add a test next to `GameTableControlTests.displayModeOutlivesTableModel`.
- **Severity:** Medium (Verified)
- **Status 2026-11-22:** fixed. `displayMode.didSet` runs `syncPawnsWithMapPins()` after scheduling the fog task. Test: `GameTableControlTests.playerLensRemovesHiddenPins` (red before).

### 5.16 SharePlay coordination wait silently skips when the scene is not attached yet
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+RenderingReadiness.swift:30-44`, caller `GameTableView+VisionOS.swift:181-184`
- **What:** `waitForFirstRenderedFrame()` returns immediately when the renderer root has no scene; the caller then joins SharePlay coordination, whose purpose is to join only after mount, because an early join crashes with "Could not find static equipment".
- **Why:** If the task wins the race against the RealityView `make`, the documented crash path reopens, intermittently.
- **Action:** Wait for the scene (bounded poll or a signal from `make`) before waiting for the frame; give up after a deadline with a log line.
- **Severity:** Medium (Unverified; ordering not proven)
- **Status 2026-11-22:** fixed in code, visionOS build verified, not run on a device. `waitForFirstRenderedFrame()` first waits up to 10 s for the renderer scene (`SceneAttachmentWait`), returns `false` otherwise and the caller then does not start SharePlay coordination (logged). Test: `SceneAttachmentWaitTests`.

### 5.17 Session duration has no upper bound; idle time and clock jumps become play time and irrevocable Game Center progress
- **Location:** `Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift:100-116`, `Modules/GameRPG/Root/GameRoot+Stop.swift:68-69`, consumers `GameStatisticsController.swift:108-134, 255-271`, `GameCenterController.swift:206-245`
- **What:** A normally stopped game is booked from start to stop; only orphan paths use last activity. There is no cap or idle clamp.
- **Why:** A game left open overnight or a wrong device clock yields a multi-day session, inflating play time and the 8-hour and 100-hour achievements, which are reported once and never lowered; `splitInterval` also loops per hour on the main actor.
- **Action:** Book a stop from the last activity or clamp the idle tail; cap the loop and the session length in the summary; decide a maximum that counts towards achievements.
- **Severity:** Medium (Likely)
- **Status 2026-11-22:** fixed (user decision). The stop's own checkpoint no longer counts as activity (`advancesActivity: false`), so `finishSession` books the end at the last activity when the idle tail exceeds 30 min; a session counts at most 12 h in the summary and achievements (`GameStatisticSessionSnapshot.capped`); `splitInterval` is bounded at 10 000 segments. Stored rows are not rewritten; existing multi-day sessions are only capped in the summary. Tests: `GameStatisticsDataControllerTests`, `GameStatisticsBucketingTests`. Achievements already reported are not lowered.

### 5.18 Audio detail toolbar "Play" plays only on this device while a game runs
- **Location:** `Modules/AudioRPG/View/PlayToolbarButton.swift:11-27`, `View/DetailListView.swift:22-27`
- **What:** Every other play entry point consults `isGameRunning` and sends a game command; this button always calls the local path.
- **Why:** The GM hears the music, no player gets it, and later GM pause commands act on audio the players never started.
- **Action:** Route through the same game-aware entry point.
- **Severity:** Medium
- **Status 2026-11-22:** fixed. The detail toolbar's Play goes through `AudioRootModel.playItem(id:isGameRunning:networkActions:)` (game-aware `startPlayback`). Test: `AudioPlaybackActionsTests.playButtonIsGameAware`.

### 5.19 Adventure `diceId` is not in the link register
- **Location:** `Modules/AdventureRPG/Model/AdventureModel.swift:131-179`, consumers `Controller/LinkController.swift:120-125`, `ExportController.swift:74-76`, `GameController.swift:71-77`, `Modules/DiceRPG/Controller/GameController.swift:247-255`
- **What:** Validate, export and link collection treat `diceId` as a link; the register diff covers only photo, table players and entries.
- **Why:** Deleting or moving a Dice item neither warns nor repairs the adventure; starting the game then focuses an empty dice set instead of the default d20.
- **Action:** Add `diceId` to the register diff and add a delete-impact test.
- **Severity:** Medium
- **Status 2026-11-22:** fixed. `AdventureModel.changedLinkRegisterModels` registers and unregisters `diceId` (module `.dice`). Tests: `AdventureTablePlayersTests` (red before). The delete-impact warning itself is not tested end to end.

### 5.20 Space viewer never reloads when the item's file is replaced, and a load error is permanent
- **Location:** `Modules/SpaceRPG/Root/ViewerRootView.swift:20-24`, `Space/SpaceViewer+Loading.swift:21-62, 117-131`, `Space/SpaceViewer.swift:102-105`, `Modules/GameRPG/GameViews/GameRootViewer.swift:215-222`
- **What:** The viewer is keyed on the item id alone and loads once inside `RealityView.make`; Pdf and Photo got a load key with the version, Space did not. Once `loadError` is set the RealityView is torn down and nothing retries.
- **Why:** A replaced USDZ keeps showing the old model until the viewer closes; an item whose file was momentarily unreadable stays on "Failed to Load 3D Model".
- **Action:** Key the viewer on id plus version as `PdfViewerLoadKey` does and make the error state retryable.
- **Severity:** Medium
- **Status 2026-11-22:** fixed in code, not run on visionOS or a device. The viewer is keyed on `SpaceViewerLoadKey(id, version, attempt)` and the error view has "Try Again", which re-creates the viewer. The new "Try Again" key is not yet in `Localizable.xcstrings` (Xcode adds it on the next catalog sync). Test: `SpaceViewerLoadKeyTests` (key only).

### 5.21 Foundry import view reloads the whole source whenever it re-appears
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryImportView.swift:65-67`, `FoundryRuleImportModel.swift:110-166`, `Modules/RolePlayGameKit/View/AppImportView.swift:49-74`
- **What:** `.task(id: selectionId)` calls the load on every appearance with no state guard; flipping the source picker removes and re-adds the view.
- **Why:** A prepared review with the user's Skip/Merge/Replace decisions or a completed result silently falls back to preflight and the archive is read again.
- **Action:** Make the load a no-op unless the state is not started (or an explicit retry from failed).
- **Severity:** Medium (Verified)
- **Status 2026-11-22:** fixed. `loadSelectedArtifact()` is a no-op unless the state is `.notStarted`; `select(url:)` resets it. Tests: `FoundryImportModelTests.reloadingIsANoOp` (red before), `failedLoadRetriesWithNewSelection`.

### 5.22 PDF block extraction hides every failure and swaps the screen to an empty result
- **Location:** `Modules/GeneratorRPG/View/PdfContentExtractionView.swift:38-48`, `Modules/PdfRPG/View/ContentExtractionView.swift:112-123`, `Modules/GeneratorRPG/BasicAI/Model/PdfContentExtractionModel.swift:25-52`
- **What:** The model records an error and returns empty or partial blocks; the view calls the result callback regardless, and the parent replaces the view (and its error banner) with the result. The double-start guard the sibling views have is missing.
- **Why:** A failed extraction looks like a PDF without text; partly failed documents silently lose pages; a fast second tap starts a second extraction.
- **Action:** Return a result type (blocks, failed pages, error) or call back only when blocks exist and no error is pending; add the task-handle guard.
- **Severity:** Medium (Verified)
- **Known:** audit 21 §5.28 (extractor fixed, view path not).
- **Status 2026-11-22:** fixed. `PdfContentExtractionModel.extractForDelivery` returns blocks only for a clean extraction (a failure or lost pages keep the screen with the banner; a PDF without text is a clean empty result); the view has a task-handle guard against a second start. Partial results are therefore not accepted from this screen; a retry is. Test: `PdfContentExtractionModelTests`.

### 5.23 Persistence and sync Lows (grouped)
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:101-135` (`updates()` ignores `deletingIds`); `Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift:208-218, 279-285, 318-334` (history cursor is a `Date`, not a token); `Modules/CoreRPG/App/AppEntityIndexLedger.swift:23-46` (indexed ids can overwrite a newer cached list after an await); `Modules/CoreRPG/Intent/IntentEntityHelpers.swift:386-404, 485-499` (Spotlight delete failures forgotten by the ledger); `Modules/AudioRPG/Model/AudioModel.swift:149-153`, `Modules/PhotoRPG/Model/PhotoModel.swift:136-153`, `Modules/TableRPG/Model/TableModel+Persistence.swift:30-52` (positional `isSame`, Known audit 27 §5.31)
- **What:** Edge cases in reconciliation, history processing and equality.
- **Why:** Rare stale or repeated sync work; a history cursor by date can skip or repeat transactions with equal timestamps.
- **Action:** Honour `deletingIds`, use persistent history tokens, compare by id in `isSame`.
- **Severity:** Low
- **Status 2026-11-22:** not fixed. Each item needs a design decision or a larger change (persistent history tokens instead of a date cursor, `isSame` by id for Audio/Photo/Table — Known audit 27 §5.31, ledger ordering).

### 5.24 Editing, Character and Dice Lows (grouped)
- **Location:** `Modules/CoreRPG/ItemList/EntryDataEditable.swift:210-217, 402-422` (a stale entry id appends a blank entry), `ItemList/GroupableEntryEditing.swift:38-72` (`convertToGroup` creates a new group when the chosen item cannot be edited); `Modules/DiceRPG/Model/DiceModel+Options.swift:96-100, 132-142` with `Controller/EditController.swift:48-75` (reroll/coup/fumble options can be added twice, duplicate `ForEach` ids); `Modules/DiceRPG/Model/DiceResultModel.swift:88-100` (rolls of sets over 100 dice dropped without feedback, Known audit 22 §5.12); `Modules/DiceRPG/Controller/GameController.swift:137-176, 294-312` (one leaked dice model per player roll, Known audit 22 §5.12); `Modules/CharacterRPG/Controller/GameController.swift:262-282`, `GameController+Dice.swift:35-60` (battle-clone dice never removed); `Modules/CharacterRPG/Controller/EditController.swift:147-165` (table link drop overwrites the entry name); `Modules/DiceRPG/Controller/DataController.swift:62-77` (Core Data narrows values the decoder accepts, Known audit 27 §5.23); `Modules/DiceRPG/Game/Detail/DiceRoll.swift:36-45` (single-die tap appends to earlier results); `Modules/DiceRPG/View/DiceInline.swift:165-169` (random die built in `body`)
- **What:** Missing duplicate/stale-id guards, silent drops and unbounded retention in the editing and dice paths.
- **Why:** Duplicate identities, silent loss of large rolls, slow growth of game-session memory on the master.
- **Action:** Add the guards, report dropped rolls to the roller, release replaced and clone dice.
- **Severity:** Low
- **Status 2026-11-22:** partly fixed. Fixed: a coup, fumble or reroll option cannot be added twice (a reroll replaces the one with the same number); test `EditControllerTests.sameOptionsAreNotAddedTwice` (red before). Not fixed: the table link drop that replaces the entry name (append or replace is a product decision), the stale-entry-id and `convertToGroup` guards, dice feedback for sets over 100 dice, leaked/clone dice models, `DiceRoll` single-die tap, random die in `body`, Core Data narrowing (need UI or device verification or a decision).

### 5.25 Game, statistics and network Lows (grouped)
- **Location:** `Modules/GameRPG/GameCenter/GameCenterController.swift:114-146` and `Statistics/View/GameCenterStatusView.swift:34-45` (no report when sign-in completes, Sign In inert after the first call, error message never shown); `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:89-108, 275-293` (a stop racing `beginSession` leaves an open session); `Modules/GameRPG/BattleRound/BattleRoundSettingsView.swift:131-141` (removing a pattern does not re-scan); `Modules/GameRPG/Intent/GameIntents.swift:202-214` (`JoinGameIntent` reports an ignored start as "already running", Known §5.30); `Modules/GameRPG/Search/SearchGlobalController.swift:28-33` and siblings (small search issues, Known §8.5); `Modules/GameRPG/Network/GameNetworkController+Delivery.swift:86-91` (`.direct(nil)` asset answer broadcasts, Known §6.6); `Modules/GameRPG/Root/GameRootSetupView.swift:66-68` vs `GameRootView.swift:17-21` (different stop guards writing `AppGameStateModel`)
- **What:** Small state-machine and reporting gaps.
- **Why:** Misleading status, orphan sessions, a broadcast where a direct answer was meant.
- **Action:** Close each gap as described by the agent notes in the scope findings.
- **Severity:** Low
- **Status 2026-11-22:** not fixed. Sign-in report, stop-vs-`beginSession` race, pattern re-scan, `JoinGameIntent` wording, search and delivery details need UI or two-device verification, or are Known items with their own decisions.

### 5.26 File viewer, Photo, Table and Weather Lows (grouped)
- **Location:** `Modules/PdfRPG/Controller/ItemController.swift:54-68`, `Root/ViewerRootView.swift:97-120` (locked PDFs open blank); `Modules/PdfRPG/Pdf/PdfWrapperView.swift:187-200` (stale highlight task); `Modules/SpaceRPG/Space/SpaceViewer+Loading.swift:68-74` (size limit only at open, not at attach); `Modules/TableRPG/Controller/TableGenerationController+OutcomeEditing.swift:49-67` (stale `editedOutcome` after selection change); `Modules/PhotoRPG/Controller/PinCutoutCache.swift:50-65, 67-90` (transient failure memoised as "no subject", disk files never pruned); `Modules/PhotoRPG/Photo/AsyncImageViewer.swift:90-122` (cancelled load runs its error tail); `Modules/WeatherRPG/Weather/StormView.swift:24-37`, `Lightning.swift:96-135` (per-drop context copies, Known §5.34/§7.10)
- **What:** Edge cases in viewers and generators.
- **Why:** Blank viewers without a message, stale previews, cached failures.
- **Action:** Show a password-needed state, clear stale state on selection change, do not memoise transient failures.
- **Severity:** Low
- **Status 2026-11-22:** not fixed. Locked-PDF state, stale highlight/outcome state, cutout cache failure memoisation and the load tails need UI states or verification on a device.

### 5.27 Import and routing Lows (grouped)
- **Location:** `Modules/RolePlayGameKit/Route/WindowRouter.swift:89-233`, `Route/RootURLHandler.swift:34-48`, `Model/AppModel+Routing.swift:49-235` (entry ids accepted by every route entry point and then dropped, so entry deep links stop at the item); `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Indexes.swift:280-300` (cyclic folder members both lose their parent); `Modules/CoreRPG/Foundry/FoundryZIPArchive.swift:166, 238, 371` vs `:467-481` (Data slice index mix, latent); `Modules/RuleRPG/Intent/RuleManagementIntents.swift:42-46` (`CreateRuleIntent` drops description formatting); hard-coded English in stored import text (`FoundryVTTDomainMapper+Documents.swift:540-603`, `+SharedHelpers.swift:405-407`, Known §5.29)
- **What:** Dropped parameters and edge cases at the import/route boundary.
- **Why:** Deep links land on the wrong level; hostile cyclic folders lose members.
- **Action:** Thread `entryId` through the router; keep cyclic members under the root.
- **Severity:** Low
- **Status 2026-11-22:** not fixed. Threading `entryId` through the router, cyclic Foundry folders (the current rule puts every member of a cycle at the root, the finding's expectation needs a decision), the ZIP slice indexes (latent), `CreateRuleIntent` formatting and the English import text (Known §5.29).

## 6. Security

### 6.1 An imported `.local` file reference resolves to an arbitrary absolute path
- **Location:** `Modules/CoreRPG/Files/FileUrl.swift:193-222` (`sanitizedForImport`, `namesFileBelowStorageRoot`), `Modules/CoreRPG/Files/LocationFileManager.swift:76-86`, consumers `FileUrlDataController.swift:392-401, 496-519`, call site `Modules/CoreRPG/Controllable/ImportControllable.swift:349`
- **What:** For `.local` references with no `Documents` component, `absoluteUrl` returns the stored URL unchanged and the sanitiser keeps any `.local` URL that has a path component and no `..`. Other locations are rebuilt below their root.
- **Why:** An imported game bundle (the app downloads `.gmz` files from GitHub), a shared item or a peer package can make the app read any file it can see in its sandbox (Core Data store, bookmark store, other adventures' files) and, in game mode, send those bytes to players as the item's file.
- **Action:** Relocate every `.local` import reference without a `Documents` component to app storage (or all `.local`, since nothing creates it any more) and return nil from `absoluteUrl` for it. Add a test for `file:///etc/hosts` as `.local`.
- **Severity:** Medium (Likely; sanitiser and resolver read by the lead and the described path holds; end-to-end send not run)
- **Known:** the delete side is audit 27 §6.4; the read side was not reported there.
- **Status 2026-11-22:** fixed at the import gate. `FileUrl.sanitizedForImport` relocates a `.local` reference without a `Documents` component to app storage (named after its last component). Not done: returning nil from `LocationFileManager.absoluteUrl` for it — the app's own `.local` files outside `Documents` (test fixtures, `hasAccess`, existing-file lookup) resolve through it, and every imported or peer reference goes through the sanitiser. Test: `UntrustedImportTests.localAbsolutePathIsRelocated` (red before).

### 6.2 Foundry text neutralisation in the rule factory is undone by the mapper
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Rules.swift:167-215`, `+Documents.swift:148-152`, `+SharedHelpers.swift:280-301`; defence being overwritten `Modules/RuleRPG/Model/RuleModel+FoundryFactory.swift:187-229`; `Modules/CoreRPG/Foundry/FoundryTextDecoder.swift:409-431` (strips the zero-width space)
- **What:** The factory escapes markdown and splits `](` and `://` so imported text cannot form links; the mapper then overwrites description and entry content through plain-text helpers that apply no escaping, and `decodedText` strips the zero-width space again.
- **Why:** A package containing a web link or a `masterrpg://` link in a description or value is stored as a live link that `AttributedString(markdown:)` renders. The factory tests pass because they test the factory alone.
- **Action:** Apply the same neutralisation at the mapper's text helpers while keeping rewritten item links, or remove the dead escaping and document the mapper as owner; add a mapper-level test with both link kinds.
- **Severity:** Medium (Likely)
- **Known:** audit 22 §6.5 / 22a §5.10, reported fixed, still open on the mapper path.
- **Status 2026-11-22:** fixed for descriptions and values. `FoundryVTTDomainMapper.safeText` and `decodedFoundryText` split `](` and `://` with a zero-width space after the decoder and before the Foundry links are rewritten, so the mapper's own item links stay live. Not covered: the composed rule contents (`projectedRuleReferenceContent`, effect and embedded-rule text) and plain names. Test: `FoundryVTTDomainMapperRuleTests.descriptionLinksAreInert` (red before).

### 6.3 Quadratic HTML tag regex freezes the Foundry import on the main actor
- **Location:** `Modules/CoreRPG/Foundry/FoundryTextDecoder.swift:42-56` (patterns at lines 44 and 49, applied at 28-34), callers `FoundryVTTDomainMapper+SharedHelpers.swift:277`, `FoundryVTTDomainMapper.swift:219`, `Modules/RuleRPG/Model/RuleModel+FoundryFactory.swift:409, 427`
- **What:** Every `<` followed by a letter makes the `[^>]*` part scan to the end when no `>` follows. Audit 26 §7.4 removed the same shape from the comment/script patterns, but these two generic tag patterns were left. The agent measured the exact pattern: a run of `<a` took 1.0 s at 20 KB, 4.0 s at 40 KB and 15.9 s at 80 KB; Foundry strings may be 64 MiB.
- **Why:** A crafted description freezes the import on the main thread for minutes; `NSRegularExpression` is not cancellation-aware, so Cancel does not stop it; on iOS the watchdog can kill the app. It needs the user to import the package.
- **Action:** Replace both patterns with the linear byte scanner used for comments (or bound the tag length), cap the string length, add a timing test with an unterminated run.
- **Severity:** Medium (pattern read by the lead; timing measured by the agent; rated Medium, not High, because it needs a deliberately hostile or broken package)
- **Status 2026-11-22:** fixed. `FoundryTextDecoder.strippingTags` replaces the three regular expressions with one linear byte pass (a `<` without a `>` ahead stops the search for all later ones); output is the same for the tested shapes. No string-length cap added. Tests: `FoundryPresentationHelpersTests.unterminatedTagsAreLinear` (34 s before, under 2 s after), `stripsTags`.

### 6.4 Dotted rule-value paths recurse and copy per component without a limit
- **Location:** `Modules/CoreRPG/Foundry/FoundryValueHierarchy.swift:75-118`, path source `FoundrySystemPackageReader.swift:674-681`, consumers `Modules/RuleRPG/Model/RuleModel+FoundryFactory.swift:289-330`
- **What:** JSON depth is capped but object keys are joined with dots and split again; one key with tens of thousands of dots becomes a path of that many components. `NodeBuilder.insert` recurses once per component and `materialized` builds a fresh path array at every level.
- **Why:** A hostile package can overflow the stack (a crash, not a catchable error) or allocate gigabytes before the 500-value presentation cap applies.
- **Action:** Cap components per path (keep an over-long path as one literal component), pass the parent path by reference or build iteratively; test a 100k-dot key.
- **Severity:** Medium (Likely; recursion and missing limit read by the lead, not executed)
- **Status 2026-11-22:** fixed. A dotted path of more than 64 components stays one literal component (`FoundryValueHierarchy.maximumPathComponents`); the recursion is not made iterative. Test: `overLongPathIsOneComponent` (a 100k-dot key; crashed the test process before).

### 6.5 Bookmark store is rewritten from a per-process copy and the save result is dropped
- **Location:** `Modules/CoreRPG/Files/FileBookmarkController.swift:113-130`, second process `Modules/PhotoRPG/Controller/ShareImportPhotoController.swift:40, 58` via `Modules/RolePlayGameKit/Model/ShareExtensionSaveController.swift:45`
- **What:** The app and the share extension each load the whole bookmark store once and rewrite it on every change; the save result is ignored.
- **Why:** Photos shared through the extension can lose their security-scoped bookmark, and a failed write is silent.
- **Action:** Re-read and merge inside `save`, or give the extension its own bookmark file; keep the pending flag set on a failed write.
- **Severity:** Medium (Likely)
- **Known:** audit 26 §5.56, still open.
- **Status 2026-11-22:** fixed. `FileBookmarkModel.save` re-reads the stored file and writes the stored rows plus only this process's changes (and removals); a failed read or write keeps the changes pending instead of dropping the result. The share extension still has its own copy in memory; there is no cross-process lock, so two writes at the same moment can still race. Tests: `FileBookmarkControllerTests.writeKeepsBookmarksOfAnotherProcess` (red before), `removalIsMerged`.

### 6.6 Generator hardening gaps (grouped)
- **Location:** `Modules/GeneratorRPG/BasicAI/Providers/PdfContentExtractor.swift:163-188`, `BasicAI/Engine/UntrustedPromptText.swift` (extractor prompt not fenced as untrusted); `Modules/GeneratorRPG/BasicAI/Providers/PhotoSummaryAnalyzer.swift:34-56`, `PrivateCloudComputeGate.swift` (the Private Cloud Compute path is permanently off: no target defines the flag and nothing calls the host declaration)
- **What:** The one PDF path that sends imported text to the model without the untrusted-text fence; a dormant PCC path.
- **Why:** Prompt injection from PDF text affects only that user's own generation; the PCC path is dead weight with a consent dialog.
- **Action:** Fence the extractor prompt like the other paths; decide whether PCC ships and remove or wire it.
- **Severity:** Low
- **Status 2026-11-22:** partly fixed. The PDF block extractor fences the page text and adds the untrusted-text instruction (`PdfContentExtractor.buildPrompt`; test `UntrustedPromptTextTests.extractorPromptIsFenced`). Not changed: the dormant Private Cloud Compute path (ship or remove is a product decision).

### 6.7 Security-scoped and iCloud reads outside their scope (grouped)
- **Location:** `Modules/PhotoRPG/Space/Spatial3DImageState.swift:46-72, 109-137`, `Modules/PhotoRPG/Intent/PhotoEntity+Image.swift:17-29` (read after the security scope ended, Unverified); `Modules/PdfRPG/Intent/PdfEntity.swift:97-105`, `Modules/SpaceRPG/Intent/SpaceEntity.swift:94-101` (shared exports hand out the stored URL without starting an iCloud download)
- **What:** File URLs used after their scope or before the data is local.
- **Why:** Sporadic failures for picked or iCloud-only files.
- **Action:** Hold the scope until the read finishes; request the download before exporting.
- **Severity:** Low
- **Status 2026-11-22:** partly fixed, untested. The Photo, Pdf and Space share/export representations request the iCloud download first (`ItemControllable.downloadedLoadableUrl`), and the photo bytes are read inside the security scope. No test: `FileUrlDataController` has no stub to observe the download. Not changed: `Spatial3DImageState` (its scope already spans the load; the finding was Unverified).

### 6.8 Hidden-room geometry is sent to players (design note)
- **Location:** `Modules/MapRPG/Model/MapSnapshot.swift:150-199`
- **What:** Hidden-room polygons are part of the payload players receive (names and content are redacted).
- **Why:** A modified client could see where hidden rooms are; players are trusted peers by design.
- **Action:** Keep as documented; revisit only if the trust model changes.
- **Severity:** Low
- **Status 2026-11-22:** no change, as the finding recommends (design note).

## 7. Performance

### 7.1 The observable full-image cache is bounded by count, not bytes, and pins pull full-resolution bitmaps
- **Location:** `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:259-316`, `Modules/PhotoRPG/Photo/AsyncThumbnail.swift:78-98, 145-162`, `Controller/CacheController.swift:35-57`, `Controller/EditController.swift:90-112`, decode cap `Modules/CoreRPG/Extensions/Image+AKImage.swift:229-230`
- **What:** Every displayed full-size photo is also held by strong reference in an observable cache that evicts only by count (120); the byte-cost cache is bypassed. A decode can be up to 8192 px (about 200-250 MB). Thumbnails of 160 pt or more switch to the full-image path, and the repository has no memory-warning handling.
- **Why:** A zoomed map with many photo pins, or paging through high-resolution scans, can pin gigabytes and end in a jetsam kill mid-session, losing unsaved game state; typical 12 MP photos are about 48 MB each, so 120 of them is about 5.7 GB.
- **Action:** Give the cache a byte budget and trim on memory warning; decode a bounded intermediate size for 160-400 pt pins; drop the observable copy when the byte cache evicts.
- **Severity:** Medium (Likely; not measured)
- **Status 2026-11-23:** partly fixed. `ObservableImageCache` now has a byte budget next to the count (384 MiB of decoded bitmaps, least recently used leave first, the newest image is always kept) and drops all full images on a memory warning (iOS, tvOS, visionOS; thumbnails stay). Test: `ImageCacheTests.observableImageByteBudget`. Not done: a bounded intermediate decode for 160–400 pt pins, and dropping the observable copy when the byte cache evicts (both change what is on screen and need a device run).

### 7.2 Sync applies each changed row with its own fetch, hop and main-actor model build
- **Location:** `Modules/CoreRPG/Controllable/SyncDataControllable.swift:120-153`, `CoreDataSnapshotPersistable.swift:62-66`, `Modules/CoreRPG/Persistence/CoreDataController.swift:350-356, 509-529`, `CoreDataChangeObserver.swift:88-100`
- **What:** A CloudKit merge with n rows runs n sequential awaits (context hop, single-row fetch, main-actor build) after the observer faulted each object to read its uuid; twelve module observers each walk the id set.
- **Why:** First sync on a new device or a big import keeps the consumer busy and holds the main actor repeatedly.
- **Action:** Fetch a batch with one `uuid IN` request and map all snapshots in one `perform`; read uuids without faulting. Profile with several thousand items.
- **Severity:** Medium (Likely; unmeasured)
- **Status 2026-11-23:** not changed: a batched `uuid IN` fetch across twelve module observers is a larger refactor, and the audit says to profile with several thousand items first.

### 7.3 Statistics reload and achievements fetch the whole event history twice per game end, aggregated on the main actor
- **Location:** `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:71-87, 275-323, 447-462`, `GameStatisticsDataController.swift:274-317`, `GameStatisticsController.swift:97-158`
- **What:** `setUp` and `finishSession` each reload (fetch plus summary) and then report achievements (a second fetch and summary); every game message is a row of about 25 columns; aggregation runs on the main actor.
- **Why:** After a year of play every game end and launch stalls the main actor and loads everything twice.
- **Action:** Compute the summary once and derive achievements from it (or use grouped fetches), run the aggregation off the main actor, fetch only the needed kinds, add retention for old rows.
- **Severity:** Medium (Verified by reading; not measured)
- **Known:** audit 27 §7.4, still open.
- **Status 2026-11-23:** partly fixed. A game start or end now fetches the whole history once and cuts the dashboard range out of it in memory (`GameStatisticsDataSet.filtered`), and the achievements come from the same set instead of a second fetch. The aggregation runs off the main actor (`summaryOffMainActor`). Test: `GameStatisticsDataControllerTests.filteredEqualsFetchedRange`. Not done: fetching only the needed event kinds and retention for old rows (needs a product decision).

### 7.4 Changing section order, visibility or metric re-runs the full statistics reload
- **Location:** `Modules/GameRPG/Statistics/View/GameStatisticsDashboardView.swift:345-347`, `GameStatisticsTypes.swift:232-240`, `GameStatisticsModel.swift:295-323`
- **What:** The task is keyed on the whole configuration, but only date range, direction and granularity affect the data.
- **Why:** Toggling or dragging sections in Customize triggers a full fetch each time while the dashboard is visible.
- **Action:** Key the task on a small hashable of the data-affecting fields.
- **Severity:** Medium (Verified)
- **Status 2026-11-23:** fixed. The dashboard reloads on `GameStatisticsDashboardConfiguration.dataKey` (date range, granularity, direction), not on section order, visibility or metric. Test: `GameStatisticsRiskTests.dataKeyIgnoresPresentationFields`.

### 7.5 The master recomputes the full content digest on every send
- **Location:** `Modules/MapRPG/Controller/GameController+Metadata.swift:46-56, 119-126`, `Model/MapUpdatePayload.swift:44-48, 75-129`, callers `GameController+Sync.swift:68, 80, 89`, `GameController+BattleSync.swift:193`, `GameController+Pins.swift:388`
- **What:** An authoritative generation is recorded only on player receive paths, so on the master `networkGeneration(for:)` falls back to building a snapshot, a canonical copy and a digest for every map message and generation check.
- **Why:** On a 20,000-cell hex map each pin drag or room toggle costs an O(entries) copy, sort and hash on the main actor per message.
- **Action:** Cache the content version keyed by a change counter, invalidated on structural edits only.
- **Severity:** Medium
- **Status 2026-11-23:** not changed: a cached content version needs an invalidation rule for every structural edit, and a stale version would stop map syncs; the audit itself asks to measure first, and the change needs a profile or a device run.

### 7.6 O(entries) equality checks in view bodies on large maps
- **Location:** `Modules/MapRPG/Map/RootEditCanvasMap.swift:100-131`, `Map/MapEditor.swift:112-117`, `Model/MapModel+Sync.swift:105-140`
- **What:** `onChange` and the presentation identity compare the whole entries array (up to 20,000 hex cells with CRDT strings) on every body evaluation.
- **Why:** Editor and GM screens pay millisecond-scale comparisons per observation tick.
- **Action:** Compare a cheap change token (the CRDT update ids) instead of the arrays.
- **Severity:** Medium (not profiled)
- **Status 2026-11-23:** not changed: replacing the array compare with a change token has the same risk as §7.5 and the audit marks it not profiled.

### 7.7 Sheet update re-projects every entry and its linked sheets on each change
- **Location:** `Modules/CharacterRPG/Controller/SheetController.swift:104-197`, `Modules/AdventureRPG/Controller/SheetController.swift:146-199`
- **What:** For every entry, each update rebuilds a full projected sheet (calculator evaluation, link register lookup, a throwaway sheet per linked item) only to compare and discard it.
- **Why:** On a character with 100 or more entries, or an adventure imported from a PDF with hundreds, every edit allocates hundreds of sheet trees on the main actor.
- **Action:** Skip entries whose source and linked entries are unchanged; build linked sheets lazily. Profile a 150-entry fixture before changing.
- **Severity:** Medium (not profiled)
- **Known:** the Rule twin is audit 27 §7.6, left open pending measurement.
- **Status 2026-11-23:** not changed: the audit itself asks to measure first, and the change needs a profile or a device run. The audit asks for a 150-entry fixture profile first.

### 7.8 One RealityKit hit entity, collider and ribbon mesh per room, including every hex cell
- **Location:** `Modules/GameRPG/Table3D/GameTableProjection.swift:114-151`, `GameTableEntities.swift:515-626`
- **What:** `syncRooms` builds a hit area for every map entry, hex cells included (capped at 20,000), each with an input target, hover effect, accessibility component, convex shape and a synchronous mesh, all on the main actor.
- **Why:** The default 100-200 cells is probably fine; a finer scale means thousands of meshes and colliders created at once (a visible hang on hex toggle or rescale) and thousands of transparent draw calls afterwards.
- **Action:** Use one shared hit surface that resolves the cell from the hit point, or create areas lazily near the touch; skip per-cell outline meshes.
- **Severity:** Medium (Likely; not measured)
- **Status 2026-11-23:** not changed: the audit itself asks to measure first, and the change needs a profile or a device run.

### 7.9 Per-frame dice-result scan grew to seven die kinds and is still not short-circuited
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+DiceResults.swift:23-48, 111-145`, `GameRenderer.swift:102-104`, `GameTableModel+Popovers.swift:122-141`, `GameTableView+PlatformFlat.swift:400-410`
- **What:** `updateDiceResults` runs every TabletopKit frame over 5 seats x 7 kinds x 6 slots (about 210 lookups) even when every die is parked; the flat table projects eight corners every frame while a popover is open.
- **Why:** Steady main-thread work at 90 Hz for the whole session on Vision Pro in the common case of no dice rolled.
- **Action:** Keep the set of non-parked die ids and skip empty seats; project only when the camera or target moved.
- **Severity:** Medium (frame cost unmeasured)
- **Known:** audit 21 §7.7, still open.
- **Status 2026-11-23:** not changed: the scan is visionOS-only TabletopKit code, which the iOS tests cannot run, and the frame cost is unmeasured.

### 7.10 252 always-live dice entities with spatial audio and about 50 SwiftUI attachments are created up front
- **Location:** `Modules/GameRPG/Table3D/GameSetup.swift:126-213`, `GameDie20.swift:139-150`, `GameTableView+VisionOS.swift:113-172`, `GameTableModel+SeatControls.swift:15`
- **What:** 6 seats x 7 kinds x 6 slots of PBR dice, each with its own spatial audio component and prepared controller, parked rather than disabled (disabling crashed joining players), plus 51 attachment entities, most of them empty.
- **Why:** Constant memory and scene cost on a device near its budget; cost not measured.
- **Action:** Measure first (RealityKit trace); share one prepared audio resource, prepare lazily on first toss, lower `maxRemovePopovers`, create guest-group attachments only for existing groups; keep dice parked by pose.
- **Severity:** Medium (counts verified, cost unverified)
- **Status 2026-11-23:** not changed: the audit itself asks to measure first, and the change needs a profile or a device run.

### 7.11 Collision shapes are generated on the main actor for every 3D viewer, including inline previews and iOS/macOS
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer+Loading.swift:213-249`, `Modules/SpaceRPG/View/InlineRowViewer.swift:22-24`
- **What:** Each viewer loads the complete USDZ and builds static triangle-mesh collision for the whole hierarchy on the main actor; on iOS and macOS the shapes serve only the hover highlight, and every linked 3D object in a sheet embeds a full viewer.
- **Why:** A sheet with several linked objects freezes the UI per model; a dense peer-sent model can hang the main actor for seconds. The 256 MiB cap bounds file size, not mesh complexity.
- **Action:** Skip collision generation for inline previews and platforms that do not use it; add a complexity budget.
- **Severity:** Medium
- **Status 2026-11-23:** not changed: skipping collision for inline previews also removes the hover highlight there, which needs a look on iOS, macOS and visionOS.

### 7.12 `PdfModel.isSame` compares entries with `==`, which includes CRDT clocks and actor ids that every load regenerates
- **Location:** `Modules/PdfRPG/Model/PdfModel.swift:145-162`, `PdfEntryModel.swift:7-39, 81`, `Controller/DataController.swift:79-86`, `Modules/CoreRPG/CRDT/LWWRegister.swift:125-129`, consumer `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:25-29`
- **What:** Two copies of one PDF with identical bookmarks compare unequal once one was rebuilt from Core Data, so `mergeSync` never short-circuits for a bookmarked PDF.
- **Why:** Every remote-change batch re-merges and re-applies each bookmarked PDF: needless saves and invalidation. No data loss expected.
- **Action:** Use the entry's own `isSame` comparator.
- **Severity:** Medium (Likely; not confirmed at runtime)
- **Status 2026-11-23:** fixed. `PdfModel.isSame` compares entries with the entry's own `isSame` (no CRDT clocks and actor ids). Test: `PdfModelTests.isSameIgnoresRegeneratedEntryClocks` (red before).

### 7.13 The PDF block extractor budget exceeds the on-device context window by design
- **Location:** `Modules/GeneratorRPG/BasicAI/Providers/PdfContentExtractor.swift:24-30, 108-135`, `BasicAI/Engine/FoundationModelInputLimiter.swift:14-24`, `PdfSummaryAnalyzer.swift:12-70`, `BasicAI/Model/PdfSummaryAnalysis.swift:25-31`
- **What:** The extractor sends up to 7,000 characters per page and asks the model to reproduce the text with no response-token cap or count guide; the limiter assumes about three characters per token while the extractor comment assumes four, against a 4,096-token window.
- **Why:** Dense pages fail with context overflow and are skipped (and, because of §5.22, silently).
- **Action:** Size the per-page input to leave room for output using the model's context size and token counting, set `maximumResponseTokens` and a maximum count on sections, use one chars-per-token constant.
- **Severity:** Medium (Likely; arithmetic from the module's own constants)
- **Status 2026-11-23:** fixed. The default page budget is derived from the window: the page counts twice (prompt and reproduced answer) next to 900 tokens of overhead, so it is about 4,900 characters instead of 7,000; one `charactersPerToken` constant (3) and the window size live in `FoundationModelInputLimiter`; each page request sets `maximumResponseTokens` to the rest of the window. Test: `UntrustedPromptTextTests.extractorBudgetFitsTheWindow`. Not done: a maximum count on generated blocks.

### 7.14 Other performance Lows (grouped)
- **Location:** `Modules/CoreRPG/Sheet/SheetRootView.swift:63` and `SheetRootModel+Selection.swift:161-190` (body walks the whole tree for the menu focus value); `Modules/CoreRPG/Links/ReferenceScanner.swift:27, 48`, `LinkBuilder.swift:48-50` (link scanners backtrack quadratically on long unterminated link text); `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:35-44, 1224-1234` (source parsed and hashed twice); `Modules/CoreRPG/EntryEditor/EntryEditorContent.swift:13`, `Buttons/InlineEditorView.swift:14`, `Modules/TableRPG/View/TableGenerationEntryRow.swift:6-23` (an `@Observable` allocated in `init` on every parent render); `Modules/PhotoRPG/Photo/InlineImporterView.swift:99-115` (PhotosPicker loads the whole original as `Data`, Known §7.8); `Modules/PdfRPG/Pdf/PdfBookmarkPage.swift:16-27` (every page label read on the main actor); `Sources/RPGShare/ItemProviderImporter.swift:19-31, 138-160` (thumbnail decoded on the main actor); `Modules/AudioRPG/Controller/AudioController.swift:152-236` (synchronous temp-file deletion on the main actor); `Modules/GameRPG/Table3D/GameBoard.swift:239-348` (fog recomposite redraws the full photo and replaces mesh and collider on every toggle); `Modules/RuleRPG/Model/RuleModel.swift:200-210, 307-308, 377-381` (`isSame` deep-compares the source payload)
- **What:** Redundant or repeated work on the main actor.
- **Why:** Minor stalls on large inputs.
- **Action:** Cache or hoist where noted; move the decodes off the main actor.
- **Severity:** Low
- **Status 2026-11-23:** partly fixed. The link scanner (`ReferenceScanner.parseLinks`) runs its pattern on one bounded window per `](scheme://` instead of the whole text; 80,000 unterminated labels took 292 s before and are linear now (test `ReferenceScannerTests.unterminatedLabelsAreLinear`, red before). `LinkBuilder.markdownLinkPattern` excludes `[` in labels and was not quadratic. Not changed: the other items (sheet focus walk, Foundry reader double parse — the reader already hands the parsed source on, per CODE_AUDIT_9 §7.3 —, `@Observable` in `init`, PhotosPicker data, bookmark page labels, share-extension thumbnail, audio temp-file deletion, fog recomposite, `RuleModel.isSame`): each needs a profile or a design decision.

## 8. SwiftUI / UI

### 8.1 Adventure game sheet mutates observable state while building `body`
- **Location:** `Modules/AdventureRPG/View/AdventureSheet.swift:27-40, 59-77, 97-116`
- **What:** `AdventureSheet.body` and `ReaderSheetView.body` (game branch) call a helper that reads, and when nil writes, an observed property and resets an `@Observable` sheet model, all inside `body`, twice per update. The Character twin was changed to resolve the model in `onChange(of:initial:)` into `@State`.
- **Why:** "Modifying state during view update" faults, an extra invalidation pass, and tree rebuilds triggered by evaluation order.
- **Action:** Port the Character pattern, ideally as a shared CoreRPG helper.
- **Severity:** Medium (Likely; the runtime warning was not observed)
- **Status 2026-11-23:** fixed. The resolution moved into the shared `ItemRootControllable.resolveGameSheetRootModel(for:)` (CoreRPG); `AdventureSheet` resolves it in `onChange(of: model.id, initial: true)` into `@State` like the Character twin (which now calls the same helper), and `body` only reads. The old `AdventureRootModel.gameSheetRootModel(for:)` is gone. The panel is empty for the first render when no model is stored yet. Tests: `GameSheetRootModelTests` (stores, reuses and moves the model; a read does not create it). Not red-verified: the helper is new API.

### 8.2 Rule entry-kind titles and source-metadata labels ignore the module bundle
- **Location:** `Modules/RuleRPG/Model/RuleSourceModels.swift:75-85`, `Modules/RuleRPG/View/RuleSourceDisclosureView.swift:55-72`, used by `RuleQuickEntryEditor.swift:160`
- **What:** The strings exist with German and Thai translations only in the Rule module catalog, but both lookups use the main bundle (CLAUDE.md requires the module bundle).
- **Why:** The section-kind picker and the whole "Rule Source" grid are English on German and Thai devices.
- **Action:** Pass the module bundle for the resources and the row titles.
- **Severity:** Medium (Verified by the agent against the catalog)
- **Status 2026-11-23:** fixed. `RuleEntryKind.localizedTitle` builds its resources with the module bundle and the metadata row titles use `Text(title, bundle: .ruleModule)`. Test: `RuleLocalizationTests` (German titles; red before).

### 8.3 Hard-coded padding, spacing and fixed sizes (about 250 sites)
- **Location:** `Modules/CoreRPG/LGViews/ItemHeaderEditorView.swift:253-419`, `CoreRPG/FileViews/SingleReview*Row*.swift` (about 78 sites), `Modules/GameRPG/GameViews/GameRootViewer.swift:175-176`, `GameViews/GameSidePanelModifier.swift:207, 214`, `Modules/SpaceRPG/Record/*` (about 35), `Modules/PdfRPG` (about 35), `Modules/AudioRPG/Audio/*` (27), `Modules/PhotoRPG`/`TableRPG` (35), `Sources/DiceRollerWidget/DiceRollerWidgetView.swift`, `Sources/RPGShare/SharingView.swift`, `Modules/GameRPG/Table3D/GameTableSeatPanels.swift:39, 111, 153, 217`
- **What:** Numeric `padding`/`spacing`/corner-radius/frame values against the CLAUDE.md rule.
- **Why:** Style drift and Dynamic Type friction; no functional bug.
- **Action:** Replace with defaults or shared theme tokens as files are touched.
- **Severity:** Low
- **Status 2026-11-23:** not changed (style sweep, to be done as files are touched, as the audit says).

### 8.4 Other SwiftUI Lows (grouped)
- **Location:** `Modules/GeneratorRPG/View/SheetAIAssistantContext.swift:42-55`, `Root/GeneratorRootModel.swift:~139-178` (controllers created, reordered and torn down inside a view `body`); `Modules/CoreRPG/LGViews/CloudFolderScanView.swift:83-115` ("Cancel" offered while the sync keeps running); `LGViews/ItemHeaderEditorView.swift:80-100, 298-309` (can save twice); `Modules/CoreRPG/Navigator/Views/ManagedPresentationView.swift:73-77` (registers its navigator from `body`; a swiped sheet leaves `isPresenting` true, Known §8.2); `Modules/GameRPG/GameViews/MasterOverlayMenu.swift:30-34`, `PlayerOverlayMenu.swift:31-35` (macOS side-menu animation ignores Reduce Motion); `Modules/GameRPG/Table3D/GameDiceResultPopover.swift:35-37` (reads TabletopKit's seat in `body`, not observable); `Modules/GameRPG/Table3D/GameTableView+PlatformFlat.swift:63-147`, `GameTableView+VisionOS.swift:51-73` (accessibility subscriptions dropped on disappear); `Modules/GeneratorRPG/BasicAI/Model/PdfSummaryAnalysis.swift:47-49` (section id can collide in `ForEach`); `Modules/AudioRPG/Controller/AudioPlayerSession.swift:258-282` (resume bypasses the session queue; observer list never cleared)
- **What:** Small state, identity and accessibility issues.
- **Why:** Occasional wrong UI state or missed accessibility updates.
- **Action:** Move work out of `body`, guard double actions, honour Reduce Motion, keep subscriptions for the view's lifetime.
- **Severity:** Low
- **Status 2026-11-23:** partly fixed. Fixed: audio session observers are cancelled and cleared before a new registration, so a second `initSession()` no longer doubles every notification (test `initialisingTwiceHandlesANotificationOnce`, red before); `ItemHeaderEditorView` saves once; Cancel in `CloudFolderScanView` is disabled while the sync runs; the macOS side-menu animation honours Reduce Motion (Master and Player); `SummaryPdfUpdateView` lists sections by offset so equal heading + page no longer collide (`PdfSection.id` itself unchanged). The last three have no test. Not changed: controllers created in `body` (`SheetAIAssistantContext`, `GeneratorRootModel`), `ManagedPresentationView` registration, `GameDiceResultPopover` seat read, the accessibility subscriptions, and the audio resume path bypassing the session queue — each needs a design change or device verification.

## 9. Dead code / duplication / refactor

### 9.1 visionOS 2D game-screen code is dead after the table-only change; the group-immersion sync is orphaned
- **Location:** `Modules/GameRPG/GameViews/GameImmersiveSpaceSync.swift:1-69`, `GameOrnamentCloseButton.swift:1-33`, `GameRootViewer.swift:164-170`, `MasterSideMenu.swift:11-24`, `PlayerSideMenu.swift:25-32`, `GameTableWindowButton.swift`, `OverlayGameLayout.swift:75-126`, `GameSidePanelModifier.swift:158-172`, `GameScreenModel.swift:229-253`, `QuickDiceOverlay.swift:31-33`, `RoundGameControlStyle.swift:27-33`, `BattleRoundSideOverlay.swift:84-86`, `RPGSharePlayController+VisionOSTemplate.swift:38`
- **What:** On visionOS `GameRootView` shows only `GameTableLaunchView`, so the 2D game screens, side panels and menus are never instantiated there. Commit `0d0fa6ac6` removed the only caller of the group-immersion sync modifier and the ornament close button; nothing reads `groupImmersionActive` any more.
- **Why:** About 400 lines of unreachable UI to maintain and snapshot, and a possible silent behaviour change: the debounced "follow the SharePlay group into or out of immersion" logic no longer runs on any path.
- **Action:** Decide whether the follow behaviour is still wanted (apply the modifier in the table host, or delete it and its writers), delete the ornament button and the visionOS branches in the 2D-only views, keep the shared pieces the table uses.
- **Severity:** Medium (dead status verified by grep; behavioural gap unverified on device)

### 9.2 `OverlayGameMenu` macOS/visionOS branches and the three-state menu views are unreachable
- **Location:** `Modules/GameRPG/GameViews/OverlayGameMenu.swift:21-35, 56-169, 253-394`, `GameMainTabButtonView.swift`, `GameScreenModel+MainTab.swift:28-60`, `GameMainTabToggleButtonView.swift:11`, `MasterOverlayMenu.swift:16-20`, `PlayerOverlayMenu.swift:19-23`
- **What:** The overlay menu is instantiated only in the non-visionOS, non-macOS branch, which forwards to the iOS and tvOS menus; the macOS and visionOS variants and the three-state button are reachable only from previews.
- **Why:** About 250 lines compile on every platform and previews hide drift.
- **Action:** Reduce `OverlayGameMenu` to the tvOS path, delete the unused views and `applyMainTabDisplayMode` with its test; confirm the macOS toolbar still uses the display mode first.
- **Severity:** Medium (Verified by grep of all callers)

### 9.3 Dead "use PDF selection / text extracted" plumbing between the viewer and four quick editors
- **Location:** `Modules/PdfRPG/Root/ViewerRootView.swift:15, 25-30`, `Controller/ViewController.swift:30-32`, `View/DetailFolderListView.swift:33`, `Model/PdfViewerActions.swift:1-52`, writers `Modules/{Adventure,Character,Map,Table}RPG/View/QuickEntryEditor.swift`
- **What:** Both consumers were removed in `34b71c2cd`; `onTextExtracted` and the environment key remain and nothing calls them.
- **Why:** The editors show a PDF pane that looks able to feed a selection into the entry text, but it does nothing; misleading API.
- **Action:** Either restore the feature or delete the parameter, key and editor closures.
- **Severity:** Medium (Verified by repository-wide grep)
- **Known:** audit 26 §9.5.

### 9.4 Seven copies of the die-type dispatch and of the generated-die boilerplate
- **Location:** `Modules/GameRPG/Table3D/GameInteraction.swift:62-109`, `GameObserver.swift:29-48`, `GameTableModel+Dice.swift:75-307`, `GameTableModel+DiceResults.swift:124-145`, `GameDie{3,4,6,8,10,12,20}.swift` (about 2,000 lines)
- **What:** Each new die kind must be added to eight `if let ... of: DieN.self` chains and cloned as another asset enum and equipment struct. The copies already drift: only the d20 restarts its toss sound unconditionally, and the rest-orientation guards differ.
- **Why:** Maintenance cost and silent divergence; a missed chain gives a die that can be picked up but not tossed.
- **Action:** One protocol for pool dice with a single lookup per kind and one generic asset cache; keep per-kind geometry and atlas code only.
- **Severity:** Medium (Verified)

### 9.5 Link drag/drop modifiers repeat the same 11-way module switch four times
- **Location:** `Modules/CoreRPG/ViewModifiers/LinkDragViewModifier.swift:38-178`
- **What:** Four modifiers map the module enum to one of 11 link-data types with the same case list; the drop paths already differ.
- **Why:** Adding a module means editing four switches; a missed case silently falls to the generic default.
- **Action:** One generic helper keyed by tag type and one module table.
- **Severity:** Medium (Verified)
- **Known:** audit 26 §9.23, referenced in audit 27 §9.

### 9.6 Oversized files with a clear split
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift` (1,282 lines), `FoundryRuleModels.swift` (849), `Controllable/ImportControllable.swift` (799), `Foundry/FoundrySystemPackageReader.swift` (754), `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift` (746), `Modules/RolePlayGameKit/Import/Foundry/FoundryImportView.swift` (715), `Modules/GameRPG/Statistics/Model/GameStatisticsTypes.swift` (709), `Modules/MapRPG/Controller/GameController+Pins.swift` (672), `Modules/CoreRPG/Persistence/CoreDataController.swift` (636), `Controllable/ItemControllable.swift` (633), `Modules/GameRPG/Table3D/GameTableEntities.swift` (627), plus about ten more between 500 and 600 lines (for example `GameMessagePipeline.swift`, `SharePlayJournalPublicationQueue.swift`, `ExportControllable.swift`, `EditControllable.swift`)
- **What:** More than 20 files exceed 500 lines; the agents proposed concrete splits for the Controllable and SharePlay files (for example `ImportControllable` into stream, apply and files extensions; the pending-operation queue out of `CoreDataController.swift`; import and merge settlement helpers out of `ItemControllable`).
- **Why:** These are the change hotspots of earlier audits and hide private helpers behind long extension blocks.
- **Action:** Pure moves with no behaviour change, one file per change.
- **Severity:** Medium

### 9.7 Unreferenced symbols and dead branches (grouped)
- **Location:** `Modules/CoreRPG/Navigator/Core/NavigationModifiers.swift:11-141` (unused vendored Navigator machinery); `Modules/CoreRPG/Sheet/SheetEntryConvertToGroupView.swift:18-22, 83-84, 157-175` (`alreadyGroup` step, placeholder "Not yet found"), `ScenesManager/Modifiers/SceneTrackerModifier.swift:42-92` (unused callbacks, Known §9); `Modules/CoreRPG/Files/FileManager+Coordination.swift:25-146` (unused coordinated file helpers); `Modules/GameRPG/SharePlay/RPGActivity.swift:17`; `Modules/GameRPG/Table3D/TableSeatPanelAnchor.swift:137-139`; `Modules/RolePlayGameKit/Import/Foundry/FoundryImportView.swift:11, 75-78, 158` (`isSelected`); `Modules/PdfRPG/Pdf/PdfWrapperView.swift:29, 57` and siblings (`horizontal` is false at every call site); `Modules/CharacterRPG/Model/ValueEntryModel.swift:97`, `Controller/DataController.swift:101-114` (entry `displayState` and the "Group" name check); `Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift:201-228` (write-only event columns, never-produced enum cases); `Modules/TableRPG/Model/TableGenerationModel.swift:87-208` (test-only members), Photo `degrees` has no writer
- **What:** Types, members and branches with no production caller.
- **Why:** Maintenance and confusion.
- **Action:** Delete after a repository-wide grep of `Modules Sources Tests`.
- **Severity:** Low

### 9.8 Duplicated code (grouped)
- **Location:** `Modules/CoreRPG/Editors/TextDoubleEditor.swift:70-201` and `TextIntEditor.swift:5-137` (about 80 percent identical); `Modules/GameRPG/GameViews/MasterGameScreen.swift:69-148` and `PlayerGameScreen.swift:43-130` (quit, window-prep, lifecycle); `Modules/AdventureRPG/View/DropChooseView.swift`, `EmptyDropButton.swift`, `PhotoDropSection.swift`, `DiceDropSection.swift` (copy-pasted drop areas); `Modules/RolePlayGameKit/Model/AppModel.swift:48-267` (tvOS branch duplicates four factory calls and the root manager); `Modules/WeatherRPG/View/WeatherStormEditor.swift:109, 131`, `WeatherThunderEditor.swift:82-128` versus `Model/WeatherLimits.swift:9-14` (slider ranges); `Modules/MapRPG/Map/MapPinViewModel.swift:184-195` (`copyPin` duplicates `MapPinModel.duplicate()`); reroll/coup/fumble option editors in Dice
- **What:** Copy-pasted logic in two or more files.
- **Why:** Drift risk.
- **Action:** Extract one shared type or constant per group.
- **Severity:** Low

## 10. Cross-cutting recommendations

- **Make every fix land on the sibling.** Four Mediums are an earlier fix that covered one path (§5.2, §5.3, §5.4, §6.2). When fixing one of these, grep for the twin path and add a test that goes through the other path too (undo vs save, mapper vs factory, every DataController vs the table-player one).
- **One validating decode at the persistence boundary.** §5.4 affects about 113 call sites; a single "unreadable stays unreadable" rule in the CRDT wrapper would close it for every module and make mixed-version CloudKit safe.
- **One import budget for hostile input.** §6.1, §6.3 and §6.4 are three instances of missing limits on package-supplied data (path scope, string length, path depth). A small shared "FoundryLimits" check (maximum text length, path components, nesting) used by the reader, factory and mapper would keep future importers from re-opening them.
- **Move large pure work off the main actor.** §3.3, §7.3, §7.5, §7.7 and §7.11 are all main-actor aggregation or conversion. Pure passes (summaries, digests, sanitising) are good `@concurrent` candidates; the models stay `@MainActor`.
- **Measure before the performance Mediums.** §7.2, §7.6 to §7.10 are unmeasured. Capture one Instruments trace per scenario (first sync of a large store, a 20,000-cell hex map, a Vision Pro table session) before changing code, as earlier audits already decided.
- **Keep GM-only visibility in one function.** §5.6 shows 2D and 3D disagreeing because placement and visibility use different locations. One "effective location" used by display, redaction, photo sharing and battle membership removes the class of bug.
- **Add a CI check for Siri/Shortcut paths that call module game-mode setters** (§5.1): only the game root should set `isGameMode`.
- **Verified sound (no finding):** the game message pipeline drain worker and continuation gates, join/reconnect, inbound byte budgets, GM-only redaction of hidden rooms and pins, `libraryWriteFilter`, player pin authorisation, ZIP/LevelDB/UniversalVTT parsing and path-safety, the privacy sanitiser, the folder-cycle guard (audit 27 §5.5), deterministic Adventure import ordering, entitlement and aps-environment Debug/Release pairs, app group and iCloud container consistency across targets, Bonjour services versus code.

## 11. What was NOT audited

- **Nothing was run on a device or simulator** except the clean iOS build. All runtime claims (hangs, races, shortcut conflicts, visionOS behaviour, SharePlay group effects) are read-only conclusions. The 3D table, TabletopKit, RealityKit and Game Center findings in particular need a device check.
- **Build settings, schemes, project structure** beyond the entitlements and Info.plist files read for §4.4 and §6. The macOS, tvOS and visionOS builds were not re-run (only the iOS Simulator build).
- **Tests:** `Tests/` (599 files) was used only to check whether something is covered or referenced; test quality and coverage were not assessed.
- **Localization wording:** only missing-bundle problems (§8.2) were noted.
- **Third-party packages** (`RPGTabletopGameContent` and other SPM content) as black boxes.
- **Skimmed or only partly read** (listed in each scope's findings file): about 9k of CoreRPG-A's 20k lines; some Sheet, LGViews and Tips files; `ViewportGeometry` past line 200 and the theme catalog/picker; the journal publication queue, the deferred delivery queue and journal ledger in GameRPG; `GameToolBar`, `EditMapToolBar`, overlay and popover geometry in MapRPG; `ExternalGameRootView`; RuleRPG root, route and detail views, `RuleCommands`, `RuleEntity`, `OpenRuleIntent`; several RolePlayGameKit layout views; audio volume and mini-bar views and the Adventure Create/Update/Delete/Search intents.
- **Not re-verified:** the full open list of audit 27; items it marks open were only checked where a scope agent touched the same code.
- **No profiling:** all performance findings are from reading code; none was measured.

## 12. Verification

Re-opened by the lead (this session) against the working tree:

- **§5.1** — opened `Modules/AdventureRPG/Intent/StartAdventureGameIntent.swift`, lines 29-38: the intent calls the adventure game controller's `startGame(with:)`, then `root.startGame()`, then navigates; opened `Modules/GameRPG/Root/GameRoot+Master.swift`, lines 40-91, which shows what a real start does (game config, master and player controllers, `gameConfig.state = .started`) that the intent skips; opened `AdventureRootModel.swift`, lines 338-344 (sets `isGameMode` on the root and all sibling roots) and `Modules/AdventureRPG/Controller/GameController.swift`, lines 64-69; a repository grep shows `root.startGame()` has exactly three callers (`GameRoot+Master.swift:75`, `GameRoot+Player.swift:84, 134`) besides the intent at `StartAdventureGameIntent.swift:35`. The `ItemControllable.replace` game-memory effect at `ItemControllable.swift:235` was read by the scope agent, not re-opened by the lead.
- **§6.1** — opened `Modules/CoreRPG/Files/FileUrl.swift`, lines 185-229 (`.local` shares the `.appCloud/.icloud/.newCloud` branch, whose check is `namesFileBelowStorageRoot`; that check does not drop a container prefix when no `Documents` component exists, so `/etc/hosts` has a non-empty component list and is returned unchanged) and `LocationFileManager.swift`, lines 70-90 (`.local` returns the raw URL when no `Documents` component exists).
- **§6.3** — opened `FoundryTextDecoder.swift`, lines 25-74: pattern `(?is)<\s*/?\s*[A-Za-z][^>]*>` is applied over the whole string with no bound, which gives quadratic scanning when no `>` follows; the timings in §6.3 are the scope agent's measurement, not re-run. Rated Medium, not High (the scope agent's rating), because it needs a hostile or broken package that the user chooses to import.
- **§6.4** — opened `FoundryValueHierarchy.swift`, lines 65-124: `insert` recurses once per path component, `materialized` builds `parentPath + [component]` at every level, and nothing limits the number of components. Same demotion to Medium as §6.3.
- **§5.9** — opened `Modules/CharacterRPG/Controller/EditController.swift`, lines 296-331: `termineType` returns `.number` for empty or whitespace-only content when the current type is text (line 323); the "= 0 Error" display was traced by the scope agent only.
- **§5.6** — opened `Modules/MapRPG/Map/MapPinPlacement.swift`, lines 20-28: `displayPins` cascades pins without a location into `map.entries.first` (the display half is confirmed); the player-side visibility, redaction and battle rules reading the raw location are the scope agent's trace.
- **§4.1** — grepped the iOS 27.2 SDK `FoundationModels.swiftinterface`: `LanguageModelError` exists with `contextSizeExceeded`, `rateLimited`, `guardrailViolation`, `refusal`, `unsupportedLanguageOrLocale` and `timeout` cases; the repository's catch sites match only the older `GenerationError`, per the scope agent.

Build ground truth: `xcodebuild -workspace MasterRPG.xcworkspace -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 18 Pro' clean build` — `** BUILD SUCCEEDED **`, no Swift warnings.

The one High (§5.1) was verified as above. There are no Critical findings, so there is no Critical to verify.
