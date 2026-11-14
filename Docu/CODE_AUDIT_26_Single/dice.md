# DiceRPG module audit (2026-11-14)

Scope: Modules/DiceRPG, 76 Swift files, ~7.9k LOC. Read in full: Model (DiceModel, DieModel, RawDie, RawDice, RawDieCounter, DiceExpression, DiceResultModel, DiceSnapshot), Controller (GameController + DiceResult + PlayerDice, DataController, EditController, LinkController, ViewController, ItemController), Root/DiceRootModel, Widget/DiceConfiguration, Intent (DiceIntents, RollSpecificDiceIntent, DiceManagementIntents, DiceEntity, OpenDiceIntent), all Game/ views, the View/ views, the Dice/ editors (Option, Special, Reroll, SpecialValue), Route and Root views. Also read CoreRPG pieces they depend on (CRDTDataUpdate, TextIntEditor/TextDoubleEditor, NumericViewModifier, GenericGameController, ItemControllable+Sync). Overall health: good. The module is clean against the CLAUDE.md rules (no GCD, no ObservableObject, `@MainActor` on every `@Observable`, `Task.sleep(for:)`, no 1-parameter onChange) and the earlier audits' fixes are in place. The real problems are semantic: the compare/"Check for" option is never evaluated on its own, the editor's dice bag appends the same die identity on every tap, and a handful of state leaks around the shared game dice model. Nothing here is a crash on a normal path. Previously fixed items (CODE_AUDIT_Dice, CODE_AUDIT_QuickDice, CODE_AUDIT_25) were not re-reported.

### Dice bag in the editor appends the same die (same id) on every tap
- Category: Bug
- Location: Modules/DiceRPG/View/DiceBag.swift:11-22 (static catalog with fixed ids) and :56-60 (`root.editController.add(die: die, ...)`); Modules/DiceRPG/Controller/EditController.swift:14-19 (`editModel.dice.append(die)` with no `duplicate()`)
- What: `DiceBag` passes the catalog's static `DieModel` straight to `add(die:)`. Tapping "d20" three times (the usual way to build "3d20") puts three dice with one identical `id` into the model. `GameDiceBag` does it right (`generateDie` makes a new UUID); the intent path builds a fresh die.
- Why: Everything keys on die id: `ForEach(model.dice)` in `DiceViewer` (duplicate identities), `remove(die:)`/`resetDie`/`roll(die:)` use `firstIndex(where: id)` so tapping the second die removes, rolls or resets the first one, `GameController.resultColor`/`diceSuccess` look up by die id so all duplicates show the first die's success colours, and `DieViewerView`'s rotation reset writes into the first die. The duplicate ids only disappear after a reload because `DataController.dice(from:)` hands out new UUIDs (so the bug heals on relaunch or a CloudKit refresh, which hides it in testing). The CODE_AUDIT_Dice §7.2 fix (making the catalog `static`) made the ids stable across redraws, which also made repeated taps within a session collide.
- Action: In `DiceBag` (or `EditController.add(die:)`) store `die.duplicate()`/a fresh-id copy. Add a test that two `add(die:)` calls with the same input give distinct ids.
- Severity: High
- Status: NEW

### The compare option and value are never evaluated unless "Add dice" is on
- Category: Bug
- Location: Modules/DiceRPG/Controller/GameController+DiceResult.swift:37 (`checked = sumResult > 0`) and :147-155 (`maxValuePerDice`); Modules/DiceRPG/Dice/DiceOptionEditor.swift:26-32; Modules/DiceRPG/Model/DiceModel.swift:184-197 (`CompareValue.check(value:against:)`, no caller in Modules, Sources or Tests)
- What: `calculate` marks a roll as checked when the sum is above 0. `compareOption`/`compareValue` only act through `maxValuePerDice`, which returns the die maximum unless `addDiceEvery > 0` (the DSA-style "roll under per die" mode). The editor offers "Check for < <= >= >" with a value independently of "Add dice".
- Why: A d20 with "Check for <= 15" and no Add dice shows `...<=15 ∑12 ✅` for every roll: the result text, the checkmark in `DiceGameResult`/`DicePlayer`, the Quick Dice value button tint, the success/failure haptic, the widget's `checked` and the statistics event (`GameStatisticsController`) all say success. The git history shows `check(value:against:)` once existed for exactly this and was orphaned.
- Action: Decide the intended semantics. Either evaluate `compareOption.check(...)` against the sum (or per die) when `addDiceEvery == 0` and use it for `checked`, or hide the "Check for" section unless Add dice is active, then delete the dead method. Add a test with a compare-only dice (existing tests only cover the `addDiceEvery` set-up).
- Severity: High
- Status: NEW

