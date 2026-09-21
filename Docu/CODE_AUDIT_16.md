# MasterRPG Code Audit

Generated 2026-09-21. Scope: 2,104 Swift files (~270k LOC including ~70k of tests; ~200k LOC of production code in `Modules/` and `Sources/`) across the MasterRPG, MasterMac, MasterTV, RPGShare and DiceRollerWidget targets and 15 modules. No Metal/other kernels exist. `Docu/`, `Snapshots/`, `Tests/` (quick reads only), `.git` and `.build` are excluded. No `Dead/` folder exists.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

**Ground truth.** A clean full iOS build (`MasterRPG` scheme, iOS Simulator, Swift 6 mode, `SWIFT_STRICT_CONCURRENCY = complete`) produced **zero compiler warnings**. The concurrency findings below are therefore things the compiler cannot see (runtime traps, races across suspension points, lifecycle) rather than diagnostics. Only the iOS scheme was rebuilt; macOS, tvOS and visionOS were not.

**How to read severity and verification.** This is the 16th audit; 15 earlier reports live in `Docu/CODE_AUDIT_*.md`, and the agents were told to skip items §13 of `CODE_AUDIT_15.md` marks fixed. Every item tagged **[verified]** was re-read by me at the cited lines after the agent reported it (§12). Items without the tag were read by the auditing agent but not independently re-read; treat their line numbers as reliable and their severity as the agent's conservative estimate.

---

## 1. Executive summary

Top items to address, in priority order:

1. **[Critical] Narrowing `Int32(...)`/`Int16(...)` traps on peer- or file-supplied integers** — §5.1 — `Modules/CharacterRPG/Controller/DataController.swift:47,56,110` (+ ~30 sites in 11 modules). One crafted `displayState` value crashes the GM's app during a game. **[verified]**
2. **[High] A finite far-future CRDT clock poisons the process and later edits are lost** — §5.2 — `Modules/CoreRPG/CRDT/WallclockTimestamp.swift:26-52`. The §5.3 fix in `CODE_AUDIT_15` only rejected non-finite values. **[verified]**
3. **[High] LevelDB block decode is quadratic in memory (400 KB block → ~5 GB)** — §6.1 — `Modules/CoreRPG/Foundry/FoundryLevelDBReader.swift:171-215`. A crafted Foundry pack kills the app on import. **[verified]**
4. **[High] Master drops live player connections without cancelling them** — §3.1 — `Modules/GameRPG/Master/MasterNetworkController.swift:122-138`. Players stay connected at the socket level and are silently black-holed. **[verified]**
5. **[High] Background App Intents run before the Core Data stack exists** — §5.3 — `Modules/RolePlayGameKit/View/DatabaseInitializationView.swift:36-73`. "Created" is returned and the data is lost. **[verified; not runtime-tested]**
6. **[High] Dice numeric conversions trap or allocate without bound on imported/synced values** — §5.4 — `Modules/DiceRPG/Model/DiceModel.swift:349-364`. **[verified]**
7. **[High] LAN listener has no handshake deadline; idle sockets exhaust the 16 pending slots** — §6.2 — `Modules/GameRPG/Network/ConnectionThrottleTracker.swift:30-51`. Anyone on the Wi-Fi can block joins.
8. **[Medium] Master `processMessages` strands the message backlog when the draining task is cancelled** — §3.2 — `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:207-225`. Player has the handoff, Master does not. **[verified]**
9. **[Medium] Dead code that `CODE_AUDIT_15` §13 said was "still used" has no callers** — §9.1 — `TabBarMinimizeBehavior26.swift`, `GameOverlayTabViewModifier.swift`, `SheetFullScreenModifier.swift` and six more files (~430 LOC). **[verified]**
10. **[Medium] Thumbnail decoding runs on the main actor** — §3.4 — `Modules/PhotoRPG/Controller/CacheController.swift:68-77`, `Modules/PhotoRPG/Controller/FileUrlDataController+ImageResolve.swift:12-27`. Scroll hitches in photo and map lists.

---

## 2. Quick wins (≤30 min each)

- **Clamp `displayState`, `addDiceEvery` and entry indices with `Int32(clamping:)`/`Int16(clamping:)`** — `Modules/CharacterRPG/Controller/DataController.swift:47,56,110`. Mirror the one site already fixed at `AdventureRPG/Controller/DataController.swift:97` (§5.1).
- **Delete `Bundle+decode.swift`** — `Modules/CoreRPG/Extensions/Bundle+decode.swift:1-39`. Unreferenced; holds all 7 `fatalError`s (§9.5).
- **Delete the nine dead files** listed in §9.1 (~430 LOC), then rebuild on all four platforms.
- **Cancel every dropped connection in `resetConnections`** — `Modules/GameRPG/Master/MasterNetworkController.swift:137` (§3.1).
- **Bound `MonotonicWallClock.observe`** to "now + small skew" — `Modules/CoreRPG/CRDT/WallclockTimestamp.swift:42-50` (§5.2).
- **Cap reconstructed key length in `decodeEntries`** — `Modules/CoreRPG/Foundry/FoundryLevelDBReader.swift:203-206` (§6.1).
- **Cancel `exportTask` on sheet disappearance** — `Modules/CoreRPG/FileViews/ExportProgressPanelView.swift:44-65` (§3.5).
- **Change device-name log privacy from `.public` to `.private`** — `Modules/GameRPG/Network/GameNetworkController.swift:84,109,130,142,148,165`, `ListenerManager.swift:48,54,193,196` (§6.7).
- **Fix `SharePlayButton` and `BrowserRowView` strings** so they localize — `Modules/GameRPG/SetupViews/SharePlayButton.swift:26-45`, `Modules/GameRPG/Browser/BrowserRowView.swift:186,189` (§4.2).
- **Replace `.cornerRadius(5)`** — `Modules/GameRPG/Statistics/View/GameStatisticsDiceChart.swift:25` (§4.3).
- **Delete the commented-out `changeNavigation` block** — `Modules/RolePlayGameKit/View/ExtendedTabBar.swift:121-131` and the other single-line commented calls in §9.6.
- **Remove the empty `Modules/CoreRPG/Shaders/` folder** (contains only `.DS_Store`) (§9.19).
- **Fix the misspelled symbols** `StoreManiplable`, `objectAttritube`, `endcoded` (§9.18).

---

## 3. Concurrency

### 3.1 Master drops live player connections without cancelling them
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:122-138` (`resetConnections`); `Modules/GameRPG/Network/ConnectionController.swift:75-80` (`deinit`), `:220-244` (`startReceiveLoop`/`receiveLoop`)
- **What:** `resetConnections()` (reached from `stopStreaming()`, `startStreaming()` and `listenerCancelled()`) sets `networkModel.connections = []` at line 137 and never calls `cancel()` on the removed connections. The `deinit` comment relies on that ("Owners may drop connections without an explicit cancel()"), but once `.ready` the receive `Task` holds `self` strongly for the whole loop (`startReceiveLoop`, lines 222-224), so `deinit` never runs.
- **Why:** After an `NWListener` failure or a `stopStreaming()`, every already-admitted player stays connected at the socket level. Its messages still reach `delegate.received`, `sendResponse` returns false because the id is gone, and broadcasts skip it. The player sees a healthy TLS connection, so its `lostConnection` and reconnect fallback never fire. The peer is silently black-holed and the `ConnectionController` and `NWConnection` leak until the peer disconnects.
- **Action:** `cancel()` every dropped connection during reset (through a tracked teardown task), and stop holding a strong `self` for the lifetime of the receive loop (weak re-check per iteration).
- **Severity:** High

### 3.2 Master `processMessages` strands the backlog when the draining task is cancelled
- **Location:** `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:191-225` (esp. 207-225); `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:495-551` (esp. 503-514 and 549-551); `Modules/GameRPG/Network/ConnectionController.swift:206-212`
- **What:** The shared `GameMessagePipeline` is drained inside whichever peer's receive task enqueued first. On cancellation, Master requeues the in-hand event and returns; the comment says the backlog resumes on "the next real trigger". Player adds a handoff `Task` for the remaining backlog on that path (lines 503-514) but not in its `catch is CancellationError` branch (549-551), which drops the in-hand event and also strands the backlog.
- **Why:** `teardown()` for connection A cancels A's `receiveTask`, and with it a drain that was handling B's and C's messages. Queued dice results, acks and state updates are not processed until an unrelated later message arrives; a final single-shot message never triggers the retry. Result: silent game-state divergence.
- **Action:** Give the drain its own owner (a long-lived consumer task per controller reading an `AsyncStream`), or add the same handoff to Master and to Player's cancellation catch. The drain must not run in a peer's cancellable context.
- **Severity:** Medium (the code path is verified; the trade-off is documented in `CODE_AUDIT_Network` §5.15, but the consequence is divergence rather than a retry)

### 3.3 `listenerNewConnection` admits a connection after the master was stopped or reset
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:229-246`
- **What:** The connection-limit check runs before `await connectionThrottle.shouldAllow(...)` and `await connectionThrottle.register(...)`; `addNew(...)` runs after both awaits with no re-check of `isStreaming` or a listener generation.
- **Why:** A `stopStreaming()` or `resetConnections()` during the suspension lets a stale connection append to the freshly cleared list and start while `isStreaming == false`; it has no owning listener and hits the leak in §3.1.
- **Action:** Re-validate a run generation after each await (as `ListenerManager` does) and cancel the `NWConnection` if stale.
- **Severity:** Medium

### 3.4 Thumbnail decode runs on the main actor
- **Location:** `Modules/PhotoRPG/Controller/CacheController.swift:54-60,68-77`; `Modules/PhotoRPG/Controller/FileUrlDataController+ImageResolve.swift:12-27`; `Modules/PhotoRPG/Root/PhotoRootModel+PhotoAccess.swift:14-30`; `Modules/CoreRPG/Extensions/Image+AKImage.swift:107-136`
- **What:** All 8 build configurations set `SWIFT_APPROACHABLE_CONCURRENCY = YES`, so a plain nonisolated `async` function runs on its caller's actor. `downsampledSource` is `@MainActor` and calls `resolvedImage` directly, so its synchronous decode closures (`AKImage.downsampledThumbnail`, which forces immediate decode) run on the main actor, as does the following `resize(to:)`. `createImage` already hops through a `@concurrent` helper; `createThumbnail` does not.
- **Why:** Every uncached list thumbnail and map/photo crop source decodes ImageIO on the main thread; scrolling a photo or map list of a few hundred items produces a hitch per row.
- **Action:** Make `resolvedImage`, `downsampledSource` and `resize` `@concurrent` (the decode closures are already `Sendable`), or route through a `@concurrent` helper like `decodedImage`.
- **Severity:** Medium (code path verified; hitch size not profiled)

### 3.5 Export sheet dismissed by system gesture leaves the detached export running
- **Location:** `Modules/CoreRPG/FileViews/ExportProgressPanelView.swift:44-47,56-65,103-125`; `Modules/CoreRPG/Controllable/ExportControllable.swift:222-256`
- **What:** The export is a `Task.detached` stored in `@State exportTask` and cancelled only by the toolbar Cancel button. The `.task` that awaits it has no cancellation handler, and there is no `.onDisappear` or `interactiveDismissDisabled`. `ImportProgressPanelView` already handles this case.
- **Why:** Swiping the sheet away (iOS/visionOS) or closing the window (macOS) leaves a possibly multi-GB export writing with no UI owner, and it then replaces the destination file unattended.
- **Action:** Wrap the wait in a cancellation handler that cancels the task, or cancel on disappear and disable interactive dismissal while running.
- **Severity:** Medium

