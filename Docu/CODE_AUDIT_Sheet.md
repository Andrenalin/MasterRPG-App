# MasterRPG — Sheet Root Code Audit

**Scope:** `Modules/CoreRPG/Sheet/SheetRootView.swift` and `Modules/CoreRPG/Sheet/SheetRootEditorView.swift`, plus the controllers and models they own or render through: `SheetRootModel.swift`, `SheetModel.swift`, `SheetView.swift`, `SheetEntryView.swift`, and the shared helpers those files call directly (`SheetEditorModel.swift`, `LinkHighlightTextModel.swift`, `UnequalAssignment.swift`, `DebouncerModel.swift`, `AppFocusModel.swift`). This is a deliberately narrow, deep pass — not a repo-wide audit. See §11 for the explicit boundary and §10 of `Docu/CODE_AUDIT_8.md` for the most recent full-codebase pass.

**Ground truth:** A clean `xcodebuild` of the `MasterRPG` scheme via the Xcode MCP (`BuildProject`) succeeded with **zero warnings** workspace-wide, confirmed via `XcodeListNavigatorIssues` at `warning` severity both before and after the build. Every concurrency/API-modernity claim below was verified by reading the cited lines, not inferred from this alone.

---

## 1. Executive summary

1. **[High] Drag-to-reorder within a sheet computes the wrong insertion index for half of all reorders** — §5.1 — `Modules/CoreRPG/Sheet/SheetRootModel.swift:849`
2. **[High] `SheetRootModel` is permanently leaked on ordinary navigation via a self-contained retain cycle through its cached link-text models** — §5.2 — `Modules/CoreRPG/Sheet/SheetRootModel.swift:323`
3. **[Medium] Sheet name/description search uses `localizedCaseInsensitiveContains` instead of the project-mandated `localizedStandardContains`** — §4.1 — `Modules/CoreRPG/Sheet/SheetModel.swift:105`, `Modules/CoreRPG/Sheet/SheetRootModel.swift:318`
4. **[Medium] `SheetModel.reset(with:)` is dead code — zero call sites anywhere in the repo** — §9.1 — `Modules/CoreRPG/Sheet/SheetModel.swift:116-147`
5. **[Medium] Every entry whose name/description gets reconciled re-triggers a full parent reconcile of its own accord** — §7.1 — `Modules/CoreRPG/Sheet/SheetEntryView.swift:90-95`
6. **[Low] `delayedTask` result still discarded in two `SheetRootModel` call sites — unfixed since round 8's §9.15** — §9.2 — `Modules/CoreRPG/Sheet/SheetRootModel.swift:946,965`
7. **[Low] Duplicate focus/scroll `.onChange` block between `SheetView` and `SheetEntryView` — unfixed since round 8's §9.12** — §9.3 — `Modules/CoreRPG/Sheet/SheetView.swift:99-108`
8. **[Low] Edit-type picker button has no minimum tap target, unlike its sibling AI button in the same file** — §8.2 — `Modules/CoreRPG/Sheet/SheetEntryView.swift:429-447`
9. **[Low] Hard-coded `.padding(.leading, 2)` on recursive sheet nesting** — §8.1 — `Modules/CoreRPG/Sheet/SheetView.swift:222`

---

## 2. Quick wins

- **§5.2** — Capture `self` weakly in the `toggler` closure instead of strongly. One-line fix, breaks a leak that fires on essentially every sheet dismissal. *(High-impact but still a one-line change; see §5.2 for the full mechanism.)*
- **§9.1** — Delete `SheetModel.reset(with:)` (`SheetModel.swift:116-147`, 32 lines) — confirmed zero callers repo-wide.
- **§9.2** — Store the `Task` returned by both `delayedTask(.milliseconds(100)) { ... }` calls in a `SheetRootModel` property and cancel the previous one before assigning a new one, matching every other `delayedTask` call site in the repo.
- **§8.1** — Replace `.padding(.leading, 2)` (`SheetView.swift:222`) with a system spacing token or remove it; CLAUDE.md explicitly asks to avoid hard-coded padding values.
- **§3.1** — Add `Sendable` to `SheetEditorModel`'s class declaration, matching every sibling `@MainActor @Observable` class in this file set (`SheetModel`, `SheetRootModel`, `AppFocusModel`, `DebouncerModel`, `ItemRootController`).
- **§5.1** — One-line fix (`SheetRootModel.swift:849`), but budget time for manual drag-and-drop QA on-device before shipping — see §5.1 for why the current ternary is a no-op.

