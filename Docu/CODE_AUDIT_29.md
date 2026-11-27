# MasterRPG Code Audit 29

Generated 2026-11-26. Snapshot of `main` at `7402237c8` (clean tree). Read-only audit of every module under `Modules/` (15 modules) and every target under `Sources/` (MasterRPG, MasterTV, RPGShare, DiceRollerWidget): about 226k Swift lines in about 2,000 files. `Tests/`, `Snapshots/` and SPM packages are excluded.

**Method.** There were four folder-scoped agents running in parallel, all on one shared brief:

| Agent | Scope | Lines |
|---|---|---|
| A | `CoreRPG` | 71k |
| B | `GameRPG` | 50k |
| C | `MapRPG`, `RolePlayGameKit`, `GeneratorRPG`, `RuleRPG`, `Sources/` | 47k |
| D | `AdventureRPG`, `AudioRPG`, `CharacterRPG`, `DiceRPG`, `PdfRPG`, `PhotoRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG` | 58k |

**Compiler.** A clean iOS build (`MasterRPG` scheme, iPhone 18 Pro simulator, fresh DerivedData) succeeded with **zero Swift compiler warnings**. The only output was two AppIntents "metadata extraction skipped" notices. No finding is therefore derived from compiler output, and the concurrency findings come from reading the code.

**Prior audits.** The previous report is `Docu/CODE_AUDIT_28.md` (2026-11-21). Findings it already listed that are still present in today's code are marked **Known: audit 28 §N**. Items fixed since then are not repeated.

**Overall verdict:** 0 Critical, 2 High, 25 Medium and 47 Low (74 numbered findings, several Low ones grouped).

The transport, message pipeline and SharePlay core held up under a full read: continuations are balanced, buffers are bounded, and the banned APIs from CLAUDE.md are absent everywhere. So are TODO/FIXME markers, `#if false` blocks, GCD, `try!`, `as!` and `fatalError`.

The remaining risk sits in three places:

1. **The boundary between the library copy and the game copy of an item.** Game memory can alias the library instance (§5.1). Forced saves during a game build on the game copy (§5.2). Memory-only edits still change the persisted link register and tag counts (§5.3). All three put session state into permanent, synced data. Only Map has a `libraryWriteFilter`.
2. **Game broadcast discipline.** A dedupe log only sees its own sends (§5.6). A 2D drop path never broadcasts (§5.8). Removing the playing audio sends a toggle, not a pause (§5.9). A retried audio play can overtake a pause (§3.2).
3. **Twin drift.** A fix landed in one module but not in its siblings:
   - `isSame` (§5.10)
   - `nonisolated(unsafe)` entity statics (§3.5)
   - `syncGameMemory: false` (§5.2)
   - analyzer error handling (§4.1, §9.1)
   - Foundry link neutralisation (§6.1)

**Confidence note:** nothing was run on a device. Each finding gives its confidence (Verified / Likely / Unverified). The lead re-opened the cited lines of every High finding and twelve Medium and Low findings (see §12).


## 0. Fix status (2026-11-27)

Fixed in the working tree (uncommitted) on `develop`. Every change carries a `See CODE_AUDIT_29 §x` comment. All four platforms build (iOS, macOS, tvOS, visionOS). Nothing was run on a device.

**User decisions:** §5.16 uses the last *opened* room. §6.2 reveals a hex cell's rooms by polygon overlap. §6.6 keeps PCC dormant. §8.8 is deferred. The refactors §9.9, §4.3 and §7.1/§7.3 were wanted and are done.

| § | Status | Note |
|---|---|---|
| 3.1 | Fixed | Seat re-claim deferred out of the observer callback |
| 3.2 | Fixed | Play generation token: a retry no longer overtakes a pause |
| 3.3 | Fixed | File naming, paths and moves are `@concurrent` |
| 3.4 | Fixed | `FoundryValuePrepass` builds the value plans off the main actor |
| 3.5 | Fixed | Computed static entity properties |
| 3.6 | Fixed | Byte compare and temp cleanup in a detached utility task, one directory listing |
| 3.7 | Fixed | Pdf highlight/navigation tasks owned and cancelled; GeneratorTaskWait waiter cancelled; capture check synchronous |
| 3.8 | Fixed (comment) | Comment corrected. No cancel guard: the view cancels on disappear, a guard would drop a finished edit |
| 3.9 | Fixed | `PinCutoutCache.Box` is checked `Sendable` |
| 4.1 | Fixed | `FoundationModelsErrorHandler` matches the current error types |
| 4.2 | Fixed (dice) | Dice snapshot uses real data. Content widgets stay closure-based: WidgetKit has no async `TimelineProvider` for static widgets |
| 4.3 | Fixed | About 2,000 renames in the Foundry/Import/Rule/Game/Dice code. `CodingKeys` keep the stored and sent `ID` keys; Core Data attributes, TabletopKit and Apple API names keep `ID` |
| 4.4 | Fixed | `chartPlotStyle` overlay instead of `GeometryReader` (not visually verified) |
| 5.1–5.3 | Fixed | Game memory holds a copy; forced saves build on the library instance; memory-only edits leave the link register and tags alone |
| 5.4, 5.13 | Fixed | Duplicate rows: writes go to the kept row; the repair rolls back on error |
| 5.5, 9.4 | Fixed | One header save with one undo step; shared re-path helper |
| 5.6 | Fixed | `BattleRoundBroadcastLog` sees every send |
| 5.7 | Fixed | Seat dice resolved by sender id |
| 5.8 | Fixed | 2D drop broadcast by the GM, gated for players |
| 5.9–5.12 | Fixed | Pause on remove; `isSame` ignores CRDT clocks; player dice lookup before clearing; Reset Data covers the Generator store |
| 5.14 | Fixed | `updates()` skips deleting ids; the history cursor is a persisted `NSPersistentHistoryToken` per actor |
| 5.15, 5.16 | Fixed | `MapPinPlacement.defaultRoom(in:)` is the one rule; battle opponents come from the last opened room |
| 5.17 | Fixed | One save ("Added Monster") |
| 5.18 | Fixed | Cancelled batch items go back to pending; Foundry archive save is shielded from cancellation |
| 5.19–5.28 | Fixed | As described in each finding; §5.25 uses ear-clipping triangulation (`PolygonTriangulation`) |
| 6.1 | Fixed | Composed rule text and names neutralised (`inertText`/`safeText`) |
| 6.2 | Fixed | `MapEntryModel.overlaps(_:)` (polygon overlap; touching borders do not count) |
| 6.3–6.5 | Fixed | Hidden attacker not spoken; name fenced; user-facing model errors without `debugDescription` |
| 6.6 | Decided | Kept dormant (user decision) |
| 7.1 | Fixed | Own private-queue statistics context; batch delete with merge |
| 7.2 | Fixed | Dictionary lookup of child rows |
| 7.3 | Fixed | `ImageMemoryBudget` shared by all module caches (384 MiB, LRU across caches); `ObjectCache` byte limits and memory-warning trim |
| 7.4 | Fixed | Dice result scan only while dice may be moving, plus a 250 ms idle scan |
| 7.5 | Open | Needs profiling first, as the finding says; not done |
| 7.6–7.9 | Fixed | Hash computed once and cache seeded; cutout outcomes and pruning; one combined extraction save; preview decoded off the main actor |
| 8.1 | Fixed | Space tutorial and help texts localised (iOS device only; checked with a generic iOS build) |
| 8.2 | Open | Needs a decision: localising at mapping time makes the stored text, and so the item version, differ between devices that import the same source in different languages |
| 8.3 | Fixed | |
| 8.4 | Fixed | 2D/3D "Unnamed room"/"Hex cell" labels; 3D room names refresh idempotently (pin labels already did); "Untitled" and inflected counts in the batch views |
| 8.5 | Fixed | Actions `@ObservationIgnored`. No once-only guard on visionOS: the table window sets the actions of a live scene again after the launch window closes |
| 8.6 | Fixed | The view asks for its controller in `.task(id:)`, not in `body` |
| 8.7 | Partly | The named files use `@ScaledMetric` (same default values); the other GameRPG sites are left for later |
| 8.8 | Deferred | User decision |
| 9.1, 9.2 | Fixed | `AnalyzerRunner`, `BatchItemRunner`; one `applyExtractedContent` in GeneratorRPG |
| 9.3 | Fixed | `exportedFileUrl` / `exportedThumbnailPngData` on `ItemControllable` |
| 9.5 | Fixed | `AppModel.makeNavigator()`, `navigatorExecutionDelay` |
| 9.6 | Fixed | Single `safeText` call |
| 9.7 | Fixed | `Modules/GameRPG/Preview/GameStatisticsFixture.swift` |
| 9.8 | Fixed | Lazy `logGameController`, `hasNoLinkedEntries`, `charactersPerToken`, comment, indentation, `maximumEmbeddedDepth` |
| 9.9 | Fixed | Every file in the table is now under 500 lines. `MasterController+AudioMessages` was split by file (`+AudioPrefetch`), not into a separate state-machine type. The 500–540 group is unchanged, as the finding suggests |
| 9.10 | Fixed | `GameMetrics.Pin`, room outline opacity, `MapRoomStroke`, `MapFogTilePlanner.maximumTilesPerAxis`, widget relevance, `ByteUnit.mebibyte`, `CoreDataFetchLimits.batchSize`. The per-module `Limits` enums are not done |

New tests: `PolygonTriangulationTests`, `MapEntryOverlapTests` (overlap and default room), `ImageMemoryBudgetTests`, plus the earlier `BattleRoundBroadcastLog` tests.

---

## 1. Executive summary