### 3.6 `AppIntentContentInvalidator` refreshes shortcuts on every save and its inner reindex is uncancellable
- **Location:** `Modules/CoreRPG/App/AppIntentContentInvalidator.swift:19-27`; `Modules/CoreRPG/Controllable/ItemControllable.swift:402`; `Modules/CoreRPG/Stores/DebouncerModel.swift:52-58`; `Modules/DiceRPG/Intent/DiceShortcutCatalog.swift:130-137`
- **What:** `invalidate()` calls `updateAppShortcutParameters` synchronously on every `ItemController.save()`, then debounces reindexing behind a one-second delay. Cancelling the debounce only cancels the sleeping outer task; the inner unstructured `Task` running `reindexAll` is never tracked, and each `reindexAll` walks every item of every module on the main actor.
- **Why:** During bulk edits, imports or sync, shortcut refreshes run N times and reindexes more than 1 s apart overlap, piling main-actor entity building and Spotlight indexing.
- **Action:** Debounce refresh and reindex behind one tracked task, await the reindex inside it so cancellation propagates, and coalesce while one is running.
- **Severity:** Medium

### 3.7 `toggleConnection` can report a successful join as failed
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift:100-154` (esp. 118-125), `253-262`
- **What:** If `.ready` arrives while `await start(model:)` is suspended, `resolvePendingConnection(success: true)` clears `joinAttemptToken` with no continuation parked. On resume the `joinAttemptToken == token` guard fails and the function returns `false` ("superseded"); `observeRemovedConnection()` is never armed.
- **Why:** When the main actor is busy longer than the LAN TLS-PSK handshake, the UI shows the join as failed and re-prompts for the code while the connection is live and its removal unobserved.
- **Action:** Store the attempt's outcome and check it after `start`, distinguishing "superseded" from "resolved".
- **Severity:** Medium

### 3.8 `BrowserManager` still has the stale-cancellation state overwrite fixed in `ListenerManager`
- **Location:** `Modules/GameRPG/Browser/BrowserManager.swift:55-95`
- **What:** `start()`/`stop()` reuse one instance, and the old `networkTask`'s `catch` blocks write `connectionState` with no generation check (fixed for `ListenerManager` in `CODE_AUDIT_15` §3.7).
- **Why:** `stop()` then an immediate `start()` lets the old task resume later and set `.cancelled`, flipping `isBrowsing` false while the new browser runs; a repeat `start()` then spawns a second browser.
- **Action:** Apply the same run-generation token and ignore catch-block writes from superseded runs.
- **Severity:** Medium

### 3.9 `BrowserManager.removed` is overwritten on every endpoint update
- **Location:** `Modules/GameRPG/Browser/BrowserManager.swift:114-131`; consumer `Modules/GameRPG/Player/PlayerNetworkController.swift:293-321`
- **What:** `updateGames` assigns `removed` to the delta of the latest update only, and the consumer reads it after at least two main-actor hops.
- **Why:** If a Bonjour remove-and-re-add of the master's service lands two updates in quick succession, the second sets `removed = []` and the removal is never seen, so the fallback-listener path is skipped.
- **Action:** Accumulate removals until consumed (consume-and-clear, or an `AsyncStream` of removal events).
- **Severity:** Low

### 3.10 `setCurrent(itemId:)` uses a stale index across an `await`
- **Location:** `Modules/CoreRPG/Controllable/GameControllable.swift:79-88,205-222`
- **What:** `existingGameItem(for:)` returns an array index; the caller then awaits `gameModel.insert(itemId:at:removeIndex:)`, which calls `items.remove(at: removeIndex)`. `apply(itemId:...)` in the same file was already made atomic (`CODE_AUDIT_EditItem` §3.3); this path was not.
- **Why:** Two quick shows, or a game-item removal racing a network reveal, shrink `items` between the awaits and `remove(at:)` traps or removes the wrong entry.
- **Action:** Find and mutate in a single synchronous main-actor function keyed by item id.
- **Severity:** Medium

### 3.11 Pending-operation flush: existence check and apply are separate `perform` blocks
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:170-206` (also `260-285`, `376-395`)
- **What:** `batchExists` runs in one `context.perform`, and the apply in a later one, with nothing preventing CloudKit merges or direct `replace(uuid:...)` calls in between.
- **Why:** A record deleted by a CloudKit import between the two steps makes the queued edit silently drop; a record created by another writer in between gets a duplicate uuid row, later resolved by object-ID string, not by recency.
- **Action:** Do the existence check and apply inside one `context.perform`, and log dropped operations.
- **Severity:** Medium

### 3.12 Failed pending operations are re-queued behind newer edits, so stale state wins
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:169-200` (re-add at 185; last-wins map at 175-177)
- **What:** After the queue is drained and `batchExists` throws, the drained operations are appended after any operations enqueued during the suspension; the next flush builds its map in queue order with last-wins.
- **Why:** Edit v1 of X is queued and flushed, `batchExists` throws, the user edits X to v2, and the re-add puts v1 after v2, so v1 overwrites v2 on disk and, through CloudKit, on other devices.
- **Action:** Re-insert failed operations at the front, or order by an operation sequence or timestamp.
- **Severity:** Medium

### 3.13 `updateFromSync` computes deletions from an older snapshot than the in-memory items
- **Location:** `Modules/CoreRPG/Controllable/SyncDataControllable.swift:42-100` (esp. 72-95)
- **What:** `currentIds` is fetched with `await`, then `staleIds` is computed from `itemDataModel.items` after that suspension; the insert/update loops each `await fetch(id:)` and apply without re-validating.
- **Why:** A CloudKit deletion batch coinciding with a just-created local item removes it from the UI; a stale fetch applied after a local delete re-inserts a ghost model.
- **Action:** Compute the diff synchronously against a snapshot taken with the fetch, exclude ids with pending operations, and re-check membership after each await.
- **Severity:** Low

### 3.14 Persistent-history `process()` can run concurrently with itself
- **Location:** `Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift:167-215`
- **What:** `schedule()` cancels the debounce `Task` even while `process()` is suspended in awaits that do not observe cancellation, so a second `process()` starts on the same actor reading the same `loadDate()`.
- **Why:** Duplicate fetch-and-merge on the view-context queue during a large CloudKit import burst; the timestamp is written by whichever finishes last.
- **Action:** Serialize `process()` with an in-flight flag and a "needs rerun" bit, separate from the debounce task.
- **Severity:** Low

### 3.15 Widget and app intents race on the shared dice `UserDefaults`
- **Location:** `Modules/DiceRPG/Controller/GameController.swift:610-644`; `Modules/DiceRPG/Intent/DiceIntents.swift:36-48`; `Sources/DiceRollerWidget/DiceRollerIntents.swift:26-56`
- **What:** The app's in-process `Mutex` and timestamp guard serialize `diceUpdateWidget`, but the app `RollDiceIntent` and the widget extension's `RollDiceIntent` (another process) each load then save the same App Group key with no lock.
- **Why:** A widget tap and an in-app roll within milliseconds lose one update; the widget may show an older roll.
- **Action:** Route all writers through one "store latest roll" API with a monotonic timestamp compare-and-set, using one overwrite key instead of read-modify-write.
- **Severity:** Low

### 3.16 `RpgSpotlightIndexerDelegate` never cancels its notification-loop task
- **Location:** `Modules/CoreRPG/Persistence/RpgSpotlightIndexerDelegate.swift:35,49-63`
- **What:** `indexingTask` iterates a `NotificationCenter.notifications` sequence that never finishes; there is no `deinit` or `stopIndexing()`.
- **Why:** When `DataBaseModel.setup()` recreates the persistence controller (Cloud/Local switch, recovery), the old loop lives for the process lifetime and duplicates logging and model updates.
- **Action:** Cancel in `deinit` or through an explicit stop when the controller is replaced.
- **Severity:** Low

### 3.17 visionOS `ImagePresentationView` frame sync is armed once but torn down in `onDisappear`
- **Location:** `Modules/PhotoRPG/Space/ImagePresentationView.swift:62-92`
- **What:** The `AsyncStream`, consumer task and update subscription are created in `RealityView`'s `make`, which runs once; `onDisappear` finishes the stream and cancels the task, `sceneUpdateSubscription` is never cancelled, and nothing re-arms on appear.
- **Why:** If the window disappears and reappears without `make` re-running, per-frame resync is dead and the view freezes on a stale frame (the failure the file's own comment describes).
- **Action:** Tie the stream, task and subscription lifetime to the RealityView (a `.task` that owns them) or arm in `onAppear`.
- **Severity:** Low

### 3.18 `FakeExportController` is `@unchecked Sendable` with mutable state and ships in production
- **Location:** `Modules/CoreRPG/Fake/FakeExportController.swift:6-25`
- **What:** Unsynchronized `var itemControllable` and `_hubControllable`; the hub setter mutates state despite the "immutable after init" claim, and the getter `preconditionFailure`s if unset.
- **Why:** Only previews and tests use it today, but any non-preview use is an unsynchronized access compiled into the shipping module.
- **Action:** Make it `@MainActor`, drop `@unchecked Sendable`, and move it under `#if DEBUG` or a support target.
- **Severity:** Low

