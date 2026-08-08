# MasterRPG Code Audit

Generated 2026-08-07, updated 2026-08-07 after a quick-wins pass (see amendment below). Scope: ~263,900 Swift LOC across 1,945 files, 0 Metal kernels, spanning targets `MasterRPG` (iOS/visionOS), `MasterMac`, `MasterTV`, `RPGShare`, `DiceRollerWidgetExtension`, and 14 feature modules (`AdventureRPG`, `AudioRPG`, `CharacterRPG`, `CoreRPG`, `DiceRPG`, `GameRPG`, `GeneratorRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `RolePlayGameKit`, `RuleRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG`).

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action. Three parallel background audits covered concurrency/API modernity, dead code/duplication, and bugs/security/performance; a fourth pass covered SwiftUI-specific structure. Every High-severity claim below was independently re-opened and confirmed before inclusion — see §12.

> **Amendment (post-audit quick-wins pass):** Two findings in the original report were wrong and have been corrected in place rather than silently edited away — see the struck-through items in §2 and the notes on §9.1 and §9.12. In short: `Modules/DiceRPG/0-Old/` and `Modules/SpaceRPG/0-Old/SpaceQuickLook.swift` are **not** dead code (despite the folder name, they're live production UI — the original "0 references" check grepped `project.pbxproj` text, which doesn't reflect this project's Xcode-16 file-system-synchronized group membership); and the `.system.search` → `.system.searchInApp` swap in §4.1 is **not** a safe mechanical fix — it broke the build (`searchInApp` requires macOS 27; this project targets macOS 26). Both were caught by actually building the project before/after, not by static review alone. Everything else in §2 was verified safe and applied.

---

## 1. Executive summary

No finding in this audit reaches **Critical** (crash-on-common-path / data loss / memory corruption with no mitigating factor) — the codebase's untrusted-input parsers (Foundry VTT archive/LevelDB readers) are in fact unusually well-hardened, per Agent C's own note. The following ten are the highest-impact items, in priority order:

1. **[High] Game log resolves Character-tied entries against the wrong module root** — §5.1 — `Modules/GameRPG/Controller/LogGameController.swift:189-190`. Every Character/value-related log entry looks up its display name in `photoRoot` instead of the correct root, so it shows the wrong name or falls back to a raw UUID.
2. **[High] Force-unwrapped `URL(string:)!` built from unescaped user-entered item names** — §5.4 — `Modules/CoreRPG/Controllable/EditControllable.swift:585-586`. Renaming a Character/Photo/item to include `#`, unencoded `%`, or `?` crashes on save.
3. **[High/Security] Hardcoded, app-wide local-network pairing secret** — §6.1 — `Modules/GameRPG/Network/GameSecurity.swift:7`. The TLS pre-shared key for Bonjour game pairing is a single string literal baked into every install; it tags traffic but authenticates nothing.
4. **[High] Foundry VTT import mapping runs synchronously on the Main Actor** — §3.1 — `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift:179-180`. The entire document/asset mapping pass for a large VTT package blocks the UI thread during import.
5. **[High, FIXED] Widget extension deployment target exceeded the host app's** — §4.6 — `MasterRPG.xcodeproj` (DiceRollerWidgetExtension target build settings). `DiceRollerWidgetExtension` was pinned to iOS/macOS/visionOS 26.4 while the host `MasterRPG` app (and everything else) targets 26.0. No 26.4-only API was found in use, so the target-level overrides were removed (now inherits the project's 26.0 default); verified with a full build-for-testing pass.
6. **[High] Export traversal duplicated byte-for-byte across 7+ modules** — §9.4 — e.g. `Modules/PdfRPG/Controller/ExportController.swift:23-53` vs. `Modules/DiceRPG/Controller/ExportController.swift:23-53` (confirmed identical). A fix to export/cycle-handling logic must be hand-applied in every module.
7. **[Medium] `fatalError()` on a nil `managedObjectContext` in every module's Core Data helpers** — §5.3 — 11 modules' `Model/DataModel+Extensions.swift`. A legitimate CloudKit-merge race (object deleted concurrently) turns into a guaranteed crash instead of a no-op.
8. **[Medium] CloudKit sync merge errors are silently swallowed** — §5.9 — `Modules/CoreRPG/Controllable/SyncDataControllable.swift:65-67`. No log line exists if a merge throws, making sync bugs very hard to diagnose in the field.
9. **[Medium, NOT a quick win] Deprecated `.system.search` App Intents schema copy-pasted into all 12 modules** — §4.1 — will eventually stop compiling, but the replacement (`.system.searchInApp`) requires macOS 27; swapping it broke the build against this project's macOS 26 deployment target. Needs either a deployment-target bump (project-wide decision) or an `#available`-gated approach, not a one-pass mechanical fix.
10. **[Low/Medium, PARTIALLY FIXED] Dead code** — §9.1, §9.2 — `Modules/CoreRPG/DeleteMe/ItemSwiftDataPersistable.swift` (deleted; genuinely zero references) and five files' worth of commented-out dead implementations (deleted). **Correction:** `Modules/DiceRPG/0-Old/` and `Modules/SpaceRPG/0-Old/SpaceQuickLook.swift` were *not* dead — see the amendment above and §9.1 — and were left untouched.

---

## 2. Quick wins (≤30 min each)

Status as of the 2026-08-07 quick-wins pass — every item below was re-verified with real cross-reference searches (not just `project.pbxproj` grepping) and a full build-for-testing pass before/after:

- ~~Delete `Modules/DiceRPG/0-Old/` (953 LOC) and `Modules/SpaceRPG/0-Old/` (70 LOC)~~ — **CORRECTED, NOT APPLIED.** Re-verification found every file in both directories is transitively wired into live production UI (`Modules/DiceRPG/Controller/ViewController.swift` instantiates `RootDiceOverlay`/`DiceFocusActionBar`/`DiceFocusResult`/`DiceFocusRoll`/`DicePlayerRoot`, which internally chain through the rest of the "0-Old" files down to `OldDiceBag`; `Modules/SpaceRPG/Controller/ViewController.swift` instantiates `SpaceQuickLook` directly). The folder name is misleading; nothing here is dead. See §9.1.
- ✅ **Deleted `Modules/CoreRPG/DeleteMe/ItemSwiftDataPersistable.swift`** and its now-empty folder — re-verified zero references anywhere. See §9.1.
- ✅ **Deleted the five commented-out dead implementations** in `CRDT.swift`, `LinkRegisterController.swift` (also left a one-line comment explaining `effectedItems` is intentionally stubbed), `GlasseffectAll.swift`, `ObjectCache.swift`, `SpaceViewer.swift` (replaced the dead block with a short `TODO` marking the still-missing visionOS auto-fit feature). See §9.2.
- ~~Swap `.system.search` → `.system.searchInApp`~~ — **CORRECTED, NOT APPLIED.** Attempted across all 12 files; broke the build (`'searchInApp' is only available in macOS 27.0 or newer`, this project targets macOS 26.0). Reverted. See §4.1 for what an actual fix would require.
- ✅ **Fixed the three filename typos**: `InpectorUnavailableView.swift` → `InspectorUnavailableView.swift`, `GameEquiqment.swift` → `GameEquipment.swift`, `TaggedPrefernceKey.swift` → `TaggedPreferenceKey.swift`. See §9.13.
- ✅ **Fixed "Successfull" → "Successful"** — `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:108`.
- ✅ **Merged `Modules/CoreRPG/View/SupporterCrownView.swift` into `Modules/CoreRPG/Views/`** and deleted the singular-named folder. See §9.14.
- ✅ **Added `.accessibilityHidden(true)` to the hidden `ShareLink`** — `Modules/GameRPG/SetupViews/SharePlayButton.swift:40`. See §8.3.
- ~~Wrap or remove the 9 unconditional `print()` calls in `MyAiPlayground.swift`~~ — **CORRECTED, NOT APPLIED.** The file is an Xcode `#Playground` (from `import Playgrounds`) — canvas-only code, analogous to `#Preview`, never part of a shipped Release build. The `print()` calls are the intended output mechanism for that canvas. Not a real leak risk; left as-is. See §9.12.
- ✅ **Fixed `DiceRollerWidgetExtension`'s deployment target** — confirmed no 26.4-only API is used anywhere in `Sources/DiceRollerWidget/`, so removed the target-level `IPHONEOS_DEPLOYMENT_TARGET`/`MACOSX_DEPLOYMENT_TARGET`/`XROS_DEPLOYMENT_TARGET` overrides via Xcode's build-setting tooling; it now inherits the project's 26.0 default like every other target. See §4.6.

---

## 3. Concurrency

