# MasterRPG Code Audit

Generated 2026-08-11. Scope: ~264,844 Swift LOC across 1,948 files, 0 Metal kernels, spanning targets `MasterRPG` (iOS/visionOS), `MasterMac`, `MasterTV`, `RPGShare`, `DiceRollerWidgetExtension`, and 15 feature modules (`AdventureRPG`, `AudioRPG`, `CharacterRPG`, `CoreRPG`, `DiceRPG`, `GameRPG`, `GeneratorRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `RolePlayGameKit`, `RuleRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG`). Deployment target confirmed uniformly 26.0 across iOS/iPadOS/tvOS/visionOS/macOS. No `Dead/` or archived directory exists in this project.

**This is a third audit pass.** Two prior rounds (`Docu/CODE_AUDIT_1.md`, dated 2026-08-07, and `Docu/CODE_AUDIT_2.md`, dated 2026-08-10 — both preserved alongside this report) already found and fixed the large majority of issues in this codebase, each verified with real `xcodebuild build`/`test` passes. This report does **not** re-derive that history. Instead it: (1) personally re-opened and re-confirmed the small number of items those reports left explicitly open, (2) gave focused scrutiny to the newest, unaudited code — three commits made today (`c12bf90c` "3D objects coordinates", `57a0b33e` "room show / hide / zoom", `220877d5` "render issues") touching `Modules/SpaceRPG/Space/SpaceViewer.swift`, `Modules/GameRPG/Table3D/*.swift`, and `Modules/GameRPG/BattleRound/BattleRoundCard.swift`, and (3) ran a fresh, independent sweep for anything the first two passes missed. Three parallel background agents covered concurrency/API modernity, dead code/duplication, and bugs/security/performance; a fourth pass (this session, direct) covered SwiftUI structure on the newest views. Every Critical/High claim below was personally re-opened and confirmed by reading the cited lines — see §12.

A full clean build (`xcodebuild -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 17 Pro' clean build`) succeeded with exactly **4 deduplicated real warnings** (down from 12 at the last audit — see §3.6 for why, and §4.1 for the surprising reason the previously-tracked 12 are gone).

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

---

## 1. Executive summary

1. **[Critical/Security] Hardcoded, world-shared TLS pre-shared key still lets any nearby device join or inject state into someone else's live game — unchanged since the first audit, still open** — §6.1 — `Modules/GameRPG/Network/GameSecurity.swift:7`.
2. **[High/Dead code] `GameSetup.swift`/`GamePortableSetup.swift` (today's "room show/hide/zoom" commit) duplicate `GameMetrics` and ~200 lines of pin/room sync math verbatim** — §9.1 — `Modules/GameRPG/Table3D/GameSetup.swift` vs. `GamePortableSetup.swift`.
3. **[High/Dead code] `GameEquipment.swift`/`GamePortableEntities.swift` (same commit) duplicate `PinComponent`/`RoomComponent`/`PinPawn`, ~250 lines** — §9.2.
4. **[High/Concurrency] Unstructured, uncancellable `DispatchQueue.main.asyncAfter` for delayed navigation resume — still open, unchanged since the second audit** — §3.1 — `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:112`.
5. **[High/Dead code] `ExportController.exporting(itemIds:)` BFS wrapper still duplicated across 12 modules — and the duplication has now caused a real behavioral drift** — §9.4 / §5.1 — `PhotoRPG`'s copy is missing a guard all 5 sibling "simple" modules have.
6. **[Medium/Security] `aps-environment: development` still baked into every Release build with zero push-notification code present — unchanged since the second audit** — §6.2.
7. **[Medium/Dead code] `PlayerController.swift` still not split — and has grown, not shrunk, since the last audit (3,841 → 3,913 lines)** — §9.6.
8. **[Medium/Concurrency] Table3D's `GroupActivityManager`/`GameObserver` use inconsistent MainActor isolation next to three siblings in the same module that already use the correct pattern** — §3.4.
9. **[Medium/Dead code] `MapRPG/Controller/GameController.swift` has grown to 1,651 lines / 90 functions with a single MARK — not previously flagged as a hot spot** — §9.7.
10. **[Low/API modernity] The previously-tracked 12-site `.system.search` deprecation warning has silently disappeared from the build — not because it was fixed, but because the toolchain moved to Xcode 27.0 GM, whose SDK now dates the deprecation to exactly the version the app doesn't yet target** — §4.1.

**The good news:** today's three newest commits were read in full by two independent passes (bugs/security agent + this session's SwiftUI pass) and contain **no new crash-reachable force-unwraps, fatal errors, or SwiftUI correctness bugs** — the "room show/hide/zoom" and "render issues" fixes are genuine, sound fixes, not papered-over symptoms (see §5.3, §8.1-8.2). Their cost is duplication, not correctness — see §9.1-§9.2.

---

## 2. Quick wins (≤30 min each)

- **Rename `tabletopGameContentBunlde` → `tabletopGameContentBundle`** — `Resources/RPGTabletopGameContent/Sources/RPGTabletopGameContent/RPGTabletopGameContent.swift:10`, plus 6 call sites, all in-repo. See §9.11.
- **Rename `PdfSummaryAnalyzyerResultModel` → `PdfSummaryAnalyzerResultModel`** (extra "y") to match its own filename — `Modules/GeneratorRPG/BasicAI/Model/PdfSummaryAnalyzerResultModel.swift:33`, 3 call sites. See §9.11.
- **Rename `asTextualRepresentationWithNonReaptingKeys` → `...NonRepeatingKeys`** — `Modules/CoreRPG/Debug/DumpEnvironment.swift:29,43`. See §9.11.
- **Add the missing `guard item.specialCategory else { return [] }` to `Modules/PhotoRPG/Controller/ExportController.swift`** — every sibling "simple" module (`Pdf`, `Dice`, `Generator`, `Audio`, `Space`) has this guard; PhotoRPG's export can currently pull in linked-but-not-contained items that shouldn't be part of an export bundle. See §5.1.
- **Delete the dead block-comment** at `Modules/DiceRPG/Space/DiceSpaceModel.swift:235-241` — leftover debugging scaffolding sitting directly above its live, `#if DEBUG`-guarded replacement.
- **Delete the 9 scattered commented-out `// print(...)` lines** — `Modules/CoreRPG/CRDT/LWWRegister.swift:34`; `Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift:158,196,208,211,216,222`; `Modules/CoreRPG/LinkRenderer/LinkHighlightTextRenderer.swift:45`; `Modules/GeneratorRPG/Playground/MyAiPlayground.swift:119`.
- **Name the magic `CGSize` thumbnail literals** in `Modules/PdfRPG/Controller/CacheController.swift:22` (`210×297`) and `Modules/SpaceRPG/Controller/CacheController.swift:19-22` (`393×350`) as `private static let thumbnailSize`, matching the pattern `PhotoRPG`/`MapRPG` already use. See §9.10.
- **Fix the `CLAUDE.md` typos** — "conurrency" (line 27), "manipluate" (×10, lines 112-121), "charactere", "groupes", "Sturcture" (line 140), "Intentm"/"Shrotcuts" (line 142), "LOcalaizations" (line 146). See §9.15.
- **Move 3 misplaced `@Observable` model classes** from `Modules/GeneratorRPG/View/` into `Modules/GeneratorRPG/BasicAI/Model/` alongside their `ResultModel` counterparts — `PdfSummaryAnalysisModel.swift`, `TableSummaryAnalysisModel.swift`, `PdfContentExtractionModel.swift`. See §9.12.

---

## 3. Concurrency

Strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`) still compiles with zero concurrency-related *errors*; the second audit's mechanical `MainActor.run` cleanup (§3.1/§3.2 of `CODE_AUDIT_2.md`) holds. This pass found one still-open High item, one new warning class introduced by that very cleanup, and a handful of smaller items.

### 3.1 Unstructured, uncancellable `DispatchQueue.main.asyncAfter` for delayed navigation resume — still open, unchanged
- **Location:** `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:106-130`, violation at line 112, inside `@MainActor internal func resume(_:values:delay:)`
- **What:** The `.auto` case of `resume(_:values:delay:)` calls `DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.send(values: values) }` to implement a delayed navigation resume — the rest of the function is otherwise clean structured-concurrency dispatch via recursive `resume(...)` calls.
- **Why:** Directly violates the project's explicit house rule against GCD-style dispatch, and is unstructured/uncancellable — a delayed resume can fire after the navigator or the view it targets is gone, and cannot be cancelled if the navigation is superseded before the delay elapses. Flagged in the second audit and never addressed.
- **Action:** Replace with a tracked `Task { try? await Task.sleep(for: .seconds(delay)); guard !Task.isCancelled else { return }; send(values: values) }`, stored so it can be cancelled if `resume`/`send` is invoked again before it fires.
- **Severity:** High

### 3.2 Fire-and-forget `Task {}` inside `.onAppear` instead of `.task {}`
- **Location:** `Sources/RPGShare/SharingInput.swift:32-36`; `Modules/CoreRPG/Inspector/LinkItemListView.swift:75-89`; `Modules/CoreRPG/LGViews/ListRootView.swift:234-256`
- **What:** All three views spawn a plain `Task { ... }` from `.onAppear` (one sleeps 0.5s then focuses a field; the other two do multi-step async list/scroll-restoration work) with no `.onDisappear` cancellation.
- **Why:** A `Task` created inside `.onAppear` is not tied to the view's lifetime, unlike `.task { }`. If the view disappears before the task completes, it keeps running and can mutate `@State`/model properties after the view is gone — the exact anti-pattern already fixed elsewhere in this codebase (`SelectedMasterView.swift`, `TutorialVideoView.swift`, per the first audit's §3.5).
- **Action:** Replace `.onAppear { Task { ... } }` with `.task { ... }`, adding `guard !Task.isCancelled else { return }` after any sleep/yield, matching the already-established fix pattern.
- **Severity:** Medium

### 3.3 `MasterController`/`PlayerController` mix explicit `Sendable` conformance with piecemeal per-method `@MainActor` — still open
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:443` (`final class MasterController: Sendable`); `Modules/GameRPG/Controller/PlayerController.swift:1062` (`final class PlayerController: Sendable`)
- **What:** Both classes remain declared `Sendable` rather than `@MainActor`, holding non-`Sendable` `@MainActor`-isolated state, with individual methods annotated `@MainActor` one at a time — unlike `Modules/MapRPG/Controller/GameController.swift`, which already uses whole-type `@MainActor` isolation successfully in the same codebase.
- **Why:** Flagged as open in the first audit and still present. Piecemeal isolation increases the risk that a future method forgets its `@MainActor` annotation, silently reintroducing a race the compiler won't catch (unlike a missing `await`, which it would).
- **Action:** Mark both classes `@MainActor` directly; drop the explicit `Sendable` conformance and the now-redundant per-method annotations.
- **Severity:** Low

### 3.4 Table3D's `GroupActivityManager`/`GameObserver` use inconsistent MainActor isolation, unlike their siblings in the same module
- **Location:** `Modules/GameRPG/Table3D/GroupActivityManager.swift:8-19` (whole class; plain, non-isolated `deinit` at 17-19 calling `tabletopGame.detachNetworkCoordinator()` directly); `Modules/GameRPG/Table3D/GameObserver.swift:8-43` (whole class conforms to `TabletopGame.Observer` with no `@MainActor`; `actionIsPending` at 18-29 defensively hops via `Task { @MainActor in ... }` before touching `die20`, while `playerChangedSeats` at 34-42 calls `tabletop.claimSeat`/`claimAnySeat` synchronously with no hop at all)
- **What:** Personally confirmed by reading both files in full. Three siblings in the same directory (`ListenerManager`, `BrowserManager`, `GameTableModel`) all use `isolated deinit` specifically so a `deinit` can safely touch actor-isolated/RealityKit-adjacent state — `GroupActivityManager` does not. `GameInteraction`/`GameRenderer` in the same directory are `@MainActor`-annotated TabletopKit-protocol conformances — `GameObserver` is not, and handles its two callbacks inconsistently (one hops, one doesn't).
- **Why:** Either a latent isolation gap (if `TabletopGame`'s seat/network APIs require main-actor confinement, as every other call site in this codebase treats them) or, at minimum, an unreviewed deviation from the module's own established pattern that makes the real isolation boundary unclear to a future reader.
- **Action:** Audit whether `TabletopGame`'s relevant APIs require main-actor confinement; if so, adopt `isolated deinit` on `GroupActivityManager` and mark `GameObserver` `@MainActor` (or hop consistently in every callback) to match its siblings.
- **Severity:** Medium

### 3.5 Untracked fire-and-forget `Task {}` for pin-photo thumbnail loads, duplicated in today's new code
- **Location:** `Modules/GameRPG/Table3D/GamePortableSetup.swift:219-224` (inside `syncPawnsWithMapPins()`); `Modules/GameRPG/Table3D/GameSetup.swift:278-283` (identical duplicate, visionOS variant)
- **What:** Both variants spawn `Task { [weak self] in await self?.loadPinThumbnail(pinId:photoId:) }` per pending photo load, with no `Task` handle stored and no cancellation on the owning `GameTableModel`'s `isolated deinit`.
- **Why:** Not an active correctness bug today (a dictionary guard prevents duplicate concurrent loads, and staleness is re-checked before applying results), but rapid map switching can accumulate untracked thumbnail-load tasks with no way to cancel them if the model is torn down mid-load.
- **Action:** Track spawned photo-load tasks (mirroring `pendingPinPhotoIds`) and cancel any in-flight ones from `GameTableModel`'s existing `isolated deinit`.
- **Severity:** Low

### 3.6 New compiler warnings: unnecessary `await` left behind by the second audit's own `MainActor.run` cleanup
- **Location:** `Modules/GameRPG/Controller/PlayerController.swift:3785,3814,3818,3821` — `[#UnnecessaryEffectMarker] warning: no 'async' operations occur within 'await' expression`
- **What:** A fresh clean build surfaces exactly 4 real warnings, all here. `scheduleSendCharacterTask()`/`scheduleProxyFocusTask(characterId:)` create a `Task { [weak self] in ... }` from an already-`@MainActor` function; the compiler now determines the `Task` closure itself inherits `@MainActor` isolation from that context, so the `await self?.clearSendCharacterTask(if:)`/`await self?.clearProxyFocusTask(if:)`/`await completeProxyFocus(...)` calls inside it never actually suspend — the `await` keyword is syntactically present but does nothing.
- **Why:** Harmless today (the code is correct, just noisy), but these are the only 4 warnings in an otherwise completely clean build — worth clearing so a future genuine warning doesn't get lost in the noise, and because they're a direct, traceable side effect of the second audit's own `MainActor.run`-removal pass (commits "fixed: more mainactor issues 3.1" / "fixed: await 3.2") rather than pre-existing debt.
- **Action:** Drop the redundant `await` at all 4 sites (the calls become plain synchronous calls once isolation is confirmed inherited).
- **Severity:** Low

---

## 4. API modernity

### 4.1 Deprecated `.system.search` App Shortcuts schema — still 12 sites, but the toolchain has moved and the finding needs re-framing
- **Location:** `Modules/AdventureRPG/Intent/SearchAdventuresIntent.swift:8`; `Modules/{Character,Rule,Generator,Dice,Space,Photo,Audio,Weather,Pdf,Table,Map}RPG/Intent/*ManagementIntents.swift` (one site each, ~line 89-94) — re-confirmed unchanged at exactly the same 12 sites as both prior audits.
- **What:** Re-grepped repo-wide: no drift. But the clean build captured for this pass (`xcodebuild`, Xcode 27.0 GM / iPhoneSimulator27.0.sdk — a newer toolchain than either prior audit used) emits **zero** warnings for these sites, down from a reliable 12 at the last audit. Traced the root cause in `AppIntents.swiftinterface`: `.system.search` carries `@available(anyAppleOS, deprecated: 27.0, ...)` and `.system.searchInApp` carries `@available(anyAppleOS 27.0, *)` — both keyed to exactly version 27.0. Since this project's deployment target is 26.0, `.search` is not yet deprecated *for this target* on the current SDK (Swift only warns once the deployment target reaches the deprecated-since version), so the warning has gone silent — and `.searchInApp` is still genuinely unusable at 26.0, confirming the prior audits' "blocked, needs a deployment-target bump" triage was exactly right, just for a slightly different proximate reason than a hard build error this time.
- **Why:** The disappearance of the warning is an artifact of beta→GM annotation cleanup on Apple's side, not evidence the underlying issue is resolved — it will resurface (both as a warning, and as a legitimately swappable API) the moment this project's deployment target moves to 27.0.
- **Action:** No mechanical action now. When a 26→27 deployment-target bump is next considered for any other reason, fold this swap into the same change — it will become a one-pass mechanical fix at that point (all 12 sites are identical in shape).
- **Severity:** Low (downgraded from Medium — currently produces no warning and has no available fix path yet)

---

## 5. Bugs / logic errors

### 5.1 `PhotoRPG`'s `ExportController` is missing a guard all 5 sibling "simple" modules have — real behavioral drift from duplication
- **Location:** `Modules/PhotoRPG/Controller/ExportController.swift:28-36` vs. `Modules/PdfRPG/Controller/ExportController.swift:28-37` (and `Dice`/`Generator`/`Audio`/`Space`RPG's identical siblings)
- **What:** Personally diffed both files. `PdfRPG` (and the other 4) guard `exporting(itemIds:)`'s BFS traversal with `guard item.specialCategory else { return [] }` before walking `item.entries` — i.e., a leaf (non-folder, non-collection) item stops the traversal there. `PhotoRPG`'s copy is missing this line entirely, so it always walks and includes `item.entries` even for a plain leaf Photo.
- **Why:** `specialCategory` (`Modules/CoreRPG/ItemList/ItemDataAccessable.swift:111`, `category == .folder || category.isCollection`) exists specifically to distinguish container items (whose children are genuinely "contained") from leaf items (whose `entries` represent cross-references, not containment). Without the guard, exporting a single non-folder Photo that happens to have any `entries` (cross-links) can silently pull unrelated linked items into the export bundle — a real, user-visible correctness bug caused directly by this module having hand-copied the pattern instead of sharing it.
- **Action:** Add the missing guard (see §2 quick win). Root-cause fix: centralize this BFS wrapper per §9.4 so this class of drift becomes structurally impossible.
- **Severity:** Medium

### 5.2 `Die`/`Die20` bundled-asset load fallback — now fully resolved, closing a loop left open by the first audit
- **Location:** `Modules/GameRPG/Table3D/GameEquipment.swift:591-598,638` (`Die20`), `:686-694,726` (`Die`)
- **What:** The first audit (`CODE_AUDIT_1.md` §5.5) found `Entity.load` force-`try!`'d in both structs' `init`, assessed it as unfixable without a fallback mesh (since `EntityEquipment.entity` is a non-optional protocol requirement), and left it as an upgraded-but-still-fatal `preconditionFailure`. Re-checked this pass: both now wrap the load in `do/catch` with a genuine, non-fatal `Self.makeFallbackEntity()` procedural stand-in mesh on failure — the exact fix the first audit described as "out of scope."
- **Why:** Recorded so the audit trail reflects this is now closed, not to claim credit for new work — this predates today's commits and was found already fixed while verifying an adjacent claim.
- **Action:** None — resolved.
- **Severity:** Low (informational)

### 5.3 No new crash-reachable bugs found in today's TabletopKit/SharePlay-synchronized changes
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift` (full file); `Modules/GameRPG/Table3D/GameEquipment.swift`, `GamePortableEntities.swift`, `GamePortableSetup.swift`, `GameSetup.swift`, `GameTableModel.swift`, `GameTableView.swift` (full files); `Modules/GameRPG/BattleRound/BattleRoundCard.swift` (full file)
- **What:** Read in full by the bugs/security agent and cross-checked against today's `git show` diffs. `SpaceViewer.swift`'s new `applySharedPlacementIfNeeded()` gating (`networkActions != nil` instead of `immersiveSpaceDisplacement != .identity`) correctly fixes a real bug — a participant whose own space alignment legitimately reports `.identity` as steady-state previously never left the head-locked anchor. `BattleRoundCard.swift`'s `VStack` restructure (independently re-verified this pass, see §8.1) is a genuine SwiftUI-diffing fix. No new force-unwraps, force-casts, or reachable `fatalError`s were introduced by any of these commits.
- **Why:** Recorded so the report reflects that this pass's highest-risk-flagged surface was read in full and found sound, not skipped.
- **Action:** None required.
- **Severity:** Low (informational)

---

## 6. Security

### 6.1 Hardcoded, world-shared TLS pre-shared key allows any local device to join or inject state into any game — still open, unchanged
- **Location:** `Modules/GameRPG/Network/GameSecurity.swift:7` (`static let passcode = "GameMasterCode"`); `Modules/GameRPG/Network/NWParameter+GameMaster.swift:19-61`; `Modules/GameRPG/Browser/BrowserManager.swift:52-138` (no join-code/PIN/host-approval UI anywhere); `Modules/GameRPG/Controller/MasterController.swift:207-217,829-897` (`accepts(...)` checks only sender-identity consistency, no secondary secret)
- **What:** Re-verified: the constant, its verbatim use as the sole TLS PSK for every Bonjour pairing handshake, and the absence of any per-session code anywhere in the codebase (a repo-wide grep for `joinCode`/`pairingCode`/`sessionCode`/`pinCode`/`passphrase` returns zero results) are all unchanged since the first audit flagged this Critical.
- **Why:** Any device with MasterRPG installed on the same local network can discover and join a stranger's live game as a full participant and inject dice results, map pins, chat, or state into a session it was never invited to — a full authentication bypass, not merely weak crypto. This is the single Critical finding across all three audit passes and remains open after two full fix rounds that addressed nearly everything else.
- **Action:** Replace the static PSK with a per-game secret (freshly generated at "Start Game," shown to the host, entered by joining players) and/or add an explicit host-side accept/deny prompt before a connection is bound to a player identity.
- **Severity:** Critical

### 6.2 `aps-environment: development` baked into Release builds of every push-capable target, with zero push-notification code present — still open, unchanged
- **Location:** `Resources/MasterRPG.entitlements`; `Resources/MasterTV.entitlements`; `Sources/RPGShare/RPGShare.entitlements` (all confirmed via `plutil -p`, `aps-environment => "development"`)
- **What:** Re-verified via `plutil` and a repo-wide grep for `UNUserNotificationCenter`/`registerForRemoteNotifications`/`PushKit`/`didReceiveRemoteNotification` — zero matches, unchanged since the second audit flagged this.
- **Why:** A latent trap — if push is ever wired up without someone remembering to fix this, App Store review can reject the build or Release traffic can silently mis-route to the dev APNs environment; it also forces every provisioning profile to request a push capability the app doesn't use.
- **Action:** Remove the `aps-environment` key from all three entitlements files until push is actually implemented.
- **Severity:** Medium

---

## 7. Performance

_No findings._ A dedicated performance sweep this pass (NSFetchRequest batching, SwiftUI view-body work, RealityKit/TabletopKit per-frame allocations, CloudKit reconciliation scope) found nothing new. The prior audits' five performance fixes were not independently re-verified end-to-end this pass, but no contrary evidence surfaced while reading the relevant files for other purposes.

---

## 8. SwiftUI / UI

### 8.1 `BattleRoundCard.swift`'s `VStack` restructure is architecturally sound, not a paper-over
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundCard.swift:43-129` (today's rewrite); call site `Modules/GameRPG/BattleRound/BattleRoundList.swift:38-55`
- **What:** The card's `body` now wraps its content and an optional inline character sheet in one `VStack(spacing: 0)`, per the file's own comment, so `BattleRoundList`'s `.frame(maxWidth: .infinity)`/`.transition`/`.draggable` apply to a single stable row instead of fanning out across separate top-level children — the classic "List rows must be unary" violation. Personally traced the `Equatable` conformance's two subtler claims through to the call site and confirmed both hold: the `@Environment`-sourced `cardLayout` read in `==` is valid (dynamic properties on an `Equatable` view resolve before the equality check runs), and the three excluded action closures (`showCharacter`/`selectHitPoints`/`selectInitiative`) really are stable — they resolve to real instance methods on `BattleRoundView` referenced identically on every render (`BattleRoundView.swift:57-59,109-120`), not fresh per-render closures.
- **Why:** Recorded because the fix looked, at a glance, like it could be papering over a symptom (a `VStack` wrapper "fixing" a layout bug can sometimes just relocate the bug) — verified it is not; this is the textbook-correct fix for the underlying SwiftUI diffing issue.
- **Action:** None — verified sound.
- **Severity:** Low (informational)

### 8.2 Today's new Table3D controls follow project conventions cleanly
- **Location:** `Modules/GameRPG/Table3D/GameTableView.swift` (both `#if os(visionOS)` and `#if os(iOS) || os(macOS)` variants); `Modules/GameRPG/Table3D/GameTableToolbar.swift`; `Modules/GameRPG/Table3D/GamePinActionMenu.swift`
- **What:** All new room-visibility/zoom/pointer controls use `Button`/`Menu` with `Label { Text(...) } icon: { Image(systemName:) }` and the project's own `.selectedRoundButton(title:module:isSelected:)` modifier — never a bare icon-only `Image` or `onTapGesture` misuse. Gesture composition for pin-vs-room hit-testing (`.simultaneousGesture`/`.exclusively(before:)`) is well-commented and correctly prioritized (pins win over room fog). `.task`/`.task(id:)` used correctly for game-model lifecycle in both platform variants.
- **Why:** Recorded for completeness of the SwiftUI pass on the newest, highest-risk-flagged UI surface.
- **Action:** None required.
- **Severity:** Low (informational)

---

## 9. Dead code / duplication / refactor

### 9.1 `GameSetup.swift`/`GamePortableSetup.swift` duplicate `GameMetrics` and ~200 lines of pin/room sync logic verbatim
- **Location:** `Modules/GameRPG/Table3D/GameSetup.swift:13-22` (enum `GameMetrics`) vs. `Modules/GameRPG/Table3D/GamePortableSetup.swift:10-19` — numerically identical values, only cosmetic `SIMD2` literal-syntax differences; `GameSetup.swift:206-240` (`syncRooms`) vs. `GamePortableSetup.swift:153-187` — personally diffed, **byte-for-byte identical**; `GameSetup.swift:240-258` (`projection`) vs. `GamePortableSetup.swift:187-202` — differs only by one comment and one redundant `@MainActor` annotation; the same pattern extends to `resetGame()`, `syncPawnsWithMapPins()`, `tablePosition(for:)`, `mapLocation(for:)`, and `orientedImageSize`/`swapsAxes`/`normalizedDegrees` (confirmed identical by the dead-code agent, not independently re-diffed by this pass).
- **What:** Today's "room show / hide / zoom" commit added this duplication fresh — both files are guarded by mutually-exclusive `#if os(visionOS)` / `#if os(iOS) || os(macOS)`, so they compile cleanly, but the platform-agnostic math (zero use of any platform-specific API in the diffed functions) is now maintained in two places by hand.
- **Why:** A bug fix or behavior change to room-fog hit-testing, pin sync, or the coordinate-projection math must be applied in both files; a slip that updates one copy but not the other is exactly the kind of platform-specific divergence a tabletop-sync feature is most likely to introduce a real bug through (see §5.1 for a concrete example of this exact failure mode happening elsewhere in the codebase).
- **Action:** Extract `GameMetrics` and the platform-agnostic sync/projection functions into a single shared file with no `#if os()` guard, leaving only the small amount of genuine TabletopKit-vs-RealityKit-camera setup code platform-specific.
- **Severity:** High

### 9.2 `GameEquipment.swift`/`GamePortableEntities.swift` duplicate `PinComponent`/`RoomComponent`/`PinPawn`, ~250 lines
- **Location:** `Modules/GameRPG/Table3D/GameEquipment.swift:275-282` (`PinComponent`), `:280-290` (`RoomComponent`), `:291-517` (`final class PinPawn`, including `init`, `update(...)`, `setPhotoTexture(_:)`, `radius(for:pointsToMeters:)`, `applySize`, `updateAccessibility` at line 439, `update(entry:projection:)` at line 493) vs. `Modules/GameRPG/Table3D/GamePortableEntities.swift:288-295,298-589` (same members, same names, `updateAccessibility` at 509, `update(entry:projection:)` at 563) — personally diffed the `updateAccessibility`/`update(entry:projection:)` block; near-identical (only difference is a trailing unrelated `GameTableImage` helper enum in the portable file, out of the diffed range)
- **What:** Same root cause as §9.1, same commit — the entire pin-token visual/accessibility/sync class was written twice, differing only in `UIColor` (visionOS) vs. a `GameTablePlatformColor` typealias abstraction (iOS/macOS, already proven to work as the one-line platform seam) plus reformatting.
- **Why:** This is the largest concrete duplication in the whole codebase found by any of the three audit passes — a change to pin-token visuals or accessibility behavior must be hand-replicated across two ~250-line blocks.
- **Action:** Extract `PinPawn`/`PinComponent`/`RoomComponent` into a shared file using the already-proven `GameTablePlatformColor` typealias pattern (`GamePortableEntities.swift:9-15`) for the one genuine platform difference.
- **Severity:** High

### 9.3 `GameRenderer.swift`/`GamePortableRenderer.swift` duplicate two RealityKit helper functions byte-for-byte
- **Location:** `Modules/GameRPG/Table3D/GameRenderer.swift:97-139` (`makePlainWoodTable()`, `firstModelComponent(in:)`) vs. `Modules/GameRPG/Table3D/GamePortableRenderer.swift:97-136` (same two functions)
- **What:** Pure RealityKit entity-construction code with zero platform dependency, confirmed identical by the dead-code agent's `diff`.
- **Why:** A rare, unambiguous "just move this" case — no risk in extracting since the code is provably identical today. Pre-dates today's commits (both files last touched Aug 8), but was surfaced by this pass's focus on the Table3D duplication cluster.
- **Action:** Move both functions to a shared internal helper (e.g. `TableAssetFactory.swift`) used by both renderers.
- **Severity:** Medium

### 9.4 `ExportController.exporting(itemIds:)` BFS wrapper still duplicated across 12 modules
- **Location:** `Modules/{Adventure,Audio,Character,Dice,Generator,Map,Pdf,Photo,Rule,Space,Table,Weather}RPG/Controller/ExportController.swift`
- **What:** The shared BFS traversal itself lives in `Modules/CoreRPG/Controllable/ExportControllable.swift:111` (`bfsExportResults(seedIds:visit:)`), but every module still hand-writes a near-identical ~23-38 line wrapper around it: `struct ExportController`, `init`, a `hubControllable` computed property with a per-module `preconditionFailure` string, and the `exporting(itemIds:)` closure itself. Confirmed via direct diff of `Dice`/`Generator`RPG (identical except the module-name string) and `Audio`/`Space`RPG (identical except module name + a stray unused import). See §5.1 for the concrete drift this duplication has already produced.
- **Why:** Flagged as High in both prior audits and still open; now has documented proof of the exact kind of bug this class of duplication produces.
- **Action:** Add an `ExportControllable` protocol-extension default for the "simple" 6-module shape, parameterized by module id, per the recommendation both prior audits already made.
- **Severity:** High

### 9.5 `DetailFolderListView` boilerplate still duplicated across 11 modules
- **Location:** `Modules/{Adventure,Audio,Character,Dice,Map,Pdf,Photo,Rule,Space,Table,Weather}RPG/View/DetailFolderListView.swift`
- **What:** Every module's `DetailFolderListView` wraps `ItemDetailRootView(...)` with an identical `.openFileWindowOverlay(...)` trailer, differing only in the concrete `Root`/`Model`/`LinkType` names and per-module `ViewerConfiguration` flags.
- **Why:** Flagged as Medium in the first audit; unchanged and still open.
- **Action:** Extract into a generic-over-`Root`/`Model` shared view or protocol-extension default, matching the fix already applied to `SyncDataController` (first audit §9.2).
- **Severity:** Medium

### 9.6 `PlayerController.swift` split still not done — file has grown, not shrunk
- **Location:** `Modules/GameRPG/Controller/PlayerController.swift` — 3,913 lines, up from 3,841 at the second audit (+72 lines, +1.9%)
- **What:** The mechanical split into `PlayerControllerModel.swift`/`PlayerController.swift`/`PlayerController+ProxyDelegate.swift`, recommended explicitly in the second audit's executive summary (§9's top item), has not happened — confirmed via `find`, no such files exist. `final class PlayerControllerModel` (lines 60-1061) still has zero internal MARKs; `final class PlayerController`'s largest chunk (`extension PlayerController { ... }`, lines 2112-3913, ~1,800 lines / 50 functions) still has no MARK breakdown despite handling nine distinct per-module network-message domains (Map/Photo/Pdf/Space/Dice/Table/Value/Weather/Audio).
- **Why:** This is still the single largest file in the app at nearly 8× the codebase's own 500-line convention, and the highest-priority open recommendation from the second audit has had zero progress in the interim.
- **Action:** Execute the already-scoped split: `PlayerControllerModel.swift` first, then break the 2112-3913 extension into per-domain files using the existing `handleX`/`applyXList` function-name prefixes as natural seams.
- **Severity:** Medium

### 9.7 `MapRPG/Controller/GameController.swift` has grown into an unflagged hot spot — 1,651 lines, 90 functions, 1 MARK
- **Location:** `Modules/MapRPG/Controller/GameController.swift:253-1651` (`extension GameController: MapGameStorable`)
- **What:** A single `// MARK: - Battle round` comment at line 761 is the only section marker across ~1,400 lines / 90 functions, which naturally group into four concerns by call order: pin/room/pointer state (lines 404-763), battle-round lifecycle (764-1261), map-content sync (1261-1358), and package/version metadata (1358-1466).
- **Why:** Not previously flagged — neither prior audit's hot-spot list reached this file. It's now the 4th-largest controller in the app with no navigational structure, and it's the same subsystem today's "room show/hide/zoom" commit extended, making further unstructured growth likely.
- **Action:** Add MARK comments for the four groupings, then split into `GameController+Pins.swift`/`+Battle.swift`/`+MapSync.swift`/`+Metadata.swift`, mirroring the split already recommended for `PlayerController.swift`.
- **Severity:** Medium

### 9.8 `SharePlayJournalPublicationQueue.swift` still has zero MARKs at 1,069 lines
- **Location:** `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift`
- **What:** The second audit fixed this file's triplicated retry-delay literals but explicitly noted it needed MARK sections added before any split — that has not happened.
- **Why:** Re-confirms an already-known, still-open item; the second audit's own precondition for splitting it safely remains unmet.
- **Action:** Add MARK sections first (6 distinct top-level types exist in the file), then split.
- **Severity:** Medium

### 9.9 `GameNetworkController.swift` — 1,182 lines, well-organized but still a split candidate
- **Location:** `Modules/GameRPG/Network/GameNetworkController.swift`
- **What:** 9 MARK sections already exist (better-organized than most oversized files in this codebase), but at 1,182 lines it remains the largest file outside the top hot-spot cluster.
- **Why:** Large enough to warrant splitting along its existing MARK seams, using the same mechanical technique both prior audits validated works cleanly for `MasterController.swift`.
- **Action:** Split into `+ExtensionName.swift` files along the 9 existing MARKs.
- **Severity:** Low

### 9.10 Divergent thumbnail-generation strategies across `CacheController.swift`
- **Location:** `Modules/PdfRPG/Controller/CacheController.swift:19-25`, `Modules/SpaceRPG/Controller/CacheController.swift:15-25` vs. `Modules/PhotoRPG/Controller/CacheController.swift:41-77`
- **What:** The shared `ImageCacheControllableStorage` skeleton is correctly centralized (per the second audit's §9.3 fix, confirmed still holding), but `PdfRPG`/`SpaceRPG` still generate thumbnails via the older `AKImage.quickLookThumbnail(for:size:)` path with hardcoded `CGSize` literals, while `PhotoRPG` has moved to a faster ImageIO-downsampled path with `PerformanceTrace` instrumentation and a named `thumbnailMaxPixelSize` constant.
- **Why:** Not a bug, but an inconsistency — two modules pay the cost of the older thumbnailing strategy while one has already been optimized, and the un-migrated modules also carry the unnamed magic-constant issue (§2).
- **Action:** Evaluate whether `PdfRPG`/`SpaceRPG` can adopt the same downsampled-thumbnail approach as `PhotoRPG`, or document why QuickLook thumbnailing is specifically required there (PDF/USD rendering vs. raster images).
- **Severity:** Low

### 9.11 Typo'd live/public symbol names
- **Location:** `Resources/RPGTabletopGameContent/Sources/RPGTabletopGameContent/RPGTabletopGameContent.swift:10` (`public let tabletopGameContentBunlde`, 6 call sites across `GameRenderer.swift`/`GamePortableRenderer.swift`/`GameEquipment.swift`); `Modules/GeneratorRPG/BasicAI/Model/PdfSummaryAnalyzerResultModel.swift:33` (`final class PdfSummaryAnalyzyerResultModel` — file name is spelled correctly, the type inside isn't; 3 call sites); `Modules/CoreRPG/Debug/DumpEnvironment.swift:29,43` (`asTextualRepresentationWithNonReaptingKeys`)
- **What:** Three live, actively-referenced symbols with typos in their names ("Bunlde", "Analyzyer", "Reapting"). All are in-repo (not a vendored dependency), so all call sites are fixable in one pass each.
- **Why:** Cosmetic but real — a public API typo propagates via autocomplete to every future call site; the `PdfSummaryAnalyzyerResultModel`/`PdfSummaryAnalyzer` near-miss is genuinely easy to misread at a glance (`PdfSummaryAnalysisModel.swift:18-19` has both back-to-back).
- **Action:** Rename all three and update call sites (see §2 quick wins).
- **Severity:** Low

### 9.12 Three `@Observable` model classes misplaced in `GeneratorRPG/View/` instead of `Model/`
- **Location:** `Modules/GeneratorRPG/View/PdfSummaryAnalysisModel.swift`, `TableSummaryAnalysisModel.swift`, `PdfContentExtractionModel.swift`
- **What:** All three are `@MainActor @Observable final class ...Model` types living in `View/`, while their companion `...ResultModel` types correctly live in `Modules/GeneratorRPG/BasicAI/Model/`.
- **Why:** Violates the module's own `Controller/Intent/Menu/Model/.../View/` folder convention and splits a logically-related model pair across two folders for no apparent reason.
- **Action:** Move the three files into `Modules/GeneratorRPG/BasicAI/Model/` (or `Modules/GeneratorRPG/Model/`) alongside their `ResultModel` counterparts.
- **Severity:** Low

### 9.13 Duplicated magic retry constants in the two Core Data persistence controllers
- **Location:** `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:207-212` vs. `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:201-206`
- **What:** Both contain an identical cleanup-retry `Task` using the same two magic numbers (`5`-second initial delay, `24 * 60 * 60`-second recurring interval computed inline rather than named).
- **Why:** A change to the cleanup cadence must be made in two places; `24 * 60 * 60` obscures intent versus a named `Duration`/constant.
- **Action:** Extract a shared named constant/helper used by both controllers.
- **Severity:** Low

### 9.14 Confirmed still clean: `#if false`, TODO count, unconditional `print()`
- **Location:** repo-wide
- **What:** Zero `#if false` blocks found. Exactly 1 TODO in the whole non-test codebase (`Modules/SpaceRPG/Space/SpaceViewer.swift:264`, unchanged from both prior audits — genuine backlog item, not urgent). All live `print()` sites (~26-30) fall into an accepted-exception category (`#if DEBUG`, `#Preview`, the non-shipping `MyAiPlayground.swift`, or doc-comment examples) — confirmed via targeted grep of today's newly-changed files too, zero new unconditional prints introduced.
- **Why:** Recorded so the report reflects these axes were re-checked, not assumed still true from the prior reports.
- **Action:** None required.
- **Severity:** Low (informational)

### 9.15 `CLAUDE.md` documentation drift — still open
- **Location:** `CLAUDE.md:140-149` ("Module Folder Sturcture" section lists a `Module` subfolder that exists in zero of the 15 modules); typos throughout (see §2)
- **What:** Re-confirmed via directory listing — unchanged since the first audit flagged this.
- **Why:** `CLAUDE.md` is loaded as context for every future coding session (human or AI); documentation drift here compounds the risk of every other finding being mis-applied.
- **Action:** Remove the `Module` bullet or clarify what it was meant to describe; fix the typos.
- **Severity:** Medium

---

## 10. Cross-cutting recommendations

1. **Extract the Table3D platform-duplication cluster (§9.1-§9.3) before it grows further.** This is the single largest new duplication introduced since the last audit — all in one feature area, added in one commit, and already exhibiting the classic "two copies drift apart" risk that §5.1 shows has already happened elsewhere in the codebase (`ExportController`). Given `PinPawn`/`GameMetrics`/the sync-math functions are provably platform-agnostic today, this is a low-risk, high-value extraction.
2. **Close the game-join security gap.** §6.1 is the sole Critical finding across all three audit passes now, and the only Critical/High-security item that has survived two full fix rounds untouched. A per-session pairing code is the standard fix for this exact local-network-Bonjour-pairing pattern.
3. **Centralize `ExportController`'s BFS wrapper — no longer just a duplication concern.** §9.4/§5.1: this duplication has now measurably produced a real behavioral bug (PhotoRPG's missing guard). Treat this as higher priority than a pure style cleanup.
4. **Actually execute the `PlayerController.swift` split next time, not just re-recommend it.** §9.6: this is the third audit pass to flag this file, and it has grown rather than shrunk since the last one. If the split isn't happening due to risk/time concerns, say so explicitly in a future audit rather than silently re-listing it — that's a more honest signal than repeating an unactioned recommendation a fourth time.
5. **Revisit the `.system.search` → `.searchInApp` migration alongside the next deployment-target discussion.** §4.1: the blocker (macOS/iOS 27 availability) is now a released, GM-shipping OS rather than a beta — this is no longer a "wait and see," it's a "the dependency has shipped, the only remaining question is when this project wants to move its floor."

---

## 11. What was NOT audited

- Everything already covered and fixed by the first two audit passes was **not** re-derived from scratch — see `Docu/CODE_AUDIT_1.md` and `Docu/CODE_AUDIT_2.md` for that history. This pass re-verified only the items those reports left explicitly open (§3.1, §6.1, §6.2, §4.1) plus a fresh independent sweep.
- Algorithmic correctness of RealityKit/3D-object rendering, TabletopKit synchronization semantics, and the Foundry LevelDB/ZIP binary-format parsing internals — only concurrency/isolation and bounds-safety were reviewed in prior passes; not re-reviewed here.
- Xcode project build settings and scheme configuration beyond the deployment-target confirmation (uniform 26.0) and the toolchain-version discovery in §4.1.
- Third-party SPM dependency internals (`RPGTabletopGameContent` and others) — treated as black boxes.
- Test coverage — no deep review of the 20+ test targets under `Tests/` this pass.
- Full accessibility audit (complete VoiceOver walkthrough, Dynamic Type stress testing, dark-mode contrast) beyond the targeted check on today's new Table3D controls (§8.2).
- Localization/String Catalog wording correctness.
- StoreKit/IAP configuration.
- Performance profiling with Instruments — no `.trace` was recorded; §7 is static-analysis-only.
- Domain logic outside the specifically-flagged newest commits — `PlayerController.swift`/`MasterController.swift`/`GameController.swift`'s non-Table3D business logic (map-pin geometry math beyond what §9.1/§9.2 cite, battle-round bookkeeping beyond what §8.1 cites) was not exhaustively re-read line-by-line this pass.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line. Every Critical/High finding below was personally re-opened and confirmed this pass (not taken solely from a background agent's report).

- **§6.1** (Critical) — `Modules/GameRPG/Network/GameSecurity.swift:1-8`: confirmed `static let passcode = "GameMasterCode"` (line 7) is the entire declared type. `Modules/GameRPG/Browser/BrowserManager.swift:52-138`: confirmed no join-code/PIN field or prompt exists anywhere. A repo-wide grep for `joinCode|pairingCode|sessionCode|pinCode|passphrase` returns zero results.
- **§3.1** (High) — `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:108,112`: confirmed `internal func resume(...)` at line 108 and `DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.send(values: values) }` at line 112, inside the `.auto` case.
- **§9.1** (High) — `Modules/GameRPG/Table3D/GameSetup.swift:13-22,206-240` vs. `GamePortableSetup.swift:10-19,153-187`: personally ran `diff` on both `syncRooms` (lines 206-240 / 153-187) — zero output, byte-for-byte identical — and on `projection` — differs only by one comment and one redundant `@MainActor`. `GameMetrics` values confirmed numerically identical at lines 13-22 / 10-19.
- **§9.2** (High) — `Modules/GameRPG/Table3D/GameEquipment.swift:439-517` vs. `GamePortableEntities.swift:509-589`: personally ran `diff` — identical apart from a trailing, out-of-range helper enum in the portable file.
- **§9.4** (High) / **§5.1** (Medium) — `Modules/PhotoRPG/Controller/ExportController.swift:28-36` vs. `Modules/PdfRPG/Controller/ExportController.swift:28-37`: personally ran `diff` — confirmed PhotoRPG is missing the `guard item.specialCategory else { return [] }` line (PdfRPG's line 31) that all 5 sibling "simple" modules have; confirmed `specialCategory`'s definition at `Modules/CoreRPG/ItemList/ItemDataAccessable.swift:111-113`.
- **§6.2** (Medium) — `plutil -p Resources/MasterRPG.entitlements` (and the other two): confirmed `"aps-environment" => "development"` present in all three; `grep -rln "UNUserNotificationCenter|registerForRemoteNotifications|PushKit|didReceiveRemoteNotification" Modules/ Sources/` returns zero matches.
- **§4.1** (Low, re-framed from Medium) — confirmed via a full clean build (`clean_build_log.txt`) that zero `.system.search` deprecation warnings are emitted; confirmed via `AppIntents.swiftinterface` (Xcode 27.0 GM SDK) that `.search` is `@available(anyAppleOS, deprecated: 27.0, ...)` and `.searchInApp` is `@available(anyAppleOS 27.0, *)` — both gated to exactly 27.0, above this project's 26.0 deployment target.
- **§9.15** — `CLAUDE.md:140-149`: confirmed no module has a literal `Module/` subfolder via directory listing of all 15 modules.

If any finding doesn't reproduce when you visit the line, flag the specific reference for re-investigation.
