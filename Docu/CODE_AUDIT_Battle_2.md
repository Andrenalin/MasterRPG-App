# MasterRPG Code Audit — BattleRound

Generated 2026-09-13. Scope: `Modules/GameRPG/BattleRound/` only — 30 Swift files, ~2,641 LOC (the SwiftUI views, screen model, and mutation controller for the live combat tracker). `Modules/MapRPG/BattleRound/` (the underlying `@Observable` data model) and `Modules/GameRPG/Network/`/`Master`/`Player`/`SharePlay` (the transport layer) are explicitly out of scope for this pass — see §11.

This is not a first-time audit of this code. `Docu/CODE_AUDIT_Battle_Round.md` (generated 2026-08-21) already covered this exact directory plus two adjacent subsystems, and per its own "§0 Fix status" every finding there was fixed, partially fixed, or deliberately deferred with documented reasoning — confirmed by re-reading the current code, not just trusting that document. Two commits have landed since (`2c70bb10` "fixed: game audit", and `fd8ed359` today, "fixed: battle chat env, and join code," which fixed a follow-on `Equatable`/`@Environment` bug in `BattleRoundCard`). This pass verifies that baseline is intact and looks for anything new.

A clean `xcodebuild build` of the `MasterRPG` scheme (iPhone 17 Pro Simulator, iOS 27.0) produced **zero real compiler warnings** — only two irrelevant `appintentsmetadataprocessor` notices about a missing `AppIntents.framework` dependency, unrelated to this scope. This matches the prior audit's own "zero warnings" baseline.

Three findings surfaced by the automated review agents were investigated and **dropped** after failing to reproduce against the actual code and data flow — see §12 for why. This report contains only findings personally verified against the cited lines.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

---

## 0. Fix status (2026-09-13)

All findings below were addressed in this pass, except §7.2 which was implemented despite its own "optional, don't do it speculatively" recommendation, per an explicit request to fix everything in this report. Verified via `xcodebuild build` (GameRPGTests scheme: zero warnings, zero errors) and `xcodebuild test` (all 18 directly relevant `GameRPGTests` cases — `BattleRoundConfiguredValueScanningTests`, `BattleRoundDiceAttributionTests`, `BattleRoundInlineCharacterTests`, `BattleRoundPresentationTests`, `BattleRoundValueRetentionTests` — and all 22 `MapRPGTests` cases in `BattleRoundControllerTests`/`BattleRoundModelTests` pass).

- **§4.1** — Fixed. `BattleRoundCharacterInspectorView.screenModel` is now a plain `let`.
- **§5.1** — Fixed. The Character-avatar drop destination now returns `controller.assignCharacter(...)`'s actual result.
- **§5.2** — Fixed. `applySettingEntry`/`useDroppedConfiguredValue` now return `Bool`, threaded through to `BattleRoundSettingsView`'s drop destination.
- **§7.1** — Fixed. `hitPointsValue` is computed once per `body` evaluation and reused for both the text and the color check.
- **§7.2** — Fixed (see note above). `BattleRankBadge` and `BattleAttackerDetails` are now `Equatable`, with `.equatable()` applied at all four call sites in the wide/compact card layouts.
- **§8.1** — Fixed. The card-level dead-attacker `.opacity(...0.58)` was removed; dimming is now owned solely by `BattleParticipantColumn`'s existing per-participant `0.62` rule, applied uniformly to attacker and defenders alike.
- **§8.2** — Fixed via documentation, not a code change: comparing an `@Environment`-sourced value inside `Equatable.==` would hit the exact same "never installed in the view tree" bug `fd8ed359` fixed for `cardLayout` — it would just always compare the environment default against itself. A doc comment now explains the exclusion and its accepted tradeoff, matching the standard this module already holds itself to.
- **§8.3** — Fixed the same way, for `nameMaxWidth` (`@ScaledMetric`) in `BattleParticipantColumn`.
- **§9.1** — Fixed. Extracted `presentInspectorOrSelection(id:)` and a pair of `resetCharacterSelectionState()`/`resetValueSelectionState()` helpers; also reused the latter two to de-duplicate the equivalent resets already present in `selectionDidChange`/`valueSelectionDidChange`.
- **§9.2** — Fixed. `presentValueSelection` now presents a meaningful, stable id (`PendingValueSelection.presentationId`) instead of a fresh `UUID()` every call.
- **§9.3** — Fixed. Extracted `BattleParticipantColumn.valueDropAction(kind:)`, used by both the Initiative and Hit Points drop destinations.
- **§9.4** — Fixed. Extracted `BattleRoundList.moveDestination(from:to:)`, used by both `moveEntry(at:by:)` and `reorder(_:over:)`.
- **§9.5** — Fixed. The `8`/`12` literals now use `BattleRoundSpacing.standard`/`.loose`; the `48`/`48` avatar size is now `BattleParticipantColumn.avatarSize`. The coincidental `0.18` opacity pair was left as-is, per the finding's own recommendation.
- **§9.6** — Fixed. Added `// MARK:` sections to `BattleRoundController.swift` for all six concerns (Lifecycle, Initiative, Turn progression, Combatant mutation, Rolls, Value-entry assignment, Broadcast).
- **§9.7** — Fixed. `moveEntries` now routes through `authorizedMapId`, matching every other mutating method in the file.
- **§9.8** — Fixed. Removed the redundant hand-written initializer from `BattleRoundCounterView`.

