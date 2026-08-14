# MasterRPG Code Audit

Generated 2026-08-14. Scope: ~266,409 Swift LOC across 1,956 files, 0 Metal kernels, spanning targets `MasterRPG` (iOS/visionOS), `MasterMac`, `MasterTV`, `RPGShare`, `DiceRollerWidgetExtension`, and 15 feature modules (`AdventureRPG`, `AudioRPG`, `CharacterRPG`, `CoreRPG`, `DiceRPG`, `GameRPG`, `GeneratorRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `RolePlayGameKit`, `RuleRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG`). Deployment target confirmed uniformly 26.0 across iOS/iPadOS/tvOS/visionOS/macOS. No `Dead/` or archived-code directory exists in this project.

**This is the fourth audit pass**, and the deepest to date. Three prior rounds (`Docu/CODE_AUDIT_1.md` 2026-08-07, `Docu/CODE_AUDIT_2.md` 2026-08-10, `Docu/CODE_AUDIT_3.md` 2026-08-11 — all preserved alongside this report) already found and fixed the large majority of issues in this codebase. Since the third audit, the codebase saw **410 files changed (+8,164/−5,258 lines)** in just three days, including a full rewrite of the local-network pairing security model and a substantial new "each player has their own d20" feature touching `Modules/GameRPG/Table3D/` — a subsystem no prior audit had ever reviewed. This pass therefore did two things in parallel: (1) re-verified every item the third audit left explicitly open, and (2) ran five independent deep-read passes — concurrency/API modernity, dead code/duplication, GameRPG/SharePlay/Table3D bugs+security+performance, all-other-modules bugs+security+performance, and a SwiftUI-focused pass — each scoped to cover ground the prior three rounds under-covered (CharacterRPG, TableRPG, WeatherRPG, RuleRPG, AdventureRPG, PdfRPG, AudioRPG, SpaceRPG business logic; `RolePlayGameKit`; CoreData model files; macOS/tvOS-specific paths; and, above all, the brand-new Table3D code). Every Critical/High claim below was personally re-opened and confirmed by reading the cited lines — see §12.

Fresh clean builds this session — `xcodebuild clean build` for `MasterRPG` (iOS Simulator), `MasterMac` (macOS), and `MasterTV` (tvOS Simulator) — **all three succeeded with zero real Swift compiler warnings** (down from 4 at the last audit; the only log lines are unrelated `appintentsmetadataprocessor` tooling notices). This is the first audit pass to build and check all three primary platform targets, not just iOS.

**The headline result:** the sole Critical finding that survived all three prior audit rounds — a hardcoded, world-shared TLS pre-shared key allowing any nearby device to join or inject state into any game — is now **fixed**, replaced with a genuine per-device join-code system. See §6.1. No new Critical findings were identified this pass. The new "each player has their own d20" feature, however, shipped with three real High-severity bugs (§5.1, §5.2, §3.3) that a focused read caught before they reached more users.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

---

## 1. Executive summary

1. **[Security] The sole Critical finding across three prior audits — a hardcoded, world-shared TLS pairing key — is now FIXED** — §6.1 — `Modules/GameRPG/Network/GameSecurity.swift` deleted, replaced by `Modules/GameRPG/Network/GameJoinCodeModel.swift`. Residual Medium: the new per-device join code is only 4 numeric digits (10,000 combinations) with no connection-attempt rate-limiting anywhere in the pairing path.
2. **[High/Bugs] The new "each player has their own d20" feature silently drops the 3rd+ die result** in any single roll of 3+ d20 — §5.1 — `Modules/GameRPG/Table3D/GameTableModel.swift:161-178`.
3. **[High/Bugs] A `% 2` seat-assignment collision means the 3rd+ SharePlay participant shares another player's physical dice** — directly undermining the new feature's own stated goal — §5.2 — `Modules/GameRPG/Table3D/GameEquipment.swift:814-820`.
4. **[High/Concurrency] An untracked `Task {}` was added around a call explicitly documented as needing to stay synchronous**, risking a silent 3D-table desync after a SharePlay reconnect — §3.3 — `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:2033-2035`.
5. **[High/Dead code] Table3D's visionOS/iOS-macOS platform duplication (~450 lines: `MapTableProjection`, `PinPawn`, sync math) is still open, and two more commits have now hand-synced both copies** — §9.1 — `Modules/GameRPG/Table3D/GameSetup.swift` vs `GamePortableSetup.swift`.
6. **[High/Concurrency] `DispatchQueue.main.asyncAfter` for delayed navigation resume — flagged in the 2nd and 3rd audits, still open** — §3.1 — `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:112`.
7. **[Medium-High/Performance] `AudioController` copies every playlist track to a freshly-UUID-named temp file on every play, with no cleanup — an unbounded disk-space leak** — §7.1 — `Modules/AudioRPG/Controller/AudioController.swift:131-165`.
8. **[Medium/Bugs] Any table with exactly one entry has a ~50% chance per roll of failing to resolve to its own entry**, due to a die-clamp/index mismatch in the core random-table feature — §5.3 — `Modules/TableRPG/Controller/TableGenerationController.swift:144-164`.
9. **[Medium/Security] `GeneratorRPG`'s conversation seeding folds untrusted, import-derived text into the model's elevated-trust `instructions:` channel instead of `prompt:`**, breaking the pattern every sibling analyzer correctly follows — §6.3 — `Modules/GeneratorRPG/Controller/GeneratorController.swift:188-199`.
10. **[Medium/Dead code] `PlayerController.swift` is still not split — third consecutive audit to flag it, and it has grown, not shrunk (3,913 → 3,915 lines)** — §9.4.

**The good news:** all five independent deep-read passes converged on the same conclusion — this is a mature, well-hardened codebase. The Foundry VTT untrusted-archive importer has zero force-unwraps and full zip-slip/decompression-bomb protection (§11). Every CoreData model file is CloudKit-compliant. The `ExportController` behavioral-drift bug from the third audit is fixed and centralized (§9.2). No new Critical findings exist anywhere in the ~266K-line codebase this pass — the only High-severity items are concentrated in one week-old, 4,650-line feature area (Table3D) that had never been read end-to-end before this audit.

---

## 2. Quick wins (≤30 min each)

- **Fix the `CarouselPhotoView.swift:11` scroll-indicator API** — use `.scrollIndicators(.hidden)` instead of `showsIndicators: false`. See §8.7.
- **Fix `GameRenderer.swift:167`'s force-unwrap** — `cursorEntity.model!.materials.append(...)` → `cursorEntity.model?.materials.append(...)`. See §5.6.
- **Delete the leftover commented-out code** in `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift:44,50,76-80`, `BattleRoundWideCardLayout.swift:36`, `BattleAttackerDetails.swift:14-16`. See §8.4.
- **Delete 4 confirmed-unreferenced functions**: `ValueEntryModel.swift:113-121` (`nameText(otherValue:)`), `ItemController.swift:43-48` (`subchildren(itemId:deep:)`, CharacterRPG), `TableEntryModel.swift:119-126` (`nameLinkText`/`contentLinkText(otherValue:)`). See §9.16.
- **Delete the unreachable Weather residue chain** — `Modules/WeatherRPG/Weather/ResidueView.swift`, `Residue.swift`, `ResidueDrop.swift` (169 lines, zero call sites) — or wire `ResidueView` into `WeatherViewer.swift` if the effect was meant to ship. See §9.15.
- **Fix the user-facing typo "Becareful"** (×2) in `Modules/RolePlayGameKit/View/SettingsView.swift:145,150` → "Be careful" — this is shipped, localized copy, not a code comment. See §9.14.
- **Fix `CLAUDE.md` typos found this pass**: "imsges" (line 98) → "images"; "TableTopKit" (line 126) → "TabletopKit" (the real framework name); lowercase "swiftUI" (line 81) → "SwiftUI"; "a game mode there players" (line 7) → "where players"; "Moduls"/"layoput" (line 127) → "Modules"/"layout". See §9.7.
- **Rename the typo'd live protocol `SpotlightIndexerAtyribute` → `SpotlightIndexerAttribute`**, updating its 12 conformance sites. See §9.8.
- **Rename `toggleKetpath` → `toggleKeyPath`** across its 6 call sites in `Modules/DiceRPG/Dice/*.swift`. See §9.19.
- **Fix `PdfContentView.swift`'s "Thumnail" typo** and either wire the dead `horizontalThumnailSize` into the horizontal-layout branch or delete it. See §5.7.
- **Fix the copy-pasted log message** in `Modules/CharacterRPG/Controller/ExportController.swift:110` — says "Table" (copied from `TableRPG`'s sibling file), should say "Character" or "Value". See §9.17.
- **Delete two confirmed-dead RolePlayGameKit types**: `SyncStateViewModifier.swift:24-74` and `AppModel.swift:359-367` (`loadFreePackages`) — zero call sites for either. See §9.14.

---

## 3. Concurrency

Strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`) compiles with zero warnings across all three fresh clean builds (iOS, macOS, tvOS). This section covers anti-patterns the compiler doesn't catch.

### 3.1 `DispatchQueue.main.asyncAfter` for delayed navigation resume — still open, third audit to flag it
- **Location:** `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:107-114`, violation at line 112, inside `Navigator.resume(_:values:delay:)`'s `.auto` case (and `.after(interval)`, which forwards to it).
- **What:** Resuming a paused deep-link value queue — used so a tab-switch/push animation can finish before the next hop in a `navigator.send(...)` chain fires — calls `DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.send(values: values) }`, where `delay` is `executionDelay` (0.3-5.0s, from `NavigationConfiguration`).
- **Why:** Directly violates the project's house rule against GCD-style dispatch; the closure strongly captures `self` (the `Navigator`) with no cancellation path if the navigator/scene tears down mid-delay, and it sits entirely outside Swift's structured-concurrency cancellation tree. Flagged in the 2nd and 3rd audits and never addressed.
- **Action:** Replace with a tracked `Task { try? await Task.sleep(for: .seconds(delay)); await send(values: values) }`, stored so a subsequent `reset()`/dealloc can cancel it — mirroring the tracked-task pattern already used elsewhere in this codebase (`GameTableModel.pendingThumbnailTasks`, `RPGSharePlayController`'s pending-teardown tracking).
- **Severity:** High

### 3.2 Piecemeal `@MainActor` on `Sendable` network/game controllers — still open, and broader than previously tracked
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:443` (`final class MasterController: Sendable`); `Modules/GameRPG/Controller/PlayerController.swift:1062` (`final class PlayerController: Sendable`, 20 `@MainActor` annotations vs. 94 methods); `Modules/GameRPG/Network/GameNetworkController.swift:503` (`final class GameNetworkController: Sendable`); `Modules/GameRPG/Master/MasterNetworkController.swift:28` (`final class MasterNetworkController: Sendable`, 14/18 methods annotated) — newly identified; `Modules/GameRPG/Player/PlayerNetworkController.swift:28` (no `Sendable` at all, 11/21 methods annotated) — newly identified.
- **What:** Each class marks isolation per-method instead of isolating the whole type, unlike their sibling *model* classes in the same files (`MasterControllerModel`, `PlayerControllerModel`, `GameNetworkControllerModel`, all correctly `@MainActor @Observable`) and unlike `GameCenterController` (`Modules/GameRPG/GameCenter/GameCenterController.swift:58`), which shows the fix is already proven elsewhere in the same module.
- **Why:** A new method added without `@MainActor` silently becomes `nonisolated`; strict concurrency only catches genuinely unsafe cross-actor access, not "should have been isolated but happens to be safe today." Originally tracked at 2 sites; now confirmed at 5.
- **Action:** Promote each class to `@MainActor final class ... : Sendable` (dropping the explicit `Sendable` where redundant) and remove the now-unnecessary per-method annotations, matching the already-applied fix on `GameCenterController`/`RPGSharePlayController`/`GameTableModel`/`MapGameModel`.
- **Severity:** Medium

### 3.3 Untracked `Task {}` wraps a call explicitly documented as needing to stay synchronous — new regression in the multi-d20 commit
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:2027-2034`, inside the `#if os(visionOS)` branch of the group-session-configure path. Contrast with the sibling call site at `:733-736` (`setup(tabletopGame:gameTableModel:)`), which still calls the same API directly and synchronously.
- **What:** The multi-d20 commit (`87dfc526`) added `Task { tabletopGame?.coordinateWithSession(groupSession) }` three lines below a comment that reads, verbatim: *"This API is synchronous. Calling it directly keeps coordination in the configured session's lifetime instead of spawning an obsolete, untracked task that reset() cannot cancel."* The new code does exactly what the comment warns against, and the `Task` is never stored in the `tasks[UUID()]` dictionary that `reset()` (lines 1617-1654) cancels.
- **Why:** On a SharePlay reconnect/session-replacement race, this orphaned `Task` can fire after `reset()` has already run, re-attaching the network coordinator to a stale `GroupSession` — silently stopping pin/dice sync on the visionOS 3D table between the Game Master and players, with no error surfaced.
- **Action:** Revert to a direct synchronous call, matching line 736 and the adjacent comment's own stated rationale; if async dispatch is genuinely needed here, track the `Task` in `tasks[UUID()]` so `reset()` can cancel it.
- **Severity:** High

### 3.4 `GroupActivityManager` conforms to raw `Observable` protocol instead of the `@Observable` macro
- **Location:** `Modules/GameRPG/Table3D/GroupActivityManager.swift:9` — `class GroupActivityManager: Observable {`.
- **What:** `Observable` (the `Observation` framework's marker protocol) is declared manually, without the `@Observable` macro — this produces no actual observation-tracking plumbing (no registrar, no `access`/`withMutation` calls); the type is "Observable" in name only.
- **Why:** Contradicts the house rule that shared data use `@Observable`. Harmless today only because no SwiftUI view body currently reads this type's properties reactively — a landmine for the next property added expecting SwiftUI invalidation.
- **Action:** Replace with `@MainActor @Observable class GroupActivityManager` (the macro adds the protocol conformance).
- **Severity:** Low

### 3.5 Table3D's `GroupActivityManager`/`GameObserver` MainActor isolation — now fixed
- **Location:** `Modules/GameRPG/Table3D/GroupActivityManager.swift:8-19`, `Modules/GameRPG/Table3D/GameObserver.swift:8-17`.
- **What:** The third audit flagged inconsistent isolation here vs. siblings (`ListenerManager`, `BrowserManager`, `GameTableModel`). Both are now whole-type `@MainActor`, and `GroupActivityManager` has an `isolated deinit`.
- **Action:** None — resolved.
- **Severity:** Low (informational)

### 3.6 `PlayerController.swift`'s 4 "unnecessary `await`" warnings — now fixed
- **Location:** `Modules/GameRPG/Controller/PlayerController.swift:3773-3839` (`scheduleSendCharacterTask`, `scheduleProxyFocusTask`, `clearProxyFocusTask`, `completeProxyFocus`).
- **What:** The third audit's own `MainActor.run`-removal cleanup left 4 warnings behind. Confirmed fixed — matches the zero-warning clean build this pass.
- **Action:** None — resolved.
- **Severity:** Low (informational)

---

## 4. API modernity

### 4.1 Deprecated `.system.search` App Shortcuts schema — unchanged, still blocked on a deployment-target bump
- **Location:** 12 sites, one per module: `Modules/AdventureRPG/Intent/SearchAdventuresIntent.swift:8`; `Modules/{Character,Rule,Generator,Dice,Space,Photo,Audio,Weather,Pdf,Table,Map}RPG/Intent/*ManagementIntents.swift` (~line 89-94 each).
- **What:** Re-confirmed identical to the third audit: `.search` is deprecated exactly at OS version 27.0, and `.searchInApp`/`SyncableEntity`/`IndexedEntityQuery` require iOS 27 — both above this project's 26.0 deployment target, so the replacement path is correctly `@available`-gated but not yet usable. No drift in count or root cause since the last two audits.
- **Why:** No action possible until the deployment target moves to 27.
- **Action:** Fold into the same change the next time a 26→27 deployment-target bump is considered — all 12 sites are mechanically identical.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Multi-d20 feature silently drops the 3rd+ die result in a single roll
- **Location:** `Modules/GameRPG/Table3D/GameTableModel.swift:161-178` (`applyDiceRoll`), cross-referenced with `Modules/GameRPG/Table3D/GameSetup.swift:99-104` (per-seat `Die20` allocation).
- **What:** Each seat is pre-allocated exactly 2 `Die20` table entities (`playerDiceIds[seatId] = [firstD20.id, secondD20.id]`). `applyDiceRoll` mirrors character-sheet d20 rolls onto them via `nextD20Index < d20Ids.count` (always 2) — any 3rd+ d20 in the same `DiceModel.dice` roll (a homebrew "roll 3d20," or a GM batch-rolling for multiple NPCs at once) is silently `continue`'d, with no log or user-facing indication that a result was dropped.
- **Why:** `DiceModel.dice` is an unbounded array — nothing prevents configuring more than 2 d20 per roll — but the table hardware model has a hard 2-slot ceiling per seat. A player/GM rolling 3+ d20 will see only 2 results reflected on the shared 3D table with no explanation.
- **Action:** Either surface the overflow (a warning log, or a visible "N results not shown on table" indicator) or expand `playerDiceIds` to allocate as many `Die20` slots as the largest supported simultaneous roll.
- **Severity:** High

### 5.2 SharePlay seat-assignment `% 2` collision breaks per-player dice ownership for 3+ players
- **Location:** `Modules/GameRPG/Table3D/GameEquipment.swift:277-283` (`PlayerSeat.seatPoses`, a fixed 3-element array: 1 master + 2 player positions) and `:814-820` (`assignSeatsForSharePlay`): `let playerSeatCount = PlayerSeat.seatPoses.count - 1` (= 2); `let seatIndex = (localIndex % playerSeatCount) + 1`.
- **What:** For `localIndex` 0, 1, 2, 3... this wraps to `seatIndex` 1, 2, 1, 2... — the 1st and 3rd sorted participants (by `activeParticipants` UUID sort) collide on `seatIndex == 1`.
- **Why:** This seat-collision pattern predates this week's changes (previously affecting only visual pawn/hand placement), but the new per-seat dice allocation (§5.1's `playerDiceIds[seatId]`) makes it materially worse: two colliding players now share the exact two `Die20` equipment IDs, so one player's character-sheet roll moves/overwrites the physical dice the other colliding player also treats as "their own" — directly undermining the feature's own stated purpose ("each player has it's own"). Parties of 3+ players are common, not an edge case.
- **Action:** Either extend the table to support more physical seats/dice pairs for larger parties, or key `playerDiceIds` by stable participant identity rather than the (collision-prone) `TableSeatIdentifier`.
- **Severity:** High

### 5.3 Any table with exactly one entry has a ~50% chance per roll of failing to resolve
- **Location:** `Modules/DiceRPG/Model/RawDie.swift:97-101` (`Sides.number()` clamp — any value `< 2` is forced up to `2`, avoiding a crashing `Int.random(in: 1...0)` for 0-entry tables) combined with `Modules/TableRPG/Controller/TableGenerationController.swift:144-164` (`roll(occurrence:model:)`) and `:201-214` (`matchingEntry(for:in:)`).
- **What:** Rolling a 1-entry table calls `diceRoot.role(number: occurrence.entries.count)` → `RawDie(.number(1))`, but `Sides.number()`'s clamp silently turns this into a d2. `matchingEntry` then only accepts results 1 or 2 as index `0`/`1` — but no index 1 exists, so a roll of "2" fails to match and surfaces `model.errorMessage = "Roll 2 does not match an entry..."`.
- **Why:** Any single-entry table — a real, unremarkable configuration — has an unintended ~50% per-roll chance of hitting a visible error instead of resolving to its only entry. No test covers this case (`Tests/TableRPGTests/TableGenerationControllerTests.swift` has no single-entry test).
- **Action:** Special-case `occurrence.entries.count == 1` in `roll(occurrence:model:)` to auto-select the sole entry without rolling, or adjust `matchingEntry`'s indexing so the clamp doesn't leak into 1-entry table math.
- **Severity:** Medium

### 5.4 `CharacterRPG.LinkController.validate()` declares filter parameters it never reads
- **Location:** `Modules/CharacterRPG/Controller/LinkController.swift:186-189` — `func validate(id: UUID?, isCharacter: Bool = false, isGameMaster: Bool = false) -> UUID?`.
- **What:** The body (`itemController.itemDataModel.items.first(where: { $0 == id })`) never reads `isCharacter` or `isGameMaster` — it only checks that `id` belongs to the module's item list at all, not that it's actually a Character (vs. NPC/monster/nested "group" value table).
- **Why:** The one non-default caller, `Modules/CharacterRPG/Controller/GameController.swift:207-210` (`playerPinPhoto(for characterId:)`), passes `isCharacter: true`, implying an expectation that filtering is scoped to real player Characters (map pins are meant for players) — but any NPC/monster/group-table id currently validates successfully too. Whether this is exploitable depends on upstream UI guarantees not independently verified end-to-end.
- **Action:** Either implement the category filter the parameter names imply, or remove the unused parameters if filtering was intentionally dropped.
- **Severity:** Low-Medium

### 5.5 Force-unwrapped `linkRegisterController!` repeated across 26 sites in 11 modules, unlike the module that already has a safer pattern
- **Location:** `Modules/{Adventure,Audio,Character,Dice,Generator,Map,Pdf,Photo,Space,Table,Weather}RPG/Controller/{EditController,ItemController,SheetController}.swift` — e.g. `Modules/SpaceRPG/Controller/EditController.swift:26`, `Modules/CharacterRPG/Controller/ItemController.swift:28`, `Modules/AdventureRPG/Controller/SheetController.swift:12`.
- **What:** Each reads `itemDataModel.linkRegisterController!` — a bare force-unwrap of a property each module's `RootModel.init()` assigns shortly after construction.
- **Why:** `Modules/RuleRPG/Controller/ItemController.swift:27-33` already shows this codebase's own established, safer pattern for exactly this situation: `guard let controller = itemDataModel.linkRegisterController else { preconditionFailure("RuleRPG requires a LinkRegisterController after setup.") }` — the same pattern used for `hubControllable` in every `ExportController.swift`. The other 11 modules never got this treatment, so a future call path reading the property before `RootModel.init()` finishes (a Preview, a test, a reset-without-reassign) crashes with a generic, contextless "unexpectedly found nil" instead of a diagnostic message.
- **Action:** Replace the 26 sites with the `guard let ... else { preconditionFailure(...) }` pattern already proven in `RuleRPG`, ideally factored into a shared `ItemControllable`/`EditControllable`/`SheetControllable` protocol-extension default to prevent future drift.
- **Severity:** Medium

### 5.6 Force-unwrap in shared RealityKit cursor setup
- **Location:** `Modules/GameRPG/Table3D/GameRenderer.swift:167` — `cursorEntity.model!.materials.append(cursorMaterial)`.
- **What:** Force-unwraps `.model` inside `ModelEntity.cursor`'s static factory.
- **Why:** Low risk in practice (`ModelEntity(mesh:)` always populates `.model`), but it's the only remaining force-unwrap across all 17 files in the Table3D directory, and is inconsistent with the do/catch hardening used elsewhere in the same module for RealityKit asset construction.
- **Action:** `cursorEntity.model?.materials.append(cursorMaterial)`.
- **Severity:** Low

### 5.7 `PdfContentView`'s horizontal-layout thumbnail size is dead code, and the horizontal layout never adapts
- **Location:** `Modules/PdfRPG/Pdf/PdfContentView.swift:79-98`.
- **What:** `private var horizontalThumnailSize: CGSize { CGSize(width: 54, height: 75) }` is declared but never referenced anywhere else in the file — `thumbnails` always passes `verticalThumnailSize` regardless of `horizontal`. `ThumbnailPdfView.swift:27` correctly switches `layoutMode` between the two, but the *size* never follows. Both names are also typo'd ("Thumnail" → "Thumbnail").
- **Why:** Simultaneously dead code (an unused property) and a plausible visual bug — horizontal-layout PDF thumbnails render at the vertical layout's size/aspect ratio.
- **Action:** Wire `horizontalThumnailSize` into the `horizontal == true` branch, or delete it if one size is meant to serve both layouts; fix the typo either way.
- **Severity:** Low

### 5.8 iPad photo-selection crash fix — confirmed sound
- **Location:** `Modules/PhotoRPG/Route/MultiSelectionDestinationView.swift:6-11`, fixed in commit `eec03122`.
- **What:** The old code read `@Environment(ItemSelectionModel.self)` with no default — SwiftUI traps at runtime if no ancestor view supplied that environment value, which was the actual crash mechanism. The fix sources `root.itemSelectionModel` directly from `PhotoRootModel` instead, matching the working pattern already used by `SelectionRoute.swift:30`. A repo-wide grep confirms no other `@Environment(ItemSelectionModel.self)` usage remains anywhere in `PhotoRPG`.
- **Action:** None — verified complete and correct.
- **Severity:** Low (informational)

---

## 6. Security

### 6.1 Critical hardcoded world-shared TLS pairing key — CONFIRMED FIXED; residual Medium risk in its replacement
- **Location:** `Modules/GameRPG/Network/GameSecurity.swift` — **deleted**. Replaced by `Modules/GameRPG/Network/GameJoinCodeModel.swift:1-94`, wired through `Modules/GameRPG/Network/NWParameter+GameMaster.swift`, `ListenerManager.swift`, `ConnectionController.swift`, `Modules/GameRPG/Master/MasterNetworkController.swift`, `Modules/GameRPG/Player/PlayerNetworkController.swift`, `Modules/GameRPG/Browser/BrowserRowView.swift`, `Modules/GameRPG/Controller/MasterController.swift:498`, `Modules/GameRPG/Controller/PlayerController.swift:1109-1113`.
- **What:** All three prior audits flagged, as the sole Critical finding across the codebase, `static let passcode = "GameMasterCode"` — a single secret shared by every install, letting any nearby device join or inject state into a stranger's live game. This has been fully replaced: `GameJoinCodeModel` generates a random 4-digit numeric code (`"0000"`-`"9999"`) independently per device per role (`masterCode` gates the primary listener, `playerCode` gates the proxy listener), persists it in `UserDefaults`, and derives the TLS PSK from it instead of the old constant. Personally traced every call site — the code is genuinely required end-to-end, not decorative, and is never logged (grepped every `passcode`/`joinCode`/`masterCode`/`playerCode` reference against `Logger`/`print` call sites — zero matches).
- **Residual risk:** A 4-digit numeric code is only 10,000 combinations. Both `ListenerManager.swift` (184 lines) and `ConnectionController.swift` (251 lines) were read in full — neither contains any connection-attempt counter, delay, backoff, or lockout; a failed TLS handshake can be retried immediately with a new guess, from the same or a different peer. At a multi-hour game session on a shared network (e.g. a convention or game store), a determined nearby attacker running an automated script could feasibly exhaust the keyspace.
- **Why:** This is a genuine, substantive fix — the full-compromise authentication bypass is closed — but the replacement's small keyspace with zero rate-limiting is a real (much lower severity) residual gap worth closing before relying on this as a hard security boundary.
- **Action:** Add connection-attempt throttling/lockout to `ListenerManager`/`ConnectionController` (e.g. exponential backoff per source, or a short lockout after N consecutive failures), and/or widen the code space (alphanumeric, or more digits) if convention/public-network use is a realistic scenario for this app.
- **Severity:** Critical → Fixed; residual finding Medium

### 6.2 `aps-environment: development` in Release entitlements — confirmed fixed
- **Location:** `Resources/MasterRPG.entitlements`, `Resources/MasterTV.entitlements`, `Sources/RPGShare/RPGShare.entitlements`.
- **What:** The second and third audits flagged this key baked into every push-capable target's entitlements with zero push-notification code present. Confirmed via `git diff` and direct grep: the key is now absent from all three files, and a repo-wide grep for `UNUserNotificationCenter`/`registerForRemoteNotifications`/`PushKit` still returns zero matches (i.e., the removal didn't silently break anything that was relying on it).
- **Action:** None — resolved.
- **Severity:** Low (informational)

### 6.3 Untrusted, import-derived content elevated into the model's `instructions:` channel instead of `prompt:`
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:188-199` (`seedConversationContext`) and `:404-425` (`compactSheetIndex`); related pattern in `Modules/GeneratorRPG/BasicAI/Engine/ConversationEngine.swift:301-341` (`generateConversationSummary`/`createNewSession`).
- **What:** `seedConversationContext` concatenates the static `defaultInstructions` with `compactSheetIndex(from: sheetModel)` — the sheet's own name plus its entries' names, up to 600 characters — and passes the result into `LanguageModelSession`'s `instructions:` parameter (the elevated-trust channel), not `prompt:`. Sheet entry names can originate from Foundry VTT import (untrusted third-party campaign data). Separately, `ConversationEngine.createNewSession(with:)` folds a model-generated conversation summary into the new session's `instructions:` on context-window overflow.
- **Why:** Every other AI-generation call site in this module (`PdfSummaryAnalyzer.swift:55-62`, `TableSummaryAnalyzer.swift:24-29`, `PdfContentExtractor.swift:68-74`) correctly keeps document-derived/untrusted text in `prompt:` and reserves `instructions:` for static, developer-authored text only. This one path breaks that pattern, elevating externally-sourced text to the channel FoundationModels' guardrails weigh more heavily. Bounded today — only entry *titles* (not full content), capped at 600 characters, and Apple's on-device guardrails still apply — so this is a defense-in-depth gap, not a directly demonstrated exploit.
- **Action:** Move `sheetIndex`/conversation-summary content into the per-turn `prompt:` (e.g. as prefixed contextual reference text), consistent with the sibling analyzers' existing pattern.
- **Severity:** Medium

---

## 7. Performance

### 7.1 `AudioController` leaks a temp file per track play, unbounded, with no cleanup
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:131-165` (`audioAsset(for:)`).
- **What:** Every time a track loads for playback, it's copied to `URL.temporaryDirectory` under a path suffixed with a freshly-generated `UUID().uuidString` (lines 143, 156) — the copy is never deleted. There is no `removeItem` anywhere in `AudioRPG`, no `deinit` cleanup in `AudioController`/`AudioPlayerModel`, and no session-end purge.
- **Why:** `add(audio:)` is called with `replace: true` repeatedly during normal use (e.g. every playlist switch — `DetailEditorToolBarButtons.swift:19`, `SharingActionView.swift:45`, `GameController.swift:237/245`); each switch re-copies every track to a brand-new randomly-named file. Temp storage grows unboundedly with playlist-switch count × track size for the life of the process. Contrast: the sibling `Modules/AudioRPG/Controller/GameController.swift:157-195` audio path uses a *stable* `itemId.uuidString` filename that gets overwritten on reuse — a smaller version of the same missing-cleanup gap, but bounded by distinct-items-played rather than play count.
- **Action:** Reuse a stable per-item temp filename (as `GameController.swift` already does) instead of a fresh UUID per play, and/or delete the previous track's temp file when `replace: true` clears the playlist or a `PlaylistItem` is evicted.
- **Severity:** Medium-High

### 7.2 Battle-round card presentations rebuilt from scratch on every render, bypassing the optimization built for exactly this
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundCardPresentation.swift:31-72` (`cardPresentations`, an uncached computed property doing a dictionary build + O(n) pass); called from `Modules/GameRPG/BattleRound/BattleRoundView.swift:54`.
- **What:** Per its own doc comment, this recomputes on "every live Battle Round tick" — upstream of the per-card `.equatable()` optimization that `BattleRoundCard` already carries specifically to avoid this class of cost (see §8.8/prior audit's §8.1).
- **Why:** The `.equatable()` guard on individual cards is undermined if the array feeding `ForEach` is rebuilt (new object identities/values) on every tick regardless of whether anything actually changed.
- **Action:** Cache `cardPresentations` on `BattleRoundModel`/`BattleRoundScreenModel`, invalidating only when combatants/entries/rolls actually change.
- **Severity:** Medium

---

## 8. SwiftUI / UI

### 8.1 visionOS is missing the room-viewport panning gesture that iOS/macOS just got
- **Location:** `Modules/GameRPG/Table3D/GameTableView.swift:16-181` (visionOS body has no equivalent of the `viewportPanGesture` added at lines 399-489 for iOS/macOS); `Modules/GameRPG/Table3D/GameEquipment.swift:36-62` (visionOS `Board.init()` never sets `BoardSurfaceComponent`/`InputTargetComponent`/`CollisionComponent`, unlike `Modules/GameRPG/Table3D/GamePortableEntities.swift:27-61`).
- **What:** The "game map move" commit wired a drag-to-pan gesture for a zoomed/focused room's crop into the iOS/macOS camera table only — the visionOS board surface isn't even hit-testable for it.
- **Why:** `GameTableModel.panViewport`/`manualViewportOffset` are platform-shared model APIs, so this reads as an unintentional gap: visionOS players can zoom into a room but can't pan within it, while iOS/macOS players can do both.
- **Action:** Add a `BoardSurfaceComponent` + hit-test collision to the visionOS `Board`'s image plane, and an equivalent drag gesture to `GameTableView`'s visionOS body.
- **Severity:** Medium

### 8.2 Physical dice entities carry no accessibility exposure, unlike their pin/room siblings
- **Location:** `Modules/GameRPG/Table3D/GameEquipment.swift:572-696` (`Die20`), `:698-783` (`Die`) — contrast with `PinPawn` (`:420-426`) and `RoomHitArea` (`:536-541`), both of which set an `AccessibilityComponent`.
- **What:** Neither die type sets an `AccessibilityComponent` label/value/activate action.
- **Why:** The multi-d20 feature tripled the table's interactive dice (1 shared die → 6, i.e. 2 per seat × 3 seats), tripling an existing accessibility gap for the *direct on-table toss* interaction path. Partially mitigated: `GameTableModel.applyDiceRoll` (§5.1) already mirrors a VoiceOver-accessible character-sheet roll onto the table dice automatically, so this isn't the only way to roll — but the direct-toss path itself remains inaccessible.
- **Action:** Add an `AccessibilityComponent` (per-seat label, `.activate` to toss) to `Die20`/`Die`, mirroring the existing pins/rooms pattern.
- **Severity:** Medium

### 8.3 `Die` (6-sided) struct is now dead code
- **Location:** `Modules/GameRPG/Table3D/GameEquipment.swift:698-783`.
- **What:** Its init signature was updated by the multi-d20 commit (`pose`/`seatControl` params added) but nothing constructs a `Die` anywhere in Table3D — only `Die20` is ever added, in `GameSetup.init()`.
- **Action:** Remove `Die`, or wire it into `GameSetup` if a d6 pool is still planned.
- **Severity:** Low

### 8.4 Leftover commented-out code in this week's touched Battle Round views
- **Location:** `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift:44,50,76-80`; `Modules/GameRPG/BattleRound/BattleRoundWideCardLayout.swift:36`; `Modules/GameRPG/BattleRound/BattleAttackerDetails.swift:14-16`.
- **What:** Commented-out conditional/view code left in place rather than deleted, in files touched by this week's commits.
- **Action:** Delete.
- **Severity:** Low

### 8.5 `BattleParticipantColumn.isAttacker` is passed everywhere, read nowhere
- **Location:** `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift:12` (declared; only referenced inside the commented-out block at line 44); call sites `BattleRoundWideCardLayout.swift:23`, `BattleRoundCompactCardLayout.swift:24`, `BattleDefenderStrip.swift:33`.
- **What:** Either dead plumbing, or a real regression where a name label was meant to be conditional on attacker/defender and the conditional got commented out (§8.4) instead of finished.
- **Action:** Remove the parameter end-to-end, or restore/finish the intended conditional.
- **Severity:** Low-Medium

### 8.6 `BattleRoundHeader.hasEntries` passed, never read
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundHeader.swift:8`; passed from `BattleRoundView.swift:23`.
- **Action:** Remove the unused parameter, or use it if it was meant to gate something.
- **Severity:** Low

### 8.7 `showsIndicators: false` instead of `.scrollIndicators(.hidden)`
- **Location:** `Modules/PhotoRPG/View/CarouselPhotoView.swift:11`.
- **Action:** `ScrollView(.horizontal) { ... }.scrollIndicators(.hidden)`.
- **Severity:** Low

### 8.8 `BattleRoundCard`'s unary-view/`Equatable` pattern — re-verified sound against this week's changes
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundCard.swift:43-129`, `BattleRoundList.swift:38-55`.
- **What:** The third audit verified this pattern was architecturally sound (not a papered-over symptom). Re-checked against the newly-added Table3D/BattleRound code this pass — no interaction between the two areas was found, and the pattern remains sound.
- **Action:** None required.
- **Severity:** Low (informational)

---

## 9. Dead code / duplication / refactor

### 9.1 Table3D platform duplication — partially fixed, and the unfixed part just absorbed two more rounds of hand-synced edits
- **Location:** `GameSetup.swift` (visionOS) vs `GamePortableSetup.swift` (iOS/macOS); `GameEquipment.swift` vs `GamePortableEntities.swift`.
- **What:** The two extractions the third audit predicted did land cleanly: `GameMetrics.swift` (20 lines) and `TableAssetFactory.swift` (62 lines) are new, `#if os()`-free, single-source-of-truth files used by both platform variants; `GameRenderer.swift`/`GamePortableRenderer.swift`'s prior duplication is also now fully resolved. **Not fixed:** `GameSetup.swift:117-247` (`syncPins`/`syncRooms`/`projection`) vs `GamePortableSetup.swift:41-196`, and `MapTableProjection` (`GameSetup.swift:311-402`, 92 lines, vs `GamePortableSetup.swift:237-334`, 98 lines) remain duplicated line-for-line (diffed directly — every hunk is whitespace/comment-only). `GameEquipment.swift:330-514` (`PinComponent`/`RoomComponent`/`PinPawn`) vs `GamePortableEntities.swift:353-594` is the same ~250-line duplicate, using the proven `GameTablePlatformColor` typealias seam for the one genuine platform difference.
- **Regression evidence:** the "game map move" commit added a new `viewportPan: CGPoint` parameter to `syncPins`/`syncRooms`/`projection`/`Board.updateMap`/`GameTableTextureRenderer.render`, applied by hand, separately, to both files (confirmed via `git show` on both). This is the second time since the finding was first raised that the "two copies must be edited in lockstep" cost has actually been paid, not just theorized.
- **Why:** ~450 lines of platform-agnostic math/entity code (zero platform-specific API use in the diffed functions) is still hand-maintained twice.
- **Action:** Extract `MapTableProjection`, `syncPins`/`syncRooms`/`projection`, and `PinPawn`/`PinComponent`/`RoomComponent`/`RoomHitArea` into shared files, following the pattern already proven for `GameMetrics`/`TableAssetFactory`.
- **Severity:** High

### 9.2 `ExportController` behavioral-drift bug — now fixed; remaining boilerplate downgraded
- **Location:** `Modules/CoreRPG/Controllable/ExportControllable.swift:140-149` (`exportingSimpleEntries`); all 6 "simple" modules' `Controller/ExportController.swift`.
- **What:** PhotoRPG's missing `guard item.specialCategory else { return [] }` (the third audit's concrete bug) is fixed — `PhotoRPG`/`PdfRPG`/`DiceRPG`/`GeneratorRPG`/`SpaceRPG` all now call a single shared `exportingSimpleEntries(itemIds:)`, which centralizes the guard with a doc comment citing this exact audit finding. The complex modules (`WeatherRPG`, `TableRPG`, `RuleRPG`) correctly use the shared `bfsExportResults`/`finalizeExportResults` helpers. What remains is purely structural per-module boilerplate (init + `hubControllable` accessor) with no behavioral-drift risk left, since all logic now delegates to the shared extension.
- **Action:** Optional: a protocol-extension default for the remaining boilerplate is still a nice-to-have, but no longer urgent.
- **Severity:** Low (downgraded from High — the actual bug is resolved)

### 9.3 `DetailFolderListView` boilerplate duplicated across 11 modules — still open
- **Location:** `Modules/{Adventure,Audio,Character,Dice,Map,Pdf,Photo,Rule,Space,Table,Weather}RPG/View/DetailFolderListView.swift`.
- **What:** Each wraps `ItemDetailRootView(...)` identically apart from generic type names and per-module `ViewerConfiguration` flags.
- **Action:** Extract into a generic-over-`Root`/`Model` shared view.
- **Severity:** Medium

### 9.4 `PlayerController.swift` split — still not done, third consecutive audit
- **Location:** `Modules/GameRPG/Controller/PlayerController.swift` — 3,915 lines (3,841 → 3,913 → 3,915 across three audits). Only 4 MARKs total; the largest block, `extension PlayerController { ... }` at lines 2114-3915 (~1,800 lines spanning nine per-module network-message domains), has zero internal MARK breakdown.
- **What:** No split has happened — confirmed via `find`, no `PlayerControllerModel.swift`/`PlayerController+ProxyDelegate.swift` files exist.
- **Action:** Execute the previously-scoped split along the existing `handleX`/`applyXList` per-module extension seams.
- **Severity:** Medium

### 9.5 `MapRPG/GameController.swift` — organization prerequisite now landed, split still pending
- **Location:** `Modules/MapRPG/Controller/GameController.swift` — 1,657 lines.
- **What:** The four MARK groupings the third audit explicitly recommended now exist verbatim (`Pin, room & pointer state` line 403, `Battle round` 763, `Map content sync` 1261, `Package & version metadata` 1349), matching the audit's suggested ranges almost exactly.
- **Action:** Now that the seams are marked, do the mechanical split into `+Pins.swift`/`+Battle.swift`/`+MapSync.swift`/`+Metadata.swift`.
- **Severity:** Low (downgraded from Medium — prerequisite landed)

### 9.6 `SharePlayJournalPublicationQueue.swift` — now adequately organized
- **Location:** `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift` — 1,089 lines, now with 10 MARK sections (up from 0), each of the file's 6 top-level types cleanly delineated.
- **What:** Satisfies the precondition the second audit set before any split was considered safe.
- **Action:** Optional: split along the now-visible seams if the file grows further.
- **Severity:** Low (downgraded from Medium)

### 9.7 `CLAUDE.md` documentation drift — partially fixed, new typos found this pass
- **Location:** `CLAUDE.md`.
- **What confirmed fixed:** the "Module Folder Sturcture" spurious-subfolder issue and the "Sturcture"/"manipluate"/"conurrency" typos from the first/third audits are gone.
- **New typos found this pass:** line 98 "imsges" → "images"; line 126 "TableTopKit" → "TabletopKit" (the real framework, confirmed via `import TabletopKit` in `GameSetup.swift:4`); line 81 lowercase "swiftUI" → "SwiftUI"; line 7 "a game mode there players can join" → "where players"; line 127 "Moduls"/"layoput" → "Modules"/"layout" (this specific pair was flagged as still-open from the third audit too).
- **Why:** `CLAUDE.md` is loaded into every future coding session; each uncaught typo compounds.
- **Action:** Fix all five in one pass.
- **Severity:** Medium

### 9.8 Live public protocol typo `SpotlightIndexerAtyribute`, propagated to 12 modules
- **Location:** `Modules/CoreRPG/Persistence/RpgSpotlightIndexerDelegate.swift:8` (`public protocol SpotlightIndexerAtyribute`), conformed to by all 12 modules' `Model/DataModel+Extensions.swift` (e.g. `Modules/TableRPG/Model/DataModel+Extensions.swift:36`).
- **What:** "Atyribute" for "Attribute" — a typo in a live, public, cross-module protocol name.
- **Action:** Rename to `SpotlightIndexerAttribute`, updating all 12 conformance sites in one pass.
- **Severity:** Low

### 9.9 CoreData relationship-accessor boilerplate duplicated across 12 `DataModel+Extensions.swift` files
- **Location:** `Modules/{Adventure,Audio,Character,Dice,Generator,Map,Pdf,Photo,Rule,Space,Table,Weather}RPG/Model/DataModel+Extensions.swift` — e.g. `TableRPG:10-34` vs `CharacterRPG:10-33` vs `SpaceRPG:10-34` (diffed directly): an identical `NSSortDescriptor(key: "index", ascending: true)` → `sortedArray(using:)` → `compactMap`-cast pattern, and an identical "find-by-uuid-or-create, `preconditionFailure` if no `managedObjectContext`" `entryOrNew` body, differing only by entity type.
- **Why:** ~24 lines × 12 modules ≈ 290 lines of identical logic; a fix to sort/fetch behavior requires 12 hand-edits.
- **Action:** Extract a generic helper (e.g. `static func sortedArray<T: NSManagedObject>(from set: Any?, sortKey: String) -> [T]` plus a generic `entryOrNew`) in `CoreRPG`, parameterized over the entity type.
- **Severity:** Medium

### 9.10 App Intents `*Entity.swift` — large duplication cluster outside any prior audit's scope, plus leftover Apple sample-code residue
- **Location:** `Modules/{Adventure,Audio,Character,Dice,Generator,Map,Pdf,Photo,Rule,Space,Table,Weather}RPG/Intent/*Entity.swift` (12 files, 144-211 lines each).
- **What:** The `*EntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery` conformance is structurally 100% identical across modules (diffed `PdfEntityQuery` vs `CharacterEntityQuery` — only type-name substitutions differ); the `Transferable`/`FileRepresentation(.pdf)` PDF-rendering block is likewise identical across at least 8 modules. **Separately:** `AdventureEntity.swift:60-68`, `CharacterEntity.swift:60-64`, `PhotoEntity.swift:60-68`, `MapEntity.swift:60-64` all contain a leftover commented-out line (`//    Image(landmark.landmark.backgroundImageName)`) verbatim from Apple's "Landmarks" App Intents sample — the closure parameter itself is still literally named `landmark` in two of these files, confirming un-adapted copy-paste. `SpaceEntity.swift:64` has an analogous leftover.
- **Why:** ~500+ lines of duplication (larger than the already-tracked `DetailFolderListView` cluster) in an area no prior audit examined (`Intent/` was out of scope for rounds 1-3).
- **Action:** Extract a generic `EntityQuery` default and a shared PDF `FileRepresentation` renderer into `CoreRPG`; delete the 4 leftover commented-out `landmark` lines and rename the 2 `landmark`-named parameters to `item`.
- **Severity:** Medium (duplication) / Low (sample-code residue)

### 9.11 Version-digest algorithm (SHA256-based, deliberately not `hashValue`) implemented three times
- **Location:** `Modules/CharacterRPG/Model/ValueModel.swift:368-380` (`StableValueVersion`) and `Modules/TableRPG/Model/TableModel.swift:280-292` (`StableTableVersion`) — byte-for-byte identical (diffed directly); plus `Modules/CharacterRPG/Controller/CharacterPackageVersion.swift:37-56` — a close structural variant (sorts its input array first, then the same body).
- **What:** All three independently reimplement `JSONEncoder(.sortedKeys)` → `SHA256.hash` → fold first 8 bytes → `Int(bitPattern:)` → non-zero coercion — the deliberate, correct fix for cross-device version determinism, just typed out three times.
- **Why:** Any future change to the digest algorithm must be applied in three places; two of the three are already provably identical, so extraction carries no behavioral risk.
- **Action:** Extract a single `CoreRPG` helper, e.g. `static func stableDigest<Value: Encodable>(_ value: Value) -> Int`.
- **Severity:** Medium

### 9.12 Additional oversized files (>500 lines) with no/minimal MARK organization, not previously flagged
- **Location:** `Modules/CoreRPG/Import/ExternalImport.swift` (1,003 lines, 0 MARKs); `Modules/MapRPG/Map/MapOverlayGeometry.swift` (815 lines, 0 MARKs, mixing 4 distinct geometry concerns); `Modules/CoreRPG/Tips/MasterRPGTips.swift` (868 lines, 0 MARKs, ~15 flat `Tip` structs); `Modules/CoreRPG/Controllable/ImportControllable.swift` (734 lines, 0 MARKs); `Modules/GeneratorRPG/Controller/GeneratorController.swift` (1,037 lines, 1 MARK); `Modules/GameRPG/Table3D/GameTableModel.swift` (964 lines, 2 MARKs, both toolbar-related — the bulk of its game/pin/room logic is unmarked); `Modules/GameRPG/Statistics/Model/GameStatisticsTypes.swift` (608 lines, 0 MARKs, ~26 data types — lower priority, pure data).
- **Action:** Add MARK sections following the pattern already validated on `MapRPG/GameController.swift` (§9.5) and `SharePlayJournalPublicationQueue.swift` (§9.6); consider a physical split for `ExternalImport.swift` and `MapOverlayGeometry.swift`.
- **Severity:** Low

### 9.13 Commented-out dead code beyond `#if false` (repo-wide sweep)
- **Location:** `Modules/CoreRPG/Links/LinkRegisterController.swift:258-260` (a fully commented-out function); `Modules/CoreRPG/Links/LinkReplaceController.swift:80` (one commented-out line inside a live `.map` closure); `Modules/PdfRPG/Pdf/PdfWrapperView.swift:149-151` (`handlePageChange` — an entirely commented-out body that's also never registered as an observer, i.e. dead in two ways at once); plus the Battle Round instances in §8.4.
- **Why:** Prior audits reported zero commented-out code found — these are small counterexamples, missed because they're short blocks rather than large `#if false` regions.
- **Action:** Delete all.
- **Severity:** Low

### 9.14 `RolePlayGameKit` — duplication and dead-code cluster (new scope this pass)
- **Location/What:** `SplitEditorNavigation.swift:95-133` vs `SplitVisionNavigation.swift:78-116` — byte-for-byte identical `tabView`/`contentView`/`splitWithDetail`/`menuView` (~45 lines). `RootRoute.swift:24-99` — the same one-case-per-module mapping written out three separate times in one file. `ValidateRepairView.swift:41-131` and `AppModel.swift:332-344` (`cleanDatabase`) — 22+11 hand-unrolled near-identical per-module blocks that should be a loop over an array. `DataBaseModel.swift:28-60` — `rpgModuleBundles` manually duplicated per `#if os(tvOS)` branch, plus a third, independently-maintained near-copy in `ShareExtensionDatabaseService.swift:88-110`. `TabbedNavigation.swift`/`SplitVisionNavigation.swift`/`SplitEditorNavigation.swift`/`SplitNavigation.swift` — the `0.8`s tab-switch mount delay hardcoded identically in 4 places despite `NavigationTiming.swift` already existing as the named-constant home for exactly this. **Dead code:** `SyncStateViewModifier.swift:24-74` and `AppModel.swift:359-367` (`loadFreePackages`) — zero call sites for either (confirmed via repo-wide grep). **Typos:** `AppModel.swift:287` "Maintanence" → "Maintenance"; `SettingsView.swift:145,150` "Becareful" → "Be careful" (user-facing, shipped copy — see §2).
- **Action:** Extract shared navigation-shell code; derive `RootRoute`'s three mappings from one source of truth; iterate arrays instead of hand-unrolling per-module loops; delete the two dead types; add a named constant to `NavigationTiming` for the mount delay; fix the typos.
- **Severity:** Medium (the "Becareful" user-facing typo and the navigation-shell duplication) / Low (the rest)

### 9.15 `WeatherRPG`/`RuleRPG` — dead code and duplication (new scope this pass)
- **Location/What:** `Modules/WeatherRPG/Weather/ResidueView.swift`/`Residue.swift`/`ResidueDrop.swift` (169 lines total) — confirmed unreachable: `WeatherViewer.swift:89-106` composes `StarsView`/`CloudsView`/`LightningView`/`StormView` but never `ResidueView`, and `Residue`/`ResidueDrop` have no other consumer. `WeatherRootFactory.swift:7` — the only module factory with an extra "Root" infix vs. 4 sibling modules' `<Module>Factory` convention. `Modules/WeatherRPG/Controller/LinkController.swift:62` — "reparing" → "repairing" typo in a log message. `Modules/WeatherRPG/Controller/EditController.swift:45-73` — 5 structurally identical `reset(...)` functions differing only by property. `Modules/WeatherRPG/View/WeatherThunderEditor.swift:91-95,112-116,133-137` — 3 near-identical `.onChange` blocks.
- **Action:** Delete the dead residue chain (or wire it into `WeatherViewer` if intended to ship — see §2); rename `WeatherRootFactory` → `WeatherFactory`; fix the typo; collapse the 5 `reset` functions into one generic `reset<T>(keyPath:value:itemId:message:)` helper.
- **Severity:** Medium (dead code, 169 unreachable lines) / Low (the rest)

### 9.16 `CharacterRPG`/`TableRPG` — duplication and dead code (new scope this pass)
- **Location/What:** `Modules/CharacterRPG/Model/Calculator.swift:65-155` — `divide`/`multi`/`minus`/`plus` are near-identical Regex-based operator handlers. `Modules/CharacterRPG/Controller/SearchController.swift` — ~300 lines of sync/async twin-pair duplication (`listModeCharacterResults`/`syncListModeCharacterResults`, etc.), differing only in `await item(for:)` vs. `itemSync(for:)`. **Dead code (confirmed zero call sites via repo-wide grep):** `ValueEntryModel.swift:113-121` (`nameText(otherValue:)`), `ItemController.swift:43-48` (`subchildren`), `TableEntryModel.swift:119-126` (`nameLinkText`/`contentLinkText`). `Modules/CharacterRPG/Controller/ExportController.swift:110` — log message says "Table" (copy-pasted from `TableRPG`'s sibling file) instead of "Character"/"Value" (see §2). Inconsistent recursion-depth magic numbers (10 vs. 25) across `GameController.swift`/`ItemController.swift`/`LinkController.swift`.
- **Action:** Parameterize `Calculator`'s 4 operator functions over the operator/closure; have the async `SearchController` variants call the sync ones after resolving needed data (or vice versa via a shared generic core); delete the 3 dead functions; fix the log message; name and reconcile the depth constants.
- **Severity:** Medium (`SearchController` duplication) / Low (the rest)

### 9.17 `AdventureRPG`/`PdfRPG`/`AudioRPG` — duplication and dead code (new scope this pass)
- **Location/What:** `Modules/AdventureRPG/Root/AdventureRootModel.swift:271-379` — `resetData()`/`save()`/`saveExternalImport()`/`validate()`/`startGame()`, each hand-unrolling the same 10-module sequence (the same "hand-unrolled per-module loop" pattern found independently in RolePlayGameKit, §9.14). `Modules/AudioRPG/Audio/MediaPlayerManager.swift:10-11` + `Controller/AudioController.swift:388-391` — `skipForward`/`skipBackward` remote-command cases that can never fire (both commands are explicitly disabled at setup, confirmed by reading the command-setup block). `AudioController.swift:131-165` vs. `Modules/AudioRPG/Controller/GameController.swift:157-195` — both independently implement "download → build `AVURLAsset`→ load duration → fall back to raw data" (see also §7.1). `Modules/AudioRPG/Controller/AudioPlayPauseButton.swift` — a SwiftUI view misplaced under `Controller/` instead of `Audio/`/`View/`.
- **Action:** Build a `[ItemRootControllable]` array once in `AdventureRootModel` and replace the 5 unrolled functions with a loop; remove the 2 dead remote-command cases or wire them up; consolidate the two `audioAsset` implementations; move the misplaced view file.
- **Severity:** Medium (`AdventureRootModel`'s 5 unrolled blocks — easy, low-risk to collapse) / Low (the rest)

### 9.18 `SpaceRPG`/`DiceRPG` — systemic naming defect and duplication (new scope this pass)
- **Location/What:** A systemic "role" vs. "roll" naming split across ~15 sites in DiceRPG's core rolling API (`RawDie.swift:8,12,58`, `DieModel.swift:142`, `RawDice.swift:71`, `RawDieCounter.swift:29`, `DiceModel.swift:13,510`, `DiceSnapshot.swift:65-66`, `DataController.swift:39,114-122`, `GameController.swift:319,343,365,578,589,592`, `DiceRootModel.swift:181-187`, `DiceSpaceModel.swift:89`) — the engine consistently spells its core verb "role" instead of "roll," while the *option type* is correctly spelled `RerollOption`/`rerollOptions`, so `DiceModel.swift:510`'s `reroleOptions:` parameter feeds a `rerollOptions` property two lines later with mismatched spelling. `ToggleDiceValue.swift:17` — "Ketpath" typo for "KeyPath," propagated consistently to 6 call sites (`CoupEditor.swift`, `FumbleEditor.swift`, `SpecialOptionEditor.swift`, `DiceOptionEditor.swift`). `CoupEditor.swift` vs `FumbleEditor.swift` — near-total structural duplication (~100 lines, diffed directly, differing only by terminology and one animation curve). `GameController.swift:435-462` vs `:477-501` — duplicate reroll/max-value-resolution and coup/fumble-resolution blocks. **Dead code:** `PositiveLabel.swift`/`NegativeLabel.swift` (33 lines each) — zero call sites; the checkmark/xmark pattern they implement is separately re-implemented inline in `ProConListView.swift:20-29,42-51` instead.
- **Why:** This is a systemic naming defect across the module's most central API surface, not an isolated typo — confirmed no functional bug results (just naming), but worth a dedicated rename pass given the breadth.
- **Action:** Rename `role`/`rolePercent`/`reroleOptions` → `roll`/`rollPercent`/`rerollOptions` throughout `DiceRPG`; rename `toggleKetpath` → `toggleKeyPath`; extract a generic `SpecialValueEditor` for `CoupEditor`/`FumbleEditor`; delete or wire up `PositiveLabel`/`NegativeLabel`.
- **Severity:** Low (cosmetic/naming, no functional impact — confirmed via direct read) — high-visibility given the breadth, worth prioritizing above other Low items.

---

## 10. Cross-cutting recommendations

1. **Extend rate-limiting to the new join-code pairing path before treating it as a closed security item.** §6.1's fix is real and substantive, but a 10,000-combination keyspace with zero connection-attempt throttling is the kind of gap that's cheap to close now and expensive to explain later. This is the highest-priority action item in this report specifically because it's the only remaining loose end on what was the app's sole Critical finding for three audit rounds running.
2. **Give the Table3D directory a dedicated stabilization pass before 3.0 ships.** Three of this report's four High-severity findings (§3.3, §5.1, §5.2) are all in the same ~4,650-line, week-old directory, all introduced by the same "each player has their own d20" feature. This isn't a sign the feature is poorly built — the underlying architecture (per-seat equipment IDs, tracked-task thumbnail loading, whole-type `@MainActor` isolation) is sound — but it is a sign that a fast-moving feature area benefits from exactly the kind of focused, full-file read this audit just gave it, and would benefit from one more before release.
3. **Finally execute the `PlayerController.swift` split, or explicitly decide not to.** §9.4 is the third consecutive audit to flag this with zero progress, and the file has grown in every one of those three intervals. If the team has decided the risk/effort tradeoff doesn't justify it, say so in the next audit rather than re-flagging a fourth time — that's a more honest signal than an unactioned recommendation on repeat.
4. **The "hand-unrolled per-module loop" pattern recurs at three different layers of the app** (§9.14 RolePlayGameKit's `ValidateRepairView`/`cleanDatabase`, §9.17 AdventureRPG's `AdventureRootModel`, and to a lesser extent §9.9's CoreData accessors) — all doing "the same operation, once per feature module, hand-typed." A single `[any ItemRootControllable]`/`[any ModuleDescriptor]`-style existential array, defined once in `CoreRPG` or `RolePlayGameKit`, would let all of these collapse to a `for` loop and make adding module #16 a one-line change instead of a N-site edit.
5. **The App Intents `Intent/` folder (§9.10) and the CoreData accessor layer (§9.9) are both large, previously-unexamined duplication clusters that mirror already-fixed patterns elsewhere** (`ExportController`, `DetailFolderListView`) almost exactly. Since the fix pattern for "per-module boilerplate with a protocol-extension default" is now proven and low-risk in this codebase (§9.2), applying the same recipe to these two newly-found clusters should be comparatively fast.

---

## 11. What was NOT audited

- Everything already covered and fixed by the first three audit passes was not re-derived from scratch — see `Docu/CODE_AUDIT_1.md`, `_2.md`, `_3.md` for that history. This pass re-verified items those reports left explicitly open, plus five independent fresh sweeps.
- Algorithmic correctness of RealityKit/3D-object rendering and TabletopKit synchronization semantics beyond concurrency/isolation and the specific bugs found in §5.1/§5.2/§3.3 — deeper geometry/physics correctness was not exhaustively re-derived.
- The Foundry VTT/LevelDB binary-format parsers (`FoundryZIPArchive.swift`, `FoundryLevelDBReader.swift`, `FoundrySystemPackageReader.swift`, `FoundryVTTArchiveSanitizer.swift`, `FoundryVTTImportReader.swift`, `UniversalVTTReader.swift`) were read for security hardening (zip-slip, decompression bombs, force-unwraps) and found clean — but their format-parsing *correctness* against real-world Foundry export variance was not tested.
- Xcode project build settings and scheme configuration beyond the deployment-target confirmation (uniform 26.0) and the three-platform clean-build verification.
- Third-party SPM dependency internals (`RPGTabletopGameContent`, `swift-snapshot-testing`, `swift-syntax`, `xctest-dynamic-overlay`, `swift-custom-dump`) — treated as black boxes.
- Test coverage — the 20+ test targets under `Tests/` got a light read for context (to avoid re-flagging known pre-existing failures) but no deep coverage review; the missing single-entry-table test case noted in §5.3 was found incidentally, not via a systematic coverage audit.
- Full accessibility audit (complete VoiceOver walkthrough, Dynamic Type stress testing, dark-mode contrast measurement) beyond the targeted checks in §8.1/§8.2 and the SwiftUI pass's grep-based house-rule sweep.
- Localization/String Catalog wording correctness (only the one user-facing typo in §2/§9.14 was caught incidentally).
- StoreKit/IAP configuration — not examined this pass (no `.storekit` file was flagged by any agent; not confirmed absent vs. simply out of scope).
- Performance profiling with Instruments — no `.trace` was recorded; §7 is static-analysis-only, same as all three prior passes.
- Exhaustive line-by-line reads of `PlayerController.swift` (3,915 lines) and `MasterController.swift` (2,665 lines) in full — both received targeted/sampled reads (message-handler switch statements, the specific line ranges cited in this report) rather than a complete read, consistent with prior audits' treatment of these files.
- CoreData migration correctness (schema versioning, migration mapping models) beyond the CloudKit-compliance schema check in §11's confirmed-clean items.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line. Every Critical/High finding below was personally re-opened and confirmed this pass.

- **§6.1** (Critical → Fixed) — confirmed `Modules/GameRPG/Network/GameSecurity.swift` no longer exists (`git show d7b5c301:...` shows the old 8-line file; current `HEAD` has no such path). Read `Modules/GameRPG/Network/GameJoinCodeModel.swift:1-94` in full — `randomCode()` (line 73-76) generates a zero-padded 4-digit string; `loadOrGenerate`/`isValidCode` (lines 78-89) validate and persist it. Traced call sites through `NWParameter+GameMaster.swift`, `MasterController.swift:498`, `PlayerController.swift:1109-1113` — the code is genuinely load-bearing. Independently, a second read of `ListenerManager.swift` (184 lines, full) and `ConnectionController.swift` (251 lines, full) confirmed zero rate-limiting/backoff/lockout logic anywhere in the connection path. `plutil`/`git diff` confirmed `aps-environment` absent from all 3 entitlements files.
- **§5.1** (High) — `Modules/GameRPG/Table3D/GameTableModel.swift:161-178`: confirmed `nextD20Index < d20Ids.count` gates the loop, and `Modules/GameRPG/Table3D/GameSetup.swift:99-104`: confirmed exactly 2 `Die20` (`firstD20`, `secondD20`) are allocated per seat, no more.
- **§5.2** (High) — `Modules/GameRPG/Table3D/GameEquipment.swift:277-283`: confirmed `PlayerSeat.seatPoses` is a fixed 3-element array. `:814-820`: confirmed `let playerSeatCount = PlayerSeat.seatPoses.count - 1` (= 2) and `let seatIndex = (localIndex % playerSeatCount) + 1` — worked the arithmetic directly: `localIndex` 0 and 2 both produce `seatIndex` 1.
- **§3.1** (High) — `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:112`: confirmed `DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.send(values: values) }` is still present, inside `resume(_:values:delay:)`'s `.auto` case.
- **§3.3** (High) — `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:2027-2034`: confirmed the comment ("This API is synchronous... spawning an obsolete, untracked task that reset() cannot cancel") sits directly above `Task { tabletopGame?.coordinateWithSession(groupSession) }`. `:733-736`: confirmed the sibling `setup(tabletopGame:gameTableModel:)` still calls the same API directly and synchronously — the contradiction is real, not a misreading of intent.
- **§9.1** (High) — confirmed via `git diff --stat d7b5c301..HEAD -- Modules/GameRPG/Table3D/` that `GameMetrics.swift` (+20 lines) and `TableAssetFactory.swift` (+62 lines) are new files; the dead-code agent's direct `diff` of `MapTableProjection` and `PinPawn`/`PinComponent`/`RoomComponent` between the platform-pair files confirmed the remaining duplication is real and current.
- **§7.1** (Medium-High) — `Modules/AudioRPG/Controller/AudioController.swift:131-165`: confirmed `UUID().uuidString` is used to name the temp-file destination at both copy sites (lines 143, 156), and a repo-wide grep for `removeItem` within `Modules/AudioRPG/` returned zero matches.

If any finding doesn't reproduce when you visit the line, flag the specific reference for re-investigation.
