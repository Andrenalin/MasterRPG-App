# CharacterRPG audit (2026-11-14)

Read in full: all of Controller/ (GameController and its 3 extensions, EditController and its 3 extensions, LinkController, SheetController, SearchController, DataController, ExportController, ViewController, CharacterPackageVersion), Model/ (Calculator, ValueModel + LinkRegister + VersionDigest, ValueEntryModel, ValueSnapshot, DataModel+Extensions, PreviewData header), Root/ (CharacterRootModel, ViewerRootView, small roots), Route/, Intent/ (all five files), and the views that carry logic (AdditionalEntryRow, InlineRowViewer, EntryListDiceRow, QuickEntryEditor, CharacterAddEntryOverlay, DropChooseView, Dice/Photo drop sections, QuickDiceFavoriteMenu, Detail*). About 7.3k LOC, largest file 434 LOC (no split needed). Grep sweep for force unwraps, try!, as!, print, GCD, onTapGesture, foregroundColor, cornerRadius, GeometryReader, ObservableObject, Task.detached, @unchecked and TODO/FIXME found nothing in module code. All `@Observable` classes are `@MainActor`. The old CODE_AUDIT_Character Critical/High items (SheetController cycle guard, tautological type guard, SearchController depth guards, AddtionalEntryRow UUID) are fixed in the code as it stands. The module is in good shape; the findings below are residual and mostly Medium/Low. Calculator was read but its parsing was not re-derived beyond the existing test suite (ValueEntryModelTests covers precedence, negatives, rounding).

### Group-item repair keeps the first referencing entry, not the owner named by groupId
- Category: Bug
- Location: Modules/CharacterRPG/Controller/EditController+Repair.swift:165-196 (owner choice 170-177, stripping other owners 192-195, `removeOld` 198-213); the only test is Tests/CharacterRPGTests/ConvertControllerRepairTests.swift:601-624
- What: `repairGroupItemConstraints` sets `groupItem.groupId = owners.first` (first item in `itemDataModel.items` order with an entry whose `valueId` is the group) and clears the `valueId` of every other owner, without preferring the owner already recorded in `groupItem.groupId`.
- Why: If two Characters reference one group item (CloudKit merge, import, duplicate bug) and the real owner (matching `groupId`) is not first in item order, "Validate Folders" moves the group to the other character and removes the group entry from the real owner's sheet. The user loses a group row from the sheet they built, and the outcome depends on list order. The existing test is titled "non-authoritative owner" but passes only because the real owner is created first.
- Action: When `groupItem.groupId` is one of `owners`, keep it and strip the others; fall back to `owners.first` only otherwise. Add a test where the `groupId` owner comes second in item order.
- Severity: Medium
- Status: NEW

### Game dice instances are created and cached inside view `body`
- Category: SwiftUI
- Location: Modules/CharacterRPG/View/EntryListDiceRow.swift:20; Modules/CharacterRPG/Controller/GameController+Dice.swift:12-49 (`cachedGameDice` writes `gameDiceModel.gameEntryDiceId` / `gameDiceId` and calls `createGameDice`, which calls `setGame(item:)` in DiceRPG/Controller/GameController.swift:235-242); Modules/CharacterRPG/View/InlineRowViewer.swift:44; Modules/GameRPG/GameViews/QuickDice/QuickDiceSlotView.swift:120
- What: `EntryListDiceRow.body` calls `gameDiceId(itemId:entryId:)`, which reads and then writes the `@Observable` `ValueGameModel` and inserts a new dice into the game item store the first time (and again whenever the dice template id changes).
- Why: Mutating observable state that the same body just read is the "modifying state during view update" pattern; it forces a second render pass and is order-dependent. When the entry's `diceId` changes, the old game dice stays in `gameModel.itemData` forever (only `removeBattleCharacterCopies` and `resetGameDiceId` clear the maps, neither deletes the dice item), so the game store grows with every re-link. CLAUDE.md asks for view logic in testable models.
- Action: Resolve or create the game dice outside `body` (on game start, on `diceId` change via `.task(id:)`/`onChange`, or in the controller when the entry is edited) and let `body` only read; delete the superseded game dice when the template id changes.
- Severity: Medium
- Status: NEW

