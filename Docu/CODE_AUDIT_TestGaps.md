# Test-Gap Audit — MasterRPG (2026-11-19)

Scope: the whole repository (`Modules/*` frameworks and `Sources/*` app, widget, share-extension targets) against the test targets in `Tests/*` and the plans in `TestPlans/*`. Read-only; no code was changed.

**Method and its limits (read first).** No full-suite coverage run exists: the only `.xcresult` bundles with coverage in DerivedData are 6-test runs (3 visionOS pin-pawn tests failing, 3 passing), so their 2–16 % figures are meaningless for the project. All gaps below come from static analysis:
1. every declared type and `func` name in `Modules/` and `Sources/` was searched for in the non-snapshot test sources (token match);
2. the candidates were opened and re-checked by hand, including the indirect paths (tests that reach a function through a public entry point are *not* listed as gaps);
3. test plans, test-target layout, skipped/gated tests and the snapshot infrastructure were read directly.

A "no reference" result therefore means *no test names the symbol*; it can still run as part of a larger flow. Where I checked and found indirect coverage, the finding says so. Private helpers reached through a tested entry point are ignored. Run `MasterAll` with code coverage once (§10.1) to turn this list into measured numbers.

Size of the thing: ~216 k LOC in 15 modules + ~3.7 k LOC in 4 app targets (1,966 Swift files); ~3,190 unit/integration test functions, ~550 snapshot test functions, 64 UI tests (105 k LOC of tests). Heuristic: 323 non-View source files (~29.7 k LOC) declare types that no unit test names; 190 of those are also unnamed by any snapshot test.

---

## 1. Executive summary

1. **[High] The whole snapshot suite has no baseline.** `Snapshots/Xcode27/` does not exist, so ~550 snapshot tests have nothing to compare against — §8.1.
2. **[High] The "destroy the store and start fresh" recovery path is untested** (`recoverStore` → `destroyStoreFiles`, both Core Data controllers) — §5.1 — `Modules/CoreRPG/Persistence/CoreDataInitModel+Setup.swift:10-28`.
3. **[High] CloudKit/Core Data sync intake has no test** (`SyncDataControllable`, `CoreDataChangeObserver`, `ContextFlushLedger` commit/rollback) — §5.2 / §3.1.
4. **[High] `GuardedRemoteDownload` (private-host / redirect / byte-cap guard) has no test** — §6.1 — `Modules/CoreRPG/Files/GuardedRemoteDownload.swift:11-111`.
5. **[High] Tests run on the iOS simulator only.** macOS, tvOS and the visionOS table have no routine test run; visionOS needs a hand-built scheme — §5.3.
6. **[Medium] Map sync metadata/package assembly (`GameController+Metadata`, `+BattleSync`) is named by almost no test** although it carries the map-sync bugs recorded in earlier audits — §5.4.
7. **[Medium] The Foundry VTT import front end (`FoundryRuleImportModel`, `UniversalVTTDomainMapper`, `FoundryVTTBridgeDecoding`, `+Documents/+Indexes/+Scenes` mappers) is largely untested** — §5.7.
8. **[Medium] The Siri/Shortcuts/Spotlight surface is tested for only 5 of ~12 modules, and only through slow UI tests** — §5.9.
9. **[Medium] `ConversationEngine` (FoundationModels chat with overflow recovery) has no seam and no test** — §5.8.
10. **[Medium] Audio playback engine and audio delivery state (deadlines, retry, join) are mostly unnamed by tests** — §5.5 / §3.2.

---

## 2. Quick wins (≤ 30 minutes each)

### 2.1 Record the snapshot baseline before anything else
- **Location:** `Scripts/run_snapshot_tests.sh`, `TestPlans/MasterSnapshot.xctestplan`
- **What:** Run `./Scripts/run_snapshot_tests.sh record 27`, review, commit `Snapshots/Xcode27`. See §8.1 for why.
- **Why:** Until then every snapshot run fails or silently records.
- **Action:** Record once on the pinned simulator (iPhone 18 Pro, Xcode 27.x), then verify twice to expose flakes (memory note: random die colour flake).
- **Severity:** High

### 2.2 Fix the three failing assertions in `verify_snapshot_view_coverage.rb`
- **Location:** `Scripts/verify_snapshot_view_coverage.rb` (run output)
- **What:** Reports "declared more than once" for `GamePinActionMenu`, `GameMapPhotoPopover`, `GamePinPhotoPopover` (`Modules/GameRPG/Table3D/GamePinActionMenu.swift`), `GameTableView` (`+PlatformFlat` vs `+VisionOS`) and `AnalyzeButtonView`/`AnalyzingView` (`PdfSummaryAnalysisView.swift` vs `TableSummaryAnalysisView.swift`).
- **Why:** The script exits with errors, so it cannot be a CI gate; the 89.8 % "view coverage" it prints is also a count of *declared* snapshot cases, not of baselines that exist.
- **Action:** Teach the script about platform-split types (`#if os`) and same-name private views, or add them to `snapshot_view_exclusions.txt`.
- **Severity:** Low

### 2.3 Give the two assertion-free test files an assertion
- **Location:** `Tests/MapRPGTests/MapPinSelectionEnvironmentTests.swift:17-45`, `Tests/MasterRPGUITests/AudioIntentTests.swift:9-12`
- **What:** The first only asserts "does not crash"; `testPauseAudioRunsWithoutAnythingPlaying` only asserts "does not throw".
- **Why:** Acceptable as smoke tests, but they read as coverage they do not give.
- **Action:** Assert the hosted picker's size/identity or the intent's returned state; otherwise tag them `smoke`.
- **Severity:** Low

### 2.4 Add a golden-value test for `StableVersionDigest`
- **Location:** `Modules/CoreRPG` (`StableVersionDigest`, used by `ValueModel+VersionDigest.swift:12`, `TableModel+Persistence.swift`)
- **What:** The tests prove `version` is equal for equal content and differs on edits (`Tests/CharacterRPGTests/ValueModelTests.swift:150-171`), but nothing pins an actual number.
- **Why:** A change to the canonical encoding keeps both property tests green yet changes every version, so master and players of different app builds see "everything changed" and re-transfer all content. Memory note: cross-device version determinism is a known risk area.
- **Action:** One golden test per digest user (Character, Table, Map, Photo…) with a literal expected `Int` for a fixed fixture.
- **Severity:** Medium

### 2.5 Replace silent `.enabled(if:)` skips with visible skips on CI
- **Location:** `Tests/GameRPGTests/BattleRoundInputAndBroadcastTests.swift:82`, `NetworkDiscoveryNamingTests.swift:44`, `Tests/CoreRPGTests/CloudDocumentControllerTests.swift:82`, `SharedContentTests.swift:111`
- **What:** Four suites skip when the sources/plists/iCloud/app-group are unavailable.
- **Why:** On CI they report "skipped" without anyone noticing; the *source-reading* tests (`sourcesAreOnDisk`, `plistsAreOnDisk`) guard architectural rules.
- **Action:** Print the skipped-test count in the test-run summary, and make the source-reading tests locate the sources through the repository root so they run on CI too.
- **Severity:** Low

---

## 3. Concurrency (gaps in concurrency-critical code and in the tests of it)

