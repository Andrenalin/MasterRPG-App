# MasterRPG Code Audit

Generated 2026-09-04. Scope: ~268,000 Swift LOC across ~1,994 files in 15 feature modules under `Modules/` (AdventureRPG, AudioRPG, CharacterRPG, CoreRPG, DiceRPG, GameRPG, GeneratorRPG, MapRPG, PdfRPG, PhotoRPG, RolePlayGameKit, RuleRPG, SpaceRPG, TableRPG, WeatherRPG) plus four app targets under `Sources/` (MasterRPG, MasterTV, RPGShare, DiceRollerWidgetExtension) and the MasterMac scheme. `.git/`, `.build/`, and `*.xcuserdata/` are excluded; no `Dead/` or archive directory exists in this repo.

**Compiler ground truth**: clean builds of all three primary schemes — `MasterRPG` (iOS/visionOS Simulator), `MasterMac` (macOS), `MasterTV` (tvOS Simulator) — each succeeded with **zero real Swift compiler warnings** (the only "warning:" lines in any log are an unrelated `appintentsmetadataprocessor` tooling notice, "Metadata extraction skipped, no AppIntents.framework dependency found," emitted for two resource-only framework targets). This is consistent with the project's `SWIFT_STRICT_CONCURRENCY = complete` setting and means the concurrency/API-modernity findings below come entirely from manual sweep, not compiler diagnostics.

**Context**: this codebase has already been through ten full audit rounds (`Docu/CODE_AUDIT_1.md`–`_10.md`) plus several scoped deep-dives, with today's own commit history showing active remediation (`da11b4a9`, `3b12c9f4`, `78b0e4d5`, `83629410`, `40ee5caa`). All findings below were freshly re-derived from current source by four independent read-only passes (concurrency/API modernity, dead code/duplication, bugs/security/performance, SwiftUI/UI) and this codebase's maturity shows: **no Critical findings surfaced in any pass.** Several previously-plausible suspicions (byte-identical `LinkController`s, duplicate `FolderListController`/`DetailFolderListView` boilerplate, `DataController` copy-paste, image/path-helper duplication) were checked and found to be either already-fixed or not actually duplicated — reported below as verified-clean rather than silently dropped, so this isn't mistaken for unchecked scope.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

---

## 1. Executive summary

1. **[High] `GeneratorCommands` is never registered in the app's macOS/iPadOS menu bar** — §5.1 — `Sources/MasterRPG/Menu/MenuCommandList.swift`. Every one of the 11 other feature modules gets a menu entry; GeneratorRPG silently doesn't, despite a complete, ready-to-use `GeneratorCommands` type sitting unused.
2. **[High] `AdventureChatRootView.swift` is a fully orphaned 321-line file** — §9.1 — `Modules/GeneratorRPG/Root/AdventureChatRootView.swift`. Despite its name, it contains no `View` at all — five supporting types with zero references anywhere else in the repo.
3. **[Medium] A drop shadow is rendered invisible by modifier ordering** — §8.1 — `Modules/TableRPG/View/TableGenerationPanelView.swift:50-58`. `.shadow()` is applied after `.clipShape()`, so it's clipped away at the same boundary it's meant to extend past — a real, user-visible regression.
4. **[Medium] Views are split into computed properties instead of separate `View` structs, ~120 times** — §8.2 — repo-wide. CLAUDE.md explicitly bans this pattern; it's the single most repeated style violation found.
5. **[Medium] A RealityKit continuation can never resume if the 3D table view is dismissed early** — §3.1 — `Modules/GameRPG/Table3D/GameTableView.swift:542-551`. No cancellation handling on a `withCheckedContinuation` awaited from a SwiftUI `.task`.
6. **[Medium] Foundry system-package mapping runs its entire pass on the Main Actor** — §3.2 — `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift:179-343`. Unlike its sibling parsers, this ties up the UI thread for the whole import of a large compendium.
7. **[Medium] A whole-dictionary `@Observable` property causes systemic list over-rendering** — §7.1 — `Modules/CoreRPG/ItemList/ItemDataModel.swift:28`. Editing any one item re-invalidates every other visible row in the same module.
8. **[Medium] Four modules hand-duplicate `GenericGameController` instead of building on it** — §9.4 — DiceRPG, CharacterRPG, SpaceRPG, MapRPG. Two sibling modules already use the correct thin-override pattern.
9. **[Medium] Several of the largest files in the repo (`MasterController.swift`, `FoundryVTTDomainMapper.swift`, the two Foundry readers) remain unsplit** — §9.7 — despite most already having clean internal `MARK` boundaries ready to extract along.
10. **[Medium] A recurring pattern of half-built AI-generation features scaffolded but never wired to product UI** — §9.8 — `SheetGenerationRequest`/`TableGenModel`/`ClearDiceHistoryIntent`/`BlurText` — worth a single product decision (finish or delete) rather than four separate cleanups.

---

## 2. Quick wins (≤30 min each)

- **Wire `GeneratorCommands` into `MenuCommandList.swift`** — `Sources/MasterRPG/Menu/MenuCommandList.swift`. A two-line addition (import + call) restores the missing macOS/iPadOS menu entry. See §5.1.
- **Reorder `.shadow()` before `.clipShape()`** — `Modules/TableRPG/View/TableGenerationPanelView.swift:50-58`. See §8.1.
- **Wrap or remove the 5× `print("url nil ")` calls** — `Modules/{MapRPG,GeneratorRPG,DiceRPG,CharacterRPG,AdventureRPG}/Model/PreviewData.swift`. Not gated by `#if DEBUG`; replace with `Logger` or gate. See §9.3.
- **Fix "occurences" → "occurrences"** — `Modules/CoreRPG/Editors/QuickLinkEditor.swift:39`. User-facing, localized help text. See §9.10.
- **Extract the inline `CGSize(width: 64, height: 64)` into a named constant** — `Modules/PhotoRPG/Controller/CacheController.swift:65`, next to the already-named `thumbnailMaxPixelSize` three lines below. See §9.12.
- **Delete the small confirmed-dead files** — `CacheItemList`, `AnchorKey<A>`, `IgnoreEquatable`/`IgnoreHashable`, `QuickLinkConfig`, `SheetRowGeometryMatch`, `LogScreenCategory`, `WindowKeyViewModifier`, `NavigationViewProviding.swift`, `RPGShortcutCatalog.swift` — each a self-contained, zero-reference removal. See §9.1.
- **Remove the stale `@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)` floors** — `Modules/CoreRPG/Navigator/Extensions/NavigationLink+Navigator.swift:40,102`. Permanently true given the 26.0 deployment target. See §4.1.

---

## 3. Concurrency

