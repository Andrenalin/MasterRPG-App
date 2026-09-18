# AdventureRPG Module Code Audit

Generated 2026-09-17. Scope: **Modules/AdventureRPG** only (56 Swift files, ~4,358 lines) — Controller, Intent, Menu, Model, Resources, Root, Route, View. No other module's source was edited or is in scope, though sibling modules (CoreRPG, MapRPG, TableRPG, etc.) were read for comparison where a finding claims "this module didn't adopt a shared pattern that others did."

A clean build of the dedicated `AdventureRPG` Xcode scheme (`xcodebuild -scheme AdventureRPG clean build`) produced **zero compiler warnings** inside this module, so there is no compiler-warning list to trace here — every concurrency/modernity finding below was found by direct reading, not by following a warning.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

---

## 1. Executive summary

1. **[Critical] Unbounded recursion in cross-module link collection can crash via stack overflow** — §5.1 — `Modules/AdventureRPG/Controller/LinkController.swift:180-222`. Two adventures linking to each other recurse forever.
2. **[High] Folder merge resurrects deleted children after CloudKit sync** — §5.3 — `Modules/AdventureRPG/Model/AdventureModel.swift:158-186`. A deletion made offline silently comes back after the next merge.
3. **[High] Quick-editor entry merge matches by name, corrupting entries with duplicate IDs** — §5.4 — `Modules/AdventureRPG/Controller/EditController.swift:298-305`. Two same-named entries collapse into one ID; one edit is silently lost.
4. **[Medium] `collectLinks(of:)` ignores its own `module` parameter** — §5.2 — `Modules/AdventureRPG/Controller/LinkController.swift:181-222`. Always collects photo links regardless of what was asked for.
5. **[Medium] User-authored adventure names logged with `privacy: .public`** — §6.1 — `Modules/AdventureRPG/Controller/LinkController.swift:150,157,173`. Campaign content leaks into unredacted system logs/sysdiagnose.
6. **[Medium] PDF export has no error propagation and an unstable, collision-prone filename** — §5.5 — `Modules/AdventureRPG/Intent/AdventureEntity.swift:58-92`.
7. **[Medium] Duplicate/convert-to-group recursion has no cycle guard** — §5.7 — `Modules/AdventureRPG/Controller/EditController.swift:234-272`. Same missing-visited-set pattern as the Critical item, lower likelihood.
8. **[Medium] AdventureRPG is the one module that hasn't adopted three shared refactors already rolled out to all 10 siblings** — §9.5, §9.7, §9.8 — `LinkController.swift`, `ExportController.swift`, `ImportController.swift`, `GameController.swift`, Route files, Intent files.
9. **[Medium] Untracked fire-and-forget `Task`s with no cancellation** — §3.1, §3.2 — `LinkController.swift:107-109`, `AdventureRootModel.swift:312-328`.
10. **[Medium] 6 of 9 `AdventureEditModel` selection properties are dead state** — §9.3 — `Modules/AdventureRPG/Controller/EditController.swift:22-32`.

---

## 2. Quick wins (≤30 min each)

- **Remove unused `import RegexBuilder`** — `Modules/AdventureRPG/Controller/EditController.swift:9`. No `Regex` API is used in the file. See §9.11.
- **Fix comment typo "santity checks" → "sanity checks"** — `Modules/AdventureRPG/Model/AdventureModel.swift:199`. See §9.12.
- **Fix mislabeled log: "Table" → "Adventure"** — `Modules/AdventureRPG/Controller/ExportController.swift:130`. Copy-pasted from TableRPG; misleads anyone debugging export-link warnings. See §5.9.
- **Drop `privacy: .public` on adventure-name log lines** — `Modules/AdventureRPG/Controller/LinkController.swift:150,157,173`. See §6.1.
- **Delete 3 unused `AdventureModel` preview fixtures** — `Modules/AdventureRPG/Model/PreviewData.swift:165-189` (`testViewModel`, `testViewModel2`, `testViewModel3`). See §9.4.
- **Delete or wire up `collectPhotos`'s dead 6 selection properties** — `Modules/AdventureRPG/Controller/EditController.swift:22-32`. See §9.3.

---

## 3. Concurrency

### 3.1 Untracked fire-and-forget `Task` in `toggleTextLink`
- **Location:** `Modules/AdventureRPG/Controller/LinkController.swift:107-109`
- **What:** `Task { await toggler?(itemId, itemControllable.config.module) }` is spun up with no stored handle, cancellation, or error handling.
- **Why:** If the owning view/text is dismissed or the item deleted before the toggler completes, the task can't be cancelled and any failure is silently dropped, risking mutation against stale state.
- **Action:** Capture the task so it can be cancelled, or make the caller `async` and `await` it directly instead of fire-and-forget.
- **Severity:** Medium

