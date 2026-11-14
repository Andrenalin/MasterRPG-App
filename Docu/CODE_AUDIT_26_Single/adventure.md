# AdventureRPG audit (2026-11-14)

Files read: all of Modules/AdventureRPG (Model, Controller, Root, Route, Intent, View, Menu; ~4.3k LOC, nothing skipped except Resources/xcstrings) plus the CoreRPG pieces they lean on (GroupableEntryEditing, EntryDataEditable, ExportControllable, SearchControllable, CRDT) and Tests/AdventureRPGTests (test names and targeted greps). Overall health: good. The module is thin (most behaviour lives in CoreRPG generics), concurrency is clean (all `@Observable` types are `@MainActor`, no GCD, no `@unchecked`), and most items of the 2026-09-17 Docu/CODE_AUDIT_Adventure.md are visibly fixed in code (visited-set in `collectLinks`, folder union merge, `.private` logging, dead `validate()` removed, `Int16(clamping:)`, TaggedIdRoute, siblingModuleRoots, GenericItemController, static-member shapes). That older document has no status section, so the leftovers are listed below as OPEN. The real weak spot is that the export graph does not follow this module's own group links. Counts: 1 High, 5 Medium, 9 Low.

### Export and game reveal do not follow group entries (entry.adventureId)
- Category: Bug
- Location: Modules/AdventureRPG/Controller/ExportController.swift:63-128 (BFS visit closure); Modules/CoreRPG/ItemList/GroupableEntryEditing.swift:14-60 (how groups are created, entry content is only a copy of the description); Modules/CoreRPG/Controllable/GameControllable.swift:300 (reveal uses `exporting(ids:)`); compare Modules/CharacterRPG/Controller/ExportController.swift:70-72 (adds `entry.valueId` to the BFS)
- What: `exporting(itemIds:)` walks only links found in entry content and folder members; the hidden group adventure that an entry stands for (`adventureId`, created by addNewGroup/convertToGroup/moveIntoGroup) is never added, whereas Character does follow `valueId`.
- Why: Revealing or sharing a single adventure (game `createGameData`, single-item .gmz export, "send to player") ships the parent without its group children. On the receiving device `SheetController.entryNameDescription` (SheetController.swift:34-39) resolves the missing group to an empty model, so the group entry shows blank name and text. `exportingAll` is unaffected (groups are only groupHidden, not totalHidden) and `ExportControllerTests` only covers link-based children, which is why nothing caught it.
- Action: Add `entry.adventureId` (when it resolves via `itemSync`) to `childIds` in the visit closure, and add a test mirroring Character's group-export test (export one adventure with a group entry, expect the group id in the result).
- Severity: High
- Status: NEW (traced by reading export + sheet code, not reproduced at runtime)

### Adventure `diceId` is never exported
- Category: Bug
- Location: Modules/AdventureRPG/Controller/ExportController.swift:63-76 (photoId and tablePlayers handled, diceId not); compare Modules/CharacterRPG/Controller/ExportController.swift:50-52 and Modules/MapRPG/Controller/ExportController.swift:65,111
- What: `item.diceId` is not collected into `diceIds`; the dice only travels when it is also linked in entry text.
- Why: A single-adventure .gmz or shared package arrives with a `diceId` pointing at nothing, and `validateLinks` later clears it (LinkController.swift:116-120), so the GM's attached dice is silently lost on the receiving device. (For the players audience it may be deliberately GM-only; the code does not say.)
- Action: Insert `item.diceId` (after `validateLink`) into `diceIds`, skipping it when `ExportAudience.current == .players` if it is meant to be GM-only; document the decision.
- Severity: Medium
- Status: NEW