### 3.1 RealityKit scene-render continuation can never resume if the view tears down first
- **Location:** `Modules/GameRPG/Table3D/GameTableView.swift:542-551` (`waitForFirstRenderedFrame(of:)`), awaited from the `.task` at `:211-214`
- **What:** `await withCheckedContinuation { continuation in scene.subscribe(to: SceneEvents.Update.self) { ...; continuation.resume() } }` has no `withTaskCancellationHandler` and no `Task.isCancelled` check.
- **Why:** SwiftUI's automatic `.task` cancellation only flips `Task.isCancelled` — it cannot unblock an already-suspended `withCheckedContinuation`. If the volumetric window/RealityView is dismissed before a further RealityKit ECS frame renders (plausible on a fast dismiss right after opening a table), the subscription never fires, the continuation is never resumed, and the awaiting `Task` plus the retained subscription leak for the process lifetime.
- **Action:** Wrap in `withTaskCancellationHandler`; cancel the RealityKit subscription and resume the continuation (with a sentinel or throw) in the `onCancel` closure, matching the cancellation-aware continuation pattern already used in `RPGSharePlayController.swift`/`ConnectionController.swift`.
- **Severity:** Medium

### 3.2 Foundry system-package domain mapping runs its entire pass on `@MainActor`
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift:179-180` (`map`), `:199-200` (`@MainActor final class FoundryMappingState`), `:271` (`build()`), `:337-343` (`cooperativeCheckpoint()`)
- **What:** Unlike its sibling parsers (`FoundryVTTImportReader`, `FoundrySystemPackageReader`, `UniversalVTTReader`, all confirmed to run inside `Task.detached`), the actual document→domain-model mapping pass (indexing, folders, rule projection, packaged assets, per-collection chat/actor/scene mapping) runs entirely on the Main Actor. The only mitigation is a manual cooperative-yield counter calling `Task.yield()` every 16 units of work.
- **Why:** For a large Foundry package — this file's own reason for existing — this ties up the Main Actor for the whole import, competing with SwiftUI's render loop. `Task.yield()` only hands control back between other already-queued main-actor work; it doesn't make this genuinely concurrent with UI rendering the way `Task.detached` would. The code's own comment acknowledges this as known debt ("can't move to a background actor without a much larger rewrite").
- **Action:** Move `FoundryMappingState`'s mutable working set off `@MainActor` (nothing in it touches UI) and hop back to `@MainActor` only for the final `@Observable` model writes — or explicitly re-document this as a scoped, permanent exception.
- **Severity:** Medium

### 3.3 Fire-and-forget widget-update `Task.detached` has no cancellation handling
- **Location:** `Modules/DiceRPG/Controller/GameController.swift:594-598`
- **What:** `Task.detached(priority: .utility) { [self] in await diceUpdateWidget(diceResult: diceResult) }` is spawned with no stored handle and no cancellation awareness. This is the sole exception among ~30 `Task.detached` call sites in the codebase, all of which otherwise return the task to the caller or wrap it in `withTaskCancellationHandler`.
- **Why:** A rapid sequence of dice rolls queues up unbounded, uncancellable `UserDefaults`-write + `WidgetCenter.reloadTimelines` calls that can complete out of order. Impact is low (a stale widget dice display, not data loss) and the file's own comment shows this was a deliberate, previously-reviewed tradeoff (references `CODE_AUDIT_Game §3.6`, explaining why `.detached` specifically was chosen here over `nonisolated`), so this is a residual gap in an already-scrutinized decision, not a fresh oversight.
- **Action:** Store the task in a `diceUpdateWidgetTask` property (cancelling any prior one), matching the pattern already used everywhere else, including the identical fix already applied to `GameJoinCodeModel`.
- **Severity:** Low

### 3.4 Sole remaining `ObservableObject` usage — verified justified
- **Location:** `Modules/GameRPG/SetupViews/SharePlayButton.swift:19-21`
- **What:** `@ObservedObject private var groupStateObserver = GroupStateObserver()` is the only occurrence of `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject`/`@EnvironmentObject` anywhere under `Modules/`/`Sources/` (confirmed via full-tree grep).
- **Why:** `GroupStateObserver` is an Apple-owned `GroupActivities` type that conforms only to `ObservableObject`, with no `@Observable` SDK alternative — exactly the "unavoidable legacy interop" exception CLAUDE.md itself carves out, not a violation.
- **Action:** None required.
- **Severity:** Low (informational)

**Swept and confirmed clean, no findings:** `@Observable` classes missing `@MainActor` (0 of ~165 declarations); `DispatchQueue.main`/`.global()`/`.sync` old-style GCD (0 — the 3 raw `DispatchQueue` uses are the mandatory `NWConnection`/`NWListener` callback-queue parameter, immediately hopping into an actor); `Task.sleep(nanoseconds:)` (0); `nonisolated(unsafe)` (1 use, documented and correctly scoped); all other `withCheckedContinuation` sites resume exactly once on every path; all 9 app-level singletons are either genuine `actor`s or correctly `@MainActor`-isolated; completion-handler PhotoKit/AVFoundation/URLSession/GameKit APIs (0 — all native async, `NSItemProvider.loadItem`/`loadDataRepresentation` are the sole justified exceptions with no async replacement); `MasterController`/`PlayerController`/`RPGSharePlayController`/`GameTableModel`'s message-ordering logic uses a consistent, correct cancel-and-chain generation-guard pattern throughout.

---

## 4. API modernity

### 4.1 Vendored `NavigatorUI` still carries `@available` floors below the 26.0 deployment target
- **Location:** `Modules/CoreRPG/Navigator/Extensions/NavigationLink+Navigator.swift:40,102`
- **What:** `@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)` gates two `NavigationLink` initializer extensions; the project's real floor is 26.0 everywhere, so these checks are permanently true. A repo-wide sweep found this as the sole surviving instance of this pattern — every other stale `@available`/`#available` branch below the 26.x floor has already been removed.
- **Why:** Inert annotations that could mislead a reader into thinking pre-26 support is still a concern. No dead `#else` branch is attached, so it's clutter, not unreachable code.
- **Action:** Remove the redundant attributes — or, since this is vendored third-party source (Navigator/NavigatorUI, credited to Michael Long, not app-owned), leave as-is and track the fix upstream instead of hand-editing vendored code.
- **Severity:** Low

_No other API-modernity findings surfaced — the project's very new 26.0 floor combined with a zero-warning clean build across all three platform schemes means essentially nothing in the checklist (PhotoKit/AVFoundation completion handlers, `UIApplication.shared.windows`, legacy `Formatter` subclasses, `String(format:)`, GCD) still exists in the tree._

---

## 5. Bugs / logic errors

