# MasterRPG Code Audit

Generated 2026-09-21 (17th audit). Scope: 2,103 Swift files (~272k LOC; ~195k LOC of production code in `Modules/` and `Sources/`, ~77k LOC of tests) across the MasterRPG, MasterMac, MasterTV, RPGShare and DiceRollerWidget targets and 15 modules. No Metal/other kernels exist. `Docu/`, `Snapshots/`, `.git`, `.build` and `DerivedData` are excluded; `Tests/` got quick reads only. No `Dead/` folder exists.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code was changed.

**Ground truth.** A clean full build of the `MasterRPG` scheme (`generic/platform=iOS Simulator`, Debug, Swift 6 mode, `SWIFT_STRICT_CONCURRENCY = complete`) produced **zero Swift compiler warnings** (only two "AppIntents metadata extraction skipped" tool notices). So the concurrency findings below are things the compiler cannot see: lifecycle, ordering, cancellation, reentrancy. macOS, tvOS and visionOS were not rebuilt and no tests were run.

**Relationship to earlier audits.** Sixteen earlier audits live in `Docu/CODE_AUDIT_*.md`. `CODE_AUDIT_16` §13 lists what its remediation pass fixed; the agents were told to skip those and to re-verify what it listed as "Not done". Items still open from it are tagged *(previously reported CODE_AUDIT_16 §X.Y)*.

**Result in one line.** No finding survived verification as Critical. The strongest are five High items: one data-loss hazard in database re-setup (§5.1), lost edits on quit (§5.2), two peer-abuse holes on the GM device (§6.1, §6.2), and a freeze in the tvOS demo (§3.1). The audit agent had rated §5.1 Critical; I demoted it (see §12).

**How to read severity and verification.** **[verified]** means I re-read the cited lines myself after an agent reported them (§12). Items without the tag were opened by the agent that reported them but not independently re-read; treat their line numbers as reliable and their severity as the agent's conservative estimate. Where I disagreed with an agent's severity I say so in the finding.

---

## 1. Executive summary

Top items to address, in priority order:

1. **[High] Re-running root-model `setUp` reconciles against a new store and deletes the binary files of every item missing from it** — §5.1 — `Modules/CoreRPG/Controllable/ItemControllable.swift:415-431`. A store switch or a failed fetch can wipe photo/PDF/audio/3D files. **[verified]**, latent, not reproduced at runtime.
2. **[High] Edits are queued in memory for up to 60 s and the exit save is an unprotected async hop** — §5.2 — `Modules/CoreRPG/App/AppExitNotificationsViewModifier.swift:17-58`. Cmd-Q or a jetsam kill loses recent edits. **[verified]**
3. **[High] A joined player can overwrite any GM-owned character by claiming its id** — §6.1 — `Modules/GameRPG/Controller/MasterController+ValueMessages.swift:50-90`, `Modules/CoreRPG/Controllable/ImportControllable.swift:37-47`. **[verified]**
4. **[High] The 512 MB frame ceiling lets one joined peer push the GM into jetsam** — §6.2 — `Modules/GameRPG/Network/GameProtocol.swift:35-47`, `GameNetworkController+MasterDelegate.swift:28-51`. **[verified]**
5. **[High] The tvOS/App-Review demo loop spins the main actor forever when the library has no photos, weathers or maps** — §3.1 — `Modules/GameRPG/Root/GameRoot.swift:538-608`. **[verified]**
6. **[Medium] Any player can request or force-reveal any library item by UUID** — §6.3 — `Modules/GameRPG/Controller/MasterController+PhotoMessages.swift:33-36,124-125`. **[verified]**
7. **[Medium] After a lost connection the player re-opens master pinning to whoever sends the first full master broadcast** — §6.4 — `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:61,272-279`. **[verified]**
8. **[Medium] A failed link/tag save rolls back every module's already-flushed edits and drops its own pending set** — §5.5 — `Modules/CoreRPG/Links/LinkRegisterController.swift:162-201`. **[verified]**
9. **[Medium] CODE_AUDIT_16 §5.3 is only partly fixed: Dice and Rule entity queries skip the database-readiness gate** — §3.2 — `Modules/DiceRPG/Intent/DiceEntity.swift:143-160`.
10. **[Medium] Hex-grid generation traps on a map with zero width/height** — §5.16 — `Modules/MapRPG/Map/MapHexGridGeometry.swift:23-56`. **[verified]**

---

## 2. Quick wins (≤30 min each)

- **Add a suspension point and an "empty library" exit to the demo loop** — `Modules/GameRPG/Root/GameRoot.swift:548` (§3.1).
- **Call `DatabaseReadiness.wait()` at the top of both entity-query overrides** — `Modules/DiceRPG/Intent/DiceEntity.swift:143`, `Modules/RuleRPG/Intent/RuleEntity.swift:85` (§3.2).
- **Log the join-code check value, pin names and SharePlay participants as `.private`** — `Modules/GameRPG/Network/NWParameter+GameMaster.swift:26-34`, `Table3D/GameTableProjection.swift:187,203`, `SharePlay/RPGSharePlayController+SessionLifecycle.swift:329` (§6.11).
- **Clamp player names on receipt (e.g. 64 characters)** — `Modules/GameRPG/Root/GameRootModel.swift:74-109` (§6.9).
- **Guard `grid(for:in:)` against non-positive size or map dimensions** — `Modules/MapRPG/Map/MapHexGridGeometry.swift:23` (§5.16).
- **Sanitize non-finite audio durations when building `PlaylistItem`** — `Modules/AudioRPG/Audio/AudioPlayerView.swift:222-244` (§5.25).
- **Filter soft-deleted items in `ItemEntityQuery.include`** — `Modules/CoreRPG/Controllable/ItemEntityQuery.swift:65-113` (§5.12).
- **Delete the two never-compiled widget files and the two stale project exceptions** — `Sources/DiceRollerWidget/DiceRollerView.swift`, `DiceRollerWidgetConfiguration.swift`, `MasterRPG.xcodeproj/project.pbxproj:1886-1896` (§9.1).
- **Delete `ExportedRPGData`/`RPGJsonFile`, both `StoreManipulable` declarations, the empty `registerRealityKitComponents()`, and `Scripts/print_wan_ip.sh`** (§9.2, §9.6).
- **Switch the seven per-module filters to `localizedStandardContains`** — `Modules/AudioRPG/Model/AudioModel.swift:200` and six more (§4.2).
- **Make `AGENTS.md` a pointer to `CLAUDE.md`** so agents that read it see the Table3D rules (§9.18).
- **Delete the sixteen single-line commented-out statements** listed in §9.5.

---

## 3. Concurrency

### 3.1 The tvOS/App-Review demo loop never yields when the library is empty **[verified]**
- **Location:** `Modules/GameRPG/Root/GameRoot.swift:538-608` (loop head at `:548`); caller `Modules/GameRPG/SetupViews/SearchProxyView.swift:28-31`
- **What:** `demoTask` runs `while !Task.isCancelled && state != .stopped`. The `for` loops over photos, weathers and maps only suspend inside their bodies, so with all three collections empty an iteration contains no `await`.
- **Why:** The `@MainActor` task never yields and never observes cancellation, so the app freezes hard. This is the "Demo" button, the path an App Review tester is most likely to tap on a fresh install.
- **Action:** Add a cancellation-aware suspension per outer iteration and bail out (or show "no demo content") when all three lists are empty.
- **Severity:** High

### 3.2 Database-readiness gate is bypassed by Dice and Rule entity queries, and Dice caches the empty result for 60 s
- **Location:** `Modules/DiceRPG/Intent/DiceEntity.swift:143-160`; `Modules/RuleRPG/Intent/RuleEntity.swift:85-91`; the gate is `Modules/CoreRPG/Controllable/ItemEntityQuery.swift:71-104`
- **What:** The shared query awaits `DatabaseReadiness.wait()`. The Dice and Rule `suggestedEntities()` overrides skip it, and the Dice override stores an empty result with a fresh timestamp when it runs before the root models exist.
- **Why:** A Siri/Shortcuts query at cold launch returns nothing for Dice and Rule; for Dice the empty answer is then served for another 60 s. CODE_AUDIT_16 §5.3 is therefore only partly fixed.
- **Action:** Await the gate at the top of both overrides and never cache an empty or not-ready result.
- **Severity:** Medium

### 3.3 `DatabaseReadiness.configure` runs inside an unstructured Task in `App.init`, so an intent can beat it
- **Location:** `Sources/MasterRPG/MasterRPGApp.swift:65-70`; `Modules/CoreRPG/App/DatabaseReadiness.swift:31-45`
- **What:** The starter is registered from `Task { @MainActor in ... }`, although `App.init` is already main-actor. `wait()` returns immediately when `isReady` is false and no starter is registered yet. The 20 s timeout Task at `:37` is also never cancelled when readiness arrives earlier.
- **Why:** A background intent on cold launch can hit exactly the race the gate was added to close.
- **Action:** Register the starter synchronously in `init`; when there is no starter and the database is not ready, wait for `markReady` instead of returning; cancel the timeout Task on resume.
- **Severity:** Medium

### 3.4 `ConversationEngine.streamResponse` does not propagate caller cancellation
- **Location:** `Modules/GeneratorRPG/BasicAI/Engine/ConversationEngine.swift:209-240` (with `cancelActiveResponse` at `:64-67`)
- **What:** The stream runs in a separate unstructured Task and the caller only awaits its value, so cancelling the caller does nothing. The `defer` that clears `activeStreamingTask` in a superseded call can run after the next call stored its own task.
- **Why:** A cancelled request keeps generating and writing partials, and Stop can no longer reach the newest stream.
- **Action:** Wrap the wait in a cancellation handler that cancels the inner task and clear the handle only if it is still the same task.
- **Severity:** Medium

### 3.5 `AdventureGeneratorController` cannot cancel its FoundationModels work
- **Location:** `Modules/GeneratorRPG/Controller/AdventureGeneratorController.swift:48-54,161-165,180-226,227-290`
- **What:** `cancel()` cancels only `currentTask` and never the engine; `extract(message:)` starts an untracked Task that neither `cancel()` nor `tearDown()` can reach. `GeneratorController` already has `currentExtractionTask`/`cancelExtraction()` for this.
- **Why:** Leaving the screen or sending a new request leaves the old generation and extraction burning on-device model time and writing into `model.extracted`.
- **Action:** Mirror `GeneratorController`: track the extraction task, cancel it in `tearDown`, and have `cancel()` also cancel the engine.
- **Severity:** Medium

