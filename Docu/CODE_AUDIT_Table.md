# TableRPG Module Code Audit

Generated 2026-09-17. Scope: `Modules/TableRPG/` only — 60 Swift files, 5,713 LOC (Controller, Intent, Menu, Model, Root, Route, View). `Modules/TableRPG/Resources/` (Core Data model file) was inspected only for the CloudKit-optionality check in §6; its `.xcdatamodeld` structure itself was not otherwise audited. No `Dead/` or archived directory exists inside this module.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made. This is the first audit pass for TableRPG — prior passes covered Dice, Audio, Space, Photo, and CoreData (see recent commits `d9f1fcfe`, `2fd147b2`, `5699f711`, `9825c79f`).

**Headline:** this module is in noticeably better shape than a typical unaudited module — zero compiler warnings, zero `#if false`/dead code, zero `print()` calls, zero TODO/FIXME markers, no force-unwraps/force-try/force-cast, no hardcoded secrets, and full compliance with the project's `Id`/`Url` naming convention and `@MainActor`/`@Observable` rules. The real findings cluster around one genuine gameplay bug (§5.1), a handful of `O(n²)` hot paths, and duplication that should move to CoreRPG.

---

## 1. Executive summary

1. **[High] Dice-table roll resolution has no lower-bound range check** — §5.1 — `Controller/GameController.swift:106-117`. A roll can match the wrong entry (or an out-of-order entry) because only the upper bound of a range is checked.
2. **[Medium] Dice-range parsing silently diverges from the correct implementation** — §5.2 — `Controller/GameController.swift:108`. Only ASCII `-` is recognized, unlike `TableGenerationController.selectorRange`, which also accepts en/em dash.
3. **[Medium] `LinkController.collectLinks` drops table-to-table links** — §5.4 — `Controller/LinkController.swift:106-127`. Missing `.table` case means photo/dice/pdf links nested behind a chained table link are never collected, unlike the equivalent code in MapRPG/AdventureRPG.
4. **[Medium] `uuid ?? UUID()` fallback can mint unstable identities during partial CloudKit sync** — §5.5 — `Controller/DataController.swift:23,76`.
5. **[Medium] `MainActor.assumeIsolated` runtime-trap risk in `TableModel`'s `nonisolated` conformances** — §3.1 — `Model/TableModel.swift:117-124,180-228,294-301,407-418`.
6. **[Medium] Non-atomic multi-`await` sequence in `GameController.receiveTable`** — §3.2 — `Controller/GameController.swift:134-188`. State captured early in the merge can go stale before it's used.
7. **[Medium] `O(n²)` folder-entries merge in `TableModel.merge`** — §7.1 — `Model/TableModel.swift:184-193`. Runs on every CRDT/CloudKit merge for folder-category tables.
8. **[Medium] `O(n²)` entry diffing in `SheetController.update`** — §7.2 — `Controller/SheetController.swift:99-134`. Runs on every sheet refresh.
9. **[Medium] Intent-indexing helper trio duplicated verbatim across 10 modules** — §9.3 — `Intent/TableManagementIntents.swift:142-169`, and the same in DiceRPG/CharacterRPG/AudioRPG/GeneratorRPG/MapRPG/PhotoRPG/PdfRPG/SpaceRPG/WeatherRPG.
10. **[Medium] Spotlight `attributeSet()` boilerplate duplicated across 12 modules** — §9.4 — `Model/DataModel+Extensions.swift:21-53`, and the same pattern in 11 sibling modules.

No Critical findings. No Security findings (§6).

---

## 2. Quick wins (≤30 min each)

- **Fix range-check + dash-parsing bug together** — `Controller/GameController.swift:101-126`. See §5.1/§5.2; both are in the same ~25-line function.
- **Replace `if let _ = item.diceId` with `if item.diceId != nil`** — `Controller/GameController.swift:106`. Purely stylistic, but sits right next to the real bug above.
- **Fix typo "santity checks" → "sanity checks"** — `Model/TableModel.swift:221`.
- **Rename misleading `photoIds` local variable to `collectedIds`** — `Controller/LinkController.swift:109-125`. The array collects whatever module type was requested, not just photos.
- **Replace hardcoded `displayState != 2` with `DisplayStateMask.totalHidden.rawValue`** — `Controller/LinkController.swift:65`, `Controller/ExportController.swift:29`. `Root/TableRootModel.swift:228` already does this correctly.
- **Add the missing `"19"` entry to the preview dice-table fixture** — `Model/PreviewData.swift:107-254`. Canvas/demo rolls of 19 currently show a spurious "does not match" error.
- **Move the stray `import SwiftUI` to the top of the file** — `View/DetailEditorToolBarButtons.swift:14`.
- **Reformat `Localization+Extensions.swift` to consistent 4-space indentation** — `Resources/Localization+Extensions.swift:5-15`.
- **Bounds-check the `#Preview` array subscripts** — `View/DetailListView.swift:9-16`, `View/DetailFolderListView.swift:7-10`. Use `.first ?? someFallbackId` instead of `items[0]`.

---

## 3. Concurrency