### SheetController.update(entry:) re-projects each entry's whole subtree on every update, then updates it again
- Category: Performance
- Location: Modules/CharacterRPG/Controller/SheetController.swift:204-264 (full re-projection at 212, recursive `update` of children at 251-255); info logs at 141 and 184
- What: For every existing entry the update path calls `sheet(entry:)`, which rebuilds the entire group sub-value tree and all link sheets from scratch (plus `linkController.calculate` and `linksFrom` per entry), only to diff it against the existing model and then call `update(...)` on each matched child, which re-projects its own entries once more.
- Why: Each nesting level rebuilds everything below it, so a group-in-group sheet does O(depth x size) work on the main actor for every observed change (typing, dice roll, game sync). Each `update` also emits two `info` log lines with an emoji and a measured duration.
- Action: Project only name, description, editType, sheetType and the entry's inline dice for the entry itself and reconcile children by source id without building their subtrees; log at debug level or drop the timing.
- Severity: Medium
- Status: NEW

### AdditionalEntryRow's Equatable ignores the entry and text model its body reads
- Category: SwiftUI
- Location: Modules/CharacterRPG/View/AdditionalEntryRow.swift:6-83 (`==` at 80-82; icon from `entry` at 69-78); wrapped with `.equatable()` at Modules/CharacterRPG/Controller/EditController.swift:144; caller Modules/CoreRPG/LGViews/EntryEditRow.swift:43-59
- What: `==` compares only `entryId`, yet `typeIcon` is derived from the passed-in `entry` value and the body renders `textModel`.
- Why: When an entry's type changes (text to number to decimal, or to a group) the row's `entry` struct changes but the views compare equal, so SwiftUI keeps the old value and the type icon can stay stale until the row identity is recreated. The earlier audit fixed the same shape in `InlineRowViewer` (now compares `source` and `destination`) but this row only had its UUID fixed. Not reproduced at runtime.
- Action: Include `entry` (it is `Equatable`) and the identity of `textModel` in `==`, or read the type from the observed model instead of the passed value. Verify with the type picker.
- Severity: Medium
- Status: NEW (unverified at runtime)

### Share-extension characters get photos but no portrait
- Category: Bug
- Location: Modules/CharacterRPG/Controller/CharacterDataController.swift:10-25 (`model.photos = photoIds`, `photoId` never set); consumers use `photoId`: Modules/CharacterRPG/Controller/SheetController.swift:42, View/ThumbnailPhotoRow.swift:14, Controller/GameController.swift:202; caller Sources/RPGShare/ShareExtensionSaveController.swift:102-103; test Tests/CharacterRPGTests/DataControllerTests.swift:132-153 asserts `photos` only
- What: A Character created from the share sheet stores the shared images in `photos` but leaves the portrait `photoId` nil, whereas the module's own rule (`EditController.add(selection:)`) is that the portrait is the first photo. The Map share path passes `photoIds.first` as its photo.
- Why: The new character shows no thumbnail, no portrait in the sheet and no player-pin photo until a manual photo edit or a Validate Folders run (`repairPhotoList`) fixes it.
- Action: Set `model.photoId = photoIds.first` in `addNewValue` and extend the test to assert it.
- Severity: Medium
- Status: NEW

### Validate Folders re-adds an item-level dice the user removed
- Category: Bug
- Location: Modules/CharacterRPG/Root/CharacterRootModel.swift:296-301 (with `EditController.removeDice(itemId:)` at Controller/EditController.swift:252-256)
- What: For every non-group character with `diceId == nil`, `checkFolders` sets the item dice to the dice of its first entry that has one.
- Why: The editor offers "Remove Dice" for the character's own dice; the next repair run silently puts a dice back, so the removal does not stick. `GameController.focusDice` already falls back to the first entry dice at runtime (GameController.swift:190), so the repair adds nothing functionally.
- Action: Drop the auto-assignment, or only do it for items that never had an item dice (needs a marker); at minimum document it as intended.
- Severity: Low
- Status: NEW

### gameEntryDisplayValue formats non-integers with string interpolation
- Category: Bug
- Location: Modules/CharacterRPG/Controller/GameController+EntryResolution.swift:172
- What: `"\(number)"` for a non-integer `Double`, while the rest of the module moved to `Calculator.formatNumber` / `ValueEntryModel.modifierText` because interpolation prints `1e-05` for small values.
- Why: Same class as CODE_AUDIT_25 §5.3 (fixed in `ValueEntryModel.calculate`); this site was missed. The string is shown to players and can be fed back into the calculator.
- Action: Use `Calculator.formatNumber(number)`.
- Severity: Low
- Status: NEW