### 3.1 `SyncDataControllable` queue / consumer ordering and `ContextFlushLedger` commit/rollback are untested
- **Location:** `Modules/CoreRPG/Controllable/SyncDataControllable.swift:40-181`; `Modules/CoreRPG/Persistence/ContextFlushLedger.swift` (`didCommit`, `didRollBack`, `failingItemIds`, `owningItemIds`, `unregister`); `Modules/CoreRPG/Persistence/CoreDataChangeObserver.swift:1-106`
- **What:** No test names `SyncDataControllable`, `updateFromSync`, `fetchUpdates`, `startSyncObservation`, `CoreDataChangeObserver` or the ledger's commit/rollback outcomes (3 of 8 ledger functions are named).
- **Why:** The doc comment at `SyncDataControllable.swift:44-49` says arrival order was a previous bug (CODE_AUDIT §3.1, CODE_AUDIT_Folder §3.19). A regression returns remote CloudKit changes in the wrong order or drops them; the effect is silent data divergence across devices.
- **Action:** Drive the protocol extension with a fake `DataPersistenceControllable`/`ItemControllable` and an in-memory context: post notifications out of order, assert the consumer applies them in arrival order, and that delete→insert→update for one id converge. Test ledger rollback restores the failing ids.
- **Severity:** High
- **Status: FIXED 2026-11-19.** `Tests/CoreRPGTests/ContextFlushLedgerTests.swift` (6 tests: save commits every registered module, a save of another context is ignored, rollback re-queues oldest first, named failing ids are discarded without blaming the others, the retry cap, `unregister`). `Tests/PdfRPGTests/SyncDataControllerTests.swift` (16 tests): the sync consumer against a fake store (insert, update merge into the live instance, insert of a loaded id, deletion diffed against the store, unsaved local insert survives, failed fetch reconciles, arrival order, batches queued before a reset are skipped), `CoreDataChangeObserver` on a real in-memory store (inserted/updated ids, other entities ignored, deleted placeholder, released observer), and `failingItemIds` (child → owner, detailed errors). Pdf stands in for every module because `SyncDataControllable`, the observer and the ledger are shared code and Pdf is the smallest module with a Core Data entity. Not covered: the second `observeCoreDataChanges` call on one instance traps by design (`precondition`), which Swift Testing cannot assert. Tests must take the entity from the store's own model (`container.managedObjectModel.entitiesByName`): `RPGPdf.entity()` finds no unique match once a second in-memory model is loaded in the process.

### 3.2 Audio delivery/deadline/retry state machine is only exercised end-to-end
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift` (22 of 33 functions unnamed in tests: `audioPlayDeadlineExpired`, `scheduleAudioPlayRetry`, `startPendingAudioPlay`, `deliverPendingAudio`, `joinRunningAudioPlay`, `clearPendingAudioPlay(s)`, `holdAudioPrefetch`, …)
- **What:** `AudioMessageFlowTests` covers the happy flows; the deadline/retry/supersede branches have no direct test.
- **Why:** Earlier audits list "pending audio play not superseded" as open (memory: audio + game controllers audit 2026-11-07). These branches are timer-driven and only fail under slow or lossy links.
- **Action:** Inject a fake clock / deadline into the master and add cases: deadline expires with a player still loading; a newer play supersedes a pending one; a late joiner joins a running play.
- **Severity:** Medium
- **Status: FIXED 2026-11-19.** `Tests/GameRPGTests/AudioPlayStateMachineTests.swift` (4 tests, none waits on a wall clock): the deadline starts the play without the quiet player and a second expiry starts nothing twice; a newer play replaces the pending one and the old deadline starts nothing; a pause ends the running play so a late player no longer joins; a play whose package cannot be prepared is retried and then dropped. The deadline was already injectable (`audioPlayDeadline`) and is expired by hand through `audioPlayDeadlineExpired(id:)`; the retry delay was a `private static let` and is now the instance property `audioPlayRetryDelay` (default 5 s, unchanged), so the test runs it in milliseconds. `maxAudioPlayRetryAttempts` is now internal. Not covered: the prefetch hold (`holdAudioPrefetch`, 60 s) and a late player that really gets the file and joins (already in `SimpleFileFlowTests`).

### 3.3 SharePlay transport and session lifecycle helpers are tested at the edges only
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift` (19 of 25 functions unnamed: `drainSendOperations`, `enqueueChunkedSend`, `sendDataReportingLoss`, `adoptLateJournalAttachment`, `scheduleDeferredPromotionIfNeeded`, …), `RPGSharePlayController+SessionLifecycle.swift` (15 of 19: `bindPlayer`, `unbindPlayer`, `requestJoin`, `makeJournalTask`…), `SharePlayJournalPublicationQueue.swift` (15 of 18: `drainPublications`, `scheduleEmergencyCleanup`, `finishWorkerIfCurrent`…)
- **What:** 34/18/12 test references exist, concentrated in transport/ledger/limiter/hang tests.
- **Why:** The previous audit (2026-11-09) lists "deferred-promotion spin", "shared master drain" and "journal hung system calls" as the area's Highs; their fixes are guarded by the named tests, the lifecycle (bind/unbind/leave, cancelActivation) is not.
- **Action:** Add lifecycle tests on the existing mocks: leave during activation, rebind after unbind, cancel while a chunked send is draining.
- **Severity:** Medium
- **Status: FIXED 2026-11-19 (the testable part).** `Tests/GameRPGTests/SharePlayLifecycleGapTests.swift` (9 tests): a stop during activation followed by a restart, a failed activation, the cleanup observer waiting for the obsolete session, observer rebind, the same session id bound again after a reset, an operation token across a rebind, the controller joining again after `stopJoin`, `cancelAll` while a payload drains (no further package, every caller failed, sender stays stopped) and a cancelled caller mid-drain (the next payload still goes out whole, in order). These run on the pure coordinators (`SharePlaySessionLifecycle`, `SharePlayActivationLifecycle`, `SharePlaySessionObserverLifecycle`) and `SharePlaySingleQueuePackageSender`; no `GroupSession` is needed. Not covered: `RPGSharePlayController.bindPlayer/unbindPlayer/requestJoin` themselves and `SharePlayJournalPublicationQueue.drainPublications` / `scheduleEmergencyCleanup`: they need a real or faked `GroupSession`, which the code does not abstract. A protocol seam for `GroupSession` is the next step and is a production change.

### 3.4 82 `Task.sleep` calls in tests
- **Location:** `Tests/GameRPGTests/SearchModelTests.swift` (8), `PhotoRPGTests/FolderListControllerTests.swift` (5), `GeneratorRPGTests/GeneratorRiskTests.swift` (5), `GameRPGTests/ConnectionOutboundQueueTests.swift` (5), `CoreRPGTests/FileUrlDataControllerFileOperationTests.swift` (5)
- **What:** Wall-clock waits used for synchronization.
- **Why:** Flake risk under TSan or on a loaded CI; the notes already list a SharePlay "expiry-yield flake".
- **Action:** Replace with `confirmation`, an awaited condition helper or an injected clock; keep real sleeps only where the production code itself sleeps.
- **Severity:** Low
- **Status: FIXED 2026-11-19 (the waiting sleeps).** New shared helper `Tests/TestSupport/AwaitCondition.swift` (`awaitCondition`, `conditionHolds`), a folder that belongs to the 14 unit-test targets. 44 of the 83 sleeps (82 in the audit, plus one in `MasterRPGUITests`) are gone: every poll loop and every "sleep, then assert" now waits for the condition (the default timeout is 30 s on purpose; a wait that succeeds returns at once, and the old loops were bounded by iteration count, so a 2 s deadline flaked under a full parallel run). "Nothing happens" assertions use `conditionHolds`, which checks the whole window instead of once after it. `ListenerRestartScheduler.schedule` takes an optional `sleep:` closure (default `Task.sleep`), so its two tests no longer wait 1.5 s each. `OneShotGate.hasWaiter` was added for the Generator gate test. The 39 sleeps that remain are on purpose: stand-ins for work or a stuck task inside the code under test (`SearchModelTests`, the 60/300 s sleeps, `AudioTrackLoaderTests`, the simulated downloads), a 1 ms or 20 ms step that makes two wall-clock timestamps differ (`*LinkControllerTests`, `PlayerCompanionsTests`), `HostingSessionPrewarmTests` (a blocking read), `MasterRPGUITests`, a trailing settle with no assertion after it (`AudioControllerTests.remoteCommands`), and three "give it time to suspend first" waits with no hook to wait on (`FolderListControllerTests.waitForRefresh` covers the production coalesce window, `TLSPasscodeHandshakeTests` the listener stop, `GeneratorRiskTests.cancelledWaiterStops`).