1. **[High] Game memory stores the library instance itself, so game-only edits change the library object** — §5.1 — `Modules/CoreRPG/Controllable/GameControllable.swift:82-93, 269-274, 349-354`
2. **[High] Forced saves during a game build on the game copy and write its session state into the library (header editor, Character inline editor, Character add-entry)** — §5.2 — `Modules/CoreRPG/Controllable/EditControllable.swift:432-434`, `Modules/CharacterRPG/Controller/EditController+InlineEditor.swift:122-138`
3. **[Medium] Memory-only game edits change the persisted link register and tag counts, and nothing reverts them** — §5.3 — `Modules/CoreRPG/Controllable/EditControllable.swift:449-458`
4. **[Medium] Battle-round broadcast dedupe goes stale after 3D/2D edits, so a revert (for example a revive) is never sent** — §5.6 — `Modules/GameRPG/BattleRound/BattleRoundBroadcastLog.swift:7-38`
5. **[Medium] Dropping a Character or Photo on the 2D game map is never broadcast by the GM, and players can drop local-only pins** — §5.8 — `Modules/MapRPG/Map/MapEditor.swift:305-338`
6. **[Medium] Removing the playing audio in a game tells players to play the track instead of pausing** — §5.9 — `Modules/AudioRPG/Root/AudioRootModel+Playback.swift:174-180`
7. **[Medium] Writes and deletes hit an arbitrary row of a duplicated uuid, not the row the startup repair keeps (lost edits, deleted items come back)** — §5.4 — `Modules/CoreRPG/Persistence/CoreDataController.swift:279-290, 407-419, 465-474`
8. **[Medium] The item header editor writes back all four fields from its open-time snapshot, which reverts concurrent sync changes** — §5.5 — `Modules/CoreRPG/LGViews/ItemHeaderEditorView.swift:17-21, 84-97`
9. **[Medium, security] Foundry composed rule text, reference targets and effect paths are still not link-neutralised** — §6.1 — `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Rules.swift:179-323` (Known: audit 28 §6.2)
10. **[Medium] Foundation Models errors are matched only as the deprecated `GenerationError`, now at eight catch sites** — §4.1 — `Modules/GeneratorRPG/BasicAI/Errors/FoundationModelsError.swift:8-30` (Known: audit 28 §4.1)

Counts: Critical 0 · High 2 · Medium 25 · Low 47 (74 numbered findings).

---

## 2. Quick wins (≤30 min each)

- **§5.1** Insert `copy()` in `setCurrent(itemId:)`, `completeReveal` and the `applyGameUpdate` fallback, as `hasItem` already does.
- **§5.2 (first part)** Pass `syncGameMemory: false` in Character `saveGameDataToPermanent`, as Adventure `saveTablePlayers` does.
- **§5.8** Gate the 2D game drop on `session.mapMode == .gameMaster` and call `session.broadcastMapEdit()` after it.
- **§5.9** Use `gameController.playingRootId` and `requestPause()` in `AudioRootModel.remove(id:)`.
- **§5.11** Remove `replacedId` from `gameModel.items`/`itemData` directly in Dice `addGameDiceResult`.
- **§5.12** Reset `generatorRoot` in `AdventureRootModel.resetData()`.
- **§3.1** Defer `reclaimLocalSeat()` into a main-actor `Task`.
- **§3.5** Turn the Character and Dice entity `nonisolated(unsafe)` statics into computed statics.
- **§6.3** Use `activeAttackerName(hidingPins:)` in `GameIntentDialog.activeName`.
- **§5.13** Use `saveCoreDataThrowing()` plus a rollback in the duplicate-row repair.
- **§5.19** Add `guard !isSaving` in the share extension's `saveContent()`.
- **§5.18** Add `catch is CancellationError` in the text batch, and add a subject-neutral `modelUnavailable` message.
- **§7.2** Use a `[UUID: Child]` dictionary in `syncEntries`.
- **§8.3** Localise "Validating Character Data".
- **§5.21** Align the Character and Weather `DataController` category defaults with the models.

---

## 3. Concurrency

### 3.1 Seat re-claim mutates the TabletopKit session synchronously inside its observer callback
- **Location:** `Modules/GameRPG/Table3D/GameObserver.swift:38-41` (call), `:68-76` (`reclaimLocalSeat()` calls `tabletop.claimSeat(matching:)`)
- **What:** `playerChangedSeats` calls `reclaimLocalSeat()` inline. Every other follow-up in the same callback is deferred through `Task { @MainActor … }`.
- **Why:** The comment at `:44-48` of the same file records that reentrant session mutation from this callback "corrupted it outright". The CLAUDE.md Table3D rules forbid it. The path runs exactly when a seat is lost during a SharePlay rebind.
- **Action:** Defer the re-claim into a main-actor `Task`. Inside the task, re-check `canAutoClaimSeat` and that the local player is still seatless.
- **Severity:** Medium · Confidence: Verified (lead re-opened)

### 3.2 A retried audio play is re-inserted as pending after a suspension, overtaking a pause
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:532-551` (retry task), `:200-211` (`startPendingAudioPlay` awaits `recordAudioMasterVersions`, then writes `pendingAudioPlays[data.id]`)
- **What:** The retry task unregisters itself before awaiting `startPendingAudioPlay`. That function suspends, then stores the play as pending with no check for supersession.
- **Why:** A pause or a newer play that lands during the suspension cannot cancel the retry (`clearPendingAudioPlays` no longer sees it). The old play is then started for players after the GM stopped it. Player play requests run on the master pipeline (`:69`), while GM actions run on `GameRoot.scheduleNetworkAction` (`Modules/GameRPG/Root/GameRoot.swift:355-370`), so the two are not serialised.
- **Action:** Give each pending play a token and re-check it after every await. Keep the retry task registered until it finishes. Route player play requests through the GM action chain.
- **Severity:** Medium · Confidence: Likely
- **Known:** the remaining gap of the "pending audio play not superseded" finding of the 2026-11-07 audio audit

### 3.3 File naming, path resolution and moves for imports run on the main actor
- **Location:**
  - `Modules/CoreRPG/Controllable/ImportControllable.swift:627, 664-668` (`@MainActor addFile`)
  - `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:157-162, 367-395` (`uniqueDestination`, `importDestination`)
  - `Modules/CoreRPG/Files/FileUrlDataController+Manage.swift:17-29` (`move(fileUrl:to:)`)
  - `Modules/CoreRPG/Files/CloudDocumentController.swift:209-234` (`suggestedFileName`/`takenFileNames`, synchronous `contentsOfDirectory`), `:309-324`, `:370-379` (`canonicalPath`, one `fileExists` per path component, called twice)
- **What:** These are plain `async` methods on `Sendable` structs. With approachable concurrency they run on the `@MainActor` caller and list folders synchronously.
- **Why:** On iCloud Drive each call can block on file-provider IPC. Every imported file, and every file moved by a folder rename, lists the whole target folder on the main thread. CODE_AUDIT_21 §3.7 moved the neighbouring accessors off the main actor; these were missed.
- **Action:** Mark them `@concurrent`, or run their bodies through `runOffCallerExecutor`. Keep the `referencedFileUrls` snapshot on the main actor.
- **Severity:** Medium · Confidence: Verified (call chain), not profiled

### 3.4 The Foundry mapping pass still runs mostly on the main actor
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift:179-200, 265-271, 339-346`, `FoundryVTTDomainMapper+SharedHelpers.swift:276-335`, `FoundryVTTDomainMapper+Documents.swift` (per-document work)
- **What:** `FoundryMappingState` is `@MainActor`. Link rewriting, id hashing, value-hierarchy flattening and model construction run on the UI thread. Only the HTML-to-text pre-pass moved off the main actor.
- **Why:** A large system package stalls "Preparing import review". Only the `Task.yield` checkpoints keep the UI alive.
- **Action:** Move id derivation and value flattening into the nonisolated pre-pass, and keep only model construction on the main actor. Measure with a large package first.
- **Severity:** Medium · Confidence: Likely
- **Known:** audit 28 §3.3 (partly fixed)

### 3.5 Character and Dice entities still keep `nonisolated(unsafe)` statics (twin of the AdventureEntity fix)
- **Location:** `Modules/CharacterRPG/Intent/CharacterEntity.swift:128, 154`, `Modules/DiceRPG/Intent/DiceEntity.swift:164, 190`. The fixed twin is `Modules/AdventureRPG/Intent/AdventureEntity.swift:134-166`.
- **What:** The `QueryProperties`/`SortingOptions` builders are `nonisolated(unsafe) static let`. AdventureEntity builds them per access.
- **Why:** These are the only `nonisolated(unsafe)` statics left in the content modules. They opt non-Sendable values out of race checking, which is the exact pattern audit 26 §3.11 removed from Adventure.
- **Action:** Turn them into computed `static var`s, as in AdventureEntity.
- **Severity:** Medium · Confidence: Verified

### 3.6 Holding peer bytes compares up to 256 MiB and lists the temp directory on the main actor
- **Location:** `Modules/CoreRPG/Files/PeerFileDataStore.swift:50-76, 105-112`; callers `Modules/CoreRPG/Controllable/ImportControllable.swift:646, 681, 688`
- **What:** `hold(_:for:)` compares the old and new `Data` (up to `maximumSourceFileBytes`). `removeTemporaryCopy` lists the temporary directory once per evicted entry. Every caller is `@MainActor addFile`.
- **Why:** A game delivery of a large PDF or 3D file to a player freezes the UI for the compare and the listings.
- **Action:** Compare the content hashes the import already has, and do the cleanup in a `@concurrent` helper.
- **Severity:** Low · Confidence: Verified

### 3.7 Unowned helper tasks (grouped)
- **Location:**
  - `Modules/GeneratorRPG/Controller/GeneratorController.swift:470-479` (`GeneratorTaskWait`: a timer task and a waiter, neither cancelled when the gate opens)
  - `Modules/PdfRPG/Pdf/PdfWrapperView.swift:65-75` (bookmark `Task` sleeps, then calls `go(to:)`, capturing the `PDFView` strongly), `:185-195` (search highlight `Task`)
  - `Modules/SpaceRPG/Record/AppDataModel.swift:15-22` (a `Task { @MainActor … }.value` used only to hop actors)
  - `Modules/MapRPG/Map/MapEditorCanvasGestures.swift:212-216` and `Modules/MapRPG/Controller/EditController.swift:310` (documented as intentional)
- **What:** Fire-and-forget tasks without stored handles.
- **Why:** A superseded generator request leaves two tasks behind. A fast next/previous, or a closed viewer, can jump the PDF page or restore an old highlight after the user has moved on.
- **Action:** Store and cancel the handles: one task per coordinator in `PdfWrapperView`, with a weak `pdfView` capture. Cancel both handles after `gate.wait()`. Make `isSupported()` `@MainActor`.
- **Severity:** Low · Confidence: Verified
- **Known:** audit 28 §3.4 and §5.26 (the Pdf highlight task); the generator and Pdf `makeView` sites are new

