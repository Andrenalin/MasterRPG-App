# MasterRPG Code Audit — Battle Round

Generated 2026-10-11. Scope: the Battle Round feature only — 48 Swift files, ~5,200 lines: `Modules/GameRPG/BattleRound/` (34 files), `Modules/MapRPG/BattleRound/` (9 files), `Modules/GameRPG/GameViews/BattleRound*.swift` (3 files), `Modules/MapRPG/Controller/GameController+Battle.swift` and `+BattleSync.swift`, plus the window plumbing it depends on (`Sources/MasterRPG/Window/WindowUtilityList.swift`, `Modules/CoreRPG/ScenesManager/`). Focus requested: the macOS window ("could not close due to an internal crash, app kept running") and the missing `skull.fill` symbol.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action. The audit itself changed no code; the findings were fixed afterwards on 2026-10-11 — **§13 lists the status of each one.** Line numbers in §1–§12 are those of the audited code, before the fixes.

**Evidence used besides reading the code**

- **macOS build** (`MasterMac`, Debug, in-scope files touched to force recompilation): `BUILD SUCCEEDED`, **zero Swift compiler warnings** in the audited files.
- **Unified system log, last 30 days, process `MasterRPG`**: three caught AppKit exceptions and repeated `skull.fill` faults. Quoted in §12.
- **Live Xcode console of the running Mac session** (PID 56231, started 18:13): `_printChanges` output and `Logger` lines, used for the observation and performance findings.
- **System symbol catalog** (`CoreGlyphs.bundle/name_availability.plist`, macOS 27.0.1, 9,524 symbols): every SF Symbol literal in scope checked against it.

Each finding is marked **verified** (read the lines or saw it in a log) or **inferred** (follows from the code, not observed).

---

## 1. Executive summary

Top items to address, in priority order:

1. **[High] A caught AppKit gesture assertion leaves a window deaf to clicks — this is the "internal crash"** — §5.1 — `Modules/GameRPG/BattleRound/BattleRoundHeaderActions.swift:20,46`. Logged twice on 2026-10-10; AppKit then prints "Ignoring all remaining gesture recognizers", so buttons such as End stop working and the window cannot be closed from its own controls.
2. **[High] `skull.fill` is not an SF Symbol** — §5.2 — `Modules/GameRPG/BattleRound/BattleRoundAttackerActions.swift:77`. The "Mark Dead" context-menu item renders without an icon and logs a SwiftUI fault on every menu build.
3. **[High] A pin highlighted during the surprise round can never get its own turn** — §5.4 — `Modules/MapRPG/BattleRound/BattleRoundModel+Turns.swift:230-233`. It is appended to the roster without a turn entry, after which "add to battle" is rejected; there is no way out except ending the battle.
4. **[High] Initiative order chosen before the first battle is discarded and reverted** — §5.3 — `Modules/GameRPG/BattleRound/BattleRoundController.swift:70,159-167`. The picker saves the setting, the controller refuses it, and Start then overwrites the saved setting with the old value.
5. **[Medium] On macOS a second, invisible Battle Round UI is always mounted in the game window** — §8.2 — `Modules/GameRPG/GameViews/OverlayMasterTabBar.swift:20`. Doubles the work, puts hidden text fields and glass buttons into the main window, and widens the surface for §5.1.
6. **[Medium] `cardPresentations` writes observed state from inside a getter that view bodies call** — §8.1 — `Modules/MapRPG/BattleRound/BattleRoundModel.swift:61`. The live console shows views being invalidated by `cardPresentationsCache`.
7. **[Medium] "Mark Dead" from the map or the 3D table skips the battle bookkeeping** — §5.6 — `Modules/MapRPG/Controller/GameController+Pins.swift:337-341`. The battle card keeps showing the combatant alive and it stays in every attacker's target list.
8. **[Medium] Removing the active attacker sends the turn back to the top of the order** — §5.5 — `Modules/MapRPG/BattleRound/BattleRoundModel+Roster.swift:37-40`.
9. **[Medium] The macOS inspector gets stuck in the last "choose value" mode** — §5.8 — `Modules/GameRPG/BattleRound/BattleRoundScreenModel.swift:36-37,211-217`.
10. **[Medium] Header actions should live in the macOS window toolbar** — §8.4 — `Modules/GameRPG/GameViews/BattleRoundWindowView.swift:35-49`. Correct for the platform and the cleanest mitigation for §5.1.

---

## 2. Quick wins (≤30 min each)

- **Replace `skull.fill`** with the symbol the name row already uses for the same action (`figure.fall`), from one shared constant — `BattleRoundAttackerActions.swift:77`, `BattleParticipantNameRow.swift:45`. §5.2, §9.9.
- **Mark `cardPresentationsCache` as not observed** — `BattleRoundModel.swift:61`. One annotation; removes the invalidation loop in §8.1. The two private index dictionaries at `:63-64` qualify too.
- **Do not mount `BattleRoundSideOverlay` on macOS** — `OverlayMasterTabBar.swift:20`. §8.2.
- **Use a non-glass button style for the header actions on macOS** as an immediate mitigation — `BattleRoundHeaderActions.swift:20,46`. §5.1.
- **Feed Start from the saved setting, not from the model** — `BattleRoundController.swift:70`. §5.3.
- **Delete the unused parameters** listed in §9.2 (six of them).
- **Delete the no-op `synchronize` after `end()`** — `GameController+Battle.swift:154`. §9.5.
- **Fix the comment that contradicts the code** — `GameController+BattleSync.swift:86-94` and `BattleRoundView.swift:46-48`. §9.6.
- **Pick a different symbol for the inspector button** than `scope` — `BattleRoundWindowView.swift:45`. §8.8.

---

## 3. Concurrency

The macOS build emitted no concurrency warnings for the audited files. Every model in scope is `@MainActor @Observable`; controllers are `@MainActor` structs; there is no GCD, no `Task.detached`, no `nonisolated(unsafe)`, no `@unchecked Sendable` and no continuation in scope. The only task is the `.task(id:)` announcement timer in `BattleRoundGameChrome.swift:34-53`, which is cancelled correctly.

### 3.1 The battle window is dismissed synchronously inside the update that ends the battle
- **Location:** `Modules/GameRPG/GameViews/BattleRoundWindowView.swift:26-29`
- **What:** `onChange(of: isRunning)` calls `scenesManager.dismissWindow(.battleRound)` directly, while SwiftUI is still applying the transaction that swaps the card list for the empty state (per-card move transitions, possibly an open inspector or inline sheet). **Inferred** — no log line ties an exception to this path.
- **Why:** Tearing down a window from inside its own view update is the same shape as the TabletopKit crash already fixed in this project by deferring to a main-actor task; AppKit is least tolerant of it when the trigger is a click inside the window being closed (the End button).
- **Action:** Defer the dismissal by one main-actor turn, and move the "battle ended → close" rule out of the view into the screen model so it can be tested.
- **Severity:** Medium