### 3.1 FoundryVTTDomainMapper blocks the Main Actor for the entire import-mapping pass
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift:179-260`; call site `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:154-170`
- **What:** `FoundryVTTDomainMapper` and its backing `FoundryMappingState` are declared `@MainActor`; `prepareReview()` awaits `FoundryVTTDomainMapper().map(...)` directly, so the whole document/folder/resource-reference mapping pass over a Foundry package runs synchronously on the main actor.
- **Why:** Unlike every sibling Foundry reader (`FoundryVTTImportReader`, `FoundrySystemPackageReader`, `UniversalVTTReader`), which explicitly offload parsing to `Task.detached`, this stage blocks the UI thread for the duration of a large-package import — exactly when the user is watching an import progress UI.
- **Action:** Make `FoundryVTTDomainMapper`/`FoundryMappingState` `nonisolated` (or a background actor) producing a `Sendable` result; hop to `@MainActor` only for the final UI-facing assignment.
- **Severity:** High

### 3.2 `Task.detached` file/network work without cancellation propagation
- **Location:** `Modules/CoreRPG/Files/FileManager+Coordination.swift:90-96`; `Modules/CoreRPG/Files/FileUrlDataController.swift:608-615`; `Sources/RPGShare/ItemProviderImporter.swift:154-161`; `Modules/CoreRPG/Cache/ResourceCache.swift:38-54`
- **What:** Each site launches `Task.detached(priority:) { ... }` and immediately `try await task.value` with no `withTaskCancellationHandler`/`task.cancel()` wiring — unlike the equivalent pattern used correctly in the Foundry readers.
- **Why:** A detached task doesn't inherit cancellation from its caller; if the awaiting `Task` is cancelled (view disappears mid-import, a subsequent load of the same cache key), the detached I/O keeps running, wasting battery/I/O and risking a race with the next load.
- **Action:** Wrap each with `withTaskCancellationHandler`, or replace `Task.detached` with a plain structured `Task { }` where detachment isn't actually required.
- **Severity:** Medium

### 3.3 Untracked, unnecessary `Task.detached` fire-and-forget work in SpaceRPG
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:383-392`; `Modules/SpaceRPG/Record/AppDataModel.swift:311-314`
- **What:** `SpaceViewer` detaches only to immediately hop back to `MainActor.run` for `generateCollisionShapes`, defeating the purpose of detaching; `AppDataModel`'s background cleanup task is similarly unmanaged.
- **Why:** Adds a pointless scheduling round-trip and leaves a dangling task if the view/model is torn down mid-generation.
- **Action:** For `SpaceViewer`, perform the work directly under `@MainActor` without detaching. For `AppDataModel`, store/cancel the cleanup task on teardown.
- **Severity:** Low