### 3.6 The pending audio-play "bounded retry" retries forever
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:123-175`
- **What:** `fulfillPendingAudioPlay` catches an export failure and calls `scheduleAudioPlayRetry`, which calls `fulfillPendingAudioPlay` again, so a permanently failing `createGameData` reschedules itself every 5 s.
- **Why:** A missing or corrupt audio file makes the GM re-export it every 5 s for the rest of the session (I/O churn, log spam), contradicting the CODE_AUDIT_Network §5.13 intent.
- **Action:** Cap the attempts (counter or backoff) and drop the pending play, or tell the player, after the cap.
- **Severity:** Medium

### 3.7 Fixed `Task.sleep` delays are used as synchronisation for window and route readiness
- **Location:** `Modules/RolePlayGameKit/Model/AppModel.swift:535-540,554-556,602-604,645-648`; `Route/WindowRouter.swift:187-190`; `View/DataBaseAppStoreAvailable.swift:69`; `Modules/CoreRPG/Controllable/FolderListControllable.swift:208,332,344`; `LGViews/ItemStateRestorationView.swift:107` (about 15 more ordering-by-delay sites, e.g. `ItemHeaderEditorView:79`, `EntryEditorContent:78`, `PdfWrapperView:75/163`, `LinkController:37`, `SpaceViewer:630`)
- **What:** Cross-window routing, database-init hand-off, selection restore and header-editor presentation wait 150 ms to 1 s and then assume the target navigation stack has mounted.
- **Why:** On a slow device, a cold window or visionOS scene creation, the route or selection is silently dropped (the comment at `AppModel.swift:632-636` admits an unmounted stack drops the route).
- **Action:** Replace the sleeps with readiness signals (a mount/registration callback resuming a continuation, or a pending-route queue drained when the receiver registers).
- **Severity:** Medium

### 3.8 Global retroactive `@unchecked Sendable` on `PDFDocument`/`PDFSelection`, plus off-main PDFKit find callbacks
- **Location:** `Modules/PdfRPG/Pdf/PdfWrapperView.swift:25-26` (rationale `:19-24`); coordinator callbacks `:123-168`
- **What:** Two Apple mutable reference types are declared `@unchecked @retroactive Sendable` for every module importing PdfRPG. The find delegate callbacks run on PDFKit's search thread, mutate `pendingMatches` and `PDFSelection.color`, and hand selections to the main actor unsynchronised.
- **Why:** This disables data-race checking for PDFKit types app-wide; CODE_AUDIT_15 §3.17 removed a similar extension for the same reason.
- **Action:** Keep PDFKit objects main-actor-confined (hop with copied values in the delegate) and remove or narrow the retroactive conformances.
- **Severity:** Medium

### 3.9 `CoreDataInitModel` never stops its long-lived tasks, so the container leaks when persistence is replaced
- **Location:** `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:60-101`; `CloudKitCoreDataPersistenceController.swift:203-260`; `Modules/RolePlayGameKit/Model/DataBaseModel.swift:87-100`
- **What:** `cloudKitEventMonitoringTask` iterates a never-finishing notification sequence capturing the container strongly, and `cleanupTask` loops every 24 h; nothing cancels them when `DataBaseModel.setup()` swaps controllers.
- **Why:** The old `NSPersistentCloudKitContainer` and its event loop stay alive for the whole process (same class as the fixed CODE_AUDIT_16 §3.16).
- **Action:** Give `CoreDataInitModel` an explicit `stop()` that cancels both tasks and call it when a controller is replaced.
- **Severity:** Low

### 3.10 Runtime-only isolation escape hatches
- **Location:** 55 `assumeMainActorIsolated` sites across model files (AdventureModel 6; Space, Photo, Pdf, Generator, Dice, Value, Audio models 5 each); 16 `encodeOnMainActor` sites (`Modules/CoreRPG/Extensions/Encoder+MainActor.swift:20-33`); `Modules/CoreRPG/Concurrency/MainActorIsolationAssumption.swift:22-29`; `@preconcurrency` conformances at `Modules/CoreRPG/ItemList/ItemRowTreeModel.swift:52,78` and `Modules/AdventureRPG/Intent/AdventureEntity.swift:112`
- **What:** `@MainActor` domain models satisfy `nonisolated` `Comparable`/`Hashable`/`Encodable` requirements via `MainActor.assumeIsolated` (a trap if the invariant breaks) or `@preconcurrency`. `encodeOnMainActor` is the codebase's one `nonisolated(unsafe)`.
- **Why:** A future `sorted()`, `Set` insertion or `encode` of these models from a detached or `@concurrent` context crashes at runtime instead of failing to compile. Nothing traps today because the two off-main encode paths do not touch these models.
- **Action:** Keep the single-point wrappers, add a lint or test that scans for off-main use, and longer term move to value snapshots.
- **Severity:** Low

### 3.11 Items from CODE_AUDIT_16 that are still open (re-verified present)
- **Location and status:**
  - §3.13 `updateFromSync` deletion diff uses a snapshot older than the in-memory items — `Modules/CoreRPG/Controllable/SyncDataControllable.swift:64-95` (fetch `:74`, stale set `:75`).
  - §3.14 persistent-history `process()` can overlap itself — `Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift:161-215`.
  - §3.15 widget and app dice intents race on shared defaults — `Sources/DiceRollerWidget/DiceRollerIntents.swift:26-56`; `Modules/DiceRPG/Controller/GameController.swift:610-644`.
  - §3.17 visionOS `ImagePresentationView` subscription lifetime — `Modules/PhotoRPG/Space/ImagePresentationView.swift:62-92`.
  - §3.19 LAN broadcast can be reordered across `encodedOffMain` — `Modules/GameRPG/Master/MasterNetworkController.swift:187-227`; `Model/GameMessagePipeline.swift:306-309`.
  - §3.20 listener callbacks run as unordered per-event Tasks — `Modules/GameRPG/Network/ListenerManager.swift:171-178`.
  - §3.21 macOS `NSImage.resetSize()` on a shared cached image from a nonisolated context — `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:47-58`.
  - §4.3 `Thread.isMainThread` then `assumeIsolated` — `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:250-259`.
- **What:** All eight were re-opened in the current code and still hold as described in that report.
- **Why:** Each is a narrow race or ordering hazard (duplicate merges, a lost widget roll, a fast pin overtaking its map, a macOS data race); none is a crash on the common path.
- **Action:** Follow the actions in `Docu/CODE_AUDIT_16.md` §3.13-§3.21 and §4.3; the LAN ordering item is best done together with the per-connection queue in §6.8.
- **Severity:** Low

### 3.12 Assorted Low lifecycle and ordering issues
- **Location:** `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:99-160` (`record` Tasks are unordered against `finishSession`); `Modules/CoreRPG/Views/SendFeedbackButton.swift:36-46,96-111` (untracked Tasks from `onChange`; a stale timeout can clear a newer sending state); the `Task.detached` plus hand-rolled cancellation-handler pattern at about 14 sites (`Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:21,47,72`, `FoundryVTTImportReader.swift:28,90,194`, `UniversalVTTReader.swift:165,187`, `Files/FileUrlDataController.swift:674`, `FileManager+Coordination.swift:98`, `Modules/GameRPG/Controller/MasterController+Messaging.swift:151`, `Sources/RPGShare/ItemProviderImporter.swift:136,255`); non-cancellable `NSItemProvider` continuation wrappers at `Sources/RPGShare/ItemProviderImporter.swift:224-251` and `Modules/PhotoRPG/Controller/ItemController.swift:48-63`
- **What:** Unstructured tasks without ownership, and duplicated detached boilerplate where `@concurrent` functions or the async `NSItemProvider` overloads exist.
- **Why:** Late statistics events can persist after a session finished; a cancelled share cannot abort a large load; the duplicated cancellation boilerplate is easy to get subtly wrong (one site forgot the post-check).
- **Action:** Serialise statistics persistence through one consumer and await it in `finishSession`; own the feedback tasks with `.task(id:)`; convert the detached sites to `@concurrent` and use the async provider APIs.
- **Severity:** Low

---

## 4. API modernity

The project rules in `CLAUDE.md` are followed almost everywhere. **Verified zero hits** in production code: `ObservableObject`, `@Published`, `@StateObject`, `@EnvironmentObject`, `Task.sleep(nanoseconds:)`, one-parameter `onChange`, `foregroundColor`, `tabItem`, all legacy `Formatter` subclasses, `String(format:)`, `UIScreen`, `showsIndicators`, `ScrollViewReader`, `replacingOccurrences`, `Array(x.enumerated())`, `try!`, `as!`, `appendingPathComponent`, `DispatchSemaphore`/`NSLock`, `Timer`, `DispatchQueue.main` and real `NavigationView` uses; `GeometryReader` has 0 uses (2 `GeometryReader3D` on visionOS); `.font(.system(size:))` has 0 uses; `@Observable` classes are all `@MainActor` (197 checked, 0 missing). The 25 `@available` and 41 `#available` sites all guard APIs above the 26.0 target, so none is dead. The single `onTapGesture` (`InspectorRowView.swift:74`) uses `count: 2` and is legitimate; the single `.cornerRadius(5)` (`GameStatisticsDiceChart.swift:25`) is the `ChartContent` API.

### 4.1 `AnyView` type erasure is still pervasive *(previously reported CODE_AUDIT_16 §4.1)*
- **Location:** 109 code occurrences in 24 files: `Modules/CoreRPG/Controllable/ViewControllable.swift` (16); `Modules/MapRPG/Controller/ViewController.swift` (10); Weather, Character and Audio `ViewController.swift` (8 each); Table, Space, Photo, Dice and Adventure `ViewController.swift` (6 each); `Modules/CoreRPG/Navigator/Core/NavigationModifiers.swift` (6); `NavigationDestination.swift` (6)
- **What:** The per-module view-factory protocol still returns `AnyView`.
- **Why:** Structural identity is lost and the project rule against `AnyView` is violated; `.equatable()` workarounds remain.
- **Action:** Move the factories to `@ViewBuilder` returns module by module, starting with the protocol in `ViewControllable.swift`.
- **Severity:** Medium

### 4.2 List filters use `localizedCaseInsensitiveContains`
- **Location:** `Modules/AudioRPG/Model/AudioModel.swift:200`; `Modules/PhotoRPG/Model/PhotoModel.swift:212`; `Modules/SpaceRPG/Model/SpaceModel.swift:208`; `Modules/TableRPG/Model/TableModel.swift:191`; `Modules/AdventureRPG/Model/AdventureModel.swift:254`; `Modules/GeneratorRPG/Model/GeneratorModel.swift:191`; `Modules/CoreRPG/Controllable/TagController.swift:158` (7 user-input sites; a non-user site in `FoundryVTTDomainMapper+Scenes.swift:196` is fine)
- **What:** The project rule requires `localizedStandardContains`, which `SearchControllable` and 58 other sites already use.
- **Why:** Per-module filters are inconsistent with global search (no diacritic/width insensitivity).
- **Action:** Switch the seven sites.
- **Severity:** Low

### 4.3 Icon-only buttons and hard-coded layout values
- **Location:** About 48 `Button { } label: { Image(systemName:) }` sites, e.g. `Modules/GameRPG/GameViews/OverlayGameMenu.swift:258,276,302`, `GameToolBarButtonView.swift:27`, `Modules/MapRPG/Map/GameToolBar.swift:56,75`, `Modules/GeneratorRPG/BasicAI/View/ChatInputView.swift:42,78`, `Modules/CoreRPG/Editors/QuickLinkEditor.swift:64,73,89`; 239 numeric `.padding(...)`, 291 stack `spacing:` literals and 92 fixed `.frame(width:)` sites (e.g. `ChatInputView.swift:36-40`)
- **What:** Both `CLAUDE.md` rules ("text alongside the image", "avoid hard-coded padding/spacing") are not followed in these places. Most icon-only buttons compensate with `.accessibilityLabel`.
- **Why:** No functional defect for the buttons; the hard-coded values do not adapt to Dynamic Type or platform metrics, and fixed widths may clip at large text sizes.
- **Action:** Convert to `Button("Title", systemImage:, action:)` with `.labelStyle(.iconOnly)`; prefer default padding/spacing; review the text-bearing fixed-width sites in Accessibility Inspector.
- **Severity:** Low

