# MasterRPG Quick Dice Overlay Code Audit (2026-10-27)

Scope: the uncommitted Quick Dice overlay feature on top of HEAD `3e4e6a60c` (23 modified files, 7 new source files and 2 new test files, about 350 changed lines plus about 890 new lines):

- CoreRPG: `Model/QuickDiceSlotsModel.swift`, `AppModels/AppSettingsModel.swift`.
- DiceRPG: `Game/Quick/*`, `Controller/ViewController.swift`.
- CharacterRPG: `View/QuickDiceFavoriteMenu.swift`, `View/EntryListDiceRow.swift`, `Controller/GameController.swift`, `GameController+Dice.swift`.
- GameRPG: `GameViews/QuickDice/*`, `GameQuickDiceToggleButton.swift`, `GameScreenModel.swift`, `OverlayGameLayout.swift`, `GameSidePanelModifier.swift`, `OnlyPlayerGameView.swift`, `PlayerGameScreen.swift`, `PlayerOverlayMenu.swift`, `OverlayGameMenu.swift`, `IOSGameOverlayMenu.swift`, `GameToolbarContent.swift`, `GameScreenOrnaments.swift`, `GameDiceVisibilityPersistence.swift`, `Root/GameRoot.swift`, `GameRootView.swift`.
- RolePlayGameKit: `AppEnvironmentSetUpViewModifier.swift`.
- The three string catalogs and the tests `CoreRPGTests/QuickDiceSlotsModelTests.swift` and `GameRPGTests/QuickDiceLayoutTests.swift`.

**Ground truth.**
- `MasterRPG` iOS (MCP build), `MasterMac`, `MasterTV` and `MasterRPG` for visionOS (`xcodebuild`) all build. The visionOS scheme needed a per-scheme `clean` first because of the known stale EagerLinkingTBD link error, in `TableRollRange.selectorRange`, code this feature did not touch.
- **0 compiler warnings** in any changed file in any of the four platform build logs or the test log.
- The 13 new tests pass. They cover the slot model and the sidebar-reservation maths.
- The empty and filled slot states were rendered with `RenderPreview` on an iPhone 18 Pro.
- **Nothing was run in a real game.** No player joined a master. Overlay placement next to the sidebar, the iOS safe-area handling, the picker sheet, the macOS/visionOS link-window drag, the visionOS ornament and tvOS focus are all unverified at runtime. Everything below is code-confirmed unless it says otherwise.

**Evidence labels.** *Code-confirmed* = read at the cited lines. *Build-confirmed* = compiler or test output. *Unverified* = plausible from the code but not reproduced.

**Result.** No Critical and no High findings. The feature has no crash path and no data-loss path that I could find. The Medium findings are functional gaps (§5.1, §5.2, §5.3), an untestable logic placement (§8.4) and a touch target (§8.2). The report is deliberately short because the diff is small. Findings are not padded to reach the skill's usual 50–100.

---

## 0. Status (fixed 2026-10-27)

All four platform schemes build with 0 warnings in the changed files, and the Quick Dice suites pass (17 tests, 9 of them new or changed for this round). Nothing was run in a real game, so the runtime items from §11 stay open.

