# MasterRPG Code Audit

Generated 2026-08-15. Scope: ~267,500 Swift LOC across ~1,993 files, covering all 15 dynamic-framework modules (`AdventureRPG`, `AudioRPG`, `CharacterRPG`, `CoreRPG`, `DiceRPG`, `GameRPG`, `GeneratorRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `RolePlayGameKit`, `RuleRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG`) and the `MasterRPG`/`MasterMac`/`MasterTV`/`RPGShare`/`DiceRollerWidgetExtension` targets. No `Dead/` or archived directory exists in this repo, so nothing was excluded by convention — only `.git/`, `.build/`, `DerivedData/`, and `xcuserdata/` were skipped.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

**Compiler ground truth:** a full clean `xcodebuild` of the `MasterRPG` scheme (iOS Simulator) succeeded with **zero real compiler warnings** (only two unrelated "AppIntents metadata extraction skipped" notices) under `SWIFT_STRICT_CONCURRENCY = complete` / Swift 6 language mode — identical to the previous pass. The findings below come from reading code and grepping for anti-patterns the compiler can't catch, not from a warnings list.

**Context on findings volume:** this repo carries five prior audit passes (`Docu/CODE_AUDIT_1.md` through `_5.md`, the latest dated 2026-08-14), and four commits have landed since that pass (`fixed: 3D objecte for visionOS`, `fixed: the table generator is fixed with level 10 - artefacts`, `fixed: refresh and save works`, `fixed: send items`), plus one file is currently uncommitted in the working tree (`Modules/SpaceRPG/Root/SpaceRootModel.swift`, `Modules/SpaceRPG/Space/SpaceViewer.swift`, and the new `Modules/SpaceRPG/Space/SpaceHandoffModel.swift` — a window→immersive-space entity handoff feature). Every "Known finding" from `CODE_AUDIT_5.md` was independently re-verified against current source this pass and is marked **FIXED**, **STILL PRESENT**, or **PARTIALLY FIXED** below rather than re-derived from scratch. The uncommitted `SpaceRPG` handoff code got specific extra scrutiny since it has never been through a prior audit cycle — it is also where this pass's highest-severity finding (§5.1) was found.

---

## 1. Executive summary

Top items to address, in priority order:

1. **[High] Window→immersive-space object handoff strands the object and gets stuck on a wrong "Moved" state** — §5.1 — `Modules/SpaceRPG/Space/SpaceViewer.swift:315-326`. Dragging/double-tapping a second Space item into an already-open immersive space silently discards it instead of replacing or queuing it.
2. **[High] `PdfEntity`/`PhotoEntity`/`SpaceEntity` Shortcuts/Spotlight export a fake placeholder card, never the real file** — §5.2 — `Modules/PdfRPG/Intent/PdfEntity.swift:60-81` (copy-pasted verbatim into `PhotoEntity.swift` and `SpaceEntity.swift`, the latter claiming `.pdf` content type for a 3D USDZ object). Shortcuts "Save File"/Share Sheet/drag-out silently hands the user a rendered Name/Description text card instead of their PDF, photo, or 3D model.
3. **[High] Uncancellable `DispatchQueue.main.asyncAfter` in the Navigator's deferred-resume path, unfixed across 4 audit cycles** — §3.1 — `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:107-114`.
4. **[Medium] `MasterMac` target's entitlements were missed by the prior `aps-environment` Debug/Release split** — §6.1 — `Resources/MasterRPG.entitlements` (used unsplit by both MasterMac configs), contrast with `MasterRPG-Debug/-Release.entitlements` and `MasterTV-Debug/-Release.entitlements`. MasterMac declares the `remote-notification` background mode but can't register for it.
5. **[Medium] Five `@MainActor` `DataController` structs block via `context.performAndWait` instead of `await context.perform`** — §3.2 — e.g. `Modules/PhotoRPG/Controller/PhotoDataController.swift:31`; these are reachable from the Share Extension's save flow.
6. **[Medium] Six call sites hand-roll the same 100ms cancel/sleep debounce instead of the existing `DebouncerModel`** — §9.4 — `Modules/CoreRPG/EntryEditor/TextEditModel.swift:89,109` and 4 more sites.
7. **[Medium] The same `FileManager.cloudURL ?? FileManager.groupURL ?? URL.documentsDirectory` fallback expression is duplicated across 4 CoreRPG files** — §9.3 — `Modules/CoreRPG/Foundry/FoundryImportArchive.swift:209-211` and 3 more, each with an identical comment.
8. **[Medium] Core Data persistence failures are now logged but still never surfaced to the user** — §5.4 — `Modules/CoreRPG/Controllable/ItemControllable.swift:384-406`; `lastPersistenceError` is written in one place and read nowhere.
9. **[Medium] `EntityGestureState`'s RealityKit drag/scale/rotate singleton isn't itself actor-isolated** — §3.4 — `Modules/SpaceRPG/Space/EntityGestureState.swift:7-49`; only its `static let shared` accessor is `@MainActor`.
10. **[Medium] An orphaned, byte-identical duplicate `.storekit` configuration file sits unreferenced by any scheme** — §9.1 — `Resources/RPGResources/Resources/MasterRPG.storekit` vs. the one actually wired in, `Modules/RolePlayGameKit/InApp/MasterRPG.storekit`.

**No Critical findings.** Every claim above was traced to an exact call path and independently corroborated (§5.1 and §5.2 were each verified by two independent reviewers this pass — see §12).

---

## 2. Quick wins (≤30 min each)

- **Fix three misspelled `MARK` navigation labels** — §9.8 — `Modules/CoreRPG/Controllable/EditControllable.swift:190,220,624` ("Carousell"→"Carousel", "Colllection"→"Collection", "mantainence"→"maintenance").
- **Delete or symlink the orphaned duplicate StoreKit config** — §9.1 — `Resources/RPGResources/Resources/MasterRPG.storekit`; nothing references it.
- **Change `itemControllable` from `var` to `let` on two `@unchecked Sendable` types** — §3.6 — `Modules/CoreRPG/Simple/SimpleLinkController.swift:13-17`, `Modules/CoreRPG/Fake/FakeLinkController.swift:5-10`.
- **Delete the unreferenced `ModelEntity.size()` extension** — §9.5 — `Modules/SpaceRPG/Space/SpaceViewer.swift:909-919`; zero call sites anywhere.
- **Delete (or wire up) the dead `animatableData` computed property** — §8.3 — `Modules/SpaceRPG/Space/SpaceViewer.swift:23-31`; `SpaceViewer` doesn't conform to `Animatable`, so SwiftUI never calls it.
- **Replace the chained `Bundle.path(forResource:ofType:)` + `URL(fileURLWithPath:)` with `Bundle.url(forResource:withExtension:)`** — §4.3 — `Modules/DiceRPG/Controller/GameController.swift:572-573`.
- **Add a one-line justification comment to the 4 undocumented `@unchecked Sendable` declarations** — §3.7 — `Modules/CoreRPG/Instrumentation/PerformanceTrace.swift:19-26` and 3 more.
- **Delete the two genuinely-unused CoreRPG debug/utility files** (or wire them in) — §9.6, §9.7 — `Modules/CoreRPG/ViewModifiers/DeviceRotateViewModifier.swift`, `Modules/CoreRPG/Debug/DumpEnvironment.swift`.

---

## 3. Concurrency

### 3.1 Uncancellable `DispatchQueue.main.asyncAfter` in Navigator's deferred resume
- **Location:** `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:107-114`
- **What:** The `.auto` case of `resume(_:values:delay:)` schedules `self.send(values: values)` via `DispatchQueue.main.asyncAfter(deadline:)` instead of a `Task`.
- **Why:** Violates the project's "never use GCD, always modern concurrency" rule and, unlike a `Task`, this closure can't be cancelled once scheduled — a torn-down/reset navigator can still receive a stale `send` later. This exact line has now been flagged across 4 consecutive audit passes with no fix landed.
- **Action:** Replace with a stored, cancellable `Task { try? await Task.sleep(for: .seconds(delay)); guard !Task.isCancelled else { return }; send(values: values) }` that a subsequent teardown/reset can cancel.
- **Severity:** High

### 3.2 `@MainActor` `DataController` structs block on `context.performAndWait` instead of async `perform`
- **Location:** `Modules/PhotoRPG/Controller/PhotoDataController.swift:31`, `Modules/CharacterRPG/Controller/CharacterDataController.swift:21`, `Modules/AdventureRPG/Controller/AdventureDataController.swift:24`, `Modules/MapRPG/Controller/MapDataController.swift:21`, `Modules/WeatherRPG/Controller/WeatherDataController.swift:21`
- **What:** Each `@MainActor public struct ...DataController`'s `async` "addNew…" method calls the synchronous, thread-blocking `context.performAndWait { … }` instead of the non-blocking `await context.perform { … }` used ~14 times elsewhere in `Modules/CoreRPG/Persistence/CoreDataController.swift`.
- **Why:** These methods are invoked from `Sources/RPGShare/ShareExtensionSaveController.swift` — the Share Extension's save flow — so a busy/private-queue Core Data context can freeze that extension's UI, defeating the point of the method being `async`.
- **Action:** Replace `context.performAndWait { … }` with `await context.perform { … }` at all five sites.
- **Severity:** Medium

### 3.3 Untracked, uncoalesced `Task` spawned on every viewport-pan delta
- **Location:** `Modules/GameRPG/Table3D/GameTableModel.swift:48-53,513-522`
- **What:** `panViewport(by:)` — the entry point for `GameTableView`'s continuous drag gesture — and `displayMode`'s `didSet` both spawn a fresh, untracked `Task { await updateFogOfWar(isGameMaster:) }` with no cancellation of any prior in-flight task, unlike this same file's `trackThumbnailTask(for:_:)` (line 725-728), which explicitly cancels the previous task first.
- **Why:** `panViewport` fires on every drag-delta during a continuous gesture, so a fast drag can queue many overlapping `updateFogOfWar` invocations on the Main Actor; these serialize and pile up, wasting work and risking a stale invocation overwriting a fresher render.
- **Action:** Store the spawned task in a `fogOfWarTask: Task<Void, Never>?` property and cancel the previous one before starting a new one, mirroring `trackThumbnailTask`.
- **Severity:** Medium

### 3.4 `EntityGestureState` singleton class is not itself actor-isolated
- **Location:** `Modules/SpaceRPG/Space/EntityGestureState.swift:7-49`
- **What:** `public class EntityGestureState` declares no `@MainActor` (and isn't `Sendable`); only its `static let shared` accessor is `@MainActor` (line 48), while its mutable stored properties (`targetedEntity`, `isDragging`, `pivotEntity`, `isScaling`, `isRotating`, etc.) carry no isolation of their own.
- **Why:** Every other singleton in the codebase (`ResourceCache`, `AccessibilityLabelCache`, `DataMutationCoordinator`, `AppModel`, `CloudKitOperationCounter`, `ExternalImportSourceRegistry`) is either an `actor` or a `@MainActor final class`. Here, once a reference is obtained via the `@MainActor` accessor, nothing in the type system stops a `nonisolated` function on the same call stack from reading/writing it without a compiler-checked actor hop.
- **Action:** Mark the class itself `@MainActor final class EntityGestureState`, matching the `@MainActor public struct GestureComponent` that is its only consumer, so isolation is enforced structurally rather than just at the accessor.
- **Severity:** Medium

### 3.5 `MainActor.assumeIsolated` escape hatch for `nonisolated` protocol conformances on 13 domain models
- **Location:** centralized helper `assumeMainActorIsolated` at `Modules/CoreRPG/Concurrency/MainActorIsolationAssumption.swift:19-21`, used across `AudioModel`, `MapModel`, `SpaceModel`, `TableModel`, `AdventureModel`, `WeatherModel`, `SimpleModel`, `GeneratorModel`, `PdfModel`, `DiceModel`, `RuleModel`, `ValueModel`, `PhotoModel` (~59 call sites)
- **What:** `Comparable`/`ItemDiffComparable`/`ItemDuplicatable` conformances on all 13 `@MainActor @Observable` domain models are `nonisolated` and route their bodies through this shared `MainActor.assumeIsolated` wrapper to read MainActor-isolated state.
- **Why:** `assumeIsolated` is a runtime trap, not a compile-time guarantee — a future `Task.detached`/background-actor caller that sorts or diffs these model arrays directly would crash instead of failing to compile. **Improvement since the last pass:** this was previously ~13 hand-rolled inline copies; it's now one shared, auditable helper. No off-Main-Actor caller was found this pass either.
- **Action:** None required today. Optional hardening: a shared regression test asserting the trap fires off-Main-Actor, documenting the contract.
- **Severity:** Low

### 3.6 `@unchecked Sendable` types with a mutable `var` exceeding their protocol's read-only requirement
- **Location:** `Modules/CoreRPG/Simple/SimpleLinkController.swift:13-17`, `Modules/CoreRPG/Fake/FakeLinkController.swift:5-10`
- **What:** Both conform to `LinkControllable: Sendable` and mark themselves `@unchecked Sendable`, but declare `itemControllable` as a mutable `var` even though the protocol only requires a read-only `var itemControllable: any ItemControllable { get }`.
- **Why:** A mutable, unsynchronized stored property on an `@unchecked Sendable` type is exactly the pattern the annotation is supposed to guard against. Current usage (constructed once, never reassigned) happens to be safe, but nothing enforces that invariant, unlike the codebase's other `@unchecked Sendable` types, which document a specific set-once precondition (e.g. `CoreDataChangeObserver`).
- **Action:** Change `itemControllable` to `let` in both types.
- **Severity:** Low

### 3.7 `@unchecked Sendable` declarations without an adjacent justification comment
- **Location:** `Modules/CoreRPG/Instrumentation/PerformanceTrace.swift:19-26`, `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:214`, `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:282`, `Modules/CoreRPG/Navigator/Core/Navigator.swift:31-33`
- **What:** `PerformanceTrace.Interval`, `RPGPersistentContainer`, `RPGPersistentCloudKitContainer`, and the vendored `Navigator` class all carry `@unchecked Sendable` with no comment explaining why the compiler's automatic check is bypassed — unlike most other `@unchecked Sendable` sites in this codebase (`AudioListenerCoordinator`, `CoreDataChangeObserver`, `FoundryJSONDepthCounter`), which each carry a specific soundness-precondition comment.
- **Why:** Each of these 4 is plausibly sound (opaque signpost token, bare Apple-framework subclasses, MainActor-isolated navigation state), but the missing rationale breaks the "one audited, documented escape hatch" discipline the rest of the codebase follows, making it harder for a future editor to know what invariant must be preserved.
- **Action:** Add a one- or two-line comment at each declaration stating the specific safety justification.
- **Severity:** Low

### 3.8 Untracked fire-and-forget `Task` for RealityKit collision-shape generation
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:586-594`
- **What:** `loadEntity(into:)` spawns `Task(name: "RealityKit Collision Shapes", priority: .utility) { @MainActor in … firstMesh.generateCollisionShapes(...) }` without retaining the task handle or checking cancellation inside it.
- **Why:** If the user rapidly switches the displayed item (re-triggering `loadEntity` for a new `id`) while the previous item's collision-shape generation is still running, the stale task keeps executing and holds a strong reference to a mesh that may no longer be on screen, doing wasted work with no way to cancel it.
- **Action:** Store the task in a `collisionShapeTask: Task<Void, Never>?` `@State`, cancel any prior one before starting a new one, and check `Task.isCancelled` before calling `generateCollisionShapes`.
- **Severity:** Low

### 3.9 Redundant `MainActor.run` hops inside an already-`@MainActor` controller
- **Location:** `Modules/GameRPG/Controller/PlayerController.swift:214-216` (`sharePhoto`), `:273-275` (`sharePdf`), `:332-334` (`shareSpace`)
- **What:** `PlayerController` is `@MainActor` (line 22), and `root`/`root.gameModel` are both MainActor-isolated too — yet all three functions wrap a simple tuple read of `root.gameModel.gameConfig.id`/`.master.id` in `await MainActor.run { ... }`, an actor hop that should already be unnecessary.
- **Why:** Each function runs per asset-reveal network message during live gameplay (a reasonably hot path); each introduces an avoidable suspension point for a synchronous property read. Low real-world impact, but a 3x-copy-pasted pattern worth cleaning up.
- **Action:** Replace the `await MainActor.run { ... }` wrapper with a direct synchronous tuple read at all three sites.
- **Severity:** Low

### 3.10 `GroupStateObserver`'s `@ObservedObject` is an unavoidable Apple-framework constraint
- **Location:** `Modules/GameRPG/SetupViews/SharePlayButton.swift:20-22`
- **What:** `@ObservedObject private var groupStateObserver = GroupStateObserver()` is confirmed to remain the only `@ObservedObject`/`ObservableObject` usage in the non-test codebase.
- **Why:** Apple's `GroupActivities.GroupStateObserver` is still Combine-based (`$isEligibleForGroupSession: Published<Bool>.Publisher`) with no `@Observable` variant offered. The house rule against `ObservableObject` cannot be satisfied here without an Apple-side change.
- **Action:** None available today.
- **Severity:** Low (informational — verified clean)

---

## 4. API modernity

### 4.1 Legacy `URL.appendingPathComponent(_:)` instead of `URL.appending(path:)`
- **Location:** `Modules/SpaceRPG/Record/CaptureFolderManager.swift:41,46,51,127,142,212`; `Modules/SpaceRPG/Record/Scanner3DRootView.swift:54`; `Modules/CoreRPG/Cache/ObjectCache.swift:81,86,91`; `Modules/CoreRPG/Files/LocationFileManager.swift:15-16`; `Modules/CoreRPG/Files/FileUrlDataController.swift:234`; `Modules/CoreRPG/Persistence/FilePersistenceController.swift:107,118,122`; `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:38-39,64`; `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:91-92,118` (22 call sites, 8 files)
- **What:** These sites build file/cache/store URLs with the older `.appendingPathComponent(_:isDirectory:)` instead of the modern `.appending(path:directoryHint:)`.
- **Why:** CLAUDE.md explicitly names `appending(path:)` as the required replacement; these are the codebase's main remaining holdout, concentrated in exactly the persistence/cache/file-management code most likely to be touched again.
- **Action:** Replace each call with `.appending(path:directoryHint:)` (or the no-hint overload).
- **Severity:** Medium

### 4.2 Legacy `URL(fileURLWithPath:)` initializer instead of `URL(filePath:)`
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:441-442,494,511,524,537,550,552,557,659,788` (12 occurrences); `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:157,1032`; `Modules/DiceRPG/Controller/GameController.swift:573`; `Modules/SpaceRPG/Record/TutorialVideoView.swift:67`; `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:127`; `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:79` (18 call sites)
- **What:** These construct a `URL` from a `String` path with `URL(fileURLWithPath:)` rather than the modern `URL(filePath:)`, most heavily inside `FoundryVTTImportReader.swift`.
- **Action:** Replace with `URL(filePath:)`; for the `FoundryVTTImportReader.swift` sites that only need `.lastPathComponent`/`.deletingPathExtension()` from a path string, consider whether string manipulation would be clearer than constructing a `URL` at all.
- **Severity:** Low

### 4.3 Legacy `Bundle.path(forResource:ofType:)` instead of `Bundle.url(forResource:withExtension:)`
- **Location:** `Modules/DiceRPG/Controller/GameController.swift:572-573`
- **What:** Dice-roll sound-effect lookup uses `Resources.bundle.path(forResource:ofType:)` (returns an optional `String`) then wraps the result in `URL(fileURLWithPath:)`, instead of `Bundle.url(forResource:withExtension:)` directly.
- **Action:** Replace with `Resources.bundle.url(forResource: diceName(...), withExtension: "m4a")`.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Window→immersive-space handoff strands the object when the immersive space is already showing something else
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:315-326` (`moveToImmersiveSpace`), `Modules/SpaceRPG/Space/SpaceHandoffModel.swift:33,41-51` (single-slot `pending`, not a queue), `Modules/CoreRPG/ScenesManager/ScenesManager.swift:451-464` (`openSpaceViewer`)
- **What:** `moveToImmersiveSpace()` unconditionally detaches the entity, sets `handedOffToImmersive = true` (swapping the window to a permanent "Moved to Immersive Space" placeholder with no retry/undo), then calls `scenesManager.openSpaceViewer(selection:)` — but `openSpaceViewer` silently no-ops (`if state == .opening || state == .opened { pendingSpaceViewerSelection = nil; return }`) whenever the immersive space is already open showing a *different* item, and `SpaceHandoffModel.pending` is a single slot that a second handoff simply clobbers.
- **Why:** A user who has item X open in the immersive space, browses to a different Space item Y's detail page (the window preview stays interactive while the space is open — a normal action), and drags/double-taps Y into the space loses Y entirely: its window is stuck on the "Moved" placeholder, its entity is silently discarded, and the immersive space never shows Y. There's no error, no retry path — just a wrong, sticky UI state.
- **Action:** Before committing to the handoff in `moveToImmersiveSpace()`, check whether the immersive space is already open with a different item and either replace its content, queue the request, or revert `handedOffToImmersive` and re-adopt the entity locally when the open call won't result in this item being shown.
- **Severity:** High

### 5.2 `PdfEntity`/`PhotoEntity`/`SpaceEntity` Transferable exports a fake placeholder, never the real file
- **Location:** `Modules/PdfRPG/Intent/PdfEntity.swift:58-93`, `Modules/PhotoRPG/Intent/PhotoEntity.swift:58-93`, `Modules/SpaceRPG/Intent/SpaceEntity.swift:58-93` — byte-for-byte identical `transferRepresentation` bodies; `Modules/PdfRPG/Intent/PdfEntity+Image.swift:24-38` (`loadAssetData` returns `cacheController.photo`/`thumbnail`, never the raw asset)
- **What:** The primary `FileRepresentation(exportedContentType: .pdf)` synthesizes a one-page PDF containing only the item's Name/Description text via `ImageRenderer`+`CGContext`, instead of exporting the real stored file — and this is true even for `SpaceEntity`, a 3D USDZ object, which still claims `exportedContentType: .pdf`. The `DataRepresentation(exportedContentType: .image)` fallback returns a PNG of the cached thumbnail/preview, not the underlying document/photo/model bytes. No representation in any of the three files calls `root.itemController.loadableUrl(itemId:)` (the real-file loader `SpaceViewer.loadEntity` itself uses).
- **Why:** A Shortcuts user who drags one of these entities into "Save File", Share Sheet, or any file-consuming action silently gets a rendered text card instead of their actual PDF/photo/3D model — wrong data, not an error, easy to miss until someone opens the exported file. This defeats the purpose of exposing these types as `IndexedEntity`/`Transferable` to Shortcuts/Spotlight/Siri. The identical body copy-pasted 3 times (with `SpaceEntity` never adapting the content type away from `.pdf`) strongly suggests one file was written and blindly duplicated.
- **Action:** Add a `FileRepresentation`/`DataRepresentation` backed by `loadableUrl(itemId:)`/the real asset data, matching each entity's actual content type (real PDF bytes, real photo, real `.usdz`), as the primary or an additional representation.
- **Severity:** High

### 5.3 `GeneratorController`'s `maxCharacters` prompt cap is dead code; free-text user input stays unbounded
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:469-481` (`prompt(for:...maxCharacters: Int = 2_800)`), `:226` (call site never passes it), `:411-431` (`compactSheetIndex` truncates via its own unrelated `maxCharacters: Int = 600` default)
- **What:** `prompt(for:...)` declares a `maxCharacters` parameter that's never referenced in the function body — the GM's free-text `message` is interpolated with no length limit at all; only the `sheetIndex` portion is capped, and by a different, independent default.
- **Why:** A dead parameter creates a false impression that user input is bounded when it isn't. Practically low-risk since the GM is a trusted local device owner and `ConversationEngine` has its own sliding-window management, but still misleading.
- **Action:** Either apply `message.prefix(maxCharacters)` before interpolating the user text, or delete the unused parameter so the code doesn't imply a safeguard that isn't there.
- **Severity:** Medium

### 5.4 Core Data persistence errors are now logged but never surfaced to the UI
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:384-406` (`save`/`flushPendingOperations`, both set `itemDataModel.lastPersistenceError`), `Modules/CoreRPG/ItemList/ItemDataModel.swift:25` (`lastPersistenceError` declared `internal(set)`)
- **What:** **STATUS: FIXED (partially).** The prior audit's "bare `try?`, zero logging" finding is resolved — `save()`, `batchDelete`, and `flushPendingOperations` now log via `Logger.itemController.error` and record failures into `itemDataModel.lastPersistenceError`. A repo-wide grep shows that property is written in exactly one file and read nowhere else.
- **Why:** A failed save is now diagnosable from device logs, but the user still gets no indication their edit never reached disk — the property is currently write-only.
- **Action:** Surface `lastPersistenceError` (e.g. a toast/banner bound to it in a shared root view).
- **Severity:** Medium

### 5.5 `AdventureRootModel`'s `linkRegisterController` still crashes if accessed before setup
- **Location:** `Modules/AdventureRPG/Root/AdventureRootModel.swift:185-191`, `Modules/CoreRPG/Controllable/ItemControllable.swift:72-84`
- **What:** **STATUS: PARTIALLY FIXED.** The prior finding about a `nil`-initialized, force-unwrapped optional unique to this one module (vs. the other 10 modules taking it as a non-optional init parameter) is resolved in form — `AdventureRootModel` now reads a shared `ItemControllable.linkRegisterController` default that fails with a named `preconditionFailure(...)` instead of a bare `!`. The underlying crash-if-read-too-early behavior is unchanged, just centralized and given a diagnostic message.
- **Why:** A Preview, test, or reset-without-reassign path that reads this before `setUp(root:context:batchContext:)` runs will still crash — deliberately, per the comment — just with a clearer message.
- **Action:** Consider making `AdventureRootModel` take `linkRegisterController` as a non-optional init parameter like the other 10 modules do, removing the crash path entirely.
- **Severity:** Medium

### 5.6 Previously-flagged force-unwraps in `EntityGestureState` — FULLY FIXED
- **Location:** `Modules/SpaceRPG/Space/EntityGestureState.swift:109,132,165,197-209`
- **What:** The prior finding about `pivotEntity.parent!`/`state.targetedEntity!` force-unwraps and `fatalError` guards is resolved — every site now uses `guard let ... else { return }` to drop the drag frame instead of crashing, and `onEnded` unconditionally clears gesture state via `defer`.
- **Action:** None needed; confirming for completeness since this module has had 3+ commits since the finding, including the uncommitted `SpaceViewer` changes.
- **Severity:** Low (informational)

### 5.7 Previously-flagged `.last!` force-unwraps in link-toggle parsing — FULLY FIXED
- **Location:** `Modules/CoreRPG/LinkRenderer/AttributedString+Link.swift:16`, `Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift:66`
- **What:** Both sites now use `url.split(separator: "]").last ?? Substring(url)` with a safe fallback instead of `.last!`.
- **Severity:** Low (informational)

### 5.8 Table generator recursion-cap fix (commit `b3889dc6`) verified correct
- **Location:** `Modules/TableRPG/Controller/TableGenerationController.swift:18-24,273-282`
- **What:** The commit changed cycle detection from "cut off a link the first time it repeats in `tablePath`" to "allow it to recur up to `maxTableRecursionCount = 10` times", correctly fixing the reported "level 10 artefacts" bug where an intentional self-referencing table ("roll again on this table") was cut off after one repeat. The `count(where:)` scan is O(depth), bounded by the depth-10 cap — no performance concern.
- **Action:** None; confirming the fix per this pass's explicit re-check of recent commits.
- **Severity:** Low (informational)

---

## 6. Security

### 6.1 `MasterMac` target's entitlements were missed by the `aps-environment` Debug/Release split
- **Location:** `Resources/MasterRPG.entitlements` (no `aps-environment` key; used unsplit by both the `MasterMac` target's Debug and Release configs — confirmed via `MasterRPG.xcodeproj/project.pbxproj:7317-7323,7397` against the `MasterMac` target definition at `project.pbxproj:3369-3402`), contrast with `Resources/MasterRPG-Debug/-Release.entitlements` (`project.pbxproj:8955,9023`) and `Resources/MasterTV-Debug/-Release.entitlements` (`project.pbxproj:7613,7659`)
- **What:** MasterMac uses `INFOPLIST_FILE = Resources/Info.plist` — the same file the iOS/visionOS target uses, which declares `UIBackgroundModes` including `remote-notification` (`Resources/Info.plist:116-120`) — but is code-signed with an entitlements file that has no `aps-environment` key at all, unlike its three sibling targets (MasterRPG, MasterTV, RPGShare), all of which were previously split into matching `development`/`production` Debug/Release pairs.
- **Why:** A target that declares the `remote-notification` background mode but has no `aps-environment` entitlement can't register for CloudKit push-driven background sync — MasterMac only picks up remote CloudKit changes when foregrounded, unlike its siblings. This is exactly the entitlements-drift class of bug the prior `aps-environment` fix addressed; MasterMac appears to have been missed by that pass.
- **Action:** Split `Resources/MasterRPG.entitlements` into `-Debug`/`-Release` variants with matching `aps-environment` values, consistent with the naming convention already used for the other three targets.
- **Severity:** Medium

### 6.2 Join-code brute-force throttle confirmed present, wired, and effective at the TLS layer
- **Location:** `Modules/GameRPG/Network/ConnectionAttemptThrottle.swift`, `Modules/GameRPG/Network/GameJoinCodeModel.swift`, `Modules/GameRPG/Master/MasterNetworkController.swift:177-229`, `Modules/GameRPG/Network/NWParameter+GameMaster.swift:45-61`
- **What:** **STATUS: CONFIRMED, no regression.** The 3-strikes/exponential-backoff actor is still wired into both Master/Player network controllers' `failed(with:for:)` delegate callbacks, triggered by an actual TLS-handshake PSK mismatch, not just an app-level check. The passcode is never sent over the wire or advertised in the Bonjour TXT record; it derives a `TLS_PSK_WITH_AES_128_GCM_SHA256` key via HMAC-SHA256, so a wrong guess fails the handshake itself.
- **Action:** None; re-confirming the prior "adequate" judgment per this pass's explicit re-check.
- **Severity:** Low (informational)

### 6.3 Join codes stored in `UserDefaults`, not Keychain
- **Location:** `Modules/GameRPG/Network/GameJoinCodeModel.swift:28-93`
- **What:** `masterCode`/`playerCode`/`lastUsedMasterJoinCode` persist in plain `UserDefaults`.
- **Why:** These are ephemeral, low-value, locally-generated 4-digit local-network pairing codes — not account credentials, not synced, changeable anytime — so device-local `UserDefaults` access requires the same sandbox access an attacker would already need. Judged adequate given §6.2's throttle covers the real attack surface (repeated remote guesses).
- **Action:** None required.
- **Severity:** Low (informational)

### 6.4 Force-unwrap on UTF-8 encoding of the join-code passcode
- **Location:** `Modules/GameRPG/Network/NWParameter+GameMaster.swift:48`
- **What:** `SymmetricKey(data: passcode.data(using: .utf8)!)` force-unwraps the result.
- **Why:** Practically unreachable — a Swift `String` is always valid Unicode, so this specific force-unwrap carries no real crash risk, unlike other force-unwraps this and prior audits have found. Flagged only as a style/consistency nit since the surrounding networking code is otherwise careful to avoid force-unwraps.
- **Action:** Low-priority — replace with a `guard let` for consistency.
- **Severity:** Low

---

## 7. Performance

### 7.1 No new performance findings beyond §3.3; targeted areas reviewed and found solid
- **Location:** `Modules/GameRPG/Controller/MasterController.swift`, `Modules/GameRPG/SharePlay/RPGSharePlayController.swift`, `Modules/GameRPG/Table3D/GameTableModel.swift`, `Modules/GameRPG/Network/GameNetworkController.swift`
- **What:** `RPGSharePlayController.swift`'s 13 `Task {}` sites consistently pair with `[weak self]` and explicit cancellation; `GameTableModel.updateFogOfWar` is gated behind a signature-comparison cache avoiding redundant board re-renders (the untracked-`Task` issue itself is §3.3, filed under Concurrency); `GameNetworkController`'s dedup ring buffer is correctly bounded (limit 512, evicts oldest) with a `reset()`; no `CIContext` usage anywhere in the codebase; media (Photo/Audio/Pdf/Space) storage consistently resolves through the iCloud-preferring `FileManager.cloudURL ?? FileManager.groupURL ?? URL.documentsDirectory` fallback (see §9.3 for its duplication), never Caches, and never as large binaries directly in Core Data.
- **Action:** None required.
- **Severity:** Low (informational)

---

## 8. SwiftUI / UI

### 8.1 CLAUDE.md's five named SwiftUI anti-patterns — verified clean repo-wide
- **Location:** repo-wide grep across `Modules/*/View`, `Modules/*/Sheet`, `Modules/*/EntryEditor`, and all other SwiftUI surfaces
- **What:** Zero real violations found for: `foregroundColor()` (0 hits), `tabItem()` (0 hits), the 1-parameter `.onChange(of:)` closure form (0 hits after excluding the valid 0- and 2-parameter forms), `.onTapGesture()` used where `Button` should be (the one hit, `Modules/CoreRPG/Inspector/InspectorRowView.swift:74`, uses `count: 2` — the explicit CLAUDE.md-sanctioned exception for needing tap count). The two apparent `.cornerRadius(` and `GeometryReader` hits are both false positives on closer read: `Modules/GameRPG/Statistics/View/GameStatisticsDiceChart.swift:25` is Swift Charts' `SectorMark.cornerRadius(_:)` (an unrelated chart-mark API, not the deprecated `View.cornerRadius()`), and the two `GeometryReader` files (`GameTableView.swift`, `ImagePresentationView.swift`) both use `GeometryReader3D` — the visionOS RealityKit-placement API, which has no `containerRelativeFrame()`/`visualEffect()` equivalent.
- **Action:** None required.
- **Severity:** Low (informational — verified clean)

### 8.2 Icon-only buttons consistently use the accessible `Label` + `.iconOnly` pattern
- **Location:** spot-checked across `Modules/CoreRPG/ItemViews/ModalCloseButton.swift`, `ModalCloseOkButton.swift`, `ModalPresentCloseButton.swift`, `Modules/PdfRPG/Pdf/SelectionBar.swift:76-85`, and ~15 more files matching the "`Button {` + bare `Image(systemName:)`" grep pattern
- **What:** Every sampled site wraps its icon in `Label { Text(...) } icon: { Image(systemName: ...) }` (applying `.labelStyle(.iconOnly)` only where visual space demands it), which always carries an accessible title even when visually icon-only — not the bare `Image`-as-label anti-pattern the grep pattern was screening for.
- **Action:** None required; this is a broad spot-check, not exhaustive.
- **Severity:** Low (informational — verified clean)

### 8.3 Dead `animatableData` computed property in `SpaceViewer.swift`
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:23-31`
- **What:** `SpaceViewer` declares a computed `var animatableData: AnimatablePair<Float, Float>` that reads/writes the view's `yaw`/`pitch` `@State`, but `struct SpaceViewer: View` never conforms to `Animatable` anywhere in the file or the module — confirmed via grep. SwiftUI's animation system only interpolates through `animatableData` for types that declare the `Animatable` conformance, so this property is never invoked by the framework; every actual `yaw`/`pitch` mutation happens via plain assignment elsewhere (lines 245-246, 334-335, 826-827, 845-850).
- **Why:** A fully-implemented property that looks like it wires object rotation into SwiftUI's Animatable interpolation machinery, but is inert boilerplate — misleading to a future reader trying to understand how rotation animation actually works here.
- **Action:** Delete it, or if per-frame interpolated rotation was the original intent, add `: Animatable` to the `SpaceViewer` declaration and verify the resulting behavior is actually desired (it would change how `withAnimation`-wrapped yaw/pitch changes render).
- **Severity:** Low

### 8.4 Computed-property view decomposition remains the largest single house-rule violation (~100+ sites, not re-catalogued this pass)
- **Location:** representative — `Modules/CoreRPG/Sheet/SheetEntryView.swift`, `Modules/CoreRPG/LGViews/ItemHeaderEditorView.swift` (full site list in `Docu/CODE_AUDIT_5.md` §8.2)
- **What:** CLAUDE.md's "decompose views into separate `View` structs, not computed properties" rule is still violated at scale across the codebase; this pass did not re-derive the full site list, only confirmed via spot-check that the pattern is unchanged in volume.
- **Why:** Defeats SwiftUI's diffing boundary on the app's largest, most complex views; the mechanical fix (extract to `private struct: View`) is low-risk per-site but the volume makes it a backlog item rather than a single fix.
- **Action:** Treat as an opportunistic backlog item — apply the extraction whenever a touched view file is already being edited for another reason, per the prior audit's own recommendation.
- **Severity:** Medium

---

## 9. Dead code / duplication / refactor

### 9.1 Orphaned duplicate StoreKit configuration file
- **Location:** `Resources/RPGResources/Resources/MasterRPG.storekit` vs. `Modules/RolePlayGameKit/InApp/MasterRPG.storekit`
- **What:** Two byte-for-byte identical `.storekit` files exist, but only `MasterRPG.xcodeproj/xcshareddata/xcschemes/MasterRPG.xcscheme:94` references a StoreKit configuration, and it points exclusively to the `RolePlayGameKit/InApp` copy — confirmed via checking every scheme (including MasterMac/MasterTV) and the pbxproj build phases.
- **Why:** The `Resources/RPGResources` copy is dead weight nothing loads at build/run/test time. Because nothing forces the two to stay in sync, a future product/price edit to the "live" copy will silently desync from the orphaned one, misleading anyone who edits the wrong file.
- **Action:** Delete `Resources/RPGResources/Resources/MasterRPG.storekit`, or replace it with a symlink to the canonical file if a Resources-target-local scheme needs it.
- **Severity:** Medium

### 9.2 Intra-file duplicated head-anchor centering logic in `SpaceViewer`
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:331-358` (new `adopt(_:into:)`) vs. `Modules/SpaceRPG/Space/SpaceViewer.swift:601-633` (pre-existing `loadEntity` immersive branch)
- **What:** The newly-added `adopt(_:into:)` (part of the uncommitted diff) re-implements, near-verbatim, the same five-statement sequence already in `loadEntity`'s immersive branch: create `AnchorEntity(.head)`, set `trackingMode = .once`, compute `visualBounds(relativeTo: nil).center`, offset by `-visualCenter.x, -visualCenter.y, -visualCenter.z - 1.5`, add as child, add to content, call `applySharedPlacementIfNeeded()`.
- **Why:** Same-file duplication of positioning math, including the magic `1.5` meter offset — a future tuning change has to be made in two places in the same file, and it's easy to update one call site and miss the other.
- **Action:** Extract a private helper, e.g. `func headAnchorPlacement(for entity: Entity) -> AnchorEntity`, called from both `loadEntity` and `adopt(_:into:)`.
- **Severity:** Medium

### 9.3 Duplicated iCloud/App-Group/Documents fallback expression across 4 files
- **Location:** `Modules/CoreRPG/Foundry/FoundryImportArchive.swift:209-211`, `Modules/CoreRPG/Files/CloudDocumentController.swift:229-231`, `Modules/CoreRPG/Import/ExternalImportSourceRegistry.swift:137-139`, `Modules/CoreRPG/Files/LocationFileManager.swift:18-20`
- **What:** The exact expression `FileManager.cloudURL ?? FileManager.groupURL ?? URL.documentsDirectory`, with an identical explanatory comment, is copy-pasted verbatim into 4 separate CoreRPG files rather than factored into one shared helper.
- **Why:** This looks like the fix applied for a prior audit finding about crash-prone force-unwraps, but the fix itself was duplicated instead of centralized — a future change to the fallback order needs 4 synchronized edits.
- **Action:** Add a `static var preferredRootUrl: URL` `FileManager` extension in one place (next to `FileManager.cloudURL`/`.groupURL`) and have all 4 call sites use it.
- **Severity:** Medium

### 9.4 Duplicated 100ms debounce pattern instead of reusing `DebouncerModel`
- **Location:** `Modules/CoreRPG/EntryEditor/EntryEditorHeaderView.swift:177`, `Modules/CoreRPG/EntryEditor/EntryEditorContent.swift:71`, `Modules/CoreRPG/EntryEditor/TextEditModel.swift:89,109`, `Modules/CoreRPG/Sheet/SheetRootModel.swift:922,942`
- **What:** Six call sites hand-roll the same `Task { try? await Task.sleep(for: .milliseconds(100)); ... }` cancel/sleep/check-cancellation pattern (haptic delay, focus delay, link-recalculation debounce ×2, parent-update-after-move ×2) — the identical `100` literal, unnamed — while `Modules/CoreRPG/Stores/DebouncerModel.swift` already provides a generic, cancellation-safe `DebouncerModel<T>` wrapper none of these sites use.
- **Why:** Six independent hand-rolled cancel/sleep copies is a correctness risk (e.g. `TextEditModel.swift`'s two debounce tasks don't share a canceller, so a name-update and content-update in flight simultaneously race independently) and a readability cost.
- **Action:** Route these through `DebouncerModel`, or at minimum a shared named constant, instead of the bare literal repeated six times.
- **Severity:** Medium

### 9.5 Dead code: unused `ModelEntity.size()` extension
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:909-919`
- **What:** `extension ModelEntity { func size() -> SIMD3<Float> { ... } }` computes mesh bounds width/height/depth, but a repo-wide grep for `.size()` finds zero callers, including within `SpaceViewer.swift` itself.
- **Action:** Delete, or move next to where scaling is actually computed (inline `visualBounds`-based logic elsewhere in the same file) and use it there.
- **Severity:** Low

### 9.6 Dead code: unused device-rotation observation feature
- **Location:** `Modules/CoreRPG/ViewModifiers/DeviceRotateViewModifier.swift:1-56`
- **What:** `View.observeRotate(with:)`, `DeviceRotationViewModifier`, and `DeviceRotationModel` (a public `@Observable` class with a 4-case orientation enum) are fully implemented with zero call sites anywhere in `Modules/` or `Sources/` outside their own declaration file.
- **Why:** An entire unused feature ships in every module linking CoreRPG for no functional benefit; suggests either an abandoned feature or a removed caller.
- **Action:** Confirm via history whether a consumer was removed; delete if so.
- **Severity:** Low

### 9.7 Dead code: `DumpingEnvironment` debug view never used in production
- **Location:** `Modules/CoreRPG/Debug/DumpEnvironment.swift:6-34`
- **What:** `DumpingEnvironment<Content: View>` (dumps/prints the current `EnvironmentValues`) is only instantiated inside its own `#Preview` block; no other file constructs it.
- **Action:** Wire it into a debug menu/`#if DEBUG` overlay so it's reachable, or delete it.
- **Severity:** Low

### 9.8 Spelling mistakes in `MARK` comments
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:190,220,624`
- **What:** Three `MARK` section headers are misspelled: "Carousell Items" (→ "Carousel"), "Folder / Colllection" (→ "Collection"), "controller mantainence" (→ "controller maintenance").
- **Why:** Cosmetic, but `MARK` comments are Xcode's jump-bar labels for this heavily-shared 742-line protocol-default-implementation file, so search-by-name silently fails for the correct spelling.
- **Action:** Fix the three strings.
- **Severity:** Low

### 9.9 Oversized files (>500 lines) not previously catalogued
- **Location:** `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift` (1089 lines, 10 MARK-delimited concerns — policy/admission, bookkeeping, the main queue actor at ~510 lines alone, deferred-delivery queue, attachment retry); `Modules/MapRPG/Map/MapOverlayGeometry.swift` (821 lines bundling 3 unrelated, independently-testable geometry namespaces: needle-drag math, fan-menu placement math, magnifier-loupe math — none reference each other); `Modules/CharacterRPG/Controller/EditController.swift` (850 lines — nearly double the next-largest module `EditController.swift`, mixing entry-list editing, quick-editor, save, and repair concerns the codebase's own `Type+Feature.swift` convention elsewhere already splits out); `Modules/CharacterRPG/Controller/SearchController.swift` (718 lines vs. 12-14 lines for every other module's version). Plus ~37 more files over 500 lines, including `Modules/RolePlayGameKit/Import/Foundry/FoundryImportView.swift` (866), `Modules/RuleRPG/Model/RuleModel.swift` (851), `Modules/GameRPG/Root/GameRootModel.swift` (802), `Modules/MapRPG/Model/MapModel.swift` (742), `Modules/GameRPG/Table3D/GameEquipment.swift` (716), `Modules/MapRPG/Map/MapEditorModel.swift` (711), `Modules/DiceRPG/Model/DiceModel.swift` (687).
- **Why:** The four detailed files each show clear internal seams (existing `MARK` boundaries or a stark size outlier vs. sibling modules) that make a mechanical split low-risk and high-value. Most `Controllable/*.swift` protocol-default files in the broader list are the *good* pattern — legitimate shared-logic centralization — and are lower priority to split than the domain-model/root-model files in the same size range.
- **Action:** Split the four detailed files along their existing seams first; treat the remaining ~37 as an opportunistic backlog, prioritizing `GameRootModel.swift`, `MapModel.swift`, `GameEquipment.swift`, `MapEditorModel.swift`, `RuleModel.swift` since domain/root-model files this size are most likely to mix unrelated concerns.
- **Severity:** Low

### 9.10 `DataModel+Extensions.swift` wrapper still duplicated across 12 modules
- **Location:** `Modules/*RPG/Model/DataModel+Extensions.swift` (40-114 lines each)
- **What:** **STATUS: STILL PRESENT, unchanged.** Each file repeats the same `entriesModel` get/set pair and `entryOrNew(for:)` wrapper, differing only by entity type; the real generic logic is already centralized in `Modules/CoreRPG/Persistence/CoreDataRelationship.swift`.
- **Action:** Unchanged from prior recommendation — optional, a protocol default with `associatedtype Entry` could reduce this further if Core Data codegen allowed it.
- **Severity:** Low

### 9.11 `FolderListController` per-module boilerplate still duplicated across 12 modules
- **Location:** `Modules/*RPG/Controller/FolderListController.swift` (38-40 lines each)
- **What:** **STATUS: STILL PRESENT, unchanged.** Confirmed mechanically necessary (each module has its own `Route` type), not a copy-paste drift source.
- **Severity:** Low

### 9.12 Hardcoded per-module thumbnail-size constants still present
- **Location:** `Modules/SpaceRPG/Controller/CacheController.swift:16`, `Modules/PdfRPG/Controller/CacheController.swift:21`, `Modules/PhotoRPG/Controller/CacheController.swift:57,63`, `Modules/MapRPG/Controller/CacheController.swift:31`
- **What:** **STATUS: STILL PRESENT, unchanged.** Each module hardcodes its own thumbnail/downsample target size; the underlying resize/downsample primitives are correctly centralized in `Modules/CoreRPG/Extensions/Image+AKImage.swift:154-207`, so only the per-module target *size* is duplicated, not the resize logic itself.
- **Severity:** Low

### 9.13 Orphan-cleanup Core Data duplication — FIXED
- **Location:** `Modules/CoreRPG/Persistence/CoreDataRelationship.swift:44` (new centralized `syncEntries(...)` generic), previously duplicated at e.g. `Modules/PdfRPG/Controller/DataController.swift:46-63`
- **What:** **STATUS: FIXED.** The orphan-cleanup logic previously duplicated verbatim across ~10 modules' `DataController.swift` now calls one centralized generic, used identically by all 12 modules. The prior High-severity CloudKit-merge-drift risk is resolved.
- **Severity:** Low (informational)

### 9.14 "reparing" → "repairing" typo — FIXED
- **Location:** `Modules/AdventureRPG/Controller/LinkController.swift:172`, `Modules/CharacterRPG/Controller/LinkController.swift:129`, `Modules/MapRPG/Controller/LinkController.swift:92`, `Modules/TableRPG/Controller/LinkController.swift:92`
- **What:** **STATUS: FIXED.** All 4 sites now read "repairing"/"preparing" correctly.
- **Severity:** Low (informational)

### 9.15 TODO/FIXME sweep — still exactly one marker in the repo
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:422` (moved from ~265 due to the uncommitted diff): `// TODO(visionOS): auto-fit the loaded model to the volumetric window's bounds`
- **What:** Confirmed still the only TODO/FIXME/HACK/XXX/`#warning` marker in the ~267K-line codebase.
- **Severity:** Low (informational)

### 9.16 `print()` usage audit — still clean
- **Location:** all `print(` call sites repo-wide
- **What:** Every non-doc-comment `print(` site is inside `#Preview`/`#Playground`/`PreviewData.swift`, or guarded by `#if DEBUG`. No new unguarded `print()` found. (The prior audit's characterization of `Modules/GeneratorRPG/Playground/MyAiPlayground.swift:10-12,34-36` as "commented-out code" was imprecise on re-inspection — they're active triple-quoted `LanguageModelSession` instruction strings inside a canvas-only `#Playground`, not dead code — still non-shipping either way.)
- **Severity:** Low (informational)

---

## 10. Cross-cutting recommendations

1. **The uncommitted `SpaceRPG` window→immersive handoff feature (§5.1, §9.2) should get a state-machine review before it ships**, not just the two fixes listed. `SpaceHandoffModel`'s single-slot `pending` plus `SpaceViewer`'s unconditional `handedOffToImmersive = true` together assume the handoff always succeeds and only ever targets an idle immersive space — neither assumption holds once a person can have multiple Space items open across a window and an immersive space simultaneously, which the app's own multi-window architecture allows today.
2. **The three `*Entity.swift` `Transferable` conformances (§5.2) were copy-pasted, bug and all.** Given `AudioEntity` (also a real-file-backed module) doesn't even attempt file export, and three other entities export a mislabeled fake PDF, this points to `Transferable`/App-Intents export never having been exercised end-to-end for any of the four file-carrying modules — worth a dedicated pass across all four rather than fixing PdfEntity in isolation and letting Photo/Space/Audio drift further.
3. **Small hand-rolled `Task { sleep; ... }` debounces (§9.4) and duplicated `FileManager` fallback logic (§9.3) are two faces of the same root cause**: a correct shared primitive exists (`DebouncerModel`, the `cloudURL`/`groupURL` fallback pattern) but call sites re-derive it by hand instead of reusing it. Same root cause as the still-present `DataModel+Extensions`/`FolderListController` per-module duplication (§9.10, §9.11) — the 15-module architecture keeps re-deriving generic logic per call site or per module instead of via one shared, generic implementation. The orphan-cleanup fix (§9.13) shows the codebase already knows how to do this centralization correctly; apply the same technique opportunistically to §9.3/§9.4.
4. **Entitlements drift (§6.1) will recur without a lint check.** This is now two consecutive audit passes where a manual entitlements split job missed a target (previously caught and fixed for MasterRPG/MasterTV/RPGShare; now MasterMac). A simple CI script asserting all four targets' entitlements files declare a matching `aps-environment` (or documenting why one deliberately doesn't) would catch this class of bug before an audit has to.
5. **`DispatchQueue.main.asyncAfter` in Navigator (§3.1) is the single longest-standing unresolved finding in this codebase's audit history — 4 consecutive passes.** Everything else flagged 3+ audits ago (`TimedMessageList`'s selector-based Timer, `EntityGestureState`'s force-unwraps, the `MasterNetworkController` Sendable gap, `AttributedString`'s `.last!`) has since been fixed. This is worth prioritizing precisely because it's the one holdout — either fix it or leave an explicit comment on why it's intentionally deferred, so future audits don't re-flag it as an oversight.

---

## 11. What was NOT audited

- **`MasterMac` and `MasterTV` schemes were not separately compiled.** Compiler ground truth (zero warnings) comes from a full clean build of the `MasterRPG` (iOS Simulator) scheme only; `#if os(macOS)`/`#if os(tvOS)` code paths were reviewed by reading, not a dedicated per-platform build.
- **`Tests/` — quick scan only, no deep coverage review**, per the skill's standard scope. Large test files (`SharePlayPackageTransportTests.swift` at 4,082 lines, `MasterPlayerControllerTests.swift` at 2,267 lines) were not read line-by-line.
- **`.xcdatamodeld` Core Data model files were not opened directly as raw XML.** CloudKit optional/default-value compliance was assessed via the mapped Swift model layer, not a field-by-field schema audit.
- **Algorithmic correctness of the RealityKit/Table3D 3D rendering pipeline, and bit-level correctness of the Foundry LevelDB/Snappy/WAL binary-format readers.** Surface-level issues (force-unwraps, bounds checks) were checked; the underlying parsing/decompression algorithms were not independently re-derived against spec.
- **`RPGTabletopGameContent` SPM package and all other SPM dependencies** (`swift-custom-dump`, `swift-snapshot-testing`, `swift-syntax`, `xctest-dynamic-overlay`) — treated as black boxes.
- **Localization wording/correctness** — a dedicated `Docu/LOCALIZATION_ACCESSIBILITY_AUDIT.md` already exists for that scope.
- **Instruments profiling / measured runtime performance.** Findings in §7 are pattern-based (source reading), not trace-validated; no `.trace` capture was taken.
- **Xcode project/build-settings structure beyond deployment-target/entitlements/warning-flag settings, and scheme configuration beyond the one scheme built for ground truth.**
- **StoreKit 2 product configuration in App Store Connect** — file/code structure only (§9.1), not whether product IDs match what's configured in App Store Connect.
- **The `Docu/CODE_AUDIT_1.md`–`_5.md`, `SWIFTUI_PERFORMANCE_AUDIT.md`, and any other prior reports in this repo** were used as a cross-reference (every prior "known finding" was re-verified against current source this pass, see §3, §5, §6, §9 status markers) but this report is independently derived from current source, not copied — treat this file as the current source of truth and `Docu/` as historical record.
- **Full dead-code census.** §9.5-§9.7's unreferenced symbols come from a ~20-symbol spot-check, not an exhaustive cross-reference of every public type/method in a 267K-LOC codebase — grep-based dead-code detection has real false-negative risk (dynamic dispatch, `@objc` selectors, App Intents reflection).

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line.

- **§5.1** — open `Modules/SpaceRPG/Space/SpaceViewer.swift`, lines 315-326 (`moveToImmersiveSpace`): confirmed it unconditionally sets `handedOffToImmersive = true` and discards local entity references before awaiting `scenesManager.openSpaceViewer`. Then open `Modules/CoreRPG/ScenesManager/ScenesManager.swift`, lines 451-464: confirmed `openSpaceViewer` returns early with no signal to the caller when `state == .opening || state == .opened`. Independently traced by two separate reviewers this pass (the dispatched bugs/security/performance sub-agent, and a direct read of the same diff before that agent's report arrived) with matching conclusions.
- **§5.2** — open `Modules/PdfRPG/Intent/PdfEntity.swift`, lines 58-93: confirmed the primary `FileRepresentation(exportedContentType: .pdf)` renders only `item.name`/`item.description` via `ImageRenderer`, never touching a real file path. Opened `Modules/PhotoRPG/Intent/PhotoEntity.swift:58-93` and `Modules/SpaceRPG/Intent/SpaceEntity.swift:58-93` directly and confirmed both contain the byte-identical block, including `SpaceEntity` still claiming `exportedContentType: .pdf` for a 3D object. Opened `Modules/PdfRPG/Intent/PdfEntity+Image.swift:24-38` and confirmed `loadAssetData` sources from `cacheController.photo`/`.thumbnail`, not a raw-asset loader.
- **§3.1** — open `Modules/CoreRPG/Navigator/Core/NavigationSend.swift`, lines 107-114. Confirmed `DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.send(values: values) }` inside the `.auto` case, with no stored task/cancellation handle.
- **§6.1** — open `MasterRPG.xcodeproj/project.pbxproj`, line 3369 (`8E49F9D82B8F654D00527E6D /* MasterMac */`) through line 3402 to confirm target identity; line 7317-7323 to confirm its Debug config's `CODE_SIGN_ENTITLEMENTS = Resources/MasterRPG.entitlements`; then open `Resources/MasterRPG.entitlements` directly and confirm no `aps-environment` key exists (contrast with `Resources/MasterRPG-Debug.entitlements:5`, which has one). Confirmed `Resources/Info.plist:116-120` lists `remote-notification` under `UIBackgroundModes` and that MasterMac's `INFOPLIST_FILE` setting points at this same file.
- **§9.1** — open `MasterRPG.xcodeproj/xcshareddata/xcschemes/MasterRPG.xcscheme`, line 94, confirm the StoreKit Configuration path points only at `Modules/RolePlayGameKit/InApp/MasterRPG.storekit`; `diff` the two `.storekit` files directly to confirm they're currently byte-identical.
- **§3.4** — open `Modules/SpaceRPG/Space/EntityGestureState.swift`, lines 7-49. Confirmed the class declaration has no `@MainActor`, and only `static let shared` at line 48 carries the annotation.
- **§8.3** — open `Modules/SpaceRPG/Space/SpaceViewer.swift`, lines 17 and 23-31. Confirmed `struct SpaceViewer: View` has no `Animatable` conformance anywhere in the file (grepped the whole module for `SpaceViewer.*Animatable` — zero hits) while `animatableData` is fully implemented at lines 23-31.

If any finding doesn't reproduce when you visit the line, flag the specific reference for re-investigation.