### 4.4 Remaining old-style API leftovers
- **Location:** `UIGraphicsImageRenderer` at `Modules/CoreRPG/Extensions/Image+AKImage.swift:135` and `Modules/GameRPG/Table3D/GameTableEntities.swift:65-68`; `Color(UIColor.systemBackground)` at `Modules/CoreRPG/Platform/Color+Background.swift:9-11`; completion-style `performBackgroundTask` at `Persistence/PersistentHistoryTrackerManager.swift:72`; `loadObject(ofClass:)` at `Files/FileDropDelegate.swift:34`; `onReceive(Just(text))` at `ViewModifiers/NumericViewModifier.swift:15` (re-fires on every body evaluation); Combine `sink` at `CoreDataChangeObserver.swift:54`, `PersistentHistoryTrackerManager.swift:120`, `AudioController.swift:289,299`; `print` (DEBUG-gated) at `Modules/GeneratorRPG/View/PdfSummaryAnalysisView.swift:176`, `Modules/CoreRPG/Fake/PreviewFixtureLoader.swift:25`
- **What:** Renderer, completion and Combine APIs where `ImageRenderer`, async and `notifications(named:)` equivalents exist. The `@ObservedObject` in `Modules/GameRPG/SetupViews/SharePlayButton.swift:21` is framework-mandated (`GroupStateObserver`) and can stay.
- **Why:** Minor rule deviations; the `Just` pattern is a known SwiftUI anti-pattern.
- **Action:** Use `ImageRenderer`/ImageIO, async notification sequences, `onChange` and `Logger`.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Re-running root-model `setUp` deletes item files that are missing from the new store **[verified]**
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:415-431` (`updates(_:)`) calling `delete(itemId:)` at `:128-156` with its defaults `withFileData: true, withDatabase: true`; `Modules/CoreRPG/Controllable/SyncDataControllable.swift:109-119` (`fetchUpdates`); `Modules/CoreRPG/Persistence/CoreDataController.swift:100-116,451-455` (a fetch error returns an empty list); `Modules/PhotoRPG/Root/PhotoRootModel.swift:86-109` (`setUp` reuses the item controller and never clears `itemDataModel.items`, same shape in all 12 root models); `Modules/RolePlayGameKit/Model/AppModel.swift:414-420`; `Modules/RolePlayGameKit/Model/DataBaseModel.swift:104-113`; `Modules/RolePlayGameKit/View/DestinationReadyView.swift:31-36`
- **What:** The full reconciliation treats every in-memory id absent from the freshly fetched list as deleted and physically removes its binary (`fileUrlDataController.delete`). The CloudKit path (`SyncDataControllable.swift:77`) correctly passes `withFileData: false, withDatabase: false`. When the database is switched (`resetDatabase` flips `hasCloudKit`, a new context arrives, `setupRootModels` runs `setUp` again on the same root models), the in-memory ids from the old store are reconciled against the new store.
- **Why:** Items that exist only in the old store lose their photo, PDF, audio and 3D files from the shared container. The same happens if a fetch ever fails and returns `[]`. **Reachability caveat:** the Settings toggle (`Modules/CoreRPG/FileViews/StorageOptionEditor.swift:44-50`) terminates the process 0.1 s after the change, which masks the path in most cases; a race is possible, especially cloud → local where the local store loads fast, and any future in-process store recovery would hit it. I could not reproduce it at runtime, so I rated it High, not the Critical the agent proposed.
- **Action:** Make full-sync reconciliation memory-only (no file or database deletion, matching the CloudKit path), clear the in-memory items before `setUp` re-runs, and make fetch failures throw instead of returning an empty array.
- **Severity:** High

### 5.2 Edits sit in an in-memory queue until an unprotected async save runs **[verified]**
- **Location:** `Modules/CoreRPG/App/AppExitNotificationsViewModifier.swift:17-58`; `Modules/CoreRPG/Persistence/CoreDataController.swift:144-155,172-217`; `Modules/CoreRPG/Controllable/CoreDataSnapshotPersistable.swift` (`replaceSync` only queues); caller `Modules/RolePlayGameKit/Route/AppGameTypeDestinationView.swift:27`
- **What:** Editor saves only call `queueReplace`; nothing reaches Core Data until `save()`, which runs on will-resign-active, will-terminate or a 60 s timer, each through `for await` over `NotificationCenter.notifications` followed by an async flush. A grep of `Modules` and `Sources` finds no `beginBackgroundTask`, `performExpiringActivity` or `applicationShouldTerminate`.
- **Why:** On macOS the process can exit right after will-terminate is posted, before the Task runs, so Cmd-Q loses up to a minute of edits; on iOS the resign-active save can be suspended mid-flight; a jetsam kill loses the window entirely.
- **Action:** Flush synchronously or defer termination on macOS, wrap the resign save in a background-task assertion, and shorten the debounce for file-backed or long-form edits.
- **Severity:** High

### 5.3 The storage-switch alert quits with `Darwin.exit(0)` without flushing
- **Location:** `Modules/CoreRPG/FileViews/StorageOptionEditor.swift:9,44-50`
- **What:** After the confirm button, a Task sleeps 0.1 s and calls `Darwin.exit(0)` on all platforms; nothing awaits the queued item saves, tag saves or link saves.
- **Why:** The last edits (see §5.2) are lost, and programmatic termination runs against HIG and App Review guidance that the project rules make binding.
- **Action:** Flush all pending saves first, then ask the user to relaunch, or re-initialise the stack in process (which also needs §5.1 fixed).
- **Severity:** Medium

### 5.4 File adds and imports can overwrite an existing file with the same name, and rollback then deletes it
- **Location:** `Modules/CoreRPG/Files/CloudDocumentController.swift:115-125,133-148` (`write`, `createNameUrl`, `move(sourceUrl:destinationFilename:)`); `Modules/CoreRPG/Files/FileUrlDataController.swift:261-323,327-375` (only caller of `createNameUrl` at `:354`); `Modules/CoreRPG/Import/ExternalImportReviewSession+Internals.swift:367-421`
- **What:** `createNameUrl` uses the picked file's bare `lastPathComponent` as destination and `write` overwrites unconditionally, whereas the sibling `move(url:newCategory:)`/`move(url:newName:)` call `suggestedFileName` for a uniqueness check. I confirmed the callee; I did not trace every caller to prove no upstream de-duplication exists.
- **Why:** Two items whose source files share a name (two `map.png` picks) would share a path: the second write replaces the first item's bytes and deleting either deletes the file for both. The external-import rollback removes created files by path, so it can also remove a pre-existing one.
- **Action:** Resolve a unique destination (`suggestedFileName`) or key files by file id before writing, and make the write non-overwriting.
- **Severity:** Medium

### 5.5 A failed link/tag save rolls back every module's flushed edits and drops its own pending set **[verified]**
- **Location:** `Modules/CoreRPG/Links/LinkRegisterController.swift:162-201` (pending set cleared at `:165`, rollback at `:196`); `Modules/CoreRPG/Controllable/TagController.swift:124-160` (cleared at `:127`, rollback at `:150`); orchestration `Modules/AdventureRPG/Root/AdventureRootModel.swift:287-298`
- **What:** `AdventureRootModel.save()` flushes all modules' queued operations into the one shared context (draining each queue), then the link and tag saves run `context.save()` and, on failure, `rollback()` that same context.
- **Why:** A link or tag save failure (disk full, mirrored-store validation) silently reverts all other modules' edits; the queues are already drained and the in-memory models still show the edits, so the loss is permanent and invisible. The link or tag change itself is also dropped because the pending sets were cleared before the write.
- **Action:** Save the item context first, or write links and tags on a scratch child context, and restore the pending sets on failure.
- **Severity:** Medium

### 5.6 A failed `save()` in `CoreDataController` is never rolled back, so one bad object blocks every later save
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:212-217,535-548` (contrast `batchDelete` at `:316-323`, which rolls back)
- **What:** `save()` flushes the queue into the context, then the throwing save fails and leaves the invalid managed objects registered; the queue is already drained.
- **Why:** Every later save re-attempts the same invalid set and fails until relaunch, while the edits exist only in memory.
- **Action:** Roll back (or delete the offending object) on failure, re-enqueue the drained operations and surface a blocking error.
- **Severity:** Medium

### 5.7 A remote deletion plus a pending local edit resurrects the deleted item invisibly
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:176-210` (else branch `:197-200`); `Modules/CoreRPG/Controllable/SyncDataControllable.swift:73-80`; `Modules/CoreRPG/Controllable/ItemControllable.swift:128-156`
- **What:** When a CloudKit deletion arrives the item leaves `ItemDataModel`, but its pending queued operations remain; the next flush finds the uuid absent and inserts a new object with the same uuid.
- **Why:** An item deleted on device B and edited on A inside the 60 s window is re-created and re-exported; it is absent from A's UI and reappears after relaunch on every device.
- **Action:** Drop pending operations for ids the sync layer reports deleted, or record a tombstone and let delete win.
- **Severity:** Medium

### 5.8 CloudKit export errors and failed setup events are never surfaced
- **Location:** `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:215-244`
- **What:** A failed `.export` event maps to `.none` (logged only) and a `.setup` event with `succeeded == false` is reported as `.inProgress`; only import errors reach `cloudKitSyncState`.
- **Why:** Quota-exceeded, not-authenticated or schema errors on export leave the UI at "succeeded" from the last import while local edits never reach iCloud.
- **Action:** Map export and setup errors to a failed state and clear it when a later export succeeds.
- **Severity:** Medium

### 5.9 The link register never sees CloudKit-synced links, and delete-and-replace can wipe other devices' link rows
- **Location:** `Modules/CoreRPG/Links/LinkRegisterController.swift:24-104,162-201`; no change observer exists for `LinkReferenceDataModel` (only for item entities, `SyncDataControllable.swift:25-27`)
- **What:** The in-memory register is built once at setup and `mergeUpdates` does not call `register`. `savePendingLinks` then deletes all persisted rows for a source and re-inserts this device's stale view.
- **Why:** Edit on A adds a link, edit on B changes another: B deletes A's link rows for that source and never re-adds them, and the loss syncs back. "Used by" lists and repair-on-delete become wrong.
- **Action:** Re-derive links from the merged item during `mergeUpdates` (or observe the link entity) and diff persisted rows instead of replacing them.
- **Severity:** Medium

### 5.10 Export silently drops a file whose read fails and replaces photos with a lossy JPEG re-encode
- **Location:** `Modules/CoreRPG/Controllable/ExportControllable.swift:368-376` (used at `:291-298`)
- **What:** `try? await loadData(for:)` treats any failure (evicted iCloud file, coordination timeout, permission) as "no file"; for photos it falls back to the cached image re-encoded as JPEG.
- **Why:** A backup is written and reported successful without the binaries, or with format-changed photos (transparency and original bytes lost, hashes differ).
- **Action:** Propagate the read error or list it in the export report, and never substitute a re-encoded image.
- **Severity:** Medium

### 5.11 Siri/Shortcuts delete intents hard-delete items and files, bypassing the trash
- **Location:** `Modules/AdventureRPG/Intent/DeleteAdventureIntent.swift:20-27`; `Modules/DiceRPG/Intent/DiceManagementIntents.swift:125-131`; same pattern in 8 more management intents (Character, Photo, Pdf, Weather, Rule, Generator and others); soft-delete convention at `Modules/AdventureRPG/Root/AdventureRootModel.swift:350-358`
- **What:** The app deletes by `markForDeletion` and purges only in the launch-time cleanup; the intents call `editController.delete(itemId:)`, which removes the row and binary immediately.
- **Why:** A mis-resolved entity or a Shortcut loop destroys items permanently with no recovery, and the parent folder keeps a dangling child id.
- **Action:** Route intent deletes through `markForDeletion` and the parent-aware removal the UI uses.
- **Severity:** Medium

### 5.12 Intent entity queries expose soft-deleted items and folders
- **Location:** `Modules/CoreRPG/Controllable/ItemEntityQuery.swift:65-113`; `allIds` returns `itemDataModel.items` in the Adventure, Audio, Character, Dice, Map, Pdf, Photo, Space, Table, Weather and Generator entity files (only `RuleEntity.swift:83` overrides `include`)
- **What:** `suggestedEntities`, `entities(matching:)` and `entities(for:)` do not filter hidden/deleted display states.
- **Why:** Siri and Shortcuts can list, open, append to or delete items the user already moved to the trash (compounds §5.11).
- **Action:** Default `include(model:)` to exclude hidden and deleted display states, and folders where the intent is item-specific.
- **Severity:** Medium

### 5.13 Cross-device file replacement never invalidates the image and thumbnail caches
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:316-325,415-431`; `Modules/CoreRPG/Cache/ObjectCache.swift:44-70` (disk key is `itemId.jpg` only)
- **What:** Sync only calls `original.replace(with:)`; cache removal happens only in local editors (`EditControllable.swift:633`, PhotoRPG `EditController.swift:42`).
- **Why:** When another device replaces an item's image, PDF or model (same id, new content hash), this device keeps serving the stale image and on-disk thumbnail across relaunches.
- **Action:** Compare the old and new `fileUrl.contentHash` in `mergeUpdates` and drop the caches on change, or key caches by content hash.
- **Severity:** Medium

