# MasterRPG Code Audit

Generated 2026-09-14. Scope: ~270,586 lines across 2,033 Swift files (no `.metal` kernels in this project) spanning targets **MasterRPG** (iOS/visionOS), **MasterMac**, **MasterTV**, **DiceRollerWidgetExtension**, and **RPGShare**, plus 14 shared framework modules (`AdventureRPG`, `AudioRPG`, `CharacterRPG`, `CoreRPG`, `DiceRPG`, `GameRPG`, `GeneratorRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `RolePlayGameKit`, `RuleRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG`). No directories were excluded as archived/dead — none exist in this repo.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made. This is the fourteenth documented audit pass on this codebase (see `Docu/CODE_AUDIT_1.md` through `_13.md` and module-specific audits) — most previously-identified issues in those documents are already fixed and are not re-litigated here; this pass independently re-derived findings by reading current code, and cross-references only where directly relevant.

**Headline result:** a full clean build of the `MasterRPG` scheme produced **zero Swift compiler warnings** (Swift 6.3, `SWIFT_STRICT_CONCURRENCY = complete`, no default actor isolation), and independent review across concurrency, dead-code/duplication, bugs/security/performance, and SwiftUI turned up **no Critical-severity findings**. The single highest-severity item is High (§9.1). This reflects a codebase that has already absorbed many audit cycles; the findings below are the genuine remainder.

---

## 1. Executive summary

1. **[High] Duplicated Foundry resource-resolution algorithm with a security-relevant classification gap** — §9.1 — `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:1088-1179` vs. `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:1897-1986`. The system-package copy's `isRemote` is missing the `data:`-URI check the world-import copy has, so a data-URI asset reference is misclassified during system-package imports.
2. **[High] Stale generation model silently edits/saves the wrong item** — §5.1 — `Modules/TableRPG/View/TableGenerationRootView.swift:6-17` + `Modules/CoreRPG/LGViews/ItemGenerationPresentationModifier.swift:21-31`. Switching the generation panel from one table directly to another (without the selection passing through `nil`) preserves the first table's `@State` model.
3. **[Medium] `.unsafelyUnwrapped` on always-should-be-set properties** — §5.2 — `Modules/GameRPG/Root/GameRootModel.swift:381-388`. Unlike `!`, this is undefined behavior (not a clean trap) in Release builds if a future refactor ever leaves the backing value `nil`.
4. **[Medium] Duplicated Foundry JSON-decoding, path-normalization, and asset-collection helpers** — §9.2-§9.4 — two independent copies across `FoundryVTTImportReader.swift` and `FoundrySystemPackageReader.swift`, already drifted (e.g. one allowlist includes `"m4v"`, the other doesn't).
5. **[Medium] Unbounded dice-roll history re-serialized on every roll inside the widget extension** — §7.1 — `Sources/DiceRollerWidget/DiceRollerView.swift:15,121,138-151`.
6. **[Medium] Unstable `@Entry` environment defaults regenerate identity on every read** — §8.1 — `Modules/PdfRPG/Model/PdfViewerActions.swift:18,32`, `Modules/CoreRPG/App/RouterActions.swift:12,26`. Defeats the exact-equality diffing these types exist for.
7. **[Medium] Non-private `@State` seeded from an init parameter in two navigation modifiers** — §8.2 — `Modules/CoreRPG/Navigator/Core/NavigationCheckpoint.swift:294,319`.
8. **[Medium] ~130 call sites still split view bodies into computed `some View` properties** instead of extracted `View` structs, the exact pattern CLAUDE.md bans — §8.3.
9. **[Medium] `RPGSharePlayController.swift` (2,635 lines) and the two Foundry importers (2,552 / 1,265 lines) remain unsplit** despite sibling files in the same modules already adopting a `+<Concern>.swift` extension-file convention — §9.7-§9.9.
10. **[Medium] Icon-only toolbar overflow menu has no accessible label** — §8.4 — `Modules/CoreRPG/LGViewModifiers/ToolbarItemListViewModifier.swift:102-104`.

---

## 2. Quick wins (≤30 min each)

- **Rename the typo'd public method** `gameGiceHeight` → `gameDiceHeight` — `Modules/DiceRPG/Controller/ViewController.swift:99` (+ 2 test call sites). §9.12.
- **Add an accessible label** to the `ellipsis.circle` overflow menu — `Modules/CoreRPG/LGViewModifiers/ToolbarItemListViewModifier.swift:102-104`. §8.4.
- **Delete the dead redundant `print`** inside a narrowed-type branch that's immediately re-printed unconditionally — `Modules/GeneratorRPG/Playground/MyAiPlayground.swift:25-33`. §9.15.
- **Delete the commented-out, already-explained-as-dead test block** — `Tests/AdventureRPGTests/AppIntentTests.swift:19-59`. §9.16.
- **Compose `DiceEntity`'s URL from the shared `URL.appScheme` constant** instead of the hardcoded literal `"RPG://DICE/0/..."` — `Modules/DiceRPG/Intent/DiceEntity.swift:101-103`. §9.13.
- **Route `FileUrlDataController.createFileUrl`'s iCloud download** through the existing `FileManager.download(coordinatingAccessAt:)` helper instead of an uncoordinated, error-swallowing direct call — `Modules/CoreRPG/Files/FileUrlDataController.swift:337-344`. §9.6.
- **Replace `preconditionFailure` with a graceful failure return** in `startNewCapture()`, matching the existing guarded pattern two lines above — `Modules/SpaceRPG/Record/AppDataModel.swift:239-254`. §5.4.
- **Move `MyAiPlayground.swift`'s `#Playground` blocks** out of the shipping `GeneratorRPG` module tree. §9.14.
- **Replace the remaining 7 ungated `print()` calls** with `Logger` (4 production files + 1 test file, 3 call sites). §5.5.

---

## 3. Concurrency

Verified: `project.pbxproj` sets `SWIFT_STRICT_CONCURRENCY = complete` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` project-wide, with **no** `SWIFT_DEFAULT_ACTOR_ISOLATION`/`-default-isolation` setting anywhere — confirming CLAUDE.md's claim that every `@Observable` class needs an explicit `@MainActor`.

### 3.1 `@Observable`/`@MainActor` coverage is fully compliant
- **Location:** all ~150 `@Observable` declarations under `Modules/` and `Sources/`
- **What:** A scripted check of every `@Observable` site and its surrounding context found zero classes missing `@MainActor`, across both attribute orderings used in the codebase.
- **Why:** This was expected to be the largest concurrency finding; the codebase is already fully compliant.
- **Action:** None required.
- **Severity:** Low

### 3.2 `GroupStateObserver` is the sole `@ObservedObject`/`ObservableObject` usage in the app
- **Location:** `Modules/GameRPG/SetupViews/SharePlayButton.swift:21-22`
- **What:** Uses `@ObservedObject private var groupStateObserver = GroupStateObserver()`.
- **Why:** `GroupStateObserver` is Apple's own `GroupActivities` type; it has no `@Observable`-based replacement in the current SDK, so this is a forced, single, documented exception rather than a drifting pattern.
- **Action:** Add a short comment noting this is an unavoidable SDK constraint; revisit if Apple ships an `@Observable` `GroupActivities` API.
- **Severity:** Low

### 3.3 Single `nonisolated(unsafe)` escape hatch for `Encodable` bridging
- **Location:** `Modules/CoreRPG/Extensions/Encoder+MainActor.swift:17-22`
- **What:** `Encoder.encodeOnMainActor(_:)` uses `nonisolated(unsafe) let encoder = self` with `MainActor.assumeIsolated` so a `nonisolated` `Encodable.encode(to:)` requirement can reach `@MainActor` model state.
- **Why:** `Encodable.encode(to:)` is a nonisolated protocol requirement and `Encoder` isn't `Sendable`, so some escape hatch is structurally required; this is a single, centralized instance, not one per model.
- **Action:** No change; audit any new `encode(to:)` caller to confirm it runs on the main actor first, since `assumeIsolated` traps at runtime rather than failing at compile time.
- **Severity:** Low

### 3.4 Raw `Network.framework` APIs require `DispatchQueue` plumbing
- **Location:** `Modules/GameRPG/Network/ListenerManager.swift:130,158`; `Modules/GameRPG/Network/ConnectionController.swift:31`
- **What:** Both instantiate a raw `DispatchQueue` because `NWListener`/`NWConnection` still require one for callbacks; every callback immediately re-enters the owning actor via `Task { await self.handle...(...) }`.
- **Why:** `Network.framework` has no async-native listener/connection API on the current SDK — this is not the banned `DispatchQueue.main.async`/`.global()`/`.sync` pattern; the boundary is already isolated correctly.
- **Action:** No change now; migrate if Apple ships an async-native `Network.framework` API.
- **Severity:** Low

### 3.5 `Task.detached` cancellation-forwarding checked and cleared
- **Location:** all 13 `Task.detached` call sites in `Modules/CoreRPG/Foundry/*.swift`, `Modules/RolePlayGameKit/Import/Foundry/*.swift`, `Modules/SpaceRPG/Record/AppDataModel.swift:310`, `Sources/RPGShare/ItemProviderImporter.swift:211`
- **What:** An initial pass flagged these as "not individually re-verified" for cancellation forwarding. Direct verification of all 13 sites found every awaited one already wraps `task.value` in `withTaskCancellationHandler { ... } onCancel: { task.cancel() }`; the one exception (`AppDataModel.swift:310`) is an intentionally fire-and-forget cleanup task that self-checks `Task.isCancelled` and is never awaited by its caller, so no wrapper is needed there.
- **Why:** Recorded here so a future re-scan doesn't re-flag this as a live issue.
- **Action:** None needed.
- **Severity:** Low

---

## 4. API modernity

### 4.1 No legacy-API usage found; confirmed by both static sweep and a warning-free build
- **Location:** n/a (repo-wide)
- **What:** None of `DateFormatter`/`NumberFormatter`/`MeasurementFormatter`, `String(format:`, `.replacingOccurrences(`, `DispatchQueue.main.async`, `UIScreen.main.bounds`, `cornerRadius(` (on a `View`), `foregroundColor(`, `.tabItem(`, single-parameter `.onChange(of:)`, `NavigationView`, `Task.sleep(nanoseconds:)`, or stale `@available(iOS X, *)` guards below the iOS 26 deployment target appear anywhere in `Modules/`, `Sources/`, or `Tests/`. A full clean build of the `MasterRPG` scheme (all iOS/visionOS module dependencies) produced **zero warnings** beyond two irrelevant `appintentsmetadataprocessor` tool notices.
- **Why:** Confirms the project's own banned-API list is enforced in practice, not just documented.
- **Action:** None needed.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Stale generation model persists across item switches (silent data-integrity bug)
- **Location:** `Modules/TableRPG/View/TableGenerationRootView.swift:6-17` (`_model = State(initialValue: controller.makeModel(itemId: itemId))` in `init`); `Modules/CoreRPG/LGViews/ItemGenerationPresentationModifier.swift:21-31` (`if let selection, let generator = root.generationControllable { generator.generationView(itemId: selection.itemId, ...) }` inside an `.overlay`)
- **What:** `TableGenerationRootView`'s `model` is a `@State` seeded once from `itemId` in `init`. The overlay that hosts it keeps the same structural position/branch whenever `selection` changes directly from one `WindowItemSelection` to another (i.e. presenting a second table's panel without the first passing through `nil`), so SwiftUI preserves the existing view identity and its `@State` storage.
- **Why:** If a second table's generation panel is presented while a first table's is already open, the pre-existing `TableGenerationModel` for the first table keeps being edited/saved even though the visible `itemId` now names the second table — a silent, non-crashing correctness bug that writes generated content to the wrong item.
- **Action:** Force new view identity per item (e.g. `.id(selection.itemId)` on the overlay content), or key the state off `.task(id:)`/`.onChange(of: itemId)` that rebuilds `model` via `controller.makeModel(itemId:)`, rather than relying solely on `init`.
- **Severity:** High

### 5.2 `.unsafelyUnwrapped` used for always-should-be-set stored properties
- **Location:** `Modules/GameRPG/Root/GameRootModel.swift:381-388`
- **What:** `viewController`/`logGameController` are non-optional computed properties that force-read a private optional backing store via `.unsafelyUnwrapped` instead of `!`.
- **Why:** Unlike `!`, `Optional.unsafelyUnwrapped` performs **no runtime check at all** in a Release (`-O`) build — reading it while `nil` is undefined behavior, not a diagnosable crash. Both backing properties are unconditionally assigned at the end of `init` today, so this isn't currently reachable, but it removes the safety net a future refactor (deferred/lazy construction, a new failable init path) would otherwise get.
- **Action:** Use `!` (or restructure as non-optional `let`s set via a two-phase init/factory) instead of `.unsafelyUnwrapped`.
- **Severity:** Medium

### 5.3 `FileUrlDataController.delete(_:)` can silently orphan on-disk bytes
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:387-408`
- **What:** For `.local`/`.appCloud`/`.newCloud`/`.url` locations, the delete task does `try? await FileManager.default.removeItem(...)` and then unconditionally removes the file bookmark regardless of whether removal actually succeeded.
- **Why:** Once the owning row is deleted and the bookmark is dropped, nothing else in the app retains a reference to that file; a removal failure (coordination timeout, permission error, transient iCloud state) leaves the binary permanently orphaned with no retry or cleanup pass — a slow storage leak over an install's lifetime.
- **Action:** Log the failure (as neighboring lines in the same file already do) and/or queue a retry, and only drop the bookmark after confirmed deletion.
- **Severity:** Low

### 5.4 `preconditionFailure` reachable if Object Capture is invoked off its gated entry point
- **Location:** `Modules/SpaceRPG/Record/AppDataModel.swift:239-254`
- **What:** `startNewCapture()` crashes the process outright (all build configurations) if `ObjectCaptureSession.isSupported` is `false` or constructing the session unexpectedly returns `nil`.
- **Why:** The only call site is gated by an `isSupported()` check in the UI today, so this isn't currently user-reachable, but `startNewCapture()` performs no re-check itself; a future entry point (Shortcuts/App Intent, or a capability-check race) would crash the whole app instead of failing the capture gracefully.
- **Action:** Replace both `preconditionFailure`s with a graceful failure return, matching the `guard let folderManager = CaptureFolderManager() else { return false }` pattern two lines above.
- **Severity:** Low

### 5.5 Leftover `print()` calls instead of `Logger`
- **Location:** `Modules/CoreRPG/LGViews/HeaderContentScrollView.swift:122`; `Modules/CoreRPG/Navigator/Core/NavigationConfiguration.swift:73`; `Modules/CoreRPG/ViewModifiers/RemoveItemViewModifier.swift:41,48`; `Modules/CoreRPG/Buttons/ControlSharingView.swift:195`; `Tests/CoreRPGTests/LinkHighlightTextModelTests.swift:81,114,115`
- **What:** These are the only `print()` calls in the entire tree not already `#if DEBUG`-gated or confined to a `#Preview` block.
- **Why:** `print()` output is unstructured, always-on, and bypasses this codebase's otherwise-consistent `Logger` conventions; `NavigationConfiguration.swift:73` in particular prints an arbitrary interpolated value whose contents aren't obviously non-sensitive at that call site. None print tokens, credentials, or raw network payloads.
- **Action:** Replace with the module's existing `Logger` categories, or remove if purely leftover debug output.
- **Severity:** Low

---

## 6. Security

This app has no backend API/IAP; the review focused on local data at rest, the SharePlay/Bonjour transport, entitlements, and untrusted-input parsing (Foundry VTT import).

### 6.1 Data-URI asset misclassification in system-package imports (security-adjacent duplication)
- **Location:** `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:1172-1176` vs. `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:1979-1983`
- **What:** See §9.1 for full detail — `FoundryPackageResourceResolver.isRemote` (system-package importer) checks only `http://`/`https://`, while `FoundryVTTResourceResolver.isRemote` (world importer) also checks `data:`.
- **Why:** A `data:`-URI asset reference in a system-package import is misclassified as a local path lookup instead of being skipped as remote, unlike the world-import path — an inconsistency in how untrusted package content is classified between the two entry points.
- **Action:** Fix as part of the shared-utility extraction proposed in §9.1.
- **Severity:** High (tracked as one item with §9.1; not double-counted in the finding total)
- **Status: FIXED.** Added the missing `data:` prefix check to `FoundryPackageResourceResolver.isRemote` (`FoundrySystemPackageReader.swift:1172-1179`) so it now matches `FoundryVTTResourceResolver.isRemote`. This is the targeted classification fix only — the broader shared-utility extraction across both readers (§9.1-§9.5) was not done and remains open as a separate dedup task. Verified with a full clean build (zero warnings) and the `CoreRPGTests/Foundry`, `RuleRPGTests`, and `DiceRPGTests` suites (59 tests, 17 suites, all passing).

### 6.2 Widget extension entitlements intentionally omit the iCloud container (verified correct)
- **Location:** `Sources/DiceRollerWidget/DiceRollerWidgetExtension.entitlements` (only `com.apple.security.application-groups`) vs. `Resources/MasterRPG-{Debug,Release}.entitlements` and `Sources/RPGShare/RPGShare-{Debug,Release}.entitlements` (both also declare `icloud-container-identifiers`)
- **What:** The widget only reads dice-roll state the main app already wrote into the shared App Group `UserDefaults`, and never touches Core Data/CloudKit directly, so no iCloud entitlement is needed.
- **Why:** Recorded as a verified non-finding so it isn't mistaken for a gap; revisit only if the widget ever reads CloudKit-synced data directly.
- **Action:** None needed today.
- **Severity:** Low (informational)

**Checked and confirmed already correctly handled (no findings):** the SharePlay transport's race/retry/journal-admission machinery; join-code security (Keychain-backed with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, no iCloud sync, exponential-backoff connection throttling); the Foundry ZIP reader's rejection of path traversal, symlinks, ZIP64/multi-disk archives, encryption, and decompression bombs; `ExternalImport`'s transactional commit/rollback with content-hash verification; all 13 Core Data `.xcdatamodeld` files (no non-optional/no-default attributes or non-optional relationships, satisfying `NSPersistentCloudKitContainer` requirements); and a repo-wide credential/secret grep (`apikey`, `secret`, `bearer`, `authorization`, `access_token`) with zero hits.

---

## 7. Performance

### 7.1 Unbounded dice-roll history re-serialized to `UserDefaults` on every roll
- **Location:** `Sources/DiceRollerWidget/DiceRollerView.swift:15` (`rollHistory: [DiceResultModel] = []`), `:121` (`rollHistory.append(result)`, no cap), `:138-151` (`loadHistory()`/`saveHistory()` JSON-encode/decode the entire array through the shared App Group `UserDefaults` on every roll and every view appearance)
- **What:** `rollHistory` grows without any upper bound, and the full array is JSON-encoded/written after every single roll.
- **Why:** This runs inside `DiceRollerWidgetExtension`, a memory-constrained process; unbounded growth plus O(n) encode/decode per roll during a long game session (hundreds of rolls) causes increasing per-roll latency and memory pressure, and large `UserDefaults` payloads risk being throttled by the system's plist-backed storage.
- **Action:** Cap `rollHistory` to a fixed recent-N count before persisting (mirroring the bounded-history pattern already used elsewhere in this codebase, e.g. `SharePlayJournalTracker`), and consider incremental persistence instead of full re-encoding.
- **Severity:** Medium
- **Status: FIXED.** Added `DiceRollerView.maxRollHistoryCount = 50`; `rollDice()` now trims the oldest entries after every append, and `loadHistory()` trims any larger array persisted before the cap existed. The full-array JSON re-encode/decode on every roll remains (now bounded to at most 50 entries rather than unbounded) — true incremental persistence was judged out of scope for this fix. Verified with a full clean build (zero warnings); no dedicated unit tests exist for this widget-extension view.

### 7.2 Fetch batching, caching, and view-body hoisting confirmed already handled
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift`; Photo/Map/Pdf/Space `CacheController.swift` + `Modules/CoreRPG/Cache/ImageCacheController.swift`; `Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift`
- **What:** `fetchBatchSize` is deliberately omitted in the generic Core Data fetch (documented: batching would disable relationship prefetching) while high-volume statistics fetches do set it — a consistent, intentional split. All cache controllers share a single cost-bounded `ObjectCache`. No view-body sorting/decoding/formatting work was found that should be hoisted.
- **Action:** None needed.
- **Severity:** Low (informational)

---

## 8. SwiftUI / UI

### 8.1 Unstable `@Entry` environment defaults regenerate identity on every read
- **Location:** `Modules/PdfRPG/Model/PdfViewerActions.swift:18` (`init(id: AnyHashable = UUID(), ...)`), `:32` (`@Entry var pdfViewerActions: PdfViewerActions = PdfViewerActions()`); `Modules/CoreRPG/App/RouterActions.swift:12` (`init(id: EnvironmentActionIdentity = .fresh(), ...)`), `:26` (`@Entry var routeActions: RouteActions = RouteActions { _, _, _ in }`); `.fresh()` resolves to `.token(UUID())` at `Modules/CoreRPG/Model/EnvironmentActionIdentity.swift:25`
- **What:** Both `@Entry` defaults construct a fresh instance whose `Equatable` conformance is keyed only on `id`, and that `id` defaults to a brand-new `UUID()`/`.fresh()` token each time the environment key's default is evaluated.
- **Why:** This is precisely the "non-constant `@Entry` default" anti-pattern — it defeats the exact-equality-based diffing these two types' own doc comments say they exist for, so a reader with no explicit `.environment(...)` writer compares unequal to itself across reads and invalidates unnecessarily.
- **Action:** Give both `@Entry` defaults a stable, constant identity (e.g. a fixed sentinel reserved for "no writer configured yet") instead of generating one per access.
- **Severity:** Medium
- **Status: FIXED.** Added `EnvironmentActionIdentity.unconfigured` (a fixed sentinel, distinct from `.fresh()` which real writers still use unmodified) and `PdfViewerActions.unconfiguredId` (a computed property, not a stored `static let`, since `AnyHashable` isn't unconditionally `Sendable`), then passed each explicitly at the two `@Entry` declaration sites instead of relying on the `.fresh()`/`UUID()` init defaults. No real writer call site was touched — every one already passes an explicit `id`. Verified with a full clean build (zero warnings) and the `CoreRPGTests`/`PdfRPGTests` suites (287 tests, 59 suites, all passing).

### 8.2 Non-private `@State` seeded from an init parameter in two navigation modifiers
- **Location:** `Modules/CoreRPG/Navigator/Core/NavigationCheckpoint.swift:294` (`NavigationCheckpointActionModifier`), `:319` (`NavigationCheckpointValueModifier`)
- **What:** `checkpoint` is declared `@State internal` (not `private`) and seeded from the modifier's `init` parameter; a later reapplication of `.navigationCheckpoint(action:)`/`.navigationCheckpoint(value:)` with a different checkpoint value at the same view-tree position would keep using the stale first-seen value.
- **Why:** Violates both "`@State` must be `private`" and the project's known "value passed into init re-stored into `@State`" bug class; masked today only because call sites currently pass a constant checkpoint value.
- **Action:** Mark both `@State` properties `private`, and either drop `@State` for a plain `let` or explicitly enforce that the checkpoint argument never changes across reapplications.
- **Severity:** Medium
- **Status: FIXED.** Marked both `@State` properties `private`. Dropping `@State` for a plain `let` was rejected — it also caches the auto-generated `identifier` stable across ordinary re-renders (a plain `let` would regenerate a fresh random `UUID` on every parent re-render, breaking the identifier the navigator later matches a returning value against). Instead, added `.id(checkpoint.name)` at the two `navigationCheckpoint(_:action:)`/`navigationCheckpoint(_:completion:)` call sites (not inside the modifiers' own `body(content:)`, where an `.id()` has no effect on the modifier's own `@State`), so SwiftUI now tears down and rebuilds the modifier whenever a genuinely different checkpoint is passed at the same view-tree position. Verified with a full clean build (zero warnings) and the `CoreRPGTests` suite (234 tests, 45 suites, all passing).

### 8.3 View bodies split into computed `some View` properties instead of extracted `View` structs
- **Location:** ~130 sites across nearly every module — representative examples: `Modules/GameRPG/GameViews/OverlayGameMenu.swift:39-318` (14 properties); `Modules/MapRPG/Map/EditMapToolBar.swift:255-424` (11 properties); `Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:99-335` (9 properties); `Modules/SpaceRPG/Space/SpaceViewer.swift:437,463,485,556,899`; `Modules/AudioRPG/Audio/AudioPlayerTimelineView.swift:48-153`; `Modules/CoreRPG/LGViewModifiers/ToolbarItemListViewModifier.swift:76,109,189`; `Modules/GameRPG/SetupViews/SelectedAdventureView.swift:87-169`; full list of ~130 sites recorded in the audit working notes
- **What:** Each is a `var name: some View { ... }` computed property inside a `View`/`ViewModifier` type, not an extracted `View` struct.
- **Why:** CLAUDE.md explicitly bans this pattern in favor of independently-diffable child `View` structs. Sibling files in the same modules (`SheetEntryView.swift`, `ItemHeaderEditorView.swift`) have already been refactored away from it per their own in-code "CODE_AUDIT §8.2" comments, showing the remaining ~130 sites are backlog, not an accepted exception.
- **Action:** Extract each computed subview property into its own `View` struct, following the pattern already used in the already-refactored sibling files. Prioritize the highest-count files (`OverlayGameMenu.swift`, `EditMapToolBar.swift`, `QuickEntryEditorView.swift`) first.
- **Severity:** Medium
- **Status: FIXED.** All ~130 cited sites across all 52 files extracted into `private struct <Parent><Purpose>View: View` types under a `// MARK: - Extracted subviews (CODE_AUDIT §8.3)` section in each file, matching the `SheetEntryView.swift` house style exactly (`let`/`@Binding` parameters for captured state, `@Environment` redeclared directly where simpler). Done via five parallel batches partitioned by module with no file overlap. Two real bugs surfaced and were fixed during verification: (1) an invalid `#if !os(tvOS)` conditional-comma-in-argument-list construct in `InlineImporterView.swift`/`NeedleMapPin.swift`, caught by the batch agent's own `swiftc -parse` check and fixed on the spot; (2) converting three instance methods (`toggleFolder`, `addItemButton`, `addItem`) in `ToolbarItemListViewModifier.swift` to file-scope free functions lost the implicit `@MainActor` isolation `View`/`ViewModifier` conformance normally infers for a type's members, causing one compile error (missing `await` on a MainActor call) and one warning (a MainActor property read from a nonisolated function) — fixed by explicitly marking those three functions `@MainActor`. Verified with a full **clean** build (zero warnings, not just an incremental one, given the scale of this change) and 1,267 tests across 186 suites, all passing (`CoreRPGTests`, `PdfRPGTests`, `DiceRPGTests`, `GameRPGTests`, `PhotoRPGTests`, `MapRPGTests`, `SpaceRPGTests`, `AudioRPGTests`). `Sources/RPGShare/SharingView.swift` has no dedicated test target; verified by the clean build only, same as before this fix.

### 8.4 Icon-only overflow menu with no accessible label
- **Location:** `Modules/CoreRPG/LGViewModifiers/ToolbarItemListViewModifier.swift:102-104`
- **What:** `Menu { … } label: { Image(systemName: "ellipsis.circle") }` has no `Label`/text alternative and no `.accessibilityLabel`.
- **Why:** VoiceOver users get no meaningful name for this toolbar overflow menu, unlike sibling round buttons elsewhere in the codebase that attach `.accessibilityLabel`/`.help` via the shared `selectedRoundButton` modifier.
- **Action:** Use `Label("More", systemImage: "ellipsis.circle")`, or add an explicit `.accessibilityLabel`.
- **Severity:** Medium
- **Status: FIXED.** Replaced the bare `Image(systemName: "ellipsis.circle")` label with `Label { Text("More", bundle: .module) } icon: { Image(systemName: "ellipsis.circle") }`, matching this file's own established two-closure `Label` pattern (`toggleFolder()`, `addItemButton(for:)`) rather than the single-string initializer, so the string picks up the module's localization convention. The toolbar still renders it icon-only by default; VoiceOver now announces "More". Verified with a full clean build (zero warnings); no dedicated unit test exists for this toolbar menu.

### 8.5 `AnyView` type-erasure at module `ViewControllable` boundaries (accepted, already tracked)
- **Location:** `Modules/CoreRPG/Controllable/ViewControllable.swift:58-102`; `Modules/CoreRPG/Navigator/Core/{AnyNavigationDestination.swift, NavigationDestination.swift, NavigationModifiers.swift}`; every module's `Controller/ViewController.swift`
- **What:** Every one of these returns `AnyView`, required because `ViewControllable`'s protocol methods can't return `some View` across a cross-module `any` existential.
- **Why:** Already an acknowledged, structurally-required boundary per the codebase's own "CODE_AUDIT §8.5" comment, not a stray misuse.
- **Action:** None beyond what's already tracked.
- **Severity:** Low

### 8.6 Minor Dynamic-Type / hard-coded-color items in non-shipping code
- **Location:** `Modules/CoreRPG/Extensions/View+variableBlur.swift:68,84,108,131,159` (fixed 300pt fonts, all inside `#Preview` blocks); `Modules/CoreRPG/Views/SupporterCrownView.swift:26,28,30,39,41,43` (literal `Color(red:green:blue:)` for bronze/silver/gold badge tones); `Modules/GameRPG/Statistics/View/GameStatisticsDiceChart.swift:25` (`SectorMark(...).cornerRadius(5)` — verified as Swift Charts' `ChartContent.cornerRadius(_:)`, not the banned `View.cornerRadius`, so **not** a violation)
- **What:** The font-size items are demo-only preview code; the crown colors are an intentional fixed medal-tone badge unlikely to need dark-mode adaptation.
- **Action:** No action expected unless these are promoted to shipping UI or the crown is meant to re-theme.
- **Severity:** Low

**Checked and confirmed clean:** no other `ObservableObject`/`@StateObject`/`@ObservedObject`/`@EnvironmentObject`/`@Published` outside §3.2's accepted exception; no `foregroundColor(`, `.tabItem(`, `NavigationView`, `fontWeight(.bold)`, `ForEach` `.indices`/`\.offset` identity, `ForEach(Array(...enumerated()))`, `showsIndicators: false`, `ScrollViewReader`, single-parameter `.onChange(of:)`, or non-private `@FocusState` anywhere; the only two `GeometryReader` usages are legitimate `GeometryReader3D` for RealityKit volumetric content; Map pin health/highlight/attacker state already pairs every color cue with a full non-color `accessibilityValue` (per [[map-pin-health-highlight-attacker-3d-colors]] and [[health-percent-text-type-entry-bug]]); hot leaf views (`ItemRowView`, `SheetEntryView`'s selection borders) already conform to `Equatable`; the pervasive "`@State` fed from an init parameter" pattern (~80 sites) was spot-checked at its highest-risk-looking call sites and found consistently guarded by naming convention, `.id()`-scoping, or an explicit `.onChange`/`.reset` write-back — no other live instance of the bug class in §5.1/§8.2 was found.

---

## 9. Dead code / duplication / refactor

### 9.1 Duplicated Foundry package-resource resolution algorithm (largest duplicate in the codebase)
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:1897-1986` (`FoundryVTTResourceResolver`) vs. `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:1088-1179` (`FoundryPackageResourceResolver`)
- **What:** Both files independently implement the same resolve-one-asset-path algorithm (remote check, candidate-path construction, byte-budget-with-overflow-protection accumulation, SHA-256 hashing via the correctly-shared `foundrySHA256`, installation-path fallback). `isInstallationPath`/`isFoundryInstallationPath` is byte-for-byte identical (`FoundryVTTImportReader.swift:1984-1986` vs. `FoundrySystemPackageReader.swift:1177-1179`); `isRemote` differs — `FoundryVTTImportReader.swift:1979-1983` also recognizes a `"data:"` prefix, `FoundrySystemPackageReader.swift:1172-1176` does not.
- **Why:** ~85 lines of security/correctness-sensitive resolution logic maintained twice; the `isRemote` gap (see §6.1) means a `data:`-URI asset reference is classified differently between the two import paths.
- **Action:** Extract one shared, parameterized `FoundryPackageResourceResolver` used by both readers, and reconcile the `isRemote` gap while merging.
- **Severity:** High

### 9.2 Duplicated path normalization/join helpers
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:1612-1642` (`FoundryVTTPath.normalized`/`.join`) vs. `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:471-490` (`FoundryPackagePath.normalized`/`.join`)
- **What:** Two private enums each independently implement identical path-traversal-safe normalization and relative-path joining; the two copies have already drifted (one strips a leading `./` itself, the other requires the caller to strip it first).
- **Why:** A future fix to the traversal-safety logic has to be applied by hand in two places.
- **Action:** Extract one shared `FoundryPackagePath` utility used by both readers.
- **Severity:** Medium

### 9.3 Duplicated Foundry JSON-decoding setup
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:1648-1660` (`FoundryVTTRawJSON.decode`) vs. `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:569-588` (`FoundryJSONDecoder.decodeSource`/`.decode`)
- **What:** Both build a `JSONDecoder`, set the same two anti-DoS `userInfo` depth-guard keys, and decode into `FoundryJSONValue`, with slightly different error-message wording.
- **Why:** The depth-guard setup is security-relevant (decompression/recursion-bomb protection); hand-copying it risks one copy being missed if the guard is ever tightened.
- **Action:** Extract one shared `FoundryJSONDecoding.decode(_:context:)` helper.
- **Severity:** Medium

### 9.4 Duplicated asset-path collection with a drifted extension allowlist
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:1779-1813` (`FoundryVTTAssetCollector`) vs. `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:1035-1084` (`FoundryAssetCollector`)
- **What:** Both keep a near-identical ~30-entry media-extension allowlist and a recursive collect walker; the allowlists have already drifted (one includes `"m4v"`, the other doesn't).
- **Why:** The two importers can classify the same file differently, and a new asset extension has to be added twice.
- **Action:** Extract one shared `FoundryAssetPathCollector` (the superset version, including HTML `src`/`href` scanning).
- **Severity:** Medium

### 9.5 Duplicated `isLicensePath` helper
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:1636-1639` vs. `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:495-498`
- **What:** Both independently check for `"license"`/`"copying"`/`"attribution"` substrings, with a slightly different directory-suffix guard between copies.
- **Action:** Fold into the shared path-utility extraction in §9.2 and reconcile the directory-suffix behavior.
- **Severity:** Low

### 9.6 `createFileUrl` bypasses the shared coordinated-download helper
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:337-344` vs. `Modules/CoreRPG/Files/FileManager+Coordination.swift:66-72` (`download(coordinatingAccessAt:)`)
- **What:** Calls `FileManager.default.startDownloadingUbiquitousItem(at:)` directly with `try?`, instead of the file-coordinated helper that wraps the same call with `NSFileCoordinator` + security-scoped-resource access.
- **Why:** The coordinated helper exists to avoid racing CloudKit sync's own coordinator-protected writes; this is the one call site still bypassing it, and its failure is silently discarded rather than logged like the neighboring failure path.
- **Action:** Route through `FileManager.download(coordinatingAccessAt:)` and log failures consistently.
- **Severity:** Low

### 9.7 `RPGSharePlayController.swift` (2,635 lines) mixes ~15 support types with a 1,700-line transport extension
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:41-639` (support types), `:643-866` (controller), `:869-2574` (send/chunk/retry, >60% of the file), `:2576-2635` (visionOS config)
- **What:** The largest production file in the repo; a single extension covers all send/chunk/retry logic.
- **Why:** The module already uses an extension-per-file pattern elsewhere (`MasterController+MapMessages.swift`, `+AudioMessages.swift`) that isn't applied here.
- **Action:** Move support types to `SharePlaySessionSupportTypes.swift`; split the transport extension into `+Send.swift`/`+ChunkedTransport.swift`/`+Recovery.swift`; move visionOS config to `+VisionOS.swift`.
- **Severity:** Medium

### 9.8 The two Foundry importers mix five separable concerns each
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift` — LevelDB decoding/merging/assembly/key-parsing (`:678-1261`, ~580 lines), Foundry Bridge decoding (`:2069-2552`, ~480 lines), plus the duplicated helpers already flagged in §9.2-§9.5 (`:1610-1996`); `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift` — LevelDB compendium decoding (`:669-915`, ~246 lines) plus the same duplicated helper categories (`:399-591,1035-1182`)
- **What:** Manifest selection, LevelDB decoding, JSON/path/asset utilities, and an unrelated "bridge" decoding format all share one file in each reader.
- **Action:** Extract `FoundryVTTLevelDBDecoding.swift` and `FoundryVTTBridgeDecoding.swift` from the first; extract `FoundrySystemCompendiumDecoding.swift` from the second; move shared helpers into the utility files proposed in §9.1-§9.4 instead of duplicating them.
- **Severity:** Medium

### 9.9 Other oversized files with concrete split proposals
- **Location:** `Modules/GameRPG/Controller/PlayerControllerModel.swift:15-1048` (no internal extension structure, unlike sibling `MasterController`'s already-adopted `+*.swift` split); `Modules/SpaceRPG/Space/SpaceViewer.swift:17-965` (one `View` struct body — a direct CLAUDE.md violation); `Modules/RolePlayGameKit/Import/Foundry/FoundryImportView.swift:7-594` (587-line wizard view); `Modules/CoreRPG/Import/ExternalImport.swift:299-1023` (`ExternalImportReviewSession` is ~70% of the file); `Modules/GameRPG/Table3D/GameEquipment.swift:776-904` (trailing SharePlay extensions unrelated to the file's "equipment" name); `Modules/GameRPG/Root/GameRootModel.swift:22-901` (two top-level types + 5 already-MARK-delineated extension groups); `Modules/CharacterRPG/Controller/EditController.swift:267-503` (largest of 9 MARK-delineated extensions); `Modules/RuleRPG/Model/RuleModel.swift:127-515` (Foundry-factory section is ~46% of the file); `Modules/CoreRPG/Foundry/FoundryRuleModels.swift:199-719` (23 DTOs with no file-level grouping); `Modules/MapRPG/Map/MapOverlayGeometry.swift` (three unrelated geometry systems); `Modules/CoreRPG/Controllable/EditControllable.swift`/`ImportControllable.swift` (protocol files dominated by default-implementation extensions); `Modules/GameRPG/Network/GameNetworkController.swift:347-662` (SharePlay delegate conformance is nearly half the file); `Modules/CoreRPG/FileViews/SingleReviewModels.swift:277-651`; `Modules/MapRPG/Model/MapModel.swift`/`Modules/DiceRPG/Model/DiceModel.swift` (largest section is the mechanical `ItemDataAccessable` extension)
- **What:** Each already shows clear MARK-delineated split points; only the mechanical file split is missing.
- **Action:** Apply the `<Type>+<Concern>.swift` extension-file convention already used elsewhere in the codebase (e.g. `MasterController`, `PlayerController`) to each.
- **Severity:** Low

### 9.10 28 additional non-test files in the 377-650 line range (bucketed)
- **Location:** `Modules/CharacterRPG/Controller/GameController.swift`, `Modules/CharacterRPG/Model/ValueModel.swift`, `Modules/CoreRPG/Controllable/ItemControllable.swift`, `Modules/CoreRPG/Foundry/FoundryVTTArchiveSanitizer.swift`, `Modules/CoreRPG/Foundry/UniversalVTTReader.swift`, `Modules/CoreRPG/Import/ExternalImportSourceRegistry.swift`, `Modules/CoreRPG/Persistence/CoreDataController.swift`, `Modules/CoreRPG/ScenesManager/ScenesManager.swift`, `Modules/CoreRPG/Sheet/SheetEntryView.swift`, `Modules/CoreRPG/Views/ViewportGeometry.swift`, `Modules/DiceRPG/Controller/GameController.swift`, `Modules/GameRPG/Controller/MasterController.swift`, `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift`, `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift`, `Modules/GameRPG/Statistics/Model/GameStatisticsTypes.swift`, `Modules/GameRPG/Table3D/GameTableView+VisionOS.swift`, `Modules/MapRPG/BattleRound/BattleRoundModel.swift`, `Modules/MapRPG/Controller/EditController.swift`, `Modules/MapRPG/Controller/GameController+Battle.swift`, `Modules/MapRPG/Map/EditMapToolBar.swift`, `Modules/MapRPG/Map/MapEditController.swift`, `Modules/MapRPG/Map/MapPinView.swift`, `Modules/MapRPG/Map/MapEditorModel.swift` (its `MapCanvasGeometryResolver` at line 628 is an easily-separable unrelated type), plus ~15 more Foundry/import-pipeline files in this range
- **What:** Sit in the 377-650 line range without an individually-detailed split.
- **Action:** Apply the same MARK-section-extraction pattern when next touched; prioritize the `FoundryVTTDomainMapper+*.swift`/`FoundryRuleImportModel.swift` files since they may share more logic with the Foundry duplication already flagged.
- **Severity:** Low

### 9.11 39 test files exceed 500 lines, several exceeding 1,000-4,000+ lines
- **Location:** `Tests/GameRPGTests/SharePlayPackageTransportTests.swift:1-4130` (largest file in the entire repository); `Tests/GameRPGTests/MasterPlayerControllerTests.swift:1-2267`; `Tests/GameRPGTests/NetworkStoreTests.swift:1-2000`; `Tests/CoreRPGSnapshotTests/CoreRPGGeneratedPreviewSnapshotTests.swift:1-1950`; `Tests/GameRPGTests/MasterControllerConnectionTests.swift:1-1458`; `Tests/PhotoRPGTests/FolderListControllerTests.swift:1-1306`; `Tests/SpaceRPGTests/EditControllerTests.swift:1-1232`; `Tests/GameRPGTests/MapMasterMessageFlowTests.swift:1-1207`; `Tests/CharacterRPGTests/EditControllerTests.swift:1-1207`; `Tests/GameRPGTests/MultiConnectionTests.swift:1-1140`; plus ~29 more in the 377-930 line range
- **What:** `SharePlayPackageTransportTests.swift` alone is larger than most production files combined with its nearest neighbor.
- **Why:** Slow to navigate, slows Xcode's per-file indexing/typechecking, and makes it hard to tell which tests exercise which specific scenario at a glance.
- **Action:** Split by scenario mirroring the production-code split proposed for `RPGSharePlayController.swift` in §9.7 (e.g. `+Chunking.swift`, `+Retry.swift`, `+Recovery.swift`).
- **Severity:** Low

### 9.12 Misspelled public symbol `gameGiceHeight`
- **Location:** `Modules/DiceRPG/Controller/ViewController.swift:99` (declaration); `Tests/DiceRPGTests/ViewControllerTests.swift:68,72` (call sites)
- **What:** `gameGiceHeight(root:)` is a typo of `gameDiceHeight`.
- **Action:** Rename and update the two test call sites.
- **Severity:** Low

### 9.13 Hardcoded link-scheme literal instead of the shared `URL.appScheme` constant
- **Location:** `Modules/DiceRPG/Intent/DiceEntity.swift:101-103`
- **What:** `urlRepresentation` returns the literal `"RPG://DICE/0/\(.id)"` instead of composing from `URL.appScheme` (`Modules/CoreRPG/App/URL+ItemId.swift:6`), unlike every other link-construction site.
- **Why:** `DiceEntity` is the only `URLRepresentableEntity` conformance in the codebase, so a future scheme change would silently miss this Shortcuts/Spotlight entry point.
- **Action:** Compose via `URL.appScheme` instead of the bare literal.
- **Severity:** Low

### 9.14 Playground/scratch code checked into a shipping module
- **Location:** `Modules/GeneratorRPG/Playground/MyAiPlayground.swift:1-127`
- **What:** A file made entirely of Xcode `#Playground(...)` macro exploration blocks sits inside `Modules/GeneratorRPG`'s main source tree, with no other references anywhere.
- **Why:** Dev-time exploration code shipped in the production module tree risks being mistaken for supported API surface.
- **Action:** Move to a Playgrounds-only location outside the compiled module target, or delete if superseded.
- **Severity:** Low

### 9.15 Redundant duplicate `print(error.localizedDescription)`
- **Location:** `Modules/GeneratorRPG/Playground/MyAiPlayground.swift:25-33`
- **What:** The `catch` block prints `error.localizedDescription` once inside a narrowed `GenerationError` check, then unconditionally again immediately after.
- **Action:** Delete the redundant inner print.
- **Severity:** Low

### 9.16 Disabled/commented-out App Intent entity-query test
- **Location:** `Tests/AdventureRPGTests/AppIntentTests.swift:19-59`
- **What:** A ~20-line `@Test` is fully commented out, preceded by a paragraph (citing CODE_AUDIT §9.12) explaining it crashes the whole XCTest process because `@Dependency` can only be accessed inside the real Intent perform flow.
- **Why:** This was the only genuine block of commented-out code found anywhere in the tree; everything else surfaced by a heuristic scan is the codebase's normal, unusually thorough prose design-rationale comments.
- **Action:** Migrate the coverage to the out-of-process `AppIntentsTesting` framework as the comment itself recommends, then delete the block.
- **Severity:** Low

### 9.17 Magic constants, `#if false`, and TODO/FIXME markers — checked, already clean
- **Location:** n/a (repo-wide)
- **What:** Zero `#if false` blocks anywhere; zero TODO/FIXME/HACK/XXX/`#warning` markers anywhere; the App Group and iCloud container identifiers are each declared exactly once (`Modules/CoreRPG/App/AppGroup.swift:6,34`); thumbnail/image-size constants are already named per-module `static let`s, not ad-hoc literals.
- **Why:** Confirms these specific risks called out in the audit brief are not present at scale.
- **Action:** None needed.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Extract one shared Foundry path/JSON/asset/resource-resolution utility file** used by both `FoundryVTTImportReader.swift` and `FoundrySystemPackageReader.swift` (§9.1-§9.5, §9.8). This is the single highest-value change in this audit: it fixes the one High-severity finding, removes ~85+386 lines of duplicated security-sensitive logic, and shrinks both of the repo's largest files as a side effect.
2. **Apply the already-established `<Type>+<Concern>.swift` extension-file split** (proven out on `MasterController`) to the handful of large files that haven't adopted it yet — `RPGSharePlayController.swift`, `PlayerControllerModel.swift`, `GameNetworkController.swift`, and the Foundry importers (§9.7-§9.10).
3. **Extract computed `some View` subview properties into real `View` structs** across the ~130 remaining sites (§8.3), following the pattern already used in this codebase's own refactored sibling files (`SheetEntryView.swift`, `ItemHeaderEditorView.swift`) — this is an established, in-progress convention, not a new one to introduce.
4. **Audit other "present a per-item panel via `selection` reassignment" call sites** for the same view-identity gap found in §5.1/§8.2 — anywhere an `.overlay`/`.sheet` swaps which item's editor is displayed by mutating an `Optional<Selection>` without transiting `nil`, the same silent-stale-state risk applies.
5. **Adopt a stable-identity convention for `@Entry` environment defaults** project-wide (§8.1) — a short internal guideline ("never default an `@Entry` value's identity token to a fresh `UUID()`/`Date()`") would prevent this pattern from recurring as new closure-carrying environment values are added.

---

## 11. What was NOT audited

- **`MasterMac`, `MasterTV`, `RolePlayGameKit`-standalone, and test-target schemes were not build-verified.** Only the `MasterRPG` iOS scheme was clean-built to capture compiler warnings (zero found); the other platform targets and all test targets share most of the same module code but weren't independently compiled for this pass.
- **Algorithmic correctness of Table3D/RealityKit rendering** beyond obviously-verifiable geometry math. No `.metal` kernels exist in this project.
- **Xcode project/build-settings structure** beyond what's visible in the scheme build and `project.pbxproj` grep checks.
- **Third-party SPM dependency internals** (`RPGTabletopGameContent`, `swift-syntax`, `swift-snapshot-testing`, `swift-custom-dump`, `xctest-dynamic-overlay`) — treated as black boxes.
- **Deep test-coverage assessment.** Test files were scanned for size/staleness/dead-code only, not reviewed for coverage gaps or assertion quality.
- **Localization correctness.** `bundle: .module` usage was assumed correct per the established convention; string content/translation quality was not assessed.
- **Performance profiling via Instruments.** No `.trace` capture was run; all performance findings are static-analysis-based.
- **Full manual line-by-line read of all ~2,033 files.** Agents prioritized hot-spot files (largest/most central) plus targeted full-tree greps for known anti-patterns; low-traffic small files received grep-level coverage only.
- **CI/fastlane/build-script correctness**, and the 20+ prior `Docu/CODE_AUDIT_*.md` documents' remaining open items were not individually re-verified as a checklist (this pass re-derived findings independently from current code).

---

## 12. Verification

No Critical findings were surfaced across any of the four independent review passes (concurrency, dead-code/duplication, bugs/security/performance, SwiftUI). The single highest-severity finding is High. Both High items were personally verified by opening the cited lines before inclusion:

- **§9.1 / §6.1** — open `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:1979-1983` and `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:1172-1176` side by side: the first's `isRemote` checks `http://`, `https://`, and `data:`; the second checks only the first two. Confirmed by direct read, not inferred.
- **§5.1** — open `Modules/TableRPG/View/TableGenerationRootView.swift:6-17` (confirm `_model = State(initialValue: controller.makeModel(itemId: itemId))` inside `init`) and `Modules/CoreRPG/LGViews/ItemGenerationPresentationModifier.swift:21-31` (confirm the `.overlay { if let selection, let generator = ... }` branch that doesn't force new identity per `itemId`). Confirmed by direct read.
- **§5.2** — open `Modules/GameRPG/Root/GameRootModel.swift:381-388`: confirm both `_viewController.unsafelyUnwrapped` and `_logGameController.unsafelyUnwrapped`. Confirmed.
- **§8.1** — open `Modules/PdfRPG/Model/PdfViewerActions.swift:18,32` and `Modules/CoreRPG/App/RouterActions.swift:12,26`: confirm the `UUID()`/`.fresh()` default expressions feeding each `@Entry` default. Confirmed.
- **§8.2** — open `Modules/CoreRPG/Navigator/Core/NavigationCheckpoint.swift:294,319`: confirm `@State internal var checkpoint` (not `private`) seeded from each modifier's `init`. Confirmed.
- **§7.1** — open `Sources/DiceRollerWidget/DiceRollerView.swift:15,121,138-151`: confirm the unbounded `append` and the full-array JSON re-encode in `saveHistory()`. Confirmed.
- **§3.5** — a candidate Medium finding ("13 `Task.detached` sites need cancellation-forwarding verification") was **dropped after verification**: all 13 sites were opened directly and each already wraps its awaited result in `withTaskCancellationHandler`/`.cancel()`, with the one non-awaited fire-and-forget exception (`AppDataModel.swift:310`) correctly not needing it. Recorded in §3.5 as a checked-and-cleared item rather than a live finding.

If any finding doesn't reproduce when you visit the line, flag it and I'll re-investigate.
