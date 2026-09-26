# MasterRPG Code Audit

Generated 2026-09-26 (18th audit). Scope: 2,100 Swift files (~273k LOC; ~196k LOC of production code in `Modules/` and `Sources/`, ~77k LOC of tests) across the MasterRPG (iOS/iPadOS/visionOS), MasterMac, MasterTV, RPGShare and DiceRollerWidget targets and 15 modules. No Metal/other kernels exist. `Docu/`, `Snapshots/`, `Integrations/`, `.git`, `.build` and `DerivedData` are excluded; `Tests/` got quick reads only. No `Dead/` folder exists.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code was changed.

**Ground truth (compiler).** Clean full Debug builds, Swift 6 mode, `SWIFT_STRICT_CONCURRENCY = complete`, Xcode 27 RC:

| Scheme / destination | Result | Swift warnings |
|---|---|---|
| MasterRPG, iOS Simulator | BUILD SUCCEEDED | 0 |
| MasterMac, macOS | BUILD SUCCEEDED | 0 |
| MasterTV, tvOS Simulator | BUILD SUCCEEDED | 0 |
| MasterRPG, **visionOS Simulator** | **BUILD FAILED** (exit 65) | 1 error, see §5.1 |

The only other diagnostics were "appintentsmetadataprocessor: Metadata extraction skipped" tool notices. Because the visionOS build stops in DiceRPG, the modules that depend on it (GameRPG, RolePlayGameKit, app target) were **not** compiled for visionOS in this audit. No tests were run.

**Relationship to earlier audits.** Seventeen earlier audits live in `Docu/CODE_AUDIT_*.md`. Since CODE_AUDIT_17 (2026-09-21, base commit `c931b6af`), a remediation pass changed 364 source files. This audit had two goals: (1) re-check that pass for regressions and incomplete fixes, and (2) re-verify items still open. The tags used:
- **[REGRESSION]** — the post-`c931b6af` pass introduced the defect.
- **[INCOMPLETE FIX]** — an audit-17 item marked fixed that does not fully work.
- *(still open from CODE_AUDIT_17 §X.Y)* — re-verified as still present.
- Items with a "won't fix"/"accepted risk" decision in CODE_AUDIT_17 (§6.1 player overwrite by id, 4-digit join code, hex cells as entries) were not re-reported.

**How to read verification.** **[verified]** means I re-read the cited lines myself after an agent reported them (see §12). Items without the tag were read by the agent that reported them but not independently re-read; treat their line numbers as reliable and their severity as the agent's estimate. Where I changed an agent's severity, the finding says so. One agent finding was dropped: a `.public` log of PDF-derived content at `PdfSummaryAnalysisView.swift:176` is inside a `#Preview`.

**Result in one line.** No Critical findings. Two High: the visionOS build is broken by today's dice-style commit (§5.1), and the audit-17 §5.7 fix turned the sync-deletion diff into permanent loss of unsaved new items (§5.2). Beyond those, the main pattern is that several audit-17 fixes don't take effect on some path: the iOS background flush (§3.1), the readiness gate (§3.2), the cloud-URL prewarm (§3.3) and the save rollback (§5.3).

---

## 1. Executive summary

Top items to address, in priority order:

1. **[High] visionOS build fails: ungated `.glassEffect` added in today's commit** — §5.1 — `Modules/DiceRPG/Game/Detail/DicePlayer.swift:63`. The MasterRPG scheme cannot be built or shipped for visionOS. **[verified]** **[REGRESSION]**
2. **[High] Sync-deletion diff now deletes the queued insert of every unsaved new item** — §5.2 — `Modules/CoreRPG/Controllable/SyncDataControllable.swift:73-79`, `ItemControllable.swift:142`. A remote deletion (or a failed id fetch) during the autosave window permanently loses duplicated/imported items. **[verified]** **[REGRESSION of §5.7]**
3. **[High] The iOS/visionOS background-save assertion is never taken** — §3.1 — `Sources/MasterRPG/iOS/iOSAppDelegate.swift:15-36`. `applicationDidEnterBackground` is not called in a scene-based app, so audit-17 §5.2 is only fixed on macOS. **[verified]** **[INCOMPLETE FIX]** (agent C rated this Medium, agent A High; I kept High because it silently reopens a data-loss item marked fixed.)
4. **[Medium] A failed save rolls back every module's flushed edits and never re-queues them** — §5.3 — `Modules/CoreRPG/Persistence/CoreDataController.swift:220-236`. **[verified]** **[INCOMPLETE FIX §5.6]**
5. **[Medium] A far-future CRDT clock now freezes a field permanently** — §5.5 — `Modules/CoreRPG/CRDT/WallclockTimestamp.swift:120-125`, `LWWRegister.swift:70-84`. **[verified]** **[REGRESSION of §5.15]**
6. **[Medium] Readiness is signalled before modules have loaded, and Dice caches the empty result** — §3.2 — `Modules/RolePlayGameKit/Model/AppModel.swift:428`, `Modules/DiceRPG/Intent/DiceEntity.swift:143-163`. **[verified]** **[INCOMPLETE FIX]**
7. **[Medium] The hex-grid cell cap silently erases the grid on large maps** — §5.6 — `Modules/MapRPG/Map/MapHexGridGeometry.swift:26,41`. **[verified]** **[REGRESSION of §5.16]**
8. **[Medium] Map-recovery throttle gives honest players no reply and is bypassable by cycling map ids** — §6.1 — `Modules/GameRPG/Controller/MasterController+MapMessages.swift:217-243`. **[verified]** **[REGRESSION of §6.7]**
9. **[Medium] PDF extraction swallows cancellation and keeps running on every page** — §3.4 — `Modules/GeneratorRPG/BasicAI/Providers/PdfContentExtractor.swift:86-117`. **[verified]** **[REGRESSION]**
10. **[Medium] New `RawDie.Sides.three` case changes the wire/storage format for d3** — §5.8 — `Modules/DiceRPG/Model/RawDie.swift:95-104,139-158`. **[verified]**

---

## 2. Quick wins (≤30 min each)

- **Gate the new `.glassEffect` with `#if !os(visionOS)`** (or route through `gameOverlayCapsuleControlStyle`) — `Modules/DiceRPG/Game/Detail/DicePlayer.swift:61-63` (§5.1).
- **Restore the 44 pt minimum in both game overlay button styles** — `Modules/CoreRPG/Buttons/OverlayButtonStyle.swift:122-123,144-145` (§8.1).
- **Move the background-task flush to a `scenePhase == .background` handler** — `Sources/MasterRPG/iOS/iOSAppDelegate.swift:15-36` (§3.1).
- **Rethrow `CancellationError` in the per-page catch** — `Modules/GeneratorRPG/BasicAI/Providers/PdfContentExtractor.swift:108-112` (§3.4).
- **Remove `.die12(color: .D)` from the dice bag and rename `D20c-1.imageset` to `D20C-1`** — `Modules/DiceRPG/View/DiceBag.swift:15`, `Resources/RPGResources/Resources/DiceAssets.xcassets/D20c-1.imageset` (§5.9).
- **Call `DiceEntityQuery.invalidateCache()` from dice add/rename/delete, or delete it** — `Modules/DiceRPG/Intent/DiceEntity.swift:169-175` (§5.10).
- **Use `@StateObject` for `GroupStateObserver`** — `Modules/GameRPG/SetupViews/SharePlayButton.swift:21-22` (§8.2).
- **Skip the send when `encodedOffMain` returns nil** — `Modules/GameRPG/Master/MasterNetworkController.swift:198-225` (§3.15).
- **Reply `.failed` when throttling map recovery, and record the timestamp only after success** — `Modules/GameRPG/Controller/MasterController+MapMessages.swift:226-231` (§6.1).
- **Add a timeout to the macOS `.terminateLater` save** — `Sources/MasterRPG/macOS/macOSAppDelegate.swift:14-20` (§3.11).
- **Call `spotlightIndexer?.stopSpotlightIndexing()` in `CoreDataInitModel.stop()`** — `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:106-111` (§3.13).
- **Delete the two never-compiled widget files, the ghost pbxproj exceptions and the missing `MasterRPG.entitlements` reference** — §9.1, §9.2.

---

## 3. Concurrency

The compiler reports nothing (see the ground-truth table), so everything here is lifecycle, ordering, reentrancy or cancellation.

### 3.1 The iOS/visionOS background-flush fix is never invoked (scene-based app) **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_17 §5.2]**
- **Location:** `Sources/MasterRPG/iOS/iOSAppDelegate.swift:15-36` (scene configuration at `:38-46`)
- **What:** The `beginBackgroundTask` + `AppModel.shared.save()` flush lives in `applicationDidEnterBackground`, but the app is scene-based (SwiftUI `App` plus `configurationForConnecting` returning `IosSceneDelegate`), and UIKit does not call app-delegate lifecycle methods for scene-based apps.
- **Why:** On iOS and visionOS no background-task assertion is ever taken, so the resign-active save can still be suspended mid-flight and recent edits lost. If the method did run, a second background entry would also overwrite `backgroundFlushTaskId` and leak the first assertion.
- **Action:** Start the assertion from a `scenePhase == .background` handler (or `sceneDidEnterBackground` in `IosSceneDelegate`) and keep one identifier per flush, ending that same identifier.
- **Severity:** High
- **Status (2026-09-26):** FIXED. The background-task flush moved to `IosAppDelegate.beginBackgroundFlush()`, triggered from the app-level (aggregate) `scenePhase == .background` in `MasterRPGApp`. Each flush keeps its own identifier (keyed by a token), so overlapping flushes no longer overwrite and leak an assertion.

### 3.2 Database readiness is signalled before any module has loaded its items **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_17 §3.2]**
- **Location:** `Modules/RolePlayGameKit/Model/AppModel.swift:414-435` (`markReady()` at `:428`); `Modules/CoreRPG/Controllable/SyncDataControllable.swift:35-39,109-119`; `Modules/DiceRPG/Intent/DiceEntity.swift:143-163`
- **What:** `setupRootModels` calls `DatabaseReadiness.markReady()` right after `adventureRoot.setUp`, but each module's initial `fetchAll()` runs later in the unstructured `Task` returned by `SyncDataControllable.start()`.
- **Why:** A cold-launch intent passes the gate and still sees empty `items`. Because `isReady` is already true, the new "don't cache an empty result before ready" guard in `suggestedEntities()` does cache it, and serves it for 60 s.
- **Action:** Mark ready only after every module's initial sync task has finished (await the stored tasks), and never cache an empty Dice result on the first load.
- **Severity:** Medium
- **Status (2026-09-26):** FIXED. `SyncDataControllable.start()` registers each module's initial load synchronously with the new `InitialLoadTracker`; `DatabaseReadiness.isReady` is now `rootModelsReady && every initial load finished`, and waiters resume only then. The Dice result cache that stored the empty list was removed (§5.10).

### 3.3 The cloud-URL prewarm doesn't keep resolution off the main thread, and never re-resolves **[INCOMPLETE FIX of CODE_AUDIT_17 §5.19]**
- **Location:** `Sources/MasterRPG/MasterRPGApp.swift:29-33`; `Modules/CoreRPG/App/AppGroup.swift:55-68`; `Modules/CoreRPG/Files/LocationFileManager.swift:12-19`; `Modules/CoreRPG/Files/FileUrlDataController.swift:37-46`
- **What:** `Task.detached { await FileManager.prewarmCloudUrls() }` starts in `App.init`, and the very next statement builds `AppModel.shared`. That chain (`ItemController` → `FileUrlDataController` → `LocationFileManager.init`) reads the lazy `static let cloudURL` synchronously on the main thread.
- **Why:** The `static let` initializer is guarded by a once-lock, so the main thread either resolves `url(forUbiquityContainerIdentifier:)` itself or blocks waiting for the detached task: the launch hitch remains. A session started while iCloud was unavailable also keeps writing to the group container for its whole lifetime.
- **Action:** Resolve the container roots through an explicit async step that callers await before the first file access, and re-resolve when `NSUbiquityIdentityDidChange` fires.
- **Severity:** Medium