### 5.14 Folder delete and duplicate recurse with no visited set although cycles are documented as possible
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:433-453,486-515` (guard docs `:273-278`, `Modules/CoreRPG/Controllable/FolderTreeDepthLimit.swift:5-13`)
- **What:** `addItem` refuses cycles at write time, but the file states cycles can still form via import or CloudKit merge; read-side walkers are depth-limited while `delete(itemId:)` and `duplicateRecursively` are not.
- **Why:** A cyclic folder makes Delete or Duplicate loop until the process is killed, duplicating or deleting items on the way.
- **Action:** Add a visited-id set (or the depth limit) to both and repair or reject cycles at import/merge.
- **Severity:** Medium

### 5.15 Wallclock decode clamps a remote clock to "now + 1 day" at each decode, so ordering depends on decode time
- **Location:** `Modules/CoreRPG/CRDT/WallclockTimestamp.swift:110-119`; `Modules/CoreRPG/CRDT/LWWRegister.swift:70-77,94-98`
- **What:** `init(from:)` rewrites any clock beyond now + 86400 s to now + 86400 s, so the stored value changes with every decode; two far-future writes tie and fall back to the actor-id tie-break, and `LWWRegister.merged` returns `other` wholesale on a tie.
- **Why:** Devices skewed by more than a day can order concurrent edits differently per replica, so replicas do not converge.
- **Action:** Keep the decoded clock untouched and clamp only when observing into the local hybrid clock; add a deterministic value-based tie-break.
- **Severity:** Medium

### 5.16 Hex-grid generation traps or allocates without bound for unvalidated map dimensions **[verified]**
- **Location:** `Modules/MapRPG/Map/MapHexGridGeometry.swift:16-21,23-56`; callers `Modules/MapRPG/Map/MapEditController+HexGrid.swift:19-47`, `Modules/MapRPG/Controller/EditController.swift:365-376`; `Modules/MapRPG/Model/MapModel.swift:77-78` (unvalidated decode of width and height)
- **What:** Neither caller guards width/height/size. With width and height 0, `initialSize` returns 0 and `grid` computes `Int(0/0)`, a trap; a negative height makes `0..<rows` an invalid range; a very large dimension with a small scale creates hundreds of thousands of `MapEntryModel`s.
- **Why:** Importing or syncing a map with zero, negative or huge dimensions and then toggling "Hex grid" or moving the scale slider crashes or exhausts memory. I rated it Medium because I could not show an ordinary photo-backed map reaching zero dimensions.
- **Action:** Validate and clamp dimensions at decode/import and cap column and row counts inside `grid`.
- **Severity:** Medium

### 5.17 The map editor commits its working copy only on UI dismissal
- **Location:** `Modules/MapRPG/Map/MapEditController.swift:47-68`; `Modules/MapRPG/Map/EditMapToolBar.swift:153-156`; `EditMapToolBarButtons.swift:57-63`
- **What:** Rooms, walls and pins are edited on `editorModel.workingCopy`; `commitChanges` runs only from Save or `.onDisappear`, with no scene-phase or periodic commit.
- **Why:** A crash, force-quit or macOS quit with an editor open discards the whole drawing session (the app-level save saves the un-updated stored model).
- **Action:** Commit from the app-exit hook and periodically, or persist a recovery snapshot.
- **Severity:** Medium

### 5.18 Character formula evaluation is exponential in link fan-out
- **Location:** `Modules/CharacterRPG/Controller/LinkController.swift:183-214`; `Modules/CharacterRPG/Model/RecursionLimits.swift:9`
- **What:** `calculate(entry:deep:)` recurses per link up to depth 10 with no memoization or visited set, running a regex and string replacement per call on the main actor.
- **Why:** A diamond-shaped or self-referencing entry (imported data) costs b^10 evaluations (about 10 million for b = 5) in a row's render path and hangs the UI.
- **Action:** Memoize per evaluation pass, detect cycles with a visited set and evaluate off the view body.
- **Severity:** Medium

### 5.19 `cloudURL` is resolved once per process on first use, usually on the main thread
- **Location:** `Modules/CoreRPG/App/AppGroup.swift:55,67-69`; first use `Modules/CoreRPG/Files/LocationFileManager.swift:14`
- **What:** A static `let` calls `url(forUbiquityContainerIdentifier:)` (which Apple advises against on the main thread) and is never re-evaluated.
- **Why:** Cold-launch hitch; if iCloud is signed out or still provisioning at that moment, the whole session falls back to the group container, so new files are written where iCloud never sees them and later lookups resolve against a different root.
- **Action:** Resolve the container once off-main at startup, re-resolve on account change and migrate files written to the fallback root.
- **Severity:** Medium

### 5.20 FoundationModels: one reused extraction session overflows its context, and one page failure discards all pages
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:142-149,229-243,362-369`; `Modules/GeneratorRPG/Controller/AdventureGeneratorController.swift:117-125,228-244`; `Modules/GeneratorRPG/BasicAI/Providers/PdfContentExtractor.swift:78-118`
- **What:** One `LanguageModelSession` serves every `extract` call, so each prompt (up to 6,000 characters plus schema) and output stays in the transcript, and `cancelExtraction()` can start the next stream while the cancelled one still responds. In the PDF loop a single `respond` failure rethrows to one `catch` and drops all blocks extracted so far.
- **Why:** After a few generations the on-device window overflows (`exceededContextWindowSize`) or requests collide (`concurrentRequests`); RPG content trips guardrails often, so a long PDF extraction fails with no partial result.
- **Action:** Create a fresh session per extraction (prewarm the next), await the previous stream before starting, and catch per page while keeping successful blocks with a per-page diagnostic.
- **Severity:** Medium

### 5.21 Audio playlist copies every track eagerly from iCloud without coordination or download
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:126-186` (task group `:133`, discarded `fileDownloaded` result `:156`, `copyItem` `:173`)
- **What:** All tracks are copied concurrently into the temp directory (unbounded task group), reading the iCloud path directly with no file coordination and no download start.
- **Why:** An evicted iCloud file raises a missing-file error and the track is silently omitted; a large playlist temporarily doubles disk use and can starve the cooperative pool.
- **Action:** Use the coordinated read/download helpers, copy lazily (current plus next) and bound concurrency.
- **Severity:** Medium

### 5.22 The GM shows hosting as "running" when the listener never starts, and never restarts it
- **Location:** `Modules/GameRPG/Network/ListenerManager.swift:85-96,157-165`; `Modules/GameRPG/Master/MasterNetworkController.swift:111-123`
- **What:** If `NWListener(using:)` throws inside `run()`, `ListenerManager` sets its state to stopped but never calls the delegate's `listenerCancelled()`, while `startListener()` has already set `listenerStatus = .running`.
- **Why:** The GM sees a healthy game while nobody can join, and the restart-with-backoff added in the latest commit never runs for this failure.
- **Action:** Report a `run()` failure through the same delegate path as `.failed` and derive `listenerStatus` from the listener's real state.
- **Severity:** Medium

### 5.23 A reconnecting player is a ghost for up to ~30 s while the GM still holds its dead socket
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:256-274,279-289`; `MasterController+NetworkStoreDelegate.swift:64-68`; `Modules/GameRPG/Network/NWParameter+GameMaster.swift:43-46`; `PlayerController+NetworkStoreDelegate.swift:72-80`
- **What:** A live connection owns its player UUID until retired; after a Wi-Fi blip the new connection is not accepted until keepalive kills the old one (about 30 s), and the player's one-shot `ready()` messages are silently lost.
- **Why:** The returning player's character sync, pin and lists are ignored, with no explicit retry.
- **Action:** When the same player id arrives on a newer authenticated connection, retire the old one (or supersede it after a short liveness probe) and send a reject ack so the player retries.
- **Severity:** Medium

### 5.24 The 3D toolbar "hex map" toggle does not re-render the board
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+ToolBar.swift:62-70`; `GameTableModel+Viewport.swift:30-34`; `GameTableModel+MapSync.swift:233-254`
- **What:** `toggleHexMap()` mutates the entries, then `syncAfterExternalEdit()` only syncs pawns and hit areas and broadcasts map state; it never calls `replaceFogOfWarTask()` like every other fog-affecting entry point.
- **Why:** The board texture (which draws every entry) stays stale until an unrelated fog change, and the structural change may not reach players.
- **Action:** Route the toggle through `replaceFogOfWarTask()` and send the structural content update.
- **Severity:** Medium

### 5.25 Assorted Low correctness items
- **Location and what:**
  - `Modules/GameRPG/Table3D/GameTableProjection.swift:101-109` and `GameTableModel+PinThumbnails.swift:22-70`: pin-photo bookkeeping is never pruned and clearing a pin's photo leaves the old texture.
  - `Modules/GameRPG/Table3D/GameTableView+PlatformFlat.swift:58-60,137-143,323-349`: accessibility subscriptions are armed once in `make` but cleared in `onDisappear`, so VoiceOver actions stop after a hide/show.
  - `Modules/AudioRPG/Audio/AudioPlayerView.swift:222-244`: an indefinite (NaN/infinite) duration violates the slider range precondition and `Int(...)` traps; the sibling scrubber already guards this.
  - `Modules/AudioRPG/Audio/AudioPlayerSession.swift:118-134`: only wired headphones pause on route change, not Bluetooth or USB.
  - `Modules/CoreRPG/Persistence/FilePersistenceController.swift:35-66,135-138`: a failed legacy-bookmark migration returns an empty list and the next save overwrites the good file.
  - `Modules/CoreRPG/Model/ItemDataExportModel.swift:50-55` vs `Controllable/ImportControllable.swift:836-841`: export accepts blocks up to 4 GB while import rejects above 512 MB.
  - `Modules/DiceRPG/Intent/DiceEntity.swift:129-172`: `invalidateCache()` has no callers, so the 60 s suggestion cache serves stale data.
  - `Modules/GameRPG/Controller/MasterController.swift:189-193,311-326`: `pendingValueUpdatesAwaitingOwnership` is not cleared when the sender disconnects.
  - `Modules/CoreRPG/Persistence/CoreDataChangeObserver.swift:22-32`: a hard `precondition` on a second observe call; plus `preconditionFailure` on a missing link register/export hub at `Controllable/ItemControllable.swift:80-85`, `ExportControllable.swift:36-42`, `Persistence/CoreDataRelationship.swift:26-31` *(previously reported CODE_AUDIT_16 §5.9)*.
  - `Modules/CoreRPG/Persistence/CoreDataController.swift:419-484`: duplicate-uuid repair deletes an arbitrary row without merging, on the read path.
  - `Modules/PdfRPG/Pdf/PdfWrapperView.swift:113-162`: PDF find keeps and highlights every match with no cap; `Modules/CoreRPG/Controllable/ExportControllable.swift:147-168` uses linear `contains` inside the BFS loop.
- **Why:** Each is a narrow edge case: a stale visual, a rarely hit crash, or an occasional inconsistency.
- **Action:** Fix opportunistically, in the module each belongs to.
- **Severity:** Low

---

## 6. Security

**Threat model for the GameRPG items.** The game master (GM) and players share a 4-digit join code (LAN) or a SharePlay session. §6.1-§6.9 assume an *authenticated* but modified or malicious peer, or an attacker who has obtained the code. Message admission itself is well built: the GM rejects player messages claiming master identity, sender identity comes from the transport binding, pin edits are authorized against pin ownership, and `SharePlayPackageReceiver` bounds streams, bytes and package counts. No hard-coded secrets, no ATS exceptions and no logged join codes were found; Debug/Release entitlement pairs are consistent; Bonjour service types in the Info.plists match `GameServiceType`.

### 6.1 A joined player can overwrite any GM-owned character by claiming its id **[verified]**
- **Location:** `Modules/GameRPG/Controller/MasterController+ValueMessages.swift:50-58,84-90`; `Modules/GameRPG/Controller/MasterController.swift:207-218` (`bindCharacterOwnership`), `256-274`; root cause `Modules/CoreRPG/Controllable/ImportControllable.swift:36-47,399-410` (`PeerImportPolicy.admit`)
- **What:** `sender.characterId` is self-declared and the join `.store` binds it as long as no other sender holds it. `admit` always admits `itemId == primaryItemId` even when the item exists locally and the sender never introduced it, and `updatePlayer` then imports with `forceSave: true`. Character ids of NPCs, monsters and other players are visible in pin data, and ownership bindings survive disconnect.
- **Why:** A malicious code holder can merge over a GM NPC/monster or another player's character in the GM's persistent, CloudKit-synced library and silently lock the real owner out.
- **Action:** Admit the primary id only if it is absent locally or was previously introduced by the same player; reject ids that exist in the GM library as non-player characters; clear bindings when the physical peer is retired; send an explicit failure ack when binding is refused.
- **Severity:** High

### 6.2 The 512 MB frame ceiling lets one joined peer push the GM into jetsam **[verified]**
- **Location:** `Modules/GameRPG/Network/GameProtocol.swift:35-47,98-121`; `Modules/GameRPG/Model/GameLimits.swift:9,13`; `Modules/GameRPG/Network/GameNetworkController+MasterDelegate.swift:28-51`; `Modules/GameRPG/Model/GameMessagePipeline.swift:159-175,299-303`
- **What:** The framer accepts any frame up to 512,000,000 bytes in both directions, and `masterReceived` decodes the whole frame (`decodedOffMain`) before the pipeline's 768 MB queued-byte budget sees it, then re-encodes the model to relay it.
- **Why:** One authenticated LAN player sending a ~400-500 MB frame drives peak memory to roughly 1.4 GB during decode and about as much again on relay; iPad and iPhone hosts are killed mid-session.
- **Action:** Use a much smaller player-to-master cap with per-type limits, enforce the queue budget on raw frame size before decode, and forward raw bytes instead of decode-then-encode (see §7.2).
- **Severity:** High

### 6.3 Any player can request, or force-reveal, any library item by UUID **[verified]**
- **Location:** `Modules/GameRPG/Controller/MasterController+PhotoMessages.swift:33-36,124-125` (and `:38-108`); same pattern in `+PdfMessages.swift:33-38`, `+SpaceMessages.swift:33-38`, `+AudioMessages.swift:31-32`, `+TableMessages.swift:32-33`, `+DiceMessages.swift:31-32`; id exposure at `Modules/CoreRPG/Controllable/FileVersionGameControllable.swift:125-136,163-170`
- **What:** A player `.store`/`.reveal` or `purpose == .assetRequest` naming an arbitrary id gets `createGameData(for:)` back with no check that the item was shared in this game, and a photo `.reveal` also makes the GM publish its canonical copy to the whole group when photo sharing is on. The GM's list broadcasts (`localFileVersions()` iterates every library item) hand every player every item id.
- **Why:** A modified client can download, or force-reveal to all players, maps, handouts, monster art and 3D models the GM never presented, so the GM's reveal gate does not exist. I rated it Medium (the agent proposed High) because it needs a modified client.
- **Action:** Serve requests only for items in a per-game released set or already reported by the requester, stop sending library-wide id lists to players, and refuse group-publish for never-revealed ids.
- **Severity:** Medium

### 6.4 After a lost connection the player re-opens master pinning to the first full master broadcast **[verified]**
- **Location:** `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:36-70` (unpin at `:61`), `255-281` (unpinned branch `:272-279`); `Modules/GameRPG/Player/PlayerNetworkController.swift:516-534`
- **What:** `resetForLostConnection` sets the master type back to not-set. In that state `acceptsSessionMessage` accepts any envelope with `sender.isMaster`, matching ids and a master state, and a LAN origin carries no physical identity, so the first such envelope pins its sender as master.
- **Why:** Another code holder can connect while a player is "lost" and forge a master broadcast; the victim then applies forged maps, photos, PDFs, 3D files and roster, and `ready()` sends it the victim's character package.
- **Action:** Keep the previous master id pinned on reconnect (or repeat the master challenge), require explicit confirmation to re-pin to a new session, and bind the pin to the transport peer as SharePlay already does.
- **Severity:** Medium

### 6.5 The GM and returning players auto-dial unauthenticated Bonjour peers, giving a PSK handshake oracle
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:401-426,505-519`; `Modules/GameRPG/Browser/BrowserManager.swift:175-195`; `BrowserRowView.swift:76-85,109-111`; `Modules/GameRPG/Network/GameJoinCodeModel.swift:111-126`
- **What:** The GM dials any advertised reconnect service whose TXT `session` equals its own id, which is public in the GM's own TXT record; players auto-connect with the stored code to any host whose instance name equals `lastUsedMasterHost`, an advertiser-chosen adventure title.
- **Why:** An active LAN attacker can advertise a look-alike service and force a PSK-TLS handshake with no user action, and offline brute-force of the 4-digit code then takes seconds. Two tables using the same adventure title also collide and burn each other's throttle allowance.
- **Action:** Add a per-session random nonce verified after the handshake, key remembered codes by an identifier the host proves, and require confirmation before dialing an unknown service.
- **Severity:** Medium