### A d3 built from text or a number is `.number(3)`, not `.three`
- Category: Bug
- Location: Modules/DiceRPG/Model/RawDie.swift:143-164 (`Sides.sides(_:)` has no `case 3`), against :195 (decoder maps 3 to `.three`); callers Modules/DiceRPG/Controller/DataController.swift:147, Modules/DiceRPG/Model/DieModel.swift:210, Modules/DiceRPG/Model/DiceExpression.swift:57,68, Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+DiceAndValues.swift:57
- What: `RawDie(text: "d3")`, `.sides(3)` (Siri "3d3", widget, Foundry import) give `.number(3)`; the d3 from the bag and the JSON decoder is `.three`. They are not `==`.
- Why: After every Core Data reload (`dice(from:)` uses `RawDie(text:)`) a bag d3 turns into `.number(3)`, whose `colorCodes` is only `[.G]` and whose `name(for:)` returns the d20 image "D20G-1", so the die silently shows a d20 face. `RawDice.addDie` merges counters by `sides ==`, so "d3" from the editor plus "d3" from an expression is shown as "d3+d3". `DieModel.isSame` (die == die) reports a change between a local and a synced d3.
- Action: Add `case 3: return .three` to `sides(_:)` (or normalise in `RawDie.init`). Add a text -> RawDie -> text -> RawDie round trip test for every named side count.
- Severity: Medium
- Status: NEW

### Roll haptic fires up to three times per roll and the first is always an error
- Category: Bug
- Location: Modules/DiceRPG/Game/Detail/DiceGameActionBar.swift:47-56; Modules/DiceRPG/Controller/GameController+PlayerDice.swift:86-113 (`rollDice` resets first, rolls 0.1 s later); Modules/DiceRPG/Game/Detail/DieViewerView.swift:54-65 (rotation reset 0.6 s later writes `dice` again)
- What: The `.onChange(of: gameItem.dice)` that drives `rollFeedbackCount` observes the whole `[DieModel]`. A roll changes it three times: `reset(for:)` (results cleared; `result.checked` is false for "not rolled"), the roll itself, and `DieViewerView`'s delayed `rotation = 0` write.
- Why: When the previous roll had results, every tap plays an error haptic at once, then the real outcome, then the same outcome again. The CODE_AUDIT_Dice §5.6 fix (watch `dice`) made the haptic fire, but on the wrong set of changes. Reading only; not device-verified.
- Action: Trigger the haptic from the roll itself (in the button action / `rollFunction` after the results exist) or compare `results` only and skip the all-empty state; ignore rotation-only changes.
- Severity: Medium
- Status: NEW

### Tapping a single die replaces the dice's result category with a generic one
- Category: Bug
- Location: Modules/DiceRPG/Game/Detail/DiceRoll.swift:50-54 (`ResultCategory(id: itemId, module: .dice)`); Modules/DiceRPG/Controller/GameController.swift:172-182 (`createDiceResult` stores the category on the model); compare Modules/DiceRPG/Controller/GameController+PlayerDice.swift:118-124 (`shareRoll` keeps `resultCategory ?? item.resultCategory`)
- What: `DiceRoll.rollDice(_:)` hard-codes a `.dice` category and `createDiceResult` writes it into `item.resultCategory`. A dice linked from a character sheet had that character's category (set by `DiceInline`/Quick Dice through `rollDice(resultCategory:)`).
- Why: After one tap on an individual die in the overlay, later rolls of the whole set (which fall back to `item.resultCategory`) and the shared result are attributed to the dice module instead of the character. `ResultCategory` is what the table and battle round use to associate a roll with its participant (see DiceSnapshot.resultCategory doc), so initiative/health-style rolls stop landing on the character.
- Action: Use the same `shareRoll(of:networkActions:)` path as `rollDie(_:of:networkActions:)` (keeps the stored category) and do not overwrite `item.resultCategory` when none is passed.
- Severity: Medium
- Status: NEW

### `createGameData(for:resultCategory:)` swaps the model's category across an await
- Category: Concurrency
- Location: Modules/DiceRPG/Controller/GameController.swift:184-198
- What: It reads `oldResultCategory`, writes the new category on the shared model, awaits `createGameData`, then writes the old one back.
- Why: Two overlapping calls for the same item (a share-to-all from `DiceInline` while a roll share runs, or two quick "Share to player" taps) interleave. The second call captures the first call's temporary category as "old" and restores it, so the temporary category stays on the model and is attached to later shares.
- Action: Pass the category into the export instead of mutating the model, or serialise per item.
- Severity: Medium
- Status: NEW