### 3.4 PDF extraction swallows cancellation and reports partial output as success **[verified]** **[REGRESSION, cfa35bdb]**
- **Location:** `Modules/GeneratorRPG/BasicAI/Providers/PdfContentExtractor.swift:86-117`
- **What:** The per-page `do/catch` added for audit-17 §5.20 has a generic `catch` that also catches `CancellationError`, and the loop never checks `Task.isCancelled`.
- **Why:** A cancelled extraction keeps walking every remaining page, creating and prewarming a new `LanguageModelSession` per page, logging spurious failures and returning partial blocks as if it had succeeded.
- **Action:** Check cancellation at the top of each iteration and rethrow `CancellationError` before the generic per-page catch.
- **Severity:** Medium

### 3.5 PDF text extraction for FoundationModels runs on the main actor
- **Location:** `Modules/GeneratorRPG/BasicAI/Providers/PdfContentExtractor.swift:37-54,122-145`; `PdfSummaryAnalyzer.swift:~130-145`; caller `Modules/GeneratorRPG/BasicAI/Model/PdfContentExtractionModel.swift:25-41`
- **What:** `extractWithProgress` is a nonisolated async method on a `Sendable` struct. Under approachable concurrency (nonisolated-nonsending by default) it runs on the caller's actor, so `page.string` for up to 20 pages executes on the main actor.
- **Why:** A large PDF causes a visible UI hitch before generation even starts.
- **Action:** Mark the text-extraction step (or the analyzer entry point) `@concurrent`.
- **Severity:** Medium

### 3.6 On-device LLM view actions run in unowned Tasks that outlive the sheet
- **Location:** `Modules/GeneratorRPG/View/TableSummaryAnalysisView.swift:64-71`; `PdfSummaryAnalysisView.swift:42-49`; `PdfContentExtractionView.swift:37-43`; `BatchTextSummaryExtractionView.swift:195-225`
- **What:** Button actions start `Task { await model.analyze…/performBatch() }`, and the task is never stored or cancelled.
- **Why:** Dismissing the sheet leaves multi-page FoundationModels work running, and the batch loop keeps writing results into items through `applyResult` after the user has left.
- **Action:** Store the task in the model (or drive it with `.task(id:)`) and cancel it on disappear.
- **Severity:** Medium

### 3.7 Audio playlist replacement is re-entrant across its await, and concurrent loads share temp filenames
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:109-146` (callers `:198-210`, `:365-369`; `Modules/AudioRPG/Controller/GameController.swift:189,196`; `SharingActionView.swift:45`)
- **What:** With `replace: true` the method clears `playList` and deletes the temp copies, then awaits a task group before appending. A second call (shared-audio observation, `loadAndPlay`, game reveal) can interleave during that await.
- **Why:** Both calls append, so the playlist ends up mixed or duplicated. Both also copy to `temporaryDirectory/<id>.<ext>`, so one call can delete a file that the other's `AVURLAsset` is still loading.
- **Action:** Serialize playlist replacement (a generation token checked after the await, or one chained task) and give each load a unique temp name.
- **Severity:** Medium

### 3.8 `GroupSession.join()` runs in `Task.detached`, with the Sendable diagnostic hidden by `@preconcurrency import`
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:386-403` (`@preconcurrency import GroupActivities` at `:8` and in 5 other files)
- **What:** `GroupSession` is a non-Sendable class. `join()`/`leave()` run on a detached executor while main-actor tasks read `$state` and `activeParticipants` and assign `.activity`.
- **Why:** This is a data race the compiler cannot report, because `@preconcurrency` suppresses the diagnostic.
- **Action:** Call `join()` on the main actor in a deferred turn (as the TabletopKit path does), and drop `@preconcurrency` from the GroupActivities imports to surface other crossings.
- **Severity:** Medium

### 3.9 PDF find: `pendingMatches` race, strong `PDFView` capture, global retroactive `Sendable` *(still open from CODE_AUDIT_17 §3.8)*
- **Location:** `Modules/PdfRPG/Pdf/PdfWrapperView.swift:20-26,118-176`
- **What:** `beginSearch` resets `pendingMatches` on main without `cancelFindString()`, while PDFKit's search thread may still be appending from the previous `beginFindString`. `documentDidEndDocumentFind` reads the array off-main. The `setSearchMatch` closure stored on `searchModel` captures `pdfView` strongly. `PDFDocument`/`PDFSelection` stay `@unchecked @retroactive Sendable` app-wide.
- **Why:** An unsynchronized Swift array race when a new search starts; the `PDFView` and its document stay alive as long as the search model does; and Sendable checking is off for PDFKit in every importing module.
- **Action:** Call `cancelFindString()` before resetting, hop `didMatchString` to the main actor (or guard the buffer with a `Mutex`), capture `pdfView` weakly, and replace the detached document load with an `@concurrent` function so the retroactive conformances can go.
- **Severity:** Medium

### 3.10 Statistics batch flush is not serialized, and a failed batch is dropped **[REGRESSION, 16109934]**
- **Location:** `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:151-186` (callers `:77-103`, `:188-219`)
- **What:** `flushPendingEvents` empties `pendingEvents`/`pendingRoster` and then awaits two separate `perform` calls. `finishSession`/`beginSession` call it again, see an empty buffer and continue while the timer flush is still suspended. The buffer is not restored when `recordEvents`/`checkpointSession` throws.
- **Why:** The in-flight roster checkpoint can land on an already-finished session, and its `lastCheckpointedRosterIds` assignment can overwrite `beginSession`'s reset. A save failure, which can come from another module's invalid object on the shared context, drops up to 100 events.
- **Action:** Chain flushes through one stored task that `finishSession`/`beginSession` await, and re-queue the batch on failure (with a retry cap).
- **Severity:** Low

### 3.11 macOS quit can hang indefinitely on `.terminateLater` **[REGRESSION, e9dc72fa]**
- **Location:** `Sources/MasterRPG/macOS/macOSAppDelegate.swift:14-20`
- **What:** `applicationShouldTerminate` returns `.terminateLater` and replies only after `await AppModel.shared.save()` returns, with no deadline.
- **Why:** A save stuck on file coordination or a Core Data `perform` makes Cmd-Q do nothing. The user then has to force-quit, which loses exactly the data the change was meant to protect.
- **Action:** Race the save against a short deadline (a few seconds), always reply, and log when the save didn't finish.
- **Severity:** Medium (agent C rated Low, agent A Medium; kept Medium because it blocks quitting)
- **Status (2026-09-26):** FIXED. `applicationShouldTerminate` still returns `.terminateLater`, but always replies within `terminationSaveDeadline` (5 s): a guarded reply from the save task or the deadline task, whichever comes first, with an error log when the deadline wins.

### 3.12 Continuations that ignore caller cancellation
- **Location:** `Modules/CoreRPG/App/DatabaseReadiness.swift:31-48`; `Modules/GameRPG/Player/PlayerNetworkController.swift:125-179`
- **What:** `wait()` and `toggleConnection` park a `CheckedContinuation` with no cancellation handler; they resume only on `markReady`/handshake or on their 20 s / 12 s timeout Tasks.
- **Why:** A cancelled App Intent or a dismissed join sheet keeps its task alive for up to 20 s / 12 s.
- **Action:** Wrap each in `withTaskCancellationHandler` that removes and resumes the stored continuation.
- **Severity:** Low
- **Status (2026-09-26):** PARTLY FIXED. `DatabaseReadiness.wait()` now resumes on task cancellation (`withTaskCancellationHandler`). `PlayerNetworkController.toggleConnection` is handled with the network items (see its own status).

### 3.13 `CoreDataInitModel.stop()` leaves the Spotlight indexer running on the replaced store **[INCOMPLETE FIX of CODE_AUDIT_17 §3.9]**
- **Location:** `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:106-111` (indexer started at `:174,235`; `CloudKitCoreDataPersistenceController.swift:84,172`)
- **What:** `stop()` cancels `cleanupTask` and `cloudKitEventMonitoringTask` only; `spotlightIndexer` never gets `stopSpotlightIndexing()` and `persistentHistoryTracker` is not torn down.
- **Why:** After a local↔CloudKit swap, the old `NSCoreDataCoreSpotlightDelegate` keeps indexing the old coordinator into the same index and keeps that container alive.
- **Action:** Stop the indexer and release the tracker and indexer in `stop()`.
- **Severity:** Low

### 3.14 Persistent-history `process()` can overlap itself *(still open from CODE_AUDIT_17 §3.11)*
- **Location:** `Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift:167-215`
- **What:** `schedule()` cancels the debounce task, but a `process()` already past its sleep ignores cancellation, and actor reentrancy at `perform`/merge lets a second pass start from the same `loadDate()`.
- **Why:** The same transactions are merged twice.
- **Action:** Keep an `isProcessing` flag or chain passes, and check cancellation between fetch and merge.
- **Severity:** Low

### 3.15 LAN sends: reordering across `encodedOffMain`, and a nil encode sent as an empty frame
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:196-227`; `Modules/GameRPG/Model/GameMessagePipeline.swift:314-318`; `Modules/GameRPG/Network/ConnectionController.swift:127-141,269-285`
- **What:** Each `sendResponse` suspends in `@concurrent encodedOffMain` before calling `connection.response`, so a small message sent after a large one can reach the connection first *(still open from CODE_AUDIT_17 §3.11)*. `encodedOffMain` returns nil when the calling task is cancelled, and callers still send it. The framer then writes a zero-length body, which the receiver's `content == nil` branch treats as "Peer closed the connection".
- **Why:** A pin or map-state update can arrive before the map it refers to. A cancelled send (for example a `scheduleNetworkAction` cancelled by `stopGame`) can disconnect players.
- **Action:** Skip the send when the encoded payload is nil, and serialize outbound frames per connection (an ordered send queue owned by `ConnectionController` that also does the encoding).
- **Severity:** Low (the empty-frame → EOF path is plausible from reading; confirm with a LAN test)

### 3.16 NWListener callbacks are still unordered per-event Tasks *(still open from CODE_AUDIT_17 §3.11)*
- **Location:** `Modules/GameRPG/Network/ListenerManager.swift:184-191`
- **What:** `stateUpdateHandler`/`newConnectionHandler` each spawn `Task { await self.handle… }`, although `ConnectionController` already switched to an ordered `AsyncStream` for the same problem.
- **Why:** `.ready` can be processed after `.failed`/`.cancelled`, and since 031194aa that ordering drives `listenerStatus`.
- **Action:** Yield raw events into an `AsyncStream` continuation directly from the handlers, as `ConnectionController.swift:100-110` does.
- **Severity:** Low

### 3.17 Fixed `Task.sleep` delays still used as readiness synchronisation *(still open from CODE_AUDIT_17 §3.7)*
- **Location:** `Modules/RolePlayGameKit/Model/AppModel.swift:535-556,602-604,645-648`; `Modules/RolePlayGameKit/Route/WindowRouter.swift:187-190`; `Modules/CoreRPG/Controllable/FolderListControllable.swift` (5 sleeps); `Modules/SpaceRPG/Space/SpaceViewer.swift:630`
- **What:** Cross-window routing and selection restore wait a fixed delay (`crossWindowRouteDelay`, 150 ms) and assume the target stack has mounted by then.
- **Why:** On slow devices or cold visionOS scenes the route is silently dropped.
- **Action:** Replace with a pending-route queue that is drained when the receiving navigator registers.
- **Severity:** Medium

### 3.18 Isolation escape hatches: stale `@unchecked Sendable` and blanket `@preconcurrency` *(partly still open from CODE_AUDIT_17 §3.10)*
- **Location:** `@unchecked Sendable`: `Modules/CoreRPG/Instrumentation/PerformanceTrace.swift:23`, `Modules/GameRPG/Table3D/GameBoard.swift:138`, `Modules/CoreRPG/Foundry/FoundryRuleModels.swift:170`, `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:253`, `CloudKitCoreDataPersistenceController.swift:293`. `@preconcurrency import CoreData`: `CoreDataController.swift:4`, `CoreDataChangeObserver.swift:4`, `CoreDataPersistenceController.swift:3`, `CloudKitCoreDataPersistenceController.swift:3`, `PersistentHistoryTrackerManager.swift:4`. `nonisolated(unsafe)`: `Modules/CoreRPG/Extensions/Encoder+MainActor.swift:25`.
- **What:** Several annotations are no longer needed (`CGImage`/`CGColor` are Sendable; the Core Data containers and context are annotated in the iOS 27 SDK). `FoundryJSONDepthCounter` keeps an unsynchronized `var`. The "predates Sendable" comments are out of date.
- **Why:** Each unneeded `@unchecked`/`@preconcurrency` turns off checking that would now pass and hides future mistakes.
- **Action:** Switch `Interval` and `BoardTextureInput` to checked `Sendable`, back the depth counter with `Atomic<Int>`/`Mutex`, and remove `@preconcurrency` from the Core Data imports, fixing whatever the compiler then reports.
- **Severity:** Low

### 3.19 Remaining narrow ordering races *(still open from CODE_AUDIT_17 §3.11/§3.12)*
- **Location:** `Sources/DiceRollerWidget/DiceRollerIntents.swift:34-56` vs `Modules/DiceRPG/Controller/GameController.swift:610-645` (widget process has no lock, so a widget roll can be lost); `Modules/PhotoRPG/Space/ImagePresentationView.swift:65-92` (`sceneUpdateSubscription` never cancelled on disappear); `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:47-58` (macOS shared-image mutation); `Modules/CoreRPG/Views/SendFeedbackButton.swift:96-111` (stale feedback timeout)
- **What:** All still behave as described in CODE_AUDIT_16 §3.13-§3.21.
- **Why:** Each is a narrow race: a lost widget roll, a leaked RealityKit subscription, a shared-image mutation, or a stale timeout.
- **Action:** Apply the CODE_AUDIT_16 actions; use `.task(id:)` for the feedback button.
- **Severity:** Low

### 3.20 App-level wiring started from unstructured Tasks
- **Location:** `Sources/MasterRPG/MasterRPGApp.swift:78-90`; `Modules/RolePlayGameKit/View/AppEnvironmentSetUpViewModifier.swift:63-66`; `Modules/RolePlayGameKit/InApp/InAppModel.swift:83-86`
- **What:** `AppIntentContentInvalidator.configure` still runs inside `Task { @MainActor in … }` in `App.init` (the pattern audit-17 §3.3 removed for `DatabaseReadiness`). `Transaction.updates` is only observed after `await inAppController.prepare()` inside a window's `.task`.
- **Why:** An `invalidate()` that fires before the Task runs finds nil closures and does nothing, and transactions are not observed during launch or when no window exists.
- **Action:** Configure the invalidator synchronously in `init`, and start the transaction listener from `App.init`.
- **Severity:** Low

### 3.21 Recursive `withObservationTracking` re-arming instead of `Observations`
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:386-409`; `Modules/GameRPG/Player/PlayerNetworkController.swift:439-470`; `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:797-827`
- **What:** Each change goes `onChange` → `Task` → `Task` → re-arm, the pattern `AudioController.swift:352-361` already replaced with `Observations`.
- **Why:** Two unstructured hops per change, and this chain has broken before when an early return skipped the re-arm (CODE_AUDIT_15 §3.8).
- **Action:** Replace each with one stored `for await … in Observations { … }` task.
- **Severity:** Low