### 3.1 `MainActor.assumeIsolated` runtime-trap risk in `TableModel`'s `nonisolated` conformances
- **Location:** `Model/TableModel.swift:117-124` (`Comparable.<`), `180-228` (`ItemDiffComparable.merge`/`isSame`), `294-301` (`ItemDuplicatable.duplicate`), `407-418` (`Equatable.==`, `Hashable.hash(into:)`)
- **What:** These `nonisolated` protocol requirements read `@MainActor`-isolated stored state by routing through `assumeMainActorIsolated` (`CoreRPG/Concurrency/MainActorIsolationAssumption.swift`), which wraps `MainActor.assumeIsolated`.
- **Why:** `MainActor.assumeIsolated` is a runtime assertion, not a compile-time guarantee. If `==`, `hash(into:)`, `<`, `merge`, `isSame`, or `duplicate` is ever invoked from a genuinely non-MainActor context (a `Set`/`Dictionary` operation or `sorted()` call from a background `Task`, or synchronous `Codable`/hashing machinery invoked off-thread by a framework), the app traps instead of failing to compile.
- **Action:** The pattern is already centralized and documented (the helper's own doc comment references "CODE_AUDIT §3.2"), so the remaining work is auditing every actual call site of these five requirements to confirm none can reach `TableModel` from off the main actor. Consider a Swift Testing case that deliberately calls one of these from a background `Task` to confirm the trap-vs-crash tradeoff is acceptable.
- **Severity:** Medium

### 3.2 Non-atomic multi-`await` sequence in `GameController.receiveTable`
- **Location:** `Controller/GameController.swift:134-188`
- **What:** `receiveTable(itemId:data:makeCurrent:)` is a non-`@MainActor` async function that chains many separate `await` hops into `@MainActor`-isolated helpers (`tableObjectIdentities()` at 149, `importNetwork(from:)` at 157, `newlyImportedTables(comparedWith:)` at 162, `persistentTableCopies(for:)` at 178, `mergeAndPersistImportedTables(...)` at 180, `setCurrent(itemId:)`/`persistCurrentTable(itemId:)` at 182/144-145, `markAvailable(_:)` at 186) with no lock or single actor hop spanning the whole sequence.
- **Why:** Between any two `await` points the MainActor is free to run other work (a second concurrent `receiveTable` call for the same/related item, or a user edit via `EditController`), so state captured early (e.g. `previousIdentities`, `persistentTables`) can go stale before it's consumed later in the same call — risking a silently incorrect CRDT merge or a lost concurrent edit under real network/game traffic.
- **Action:** Serialize calls to `receiveTable` per item (e.g. an actor-backed queue/lock keyed by `itemId`), or re-derive each merge step's state immediately before using it rather than trusting values captured several `await`s earlier.
- **Severity:** Medium

### 3.3 Fire-and-forget `Task` with no cancellation or error surfacing for the share-link command
- **Location:** `Controller/LinkController.swift:26-34` (the `Task` at line 29)
- **What:** `toggleTextLink(...)` is synchronous but, for the `.share` command, spawns an unstructured `Task { await shareResult?.networkActions?.shareId(gameController.share(id: itemId)) }` and immediately returns, discarding the task handle.
- **Why:** No way to cancel this task if the triggering view disappears right after the tap; no way for the caller to know whether the share succeeded; any thrown error from `shareId`/`share(id:)` is silently dropped.
- **Action:** Either make the share path `async` so callers can await/cancel it through the existing `toggler`/`shareResult` callback machinery, or capture and store the `Task` on the view side so it can be cancelled and its failure surfaced.
- **Severity:** Low

---

## 4. API modernity

### 4.1 `@preconcurrency` downgrade on `TableEntityQuery: IndexedEntityQuery`
- **Location:** `Intent/TableEntity.swift:111-125`
- **What:** `extension TableEntityQuery: @preconcurrency IndexedEntityQuery { ... }` opts the `reindexEntities`/`reindexAllEntities` conformance out of strict concurrency checking.
- **Why:** `@preconcurrency` silently suppresses Sendable/isolation diagnostics for this conformance. It may be a leftover from an earlier SDK, or it may be masking a genuine Sendable gap (e.g. crossing into `CSSearchableIndex.default().indexAppEntities`). Unlike the project's other intentional concurrency escape hatches (e.g. `assumeMainActorIsolated`'s doc comment), this one is undocumented.
- **Action:** Try removing `@preconcurrency` and rebuild under complete checking; if still required, add a comment explaining exactly why, matching the project's convention for documenting these escape hatches.
- **Severity:** Low