### Rolling a library dice outside a game mutates the synced model
- Category: Bug
- Location: Modules/CoreRPG/Controllable/GenericGameController.swift:27-29 (`gameItem(for:)` falls back to the library item); Modules/DiceRPG/Controller/GameController+DiceResult.swift:213-243 (`reset(for:)`, `roll(die:for:)`); Modules/DiceRPG/View/DiceInline.swift:21-30; Modules/DiceRPG/Root/DetailRootView.swift:20-26; Modules/DiceRPG/Controller/LinkController.swift:18; Modules/DiceRPG/Intent/DiceIntents.swift:122-127
- What: With no game running, `DiceInline`, the Space-bar roll, roll links and the roll intents call `rollDice` on a dice that is not in `gameModel.itemData`, so `gameItem(for:)` returns the library `DiceModel` itself and the roll writes results and a random rotation into its `dice` (and thus a fresh `dice_.update` LWW stamp).
- Why: `DiceModel.merge` arbitrates every plain field (modifier, compare, coup, reroll, ...) by `mergedDice.update`. A roll made after another device's edit but before that edit syncs gives the local copy the newer stamp, so the remote change to modifier/coup/rerolls loses the merge. Roll results also appear in the dice list thumbnails and in `isSame` comparisons. Not verified end to end (depends on the offline timing), the mutation itself is verified by reading.
- Action: Roll on a game copy (`createGameDice`) or clear results without touching `dice_` (keep results outside the CRDT value); at minimum make the roll not bump the update marker.
- Severity: Medium
- Status: NEW

### A roll shares the whole DiceSnapshot (description, tags, entries) with every player
- Category: Security
- Location: Modules/DiceRPG/Controller/GameController.swift:172-182 (`createDiceResult` builds `DiceResultModel` from `DiceSnapshot(item)`); Modules/DiceRPG/Model/DiceSnapshot.swift:7-40; Modules/DiceRPG/Controller/GameController+DiceResult.swift:12-14
- What: `DiceResultModel` carries the full snapshot, including `description_`, `tags_`, `entries_` and `parentId` of the GM's dice, and `shareRoll` broadcasts it (`.generic`, no target).
- Why: A game master's dice description is free text and may hold notes ("boss phase 2 damage, only if ..."). Players do not see it in the overlay (`addGameDiceResult` replaces the name with the player's name), but the data is on their devices and in the master's relayed messages. Receivers only need the dice, options and results.
- Action: Send a reduced snapshot for rolls (dice, options, resultCategory; blank description, tags, entries, parentId), or strip those fields in `DiceResultModel.init`.
- Severity: Medium
- Status: NEW

### `resetPlayerDice(to:)` maps by display name and can duplicate a player's dice
- Category: Bug
- Location: Modules/DiceRPG/Controller/GameController.swift:289-301; callers Modules/GameRPG/Controller/MasterController+Control.swift:88, Modules/GameRPG/Controller/PlayerController+Control.swift:87
- What: `compactMap { name in playerDice.first { $0.name == name } }` returns the first match for each name, although `addGameDiceResult` deliberately lets two same-named devices keep separate dice (`playerDiceSenders`).
- Why: With two players of the same name the list ends with one `DiceModel` twice and drops the other (duplicate `ForEach` identity in `DicePlayer`). `isPlayerHidden`/`toggleHidden` also key on the name, so hiding one hides both.
- Action: Reset by sender id or de-duplicate by dice id; key `hiddenPlayers` by sender id.
- Severity: Low
- Status: NEW

### A die keeps only its first 100 results, so the 101st tap silently does nothing
- Category: Bug
- Location: Modules/DiceRPG/Model/DieModel.swift:54-65 (`boundedResults` uses `prefix`) and :175-196 (`roll` returns `DieModel(... result: result + rollResult)`)
- What: Single-die taps (`DiceRoll`, `rollDie`) append to `result`; the initializer then truncates to the first 100, dropping the newest.
- Why: After 100 taps on one die its displayed value (`result.last`) and sums never change again until "Roll dice" resets. Low likelihood, but the bound should drop the oldest.
- Action: Keep the suffix (`suffix(maximumResultCount)`) when bounding rolled results.
- Severity: Low
- Status: NEW