### 3.2 Untracked fire-and-forget `Task` in `AdventureRootModel.validate()`
- **Location:** `Modules/AdventureRPG/Root/AdventureRootModel.swift:312-328`
- **What:** `validate()` is a synchronous function whose entire body is wrapped in `Task { @MainActor in ... }` with no stored handle, no de-duplication, and no way for the caller to observe completion or errors.
- **Why:** Repeated quick calls (e.g. double-triggered from UI) can launch overlapping validation passes across all sibling roots with no cancellation of the prior run.
- **Action:** Make `validate()` itself `async` and propagate to callers, or store the `Task` and cancel any in-flight run before starting a new one.
- **Severity:** Medium

### 3.3 Two-phase init via `preconditionFailure` on struct-held `RootManager`
- **Location:** `Modules/AdventureRPG/Controller/LinkController.swift:28-33`, `Modules/AdventureRPG/Controller/ExportController.swift:30-35`, `Modules/AdventureRPG/View/AdventureSheet.swift:97-115`
- **What:** `LinkController`/`ExportController` are `struct`s holding `var rootManager: RootManager?`, set only after construction inside `AdventureRootModel.setUp(root:context:)`. Any use before that traps via `preconditionFailure`. `AdventureSheet` does the same for `rootController.rootManager`.
- **Why:** Being value types, any copy taken before `setUp()` runs carries a permanently-nil `rootManager` and crashes on first use rather than degrading — a real (if currently theoretical, per the pre-existing "must call setUp() first" contract) two-phase-init hazard if a lazy property ever captures these controllers early.
- **Action:** Either make `rootManager` a required init parameter (pass it in rather than mutate post-construction), or guarantee `setUp()` runs before any lazy property that could capture these controllers is realized.
- **Severity:** Medium

### 3.4 Runtime-only `MainActor.assumeIsolated` escape hatch in `nonisolated` protocol conformances
- **Location:** `Modules/AdventureRPG/Model/AdventureModel.swift:158-186` (`merge`), `:188-206` (`isSame`), `:220-233` (`duplicate`/`duplicateWithoutCopy`), `:310-317` (`Comparable.<`), `:334-351` (`Codable.encode`)
- **What:** Every `nonisolated` protocol requirement (`ItemDiffComparable`, `ItemDuplicatable`, `Comparable`, `Codable`) reads `@MainActor`-isolated CRDT-wrapped state by routing through `assumeMainActorIsolated`, which calls `MainActor.assumeIsolated` — a runtime trap, not a compile-time guarantee.
- **Why:** If any of these is ever reached off the MainActor (e.g. `Array<AdventureModel>.sorted()`, `Set`/`Dictionary` hashing, or `Codable` machinery invoked from a background import/export/sync path), the app crashes instead of failing to compile. This is a documented, deliberate trade-off (comment cites a prior audit), not a new bug, but it's a live trap surface that must be re-verified whenever `SyncDataController`/`ImportController`/`ExportController` change.
- **Action:** Audit every call site of `merge`/`isSame`/`duplicate`/`<`/`encode(to:)` to confirm none are reachable from a non-MainActor context, and keep that list current as those controllers evolve.
- **Severity:** Medium

### 3.5 Non-`Sendable`-annotated async closure captured across an unstructured `Task` boundary
- **Location:** `Modules/AdventureRPG/Controller/LinkController.swift:101-109` (`toggler: ((UUID, NetworkModules) async -> Void)?`, from CoreRPG's `LinkControllable`)
- **What:** The `toggler` closure parameter isn't marked `@Sendable`, yet it's captured and invoked inside a freestanding `Task { }` at line 107.
- **Why:** Compiles cleanly today under Swift 6.3's region-based isolation, but is fragile — any future change that captures `toggler` in more than one place, or switches this to `Task.detached`, could reintroduce a real data race the type system won't catch, since the parameter type itself isn't `Sendable`.
- **Action:** Mark the `toggler`/`editAction` closure parameters `@Sendable` at their declaration in CoreRPG's `LinkControllable`, or document why it's safe not to at this call site.
- **Severity:** Low

---

## 4. API modernity

_No findings._ Verified clean against every rule in this repo's Swift/SwiftUI style guide: no `String(format:)`, no legacy `Formatter` subclasses, no `replacingOccurrences`, no old-style GCD (`DispatchQueue.main.async`), no `.contains()` for user-input filtering, no pre-modern `URL` construction, no `@available` guard below the iOS 26 deployment target, no lingering `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject`/`@EnvironmentObject`, and all 3 `@Observable` classes (`AdventureModel`, `EditController`'s `AdventureEditModel`, `AdventureRootModel`) are correctly `@MainActor`. The one `@available(iOS 27, macOS 27, visionOS 27, *)` guard in `Intent/AdventureEntity.swift:110,115` is forward-looking (above the current 26 target, compiler-gated), not dead code.