| § | Status | How |
|---|---|---|
| 4.1 | Kept, documented | `UserDefaults` is still not `Sendable` in this SDK (the build rejects removing it); the `nonisolated(unsafe)` now carries a comment saying why |
| 4.2 | Won't fix | Matches the surrounding game chrome, as the finding itself concluded |
| 5.1 | Fixed | The whole slot, in every state, is a drop target with a highlight; the empty view is a plain button |
| 5.2 | Fixed | A base-dice slot checks that its template resolves (`validateLink`), shows "Unavailable" otherwise, and makes its copy once the dice is there |
| 5.3 | Fixed | The override lives in `QuickDiceSlotsModel` (`setOverride`, `effectiveValue`, `linkedValueChanged`); the slot and the sheet row both read the effective value |
| 5.4 | Fixed | `setOverride` ignores values of 0 or less |
| 5.5 | Fixed | The slot view is keyed by its source; `assign` keeps the game copy when the same dice is assigned again |
| 5.6 | Fixed | `prune` removed. Pruning on load would delete valid slots while iCloud items are still loading, so a dangling entry stays "Unavailable" until the player clears it |
| 5.7 | Fixed | New `sheetRootItemId` environment value; the favorite menu shows only on the player's own character sheet |
| 5.8 | Fixed | Manual values and overrides are clamped to the dice model's bound on assign, set and load |
| 5.9 | Fixed | A base-dice roll passes no category, so it is shared like a dice rolled from the dice list; the master's table and battle-round code only read `.value`/`.character` categories |
| 7.1 | Accepted | Left as the finding advised; the shared effective value is the place to optimise if profiling asks for it |
| 7.2 | Fixed | The value button reads the result once per update |
| 8.1 | Fixed | The extra `NavigationStack` is gone; the list's own stack and dismiss button are used |
| 8.2 | Fixed | `.minimumHitArea()` on the value button |
| 8.3 | Fixed | `ViewThatFits` drops the icon and keeps the number in narrow slots |
| 8.4 | Fixed | The override, bounds and game-copy rules are in the model and covered by tests; the views only render them |
| 8.5 | Changed, unverified | The overlay sits in the trailing ornament below the side menu, so it cannot collide with another ornament, and has a `glassBackgroundEffect`; not seen in a visionOS simulator |
| 8.6 | Won't fix | The first-render write is the same one the existing sheet row makes, it is idempotent afterwards, and resolving it in a task would miss entry-dice changes |
| 8.7 | Fixed | The overlay is an accessibility container labelled "Quick Dice"; the slot label is on the button; the value button reports its value |
| 9.1 | Fixed | See 5.6 |
| 9.2 | Fixed | `GameRoot.offersQuickDice(isMaster:)` is the one rule, used by all seven sites |
| 9.3 | Fixed | `DiceRootModel.rollAndShare` is the one roll, share and donate step for `DiceInline` and the quick roll button; the two labels stay separate because their layouts differ |
| 9.4 | Fixed | One `GameOverlayToggleButton` behind both toggles, one iOS field wrapper, and `index(forItem:entry:)` now takes item first |
| 9.5 | Fixed | The preview uses the public `DiceRootModel.previewDiceId` |

---

## 1. Executive summary

1. **[Medium] On macOS and visionOS a filled slot cannot be given other dice by dropping** — §5.1 — `GameViews/QuickDice/QuickDiceSlotView.swift:31-48, 74-97`. The context menu's "Choose Dice" opens the dice link window, but only an empty slot is a drop target.
2. **[Medium] A deleted or not-yet-loaded base dice becomes an empty dice that can still be rolled and shared** — §5.2 — `QuickDiceSlotView.swift:143-188`.
3. **[Medium] The sheet's dice row re-pushes the linked value over an active override** — §5.3 — `CharacterRPG/View/EntryListDiceRow.swift:24-31`, `QuickDiceSlotView.swift:102-139`.
4. **[Medium] The value button's tap target is about 28 pt, under the 44 pt minimum** — §8.2 — `DiceRPG/Game/Quick/QuickDiceValueButton.swift:36-38`.
5. **[Medium] Slot behaviour (override, value push, game-dice reuse) lives inside views and cannot be unit-tested** — §8.4 — `QuickDiceSlotView.swift:102-189`. This is contrary to the CLAUDE.md rule "place view logic into view models".
6. **[Medium] The picker sheet wraps a view that already has its own `ManagedNavigationStack` in a second `NavigationStack`** — §8.1 — `DiceRPG/Game/Quick/QuickDicePicker.swift:14`. Unverified.
7. **[Low] The visionOS ornament has no background and its anchor collides with an existing ornament** — §8.5 — `GameScreenOrnaments.swift:47-55`. Unverified.
8. **[Low] The "player, not observer" rule is copied in seven places** — §9.2.

---

## 2. Quick wins

- §9.1: delete or use `QuickDiceSlotsModel.prune(keeping:)`, which only its own test calls.
- §4.1: drop `nonisolated(unsafe)` on `UserDefaultsQuickDiceSlotStore.defaults` if `UserDefaults` is `Sendable` in this SDK; otherwise leave it.
- §8.2: give the value button `.minimumHitArea()`, which `GameOverlay*ButtonStyle` already uses.
- §5.4: have the quick editor's slot closure reject values ≤ 0 visibly, or let the dice accept 0.
- §9.4: rename the parameters of `index(forEntry:in:)` to match `.entry(itemId:entryId:)` order.

---

## 3. Concurrency

_No findings._