---

## 1. Executive summary

No Critical or High-severity issues were found. This directory remains in the clean state the prior audit left it in; what follows is incremental drift and a handful of small, genuine gaps a fresh pass turned up.

1. **[Medium] A dead attacker's avatar is dimmed almost twice as much as a dead defender's** — §8.1 — `BattleRoundCard.swift:95` and `BattleParticipantColumn.swift:192`. Two independent, unreconciled `isDead → opacity` rules compound only for attackers.
2. **[Medium] `BattleRoundController.swift` has grown to 400 lines with zero navigation aids** — §9.6 — six distinct concerns (lifecycle, initiative, turn progression, combatant mutation, rolls, value-entry assignment) share one undivided file.
3. **[Medium] The macOS-inspector-vs-iOS-sheet presentation branch is duplicated verbatim in two methods** — §9.1 — `BattleRoundScreenModel.swift:112-116,191-195`; a future third presentation path has no single place to update.
4. **[Medium] Dropping a Character onto a combatant's avatar always reports success, even when the assignment is silently rejected** — §5.1 — `BattleParticipantColumn.swift:99-104`. The sibling Initiative/HP drop targets two lines below correctly propagate their result; this one discards it.
5. **[Low] Two `Equatable` conformances added under the prior audit's performance fix exclude `@Environment`-sourced values from their own optimization** — §8.2, §8.3 — the same class of bug fixed today in `fd8ed359` for `cardLayout`, at lower severity since the worst case is a stale animation/Dynamic-Type width rather than misapplied game state.
6. **[Low] `moveEntries` is the one mutating method that doesn't route through `authorizedMapId`** — §9.7 — `BattleRoundController.swift:121-124` — contradicts the file's own doc comment claiming universal coverage.
7. **[Low] Unnecessary `@Bindable` on a property that's never bound** — §4.1 — `BattleRoundCharacterInspectorView.swift:10`.
8. **[Low] `hitPointsValue`'s link-resolution walk runs twice per `body` evaluation** — §7.1 — `BattleParticipantColumn.swift:136,143`.

---

## 2. Quick wins (≤30 min each)

