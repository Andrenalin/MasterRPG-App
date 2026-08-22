# MasterRPG Search Feature — Code Audit

Generated 2026-08-22. **Scope: the Search feature only** — `SearchRootView`, `ListRootView`, `LinkItemRootView`, `SearchRootControllable`, and their full dependency chain, per the requested audit target (not a whole-repo audit). ~4,466 lines across 44 files were read in full: all of `Modules/GameRPG/Search/`, `Modules/CoreRPG/Controllable/{SearchRootControllable,SearchControllable,SearchListController,FolderListControllable,ListSearchTiming,ItemRootControllable}.swift`, `Modules/CoreRPG/Model/{SearchModel,SearchResult}.swift`, `Modules/CoreRPG/LGViews/ListRootView.swift`, `Modules/CoreRPG/Inspector/{LinkItemRootView,LinkItemListView,LinkItemFilterFieldView}.swift`, the two `Fake*` test doubles, and all 12 modules' `Controller/SearchController.swift` + `Controller/FolderListController.swift`. A further ~15 dependency files (`GameRootModel.swift`'s search helpers, `EditControllable.swift`, `CacheItemListModel.swift`, `FolderListModel.swift`, `TextFieldAll.swift`, several `*EntryModel.swift` files, `ItemDataModel.swift`, `ItemEditorForegroundView.swift`, `ToolbarItemListViewModifier.swift`, and the 15 call sites of `LinkItemRootView`/`ListRootView`) were read to verify specific claims below.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

