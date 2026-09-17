# MasterRPG — CharacterRPG Module Code Audit

Generated 2026-09-17. Scope: `Modules/CharacterRPG/` — 59 Swift files, ~6,523 LOC (Controller/, Intent/, Menu/, Model/, Resources/, Root/, Route/, View/). No `Dead/` or archived directory exists in this module; the entire tree was audited.

A clean `xcodebuild -scheme CharacterRPG` (iPhone 17 Pro Simulator, iOS 27.0 runtime) produced **zero compiler warnings** inside this module — the concurrency/API-modernity findings below come from close reading, not the build log.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

---

## 1. Executive summary

1. **[Critical] `SheetController`'s sheet-tree builder has no cycle/depth guard** — §5.1 — `Controller/SheetController.swift:15-79`. Every other recursive walk over this same value/link graph in the module guards against cycles with `RecursionLimits.maxValueLinkDepth`; this one doesn't, and it runs on essentially every character-sheet render.
2. **[High] Tautological type-guard silently downgrades decimal entries to `.number`** — §5.2 — `Controller/EditController.swift:184,199`. `entry.type != .number || entry.type != .decimal` is always true for any single value, so linking a dice or a value always force-converts the entry, destroying chosen `.decimal` types.
3. **[High] `SearchController` recurses into linked sub-values with no cycle/depth guard** — §5.3 — `Controller/SearchController.swift:72-108,405-436`. Same malformed-data risk as #1, but in global/inspector search.
4. **[High] `AddtionalEntryRow`'s fallback `entryId` mints a new UUID on every access** — §8.1 — `View/AddtionalEntryRow.swift:54-56`. Defeats the view's own `Equatable` conformance and can desync sibling lookups within one render.
5. **[High] `EditController.swift` is a 900-line file mixing six unrelated concerns** — §9.7 — `Controller/EditController.swift:1-900`. Sheet-edit mapping, link toggling, duplication, inline quick-editing, and a self-contained ~200-line data-repair subsystem all live in one file.
6. **[Medium] `ValueModel`'s `nonisolated` `Equatable`/`Comparable`/`Codable` rely on a runtime `assumeMainActorIsolated` trap, not compile-time safety** — §3.3 — `Model/ValueModel.swift:122-129,202-253,379-386,509-515`. Any future off-MainActor caller traps instead of failing to compile.
7. **[Medium] `InlineRowViewer`'s `Equatable` ignores `destination`/`destinationModel`** — §8.2 — `View/InlineRowViewer.swift:10-57`. SwiftUI can skip a re-render that should have happened.
8. **[Medium] `ViewerRootView.gameSheetRootModel` mutates `@Observable` state as a side effect of a `body`-read computed property** — §8.3 — `Root/ViewerRootView.swift:90-108`. SwiftUI's "modifying state during view update" anti-pattern.
9. **[Medium] `EditController.duplicate(itemId:withCopy:)` is missing `@MainActor`** — §3.1 — `Controller/EditController.swift:337-345`. Every sibling function in the file is `@MainActor`; this one isn't, adding redundant actor hops in a recursive duplication loop.
10. **[Medium] App Intents accept empty/whitespace names and stale entity references without validation** — §5.6 — `Intent/CharacterManagementIntents.swift:32-51,74-88`. Siri/Shortcuts can create blank-named characters or silently no-op against a deleted character while still reporting success.

---

## 2. Quick wins (≤30 min each)

- **Fix the tautological guard** (§5.2) — change `||` to `&&` at `EditController.swift:184` and `:199`. Two-character fix, high-impact bug.
- **Fix `AddtionalEntryRow`'s non-deterministic `entryId`** (§8.1) — compute once as a stored `let` instead of a computed `var`.
- **Include `destination` in `InlineRowViewer.==`** (§8.2) — one-line fix mirroring `EntryListDiceRow.==`.
- **Delete `EditController.add(model:into:)`** (§9.1) — zero call sites anywhere in the app or tests.
- **Delete the five dead `ValueEntryModel` toggle/predicate properties** (§9.2) — `isGeneratorToggle`, `isSelectedToggle`, `valueTypeToggle`, `canGenerator`, `canSelection` at `Model/ValueEntryModel.swift:84-109`.
- **Delete `entryOrNew`/`photoOrNew` unused wrappers** (§9.3) — `Model/DataModel+Extensions.swift:17-19,28-30`.
- **Rename `AddtionalEntryRow.swift` → `AdditionalEntryRow.swift`** (§9.13) — fix the typo, update the one call site at `EditController.swift:159`.
- **Rename `SelectionCharacterRoute.swift` → `SelectionRoute.swift`** (§9.14) — matches every sibling module's naming and the type it actually declares.
- **Convert the three informal TODO-style comments to tracked `// TODO:`** (§9.16) — `EditController.swift:341,872`, `View/DetailEditorView.swift:14`.
- **Add `@MainActor` to `OpenCharacterIntent.perform()`** (§3.4) — matches its four sibling intents.
- **Add `@MainActor` to the `ValueGameStorable.updatePlayer(data:)` protocol requirement** (§3.5) — matches its 11 sibling requirements.
- **Replace the five raw `Circle()`/`RoundedRectangle()`/`Capsule()`/`Rectangle()` instantiations with static-member shapes** (§4.1) — `AddtionalEntryRow.swift:28`, `DropChooseView.swift:27,31`, `CharacterAddEntryOverlay.swift:90,165`.

---

## 3. Concurrency

The module is unusually clean: all four `@Observable` classes (`ValueModel`, `CharacterRootModel`, `ValueEditModel`, `ValueGameModel`) already carry `@MainActor`, and there are zero occurrences of `DispatchQueue`, `Task.detached`, `nonisolated(unsafe)`, `@unchecked Sendable`, `Task.sleep(nanoseconds:)`, or `withCheckedContinuation` anywhere in the module. In-code comments reference prior `CODE_AUDIT_Game`/`EditItem`/`13`/`10` passes, confirming this module already went through concurrency hardening. The findings below are the residual issues found by close reading.