### Group entry edits write the raw entry name into the group item
- Category: Bug
- Location: Modules/AdventureRPG/Controller/EditController.swift:95-103 (`update(itemId:entryId:name:content:forceSave:)`); compare Modules/CharacterRPG/Controller/EditController.swift:310-313 (`name.withoutLink()`) and Modules/CoreRPG/ItemList/GroupableEntryEditing.swift:49 (also strips)
- What: For an entry with `adventureId`, `reset(name: name, itemId: adventureId)` is called with the unstripped `name`, while every other group path (convertToGroup, Character's update) uses `withoutLink()`. The sheet presents group entry names as `adventure.url(linkNumber: 0)` (SheetController.swift:35), i.e. a markdown link.
- Why: If the editor hands that link text back as `name`, the group adventure's own name becomes `[Name](RPG://ADVENTURES/...)`, a self-referencing link in its title, in lists and in Spotlight. Not reproduced; there is no test of `update` on a group entry in AdventureRPGTests.
- Action: Use `name.withoutLink()` for the group item (as Character does) and add a test with a group entry whose name carries the link form.
- Severity: Medium
- Status: NEW (unverified at runtime)

### `diceId` merges by direction instead of by timestamp
- Category: Bug
- Location: Modules/AdventureRPG/Model/AdventureModel.swift:95 (`public var diceId: UUID?`), :204 (`diceId: other.diceId`), :313 (`diceId <=> model.diceId`); compare Modules/TableRPG/Model/TableModel.swift:186 (`diceId_` is a CRDT there)
- What: `photoId`, `name`, `tags`, `tablePlayers` merge as LWW registers, but `diceId` (like `displayState`, `parentId`, `groupId`) is a plain value that always takes `other`'s side in `merge`.
- Why: With two devices, an older copy arriving as `other` reverts the dice the GM just set or cleared on the newer device; which side wins depends on import direction, not on who edited last.
- Action: Make `diceId` a `CRDT<UUID?>` (decode with an epoch-stamped default like `noTablePlayers` for old files and add a nullable Core Data column or reuse the existing string), or document that it is intentionally last-importer-wins.
- Severity: Medium
- Status: NEW

### Global search treats entry-only matches as item matches
- Category: Bug
- Location: Modules/AdventureRPG/Model/AdventureModel.swift:281-288 (`filter(filter:includeEntries:)` ignores `includeEntries`); caller Modules/CoreRPG/Controllable/SearchControllable.swift:30; Modules/CharacterRPG/Model/ValueModel.swift:241 and RuleRPG/Model/RuleModel.swift:288 honour the flag; TableRPG/Model/TableModel.swift:189 has the same defect
- What: `globalSearchResults` asks for `includeEntries: false` but Adventure still searches entries, so an adventure whose only match is deep in an entry is reported as an item hit with `matchedContent` set to its (non-matching) description.
- Why: Wrong snippet and inflated relevance in game/global search results; harmless data-wise.
- Action: Add `includeEntries` to the guard (`guard includeEntries, !specialCategory`), and fix Table the same way (outside this area).
- Severity: Low
- Status: NEW

### Sheet update rebuilds every entry's sheet on each change (quadratic lookups)
- Category: Performance
- Location: Modules/AdventureRPG/Controller/SheetController.swift:87-180 (`update`): `entryIds.contains` inside filter + `removeAll` (:124,129), `sheetModel.entries.first(where:)` per entry (~:135), and a full `sheet(entry:...)` projection per entry (:147) including `linksFrom` and cross-module `SheetLinkGuard` lookups
- What: Every call to `update` (runs on the main actor after each edit) is O(entries²) and re-materialises each entry's link sheets even when only one entry changed.
- Why: Adventures extracted from long PDFs have hundreds of entries; typing in one entry rebuilds all of them. Not measured.
- Action: Build a `[UUID: SheetModel]` dictionary and a `Set` of entry ids once, and project only entries whose content/links changed (or are new); profile with a 500-entry adventure first.
- Severity: Medium
- Status: NEW

### `changedLinkRegisterModels` is O(n²) over entries
- Category: Performance
- Location: Modules/AdventureRPG/Model/AdventureModel.swift:126-165 (subscript at :321-324)
- What: It builds `Set(entries.map(\.id))` four times and resolves each id through `self[$0]` / `oldValue[$0]`, which is a linear `firstIndex` (subscript at :321), then compares whole entry arrays with `!=` first.
- Why: Runs on every save of an adventure; hundreds of entries means tens of thousands of comparisons per keystroke-debounce.
- Action: Index old and new entries once into dictionaries by id and iterate those.
- Severity: Low
- Status: NEW

### `collectLinks` ignores item-level dice/characters and group children
- Category: Bug
- Location: Modules/AdventureRPG/Controller/LinkController.swift:150-196
- What: It returns `photoId` and photo links only for `.photo`, never follows `entry.adventureId` (so photos inside group adventures are missed) and has no `.dice`/`.value` handling although `diceId` and `tablePlayers` are item-level links; MapRPG calls it across modules (MapRPG/Controller/LinkController.swift:116-135).
- Why: Callers asking for the links of an adventure that uses groups get an incomplete set (same root cause as the export gap).
- Action: Follow `adventureId` children under the existing visited set and add the item-level ids when `module` matches.
- Severity: Low
- Status: NEW

### `validateLinks` does not check group entries
- Category: Bug
- Location: Modules/AdventureRPG/Controller/LinkController.swift:106-148
- What: photo, dice, table players and entry content links are validated; an `entry.adventureId` whose group item no longer exists is left as is.
- Why: A dangling group entry renders blank and is never repaired by "Validate Folders" (deleting normally cascades through `willDeleteChildren`, so this needs a sync or import accident).
- Action: Remove or clear entries whose `adventureId` does not resolve, and report it in the validation model.
- Severity: Low
- Status: NEW (unverified)

### Older Adventure audit items that are still open in code
- Category: Concurrency | Refactor
- Location: Modules/AdventureRPG/Controller/LinkController.swift:68-70 (untracked `Task { await toggler?(...) }`) [CODE_AUDIT_Adventure §3.1]; LinkController.swift:30, ExportController.swift:32 and View/AdventureSheet.swift:103 (`preconditionFailure` when `rootManager` is nil, struct-held two-phase init) [§3.3]; LinkController.swift:88-103 (`repairLinks` calls 10 sibling `repairLink`s per link) [§7.1]; Controller/ViewController.swift:15-21,30-40 (`AnyView`, forced by CoreRPG `ViewControllable`) [§8.1]; Route/* (six destination-view naming schemes) [§8.4]; Intent/AppendAdventureSectionIntent.swift, CreateAdventureIntent.swift, DeleteAdventureIntent.swift (not merged into one ManagementIntents file) [§9.9]
- What: The items above were verified by reading the lines; none changed since 2026-09-17.
- Why: All are low impact. The `toggler` Task cannot be cancelled and drops errors; `repairLinks` does 10x redundant lookups on every validate pass (dispatch by `link.module` as `handleTextLink` already does would fix it).
- Action: Decide won't-fix vs fix per item; the cheap one is `repairLinks` dispatch by module, and the `toggler` call can become `async` instead of an owned-nowhere Task.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_Adventure §3.1, §3.3, §7.1, §8.1, §8.4, §9.9]

### Preview and mock fixtures compile into Release
- Category: Dead code
- Location: Modules/AdventureRPG/Model/PreviewData.swift:17-42 and :70-195 (`AdventureRootModel.preview`, `previewFixture`, `previewWithData`, `AdventureModel.preview`, `previewFixtures` outside `#if DEBUG`); Modules/AdventureRPG/Model/MockData.swift:1-67 (imports SwiftData, `LinkDataModel`)
- What: Only two blocks of PreviewData are `#if DEBUG`; the rest and all of MockData ship in Release builds, and the files sit in Model/ instead of the documented Preview/ folder.
- Why: Dead code and extra imports in the release binary; CLAUDE.md asks for `#if DEBUG` fixtures in a Preview folder.
- Action: Wrap both files in `#if DEBUG` (the `#Preview` macros already compile out) and move them to Modules/AdventureRPG/Preview/; check that tests do not rely on them in Release.
- Severity: Low
- Status: NEW

### `ViewController.diceSelection` is only referenced by a test
- Category: Dead code
- Location: Modules/AdventureRPG/Controller/ViewController.swift:48; only caller Tests/AdventureRPGTests/ViewControllerTests.swift:33
- What: The helper returns the Dice drop view for a selection model but nothing in Modules/ or Sources/ calls it (Map and Table have copies that are equally unreferenced outside tests).
- Why: Dead API kept alive by its own test.
- Action: Delete it and its test line (and the Map/Table twins in their own audits).
- Severity: Low
- Status: NEW

### `nonisolated(unsafe)` on Find-action query statics
- Category: Concurrency
- Location: Modules/AdventureRPG/Intent/AdventureEntity.swift:134,160
- What: `properties` and `sortingOptions` are `nonisolated(unsafe) static let` because `QueryProperties`/`SortingOptions` are not Sendable.
- Why: A project-rule violation, though safe in practice (immutable after init); other modules copy the same pattern.
- Action: Make them `static var ...: QueryProperties { ... }` computed properties if the protocol allows, otherwise keep and comment the reason once.
- Severity: Low
- Status: NEW

### Drop view style deviations (SwiftUI rules)
- Category: SwiftUI
- Location: Modules/AdventureRPG/View/DropChooseView.swift:32 (`RoundedRectangle(cornerRadius:style:)` instance instead of `.rect(cornerRadius:)`), :37-45 (image-only remove Button, label is only an accessibility label), Modules/AdventureRPG/View/EmptyDropButton.swift:32 (`.padding(.horizontal, 12)`), Modules/AdventureRPG/View/DetailListView.swift:42 (`withAnimation` ignoring Reduce Motion)
- What: Small leftovers of CLAUDE.md rules: static shape lookup, `Button("Remove", systemImage:)` with text, no hard-coded padding, respect `accessibilityReduceMotion` as the sibling views do.
- Why: Style consistency only.
- Action: Fix opportunistically when the file is next touched.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_Adventure §8.2] for the shape, rest NEW

### Test gaps on the risky controller paths
- Category: Test gap
- Location: Tests/AdventureRPGTests (no hits for `duplicate(item`, `saveTablePlayers`, `tablePlayers(for`, group export, `update(itemId:entryId:` on a group entry, folder/collection duplication)
- What: `EditController.duplicate(item:)` with groups, folders and collections (EditController.swift:121-178), `GameController.saveTablePlayers` (GameController.swift:104-118, which rewrites link registers and mirrors into a loaded game copy), export of group/dice (see findings above), and `AdventureModel.merge` for folder entries are only covered indirectly or not at all (`GameControllerTests` ends at start/reset).
- Why: These carry data-loss potential (duplicate copies member ids, saveTablePlayers deliberately avoids a full library overwrite during a game).
- Action: Add tests: duplicate adventure with group entry (child copied, `groupId` and `adventureId` remapped), duplicate folder with sub-folder, saveTablePlayers during game mode (library updated, game copy session fields untouched, link register diffs), merge of two folder variants.
- Severity: Medium
- Status: NEW

Not audited in this area: Resources (string catalogs, Core Data model file), runtime behaviour on devices (all findings are from reading; none reproduced), performance measurements, and the CoreRPG generics (GenericItemController, EntryDataEditable, FolderEntryMerge) beyond the parts quoted above.
