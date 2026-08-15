# MasterRPG Code Audit

Generated 2026-08-14. Scope: ~266,845 Swift LOC across 1,986 files, covering all 15 dynamic-framework modules (`AdventureRPG`, `AudioRPG`, `CharacterRPG`, `CoreRPG`, `DiceRPG`, `GameRPG`, `GeneratorRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `RolePlayGameKit`, `RuleRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG`) and the `MasterRPG`/`MasterMac`/`MasterTV`/`RPGShare`/`DiceRollerWidgetExtension` targets. No `Dead/` or archived directory exists in this repo, so nothing was excluded by convention — only `.git/`, `.build/`, and Xcode project-internal directories were skipped.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

**Compiler ground truth:** a full clean `xcodebuild` of the `MasterRPG` scheme (iOS Simulator) across all 21 in-scope targets succeeded with **zero real compiler warnings** (only two unrelated "AppIntents metadata extraction skipped" notices) and zero errors, under `SWIFT_STRICT_CONCURRENCY = complete` / Swift 6 language mode. This is not a gap in this audit — the codebase is genuinely warning-clean. Findings below were found by reading code and grepping for anti-patterns the compiler can't catch (architectural concurrency choices, force-unwraps, duplication, SwiftUI idiom, security), not by tracing diagnostics.

**Context on findings volume:** this repo already carries four prior audit passes (`Docu/CODE_AUDIT_1.md` through `_4.md`) plus dedicated `SWIFTUI_PERFORMANCE_AUDIT.md` and `LOCALIZATION_ACCESSIBILITY_AUDIT.md` reports, and in-code comments (e.g. `Modules/GameRPG/Network/ConnectionAttemptThrottle.swift:7`) show prior findings being actively fixed. All four agents in this pass cross-checked prior claims against current source and discarded roughly a dozen stale items (typos already fixed, files already deleted, helpers already extracted, a hardcoded TLS passcode already replaced) before reporting anything below. The result is a shorter, higher-signal finding set (37 items) than a first-pass audit would typically produce — that reflects the codebase's actual state, not reduced audit effort.

---

## 1. Executive summary

Top items to address, in priority order:

1. **[High] `@State` in Navigator checkpoint modifiers is seeded once from an init parameter and never re-synced** — §8.1 — `Modules/CoreRPG/Navigator/Core/NavigationCheckpoint.swift:294,319`. Re-applying a checkpoint modifier with a changed value silently keeps using the stale first-seen value.
2. **[High] Every Core Data save across the entire app swallows failures silently** — §5.1 — `Modules/CoreRPG/Controllable/ItemControllable.swift:377-384`. A failed `save()` leaves the UI showing an edit that never reached disk, with zero diagnostic trail.
3. **[High] Force-unwraps in RealityKit entity-drag gesture code, guarded only by a single un-reentrant global** — §5.2 — `Modules/SpaceRPG/Space/EntityGestureState.swift:106,127,158,192`. A concurrent/mid-flight entity-hierarchy change (plausible given SharePlay-synced object placement) traps instead of degrading.
4. **[High] `MainActor.assumeIsolated` used as the isolation proof for `nonisolated` protocol conformances on 13 domain models** — §3.2 — representative: `Modules/PdfRPG/Model/PdfModel.swift:102-113`. Sound today (verified no off-Main-Actor caller exists), but it trades a compile-time guarantee for a runtime trap with no regression test protecting the invariant.
5. **[High] Orphan-cleanup Core Data logic duplicated verbatim across 10 modules' `DataController.swift`** — §9.1 — e.g. `Modules/PdfRPG/Controller/DataController.swift:46-63`. A future CloudKit-merge correctness fix has to be manually reapplied 10 times or silently drifts.
6. **[High] Uncancellable `DispatchQueue.main.asyncAfter` in the Navigator's deferred-resume path, unfixed across 3 prior audit passes** — §3.1 — `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:112-114`. A torn-down navigation context can still receive a stale, un-cancelled `send` later.
7. **[Medium] Objective-C selector-based `Timer` inside a `@MainActor` class, defended by runtime `dispatchPrecondition` instead of the type system** — §3.5 — `Modules/SpaceRPG/Record/TimedMessageList.swift:121-142`.
8. **[Medium] `linkRegisterController` force-unwrap is the sole remaining site of a pattern already fixed in the other 10 modules** — §5.3 — `Modules/AdventureRPG/Root/AdventureRootModel.swift:188-189` (confirmed unique via cross-module grep).
9. **[Medium] View logic expressed as computed `some View` properties instead of separate `View` structs, ~100+ sites** — §8.2 — e.g. `Modules/CoreRPG/Sheet/SheetEntryView.swift`, `Modules/CoreRPG/LGViews/ItemHeaderEditorView.swift`. The most-repeated house-rule violation found; defeats SwiftUI's diffing boundary on the app's largest, most complex views.
10. **[Medium] Unbounded user text forwarded verbatim into the on-device FoundationModels prompt** — §7.1 — `Modules/GeneratorRPG/Controller/GeneratorController.swift:469-481`.

---

## 2. Quick wins (≤30 min each)

- **Fix the "reparing" → "repairing" typo copy-pasted into 4 modules' `LinkController.swift` log lines** — §9.8 — `Modules/AdventureRPG/Controller/LinkController.swift:172`, `Modules/CharacterRPG/Controller/LinkController.swift:129`, `Modules/MapRPG/Controller/LinkController.swift:92`, `Modules/TableRPG/Controller/LinkController.swift:92`.
- **Delete the commented-out prompt/instructions blocks in the AI playground file** — §9.9 — `Modules/GeneratorRPG/Playground/MyAiPlayground.swift:10-12,19-21`.
- **Mark the two `@FocusState.Binding` properties `private`** — §8.5 — `Modules/GeneratorRPG/View/SheetAIAssistantStandardControl.swift:19`, `Modules/GeneratorRPG/BasicAI/View/ChatInputView.swift:10`.
- **Add `: Sendable` to `MasterNetworkController` for consistency with its three sibling controllers** — §3.6 — `Modules/GameRPG/Master/MasterNetworkController.swift:27-28`.
- **Replace the force-unwrapped `.last!` in link-toggle string parsing with a safe fallback** — §5.4 — `Modules/CoreRPG/LinkRenderer/AttributedString+Link.swift:16`, `Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift:68`.
- **Mark `checkpoint` `private` and `let` in the two Navigator checkpoint modifiers** — §8.1 — `Modules/CoreRPG/Navigator/Core/NavigationCheckpoint.swift:294,319` (pairs with the fuller fix in §8.1, but the `private` half alone is a one-line change).
- **Wire the two icon-only buttons to the same `Label`+`.labelStyle(.iconOnly)` pattern their siblings already use** — §8.3 — `Modules/CoreRPG/Sheet/SheetEntryAddGroupButton.swift:20-22`, `Modules/CoreRPG/Sheet/SheetEntryConvertToGroupButton.swift:17-19`.

---

## 3. Concurrency

### 3.1 Uncancellable `DispatchQueue.main.asyncAfter` in Navigator's deferred resume
- **Location:** `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:107-114`
- **What:** `resume(_:values:delay:)`'s `.auto` case schedules `self.send(values: values)` via `DispatchQueue.main.asyncAfter(deadline:)` instead of a `Task`.
- **Why:** Violates the project's explicit "never use GCD, always modern concurrency" rule. Unlike a `Task`, this closure cannot be cancelled once scheduled — if the navigator/view is torn down before the delay elapses, a stale `send` still fires against a context that has moved on. This exact line has been flagged across 3 prior audit passes and remains unfixed.
- **Action:** Replace with a stored, cancellable `Task { try? await Task.sleep(for: .seconds(delay)); await send(values: values) }` that a subsequent teardown/`reset()` can cancel.
- **Severity:** High

### 3.2 `MainActor.assumeIsolated` bridges `nonisolated` protocol conformances to `@MainActor` state across 13 domain models
- **Location:** representative sample — `Modules/PdfRPG/Model/PdfModel.swift:107-176`; `Modules/DiceRPG/Model/DiceModel.swift:395-505,678`; `Modules/WeatherRPG/Model/WeatherModel.swift:142,170,209,288,427`; `Modules/AdventureRPG/Model/AdventureModel.swift:159,189,222,230,307,351`; `Modules/CharacterRPG/Model/ValueModel.swift:124,204,235,381,506`; `Modules/PhotoRPG/Model/PhotoModel.swift:116,125,154,179,301`; `Modules/RuleRPG/Model/RuleModel.swift:771`; `Modules/GeneratorRPG/Model/GeneratorModel.swift:121,150,166,241,248`; `Modules/MapRPG/Model/MapModel.swift:406,484,524,598,733`; `Modules/SpaceRPG/Model/SpaceModel.swift:114,126,155,187,292`; `Modules/TableRPG/Model/TableModel.swift:119,182,212,296,409`; `Modules/AudioRPG/Model/AudioModel.swift:109,122,153,178,293`; `Modules/CoreRPG/Simple/SimpleModel.swift:176` (~60 call sites total).
- **What:** Each `@MainActor @Observable` model conforms to `nonisolated Comparable`/`ItemDiffComparable`/`ItemDuplicatable`, whose requirements (`<`, `merge`, `isSame`, `duplicate`) are `nonisolated` by default; every implementation wraps its body in `MainActor.assumeIsolated { ... }` to legally touch `@MainActor` stored properties.
- **Why:** `assumeIsolated` is a runtime assertion, not a compiler guarantee. Verified: the one major background aggregator that touches these types, `FoundryVTTDomainMapper`, is itself whole-file `@MainActor`, so no current call site violates the invariant. But if any future caller invokes `<`, `merge`, `isSame`, or `duplicate` from a non-Main-Actor context (a `Task.detached`, a `Set`/`Dictionary` operation on a background actor, a future CRDT-merge path), the process traps instead of failing to compile — isolation enforced by human-audited convention, not the type system.
- **Action:** Not an active bug — no fix required today. Harden it: add a lightweight per-model-type regression test asserting the trap fires off-Main-Actor (documents the contract), or centralize the escape hatch behind one shared helper so new model types can't hand-roll it incorrectly.
- **Severity:** High

### 3.3 `@MainActor @Observable final class X: Sendable` is a deliberate, sound, codebase-wide convention
- **Location:** representative sample — `Modules/GameRPG/Network/GameJoinCodeModel.swift:26-27`; `Modules/GameRPG/Controller/MasterController.swift:18-19,443-444`; `Modules/GameRPG/Controller/PlayerControllerModel.swift:14-15`; `Modules/GameRPG/Table3D/GameTableModel.swift:19-20`; `Modules/GameRPG/GameCenter/GameCenterController.swift:25-26,58-59`; ~45 more sites across every module. All 166 `@Observable` usages in the codebase pair with `@MainActor` with zero exceptions.
- **What:** Every `@Observable` class is `@MainActor`, and most additionally declare an explicit, non-`@unchecked` `Sendable` conformance so they can cross actor boundaries as a value; a small number (`CoreDataInitModel`, `SimpleModel`, `FakeItemModel`) need `@unchecked Sendable` with a documented reason each (a `nonisolated init` writing directly to `@Observable`-synthesized storage).
- **Why:** This is Swift 6's sanctioned pattern for a global-actor-isolated class that needs to cross actor boundaries — `@MainActor` isolation is what makes the (otherwise non-`Sendable`) class provably data-race-free, and the compiler accepts every instance with zero errors. Sampled stored properties confirm nothing hides a genuine escape hatch behind the `@unchecked` sites. Confirms the pattern originally flagged for review on `GameJoinCodeModel` is benign and consistent, not an anomaly.
- **Action:** None required. Optional: cross-reference this finding from the `@unchecked Sendable` sites' doc comments for future auditors.
- **Severity:** Low (informational — verified clean)

### 3.4 `GroupStateObserver`'s `@ObservedObject`/Combine usage is an unavoidable Apple-framework constraint
- **Location:** `Modules/GameRPG/SetupViews/SharePlayButton.swift:20-22`
- **What:** `@ObservedObject private var groupStateObserver = GroupStateObserver()` is the only `@ObservedObject`/`ObservableObject` usage in the non-test codebase.
- **Why:** Apple's `GroupActivities.GroupStateObserver` is still Combine-based (`$isEligibleForGroupSession: Published<Bool>.Publisher`) as of this SDK, with no `@Observable` variant offered. The house rule against `ObservableObject` cannot be satisfied here without an Apple-side change.
- **Action:** None available today. Add a short comment noting the framework constraint so it isn't re-flagged as a stray violation in future sweeps.
- **Severity:** Low

### 3.5 Selector-based `Timer` inside a `@MainActor` class, defended by runtime `dispatchPrecondition` instead of the type system
- **Location:** `Modules/SpaceRPG/Record/TimedMessageList.swift:18-19` (class declaration), `:121-127` (`Timer.scheduledTimer(timeInterval:target:selector:userInfo:repeats:)`), `:136-142` (`@objc private func onTimer()`)
- **What:** `TimedMessageList` is `@MainActor @Observable`, yet schedules its expiry timer with the old Objective-C `target:`/`selector:`/`@objc` API, and defends thread-correctness at runtime via `dispatchPrecondition(condition: .onQueue(.main))` in three separate methods rather than relying on `@MainActor` isolation being statically enforced.
- **Why:** File is adapted from an Apple sample (per its header/LICENSE comment) and predates the app's Swift 6 migration. The `@objc`/selector Timer API and manual `dispatchPrecondition` checks are redundant with, and weaker than, what `@MainActor` already guarantees at compile time, and are inconsistent with the rest of the app's `Task.sleep(for:)`-based scheduling.
- **Action:** Replace with a closure-based `Timer.scheduledTimer(withTimeInterval:repeats:)` (drops the `@objc` selector and `NSObject` requirement), or preferably a cancellable `Task`-based sleep matching the rest of the codebase; drop the now-redundant `dispatchPrecondition` calls once isolation is compiler-enforced.
- **Severity:** Medium

### 3.6 Sibling `@MainActor` network-controller classes are inconsistent about declaring `Sendable`
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:27-28` (no `Sendable`) vs. siblings `Modules/GameRPG/Player/PlayerNetworkController.swift:27-28`, `Modules/GameRPG/Network/GameNetworkController.swift:502-503`, `Modules/GameRPG/Controller/MasterController.swift:443-444` (all `: Sendable`)
- **What:** Four structurally-parallel `@MainActor` controller classes in the same feature area; three explicitly conform to `Sendable`, one doesn't.
- **Why:** Not a compiler error today, but an avoidable asymmetry — a future change that captures a `MasterNetworkController` reference the way its siblings' instances already are would hit an avoidable compile error instead of "just working."
- **Action:** Add `: Sendable` to `MasterNetworkController` to match its three siblings.
- **Severity:** Low

---

## 4. API modernity

### 4.1 Vendored `NavigatorUI` library carries `@available` guards far below the 26.0 deployment target
- **Location:** `Modules/CoreRPG/Navigator/Extensions/NavigationLink+Navigator.swift:40,102` (`@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)`)
- **What:** Two extension blocks are gated behind minimum-OS checks that are unconditionally true given this project's 26.0 deployment target across every platform.
- **Why:** Dead availability code — harmless, but a reminder this is a manually vendored third-party library (hand-applied version bumps in git history) rather than an SPM dependency, so it doesn't get pruned by first-party modernization passes.
- **Action:** Low priority; strip the now-always-true guards next time the vendored copy is updated, not worth a special-purpose edit otherwise.
- **Severity:** Low

### 4.2 Dead completion-handler `NSItemProvider` import path in PhotoRPG
- **Location:** `Modules/PhotoRPG/Controller/ItemController.swift:37-56` (`static func importImageFromProviders(_:completion:)`)
- **What:** Uses `provider.loadDataRepresentation(forTypeIdentifier:completion:)` (string-typeIdentifier, callback-based) wrapped in a hand-rolled `Task { @MainActor in completion(data) }` hop, instead of the modern `async throws` UTType-based API the rest of the codebase already uses correctly elsewhere (e.g. `Sources/RPGShare/ItemProviderImporter.swift`). A repo-wide grep found zero callers.
- **Why:** Minor modernity gap compounded by apparently being unreferenced dead code.
- **Action:** Delete if genuinely unused, or rewrite as an `async throws -> Data?` function using `loadDataRepresentation(for type: UTType)` if still needed.
- **Severity:** Low

### 4.3 Deprecated `.system.search` App Shortcuts schema across 12 modules
- **Location:** one site per module — `Modules/AdventureRPG/Intent/SearchAdventuresIntent.swift:8` and the equivalent file in `Modules/{Character,Rule,Generator,Dice,Space,Photo,Audio,Weather,Pdf,Table,Map}RPG/Intent/`.
- **What:** `@AppIntent(schema: .system.search)` uses a schema Apple deprecates exactly at OS version 27.0; the replacement requires a deployment target one major version above this project's current 26.0.
- **Why:** No actionable fix exists until the deployment target moves to 27 — flagged for completeness since it's a live, mechanically identical gap across 12 files.
- **Action:** Fold into whatever change eventually bumps the deployment target past 27; all 12 sites are mechanically identical, a single coordinated edit when the time comes.
- **Severity:** Low

### 4.4 Manual `EnvironmentKey` conformance instead of the `@Entry` macro
- **Location:** `Modules/RolePlayGameKit/View/DatabaseInitializationView.swift:112-121`, `Modules/CoreRPG/LGViews/ItemStateRestorationView.swift:131-140`, `Modules/CoreRPG/FileViews/StorageOptionEditor.swift:87-96`
- **What:** Each declares a private `EnvironmentKey` struct plus a hand-written `EnvironmentValues` getter/setter instead of the one-line `@Entry` macro, for stable `Bool` defaults.
- **Why:** Soft-deprecated boilerplate; purely a maintenance/readability cost since default values are stable literals. (`Modules/CoreRPG/Navigator/Navigator.swift:347-352`'s manual `EnvironmentKey` is intentionally excluded — it has a code comment documenting a known `@Entry` macro bug it works around.)
- **Action:** Replace each with `@Entry var <name>: Bool = <default>` on `EnvironmentValues`.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Silent, unlogged Core Data save-failure swallowing across the entire app
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:374,377-380,382-384`
- **What:** `save()`, `resetData()`'s batch-delete, and `flushPendingOperations()` all call the throwing Core Data layer via bare `try?` with no logging, error propagation, or user-facing surfacing.
- **Why:** `save()` is the terminal call for essentially every item edit across all 15 modules (~72 call sites). If `context.save()` throws (validation failure, CloudKit merge/schema conflict, disk full, migration edge case), the UI has already applied the in-memory change — the user believes the edit succeeded while it silently never reaches disk, with zero diagnostic trail.
- **Action:** Replace the bare `try?` with `do`/`catch` that at minimum logs via `Logger` (matching the pattern already used in `PersistentHistoryTrackerManager`), and surface a recoverable-error state to the relevant `ItemController`/UI.
- **Severity:** High

### 5.2 Force-unwraps in RealityKit entity-drag gesture code, guarded by one un-reentrant global
- **Location:** `Modules/SpaceRPG/Space/EntityGestureState.swift:106,127,158,192,196-197`
- **What:** `handlePivotDrag`/`handleFixedDrag` force-unwrap `state.targetedEntity` (`fatalError` on nil) and `onEnded` force-unwraps both `pivotEntity.parent!` and `state.targetedEntity!` when reparenting out of the pivot. All gesture state lives in one `@MainActor` singleton (`EntityGestureState.shared`, confirmed via grep to be the only touch point in the module) shared across every draggable entity, with no protection against two concurrent drags.
- **Why:** `SpaceViewer.swift` documents that this view syncs placement across SharePlay participants. If the dragged entity's parent changes — or the pivot entity is torn out from under a drag — via any concurrent mutation before `onEnded` runs, the force-unwraps trap. The single shared singleton also has no defense against two simultaneous drags on different entities corrupting the tracked target.
- **Action:** Replace the force-unwraps with `guard let ... else { return }` bail-outs (silently dropping the reparent is far safer than crashing); consider keying gesture state per-entity instead of one global singleton so concurrent gestures can't collide.
- **Severity:** High

### 5.3 Two-phase-init force-unwrap crash window in `AdventureRootModel.linkRegisterController`
- **Location:** `Modules/AdventureRPG/Root/AdventureRootModel.swift:105-108,188-189`
- **What:** `_linkRegisterController: LinkRegisterController?` is `nil` after `init()` and only assigned inside `setUp(root:context:batchContext:)`, called later; the public accessor is `var linkRegisterController: LinkRegisterController { _linkRegisterController! }`.
- **Why:** Any code path that reads `.linkRegisterController` before `setUp()` runs crashes instead of failing gracefully. Confirmed via cross-module grep that this is the **sole remaining site** of a pattern that used to exist at ~26 sites across 11 modules and has since been fixed everywhere else (other modules take `linkRegisterController` as a direct, non-optional `setUp` parameter with no force-unwrapped accessor).
- **Action:** Align with the safer pattern already used by the other 10 modules instead of the bare `!`.
- **Severity:** Medium

### 5.4 Force-unwrap on `split(separator:).last` when toggling a markdown link
- **Location:** `Modules/CoreRPG/LinkRenderer/AttributedString+Link.swift:16`, `Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift:68`
- **What:** Both sites compute `url.split(separator: "]").last!` — `split` returns an empty array on an empty string, making `.last!` trap.
- **Why:** Reachable from `LinkController.toggleLink`/link-repair code across all 11 feature modules. Current callers always build `url` from a well-formed `"[name](scheme://...)"` string, making an empty input unlikely today, but there's no defensive fallback if a future caller or a corrupted/legacy stored link string breaks that assumption.
- **Action:** Replace `.last!` with `.last ?? Substring(url)`, or an explicit guard that returns the input unchanged on empty split.
- **Severity:** Low

---

## 6. Security

Deep review covered: the local-network game-pairing flow (`GameJoinCodeModel`, TLS-PSK handshake, `ConnectionAttemptThrottle`), the Foundry VTT untrusted-archive importer (ZIP parser, LevelDB/WAL/Snappy readers, bounded base64 decoder), CloudKit/Core Data persistence (`PersistentHistoryTrackerManager`, merge policy, all 14 Core Data models' optional/default-value compliance), entitlements files for every target, and StoreKit 2 IAP code. Most previously-known issues visible in this codebase's history (a hardcoded shared TLS passcode, unthrottled join-code brute-forcing) are verifiably already fixed — `GameJoinCodeModel.swift`'s own doc comment and `ConnectionAttemptThrottle.swift`'s header describe the earlier hardening. No hardcoded secrets/API keys were found in a repo-wide sweep. No zip-slip, zip-bomb, or unbounded-allocation issue was found in the Foundry import path (`FoundryBoundedBase64.swift`'s name-implied bound is enforced, not just named). One residual item:

### 6.1 Residual keyspace of the 4-digit local-network join code
- **Location:** `Modules/GameRPG/Network/GameJoinCodeModel.swift:72-76` (`randomCode()`, confirmed: 4 numeric digits, 10,000 possible values), `Modules/GameRPG/Network/ConnectionAttemptThrottle.swift:17-49` (confirmed: 3-strikes lockout with exponential backoff capped at 300s, per source host)
- **What:** The join code's keyspace is small (10,000 values), though the connection itself is gated by a TLS-PSK handshake (not a plaintext comparison), and a verified per-source throttle now caps the practical brute-force rate to roughly one attempt per up to 5 minutes once locked out.
- **Why:** With the throttle in place, this is a reasonable mitigation for a same-room pairing PIN — but the keyspace is still small enough that a patient, sustained attacker on the same LAN over a long game session isn't fully ruled out the way a longer code or a manual join-confirmation prompt would.
- **Action:** Consider lengthening the code (e.g. 6 digits) or adding a master-side "new device wants to join" confirmation prompt for defense in depth. No urgent action — the throttle already bounds the practical attack rate.
- **Severity:** Low

---

## 7. Performance

### 7.1 Unbounded user chat message forwarded to the on-device FoundationModels prompt
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:469-481`; `Modules/GeneratorRPG/View/SheetAIAssistantStandardControl.swift:45-51`
- **What:** `prompt(for:module:rootSheetModel:focusedContent:maxCharacters:)` caps only the existing-sheet-entries context (`compactSheetIndex`, 600-char default) before folding it into the prompt; the user's own `message` text is inserted verbatim with no length cap, and the backing `TextField` has no character limit either.
- **Why:** A user pasting a large block of text (e.g. an entire imported adventure's prose) sends it unbounded straight into the on-device LLM prompt, degrading generation latency/battery or failing outright once the model's context window is exceeded, with no truncation or warning before the request is made.
- **Action:** Apply the same `maxCharacters`-style truncation already used for `compactSheetIndex` to the raw `message` before composing the prompt, and/or enforce a `TextField`/`TextEditor` character limit with visible feedback.
- **Severity:** Medium

### 7.2 Demo/fixture data regenerated on every view re-render via a stored property initializer
- **Location:** `Modules/GameRPG/Statistics/View/GameStatisticsDashboardView.swift:23-26`
- **What:** `private let previewSummary = GameStatisticsPreviewController().summary(referenceDate:calendar:)` runs the full fixture-summary builder (multiple array literals plus several `Calendar.date(byAdding:)` calls) inside the `View` struct's per-construction property initializer, and this value is threaded into the real empty-state view (shown whenever `model.summary.sessionCount == 0`), not just used in `#Preview`.
- **Why:** `View` structs are recreated on every parent redraw, so this fixture generation reruns on every re-render of the dashboard regardless of whether the empty state is even shown.
- **Action:** Compute once (a cached `static let`/lazy value on the preview controller, or construct inside the empty-state child view's own cached state) instead of an eagerly-evaluated stored property on the frequently-reconstructed root view.
- **Severity:** Medium

### 7.3 Repeated `Calendar` symbol lookup inside a per-data-point chart closure
- **Location:** `Modules/GameRPG/Statistics/View/GameStatisticsScheduleChart.swift:43-46` (`weekdayTitle(for:)`), called from within `Chart(points) { point in ... }` at lines 21 and 24
- **What:** `Calendar.autoupdatingCurrent.shortWeekdaySymbols` is fetched fresh inside `weekdayTitle(for:)`, called twice per chart point (mark value + accessibility label) on every render.
- **Why:** Small but unnecessary repeated work inside a render-hot chart closure; the symbol array is stable for the duration of a render pass.
- **Action:** Hoist `Calendar.autoupdatingCurrent.shortWeekdaySymbols` into a single value computed once per `body` evaluation, passed into `weekdayTitle(for:)`.
- **Severity:** Low

### 7.4 Inconsistent `JSONEncoder`/`JSONDecoder` allocation pattern
- **Location:** `Modules/CoreRPG/Navigator/Core/NavigationSceneStorage.swift:43-44` (shared `static let decoder`/`encoder` — the good pattern) vs. ~40 sites across `CoreRPG`/`GameRPG`/`DiceRPG`/`MapRPG`/`RuleRPG` that allocate fresh `JSONEncoder()`/`JSONDecoder()` per call, e.g. `Modules/CoreRPG/Files/FileUrl.swift:26,131`, `Modules/GameRPG/Model/GameNetworkModel.swift:1001,1011`, `Modules/MapRPG/Model/MapWallModel.swift:134,148`.
- **What:** One file already establishes a shared-instance pattern to avoid repeated allocation; most call sites still allocate fresh per use.
- **Why:** Minor — `JSONEncoder`/`JSONDecoder` allocation is cheap relative to the encode/decode work itself. Style/consistency issue, not a measured bottleneck.
- **Action:** Optional — adopt the `NavigationSceneStorage` pattern in hot paths like `GameNetworkModel`'s wire-protocol encode/decode if profiling ever shows it matters.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 `@State` in Navigator checkpoint modifiers is seeded once from an init parameter, never re-synced, and not `private`
- **Location:** `Modules/CoreRPG/Navigator/Core/NavigationCheckpoint.swift:293-316` (`NavigationCheckpointActionModifier`), `:318-340` (`NavigationCheckpointValueModifier`)
- **What:** `@State internal var checkpoint: NavigationCheckpoint<T>` is declared without `private`, and its only value comes from `init(checkpoint:...)` assigning straight into the wrapped property; it's never re-synced from the parameter after first construction. Verified by reading both modifiers directly.
- **Why:** The exact "`@State` on a passed-in value" trap: if a caller ever reapplies `.navigationCheckpoint(action:)`/`.navigationCheckpointValue(completion:)` with a changed `checkpoint` on an already-mounted view, the modifier silently keeps using the stale first-seen value.
- **Action:** Store `checkpoint` as `private let` unless the modifier genuinely needs separate mutable state; if it must diverge, forward updates explicitly via `.onChange(of:)` the way `SingleReviewLinkText.swift` does for its own seeded `@State`.
- **Severity:** High

### 8.2 View logic expressed as computed `some View` properties instead of separate `View` structs
- **Location:** `Modules/CoreRPG/Sheet/SheetEntryView.swift:120,146,167,234,253,317,334,395,420`; `Modules/CoreRPG/LGViews/ItemHeaderEditorView.swift:82,140,175,229,266`; `Modules/CoreRPG/LGViews/ListRootContextMenu.swift:87-287` (10 properties); `Modules/WeatherRPG/View/WeatherStormEditor.swift:68-112`; `Modules/CoreRPG/ItemDetail/ItemDetailContentView.swift:66-135`; `Modules/GeneratorRPG/View/PdfSummaryAnalysisView.swift:40-83`; plus ~100 more occurrences across 47 files.
- **What:** Large chunks of view hierarchy are broken into `private var xyz: some View { ... }` / `@ViewBuilder var xyz: some View { ... }` computed properties on the same `View` struct rather than extracted into their own `View` conformances.
- **Why:** The single most-repeated CLAUDE.md violation found. Computed properties give SwiftUI no independent identity/diffing boundary, so every property re-evaluates whenever the parent's `body` does — defeating extraction-based render-skipping on exactly the largest, most complex views (`SheetEntryView`, `ItemHeaderEditorView`) that would benefit most.
- **Action:** Extract each `some View` computed property into its own `private struct ...: View` taking only the data it needs.
- **Severity:** Medium

### 8.3 Icon-only buttons with no accompanying text
- **Location:** `Modules/CoreRPG/Sheet/SheetEntryAddGroupButton.swift:20-22`, `Modules/CoreRPG/Sheet/SheetEntryConvertToGroupButton.swift:17-19`
- **What:** When `onlyIcon == true`, the button's label is a bare `Image(systemName:)` with no `Text`, `Label`, or `.accessibilityLabel` — unlike 4 sibling files in the same folder (`SheetEntryAddButton`, `SheetEntryDeleteButton`, `SheetEntryTakeOverButton`, `SheetEntryQuickEditButton`), which use `Label { Text(...) } icon: { Image(...) }.applyIf(onlyIcon) { $0.labelStyle(.iconOnly) }` so VoiceOver still reads the title.
- **Why:** A VoiceOver user would hear no label at all for this control; violates the house rule that image-only buttons must pair with text. Currently `onlyIcon: true` is never passed at any call site, so this is latent, but it's public API surface other code can invoke.
- **Action:** Switch both to the same `Label`+`.labelStyle(.iconOnly)` pattern used by the sibling buttons.
- **Severity:** Medium

### 8.4 Missing `Equatable` on hot `ForEach`/`List` leaf row views
- **Location:** `Modules/CoreRPG/LGViews/ListRowItemView.swift:1-67` (rendered from `ForEach(listModel.list)` in `ItemRowsView.swift:20-38` — the app's primary item-browser row) and `Modules/CoreRPG/Sheet/SheetEntryView.swift:5-27` (rendered from `ForEach(sheetModel.entries)` in `SheetView.swift:178-196` — the primary character/rule sheet entry row)
- **What:** Neither row view conforms to `Equatable`, so SwiftUI can't cheaply skip re-diffing rows whose inputs haven't changed; both are complex rows with drag/drop, context menus, and multiple modifiers.
- **Why:** In lists with many rows, every parent-driven update re-diffs the full body of every row instead of short-circuiting unchanged ones.
- **Action:** Both currently hold existentials/generics that resist direct `Equatable` conformance (`ListRowItemView` holds `any ItemRootControllable`/`any FolderListControllable`; `SheetEntryView` is generic over `LinkType.Type` with a reference-type `rootModel`) — introduce a small `Equatable` snapshot struct capturing just the render-affecting fields and diff on that instead.
- **Severity:** Medium

### 8.5 `@FocusState.Binding` properties not marked `private`
- **Location:** `Modules/GeneratorRPG/View/SheetAIAssistantStandardControl.swift:19`, `Modules/GeneratorRPG/BasicAI/View/ChatInputView.swift:10` (`@FocusState.Binding var isTextFieldFocused: Bool`)
- **What:** Both properties are declared without `private`, unlike every other `@FocusState`-family declaration found in the sweep.
- **Why:** Minor deviation from the correctness rule that `@FocusState` properties be `private`; low practical impact since this is the `.Binding` projection meant to be supplied by the parent (functions like a `@Binding`), but still inconsistent with the stated convention.
- **Action:** Mark both `private`.
- **Severity:** Low

### 8.6 Liquid Glass adoption gap: no `tabBarMinimizeBehavior` on the primary `TabView`
- **Location:** `Modules/RolePlayGameKit/View/TabbedNavigation.swift:24-57`
- **What:** The main phone tab bar already adopts iOS 26 APIs well (`Tab(role: .search)`, `tabViewBottomAccessory`), but doesn't opt into `tabBarMinimizeBehavior(_:)` for scroll-based minimization.
- **Why:** Missed opportunity for the modern minimizing-tab-bar chrome on the app's most prominent navigation surface, on content-heavy scrollable tabs.
- **Action:** Consider `.tabBarMinimizeBehavior(.onScrollDown)` on the root `TabView`.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Core Data orphan-cleanup block duplicated verbatim across 10 modules
- **Location:** `Modules/PdfRPG/Controller/DataController.swift:49-63`, `Modules/AdventureRPG/Controller/DataController.swift:49-63`, `Modules/SpaceRPG/Controller/DataController.swift:50-64`, `Modules/PhotoRPG/Controller/DataController.swift:50-64`, `Modules/AudioRPG/Controller/DataController.swift:50-64`, `Modules/TableRPG/Controller/DataController.swift:48-62`, `Modules/WeatherRPG/Controller/DataController.swift:64-78`, `Modules/CharacterRPG/Controller/DataController.swift:65-79`, `Modules/MapRPG/Controller/DataController.swift:69-84`, `Modules/DiceRPG/Controller/DataController.swift:72-86`
- **What:** Each module's `applySnapshot(_:into:)` repeats an identical ~15-line block that diffs old vs. new entries via `unequalSet`, rebuilds `entriesModel`, and manually deletes orphaned managed objects — necessary because the Core Data inverse relationship rule is `Nullify`. Confirmed identical apart from type names via direct read/diff.
- **Why:** This orphan-delete logic is subtle — it exists specifically to avoid leaking rows locally and in CloudKit — and is hand-copied 10 times; a future correctness fix (e.g. a CloudKit merge edge case) must be manually reapplied to all 10 files or silently drifts.
- **Action:** Extract a generic helper in `CoreRPG`, e.g. `static func syncEntries<Parent: NSManagedObject, Child: NSManagedObject & CoreDataId>(update:...)`, parameterized over the entity/child types, called from each `DataController`.
- **Severity:** High

### 9.2 `ExportController` boilerplate is byte-for-byte identical in 3 modules
- **Location:** `Modules/PdfRPG/Controller/ExportController.swift:1-22`, `Modules/DiceRPG/Controller/ExportController.swift:1-22`, `Modules/GeneratorRPG/Controller/ExportController.swift:1-22`
- **What:** All three files are the same 22 lines (`struct ExportController`, `init`, `exporting(itemIds:)` forwarding to the shared `exportingSimpleEntries(itemIds:)` default) with no per-module logic.
- **Why:** Pure duplication with zero behavioral content — the real logic already lives in a shared `ExportModelBacked` default.
- **Action:** Give `ExportModelBacked`/`ItemControllable` a protocol-extension default for the whole `exporting(itemIds:)` method, and delete these 3 files, letting the modules pick up the default automatically.
- **Severity:** Medium

### 9.3 App Intents `*Entity.swift` duplicated near-verbatim across 12 modules
- **Location:** `Modules/{Adventure,Audio,Character,Dice,Generator,Map,Pdf,Photo,Rule,Space,Table,Weather}RPG/Intent/*Entity.swift` (144-211 lines each), e.g. `Modules/PdfRPG/Intent/PdfEntity.swift:1-178` vs. `Modules/CharacterRPG/Intent/CharacterEntity.swift:1-174`
- **What:** Direct diff shows the `EntityQuery`/`EntityStringQuery`/`EnumerableEntityQuery` conformance (`suggestedEntities`, `entities(for:)`) is structurally 100% identical, differing only by type name; ~8 modules additionally repeat an identical `Transferable`/`FileRepresentation` block.
- **Why:** ~2,000 total lines where most is mechanical type substitution; any fix to intent-query behavior (pagination, error handling) requires 12 hand-edits.
- **Action:** Extract a generic default `EntityQuery` implementation and shared `Transferable` conformance into `CoreRPG`, parameterized over the module's root/model/entity types.
- **Severity:** Medium

### 9.4 `Die` (6-sided) RealityKit equipment type is unreachable dead code
- **Location:** `Modules/GameRPG/Table3D/GameEquipment.swift:504-604` (full `struct Die: EntityEquipment`); referenced only in a defensive fallback at `Modules/GameRPG/Table3D/GameTableModel.swift:236-240`
- **What:** `Die(...)` is never constructed anywhere — a repo-wide grep across `Modules/GameRPG/Table3D/` returns zero instantiation sites (only `Die20(...)` is ever allocated, in `GameSetup.swift:101-102`). The only other reference is a fallback `tabletopGame.equipment(of: Die.self, matching: dieId)` branch that can never succeed since no `Die` equipment is ever added to the table.
- **Why:** ~100 lines of fully-built RealityKit entity/audio/accessibility code, plus a dead branch referencing it, sit in a hot, frequently-touched file with no runtime benefit.
- **Action:** Delete `struct Die` and the `Die.self` fallback branch in `tossDieForAccessibility`, or wire it into `GameSetup.init()` if a d6 pool is genuinely still planned.
- **Severity:** Medium

### 9.5 Oversized files (>500 lines) beyond the top 10 hot-spot files
- **Location (top 10 of ~44 additional files found):** `Modules/CoreRPG/Import/ExternalImport.swift:1-1023`; `Modules/GameRPG/Model/GameNetworkModel.swift:1-1019`; `Modules/GameRPG/Controller/PlayerControllerModel.swift:1-1015`; `Modules/CoreRPG/Sheet/SheetRootModel.swift:1-1009`; `Modules/CoreRPG/Tips/MasterRPGTips.swift:1-878`; `Modules/RolePlayGameKit/Import/Foundry/FoundryImportView.swift:1-866`; `Modules/RuleRPG/Model/RuleModel.swift:1-851`; `Modules/CharacterRPG/Controller/EditController.swift:1-833`; `Modules/CoreRPG/Foundry/FoundryRuleModels.swift:1-826`; `Modules/MapRPG/Map/MapOverlayGeometry.swift:1-821`.
- **What:** ~34 further non-test files sit between 500-800 lines (e.g. `GameRootModel.swift` 793, `SpaceViewer.swift` 791, `SearchControllable.swift` 761, `ImportControllable.swift` 750, `MapModel.swift` 742). Several of the top 10 already have clean internal `MARK` structure enabling a low-risk mechanical split: `ExternalImport.swift` has 5 MARK sections at lines 6, 93, 197, 222, 296; `MapOverlayGeometry.swift` has 3 distinct geometry concerns at lines 7, 34, 568; `RuleModel.swift` has 6 protocol-conformance extensions starting at line 518.
- **Why:** Large files are harder to navigate/review and increase merge-conflict risk.
- **Action:** Split along the existing seams — e.g. `ExternalImport.swift` → `+Provenance`/`+BatchItems`/`+Decisions`/`+Results`/`+ReviewSession`; `MapOverlayGeometry.swift` → `MapNeedleDragGeometry`/`MapAdaptiveFanPlacement`/`MapLoupeGeometry`; `RuleModel.swift` → one `RuleModel+Protocols.swift` per conformance; `MasterRPGTips.swift` → one file per its 5 existing MARK categories.
- **Severity:** Medium

### 9.6 `DataModel+Extensions.swift` relationship-accessor wrapper duplicated across 12 modules
- **Location:** `Modules/{Adventure,Audio,Character,Dice,Generator,Map,Pdf,Photo,Rule,Space,Table,Weather}RPG/Model/DataModel+Extensions.swift` (40-65 lines each)
- **What:** Each file repeats an identical `entriesModel` get/set pair and `entryOrNew(for:)` wrapper, differing only by entity type. The heavy lifting (`sortedArray<T>`, `childOrNew<Child>`) is already correctly centralized as generics in `Modules/CoreRPG/Persistence/CoreDataRelationship.swift:15-33`.
- **Why:** ~250 lines of mechanical per-type wrapper code; low drift risk since the real algorithm is already shared, but still 12 places to touch if the wrapper signature changes.
- **Action:** Optional — a protocol default with an `associatedtype Entry` could reduce this further if Core Data codegen allowed it; lower priority given the algorithm is already centralized.
- **Severity:** Low

### 9.7 `FolderListController` per-module boilerplate (12 modules)
- **Location:** `Modules/{Adventure,Audio,Character,Dice,Generator,Map,Pdf,Photo,Rule,Space,Table,Weather}RPG/Controller/FolderListController.swift` (38-40 lines each)
- **What:** Every file is identical apart from the concrete `Route` types passed to `detailDestination`/`folderDestination`/`folderInlineDestination`/`viewerDestination`.
- **Why:** Confirmed to be mechanically necessary (each module has its own `Route` enum), not a copy-paste bug source — no logic exists here to drift.
- **Action:** Low priority; a generic `FolderListController<Route: NavigationDestination>` could collapse these if per-module `Route` types were unified under one protocol, but current duplication carries minimal risk.
- **Severity:** Low

### 9.8 "reparing" typo copy-pasted into 4 modules' `LinkController.swift`
- **Location:** `Modules/AdventureRPG/Controller/LinkController.swift:172`, `Modules/CharacterRPG/Controller/LinkController.swift:129`, `Modules/MapRPG/Controller/LinkController.swift:92`, `Modules/TableRPG/Controller/LinkController.swift:92`
- **What:** All four contain the identical log string "...will be replaced from reparing links." (should be "repairing").
- **Why:** Direct evidence the log line was copy-pasted across modules; low user impact (Logger output only) but confirms the duplication pattern extends into non-generated code too.
- **Action:** Fix the typo in all 4 sites; consider moving the log call into a shared `LinkControllable` default so it exists once.
- **Severity:** Low

### 9.9 Commented-out prompt/instructions blocks in `MyAiPlayground.swift`
- **Location:** `Modules/GeneratorRPG/Playground/MyAiPlayground.swift:10-12,19-21`
- **What:** Two multi-line commented-out `Prompt`/instructions blocks remain inside an Xcode `#Playground` (canvas-only, never compiled into a shipping target).
- **Why:** Dead code inside an otherwise-legitimate file (its unconditional `print()` calls are the intended canvas output, not a leak) — just clutter, no functional risk.
- **Action:** Delete, or restore if they represent an alternate example worth keeping.
- **Severity:** Low

### 9.10 Hardcoded per-module thumbnail-size constants
- **Location:** `Modules/SpaceRPG/Controller/CacheController.swift:16` (`CGSize(width: 393, height: 350)`), `Modules/PdfRPG/Controller/CacheController.swift:21` (`CGSize(width: 210, height: 297)`), `Modules/PhotoRPG/Controller/CacheController.swift:57,63` (`64x64`, `256`), `Modules/MapRPG/Controller/CacheController.swift:31` (`1024`)
- **What:** Each module's `CacheController` hardcodes its own thumbnail/downsample target size, each with a short doc comment explaining the choice (A4 proportions, QuickLook canvas proportions, etc.).
- **Why:** Reasonably low risk since each is documented in place, but not centralized — a future global "make thumbnails 2x for retina" change means editing 4+ files individually.
- **Action:** Optional — promote to named constants in a shared `ThumbnailSizing` enum in `CoreRPG` if these are ever expected to change together.
- **Severity:** Low

### 9.11 Backlog markers are essentially clean
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:265` (`// TODO(visionOS): auto-fit the loaded model to the volumetric window's bounds`)
- **What:** A repo-wide case-insensitive sweep for `TODO|FIXME|HACK|XXX|#warning` found exactly one marker in the entire ~266K-line codebase.
- **Why:** Positive signal — no backlog debt is hidden in comments. Worth recording so this isn't re-swept from scratch in a future audit.
- **Action:** No action required beyond eventually implementing the auto-fit behavior.
- **Severity:** Low (informational)

### 9.12 `print()` usage is already clean
- **Location:** all ~30 `print(` call sites repo-wide, e.g. `Modules/DiceRPG/Space/HandTrackingModel.swift:31,41,86`, `Modules/DiceRPG/Space/DiceSpaceModel.swift:91,226`, `Modules/CoreRPG/Navigator/Core/NavigationConfiguration.swift:73`
- **What:** Every non-test, non-Preview, non-`#Playground` `print()` call is wrapped in `#if DEBUG` (verified by reading surrounding context of each hit); the remainder are inside `#Preview {}` blocks (never shipped) or the intentionally-unconditional `MyAiPlayground.swift` canvas file.
- **Why:** No leak risk found. Recorded so it isn't re-flagged from a shallow grep in a future pass.
- **Action:** None required.
- **Severity:** Low (informational)

### 9.13 Bundle/App-Group identifiers are already correctly centralized
- **Location:** `Modules/CoreRPG/App/AppGroup.swift:6,34` (`appGroupString`, `cloudContainerIdentifier`)
- **What:** A repo-wide grep for these literal strings outside `AppGroup.swift` returned zero hits — every consumer references the named constant.
- **Why:** Positive finding — exactly the duplicate-literal-key risk this audit checks for, already done correctly.
- **Action:** None required.
- **Severity:** Low (informational)

---

## 10. Cross-cutting recommendations

1. **Centralize the per-module Core Data snapshot-sync boilerplate.** §9.1 (orphan-cleanup), §9.6 (`DataModel+Extensions` wrappers), and §9.7 (`FolderListController`) are three faces of the same root cause: the 15-module architecture re-derives the same generic logic per module by hand instead of via a shared generic type. §9.1 is the one with real drift risk (subtle CloudKit-correctness logic); prioritize it, and use the same generic-extraction technique for the others opportunistically.
2. **The `MainActor.assumeIsolated` escape hatch (§3.2) deserves a standing regression test, not a one-time fix.** It's sound today, but it's a pattern relied on by 13 model types with no compiler backstop — a single shared test helper (`assertTrapsOffMainActor(_:)`) applied to each model's `Comparable`/`ItemDiffComparable` conformance would convert "personally verified" into "continuously verified."
3. **`DispatchQueue`-based scheduling is down to two known survivors** (§3.1 Navigator, §3.5 `TimedMessageList`) in an otherwise fully modern-concurrency codebase. Worth a dedicated pass to convert both to `Task`-based cancellable scheduling, closing out a rule violation that's been re-flagged across 3+ audit cycles.
4. **Computed-property view decomposition (§8.2) is the single highest-count house-rule violation** (~100+ sites). Given its volume, treat it as a backlog item tackled opportunistically whenever a touched view file is already being edited for another reason, rather than a dedicated sweep — the fix pattern is mechanical (extract to `private struct: View`) and low-risk per-site.
5. **Bare `try?` on Core Data operations (§5.1) is worth auditing beyond `ItemControllable.save()`.** This pass found it at the `ItemControllable` layer; a follow-up grep for `try? await ...save()` / `try? context.save()` across `DataController`/`SyncDataController`/`EditController` implementations would confirm whether the same silent-failure pattern recurs elsewhere in the persistence stack.

---

## 11. What was NOT audited

- **`MasterMac` and `MasterTV` schemes were not separately compiled.** The compiler ground truth (zero warnings) comes from a full clean build of the `MasterRPG` (iOS Simulator) scheme only; platform-conditional code paths reachable only under `#if os(macOS)`/`#if os(tvOS)` branches were reviewed by reading, not by a dedicated per-platform build.
- **`Tests/` — quick scan only, no deep coverage review**, per the skill's standard scope. Several test files are very large (`SharePlayPackageTransportTests.swift` at 4,082 lines, `MasterPlayerControllerTests.swift` at 2,267 lines) and were not read line-by-line; test-target duplication was noted only incidentally where it surfaced during production-code investigation.
- **`.xcdatamodeld` Core Data model files were not opened directly as raw XML.** Optional/default-value compliance with the CLAUDE.md CloudKit rule was assessed via the mapped Swift model layer and the security agent's targeted read, not a field-by-field audit of the model editor's underlying schema.
- **Algorithmic correctness of the RealityKit/Table3D 3D rendering pipeline, and bit-level correctness of the Foundry LevelDB/Snappy/WAL binary-format readers.** Surface-level issues (force-unwraps, bounds) were flagged; the underlying parsing/decompression algorithms were not independently re-derived against the LevelDB/Snappy spec.
- **`RPGTabletopGameContent` SPM package (visionOS 3D content) and all other SPM dependencies** (`swift-custom-dump`, `swift-snapshot-testing`, `swift-syntax`, `xctest-dynamic-overlay`) — treated as black boxes.
- **Localization wording/correctness** — a dedicated `Docu/LOCALIZATION_ACCESSIBILITY_AUDIT.md` already exists in this repo for that scope; not re-derived here.
- **Instruments profiling / measured runtime performance.** Performance findings in §7 and the `Docu/SWIFTUI_PERFORMANCE_AUDIT.md` companion report are pattern-based (source reading), not trace-validated; no `.trace` capture was taken as part of this pass.
- **Xcode project/build-settings structure beyond what's visible in `project.pbxproj`'s deployment-target and warning-flag settings**, and scheme configuration beyond the one scheme built for ground truth.
- **StoreKit 2 product configuration in App Store Connect** — file/code structure only (`Sources/MasterRPG/PackageProducts.swift`, `Modules/RolePlayGameKit/InApp/`), not whether each product ID matches what's actually configured in App Store Connect.
- **The `Docu/CODE_AUDIT_1.md`–`_4.md`, `SWIFTUI_PERFORMANCE_AUDIT.md`, and `xcode-security-audit-scratchpad.md` reports already in this repo** were used as a cross-reference to avoid re-reporting already-fixed issues, but this report was independently derived from current source, not copied from them — treat this file as the current source of truth and the `Docu/` reports as historical record.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line. The following High-severity findings (this pass found zero Critical-severity findings — every Critical-bar claim from the initial agent sweeps was demoted on review, since none met the "crash/data-loss/memory-corruption/security-exposure, verified reachable" bar) were personally spot-verified by opening the cited file and reading the surrounding code, not just trusting the sub-agent's report:

- **§3.1** — opened `Modules/CoreRPG/Navigator/Core/NavigationSend.swift`, lines 107-114. Confirmed `DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.send(values: values) }` inside the `.auto` case, with no stored task/cancellation handle.
- **§3.2** — opened `Modules/PdfRPG/Model/PdfModel.swift`, lines 102-113. Confirmed `extension PdfModel: nonisolated Comparable` with `<` wrapped in `MainActor.assumeIsolated { lhs.name < rhs.name }`, and the `merge` conformance at lines 117-139 using the same pattern.
- **§5.1** — opened `Modules/CoreRPG/Controllable/ItemControllable.swift`, lines 374-384. Confirmed `try? await dataControllable?.batchDelete(ids:)`, `try? await dataControllable?.save()`, and `try? await dataControllable?.flushPendingOperations()` with no surrounding `do`/`catch` or logging.
- **§5.2** — opened `Modules/SpaceRPG/Space/EntityGestureState.swift`, lines 80-198. Confirmed `fatalError` guards at lines 106,127,158 and force-unwraps `pivotEntity.parent!`/`state.targetedEntity!` at line 192; confirmed via grep that `EntityGestureState.shared` (line 48, `@MainActor static let shared`) has no other external mutation points within `Modules/SpaceRPG`.
- **§5.3** — opened `Modules/AdventureRPG/Root/AdventureRootModel.swift`, lines 105-108 and 188-189. Confirmed `_linkRegisterController` is `nil`-initialized and only set in `setUp(root:context:batchContext:)`; confirmed the force-unwrapping accessor `{ _linkRegisterController! }`. Cross-checked via `grep -rn "_linkRegisterController" Modules/*/Root/*.swift` that no other of the 11 modules' root models declares this optional-storage-plus-force-unwrap pattern (e.g. `CharacterRootModel.setUp` takes `linkRegisterController` as a plain non-optional parameter instead).
- **§6.1** — opened `Modules/GameRPG/Network/GameJoinCodeModel.swift`, lines 72-89 (confirmed 4-digit numeric `randomCode()`) and `Modules/GameRPG/Network/ConnectionAttemptThrottle.swift`, lines 1-50 (confirmed the 3-strikes/exponential-backoff/300s-cap throttle `actor`, with an in-code comment explicitly referencing a prior audit finding it was written to close).
- **§8.1** — opened `Modules/CoreRPG/Navigator/Core/NavigationCheckpoint.swift`, lines 285-340. Confirmed both `NavigationCheckpointActionModifier` and `NavigationCheckpointValueModifier` declare `@State internal var checkpoint` (not `private`), assigned once in `init` with no subsequent re-sync path.
- **§9.1** — opened `Modules/PdfRPG/Controller/DataController.swift`, lines 40-65. Confirmed the `unequalSet(lhs: &model.entriesUpdate, ...)` orphan-cleanup block matches the pattern described, including the `// The inverse rule is Nullify...` comment explaining why manual deletion is needed.

If any finding doesn't reproduce when you visit the line, flag the specific reference for re-investigation.