- **Convert four raw `8`/two raw `12` literals to the existing `BattleRoundSpacing.standard`/`.loose` tokens** — `BattleParticipantColumn.swift:50`, `BattleRankBadge.swift:15`, `BattleRoundCompactCounter.swift:18`, `BattleRoundHeader.swift:22`, `BattleRoundCompactCounter.swift:17`, `BattleRoundHeader.swift:42` — these already match a named token sitting unused nearby. See §9.5.
- **Delete the hand-written `init(model:style:)` in `BattleRoundCounterView.swift:9-12`** — identical to the compiler-synthesized memberwise initializer for this two-property struct. See §9.8.
- **Change `@Bindable var screenModel` to a plain `let screenModel`** in `BattleRoundCharacterInspectorView.swift:10` — no `$screenModel...` binding is ever created. See §4.1.
- **Return the actual result from the two drop destinations that currently hard-code `return true`** — `BattleParticipantColumn.swift:99-104` (§5.1) and `BattleRoundSettingsView.swift:109-115` (§5.2, needs `useDroppedConfiguredValue` to return `Bool` first).
- **Extract a local `avatarSize` constant** for the `48`/`48` pair in `BattleParticipantColumn.swift:55,58` — same element, same file, written twice. See §9.5.
- **Route `moveEntries` through `authorizedMapId`** (or amend its doc comment) — `BattleRoundController.swift:121-124`. See §9.7.

---

## 3. Concurrency

_No findings._ A clean build produced zero concurrency warnings (matching the prior audit's baseline), and a fresh manual pass found no new anti-patterns: no `DispatchQueue.main.async`, `Task.detached`, `nonisolated(unsafe)`, or `@preconcurrency` anywhere in this directory; `unowned let root: GameRoot` in `BattleRoundController.swift:26` remains the only non-strong reference in scope, and nothing new captures `controller`/`root` unsafely across the three `@MainActor (BattleCombatant) -> Void` closures threaded through this directory's views.

---

## 4. API modernity

### 4.1 Unnecessary `@Bindable` on a property with no binding use
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundCharacterInspectorView.swift:10`
- **What:** `@Bindable var screenModel: BattleRoundScreenModel` is declared, but `body` only reads `screenModel.pendingValueSelection`/`.selectedCharacter`/`.selectedValue` — no `$screenModel...` binding is ever produced. `BattleRoundSettingsView.swift:11` shows the correct contrast: `let screenModel` is plain there, and only `settings` (which genuinely needs `$settings.initiativeOrder`) is `@Bindable`.
- **Why:** Misleading to a future reader — the wrapper implies a binding is needed or produced here, and it isn't.
- **Action:** Change to a plain `let screenModel: BattleRoundScreenModel`.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Character-avatar drop destination reports success unconditionally
- **Location:** `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift:99-104`
- **What:** `.battleLinkCharacterDropDestination { characters, _ in ... controller.assignCharacter(combatant.id, character.itemId); return true }` discards `assignCharacter`'s `@discardableResult Bool` and always returns `true`. The two value-drop destinations immediately below it (`:120-131` for Initiative, `:146-160` for Hit Points) correctly `return controller.assignValueEntry(...)`.
- **Why:** `assignCharacter` can genuinely fail (e.g. `authorizedMapId` becomes `nil` because `isMaster` flipped mid-session during a host handoff, or the underlying `assignBattleCharacter` rejects the id) — in that case SwiftUI still plays the drop's success feedback even though nothing was assigned, misleading the GM into believing the character link succeeded.
- **Action:** Change to `return controller.assignCharacter(combatant.id, character.itemId)`, matching the pattern already used two call sites below it in the same file.
- **Severity:** Medium

### 5.2 Configured-value drop destination has the same unconditional-success shape
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundSettingsView.swift:109-115`; `Modules/GameRPG/BattleRound/BattleRoundScreenModel.swift:162-174` (`useDroppedConfiguredValue`), `:198-210` (`applySettingEntry`)
- **What:** The drop closure calls `screenModel.useDroppedConfiguredValue(...)` — a `Void`-returning method whose internal `applySettingEntry` can silently no-op via its own `guard let entry = ... else { return }` — then unconditionally `return true`.
- **Why:** Same class of misleading success feedback as §5.1, here for the Settings panel's "drop a value to define a named pattern" flow.
- **Action:** Have `applySettingEntry`/`useDroppedConfiguredValue` return a `Bool` reflecting whether the entry was actually found and applied, and thread that through to the drop closure's return value.
- **Severity:** Low

---

## 6. Security

_No new findings._ The prior audit's §6.1 fix (`recordDiceResult`'s ownership check before trusting a network-payload-claimed `resultCategory`) was re-traced end to end for this pass: `BattleRoundController.swift:247-292`'s `authorizedCharacterCombatant` gate correctly requires `isMaster || (combatant.isPlayer && (pinId == senderId || pin.players.contains(senderId)))` before a claimed combatant id can override the `senderId`-derived fallback, and the final `combatantId` resolution (`:284-286`) can only reach `model.masterRollRecipientCombatantId` when `isMaster` is `true` — never from an unauthenticated payload field. No regression found. See §12 for the verification trail.