### 3.2 `unowned` root inside a `Sendable` controller that views capture
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundController.swift:16,26`
- **What:** The controller holds `unowned let root: GameRoot` and is copied into every card, closure and the screen-model call path. **Verified.**
- **Why:** The comment's assumption ("reachable only while `root` is alive") holds today because `GameRoot` lives for the app's lifetime; if a root is ever replaced (store switch, preview, test) any retained view closure traps instead of leaking.
- **Action:** Keep it, but add a test that a `GameRoot` can be released with a Battle Round window open, or switch to `weak` with early returns at the mutation entry points.
- **Severity:** Low

---

## 4. API modernity

No deprecated API, no legacy observation, no `foregroundColor`, `cornerRadius()`, `onTapGesture`, `GeometryReader`, one-parameter `onChange`, `DispatchQueue` or `String(format:)` in scope.

### 4.1 Shape struct instances where the project rule asks for static members
- **Location:** `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift:50,64`; `Modules/GameRPG/BattleRound/BattleRoundCard.swift:99-102`
- **What:** `Circle()` and `UnevenRoundedRectangle(...)` are instantiated directly. **Verified.**
- **Why:** `CLAUDE.md` asks for static member lookup (`.circle`, `.rect(...)`) where possible.
- **Action:** Use the static shape members; the leading bar can be a `.rect(topLeadingRadius:bottomLeadingRadius:)` fill.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Caught AppKit gesture assertion disables a window's controls ("internal crash, app not crashing")
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundHeaderActions.swift:20,46` (interactive glass buttons); `Modules/GameRPG/BattleRound/BattleRoundList.swift:50-53` (whole-card drag source and drop target); `Modules/GameRPG/BattleRound/BattleRoundCard.swift:125-133` (context menu); `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift:87-90,106,128` (three nested drop targets per participant); `Modules/GameRPG/BattleRound/BattleRollResults.swift:23-45` and `BattleDefenderStrip.swift:25-43` (nested horizontal scroll views)
- **What:** On 2026-10-10 at 21:09:14 and 23:46:40 AppKit raised `NSInternalInconsistencyException: Unexpected equal node indexes` (`NSGestureRecognizerContainer.m:158`) while routing a mouse event (`-[NSWindow sendEvent:]` → `_routeMouseEventToActiveGestureRecognizers:` → `NSGestureRecognizerContainerCompare`). The exception was caught, and two seconds later AppKit logged "Stuck gesture recognizers detected" followed by "Ignoring all remaining gesture recognizers. This is a bug and you should file a radar." The two stuck recognizers sit on the same navigation-pane hosting view: one is SwiftUI's `FlexInteraction` recognizer, the other SwiftUI's general gesture recognizer with three targets. **Verified** from the log. `FlexInteraction` is the Liquid Glass interactive effect (AppKit's SDK exports `NSGlassEffectView.effectInteractiveSources: SwiftUI.FlexInteraction.Sources`). **Inferred:** that the affected window was Battle Round and which click triggered it — the second occurrence is in the same process that logged the `skull.fill` fault 92 seconds later, i.e. the Battle Round card menu was in use.
- **Why:** After AppKit starts ignoring a window's gesture recognizers, SwiftUI buttons in it no longer respond. End is one of the two glass buttons and is the control that closes this window (via §3.1), so the visible symptom is a window that will not close while the app stays alive. The root assertion is in the system (macOS 27.0.1), but this screen stacks more gesture sources into one hosting view than any other: glass buttons, a draggable card that is also a drop target, three inner drop targets per participant, a context menu, nested scroll views — and, on macOS, a hidden second copy of all of it in the main game window (§8.2).
- **Action:** Treat as a system bug to avoid, not to fix: (a) on macOS move Next Turn / Next Round / End into the window toolbar, where the system hosts the glass outside the content hosting view (§8.4), or at least use a bordered style there; (b) stop mounting the hidden overlay on macOS (§8.2); (c) narrow the drag source to a handle instead of the whole card so buttons and text fields are not inside a drag gesture; (d) set an Objective-C exception breakpoint, reproduce, and file Feedback with the backtrace in §12; (e) re-test on the next macOS 27 update.
- **Severity:** High

### 5.2 `skull.fill` does not exist in SF Symbols
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundAttackerActions.swift:77`
- **What:** The "Mark Dead" context-menu item asks for `skull.fill`; the system catalog (9,524 symbols) contains no symbol whose name includes "skull". SwiftUI logs the fault "No symbol named 'skull.fill' found in system symbol set" each time the menu is built (seen 2026-10-08 and 2026-10-10). **Verified.** All 24 other dotted symbol names in scope exist.
- **Why:** The destructive menu item has no icon on every platform, and the fault is logged repeatedly.
- **Action:** Use the same symbol as the name row's toggle (`figure.fall`, `BattleParticipantNameRow.swift:45`) from a single shared constant, and add a unit test that resolves every symbol name the module uses.
- **Severity:** High

### 5.3 Initiative order chosen before the first battle is discarded, then reverted in settings
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundSettingsView.swift:33-39`; `Modules/GameRPG/BattleRound/BattleRoundController.swift:36-38,70,159-167`; `Modules/MapRPG/Controller/GameController+Battle.swift:54,181-188`
- **What:** The picker writes `settings.initiativeOrder` (persisted), then asks the controller to apply it. The controller requires `authorizedMapId`, which is `nil` until a battle has started in this session (and again after `resetBattleRound()`, `GameRoot.swift:514`), so `model.initiativeOrder` keeps its old value. `start()` passes `model.initiativeOrder`, and `beginBattle` then writes that old value back over the saved setting. **Verified.**
- **Why:** A game master who opens Battle Settings, switches to ascending and presses Start gets a descending battle, and the picker has silently flipped back.
- **Action:** Keep one source of truth — the settings model — and have Start and the model read from it; the model's public settable `initiativeOrder` (`BattleRoundModel.swift:34`) should become derived or internal. See §9.8.
- **Severity:** High

### 5.4 A pin highlighted during the surprise round becomes a roster member without a turn and can no longer be added
- **Location:** `Modules/MapRPG/BattleRound/BattleRoundModel+Turns.swift:230-233`; `Modules/MapRPG/Controller/GameController+BattleSync.swift:57-71`; `Modules/MapRPG/Controller/GameController+Battle.swift:228-238`; `Modules/MapRPG/BattleRound/BattleRoundModel+Roster.swift:10-23`
- **What:** `synchronize(pins:additionalDefenders:)` appends every highlighted non-combatant pin to `combatants` before it checks for an active attacker, so this also runs during the surprise round. The pin gets no turn entry. Both guards on the add path then reject it because `combatant(pinId:)` is no longer `nil`. **Verified** by reading; not reproduced.
- **Why:** Players highlight their targets. If a player (or the master) highlights a monster outside the starting room while the surprise round is being prepared, that monster can never act in this battle. It has no card, and "Remove from Battle" exists only on attacker cards, so the only recovery is ending the battle.
- **Action:** Either do not auto-add defenders while `isPreparingSurprise`, or let the add path promote an existing roster member to an attacker by creating its entry.
- **Severity:** High

### 5.5 Removing the active attacker resets the turn pointer to the top of the order
- **Location:** `Modules/MapRPG/BattleRound/BattleRoundModel+Roster.swift:37-40`; `Modules/MapRPG/BattleRound/BattleRoundModel+Turns.swift:148-151`
- **What:** `removeCombatant` clears `activeAttackerId`; the next `nextAttacker()` finds no active attacker and activates the first living entry. **Verified.**
- **Why:** Mid-round, combatants that already acted get a second turn and the round counter does not advance. In round 0 the model also re-enters "preparing surprise", re-opening roster additions and roll eligibility for everyone.
- **Action:** Before removing the active entry, hand the turn to the next living entry (or remember the removed position) so progression continues from where it was.
- **Severity:** Medium

### 5.6 "Mark Dead" from the map menu or the 3D table bypasses the battle bookkeeping
- **Location:** `Modules/MapRPG/Controller/GameController+Pins.swift:337-341`; callers `Modules/MapRPG/Map/MapEditorActionRouter.swift:293`, `Modules/GameRPG/Table3D/GameTableModel+PinSelection.swift:220-225`; compare `Modules/MapRPG/Controller/GameController+Battle.swift:279-310`
- **What:** `toggleDeadPin` only flips `pin.isDead` and the callers broadcast. The battle path (`setBattleCombatantDead`) additionally clears the highlight, removes the combatant from every attacker's target list and re-synchronizes defenders and health. **Verified** for both call paths; any later re-sync on the master was not traced beyond `broadcastMapEdit`.
- **Why:** The roster stores its own copy of each pin, so after a map-side toggle the battle card still shows the combatant alive until some other action re-syncs, turn skipping uses the stale flag, and the dead combatant stays a highlighted target for other attackers.
- **Action:** Route all three entry points through one "set dead" operation that checks for a running battle on that map.
- **Severity:** Medium

### 5.7 Drag-to-reorder is undone by the next initiative change
- **Location:** `Modules/MapRPG/BattleRound/BattleRoundModel+Turns.swift:123-125`; `Modules/MapRPG/BattleRound/BattleRoundModel.swift:146-162`; re-sort callers `BattleRoundModel+Turns.swift:82,96`, `BattleRoundModel+Roster.swift:21`
- **What:** A manual move only rearranges `entries`. `sortEntries()` re-sorts by initiative on every initiative edit, order change or added combatant, preserving prior order only for ties and missing values. **Verified.**
- **Why:** The list header invites "Drag to reorder" for any card, but a manual position between combatants with different initiatives disappears the next time anyone's initiative is adjusted.
- **Action:** Decide the rule: restrict manual moves to ties, or store a manual rank that the sort respects.
- **Severity:** Medium

### 5.8 The macOS inspector stays in the last "choose value" mode
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundScreenModel.swift:36-37,96-112,176-187,193-206,211-217`; `Modules/GameRPG/BattleRound/BattleRoundCharacterInspectorView.swift:18-23`
- **What:** On macOS a "choose" action only sets the pending state and opens the inspector. Assignment then happens by drag and drop straight through the controller, which never clears `pendingValueSelection`, `pendingCharacterCombatantId` or `selectedValue.onlyChildrenFrom`; those are cleared only by the selection-change callbacks, which the inspector's non-selecting list never triggers. **Verified.**
- **Why:** After "Choose the Hit Points value" for one combatant, the inspector keeps showing only that character's entries — also when it is closed and reopened from the toolbar — until another context-menu action happens to reset it.
- **Action:** Clear the pending state when a drop succeeds and when the inspector is dismissed; expose the current mode in the inspector with a way back to the full character list.
- **Severity:** Medium

### 5.9 Assigning a character ignores the chosen one when the pin already carries a stale character id
- **Location:** `Modules/MapRPG/Controller/GameController+Battle.swift:347-356`
- **What:** For a non-player token without a live battle copy, the source is `currentCharacterId ?? characterId` — the pin's existing id wins over the character the game master just picked. **Verified.**
- **Why:** If the pin's original character can no longer be copied (deleted, or copy creation failed at battle start), every attempt to assign a different character fails silently, because the copy is always attempted from the stale id. The same branch would also create a monster-style copy for a player pin that has no character, contradicting the comment above it.
- **Action:** Prefer the explicitly chosen character when the current one has no live copy, and guard the player case separately.
- **Severity:** Medium

### 5.10 A hit-points formula that fails to resolve fails silently
- **Location:** `Modules/MapRPG/Controller/GameController+BattleSync.swift:160-169`
- **What:** The live session logs, on every sync, that pin "Fenitran"'s base text `[KÖR](…)+[HÄ](…)+10+` "resolved to 0 Error, not a positive number", so its health percent is `nil`. The base is taken by splitting the raw value at the first `|` before links are resolved. **Verified** in the console; the entry's raw value was not inspected, so whether the trailing `+` is data or a consequence of the split is open.
- **Why:** The game master sees a gray health ring and nothing that says why; the only trace is a debug log.
- **Action:** Surface "hit points cannot be calculated" on the card next to HP, and split base and modifier with the link engine's tokenizer rather than on the raw text.
- **Severity:** Medium

### 5.11 With every combatant dead, Next Turn activates a dead combatant and advances the round on every press
- **Location:** `Modules/MapRPG/BattleRound/BattleRoundModel+Turns.swift:150,158-159`
- **What:** Both fallbacks use `entries[0].attackerId` when nobody is alive. **Verified.**
- **Why:** Harmless but odd end state: a dead attacker is highlighted as active and the round counter climbs.
- **Action:** Return `false` (or offer to end the battle) when no living attacker exists.
- **Severity:** Low

### 5.12 Initiative cannot be 0 or negative, and "+" from an empty value yields 2
- **Location:** `Modules/MapRPG/BattleRound/BattleRoundModel+Turns.swift:76,89`; `Modules/MapRPG/Controller/GameController+Metadata.swift:286-296`
- **What:** Every path clamps to a minimum of 1, and adjusting from `nil` starts at 1 before adding the amount. **Verified.**
- **Why:** Some rule systems use 0 or negative initiative; the off-by-one on the first "+" press is visible.
- **Action:** Confirm the clamp is intended; start an empty value at the pressed direction's first step.
- **Severity:** Low

### 5.13 Scene tracking marks the window closed while it is opening
- **Location:** `Modules/CoreRPG/ScenesManager/Modifiers/SceneTrackerModifier.swift:49-58`
- **What:** The log for opening the window reads "state opening" → "scenePhase battleRound is background - setting state to closed" → "active - setting state to opened". `.background` is treated as "closed" although on macOS it is also reported for a window that exists but is not yet (or no longer) visible. **Verified** in the console.
- **Why:** The Battle Round menu toggle reads this state (`GameSidebarToolbarMenu.swift:107`), so it can show "closed" for an open window; each flip also re-renders every window button (§7.5).
- **Action:** Derive "closed" from the window actually going away (`onDisappear`), not from `.background`.
- **Severity:** Low

### 5.14 A duplicate-search-item toolbar exception was logged once and could not be attributed
- **Location:** not attributable; nearest candidate `Modules/CoreRPG/Inspector/LinkItemListView.swift:118-124`
- **What:** 2026-10-09 08:51:40: `NSInternalInconsistencyException: NSToolbar … already contains an item with the identifier com.apple.SwiftUI.search`. In the Battle Round window the inspector list is created with the `.inspector` type, which does not attach `.searchable`, and the inline character sheet has none, so this window has no second search source that I could find. **Verified** that it happened; **not attributed**.
- **Why:** Same class as §5.1 — a caught exception that leaves a window half-configured. The project already works around it elsewhere (`SearchBarVisibleModel`).
- **Action:** Catch it with an exception breakpoint the next time it appears and note which window was frontmost.
- **Severity:** Low

---

## 6. Security

No secrets, credentials, file access or URL handling in scope. `recordDiceResult` checks that a player-sent roll may only be attributed to that player's own combatant (`BattleRoundController.swift:334-341`), and the battle table itself never leaves the master.

### 6.1 A player's highlight makes the master create roster entries and character copies
- **Location:** `Modules/MapRPG/Controller/GameController+BattleSync.swift:57-71`; `Modules/MapRPG/Controller/GameController+Battle.swift:106-120`
- **What:** Every highlighted pin that is not yet a combatant is turned into one on the master, including a runtime copy of its character; nothing bounds how many. **Verified.**
- **Why:** A player can grow the master's roster and game memory by highlighting pins; the entries also cannot be removed in the UI (§5.4). Consistent with the project's standing "players are trusted" decision, so this is a robustness note rather than a vulnerability.
- **Action:** Limit auto-added defenders to pins in the active room, or cap the count per battle.
- **Severity:** Low

---

## 7. Performance

### 7.1 Every hit-point or turn action sends the full map state plus the battle state, with no coalescing
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundController.swift:133-156,429-433,446-465`
- **What:** `broadcast(mapId:)` sends a `.mapState` update and a `.battleRound` update per action (console: "Send 120 MapState", "Send 121 BattleRound", 150–200 ms apart), and each HP stepper click is one action. `refreshConfiguredValues()` broadcasts even when nothing changed. **Verified.**
- **Why:** Ten clicks on "−" are twenty messages; over SharePlay each one goes through the relay.
- **Action:** Coalesce broadcasts per run-loop turn or with a short debounce, and skip the map state when no pin changed.
- **Severity:** Medium

### 7.2 The whole Battle Round root view re-evaluates when the scroll position changes
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundView.swift:17,38-84`
- **What:** `ScrollPosition` is `@State` on the root view and bound to the scroll view, so each position update re-runs the root body (console: "BattleRoundView: __scrollPosition changed." in pairs after every turn). **Verified.**
- **Why:** The root body rebuilds the header inputs and reads `cardPresentations` each time.
- **Action:** Move the scroll view, its position state and the scroll-to-active rule into a child view.
- **Severity:** Medium

### 7.3 Health percent is computed at least twice per action for every combatant, with a debug log on every call
- **Location:** `Modules/MapRPG/Controller/GameController+BattleSync.swift:86-105,144-180`
- **What:** The console shows two full passes over all pins within ~12 ms per action; each call resolves the linked formula chain and ends in a `Logger.debug` at `:176-178`. The comment at `:86-94` says the diagnostic log only fires on an actual change, which is true for the caller's log but not for the function's own. **Verified.**
- **Why:** The function is also called per pin from the map's render path, so the cost scales with redraws, not with changes.
- **Action:** Cache the percent per combatant keyed on the entry's value, and drop or gate the per-call log.
- **Severity:** Low

### 7.4 Synchronizing pins rebuilds the lookup indexes once per changed combatant
- **Location:** `Modules/MapRPG/BattleRound/BattleRoundModel.swift:41-43,117-130`; `Modules/MapRPG/BattleRound/BattleRoundModel+Turns.swift:222-228`
- **What:** Each in-place `combatants[index].pin = pin` fires `didSet`, rebuilding both dictionaries and notifying observers. **Verified.**
- **Why:** Quadratic in roster size and one observation notification per element; small today, but this runs on every map sync.
- **Action:** Mutate a local copy and assign the array once.
- **Severity:** Low

### 7.5 One scene-state change re-renders every window button
- **Location:** `Modules/CoreRPG/ScenesManager/ScenesManager.swift:142,148-150`
- **What:** All scene states live in one observed dictionary; the console shows 13 `GameWindowButtonView` plus two menu invalidations per flip, three flips per window open. **Verified.**
- **Why:** Opening the Battle Round window costs roughly 45 unrelated view updates in the main window.
- **Action:** Observe per scene (one small observable per scene id, or an equatable derived value per button).
- **Severity:** Low

### 7.6 A new screen model is allocated on every parent evaluation
- **Location:** `Modules/GameRPG/GameViews/BattleRoundWindowView.swift:8-13`; `Modules/GameRPG/GameViews/BattleRoundSideOverlay.swift:11-16`
- **What:** `State(wrappedValue: BattleRoundScreenModel(...))` in `init` builds a model and two selection models each time the parent body runs; SwiftUI keeps only the first. **Verified.**
- **Why:** The overlay's parent is the game screen, which re-evaluates often.
- **Action:** Use the project's lazy-state pattern, or own the screen model on `GameRoot`.
- **Severity:** Low

### 7.7 `BattleRoundGameChrome` is invalidated by every roster change
- **Location:** `Modules/GameRPG/GameViews/BattleRoundGameChrome.swift:15-34`
- **What:** The console shows 28 "BattleRoundGameChrome: \BattleRoundModel.combatants changed" lines in a three-minute session, although the view only needs `isRunning` and `roundCounter`. **Verified** as observed; which read registers the dependency was not traced.
- **Why:** The chrome sits on the master and the player game screen.
- **Action:** Pass the two values in from a parent, or split the announcement into a child that takes plain values.
- **Severity:** Low

### 7.8 Roll results accumulate for the whole battle
- **Location:** `Modules/MapRPG/BattleRound/BattleRoundModel+Rolls.swift:34-42`
- **What:** Rolls are appended per entry and never trimmed on a new turn or round. **Verified.**
- **Why:** The cache key in `cardPresentations` compares all entries including all rolls on every access, and each strip lays out its whole history.
- **Action:** Keep the last N per entry or clear on a new round.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 `cardPresentations` mutates observed state inside a getter called from view bodies
- **Location:** `Modules/MapRPG/BattleRound/BattleRoundModel.swift:61`; `Modules/MapRPG/BattleRound/BattleRoundCardPresentation.swift:54,95`
- **What:** `cardPresentationsCache` is a stored property of an `@Observable` class without `@ObservationIgnored`. The getter reads it and, on a miss, writes it — during `BattleRoundView.body`. The live console shows "LinkItemRootView: \BattleRoundModel.cardPresentationsCache changed.", i.e. views are being invalidated by the cache write. **Verified.**
- **Why:** Every real change costs a second body pass for each reader (window and, on macOS, the hidden overlay), and state written during a view update is the pattern SwiftUI warns about. It also undercuts the `.equatable()` work done on the cards.
- **Action:** Exclude the cache (and the two private index dictionaries at `:63-64`) from observation.
- **Severity:** Medium

### 8.2 On macOS a hidden duplicate of the Battle Round UI is always mounted in the game window
- **Location:** `Modules/GameRPG/GameViews/OverlayMasterTabBar.swift:20`; `Modules/GameRPG/GameViews/BattleRoundSideOverlay.swift:26-58`
- **What:** `BattleRoundSideOverlay` is added on every platform and hidden with offset, opacity 0 and `allowsHitTesting(false)`. macOS presents Battle Round in its own window (`GameSidebarToolbarMenu.swift:107-116`) and never shows the overlay, yet the console of the Mac session logs `BattleRoundSideOverlay` updates. **Verified.**
- **Why:** A full second navigation stack, card list, set of text fields, glass buttons, drop targets and `onChange` handlers runs invisibly in the main window; every battle change is rendered twice. Hit-testing is off, but the hidden text fields remain in the keyboard focus loop (**inferred**), and the extra glass and gesture sources in the main window are exactly the ingredients of §5.1.
- **Action:** Do not build the overlay on macOS; on the other platforms build its content only while it is shown, keeping the slide animation on the container.
- **Severity:** Medium

### 8.3 Modifiers are applied to multi-root views and fan out to every child
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundView.swift:41-53`; `Modules/GameRPG/BattleRound/BattleRoundSettingsView.swift:13-47`; `Modules/GameRPG/BattleRound/BattleRoundList.swift:20-71`
- **What:** `BattleRoundSettingsView.body` and `BattleRoundList.body` each return several sibling views with no container. `.frame(maxHeight: 280)` and `.transition(...)` on the settings view, and `.padding`, `.frame` and `.animation` on the list's `ForEach`, are therefore applied per child. The comment at `BattleRoundView.swift:46-48` describes a layout (panel above the scroll view) that no longer exists; the settings body is still indented as if a container had been removed. **Verified.**
- **Why:** The settings panel is not height-capped as a whole, has no background or grouping, and its rows animate individually. `BattleRoundCard.swift:68-74` documents the same fan-out problem as already fixed for the card.
- **Action:** Give the settings panel and the list header one container each and attach panel-level modifiers there.
- **Severity:** Medium

### 8.4 The header's actions are drawn in the content area while the macOS toolbar holds only the inspector button
- **Location:** `Modules/GameRPG/GameViews/BattleRoundWindowView.swift:35-49`; `Modules/GameRPG/BattleRound/BattleRoundHeader.swift:15-44`; `Modules/GameRPG/BattleRound/BattleRoundHeaderActions.swift:10-49`
- **What:** Next Turn, Next Round and End are small icon-only buttons in a custom header inside the scrolling content's stack; the window toolbar exists but carries one item. End is destructive, has no confirmation, and closes the window. **Verified.**
- **Why:** On macOS, window-level actions belong in the toolbar (keyboard shortcuts, overflow, customization, system glass). Moving them also takes the interactive glass out of the content hosting view (§5.1).
- **Action:** On macOS provide the three actions as toolbar items with shortcuts and a confirmation for End; keep the in-content header for the side panel on other platforms.
- **Severity:** Medium

### 8.5 Lazy horizontal stacks and nested scroll views inside lazy vertical rows
- **Location:** `Modules/GameRPG/BattleRound/BattleDefenderStrip.swift:25-43`; `Modules/GameRPG/BattleRound/BattleRollResults.swift:23-45`
- **What:** Each card contains a horizontal `ScrollView` with a `LazyHStack` of participant columns (no fixed height), and every participant contains another horizontal scroll view for rolls. **Verified.**
- **Why:** A lazy stack's cross-axis size depends on which children are realized, so a card's height can change while scrolling, which moves the outer lazy list and its scroll-to-active animation. Defender counts are small; laziness buys nothing here and adds scroll-gesture containers per card.
- **Action:** Use plain stacks for the defender strip, and consider a fixed number of visible roll badges instead of a scroll view per participant.
- **Severity:** Medium

### 8.6 On macOS, values can only be assigned by dragging onto caption-sized targets
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundCharacterInspectorView.swift:13-23`; `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift:97-107,119-129`
- **What:** The inspector list is non-selecting by design, so "Choose the Hit Points value" only opens it; the drop targets are the "Ini:" and "HP:" labels in `.caption2`. **Verified.**
- **Why:** The action names promise a choice, but there is nothing to click, and the targets are small and unmarked; there is no keyboard or VoiceOver path for it on macOS.
- **Action:** Let a click in the inspector assign to the pending combatant (the callbacks already exist for the sheet path), and highlight valid drop targets while a drag is in progress.
- **Severity:** Medium

### 8.7 The empty state is not centred
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundEmptyState.swift:36`; `Modules/GameRPG/BattleRound/BattleRoundView.swift:65-70`
- **What:** `frame(maxHeight: .infinity)` has no effect inside a lazy stack in a scroll view. **Verified.**
- **Why:** "No Battle Running" sits at the top of a tall window.
- **Action:** Show the empty state outside the scroll view, or size it with `containerRelativeFrame`.
- **Severity:** Low

### 8.8 One symbol for two meanings, and an explicit animation on the inspector
- **Location:** `Modules/GameRPG/GameViews/BattleRoundWindowView.swift:37-46`; `Modules/GameRPG/BattleRound/BattleActivateAttackerButton.swift:14`; `Modules/GameRPG/BattleRound/BattleRoundAttackerActions.swift:66`
- **What:** `scope` is both the inspector toggle in the toolbar and "make this combatant the attacker" on every card; the toggle wraps the inspector binding in `withAnimation`. **Verified.**
- **Why:** The same icon a few centimetres apart does two different things; the system already animates inspector presentation.
- **Action:** Use the standard trailing-sidebar symbol for the inspector and drop the explicit animation.
- **Severity:** Low

### 8.9 Two nested minimum frames on a content-sized window
- **Location:** `Sources/MasterRPG/Window/WindowUtilityList.swift:113-118,126`; `Sources/MasterRPG/Window/WindowViewerList.swift:144`
- **What:** The window content gets `minWidth: 620, minHeight: 520` and then, from the shared setup modifier, `minWidth: 600, minHeight: 400`; the inspector (min 260) is inside the 620. **Verified.**
- **Why:** The outer frame is redundant, and with the inspector open the main column can shrink to about 360 points, below the card's intended width.
- **Action:** Keep one minimum per window and size it for the inspector-open case.
- **Severity:** Low

### 8.10 Hard-coded metrics and colors
- **Location:** `BattleRoundCard.swift:86,95,99-104`; `BattleRoundHeader.swift:45`; `BattleRoundCompactCardLayout.swift:58`; `BattleDefenderStrip.swift:23,43`; `BattleRoundAnnouncementCounter.swift:26-29`; `BattleRoundList.swift:65`; `BattleRankBadge.swift:15`; `BattleParticipantColumn.swift:28`; active/attacker/defender colors at `BattleRoundCompactCardLayout.swift:36`, `BattleDefenderStrip.swift:33`, `BattleRoundCard.swift:103`
- **What:** Paddings of 10, 16, 18, 24 and 4, a corner radius of 12 in three places, fixed 100×74 and 280 frames, a 48-point avatar and literal blue/red/gray. **Verified.** `BattleRoundSpacing` already exists for exactly this.
- **Why:** The project rule is to avoid hard-coded padding and spacing; the fixed frames do not scale with Dynamic Type, and the colors ignore the app theme.
- **Action:** Extend the spacing scale with the card padding and radius, use scaled metrics for the fixed frames, and take role colors from the theme.
- **Severity:** Low

### 8.11 Typed values that do not parse are discarded without feedback
- **Location:** `Modules/GameRPG/BattleRound/BattleAttackerConfigRows.swift:117-123,169-178`
- **What:** On submit or focus loss the text is parsed with the plain integer initializer; anything else silently reverts to the previous value. **Verified.**
- **Why:** Input with a grouping separator, a sign typed with a typographic minus, or digits in another script is lost without explanation.
- **Action:** Bind the field with a number format style so parsing is locale-aware and invalid input stays visible.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

No `#if false`, no commented-out code blocks, no `TODO`/`FIXME`/`HACK`, no `print()` and no file over 500 lines in scope (largest: `BattleRoundController.swift`, 476).

### 9.1 The modal character-sheet presentation appears unreachable
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundPresentation.swift:6`; `Modules/GameRPG/BattleRound/BattleRoundView.swift:98-99`; `Modules/GameRPG/BattleRound/BattleRoundScreenModel.swift:101-104`; `Modules/GameRPG/BattleRound/BattleCharacterSheetPresentationView.swift` (whole file); `Modules/GameRPG/BattleRound/BattleRoundViewModifiers.swift:6-13`
- **What:** `.sheet(...)` is only produced in `showCharacterSheet` when the factory returns a presentation. Its three callers reach it only when the same factory has just returned `nil` (`BattleRoundCard.swift:31-35`) or when the combatant has no source character (`BattleRoundScreenModel.swift:128-131,145-148`), in which case the factory cannot succeed either. **Inferred** by tracing the three paths. The presented view also hosts the sheet without a scroll view, so it would clip if it were ever shown. On macOS the `.selection` case is never set either (`BattleRoundScreenModel.swift:211-217`), so the whole `.sheet(item:)` modifier is inert there.
- **Why:** About 60 lines plus an enum case and a modifier kept alive by a branch that cannot fire.
- **Action:** Confirm with a breakpoint, then remove the case, the view and `battleInlineNavigationTitle()`.
- **Severity:** Medium

### 9.2 Unused parameters
- **Location:** `BattleRoundScreenModel.swift:99,117,126,143,179` (`scenesManager`, never read — and the environment reads that feed it at `BattleRoundView.swift:15` and `BattleRoundSettingsView.swift:84`); `BattleRoundList.swift:12` (`screenModel`); `BattleRoundHeader.swift:10` (`initiativeOrder`, which also makes the header depend on that value); `BattleInitiativeOrderMenu.swift:8` (`isDisabled`, always `false`); `GameController+Metadata.swift:299-303` (`includingPlayers`, always `true`, and `false` would make the function do nothing); `BattleRoundScreenModel.swift:172-174` (`refreshConfiguredValues(controller:)`, a pure pass-through)
- **What:** Six parameters that no code path uses. **Verified** by grep.
- **Why:** Leftovers from the presentation rework; they widen view dependencies and mislead readers.
- **Action:** Remove them and the two environment reads.
- **Severity:** Low

### 9.3 API kept alive only by tests
- **Location:** `Modules/MapRPG/Controller/GameController+Battle.swift:60-88` (`startBattle(itemId:initiativeOrder:)`: 0 production callers, 18 in tests); `Modules/MapRPG/BattleRound/BattleRoundModel.swift:140-142` (`rolls(for:in:)`: 0 / 7); `Modules/GameRPG/BattleRound/BattleAttackerConfigRows.swift:18-20` (`needsValueConfiguration`: 0 / 2); `Modules/GameRPG/GameViews/GameScreenModel.swift:99-101` (`toggleBattleRoundSidebar()`: 0 / 3)
- **What:** Four members with no production caller. **Verified** by grep over `Modules/` and `Sources/`.
- **Why:** The tests exercise `startBattle`, while the app starts battles through `BattleRoundController.start()` — so 18 tests cover a path the product does not run (see §9.4).
- **Action:** Point the tests at the production entry point and delete the unused members.
- **Severity:** Medium

### 9.4 Battle start is implemented twice
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundController.swift:51-63`; `Modules/MapRPG/Controller/GameController+Battle.swift:67-79`
- **What:** The same player/room combatant construction, including the same comment, exists in both. **Verified.**
- **Why:** The tested copy and the shipped copy can drift.
- **Action:** Keep one, in the map controller, and have the Battle Round controller call it.
- **Severity:** Medium

### 9.5 A synchronize call that can never do anything
- **Location:** `Modules/MapRPG/Controller/GameController+Battle.swift:153-154`
- **What:** `synchronize(pins:)` is called right after `end()`, and returns immediately when the battle is not running. **Verified.**
- **Action:** Delete the call.
- **Severity:** Low

### 9.6 Comments that no longer match the code, and 59 references to overwritten audit reports
- **Location:** `Modules/MapRPG/Controller/GameController+BattleSync.swift:86-94` (says the log fires only on change); `Modules/GameRPG/BattleRound/BattleRoundView.swift:46-48` (describes a removed layout); `Modules/GameRPG/BattleRound/BattleRoundController.swift:418-422` (argues with a doc comment that no longer exists); 45 "See CODE_AUDIT §N.M" comments across the scope
- **What:** The bare "CODE_AUDIT §N.M" references point at a file this skill overwrites on every run; only the 14 that name a numbered report (`CODE_AUDIT_19` etc.) still resolve. **Verified** by grep.
- **Why:** A reader following "§8.1" today lands on an unrelated finding in this report.
- **Action:** Replace the bare references with the reason itself (most comments already state it) or with the archived report's name under `Docu/`.
- **Severity:** Low

### 9.7 Section markers that mislead
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundController.swift:209,271` (two "Combatant mutation" marks, the second above rolls' neighbours); `Modules/MapRPG/BattleRound/BattleRoundModel.swift:24` ("Combatant lookups" above `init`)
- **Action:** Rename or move the marks.
- **Severity:** Low

### 9.8 Two stores for the initiative order
- **Location:** `Modules/MapRPG/BattleRound/BattleRoundModel.swift:34`; `Modules/MapRPG/BattleRound/BattleRoundSettingsModel.swift:38-42`; sync points `Modules/MapRPG/Controller/GameController.swift:22`, `GameController+Battle.swift:54,186`, `BattleRoundSettingsView.swift:37-39`
- **What:** The order lives in the model and in the settings and is copied between them in four places, one of them a view's `onChange`. **Verified.** Root cause of §5.3.
- **Action:** Make the settings model the owner and let the battle model read it.
- **Severity:** Medium

### 9.9 Two "mark dead" controls with separately chosen icons and titles
- **Location:** `Modules/GameRPG/BattleRound/BattleParticipantNameRow.swift:38-58`; `Modules/GameRPG/BattleRound/BattleRoundAttackerActions.swift:71-79`
- **What:** The toggle's title and symbol pair is written out twice, with different symbols. **Verified.** Origin of §5.2.
- **Action:** One small presentation value (title, symbol, role) used by both.
- **Severity:** Low

### 9.10 Presentation rules live in views
- **Location:** `Modules/GameRPG/GameViews/BattleRoundWindowView.swift:26-29`; `Modules/GameRPG/GameViews/BattleRoundSideOverlay.swift:28-33`; `Modules/GameRPG/BattleRound/BattleRoundList.swift:82-109`
- **What:** "Battle ended → dismiss" is duplicated in two views, and the reorder index math sits in the list view. **Verified.**
- **Why:** `CLAUDE.md` asks for view logic in testable models; neither rule has a test today.
- **Action:** Move both into `BattleRoundScreenModel`.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Keep the gesture surface of a macOS content view small.** §5.1 is a system assertion, but the screen that hit it combines interactive glass, a draggable-and-droppable card, nested drop targets, a context menu and nested scroll views in one hosting view — twice, counting the hidden overlay. Put window actions in the toolbar (§8.4), drag from a handle, and do not mount invisible interactive UI (§8.2). The same review is worth doing for any other macOS window that mixes `.buttonStyle(.glass)` with drag and drop.
2. **Treat caught AppKit exceptions as crashes during development.** They do not terminate the app, so they are easy to miss; the only trace is a `HIExceptions` fault in the unified log. Run the Mac scheme with an Objective-C exception breakpoint, or launch with `NSApplicationCrashOnExceptions` in Debug, and check the log for `HIExceptions` after a test session.
3. **One owner per piece of state.** §5.3/§9.8 (initiative order), §5.6 (dead flag on the pin versus the roster's pin copy) and §5.8 (pending selection versus inspector) are all the same shape: a value copied into a second place and synchronized by hand.
4. **Observable models: exclude caches and indexes from observation.** §8.1 is one annotation; a quick grep for stored non-`let` properties named `*Cache`/`*Index*` in `@Observable` classes across the modules would find siblings.
5. **Test the entry point the app uses.** §9.3/§9.4: 18 tests drive `startBattle`, the product calls `BattleRoundController.start()`. The same check applies to the turn-order and dead-marking paths in §5.4–§5.6, which have several entry points each.
6. **Validate symbol names in a test.** A parameterized test over the module's symbol literals against `NSImage(systemSymbolName:)`/`UIImage(systemName:)` would have caught §5.2.

---

## 11. What was NOT audited

- **Everything outside Battle Round.** `ScenesManager`, the window list, `ManagedNavigationStack`, the link-list inspector and the character sheet were read only as far as needed to follow a Battle Round path.
- **The three parallel audit agents did not complete.** They were launched as the skill prescribes and all three stopped on an account spend limit before returning anything; the concurrency, dead-code and bug passes were then done by reading every file in scope directly. The separate SwiftUI-expert pass was not run as its own step; the SwiftUI review in §8 is from the same direct read.
- **No reproduction of §5.1.** The Mac app was running in the user's debug session during the audit and was not driven. The link between the logged exception and the Battle Round window is by timing and by the recognizer types involved, as stated in the finding.
- **iOS, tvOS and visionOS builds.** Only the macOS scheme was built. Platform branches for the other systems were read, not compiled or run.
- **The player side of the protocol** (`PlayerController+Map`, deferred battle-round replay, sequence handling across a master reset) — read only at `BattleRoundModel+Network.swift`; whether players' sequence gates survive `resetBattleRound()` on the master was not traced.
- **Tests** under `Tests/MapRPGTests/BattleRound*` and `Tests/GameRPGTests/BattleRound*` — used for reference counts only; not run, not reviewed for coverage.
- **3D table integration** (`GameTableModel+PinSelection`, `syncPawnsWithMapPins`) beyond the dead-toggle path in §5.6.
- **Localization** — string catalogs not checked; several accessibility strings in scope were not verified for translation.
- **Performance profiling** — no Instruments trace; §7 is from the console and from reading.

---

## 12. Verification

Open Xcode and command-click a `path:line` reference; it should land on the cited line. There are no Critical findings. For the High findings and the evidence-based Medium ones:

- **§5.1** — unified log, process `MasterRPG`, 2026-10-10 23:46:40 (PID 30916): `*** Assertion failure in NSComparisonResult NSGestureRecognizerContainerCompare(...), NSGestureRecognizerContainer.m:158` / `Unexpected equal node indexes`; backtrace frames `NSGestureRecognizerContainerCompare` ← `-[NSGestureRecognizer isDeeperThanContainer:referenceNode:]` ← `Gestures` ← `-[_NSGFGestureEnvironment _routeMouseEventToActiveGestureRecognizers:]` ← `-[NSWindow(NSEventRouting) sendEvent:]`; then at 23:46:42 `Stuck gesture recognizers detected` naming `_NSComponentGestureRecognizer<SwiftUI.FlexInteraction.GestureFactory.ComponentValue>` and `SwiftUI.AppKitGestureRecognizer` on one `NSHostingView<…NavigationPaneModifier…>`, and `Ignoring all remaining gesture recognizers. This is a bug and you should file a radar.` Same exception at 21:09:14 (PID 30251). To re-read: `/usr/bin/log show --last 30d --predicate 'process == "MasterRPG" AND eventMessage CONTAINS "Unexpected equal node indexes"'`. Glass buttons: open `BattleRoundHeaderActions.swift`, lines 20 and 46.
- **§5.2** — open `BattleRoundAttackerActions.swift`, line 77. Log: `[com.apple.SwiftUI:Invalid Configuration] No symbol named 'skull.fill' found in system symbol set` (2026-10-08 21:01–21:02, 2026-10-10 23:48). The symbol catalog on macOS 27.0.1 has no name containing "skull".
- **§5.3** — open `BattleRoundController.swift`: line 37 (`authorizedMapId` is `nil` without `model.mapId`), lines 159-167 (returns `false`), line 70 (`start()` passes `model.initiativeOrder`); then `GameController+Battle.swift` line 54 (settings overwritten on begin).
- **§5.4** — open `BattleRoundModel+Turns.swift`, lines 230-233: the append happens before the `guard let activeAttackerId` at 235. Then `GameController+Battle.swift` line 231 and `BattleRoundModel+Roster.swift` lines 12-13: both reject a pin that is already a combatant.
- **§5.5** — open `BattleRoundModel+Roster.swift`, lines 37-40, then `BattleRoundModel+Turns.swift`, lines 148-151.
- **§5.6** — open `GameController+Pins.swift`, lines 337-341, and compare with `GameController+Battle.swift`, lines 279-310.
- **§8.1** — open `BattleRoundModel.swift`, line 61 (no `@ObservationIgnored`), and `BattleRoundCardPresentation.swift`, lines 54 and 95. Console line from the live session: `LinkItemRootView: \BattleRoundModel.cardPresentationsCache changed.`
- **§8.2** — open `OverlayMasterTabBar.swift`, line 20 (outside the platform conditional at 14-19). Console line from the Mac session: `BattleRoundSideOverlay: @self, @identity, _gameScreenModel, _accessibilityReduceMotion, _screenModel changed.`
- **§7.1** — console: `MasterController: Send 120: Update - MapState` at 18:16:14.368 and `Send 121: Update - BattleRound` at 18:16:14.561 for one action.

If any finding does not reproduce when you visit the line, tell me the reference and I will re-investigate.

---

## 13. Fix status (2026-10-11)

Applied after the audit. Of the 47 findings: 40 fixed; §5.13 fixed on macOS only; §5.1 mitigated; §3.2 kept as recommended and covered by a test; §7.1 and §7.3 partly; §5.14 not fixable in code; §6.1 unchanged by decision. Four findings needed a decision, taken by the author: §5.7 (a dragged order sticks), §8.4 (End asks first on every platform), §5.12 (initiative may be 0 or negative), §6.1 (no limit on auto-added targets).

**Verification:** `MasterMac` builds with no warnings in the changed files; the tvOS and visionOS apps and the iOS test build compile as well. On the iPhone simulator the complete `MapRPGTests`, `GameRPGTests`, `CoreRPGTests` and `CharacterRPGTests` targets pass (1,381 tests); 50 of them are new and cover the fixed rules. The card layout, the settings panel and the header were rendered offscreen on iOS and looked at. **Not verified:** nothing was run interactively — the macOS window, its toolbar, the inspector's click-to-assign, dragging by the handle and the iOS side panel's show/hide were compiled, not clicked.

| Finding | Status | What changed |
| --- | --- | --- |
| §3.1 | Fixed | The window closes one main-actor turn after the battle ended; the rule is `BattleRoundScreenModel.battleRunningDidChange`, tested. |
| §3.2 | Kept, tested | `unowned` stays as recommended. New test: the battle round's objects do not keep a `GameRoot` alive. |
| §4.1 | Fixed | Static shape members. One `Circle()` remains for the avatar's stroked ring, which has no static-member spelling. |
| §5.1 | Mitigated | On macOS the turn actions are window toolbar items, the hidden overlay is gone (§8.2), and a card is dragged by a handle, not as a whole. Glass header buttons remain on iOS and tvOS only. The system assertion itself was not reproduced, so the effect is not confirmed. Still open for you: file Feedback with the backtrace in §12, re-test on the next macOS 27 update. |
| §5.2 | Fixed | `figure.fall`, from one shared `BattleDeadToggle`. A test reads the symbol names out of the battle round sources and asks the system for each. |
| §5.3 | Fixed | The saved setting is the one owner. `setBattleInitiativeOrder` works without a running battle; a battle begins in the saved order and no longer writes it back. |
| §5.4 | Fixed | A pin that is on the roster only as a target can be given its own turn while the surprise round is prepared (`canAddCombatant`); it keeps its combatant and Character copy. |
| §5.5 | Fixed | Removing the active attacker passes the turn to the next living one, as Next Turn would; at the end of the order the next round starts. |
| §5.6 | Fixed | Map menu, 3D table and battle card all go through `setPinDead`, which does the battle bookkeeping for a combatant of a running battle. |
| §5.7 | Fixed | An initiative edit moves only that combatant's card; the others keep the order they were dragged into. Changing the Initiative Order re-sorts everything. |
| §5.8 | Fixed | A drop finishes the matching pending choice, closing the inspector cancels it, and the inspector shows what it is waiting for with "Show All Characters". |
| §5.9 | Fixed | The chosen Character is used when the token has no live copy. A player token without a Character takes the chosen one as it is, without a copy. |
| §5.10 | Fixed | A warning sign next to "HP:" when the chosen value yields no health. Base and current are resolved by the Character module (`gameValueBaseAndCurrent`), which does not split at a "\|" inside a link. A value that really ends in an operator still does not evaluate — it now shows the warning. |
| §5.11 | Fixed | With nobody alive, Next Turn and Next Round do nothing. This reverses a behaviour an earlier test asserted on purpose ("falls back to the first entry"); that test was rewritten. |
| §5.12 | Fixed | No clamp. "+" on an empty value gives 1, "−" gives −1. Also fixes a trap for a value of exactly 2⁶³. |
| §5.13 | Fixed on macOS | A window that is opening is no longer marked closed by the `.background` phase it passes through. Other platforms are unchanged; "closed" is still derived from `.background` there. |
| §5.14 | Not fixed | Still not attributable to a window. The new inspector mode uses the list type that adds no search field, so it adds no second source. |
| §6.1 | No change | By decision: players are trusted. Only the trap of §5.4 was removed. |
| §7.1 | Partly | Each of the two messages is sent only when its state differs from the one last sent (`BattleRoundBroadcastLog`): a hit-point step sends one message instead of two, an action that changes nothing sends none. No timer-based coalescing — ten quick clicks are still ten map messages. |
| §7.2 | Fixed | Scroll view and scroll position live in `BattleRoundScrollContent`. |
| §7.3 | Partly | `healthPercent(for:)` no longer logs; the reason for a missing value is logged where a new value is persisted. Not cached: the percent depends on linked values several hops away, so a cache keyed on the entry's own text would go stale. |
| §7.4 | Fixed | `synchronize` assigns the roster once per call. |
| §7.5 | Fixed | One observable state per scene; setting an unchanged state notifies nobody. Tested. |
| §7.6 | Fixed | `LazyState` for the screen model in the window and the side panel. |
| §7.7 | Fixed | The chrome takes the attacker's name when a round is announced instead of reading the roster in `body`. Not re-measured in the console. |
| §7.8 | Fixed | A combatant keeps its newest 20 rolls per turn entry. |
| §8.1 | Fixed | Cache and both lookup indexes are `@ObservationIgnored`. Tested. |
| §8.2 | Fixed | The side panel is mounted on iOS only, and its content exists only while it is shown. |
| §8.3 | Fixed | The settings panel is one container; the list's row modifiers sit on the rows. The 280-point cap and its stale comment are gone — the panel scrolls with the list. |
| §8.4 | Fixed | macOS toolbar: Next Turn (⌘→), Next Round (⌥⌘→), End, inspector. End asks first on every platform. |
| §8.5 | Fixed | Plain stacks. The rolls keep their horizontal scroll view. |
| §8.6 | Fixed | A click in the inspector assigns while a choice is pending. Drop targets are larger and outlined while a drag hovers over them. |
| §8.7 | Fixed | The empty state is centred in the visible area unless the settings are expanded above it. |
| §8.8 | Fixed | `sidebar.trailing` for the inspector, as a toolbar toggle without an explicit animation. |
| §8.9 | Fixed | The battle view sets its own least width (list 400, inspector 260); the window frame keeps ideal size and least height. The shared 600×400 floor of all windows is unchanged. |
| §8.10 | Fixed | Spacing scale extended, fixed frames are scaled metrics, role colors come from `BattleRoundPalette`. The colors stay blue/red/gray on purpose: they are the map's pin colors. |
| §8.11 | Fixed | Locale-aware parsing (`BattleNumberInput`); text that is not a whole number stays in the field, marked. |
| §9.1 | Fixed | The modal sheet case, its view and `battleInlineNavigationTitle()` are removed. |
| §9.2 | Fixed | All six parameters and the two environment reads are removed. |
| §9.3 | Fixed | `startBattle(itemId:)` is now what the app calls; `rolls(for:in:)`, `needsValueConfiguration` and `toggleBattleRoundSidebar()` are removed. |
| §9.4 | Fixed | `BattleRoundController.start()` calls the map controller's `startBattle`. |
| §9.5 | Fixed | Call removed. |
| §9.6 | Fixed | The three stale comments are rewritten; no bare "CODE_AUDIT §N.M" reference is left in the battle round files. Other files of `MapRPG` still have some. |
| §9.7 | Fixed | Marks renamed. |
| §9.8 | Fixed | See §5.3. The model's copy is settable only inside `MapRPG`. |
| §9.9 | Fixed | See §5.2. |
| §9.10 | Fixed | Both rules and the reorder index math are in `BattleRoundScreenModel`, tested. |

Changes you will notice that the findings did not spell out:

- A battle card is dragged by the grip under its rank badge on iOS and visionOS too, not only on macOS.
- New strings have German and Thai translations; the Thai ones are marked machine-translated.
- A single tap on a highlighted pin during the surprise round now adds it to the battle (before, the add was refused and the pin menu opened).