### 6.6 Constant PSK identity and a 4-digit code are brute-forceable offline *(previously reported CODE_AUDIT_16 §6.5; CODE_AUDIT_JoinCode)*
- **Location:** `Modules/GameRPG/Network/NWParameter+GameMaster.swift:53-97`; `Modules/GameRPG/Network/GameJoinCodeModel.swift:135-138,279`
- **What:** The PSK is derived from the code with a constant identity in a plain PSK suite with no key exchange, and `codeLength` is 4; `ConnectionAttemptThrottle` only limits online guessing.
- **Why:** One captured handshake (or the oracle in §6.5) yields the code offline in seconds.
- **Action:** A longer code or an ephemeral-key/PAKE handshake; this is the open decision noted in `CODE_AUDIT_15`.
- **Severity:** Medium

### 6.7 Players can trigger repeated full map-package exports on the GM with no rate limit
- **Location:** `Modules/GameRPG/Controller/MasterController+MapMessages.swift:64-74,124-144,208-270`
- **What:** A map `.reveal` request, or a data-less `.update .generic` for any map id, runs `stableMapRecoveryBundle` (up to three detached full `createMapGameData` exports per request); distinct message ids defeat de-duplication and there is no per-player throttle.
- **Why:** One player can keep the GM re-exporting multi-hundred-MB map packages, starving the device and network for everyone.
- **Action:** Add a per-player rate limit and a cool-down keyed by (player, map generation), restrict requests to the shown map and reuse a cached bundle per generation.
- **Severity:** Medium

### 6.8 No send-queue cap or slow-consumer eviction on LAN connections *(residual of CODE_AUDIT_Network §5.5)*
- **Location:** `Modules/GameRPG/Network/ConnectionController.swift:127-162`; `Modules/GameRPG/Master/MasterNetworkController.swift:193-227`
- **What:** Sends are fire-and-forget into `NWConnection` with only a completion error callback; nothing bounds queued bytes per connection.
- **Why:** A stalled or hostile player accumulates every broadcast (map states, 100 MB+ packages) in GM memory until the OS terminates the app.
- **Action:** Track bytes in flight per connection, drop non-critical messages (map state, pins) above a threshold and disconnect a peer that stays over the limit.
- **Severity:** Medium

### 6.9 Player-controlled strings are unbounded and echoed in every master broadcast and persisted per event
- **Location:** `Modules/GameRPG/Root/GameRootModel.swift:74-109`; `Modules/GameRPG/Model/GameNetworkModel.swift:39-58,290-313`; `Modules/GameRPG/Statistics/Controller/GameStatisticsController.swift:30-38,86-102`
- **What:** `sender.name` enters the roster with no length cap, the v1-compatible encoder writes the roster three times in every master message, and statistics store `actorName` and participant names on every event row.
- **Why:** An authenticated peer with a huge name (up to the frame limit) inflates every GM broadcast to every player and the local statistics store.
- **Action:** Clamp names on receipt (for example 64 characters) and drop the redundant roster copies for peers on the current protocol version.
- **Severity:** Medium

### 6.10 Remote-URL FileUrl validation is bypassable and the download has no in-flight size cap
- **Location:** `Modules/CoreRPG/Files/FileUrl.swift:203-224` (`isPublicRemoteFileURL`); `Modules/CoreRPG/Files/FileUrlDataController.swift:609-653,688-695`
- **What:** The private-host check misses `localhost.` (trailing dot) and non-dotted-quad IPv4 such as `127.1` or `0x7f.0.0.1` (the `octets.count == 4` guard returns true for them) and hostnames resolving to private ranges; `URLSession.shared.download` follows redirects without re-validation and the 256 MB cap is checked only after the full download.
- **Why:** A peer-supplied FileUrl can make the GM's device fetch loopback or LAN URLs and cache the response as an item file, and a hostile server can stream gigabytes to disk before the check.
- **Action:** Parse hosts with `inet_pton`/`getaddrinfo` semantics, re-validate every redirect hop and the resolved address, and abort above the limit via a download delegate.
- **Severity:** Medium

### 6.11 Sensitive values are logged with `privacy: .public`
- **Location:** `Modules/GameRPG/Network/NWParameter+GameMaster.swift:26-34` with call sites `ListenerManager.swift:158-159` and `ConnectionController.swift:65` (a 4-bit HMAC nibble of the join code); `Modules/GameRPG/Table3D/GameTableProjection.swift:187,203` (user-authored pin names, including monsters the GM has not revealed); `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:329` and `SharePlayPackageReceiver.swift:195` (participant lists and ids)
- **What:** Of 286 `.public` annotations most are counters and UUIDs; these few carry code fingerprints or user-authored names.
- **Why:** The nibble cuts the 4-digit code space by a factor of 16 for anyone with a sysdiagnose; pin names can spoil hidden content.
- **Action:** Log them `.private`, or remove the nibble and compile the diagnostic out of release builds.
- **Severity:** Low

### 6.12 Share-extension downloads and platform entitlement inconsistencies
- **Location:** `Sources/RPGShare/ItemProviderImporter.swift:154-165,262-274` *(previously reported CODE_AUDIT_16 §6.6)*; `Resources/InfoTV.plist` vs `Resources/Info.plist`; `Resources/MasterTV-Debug.entitlements` and `MasterTV-Release.entitlements`; macOS sandbox settings at `MasterRPG.xcodeproj/project.pbxproj:7324-7328,7397-7401,8958-8963,9026-9030` *(previously reported CODE_AUDIT_16 §6.8)*
- **What:** File text is capped at 5 MB but `URLSession.shared.download(from:)` still downloads fully before any size or content-type check and fetches any URL. tvOS sets `CKSharingSupported` true (iOS false), lacks the group-session entitlement although GameRPG compiles SharePlay code, and its plist declares a ubiquity container without the CloudDocuments service. The macOS sandbox and network entitlements come only from build settings.
- **Why:** A hostile share can exhaust the extension's memory and reach LAN targets; SharePlay calls fail at runtime on tvOS (unverified); a build-setting change could silently drop the macOS sandbox.
- **Action:** Use a delegate-based capped download with host/scheme restrictions, align or gate the tvOS features, and declare the sandbox in the macOS entitlements file.
- **Severity:** Low

---

## 7. Performance

### 7.1 Every master send and incoming message triggers a Core Data fetch and save (statistics)
- **Location:** `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:100-150`; `Statistics/Controller/GameStatisticsDataController.swift:54-72,117-176,251-289,350-354`; call sites `MasterController+Messaging.swift:293`, `MasterController+NetworkStoreDelegate.swift:248,282,310`, `PlayerController+SendMessages.swift:245,283,331`
- **What:** Each processed message spawns a Task that fetches the session, may run a duplicate-count fetch, inserts an event row, syncs participants and calls `context.save()`; with more than one participant `checkpointSession` repeats a fetch, sync and save.
- **Why:** Pin drags and map edits produce dozens of messages per second, so bursts become dozens of unbatched saves per second plus unbounded task fan-out on the GM device.
- **Action:** Coalesce events into a bounded buffer flushed on a timer or count, skip or aggregate high-frequency map/pin/screen messages, and checkpoint participants only when the roster changes.
- **Severity:** Medium

### 7.2 Relay decodes and re-encodes payloads, and full-library lists are re-broadcast on every player report
- **Location:** `Modules/GameRPG/Network/GameNetworkController+MasterDelegate.swift:28-48`; `Modules/GameRPG/Master/MasterNetworkController.swift:215-226`; `Modules/GameRPG/Controller/MasterController+PhotoMessages.swift:128-134`; `+AudioMessages.swift:75-80` (same in Pdf/Space); `MasterController+Control.swift:78-131`
- **What:** `masterReceived` already holds the raw `Data`, decodes it, then `sendResponse` encodes it again (SharePlay adds a third encode). Each player list report makes the GM rebuild the whole-library version list and broadcast it to every player, and `performResetPlayers` re-sends full map content on each roster change.
- **Why:** Large player presentations double peak memory and CPU per relay, and N joining players cost O(N × library) LAN traffic and main-actor work.
- **Action:** Forward the original frame bytes to LAN peers and encode once for SharePlay; send targeted lists to the requester only (or debounce and coalesce) and limit them to items shared in this game.
- **Severity:** Medium

### 7.3 `mapUpdateResult` builds a string with a quadratic `reduce` and is called per pin message
- **Location:** call sites `Modules/GameRPG/Controller/PlayerController+MapPresentation.swift:28,86`, `Table3D/GameTableModel+Broadcast.swift:59-65`; root cause `Modules/MapRPG/Controller/GameController+Sync.swift:28-32`
- **What:** `networkMapUpdate` rebuilds the entry string with `reduce("")` plus a JSON encode of every pin on the main actor, and callers use it only to read the generation fingerprint. Hex-grid cells count as entries.
- **Why:** With a few thousand hex cells each pin move or GM edit costs O(entries²) string copying and stalls the UI and network handling.
- **Action:** Use the cheap `networkGeneration(for:)` for comparisons, build the string with `reduce(into:)`/join and cache it until entries change.
- **Severity:** Medium

### 7.4 3D diagnostics run on every map sync and allocate per room and pin
- **Location:** `Modules/GameRPG/Table3D/GameTableProjection.swift:47-56,133,162-229`
- **What:** `logPinDiagnostics` and `logRoomDiagnostics` loop every entry and pin on each `syncPawnsWithMapPins`, building arrays and reason strings regardless of log level.
- **Why:** Pure main-actor overhead on every pin update, large on hex maps.
- **Action:** Gate them behind a debug flag or compile-time check and compute lazily (see also §6.11 for the `.public` names).
- **Severity:** Medium

### 7.5 Hex maps create one entity, hit area and persisted row per cell *(previously reported CODE_AUDIT_16 §7.2)*
- **Location:** `Modules/GameRPG/Table3D/GameTableProjection.swift:139-153`; `GameTableEntities.swift:295-345`; `GameTableModel+MapSync.swift:233-254`; `Modules/MapRPG/Map/MapEditController+HexGrid.swift:19-52`; `MapHexGridGeometry.swift:23-56`; `Modules/MapRPG/Controller/DataController.swift:161-173`
- **What:** Hex cells are treated as rooms for hit areas, the render signature and fog paths, the whole grid is regenerated per slider tick as one `MapEntryModel` per hex, and the same cells are persisted as Core Data rows (roughly 366k rows at 61k cells with six points each) that also flow through CloudKit.
- **Why:** Tens of thousands of entities, path fills and CloudKit rows on large hex maps.
- **Action:** Exclude hex cells from hit volumes and fog fills, and stop persisting them: store only the scale and regenerate.
- **Severity:** Medium