### 3.19 LAN broadcast sends can be reordered
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:144-177`; `Modules/GameRPG/Model/GameMessagePipeline.swift:293-298` (`encodedOffMain`)
- **What:** `sendResponse` awaits an off-main encode and the main actor is re-entrant across it; independent tasks that call `send` do not serialize (SharePlay has a single-queue FIFO sender, LAN does not).
- **Why:** A slow `show(map)` encode can be overtaken by a fast pin update, so players receive the update before the map it belongs to; counters recover it, but with avoidable drops and repair requests.
- **Action:** Assign the wire sequence and enqueue into a per-connection FIFO before encoding.
- **Severity:** Low

### 3.20 `ListenerServerController` still delivers state and connection callbacks through per-event unordered Tasks
- **Location:** `Modules/GameRPG/Network/ListenerManager.swift:160-167,186-215`
- **What:** `CODE_AUDIT_15` §3.6 fixed this for `ConnectionController` with one `AsyncStream`; the listener's `stateUpdateHandler` and `newConnectionHandler` still spawn a `Task` per callback into an unbounded stream.
- **Why:** `.ready`/`.failed`/`.cancelled` have no ordering guarantee, and a late connection after `finish()` is dropped without `cancel()`, leaving the dialing peer to its own timeout; a flood of unauthenticated dials queues without a cap.
- **Action:** Feed a single `AsyncStream` from the handlers, consume in one ordered loop, cancel late arrivals and bound the buffer.
- **Severity:** Low

### 3.21 macOS: cached shared `NSImage` mutated on read from a nonisolated async context
- **Location:** `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:53-58`; `Modules/CoreRPG/Extensions/Image+AKImage.swift:89-91`
- **What:** `photo(for:)` is not main-actor isolated yet calls `image?.resetSize()`, which assigns `NSImage.size` on the cached instance that views also hold.
- **Why:** `NSImage` mutation is not thread-safe; wrong sizes or a race on macOS (a no-op on iOS).
- **Action:** Return a copy or make the size correction read-only.
- **Severity:** Low

> Not a finding: the agents read the `@unchecked Sendable`/`nonisolated(unsafe)` sites at `AudioListenerCoordinator.swift:30-42`, `GameBoard.swift:134-180`, `CoreDataChangeObserver.swift:22-60`, `FoundryRuleModels.swift:170-172`, `CoreDataPersistenceController.swift:242`, `CloudKitCoreDataPersistenceController.swift:279` and `PerformanceTrace.swift:23` and found their stated invariants hold. The only unsound instance is §3.18.

---

## 4. API modernity

### 4.1 `AnyView` type erasure in every module's view factory
- **Location:** `Modules/CoreRPG/Controllable/ViewControllable.swift` (16), `Modules/MapRPG/Controller/ViewController.swift` (10), Weather/Character/Audio `ViewController.swift` (8 each), Table/Space/Photo/Dice/Adventure `ViewController.swift` (4-6 each), `Modules/CoreRPG/Navigator/Core/NavigationModifiers.swift` (6), `Modules/CoreRPG/ItemList/EntryDataEditable.swift:42,144`, `Modules/CoreRPG/Route/InternalRoute.swift:41`, `Modules/CoreRPG/Navigator/Views/ManagedNavigationStack.swift:120,155`
- **What:** 105 non-comment occurrences in 22 files, from the `ViewControllable` factory protocol and `mappedNavigationView(for:) -> AnyView` in the Navigator. This is the project's most widespread rule violation (`CLAUDE.md` says avoid `AnyView`).
- **Why:** It discards structural identity and diffing for every module view factory, and is why call sites need `.equatable()` workarounds (`Modules/PdfRPG/Controller/ViewController.swift:15,19`).
- **Action:** Move to `@ViewBuilder` factories or generic/closure-based factories, keeping one documented type-erasure boundary in the Navigator.
- **Severity:** Medium

### 4.2 `SharePlayButton` and `BrowserRowView` strings are never localized
- **Location:** `Modules/GameRPG/SetupViews/SharePlayButton.swift:26-45` (callers `SelectedAdventureView.swift:194`, `SelectedPlayerView.swift:146`); `Modules/GameRPG/Browser/BrowserRowView.swift:186,189`
- **What:** `SharePlayButton` takes `any StringProtocol`, which resolves to the verbatim-string `Button` overload; `BrowserRowView`'s `Button("Cancel")` and `Button("Join")` skip `bundle: .module`.
- **Why:** Three shipping strings are untranslated or looked up in the wrong table.
- **Action:** Take a `LocalizedStringResource` (or `Text`) in `SharePlayButton` and use `Text(..., bundle: .module)` labels.
- **Severity:** Low

### 4.3 Minor rule hits
- **Location:** `.cornerRadius(5)` at `Modules/GameRPG/Statistics/View/GameStatisticsDiceChart.swift:25`; `@ObservedObject` at `Modules/GameRPG/SetupViews/SharePlayButton.swift:21-22` (`GroupStateObserver`, framework-mandated); `UIGraphicsImageRenderer` at `Modules/CoreRPG/Extensions/Image+AKImage.swift:133`; `Color(UIColor.systemBackground)` at `Modules/CoreRPG/Platform/Color+Background.swift:9-11`; completion-style `performBackgroundTask` at `Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift:72-86` and `loadObject(ofClass:)` at `Modules/CoreRPG/Files/FileDropDelegate.swift:34` (async variants exist); a `Thread.isMainThread` then `assumeIsolated` fast path at `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:250-259`
- **What:** One `cornerRadius`, one framework-driven `ObservableObject`, one `UIGraphicsImageRenderer`, one UIKit-colour bridge, two completion-handler APIs, and a thread check whose own comment admits the synchronous callback is not guaranteed.
- **Why:** Small deviations from project rules; the thread check can trap if the store-load callback ever arrives off the main thread.
- **Action:** Use `.clipShape(.rect(cornerRadius:))`, observe the group-state publisher in a `.task`, use `ImageRenderer`/ImageIO for the crop, adopt the async variants, and always hop with `Task { @MainActor }` (or make store loading `async`).
- **Severity:** Low

### 4.4 Rules checked and clean
_No findings._ Grep and read-through found zero uses of `Task.sleep(nanoseconds:)`, one-parameter `onChange`, `foregroundColor`, `tabItem`, `NavigationView`, `UIScreen.main`, `ScrollViewReader`, `showsIndicators`, `fontWeight(.bold)`, `String(format:)`, legacy formatters, `replacingOccurrences`, `URL(fileURLWithPath:)`, `Array(x.enumerated())` in `ForEach`, hard-coded system font sizes, `try!`/`as!`, `ObservableObject` (beyond §4.3), or `.contains()` on user-entered filter text. `DispatchQueue` appears 3 times, all as `NWConnection`/`NWListener` queues. No `#available` guard is dead against the 26.0 deployment target.

---

## 5. Bugs / logic errors

### 5.1 Narrowing `Int32(...)`/`Int16(...)` traps on peer- or file-supplied integers
- **Location:** `Modules/CharacterRPG/Controller/DataController.swift:47,56,110`; decoded unchecked at `Modules/CharacterRPG/Model/ValueModel.swift:50` and `Modules/DiceRPG/Model/DiceModel.swift:84`. Same trapping initializers under `Modules/*/Controller/DataController.swift`: Pdf 69,114; Dice 56,79,160; Weather 53,100; Adventure 46; Photo 45,86; Rule 60,103,105; Generator 45,88; Map 67,185,212,238; Space 45,86; Table 45,86; Audio 46,85 (34 non-`clamping` narrowings in total)
- **What:** Each module's `applySnapshot` and entry `map` narrow decoded `Int` fields to Core Data attribute types with trapping initializers (`Int32(snapshot.displayState)`, `Int16(index)`, `Int16(snapshot.addDiceEvery)`). `ValueModel` decodes `displayState` as a raw `Int` with no range check, and no import or peer policy validates it. Only `AdventureRPG/Controller/DataController.swift:97` was changed to `Int16(clamping:)`, and its comment shows the risk was already understood.
- **Why:** A player sends a Character package whose JSON has `"_displayState": 4294967296`. The master merges it and the next persistence flush runs `applySnapshot` inside `context.perform`, where the narrowing traps; a Swift trap cannot be caught, so the GM's app dies mid-game. Cost to the attacker is a few bytes plus a LAN join code or SharePlay seat. A crafted `.gmz` does the same on user import, and any item with more than 32,767 entries traps at `entry.index = Int16(index)`.
- **Action:** Validate or clamp `displayState` (against `DisplayStateMask`), `addDiceEvery` and per-item entry counts at decode or in `prepareDecodedItem`, so every untrusted path is covered, and replace the narrowing initializers in every `applySnapshot`/`map` with `clamping:` or `exactly:` plus a failure path.
- **Severity:** Critical **[verified]** (the trapping line and the missing validation were re-read; the network path was traced by the agent through `handleValue` → `updatePlayer` → `importNetwork` → `merge(forceMerge: true)` → `queueReplace` and was not re-traced by me)

### 5.2 A finite far-future CRDT clock poisons the process, and later edits are lost
- **Location:** `Modules/CoreRPG/CRDT/WallclockTimestamp.swift:26-52` (`observe` 42-50, `now` 26-32); `Modules/CoreRPG/CRDT/LWWRegister.swift:71-82,117-129`; `Modules/CoreRPG/CRDT/CRDT.swift:60-63`; `Modules/CoreRPG/Extensions/JSONCoding.swift:11-13`
- **What:** `CODE_AUDIT_15` §5.3 is marked Fixed, but `observe` only rejects non-finite values and otherwise ratchets `lastIssued` to any finite remote timestamp. For `1.7976931348623157e308`, `now()` returns `last.nextUp`, which is `+inf`. `JSONCoding.encoder` is a plain `JSONEncoder` that throws on infinity, and `CRDT.rawValue` converts the failed encode into `""`.
- **Why:** A player re-syncs a package with one register carrying that clock. From then on every local register write on the GM device has clock `+inf`, persists as `""`, and on reload fails to decode and falls back to the default, so edited names and descriptions revert to empty (and propagate through CloudKit). Even a finite huge clock (1e300) permanently disables wall-clock semantics for that process.
- **Action:** Bound `observe` to "now plus a small skew" (the codebase already has `NetworkTimestampPolicy.maximumFutureSkew`), and make `CRDT.rawValue` fail loudly instead of returning `""`.
- **Severity:** High **[verified]**

### 5.3 Background App Intents run against root models whose Core Data stack was never initialized
- **Location:** `Modules/RolePlayGameKit/View/DatabaseInitializationView.swift:36-49,64-73`; `Modules/DiceRPG/Intent/DiceManagementIntents.swift:8-56` (`supportedModes` at line 12); `Modules/CoreRPG/Controllable/ItemControllable.swift:391-403`; `Modules/CoreRPG/Controllable/ItemEntityQuery.swift:61-98`; `Modules/DiceRPG/Root/DiceRootModel.swift:82-105`; `Modules/DiceRPG/Intent/DiceEntity.swift:143-160`; same pattern in the Pdf/Weather/Character/Photo/Rule/Adventure management intents
- **What:** `DataBaseModel.setup()` and `appModel.setupRootModels` run only from `.task` modifiers in `DatabaseInitializationView`, i.e. after a SwiftUI scene exists. Intents declared with `.background` mode can run when the app is launched without one. `ItemController.save()` is `try await dataControllable?.save()`, a silent no-op when `dataControllable` is nil, and nothing waits for readiness.
- **Why:** `CreateDiceIntent` inserts in memory, "saves" nothing, indexes the entity in Spotlight and returns "Created"; the data is lost on suspend. Entity queries return empty for Shortcuts/Siri parameter resolution, and `DiceEntity`'s cache stores the empty list with a fresh timestamp, serving it for 60 s.
- **Action:** Add an awaitable, idempotent "database ready" gate on `AppModel`, have `ItemEntityQuery` and every background intent await it, start DB initialization from the app or app delegate instead of a view `.task`, and never cache results while the root is not ready.
- **Severity:** High **[verified in code; not runtime-tested on device]**

### 5.4 Dice numeric conversions trap or allocate without bound on imported or synced values
- **Location:** `Modules/DiceRPG/Model/DiceModel.swift:349-353` (`inlineText`) and `355-364` (`resetDice`); `Modules/DiceRPG/Controller/GameController.swift:444,514,532`; `Modules/DiceRPG/Game/Editor/DiceQuickEditor.swift:77`; `Modules/DiceRPG/Controller/DataController.swift:79`; `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+DiceAndValues.swift:37-58`; `FoundryVTTDomainMapper+SharedHelpers.swift:405-419`; `Modules/CharacterRPG/View/EntryListDiceRow.swift:49-66`
- **What:** `Int(modifier)` and `Int(compareValue)` are trapping conversions of finite-but-huge `Double`s (only `isFinite` is guarded); Foundry formulas accept `d<sides>` with any positive `Int`, which can overflow `sumResult`; and `resetDice` builds `(1...number).map { duplicate() }` with `number = Int(compareValue) / addDiceEvery`, where `compareValue` comes from any calculated Character value.
- **Why:** A Foundry system package with formula `1d20+99999999999999999999999` produces a Dice item that crashes the dice list when rendered. A Character stat of 1,000,000,000 with "add dice every 1" allocates about a billion `DieModel`s on the main actor from an `onChange`, hanging or killing the app. `DataController` stores modifier and compareValue as `Float`, so a large `Double` becomes `+inf`.
- **Action:** Clamp sides, count, modifier and compareValue on import and decode, use saturating or `exactly:` Double-to-Int conversions everywhere, cap `resetDice` at a small maximum dice count, and use `clamping:` for `addDiceEvery`.
- **Severity:** High **[verified for the trapping conversions at lines 349-364; the Foundry and Character-stat routes were traced by the agent]**