### 3.8 The 3D room toggle's "a second tap cancels the first" comment is not true
- **Location:** `Modules/GameRPG/Table3D/GameTableView+PlatformFlat.swift:130-132`, `Modules/GameRPG/Table3D/GameTableModel+ToolBar.swift:108-129`
- **What:** The toggles mutate the map, await the fog render, then always sync pawns and broadcast. None of these steps checks `Task.isCancelled`.
- **Why:** The outcome is correct only because both broadcasts carry the current state. The comment invites a wrong fix later.
- **Action:** Reword the comment to "a second tap supersedes the render", and optionally skip the first broadcast when cancelled.
- **Severity:** Low · Confidence: Verified

### 3.9 `PinCutoutCache.Box` is `@unchecked Sendable` around an immutable `CGImage?`
- **Location:** `Modules/PhotoRPG/Controller/PinCutoutCache.swift:36-39`
- **What:** A final class with one `let` field uses an unchecked conformance.
- **Why:** The unchecked conformance hides any future mutable field from the checker.
- **Action:** Declare it `Sendable`, and keep `@unchecked` only if one of the SDKs rejects that.
- **Severity:** Low · Confidence: Unverified (not compiled on all five SDKs)

---

## 4. API modernity

### 4.1 Foundation Models errors are matched only as the deprecated `GenerationError`
- **Location:**
  - `Modules/GeneratorRPG/BasicAI/Errors/FoundationModelsError.swift:8-30, 44, 99-100`
  - `Modules/GeneratorRPG/Controller/GeneratorController.swift:244, 367`
  - `Modules/GeneratorRPG/Intent/RunGeneratorIntent.swift:64`
  - `Modules/GeneratorRPG/BasicAI/Providers/PdfSummaryAnalyzer.swift:118`, `TableSummaryAnalyzer.swift:48`, `CharacterSummaryAnalyzer.swift:56` (new since audit 28), `PdfContentExtractor.swift:134`
- **What:** On iOS 27 the runtime throws `LanguageModelError`. All eight catch sites match only `LanguageModelSession.GenerationError`. Only `ConversationEngine.swift:115-124` handles both.
- **Why:** The guardrail, refusal and unsupported-locale messages never show. `RunGeneratorIntent` lets the error escape as an intent failure instead of a spoken dialog.
- **Action:** Use one `FoundationModelsErrorHandler.message(for: any Error, subject:)` with an availability-gated `LanguageModelError` branch, and route all eight sites through it (see §9.1).
- **Severity:** Medium · Confidence: Verified (catch sites)
- **Known:** audit 28 §4.1 (still open, one more site)

### 4.2 Content widgets use the closure-based `TimelineProvider`; the dice widget snapshot ignores real data
- **Location:** `Sources/DiceRollerWidget/ContentWidgets.swift:25-45`, `Sources/DiceRollerWidget/DiceRollerProvider.swift:22-28`
- **What:** `getSnapshot`/`getTimeline` use completion handlers. `snapshot(for:in:)` always returns `.preview`, even when `context.isPreview` is false.
- **Why:** This is the legacy API shape. Transient displays such as the Smart Stack show a fake roll instead of the last real one.
- **Action:** Move to the async provider. Return the stored snapshot when `!context.isPreview`.
- **Severity:** Low · Confidence: Verified
- **Known:** audit 28 §4.4 (the closure provider)

### 4.3 `ID`/`URL` casing against the project's `Id`/`Url` rule
- **Location:**
  - `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:31, 35, 99, 117, 141-142, 266, 284`
  - `Modules/GameRPG/Controller/LogGameController.swift:90, 164, 186, 273-294`
  - `Modules/GameRPG/Root/GameRoot.swift:47`
  - `Modules/GameRPG/SetupViews/SelectedAdventureView.swift:13`, `SelectedPlayerView.swift:12`, `ImportRouteDestinationView.swift:23`
  - `Modules/DiceRPG/Controller/GameController.swift:302-307`
  - The RolePlayGameKit Foundry mapper (`sourceID`, `stableID`, `parentID` …, about 650 occurrences) and RuleRPG (about 40)
  - `Modules/RolePlayGameKit/Model/AppModel.swift:45`, `AppModel+Routing.swift:11-37`
- **What:** Newer code uses `ID`/`UUID`/`URL` suffixes, which CLAUDE.md forbids.
- **Why:** The naming convention drifts. The Foundry names mirror CoreRPG Foundry types, so renaming them crosses module boundaries.
- **Action:** Rename GameRPG and Dice now, keeping `@AppStorage` keys unchanged. For the Foundry stack, either rename it in one mechanical change together with CoreRPG or record it in CLAUDE.md as an exception.
- **Severity:** Low · Confidence: Verified

### 4.4 `GeometryReader` in the dice chart overlay
- **Location:** `Modules/GameRPG/Statistics/View/GameStatisticsDiceChart.swift:36`
- **What:** The annotation is placed through `GeometryReader`.
- **Why:** CLAUDE.md prefers newer alternatives. `chartOverlay` with `ChartProxy` gives the plot frame directly.
- **Action:** Use `.chartOverlay { proxy in … }`.
- **Severity:** Low · Confidence: Verified

---

## 5. Bugs / logic errors

### 5.1 Game memory stores the library instance itself, so game-only edits change the library object
- **Location:**
  - `Modules/CoreRPG/Controllable/GameControllable.swift:82-93` (`setCurrent(itemId:)` inserts `itemControllable.item(for:)` without `copy()`)
  - `:269-274` (`completeReveal` inserts `itemSync(for:)`)
  - `:349-354` (`applyGameUpdate`: `gameItem ?? itemControllable.itemSync(for:)`)
  - Compare `:71-76` (`hasItem` copies)
  - Mutation site: `Modules/CoreRPG/Controllable/ItemControllable.swift:542-549` (`replaceInGameMemory` mutates the existing game instance in place)
  - Lookup: `Modules/CoreRPG/ItemList/ItemDataModel.swift:107-112`
- **What:** When an item has no game copy yet, the lookup returns the library instance from `itemData`. These three paths put that same object into `gameItemData`. From then on, every memory-only game edit (`replace(… forceSave: false)` → `replaceInGameMemory` → `existing.replace(with:)`) mutates the library object.
- **Why:**
  - Session state shows in the library during and after the game: a changed Table or Weather on the master, or a player's revealed Photo/Table/Space/Character.
  - The next library write of that item persists it to Core Data and CloudKit on every device.
  - `applyGameUpdate` reaches the fallback whenever a delivered package merges as unchanged, which is the normal case for a player that already has the item.
  - CODE_AUDIT_21 §5.31 fixed exactly this aliasing in the opposite direction (`persistFromGame`).
- **Action:** Insert `copy()` in all three paths, or make `ItemGameModel.insert/apply/append` copy any instance that is `===` to the library instance. Add a test that edits a revealed item in game mode and checks that the library instance is unchanged.
- **Severity:** High · Confidence: Likely (aliasing verified by the lead; the user-visible effect was not run)

### 5.2 Forced saves during a game build on the game copy and write session state into the library
- **Location:**
  - `Modules/CoreRPG/Controllable/EditControllable.swift:432-434` (`editModel(for:)` → `itemSync(for:)`, which prefers the game copy), `:89-94` and `:98-191` (every `reset…` builds on `editModel`)
  - `Modules/CoreRPG/LGViews/ItemHeaderEditorView.swift:87-97` (`forceSave: true`)
  - `Modules/CharacterRPG/View/CharacterAddEntryOverlay.swift:153-163` (`addForcingPersistence`)
  - `Modules/CoreRPG/Controllable/ItemControllable.swift:228-264` (the default `syncGameMemory: true`)
  - The opposite direction: `Modules/CharacterRPG/Controller/EditController+InlineEditor.swift:122-138` (`saveGameDataToPermanent`)
  - The correct twin: `Modules/AdventureRPG/Controller/GameController.swift:112`
  - The only filter: `Modules/MapRPG/Root/MapRootModel.swift:145`
- **What:** Two failure directions:
  - **Game copy into library:** the header editor and Character add-entry force-save a copy of the *game* copy. `replace(…forceSave: true)` writes all of it, session fields included, into the library. Only Map strips session content with a `libraryWriteFilter`.
  - **Library over game copy:** `saveGameDataToPermanent` copies the library item with the one edited entry and force-saves it with the default `syncGameMemory: true`, so `syncGameMemoryIfLoaded` overwrites the game copy with library values.
- **Why:**
  - Renaming a revealed character during a game persists its in-game hit points and battle values as permanent values on every device.
  - A player's value change makes the master's other session-only changes on that character revert on screen.
  - The intents already refuse in-game items for this reason (`Modules/CoreRPG/Intent/IntentEntityHelpers.swift:169-178`).
- **Action:** For forced edits, build on `itemSync(for:noGame: true)`, apply only the changed fields, and mirror only those fields into the game copy, as `persistFileUrl` and `persistMembershipChange` do. Pass `syncGameMemory: false` in `saveGameDataToPermanent`. Ideally add one shared "persist these fields/this entry only" helper.
- **Severity:** High · Confidence: Likely (paths verified by the lead)