All new `@Observable` types are `@MainActor` (`QuickDiceSlotsModel`, and `GameScreenModel` already was). `QuickDiceSlotStoring` is `Sendable`. The only `nonisolated(unsafe)` is §4.1. No `DispatchQueue`, no `Task.sleep(nanoseconds:)`, no unstructured `Task` was added. There are 0 concurrency warnings in the four build logs.

---

## 4. API modernity

### 4.1 `nonisolated(unsafe)` on a `UserDefaults` property
- **Location:** `Modules/CoreRPG/Model/QuickDiceSlotsModel.swift:33-38`
- **What:** `UserDefaultsQuickDiceSlotStore` stores `UserDefaults` as `nonisolated(unsafe)` to satisfy `Sendable`.
- **Why:** `UserDefaults` is documented thread-safe and is `Sendable` in recent SDKs, so the opt-out is probably unnecessary and hides future mistakes.
- **Action:** Try removing the annotation on the iOS 26/27 SDK; keep it only if the compiler requires it, with a one-line comment saying why.
- **Severity:** Low

### 4.2 Hard-coded padding and spacing in new views
- **Location:** `QuickDiceOverlay.swift:19-22` (spacing 4, padding 8), `QuickDiceSlotView.swift:81-90`, `QuickDiceRollButton.swift:30-37`, `QuickDiceValueButton.swift:66-68`, `GameScreenOrnaments.swift:52`
- **What:** CLAUDE.md says to avoid hard-coded padding and stack spacing unless requested.
- **Why:** Consistency only. The surrounding game chrome (`OverlayGameMenu`, `IOSGameOverlayMenu`) uses the same literal values, so the new code matches its neighbours.
- **Action:** Leave as is, or move the spacing into `GameScreenModel` constants next to `mapOverlaySpacing` if more overlays are added.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 A filled slot cannot receive a drop, so "Choose Dice" is a dead end on macOS and visionOS
- **Location:** `Modules/GameRPG/GameViews/QuickDice/QuickDiceSlotView.swift:31-48` (context menu), `:65-72` (`choose()`), `:74-97` (`DropItemModuleArea` only in `QuickDiceEmptySlotView`)
- **What:** On macOS and visionOS `choose()` opens the dice link window, which is a drag source. Only the empty-slot view is wrapped in `DropItemModuleArea`. After choosing "Choose Dice" on a filled slot there is nothing to drop onto.
- **Why:** Replacing a slot's dice on those two platforms requires "Clear Slot" first. The menu item is misleading.
- **Action:** Wrap the whole slot (all three states) in the drop area, or hide "Choose Dice" on macOS/visionOS and offer Clear only. Prefer the first, since the plan said "drop it" should work.
- **Severity:** Medium

### 5.2 A deleted or unloaded base dice shows as an empty, rollable dice
- **Location:** `QuickDiceSlotView.swift:143-188` (`makeGameDice()` at `:176-183`), `Modules/CoreRPG/Controllable/GenericGameController.swift:27-29`
- **What:** `createGameDice(for:gameDiceId:)` copies `itemController.itemOrEmpty(for: diceId)`, so a template that no longer exists (deleted, or iCloud not yet loaded) yields an empty dice model. The slot renders a blank label and a working roll button. Entry slots get an "Unavailable" state (`QuickDiceUnavailableSlotView`); base-dice slots never do.
- **Why:** The player can roll an empty dice and share an empty result to the table. The slot also never recovers when the template appears later, because the copy is remembered by `QuickDiceSlotsModel.gameDiceId(at:for:)`.
- **Action:** Check that the template resolves (`itemController.itemSync(for:)` through a public Dice API) before making the copy; show the existing Unavailable state otherwise, and re-resolve when it changes. Do not remember a copy of a missing template.
- **Severity:** Medium

### 5.3 The sheet's dice row re-pushes the linked value over an active override
- **Location:** `Modules/CharacterRPG/View/EntryListDiceRow.swift:24-31`, `QuickDiceSlotView.swift:112-131`
- **What:** An entry slot shares one game dice with the sheet row of the same entry. The row's `.onChange(of: compareValue, initial: true)` and `.onChange(of: id)` call `validateForValue` with the linked value whenever the row (re)appears. A slot's temporary override lives only in the slot's `@State`, so it is overwritten without the slot noticing.
- **Why:** The slot shows a value different from the one the dice uses, and the override is silently lost. The override then also survives in `@State` as a stale `overrideValue`, so the next linked change looks like nothing happened. This can happen whenever the sidebar content remounts.
- **Action:** Make the override part of the shared state (for example, hold the override in `QuickDiceSlotsModel` and let both the sheet row and the slot read the effective value from one place), or have the slot re-assert its override when the dice's compare value changes underneath it. Not verified at runtime.
- **Severity:** Medium

