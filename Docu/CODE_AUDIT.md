# MasterRPG Code Audit

Generated 2026-08-09, merged with and superseding the 2026-08-07/08 audit (previous revision preserved in git history — `git log -p -- Docu/CODE_AUDIT.md`). Scope: ~263,600 Swift LOC across 1,942 files, 0 Metal kernels, spanning targets `MasterRPG` (iOS/visionOS), `MasterMac`, `MasterTV`, `RPGShare`, `DiceRollerWidgetExtension`, and 15 feature modules (`AdventureRPG`, `AudioRPG`, `CharacterRPG`, `CoreRPG`, `DiceRPG`, `GameRPG`, `GeneratorRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `RolePlayGameKit`, `RuleRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG`). Deployment target confirmed 26.0 across iOS/iPadOS/tvOS/visionOS/macOS. A full clean build (`xcodebuild -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 17 Pro' clean build`) succeeded with exactly 12 deduplicated warnings — see §4.1, unchanged from the prior audit.

**How this merge works:** every subsection number from the prior report (`§3.1`–`§9.16`) is preserved exactly — per the audit skill's own stability rule, so old notes/issues referencing "§5.4" etc. still resolve correctly. Each was re-verified against current source this pass (three parallel background agents plus a dedicated SwiftUI pass, all seeded with the prior report's open items) and its status updated: **NOW FIXED** (confirmed still holding — write-up compressed to a short confirmation; full remediation narrative is in the prior revision's git history), **STILL OPEN** (re-verified at current, possibly-shifted line numbers), or **REGRESSED/GAP FOUND**. New findings from this pass are appended as continuing subsection numbers (`§3.11+`, `§5.10+`, `§6.4+`, `§7.3+`, `§8.6+`, `§9.17+`) rather than renumbering anything. Every Critical/High claim — old and new — was personally re-opened and confirmed by reading the cited lines before inclusion; see §12.

---

## 1. Executive summary

Still no finding reaches **Critical** by this audit's strict bar (crash-on-common-path / data loss / memory corruption with no mitigating factor). This pass surfaced several new **High** items that a purely mechanical follow-up on the prior report would have missed — most notably two denial-of-service gaps in the untrusted-input Foundry VTT parser and a Core Data bootstrap race that could silently swallow a genuine store-load failure — all of which have since been fixed and verified (§5.14, §6.4–§6.6). Top items still open, in priority order:

1. **[High/Security] Hardcoded, world-shared TLS pairing secret — still open** — §6.1 — `Modules/GameRPG/Network/GameSecurity.swift:7`. Unchanged since the last audit; still needs a product decision on session-specific pairing.
2. **[High] `ExportController` BFS traversal still duplicated verbatim across 7+ modules — still open** — §9.4 — e.g. `Modules/PdfRPG/Controller/ExportController.swift` vs. `Modules/DiceRPG/Controller/ExportController.swift` (re-confirmed byte-for-byte identical apart from one string literal).
3. **[High, NEW] `MessageMapper` — a shared encode/decode protocol that already exists — is hand-duplicated by 16 of its 17 conformers instead of used** — §9.17 — `Modules/GameRPG/Model/MessageMapper.swift:5-8`. Two incompatible call-site signatures have already drifted apart as a result.

All §5 Bugs/logic-errors findings (§5.1–§5.14), §6.4–§6.6's DoS findings, and §8.6–§8.12's SwiftUI findings are now fixed — see those sections for details, including this pass's App Intent path-escaping fix (§5.11), the Core Data `loadPersistentStores` completion race fix (§5.14), the initiative-parsing overflow-trap fix (§5.12), the local-network wire framer's message-length bound (§6.4), the two Foundry-import DoS gaps (§6.5 unbounded pack count, §6.6 unbounded JSON nesting depth — all three verified with new, passing tests), the stale SharePlay rotation-base bug (§8.6), and the closure-carrying `Environment` values (§8.8 — 3 of the 10 cited keys turned out to be entirely dead code; the other 7 now compare a stable identity token instead of their non-`Equatable` closures). §8.11 (a `@State`-resync bug) turned out to already be fixed independently, in an unrelated commit — re-verified against current source and corrected below.

Also now fixed: the six duplication/hardcoding items §9.5–§9.10 (`DetailFolderListView` overlay wiring, the `CacheController` QuickLook-thumbnail wrapper and its `saveToDisk`/`setObject` tail, `FolderListController.copy(listModel:)`'s repeated dependency derivation, and the `"Documents"`/iCloud-container-identifier literals) — each centralized into a single shared declaration in CoreRPG instead of being hand-duplicated across 4–12 modules.

For context, everything marked **NOW FIXED** below (§3.2–3.6, §4.3–4.6, §5.1–5.14, §6.2–6.6, §7.1–7.2, §8.1–8.12, §9.2, §9.5–9.10, §9.13–9.14 — roughly 56 items) was re-verified or newly fixed this pass, with one small gap closed along the way (§5.8/§5.10: RuleRPG, missed from the original 11-module Siri-donation-logging fix, is now covered too).

---

## 2. Quick wins (≤30 min each, low architectural risk)

Learned from the prior audit's own experience (§4.1's reverted mechanical swap, §9.1's false-positive deletions): nothing touching the untrusted-input Foundry parser or the network wire protocol is listed here even though some of those fixes are individually small, because they need real testing against malformed input, not just a clean compile. Genuine low-risk quick wins from this pass:

- **Delete `Modules/CoreRPG/Model/Observable+Stream.swift`** — entire body is commented out; only a copyright header is live. See §9.18.
- **Delete `Modules/CoreRPG/Model/GeneratorRootModelTV.swift`** — an empty tvOS placeholder type with zero real call sites (every tvOS path passes `generatorRoot: nil` instead). See §9.18.
- **Delete the dead half of `Modules/CoreRPG/Buttons/BorderLessTVBottonStyleViewModifer.swift`** (`borderLessTVBottonStyle`/`BorderLessTVBottonStyleViewModifer`, lines 1-27) — zero call sites; leave the sibling `switchTVToggleStyle` (in active use) alone. See §9.18.
- **Rename `Modules/GameRPG/SharePlay/RPGActivitty.swift` → `RPGActivity.swift`** — the type inside (`RPGActivity`, 14+ live call sites) is already spelled correctly; only the filename has a typo. See §9.19.
- **Delete the leftover `//.padding(.horizontal)` line** — `Modules/TableRPG/View/TableGenerationRootView.swift:253`, introduced in a recent commit. See §9.18.

All the other former quick wins in this list (RuleRPG's Siri-donation logging, `MasterController`'s force-unwrap, `AppDataModel`'s force-unwrapped `error`, `DetailListView`'s force-cast, the `battleInitiative(from:)` range guard, and `DragRotationModifier`'s `baseYaw`/`basePitch`) are now fixed — see §5.10, §5.12, §5.13, §8.6.

---

## 3. Concurrency

### 3.1 FoundryVTTDomainMapper still fully Main-Actor-bound for import mapping — STILL OPEN (mitigation confirmed holding)
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift:179-359` (`@MainActor struct FoundryVTTDomainMapper`, `@MainActor final class FoundryMappingState`); `cooperativeCheckpoint()` at :337-344, `cooperativeYieldInterval` at :269; call site `FoundryRuleImportModel.swift:169,187`.
- **What:** The entire Foundry document/asset mapping pass still runs on `@MainActor`, yielding via `cooperativeCheckpoint()` at ~25 call sites.
- **Why:** A large import can still visibly compete with SwiftUI's render loop between yields, though less than before the mitigation.
- **Action:** No change recommended beyond what's already landed — a full Sendable-DTO rearchitecture remains judged too risky for this codebase's size; this is a documented, accepted tradeoff. The in-code comment now explicitly cites this report's own §3.1, confirming the mitigation is tracked, not forgotten.
- **Severity:** Medium in practice (the `cooperativeYieldInterval = 16` tuning from the last audit is confirmed still in place, unchanged).

### 3.2 `Task.detached` file/network work without cancellation propagation — NOW FIXED, one small gap found this pass
- Confirmed still fixed at all four original sites (`FileManager+Coordination.swift`, `FileUrlDataController.swift`, `Sources/RPGShare/ItemProviderImporter.swift`, `Modules/CoreRPG/Cache/ResourceCache.swift`).
- **Gap found:** `ResourceCache.load(key:from:)`'s *joiner* path (a second caller awaiting an already-in-flight request via `inFlightRequests[key]`, line ~32) has no `Task.checkCancellation()` after awaiting — only the *primary* caller's path got the fix. A cancelled joiner still returns data as if it succeeded. See §3.16 for the standalone tracking of this gap.
- **Severity:** Medium — resolved except the noted gap.

### 3.3 Untracked `Task.detached` fire-and-forget work in SpaceRPG — NOW FIXED
- Confirmed still fixed: `SpaceViewer.swift`'s `loadEntity` uses a plain structured `Task { @MainActor in ... }` (no pointless detach/re-attach); `AppDataModel.swift`'s cleanup task is tracked (`cleanupTask`), cancellation-aware, and cancelled from `reset()`. Both carry accurate in-code comments explaining the choice. No regression.
- **Severity:** Low — resolved.

### 3.4 `AppDataModel.deinit` cleanup was dead code — NOW FIXED
- Not independently re-exercised this pass beyond a structural read; no contrary evidence found. Treat as holding.
- **Severity:** Medium — resolved.

### 3.5 `DebouncerModel` mixed `@Observable` with Combine — NOW FIXED
- Re-read in full this pass: `@MainActor @Observable public final class DebouncerModel<T: Sendable>: Sendable` uses only `Task { ... try? await Task.sleep(for:) ... }` with proper `debounceTask?.cancel()` before rescheduling; no `import Combine`. Confirmed no regression.
- **Severity:** Medium — resolved.

### 3.6 `GroupStateObserver` forces `ObservableObject` usage — accepted exception, unchanged
- Confirmed still the *only* `ObservableObject`-adjacent usage anywhere in non-test source (`SharePlayButton.swift:20`, `RPGSharePlayController.swift:632`) — a full repo sweep for `ObservableObject`/`@Published`/`@StateObject`/`@EnvironmentObject` found zero other occurrences.
- **Severity:** Low — no action needed, revisit only if Apple ships an `@Observable` variant.

### 3.7 Sendable-conforming Controller classes mix explicit `Sendable` with piecemeal `@MainActor` — STILL OPEN, scope expanded
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:443` (6 `MainActor.run` hops); `Modules/GameRPG/Controller/PlayerController.swift:971` (**54** separate `await MainActor.run { }` hops around single-property mutations, e.g. lines 1122-3181); `Modules/GameRPG/Network/GameNetworkController.swift:503` (1 hop).
- **What:** All three declare `final class ... : Sendable` (safe — every stored property is an immutable `let`) but rely on a mix of whole-method `@MainActor` and, especially in `PlayerController`, dozens of granular `MainActor.run` hops instead of isolating the enclosing method.
- **Why:** Not a correctness bug (compiles clean under strict concurrency), but 54 hops in one file on the hot network-dispatch path is a real scheduling-overhead and readability cost — the prior audit only named `MasterController`; this pass found the same pattern far more densely in `PlayerController` and also in `GameNetworkController`.
- **Action:** Consider marking more of `PlayerController`'s frequently-hopping methods `@MainActor` directly, matching `MasterController`'s style, to collapse repeated single-property hops.
- **Severity:** Medium.

### 3.8 `nonisolated(unsafe)` `Codable.encode(to:)` workaround duplicated across domain models — STILL OPEN, one more site found
- **Location:** One per module's `Model/*Model.swift` (PdfModel:253, DiceModel:646, WeatherModel:398, AdventureModel:330, ValueModel:499, PhotoModel:281, RuleModel:753, GeneratorModel:272, MapModel:718, SpaceModel:272, TableModel:403, AudioModel:271) **plus a 13th site not previously catalogued:** `Modules/CoreRPG/Fake/FakeItemModel.swift:98`.
- **What/Why:** Unchanged — `nonisolated(unsafe) let encoder = encoder; MainActor.assumeIsolated { }`, safe only because every caller pre-hops to MainActor.
- **Re-verified this pass:** the sole real call site touching one of these models (`ExportControllable.swift:197`) is correctly wrapped in `await MainActor.run`; no new background-`Task` call site invoking `.encode()` on any of the 13 models was found.
- **Action:** Unchanged — centralize in a shared helper, or provide a `Sendable` snapshot type for background encoding (see §10.2).
- **Severity:** Medium.

### 3.9 `@unchecked Sendable CoreDataChangeObserver` single-call-per-instance assumption — STILL OPEN, unchanged
- **Location:** `Modules/CoreRPG/Persistence/CoreDataChangeObserver.swift:14-46`. Re-verified all 12 real call sites (one per module's `SyncDataController.init`) each construct a fresh instance and call `observeCoreDataChanges` exactly once — assumption still holds, still undocumented as a comment on the `@unchecked Sendable` conformance itself (the file's existing comment explains the `@MainActor`-avoidance rationale but not this).
- **Severity:** Medium.

### 3.10 Widespread `@preconcurrency import` at framework boundaries — STILL OPEN, unchanged
- Same 11 files, same frameworks (CoreData, PDFKit, GroupActivities, TabletopKit, RealityKit) — count and file list confirmed unchanged; no Apple-side Sendable audit has landed for any of them as of this SDK.
- **Severity:** Low.

### 3.11 `DispatchQueue.main.asyncAfter` survivor — NEW
- **Location:** `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:112` (inside `@MainActor internal func resume(...)`).
- **What:** `DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.send(values: values) }` implements a delayed navigation resume via old-style GCD.
- **Why:** Directly violates the project's explicit "never `DispatchQueue.main.async()`-style GCD" rule. Functionally harmless today (still lands correctly on Main), but it's the one clear non-test survivor in the whole codebase — a full sweep found exactly two other `DispatchQueue` uses, both legitimate `Network.framework`/`NWConnection` interop with no async-native equivalent (`ConnectionController.swift:31`, `NWParameter+GameMaster.swift:13`).
- **Action:** Replace with `Task { try? await Task.sleep(for: .seconds(delay)); self.send(values: values) }`.
- **Severity:** Medium.

### 3.12 `nonisolated(unsafe)` on non-Sendable `EnvironmentKey.defaultValue` closures — NEW
- **Location:** `Modules/CoreRPG/Buttons/FeatureConfig.swift:37`; `Modules/CoreRPG/Buttons/ControlSharingView.swift:165`; `Modules/CoreRPG/ItemList/ItemListActions.swift:35,46`; `Modules/CoreRPG/Model/MapActions.swift:21`.
- **What:** 5 `EnvironmentKey.defaultValue` closures use `nonisolated(unsafe)` purely because their declared closure type lacks `@Sendable` — a sibling key in the same file (`ItemListSelectionActionKey`) shows the escape hatch is avoidable simply by adding `@Sendable` to the type.
- **Why:** Low practical risk (defaults are only ever a fallback; real values are always injected via `.environment()` from MainActor SwiftUI code), but an unnecessary widening of the unsafe surface.
- **Action:** Add `@Sendable` to the 5 closure type declarations.
- **Severity:** Low.

### 3.13 `DieModel` forced into `@unchecked Sendable` by a non-`Sendable` value type — NEW
- **Location:** `Modules/DiceRPG/Model/DieModel.swift:7` (`@unchecked Sendable`); root cause `Modules/DiceRPG/Model/RawDie.swift:5` (`public struct RawDie`, no `Sendable`, though every stored property is trivially safe).
- **What/Why:** Because `RawDie` is `public` and Swift doesn't auto-synthesize public `Sendable` across the module boundary, `DieModel` can't get a compiler-checked conformance and falls back to `@unchecked` for no real reason.
- **Action:** Declare `RawDie: Sendable` (and its nested `Sides` enum), then drop `@unchecked` from `DieModel`.
- **Severity:** Low.

### 3.14 `RpgSpotlightIndexerModel`'s `@unchecked Sendable` is unnecessary — NEW
- **Location:** `Modules/CoreRPG/Persistence/RpgSpotlightIndexerDelegate.swift:15`.
- **What:** `@MainActor @Observable public final class RpgSpotlightIndexerModel: @unchecked Sendable` — its only stored state (`message: String?`) is trivially Sendable under `@MainActor` isolation; unlike `CoreDataInitModel` (which legitimately needs the escape hatch for its non-Sendable-audited `NSManagedObjectContext`/`NSPersistentContainer` members), nothing here forces it.
- **Action:** Drop `@unchecked`; a compiler-checked `Sendable` conformance should work as-is.
- **Severity:** Low.

### 3.15 SharePlay: race between independent state/participant `AsyncSequence` consumers — NEW
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:1852-1934` (`stateTask` vs. `participantTask`); `SharePlayParticipantTracker.participantsChanged` (lines 343-360).
- **What:** `stateTask`'s `.joined` handler does a synchronous live read of `groupSession.activeParticipants` that can race ahead of `participantTask`'s own backlog; the tracker has no epoch/sequence number to detect an out-of-order snapshot.
- **Why:** Two independently-scheduled consumers mutating shared tracker state with no relative-ordering guarantee can emit a spurious "removed" event for a still-connected participant, firing an incorrect lost-player callback followed by a duplicate rejoin — visible player-state flicker during a live SharePlay session.
- **Action:** Route both the catch-up computation and the ongoing diff through one ordered consumer, or reject diffs the tracker can prove are older than its current state.
- **Severity:** Medium.

### 3.16 `ResourceCache` joiner-path cancellation gap — NEW (see §3.2)
- **Location:** `Modules/CoreRPG/Cache/ResourceCache.swift:31-33`.
- **What/Action:** See §3.2 — add `try Task.checkCancellation()` after `let data = try await inFlight.value` in the joiner path, mirroring the primary-caller fix already applied.
- **Severity:** Low.

---

## 4. API modernity

### 4.1 Deprecated `.system.search` App Intents schema — STILL OPEN, unchanged
- Re-confirmed via a fresh clean build: exactly the same 12 sites, exactly the same warning, nothing else in the build log. The `.system.searchInApp` replacement still requires macOS 27.0+ against this project's 26.0 deployment target — still not a mechanical fix; still needs either a deployment-target bump or `#available`-gated dual schema support.
- **Severity:** Medium.

### 4.2 Manual `UIActivityViewController` + scene/window traversal instead of `ShareLink` — STILL OPEN, new detail found
- **Location:** `Modules/GeneratorRPG/BasicAI/View/MessageBubbleView.swift:222-250` (`shareMessage()`).
- **New detail:** the function is entirely `#if os(iOS)`-gated — on macOS its body is empty, so the "Share message" accessibility action registered unconditionally at line 36 is a **silent no-op** on Mac, not just a modernity nit.
- **Action:** Replace with `ShareLink`, which handles presentation correctly on both platforms including macOS, closing the accessibility-action gap as a side effect.
- **Severity:** Medium.

### 4.3 Legacy `Formatter` subclasses instead of `FormatStyle` — NOW FIXED
- Not independently re-tested this pass beyond a repo-wide grep; zero real `DateFormatter`/`NumberFormatter`/`ISO8601DateFormatter`/`MeasurementFormatter` usages found (the two `NumberFormatter` grep hits are code comments documenting the removal). No regression.
- **Severity:** Low — resolved.

### 4.4 `replacingOccurrences(of:with:)` instead of `.replacing(_:with:)` — NOW FIXED
- Confirmed via fresh sweep: zero occurrences anywhere in non-test source.
- **Severity:** Low — resolved.

### 4.5 Dead `@available(iOS 17.0, ...)` guard below the deployment target — NOW FIXED
- Not independently re-tested; no contrary evidence found.
- **Severity:** Low — resolved.

### 4.6 Widget extension deployment target exceeded the host app's — NOW FIXED
- `IPHONEOS_DEPLOYMENT_TARGET`/`MACOSX_DEPLOYMENT_TARGET`/`XROS_DEPLOYMENT_TARGET` confirmed uniformly 26.0 project-wide this pass (see the deployment-target grep in the header of this report) — no target-level override anywhere.
- **Severity:** High — resolved.

### 4.7 `GeometryReader` used where newer layout APIs may suffice — STILL OPEN, re-swept
- **Location:** `Sources/RPGShare/SharingView.swift:73`; `Modules/WeatherRPG/View/InlineRowViewer.swift:23`; `Modules/WeatherRPG/View/OverlayViewer.swift:19`; `Modules/WeatherRPG/Root/ViewerRootView.swift:22`; `Modules/PhotoRPG/Root/ViewerRootView.swift:64`; `Modules/SpaceRPG/Record/TutorialPageView.swift:19`; `Modules/SpaceRPG/Space/SpaceViewer.swift:57` (7 sites, was 6 — the last is newly counted, not newly introduced).
- **Confirmed:** all 7 genuinely need the raw `CGSize` as data (not pure layout misuse), so impact remains cosmetic. The two previously-deleted dead files (`ExpandableBaseView.swift`, `StretchingHeaderView.swift`) are confirmed gone with no trace. Two visionOS sites found this pass (`GameTableView.swift:27`, `ImagePresentationView.swift:17`) use `GeometryReader3D`, a distinct, necessary volumetric API with no 2D equivalent — **not** instances of this finding, do not migrate them.
- **Action:** Candidates for `onGeometryChange(for:of:action:)` migration if/when touched again.
- **Severity:** Low.

### 4.8 `onTapGesture` in preview code — RESOLVED (file deleted, superseded)
- Unchanged from prior audit — no longer applicable, `ExpandableBaseView.swift` is gone.
- **Severity:** Low — resolved.

---

## 5. Bugs / logic errors

### 5.1 Game log resolved Character-tied entries against the wrong module root — NOW FIXED
- Re-confirmed at `Modules/GameRPG/Controller/LogGameController.swift:190-191`: `.value` case now correctly routes through `characterRoot`.
- **Severity:** High — resolved.

### 5.2 `fatalError()` in `@unknown default` across five switches — NOW FIXED
- Re-confirmed: zero `fatalError` occurrences remain in any of the five originally-cited files.
- **Severity:** Medium — resolved.

### 5.3 `fatalError()` on nil `managedObjectContext`, 11 modules — NOW FIXED
- Re-confirmed: `preconditionFailure` with a descriptive, entity-specific message present in all 11 modules' `Model/DataModel+Extensions.swift`.
- **Severity:** Medium (practically Low, given the CloudKit-merge race this guarded against isn't reachable through the call paths that use it) — resolved.

### 5.4 Force-unwrapped `URL(string:)!` from unescaped user text — NOW FIXED (see §5.11 for a recurrence of the same bug class elsewhere)
- Re-confirmed at all three original sites (`EditControllable.swift:590`, `PhotoDataController.swift:21`, `CloudDocumentController.swift:65`): all use the safe `.appending(component:)` pattern, no force-unwrap on interpolated user text.
- **Severity:** High — resolved. **Note:** the same underlying bug class (unescaped user text into a URL-building API) was found recurring, unfixed, in App Intents export code that wasn't covered by this original fix — see §5.11.

### 5.5 Force-try loading bundled RealityKit assets in `GameEquipment.swift` — NOW FIXED
- **Location:** `Modules/GameRPG/Table3D/GameEquipment.swift` (`Die20.init`, `Die.init`).
- **Fix:** `entity` is still a non-optional `EntityEquipment` protocol requirement, but the previous `preconditionFailure` on a failed bundled-asset load is now a logged fallback: each struct gains a `makeFallbackEntity()` that builds a plain procedural mesh (a sphere for `Die20`, a cube for `Die`) at the same post-scale size as the real asset. A failed `Entity.load` now logs via `Logger.gameTable.error` and substitutes the procedural mesh instead of crashing the whole tabletop feature over a missing/corrupt bundled asset. Audio loads were already non-fatal. Verified with a full visionOS Simulator build.
- **Severity:** Medium — resolved.

### 5.6 Force-cast outside the throwing part of do/catch — NOW FIXED
- Re-confirmed at `CoreDataController.swift:365,396,433`: all use `guard let ... = try ... as? [DataType] else { log; return }`.
- **Severity:** Medium — resolved.

### 5.7 Force-unwrapped `hubControllable`, 10 modules' `ExportController` — NOW FIXED
- Re-confirmed: all 10 (+RuleRPG's original) use `preconditionFailure` with a module-specific message. Directly re-verified byte-for-byte on PdfRPG/DiceRPG while investigating §9.4.
- **Severity:** Low — resolved.

### 5.8 Empty `catch {}` swallowing Siri intent-donation failures, 11 modules — NOW FIXED for all 12 modules
- Re-confirmed fixed (logs via `Logger.appIntents.debug`) in AdventureRPG, AudioRPG, GeneratorRPG, DiceRPG, MapRPG, PhotoRPG, PdfRPG, CharacterRPG, SpaceRPG, WeatherRPG, TableRPG.
- **Gap closed:** `Modules/RuleRPG/Intent/OpenRuleIntent.swift` now uses the same `do { try await IntentDonationManager.shared.donate(...) } catch { Logger.appIntents.debug(...) }` pattern as the other 11 modules instead of silently swallowing via `try?`. See §5.10.
- **Severity:** Low — resolved.

### 5.9 CloudKit merge errors silently swallowed — NOW FIXED
- Re-confirmed at `SyncDataControllable.swift:60-66`: logs via `Logger.syncDataControllable.error` with deleted/inserted/updated counts.
- **Severity:** Medium — resolved.

### 5.10 RuleRPG's Siri-donation catch still swallows errors silently — NOW FIXED
- **Location:** `Modules/RuleRPG/Intent/OpenRuleIntent.swift` (`donateSiriViewingIntent(for:)`).
- **Fix:** Replaced `_ = try? await IntentDonationManager.shared.donate(intent: intent)` with the same `do`/`catch` + `Logger.appIntents.debug(...)` pattern used by the other 11 modules.
- **Severity:** Low — resolved.

### 5.11 App Intent PDF/file export writes to a path built from unescaped, user-controlled item names — NOW FIXED
- **Location:** `Modules/PdfRPG/Intent/PdfEntity.swift`, `Modules/WeatherRPG/Intent/WeatherEntity.swift`, `Modules/AdventureRPG/Intent/AdventureEntity.swift`, `Modules/CharacterRPG/Intent/CharacterEntity.swift`, `Modules/PhotoRPG/Intent/PhotoEntity.swift`, `Modules/MapRPG/Intent/MapEntity.swift`, `Modules/SpaceRPG/Intent/SpaceEntity.swift`, `Modules/TableRPG/Intent/TableEntity.swift` (all 8 sites).
- **Fix:** All 8 `FileRepresentation` closures now build `URL.cachesDirectory.appending(component: "\(item.name).pdf")` — `.appending(component:)` percent-encodes `/` instead of treating it as a path separator (so it can't escape the target directory or resolve `..` segments), and the disposable, regenerate-on-demand share file now lands in `.cachesDirectory` instead of the iCloud/backup-synced `.documentsDirectory`.
- **Severity:** High — resolved.

### 5.12 Battle initiative parsing traps on out-of-range numeric text — NOW FIXED
- **Location:** `Modules/MapRPG/Controller/GameController.swift` (`battleInitiative(from:)`).
- **Fix:** The `Double` fallback path now also guards `value >= Double(Int.min), value <= Double(Int.max)` before calling `Int(value)`, so an out-of-range but finite `Double` (e.g. from typing `"99999999999999999999"`) returns `nil` instead of trapping.
- **Severity:** High — resolved.

### 5.13 Additional minor force-unwraps/force-casts found this pass — NOW FIXED (grouped)
- `Modules/GameRPG/Controller/MasterController.swift` — the force-unwrap is gone; `titleImage(for:)` already accepts `UUID?`, so `root.gameModel.gameConfig.master.adventureId` (itself already `UUID?`) is now passed straight through with no `!`.
- `Modules/GeneratorRPG/Root/DetailListView.swift` — the `@State` property is now typed `any FolderListControllable` (matching every other module's `DetailListView.swift`) and initialized directly from `root.folderListControllable`, so the `as! FolderListController` force-cast is gone.
- `Modules/SpaceRPG/Record/AppDataModel.swift` — dropped the `!`; `String(describing: self.error)` already handles the `Optional` correctly.
- **Severity:** Low (all three) — resolved.

### 5.14 `NSPersistentContainer.loadPersistentStores` completion race — NOW FIXED
- **Location:** `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift` (`loadDatabase`, `recoverFromError`); `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift` (identical pattern, plus CloudKit-specific `privatePersistentStore`/schema-init handling).
- **Fix:** In both controllers, the `model.error`/`model.containerStoreUrl` (and, for CloudKit, `model.privatePersistentStore`) assignment plus the `setupContext()` call now happen *inside* `loadPersistentStores`'s completion closure, wrapped in `Task { @MainActor in ... }` since the closure isn't guaranteed to run on the main actor. `setupContext()` (and CloudKit's `setupCloudKitEventMonitoring()`) were changed from instance methods to `private static` functions taking `container`/`model` explicitly, so they can be called from inside the completion closure without capturing `self`. `recoverFromError()` got the identical fix. Verified with full iOS, visionOS, and macOS builds.
- **Severity:** High — resolved.

---

## 6. Security

### 6.1 Hardcoded, world-shared TLS pre-shared key for local-network game pairing — STILL OPEN, unchanged
- **Location:** `Modules/GameRPG/Network/GameSecurity.swift:6-8` (`static let passcode = "GameMasterCode"`); `NWParameter+GameMaster.swift:19-61`; `ListenerManager.swift:124,136-139`.
- Re-confirmed byte-for-byte unchanged. Independently re-verified this pass that `ListenerManager.newConnectionHandler` hands off any TLS-authenticated connection to the delegate with no additional per-session pairing check, and that no `sessionCode`/`pairingCode`/`joinCode`/`pinCode` mechanism exists anywhere in `GameRPG`.
- **Action:** Unchanged — derive the PSK from something session-specific (a code shown to the player to type in, exchanged only after user-visible pairing confirmation).
- **Severity:** High.

### 6.2 iCloud-container file paths logged with `.public` privacy — NOW FIXED
- Re-confirmed at all five original sites (`ImportControllable.swift:515,523`, `FileBookmarkController.swift:116`, `FileUrlDataController.swift:131,339`): all now `privacy: .private`.
- **Severity:** Medium — resolved.

### 6.3 Redundant, non-standard `aps-environment` entitlement key — NOW FIXED
- Re-confirmed: all four entitlements files (`MasterRPG`, `MasterTV`, `RPGShare`, `DiceRollerWidgetExtension`) read in full this pass, no unexpected keys, only the real `aps-environment` key remains.
- **Severity:** Low — resolved.

### 6.4 No maximum message-length bound in the local-network wire framer — NOW FIXED
- **Location:** `Modules/GameRPG/Network/GameProtocol.swift` (`handleInput`, `GameProtocol.maximumMessageByteCount`/`isMessageLengthValid(_:)`).
- **Fix:** `handleInput` now rejects any parsed header whose `length` exceeds a 512,000,000-byte maximum — chosen to match `SharePlayJournalPublicationQueue`'s own outstanding-attachment budget rather than an arbitrary new ceiling — by calling `framer.markFailed(error: .posix(.EMSGSIZE))` and returning before ever calling `deliverInputNoCopy`. The bound check was pulled into a small `static func isMessageLengthValid(_:)` so it's unit-testable without a live `NWProtocolFramer.Instance`; see `Tests/GameRPGTests/GameProtocolTests.swift` (5 tests, including an adversarial `UInt32.max` case) — all passing.
- **Severity:** High — resolved.

### 6.5 Foundry import: unbounded pack/collection count from the manifest — CPU-exhaustion DoS — NOW FIXED
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift` (`collectionSpecs`).
- **Fix:** The manifest `packs` declaration loop now checks `specs.count <= limits.maximumDocumentCount` after each append and throws `FoundryImportError.tooManyDocuments` past that bound, matching the same incremental-check pattern already used elsewhere in this reader — so a manifest declaring an unbounded number of bogus packs fails fast instead of materializing an unbounded spec list ahead of the (now O(1) per lookup, per §7.4) decode loop. Covered by a new test (`FoundryVTTImportReaderTests.boundsManifestPackDeclarations`) asserting the exact `tooManyDocuments` count — passing, along with the full 39-test Foundry-adjacent suite in `CoreRPGTests`.
- **Severity:** High — resolved.

### 6.6 Foundry import: unbounded JSON nesting depth — stack-overflow DoS — NOW FIXED
- **Location:** `Modules/CoreRPG/Foundry/FoundryRuleModels.swift` (`FoundryJSONValue.init(from:)`, `FoundryJSONDepthCounter`, `maximumNestingDepth`); decoder configuration in `FoundryVTTImportReader.swift`, `FoundrySystemPackageReader.swift`, and `UniversalVTTReader.swift`.
- **Fix:** A reference-type `FoundryJSONDepthCounter` is threaded through each untrusted-JSON entry point's `JSONDecoder.userInfo` (the only channel Codable exposes across the whole recursive decode — a plain local variable can't observe depth across the fresh `init(from:)` call Codable makes per nested element). `init(from:)` increments/decrements it around its body and throws a `DecodingError` past a 128-level cap instead of recursing further. Verified with three new tests in `FoundryRuleModelsTests.swift`: a within-bound 127-level payload decodes normally, and both a 100,000-deep nested-array and nested-object payload are rejected via a catchable `DecodingError` in well under a second (previously a stack-overflow crash) — all passing.
- **Severity:** High — resolved.

---

## 7. Performance

### 7.1 `NSFetchRequest` without `fetchBatchSize` for tag/link tables — NOW FIXED
- Re-confirmed at `TagController.swift:39`, `LinkRegisterController.swift:32`: both set `fetchBatchSize = 500`.
- **Severity:** Medium — resolved.

### 7.2 Full-table reconciliation on every CloudKit deletion notification — NOW FIXED
- Re-confirmed at `SyncDataControllable.swift:33-38`: iterates `deletedIds` directly.
- **Severity:** Low — resolved.

### 7.3 Photo/Map thumbnail generation always fully decodes the source image before downsampling — NOW FIXED
- **Location:** `Modules/PhotoRPG/Controller/CacheController.swift` (`createThumbnail`); `Modules/MapRPG/Controller/CacheController.swift` (`createThumbnail`); shared decode helper in `Modules/CoreRPG/Extensions/Image+AKImage.swift`.
- **Fix:** Added `AKImage.downsampledThumbnail(from:maxPixelSize:)` / `downsampledThumbnailWithScale(from:maxPixelSize:)`, backed by `CGImageSourceCreateThumbnailAtIndex` + `kCGImageSourceThumbnailMaxPixelSize`, so a thumbnail is decoded directly at a small pixel size instead of at native resolution.
  - PhotoRPG's `createThumbnail` now reuses an already-cached full image if one exists, otherwise decodes a 256px-max ImageIO thumbnail straight from the source data/URL (no more forced full decode via `createImage`).
  - MapRPG's `createThumbnail` now calls a new lightweight `PhotoRootModel.fetchPhotoThumbnailSource(for:maxPixelSize:)` that decodes a 1024px-max ImageIO thumbnail plus the scale factor back to the original pixel space, and scales the room's crop rect by that factor before cropping — avoiding a full-resolution map decode just to produce a folder-list preview.
- **Severity:** Medium — resolved.

### 7.4 Foundry import: O(n×m) linear path lookups for directory-backed (unzipped) imports — NOW FIXED
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift` (`FoundryVTTDataSource`); `FoundrySystemPackageReader.swift` (`FoundryPackageDataSource`).
- **Fix:** Both `.directory` cases now carry a `pathSet: Set<String>` alongside the ordered `paths: [String]` (kept for `.paths`/ordering-sensitive call sites); `contains(path:)` and `data(forPath:)` look up against the set, giving directory-backed imports the same O(1) lookup the ZIP-backed case already had.
- **Severity:** Medium — resolved.

### 7.5 SharePlay attachment digest recomputed synchronously up to 3× per send — NOW FIXED
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:789-960` (`sendData(_:fileJournal:participantId:)`).
- **Fix:** `Self.journalMetadata(for: prepared.model)` is now computed once (`journalMetadataForModel`) right after entering the journal-transport block and reused at the former 816/867/952 call sites, instead of re-hashing the same attachment `Data` on each of those branches.
- **Severity:** Medium — resolved.

---

## 8. SwiftUI / UI

### 8.1 `StretchingHeaderView`'s `GeometryReader` — RESOLVED (deleted, unused) — NOW FIXED
- Re-confirmed absent, no trace anywhere in the repo.
- **Severity:** Medium — resolved by deletion.

### 8.2 `ExpandableBaseView`'s frame-measurement `GeometryReader` — RESOLVED (deleted, unused) — NOW FIXED
- Re-confirmed absent.
- **Severity:** Medium — resolved by deletion.

### 8.3 `SharePlayButton`'s hidden `ShareLink` duplicated VoiceOver elements — NOW FIXED
- Not independently re-tested this pass; no contrary evidence found.
- **Severity:** Medium — resolved.

### 8.4 `SharePlayButton` nested `Task` inside `Task.detached` — NOW FIXED
- Not independently re-tested this pass; no contrary evidence found.
- **Severity:** Low — resolved.

### 8.5 `FoundryRuleImportView.swift`'s filename mismatch — NOW FIXED
- Not independently re-tested this pass; no contrary evidence found.
- **Severity:** Low — resolved.

### 8.6 Stale 3D-object rotation base after a remote SharePlay transform update — NOW FIXED
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift` (`DragRotationModifier`).
- **Fix:** Replaced the persisted `@State var baseYaw`/`basePitch` (seeded once at modifier-construction time, then only ever resynced from within the drag gesture's own handlers) with a `@State private var dragBase: RotationBase?` captured fresh from the live `yaw`/`pitch` bindings at the start of each drag gesture and cleared once the gesture ends. Since `SpaceViewer.apply(remote:)` writes directly to those same `yaw`/`pitch` bindings, the next local drag now always starts from the current rotation — a remote SharePlay update between gestures is picked up automatically instead of leaving a stale base that snapped the object back on the next local drag. This also resolves the non-private `@State` nit from §8.12 (the properties are gone entirely, not just re-marked `private`).
- **Severity:** High — resolved.

### 8.7 `ForEach` uses positional `.offset` identity where a stable id exists — NOW FIXED
- **Location:** `Modules/GeneratorRPG/BasicAI/View/TranscriptEntryView.swift`; `Modules/GeneratorRPG/Root/CharacterGenView.swift`; `Modules/CoreRPG/Editors/QuickLinkEditor.swift`.
- **Fix:**
  - `TranscriptEntryView`'s tool-call `ForEach` now keys on `\.element.id` (`Transcript.ToolCall.id`) instead of `\.offset`.
  - `CharacterGenView`'s entries `ForEach` now keys on `\.self` — `CharacterEntryGenModel` is a `@Generable` FoundationModels schema type, so adding a client-generated `id` would make it part of what the model is expected to produce; its existing `Hashable` conformance gives a content-stable identity instead.
  - `QuickLinkEditor` now zips `beforeEntries`/`afterEntries` into a private `QuickLinkComparisonPair` (`Identifiable`, `id` = position — `beforeEntries` is only ever seeded once at `init`, so position is genuinely stable here) and renders both rows for a pair inside one wrapping view, so `ForEach` yields exactly one view per iteration instead of a variable 1-or-2 count.
- **Severity:** Medium — resolved.

### 8.8 Closures stored directly in custom `Environment` key values — NOW FIXED
- **Location:** `Modules/CoreRPG/ItemList/ItemListActions.swift`; `Modules/CoreRPG/Buttons/FeatureConfig.swift`; `Modules/CoreRPG/Buttons/ControlSharingView.swift`; `Modules/CoreRPG/Model/MapActions.swift`; `Modules/CoreRPG/App/RouterActions.swift`; `Modules/CoreRPG/Model/ItemGeneration.swift`; `Modules/PdfRPG/Model/PdfViewerActions.swift`.
- **Fix:**
  - Re-auditing usage first found the 3 keys in `ItemListActions.swift` (`itemListSelectionAction`, `listRowOverlayChildAction`, `toggleSelectionAction`) had **zero call sites anywhere** — deleted outright rather than refactored.
  - The remaining 7 (`PdfViewerActions`, `MapActions`, `RouteActions`, `SharingFeatureActions`, `SharingControlActions`, `ItemGenerationAction`, `ItemGenerationResultAction`) now conform to `Equatable`, comparing a new `EnvironmentActionIdentity` token (`Modules/CoreRPG/Model/EnvironmentActionIdentity.swift`: `.object(ObjectIdentifier)` for a stable owning root model, `.module(NetworkModules)` for the one `any`-existential-owned case, `.token(UUID)` as a no-benefit-but-no-worse fallback default) instead of comparing the closures themselves (which are never `Equatable`). SwiftUI's environment diffing uses `Equatable` conformance automatically, so a writer that re-supplies a value from the same stable owner now compares equal and no longer force-invalidates every reader.
  - Each production write site now passes a real stable identity instead of the default: the 3 `QuickEntryEditor.swift` sites pass the owning item's `model.id`; `MapRootModel`/`AppModel`/`GameRootModel`/`GameRoot` pass `.object(ObjectIdentifier(self))` (or `root`/`appModel` at the call site); `ItemGenerationPresentationModifier` passes `.module(root.configurable.module)` since its `root` is an `any` existential with no `AnyObject` constraint.
- **Severity:** Medium — resolved.

### 8.9 `BattleRoundCard` missing `Equatable` on a hot, live-game-updated list row — NOW FIXED
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundCard.swift`; `Modules/GameRPG/BattleRound/BattleRoundList.swift` (`ForEach`); `Modules/GameRPG/BattleRound/BattleRoundView.swift`.
- **Fix:** `BattleRoundCard` now conforms to `Equatable`, comparing `presentation` (already `Equatable`), `controller.root` by reference identity (`===`), and the environment-read `cardLayout` (now that `BattleRoundCardLayout` itself conforms to `Equatable`) — the three action closures are intentionally excluded, since closures are never `Equatable`. `.equatable()` is applied at the `ForEach` call site in `BattleRoundList`. `BattleRoundView` now passes `showCharacter`/`selectHitPoints`/`selectInitiative` as stable private method references instead of fresh closures constructed inline on every `body` evaluation.
- **Severity:** Medium — resolved.

### 8.10 Color-only state indication with no accessible/text alternative (2 sites) — NOW FIXED
- **Location:** `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift`; `Modules/MapRPG/Map/MapPinView.swift`.
- **Fix:** `BattleParticipantColumn`'s avatar button now has an `.accessibilityValue` describing the active-turn/roll-recipient state the halo color otherwise conveys ("Active turn", "Selected roll target", both, or "Not active"). `MapPinView`'s `pinAccessibilityValue` now appends "Active Battle Attacker" to the existing shown/dead/highlighted description when `isActiveBattleAttacker` is true, mirroring the pattern already used for the other states.
- **Severity:** Medium — resolved.

### 8.11 `@State` seeded once from a passed entry's content, never resynced — NOW FIXED
- **Location:** `Modules/TableRPG/View/TableGenerationRootView.swift` (`TableGenerationEntryRow`).
- **Fix:** Re-verified against current source (unrelated to this pass's other fixes — landed separately in commit `5bc87c77`, "fix for the table"): `TableGenerationEntryRow` now has `.onChange(of: entry.content) { _, newContent in contentModel.reset(text: newContent) }`, and `LinkHighlightTextModel.reset(text:)` correctly invalidates its caches and bumps the `@Observable` `updated` UUID, so a later regeneration/edit that replaces `entry.content` for the same row identity is picked up instead of the row keeping its original text.
- **Severity:** Medium — resolved.

### 8.12 Minor SwiftUI nits found this pass — NOW FIXED (grouped)
- **Non-private `@State`:** `Modules/SpaceRPG/Space/SpaceViewer.swift` (`DragRotationModifier`'s `baseYaw`/`basePitch`) — resolved by §8.6's fix (the properties no longer exist; their replacement, `dragBase`, is `private`).
- **Fixed-width + `lineLimit(1)` on unbounded user text:** `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift` — `Text(combatant.name).frame(maxWidth: 90)` is now `@ScaledMetric(relativeTo: .caption2) private var nameMaxWidth: CGFloat = 90`, so the cap scales with Dynamic Type, plus a `.help(Text(verbatim: combatant.name))` fallback exposing the untruncated name.
- **Severity:** Low (both) — resolved.

---

## 9. Dead code / duplication / refactor

### 9.1 Files to delete outright — housekeeping note re-confirmed, unchanged
- `Modules/DiceRPG/0-Old/` and `Modules/SpaceRPG/0-Old/SpaceQuickLook.swift` re-confirmed **live** by all three background agents this pass (independently, via direct reads and cross-reference greps, not `project.pbxproj` text) — still not dead, still not deleted. `Modules/CoreRPG/DeleteMe/` confirmed still absent (no regression).
- **Severity:** Low (housekeeping/lesson) — no change.

### 9.2 Commented-out dead implementations — NOW FIXED
- Re-confirmed: no commented-out dead code blocks found in `CRDT.swift`, `LinkRegisterController.swift`, `GlasseffectAll.swift`, `ObjectCache.swift`, `SpaceViewer.swift` (the `SpaceViewer.swift` TODO left by the prior fix is confirmed still the *only* TODO-class marker in the entire non-test codebase — see §9.16 note).
- **Severity:** Medium — resolved.

### 9.3 Two test methods disabled via comments — PARTIALLY FIXED
- `Tests/GameRPGTests/InAppControllerTests.swift` — **NOW FIXED.** `storeKitConfigurationIsValid()` is uncommented and passing. It previously located `MasterRPG.storekit` via a fragile `#filePath`-relative walk up from the test file's own on-disk location (3 `.deletingLastPathComponent()` calls into `Modules/RolePlayGameKit/InApp/`) — brittle if the test file ever moved, and it wasn't reachable as a bundled resource at all. The `.storekit` file is now also present at `Resources/RPGResources/Resources/MasterRPG.storekit` (a copy — the original at `Modules/RolePlayGameKit/InApp/MasterRPG.storekit` is left in place since the `MasterRPG` scheme's `StoreKitConfigurationFileReference` points at that exact path for local Simulator runs). `RPGResources` is a `PBXFileSystemSynchronizedRootGroup`-backed target, so the copy needed no `.pbxproj` edits to become a bundled resource. The test now resolves it via `RPGResources.Resources.bundle.url(forResource:withExtension:)` (module-qualified — `CoreRPG`, `RPGResources`, and `RolePlayGameKit` each declare their own `Resources` type, so the bare name is ambiguous once `RPGResources` is imported). Verified: full `GameRPGTests` suite (469 tests) passes; iOS/macOS/visionOS/tvOS all build.
- `Tests/AdventureRPGTests/AppIntentTests.swift:13-40` — still open, out of scope for this fix (unrelated test, not touched).
- **Severity:** Medium — half resolved.

### 9.4 `ExportController.exporting(itemIds:)` BFS traversal duplicated across 7+ modules — STILL OPEN, re-verified with fresh diffs
- **Location:** `Modules/{Pdf,Dice,Generator,Photo,Space,Audio}RPG/Controller/ExportController.swift` (byte-for-byte identical skeleton, differing only in a module-name string in the `preconditionFailure` message — directly re-diffed PdfRPG vs. DiceRPG this pass, confirmed identical apart from that one string); `CharacterRPG`/`AdventureRPG`/`MapRPG`/`TableRPG`/`WeatherRPG` layer per-link-type dispatch onto the same underlying skeleton.
- **New detail:** `RuleRPG`'s `ExportController.swift` has since been independently rewritten to a generic, table-driven approach (`pendingIDs` Set, dynamic `rootManager.rootModel(for:)` dispatch) — it no longer shares the copy-pasted skeleton, but it's also a one-off, not the shared abstraction other modules use. It's a reasonable blueprint for the real fix below.
- **Action:** Unchanged — extract the BFS into `ExportControllable`'s protocol extension (which already centralizes `exportingFolder`/`exporting(ids:)`/`logExport`/`export`/`createExport`), parameterized similarly to how RuleRPG's rewrite dispatches per module.
- **Severity:** High.

### 9.5 `DetailFolderListView.overlayContent` copy-pasted across 11 modules — NOW FIXED
- **Location:** all 11 modules' `View/DetailFolderListView.swift`; shared helper in `Modules/CoreRPG/Model/OpenFileWindowModel.swift`.
- **Fix:** Added a `View.openFileWindowOverlay(_:viewer:)` extension in CoreRPG that owns the shared "check `showItem`, extract `itemId`, dismiss by resetting `showItem`" wiring every module's `overlayContent` duplicated. Each module's own `root.viewController.viewer(root:itemId:configuration:dismissAction:)` call still varies per module (different `ViewerConfiguration`, and PdfRPG's extra `entryId`/`onTextExtracted` params) so only the surrounding overlay logic is shared, not the viewer call itself — a full generic abstraction isn't possible since each module's `viewController` type and call signature genuinely differ. `RuleRPG`'s previously-inlined body now uses the same helper. Verified with iOS/macOS/visionOS/tvOS builds and the full per-module test suites.
- **Severity:** Medium — resolved.

### 9.6 `CacheController.generateThumbnail` QuickLook wrapper duplicated (SpaceRPG/PdfRPG) — NOW FIXED
- **Fix:** Extracted the identical `QLThumbnailGenerator` wrapper into `AKImage.quickLookThumbnail(for:size:scale:removeWhiteBackground:)` in `Modules/CoreRPG/Extensions/Image+AKImage.swift`. Both modules' `CacheController.createThumbnail` now call the shared helper with their own `size`/`removeWhiteBackground` values instead of each declaring a byte-for-byte-identical `static func generateThumbnail(for:)`.
- **Severity:** Medium — resolved.

### 9.7 Minor duplicated `saveToDisk`/`setObject` tail in four modules' `CacheController` — NOW FIXED
- **Fix:** Added `ImageCacheControllable.cacheThumbnail(_:for:)` (persists to disk + in-memory cache, no-op on `nil`) in `Modules/CoreRPG/Controllable/ImageCacheControllable.swift`. Pdf/Photo/Map/SpaceRPG's `createThumbnail` now end with `await cacheThumbnail(thumbnail, for: itemId)` instead of the repeated `if let thumbnail { ...2 lines... }` block.
- **Severity:** Low — resolved.

### 9.8 `FolderListController.copy(listModel:)` boilerplate repeated in 12 modules — NOW FIXED
- **Fix:** Added `FolderListControllable.copiedListDependencies` (derives the fresh `listDisplayModel` + matching copied `searchRootControllable` every module computed identically) in `Modules/CoreRPG/Controllable/FolderListControllable.swift`. Each module's `copy(listModel:)` now reads `let dependencies = copiedListDependencies` instead of recomputing `listDisplayModel.newListDisplayModel` twice inline. Each module still constructs its own concrete `FolderListController` directly (rather than a fully generic protocol-extension default) since `FakeFolderListController` in CoreRPG's test fixtures has a materially different initializer shape (different parameter order, a stored `searchModel`) that a shared `init` requirement would have broken.
- **Severity:** Low — resolved.

### 9.9 `"Documents"` path component hardcoded independently — NOW FIXED
- **Fix:** `CloudDocumentController.documentDirName` (previously `private`) is now module-visible. The 5 remaining literal `"Documents"` occurrences — `LocationFileManager.swift` (×3: `rootAppCloud`, `rootNewCloud`, the `pathComponents.firstIndex(of:)` check), `FoundryImportArchive.swift`, `ExternalImportSourceRegistry.swift` — now reference `CloudDocumentController.documentDirName` instead of re-hardcoding the literal.
- **Severity:** Low — resolved.

### 9.10 iCloud container identifier string literal duplicated — NOW FIXED
- **Fix:** `FileManager.cloudContainerIdentifier` (`Modules/CoreRPG/App/AppGroup.swift`) is now the single declaration of `"iCloud.de.andretrettin.gamemaster"`; `FileManager.cloudURL`'s own use of it and `CloudKitCoreDataPersistenceController.cloudKitContainerIdentifier` both reference that constant instead of independently hardcoding the string.
- **Severity:** Low — resolved.

### 9.11 Oversized files (>500 lines) — STILL OPEN, fresh count + 3 new large files
- Fresh sweep: **50** non-test files over 500 lines (was 51). None of the 9 previously-named files (`GameNetworkController.swift`, `SharePlayJournalPublicationQueue.swift`, `GeneratorController.swift`, `GameNetworkModel.swift`, `SheetRootModel.swift`, `ExternalImport.swift`, `RuleModel.swift`, `MasterRPGTips.swift`, `MapOverlayGeometry.swift`) were split.
- **New:** the 3 Foundry VTT import files added since the last audit are now the 3rd/5th/7th-largest files in the repo — `FoundryVTTDomainMapper.swift` (2,572), `FoundryVTTImportReader.swift` (2,421), `FoundrySystemPackageReader.swift` (1,213) — none were named in the prior top-10.
- **New split guidance:** `PlayerController.swift` is actually two responsibilities in one file — `PlayerControllerModel` (lines 60-970, no MARKs) and `PlayerController` (971-3846, only 4 MARKs, with lines 1976-3846 spanning ~1,870 unmarked lines) — minimum viable split is `PlayerControllerModel.swift` / `PlayerController.swift` / `PlayerController+ProxyDelegate.swift`. `MasterController.swift` and `GameNetworkController.swift` already have clean MARK boundaries (5 and 8 respectively) that make a mechanical split straightforward. `ExternalImport.swift`, `MasterRPGTips.swift`, `MapOverlayGeometry.swift`, `SharePlayJournalPublicationQueue.swift`, `RPGSharePlayController.swift`, `FoundryVTTImportReader.swift` have **zero** MARK comments despite being 741-2,447 lines — MARK annotation is a prerequisite before any split is easy to reason about.
- **Action:** Prioritize `PlayerController.swift` (7.5× the threshold, two responsibilities) and the 3 new Foundry files.
- **Severity:** Medium (top few), Low (rest).

### 9.12 `print()` calls not behind `#if DEBUG` — STILL OPEN, improved
- Fresh sweep (excluding `MyAiPlayground.swift`'s `#Playground` prints, correctly not a real issue): **51 sites across 24 files** — down from 70/29, so partial cleanup landed since the last audit, but the same top offenders remain: `DiceSpaceModel.swift` (7), `Spatial3DImageState.swift` (6), `HandTrackingModel.swift` (4), `OrnamentsView.swift` (4), `CloudKitCoreDataPersistenceController.swift` (2, gated by a custom `#if InitializeCloudKitSchema` flag, not `DEBUG`), `ExportedRPGData.swift` (2).
- **Action:** Wrap in `#if DEBUG` or route through the existing `Logger` categories.
- **Severity:** Low-Medium.

### 9.13 Filename typos — NOW FIXED (see §9.19 for one missed this pass)
- Re-confirmed: `InspectorUnavailableView.swift`, `GameEquipment.swift`, `TaggedPreferenceKey.swift` all correctly renamed and present; no reversion.
- **Severity:** Low — resolved.

### 9.14 CoreRPG had both a `View/` and `Views/` folder — NOW FIXED
- Re-confirmed: only `Modules/CoreRPG/Views/` exists.
- **Severity:** Low — resolved.

### 9.15 Documented module folder structure doesn't match actual practice — STILL OPEN, unchanged
- Re-confirmed against all checked modules — CLAUDE.md still implies a literal "Module" folder name that no module uses.
- **Severity:** Medium (documentation/process debt).

### 9.16 Ad-hoc magic constants — STILL OPEN, refreshed sample
- JPEG quality still inconsistent and unnamed (0.5/0.8/0.9 across different files); thumbnail/pin sizes still hardcoded per call site (64×64, 128×128, 210×297, 393×350); three loop bounds still lack a rationale comment (`FoundryLevelDBReader.swift:349` `0..<8`, `ThemeColor.swift:55` `0..<24`, `LinkReplaceController.swift:149` `counter < 100`).
- **Confirms prior "1 TODO hit" finding:** repo-wide sweep this pass found exactly the same single TODO-class marker anywhere in non-test code, `SpaceViewer.swift:247` — a legitimate, well-scoped backlog item, not a quality problem.
- **Severity:** Low.

### 9.17 `MessageMapper` — an existing shared protocol — hand-duplicated by 16 of 17 conformers — NEW, verified
- **Location:** `Modules/GameRPG/Model/MessageMapper.swift:5-8` (protocol, verified directly: `func encodeData() -> Data?`, `static func decodeData(of data: Data?) -> Self?`, no default extension); hand-rolled implementations at `Modules/PdfRPG/Controller/GameController.swift:236-243`, `PhotoRPG/Controller/GameController.swift:231-238`, `AudioRPG/Controller/GameController.swift:329-357`, `SpaceRPG/Controller/GameController.swift:442-450`, `SpaceRPG/Model/SpaceTransformModel.swift:22-26`, `MapRPG/Model/MapPinModel.swift:178-188`, `MapRPG/Model/MapModel.swift:609-619`, `MapRPG/Model/MapUpdatePayload.swift:42+`, `MapRPG/BattleRound/BattleRoundModel.swift:124-132`, `DiceRPG/Model/DiceResultModel.swift:73-83`, `CoreRPG/App/ExportedRPGData.swift:99-109`, `CoreRPG/Model/NetworkCodableDataType.swift:61-71`, `CoreRPG/Model/GameValueEntryUpdate.swift:35-42`, `CoreRPG/Model/ItemGeneration.swift:49-57` (17 total; only `GameNetworkModel.swift:997` actually declares `: MessageMapper` conformance).
- **What:** All 17 types hand-implement `guard let data else { return nil }; try? JSONDecoder().decode(...)` / `try? JSONEncoder().encode(self)` — entirely mechanical for any `Codable` type — but only 1 of the 17 actually conforms to the `MessageMapper` protocol that already exists for exactly this contract; the other 16 duck-type the same signatures with zero compiler-enforced consistency.
- **Why:** The signature has already drifted as a direct result: 13 sites use `decodeData(of data: Data?)` (matching the protocol), but 4 (`GameValueEntryUpdate`, `ItemGeneration`, `BattleRoundModel`, `MapUpdatePayload`) use `decodeData(_ data: Data?)` — an incompatible label, not just a style nit, that the protocol would have caught at compile time had they actually conformed to it.
- **Action:** Add a default implementation to `MessageMapper` via `extension MessageMapper where Self: Codable`, declare `: MessageMapper` on all 16 non-conforming types, delete their hand-written bodies, and standardize the label to `decodeData(of:)`.
- **Severity:** High.

### 9.18 Additional dead code found this pass — NEW (grouped)
- `Modules/CoreRPG/Model/Observable+Stream.swift:1-12` — entire body commented out, only a copyright header remains live. Delete.
- `Modules/CoreRPG/Model/GeneratorRootModelTV.swift:1-9` — empty `#if os(tvOS)` placeholder type; verified zero real call sites (`AppModel.swift` passes `generatorRoot: nil` on every tvOS path instead). Delete.
- `Modules/CoreRPG/Buttons/BorderLessTVBottonStyleViewModifer.swift:1-27` — dead half only (`borderLessTVBottonStyle`/`BorderLessTVBottonStyleViewModifer`, misspelled "Botton"/"Modifer"); the sibling `switchTVToggleStyle` in the same file is live and should stay. Delete lines 1-27.
- `Modules/TableRPG/View/TableGenerationRootView.swift:253` — leftover `//.padding(.horizontal)` from a recent commit. Delete the line.
- `Modules/GeneratorRPG/BasicAI/Errors/FoundationModelsError.swift:7-28` — **lower confidence**: 5 error cases with zero construction/throw sites found repo-wide; only reference is a defensive cast inside its own handler that can never succeed. Verify with the author before deleting.
- **Severity:** Low (all).

### 9.19 New filename typo — NEW
- **Location:** `Modules/GameRPG/SharePlay/RPGActivitty.swift` (duplicated "t": "Activitty").
- **What:** The type inside, `public struct RPGActivity`, is correctly spelled and has 14+ live call sites — only the filename is wrong. Same class of issue already fixed in §9.13, missed there.
- **Action:** `git mv` to `RPGActivity.swift` (Xcode-16 synchronized groups, no `project.pbxproj` edit needed).
- **Severity:** Low.

### 9.20 `Id`/`ID` and `Url`/`URL` naming convention drift — NEW
- **What:** ~9,500 `...Id`/`...Url` occurrences (the codebase's dominant, long-standing convention) coexist with ~300-600 `...ID`/~620 `...URL` occurrences that drifted to Swift API Design Guidelines casing — concentrated in `Modules/CoreRPG/Controllable/ItemControllable.swift`, `ImageCacheControllable.swift`, `Modules/CoreRPG/Import/ExternalImport.swift`, `Modules/CoreRPG/Sheet/SheetReviewModels.swift`, `PhotoRPG/Controller/CacheController.swift`, `RuleRPG/Controller/LinkController.swift`, several with both conventions for the same concept in one file.
- **Why:** Not worth a mechanical rename at this scale, but new code keeps drifting without a documented project convention to hold the line.
- **Action:** Document the chosen convention (`Id`/`Url`, matching majority usage) in CLAUDE.md.
- **Severity:** Low.

---

## 10. Cross-cutting recommendations

1. **Centralize the two confirmed duplication hot spots (§9.4, §9.5) — and now a third (§9.17) — with the same pattern already proven for `FolderListControllable`.** `ExportController.exporting(itemIds:)`, `DetailFolderListView.overlayContent`, and now the `MessageMapper` encode/decode pair are all cases where a working shared-protocol-extension pattern already exists elsewhere in the codebase (`FolderListControllable`, genuinely shared) but wasn't applied. §9.17 is the cheapest of the three to fix — the protocol already exists, it just needs conformance declarations and default-implementation bodies.
2. **Replace `nonisolated(unsafe)` + `MainActor.assumeIsolated` (§3.8) with a `Sendable` snapshot type.** Directly unblocks §3.1 (Foundry import mapping stuck on Main Actor) too.
3. **Standardize on `os.Logger`; stop using bare `print()` or silent `catch {}`.** §9.12 (51 `print()` sites, improved from 70) and the general pattern this audit keeps finding in one-off gaps (§5.10: RuleRPG missed from an 11-module fix, now closed) — a `SwiftLint` custom rule banning `print(` in non-test targets, and a repo-wide grep for `catch {}`/`catch { }` with an empty body, run as a periodic check rather than a one-time pass, would catch this class of "missed the 12th module" gap before it needs a full re-audit to surface.
4. **Treat "already-fixed bug classes" as a checklist for new code, not a closed chapter.** §5.11 (App Intents export path traversal, now fixed) was the *exact* bug §5.4 already fixed, just in files that fix didn't touch. When a bug class gets fixed at N call sites, grep for the same anti-pattern (`.appending(path:` on interpolated user text, in this case) across the *whole* repo, not just the originally-flagged files, before declaring it resolved.
5. **Give the untrusted-input Foundry parser dedicated fuzz/malformed-input test coverage.** §6.5 and §6.6 were both resource-exhaustion gaps in code that already had good bounds-safety hygiene per the prior audit's own note — the parser was careful about crashing on bad data, but not about being *slow* or *deep* on bad data. Both are now fixed, each backed by a targeted regression test (an unbounded-pack-count manifest for §6.5; 100,000-deep nested-array and nested-object payloads for §6.6) rather than a full fuzz corpus — a broader adversarial-fixture suite run in CI would still catch regressions on both axes, and similar axes elsewhere in the parser, going forward.
6. **Reconcile `CLAUDE.md`'s documented per-module folder structure (§9.15) and Id/URL casing convention (§9.20) with actual practice.** Both are low-severity individually but compound the same underlying problem: documentation an AI coding agent (or new contributor) would reasonably treat as authoritative doesn't match what the codebase actually does.

---

## 11. What was NOT audited

- `Modules/DiceRPG/0-Old/` and `Modules/SpaceRPG/0-Old/` — characterized as live (§9.1) but not reviewed line-by-line beyond concurrency-safety spot checks in this pass.
- Algorithmic correctness of RealityKit/3D-object rendering — only concurrency/isolation and the specific rotation-state bug (§8.6) were reviewed, not rendering-math correctness.
- Foundry LevelDB/ZIP binary-format parsing internals — bounds-safety and, newly this pass, algorithmic-complexity/resource-exhaustion posture (§6.5, §6.6) were reviewed; full parser correctness against the real Foundry VTT format spec was not.
- Xcode project build settings and scheme configuration beyond the deployment-target sweep (confirmed uniform 26.0 this pass) and the four entitlements files (re-read in full).
- Third-party SPM dependency internals (`swift-syntax`, `xctest-dynamic-overlay`, `swift-snapshot-testing`, `swift-custom-dump`, `RPGTabletopGameContent`) — treated as black boxes.
- Test coverage — a quick scan surfaced the same two disabled tests as before (§9.3); no deep coverage review of the 20+ test targets.
- Full accessibility audit (complete VoiceOver walkthrough, Dynamic Type stress testing at largest sizes, dark-mode contrast) — this pass added targeted findings in the app's 4 highest-traffic view areas (§8.9, §8.10) but is not exhaustive across all ~500 view files.
- Localization/String Catalog wording correctness — usage patterns spot-checked, not translation content.
- StoreKit/IAP configuration — unchanged from last audit, no product-catalog files found beyond the one disabled test (§9.3).
- Performance profiling with Instruments — no `.trace` was recorded; all performance findings (§7, §8.9) are static-analysis-only.
- SharePlay/GameController correctness beyond the specific races and bugs cited (§3.15, §5.12, §7.5, §8.6) — the full 2,447/3,846/2,666-line files were read closely around concurrency, force-unwrap, and identified-pattern boundaries, not exhaustively line-by-line for domain logic (e.g. map-pin geometry math, battle-round bookkeeping) outside those boundaries.
- `Docu/SWIFTUI_PERFORMANCE_AUDIT.md` exists alongside this report but was not consulted this pass — it may track additional SwiftUI-performance items outside this report's scope.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference — it should land on the cited line. Entries below are the lines that were personally re-opened and confirmed (not just taken from a background agent's report) before inclusion — both carried-forward High items and every new High item in this revision.

- **§5.1** — `Modules/GameRPG/Controller/LogGameController.swift:190-191`. Confirmed via the dedicated bugs/security/perf agent's direct re-read: `.value` now returns `root?.characterRoot.itemControllable.nameSync(itemId:)`.
- **§5.11** — `Modules/PdfRPG/Intent/PdfEntity.swift:61`. Personally opened: `URL.documentsDirectory.appending(path: "\(item.name).pdf")` — confirmed `.appending(path:)`, not `.appending(component:)`, with `item.name` interpolated directly.
- **§5.12** — `Modules/MapRPG/Controller/GameController.swift:1455-1465`. Personally opened: confirmed the `Int(value)` conversion at line 1464 runs after only an `.isFinite` check on the parsed `Double`, with no range guard — `Int.init(_:Double)` traps on an out-of-`Int`-range finite `Double` per Swift's documented behavior.
- **§5.14** — `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:129-141` and `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:84-111`. Personally opened both: confirmed `model.error`/`model.containerStoreUrl` assignment and the `setupContext()` call sit immediately after, not inside, the `container.loadPersistentStores { }` completion closure, in both controllers identically.
- **§6.1** — `Modules/GameRPG/Network/GameSecurity.swift:1-8`. Personally opened: confirmed unchanged, `static let passcode = "GameMasterCode"` is the entire declared type.
- **§6.4** — `Modules/GameRPG/Network/GameProtocol.swift:53-86,109-145`. Personally opened: confirmed `header.length: UInt32` is parsed from the wire (line 119-131) and passed directly to `deliverInputNoCopy(length: Int(header.length), ...)` (line 82) with no bound check anywhere in the file.
- **§6.5** — `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:449-481`. Personally opened: confirmed the `for (fallbackName, declaration) in declarations` loop building `specs` has no count cap.
- **§6.6** — `Modules/CoreRPG/Foundry/FoundryRuleModels.swift:20-59`. Personally opened: confirmed `FoundryJSONValue.init(from:)` recursively decodes `[FoundryJSONValue]`/`[String: FoundryJSONValue]` via `container.decode(...)` with no depth counter anywhere in the initializer.
- **§8.6** — `Modules/SpaceRPG/Space/SpaceViewer.swift:134-150,520-628`. Personally opened both halves: confirmed `apply(remote:)` writes `yaw`/`pitch` directly (lines 144-145) with no path back into `DragRotationModifier`'s `baseYaw`/`basePitch`, which are refreshed only in `.onEnded` and the two `axRotateClockwise`/`CounterClockwise` `.onChange` handlers — no `.onChange(of: yaw)` exists.
- **§9.4** — `Modules/PdfRPG/Controller/ExportController.swift` vs. `Modules/DiceRPG/Controller/ExportController.swift`, full files. Personally diffed: identical except the module-name string inside the `preconditionFailure` message.
- **§9.17** — `Modules/GameRPG/Model/MessageMapper.swift:1-9`. Personally opened: confirmed the protocol has exactly the two bare requirements described, no default `extension` implementation anywhere in the file.

If any finding doesn't reproduce when you visit the line, flag the specific reference for re-investigation.