### 3.5 The `GameRPGTests` TSan crash blocks the strongest data-race signal
- **Location:** project notes (memory: "known failing tests")
- **What:** A TSan `DEADLYSIGNAL` crash in `GameRPGTests` (code-66 victim batches) is recorded as pre-existing. Not re-verified in this audit.
- **Why:** With strict concurrency the main remaining defence is TSan; a suite that crashes under it is not run under it.
- **Action:** Bisect the crashing batch, fix or quarantine the single test, then enable TSan in the plan.
- **Severity:** Medium
- **Status: FIXED 2026-11-19.** Run with `-enableThreadSanitizer YES` on iOS 27.2 / Xcode 27.2, the first run did not crash on a test: it restarted the runner three times on real data races (`ThreadSanitizer: Swift access race` in `PlayerConnectionDelegateMock`, whose four counters were plain `var`s written from the connection's tasks while the test polled them) and once with `DEADLYSIGNAL` / SEGV inside TSan's own allocator (`__tsan::MetaMap::AllocBlock` under a `Base64.decode` malloc while `FilePersistenceController.loadIfReadable` decoded a large file). Each race report ends the process and the runner relaunches, which is what produced the "exited with code 66" victim batches. The mock is now `Mutex`-backed. After that fix `GameRPGTests` ran clean under TSan four times in a row (941 tests, 0 reports, about 147 s against 61 s without). The allocator SEGV did not come back in those four runs; it is a TSan-runtime fault, not an app race, and it was not reproduced, so treat a lone recurrence as that known TSan limitation. There was no TSan setting in any test plan or scheme (the earlier note that the plans enable it was out of date). It is now a separate plan, `TestPlans/MasterThreadSanitizer.xctestplan` (GameRPGTests only, TSan on, random order), listed in the `MasterRPG` scheme; the default `MasterRPG` plan stays without it so everyday runs stay fast. Run: `xcodebuild test -project MasterRPG.xcodeproj -scheme MasterRPG -testPlan MasterThreadSanitizer -destination <iOS 27 simulator>`.

---

## 4. API modernity (of the test code)

### 4.1 Mixed frameworks are deliberate; XCTest remains only where required
- **Location:** `Tests/MasterRPGUITests/*` (XCTest + `AppIntentsTesting`), all other targets (Swift Testing)
- **What:** Unit tests use Swift Testing with `@Suite`/`@Test`; UI/intents tests use XCTest, which those frameworks need.
- **Why:** No action; recorded so the next reader does not "migrate" them.
- **Action:** None.
- **Severity:** Low

### 4.2 UI tests are not in the default `MasterRPG` plan
- **Location:** `TestPlans/MasterRPG.xctestplan`, `TestPlans/MasterAppIntents.xctestplan`
- **What:** `MasterRPG` = 14 unit targets; UI/intents tests sit in `MasterAll` (all) and `MasterAppIntents` (5 classes).
- **Why:** A developer running the default plan never executes the 64 UI tests.
- **Action:** Document which plan runs when; run `MasterAppIntents` nightly.
- **Severity:** Low

---

## 5. Bugs / untested high-risk logic

### 5.1 Store recovery that deletes the database files is untested
- **Location:** `Modules/CoreRPG/Persistence/CoreDataInitModel+Setup.swift:10-28`, `CoreDataPersistenceController.swift:42-50, 195-216`, `CloudKitCoreDataPersistenceController.swift:100, 140`
- **What:** `recoverStore` calls `destroyStoreFiles` (destroys the sqlite store, `-wal`, `-shm`) and reloads. No test names `CoreDataInitModel`, `recoverStore`, `destroyStoreFiles`, `recoverableError` or `CloudKitCoreDataPersistenceController`; `PersistenceIssueCenterTests` tests only the issue surface.
- **Why:** This is the one code path whose bug means local data loss. It decides what is "recoverable", and for the CloudKit store whether the data returns from iCloud.
- **Action:** With a temp-directory sqlite store: (a) corrupt file → `recoverStore` leaves a loadable empty store and `error == .none`; (b) non-recoverable error → files untouched, `.removeFile`/`.creation` surfaced; (c) the in-memory configuration never touches disk. Gate the CloudKit variant behind the same code using the local controller.
- **Severity:** High
- **Status: FIXED 2026-11-19.** `Tests/CoreRPGTests/StoreRecoveryTests.swift` (real SQLite files in a temporary folder): (a) a garbage store is classified as recoverable, `recoverStore` replaces it with a loadable empty store that accepts a save, `error` goes to `.none` and a stale `-wal` is not replayed; (b) a recovery that cannot delete (read-only folder) surfaces `.removeFile`, sets nothing up and removes nothing, and `.creation`, `.loadModel`, `.none` or a missing store url leave every file untouched; `loadFailure` sends disk-full, permission, locking, read-only and SQLITE_BUSY/FULL (also under an underlying error) to `.creation`, corruption and migration errors to `.migration`; `destroyStoreFiles` removes the database, `-wal` and `-shm` only and tolerates missing sidecars; (c) the in-memory configuration uses `/dev/null`, records no store url and `recoverFromError()` does nothing. The CloudKit controller calls the same `recoverStore`, so it is covered through that shared code; the `NSPersistentCloudKitContainer` itself needs an iCloud account and is not created. No production code changed.

### 5.2 CloudKit event monitoring and sync intake
- **Location:** `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:60-140` (`setupCloudKitEventMonitoring`, `loadDatabase`), `SyncDataControllable.swift:40-181`
- **What:** Same finding as §3.1 viewed from the persistence side: nothing names `CloudKitEventModelUpdate`, `RPGPersistentCloudKitContainer`, `startSyncConsumerIfNeeded`.
- **Why:** Sync-state (`CloudKitSyncState`) drives what the user is told; wrong state hides failed syncs.
- **Action:** Unit-test the pure mapping from event → `CloudKitSyncState` after extracting it from the container subclass.
- **Severity:** Medium
- **Status: FIXED 2026-11-19.** The mapping was extracted: `Modules/CoreRPG/Persistence/CloudKitSyncEvent.swift` holds `CloudKitSyncEvent` (a copy of what `NSPersistentCloudKitContainer.Event` says, which cannot be built outside the framework), `modelUpdate(now:)` (event → `CloudKitEventModelUpdate`) and `CoreDataInitModel.apply(_:)`. `setupCloudKitEventMonitoring` now only converts the event and applies the update; behaviour is unchanged. `Tests/CoreRPGTests/CloudKitSyncEventTests.swift` (13 test functions): a successful setup changes nothing, a setup/import/export without a result is in progress, a failed setup/import/export surfaces the reason, a success clears an earlier failure and stamps `lastSuccessfulSync`, a failure keeps the time of the last success, an unknown event type changes nothing, and a failed export after an import success ends in `.failed`. `startSyncConsumerIfNeeded` is covered by §3.1. Not covered: the `for await` loop itself and `RPGPersistentCloudKitContainer` (they need an iCloud account).

### 5.3 Platform coverage: iOS simulator only
- **Location:** `TestPlans/*.xctestplan`, `CLAUDE.md` (test commands), 11 test files with `#if canImport(UIKit)/os(iOS)/os(visionOS)`, `Tests/GameRPGTests/GameTablePinPawnTests.swift:3`
- **What:** The test commands in `CLAUDE.md` and the plans target the iOS simulator. The only visionOS-gated unit test file (`GameTablePinPawnTests`) needs a temporary scheme copy because the visionOS `build-for-testing` fails inside `swift-snapshot-testing` (CLAUDE.md). The documented test commands and the plans use an iOS destination only, so macOS (`MasterMac`) and tvOS (`MasterTV`) get no test run; `PortableGameRenderer`, `GameTableView+PlatformFlat` (macOS camera orbit vs iOS drag), `GameTableView+VisionOS`, `TableScaleGestureController`, `GameRenderer` have no test.
- **Why:** The macOS orbit-vs-drag rule and the visionOS pinch-to-scale/TabletopKit paths are platform-specific by design and have no regression net; today's visionOS pawn tests are the evidence (3 of 6 currently failing in the latest local run).
- **Action:** Make snapshot tests a separate package/target so visionOS `build-for-testing` works with the normal scheme; add a macOS test destination to `MasterRPG.xctestplan` for the `#if canImport(AppKit)`-clean suites; move more decisions into pure types (as `TableSeatAssignment`/`MapTableProjection` already do) so iOS can test them.
- **Severity:** High

### 5.4 Map sync metadata and battle sync
- **Location:** `Modules/MapRPG/Controller/GameController+Metadata.swift:1-480` (19 of 25 functions unnamed: `mapNetworkData`, `packageCoreMetadata`, `stablePackageMetadata`, `currentMapContentUpdate`, `applyPlayerMetadata`, `applyHealthPercent`, `updatePinState`, `releaseBattleCharacters`…), `GameController+BattleSync.swift` (`applyBattleRoundUpdate`, `battleHealth`), `GameController+Pins.swift` (`applyPinHandovers`, `placePlayerPinsInFirstRoom`, `keepBattleRosterInStepWithPlayerPins`)
- **What:** `PinHandoverTests` and the GameRPG map flow tests reach part of this indirectly; the functions above are not named anywhere.
- **Why:** Three recent fixes in this area (health percent, highlight reset, player character sync — memory notes) were each found by production logs, not by a test that existed beforehand. This file is where such regressions land.
- **Action:** Test `stablePackageMetadata`/`mapNetworkData` as pure functions (same map → same bytes; unchanged map → unchanged version), `applyHealthPercent` and `applyPlayerMetadata` as the master/player pair (player never writes `healthPercent`), `applyBattleRoundUpdate` for a round advance.
- **Severity:** Medium
- **Status: FIXED 2026-11-19, with one finding left open.** `Tests/MapRPGTests/MapSyncMetadataTests.swift` (26 test functions): the envelope (`mapNetworkData`); `stablePackageMetadata`/`packageCoreMetadata`/`currentMapAssetVersion` agree and are stable for an unchanged map; the content version changes with structure (room name, pin name, new pin) and does **not** change with a pin's runtime state (position, visibility, health, highlight, timestamp), while hidden content still changes it; `MapAssetFingerprint` follows map id, photo id and photo version; an authoritative generation wins, a record without versions is forgotten, `refreshAuthoritativeMapContentVersion` keeps version and asset version; `isCurrentGeneration` needs all six conditions; `applyPlayerMetadata` replaces identity and keeps position, health, highlight, death, timestamp and map id, and a late Character package updates the map pin without moving it; `battleHealth` (no Character, no entry, missing entry, base|modifier, clamping, free text); only the master writes `healthPercent` (`synchronizeBattleDefenders(isGameMaster: false)` leaves the master's value, the master recomputes it and does not rewrite an unchanged one); `mutatedPinState` timestamps are monotonic and a moved pin takes the map id; `libraryPins`, `mapStateBool`; the payload for players leaves out notes, hidden room text and hidden pins but keeps the version of the true map; a player applies the master's round advance and ignores an older or repeated update, refuses another generation, a missing payload or another map; a hidden pin on its turn is not named. **Finding (not changed):** equal map content does not give equal payload bytes. `MapSnapshot.redactedForNonMaster()` assigns `description` and `tags` through `wrappedValue`, which stamps a new CRDT clock on every export, although the doc comment on `MapUpdatePayload.encodeData()` says the bytes are compared across sends. Nothing compares them today (the content version is computed from the unredacted snapshot and is stable), so there is no user-visible bug; the test therefore compares decoded content and the version, not bytes. If byte comparison is ever added, keep the original clock when blanking those fields. Not covered here: `applyActiveBattleHighlights`, `releaseBattleCharacters`, `scrubLibraryMapsOfSessionContent` (partly in `SessionPinsNotInLibraryTests`), `updateMap` (in `GameControllerTests`).