---

## 7. Performance

### 7.1 `hitPointsValue`'s link-resolution walk runs twice per render
- **Location:** `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift:133-144` (used at `:136` and `:143`)
- **What:** The `private var hitPointsValue: String?` computed property — which calls `gameEntryDisplayValue(characterId:entryId:)`, the same link-resolution walk the prior audit's §7.1 already flagged as potentially expensive for chained formula entries — is referenced twice within one `body` evaluation: once for the displayed text, once for the `foregroundStyle` nil-check.
- **Why:** Every time this view's `body` actually runs (i.e. whenever `.equatable()` doesn't skip it), the resolution runs twice for no functional benefit, compounding with roster size and formula complexity.
- **Action:** Compute `let hp = hitPointsValue` once near the top of `body` and reuse it for both the text and the `foregroundStyle` condition.
- **Severity:** Low

### 7.2 `BattleRankBadge`/`BattleAttackerDetails` sit one level below the existing `Equatable` optimization
- **Location:** `Modules/GameRPG/BattleRound/BattleRankBadge.swift` (whole file), `BattleAttackerDetails.swift` (whole file); call sites in `BattleRoundWideCardLayout.swift:11-14,27-31`, `BattleRoundCompactCardLayout.swift:12-15,28-32`
- **What:** Following the same reasoning that justified `BattleParticipantColumn`'s `Equatable` conformance, these two sibling leaf views — rendered inside the same per-tick card layouts — have no `Equatable`/`.equatable()` of their own.
- **Why:** Lower-impact than the original finding: `BattleRoundCard` already gates the whole subtree with its own `.equatable()`, so this only matters when the card's `presentation` changed for an unrelated reason (e.g. one defender's HP) and the identical attacker rank/details still get rebuilt.
- **Action:** Optional — only worth adding if a profiling trace shows it matters; not worth doing speculatively given the likely size of the win.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 A dead attacker's row is dimmed by two independent, unreconciled rules
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundCard.swift:95`; `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift:192`
- **What:** `BattleRoundCard` dims the whole card group to `.opacity(presentation.attacker.combatant.isDead ? 0.58 : 1)`, and `BattleParticipantColumn` independently dims that same participant's own column to `.opacity(combatant.isDead ? 0.62 : 1)`. These compound multiplicatively — only when the *attacker* is dead (≈0.36 effective opacity) — while a dead *defender* only ever gets the single `0.62` dim from its own column, since the card-level rule only reads `presentation.attacker`'s state.
- **Why:** Two different, unreconciled magic numbers implementing "dead → dim" at two view-tree levels produce a visibly inconsistent result: a dead attacker's row is markedly darker than a dead defender's, which reads as a bug rather than a deliberate visual distinction.
- **Action:** Pick one owner for "dead" dimming — either drop the card-level `.opacity(...0.58)` (each participant already dims itself) or drop the per-column dimming for the attacker case — and use one named constant for whichever dim factor remains.
- **Severity:** Medium

### 8.2 `BattleRoundCard`'s `Equatable` excludes the Environment value it reads for animation
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundCard.swift:49,96-99,149-153`
- **What:** `accessibilityReduceMotion` is read via `@Environment` in `body` to gate `.animation(...)`, but is not part of `Equatable.==` (which compares only `presentation`, `controller.root`, `cardLayout`).
- **Why:** `.equatable()` (applied at `BattleRoundList.swift:47`) skips re-invoking `body` when `==` reports equal. Since Reduce Motion isn't part of that comparison, toggling the system Reduce Motion setting while a card's other compared state is unchanged can leave its `.animation` modifier stuck at the value captured at the last real re-render — the same "Environment value not reflected because `.equatable()` short-circuits" mechanism `fd8ed359` fixed for `cardLayout` today, here manifesting as a missed update rather than a silently-defaulted read, and at much lower practical impact (a cosmetic animation lag, not misapplied game state).
- **Action:** Either include `accessibilityReduceMotion` in `==`, or explicitly note (as was done for `cardLayout`) that this lag is accepted.
- **Severity:** Low