(SwiftUI-specific modernity items — `AnyView`, struct-literal shapes, view decomposition — are grouped under §8 instead, since they map directly to this repo's SwiftUI-specific style rules.)

---

## 5. Bugs / logic errors

### 5.1 Unbounded recursion in cross-module link collection — stack-overflow crash risk
- **Location:** `Modules/AdventureRPG/Controller/LinkController.swift:180-222` (`collectLinks(of:from:)`)
- **What:** Verified by reading: for a `.adventure`-typed entry link with no `entryId` (an item-level adventure→adventure link), line 211-214 recurses into `resolvedRootManager.adventureRoot.linkControllable.collectLinks(of:from:)` with no visited-set or depth guard — unlike CoreRPG's own `bfsExportResults` helper, which explicitly tracks visited IDs to stay cycle-safe.
- **Why:** Two adventures that link to each other at the item level (a natural GM pattern — e.g. a "sequel hook" entry linking forward, and the sequel linking back) cause A→B→A→B… recursion with no base case, crashing via stack overflow. Reachable today through `EditController.collectPhotos(itemId:entryId:)` (`Modules/AdventureRPG/Controller/EditController.swift:337-343`), a real user-facing "collect linked photos" action, and through any other module's `LinkController` that calls into this public `LinkControllable` method.
- **Action:** Thread a `visited: Set<UUID>` through `collectLinks` (mirroring `bfsExportResults`'s pattern) and stop recursing into an itemId already visited.
- **Severity:** Critical

### 5.2 `collectLinks(of:)` ignores its own `module` parameter
- **Location:** `Modules/AdventureRPG/Controller/LinkController.swift:181-222`
- **What:** The function is typed as "collect links of module X from itemId," but unconditionally collects the item's own `photoId` (line 184-186) and any `.photo`-typed entry link (line 190-192) regardless of the `module` argument — `module` is only ever forwarded to nested recursive calls, never compared against `$0.module` at the current level.
- **Why:** Currently masked because the only call site (`EditController.collectPhotos`, line 338) always passes `.photo`. But it's a public `LinkControllable` protocol requirement any module can call with any value (the identical bug/pattern exists in `Modules/MapRPG/Controller/LinkController.swift:103-138`). A future caller passing e.g. `.audio` would silently get photo IDs mixed into what it asked for.
- **Action:** Either rename to reflect actual behavior (`collectPhotoLinks(from:)`) or switch on `module` before deciding what to collect at the current level.
- **Severity:** Medium

### 5.3 Folder-entries merge resurrects deleted children after CloudKit sync
- **Location:** `Modules/AdventureRPG/Model/AdventureModel.swift:158-186` (`merge(_:)`)
- **What:** Verified: for `category == .folder`, merge bypasses the model's normal last-write-wins `CRDTDataUpdate.merged` (used for every other category and for non-folder entries) and instead unions entry IDs from both sides (`Set(entries.map(\.id)).union(other.entries.map(\.id))`), keeping anything found on either side.
- **Why:** `CRDTDataUpdate.merged` is whole-array LWW — the more recently updated side wins atomically, so a deletion on the winning side stays a deletion. The folder-specific union has no tombstone concept: if a user removes a child from a folder on Device A while Device B is offline, the next CloudKit merge re-adds it via the union, silently resurrecting a deletion the user explicitly made.
- **Action:** Track per-child removal (tombstones) for folder membership, or switch folders to the standard LWW merge and accept losing concurrent additions instead of silently resurrecting concurrent deletions.
- **Severity:** High

### 5.4 Quick-editor entry merge matches by name, causing duplicate entry IDs
- **Location:** `Modules/AdventureRPG/Controller/EditController.swift:298-305` (`merge(itemId:entries:)`)
- **What:** Verified: `entries.map { entry in var foundEntry = item.entries.first(where: { $0.name == entry.name }); foundEntry?.content = entry.content; return foundEntry ?? entry }` matches incoming entries to existing ones by `name`, not `id`.
- **Why:** RPG content commonly has duplicate entry names ("Room", "Trap", "Encounter"). If two incoming entries share a name, both match the same existing entry via `first(where:)`, producing two `AdventureEntryModel` values with the same `id` but different content — silently corrupting `entries` since id-keyed lookups (`AdventureModel.subscript(id:)`, `isSame`'s indexed comparison) only ever see the first, and the second edit is lost.
- **Action:** Match incoming entries by `id` when available, falling back to name only for genuinely new entries; de-duplicate before merging.
- **Severity:** High

### 5.5 PDF export: no error propagation, unstable filename
- **Location:** `Modules/AdventureRPG/Intent/AdventureEntity.swift:58-92` (`Transferable.transferRepresentation`, `.pdf` `FileRepresentation`)
- **What:** The PDF is written to `URL.cachesDirectory.appending(component: "\(item.name).pdf")`. If `CGContext(url as CFURL, mediaBox: &box, nil)` fails, the closure returns early with no page written, yet a URL is still handed back as if export succeeded.
- **Why:** (1) Using the mutable, non-unique `item.name` as the on-disk filename means exporting two adventures with the same title — or the same adventure twice concurrently from two share-sheet invocations — overwrites/races on the same Caches file. (2) A failed `CGContext` init silently yields an empty/stale PDF URL with no error surfaced to the caller or Share Sheet.
- **Action:** Derive the filename from `item.id` instead of the display name; throw/propagate a failure instead of silently returning when `CGContext` init fails.
- **Severity:** Medium

### 5.6 Entry index conversion can trap on very large entry lists
- **Location:** `Modules/AdventureRPG/Controller/DataController.swift:90-96` (`map(_ viewModel:into:index:)`)
- **What:** `model.index = Int16(index)` is a non-failable, unclamped `Int` → `Int16` conversion, matching the Core Data schema's `Integer 16` for `RPGAdventureEntry.index`.
- **Why:** Traps if an adventure ever accumulates more than 32,767 entries. Unlikely from normal UI usage, but imported `.gmz` files are untrusted, shared input — a corrupted or crafted import with an oversized entries array crashes on save rather than failing gracefully.
- **Action:** Clamp with `Int16(clamping: index)` or validate/reject imports exceeding the limit with a user-facing error.
- **Severity:** Low

### 5.7 Duplicate/convert-to-group recursion has no cycle guard
- **Location:** `Modules/AdventureRPG/Controller/EditController.swift:234-272` (`duplicateFolderEntries`, `duplicateSubAdventure`)
- **What:** Both functions recurse into child/group models (`entry.childId` / `entry.adventureId`) with no visited-set — the same missing-guard shape as §5.1's `collectLinks`.
- **Why:** If a folder/group hierarchy ever becomes self-referential (corrupted CloudKit sync data, or a future bug in group creation), duplicating that item recurses forever and crashes. Lower likelihood than §5.1 since today's UI flows (`groupFolders`/`addNewGroup`/`convertToGroup`) don't appear to let a user directly create such a cycle, but there's no defensive check if the data is ever inconsistent.
- **Action:** Add a visited-id set to both recursive helpers, matching the fix recommended for §5.1.
- **Severity:** Medium

### 5.8 Silently swallowed Spotlight re-indexing error
- **Location:** `Modules/AdventureRPG/Intent/AdventureShortcutCatalog.swift:90-98` (line 97)
- **What:** `reindexAll(root:)` calls `try? await CSSearchableIndex.default().indexAppEntities(entities)`, discarding any thrown error with no logging.
- **Why:** Inconsistent with the rest of the module — `AppendAdventureSectionIntent.swift:38-40` and `DeleteAdventureIntent.swift:28-41` both propagate/branch on the same API's errors — and a real indexing failure (disk full, index corruption) is now invisible for debugging.
- **Action:** Log the discarded error via `Logger.appIntents` (already used elsewhere in this module) instead of silently dropping it.
- **Severity:** Low

### 5.9 Export error log mislabels the module as "Table"
- **Location:** `Modules/AdventureRPG/Controller/ExportController.swift:130`
- **What:** `Logger.exportController.error("Table \(item.name, privacy: .private) export is not handling link ...")` — this is AdventureRPG's `ExportController`, but the message says "Table," clearly copy-pasted from TableRPG's equivalent without updating the literal.
- **Why:** Misleading diagnostic output makes future debugging of dropped/unhandled export links harder.
- **Action:** Change "Table" to "Adventure" (or interpolate `itemController.config.module` dynamically).
- **Severity:** Low

---

## 6. Security

### 6.1 User-authored adventure names logged with `privacy: .public`
- **Location:** `Modules/AdventureRPG/Controller/LinkController.swift:150, 157, 173`
- **What:** `Logger.linkController.warning/info("Adventure: \(replacedItem.name, privacy: .public) ...")` explicitly marks the adventure's title as public in three log lines (broken photo/dice link reset, link-repair notice).
- **Why:** Adventure names are user-created campaign/story content. `.public` logging means the string appears unredacted in the unified log, sysdiagnose bundles, and Console.app. Contrast with `ExportController.swift:130`, which correctly logs the equivalent item name as `.private`.
- **Action:** Drop the explicit `privacy: .public` (default is already redacted) or switch to `.private` to match the pattern used elsewhere in this module.
- **Severity:** Medium

No hardcoded secrets/API keys/tokens found (module makes no external network calls — CoreData/CloudKit + cross-module linking only). Core Data schema (`Resources/Model.xcdatamodeld/Adventure.xcdatamodel`) was checked against the CloudKit requirement that every attribute have a default or be optional, and every relationship be optional: **fully compliant**, no violations.

---

## 7. Performance

### 7.1 `repairLinks` calls all 10 sibling `repairLink` methods per link, unconditionally
- **Location:** `Modules/AdventureRPG/Controller/LinkController.swift:127-143`
- **What:** For every link in every entry, `repairLinks` sequentially calls `repairLink` on all 10 sibling `linkControllable`s (audio, dice, map, pdf, photo, rule, space, table, character, weather) plus itself, rather than dispatching to the one relevant module.
- **Why:** 10x redundant calls per link on every `validateLinks` pass. Minor at today's scale, but it's also the same duplication root cause covered in §9.5 — fixing that dispatch pattern fixes this performance cost as a side effect.
- **Action:** See §9.5 — dispatch by `link.module` (as `handleTextLink` already does) or iterate `root.siblingModuleRoots` instead of hand-listing all 10.
- **Severity:** Low

No other performance findings surfaced: no heavy work in SwiftUI view bodies, no synchronous large-collection operations, no repeated CoreData re-fetches, and no O(n²) list/search patterns were found in this module's View/Search/FolderList code.

---

## 8. SwiftUI / UI

### 8.1 `AnyView` type-erasure required by a cross-module protocol
- **Location:** `Modules/AdventureRPG/Controller/ViewController.swift:15-21, :30-40`
- **What:** `thumbnailRowView(for:)` (×2) and `batchExtractionView(...)` wrap their SwiftUI content in `AnyView`.
- **Why:** Directly against this repo's "avoid `AnyView` unless absolutely required" rule — verified it *is* currently required, because CoreRPG's `ViewControllable` protocol (`Modules/CoreRPG/Controllable/ViewControllable.swift:60,63,81`) declares these requirements returning `AnyView`/`AnyView?` directly, and that protocol is used polymorphically as `any ViewControllable` across all 11 modules. `some View` can't be substituted here without a wider protocol redesign.
- **Action:** Not fixable inside AdventureRPG alone — flag for a cross-module follow-up on `ViewControllable` (e.g. evaluate an `any View` boxing scheme now that the deployment target is iOS/visionOS 26) rather than editing this module in isolation.
- **Severity:** Low

### 8.2 `RoundedRectangle` struct instance instead of static member
- **Location:** `Modules/AdventureRPG/View/DropChooseView.swift:28, :32`
- **What:** `RoundedRectangle(cornerRadius: 24, style: .continuous)` is instantiated directly inside `.background { }`/`.overlay { }`, inconsistent with this repo's "prefer static member lookup" rule — and with this exact file's correct `.clipShape(.rect(corners: .concentric))` three lines above (line 18).
- **Why:** Mixed style within a single view; the static-member form is the project's stated convention.
- **Action:** Replace with the modifier equivalents, e.g. `.background(Color.accentColor.tertiary, in: .rect(cornerRadius: 24, style: .continuous))`.
- **Severity:** Low

### 8.3 Toolbar content split via computed property instead of a dedicated type
- **Location:** `Modules/AdventureRPG/View/DetailListView.swift:52-71`
- **What:** `@ToolbarContentBuilder var toolbarContent: some ToolbarContent` decomposes the toolbar as a computed property on `DetailListView`.
- **Why:** This repo's rule "do not break views up using computed properties; place them into new View structs instead" applies equally to `ToolbarContent` — the same coupling-to-parent-identity problem the rule targets.
- **Action:** Extract into a standalone `ToolbarContent`-conforming type (e.g. `DetailListToolbarContent`) taking `root`/`model` as parameters.
- **Severity:** Low

### 8.4 Route destination-view naming has six different schemes in one small folder
- **Location:** `Modules/AdventureRPG/Route/AdventureRoute.swift:58` (`DestinationAdventureRouteView`), `AdventureDetailRoute.swift:65` (`DestinationDetailAdventureRouteView`), `AdventureEditorRoute.swift:31` (`DestinationAdventureEditorRouteView`), `DetailRoute.swift:41` (`ViewerRouteDestinationView`), `SelectionRoute.swift:23` (`SelectionDestinationView`), `AdventureExtractionDestination.swift:8` (`AdventureExtractionDestination`, no `View` suffix)
- **What:** Six Route files use six different naming shapes for "the view a route case renders": `Destination<X>RouteView`, `<X>RouteDestinationView` (reversed order), `<X>DestinationView`, and a bare `<X>Destination` struct.
- **Why:** Makes it harder to predict a destination view's name from its route and to grep consistently across the folder.
- **Action:** Standardize on the majority pattern (`Destination<X>RouteView`); rename the other three to match.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Files to delete outright
_None._ No file in this module is wholly dead, `#if false`'d, or a stale `_OLD`/`Legacy`/`v1` copy.

### 9.2 `EditController.collectPhotos` never called from production code
- **Location:** `Modules/AdventureRPG/Controller/EditController.swift:337-343`
- **What:** `collectPhotos(itemId:entryId:)` is called only by `Tests/AdventureRPGTests/EditControllerTests.swift:125` — no View/Route/Intent calls it.
- **Action:** Wire it into a View/Route if it's an intended feature, or delete it and its test.
- **Severity:** Low

### 9.3 6 of 9 `AdventureEditModel` selection properties are dead state
- **Location:** `Modules/AdventureRPG/Controller/EditController.swift:22-32`
- **What:** `selectionAudio`, `selectionCharacter`, `selectionMap`, `selectionSpace`, `selectionTable`, `selectionWeather` are declared but referenced nowhere outside their own declaration; only `selectionDice`, `selectionPdf`, `selectionPhoto` are used (by `DiceDropSection.swift`/`PhotoDropSection.swift`/`QuickEntryEditor.swift`).
- **Why:** Each is a live `ItemSelectionModel()` allocated on every `EditController` construction for no purpose — likely an abandoned feature (planned drop sections never built) or copy-paste from another module.
- **Action:** Delete the 6 unused properties, or if planned, track with a ticket reference instead of silently carrying dead state.
- **Severity:** Medium

### 9.4 Three unused `AdventureModel` preview/test fixtures
- **Location:** `Modules/AdventureRPG/Model/PreviewData.swift:165-189`
- **What:** `testViewModel`, `testViewModel2`, `testViewModel3` (with `uuid2`/`uuid3` constants) are never referenced anywhere (`uuid2` is separately reused by `previewFixtures` — keep that constant).
- **Action:** Delete the three unused model fixtures.
- **Severity:** Low

### 9.5 Hand-listed per-sibling-module dispatch instead of the existing `siblingModuleRoots` abstraction
- **Locations:** `Modules/AdventureRPG/Controller/LinkController.swift:37-70` (`handleTextLink`), `:72-98` (`toggleLink`), `:127-143` (`repairLinks`), `:180-222` (`collectLinks`); `Modules/AdventureRPG/Controller/ExportController.swift:42-55, 57-158, 160-171`; `Modules/AdventureRPG/Controller/ImportController.swift:36-47`; `Modules/AdventureRPG/Controller/GameController.swift:75-87`
- **What:** Each of these hand-writes a 9-or-10-case switch/sequential-call list dispatching to every sibling module by name, five separate times across four files.
- **Why:** `AdventureModuleRoot.swift:37-44` already exposes `siblingModuleRoots: [any AdventureModuleRoot]` for exactly this — used correctly by `AdventureRootModel`'s own `resetData()`/`save()`/`validate()` and by this module's `SheetController.swift:72,173`. `ExportController.additionalExport`'s hand-numbered `ids1...ids9` variables are especially fragile: adding a module means renumbering every subsequent variable.
- **Action:** Replace each hand-listed switch/call chain with iteration over `root.siblingModuleRoots` (or `RootManager.rootModel(for:)`, as `SheetController` already does).
- **Severity:** Medium

### 9.6 `AdventureRootModel.init` constructs 18 near-identical `ItemSelectionModel` instances
- **Location:** `Modules/AdventureRPG/Root/AdventureRootModel.swift:72-101`
- **What:** `editorLinkModel` (11 calls) and `playerLinkModel` (7 calls) each pass `ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: <bool>)`, identical except the trailing bool.
- **Action:** Add a small local factory (e.g. `.multiSelection(allowEntrySelection:)`) instead of repeating all 4 named parameters 18 times.
- **Severity:** Low

### 9.7 Route parsing hand-copied instead of CoreRPG's `TaggedIdRoute`
- **Location:** `Modules/AdventureRPG/Route/AdventureRoute.swift:15-30`, `AdventureDetailRoute.swift:14-37`, `DetailRoute.swift:15-30`
- **What:** All three hand-implement `split(separator: "/")` / `UUID(uuidString:)` parsing for `RawRepresentable`.
- **Why:** `CoreRPG/Route/TaggedIdRoute.swift` exists specifically to eliminate this boilerplate; only `TableRPG`'s three Route files have adopted it. AdventureRPG's equivalents are pre-refactor.
- **Action:** Migrate to `TaggedIdRoute.rawValue(token:id:)` / `TaggedIdRoute.parse(_:resolve:)`, mirroring TableRPG.
- **Severity:** Medium

### 9.8 Intent files don't use CoreRPG's shared Spotlight-indexing helpers
- **Location:** `Modules/AdventureRPG/Intent/CreateAdventureIntent.swift:33,38-41`; `AppendAdventureSectionIntent.swift:31,36-41`; `DeleteAdventureIntent.swift:27-41`; `AdventureShortcutCatalog.swift:90-98`
- **What:** Each hand-copies the same `CSSearchableIndex` indexing/deletion body.
- **Why:** `CoreRPG/Controllable/IntentEntityHelpers.swift` provides `intentPlainText(from:)`, `indexIntentEntities(_:)`, `deleteIntentEntities(ids:ofType:)` to replace exactly this; AudioRPG, CharacterRPG, DiceRPG, GeneratorRPG, MapRPG, PdfRPG, PhotoRPG, SpaceRPG, TableRPG, and WeatherRPG have all adopted it — AdventureRPG is the one holdout.
- **Action:** Replace the 4 call sites with the shared helpers.
- **Severity:** Medium

### 9.9 Intent files not consolidated into a single `*ManagementIntents.swift` like every sibling module
- **Location:** `AppendAdventureSectionIntent.swift`, `CreateAdventureIntent.swift`, `DeleteAdventureIntent.swift`
- **What:** Every sibling module groups Create/Delete/Update-style intents into one `<Module>ManagementIntents.swift`; AdventureRPG keeps three standalone files.
- **Action:** Merge into `AdventureManagementIntents.swift` to match the established convention.
- **Severity:** Low

### 9.10 `DiceDropSection`/`PhotoDropSection` near-duplicate views
- **Location:** `Modules/AdventureRPG/View/DiceDropSection.swift:1-28`, `PhotoDropSection.swift:1-28`
- **What:** Identical structure (root/model properties, a drop-choose call, an `.onChange` calling `add(<field>Id:itemId:)`, a `.task(id:)` resetting selection), differing only in module/field.
- **Why:** A third module link would copy this file again; also explains why the other 6 selection properties in §9.3 are unused (this pattern was never extended to them).
- **Action:** Extract a generic `LinkDropSection<Module>` view, or accept as intentional boilerplate at 2 instances (a 3rd copy should tip this into "must template").
- **Severity:** Low

### 9.11 Unused `import RegexBuilder`
- **Location:** `Modules/AdventureRPG/Controller/EditController.swift:9`
- **What:** Imported but no `Regex`/`RegexBuilder` API is used in the 344-line file.
- **Action:** Remove the import.
- **Severity:** Low

### 9.12 Comment typo
- **Location:** `Modules/AdventureRPG/Model/AdventureModel.swift:199`
- **What:** `// santity checks` should read `// sanity checks`.
- **Action:** Fix.
- **Severity:** Low

### 9.13 `AdventureDataController` reads as part of the main controller hierarchy but isn't
- **Location:** `Modules/AdventureRPG/Controller/AdventureDataController.swift:1-29`
- **What:** A standalone `@MainActor` struct with one method, used only by the Share Extension (`Sources/RPGShare/ShareExtensionSaveController.swift`) and its own test — not one of the 12 controllers the module's documented architecture enumerates, and not constructed by `AdventureRootModel`. It builds its own throwaway `DataController` internally, duplicating `DataController`'s construction logic.
- **Action:** No functional change needed; consider a doc comment or a name (e.g. `ShareExtensionAdventureController`) that doesn't read as a sibling of `ItemController`/`EditController`.
- **Severity:** Low

### 9.14 Files approaching the 300-line refactor threshold (none exceed 500)
- **`AdventureRootModel.swift` (377 lines)** — mixes DI wiring, three protocol conformances, and game-mode helpers in one file. Severity: Low.
- **`AdventureModel.swift` (365 lines)** — mixes the CRDT-backed domain model with 7 protocol-conformance extensions. Severity: Low.
- **`EditController.swift` (344 lines)** — mixes core editing, group management, duplication, quick-link editing, and AI extraction; already has `// MARK:` sections marking natural split points. Severity: Low.
- No file in the module exceeds 500 lines.

### 9.15 Magic constants: repeated corner-radius/frame values
- **Location:** `Modules/AdventureRPG/View/DropChooseView.swift:24,26,28,32`
- **What:** `cornerRadius: 24` appears 3 times and `.frame(height: 128)` once, all as bare literals in one file.
- **Action:** Hoist to a local constant (e.g. `private let dropAreaCornerRadius: CGFloat = 24`).
- **Severity:** Low

### 9.16 Magic constant: hardcoded macOS preview frame size
- **Location:** `Modules/AdventureRPG/Model/MockData.swift:56-58`
- **What:** `.frame(width: 800, height: 600)` under `#if os(macOS)` with no named constant or comment.
- **Action:** Low priority — preview-only scaffolding; leave as-is or annotate if the size is meaningful.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Give recursive cross-module traversal a shared, cycle-safe primitive.** §5.1 and §5.7 are the same missing-visited-set bug shape in two different recursive functions (`collectLinks`, `duplicateFolderEntries`/`duplicateSubAdventure`). CoreRPG's `bfsExportResults` already solves this correctly for export — consider extracting a small generic "visited-set BFS/DFS over linked items" helper into CoreRPG that both `collectLinks`-style and `duplicate*`-style code can reuse, so future modules don't reintroduce the same trap.

2. **AdventureRPG missed a repo-wide refactor pass that every sibling module received.** §9.5 (siblingModuleRoots dispatch), §9.7 (TaggedIdRoute), and §9.8 (IntentEntityHelpers) are three independent instances of "AdventureRPG still has the pre-refactor code that 9-10 other modules already migrated off of." This suggests AdventureRPG was out of scope for those three refactor passes (perhaps because it predates them, or was skipped as "the hub module, handle it separately"). Worth a single follow-up pass applying all three refactors together, since they touch overlapping files (`LinkController.swift`, `ExportController.swift`, Route files, Intent files).

3. **Audit `privacy: .public` logging repo-wide, not just here.** §6.1 is a one-module instance of a pattern that's easy to introduce by copy-pasting a log line from a context where the data genuinely was safe to log publicly. Worth a quick grep across all modules for `privacy: .public` next to any `.name`/`.description`/user-content interpolation.

---

## 11. What was NOT audited

- Every other module (CoreRPG, AudioRPG, CharacterRPG, DiceRPG, MapRPG, PdfRPG, PhotoRPG, SpaceRPG, TableRPG, WeatherRPG, RuleRPG, GeneratorRPG, GameRPG, RolePlayGameKit) — read only where cited as comparison evidence for a duplication finding (§9.5, §9.7, §9.8), never audited in their own right.
- `Tests/AdventureRPGTests` — referenced only to confirm whether a symbol is truly dead (§9.2); no test-quality or coverage review performed.
- Build settings, scheme configuration, Xcode project structure beyond what's visible via the `AdventureRPG` scheme build.
- Third-party/SPM dependency internals (none are direct AdventureRPG dependencies beyond the sibling-module frameworks it imports).
- Localization/string-catalog correctness — `Resources/Localization+Extensions.swift` and `.xcstrings` content were not reviewed for translation accuracy.
- Algorithmic correctness of the AI Extraction feature (`EditController.swift:317-333`, `#if !os(tvOS)`) beyond the surface-level review in §5 — `TableSummaryAnalysis`'s own model/prompt logic lives outside this module.
- Performance profiling with Instruments — §7 identifies static code smells only, no traces were captured.
- Accessibility/Dynamic Type/VoiceOver review of Views under `Modules/AdventureRPG/View/` beyond the structural SwiftUI findings in §8.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference — it should land on the cited line.

- **§5.1** — open `Modules/AdventureRPG/Controller/LinkController.swift`, lines 180-222. Confirm the `.adventure` case at line 211-214 recurses into `resolvedRootManager.adventureRoot.linkControllable.collectLinks(of:from:)` with no visited-set anywhere in the function, and that line 338 of `EditController.swift` (`collectPhotos`) is a real, reachable call site.
- **§5.3** — open `Modules/AdventureRPG/Model/AdventureModel.swift`, lines 158-186. Confirm the `if mergedCategory.wrappedValue == .folder` branch uses `Set(...).union(...)` instead of `entries_.merged(other:)`, unlike every other property in the same function.
- **§5.4** — open `Modules/AdventureRPG/Controller/EditController.swift`, lines 298-305. Confirm `item.entries.first(where: { $0.name == entry.name })` — a name match, not an id match.
- **§6.1** — open `Modules/AdventureRPG/Controller/LinkController.swift`, lines 150, 157, 173. Confirm `privacy: .public` on `replacedItem.name` in all three log calls, and compare to `ExportController.swift:130`'s `privacy: .private` on the equivalent value.
- **§9.5** — open `Modules/AdventureRPG/Controller/ExportController.swift`, lines 160-171 (`additionalExport`). Confirm the `ids1...ids9` sequential-variable pattern, and compare to `Modules/AdventureRPG/Root/AdventureModuleRoot.swift:37-44`'s `siblingModuleRoots` array, which is already used correctly elsewhere in this module (`SheetController.swift:72,173`).

If any finding doesn't reproduce when you visit the line, flag the specific reference for re-investigation.