### 3.4 `AppDataModel.deinit` cleanup is dead code — teardown never runs
- **Location:** `Modules/SpaceRPG/Record/AppDataModel.swift:101-104`
- **What:** `deinit` contains only a commented-out `DispatchQueue.main.async { self.detachListeners() }`; nothing runs on deallocation.
- **Why:** `detachListeners()` (presumably tearing down subscriptions/capture session) is never called on teardown. The old GCD call was correctly identified as unsafe (a `nonisolated deinit` can't `await` actor-isolated cleanup), but no replacement was written — silently reintroducing whatever resource-retention issue the commented code was meant to fix.
- **Action:** Have `endCapture()`/state-transition code call `detachListeners()` explicitly before the object can deallocate, and delete the dead `deinit` body.
- **Severity:** Medium

### 3.5 `DebouncerModel` mixes `@Observable` with Combine `@Published`/`AnyCancellable`
- **Location:** `Modules/CoreRPG/Stores/DebouncerModel.swift:1-25`
- **What:** `DebouncerModel` is `@MainActor @Observable`, yet its `input` property is additionally `@ObservationIgnored @Published`, with debouncing implemented via `Combine`'s `$input.debounce(...).sink { }` and a stored `AnyCancellable`.
- **Why:** Reintroduces Combine's separate scheduling/cancellation model (and a `[weak self]` capture) for something modern Swift Concurrency can express without Combine, contrary to project convention.
- **Action:** Reimplement the debounce with a `Task`-based cancel-and-restart of `Task.sleep(for:)` on each `input` write.
- **Severity:** Medium

### 3.6 `GroupStateObserver` forces `ObservableObject` usage (accepted exception)
- **Location:** `Modules/GameRPG/SetupViews/SharePlayButton.swift:19-21`; `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:632`
- **What:** Apple's `GroupStateObserver` (from `GroupActivities`) conforms to `Combine.ObservableObject`; both files hold it via `@ObservedObject`/plain storage. This is the only `ObservableObject`-adjacent usage in the codebase.
- **Why:** Legitimate SDK-forced exception — Apple hasn't shipped an `@Observable` variant. Flagged for visibility, not as a violation.
- **Action:** No change needed; revisit if Apple ships an `@Observable` replacement.
- **Severity:** Low

### 3.7 `MasterController` mixes an explicit `Sendable` conformance with piecemeal `@MainActor` annotations
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:443-585`
- **What:** `final class MasterController: Sendable` stores a non-`Sendable`, `@MainActor`-isolated `root: GameRoot` and `gameModel`, but the class itself isn't `@MainActor`; some methods (`start()`, `stop()`) are individually `@MainActor` while others (`resetPlayers()`, `show(for:)`) rely on ad hoc `await`/`MainActor.run`.
- **Why:** Harder to audit than whole-type isolation (as `MasterControllerModel`/`GameRoot` already use); a future edit could easily forget an `await` before touching `gameModel`/`root` from a non-isolated method.
- **Action:** Mark `MasterController` `@MainActor` directly, dropping the explicit `Sendable` and the redundant per-method annotations.
- **Severity:** Low

### 3.8 `nonisolated(unsafe)` `Codable.encode(to:)` workaround duplicated across all 11 domain models
- **Location:** `Modules/PdfRPG/Model/PdfModel.swift:253`; `Modules/CoreRPG/Fake/FakeItemModel.swift:98`; `Modules/DiceRPG/Model/DiceModel.swift:646`; `Modules/WeatherRPG/Model/WeatherModel.swift:398`; `Modules/AdventureRPG/Model/AdventureModel.swift:330`; `Modules/CharacterRPG/Model/ValueModel.swift:499`; `Modules/PhotoRPG/Model/PhotoModel.swift:281`; `Modules/RuleRPG/Model/RuleModel.swift:753`; `Modules/GeneratorRPG/Model/GeneratorModel.swift:272`; `Modules/MapRPG/Model/MapModel.swift:718`; `Modules/SpaceRPG/Model/SpaceModel.swift:272`; `Modules/TableRPG/Model/TableModel.swift:403`; `Modules/AudioRPG/Model/AudioModel.swift:271`
- **What:** Every `@MainActor @Observable` domain model implements `nonisolated func encode(to:)` via `nonisolated(unsafe) let encoder = encoder; MainActor.assumeIsolated { ... }` to satisfy `Encodable` while reading main-actor-isolated properties.
- **Why:** Safe only because every current call site wraps encoding in `MainActor.run` first (`ExportControllable.swift:197`) — but `MainActor.assumeIsolated` is a *runtime*, not compile-time, guarantee. Any future call to `JSONEncoder().encode(model)` from a background `Task`/`Task.detached` (several exist in this codebase) will trap instead of failing to compile.
- **Action:** Centralize the pattern in one shared helper so the invariant is documented in one place, or provide a `Sendable` snapshot type for background encoding so `nonisolated(unsafe)` isn't needed at all.
- **Severity:** Medium

### 3.9 `@unchecked Sendable CoreDataChangeObserver` safety assumption is undocumented
- **Location:** `Modules/CoreRPG/Persistence/CoreDataChangeObserver.swift:14-49`
- **What:** `CoreDataChangeObserver` is `final class ... @unchecked Sendable`, deliberately not `@MainActor` because Core Data posts its merge notification synchronously on the originating context's own queue; it hops via `performAndWait` before extracting `Sendable` `UUID`s.
- **Why:** Correctly reasoned (confirmed by an in-code comment referencing prior breakage from an incorrect `@MainActor` annotation), but its safety depends on `observeCoreDataChanges` never being invoked twice concurrently on the same instance — an assumption that isn't stated anywhere.
- **Action:** Add a doc comment stating the single-call-per-instance assumption, or make `observer` an array so multi-observer usage is safe by construction.
- **Severity:** Low

### 3.10 Widespread `@preconcurrency import` masks Sendable diagnostics at 11 boundaries
- **Location:** `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift`, `CoreDataController.swift`, `CloudKitCoreDataPersistenceController.swift`, `PersistentHistoryTrackerManager.swift`, `CoreDataChangeObserver.swift`; `Modules/GameRPG/SharePlay/RPGSharePlayController.swift`; `Modules/GameRPG/Table3D/GroupActivityManager.swift`; `Modules/PdfRPG/Pdf/SearchBar.swift`, `SelectionBar.swift`; `Modules/PdfRPG/Root/ViewerRootView.swift`; `Modules/SpaceRPG/Record/ReconstructionProgressView.swift`
- **What:** Eleven files use `@preconcurrency import` for `CoreData`, `GroupActivities`, or `PDFKit` to suppress Sendable diagnostics on Apple's not-yet-audited types.
- **Why:** Standard, currently necessary workaround — but means the compiler isn't checking Sendable-crossing usage of `NSManagedObjectContext`/`GroupSession` at these boundaries; correctness depends entirely on manual discipline (found sound in sampled files) rather than the type system.
- **Action:** No immediate action; remove `@preconcurrency` per-import once Apple ships Sendable-audited versions.
- **Severity:** Low

---

## 4. API modernity

### 4.1 Deprecated `.system.search` App Intents schema used identically in all 12 modules
- **Location:** `Modules/CharacterRPG/Intent/CharacterManagementIntents.swift:91`; `Modules/RuleRPG/Intent/RuleManagementIntents.swift:91`; `Modules/GeneratorRPG/Intent/GeneratorManagementIntents.swift:94`; `Modules/DiceRPG/Intent/DiceManagementIntents.swift:89`; `Modules/SpaceRPG/Intent/SpaceManagementIntents.swift:94`; `Modules/PhotoRPG/Intent/PhotoManagementIntents.swift:93`; `Modules/AudioRPG/Intent/AudioManagementIntents.swift:93`; `Modules/WeatherRPG/Intent/WeatherManagementIntents.swift:92`; `Modules/PdfRPG/Intent/PdfManagementIntents.swift:91`; `Modules/TableRPG/Intent/TableManagementIntents.swift:92`; `Modules/MapRPG/Intent/MapManagementIntents.swift:91`; `Modules/AdventureRPG/Intent/SearchAdventuresIntent.swift:8`
- **What:** Every module's `ShowInAppSearchResultsIntent` is declared `@AppIntent(schema: .system.search)` — the only warnings a clean build actually emits (confirmed by a full clean build, 13 raw occurrences deduplicating to these 12 sites).
- **Why:** Same deprecated schema identifier copy-pasted into all 12 modules; will eventually be removed, and the 12 identical warnings currently hide any other real warning in build logs.
- **Action:** ~~Replace `.system.search` with `.system.searchInApp` in one pass~~ — **attempted and reverted**: `.system.searchInApp` carries `@available(macOS 27.0, *)` (confirmed by the build error `'searchInApp' is only available in macOS 27.0 or newer`), and this project's `MasterMac` target/project default is macOS 26.0 (see §4.6 for the sibling deployment-target issue — this project is clearly mid-transition on OS floors). A real fix needs either: (a) a project-wide macOS 26→27 deployment bump, which is a product decision, not a quick win; or (b) keeping `.system.search` until that bump happens. Not mechanical; do not attempt this again without also raising `MACOSX_DEPLOYMENT_TARGET`.
- **Severity:** Medium

### 4.2 Manual `UIActivityViewController` + scene/window traversal instead of `ShareLink`
- **Location:** `Modules/GeneratorRPG/BasicAI/View/MessageBubbleView.swift:222-245`
- **What:** `shareMessage()` builds a `UIActivityViewController` and locates a presenter via `UIApplication.shared.connectedScenes.first as? UIWindowScene`, `.windows.first`, `.rootViewController`.
- **Why:** Grabbing "first" scene/window is unreliable on iPad/visionOS multi-window configurations, and duplicates functionality the codebase already uses correctly elsewhere (`ShareLink` in `SharePlayButton.swift:40`).
- **Action:** Replace with SwiftUI's `ShareLink`.
- **Severity:** Medium

### 4.3 Legacy `Formatter` subclasses instead of `FormatStyle` — FIXED
- **Location:** `Modules/CoreRPG/Editors/TextDoubleEditor.swift:116-118` (pre-fix); `Modules/CharacterRPG/Model/Calculator.swift:28-31` (pre-fix); `Modules/CharacterRPG/Controller/EditController.swift:434-447` (pre-fix); `Modules/SpaceRPG/Record/CaptureFolderManager.swift:140-141` (pre-fix)
- **What:** Four sites constructed `NumberFormatter()` (three) or `ISO8601DateFormatter()` (one) instead of `FormatStyle`/`ParseStrategy`.
- **Why:** Explicitly forbidden by project convention; all four were simple literal parse/format operations with direct modern equivalents.
- **Action taken:** ✅ Replaced all four with `try? Double(text, format: .number.locale(...))` (and `try? Int(...)` for the integer-only `parseInteger` sibling in `EditController.swift`), and `Date().formatted(.iso8601)` for the timestamp folder name. Verified via `DocumentationSearch` that `Double(_:format:)`/`Int(_:format:)` parsing initializers exist and behave equivalently to the old locale-aware `NumberFormatter().number(from:)` path. Confirmed with a full `buildForTesting` pass.
- **Severity:** Low — resolved.

### 4.4 `replacingOccurrences(of:with:)` instead of `replacing(_:with:)` — FIXED
- **Location (pre-fix):** `Modules/CoreRPG/ItemList/EntryDataEditable.swift:296`; `Modules/CoreRPG/Controllable/EditControllable.swift:565`; `Modules/CoreRPG/Controllable/LinkControllable.swift:125,223,228,230,243,246`; `Modules/CoreRPG/Extensions/String+MarkDown.swift:56`; `Modules/CoreRPG/Links/LinkReplaceController.swift:67,69,95,97,113,175,187`; `Modules/CoreRPG/Files/LocationFileManager.swift:45,48`; `Modules/CoreRPG/Text/EntryTextParser.swift:115-116`; `Modules/DiceRPG/Model/RawDice.swift:119`; `Modules/CharacterRPG/Controller/LinkController.swift:225,236,280`; `Modules/CharacterRPG/Model/Calculator.swift:159`; `Modules/GeneratorRPG/BasicAI/Engine/FoundationManager.swift:53` (26 sites confirmed by re-grep; original count of 28 was a slight overcount)
- **What:** 26 call sites used the old API for plain literal substring replacement, two of them (`EntryDataEditable.swift:296`, and two duplicated in `LinkReplaceController.swift`) via the `range:`-taking overload.
- **Why:** Project convention prefers `replacing(_:with:)`; all sites were mechanical, no `NSString`/regex dependency.
- **Action taken:** ✅ Replaced all 26 with `.replacing(_:with:)`; the three `range:`-taking call sites used `.replacing(_:with:subrange:)` instead (confirmed via `DocumentationSearch` that this overload exists on `RangeReplaceableCollection` and accepts the same `Range<String.Index>` the old `range:` parameter did). Three files had duplicate identical lines (`LinkControllable.swift` ×3, `LinkReplaceController.swift` ×2×2, `LocationFileManager.swift` ×2) — fixed with a scoped `replace_all` per identical snippet, safe since each duplicate site does the exact same operation. Confirmed with a full `buildForTesting` pass.
- **Severity:** Low — resolved.

### 4.5 Dead `@available(iOS 17.0, ...)` guard below the project's deployment target — FIXED
- **Location:** `Modules/CoreRPG/Navigator/Extensions/LazyState.swift:28` (pre-fix)
- **What:** A vendored `@propertyWrapper` (attributed to "Runes" by Michael Long, per its header comment) was guarded with `@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)`, all below this project's 26.0 minimum.
- **Why:** Permanently true given the project's deployment targets — dead code that obscured the type's real requirements.
- **Action taken:** ✅ Removed the redundant `@available` attribute and replaced it with a short comment explaining it's vendored and why the guard was dropped, so a future diff against upstream "Runes" stays legible. Confirmed with a full `buildForTesting` pass.
- **Severity:** Low — resolved.

### 4.6 Widget extension deployment target (26.4) exceeded the host app's (26.0) — FIXED
- **Location:** `DiceRollerWidgetExtension` target build settings (previously `IPHONEOS_DEPLOYMENT_TARGET`/`MACOSX_DEPLOYMENT_TARGET`/`XROS_DEPLOYMENT_TARGET` overrides in `MasterRPG.xcodeproj/project.pbxproj`) vs. project-level defaults inherited by the `MasterRPG` app target
- **What:** `DiceRollerWidgetExtension` explicitly overrode `IPHONEOS_DEPLOYMENT_TARGET`/`MACOSX_DEPLOYMENT_TARGET`/`XROS_DEPLOYMENT_TARGET` to `26.4`, while the host app and every other target inherit the project-level `26.0` with no override.
- **Why:** An app extension's deployment target should never exceed its containing app's. On an OS version where `26.0 ≤ OS < 26.4`, the host app installs fine but the Dice widget/Live Activity extension can't load — a silent feature loss for early-26.x adopters.
- **Action taken:** Grepped `Sources/DiceRollerWidget/` for any `@available(iOS 26.4` / 26.4-specific API usage — found none. Removed the three target-level overrides via `mcp__xcode__UpdateTargetBuildSetting` (not by hand-editing `project.pbxproj`, per project convention) so the extension now inherits the project's `26.0` default like every other target. Verified with a full `buildForTesting` pass — succeeded.
- **Severity:** High (now resolved)

### 4.7 `GeometryReader` used where newer scroll/layout APIs may suffice
- **Location:** `Modules/CoreRPG/List/ExpandableBaseView.swift:60`; `Modules/CoreRPG/Views/StretchingHeaderView.swift:13` (see §8.1-8.2 for a deeper, independently-verified look at these two); `Modules/WeatherRPG/View/InlineRowViewer.swift:23`; `Modules/WeatherRPG/View/OverlayViewer.swift:19`; `Modules/WeatherRPG/Root/ViewerRootView.swift:22`; `Modules/PhotoRPG/Root/ViewerRootView.swift:64`; `Modules/SpaceRPG/Record/TutorialPageView.swift:19`; `Sources/RPGShare/SharingView.swift:73`
- **What:** Nine views (excluding two visionOS `GeometryReader3D` uses with no simpler equivalent) still use `GeometryReader` for sizing/parallax.
- **Why:** Project convention prefers `containerRelativeFrame()`/`visualEffect()`; `GeometryReader` forces `.infinity`-sized child layout and re-renders the subtree on every geometry change.
- **Action:** Audit each site against `containerRelativeFrame()`/`visualEffect()`/`onScrollGeometryChange`; `StretchingHeaderView` is the strongest candidate (see §8.1).
- **Severity:** Low

### 4.8 `onTapGesture` in preview code models the wrong pattern — FIXED
- **Location:** `Modules/CoreRPG/List/ExpandableBaseView.swift:94,118` (pre-fix)
- **What:** Two `#Preview` blocks attached `.onTapGesture { withAnimation { isExpanded.toggle() } }` to a `Text` row instead of using `Button`.
- **Why:** Preview-only, so low risk, but set a copy-pasteable bad example for the disclosure-row pattern it demonstrates.
- **Action taken:** ✅ Wrapped each header's `Text` as a `Button` label with `.buttonStyle(.plain)` (to keep the original unstyled look) and moved the `withAnimation { isExpanded.toggle() }` into the button's action, dropping the now-unnecessary `.contentShape(Rectangle())`/`.onTapGesture`. Confirmed with a full `buildForTesting` pass.
- **Severity:** Low — resolved.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Game log resolves Character-tied entries against the wrong module root — FIXED
- **Location:** `Modules/GameRPG/Controller/LogGameController.swift:189-190` (pre-fix)
- **What:** In `name(for module:itemId:)`, the `case .value:` branch (the Character/"values" module) looked up the display name via `root?.photoRoot.itemControllable.nameSync(itemId:)` instead of the character root.
- **Why:** Any game-log entry referencing a Character item resolved in the wrong module — falling back to a raw UUID string, or, if a Photo happens to share that UUID, showing an entirely wrong name.
- **Action taken:** ✅ Routed the `.value` case through `root?.characterRoot.itemControllable.nameSync(itemId:)`; added the now-required `import CharacterRPG` (the file had never referenced `characterRoot` before, so the module wasn't previously imported). Verified with a full `buildForTesting` pass.
- **Severity:** High — **verified**, see §12. Resolved.

### 5.2 `fatalError()` in `@unknown default` across five switches — FIXED
- **Location (pre-fix):** `Modules/GameRPG/Controller/LogGameController.swift:203-204`; `Modules/GameRPG/Controller/PlayerController.swift:2044`; `Modules/GameRPG/Controller/MasterController.swift:1273-1274`; `Modules/RolePlayGameKit/Model/AppModel.swift:412-413`; `Modules/RolePlayGameKit/Model/DataBaseModel.swift:163-164`
- **What:** Five switches crashed with a bare `fatalError()` in `@unknown default` instead of degrading gracefully. **Correction:** four are over the cross-module `NetworkModules` enum as originally described, but `DataBaseModel.swift:163-164` is actually a switch over the unrelated `CoreDataInitError` enum (`loadModel`/`removeFile`/`migration`/`creation`) — a different, smaller mischaracterization caught during the fix.
- **Why:** Not reachable with today's enum cases, but `MasterController`/`PlayerController`'s switches sit directly in the incoming-network-message dispatch path — adding one case to a shared enum without touching every site turns a routine feature addition into a guaranteed crash.
- **Action taken:** ✅ Each now falls back gracefully instead of crashing, matching the idiom already used elsewhere in its own switch: `PlayerController`/`MasterController` log via `Logger.networking.error(...)` and return `nil` (mirroring `MasterController`'s existing "not supported" case); `LogGameController` returns `itemId.uuidString` (mirroring its own `.none`/`.game` cases); `AppModel.windowPlacement` returns `.leading(SceneId.game.rawValue)` (mirroring its own default-ish cases); `DataBaseModel` sets a generic localized `errorMessage` (mirroring its sibling `case`s) instead of crashing. Verified with a full `buildForTesting` pass.
- **Severity:** Medium — resolved.

### 5.3 `fatalError()` when `managedObjectContext` is nil, repeated across every module's Core Data extension — FIXED (with a corrected root-cause understanding)
- **Location (pre-fix):** `Modules/MapRPG/Model/DataModel+Extensions.swift:32,54,64,85,106,118`; `Modules/PdfRPG/Model/DataModel+Extensions.swift:32`; `Modules/DiceRPG/Model/DataModel+Extensions.swift:32`; `Modules/WeatherRPG/Model/DataModel+Extensions.swift:32`; `Modules/AdventureRPG/Model/DataModel+Extensions.swift:32`; `Modules/CharacterRPG/Model/DataModel+Extensions.swift:32,58`; `Modules/PhotoRPG/Model/DataModel+Extensions.swift:32`; `Modules/GeneratorRPG/Model/DataModel+Extensions.swift:32`; `Modules/SpaceRPG/Model/DataModel+Extensions.swift:32`; `Modules/TableRPG/Model/DataModel+Extensions.swift:32`; `Modules/AudioRPG/Model/DataModel+Extensions.swift:32`
- **What:** Helper accessors like `entryOrNew(for:)`/`mapPinOrNew(for:)` called `fatalError("ManagedObjectContext should be available!")` whenever the parent object's `managedObjectContext` was `nil`.
- **Correction to the original "CloudKit merge race" theory:** traced every call site (all live inside each module's `DataController.applySnapshot`, itself always invoked synchronously from inside the same `context.perform { updater(...) }` block that fetched-or-created the receiver — see `CoreDataController.swift`'s `replace`/`queueReplace`). Core Data serializes all work on a context through `context.perform`, so nothing can delete the receiver out from under this code mid-block; the CloudKit-merge race the original finding described isn't actually reachable through these call paths. A full non-crashing refactor (changing all 17 definitions plus their ~17 call sites across 11 modules' CloudKit-synced save pipelines to return `Optional` and propagating `guard let`/`compactMap` through each) was assessed and rejected as disproportionate risk for a currently-unreachable path — that scale of change to save-transaction code isn't something to do without the ability to exercise real CloudKit sync in testing.
- **Action taken:** ✅ Instead, matched the codebase's own existing convention for this exact scenario — `Modules/RuleRPG/Model/DataModel+Extensions.swift` already handles it via `preconditionFailure` with a descriptive message rather than a bare `fatalError`. Applied the same pattern (still traps if the invariant is ever violated, but with a clear, type-specific diagnostic) to all 11 modules' `entryOrNew`/`mapPinOrNew`/`displyConfigOrNew`/`newCoordinate`/`coordinateOrNew`/`photoOrNew` helpers. Verified with a full `buildForTesting` pass.
- **Severity:** Medium → this is better characterized as Low given the reachability finding above; resolved either way.

### 5.4 Force-unwrapped `URL(string:)!` built from unescaped user-provided text — FIXED
- **Location (pre-fix):** `Modules/CoreRPG/Controllable/EditControllable.swift:585-586`; `Modules/PhotoRPG/Controller/PhotoDataController.swift:19`; `Modules/CoreRPG/Files/CloudDocumentController.swift:61`
- **What:** User-editable text (an item name, or a path segment decoded from `URL.pathComponents`) was interpolated into a string and passed straight into `URL(string:)!`.
- **Why:** `URL(string:)` returns `nil` for strings containing characters not valid in a URL component (`#`, unencoded `%`/`?`), plausible in user-typed names. Force-unwrapping crashed the app on save.
- **Action taken:** ✅ All three now build the `URL` via `.appending(path:)`/`.appending(component:)` from a safe `URL(string: "/")!` base instead of parsing an interpolated string — `.appending(component:)` percent-encodes its argument, so it can never fail, eliminating the force-unwrap entirely rather than just handling its failure. Verified via `DocumentationSearch` that `.appending(component:)` percent-encodes disallowed characters (unlike `.appending(path:)`, which treats `/` as a literal separator — used for the pre-existing `folder` prefix, which is already `/`-joined). Confirmed with a full `buildForTesting` pass.
- **Severity:** High — **verified**, see §12. Resolved.

### 5.5 Force-try loading bundled RealityKit tabletop assets in `init` — PARTIALLY FIXED (with a corrected assessment)
- **Location (pre-fix):** `Modules/GameRPG/Table3D/GameEquipment.swift` (renamed from `GameEquiqment.swift` in §9.13) — `Die20` init (the struct's actual name; the audit's original "D20" was the human-readable die name, not the Swift type), entity load; `Die` init, both entity and audio load.
- **Correction:** `entity: Entity` is a **required, non-optional** property of Apple's own `EntityEquipment` protocol (TabletopKit) — confirmed via `DocumentationSearch`, whose official sample code force-loads bundled RealityKit assets the exact same way (`self.entity = try! Entity.load(...)`). There is no way to "hide the 3D die" on a load failure without providing *some* valid `Entity`, so the entity load cannot be made fully non-crashing without inventing a fallback placeholder mesh — out of scope for this pass. The audio load, however, is not protocol-required and was a legitimate fully-fixable case (already handled correctly for `Die20`, not for `Die`).
- **Action taken:** Entity loads (both structs) now wrap `Entity.load` in `do/catch` and crash via `preconditionFailure` with a specific diagnostic message instead of a bare `try!` — same "still fatal, but diagnosable" upgrade used throughout this pass, appropriate for a required, shipped, non-user-triggerable asset. ✅ `Die`'s audio load is now **fully fixed**: `Die.audioPlaybackController` changed from non-optional to `AudioPlaybackController?`, its `AudioFileResource.load` wrapped in `do/catch` logging via `Logger.gameTable.error(...)` and falling back to `nil` (mirroring `Die20`'s already-correct pattern exactly), and `playTossSound()` updated to `guard let`. Confirmed with a full `buildForTesting` pass.
- **Severity:** Medium — audio-load half resolved; entity-load half improved (better diagnostics) but inherently can't be made non-fatal given the protocol constraint.

### 5.6 Force-cast not covered by the surrounding `do/catch` — FIXED
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:365,393,427` (pre-fix)
- **What:** `try self.context.fetch(request) as! [DataType]` — the `as!` sat outside the throwing part of the expression, so a failed cast trapped instead of being caught by the immediately surrounding `catch { Logger....error(...) }`.
- **Action taken:** ✅ Changed all three to `guard let ... = try ... as? [DataType] else { Logger.coreDataController.error(...); return [] /* or nil */ }`, routing a cast failure through the same graceful-return path each function already uses for a thrown fetch error. Verified with a full `buildForTesting` pass.
- **Severity:** Medium — resolved.

### 5.7 Force-unwrapped `hubControllable` repeated across 10 modules' `ExportController` — FIXED
- **Location (pre-fix):** `Modules/PdfRPG/Controller/ExportController.swift:13-15`; `Modules/DiceRPG/Controller/ExportController.swift:13-15`; `Modules/AudioRPG/Controller/ExportController.swift:14-16`; `Modules/MapRPG/Controller/ExportController.swift:26-28`; `Modules/CharacterRPG/Controller/ExportController.swift:23-25`; `Modules/PhotoRPG/Controller/ExportController.swift:13-15`; `Modules/SpaceRPG/Controller/ExportController.swift:13-15`; `Modules/GeneratorRPG/Controller/ExportController.swift:13-15`; `Modules/TableRPG/Controller/ExportController.swift:18-20`; `Modules/WeatherRPG/Controller/ExportController.swift:15-17`
- **What:** `var hubControllable: any RootExportControllable { get { exportModel.hubControllable! } ... }` force-unwrapped a late-bound dependency in all 10 modules, while `Modules/RuleRPG/Controller/ExportController.swift:31-39` already fixed this same pattern with a `preconditionFailure` and a descriptive message.
- **Action taken:** ✅ Applied RuleRPG's exact `preconditionFailure("<Module> export requires its Adventure export hub after setup.")` pattern to all 10 modules' `hubControllable` getters. Verified with a full `buildForTesting` pass.
- **Severity:** Low — resolved.

### 5.8 Empty `catch {}` swallows Siri intent-donation failures — FIXED
- **Location (pre-fix):** `Modules/PdfRPG/Intent/OpenPdfIntent.swift:48`; `Modules/DiceRPG/Intent/OpenDiceIntent.swift:48`; `Modules/WeatherRPG/Intent/OpenWeatherIntent.swift:49`; `Modules/AdventureRPG/Intent/OpenAdventureIntent.swift:51`; `Modules/CharacterRPG/Intent/OpenCharacterIntent.swift:49`; `Modules/PhotoRPG/Intent/OpenPhotoIntent.swift:48`; `Modules/GeneratorRPG/Intent/OpenGeneratorIntent.swift:49`; `Modules/MapRPG/Intent/OpenMapIntent.swift:49`; `Modules/SpaceRPG/Intent/OpenSpaceIntent.swift:49`; `Modules/TableRPG/Intent/OpenTableIntent.swift:49`; `Modules/AudioRPG/Intent/OpenAudioIntent.swift:49`
- **What:** `try await IntentDonationManager.shared.donate(intent:)` failures were caught with an entirely empty `catch {}` in every module's `donateSiriViewingIntent`.
- **Action taken:** ✅ Added a new `Logger.appIntents` category to the shared `Logger` extension (`Modules/CoreRPG/Debug/Logging.swift`, alongside the existing per-subsystem categories), then logged each failure at `.debug` level with the specific intent name in all 11 files (plus the `import os.log` each file was missing). Verified with a full `buildForTesting` pass.
- **Severity:** Low — resolved.

### 5.9 CloudKit merge errors silently swallowed in the shared sync path — FIXED
- **Location:** `Modules/CoreRPG/Controllable/SyncDataControllable.swift:65-67` (pre-fix)
- **What:** `updateFromSync(deletedIds:insertedIds:updatedIds:)` — used by every module's `SyncDataController` via protocol extension — wrapped the CloudKit merge in `do { ... } catch { /* comment only, no logging */ }`.
- **Action taken:** ✅ Added a new `Logger.syncDataControllable` category (no existing Logger category fit; `CloudKitOperationCounter`, referenced in the original finding's Action, is a separate operation-counting utility, not a logger) and logged the error with the deleted/inserted/updated counts in the `catch`, keeping the existing non-fatal retry behavior. Added the file's missing `import os.log`. Verified with a full `buildForTesting` pass.
- **Severity:** Medium — resolved.

---

## 6. Security

### 6.1 Hardcoded, world-shared TLS pre-shared key for local-network (Bonjour) game pairing
- **Location:** `Modules/GameRPG/Network/GameSecurity.swift:6-8`; `Modules/GameRPG/Network/NWParameter+GameMaster.swift:19-61`; `Modules/GameRPG/Network/ListenerManager.swift:124`
- **What:** `GameSecurity.passcode = "GameMasterCode"` is a compile-time constant, identical in every install, used as the sole material for the `NWParameters` TLS pre-shared key that both `NWListener` (master) and `NWConnection` (player) use to "pair" on the local network — per the doc comment, "so only MasterRPG peers can pair."
- **Why:** Because the string is fixed and trivially extractable from the shipped binary, it authenticates nothing about *who* may join a specific session — it only distinguishes MasterRPG traffic from generic LAN traffic. Any device on the same network running the app (or a reimplementation using the extracted string) can complete the TLS handshake, since there's no additional per-session pairing code/PIN checked anywhere in `ListenerManager`/`MasterController` before a connection is handed to the message pipeline.
- **Action:** Derive the PSK from something session-specific (a code shown to the player to type in, or exchanged only after user-visible pairing confirmation); treat the current scheme as protocol tagging, not authentication.
- **Severity:** High — **verified**, see §12.

### 6.2 iCloud-container/user-bearing file paths logged with `.public` privacy
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:506,515,517,523`; `Modules/CoreRPG/Files/FileBookmarkController.swift:116`; `Modules/CoreRPG/Files/FileUrlDataController.swift:131,339`
- **What:** `Logger` calls interpolate `localFileUrl.rawUrl.absoluteString`/`url.absoluteString` with `privacy: .public`, disabling os_log's automatic redaction.
- **Why:** On macOS these URLs point under the user's iCloud container path, so the username and local file layout end up unredacted in Console.app/sysdiagnose captures — unnecessary PII exposure for routine import/bookmark logging.
- **Action:** Use `privacy: .private` (default) for absolute URLs, or log only the last path component/file UUID as already done elsewhere in the same file.
- **Severity:** Medium

### 6.3 Redundant, non-standard `aps-environment` entitlement hardcoded to "development"
- **Location:** `Resources/MasterRPG.entitlements:5-7`; `Resources/MasterTV.entitlements:5-6`; `Sources/RPGShare/RPGShare.entitlements:5-7`
- **What:** The real Apple key is `aps-environment`; `com.apple.developer.aps-environment` (present alongside it in two files) isn't a documented Apple entitlement and looks like a copy/paste duplicate. Both real keys are hardcoded to `"development"`.
- **Why:** With manually-committed entitlements (vs. Xcode-managed signing that rewrites this at Archive time), a release build could ship with the development APNs environment.
- **Action:** Remove the stray duplicate key; confirm the release build pipeline overrides `aps-environment` to `production` for archives.
- **Severity:** Low

---

## 7. Performance

### 7.1 `NSFetchRequest` without `fetchBatchSize` for app-wide tag/link tables
- **Location:** `Modules/CoreRPG/Controllable/TagController.swift:36-37`; `Modules/CoreRPG/Links/LinkRegisterController.swift:29-30`
- **What:** `TagDataModel.fetchRequest()`/`LinkReferenceDataModel.fetchRequest()` execute with no `fetchBatchSize`, materializing every tag and every cross-item link reference in the store at once.
- **Why:** Both tables grow with every item/entry in every module, so this is an unbounded, unbatched fetch on every reload of the tag/link caches as a campaign's data grows.
- **Action:** Set a `fetchBatchSize` (e.g. 200-500) on both requests.
- **Severity:** Medium

### 7.2 Full-table reconciliation triggered by every CloudKit deletion notification
- **Location:** `Modules/CoreRPG/Controllable/SyncDataControllable.swift:32-45`
- **What:** On any non-empty `deletedIds`, the handler calls `dataControllable.fetchIds()` — every id currently in the store — and diffs it against the full in-memory item set, rather than resolving only the reported `deletedIds`.
- **Why:** For modules with large item counts, a single-item deletion notification triggers an O(n) full-table fetch and diff instead of an O(k) targeted removal, on every module's sync controller simultaneously.
- **Action:** Use the reported `deletedIds` directly to remove matching in-memory items; reserve full reconciliation for a periodic/startup pass.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 `StretchingHeaderView`'s `GeometryReader` recomputes on every scroll frame
- **Location:** `Modules/CoreRPG/Views/StretchingHeaderView.swift:12-18`
- **What:** The scroll-linked stretch/parallax header reads `proxy.frame(in: .global).minY` inside a `GeometryReader` wrapping the whole header content, recomputing `height(for:)`/`offset(for:)` on every layout pass while the enclosing `List`/`ScrollView` scrolls.
- **Why:** `GeometryReader` forces its content to `.infinity` sizing and reruns on every geometry change; reading `.global` coordinates also breaks if the header is ever presented inside a sheet/`NavigationStack` with its own coordinate space. This is exactly the pattern `visualEffect(_:)`/`onScrollGeometryChange` were introduced to replace.
- **Action:** Rewrite using `visualEffect(_:)` keyed to scroll offset, or `onScrollGeometryChange`, so the stretch effect doesn't force a `GeometryReader` layout pass per scroll frame.
- **Severity:** Medium

### 8.2 `ExpandableBaseView`'s frame-measurement `GeometryReader` re-triggers every animation frame
- **Location:** `Modules/CoreRPG/List/ExpandableBaseView.swift:22-27,52-74`
- **What:** `expandedContent` applies `.getFrame($expansionFrame, space: .local)` — a `background(GeometryReader { ... }.preference(...))` — while its `.opacity(animatableData)` is being interpolated by SwiftUI's `Animatable` machinery during expand/collapse.
- **Why:** The background `GeometryReader`/`PreferenceKey` frame-measurement modifier re-runs on every interpolated animation frame (SwiftUI calls `body` per-frame for `Animatable` types), not just once per state change, which is more layout work than the animation needs and can cause visible jank on the expand/collapse transition.
- **Action:** Cache the measured frame once (e.g. only re-measure when `content` identity changes, not every `animatableData` tick), or drive the expansion height from a value already known without re-measuring per frame.
- **Severity:** Medium

### 8.3 `SharePlayButton`'s hidden `ShareLink` duplicates VoiceOver elements — FIXED
- **Location:** `Modules/GameRPG/SetupViews/SharePlayButton.swift:38-41`
- **What:** `ShareLink(item: activity, preview: ...).hidden()` sat in a `ZStack` under a visible `Button(text, systemImage: "shareplay")` with the same label — `.hidden()` removes the `ShareLink` visually but does not remove it from the accessibility tree.
- **Why:** VoiceOver users can swipe onto an invisible second control with the same effective purpose as the visible Button, which is confusing and clutters the accessibility rotor.
- **Action taken:** ✅ Added `.accessibilityHidden(true)` to the hidden `ShareLink`. Verified with a `buildForTesting` pass.
- **Severity:** Medium — resolved.

### 8.4 `SharePlayButton` nests a `Task` inside a `Task.detached` just to hop back to `MainActor`
- **Location:** `Modules/GameRPG/SetupViews/SharePlayButton.swift:44-54`
- **What:** The button action runs `Task.detached { do { try await activity.activate() } catch { print(...); Task { @MainActor in isActivationErrorViewPresented = true } } }` — a detached task containing a further nested `Task` solely to reach the main actor for the error-alert flag.
- **Why:** Unnecessary indirection; a UI-invoked action doesn't need `Task.detached` at all, and the nested `Task { @MainActor in }` adds a second scheduling hop for no benefit.
- **Action:** Use a single structured `Task { @MainActor in ... }` (or `Task { ... }` with an explicit `await MainActor.run` only around the flag write) instead of detaching.
- **Severity:** Low

### 8.5 `FoundryRuleImportView.swift`'s filename doesn't match its primary type
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportView.swift:7`
- **What:** The file defines `struct FoundryImportView: View` (plus ~10 well-scoped private child View structs) — the type is named `FoundryImportView`, not `FoundryRuleImportView`. **Correction to an earlier duplication-pass note:** despite being 866 lines, this file is *not* a "computed-property soup" violation of the project's view-composition convention — it's already cleanly decomposed into ~10 dedicated `private struct ... View` types (`FoundryPreflightView`, `FoundrySourceIdentitySection`, `FoundryExternalImportReviewView`, etc.), each with its own small `body`. No split is needed on structural grounds.
- **Why:** The filename/type mismatch is real friction for fuzzy-file-search; the file being long is a byproduct of hosting the whole VTT-import flow's screens together, not of any one view being overgrown.
- **Action:** Rename the file to `FoundryImportView.swift` to match its primary type (or rename the type to match the file, whichever the module's naming convention prefers). Do not spend time splitting it further on view-structure grounds — see §9.11 for the corrected framing.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Files to delete outright
- ~~`Modules/DiceRPG/0-Old/` (953 LOC, 15 files) — confirmed 0 build references; superseded dice-bag/roll-result UI.~~ **RETRACTED — this was wrong.** `grep -c "0-Old" project.pbxproj` returning 0 does not mean unbuilt: this project uses Xcode 16 file-system-synchronized groups (`PBXFileSystemSynchronizedRootGroup`), where whole-folder membership is implicit and never appears as a path string in `project.pbxproj`. A real build log shows every file in this directory being compiled into the `DiceRPG` target, and cross-reference greps show `Modules/DiceRPG/Controller/ViewController.swift` directly instantiates `RootDiceOverlay`, `DiceFocusActionBar`, `DiceFocusResult`, `DiceFocusRoll`, and `DicePlayerRoot` from this folder — which in turn internally chain through `DiceOverlay` → `DiceInlineEditor` → `OldDiceBag`, `DiceGameResult` → `DiceQuickEditor`, and `DicePlayer` → `DieViewerView`. Every one of the 15 files is live. **Not deleted.** The folder name ("0-Old") is simply misleading — if a redesign superseding this UI was planned, it never shipped.
- ~~`Modules/SpaceRPG/0-Old/SpaceQuickLook.swift` (70 LOC) — confirmed 0 build references.~~ **RETRACTED, same root cause.** `Modules/SpaceRPG/Controller/ViewController.swift:39,42` directly instantiates `SpaceQuickLook`. Live. **Not deleted.**
- ✅ `Modules/CoreRPG/DeleteMe/ItemSwiftDataPersistable.swift` (60 LOC) — folder literally named `DeleteMe`; re-verified with a real repo-wide grep (not a pbxproj-text grep) that zero files reference `ItemSwiftDataPersistable` outside its own definition. **Deleted**, along with the now-empty `DeleteMe/` folder.
- **Severity:** Low (housekeeping) — see §12 for the verification method that caught the false positive on the first two.
- **Lesson:** for this project specifically, "0 references in `project.pbxproj`" is not evidence of dead code — always cross-reference actual type usage (`grep -rn <TypeName>`) and, where possible, confirm against a real build log.

### 9.2 Commented-out dead implementations left in place instead of deleted — FIXED
- ✅ `Modules/CoreRPG/CRDT/CRDT.swift:57-171` (pre-fix line numbers) — a full 90-line commented-out earlier `@propertyWrapper struct CRDT<T>` sat directly above the live 4-line implementation. **Deleted.**
- ✅ `Modules/CoreRPG/Links/LinkRegisterController.swift:268-385` (pre-fix) — two full commented-out `public extension` blocks, plus the live `effectedItems(targetId:targetEntryId:targetModule:)` (public API) whose body was entirely commented out and unconditionally `return []`. **Verified:** this specific `effectedItems` overload has zero call sites anywhere in the repo (a *different*, live `effectedItems` exists in `EffectedLinkActionPanelView.swift:179`) — confirmed dead code, not a silently-disabled live feature as initially suspected. **Deleted the commented blocks**; left the stubbed `effectedItems` function with a one-line comment explaining it's unimplemented and unreferenced, rather than inventing a real CoreData/SwiftData fetch implementation (that's a feature decision, not a quick win).
- ✅ `Modules/CoreRPG/Platform/GlasseffectAll.swift:1-14` — the entire body of `extension View { glassEffectAll... }` was commented out, leaving an inert empty extension. **Deleted the comment**, left the empty extension as-is (removing it entirely would be a slightly bigger change than a quick win warrants, since it's a public extension point).
- ✅ `Modules/CoreRPG/Cache/ObjectCache.swift:79-90` (pre-fix) — an 11-line commented cross-platform JPEG/PNG encode path sat above the live one-liner; fully obsolete now that `Image+AKImage.swift` abstracts the platform difference. **Deleted.**
- ✅ `Modules/SpaceRPG/Space/SpaceViewer.swift:246-272` (pre-fix) — ~20 lines computing volumetric-window auto-fit sizing, commented out under `#if os(visionOS)` with the note `// this is we activate later`. **Replaced with a two-line `// TODO(visionOS):` comment** describing the still-missing feature, per the original recommendation to convert it to a tracked follow-up rather than silently deleting institutional knowledge of unfinished work.
- All five verified safe by construction — comments never compile, so removing them cannot change build output. Confirmed with a full `buildForTesting` pass regardless.
- **Severity:** Medium (dead code cleanup; the `LinkRegisterController` case additionally clarified a false alarm about a disabled feature) — now resolved.

### 9.3 Two test methods disabled via comments rather than `@Test(.disabled)`
- **Location:** `Tests/GameRPGTests/InAppControllerTests.swift:124-144` (StoreKit configuration validity test); `Tests/AdventureRPGTests/AppIntentTests.swift:13-43` (`shortcutCatalogKeepsPublishedBudget`, `entityQueryLimitsPickerResultsWithoutLimitingFullIndex`)
- **What:** `@Test` functions are commented out instead of removed or marked `.disabled()`.
- **Why:** These are exactly the tests that would catch silent regressions (StoreKit product catalog, AppIntent entity-query pagination) and currently don't run at all, with no `swift test --list-tests` visibility that they're skipped.
- **Action:** Fix and re-enable, or mark `@Test(.disabled("reason"))` so the gap is discoverable.
- **Severity:** Medium

### 9.4 `ExportController.exporting(itemIds:)` BFS traversal duplicated verbatim across 7+ modules
- **Location:** `Modules/PhotoRPG/Controller/ExportController.swift:20-53`; `Modules/SpaceRPG/Controller/ExportController.swift:20-53`; `Modules/DiceRPG/Controller/ExportController.swift:20-54`; `Modules/PdfRPG/Controller/ExportController.swift:20-53`; `Modules/AudioRPG/Controller/ExportController.swift`; `Modules/GeneratorRPG/Controller/ExportController.swift`; `Modules/WeatherRPG/Controller/ExportController.swift`
- **What:** Every module implements an identical `struct ExportController` and an identical while-loop BFS over `checkIds`/`results`, differing only in which `entryId.<x>Id` key path is walked and whether it's gated by `item.specialCategory`. **Verified:** `PdfRPG` and `DiceRPG`'s `ExportController.swift` files are byte-for-byte identical (confirmed by direct comparison), not merely similar.
- **Why:** A bug fix to the export traversal (cycle handling, `mergePartial` semantics) must be hand-applied in 7-13 files.
- **Action:** Extract the traversal into a default `ExportControllable` protocol extension in CoreRPG parameterized by a `childId(for:)` closure/keypath, mirroring how `FolderListControllable` already centralizes its logic.
- **Severity:** High — **verified**, see §12.

### 9.5 `DetailFolderListView.overlayContent` copy-pasted across 11 modules
- **Location:** `Modules/PhotoRPG/View/DetailFolderListView.swift:36-46`; `Modules/AudioRPG/View/DetailFolderListView.swift:47-57`; `Modules/MapRPG/View/DetailFolderListView.swift:34-46`; `Modules/SpaceRPG`, `CharacterRPG`, `TableRPG`, `PdfRPG`, `WeatherRPG`, `AdventureRPG`, `RuleRPG`, `DiceRPG` — all `View/DetailFolderListView.swift`
- **What:** Every module's `DetailFolderListView` repeats an identical `@ViewBuilder private var overlayContent` (checks `root.openFileWindowModel.showItem`, calls `root.viewController.viewer(root:itemId:configuration:)`) and an identical `.overlay { overlayContent }` call. **Verified:** PhotoRPG and MapRPG's files are identical apart from the wrapped detail content and `linkTypes` parameter.
- **Why:** Genuine copy-paste (not protocol conformance — it's a `@ViewBuilder` property with no shared base). The state-ownership pattern itself is correct (no `@State`-wrapping-a-passed-value issue found), so this is pure duplication, not a functional bug.
- **Action:** Extract into a CoreRPG `ViewModifier` (e.g. `.openFileWindowOverlay(root:)`) applied once, eliminating ~11 duplicate ~10-line copies.
- **Severity:** Medium — **verified**, see §12.

### 9.6 `CacheController.generateThumbnail` QuickLook wrapper duplicated (SpaceRPG/PdfRPG)
- **Location:** `Modules/SpaceRPG/Controller/CacheController.swift:38-58`; `Modules/PdfRPG/Controller/CacheController.swift:42-62`
- **What:** Both define `static func generateThumbnail(for url: URL?) async -> AKImage?` wrapping `QLThumbnailGenerator.Request`, differing only in the hardcoded `CGSize` (393×350 vs. 210×297) and SpaceRPG's extra background-removal call.
- **Why:** Same QuickLook error-handling/logging logic maintained twice.
- **Action:** Move to a shared CoreRPG helper parameterized by size and a whitening flag.
- **Severity:** Medium

### 9.7 Minor duplicated tail in four modules' `CacheController`
- **Location:** `Modules/PhotoRPG/Controller/CacheController.swift`, `Modules/MapRPG/Controller/CacheController.swift`, `Modules/SpaceRPG/Controller/CacheController.swift`, `Modules/PdfRPG/Controller/CacheController.swift`
- **What:** The `thumbnailCacheController.saveToDisk(...); thumbnailCacheController.setObject(...)` two-line tail is repeated identically in all four, even though the thumbnail-generation logic above it legitimately differs per module.
- **Action:** Add a default `func store(thumbnail:for:)` to the `ImageCacheControllable` protocol extension.
- **Severity:** Low

### 9.8 `FolderListController.copy(listModel:)` boilerplate repeated in 12 modules
- **Location:** Each module's `Controller/FolderListController.swift` (PhotoRPG, AudioRPG, MapRPG, SpaceRPG, CharacterRPG, DiceRPG, TableRPG, PdfRPG, WeatherRPG, AdventureRPG, RuleRPG, GeneratorRPG)
- **What:** All 12 `FolderListController` structs repeat the same 6-line `copy(listModel:)` implementation. **Note:** the rest of each controller is a legitimate thin conformance to `FolderListControllable` (real logic lives in the 604-line protocol extension) — only this one method is pure boilerplate; this is a much smaller duplication footprint than initially hypothesized.
- **Action:** Low priority — add a default `copy(listModel:)` to the protocol extension via a shared init requirement.
- **Severity:** Low

### 9.9 `"Documents"` path component hardcoded independently in 4 files / 6 call sites
- **Location:** `Modules/CoreRPG/Files/CloudDocumentController.swift:210` (has the real constant, `documentDirName`); `Modules/CoreRPG/Files/LocationFileManager.swift:15,18,67`; `Modules/CoreRPG/Foundry/FoundryImportArchive.swift:211`; `Modules/CoreRPG/Import/ExternalImportSourceRegistry.swift:139`
- **Action:** Route all 6 call sites through `CloudDocumentController.documentDirName`.
- **Severity:** Low

### 9.10 iCloud container identifier string literal duplicated in 2 files
- **Location:** `Modules/CoreRPG/App/AppGroup.swift:27`; `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:16`
- **Action:** Define a single `static let cloudKitContainerIdentifier` in `AppGroup.swift`, referenced from the other file.
- **Severity:** Low

### 9.11 Oversized files (>500 lines) beyond the top hot-spots
51 non-test Swift files exceed 500 lines. Beyond the seven networking/import hot-spots already covered in §3/§5, ten more worth splitting along their own `// MARK` boundaries:
- `Modules/GameRPG/Network/GameNetworkController.swift` (1,182 LOC) — split by transport concern: `+Master`, `+Player`, `+SharePlay`, `+Utility` extensions.
- `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift` (1,074 LOC) — extract retry/backoff policy and journal-entry codec into separate files.
- `Modules/GeneratorRPG/Controller/GeneratorController.swift` (1,037 LOC) — lacks internal `// MARK` structure entirely; add sections first, then split request-building from response-parsing.
- `Modules/GameRPG/Model/GameNetworkModel.swift` (1,018 LOC) — a Model file this size suggests logic that belongs in `GameNetworkController`/`MasterController`/`PlayerController` per the project's own MVC split; audit for methods that should move.
- `Modules/CoreRPG/Sheet/SheetRootModel.swift` (1,009 LOC) — has two separate "AI generation" `// MARK` sections (197, 610); worth checking for accidental duplication before splitting into `+Search`/`+ContextMenu`/`+AIGeneration`.
- `Modules/CoreRPG/Import/ExternalImport.swift` (1,003 LOC) — split by import phase (parsing vs. mapping vs. provenance), mirroring how the `Foundry*` readers are already separated.
- `Modules/RuleRPG/Model/RuleModel.swift` (852 LOC) — check whether Core Data mapping logic has leaked in from `RuleRPG/Controller/DataController.swift`.
- `Modules/CoreRPG/Tips/MasterRPGTips.swift` (816 LOC) — split declarative tip catalog from donation/eligibility logic.
- `Modules/MapRPG/Map/MapOverlayGeometry.swift` (815 LOC) — split pin geometry, toolbar/button geometry, and layer/canvas geometry.
- **Note:** `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportView.swift` (866 LOC) was flagged in the same size sweep but does **not** need a split — see the correction in §8.5; it's already decomposed into ~10 small child View structs, just needs a filename fix.
- **Severity:** Medium (top 3), Low (rest).

### 9.12 `print()` calls not behind `#if DEBUG`
70 non-comment `print(...)` sites across 29 files. Top offenders:
- ~~`Modules/GeneratorRPG/Playground/MyAiPlayground.swift` (9 calls) — dumps FoundationModels streaming responses/tool-call errors to console; confirm the file's target membership doesn't ship to release.~~ **RETRACTED.** Read the file: it's entirely `#Playground(...)` blocks (`import Playgrounds`, Xcode's interactive-canvas macro, the same family as `#Preview`). This code only executes inside Xcode's Playground canvas and is never part of a shipped Release build — `print()` is the canvas's actual output mechanism, not a leak. No change made; not a real issue.
- `Modules/DiceRPG/Space/DiceSpaceModel.swift` (7 calls) — unconditional per-frame RealityKit/visionOS scene-loading diagnostics.
- `Modules/PhotoRPG/Space/Spatial3DImageState.swift` (6) + `OrnamentsView.swift` (4) — spatial-photo pipeline status/error logging, including raw `error.localizedDescription`.
- `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:106,108` and `Modules/CoreRPG/App/ExportedRPGData.swift:105,156` — CloudKit schema-init and export errors printed unconditionally; closest thing to a sensitive-data-via-`print` risk since error descriptions can embed paths/identifiers.
- Remaining ~44 calls across 20 files (1-3 each): `RemoveItemViewModifier.swift`, `DumpEnvironment.swift`, `AudioPlayerSession.swift`, `RealityView+CameraTracking.swift`, `GameProtocol.swift`, `HandTrackingModel.swift`, `MapRPG`/`CharacterRPG` `ExportController.swift` (identical error-message duplication — cross-ref §9.4), `PreviewData.swift`, and others.
- **Action:** Route through the existing `os.Logger` categories (`Logger.cacheController` etc.) or wrap in `#if DEBUG`.
- **Severity:** Low-Medium (aggregate; Medium for the two clusters that risk leaking content/paths).

### 9.13 Filename typos and an unused public type — FIXED (typos); type left as-is
- ✅ `Modules/CoreRPG/Views/InpectorUnavailableView.swift` → **renamed to** `InspectorUnavailableView.swift`. The type inside (`InspectorUnavailableView`) was already spelled correctly and is `public` but still has zero call sites outside its own `#Preview` and a machine-generated snapshot test — that part is unchanged; deciding its fate (wire it up vs. delete) is a product/UI decision, not a quick win, so the type itself was left in place.
- ✅ `Modules/GameRPG/Table3D/GameEquiqment.swift` → **renamed to** `GameEquipment.swift`. Internal type names (`Table`, `Board`, `Die`, etc.) were already correct.
- ✅ `Modules/CoreRPG/Extensions/TaggedPrefernceKey.swift` → **renamed to** `TaggedPreferenceKey.swift`.
- All three renames verified safe: this project uses Xcode 16 file-system-synchronized groups, so file renames need no `project.pbxproj` edits (confirmed with a `buildForTesting` pass after renaming).
- **Severity:** Low — resolved.

### 9.14 CoreRPG has both a `View/` and a `Views/` top-level folder — FIXED
- **Location (pre-fix):** `Modules/CoreRPG/View/` (1 file: `SupporterCrownView.swift`) vs. `Modules/CoreRPG/Views/` (14 files)
- **Why:** New contributors won't know which folder to add a new CoreRPG view to — the module that defines the documented convention doesn't follow it cleanly itself.
- **Action taken:** ✅ Moved `SupporterCrownView.swift` into `Modules/CoreRPG/Views/` and deleted the now-empty `Modules/CoreRPG/View/` folder. Verified with a `buildForTesting` pass.
- **Severity:** Low — resolved.

### 9.15 Documented Module folder structure doesn't match actual per-module practice
- **Location:** `CLAUDE.md` ("Module: Module specific code") vs. e.g. `AudioRPG/Audio`, `DiceRPG/Dice` + `DiceRPG/Space` + `DiceRPG/Widget`, `MapRPG/Map` + `MapRPG/BattleRound` + `MapRPG/Extension`
- **What:** No module has a folder literally named `Module`; each instead names it after its domain, and several split it into multiple ad hoc folders.
- **Why:** Either stale documentation or an unenforced convention — misleading for anyone (human or AI agent) using `CLAUDE.md` as the source of truth for file placement.
- **Action:** Update `CLAUDE.md`'s folder-structure section to reflect actual practice, or standardize modules on a single folder name going forward.
- **Severity:** Medium (documentation/process debt)

### 9.16 Ad-hoc magic constants
- Thumbnail pixel sizes hardcoded per call site instead of named constants — production sizes worth naming: `Modules/PhotoRPG/Controller/CacheController.swift:58` (64×64), `Modules/SpaceRPG/Controller/CacheController.swift:40` (393×350), `Modules/PdfRPG/Controller/CacheController.swift:44` (210×297).
- JPEG compression-quality values inconsistent and unnamed: `0.5` (`PlayerController.swift:1298`, screen-share frame), `0.8` (`ObjectCache.swift:78`), `0.9` (`ExportControllable.swift:217`, `EditController.swift:38,81`) — unclear whether the 0.8/0.9 split is intentional.
- Retry/loop bounds with no rationale comment: `FoundryLevelDBReader.swift:349` (`0..<8`), `ThemeColor.swift:55` (`0..<24`).
- **Action:** Promote to named constants (`ThumbnailSize`, `JPEGQuality` enums) with a one-line rationale each.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Centralize the two confirmed duplication hot spots (§9.4, §9.5) with the same pattern already proven for `FolderListControllable`.** Both `ExportController.exporting(itemIds:)` and `DetailFolderListView.overlayContent` are copy-pasted, not shared, even though a working "thin per-module conformance to a CoreRPG protocol extension" pattern already exists elsewhere in the codebase (`FolderListControllable`, 604 lines, genuinely shared). Applying that same shape here would collapse ~18 duplicate implementations into one each.
2. **Replace `nonisolated(unsafe)` + `MainActor.assumeIsolated` (§3.8) with a `Sendable` snapshot type usable off the main actor.** This directly unblocks §3.1 (Foundry import mapping forced onto the Main Actor) too — a background-safe snapshot type would let both JSON encoding and import mapping move off the main actor without runtime-only safety guarantees.
3. **Standardize on `os.Logger` and stop using bare `print()` or empty `catch {}`.** §9.12 (70 `print()` sites), §5.8 (11 empty Siri-donation catches), and §5.9 (silently swallowed CloudKit merge errors) are the same missing habit in three places. A `SwiftLint` custom rule banning `print(` in non-test targets would catch this class of issue going forward.
4. **Sweep for `fatalError()`/force-unwrap/force-try on paths reachable from CloudKit sync races or user-entered text.** §5.2, §5.3, §5.4, §5.5, §5.6, and §5.7 are the largest single cluster in this audit. None is individually catastrophic, but together they represent a consistent habit of treating optionality from user input, CloudKit merges, and bundled-resource loading as unrecoverable rather than handled.
5. **Reconcile `CLAUDE.md`'s documented per-module folder structure with actual practice** (§9.15) — several other findings in this audit implicitly assumed the documented convention; fixing the docs (or the folders) makes the convention actually enforceable and reduces the friction that findings like §9.14 create for new contributors and AI coding agents alike.

---

## 11. What was NOT audited

- `Modules/DiceRPG/0-Old/` and `Modules/SpaceRPG/0-Old/` — characterized (§9.1) but not reviewed line-by-line since confirmed unbuilt/archived.
- Algorithmic correctness of RealityKit/3D-object rendering and the LevelDB/ZIP binary-format parsing internals in the Foundry import pipeline — only bounds-check/security posture was reviewed (found well-hardened), not full parser correctness.
- Xcode project build settings and scheme configuration beyond the deployment-target sweep (§4.6) and the three sampled entitlements files (§6.3).
- Third-party SPM dependency internals: `swift-syntax`, `xctest-dynamic-overlay`, `swift-snapshot-testing`, `swift-custom-dump`, `RPGTabletopGameContent` — treated as black boxes.
- Test coverage — a quick scan surfaced two disabled tests (§9.3); no deep coverage review of the 20+ test targets under `Tests/`.
- Full accessibility audit (VoiceOver full walkthrough, Dynamic Type stress testing at largest sizes, dark-mode contrast) — only spot-checked in the 6 files read for §8; one concrete issue found (§8.3).
- Localization / String Catalog correctness — usage of `Text(..., bundle: .module)` was spot-checked for pattern compliance, not translation wording.
- StoreKit/IAP configuration — Agent C found no IAP/StoreKit product-catalog files to audit beyond the one disabled test in §9.3.
- Performance profiling with Instruments — no `.trace` was recorded or analyzed; performance findings are static-analysis-only (§7, §8.1, §8.2).
- The known pre-existing failing tests and prior SharePlay/GameController fixes referenced in project history were not re-verified here; this audit is a static read-only pass, not a test run.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line.

- **§5.1** — open `Modules/GameRPG/Controller/LogGameController.swift`, lines 189-190. Confirmed: the `.value` case returns `root?.photoRoot.itemControllable.nameSync(itemId:)`, while every sibling case (`.map`, `.table`, `.adventure`, etc.) correctly returns its own module's root — `.value` is the only mismatched case.
- **§5.4** — open `Modules/CoreRPG/Controllable/EditControllable.swift`, lines 580-586. Confirmed: `filePath` interpolates `item.name` directly (`"\(folder)\(item.name).\(itemControllable.config.filenameExtension)"`) with no percent-encoding, then `URL(string: filePath)!` force-unwraps.
- **§6.1** — open `Modules/GameRPG/Network/GameSecurity.swift`, lines 1-8. Confirmed: a single `static let passcode = "GameMasterCode"` is the entire declared type; the doc comment above it states it's the sole source of the TLS pre-shared key for peer pairing.
- **§3.1** — open `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift`, lines 179-180 (`@MainActor struct FoundryVTTDomainMapper`), and `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift`, line 169 (`try await FoundryVTTDomainMapper().map(...)` inside `prepareReview()`, itself invoked from a `Task { @MainActor in ... }` in `FoundryImportView.swift:166-169`).
- **§4.6** — grep `MasterRPG.xcodeproj/project.pbxproj` for `IPHONEOS_DEPLOYMENT_TARGET`/`XROS_DEPLOYMENT_TARGET`/`MACOSX_DEPLOYMENT_TARGET`: confirmed both `26.0` and `26.4` values are present project-wide, with `26.4` isolated to the `DiceRollerWidgetExtension` target's build configs.
- **§9.4** — open `Modules/PdfRPG/Controller/ExportController.swift` and `Modules/DiceRPG/Controller/ExportController.swift` side by side, lines 1-55 of each: confirmed byte-for-byte identical, including the `Sendable` struct declaration, the force-unwrapped `hubControllable` (§5.7), and the full BFS loop body.
- **§9.2 (LinkRegisterController)** — open `Modules/CoreRPG/Links/LinkRegisterController.swift`, lines 364-385: confirmed `effectedItems(targetId:targetEntryId:targetModule:)`'s body is `return []` with the real implementation entirely commented out below it; a repo-wide grep for `effectedItems(` shows this specific overload has no callers (the live "what links here" UI calls a different, static `effectedItems` in `EffectedLinkActionPanelView.swift`).

If any finding doesn't reproduce when you visit the line, flag the specific reference for re-investigation.
