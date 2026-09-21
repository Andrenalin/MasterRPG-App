# MasterRPG Code Audit

Generated 2026-09-20. Scope: ~273,000 lines across 2,120 Swift files (no `.metal` sources exist) spanning targets **MasterRPG** (iOS/visionOS), **MasterMac**, **MasterTV**, **DiceRollerWidgetExtension**, **RPGShare**, and 15 shared framework modules (`AdventureRPG`, `AudioRPG`, `CharacterRPG`, `CoreRPG`, `DiceRPG`, `GameRPG`, `GeneratorRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `RolePlayGameKit`, `RuleRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG`). No archived/`Dead/` directories exist; `Snapshots/` (generated) and `Docu/` were excluded.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made. This is the fifteenth audit pass (see `Docu/CODE_AUDIT_1.md`–`_14.md` and the per-module audits). Items already open in `CODE_AUDIT_14.md`, `CODE_AUDIT_Network.md` and `CODE_AUDIT_3dTable.md` are not re-litigated unless noted "still present".

**Compiler ground truth.** A full clean build of the `MasterRPG` scheme (iOS Simulator, all 15 modules + app + widget + share extension) produced **0 Swift warnings and 0 errors** (only two "App Intents metadata extraction skipped" tool notices). macOS, tvOS and visionOS destinations were **not** built, so `#if os(...)` branches for those platforms were read by eye only. The repo's own `Scripts/verify_accessibility.rb` passes; `Scripts/verify_localization.rb` fails with 162 issues (§8.5).

**Headline result.** The mechanical hygiene is excellent (zero `try!`/`as!`, zero `ObservableObject` except one Apple-forced type, no banned SwiftUI modifiers to speak of, computed-`some View` splitting down from ~130 to 1 site). The real remainder is **trust-boundary and robustness work** in the import/file layer and the game network stack: one Critical file-path traversal reachable from a hostile `.gmz` or an authenticated LAN/SharePlay peer (§5.1), and several High findings around peer-supplied data being imported unfiltered (§5.2), a 4-digit PSK (§6.1), unclamped CRDT clocks (§5.3), and blocking file coordination on the Swift concurrency pool (§3.1).

---

## 1. Executive summary

Top items to address, in priority order:

1. **[Critical/Security] Path traversal in `FileUrl` resolution allows arbitrary file write/delete/read inside the app container** — §5.1 — `Modules/CoreRPG/Files/CloudDocumentController.swift:71-95`, `Modules/CoreRPG/Files/FileUrlDataController.swift:292-298`. A hostile `.gmz` or an authenticated peer's reveal can overwrite the Core Data store or other module files.
2. **[High/Security] Peer-supplied Character package is imported into the GM's permanent library with no id filtering** — §5.2 — `Modules/CharacterRPG/Controller/GameController+Sync.swift:54-58`, `Modules/CoreRPG/Controllable/ImportControllable.swift:95-215`.
3. **[High/Security] Join secret is a 4-digit TLS-PSK; offline-guessable and only throttled after failure** — §6.1 — `Modules/GameRPG/Network/GameJoinCodeModel.swift:100-102,172`, `ConnectionAttemptThrottle.swift:45-64`. Every trust-boundary finding above is reachable once the code is known.
4. **[High] CRDT last-writer-wins trusts any wall-clock timestamp** — §5.3 — `Modules/CoreRPG/CRDT/WallclockTimestamp.swift:59-71`. One wrong-clock device or crafted payload freezes items against later edits.
5. **[High/Concurrency] Blocking `NSFileCoordinator` calls run on the cooperative thread pool** — §3.1 — `Modules/CoreRPG/Files/FileManager+Coordination.swift:90-101`. Dozens of evicted-iCloud reads can starve every other async task, including LAN receive loops.
6. **[Medium/Security] PSK identity is built from raw bytes of a stack `Data` struct (out-of-bounds read + pointer leak in cleartext handshake)** — §6.2 — `Modules/GameRPG/Network/NWParameter+GameMaster.swift:85-93`.
7. **[Medium] `recoverFromError()` deletes only the `.sqlite` file, leaving `-wal`/`-shm` and CloudKit state** — §5.4 — `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:138-158`.
8. **[Medium] Import swallows every per-item and per-block error and reports success; export overwrites the previous file in place** — §5.7 — `Modules/CoreRPG/Controllable/ImportControllable.swift:133-172`.
9. **[Medium] Bookmark store is written non-atomically and a decode failure is treated as "empty" then overwritten** — §5.5 — `Modules/CoreRPG/Persistence/FilePersistenceController.swift:34-104`.
10. **[Medium] Master/Player Photo, Pdf and Space message handlers are copy-pasted and already drifted** — §9.9 — `Modules/GameRPG/Controller/MasterController+{Photo,Pdf,Space}Messages.swift`. The riskiest duplication in the repo because it sits in the network layer with a history of lost-message bugs.

---

## 2. Quick wins (≤30 min each)

- **Reject `..` components and absolute paths in `FileUrl` at decode/resolve time** as a first containment step — `Modules/CoreRPG/Files/CloudDocumentController.swift:71-95`. Small, high value; the full fix is §5.1.
- **Fix the PSK identity construction** to use the string's content bytes — `Modules/GameRPG/Network/NWParameter+GameMaster.swift:85-93`. §6.2.
- **Make `recoverFromError()` remove `-wal`/`-shm` sidecars** (or use the coordinator's destroy API) — `CloudKitCoreDataPersistenceController.swift:138-158`, `CoreDataPersistenceController.swift:158-181`. §5.4.
- **Write bookmark JSON atomically** — `Modules/CoreRPG/Persistence/FilePersistenceController.swift:34-68`. §5.5.
- **Check `terminalOutcomeReported` in `connectionFailed`** — `Modules/GameRPG/Network/ConnectionController.swift:314-322`. §3.6.
- **Fix `try? await Task.sleep` swallowing cancellation** in the recurring history cleanup — `Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift:38-47`. §3.9.
- **Switch `isolated deinit` for the four `assumeIsolated`-in-deinit classes** — `Navigator.swift:233-241`, `NavigationSend.swift:411-424`, `NavigationLocked.swift:54-62`, `NavigationProvidedDestination.swift:118-125`. §3.4.
- **Change ~10 `privacy: .public` logs of item names to `.private`** — e.g. `Modules/AudioRPG/Controller/AudioController.swift:252`. §6.6.
- **Delete the iOS 18 `#available` else-branch** — `Modules/CoreRPG/Navigator/Core/NavigationDismiss.swift:61-70`. §4.2.
- **Replace the shipping `print(`** — `Modules/GeneratorRPG/View/PdfSummaryAnalysisView.swift:176` (the other is preview-only, `Modules/CoreRPG/Fake/PreviewFixtureLoader.swift:25`). §9.22.
- **Delete `ChatViewModel.swift`** (198 unreferenced lines) — `Modules/GeneratorRPG/Model/ChatViewModel.swift`. §9.5.
- **Delete `Modules/CoreRPG/CustomBars/` and `Modules/CoreRPG/Shaders/`** — unreferenced / no Metal sources. §9.3, §9.2.
- **Guard `RootURLHandler` on `url.isFileURL`** — `Modules/RolePlayGameKit/Route/RootURLHandler.swift:17-24`. §5.12.
- **Reconcile string catalogs** (`xcodebuild -exportLocalizations`/Xcode "Refresh") to drop ~250 stale keys and fill ~95 missing German strings. §8.5.
- **Name the two `512_000_000` byte limits once** — `GameProtocol.swift:41`, `SharePlayJournalPublicationQueue.swift:92`. §9.20.

---

## 3. Concurrency

Compiler ground truth: zero warnings. Findings below are semantic issues the compiler cannot see. `@Observable`/`@MainActor` coverage was re-checked including the new uncommitted Table3D files: **fully compliant**. Every `withCheckedContinuation` site traced (SharePlay journal queues, `RPGSharePlayController.swift:249`, `GameTableModel+RenderingReadiness.swift:33`, `PlayerNetworkController.swift:139`, `ConnectionController.swift:249`) resumes exactly once on the paths read.

### 3.1 Blocking `NSFileCoordinator` calls run on the cooperative thread pool
- **Location:** `Modules/CoreRPG/Files/FileManager+Coordination.swift:90-101` (helper), used by every coordinated read/write/copy/download/delete/exists call in that file
- **What:** `performCoordinatedFileAccess` wraps each synchronous `NSFileCoordinator.coordinate` call in `Task.detached(priority: .utility)`, so every coordinated operation parks a Swift-concurrency pool thread while it waits; cancellation only calls `task.cancel()`, which cannot interrupt a coordinator already waiting.
- **Why:** The coordinator blocks until presenters/iCloud release the file, which can take long for evicted iCloud items. A module list with dozens of not-yet-downloaded thumbnails/PDFs can occupy every pool thread (roughly one per core), starving unrelated async work — LAN receive loops, `Task.sleep` wake-ups, `@concurrent` decode/render. The in-code comment ("suspends instead of blocking its thread") holds only for the caller, not for the pool.
- **Action:** Run coordination on a dedicated bounded serial queue/`OperationQueue` (or custom executor) bridged with a continuation, or cap concurrent coordinated operations with a limiter. Note cancellation still cannot abort an in-progress wait.
- **Severity:** High

### 3.2 LAN receive and relay decode/encode multi-megabyte JSON on the main actor
- **Location:** `Modules/GameRPG/Network/GameNetworkController+MasterDelegate.swift:29,41-42`; `GameNetworkController+PlayerDelegate.swift:28-39`; `Modules/GameRPG/Master/MasterNetworkController.swift:147,155,168`; codec at `Modules/GameRPG/Model/GameMessagePipeline.swift:269-281`
- **What:** `GameNetworkController` is `@MainActor` and `GameNetworkModel.decodeData(of:)` is a plain synchronous static, so it runs on the main actor for every inbound LAN message; relaying re-encodes the decoded model (up to three `encodeData()` calls in `MasterNetworkController`) instead of forwarding the received bytes.
- **Why:** Messages carry Base64 attachments (framer limit ~512 MB). A Map/Photo/PDF push over Bonjour hitches the GM's UI for decode and again for each re-encode. The SharePlay path deliberately keeps both off-main (`@concurrent` helpers in `RPGSharePlayController+ChunkedTransport.swift:763-781`), so the transports are inconsistent.
- **Action:** Decode/encode in a `@concurrent` helper as SharePlay does, and relay the original bytes when the envelope is unchanged.
- **Severity:** Medium (downgraded from the agent's High: cost is bounded by attachment size and only large pushes hit it)

### 3.3 Import stream parsing for network game data runs on the caller's (main) actor
- **Location:** `Modules/CoreRPG/Controllable/GameControllable.swift:399-406` (`importNetwork`), `:362-370`; `Modules/CoreRPG/Controllable/ImportControllable.swift:95-215`; `InputStream.readData(size:)` at `:733-753`
- **What:** `importNetwork`/`importStream` are `nonisolated async`; under approachable concurrency they inherit the caller's actor, and the player-side callers are `@MainActor`, so the synchronous read loop and the up-to-512 MB `[UInt8]` allocation-then-copy run on main.
- **Why:** A large PDF/3D-object reveal stalls the UI and doubles peak memory. The export side was already fixed the same way (`detachedGameData`, `MasterController+Messaging.swift:98-151`).
- **Action:** Parse off-main (`@concurrent` or detached with cancellation forwarding as `importUrl` does); read directly into `Data`.
- **Severity:** Medium

### 3.4 `MainActor.assumeIsolated` inside non-isolated `deinit`s
- **Location:** `Modules/CoreRPG/Navigator/Core/Navigator.swift:233-241`; `NavigationSend.swift:411-424`; `NavigationLocked.swift:54-62`; `NavigationProvidedDestination.swift:118-125`
- **What:** Four classes call `assumeIsolated` from a plain `deinit`, which runs on whatever thread drops the last reference.
- **Why:** If the last reference is released off-main (e.g. a `Task` or closure context freed on a pool thread) the app traps. Instances currently die on main via SwiftUI `@State`, so this is latent.
- **Action:** Use `isolated deinit`, which the project already uses in `ListenerManager`, `RPGSharePlayController`, `GameTableModel`.
- **Severity:** Medium

### 3.5 Runtime-trap isolation contract on `nonisolated` conformances of `@MainActor` models
- **Location:** `assumeMainActorIsolated` at 61 sites in 19 files (e.g. `Modules/DiceRPG/Model/DiceModel.swift:395-402,676-690`, Adventure/Space/Photo/Pdf/Value/Audio models); helper `Modules/CoreRPG/Concurrency/MainActorIsolationAssumption.swift:19-21`; `@preconcurrency` conformances `Modules/CoreRPG/ItemList/ItemRowTreeModel.swift:52,78`; `Modules/CoreRPG/Extensions/Encoder+MainActor.swift:21-33`
- **What:** `<`, `==`, `merge`, `isSame`, `duplicate`, `encode(to:)` are `nonisolated` so `sorted()`, `Set` and Codable can call them, but their bodies trap unless the caller is on the main thread.
- **Why:** Any future `Task.detached`/`@concurrent`/`JSONEncoder` use over these models (e.g. sorting a model array in a detached import task) crashes at runtime with no compile-time signal.
- **Action:** Keep the single helper; add debug logging and unit tests that assert off-main misuse is caught; prefer sorting/hashing on Sendable snapshots (`ItemRowModel`, ids).
- **Severity:** Medium

### 3.6 `ConnectionController`: unordered state callbacks and a possible double terminal outcome
- **Location:** `Modules/GameRPG/Network/ConnectionController.swift:90-95,202-236,247-262,265-275,314-322`
- **What:** (a) Each `NWConnection.State` change is delivered through its own unstructured `Task`, with no FIFO guarantee, so `.ready` can be processed after `.failed`/`.cancelled` and arm a receive on a dead connection. (b) `terminalOutcomeReported` is checked only in `.cancelled`, not in `connectionFailed`; on intentional `cancel()` the pending receive completes with an error and reaches `process(error:)` → `connectionFailed`, so the delegate can see `lostConnection` and `failed` for the same connection.
- **Why:** The "one terminal outcome" invariant documented in `CODE_AUDIT_Reconnect` §3.1 / `CODE_AUDIT_Network` §5.9 is not actually enforced. Consequences are mostly benign today because `removeConnection` is idempotent and `PlayerNetworkController` guards with `isCurrentConnection`, but throttle bookkeeping can double count.
- **Action:** Deliver states through a single `AsyncStream` consumed by one loop; check `terminalOutcomeReported` in `connectionFailed`; ignore receive completions after `cancel()`.
- **Severity:** Medium

### 3.7 `ListenerManager`: superseded `networkTask` overwrites newer state
- **Location:** `Modules/GameRPG/Network/ListenerManager.swift:57-90`
- **What:** `startListening()` cancels the old task and starts a new one synchronously; the old task's `CancellationError` handler resumes later and sets `state = .cancelled`/`.stopped` after the new call already set `.connecting` (and can overwrite `stopListening()`'s `.stopped`).
- **Why:** Bogus state for observers, and the `startListening` guard is bypassed so a second listener can start while the first is still starting — the classic stale-result-overwrites-newer-state pattern.
- **Action:** Tag each run with a generation token and apply catch-block state writes only if the token is current.
- **Severity:** Medium

### 3.8 visionOS share-state observation chain is broken by `reset()`
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:798-825`; reset at `RPGSharePlayController+ChunkedTransport.swift:900-925`. (`#if os(visionOS)` — read by eye only.)
- **What:** `withObservationTracking` fires once and re-arms only inside the tracked `Task` body after `guard !Task.isCancelled`; `reset()` cancels every entry in `tasks`, so a mode change racing a reset leaves observation un-armed and `setup()` does not run again.
- **Why:** Group-immersion/presentation-mode sync silently stops for later sessions until the game is restarted.
- **Action:** Re-arm observation before scheduling the task (as `PlayerNetworkController.checkForRemoval` does) or use a persistent `Observations` loop that survives `reset()`.
- **Severity:** Medium

### 3.9 Recurring history cleanup runs immediately when its task is cancelled
- **Location:** `Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift:38-47`; cancelled/replaced at `CoreDataPersistenceController.swift:~229`
- **What:** `try? await Task.sleep(...)` swallows the `CancellationError`, so a cancelled task falls straight into `await cleanup()`; the `while !Task.isCancelled` check only stops the loop afterwards.
- **Why:** Cancelling/replacing the task (store reload, teardown) runs `persistentHistoryCleaner.clean()` on the main actor immediately, defeating the startup delay.
- **Action:** Use `try await` and return on cancellation, or check `Task.isCancelled` before each `cleanup()`.
- **Severity:** Medium

### 3.10 Sleep-based synchronization for navigation and window routing
- **Location:** `Modules/RolePlayGameKit/Model/AppModel.swift:425-428,514-537,580-584,622-628`; `Modules/RolePlayGameKit/Route/WindowRouter.swift:188-189`; `Modules/PdfRPG/Pdf/PdfWrapperView.swift:75,163`; 45 `try? await Task.sleep` sites in total
- **What:** Routes/selections are applied after fixed delays (~150 ms cross-window, 0.8 s receiver) as a stand-in for "the window/stack has mounted"; tasks are untracked, capture `self` strongly, and `try?` swallows cancellation so a cancelled sleep still performs the route.
- **Why:** On a slow device or cold macOS/visionOS window open, the route is dropped or applied before the stack subscribes; failures are timing-dependent.
- **Action:** Use readiness signals (the existing `pendingExternalRoute` approach or an `AsyncStream` reporting "mounted"); keep one tracked task per route and check cancellation after the sleep.
- **Severity:** Medium

### 3.11 `SpaceViewer` subscription closures capture the view struct
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:556-600` (subscriptions stored in `@State` at `:58-59`). (visionOS — read by eye only; not compiled.)
- **What:** Four `content.subscribe` closures use `self.` inside `Task { @MainActor in … }`, capturing the `SpaceViewer` value whose `@State` storage holds the `EventSubscription` that retains the closure.
- **Why:** Likely retain cycle and stale-copy capture; violates the project rule "a closure stored on the model must never capture a SwiftUI view value". Unverified at runtime.
- **Action:** Route events through a `@MainActor @Observable` model held weakly, or capture only the specific state/handler needed.
- **Severity:** Medium

### 3.12 `FileUrl` hashing and temp-file writes run on the caller's actor
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:238,274,282,364`
- **What:** `FileUrlDataController` is a Sendable struct with `nonisolated async` methods, so under approachable concurrency the SHA-256 of whole picked/imported files and temp writes run on the main actor when called from `@MainActor` item controllers.
- **Why:** Importing a hundreds-of-MB file blocks the UI for the hash duration.
- **Action:** Mark hash/write steps `@concurrent` or hash inside the coordinated-read task.
- **Severity:** Medium

### 3.13 `GameJoinCodeModel`: fire-and-forget Keychain writes can reorder
- **Location:** `Modules/GameRPG/Network/GameJoinCodeModel.swift:60-100,150-165`
- **What:** Each change spawns `Task.detached` that checks `isCancelled` only at start; a superseded task already inside `set` still finishes, while the new one runs in parallel.
- **Why:** Two quick edits (or `reset()` calling `randomCode()` twice) can persist the older code last; the write may also be lost at termination.
- **Action:** Serialize writes through one actor/`AsyncStream`, or write synchronously (the value is 4 characters).
- **Severity:** Low

### 3.14 Dice widget update task can lose the newest roll
- **Location:** `Modules/DiceRPG/Controller/GameController.swift:609-627`
- **What:** A newer roll cancels the previous `Task.detached`, but `diceUpdateWidget` checks `isCancelled` once at entry, before its read-modify-write of `DiceConfiguration` in UserDefaults.
- **Why:** An older task past the guard can finish last, leaving the widget on a stale roll.
- **Action:** Serialize through an actor/`AsyncStream` or make the write last-writer-wins by roll id.
- **Severity:** Low

### 3.15 Side-effecting untracked `Task` inside a String-returning link transform
- **Location:** `Modules/CharacterRPG/Controller/LinkController.swift:35-40` (`toggleTextLink`)
- **What:** A function returning a rewritten `String` also fires an untracked `Task { sleep 100 ms; await toggler(...) }` for auto-expand, with no de-duplication.
- **Why:** If reached from text rebuilds (e.g. via view-body evaluation) the toggler could fire repeatedly per link. Call frequency was not confirmed.
- **Action:** Make the transform pure and trigger the toggle from the tap or `.task(id:)`.
- **Severity:** Low

### 3.16 `@unchecked Sendable` / `nonisolated(unsafe)` inventory — no latent races found
- **Location:** `FoundryRuleModels.swift:167-172`; `CoreDataChangeObserver.swift:22-77`; `CoreDataPersistenceController.swift:22,209`; `CloudKitCoreDataPersistenceController.swift:279`; `Navigator.swift:31-38`; `SimpleModel.swift:17`; `FakeItemModel.swift:6`; `FakeExportController.swift:6`; `SingleReviewPreviewData.swift:6`; `PerformanceTrace.swift:19-23`; `Encoder+MainActor.swift:25`; `GameBoard.swift:134`; `AudioListenerCoordinator.swift:30-40`; DEBUG spies in `Master/MasterNetworkModel.swift`, `Player/PlayerNetworkModel.swift`
- **What:** All ~30 sites were audited: protection is real (single-decode confinement, immutable values, `Mutex`, stateless subclasses). `@unchecked` is redundant on `@MainActor` classes (`Navigator`, `CoreDataInitModel`, `SimpleModel`, `FakeItemModel`, `PreviewItemModel`), and `CoreDataChangeObserver.observeCoreDataChanges` traps via `precondition` if called twice.
- **Why:** Redundant markers would hide a real problem if isolation were ever removed.
- **Action:** Drop `@unchecked Sendable` on the `@MainActor` classes; optionally return an error instead of trapping in `CoreDataChangeObserver`.
- **Severity:** Low

### 3.17 Retroactive `@unchecked Sendable` on the standard library's `KeyPath`
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:9`
- **What:** `extension KeyPath: @unchecked @retroactive Sendable {}` is declared globally in CoreRPG.
- **Why:** It disables Sendable checking for every key path in every importing module and will conflict if the standard library adds its own conformance.
- **Action:** Remove it; use `@Sendable` closures / `KeyPath & Sendable`, or a private wrapper type.
- **Severity:** Low

---

## 4. API modernity

### 4.1 CLAUDE.md ban-list sweep: essentially clean
- **Location:** Grep counts over `Modules/` and `Sources/` (excluding Tests/Snapshots/comments)
- **What:** Zero hits for `ObservableObject`/`@Published`/`@StateObject`/`@EnvironmentObject`, `foregroundColor`, `.tabItem`, `NavigationView`, `UIScreen`, `String(format:)`, `DateFormatter`/`NumberFormatter`/`MeasurementFormatter`, `replacingOccurrences`, `ScrollViewReader`, `showsIndicators`, `appendingPathComponent`, `Task.sleep(nanoseconds:)`, 1-parameter `onChange`, `Array(x.enumerated())`, `.actionSheet`, `UIApplication.shared.windows`. Accepted exceptions: one `@ObservedObject` for Apple's `GroupStateObserver` (`Modules/GameRPG/SetupViews/SharePlayButton.swift:21`); 3 `DispatchQueue` uses required by Network.framework (`ConnectionController.swift:38`, `ListenerManager.swift:130`, `NWParameter+GameMaster.swift:13`); one `onTapGesture(count: 2)` (count needed, `Modules/CoreRPG/Inspector/InspectorRowView.swift:74`); `GeometryReader3D` (2 sites, visionOS-only); `.cornerRadius(5)` at `Modules/GameRPG/Statistics/View/GameStatisticsDiceChart.swift:25` is the `ChartContent` modifier (false positive); `fontWeight(.heavy)` at `Modules/CoreRPG/Extensions/View+variableBlur.swift:217` (cosmetic, dead file §9.2).
- **Why:** Confirms the modernization work is complete.
- **Action:** None.
- **Severity:** Low

### 4.2 Dead OS-version branch and unreferenced deprecated Navigator shims
- **Location:** `Modules/CoreRPG/Navigator/Core/NavigationDismiss.swift:58-72` (`#available(iOS 18.0, *)` with dead `else`), `:100-133` (four `navigationDismiss*` triggers + deprecated `navigationDismissible`); `NavigationSend.swift:82-86`; `NavigationDestination.swift:188-192`; `Navigator.swift:176-190` (`Navigator.current` + `_staticCurrent` weak global, written but never read); `NavigationLocked.swift` (`addNavigationLock`/`removeNavigationLock`)
- **What:** `#available(iOS 18.0, *)` is always true at a 26.0 deployment target; the deprecated items have no callers in Modules, Sources or Tests. Every other `#available` in the repo is for 26.1/26.4/27 and is legitimate.
- **Why:** Dead branch and dead public surface in the vendored Navigator.
- **Action:** Delete the else-branch and unreferenced shims/modifiers.
- **Severity:** Low

### 4.3 `UIGraphicsImageRenderer` in AKImage cropping
- **Location:** `Modules/CoreRPG/Extensions/Image+AKImage.swift:133`
- **What:** Bitmap crop uses `UIGraphicsImageRenderer` in a UIKit-only path (not a SwiftUI view render).
- **Why:** CLAUDE.md prefers `ImageRenderer` for *rendering SwiftUI views*; this is image cropping, so the rule does not directly apply.
- **Action:** Leave, or move to `CGImage.cropping(to:)` when the file is next touched.
- **Severity:** Low

### 4.4 `@preconcurrency` usage inventory
- **Location:** `@preconcurrency import CoreData` (5 files), `GroupActivities` (7 files incl. `RPGSharePlayController+ChunkedTransport.swift:8`), `TabletopKit`, `PDFKit` (3 files); conformances at `Navigator.swift:362`, `AnimatableFont.swift:11-16`; `RPGSharePlayController+SessionLifecycle.swift:393-403` sends a `GroupSession` into a detached task; `Modules/PdfRPG/Controller/ItemController.swift:56` returns a `PDFDocument` from a detached task without forwarding cancellation
- **What:** All cover framework types that predate Sendable annotations. Core Data use is confined to private background contexts with `await context.perform`; no `viewContext` and no `performAndWait` on main was found.
- **Why:** Acceptable now; revisit when SDKs annotate.
- **Action:** Forward cancellation into the PdfRPG detached task; otherwise revisit at the next SDK.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 `FileUrl` path traversal: arbitrary file write, delete and read inside the app containers
- **Location:** `Modules/CoreRPG/Files/CloudDocumentController.swift:71-95` (`fullUrl(fileUrl:)`, `fullUrl(filePath:)`), `:262-265` (`moduleUrl`); `Modules/CoreRPG/Files/LocationFileManager.swift:54-105`; `Modules/CoreRPG/Files/FileUrlDataController.swift:186-253` (`url(for:)`), `:258-320` (`createNewFileUrl`, esp. `:292,298`), `:409-435` (`delete`); `Modules/CoreRPG/Controllable/ImportControllable.swift:563-596` (`addFile`, call at `:588`); `Modules/CoreRPG/Controllable/GameControllable.swift:345-406`; `Modules/GameRPG/Controller/MasterController+PhotoMessages.swift:87-107` (call at `:95`)
- **What:** `FileUrl.rawUrl`, `location` and `module` are decoded straight from item JSON with no sanitisation (`FileUrl.swift`); `fullUrl(fileUrl:)` appends the URL's `pathComponents` one by one including `..`, `nameUrl`/`fullUrl(filePath:)` re-append them, `.other` locations and the `rawUrl` fallback in `url(for:)` pass absolute file URLs through unchanged, and no containment check against the module root exists anywhere on the path.
- **Why:** Verified by tracing the code and by a scratch test reproducing the exact URL operations (`URL.append(path:)`, `pathComponents`, JSON `URL` decode all preserve `..`): a `rawUrl` of `../../Stores/Private/private.sqlite` on a photo/PDF/space item with an attached file makes `createNewFileUrl` write attacker bytes to `<root>/Documents/<module>/../../Stores/Private/private.sqlite`, i.e. above `Documents/`. `preferredRootUrl` is the app-group container when iCloud is off and on tvOS (it holds the Core Data store); with iCloud on it is the ubiquity container (other synced module files). Triggers: (a) the GM importing a shared `.gmz`; (b) a player's `.reveal` of a photo/PDF/space item the master does not have — with default `FeatureConfig` (`photoSharing`/`spaceSharing` true) `handlePhoto` calls `updateGame(data:)` → `importNetwork` → `importStream` → `addFile` → `createNewFileUrl`. The same unvalidated URL drives `delete(_:)` (deletes any traversed file when the poisoned item is deleted) and `loadData(for:)`/`createGameData` (reads any absolute/traversed path and sends its bytes to players when the GM reveals the item). The peer path needs an authenticated LAN/SharePlay peer (see §6.1 for how weak the 4-digit gate is). Not exercised end-to-end in the running app; exact reach depends on which files sit above `Documents/` in each target/configuration.
- **Action:** Validate `FileUrl` at decode **and** at every resolve: reject `..` components, absolute paths, and unknown locations; resolve to a standardized path and require it to stay under the module root; never fall back to `rawUrl` for peer/import-originated items; accept `.url` locations only when http(s) (see §6.3); apply the same checks in `delete`. Consider rebuilding the stored path from `fileId` + extension instead of trusting the sender's path at all.
- **Severity:** Critical

### 5.2 Player-supplied Character package is imported into the GM's permanent library without id filtering
- **Location:** `Modules/GameRPG/Controller/MasterController+ValueMessages.swift:84-108` (call at `:85`); `Modules/CharacterRPG/Controller/GameController+Sync.swift:54-58`; `Modules/CoreRPG/Controllable/GameControllable.swift:399-406`; `Modules/CoreRPG/Controllable/ImportControllable.swift:95-215` (esp. `:139-176`, `addItem(importedItem:id:…)`)
- **What:** `updatePlayer(data:)` calls `importNetwork(from:forceSave: true)`; `importStream` then applies every item in the byte stream via `addItem`, and `additionalImport`/`finalImport` pull in linked modules. The only check is that `data.id` equals the sender's `characterId` — it is never compared to the ids inside the package.
- **Why:** A joining player (or anyone holding the join code, §6.1) can send a package containing ids of the GM's other characters/NPCs/other players' characters (and linked items) and have them merged into the permanent, CloudKit-synced library. Combined with unclamped timestamps (§5.3) the attacker's values always win.
- **Action:** Restrict peer imports to the exact expected ids (the single character plus its declared dependencies); import into game memory (`gameMemoryOnly`) rather than the library, or require GM confirmation; cap item/entry counts per package.
- **Severity:** High

### 5.3 CRDT last-writer-wins trusts any wall-clock timestamp
- **Location:** `Modules/CoreRPG/CRDT/LWWRegister.swift:46-53,71-83,115-119`; `Modules/CoreRPG/CRDT/WallclockTimestamp.swift:52-79` (ordering at `:59`, init at `:67`)
- **What:** The clock is `Date()`-based (`MonotonicWallClock.now()` is monotonic only within the process); remote timestamps are neither clamped nor used to advance the local clock, and NaN timestamps from crafted JSON order inconsistently.
- **Why:** One device with a clock set years ahead, or one crafted import/peer payload, wins every merge; afterwards edits from correctly-clocked devices silently lose on the next CloudKit/import merge, freezing the item. Amplifies §5.2.
- **Action:** Use a hybrid logical clock (take max(local, observed)+1 on merge); reject or clamp timestamps more than a few minutes in the future from untrusted sources; reject non-finite values.
- **Severity:** High

### 5.4 `recoverFromError()` deletes only the `.sqlite` file
- **Location:** `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:138-158`; `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:158-181`
- **What:** `removeItem(at:)` removes only the main store file, and the `.migration` state is set for *any* `loadPersistentStores` error.
- **Why:** After "delete database", a fresh store is created beside a stale `-wal`/`-shm` that SQLite can replay into it (corruption/immediate load failure), CloudKit history/mirroring state files are left behind, and transient errors (disk full, data-protection lock) are offered the same destructive remedy.
- **Action:** Use `NSPersistentStoreCoordinator.destroyPersistentStore(at:type:options:)` (or delete sidecars together); distinguish real migration errors from transient ones before offering deletion.
- **Severity:** Medium

### 5.5 Bookmark store is written non-atomically; a load failure is treated as empty and then overwritten
- **Location:** `Modules/CoreRPG/Persistence/FilePersistenceController.swift:34-55,57-68,100-104`; `Modules/CoreRPG/Files/FileBookmarkController.swift:56-74`; `Modules/CoreRPG/Files/FileDataController.swift:57-73`
- **What:** `saveModel` uses `try? encoder.encode` and non-atomic `Data.write`; `load()` returns `[]` on any decode error; `save()` rewrites the whole dictionary on every change.
- **Why:** A kill mid-write truncates `<module>Bookmarks.json`; the next launch loads nothing and the next save overwrites the corrupt file, losing every user-picked (`.icloud`/`.other`) bookmark. O(n) rewrite per change.
- **Action:** Write atomically; keep a backup/rename on decode failure and never overwrite a file that failed to decode; save incrementally or debounced.
- **Severity:** Medium

### 5.6 Core Data helpers hide failures and can create duplicates
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:169-194,286-305,331-351,382-411,488-494`
- **What:** `batchExists` returns an empty set on a fetch error, so `flushPendingOperations`/`batchReplace` insert everything as new; `batchDelete`/`saveCoreData` only log errors; `fetchAndDelete` keeps an arbitrary duplicate; `flushPendingOperations` clears its queue before the awaited work runs.
- **Why:** A transient fetch error during save creates duplicate uuid rows; a later fetch deletes an arbitrary one (possibly the newest edit); a failed delete save still logs "Batch deleted".
- **Action:** Make `batchExists` throw; restore the queue when a flush fails; propagate save errors; keep the duplicate with the newest CRDT timestamp deterministically.
- **Severity:** Medium

### 5.7 Import swallows per-item and per-block errors and still reports success; export edge cases
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:133-176,270-291,733-753`; `Modules/CoreRPG/Model/ItemDataExportModel.swift:44-72`; `Modules/CoreRPG/Controllable/ExportControllable.swift:218-244`
- **What:** `importStream` catches errors per item and per block and only logs; `notEnoughData` (truncated file), `CancellationError`, and unsupported tokens are all swallowed and `performImport` still finishes "successfully". `readData(size:)` allocates up to 512 MB before checking availability. Export writes with `OutputStream(url:append:false)` directly over the destination; `append(counter:)` converts to `UInt32` (traps above 4 GB); `write(data:)` can spin if `write` returns 0.
- **Why:** A corrupt/partial `.gmz` "succeeds" with fewer items and no message; a truncated header can allocate ~1 GB peak and get the app jetsammed; a failed/cancelled export destroys the previous backup file.
- **Action:** Count failed items and surface a partial-import summary; fail on framing errors and rethrow `CancellationError`; read in chunks with remaining-byte checks; export to a temp file and replace atomically; handle `write == 0` and size limits explicitly.
- **Severity:** Medium

### 5.8 Batch delete/insert on CloudKit-mirrored entities
- **Location:** `Modules/CoreRPG/Links/LinkRegisterController.swift:135-189`; `Modules/CoreRPG/Controllable/TagController.swift:100-140`; entity flags in `Modules/CoreRPG/Resources/Model.xcdatamodeld/Model.xcdatamodel/contents:3-19`; compare the documented caveat at `CoreDataController.swift:280-285`
- **What:** `LinkReferenceDataModel` and `TagDataModel` are `syncable="YES"` yet are written with `NSBatchDeleteRequest`/`NSBatchInsertRequest`, which bypass the mirroring export the repo's own comment warns about.
- **Why:** Deletions never reach other devices and locally rebuilt rows can duplicate mirrored ones, so link/tag state diverges. Not verified on two devices.
- **Action:** Mark these entities non-syncable (they can be rebuilt locally) or write them through the context.
- **Severity:** Medium

### 5.9 Client-authoritative dice results
- **Location:** `Modules/GameRPG/Controller/MasterController+DiceMessages.swift:29-59`
- **What:** The master accepts a player-reported `DiceResultModel` (sum, values, checked, result) into battle-round initiative, the game dice log and `tableGameControllable.addResult`, checking only the feature flag and message shape.
- **Why:** A player can forge any sum or a coup to set their own initiative or trigger a table outcome (e.g. a loot push).
- **Action:** Validate values against the dice definition (count, sides, range) or roll on the master for outcome-bearing rolls; bound `values` length and dice count.
- **Severity:** Medium

### 5.10 Generator supersession clears the busy state of the newer request
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:264-311,341-348`
- **What:** `defer { model.isLoading = false }` / `isExtracting` run in the superseded task after a newer request has started.
- **Why:** Sending a second request quickly shows an idle UI while the newer one is still generating.
- **Action:** Clear the flags only when the task's generation still equals `currentGeneration`.
- **Severity:** Low

### 5.11 Dice-notation parser and counter use unchecked `Int` arithmetic (latent)
- **Location:** `Modules/DiceRPG/Model/RawDieCounter.swift:25-58`; `Modules/DiceRPG/Model/RawDice.swift:73-95,113-129`
- **What:** `count` comes from `Int(text)`; `roll()` loops `1...abs(count)` (`abs(Int.min)` traps, huge counts loop effectively forever) and `min`/`max` compute `count * die.max` unchecked.
- **Why:** No production caller of `RawDice(text:)` was found, so this is latent until wired to imported/peer text.
- **Action:** Clamp count and sides; use overflow-reporting arithmetic.
- **Severity:** Low

### 5.12 `RootURLHandler` routes any URL by file extension regardless of scheme
- **Location:** `Modules/RolePlayGameKit/Route/RootURLHandler.swift:17-24`; `Modules/RolePlayGameKit/Model/AppModel.swift:439-458`
- **What:** Any URL ending `.gmz`, `.uvtt`, `.dd2vtt` or `.mrpgfoundry` (including `RPG://x/y.gmz` or a web URL) goes to the import UI, and `presentImport` calls `startAccessingSecurityScopedResource` on it.
- **Why:** The user must still approve and non-file URLs cannot be read, so impact is a confusing pending-import state.
- **Action:** Require `url.isFileURL` for document import.
- **Severity:** Low

### 5.13 Audio playlist temp copies are never removed when the playlist is replaced
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:109-140,145-169,204-221`
- **What:** `add(audio:replace:true)` clears `playList` without deleting each entry's `temporaryDirectory/<id>.<ext>` copy; only `removeAudio` does.
- **Why:** Long sessions leave many full-size audio copies in tmp until the OS purges them.
- **Action:** Remove old temp copies when replacing the playlist and at teardown.
- **Severity:** Low

### 5.14 `OptionKeyDownModel` monitor is never removed
- **Location:** `Modules/CoreRPG/Extensions/PressedKeyDetection.swift:167-197` (`deinit { // stop? }`, `stop()` never called); ~110 unused `kVK_*` constants at `:8-160`
- **What:** The local `NSEvent` monitor is registered and never removed; almost all key-code constants and helpers are unreferenced.
- **Why:** Harmless while the model is app-lifetime; leaks if it is ever recreated.
- **Action:** Delete unused constants/helpers; call `stop()` from an isolated `deinit`.
- **Severity:** Low

---

## 6. Security

Reviewed and found solid (not findings): `FoundryZIPArchive` (zip-slip, symlinks, bomb limits), LevelDB/Snappy readers, Foundry media normaliser, `SharePlayPackageReceiver` bounds, sandbox/ATS settings, usage descriptions, per-config `aps-environment` entitlements. No hardcoded secrets or tokens were found.

### 6.1 Join secret is a 4-digit code used as a TLS-PSK; guesses are throttled only after failure
- **Location:** `Modules/GameRPG/Network/GameJoinCodeModel.swift:99-103,172`; `Modules/GameRPG/Network/NWParameter+GameMaster.swift:25-82`; `Modules/GameRPG/Network/ConnectionAttemptThrottle.swift:45-64`; `Modules/GameRPG/Network/GameNetworkController+MasterDelegate.swift:33-38`
- **What:** The PSK is `HMAC(passcode, "GameMaster")` over 10,000 possible codes (`Int.random(in: 0...9999)`, zero-padded), with a constant PSK identity; codes persist per device until manually reset and the last-used code is retried automatically. The throttle's `shouldAllow` only consults `lockedUntil`, which `recordFailure` sets after failures, and it is keyed per host.
- **Why:** A TLS-PSK handshake gives an on-LAN eavesdropper or rogue Bonjour advertiser material to test all 10,000 codes offline in seconds; the throttle only slows online guessing (parallel handshakes all pass `shouldAllow` before any failure is recorded, and multiple addresses/IPv6 privacy addresses evade a per-host key). Once known, every master-state and message path — including §5.1 and §5.2 — is reachable, since there is no per-connection cap and no authentication beyond the code.
- **Action:** Use a longer random secret (≥8 alphanumerics or a QR/handshake-derived secret) or a PAKE; rotate per session; add a per-listener cap on pending and total connections and count in-flight handshakes toward the throttle.
- **Severity:** High

### 6.2 PSK identity is built from raw bytes of a stack `Data` value (out-of-bounds read + pointer leak)
- **Location:** `Modules/GameRPG/Network/NWParameter+GameMaster.swift:85-93`
- **What:** `withUnsafeBytes(of: stringData)` exposes the memory of the `Data` *struct* (16 bytes), not its contents, and the code then builds a buffer of `stringData.count` (22 bytes for "GameMaster" in `.unicode`) from that base address.
- **Why:** The PSK identity sent in clear in the TLS ClientKeyExchange is adjacent stack memory plus heap-pointer bytes: a small out-of-bounds read, an ASLR-weakening information leak, and an identity that differs per process. It works only because the server ignores the identity.
- **Action:** Build the `DispatchData` from `stringData.withUnsafeBytes` (content bytes) or from `Data("GameMaster".utf8)`.
- **Severity:** Medium

### 6.3 A peer-supplied `.url` `FileUrl` makes the GM device fetch arbitrary https URLs
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:602-638,674-681`; `Modules/CoreRPG/Files/FileUrl.swift:154-163`
- **What:** An item from a peer or import can carry `location == .url` with any https URL; `ensureRemoteCache` downloads it via `URLSession.shared.download` with no size limit, redirect policy or private-address checks.
- **Why:** Leaks the GM's IP to an attacker's server, permits probing of internal HTTPS hosts, and forces an unbounded download into Caches.
- **Action:** Do not auto-fetch remote URLs from peer/import-supplied items; require an explicit GM action and cap size/content type.
- **Severity:** Medium

### 6.4 Network framer accepts declared frames up to 512 MB per connection
- **Location:** `Modules/GameRPG/Network/GameProtocol.swift:41,98-118`
- **What:** `deliverInputNoCopy(length:)` permits any declared length up to 512,000,000 bytes with no per-connection quota or global budget.
- **Why:** One authenticated but hostile/buggy player can declare 512 MB and stream it; `receiveMessage` buffers the whole frame and JSON decoding copies it again, so a GM iPad/Apple TV is jetsammed mid-game; several connections multiply this.
- **Action:** Cap non-file LAN frames at a few MB, move large payloads to a file/journal channel with per-peer budgets, and enforce a total in-flight byte budget.
- **Severity:** Medium

### 6.5 Item names and other user content logged with `privacy: .public`
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:252`; `AudioRPG/Controller/LinkController.swift:75`; `TableRPG/Controller/LinkController.swift:73,89`; `TableRPG/Controller/ExportController.swift:71`; `RuleRPG/Controller/LinkController.swift:159`; `SpaceRPG/Controller/LinkController.swift:58`; `WeatherRPG/Controller/LinkController.swift:44,50`; `DiceRPG/Controller/LinkController.swift:66`; `CoreRPG/Controllable/EditControllable.swift:243`
- **What:** Campaign item names, titles and link markdown are logged as public; Adventure/import/Map code already uses `.private` for the same data.
- **Why:** NPC/plot/audio-title text lands in plaintext, sysdiagnose-exportable logs, contradicting the repo's own convention.
- **Action:** Switch to `.private` or log ids only.
- **Severity:** Low

---

## 7. Performance

### 7.1 Share extension reads unbounded payloads into memory
- **Location:** `Sources/RPGShare/ItemProviderImporter.swift:21-52,100-115,160-178,209-224`
- **What:** Each shared image/file is loaded fully into `Data`, `.url` items are fetched with `URLSession.shared.data(from:)` with no size cap, and downsampling/total-budget checks run only after the whole payload is in memory.
- **Why:** One very large file/image or a URL pointing at a big download exceeds the extension's ~120 MB limit; the extension is killed and the user loses the share with no error. A shared web-page URL is also downloaded and saved as an "image".
- **Action:** Check file size before reading; use `CGImageSourceCreateWithURL` for file URLs; cap network downloads and reject non-image types; apply the budget before loading.
- **Severity:** Medium

### 7.2 Share extension opens the full `NSPersistentCloudKitContainer`
- **Location:** `Modules/RolePlayGameKit/Model/ShareExtensionDatabaseService.swift:36-65`
- **What:** With CloudKit enabled the extension constructs `CloudKitCoreDataPersistenceController`, loading all module models, the mirroring delegate and the history tracker in a short-lived process.
- **Why:** Two mirroring delegates on one store (app + extension), a process that can be terminated mid-export, and tight memory. Not verified at runtime.
- **Action:** Open the store in the extension without `cloudKitContainerOptions`, keeping persistent history on, and let the app export.
- **Severity:** Medium

### 7.3 Foundry archive store decodes every stored archive in full to build summaries
- **Location:** `Modules/CoreRPG/Foundry/FoundryImportArchive.swift:151-155,157-204,236-268`; callers `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:124,233`
- **What:** `sourceRegistryEntries()` and `summaries()` call `decodedArchives()`, decoding every archive JSON (each up to 512 MB) into memory at once on each import review.
- **Why:** With several large imported systems, opening the import screen can decode gigabytes of `FoundryJSONValue` trees and get the app jetsammed.
- **Action:** Persist a small summary index per archive or decode only the manifest header; process one archive at a time.
- **Severity:** Medium

### 7.4 Content-widget snapshot rebuilt and reloaded on every item mutation
- **Location:** `Modules/CoreRPG/Widget/ContentWidgetSnapshot.swift:42-60`; call sites `Modules/CoreRPG/Controllable/ItemControllable.swift:155,181,323,379,430,437`; `Modules/RolePlayGameKit/Model/AppModel.swift:268`
- **What:** Each mutation walks all items, JSON-encodes and writes UserDefaults, and calls `WidgetCenter.reloadTimelines`.
- **Why:** A bulk import/CloudKit sync burst of thousands of items is O(N²), and frequent reload requests are throttled by WidgetKit.
- **Action:** Coalesce with a debounce/dirty flag and compute only the first four visible items.
- **Severity:** Low (Medium if large libraries are imported regularly)

---

## 8. SwiftUI / UI

Scope: `Modules/*/View*`, `CoreRPG/{Views,LGViews,LGViewModifiers}`, `RolePlayGameKit`, `GameRPG/GameViews`, `Sources/*` (688 view-related files scanned; the accessibility verifier passes across 1,820 production files).

### 8.1 SwiftUI ban-list conformance is very high
- **Location:** repo-wide greps
- **What:** Zero `foregroundColor`, `.tabItem`, `NavigationView`, `showsIndicators`, `ScrollViewReader`, 1-parameter `onChange`, old accessibility modifiers, `.animation(_:)` without `value`, `ForEach(.indices)`; only one non-private `@State` (§8.2); computed `some View` *property* splitting is down to one site (`Modules/CoreRPG/FileViews/SingleReviewFilePropertyRow.swift:93`; `NavigationDestination.swift:189` is a `@ViewBuilder` bridge) versus ~130 in the previous audit. The only `ForEach` id by position is `Modules/DiceRPG/Game/Detail/DieViewerView.swift:35` (per-die result list, benign). Small `.filter`/`.sorted` calls in view files operate on small collections (e.g. `MapEntryViewer.swift:114`, `AddtionalEntryRow.swift:45`) and are not hot.
- **Why:** Confirms the modernization is complete; no view-body hoisting issues significant enough to report were found.
- **Action:** None.
- **Severity:** Low

### 8.2 Non-private `@State` on `ImageViewer` (documented exception)
- **Location:** `Modules/PhotoRPG/Photo/ImageViewer.swift:19` (also `@GestureState var gestureSession` at `:22`)
- **What:** `@State var viewportModel` is not `private` because `ImageViewer+Gestures.swift` reads it.
- **Why:** Violates the "`@State` is private" rule in spirit; the reason is commented.
- **Action:** Pass the model into the gesture extension instead, or leave as-is.
- **Severity:** Low

### 8.3 `AnyView` at the module boundary (114 mentions)
- **Location:** `Modules/CoreRPG/Controllable/ViewControllable.swift` (16), per-module `Controller/ViewController.swift` (4–10 each), `CoreRPG/Navigator/Core/NavigationModifiers.swift` (6)
- **What:** `AnyView` erases module-provided views (rows, importers, thumbnails) behind protocol requirements.
- **Why:** It is the accepted type-erasure seam between 15 modules (`CODE_AUDIT_14` §8.5); costs diffing precision in list rows.
- **Action:** None now; if list-row performance ever matters, switch hot row factories to `some View` associated types.
- **Severity:** Low

### 8.4 Hard-coded padding, spacing and fixed frame sizes
- **Location:** ~106 `.padding(<literal>)`, ~320 `spacing: <literal>`, ~126 `.frame(width:/height: <literal>)` in `Modules/` and `Sources/` (e.g. `DieViewerView.swift:26-45`)
- **What:** CLAUDE.md asks to avoid hard-coded padding/spacing unless requested.
- **Why:** Weak Dynamic Type scaling and inconsistent spacing on tvOS/visionOS; a style guideline, not a defect.
- **Action:** Convert opportunistically to default spacing or `@ScaledMetric` when a view is next edited.
- **Severity:** Low

### 8.5 String catalogs out of sync with the repo's own verifier (162 issues)
- **Location:** `Scripts/verify_localization.rb` output; catalogs `Modules/*/Resources/Localizable.xcstrings`, `Resources/Localizable.xcstrings`, `Resources/InfoTVPlist.xcstrings`, `Sources/DiceRollerWidget/Localizable.xcstrings`
- **What:** ~95 active keys have no complete German localization (GameRPG 26, TableRPG 13, DiceRPG 11, CoreRPG 6, MapRPG 9, RolePlayGameKit 7, PhotoRPG 5, PdfRPG 2, others), including user-facing join-code, reconnect, battle and turn-order strings and common words ("Done", "Save", "Close", "Yes", "No" in TableRPG); ~250 stale keys sit in 14 catalogs (GeneratorRPG 72, DiceRollerWidget 50, GameRPG 43, CoreRPG 17, MapRPG 15, InfoTVPlist 13). `GameRPG/Resources/Localizable.xcstrings` also has uncommitted edits in the working tree.
- **Why:** German users see English fallbacks in the newest features; stale keys bloat the catalogs. Wording quality was not assessed.
- **Action:** Refresh catalogs with a compiler extraction, translate the missing keys, and delete stale ones; run the verifier in CI.
- **Severity:** Medium

---

## 9. Dead code / duplication / refactor

Dead-code claims below were confirmed with a whole-repo identifier scan across `Modules/`, `Sources/` and `Tests/`; the highest-LOC ones (§9.1–§9.6) were re-checked by hand. Generated snapshot tests reference several of these types, so delete their snapshot roots too.

### 9.1 Vendored Navigator checkpoint/flow API is unused (~780 LOC)
- **Location:** `Modules/CoreRPG/Navigator/Core/NavigationCheckpoint.swift:1-446`; `NavigationFlow.swift:1-334`; storage in `NavigationSceneStorage.swift:16-79` and `Navigator.swift:76`
- **What:** `NavigationFlow`, `NavigationCheckpoint(s)`, `navigationCheckpoint` and `returnToCheckpoint` have zero references outside `Modules/CoreRPG/Navigator` (re-verified).
- **Why:** Compiled, maintained and persisted into scene storage without being reachable. Note the prior audit also flagged `@State` seeded from an init parameter in this file (`CODE_AUDIT_14` §8.2).
- **Action:** Delete the files and drop the checkpoint plumbing from `Navigator`/`NavigationSceneStorage`.
- **Severity:** Medium (~780 LOC removed)

### 9.2 Metal-shader-dependent files ship without any Metal source and are unused
- **Location:** `Modules/CoreRPG/Buttons/HarmonicButton.swift:1-97`; `Modules/CoreRPG/Extensions/View+variableBlur.swift:1-237`; `Extensions/VisualEffect+variableBlur.swift:1-57` (`ShaderLibrary.bundle(.module)` at `:10`); `Modules/CoreRPG/Shaders/` (contains only a `.DS_Store` and a commented-out shader)
- **What:** The repo has no `.metal` files; `HarmonicButton` and `variableBlur` have no non-test callers (re-verified for `HarmonicButton`).
- **Why:** ~390 LOC of unreachable code; if ever used, the missing shader would silently render nothing.
- **Action:** Delete the three Swift files and the `Shaders/` folder (or restore the Metal sources if wanted) plus their snapshot roots.
- **Severity:** Medium

### 9.3 `CustomBars` folder is dead
- **Location:** `Modules/CoreRPG/CustomBars/CustomNavBarView.swift:1-92`; `CustomNavBarInternalView.swift:1-84`; `NavBarBackground.swift:1-39`; `NavBarEnv.swift:1-38`
- **What:** Referenced only within the folder and by generated snapshot tests (`CoreRPGGeneratedPreviewSnapshotTests.swift:95-127`, `CoreRPGDynamicPreviewSnapshotTests.swift:85-100`).
- **Why:** ~250 LOC of public API with no product use.
- **Action:** Delete the folder and its snapshot roots.
- **Severity:** Medium

### 9.4 ~1,000 LOC of unreferenced view-modifier helpers
- **Location (whole files):** `Modules/CoreRPG/Buttons/CustomDragTapGesture.swift:1-354`; `ItemViews/ExpandButtonModifier.swift`; `List/ShowItemViewModifier.swift`; `ViewModifiers/SheetFullScreenModifier.swift`; `ViewModifiers/TabBarMinimizeBehavior26.swift`; `Animations/AnimationEndCallback.swift`; `App/AppToolBarAppearenceViewModifier.swift`; `App/KeyboardObserver.swift`; `Extensions/AnimatableFont.swift`; `Extensions/OverlayStrokeStyle.swift`; `ViewModifiers/Keyshortcuts.swift`; `Accessibility/AccessibilityLabelCache.swift`; `Modules/GameRPG/GameViews/GameOverlayTabViewModifier.swift`. **Partial (dead functions in live files):** `App/PlatformModifiers.swift:14,22,78,87,96`; `ViewModifiers/FocusModifiers.swift:9,13`; `Buttons/BorderLessTVBottonStyleViewModifer.swift:30`; `Platform/NavigationStackWrapper.swift:6`; `Platform/TextFieldAll.swift:20`; `Rows/ColoredEditRowModifier.swift:9`; `List/RowTintModifier.swift:6`; `Extensions/AnchorPreference.swift:6`; `Extensions/Scene+DefaultSize.swift:6`
- **What:** Each helper's `View` extension and modifier type appear nowhere else in Modules, Sources or Tests (confirmed by identifier-frequency scan; `dragTapGesture` re-verified).
- **Why:** ~20 abandoned helpers cost compile time and API surface.
- **Action:** Delete whole-file items after confirming no preview-only use; prune the partial ones.
- **Severity:** Medium

### 9.5 `ChatViewModel` is an unreferenced 198-line class
- **Location:** `Modules/GeneratorRPG/Model/ChatViewModel.swift:1-198`
- **What:** Referenced nowhere outside its own file (re-verified); its stored property `SamplingStrategyConfiguration` is capitalized like its type.
- **Why:** A full FoundationModels chat model the module's real controllers don't use.
- **Action:** Delete; then re-check whether the old chat-path `submitFeedback`/`getFeedback` and `ConversationEngine` features are still reachable.
- **Severity:** Medium

### 9.6 SwiftData controller is test-only in a Core Data app
- **Location:** `Modules/CoreRPG/Persistence/SwiftDataController.swift:1-62` (only referenced by `Tests/CoreRPGTests/SwiftDataControllerTests.swift`)
- **What:** A `@preconcurrency @ModelActor` whose `fetch()` returns non-Sendable `PersistentModel` arrays across the actor boundary; no production callers; its `Logger.swiftDataController` category is unreferenced.
- **Why:** A parallel, never-used persistence stack that hides Sendable violations behind `@preconcurrency` and would be a data race if used.
- **Action:** Delete it with its test.
- **Severity:** Low

### 9.7 Many small dead members
- **Location:** `CoreRPG/Debug/Logging.swift:6-11`; `ScenesManager.swift:235,260,391`; `ScenesManager/ModuleRouting.swift:20`; `Cache/ResourceCache.swift:79,98`; `Cache/ObjectCache.swift:61`; `Files/CloudDocumentController.swift:52`; `ItemList/EntryDataEditable.swift:155`; `Controllable/EditControllable.swift:236`; `Persistence/CoreDataController.swift:470`; `Extensions/Bundle+decode.swift:36`; `FileViews/ImportReviewModels.swift:121`; `MapRPG/Controller/EditController.swift:327`; `MapRPG/Model/DataModel+Extensions.swift:28`; `MapRPG/BattleRound/BattleRoundSettingsModel.swift:73`; `GeneratorRPG/Controller/AdventureGeneratorController.swift:227`; `CoreRPG/Tips/MasterRPGTips.swift:344`; `CoreRPG/Model/CodableColor.swift:44`; `CoreRPG/Persistence/CoreDataPersistenceController.swift:62`; `CoreRPG/Model/FolderListModel.swift:36,37,41`; `CoreRPG/Sheet/SheetRootModel.swift:12`; `GameRPG/Controller/PreviewData.swift:210,215`; `CoreRPG/Text/OnboardingEmphasisAttribute.swift:95,122`; `Sources/MasterRPG/PackageProducts.swift:1-21` (hardcoded StoreKit ids, no callers); `Sources/MasterRPG/macOS/LinkWindowCommandsView.swift:1-36` (self-preview only)
- **What:** Each is declared and never referenced (single-occurrence identifiers across the repo).
- **Why:** Individually cheap, collectively noise.
- **Action:** Delete; a build flags any protocol witness that was missed.
- **Severity:** Low

### 9.8 Test doubles live in production sources
- **Location:** `Modules/GameRPG/Master/MasterNetworkModel.swift:65-226`; `Player/PlayerNetworkModel.swift:80-203`; `Network/ConnectionController.swift:159`
- **What:** Spy/stub classes sit in framework sources under `#if DEBUG`; three are unreferenced, and `Tests/GameRPGTests/Mocks` defines a parallel family.
- **Why:** ~230 LOC of dead debug code and two competing test-double families.
- **Action:** Delete the three unreferenced stubs; move the used ones into `Tests/GameRPGTests/Mocks`.
- **Severity:** Low

### 9.9 Master/Player Photo, Pdf and Space message handlers are copy-pasted and have drifted
- **Location:** `Modules/GameRPG/Controller/MasterController+PhotoMessages.swift:1-169` vs `MasterController+PdfMessages.swift:1-169` (and `+SpaceMessages.swift:1-221`); `PlayerController+Photo.swift:1-217` vs `PlayerController+Pdf.swift:1-216` (and `+Space.swift:1-310`)
- **What:** After swapping the module name the Master Photo/Pdf handlers differ in only 36 changed lines (re-verified), the Player ones in ~91; Pdf guards on `hasLocalFileData` at four points while Photo gates on `features.photoSharing`, and comments have diverged.
- **Why:** A fix to reveal/store/update/`.itemMissing` handling must be hand-applied in three places, and a missed copy is a silent behavior difference in network code with a history of lost-message bugs (and the site of §5.1's `updateGame` call).
- **Action:** Extract a generic file-module message handler in GameRPG parameterized by module root, feature flag and availability check; keep only module-specific steps (Space transform validation) separate.
- **Severity:** Medium (highest-priority duplication)

### 9.10 Foundry package data-source and directory walker exist twice
- **Location:** `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:320-372,440-470` (`FoundryPackageDataSource`, `directoryPaths`) vs `Modules/CoreRPG/Foundry/FoundryVTTDataSource.swift:7-140`; duplicate `CharacterSet` literals at `FoundryVTTImportReader.swift:888` and `FoundrySystemCompendiumDecoding.swift:268`
- **What:** Both are the same archive/directory enum with the same symlink-safe enumerator, root-prefix escape check, `.tooManyDocuments` guard and `data(forPath:)` containment check; they have already drifted (`selectedPath` handling, `maximumArchiveSize` vs `maximumEntrySize`).
- **Why:** This is path-escape defense; a hardening fix in one copy leaves the other exposed. `CODE_AUDIT_14` §9.1–9.5 unified other helpers but not this pair.
- **Action:** One shared internal source type (optional `selectedPath`) and one `directoryPaths` walker in CoreRPG/Foundry.
- **Severity:** Medium

### 9.11 Per-module Controller/Route boilerplate that differs only by module name
- **Location:** `FolderListController.swift` (12 modules, ~367 LOC); `Route/DetailRoute.swift` (9 modules, ~55 LOC each); `SyncDataController.swift` (12 files); `PhotoSnapshot` vs `SpaceSnapshot` (zero diff after rename); `Model/MockData.swift` (13 files, ~811 LOC); `Root/ModuleConfiguration.swift`
- **What:** Photo/Space/Map/Character `DetailRoute.swift` are identical after a name substitution (0–2 diff lines), as are Audio/Pdf `FolderListController`.
- **Why:** ~1,900 LOC of copy-paste; earlier audits genericized Edit/Import/Search controllers but not these siblings, so a routing change touches 9–12 files.
- **Action:** Extend the generic-controller approach: generic `FolderListController`, shared `DetailRoute`/`ViewerRouteDestinationView`, one generic `SyncDataController`, shared preview `MockData` scaffold.
- **Severity:** Medium

### 9.12 `DataController.mapSnapshot`/`applySnapshot` copied ~11 times
- **Location:** `Modules/{Audio,Pdf,Photo,Space,Table,Weather,Dice,Character,Map,Adventure,Rule,Generator}RPG/Controller/DataController.swift` (87–256 lines each; e.g. `AudioRPG/.../DataController.swift:23-70`)
- **What:** Every module repeats the same field mapping (uuid, name, information, tags, category default, displayState, `fileUrl` with `fileUrlUpdate`, entries via `syncEntries`, parentId).
- **Why:** A new common field (like the recent CRDT `fileUrlUpdate`) must be added in ~11 files; the copies already diverge (uuid-repair exists in Pdf only).
- **Action:** Move the common-field mapping into a CoreRPG helper; modules keep only extra fields and entry mappers.
- **Severity:** Medium

### 9.13 `LinkController.toggleTextLink` / `validateLinks` copy-pasted with drift
- **Location:** `Modules/{Audio,Pdf,Photo,Space,Weather,Dice,Map,Table}RPG/Controller/LinkController.swift` (e.g. Photo `:16-40,49-58`; Audio `:50-55`; Weather `:25-35`); `standardToggleResult` at `Modules/CoreRPG/Controllable/LinkControllable.swift:233-251` is adopted only by Photo and Space
- **What:** Six modules hand-inline the `standardToggleResult` body; between copies the share branch differs (`try?` vs do/catch-log), visibility checks differ (`displayState != 2` in 7 modules vs `!isHidden` in Space), and log privacy/levels differ.
- **Why:** Behavioral drift in user-visible link behavior.
- **Action:** Route all modules through `standardToggleResult` with a hook for module-specific `.play`/`.show`; use one `validateLinks`/`repairLinks` template.
- **Severity:** Medium

### 9.14 App Intents boilerplate repeated across 11 modules (~4,000 LOC)
- **Location:** `Modules/*/Intent/*ManagementIntents.swift` (11 files, 1,970 LOC); `Open*Intent.swift` (680 LOC); `*Entity.swift` (1,664 LOC); `*ShortcutCatalog.swift` (~90 LOC each)
- **What:** After renaming, Photo vs Space ManagementIntents differ in ~35 lines and Photo vs Weather in ~19; five `*EntityAssetUnavailableError`/`*PdfRenderError` structs are identical.
- **Why:** Contract changes (e.g. repeated `#available(iOS 27, …)` guards) must change in lockstep.
- **Action:** Push shared logic into CoreRPG helpers (`IntentEntityHelpers.swift` exists) so each module supplies a small config and thin concrete intent types.
- **Severity:** Medium

### 9.15 Hand-written markdown link construction in 8+ places
- **Location:** `Modules/CoreRPG/Model/LinkDataTransferable.swift:17,19`; `Links/LinkRegisterListModel.swift:70`; `ItemList/EntryDataEditable.swift:135`; `ItemList/ItemDataAccessable.swift:132`; `CharacterRPG/Controller/EditController.swift:153`; `RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+SharedHelpers.swift:346`; `PhotoRPG/Model/PhotoModel.swift:257`; `AudioRPG/Model/AudioModel.swift:243`; `CoreRPG/Widget/ContentWidgetSnapshot.swift:63,67`
- **What:** Each site builds the `[name](RPG://token/linkNumber/itemId[/entryId][/command])` string inline; the Foundry copy escapes `[ ] \` while the others don't.
- **Why:** The link grammar is documented nowhere in code; a grammar change needs 8+ edits.
- **Action:** One `LinkBuilder`/URL-string factory in CoreRPG (item, entry, command variants); keep the intentional Photo/Audio override.
- **Severity:** Medium

### 9.16 Magic integers for `displayState` at 54 non-test sites
- **Location:** `Modules/CharacterRPG/Controller/EditController+Repair.swift:18,27,31`; `Modules/CoreRPG/Controllable/EditControllable.swift:185,189,205,219,239,545,559,627`; `CharacterRPG/Controller/SearchController.swift` (7); `CoreRPG/Controllable/SearchControllable*.swift` (7); `{Pdf,Dice,Photo,Map,Weather}RPG/Controller/LinkController.swift`; `CoreRPG/Widget/ContentWidgetSnapshot.swift:46`
- **What:** Code compares `displayState == 0/1/2` although `DisplayStateMask` (`CoreRPG/Model/ItemListable.swift:7-13`) and `isHidden` (`:35`) exist; 99 more in tests.
- **Why:** Mask semantics are unreadable at the call site and `== 2` vs `& mask` checks can disagree.
- **Action:** Add `isVisible`/`isGroupHiddenOnly` helpers beside `isHidden` and migrate call sites.
- **Severity:** Medium

### 9.17 Security-scoped resource acquire/release hand-rolled ~25 times
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:29,91,195`; `FoundrySystemPackageReader.swift:22,73`; `UniversalVTTReader.swift:166,188`; `Import/ExternalImportSourceRegistry.swift:601`; `Files/FileUrlDataController.swift:150,210,249,312,562`; `Files/FileManager+Coordination.swift:104,186,187`; `Controllable/{EditControllable:656,ImportControllable:271,ExportControllable:226}.swift`; `RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:97`; `RolePlayGameKit/Model/AppModel.swift:442`; `SpaceRPG/Space/SpaceViewer.swift:501`; `PhotoRPG/Space/Spatial3DImageState.swift:46`
- **What:** Each site writes its own `startAccessing…`/`defer { stop… }`; about half discard the return value and ~8 have no matching stop nearby.
- **Why:** A missed stop leaks the scope; discarded results silently run without access on failure.
- **Action:** Add a `URL.withSecurityScopedAccess { }` helper (sync and async) in CoreRPG and migrate the sites.
- **Severity:** Medium

### 9.18 Oversized files and long functions
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift` (1,314); `SpaceRPG/Space/SpaceViewer.swift` (1,119, grown from 965; `loadEntity` `:479-710` is 231 lines); `GameRPG/Controller/PlayerControllerModel.swift` (1,065, one class, no extensions); `GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift` (939; `sendData` `:24-306`); `GameRPG/SharePlay/RPGSharePlayController.swift` (924); `GameRPG/Root/GameRootModel.swift` (910, two types); `CoreRPG/Foundry/FoundrySystemPackageReader.swift` (835); `FoundryRuleModels.swift` (829); `CoreRPG/Controllable/EditControllable.swift` (816); `ImportControllable.swift` (754); `RolePlayGameKit/Import/Foundry/FoundryImportView.swift` (720); 31 non-test files exceed 500 lines. Longest functions: `GameRPG/Controller/PlayerController+Map.swift:20` `handleMap` (313); `GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:175` `configureGroupSession` (252); `CoreRPG/Import/ExternalImportReviewSession.swift:95` `commit` (239); `MapRPG/Map/EditMapToolBar.swift:30` `body` (223); `CoreRPG/Foundry/FoundryVTTBridgeDecoding.swift:205` `decodeContents` (196); `GameRPG/Controller/MasterController+SpaceMessages.swift:20` `handleSpace` (185); `GameRPG/Network/GameNetworkController+SharePlayDelegate.swift:89` `routeSharePlayUpdate` (181). 35 functions exceed 100 lines.
- **What:** The `RPGSharePlayController.swift` split flagged in `CODE_AUDIT_14` §9.7 (2,635 lines) is done (now 924 plus `+*` files); `SpaceViewer` and `PlayerControllerModel` keep growing.
- **Why:** Hard to test/review; the network handlers listed are where the audit history shows lost-message bugs.
- **Action:** Split by existing MARKs (`GameRoot` → its own file; `PlayerControllerModel+Map/+Journal/+Reveal.swift`; `SpaceViewer+Immersive/+Handoff/+Loading.swift`); break the 250+ line functions into phase helpers.
- **Severity:** Medium

### 9.19 App-group `UserDefaults` recreated at six sites
- **Location:** `Modules/CoreRPG/Widget/ContentWidgetSnapshot.swift:34,57`; `Persistence/PersistentHistoryTrackerManager.swift:89,109`; `Modules/DiceRPG/Widget/DiceConfiguration.swift:32,38`; shared accessor `UserDefaults.appGroup` at `Modules/CoreRPG/App/AppGroup.swift:13`
- **What:** Six sites construct `UserDefaults(suiteName:)` independently; `AppGroup.appGroup` is `@MainActor`, probably prompting the workaround, and nil-fallback policy diverges (`?? .standard` in one).
- **Why:** Duplicated lookup and inconsistent fallback.
- **Action:** Provide a `nonisolated` accessor (`UserDefaults` is thread-safe) and use it everywhere.
- **Severity:** Low

### 9.20 Repeated magic limits and identifiers
- **Location:** `Modules/GameRPG/Network/GameProtocol.swift:41` and `SharePlay/SharePlayJournalPublicationQueue.swift:92` (both `512_000_000`; a comment says they "match" but nothing enforces it); `SharePlayPackageReceiver.swift:40`, `SharePlayPlayerJournalAdmission.swift:141`, `Network/GameRelayAdmission.swift:39` (three separate `.seconds(120)` windows); `CoreRPG/Cache/ObjectCache.swift:20` (`256_000_000`); bundle id `de.andretrettin.gamemaster` in `CoreRPG/Debug/Logging.swift:7` and `Persistence/RpgSpotlightIndexerDelegate.swift:38`; AppStorage keys `lastSelectedGameType`/`lastAdventureUUID` each in two views
- **What:** Values that must stay equal are repeated as literals.
- **Why:** Changing one silently desynchronizes the others.
- **Action:** Name each once (e.g. a shared game-limits type) and reference it.
- **Severity:** Low

### 9.21 Preview/mock/fake data compiled into release frameworks
- **Location:** `Modules/CoreRPG/Fake/` (20 files, 962 LOC, only 3 under `#if DEBUG`); `Modules/*/Model/MockData.swift` + `PreviewData.swift` (~3,880 LOC); `CoreRPG/Fake/TestFixtures.swift:1-64` (unreferenced)
- **What:** `Fake*` controllers, `PreviewFixtureLoader` and every module's mock/preview data compile unguarded into shipping binaries, and `Fake` types are visible in public module API.
- **Why:** ~4,800 LOC of release dead weight.
- **Action:** Wrap in `#if DEBUG` or move to a preview-support target; delete `TestFixtures.swift`.
- **Severity:** Low

### 9.22 Unresolved TODOs and stray `print`
- **Location:** TODO at `Modules/CharacterRPG/Controller/EditController+Repair.swift:178` and `Modules/CharacterRPG/View/DetailEditorView.swift:14`; `print(` at `Modules/GeneratorRPG/View/PdfSummaryAnalysisView.swift:176` (shipping) and `Modules/CoreRPG/Fake/PreviewFixtureLoader.swift:25` (preview)
- **What:** Only two TODO markers and two `print` calls remain; no HACK/FIXME/`#warning`, no `#if false`.
- **Why:** Confirms these categories are clean.
- **Action:** Resolve the two TODOs; replace the shipping `print` with `Logger`.
- **Severity:** Low

### 9.23 Typos in public and file names
- **Location:** `Modules/CoreRPG/Buttons/BorderLessTVBottonStyleViewModifer.swift` (`Botton`, `Modifer`; `borderLessTVBottonStyle` has 35 call sites); `App/AppToolBarAppearenceViewModifier.swift`; `ViewModifiers/NavigationVisibility.swift` (`NavigationVisibiltyViewModifier`); `LGViewModifiers/SearchItemListViewModifier.swift:72` (`searchScopeActivition`); `ItemList/EntryDataEditable.swift:132` (`nextLinkNumer`); `Buttons/RoundGlassButtonstyle.swift`; `Tests/GameRPGTests/Mocks/GameListnerMocks.swift`
- **What:** Misspelled type, function, variable and file names in CoreRPG API.
- **Why:** Cosmetic, but the misspellings are public API and get copied.
- **Action:** Rename in one Xcode refactor commit.
- **Severity:** Low

### 9.24 Test-target helper duplication
- **Location:** `Tests/*/MockRoot.swift` (8 files); `makeRoot()` 25 times (e.g. `Tests/PhotoRPGTests/FolderListControllerTests.swift:25`); `expectApproximately` in `ImageViewportGeometryTests.swift:345`, `ViewportGeometryTests.swift:288`, `MapEditorViewportTransformTests.swift:875`; `appendLittleEndian` in 6 files; snapshot fixture-cache enum repeated in ~20 generated files; `ConcreteFolderListControllerTests.swift` in 11 modules
- **What:** The same setup/helper code is copied per module or file.
- **Why:** More places to update when a root-model init or byte helper changes.
- **Action:** Move helpers into `Tests/SnapshotTestSupport`, generate `MockRoot` from a CoreRPG test-support protocol, fold the `Concrete*` tests into one parameterized suite.
- **Severity:** Low

### 9.25 Source comments cite audit documents by ambiguous section number
- **Location:** 919 occurrences across 491 files in `Modules/` and `Sources/` (e.g. `Modules/CoreRPG/Navigator/Extensions/LazyState.swift:30`); 511 are the bare form `CODE_AUDIT §x.y`
- **What:** With 14 numbered audits plus per-topic ones, "see CODE_AUDIT §9.14" cannot be resolved without guessing, and it couples source to `Docu/` files that may be renamed or pruned.
- **Why:** Rationale is effectively lost when the audit docs are rotated.
- **Action:** Fold the rationale into the comment or use the full document name.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Treat every peer/import-supplied model as untrusted at one choke point.** §5.1, §5.2, §5.3, §6.3 and §5.9 share a root cause: item JSON from `.gmz` files and from players is decoded and then applied with the same trust as local edits. Add a single "untrusted import" validation layer (path/URL sanitisation, id allow-list, timestamp clamping, size caps) in `ImportControllable`/`GameControllable.updateGame` that the game handlers and the file importer both pass through, and import peer data into game memory unless the GM confirms.
2. **Harden the join secret and connection admission together.** §6.1, §6.2 and §6.4 make the LAN listener the weakest link. A longer per-session secret, per-listener connection caps and frame-size budgets shrink the reach of every other network finding.
3. **Give file coordination and heavy I/O a dedicated execution model.** §3.1, §3.3 and §3.12 all stem from synchronous, blocking work running on the cooperative pool or the caller's (main) actor. One bounded I/O executor plus consistent `@concurrent` decode/hash helpers would fix all three and match the SharePlay path's existing off-main approach (§3.2).
4. **Make persistence writes atomic and failure-aware.** §5.4, §5.5, §5.6 and §5.7 share the pattern "log the error, continue, overwrite the good copy". Adopt atomic writes, keep-on-decode-failure, and propagate save errors as a repo rule for the file/Core Data layer.
5. **Finish the generic-controller consolidation.** §9.9–§9.15 are the same story the earlier audits started (`GenericEditController` etc.): ~7,000 LOC of per-module near-duplicates that have already drifted. Consolidating the network file-module handlers (§9.9) first has the best risk/benefit.
6. **Replace time-based synchronization with readiness signals.** §3.6, §3.7, §3.8 and §3.10 show ordering assumptions expressed as sleeps, unordered task-per-callback delivery and re-arm-after-cancel gaps. Prefer ordered `AsyncStream`s, generation tokens and explicit "mounted" signals.
7. **Delete the ~3,000 LOC of verified-dead code in one commit series** (§9.1–§9.7, §4.2) and add a periodic identifier-frequency scan to catch new dead API early.
8. **Wire `verify_localization.rb` into CI** (§8.5); the accessibility verifier already passes and is doing its job.

---

## 11. What was NOT audited

- **macOS, tvOS and visionOS builds were not run.** Only the `MasterRPG` iOS Simulator build produced compiler ground truth; `#if os(macOS/tvOS/visionOS)` branches (notably visionOS in `Modules/GameRPG/Table3D`, `SpaceViewer`, `ImagePresentationView`) were read by eye. Findings §3.8 and §3.11 are from those unbuilt branches.
- **Uncommitted in-progress work.** `Modules/GameRPG/Table3D/*` and related GameRPG files were modified in the working tree at audit time; they were treated lightly and `Docu/CODE_AUDIT_3dTable.md` (untracked) was not re-verified.
- **Open items in `CODE_AUDIT_Network.md`** (e.g. §5.1 `SharePlayDeferredDeliveryQueue`) were not re-verified; only follow-ups discovered independently are reported (§3.6, §3.7).
- **Files only sampled, not read line by line:** `PlayerControllerModel.swift`, `EditControllable.swift`, and the remainder of `RPGSharePlayController+ChunkedTransport.swift` (task/continuation greps only).
- **Runtime behavior.** No Instruments traces, no two-device CloudKit test (§5.8 unverified), no on-device verification of share-extension memory (§7.1, §7.2), and §5.1 was verified by code trace plus a scratch test of URL semantics rather than by exercising the running app.
- Algorithmic correctness of domain code (dice math, fog-of-war geometry, Foundry compendium normalisation) beyond obvious issues; Metal kernels do not exist.
- Build settings / Xcode project structure beyond what is visible in shared schemes; `Docu/xcode-security-*.md` were not reviewed.
- Third-party SPM dependency internals (`swift-syntax`, `swift-snapshot-testing`, `RPGTabletopGameContent`, and others).
- Tests under `Tests/` — dead-helper and duplication scan only; no coverage review.
- Localization wording (only completeness was checked, §8.5); accessibility beyond the repo's own verifier.
- StoreKit product configuration and App Store Connect matching (`PackageProducts.swift` is unreferenced, §9.7).
- App Intents / widget extension entitlements were not opened individually beyond the per-configuration `aps-environment` split already documented.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line. Each Critical/High finding has an exact line range.

For the Critical and High items, these are the lines that prove the claim:

- **§5.1 (Critical)** — open `Modules/CoreRPG/Files/CloudDocumentController.swift`, lines `71-87`: `fullUrl(fileUrl:)` appends every path component of the URL (including `..`) onto `moduleUrl` with no containment check; `:89-91` `fullUrl(filePath:)` appends again; `:262-265` shows `moduleUrl` is `<root>/Documents/<module>`. Then `Modules/CoreRPG/Files/FileUrlDataController.swift`, lines `292-298`: `createNewFileUrl` feeds the unvalidated `unconvertedFileUrl.rawUrl` through those functions and writes the peer's bytes. The peer entry point is `Modules/GameRPG/Controller/MasterController+PhotoMessages.swift:95` → `Modules/CoreRPG/Controllable/GameControllable.swift:399-406` → `ImportControllable.swift:153` → `:588`. The decoded URL keeps `..` because `FileUrl` (`Modules/CoreRPG/Files/FileUrl.swift:6-66`) stores whatever URL the JSON contains.
- **§5.2 (High)** — open `Modules/CharacterRPG/Controller/GameController+Sync.swift`, lines `54-58` (`updatePlayer` → `importNetwork(from:forceSave: true)`), then `Modules/CoreRPG/Controllable/ImportControllable.swift`, lines `139-176` (each stream item goes to `addItem(importedItem:id: newItem.id…)`); nothing compares those ids with `characterId` checked at `MasterController+ValueMessages.swift:84-85`.
- **§5.3 (High)** — open `Modules/CoreRPG/CRDT/WallclockTimestamp.swift`, lines `59-71`: ordering is `(clock, id)` from a decoded or `Date()`-derived `TimeInterval` with no clamp or observed-clock advance.
- **§6.1 (High)** — open `Modules/GameRPG/Network/GameJoinCodeModel.swift`, lines `99-103` (10,000-value keyspace) and `:172` (`codeLength = 4`); `Modules/GameRPG/Network/ConnectionAttemptThrottle.swift`, lines `45-64` (`shouldAllow` only reads `lockedUntil`, set by `recordFailure` after a failed attempt, keyed per host).
- **§3.1 (High)** — open `Modules/CoreRPG/Files/FileManager+Coordination.swift`, lines `90-101`: each coordinated call is a `Task.detached` wrapping a blocking `coordinate`, and `onCancel` merely cancels the task.
- **§6.2 (Medium, memory-safety)** — open `Modules/GameRPG/Network/NWParameter+GameMaster.swift`, lines `85-93`: `withUnsafeBytes(of: stringData)` views the `Data` value itself, then a buffer of `stringData.count` is built from its base address.
- **§3.2 (Medium)** — open `Modules/GameRPG/Network/GameNetworkController+MasterDelegate.swift:29` (decode inside a `@MainActor` type), `Modules/GameRPG/Model/GameMessagePipeline.swift:269-281` (plain synchronous decode/encode), `Modules/GameRPG/Master/MasterNetworkController.swift:147,155,168`.
- **§9.1, §9.2, §9.5, §9.6 (dead-code, re-verified)** — no references outside `CoreRPG/Navigator` to `NavigationCheckpoint`/`returnToCheckpoint`/`NavigationFlow`; `find . -name '*.metal'` returns nothing while `HarmonicButton`/`variableBlur` call a shader library; `ChatViewModel` and `SwiftDataController` appear only in their own files (plus a test for the latter).
- **§9.9 (duplication)** — `diff` of `MasterController+PhotoMessages.swift` vs `MasterController+PdfMessages.swift` after normalising the module word differs in 36 lines.
- **§8.5 (localization)** — run `ruby Scripts/verify_localization.rb`; it reports 162 issues (~95 missing German, ~250 stale keys).
- **Compiler baseline** — a clean `xcodebuild -workspace MasterRPG.xcworkspace -scheme MasterRPG -destination 'generic/platform=iOS Simulator' build` finished `BUILD SUCCEEDED` with no Swift warnings.

If any finding doesn't reproduce when you visit the line, ping me with the specific reference and I'll re-investigate.

---

## 13. Remediation status (2026-09-21)

Status of every numbered finding after the remediation pass. **Fixed** = changed and built on iOS, macOS, tvOS and visionOS with zero warnings; unit tests pass except the pre-existing `ExternalImportTests` race (a static commit-in-progress flag under parallel tests, verified identical on the untouched baseline). Regression tests were added for §5.1, §5.2, §5.3, §5.11, §6.1 (handshake caps), §6.3, §9.15. Items marked *not runtime-verified* need a manual check on device.

| § | Status | Notes |
|---|---|---|
| 3.1 | Fixed | Coordinated file access is capped by a cancellable limiter (never more than `cores-1`, max 4, blocked threads). |
| 3.2 | Fixed | LAN decode/encode run `@concurrent`. Relaying the original bytes instead of re-encoding was not done. |
| 3.3 | Fixed | `importNetwork` is `@concurrent`; block reads are chunked (no up-front 512 MB allocation). |
| 3.4 | Fixed | `isolated deinit` in the four Navigator classes. |
| 3.5 | Partly | Call-site file/line now reach `assumeIsolated`; the runtime-trap contract itself remains by design. |
| 3.6 | Fixed | Ordered `AsyncStream` state delivery, one terminal outcome, no report after a local cancel. |
| 3.7 | Fixed | Generation token on listener runs. |
| 3.8 | Fixed | Observation re-armed before scheduling. visionOS; *not runtime-verified*. |
| 3.9 | Fixed | Cancellation no longer triggers an immediate cleanup. |
| 3.10 | Deferred | Needs per-window "mounted" readiness signals on macOS/visionOS; not safe to change blind. |
| 3.11 | Deferred | visionOS-only view-state rework; needs on-device validation. |
| 3.12 | Fixed | `createNewFileUrl`/`createFileUrl` are `@concurrent`. |
| 3.13 | Fixed | Ordered, lock-serialized Keychain write buffer. |
| 3.14 | Fixed | Serialized widget write; an older roll cannot overwrite a newer one. |
| 3.15 | No change | Verified: `handleTextLink` runs only on a link tap, so the task fires once per tap. |
| 3.16 | Fixed | Redundant `@unchecked Sendable` removed from the `@MainActor` classes. |
| 3.17 | Fixed | Global `KeyPath` conformance removed; two key-path captures fixed properly. |
| 4.1 | n/a | Informational. |
| 4.2 | Fixed | Dead OS branch, deprecated shims and unused dismiss triggers removed. |
| 4.3 | No change | UIKit-only image crop, rule does not apply. |
| 4.4 | Fixed | PDF load cancellation forwarded. |
| 5.1 | Fixed | Traversal components dropped at every builder; import normalises every decoded `FileUrl`. Tests added. |
| 5.2 | Fixed | `PeerImportPolicy`: a peer may write its own item, items it introduced and new items only, capped in size. |
| 5.3 | Fixed | Hybrid logical clock (`MonotonicWallClock.observe`) on every merge; non-finite clocks rejected at decode. |
| 5.4 | Fixed | Store files destroyed together; transient errors are not offered the destructive recovery. |
| 5.5 | Fixed | Atomic writes, corrupt file kept aside, coalesced saves. |
| 5.6 | Fixed | Failures propagate; queue restored on failure; the surviving duplicate is chosen deterministically (not "newest"). |
| 5.7 | Fixed | Framing errors fail the import, failed items are counted and shown, export writes a temp file then replaces. |
| 5.8 | Fixed | Links/tags written through the context instead of batch requests. *Not verified on two devices.* |
| 5.9 | Partly | Implausible rolls are refused (size, dice count, sum bounds). Rolling on the master is a design change. |
| 5.10 | Fixed | |
| 5.11 | Fixed | Count clamp and saturating arithmetic. Tests added. |
| 5.12 | Fixed | |
| 5.13 | Fixed | |
| 5.14 | Fixed | macOS build verified. |
| 6.1 | Partly | Pending-handshake caps (16 total, 3 per source) and a 32-connection cap added. **The 4-digit secret is unchanged: lengthening it changes the join UI, stored codes and cross-version compatibility, which needs a product decision.** |
| 6.2 | Fixed | |
| 6.3 | Fixed | Peer-supplied `.url` items must be public hosts; downloads capped at 256 MB. A GM's own imports may keep LAN hosts. Explicit GM approval before fetching was not added. |
| 6.4 | Deferred | A real fix needs chunked large-payload transport on the LAN path (protocol change). |
| 6.5 | Fixed | User content in logs is `.private`. |
| 7.1 | Fixed | Files downsampled from disk, downloads to disk with an image-type check and size caps. |
| 7.2 | Deferred | Opening the store without CloudKit options in the extension needs on-device verification of history-based export. |
| 7.3 | Fixed | Archives decoded one at a time. |
| 7.4 | Fixed | Snapshot publishing debounced (750 ms). |
| 8.1, 8.3 | n/a | Informational. |
| 8.2 | No change | Documented exception (gesture extension in another file). |
| 8.4 | Not done | Style guideline, Low. |
| 8.5 | Partly | 88 missing German strings translated. ~250 stale keys remain: refresh the catalogs in Xcode (deleting them blindly could drop dynamically-looked-up translations). |
| 9.1–9.3, 9.5, 9.6 | Fixed | Navigator checkpoints/flow, blur/shader files, CustomBars, `ChatViewModel`, `SwiftDataController` removed. Stale snapshot roots removed; the snapshot test target compiles again. |
| 9.4 | Partly | 10 verified-dead files removed. Three the audit listed (`SheetFullScreenModifier`, `TabBarMinimizeBehavior26`, `GameOverlayTabViewModifier`) are still used and were kept; dead functions inside live files were not pruned. |
| 9.7 | Mostly | 22 single-occurrence dead members plus `PackageProducts.swift` and `LinkWindowCommandsView.swift`; members with more than one reference were left. |
| 9.8 | Fixed | Used spies moved to the test target, unreferenced ones deleted. |
| 9.9 | Deferred | The Photo/Pdf handlers differ in real guards (`photoSharing` vs `hasLocalFileData`); unifying needs a per-module behavior decision. |
| 9.10 | Fixed | One shared package data source and path encoder. |
| 9.11, 9.12, 9.14 | Deferred | Large per-module consolidations (~7,000 LOC); need their own change set. |
| 9.13 | No change | The shared tail is already centralized; remaining differences are intentional (per-module link types and content lookups). |
| 9.15 | Fixed | `LinkBuilder`; tests added. |
| 9.16 | Fixed | 54 comparisons use `DisplayStateMask` names. |
| 9.17 | Fixed | `SecurityScopedAccess` keeps start/stop balanced; the unbalanced sites were a latent bug. |
| 9.18 | Partly | `GameRoot` split out of `GameRootModel.swift`; other files unchanged. |
| 9.19 | Fixed | |
| 9.20 | Partly | Message limit and `@AppStorage` keys named once; retention windows left. |
| 9.21 | Deferred | Needs a Release-configuration check. |
| 9.22 | No change | The `print` is inside `#if DEBUG` in a `#Preview`; not shipping code. |
| 9.23 | Fixed | |
| 9.24, 9.25 | Deferred | Test-helper consolidation and rewriting 919 audit citations in comments. |