---

## 3. Concurrency

The full file set is `@MainActor @Observable` throughout (`SheetRootModel`, `SheetModel`, `SheetEditorModel`, `AppFocusModel`, `ItemRootController`, `DebouncerModel`), matches CLAUDE.md's mandated pattern, and produced zero compiler warnings in a clean build. No `DispatchQueue`, no `Task.sleep(nanoseconds:)`, no raw `MainActor.assumeIsolated`, and no force-unwraps were found in any of the seven files read in full. `SheetRootView`'s deferred `Task { @MainActor in focusedEntryId = target }` (line 90-92) is redundant isolation-wise (the view body already runs on `@MainActor`) but is deliberately used to defer by one runloop tick, per its own comment — not a bug.

### 3.1 `SheetEditorModel` is the one class in this file set without an explicit `Sendable` conformance
- **Location:** `Modules/CoreRPG/Sheet/SheetEditorModel.swift:6`
- **What:** `@MainActor @Observable public final class SheetEditorModel {` — no `Sendable`. Every sibling class touched by this audit (`SheetModel.swift:6`, `SheetRootModel.swift:46`, `AppFocusModel.swift:10`, `DebouncerModel.swift:6`, `ItemRootControllable.swift:44`) declares `: Sendable` alongside `@MainActor @Observable`.
- **Why:** `SheetRootModel.editorModel` is a `public let` of this type, and `SheetRootModel` itself is `Sendable` — currently fine only because both are `@MainActor`-isolated, but any future generic code requiring `T: Sendable` on `SheetEditorModel` specifically (e.g. crossing into a `Task` or an `async` boundary the way `SheetRootModel.addNewGroup`/`convertEntryToGroup` already do) will fail to compile without this being fixed first.
- **Action:** Add `Sendable` to the class declaration.
- **Severity:** Low

---

## 4. API modernity