### 5.1 `GeneratorCommands` never registered in the app's menu — missing from `MenuCommandList`
- **Location:** `Modules/GeneratorRPG/Menu/GeneratorCommands.swift:1-24` vs. `Sources/MasterRPG/Menu/MenuCommandList.swift:1-49`
- **What:** `GeneratorCommands: Commands` is fully implemented — wraps `ModuleCommands(root:scenesManager:routeActions:key: "-")` exactly like all 11 sibling modules' `*Commands` structs — but `MenuCommandList.swift` (the aggregator that imports and instantiates `AdventureCommands`, `CharacterCommands`, `PdfCommands`, `RuleCommands`, `TableCommands`, `MapCommands`, `AudioCommands`, `DiceCommands`, `PhotoCommands`, `SpaceCommands`, `WeatherCommands`) neither imports `GeneratorRPG` nor instantiates `GeneratorCommands`. Verified directly: `appModel.generatorRoot` does exist and is used elsewhere (`MasterRPGApp.swift`, `WindowViewerList.swift`), so the module itself is integrated — only its menu commands are missing.
- **Why:** On macOS/iPadOS, every other module gets a menu-bar entry and keyboard shortcut for opening its window; GeneratorRPG silently doesn't. Reads as an integration gap rather than an intentional exclusion, since the type exists complete and ready to use.
- **Action:** Add `GeneratorCommands(root: appModel.generatorRoot, scenesManager: appModel.scenesManager, routeActions: routeActions)` to `MenuCommandList.swift`, plus the `GeneratorRPG` import.
- **Severity:** High

### 5.2 `DiceEntityQuery`'s Siri/Shortcuts suggestion cache has no invalidation hook wired
- **Location:** `Modules/DiceRPG/Intent/DiceEntity.swift:120-122` (`cachedEntities`/`lastCacheUpdate`/`cacheValidityDuration`), `:134-152` (`suggestedEntities()`), `:155-158` (`invalidateCache()`)
- **What:** `invalidateCache()` exists specifically to reset this 60-second cache but is never called anywhere in the repo (confirmed via repo-wide grep) — the cache only ever resets via its own TTL expiring.
- **Why:** A dice set renamed or deleted is still offered to Siri/Shortcuts/Spotlight from stale cached data for up to 60 seconds. Bounded impact (the TTL does eventually clear it, and a stale suggestion would just fail to resolve), but the dead `invalidateCache()` reads as a wired-up safety net that isn't.
- **Action:** Call `DiceEntityQuery.invalidateCache()` from `ItemController`'s dice add/rename/delete path, or drop the dead function and document reliance on the TTL alone.
- **Severity:** Low