### 5.5 `RawDice`/`RawDieCounter` arithmetic is still unchecked (re-check of `CODE_AUDIT_15` §5.11)
- **Location:** `Modules/DiceRPG/Model/RawDice.swift:42,73-74,121-125`; `Modules/DiceRPG/Model/RawDieCounter.swift:22-25,37`; `Modules/DiceRPG/Model/RawDie.swift:31-33`
- **What:** The earlier fix clamped per-term count and made `min`/`max` saturating, but `modifier += number` in `parse`, `existingDie.count += dieCounter.count` in `addDie`, and `result += die.roll()` / `result + modifier` in `roll()` remain plain arithmetic.
- **Why:** `"1000d9223372036854775807".roll()` overflows on the second die and traps; text such as `+9223372036854775807+1` traps in `parse`. Notation comes from imported or peer text.
- **Action:** Use the existing `saturatingSum`/`saturatingProduct`, clamp the `addDie` merge, and bound `sides` in `RawDie(text:)`.
- **Severity:** Medium

### 5.6 Keychain write errors are ignored and the UserDefaults migration deletes its only copy regardless
- **Location:** `Modules/GameRPG/Network/JoinCodeStorage.swift:22-58`; `Modules/GameRPG/Network/GameJoinCodeModel.swift:112-145`
- **What:** `set` discards the results of `SecItemUpdate`/`SecItemAdd` (the protocol returns `Void`); `loadOrGenerate` writes the legacy value and then removes the `UserDefaults` copy unconditionally. Items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, and macOS does not set `kSecUseDataProtectionKeychain`.
- **Why:** If the app launches while the device is locked (a background launch by intent or widget) or a re-signed macOS build is denied access, the read returns nil and the code is silently regenerated, and the migration can delete the only stored code without a successful write. The GM then advertises a code different from the one already shared.
- **Action:** Return a success value from `set`, remove legacy defaults only after a verified write, use the data-protection keychain on macOS, and do not regenerate on `errSecInteractionNotAllowed`.
- **Severity:** Medium

### 5.7 Peer-supplied map-pin and Space-transform numbers are not validated
- **Location:** `Modules/MapRPG/Controller/GameController+Pins.swift:99-156`; `Modules/MapRPG/Model/MapPinModel.swift:144-161`; `Modules/SpaceRPG/Controller/GameController.swift:251-253`; `Modules/SpaceRPG/Model/SpaceTransformModel.swift:15-33`; `Modules/GameRPG/Table3D/GameTableProjection.swift` (`tablePosition(for:)`)
- **What:** `updatePin` accepts any `location` for the sender's own pin and rebroadcasts it; `MapPinModel` decode does not check `location`, `healthPercent` or the `players` size; `isValidSpaceTransform` only checks that the payload decodes.
- **Why:** A player sets their pin to (1e300, -1e300) and every peer projects it, giving absurd 2D offsets and inf/NaN `SIMD3` positions on the 3D table; a zero-length quaternion or zero scale gives NaN transforms in the visionOS Space viewer. This is a griefing/stability issue, not a confirmed crash.
- **Action:** On receipt require finite values, clamp pin location to the map bounds, bound `players` and `name`, and validate `SpaceTransformModel` (finite, non-zero scale within limits, normalized rotation).
- **Severity:** Medium

### 5.8 The two `FileUrlDataController.url(for:action:)` overloads have drifted
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:187-214` (async closure) vs `216-255` (sync closure)
- **What:** Both do the `.url` cache, `.newCloud`, `absoluteUrl`, bookmark resolution and security-scoped access. Only the sync overload writes `fileUrl.data` to a temp file when there is no bookmark (lines 227-236); the async overload ignores `fileUrl.data`.
- **Why:** A staged, not-yet-committed import file resolves to `fullUrl` on the async path instead of its bytes, so behavior depends on which closure type the caller uses.
- **Action:** One private `resolveProcessUrl(for:) async` used by both overloads, and decide deliberately whether the temp-file fallback applies to the async path.
- **Severity:** Medium

### 5.9 Release-active `preconditionFailure`s reachable at view presentation
- **Location:** `Modules/CoreRPG/Sheet/TableRootSheet.swift:35`; `Modules/AdventureRPG/View/AdventureSheet.swift:103`; `Modules/CharacterRPG/Root/ViewerRootView.swift:120`; also `Modules/CoreRPG/Controllable/ItemControllable.swift:82`, `ExportControllable.swift:39`, `Persistence/CoreDataRelationship.swift:29`, `Modules/AdventureRPG/Controller/LinkController.swift:30`, `ExportController.swift:32`, `Modules/RuleRPG/Controller/LinkController.swift:34`, `ExportController.swift:26`
- **What:** 11 preconditions guard "root manager / link register / export hub set after setup"; `CoreDataRelationship.swift:29` fires when a managed object has no context. Three run at view presentation.
- **Why:** A crash in production if any module root is presented before `rootManager` is assigned (window restoration or deep-link timing).
- **Action:** Keep the crashes where they encode a true invariant, but render a placeholder instead of trapping in the three view-level sites.
- **Severity:** Medium

### 5.10 Non-atomic temp copy of file data that is never cleaned up
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:230-240`
- **What:** For a `FileUrl` carrying `data`, `data.write(to: tempUrl)` is not atomic and the file stays in `URL.temporaryDirectory/<fileId>.<ext>` after use.
- **Why:** Two concurrent accesses for one file id (thumbnail plus viewer) can let one action read a half-written file; copies of imported PDFs, audio or images persist in tmp until the OS clears it.
- **Action:** Write atomically and delete after the action, or use unique temp names per call.
- **Severity:** Low

### 5.11 LAN hosting ends on any listener failure with no retry
- **Location:** `Modules/GameRPG/Network/ListenerManager.swift:88-106`; `Modules/GameRPG/Master/MasterNetworkController.swift:224-226`
- **What:** `.failed` or `.cancelled` from `NWListener` maps to `listenerCancelled()`, which calls `stopStreaming()`.
- **Why:** A transient listener error (Wi-Fi roam, sleep/wake) ends the LAN session for every connected player and needs a manual restart.
- **Action:** Restart the listener with backoff for transient failures and only stop after repeated failures, telling the GM.
- **Severity:** Low

### 5.12 Two open TODOs on user-data paths
- **Location:** `Modules/CharacterRPG/Controller/EditController+Repair.swift:178`; `Modules/CharacterRPG/View/DetailEditorView.swift:14-15`
- **What:** (1) "confirm this should stay visible when ungrouped" is an undecided rule in a repair routine that sets `displayState = 0` for an ownerless group item; (2) "`.task` swallows updates further down, causing a double creation on start — accepted for now". Both cite a stale `CODE_AUDIT_Character §9.16` reference.
- **Why:** An undecided product rule runs on user data, and the second is a known double initialization.
- **Action:** Decide (1) and encode it in a named constant or test; fix or file (2) and drop the stale references.
- **Severity:** Low

---

## 6. Security

### 6.1 LevelDB block decode has quadratic memory and CPU
- **Location:** `Modules/CoreRPG/Foundry/FoundryLevelDBReader.swift:171-215` (`decodeEntries`, esp. 203-206); `:41` (`[UInt8](data)`); limit default at `Modules/CoreRPG/Foundry/FoundryRuleModels.swift:740`
- **What:** Key prefix sharing lets `sharedLength` equal `previousKey.count`, so each entry builds a full-length key array (`Array(previousKey.prefix(...))` plus the suffix) and stores it. Only the entry count (100,000) is capped; key length and cumulative key bytes are not, and the `maximumRuleDataSize` budget counts only raw block bytes.
- **Why:** A crafted compendium has a ~400 KB block of 100k entries with `shared=k, unshared=1, value=0` (about 4 bytes each). Key i has length i, so about 5 GB is allocated and copied. The CRC32C block checksum is attacker-computable. The app is jetsam-killed or hangs on import, and `records(in:)` also copies the whole table (up to 512 MB) into `[UInt8]`.
- **Action:** Cap the reconstructed key length (a few KB) and the cumulative decoded key+value bytes against `limits`, reject entries whose shared+unshared length exceeds the cap, and parse from `Data` or a mapped buffer instead of `[UInt8](data)`.
- **Severity:** High **[verified]**

### 6.2 Inbound LAN connections have no handshake deadline
- **Location:** `Modules/GameRPG/Network/ConnectionThrottleTracker.swift:30-43,48-51`; `Modules/GameRPG/Master/MasterNetworkController.swift:196-220`; `Modules/GameRPG/Network/ConnectionController.swift:108-122`; `Modules/GameRPG/Network/ConnectionAttemptThrottle.swift:87-92`
- **What:** `CODE_AUDIT_15` capped pending handshakes at 16 total and 3 per source, plus 32 connections. A slot is released only by `.ready`, `.failed`, `.cancelled` or `lostConnection`; nothing times out an inbound connection stuck in `.preparing`/`.waiting` (a repository search for a handshake or connection timeout found none).
- **Why:** One host opens 3 idle sockets from each of about 6 source addresses (the throttle key is the host string). Every later legitimate join is then refused by `shouldAllow` or the 32-connection guard with no error shown to the player, until the GM restarts streaming.
- **Action:** Add a server-side handshake deadline (about 10-15 s) that cancels the connection and clears its `pendingSources` entry.
- **Severity:** High

### 6.3 Inbound message pipeline bounds message count, not bytes
- **Location:** `Modules/GameRPG/Model/GameMessagePipeline.swift:127-146`; `Modules/GameRPG/Model/GameLimits.swift:9`; `Modules/GameRPG/Network/GameProtocol.swift:41,100-111`
- **What:** `maximumQueuedMessages = 128` counts events, while each retains a decoded `GameNetworkModel` and one frame may be up to 512,000,000 bytes. Outbound SharePlay has a byte budget; the LAN inbound queue does not. Related to the deferred LAN frame cap (`CODE_AUDIT_15` §6.4) but a separate missing bound.
- **Why:** An authenticated player streaming a few hundred-MB messages with distinct counters passes dedup and pushes memory into the GB range, killing the GM app mid-session.
- **Action:** Add a cumulative queued-byte budget (and per-connection budget) at admission and drop or reject when exceeded.
- **Severity:** Medium

### 6.4 SharePlay package receiver quotas are global, not per participant
- **Location:** `Modules/GameRPG/SharePlay/SharePlayPackageReceiver.swift:35-40,118-130,195-231`
- **What:** `maxIncompleteStreams` (64) and the byte budget are shared by all participants, and making room evicts the globally least-recently-active stream.
- **Why:** One participant opens 65 tiny partial streams and evicts every other participant's in-progress chunked transfer, including the master's map or photo packages, which then expire silently with no retry (`CODE_AUDIT_Network` §5.2).
- **Action:** Apply per-source stream and byte quotas and evict within the offending source first.
- **Severity:** Medium

### 6.5 The TLS-PSK join code is recoverable from one passively captured handshake
- **Location:** `Modules/GameRPG/Network/NWParameter+GameMaster.swift:53-83`; `Modules/GameRPG/Network/ConnectionAttemptThrottle.swift:19-79`
- **What:** The PSK is `HMAC(code, "GameMaster")` under `TLS_PSK_WITH_AES_128_GCM_SHA256`, a plain PSK suite with no ephemeral key exchange and a constant identity. The throttle limits only online guessing and is bypassed by rotating source addresses (256 tracked).
- **Why:** An attacker who records one handshake on shared Wi-Fi can brute-force the 4-digit code offline (10^4 candidates), decrypt the recorded session (no forward secrecy) and join.
- **Action:** Treat this as part of the deferred `CODE_AUDIT_15` §6.1 product decision: either a longer code or a PSK suite with ephemeral key exchange or a password-authenticated key exchange.
- **Severity:** Medium