### 7.6 Full-resolution images are decoded with no pixel cap, and the decode is lazy
- **Location:** `Modules/PhotoRPG/Controller/CacheController.swift:23-48`; `Modules/PhotoRPG/Controller/FileUrlDataController+ImageResolve.swift:15-32`; `Modules/CoreRPG/Cache/ImageCacheController.swift:30-33`
- **What:** `createImage` loads the whole file and builds an image at full size with no ImageIO downsample or dimension check; on UIKit the bitmap decode is deferred to first draw, so the `@concurrent` hop does not decode off the main actor.
- **Why:** A 16k × 16k battle map is roughly a 1 GB bitmap, causing memory pressure or jetsam on iPhone and visionOS and a first-render hitch on the main thread.
- **Action:** Decode via ImageIO with a `kCGImageSourceThumbnailMaxPixelSize` sized to the display and force decode off-main.
- **Severity:** Medium

### 7.7 Tag and link rows are rewritten wholesale on every save
- **Location:** `Modules/CoreRPG/Controllable/TagController.swift:124-160` (`setup` keeps the last-loaded row at `:39-45`); `Modules/CoreRPG/Links/LinkRegisterController.swift:162-201`
- **What:** Each save deletes all `TagDataModel` rows of the affected modules and all link rows of the affected sources, then inserts fresh objects.
- **Why:** With N tags each save exports about 2N CloudKit record operations, and two devices re-inserting the same (module, title) create duplicate records with nondeterministic counts.
- **Action:** Upsert by (module, title) or a stable id, diff link rows, and recompute counts from items instead of persisting them.
- **Severity:** Medium

---

## 8. SwiftUI / UI

A SwiftUI expert pass (Step 4) grepped `Modules/` and `Sources/` for the skill's hard rules. Results: exactly **one** non-private `@State` (documented and intentional, §8.5); **zero** `.animation(_:)` calls without `value:`; **zero** `ForEach` over `.indices`/`\.offset`; **one** computed-property view fragment (`Modules/CoreRPG/FileViews/SingleReviewFilePropertyRow.swift:93`); no `GeometryReader`, no fixed `.font(.system(size:))`. The UI layer is in good shape; accessibility and layout-value findings are in §4.3.

### 8.1 `ForEach(id: \.self)` on strings that can repeat
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryImportView.swift:498` (import warnings, `prefix(20)`); `Modules/GameRPG/BattleRound/BattleRoundSettingsView.swift:62` (pattern names); `Modules/SpaceRPG/Record/ProConListView.swift:31,53`; `Modules/GeneratorRPG/View/TextSummaryUpdateView.swift:44`, `Modules/PdfRPG/View/SummaryPdfUpdateView.swift:58` (tags). The other ~33 of the 40 `id: \.self` uses are on enums or constants and are fine.
- **What:** Identity is the displayed content, so duplicate strings produce duplicate identities (undefined diffing).
- **Why:** Repeated import warnings are plausible and would mis-render or drop rows; the other sites are static text with low risk.
- **Action:** Use an enumerated identity or a stable id for the warning list; leave the static lists alone.
- **Severity:** Low

### 8.2 Oversized view bodies and handlers
- **Location:** `Modules/GameRPG/Table3D/GameTableView+VisionOS.swift:41` (`body` ~248 lines); `Modules/MapRPG/Map/EditMapToolBar.swift:30` (`body` ~223 lines); `Modules/SpaceRPG/Space/SpaceViewer.swift:479` (`loadEntity` ~231); `Modules/GameRPG/Controller/PlayerController+Map.swift:20` (`handleMap` ~313); `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:24` (`sendData` ~282); `RPGSharePlayController+SessionLifecycle.swift:175` (`configureGroupSession` ~252); `Modules/CoreRPG/Import/ExternalImportReviewSession.swift:95` (`commit` ~239) *(previously reported CODE_AUDIT_16 §9.17)*
- **What:** Very long single functions; lengths were carried over from the earlier audit since the containing files are the same size.
- **Why:** Large `body` properties are hard to diff and to keep invalidation narrow, and the network handlers are hard to test in an area with a history of lost-message bugs.
- **Action:** Extract subview structs from the bodies, and break the handlers into named phases (validate, defer, apply, acknowledge).
- **Severity:** Medium

### 8.3 Icon-only control coverage is unproven
- **Location:** repo-wide: 586 `Image(systemName:)` uses against 186 `accessibilityLabel` calls *(previously reported CODE_AUDIT_16 §8.2/§8.3)*
- **What:** The counts are unchanged; no individual site was verified as a defect.
- **Why:** A VoiceOver gap in a game-time control (map toolbar, dice) would block a player.
- **Action:** Run an Accessibility Inspector pass on the game screen, the map editor and the dice roller.
- **Severity:** Low

### 8.4 View logic that belongs in a controller or model
- **Location:** `Modules/GameRPG/GameViews/OverlayGameMenu.swift:50-110` (`handleMainTabToggle`, `handleMainTabDisplayModeChange` mutate settings and manage scene windows inside a private view extension)
- **What:** Menu-mode logic lives in the view and cannot be unit-tested there, contrary to the project rule to place view logic into view models.
- **Why:** The behaviour has no test seam.
- **Action:** Move the handlers into `GameScreenModel` or a controller.
- **Severity:** Low

### 8.5 Minor `@State` and `ForEach` items
- **Location:** `Modules/PhotoRPG/Photo/ImageViewer.swift:19` (`@State var viewportModel` is not `private`, documented as read by `ImageViewer+Gestures.swift`); `Modules/RolePlayGameKit/Import/Foundry/FoundryImportView.swift:417` (`filter` inside a `ForEach` collection expression)
- **What:** One deliberate deviation from the "`@State` is private" rule, and one per-body filter.
- **Why:** Cosmetic; the filter runs each body evaluation over a small list.
- **Action:** Keep the comment on the first; hoist the filter into the model.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

Baseline: 1,795 production Swift files (~194,861 LOC). Files over 500 LOC: **33** (31 in CODE_AUDIT_16); over 1,000 LOC: **3**. There are no `#if false` blocks, no ungated `print`/`debugPrint`/`dump`/`NSLog`, and only two TODO markers. CODE_AUDIT_16 §9.1, §9.5, §9.6, §9.18 (typos listed there) and §9.19 are confirmed fixed.

### 9.1 Two source files are excluded from every target and never compiled
- **Location:** `Sources/DiceRollerWidget/DiceRollerView.swift:1-424`; `Sources/DiceRollerWidget/DiceRollerWidgetConfiguration.swift:1-193`; `MasterRPG.xcodeproj/project.pbxproj:1886-1896` (also lists `DiceRollerWidgetDiceRollerExamples.swift` and `FavoriteDiceManagementView.swift`, which no longer exist)
- **What:** The folder is a synchronized group of the widget extension only and its exception list names both files, so no target compiles them; nothing references `DiceRollerView` besides its own preview. It contains its own JSON roll-history persistence, and the folder's string catalog carries 50 stale keys.
- **Why:** 617 LOC of dead, unbuildable code and stale project metadata.
- **Action:** Delete both files (or add them to a real target) and drop the exception list in the same change.
- **Severity:** Medium

### 9.2 Dead types and protocols
- **Location:** `Modules/CoreRPG/App/ExportedRPGData.swift:71-144` (`ExportedRPGData` and both `RPGJsonFile` variants; keep the `UTType` constants at `:94-99`, used by `ImportProgressPanelView.swift:182`); `Modules/CoreRPG/FileViews/SettingsView.swift:1-10` and `Modules/RolePlayGameKit/View/SettingsView.swift:20-24` (two identical `StoreManipulable` protocols, no conformers); `Modules/CoreRPG/App/AppTabBarViewModifier.swift:5` (`AppRouter`, one conformer, never a constraint); `Modules/CoreRPG/CRDT/DeltaCRDT.swift:16` (one conformer, never a constraint); `Modules/CoreRPG/Cache/ResourceCache.swift:1-120` (test-only, unbounded cache); `Sources/MasterRPG/RealityKitInit.swift:11-16` with its call at `MasterRPGApp.swift:31` (empty body)
- **What:** Types with no production consumer; the two `SettingsView.swift`/`AppTabBarViewModifier.swift` files are also misnamed for their content.
- **Why:** About 250 LOC of public API surface with a latent unbounded-memory pattern (`ResourceCache`) and a duplicate public name.
- **Action:** Delete them, keeping the `UTType` extension in a file named for it.
- **Severity:** Low

### 9.3 About 110 unreferenced members and 41 test-only members remain *(previously reported CODE_AUDIT_16 §9.2/§9.3)*
- **Location:** CoreRPG holds 100 of 127 single-hit names (minus ~15 witnesses/delegate methods). Examples: `Modules/CoreRPG/App/PlatformModifiers.swift:15,23,80,89,98`; `Navigator/Core/Navigator.swift:190,310,323`; `Files/FileUrlViewModel.swift:31-46`; `Fake/TestFixtures.swift:24-62`; `Links/ReferenceScanner.swift:26`; `Text/ContentAttributes.swift:10,11,24,44`; `Modules/RuleRPG/Resources/Localization+Extensions.swift:1-13` (whole file). Test-only: `Modules/CoreRPG/Tips/MasterRPGTips.swift:48-76`, `Sheet/SheetSearchContext.swift:12-31`, `Modules/GameRPG/Network/JoinCodeStorage.swift:153`. **Keep** `participantJoined` (`Modules/GameRPG/Statistics/Model/GameStatisticsTypes.swift:50`, a persisted raw value) and treat `migrationKey` (`Modules/CoreRPG/AppModels/AppSettingsModel.swift:237`) as deletable only after confirming its migration shipped. Legacy live-model overloads in `Modules/CoreRPG/Persistence/CoreDataController.swift:100,129,144,331,394` have no callers *(§9.4)*.
- **What:** Names with one repo-wide hit, or used only by tests; the legacy overloads would let a future caller hand main-actor state to `@Sendable` queue closures.
- **Why:** Inflated surface and a compile-time hazard.
- **Action:** Delete in one pass and let the compiler catch anything missed; check TipKit rules before touching `MasterRPGTips`.
- **Severity:** Low

### 9.4 A vestigial SwiftData model, 13 ungated `MockData` containers and 20 ungated `Fake/` files ship in release
- **Location:** `Modules/CoreRPG/Model/LinkDataModel.swift:1-11`; `Modules/*/Model/MockData.swift` (13 files, ~800 LOC); `Modules/CoreRPG/Text/ContentFormattingDefinition.swift:9,23,39`; `Modules/CoreRPG/Fake/` (20 files, 965 LOC); `Modules/CoreRPG/Debug/RainbowDebug.swift`
- **What:** The app is Core Data, yet `LinkDataModel` is a SwiftData `@Model` holding only an `id`, used solely as the preview `ModelContainer` schema and as `LinkDataModel.ID` (just `UUID`) in three declarations; none of the mock or fake files is under `#if DEBUG`.
- **Why:** `import SwiftData`, a second persistence stack and about 1,000 LOC of fake controllers ship in the release frameworks purely for previews.
- **Action:** Replace `LinkDataModel.ID` with `UUID`, delete `LinkDataModel`, and move the mock and fake code under `#if DEBUG` or a preview target.
- **Severity:** Medium

### 9.5 Commented-out code and unresolved TODOs
- **Location:** commented-out (16 single-line statements): `Modules/CoreRPG/Sheet/SheetRootModel+Editor.swift:50,61`; `Editors/TextDoubleEditor.swift:42`; `Modules/MapRPG/Map/EditMapToolBar.swift:137`; `Modules/GeneratorRPG/Controller/GeneratorController.swift:321`, `AdventureGeneratorController.swift:220`; `Modules/PhotoRPG/Model/DataModel+Extensions.swift:26`; `Modules/CoreRPG/LGViews/HeaderFooterContentScrollView.swift:34,163,184`; `ItemDetail/ItemEditorForegroundView.swift:83`; `LGViewModifiers/ToolbarItemListViewModifier.swift:207`; `Debug/RainbowDebug.swift:23`; `Sources/DiceRollerWidget/DiceRollerWidgetConfiguration.swift:86`; TODOs: `Modules/CharacterRPG/View/DetailEditorView.swift:14`, `Modules/CharacterRPG/Controller/EditController+Repair.swift:178`
- **What:** Obsolete disabled statements and two TODOs citing CODE_AUDIT_Character §9.16 (a `.task` double-creation accepted "for now", and whether an ungrouped group stays visible).
- **Why:** Dead text, and some suggests behaviour that is not wired up.
- **Action:** Delete the commented statements; resolve the TODOs or track them elsewhere.
- **Severity:** Low