### 8.3 `BattleParticipantColumn`'s `Equatable` excludes its own Dynamic-Type-driven width
- **Location:** `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift:23,46,261-277`
- **What:** `@ScaledMetric private var nameMaxWidth` (driven by `\.sizeCategory`) is used in `body` (line 46) but is not part of `Equatable.==` (lines 271-277), and this view is rendered `.equatable()` at every call site (`BattleDefenderStrip.swift:41`, `BattleRoundWideCardLayout.swift:26`, `BattleRoundCompactCardLayout.swift:27`).
- **Why:** Same mechanism as §8.2 — a system Dynamic Type change while a participant's other compared state is unchanged risks the name-truncation width not updating until some unrelated field forces a real diff.
- **Action:** Decide and document, as was done for `cardLayout`, whether size-category should factor into equality, or that the lag is acceptable.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

This directory remains, per the prior audit's own characterization, unusually clean: zero `#if false` blocks, zero commented-out code, zero `TODO`/`FIXME`/`HACK`/`XXX`/`#warning` markers, zero raw `print()`/`NSLog()` calls, and — re-confirmed this pass by cross-checking every public/internal symbol against callers in `GameRPG/GameViews/`, `GameRPG/Root/`, `MapRPG/Controller/GameController+Battle.swift`, and the relevant test targets — zero unreferenced symbols.

### 9.1 macOS-inspector-vs-sheet presentation branch duplicated verbatim
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundScreenModel.swift:112-116` (`showCharacterSheet`), `:191-195` (`presentValueSelection`)
- **What:** Both methods end with the identical `#if os(macOS) isInspectorPresented = true #else presentation = .selection(...) #endif` branch, and both independently reset the "other" selection model's state just above it (`pendingCharacterCombatantId`/`selectedCharacter` vs. `pendingValueSelection`/`selectedValue`).
- **Why:** A future third presentation path, or a platform-behavior change, has no single place to update; the two copies can silently drift apart.
- **Action:** Extract a private `presentInspectorOrSelection(id:)` for the platform branch, and a small `resetOtherSelectionState()` helper for the paired resets.
- **Severity:** Medium