### 6.6 Share extension: text and URL downloads have weaker caps than image loads
- **Location:** `Sources/RPGShare/ItemProviderImporter.swift:154-165,206-216,262-275`
- **What:** Shared text via `.text`/`.data` is returned uncapped; `URLSession.shared.download(from:)` has no byte limit and the size check runs after the full download; any http(s) URL is fetched, including LAN and loopback targets.
- **Why:** A very large text share or a hostile URL serving gigabytes exhausts the extension's ~120 MB budget and the extension is terminated, losing the share. It is user-initiated, so risk is low.
- **Action:** Cap text at load, use a delegate-based download that aborts above the limit, and allow only public https hosts.
- **Severity:** Low

### 6.7 Device and GM names are logged with `privacy: .public`
- **Location:** `Modules/GameRPG/Network/GameNetworkController.swift:84,109,130,142,148,165`; `Modules/GameRPG/Network/ListenerManager.swift:48,54,193,196`
- **What:** The user's device or game name (often a real name, since it is the Bonjour service name) is logged public; `CODE_AUDIT_15` §6.5 fixed item content only.
- **Why:** Names appear unredacted in sysdiagnose and in Console on a paired device.
- **Action:** Use `.private` for names.
- **Severity:** Low

### 6.8 Entitlements and ATS hygiene (recorded so it is not re-audited)
- **Location:** `Resources/MasterRPG-Release.entitlements`, `Resources/MasterRPG-Debug.entitlements`, `Resources/Info.plist`, `Sources/RPGShare/RPGShare-Release.entitlements`
- **What:** No hardcoded secrets or keys were found, `NSAllowsArbitraryLoads` is false with no ATS exceptions, and the `RPG://` scheme only navigates. The macOS-only `com.apple.security.device.audio-input` key sits in the iOS entitlements files (harmless). macOS sandboxing comes only from `ENABLE_APP_SANDBOX = YES` in the project, not from the entitlements files.
- **Why:** No exploitable issue found; a project-setting change could silently drop the sandbox.
- **Action:** Also declare the sandbox in the macOS entitlements file.
- **Severity:** Low

---

## 7. Performance

### 7.1 Foundry WAL/manifest fragment assembly copies the accumulated record per fragment
- **Location:** `Modules/CoreRPG/Foundry/FoundryLevelDBWriteAheadLogReader.swift:87-104,128-136`; whole-file copy at `:23`
- **What:** `guard var value = fragmented` binds a second reference while `fragmented` is still live, so `value.append` copies the whole accumulated buffer for each 32 KB fragment before `fragmented = value` reassigns it.
- **Why:** A 200 MB logical record needs about 6,000 fragments averaging 100 MB copies (~600 GB of memcpy), and cancellation is checked only per physical record, so the import UI appears hung.
- **Action:** Append in place (`fragmented?.append` or a swap/take pattern) so the buffer stays uniquely referenced.
- **Severity:** Medium

### 7.2 Hex-grid maps regenerate tens of thousands of entries per slider tick and create one RealityKit entity per hex
- **Location:** `Modules/MapRPG/Map/MapHexGridGeometry.swift:23-56`; `Modules/MapRPG/Map/MapEditController+HexGrid.swift:18-52`; `Modules/MapRPG/Controller/EditController.swift:365-370`; `Modules/GameRPG/Table3D/GameTableProjection.swift:106-135`; `Modules/GameRPG/Table3D/GameTableEntities.swift:315-347`; `Modules/GameRPG/Table3D/GameTableModel+MapSync.swift:240-256`
- **What:** `grid(for:in:)` builds a `MapEntryModel` (UUID, name, 6 points) per cell, `updateHexScale` regenerates the whole grid on every slider change on the main actor, and `syncRooms` creates a `RoomHitArea` (collision hull, input target, hover effect, accessibility component) for every entry including hex cells; `renderSignature` hashes every entry's coordinates on each sync.
- **Why:** An 8000×8000 px map at hex size 20 has about 61k cells: 61k models per slider tick, 61k RealityKit entities when the 3D table opens, and 366k points rehashed on every pin update. The UI stalls and can be killed.
- **Action:** Exclude hex-grid entries from room hit volumes (or use an analytic hit test), debounce or commit grid regeneration off the main actor, and compute the render signature incrementally or from a per-map version.
- **Severity:** Medium

---

## 8. SwiftUI / UI

### 8.1 SwiftUI correctness checklist: clean
_No findings._ Greps over `Modules/` and `Sources/` returned: 1 non-`private` `@State` (`Modules/PhotoRPG/Photo/ImageViewer.swift:19`, a documented exception for the gesture extension in another file); 0 non-`private` `@FocusState`; 0 `ForEach` over `.indices`/`\.offset`; 0 `.animation(_:)` without `value:`; 1 `onTapGesture` (`Modules/CoreRPG/Inspector/InspectorRowView.swift:74`, needs `count: 2`, allowed); 0 `sorted`/`filter` in view bodies of the sampled view folders (only two model-level `filter(searchText:)` calls); 36 `Equatable` leaf views. The `@State` initializers assigned in `init` (`SingleReviewLinkText.swift:9`, `InlineEditorView.swift:14`, `LinkItemListView.swift:19`, `ExportProgressPanelView.swift:16`, `QuickLinkEditor.swift:16`) are either owned-model creation or follow an `onChange` re-sync (as in `SingleReviewLinkText`), so they do not ignore parameter updates. Only 1 non-`body` computed `some View` property exists, so the "no computed-property views" rule is followed. `AnyView` is the exception (§4.1).

### 8.2 Fixed-width frames may not scale with Dynamic Type
- **Location:** 93 occurrences of `.frame(width: <number>` across `Modules/` and `Sources/` (not sampled individually; use `grep -rn "frame(width: [0-9]"`)
- **What:** Numeric fixed widths are used in toolbar, row and overlay views; `CLAUDE.md` asks for Dynamic Type and to avoid hard-coded layout values.
- **Why:** Fixed widths clip or truncate larger text sizes, especially in overlays and list rows on iPhone and Apple TV.
- **Action:** Review each site for text-bearing content and replace with `ScaledMetric`, `containerRelativeFrame`, or flexible frames where the frame surrounds text.
- **Severity:** Low (candidate list only; no site was verified as a defect)

### 8.3 Accessibility coverage is unverified for icon-only controls
- **Location:** repository-wide: 586 `Image(systemName:)` uses versus 186 `accessibilityLabel`, 42 `accessibilityElement` and 35 `accessibilityHint` calls
- **What:** The counts do not prove a gap (many symbols sit inside `Button(_, systemImage:)`, `Label` or decorative contexts), but they leave no basis to say coverage is complete.
- **Why:** Unlabelled icon-only controls are unusable with VoiceOver, and App Review looks at accessibility.
- **Action:** Run an Accessibility Inspector pass on the game screen, map editor and list toolbars, and grep specifically for `Image(systemName:)` outside `Label`/`Button` title initializers.
- **Severity:** Low (not assessed in depth)

---

## 9. Dead code / duplication / refactor

### 9.1 Files and types that nothing references (~430 LOC), including three `CODE_AUDIT_15` §13 said were "still used"
- **Location:** `Modules/GameRPG/GameViews/PlayerConnectionStatusView.swift:1-33`; `Modules/CoreRPG/Sheet/InlineSheetSearchControl.swift:1-114`; `Modules/CoreRPG/Views/InspectorUnavailableView.swift:1-21`; `Modules/CoreRPG/ItemList/ScreenSizeModel.swift:1-14`; `Modules/CoreRPG/ViewModifiers/VerticalLabelStyle.swift:1-18`; `Modules/CoreRPG/ViewModifiers/TabBarMinimizeBehavior26.swift:1-79`; `Modules/GameRPG/GameViews/GameOverlayTabViewModifier.swift:1-21`; `Modules/CoreRPG/ViewModifiers/SheetFullScreenModifier.swift:5-9,52-82`; `Modules/CoreRPG/Text/OnboardingEmphasisAttribute.swift:7-88,95-120`
- **What:** Word-boundary greps over Modules, Sources and Tests show each name only in its own file (previews aside). `tabBarMinimizeBehavior26` and `backgroundExtensionEffect26` have one hit each (the declaration); `gameOverlayTabBarView` appears only in two commented-out calls; `sheetFullScreen` only at its declaration (`sizedSheet` in the same file is live). `OnboardingAppearanceEffectRenderer` and `OnboardingTextTransition` are referenced only by a commented line at `Modules/CoreRPG/LinkRenderer/LinkHighlightTextView.swift:29`. `TabBarMinimizeBehavior26`, `GameOverlayTabViewModifier` and `SheetFullScreenModifier` are the same three `CODE_AUDIT_15` §13 §9.4 kept as "still used".
- **Why:** Compiled and maintained dead code, and it contradicts the previous remediation note.
- **Action:** Delete the files and ranges (including generated snapshot roots) and rebuild on all four platforms.
- **Severity:** Medium (~430 LOC removed) **[verified by grep]**

### 9.2 About 45 unreferenced members that `CODE_AUDIT_15` §9.4/§9.7 left in live files
- **Location:** e.g. `Modules/CoreRPG/App/PlatformModifiers.swift:15,23,80,89,98`; `Modules/CoreRPG/Platform/ToolbarSecondaryPlacement.swift:16,24,33`; `Modules/CoreRPG/Extensions/PlatformHelpers.swift:23,41,50`; `Modules/CoreRPG/Navigator/Core/Navigator.swift:190,310,323`; `Modules/CoreRPG/Files/FileUrlViewModel.swift:31,35,41,46`; `Modules/CoreRPG/Model/ItemListable.swift:43,47,51`; `Modules/CoreRPG/Sheet/SheetModel.swift:68,70,179`; `Modules/CoreRPG/Fake/TestFixtures.swift` (whole file); `Modules/GameRPG/GameViews/GameScreenModel.swift:64,85,86`; `Modules/DiceRPG/Model/DiceModel.swift:334,339`; `Modules/MapRPG/Controller/EditController.swift:14,15`; `Modules/RuleRPG/Resources/Localization+Extensions.swift:5-13` (whole file); `Modules/RolePlayGameKit/Model/AppModel.swift:588`; and ~25 more listed by the agent in the same modules (CoreRPG, GameRPG, DiceRPG, MapRPG, PdfRPG, SpaceRPG, GeneratorRPG)
- **What:** Each name returns exactly one word-boundary match repo-wide, its declaration, so none is a protocol witness. Not checked: `#selector`, string-based lookup and Xcode previews.
- **Why:** Inflated, mostly public API surface that misleads readers; `CODE_AUDIT_15` §13 states "dead functions inside live files were not pruned".
- **Action:** Delete them in one pass and let the compiler catch anything missed.
- **Severity:** Low

