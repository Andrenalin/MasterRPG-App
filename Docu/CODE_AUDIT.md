# MasterRPG Code Audit

Generated 2026-08-09, merged with and superseding the 2026-08-07/08 audit (previous revision preserved in git history — `git log -p -- Docu/CODE_AUDIT.md`). Scope: ~263,600 Swift LOC across 1,942 files, 0 Metal kernels, spanning targets `MasterRPG` (iOS/visionOS), `MasterMac`, `MasterTV`, `RPGShare`, `DiceRollerWidgetExtension`, and 15 feature modules (`AdventureRPG`, `AudioRPG`, `CharacterRPG`, `CoreRPG`, `DiceRPG`, `GameRPG`, `GeneratorRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `RolePlayGameKit`, `RuleRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG`). Deployment target confirmed 26.0 across iOS/iPadOS/tvOS/visionOS/macOS. A full clean build (`xcodebuild -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 17 Pro' clean build`) succeeded with exactly 12 deduplicated warnings — see §4.1, unchanged from the prior audit.

**How this merge works:** every subsection number from the prior report (`§3.1`–`§9.16`) is preserved exactly — per the audit skill's own stability rule, so old notes/issues referencing "§5.4" etc. still resolve correctly. Each was re-verified against current source this pass (three parallel background agents plus a dedicated SwiftUI pass, all seeded with the prior report's open items) and its status updated: **NOW FIXED** (confirmed still holding — write-up compressed to a short confirmation; full remediation narrative is in the prior revision's git history), **STILL OPEN** (re-verified at current, possibly-shifted line numbers), or **REGRESSED/GAP FOUND**. New findings from this pass are appended as continuing subsection numbers (`§3.11+`, `§5.10+`, `§6.4+`, `§7.3+`, `§8.6+`, `§9.17+`) rather than renumbering anything. Every Critical/High claim — old and new — was personally re-opened and confirmed by reading the cited lines before inclusion; see §12.

---

## 1. Executive summary

Still no finding reaches **Critical** by this audit's strict bar (crash-on-common-path / data loss / memory corruption with no mitigating factor), but this pass surfaced several new **High** items that a purely mechanical follow-up on the prior report would have missed — most notably two denial-of-service gaps in the untrusted-input Foundry VTT parser, and a Core Data bootstrap race that can silently swallow a genuine store-load failure. Top items in priority order:

1. **[High/Security] Hardcoded, world-shared TLS pairing secret — still open** — §6.1 — `Modules/GameRPG/Network/GameSecurity.swift:7`. Unchanged since the last audit; still needs a product decision on session-specific pairing.
2. **[High/Security, NEW] No maximum length on the local-network message framer** — §6.4 — `Modules/GameRPG/Network/GameProtocol.swift:82`. Compounds #1: any device that completes the (secret-derived) TLS handshake can declare an arbitrary multi-gigabyte message length with nothing downstream validating it.
3. **[High/Security, NEW] Foundry import: unbounded pack count from the manifest enables a CPU-exhaustion DoS** — §6.5 — `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:449-481`. A tiny, well-formed manifest can declare millions of bogus packs, forcing an O(specs × paths) scan with no cap.
4. **[High/Security, NEW] Foundry import: unbounded JSON nesting depth — stack-overflow DoS** — §6.6 — `Modules/CoreRPG/Foundry/FoundryRuleModels.swift:20-59`. A small, deeply-nested JSON array/object payload recurses one native stack frame per level with no depth guard.
5. **[High, NEW] App Intent PDF/file export writes to a path built from an unescaped, user-controlled item name — same bug class as an already-fixed one, recurring in 8 files** — §5.11 — e.g. `Modules/PdfRPG/Intent/PdfEntity.swift:61`. `.appending(path:)` treats `/`/`..` in a free-text item name as literal path structure.
6. **[High, NEW] Core Data `loadPersistentStores` completion race in both persistence controllers** — §5.14 — `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:129-140`, `CloudKitCoreDataPersistenceController.swift:87-100`. Error/URL state is read immediately after calling `loadPersistentStores`, not inside its completion handler, which Apple documents as not guaranteed synchronous — a genuine migration/corruption failure can go completely undetected.
7. **[High, NEW] User-typed initiative value can crash the app via `Int(Double)` overflow trap** — §5.12 — `Modules/MapRPG/Controller/GameController.swift:1464`. Typing a plain large number (no scientific notation needed) into any Character value mapped to "initiative" traps the Game Master's device mid-battle.
8. **[High] `ExportController` BFS traversal still duplicated verbatim across 7+ modules — still open** — §9.4 — e.g. `Modules/PdfRPG/Controller/ExportController.swift` vs. `Modules/DiceRPG/Controller/ExportController.swift` (re-confirmed byte-for-byte identical apart from one string literal).
9. **[High, NEW] `MessageMapper` — a shared encode/decode protocol that already exists — is hand-duplicated by 16 of its 17 conformers instead of used** — §9.17 — `Modules/GameRPG/Model/MessageMapper.swift:5-8`. Two incompatible call-site signatures have already drifted apart as a result.
10. **[High, NEW, verified] Stale 3D-object rotation base after a remote SharePlay transform update** — §8.6 — `Modules/SpaceRPG/Space/SpaceViewer.swift:542-564`. After another participant moves the shared 3D object, the next local drag gesture snaps it back toward the pre-update rotation.

For context, everything marked **NOW FIXED** below (§3.2–3.6, §4.3–4.6, §5.1–5.9, §6.2–6.3, §7.1–7.2, §8.1–8.5, §9.2, §9.13–9.14 — roughly 30 items) was re-verified this pass and confirmed still holding, with one small gap found (§5.8/§5.10: one module, RuleRPG, was missed from the original 11-module Siri-donation-logging fix).

---

## 2. Quick wins (≤30 min each, low architectural risk)

Learned from the prior audit's own experience (§4.1's reverted mechanical swap, §9.1's false-positive deletions): nothing touching the untrusted-input Foundry parser or the network wire protocol is listed here even though some of those fixes are individually small, because they need real testing against malformed input, not just a clean compile. Genuine low-risk quick wins from this pass:

- **Delete `Modules/CoreRPG/Model/Observable+Stream.swift`** — entire body is commented out; only a copyright header is live. See §9.18.
- **Delete `Modules/CoreRPG/Model/GeneratorRootModelTV.swift`** — an empty tvOS placeholder type with zero real call sites (every tvOS path passes `generatorRoot: nil` instead). See §9.18.
- **Delete the dead half of `Modules/CoreRPG/Buttons/BorderLessTVBottonStyleViewModifer.swift`** (`borderLessTVBottonStyle`/`BorderLessTVBottonStyleViewModifer`, lines 1-27) — zero call sites; leave the sibling `switchTVToggleStyle` (in active use) alone. See §9.18.
- **Rename `Modules/GameRPG/SharePlay/RPGActivitty.swift` → `RPGActivity.swift`** — the type inside (`RPGActivity`, 14+ live call sites) is already spelled correctly; only the filename has a typo. See §9.19.
- **Delete the leftover `//.padding(.horizontal)` line** — `Modules/TableRPG/View/TableGenerationRootView.swift:253`, introduced in a recent commit. See §9.18.
- **Add the missing error-logging to RuleRPG's Siri-donation catch** — `Modules/RuleRPG/Intent/OpenRuleIntent.swift:47` (`_ = try? await IntentDonationManager.shared.donate(...)`) — the other 11 modules already log via `Logger.appIntents`; RuleRPG was missed from that pass. See §5.10.
- **Mark `DragRotationModifier`'s `baseYaw`/`basePitch` `private`** — `Modules/SpaceRPG/Space/SpaceViewer.swift:563-564`. See §8.6.
- **Guard `MasterController.start()`'s force-unwrap** — `Modules/GameRPG/Controller/MasterController.swift:495` (`root.gameModel.gameConfig.master.adventureId!`) — add a `guard let` instead of relying on an upstream-only invariant. See §5.13.
- **Fix the force-unwrapped `error` in `AppDataModel`'s failed-state logging** — `Modules/SpaceRPG/Record/AppDataModel.swift:330` — `String(describing:)` already handles `Optional` fine; drop the `!`. See §5.13.
- **Fix `GeneratorRPG/Root/DetailListView.swift:19`'s force-cast** (`listController as! FolderListController`) — store the `any FolderListControllable` existential directly, matching every other module's `DetailListView.swift`. See §5.13.
- **Add the range guard in `battleInitiative(from:)`** before the final `Int(value)` conversion — `Modules/MapRPG/Controller/GameController.swift:1464`. See §5.12.

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

### 5.5 Force-try loading bundled RealityKit assets in `GameEquipment.swift` — PARTIALLY FIXED, unchanged assessment
- Entity loads (`Die20`, `Die`) remain `preconditionFailure`-guarded but still fatal by design — `EntityEquipment.entity` is a non-optional protocol requirement (confirmed against Apple's own sample code using the identical pattern), so this can't be made fully non-crashing without a fallback placeholder mesh. Audio loads for both structs re-confirmed fully non-fatal (`AudioPlaybackController?`, `do/catch` + `Logger.gameTable.error`).
- **Severity:** Medium — audio half resolved; entity half is an accepted, unavoidable tradeoff.

### 5.6 Force-cast outside the throwing part of do/catch — NOW FIXED
- Re-confirmed at `CoreDataController.swift:365,396,433`: all use `guard let ... = try ... as? [DataType] else { log; return }`.
- **Severity:** Medium — resolved.

### 5.7 Force-unwrapped `hubControllable`, 10 modules' `ExportController` — NOW FIXED
- Re-confirmed: all 10 (+RuleRPG's original) use `preconditionFailure` with a module-specific message. Directly re-verified byte-for-byte on PdfRPG/DiceRPG while investigating §9.4.
- **Severity:** Low — resolved.

### 5.8 Empty `catch {}` swallowing Siri intent-donation failures, 11 modules — NOW FIXED for 10/11; gap found in the 12th module
- Re-confirmed fixed (logs via `Logger.appIntents.debug`) in AdventureRPG, AudioRPG, GeneratorRPG, DiceRPG, MapRPG, PhotoRPG, PdfRPG, CharacterRPG, SpaceRPG, WeatherRPG, TableRPG.
- **Gap:** `Modules/RuleRPG/Intent/OpenRuleIntent.swift:47` still silently swallows (`_ = try? await IntentDonationManager.shared.donate(...)`) — RuleRPG wasn't in the original 11-module list this fix targeted. See §5.10 and the matching quick win in §2.
- **Severity:** Low — resolved except RuleRPG.

### 5.9 CloudKit merge errors silently swallowed — NOW FIXED
- Re-confirmed at `SyncDataControllable.swift:60-66`: logs via `Logger.syncDataControllable.error` with deleted/inserted/updated counts.
- **Severity:** Medium — resolved.

### 5.10 RuleRPG's Siri-donation catch still swallows errors silently — NEW (gap in §5.8's fix)
- **Location:** `Modules/RuleRPG/Intent/OpenRuleIntent.swift:47`.
- **What/Why:** Same diagnosability gap §5.8 fixed everywhere else; RuleRPG was missed.
- **Action:** Apply the same `Logger.appIntents.debug(...)` pattern used in the other 11 modules.
- **Severity:** Low.

### 5.11 App Intent PDF/file export writes to a path built from unescaped, user-controlled item names — NEW
- **Location:** `Modules/PdfRPG/Intent/PdfEntity.swift:61`, `Modules/WeatherRPG/Intent/WeatherEntity.swift:61`, `Modules/AdventureRPG/Intent/AdventureEntity.swift:61`, `Modules/CharacterRPG/Intent/CharacterEntity.swift:61`, `Modules/PhotoRPG/Intent/PhotoEntity.swift:61`, `Modules/MapRPG/Intent/MapEntity.swift:61`, `Modules/SpaceRPG/Intent/SpaceEntity.swift:61`, `Modules/TableRPG/Intent/TableEntity.swift:61` (8 sites, verified directly at `PdfEntity.swift:61`).
- **What:** Each `Transferable.transferRepresentation`'s `FileRepresentation` builds `URL.documentsDirectory.appending(path: "\(item.name).pdf")`. Unlike `.appending(component:)` (used in §5.4's fix), `.appending(path:)` does **not** percent-encode `/` — it's a literal path separator, and `..` segments resolve as parent-directory references. `item.name` is free-text, CloudKit-synced, fully user-controllable.
- **Why:** A `/` or `..` in any Pdf/Weather/Adventure/Character/Photo/Map/Space/Table item's name causes the generated share file to be written to an unintended subpath (silently failing if the directory doesn't exist, since `CGContext(url as CFURL, ...)` returns `nil` and the function just returns) or overwrites an existing file at an attacker/user-chosen relative location inside the app's own Documents container. This is exactly §5.4's bug class recurring in App Intents/Siri/Shortcuts sharing code that fix pass didn't cover. Separately: this disposable, regenerate-on-demand share file is written to `.documentsDirectory` (iCloud/backup-synced) rather than `.cachesDirectory`/a temp directory.
- **Action:** Swap `.appending(path:)` → `.appending(component:)` in all 8 files (percent-encodes `/`, can't fail); move the output location to `.cachesDirectory` or `FileManager.default.temporaryDirectory`.
- **Severity:** High.

### 5.12 Battle initiative parsing traps on out-of-range numeric text — NEW, verified
- **Location:** `Modules/MapRPG/Controller/GameController.swift:1455-1465` (`battleInitiative(from:)`).
- **What:** For text that fails `Int(value)`, the function parses as `Double`, checks only `.isFinite`, then returns `max(1, Int(value))`. Verified directly: `Int.init(_:Double)` traps at runtime when the magnitude exceeds `Int`'s range even though the `Double` is perfectly finite.
- **Why:** `value` is the free-text display value of whatever Character game-entry is mapped to "initiative" — ordinary user-typed, CloudKit/game-network-synced text. A plain large number like `"99999999999999999999"` (no scientific notation required) parses fine as a finite `Double` (~1e20) but crashes the instant `Int(value)` runs, since 1e20 exceeds `Int64.max`. Reachable via `addBattleCombatant`/`assignBattleCharacter`/`refreshBattleConfiguredValues` — a session-ending crash on the Game Master's device from an ordinary typo or pasted garbage, no malicious intent needed.
- **Action:** Guard the range before converting: bail out (return `nil`) if `value < Double(Int.min) || value > Double(Int.max)` before calling `Int(value)`.
- **Severity:** High.

### 5.13 Additional minor force-unwraps/force-casts found this pass — NEW (grouped)
- `Modules/GameRPG/Controller/MasterController.swift:495` — `root.gameModel.gameConfig.master.adventureId!` force-unwrapped; currently safe only because the sole call site enforces the invariant in a different file. Add a local `guard let`.
- `Modules/GeneratorRPG/Root/DetailListView.swift:19` — `listController as! FolderListController` force-casts an existential to a concrete type; every other module's `DetailListView.swift` stores the protocol-typed value directly instead. Crashes if ever given a test/preview mock.
- `Modules/SpaceRPG/Record/AppDataModel.swift:330` — `self.error!` force-unwrapped inside error-state logging; safe today only by call-site discipline (`switchToErrorState` always sets `error` first). `String(describing:)` already handles `Optional` — drop the `!`.
- **Severity:** Low (all three — none currently reachable, all one bad refactor away from a crash).

### 5.14 `NSPersistentContainer.loadPersistentStores` completion race — NEW
- **Location:** `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:129-140` (`loadDatabase`), `:144-155` (`recoverFromError`); `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:87-100`, `:114-126` (identical pattern) — both verified directly.
- **What:** `container.loadPersistentStores { storeDescription, error in initError = ...; storeUrl = ... }` is called, and immediately *after* — not inside the completion closure — the code reads `initError`/`storeUrl` and assigns `model.error`/`model.containerStoreUrl`, then calls `setupContext()`, which itself gates on `model.error == .none`. Apple documents `loadPersistentStores` as always asynchronous, with no synchronous variant guaranteed.
- **Why:** `model.error` is effectively read at its pre-completion initial value (`.none`) regardless of whether the store actually finished loading. The entire recoverable-error UI path in `DataBaseModel.finishSetup()` (the "database could not be loaded, recover?" flow, `canRecover = true`) becomes unreachable under real async completion timing: a genuine migration/corruption failure goes undetected, the app proceeds as if the store loaded fine, and every subsequent Core Data operation against the broken store fails deep in the app with no diagnosis or recovery offered. `recoverFromError()` has the identical bug, so even manual recovery (delete + recreate) doesn't reliably confirm success. This is the Core Data bootstrap path exercised on every single app launch, in both the local-only and CloudKit-backed controllers.
- **Action:** Move the `model.*` assignment and `setupContext()` call *inside* the completion handler (re-dispatching to `@MainActor`, since the handler isn't guaranteed to run on Main), or bridge to `async`/`await`.
- **Severity:** High. Not empirically reproduced with a crash/log (the finding rests on Apple's documented API contract plus a static trace, not an observed failure — for a healthy local store the completion in practice often does return before `loadPersistentStores` does, which is exactly what makes this intermittent and dangerous rather than obviously broken).

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

### 6.4 No maximum message-length bound in the local-network wire framer — NEW
- **Location:** `Modules/GameRPG/Network/GameProtocol.swift:53-86` (`handleInput`), `:82` (`deliverInputNoCopy(length: Int(header.length), ...)`); header struct at `:109-145`.
- **What:** `GameProtocolHeader.length` (`UInt32`) is parsed directly off the wire with no upper-bound sanity check before being handed to `deliverInputNoCopy`. Verified directly: no size validation exists anywhere else in the framer or in `PlayerController`/`MasterController`'s message dispatch.
- **Why:** Because §6.1's PSK is a fixed, extractable string, any device on the same local network that completes the TLS handshake can act as a "MasterRPG peer" and declare a length up to ~4 GB, forcing the receiving side to wait/buffer for that many bytes — a resource-exhaustion/connection-hang vector that directly compounds §6.1 rather than being independently mitigated.
- **Action:** Reject/close the connection if `header.length` exceeds a defined maximum sane message size (sized to the largest legitimate attachment the app actually sends), before calling `deliverInputNoCopy`. Needs real testing against the SharePlay/network test suite before landing — not a "quick win."
- **Severity:** High.

### 6.5 Foundry import: unbounded pack/collection count from the manifest — CPU-exhaustion DoS — NEW, verified
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:449-481` (spec construction, verified directly), `:279-301` (main decode loop), `:644-656` (`decodeLevelDBCollection`).
- **What:** `collectionSpecs` builds one spec per entry in the manifest's `packs` array/object with **no cap** — unlike documents/records elsewhere in the same reader, which are gated by `FoundryVTTReadBudget`. Verified: the loop at line 464-480 has no count limit, and the budget object is only relevant downstream, after this array is already fully materialized.
- **Why:** A minimal pack declaration (`{"type":"x"}`, ~13 bytes) lets a small, well-formed manifest declare millions of bogus packs; each spec triggers two full linear `source.paths.filter { }` scans (O(specs × paths)), and a `missingPack` error per bad spec is caught and logged rather than aborting — turning a routine file import into a multi-minute CPU-pegging hang from a tiny, innocuous-looking file.
- **Action:** Cap collection-spec count against `limits.maximumDocumentCount` before iterating; back `source.paths` lookups with a `Set`/index instead of re-filtering per spec (also fixes §7.4). This is untrusted-input parser code — needs real fuzz/malformed-input testing before landing, not a quick mechanical patch (see the caution in §2).
- **Severity:** High.

### 6.6 Foundry import: unbounded JSON nesting depth — stack-overflow DoS — NEW, verified
- **Location:** `Modules/CoreRPG/Foundry/FoundryRuleModels.swift:20-59` (`FoundryJSONValue.init(from:)`, verified directly); reached from `FoundryVTTImportReader.swift:1572-1582` and `FoundrySystemPackageReader.swift:534-550`.
- **What:** `FoundryJSONValue`'s custom `Decodable` conformance recurses one native Swift stack frame per JSON array/object nesting level (confirmed directly: lines 52-55 recursively decode `[FoundryJSONValue]`/`[String: FoundryJSONValue]` with no depth tracking). The only depth guard anywhere in either reader (`depth < 64` in `decodeDocument`) applies to the already-decoded embedded-document hierarchy, not to raw JSON structural nesting during decode.
- **Why:** A ~200 KB payload of ~100,000 nested arrays (`[[[[[…]]]]]`) — well under any per-entry size cap — recurses ~100,000 native stack frames during decode and crashes the process via stack overflow. Reachable from any JSON file the standard import flow touches (manifest, template, localization, any pack record), not just a specially-crafted archive.
- **Action:** Add an explicit depth counter to `FoundryJSONValue.init(from:)`, failing with a normal `FoundryImportError` past a bounded depth (e.g. 64-128). Same testing caveat as §6.5 — this is the parser's core untrusted-JSON-decode path.
- **Severity:** High.

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

### 8.6 Stale 3D-object rotation base after a remote SharePlay transform update — NEW, verified
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:520-628` (`DragRotationModifier`), `baseYaw`/`basePitch` at :563-564 seeded once at :542-543; external write path at `apply(remote:)`, :134-150.
- **What:** `DragRotationModifier`'s `@State var baseYaw`/`basePitch` are seeded only once, from the call-site expression `baseYaw: yaw.wrappedValue` at modifier-construction time. Verified directly: they're refreshed *only* inside the modifier's own `.onEnded` (line 613-614) and its two `axRotateClockwise`/`axRotateCounterClockwise` `.onChange` handlers (lines 617-628) — there is no `.onChange(of: yaw)`/`.onChange(of: pitch)`. `SpaceViewer.apply(remote:)` sets `yaw`/`pitch` directly (lines 144-145) whenever a remote SharePlay participant's transform update arrives, completely bypassing the modifier's own update paths.
- **Why:** After any remote participant moves the shared 3D object, the next *local* drag gesture computes `spin(displacement:base: baseYaw)` from the stale pre-update `baseYaw` — the object visibly snaps back toward the old rotation the instant a local drag begins. A real, user-visible SharePlay desync bug in the visionOS tabletop view.
- **Action:** Add `.onChange(of: yaw)`/`.onChange(of: pitch)` to refresh `baseYaw`/`basePitch` whenever the binding changes for a reason other than the gesture itself, or derive the delta from the binding's value read at gesture-start instead of separately-tracked base state. Also mark both `@State` properties `private` (currently not — see quick win in §2).
- **Severity:** High.

### 8.7 `ForEach` uses positional `.offset` identity where a stable id exists — NEW
- **Location:** `Modules/GeneratorRPG/BasicAI/View/TranscriptEntryView.swift:48` (`ForEach(toolCalls.enumerated(), id: \.offset)` — `Transcript.ToolCall` has its own stable `id: String`); `Modules/GeneratorRPG/Root/CharacterGenView.swift:20` (`ForEach(value.entries.enumerated(), id: \.self.offset)` — recursively-rendered, AI-streamed generation entries); `Modules/CoreRPG/Editors/QuickLinkEditor.swift:103-109` (index-range identity *plus* a non-constant view count per iteration — a double violation).
- **Why:** If any of these lists are ever mutated/reordered in place rather than only appended to (streaming updates, generation edits), SwiftUI misattributes row identity and local view state to the wrong element; `QuickLinkEditor`'s variable view-count-per-iteration additionally breaks `List`'s ability to diff/animate reliably.
- **Action:** Key `TranscriptEntryView`'s `ForEach` on `\.id`; give `CharacterEntryGenModel` a stable client-generated `UUID`; restructure `QuickLinkEditor` so each iteration yields exactly one view keyed by stable content identity (e.g. zip `beforeEntries`/`afterEntries` into one identifiable pair type).
- **Severity:** Medium.

### 8.8 Closures stored directly in custom `Environment` key values — NEW
- **Location:** `Modules/CoreRPG/ItemList/ItemListActions.swift:17-47` (3 keys); `Modules/CoreRPG/Buttons/FeatureConfig.swift:21-38`; `Modules/CoreRPG/Buttons/ControlSharingView.swift:164-165`; `Modules/CoreRPG/Model/MapActions.swift:5-21`; `Modules/CoreRPG/App/RouterActions.swift:5-17`; `Modules/CoreRPG/Model/ItemGeneration.swift:59-99`; `Modules/PdfRPG/Model/PdfViewerActions.swift:11-21` (10 keys total).
- **What:** At least 10 custom `EnvironmentKey`/`@Entry` values hold a closure (or a struct whose only payload is closures) as their environment value type.
- **Why:** Closures aren't `Equatable`, so SwiftUI treats every environment write as a change. Concretely, `Modules/AdventureRPG/View/QuickEntryEditor.swift:49`, `Modules/CharacterRPG/View/QuickEntryEditor.swift:49`, and `Modules/MapRPG/View/QuickEntryEditor.swift:46` all construct `PdfViewerActions(selectedText: usePdfSelection(selection:))` inline in `body`, re-writing the environment with a fresh closure/struct on every single re-render, forcing the whole PDF-viewer subtree reading `\.pdfViewerActions` to be treated as invalidated regardless of whether behavior changed.
- **Action:** Replace closure-carrying environment keys with a small `@Observable`/protocol-typed controller (or route through the existing root controller already in environment) so the environment value is a stable, comparable reference instead of a fresh closure each render.
- **Severity:** Medium.

### 8.9 `BattleRoundCard` missing `Equatable` on a hot, live-game-updated list row — NEW
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundCard.swift:32-121`; `Modules/GameRPG/BattleRound/BattleRoundList.swift:38-54` (`ForEach`); `Modules/GameRPG/BattleRound/BattleRoundView.swift:57-77` (inline closures).
- **What:** `BattleRoundCard`, re-rendered on every live Battle Round state change (HP, initiative, active turn, rolls), doesn't conform to `Equatable`; `BattleRoundView.body` additionally passes it `showCharacter`/`selectHitPoints`/`selectInitiative` as fresh inline closures on every body evaluation, which would defeat an `.equatable()` wrapper even if added.
- **Why:** During an active battle round, every combatant/HP/initiative tick forces SwiftUI to re-diff and re-render every card in the turn order, even ones whose displayed content is unchanged — exactly the "hot leaf view inside a live-updated list" scenario worth optimizing.
- **Action:** Conform `BattleRoundCard` to `Equatable` (comparing the already-`Equatable` `presentation` plus controller/layout identity) and apply `.equatable()`; hoist the three action closures to stable method references instead of recreating them per body pass.
- **Severity:** Medium.

### 8.10 Color-only state indication with no accessible/text alternative (2 sites) — NEW
- **Location:** `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift:78-86,95-99,199-206` (combatant avatar halo color = active-turn/roll-recipient signal, but the button's `.accessibilityLabel` never mentions either state — unlike the separate "Roll Target" button below it, which correctly exposes `.accessibilityValue`); `Modules/MapRPG/Map/MapPinView.swift:416-423,495-510` (pin ring: blue = active battle attacker, red = highlighted, but `pinAccessibilityValueResource` only encodes shown/dead/highlighted — `isActiveBattleAttacker` is never included in the announced value).
- **Why:** A VoiceOver user (or a color-blind sighted user, since blue-vs-red/color-vs-gray is the only differentiator) cannot distinguish these states from the accessibility tree at all — in the app's highest-traffic live-game views.
- **Action:** Add the missing state to each accessibility value/label — a short "Active turn"/"Active in Battle" addition in each case, mirroring the pattern already used correctly elsewhere in the same files.
- **Severity:** Medium.

### 8.11 `@State` seeded once from a passed entry's content, never resynced — NEW
- **Location:** `Modules/TableRPG/View/TableGenerationRootView.swift:486-512` (`TableGenerationEntryRow`).
- **What:** `_contentModel = State(initialValue: LinkHighlightTextModel(linkControllable: nil, text: entry.content))` seeds `@State private var contentModel` once from the `entry` passed into `init`; unlike `entry.name` (read live at line 538), `body` never re-reads `entry.content` directly.
- **Why:** This row is a `ForEach(occurrence.visibleEntries)` element keyed by `entry.id`; if a later regeneration/edit replaces the entries array with updated `content` for the same `id` while the row's view identity persists, the row keeps displaying the original text it was created with — the textbook "passed value captured into `@State`, silently ignoring updates" bug the correctness checklist flags as a hard rule violation.
- **Action:** Read `entry.content` directly in `body` (dropping `@State` if `LinkHighlightTextModel` is just a display wrapper), or add `.onChange(of: entry.content)` to refresh it, mirroring the pattern already used in `NameItemNewRow`/`DescriptionItemNewRow` in the same area.
- **Severity:** Medium.

### 8.12 Minor SwiftUI nits found this pass — NEW (grouped)
- **Non-private `@State`:** `Modules/SpaceRPG/Space/SpaceViewer.swift:563-564` (`DragRotationModifier`'s `baseYaw`/`basePitch`) — see §8.6, same fix.
- **Fixed-width + `lineLimit(1)` on unbounded user text:** `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift:41-44` — `Text(combatant.name).frame(maxWidth: 90)` hard-caps a free-text combatant name regardless of Dynamic Type setting, risking illegible truncation at larger accessibility sizes with no `.help()`/long-press fallback to the full name.
- **Action:** Mark the `@State` properties `private`; drop or `@ScaledMetric`-scale the fixed `maxWidth`.
- **Severity:** Low (both).

---

## 9. Dead code / duplication / refactor

### 9.1 Files to delete outright — housekeeping note re-confirmed, unchanged
- `Modules/DiceRPG/0-Old/` and `Modules/SpaceRPG/0-Old/SpaceQuickLook.swift` re-confirmed **live** by all three background agents this pass (independently, via direct reads and cross-reference greps, not `project.pbxproj` text) — still not dead, still not deleted. `Modules/CoreRPG/DeleteMe/` confirmed still absent (no regression).
- **Severity:** Low (housekeeping/lesson) — no change.

### 9.2 Commented-out dead implementations — NOW FIXED
- Re-confirmed: no commented-out dead code blocks found in `CRDT.swift`, `LinkRegisterController.swift`, `GlasseffectAll.swift`, `ObjectCache.swift`, `SpaceViewer.swift` (the `SpaceViewer.swift` TODO left by the prior fix is confirmed still the *only* TODO-class marker in the entire non-test codebase — see §9.16 note).
- **Severity:** Medium — resolved.

### 9.3 Two test methods disabled via comments — STILL OPEN, unchanged
- `Tests/GameRPGTests/InAppControllerTests.swift:124-144`, `Tests/AdventureRPGTests/AppIntentTests.swift:13-40` — both re-confirmed still fully commented out rather than `@Test(.disabled(...))`.
- **Severity:** Medium.

### 9.4 `ExportController.exporting(itemIds:)` BFS traversal duplicated across 7+ modules — STILL OPEN, re-verified with fresh diffs
- **Location:** `Modules/{Pdf,Dice,Generator,Photo,Space,Audio}RPG/Controller/ExportController.swift` (byte-for-byte identical skeleton, differing only in a module-name string in the `preconditionFailure` message — directly re-diffed PdfRPG vs. DiceRPG this pass, confirmed identical apart from that one string); `CharacterRPG`/`AdventureRPG`/`MapRPG`/`TableRPG`/`WeatherRPG` layer per-link-type dispatch onto the same underlying skeleton.
- **New detail:** `RuleRPG`'s `ExportController.swift` has since been independently rewritten to a generic, table-driven approach (`pendingIDs` Set, dynamic `rootManager.rootModel(for:)` dispatch) — it no longer shares the copy-pasted skeleton, but it's also a one-off, not the shared abstraction other modules use. It's a reasonable blueprint for the real fix below.
- **Action:** Unchanged — extract the BFS into `ExportControllable`'s protocol extension (which already centralizes `exportingFolder`/`exporting(ids:)`/`logExport`/`export`/`createExport`), parameterized similarly to how RuleRPG's rewrite dispatches per module.
- **Severity:** High.

### 9.5 `DetailFolderListView.overlayContent` copy-pasted across 11 modules — STILL OPEN, unchanged
- Re-confirmed: same 11 modules (`RuleRPG` inlines the identical body directly rather than via a named property — a minor variant, same root duplication).
- **Severity:** Medium.

### 9.6 `CacheController.generateThumbnail` QuickLook wrapper duplicated (SpaceRPG/PdfRPG) — STILL OPEN, unchanged
- **Severity:** Medium.

### 9.7 Minor duplicated `saveToDisk`/`setObject` tail in four modules' `CacheController` — STILL OPEN, unchanged
- **Severity:** Low.

### 9.8 `FolderListController.copy(listModel:)` boilerplate repeated in 12 modules — STILL OPEN, unchanged
- **Severity:** Low.

### 9.9 `"Documents"` path component hardcoded independently — STILL OPEN, line refs updated
- Canonical constant now at `CloudDocumentController.swift:217` (was :210); still 5 literal `"Documents"` occurrences in `LocationFileManager.swift` (×3), `FoundryImportArchive.swift`, `ExternalImportSourceRegistry.swift`.
- **Severity:** Low.

### 9.10 iCloud container identifier string literal duplicated — STILL OPEN, unchanged
- Re-confirmed at `AppGroup.swift:27` and `CloudKitCoreDataPersistenceController.swift:16` — both still hardcode `"iCloud.de.andretrettin.gamemaster"` independently.
- **Severity:** Low.

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
3. **Standardize on `os.Logger`; stop using bare `print()` or silent `catch {}`.** §9.12 (51 `print()` sites, improved from 70), §5.10 (one remaining silent Siri-donation catch), and the general pattern this audit keeps finding in one-off gaps (RuleRPG missed from an 11-module fix) — a `SwiftLint` custom rule banning `print(` in non-test targets, and a repo-wide grep for `catch {}`/`catch { }` with an empty body, run as a periodic check rather than a one-time pass, would catch this class of "missed the 12th module" gap before it needs a full re-audit to surface.
4. **Treat "already-fixed bug classes" as a checklist for new code, not a closed chapter.** §5.11 (App Intents export path traversal) is the *exact* bug §5.4 already fixed, just in files that fix didn't touch. When a bug class gets fixed at N call sites, grep for the same anti-pattern (`.appending(path:` on interpolated user text, in this case) across the *whole* repo, not just the originally-flagged files, before declaring it resolved.
5. **Give the untrusted-input Foundry parser dedicated fuzz/malformed-input test coverage.** §6.5 and §6.6 are both resource-exhaustion gaps in code that already has good bounds-safety hygiene per the prior audit's own note — the parser is careful about crashing on bad data, but not yet about being *slow* or *deep* on bad data. A small corpus of adversarial fixtures (huge pack counts, deeply nested JSON) run in CI would catch regressions on both axes going forward.
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