### 3.1 `EditController.duplicate(itemId:withCopy:)` missing `@MainActor`
- **Location:** `Controller/EditController.swift:337-345`
- **What:** `func duplicate(itemId: UUID, withCopy: Bool) async -> UUID` is the only async function in this file not annotated `@MainActor` — every sibling (`duplicateSubValue`, `duplicateFolderEntries`, `removePhotos`, `willDeleteChildren`, `addNewGroup`, `addItemAsGroup`, `convertToGroup`, `addItem(sheet:forceSave:)`) is explicitly `@MainActor`.
- **Why:** Because the function itself is nonisolated, each `await` inside it is a genuine actor-hop rather than a plain suspension point, reintroducing a re-entrancy window its `@MainActor` siblings don't have — and it's called from `duplicateFolderEntries`'s recursive loop (line 324), multiplying the extra hops per duplicated child.
- **Action:** Add `@MainActor` to match the rest of the file.
- **Severity:** Medium

### 3.2 `@preconcurrency` conformance for `CharacterEntityQuery`
- **Location:** `Intent/CharacterEntity.swift:106-127` (specifically line 113, `extension CharacterEntityQuery: @preconcurrency IndexedEntityQuery`)
- **What:** Conforms to Apple's `IndexedEntityQuery` (gated `#if compiler(>=6.4)` / `@available(iOS 27, ...)`) using `@preconcurrency`, suppressing Swift 6 concurrency-safety checking for that conformance.
- **Why:** `@preconcurrency` silences isolation/Sendable checking rather than proving it's safe; if Apple's protocol gains stricter isolation annotations in a future SDK, this conformance won't benefit from a compiler error flagging the mismatch.
- **Action:** Re-check whether `@preconcurrency` is still needed each time the deployment target advances past iOS 27; remove once `IndexedEntityQuery`'s requirements are fully concurrency-annotated upstream.
- **Severity:** Low