---

## 4. API modernity

### 4.1 Soft-deprecated SwiftUI/UIKit APIs still in use
- **Location:** `.accentColor`: `Modules/CoreRPG/Theme/AppThemeEnvironment.swift:53`, `Modules/CoreRPG/Buttons/OverlayButtonStyle.swift:168`. `.autocapitalization`/`.disableAutocorrection`: `Modules/CoreRPG/Editors/AddTagsEditor.swift:45,48`, `TextIntEditor.swift:74,77`, `TextDoubleEditor.swift:129,132`, `Modules/CoreRPG/Inspector/LinkItemFilterFieldView.swift:21`. `.statusBar(hidden:)`: `Modules/GameRPG/ExternalScreen/ExternalGameRootView.swift:18`. `application(_:handleOpen:)`: `Sources/MasterRPG/iOS/iOSAppDelegate.swift:48-54`.
- **What:** Deprecated APIs. `application(_:handleOpen:)` has been deprecated since iOS 9 and is never called in a scene-based app.
- **Why:** Deprecation noise, plus one dead URL-handling path that looks live.
- **Action:** Use `.tint`, `.textInputAutocapitalization(.never)`, `.autocorrectionDisabled()` and `.statusBarHidden()`; delete `handleOpen` (the scene's `openURLContexts` already handles URLs).
- **Severity:** Low

### 4.2 Combine and closure-based notification observers remain *(partly still open from CODE_AUDIT_17 §4.4)*
- **Location:** `Modules/CoreRPG/Persistence/CoreDataChangeObserver.swift:32-57`; `PersistentHistoryTrackerManager.swift:72-84,119-125`; `Modules/AudioRPG/Controller/AudioController.swift:289-315,327-331`; `Modules/AudioRPG/Audio/AudioPlayerSession.swift:94-114`; `Modules/RolePlayGameKit/View/AppEnvironmentSetUpViewModifier.swift:56-62` with the string-named notification at `Modules/CoreRPG/Tips/MasterRPGTips.swift:132,274`
- **What:** `publisher(for:)`/`sink`, `addObserver(forName:queue:)` closures, a periodic time observer on `queue: nil` that allocates a Task per tick, and a custom `Notification.Name` used as an in-app event bus.
- **Why:** Per-event Task hops lose ordering (for example `timeControlStatus` updates), and untyped notifications bypass isolation checking.
- **Action:** Move to `NotificationCenter.notifications(named:)` or typed messages, `addPeriodicTimeObserver(queue: .main)`, and `await container.performBackgroundTask`; replace the tip notification with a direct model call.
- **Severity:** Low

### 4.3 NSItemProvider and DropDelegate completion wrappers *(still open from CODE_AUDIT_17 §4.4)*
- **Location:** `Modules/PhotoRPG/Controller/ItemController.swift:47-63`; `Sources/RPGShare/ItemProviderImporter.swift:224-251`; `Modules/CoreRPG/Files/FileDropDelegate.swift:31-47`
- **What:** `loadDataRepresentation`/`loadItem`/`loadObject(ofClass:)` are wrapped in hand-written continuations or callbacks.
- **Why:** None is cancellable, while async overloads and `.dropDestination(for:)` exist on the deployment target.
- **Action:** Use the async `NSItemProvider` overloads and `dropDestination`.
- **Severity:** Low

### 4.4 Hand-rolled `Task.detached` + cancellation-handler boilerplate at 16 sites *(still open from CODE_AUDIT_17 §3.12)*
- **Location:** `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:21,47,72`; `FoundryVTTImportReader.swift:28,90,194`; `UniversalVTTReader.swift:165,187`; `Modules/RolePlayGameKit/Import/Foundry/FoundryMediaNormalizer.swift:30`; `FoundryRuleImportModel.swift:105`; `Modules/CoreRPG/Files/FileManager+Coordination.swift:98`; `FileUrlDataController.swift:674`; `Modules/GameRPG/Controller/MasterController+Messaging.swift:151`; `Modules/PdfRPG/Controller/ItemController.swift:59`; `Sources/RPGShare/ItemProviderImporter.swift:136,255`
- **What:** Each site builds `Task.detached` + `withTaskCancellationHandler` by hand to leave the caller's executor.
- **Why:** `@concurrent` functions give the same result with structured cancellation and no escaping capture; the copies are error-prone (see §9.10 for the security-scope variant).
- **Action:** Convert each site to an `@concurrent` function.
- **Severity:** Low

### 4.5 NWConnection/NWListener bridged through DispatchQueues where iOS 26 structured Network APIs exist
- **Location:** `Modules/GameRPG/Network/ConnectionController.swift:34-112,239-255`; `Modules/GameRPG/Network/ListenerManager.swift:142-210`
- **What:** The two actors bridge queue callbacks through a DispatchQueue, a continuation per receive and a Task per event. `BrowserManager` already uses the iOS 26 `NetworkBrowser`.
- **Why:** This bridging is the source of the ordering issues in §3.15/§3.16.
- **Action:** Evaluate `NetworkConnection`/`NetworkListener` (async, framer-capable) for the LAN transport.
- **Severity:** Low

### 4.6 Navigator identity and equality derived from `hashValue`
- **Location:** `Modules/CoreRPG/Navigator/Core/NavigationDestination.swift:173-181`; `Modules/CoreRPG/Navigator/Protocols/Binding+Extension.swift:46-48`
- **What:** `NavigationDestination.id` is `hashValue`, and `==` compares ids; `Binding ==` compares `hashValue`.
- **Why:** A hash collision makes different destinations compare equal (SwiftUI may then skip a navigation), and ids change on every launch if they are ever restored.
- **Action:** Base `==` on the underlying values and use a stable id.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 visionOS build fails: ungated `.glassEffect` in `DicePlayer` **[verified]** **[REGRESSION, 396b6052]**
- **Location:** `Modules/DiceRPG/Game/Detail/DicePlayer.swift:59-64`
- **What:** Today's commit "fixed: the player dice style" added `.glassEffect(.regular.interactive(), in: .capsule)` to the non-button branch without a platform guard; `glassEffect(_:in:)` is unavailable in visionOS (`error: 'glassEffect(_:in:)' is unavailable in visionOS`).
- **Why:** The MasterRPG scheme cannot be built for visionOS, so no visionOS build can ship, and downstream modules (GameRPG, RolePlayGameKit, app target) weren't type-checked for visionOS in this audit. Every other `glassEffect` site is already gated (checked all call sites).
- **Action:** Wrap it in `#if !os(visionOS)` with a visionOS fallback, as `OverlayButtonStyle.swift:101-108` does, and add a visionOS build to the pre-commit/CI check.
- **Severity:** High

### 5.2 The sync-deletion diff now discards the queued insert of every unsaved new item **[verified]** **[REGRESSION of CODE_AUDIT_17 §5.7, e32f7d67]**
- **Location:** `Modules/CoreRPG/Controllable/SyncDataControllable.swift:73-79`; `Modules/CoreRPG/Controllable/ItemControllable.swift:128-143` (`removePendingOperations` at `:142`), `:443-458` (`updates(_:)`); `Modules/CoreRPG/Persistence/CoreDataController.swift:481-508` (`fetchId` returns `[]` on error)
- **What:** `updateFromSync` treats every in-memory id missing from a fresh `fetchIds()` as deleted and calls `delete(withDatabase: false)`. An item created through `replace(isInsert: true)` is only queued (`replaceSync` → `queueReplace`) until the next flush, so it is "missing" too. `delete` now also calls `removePendingOperations`, which removes that queued insert.
- **Why:** An item duplicated, imported (peer character, intent, Foundry review) or created on this device within the autosave window disappears for good as soon as any remote deletion arrives for the same module. Before the fix it vanished from memory but came back on the next flush or relaunch. Because `fetchId` swallows fetch errors and returns `[]`, a single failed id fetch empties the whole module in memory and drops all of its pending edits.
- **Action:** Build the "stale" set only from ids that were persisted before (exclude ids with a pending insert), make `fetchIds` throw instead of returning `[]`, and call `removePendingOperations` only for confirmed remote deletions.
- **Severity:** High
- **Status (2026-09-26):** FIXED. `CoreDataModel` tracks locally created items whose insert is queued (`markUnsavedInsert`, set from `ItemControllable.replace(isInsert:)` and `replaceForExternalImport`) until a save commits them. Both the incremental sync diff (`SyncDataControllable.updateFromSync`) and the full reconciliation (`ItemControllable.updates(_:)`) exclude those ids, so `removePendingOperations` only runs for real remote deletions. `fetchIds`/`fetchId(request:)` now throw instead of returning `[]`. Covered by `PendingOperationLedgerTests`.

### 5.3 A failed save rolls back the shared context but never re-queues the drained edits **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_17 §5.6]**
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:184-236` (rollback at `:228-233`)
- **What:** `save()` drains the queue into the context (`flushPendingOperations`), `context.save()` fails, and `context.rollback()` runs on the single context all modules share. The drained operations are not restored; `restorePendingOperations` only runs when the apply step fails, not the save.
- **Why:** One invalid object in any module rolls back every module's flushed edits. The in-memory models still show them, the next save succeeds with nothing to write, and the edits are gone after relaunch with no sign.
- **Action:** Keep the drained operations for the duration of the call, re-queue them after the rollback, and surface the error visibly.
- **Severity:** Medium
- **Status (2026-09-26):** FIXED. Flushed operations are recorded as in-flight on the context queue. The new `ContextFlushLedger` clears them on every `NSManagedObjectContextDidSave` of the shared context and, through `rollbackRestoringFlushedOperations()` (used at every rollback site: `CoreDataController.save`/`batchDelete`, `LinkRegisterController`, `TagController`), re-queues every module's in-flight edits in front of newer ones. Covered by `PendingOperationLedgerTests.rollbackOfTheSharedContextRequeuesFlushedEdits`.

### 5.4 `saveExternalImport` still saves links/tags first, so a rolled-back import reports success **[INCOMPLETE FIX of CODE_AUDIT_17 §5.5]**
- **Location:** `Modules/AdventureRPG/Root/AdventureRootModel.swift:309-320`; `Modules/CoreRPG/Links/LinkRegisterController.swift:172-205`; `Modules/CoreRPG/Controllable/TagController.swift:131-162`
- **What:** The fix reordered only `save()`. `saveExternalImport` still flushes every module and then runs `savePendingLinks`/`savePendingTags`, each of which saves and, on failure, rolls back the whole context; the final item save then has nothing to write and succeeds.
- **Why:** A link/tag failure during a Foundry/UniversalVTT import rolls back the whole flushed import while the call returns success, and the review session doesn't roll back its installed attachments.
- **Action:** Apply the `save()` ordering here too (items first), and turn a link/tag failure into a thrown error.
- **Severity:** Medium
- **Status (2026-09-26):** FIXED. `saveExternalImport` now saves items first (its failure is thrown so the review session rolls back). `savePendingLinks`/`savePendingTags` are now `throws` and restore their pending sets on failure; after the items are committed, a link/tag failure only rolls back its own derived rows and is retried by the next save, so it deliberately doesn't report the committed import as failed.

### 5.5 One far-future CRDT timestamp now freezes a field permanently **[verified]** **[REGRESSION of CODE_AUDIT_17 §5.15]**
- **Location:** `Modules/CoreRPG/CRDT/WallclockTimestamp.swift:106-125` (decode), `:45-58` (`observe`); `Modules/CoreRPG/CRDT/LWWRegister.swift:70-84`
- **What:** The decoded clock is now kept raw, and `merging(with:)` adopts `other._storage` unchanged. `observe` still caps the local hybrid clock at now + 1 day, so a register merged with a clock of year 2100 (or 1e300) is stored with that clock.
- **Why:** Every later local write is at most now + 1 day, so it loses that merge on every replica, and the field stays frozen until real time catches up. A skewed device or a crafted peer payload (players can write characters) triggers this. CODE_AUDIT_16 §5.2 had closed it.
- **Action:** Clamp the incoming clock once at merge time (observe-time now + skew) and store the clamped value, with a deterministic tie-break (actor id, then value), rather than re-clamping on decode.
- **Severity:** Medium
- **Status (2026-09-26):** FIXED. `LWWRegister` merges (`merging`, `merged`, `mergeDelta`, `mergingDelta`) go through one `mergedStorage` rule: an atom whose clock is beyond now + skew (`Metadata.isAdmissible`) loses to an admissible one on either side, so replicas converge and a far-future value stored before the fix heals on its next merge. Clamping at merge time was tried and rejected because it depends on each replica's merge time. A local write now calls `observe` on the stored clock first, so it always orders after the value it overwrites, including after a relaunch. Covered by two new tests in `UntrustedImportTests`.

### 5.6 The hex-grid cell cap silently erases the grid on large maps **[verified]** **[REGRESSION of CODE_AUDIT_17 §5.16]**
- **Location:** `Modules/MapRPG/Map/MapHexGridGeometry.swift:26,37-41`; `Modules/MapRPG/Map/MapEditController+HexGrid.swift:41-51`; `Modules/MapRPG/Map/MapEditorScaleRanges.swift:13`
- **What:** `columns * rows > 20_000` returns `[]`, and `updateHexScale` passes that to `replaceGrid`, which removes the existing cells. The slider range (20…200) exceeds the cap on common large maps: an 8192 × 8192 map at scale 20 needs about 237 × 274 ≈ 65k cells.
- **Why:** Dragging the hex slider low on a large battle map makes the grid, and its per-cell reveal state, disappear without a message (`isHexMap` flips to false). `Int(...)` of a huge finite quotient and `columns * rows` can also still overflow and trap.
- **Action:** Clamp the scale up to the smallest size that fits the cap (and reflect that in the slider) instead of returning `[]`, and use checked conversions (`Int(exactly:)`, `multipliedReportingOverflow`).
- **Severity:** Medium

### 5.7 Audio playlist: new unconditional iCloud download step (likely fails for non-iCloud files), write lock, and eager copies **[REGRESSION / INCOMPLETE FIX of CODE_AUDIT_17 §5.21, c46ecb28]**
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:133-146,156-179`; `Modules/CoreRPG/Files/FileManager+Coordination.swift:66-72`
- **What:** Every track now calls `download(coordinatingAccessAt:)`, which takes a coordinated *write* lock just to call `startDownloadingUbiquitousItem`. The previous code only did this for ubiquitous files. The comment says it "waits for" the download, but that call returns immediately (the following coordinated read does the waiting). The task group still copies every track at once.
- **Why:** If `startDownloadingUbiquitousItem` throws for non-ubiquitous URLs (local store, app-group fallback, tvOS; confirm on device), every track is silently left out of the playlist for users without iCloud Drive. The write lock contends with sync for no benefit, and large playlists double disk usage.
- **Action:** Drop the explicit download step (a coordinated read downloads on demand) or run it only when `isUbiquitousItem == true` as a read with `.withoutChanges`; fix the comment; copy only the current and next tracks, or cap the group's concurrency.
- **Severity:** Medium

### 5.8 New `RawDie.Sides.three` case changes the encoded form of every d3 **[verified]**
- **Location:** `Modules/DiceRPG/Model/RawDie.swift:95-104,139-158` (added in c2d185f2); decoded via `Modules/DiceRPG/Model/DieModel.swift:50`
- **What:** `Sides.sides(3)` now returns `.three`, which the synthesized `Codable` writes as `{"three":{}}`; a d3 used to be `.number(3)`.
- **Why:** Any device still on a build without `.three` fails to decode every dice set or character containing a d3. That covers CloudKit-synced rows and LAN/SharePlay payloads during a mixed-version rollout. Relevant only if a build without `.three` is in users' hands.
- **Action:** Keep encoding 3 as `.number(3)` (custom `Codable` or map `.three` only for display), and add a decode test for the legacy shape.
- **Severity:** Medium

### 5.9 Dice colour/art mismatches: a bag entry with no art, no validation of stored colours, and a mis-cased asset **[verified]**
- **Location:** `Modules/DiceRPG/View/DiceBag.swift:15` (`.die12(color: .D)`); `Modules/DiceRPG/Model/RawDie.swift:82-94` (`colorCodes`); `Modules/DiceRPG/Model/DieModel.swift:21-26,90-106`; `Resources/RPGResources/Resources/DiceAssets.xcassets/D20c-1.imageset` (PNG files named `D20-1@Nx.png`)
- **What:** `diceBagC` offers a d12 in colour D, but `colorCodes` for `.twelve` is `[.A, .B, .C, .G]` and no `D12D-*` imageset exists. `resolvedColor` passes any explicit stored colour through unchecked (the guard that forced unsupported colours to "G" was removed). The face-1 asset for colour-C d20 is named `D20c-1` while the code builds `D20C-1`.
- **Why:** The D12-D bag entry renders a blank die. A colour carried over after a sides change, or from import or a peer, renders blank. A natural 1 on a colour-C d20 may render blank if the lookup is case-sensitive, and the naming is inconsistent either way.
- **Action:** Build the bag rows from `colorCodes` (and remove `.die12(color: .D)`), fall back to a valid code in `resolvedColor` when the colour isn't in `die.colorCodes`, and rename the imageset (and its PNGs) to the shared scheme.
- **Severity:** Medium

### 5.10 `DiceEntityQuery.invalidateCache()` is never called, though its doc says it is **[verified]**
- **Location:** `Modules/DiceRPG/Intent/DiceEntity.swift:169-175` (cache read at `:146-149`)
- **What:** The doc comment says it is "called from ItemController whenever a dice set is added, renamed, or deleted", but nothing in Modules, Sources or Tests calls it.
- **Why:** Siri/Shortcuts/Spotlight suggestions serve stale dice for the full 60 s TTL, and the comment makes readers think this is handled. It combines with §3.2.
- **Action:** Call it from the dice add/rename/delete paths, or delete it and fix the comment.
- **Severity:** Medium
- **Status (2026-09-26):** FIXED. The never-invalidated 60 s cache (and `invalidateCache()`) was removed; `DiceEntityQuery` now uses the shared `ItemEntityQuery.suggestedEntities()`, which also applies the trashed-item filter the override skipped.

### 5.11 SharePlay seat ranks depend on when each player learns who the master is
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+TableCoordination.swift:23-70`; `Modules/GameRPG/Table3D/TableSeatAssignment.swift:27-50`; `Modules/GameRPG/Table3D/GameTableModel+Seating.swift:66-121`
- **What:** A player ranks participants without the master once the master is known, but with the master still in the list before that. The seat is recomputed only on `activeParticipants` changes, not when the master becomes known.
- **Why:** Two players can compute the same seat, one before and one after learning the master, and then share one seat and dice pool until the roster changes.
- **Action:** Re-run `assignSeatsForSharePlay` when the master becomes known, or rank only by ids every device already agrees on; add a `TableSeatAssignment` unit test for this ordering.
- **Severity:** Medium

### 5.12 Synced links get a new random UUID on each device, so link rows churn **[INCOMPLETE FIX of CODE_AUDIT_17 §5.9]**
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:324-352`; `Modules/CoreRPG/Links/LinkRegisterListModel.swift:8-38`; `Modules/CoreRPG/Links/LinkRegisterController.swift:176-194`
- **What:** `mergeUpdates` re-derives links through `LinkRegisterModel(link:source:)`, which assigns `id: UUID()`, and `savePendingLinks` diffs stored rows by that UUID.
- **Why:** Each device deletes the other device's row for the same link and inserts its own, so every synced link change becomes a CloudKit delete + insert per device, and "used by" rows flap.
- **Action:** Derive a deterministic link id (for example a hash of source, entry, destination and link number), or diff by that identity tuple.
- **Severity:** Low

### 5.13 Tag and link de-duplication keeps an arbitrary survivor
- **Location:** `Modules/CoreRPG/Controllable/TagController.swift:136-145`; `Modules/CoreRPG/Links/LinkRegisterController.swift:179-185`
- **What:** When two rows share a key, whichever comes first in the unsorted fetch is kept and the rest are deleted.
- **Why:** Two devices saving the same module at the same time can each keep a different row and delete the other, and after sync both rows are gone until that module is saved again.
- **Action:** Choose the survivor deterministically (for example the lowest object-ID URI, as `CoreDataController.fetchAndDelete` does).
- **Severity:** Low
- **Status (2026-09-26):** FIXED. Both upserts sort the fetched rows by object-ID URI before de-duplicating, so every device keeps the same survivor.

### 5.14 GM can lose its browser for good during the browser's restart pause
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:128-139,411-417`; `Modules/GameRPG/Browser/BrowserManager.swift:125-135`
- **What:** `refresh(games:)` sets `browserManager = nil` whenever `!isBrowsing`, the new supervisor deliberately passes through `.stopped` during its back-off, and `resumeAfterActivation` only restarts an existing manager.
- **Why:** If a `games` change lands during a supervised restart, the GM stops auto-redialing returning players for the rest of the session.
- **Action:** Keep `browserManager` while it is only restarting, and recreate it in `resumeAfterActivation` if it is nil.
- **Severity:** Low

### 5.15 GM hosting status reads "stopped" while the listener is starting or waiting **[REGRESSION of CODE_AUDIT_17 §5.22]**
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:97-124,295-299`; `Modules/GameRPG/Network/ListenerManager.swift:229-245`
- **What:** `resetConnections` sets `listenerStatus = .stopped`, and only `.ready` sets `.running`; `.waiting` (local-network permission prompt, no interface) is ignored.
- **Why:** While hosting is active, the UI says "stopped" instead of "starting" or "waiting for permission", and waiting never becomes `.restarting`/`.failed`.
- **Action:** Add a `.starting` status and map `.waiting(error)` to a visible degraded status.
- **Severity:** Low

### 5.16 A provisional join code can replace the displayed code after hosting has started
- **Location:** `Modules/GameRPG/Network/GameJoinCodeModel.swift:155-179,187-200`; `Modules/GameRPG/Root/GameRoot.swift:143-147`
- **What:** When the keychain read is `.unavailable` at launch, a random provisional code is used; if hosting starts with it and `applicationBecameActive` later resolves the stored code, `masterCode` changes while the running listener keeps the provisional passcode.
- **Why:** The code on screen no longer matches the listener, so every join fails as "bad code".
- **Action:** Refuse to host while the key is unresolved, or don't apply a resolved code while a listener is running on the provisional one.
- **Severity:** Low

### 5.17 On macOS, `.unavailable` from the data-protection keychain skips the legacy fallback on read
- **Location:** `Modules/GameRPG/Network/JoinCodeStorage.swift:51-68`
- **What:** `read` returns `.unavailable` immediately (for example `errSecMissingEntitlement`) instead of trying the legacy keychain, while `set` does fall back to legacy.
- **Why:** In builds without data-protection keychain access, codes are written but never read back, so they regenerate on every launch, contradicting the doc comment at `:43-47`.
- **Action:** Also read the legacy keychain when the data-protection read fails with a missing-entitlement status.
- **Severity:** Low

### 5.18 Every `.waiting(.tls)` counts as a wrong join code
- **Location:** `Modules/GameRPG/Network/ConnectionController.swift:215-224`
- **What:** Any TLS waiting reason ends the connection with `isAuthenticationFailure: true`, while the `.failed` path uses `isAuthenticationFailure(_:)` to tell them apart.
- **Why:** Transient handshake errors on flaky Wi-Fi count toward the 3-strike lockout, so a legitimate reconnecting player can lock themselves out.
- **Action:** Route the TLS status through the same classifier (bad MAC / unknown PSK identity only).
- **Severity:** Low

### 5.19 3D hex toggle has no GM guard and sends no structural update **[INCOMPLETE FIX of CODE_AUDIT_17 §5.24]**
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+ToolBar.swift:66-76`
- **What:** `toggleHexMap` edits the map without the `isGameMaster` guard its sibling actions have, and only sends `mapState` (via `syncAfterExternalEdit`), not the new hex entries.
- **Why:** Players receive a state that references entries they don't have, and each must run a repair round trip, which §6.1's throttle can now drop.
- **Action:** Add `guard isGameMaster` and broadcast the structural (`.generic`) update through a `broadcastMapEdit` variant, per the CLAUDE.md Table3D rules.
- **Severity:** Low

### 5.20 In `AdventureGeneratorController`, a superseded extraction clears the newer one's busy flag **[INCOMPLETE FIX of CODE_AUDIT_17 §3.5]**
- **Location:** `Modules/GeneratorRPG/Controller/AdventureGeneratorController.swift:235-253`
- **What:** The old task's `defer { model.isExtracting = false }` runs after the replacement task has started; `GeneratorController` got a generation guard for this, this controller did not.
- **Why:** The UI shows idle while the newer extraction is still streaming.
- **Action:** Mirror `GeneratorController`: clear `isExtracting` only if the finishing task is still the current one.
- **Severity:** Low

### 5.21 Roll-result haptic uses a `Bool` trigger, so repeated identical outcomes are silent
- **Location:** `Modules/DiceRPG/Game/Detail/DiceGameActionBar.swift:50-55`
- **What:** `.sensoryFeedback(diceRollResult ? .success : .error, trigger: diceRollResult)` fires only when the Bool changes.
- **Why:** Two successes (or two failures) in a row produce no haptic on the second roll, so the feedback looks random to the player.
- **Action:** Trigger on a roll counter or the dice value (which already drives the `onChange`) and pick success/error from the result.
- **Severity:** Low

---

## 6. Security

Entitlements were checked for all targets: Debug/Release pairs are consistent, the App Group and iCloud container match CLAUDE.md, and the macOS targets get sandbox and network entitlements through `ENABLE_APP_SANDBOX`/`ENABLE_*_NETWORK_CONNECTIONS` build settings. No hard-coded secrets found.

### 6.1 Map-recovery throttle is bypassable, and it silently drops legitimate repairs **[verified]** **[REGRESSION of CODE_AUDIT_17 §6.7]**
- **Location:** `Modules/GameRPG/Controller/MasterController+MapMessages.swift:217-243` (callers `:69-71`, `:131-137`)
- **What:** The throttle key is (player, map); the timestamp is stored *before* the export runs; and a throttled request returns `nil` with no `.failed` reply (CODE_AUDIT_Network §5.11 requires one).
- **Why:** A malicious player cycles through map ids (any library id is accepted, see CODE_AUDIT_17 §6.3) and still gets unlimited full exports. An honest player whose repair lands inside the 10 s window gets no answer, even when the earlier export failed.
- **Action:** Add a per-player budget across all maps, record the timestamp only after a successful export, and reply `.failed` (or a retry-after) when throttling.
- **Severity:** Medium

### 6.2 The LAN relay now forwards raw player frames, including junk padding **[REGRESSION of CODE_AUDIT_17 §7.2]**
- **Location:** `Modules/GameRPG/Network/GameNetworkController+MasterDelegate.swift:42-51`; `Modules/GameRPG/Model/GameMessagePipeline.swift:305-312`
- **What:** `PreEncodedMessage` re-sends the peer's original bytes to every other player; the old decode/re-encode dropped unknown keys.
- **Why:** A player can pad a tiny group event (dice, pin) with up to about 100 MB of ignored JSON, and the GM amplifies it to N−1 players; `GameRelayAdmission` has no byte budget. The LAN and SharePlay copies of the same message also now differ.
- **Action:** Forward raw bytes only when the frame is close to the decoded payload size (or re-encode small control messages), and add a per-sender byte budget to relay admission.
- **Severity:** Medium

### 6.3 The player-name clamp covers only the roster **[INCOMPLETE FIX of CODE_AUDIT_17 §6.9]**
- **Location:** `Modules/GameRPG/Root/GameRootModel.swift:74-90`; `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:254`; `Modules/GameRPG/Statistics/Controller/GameStatisticsController.swift:32,60-65`; `Modules/GameRPG/Model/GameMessagePipeline.swift:104-106,162-168`
- **What:** `SharingControlModel(name:)`, statistics `actorName` and participant names still use the unclamped `sender.name`, and the pipeline's queued-byte budget counts only `data.data`.
- **Why:** An authenticated peer's huge name is still stored in every statistics event (up to 100 buffered) and in sharing controls, and it bypasses the 300 MB queue budget.
- **Action:** Clamp `sender.name` once at decode/admission, and count name bytes in the queue budget.
- **Severity:** Medium

### 6.4 Share-extension image fallback can read up to 256 MB into memory
- **Location:** `Sources/RPGShare/ItemProviderImporter.swift:133-147`
- **What:** For a file between 8 MB and 256 MB, if `CGImageSourceCreateWithURL` or the downsample returns nil, the code falls back to `Data(contentsOf:)` of the whole file.
- **Why:** Share extensions have a memory limit of roughly 120 MB, so an undecodable large file gets the extension killed. Remote URLs are still downloaded in full with no host check *(still open from CODE_AUDIT_17 §6.12)*.
- **Action:** Throw instead of falling back above the raw-image cap, and use a capped, delegate-based download.
- **Severity:** Low

### 6.5 Remote file download validation gaps *(still open from CODE_AUDIT_17 §6.10)*, plus a new false positive
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:609-695`; `Modules/CoreRPG/Files/FileUrl.swift:228-234`
- **What:** Redirect re-validation, a check on what a hostname resolves to, and a size cap during download are still missing. The new "hex-only host" check also rejects real hostnames made only of hex letters (for example `cafe.be`).
- **Why:** A public URL can still redirect to a private host or stream an unbounded body, and some legitimate hosts are now refused.
- **Action:** Validate each redirect in a `URLSessionTaskDelegate`, cap the bytes received, and restrict the hex-host rule to labels that actually parse as numeric IPv4.
- **Severity:** Low

---

## 7. Performance

### 7.1 `createGameData` exports run on the main actor at about 15 call sites
- **Location:** `Modules/CoreRPG/Controllable/GameControllable.swift:167,255-277`; `ExportControllable.swift:327-360`; callers `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:32,48,139`, `+SpaceMessages.swift:37,77,85,138,191`, `+PdfMessages.swift:37,75`, `+DiceMessages.swift:27,32` (compare `detachedGameData` at `MasterController+Messaging.swift:146-162`)
- **What:** The requirement is nonisolated, so it inherits the caller's executor. Only the reveal dispatcher detaches it; the audio, PDF and space paths stream multi-MB file bytes on the main actor.
- **Why:** Main-thread hitches proportional to file size during reveals and repairs, and two inconsistent patterns for the same call.
- **Action:** Mark `createGameData`/`createMapGameData`/`createWeatherGameData` `@concurrent` and delete `detachedGameData`.
- **Severity:** Low

### 7.2 `AVAudioSession.setCategory` runs synchronously on the main actor
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerSession.swift:45-51,57-78`
- **What:** `setActive` moved to `@concurrent`, but `setCategory(.playback, policy: .longFormAudio)` still runs in the `@MainActor` `initSession()`.
- **Why:** `setCategory` is the SessionCore call the SharePlay code documents as blocking the main thread during an active call.
- **Action:** Move `setCategory` into the same `@concurrent` step, before `setActive`.
- **Severity:** Low

### 7.3 Blocking `NSFileCoordinator` calls occupy cooperative-pool threads
- **Location:** `Modules/CoreRPG/Files/FileManager+Coordination.swift:90-113,121-195,211-250`
- **What:** Every coordinated access runs a synchronous `coordinate(…)` inside `Task.detached`, up to 4 at a time.
- **Why:** Up to 4 cooperative threads (most of the pool on a 6-core device) can sit blocked waiting on iCloud downloads.
- **Action:** Use `NSFileCoordinator.coordinate(with:queue:byAccessor:)` bridged by a continuation, so the wait happens on an `OperationQueue`.
- **Severity:** Low

### 7.4 Bookmark JSON load/save on the caller's actor, and an unused `priority` parameter
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:55-59`; `Modules/CoreRPG/Persistence/FilePersistenceController.swift:16-29,34-60`; `Modules/CoreRPG/Files/FileDataController.swift:46-72`
- **What:** `FilePersistenceController.load()` is nonisolated, so `Data(contentsOf:)`, directory creation and decode run on main during launch (once per file module); the `priority` passed through both types is never used.
- **Why:** Small synchronous I/O at launch, plus dead configuration left from the previous `Task.detached(priority:)` design.
- **Action:** Make load/save `@concurrent` and remove the `priority` parameters.
- **Severity:** Low

### 7.5 Image resize renders at a fixed 3× on top of the screen scale
- **Location:** `Modules/CoreRPG/Extensions/Image+AKImage.swift:108-140`
- **What:** `resize` multiplies `targetSize` by `pixelScale = 3` and then uses `UIGraphicsImageRenderer(size:)` with the default format, which applies the screen scale again.
- **Why:** Thumbnails come out at up to 9× the needed pixel area on iPhone, wasting memory and decode time.
- **Action:** Use an ImageIO thumbnail (as `boundedDecode` already does) or `byPreparingThumbnail(ofSize:)`, or set `format.scale = 1`.
- **Severity:** Low

### 7.6 Items still open by decision
- **Location:** CODE_AUDIT_17 §7.2 (targeted player-list broadcasts) and §7.5 (hex cells as entries)
- **What:** Both remain as documented in CODE_AUDIT_17; §7.5 is also why the cell cap in §5.6 exists.
- **Why:** Listed so they aren't forgotten; they need the protocol/design decisions recorded there.
- **Action:** None beyond the recorded decisions.
- **Severity:** Low

---

## 8. SwiftUI / UI

The rule scan against CLAUDE.md was clean: no `foregroundColor`, `cornerRadius()` view modifier (the one hit is the Charts `BarMark` API), `tabItem`, `ObservableObject`/`@Published`/`@StateObject`, `NavigationView`, `GeometryReader` (only `GeometryReader3D` on visionOS), `ScrollViewReader`, `showsIndicators:`, `DispatchQueue.main`, legacy `Formatter`s, `String(format:)`, `replacingOccurrences`, fixed `.font(.system(size:))`, `fontWeight(.bold)`, single-parameter `onChange`, or `Task.sleep(nanoseconds:)`. The single `onTapGesture` uses `count: 2`, which the rules allow. `AnyView` (109 hits) is confined to the per-module `ViewController` type-erasure layer and the vendored Navigator.

### 8.1 The shared game-overlay button styles dropped the 44 pt minimum hit target **[verified]** **[REGRESSION, 396b6052]**
- **Location:** `Modules/CoreRPG/Buttons/OverlayButtonStyle.swift:116-150`; `Modules/DiceRPG/Game/Detail/DiceGameActionBar.swift:26-76`; `Modules/DiceRPG/Game/Detail/DicePlayer.swift:55-57`; also used in `Modules/MapRPG/Map/GameToolBar.swift` and `HexMapScaleView.swift`
- **What:** `.frame(minWidth: 44, minHeight: 44)` was replaced by `.imageScale(.large).padding(8)` in both `GameOverlayControlButtonStyle` and `GameOverlayCapsuleButtonStyle`, and the Edit/Roll buttons lost their own 44 pt frames while the sibling buttons in the same bar kept theirs.
- **Why:** A large-scale body-size symbol plus 16 pt of padding comes out below the 44 × 44 pt HIG minimum, which affects game-time controls on iPhone. The same action bar now also mixes two button sizes.
- **Action:** Put `minWidth/minHeight: 44` back into both styles (keeping the new padding) and remove the per-button frames so all overlay buttons size alike.
- **Severity:** Medium (agent C rated Low; raised because it is an HIG/accessibility regression across every overlay control)
- **Status (2026-09-26):** FIXED. The compact visual size (`.imageScale(.large).padding(8)`) is kept; both styles now hit-test through a private `MinimumHitAreaShape` content shape that is centred on the control and at least 44×44 pt, so the tappable area grows without changing layout. The per-button label frames in `DiceGameActionBar` were removed in 9156df35, so every overlay button in the bar renders at the same size.

### 8.2 `SharePlayButton` owns a `GroupStateObserver` through `@ObservedObject`
- **Location:** `Modules/GameRPG/SetupViews/SharePlayButton.swift:21-22` (a second observer at `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:713,776-783`)
- **What:** `@ObservedObject private var groupStateObserver = GroupStateObserver()` creates a fresh observer every time the parent re-evaluates the view.
- **Why:** Each re-init starts a new system observer whose eligibility can briefly read `false`, so the button falls back to the share sheet. `@ObservedObject` must not own its object; CODE_AUDIT_17's note that it "can stay" missed this.
- **Action:** Use `@StateObject` (there is still no `@Observable` alternative for `GroupStateObserver`), or read the controller's existing `canActivateSharePlay` from the environment.
- **Severity:** Medium

### 8.3 Fixed frames clip text at large Dynamic Type sizes
- **Location:** `Modules/GameRPG/BattleRound/BattleRollResults.swift:28` (`.frame(width: 76, height: 25)` around `.caption2` text); icon-only toolbar buttons with fixed `height: 24` at `Modules/MapRPG/Map/GameToolBar.swift:59,78,165,188`, `Modules/GameRPG/GameViews/GameMainTabToggleButtonView.swift:22`, `Modules/CoreRPG/List/ShareListItemModifier.swift:60`
- **What:** 234 numeric `.frame` sizes exist; most are decorative, but these wrap text or symbols that should grow with Dynamic Type.
- **Why:** At accessibility text sizes the battle roll totals are clipped vertically, and toolbar symbols stay at the base size.
- **Action:** Use `@ScaledMetric` for these dimensions, or `minHeight` instead of a fixed height.
- **Severity:** Low

### 8.4 `ForEach(id: \.self)` over content that can contain duplicates
- **Location:** `Modules/GeneratorRPG/Root/CharacterGenView.swift:25` (AI-generated entries); tag lists at `Modules/CoreRPG/ItemViews/TagItemRow.swift:19`, `Modules/CoreRPG/Editors/RemoveTagsEditor.swift:26`, `Modules/PdfRPG/View/SummaryPdfUpdateView.swift:58`, `Modules/GeneratorRPG/View/TextSummaryUpdateView.swift:44`
- **What:** Identity is the element's own value; generated entries and unnormalized tag arrays can contain equal values.
- **Why:** Duplicate ids give undefined `ForEach` diffing (rows swap or vanish, with a runtime warning).
- **Action:** De-duplicate tags at the model layer, and key generated entries by index-plus-content or a wrapper id assigned after generation.
- **Severity:** Low

### 8.5 `@State` seeded from init parameters in views that can receive new inputs
- **Location:** `Modules/TableRPG/View/TableGenerationRootView.swift:16` (`controller.makeModel(itemId:)` on every init); `Modules/CoreRPG/LGViews/ItemHeaderEditorView.swift:21-24`; `Modules/RuleRPG/View/RuleQuickEntryEditor.swift:17`; `Modules/CoreRPG/Sheet/SheetEntryConvertToGroupView.swift:36`
- **What:** `State(initialValue:)` captures the first value only; `makeModel` also runs (and is thrown away) on every parent re-render.
- **Why:** If the parent reuses the view identity with a different `itemId`/model, the view keeps showing the old state; the wasted model construction costs work on each parent update.
- **Action:** Add `.id(itemId)` at the call sites (or build the model in `.task(id:)`), and document the editors as "snapshot on open" where that is intended.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

No `#if false` blocks, no ungated `print`/`debugPrint`/`dump`/`NSLog`, and no FIXME/HACK/XXX/`#warning` markers were found. None of CODE_AUDIT_17's §9 items has been addressed yet; they are consolidated here.

### 9.1 Files to delete outright *(still open from CODE_AUDIT_17 §9.1/§9.2/§9.6)*
- `Sources/DiceRollerWidget/DiceRollerView.swift` (424 LOC) and `DiceRollerWidgetConfiguration.swift` (193 LOC): excluded from every target via `membershipExceptions`, so they never compile.
- Ghost entries `DiceRollerWidgetDiceRollerExamples.swift`, `FavoriteDiceManagementView.swift` in `MasterRPG.xcodeproj/project.pbxproj:1888-1894`: the files don't exist.
- `Modules/CoreRPG/App/ExportedRPGData.swift:71-144` (keep the `UTType` constants at `:94-99` in a file named for them); the two identical `StoreManipulable` protocols (`Modules/CoreRPG/FileViews/SettingsView.swift:1-10`, `Modules/RolePlayGameKit/View/SettingsView.swift:20-24`); `AppRouter` (`Modules/CoreRPG/App/AppTabBarViewModifier.swift:5`); test-only `Modules/CoreRPG/Cache/ResourceCache.swift`; empty `registerRealityKitComponents()` (`Sources/MasterRPG/RealityKitInit.swift:11-16`, call at `MasterRPGApp.swift:36`); `Scripts/print_wan_ip.sh`; unused `PhotographyTips`/`Reticle` imagesets in `Modules/SpaceRPG/Resources/Assets.xcassets`.
- **Severity:** Medium (~900 LOC and several misleading project entries removed)

### 9.2 Project references a deleted `MasterRPG.entitlements`
- **Location:** `MasterRPG.xcodeproj/project.pbxproj:1868` (file reference), `:2752` (Resources group)
- **What:** No such file exists; every target uses the `-Debug`/`-Release` variants.
- **Why:** It shows as a red missing file and misleads anyone looking for the app's entitlements.
- **Action:** Remove the reference and group entry.
- **Severity:** Low

### 9.3 About 95 members with exactly one repo-wide occurrence *(still open from CODE_AUDIT_17 §9.3, with new entries)*
- **Location:** New since audit 17: `Modules/GameRPG/GameViews/GameScreenModel.swift:64` (`resetToMainTab`), `:85-86`; `Modules/GameRPG/Table3D/GameTableModel+MapSync.swift:18` (`refreshCurrentMap`, next to the sanctioned `refreshFogOfWar`); `Modules/MapRPG/BattleRound/BattleRoundModel+Roster.swift:56`; `Modules/DiceRPG/Model/DiceModel.swift:334,339`; `Modules/PdfRPG/Model/PdfModel.swift:103`; `Modules/SpaceRPG/Model/SpaceModel.swift:107`; `Modules/GeneratorRPG/BasicAI/Engine/FoundationManager.swift:49`; `Modules/GeneratorRPG/BasicAI/Model/Transcript+TextExtraction.swift:6`. Still open: `Modules/CoreRPG/App/PlatformModifiers.swift:15,23,80,89,98`, `Modules/CoreRPG/ViewModifiers/FocusModifiers.swift:10,14`, `Modules/CoreRPG/Extensions/PlatformHelpers.swift:23,41,50`, `Modules/CoreRPG/Files/FileUrlViewModel.swift:31-46`, `Modules/CoreRPG/Model/ItemListable.swift:43-51`, `Modules/CoreRPG/Links/ReferenceScanner.swift:26`, `Modules/RuleRPG/Resources/Localization+Extensions.swift` (whole file)
- **What:** 135 names have a single occurrence; excluding ~40 delegate/protocol witnesses leaves ~95 that are really unused.
- **Why:** The public API is bigger than it needs to be, and some dead entry points sit next to the ones CLAUDE.md says to use.
- **Action:** Delete them in one pass and let the compiler catch any misses (keep `participantJoined` and `migrationKey`, as audit 17 advised).
- **Severity:** Low

### 9.4 Legacy live-model `CoreDataController` overloads have no callers *(still open from CODE_AUDIT_17 §9.3/§9.4)*
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:108,130,137,152,350`
- **What:** `fetch(mapper:)`, `fetch(uuid:mapper:)`, `replace(uuid:with:updater:)`, `queueReplace(uuid:with:updater:)` and `batchReplace(models:keyPath:updater:)` have no callers; only the snapshot twins are used.
- **Why:** A future caller could send main-actor models into `@Sendable` queue closures.
- **Action:** Delete them and point their docs at the snapshot APIs.
- **Severity:** Low

### 9.5 Preview scaffolding and a SwiftData model ship in release *(still open from CODE_AUDIT_17 §9.4)*
- **Location:** `Modules/CoreRPG/Model/LinkDataModel.swift:1-11`; 13 × `Modules/*/Model/MockData.swift`; 17 of 20 files in `Modules/CoreRPG/Fake/`; `Modules/GameRPG/Statistics/Model/GameStatisticsTypes.swift:439-620` (fixtures)
- **What:** None of these is under `#if DEBUG`; `LinkDataModel` is only used as `LinkDataModel.ID` and as a preview schema.
- **Why:** About 1,200 LOC of preview/test scaffolding and an `import SwiftData` stack are linked into release frameworks.
- **Action:** Replace `LinkDataModel.ID` with `UUID`, delete the model, and move MockData/Fake/fixtures under `#if DEBUG`.
- **Severity:** Medium

### 9.6 Commented-out statements and remaining TODOs *(still open from CODE_AUDIT_17 §9.5)*
- **Location:** `Modules/CoreRPG/Sheet/SheetRootModel+Editor.swift:50,61`; `Modules/CoreRPG/Editors/TextDoubleEditor.swift:42`; `Modules/CoreRPG/LGViews/HeaderFooterContentScrollView.swift:34,163,184`; `Modules/CoreRPG/ItemDetail/ItemEditorForegroundView.swift:83`; `Modules/CoreRPG/LGViewModifiers/ToolbarItemListViewModifier.swift:207`; `Modules/CoreRPG/Debug/RainbowDebug.swift:23`; `Modules/PhotoRPG/Model/DataModel+Extensions.swift:26`; `Modules/MapRPG/Map/EditMapToolBar.swift:139`; `Modules/GeneratorRPG/Controller/GeneratorController.swift:328`; `Modules/GeneratorRPG/Controller/AdventureGeneratorController.swift:228`; new: `Modules/CoreRPG/Extensions/Image+AKImage.swift:16`, `Modules/CoreRPG/App/UserActivity.swift:64`, `Modules/CoreRPG/LinkRenderer/LinkHighlightTextRenderer.swift:89`. TODOs: `Modules/CharacterRPG/View/DetailEditorView.swift:14`, `Modules/CharacterRPG/Controller/EditController+Repair.swift:178`
- **What:** Twenty obsolete single-line disabled statements, plus two TODOs about known behaviour doubts.
- **Why:** Noise, and some suggest behaviour that isn't wired up.
- **Action:** Delete the statements; resolve the TODOs or move them to the issue tracker.
- **Severity:** Low

### 9.7 Per-module list-sequence trackers copied 8 times across Master and Player *(still open from CODE_AUDIT_17 §9.10)*
- **Location:** `Modules/GameRPG/Controller/PlayerControllerModel.swift:235-420`; `Modules/GameRPG/Controller/MasterController.swift:509-567`
- **What:** `canApplyXList`, `recordXList`, `hasAuthoritativeXList` and `resetXListSequence` are the same code under eight names, and the three deferred-reveal families are identical too.
- **Why:** A sequencing fix in this historically lost-message-prone area must be repeated 8 times by hand.
- **Action:** One generic `ListSequenceTracker` keyed by `NetworkModules` and one `DeferredRevealQueue`, used by both models.
- **Severity:** Medium

### 9.8 Twelve hand-rolled bounded LRU dictionaries
- **Location:** `Modules/GameRPG/Controller/PlayerControllerModel.swift:277,334,391,454,511`; `Modules/GameRPG/Controller/MasterController.swift:370,422,450`; `Modules/GameRPG/Root/GameRootModel.swift:332`; `Modules/GameRPG/Network/SharePlayPlayerJournalAdmission.swift:244,365`; `Modules/GeneratorRPG/Root/GeneratorRootModel.swift:157`
- **What:** Each copy is a dictionary plus an order array with O(n) `removeAll { $0 == key }` and `removeFirst()` eviction; a bounded helper exists only for sets (`PhysicalIdentityDenylist`).
- **Why:** Twelve copies of one eviction rule, each able to let the map and order array drift apart.
- **Action:** Add a generic `BoundedOrderedDictionary<Key, Value>` to CoreRPG and replace them.
- **Severity:** Medium

### 9.9 Folder-entry union merge copied into 9 item models; only one copy is deterministic
- **Location:** `Modules/AudioRPG/Model/AudioModel.swift:130-135`; `Modules/WeatherRPG/Model/WeatherModel+Sync.swift:13`; `Modules/CharacterRPG/Model/ValueModel.swift:136`; `Modules/PhotoRPG/Model/PhotoModel.swift:122`; `Modules/RuleRPG/Model/RuleModel.swift:183`; `Modules/GeneratorRPG/Model/GeneratorModel.swift:124`; `Modules/MapRPG/Model/MapModel+Sync.swift:104`; `Modules/SpaceRPG/Model/SpaceModel.swift:129`; `Modules/TableRPG/Model/TableModel+Persistence.swift:16`
- **What:** The same block (union ids from a `Set`, O(n²) lookups, sort by name) appears 9 times, and only Photo's copy fixed the non-deterministic order from the `Set`.
- **Why:** Two devices can order equally-named entries differently in the 8 unfixed copies (cross-device determinism, see the memory note on version determinism), and CRDT merge fixes must be applied 9 times.
- **Action:** One `mergedFolderEntries(_:_:)` helper in CoreRPG with a deterministic tie-break (name, then id).
- **Severity:** Medium

### 9.10 Security-scoped access and detached-reader wrappers repeated *(extends CODE_AUDIT_17 §9.12)*
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:28-47,91,195`; `FoundrySystemPackageReader.swift:21-37,73`; `UniversalVTTReader.swift:164-180,186-201`; manual `startAccessingSecurityScopedResource` also at `Modules/CoreRPG/Import/ExternalImportSourceRegistry.swift:601`, `Modules/CoreRPG/Files/FileUrlDataController.swift:151`, `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:106`, `Modules/SpaceRPG/Space/SpaceViewer.swift:501`, `Modules/RolePlayGameKit/Model/AppModel.swift:463`
- **What:** An ~18-line "detached + security scope + cancellation handler" wrapper appears 7 times, and 12 sites bypass the existing `SecurityScopedAccess` helper.
- **Why:** Unbalanced start/stop scope calls are a known bug class here, and each copy must get cancellation right on its own.
- **Action:** Add `SecurityScopedAccess` as an `@concurrent` helper and move all 12 sites onto it (combine with §4.4).
- **Severity:** Low

### 9.11 Master and Player Photo/PDF/Space message handlers are near-copies *(still open from CODE_AUDIT_17 §9.10)*
- **Location:** `Modules/GameRPG/Controller/MasterController+PhotoMessages.swift`, `+PdfMessages.swift` (169 LOC each, 36 lines differ), `+SpaceMessages.swift`; `Modules/GameRPG/Controller/PlayerController+Photo.swift`, `+Pdf.swift`, `+Space.swift`
- **What:** The file-module handlers are near-duplicates on both sides.
- **Why:** Authorization fixes (CODE_AUDIT_17 §6.3) and future fixes must be applied 3-4 times.
- **Action:** One generic file-module handler per side, parameterised by module and store.
- **Severity:** Medium

### 9.12 ImageIO downsampling/header checks written three times
- **Location:** `Modules/CoreRPG/Extensions/Image+AKImage.swift:166-244`; `Sources/RPGShare/ItemProviderImporter.swift:125-185`; `Modules/RolePlayGameKit/Import/Foundry/FoundryMediaNormalizer.swift:159-195`
- **What:** Three `CGImageSource` pipelines, each with its own options and caps (8192 px, 4096 px, 20,000 px / 400 MP).
- **Why:** Decompression-bomb guards drift (only the Foundry copy checks header dimensions before decoding).
- **Action:** One CoreRPG `ImageDecoding` helper (bounded decode, downsample-to-JPEG, header check) used by all three.
- **Severity:** Low

### 9.13 Per-module boilerplate families still move in lockstep *(still open from CODE_AUDIT_17 §9.7-§9.9)*
- **Location:** `Modules/*/Resources/BundleModule.swift` (14 copies); `Controller/SyncDataController.swift` (12); `Root/LinkRootView.swift` (12); `Root/DetailRootView.swift` (12); `Route/DetailRoute.swift` (9); `Controller/FolderListController.swift`, `DataController.swift`, `ExportController.swift`, `LinkController.swift` (12 each); `Resources/Localization+Extensions.swift` (10); `Intent/*ManagementIntents.swift` (11 files, 2,014 LOC)
- **What:** File counts match audit 17; no generic CoreRPG replacement exists yet.
- **Why:** Every routing, bundle, intent or Spotlight change touches 9-14 files.
- **Action:** Follow audit 17's order: bundle/localization helpers first, then generic `DetailRoute`, `FolderListController`, `SyncDataController` and intent bodies.
- **Severity:** Medium

### 9.14 Smaller duplicates *(partly still open from CODE_AUDIT_17 §9.11/§9.12)*
- **Location:** Five PDF-export `Transferable` blocks (`Modules/AdventureRPG/Intent/AdventureEntity.swift:58-110`, `Modules/CharacterRPG/Intent/CharacterEntity.swift:60-95`, `Modules/MapRPG/Intent/MapEntity.swift:60-90`, `Modules/TableRPG/Intent/TableEntity.swift:60-90`, `Modules/WeatherRPG/Intent/WeatherEntity.swift:62-100`); three sides→`DieModel` switches (`Modules/DiceRPG/Widget/DiceConfiguration.swift:72-89`, `Sources/DiceRollerWidget/DiceRollerIntents.swift:89-98`, dead `DiceRollerView.swift:301`) and the redundant `DieModel.name(for:)` switch (`DieModel.swift:94-104`); inline `JSONEncoder()`/`JSONDecoder()` at 28 sites including the wire default `Modules/CoreRPG/Model/MessageMapper.swift:21,26` while `JSONCoding` exists; four extract toolbar buttons, six preview UUID helpers, two identical SharePlay button views (`Modules/GameRPG/SetupViews/SelectedAdventureView.swift:186`, `SelectedPlayerView.swift:138`)
- **What:** Small verbatim copies.
- **Why:** They drift apart independently (the D12-D gap in §5.9 came from the hand-kept dice lists).
- **Action:** One `renderSummaryPdf(title:description:)`, a `DieModel(sides:color:)` factory with a single-interpolation `name(for:)`, `MessageMapper` defaulting to `JSONCoding`, and shared toolbar/preview/SharePlay components.
- **Severity:** Low

### 9.15 Oversized files (>500 LOC)
- **`Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift` (1,313)** — split into reader (1-277), decoder (278-657), document decoder (658-1017), extraction (1018-1238), caches (1239-1313). Severity: Medium.
- **`Modules/SpaceRPG/Space/SpaceViewer.swift` (1,119)** — `loadEntity` alone is ~277 lines (479-756); move loading to a controller/model in `SpaceViewer+Loading.swift`, and extract `+SharedSync` (195-365), `+Handoff` (366-467) and subviews (820-1119). Severity: Medium.
- **`Modules/GameRPG/Controller/PlayerControllerModel.swift` (1,065) / `MasterController.swift` (650)** — `MasterController.swift` actually holds the 570-line `MasterControllerModel`; rename, then extract the generic trackers of §9.7/§9.8. Severity: Medium.
- **`Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift` (939)** — `sendData` is 288 lines; split into `+JournalAdmission` (312-641), `+SendQueue` (648-760), `+Chunking` (763-900). Severity: Medium.
- **`Modules/GameRPG/SharePlay/RPGSharePlayController.swift` (929)** — 600 lines of support types; move 48-329 to `SharePlaySessionLifecycle.swift` and 336-646 to `SharePlayTrackers.swift`. Severity: Low.
- **`Modules/CoreRPG/Controllable/ImportControllable.swift` (866) / `EditControllable.swift` (827)** — extract import models, review diff, files, `InputStream` reading; edit menu/folder/files. Severity: Low.
- **`Modules/CoreRPG/Foundry/FoundryRuleModels.swift` (829) / `FoundrySystemPackageReader.swift` (738)** — extract `FoundryJSONValue`, import limits, system decoders, utilities. Severity: Low.
- **`FoundryImportView.swift` (711), `DiceModel.swift` (703), `AppModel.swift` (679), `GameRoot.swift` (654)** — split along existing MARK/extension boundaries (`+Sync`/`+DataAccess`/`+Codable`; `+Maintenance`/`+Routing`; `+Selection`/`+Master`/`+Player`/`+Demo`). Severity: Low.

### 9.16 Naming: Id/Url convention and misspelled symbols *(partly still open from CODE_AUDIT_17 §9.14/§9.15)*
- **Location:** Id/Url drift: `senderId` 74 vs `senderID` 32 (both in `Modules/GameRPG/Controller/PlayerControllerModel.swift:18,66`), `parentId` 682 vs `parentID` 77, `fileUrl` 475 vs `fileURL` 19, `sourceUrl` 9 vs `sourceURL` 64; heaviest in `Modules/CoreRPG/Import/ExternalImportSourceRegistry.swift`, `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift`, `Modules/GameRPG/Network/SharePlayPlayerJournalAdmission.swift`, `Modules/CoreRPG/Foundry/FoundryVTTImportModels.swift:64-141`. Misspelled core types: `ItemDataAccessable` (`Modules/CoreRPG/ItemList/ItemDataAccessable.swift:59`, 273 hits), `EntryDataAccessable`, `Storeable` (`Modules/CoreRPG/Files/FileDataController.swift:6`), `ItemLinkRegistable`, `ItemReferencable`, `effectedLink`/`EffectedItemModel` (`Modules/CoreRPG/Model/RemoveEntryListModel.swift:13,29`). Typos still open: `sugguestionTags`, `historyTransactionConvertionFailed`, `preparaEngine`, `isProminet`, `AddtionalEntryRow`, `initalPackage`, `firstRerole`, `deactive`, `haslink`, `titlename`, `ccolor`, `throttleInMilliSeconds`, `"ScaeExample"` (`Resources/RPGResourcesDebug/Resources.swift:35`). Misleading files: `Modules/GameRPG/Table3D/GamePortableSetup.swift`/`GamePortableRenderer.swift` declare classes with the same names as `GameSetup.swift`/`GameRenderer.swift` under `#if`; views in `Persistence/` and `Model/` (`CloudKitSyncStatusView.swift`, `OpenFileWindowModel.swift:75`).
- **What:** The CLAUDE.md Id/Url convention is broken ~2,250 times, sometimes mixed for one concept; misspelled names sit at the core of the model layer.
- **Why:** Search becomes unreliable. Foundry models are `Codable`, so renames need `CodingKeys`, and the duplicate class names across platforms make cross-platform changes error-prone.
- **Action:** Rename module by module (Foundry import and SharePlay first, with explicit `CodingKeys` where the name is a persisted key); do the misspellings in one mechanical commit; give the portable Table3D types distinct names.
- **Severity:** Low

### 9.17 Magic constants
- Network back-off `[1, 2, 4, 8, 15, 30] s` written three times with diverged attempt caps (`Modules/GameRPG/Browser/BrowserManager.swift:44`, `Modules/GameRPG/Master/MasterNetworkController.swift:328-330,365`, `Modules/GameRPG/Player/PlayerNetworkController.swift:88-89,504`); the 15 s handshake deadline twice → move to `GameLimits`.
- Byte limits in mixed units: `536_870_912` (`Modules/CoreRPG/Foundry/FoundryImportArchive.swift:120`, `FoundryRuleModels.swift:738-739`); "256 MB" as `256_000_000` (`Modules/CoreRPG/Cache/ObjectCache.swift:20`, `FileUrlDataController.swift:607`) vs `256 * 1_024 * 1_024` (`Sources/RPGShare/ItemProviderImporter.swift:200`); token default 4096 at `Modules/GeneratorRPG/BasicAI/Engine/TranscriptTokenCounting.swift:98` duplicating `AppConfiguration.TokenManagement.defaultMaxTokens`.
- `de.andretrettin.` prefixes in four spellings in ~40 places (e.g. `Modules/CoreRPG/App/AppGroup.swift:6,40`, `Modules/GameRPG/GameCenter/GameCenterController.swift:125-138`, `Modules/GameRPG/Network/JoinCodeStorage.swift:49`); `@SceneStorage("RootRoute")` with three different defaults (`Modules/RolePlayGameKit/View/TabbedNavigation.swift:124`, `TabSidebar.swift:92`, `SplitNavigation.swift:69`); `delayedTask(.milliseconds(100))` at 8 sites.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Add visionOS (and ideally macOS/tvOS) to the pre-commit build.** The only build-breaking defect (§5.1) was committed hours before this audit and would have been caught by a single `xcodebuild -destination 'generic/platform=visionOS Simulator'`. Glass effects, TabletopKit and `GeometryReader3D` are all platform-gated, so every UI change needs the other platforms compiled. A small script in `Scripts/` running the four destinations would cover this.
2. **Treat the pending-operations queue as the source of truth for unsaved work.** §5.2, §5.3, §5.4 and §3.10 all come from the same gap: code that drains, drops or rolls back the queue without knowing which operations are unsaved inserts and without restoring them on failure. One small `PendingWrite` state machine (queued → flushed → saved, re-queued on rollback, never dropped by in-memory reconciliation) in `CoreDataController` would close all four. Use snapshot-level tests that simulate a failing `context.save()` and a remote delete during the autosave window.
3. **Verify each audit fix on every path it claims to cover.** Six audit-17 fixes are incomplete because they were applied to one call site, platform or lifecycle hook: §3.1 (scene-based app), §3.2 (readiness before data), §3.3 (prewarm raced by a synchronous read), §5.4 (`saveExternalImport` not reordered), §5.19 (3D path), §6.3 (only the roster clamped). For each future fix, grep for sibling call sites and add a test that exercises the path the finding named.
4. **Clamp or validate peer data once, at admission.** §5.5 (CRDT clocks), §6.2 (relay padding) and §6.3 (names) are all peer-controlled values that are checked at one consumer and trusted at others. Normalizing `GameNetworkModel` in `GameMessagePipeline` (clamp names, clocks, and frame-vs-payload size) protects every downstream consumer, including the LAN relay.
5. **Replace unstructured escape hatches with `@concurrent` and stored tasks.** §3.5, §3.6, §4.4, §7.1, §7.3 and §7.4 are all "work on the wrong executor" or "task nobody owns". The project already uses `@concurrent` well in places (`encodedOffMain`, `audioAsset`); applying it consistently lets roughly 16 `Task.detached` blocks and several `@preconcurrency` imports go (§3.18).
6. **Generate hand-kept lists from their source of truth.** §5.9 (dice bag vs `colorCodes`), §9.9 (9 merge copies), §9.7/§9.8 (8 trackers, 12 LRUs) and §9.14 (3 sides→die switches) are copies that have already drifted apart. Each has a natural generic home in CoreRPG or GameRPG/Model.

---

## 11. What was NOT audited

- `Docu/`, `Snapshots/`, `Integrations/` (third-party), `.git`, `.build`, `DerivedData`.
- The visionOS build of GameRPG, RolePlayGameKit and the app target: the build stopped at DiceRPG (§5.1), so visionOS-only code in those modules was not type-checked.
- Runtime behaviour: no tests, UI tests, Instruments traces or on-device runs. The claims about `startDownloadingUbiquitousItem` on non-ubiquitous URLs (§5.7) and the empty-frame → EOF path (§3.15) come from reading the code and should be confirmed on a device or in a LAN test.
- Algorithmic correctness of the Foundry/UniversalVTT/LevelDB parsers, CRDT types beyond the clock handling, and TabletopKit/RealityKit scene math.
- The 24 findings in `Docu/CODE_AUDIT_Network.md`: only new issues and the network items listed in audit 17 were re-checked.
- Build settings and scheme configuration beyond the sandbox/network entitlement settings; the RPGTabletopGameContent SPM package internals.
- `Tests/` got a quick scan only (flaky wall-clock sleeps in `Tests/GameRPGTests/PlayerFallbackListenerTests.swift:115`, `MasterNetworkControllerTests.swift:409`, `EndToEndJoinTests.swift:22`, `TLSPasscodeHandshakeTests.swift:144`, and `SearchModelTests.swift:32-145` were noted but not deeply reviewed).
- StoreKit product configuration and App Store Connect parity.
- Localization quality: stale-key counts (266 across 11 catalogs, *still open from CODE_AUDIT_17 §9.6*) were noted, wording was not assessed.
- Dice artwork: only naming and coverage were checked against `RawDie.colorCodes`, not the 344 image sets' content.

---

## 12. Verification

Spot-check pattern: open Xcode and command-click the `path:line` reference in this report; it should land on the cited line. There are no Critical findings; the High and key Medium findings below were re-read by me after the agents reported them.

- **§5.1** — open `Modules/DiceRPG/Game/Detail/DicePlayer.swift`, lines 59-64: `.glassEffect(.regular.interactive(), in: .capsule)` has no `#if`. `xcodebuild -scheme MasterRPG -destination 'generic/platform=visionOS Simulator' build` fails with `DicePlayer.swift:63:18: error: 'glassEffect(_:in:)' is unavailable in visionOS` (exit 65). `git show 396b6052 -- Modules/DiceRPG/Game/Detail/DicePlayer.swift` shows the line was added today. I checked every other `.glassEffect(` site; all are gated or commented out.
- **§5.2** — open `Modules/CoreRPG/Controllable/SyncDataControllable.swift` lines 73-79 (stale = in-memory ids not in `fetchIds()`), then `ItemControllable.swift` line 142 (`removePendingOperations` now runs for `withDatabase: false`), and `ItemControllable.swift` lines 193-198 (`isInsert` only calls `replaceSync`, which queues via `CoreDataController.queueReplace`, lines 152-177). `git log -L128,143:Modules/CoreRPG/Controllable/ItemControllable.swift` shows `e32f7d67` added the call. `CoreDataController.fetchId` (line 481 onward) returns `[]` on error.
- **§3.1** — open `Sources/MasterRPG/iOS/iOSAppDelegate.swift` lines 21-36 (`applicationDidEnterBackground`) and lines 38-46 (`configurationForConnecting` → `IosSceneDelegate`). UIKit's documentation states that app-delegate lifecycle callbacks are not delivered to scene-based apps.
- **§5.3** — open `Modules/CoreRPG/Persistence/CoreDataController.swift` lines 184-218 (drain via `clearPendingOperations`; restore only in the apply `catch`) and lines 220-236 (`rollback()` on save failure, with no restore).
- **§5.5** — open `Modules/CoreRPG/CRDT/WallclockTimestamp.swift` lines 106-125 (decode keeps the raw clock) and lines 45-58 (`observe` caps at now + 86,400 s); `LWWRegister.swift` lines 70-84 (`merging` adopts `other._storage` unchanged).
- **§3.2** — open `Modules/RolePlayGameKit/Model/AppModel.swift` line 428 (`markReady()` directly after `adventureRoot.setUp`), `SyncDataControllable.swift` lines 35-39 (`start()` returns an unstructured Task that runs `fetchAll()`), and `Modules/DiceRPG/Intent/DiceEntity.swift` lines 158-163 (the empty result is cached once `isReady`).
- **§5.6** — open `Modules/MapRPG/Map/MapHexGridGeometry.swift` lines 26 and 37-41 (`> 20_000` → `[]`), `MapEditController+HexGrid.swift` lines 41-51 (`replaceGrid` with that result), and `MapEditorScaleRanges.swift` line 13 (`20 ... 200`). Worked example: 8192 × 8192 at size 20 → 237 columns × 274 rows ≈ 64,900 cells.
- **§6.1** — open `Modules/GameRPG/Controller/MasterController+MapMessages.swift` lines 222-231: the key is (player, map), the throttled path returns `nil` with no reply, and the timestamp is written before `stableMapRecoveryBundle` runs.
- **§3.4** — open `Modules/GeneratorRPG/BasicAI/Providers/PdfContentExtractor.swift` lines 86-117: the generic `catch` at line ~110 also catches `CancellationError`, and there is no cancellation check in the loop.
- **§5.8** — open `Modules/DiceRPG/Model/RawDie.swift` lines 95-104 (`case three`) and 139-158 (`sides(3)` → `.three`); `git log -S"case three"` → `c2d185f2`.
- **§5.9** — open `Modules/DiceRPG/View/DiceBag.swift` line 15 (`.die12(color: .D)`) and `RawDie.swift` line 88 (`.twelve: [.A, .B, .C, .G]`); `ls DiceAssets.xcassets | grep ^D12` lists only A/B/C/G, and `D20c-1.imageset` contains `D20-1@1x.png`, etc.
- **§5.10** — `grep -rn invalidateCache Modules Sources Tests` returns only the declaration at `Modules/DiceRPG/Intent/DiceEntity.swift:172`.
- **§8.1** — `git show 396b6052 -- Modules/CoreRPG/Buttons/OverlayButtonStyle.swift` shows `.frame(minWidth: 44, minHeight: 44)` replaced by `.imageScale(.large).padding(8)` in both styles.
- **Dropped:** the agent-reported `.public` log at `Modules/GeneratorRPG/View/PdfSummaryAnalysisView.swift:176` sits inside `#Preview` (line 172), so it never runs in the app.

If any finding doesn't reproduce when you visit the line, send me the specific reference and I'll re-investigate.