### 5.4 An override of 0 or less is accepted by the editor and silently ignored by the dice
- **Location:** `QuickDiceSlotView.swift:122-139`, `Modules/DiceRPG/Controller/GameController.swift:240-246` (`validateForValue` guards `compareValue > 0`), `DiceRPG/Game/Editor/DiceQuickEditor.swift` (`Int(value) ?? 0`)
- **What:** The quick editor reports 0 for an empty or "0" field. The slot stores it as the override and the editor closes, but `validateForValue` refuses the value, so the dice keeps its old value.
- **Why:** The button shows the old value while the slot believes it is overridden. Low impact, but it looks like a lost input.
- **Action:** Ignore non-positive values in the slot's closure (keep the editor open or restore the field), or allow 0 consistently. Same limit as the existing player-dice flow, which uses a different path (`resetCompareValue`).
- **Severity:** Low

### 5.5 A base-dice slot keeps its old game copy while the source changes in place
- **Location:** `QuickDiceSlotView.swift:143-188`, `Modules/CoreRPG/Model/QuickDiceSlotsModel.swift:100-110`
- **What:** `QuickDiceBaseDiceSlotView` holds the game dice in `@State`. When the slot changes from `.dice(A)` to `.dice(B)`, the view keeps its identity, so it shows A's copy until `.task(id: diceId)` replaces it. Re-assigning the same dice to the slot clears the model's remembered copy (`assign` sets `gameDice[index] = nil`) while the view keeps using the old one, so a later view recreation makes a second copy and drops the roll results.
- **Why:** A brief wrong frame and a rare result loss. Low impact.
- **Action:** Key the view by the slot's source (`.id`), or let the model own the game dice id so the view always reads one value.
- **Severity:** Low

### 5.6 Saved slots are never cleaned up
- **Location:** `Modules/CoreRPG/Model/QuickDiceSlotsModel.swift:33-60, 131-139`
- **What:** `prune(keeping:)` exists but nothing calls it, and `"quickDiceSlots.<characterId>"` keys are never removed, not even when the character is deleted.
- **Why:** Dangling entry slots show as "Unavailable" until the player clears them, and the UserDefaults keys accumulate. Neither is harmful.
- **Action:** Either prune when a character's data is loaded in game (for example in `PlayerGameScreen` after the character is in game memory), or remove `prune` (see §9.1) and document the manual Clear.
- **Severity:** Low

### 5.7 An entry from another character's sheet can be put into the player's slots
- **Location:** `Modules/CharacterRPG/View/QuickDiceFavoriteMenu.swift:17-21`
- **What:** The menu shows on any character sheet row during a player game, not only the player's own character. `QuickDiceSlot.Source.entry` stores only `itemId` and `entryId`.
- **Why:** A player can favorite an entry of a character the GM shared. If that item later disappears, the slot becomes Unavailable. Possibly a feature, but unplanned.
- **Action:** Decide whether foreign sheets are allowed. If not, require `itemId` (or its group owner) to be the player's `selectedCharacter` before showing the menu.
- **Severity:** Low

### 5.8 A restored manual value is unbounded
- **Location:** `QuickDiceSlotsModel.swift:9-25` (`manualValue: Int?`), `QuickDiceSlotView.swift:185-188`
- **What:** The value is decoded from UserDefaults and pushed to the dice as is. `DiceModel` itself bounds decoded values (`boundedValue`), and `addDiceEvery` scales the dice count with the compare value.
- **Why:** A huge number (typed into the editor, or a corrupted default) could create a very large number of dice. The existing quick editor has the same exposure, so this is not new risk, only new persistence of it.
- **Action:** Clamp the value in `setManualValue` and on load, using the same limit as `DiceModel.boundedValue`.
- **Severity:** Low

### 5.9 The shared result category of a base-dice roll uses the template id (unverified)
- **Location:** `QuickDiceSlotView.swift:154-157`
- **What:** The roll shares `ResultCategory(id: diceId, module: .dice)` where `diceId` is the library dice's id, while the rolled dice is a game copy.
- **Why:** The master's log and any code that resolves the category to a name may look up the template on a device that does not have it. I did not check what the receiver does with it.
- **Action:** Send a real game roll between two devices and read the log entry; compare with a roll from the main dice overlay.
- **Severity:** Low