### Typed values in the number editors bypass the slider ranges and `Int(Double)` can trap
- Category: Bug
- Location: Modules/CoreRPG/Editors/TextIntEditor.swift:82-87 and Modules/CoreRPG/Editors/TextDoubleEditor.swift:~123-130 (submit assigns the typed value unclamped); used with ranges at Modules/DiceRPG/Dice/DiceOptionEditor.swift:20,31 (modifier -10...10, compare 1...41), Dice/RerollEditor.swift:124,156, Dice/SpecialValueEditor.swift:130, Dice/SpecialOptionEditor.swift:49; conversions `Int(...)` at Modules/DiceRPG/Dice/RerollEditor.swift:46, Dice/SpecialValueEditor.swift:135, Modules/DiceRPG/Controller/EditController.swift:87
- What: The range only limits the slider. A typed modifier of 5000, a compare value of 900 or a reroll number beyond the die's faces is accepted. `TextIntEditor` parses `Int(text)` then stores `Double(value)`; a 19-digit entry near `Int.max` rounds to 2^63 and the later `Int(rerollValue)` traps.
- Why: The module's decode-side bounds (`DiceModel.boundedValue`, `maximumDiceCount`) show these ranges are intended limits. The trap needs an exact 19-digit entry, so it is unlikely but cheap to remove. Fractions in the modifier field (shown as 2.5) are applied truncated (`saturatingInt`).
- Action: Clamp to the editor's `range` on submit; convert with `Int(exactly:)`/the existing `saturatingInt`; round the modifier to an integer in `reset(modifier:)`.
- Severity: Low
- Status: NEW

### No upper bound on dice added through the editor or intents, but decoding keeps only 1,000
- Category: Bug
- Location: Modules/DiceRPG/Controller/EditController.swift:14-19; Modules/DiceRPG/Intent/DiceManagementIntents.swift:96; Modules/DiceRPG/Model/DiceModel.swift:359-365
- What: `add(die:)` appends without a limit while `bounded(dice:)` truncates to `maximumDecodedDiceCount` (1,000) on every decode (peer package, `.gmz`).
- Why: A set that grows past 1,000 (for example a repeating "Add Die to Dice" shortcut) is silently cut on the player's device and after import, and rendering/animation of that many dice is unusable long before.
- Action: Refuse `add(die:)` at the limit (UI disables the bag, intent returns a dialog).
- Severity: Low
- Status: NEW

### Result computation repeated several times per view body
- Category: Performance
- Location: Modules/DiceRPG/Game/Detail/DiceGameResult.swift:49-66 (`result(itemId:)` twice plus `resultText`, which calls it again); Modules/DiceRPG/Game/Detail/DicePlayer.swift:112-118 and :80-83; Modules/DiceRPG/Controller/GameController+DiceResult.swift:12-40 (each call builds a `DiceSnapshot` and re-sorts via `reorder`)
- What: Each body evaluation of the overlay computes the full `DiceResultModel` (snapshot copy, sums, `reorder`, `diceSuccess` per die, which itself calls `fumble` and `reorder` again) three to five times per player row and per die in `DieViewerView`'s `resultColor`.
- Why: Not slow for a handful of dice, but with 10+ players each re-render of the overlay during a roll animation (rotation and result changes) is O(players x dice x rerolls) several times over, on the main actor.
- Action: Compute `result` once per row/body (`let result = ...`), and give `DieViewerView` a precomputed colour array per set instead of a per-die `diceSuccess` lookup.
- Severity: Low
- Status: NEW

### `InlineRowViewer` equality ignores `destination`
- Category: SwiftUI
- Location: Modules/DiceRPG/View/InlineRowViewer.swift:22-24
- What: `==` compares only `source`, but `destination` supplies `ResultCategory(source: destination)` for the roll.
- Why: Reusing the viewer for the same dice under another sheet row (moving/duplicating an entry, rebinding) keeps the old category in the button, attributing the roll to the wrong character or table.
- Action: Compare `destination` as well.
- Severity: Low
- Status: NEW

### Share menu in `DiceInline` swallows errors with `try?`
- Category: Bug
- Location: Modules/DiceRPG/View/DiceInline.swift:46-47 and :56-58
- What: Both share actions use `try? await createGameData(...)` and silently do nothing on failure; `LinkController` logs the same failure.
- Why: A failed share looks like a dead button.
- Action: Log the error (`Logger.linkController.error`) as the link path does.
- Severity: Low
- Status: NEW