**Methodology note:** a full `xcodebuild` of the `MasterRPG` scheme was run to capture compiler warnings (per the audit skill's Step 2), but it landed on a fully cached incremental build (0 warnings anywhere, `BUILD SUCCEEDED`) since none of the scoped files had pending changes — it produced no signal for this subsystem. A scoped `xcodebuild -scheme CharacterRPG` build was also run and confirmed the target's strict-concurrency settings (`SWIFT_VERSION=6.0`, `SWIFT_STRICT_CONCURRENCY=complete`) with zero warnings. Concurrency findings below therefore rest on manual reading against those settings, not compiler ground truth — treat §3 as slightly less certain than a warning-driven audit would be.

**Context found while auditing:** several files in this subsystem (`FolderListControllable.swift`, `ListSearchTiming.swift`, `SearchGlobalController.swift`) carry inline comments referencing a prior "CODE_AUDIT §9.4" and "§9.14" — evidence this exact subsystem has already been through at least one prior audit-and-fix cycle (the `copy(listModel:)` hoisting and the shared `typingDebounce` constant both show the fix already applied). This is a well-maintained area; most findings below are Medium/Low polish rather than fresh regressions.

---

## 1. Executive summary

1. **[High] Unguarded double-tap race in `FolderListControllable.add()` can create duplicate items and file them under the wrong parent** — §3.1 — `Modules/CoreRPG/Controllable/FolderListControllable.swift:283-320`.
2. **[High] Rapid folder/parent switching in the inspector can display the wrong folder's children** — §3.2 — `Modules/CoreRPG/Controllable/FolderListControllable.swift:263-267,129-150`.
3. **[High] No cycle-guard anywhere in the folder/collection tree recursion, and the write path that grows the graph doesn't prevent forming one** — §5.3 — `Modules/CoreRPG/Controllable/EditControllable.swift:223-234` + 4 recursive tree-builders.
4. **[High] The entire synchronous "mirror" search implementation (~385 lines) has zero production callers — dead code reachable only from tests** — §9.1 — `Modules/CoreRPG/Controllable/SearchControllable.swift:612-763`, `Modules/CharacterRPG/Controller/SearchController.swift` (8 method pairs).
5. **[Medium-High] `localizedCaseInsensitiveContains` used instead of the mandated `localizedStandardContains` across 7 real result-filtering sites** — §5.1 — CharacterRPG's global search + 6 `*EntryModel.filter(with:)` defaults.
6. **[Medium] `SearchListView`'s `.searchable` prompt is a bare string literal, not `Text(..., bundle: .module)` — breaks localization in every non-English locale** — §8.1 — `Modules/GameRPG/Search/SearchListView.swift:46`.
7. **[Medium] Two unrelated `SearchModel` classes share the same unqualified name** (`CoreRPG.SearchModel` vs. `GameRPG.SearchModel`), relying entirely on same-module shadowing — §9.4 — `Modules/CoreRPG/Model/SearchModel.swift`, `Modules/GameRPG/Search/SearchModel.swift`.
8. **[Medium] `ListRootView.root` is declared without the `any` existential keyword**, inconsistent with its sibling properties and the rest of the codebase — §4.1 — `Modules/CoreRPG/LGViews/ListRootView.swift:9`.
9. **[Medium] `.textContentTypeAll(.name)` on a generic item/entry filter field** risks inappropriate Contacts-app autofill suggestions on a search box — §8.2 — `Modules/CoreRPG/Inspector/LinkItemFilterFieldView.swift:21`.
10. **[Medium] Deep/wide folder trees are walked fully synchronously on `@MainActor`** with no yield point, on every search and every chevron toggle — §7.1 — `Modules/CoreRPG/Controllable/FolderListControllable.swift:399-443,499-528`.

---

## 2. Quick wins (≤30 min each)

- **Remove the dangling trailing comma + blank line** — `Modules/GameRPG/Search/SearchRootView.swift:16-17`. Cosmetic leftover from a removed parameter; harmless but looks like an incomplete edit.
- **Delete the stray commented-out modifier line** — `Modules/CoreRPG/ItemDetail/ItemEditorForegroundView.swift:51` (`//.environment(folderListController.listDisplayModel)`). See §9.10.
- **Delete `SearchTags.allCategory`** — `Modules/CoreRPG/Model/SearchModel.swift:110`. Zero references anywhere in the repo.
- **Fix `Text(String)` vs `Text(verbatim:)` inconsistency** — `Modules/GameRPG/Search/SearchResultRow.swift:29,46`. See §8.3.
- **Add `any` to `ListRootView.root`** — `Modules/CoreRPG/LGViews/ListRootView.swift:9`. One-word fix, matches every sibling property on the same struct.
- **Wrap `SearchListView`'s search prompt in `Text(..., bundle: .module)`** — `Modules/GameRPG/Search/SearchListView.swift:46`. See §8.1.
- **Remove `.textContentTypeAll(.name)` from `LinkItemFilterFieldView`** — `Modules/CoreRPG/Inspector/LinkItemFilterFieldView.swift:21`. See §8.2.
- **Delete CharacterRPG's dead "legacy helper"** — `Modules/CharacterRPG/Controller/SearchController.swift:620-623` (`inspectorSearchResults(searchText:characterId:)`). Zero callers found anywhere.

---

## 3. Concurrency

### 3.1 Unguarded double-tap race in `FolderListControllable.add()` creates duplicate items and can file them under the wrong parent
- **Location:** `Modules/CoreRPG/Controllable/FolderListControllable.swift:283-320` (`add(type:url:root:)`); triggered from `Modules/CoreRPG/LGViewModifiers/ToolbarItemListViewModifier.swift:165-169` (plain `Button { Task { await addItem(for: type) } }`, no `.disabled()` guard) and `Modules/CoreRPG/LGViews/ListRootView.swift:174-176` (drag-and-drop).
- **What:** `add()` spawns a bare, unstored, uncancelled `Task { }` on every call, with no de-duplication guard and no in-flight indicator on the triggering button; it also reads `listModel.selectedParentId` live at the end of a ~1.25s chain of `Task.sleep(for:)` calls (`newItemSettleDelay` = 1s, `headerEditorPresentationDelay` = 0.25s) rather than capturing it at call time.
- **Why:** a double-tap (trivially reachable — no disabled state, no debounce) starts two fully independent `Task`s, each calling `root.editControllable.addNew(type:)` and creating a second, unwanted item, racing to set `addedModelId`/selection/`openHeaderEditor` in unpredictable order; separately, a folder-selection change during the ~1.25s window means the new item can be filed under whatever folder happens to be selected *when the task finishes*, not the one selected when "Add" was tapped.
- **Action:** give `add()` a coalescing/cancellable task handle (mirror the `didSet { oldValue?.cancel() }` idiom `SearchModel.currentTask` already uses two files away), or disable the add affordance while a creation task is in flight; capture the target parent id at task start instead of re-reading `listModel` at completion.
- **Severity:** High. (Not Critical: the result is an extra, deletable item / occasional mis-filing, not a crash or unrecoverable data loss.)

### 3.2 Stale detail-search race on rapid folder/parent switching can display the wrong folder's children
- **Location:** `Modules/CoreRPG/Controllable/FolderListControllable.swift:263-267` (`resetDetail`, spawns `Task(name: "Initial Detail Search")`) and `:129-150` (`performDetailSearch`); enabled by `Modules/CoreRPG/Model/FolderListModel.swift:146-166` (`resetDetailList` mutates the *same* `detailListModel` instance in place on the 2nd+ call rather than replacing it); reached from `Modules/CoreRPG/Inspector/LinkItemListView.swift:66-74` (`.task(id: parentModel?.id) { resetDetail(...) }`).
- **What:** `resetDetail` deliberately bypasses the coalescing `searchModel.currentTask` token (per its own comment, precisely to avoid being cancelled by sibling initial triggers) via a raw, unstored `Task`. `performDetailSearch` captures `detailListModel`/`parentModel` at the start, awaits `scopedResults(...)`, then writes `searchModel.detailResults`/`detailListModel.list` at the end with no check that the parent is still current.
- **Why:** switching between two folders quickly in the inspector — an entirely normal browsing action — can let a slower, stale search for the *first* folder resolve after a newer one for the *second* folder, silently overwriting the UI with the wrong folder's children.
- **Action:** capture a generation/identity token at the start of `performDetailSearch` and discard the write-back if `detailListModel.parentModel?.id` no longer matches the token, or route this through a cancellable task the way `runSearch`/`scheduleSearch` already do.
- **Severity:** High.

### 3.3 `SearchControllable` protocol's `@MainActor` annotations are inconsistent across its own requirements
- **Location:** `Modules/CoreRPG/Controllable/SearchControllable.swift:9` (`@MainActor func globalSearchResults`) vs. `:10-11` (`listSearchResults`/`inspectorSearchResults`, no `@MainActor`) vs. `:14-15` (`syncListSearchResults`/`syncInspectorSearchResults`, `@MainActor`).
- **What:** every real conformer implements all five methods as `@MainActor` (CoreRPG's default extension at `:65,:271`; CharacterRPG's override at `Modules/CharacterRPG/Controller/SearchController.swift:114,:362`), but the protocol's declared contract doesn't require it uniformly.
- **Why:** a future conformer has no compiler-enforced signal that `listSearchResults`/`inspectorSearchResults` must run on MainActor, and could legally satisfy the requirement off-actor — silently breaking the "search is MainActor-only" architecture this subsystem otherwise relies on throughout.
- **Action:** add `@MainActor` to the two under-annotated requirements to match the rest of the protocol.
- **Severity:** Medium.

### 3.4 `GameRPG.SearchModel`'s manual task cancel/set duplicates — instead of reusing — `CoreRPG.SearchModel`'s established auto-cancelling idiom
- **Location:** `Modules/GameRPG/Search/SearchModel.swift:22-35` (`_searchTask`/`cancelSearch()`/`setSearchTask()`/`awaitCurrentSearch()`) and `Modules/GameRPG/Search/SearchGlobalController.swift:27-51` (`performSearch()`).
- **What:** `performSearch()` manually calls `model.cancelSearch()` before `model.setSearchTask(...)`, and wraps its real work in a second, redundant `Task { @MainActor in }` even though `performSearch()` is already `async`/`@MainActor` — instead of the `didSet { oldValue?.cancel() }` pattern `CoreRPG.SearchModel.currentTask` (`Modules/CoreRPG/Model/SearchModel.swift:54-56`) already established.
- **Why:** correctness depends entirely on call-order discipline (cancel-then-set) the compiler cannot enforce; it only works today because there is a single call site (`SearchListView.swift`'s `.task(id:)`). A future second call site that assigns without cancelling first would silently leak a running search task.
- **Action:** give `GameRPG.SearchModel` the same `didSet`-cancelling `currentTask` field and drop the redundant inner `Task` wrapper.
- **Severity:** Low-Medium.

### 3.5 Unstored, uncancelled selection-restore `Task` can be overwritten out of order
- **Location:** `Modules/CoreRPG/Controllable/FolderListControllable.swift:198-204`, inside `applyPostUpdateSelection`.
- **What:** a `Task(name: "List Selection Restore") { @MainActor in ... }`, delayed by `ListSearchTiming.selectionRestoreRenderDelay` (50ms), sets `listModel.listSelection`; nothing stores or cancels it.
- **Why:** a second rapid data-change/search within that 50ms window isn't guarded against, so this orphaned task can overwrite a newer, correct selection with the stale `addedModelId`'s selection.
- **Action:** route through the existing cancellable `currentTask` mechanism, or check a generation counter before applying.
- **Severity:** Low.

---

## 4. API modernity

### 4.1 `ListRootView.root` declared without the `any` existential keyword
- **Location:** `Modules/CoreRPG/LGViews/ListRootView.swift:9` (`let root: ItemRootControllable`).
- **What:** the very next two properties on the same struct (`:10-11`) explicitly write `any FolderListControllable` / `(any ItemDataAccessable)?`, and `LinkItemRootView`'s equivalent property (`Modules/CoreRPG/Inspector/LinkItemRootView.swift:24`) also uses `any ItemRootControllable` — `ListRootView` is the outlier.
- **Why:** bare protocol-typed properties without `any` are on Swift's own deprecation path (a future language mode with `ExistentialAny` makes this a compile error), and the inconsistency with three other properties in the same file makes it read as an oversight rather than a deliberate choice.
- **Action:** add `any` to match every sibling property and the rest of the codebase's convention.
- **Severity:** Medium.

_No other scoped file uses a deprecated iOS API, legacy GCD, `Formatter` subclass, C-style formatting, or a soft-deprecated SwiftUI modifier — confirmed by direct reading of all 44 primary files plus a clean, warning-free `CharacterRPG` scheme build._

---

## 5. Bugs / logic errors

### 5.1 `localizedCaseInsensitiveContains` used instead of the project-mandated `localizedStandardContains` across 7 real filtering sites
- **Location:** `Modules/CharacterRPG/Controller/SearchController.swift:47-48` (`globalSearchResults`'s regular-character branch); `Modules/CoreRPG/ItemList/EntryDataAccessable.swift:24-26` (default `filter(with:)`, reached via `SearchControllable.swift:34`'s default `globalSearchResults`); `Modules/AdventureRPG/Model/AdventureEntryModel.swift:62-64`; `Modules/MapRPG/Model/MapEntryModel.swift:147-149`; `Modules/TableRPG/Model/TableEntryModel.swift:50-52`; `Modules/CharacterRPG/Model/ValueEntryModel.swift:233-235`; `Modules/CharacterRPG/Model/ValueModel.swift:415-417`. (For contrast: `Modules/RuleRPG/Model/RuleEntryModel.swift:104-106` correctly uses `localizedStandardContains`, and every filtering call site inside `SearchControllable.swift`'s shared `itemMatchesFilter` — used by every module's list/folder/inspector search — is correct.)
- **What:** these seven call sites use `localizedCaseInsensitiveContains`, which is case-insensitive but not diacritic-insensitive and skips locale-tailored collation, unlike `localizedStandardContains` (CLAUDE.md: "Filtering text based on user-input must be done using `localizedStandardContains()`").
- **Why:** this is genuine result-inclusion filtering, not post-filter scoring — a plain-ASCII query (e.g. "jose") will fail to find an accented name ("José") through the cross-module global search or through any entry's default text filter, even though the identical item would be found via the module's own list/folder/inspector search path. The app explicitly supports German localization (`SearchListView.swift`'s locale-based module ordering), where accented/umlaut character and place names are common — this is a real, user-facing "can't find my character" class of bug, not a theoretical one.
- **Action:** replace all seven call sites with `localizedStandardContains(searchText)`, matching `itemMatchesFilter`'s convention already used everywhere else in this subsystem.
- **Severity:** Medium-High.

### 5.2 `calculateRelevance` scores matches with non-locale-aware string comparison, producing wrong ranking order for accented/locale-specific names
- **Location:** `Modules/CoreRPG/Controllable/SearchControllable.swift:535-571` (`calculateRelevance`), specifically the `.compare(searchText, options: .caseInsensitive)` and `.range(of: searchText, options: [.caseInsensitive, .anchored])` calls at lines 539-541.
- **What:** exact/prefix-match scoring uses plain Unicode case-folding instead of `localizedStandardContains`/locale-aware comparison, unlike the inclusion checks in the same file.
- **Why:** an item that should score as an exact/prefix match under diacritic- or locale-aware comparison (e.g. "cafe" against "Café") instead falls through to the lower generic-`localizedStandardContains` branch (+25 instead of +100/+50), visibly reordering results for non-ASCII names — a ranking bug, not merely an omission.
- **Action:** replace the `.compare`/`.range(of:)` calls with locale-aware equivalents (e.g. `localizedCompare(...) == .orderedSame` for the exact-match tier) so scoring matches the file's own filtering convention.
- **Severity:** Medium.

### 5.3 No cycle-guard anywhere in the folder/collection tree recursion; the one write path that grows the graph doesn't prevent forming a cycle
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:223-234` (`addItem(itemId:parentId:)`, only guards direct self-parenting `itemId != parentId`); `Modules/CoreRPG/Controllable/SearchControllable.swift:145-213` (`buildFolderTreeNode`) and `:702-762` (`syncBuildFolderNode`); `Modules/CoreRPG/Controllable/FolderListControllable.swift:399-443` (`appendToFlat`) and `:499-510` (`flattenCachedChildren`); `Modules/CharacterRPG/Controller/SearchController.swift:194-224,285-313` (`buildCharacterFolderNode`/`syncBuildCharacterFolderNode`).
- **What:** `addItem(itemId:parentId:)` never checks whether `parentId` is already a descendant of `itemId` before linking them — only that they aren't identical — while every recursive tree-builder that later walks `entry.childId`/`item.children` has no visited-set, no depth cap, and no cycle check.
- **Why:** if a folder/collection ever became its own indirect ancestor (via this unguarded write, an import, or a CloudKit merge conflict), every one of these recursive functions — which run synchronously on `@MainActor` on every search and every chevron toggle — would recurse forever and stack-overflow-crash. No UI path was confirmed to currently reach this state (all identified add/move call sites were not exhaustively audited), so this is a latent robustness gap rather than a reproduced crash.
- **Action:** add an ancestor-chain check to `addItem(itemId:parentId:)` before linking; add a visited-id guard (or depth cap) to the shared recursive tree builders as defense-in-depth regardless.
- **Severity:** High (latent — not confirmed reachable today, but the blast radius of an unguarded infinite recursion on the main thread warrants treating it as High rather than Medium).

### 5.4 `GameRoot.rootController(for:)`'s `.rule` case silently substitutes the Adventure root when `ruleRoot` is nil
- **Location:** `Modules/GameRPG/Root/GameRootModel.swift:811-838`, specifically `:828` (`ruleRoot?.rootController ?? adventureRoot.rootController`); sole caller `Modules/GameRPG/Search/SearchResultRow.swift:21`; guard site `Modules/GameRPG/Search/SearchGlobalController.swift:62-64` (`.rule` results are only ever added `if let ruleRoot`).
- **What:** traced every caller of this method repo-wide — `SearchResultRow.swift:21` is the only call site. In production, `Modules/RolePlayGameKit/Model/AppModel.swift:189,216` always constructs and passes a real, non-optional `ruleRoot` on every platform (unlike `generatorRoot`, which genuinely is conditionally nil), so `root.ruleRoot` is never nil in the shipping app. The only place it's actually nil is `GameRoot.previewFixture()`, and no current preview/fixture constructs a `.rule` result against that root.
- **Why:** confirmed unreachable today, but the silent `??` fallback means a future preview, test, or platform variant that legitimately omits Rule support would render Adventure content mislabeled as a Rule search result instead of failing loudly.
- **Action:** replace the silent fallback with an explicit assertion or a `nil`-safe path that fails visibly in debug builds.
- **Severity:** Low.

---

## 6. Security

### 6.1 Raw search text logged via `os.Logger` without an explicit privacy annotation
- **Location:** `Modules/CoreRPG/Controllable/FolderListControllable.swift:76,83,91` (`Logger.folderListControllable.info(...)`, three call sites per search).
- **What:** each line interpolates the raw `searchText` (and `source`) with no explicit `privacy:` qualifier, while this same codebase explicitly marks `privacy: .public` on error descriptions elsewhere (`Modules/CoreRPG/Controllable/ItemControllable.swift:379,392,403`) — showing privacy-annotation awareness exists in the codebase but wasn't applied here.
- **Why:** `os.Logger` string interpolations of non-scalar types default to redacted in *collected* system logs (Console/sysdiagnose) unless marked `.public`, so this is not a proven PII leak via Apple's log collection — but the raw query (which can contain sensitive campaign/character notes) is fully visible in Xcode's live console during any debugging or TestFlight session, and three duplicate log lines per search add noise.
- **Action:** add an explicit `privacy: .private` annotation for clarity of intent, and consider collapsing the three log lines per search into one.
- **Severity:** Low.

_No hardcoded secrets, API keys, tokens, or embedded URLs were found in any of the 44 scoped files._

---

## 7. Performance

### 7.1 Deep/wide folder and collection trees are walked fully synchronously on `@MainActor`, with no yield point or size guard
- **Location:** `Modules/CoreRPG/Controllable/FolderListControllable.swift:399-443` (`appendToFlat`) and `:499-528` (`flattenCachedChildren`/`loadChildrenViaSearch`); `Modules/CoreRPG/Controllable/SearchControllable.swift:145-213,702-762` (folder-node builders).
- **What:** every node visit does dictionary lookups, `localizedStandardContains` calls, and recursive children construction in a tight loop with no `Task.yield()` and no depth/count cap — whether triggered by the 300ms typing-debounce search or a single, fully synchronous chevron toggle (`toggleFolder`, per its own doc comment at line 538).
- **Why:** for a GM with a large, deeply nested Map/Table/Character folder tree, this can consume a long, unyielding main-thread stretch on every settled keystroke and every fold/unfold, causing dropped frames or a visible hitch. Plausible from reading the code; not measured/profiled in this review.
- **Action:** consider inserting periodic `Task.yield()` in the async recursive builders, and/or capping how much of very large trees is eagerly expanded; profile with Instruments on a large fixture before over-engineering.
- **Severity:** Medium.

---

## 8. SwiftUI / UI

### 8.1 `SearchListView`'s `.searchable` prompt bypasses the module's localization bundle
- **Location:** `Modules/GameRPG/Search/SearchListView.swift:46` (`.searchable(text: $model.searchText, placement: .sidebar, prompt: "Search items and entries")`).
- **What:** the `prompt:` argument is a bare string literal, which SwiftUI resolves as an implicit `LocalizedStringKey` looked up against `Bundle.main` — not `GameRPG`'s own resource bundle — while every other user-facing string in this same file (and the project's CLAUDE.md convention) uses `Text("...", bundle: .module)`.
- **Why:** in any non-English locale, this prompt will likely fall back to the raw English string instead of resolving GameRPG's localized copy, since `Bundle.main`'s string catalog doesn't contain GameRPG's module-scoped translations.
- **Action:** wrap it as `Text("Search items and entries", bundle: .module)` (or an equivalent `LocalizedStringResource` with an explicit bundle), matching the `.searchable(prompt: Text)` overload.
- **Severity:** Medium.

### 8.2 `.textContentTypeAll(.name)` applied to a generic item/entry filter field
- **Location:** `Modules/CoreRPG/Inspector/LinkItemFilterFieldView.swift:21`; wrapper definition `Modules/CoreRPG/Platform/TextFieldAll.swift:12-14,54-79`.
- **What:** the inspector/link-picker's search box declares `UITextContentType.name` via the app's cross-platform `TextContentTypeAll` wrapper. This is the *only* call site of `.textContentTypeAll` in the entire repository (confirmed by repo-wide grep) — no other search or filter field anywhere else in the app sets a content type at all.
- **Why:** `.textContentType(.name)` tells iOS this field collects a person's name, which can surface Contacts-app autofill/QuickType suggestions on what is actually a free-text campaign/character/item search box — inconsistent with the rest of the app and almost certainly a copy-paste artifact from a real name-entry field.
- **Action:** remove `.textContentTypeAll(.name)` from this filter field.
- **Severity:** Medium.

### 8.3 Inconsistent `Text(String)` vs. `Text(verbatim:)` for the same class of dynamic, non-localizable content
- **Location:** `Modules/GameRPG/Search/SearchResultRow.swift:29` (`Text(result.itemName)`) and `:46` (`Text(matchedContent)`), contrasted with the same file's own correct usage at `:32` (`Text(verbatim: "·")`) and `:41` (`Text(verbatim: "\(entryName): \(matchedContent)")`).
- **What:** two of four dynamic/user-generated string displays in this row skip `Text(verbatim:)`, triggering a needless (harmless but wasteful) String Catalog lookup for user-authored content, and are inconsistent with the other two call sites one line away in the same view.
- **Why:** minor, but signals the pattern wasn't applied deliberately — the next similar row view in this codebase is as likely to copy the inconsistent version as the correct one.
- **Action:** switch both to `Text(verbatim:)` for consistency with the rest of the file.
- **Severity:** Low.

### 8.4 `LinkItemRootView` seeds `@State` from an init parameter — compensated, but worth tightening
- **Location:** `Modules/CoreRPG/Inspector/LinkItemRootView.swift:13-22,34-42`.
- **What:** `@State private var parentModel` is seeded from `itemSelectionModel.onlyChildrenFrom` inside `init` — the general SwiftUI anti-pattern where `@State`'s initial value silently ignores later changes to the source parameter — but a `.task(id: itemSelectionModel.onlyChildrenFrom)` immediately below re-derives `parentModel` from the same source on every subsequent id change.
- **Why:** `.task(id:)` is the correct idiom and fully compensates for updates after the first render; the only residual gap is a single frame at initial appearance before the task's body executes, which recomputes the identical value `init` already set — no observable staleness in practice.
- **Action:** low priority; if fully eliminating the anti-pattern shape is desired, drive `parentModel` as a plain computed property instead of `@State`, since the child `LinkItemListView` already treats it as pass-through data.
- **Severity:** Low.

### 8.5 Cosmetic: dangling trailing comma and blank line
- **Location:** `Modules/GameRPG/Search/SearchRootView.swift:12-17` — `.modifier(CompactNavigationModifier(root: root, navigator: navigator, model: root.searchController.model,\n\n))`.
- **What:** a trailing comma followed by a blank line before the closing parenthesis.
- **Why:** purely cosmetic, but reads as a leftover from a removed parameter rather than an intentional edit.
- **Action:** remove the trailing comma and blank line.
- **Severity:** Low.

---

## 9. Dead code / duplication / refactor

### 9.1 The entire synchronous "mirror" search implementation has zero production callers
- **Location:** `Modules/CoreRPG/Controllable/SearchControllable.swift:612-763` — `syncListSearchResults`, `syncInspectorSearchResults`, `syncListModeResults`, `syncFolderModeResults`, `syncBuildFolderNode` (~142 lines); `Modules/CharacterRPG/Controller/SearchController.swift` — all eight `sync*` overrides paired with their async twins: `syncFocusedCharacterInspector` (`:405-458`) / `focusedCharacterInspector` (`:464-519`), `syncCharacterInspectorResult` (`:627-635`) / `characterInspectorResult` (`:673-681`), `syncCollectValueEntries` (`:640-669`) / `collectValueEntries` (`:686-717`), `syncFolderModeCharacterResults` (`:248-282`) / `folderModeCharacterResults` (`:155-191`), `syncBuildCharacterFolderNode` (`:285-313`) / `buildCharacterFolderNode` (`:194-224`), `syncListModeCharacterResults` (`:230-245`) / `listModeCharacterResults` (`:136-152`), `syncInspectorSearchResults(listMode:...)` (`:322-360`) / `inspectorSearchResults(listMode:...)` (`:362-400`), `syncInspectorSearchResults(parentId:)` (`:544-574`) / `inspectorSearchResults(parentId:)` (`:587-618`) — roughly 243 more lines.
- **What:** a repo-wide grep of every non-test call site of `syncListSearchResults(` and `syncInspectorSearchResults(` found zero production callers. `SearchListController`/`SearchLinkController` — the two concrete `SearchRootControllable` conformers actually wired into every module's `FolderListController` — call only the async `listSearchResults`/`inspectorSearchResults`/`scopedResults`. The only sync method genuinely used in production is the much smaller, unrelated `syncExpandResults` (`FolderListControllable.swift:519`). The only callers of the code cited above are `Tests/CharacterRPGTests/SearchControllerTests.swift` and CharacterRPG's own internal self-dispatch, itself only reachable through the same dead entry point.
- **Why:** ~385 lines across two files exist solely to be unit-tested, not to serve the app. This is the highest-value cleanup target in the whole subsystem: unlike the async paths (load-bearing), these can be deleted with zero production risk, and doing so would shrink `SearchControllable.swift` from 763 to ~611 lines and CharacterRPG's `SearchController.swift` from 718 to ~270-320 lines — resolving §9.5's oversized-file concern for both without any structural split. Within `SearchControllable.swift`, `listModeResults`/`syncListModeResults` (`:76-90` / `:648-662`) are in fact **100% byte-identical** — `listModeResults` never awaited anything to begin with, so its "sync" twin required zero changes to produce, i.e. this pair is pure copy-paste, not an async→sync port.
- **Action:** confirm with the team whether these sync entry points were meant for a not-yet-wired synchronous caller (e.g. a future widget path); if not, delete them and their tests, keeping only `syncExpandResults`.
- **Severity:** High.

### 9.2 `SearchRootControllable.results(text:focusId:)` (2-param) and its sole helper have zero production callers
- **Location:** protocol declaration `Modules/CoreRPG/Controllable/SearchRootControllable.swift:23` (its own doc comment already flags "rarely used now that `syncExpandResults` handles most cases"); implementations `Modules/CoreRPG/Controllable/SearchListController.swift:29-36,118-135`; sole supporting helper `inspectorEntryResults` at `Modules/CoreRPG/Controllable/SearchControllable.swift:507-531`.
- **What:** a repo-wide grep of `.results(text:` with a `focusId:` argument found call sites only in `Tests/TableRPGTests/InspectorEntryOrderTests.swift:125` and `Tests/PdfRPGTests/InspectorToggleBugFixTests.swift:71,90,106` — the production feature this method served (`loadChildrenViaSearch`) fully migrated to the sync `syncExpandResults` (`FolderListControllable.swift:519`), leaving the async 2-param overload orphaned as a protocol requirement every future conformer must still implement.
- **Why:** dead protocol surface area, purely to satisfy tests that could call the sync replacement instead.
- **Action:** verify with the team, then either delete `results(text:focusId:)` and `inspectorEntryResults` from the protocol and both conformers, or repoint the tests at `syncExpandResults` and remove the async overload.
- **Severity:** Medium.

### 9.3 `ListRootView` and `LinkItemListView` independently duplicate `listModel`/`shouldShowNoResults`
- **Location:** `Modules/CoreRPG/LGViews/ListRootView.swift:148-153,161-163`; `Modules/CoreRPG/Inspector/LinkItemListView.swift:140-145,152-154`.
- **What:** both compute `parentModel != nil ? detailListModel : listModel` and `searchModel.searchReturnedNoResults` verbatim, and `LinkItemListView`'s doc comment explicitly says its version works "exactly as `ListRootView` does" — an acknowledged, uncorrected copy.
- **Why:** a future change to detail-scoping semantics (e.g. adding a third scope) must be applied twice; the comment already documents this file is intentionally mirroring the other's behavior instead of sharing it.
- **Action:** hoist both as default `FolderListControllable` extension members (e.g. a `scopedListModel(parentModel:)` function and a parameterless `shouldShowNoResults` property), since both views already hold a `FolderListControllable` reference.
- **Severity:** Medium.

### 9.4 Two unrelated `SearchModel` classes share the same unqualified name
- **Location:** `Modules/CoreRPG/Model/SearchModel.swift:5-96` (`@Observable public final class SearchModel: Sendable`, driving `FolderListControllable`'s list/inspector search — `tagController`, `searchToken`, `selectedTokens`, `filterId`, auto-cancelling `currentTask`/`tagTask`); `Modules/GameRPG/Search/SearchModel.swift:6-40` (`@Observable final class SearchModel`, no `Sendable`, driving the cross-module game search — `results: [NetworkModules: [SearchResult]]`, `isSearching`, `playerMode`).
- **What:** `GameRPG` imports `CoreRPG` (making `CoreRPG.SearchModel` visible) while separately declaring its own, unrelated `SearchModel` — Swift's local-module-wins shadowing means every bare `SearchModel` reference inside `SearchRootView.swift`, `SearchGlobalController.swift`, `SearchListView.swift`, and `SearchDetailView.swift` silently resolves to the small local type. No file anywhere qualifies either type explicitly.
- **Why:** a maintainer more familiar with the widely-used `CoreRPG.SearchModel` (used throughout `ListRootView`/`LinkItem*`) could easily assume properties that don't exist on GameRPG's type (`filterId`, `searchToken`, the auto-cancelling `currentTask`), and it actively confuses anyone grepping the codebase for "the" `SearchModel`.
- **Action:** rename GameRPG's type to something scoped to its actual purpose, e.g. `GlobalSearchModel`, matching the sibling `SearchGlobalController` name already used in the same file.
- **Severity:** Medium.

### 9.5 Three oversized files, with clean existing `MARK` seams to split along
- **Location:** `Modules/CoreRPG/Controllable/SearchControllable.swift` (763 lines: Global Search `18-60`, List Search `62-255`, Inspector Search `257-532`, relevance/sorting `534-611`, Synchronous Search `612-763`); `Modules/CoreRPG/Controllable/FolderListControllable.swift` (645 lines: search execution `~35-330`, List change `280-330`, Search & Filter `332-529`, Folder Logic `531-645`); `Modules/CharacterRPG/Controller/SearchController.swift` (718 lines: Global search `14-109`, List search `113-315`, Inspector search `317-718`).
- **What:** all three already have `MARK` boundaries that line up with natural extension-file splits.
- **Why:** size makes the §9.1 duplication harder to spot at a glance and slows code review/navigation.
- **Action:** resolve §9.1 first — it shrinks `SearchControllable.swift` to ~611 lines and CharacterRPG's file to ~270-320 lines, likely removing the need to split either. If `FolderListControllable.swift` still feels large afterward, split its `Folder Logic` extension (`531-645`) into its own file.
- **Severity:** Medium.

### 9.6 Confirmed-dead properties and a legacy helper
- **Location:** `Modules/CoreRPG/Model/SearchModel.swift:110` (`SearchTags.allCategory` — declaration only, zero uses); `Modules/CoreRPG/Model/SearchModel.swift:20` (`searchToken: ItemListCategory` — set via `init`/`newSearchModel` but never read by any conditional anywhere in the repo); `Modules/CharacterRPG/Controller/SearchController.swift:620-623` (`inspectorSearchResults(searchText:characterId:)`, self-labeled "legacy helper", zero callers).
- **What:** each verified via full-repo grep with only the declaration/assignment sites matching.
- **Why:** inert code that adds surface area without behavior; `searchToken` in particular is easy to mistake for a live filter when reading `SearchModel`.
- **Action:** delete `SearchTags.allCategory` and the CharacterRPG legacy helper outright; either wire `searchToken` into real filtering logic or remove it along with its constructor parameter.
- **Severity:** Low.

### 9.7 Ten of twelve per-module `SearchController.swift` files are near-identical ~14-line boilerplate
- **Location:** `AdventureRPG`, `AudioRPG`, `DiceRPG`, `GeneratorRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG` — all textually identical modulo whitespace (`struct SearchController: Sendable { let itemController: ItemController }` + `extension SearchController: SearchControllable { var itemControllable: any ItemControllable { itemController } }`); `RuleRPG` is semantically identical in 12 more compact lines. `CharacterRPG` (718 lines) is the sole real outlier with genuine per-module logic.
- **What:** unlike `FolderListController` (which has legitimate per-module route/destination differences, confirmed already maximally hoisted per its own inline comments referencing a prior audit), these 10-11 files have zero per-module-specific logic.
- **Why:** a protocol-extension default can't supply a *stored* property of a per-module concrete type, but a **generic** wrapper can, since nothing here blocks genericizing over `ItemController`: `struct GenericSearchController<IC: ItemControllable & Sendable>: SearchControllable, Sendable { let itemController: IC; var itemControllable: any ItemControllable { itemController } }`, with each module reduced to `typealias SearchController = GenericSearchController<ItemController>`.
- **Action:** introduce the generic wrapper in `CoreRPG`; replace the 10-11 boilerplate files with one-line typealiases; leave `CharacterRPG` untouched.
- **Severity:** Low.

### 9.8 `SearchDetailView`'s per-module switch repeats an identical `ViewerConfiguration` construction 11 times
- **Location:** `Modules/GameRPG/Search/SearchDetailView.swift:28-41`.
- **What:** every case of the 11-way `switch selection.module` constructs `ViewerConfiguration(closeButton: false, addToolbar: true, isGame: false)` verbatim, differing only in which module's `viewController`/`root` is used.
- **Why:** a future change to the detail-view configuration (e.g. adding a toolbar item) requires editing 11 near-identical lines instead of one shared constant.
- **Action:** hoist `ViewerConfiguration(closeButton: false, addToolbar: true, isGame: false)` into a single `static let` and reference it from every case.
- **Severity:** Low.

### 9.9 Stray commented-out modifier line
- **Location:** `Modules/CoreRPG/ItemDetail/ItemEditorForegroundView.swift:51` — `//.environment(folderListController.listDisplayModel)`, directly beneath a `ListRootView(...)` call.
- **What:** a single commented-out `.environment(...)` modifier, left in place with no explanatory comment.
- **Why:** unclear whether this was deliberately disabled (regression risk if deleted blind) or simply forgotten; either way it's noise for the next reader.
- **Action:** either delete it, or replace with a one-line comment explaining why it's disabled if that's intentional.
- **Severity:** Low.

_Confirmed clean, no action needed: no `#if false` blocks, no `TODO`/`FIXME`/`HACK`/`XXX` markers, and no bare (non-`Logger`) `print()` calls anywhere in the 44 scoped files. All 12 modules' `FolderListController.swift` were confirmed to already share an identical 5-property shape, varying only in the per-module `Route` enum cases their 4 destination methods return — legitimate, unavoidable wiring, not duplication; no further hoisting is possible there._

---

## 10. Cross-cutting recommendations

1. **Delete the dead sync-mirror code before doing anything else in this subsystem.** §9.1 and §9.2 together account for roughly 420 of the ~1,480 lines in `SearchControllable.swift` + CharacterRPG's `SearchController.swift` — over a quarter of the two largest files in scope. Removing it first would shrink §9.5's oversized-file list from three files to effectively one, and would make the remaining, load-bearing async logic significantly easier to review for the filtering-correctness issues in §5.1/§5.2.
2. **Standardize on `localizedStandardContains` everywhere text is matched against user input**, including relevance scoring (§5.1, §5.2) — the shared `itemMatchesFilter` helper already gets this right; the outliers are all places that grew their own local comparison instead of reusing it.
3. **Give every fire-and-forget `Task` in this subsystem the same cancellable/coalescing shape `SearchModel.currentTask` already established** (§3.1, §3.2, §3.4, §3.5) — four independent findings share one root cause: this codebase has a correct, established pattern (`didSet { oldValue?.cancel() }` + a stored task handle) that several newer call sites didn't reuse.
4. **Qualify or rename type names that collide across modules** (§9.4) — `SearchModel` is the only collision found in this scope, but it's worth a quick repo-wide grep for other same-name types across module boundaries while this is fresh.

---

## 11. What was NOT audited

- **The rest of the codebase.** This was a scoped audit of the Search feature only, per the request — not a full-repo pass.
- **Every per-module `SearchController.swift` override in full depth.** `CharacterRPG`'s (the one real outlier) was read completely; the 11 others were confirmed as boilerplate/near-boilerplate by direct comparison but not each individually re-derived line-by-line.
- **Deep dependency files**, e.g. `FolderListModel.swift`, `ItemDataModel.swift`, `EditControllable.swift`, `EntryDataAccessable.swift`, and the `*EntryModel.swift` files, were read only far enough to verify specific claims above (cited inline) — not audited as their own subsystems.
- **Runtime/empirical verification.** All findings come from static reading, not from running the app or a debugger; the two race-condition findings (§3.1, §3.2) and the performance finding (§7.1) are reasoned from code structure, not reproduced with Instruments or manual double-tap testing.
- **Compiler warnings as ground truth for §3/§4.** The full-scheme build was fully cached (0 warnings, nothing recompiled in scope); only a scoped `CharacterRPG` build actually compiled scoped code, and it was clean. A clean/from-scratch build touching every scoped file was not run within this audit's time budget.
- **Test coverage assessment.** Existing tests for this subsystem (`Tests/*RPGTests/SearchControllerTests.swift`, `Tests/GameRPGTests/SearchModelTests.swift`, etc.) were used only to establish call-site evidence for §9.1/§9.2's dead-code claims, not reviewed for their own quality or coverage gaps.
- **Localization wording correctness** beyond the structural bundle-scoping issue in §8.1.
- **Algorithmic correctness of the relevance-scoring weights** in `calculateRelevance` (§5.2) beyond the locale-comparison defect — whether 100/50/25/80/40/20/10/15 are the "right" weights for search ranking is a product decision, not audited.

---

## 12. Verification

No finding in this report was rated Critical — the highest severity found is High, and both High-rated Bugs/Concurrency findings were personally spot-verified by opening the cited lines (per this skill's requirement to verify severity claims before propagating them), not merely taken from agent output.

- **§3.1** — open `Modules/CoreRPG/Controllable/FolderListControllable.swift`, lines 283-320. Confirm `Task { }` has no stored handle and no guard; then open `Modules/CoreRPG/LGViewModifiers/ToolbarItemListViewModifier.swift`, lines 165-169, and confirm the triggering `Button` has no `.disabled()` tied to an in-flight state.
- **§3.2** — open `Modules/CoreRPG/Controllable/FolderListControllable.swift`, lines 263-267 (`resetDetail`) and 129-150 (`performDetailSearch`). Confirm the `Task(name: "Initial Detail Search")` is not assigned to any stored/cancellable property, and that `performDetailSearch`'s final `guard !Task.isCancelled` (line 147) is the only staleness check — nothing compares the write-back against the detail model's *current* `parentModel.id`.
- **§5.3** — open `Modules/CoreRPG/Controllable/EditControllable.swift`, lines 223-234. Confirm the only guard is `itemId != parentId`; no ancestor-chain walk precedes the link.
- **§9.1** — open `Modules/CoreRPG/Controllable/SearchControllable.swift`, lines 76-90 and 648-662, side by side. Confirm `listModeResults` and `syncListModeResults` are byte-identical apart from the function name. Then `grep -rn "syncListSearchResults(\|syncInspectorSearchResults(" --include="*.swift"` from the repo root and confirm every hit outside `SearchControllable.swift`/`SearchController.swift` themselves is under `Tests/`.
- **§5.1** — open `Modules/CharacterRPG/Controller/SearchController.swift`, lines 47-48, and compare against `Modules/CoreRPG/Controllable/SearchControllable.swift`, lines 219-229 (`itemMatchesFilter`) — confirm the former uses `localizedCaseInsensitiveContains` where the latter (the shared, correct helper) uses `localizedStandardContains`.

If any finding doesn't reproduce when you visit the line, flag the specific reference and it'll get re-investigated.