### 5.5 Audio playback engine
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift` (no test names the type), `AudioController+Observation.swift`, `GameController+Playback.swift` (10 of 22 unnamed: `requestPause/Seek/Skip/Track`, `syncLoadedPlaylist`, `loadRemainingTracks`), `AudioListenerCoordinator.swift`, `Model/AudioPlayerModel.swift`, `AudioPlayerBarViewModel.swift`
- **What:** Playback *actions* are tested (`AudioPlaybackActionsTests`), the controller that owns `AVPlayer`/audio session and the observer box are not.
- **Why:** `AudioController` is the single owner of the audio session and of KVO; a leak or double-observer shows up as stuck playback in a game.
- **Action:** Introduce a small player protocol (`play`, `pause`, `seek`, `currentTime`) so the controller can run against a fake; test skip/seek ordering and audio-session release (`releaseAudioSession`).
- **Severity:** Medium
- **Status: FIXED 2026-11-19, without the protocol.** The premise was partly stale: `AudioControllerTests`, `AudioTransportCommandTests` (seek, resume, next/previous against a real audio file), `AudioLoopTests` and `AudioSessionStateMachineTests` already named the controller. A player protocol is not needed to test it: the real `AVPlayer` runs in the simulator, and every state the audit lists is observable on `AudioPlayerModel`, so no production code changed. `Tests/AudioRPGTests/AudioEngineTests.swift` (14 test functions, serialized because the audio session is shared): a pause that arrives while the session activates wins over the play on its way (and a play nobody paused does start the player, so the first check is not vacuous); `releaseAudioSession` keeps the session while playback is wanted or the player plays and gives it back otherwise; switching tracks pauses first; skip stays inside the playlist and does nothing without a current track; a newer seek cancels the older; the seek time keeps sub-second precision; replacing the playlist frees the dropped temp copies and resets current item, root, generation and the player item; removing the current track frees its file and clears the player, removing another keeps it; preparing the engine again does not add a second set of observers; a media-services reset replaces the player, ends the old observers, starts three new ones, reloads the current track, bumps the playback generation and tells the SharePlay coordinator; a remote command the game takes is not acted on locally; volume reaches the player and a mute remembers the last audible level. Not covered: the KVO status → `isPlaying` observer and the end-of-item notification (they need a playable file; the loop tests call `advanceAfterTrackEnd` directly), time-observer ticks, `AudioListenerCoordinator`, `AudioPlayerBarViewModel`, dedup of an already-present track in `add`.

### 5.6 Routing, scenes and window opening
- **Location:** `Modules/RolePlayGameKit/Route/WindowRouter.swift:1-361` (13 of 16 functions unnamed), `RootURLHandler.swift`, `Model/AppModel+Routing.swift:1-247` (11 of 14: `continueActivity`, `presentVTTImport`, `routeToModuleWhenReady`, `restoreRouteAfterLayoutChange`…), `Modules/CoreRPG/ScenesManager/ScenesManager.swift` (15 of 20: `openSpaceViewer`, `toggleSpaceViewer`, `setImmersiveSpaceState`…), `Modules/CoreRPG/Navigator/Core/NavigationSend.swift`/`NavigationAction.swift`
- **What:** `RolePlayGameKitRoutingTests` and `ScenesManagerObservationTests` test the main decisions; the per-layout action tables and URL handling are unnamed.
- **Why:** The memory notes record two navigator bugs (wrong column, wrong environment navigator) that only appeared at runtime on iPad/split view.
- **Action:** Table-driven tests for `RootURLHandler` (every URL shape → route), `AppModel+Routing` (layout change restores the route) and `WindowRouter` per size class.
- **Severity:** Medium
- **Status: FIXED 2026-11-19 for iOS/iPadOS; macOS and visionOS tables are not run (see §5.3).** `Tests/GameRPGTests/RoutingTableTests.swift` (27 test functions) asks the navigator what each action would send, so the tables are checked without a window. `WindowRouter`: every editor module on a regular layout (root route, reset, detail), on a compact layout (editors tab, reset, extended tab, detail), without an item (keeps the selection), Adventures/Characters/game/search/settings in both layouts, the editor window (tab switch plus the action that writes the selection onto the module, checked on `navigationModel.selectedItemId`), the search and settings windows, and routes forwarded to another window. `KnownRoutes.route` and the `RootRoute`/`ExtendedTabRoute` round trip for every module. `RootURLHandler`: a deep link before the database is ready becomes the pending route (item and entry kept, malformed ids dropped, scheme and module case-insensitive), foreign links and web addresses that merely end in `.gmz`/`.uvtt` are not handled, `.gmz`/`.uvtt`/`.dd2vtt`/`.mrpgfoundry` files (any case) open the matching import and wait for the database, the same document twice keeps the first request, a ready deep link is deduplicated within a second. `AppModel+Routing`: pending route replay and replacement, pending import presentation, `continueActivity` (own Handoff activity, incomplete activity, foreign activity), `navigator(for:)` for every module, and `rememberRouteForLayoutChange`/`restoreRouteAfterLayoutChange` for regular and compact layouts. Not covered: `ScenesManager.openSpaceViewer/toggleSpaceViewer/setImmersiveSpaceState` and the Spotlight branch of `continueActivity` (needs a Core Spotlight activity and a database), the delayed `presentVTTImport` task, and the size-class observers in `TabRootView`.

### 5.7 Foundry VTT / Universal VTT import front end
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:1-471`, `UniversalVTTDomainMapper.swift:1-264`, `FoundryVTTDomainMapper+Documents.swift` (14/14 unnamed), `+Indexes.swift` (13/13), `+SharedHelpers.swift` (27/31), `+Scenes.swift` (9/11), `Modules/CoreRPG/Foundry/FoundryVTTBridgeDecoding.swift:1-507`, `FoundryPackageResolution.swift` (13/18), `FoundryTextDecoder.swift` (12/17), `Modules/CoreRPG/Import/ExternalImportReviewSession+Internals.swift` (8/11)
- **What:** The reader/zip/level-DB/sanitizer layers are well tested (`Tests/CoreRPGTests/Foundry/*`, `GameRPGTests/FoundryVTTDomainMapper*Tests`). The import *view-model* (`FoundryImportModel`, load/destination state), the `+Documents`/`+Indexes` mappers and the bridge decoder have no test that names them. Some may be reached through `FoundryVTTDomainMapperValueHierarchyTests`; I could not confirm which.
- **Why:** Imports consume untrusted third-party packages; a mapper regression produces silently wrong rules/characters in the user's library.
- **Action:** Add fixture-based tests (one small world pack) asserting the mapped item counts and folder placement, and a model test for `LoadState` transitions (cancel, failure, partial). Move the RolePlayGameKit tests to their own target (§9.1).
- **Severity:** Medium
- **Status: FIXED 2026-11-19 for the import view-model; the mappers were already covered.** `Tests/GameRPGTests/FoundryImportModelTests.swift` (14 test functions) runs `FoundryImportModel` against a temporary registry and archive folder: initial state, what `select` resets, a Universal VTT file loading to the preflight with a resolved source, an unknown file, an invalid resolution and a missing file failing with a message (and not locking the selection), a load replaced by a newer selection never storing the first file's data, a cancelled load, category toggling and the privacy-safe defaults, source choice only while the source is ambiguous, a selection error, and a review without a source failing. Not covered: `prepareReview`/`commit` against a real library, a Foundry world pack end to end (a fixture pack is still wanted), and moving the RolePlayGameKit tests to their own target (§9.1).