### 9.6 Unused assets, stale localization keys and an orphaned script
- **Location:** `Modules/SpaceRPG/Resources/Assets.xcassets/PhotographyTips.imageset` and `Reticle.imageset`; about 258 `"extractionState": "stale"` keys (GeneratorRPG 72, DiceRollerWidget 50, GameRPG 43, CoreRPG 22, MapRPG 16, ~50 more); `Scripts/print_wan_ip.sh:1-25`
- **What:** Two images with zero references, Xcode-flagged stale keys, and a script referenced nowhere except a local settings file.
- **Why:** Shipped weight and translator noise.
- **Action:** Delete the images and script, and prune stale keys in Xcode.
- **Severity:** Low

### 9.7 Per-module boilerplate is identical after a name swap *(previously reported CODE_AUDIT_16 §9.7)*
- **Location:** `Modules/*/Resources/BundleModule.swift` (13 lines × 14); `Controller/SyncDataController.swift` (20 × 11); `Root/LinkRootView.swift` (19 × 10); `Root/DetailRootView.swift` (22-28 × 12); `Route/DetailRoute.swift` (55-56 × 9); `Route/<Module>Route.swift` (63-71 × 12); `Menu/<Module>Commands.swift` (24 × 11); `Controller/FolderListController.swift` (30-31 × 12); `Intent/Open<Module>Intent.swift` (53-59 × 12); localization helpers `Modules/{Adventure,Audio,Character,Generator,Map,Pdf,Space,Table,Weather}RPG/Resources/Localization+Extensions.swift` (15 × 9)
- **What:** Families that move in lockstep across 9-14 modules.
- **Why:** A routing, bundle or command change is repeated in 9-14 files.
- **Action:** Generic `DetailRoute<Root>`, `FolderListController`, `SyncDataController<Entity>`, `LinkRootView<Root>` and one localization helper in CoreRPG, with `BundleModule.swift` from a template; do bundle and localization first.
- **Severity:** Medium

### 9.8 App Intents families are 80-95% identical across the item modules
- **Location:** `Modules/*/Intent/*ManagementIntents.swift` (146-199 LOC each, ~2,014 LOC total; Photo vs Audio differ in 10 of 190 lines); `*ShortcutCatalog.swift` (78-142 LOC); `*Entity.swift` (112-195 LOC)
- **What:** The create, append, delete and open intents, shortcut tiles and entity/query types are copies per module although `ItemEntityQuery` already exists as a shared base.
- **Why:** About 4,500 LOC of intent surface where every contract change touches 11-12 files, and the same defect (§5.11, §5.12) exists in each copy.
- **Action:** Move intent bodies and shortcut construction into generic CoreRPG helpers parameterised by module configuration, leaving only module-specific `AppEntity` fields.
- **Severity:** Medium

### 9.9 Core Data mapper, export and link controllers are near-copies per module *(previously reported CODE_AUDIT_16 §9.8)*
- **Location:** `Modules/{Audio,Photo,Space}RPG/Controller/DataController.swift` (87-88 LOC; Photo vs Space differ in 8 lines), `ExportController.swift` (38-39), `{Photo,Space}RPG/Controller/LinkController.swift` (61-63), `{Photo,Pdf,Space,Map}RPG/Controller/CacheController.swift`, `attributeSet()` in `Modules/*/Model/DataModel+Extensions.swift`, and 12 `Modules/*/Model/*Snapshot.swift` files (49-58 LOC)
- **What:** The item and edit controller layers are already shared in CoreRPG; this is the remaining tail.
- **Why:** A Spotlight, snapshot or CRDT mapping change is copied 3-12 times.
- **Action:** A shared common-field mapper and `makeSpotlightAttributes(...)` helper in CoreRPG, and generic file-module export and link controllers.
- **Severity:** Medium

### 9.10 Master and Player photo, PDF and space handlers, and per-module sequence trackers *(previously reported CODE_AUDIT_16 §9.9)*
- **Location:** `Modules/GameRPG/Controller/MasterController+PhotoMessages.swift` vs `+PdfMessages.swift` (169 LOC each, 36 lines differ), `+SpaceMessages.swift` (221); `PlayerController+Photo.swift` vs `+Pdf.swift` (217 and 216, 91 differ), `+Space.swift` (310); `PlayerControllerModel.swift:235,250,310,367`
- **What:** Unchanged since CODE_AUDIT_16.
- **Why:** A network area with a history of lost-message bugs, where a fix (and the authorization gap in §6.3) must be applied by hand three or four times.
- **Action:** One `ListSequenceTracker` keyed by `NetworkModules` and one generic file-module handler.
- **Severity:** Medium

### 9.11 Five PDF-export `Transferable` blocks have drifted error handling *(previously reported CODE_AUDIT_16 §9.10)*
- **Location:** `Modules/AdventureRPG/Intent/AdventureEntity.swift:62-98`; `CharacterRPG/Intent/CharacterEntity.swift:60-94`; `MapRPG/Intent/MapEntity.swift:60-84`; `TableRPG/Intent/TableEntity.swift:60-84`; `WeatherRPG/Intent/WeatherEntity.swift:62-96`
- **What:** Only `WeatherEntity` checks the write; `MapEntity` returns a URL for a file that was never written if `CGContext` creation fails (`:73-75`); files are named after the raw item name; "Name:"/"Description:" are hard-coded English.
- **Why:** Inconsistent, sometimes broken sharing and Shortcuts output.
- **Action:** One CoreRPG `renderSummaryPdf(title:description:)` that throws, with a write check and a sanitized filename.
- **Severity:** Medium

### 9.12 Smaller duplicated helpers
- **Location:** four copies of the `NSFileCoordinator` tail in `Modules/CoreRPG/Files/FileManager+Coordination.swift:122-195` *(§9.11)*; 13 hand-rolled `startAccessingSecurityScopedResource` sites (`Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:22,73`, `FoundryVTTImportReader.swift:29,91,195`, `UniversalVTTReader.swift:166,188`, `Import/ExternalImportSourceRegistry.swift:601`, `Files/FileUrlDataController.swift:136,151`, `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:97`, `Modules/SpaceRPG/Space/SpaceViewer.swift:501`, `Modules/RolePlayGameKit/Model/AppModel.swift:463`) versus the shared `SecurityScopedAccess` *(§9.12)*; `ExtractToolBarButton` copies (`Modules/PdfRPG/View/DetailEditorToolBarButtons.swift:13` and three near-copies), a `UUID.fixture` extension in six `PreviewData.swift` files, ImageIO thumbnail options in `Image+AKImage.swift` and `Sources/RPGShare/ItemProviderImporter.swift`, and identical `Selected{Adventure,Player}ViewSharePlayButtonView` bodies *(§9.15)*; 31 inline `JSONEncoder()`/`JSONDecoder()` allocations in 20 files (the App Group store is now shared) *(§9.14)*
- **What:** Verbatim copies that differ by a route or constant.
- **Why:** Two idioms for one rule (unbalanced start/stop is the latent bug class from CODE_AUDIT_15 §9.17) and constant drift.
- **Action:** One generic coordination helper, migrate the 13 sites to `SecurityScopedAccess`, a generic `ExtractToolBarButton(route:)`, one shared preview fixture and a shared SharePlay overlay view.
- **Severity:** Low