### 9.3 Symbols used only by tests
- **Location:** `Modules/CoreRPG/Sheet/SheetSearchContext.swift:12` (whole class); `Modules/GameRPG/Model/GameNetworkModelV1.swift:36-60,94-101`; `Modules/CoreRPG/Fake/TestFixtures.swift:50,53,56`; `Modules/CoreRPG/Import/ExternalImport.swift:195`; `Modules/CoreRPG/Import/ExternalImportSourceRegistry.swift:222`; `Modules/CoreRPG/Links/LinkRegisterController.swift:87`; `Modules/CoreRPG/Sheet/SheetRootModel+Selection.swift:90`; `Modules/DiceRPG/Controller/ViewController.swift:87,109`; `Modules/AdventureRPG/Controller/EditController.swift:352`; `Modules/AudioRPG/Controller/ViewController.swift:67`; `Modules/GameRPG/Table3D/GameTableModel+ToolBar.swift:101,123`; `Modules/GameRPG/SharePlay/SharePlaySingleQueuePackageSender.swift:79`; `Modules/GeneratorRPG/BasicAI/Engine/FoundationModelInputLimiter.swift:52`; `Modules/CharacterRPG/Model/ValueModel.swift:119`; `Modules/MapRPG/Map/NeedleMapPin.swift:135`; `Modules/CoreRPG/Tips/MasterRPGTips.swift:48-76`
- **What:** One production hit (the declaration) and at least one in `Tests/`.
- **Why:** Production code carried only to satisfy tests.
- **Action:** Delete the symbol and its test unless the test guards behavior that lives elsewhere (then repoint it). Confirm the `MasterRPGTips.shouldShow*` group is not consumed indirectly by TipKit `rules` before deleting.
- **Severity:** Low

### 9.4 Legacy live-`Model` overloads in `CoreDataController` are dead and would touch `@MainActor` models on the Core Data queue
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:93-135` (`fetch(mapper:)`, `replace(uuid:with:)`), `:137-150` (`queueReplace(uuid:with:)`), `:323-345` (`batchReplace(models:)`), `:374-390` (`processBatchChunk`)
- **What:** All 12 modules use the `CoreDataSnapshotPersistable` snapshot path, and a repo-wide grep finds no callers of these overloads. They pass `@MainActor` model instances into `context.perform` closures typed `@Sendable`.
- **Why:** Because `@MainActor` classes are implicitly `Sendable`, a future caller compiles cleanly and then reads main-actor state off the context queue or traps in a nonisolated shim.
- **Action:** Delete the legacy overloads, or restrict them to `Sendable` value snapshots.
- **Severity:** Low

### 9.5 `Bundle.decode` is unreferenced and holds all seven `fatalError`s
- **Location:** `Modules/CoreRPG/Extensions/Bundle+decode.swift:1-39` (fatalErrors at 8,12,22,24,26,28,30; `BundleDecodeError` at 36)
- **What:** Nothing in Modules, Sources or Tests calls `Bundle.decode(_:from:)` or `BundleDecodeError`.
- **Why:** Unreachable today; a future caller with a missing or bad resource would crash on launch.
- **Action:** Delete it (or make it `throws`).
- **Severity:** Low **[verified by grep]**

### 9.6 Commented-out code blocks
- **Location:** `Modules/RolePlayGameKit/View/ExtendedTabBar.swift:121-131` (disabled `changeNavigation`, no references); single-line commented calls at `Modules/CoreRPG/LinkRenderer/LinkHighlightTextView.swift:29`, `Modules/CoreRPG/LGViews/HeaderFooterContentScrollView.swift:34,163,184`, `Modules/CoreRPG/ItemDetail/ItemEditorForegroundView.swift:83`, `Modules/CoreRPG/LGViewModifiers/ToolbarItemListViewModifier.swift:207`, `Modules/CoreRPG/Debug/RainbowDebug.swift:23`, `Modules/GameRPG/GameViews/OnlyPlayerGameView.swift:22`, `Modules/GameRPG/GameViews/OnlyGameView.swift:23`, `Modules/GeneratorRPG/Controller/GeneratorController.swift:321`, `Modules/GeneratorRPG/Controller/AdventureGeneratorController.swift:220`, `Modules/MapRPG/Map/EditMapToolBar.swift:137`, `Modules/PhotoRPG/Model/DataModel+Extensions.swift:26`, `Sources/DiceRollerWidget/DiceRollerWidgetConfiguration.swift:86`
- **What:** There is no `#if false` or `#if 0` anywhere; the only 3+ line commented-out code block is `ExtendedTabBar.swift:121-131`. Other long `//` runs are prose, and `SpaceRPG/Record/*.swift` headers are Apple sample-code licenses.
- **Why:** Dead text suggests features are still wired up (`.gameOverlayTabBarView`, `OnboardingTextTransition`).
- **Action:** Delete the lines; where a comment records a decision (e.g. the `.popoverTip` at `ToolbarItemListViewModifier.swift:207`), turn it into a sentence.
- **Severity:** Low

### 9.7 Per-module boilerplate that is identical after a name swap (new counts for deferred §9.11/§9.14)
- **Locations (LOC per file × module count):** `Modules/*/Resources/BundleModule.swift` 13 × 14; `Modules/*/Controller/SyncDataController.swift` 20 × 12; `Modules/*/Root/LinkRootView.swift` 19 × 12; `Modules/*/Root/DetailRootView.swift` ~24 × 12; `Modules/*/Route/DetailRoute.swift` 55 × 9 (Space and Map identical to Photo; `init?(rawValue:)` split logic at about lines 14-33 in each); `Modules/*/Route/<Module>Route.swift` ~67 × 11; `Modules/*/Menu/<Module>Commands.swift` 24 × 11; `Modules/*/Root/<Module>RootView.swift` 34 × 8; `Modules/*/Controller/FolderListController.swift` 30 × 12; `Modules/*/Intent/Open<Module>Intent.swift` ~57 × 11; `Modules/*/Controller/SheetController.swift` ~28 × 4; `Modules/*/Controller/ViewController.swift`
- **What:** About 2,900 LOC of the ~7,000 across these families differ only in the module name (Rule is the usual outlier, e.g. `Bundle.ruleModule` versus `Bundle.module` in the other 13).
- **Why:** A change to routing, `Resources` or command wiring must be repeated in 9-14 files; diffs show the copies otherwise move in lockstep.
- **Action:** One generic `DetailRoute<Root>`, one `FolderListController` generic over the route namespace, one `SyncDataController<Entity>`, one `LinkRootView<Root>`, and emit `BundleModule.swift` from a template. Order: Bundle/Localization first, then routes.
- **Severity:** Medium

### 9.8 Core Data snapshot mapping and Spotlight `attributeSet()` are copied per module
- **Location:** `mapSnapshot`/`applySnapshot`/`makeModel`/`makeSnapshot`/`map(_:)` at `Modules/{Audio,Photo,Space}RPG/Controller/DataController.swift:21-88` (Photo vs Space differ in 8 of 88 lines); `attributeSet()` in 20 implementations in `Modules/{Adventure,Audio,Character,Dice,Generator,Map,Pdf,Photo,Rule,Space,Table,Weather}RPG/Model/DataModel+Extensions.swift`
- **What:** `attributeSet()` repeats the same 15-line tag loop in 11 files, differing only in `contentType` and which field feeds `textContent`; the snapshot mappers share most common-field code.
- **Why:** A change to Spotlight indexing touches 12 files (`//attributeSet.thumbnailData =` is already a stale line at `PhotoRPG/Model/DataModel+Extensions.swift:26`).
- **Action:** A CoreRPG `makeSpotlightAttributes(id:name:text:tags:contentType:)` helper plus a shared common-field mapper (the deferred §9.12).
- **Severity:** Medium (about 300 LOC for Spotlight, 700 for snapshot mappers)

### 9.9 Master/Player Photo, Pdf and Space handlers and per-module sequence trackers (deferred §9.9, with concrete detail)
- **Location:** `Modules/GameRPG/Controller/MasterController+PhotoMessages.swift:20,154` vs `+PdfMessages.swift:20,154`; `+SpaceMessages.swift:20,206`; `PlayerController+Photo.swift:15,122,137,176,207` vs `PlayerController+Pdf.swift:15,129,144,179,206` and `PlayerController+Space.swift:21,174,189,224,300`; `Modules/GameRPG/Controller/PlayerControllerModel.swift:235-421`
- **What:** The Master Photo and Pdf files are 169 lines each and differ in 32 changed lines after substitution; `PlayerControllerModel` carries four parallel blocks (`canApply<X>List`, `record<X>List`, `hasAuthoritative<X>List`, `defer<X>Reveal`, `deferred<X>Reveals`, `removeDeferred<X>Reveal(s)`, `reset<X>ListSequence`) for Audio (235-248), Photo (250-308), Pdf (310-365) and Space (367-421), the last three identical modulo name.
- **Why:** This is network-message handling with a history of lost-message bugs; a fix to reveal/defer logic must be repeated by hand three or four times.
- **Action:** One `ListSequenceTracker` value type instantiated per module (keyed by `NetworkModules`) and one generic file-module handler parameterised by feature flag and availability check.
- **Severity:** Medium

### 9.10 Five identical PDF-export `Transferable` blocks with drifted error handling and localization
- **Location:** `Modules/{Weather:62-96, Adventure:62-98, Character:60-94, Map:60-84, Table:60-84}RPG/Intent/*Entity.swift`; plain-text `DataRepresentation` in 10 Entity files (e.g. `PdfRPG` :82, `DiceRPG` :92, `TableRPG` :85)
- **What:** All five render `VStack{Text(name); Text(description)}` with `ImageRenderer` at width 600 and write with `CGContext(url as CFURL, ...)` into `URL.cachesDirectory` (name-based in most, `item.id` in Adventure and Character). Only `WeatherEntity` checks the write (`didWritePdf`, a localized error); the Map entity returns a non-existent file URL if `CGContext` creation fails, and English `"Name:"`/`"Description:"` are hard-coded in most.
- **Why:** Drifted behavior in user-visible sharing and Shortcuts output; the filename comes from a user-chosen item name.
- **Action:** One CoreRPG `renderSummaryPdf(title:description:) throws -> URL` with the write check and a sanitized filename, and one shared plain-text formatter.
- **Severity:** Medium

### 9.11 `NSFileCoordinator` wrappers: four copies of the same 12-line tail
- **Location:** `Modules/CoreRPG/Files/FileManager+Coordination.swift:121-137,139-155,157-175,177-195` (`execute` variants at 115 and 197); limiter release on two paths at about 103-113
- **What:** Each `coordinate(...)` declares the same `coordinatorError`/`result` variables and repeats the same `guard let result else { throw CocoaError(.fileReadUnknown) }` with an identical 5-line comment.
- **Why:** About 50 duplicated LOC in the file-safety layer.
- **Action:** A private generic helper taking a closure that receives the `error:` pointer and a result sink, and a helper wrapping limiter acquire/release.
- **Severity:** Low

### 9.12 Hand-rolled security-scoped access remains at 11 sites next to the shared helper
- **Location:** `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:22,73`; `FoundryVTTImportReader.swift:29,91,195`; `UniversalVTTReader.swift:166,188`; `Modules/CoreRPG/Import/ExternalImportSourceRegistry.swift:601`; `Modules/CoreRPG/Files/FileUrlDataController.swift:151`; `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:97`; `Modules/SpaceRPG/Space/SpaceViewer.swift:501`; `Modules/RolePlayGameKit/Model/AppModel.swift:441,462`
- **What:** `SecurityScopedAccess` (`Modules/CoreRPG/Files/SecurityScopedAccess.swift`) already has 14 call sites; these 11 still call `startAccessingSecurityScopedResource` with a manual `defer`.
- **Why:** Two idioms for one rule, and `CODE_AUDIT_15` §9.17 identified unbalanced sites as a latent bug.
- **Action:** Migrate them to `startSecurityScopedAccess()`, and store the `SecurityScopedAccess` value in `AppModel` instead of the raw URL.
- **Severity:** Low

