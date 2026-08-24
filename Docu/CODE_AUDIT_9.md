# MasterRPG Code Audit — Round 9

Generated 2026-08-23. Scope: ~268,000 Swift LOC across ~2,006 files, covering all 15 dynamic-framework modules (`AdventureRPG`, `AudioRPG`, `CharacterRPG`, `CoreRPG`, `DiceRPG`, `GameRPG`, `GeneratorRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `RolePlayGameKit`, `RuleRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG`) and the `MasterRPG`/`MasterMac`/`MasterTV`/`RPGShare`/`DiceRollerWidgetExtension` targets. No `Dead/` or archived directory exists in this repo, so nothing was excluded by convention — only `.git/`, `.build/`, `DerivedData/`, and `xcuserdata/` were skipped.

**This is a full-codebase pass, the ninth in this repo's history.** `Docu/CODE_AUDIT_1.md` through `_8.md` (2026-08-07 → 2026-08-20) already covered the whole codebase eight times; since round 8, seven additional **scoped, deep-dive** audits ran (`CODE_AUDIT_Sheet.md`, `_Search.md`, `_EditItem.md`, `_Import.md`, `_BattleRound.md`, `_Link.md`, `_Game.md`, 2026-08-21 → 2026-08-22), each targeting one subsystem in more depth than a full-codebase pass allows. **All seven were remediated same-day or next-day** — verified directly against git history, not assumed:

| Scoped audit | Fix commit | Verified |
|---|---|---|
| Sheet | `0a9241cd` "fixed: Sheet Code Audit" | landed in the same commit as the doc |
| Search | `c9778601` "fixed: Search CODE audit applied" | landed in the same commit as the doc |
| EditItem | `3e7ba669` "fixed: code audit of item / edit and maybe a shareplay player crash" | landed in the same commit as the doc; spot-checked §5.6's `GroupEditorModel.tags` fix directly in current source — present, with an in-code comment citing the finding |
| Import/Export | `c6794214` "fixed: seaveral seating bugs and the import /export audit" | landed one commit after `3f367fd1` added the doc; spot-checked §6.1's `maxSingleBlockSize` guard directly in current source — present |
| Link | `6fbe6a68` "fixed: code audit links" | landed in the same commit as the doc |
| BattleRound | `a572588f` "fixed: BattleRound code audit" | doc's own §0 fix-status table confirms 21 of 24 findings fixed, 3 explicitly deferred with reasoning |
| Game (GameControllers) | `2c70bb10` "fixed: game audit" | doc's own fix-pass status confirms 38 of 60 findings fixed outright, 15 explicitly deferred, 4 partially fixed |
| Round 8 (full codebase) | `7af39c14` "fixed: code audit 8" | separate commit shortly after the round-8 doc |

This round's job is therefore **not** to re-derive that history. It does three things: (1) re-verifies a sample of the above remediations directly against current source rather than trusting the commit messages alone (see the "Verified" column and §12), (2) gives the code changed since the last audit fix (`2c70bb10`..`HEAD`: `GameRPG/Table3D/*`, `SpaceRPG/Space/SpaceViewer.swift`, `PhotoRPG/Space/ImagePresentationView.swift`→`ImageSpaceView.swift`, `MapRPG` pin-action views, `Sources/MasterRPG/Window/*` — five commits, 22 files) extra scrutiny as genuinely unaudited territory, and (3) runs a fresh, independent full-codebase sweep (four parallel passes: concurrency/API modernity, dead code/duplication, bugs/security/performance, and a dedicated SwiftUI-expert pass) to catch anything eight prior full rounds missed. Findings that duplicate an already-fixed item are dropped; findings that duplicate a **deliberately deferred** item (Game.md's §9.2-§9.5/§9.10/§9.11, explicitly budgeted out of the 2026-08-22 fix pass) are kept and cited as confirmation the deferral is still an open decision, not re-presented as new discoveries.

**Compiler ground truth:** genuine full clean `xcodebuild build` (fresh `DerivedData`, not incremental) of all three shipping app schemes:
- `MasterRPG` (iOS/visionOS, iPhone 17 Pro Simulator, iOS 26.5) — **BUILD SUCCEEDED**, zero real warnings.
- `MasterMac` (macOS 26) — **BUILD SUCCEEDED**, zero real warnings.
- `MasterTV` (tvOS 27 Simulator) — **BUILD SUCCEEDED**, zero real warnings.

The only lines matching `warning:` anywhere in any of the three logs are benign `appintentsmetadataprocessor: Metadata extraction skipped, no AppIntents.framework dependency found` notices from targets that don't use App Intents — identical to every prior round. A full-tree grep for every hard CLAUDE.md rule (`DispatchQueue.main.async`/`.asyncAfter`, `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject`/`@EnvironmentObject`, `Task.sleep(nanoseconds:)` in production code, `DateFormatter`/`NumberFormatter`/`MeasurementFormatter`, `String(format:)`, `.replacingOccurrences`) also returned zero genuine hits outside the one accepted `GroupStateObserver` exception already on record. **Zero `TODO`/`FIXME`/`HACK`/`XXX`/`#warning` markers and zero `#if false` blocks exist anywhere in `Modules`/`Sources`/`Tests`** — confirmed by this round's own sweep, consistent with every prior round's finding.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made. Every Critical/High claim below was personally re-opened and confirmed by reading the cited lines before inclusion — see §12.

---

## 1. Executive summary

**No Critical findings this round** — nothing found reaches the crash/data-loss/memory-corruption bar. Top items, in priority order:

1. **[High] `ObservableImageCache` is an unbounded, unevicted dictionary sitting in front of the properly-bounded `NSCache`-based `ImageCacheController`** — §7.1 — `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:202-239`. First documented 2026-08-08 in `Docu/SWIFTUI_PERFORMANCE_AUDIT.md` (P0); independently reconfirmed unfixed 15 days later by this round's fresh agent.
2. **[High] Full-resolution photo decode (`AKImage(data:)`/`AKImage(contentsOfFile:)`) runs synchronously on `@MainActor`** — §7.2 — `Modules/PhotoRPG/Controller/CacheController.swift:22-42`. Same `SWIFTUI_PERFORMANCE_AUDIT.md` P0, same 15-day persistence.
3. **[High] `InlineImporterView`'s `Equatable` conformance ignores `preopen`/`layoutDown`, freezing the file-importer's layout after a file is attached** — §5.1 — `Modules/PhotoRPG/Photo/InlineImporterView.swift:97-125,251-253` and the `SpaceRPG` twin.
4. **[High] Views are decomposed via computed properties instead of separate `View` structs at ~150 call sites across 35+ files** — §8.1 — representative: `Modules/CoreRPG/LGViews/ListRootView.swift:171`, `Modules/CoreRPG/Editors/TextDoubleEditor.swift:102,126`. A named, explicit CLAUDE.md rule, violated at scale.
5. **[High] Reading any item via `itemSync(for:)`/`itemOrEmpty(for:)` subscribes the caller to the module's entire `itemData` dictionary, not just the one id read** — §8.2 — `Modules/CoreRPG/ItemList/ItemDataModel.swift:28`, `Modules/CoreRPG/Controllable/ItemControllable.swift:473-480`. Editing any one item in a module re-invalidates every other open row/editor for that module.
6. **[High] `GameTableModel.handleMapChange` has no supersession guard between its own independent call sites** — §3.2 — `Modules/GameRPG/Table3D/GameTableModel.swift:344-437`, `GameTableView.swift:298-306,354`. The model's own `fogOfWarTask` demonstrates the correct cancel-then-replace pattern two functions away; this one doesn't use it.
7. **[High] Six `Task.detached` export/recovery call sites have no cancellation propagation**, unlike every other `Task.detached` use in the codebase — §3.1 — `Modules/GameRPG/Controller/MasterController.swift:729-751,1752-1754`.
8. **[High] Ten of twelve per-module `GameController`s still hand-duplicate `GenericGameController`'s core** — §9.1 — flagged in round 8's cross-cutting recommendations and `CODE_AUDIT_Game.md §9.1`; confirmed today only `RuleRPG`/`GeneratorRPG` (2 of 12) have migrated, `DiceRPG` (614 lines), `CharacterRPG` (512), `SpaceRPG` (415), `MapRPG` (430) have not.
9. **[High] `MasterController.handlePhoto`/`handlePdf`/`handleSpace`, `PhotoRPG`/`PdfRPG`'s `GameController.swift`, and `PlayerController.sharePhoto`/`sharePdf`/`shareSpace` remain triplicated** — §9.2 — this is `CODE_AUDIT_Game.md §9.2-§9.5`'s file-backed-module consolidation, **explicitly deferred** by the team's own 2026-08-22 fix pass as "real work, disproportionate risk for the remaining budget" — confirmed still present, not a regression.
10. **[Medium→High trend] Two independent, 2+-week-old performance findings (this item and #1/#2 above) plus this round's fresh dead-code/duplication sweep together account for the large majority of remaining maintenance debt** — see §10 for the consolidated recommendation.

---

## 2. Quick wins (≤30 min each)

- **Delete the pre-clip dead `.shadow(radius: 10)` call** — `Modules/CoreRPG/Buttons/QuickEditorButtonView.swift:56` (`QuickAddButtonStyle.makeBody`) — it renders before `.clipShape(Circle())` at line 57 and is entirely clipped away; confirmed by direct read. See §8.4.
- **Fix `RawDie.Sides.number()`'s `sides == 1` case** — `Modules/DiceRPG/Model/RawDie.swift:97-100` — currently clamps `sides < 2` up to `2`, silently turning a "d1" die into a coin flip instead of a fixed roll of 1. See §5.3.
- **Add `withAnimation`/`@Environment(\.accessibilityReduceMotion)` gating is not the issue here** — skip; see instead: **name the `FoundryMediaNormalizer.swift:231` and `ItemProviderImporter.swift:148` raw JPEG-quality literals** (`0.9`, `0.85`) using the existing `JPEGQuality` enum every other call site already references. See §9.14.
- **Delete the four dead composite Foundation Models types** — `Modules/GeneratorRPG/BasicAI/Model/BlockGenModel.swift:9-49` (`BlockGenModel`, `BlockCategoryGenModel`) — reachable only from `#Playground` blocks, zero production callers. See §9.7.
- **Delete the orphaned Adventure-generation view/model chain** — `Modules/GeneratorRPG/Model/AdventureGenModel.swift` + `CampaignGenView.swift`/`AdventureGenView.swift`/`ScenarioGenView.swift`/`EntryGenView.swift` — superseded by `BlockEntryGenModel`, zero navigation references. See §9.8.
- **Delete the four superseded per-module `QuickEditorButton` views** — `TableRPG`/`CharacterRPG`/`MapRPG`/`AdventureRPG`'s own `QuickEditorButton.swift` files — `SheetEntryQuickEditButton.swift` now drives this generically in production; the four are unreferenced. See §9.6.
- **Wrap the 14 confirmed un-gated `print()` calls in `#if DEBUG`** — 5 in `#Preview` blocks (`ControlSharingView.swift:184`, `HeaderContentScrollView.swift:115`, `RemoveItemViewModifier.swift:40,45`, `PdfSummaryAnalysisView.swift:184`), 9 in `MyAiPlayground.swift`'s `#Playground` blocks (the latter print AI-generated narrative content). See §9.13.

---

## 3. Concurrency

### 3.1 Six `Task.detached` export/recovery call sites have no cancellation propagation — **Fixed 2026-08-24**
- **Fix:** All six sites now route through a new `MasterController.detachedGameData(priority:_:)` helper that wraps the detached task in `withTaskCancellationHandler { … } onCancel: { task.cancel() }`, matching the pattern used elsewhere in the codebase. Verified with a full clean `xcodebuild build` of `MasterRPG` (iOS Simulator) and `MasterMac` — both **BUILD SUCCEEDED**.
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:729-751` (`createGameData(for:)`, 5 call sites — map/photo/pdf/space/weather), `:1752-1754` (`stableMapRecoveryBundle(for:)`)
- **What:** Each `Task.detached` is `await`ed immediately via `.value` with no stored handle and no `withTaskCancellationHandler`. The file's own doc comment directly above (lines 715-724) explains *why* `Task.detached` is used here at all — to get an explicit off-main starting point under the project's approachable-concurrency setting, per `CODE_AUDIT_Game.md §3.5` — but that comment addresses a different concern (the export previously ran synchronously on the main actor) and doesn't mention cancellation. Every *other* `Task.detached` use in the codebase (`FoundrySystemPackageReader.swift:17-36`, `FoundryVTTImportReader.swift:20-40`, `UniversalVTTReader.swift:163-180`, `ImportControllable.swift:81-93`, `FileUrlDataController.swift:612-625`) pairs the detached task with `withTaskCancellationHandler { … } onCancel: { task.cancel() }`.
- **Why:** If the enclosing async call (a map reveal, repair, or recovery) is cancelled, the detached task runs to completion regardless — cancelling an in-flight reveal/repair doesn't actually stop the expensive encode.
- **Action:** Wrap these six call sites in `withTaskCancellationHandler`, matching the pattern already used everywhere else in the codebase, including the very same file's own neighboring comment referencing the dispatcher this belongs to.
- **Severity:** High

### 3.2 `GameTableModel.handleMapChange` has no supersession guard between its own independent call sites — **Fixed 2026-08-24**
- **Fix:** `handleMapChange` no longer does the work directly; it now delegates through a new `replaceMapChangeTask(isGameMaster:)`, which cancels any in-flight `performMapChange` before starting a new one and stores it in a new `mapChangeTask` property (mirroring `fogOfWarTask`/`replaceFogOfWarTask`'s existing pattern). `performMapChange` re-checks `Task.isCancelled` after the `mapModel(for:)` await and again before the final `syncPawnsWithMapPins()`, so a superseded call can no longer commit stale state after a newer one has started. `mapChangeTask` is also cancelled in `deinit`. Verified with a full clean `xcodebuild build` of `MasterRPG` (iOS Simulator) — **BUILD SUCCEEDED**.
- **Location:** `Modules/GameRPG/Table3D/GameTableModel.swift:344-437` (`handleMapChange(isGameMaster:)`/`loadMapPhoto(mapModel:isGameMaster:)`); call sites at `GameTableView.swift:298-306` (a plain `.task { await initializeGameIfNeeded() }`, which itself calls `handleMapChange` at line 354) and `:301-306` (a *separate* `.task(id: currentItemId) { await game.handleMapChange(...) }`)
- **What:** `currentMapId = currentItemId` is set at line 379 *before* `await loadMapPhoto(...)` at line 382; `loadMapPhoto` only checks `guard !Task.isCancelled` (line 408) after its own `await photoRoot.fetchPhotoImage(...)`, never re-validating that the map it started loading is still current. Confirmed directly: line 298's `.task` and line 301's `.task(id:)` are two *independent* Task hierarchies on the same `GameTableModel` instance — SwiftUI's automatic cancel-on-id-change protects re-entrant calls only *within* the `.task(id:)` hierarchy, not against a concurrent call arriving via the plain `.task` on initial view appear.
- **Why:** The same file's `updateFogOfWar`/`replaceFogOfWarTask` (lines 439-458) deliberately cancel-and-replace to avoid exactly this class of race, with an explicit comment about superseded results not being allowed to apply late. `handleMapChange` has no equivalent guard, so on initial load (or any future third caller sharing this instance) a slower, stale photo fetch can overwrite a newer one's state on the shared 3D table.
- **Action:** Give `handleMapChange`/`loadMapPhoto` the same generation-token discipline already used for `fogOfWarTask` in this file, re-validating `currentItemId` after the `await` before committing state.
- **Severity:** High

### 3.3 `ObjectCache<Object: AnyObject>`'s generic bound doesn't require `Sendable` — **Fixed 2026-08-24**
- **Fix:** Declaration changed to `actor ObjectCache<Object: AnyObject & Sendable>`. The sole instantiation (`ObjectCache<AKImage>()`) still compiles unchanged, confirming the audit's own read that the SDK's `UIImage`/`NSImage` Sendable annotations already cover it. Verified with a full clean `xcodebuild build` of both `MasterRPG` (iOS Simulator, `AKImage == UIImage`) and `MasterMac` (`AKImage == NSImage`) — both **BUILD SUCCEEDED**.
- **Location:** `Modules/CoreRPG/Cache/ObjectCache.swift:12` (declaration); `Modules/CoreRPG/Cache/ImageCacheController.swift:15` (`ObjectCache<AKImage>()`, the sole instantiation); `Modules/CoreRPG/Extensions/Image+AKImage.swift:16` (a commented-out `//extension NSImage: @unchecked @retroactive Sendable {}`, left in place)
- **What:** `insertObject(_:for:cost:)`/`cachedObject(for:)` pass `Object` values across this actor's isolation boundary with no `Sendable` requirement on the type parameter — unlike the codebase's other generic actor, `FileDataModel<Datatype: Codable & Storeable & Sendable>` (`FileDataController.swift:10`), which does constrain it. Verified this compiles clean under `SWIFT_STRICT_CONCURRENCY = complete` on all three platforms (this round's own build ground truth, above) with `AKImage` bound to both `UIImage` (iOS/tvOS) and `NSImage` (macOS) — the commented-out retroactive-Sendable line for `NSImage` suggests the current SDK's own Sendable treatment of these types already satisfies the compiler without it.
- **Why:** The current sole usage is safe today because the SDK's own annotations cover `UIImage`/`NSImage` crossing this boundary — this is a defensive-typing gap, not a live data race: nothing here fails to build, and no reachable path was found where a genuinely unsafe non-`Sendable` class is passed through this actor.
- **Action:** Constrain the declaration to `actor ObjectCache<Object: AnyObject & Sendable>` so the compiler enforces safety for any future instantiation, rather than relying on today's specific type argument happening to be SDK-safe.
- **Severity:** Medium

### 3.4 `DispatchQueue` still present via `Network.framework`'s callback-queue parameter — **Fixed 2026-08-24**
- **Fix:** `ListenerServerController` now has its own dedicated `DispatchQueue(label: "de.andretrettin.MasterRPG.ListenerServerController")` (matching `ConnectionController`'s naming/shape) and `listener.start(queue: queue)` replaces `listener.start(queue: .main)`. Both wrappers now route Network.framework callbacks through a dedicated background queue before hopping into the actor via `Task { await self... }`. Verified with a full clean `xcodebuild build` of `MasterRPG` (iOS Simulator) — **BUILD SUCCEEDED**.
- **Location:** `Modules/GameRPG/Network/ConnectionController.swift:31` (`DispatchQueue(label:)`, a dedicated background queue); `Modules/GameRPG/Network/ListenerManager.swift:152` (`listener.start(queue: .main)`)
- **What:** `NWConnection`/`NWListener` require a `DispatchQueue` for their state/data callbacks — Network.framework has no async-native, queue-less API — so this is functionally necessary, not a project-convention violation. It's easy to miss in a text grep for "zero `DispatchQueue`" since `ListenerManager.swift:152` uses `.main` via implicit member lookup rather than the spelled-out type name.
- **Why:** `ConnectionController` routes its callbacks through a dedicated background queue; `ListenerServerController.run()` instead routes every listener state/new-connection callback through `DispatchQueue.main` — an inconsistency between the two Network.framework wrappers in the same module, not a correctness bug.
- **Action:** Either document both as the sanctioned Network.framework exception to the "no DispatchQueue" rule, or move `ListenerServerController`'s queue off `.main` to match `ConnectionController`'s approach.
- **Severity:** Low

### 3.5 `Task.sleep(nanoseconds:)` survives in one test — **Fixed 2026-08-24**
- **Fix:** Replaced with `try? await Task.sleep(for: .milliseconds(100))`. (The test still waits on a fixed delay rather than a deterministic completion signal — that part of the finding was noted as a separate, lower-priority follow-up and left as-is here.) Confirmed no build errors trace to this file in a full `build-for-testing` pass of `MasterRPG`.
- **Location:** `Tests/SpaceRPGTests/EditControllerTests.swift:840`
- **What:** `try? await Task.sleep(nanoseconds: 100_000_000)` — the sole occurrence anywhere in the repo (production or test) of the banned API.
- **Why:** Isolated miss, not systemic; also signals the test waits on a fixed delay rather than a deterministic completion signal from the duplicate operation it's testing.
- **Action:** Replace with `Task.sleep(for: .milliseconds(100))`, or better, await a concrete completion signal.
- **Severity:** Low

---

## 4. API modernity

### 4.1 `NSItemProvider` completion-handler APIs wrapped in continuations — **Partially re-investigated and fixed 2026-08-24; the "native async" premise for the other two sites does not hold**
- **Re-investigation:** Checked directly against current Apple documentation (`NSItemProvider`'s full "Loading the provider's contents" method list) before touching anything: there is **no** native `async throws` overload of `loadItem`/`loadDataRepresentation`/`loadObject` anywhere in the current SDK — every loading method on `NSItemProvider` is still completion-handler/`Progress`-returning only, at any deployment target including this app's 26.0 floor. So `ItemController.swift:48-64` and `ItemProviderImporter.swift:180-210` wrapping the completion handler in `withCheckedThrowingContinuation` is not legacy debt to modernize away — it *is* the modern, idiomatic bridge, and both sites already do it correctly. No change made to either; the "Action" below as originally written (replace with "the direct async NSItemProvider APIs") isn't executable because that API doesn't exist.
- **Fix:** The one genuine, independent bug in this finding — `FileDropDelegate.swift:33-39` dropping the completion handler's `error` parameter entirely — is fixed: the `else if let error` branch now logs the failure via `Logger.fileStore.error(...)` instead of silently doing nothing. Verified with a full clean `xcodebuild build` of `MasterRPG` (iOS Simulator), `MasterMac`, and `MasterTV` — all **BUILD SUCCEEDED**.
- **Location:** `Modules/PhotoRPG/Controller/ItemController.swift:48-64` (`withCheckedThrowingContinuation` around `loadDataRepresentation(forTypeIdentifier:completionHandler:)`), `Sources/RPGShare/ItemProviderImporter.swift:180-210` (both already documented in `CODE_AUDIT_8.md §4.1`, confirmed unchanged — correctly so) plus **`Modules/CoreRPG/Files/FileDropDelegate.swift:30-42`** (`loadObject(ofClass:completionHandler:)` wrapped in a raw `Task { @MainActor in }`, not found by round 8's narrower scope)
- **What:** `FileDropDelegate.swift:34` (pre-fix) dropped the callback's `error` parameter entirely, silently swallowing load failures (round 8 didn't catch this because it wasn't in that pass's file set).
- **Why:** Legacy debt claim doesn't hold for the two continuation-wrapped sites (see re-investigation above); `FileDropDelegate`'s dropped error was a real, independent correctness gap, now fixed.
- **Severity:** Low (modernity claim retracted for 2 of 3 sites) / the `FileDropDelegate` error-swallowing — now fixed.

### 4.2 Combine `Timer.publish` used for recurring effects instead of `TimelineView`/an async sleep loop — **Fixed 2026-08-24**
- **Fix:** `LightningView` no longer holds a `Timer.publish(...).autoconnect()` property or does manual `timer.upstream.connect().cancel()`/reassignment bookkeeping — a new private `PeriodicStrikeTrigger` view wraps `TimelineView(.periodic(from:by:))` and calls `strike()` on each tick, mounted conditionally via `.background { if frequency >= 1 { ... } }` (matching the old "frequency < 1 means off" behavior with no timer at all). `AppExitNotificationsViewModifier`'s `Timer.publish(every: 60, ...)` is replaced by a cancellable `runPeriodicHousekeeping()` `Task`-based sleep loop, run as one of the view's `.task` modifiers so SwiftUI cancels it automatically on disappear — same lifecycle the Combine subscription had. The `Combine` import is no longer needed in either file. Verified with a full clean `xcodebuild build` of `MasterRPG` (iOS Simulator), `MasterMac`, and `MasterTV` — all **BUILD SUCCEEDED**.
- **Location:** `Modules/WeatherRPG/Weather/LightningView.swift:12,46,73,75`; `Modules/CoreRPG/App/AppExitNotificationsViewModifier.swift:15,30,47`
- **What:** Both drive a repeating effect with `Timer.publish(every:on:in:).autoconnect()` + `.onReceive`, including manual cancel-and-republish bookkeeping (`LightningView.swift:73-75`) to change the interval. These are the only two `Timer.publish` usages in the app.
- **Why:** At this deployment target, `TimelineView(.periodic(from:by:))` (rendering cadence) or a cancellable `Task`-based sleep loop (periodic housekeeping) replaces both without the Combine dependency or manual reconnect bookkeeping.
- **Action:** Replace `LightningView`'s with `TimelineView`; replace `AppExitNotificationsViewModifier`'s with a `Task`-based sleep loop.
- **Severity:** Medium

### 4.3 Legacy `FileManager` directory lookup instead of `URL.documentsDirectory` — **Fixed 2026-08-24**
- **Fix:** `rootScansFolder()` now returns `URL.documentsDirectory.appending(path: "Scans/", directoryHint: .isDirectory)` directly — the function keeps its `-> URL?` signature (implicitly wrapping the non-optional result) since its sole call site already unwraps via `guard let`. Verified with a full clean `xcodebuild build` of `MasterRPG` (iOS Simulator) and `MasterMac` — both **BUILD SUCCEEDED**.
- **Location:** `Modules/SpaceRPG/Record/CaptureFolderManager.swift:205-213` (`rootScansFolder()`)
- **What:** The sole remaining use of `FileManager.default.url(for: .documentDirectory, in:appropriateFor:create:)`; every other directory lookup in the codebase (`AppGroup.swift:50`, `FilePersistenceController.swift:107,118,122`, `LocationFileManager.swift:17`, several `Intent` files) already uses `URL.documentsDirectory`.
- **Action:** Replace with `URL.documentsDirectory.appending(path: "Scans/", directoryHint: .isDirectory)`.
- **Severity:** Low

### 4.4 Closure-based `NotificationCenter` observation where the async `notifications(named:)` sequence exists — **Fixed 2026-08-24**
- **Fix:** All four converted to `.task { for await _ in NotificationCenter.default.notifications(named:) { … } }` (or the `Task`-iterating-an-async-sequence equivalent for the one non-View case):
  - `KeyboardObserverViewModifier` — two `.task`s (show/hide), replacing the merged `Publishers.Merge` + `.onReceive`; the `Combine` import is gone.
  - `KeyboardAvoiding` — two `.task`s (show/hide) reading `notification.keyboardHeight` directly, replacing `Publishers.keyboardHeight` + `.onReceive`; the `Combine` import and the `Publishers.keyboardHeight` extension are gone (the `Notification.keyboardHeight` extension is kept — still used by the show handler).
  - `AppExitNotificationsViewModifier` — folded into the §4.2 fix above: its two notification subscriptions are now `.task`s over `notifications(named:)` alongside the periodic-housekeeping `.task`.
  - `RpgSpotlightIndexerDelegate.observeIndexing()` — the one non-View, non-`.task`-eligible case: the `addObserver(forName:object:queue:using:)` token (`observables: AnyObject?`) is replaced by a `private var indexingTask: Task<Void, Never>?` that iterates `NotificationCenter.default.notifications(named:)` in a loop; cancelling the task is the direct equivalent of the old `removeObserver(_:)` call, preserving the original enable/disable toggle semantics.
  - The two justified exceptions (`AudioPlayerSession.swift`, `CoreDataChangeObserver.swift`) were left unchanged, per the original finding's own reasoning.
  - Verified with a full clean `xcodebuild build` of `MasterRPG` (iOS Simulator), `MasterMac`, and `MasterTV` — all **BUILD SUCCEEDED**.
- **Location:** `Modules/CoreRPG/App/KeyboardObserver.swift:30-39`, `Modules/CoreRPG/ViewModifiers/KeyboardAvoiding.swift:14-20`, `Modules/CoreRPG/Persistence/RpgSpotlightIndexerDelegate.swift:46-59`, `Modules/CoreRPG/App/AppExitNotificationsViewModifier.swift:20-51`

### 4.5 Dead `@available` guard below the deployment floor in vendored Navigator — confirmed unchanged since round 8 §4.2, **no action taken (by design)**
- **Location:** `Modules/CoreRPG/Navigator/Extensions/NavigationLink+Navigator.swift:40,102`
- **What:** `@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)` on vendored third-party (`NavigatorUI`) code, unreachable-false at this app's 26.0 floor.
- **Action:** No action unless the vendored package is forked. Informational only, as in round 8. Re-confirmed 2026-08-24 during the §4.1-4.5 fix pass — left untouched intentionally, per the finding's own recommendation; this is not vendored-package code we own.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 `InlineImporterView`'s `Equatable` conformance ignores `preopen`/`layoutDown`, freezing the importer's layout after a file is attached
- **Location:** `Modules/PhotoRPG/Photo/InlineImporterView.swift:97-125,251-253` (`static func ==` compares only `itemId`), `Modules/SpaceRPG/View/InlineImporterView.swift:73-90,185-187` (same shape); `PhotoRPG/Controller/ViewController.swift:15-17` and `SpaceRPG/Controller/ViewController.swift:15-17` (both wrap the view in `.equatable()`); real call site `Modules/CoreRPG/ItemDetail/ItemFileImporterView.swift:61-67` passes `preopen: isInitial, layoutDown: !isInitial` for a stable `model.id`, where `isInitial` flips the moment the item's file is set.
- **What:** `.equatable()` uses this narrow `==` to decide whether to skip re-rendering; since `itemId` is unchanged, SwiftUI treats the before/after values as identical, so the button-fan's `layoutDown` orientation and the `isExpanded` state seeded from `preopen` never update after the initial render.
- **Why:** The importer visually stays in its "no file yet" arrangement even after a file is attached, for the life of that view identity.
- **Action:** Include `preopen`/`layoutDown` in the `Equatable` conformance (or drop `.equatable()` here), matching every other `Equatable` view in the codebase, which compares every stored property that can vary.
- **Severity:** High

### 5.2 visionOS tabletop drag-destination cursor never renders — recently-touched code
- **Location:** `Modules/GameRPG/Table3D/GameRenderer.swift:91-134` (`cursorTransform` `willSet` at 91-110, `updateCursor(_:valid:)` at 127-134); `Modules/GameRPG/Table3D/GameInteraction.swift:10-33` (`updateCursor`, `update(interaction:)`)
- **What:** Confirmed directly: `updateCursor(_:valid:)` at `GameRenderer.swift:127-134` ignores both its `proposedDestination` and `valid` parameters and unconditionally sets `cursorTransform = nil`. `GameInteraction`'s `updateCursor`/`update(interaction:)` (the `TabletopInteraction.Delegate` requirement) do the same.
- **Why:** `ModelEntity.cursor` builds an elaborate translucent cylinder specifically to preview where a dragged die/equipment would land, with full snap/animate/turn-off logic in `cursorTransform`'s `willSet` (lines 92-109) — all dead except "turn off," because no code path ever computes and assigns a real transform. This file is in the set changed since the last audit fix (`GameRenderer.swift` appears in the `2c70bb10..HEAD` diff), so this is either a recent regression or a feature that was never finished being wired up.
- **Action:** Compute a `Transform` for `proposedDestination` in `GameInteraction.update(interaction:)` and pass it through instead of hardcoding `nil`.
- **Severity:** Medium

### 5.3 `RawDie.Sides.number()` silently turns a valid "d1" die into a coin flip
- **Location:** `Modules/DiceRPG/Model/RawDie.swift:83-103` (`Sides.number()`, specifically 97-100), `:48-56` (`init(text:)`)
- **What:** `case .number(sides)` clamps any `sides < 2` up to `2`. `RawDie(text:)` parses arbitrary "d\<N\>" notation from a character formula or Foundry import via `Sides.sides(number)`, so "d1" resolves to `.number(1)` and rolls `Int.random(in: 1...2)` instead of a deterministic `1`. Confirmed unchanged by direct read.
- **Why:** A die a game system or import specifies as always-1 (a common "guaranteed minimum" mechanic) has a 50% chance of rolling 2, silently corrupting any dependent calculation. `TableGenerationController.swift:183-190` already special-cases a single-entry table specifically to route around this exact clamp — confirming the team is aware it misbehaves for `sides == 1` but hasn't fixed it at the source.
- **Action:** Special-case `sides == 1` to return a fixed `1` instead of doubling the range.
- **Severity:** Medium

### 5.4 `PdfWrapperView`'s search wraps `PDFDocument.findString` in `Task { @MainActor in }`, which doesn't move the blocking call off the main thread
- **Location:** `Modules/PdfRPG/Pdf/PdfWrapperView.swift:98-140` (`updateView`), `:146-152` (`Coordinator`)
- **What:** `Task { @MainActor in ... }`'s closure body stays `@MainActor`, so the actual `pdfView.document?.findString(searchText, withOptions: .caseInsensitive)` call still blocks the main thread for the duration of the search — `Task { @MainActor in }` only defers scheduling, it doesn't move work off-thread. The non-blocking alternative is already half-wired: `pdfView.document?.delegate = context.coordinator` (line 100) sets a `Coordinator` that conforms to `PDFDocumentDelegate` (line 146) but implements none of its methods.
- **Why:** For large, multi-page PDFs (rulebooks — exactly what this module manages), this freezes the UI for the duration of the search.
- **Action:** Switch to `beginFindString(_:withOptions:)` and collect matches via `PDFDocumentDelegate.didMatchString(_:)`.
- **Severity:** Medium

### 5.5 `RotatePhotoView`'s `imageWidth` `@State` is frozen when the `size` parameter changes — latent, no reachable call site today
- **Location:** `Modules/CoreRPG/Views/RotatePhotoView.swift:8-19,40,62-76`
- **What:** When `size != nil`, `_imageWidth = State(wrappedValue: size.width)` seeds state once in `init`; the rendered `.frame(width:)` reads `size?.width` live, but `height(for:)`/`scale(for:)` both key off the frozen `@State` value, updated only in the `size == nil` branch via `onGeometryChange`.
- **Why:** If a future caller passes a `size` that changes for the same view identity, height/overlay scale wouldn't track it. No current production call site passes `size` (only `#Preview` does) — latent, not currently reachable.
- **Action:** Drive `imageWidth` from `onGeometryChange` unconditionally, or read `size?.width` directly in the two computed helpers instead of caching it.
- **Severity:** Low

### 5.6 Ambiguous, type-punned `CRDT<String>.wrappedValue` setter
- **Location:** `Modules/CoreRPG/CRDT/CRDT.swift:25-34`
- **What:** The `wrappedValue` setter special-cases `T == String`: if the new value happens to be valid JSON decodable as the register's own `LWWRegister<String, T>` schema, it replaces the *entire* register (actor ID, timestamp, everything) instead of the normal LWW value update every other `T` gets.
- **Why:** A plain text edit that happens to parse as the register's own JSON schema would silently discard the register's provenance metadata instead of recording a normal, tracked update — narrow but baked into the property wrapper's core mutation path with no explicit "this is a deserialize, not a user edit" flag.
- **Action:** Use a separate, explicitly-named restore method (mirroring the existing `init(string:defaultValue:)`); make the plain setter always go through the normal LWW path.
- **Severity:** Low

### 5.7 Stray dead code referencing an out-of-scope variable
- **Location:** `Modules/WeatherRPG/Weather/StarsView.swift:70`
- **What:** `//        .frame(width: size.width, height: size.height)` — commented out, references a `size` not in scope at that point; would not compile if uncommented.
- **Action:** Delete.
- **Severity:** Low

---

## 6. Security

### 6.1 Character/Map link-repair and edit-diagnostic logging uses `.public` privacy, inconsistent with the project's own established `.private` policy for the same category of data
- **Location:** `Modules/CharacterRPG/Controller/EditController.swift:751,753,780,796,808,825,883`; `Modules/CharacterRPG/Controller/LinkController.swift:90,97,107,114,130,147`; `Modules/MapRPG/Controller/LinkController.swift:83,95`
- **What:** These `Logger.editController`/`Logger.linkController` calls interpolate actual Character/NPC/Map/entry names (`item.name`, `entry.name`, `oldOwner.name`, `targetName`, `parentName`) at `privacy: .public`.
- **Why:** `Modules/MapRPG/Controller/GameController+Metadata.swift:283` explicitly logs the equivalent data (`combatant.pin.name`) at `.private`, with an in-code comment citing "Matches synchronizeBattleDefenders' .private policy ... See CODE_AUDIT_Game §6.3" — a policy that has now been applied to the Battle/Master paths (per `CODE_AUDIT_Game.md §6.3` and `CODE_AUDIT_BattleRound.md §6.3`, both confirmed fixed) but not carried over to these two `LinkController`/`EditController` files. A device sysdiagnose or Console capture can surface a GM's character/NPC/map names — potentially spoiler-sensitive creative content — in plaintext.
- **Action:** Change these interpolations to `.private`, matching the policy already established and fixed elsewhere for the same category of data.
- **Severity:** Medium

---

## 7. Performance

### 7.1 Unbounded, unevicted in-memory image cache defeats the bounded `NSCache` tier — open 15 days, independently reconfirmed
- **Location:** `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:202-239` (`ObservableImageCache`), `:104-110` (`remove(itemId:includeImage:)`, the only eviction path); `Modules/CoreRPG/LGViews/CachePhotoView.swift:74-90` (`loadImage()` unconditionally populates it)
- **What:** `ObservableImageCache` is a plain `[UUID: AKImage]` dictionary with no count/cost limit and no memory-pressure eviction, bridging the actor-isolated, properly `NSCache`-bounded `ImageCacheController` (`ObjectCache`, capped at 2,500 objects / 256 MB — see §3.3) into synchronous SwiftUI reads. The only removal path is item deletion/file replacement — never scroll-off or memory pressure.
- **Why:** `CachePhotoView`/`GroupedPhotoView` is the shared full-resolution image view used across every module's item lists and detail screens. In a long campaign session, every full-resolution image ever displayed accumulates permanently in this dictionary for the app session's lifetime, independent of and in addition to the properly-bounded `NSCache` — a real path to memory pressure/jetsam on iOS/visionOS. First documented `Docu/SWIFTUI_PERFORMANCE_AUDIT.md` (2026-08-08) as risk P0; unlike nearly everything else in that document (which this round's agents cross-checked), this one is still present 15 days later.
- **Action:** Cap `ObservableImageCache` (an LRU with a bound, or back it by the same `NSCache`), or evict proactively on `scenePhase` background / memory-pressure signals.
- **Severity:** High

### 7.2 Full-resolution photo decode runs synchronously on `@MainActor` — same 15-day persistence
- **Location:** `Modules/PhotoRPG/Controller/CacheController.swift:22-42` (`createImage(for:item:)`)
- **What:** `@MainActor`, calls `AKImage(data:)`/`AKImage(contentsOfFile:)` directly — full image decompression — on the main actor. Only the thumbnail path uses ImageIO downsampling; the full-image path doesn't.
- **Why:** Rendering a full-resolution photo (map backgrounds, character portraits) triggers a main-thread decode; for large source images this causes visible hitches. Same `SWIFTUI_PERFORMANCE_AUDIT.md` P0, unresolved since 2026-08-08.
- **Action:** Move the decode off the main actor (matching the pattern already used in `AudioPlayerSession.setActive()`), then hop back to set the cache.
- **Severity:** Medium

### 7.3 System-package Foundry imports still parse the same archive up to 3 times — confirmed unchanged since round 8 §7.1
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:90-152`; `Modules/CoreRPG/Foundry/FoundryArtifactDetector.swift:35,74`; `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:20,44`; `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:17-36`
- **What:** `detect()` fully parses the ZIP central directory once independently, `FoundryVTTDecoder.decode()` parses it again via the shared cache, and `FoundrySystemPackageReader.read()` parses it a third time through a completely separate, uncached data source.
- **Why:** Multiplies disk I/O and ZIP central-directory parsing up to 3x on every "import a Foundry system package" flow, scaling with archive size (up to 1 GiB).
- **Action:** Have `FoundryArtifactDetector`/`FoundrySystemPackageReader` accept an already-opened data source or share `FoundryZIPDataSourceCache`.
- **Severity:** Medium

---

## 8. SwiftUI / UI

### 8.1 Views decomposed via computed properties instead of separate `View` structs — a named CLAUDE.md rule, violated at scale
- **Location:** ~150 occurrences across 35+ files, spanning every module. Representative sample: `Modules/CoreRPG/LGViews/ListRootContextMenu.swift:87,100,121,136,163,176,193,214,230,247,262,287`; `Modules/CoreRPG/LGViews/ListRowItemView.swift:85-143`; `Modules/CoreRPG/LGViews/ItemRowView.swift:72-112`; `Modules/CoreRPG/LGViews/ListRootView.swift:171`; `Modules/CoreRPG/Editors/TextDoubleEditor.swift:102,126` (confirmed by direct read — `textInputView`/`sliderView` are `private extension` computed properties, not `View` structs); `Modules/CoreRPG/Editors/TextIntEditor.swift:58,79`; `Modules/WeatherRPG/View/WeatherStormEditor.swift:68,74,92,112`; `Modules/GeneratorRPG/View/PdfSummaryAnalysisView.swift:40,58,83`; `Modules/PdfRPG/View/ContentExtractionView.swift:71,86,99`; `Modules/PhotoRPG/Root/ViewerRootView.swift:64,133,156`; `Modules/RolePlayGameKit/View/TabSidebar.swift:46`; `Sources/RPGShare/SharingView.swift:97,165,181`.
- **What:** Bodies are broken up with `private var x: some View`/`@ViewBuilder var x: some View` computed properties instead of dedicated `View` structs.
- **Why:** CLAUDE.md explicitly bans this ("Do not break views up using computed properties; place them into new View structs instead") because computed properties share the parent's invalidation boundary — a state change re-evaluates every section, not just the affected one. This is measurably worse than a style nit for the numeric-editor family specifically (`TextDoubleEditor`/`TextIntEditor`/`WeatherStormEditor`/`WeatherThunderEditor`/`WeatherConditionEditor`): dragging one slider or typing in one field re-runs every sibling section's body on the same struct, and these are shared CoreRPG components reused on essentially every numeric-value editing screen in the app.
- **Action:** Extract each named section into its own `View` struct with narrow inputs — the codebase already does this correctly elsewhere (e.g. `ItemHeaderEditorView`'s extracted `ItemHeaderEditorNameSection`) as the model to follow.
- **Severity:** High

### 8.2 Reading an item via `itemSync(for:)`/`itemOrEmpty(for:)` subscribes the caller to the module's entire `itemData` dictionary
- **Location:** `Modules/CoreRPG/ItemList/ItemDataModel.swift:8-9,28` (`@MainActor @Observable public final class ItemDataModel`, `public var itemData: [UUID: ModelType] = [:]` — confirmed by direct read: a plain `@Observable`-tracked dictionary, not a per-key-observable structure); `Modules/CoreRPG/Controllable/ItemControllable.swift:473-480` (`itemSync(for:)`/`itemOrEmpty(for:)`, both subscript directly into it); call sites include `Modules/CharacterRPG/View/EntryListDiceRow.swift:16,44`, `InlineRowViewer.swift:23`, `ThumbnailPhotoRow.swift:20` (Character and Adventure), `AddtionalEntryRow.swift:43` (Character and Map), `Modules/CoreRPG/LGViews/EntryEditRow.swift:59`, `Modules/PhotoRPG/View/CarouselPhotoItemView.swift:48`
- **What:** Swift's Observation framework tracks a dictionary-typed `@Observable` property at whole-property granularity, not per-key — reading any single key inside a view's `body` registers that view as an observer of the *entire* dictionary. Several of the row views above resolve their model this way inside `body` rather than being handed an already-resolved reference.
- **Why:** Editing any one item in a module re-invalidates every other open row/editor in that module that ever resolved its model via `itemSync`/`itemOrEmpty` — even for a completely unrelated item id. Marking these rows `Equatable` (several already are) does not prevent this, since Observation-triggered invalidation bypasses the parent-diffing path `.equatable()` optimizes.
- **Action:** Have these call sites receive an already-resolved model reference from their parent (as `ItemRowView`/`ListRowItemView` already do), instead of re-resolving via the shared dictionary inside each row's own body.
- **Severity:** High

### 8.3 Hidden `Picker` label with no compensating accessibility label
- **Location:** `Modules/GeneratorRPG/View/PdfSummaryAnalysisView.swift:40-56`, `TableSummaryAnalysisView.swift:40-56`, `BatchTextSummaryExtractionView.swift:100-115`
- **What:** `languagePicker` places a `Text("Output Language")` beside a `Picker` in a bare `HStack`, then calls `.labelsHidden()` on the `Picker` with no `.accessibilityLabel` tying the two together.
- **Why:** VoiceOver treats the `Text` and `Picker` as separate elements; a VoiceOver user landing on the picker hears only the selected language, not what it controls.
- **Action:** Wrap in `LabeledContent` (as done correctly elsewhere, e.g. `ValuePickerEditor`) or add `.accessibilityLabel(Text("Output Language"))` directly.
- **Severity:** Medium

### 8.4 `.shadow()` applied before `.clipShape(Circle())` renders dead
- **Location:** `Modules/CoreRPG/Buttons/QuickEditorButtonView.swift:50-61` (`QuickAddButtonStyle.makeBody`, specifically lines 56-57 — confirmed by direct read: `.shadow(radius: 10)` precedes `.clipShape(Circle())`, then a second `.shadow(color:radius:x:y:)` follows the clip); `Modules/CoreRPG/Buttons/OverlayButtonStyle.swift:8-22` (same shape)
- **What:** The pre-clip shadow becomes part of the content the following `.clipShape` clips away — confirmed dead by comparing against `ImageOverlayButton.swift:80-81`, where the same team applies shadow after `.clipShape` correctly.
- **Action:** Remove the pre-clip `.shadow(radius: 10)` call. Quick win — see §2.
- **Severity:** Medium

### 8.5 Liquid Glass adoption opportunity for manually-emulated circular button styles
- **Location:** `Modules/CoreRPG/Buttons/QuickEditorButtonView.swift:50-61`, `OverlayButtonStyle.swift:8-22`, `ImageOverlayButton.swift:75-82`
- **What:** These hand-emulate glass via `.background(.ultraThinMaterial)` + `.clipShape(Circle())` rather than native `.glassEffect(.regular, in: .circle)`, already used elsewhere in the codebase (`ItemHeaderEditorView`, `TableGenerationPanelView`).
- **Why:** Migrating modernizes these to iOS 26 Liquid Glass and incidentally eliminates §8.4's shadow-ordering bug, since `.glassEffect` composits shape/shadow internally.
- **Action:** Replace with `.glassEffect(.regular, in: .circle)`, gated consistently with the rest of the app.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Ten of twelve per-module `GameController`s still hand-duplicate `GenericGameController`'s core
- **Location:** `Modules/CoreRPG/Controllable/GenericGameController.swift` (85 lines, the shared default); confirmed by direct line count: `Modules/DiceRPG/Controller/GameController.swift` (614 lines), `Modules/CharacterRPG/Controller/GameController.swift` (512), `Modules/SpaceRPG/Controller/GameController.swift` (415), `Modules/MapRPG/Controller/GameController.swift` (430) vs. `Modules/RuleRPG/Controller/GameController.swift` and `Modules/GeneratorRPG/Controller/GameController.swift` (8 lines each — confirmed by direct read: both are a one-line `typealias GameController = GenericGameController<ItemController, ExportController>` with an in-code comment citing "CODE_AUDIT §9.3")
- **What:** Flagged across round 8's cross-cutting recommendations ("persisted across 8 audit rounds") and `CODE_AUDIT_Game.md`'s executive-summary item 9 / §9.1; confirmed today that only Rule/Generator have migrated.
- **Why:** A bug fix or protocol change to the shared game-sync contract must be manually verified against up to ten independently-evolved copies — exactly the kind of drift this codebase's own history shows causes GM/player sync bugs.
- **Action:** Audit whether Dice/Character/Space/Map's `GameController`s can be re-expressed as thin overrides of `GenericGameController`, keeping only genuinely module-specific logic (e.g. Dice's roll-result handling) as overrides.
- **Severity:** High

### 9.2 File-backed-module sync logic remains triplicated across Photo/Pdf/Space — deliberately deferred by `CODE_AUDIT_Game.md`'s 2026-08-22 fix pass, confirmed still present
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:1837-1980` (`handlePdf`), `:1981-2124` (`handlePhoto`), `:2258-2453` (`handleSpace`) — three near-identical ~140-line handlers; `Modules/PhotoRPG/Controller/GameController.swift` (216 lines) vs. `Modules/PdfRPG/Controller/GameController.swift` (221 lines) — directly diffed, line-for-line identical modulo module name; `Modules/GameRPG/Controller/PlayerController.swift:216-271` (`sharePhoto`), `:275-329` (`sharePdf`), `:333-388` (`shareSpace`) — same structure, three times
- **What:** This is exactly `CODE_AUDIT_Game.md`'s §9.2-§9.5 finding set. That audit's own fix-pass status explicitly lists these as **deferred** ("real work, disproportionate risk for the remaining budget after §9.1 and §9.9 landed") rather than skipped by oversight. Independently reconfirmed present in current source by this round's fresh agents, with exact line numbers re-verified.
- **Why:** ~200+ lines of version-ledger/availability logic and three ~140-line message handlers duplicated with no mechanism keeping the copies in sync — exactly the kind of file-availability logic implicated in this app's documented history of GM/player sync bugs.
- **Action:** As already recommended in `CODE_AUDIT_Game.md`: extract a generic `PlayerVersionLedger`/`FileAvailabilityGameControllable` protocol parameterized by `NetworkModules`, and one `handleFileBackedModule(_:controllable:availability:featureEnabled:)` helper for the three Master-side handlers. This remains the single highest-leverage refactor in `GameRPG`, per that audit's own assessment — re-affirmed here, not newly discovered.
- **Severity:** High

### 9.3 AppIntent `Entity`/`EntityQuery` boilerplate still duplicated 12x — confirmed unchanged since round 8 §9.1
- **Location:** `Modules/{Pdf,Photo,Space,Audio,Character,Rule,Dice,Generator,Map,Table,Weather,Adventure}RPG/Intent/*Entity.swift`, ~170-220 lines each
- **What:** Diffing any two still shows only type-name/string swaps; no shared generic base exists in CoreRPG.
- **Action:** Pull `EntityQuery`/`IndexedEntity` conformance into a shared generic CoreRPG base.
- **Severity:** Medium

### 9.4 PNG-encoding AppIntent helper triplicated across Pdf/Photo/Space
- **Location:** `Modules/PdfRPG/Intent/PdfEntity+Image.swift:11-46`, `Modules/PhotoRPG/Intent/PhotoEntity+Image.swift:12-47`, `Modules/SpaceRPG/Intent/SpaceEntity+Image.swift:12-48`
- **What:** `loadAssetData(isThumbnail:)` (with its `ImageCreationError` struct and UIKit/AppKit PNG-encoding fallback chain) is byte-for-byte identical in all three files. CoreRPG already unifies the equivalent JPEG path (`Image+AKImage.swift` + `JPEGQuality`), but no analogous PNG helper exists.
- **Action:** Add a cross-platform `AKImage.pngRepresentationData()` to `Image+AKImage.swift`; have all three call sites use it.
- **Severity:** Medium

### 9.5 `StableVersionDigest` re-duplicated in MapRPG and RuleRPG, and already diverging
- **Location:** `Modules/MapRPG/Model/MapUpdatePayload.swift:140-151` (`StableMapVersion`), `Modules/RuleRPG/Model/RuleModel.swift:808-820` (`StableRuleVersion`) vs. canonical `Modules/CoreRPG/Model/StableVersionDigest.swift:17-29`
- **What:** Both private enums reimplement `StableVersionDigest.digest`'s exact algorithm and have already drifted on their encode-failure fallback (`-1` vs. `1`, matching neither the canonical implementation nor each other).
- **Why:** `StableVersionDigest`'s own doc comment says it was extracted specifically to eliminate near-identical implementations elsewhere — these two were never migrated. Cross-device version comparisons are a documented past bug source in this codebase.
- **Action:** Delete both; call `StableVersionDigest.digest(_:)` directly.
- **Severity:** Medium

### 9.6 Per-module `QuickEditorButton` views superseded by a generic component, left uncalled
- **Location:** `Modules/TableRPG/View/QuickEditorButton.swift`, `Modules/CharacterRPG/View/QuickEditorButton.swift`, `Modules/MapRPG/View/QuickEditorButton.swift`, `Modules/AdventureRPG/View/AdventureQuickEditorButton.swift`
- **What:** Each duplicates `navigator.navigate(to: <Module>EditorRoute.quickEditor(model.id))`, but has zero call sites outside its own file/preview/snapshot test — `Modules/CoreRPG/Sheet/SheetEntryQuickEditButton.swift` (wired into production via `SheetContextMenuView.swift:15`) now drives this generically for every module.
- **Action:** Delete all four and their preview-snapshot test entries. Quick win — see §2.
- **Severity:** Medium

### 9.7 Dead composite Foundation Models types reachable only from a scratch Playground
- **Location:** `Modules/GeneratorRPG/BasicAI/Model/BlockGenModel.swift:9-49` (`BlockGenModel`, `BlockCategoryGenModel`), consumed only by `Modules/GeneratorRPG/Playground/MyAiPlayground.swift:83,92`
- **What:** Zero references outside each other and non-shipping `#Playground` blocks; production adventure-extraction code uses `BlockEntryGenModel` exclusively.
- **Action:** Delete both types and update the Playground calls, or move the Playground to a non-shipping scratch target. Quick win — see §2.
- **Severity:** Low

### 9.8 Orphaned "Adventure/Campaign/Scenario/Entry" generation model and view chain
- **Location:** `Modules/GeneratorRPG/Model/AdventureGenModel.swift:1-61`, `Modules/GeneratorRPG/Root/CampaignGenView.swift`, `AdventureGenView.swift`, `ScenarioGenView.swift`, `EntryGenView.swift` (~290 lines total)
- **What:** A self-referential chain with none of the four views or backing models referenced from any Root/Route/navigation file; production generation exclusively uses `BlockEntryGenModel`.
- **Action:** Delete `AdventureGenModel.swift` and the four `*GenView.swift` files plus their snapshot-test entries. Quick win — see §2.
- **Severity:** Medium

### 9.9 Orphaned `AdventureChatRootView` sub-components from a superseded chat UI
- **Location:** `Modules/GeneratorRPG/Root/AdventureChatHeaderView.swift`, `AdventureChatMetricPill.swift`, `AdventureCurrentAnswerCard.swift`, `AdventureGeneratedBlockRow.swift`, `AdventureBlockListSectionHeader.swift`, `AdventureNoBlocksView.swift` (~275 lines total)
- **What:** Built as sub-components of a `struct AdventureChatRootView` that no longer exists in that file; the current AI-assistant UI (`SheetAIAssistantOverlayView.swift`/`SheetAIAssistantStandardControl.swift`) references none of them.
- **Action:** Delete all six files and their generated preview-snapshot test entries.
- **Severity:** Medium

### 9.10 Widespread `ID`/`URL` casing violates the project's mandated `Id`/`Url` convention, concentrated in two subsystems
- **Location:** `Modules/GameRPG/Model/LogGameModel.swift:12,18,65` (including the public type `GameDeliveryMessageID`), `Modules/GameRPG/Network/GameRelayAdmission.swift:12,57,78`, `Modules/RuleRPG/Controller/RuleEntryTree.swift:26-205`, `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:956,1077`, `Modules/RolePlayGameKit/Router/RootURLHandler.swift:8` (public type, used at MasterRPGApp.swift:92,118); also independently documented at `Modules/GameRPG/Model/GameNetworkModel.swift:109,112,120,126`/`Modules/GameRPG/Network/GameNetworkController.swift` in `CODE_AUDIT_BattleRound.md §4.1` (deliberately **not** fixed there — "touches ~80+ occurrences ... the risk/reward didn't justify a blind mechanical rename")
- **What:** The Foundry-import subsystem and GameRPG's networking/session layer consistently use `ID`/`URL` casing instead of the mandated `Id`/`Url`, while MapRPG/DiceRPG/AdventureRPG/CharacterRPG/WeatherRPG correctly follow it.
- **Action:** A scoped, compiler-assisted rename sweep for these two subsystems specifically, public declarations first — the `BattleRound` audit's own reasoning for deferring the network-protocol half still applies (wire-format `CodingKeys` need explicit pinning); the Foundry-import half carries no such wire-format risk and is a better first target.
- **Severity:** Medium

### 9.11 `GameStatisticsController`/`GameStatisticsTypes` use `sessionID` instead of `sessionId`
- **Location:** `Modules/GameRPG/Statistics/Model/GameStatisticsTypes.swift:268,314,327,440,450,499,507,538,568,578,594,605`, `Modules/GameRPG/Statistics/Controller/GameStatisticsController.swift:12,25,95,96`
- **What:** A self-contained instance of the same casing violation, isolated to the Statistics feature.
- **Action:** Rename `sessionID` → `sessionId` throughout.
- **Severity:** Low

### 9.12 Module folder-structure divergence: `Route` vs `Routes` vs `Router`, `Intent` vs `AppIntent`
- **Location:** `Modules/CoreRPG/Routes/` and `Modules/RolePlayGameKit/Router/` vs. `Route/` used by all 11 other feature modules; `Modules/RolePlayGameKit/AppIntent/` vs. `Intent/` used by all 12 others
- **What:** Same concept named differently across the two shared/merge modules vs. every feature module.
- **Action:** Rename to match, or document the two shared modules as an explicit exception in CLAUDE.md.
- **Severity:** Low

### 9.13 Un-gated `print()` calls, confirmed 14 outside `#if DEBUG`
- **Location:** `Modules/CoreRPG/Buttons/ControlSharingView.swift:184`, `HeaderContentScrollView.swift:115`, `RemoveItemViewModifier.swift:40,45`, `Modules/GeneratorRPG/View/PdfSummaryAnalysisView.swift:184` (5, all inside `#Preview` blocks); `Modules/GeneratorRPG/Playground/MyAiPlayground.swift:22,26,28,86,94,97,102,104,106` (9, all inside `#Playground` blocks)
- **What:** Confirmed 14 of 26 raw repo-wide matches lack a `#if DEBUG` guard — every module's own `PreviewData.swift` already gates its prints correctly, showing the convention exists but wasn't applied here.
- **Why:** The Playground prints output AI-generated adventure/narrative text and raw error descriptions; no print anywhere contains file paths, credentials, or device identifiers.
- **Action:** Wrap both groups in `#if DEBUG`, or delete the Preview-block ones outright. Quick win — see §2.
- **Severity:** Medium (Playground group) / Low (Preview-block group)

### 9.14 JPEG-quality literals bypass the existing shared `JPEGQuality` enum at two lower-level encode paths
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryMediaNormalizer.swift:231` (raw `0.9`), `Sources/RPGShare/ItemProviderImporter.swift:148` (raw `0.85`, matching no existing tier)
- **What:** `JPEGQuality` (`.transport = 0.5`, `.cachedThumbnail = 0.8`, `.export = 0.9`) is referenced by every other `jpegData(compressionQuality:)` call site except these two `CGImageDestination`-based paths.
- **Action:** Reference `JPEGQuality.export` at the first site; add or reuse a named case for the second. Quick win — see §2.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **The per-module boilerplate genericization has now persisted across 9 full audit rounds for `GameController` (§9.1) and 8+ rounds for `ImportController`/`ExportController`/`ItemController`/`FolderListController`/App-Intents-`Entity` (§9.3, all previously fixed for the latter group per round 8, still open for `GameController` specifically).** This remains the single highest-leverage mechanical refactor available in the codebase.
2. **The two oldest-standing findings in this report (§7.1, §7.2) are both from a dedicated performance audit dated 2026-08-08 — 15 days and multiple intervening audit rounds ago — and neither has moved.** Both are well-understood, well-documented, and low-architectural-risk to fix (bound a dictionary; move a decode off `@MainActor`). Given how quickly this team has remediated every *other* audit finding in this repo's history (see the table at the top of this report), their persistence suggests they simply haven't been prioritized yet, not that they're hard — worth scheduling explicitly.
3. **Apply the cancel-then-replace-with-generation-token pattern uniformly.** `fogOfWarTask` (`GameTableModel.swift`) demonstrates this works well and is already house style for state that might race across an `await`. §3.1 (`Task.detached` cancellation) and §3.2 (`handleMapChange` supersession) are both sibling gaps in the exact same file/subsystem that never got the treatment.
4. **The "view split via computed property" and "whole-dictionary Observable read" findings (§8.1, §8.2) are architecturally related and worth fixing together where they overlap**: several of §8.2's offending row views (`EntryListDiceRow`, `ThumbnailPhotoRow`) are exactly the kind of hot, frequently-instantiated leaf view where §8.1's extraction discipline also applies — extracting them into dedicated `View` structs that receive an already-resolved model as a plain input parameter fixes both problems in the same edit.
5. **`Docu/CODE_AUDIT_Game.md`'s explicit deferrals (§9.2-§9.5, §9.10, §9.11) were a considered, budget-driven decision, not an oversight — this round confirms they're still exactly where that pass left them.** They remain queued, not forgotten; worth revisiting as a dedicated follow-up pass given how much cross-file drift risk they carry (per that audit's own framing).

---

## 11. What was NOT audited

- **Algorithmic correctness** of the Foundry VTT domain-mapping logic (`FoundryVTTDomainMapper.swift`), 3D/RealityKit rendering math, and CRDT merge semantics beyond the one type-punning issue in §5.6 — structural/duplication/dead-code aspects only were reviewed for these.
- **Build settings, scheme configuration, and Xcode project structure** beyond what's visible via the three shipping-app schemes built for this round's warning capture.
- **Third-party SPM dependency internals** (`swift-custom-dump`, `swift-syntax`, `swift-snapshot-testing`, `xctest-dynamic-overlay`) and the vendored `NavigatorUI` package beyond the one `@available` citation in §4.5.
- **Deep test-coverage assessment.** `Tests/` was scanned for markers and dead-code cross-references (used to confirm several §9 findings) but not reviewed for coverage gaps or test quality.
- **Localization wording quality** — `Docu/LOCALIZATION_ACCESSIBILITY_AUDIT.md` (2026-07-16) exists as a dedicated prior pass on this topic and was not re-run; this round's SwiftUI pass only flagged structural bundle-scoping issues where directly encountered (none found this round).
- **Performance profiling via Instruments.** §7's findings, and the still-open §7.1/§7.2 from `SWIFTUI_PERFORMANCE_AUDIT.md`, are based on static source reading, not captured traces — that document's own "Trace proof" sections remain the right next step before landing a fix, not this report's static confirmation alone.
- **StoreKit 2 / IAP** (`InAppModel.swift`/`InAppView.swift`) — spot-checked by this round's bugs/security agent and found to use correct, modern APIs (`Product`/`Transaction`/`AppStore.sync()`) with no code-level issues; App Store Connect product-catalog alignment was not checked.
- **Full re-verification of all ~250 findings across the 15 prior `Docu/CODE_AUDIT_*.md` documents.** This round spot-checked a representative sample per subsystem (see the remediation table at the top and §12) rather than re-opening every historical line — the volume of already-fixed, already-verified material makes exhaustive re-derivation low value; this report's job is the delta.
- **Entitlements files** beyond what's already tracked in project memory (the Debug/Release entitlement-pair split) — not re-reviewed this round.
- **Other platforms' (MasterMac, MasterTV) target-specific conditional-compilation branches** beyond what surfaced incidentally in the files read for other findings.

---

## 12. Verification

- **§3.1** — open `Modules/GameRPG/Controller/MasterController.swift:715-755`. Read the doc comment at 715-724 (cites `CODE_AUDIT_Game §3.5`, addresses a different concern) then confirm all 5 `Task.detached` blocks in `createGameData(for:)` (729-751) have no `withTaskCancellationHandler`. Compare against `Modules/CoreRPG/Files/FileUrlDataController.swift:612-625` for the codebase's own correct pattern.
- **§3.2** — open `Modules/GameRPG/Table3D/GameTableModel.swift:344-437` and `Modules/GameRPG/Table3D/GameTableView.swift:298-306`. Confirm line 298's `.task` and line 301's `.task(id:)` are independent hierarchies both reaching `handleMapChange` on the same `game` instance; confirm `loadMapPhoto`'s only staleness check (line 408) is `Task.isCancelled`, with no re-validation of `currentItemId` after the `await` at line 407.
- **§3.3** — open `Modules/CoreRPG/Cache/ObjectCache.swift:12` (no `Sendable` bound) and `Modules/CoreRPG/Extensions/Image+AKImage.swift:16` (commented-out retroactive conformance). Cross-check this round's own build ground truth above (zero warnings on all 3 platforms) as evidence the SDK's current annotations already cover the sole instantiation.
- **§5.1** — open `Modules/PhotoRPG/Photo/InlineImporterView.swift:251-253`; confirm `static func ==` compares only `lhs.itemId == rhs.itemId`. Open `Modules/CoreRPG/ItemDetail/ItemFileImporterView.swift:61-67` and confirm `preopen`/`layoutDown` are passed as `isInitial`/`!isInitial`, which changes after the initial render.
- **§5.2** — open `Modules/GameRPG/Table3D/GameRenderer.swift:127-134`; confirm `updateCursor(_:valid:)`'s body ignores both parameters and sets `cursorTransform = nil` unconditionally.
- **§5.3** — open `Modules/DiceRPG/Model/RawDie.swift:97-100`; confirm `sides < 2` returns `2` for any input including `1`.
- **§7.1** — open `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:202-239`; confirm `ObservableImageCache` has no count/cost cap. Cross-reference `Docu/SWIFTUI_PERFORMANCE_AUDIT.md` lines 83-119 (dated 2026-08-08) describing the identical mechanism.
- **§8.1** — open `Modules/CoreRPG/Editors/TextDoubleEditor.swift:101-125`; confirm `textInputView` is declared inside `private extension TextDoubleEditor`, not as a `View` struct.
- **§8.2** — open `Modules/CoreRPG/ItemList/ItemDataModel.swift:8-9,28`; confirm `@MainActor @Observable public final class ItemDataModel` declares `itemData` as a plain `[UUID: ModelType]`, then open `Modules/CoreRPG/Controllable/ItemControllable.swift:473-480` and confirm `itemSync`/`itemOrEmpty` subscript directly into it.
- **§9.1** — `wc -l` the six cited `GameController.swift` files directly; confirm Rule/Generator are 8-line typealiases and Dice/Character/Space/Map are 400-600+ lines each.
- **§9.2** — open `Docu/CODE_AUDIT_Game.md` and search for "⏸️ 15 deferred" in its fix-pass status header; confirm §9.2-§9.5/§9.10/§9.11 are named there as deliberately deferred, then re-open `Modules/GameRPG/Controller/MasterController.swift:1837-1980,1981-2124,2258-2453` to confirm the three handlers are still present at those lines in current source.

If any finding doesn't reproduce when you visit the line, flag it with the specific reference and it'll be re-investigated in the next round.