### 5.3 `FileManager+Coordination.swift` force-unwraps `NSFileCoordinator`'s out-parameter result at 4 call sites
- **Location:** `Modules/CoreRPG/Files/FileManager+Coordination.swift:116-117, 127-128, 140-141, 153-154` (all four `coordinate(...)` overloads: `guard coordinatorError == nil else { throw coordinatorError! }` then `return try result!.get()`)
- **What:** `result` is only ever set inside the synchronous callback `NSFileCoordinator.coordinate` invokes on success; if that contract were ever violated (an OS change, a misbehaving third-party file provider, a partial-failure case that doesn't populate the error out-parameter), both force-unwraps crash instead of surfacing a catchable error.
- **Why:** Repeated identically 4 times, so a regression to this assumption hits every read/write/move path touching security-scoped/iCloud-Drive files. In practice `NSFileCoordinator` reliably calls the block or sets the error, so this is low-probability, but the function already `throws` — there's no reason to force-unwrap.
- **Action:** Replace `coordinatorError!`/`result!` with a synthesized error (e.g. a local `CocoaError`) when the coordinator returns with neither set, so a contract violation degrades to a caught error instead of a crash.
- **Severity:** Low

**Swept and re-verified correct, no findings:** content-version/fingerprint drift on self-rebroadcast, `healthPercent` recompute on battle-round turn/highlight advance, link-resolution in calculated values (`LinkController.calculate`/`GameController.calculatedValue`), `resetPlayers()`'s three-call-site interleaving race, the file-backed-module (Pdf/Photo/Space) sync triplication, and the join-code brute-force gap — all confirmed fixed and non-regressed in current source, several by reading today's own remediation commits (`da11b4a9`, `3b12c9f4`, `78b0e4d5`) end to end. No `@State`-shadows-a-passed-in-value bugs, no unchecked array indexing in dice/table/battle-order code, and no empty/error-eating `catch` blocks were found in the areas swept.

---

## 6. Security

_No findings._

Areas checked and confirmed clean: no hardcoded secrets/tokens/API keys (`Bearer`, `apiKey`, `secret`, `Authorization` all grepped with no hits); no debug-vs-release endpoint switching exists (there is no traditional backend — sync is CloudKit + a custom local-network protocol, not a dev/prod URL split); the local-network join protocol has bounds-checked header parsing (`GameProtocol.handleInput` guards `buffer.count < headerSize`) and the 4-digit join code has exponential-backoff connection-attempt throttling (`ConnectionAttemptThrottle.swift`) — no unauthenticated brute-force gap found; the 9 entitlements files' App Group (`group.de.andretrettin.MasterRPG`) and iCloud container (`iCloud.de.andretrettin.gamemaster`) identifiers are consistent across `Resources/*.entitlements`, `Sources/RPGShare/*.entitlements`, and `Sources/DiceRollerWidget/DiceRollerWidgetExtension.entitlements`; tvOS's `useCloudKit: false` hardcoding is intentional and consistently documented (`AppGroup.swift`, `SettingsView.swift`'s `#if !os(tvOS)` gate), not a live bug.

---

## 7. Performance

### 7.1 Whole-dictionary `@Observable` property causes systemic list over-rendering
- **Location:** `Modules/CoreRPG/ItemList/ItemDataModel.swift:28` (`public var itemData: [UUID: ModelType] = [:]`); subscript access via `itemSync(for:)`/`itemOrEmpty(for:)` in `Modules/CoreRPG/Controllable/ItemControllable.swift`; representative call sites in row/editor `body`s across CharacterRPG, PhotoRPG, `CoreRPG/LGViews`
- **What:** Swift's Observation framework tracks a dictionary-typed `@Observable` property at whole-property granularity, not per-key. Reading any single item id inside a view's `body` subscribes that view to every other item in the same module's dictionary.
- **Why:** Editing or syncing (including a remote CRDT merge) any one item re-invalidates and re-renders every other currently-visible row/editor for that module, even for completely unrelated items — a systemic over-render cost on list-heavy screens (Character sheets, Photo carousels).
- **Action:** Have hot row/editor call sites receive an already-resolved model reference from a parent that already observes the specific id, instead of re-resolving via the shared dictionary inside each row's own `body`.
- **Severity:** Medium

### 7.2 `FoundryArtifactDetector.detect()` parses the archive independently of the main import readers
- **Location:** `Modules/CoreRPG/Foundry/FoundryArtifactDetector.swift:35` (`detect(at:)`) vs. `FoundryVTTImportReader.swift`/`FoundrySystemPackageReader.swift`'s own decode path
- **What:** `detect()` is called earlier and separately (often with user interaction in between) to identify the artifact type before the main reader runs its own decode — the two never share a parse result.
- **Why:** A large Foundry system-package archive gets parsed twice end-to-end for one import operation; for the largest compendium packages this is measurable, avoidable CPU/IO work on a user-initiated import flow.
- **Action:** Add a URL+mtime-keyed cache spanning `detect()` and the main reader's `read(from:)` — only worth doing if profiling confirms this as an actual hot path; it's currently a bounded, one-time cost per import.
- **Severity:** Medium

### 7.3 `RPGJsonFile` allocates fresh `JSONDecoder`/`JSONEncoder` instead of the shared `JSONCoding` singletons
- **Location:** `Modules/CoreRPG/App/ExportedRPGData.swift:126` (`JSONDecoder()` in `init(configuration:)`), `:134` (`JSONEncoder()` in `fileWrapper(configuration:)`)
- **What:** Every other decode/encode hot path in the app (`GameNetworkModel`, `CRDT.swift`) was migrated to shared `JSONCoding.decoder`/`.encoder` singletons; this `FileDocument` conformance for the `.gmz` export/import file type still allocates its own each call.
- **Why:** Low-traffic (one open/save per export/import), so impact is minor — but it's the one remaining inconsistency with a pattern the rest of the codebase just finished standardizing on, and a silent drift point if `JSONCoding`'s configuration ever changes and this call site is missed.
- **Action:** Replace both with `JSONCoding.decoder`/`JSONCoding.encoder`.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 Shadow rendered invisible by clipShape/glass-effect ordering
- **Location:** `Modules/TableRPG/View/TableGenerationPanelView.swift:50-58`
- **What:** The panel's modifier chain is `.clipShape(.rect(cornerRadius: 28))` → `.glassBackgroundEffect(...)`/`.glassEffectAll(...)` → `.shadow(radius: 24)` (verified by direct read). `.shadow()` is applied after the view is already clipped to its own rect, so the shadow is clipped away at the same boundary it's meant to extend beyond.
- **Why:** The intended drop shadow around the generator panel never actually renders — a real, user-visible polish regression, not just a style nit.
- **Action:** Apply `.shadow()` before `.clipShape()`, or wrap the clipped/glass content in an outer container and shadow that container instead.
- **Severity:** Medium

### 8.2 Views split into computed properties instead of separate `View` structs
- **Location:** ~120 occurrences across the audited scope, including (non-exhaustive): `Modules/CoreRPG/ItemDetail/ItemDetailContentView.swift:66,90,125,136`; `ItemEditorBackgroundView.swift:48,55,78`; `ItemEditorForegroundView.swift:35,54`; `ItemFileImporterView.swift:23,33,46,71`; `Modules/CoreRPG/LGViews/ListRootContextMenu.swift:87-287` (11 properties); `GroupEditorView.swift:171,201,238`; `ItemHeaderEditorView.swift:84`; `ItemRowView.swift:77,98,108`; `ListRootView.swift:171`; `ListRowItemView.swift:89`; `HeaderContentScrollView.swift:87`; `HeaderFooterContentScrollView.swift:65,84`; `Modules/CoreRPG/Sheet/SheetContextMenuView.swift:43-147` (8 properties); `SheetEntryView.swift:172,205,226,247`; `SheetView.swift:75,124,140,187,201,252`; `Modules/CoreRPG/Editors/{AddTagsEditor,QuickLinkEditor,RemoveTagsEditor,ToggleEditor,ValuePickerEditor}.swift`; and similar computed-property sections in AdventureRPG, CharacterRPG, GameRPG, GeneratorRPG, MapRPG, PdfRPG, PhotoRPG, RolePlayGameKit, SpaceRPG, TableRPG, WeatherRPG view files, and `Sources/DiceRollerWidget/*.swift`.
- **What:** `var someSection: some View { ... }` computed properties are used pervasively to break up large view bodies, instead of separate `View` structs.
- **Why:** CLAUDE.md explicitly bans this pattern ("Do not break views up using computed properties; place them into new `View` structs instead."). Computed properties get no independent identity/diffing, are harder to preview/test in isolation, and this is the single most repeated style violation found in the sweep.
- **Action:** Extract each into a dedicated `View` struct taking only the data it needs as parameters, consistent with the already-correct pattern seen in files like `GameStatisticsDashboardView.swift`.
- **Severity:** Medium

### 8.3 List filter/sort recomputed on every body evaluation
- **Location:** `Modules/CoreRPG/LGViews/GameShareView.swift:83-89` (`playerReportStatuses`); `Modules/TableRPG/View/TableGenerationOccurrenceHeaderView.swift:138-141` (`visiblePlayers`); `Modules/TableRPG/View/TableGenerationSaveSendButton.swift:89-92` (`visiblePlayers`)
- **What:** Each is a computed property doing `.filter(\.show).map(...).sorted(...)` read directly from `body`, so the chain reruns every render rather than being cached or recomputed only when the underlying source changes.
- **Why:** Classic body-work-that-should-be-hoisted smell, duplicated identically in three places. Impact is currently low since player lists are small.
- **Action:** Hoist into a value cached on state/model, recomputed only via `onChange` of the underlying control list.
- **Severity:** Low

### 8.4 `AnyView` used for cross-module protocol/navigation type erasure
- **Location:** `Modules/CoreRPG/Controllable/ViewControllable.swift:58-102` (~16 occurrences across protocol requirements/default impls); `Modules/CoreRPG/Navigator/Core/NavigationDestination.swift:160-166`; `NavigationModifiers.swift:109-127`; `AnyNavigationDestination.swift:53-54`; `Modules/CoreRPG/Navigator/Protocols/NavigationViewProviding.swift:25,41-42,53-54`; `NavigationProvidedView.swift:65`; `Modules/CoreRPG/ItemList/EntryDataEditable.swift:42,145`; `Modules/CoreRPG/Sheet/SheetEntryView.swift:154,168`; `ItemDetailContentView.swift:68`; `Modules/CoreRPG/Route/InternalRoute.swift:41`; `Modules/CoreRPG/Model/ItemGeneration.swift:121`
- **What:** `AnyView` is the return type across the `ViewControllable` protocol (implemented separately by every feature module) and the Navigator's destination-mapping machinery.
- **Why:** CLAUDE.md flags `AnyView` "wherever avoidable," but here it's largely structural — these are `any`-existential protocol boundaries crossing dynamic framework/module boundaries where `some View` isn't expressible on a protocol requirement used as `any ViewControllable`/`any NavigationDestination`. Genuinely hard to remove without a broader architecture change.
- **Action:** Leave as-is unless the module-boundary architecture is revisited; if reduction is wanted, prioritize the smaller view-level sites (`SheetEntryView.swift:154,168`, `ItemDetailContentView.swift:68`) over the protocol requirements.
- **Severity:** Low

### 8.5 Misleading "eliminates AnyView overhead" comment
- **Location:** `Modules/CoreRPG/Controllable/ViewControllableViews.swift:6-26`
- **What:** The file's doc comment claims `FileImporterViewWrapper<Controller: ViewControllable>` "avoids AnyView type erasure"/"eliminates AnyView overhead," but its `body` returns `controller.fileImporterView(...)`, still typed `AnyView` per the `ViewControllable` protocol — the wrapper only avoids `any ViewControllable` existential dispatch, not the `AnyView` boxing itself.
- **Why:** Could lead a future contributor to believe this pattern fully avoids `AnyView` overhead when the underlying return type is still boxed; the "optimization" is also only applied to one of several `AnyView`-returning protocol methods.
- **Action:** Correct the comment to describe what's actually eliminated, or finish the wrapper pattern for the rest of the protocol's `AnyView`-returning methods.
- **Severity:** Low

### 8.6 Missing `Equatable` conformance on hot leaf row views
- **Location:** `Modules/CoreRPG/LGViews/NameItemNewRow.swift:5`; `DescriptionItemNewRow.swift:5`; `Modules/GameRPG/Statistics/View/GameStatisticsSessionRow.swift:5`; `Modules/RuleRPG/View/RuleSourceDisclosureView.swift:5`; `Modules/CharacterRPG/View/EntryListDiceRow.swift:7`
- **What:** These per-row views hold only plain value-type/UUID/String/snapshot-struct properties — easy `Equatable` candidates — yet don't conform, while sibling row views in the same folders (`ThumbnailPhotoRow`, `InlineRowViewer`, `ListRowItemView`, `SheetEntryView`) already do, including a documented custom `==` pattern in `ListRowItemView.swift:23-28`.
- **Why:** `NameItemNewRow`/`DescriptionItemNewRow` in particular render inside every list row across every module (via `ItemRowView`) — missing `Equatable` means SwiftUI can't skip re-diffing their subtree when unrelated sibling properties are re-passed unchanged.
- **Action:** Add `Equatable` conformance mirroring the existing pattern.
- **Severity:** Low

### 8.7 `ForEach` identity keyed on mutable, AI-streamed content
- **Location:** `Modules/GeneratorRPG/Root/CharacterGenView.swift:25`
- **What:** `ForEach(value.entries, id: \.self)`, where `value.entries` is `[CharacterEntryGenModel]`, a `@Generable` FoundationModels-streamed type with no stable id — identity is the row's own hashable content.
- **Why:** Project rule is that `ForEach` identity must never be derived from mutable content. This is a documented, deliberate tradeoff forced by the `@Generable` schema (a client-generated id would leak into what the model is asked to produce) — the in-file comment already acknowledges instability "once the AI-streamed list is edited or reordered." Could still cause row-identity churn/animation glitches if a streamed entry is edited in place.
- **Action:** If in-place editing becomes common, derive a stable synthetic key (e.g. an index-stable wrapper assigned once streaming stops) rather than raw content hashing. No easy fix given the `@Generable` constraint otherwise.
- **Severity:** Low

**Swept and confirmed clean, no findings:** `foregroundColor(`, `tabItem(`, old `NavigationView`, `showsIndicators: false`, `ScrollViewReader`, `ForEach` on `.indices`/`.offset`, unnecessary `Array(...enumerated())`, `fontWeight(`, `UIColor` in SwiftUI code, hardcoded `.font(.system(size:))`, force unwraps/`try!`/`as!`, non-`private` `@State`/`@FocusState`, and the 1-parameter `onChange()`/`.animation(_:)` forms — zero real hits across the ~394 files in scope. No `@State` was found shadowing a live parent-owned value passed through `init`.

---

## 9. Dead code / duplication / refactor

### 9.1 Files to delete outright
- `Modules/GeneratorRPG/Root/AdventureChatRootView.swift` (321 lines) — despite the name, contains no `View`; its 5 types (`AdventureChatBlockOrigin`, `AdventureChatBlockSnapshot`, `AdventureChatSeedBlock`, `AdventureSheetContextBuilder`, `AdventureChatPreviewData`) have zero references anywhere else (verified). See also §5's related-pattern note in §9.8. **Severity: High** (orphaned island, largest dead file found).
- `Modules/CoreRPG/Navigator/Protocols/NavigationViewProviding.swift` — vendored/leftover Navigator-library reference code (`NavigationViews`, `NavigationViewProviding`, `NavigationViewProvider`, `MockNavigationViewProvider`), zero references anywhere (verified); its naming overlaps confusingly with the real, actually-used `NavigationViewProvidingSentinel` in `NavigationProvidedDestination.swift:111`. **Severity: Medium.**
- `Modules/CoreRPG/ItemList/CacheItemListModel.swift:57-76` — `CacheItemList`, a `[UUID: CacheItemListModel]` keyed cache, superseded by every `FolderListController` owning its own single `CacheItemListModel()` directly. **Severity: Low.**
- `Modules/CoreRPG/Extensions/AnchorPreference.swift:5-12` — `AnchorKey<A>`, orphaned by an internal migration to `TaggedKey<Anchor<A>, Void>` (used instead by the file's only function). **Severity: Low.**
- `Modules/CoreRPG/PropertyWrappers/IgnoreEquatableHashable.swift:1-30` — `IgnoreEquatable`/`IgnoreHashable`, never adopted anywhere. **Severity: Low.**
- `Modules/CoreRPG/Links/QuickLinkConfig.swift:15-25` — `QuickLinkConfig`, unreferenced (its file-sibling `LinkEntryModel` is used and should stay). **Severity: Low.**
- `Modules/CoreRPG/Sheet/SheetRootModel.swift:17-20` — `SheetRowGeometryMatch`, never instantiated (leftover from an abandoned `matchedGeometryEffect` tracking feature; sibling `SheetRowGeometryID` is genuinely used and should stay). **Severity: Low.**
- `Modules/CoreRPG/Debug/Logging.swift:14-16` — `LogScreenCategory`, single-case enum, never referenced. **Severity: Low.**
- `Modules/CoreRPG/Menu/WindowKeyViewModifier.swift:11-17` — no-op `ViewModifier` stub (`body` ignores its own `key` property); never instantiated anywhere. **Severity: Low.**
- `Modules/RolePlayGameKit/Intent/RPGShortcutCatalog.swift:1-17` — `RPGShortcutCatalog.navigate` duplicates the shortcut `MasterRPGShortcuts.appShortcuts` already hand-writes inline; the catalog type itself is never referenced. **Severity: Low.**

### 9.2 Near-duplicate `toggleTextLink`/`validateLinks` mechanics across module `LinkController`s
- **Locations:** `Modules/PhotoRPG/Controller/LinkController.swift:16-65`, `Modules/SpaceRPG/Controller/LinkController.swift:16-60` (near-identical — differ in log-message module name and a couple of interpolation/parameter details, not byte-for-byte as an initial pass suggested, but sharing the same assembly logic almost line-for-line); `Modules/PdfRPG/Controller/LinkController.swift`, `Modules/DiceRPG/Controller/LinkController.swift`, `Modules/WeatherRPG/Controller/LinkController.swift` (65-80 lines each, same share/show/remove-action scaffolding with small per-module deltas).
- **What:** `LinkControllable` (`Modules/CoreRPG/Controllable/LinkControllable.swift:63`) declares `toggleTextLink` as a protocol requirement with no default implementation, unlike `repairLinks`/`collectLinks`, which do have defaults (lines 229, 330) — so every module reimplements the same mechanics by hand.
- **Why:** A bugfix to the share/show/remove assembly logic must be repeated in 5-6 places.
- **Action:** Add a default `LinkControllable` extension for `toggleTextLink` parameterized by a description-resolver closure, mirroring how `repairLinks`/`collectLinks` already get defaults; leave PdfRPG/DiceRPG's genuinely different branches (entry content, dice-roll command) as module overrides.
- **Action verified:** direct diff of the Photo/Space pair confirms real shared structure, corrected from an initial overclaim of literal byte-identity.
- **Severity:** Medium

### 9.3 Duplicated unguarded `print("url nil ")` across 5 `PreviewData.swift` files
- **Locations:** `Modules/MapRPG/Model/PreviewData.swift:50`, `Modules/GeneratorRPG/Model/PreviewData.swift:39`, `Modules/DiceRPG/Model/PreviewData.swift:51`, `Modules/CharacterRPG/Model/PreviewData.swift:45`, `Modules/AdventureRPG/Model/PreviewData.swift:48`
- **What:** Identical `print("url nil ")` guard-clause (same trailing-space typo) copy-pasted into 5 modules' preview-fixture loaders, none behind `#if DEBUG`.
- **Why:** Duplicated logic that will drift, and the print statement compiles into Release builds.
- **Action:** Move `.gmz` bundle-resource loading into one CoreRPG preview-fixture helper, and route the failure log through `Logger` instead of `print`.
- **Severity:** Low

### 9.4 Per-module `GameController`s hand-duplicate `GenericGameController` instead of building on it
- **Locations:** `Modules/CoreRPG/Controllable/GenericGameController.swift` (85 lines, the shared default) vs. `Modules/DiceRPG/Controller/GameController.swift` (614 lines), `Modules/CharacterRPG/Controller/GameController.swift` (528 lines), `Modules/SpaceRPG/Controller/GameController.swift` (350 lines), `Modules/MapRPG/Controller/GameController.swift` (430 lines) — compare `Modules/RuleRPG/Controller/GameController.swift` and `Modules/GeneratorRPG/Controller/GameController.swift`, both correctly reduced to an 8-line `typealias GameController = GenericGameController<...>`.
- **What:** Confirmed via direct line counts — four modules still carry a full, independently-maintained copy of the game-sync contract rather than the thin-override pattern the other two already use.
- **Why:** A fix or behavior change to the shared game-sync contract — including the version/fingerprint logic implicated in this app's own documented history of GM/player sync bugs — must be manually re-applied and verified against up to four separately-evolved copies, with no compiler check keeping them consistent.
- **Action:** Migrate Dice/Character/Space/Map's `GameController`s to thin overrides of `GenericGameController`, keeping only genuinely module-specific logic (e.g. Dice's roll-result handling) as overrides.
- **Severity:** Medium

### 9.5 `GameTableView.swift` duplicates `performRoomAction(_:)` and `staleGestureTimeout` between platform-specific structs
- **Location:** `Modules/GameRPG/Table3D/GameTableView.swift:93` (visionOS `struct GameTableView: View`) vs. `:635` (second, iOS/macOS `struct GameTableView: View`, same file) — `performRoomAction(_:)` byte-identical at `:133-135` and `:785-787`; `staleGestureTimeout` byte-identical at `:137` and `:789`.
- **What:** Both platform-specific struct bodies in the same file independently declare the identical cancel-then-replace task helper and the identical stale-gesture timeout constant.
- **Why:** A tuning change made to one platform's copy and not the other silently diverges behavior between visionOS and iOS/macOS.
- **Action:** Extract both into a small shared helper/value type used via composition from both platform structs.
- **Severity:** Low

### 9.6 `PdfRPG`/`SpaceRPG` `CacheController` thumbnail generation is near-duplicate
- **Location:** `Modules/PdfRPG/Controller/CacheController.swift:10-26` vs. `Modules/SpaceRPG/Controller/CacheController.swift:6-19` — near-identical `createThumbnail(for:item:)` bodies, differing only in the `thumbnailSize` constant and a `removeWhiteBackground` flag.
- **What:** `ImageCacheControllable`'s own doc comment asserts each module's `createThumbnail` body is "genuinely module-specific," which no longer holds for these two specifically.
- **Why:** Small, low-risk consolidation opportunity.
- **Action:** Add a default `ImageCacheControllable` implementation parameterized by `thumbnailSize`/`removeWhiteBackground`.
- **Severity:** Low

### 9.7 Oversized files (>500 lines) needing a split
- `Modules/GameRPG/Controller/MasterController.swift` (2,903 lines) — already organized into `extension` blocks (Control, Send Messages, `MasterNetworkStoreDelegate`, `MasterNetworkProxyControllerDelegate`), but a single 1,146-line extension (`:1382-2527`) mixes the full per-module message dispatcher (`handleAudio`/`handleDice`/`handleGame`/`handleMap`/`handlePdf`/`handlePhoto`/`handleTable`/`handleValue`/`handleWeather`/`handleSpace`) for 9+ unrelated modules. Split along the existing extension boundaries, then split the handler block one file per target module (`MasterController+MapMessages.swift` is the biggest win). **Severity: Medium.**
- `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift` (2,602 lines) — already has clean `MARK` boundaries (Indexes/folders, Rules, Assets, Document dispatch, Scene conversion, Dice/values, Shared helpers) but all live in one file. Split into one file per section. **Severity: Medium.**
- `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift` (2,494 lines) / `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift` (1,235 lines) — unlike the domain mapper, essentially no `MARK` dividers; manifest decode, per-collection decode, LevelDB-specific decode, legacy-database decode, folder/document decode, and resource loading are all interleaved as top-level methods. Add `MARK` dividers first, then extract once boundaries are visible. **Severity: Medium.**
- `Modules/GameRPG/Table3D/GameTableModel.swift` (1,200 lines), `Modules/CoreRPG/Sheet/SheetRootModel.swift` (1,067 lines), `Modules/GameRPG/Controller/PlayerController.swift` (984 lines) — all three already carry clean internal `MARK`/extension boundaries; same split-by-extension opportunity as `MasterController`. **Severity: Low.**
- `Modules/GameRPG/SharePlay/RPGSharePlayController.swift` (2,595 lines) — carries an explicit in-file comment noting this size was already evaluated and deliberately kept as one file with `MARK` dividers rather than split, given the cross-references a full split would need to untangle (references a prior audit round by name). **No new action — re-flagging would misrepresent a conscious, documented decision. Severity: Low/informational.**
- 28 additional files between 501-673 lines (e.g. `GameRootModel.swift`, `FoundryImportView.swift`, `RuleModel.swift`, `FoundryRuleModels.swift`, `MapOverlayGeometry.swift`, `EditControllable.swift`, `MapModel.swift`, `MapEditorModel.swift`, `DiceModel.swift`) were not individually reviewed for internal structure — likely candidates for the same triage in a follow-up pass. `Tests/CoreRPGSnapshotTests/CoreRPGGeneratedPreviewSnapshotTests.swift` (1,950 lines) and `Tests/GameRPGSnapshotTests/GameRPGGeneratedPreviewSnapshotTests.swift` (1,001 lines) are machine-generated by `Scripts/generate_snapshot_tests.rb` — not hand-maintained oversized files; restructure the generator, not the output. **Severity: Low.**

### 9.8 Implemented-but-unreachable features scaffolded and never wired to product UI
- `Modules/CoreRPG/Sheet/SheetModel.swift:233-283` — `SheetGenerationRequest`, `GeneratedSheetDraft`, `SheetGeneratedBatch`: three fully-implemented, `Sendable`/`Identifiable` models for an AI sheet-generation flow, unreferenced anywhere outside their own declarations.
- `Modules/GeneratorRPG/Model/TableGenModel.swift:1-42` — `TableGenModel`/`TableEntryGenModel`/`TableLinkGenModel`: a full `@Generable` guided-generation model tree for AI-generated random tables, unreferenced anywhere.
- `Sources/DiceRollerWidget/DiceRollerIntents.swift:61-73` — `ClearDiceHistoryIntent`: complete `perform()` implementation (clears last roll, reloads widget), but unlike its sibling `RollDiceIntent` (wired via `Button`/`ControlWidgetButton` in `DiceRollerWidgetView.swift:174` and `DiceRollerWidget.swift:99`), never attached to any control.
- `Modules/CoreRPG/Text/BlurText.swift:10-64` — `BlurText`/`BlurAttribute`/`BlurEffect`: a "critical hit!" combat-text effect; `BlurEffect: TextRenderer` is never actually applied (`BlurText.body` sets the `.customAttribute` but never calls `.textRenderer(BlurEffect())`, so the attribute is inert), and `BlurText` itself has no production call site (only the auto-generated snapshot-test file references it).
- `Modules/GeneratorRPG/BasicAI/Model/ChatMessage.swift:51-64` — `RequestResponsePair`: fully implemented, `Identifiable`, never referenced.
- **What / Why:** Five separate instances of the same shape — a feature (mostly AI-generation-adjacent) fully scaffolded at the model/intent layer, then never connected to a view or control. Together they suggest a broader half-built FoundationModels-based generation effort spanning CoreRPG/GeneratorRPG/DiceRollerWidget that was paused mid-integration, rather than five unrelated one-offs.
- **Action:** One product decision applied consistently — confirm which of these are still planned; wire each into its intended UI, or delete the scaffolding for anything abandoned, rather than resolving them as five independent cleanups.
- **Severity:** Medium

### 9.9 `ReviewCustomProperty.displayName` localization inconsistency across modules
- **Location:** `Modules/DiceRPG/Model/DiceModel.swift:488-498`, `Modules/AdventureRPG/Model/AdventureModel.swift`, `Modules/CharacterRPG/Model/ValueModel.swift:372-376`, `Modules/MapRPG/Model/MapModel.swift` (bare English string literals) vs. `Modules/WeatherRPG/Model/WeatherModel.swift:253-279`, `Modules/PhotoRPG/Model/PhotoModel.swift`, `Modules/RuleRPG/Model/RuleModel.swift`, `Modules/SpaceRPG/Model/SpaceModel.swift`, `Modules/TableRPG/Model/TableModel.swift` (correctly wrapped in `String(localized:bundle: .module)`).
- **What:** 4 modules pass raw English string literals to `ReviewCustomProperty(displayName:)`, while 5 correctly localize it.
- **Why:** `displayName` is shown in the on-device review/repair UI; the 4 non-localized modules show English text to non-English users there, inconsistent with the bundle-based localization CLAUDE.md mandates and used everywhere else.
- **Action:** Wrap the 4 modules' `displayName` string literals with `String(localized:bundle: .module)` to match the other 5.
- **Severity:** Medium

### 9.10 Naming / organization nits
- `Modules/CoreRPG/Editors/QuickLinkEditor.swift:39` — "... replace the occurences." → "occurrences" (localized, user-facing help text). **Low.**
- `Modules/MapRPG/Extension/` (singular) vs. `Modules/CoreRPG/Extensions/` (plural) — the only two modules with a dedicated extensions folder disagree on its name. Rename `MapRPG/Extension` → `Extensions`. **Low.**
- `Modules/RuleRPG/Controller/RuleEntryTree.swift:1-218` — `RuleEntryTree` is a stateless tree-projection algorithm (cycle detection + hierarchy building) over `RuleEntryModel`, reads as a derived Model-layer type, not a Controller per CLAUDE.md's folder convention. Consider moving to `Modules/RuleRPG/Model/`. **Low.**
- `Modules/CoreRPG/List/DetailSectionRow.swift:39-87` — `CompactSectionRowViewModifier` is unreferenced anywhere, and internally uses `embbed` (should be `embedded`) and `grouppedView` (should be `groupedView`). Delete if unneeded; fix the typos if kept. **Low.**

**Verified NOT an issue, no action needed:** per-module `FolderListController.swift`/`DetailFolderListView.swift` (all 12/11 are thin protocol-conformance wrappers over shared `CoreRPG` logic, not duplicated logic); `DataController` mapping boilerplate (shared machinery already lives in CoreRPG; per-module differences are inherent field-list differences, not copy-paste); image encode/thumbnail-cache/file-path construction (JPEG encoding funnels through one `AKImage.jpegData` helper with a named quality-tier enum; App Group/iCloud container ids each declared exactly once); `ItemController`/`DataController`/etc. naming is consistent across all 12 feature modules with no deviation.

### 9.11 `Id`-suffix casing convention violated at ~258 sites
- **Location (representative, confirmed via repo-wide word-boundary grep, excluding `Tests/`):** `Modules/CoreRPG/FileViews/ImportReviewModels.swift:86-87` (`selectedModuleID`, `selectedItemID`), `Modules/CoreRPG/Settings/ThemePreviewCard.swift:6` (`themeID`), `Modules/CoreRPG/AppModels/AppSettingsModel.swift:74,214` (`appThemeID`), `Modules/CoreRPG/TabNavigation/ZoomTransitionViewModifier.swift:11,30` (`sourceID`), `Modules/CoreRPG/Persistence/RpgSpotlightIndexerDelegate.swift:56,58` (`storeID`) — 258 total `var`/`let ...ID` declarations across the module tree.
- **What:** CLAUDE.md mandates `Id` casing (`itemId`, not `itemID`); the equivalent `Url`-suffix violation was fully fixed repo-wide as of today's changes (0 remaining), but the `Id` half of the same rule remains widely unaddressed.
- **Why:** Pure style/consistency, no functional impact — but every new occurrence compounds an already-large inconsistency, and mixed casing within the same file makes the convention harder to follow going forward.
- **Action:** Now that the lower-risk `Url` half is done, run a compiler-assisted rename over the plain-Swift-property subset first (no `CodingKeys`/Core Data attribute-name/wire-format entanglement), leaving Foundry-import or GameRPG-networking wire-format-adjacent properties for a separate, more careful pass.
- **Severity:** Low

### 9.12 Inline magic-constant `CGSize` beside a named sibling constant
- **Location:** `Modules/PhotoRPG/Controller/CacheController.swift:65` (`CGSize(width: 64, height: 64)` inline) vs. `:71` (`private static let thumbnailMaxPixelSize: CGFloat = 256`, correctly named/documented three lines away).
- **What:** A raw literal sits three lines from a properly named sibling constant in a file that otherwise follows the project's named-constant convention well.
- **Why:** Makes the 64pt target harder to find/change; small inconsistency.
- **Action:** Extract `private static let thumbnailTargetSize = CGSize(width: 64, height: 64)` next to `thumbnailMaxPixelSize`.
- **Severity:** Low

**Verified NOT an issue, no action needed:** App Group / iCloud container / retry-backoff constants — `appGroupString`/`cloudContainerIdentifier` each declared exactly once (`AppGroup.swift`); SharePlay's `defaultRetryDelays`/`cleanupRetryDelays` are already named constants, extracted from 3 previously hand-copied call sites in an earlier audit round. No `#if false` blocks and zero TODO/FIXME/HACK/XXX/`#warning` markers exist anywhere in the tree (confirmed via full-tree grep). No stale `*_OLD*`/`*Legacy*`/`*Deprecated*`/`*_v1*`/`*_v2*`-named files exist (an initial name-based grep hit was a false positive — "Folder" contains the substring "old").

---

## 10. Cross-cutting recommendations

1. **Give `LinkControllable.toggleTextLink` a default implementation** (ties §9.2), the same way `repairLinks`/`collectLinks` already have one — the protocol already demonstrates the right pattern for two of its three duplicated-logic requirements; finish the third.
2. **Standardize every module's `GameController` on `GenericGameController`** (ties §9.4, §3.2's underlying sync-correctness concerns) — two modules already prove the thin-override pattern works; the historical GM/player sync bug class this app has repeatedly hit is exactly the kind of divergence four independently-maintained copies invites.
3. **Split the repo's half-dozen largest files along their already-existing `MARK` boundaries** (ties §9.7, §3.2) — most of the work here is mechanical extraction, not redesign, since the internal organization is already in place; `RPGSharePlayController.swift` shows the team already knows how to document a deliberate exception when a split genuinely isn't worth the risk.
4. **Resolve the "AI generation scaffolded but never wired" pattern once, not five times** (ties §9.1's `AdventureChatRootView`, §9.8) — a single product conversation about which on-device generation features are still planned would let five separate cleanup decisions collapse into one.
5. **Finish the `Id`-suffix casing pass now that `Url` is done** (ties §9.11) — the codebase just proved out the process on the lower-risk half of the same rule.
6. **Consider a SwiftLint (or similar) custom rule for "no computed `View` properties"** (ties §8.2) — at ~120 occurrences, this is now the highest-volume single style violation in the tree, and a compiler-adjacent check would stop new instances from landing faster than manual review can catch them.

---

## 11. What was NOT audited

- Algorithmic correctness of RealityKit/Table3D rendering geometry, dice-roll RNG fairness, and Metal/shader-level code (none found in this repo beyond RealityKit usage) — out of scope per the audit skill's own charter.
- Xcode project/build settings and scheme configuration beyond the three clean builds actually run (MasterRPG/iOS+visionOS Simulator, MasterMac/macOS, MasterTV/tvOS Simulator) — target membership, code-signing configuration, and build-phase scripts were not reviewed.
- Third-party SPM dependency internals (`swift-syntax`, `swift-snapshot-testing`, `swift-custom-dump`, `xctest-dynamic-overlay`, `RPGTabletopGameContent`, vendored Navigator/NavigatorUI source) were treated as black boxes, except where a leftover vendored-reference file was found unused (§9.1).
- Test coverage / correctness. `Tests/` was excluded from the main sweep except where an oversized test file was noted purely for size (§9.7) or a machine-generated snapshot-test file was correctly excluded from the oversized-file findings.
- Localization wording/translation quality — only structural/consistency gaps were noted (missing `bundle: .module` wrapping in §9.9, one spelling typo in §9.10), not translation correctness.
- Performance profiling via Instruments — no `.trace` capture was run; all performance findings (§7, parts of §8) are static-analysis-only and should be confirmed against a real trace before prioritizing.
- CloudKit schema / Core Data model correctness beyond what's visible in source — entity migrations and CloudKit Dashboard configuration were not reviewed.
- `RPGShare` share-extension and `DiceRollerWidgetExtension` entitlement file contents beyond a source-level consistency skim (§6).
- Foundry VTT import correctness against real-world compendium files — only code-level parsing safety (force-unwraps, error handling) was assessed, not semantic correctness of the mapped output.
- The ten prior audit documents in `Docu/CODE_AUDIT_1.md`–`_10.md` and the topic-specific ones (`CODE_AUDIT_Game.md`, `_Import.md`, `_Link.md`, `_Search.md`, `_Sheet.md`, `_EditItem.md`, `_Battle_Round.md`) were not read in full as ground truth; findings in this report were independently re-derived from current source, with only targeted cross-checks against specific claims agents encountered while verifying nearby code.

---

## 12. Verification

No Critical findings were surfaced by any of the four independent investigation passes (concurrency/API modernity, dead code/duplication, bugs/security/performance, SwiftUI/UI) — consistent with this codebase's maturity after ten prior audit rounds. Verification therefore focused on the two High findings and a representative sample of Medium findings, all confirmed by direct reads in this session (not taken on the sub-agents' word):

- **§5.1** — open `Sources/MasterRPG/Menu/MenuCommandList.swift`, lines 1-49: confirm the `import` list has no `GeneratorRPG` and the `body` has no `GeneratorCommands(...)` call, versus all 11 sibling modules. Cross-check `Modules/GeneratorRPG/Menu/GeneratorCommands.swift`, lines 1-24: the type is complete and ready to use.
- **§9.1** (`AdventureChatRootView.swift`) — open `Modules/GeneratorRPG/Root/AdventureChatRootView.swift` (321 lines); grep the repo for `AdventureChatBlockOrigin`, `AdventureChatBlockSnapshot`, `AdventureChatSeedBlock`, `AdventureSheetContextBuilder`, `AdventureChatPreviewData` and confirm zero hits outside this file.
- **§9.1** (`NavigationViewProviding.swift`) — grep the repo for `NavigationViews`, `NavigationViewProviding`, `MockNavigationViewProvider` and confirm zero hits outside `Modules/CoreRPG/Navigator/Protocols/NavigationViewProviding.swift`.
- **§8.1** — open `Modules/TableRPG/View/TableGenerationPanelView.swift`, lines 50-58: confirm `.clipShape(.rect(cornerRadius: 28, style: .continuous))` at line 52 precedes `.shadow(radius: 24)` at line 58.
- **§9.2** — diff `Modules/PhotoRPG/Controller/LinkController.swift:16-65` against `Modules/SpaceRPG/Controller/LinkController.swift:16-60`: confirm near-identical structure with genuine small differences (an extra `removeActionSpacing` parameter, differing interpolation), not literal byte-identity.
- **§3.3** — open `Modules/DiceRPG/Controller/GameController.swift`, lines 585-600: confirm the in-file comment explicitly references a prior audit round (`CODE_AUDIT_Game §3.6`) explaining the `.detached` choice, meaning this is a residual gap in an already-reviewed decision.

If any finding doesn't reproduce when you visit the line, flag it and it'll be re-investigated.