---

## 6. Security

_No findings._

The feature stores only UUIDs and small integers in `UserDefaults`, adds no network message type (a roll uses the existing `networkActions.game(...)` path), reads no user-controlled strings into code, and shows no new external input. Slot data from a corrupted default fails to decode and is dropped (`try?` in `UserDefaultsQuickDiceSlotStore.slots(for:)`, `QuickDiceSlotsModel.swift:40-45`).

---

## 7. Performance

### 7.1 Each entry slot recomputes the value formula, as does the sheet row
- **Location:** `QuickDiceSlotView.swift:112-114`, `CharacterRPG/View/EntryListDiceRow.swift:24`
- **What:** `diceCompareValue` runs `LinkController.calculate(entry:)` inside `body`, once per entry slot and once more for the sheet row of the same entry. It is re-run whenever any observed linked entry changes.
- **Why:** Up to four extra formula resolutions per change, each following links at any depth. Fine for typical sheets; visible only with deep formulas.
- **Action:** Leave for now. If profiling shows cost, resolve the value once in a shared model (the same place as §5.3's fix).
- **Severity:** Low

### 7.2 `QuickDiceValueButton` evaluates the dice result up to three times per body
- **Location:** `DiceRPG/Game/Quick/QuickDiceValueButton.swift:17-52`
- **What:** `hasResults`, the `.tint` expression and `icon(hasResults:)` each call `root.gameController.result(itemId:)`, which recalculates the roll outcome.
- **Why:** Small, repeated work on every state change, times four slots.
- **Action:** Read the result once into a local at the top of `body` and pass it down.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 The picker sheet nests a `NavigationStack` around a view that owns one
- **Location:** `Modules/DiceRPG/Game/Quick/QuickDicePicker.swift:14-16`, `Modules/CoreRPG/Inspector/LinkItemListView.swift:37`
- **What:** `LinkItemListView` creates its own `ManagedNavigationStack(name: "LinkInspector")`. `QuickDicePicker` puts `LinkRootView` inside another plain `NavigationStack`.
- **Why:** Possible double navigation bars and toolbar items attached to the wrong stack; the dismiss and add buttons live in the list's own toolbar. The existing managed-sheet route (`SelectionRoute.selection`) does not add this wrapper. Not run, so unverified.
- **Action:** Drop the wrapper and present `LinkRootView(type: .selection, …)` directly (its toolbar already carries the dismiss button for non-window types), or check on iOS and tvOS that the bar renders once.
- **Severity:** Medium

### 8.2 The value button is smaller than the 44 pt minimum tap target
- **Location:** `Modules/DiceRPG/Game/Quick/QuickDiceValueButton.swift:36-38`
- **What:** The button uses `.bordered`, `.capsule` and `.controlSize(.small)`, about 28 pt tall. The old capsule style applied `.minimumHitArea()` (`CoreRPG/Buttons/OverlayButtonStyle.swift:99,122`) and the roll button here has `minHeight: 44`.
- **Why:** Hard to hit on a phone during a game, against the HIG.
- **Action:** Add `.minimumHitArea()` or a `minHeight: 44` frame while keeping the compact look.
- **Severity:** Medium

### 8.3 Narrow slots on small phones in landscape (unverified)
- **Location:** `QuickDiceOverlay.swift:19-27`, `GameScreenModel.swift` (`WidthValues.small = 300`)
- **What:** The overlay is `sideBarWidth` wide minus the trailing safe-area inset (59 pt on a notched phone in landscape) and 16 pt padding, so each of the four slots is about 56 pt wide. The roll label is scaled down to 60%, and the value button shows icon plus number.
- **Why:** The number may truncate at larger Dynamic Type sizes. The preview showed 68 pt per slot in portrait with the default size.
- **Action:** Check landscape and AX sizes. A fallback could hide the value icon (number only) below a width threshold.
- **Severity:** Low

### 8.4 Slot logic lives in views, so none of it is tested
- **Location:** `QuickDiceSlotView.swift:102-139` (override and apply), `:143-188` (game-dice reuse and manual value)
- **What:** CLAUDE.md says view logic belongs in view models so it can be tested. The tests cover only the plain `QuickDiceSlotsModel` and the reservation maths.
- **Why:** §5.3, §5.4 and §5.5 are all in this code. There is no test that a linked change clears the override or that the effective value reaches the dice.
- **Action:** Move "effective value = override ?? linked" and the "which dice id to use" decisions into a small `@MainActor` type (one per slot) with a testable inputs/outputs surface, and add Swift Testing cases for the override lifecycle.
- **Severity:** Medium

### 8.5 visionOS ornament: no background, and the anchor is shared (unverified)
- **Location:** `Modules/GameRPG/GameViews/GameScreenOrnaments.swift:47-55`, `QuickDiceOverlay.swift:28-32`
- **What:** `QuickDiceOverlay` applies its material background and shadow only `#if !os(visionOS)`. The ornament sits at `.scene(.bottomTrailing)` with `contentAlignment: .bottomLeading`, and `diceResultView` already uses `.scene(.bottomTrailing)` with `.topTrailing`.
- **Why:** The slots may float without a surface, and the two ornaments may overlap or crowd the volume handle. The visionOS notes in memory say `glassBackgroundEffect` is the one that works there.
- **Action:** Look at it in the simulator with the probe app, give the ornament a `glassBackgroundEffect()`, and move it if it collides.
- **Severity:** Low

### 8.6 Side effects while evaluating `body` for entry slots
- **Location:** `QuickDiceSlotView.swift:110-114`, `CharacterRPG/Controller/GameController+Dice.swift:28-44`
- **What:** `gameDiceId(itemId:entryId:)` creates the game dice and writes `gameDiceModel` (observable) on the first call, inside the view body. `EntryListDiceRow` does the same, and now up to four more views do.
- **Why:** State written during a view update can produce "modifying state during view update" warnings or an extra pass. After the first call the lookup is idempotent, so the risk is limited to the first render, and no warning appeared in the previews.
- **Action:** Leave the existing row; for the slot, resolve once in `.task(id:)` as the base-dice slot already does.
- **Severity:** Low

### 8.7 Accessibility of the overlay and slots
- **Location:** `QuickDiceOverlay.swift:15-36`, `QuickDiceSlotView.swift:96`
- **What:**
  - The overlay has no accessibility container or label, so VoiceOver reads four unrelated groups.
  - `.accessibilityLabel` on the `DropItemModuleArea` container may not apply to the inner button.
  - An overridden value has no visual or spoken marker.
- **Why:** The roll and value buttons do have labels, so the feature works; navigation is just unstructured.
- **Action:** Add `.accessibilityElement(children: .contain)` with a "Quick Dice" label to the overlay, put the slot label on the button itself, and mark an overridden value (for example in the value button's accessibility value).
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 `QuickDiceSlotsModel.prune(keeping:)` is dead code
- **Location:** `Modules/CoreRPG/Model/QuickDiceSlotsModel.swift:131-139`, only called from `Tests/CoreRPGTests/QuickDiceSlotsModelTests.swift`
- **What:** The plan had stale entry slots pruned on load; the implementation shows "Unavailable" instead, so nothing calls `prune`.
- **Why:** An API with a test but no caller. Also see §5.6.
- **Action:** Use it (§5.6) or delete it with its test.
- **Severity:** Low

### 9.2 The "player and not observer" rule is repeated seven times
- **Location:** `IOSGameOverlayMenu.swift:28, 56`, `OverlayGameMenu.swift:111, 166`, `GameToolbarContent.swift` (the `role == .player` block), `PlayerOverlayMenu.swift:17`, `GameScreenOrnaments.swift:48`
- **What:** Each site re-derives whether the quick dice toggle or overlay is offered.
- **Why:** A change (for example allowing observers or the GM) means touching all seven.
- **Action:** One computed property on `GameRoot` or `GameScreenModel` (for example "offers quick dice for role"), used by all of them.
- **Severity:** Medium

### 9.3 The roll logic and label of `DiceInline` are copied into `QuickDiceRollButton`
- **Location:** `Modules/DiceRPG/Game/Quick/QuickDiceRollButton.swift:18-40`, `Modules/DiceRPG/View/DiceInline.swift:119-142` and the private `DiceInlineLabel`
- **What:** Focus + `rollDice(... resultCategory)` + `donateRoll`, and the die-image label, exist twice.
- **Why:** The two will drift (for example a new roll side effect added to one).
- **Action:** Extract the "focus, roll and share" action into one `DiceRootModel` or `GameController` helper that both call, and share the label.
- **Severity:** Low

### 9.4 Duplicated toggle button, and an inconsistent parameter order
- **Location:** `GameQuickDiceToggleButton.swift` vs `GameDiceToggleButton.swift`; `IOSGameDiceToggleButtonField.swift` (two near-identical wrappers); `QuickDiceSlotsModel.swift:121-124` (`index(forEntry:in:)` takes entry then item, while `.entry(itemId:entryId:)` takes item then entry)
- **What:** Three near-copies of the same toggle plumbing, and an easy-to-swap argument pair.
- **Why:** Cosmetic duplication and a small footgun, since both are `UUID`.
- **Action:** One generic "overlay toggle" view parameterised by title and symbol; reorder the labels to item-first.
- **Severity:** Low

### 9.5 Preview-only copy of a mock id
- **Location:** `QuickDiceOverlay.swift:46-60`
- **What:** The "Filled slots" preview repeats the byte literal of `DiceModel.previewId`, because that id is internal to DiceRPG.
- **Why:** The preview breaks silently if the mock id changes.
- **Action:** Expose a public preview helper in DiceRPG, or leave with the existing comment.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

- **Make one place own "what value does this dice use".** §5.3, §5.4, §7.1 and §8.4 all come from the value being resolved in several views. A single per-slot type holding linked value, override and effective value fixes them together and makes them testable.
- **Settle the picker contract per platform in one place.** Sheet versus link-window-and-drop is decided in the slot view today (§5.1). Putting the drop target on the whole slot makes both paths work for every state.
- **Verify the feature once end to end.** Join as a player against a master (simulator plus a Mac), then run the checklist in §11. Most open items here are "looks fine in code, not seen running".

---

## 11. What was NOT audited

- Runtime behaviour in a real game: overlay layout beside a visible sidebar, iOS safe-area handling, animations, the sheet and popover presentation, the link-window drag on macOS and visionOS, the tvOS focus order, sharing a roll to the master and reading the log (§5.9).
- Deep SwiftUI-expert pass: the checks were applied inline from the skill's checklist, not through a separate `swiftui-expert-skill` run.
- Snapshot baselines: `Snapshots/Xcode27/GameRPGSnapshotTests/GameRPGGeneratedPreviewSnapshotTests` is empty, so no snapshot could regress. The `IOSGameOverlayMenu` player snapshot will show one extra button when baselines are recorded again.
- The old Docu audits and unrelated modules; localization wording (the German and Thai strings are my own, with the Thai marked `machine_translated`).
- Full test suites: only the two new suites were run.
- CloudKit, Core Data and App Intents: nothing in this change touches them.

---

## 12. Verification

No finding is Critical or High, so these are the lines that prove the Medium claims.

- **§5.1** — `QuickDiceSlotView.swift:31-48` offers "Choose Dice" for any filled slot; `:65-72` opens `NetworkModules.dice.linkWindowId` on macOS/visionOS; `:80` is the only `DropItemModuleArea`, inside `QuickDiceEmptySlotView` (`:74-97`).
- **§5.2** — `GenericGameController.swift:27-29` returns `itemOrEmpty(for:)` for an unknown id; `QuickDiceSlotView.swift:176-183` has no existence check before `createGameDice`; `QuickDiceUnavailableSlotView` (`:205-218`) is used only from `QuickDiceEntrySlotView` (`:132-134`).
- **§5.3** — `EntryListDiceRow.swift:24-31` runs `updateDiceValue` on `compareValue` (`initial: true`) and `id`; `QuickDiceSlotView.swift:109-131` keeps `overrideValue` in `@State` and clears it only on `linkedValue` changes.
- **§5.4** — `GameController.swift:240-246`, the `compareValue > 0` guard in `validateForValue`.
- **§8.1** — `QuickDicePicker.swift:14` (`NavigationStack`) around `LinkRootView`, whose `LinkItemListView.swift:37` builds `ManagedNavigationStack(name: "LinkInspector")`.
- **§8.2** — `QuickDiceValueButton.swift:36-38` (`.buttonStyle(.bordered)`, `.capsule`, `.controlSize(.small)`), no `minimumHitArea`.
- **§8.4** — `QuickDiceSlotView.swift:102-189` contains the override, `onChange` and game-dice code; `Tests/` has no test touching it.
- **§9.2** — grep of `!isMaster && … observer` and `offersQuickDice` finds the seven sites listed above.