### 9.2 The only two call sites of `.selection`'s associated id use inconsistent semantics
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundScreenModel.swift:115` vs. `:194`
- **What:** `showCharacterSheet` presents `.selection(combatant.id)` — a stable, meaningful id — while `presentValueSelection` presents `.selection(UUID())` — a fresh random id every call.
- **Why:** Confusing for a future reader trying to understand what `.selection`'s associated value represents; the random id also forces `.sheet(item:)` to treat every `presentValueSelection` call as a brand-new item identity even when re-invoked for the same combatant/kind.
- **Action:** Use a consistent, meaningful id once the two call sites are merged per §9.1.
- **Severity:** Low

### 9.3 Near-identical drop-destination closures for Initiative and Hit Points
- **Location:** `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift:119-131` vs. `:145-160`
- **What:** The two `.battleLinkCharacterDropDestination` closures are byte-identical apart from `kind: .initiative` vs. `kind: .hitPoints`.
- **Why:** A future fix to one copy's guard logic could easily be missed in the other.
- **Action:** Extract a small private `View` helper (e.g. a method taking `kind: BattleValueKind` and building the drop destination from the enclosing `combatant`/`controller`) and use it at both sites.
- **Severity:** Low

### 9.4 Reorder-destination index math duplicated between drag and accessibility paths
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundList.swift:83-88` (`moveEntry(at:by:)`) vs. `:90-104` (`reorder(_:over:)`)
- **What:** Both independently compute the same "insertion destination needs +1 when moving forward" arithmetic to translate a source/target pair into the destination index `IndexSet`-based moves expect (verified correct by hand-tracing both the "move earlier" and "move later" cases against `BattleRoundModel.moveEntries`'s `entries.move(fromOffsets:toOffset:)` semantics — no bug in the math itself, just duplication).
- **Why:** Subtle off-by-one-prone logic duplicated between the drag-based and accessibility-action-based reorder paths added in the same recent accessibility fix; a future correction to one is easy to miss in the other.
- **Action:** Extract `private static func moveDestination(from: Int, to: Int) -> Int` and use it in both places.
- **Severity:** Low

### 9.5 Magic constants that already have (or warrant) a shared token
- Raw `8` matching `BattleRoundSpacing.standard` — `BattleParticipantColumn.swift:50`, `BattleRankBadge.swift:15`, `BattleRoundCompactCounter.swift:18`, `BattleRoundHeader.swift:22`.
- Raw `12` matching `BattleRoundSpacing.loose` — `BattleRoundCompactCounter.swift:17`, `BattleRoundHeader.swift:42`.
- The `48`/`48` avatar size written twice in the same view — `BattleParticipantColumn.swift:55,58`.
- **Action:** Replace the spacing literals with the existing tokens; extract a local `avatarSize` constant for the avatar-size pair. (A stray `0.18` opacity literal repeating between `BattleRoundAnnouncementCounter.swift:31` and `BattleRollResults.swift:19` was also noted but is likely coincidental — not worth a token unless a third occurrence appears.)
- **Severity:** Low

### 9.6 `BattleRoundController.swift` has grown into oversized-file territory
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundController.swift` (400 lines)
- **What:** Now the largest file in the directory, with zero `// MARK:` section dividers across six distinguishable concerns: lifecycle (`start`/`end`), initiative (`setInitiative`/`adjustInitiative`/`setInitiativeOrder`/`moveEntries`), turn progression (`activateAttacker`/`nextAttacker`/`nextRound`), combatant mutation (`addCombatant`/`removeCombatant`/`setDead`/`assignCharacter`), rolls (`addRoll`/`selectRollRecipient`/`recordDiceResult`), value-entry assignment (`assignValueEntry`/`refreshConfiguredValues`), and broadcast (`broadcast(mapId:)`).
- **Why:** Each method is individually well-documented, but there's no way to jump to a concern in the outline view, and it's trending toward the kind of unnavigable growth the prior audit flagged as High severity for `RPGSharePlayController.swift` (albeit at a fraction of that file's size).
- **Action:** At minimum, add `// MARK:` sections for the six groups above. If it keeps growing, split into `BattleRoundController+Turns.swift` (initiative/turn progression) and `BattleRoundController+Combatants.swift` (combatant mutation/rolls/value-entry), keeping lifecycle + broadcast + `authorizedMapId` in the main file.
- **Severity:** Medium

`BattleParticipantColumn.swift` (299 lines) is the second-largest file and worth watching, but is a single cohesive view with no obviously separable second responsibility — no split warranted today.

### 9.7 `moveEntries` bypasses the file's own `authorizedMapId` invariant
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundController.swift:36-38,121-124`
- **What:** `moveEntries(_:_:)` checks `root.gameModel.gameConfig.isMaster` directly instead of going through `authorizedMapId`, which every other mutating method in the file now uses.
- **Why:** `authorizedMapId`'s own doc comment (lines 32-38) states "every mutating method below collapses its own `isMaster`/`mapId` guard to this single computed property so a future method can't skip the authorization check by omission" — `moveEntries` is the one exception, so the claim is currently inaccurate. (`moveEntries` doesn't broadcast over the network either, but that's correct as-is: the turn-order array isn't part of `BattleRoundNetworkState`'s wire payload at all — see §12 — so there's nothing to resync from this specific mutation, unlike the doc-comment risk here.)
- **Action:** Either route `moveEntries` through `authorizedMapId` (ignoring the unused `mapId`) for consistency, or amend the doc comment to note this documented exception.
- **Severity:** Low

### 9.8 Hand-written initializer identical to the synthesized one
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundCounterView.swift:9-12`
- **What:** `init(model:style:)` does nothing but assign both parameters to identically-named stored `let` properties — exactly what Swift's synthesized memberwise initializer already provides for this plain two-property struct.
- **Why:** Pure boilerplate with no behavioral difference; one more place to keep in sync for no benefit.
- **Action:** Delete the explicit initializer.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **The `@Environment`-excluded-from-`Equatable` bug class deserves a one-line convention, not just a one-off fix.** `fd8ed359` fixed it for `cardLayout` by making it a stored property; §8.2 and §8.3 show the same shape recurring for `accessibilityReduceMotion` and `nameMaxWidth` at lower stakes. Worth a short note in this module's contributing guide: any `@Environment`-read value a hot view depends on for its rendered output either belongs in `Equatable.==` or needs an explicit comment saying why it's deliberately excluded — so the next one is a documented decision, not a rediscovery.
2. **The macOS-inspector/iOS-sheet duplication (§9.1) and its id-semantics drift (§9.2) are one root cause.** Fixing the extraction in §9.1 is also the natural place to settle §9.2's inconsistency, rather than treating them as two separate follow-ups.
3. **Drop destinations that discard a `Bool` result (§5.1, §5.2) are a small but repeatable pattern** — worth a quick grep across the rest of the module the next time this file set is touched, to confirm no third instance exists outside this scope.
4. **Continue the prior audit's file-splitting momentum into this file.** `BattleRoundController.swift` (§9.6) is the one file in this directory now large enough to warrant the same `// MARK:`-first, split-if-it-keeps-growing treatment the prior audit already applied successfully to five other files in this codebase.

---

## 11. What was NOT audited

- `Modules/MapRPG/BattleRound/` (the `BattleRoundModel`/`BattleRoundTypes`/`BattleRoundCardPresentation` data layer this directory's views and controller read from) — treated as an interface, read only where needed to verify a specific claim (e.g. `BattleRoundNetworkState`'s field list, `moveEntries`'s underlying implementation). Not audited for its own correctness/duplication/concurrency.
- `Modules/GameRPG/Network/`, `Master/`, `Player/`, `SharePlay/` — the transport layer `BattleRoundController.broadcast(mapId:)` ultimately calls into. Already covered by `Docu/CODE_AUDIT_Battle_Round.md`'s 2026-08-21 pass; not re-audited here.
- `Modules/MapRPG/Controller/GameController+Battle.swift` and the wider `GameController*` family — same as above, out of scope for this pass; consulted read-only to verify specific cross-boundary claims (e.g. `networkBattleRoundUpdate`'s payload shape).
- Every other `GameRPG` subdirectory (`Statistics/`, `GameCenter/`, `ExternalScreen/`, `SetupViews/`, `Search/`, `Browser/`, `Table3D/`, `Root/`, the wider `GameViews/`) beyond the specific call sites cited for verification (`BattleRoundWindowView.swift`, `BattleRoundGameChrome.swift`, etc.).
- Test coverage depth. `Tests/GameRPGTests/BattleRound*.swift` and `Tests/MapRPGTests/BattleRoundControllerTests.swift`/`BattleRoundModelTests.swift` exist and were used only as cross-reference to rule out dead code — no line-coverage or test-quality review performed.
- Localization string wording (all strings observed correctly use `bundle: .module`; wording itself wasn't assessed).
- Instruments profiling/hitches — §7's findings are based on static code reading, not a captured trace.
- Other platforms' (MasterMac, MasterTV) target-specific entitlements beyond what's visible inline as `#if os(...)` in the files reviewed.
- CoreData/CloudKit sync itself — out of scope; this audit covers only the live in-session view/controller code.

---

## 12. Verification

- **§6 (re-verification, no finding)** — open `Modules/GameRPG/BattleRound/BattleRoundController.swift`, lines 247-292. Confirm `authorizedCharacterCombatant` (line 276-283) gates `characterCombatant` behind `isMaster || (combatant.isPlayer && (combatant.pinId == senderId || combatant.pin.players.contains(senderId)))` before it can be used, and that the final `combatantId` (line 284-286) only reaches `model.masterRollRecipientCombatantId` when `isMaster` is `true`. The prior audit's §6.1 fix is intact.
- **§8.2/§8.3 (re-verification of the `fd8ed359` fix, no finding beyond what's listed)** — open `BattleRoundCard.swift` lines 41-153 and confirm `cardLayout` is now a plain stored `let` (not `@Environment`), compared directly in `Equatable.==` at line 152, threaded explicitly through `BattleRoundList.swift:42` and both `#Preview`s; a repo-wide grep for `battleRoundCardLayout` returns no remaining reference to the removed `EnvironmentValues` extension.
- **§9.7 note (why no broadcast is needed for `moveEntries`)** — open `Modules/MapRPG/BattleRound/BattleRoundTypes.swift`, lines 107-127 (`BattleRoundNetworkState`). Confirm its fields are only `mapId`, `isRunning`, `roundCounter`, `activePinId`, `sequence` — the `entries` array (turn order) is never part of the wire payload. Cross-check `Modules/GameRPG/GameViews/BattleRoundWindowView.swift:51-61`: the entire `BattleRoundView` (including the reorderable list) is gated `if root.gameModel.gameConfig.isMaster`, with a `ContentUnavailableView` for anyone else — players never see this screen at all. This is why `moveEntries` not broadcasting is correct as-is, not a bug.

### Findings investigated and dropped

Two claims from the automated review pass were traced end-to-end against the actual code and dropped as not reproducible, per this audit's own verification discipline:

- **"`moveEntries` never broadcasts its reorder over the network, desyncing players' turn-order UI."** Refuted: per the note above, the turn-order array isn't part of any network message this app sends — only `roundCounter`/`activePinId`/`isRunning`/`sequence` are, and those are unaffected by manually reordering the display list. The screen this reordering happens on is master-only in the first place (`BattleRoundWindowView.swift:23,51-61`), so there's no player-facing state to desync.
- **"A stale `pendingCharacterCombatantId`/`pendingValueSelection` can silently apply to the wrong combatant if the macOS inspector is closed and reopened via its toolbar button without completing a selection."** Refuted by tracing the actual tap-handling path: `BattleRoundCharacterInspectorView` renders its list with `type: .inspector`, and `InspectorRowView.swift:139-145`'s `isSelectionActive` — which gates whether `SelectListItemViewModifier`'s tap-`Button` (the only thing that calls `selectionModel.toggleSelection`, per `SelectItemModifier.swift:26-31`) renders at all — is `true` only for `type == .selection || type == .selectionInline`. In `.inspector` mode, tapping a row never calls `toggleSelection`, so `screenModel.selectedCharacter.selection` cannot change via the macOS inspector at all; the in-code comment in `BattleRoundCharacterInspectorView.swift:13-17` ("tap no longer assigns anything") is accurate. The only two places that ever set `presentation = .selection(...)` (`showCharacterSheet`, `presentValueSelection`) both freshly (re)set the corresponding pending-selection state in the same call, so no stale-application path exists on iOS/visionOS either.

If any finding here doesn't reproduce when you visit the line, flag it and it'll be re-investigated.