### 5.8 `ConversationEngine` has no seam
- **Location:** `Modules/GeneratorRPG/BasicAI/Engine/ConversationEngine.swift:10-427`, `ConversationContextBuilder.swift`, `Controller/ConversationSessionModel.swift`
- **What:** The engine (sliding window, overflow recovery at lines 93 and 117, summarisation at 314, session reset) holds a concrete `LanguageModelSession`; no test names the engine, the session model or the context builder. `TranscriptTokenCounting` is tested.
- **Why:** Overflow recovery is exactly the code that runs rarely and on real user data; today it can only be exercised on a device with Apple Intelligence.
- **Action:** Put the session behind a one-method protocol, test: overflow → fresh session carrying a summary; cancel during streaming; `setMaxContextSize` shrink applies the window.
- **Severity:** Medium
- **Status: FIXED 2026-11-19 with a narrower seam than the audit proposed.** `ConversationEngine` got three internal hooks (`ModelHooks`: `respond`, `streamedContent`, `summarize`) instead of a session protocol; the production engine leaves them `nil`, and everything around them is the real code. `Tests/GeneratorRPGTests/ConversationEngineTests.swift` (21 test functions, 3 suites) covers: blank prompts refused before the model, trimming, overflow → summary → new session → continuation prompt with the summary and the user's message last (one-shot and streaming), a failing summary resetting the session and answering with the trimmed reset message (also as the partial response) or rethrowing without one, a blank reset message counting as none, a cancelled summary **not** resetting the session, other errors passing through, the `isSummarizing` flag, cancelling a stream, partial responses in order, a superseded request not dropping the newer one's handle, `setMaxContextSize`, `rebuild`, state notifications, plus `ConversationState`, `GenerationSettings` (fixed seed reused) and `ConversationContextBuilder`. Not covered: the sliding-window shrink (`shouldApplyWindow` needs a transcript, which only a real session builds) and the real `LanguageModelSession` streaming.

### 5.9 App Intents: UI tests cover 5 modules, unit tests cover `ItemIntentSupport`
- **Location:** `Tests/MasterRPGUITests/{Adventure,Audio,Dice,Item,Navigate}IntentTests.swift`; unnamed: `Modules/GameRPG/Intent/GameIntents.swift` (`EndBattleIntent`…), `GeneratorRPG/Intent/GeneratorManagementIntents.swift`, `GeneratorEntity.swift`, `AdventureRPG/Intent/UpdateAdventureIntent.swift`, `CoreRPG/Intent/IntentDonations.swift`, `CoreRPG/Persistence/RpgSpotlightIndexerDelegate.swift`, `Sources/MasterRPG/MasterRPGShortcuts.swift`, `MasterRPGSpotlightIndexer.swift`
- **What:** Game, Generator, Map, Character, Table, Weather, Pdf, Photo, Space intents have no intent-level test; only the shared body is unit tested. The Spotlight tap path is recorded as unverified on device (memory: App Intents re-audit).
- **Why:** Intents run outside the app UI where a crash or a wrong item is visible to the user in Siri/Shortcuts.
- **Action:** Unit-test `perform()` bodies through `ItemIntentSupport` for each module with an in-memory root (cheap, no UI); keep UI tests for the Siri path only.
- **Severity:** Medium
- **Status: PARTLY FIXED 2026-11-19.** `Tests/GameRPGTests/GameIntentGuardTests.swift` (7 test functions) runs `NextTurnIntent`, `NextRoundIntent`, `EndBattleIntent` and `StopGameIntent` through `perform()` with the dependency set on the intent: no battle (master and player), no running game, a player not allowed to stop the master's game (no flag change), the Control Center next turn doing nothing without a battle, and the three dialogs being different texts. `Tests/CoreRPGTests/IntentDonationsTests.swift` (4 test functions) covers the donation throttle (once per item, independent items, a missing item not starting the throttle) and a cancelled open dwell. `ItemIntentSupportTests` already covered the shared bodies. Not covered: a battle that is running (next turn / round / end with confirmation), `JoinGameIntent`, the Generator and Adventure update intents, the other modules' `perform()` bodies, `RpgSpotlightIndexerDelegate`, `MasterRPGShortcuts`.