### 5.3 Memory-only game edits change the persisted link register and tag counts
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:449-458` (`saveChanges` updates the register before `replace`), `:111-120`, `:168-177`, `:193-198` (tag counts); `Modules/CoreRPG/Links/LinkRegisterController.swift:187` (`savePendingLinks`); `Modules/CoreRPG/Controllable/TagController.swift`
- **What:** In game mode the edit stays in game memory, but the register and tag changes go to the shared, synced Core Data tables. Nothing reverts them at `ItemGameModel.reset()`.
- **Why:** After the game, "used by" lists and delete warnings show phantom references. A link removed during the game is missing from the register, so deleting its target gives no warning and leaves a broken link. Tag suggestions drift the same way.
- **Action:** Skip the register and tag updates for memory-only writes, or keep a session overlay that is dropped at game end and then rebuilt from the library copies.
- **Severity:** Medium · Confidence: Verified (code path), impact Likely

### 5.4 Writes and deletes go to an arbitrary row of a duplicated uuid, not the row the repair keeps
- **Location:**
  - `Modules/CoreRPG/Persistence/CoreDataController.swift:279-290` (the flush uses `existingRowsInContext`)
  - `:407-419` ("the first fetched is taken", no sort)
  - `:509-524` (`fetchCoreData`: `objects.first`)
  - The survivor rule: `:465-474` with `Modules/CoreRPG/Persistence/DuplicateRowOrder.swift:55-80`
- **What:** With two rows for one uuid (for example the same package imported on two devices, CODE_AUDIT_21 §5.7), the flush updates or deletes whichever row the unsorted fetch returns. The startup repair keeps the row with the lowest record name.
- **Why:** Edits made to the losing row are deleted by the next launch's repair, on every device. A delete removes only one row, so the item comes back.
- **Action:** Pick the survivor with `DuplicateRowOrder` in the flush and delete the other rows in the same save. Delete all rows of the uuid for a delete operation.
- **Severity:** Medium · Confidence: Verified (code); the state needs two devices

### 5.5 The item header editor saves every field from the snapshot taken when it opened, as four saves
- **Location:** `Modules/CoreRPG/LGViews/ItemHeaderEditorView.swift:17-21` (state captured in `init`), `:84-97`; `Modules/CoreRPG/Controllable/EditControllable.swift:89-94` (`update` runs four `reset…` calls, each with its own save and undo step); the combined twin is at `:98-129`
- **What:** The name, description, category and tags captured when the editor opened are all written back, including fields the user never touched.
- **Why:** If a sync changed the description while the editor was open, a rename reverts it. The newer CRDT stamp makes the revert win on every device. One edit also creates up to four undo steps and four writes.
- **Action:** Pass only the changed fields and route `update` through the combined reset, extended with category (see §9.4).
- **Severity:** Medium · Confidence: Verified (lead re-opened)

### 5.6 Battle-round broadcast dedupe goes stale after edits on other paths, so a revert is never sent
- **Location:**
  - `Modules/GameRPG/BattleRound/BattleRoundBroadcastLog.swift:7-38`
  - `Modules/GameRPG/BattleRound/BattleRoundController.swift:260-271` (`setDead`), `:438-461` (`broadcast(mapId:)`)
  - `Modules/GameRPG/Table3D/GameTableModel+PinSelection.swift:244-257` (`addPinToBattleRound`)
  - `Modules/GameRPG/Table3D/GameTableModel+Broadcast.swift:110-117`
- **What:** The log records only `BattleRoundController`'s own sends and skips a send equal to the last one recorded. Its doc comment assumes that "every other change is sent by the path that made it", which does not hold for A→B→A sequences.
- **Why:**
  - Traced sequence: BattleRound sends map state M1. The 3D pin menu marks a pin dead and sends M2 outside the log. BattleRound `setDead(false)` brings the state back to M1, `shouldSend(M1)` returns false, and players keep seeing the pin dead.
  - The 3D add path also skips `synchronizeBattleDefenders`.
- **Action:** Record every map-state and battle-state send in the log (update it from `broadcastMapEdit`/`broadcastBattleRoundState`), or reset it whenever another path sends. Route 3D battle mutations through the controller's helper.
- **Severity:** Medium · Confidence: Verified (lead re-opened)

### 5.7 The 3D table resolves a seat's dice colour and results by display name
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+Dice.swift:135-175` (`:149`), `Modules/GameRPG/Table3D/GameDiceResultPopover.swift:35-62`, `Modules/GameRPG/SharePlay/RPGSharePlayController+TableCoordination.swift:102-152` (`seatPlayerNames`)
- **What:** The seat → player → dice mapping on visionOS matches on the display name.
- **Why:** Two participants with the same name (for example two default "Player" names) get each other's dice colour and result popover.
- **Action:** Carry the player id in the seat assignment and look dice up by id. Keep the name for display only.
- **Severity:** Medium · Confidence: Verified
- **Known:** CODE_AUDIT_26_Single game-a/game-b (still present on the 3D path)

### 5.8 2D game-map drop: not broadcast by the GM, not gated for players
- **Location:** `Modules/MapRPG/Map/MapEditor.swift:305-338` (game branch `:314-335`), `Modules/MapRPG/Map/RootCanvasMap.swift:72-84`; compare `Modules/MapRPG/Map/GameToolBar.swift:215-217`
- **What:** In the game branch, a dropped Character or Photo calls `addMonsters` and `addPhotoPins` and stops, with no `session.broadcastMapEdit()`. The drop branch does not check `session.mapMode`, and the player view gets the same `dropDestination`.
- **Why:** Players don't see the GM's dropped pins until an unrelated edit or "Refresh Shared Map". The toolbar's "Choose Pins" path does broadcast. On a player's device a drop creates local-only pins that diverge from the shared map.
- **Action:** Return early unless the mode is `.gameMaster`, then call `broadcastMapEdit()` (which honours "pause sharing"). Alternatively, don't install the drop target in player mode. Add a test next to the ChooseMapPins test.
- **Severity:** Medium · Confidence: Verified (lead re-opened; not run on a device)

### 5.9 Removing the playing audio in a game broadcasts a play toggle, not a pause
- **Location:** `Modules/AudioRPG/Root/AudioRootModel+Playback.swift:174-180`; toggle semantics at `Modules/AudioRPG/Controller/GameController+Playback.swift:363-368`; `requestPause()` at `:379-381`
- **What:** `remove(id:)` compares `currentId` (the *track*) with `id` and sends `requestPlay(id:)`. That request is a toggle based on `isPlayingPlaylist(id:)`, which compares the playlist *root*.
- **Why:** When `id` is the current track, players are told to *play* it while it is removed locally. When `id` is a playlist root, no pause is sent and players keep playing.
- **Action:** Compare against `gameController.playingRootId` and send `gameController.requestPause()`.
- **Severity:** Medium · Confidence: Verified (lead re-opened)

### 5.10 `isSame` compares entries by position with `==`, which includes CRDT clocks (twin of the fixed Pdf version)
- **Location:**
  - `Modules/AudioRPG/Model/AudioModel.swift:140-155`
  - `Modules/PhotoRPG/Model/PhotoModel.swift:136-152`
  - `Modules/TableRPG/Model/TableModel+Persistence.swift:34-49`
  - `Modules/CharacterRPG/Model/ValueModel.swift:163-180`
  - `Modules/AdventureRPG/Model/AdventureModel.swift:232-250`
  - The fixed twin: `Modules/PdfRPG/Model/PdfModel.swift:145-163`
- **What:** Five models use synthesized `==` on `CRDT<…>` entry fields, by position.
- **Why:** The same item loaded twice reports "changed", which triggers redundant replaces, UI refreshes and possibly re-saves. A reordered list also reports "changed".
- **Action:** Port the Pdf implementation (a dictionary keyed by id, compared with `entry.isSame`) to all five.
- **Severity:** Medium · Confidence: Likely
- **Known:** audit 28 §5.23 covers the positional part for Audio, Photo and Table. §7.12 fixed Pdf. The Character and Adventure sites are new.

### 5.11 Replaced player dice stay in the game item list (sender cleared before the lookup)
- **Location:** `Modules/DiceRPG/Controller/GameController.swift:150-171`
- **What:** `playerDiceSenders[replacedId] = nil` (`:160`) runs before the `gameModel.items` lookup that relies on `isSamePlayer`, which then cannot match the old dice.
- **Why:** Every roll from a player with a known sender id adds an item and an `itemData` entry and never removes the old ones. Game memory grows, and stale dice rows stay for the session.
- **Action:** Remove `replacedId` from `gameModel.items`/`itemData` directly, or clear the sender after the lookup.
- **Severity:** Medium · Confidence: Verified (lead re-opened)
- **Known:** audit 28 §5.24

### 5.12 Reset Data skips the Generator store
- **Location:** `Modules/AdventureRPG/Root/AdventureRootModel.swift:285-292`; caller `Modules/RolePlayGameKit/Model/AppModel.swift:338-347`; root lists `Modules/AdventureRPG/Root/AdventureModuleRoot.swift:28-40`
- **What:** `resetData()` resets Adventure and every `siblingModuleRoots` entry. `generatorRoot`, which has its own Core Data store, is not in that list. `save()` flushes it separately.
- **Why:** After a destructive "Reset Data", the generator items and history survive while every other module is empty.
- **Action:** Reset `generatorRoot` explicitly, or document that generator data is intentionally kept.
- **Severity:** Medium · Confidence: Likely

### 5.13 The duplicate-row repair saves the shared context and swallows the error without a rollback
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:453-455, 499-501, 531-537`
- **What:** `fetchAndDelete` and `fetchId` (which runs on every sync batch with deletions, `SyncDataControllable.swift:105`) call `saveCoreData()`. That call only logs a failure and leaves the context dirty.
- **Why:** The next save of any module fails again or commits unexpected changes. Every other save path rolls back (CODE_AUDIT_17 §5.6).
- **Action:** Use `saveCoreDataThrowing()` plus `rollbackRestoringFlushedOperations(after:)`.
- **Severity:** Low · Confidence: Verified

### 5.14 Persistence and sync Lows still present
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:114-169` (`updates()` ignores `deletingIds`); `Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift:229-247, 300-302, 340-353` (the history cursor is a `Date`)
- **What:** Unchanged since audit 28.
- **Why:** A full reconciliation that runs during a delete can re-add the item. Transactions with equal timestamps can be skipped or merged twice.
- **Action:** As in audit 28.
- **Severity:** Low · Confidence: Verified
- **Known:** audit 28 §5.23

### 5.15 Unplaced pins follow three different "first room" rules
- **Location:** `Modules/MapRPG/Map/MapPinPlacement.swift:24-28`, `Modules/MapRPG/Controller/GameController+Pins.swift:265-283`, `Modules/MapRPG/Controller/GameController+Battle.swift:26-36`
- **What:** The rules differ:
  - Display uses `map.entries.first`, which can be a hidden room or a hex cell.
  - Player placement prefers a shown non-hex room.
  - Battle start uses `entries.first`.
- **Why:** A pin is drawn in one place for the GM and stored in another for players. On hex-only maps a battle can start with only one cell's pins as opponents.
- **Action:** Add one `MapPinPlacement.defaultRoom(in:)` helper and use it at all three sites.
- **Severity:** Low · Confidence: Verified