### 9.13 Oversized files: 33 over 500 LOC, 3 over 1,000 *(previously reported CODE_AUDIT_16 §9.16; sizes unchanged)*
- **Location (LOC):** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift` 1313; `Modules/SpaceRPG/Space/SpaceViewer.swift` 1119; `Modules/GameRPG/Controller/PlayerControllerModel.swift` 1065; `GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift` 939; `RPGSharePlayController.swift` 929; `CoreRPG/Controllable/ImportControllable.swift` 861; `CoreRPG/Foundry/FoundryRuleModels.swift` 829; `CoreRPG/Controllable/EditControllable.swift` 804; `CoreRPG/Foundry/FoundrySystemPackageReader.swift` 738; `RolePlayGameKit/Import/Foundry/FoundryImportView.swift` 720; `DiceRPG/Model/DiceModel.swift` 703; `CoreRPG/Files/FileUrlDataController.swift` 701; `RolePlayGameKit/Model/AppModel.swift` 679; `CoreRPG/FileViews/SingleReviewModels.swift` 670; `GameRPG/Root/GameRoot.swift` 652; `DiceRPG/Controller/GameController.swift` 648; `CoreRPG/Import/ExternalImportSourceRegistry.swift` 633; `CoreRPG/Sheet/SheetEntryView.swift` 631; `GameRPG/Controller/MasterController.swift` 627; `GameRPG/Statistics/Model/GameStatisticsTypes.swift` 620; `CoreRPG/Views/ViewportGeometry.swift` 605; plus 12 more between 501 and 598 LOC
- **What:** The splits proposed in CODE_AUDIT_16 §9.16 still apply; new proposals are `GameRoot.swift` (split into `GameRoot`/`GameRootModel` extensions) and `GameStatisticsTypes.swift` (move fixtures at lines 449-620 into a `+Fixtures` file).
- **Why:** Reviewability, and the network files are where lost-message bugs cluster.
- **Action:** Mechanical extraction along existing MARK or extension boundaries with no behaviour change.
- **Severity:** Medium

### 9.14 Spelling mistakes in symbol names
- **Location:** `sugguestionTags` (`Modules/CoreRPG/Controllable/TagController.swift:156`, `Model/SearchModel.swift`); `historyTransactionConvertionFailed` (`Persistence/PersistentHistoryTrackerManager.swift:213`); `preparaEngine` (`Modules/GeneratorRPG/Controller/GeneratorController.swift:229`); `isProminet` (`Modules/CoreRPG/Buttons/GlassButton.swift:27`); `decimnalSeparator` (`ViewModifiers/NumericViewModifier.swift:17`); `AddtionalEntryRow` (`Modules/MapRPG/Controller/EditController.swift:103`); `initalPackage` (`Modules/GameRPG/SharePlay/SharePlayPackageReceiver.swift:151`); `firstRerole` (`Modules/DiceRPG/Controller/GameController.swift:557`); `deactive` (`Modules/CoreRPG/Model/TagFilterList.swift:7`); `haslink` (`LinkRenderer/AttributedString+Link.swift:20`); `titlename` (`Modules/MapRPG/Map/EditMapToolBar.swift:178`); `ccolor` (`Modules/MapRPG/Model/MapPinModel.swift:149`); `throttleInMilliSeconds` (`SharePlaySingleQueuePackageSender.swift:82`); `ScaeExample` (`Resources/RPGResourcesDebug/Resources.swift`)
- **What:** Typos found by a dictionary pass; the ones fixed after CODE_AUDIT_16 are not repeated. The `Id`/`Url` casing convention is intentional and not flagged.
- **Why:** Search-hostile API.
- **Action:** One rename commit.
- **Severity:** Low

### 9.15 Mixed naming conventions and misplaced files
- **Location:** `LinkHighLight*` types (27 hits) in `Modules/CoreRPG/LinkRenderer/`; `MarkDown` vs `Markdown`; `firstLunchKey = "FirstLunchMasterRPG"` (`Modules/CoreRPG/AppModels/AppSettingsModel.swift:238`, persisted); `IosAppDelegate` vs `MacAppDelegate`; `ToolBar` (124 lines) vs `Toolbar` (262); five names for the per-module game-store protocol (`AudioGameStoreable`, `DiceGameStorable`, `MapGameStorable`, `AdventureStoreGameable`, `WeatherGameControllable` in the modules' `Controller/GameController.swift`); files not named for their primary type (`Modules/CoreRPG/Menu/AppCommands.swift`, `Links/QuickLinkConfig.swift`, `Buttons/RoundGlassButtonStyle.swift`, `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift`, `Modules/GameRPG/Table3D/GameEquipment.swift`, `Modules/GameRPG/Model/Localization+Extensions.swift`, `Modules/CoreRPG/Model/GeneratorRootModelTV.swift`); public type names duplicated across 12-15 modules (`ModuleConfiguration`, `ViewController`, `Resources`)
- **What:** Convention drift that makes cross-module search and qualified-name resolution error-prone; `firstLunch` is persisted, so renaming it needs a migration.
- **Why:** Ambiguity and hard-to-find code.
- **Action:** Pick one spelling and suffix per concept, rename files to their primary type, and prefix or internalise the duplicated public names; keep the persisted key string or migrate it.
- **Severity:** Low

### 9.16 Magic constants still unnamed *(previously reported CODE_AUDIT_16 §9.20)*
- **Location:** Foundry limits `536_870_912` at `Modules/CoreRPG/Foundry/FoundryImportArchive.swift:120` and `FoundryRuleModels.swift:736-745`; `256_000_000` at `Cache/ObjectCache.swift:20` and `Files/FileUrlDataController.swift:607`; `.seconds(120)` at `Modules/GameRPG/SharePlay/SharePlayPackageReceiver.swift:41`, `Network/SharePlayPlayerJournalAdmission.swift:141`, `Network/GameRelayAdmission.swift:39`, `Master/MasterNetworkController.swift:321`; `256_000`, `128_000_000`, `64_000_000` at `SharePlaySingleQueuePackageSender.swift:79-85`; `metadataHeadroom` at `SharePlayDeferredDeliveryQueue.swift:57`; `milliseconds(100)` in 9 files; four spellings of the `de.andretrettin.` bundle prefix in 40 places (`ExportedRPGData.swift:95-99`, `InAppModel.swift:9-11`, `AppGroup.swift:6,40`, `GameCenterController.swift`, `LinkDataTransferable.swift`); Bonjour types at `Modules/GameRPG/Browser/GameServiceType.swift:35-41` mirrored by hand in `Resources/Info.plist:63-66` and `InfoTV.plist:50-53`; `@SceneStorage("RootRoute")` repeated with different defaults in `Modules/RolePlayGameKit/View/TabbedNavigation.swift:124`, `TabSidebar.swift:92`, `SplitNavigation.swift:69`
- **What:** Where a named constant exists the value is often repeated elsewhere.
- **Why:** One cap or window can change while its twin silently diverges; a typo in a Bonjour type has no compile-time check.
- **Action:** A `BundleIds` enum, shared Foundry limits, an extended `GameLimits`, one debounce constant and a shared route storage key.
- **Severity:** Low

### 9.17 Architecture drift from `CLAUDE.md`, and stale agent docs
- **Location:** stateful "Controller" classes: `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:650` (~100 stored properties), `Controller/MasterController.swift:565`, `Controller/PlayerController.swift:23`, `Master/MasterNetworkController.swift:29`, `Player/PlayerNetworkController.swift:29`, `Network/GameNetworkController.swift:21`, `Modules/AudioRPG/Controller/AudioController.swift:10`; layering: `import GeneratorRPG` in `Modules/CharacterRPG` (4 files), `MapRPG` (9), `TableRPG` (9), `PdfRPG` (6); `/Users/andrenalin/Developer/gamemaster/AGENTS.md` vs `CLAUDE.md`; UI-dependent models `Modules/GameRPG/Table3D/GameTableModel.swift:8-24,107` (documented), `Modules/SpaceRPG/Record/AppDataModel.swift:11`
- **What:** About eight session-owning "Controller" classes contradict "stateless struct Controllers"; the module import graph is a clean DAG but `CLAUDE.md` says Generator is used only in Pdf and Adventure, while Map and Table depend on it too; `AGENTS.md` lacks the whole "3D Game Table" section.
- **Why:** Documentation drift; agents that read `AGENTS.md` miss rules such as `broadcastMapEdit` and idempotent syncs.
- **Action:** Add an explicit exception for network and session controllers (or rename them `...Session`), update the module list, and make `AGENTS.md` a symlink or one-line pointer.
- **Severity:** Low

### 9.18 A vendored NavigatorUI copy sits inside CoreRPG
- **Location:** `Modules/CoreRPG/Navigator/` (27 files, ~3,800 LOC, headers "Created by Michael Long"); unused deprecated members at `Navigator/Core/NavigationDestination.swift:205` and `AnyNavigationDestination.swift:127`
- **What:** A third-party library checked in as source with no license file in the folder, using Combine and `ObservableObject`.
- **Why:** An attribution and maintenance-ownership question, plus unused public surface; `CLAUDE.md` says not to add third-party frameworks without asking.
- **Action:** Confirm the license and add attribution, then trim the unused API.
- **Severity:** Low

### 9.19 Test-suite hygiene
- **Location:** all 29 `Tests/*SnapshotTests/*.swift` suites are disabled on Xcode 26 via `Tests/SnapshotTestSupport/SnapshotTestEnvironment.swift:100-102`; commented-out test at `Tests/AdventureRPGTests/AppIntentTests.swift:34-58`; `Tests/*/MockRoot.swift` in 7 targets; `Tests/PhotoRPGTests/FolderListControllerTests.swift` (1306 LOC); an assertion-free test at `Tests/GameRPGTests/SearchModelTests.swift:27`
- **What:** Snapshot coverage depends on the toolchain, one test is commented out (documented: it crashed the shared xctest process), and the duplicated controller tests mirror the production duplication. The known-failing areas in project memory were not re-run.
- **Why:** Snapshot coverage silently drops on Xcode 26.
- **Action:** Time-box the Xcode 26 disable, delete the commented-out test in favour of an `AppIntentsTesting` target, and share a generic `MockRoot`.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Make full-sync reconciliation and store swaps memory-only, and fix the save pipeline as one unit.** §5.1, §5.2, §5.3, §5.5, §5.6, §5.7 and §5.17 are one theme: queued in-memory edits, a shared context, and several paths that discard or delete without a barrier. A single "flush barrier" (background-task assertion, synchronous macOS terminate flush, restore-on-failure of every drained queue) plus a rule that reconciliation never touches files would close most of them.
2. **Treat every authenticated peer as untrusted at the GameRPG boundary.** §6.1-§6.4, §6.7-§6.9 share a root: admission checks who a message is from, but not what it may name or how big it may be. A per-game "released items" set, per-type size caps enforced before decode, per-player rate limits and length-clamped strings would address them together (and shrink §7.2).
3. **Collapse the per-module duplicates before fixing bugs in them.** §9.7-§9.11 mean that every fix (soft-delete in intents §5.11/§5.12, asset authorization §6.3, PDF export §9.11) has to be applied 3-12 times. Generic CoreRPG helpers first, then apply each fix once.
4. **Replace fixed sleeps and unstructured Tasks with readiness signals and owned tasks.** §3.2, §3.3, §3.7, §3.12: the 150 ms-1 s delays and start-up Tasks in `App.init` are the same design smell that produced the intent/readiness race.
5. **Bound inputs at decode time, not at use.** §5.16 (map dimensions), §5.14 (folder cycles), §5.18 (formula breadth), §6.10 (download size), §7.6 (image pixels): each trusts a decoded value that a file, peer or synced device can set arbitrarily.
6. **Gate debug and preview code out of release.** §9.4, §7.4 and §6.11 all ship diagnostics or preview scaffolding (and `.public` logging) in the release binaries.

---

## 11. What was NOT audited

- `Docu/`, `Snapshots/`, `.git`, `.build` and `DerivedData` (excluded by request/convention). No `Dead/` folder exists.
- **Only the iOS Simulator scheme was rebuilt** (zero Swift warnings). macOS, tvOS and visionOS were not rebuilt, so platform-conditional compile errors were not checked. No tests were run and the known-failing areas recorded in project memory were not re-run.
- **Runtime behaviour.** Nothing was launched. §5.1 in particular was established by reading the code path and is not reproduced; §6.3 and §6.4 depend on a modified client.
- **visionOS TabletopKit files** (`GameDice`, `GameRenderer`, the TabletopKit observer) were not read in depth; the iOS/macOS Table3D code was.
- Algorithmic correctness of the CRDT merge, the LevelDB/Foundry readers and the RealityKit board renderer beyond the specific bounds and ordering issues reported. The agents found the ZIP archive bounds, LevelDB/WAL readers, import stream framing, integer narrowing sites and non-finite CRDT clock guards clean.
- Build settings and Xcode project structure beyond the shared entitlements, Info.plists and the target-membership exceptions in §9.1; third-party dependency internals (RPGTabletopGameContent and the SPM test dependencies).
- `Tests/` — quick scan only; no deep coverage review.
- Localization correctness (untranslated and stale keys are noted in §9.6, wording is not assessed) and the StoreKit product configuration.
- The 24 findings in `Docu/CODE_AUDIT_Network.md` were not re-audited; only new issues and the CODE_AUDIT_16 "Not done" items were re-verified.
- The audit used **four** parallel agents instead of the skill's three: the bugs/security/performance brief was split into GameRPG + RolePlayGameKit + Sources, and all other modules, because of the codebase size. Agent-reported items not tagged **[verified]** were not independently re-read.

---

## 12. Verification

Spot-check pattern: open Xcode and command-click the `path:line` reference; it should land on the cited line. No finding is Critical. The lines below prove each High item and the items I re-read, and record where I changed the reported severity.

- **§5.1** — open `Modules/CoreRPG/Controllable/ItemControllable.swift`, lines `415-423` (`updates` calls `delete(itemId:)` with defaults for every id missing from the fetched list) and `128-156` (defaults delete the file at `:149-151`); `Modules/PhotoRPG/Root/PhotoRootModel.swift:86-109` (`setUp` reuses the item controller without clearing `items`); `Modules/CoreRPG/Persistence/CoreDataController.swift:451-454` (fetch error returns `[]`); `Modules/CoreRPG/FileViews/StorageOptionEditor.swift:9,44-50` (the 0.1 s exit that masks the switch path). **Severity note:** the audit agent proposed Critical; I demoted it to High because the store-switch trigger is masked by that exit and I could not reproduce a live path.
- **§5.2** — open `Modules/CoreRPG/App/AppExitNotificationsViewModifier.swift`, lines `17-58` (each save is an async handler behind `for await` on a notification) and `runPeriodicHousekeeping` (60 s); a repo grep for `beginBackgroundTask|performExpiringActivity|applicationShouldTerminate` in `Modules` and `Sources` returns nothing.
- **§5.4** — open `Modules/CoreRPG/Files/CloudDocumentController.swift`, lines `133-148` (bare `lastPathComponent`, then an unconditional `write`) versus `:159,188` (sibling `move` overloads that call `suggestedFileName`). Partially verified: upstream callers were not exhaustively traced.
- **§5.5** — open `Modules/CoreRPG/Links/LinkRegisterController.swift`, lines `162-201` (set cleared at `:165`, `context.rollback()` at `:196`) and `Modules/AdventureRPG/Root/AdventureRootModel.swift:287-298` (all modules flushed into the same context before the link and tag saves).
- **§5.16** — open `Modules/MapRPG/Map/MapHexGridGeometry.swift`, lines `16-21` (size 0 for zero dimensions) and `23-30` (`Int` of a NaN/inf quotient, and `0..<rows`), and `Modules/MapRPG/Map/MapEditController+HexGrid.swift:19-47` (no guard). Severity kept at Medium because a zero-dimension map is not a normal case.
- **§3.1** — open `Modules/GameRPG/Root/GameRoot.swift`, lines `548-608`: the only `await`s sit inside the `for` bodies of photos, weathers and maps, so an iteration over three empty lists never suspends.
- **§6.1** — open `Modules/GameRPG/Controller/MasterController+ValueMessages.swift`, lines `50-58` (binding from the peer-declared `characterId`) and `84-90` (import with `peerImportPolicy`), then `Modules/CoreRPG/Controllable/ImportControllable.swift:37-40` (`itemId == primaryItemId` is admitted even when `existsLocally`).
- **§6.2** — open `Modules/GameRPG/Model/GameLimits.swift:9` (512,000,000), `Modules/GameRPG/Network/GameProtocol.swift:41,103-107` (only that bound), and `Modules/GameRPG/Network/GameNetworkController+MasterDelegate.swift:28-47` (full decode at `:29`, then relay by re-encode at `:43`, before any queue budget).
- **§6.3** — open `Modules/GameRPG/Controller/MasterController+PhotoMessages.swift`, lines `33-36` (asset request returns `createGameData` for `model.data.id`) and `124-125` (`.store` does the same), and `Modules/CoreRPG/Controllable/FileVersionGameControllable.swift:125-136,163-170` (`fileList`/`localFileVersions` iterate every library item). **Severity note:** I rated this Medium; the agent proposed High.
- **§6.4** — open `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift`, line `61` (master type reset to not-set) and lines `272-279` (unpinned branch accepts any self-consistent full master broadcast).
- **§3.2 / §3.3, §5.3, §6.5-§6.10** — reported by the auditing agents and read by them at the cited lines; not independently re-read by me.
- **SwiftUI counts in §8** — reproduced by grep: 1 non-private `@State`, 0 unvalued `.animation`, 0 `ForEach` over `.indices`/`\.offset`, 1 computed `some View` fragment, 40 `id: \.self` sites (list reviewed).

If any finding doesn't reproduce when you visit the line, tell me the specific reference and I'll re-investigate.