### 4.2 iOS 27 "modern API" paths are unreachable under the project's stated Swift 6.3 compiler
- **Location:** `Intent/TableManagementIntents.swift:157-168` (`deleteIntentEntities`, `#if compiler(>=6.4)` gating `CSSearchableIndex.default().deleteAppEntities(identifiedBy:ofType:)`); `Intent/OpenTableIntent.swift:33-37,41-54` (`addSiriContext`/`donateSiriViewingIntent`, same `#if compiler(>=6.4)` gate around `appEntityIdentifier`/`EntityIdentifier`)
- **What:** Both files guard their newest AppIntents/CoreSpotlight APIs (all `@available(iOS 27, ...)`) behind `#if compiler(>=6.4)`, but project context states the compiler in use is Swift 6.3.
- **Why:** With a 6.3 compiler these blocks compile out entirely, so even a device already running iOS 27 always falls back to the older bulk `deleteSearchableItems(withIdentifiers:)` API and never gets Siri entity-identifier donation — source that looks like coverage but isn't currently exercised.
- **Action:** Confirm the actual shipping toolchain version. If ≥6.4, drop the compiler-version gate (the `#available` checks alone suffice). If genuinely 6.3, comment that this is dormant/future-proofing code so it isn't mistaken for exercised functionality.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Dice-table roll resolution has no lower-bound range check
- **Location:** `Controller/GameController.swift:101-126`, specifically `106-117`
- **What:** `entry(for id:with result:)`'s `.dice` case matches the **first** entry whose parsed upper bound (`numbers.last`) is `>= result` (`return result <= last`). It never checks that `result` is also `>=` the range's lower bound, and relies on `item.entries` being pre-sorted ascending by range.
- **Why:** For a dice table with ranged entries like `"5-10"`, `"1-4"` (e.g. after a user drags to reorder rows), a roll of `2` hits `"5-10"` first (`2 <= 10` is true) and returns the wrong entry — corrupting which loot/encounter a die roll maps to. This is public API on `GameController` with `Tests/TableRPGTests/GameControllerTests.swift` asserting the buggy behavior as correct. No production call site was found in this snapshot — live rolls currently go through `TableGenerationController.matchingEntry`, which does this correctly via `selectorRange(...).contains(result)` (verified at `Controller/TableGenerationController.swift:219-229,232-244`) — but a future caller (e.g. a GameRPG live-roll wire-up) will inherit the bug and its test coverage will not catch it.
- **Action:** Reimplement using the same "parse full range, `ClosedRange.contains`" approach as `TableGenerationController.selectorRange`/`matchingEntry`, independent of entry array order. Update `GameControllerTests` accordingly.
- **Severity:** High

### 5.2 Dice-range parsing only splits on ASCII hyphen, diverging from the correct implementation
- **Location:** `Controller/GameController.swift:108` (`$0.name.split(separator: "-")`)
- **What:** Range names are split only on `"-"`. `TableGenerationController.selectorRange(for:)` (`Controller/TableGenerationController.swift:219-229`, verified) explicitly also accepts en dash `–` and em dash `—`.
- **Why:** iOS/macOS "smart punctuation" commonly auto-converts a typed `-` between two numbers into an en dash in text fields. An entry named `"1–5"` (en dash) silently never matches any roll in `GameController.entry(for:with:)`, while the same content works fine through `TableGenerationController` — a silent-failure inconsistency between the two roll-resolution paths in the same module.
- **Action:** Share one range-parsing implementation (have `GameController.entry(for:with:)` call `TableGenerationController.selectorRange`) instead of maintaining two diverging parsers. Fold this fix in with §5.1.
- **Severity:** Medium

### 5.3 Stale `lastRoll` shown alongside a "roll doesn't match" error
- **Location:** `Controller/TableGenerationController.swift:138-163` (`apply(result:to:model:)`)
- **What:** On a failed match (`matchingEntry` returns `nil`), the function clears pending-roll flags (`clearPendingRoll`) and sets `model.errorMessage`, but never resets `occurrence.lastRoll` from a previous successful roll.
- **Why:** `TableGenerationOccurrenceHeaderView` (`View/TableGenerationOccurrenceHeaderView.swift:29-32`, verified) renders `"Rolled \(lastRoll)"` whenever `lastRoll != nil`. A user who rolls successfully, edits the table (removing/renaming the matched entry), then rolls again with a result that no longer matches anything sees a confusing UI: the old "Rolled N" badge still shown next to a fresh "does not match an entry" error.
- **Action:** Clear `occurrence.lastRoll = nil` before attempting the match in `apply(result:to:model:)`, or only on match failure.
- **Severity:** Low