### 9.13 Localization and bundle helpers are duplicated per module
- **Location:** `Bundle.localizedString(forKey:)` and `String.localizedString` in `Modules/{Audio,Pdf,Weather,Map,Space,Table,Character,Rule,Generator,Adventure}RPG/Resources/Localization+Extensions.swift` and `Modules/GameRPG/Model/Localization+Extensions.swift` (11 × ~15 lines); `Modules/CoreRPG/Extensions/LocalizedStringKey+String.swift:12`; the 14 `BundleModule.swift` files
- **What:** Photo and Dice have no such file, Rule's copy is dead (§9.2), Rule alone uses `Bundle.ruleModule`, and GameRPG keeps its file in `Model/` rather than `Resources/`.
- **Why:** Three placements and two bundle idioms for one convention; `String.localizedString` collides in name with CoreRPG's version, so a wrong-bundle lookup fails silently.
- **Action:** Put `Bundle.localizedString(forKey:)` once in CoreRPG, make each module's extension a one-liner, and align Rule's `BundleModule`.
- **Severity:** Low

### 9.14 JSON encode/decode helpers exist in six shapes
- **Location:** `Modules/CoreRPG/Extensions/JSONCoding.swift:11-14` (4 users); `Modules/CoreRPG/Model/JSONString.swift:6-22`; `Model/MessageMapper.swift:19-27`; `Files/FileDataController.swift:63-77`; `Import/ExternalImportSourceRegistry.swift:255-273`; `Persistence/FilePersistenceController.swift:48,111`; `Modules/DiceRPG/Widget/DiceConfiguration.swift:29-38`; `Modules/CoreRPG/Widget/ContentWidgetSnapshot.swift:34-56`; `Sources/DiceRollerWidget/DiceRollerView.swift:150-159`
- **What:** App Group `UserDefaults` JSON load/save is implemented separately in three widget-related files, and 21 other files allocate `JSONEncoder()`/`JSONDecoder()` inline; only `ExternalImportSourceRegistry` sets an `.iso8601` date strategy.
- **Why:** Not a performance problem, but inconsistent date and key strategies are easy to get wrong.
- **Action:** Extend `JSONCoding` with `string(from:)`/`value(from:)` and add one CoreRPG `AppGroupCodableStore` that the three widget sites reuse; do not sweep the inline allocations.
- **Severity:** Low

### 9.15 Small copy-paste helpers
- **Location:** near-identical `ExtractToolBarButton` at `Modules/AdventureRPG/View/AdventureExtractToolBarButton.swift:1-29`, `Modules/PdfRPG/View/DetailEditorToolBarButtons.swift:13-33`, `Modules/MapRPG/View/MapDetailToolBarButtons.swift:1-32`, `Modules/TableRPG/View/DetailEditorToolBarButtons.swift:1-34`; `private extension UUID { static func fixture }` in `Modules/{Pdf:143-149, Photo:210-216, Map:357-363, Space:145-151, Table:344-350}RPG/Model/PreviewData.swift`; ImageIO thumbnail options at `Modules/CoreRPG/Extensions/Image+AKImage.swift:190-197` and `Sources/RPGShare/ItemProviderImporter.swift:167-175`
- **What:** Verbatim copies differing only in a route case or size constant.
- **Why:** Small but constant drift.
- **Action:** A generic `ExtractToolBarButton(route:isDisabled:)` in CoreRPG, one shared preview `UUID.fixture`, and a shared ImageIO helper if RPGShare can link CoreRPG.
- **Severity:** Low

### 9.16 Oversized files (31 non-test files exceed 500 lines); proposed splits for the top 10
- **`Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift` (1313)** — keep the public reader (6-241) and mutation helpers (242-277); move the decoder (280-461), collection spec (462-657), document decoder (658-891), type inference (892-1017), embedded extraction (1018-1139) and JSON/validation/statistics helpers (1140-1313) into their own files. Severity: Medium.
- **`Modules/SpaceRPG/Space/SpaceViewer.swift` (1119)** — `+ImmersiveSync` (195-365), `+Handoff` (366-819, including `loadEntity` 479-710), and the extracted subviews (820-end). Severity: Medium.
- **`Modules/GameRPG/Controller/PlayerControllerModel.swift` (1065)** — `+ListSequencing` (235-417), `+MapSequencing` (430-560 and 736-957), `+Presentation` (560-732); keep counters/participant at 166-233. Severity: Medium.
- **`Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift` (939)** — break `sendData` (24-306) into phase helpers and move receive code to `+ChunkedReceive.swift`. Severity: Medium.
- **`Modules/GameRPG/SharePlay/RPGSharePlayController.swift` (929)** — lines 48-646 are 25 support types; split into session lifecycle (55-230), coordinators (230-395), journal tracker (395-547) and map-recovery tracker (547-646), leaving the controller at 647-929. Severity: Medium.
- **`Modules/CoreRPG/Controllable/ImportControllable.swift` (861)** — `ImportState` (7-107), `+ReviewDiff` (511-639), `+FileHandling` (640-782), `InputStream+Reading` (783-861). Severity: Medium.
- **`Modules/CoreRPG/Foundry/FoundryRuleModels.swift` (829)** — JSON value (10-198), manifests (199-321), resources (322-390), rules/effects (391-697), diagnostics/limits/errors (698-829). Severity: Medium.
- **`Modules/CoreRPG/Controllable/EditControllable.swift` (804)** — `+Menu` (417-586), `+Files` (600-690), `+Maintenance` (691-763), `+UndoRedo` (764-804), `+Folder` (268-383). Severity: Medium.
- **`Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift` (738)** — `+Localization` (338-376), `+Manifest` (377-448), `+Template` (449-529), reference decoder (530-654), utilities (655-738). Severity: Low.
- **`Modules/RolePlayGameKit/Import/Foundry/FoundryImportView.swift` (720)** — its 9 private subview structs (at 173, 202, 272, 330, 395, 445, 562, 595, 650) into their own files. Severity: Low.
- Also `Modules/CoreRPG/Files/FileUrlDataController.swift` (702: `+RemoteCache` 577-702, `+FileManagement` 494-576) and `Modules/DiceRPG/Model/DiceModel.swift` (691: `+Options` 128-318, `+Diff` 406-506, `+Codable` 623-680). Severity: Low.
- **Why (all):** Reviewability, and the network files in this list are where the audit history shows lost-message bugs. **Action:** Mechanical extraction along the boundaries above with no behavior change.

### 9.17 Functions over 150 lines (16 found)
- **Location:** `Modules/GameRPG/Controller/PlayerController+Map.swift:20` `handleMap` (313); `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:24` `sendData` (282); `RPGSharePlayController+SessionLifecycle.swift:175` `configureGroupSession` (252); `Modules/GameRPG/Table3D/GameTableView+VisionOS.swift:41` `body` (248); `Modules/CoreRPG/Import/ExternalImportReviewSession.swift:95` `commit` (239); `Modules/SpaceRPG/Space/SpaceViewer.swift:479` `loadEntity` (231); `Modules/MapRPG/Map/EditMapToolBar.swift:30` `body` (223); `Modules/CoreRPG/Foundry/FoundryVTTBridgeDecoding.swift:205` `decodeContents` (196); `Modules/GameRPG/Controller/MasterController+SpaceMessages.swift:20` `handleSpace` (185); `Modules/GameRPG/Network/GameNetworkController+SharePlayDelegate.swift:89` `routeSharePlayUpdate` (181); `Modules/RolePlayGameKit/View/SettingsView.swift:41` `body` (172); `Sources/MasterRPG/Window/WindowUtilityList.swift:17` `body` (171); `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:74` `body` (163); `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:143` `readSynchronously` (161); `Modules/RolePlayGameKit/Model/AppModel.swift:124` `init` (156); `Modules/GameRPG/Controller/PlayerController+Space.swift:21` `handleSpace` (152); `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift:30` `body` (150)
- **What:** Brace-matched lengths (approximate).
- **Why:** The network handlers are hard to test and easy to break; the oversized `body`s defeat invalidation granularity.
- **Action:** Break handlers into named phases (validate, defer, apply, ack) and extract subviews from the oversized bodies.
- **Severity:** Medium

### 9.18 Misspelled and mixed-convention symbol names
- **Location:** `StoreManiplable` (protocol, 3 uses) at `Modules/CoreRPG/FileViews/SettingsView.swift:6`; `objectAttritube` at `Modules/CoreRPG/Persistence/RpgSpotlightIndexerDelegate.swift:46-47`; `endcoded` at `Modules/CoreRPG/App/ExportedRPGData.swift:126`; `LinkHighLightLocations.swift`, `LinkHighLightLocation`, `LinkExpandHighLightValues` (18 uses) versus `LinkHighlightTextModel`/`LinkHighlightTextView`; `IosAppDelegate`/`IosSceneDelegate` in files named `iOSAppDelegate.swift`/`iOSSceneDelegate.swift` versus `MacAppDelegate`; `prevMarkDown`/`newMarkDown`/`urlMarkDown`/`minimizeMarkDown` versus `Markdown`; `ToolBar` (34 identifiers) versus `Toolbar` (29), sometimes in the same module
- **What:** The earlier §9.23 typos are fixed; these remain. (The `Id`/`Url` casing is the project convention and is not flagged.)
- **Why:** Cosmetic, but public API and the `ToolBar`/`Toolbar` split hinders search.
- **Action:** Rename in one refactor commit.
- **Severity:** Low

### 9.19 Files whose name does not match the primary type, or in the wrong folder
- **Location:** `Modules/CoreRPG/FileViews/SettingsView.swift` (holds the `StoreManiplable` protocol; the real `SettingsView` is in `Modules/RolePlayGameKit/View/SettingsView.swift`); `Modules/CoreRPG/App/AppTabBarViewModifier.swift` (only `protocol AppRouter`); `Modules/CoreRPG/Menu/AppCommands.swift` (only `AltLinkWindowCommandView`); `Modules/CoreRPG/Links/QuickLinkConfig.swift` (`LinkEntryModel`); `Modules/CoreRPG/Buttons/RoundGlassButtonStyle.swift` (`SelectedRoundButtonViewModifier`); `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift` (`FoundryImportModel`); `Modules/GameRPG/Table3D/GameEquipment.swift` (a generic `struct Table: Tabletop` in a module beside `TableRPG`); `Modules/PdfRPG/Controller/EditController.swift` (`LinkPdfModuleTransferable` first); `Modules/GameRPG/Model/Localization+Extensions.swift` (others use `Resources/`); an empty `Modules/CoreRPG/Shaders/` folder
- **What:** 47 single-type files have a name that differs from their type; this is the confusing subset.
- **Why:** Navigation and code search.
- **Action:** Rename files to the primary type, move `StoreManiplable` to `CoreRPG/Stores`, and remove the empty `Shaders/` folder.
- **Severity:** Low

