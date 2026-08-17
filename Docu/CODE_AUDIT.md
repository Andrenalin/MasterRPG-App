# MasterRPG Code Audit — Release 3.0

Generated 2026-08-16. Scope: ~267,500 Swift LOC across ~1,992 files, covering all 15 dynamic-framework modules (`AdventureRPG`, `AudioRPG`, `CharacterRPG`, `CoreRPG`, `DiceRPG`, `GameRPG`, `GeneratorRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `RolePlayGameKit`, `RuleRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG`) and the `MasterRPG`/`MasterMac`/`MasterTV`/`RPGShare`/`DiceRollerWidgetExtension` targets. No `Dead/` or archived directory exists in this repo, so nothing was excluded by convention — only `.git/`, `.build/`, `DerivedData/`, and `xcuserdata/` were skipped.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

**Compiler ground truth:** a full clean `xcodebuild clean build` of the `MasterRPG` scheme (iOS Simulator) succeeded with **zero real compiler warnings** (only two unrelated "AppIntents metadata extraction skipped" notices) under `SWIFT_STRICT_CONCURRENCY = complete` / Swift 6 language mode —`SWIFT_TREAT_WARNINGS_AS_ERRORS` is not set, so this is a genuinely clean build, identical to the previous pass. Nearly every hard CLAUDE.md rule (no GCD, no `ObservableObject`, no `DateFormatter`, no `UIScreen.main`, no `NavigationView`, no single-parameter `onChange`, etc.) came back with **zero** violations on a full-tree grep this pass — this codebase is unusually disciplined about its own style rules, and the findings below reflect that: they skew toward logic/architecture gaps and new-feature edges rather than rule violations.

**Context on findings volume:** this repo carries six prior audit passes (`Docu/CODE_AUDIT_1.md` through `_6.md`, the latest dated 2026-08-15), and a commit titled "fixed: tons of issues from the audit" landed on 2026-08-16 addressing that pass. Every "Known finding" from `CODE_AUDIT_6.md` was independently re-verified against current source this pass, not re-derived from the old report: the `NavigationSend.swift` `DispatchQueue.main.asyncAfter` (flagged across 4 consecutive prior passes) is now a cancellable `Task`; all five `...DataController` structs now use `await context.perform`; `EntityGestureState` is now itself `@MainActor`; the duplicated path-fallback and the unused `DeviceRotateViewModifier.swift`/`DumpEnvironment.swift` are confirmed gone. Five commits landed today touching `GameRPG/GameViews` and `GameRPG/Table3D` (a new dice overlay, a map-toolbar fix, and a visionOS ornament rework) — none of that code has been through a prior audit cycle, and it is where this pass's two Critical findings were found.

---

## 1. Executive summary

Top items to address, in priority order:

1. **[Critical] The Share Extension's own "lightweight architecture" is defeated by a default-parameter reference to the full-app `AppModel.shared` singleton** — §5.1 — `Sources/RPGShare/SharingView.swift:50`. Every extension launch silently builds all 12 module root models, four `Navigator`s, and a second Core Data stack inside a ~120MB-budget process — exactly what a comment two lines away in `ShareViewController.swift` says was already removed once for being "too heavy for a share extension."
2. **[Critical] The 3D Object Scanner never attaches its finished scan to the item the user opened it from — the model is silently lost** — §5.2 — `Modules/SpaceRPG/View/InlineImporterView.swift:141-147`, `Modules/SpaceRPG/Record/Scanner3DRootView.swift`. Confirmed by full-tree grep: zero references to `itemId`/`editController`/`resetFile` anywhere under `Modules/SpaceRPG/Record/`.
3. **[High] Foundry image import has no pixel-dimension cap before allocating a full-size bitmap — a decompression-bomb vector from untrusted archives** — §6.1 — `Modules/RolePlayGameKit/Import/Foundry/FoundryMediaNormalizer.swift:148-212`.
4. **[High] Re-decoding a saved Foundry import archive skips the JSON nesting-depth guard used at every other decode site — a reachable stack-overflow crash** — §6.2 — `Modules/CoreRPG/Foundry/FoundryImportArchive.swift:219-227`. Verified: `JSONDecoder()` here sets no `userInfo` depth counter, unlike the other three `FoundryJSONValue`-decoding call sites.
5. **[High] Every packaged Foundry asset (image/audio) reopens and fully re-parses the entire ZIP archive just to extract one file** — §7.1 — `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:165-216,1416-1462`. The fix for this exact class of bug already exists for the bridge-format path (`FoundryBridgeResourceCache`) but was never applied to the standard ZIP path.
6. **[High] A stale `stopGame()` Task can race a fresh `startGame()` and silently null out the just-started session's controllers** — §5.3 — `Modules/GameRPG/Root/GameRootModel.swift:572-688`. Verified: `stopGame()` unconditionally sets `masterController`/`playerController` to `nil` at the end of several `await` points, with no reentrancy guard against a concurrent `startGame()`.
7. **[High] Dismissing the game window via system chrome (not the in-app Quit alert) never tears down the game/network session** — §5.4 — `Modules/GameRPG/GameViews/MasterGameScreen.swift:85-87`. Verified: `.onDisappear` only clears the map editor session; nothing calls `stopGame()`.
8. **[High] `GeneratorController` (the on-device AI assist) is shared per module type across every open window, not per item** — §5.8 — `Modules/GeneratorRPG/Root/GeneratorRootModel.swift:137-142`. Verified: `generatorControllers` is keyed only by `NetworkModules`, so two macOS/visionOS windows on different Map items share one conversation/session.
9. **[High] The Share Extension loads full-resolution shared images entirely into memory with no size cap** — §6.3 — `Sources/RPGShare/ItemProviderImporter.swift:155-170`. A single large photo or several shared together can exceed the extension's memory budget.
10. **[High] Untracked, per-tap `Task`s for room toggle/focus bypass the fog-of-war model's own cancellation guard** — §5.5 — `Modules/GameRPG/Table3D/GameTableModel.swift:338-380`. Rapid room toggling can run two expensive fog recomposites concurrently with no guarantee the final result matches the latest action.

---

## 2. Quick wins (≤30 min each)

- **Rename the misspelled public property `availblity` → `availability`** — §8.8 — `Modules/GeneratorRPG/Controller/GeneratorController.swift:188-190`; 3 call sites to update alongside it.
- **Delete the 568-line commented-out `/* ... */` dead-code block** — §9.1 — `Modules/GeneratorRPG/Controller/GeneratorController.swift:492-1059`; source control retains history if it's ever needed.
- **Delete the unreferenced `drafts(from:)` method and its hardcoded, wrong-for-non-adventure `typeId: .adventure`** — §9.1 — `Modules/GeneratorRPG/Controller/GeneratorController.swift:434-451`.
- **Delete the dead `cleanupTaskOrder` write-only property** — §9.1 — `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift:114,488,493`.
- **Delete the unused duplicate `base64Hash(_:)` helper** — §9.1 — `Modules/RolePlayGameKit/Import/Foundry/UniversalVTTDomainMapper.swift:264-275`.
- **Delete the dead `setupWorldTracking()` extension** — §9.1 — `Modules/SpaceRPG/Space/RealityView+CameraTracking.swift:9-27`; zero call sites anywhere.
- **Fix the MARK comment that names the wrong protocol** — §9.14 — `Modules/GameRPG/Controller/MasterController.swift:2281,2283` (`MasterNetworkProxyStoreDelegate` → `MasterNetworkProxyControllerDelegate`).
- **Move the misplaced `ScenesManager.SceneState.isPresentedInGameMenu` extension** out of `MasterGameScreen.swift` into `ScenesManager.swift` beside its own type — §9.15.
- **Remove the unused `aps-environment` entitlement from both RPGShare entitlement files** — §6.7 — no push-notification code exists anywhere under `Sources/RPGShare/`.
- **Add `[weak self]` to the `Task` in `GeneratorSessionModel.init()`** — §3.6 — `Modules/GeneratorRPG/Controller/GeneratorController.swift:22-24`; the closure one line above already does this correctly.
- **Fix the unused closure parameters in `defaultWindowPlacement`** — §8.5 — `Sources/MasterRPG/visionOS/WindowVisionList.swift:42-45`.

---

## 3. Concurrency

Every concurrency item from `CODE_AUDIT_6.md` was independently re-verified this pass and confirmed **fixed**: the `NavigationSend.swift` deferred-resume now uses a cancellable `Task` (not `DispatchQueue.main.asyncAfter`), all five `...DataController` structs use `await context.perform`, and `EntityGestureState` is now itself `@MainActor`. A full-tree grep found zero raw `DispatchQueue.main.async`/`.asyncAfter` anywhere, and all 26 `@Observable` classes carry `@MainActor`.

### 3.1 Actor reentrancy hazard: find-then-mutate race in `FileDataController`
- **Location:** `Modules/CoreRPG/Files/FileDataController.swift:106-122` (`delete(id:)`, `replace(data:)`), reachable via `Modules/CoreRPG/Files/FileBookmarkController.swift:34-54`
- **What:** `delete(id:)`/`replace(data:)` do `let index = await model.data.firstIndex(where:...)` and then, in a *separate* awaited actor call, mutate at that index — with no atomicity between the two.
- **Why:** `FileBookmarkModel`, the actor that owns this controller, is itself reentrant (it awaits `fetchIfNeeded()` then `save()`). A rapid add-then-remove (plausible when a Photo/PDF/Space/Audio picker grants access to several files back to back) can interleave and mutate `model.data` between the read and the write, silently corrupting/removing the wrong bookmark or trapping on a stale index.
- **Action:** Make delete/replace a single actor-isolated operation on `FileDataModel` (`func remove(id:)`/`func replace(_:)` doing the find-and-mutate atomically) instead of splitting it across two separately-scheduled `await`s.
- **Severity:** Medium

### 3.2 Blocking `context.performAndWait` instead of `await context.perform` in the persistent-history processor
- **Location:** `Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift:183,248`
- **What:** `PersistentHistoryProcessor.process()`, an `actor` method, blocks its own executor thread synchronously waiting on two different `NSManagedObjectContext` queues instead of suspending with `await context.perform`.
- **Why:** This is the exact anti-pattern already eliminated from the five `...DataController` structs, just missed in this file. Blocking the actor's thread risks thread-pool starvation under a burst of CloudKit remote-change notifications; the `viewContext.performAndWait` case specifically blocks a background actor's thread on the main-queue-bound view context.
- **Action:** Convert both call sites to `try await backgroundContext.perform { ... }` / `await viewContext.perform { ... }`.
- **Severity:** Medium

### 3.3 `MainActor.assumeIsolated` used directly in three vendored `deinit`s, bypassing the shared documented helper
- **Location:** `Modules/CoreRPG/Navigator/Core/Navigator.swift:232-240`, `NavigationLocked.swift:50-61`, `NavigationProvidedDestination.swift:111-126`
- **What:** Three `deinit`s in the vendored NavigatorUI library call `MainActor.assumeIsolated { ... }` directly instead of routing through the project's one shared, documented `assumeMainActorIsolated` helper at `Modules/CoreRPG/Concurrency/MainActorIsolationAssumption.swift`.
- **Why:** `deinit` is `nonisolated` with no guarantee it runs on the Main Actor — it fires whenever the last strong reference drops, which can happen from a background `Task`. If that ever happens off-main, this traps at runtime (a crash), and being an unshared, raw `assumeIsolated` call, it isn't covered by the audit trail the shared helper exists to provide.
- **Action:** Route through `assumeMainActorIsolated`, or prefer a `Task { @MainActor in ... }` hop capturing only Sendable values, avoiding the runtime-trap risk entirely. Since this is vendored source, apply the patch locally and track it for re-application on any future vendor sync.
- **Severity:** Medium

### 3.4 Redundant `MainActor.run` inside already-`@MainActor` code on `MasterController`'s hottest receive paths
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:523-525` (`resetPlayers()`), `:1140-1153` (`recordDeliveryReceipt(_:)`)
- **What:** `MasterController` is `@MainActor`, yet these two methods wrap a synchronous read of `root.gameModel`/`root.logGameController` in `await MainActor.run { ... }`, unlike every other call site in the same file (which read the properties directly with a comment explaining the wrapper is unnecessary).
- **Why:** `recordDeliveryReceipt` runs once per incoming `.ok` acknowledgement — one of the master's most frequent inbound message types — adding an avoidable extra actor-hop suspension on a hot path. Independently flagged by two separate review passes this audit.
- **Action:** Delete both `MainActor.run { }` wrappers; read the properties directly, matching the rest of the file.
- **Severity:** Medium

### 3.5 `@unchecked Sendable` without a safety-justification comment
- **Location:** `Modules/CoreRPG/Foundry/FoundryRuleModels.swift:161-169` (`FoundryJSONDepthCounter`)
- **What:** This is the sole `@unchecked Sendable` type in the codebase without an explicit confinement-precondition comment (every sibling — `CoreDataChangeObserver`, `Navigator`, `RPGPersistentContainer`, `PerformanceTrace.Interval` — has one).
- **Why:** Makes it harder to audit whether the unchecked claim (one instance per single-threaded decode call, never shared) still holds if the type is ever reused.
- **Action:** Add a one-line comment stating the confinement precondition, matching the codebase's established convention for this annotation.
- **Severity:** Low

### 3.6 `Task` in `GeneratorSessionModel.init()` doesn't capture `[weak self]`
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:22-24`
- **What:** `Task(name: "Foundation Context Size") { await fetchContextSize() }` implicitly captures `self` strongly, unlike the adjacent closure one line above.
- **Why:** Low practical impact (short-lived, fire-and-forget) but an inconsistency against the immediately neighboring pattern.
- **Action:** Capture `[weak self]` for consistency.
- **Severity:** Low

### 3.7 No generation-id guard against a stale partial-stream write racing a newer AI request
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:221-280,293-405`
- **What:** `request()`/`extract()` cancel the previous task and immediately start a new one, relying entirely on cooperative cancellation propagating through the streaming `AsyncSequence` — no generation-id stamp is compared before a stream callback writes state.
- **Why:** In the narrow window before the old task observes cancellation, its stale callback can fire once more and overwrite the freshly-started request's just-set state — a visible flicker or corrupted partial output.
- **Action:** Stamp each invocation with a generation id and guard every state write with an equality check against the current generation id.
- **Severity:** Medium

---

## 4. API modernity

A full-tree grep for every hard CLAUDE.md/SwiftUI rule (`DateFormatter`/`NumberFormatter`, `String(format:)`, `replacingOccurrences`, `UIScreen.main`, `NavigationView`, single-parameter `.onChange`, `.foregroundColor()`, `.cornerRadius()`, `.tabItem()`, `Task.sleep(nanoseconds:)`, non-localized `.contains()` on search text) returned **zero** genuine hits. Deployment targets are iOS/macOS/tvOS/visionOS 26.0 across the board, so there is no back-compat surface to modernize against.

### 4.1 Dead `@available` guards at or below the 26.0 deployment floor
- **Location:** `Modules/CoreRPG/App/PlatformModifiers.swift:31,41,46` (`@available(iOS 26.0, macOS 26.0, tvOS 26.0, *)`); `Modules/CoreRPG/Navigator/Extensions/NavigationLink+Navigator.swift:40,102` (vendored, `@available(iOS 16.0, ...)`)
- **What:** These guard APIs with an OS floor at or below the app's actual unconditional 26.0-only deployment target.
- **Why:** Dead weight that adds no compile-time safety and slightly obscures that the API is unconditionally available in this codebase.
- **Action:** Remove the attributes in the project-owned `PlatformModifiers.swift`. For the vendored `NavigationLink+Navigator.swift`, either drop it locally or leave it as a conscious "unmodified upstream copy" decision.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Share Extension's `AppModel.shared` default-parameter singleton defeats its own lightweight architecture
- **Location:** `Sources/RPGShare/SharingView.swift:50`, `Sources/RPGShare/ShareViewController.swift:13-15,30-33,71-74`, `Modules/RolePlayGameKit/Model/AppModel.swift:29-31,121-260`
- **What:** `SharingView.init` declares `useCloudKit: Bool = AppModel.shared.settingsModel.useCloudKit` as a default parameter. `ShareViewController.swift` (both iOS and macOS variants) constructs `SharingView` without ever supplying `useCloudKit:`, so this default is evaluated on every extension launch. Reading `AppModel.shared` forces Swift to lazily run `AppModel.init()`, which (verified directly) builds every module's root model — Dice, Photo, Audio, Pdf, Rule, Space, Table, Weather, Character, Map, Adventure, Generator — four `Navigator`s, a `TagController`, `InAppController`, `ScenesManager`, and its own `DataBaseModel` Core Data stack. `ShareViewController.swift:13-14` carries a comment stating this exact initialization ("`let appModel = AppModel()`") was already removed once because it's "too heavy for a share extension."
- **Why:** Share Extensions run under an ~120MB memory ceiling and a strict time budget; building the entire main-app object graph (plus a second, independent Core Data stack pointed at the same store the "lightweight" `ShareExtensionDatabaseService` already opened) risks a silent jetsam kill or timeout on every single share, and risks store-coordination conflicts between the two simultaneously-open Core Data stacks.
- **Action:** Never reference `AppModel.shared` from extension code. Read the `useCloudKit` setting directly from the App Group–shared settings store, or thread it through explicitly without touching the singleton.
- **Severity:** Critical

### 5.2 3D Scanner capture flow never attaches the captured model to the item — silent data loss
- **Location:** `Modules/SpaceRPG/View/InlineImporterView.swift:141-147`, `Modules/SpaceRPG/Record/Scanner3DRootView.swift:23-71`, `Modules/SpaceRPG/Record/ReconstructionPrimaryView.swift:20-24`, `Modules/SpaceRPG/Record/AppDataModel.swift`
- **What:** The "3D Scanner" button presents `Scanner3DRootView()` with no `itemId` and no completion callback (`InlineImporterView.swift:142-146`). Verified by full-tree grep: zero references to `itemId`, `editController`, `itemController`, or `resetFile` exist anywhere under `Modules/SpaceRPG/Record/`. After the ObjectCapture → reconstruction pipeline finishes, `ReconstructionPrimaryView.swift:20-24`'s completion closure calls only `appModel?.endCapture()`, which resets capture state — it never calls `editController.resetFile(url:itemId:)` the way the plain file-importer button (`InlineImporterView.swift:132`) does for the identical outcome.
- **Why:** A user who completes the entire photogrammetry scan flow — a genuinely time-consuming, multi-minute physical capture process — ends up with the generated USDZ sitting only in `Documents/Scans/<timestamp>/Models/`, completely disconnected from the `SpaceModel` item they opened the scanner from. The scan is silently lost from the app's perspective, with no error shown.
- **Action:** Thread an `itemId` and a completion/dismiss handler from `InlineImporterView` through `Scanner3DRootView` to `ReconstructionPrimaryView`/`ModelView`, and call `editController.resetFile(url:itemId:)` with the produced USDZ once the user finishes reviewing it.
- **Severity:** Critical

### 5.3 Race between game-start and an in-flight game-stop can silently wipe a just-started session
- **Location:** `Modules/GameRPG/GameViews/MasterGameScreen.swift:186-191`, `PlayerGameScreen.swift:162-167`; `Modules/GameRPG/Root/GameRootModel.swift:572-688`
- **What:** `endGame()` sets `appGameStateModel.isGameRunning = false` synchronously, then fires an unstructured `Task { await root.stopGame() }`. Verified: `stopGame()` (`GameRootModel.swift:665-688`) has several `await` points and unconditionally sets `gameModel.masterController`/`playerController = nil` at the end. `startGame()` (`:572-626`) assigns fresh controllers partway through with no reentrancy guard against a previous `stopGame()` Task still in flight.
- **Why:** A quick restart after quitting (or a rapid quit→rejoin) can let the old `stopGame()` Task null out the controller references *after* a new `startGame()` has already assigned fresh ones — silently wiping the just-started session or leaving it half-initialized.
- **Action:** Add a reentrancy guard (an `isStopping` flag or generation token) so `startGame` refuses to run — or awaits — while a `stopGame` Task is in flight, or have `endGame()` `await stopGame()` directly before flipping `isGameRunning`.
- **Severity:** High

### 5.4 Dismissing the game window via system chrome never tears down the game session
- **Location:** `Modules/GameRPG/GameViews/MasterGameScreen.swift:85-87`, `PlayerGameScreen.swift:59-61`; `Modules/CoreRPG/SceneTrackerModifier.swift:44-65`; `Sources/MasterRPG/MasterRPGApp.swift:94`
- **What:** The only path that calls `endGame()`/`stopGame()` is the in-app Quit alert reached through `GameOrnamentCloseButton`/`OverlayGameMenu`. Verified: `.onDisappear` on both game screens only calls `root.mapRoot.rootModel.clearGameEditorSession()`; the scene tracker only updates window-open bookkeeping.
- **Why:** On visionOS, a window can be dismissed via the system's own close affordance independent of any in-app control. Doing so leaves the game session, SharePlay/network connection, and `isGameRunning` fully "active" with no visible UI until the app process is actually terminated. Today's ornament rework made `GameOrnamentCloseButton` the sole dedicated Quit affordance, so any bypass of it now leaves a dangling active session with no in-window way to end it.
- **Action:** Hook the tracked scene's dismissal (or `scenePhase == .background` for the game window) to trigger the same teardown path, at minimum leaving the SharePlay/network session and notifying other participants.
- **Severity:** High

### 5.5 Untracked per-tap `Task`s for room toggle/focus bypass the model's own fog-recomposite cancellation guard
- **Location:** `Modules/GameRPG/Table3D/GameTableView.swift:49,59,169,172,583,586`; `Modules/GameRPG/Table3D/GameTableModel.swift:90,338-380,502-512,609-642`
- **What:** Every room long-press/double-tap and VoiceOver room activation spawns a bare, unstored `Task { await loadedGame.toggleRoomVisibility/toggleRoomFocus }` (6 call sites). Inside the model, `toggleRoomVisibility`, `toggleRoomFocus`, `setAllRoomsShown`, and `handleMapChange` call `updateFogOfWar` directly instead of going through the existing `fogOfWarTask` property that `displayMode`'s `didSet` and `panViewport(by:)` already use to cancel a superseded fog recomposite before starting a new one.
- **Why:** A user rapidly toggling/focusing rooms (or a GM firing several toolbar actions back to back) can have two or more expensive `ImageRenderer`-based fog recomposites in flight concurrently, with no guarantee the final winning result matches the most recent action; the stray `Task` also keeps `self` alive after the view disappears.
- **Action:** Route every fog-affecting call through the same `fogOfWarTask` cancel-then-replace pattern `panViewport(by:)` already uses, and have the view store/cancel its own per-room `Task` instead of firing detached ones per tap.
- **Severity:** High

### 5.6 `GeneratorSessionModel.cancel()` never stops the underlying FoundationModels stream; the one method that does is unreachable
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:48-53,171-174,221-222`
- **What:** `cancel()` only cancels the outer wrapper `Task`, never calling `conversationEngine.cancelActiveResponse()`. The only method that does call it, `tearDown()`, has zero call sites anywhere in the codebase.
- **Why:** If a user opens the AI panel, starts a generation, then navigates away without issuing another prompt, the on-device `LanguageModelSession` stream keeps running in the background indefinitely, burning CPU/battery, and its completion handler still writes into a `rootModel` the UI no longer expects updates for.
- **Action:** Have `cancel()` also call `conversationEngine.cancelActiveResponse()`, and wire an actual teardown call (e.g. `.onDisappear`) so leaving the AI surface reliably stops the session.
- **Severity:** High

### 5.7 AI generation failures are captured but never shown to the user
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:41-46,267-278,363-402`; `SheetAIAssistantOverlayView.swift`
- **What:** `request()`/`extract()` set `model.responseErrorContent`/`showError` on every failure, but no view observes `generatorController.model.showError` — `SheetAIAssistantOverlayView`'s alert is bound to a separate local `@State errorMessage` that is only ever set to `nil` throughout the file.
- **Why:** When on-device generation fails (model unavailable, guardrail violation, decoding failure, context overflow), the UI silently returns with no explanation — the user just sees generation "do nothing."
- **Action:** Bind the alert directly to `generatorController.model.showError`/`responseErrorContent` and call `model.dismissError()` on dismiss.
- **Severity:** High

### 5.8 `GeneratorController` is shared per module type across concurrent windows, not per item
- **Location:** `Modules/GeneratorRPG/Root/GeneratorRootModel.swift:137-142`; `Modules/GeneratorRPG/Controller/GeneratorController.swift:198-203`
- **What:** Verified: `generatorControllers: [NetworkModules: GeneratorController]` is keyed only by module type — one shared instance for every Map item, one for every Character item, etc. — and `seedConversationContext` rebuilds the shared `ConversationEngine` whenever the displayed item id differs from the last one, with no per-window scoping.
- **Why:** On macOS/visionOS multi-window UI, two windows showing different items of the same module type will have "Ask AI" activation in one window silently rebuild/clear the other's conversation history and cancel its in-flight generation via the shared `currentTask`.
- **Action:** Scope `GeneratorController`/session state per item or per window/scene, or explicitly guard against concurrent activation from two different item ids.
- **Severity:** High

### 5.9 3D Scanner capture folders (Images/Models) are never deleted, only Snapshots
- **Location:** `Modules/SpaceRPG/Record/AppDataModel.swift:240-252,314-327`; `Modules/SpaceRPG/Record/CaptureFolderManager.swift:33-55,134-160`
- **What:** Each scan session creates a fresh timestamped folder with Images/Snapshots/Models subfolders; only `Snapshots/` is ever cleaned up. `reset()` never deletes `rootScanFolder`, `imagesFolder`, or `modelsFolder`, and a cancelled/failed scan leaves the partial Images folder behind too.
- **Why:** Combined with §5.2 (the model is never imported into managed storage either), every use of the scanner — successful or not — permanently grows Documents by tens of MB of capture photos plus the output model, with no cap or cleanup path.
- **Action:** Delete the entire capture folder tree once its contents are no longer needed, or immediately on restart/cancellation.
- **Severity:** High

### 5.10 `viewportPanStart` has no recovery path if `.onEnded` is never delivered
- **Location:** `Modules/GameRPG/Table3D/GameTableView.swift:116-129,454,527-541`
- **What:** `.onChanged` only records `viewportPanStart` when `nil`, cleared only via `defer` inside `.onEnded`. If `.onEnded` is ever not delivered (system interruption, window backgrounding mid-drag), `viewportPanStart` is permanently stuck non-`nil`.
- **Why:** Once stuck, every future `.onChanged` fails its guard and never re-arms, and the eventual `.onEnded` for a completely unrelated later drag computes its delta against the stale start position — a wrong/large viewport jump with no self-correction short of view teardown.
- **Action:** Add a defensive reset (clear on gesture-start lookup failure, or track gesture identity/timeout) so an undelivered `.onEnded` can't permanently wedge future pans.
- **Severity:** Medium

### 5.11 Viewport panning silently no-ops on maps without explicit width/height, unlike every other coordinate path
- **Location:** `Modules/GameRPG/Table3D/GameTableModel.swift:519-522` vs. `:787-796`
- **What:** `panViewport(fromTableStart:toTableEnd:)` guards on `width > 0, height > 0` and simply returns on failure; `pinDragEnded`, facing the identical zero-dimension case, falls back to `MapTableProjection.orientedImageSize`.
- **Why:** For a map relying on the image-size fallback, pin-dropping works but viewport panning is silently a no-op — the drag does nothing with no feedback, reading as a broken gesture.
- **Action:** Give `panViewport(fromTableStart:toTableEnd:)` the same `orientedImageSize` fallback `pinDragEnded` already uses.
- **Severity:** Medium

### 5.12 `manualViewportOffset` can be reset by a network-driven room-focus change while a pan gesture is mid-flight
- **Location:** `Modules/GameRPG/Table3D/GameTableModel.swift:101-107,277,349,490-495,519-536`
- **What:** `resetViewportPanIfFocusedRoomChanged` (reachable via an incoming network `mapState` update) zeroes `manualViewportOffset` on any focused-room-id change with no coordination against a currently-active local drag.
- **Why:** If the GM changes room focus on another device while a player is mid-pan locally, the offset baseline resets underneath the active gesture, and the eventual `.onEnded` applies a stale delta on top of the just-zeroed offset — a visible unexpected snap.
- **Action:** When resetting `manualViewportOffset` due to an externally-driven focus change, also invalidate any in-progress local pan gesture.
- **Severity:** Low

### 5.13 Foundry folder-hierarchy projection has no cycle guard, unlike the RuleRPG folder path in the same file
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift:503-556` (`createFolders`), `:591-611` (`resolveFolder`); contrast `:790-815` (`safeRuleFolderParent`)
- **What:** The general module folder projection assigns each folder's `parentID` via a single O(1) lookup with no ancestor-chain walk, so a Foundry folder cycle is silently projected as a genuine circular `parentId` chain — unlike the RuleRPG folder path in the same file, which already implements cycle detection.
- **Why:** Any downstream code that walks a `parentId` chain upward (breadcrumbs, move/drag validation, folder deletion cascades) is not guaranteed to be cycle-safe for imported content.
- **Action:** Apply the same cycle-detection approach `safeRuleFolderParent` already uses to `createFolders`/`resolveFolder`.
- **Severity:** Medium

### 5.14 O(children × levels) Foundry scene mapping runs synchronously on the Main Actor with no cancellation checks
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift:1347-1480` (`mapLeveledScene`), `:1776-1799` (`assignLevelMembership`), `:1757-1774,1811-1818`
- **What:** These do an O(children × levels) linear scan per Token/Wall/AmbientSound with no `Task.checkCancellation()`/yield anywhere in the path, unlike essentially every other per-document loop in the mapper.
- **Why:** A single crafted Scene with many embedded Level/Token/Wall/AmbientSound documents (bounded only by the global 100,000-document cap) can block the Main Actor for a substantial, uninterruptible stretch — the import cancel button cannot take effect until this synchronous call returns.
- **Action:** Thread cancellation checks through the inner loops, or precompute an ID→level dictionary instead of repeated linear scans.
- **Severity:** Medium

### 5.15 `extract()` duplicates and diverges from the existing `FoundationModelsErrorHandler`
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:363-398` (compare `:272`)
- **What:** `request()`'s catch block reuses `FoundationModelsErrorHandler.handleError(error)`; `extract()`'s catch block hand-rolls its own switch covering only ~4 of ~9 `GenerationError` cases, with wording that drifts from the shared handler for overlapping cases.
- **Why:** Two different, drifting vocabularies for identical error types depending on which code path failed.
- **Action:** Replace the inline switch in `extract()`'s catch block with a call to `FoundationModelsErrorHandler.handleError(error)`.
- **Severity:** Medium

### 5.16 `isLoading` reset via a session snapshot instead of a deterministic value
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:246`
- **What:** `defer { model.isLoading = model.session.isResponding }` runs on every exit path, deriving the value from a session snapshot that `ConversationEngine` can reassign mid-flight, rather than setting `false` directly.
- **Why:** Risks a spinner stuck `true` after an error, or clearing prematurely while another operation on a swapped-in session is still in flight.
- **Action:** Set `model.isLoading = false` directly in the defer (or per catch branch).
- **Severity:** Medium

### 5.17 `extract(message:)` doesn't bound the size of the text it feeds into the extraction prompt
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:293-319` (compare `:469-484`)
- **What:** `prompt(for:...)` caps the GM's request text at 2,800 characters; `extract(message:rootModel:)` takes the full conversational response with no length check, and the upstream conversational call never sets `maximumResponseTokens`.
- **Why:** A long conversational reply, wrapped in extraction instructions plus schema, can itself exceed the context window on the immediately-following extraction call — a reachable, easily-hit context-window-exceeded failure that (per §5.7) is also never shown to the user.
- **Action:** Cap `maximumResponseTokens` on the initial generation, or truncate/summarize the message before building the extraction prompt.
- **Severity:** Medium

### 5.18 `tearDown()` doesn't cancel the extraction task
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:171-174`
- **What:** `tearDown()` cancels the conversational response/task but never calls `model.cancelExtraction()`.
- **Why:** Even once `tearDown()` is wired up (§5.6), an in-flight extraction on its own separate session would keep running and writing into `rootModel` after teardown.
- **Action:** Add `model.cancelExtraction()` to `tearDown()`.
- **Severity:** Medium

### 5.19 `moveToImmersiveSpace()` forces an unneeded close/reopen, working against `ScenesManager`'s own in-place-replace fix
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:291-309`; `Modules/CoreRPG/ScenesManager/ScenesManager.swift:472-501`
- **What:** `moveToImmersiveSpace()` unconditionally dismisses the space viewer before reopening it, citing stale behavior in its own comment; `openSpaceViewer` now replaces the displayed item in place without closing anything, specifically to swap content smoothly.
- **Why:** Forces a visible flicker/full teardown-reopen instead of an in-place swap for a supported, common handoff scenario, and can lose unbroadcast local pose changes to the previously-displayed entity since it's torn down immediately.
- **Action:** Drop the `dismissSpaceViewer()` call and rely on `openSpaceViewer`'s existing in-place-replace behavior; update the stale comment.
- **Severity:** Medium

### 5.20 `deliveryMessagesByWireID` grows without bound for the life of a game session
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:148,304-311,317-319,512`
- **What:** This dictionary gets a new entry for nearly every outgoing master message and is only ever cleared at session end (`stop()`). Sibling caches in the same class (`playerJournalAdmissions`, `peerAvailabilitySources`) are capped at 256 with FIFO eviction; this one has no bound.
- **Why:** Over a long-running session — the normal use case for this app — the dictionary accumulates one entry per outgoing message indefinitely, a real memory-growth concern on memory-constrained platforms like tvOS or for long/many-player sessions.
- **Action:** Add a FIFO/LRU bound mirroring the existing `maximumPlayerJournalAdmissions`/`maximumPeerAvailabilitySources` pattern.
- **Severity:** Medium

### 5.21 Hand Tracking authorization-revoked handler is an empty stub with a comment describing the missing behavior
- **Location:** `Modules/DiceRPG/Space/HandTrackingModel.swift:80-83`
- **What:** `case .authorizationChanged(let type, let status): if type == .handTracking && status != .allowed { // Stop the game, ask the user to grant hand tracking authorization again in Settings. }` — the `if` body is empty.
- **Why:** When a player revokes Hand Tracking permission mid-game, nothing happens — no pause, no prompt — despite the comment describing the intended behavior.
- **Action:** Implement the described behavior, or turn the comment into a tracked TODO so it's discoverable.
- **Severity:** Medium

---

## 6. Security

### 6.1 No pixel-dimension cap before allocating a full-size bitmap when normalizing Foundry images
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryMediaNormalizer.swift:148-212` (`makeJPEG(from:)`), reached via the attachment `load` closure in `FoundryVTTDomainMapper.swift`'s `createAsset` (~1041-1052), gated only by the default-on `.assets` import category
- **What:** After `CGImageSourceCreateImageAtIndex` decodes the source image, `makeJPEG` allocates a `CGContext` sized exactly to the source width/height at 4 bytes/pixel, with no upper bound on either dimension or their product.
- **Why:** A small, highly-compressible, attacker-crafted image referenced from within a Foundry archive (bounded only by the ~64MB compressed-size cap, not decoded pixel count) can declare an enormous width×height, forcing an uncapped, attacker-controlled allocation — a decompression-bomb/memory-exhaustion vector reachable directly from the untrusted-archive import path with default settings.
- **Action:** Read dimensions via `CGImageSourceCopyPropertiesAtIndex` before calling `CGImageSourceCreateImageAtIndex`, and reject images whose pixel count exceeds a defined budget, mirroring the `maximumUniversalVTTPixelDimension` bound already used for Universal VTT maps.
- **Severity:** High

### 6.2 Re-decoding a saved Foundry import archive skips the JSON nesting-depth guard used everywhere else
- **Location:** `Modules/CoreRPG/Foundry/FoundryImportArchive.swift:219-227` (`FoundryImportArchiveStore.decode(_:)`); compare `FoundrySystemPackageReader.swift:536-541`, `FoundryVTTImportReader.swift:1582-1593`, `UniversalVTTReader.swift:303-312`; guard defined at `FoundryRuleModels.swift:25-34`
- **What:** Verified: `decode(_:)` builds a plain `JSONDecoder()` (line 220) and never sets the `userInfo[.masterRPGFoundryJSONDepth]` key that `FoundryJSONValue.init(from:)` requires to enforce its 128-level nesting cap — the only one of four `FoundryJSONValue`-decoding call sites to omit it.
- **Why: ** This path re-reads every `.json` archive under the iCloud-synced `foundry/archives` directory on essentially every import attempt. A deeply-nested value (from corrupted sync, a restored backup, or any other writer of that shared directory) triggers unbounded native-stack recursion — a stack-overflow trap, not a catchable Swift error — exactly the crash class the depth counter exists to prevent.
- **Action:** Set `decoder.userInfo[.masterRPGFoundryJSONDepth] = FoundryJSONDepthCounter()` in `FoundryImportArchiveStore.decode(_:)` to match the other three sites.
- **Severity:** High

### 6.3 Share Extension loads full-resolution shared images entirely into memory with no size cap
- **Location:** `Sources/RPGShare/ItemProviderImporter.swift:155-170`, `Modules/PhotoRPG/Controller/PhotoDataController.swift:11-36`
- **What:** `ItemProviderImporter.data(from:)` reads shared file-backed items via `Data(contentsOf:)` with no size check or downsampling; `PhotoDataController.addNewPhoto` writes that raw data straight to disk. Multiple shared images are held in memory as an array before saving.
- **Why:** A single large photo (ProRAW, HEIC panorama) or several photos shared together can push well past the Share Extension's ~120MB budget, causing a silent jetsam kill mid-share — compounding §5.1's memory pressure.
- **Action:** Stream/downsample large images before holding them in memory, and cap total in-flight payload size across multiple attachments.
- **Severity:** High

### 6.4 User-authored content and player identifiers logged at `.public` privacy across SharePlay, network, and import paths
- **Location:** `Modules/GameRPG/Model/GameNetworkModel.swift:988-989` and `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:756,820,843,848,978` (player display name in `debugDescription`, logged on essentially every SharePlay send); `Modules/CharacterRPG/Controller/EditController.swift:715-847` and the `LinkController.swift` of `CharacterRPG`/`AdventureRPG`/`MapRPG`/`TableRPG`/`WeatherRPG`/`RuleRPG` (dozens of sites logging user-entered item/entry names during link/folder repair); `Modules/CoreRPG/Controllable/ImportControllable.swift:442-694` (`String.importLogPreview` logs up to 240 characters of imported field content — before/after/merged — during manual import review)
- **What:** A systemic pattern: `.public` privacy opts these values out of unified-logging's default redaction, so they persist in plaintext in Console.app output and any sysdiagnose/log archive pulled from the device. The import-review path is the largest surface: it can put substantial, unredacted excerpts of imported character sheets, adventure notes, or campaign content into the system log during ordinary (non-DEBUG-gated) import flows.
- **Why:** Player display names, campaign content, and imported sheet text are all things a user would reasonably expect to stay off-device unless explicitly shared; `.public` logging defeats that expectation continuously during normal use (live games, imports, link repair).
- **Action:** Establish and apply a repo-wide convention: user-authored text and user-chosen identifiers default to `.private` in `Logger` calls; reserve `.public` for enum cases, counts, and internal identifiers. Prioritize the `ImportControllable.swift` diff-logging site first (highest content-volume exposure).
- **Severity:** Medium

### 6.5 Peer network endpoint (IP/port) logged with `.public` privacy
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift:255`
- **What:** A debug log statement logs the full `NWEndpoint.debugDescription`, including the peer's local IP address and port, with `.public` privacy.
- **Why:** Persists another player's/GM's local network address in plaintext system logs, unnecessary for a debug trace.
- **Action:** Change to `.private` (the default) or log only a non-identifying token.
- **Severity:** Low

### 6.6 Local-network join code stored in plain `UserDefaults`; no Keychain use anywhere in the codebase
- **Location:** `Modules/GameRPG/Network/GameJoinCodeModel.swift:44-56,91-93`
- **What:** `masterCode`/`playerCode` — the TLS pre-shared-key passcode gating Bonjour connections — are persisted via plain `UserDefaults.standard`. A repo-wide search found zero Keychain usage anywhere in the codebase.
- **Why:** `UserDefaults` is unencrypted app-sandbox storage, included in unencrypted local device backups — a weaker guarantee than Keychain for a value gating network trust.
- **Action:** Consider moving join codes (and any future device-pairing credentials) into Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- **Severity:** Low

### 6.7 RPGShare Share Extension carries an unused `aps-environment` entitlement
- **Location:** `Sources/RPGShare/RPGShare-Debug.entitlements:5-6`, `RPGShare-Release.entitlements:5-6`
- **What:** Both entitlement files declare `aps-environment`, but no push-notification handling code exists anywhere under `Sources/RPGShare/`.
- **Why:** Extra entitlements beyond functional need violate least-privilege and can draw unnecessary App Review scrutiny; suggests the file was copy-pasted from the main app's template.
- **Action:** Remove `aps-environment` from both RPGShare entitlement files unless a concrete need is identified.
- **Severity:** Low

### 6.8 Bonjour connection acceptance — verified already mitigated, informational only
- **Location:** `Modules/GameRPG/Network/NWParameter+GameMaster.swift:19-65`, `ListenerManager.swift:131-148`, `ConnectionAttemptThrottle.swift:1-65`, `MasterNetworkController.swift`, `PlayerNetworkController.swift`
- **What:** Connections use `NWParameters(passcode:)` deriving an HMAC-SHA256 PSK from the per-device join code for a mandatory TLS-PSK handshake; `ConnectionAttemptThrottle` locks out a source after 3 consecutive failures with exponential backoff (5s–300s).
- **Why:** This is the intended, already-mitigated design — connection acceptance is not unconditional. The residual gap is a 10,000-value (4-digit numeric) keyspace and a per-source-host (not session-wide) throttle key.
- **Action:** No change required; consider a longer/alphanumeric code or a session-wide attempt cap for further hardening.
- **Severity:** Low

---

## 7. Performance

### 7.1 Every packaged Foundry asset reopens and fully re-parses the whole ZIP archive
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:165-216,1416-1462`; wired via `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:166-168,184-186`; used in `FoundryVTTDomainMapper.swift:1014-1087`
- **What:** Each `ExternalImportAttachment.load` closure independently calls `reader.resourceData(for:from:)`, which constructs a brand-new `FoundryVTTDataSource` — a full `Data(contentsOf:)` read plus a full ZIP central-directory parse/validation of every entry — just to extract one file's bytes.
- **Why:** For a world/module with N packaged images/audio files, the entire archive (up to 1GiB) gets fully re-read and re-validated N times instead of once. The fix for exactly this bug class already exists for the `.mrpgfoundry` bridge format (`FoundryBridgeResourceCache`) but was never applied to the standard ZIP-backed system/module/world path.
- **Action:** Give the ZIP-backed reader an equivalent reader-scoped cache, or have the domain mapper batch lookups through the existing `readResources(_:from:in:)` API instead of single-resource `resourceData(for:from:)`.
- **Severity:** High

### 7.2 System-package imports read/parse the same ZIP archive three times and decode the same LevelDB tables twice
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:90-152`; `Modules/CoreRPG/Foundry/FoundryArtifactDetector.swift:70-93`; `FoundryVTTImportReader.swift:18-54,256-354,644-709`; `FoundrySystemPackageReader.swift:17-36,118-204`
- **What:** `loadSelectedArtifact()` detects the artifact, reads it via the general reader, then re-reads/re-parses it a third time inside `FoundrySystemPackageReader` for `.system` packages. The same `.ldb` compendium pack tables get fully decoded twice.
- **Why:** For the common "system package" import path, this multiplies disk I/O and decode work by up to 3x archive parses / 2x pack-table decode on every import, scaling with archive size (up to 1GiB) and document count (up to 100,000).
- **Action:** Share one already-opened/parsed archive/data-source (and ideally one decoded document set) between the artifact detector, the general VTT reader, and the rule-package reader.
- **Severity:** Medium

### 7.3 Linear `pinPawns` scans on the per-tick pin-drag path
- **Location:** `Modules/GameRPG/Table3D/GameTableModel.swift:763-775` (`updatePinMenuAttachmentPosition`), `:778-784` (`pinDragChanged`)
- **What:** `pinDragChanged` runs on every `.onChanged` delta of a pin drag and does an O(n) `pinPawns.first(where:)` scan; when the dragged pin is selected, a second O(n) scan runs — both potentially dozens of times per second during one drag.
- **Why:** Scales linearly with room/pin count on a busy map (many monster pins, battle-round combatants), an avoidable per-gesture-delta cost.
- **Action:** Cache the dragged pawn once at drag-start, or back `pinPawns` with a `[UUID: Pawn]` dictionary given roughly eight call sites already do this same lookup pattern.
- **Severity:** Medium

### 7.4 `focusedDiceRollSignature` recomputed on every SwiftUI body evaluation
- **Location:** `Modules/GameRPG/Table3D/GameTableView.swift:305-314`
- **What:** This computed property (`diceModel.dice.flatMap(\.result)`) is evaluated fresh on every body pass purely to feed an `.onChange(of:)` equality check.
- **Why:** Flattens every result array on every body evaluation regardless of whether anything dice-related changed — wasted allocation on a view already doing meaningful per-frame-adjacent work.
- **Action:** Derive the signature only when the underlying dice model's result actually changes (an `@Observable`-tracked cached signature) rather than recomputing on every body evaluation.
- **Severity:** Low

### 7.5 Fixed 0.6s window-preparation delay, duplicated verbatim between Master/Player game screens
- **Location:** `Modules/GameRPG/GameViews/MasterGameScreen.swift:140-184`, `PlayerGameScreen.swift:109-160`
- **What:** `prepareWindows()` starts with an unconditional `try await Task.sleep(for: .seconds(0.6))` before opening the adventure/character viewer window on visionOS; the entire function body is duplicated nearly verbatim between the two screens (see §9.8).
- **Why:** A hardcoded delay is a timing guess, not a guarantee — it can still race scene readiness on a loaded system, or add needless latency on a fast one.
- **Action:** Replace the fixed sleep with an actual readiness signal from `ScenesManager` if available; centralize alongside the dedup in §9.8.
- **Severity:** Medium

---

## 8. SwiftUI / UI

A direct SwiftUI-expert-skill pass sampled `GameViews/`, `Table3D/GameTableView.swift`, `WindowVisionList.swift`, plus shared UI helpers under `CoreRPG/LGViews`, `CoreRPG/Buttons`, `CoreRPG/ViewModifiers`, and `CoreRPG/EntryEditor`. The shared-helper sample (`QuickEditorDoubleView`/`IntView`, `InlineEditorView`, `EntryNameEditor`, `BatteryView`, `GameScreenModel`) was clean: correct `@Binding`/`@Bindable` usage, correct external-value sync via `onChange(..., initial: true)` rather than misplaced `@State`, correct `[weak self]` capture, and — notably — `BatteryView.swift` documents its own fix for a memory leak from a prior audit pass (§5.5 of `CODE_AUDIT_5`), now closed via `.onAppear`/`.onDisappear` instead of an unreachable actor-isolated `deinit`. One claim from the bugs/security pass was checked and corrected: `GameOrnamentCloseButton`'s `Label { Text } icon: { Image }` + `.labelStyle(.iconOnly)` composition is not a deviation — it's the same pattern used consistently across at least 6 sibling icon-only buttons in `GameViews/` (`GameQuitToolbarButton`, `IOSGameOverlayCloseButton`, `GameSidebarToolbarMenu`, `GameTableWindowButton`, `IOSGameSidebarMenu`), so it was dropped as a finding.

### 8.1 `OverlayGameMenu` built entirely from computed `var` sub-views, not dedicated `View` structs
- **Location:** `Modules/GameRPG/GameViews/OverlayGameMenu.swift:37-338` (~15 computed properties)
- **What:** Verified directly: the file decomposes UI into computed properties (`titleView`, `closeFieldView`, `toolIconMacViewMaster`, etc.) instead of `View` structs, contradicting CLAUDE.md's explicit rule ("place them into new `View` structs instead").
- **Why:** Computed properties give SwiftUI no independent identity/update boundary, so every sub-view re-evaluates on any state change to `OverlayGameMenu` rather than only when its own inputs change — a real diffing cost given this view sits in an ornament driven by several frequently-changing environment objects during a live game.
- **Action:** Extract each sub-view, at minimum the platform menu variants and frequently-recomputed leaf buttons, into their own `View` structs taking explicit parameters/bindings.
- **Severity:** Medium

### 8.2 Window/settings business logic embedded directly in a View extension
- **Location:** `Modules/GameRPG/GameViews/OverlayGameMenu.swift:241-320`
- **What:** `handleMainTabToggle`/`handleMainTabDisplayModeChange` mutate persisted settings, presentation state, and drive window open/dismiss — all from a `private extension` on the View itself, invoked from `.onChange` closures.
- **Why:** Per the project's MVC architecture, this cross-system coordination logic belongs in a Controller/view-model; as written it can't be unit-tested without instantiating the whole view hierarchy and its environment objects.
- **Action:** Move this logic into a testable controller/view-model that `OverlayGameMenu` calls into.
- **Severity:** Medium

### 8.3 `.toggle()` used for one-shot "show" actions instead of explicit assignment
- **Location:** `Modules/GameRPG/GameViews/OverlayGameMenu.swift:118` (`showQuitGameAlert.toggle()`), `MasterGameScreen.swift:65` (`showExport.toggle()`)
- **What:** Verified: these are one-directional "open this" actions, whereas the sibling `GameQuitToolbarButton`/`IOSGameOverlayCloseButton`/`GameOrnamentCloseButton` correctly use direct assignment (`= true`).
- **Why:** If the action ever fires while the flag is already `true` (double-activation via accessibility/Voice Control/a stray duplicate event), it silently flips back to `false` and the alert/sheet never appears, with no visible feedback.
- **Action:** Use direct assignment for all "present" triggers, consistent with the sibling close buttons.
- **Severity:** Medium

### 8.4 Fixed `.frame(height: 24)` on icons undercuts Dynamic Type / `imageScale`
- **Location:** `Modules/GameRPG/GameViews/OverlayGameMenu.swift:122,137,157`
- **What:** Verified: three icons apply `.imageScale(...)` and then immediately clamp to a hardcoded `.frame(height: 24)`.
- **Why:** The explicit height caps the icon regardless of Dynamic Type/imageScale, working against users who increase system text size.
- **Action:** Drop the fixed frame height (or express it relative to current type size) and let imageScale/Dynamic Type govern rendered size.
- **Severity:** Low

### 8.5 Unused closure parameters in `defaultWindowPlacement`
- **Location:** `Sources/MasterRPG/visionOS/WindowVisionList.swift:42-45`
- **What:** `.defaultWindowPlacement { content, context in return WindowPlacement(.utilityPanel) }` never references `content` or `context`.
- **Why:** Minor code-quality issue; obscures that the placement is unconditional.
- **Action:** Use `{ _, _ in WindowPlacement(.utilityPanel) }`.
- **Severity:** Low

### 8.6 Random `UUID()` fallback for the space-viewer immersive-space id churns view identity
- **Location:** `Sources/MasterRPG/visionOS/WindowVisionList.swift:70-73`
- **What:** The `id:` passed to `spaceImmersionWindow` falls back to a freshly generated `UUID()` when all other selection sources are `nil`.
- **Why:** A new random `UUID` on every body re-evaluation that hits this fallback churns view identity unnecessarily rather than presenting a stable "no selection" state.
- **Action:** Use a stable sentinel instead of a freshly-minted random UUID each time.
- **Severity:** Low

### 8.7 Avoidable force-unwrap building `SpaceEntity`'s plain-text Transferable representation
- **Location:** `Modules/SpaceRPG/Intent/SpaceEntity.swift:79-84`
- **What:** `"""...""".data(using: .utf8)!` force-unwraps encoding a string interpolation to UTF-8.
- **Why:** Always succeeds in practice, but is both a force-unwrap CLAUDE.md asks to avoid and a legacy API where the modern always-non-optional initializer removes both issues at once.
- **Action:** Replace with `Data("Name: \($0.name)\nDescription: \($0.description)".utf8)`.
- **Severity:** Low

### 8.8 `availblity` — misspelled public property name
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:188-190`
- **What:** `var availblity: Bool { foundationManager.isModelAvailable }` should be `availability`; used at three call sites across SheetAIAssistant views.
- **Why:** Typo in a public-facing API name; harms readability/grep-ability and risks being copy-pasted forward.
- **Action:** Rename to `availability` and update the call sites.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Dead code to delete outright
- `Modules/GeneratorRPG/Controller/GeneratorController.swift:492-1059` — a 568-line `/* ... */` block comment implementing an entirely different, superseded generation-queue architecture (referencing properties that don't exist on the live types above it). It's a raw block comment rather than `#if false` or line-prefixed `//`, which is why a separate grep-only sweep of this codebase missed it — worth noting for future audits.
- `Modules/GeneratorRPG/Controller/GeneratorController.swift:434-451` — `drafts(from:)`, zero call sites, and hardcodes `typeId: .adventure` regardless of actual module (would be a real bug if ever reconnected).
- `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift:114,488,493` — `cleanupTaskOrder: [UUID]`, appended to and pruned but never read; `cancelAll()` iterates `cleanupTasks.values` directly.
- `Modules/RolePlayGameKit/Import/Foundry/UniversalVTTDomainMapper.swift:264-275` — `base64Hash(_:)`, an unused verbatim duplicate of the helper `FoundryVTTDomainMapper.swift` actually uses.
- `Modules/SpaceRPG/Space/RealityView+CameraTracking.swift:9-27` — `setupWorldTracking()`, zero call sites.
- `Modules/SpaceRPG/Space/RealityView+Gesture.swift`, `Gesture+3d.swift`, `EntityGestureState.swift`, `Entity+Gesture.swift`, most of `Simd+Operations.swift` (~450 lines) — `installGestures()`, the only entry point into this `GestureComponent`/`EntityGestureState` pipeline, has zero call sites anywhere; `SpaceViewer` uses `.realityViewCameraControls(.orbit)`/`ManipulationComponent` instead, but still attaches a live, inert `GestureComponent` to every loaded entity on iOS/macOS. **Note if ever reconnected:** `EntityGestureState.shared` is a single global singleton whose drag handlers apply the gesture's translation to `state.targetedEntity` rather than `value.entity` — with more than one interactive entity visible (routine in this app: multiple folder-list viewers, multi-window macOS, a window alongside the immersive space), a second concurrent drag would misapply deltas to the wrong entity.
- **Severity:** High (clean up; ~1,050+ LOC removed, plus one latent design flaw retired if the gesture subsystem goes with it)

### 9.2 App Intents `Entity`/`EntityQuery` boilerplate duplicated 12x
- **Locations:** `Modules/{Pdf,Photo,Space,Audio,Character,Rule,Dice,Generator,Map,Table,Weather,Adventure}RPG/Intent/*Entity.swift` (144-211 lines each)
- **What:** Diffing `PdfEntity.swift` against `PhotoEntity.swift`/`SpaceEntity.swift` shows ~124 of 170 lines changed, and every changed line is a pure type-name/string swap — the `IndexedEntity`/`Transferable`/`EntityQuery`/`EnumerableEntityQuery`/`SyncableEntity` conformance skeleton is identical across all 12 modules.
- **Action:** Pull the `EntityQuery` conformance body (`suggestedEntities`/`entities(for:)`/`entities(matching:)`/`allEntities`/reindex) into a shared generic base in CoreRPG that each module's concrete `XyzEntityQuery` forwards to.
- **Severity:** Medium

### 9.3 Per-module `ImportController.swift`/`ExportController.swift` byte-identical across 10+ modules
- **Locations:** `ImportController.swift` in Audio/Character/Dice/Generator/Map/Pdf/Photo/Space/Table/Weather RPG (all 19 lines, `diff` returns empty for every pair); `ExportController.swift` in Dice/Generator/Pdf RPG (20 lines, empty diff)
- **What:** A trivial passthrough struct (`struct ImportController: Sendable { let itemController: ItemController; let editController: EditController }`) copy-pasted verbatim into 10+ module folders — the strongest evidence in this audit that a generic base type belongs in CoreRPG. `AudioRPG/Controller/ExportController.swift:23-27` deliberately overrides the default (playlist tracks vs. cross-references) and should stay bespoke.
- **Action:** Add a generic `GenericImportController<Item: ItemControllable, Edit: EditControllable>: ImportControllable` (and an Export equivalent) to CoreRPG; have each module `typealias` to it, eliminating 13+ near-duplicate files.
- **Severity:** Medium

### 9.4 Per-module `ItemController.swift`/small-tier `GameController.swift` near-identical (typealias-only diffs)
- **Locations:** `Weather/Adventure/GeneratorRPG/Controller/ItemController.swift` (23-24 lines each); `Generator/RuleRPG/Controller/GameController.swift` (40/43 lines)
- **What:** Diffs show only `typealias Model = XyzModel` and whitespace differences.
- **Action:** Extend the `Model`-generic base-type treatment from §9.3 to these tiers before the next (16th) module is added.
- **Severity:** Low

### 9.5 `FolderListController.swift` near-identical across all 12 modules
- **Locations:** `Modules/{Adventure,Space,Dice,Table,Weather,Character,Generator,Rule,Audio,Map,Pdf,Photo}RPG/Controller/FolderListController.swift` (38-40 lines each)
- **What:** Identical `FolderListControllable` conformance (`detailDestination`/`folderDestination`/`folderInlineDestination`/`viewerDestination`/`copy(listModel:)`) with only the module's `Route` enum names swapped. As a copy-paste artifact: 5 of the 12 copies carry an unused `import SwiftData` (see §9.6) that the other 7 don't — direct evidence of the "duplicate 12x, tweak names" authoring process.
- **Action:** Move the 100%-identical `copy(listModel:)` method body into a default `FolderListControllable` protocol extension in CoreRPG, leaving only the 4 destination-mapping functions per module.
- **Severity:** Low

### 9.6 Dead `import SwiftData` in 42 non-test files
- **Location:** representative sample — `Modules/RolePlayGameKit/Model/AppModel.swift:7`, `Modules/PdfRPG/Root/PdfRootModel.swift:5`, plus `FolderListController.swift`/`DropChooseView.swift`/`RootModel.swift`/`RootFactory.swift` across Pdf/Space/Audio/Map/Photo/Dice/Adventure/Character/Generator/Table RPG, and several `CoreRPG/{Controllable,LGViews,Model,Fake,EntryEditor}` files
- **What:** Verified: of 84 non-test files importing `SwiftData`, only ~17 (mostly `MockData.swift` preview fixtures plus `SwiftDataController.swift`/`LinkDataModel.swift`) actually reference any SwiftData symbol (`Schema`/`@Model`/`ModelContext`/`@Query`/etc.) — the other 42 carry a dead import.
- **Why:** Unnecessary link-time coupling and slightly slower incremental compilation.
- **Action:** Remove the unused import from all 42 files.
- **Severity:** Low

### 9.7 `Master*`/`Player*` GameRPG view pairs duplicated instead of role-parameterized
- **Locations:** `Modules/GameRPG/GameViews/MasterGameScreen.swift` vs. `PlayerGameScreen.swift`; `MasterOverlayMenu.swift` vs. `PlayerOverlayMenu.swift`; `MasterGameWindowButtonView.swift` vs. `PlayerGameWindowButtonView.swift`
- **What:** Confirmed by direct diff: the entire visionOS `#if os(visionOS)` ornament block (6 `.ornament(...)` modifiers) is structurally identical between Master/Player screens, differing only by side-menu type and `isMaster: true/false`; `endGame()` is byte-identical; `prepareWindows()`'s 0.6s settle delay (§7.5) is duplicated verbatim; `MasterOverlayMenu`/`PlayerOverlayMenu` share an identical `OverlayGameLayout`/`OverlayToolBar`/`GameToolbarContent` scaffold that *already* demonstrates the better role-parameterized pattern used elsewhere in the very same file pair.
- **Why:** Every future change to the shared ornament layout, alert copy, or window-prep timing must be hand-mirrored across 2-3 files, and constants (like the 0.6s delay) can silently drift out of sync.
- **Action:** Extract the shared visionOS ornament scaffold into a single view/modifier taking `sideMenu: some View` and `isMaster: Bool`; extract `endGame()`/the quit-confirmation alert and the window-prep delay into one shared location both screens call into.
- **Severity:** Medium

### 9.8 `AddEntryButton` duplicated 4x with an inconsistent name and an accessibility regression in 2 of the 4 copies
- **Locations:** `Modules/{Character,Map,Table}RPG/View/AddEntryButton.swift`, `Modules/AdventureRPG/View/AdventureAddEntryButton.swift`
- **What:** All four implement the identical "add entry, then after a 0.25s settle delay set `scrollEntryId`" pattern. CharacterRPG and AdventureRPG wrap the mutation in `withAnimation(reduceMotion ? nil : .default)` (respecting Reduce Motion); MapRPG and TableRPG use plain `withAnimation` with no Reduce Motion check. AdventureRPG's copy is also named differently from the other three.
- **Why:** The Reduce Motion gap is a genuine accessibility regression for MapRPG/TableRPG players who've enabled it.
- **Action:** Extract one shared `AddEntryButton` into CoreRPG so the Reduce Motion fix and the 0.25s constant only need to exist once; rename `AdventureAddEntryButton` to match if a fully shared component isn't adopted immediately.
- **Severity:** Medium

### 9.9 Hand-rolled cancel/sleep debounce reintroduced at 3 sites despite `DebouncerModel` existing
- **Locations:** `Modules/CoreRPG/App/AppIntentContentInvalidator.swift:19-27`, `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:111-116`, `Modules/SpaceRPG/Record/TimedMessageList.swift:103-119`
- **What:** Each hand-rolls the exact `task?.cancel(); task = Task { try? await Task.sleep(for:...); guard !Task.isCancelled else { return }; ... }` sequence that `Modules/CoreRPG/Stores/DebouncerModel.swift`'s `delayedTask(_:operation:)` (added specifically to replace 6+ prior call sites) already covers; none of these 3 import/call it.
- **Action:** Replace each with `delayedTask(.seconds(n)) { ... }`, matching `TextEditModel.swift:88,104`.
- **Severity:** Medium

### 9.10 Two minor `JSONEncoder()`/`JSONDecoder()` stragglers bypass the shared `JSONCoding` singleton
- **Location:** `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:44,276`
- **What:** Ad-hoc instances with no custom formatting and no documented reason not to share `JSONCoding.encoder`/`.decoder`, on a low-frequency UserDefaults path.
- **Action:** Swap to `JSONCoding.decoder`/`JSONCoding.encoder`; not urgent.
- **Severity:** Low

### 9.11 Commented-out test block for a known App Intents test-process crash
- **Location:** `Tests/AdventureRPGTests/AppIntentTests.swift:19-53`
- **What:** A full 35-line `@Test` is commented out line-by-line, with a comment explaining `AdventureEntityQuery`'s `@Dependency var root` crashes the whole XCTest process outside the real App Intents perform flow.
- **Action:** The comment already names the fix (move to an out-of-process `AppIntentsTesting`/XCUITest target); track as a coverage gap rather than leaving it commented indefinitely.
- **Severity:** Low

### 9.12 `MasterNetworkNodel`/`PlayerNetworkNodel` — consistent "Nodel"/"Model" typo, plus a file/type name mismatch
- **Location:** `Modules/GameRPG/Master/MasterNetworkNodel.swift` (filename typo too), `Modules/GameRPG/Player/PlayerNetworkModel.swift:25` (file correctly named, type inside misspelled)
- **What:** Both classes are spelled `...NetworkNodel` instead of `...NetworkModel`, used consistently (if wrongly) throughout `MasterNetworkController.swift`, `PlayerNetworkController.swift`, and several test files.
- **Action:** Rename both types (and the one mismatched filename) across ~10+ files, including tests; purely mechanical.
- **Severity:** Medium

### 9.13 Inconsistent `NSRegularExpression` alongside a native Swift `Regex` literal in the same function
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift:1986-1994` (`createDice`), `:2434` (`rewriteFoundryLinks`), `:2544-2546` (`simpleModifier` — uses both a `Regex` literal and `NSRegularExpression` back to back)
- **Action:** Migrate the remaining `NSRegularExpression` call sites to Swift `Regex`/`RegexBuilder`, matching the pattern the file already demonstrates elsewhere.
- **Severity:** Low

### 9.14 MARK comment names the wrong protocol
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:2281,2283`
- **What:** `// MARK: - MasterNetworkProxyStoreDelegate` precedes `extension MasterController: MasterNetworkProxyControllerDelegate` — names don't match.
- **Action:** Fix the MARK comment.
- **Severity:** Low

### 9.15 Misplaced `ScenesManager.SceneState` extension
- **Location:** `Modules/GameRPG/GameViews/MasterGameScreen.swift:194-203`
- **What:** `extension ScenesManager.SceneState { var isPresentedInGameMenu: Bool }` lives inside one specific screen's file but is consumed from 4 unrelated files.
- **Action:** Move it to `Modules/CoreRPG/ScenesManager/ScenesManager.swift` beside `SceneState`'s own declaration.
- **Severity:** Low

### 9.16 Oversized files (>500 lines) — 53 non-test files, top examples with split proposals
- **`Modules/GameRPG/Controller/MasterController.swift` (2,656 lines)** — 5 MARK-delimited extensions already outline the seams; split each into its own file (`MasterController+Send.swift`, etc.), mirroring the existing `PlayerController+Map.swift` pattern. Medium.
- **`Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift` (2,572 lines)** — 7 clear MARK sections (Indexes/Rules/Assets/Document dispatch/Scene conversion/Dice/Shared helpers); split along them. Medium.
- **`Modules/GameRPG/SharePlay/RPGSharePlayController.swift` (2,474 lines)** — a single 1,687-line extension (lines 745-2432) with zero internal MARK structure, though ~25 methods cluster into 3 clear groups (transport, session lifecycle, attachment handling); split into 3 files with MARK headers. Medium.
- **`Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift` (1,215 lines)** — zero MARK comments; move the nested `FoundryReferenceDecoder` enum to its own file first. Low.
- **`Modules/CoreRPG/Sheet/SheetRootModel.swift` (1,007 lines)** — 40+ methods with no MARK grouping in a core cross-module model; group into `+Selection`/`+Linking`/`+EntryEditing`/`+Filtering` extensions. Medium.
- **43 more** between 500-2,432 lines, including several already MARK-sectioned (`FoundryVTTImportReader.swift` 2,432, `GameNetworkController.swift` 1,156, `SharePlayJournalPublicationQueue.swift` 1,089, `GeneratorController.swift` 1,061, `PlayerController.swift` 1,045, `GameTableModel.swift` 1,026, `ExternalImport.swift` 1,023) — these are near-zero-risk mechanical splits; prioritize them over the handful with no existing structure. `CharacterRPG/Controller/SearchController.swift` (718 lines) is a notable outlier — 50x every sibling module's 12-14-line `SearchController.swift` — but already 3-way MARK-sectioned.
- **Severity:** Medium (well-sectioned files) to Low (rest)

### 9.17 Ad-hoc magic constants — 72 unnamed `Task.sleep` intervals with no shared vocabulary
- **Location:** repo-wide, at least 20 distinct literal values across `RolePlayGameKit`, `CoreRPG`, `DiceRPG`, `GameRPG`, `CharacterRPG`, `MapRPG`, `SpaceRPG`, `TableRPG`, and the widget/share-extension targets; the 0.25s "scroll to new entry" delay is duplicated in 4 files (§9.8), the 0.6s window-prep delay in 2 (§7.5, §9.7)
- **What:** Unlike the SharePlay send path (`SharePlayPackageSender.swift` names `throttleInMilliSeconds`) or the persistent-history tracker (named `initialCleanupDelay`), most of the other 60+ sites use bare literals, even where the same value recurs.
- **Why:** No single place to audit/retune "how long do we wait before X"; near-duplicate values (0.5 vs 0.6 vs 1.0) look like typos even where they aren't.
- **Action:** Not worth a blanket sweep, but any file touched for other reasons should hoist its sleep literal(s) into a named constant, following the `SharePlayPackageSender` precedent.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Generic base types for per-module boilerplate.** §9.2-9.6 all point at the same root cause: `ImportController`, `ExportController`, `ItemController`, the small-tier `GameController`, and `FolderListController` are hand-copied into every one of the 12+ feature modules with only type names differing. `CoreDataController<Model, Entity>` already proves this pattern works for the CoreData-mapping half of `DataController` — extend it to these thinner tiers before a 16th module makes the copy-paste cost worse. The App Intents `Entity`/`EntityQuery` skeleton (§9.2) is the same shape but constrained by macro requirements; a partial generic base is still worth it.
2. **Extend the `fogOfWarTask`-style cancel-then-replace pattern to every state-mutating entry point, not just the two call sites that already have it.** §5.5 shows the pattern exists and works — it just isn't applied consistently within the same file. The same "some sites already do it right, others don't" shape recurs at §6.1/§6.2 (3 of 4 Foundry decode sites set the depth guard; only `.assets` import lacks a pixel cap that Universal VTT already has) and §3.4 (most `MasterController` call sites already avoid the redundant `MainActor.run`). These aren't missing patterns — they're inconsistently-applied ones, which usually means a targeted audit-and-apply pass is cheaper than a redesign.
3. **Route every `@unchecked Sendable`/`MainActor.assumeIsolated` use through the one shared, documented helper.** §3.3 and §3.5 are both single stragglers outside an otherwise well-established convention (`MainActorIsolationAssumption.swift`) — worth a one-time sweep now that the pattern has mostly stuck.
4. **Establish a repo-wide `Logger` privacy default of `.private` for user-authored content and identifiers.** §6.4's four independent hit locations (SharePlay, six Link/Edit controllers, import review) show this isn't one file's oversight but a missing house style. A lint rule or code-review checklist item would be cheaper than chasing each site.
5. **The on-device AI assist (`GeneratorController`) needs per-item/per-window scoping and its error state needs to actually reach the UI.** §5.6-§5.8, §5.15-§5.18 are nine distinct findings in one ~1,000-line controller, several stemming from the same shared-session design (§5.8) and the same never-wired-up `tearDown()` (§5.6, §5.18). This is the single highest-density cluster of Medium/High bugs in the audit and would benefit from a dedicated pass rather than one-off fixes.
6. **Untrusted Foundry archive input needs uniformly-applied resource bounds.** The import pipeline already has the right primitives (JSON depth counter, pixel-dimension caps, cycle detection, chunked parsing) — §5.13, §6.1, §6.2 are all cases where an existing safeguard simply wasn't applied to one of several parallel code paths. A shared "untrusted decode" checklist (depth guard set? pixel cap checked? cycle-safe?) applied at each new Foundry entry point would catch this class going forward.

---

## 11. What was NOT audited

- No `Dead/` or archived directory exists in this repo, so nothing was excluded by convention.
- Algorithmic correctness of the Foundry VTT domain-mapping logic beyond surface-level bug/duplication scanning — the actual game-rule/scene-conversion semantics were not verified against Foundry's own data model.
- Xcode project/build settings and scheme configuration beyond what's visible via the Xcode MCP's shared-scheme list and a clean build.
- Third-party SPM dependency internals: `swift-snapshot-testing`, `swift-custom-dump`, `swift-syntax`, `xctest-dynamic-overlay`, and the local `RPGTabletopGameContent` package are treated as black boxes. The vendored NavigatorUI copy under `Modules/CoreRPG/Navigator/` was reviewed only at the specific lines cited in §3.3/§4.1, not in full.
- Test coverage assessment — `Tests/` was scanned for TODOs/dead code/print()s and the one App Intents crash workaround (§9.11), but no deep review of test quality or coverage gaps.
- Localization and String Catalog content — presence of `bundle: .module`/`LocalizedStringResource` was spot-checked incidentally, but wording/translation quality was not assessed.
- StoreKit 2 product configuration in `Modules/RolePlayGameKit/InApp/MasterRPG.storekit` — file structure only, not whether each product matches App Store Connect.
- Performance profiling via Instruments — findings in §7 are static-analysis-identified *potential* hot paths (per-gesture allocations, repeated re-parsing, linear scans), not measured hitches or CPU traces.
- macOS/tvOS-specific code paths received lighter scrutiny than iOS/visionOS, matching where the most recent commits (dice overlay, map toolbar, ornament rework) actually landed.
- CoreData-to-CloudKit migration correctness and conflict-resolution semantics beyond what surfaced incidentally in §3.1/§3.2.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line.

Both Critical findings, and several Highs central to the executive summary, were personally opened and confirmed (not just propagated from an agent) before inclusion:

- **§5.1** — open `Sources/RPGShare/SharingView.swift:50` (the default-parameter expression), `Sources/RPGShare/ShareViewController.swift:13-14,30-33` (the comment explaining why this was removed once, and the call site that never supplies `useCloudKit:`), and `Modules/RolePlayGameKit/Model/AppModel.swift:29-31,121-220` (confirms `AppModel.init()` builds every module root model, four Navigators, and its own `DataBaseModel`).
- **§5.2** — open `Modules/SpaceRPG/View/InlineImporterView.swift:132` (the plain file-importer's correct `resetFile` call) against `:142-146` (the scanner's bare, itemId-less presentation) and `Modules/SpaceRPG/Record/ReconstructionPrimaryView.swift:20-24` (completion closure calls only `endCapture()`). A repo-wide grep for `resetFile`/`editController`/`itemController` inside `Modules/SpaceRPG/Record/` returns nothing.
- **§5.3** — open `Modules/GameRPG/Root/GameRootModel.swift:609` (`gameModel.playerController = player` assigned synchronously mid-`startGame`) against `:665-688` (`stopGame()`'s unconditional `nil`-outs after several `await` points) and `MasterGameScreen.swift:186-191` (`endGame()`'s unstructured `Task`).
- **§5.4** — open `MasterGameScreen.swift:85-87` (`.onDisappear` body) and confirm it never calls `stopGame()`/`endGame()`.
- **§5.8** — open `Modules/GeneratorRPG/Root/GeneratorRootModel.swift:137-142` and confirm the dictionary is keyed by `NetworkModules` only, with 4 fixed keys, not per-item.
- **§6.2** — open `Modules/CoreRPG/Foundry/FoundryImportArchive.swift:219-227` and confirm `JSONDecoder()` is constructed with no `userInfo` assignment, unlike the three sibling sites named in the finding.
- **§8.1/§8.3/§8.4** — open `Modules/GameRPG/GameViews/OverlayGameMenu.swift`: lines 37-338 for the computed-`var` decomposition, line 118 for `.toggle()`, lines 122/137/157 for the fixed `.frame(height: 24)`.
- **§9.1 (block comment)** — open `Modules/GeneratorRPG/Controller/GeneratorController.swift:492` and `:1059` to confirm the `/* ... */` boundaries.

If any finding doesn't reproduce when you visit the line, flag the specific reference and it will be re-investigated.