### 5.16 Battle opponents come from the last *toggled* room, but the comment says "opened"
- **Location:** `Modules/MapRPG/Controller/GameController+Battle.swift:26-30`, `Modules/MapRPG/Controller/GameController.swift:35-39, 59-65`
- **What:** `battleStartPins` reads `lastActivatedRoomId`, which also records closes. `lastOpenedRoomIds` exists and matches the comment.
- **Why:** If the GM closes a room just before starting a battle, the opponents come from the room that was just hidden.
- **Action:** Decide the intended rule (needs a user decision), then switch to the opened-room id or fix the comment.
- **Severity:** Low · Confidence: Verified (mismatch); intent unverified

### 5.17 Linking a Character into a map room saves up to three times
- **Location:** `Modules/MapRPG/Controller/EditController.swift:100-104, 433-449`
- **What:** The `.value` branch calls `addMonsters` (which saves), then `save(updated:message:"Added Monster")`, then `addLinkInEntry` (which saves again).
- **Why:** One gesture creates up to three undo steps and three game broadcasts.
- **Action:** Drop the middle save, and let the monster add and the link write share one save.
- **Severity:** Low · Confidence: Verified

### 5.18 Generator and Foundry cancellation and error-message Lows (grouped)
- **Location:**
  - `Modules/GeneratorRPG/View/BatchTextSummaryExtractionView.swift:271-285` (a cancellation is shown as "failed"; compare `BatchPdfSummaryExtractionView.swift:177-185`)
  - `Modules/GeneratorRPG/BasicAI/Errors/PdfSummaryAnalysisError.swift:23-27`, thrown by `TableSummaryAnalyzer.swift:19` and `CharacterSummaryAnalyzer.swift:29` ("PDF summary analysis requires it" shown for tables and characters)
  - `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:316-330` (a cancellation after commit becomes an "archive could not be saved" warning)
- **What:** `CancellationError` is not separated from real failures, and one error type is reused for the wrong subject.
- **Why:** Users see misleading failure rows and messages.
- **Action:** Add `catch is CancellationError`, and add a subject-neutral `modelUnavailable` (`FoundationModelsErrorHandler.Subject` exists).
- **Severity:** Low · Confidence: Verified

### 5.19 Share-extension Save can run twice
- **Location:** `Sources/RPGShare/SharingView.swift:180-205, 336-341`
- **What:** `saveContent()` has no `guard !isSaving`. The button starts a new `Task` on every tap, and `.disabled(isSaving)` only applies after the next render.
- **Why:** A fast double tap can create two items.
- **Action:** Add `guard !isSaving else { return }` before setting the flag.
- **Severity:** Low · Confidence: Likely

### 5.20 Start Adventure Game intent says "a game is already running" when the game hook is not registered
- **Location:** `Modules/AdventureRPG/Intent/StartAdventureGameIntent.swift:37-41`
- **What:** `root.selectAdventureForGame?(target.id) ?? false` treats a nil hook as a refusal.
- **Why:** On a cold Siri launch, or a window where the game module has not set the hook, the user gets a false message.
- **Action:** Handle a nil hook separately: navigate and say the Game tab will open, or throw a specific error.
- **Severity:** Low · Confidence: Likely

### 5.21 Category defaults in the Core Data mapping differ from the model defaults
- **Location:** `Modules/CharacterRPG/Controller/DataController.swift:27` (`.game`) vs `Modules/CharacterRPG/Model/ValueModel.swift:12` (`.character`); `Modules/WeatherRPG/Controller/DataController.swift:27` (`.adventure`) vs `Modules/WeatherRPG/Model/WeatherModel.swift:12` (`.scenario`)
- **What:** A nil or unknown stored category maps to a different category than a new item gets.
- **Why:** Older or empty records show under the wrong filter. For Character, `.game` is not even one of its `categoryTags`.
- **Action:** Define one static `defaultCategory` per module and use it in both places.
- **Severity:** Low · Confidence: Likely

### 5.22 Dice `reset(addValue:)` converts Double to Int without the guard its twin has
- **Location:** `Modules/DiceRPG/Controller/EditController.swift:102-106`; the guarded twin is `:114-120`
- **What:** `Int(addValue)` traps on NaN, infinite or out-of-range values. `reset(modifier:)` checks `isFinite` first.
- **Why:** The value comes from a text editor (`Modules/DiceRPG/Dice/SpecialOptionEditor.swift:39-44`). If the editor lets such a value through, the app crashes.
- **Action:** Clamp to the editor range and use `Int(exactly:)` or the existing `saturatingInt`.
- **Severity:** Low · Confidence: Unverified (whether the editor clamps first was not traced)

### 5.23 `fetchPhotoAnalysisImage` documents "nil when not downloaded" but may start downloads
- **Location:** `Modules/PhotoRPG/Root/PhotoRootModel+PhotoAccess.swift:76-87`
- **What:** It calls `fileUrlDataController.resolvedImage`, which can load data and start an iCloud download.
- **Why:** A batch "Extract Information" over many dataless photos can download the whole selection, against the documented contract and the iCloud-placeholder rule.
- **Action:** Check `hasDownloadedData` first, or fix the comment if downloading is intended.
- **Severity:** Low · Confidence: Likely

### 5.24 PDF bookmark names split on spaces only
- **Location:** `Modules/PdfRPG/Controller/EditController.swift:62-70`
- **What:** `content.split(separator: " ").first` keeps newlines and tabs.
- **Why:** Names become "Word\nNext". A selection of only whitespace gives "\n" instead of "Unnamed".
- **Action:** Split on `\.isWhitespace`.
- **Severity:** Low · Confidence: Likely

### 5.25 Concave room hit volumes on the 3D table overlap their neighbours
- **Location:** `Modules/GameRPG/Table3D/GameTableEntities.swift:618-634`
- **What:** Each room's collision shape is the convex hull of its polygon.
- **Why:** For L- or U-shaped rooms, a GM tap can hit the wrong `RoomHitArea` and reveal fog the GM meant to keep hidden.
- **Action:** Triangulate the polygon, or hit-test against the polygon in table space after the ray hit.
- **Severity:** Low · Confidence: Likely