### 9.20 Magic constants worth naming
- **Location:** Foundry import byte limits `536_870_912` (three times), `1_073_741_824`, `67_108_864`, `100_000`, `400_000` at `Modules/CoreRPG/Foundry/FoundryRuleModels.swift:736-745`, `FoundryImportArchive.swift:120`, `FoundryVTTDomainMapper.swift:74`, `FoundryMediaNormalizer.swift:135`; `256_000_000` at `Modules/CoreRPG/Cache/ObjectCache.swift:20` and `Files/FileUrlDataController.swift:608`; `.seconds(120)` retention windows at `Modules/GameRPG/SharePlay/SharePlayPackageReceiver.swift:40`, `Network/SharePlayPlayerJournalAdmission.swift:141`, `Network/GameRelayAdmission.swift:39` (with `limit: 512`); `delayedTask(.milliseconds(100))` in six sites in `SheetRootModel+Reconcile.swift:35`, `SheetRootModel+ContextMenu.swift:144,164`, `EntryEditorHeaderView.swift:101`, `TextEditModel.swift:87,103`; retry-delay arrays and `metadataHeadroom = 1_000_000` at `Modules/GameRPG/SharePlay/SharePlayDeferredDeliveryQueue.swift:57,337-351`; `256_000`, `128_000_000`, `64_000_000` at `SharePlaySingleQueuePackageSender.swift:79-85`; the `de.andretrettin.` prefix in 30+ places under three spellings (`gamemaster`, `MasterRPG`, `masterrpg`); Bonjour service types at `Modules/GameRPG/Browser/GameServiceType.swift:35-41` (must match `NSBonjourServices`; nothing enforces it); a hard-coded GitHub URL at `Modules/CoreRPG/FileViews/ImportInformationSection.swift:9` and English `"Name:"`/`"Description:"` in 9 Entity files
- **What:** Where a named constant exists it is defined once but the values are repeated elsewhere.
- **Why:** If one 256 MB cap or 120 s window changes, the others silently diverge, and a typo in a Bonjour type or identifier breaks discovery with no compile error.
- **Action:** A `BundleIds` enum (or `Bundle.main.bundleIdentifier`), `FoundryImportLimits.standard`, an extended `GameLimits` for admission windows and send-queue caps, and `EditTiming.debounce` for the 100 ms delays.
- **Severity:** Low

### 9.21 `print()` and preview code in the release framework
- **Location:** `Modules/GeneratorRPG/View/PdfSummaryAnalysisView.swift:176` (inside a `#Preview` under `#if DEBUG`); `Modules/CoreRPG/Fake/PreviewFixtureLoader.swift:25` (inside `#if DEBUG` in a public function); doc-comment-only hits at `Modules/CoreRPG/ScenesManager/Modifiers/SceneTrackerModifier.swift:25,26,98,100` and `ScenesManager.swift:195,280`
- **What:** Only 2 real `print` calls exist, both under `#if DEBUG`, neither logs sensitive data. The public `PreviewFixtureLoader` and the `Fake/` folder still compile into the release framework.
- **Why:** Nothing ships or leaks; the only cost is preview code in the shipping binary.
- **Action:** Optionally switch to `Logger` and put the whole `Fake/` folder under `#if DEBUG`.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Make "untrusted numeric input" a first-class rule.** §5.1, §5.4, §5.5, §5.7 and §6.1 are the same defect: a decoded number reaches a trapping conversion, an unchecked arithmetic operation or an unbounded allocation. The earlier audits fixed individual sites (`Int16(clamping:)` in Adventure, count clamps in `RawDice`) but the pattern recurs in every module's `DataController`. Add one validation pass at decode for peer and file input (ranges for `displayState`, dice sides/modifier, entry counts, coordinates), ban plain `Int32(`/`Int16(` narrowing in `DataController` files via a lint or review rule, and add one fuzz-style test per module that feeds `Int.max`, `Double.greatestFiniteMagnitude` and negative values through `applySnapshot`.
2. **Give every long-lived network object an explicit lifetime owner.** §3.1, §3.2, §3.3, §3.8 and §3.20 all come from relying on `deinit` or "the next message" to clean up. A receive loop that holds `self` strongly cannot be released by dropping the reference, and a drain running in a peer's cancellable task cannot outlive that peer. Adopt one pattern: an owner-cancelled root task per connection plus a run-generation token checked after every await, as `ListenerManager` already does, and apply it to `BrowserManager`, the master connection list and the message pipeline drain.
3. **Bound every accumulator, not just its count.** §6.1 (key bytes), §6.3 (queued bytes), §6.4 (per-source streams) and §7.1 (fragment copies) show that entry-count caps leave memory unbounded. Introduce budgets in bytes at admission points and thread `GameLimits` and `FoundryImportLimits` through them.
4. **Finish moving persistence to a "database ready" model.** §5.3, §3.11, §3.12 and §3.13 all involve work that assumes `dataControllable` exists and that queued state is consistent across an `await`. An awaitable readiness gate plus single-`perform` check-and-apply would remove a family of silent-loss bugs.
5. **Finish the deferred boilerplate consolidation as one project.** §9.7-§9.9 are the same ~7,000 LOC noted in `CODE_AUDIT_15` §9.11/9.12/9.14. The agents' diffs show the copies move in lockstep, which makes a generic replacement low risk; doing it module by module leaves the protocol handlers (§9.9), which have the most bug history, for last.
6. **Keep the post-remediation audit loop honest.** §5.2 and §9.1 both re-open items that `CODE_AUDIT_15` marked Fixed or "still used". Each future remediation pass should include a regression test or a grep check for the specific claim (e.g. "no file named in §9.4 has zero references"), so a "Fixed" status can be trusted.

---

## 11. What was NOT audited

- **Verification scope.** Only the `MasterRPG` iOS scheme was built (clean, zero warnings). macOS, tvOS and visionOS builds, and the test suites, were not run. No finding was runtime-tested on a device or simulator, including §5.3 (background intents) and §3.4 (main-actor thumbnail decode, not profiled in Instruments).
- **Independently re-read by me:** §5.1, §5.2, §5.3, §5.4 (trapping lines), §6.1, §3.1, §3.2, §3.4 (path and build setting) and §9.1/§9.5 (greps). All other items rest on the auditing agent having read the cited code; their line numbers may drift.
- Algorithmic correctness of domain code (Foundry/LevelDB format semantics beyond the decoder bounds, dice-formula grammar, fog-of-war geometry, CRDT convergence proofs).
- Build settings, scheme configuration and Xcode project structure beyond confirming `SWIFT_APPROACHABLE_CONCURRENCY = YES` in all 8 configurations and the 26.0 deployment targets.
- Third-party dependency internals (SPM package `RPGTabletopGameContent` for visionOS 3D content is a black box).
- `Tests/` — read only to learn expected behavior; no coverage assessment. Test-only symbols are noted in §9.3.
- Snapshot roots under `Snapshots/` and the generated snapshot-test files (checked only for references to deleted code).
- The RPGShare and DiceRollerWidget extension targets got light coverage (§3.15, §6.6); their entitlements were opened (§6.8) but not compared against the App Group identifier beyond `group.de.andretrettin.MasterRPG`.
- Localization and string catalogs: only three untranslated or wrong-bundle strings were noted (§4.2); the ~250 stale keys already listed in `CODE_AUDIT_15` §8.5 were not re-audited.
- SwiftUI: the checklist greps (§8.1) cover the whole tree, but no `.trace`/Instruments session was recorded, so update-count and invalidation performance are unmeasured. Accessibility (§8.3) and fixed frames (§8.2) are candidate lists, not confirmed defects. Liquid Glass adoption was not assessed.
- Previously reported items in `CODE_AUDIT_15` §13 marked Fixed were not re-verified except where a finding explicitly re-opens one (§5.2, §5.5, §9.1).

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line. Each Critical/High finding has an exact line range.

- **§5.1** — open `Modules/CharacterRPG/Controller/DataController.swift`, lines `47` and `56`. Line 47 narrows with `Int32(snapshot.displayState)` and line 56 with `Int16(index)`; neither clamps. Then open `Modules/CharacterRPG/Model/ValueModel.swift`, line `50`, where `displayState` is decoded as a plain `Int` with no range check. Compare with `Modules/AdventureRPG/Controller/DataController.swift`, lines `96-97`, the only site that uses `Int16(clamping:)` and whose comment names the untrusted-import risk.
- **§5.2** — open `Modules/CoreRPG/CRDT/WallclockTimestamp.swift`, lines `26-32` and `42-50`. `now()` returns `last.nextUp` when `candidate <= last`, and `observe` sets `last` to any finite remote value; `nextUp` of `Double.greatestFiniteMagnitude` is `+inf`. Then `Modules/CoreRPG/CRDT/CRDT.swift`, lines `60-63` (`rawValue` returns `""` on encode failure) and `Modules/CoreRPG/Extensions/JSONCoding.swift`, line `12` (default `JSONEncoder`, which throws on infinity).
- **§5.3** — open `Modules/RolePlayGameKit/View/DatabaseInitializationView.swift`, lines `36-49` and `64-73` (both database setup and `setupRootModels` are `.task` modifiers), then `Modules/CoreRPG/Controllable/ItemControllable.swift`, line `391-393` (`try await dataControllable?.save()`, a no-op when nil) and `Modules/DiceRPG/Intent/DiceManagementIntents.swift`, line `12` (`.background` is a supported mode).
- **§5.4** — open `Modules/DiceRPG/Model/DiceModel.swift`, lines `349-353` (`Int(modifier)` at 351) and `355-364` (`Int(compareValue)` at 357 and `(1 ... number).map { die.duplicate() }` at 362).
- **§6.1** — open `Modules/CoreRPG/Foundry/FoundryLevelDBReader.swift`, lines `189-207`. The guard at `:189` allows `sharedLength` up to `previousKey.count`, line `203` builds a full-length copy of the previous key, and line `206` appends it to `entries`; the only limit is the entry count at `:207`, whose default is `100_000` (`FoundryRuleModels.swift:740`).
- **§6.2** — open `Modules/GameRPG/Network/ConnectionThrottleTracker.swift`, lines `30-51`: pending slots are released only through `register`/`resolve`/`clear`; a search for `handshakeTimeout`, `handshakeDeadline` and `connectionTimeout` under `Modules/GameRPG` returns nothing.
- **§3.1** — open `Modules/GameRPG/Master/MasterNetworkController.swift`, line `137` (`networkModel.connections = []` with no `cancel()`), then `Modules/GameRPG/Network/ConnectionController.swift`, lines `75-80` (the `deinit` that would cancel) and `222-224` (the receive `Task { [weak self] in guard let self ... await self.receiveLoop() }`, which keeps `self` alive for the whole loop).
- **§3.2** — open `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift`, lines `207-225` (requeue and `return` with no handoff) and compare `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift`, lines `503-514` (handoff `Task`) and `549-551` (`catch is CancellationError` with no handoff).
- **§3.4** — open `Modules/PhotoRPG/Controller/CacheController.swift`, lines `68-77` (`@MainActor` `downsampledSource` calling `resolvedImage`) and `Modules/PhotoRPG/Controller/FileUrlDataController+ImageResolve.swift`, lines `12-27` (plain `async` with synchronous `decodeData`/`decodeUrl` calls); confirm `grep -c "SWIFT_APPROACHABLE_CONCURRENCY = YES" MasterRPG.xcodeproj/project.pbxproj` returns `8`.
- **§9.1** — run `grep -rnw "tabBarMinimizeBehavior26\|gameOverlayTabBarView\|sheetFullScreen\|PlayerConnectionStatusView\|InlineSheetSearchControl\|InspectorUnavailableView\|ScreenSizeModel" Modules Sources Tests --include='*.swift'`; every hit is the declaration, its own preview, or a commented-out line (`OnlyPlayerGameView.swift:22`, `OnlyGameView.swift:23`).
- **§9.5** — run `grep -rn "BundleDecodeError\|Bundle.decode" Modules Sources Tests --include='*.swift'`; the only hit is the declaration at `Modules/CoreRPG/Extensions/Bundle+decode.swift:36`.

If any finding doesn't reproduce when you visit the line, ping me with the specific reference and I'll re-investigate.