### 5.4 `LinkController.collectLinks` doesn't recurse into table-to-table links
- **Location:** `Controller/LinkController.swift:106-127`
- **What:** The `switch $0.module` only handles `.photo`, `.dice`, `.pdf` (recursing into `diceRoot`/`pdfRoot`'s own `collectLinks`, verified at lines 116-119); there is no `.table` case, so a link to another Table is silently dropped instead of being followed.
- **Why:** Sibling modules implement this correctly: `Modules/MapRPG/Controller/LinkController.swift:124` and `Modules/AdventureRPG/Controller/LinkController.swift:210` both include a `.table` case recursing into `tableRoot.linkControllable.collectLinks(...)`. Because TableRPG's own implementation omits it, any photo/dice/pdf links nested behind a chain of Table→Table links (a documented, intentional pattern — see `TableGenerationController.maxTableRecursionCount`) are never collected. The one confirmed caller, `EditController.collectPhotos(itemId:entryId:)` in AdventureRPG (reached via `tableRoot.linkControllable.collectLinks`), will silently produce an incomplete photo collection for such tables.
- **Action:** Add a `.table` case that recurses via `itemController` into the linked table's own entries, with a recursion-depth guard (mirroring `TableGenerationController.maxTableRecursionCount`) since tables may legitimately link back to themselves.
- **Severity:** Medium

### 5.5 `uuid ?? UUID()` fallback can mint a new identity on read for CloudKit-optional fields
- **Location:** `Controller/DataController.swift:23` (`mapSnapshot`), `:76` (`map(_ model: RPGTableEntry)`) — both verified
- **What:** `TableSnapshot(id: model.uuid ?? UUID(), ...)` and the entry mapper both fall back to a freshly generated `UUID()` when Core Data's `uuid` attribute (required-optional per the CloudKit `NSPersistentCloudKitContainer` constraint) is `nil`.
- **Why:** CloudKit materializes records incrementally — a record can briefly appear with some fields (including `uuid`) still `nil` before a follow-up sync fills them in. During that window, every fetch/map of that record mints a *different* random identity, breaking `Identifiable` stability (SwiftUI diffing thrash, potential duplicate rows) and risking the CRDT layer never converging that record with its eventually-synced real counterpart. The write path (`applySnapshot`, line 40) is fine — the risk is purely inbound/read-side during partial sync.
- **Action:** Treat a `nil` `uuid` as "not yet ready" (skip/defer mapping that record) rather than substituting a throwaway random id, or persist the generated id back onto the managed object immediately so it's stable across repeated reads.
- **Severity:** Medium

### 5.6 Magic number `displayState != 2` duplicated instead of using the named constant
- **Location:** `Controller/LinkController.swift:65` (verified), `Controller/ExportController.swift:29`
- **What:** Both guard against "totally hidden" items with a hardcoded `displayState != 2`, while `Root/TableRootModel.swift:228` correctly uses `DisplayStateMask.totalHidden.rawValue` for the identical check.
- **Why:** Three call sites checking the same concept two different ways is a latent bug waiting to happen — if `DisplayStateMask`'s bit layout ever changes, the two magic-number sites silently start guarding the wrong thing while the named-constant site keeps working.
- **Action:** Replace both `!= 2` occurrences with `!= DisplayStateMask.totalHidden.rawValue`.
- **Severity:** Low

### 5.7 View directly duplicates the controller's private pending-roll reset logic
- **Location:** `View/TableGenerationOccurrenceHeaderView.swift:164-167` vs `Controller/TableGenerationController.swift:305-312`
- **What:** `TableGenerationOccurrenceHeaderView.shareDice(to:playerName:)`'s error-recovery path (verified at lines 165-167) sets `occurrence.isAwaitingPlayerRoll = false; occurrence.awaitingPlayerId = nil; occurrence.awaitingPlayerName = nil` inline — the exact same three assignments as `TableGenerationController.clearPendingRoll(in:)`, which is `private` and therefore unreachable from the view.
- **Why:** A View reaching directly into an `@Observable` model's fields to replicate controller-owned state-reset logic breaks the Controller-owns-mutation architecture and will silently drift if `clearPendingRoll` ever gains a step (e.g. clearing an error message too).
- **Action:** Add a small internal (non-`private`) method on `TableGenerationController`, e.g. `func cancelPendingShare(occurrence:)`, that the view calls instead of hand-rolling the three assignments.
- **Severity:** Medium

### 5.8 `GameController.entry(for:with:)` has no confirmed production call site
- **Location:** `Controller/GameController.swift:101-126`
- **What:** This method (the same one carrying the bug in §5.1/§5.2) is referenced only from `Tests/TableRPGTests/GameControllerTests.swift`; no call site was found elsewhere in `Modules/` (including `GameRPG`, `RolePlayGameKit`, or the widget targets).
- **Why:** Either this is dead production code kept alive only by its own unit test — in which case the test is asserting buggy behavior that will never actually run — or it's a genuinely missing integration point that should be wired into live gameplay (`addResult`/`receiveTable`) but currently isn't.
- **Action:** Confirm with the team whether this was meant to back real gameplay. If so, fix it per §5.1/§5.2 and wire it in. If it's superseded by `TableGenerationController.matchingEntry`, delete both the method and its test rather than leaving a buggy, untested-in-practice duplicate around.
- **Severity:** Medium

---

## 6. Security

_No findings._ No hardcoded secrets/tokens/API keys, no `Bearer`/`apiKey`/`Authorization` strings, and no unsafe debug-log content were found anywhere under `Modules/TableRPG/`. Core Data model attributes in `Resources/Model.xcdatamodeld/RPGTables.xcdatamodel/contents` all satisfy the project's CloudKit rule (every non-optional attribute has a `defaultValueString`, all relationships are `optional="YES"`) — no schema-level violations found.

---

## 7. Performance

### 7.1 `O(n²)` folder-entries merge in `TableModel.merge`
- **Location:** `Model/TableModel.swift:184-193` (verified)
- **What:** For folder-category tables, `combined = allIds.compactMap { id in entries.first { $0.id == id } ?? other.entries.first { $0.id == id } }` does a linear scan of both `entries` and `other.entries` for every id in the unioned id set.
- **Why:** This runs on every CRDT merge (CloudKit sync merges, master/player table imports via `GameController.receiveTable`) for any folder-category Table, scaling `O(n²)` with the number of subfolder/child entries.
- **Action:** Build `Dictionary(uniqueKeysWithValues:)` lookups for `entries` and `other.entries` by id once, then do `O(1)` lookups per id.
- **Severity:** Medium

### 7.2 `O(n²)` entry diffing in `SheetController.update`
- **Location:** `Controller/SheetController.swift:99-134` (verified)
- **What:** `entryIds` is kept as a plain `[UUID]` (line 99) and used with `.contains(entryId)` inside both the `filter` (102-105) and `removeAll` (107-110) closures — each `.contains` call is `O(n)`. The main loop (116-134) separately does `sheetModel.entries.first(where: { $0.source.entryId == entry.id })` for every entry in `model.entries`, another `O(n)` scan per iteration.
- **Why:** `update(root:sheetModel:isEditor:)` runs on every sheet refresh (CoreData/CRDT sync, editor keystrokes debounced through `SheetRootModel`), so with tables holding many entries this is a real, repeated `O(n²)` cost on the main actor.
- **Action:** Convert `entryIds` to a `Set<UUID>` for the `.contains` checks, and build a `[UUID: SheetModel]` dictionary from `sheetModel.entries` once before the loop instead of calling `.first(where:)` per entry.
- **Severity:** Medium

### 7.3 Preview/sample fixture data ships in Release builds
- **Location:** `Model/PreviewData.swift:1-341`, `Model/TableGenerationPreviewData.swift:1-93`, `Model/MockData.swift:1-71`
- **What:** Aside from the `#if DEBUG`-gated `testRoot(...)` helper (`PreviewData.swift:35-47`), none of this — full `TableModel`/`TableEntryModel` fixture trees, a `MockRootViewModifier` building a complete fake `RootManager` stack, and `TableGenerationModel` preview variants — is gated behind `#if DEBUG`. Only `#Preview` macro call *sites* elsewhere are stripped from Release builds by Xcode; these static declarations are ordinary Swift code compiled and linked into every configuration, including Release/App Store builds.
- **Why:** Unnecessary binary size growth and shipped internal/placeholder content in every release build. This is a repo-wide convention (the same pattern exists in DiceRPG's and PdfRPG's own `PreviewData.swift`), so it's systemic rather than unique to this module — see §10.
- **Action:** Wrap the fixture declarations (or at minimum `MockRootViewModifier`/`MockData`) in `#if DEBUG`, matching the existing `testRoot()` treatment, so they're excluded from Release/TestFlight/App Store builds.
- **Severity:** Medium

---

## 8. SwiftUI / UI

A dedicated pass over all 22 files in `View/` and 7 files in `Root/` (full reads, not grep) found the SwiftUI layer to be clean and convention-compliant: `foregroundStyle()` used throughout (no `foregroundColor()`), `clipShape(.rect(cornerRadius:))` used correctly, no `onTapGesture` misuse, no `GeometryReader`, no `Array(x.enumerated())`, `onChange` always uses the two-parameter/no-parameter form, `Task.sleep(for:)` used correctly, `scrollIndicators(.hidden)` used correctly, `AnyView` used only where protocol-mandated (`Controller/ViewController.swift:17-23,51-61`, `Controller/TableGenerationViewController.swift:14-23`), accessibility labels/hints/values present on interactive controls, and full `Id`/`Url` naming compliance. `ThumbnailDiceRow` already conforms to `Equatable` for its `ForEach` usage.

The two real view-structure violations were found and confirmed during the dead-code pass (§9) rather than here, and are cross-referenced below to avoid duplication:

### 8.1 Toolbar content extracted as a computed property instead of a `ToolbarContent` struct
- **Location:** `View/DetailListView.swift:54-71`
- **What:** `@ToolbarContentBuilder var toolbarContent: some ToolbarContent` is a computed property used via `.toolbar { toolbarContent }` at line 29, rather than a dedicated `View`/`ToolbarContent`-conforming struct.
- **Why:** Project convention (CLAUDE.md: "Do not break views up using computed properties; place them into new View structs instead") explicitly calls this out; computed properties don't get their own identity/diffing.
- **Action:** Extract into a dedicated `struct DetailListToolbarContent: ToolbarContent { ... }` taking `model`/`root`/`folderListController` as needed.
- **Severity:** Low

### 8.2 Private function returning `some View` used as a body fragment
- **Location:** `View/TableGenerationPanelView.swift:63-90`
- **What:** `outcomeSheetEditor(session:) -> some View` is a private function (not a computed property, but the same anti-pattern) building a 25-line view fragment inline.
- **Why:** Same readability/identity concerns — a function-returned `some View` doesn't get independent `Equatable`/diffing behavior a real `View` struct would.
- **Action:** Extract into `private struct TableGenerationOutcomeSheetEditorView: View` taking `session: SimpleSheetEditingSession` as a property.
- **Severity:** Low

### 8.3 Inconsistent magic corner-radius and layout constants across the generation panel
- **Location:** Corner radii — `View/TableGenerationOccurrenceView.swift:65` (20), `View/TableGenerationEntryRow.swift:116` (16), `View/TableGenerationPanelView.swift:55,57,59` (28), `View/TableGenerationResultView.swift:51,81` (16). Layout — `View/TableGenerationResultView.swift:47-48` (`minHeight: 44`, `padding(.horizontal, 12)`), `View/ThumbnailDiceRow.swift:16` (`padding(.trailing, 20)`), `View/TableGenerationPanelView.swift:50` (`maxWidth: 760, maxHeight: 820`), `Model/MockData.swift:62` (`width: 800, height: 600`)
- **What:** Three different unexplained corner radii and several unnamed layout numbers are hardcoded ad hoc across the same cohesive feature, all verified present at the cited lines.
- **Why:** CLAUDE.md: "Avoid specifying hard-coded values for padding and stack spacing unless requested." Three different radii in one feature suggests copy-paste rather than an intentional scale; `44` (likely a minimum tap target) and the `760×820` panel size look like intentional design decisions that deserve a name so they aren't accidentally "simplified" away later.
- **Action:** Introduce named constants (e.g. `TableGenerationLayout.cardRadius/.groupRadius/.panelRadius`, `.minTouchTargetHeight`, `.panelSize`) in one place, or switch to an existing CoreRPG design-token enum if one already covers this.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Files to delete outright
_None found._ No `#if false` blocks, no commented-out code blocks, no `_OLD`/`Old_`/`_v1`/`_v2`/`Legacy`/`Deprecated`-named files, no filename typos. The only incidental matches for "legacy-looking" names were "fOLDer" substrings in `FolderListController.swift`/`DetailFolderListView.swift` — false positives.

### 9.2 CoreRPG-generic controllers already in place (informational — no action needed)
- **Location:** `Controller/ItemController.swift:8`, `Controller/ImportController.swift:8`, `Controller/SearchController.swift:5`
- **What:** `ItemController`, `ImportController`, and `SearchController` are simple `typealias`es to `GenericItemController<TableModel>`, `GenericImportController<...>`, and `GenericSearchController<ItemController>`, each with a `CODE_AUDIT §9.x` comment noting they were already genericized into CoreRPG.
- **Why:** Confirms this module doesn't duplicate CoreRPG base-controller logic — flagged only so it isn't mistakenly re-reported as a finding in a future pass.
- **Severity:** Low (informational)

### 9.3 Duplicated intent helper trio across 10 modules
- **Location:** `Intent/TableManagementIntents.swift:142-169`
- **What:** `intentPlainText(from:)`, `indexIntentEntities(_:)`, and `deleteIntentEntities(ids:ofType:)` are private free functions defined byte-for-byte identical in TableRPG, DiceRPG, CharacterRPG, AudioRPG, GeneratorRPG, MapRPG, PhotoRPG, PdfRPG, SpaceRPG, and WeatherRPG's `*ManagementIntents.swift` files.
- **Why:** 10× copy-paste of ~25 lines of Spotlight indexing/deletion glue; any bug fix (e.g. the iOS 27 availability branch from §4.2) has to be replicated by hand in 10 places.
- **Action:** Move these three helpers into CoreRPG (e.g. `CoreRPG/AppIntents/IntentEntityHelpers.swift`) as `package`/`public` free functions, then delete the per-module copies.
- **Severity:** Medium

### 9.4 Duplicated `attributeSet()` Spotlight indexing pattern across 12 modules
- **Location:** `Model/DataModel+Extensions.swift:21-53`
- **What:** `RPGTable.attributeSet()` and `RPGTableEntry.attributeSet()` build a `CSSearchableItemAttributeSet` with near-identical boilerplate (identifier/displayName/title/textContent assignment, tag-splitting into keywords); the same shape recurs in AdventureRPG, AudioRPG, CharacterRPG, DiceRPG, GeneratorRPG, MapRPG, PdfRPG, PhotoRPG, RuleRPG, SpaceRPG, WeatherRPG.
- **Why:** Same Spotlight-attribute-building logic hand-copied 12 times; the tag-splitting loop in particular is generic string processing with zero Table-specific behavior.
- **Action:** Extract a CoreRPG helper, e.g. `SpotlightAttributeBuilder.make(identifier:name:content:tags:)`, and have each module's `attributeSet()` call it with its own field names.
- **Severity:** Medium

### 9.5 Duplicated PDF `Transferable` rendering closure across 5 modules
- **Location:** `Intent/TableEntity.swift:58-91`
- **What:** The `FileRepresentation(exportedContentType: .pdf)` closure that builds an `ImageRenderer`/`CGContext` PDF from a `VStack { Text(name); Text(description) }` is structurally duplicated in AdventureRPG, CharacterRPG, MapRPG, TableRPG, and WeatherRPG's `*Entity.swift` files.
- **Why:** ~20 lines of PDF-rendering plumbing repeated 5×; a rendering fix needs 5 edits.
- **Action:** Factor into a CoreRPG helper like `EntityPDFExport.makeFileRepresentation(name:description:)`, parameterized by name/description.
- **Severity:** Low-Medium

### 9.6 Duplicated Route `RawRepresentable` token-parsing boilerplate (within TableRPG itself)
- **Location:** `Route/DetailRoute.swift:15-30`, `Route/TableRoute.swift:14-29`, `Route/TableDetailRoute.swift:17-40`
- **What:** All three route enums implement `RawRepresentable` with the identical pattern: build `"token/\(id.uuidString)"` in `rawValue`, then in `init?(rawValue:)` split on `"/"`, extract `token`/`idString`, parse the `UUID`, and switch on `token`.
- **Why:** Same ~15-line parsing/encoding boilerplate copied 3× in this module alone, and the identical shape almost certainly recurs in every other module's Route files — exactly the kind of shared plumbing CoreRPG should own.
- **Action:** Add a CoreRPG helper — a `SingleIdRoutable`/`TaggedIdRoute` protocol or a static `parseTaggedId(_:cases:)` function — that each route's `init?(rawValue:)`/`rawValue` can delegate to, keeping only the per-case `String`↔`enum` mapping local.
- **Severity:** Medium

### 9.7 Duplicated `formatEntries` text-flattening helper across 3 modules
- **Location:** `Route/TableExtractionDestination.swift:33-44`
- **What:** `formatEntries(_ model: TableModel) -> String` (builds `"- name: content"` lines from a model's entries for AI-extraction input) has the same shape in `AdventureRPG/Route/AdventureExtractionDestination.swift` and `MapRPG/Route/MapExtractionDestination.swift`.
- **Why:** Same list-flattening logic duplicated 3× for feeding `TextSummaryExtractionView`.
- **Action:** Move to CoreRPG as a generic helper operating on name/content pairs, e.g. `TextSummaryExtractionFormatter.formatEntries(name:content:pairs:)`.
- **Severity:** Low

### 9.8 Duplicated boilerplate within `PreviewData.swift` itself
- **Location:** `Model/PreviewData.swift:14-30` vs `36-46`
- **What:** `previewFixture(models:)` and `testRoot(diceRoot:pdfRoot:)` both construct a `TableRootModel`, a fake `RootManager.preview`, a second "real" `RootManager`, and call `setUp(...)` on each sub-root — 9 of ~12 lines are copy-pasted verbatim between the two functions.
- **Why:** Any change to the setup sequence (e.g. adding a new sub-root needing `setUp`) must be made in both places or the two preview paths silently diverge.
- **Action:** Extract the shared "build root + wire up rootManager + setUp all sub-roots" sequence into a private helper (e.g. `makeWiredRoot(diceRoot:pdfRoot:) -> TableRootModel`) that both functions call, with `previewFixture` additionally inserting `models` afterward.
- **Severity:** Low

### 9.9 Oversized file: `TableGenerationController.swift` (450 lines)
- **Location:** `Controller/TableGenerationController.swift:1-451`
- **What:** Single file mixes three responsibilities: core roll/select/hide/reset generation logic (17-260), occurrence-tree construction/recursion guarding (262-350), and an entirely separate "Outcome Sheet Editing" feature (353-450) with its own doc-comment section header.
- **Why:** Exceeds the module's ~400-line informal ceiling and bundles two loosely related concerns behind one type, making independent review/testing harder.
- **Action:** Split the "Outcome Sheet Editing" extension (`beginEditingOutcomeSheet`, `endEditingOutcomeSheet`, `discardOutcomeSession`, `addOutcomeToCharacter`, `flattenOutcomeText`) into `TableGenerationController+OutcomeEditing.swift`, keeping `TableGenerationController` focused on roll/select/build-tree logic.
- **Severity:** Medium

### 9.10 Oversized file: `TableModel.swift` (418 lines)
- **Location:** `Model/TableModel.swift:1-419`
- **What:** Combines CRDT-backed domain model boilerplate, `ItemLinkRegistable` conformance, `ItemDiffComparable`/`merge`/`isSame`/`version`, private `CanonicalTableContent`/`CanonicalTableEntry` version-digest types, `ItemDuplicatable`, `ItemDataAccessable`, and a hand-written `Codable` conformance all in one file.
- **Why:** The same pattern repeats in other modules' `XModel.swift` files and is largely boilerplate driven by the CRDT/Codable/CoreData-snapshot architecture rather than Table-specific logic; grouping unrelated protocol conformances in one 418-line file makes the Table-specific bits (lines 126-178, `linkRegisterModels`) hard to find.
- **Action:** Split into `TableModel.swift` (init + stored properties only), `TableModel+Links.swift` (`ItemLinkRegistable` conformance), and `TableModel+Persistence.swift` (`ItemDiffComparable`, `Codable`, canonical-content types, `ItemDataAccessable`). Mirrors the split already present in some sibling modules.
- **Severity:** Low-Medium

### 9.11 View directly duplicates controller's private reset logic
- _See §5.7 — cross-referenced here because it is fundamentally a duplication issue (view re-implementing controller logic), not just a bug._

### 9.12 Unresolved TODOs / FIXMEs
_None found._ A repo-wide grep for `TODO|FIXME|HACK|XXX|#warning` inside `Modules/TableRPG/` returned zero matches.

### 9.13 Magic constants
- **Corner radii and layout constants** — see §8.3 (SwiftUI section) for the full list; not repeated here to avoid duplicate entries.
- **`displayState != 2`** — see §5.6.

### 9.14 Naming and formatting nits
- **Unnecessary optional binding** `if let _ = item.diceId` at `Controller/GameController.swift:106` — replace with `if item.diceId != nil`. Severity: Low.
- **Misleading variable name** `photoIds` at `Controller/LinkController.swift:109-125` collects mixed link types (photo/dice/pdf), not just photos — rename to `collectedIds`. Severity: Low.
- **Typo** "santity checks" at `Model/TableModel.swift:221` — should read "sanity checks". Severity: Low.
- **Inconsistent indentation** within `Resources/Localization+Extensions.swift:5-15` — the `Bundle.localizedString(forKey:)` extension uses 2-space indentation while `String.localizedString` immediately below uses 4-space, in the same 16-line file. Note: this extension is not dead code — CoreRPG's `EntryDataEditable.save(updated:message:)` default implementation calls `.localizedString` on already-localized strings to re-resolve them against each module's `Bundle.module`, so it's used indirectly via protocol default. Severity: Low.
- **Out-of-order import** `import SwiftUI` at `View/DetailEditorToolBarButtons.swift:14`, appearing after a `#Preview` block that already uses SwiftUI, rather than grouped with other imports at the top. Same minor issue (blank line between imports) at `Menu/TableCommands.swift:3-5`. Severity: Low.
- **Unused `root` parameter** at `Controller/ViewController.swift:38-40` — `gameListView(root: TableRootModel)` never references `root`. If protocol-mandated (check `ViewControllable`), rename to `_ root:` to signal intentional non-use; if not mandated, drop the parameter. Severity: Low.

---

## 10. Cross-cutting recommendations

1. **Consolidate the Spotlight/AppIntents plumbing into CoreRPG.** §9.3, §9.4, and §9.5 together describe ~65 lines of near-identical code copy-pasted across 5-12 modules each. This is the single highest-leverage cleanup available: three CoreRPG extractions would eliminate dozens of duplicate call sites app-wide and mean future fixes (like the iOS 27 availability gate in §4.2) only need to land once.
2. **One range-parsing implementation for table rolls.** §5.1 and §5.2 are two symptoms of the same root cause: `GameController` re-implements a simpler, buggier version of `TableGenerationController.selectorRange`/`matchingEntry`. Wherever a "roll result → matching entry" mapping exists in this codebase, it should delegate to a single shared implementation rather than being hand-rolled per call site.
3. **Gate all preview/mock fixture data behind `#if DEBUG` repo-wide.** §7.3 is explicitly a systemic pattern, not unique to TableRPG — the same shape exists in DiceRPG's and PdfRPG's `PreviewData.swift`. Worth a dedicated pass across all modules rather than fixing TableRPG in isolation.
4. **Prefer `Set`/`Dictionary` lookups over repeated `.contains`/`.first(where:)` in merge and diff loops.** §7.1 and §7.2 are the same performance anti-pattern (linear scan inside a loop that's itself iterating a collection) in two different controllers. Worth a quick sweep of other modules' `merge`/`update` functions for the same shape.
5. **Controllers should expose the mutation methods views need, not force views to replicate them.** §5.7 is a small instance of a real architecture rule: if a view needs to reset controller-owned state, the fix belongs in the controller's public surface, not copy-pasted into the view.

---

## 11. What was NOT audited

- Algorithmic correctness of the CRDT merge algorithm itself (`CRDTDataUpdate`, `CRDT` wrapper types) — treated as a CoreRPG black box; only TableRPG's *usage* of it was reviewed.
- `Modules/TableRPG/Resources/Model.xcdatamodeld` structure beyond the CloudKit-optionality spot check in §6 — schema design, indexing, and migration history were not reviewed.
- Build settings, scheme configuration, and Xcode project structure beyond what's visible in the shared `MasterRPG` scheme.
- Third-party SPM dependency internals (none are TableRPG-specific; the module depends only on sibling first-party modules: CoreRPG, DiceRPG, PdfRPG, GeneratorRPG).
- Deep test-coverage assessment of `Tests/TableRPGTests/` — noted where a specific test asserts buggy behavior (§5.1, §5.8), but no broader coverage review was performed.
- Localization wording/correctness in `Resources/Localizable.xcstrings` — only presence of `bundle: .module` usage was spot-checked.
- Cross-module duplication beyond what surfaced incidentally while auditing TableRPG (§9.3-9.7 name the other modules affected, but those modules' own code was not independently audited).
- Performance profiling / Instruments traces — §7 findings are static-analysis "potential hot path" observations, not measured.
- `GameRPG`'s and `RolePlayGameKit`'s consumption of TableRPG's public API beyond confirming call-site existence (or absence, per §5.1/§5.8) via repo-wide grep.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line. Every finding above with a `Controller/`, `Model/`, or `View/` location was directly opened and read during this audit (not just grep-matched by the delegated sub-agents) before being included.

- **§5.1** — open `Controller/GameController.swift`, lines 101-126. Confirm the `.dice` case checks only `result <= last` with no corresponding lower-bound comparison, and compare against the correct `ClosedRange.contains` pattern at `Controller/TableGenerationController.swift:219-244`.
- **§5.2** — open `Controller/GameController.swift`, line 108, and compare its `.split(separator: "-")` against `Controller/TableGenerationController.swift:222-224`, which additionally matches `–`/`—`.
- **§5.4** — open `Controller/LinkController.swift`, lines 106-127. Confirm the `switch $0.module` has cases only for `.photo`, `.dice`, `.pdf`, with `default: break` silently dropping everything else including `.table`.
- **§5.5** — open `Controller/DataController.swift`, lines 21-34 and 74-80. Confirm both `mapSnapshot` and the entry `map` function use `model.uuid ?? UUID()`.
- **§5.7** — open `View/TableGenerationOccurrenceHeaderView.swift`, lines 150-174, and compare the `catch` block's three assignments against `Controller/TableGenerationController.swift:305-312`'s `clearPendingRoll(in:)`.
- **§7.1** — open `Model/TableModel.swift`, lines 184-193. Confirm the `compactMap` closure calls `.first { $0.id == id }` on both `entries` and `other.entries` per iterated id.
- **§7.2** — open `Controller/SheetController.swift`, lines 99-134. Confirm `entryIds` is typed `[UUID]` (not `Set<UUID>`) and used with `.contains` in two closures, plus `.first(where:)` inside the main `for entry in model.entries` loop.
- **§3.1** — open `Model/TableModel.swift`, lines 180-228 and 407-418. Confirm each `nonisolated` conformance body is wrapped in `assumeMainActorIsolated { ... }`.

If any finding doesn't reproduce when you visit the line, flag it and it will be re-investigated.