### 5.10 SpaceRPG capture pipeline
- **Location:** `Modules/SpaceRPG/Record/AppDataModel.swift:1-509` (17 of 17 unnamed), `CaptureFolderManager.swift` (6/6), `OnboardingStateMachine.swift`, `AppDataModel+Orbit.swift`, `PlayerView.swift`, `ModelView.swift`
- **What:** 53 SpaceRPG files (4.5 k LOC) are named by no unit *or* snapshot test; the 178 SpaceRPG tests cover the model/editor side.
- **Why:** `OnboardingStateMachine` is a pure transition table and `CaptureFolderManager` does file creation/cleanup (`cleanupStaleScans` deletes folders) — both are testable without a camera.
- **Action:** Test the state machine's transition table and `CaptureFolderManager` against a temp directory (create, load shots, parse ids, stale cleanup keeps live scans).
- **Severity:** Medium
- **Status: FIXED 2026-11-19 for the parts that need no camera.** `OnboardingStateMachine`, `CaptureFolderManager` and `ShotFileInfo` were behind `#if os(iOS) && !targetEnvironment(simulator)` only because `Logger.scanner3D` lived in the device-only root view; the logger moved to `Scanner3DLogger.swift` and the three files are no longer gated (all five platforms build). `Tests/SpaceRPGTests/CaptureOnboardingTests.swift` (19 test functions) covers the initial/reset rules, every transition of the table (each state reached through real transitions by a search over the machine's own `enter`), refused inputs, end states, both complete walks, the offered inputs, every state being reachable, and the table being closed; and the capture folder: shot id parsing (valid and foreign names), the three subfolders below Caches, two scans in one second getting different folders, `loadShots` sorting/filtering/reloading/throwing, and the cleanup keeping a live scan. The stale-scan cleanup itself is in `ScanFolderCleanupTests`. Not covered: `AppDataModel` and `+Orbit` (they need a camera session), `PlayerView`, `ModelView`.

### 5.11 Game statistics aggregation
- **Location:** `Modules/GameRPG/Statistics/Controller/GameStatisticsController.swift:1-351` (12 of 17 unnamed: `activityPoints`, `categoryPoints`, `diceOutcomePoints`, `heatMapPoints`, `modulePoints`, `networkPoints`, `participantPoints`, `splitInterval`)
- **What:** `GameStatisticsControllerTests` and `GameStatisticsRiskTests` exist and name the controller 12 times; the chart-point builders are unnamed.
- **Why:** Pure bucketing logic (time splits, empty ranges, boundaries) with a history of off-by-one risk.
- **Action:** Table tests for `splitInterval` boundaries and each `*Points` builder with an empty and a one-event log.
- **Severity:** Low
- **Status: FIXED 2026-11-19.** `Tests/GameRPGTests/GameStatisticsBucketingTests.swift` (22 test functions) reaches the private builders through `summary`: empty data, one session, the 15-minute boundary and observer/proxy sessions, the ten newest sessions, splits at midnight, at a month end and at a week start (Monday vs Sunday calendar), a game ending exactly at midnight, two games on one day, a reversed interval, the heat map (hour split, shared cells, time zone), role/character/adventure points and their placeholders, dice outcomes, own-rolls-only with and without a recorded local participant, module, party and network points, and uncounted sessions leaving no trace.

### 5.12 Per-module controllers without a test file
- **Location:** `ItemControllerTests` missing for Audio, Map, Photo, Pdf, Space, Table, Weather (present for Adventure, Character, Dice); `EditControllerTests` missing for Photo (`Modules/PhotoRPG/Controller/EditController.swift`, 6 of 9 functions unnamed) and Weather; `PdfRPG/Controller/EditController.swift` (`LinkPdfModuleTransferable`); `PhotoRPG/Controller/CacheController.swift`, `MapRPG/Controller/CacheController.swift`; RuleRPG has no Item/Export/Link/FolderList test files; GeneratorRPG has only `DataControllerTests`
- **What:** Test-file matrix per controller kind (names taken from `Tests/<Module>Tests`).
- **Why:** The controllers are the architecture's unit of testability (MVC with stateless controllers). Missing files mean missing add/remove/trash/ordering tests per module; the shared generic code is covered through other modules, the module-specific overrides are not.
- **Action:** Create one generic `ItemControllable` conformance suite (add, delete, restore, order, duplicate names) parameterised over the 10 module factories rather than 7 new files (§10.2).
- **Severity:** Medium
- **Status: PARTLY FIXED 2026-11-19.** `Tests/GameRPGTests/ModuleItemLifecycleTests.swift` runs 7 shared-lifecycle tests for each of the 11 module roots of one in-memory app (77 cases): add an item, add a folder, unique ids, delete keeps the others, delete of an unknown id, add after delete, controller belongs to its module. Not covered: restore from the trash, ordering and duplicate names (these need the module's edit controller and are not on the type-erased root), the missing Photo/Weather `EditControllerTests`, the two `CacheController`s (§7.2), and RuleRPG/GeneratorRPG specific files.

### 5.13 Shared import/export engine tested through modules, not directly
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:1-765` (28 of 35 unnamed: `normalizeImportedItemForMerge`, `reusableExistingFileUrl`, `settleImportedFile`, `shouldDeferGameModeFolderImport`, `admitPeerFolders`, `appendDeletionReviewItem`…), `ExportControllable.swift:1-502` (21 of 27: `bfsExportResults`, `exportingFolder`, `fitsImportBlock`, `finalizeExportResults`), `ImportControllable+ReviewLog.swift`, `EditControllable+Folders.swift` (`FolderEditScope`)
- **What:** Photo, Table, Character, Adventure, Audio import/export tests exercise the engine end to end (`PeerFolderImportTests`, `ImportGameAuditTests`, `UntrustedImportTests`); the engine's helpers are unnamed, and Rule/Generator have no import/export test.
- **Why:** 1,267 lines of the most shared logic; a regression shows up as a failure in 10 modules at once, which hides where it is.
- **Action:** Test the engine once with a minimal fake module (merge, peer-folder admission, deferred folder import in game mode, file settle) and shrink the per-module tests to module-specific mapping.
- **Severity:** Medium
- **Status: PARTLY FIXED 2026-11-19 (export side).** `Tests/DiceRPGTests/ExportEngineHelperTests.swift` (12 test functions) tests the shared export engine once on the simplest module: a complete folder promoted, an incomplete one written as a partial folder, a selected folder exporting its children, promotion cascading up, a partial inner folder making every ancestor partial, root items and an empty selection, the traversal (dedup, cycles, missing ids skipped without following their children), the simple-entries traversal stopping at leaves, and `finalizeExportResults`; `ExportBlockLimitTests` pins `fitsImportBlock` at the limit. **Finding, not changed:** `bfsExportResults` visits an id twice if the same id is passed twice in `seedIds` (its own dedup covers only discovered ids); the result is a set and `ItemModuleIds` already removes duplicates, so nothing is wrong today. The import helpers (`admitPeerFolders`, `shouldDeferGameModeFolderImport`, `sanitizeImportedFileUrl`, …) are `private` and still only covered through the module-level `PeerFolderImportTests`, `ImportGameAuditTests` and `UntrustedImportTests`; a fake-module engine test would need them widened to `internal`.

### 5.14 `GameCenterController`
- **Location:** `Modules/GameRPG/GameCenter/GameCenterController.swift:1-219`
- **What:** 12 of 13 functions unnamed (`authenticate`, `reportAchievements`, `beginReporting`/`finishReporting`); the controller is named 44 times because the achievements *rules* are tested through `GameStatisticsControllerTests`.
- **Why:** Reporting deduplication and error paths hit a service that cannot be called from tests.
- **Action:** Wrap `GKAchievement.report` in a protocol and assert one report per unlocked id, none when unauthenticated.
- **Severity:** Low
- **Status: FIXED 2026-11-19.** `GameCenterController` now talks to a `GameCenterService` protocol (live: `GameKitGameCenterService`), and the decision of what to report is the pure `GameCenterController.updates(for:existing:)`. `Tests/GameRPGTests/GameCenterReportingTests.swift` (14 test functions): nothing loaded or reported when unauthenticated, a first game reported once with the banner only at 100 percent, zero progress not reported, no report call without progress, unchanged progress not reported again (also across two reports), higher progress reported and lower never lowered, duplicate ids from Game Center not trapping, duplicate progress reported once, the banner boundary, and a failing load / failing report / cancelled report / recovery after an error. `authenticate()` and `setAccessPoint` stay bound to GameKit.

### 5.15 Small controller/model gaps
- **Location:** `Modules/CharacterRPG/Controller/SearchController.swift` (`characterInspectorResult`, `listModeCharacterResults`, `makeEntryResult`, `collectValueEntries`); `Modules/PdfRPG/Pdf/PdfSearchModel.swift`; `Modules/CoreRPG/Model/EditorLinkModel.swift`; `Modules/GameRPG/Model/GameNetworkModel+Shape.swift`; `Modules/CoreRPG/FileViews/GameBundleBrowserModel.swift`; `Modules/CoreRPG/Simple/SimpleSheetEditingSession.swift`; `Modules/CoreRPG/Links/ReferenceScanner.swift` (6 of 8)
- **What:** Self-contained models/controllers that no test names.
- **Why:** Each is small, user-facing and cheap to test.
- **Action:** One focused test file each; start with `ReferenceScanner` (link integrity) and `SearchController` (character list mode).
- **Severity:** Low
- **Status: FIXED 2026-11-19.** `ReferenceScannerTests` extended to 10 (no scheme, exact scheme, fields, several links, bad entry, empty name, broken neighbour); `Tests/PdfRPGTests/PdfSearchModelTests.swift` (7); `Tests/GameRPGTests/GameNetworkModelShapeTests.swift` (15: timestamp policy, acknowledgements, report-list envelope, asset requests, dice roll, group events and their limits, presentation, asset carrying, `reference`); `Tests/CoreRPGTests/GameBundleBrowserModelTests.swift` (9: the status machine, with a private-address download failing without a network); `SimpleSheetEditingSessionTests` (6); `EditorLinkModelTests` (7); `Tests/CharacterRPGTests/InspectorParentSearchTests.swift` (7: the parent-scoped inspector search, group entries reported against the character, the recursion guard, localized matching). The Character `SearchController` list/folder/global paths were already tested; only the parent-scoped path was missing.

---

## 6. Security

### 6.1 `GuardedRemoteDownload` is untested
- **Location:** `Modules/CoreRPG/Files/GuardedRemoteDownload.swift:11-111`
- **What:** No test names `GuardedRemoteDownload`, `allowsPrivateHosts`, `connectedToPrivateAddress` or `downloadWithResponse`.
- **Why:** This is the SSRF/size guard introduced by CODE_AUDIT_18 §6.4/6.5, CODE_AUDIT_19 §6.2, CODE_AUDIT_20 §6.2: it must reject a redirect to a LAN host, a body over `maximumBytes`, a non-2xx response and a private connected address. A refactor of the static `session`/`Delegate` could remove each silently.
- **Action:** Make the `URLSession` configuration injectable (a `URLProtocol` stub) and add four cases: redirect to a private IP, oversize body (streamed, aborted), 404, connected-to-private after a public name; plus the happy path.
- **Severity:** High

### 6.2 `SecurityScopedAccess`
- **Location:** `Modules/CoreRPG/Files/SecurityScopedAccess.swift:1-94`
- **What:** `withSecurityScopedAccess` / `startSecurityScopedAccess` have no test.
- **Why:** An unbalanced start/stop leaks scoped access (stops working after a number of opens) — reproducible only with a unit test on a temp URL.
- **Action:** Test balance on throw, on cancellation, and nested use.
- **Severity:** Low

### 6.3 Share extension save path
- **Location:** `Sources/RPGShare/ShareExtensionSaveController.swift:1-117`, `ShareViewController.swift`, `SharingInput.swift`; `Sources/RPGShare/ItemProviderImporter.swift` is covered (44 references)
- **What:** `ShareExtensionSaveRuleTests` (in `GameRPGTests`) covers the rules; `saveContent` — which writes into the app-group container — has no test. Memory note: "share-extension container" is an open item in CODE_AUDIT_15.
- **Why:** The extension runs in a separate, memory-limited process with no UI to show errors.
- **Action:** Extract `saveContent` into `CoreRPG`/a package target so it can be unit-tested with a temp container.
- **Severity:** Medium

### 6.4 Untrusted-import coverage is good — keep it
- **Location:** `Tests/CoreRPGTests/UntrustedImportTests.swift`, `Foundry/FoundryVTTArchiveSanitizerTests.swift`, `FoundryZIPArchive` tests (105 references)
- **What:** Path traversal and archive sanitizing are covered; recorded as the positive example.
- **Why:** The gap is only that the *module-level* `sanitizeImportedFileUrl` (`ImportControllable.swift`) is not named directly (§5.13).
- **Action:** One direct test with `../` and absolute-path inputs.
- **Severity:** Low

---

## 7. Performance

### 7.1 Almost no performance regression tests
- **Location:** `Tests/CoreRPGTests/FolderAuditPerformanceTests.swift` (the only one found)
- **What:** Folder listing is guarded; large-library load, import of a big Foundry world, SharePlay package assembly and map fog rendering have no measured budget.
- **Why:** Earlier audits found a full-reindex-per-save and a sync-load-on-init; both are invisible to correctness tests.
- **Action:** Add 3–4 `measure`/time-budget tests with generous thresholds (10 000 items load; 5 000-entry folder import; fog render of the example map).
- **Severity:** Low

### 7.2 `ObjectCache` and the two `CacheController`s
- **Location:** `Modules/CoreRPG/Cache/ObjectCache.swift:1-99` (7 of 10 unnamed: disk save/load/eviction), `PhotoRPG/Controller/CacheController.swift`, `MapRPG/Controller/CacheController.swift`
- **What:** Only `FileUrlDataControllerTests` touches the cache.
- **Why:** Eviction and disk fallback decide memory use of image-heavy modules.
- **Action:** Test eviction at the count limit and the disk round trip with a temp directory.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 Snapshot baseline missing
- **Location:** `Tests/SnapshotTestSupport/SnapshotTestEnvironment.swift:60-65` (reference path `Snapshots/Xcode27/<Target>/<Suite>`), `Scripts/verify_snapshot_view_coverage.rb` ("Missing root snapshot baseline directory Snapshots/Xcode27")
- **What:** `ls Snapshots` → "No such file or directory". No `__Snapshots__` folder exists either. ~550 snapshot test functions in 13 `*SnapshotTests` targets and the `MasterSnapshot` plan have no reference images.
- **Why:** With `swift-snapshot-testing`, a missing reference is a failure the first time (and writes the image). Either the suite is red, or someone records on the machine that runs it and the "reviewed" baseline is whatever that run produced. The coverage number the script prints (89.8 %) is therefore a count of declared cases only. Memory note: the folder was already absent on 2026-10-09 and Xcode is now 27.2.
- **Action:** Record and commit the baseline (§2.1); decide whether the baseline lives in the repo or in a separate artifact store (~550 reference images); make `run_snapshot_tests.sh verify` fail when the directory is missing.
- **Severity:** High

### 8.2 Modules and targets with no snapshot target
- **Location:** `Scripts/verify_snapshot_view_coverage.rb` output: RuleRPG 0/17 views, DiceRollerWidget 0/10, RPGShare 0/10, MasterRPG app 0/3; there is no `Tests/RuleRPGSnapshotTests` and no `RolePlayGameKitSnapshotTests` (its generated cases live in `GameRPGSnapshotTests/RolePlayGameKitGeneratedPreviewSnapshotTests.swift`)
- **What:** The script's own gate (80 %) hides four fully uncovered targets.
- **Why:** The widget and share extension are separate processes with their own layout constraints (accent/tinted rendering) and no other UI check.
- **Action:** Add `RuleRPGSnapshotTests`; render the widget views through `ImageRenderer` in a unit test for the main families; set the gate per module, not globally.
- **Severity:** Medium

### 8.3 Snapshots exclude visionOS; tvOS and macOS are never rendered
- **Location:** `Tests/SnapshotTestSupport/SnapshotTestEnvironment.swift:3` (`#if !os(visionOS)`), `MasterSnapshot.xctestplan` (one destination)
- **What:** All references are iOS renderings.
- **Why:** The macOS and tvOS layouts (`Sources/MasterMac`, `MasterTV` and the `#if os` branches in the views) are not visually tested; the visionOS ornaments and volumetric toolbar are verified by hand with a probe app (memory).
- **Action:** At least a macOS snapshot destination for the sidebar/toolbar views; document the visionOS manual check in `Docu/SNAPSHOT_TESTING.md`.
- **Severity:** Medium

### 8.4 UI tests are navigation smoke tests
- **Location:** `Tests/MasterRPGUITests/ContentModuleUITests.swift:7-129`, `GameSettingsAndSearchUITests.swift:7-70`
- **What:** 14 tests: open each module and press create, a statistics toggle, theme chooser, global search. Nothing covers starting/joining a game, the map editor, import/export, trash/restore, the drag-and-drop link flows or the Siri-to-app navigation beyond `NavigateIntentTests`.
- **Why:** The product's central flow — game master + player in a game — is only tested below the UI (GameRPGTests, 935 tests). Window/scene bugs recorded in the notes (navigator in split view, attachment focus crash) were all found by hand.
- **Action:** Add 5 end-to-end UI journeys: create adventure → add character → start local game; join code entry; import a sample pack from `Scripts/example_data`; trash and restore; open map editor and draw a room.
- **Severity:** Medium

### 8.5 View logic that cannot be tested where it lives
- **Location:** `Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:1-494` (`QuickEditorLazyValue` and link write-back), `Modules/CoreRPG/LGViews/GroupEditorView.swift:1-305`, `Modules/TableRPG/View/TableGenerationRootView.swift` (`LazyGenerationModel`), `Modules/GameRPG/GameViews/BatteryView.swift` (`BatteryMonitor`), `Modules/PhotoRPG/Photo/ImageViewer.swift` (`ViewportModelStore`), `Modules/MapRPG/View/DisplayConfigEditor.swift`
- **What:** View files that declare their own model/controller types with logic; only snapshot references (`sr` = 4–8) exist.
- **Why:** `QuickEntryEditorView` is the exact place where the earlier health/link bug was found (memory: "Character sheet inline quick-editor… link destroyed"); the fix is guarded by an end-to-end regression test, not by view-model tests.
- **Action:** Move the model types out of the view files (CLAUDE.md already asks for view logic in view models) and test them directly.
- **Severity:** Medium

### 8.6 No accessibility or Dynamic Type tests
- **Location:** `Scripts/verify_accessibility.rb` (static check only), no UI test sets `XCUIApplication.launchArguments` for Dynamic Type or VoiceOver
- **What:** Accessibility is enforced by script, not by test.
- **Why:** The snapshot environment pins one Dynamic Type size (`Docu/SNAPSHOT_TESTING.md`).
- **Action:** Add a second snapshot configuration at `accessibility3` for ~10 critical views, and an `performAccessibilityAudit()` UI test per module root.
- **Severity:** Low

---

## 9. Dead code / duplication / test-suite hygiene

### 9.1 RolePlayGameKit and RuleRPG have no test target of their own
- **Location:** `Tests/GameRPGTests/{AppModelResetDataTests,InAppControllerTests,RolePlayGameKitRoutingTests,FoundryVTTDomainMapper*Tests,FoundryMediaNormalizerTests,FoundryImportProgressPresentationTests,ShareExtensionSaveRuleTests}.swift`; `Tests/RuleRPGTests` exists but no `RolePlayGameKitTests`
- **What:** 10 test files for `RolePlayGameKit` (and the share extension) live in `GameRPGTests`.
- **Why:** The per-module convention (one `<Module>Tests`, one `<Module>SnapshotTests`) is broken for the module with 10 k LOC and the Foundry importers, so ownership and per-module coverage reports attribute those tests to GameRPG.
- **Action:** Add `RolePlayGameKitTests`, move those files, add it to all three unit plans.
- **Severity:** Medium

### 9.2 Per-module controller tests are copies of each other
- **Location:** `Tests/*/ExportControllerTests.swift` (10), `ImportControllerTests.swift` (10), `LinkControllerTests.swift` (10), `SheetControllerTests.swift` (10), `DataControllerTests.swift` (11)
- **What:** Same test names and structure per module.
- **Why:** A change to the shared protocol means ten edits; the modules without a file (§5.12) simply drift.
- **Action:** Generic conformance suites with a `ModuleFixture` (see §10.2).
- **Severity:** Low

### 9.3 Production-compiled preview/mock types are the test fixtures
- **Location:** `Modules/*/Model/MockData.swift`, `Modules/CoreRPG/Fake/FakeEditController.swift`, `Modules/GameRPG/Preview/PreviewData.swift`
- **What:** Tests rely on `MockRoot.importTestData()` and `Fake*` types that ship in the Release binary (`#Preview` is built in Release; memory note).
- **Why:** Not a gap by itself; it blocks making fixtures `#if DEBUG` and makes test data changes also change previews and snapshots.
- **Action:** Keep as is; do not rewrite fixtures without regenerating the baseline (§8.1).
- **Severity:** Low

### 9.4 Tracked-but-unused snapshot generator report path
- **Location:** `Docu/SNAPSHOT_TESTING.md` says the report is `Tests/SNAPSHOT_GENERATION_REPORT.md`; the file is at `Docu/SNAPSHOT_GENERATION_REPORT.md`
- **What:** Stale path in docs.
- **Why:** Misleads whoever regenerates the cases.
- **Action:** Fix the doc.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

### 10.1 Establish a measured baseline
Run `MasterAll` once with coverage on and export `xccov view --report --files-for-target` per module; store the per-module figures in `Docu/` and compare after each batch of fixes. This audit's static list should be re-ranked by the real numbers.

### 10.2 Shared conformance suites for the Controllable protocols
`ItemControllable`, `ImportControllable`, `ExportControllable`, `LinkControllable`, `SyncDataControllable` already hold the logic; write one generic parameterised suite each, fed by a `ModuleFixture` per module (factory + sample item). This closes §5.12/§5.13/§3.1 for all modules at once.

### 10.3 Fakes at the system boundaries
Introduce small protocols (and fakes under `Tests/`) for: `LanguageModelSession` (§5.8), `AVPlayer` (§5.5), `GKAchievement` (§5.14), `URLSession` in `GuardedRemoteDownload` (§6.1), the clock for audio deadlines (§3.2) and the persistent store loader (§5.1). Each is under 30 lines and unlocks a named gap.

### 10.4 Make snapshot tests a separate package or workspace scheme
That removes the visionOS `build-for-testing` failure noted in `CLAUDE.md` and lets the normal `MasterRPG` scheme run the `os(visionOS)` unit tests directly.

### 10.5 Gate pull requests on a short list
Unit plan on iOS (with `RolePlayGameKitTests`), `MasterSnapshot` verify, `verify_snapshot_view_coverage.rb` (once fixed), plus a nightly `MasterAppIntents`. A silently skipped suite count should appear in the summary (§2.5).

### 10.6 Write the regression test first when a production log leads to a fix
The recent health-percent, highlight-reset and player-sync fixes each had a failing production log before a test existed (memory). The area behind them is §5.4; a test per past bug there is the cheapest safeguard.

---

## 11. What was NOT audited

- **Measured coverage.** No full-suite run; see the method note. Figures are name-token matches, not executed lines.
- **Test quality.** I did not read the 3,190 test bodies for weak assertions, over-mocking or order dependence; only the structure, gates and the files named above.
- **Currently failing tests.** The recorded failures (ConverterController re-hide, FileUrl double-path, cloud read-back family, SharePlay expiry yield) come from project notes and were not re-run.
- **visionOS-specific RealityKit/TabletopKit behaviour** (no simulator interaction); the 3D dice and pin geometry are generated in code and verified by hand per the notes.
- **Localization, build settings, schemes beyond the shared test plans, third-party packages.**
- **`Docu/`, `Scripts/example_data`, Resources catalogs, `Integrations/`.**
- **The Xcode Cloud / CI configuration** — it is not in the repository, so whether `MasterRPG.xctestplan` or `MasterAll` runs there could not be checked (tests mention "CI" in skip reasons).
- **SwiftUI expert pass (skill step 4).** Skipped: the request was about tests, and §8 reports only test-visible UI findings.

---

## 12. Verification

Findings assigned High were checked by opening the cited lines:

- **§5.1** — `Modules/CoreRPG/Persistence/CoreDataInitModel+Setup.swift`, lines 10-28: `recoverStore` guards on `recoverableError`, calls `container.destroyStoreFiles(at: url)` and reloads. `CoreDataPersistenceController.swift` lines 42-50: `destroyStoreFiles` runs `destroyPersistentStore` then removes `""`, `-wal`, `-shm` files. `grep -rn "CoreDataInitModel\|recoverStore\|destroyStoreFiles" Tests` returns only `SharePlayPackageTransportTests` (a different `loadFailure` hit) and `PersistenceIssueCenterTests` (issue center), neither calling the recovery.
- **§3.1 / §5.2** — `Modules/CoreRPG/Controllable/SyncDataControllable.swift`, lines 40-52 (`start()`, `updateFromSync` queued "in the order the notifications arrive"); `grep -rn "SyncDataController\|updateFromSync\|CoreDataChangeObserver\|startSyncObservation" Tests` → no match.
- **§6.1** — `Modules/CoreRPG/Files/GuardedRemoteDownload.swift`, lines 11-40: private-address, status and size checks all live in `downloadWithResponse`; `grep -rnE "GuardedRemote|allowsPrivateHosts|connectedToPrivateAddress|downloadWithResponse" Tests` → no match.
- **§5.3** — `grep -rl "os(visionOS)" Tests` → only `Tests/GameRPGTests/GameTablePinPawnTests.swift`; plans in `TestPlans/*.xctestplan` list unit targets with no destination per platform; `CLAUDE.md` documents the temporary-scheme workaround; latest local result bundle `Test-MasterRPG-2026.11.19_12-39-28` has 3 failed of 6 tests (`Multiple pawns keep independent highlight rings`, `Dead and highlighted visuals remain independent`, `Player taps mutate the live pin and send targeted map-pin updates`).
- **§8.1** — `ls Snapshots` → "No such file or directory"; `ruby Scripts/verify_snapshot_view_coverage.rb` → "Missing root snapshot baseline directory Snapshots/Xcode27"; reference path built at `Tests/SnapshotTestSupport/SnapshotTestEnvironment.swift:60-65`; `find . -type d -name __Snapshots__` → none.

Checked and **dropped**: "Character/Table version digest untested" — `Tests/CharacterRPGTests/ValueModelTests.swift:150-171` and `Tests/TableRPGTests/GameControllerTests.swift:73-77` test it; only the golden-value gap remains (§2.4). "`GameController+Pins` untested" — `Tests/MapRPGTests/PinHandoverTests.swift` covers the handover path; only three helpers are unnamed (§5.4).