### Dead code
- Category: Dead code
- Location: `DiceModel.CompareValue.check(value:against:)` Modules/DiceRPG/Model/DiceModel.swift:184-197; `ViewController.gameDiceHeight(root:)` and `width(for:maxWidth:)` Modules/DiceRPG/Controller/ViewController.swift:132-153 (only Tests/DiceRPGTests/ViewControllerTests.swift calls them); `DiceGameStorable.number(for:result:)` / `GameController.number` Modules/DiceRPG/Controller/GameController.swift:79,273 (only a test); unused parameters `DicePlayer.filterout` (Modules/DiceRPG/Game/Detail/DicePlayer.swift:7, passed from DiceOverlay.swift:109 and DicePlayerRoot.swift:36) and `DiceGameResult.canShowPlayer` (Modules/DiceRPG/Game/Detail/DiceGameResult.swift:8); unused environment values `appGameStateModel`, `networkActions` in Modules/DiceRPG/Game/DiceOverlay.swift:13-15 and `canShowPlayer`-style plumbing in `FocusedDiceContainer` callers; `toggleHidden` is `async` without an await (GameController+PlayerDice.swift:48)
- What: Members with no production caller (verified by repo-wide grep of Modules, Sources, Tests).
- Why: Misleads readers (the compare check in particular, see above) and widens the protocol surface (`DiceGameStorable`).
- Action: Delete, or wire `check(value:)` in as part of the compare fix. Remove the unused parameters.
- Severity: Low
- Status: NEW

### DiceModel.swift is 712 lines
- Category: Refactor
- Location: Modules/DiceRPG/Model/DiceModel.swift
- What: One file holds the class, the nested option types, bounds helpers, merge/diff, ItemDataAccessible, Codable and Hashable.
- Why: Oversized (CODE_AUDIT_25 lists it); the audit CODE_AUDIT_Dice §9.9 deferred the split.
- Action: Split along the existing MARK sections into `DiceModel.swift` (stored state and init), `DiceModel+Options.swift` (CompareValue, CoupFumbleOption, RerollOption), `DiceModel+Merge.swift` (merge/isSame/duplicate), `DiceModel+Codable.swift`, `DiceModel+ItemData.swift`.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_Dice §9.9]

### Preview fixtures still compile into Release
- Category: Dead code
- Location: Modules/DiceRPG/Model/PreviewData.swift:136-319 (fixtures `diceCoC`, `diceERPS`, `previewDisplay*`, `previewBagDice`, only `previewWithData`/`testRoot` are `#if DEBUG`); Modules/DiceRPG/Model/MockData.swift (SwiftData `PreviewModifier`)
- What: Most fixture data is ungated; `DiceModel.previewSnapshot` is also used as the production widget default (Modules/DiceRPG/Widget/DiceConfiguration.swift:147,194).
- Why: Release size only; the widget default should not depend on the preview fixture.
- Action: Give `DiceConfiguration.default` its own small default dice and gate the rest of the fixtures with `#if DEBUG`.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_Dice §9.10]

### Views split via helper methods instead of View structs
- Category: SwiftUI
- Location: Modules/DiceRPG/Game/Detail/DicePlayer.swift:46-83 (`playerButton`, `playerDice(playerId:)`); Modules/DiceRPG/View/DiceBag.swift:57-72 (`diceBagView(for:)`)
- What: `@ViewBuilder` functions return sub-views, which CLAUDE.md asks to be separate `View` structs.
- Why: Rule violation; also share the parent's invalidation boundary (relevant for the player rows, see the performance finding).
- Action: Extract `DicePlayerRow`, `DicePlayerButton`, `DiceBagRow`.
- Severity: Low
- Status: NEW

### Test gaps
- Category: Test gap
- Location: Tests/DiceRPGTests
- What: No test covers: compare-only dice results (`checked`), unique die ids after repeated `add(die:)`/bag taps, text round trip of `RawDie` for d3, the `createGameData(resultCategory:)` restore under overlap, `resetPlayerDice` with duplicate names, or the roll haptic trigger.
- Why: Each of these is a bug above that the existing suites cannot catch (existing GameController tests always set up `addDiceEvery`).
- Action: Add the five tests together with the fixes.
- Severity: Low
- Status: NEW

Not audited in this area: the DiceRollerWidgetExtension sources under Sources/DiceRollerWidget (only the module-side `DiceConfiguration`/snapshot types were read), the Core Data model file and CloudKit schema, the localisation catalogs, snapshot tests, `Resources/` art assets, and the Quick Dice slot model and views that live outside Modules/DiceRPG (only the DiceRPG-side `QuickDiceRollButton`/`QuickDiceValueButton`/`QuickDicePicker` were read). Intent behaviour was read but not run (Siri/Shortcuts runtime paths unverified). No UI was verified at runtime; the haptic and overlay findings are from reading.