### 3.3 `ValueModel`'s `nonisolated` protocol conformances rely on a runtime isolation trap
- **Location:** `Model/ValueModel.swift:122-129` (`<`), `:202-232` (`merge`), `:234-253` (`isSame`), `:379-386` (`duplicate`), `:509-515` (`==`)
- **What:** `ValueModel` is `@MainActor @Observable`, but conforms `nonisolated` to `Comparable`, `ItemDiffComparable`, and `ItemDuplicatable`; each of these five method bodies reads `@MainActor`-isolated stored properties by wrapping the body in `assumeMainActorIsolated { ... }` (CoreRPG's wrapper over `MainActor.assumeIsolated`).
- **Why:** `MainActor.assumeIsolated` is a *runtime* precondition, not a compiler guarantee. If any of `==`, `<`, `merge`, `isSame`, or `duplicate` is ever invoked from a genuinely non-MainActor context (e.g. `Set<ValueModel>`/`Dictionary` operations, `.sorted()`, or `Codable` machinery reached from a background `Task` elsewhere in the app), the app traps instead of failing to compile.
- **Action:** No change required if every call site is verified to stay on MainActor — this pattern is intentionally centralized in CoreRPG's `MainActorIsolationAssumption.swift` for exactly this kind of audit. Flagging so these five sites stay in that audit trail as new callers are added.
- **Severity:** Medium

### 3.4 `OpenCharacterIntent.perform()` omits `@MainActor`
- **Location:** `Intent/OpenCharacterIntent.swift:20-23`
- **What:** `func perform() async throws -> some IntentResult` has no `@MainActor`, while `CreateCharacterIntent.perform()`, `AddCharacterEntryIntent.perform()`, `DeleteCharacterIntent.perform()`, and `SearchCharactersIntent.perform()` (all in `Intent/CharacterManagementIntents.swift`) are explicitly `@MainActor`.
- **Why:** Functionally safe today (its one call, `await navigator.perform(...)`, hops correctly), but the inconsistency makes it easy for a future edit to add MainActor-isolated work here without the compiler forcing an explicit acknowledgment, unlike its siblings.
- **Action:** Add `@MainActor` for consistency.
- **Severity:** Low

### 3.5 `ValueGameStorable.updatePlayer(data:)` protocol requirement omits `@MainActor`
- **Location:** `Controller/GameController.swift:89` (requirement), `:483-484` (implementation)
- **What:** Every requirement on `ValueGameStorable` is `@MainActor` except `func updatePlayer(data: NetworkCodableDataType) async throws` (line 89); the concrete implementation is `@MainActor` (line 483-484).
- **Why:** Compiles today only because an `async` requirement can be satisfied by an actor-isolated implementation, but any other/future conformer is free to implement `updatePlayer` as genuinely nonisolated, silently losing the isolation guarantee every other method on this protocol provides.
- **Action:** Add `@MainActor` to the protocol requirement to match its 11 siblings.
- **Severity:** Low

---

## 4. API modernity

### 4.1 Concrete `Shape` types instantiated instead of the static-member form
- **Location:** `View/AddtionalEntryRow.swift:28` (`Circle().stroke(...)`); `View/DropChooseView.swift:27,31` (`RoundedRectangle(cornerRadius: 24, style: .continuous)` ×2); `View/CharacterAddEntryOverlay.swift:90` (`Capsule()`) and `:165` (`Rectangle().fill(...)`, inside a `#Preview`)
- **What:** Five call sites construct `Circle()`, `RoundedRectangle(cornerRadius:style:)`, `Capsule()`, and `Rectangle()` directly instead of the static-member shape syntax (`.circle`, `.rect(cornerRadius:style:)`, `.capsule`, `.rect`).
- **Why:** This repo's own CLAUDE.md explicitly mandates static-member lookup (`.circle` rather than `Circle()`) as a house-wide convention; these five are the only violations in the module.
- **Action:** Replace each with its static-member equivalent.
- **Severity:** Low

_No other API-modernity findings: no `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject`, no legacy `Formatter` subclasses, no `String(format:)`, no `replacingOccurrences`, no `foregroundColor()`/`cornerRadius()`/`tabItem()`, no single-parameter `onChange(of:)`, no `.contains()` for user-text filtering, and no `@available` guards below the iOS 26 deployment target were found anywhere in the module._

---

## 5. Bugs / logic errors

### 5.1 `SheetController`'s sheet-tree builder recurses with no cycle/depth guard
- **Location:** `Controller/SheetController.swift:15-79` — mutual recursion between `sheet(root:itemId:...)` (line 15) and `sheet(entry:...)` (line 42), via `entry.valueId` (line 52-53) and via same-module `linkRegisterController.linksFrom` links (line 58-74)
- **What:** `sheet(entry:...)` recurses into `sheet(root:itemId: subValueId, ...)` for every entry with a `valueId`, and again for every same-module link discovered via the link register, with no `visited` set or depth bound.
- **Why:** Every other recursive walk over this exact value/group graph in the module — `EditController.duplicateSubValue` (`EditController.swift:351-364`), `EditController.duplicateFolderEntries` (`:318-329`), `GameController.gameEntry`/`gameEntryPath` (`:241,289,319`) — explicitly guards against cycles using `RecursionLimits.maxValueLinkDepth`, with comments noting a cyclic `groupId`/`valueId` graph is "a plausible outcome of a merge/import bug, or two devices concurrently editing... via CloudKit sync." `SheetController` builds the sheet tree on essentially every character-sheet render/update and has no such guard — confirmed by direct read: no `RecursionLimits`, `visited`, or depth parameter appears anywhere in `SheetController.swift`. The same class of malformed data the rest of the module defends against will cause unbounded recursion and a stack-overflow crash here.
- **Action:** Thread a `visited: Set<UUID>` or depth counter through `sheet(root:itemId:...)`/`sheet(entry:...)` using `RecursionLimits.maxValueLinkDepth`, matching the pattern already used elsewhere in the module.
- **Severity:** Critical — verified by reading `SheetController.swift` in full and cross-checking the guarded pattern's presence at the cited `EditController`/`GameController` lines.

### 5.2 Tautological type-guard silently downgrades decimal entries to `.number`
- **Location:** `Controller/EditController.swift:184` and `:199`
- **What:** `if entry.type != .number || entry.type != .decimal { entry.type = .number }` is used when linking a dice (line 184) or a value (line 199) into an entry, apparently intending "only force to `.number` if the entry isn't already `.number` or `.decimal`."
- **Why:** For any single enum value, at least one of the two `!=` comparisons is always true — a value can never equal both `.number` and `.decimal` simultaneously — so the condition is a tautology that is always true. Every entry that gets a dice or value link is silently force-converted to `.number`, even if it was already `.decimal`, corrupting the user's chosen value type and losing decimal display/precision from then on. Confirmed by direct read.
- **Action:** Change `||` to `&&` at both sites (`entry.type != .number && entry.type != .decimal`).
- **Severity:** High

### 5.3 `SearchController` recurses into linked sub-values with no cycle/depth guard
- **Location:** `Controller/SearchController.swift:72-108` (`result(item:searchText:displayMode:foundResults:)`, recursion at `:102-105`) and `:405-436` (`collectValueEntries(of:characterId:characterName:searchText:into:)`, recursion at `:431-434`)
- **What:** Both functions recurse into `entry.valueId`'s sub-value with no depth counter or `visited` set, unlike the sibling recursive walker in the same file, `buildCharacterFolderNode` (`:184-218`), which is explicitly bounded by `FolderTreeDepthLimit.max`. Confirmed by direct read of lines 72-108.
- **Why:** Same malformed/cyclic-data risk as §5.1 — a cyclic `valueId` chain (e.g. from a CloudKit merge conflict) will recurse indefinitely during global search or the inspector search, crashing with a stack overflow.
- **Action:** Add the same depth/visited guard used by `buildCharacterFolderNode` to both functions.
- **Severity:** High

### 5.4 Decimal-type formula results aren't guarded against NaN/Infinity
- **Location:** `Model/ValueEntryModel.swift:184-198` (`calculate(on:)`)
- **What:** For `.number` type, the result is checked for `isNaN`, `isInfinite`, and overflow before formatting (returning `"0 Error"` otherwise); for `.decimal` type, the `else` branch just returns `"\(final)"` with no such check.
- **Why:** A division-by-zero in a decimal-typed formula (e.g. dividing by a linked value that resolves to 0) silently displays `"inf"`, `"-inf"`, or `"nan"` to the player instead of the same `"0 Error"` fallback used for number-typed entries — an inconsistent and confusing failure mode on a live character sheet.
- **Action:** Apply the same `isNaN || isInfinite` guard to the `.decimal` branch before formatting.
- **Severity:** Medium

### 5.5 `ValueModel.filter(filter:includeEntries:)` ignores the `includeEntries` flag
- **Location:** `Model/ValueModel.swift:415-422`
- **What:** The `includeEntries` parameter is never referenced in the function body — entries are always searched (for non-special-category items) regardless of what the caller passes.
- **Why:** CoreRPG's shared `SearchControllable.globalSearchResults(searchText:)` default explicitly calls this with `includeEntries: false` expecting entries excluded from item-level matching. CharacterRPG's own `SearchController` currently overrides `globalSearchResults` with a custom implementation that never calls `ValueModel.filter`, so this is latent rather than actively firing today — but any future code path using the shared protocol default (or calling `.filter(filter:includeEntries:)` generically) will silently get entry-level matches it explicitly asked to exclude. `RuleRPG`'s `RuleModel.filter` correctly gates on `includeEntries` for comparison.
- **Action:** Gate the `entries.contains { … }` return behind `includeEntries`, matching `RuleModel.filter`'s pattern.
- **Severity:** Low

### 5.6 App Intents accept empty/whitespace names and stale entity references without validation
- **Location:** `Intent/CharacterManagementIntents.swift:32-51` (`CreateCharacterIntent.perform`) and `:74-88` (`AddCharacterEntryIntent.perform`)
- **What:** Neither intent trims/validates `name`/`entryName` before creating the character or entry, and `AddCharacterEntryIntent` never checks that `target.id` (a `CharacterEntity` that may be stale — deleted since Siri/Shortcuts last cached it) still resolves to a real character before reporting success.
- **Why:** Siri/Shortcuts can pass an empty or all-whitespace string, creating a character/entry with a blank, unusable name; if `target` refers to an already-deleted character, the add presumably no-ops silently while the intent still returns a "Added … to …" success dialog, misleading the user/automation about what happened.
- **Action:** Validate `name`/`entryName` are non-empty after trimming (returning a `requestValueDialog` prompt or throwing otherwise), and check the target character still exists before reporting success in `AddCharacterEntryIntent`.
- **Severity:** Medium

### 5.7 `ValueType` ↔ `SheetModelEditType` conversion logic split across two files
- **Location:** `Model/ValueEntryModel.swift:200-208` (`editType`) and `Controller/EditController.swift:71-90` (`updateSheetEditType`)
- **What:** `ValueEntryModel.editType` maps `ValueType → SheetModelEditType`; `EditController.updateSheetEditType` independently hand-writes the inverse `SheetModelEditType → ValueType` switch. Both must be kept in sync by hand whenever a new `ValueType` case is added.
- **Why:** Two independent switch statements implementing inverse mappings of the same two enums, in different files, is a correctness trap — a new `ValueType` case added to one switch but not the other compiles fine (no exhaustiveness link between them) and silently misbehaves.
- **Action:** Co-locate both directions next to each other (e.g. as failable/custom initializers on each type in one file) so a reviewer sees both switches together.
- **Severity:** Low

_Verified clean: zero force-unwraps (`!`), implicitly-unwrapped optionals, `as!` force-casts, `try!`, `fatalError`, `hashValue` usage, `print()` calls, or empty/error-swallowing `catch {}` blocks anywhere in the module. `LinkController.calculate(entry:deep:)` and `GameController.calculatedValue(_:type:)` both correctly resolve markdown links before doing arithmetic, and `ValueModel.version`/`CharacterPackageVersion.digest` correctly use a stable version digest rather than `hashValue` — the known cross-module bug classes from prior audits do not recur here._

---

## 6. Security

### 6.1 `CharacterEntity`'s PDF export uses unsanitized user text as a cache filename
- **Location:** `Intent/CharacterEntity.swift:60-81` (`Transferable.transferRepresentation`, `FileRepresentation`)
- **What:** `URL.cachesDirectory.appending(component: "\(item.name).pdf")` builds the export filename directly from the character's user-editable `name` with no sanitization or uniquing.
- **Why:** Two characters sharing a name (or concurrent exports of the same character) collide on the same cache file path; unusual characters in `name` (emoji, very long strings, reserved filename characters) can produce degenerate filenames. Low risk since `appending(component:)` percent-encodes path separators so it cannot escape the caches directory — this is a correctness/collision issue, not an exploitable one.
- **Action:** Derive the filename from `item.id` (or a sanitized/uniqued version of `name`) instead of the raw user-facing name.
- **Severity:** Low

_No hardcoded secrets, API keys, or tokens found (grepped for `Bearer`/`apiKey`/`secret`/`Authorization`). No sensitive auth-token storage in this module — Character data is Core Data + CloudKit only, with no GM-only/player-visible field leak identified in `ExportController`/`SheetController`._

---

## 7. Performance

_No findings._ Neither the concurrency/modernity pass nor the bugs/performance pass surfaced a distinct performance issue in this module (no per-frame allocations, no uncached heavy `body` work beyond what's already covered in §8, no O(n²) search patterns). The unbounded recursions in §5.1 and §5.3 are logic/crash bugs, not performance issues, and are reported there. This module was not profiled with Instruments — see §11.

---

## 8. SwiftUI / UI

### 8.1 `AddtionalEntryRow`'s fallback `entryId` is non-deterministic across accesses in the same render
- **Location:** `View/AddtionalEntryRow.swift:54-56` (`private var entryId: UUID { source.entryId ?? UUID() }`), consumed at lines 41, 51, and 66
- **What:** `entryId` is a computed property that mints a brand-new random `UUID()` every time it's evaluated whenever `source.entryId` is `nil`; it's called independently from `body` (line 41), `valueEntry` (line 51), and the `Equatable` conformance (line 66).
- **Why:** If `source.entryId` is ever `nil`, each of those three call sites gets a *different* random UUID within the same render pass: `EntryListDiceRow` gets one id, `model[entryId]` (which returns `.empty(id)` on a miss per `ValueModel`'s subscript) is looked up with another, and the `==` used by `.equatable()` compares yet another pair of freshly-minted UUIDs that can never be equal — permanently defeating the view's equatable-based render-skipping and returning empty/incorrect entry data.
- **Action:** Compute `entryId` once (e.g. store as a `let` in `init`, or memoize via `source.entryId`) so all three uses agree within a render; consider making it non-optional at the call site if `source.entryId` is actually guaranteed non-nil in practice.
- **Severity:** High

### 8.2 `InlineRowViewer`'s `Equatable` conformance ignores `destination` and `destinationModel`
- **Location:** `View/InlineRowViewer.swift:10-57` (fields at 11-19, `body`'s use of `destination`/`destinationModel` at 27-37, `==` at 54-56)
- **What:** `static func ==` only compares `source`, but `body` branches and renders based on `destination.entryId`, `destination.itemId`, and `destinationModel`.
- **Why:** Call sites wrap this view with `.equatable()`, so SwiftUI uses this `==` to decide whether to skip re-rendering; if two updates share the same `source` but differ in `destination`/`destinationModel`, the view won't re-render even though its displayed content should change.
- **Action:** Include `destination` (and ideally `destinationModel`'s identity) in the equality check, mirroring how `EntryListDiceRow.==` (`EntryListDiceRow.swift:17-21`) compares `itemId`, `entryId`, and `resolvedModel?.id`.
- **Severity:** Medium

### 8.3 View-body computed property mutates observable state as a side effect
- **Location:** `Root/ViewerRootView.swift:90-108` (`gameSheetRootModel`), invoked from `body` at line 64
- **What:** `gameSheetRootModel` is a plain computed `var` read directly from `body`; on every access it either calls `existing.reset(itemId:)` on the stored `@Observable` model or creates a brand-new `SheetRootModel` and assigns it back into `root.editController.editorModel.gameSheetRootModel`.
- **Why:** Mutating `@Observable` state from inside a view's `body` evaluation is an anti-pattern SwiftUI explicitly warns about ("Modifying state during view update") and can trigger extra render passes or repeatedly hit the fallback-create branch if `body` is invoked more than once per update cycle (e.g. during diffing/preview re-evaluation).
- **Action:** Move the "reuse-or-create-and-store" logic out of the computed property into an explicit lifecycle hook (`.onAppear`/`.task(id:)`/`onChange(of: model.id)`) that only runs once per relevant change, and have `body` merely read the already-resolved value.
- **Severity:** Medium

_Reviewed all 17 View/ files, all 7 Root/ files, and Menu/CharacterCommands.swift in full for `@State`/`@Bindable`/`@Observable` misuse, modifier ordering, Dynamic Type, and hoistable view-body work. No other issues found: all `@State` is private and view-owned, no passed values are mis-declared `@State`, no `GeometryReader` usage, `onChange(of:)` is always used in its two-parameter or zero-parameter form, and destructive actions (`DropChooseView`'s remove button) carry `accessibilityLabel`/`accessibilityHidden`. `EntryListDiceRow`'s `.onChange(of: updateOtherValue, initial: true)` re-registration pattern (`EntryListDiceRow.swift:37-42`) was checked against `LinkController.updateValueCalculation`'s `withObservationTracking(_:onChange:)` implementation (`LinkController.swift:270-284`) and confirmed correct — `withObservationTracking`'s `onChange` fires once per registration, so toggling state inside it to re-trigger the `onChange(of:)` and re-subscribe is the idiomatic pattern, not a bug._

---

## 9. Dead code / duplication / refactor

### 9.1 `EditController.add(model:into:)` is dead code
- **Location:** `Controller/EditController.swift:664-670`
- **What:** `func add(model childModel: ValueModel, into itemId: UUID?)` under the `// MARK: - GameController` section has zero call sites anywhere in the app or test suite.
- **Why:** Dead code increases surface area for maintainers and gives a false impression that `GameController` depends on this path.
- **Action:** Delete the method (and the stray "GameController" MARK, which doesn't match its actual caller-less content) unless a planned caller is imminent.
- **Severity:** Medium

### 9.2 `ValueEntryModel` dead toggle/predicate cluster
- **Location:** `Model/ValueEntryModel.swift:84-109` (`isGeneratorToggle`, `isSelectedToggle`, `valueTypeToggle`, `canGenerator`, `canSelection`)
- **What:** Five computed properties declared but never referenced anywhere else in the module, app, or tests.
- **Why:** These look like they were meant to back SwiftUI bindings (`$model.isGeneratorToggle` etc.) but nothing binds to them; pure maintenance weight.
- **Action:** Remove unless a near-term UI binding is planned that should use them instead of the ad-hoc mutation call sites that exist today.
- **Severity:** Medium

### 9.3 `entryOrNew`/`photoOrNew` convenience wrappers unused
- **Location:** `Model/DataModel+Extensions.swift:17-19,28-30`
- **What:** `RPGValue.entryOrNew(for:)` and `.photoOrNew(for:)` wrap the shared generic `childOrNew` (from `Modules/CoreRPG/Persistence/CoreDataRelationship.swift`) but have no call sites — only `childOrNew` itself (via `syncEntries` in `DataController.swift`) is actually used.
- **Why:** CoreRPG's own doc comment calls this the pre-`childOrNew` pattern that migration should have deleted; the same leftover pattern repeats in every other module's own `DataModel+Extensions.swift`.
- **Action:** Delete both wrappers in this file (the same pattern module-wide is out of this module's scope).
- **Severity:** Low

### 9.4 `ItemController.children(itemId:)` override never invoked
- **Location:** `Controller/ItemController.swift:31-34`
- **What:** Overrides `ItemControllable.children(itemId:)` with custom single-element-array logic, but no call site exists anywhere in the app (the CoreRPG default implementation is equally unused).
- **Why:** Unreachable protocol-conformance code masks the fact this customization has no effect.
- **Action:** Confirm no caller is planned; if none, remove the override — coordinate with CoreRPG since other modules may have the same dead override.
- **Severity:** Low

### 9.5 `ViewController.diceSelection(root:selectionModel:)` only exercised by its own test
- **Location:** `Controller/ViewController.swift:34-37`
- **What:** Not a `ViewControllable` protocol requirement; its only caller is `Tests/CharacterRPGTests/ViewControllerTests.swift`. The identical uncalled pattern repeats in AdventureRPG/MapRPG/TableRPG's own `ViewController.swift`.
- **Why:** A method with a test but no production caller is either dead or missing a wire-up; either way it's misleading coverage.
- **Action:** Either wire it into a real call site (e.g. a Character-specific dice picker) or delete it and its test.
- **Severity:** Medium

### 9.6 Unused `itemId` parameter on `ValueGameModel.resetGameDiceId`
- **Location:** `Controller/GameController.swift:16-18`
- **What:** `func resetGameDiceId(itemId: UUID, entryId: UUID) { gameEntryDiceId[entryId] = nil }` never reads `itemId`, and only clears `gameEntryDiceId`, not the companion `gameDiceId` dictionary that `removeBattleCharacterCopies` (`:459-475`) clears for both keyed dictionaries together.
- **Why:** An unused parameter is dead surface area, and the asymmetry with `removeBattleCharacterCopies` suggests this reset may be incomplete rather than intentional.
- **Action:** Either remove the unused parameter or use it (e.g. also clear `gameDiceId[entryId]`) — verify against `Tests/CharacterRPGTests/GameControllerTests.swift:45` before changing behavior.
- **Severity:** Low

### 9.7 `EditController.swift` is a 900-line God file
- **Location:** `Controller/EditController.swift:1-900`
- **What:** One file carries: sheet-edit-type mapping, network entry-update encoding, link add/remove, item duplication (3 recursive helpers), inline quick-editor value read/write (7 methods), `QuickEntryEditor` text parsing, sheet-generated item creation, and a ~200-line "Final Repair" constraint-fixup subsystem (`repairCharacterContrains` + 4 private helpers + `removeOld`, lines ~704-899) that is already self-contained under its own `// MARK: - Final Repair`.
- **Why:** A single 900-line struct extension file is hard to navigate/review and mixes unrelated concerns (data-repair heuristics vs. live gameplay value editing vs. duplication).
- **Action:** Extract at minimum `EditController+Repair.swift` (the self-contained repair block) and `EditController+InlineEditor.swift` (the "Inline Quick Editor" + "QuickEntryEditor" sections, ~lines 503-660); consider a further `EditController+Duplication.swift` for the duplication helpers.
- **Severity:** High

### 9.8 `GameController.swift` mixes four independent concerns
- **Location:** `Controller/GameController.swift:1-528`
- **What:** Contains `ValueGameModel`/`GameEntryPath`/`ValueGameStorable` type definitions, dice-game caching (`gameDiceId`/`cachedGameDice`, ~lines 134-176), battle-copy management (`createBattleCharacterCopy`/`battleCharacterCopy`/`removeBattleCharacterCopies`), recursive entry-path resolution (the `gameEntry*` family, `gameEntryPath`, `resolveGroupedEntry`, `gameMemoryCopy`), and network sync (`applyGameValueEntryUpdate`, `updatePlayer`) all in one file/struct.
- **Why:** Four largely independent concerns bundled together, each already delimited by comments/doc blocks, making the file harder to scan than necessary.
- **Action:** Split into `GameController+Dice.swift`, `GameController+EntryResolution.swift` (the `gameEntry*`/path-resolution cluster), and `GameController+Sync.swift` (`applyGameValueEntryUpdate`/`updatePlayer`), leaving battle-copy management and protocol/type declarations in the main file.
- **Severity:** Medium

### 9.9 `ValueModel.swift` — version-digest and link-register logic are natural extractions
- **Location:** `Model/ValueModel.swift:1-520`
- **What:** The class body, `ItemLinkRegistable` conformance (~132-199), `ItemDiffComparable`/version digest (~202-262), the private `CanonicalValueContent`/`CanonicalValueEntry`/`categoryAndTags` version-fingerprint machinery (~264-365), `ItemDuplicatable` (~379-395), `ItemDataAccessable` (~399-465), and `Codable` (~472-507) all live in one file.
- **Why:** The `CanonicalValueContent` version-digest subsystem (~100 lines) and the link-register diffing logic (~70 lines) are each self-contained and independently testable, but buried inside a single large model file alongside unrelated `Codable`/`Equatable` boilerplate.
- **Action:** Extract `ValueModel+VersionDigest.swift` (the `version` property plus `CanonicalValueContent`/`CanonicalValueEntry`/`categoryAndTags`) and `ValueModel+LinkRegister.swift` (`ItemLinkRegistable` conformance).
- **Severity:** Medium

### 9.10 `PreviewData.swift`: `previewFixture(models:)` and `testRoot(...)` duplicate ~15 lines of root-wiring verbatim
- **Location:** `Model/PreviewData.swift:18-35` and `:51-64`
- **What:** Both functions build a `CharacterRootModel`, a fake `RootManager`, a real cross-wired `RootManager`, then call `setUp` six times (once per sub-root) with identical arguments — differing only in the initial constructor args and whether preview models get inserted afterward.
- **Why:** Any future change to the root-wiring sequence (e.g. a new sub-root needing `setUp`) must be made in two places or silently drifts, since preview and test fixtures would then wire up differently.
- **Action:** Extract a shared private helper (e.g. `wireRoots(_ root: CharacterRootModel) -> RootManager`) that both functions call.
- **Severity:** Low

### 9.11 `SheetController` builds the same dice-inline `SheetModel` three separate times
- **Location:** `Controller/SheetController.swift:47-49, 96-98, 196`
- **What:** `sheet(entry:...)` (:47-49), `createDiceInline(...)` (:96-98), and `update(entry:...)` (:196) each independently construct a `SheetModel(source: ItemRowModel(itemId: diceId, typeId: .dice), ...)` "dice inline sheet" literal, with only `destination`/`isShown` varying.
- **Why:** Three near-identical constructions of the same concept make it easy for one call site to drift when the shape changes — `sheet(entry:)`'s version already omits `isShown` and constructs `destination` inline rather than reusing `createDiceInline`.
- **Action:** Route all three through `createDiceInline(diceId:itemId:level:isShown:)` (adjusting its signature to accept an explicit `destination` where needed) instead of hand-rolling the `SheetModel` literal each time.
- **Severity:** Medium

### 9.12 `EditController`'s four `updateValue(itemId:entryId:...)` overloads repeat the same guard/save/persist boilerplate
- **Location:** `Controller/EditController.swift:555-606`
- **What:** `updateValue(...decimal:)`, `updateValue(...number:)`, `updateValue(...selected:)`, and `updateValue(...value:)` each independently do: `guard let entryId, let item = editModel(for: itemId) else { return }`, an unchanged-value early-return, `item[entryId].X = Y`, `save(updated:message:)`, then `saveGameDataToPermanent(itemId:entryId:)`.
- **Why:** The only genuinely distinct part of each overload is the single mutation and its localized message string; the surrounding five lines of control flow are copy-pasted four times, so a future change to the persistence flow needs four edits.
- **Action:** Factor out a private helper (e.g. `applyEntryUpdate(itemId:entryId:message:mutate:)`) that does the guard/save/`saveGameDataToPermanent` dance once, with each public overload supplying just its comparison + mutation closure.
- **Severity:** Medium

### 9.13 `AddtionalEntryRow.swift` is a typo for "AdditionalEntryRow"
- **Location:** `View/AddtionalEntryRow.swift:1` (whole file; type declared at line 6)
- **What:** File and type name are both misspelled ("Addtional" instead of "Additional").
- **Why:** Typo'd symbol names are harder to discover via search/autocomplete; `EditController.swift:159` already references it (`AddtionalEntryRow(source:entry:textModel:)`), so the typo has propagated to at least one call site.
- **Action:** Rename the file and type to `AdditionalEntryRow`; update the call site in `EditController.swift:159`.
- **Severity:** Low

### 9.14 `SelectionCharacterRoute.swift` filename doesn't match its type
- **Location:** `Route/SelectionCharacterRoute.swift:1-29` (type declared as `enum SelectionRoute` at line 6)
- **What:** Every other Route file in this module (and every sibling module — PdfRPG, AdventureRPG, DiceRPG, PhotoRPG all name theirs `SelectionRoute.swift`) matches filename to type name exactly. Only CharacterRPG's copy is named `SelectionCharacterRoute.swift` while declaring the same generic `SelectionRoute`.
- **Why:** The filename misleadingly suggests a Character-specific type exists, when the actual type is the same generic type every other module declares.
- **Action:** Rename the file to `SelectionRoute.swift` to match the type and the rest of the codebase's convention.
- **Severity:** Low

### 9.15 `CharacterDataController` vs. `DataController` naming collision
- **Location:** `Controller/CharacterDataController.swift:1-27` vs. `Controller/DataController.swift:1-115`
- **What:** The module has two differently-scoped "DataController" types in the same folder: `DataController` is the documented domain↔CoreData mapper (per this repo's Controller-naming convention), while `CharacterDataController` is an unrelated, narrowly-scoped helper used only by `Sources/RPGShare/ShareExtensionSaveController.swift` to create one new value from the iOS Share Extension.
- **Why:** A reader relying on the documented "DataController = domain↔CoreData mapper" convention will likely assume `CharacterDataController` is the module's primary data controller (or a variant of it) rather than a narrow Share-Extension-only helper.
- **Action:** Rename to something that signals its actual scope, e.g. `ShareExtensionValueController`.
- **Severity:** Low

### 9.16 Informal, TODO-like comments not caught by a `TODO|FIXME|HACK` sweep
- **Location:** `Controller/EditController.swift:341` ("// this will not add the links to the database linkregister is missing"), `:872` ("groupItem.displayState = 0 // make this visible (or should I remove it?"), `View/DetailEditorView.swift:14` ("// task is swallowing the updates later, this causes a 2 double creation on start / that is acceptable")
- **What:** Three comments read as unresolved self-notes rather than documentation: one flags a known missing feature (link-register not populated on duplicate), one is a literal open question left in the code, one documents an accepted-but-unfixed double-creation bug.
- **Why:** These are functionally TODOs that won't surface in a standard `TODO|FIXME|HACK` grep sweep; the duplicate-link-register gap in particular sounds like a real latent bug (duplicated items' links wouldn't be discoverable via the link register).
- **Action:** Convert each to an explicit `// TODO:` (or file a tracked issue); specifically re-verify whether `EditController.swift:341`'s "linkregister is missing" gap is still true and worth fixing.
- **Severity:** Low

### 9.17 `DiceDropSection.swift` and `PhotoDropSection.swift` are structurally duplicated
- **Location:** `View/DiceDropSection.swift:1-31` and `View/PhotoDropSection.swift:1-31`
- **What:** Both are ~30-line views wrapping a `root.<X>Root.viewController` call, an `.onChange(of: selection)` that calls `root.editController.add(...)`, and a `.task(id:)` that calls `.resetSelection(...)` — identical shape, differing only in which sub-root/selection model/add-method is used.
- **Why:** The same three-part scaffold is hand-copied per drop target; AdventureRPG's own `DiceDropSection.swift`/`PhotoDropSection.swift` repeat the exact same shape, suggesting a shared generic component in CoreRPG would avoid a fresh per-module rewrite each time a module gains this kind of drop target.
- **Action:** Extract a generic `ItemDropSection<Selection>` view (or a CoreRPG helper) taking the viewer content, selection model, and add/reset closures, and have both views become thin instantiations of it.
- **Severity:** Low

### 9.18 `ValueModel`'s `duplicate()`/`duplicateWithoutCopy()`/`copy()` are three near-identical constructors
- **Location:** `Model/ValueModel.swift:380-413`
- **What:** All three build a `ValueModel(...)` passing nearly the same 11 arguments, differing only in `id` (new vs. same), `name` (renamed-copy vs. original), `entries` (re-duplicated vs. passthrough), and whether `parentId`/`groupId` are nilled out.
- **Why:** Three parallel initializer call sites for "make another `ValueModel` like this one" is a drift risk — a new stored property must be remembered in three places (plus `ValueSnapshot.makeModel()`).
- **Action:** Introduce one private clone helper parameterized by `(id:, name:, entries:, parentId:, groupId:)` that the three public methods call.
- **Severity:** Medium

### 9.19 A few unnamed magic constants
- **Location:** `View/QuickEntryEditor.swift:13` (`DebouncerModel(initialValue: "", delay: 2)`), `View/DropChooseView.swift:23,25,27,32` (frame height `128`, corner radius `24` used 3×, stroke `lineWidth: 2`)
- **What:** Unlike `EditController`'s `linkToggleDelay`/`AddGroupButton`'s `scrollToNewGroupDelay` (both properly named `static let` constants), the debounce delay and the drop-target's sizing/corner-radius/stroke-width values are inline literals repeated across the same view.
- **Why:** `24` appears three times in `DropChooseView.swift` for what should be one concept (corner radius); a future design tweak requires hunting down each literal instead of changing one named constant.
- **Action:** Promote these to named `static let` constants near their usage, following the pattern already established by `linkToggleDelay`/`scrollToNewGroupDelay`.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Make the cycle/depth-guard pattern mandatory for every recursive walk over the value/link graph.** `EditController` and `GameController` both defend against cyclic `groupId`/`valueId` data (a documented, real outcome of CloudKit merge conflicts and concurrent edits) with `RecursionLimits.maxValueLinkDepth` and `visited: Set<UUID>` — but `SheetController` (§5.1) and `SearchController` (§5.3) don't, despite walking the identical graph. Treat this as a checklist item for any new recursive traversal in this module: does it touch `entry.valueId` or link-register data, and if so, does it carry the same guard as its siblings?
2. **Audit every `.equatable()`-wrapped view for equality/render coverage.** Two separate findings in this module (§8.1, §8.2) are the same root cause: a custom `Equatable` conformance that doesn't cover everything `body` actually reads, silently breaking SwiftUI's render-skip optimization. `EntryListDiceRow.==` gets this right (compares `itemId`, `entryId`, `resolvedModel?.id`) — use it as the template and grep for every `Equatable` view in the module to confirm its `==` covers every property `body` branches or renders on.
3. **Do a full `@MainActor` consistency sweep on async functions.** §3.1, §3.4, and §3.5 are all the same shape: one function in a file/protocol is missing `@MainActor` while every sibling has it. Individually low-risk, but the pattern recurring three times suggests annotations are being added ad hoc rather than enforced. A lint rule or periodic grep for "async func in an otherwise-`@MainActor` file without its own `@MainActor`" would catch this class going forward.
4. **Introduce small private "construct once" helpers wherever a type is built by hand in 3+ places.** §9.11 (dice-inline `SheetModel`), §9.12 (four `updateValue` overloads), and §9.18 (three `ValueModel` clone constructors) are all the same drift risk: a shape or field list duplicated across call sites that must be remembered together. None are urgent individually, but as a house pattern, prefer one private factory/helper over copy-pasted literals whenever a third occurrence appears.
5. **Split `EditController.swift` and `GameController.swift` along their existing `// MARK:` seams** (§9.7, §9.8) — both files are already internally organized into clearly-delimited sections; the work is mechanical extraction, not redesign, and would make future single-concern changes easier to review in isolation.

---

## 11. What was NOT audited

- **Cross-module code CharacterRPG depends on** (CoreRPG, DiceRPG, PdfRPG, PhotoRPG, TableRPG, GeneratorRPG) — only read where directly referenced from CharacterRPG call sites (e.g. `RecursionLimits`, `assumeMainActorIsolated`, `SearchControllable` defaults); no independent audit of those modules' own code.
- **`Tests/CharacterRPGTests/`** — referenced to confirm/deny call sites (e.g. §9.5, §9.6) but not reviewed for test quality or coverage gaps.
- **`Resources/Model.xcdatamodeld`** — the Core Data schema file itself was not opened; CloudKit-compatibility rules (optional properties/relationships) were checked only where visible from `ValueModel`/`ValueEntryModel`'s Swift-side mapping code, not from the `.xcdatamodel` directly.
- **Algorithmic correctness of `Calculator.swift`'s formula evaluation** beyond the NaN/Infinity guard gap (§5.4) — deep review of the expression-parsing logic itself is out of scope.
- **Localization wording** — `String(localized:)`/`Text(_:bundle:)` usage was checked for the correct `.module` bundle pattern per CLAUDE.md, but translated string content/quality was not assessed.
- **Instruments profiling / performance traces** — §7's "no findings" reflects static reading only; no `.trace` capture was recorded or analyzed for this module.
- **macOS/tvOS/visionOS-specific manual testing** — the build verification was iOS Simulator only (`xcodebuild -scheme CharacterRPG`, iPhone 17 Pro, iOS 27.0); platform-conditional code paths (`#if os(...)`) were read but not exercised on other platforms.
- **Xcode project/build-settings review** beyond confirming a clean, warning-free build of the `CharacterRPG` scheme.
- **`RPGShare` Share Extension target** — read only the one call site into `CharacterDataController` (§9.15); the extension's own code was not audited.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line.

- **§5.1 (Critical)** — open `Modules/CharacterRPG/Controller/SheetController.swift`, lines 15-79. Confirm `sheet(root:itemId:...)` and `sheet(entry:...)` recurse into each other with no `visited`/depth parameter anywhere in the file, then open `Modules/CharacterRPG/Controller/EditController.swift:318-329,351-364` and `Modules/CharacterRPG/Controller/GameController.swift:241,289,319` to see the `RecursionLimits.maxValueLinkDepth`/`visited` guard pattern this file is missing.
- **§5.2 (High)** — open `EditController.swift`, lines 184 and 199. Confirm both read `if entry.type != .number || entry.type != .decimal` — an always-true condition for any single `ValueType` case.
- **§5.3 (High)** — open `Modules/CharacterRPG/Controller/SearchController.swift`, lines 72-108. Confirm the recursive call at line 102-104 into `result(item:...)` carries no depth/visited argument, unlike `buildCharacterFolderNode` (lines 184-218) in the same file.
- **§8.1 (High)** — open `Modules/CharacterRPG/View/AddtionalEntryRow.swift`, lines 54-56. Confirm `entryId` is a computed `var` (not a stored `let`) that calls `UUID()` in its fallback branch, and that it's read independently at lines 41, 51, and 66.
- **§9.7 (High)** — open `EditController.swift` and confirm its line count (~900) and the six distinct `// MARK:` sections spanning sheet-editing, duplication, inline editing, and the self-contained "Final Repair" block (~lines 704-899).

If any finding doesn't reproduce when you visit the line, flag the specific reference for re-investigation.