### SearchController.result(item:) entry branch is unreachable
- Category: Dead code
- Location: Modules/CharacterRPG/Controller/SearchController.swift:42-45 (only call site, folders and collections only), 71-113 (`if !item.specialCategory` at 82 and the recursion at 107-110 can never run); doc comment 25-29 says it "searches the collection's children entries"
- What: `globalSearchResults` calls `result(...)` only for `specialCategory` items, and `result` searches entries and recurses into group sub-values only for items that are not `specialCategory`.
- Why: About 30 lines (entry matching, group recursion, the `depth` parameter and its CODE_AUDIT_Character §5.3 guard) are dead, and the comment misdescribes what folders do in global search (only the folder's own name/description match is checked; characters inside folders are found by the main loop).
- Action: Delete the dead branch and the depth parameter, or, if entry search was intended for global search, call it for regular characters and add a test; fix the comment either way.
- Severity: Low
- Status: NEW

### InlineRowViewer.diceSource mints a random entry id and can never remap
- Category: Dead code
- Location: Modules/CharacterRPG/View/InlineRowViewer.swift:35-37, 43-48
- What: The `else` branch (taken only when `destination.entryId == nil`) calls `gameDiceId(itemId:entryId: destination.entryId ?? UUID())`, so the entry id is always a fresh random UUID.
- Why: The lookup always misses (`gameItem(for:)[randomId]` is an empty entry with no dice) and `diceSource` always returns `source`; the call is pure overhead in `body` and the remapping it suggests never happens.
- Action: Return `source` directly for the `entryId == nil` case and drop `diceSource`'s game lookup.
- Severity: Low
- Status: NEW

### Preview and mock fixtures ship in Release and are duplicated
- Category: Refactor
- Location: Modules/CharacterRPG/Model/PreviewData.swift:10-270 (only lines 50-66 are under `#if DEBUG`; `ValueModel.preview` at ~116-124 duplicates the first two models of `previewFixtures` at ~134-160); Modules/CharacterRPG/Model/MockData.swift (SwiftData `ModelContainer`, no DEBUG guard); `RPGResources` is imported for preview data only
- What: Public preview roots and fixture models are compiled into the Release framework, and the same two fixture models are spelled out twice.
- Why: Larger binary, a SwiftData dependency and preview-only wiring in production, and two copies to keep in sync. CLAUDE.md puts preview and mock fixtures behind `#if DEBUG`. Other modules follow the same pattern (AdventureRPG/Model/PreviewData.swift uses `CharacterRootModel.preview`), so a fix has to be repo-wide.
- Action: Wrap PreviewData/MockData in `#if DEBUG` per module (check that `#Preview` blocks and tests build) and build `preview` from `previewFixtures`.
- Severity: Low
- Status: NEW

### AnyView in four ViewControllable/EditControllable overrides
- Category: API
- Location: Modules/CharacterRPG/Controller/ViewController.swift:13-26 (4 sites); Modules/CharacterRPG/Controller/EditController.swift:143-145
- What: Five `AnyView` wrappers around `.equatable()` rows.
- Why: CLAUDE.md says to avoid `AnyView`; these exist because the CoreRPG protocols (`rowViewer`, `thumbnailRowView`, `additionalRowView`) return `AnyView`, so they cannot be changed in this module alone.
- Action: If the protocols are touched anyway, make them return `some View` via associated types or a type-erased wrapper owned by CoreRPG; otherwise leave.
- Severity: Low
- Status: NEW

### Test gaps
- Category: Test gap
- Location: Tests/CharacterRPGTests (SheetControllerTests.swift, ConvertControllerRepairTests.swift)
- What: No test covers `repairGroupItemConstraints` with the `groupId` owner second in order; nothing asserts that `SheetController.update` on a nested group does not rebuild subtrees (only behaviour is asserted); `checkFolders` re-adding the item dice is untested either way; no test pins the share-extension portrait.
- Why: The first of these is the data-loss path in the Medium repair finding above.
- Action: Add the owner-order test with that fix; add the portrait assertion to `characterDataControllerCreatesTrimmedValue`.
- Severity: Low
- Status: NEW

Not audited in this area: Resources/ string catalogs (translations), the CoreData model file, and CoreRPG generic implementations that the module delegates to (`GenericFolderListController`, `GenericImportController`, `EntryDataEditable` defaults, `ItemEntityQuery`); Calculator regex semantics beyond what the existing tests pin; App Intents behaviour at runtime (already covered by CODE_AUDIT_AppIntents*.md); runtime behaviour of the SwiftUI findings (nothing was built or run).