### 4.1 Sheet search uses `localizedCaseInsensitiveContains` instead of the required `localizedStandardContains`
- **Location:** `Modules/CoreRPG/Sheet/SheetModel.swift:105` (`filter(searchText:shouldRestoreState:)`); `Modules/CoreRPG/Sheet/SheetRootModel.swift:318` (`description(for:)`)
- **What:** Both call sites filter user-typed search text against entry name/description with `.localizedCaseInsensitiveContains(searchText)`. CLAUDE.md: "Filtering text based on user-input must be done using `localizedStandardContains()` as opposed to `contains()`."
- **Why:** `localizedCaseInsensitiveContains` only case-folds; `localizedStandardContains` additionally normalizes diacritics and matches the search behavior users expect from Spotlight-style filtering elsewhere in the app (e.g. accented characters in a monster or NPC name won't match an unaccented search term today).
- **Action:** Replace both call sites with `.localizedStandardContains(searchText)`.
- **Severity:** Medium

---

## 5. Bugs / logic errors

### 5.1 Drag-to-reorder within a sheet computes the wrong insertion index
- **Location:** `Modules/CoreRPG/Sheet/SheetRootModel.swift:839-857`, specifically line 849
- **What:** `reorderEntry(from:to:in:)` computes `let insertIndex = sourceIndex < targetIndex ? targetIndex : targetIndex` — **both branches of the ternary return the same value**, so the `sourceIndex < targetIndex` condition has no effect at all.
- **Why:** This is reachable from `SheetView`'s same-parent drag reorder (`SheetRootModel.swift:900-903`, called from `handleDrop`). Removing the element at `sourceIndex` before inserting shifts every later index down by one — the standard fix is `targetIndex - 1` when `sourceIndex < targetIndex`, and `targetIndex` unchanged otherwise. Tracing both directions confirms the asymmetry: dragging entry A (index 0) onto entry C (index 2) in `[A,B,C,D]` lands A **after** C → `[B,C,A,D]`; dragging D (index 3) onto B (index 1) lands D **before** B → `[A,D,B,C]`. The same "drop onto this entry" gesture produces opposite before/after placement depending purely on drag direction, and the resulting (wrong) order is what gets persisted via `editable.move(...)` on the next line — the incorrect order is saved, not just transiently displayed.
- **Action:** Subtract one from the insertion index specifically for the `sourceIndex < targetIndex` branch, to compensate for the removal shifting every later index down by one; leave the other branch unchanged.
- **Severity:** High

### 5.2 `SheetRootModel` is permanently leaked on ordinary navigation via a retain cycle through its own link-text cache
- **Location:** `Modules/CoreRPG/Sheet/SheetRootModel.swift:321-328`, specifically the `toggler` closure at line 323; cycle partner at `Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift:8-21`
- **What:** `linkTextModel(for:text:shareResults:)` creates a `LinkHighlightTextModel` with `toggler: { self.toggle(id: id, itemId: $0, module: $1, linkNumber: $2) }` — `self` (the `SheetRootModel`) captured strongly, no `[weak self]`. `LinkHighlightTextModel` stores this in a `let toggler: (...) async -> Void)?` stored property (`LinkHighlightTextModel.swift:21`). The new model is then stored in `self.linkTextModel[id]` (`SheetRootModel.swift:326`), a dictionary property *on the same `SheetRootModel`*. This closes a two-object cycle: `SheetRootModel → linkTextModel[id] → LinkHighlightTextModel.toggler → SheetRootModel`, entirely self-contained — every SwiftUI row that ever renders a name or description (`SheetView.nameRow`/`secondaryRow`, `SheetEntryMainRowView`, `SheetEntryContentRowView`, `SheetEntryMainRowView`'s `.audio` case) populates this dictionary, so the cycle forms on the very first render of any sheet.
- **Why:** `reset(itemId:)` (`SheetRootModel.swift:242`, `linkTextModel = [:]`) does break the cycle when a `SheetRootModel` instance is *reused* for a different item on the same screen (the pattern `SheetRootEditorView`'s own header comment describes) — clearing the dictionary drops `SheetRootModel`'s only strong reference to each old `LinkHighlightTextModel`, which then deinits and releases its own strong hold back on `SheetRootModel`. But `reset(itemId:)` is only called on an item switch *within* an already-live screen. When the screen itself is dismissed instead (closing the editor, navigating to a different module, dismissing the import-review sheet built by the fourth initializer at `SheetRootModel.swift:75-129`), nothing calls `reset` first — the view's `@State`/owning reference to `SheetRootModel` is released, but the internal `SheetRootModel ↔ LinkHighlightTextModel` cycle has no external participant, so ARC never reclaims either side. The entire materialized `SheetModel` tree that `SheetRootModel.sheetModel` still points to (every entry, every inline sub-item) is kept alive transitively along with it. This is not an edge case — it is the ordinary "leave this screen" path, repeated every time a sheet is opened and closed for the rest of the process's lifetime, on iPad/visionOS sessions that routinely keep GM sessions open for hours.
- **Action:** Capture `self` weakly in the `toggler` closure instead of strongly, matching the established convention elsewhere in `CoreRPG` for exactly this shape of stored closure (e.g. `NavigationSend.swift:113`, `PersistentHistoryTrackerManager.swift:163`).
- **Severity:** High

---

## 6. Security

No findings. The audited files contain no network calls, no credential handling, no raw SQL/URL construction from unsanitized input, and no file-system access beyond what's delegated to controllers outside this scope.

---

## 7. Performance

### 7.1 Every entry whose name/description gets reconciled re-triggers a full parent reconcile of its own accord
- **Location:** `Modules/CoreRPG/Sheet/SheetEntryView.swift:90-95`; `Modules/CoreRPG/Sheet/SheetRootModel.swift:985-996` (`updateParent(_:)`)
- **What:** Every `SheetEntryView` attaches `.onChange(of: entryModel.name) { rootModel.updateParent(parentModel) }` and the same for `.description`. `updateParent(_:)` re-reconciles the *entire* parent subtree via `sheetControllable.update(...)`, not just the one changed entry.
- **Why:** A single external reconcile that touches several sibling entries at once (e.g. a multi-entry sync from another device, or an import) mutates each entry's `.name`/`.description` in turn. Each mutation independently fires that entry's own `.onChange`, which calls `updateParent(parentModel)` again — so one incoming change with *n* affected entries under the same parent produces up to *n* redundant full-subtree reconciles instead of one. `unequalSet`/`<=>`-based reconcile logic in the per-module `SheetController.update()` implementations makes each of those extra passes a no-op past the first, so this is bounded and not a correctness bug — but it's `O(n)` reconcile work for what should be `O(1)`, on a path (external sync landing) that's already latency-sensitive during live play.
- **Action:** Consider debouncing `updateParent(parentModel)` calls triggered from this specific `.onChange` pair (e.g. coalescing same-runloop-tick calls for the same `parentModel`), or moving the reconcile trigger to the point where the *batch* of changes is applied rather than per-field.
- **Severity:** Medium

### 7.2 Search filtering runs a full, un-debounced tree pass on every keystroke
- **Location:** `Modules/CoreRPG/Sheet/SheetRootModel.swift:161-182` (`searchText` `didSet`), `:677-682` (`updateFilteredEntries`)
- **What:** `searchText`'s `didSet` calls `updateFilteredEntries()` synchronously on every character typed, which recursively calls `sheetModel.filter(searchText:)` over the whole tree and then iterates every cached `LinkHighlightTextModel` in `linkTextModel.values` (not just currently-visible ones) to call `.reset(highlightedText:)`.
- **Why:** No debounce exists on this path, unlike `DebouncerModel`/`delayedTask`, which this same file family already imports and uses elsewhere for exactly this kind of "settle after typing" case. For a large character sheet or table with many nested entries, this is a full-tree walk per keystroke.
- **Action:** Low-priority given round 8's dedicated SwiftUI pass over this same rework found no user-visible issue at typical sheet sizes — worth a debounce only if profiling on a large real sheet shows it matters.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 Hard-coded padding value on recursive sheet nesting
- **Location:** `Modules/CoreRPG/Sheet/SheetView.swift:219-225`, specifically `.padding(.leading, 2)` on line 222
- **What:** The recursive `SheetView` call for a sub-entry's nested entries hard-codes `2` points of leading padding per nesting level.
- **Why:** CLAUDE.md: "Avoid specifying hard-coded values for padding and stack spacing unless requested." Every other spacing value in this same file/file-family is either a system default or a named constant.
- **Action:** Replace with a system spacing token, or hoist to a named constant if `2` is deliberately chosen to be smaller than any system spacing value.
- **Severity:** Low

### 8.2 Edit-type picker button has no minimum tap target, unlike its sibling in the same file
- **Location:** `Modules/CoreRPG/Sheet/SheetEntryView.swift:429-447` (`SheetEntryEditTypeIndicatorView`, editor-mode branch); contrast with `Modules/CoreRPG/Sheet/SheetEntryView.swift:307-322` (`SheetEntryMainRowView`'s "Ask AI about this entry" button)
- **What:** The edit-type picker toggle (`Button { isPickerPresented = true } label: { ... }`) is sized only by `.imageScale(.small)` + `.padding(4)` around a small SF Symbol — no `.frame(minWidth:minHeight:)`. The AI-assist button 100 lines above it, in the same file, explicitly sets `.frame(minWidth: 44, minHeight: 44)` for exactly this reason.
- **Why:** Apple's Human Interface Guidelines recommend a 44×44pt minimum interactive tap target; this button is one of the few interactive controls in the row that doesn't meet it, inconsistent with its sibling in the same view.
- **Action:** Add `.frame(minWidth: 44, minHeight: 44)` to match `SheetEntryMainRowView`'s AI button.
- **Severity:** Low

*(A dedicated SwiftUI-expert pass over this same `CoreRPG/Sheet` rework in round 8 (`Docu/CODE_AUDIT_8.md` §8) found the surface "uniformly high quality" otherwise — correct `Equatable` leaf views, `accessibilityReduceMotion` gating on every animation sampled here, `ForEach` on stable model identity throughout. Both findings above are additions on top of that pass, not contradictions of it.)*

---

## 9. Dead code / duplication / refactor

### 9.1 `SheetModel.reset(with:)` is dead code
- **Location:** `Modules/CoreRPG/Sheet/SheetModel.swift:116-147`
- **What:** A 32-line method that reconciles one `SheetModel`'s scalar fields from another via the `<=>` conditional-assignment operator. Confirmed via repo-wide grep: zero call sites anywhere, including tests. Every real `SheetControllable.update(...)` implementation checked (`SimpleSheetController.swift`) reconciles fields directly with `unequalSet`/`<=>` inline instead of calling this method.
- **Why:** Dead, unreachable reconciliation logic; also internally inconsistent with itself if it were ever revived — line 131 (`entries = otherSheetModel.entries`) is a plain assignment while every sibling field on the same method uses the change-gated `<=>` operator, which would unconditionally re-trigger `@Observable` invalidation for `entries` even when unchanged.
- **Action:** Delete the method. If a future need for tree-reset-from-snapshot reappears, model it after the working per-module `update(...)` implementations instead, using `<=>` consistently.
- **Severity:** Medium

### 9.2 `delayedTask` result still discarded in two `SheetRootModel` call sites
- **Location:** `Modules/CoreRPG/Sheet/SheetRootModel.swift:946` (`moveEntry(_:in:into:)`), `:965` (`moveEntryOutOfGroup(_:in:parent:)`)
- **What:** Both discard the `Task` returned by `delayedTask(.milliseconds(100)) { [self] in updateParent(parentModel) }`. Carried over, unfixed, from `Docu/CODE_AUDIT_8.md` §9.15.
- **Why:** Every other `delayedTask` call site in the repo (`AppIntentContentInvalidator.swift`, `NavigationSend.swift`, `TimedMessageList.swift`) stores the returned task and cancels the previous one before starting a new one — `delayedTask`'s own doc comment states this is the caller's responsibility. Rapidly moving multiple entries between groups spawns multiple untracked, uncancelled delayed calls. Currently harmless because the deferred `updateParent(parentModel)` is idempotent, but it silently violates a pattern this codebase otherwise treats as a hard rule.
- **Action:** Store the returned `Task` in a `SheetRootModel` property (e.g. `pendingGroupMoveTask: Task<Void, Never>?`) and cancel the previous one before assigning a new one.
- **Severity:** Low

### 9.3 Duplicate focus/scroll `.onChange` block between `SheetView` and `SheetEntryView`
- **Location:** `Modules/CoreRPG/Sheet/SheetView.swift:99-108` vs `Modules/CoreRPG/Sheet/SheetEntryView.swift:67-75`
- **What:** Both attach a near-identical `.onChange(of: focusedEntryId.wrappedValue)` — guard the focused id matches this row, then call `rootModel.handleFocusActivation(entryModel:parent:)` — with matching doc comments citing the same rationale. Carried over, unfixed, from `Docu/CODE_AUDIT_8.md` §9.12 (both sites already carry a `See CODE_AUDIT §9.12` comment acknowledging this).
- **Why:** Two files now have to stay hand-synchronized for any future change to focus/scroll/selection sequencing.
- **Action:** As previously recommended: extract the shared guard-then-`handleFocusActivation` call into one small view-modifier or free function both call sites invoke, rather than repeating the `.onChange` body.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **The `[weak self]` convention that already exists elsewhere in `CoreRPG` (`NavigationSend.swift`, `PersistentHistoryTrackerManager.swift`, `ScenesManager.swift`) was not applied to §5.2's `toggler` closure.** Given how easy this class of bug is to introduce (a stored closure on a cached child object, capturing the parent that owns the cache), it's worth a quick repo-wide grep for other `LinkHighlightTextModel(... toggler: { self.` construction sites outside this audit's scope (e.g. `EntryDataEditable.swift:380-383` creates the same shape of model) to confirm they don't share the same mistake.
2. **`reset(itemId:)`'s doc comment explains it exists specifically to avoid a different re-render bug (tight `DetailEditorView` re-render loop) — it's worth documenting, next to it, that it *also* happens to be what currently prevents §5.2's leak from accumulating during same-screen item switching**, so a future refactor of that method doesn't accidentally drop the `linkTextModel = [:]` line without realizing it's load-bearing for more than one reason.
3. **§9.2 and §9.3 are both round-8 findings that survived a full audit cycle untouched.** Neither is high-severity individually, but a repo-wide sweep of previously-flagged Low-severity items across all nine `Docu/CODE_AUDIT_*.md` rounds may be worth a dedicated pass, since the pattern (flagged, acknowledged in a code comment, still not fixed) recurs.

---

## 11. What was NOT audited

- **The rest of `Modules/CoreRPG/Sheet/`** — `SheetEntryButtons.swift`, `SheetEntryEditButton`/`SheetEntryDeleteButton`/`SheetEntryTakeOverButton`/`SheetEntryAddButton`/`SheetEntryAddGroupButton`, `SheetContextMenuView.swift`, `GeneratedSheetEntryContextMenu.swift`, `SheetEntryConvertToGroupButton`/`View`, `InlineSheetSearchControl.swift`, `SheetSearchContext.swift`, `SheetEditorEnvironment.swift`, the whole `SheetEntryReview*`/`SheetReviewModels`/`ReviewSheetMemory` import-review family, `TableSheetView.swift`/`TableRootSheet.swift`, and `SheetBorderViewModifier.swift` were referenced from the audited files but not independently read line-by-line. They're candidates for a follow-up pass.
- **The eleven per-module `SheetControllable` implementations** (`Modules/{Adventure,Audio,Character,Dice,Generator,Map,Pdf,Photo,Rule,Space,Table,Weather}RPG/Controller/SheetController.swift`) — only `SimpleSheetController.swift` was spot-checked, to confirm `reset(with:)` (§9.1) really has no caller and to sanity-check the reconcile pattern referenced in §7.1/§9.1's rationale.
- **`ItemRootController`/`RootManager`'s full surface** — read only far enough to confirm `@MainActor @Observable ... Sendable` conformance; the ~20 other controllers it exposes (`editControllable`, `itemControllable`, `folderListControllable`, etc.) are out of scope.
- **`LinkHighlightTextModel`'s markdown-link parsing/rendering internals** (`components(for:...)`, `hightlight(...)`, bold/link-range scanning) — read in full to confirm the §5.2 retain-cycle mechanism, but its algorithmic correctness was not reviewed.
- **`InlineEditorView`, `LinkHighlightTextView`, `GameShareView`, `ShareValueResult`** — referenced from the audited files as call sites but not opened.
- **Test coverage** — not assessed. No test file for `SheetRootModel`/`SheetModel` reorder or link-cache-lifetime behavior was located during this pass; §5.1 and §5.2 in particular would benefit from a regression test once fixed.
- **Build settings, scheme configuration, and Xcode project structure** beyond confirming a clean warning-free build of the active `MasterRPG` scheme.
- **The wider, whole-repository concerns already tracked in `Docu/CODE_AUDIT_1.md` through `CODE_AUDIT_8.md`** (per-module controller genericization, Master/Player view duplication, oversized files, etc.) — this report only re-surfaces the two items from that history (§9.2, §9.3) that live inside this audit's specific scope and remain unfixed; it does not re-verify the rest of that history.

---

## 12. Verification

- **§5.1** — Open `Modules/CoreRPG/Sheet/SheetRootModel.swift`, lines 839-857. Line 849 reads `let insertIndex = sourceIndex < targetIndex ? targetIndex : targetIndex` — both ternary branches are the literal same expression, confirmed by direct inspection (not a formatting artifact). Traced by hand against `Array.move(fromOffsets:toOffset:)` semantics for both `sourceIndex < targetIndex` and `sourceIndex > targetIndex` cases; the two directions produce inconsistent before/after placement relative to the drop target, confirming the missing `- 1` adjustment.
- **§5.2** — Open `Modules/CoreRPG/Sheet/SheetRootModel.swift`, lines 321-328, and `Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift`, lines 8-21. Confirmed: (1) the `toggler` closure at `SheetRootModel.swift:323` captures `self` with no `weak`/`unowned`; (2) `LinkHighlightTextModel.toggler` is a stored `let` (line 21), not a fire-and-discard parameter; (3) the created model is stored back into `self.linkTextModel[id]` at `SheetRootModel.swift:326`, on the very object the closure captured — closing the cycle. Cross-checked that `reset(itemId:)` (`SheetRootModel.swift:234-256`) does clear `linkTextModel = [:]` and thus breaks the cycle for same-screen item switching, but confirmed no equivalent call exists on screen dismissal via a repo-wide grep for `reset(itemId:` call sites — the cycle is unguarded on that path.
- **§4.1** — Open `SheetModel.swift:105` and `SheetRootModel.swift:318`; both read `.localizedCaseInsensitiveContains(searchText)` verbatim. Cross-checked against CLAUDE.md's explicit `localizedStandardContains()` requirement.
- **§9.1** — `grep -rn "\.reset(with\|func reset(with" .` across the full repository (including test targets) returns exactly one match: the method's own definition at `SheetModel.swift:116`. No call sites.
- **§9.2 / §9.3** — Both independently re-derived by direct line-by-line reading of the current file state (not copied from history), then cross-referenced against `Docu/CODE_AUDIT_8.md` §9.12/§9.15, where the same files/lines were flagged previously — confirming these are unfixed carryovers rather than regressions.
- **Concurrency (§3)** — `mcp__xcode__BuildProject` on the `MasterRPG` scheme completed successfully in 31.5s; `mcp__xcode__XcodeListNavigatorIssues` at `warning` severity returned zero issues workspace-wide immediately after.
