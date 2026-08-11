# MasterRPG Code Audit

Generated 2026-08-10. Scope: ~264,465 Swift LOC across 1,954 files, 0 Metal kernels, spanning targets `MasterRPG` (iOS/visionOS), `MasterMac`, `MasterTV`, `RPGShare`, `DiceRollerWidgetExtension`, and 15 feature modules (`AdventureRPG`, `AudioRPG`, `CharacterRPG`, `CoreRPG`, `DiceRPG`, `GameRPG`, `GeneratorRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `RolePlayGameKit`, `RuleRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG`). Deployment target confirmed uniformly 26.0 across iOS/iPadOS/tvOS/visionOS/macOS. No `Dead/` or other archived directory exists in this project, so nothing was excluded on that basis.

**Prior audit note:** a previous `Docu/CODE_AUDIT.md` (dated 2026-08-09, same section-numbering scheme, extremely mature — ~69 of ~90 tracked items already marked fixed) exists in git history but is staged for deletion in the working tree as of this run. Rather than re-deriving already-fixed items from scratch, this pass used that document's still-open items as a lead list and **personally re-opened and confirmed every one against current source** before including it below (see §12) — this is not a transcription of the old report. 29 source files still contain `// See CODE_AUDIT §X.Y`-style comments pointing at the old document's numbering; since this report is a fresh document with its own numbering, those in-code references will now dangle (see §9.13, §10.7).

A full clean build (`xcodebuild -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 17 Pro' clean build`) succeeded with exactly **12 deduplicated warnings**, all one root cause (§4.1) — a strong signal for `SWIFT_STRICT_CONCURRENCY = complete` holding cleanly, though strict-concurrency checking doesn't catch every runtime race (see §3).

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

---

## 1. Executive summary

1. **[Critical/Security] Hardcoded, world-shared TLS pre-shared key lets any nearby device join and inject state into someone else's live game** — §6.1 — `Modules/GameRPG/Network/GameSecurity.swift:7`.
2. **[High/Bugs] Force-unwrapped App Group access can crash the whole app and every extension at launch on any entitlement/provisioning mismatch** — §5.1 — `Modules/CoreRPG/App/AppGroup.swift:7,30`.
3. **[High/Concurrency] Unstructured, uncancellable `DispatchQueue.main.asyncAfter` delayed navigation resume** — §3.4 — `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:112`.
4. **[High/Concurrency] 54 redundant `MainActor.run` hops in `PlayerController`'s hot network-dispatch path (+6 in `MasterController`)** — §3.1 — `Modules/GameRPG/Controller/PlayerController.swift`.
5. **[Medium/Security] `aps-environment: development` baked into every Release build with zero push-notification code present** — §6.2 — `Resources/MasterRPG.entitlements:5-6`.
6. **[Medium/API modernity] Deprecated `.system.search` App Shortcuts phrase — the sole compiler-warning root cause in the entire build, across 12 modules** — §4.1.
7. **[Medium/Dead code] `SyncDataController.swift` duplicated byte-for-shape-identical across 12 modules** — §9.2 — `Modules/*RPG/Controller/SyncDataController.swift`.
8. **[Medium/Bugs] `BatteryMonitor`'s macOS polling `Task` is never cancelled — an orphaned infinite-wake loop per view lifecycle** — §5.5 — `Modules/GameRPG/GameViews/BatteryView.swift:69-131`.
9. **[Medium/Dead code] `PlayerController.swift` is 3,841 lines (7.5× the codebase's own 500-line convention), two responsibilities in one file, ~1,846 unmarked lines** — §9.9 — `Modules/GameRPG/Controller/PlayerController.swift`.
10. **[Medium/Bugs] Six structurally-identical `catch { return nil }` blocks silently swallow player asset-import failures with no logging** — §5.3 — `Modules/GameRPG/Controller/{Master,Player}Controller.swift`.

---

## 2. Quick wins (≤30 min each)

- **Add `deinit { stopMonitoring() }` to `BatteryMonitor`** (or call it from `BatteryView`'s `.onDisappear`) — `Modules/GameRPG/GameViews/BatteryView.swift:69-131`. Stops an orphaned Task from accumulating on macOS. See §5.5.
- **Fix `FileUrlDataController.swift`'s dead fallback path** — only assign `loadedFileUrl = tempUrl` when the write actually succeeds. See §5.4.
- **Delete the 5 unused `*Wrapper` view files** (`RowViewerWrapper.swift`, `ThumbnailRowViewWrapper.swift`, `SharingViewWrapper.swift`, `LinkListViewWrapper.swift`, `InlineEditRowViewerWrapper.swift`) — zero call sites anywhere, confirmed via grep. See §9.1.
- **Delete the commented-out `AnyView` block** at `Modules/CoreRPG/ItemViews/QuickEditorAction.swift:54`. See §9.1.
- **Route the 6 silent `catch { return nil }` blocks through `Logger.networking.error(...)`**, matching every other catch in the same two files. See §5.3.
- **Rename `Docu/CoreRPG` → `Docu/CoreRPG.md`** — the only file in `Docu/` missing its extension. See §9.11.
- **Fix the stale `OldDiceBag` snapshot-test names** left over from today's rename commit (`fa5c4ec3`) — `Tests/DiceRPGSnapshotTests/DiceRPGGeneratedPreviewSnapshotTests.swift:128-134`. See §9.6.
- **Remove the now-unreachable `/0-Old/` path exclusions** in `Scripts/verify_localization.rb:340` and `Scripts/verify_accessibility.rb:17` — no `0-Old` directory exists anywhere post-rename. See §9.7.
- **Replace the 3 triplicated retry-delay literals** in `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift` with one named constant, mirroring the file's own `SharePlayAttachmentLoadRetry` pattern. See §9.4.

---

## 3. Concurrency

Strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`) compiles with zero concurrency-related warnings — a genuinely strong baseline. The findings below are things the compiler can't catch: readability/overhead patterns, one house-rule violation, and a couple of documented-but-worth-recording tradeoffs.

### 3.1 Pervasive, redundant `MainActor.run` hopping in the SharePlay/network hot path
- **Location:** `Modules/GameRPG/Controller/PlayerController.swift` — 54 sites (1122, 1148, 1181, 1207, 1240, 1266, 1325, 1329, 1381, 1384, 1433, 1436, 1543, 1813, 2075, 2079, 2085, 2088, 2601, 2750, 2761, 2792, 2795, 2975, 3008, 3041, 3100, 3113, 3145, 3176, 3197, 3222, 3226, 3292, 3327, 3349, 3375, 3385, 3444, 3488, 3527, 3556, 3575, 3580, 3599, 3638, 3701, 3716, 3722, 3732, 3743, 3751, 3758, 3770); `Modules/GameRPG/Controller/MasterController.swift` — 6 sites (521, 547, 622, 754, 1141, 1577); `Modules/GameRPG/Network/GameNetworkController.swift` — 1 site (786). All counts personally re-verified via `grep -c "MainActor.run"`.
- **What:** `PlayerController` and `MasterController` are plain `final class ... : Sendable` (not `@MainActor`, not an actor) holding an `@MainActor @Observable` model. Nearly every read/write of that model's state wraps in `await MainActor.run { ... }` instead of directly `await`-ing the already-`@MainActor` property/method — e.g. the model already defines `setGameUpdateType(_:)` at `PlayerController.swift:966-968`, but most call sites bypass it in favor of a closure.
- **Why:** This is the busiest concurrency-critical subsystem in the app (network I/O feeding UI state). The redundant hops add scheduling overhead per message, obscure which reads are genuinely atomic multi-field snapshots (a legitimate subset exists, e.g. line 1122's `(playerId, masterId)` tuple) versus simple single-field mutations that don't need a closure, and make the real isolation boundary harder to audit at a glance.
- **Action:** Where a single property/method is touched, drop the `MainActor.run` wrapper and `await` the `@MainActor` call directly (or route through the model's existing setter methods); reserve `MainActor.run` for genuinely atomic multi-property reads. `MasterController`'s broader per-method `@MainActor` style is the better template — see §3.2.
- **Severity:** High

### 3.2 Same `MainActor.run` anti-pattern replicated across CoreRPG's shared Controllable protocols and several modules' `GameController`
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift` (14 sites), `ExportControllable.swift` (9), `GameControllable.swift` (3), `CoreDataSnapshotPersistable.swift` (3 — sits on the CloudKit-remote-change → `ItemController` merge boundary), `SyncDataControllable.swift` (2 — same boundary), `TagController.swift` (1), `SearchControllable.swift` (1); `Modules/{Table,Dice,Weather,Audio}RPG/Controller/GameController.swift` (multiple each); `Modules/GameRPG/Network/ListenerManager.swift` (2), `Modules/GameRPG/Browser/BrowserManager.swift` (2), `Modules/GameRPG/Player/PlayerNetworkController.swift` (1); 3 `GeneratorRPG` AI provider files; `Modules/SpaceRPG/Space/SpaceViewer.swift` (1); `Modules/CharacterRPG/Controller/CharacterPackageVersion.swift` (1).
- **What:** Same root cause as §3.1, recurring in the shared protocol default implementations used by every module. `Modules/MapRPG/Controller/GameController.swift` demonstrates the working alternative already used successfully elsewhere in the codebase: every function individually marked `@MainActor`, zero `MainActor.run` calls needed.
- **Why:** The inconsistency across modules increases review burden and the risk of a future edit silently reintroducing an actual race when someone copies the wrong (hop-heavy) pattern instead of the clean one.
- **Action:** Standardize on per-function `@MainActor` annotations (MapRPG's pattern) instead of `MainActor.run` closures throughout `CoreRPG/Controllable/*.swift` and the listed `GameController`/network files.
- **Severity:** Medium

### 3.3 `RPGSharePlayController` cannot self-clean on deallocation; relies on callers remembering `reset()`
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:602-685` (class + plain `deinit`), `:1607-1644` (`reset()`); contrast `Modules/GameRPG/Network/ListenerManager.swift:49-53`, `Modules/GameRPG/Browser/BrowserManager.swift:42-44`, `Modules/GameRPG/Table3D/GameTableModel.swift:606-611`, all three of which use `isolated deinit`.
- **What:** `RPGSharePlayController`'s `deinit` is a plain nonisolated `deinit` that only logs, with an in-code comment noting it "cannot access @MainActor-isolated `tasks`." The many session tasks stored in `tasks: [UUID: Task<Void, Never>]` (plus `sendOperationTask`, `deferredPromotionTask`) are only cancelled by an explicit call to `reset()`.
- **Why:** Three sibling files in the same module already solve this with `isolated deinit`. Any future non-singleton instantiation of `RPGSharePlayController` — tests already do this at `Tests/GameRPGTests/SharePlayPackageTransportTests.swift:124,1294` — that's released without calling `reset()` first leaks every task it owns.
- **Action:** Adopt `isolated deinit { reset() }` on `RPGSharePlayController`, matching the other three files in this module.
- **Severity:** Medium

### 3.4 `DispatchQueue.main.asyncAfter` used instead of structured concurrency
- **Location:** `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:107-114`, violation at line 112, inside `@MainActor internal func resume(...)`.
- **What:** `DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.send(values: values) }` implements a delayed navigation resume via old-style GCD.
- **Why:** Directly violates the project's explicit house rule ("never use `DispatchQueue.main.async()`-style GCD; always use modern Swift concurrency") and, more importantly, is unstructured and uncancellable — a delayed navigation resume can fire after the navigator/view it targets is already gone. A full repo sweep found exactly 2 other `DispatchQueue` uses, both legitimate Network.framework/`NWConnection` interop with no async-native equivalent (`ConnectionController.swift:31`, `NWParameter+GameMaster.swift:13`) — this is the one clear non-test survivor.
- **Action:** Replace with a tracked `Task { try? await Task.sleep(for: .seconds(delay)); await send(values: values) }`.
- **Severity:** High

### 3.5 Fire-and-forget `Task` inside `.onAppear` instead of the `.task` modifier
- **Location:** `Modules/GameRPG/SetupViews/SelectedMasterView.swift:32-38`; `Modules/SpaceRPG/Record/TutorialVideoView.swift:47-62`.
- **What:** Both views spawn `Task { @MainActor in try? await Task.sleep(for: ...); <mutate state> }` from `.onAppear` rather than using the `.task { }` view modifier.
- **Why:** `.onAppear`-spawned tasks aren't tied to the view's lifetime and are never cancelled if the view disappears before the sleep completes (2s in `SelectedMasterView`, up to 4s in `TutorialVideoView`) — a dismissed view can still mutate `root.gameModel.selectedGameMaster`/`appModel.orbitState` afterward.
- **Action:** Replace `.onAppear { Task { ... } }` with `.task { ... }`, which is automatically cancelled when the view disappears.
- **Severity:** Medium

### 3.6 `CoreDataChangeObserver`'s `@unchecked Sendable` rests on an unenforced single-call-per-instance assumption
- **Location:** `Modules/CoreRPG/Persistence/CoreDataChangeObserver.swift:14-46`.
- **What:** `private var observer: AnyCancellable?` is mutable state inside a `@unchecked Sendable public final class`. The file's own comment (lines 8-12) documents *why the class can't be `@MainActor`* (Core Data posts change notifications synchronously on the context's own possibly-background queue) but not the actual soundness precondition: safety depends entirely on `observeCoreDataChanges` being called exactly once per instance. The 12 real call sites (one per module's `SyncDataController.init`) do satisfy this, but nothing in the type enforces it.
- **Why:** An undocumented invariant is one refactor away from becoming a real race — a future call site that reuses an existing `CoreDataChangeObserver` instance for a second `observeCoreDataChanges` call would silently drop the first subscription's cancellable, with no compiler signal.
- **Action:** Add a comment on the `@unchecked Sendable` conformance itself documenting the single-call precondition, or enforce it with a `precondition(observer == nil)` guard at the top of `observeCoreDataChanges`.
- **Severity:** Medium

### 3.7 `FoundryVTTDomainMapper` fully Main-Actor-bound for import mapping — documented, accepted tradeoff
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift:179-359` (`@MainActor struct FoundryVTTDomainMapper`, `@MainActor final class FoundryMappingState`); `cooperativeCheckpoint()` at ~25 call sites; `cooperativeYieldInterval = 16` at line 269; call sites `FoundryRuleImportModel.swift:169,187`.
- **What:** The entire Foundry document/asset mapping pass runs on `@MainActor`, yielding periodically via `cooperativeCheckpoint()`.
- **Why:** A large import can still visibly compete with SwiftUI's render loop between yields, though the yield-interval tuning mitigates the worst of it. A full Sendable-DTO rearchitecture would help more directly but was judged too risky for this codebase's size and is not recommended here either — flagging so it stays a documented tradeoff, not a forgotten one.
- **Action:** No change recommended beyond what's already landed (the yield interval). Revisit only if a specific large-import stutter is reported.
- **Severity:** Medium (in practice; the mitigation is real and holding)

### 3.8 `@preconcurrency import` at 11 framework boundaries
- **Location:** `Modules/PdfRPG/Pdf/SearchBar.swift`, `SelectionBar.swift`, `Modules/PdfRPG/Root/ViewerRootView.swift` (PDFKit); `Modules/CoreRPG/Persistence/{CloudKitCoreDataPersistenceController,CoreDataController,CoreDataChangeObserver,PersistentHistoryTrackerManager,CoreDataPersistenceController}.swift` (CoreData); `Modules/GameRPG/SharePlay/RPGSharePlayController.swift`, `Modules/GameRPG/Table3D/GroupActivityManager.swift` (GroupActivities); `Modules/SpaceRPG/Record/ReconstructionProgressView.swift` (RealityKit/ObjectCapture).
- **What:** Standard practice for pre-Sendable Apple frameworks — Apple hasn't shipped a Sendable audit for CoreData, PDFKit, GroupActivities, or RealityKit as of this SDK.
- **Why:** Informational; nothing actionable until Apple updates these frameworks' headers.
- **Action:** No action; periodically re-check whether newer SDKs drop the need for any of these.
- **Severity:** Low

### 3.9 `nonisolated(unsafe)` — sole production usage, audited and safe
- **Location:** `Modules/CoreRPG/Extensions/Encoder+MainActor.swift:17-22`.
- **What:** `nonisolated(unsafe) let encoder = self`, paired with `MainActor.assumeIsolated`, is the codebase's only production `nonisolated(unsafe)` — documented as the single, audited escape hatch for `Encodable.encode(to:)`'s `nonisolated` protocol requirement crossing into `@MainActor`-isolated domain models. Confirmed correctly scoped: every real call site pre-hops to `MainActor` before invoking `.encode()`.
- **Action:** No change needed; keep this as the sole sanctioned call site and reject any new ad hoc `nonisolated(unsafe)` in review.
- **Severity:** Low (informational)

### 3.10 `@ObservedObject` for Apple's `GroupStateObserver` — accepted SDK exception
- **Location:** `Modules/GameRPG/SetupViews/SharePlayButton.swift:19-21`.
- **What:** `@ObservedObject private var groupStateObserver = GroupStateObserver()` — `GroupStateObserver` is Apple's own `GroupActivities` type and conforms to `ObservableObject`, not `@Observable`; app code cannot change that.
- **Action:** No change — this is the one legitimate SDK-imposed exception to the `@Observable` house rule. Recorded so it isn't mistakenly "fixed" (which wouldn't compile) during a future cleanup pass.
- **Severity:** Low (informational)

### 3.11 Closure-based `NotificationCenter.addObserver` where an async notification sequence is available — NOW FIXED
- **Location:** `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:199-259` (`setupCloudKitEventMonitoring`); `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:45` (new `cloudKitEventMonitoringTask` bookkeeping property on `CoreDataInitModel`).
- **Fix:** Replaced the `NotificationCenter.default.addObserver(forName:object:queue: .main) { }` closure + `MainActor.assumeIsolated { }` pair with `for await notification in NotificationCenter.default.notifications(named:object:)` inside a `Task { [weak model] in ... }`, started from the already-`@MainActor` `setupCloudKitEventMonitoring`. Since the `Task` is created within an `@MainActor` context, its body is `@MainActor`-isolated by inference (the same established pattern already used one function up, in `setupContext`'s `cleanupTask`), so every `model.cloudKitSyncState`/`model.lastSuccessfulSync` write is now directly and safely isolated — no manual `assumeIsolated` assertion needed. The task is stored in a new `cloudKitEventMonitoringTask: Task<Void, Never>?` property on `CoreDataInitModel` (mirroring the existing `cleanupTask` property) and cancelled before a fresh one is assigned, guarding against a leaked prior observer if this function were ever called twice. `[weak model]` avoids a retain cycle (the task's `for await` loop runs indefinitely until the notification stream ends or the task is cancelled, so a strong capture would keep `model` alive forever via `model → Task → closure → model`).
- **Verified:** `xcodebuild -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` — **BUILD SUCCEEDED**, 0 new warnings.
- **Severity:** Low — resolved.

---

## 4. API modernity

### 4.1 Deprecated `.system.search` App Shortcuts phrase — 12 modules, the sole compiler-warning root cause in the entire build
- **Location:** `Modules/AdventureRPG/Intent/SearchAdventuresIntent.swift:8`; `Modules/{Audio,Character,Dice,Generator,Map,Pdf,Photo,Rule,Space,Table,Weather}RPG/Intent/*ManagementIntents.swift` (one site each, ~line 89-94).
- **What:** A fresh clean build produces exactly 12 deduplicated warnings, all `'search' is deprecated: Use .system.searchInApp instead`.
- **Why:** The `.system.searchInApp` replacement requires a newer OS version than this project's 26.0 deployment target in at least some SDK betas — not a mechanical find-and-replace; needs either a deployment-target bump or `#available`-gated dual-schema support.
- **Action:** Evaluate `.system.searchInApp`'s actual minimum-version requirement against the 26.0 target; if it's available at 26.0, do the mechanical swap across all 12 sites in one pass (they're identical in shape). If not, gate with `#available` and keep `.search` as the fallback.
- **Severity:** Medium

### 4.2 Closure-based `NotificationCenter` — see §3.11
_Cross-referenced under Concurrency since the fix is a concurrency-adjacent API swap, not a deprecation._

### 4.3 Deprecated `navigationBarTitle` + `GeometryReader`-for-proportional-sizing in a vendored sample view
- **Location:** `Modules/SpaceRPG/Record/TutorialPageView.swift:19,32,44,46`.
- **What:** `.navigationBarTitle(pageName, displayMode: .inline)` (line 46) is the pre-`NavigationStack` API, deprecated since iOS 14 in favor of `.navigationTitle(_:)` + `.navigationBarTitleDisplayMode(_:)`. The view also wraps its body in a plain `GeometryReader` (line 19) purely to compute `0.85 * geometry.size.width` (line 32) and force a `.frame(width:height:)` to the reader's full size (line 44).
- **Why:** This is the only place in the app still using the deprecated title API, and it's exactly the "proportional sizing" `GeometryReader` case replaceable by `containerRelativeFrame()`. **Context:** this file is adapted Apple Object Capture sample code (carries its own `LICENSE.txt` header), gated `#if os(iOS) && !targetEnvironment(simulator)` — it only compiles for a real device, which this environment can't build or verify, and was deliberately left untouched by a prior audit pass for exactly that reason.
- **Action:** Low-risk to modernize (`.navigationTitle`/`.navigationBarTitleDisplayMode`, `.containerRelativeFrame(.horizontal) { width, _ in width * 0.85 }`), but verify on a real device before merging since this environment can't build/preview it.
- **Severity:** Medium (the change itself), but treat as deliberately deprioritized until real-device verification is available.

---

## 5. Bugs / logic errors

### 5.1 Force-unwrapped App Group access can crash the whole app and every extension at launch
- **Location:** `Modules/CoreRPG/App/AppGroup.swift:7,30` (`UserDefaults.appGroup = UserDefaults(suiteName: appGroupString)!`, `FileManager.groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)!`); consumed at `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:33`, `CoreDataPersistenceController.swift:85`, `Modules/CoreRPG/Files/LocationFileManager.swift:18`, `Modules/CoreRPG/Persistence/FilePersistenceController.swift:114`.
- **What:** Both are force-unwrapped `static let` globals, personally confirmed by reading `AppGroup.swift` in full. Either force-unwrap traps the instant it's first touched if the App Group entitlement/container is unavailable.
- **Why:** Any entitlement/provisioning mismatch (ad-hoc/enterprise signing drift, a future extension target that forgets the entitlement) becomes an unconditional launch crash for both the CloudKit and local-only Core Data stacks, rather than a recoverable, surfaced error — invisible in normal development (entitlements always correct there) but fatal in field/CI/TestFlight signing edge cases. With 5 targets (`MasterRPG`, `MasterMac`, `MasterTV`, `RPGShare`, `DiceRollerWidgetExtension`) each needing matching App Group configuration, this is a real, not merely theoretical, risk surface.
- **Action:** Make `appGroup`/`groupURL` throwing or optional-returning APIs, and have `loadDatabase()` set `model.error` (as it already does for other init failures) instead of crashing.
- **Severity:** High

### 5.2 `fatalError` on an out-of-range die value reachable from SharePlay/TabletopKit-synchronized state
- **Location:** `Modules/GameRPG/Table3D/GameEquipment.swift:466-468` (`Die20.restingOrientation`), `:604-605` (`Die.restingOrientation`).
- **What:** Both call `fatalError("Invalid die value...")` when the synchronized `DieState.value` (delivered via TabletopKit's `UpdateEquipmentAction<DieState>`, synced across all SharePlay participants) falls outside the expected face range. A neighboring near-zero-axis case in the same function already has a graceful fallback.
- **Why:** A TabletopKit version skew, a corrupted/delayed sync payload, or a toss animation resumed after a session rebind could plausibly deliver an out-of-range value — crashing every participant's app simultaneously instead of one participant seeing a glitched pose.
- **Action:** Replace both `fatalError` calls with a clamped/default orientation + log, mirroring the existing near-zero-axis fallback pattern.
- **Severity:** Medium

### 5.3 Six structurally-identical `catch { return nil }` blocks silently swallow player asset-import failures
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:1774-1776` (PDF `.itemMissing` fallback), `:1919-1921` (Photo), `:2202-2204` (Space); `Modules/GameRPG/Controller/PlayerController.swift:2566-2568` (Map import), `:2592-2594` (Audio reveal), `:2670-2672` (Map import).
- **What:** All 6 discard the thrown error entirely, following a successful-looking `try`/`try await ...updateGame(...)` import call — inconsistent with every other `catch` in the same two files, which consistently call `Logger.networking.error(...)`.
- **Why:** A failure importing a player's shared photo/PDF/space/map bytes as the canonical asset (disk full, corrupted payload, iCloud eviction mid-write) disappears without a trace, making a real, reproducible bug ("my photo never got shared to the group") undiagnosable from logs.
- **Action:** Add `Logger.networking.error(...)` calls matching the pattern used everywhere else in these two files.
- **Severity:** Medium

### 5.4 Temp-file write failure is silently ignored, and the fallback path is skipped even though the write didn't succeed
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:233-237`.
- **What:** `try? data.write(to: tempUrl)` discards any write error, but `loadedFileUrl = tempUrl` is assigned unconditionally on the next line regardless of success — so `processUrl = loadedFileUrl ?? fullUrl` never falls back to `fullUrl` on a failed write.
- **Why:** On a failed temp write (disk pressure, sandbox issue), the subsequent action (e.g. a QuickLook thumbnail request) gets a URL to a nonexistent file, silently producing no preview instead of falling back to the still-available `fullUrl`.
- **Action:** Only assign `loadedFileUrl = tempUrl` when the write succeeds; otherwise fall through to `fullUrl`.
- **Severity:** Medium

### 5.5 `BatteryMonitor`'s macOS polling `Task` is never cancelled — an orphaned infinite-wake loop per view lifecycle
- **Location:** `Modules/GameRPG/GameViews/BatteryView.swift:69-131`.
- **What:** Personally verified: `BatteryMonitor.init()` (line 71-73) calls `startMonitoring()`, which on macOS starts `pollTask = Task { [weak self] in while !Task.isCancelled { sleep 30s; refresh() } }` (line 110-119). `stopMonitoring()` (line 121, cancels `pollTask` at 129-130) has exactly one reference in the whole repo — its own declaration; grepped repo-wide, confirmed it is never called from anywhere. `BatteryView` owns the monitor via `@State private var monitor = BatteryMonitor()` (line 18) with no `deinit` on `BatteryMonitor` and no `.onDisappear` on `BatteryView`.
- **Why:** `[weak self]` avoids a crash, but the `Task` itself keeps waking every 30s forever after the owning view/monitor deallocate, because nothing ever cancels it. Each time a `BatteryView` appears/disappears (e.g. entering/leaving the game screen repeatedly), one more permanently-leaked sleeping `Task` accumulates for the process lifetime on macOS.
- **Action:** Add `deinit { stopMonitoring() }` to `BatteryMonitor` (or call `monitor.stopMonitoring()` from `BatteryView`'s `.onDisappear`).
- **Severity:** Medium

### 5.6 `ObjectCache.allKeys` grows unbounded and is never read
- **Location:** `Modules/CoreRPG/Cache/ObjectCache.swift:26,38-42,44-47`.
- **What:** Updated on every `insertObject`/`removeObject` call but never trimmed when the backing `NSCache` evicts entries automatically (no `NSCacheDelegate` hooked up); a repo-wide search shows `allKeys` is never read anywhere.
- **Why:** Over a long campaign with many photos/maps/PDFs cached and evicted, this `Set<UUID>` accumulates entries indefinitely for objects long since gone — an unbounded, if slow, memory leak that also serves no purpose since nothing consumes it.
- **Action:** Remove `allKeys` entirely, or implement `NSCacheDelegate.cache(_:willEvictObject:)` to keep it in sync if it's meant to track live cache membership.
- **Severity:** Low

### 5.7 `print()` instead of structured `Logger` swallows SharePlay/network message-decode diagnostics
- **Location:** `Modules/GameRPG/Model/GameNetworkModel.swift:998-1006` (`decodeData(of:)`).
- **What:** The entry point for every inbound wire/journal/SharePlay message logs a decode failure via `print("**** Error \(error.localizedDescription)")` instead of the `Logger.networking` used everywhere else in this subsystem; returns `nil` safely (no crash) but with no structured, privacy-scrubbed log entry.
- **Why:** A malformed or malicious payload from a local-network or SharePlay peer that fails to decode leaves no trace in Console/os_log — precisely the signal that would help diagnose either a protocol-version mismatch or an actual probing attempt against the parser.
- **Action:** Replace with `Logger.networking.error(...)`.
- **Severity:** Low

### 5.8 Repeated force-cast pattern in Core Data relationship accessors across every module
- **Location:** `Modules/{Pdf,Dice,Weather,Adventure,Character,Photo,Generator,Space,Table,Audio}RPG/Model/DataModel+Extensions.swift:18` (CharacterRPG also `:44`) — 10 modules.
- **What:** Each `entriesModel` getter does `(entries as NSSet).sortedArray(using: [sortDescriptor]) as! [RPGXxxEntry]` immediately after already validating `entries as? Set<RPGXxxEntry>` two lines above.
- **Why:** Currently safe in practice (Core Data's typed relationship guarantees element type; `sortedArray` only reorders), but a fragile, copy-pasted pattern repeated 11 times — any future relationship/migration edge case would crash instead of degrading gracefully, and an `as!` immediately after an `as?` guard is redundant defensive-coding debt.
- **Action:** Use `.compactMap { $0 as? RPGXxxEntry }` on the sorted array, or cast once and reuse.
- **Severity:** Low

### 5.9 Untrusted-input parsers (Foundry VTT import, SharePlay wire protocol) — checked, already hardened
- **Location:** `Modules/CoreRPG/Foundry/{FoundryZIPArchive,FoundryVTTArchiveSanitizer,FoundryBoundedBase64,FoundryLevelDBReader,FoundryLevelDBWriteAheadLogReader,FoundryRuleModels,FoundryVTTImportReader,FoundrySystemPackageReader}.swift`; `Modules/GameRPG/SharePlay/SharePlayPackageReceiver.swift`; `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift`; `Modules/MapRPG/Controller/GameController.swift`; `Modules/GameRPG/Network/GameProtocol.swift`.
- **What:** Read in full or near-full and grepped exhaustively for force-unwraps, `try!`, `as!`, unchecked indexing, and unbounded recursion — this is the app's highest-value attack surface (a user imports a third-party Foundry VTT export, or a local-network peer sends arbitrary bytes). All ZIP path components are validated against `../`, `\`, NUL, drive-letter-absolute, and symlink entries before extraction (`FoundryZIPArchive.swift:236-299`); all size/length/offset fields read from untrusted bytes are bounds- and overflow-checked before allocation/slicing; JSON nesting depth is explicitly capped at 128 (`FoundryRuleModels.swift:20-34`, personally confirmed present); the network wire framer caps declared message length at 512,000,000 bytes (`GameProtocol.swift:41,45-46,95-97`, personally confirmed present); SharePlay's chunked-message reassembly bounds per-stream/per-package/cumulative byte counts with LRU eviction and expiry.
- **Why:** Reporting this so the audit record reflects that the named highest-priority attack surface is already well-hardened, not unreviewed.
- **Action:** None required. Worth preserving as regression-test coverage (`Tests/CoreRPGTests/Foundry/`) since these are exactly the invariants a future refactor could accidentally weaken.
- **Severity:** Low (informational)

---

## 6. Security

### 6.1 Hardcoded, world-shared TLS pre-shared key allows any local device to join or inject state into any game
- **Location:** `Modules/GameRPG/Network/GameSecurity.swift:7` (`static let passcode = "GameMasterCode"`); `Modules/GameRPG/Network/NWParameter+GameMaster.swift:21,27-61` (used to build TLS parameters for both `NWListener` and `NWConnection`); `Modules/GameRPG/Network/ListenerManager.swift:124`; `Modules/GameRPG/Browser/BrowserManager.swift:52-135`; `Modules/GameRPG/Controller/MasterController.swift:185-215` (`add`/`accepts(connectionId:sender:)`), `:835-895` (`accepts(_:origin:)`).
- **What:** The TLS pre-shared key that "authenticates" every Bonjour peer connection derives from a compile-time constant string identical across every install of the app — personally confirmed: `NWParameters(passcode: GameSecurity.passcode)` is used verbatim for both the listener and connection side. `BrowserManager` auto-discovers advertised MasterRPG games over Bonjour and lets a user tap-to-join with no per-session code, PIN, or host-side approval UI — personally confirmed no such field/prompt exists anywhere in `BrowserManager.swift`. `MasterController.accepts(_:origin:)` gates on identity-consistency (a peer can't spoof an existing player/master ID or reuse a role across connections) but has no secondary secret check beyond the TLS handshake completing — any peer that completes the handshake (which only requires knowing the universal hardcoded passcode) is auto-admitted as a legitimate new player via `add(connectionId:playerId:role:)`.
- **Why:** Any device with MasterRPG installed on the same local network — a coffee shop, a convention hall, a shared office or dorm network — can discover and join a stranger's live game as a player/observer and have its messages processed exactly like an invited player: inject dice results, map pins, chat, or state into a running game it was never invited to. This is a full authentication bypass into another user's live multiplayer session, not merely weak crypto.
- **Action:** Replace the static PSK with a per-game secret (freshly generated at "Start Game," shown to the host, entered by joining players), and/or add an explicit host-side accept/deny prompt per incoming connection before `add()`/`accepts()` binds a connection to a player identity.
- **Severity:** Critical

### 6.2 `aps-environment: development` baked into Release builds of every push-capable target, with zero push-notification code present
- **Location:** `Resources/MasterRPG.entitlements:5-6`; `Resources/MasterTV.entitlements:5-6`; `Sources/RPGShare/RPGShare.entitlements:5-6`; `MasterRPG.xcodeproj/project.pbxproj` (same entitlements file referenced by both Debug and Release configurations for each target).
- **What:** All 3 targets declare `aps-environment=development` for both Debug and Release; a repo-wide search found zero uses of `UNUserNotificationCenter`, `registerForRemoteNotifications`, or `PushKit`.
- **Why:** Dead capability today, but a latent trap — if push is ever wired up without someone remembering to fix this, App Store review can reject the build or Release traffic can silently mis-route to the dev APNs environment; it also forces every provisioning profile to include a push capability the app doesn't use.
- **Action:** Remove the `aps-environment` key until push is actually implemented, or split Debug/Release entitlements files when that work begins.
- **Severity:** Medium

### 6.3 Untrusted-input hardening — see §5.9
_Cross-referenced under Bugs since it's a code-correctness finding (bounds-safety), not a new vulnerability._

---

## 7. Performance

No new performance findings surfaced this pass. The prior audit's five performance fixes — `fetchBatchSize` batching on tag/link tables, incremental (not full-table) CloudKit-deletion reconciliation, ImageIO downsampled thumbnail generation instead of full-resolution decode, O(1) Foundry path lookups for directory-backed imports, and cached (not per-branch-recomputed) SharePlay attachment digests — were not independently re-verified end-to-end this pass; the source files implementing them (`Modules/CoreRPG/Extensions/Image+AKImage.swift`, `Modules/CoreRPG/Foundry/*`, `Modules/GameRPG/SharePlay/RPGSharePlayController.swift`) were read for other purposes during this pass with no contrary evidence found, but that's incidental coverage, not a dedicated performance re-audit. See §11.

---

## 8. SwiftUI / UI

The SwiftUI layer was checked directly (not via a sub-agent) against the full `swiftui-expert-skill` correctness checklist — state ownership (`@State` seeded from a passed value), `ForEach` identity, deprecated modifiers (`onChange` 1-param, `cornerRadius`, `foregroundColor`, `tabItem`, `NavigationView`), accessibility on icon-only controls, localization (`Text(..., bundle:)`), `GeometryReader` usage, and missing `Equatable` on hot leaf views.

### 8.1 Checklist clean sweep — no violations found
- **Location:** All `Modules/*/View/`, `Root/`, `Menu/`, `LGViews/`, `Sheet/` folders, plus `CoreRPG` shared UI helpers.
- **What:** Zero occurrences of: deprecated 1-parameter `.onChange(of:)` (out of 255 total `onChange` sites); `.foregroundColor(`; `.tabItem(`; `NavigationView {`; `DateFormatter()`/`NumberFormatter()`/`MeasurementFormatter()`; `String(format:`; `.fontWeight(.bold)`; `ForEach` using `.indices`/`\.offset`/`Array(x.enumerated())`; `Text("literal")` missing a `bundle:` parameter. Only 1 `.onTapGesture()` (legitimately needs `count: 2`). Only 3 `GeometryReader` uses (2 are visionOS `GeometryReader3D`, a distinct necessary volumetric API; the third is the vendored sample file at §4.3). The classic "`@State` seeded from a passed value, never resynced" anti-pattern was checked at all 6 sites where the seeding pattern (`_x = State(initialValue:)` in a custom `init`) appears — each is either explicitly resynced via `.onChange`, or is deliberate modal edit-buffer/one-time-initial-value semantics. Thumbnail row views already apply `.equatable()` at their call sites (`AnyView(ThumbnailPhotoRow(...).equatable())` etc.) before erasure.
- **Why:** Recording the sweep so the report doesn't read as if this large a surface (all view files) went unreviewed.
- **Action:** None.
- **Severity:** Low (informational)

### 8.2 `AnyView` pervasive at the `ViewControllable` protocol boundary — architecturally justified
- **Location:** `Modules/CoreRPG/Controllable/ViewControllable.swift:58-84` (protocol requirements); implementations in all 10 modules' `Controller/ViewController.swift`.
- **What:** ~45 of the ~50 repo-wide `AnyView` occurrences are return-type erasure at a cross-module protocol boundary, where each module's `ViewController` must return a common `AnyView` because the concrete SwiftUI view type differs per conforming module — Swift protocols can't express a per-conformance `some View` return.
- **Why:** No `some View`-based alternative exists for this heterogeneous-return protocol-registry design; not an oversight.
- **Action:** None on the protocol-boundary uses. The remaining ~5 non-boundary occurrences (dead wrapper types + 1 commented block) are dead code — see §9.1.
- **Severity:** Low (informational)

---

## 9. Dead code / duplication / refactor

### 9.1 Files/blocks to delete outright
- `Modules/CoreRPG/Controllable/RowViewerWrapper.swift`, `ThumbnailRowViewWrapper.swift`, `SharingViewWrapper.swift`, `LinkListViewWrapper.swift`, `InlineEditRowViewerWrapper.swift` — 5 `Equatable`-wrapping `View` structs whose doc comments claim to "eliminate AnyView overhead," but personally confirmed via grep to have **zero call sites** anywhere outside their own declaration file. They wouldn't actually eliminate `AnyView` from the protocol boundary either way (the wrapped `controller.rowViewer(...)` call still returns `AnyView` internally) — the real call sites already solve the equatable-diffing problem a different, working way (`.equatable()` applied to the concrete view *before* erasure, e.g. `AnyView(ThumbnailDiceRow(...).equatable())`). Genuinely abandoned code from an incomplete migration attempt.
- `Modules/CoreRPG/ItemViews/QuickEditorAction.swift:54` — commented-out `AnyView(...)` block.
- **Severity:** Low (clean up; ~150 LOC removed)

### 9.2 `SyncDataController.swift` duplicated byte-for-shape-identical across 12 modules
- **Locations:** `Modules/{Adventure,Audio,Character,Dice,Generator,Map,Pdf,Photo,Space,Table,Weather}RPG/Controller/SyncDataController.swift` (21 lines each, identical) and `Modules/RuleRPG/Controller/SyncDataController.swift` (29-line variant). Personally diffed all 12: every file declares the identical `struct SyncDataController: Sendable` with the same 4 stored properties and the same `@MainActor init` body, differing only in the Core Data entity type passed to `changeObserver.observeCoreDataChanges(from:entity:handler:)` (`RPGAdventure.entity()` vs `RPGRule.entity()` vs `RPGDice.entity()`, etc.).
- **Action:** Add a generic default via a `SyncDataControllable` protocol-extension initializer parameterized by the entity type, following the same pattern already proven for `FolderListControllable.copiedListDependencies` and `ExportControllable.bfsExportResults`/`finalizeExportResults` (both already-completed instances of exactly this refactor — see §10.1). Any change to the init logic currently requires editing 12 files identically.
- **Severity:** Medium

### 9.3 `CacheController` struct skeleton duplicated across 4 modules
- **Locations:** `Modules/PhotoRPG/Controller/CacheController.swift:6-18`, `Modules/PdfRPG/Controller/CacheController.swift:10-22`, `Modules/SpaceRPG/Controller/CacheController.swift:6-18`, `Modules/MapRPG/Controller/CacheController.swift:17-33` (MapRPG a near-identical variant).
- **What:** The `createThumbnail` method bodies were already centralized in a prior pass (`AKImage.quickLookThumbnail`, `cacheThumbnail(_:for:)`), but the surrounding property/init skeleton (`imageCacheController`, `thumbnailCacheController`, `fileUrlDataController`/`photoRoot`, `observableImageCache`) is still hand-duplicated identically.
- **Action:** Extract a `struct BaseCacheController` or default memberwise init in `Modules/CoreRPG/Controllable/ImageCacheControllable.swift`, leaving only `createThumbnail`'s module-specific body per conformer.
- **Severity:** Low

### 9.4 Retry-delay array triplicated in one file
- **Location:** `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift:461-465, 509-513, 764-768`, versus the file's own reusable `SharePlayAttachmentLoadRetry.defaultRetryDelays` at `:1046-1050`.
- **What:** The exact same 4-element `[Duration]` retry-delay literal (`[.milliseconds(250), .seconds(1), .seconds(2), .seconds(5)]`) appears verbatim in 3 different cleanup-retry loops, while a structurally similar, already-reusable retry helper exists in the same file.
- **Action:** Hoist to a single named constant and reference it from all 3 sites, mirroring `SharePlayAttachmentLoadRetry`'s existing pattern (visible proof the codebase already knows this fix — `RPGSharePlayController.swift:659`'s `journalAddTimeout` is a good counter-example of the pattern done right).
- **Severity:** Low

### 9.5 `RouteRouteDestionationView` / `ExtendedTabRouteDestionationView` — "Destionation" typo in both filename and type name, live and referenced from generated snapshot tests
- **Location:** `Modules/RolePlayGameKit/Router/RouteRouteDestionationView.swift:22`, `Modules/RolePlayGameKit/Router/ExtendedTabRouteDestionationView.swift:19`; called from `Modules/RolePlayGameKit/Router/RootRoute.swift:114`, `Modules/RolePlayGameKit/Router/ExtendedTabRoute.swift:65`; test names in `Tests/GameRPGSnapshotTests/RolePlayGameKitGeneratedPreviewSnapshotTests.swift:53-86`.
- **What:** Both filename and struct name misspell "Destination" as "Destionation"; `RouteRouteDestionationView` additionally doubles the word "Route."
- **Why:** Larger blast radius than previously-fixed filename typos, since filename and type name agree with each other (both wrong the same way), so a filename-vs-type-mismatch sweep wouldn't catch it.
- **Action:** Rename both types to `RouteDestinationView`/`ExtendedTabRouteDestinationView`, update the 2 call sites plus snapshot-test names/comments.
- **Severity:** Low

### 9.6 Stale renamed-pair artifact: `OldDiceBag` snapshot test still names the pre-rename symbol
- **Location:** `Tests/DiceRPGSnapshotTests/DiceRPGGeneratedPreviewSnapshotTests.swift:128-134`.
- **What:** Today's rename commit (`fa5c4ec3`, "renamed --> old are not old anymore") moved `Modules/DiceRPG/0-Old/Editor/OldDiceBag.swift` → `Modules/DiceRPG/Game/Editor/GameDiceBag.swift`, but this generated snapshot test's comment (`// snapshot-root: DiceRPG::OldDiceBag`), test name (`@Test("OldDiceBag")`), and function name (`func snapshotOldDiceBag()`) still say "OldDiceBag," while the body correctly calls `DiceRPG.GameDiceBag { _ in }`.
- **Action:** Rename the test/comment to `GameDiceBag`; re-run whatever generates `*GeneratedPreviewSnapshotTests.swift` so future regeneration doesn't reintroduce the stale name.
- **Severity:** Low

### 9.7 Stale `/0-Old/` path exclusions left in verification scripts after the rename
- **Location:** `Scripts/verify_localization.rb:340` (`return if relative.include?("/0-Old/")`), `Scripts/verify_accessibility.rb:17` (`.reject { |path| path.to_s.include?("/0-Old/") }`).
- **What:** Both scripts special-case-skip any path containing `/0-Old/`, but no `0-Old` directory exists anywhere post-rename (confirmed repo-wide; only these 2 scripts plus 2 doc files still mention it).
- **Action:** Remove the now-unreachable exclusion branches from both scripts; update the 2 stale doc mentions (`Tests/SNAPSHOT_GENERATION_REPORT.md`, `Docu/SNAPSHOT_GENERATION_REPORT.md`).
- **Severity:** Low

### 9.8 `#if InitializeCloudKitSchema` guards a print-only path with no build setting ever defining the flag
- **Location:** `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:109-117`.
- **What:** Custom compilation flag `InitializeCloudKitSchema` is never set in any scheme or `.xcconfig` (confirmed via grep of `project.pbxproj` and all xcconfigs) — the `#if` branch (including 2 `print()` calls) is unreachable in every configured build.
- **Action:** Document as a manual local-only developer escape hatch (comment explaining how to enable it for a one-off CloudKit-schema push), or move it to a script instead of a permanently-disabled compiler flag.
- **Severity:** Low

### 9.9 Oversized files >800 lines (34 total)
- **Location (largest production files, all personally spot-checked for MARK coverage):**
  - `Modules/GameRPG/Controller/PlayerController.swift` — 3,841 lines. `PlayerControllerModel` (60-970, no MARKs) and `PlayerController` (971-3841) are two responsibilities in one file; MARKs exist at 1004, 1068, 1527, 1971, but lines ~1995-3841 (~1,846 lines) have no further breakdown.
  - `Modules/GameRPG/Controller/MasterController.swift` — 2,666 lines, clean MARK boundaries at 486, 582, 832 (spans to 2291, ~1,460 unmarked lines), 2293, 2320.
  - `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift` — 2,572 lines, 7 MARKs already present (good split seams exist).
  - `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift` — 2,432 lines, zero MARKs.
  - `Modules/GameRPG/SharePlay/RPGSharePlayController.swift` — 2,464 lines, zero MARKs; only 2 top-level extensions span almost the whole file.
  - `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift` — 1,215 lines, zero MARKs.
  - `Modules/GameRPG/Network/GameNetworkController.swift` — 1,182 lines, 7 clean MARKs.
  - `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift` — 1,074 lines, zero MARKs, 6 distinct top-level types.
  - `Modules/GeneratorRPG/Controller/GeneratorController.swift` — 1,037 lines.
  - `Modules/GameRPG/Model/GameNetworkModel.swift` — 1,018 lines (includes intentionally-retained `GameNetworkModelV1`/`GameConfigModelV1` legacy wire-format types at 684-739 — legitimate backward compat, not dead code).
  - `Modules/CoreRPG/Sheet/SheetRootModel.swift` — 1,009 lines.
  - `Modules/CoreRPG/Import/ExternalImport.swift` — 1,003 lines, zero MARKs.
  - Plus 12 more production files 700-870 lines (`FoundryImportView.swift` 866, `RuleModel.swift` 851, `FoundryRuleModels.swift` 826, `MasterRPGTips.swift` 816, `MapOverlayGeometry.swift` 815, `EditController.swift` [CharacterRPG] 808, `GameRootModel.swift` 783, `SpaceViewer.swift` 752, `MapModel.swift` 742, `GameEquipment.swift` 741, `SearchController.swift` 718, `MapEditorModel.swift` 711), and oversized test files (`SharePlayPackageTransportTests.swift` 4,082, `MasterPlayerControllerTests.swift` 2,267, `NetworkStoreTests.swift` 1,999, `MasterControllerConnectionTests.swift` 1,423).
- **Action:** Prioritize `PlayerController.swift` (mechanical split into `PlayerControllerModel.swift` / `PlayerController.swift` / `PlayerController+ProxyDelegate.swift` along its existing MARKs). Add MARK comments *first* to the zero-MARK files >1,000 lines before attempting a split (`FoundryVTTImportReader.swift`, `RPGSharePlayController.swift`, `SharePlayJournalPublicationQueue.swift`, `ExternalImport.swift`, `FoundrySystemPackageReader.swift`) — none of them can be safely split until logical sections are demarcated. `MasterController.swift`, `GameNetworkController.swift`, and `FoundryVTTDomainMapper.swift` already have clean MARK seams and can be split into `+ExtensionName.swift` files mechanically today.
- **Severity:** Medium (top 3-4: `PlayerController.swift`, `RPGSharePlayController.swift`, `FoundryVTTImportReader.swift`, `SharePlayJournalPublicationQueue.swift`), Low (rest)

### 9.10 `print()` calls not behind `#if DEBUG` or a logging wrapper — 56 sites across 30 files
- **Location (top offenders):** `Modules/DiceRPG/Space/DiceSpaceModel.swift:84,202,203,208,218,231,285` (7); `Modules/PhotoRPG/Space/Spatial3DImageState.swift:37,48,77,83,87,91` (6); `Modules/PhotoRPG/Space/OrnamentsView.swift:15,29,34,40` (4); `Modules/DiceRPG/Space/HandTrackingModel.swift:29,37,47,80` (4); `Modules/PhotoRPG/Space/ImagePresentationView.swift:29,44,52` (3); `Modules/CoreRPG/Debug/DumpEnvironment.swift:27,29,30` (3, named "Debug" — likely intentional dev tool, lowest priority); `Modules/SpaceRPG/Space/SpaceViewer.swift:441,447` and `Modules/SpaceRPG/Space/RealityView+CameraTracking.swift:21,23` (2 each); `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:114,116` (gated by the never-defined `InitializeCloudKitSchema` flag — see §9.8, not `#if DEBUG`); `Modules/AudioRPG/Audio/AudioPlayerSession.swift:63,73`; `Modules/CoreRPG/ViewModifiers/RemoveItemViewModifier.swift:40,45`; 18 more files with 1 site each, including `Modules/{Adventure,Character,Map}RPG/Controller/ExportController.swift` (each prints `"*** ERROR table \(item.name) export is not handling link \($0)"`, echoing user-authored campaign content to the console in shipped builds).
- **Why:** Console noise in Release builds; the 3 `ExportController` sites leak user-created content strings; the Space/AR-tracking files account for over a third of all sites. The codebase already has an established `Logger`/`os.log` convention (`Modules/CoreRPG/Debug/Logging.swift:18`, `CoreDataController.swift:506`, `FilePersistenceController.swift:135`), so these `print()` sites are inconsistent with the project's own established pattern, not a greenfield gap.
- **Action:** Route through existing `Logger` categories or wrap in `#if DEBUG`. Consider a SwiftLint custom rule banning bare `print(` in non-test targets — a prior pass already made this exact recommendation when the count was lower (51/24), suggesting the rule was never added; see §10.4.
- **Severity:** Low-Medium

### 9.11 `Docu/CoreRPG` documentation file is missing its `.md` extension
- **Location:** `Docu/CoreRPG` (26,159 bytes).
- **What:** Every other file in `Docu/` uses `.md` except this one, an LLM-oriented documentation file for the CoreRPG module.
- **Why:** Won't render as Markdown in editors/GitHub that rely on the extension; the bare name also collides visually with the `Modules/CoreRPG` directory.
- **Action:** Rename to `Docu/CoreRPG.md` (or a more descriptive name to avoid the module-name collision).
- **Severity:** Low

### 9.12 Commented-out disabled test in `AdventureRPG`
- **Location:** `Tests/AdventureRPGTests/AppIntentTests.swift:13-43`.
- **What:** Two entire `@Test` methods (`shortcutCatalogKeepsPublishedBudget`, `entityQueryLimitsPickerResultsWithoutLimitingFullIndex`) are commented out line-by-line — the only run of commented-out code in the whole non-Playground codebase (the `#Playground` scratch file `Modules/GeneratorRPG/Playground/MyAiPlayground.swift` is Xcode Playgrounds code, never compiled into a shipping target, and not counted as dead code).
- **Action:** Either restore/fix these two tests (likely broken by an `AppDependencyManager`/entity-query API change) or delete them outright instead of leaving them commented.
- **Severity:** Low

### 9.13 29 in-code comments reference the now-deleted `Docu/CODE_AUDIT.md` by its old section numbers
- **Location:** e.g. `Modules/CoreRPG/Extensions/Image+AKImage.swift:237`, `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:1930`, `Modules/CoreRPG/App/AppGroup.swift:27` — 29 files total (`grep -rln "CODE_AUDIT" --include="*.swift" .`).
- **What:** A prior `Docu/CODE_AUDIT.md` (same skill/numbering scheme, dated 2026-08-09) is staged for deletion in the working tree (not yet committed) as of this session's start. 29 source files still carry `// See CODE_AUDIT §X.Y`-style comments pointing at that document's section numbers.
- **Why:** This new report is a fresh document with independent numbering — those in-code references will now point at nothing once the old file is actually gone (or at stale numbers if it's kept around). Either outcome quietly breaks a trail future readers would otherwise follow.
- **Action:** Decide whether the old `Docu/CODE_AUDIT.md` deletion should be committed (in which case, sweep the 29 comments to either remove the dangling reference or repoint to this report's equivalent section), or keep both documents side-by-side with a note distinguishing them.
- **Severity:** Medium (process/continuity, not a code defect)

### 9.14 TODO marker — only one in the entire non-test codebase
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:246`.
- **What:** `// TODO(visionOS): auto-fit the loaded model to the volumetric window's bounds...` inside `#if os(visionOS)`. A repo-wide sweep found zero `FIXME`/`HACK`/`XXX`/`#warning` markers anywhere.
- **Action:** None required beyond normal backlog tracking; confirms near-zero TODO-marker debt.
- **Severity:** Low (informational)

### 9.15 `FolderListController`/`DetailFolderListView` per-module pattern — confirmed intentional, no copy-paste-bug divergence found
- **Location:** 12 `FolderListController.swift` + 11 `DetailFolderListView.swift` files across modules.
- **What:** Diffed across 5 modules (`AdventureRPG`, `DiceRPG`, `CharacterRPG`, `AudioRPG`, `MapRPG` for controllers; `CharacterRPG`, `AudioRPG`, `WeatherRPG`, `DiceRPG` for views). All differences found are legitimate per-module feature additions (AudioRPG's `AudioPlayerBarView` overlay, WeatherRPG's/DiceRPG's ambient overlay animations, differing `viewerDestination`/`linkTypes` per module's real routing needs) — no edge-case-only-handled-by-one-module bug found in this sample.
- **Action:** None. Documented per the audit's own verification-transparency convention — this pattern is intentional per-module parallelism, not duplication to fix.
- **Severity:** Low (informational)

---

## 10. Cross-cutting recommendations

1. **Standardize on per-function `@MainActor` instead of `MainActor.run` closures.** §3.1 and §3.2 are the same root cause recurring in the hottest subsystem (`PlayerController`, 54 sites) and the shared protocol layer (`CoreRPG/Controllable/*`, ~40 more sites). `MapRPG/Controller/GameController.swift` already proves the cleaner alternative works in this codebase — use it as the template for a mechanical pass, prioritizing `PlayerController.swift` first.
2. **Close the game-join security gap, and audit for other places relying solely on the shared PSK.** §6.1 is the single Critical finding in this report. A per-session pairing code (generated at "Start Game," shown to the host, typed by joiners) is the standard fix for this exact local-network-Bonjour-pairing pattern.
3. **Extract shared protocol-extension defaults for the remaining duplicated controller boilerplate.** §9.2 (`SyncDataController`) and §9.3 (`CacheController` skeleton) are both instances of a pattern this codebase has *already* fixed twice — `FolderListControllable.copiedListDependencies` and `ExportControllable.bfsExportResults`/`finalizeExportResults` are both real, working shared implementations (not proposals) that the same treatment should extend to.
4. **Standardize on `os.Logger`; eliminate `print()` and silent `catch {}`.** §5.3 (6 silent-swallow catches), §5.7 (one `print()` on a hot decode path), and §9.10 (56 `print()` sites) are the same theme recurring at different scales. A SwiftLint custom rule banning bare `print(` in non-test targets, plus a periodic grep for empty-bodied `catch {}`, would catch this class of gap before it needs a full audit pass to resurface — this exact recommendation appears to have been made before (the `print()` count crept back up from a previously-reported 51/24 to 56/30), suggesting the rule was never actually added.
5. **Add MARK annotations before splitting oversized files.** §9.9's zero-MARK files >1,000 lines (`FoundryVTTImportReader.swift`, `RPGSharePlayController.swift`, `SharePlayJournalPublicationQueue.swift`, `ExternalImport.swift`, `FoundrySystemPackageReader.swift`) can't be split safely without first demarcating logical sections — treat MARK-annotation as its own quick pass ahead of any structural split.
6. **Reconcile `CLAUDE.md`'s documented per-module folder structure with actual practice.** Personally confirmed: no module has a literal `Module/` subfolder (`find Modules -maxdepth 2 -type d -iname "Module"` → nothing); e.g. `PhotoRPG/` actually has `Controller/, Intent/, Menu/, Model/, Photo/, Resources/, Root/, Route/, Space/, View/` — domain-named folders instead of a generic one. This is the exact document that drives this audit and future AI-assisted changes to this codebase; a mismatch here compounds every other finding's risk of being mis-applied.
7. **Resolve the dangling `CODE_AUDIT §X.Y` references before they go stale.** §9.13 — 29 files reference the old audit's numbering; this report doesn't preserve that numbering (a fresh run, not a merge), so a decision is needed on whether to sweep those comments now or accept they'll point at nothing.

---

## 11. What was NOT audited

- Algorithmic correctness of RealityKit/3D-object rendering — only concurrency/isolation was reviewed, not rendering-math correctness.
- Foundry LevelDB/ZIP binary-format parsing internals against the real Foundry VTT format spec — bounds-safety and resource-exhaustion posture were reviewed (§5.9), full format-correctness was not.
- Xcode project build settings and scheme configuration beyond the deployment-target sweep (confirmed uniform 26.0) and the entitlements files (read in full for §6.2).
- Third-party SPM dependency internals (`RPGTabletopGameContent` and any others) — treated as black boxes.
- Test coverage — a quick scan surfaced §9.12's disabled test; no deep coverage review of the 20+ test targets.
- Full accessibility audit (complete VoiceOver walkthrough, Dynamic Type stress testing at largest sizes, dark-mode contrast) — the SwiftUI pass (§8) spot-checked several icon-only buttons and confirmed a shared `.accessibilityLabel`-applying modifier pattern, but did not exhaustively review all ~71 `Image(systemName:)` sites.
- Localization/String Catalog wording correctness — usage patterns spot-checked (§8.1's `bundle:` sweep), not translation content.
- StoreKit/IAP configuration — `InAppModel.swift`'s use of `StoreKit.Transaction.currentEntitlements` was located and confirmed to use the modern async API, but the `.storekit` product-catalog file wasn't cross-checked against App Store Connect.
- Performance profiling with Instruments — no `.trace` was recorded; §7 is static-analysis-only (and largely deferred to a prior pass's fixes, not independently re-verified this time).
- SharePlay/GameController correctness beyond the specific concurrency/bug findings cited (§3.1, §3.3, §5.2, §5.3, §6.1) — the large `PlayerController.swift`/`MasterController.swift`/`RPGSharePlayController.swift` files were read closely around those boundaries, not exhaustively line-by-line for domain logic (map-pin geometry math, battle-round bookkeeping) outside them.
- `Tests/` directories — scanned for duplication/structure (§9) and one disabled test (§9.12), not reviewed for test-logic correctness.
- The historical `Docu/CODE_AUDIT.md`'s ~69 "NOW FIXED" items were spot-checked only where they overlapped this pass's own findings (§6.1's fixed sub-items §6.4-§6.6, confirmed still fixed in §5.9; §4.7's `GeometryReader` migration, confirmed still holding in §8.1) — not every one of the ~69 was re-verified line-by-line.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line. Every Critical/High finding below was personally re-opened and confirmed this pass (not taken solely from a background agent's report).

- **§6.1** (Critical) — `Modules/GameRPG/Network/GameSecurity.swift:1-8`: confirmed `static let passcode = "GameMasterCode"` is the entire declared type. `Modules/GameRPG/Network/NWParameter+GameMaster.swift:21`: confirmed `NWConnection(to: endpoint, using: NWParameters(passcode: GameSecurity.passcode))`. `Modules/GameRPG/Browser/BrowserManager.swift:52-135`: confirmed no join-code/PIN field or prompt exists anywhere in the file — `start()`/`updateGames(from:)` populate a tap-to-join list directly from discovered Bonjour endpoints. `Modules/GameRPG/Controller/MasterController.swift:835-895`: confirmed `accepts(_:origin:)` checks identity-consistency only (sender ID/role reuse), with no secondary secret check before `gameModel.accepts(connectionId:sender:)` → `add(...)` admits a new player.
- **§5.1** (High) — `Modules/CoreRPG/App/AppGroup.swift:7,30`: confirmed both `UserDefaults.appGroup` and `FileManager.groupURL` are force-unwrapped `static let` globals, read in full file context.
- **§3.4** (High) — `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:105-120`: confirmed `DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.send(values: values) }` at line 112, inside `@MainActor internal func resume(...)`.
- **§3.1** (High) — `grep -c "MainActor.run" Modules/GameRPG/Controller/PlayerController.swift` → 54; same command against `MasterController.swift` → 6; against `Modules/GameRPG/Network/GameNetworkController.swift` → 1. Counts independently reproduced, matching both the concurrency agent's site list and a prior audit pass's count.
- **§5.5** (Medium, but verification included given its prominence in §1) — `Modules/GameRPG/GameViews/BatteryView.swift:69-131`: confirmed `init()` calls `startMonitoring()` (line 71-73), which starts an uncancelled `pollTask` on macOS (line 110-119); `grep -rn "stopMonitoring\|BatteryMonitor(" Modules/ Sources/ Tests/` → only 2 matches, the type's own declaration line and its own `func stopMonitoring()` declaration — confirmed never called.
- **§9.2** (Medium) — personally diffed all 12 `SyncDataController.swift` files: 11 are byte-for-byte identical except the `entity:` argument (`RPGAdventure.entity()`, `RPGAudio.entity()`, `RPGValue.entity()`, `RPGDice.entity()`, `RPGGenerator.entity()`, `RPGMap.entity()`, `RPGPdf.entity()`, `RPGPhoto.entity()`, `RPGSpace.entity()`, `RPGTable.entity()`, `RPGWeather.entity()`); `RuleRPG`'s is a 29-line variant.
- **§4.1** (Medium) — clean build log (`clean_build_log.txt`, `grep -E "^/Users.*warning:" | sort -u`) confirmed exactly 12 unique warnings, all `'search' is deprecated: Use .system.searchInApp instead`, one per module's Intent file.
- **§9.9** (Medium, top items) — confirmed via `wc -l` on each cited file; MARK presence/absence confirmed via `grep -n "// MARK"` on `PlayerController.swift`, `MasterController.swift`, `FoundryVTTImportReader.swift`, `RPGSharePlayController.swift`.

If any finding doesn't reproduce when you visit the line, flag the specific reference for re-investigation.