### 5.26 Embedded Foundry documents without an id can collide with a real id and fail the whole import
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:843-858` (fallback `"embedded-\(n)"`), validator `:1147-1169`
- **What:** A positional fallback id can equal a sibling's real id. The identity validator then throws for the whole package.
- **Why:** One odd document makes the entire import fail.
- **Action:** Use fallback ids with a character Foundry ids never contain, or add a suffix until the id is unique.
- **Severity:** Low · Confidence: Likely

### 5.27 The ZIP reader mixes absolute `subdata` ranges with `startIndex`-relative readers
- **Location:** `Modules/CoreRPG/Foundry/FoundryZIPArchive.swift:166` versus `:467-481`
- **What:** The bug is latent while the archive `Data` starts at index 0, which it does today.
- **Why:** Passing a slice would read the wrong bytes.
- **Action:** As in audit 28.
- **Severity:** Low · Confidence: Verified
- **Known:** audit 28 §5.27

### 5.28 Redundant force unwraps of the store description
- **Location:** `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:179-181` (already bound at `:166`), `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:72-74`
- **What:** `persistentStoreDescriptions.first!` is used although a `guard let` already holds the same value.
- **Why:** It breaks the no-force-unwrap rule and would trap if the setup changes.
- **Action:** Use the bound description.
- **Severity:** Low · Confidence: Verified

---

## 6. Security

Re-checked and still holding (no finding):
- `.local` import relocation (`Modules/CoreRPG/Files/FileUrl.swift:200-206`)
- Traversal filtering (`CloudDocumentController.safeComponents`, `moduleFileUrl` containment)
- Remote-host checks
- The GMZ block cap
- Foundry directory-source symlink and containment checks
- The JSON depth guard and the Universal VTT budgets
- Share-extension continuations
- Widget entitlements (App Group only)

No secrets were found, and the interpolated `Logger` calls in scope log only default-private strings and integers.

### 6.1 Foundry composed rule text and names are still not link-neutralised
- **Location:**
  - `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Rules.swift:179-201` (reference, embedded-rule and effect names)
  - `:217-248` (`projectedRuleReferenceContent`: target at `:233`, pack, document, type, source)
  - `:300-323` (effect id, statuses, change paths)
  - `FoundryVTTDomainMapper+SharedHelpers.swift:394-400` (`presentedFoundryValue` object keys)
- **What:** These paths use `sanitizedFoundryText` (decode only) instead of `safeText`/`neutralizingLinks`.
- **Why:** A package string containing `](masterrpg://…)` or `https://…` becomes a live link in rule entries. The description and value paths were fixed; these siblings were not.
- **Action:** Apply `neutralizingLinks` in these helpers, keeping the mapper's own `markdownLink` output live. Add one mapper test per path.
- **Severity:** Medium · Confidence: Verified
- **Known:** audit 28 §6.2 (listed remainder)

### 6.2 Revealing a hex cell reveals whole hidden rooms by bounding-rect overlap
- **Location:** `Modules/MapRPG/Model/MapModel+Geometry.swift:286-300`
- **What:** Toggling a hidden hex cell shows every hidden non-hex room whose `rect` intersects the cell.
- **Why:** For L-shaped or diagonal rooms, a hex next to the bounding box (but outside the room) reveals the room's name, text and pins to players.
- **Action:** Test the intersection against the room polygon (or require the cell centre to lie inside), or confirm with the user that rooms should reveal at all on a hex toggle.
- **Severity:** Low · Confidence: Verified (lead re-opened)

### 6.3 Siri "Next Turn" / "Next Round" speaks a hidden attacker's name
- **Location:** `Modules/GameRPG/Intent/GameIntents.swift:64, 258-271` (`GameIntentDialog.activeName(in:)`); the hiding variant is `Modules/MapRPG/BattleRound/BattleRoundCardPresentation.swift:126-129`
- **What:** The dialog reads the attacker's name directly and ignores "Hide Hidden Attackers", which the on-screen header honours.
- **Why:** Siri speaks the hidden monster's name aloud at the table.
- **Action:** Use `activeAttackerName(hidingPins:)`, or fall back to the generic "Next turn." dialog.
- **Severity:** Low · Confidence: Verified (lead re-opened)

### 6.4 The existing character name is interpolated outside the untrusted-text fence
- **Location:** `Modules/GeneratorRPG/BasicAI/Providers/CharacterSummaryAnalyzer.swift:86-89`
- **What:** The item name, which can come from a Foundry or peer import, is placed in the instruction part of the prompt.
- **Why:** A crafted name can inject instructions. The impact is limited to the user's own output.
- **Action:** Pass the name through `UntrustedPromptText.fenced`, or strip quotes and newlines and cap its length.
- **Severity:** Low · Confidence: Verified

### 6.5 Model error messages show `debugDescription` to users
- **Location:** `Modules/GeneratorRPG/BasicAI/Errors/FoundationModelsError.swift:11-28`
- **What:** Every user-facing message appends `context.debugDescription`.
- **Why:** Framework-internal, unlocalised text appears in alerts and spoken dialogs.
- **Action:** Log the debug text and show only the localised sentence.
- **Severity:** Low · Confidence: Verified

### 6.6 The Private Cloud Compute path is still dormant
- **Location:** `Modules/GeneratorRPG/BasicAI/Providers/PhotoSummaryAnalyzer.swift:34-56`, `PrivateCloudComputeGate.swift`
- **What:** Nothing calls the host entitlement declaration, so the PCC path cannot run.
- **Why:** This is dead code that still has to be kept safe, because PCC without the entitlement is fatal.
- **Action:** Make the ship-or-remove product decision.
- **Severity:** Low · Confidence: Verified
- **Known:** audit 28 §6.6

---

## 7. Performance

### 7.1 Statistics saves commit the shared context and delete row by row
- **Location:** `Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift:502-510` (`saveIfNeeded`), `:348-361`, `:368-392` (deletes), `:286` (`fetchDataSet` loads every session)
- **What:** The statistics flush calls `save()` on the app's shared context. Deletes fetch every row and delete them one by one.
- **Why:** Other modules' pending edits are committed as a side effect, and a failing foreign object fails the statistics save. With months of sessions, "Delete All" and the dashboard stall the main actor.
- **Action:** Give statistics its own background or child context, use `NSBatchDeleteRequest` with a merge, and fetch aggregated ranges.
- **Severity:** Medium · Confidence: Likely
- **Known:** audit 28 §7.3 (the fetch-all part)

### 7.2 Every saved item matches its child rows with a linear search per entry
- **Location:** `Modules/CoreRPG/Persistence/CoreDataRelationship.swift:24-27, 44-60`; the 14 `syncEntries` call sites (for example `Modules/MapRPG/Controller/DataController.swift:71, 90`, `Modules/RuleRPG/Controller/DataController.swift:67`, `Modules/CharacterRPG/Controller/DataController.swift:50, 61`)
- **What:** `childOrNew` runs `existing.first(where:)` per incoming entry. That is O(n²) on every save, even for a name-only change.
- **Why:** Foundry rule items, large maps and characters reach thousands of entries, and the shared save that every module waits on is delayed.
- **Action:** Build a `[UUID: Child]` dictionary once per call.
- **Severity:** Medium · Confidence: Verified (complexity), impact Likely

### 7.3 Image memory budgets are per module and per cache, not per app
- **Location:** `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:16-23, 263`; `Modules/CoreRPG/Cache/ObjectCache.swift:13-21, 81-90`
- **What:** The memory budgets multiply:
  - There are four observable caches of 384 MiB each (Map, Photo, Pdf, Space), so up to 1.5 GiB of full images.
  - There are eight `NSCache`s of 256 MiB each.
  - The full-image and thumbnail disk files share one path per item id.
- **Why:** On iPad or Vision Pro with several modules in use, the combined budget far exceeds what a memory warning tolerates, and only the observable caches are trimmed on a warning. Removing a full image also deletes its thumbnail.
- **Action:** Use one process-wide byte budget, trim the `NSCache`s on a memory warning, and give thumbnails their own disk path.
- **Severity:** Medium · Confidence: Verified
- **Known:** audit 28 §7.1 (the remainder of a partial fix)

### 7.4 Per-frame dice-result scan in the TabletopKit render callback
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+DiceResults.swift:23-40`, called from `Modules/GameRPG/Table3D/GameRenderer.swift` `onUpdate`
- **What:** Every frame iterates all seats and their dice.
- **Why:** This is constant per-frame work for the whole game, even with no dice in motion.
- **Action:** Short-circuit on a "dice in flight" flag that the roll and toss actions set.
- **Severity:** Medium · Confidence: Verified
- **Known:** audit 28 §7.9

### 7.5 The master recomputes the map content digest per message; O(entries) equality in view bodies
- **Location:** `Modules/MapRPG/Controller/GameController+Metadata.swift:46-56, 119-126`, `Modules/MapRPG/Model/MapUpdatePayload.swift:44-48, 75-129`, `Modules/MapRPG/Map/MapEditor.swift:117-122`, `Modules/MapRPG/Map/RootEditCanvasMap.swift:100-131`
- **What:** Each map message rebuilds a snapshot and digest. `onChange(of: map.entries)` compares arrays of up to 20,000 hex cells.
- **Why:** On large hex maps, every pin drag or room toggle costs a full copy, sort and hash on the main actor.
- **Action:** Profile first, then cache the content version behind a structural-change counter.
- **Severity:** Medium · Confidence: Likely (not profiled)
- **Known:** audit 28 §7.5, §7.6

### 7.6 Foundry read parses and hashes the source, then does it again on the first resource read
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:30-44, 89, 1219-1234`; `Modules/CoreRPG/Foundry/FoundryVTTDataSource.swift:86-93`
- **What:** `read` does not seed `zipDataSourceCache`, and a directory source re-hashes on every `sourceSHA256` access.
- **Why:** Import time and peak memory double for large worlds.
- **Action:** Seed the cache from `read`, and store the directory hash once.
- **Severity:** Low · Confidence: Verified
- **Known:** audit 28 §7.14

### 7.7 The pin cutout cache memoises transient failures and never prunes its disk folder
- **Location:** `Modules/PhotoRPG/Controller/PinCutoutCache.swift:50-65, 80-87`
- **What:** A failed decode (for example a photo not downloaded yet) is cached as "no subject". Old cutouts stay in `Caches/PinCutouts` forever.
- **Why:** Pins of a late-arriving photo get no cutout until relaunch, and disk use grows.
- **Action:** Cache only real "no subject" results, and prune stale revisions on launch.
- **Severity:** Low · Confidence: Verified
- **Known:** audit 28 §5.26

### 7.8 Batch extraction applies title, description and tags as three separate saves
- **Location:** `Modules/AdventureRPG/Controller/EditController.swift:227-237`, `Modules/TableRPG/Controller/EditController.swift:88-98`, `Modules/CharacterRPG/Controller/EditController.swift:363-373`, `Modules/MapRPG/Controller/EditController.swift:142-152`
- **What:** Each `reset(...)` call copies, saves and registers an undo step.
- **Why:** A batch over N items gives 3N saves, CloudKit exports and undo entries.
- **Action:** Apply all fields to one edit model and save once (see §9.2).
- **Severity:** Low · Confidence: Likely

### 7.9 The share-extension preview is decoded on the main actor
- **Location:** `Sources/RPGShare/ItemProviderImporter.swift:18-23`, called from `:127, 139, 150`
- **What:** `ImageItem.init` downsamples a 1,200 px preview inside the `@MainActor` importer.
- **Why:** Sharing several large photos makes the loading spinner hitch.
- **Action:** Build `ImageItem` inside the existing `runOffCallerExecutor` closures.
- **Severity:** Low · Confidence: Verified
- **Known:** audit 28 §7.14

---

## 8. SwiftUI / UI

### 8.1 The Space capture tutorial and help pages show hard-coded, unlocalised English
- **Location:** `Modules/SpaceRPG/Record/TutorialPageView.swift:9-47`, `ProConListView.swift:10-21`, `ObjectHelpPageView.swift:10-30`, `EnvironmentHelpPageView.swift`
- **What:** The texts are `String` literals passed to `Text(String)`. None of them is in the module catalog, and there is a typo, "transluscent".
- **Why:** Non-English users see English help in the 3D scanner, which breaks the `bundle: .module` rule. `FeedbackMessages.swift` in the same folder does it correctly.
- **Action:** Store the texts as `LocalizedStringResource`, add them to the catalog and fix the typo.
- **Severity:** Medium · Confidence: Verified

### 8.2 Hard-coded English in stored Foundry import text
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Documents.swift:540-582`, `FoundryVTTDomainMapper+Rules.swift:194, 233-248, 302-303`, `Modules/RuleRPG/Model/RuleModel+FoundryFactory.swift:113-120`
- **What:** Labels such as "Effect n", "**Target:**" and "yes"/"no" are written into persisted entry text as English.
- **Why:** Users of other languages get mixed-language rule entries that can't be re-localised later.
- **Action:** Localise at mapping time, or store the structure and render the labels in the view.
- **Severity:** Low · Confidence: Verified
- **Known:** audit 28 §5.27 (now extended to the Rules mapper and factory)

### 8.3 The Character validation section title is not localised
- **Location:** `Modules/CharacterRPG/Root/CharacterRootModel.swift:231`; shown via `Modules/RolePlayGameKit/View/ValidateRepairView.swift:129` (`Text(verbatim:)`)
- **What:** A raw English string is passed to `update(section:)`.
- **Why:** That section of the validation report is English in every language.
- **Action:** Use `String(localized:bundle: .module)`.
- **Severity:** Low · Confidence: Verified

### 8.4 Accessibility and display gaps (grouped)
- **Location:**
  - `Modules/MapRPG/Map/MapRoomCanvas.swift:331` (empty VoiceOver label for unnamed rooms and every hex cell)
  - `Modules/GameRPG/Table3D/GameTableEntities.swift:537, 552, 557, 566-573, 246` (3D room and pin names and accessibility labels are set once and never refreshed after a rename)
  - `Modules/GeneratorRPG/View/BatchPdfSummaryExtractionView.swift:84, 143`, `BatchTextSummaryExtractionView.swift:139, 204` (raw UUID shown for an empty name; "1 items")
- **What:** Empty or stale labels, machine ids shown to users, and plural errors.
- **Why:** VoiceOver users hear nothing or an old name, and the batch summary shows UUIDs.
- **Action:** Fall back to localised "Room n"/"Hex cell" labels, refresh labels in `update` (idempotently), show "Untitled", and use `^[\(n) item](inflect: true)`.
- **Severity:** Low · Confidence: Verified

### 8.5 `ScenesManager` keeps SwiftUI environment actions as observed state and re-assigns them on visionOS
- **Location:** `Modules/CoreRPG/ScenesManager/ScenesManager.swift:45-46, 66-68, 98-111`; compare `:115-124`
- **What:** `openWindow`, `dismissWindow` and the immersive-space actions are tracked properties. The visionOS `setActions` has no "already set" guard.
- **Why:** Every call invalidates each view that reads the manager.
- **Action:** Mark the actions `@ObservationIgnored` and add the same once-only guard on visionOS.
- **Severity:** Low · Confidence: Likely

### 8.6 Controllers are created in view bodies in GeneratorRPG
- **Location:** `Modules/GeneratorRPG/View/SheetAIAssistantContext.swift:42-55`, `Modules/GeneratorRPG/Root/GeneratorRootModel.swift:139-178`
- **What:** Controllers are created, reordered and torn down while `body` is built.
- **Why:** This adds work on every render and risks state resets.
- **Action:** Own the controllers in the model and create them on appear.
- **Severity:** Low · Confidence: Verified
- **Known:** audit 28 §8.4

### 8.7 Hard-coded padding and stack spacing
- **Location:** 68 sites in GameRPG, the largest being `Modules/GameRPG/SetupViews/SelectedAdventureView.swift` (7), `SelectedPlayerView.swift` (5), `GameJoinCodeSetupButton.swift` (4), `GameViews/GameTableLaunchView.swift:26`; CoreRPG `EntryEditor/EntryEditorContent.swift:31`, `LGViews/ItemHeaderEditorView.swift:63`
- **What:** Numeric `.padding(n)` and `spacing: n` values.
- **Why:** This conflicts with CLAUDE.md and doesn't scale with Dynamic Type.
- **Action:** Use the defaults or `@ScaledMetric`, fixing them opportunistically.
- **Severity:** Low · Confidence: Verified
- **Known:** audit 28 §8.3

### 8.8 `AnyView` in the per-module ViewControllers
- **Location:** `Controller/ViewController.swift` in CharacterRPG (5 sites); WeatherRPG, TableRPG, PhotoRPG and AudioRPG (4 each); SpaceRPG, PdfRPG and DiceRPG (3 each)
- **What:** There are 30+ `AnyView(` erasures, forced by the `ViewController` protocol's existential return type.
- **Why:** CLAUDE.md asks to avoid `AnyView`. The erasure resets view identity for every module detail screen.
- **Action:** Refactor at the protocol level in CoreRPG (`@ViewBuilder` requirements or associated view types); no fix per module.
- **Severity:** Low · Confidence: Verified (count), impact Unverified

---

## 9. Dead code / duplication / refactor

No stale files were found (no `_OLD`/`Legacy`/`#if false` files), and there are no TODO/FIXME/HACK markers in `Modules/` or `Sources/`.

### 9.1 Three analyzers and two batch views duplicate the availability check, the catch ladder and the run loop
- **Location:** `Modules/GeneratorRPG/BasicAI/Providers/PdfSummaryAnalyzer.swift:30-33, 110-121`, `TableSummaryAnalyzer.swift:17-20, 42-53`, `CharacterSummaryAnalyzer.swift:27-30, 50-60`; `Modules/GeneratorRPG/View/BatchPdfSummaryExtractionView.swift:140-200`, `BatchTextSummaryExtractionView.swift:200-300`
- **What:** The same guard and five-arm catch are copied three times, and the two batch views copy each other's run loop.
- **Why:** The copies have already drifted (§5.18). The §4.1 fix would have to be applied three times.
- **Action:** Add one `AnalyzerRunner` that owns availability and error mapping, plus a generic batch runner parameterised by the per-item step.
- **Severity:** Medium · Confidence: Verified

### 9.2 `applyExtractedContent(TableSummaryAnalysis…)` is copied verbatim into four EditControllers
- **Location:** `Modules/AdventureRPG/Controller/EditController.swift:227-237`, `Modules/TableRPG/Controller/EditController.swift:88-98`, `Modules/CharacterRPG/Controller/EditController.swift:363-373`, `Modules/MapRPG/Controller/EditController.swift:142-152`
- **What:** Four identical 10-line bodies.
- **Why:** The §7.8 single-save fix, or the "name only if empty" rule, would have to be made four times.
- **Action:** Move the body into a constrained `EditControllable` extension in CoreRPG.
- **Severity:** Low · Confidence: Verified

### 9.3 The Pdf/Space/Photo entity file and thumbnail representations are twins
- **Location:** `Modules/PdfRPG/Intent/PdfEntity+Image.swift` and `Modules/SpaceRPG/Intent/SpaceEntity+Image.swift` (identical after renaming); `Modules/PhotoRPG/Intent/PhotoEntity.swift:103-108`, `Modules/PdfRPG/Intent/PdfEntity.swift:101-106`, `Modules/SpaceRPG/Intent/SpaceEntity.swift:99-104`
- **What:** The same export closures appear in each module, with only the error type changed.
- **Why:** The audit 28 §6.7 fix had to be applied three times.
- **Action:** Add shared `exportedFileUrl(itemId:)` and `thumbnailPngData(itemId:)` helpers next to `FileBackedModuleAccess`.
- **Severity:** Low · Confidence: Verified

### 9.4 Two ways to save the header fields, and a duplicated folder re-path loop
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:89-94` versus `:98-129`; the loop is copied at `:123-128` and `:159-165`
- **What:** Two entry points do the same edit with different save and undo semantics.
- **Why:** Callers pick the wrong one (§5.5), and the two loops can drift.
- **Action:** Keep the combined reset with category added, route `update` through it, and extract the loop into one helper.
- **Severity:** Low · Confidence: Verified

### 9.5 AppModel: a dead platform conditional and four identical Navigator configurations
- **Location:** `Modules/RolePlayGameKit/Model/AppModel.swift:47-51, 145-176`
- **What:** The `#if os(tvOS)` and `#else` branches are identical. Four `Navigator(configuration:)` blocks each repeat `executionDelay: 0.4`.
- **Why:** This is noise, and the delay has to be changed in four places.
- **Action:** Remove the conditional, and add `makeNavigator()` with a named delay constant.
- **Severity:** Low · Confidence: Verified
- **Known:** audit 28 §9.8

### 9.6 Redundant double link rewrite in Foundry journal and chat content
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Documents.swift:386, 597`; `safeText` at `FoundryVTTDomainMapper+SharedHelpers.swift:293-295`
- **What:** `rewriteFoundryLinks(safeText(content))`, where `safeText` already rewrites the links.
- **Why:** The regex pass runs twice per document on the main actor (§3.4).
- **Action:** Call `safeText(content)` alone.
- **Severity:** Low · Confidence: Verified

### 9.7 A debug fixture is embedded in the statistics types file
- **Location:** `Modules/GameRPG/Statistics/Model/GameStatisticsTypes.swift:575-759`
- **What:** About 185 of the file's 759 lines are a `#if DEBUG` fixture.
- **Why:** It pushes the file over 500 lines. Other modules keep fixtures in `Preview/`.
- **Action:** Move it to `Modules/GameRPG/Preview/GameStatisticsFixture.swift`.
- **Severity:** Low · Confidence: Verified

### 9.8 Small cleanups (grouped)
- **Location:**
  - `Modules/GameRPG/Root/GameRoot.swift:101, 118-120` (the `_logGameController!` invariant)
  - `Modules/MapRPG/Map/MapRoomCanvas.swift:505-506` (stale "asynchronous Canvas" comment)
  - `Modules/MapRPG/Controller/EditController.swift:520-526` (`affectedLinks = true` means "no links", plus a stray `break;`)
  - `Modules/GeneratorRPG/Intent/RunGeneratorIntent.swift:146` (`/ 4` while `charactersPerToken` is 3)
  - `Modules/RolePlayGameKit/Model/AppModel.swift:423-456` (indentation)
  - `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:812` (inline depth `64`)
- **What:** Stale comments, inverted names, an unchecked invariant and duplicated constants.
- **Why:** They mislead maintainers.
- **Action:** Make `logGameController` a `lazy var`, rename to `hasNoLinkedEntries`, reuse `charactersPerToken`, and name the depth limit.
- **Severity:** Low · Confidence: Verified

### 9.9 Oversized files (>500 LOC)

| File | Lines | Split proposal |
|---|---|---|
| `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift` | 1,282 | Reader and caches; decode orchestration and discovery; document tree and LevelDB keys; type-inference tables |
| `Modules/CoreRPG/Foundry/FoundryRuleModels.swift` | 849 | One file per model family |
| `Modules/CoreRPG/Controllable/ImportControllable.swift` | 799 | File handling (`:604-730`) and private helpers into `+Files` |
| `Modules/GameRPG/Statistics/Model/GameStatisticsTypes.swift` | 759 | Fixture out (§9.7); dashboard config separate from summaries |
| `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift` | 754 | Models separate from the reader |
| `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift` | 747 | Sender, receiver reassembly and journal drain |
| `Modules/RolePlayGameKit/Import/Foundry/FoundryImportView.swift` | 715 | Start, review and commit subviews |
| `Modules/MapRPG/Controller/GameController+Pins.swift` | 672 | `+PinUpdate` and `+PinPlacement` |
| `Modules/CoreRPG/Controllable/ItemControllable.swift` | 643 | External-import staging (`:440-524`) into `+ExternalImport` |
| `Modules/GameRPG/Table3D/GameTableEntities.swift` | 636 | `PinPawn`, `RoomHitArea`, `GameTableImage` |
| `Modules/CoreRPG/Persistence/CoreDataController.swift` | 636 | `CoreDataModel`/`PendingOperation` and the DEBUG logging out |
| `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Documents.swift` | 604 | Journal, chat and actor mapping |
| `Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift` | 588 | Fetch and aggregate vs write and delete |
| `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift` | 584 | Join and rebind vs teardown |
| `Modules/CoreRPG/Foundry/UniversalVTTReader.swift` | 583 | Models separate from the reader |
| `Modules/MapRPG/Map/MapRoomCanvas.swift` | 571 | Tile geometry into its own file |
| `Modules/GameRPG/Controller/MasterController+AudioMessages.swift` | 568 | Pending-play/retry state machine into its own type (also makes §3.2 testable) |
| `Modules/RolePlayGameKit/Model/AppModel.swift` | 548 | Factory and window placement out |
| `Modules/MapRPG/Controller/EditController.swift` | 539 | Monster, photo-pin and hex-grid extensions |
| `Modules/GeneratorRPG/Controller/GeneratorController.swift` | 528 | `GeneratorTaskWait`/`OneShotGate` and the extraction flow out |

Also between 500 and 540 lines: `FileUrlDataController(+Create)`, `EditControllable`, `SharePlayJournalPublicationQueue`, `ExportControllable`, `GameTableView+VisionOS`/`+PlatformFlat`, `SpaceRPG/Record/AppDataModel` (Apple sample), `ListRootContextMenu`, `FoundryVTTBridgeDecoding`, `ScenesManager`, `IntentEntityHelpers`, `FoundryTextDecoder`, `GameMessagePipeline` (leave as is).

- **Severity:** Medium
- **Known:** audit 28 §9.6 (most of the top entries)

### 9.10 Magic constants
- **Unnamed, worth naming:**
  - `Modules/RolePlayGameKit/Model/AppModel.swift:148, 156, 164, 172` (`executionDelay: 0.4`, four times)
  - PinPawn geometry literals in `Modules/GameRPG/Table3D/GameTableEntities.swift:164-255` (0.005, 0.004, 0.006, 1.8, 0.72, 0.10, 0.0015, 0.02)
  - RoomHitArea values at `:577-613` (outline 8, highlight 8, lift 0.003, opacity 0.01)
  - `Modules/MapRPG/Map/MapRoomCanvas.swift:110, 144, 428, 453` (stroke widths, and `4_096` twice)
  - `Modules/GeneratorRPG/Intent/RunGeneratorIntent.swift:146` (`/ 4`)
  - `Sources/DiceRollerWidget/DiceRollerProvider.swift:71-76` (relevance 75/50/10, durations 300/1800)
  - `Modules/CoreRPG/Files/FileUrl.swift:101` and `Modules/CoreRPG/Controllable/ExportControllable.swift:466` (`1 << 20` twice, while `ByteUnit.mebibyte` exists)
  - `Modules/CoreRPG/Controllable/TagController.swift:87` and the `LinkRegisterController` setup (`fetchBatchSize = 500` twice)
- **Named but scattered:** the per-module limits in Audio, Dice, Table, Photo, Pdf and Space would read better as a per-module `Limits` enum, like `WeatherLimits`.
- **Action:** Move the Table3D literals into `GameMetrics` (unit: metres) and name the others.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **One write discipline for the library copy vs the game copy** (§5.1, §5.2, §5.3, §5.5). Today each caller decides whether to copy, which copy to build on, whether to sync game memory and whether side tables follow. Put the rules in `ItemControllable`/`ItemGameModel`:
   - game memory never holds a library instance (copy on insert);
   - a forced write builds on the library copy and applies only named fields or entries;
   - memory-only writes never touch the link register or the tags.

   Give every module a `libraryWriteFilter` (Map's is the model), or make the filter a protocol requirement with a default.
2. **Fix twins, not sites.** Five findings are a fix that landed in one module only: `isSame` (§5.10), `nonisolated(unsafe)` statics (§3.5), `syncGameMemory: false` (§5.2), analyzer error handling (§4.1/§9.1), Foundry neutralisation (§6.1). When fixing one of these, `rg` for the sibling pattern in all 15 modules. Better still, move the shared behaviour into CoreRPG (§9.1, §9.2, §9.3), so there is only one copy.
3. **Every game-visible state change goes through one broadcast funnel.** §5.6 (a dedupe log blind to other senders), §5.8 (a drop path with no broadcast), §5.9 (a toggle used as a pause) and §3.2 (a retry that overtakes a pause) all come from per-path broadcasting. A single "map/battle/audio state changed" funnel would make dedupe and supersession correct by construction. It should record the last sent value and honour `isStreaming`.
4. **Identity by id, never by display name** (§5.7, and the name fallback in Dice `isSamePlayer`). Carry player ids through seat assignment and dice lookup.
5. **GM-only information at every output surface.** The visual paths are well guarded. The new leaks are on secondary surfaces: Siri speech (§6.3), hex-reveal geometry (§6.2) and 3D hit volumes (§5.25). Treat "what can a player see or hear" as a checklist item for intents, accessibility labels and geometry approximations.
6. **File-system work off the main actor.** §3.3, §3.6 and §7.9 are the remaining synchronous listing, compare and decode paths. Approachable concurrency makes a plain `async` on a `Sendable` struct run on its `@MainActor` caller. Default file helpers to `@concurrent`.

---

## 11. What was NOT audited

- **Tests** (`Tests/`), snapshot baselines (`Snapshots/`) and test plans: not reviewed.
- **Third-party SPM packages** (`RPGTabletopGameContent`, NavigatorUI, swift-snapshot-testing): black boxes.
- **Runtime behaviour:** nothing was run on a simulator or device. TabletopKit, RealityKit, SharePlay, CloudKit and Foundation Models behaviour is inferred from the code. Only the iOS target was built (zero warnings). macOS, tvOS, visionOS and the widget extension were not compiled for this audit.
- **Build settings, schemes, entitlements and Info.plists:** not reviewed, except that the widget entitlements were opened (App Group only, correct).
- **String catalogs and translation quality:** not assessed. Only missing `bundle: .module` and literal-English strings were flagged.
- **CoreRPG UI folders:** checked by grep only, for the CLAUDE.md rules and not read in depth: Animations, Buttons, Editors, EntryEditor, Inspector, ItemDetail, ItemViews, Layout, LGViewModifiers, List, Menu, Rows, Search, Settings, Sheet, Simple, TabNavigation, Text, Theme, Tips, ViewModifiers, Views and Widget.
- **CoreRPG files not read:** FoundryRuleModels, FoundrySystemPackageReader, the LevelDB readers, ArchiveSanitizer, BridgeDecoding (all audited heavily before), FileBookmarkController, GuardedRemoteDownload, PersistenceIssueCenter and the Spotlight files.
- **GameRPG folders only skimmed:** GameViews, SetupViews, Browser, ExternalScreen, Search, Master and Preview (excluded on purpose).
- **Content-module View folders:** sampled only (Root, Controller and Intent were read in full).
- **Other skimmed areas:** the Map Intent, Route, Menu and View folders; RolePlayGameKit Intent, Route and non-Foundry Import; GeneratorRPG Configuration, Model and View; RuleRPG View, Route and Menu; the window lists and Spotlight indexer in `Sources/MasterRPG`.
- **Decided items:** not re-reported. These are trusted-peer import policy, chunked SharePlay Messenger overhead, session-only `healthPercent`, `#Preview` fixtures in Release, no dice or seats on the iOS/macOS table, the removed `.local` transport, the 2.6 file protocol, the pipeline-owned drain, and `sessionId` per join code.

---

## 12. Verification

The lead re-opened these lines after the agents reported:

- **§5.1** — `Modules/CoreRPG/Controllable/GameControllable.swift:82-93`: `setCurrent` inserts `await itemControllable.item(for:)` directly. `:71-76` (`hasItem`) calls `item.copy()` before `append`. `Modules/CoreRPG/ItemList/ItemDataModel.swift:107-112` returns `itemData[itemId]` (the library instance) when no game copy exists. `Modules/CoreRPG/Controllable/ItemControllable.swift:542-549` mutates the existing game instance in place.
- **§5.2** — `Modules/CoreRPG/Controllable/EditControllable.swift:432-434`: `editModel(for:)` is `itemSync(for: itemId)?.copy()` with the default `noGame: false`. `Modules/CharacterRPG/Controller/EditController+InlineEditor.swift:136` calls `replace(model:isInsert:forceSave:)`, whose overload at `ItemControllable.swift:228-230` passes `syncGameMemory: true`. `Modules/AdventureRPG/Controller/GameController.swift:112` passes `false`.
- **§5.5** — `Modules/CoreRPG/LGViews/ItemHeaderEditorView.swift:17-21` captures all four fields in `init`. `:87-97` writes all four back with `forceSave: true` through `EditControllable.update` (`:89-94`), which is four `reset…` calls.
- **§5.6** — `Modules/GameRPG/BattleRound/BattleRoundBroadcastLog.swift`: `shouldSend` compares only against its own last value. `Modules/GameRPG/Table3D/GameTableModel+PinSelection.swift:244-257` broadcasts directly, without updating the log.
- **§5.8** — `Modules/MapRPG/Map/MapEditor.swift:314-335`: the game branch has no `broadcastMapEdit()`. `Modules/MapRPG/Map/GameToolBar.swift:215-217` shows the broadcasting twin. `Modules/MapRPG/Map/RootCanvasMap.swift:72-84` installs the drop target with no mode check.
- **§5.9** — `Modules/AudioRPG/Root/AudioRootModel+Playback.swift:174-180` compares `currentId == id` and sends `requestPlay(id:)`. `Modules/AudioRPG/Controller/GameController+Playback.swift:363-368` shows that it is a toggle on the playlist root.
- **§5.11** — `Modules/DiceRPG/Controller/GameController.swift:160` clears the sender. `:167-169` then matches via `isSamePlayer`, which reads that sender.
- **§3.1** — `Modules/GameRPG/Table3D/GameObserver.swift:38-41` calls `reclaimLocalSeat()` inline. `:44-48` documents why inline mutation is unsafe. `:68-76` calls `tabletop.claimSeat`.
- **§6.2** — `Modules/MapRPG/Model/MapModel+Geometry.swift:294-298` filters with `$0.rect.intersects(source)` and sets `isShown = true`.
- **§6.3** — `Modules/GameRPG/Intent/GameIntents.swift:266-271` reads `model.attacker(for:)?.name` with no hidden-pin check. `Modules/MapRPG/BattleRound/BattleRoundCardPresentation.swift:126-129` is the hiding variant.
- **Compiler ground truth** — clean `xcodebuild … -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build` with fresh DerivedData: `BUILD SUCCEEDED`, 0 Swift warnings.

There are no Critical findings. For any other finding, open the cited `path:line`. If a finding does not reproduce, report its §N.M.
