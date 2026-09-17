# MasterRPG — DiceRPG Module Code Audit

Generated 2026-09-17. Scope: `Modules/DiceRPG/` only — 76 Swift files, ~7,027 LOC, across the MasterRPG (iOS/visionOS), MasterMac, MasterTV, and DiceRollerWidgetExtension targets. No other module was audited; DiceRPG's own shared Core Data model (`Resources/Model.xcdatamodeld`) was checked in full.

The module compiled with **zero warnings** on a forced clean rebuild under Swift 6 / `SWIFT_STRICT_CONCURRENCY = complete`, and carries visible scars from many prior audit passes (`// See CODE_AUDIT...` comments throughout) — most first-pass anti-patterns (force-unwraps, `DispatchQueue`, `ObservableObject`, single-parameter `onChange`, `GeometryReader`, etc.) are already gone. The findings below are what a close read turned up beyond that.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action.

---

## Fix status (2026-09-17)

All Critical/High/Medium findings and nearly all Low findings were applied and verified with a full `xcodebuild` of the `MasterRPG` scheme (0 errors, 0 warnings), plus a scoped `build-for-testing` pass covering `DiceRPGTests`, `DiceRPGSnapshotTests`, and `GameRPGTests` (all compiled cleanly). Actual test *execution* is currently blocked in this environment by a pre-existing, unrelated compile failure in `CoreRPGSnapshotTests` (`navigationSceneRestorationEnabled` missing on the iOS 27 beta SDK) — not part of this audit's scope and not touched by these fixes.

**Intentionally not applied**, with rationale:
- **§3.2** (`DiceModel`'s `nonisolated` conformances trap via `assumeMainActorIsolated`) — architectural observation, no concrete safe code change identified; left as documented risk.
- **§4.4** (`AnyView` in `ViewController.swift`) — confirmed structurally necessary for the cross-module `ViewControllable` protocol; left as-is.
- **§7.3**, **§9.8**, **§9.19** — each explicitly recommended "no urgent action" in its own finding; the underlying duplication is a deliberate Sendable-boundary/widget-extension-isolation pattern.
- **§9.9** (splitting `DiceModel.swift`/`GameController.swift` into extension files) — deferred: purely organizational with zero functional impact, but hand-copying ~1,300 lines across new files during this same pass carried more transcription risk than the benefit justified. Worth a dedicated, separately-verified follow-up.
- **§9.15** (`ViewController.gameView(root:)` ignores its parameter) — the finding itself says this needs cross-module coordination with sibling modules (PdfRPG has the identical issue) before changing the shared protocol; not done unilaterally here.

**One finding was withdrawn as a false positive after it broke the build**: §9.17 (`DieModel.name`'s no-op setter) — see its updated entry below. This is the kind of overstated/incorrect finding the audit process asks to catch before shipping; it slipped through here and was caught by the build instead, then corrected.

---

## 1. Executive summary

Top items to address, in priority order:

1. **[Critical] Infinite loop / permanent UI hang when reroll options cover every face of a die** — §5.1 — `Modules/DiceRPG/Model/DieModel.swift:143-149`.
2. **[High] Siri/Shortcuts "Roll a D20", "Roll a D6", and "Dice History" open a URL scheme the app never registers** — §5.2 — `Modules/DiceRPG/Intent/DiceIntents.swift:31-59`.
3. **[High] Reroll/Coup/Fumble trigger-value editors validate against the wrong (pool-sum) range**, making "reroll/fumble on a natural 1" impossible to configure for any multi-die pool — §5.3 — `Modules/DiceRPG/Dice/RerollEditor.swift:124,156`.
4. **[High] Dice color/skin choice is silently discarded on every Core Data load / CloudKit merge** — §5.4 — `Modules/DiceRPG/Controller/DataController.swift:121-131`.
5. **[High] A d4/d20's art variant (A vs G) re-rolls randomly on every SwiftUI re-render**, causing visible flicker unrelated to any actual dice roll — §5.5 — `Modules/DiceRPG/Model/DieModel.swift:70-79`.
6. **[Medium] Compare-value success/failure haptic feedback watches a property a roll never changes**, so it never fires — §5.6 — `Modules/DiceRPG/Game/Detail/DiceGameActionBar.swift:47-49`.
7. **[Medium] Uncancelled per-rotation reset `Task` can race and clobber a newer roll's animation state** — §3.1 — `Modules/DiceRPG/Game/Detail/DieViewerView.swift:54-65`.
8. **[Medium] `PreviewData.swift`'s fixture data (hundreds of lines) compiles unconditionally into every Release build** on every platform — §9.10 — `Modules/DiceRPG/Model/PreviewData.swift`.
9. **[Medium] `RawDieCounter.roll()` traps with an invalid range for "0dN" dice notation** — §5.7 — `Modules/DiceRPG/Model/RawDieCounter.swift:29-36`.
10. **[Medium] Double-localization no-op (`.localizedString` chained after `String(localized:bundle:)`) at 20 call sites** — §9.2 — `Modules/DiceRPG/Controller/EditController.swift` + 4 editor files.

---

## 2. Quick wins (≤30 min each)

- **Fix "Cthuhlu" → "Cthulhu"** — `Modules/DiceRPG/Model/PreviewData.swift:181`. §9.14.
- **Rename `resultCategopry` → `resultCategory`** (4 sites) — `GameController.swift:321,329`, `LinkController.swift:22`, `DiceInline.swift:113`. §9.11.
- **Rename `reset(modifer:)` → `reset(modifier:)`** — `EditController.swift:97` + 2 call sites. §9.12.
- **Rename `roleDice`/`roleShareTitle`/`roleAndShareDiceResult` → `roll…`** — `DiceRoll.swift:49`, `DiceInline.swift:107,111`. §9.13.
- **Switch `DiceModel.filter` to `localizedStandardContains`** to match the house rule and `DiceEntityQuery`'s already-correct search — `DiceModel.swift:542-546`. §4.1.
- **Delete dead `DiceFactory.diceImage(for:result:)`** — `DiceFactory.swift:15-18`, unreferenced repo-wide. §9.1.
- **Delete dead `DiceEntity.sharePreview`** — `DiceEntity.swift:195-199`, unreferenced repo-wide. §9.1.
- **Strip the 20 redundant `.localizedString` calls** after `String(localized:bundle:)` — see §9.2 for the full site list.
- **Move or delete the stray `Intent/IOS18_OPTIMIZATIONS.md`** planning doc, which describes files/behavior that were never actually built this way. §9.1.

---

## 3. Concurrency

### 3.1 Uncancelled reset `Task` spawned per rotation change
- **Location:** `Modules/DiceRPG/Game/Detail/DieViewerView.swift:54-65`
- **What:** `.onChange(of: die.rotation, initial: true)` spawns a new `Task { @MainActor in try? await Task.sleep(for: .60s); ...resetDie... }` on every nonzero rotation change, with no stored task handle to cancel a prior in-flight instance.
- **Why:** A rapid sequence of rolls can queue up multiple concurrent 0.6s-delayed reset tasks racing to call `resetDie` — the exact failure mode `GameController`'s own `diceUpdateWidgetTask` (`GameController.swift:20-23`) is explicitly documented and designed to avoid ("so a rapid sequence of rolls can't queue up out-of-order... updates"). Here the same hazard exists unguarded.
- **Action:** Store the `Task` in `@State` and cancel the previous one before starting a new one, mirroring the pattern already used in `GameController.roll(die:for:)`.
- **Severity:** Medium

### 3.2 `nonisolated` conformances on `@MainActor` `DiceModel` rely on a runtime-trapping escape hatch
- **Location:** `Modules/DiceRPG/Model/DiceModel.swift:395-401` (`Comparable <`), `406-441` (`merge`), `443-484` (`isSame`), `507-517` (`duplicate`), `680-686` (`==`); helper at `Modules/CoreRPG/Concurrency/MainActorIsolationAssumption.swift:19-21`
- **What:** `DiceModel`'s `nonisolated` `Comparable`/`ItemDiffComparable`/`ItemDuplicatable`/`Equatable` conformances all funnel through `assumeMainActorIsolated`, which calls `MainActor.assumeIsolated` — a runtime assertion, not a compile-time guarantee.
- **Why:** If any generic infrastructure (e.g. `Array.sorted()`, `Set`/`Dictionary` machinery, Codable) ever invokes one of these off the main actor, the app traps instead of failing to compile. `DiceModel`'s own sibling, `DiceSnapshot`, deliberately avoids this pattern ("no actor hop, no traps" — `DiceSnapshot.swift:229`).
- **Action:** Keep `DiceModel` (as opposed to `DiceSnapshot`) call sites restricted to MainActor-only contexts; consider centralizing/auditing use of `assumeMainActorIsolated` rather than relying on convention alone.
- **Severity:** Medium

### 3.3 Inconsistent off-main handling between the two roll-triggered widget-config write paths
- **Location:** `Modules/DiceRPG/Intent/RollSpecificDiceIntent.swift:38-45` vs. `Modules/DiceRPG/Controller/GameController.swift:607-626` (`diceUpdateWidget`)
- **What:** `GameController.diceUpdateWidget` deliberately moves the widget-config JSON-encode + `UserDefaults` write to `Task.detached(priority: .utility)` to keep I/O off the main thread (per its own inline comment). `RollSpecificDiceIntent.perform()`, a `@MainActor` function invoked via Siri, does the identical encode/write synchronously on the main actor instead.
- **Why:** The UI-roll and Siri-roll paths write the same App-Group-shared config independently and without coordination — today a benign "last write wins," but the Siri path blocks its main actor on file I/O that the other path goes out of its way to avoid, and future changes could turn the race into something less benign.
- **Action:** Route `RollSpecificDiceIntent`'s widget-config update through the same off-main path `GameController` uses.
- **Severity:** Low

---

## 4. API modernity

### 4.1 `localizedCaseInsensitiveContains` instead of the house-mandated `localizedStandardContains`
- **Location:** `Modules/DiceRPG/Model/DiceModel.swift:542-546` (`filter(filter:includeEntries:)`)
- **What:** `name.localizedCaseInsensitiveContains(filter) || description.localizedCaseInsensitiveContains(filter)` is used for the in-app list-search predicate.
- **Why:** CLAUDE.md mandates `localizedStandardContains()` for user-input filtering. It's also inconsistent within the same module: `DiceEntityQuery.matches(model:text:)` (`Intent/DiceEntity.swift:137-141`) correctly uses `localizedStandardContains` for the same kind of search, so Spotlight/Siri search and the in-app list filter can now disagree on which items match (e.g. diacritic sensitivity differs).
- **Action:** Change both calls in `DiceModel.filter` to `localizedStandardContains`.
- **Severity:** Low

### 4.2 `WIDGET_EXTENSION` compilation flag is documented but never actually defined
- **Location:** `Modules/DiceRPG/Widget/DiceConfiguration.swift` (guards only with `#if !os(tvOS)`); confirmed repo-wide that `WIDGET_EXTENSION` appears only in `CLAUDE.md`/`AGENTS.md`/`Docu/Architecture.md`/Scripts, never in `project.pbxproj`'s `SWIFT_ACTIVE_COMPILATION_CONDITIONS` nor in any `.swift` file
- **What:** `CLAUDE.md` states "Widget extension code uses `#if !WIDGET_EXTENSION` to exclude unavailable APIs," but no Xcode target defines this Swift compilation condition, and no file in the repo uses it.
- **Why:** `#if !WIDGET_EXTENSION` with the symbol undefined always evaluates true, including inside the actual widget extension target — so if this convention were ever relied on to gate an extension-unavailable API, it would silently fail to exclude anything.
- **Action:** Either wire a real `WIDGET_EXTENSION` custom compilation condition onto the `DiceRollerWidgetExtension` target and use it where needed, or correct the stale convention in `CLAUDE.md`/`AGENTS.md`.
- **Severity:** Medium

### 4.3 Hardcoded `"gamerpg://"` URL literals bypass the canonical scheme/token helpers
- **Location:** `Modules/DiceRPG/Intent/DiceIntents.swift:34,52`; compare canonical form at `Modules/DiceRPG/Intent/DiceEntity.swift:110-112` (`"RPG://DICE/0/\(id)"`, explicitly commented as needing to stay hand-kept in sync with `URL.appScheme` and `NetworkModules.dice.token`)
- **What:** `RollDiceIntent`/`ShowDiceHistoryIntent` build deep-link URLs with a hardcoded, different scheme/host literal than the one used everywhere else in the module. This is the root cause of §5.2's functional break.
- **Why:** No test verifies these two literals (unlike the sibling literal, which has `DiceEntityURLRepresentationTests`), so scheme drift goes uncaught.
- **Action:** Route these two intents through `URL.appScheme`/`NetworkModules.dice.token` instead of separate literals — see §5.2 for the full fix.
- **Severity:** Medium

### 4.4 `AnyView` used for cross-module view type-erasure
- **Location:** `Modules/DiceRPG/Controller/ViewController.swift:14-24` (`thumbnailRowView(for:)` ×2, `rowViewer(source:destination:)`)
- **What:** Three `ViewControllable` protocol witnesses return `AnyView(...)`.
- **Why:** CLAUDE.md says to avoid `AnyView` unless "absolutely required." It looks structurally necessary here — `ViewControllable` is a cross-module protocol whose concrete views differ per module, and `View.Body` prevents a plain `any View` existential from working — but it's worth a second look at whether a generic dispatcher could reach an opaque `some View` instead.
- **Action:** Check with the `ViewControllable` protocol definition in CoreRPG whether a non-type-erased alternative is feasible; if not, this is an accepted, necessary use.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Infinite loop / app hang when reroll options cover every face of a die
- **Location:** `Modules/DiceRPG/Model/DieModel.swift:143-149` (the loop); `Modules/DiceRPG/Controller/EditController.swift:69-74` (`add(reroll:)` — no validation preventing full coverage); `Modules/DiceRPG/Dice/RerollEditor.swift` (editor UI has no guard either)
- **What:** `roll(resetResults:rerollOptions:)` does:
  ```
  repeat { roll = die.roll(); rollResult.append(roll) }
  while rerollOptions.contains(where: { $0.number == roll })
  ```
  with no iteration cap, and nothing anywhere in the add/edit path (`EditController.add(reroll:)`, `RerollEditor`) stops a user from adding a reroll entry for every face of a die (e.g. four reroll rules on a d4 covering 1, 2, 3, 4 — each entry is independently appended with no dedup or coverage check).
- **Why:** Once every face is covered, the `while` condition is always true. This loop runs synchronously on `@MainActor`, invoked directly from the "Roll dice" button and `DiceRoll`'s per-die button (`GameController.roll(die:for:)`), so it freezes the UI permanently and grows `rollResult` unboundedly until the OS kills the app. **Verified**: read `DieModel.swift:143-149`, `RerollEditor.swift` (no cap on the number or range of reroll entries a user can add), and `EditController.swift:69-74` (unconditionally appends).
- **Action:** Cap reroll attempts (e.g. bail out after N tries, or once `rerollOptions` covers the die's full face range) and/or prevent the editor from letting reroll options cover every possible value.
- **Severity:** Critical

### 5.2 Siri/Shortcuts "Roll Dice" and "Show Dice History" are non-functional
- **Location:** `Modules/DiceRPG/Intent/DiceIntents.swift:31-40` (`RollDiceIntent.perform()`), `50-58` (`ShowDiceHistoryIntent.perform()`); registered via `Modules/DiceRPG/Intent/DiceShortcutCatalog.swift:71-93` (`rollD20`, `rollD6`) and `95-105` (`history`)
- **What:** Both intents build a URL with scheme `"gamerpg://..."` and open it via `OpenURLIntent`. The app's only registered scheme is `"RPG"` (`Modules/CoreRPG/App/URL+ItemId.swift:6`, `URL.appScheme`) — **verified**: repo-wide grep confirms `"gamerpg"` appears nowhere else, and no Info.plist declares it. `ShowDiceHistoryIntent` additionally targets `dice/0/history`, but `DiceRoute` never parses a "history" token — only `detail/<uuid>`.
- **Why:** These are `isDiscoverable = true` App Intents wired to real Siri phrases ("Roll a D20 in MasterRPG", "What was my last roll in MasterRPG" — confirmed in `DiceShortcutCatalog.swift:71-105`). Invoking them opens an unresolvable URL scheme; the shortcut silently does nothing.
- **Action:** Either implement these for real (reuse `RollSpecificDiceIntent`'s pattern of calling `GameController`/`DiceRootModel` directly and returning a snippet/dialog) or remove them from `DiceShortcutCatalog` until fixed.
- **Severity:** High

### 5.3 Reroll/Coup/Fumble editors validate against the wrong range for multi-die pools
- **Location:** `Modules/DiceRPG/Dice/RerollEditor.swift:124,156`; `Modules/DiceRPG/Dice/SpecialValueEditor.swift:123` (shared by `CoupEditor.swift`/`FumbleEditor.swift`); contrast the correct pattern at `Modules/DiceRPG/Dice/SpecialOptionEditor.swift:55`
- **What:** These three `TextIntEditor` fields constrain the trigger/replacement value with `range: model.minValue...model.maxValue` (`DiceModel.swift:378-384`) — the **sum across every die in the pool** — instead of `model.minFirstValue...model.maxFirstValue` (`DiceModel.swift:386-392`, a single die's range), which `SpecialOptionEditor` already uses correctly for the analogous "Add Dice Every" field. **Verified** by reading all four sites.
- **Why:** Reroll/coup/fumble "number" values are matched per individual die result (`GameController.resolvedDiceValue`/`matchesSpecialValue` compare against each die's own result, capped at that die's max). For any pool with more than one die, `minValue` (sum of minimums) exceeds 1, so a user literally cannot configure the extremely common "reroll/fumble on a natural 1" rule — the picker's lower bound excludes 1. The upper bound similarly allows picking a per-die trigger value that can never occur on any single die.
- **Action:** Use `model.minFirstValue...model.maxFirstValue` for these three fields.
- **Severity:** High

### 5.4 Dice color/skin (and per-die identity) silently lost on every Core Data round trip
- **Location:** `Modules/DiceRPG/Controller/DataController.swift:29` (persist path uses only `die.text`), `57-59` (`model.dice = snapshot.dice.map { $0.die.text }.joined(separator: ",")`), `121-131` (`dice(from:)` reconstructs `DieModel(id: UUID(), die: RawDie(text: $0))`); `Modules/DiceRPG/Model/RawDie.swift:74-76` (`text` only encodes `"d<sides>"`)
- **What:** `RPGDice.dice` is persisted as a plain comma-joined string of `RawDie.text` values. Reloading reconstructs each die with a **new random UUID** and the default `color: .Random`, discarding whatever `DieModel.color`/`rotation`/`displayState` was before saving. **Verified** by reading `DataController.swift` end to end.
- **Why:** `View/DiceBag.swift` lets a user pick an "A" or "G" art skin for a d4/d20. That choice never survives an app relaunch or a CloudKit merge that re-maps the Core Data object into a fresh snapshot — the die silently reverts to `.Random`, which then (per §5.5) re-randomizes on every render.
- **Action:** Persist color (and any other worth-keeping `DieModel` fields) alongside sides in the stored string, or promote to a small per-die Core Data attribute; keep a stable `id` if text round-tripping is retained.
- **Severity:** High

### 5.5 Die art variant re-randomizes on every SwiftUI re-render
- **Location:** `Modules/DiceRPG/Model/DieModel.swift:70-79` (`name(for:)`), consumed directly from `Modules/DiceRPG/Game/Detail/DieViewerView.swift:20` (`die.diceImage(for: die.result.last ?? die.die.max)`)
- **What:** For d4/d20 dice with `color == .Random` (the default), `name(for:)` calls `RawDie(.number(2)).roll()` on every invocation to pick between the "A"/"G" art variant. It's a computed property read directly from `DieViewerView.body`. **Verified** by reading both files.
- **Why:** Every SwiftUI re-render of that die (animation ticks, unrelated parent state changes) can flip which art variant is shown — visible flicker completely independent of any actual dice roll.
- **Action:** Resolve the A/G variant once (e.g. at `DieModel` creation) and store it instead of re-rolling on every property access.
- **Severity:** High

### 5.6 Compare-value success/failure haptic feedback watches the wrong property
- **Location:** `Modules/DiceRPG/Game/Detail/DiceGameActionBar.swift:47-49`
- **What:** `.onChange(of: root.gameController.gameItem(for: itemId).entries) { diceRollResult = root.gameController.result(itemId: itemId).checked }`, feeding `.sensoryFeedback(diceRollResult ? .success : .error, trigger: diceRollResult)`.
- **Why:** A dice roll mutates `DiceModel.dice`, never `.entries` (a separate cross-reference field for Core Data child entries). Since `.entries` never changes on a roll, this `onChange` essentially never fires from an actual roll, so the haptic feedback for a compare-value check silently never triggers.
- **Action:** Watch `root.gameController.gameItem(for: itemId).dice` (or another roll-result signal) instead of `.entries`.
- **Severity:** Medium

### 5.7 `RawDieCounter.roll()` traps for "0dN" dice notation
- **Location:** `Modules/DiceRPG/Model/RawDieCounter.swift:29-36` (`roll()`), reachable via `RawDieCounter.init(text:)` (parses any regex-matched `"<count>d<sides>"` substring, including `"0d6"`)
- **What:** `(1 ... abs(count)).forEach { ... }` — when `count == 0` this constructs `1...0`, an invalid `ClosedRange` that traps at runtime. **Verified**: for input text `"0d6"`, the regex captures `Count = "0"`, `Int("0") = 0`, `count = 0`, and `roll()` then builds `1...0`.
- **Why:** `RawDieCounter(text:)` is `public` and reachable from any dice-notation text parsed elsewhere in the app (formulas or imported/linked content that could plausibly contain a "0d6" typo or template artifact). Calling `.roll()` on such a counter crashes.
- **Action:** Guard `count != 0` before building the range (e.g. `guard count != 0 else { return 0 }`).
- **Severity:** Medium

### 5.8 Silent failure of the in-game "share result" link action
- **Location:** `Modules/DiceRPG/Controller/LinkController.swift:26-31`
- **What:** `Task { if let shareResult, let result = try? await gameController.createGameData(...) { shareResult.networkActions?.game(result, .show, nil) } }` — `try?` discards any thrown error with no fallback or user feedback.
- **Why:** If `createGameData(for:resultCategory:)` throws, tapping "share" on a dice entry during a live game silently does nothing, with no indication to the GM that the send failed.
- **Action:** Log the error and/or surface a user-facing failure indicator instead of swallowing it via `try?`.
- **Severity:** Medium

### 5.9 `RootDiceOverlay.hideDice` parameter is plumbed through but has no effect (currently harmless)
- **Location:** `Modules/DiceRPG/Game/RootDiceOverlay.swift:7-21`; `Modules/DiceRPG/Controller/ViewController.swift:77-80`; `Modules/GameRPG/GameViews/OverlayGameLayout.swift:50-51`
- **What:** `RootDiceOverlay.body` never reads its stored `hideDice` property — it always passes a hardcoded `hideOwnDice: valueFor(iOS: false, macOS: false, tvOS: false, visionOS: true)` to `DiceOverlay`.
- **Why:** **Verified and demoted from an initial "live bug" claim**: the only production call site, `OverlayGameLayout.swift:50-51`, already gates rendering with `if !hideDice && gameScreenModel.showDice { ...overlayGameView(hideDice:)... }` — so `RootDiceOverlay` is only ever instantiated when `hideDice == false` in practice. The parameter is dead/vestigial, not a currently-observable functional bug. It would become a live bug if that outer guard were ever loosened.
- **Action:** Either wire `hideDice` into the `hideOwnDice:` argument, or remove the parameter end-to-end (from `ViewController.overlayGameView` and `RootDiceOverlay`) since it does nothing today.
- **Severity:** Low

---

## 6. Security

_No findings._ Repo-wide grep for `Bearer`/`apiKey`/`secret`/`Authorization`/hardcoded tokens returned nothing in this module. All disk/App-Group writes go through `UserDefaults(suiteName: UserDefaults.appGroupString)` consistently with the documented App Group (`group.de.andretrettin.MasterRPG`); no over-broad file-system or entitlement usage was found in DiceRPG's own code. The Core Data model was checked against the project's CloudKit rule (every non-optional attribute has a default; both relationships — `RPGDice.entries`, `RPGDiceEntry.die` — are `optional="YES"`) and is compliant.

---

## 7. Performance

### 7.1 `DiceConfiguration.availableDice` is serialized on every roll but never read back
- **Location:** `Modules/DiceRPG/Widget/DiceConfiguration.swift:182-217`
- **What:** `availableDice: [DieModel]` is set at construction and round-trips through `Codable`/`UserDefaults` on every `save()` (called on every roll via `GameController.roll`), but repo-wide grep shows no code ever reads `config.availableDice` back afterward.
- **Why:** Wasted encode/decode + `UserDefaults` I/O on every single dice roll, and a dead field that misleads readers into thinking a widget dice-picker consumes it.
- **Action:** Either wire it into an actual widget dice-picker UI, or remove the property from `DiceConfiguration`.
- **Severity:** Medium

### 7.2 `DiceBag` "add die" catalogs rebuild with new identities on every render
- **Location:** `Modules/DiceRPG/View/DiceBag.swift:9-10`
- **What:** `diceBagA`/`diceBagG` are instance (not `static`) properties built from `.die4(color:)`/`.die20(color:)` etc., each of which internally generates a new `UUID()`. Since `DiceBag` is a `struct View` re-initialized on every parent redraw, these fixed catalog arrays — and the `Identifiable` ids `ForEach` uses — are rebuilt with fresh ids each time.
- **Why:** Unnecessary allocation plus SwiftUI identity churn on a view that sits inside the frequently-updated dice editor; any parent redraw invalidates every "add die" button's identity, which can interrupt in-flight animations/gesture state.
- **Action:** Make `diceBagA`/`diceBagG` `static let` since they represent a fixed catalog, not per-instance data.
- **Severity:** Low

### 7.3 Every roll performs two separate encode+`UserDefaults` writes of overlapping data
- **Location:** `Modules/DiceRPG/Widget/DiceConfiguration.swift` — `DiceConfiguration.save()` unconditionally also calls `DiceWidgetSnapshot(configuration: self).save()`
- **What:** The widget maintains its own slimmed-down mirror structs (`DiceWidgetDice`/`DiceWidgetRoll`/`DiceWidgetSnapshot`) that are derived from and persisted alongside the full `DiceConfiguration` on every single roll. See §9.19 for the duplication angle; this is the runtime-cost angle.
- **Why:** Doubling the JSON encode + shared-container write work per roll is measurable overhead on a hot, latency-sensitive path (the roll button), even though the underlying duplication is largely a deliberate "compact widget snapshot" design.
- **Action:** No urgent action given the documented rationale; consider deriving `DiceWidgetSnapshot` lazily inside the widget process instead of persisting it redundantly from the app process on every roll.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 Manual Reduce-Motion ceremony repeated ~26 times with no shared helper
- **Location:** (26 call sites across 16 files) `Dice/RerollEditor.swift:47,68`; `Dice/SpecialValueEditor.swift:72,132`; `Game/DiceOverlay.swift:30,33`; `Game/Detail/DiceGameActionBar.swift` (7×); `Game/RootDiceOverlay.swift:17`; `Game/Detail/DiceFocusResult.swift:15`; `Game/Detail/DieViewerView.swift:49,53,60`; `Game/Detail/DiceGameResult.swift:28,31`; `Game/Detail/DicePlayerRoot.swift:14`; `Game/Detail/DiceFocusActionBar.swift:15`; `Game/Editor/DiceInlineEditor.swift:44`; `Game/Detail/DiceFocusRoll.swift:28`; `View/DropChooseView.swift:38`; `View/DiceViewer.swift:19`; `View/DiceInline.swift:24,42,74,98,112`; `View/DiceBag.swift:32` — each paired with its own `@Environment(\.accessibilityReduceMotion)` declaration
- **What:** Every view re-derives `withAnimation(reduceMotion ? nil : .someAnimation)` by hand instead of using a shared helper; none exists in CoreRPG either.
- **Why:** With 26 hand-copied instances, a single missed site silently violates the app's own Reduce-Motion accessibility support, and there's no single place to fix a bug in the pattern.
- **Action:** Add a small CoreRPG helper (e.g. a `View.withReducedMotionAnimation(_:)` modifier or a free function taking `reduceMotion`) and migrate call sites incrementally. This is a cross-module change since CoreRPG is shared — see §10.
- **Severity:** Medium

### 8.2 Triplicated "focused dice" state-tracking boilerplate
- **Location:** `Modules/DiceRPG/Game/Detail/DiceFocusActionBar.swift:6-20`, `DiceFocusResult.swift:6-20`, `DiceFocusRoll.swift:19-33`
- **What:** All three views declare the identical shape — `@Environment(DiceRootModel.self)`, `@Environment(\.accessibilityReduceMotion)`, `@State private var itemId = UUID()`, and an identical `.onChange(of: root.gameController.gameModel.focusItemIds, initial: true) { withAnimation(...) { itemId <=> ...first ?? UUID() } }` — wrapping a different child view each time.
- **Why:** The same 10-15 lines of state-sync plumbing tripled; any change to how "focused dice" is tracked requires touching all three files identically.
- **Action:** Extract a small generic wrapper (e.g. `FocusedDiceContainer<Content: View>(content: (UUID) -> Content)`) that owns the `itemId` state + `onChange`, reducing all three call sites to one-liners.
- **Severity:** Medium

### 8.3 Magic layout constants without named constants
- **Location:** `Modules/DiceRPG/Controller/ViewController.swift:99-122` (`82.0`, `36.0`, `112`, `56`, `20`); `Modules/DiceRPG/Game/Detail/DicePlayerRoot.swift:34` (`-200` offset)
- **What:** `height(for:)`/`gameDiceHeight`/`width(for:)` hardcode base row height, per-extra-result-row height, and per-platform width values with no named constants or derivation comments. `DicePlayerRoot` hardcodes a `-200` slide-offset for hiding player dice off-screen.
- **Why:** These numbers encode a real UI contract (row heights matching `DieViewerView`'s 44pt circle + spacing) that will silently drift if that sizing ever changes, since nothing ties the two together. Contrast with `GameController.localRollStartDelay`/`diceSoundVolume`, which are already named constants in this same module — good precedent to extend.
- **Action:** Promote to named `static let` constants alongside the existing well-named-constants pattern.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Files/symbols to delete outright
- `Modules/DiceRPG/Intent/IOS18_OPTIMIZATIONS.md` (425 lines) — a stray planning doc inside a source folder describing files (`DiceShortcuts.swift`, `DiceRollerIntents.swift`) that don't exist and features (haptic feedback, invalidatable snippet content for dice history) never implemented; appears to be the origin of the broken intents in §5.2/§4.3. Move to `Docu/` or delete.
- `Modules/DiceRPG/Root/DiceFactory.swift:15-18` — `DiceFactory.diceImage(for:result:)`, unreferenced repo-wide (all real call sites use the instance method `DieModel.diceImage(for:)`).
- `Modules/DiceRPG/Intent/DiceEntity.swift:195-199` — `sharePreview` computed property, unreferenced by any `ShareLink` or other call site.
- **Severity:** Low (cleanup; small LOC removed)

### 9.2 Redundant double-localization call, 20 occurrences
- **Locations:** `Modules/DiceRPG/Controller/EditController.swift:15,22,37,44,59,66,73,80,88,94,100,106` (12 occurrences); `Dice/CoupEditor.swift:17`; `Dice/FumbleEditor.swift:17`; `Dice/DiceOptionEditor.swift` (2); `Dice/SpecialOptionEditor.swift` (2); helper at `Resources/Localization+Extensions.swift:11-15`
- **What:** Every call site does `String(localized: "...", bundle: .module).localizedString` — `String(localized:bundle:)` already resolves the string, then `.localizedString` re-runs `Bundle.module.localizedString(forKey: self)` using that *already-resolved* text as the lookup key. **Verified**: read `Localization+Extensions.swift` — the helper is exactly `Bundle.module.localizedString(forKey: self, value: nil, table: nil)`.
- **Why:** Once resolved to (e.g.) German text, using that text as a String Catalog key won't match any key, so the second call silently falls back to returning its input unchanged — a no-op that wastes a bundle lookup and confuses readers into thinking it does something.
- **Action:** Drop `.localizedString` from all 20 call sites; delete the now-unused `String.localizedString`/`Bundle.localizedString(forKey:)` helpers if nothing else uses them.
- **Severity:** Medium

### 9.3 Duplicated coup/fumble add/remove method pairs
- **Locations:** `Modules/DiceRPG/Controller/EditController.swift:25-45` (`add(coup:)`/`remove(coup:)`) vs. `:47-67` (`add(fumble:)`/`remove(fumble:)`)
- **What:** Two structurally identical 10-line method pairs differing only in which `DiceModel` property/message they touch.
- **Why:** Any future third "special value" bucket, or a bugfix to the shared logic, must be hand-copied to both.
- **Action:** Factor into one generic helper parameterized by `WritableKeyPath`s for the values array and the "only on first die" flag, plus the localized message.
- **Severity:** Medium

### 9.4 Duplicated onChange→reset sync blocks in `DiceOptionEditor`
- **Location:** `Modules/DiceRPG/Dice/DiceOptionEditor.swift:42-76`
- **What:** The three `.onChange(of: model.modifier/.compareValue/.compareOption)` handlers each duplicate one of the three blocks already in `syncAllEditModels()`, verbatim.
- **Why:** The same sync logic exists in two places in one file; a fix to one property's sync logic must be applied twice.
- **Action:** Have each `.onChange` handler call the corresponding single-property line inside `syncAllEditModels()`.
- **Severity:** Low

### 9.5 Duplicated `resultColor(for:)` helper
- **Location:** `Modules/DiceRPG/Game/Detail/DiceRoll.swift:43-47` and `Modules/DiceRPG/Game/Detail/DicePlayer.swift:119-123`
- **What:** Both implement an identical-bodied lookup (`root.gameController.diceSuccess(for:).first(where: { $0.0 == dieId })?.1 ?? []`).
- **Action:** Move to a single `GameController.resultColor(for:itemId:)` helper and have both views call it.
- **Severity:** Low

### 9.6 `DieModel` — 7 near-identical pairs of static color-variant factories
- **Location:** `Modules/DiceRPG/Model/DieModel.swift:160-215`
- **What:** Each die size (`die2` through `die20`) repeats a two-line `static var dieN` + `static func dieN(color:)` pattern — 56 lines of boilerplate.
- **Action:** Replace with a single generic `static func die(_ sides: RawDie.Sides, color: ColorCode = .Random) -> DieModel`, optionally keeping a couple of the most-used named shortcuts for call-site readability.
- **Severity:** Low

### 9.7 `RawDie.roll(_:)` duplicates `roll()` instance-method body
- **Location:** `Modules/DiceRPG/Model/RawDie.swift:8-10` vs. `:62-64`
- **What:** `static func roll(_ sides: Sides) -> Int` and `func roll() -> Int` have byte-identical bodies (`Int.random(in: 1 ... sides.number())`).
- **Action:** Have the instance method call the static one: `func roll() -> Int { Self.roll(sides) }`.
- **Severity:** Low

### 9.8 `DiceModel`/`DiceSnapshot` — fully duplicated init/CodingKeys/Codable boilerplate (accepted pattern, flagged as refactor candidate)
- **Location:** `Modules/DiceRPG/Model/DiceModel.swift:13-88,624-678` vs. `Modules/DiceRPG/Model/DiceSnapshot.swift:38-67,147-227`
- **What:** Both types carry the same 22-field `CodingKeys` enum and near-identical encode/decode bodies — intentionally, per the file's own doc comment, so the wire format and stored configuration stay byte-compatible.
- **Why:** Deliberate MainActor-model / Sendable-snapshot-twin architecture, repeated across the module — but every field addition requires four manual, compiler-unenforced updates in lockstep.
- **Action:** No behavior change recommended; consider a lightweight shared "field list" mechanism if the team later adopts Swift macros here.
- **Severity:** Low

### 9.9 Oversized files (>500 LOC)
- **`Modules/DiceRPG/Model/DiceModel.swift` (691 lines)** — mixes the core class + inits (1-90), nested `CompareValue`/`CoupFumbleOption`/`RerollOption` types (128-297), computed-helpers extension (319-393), `Comparable`/`ItemDiffComparable` (395-485), `ItemDuplicatable` (507-518), `ItemDataAccessable` (520-621), `Codable` (623-678), `Equatable`/`Hashable` (680-691). Split along these existing extension boundaries into `DiceModel+Options.swift`, `DiceModel+Diffing.swift`, `DiceModel+ItemDataAccessable.swift`, `DiceModel+Codable.swift`.
- **`Modules/DiceRPG/Controller/GameController.swift` (627 lines)** — already has clear internal `// MARK:` boundaries (`DiceGameModel`/`DiceGameStorable` protocol, "Player Dice" extension at 248-291, roll/sound logic at 293-386, and a ~240-line "Dice Result" calculation extension at 388-627 with no UI/persistence side effects, a good standalone-testable-file candidate). Split into `GameController+PlayerDice.swift`, `GameController+Rolling.swift`, `GameController+Result.swift`.
- **Severity:** Medium (both — size alone doesn't break anything, but both hinder navigation and raise merge-conflict surface)

### 9.10 `PreviewData.swift` fixture data compiles unconditionally into Release builds
- **Location:** `Modules/DiceRPG/Model/PreviewData.swift:7-73` (unconditional), `:47-60` (only the import `Task` is `#if DEBUG`-gated), `:62-72` (`testRoot()` is fully `#if DEBUG`-gated)
- **What:** Most of this file — several hundred lines of fixture `DiceModel`/`DieModel`/`DiceRootModel.preview` data with hardcoded UUIDs — compiles into every build configuration and platform target, Debug and Release alike.
- **Why:** This is SwiftUI-Preview/test-fixture-only data with zero runtime benefit to end users, yet ships in the Release App Store binary as dead static data. `DiceRootModel.preview` is a `public static let`, which the linker may retain if anything is transitively reachable from a Release code path.
- **Action:** Gate the file's non-widget-facing content behind `#if DEBUG`; verify with a Release build + `strings`/`nm` check that the remaining symbols are actually stripped.
- **Severity:** Medium

### 9.11 Misspelled parameter `resultCategopry`, 4 sites
- **Location:** `Modules/DiceRPG/Controller/GameController.swift:321,329`; `Modules/DiceRPG/Controller/LinkController.swift:22`; `Modules/DiceRPG/View/DiceInline.swift:113`
- **What:** Consistently misspelled across its declaration and all 3 call sites.
- **Action:** Rename to `resultCategory` at all 4 sites — internal parameter name only, safe refactor.
- **Severity:** Low

### 9.12 Misspelled parameter `modifer`
- **Location:** `Modules/DiceRPG/Controller/EditController.swift:97`; call sites `Modules/DiceRPG/Dice/DiceOptionEditor.swift:48,68`
- **What:** `reset(modifer:)` instead of `reset(modifier:)` (the property it writes, `item.modifier`, is spelled correctly).
- **Action:** Rename `reset(modifer:)` → `reset(modifier:)` and update both call sites.
- **Severity:** Low

### 9.13 "role" vs "roll" naming typo, 3 symbols
- **Location:** `Modules/DiceRPG/Game/Detail/DiceRoll.swift:49` (`roleDice`); `Modules/DiceRPG/View/DiceInline.swift:107` (`roleShareTitle`), `:111` (`roleAndShareDiceResult`)
- **Action:** Rename to `rollDice`/`rollShareTitle`/`rollAndShareDiceResult`.
- **Severity:** Low

### 9.14 "Cthuhlu" spelling in preview data
- **Location:** `Modules/DiceRPG/Model/PreviewData.swift:181`
- **What:** `"This is a dice for Call of Cthuhlu."` — should be "Cthulhu".
- **Action:** Fix spelling.
- **Severity:** Low

### 9.15 `ViewController.gameView(root:)` ignores its `root` parameter
- **Location:** `Modules/DiceRPG/Controller/ViewController.swift:51-53`
- **What:** `func gameView(root: DiceRootModel) -> some View { LinkRootView(...) }` never reads `root`.
- **Why:** Already flagged for sibling modules (`Docu/CODE_AUDIT_Audio.md` notes PdfRPG's and DiceRPG's `gameView(root:)` are identical modulo parameter type) but left unfixed here.
- **Action:** Either use `root` meaningfully or drop the parameter from the `GameControllable` protocol requirement — coordinate with sibling modules before doing this alone, since it's a cross-module protocol change.
- **Severity:** Low

### 9.16 `DiceQuickEditor` row-button subviews are near-duplicates
- **Location:** `Modules/DiceRPG/Game/Editor/DiceQuickEditor.swift:89-111`
- **What:** `DiceQuickEditorRowMinusButtonsView`/`DiceQuickEditorRowPlusButtonsView` are identical except for the literal array (`[10,5,2,1]` vs `[1,2,5,10]`) and one `isAddition` bool.
- **Action:** Merge into one `DiceQuickEditorRowButtonsView(values:isAddition:)`.
- **Severity:** Low

### 9.17 _REMOVED: false positive — `DieModel.name`'s setter is protocol-required, not dead_
- **Location:** `Modules/DiceRPG/Model/DieModel.swift:65-68`
- **What it looked like:** `public var name: String { get { name(for: 1) } set {} }` — a no-op setter that seemed removable since no call site assigns to it.
- **What it actually is:** `DieModel: EntryDataAccessable` (CoreRPG) requires `var name: String { get set }` for types whose entries support renaming via the shared list-editing UI. A die has no free-text name of its own, so the no-op setter is the correct implementation — the same pattern already used one property below it, `content`. Removing the setter breaks the protocol conformance (confirmed by an actual build failure: "Type 'DieModel' does not conform to protocol 'EntryDataAccessable'").
- **Outcome:** Reverted after applying and rebuilding; left as originally written, now with a comment explaining why it's intentional.

### 9.18 Two near-identical JSON+UserDefaults persistence blocks in `DiceConfiguration.swift`
- **Location:** `Modules/DiceRPG/Widget/DiceConfiguration.swift:161-176` (`DiceWidgetSnapshot.loadFromUserDefaults`/`save`) and `:203-216` (`DiceConfiguration.loadFromUserDefaults`/`save`)
- **What:** Two near-identical pairs of encode/decode + `UserDefaults(suiteName:)` read/write blocks, one per type, in the same file.
- **Action:** Extract a small generic helper (`loadCodable<T: Codable>(key:)` / `saveCodable<T: Codable>(_:key:)`), in this file or CoreRPG.
- **Severity:** Low

### 9.19 `DiceWidgetSnapshot`/`DiceWidgetDice`/`DiceWidgetRoll` duplicate `DiceSnapshot`/`DiceResultModel` shape
- **Location:** `Modules/DiceRPG/Widget/DiceConfiguration.swift:30-177` vs. `Modules/DiceRPG/Model/DiceSnapshot.swift`, `Modules/DiceRPG/Model/DiceResultModel.swift`
- **What:** The widget maintains its own slimmed-down mirror structs, persisted alongside the full models on every roll (see §7.3 for the runtime cost).
- **Why:** Largely necessary — the widget extension can't import the full app-facing model types — but any future field added to `DiceModel`/`DiceSnapshot` needs a matching manual decision about whether the widget mirror needs it too, with no compiler help to catch drift.
- **Action:** No urgent action; consider a comment or test asserting the two stay in sync.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Centralize the Reduce-Motion animation pattern.** §8.1's 26 manual copies of `withAnimation(reduceMotion ? nil : ...)` (with no existing CoreRPG helper) is the clearest repo-wide opportunity in this audit — a single `View` helper or free function would remove an entire class of "forgot to gate this one" accessibility bugs. Since CoreRPG is shared, this should be designed once and adopted by every module, not just DiceRPG.
2. **Range validation for pool-scoped vs. die-scoped values needs a single source of truth.** §5.3 shows `minValue`/`maxValue` (pool sum) and `minFirstValue`/`maxFirstValue` (single die) are easy to confuse at the call site, and three of four editors picked the wrong one. Consider renaming these to something less swappable (e.g. `poolValueRange` vs. `singleDieValueRange`) so the type system/naming steers editors toward the right one.
3. **App Intents that build their own deep-link URLs instead of using `URL.appScheme`/`NetworkModules` tokens will keep drifting.** §4.3/§5.2 is one instance; consider a single `DiceDeepLink` helper (as the module's own code comments already gesture toward) that every intent is required to go through, rather than allowing hand-written URL strings.
4. **The App-Group "load-with-side-effect-write" pattern (§3.3, §7.1, §9.18) suggests the widget-config persistence layer would benefit from a small, tested `AppGroupStore<T: Codable>` abstraction** shared between `DiceConfiguration` and `DiceWidgetSnapshot`, replacing the current pair of hand-rolled encode/decode blocks and clarifying which operations should and shouldn't have write side effects.

---

## 11. What was NOT audited

- Every module other than `Modules/DiceRPG/` — no findings here should be read as commentary on `GameRPG`, `CoreRPG`, `RolePlayGameKit`, or any other module, even where this report cites them for context (e.g. `URL.appScheme`, `OverlayGameLayout`).
- `Tests/DiceRPGTests/` and `Tests/DiceRPGSnapshotTests/` — a quick scan confirmed they exist and reference the files discussed above, but no deep test-coverage review was performed.
- `DiceRollerWidgetExtension` target's Info.plist/entitlements — not opened directly; the App Group identifier usage was checked only via source-level `UserDefaults(suiteName:)` calls, not the entitlements file itself.
- Algorithmic correctness of the dice-notation regex parser (`RawDieCounter`/`RawDice` parsing) beyond the specific `"0dN"` defect found in §5.7 — broader fuzzing of malformed dice-notation strings was not performed.
- Localization string quality/translation correctness — only the localization *mechanism* bug (§9.2) was in scope, not wording.
- Build settings, scheme configuration, or Xcode project structure beyond the DiceRPG target's own compile flags noted in §4.2.
- Performance profiling with Instruments — findings in §7 are based on reading the code for obvious waste, not measured traces.
- The `Resources/Model.xcdatamodeld` was checked only against the CloudKit optionality rule from CLAUDE.md, not for broader schema-design quality.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line.

- **§5.1** — open `Modules/DiceRPG/Model/DieModel.swift`, lines 143-149. Confirm the `repeat`/`while` loop has no attempt counter, then open `Modules/DiceRPG/Controller/EditController.swift:69-74` and `Modules/DiceRPG/Dice/RerollEditor.swift` to confirm nothing stops a user from adding one reroll entry per face value.
- **§5.2** — open `Modules/DiceRPG/Intent/DiceIntents.swift`, lines 34 and 52 (the `"gamerpg://..."` literals), then `Modules/CoreRPG/App/URL+ItemId.swift:6` to see the real scheme is `"RPG"`.
- **§5.3** — open `Modules/DiceRPG/Dice/RerollEditor.swift:124,156` and `Modules/DiceRPG/Dice/SpecialValueEditor.swift:123` (all three use `model.minValue...model.maxValue`), then `Modules/DiceRPG/Model/DiceModel.swift:378-392` to see `minValue`/`maxValue` are pool sums while `minFirstValue`/`maxFirstValue` are the single-die range that `SpecialOptionEditor.swift:55` correctly uses instead.
- **§5.4** — open `Modules/DiceRPG/Controller/DataController.swift`, lines 57-59 and 121-131. Confirm `applySnapshot` writes only `die.text` and `dice(from:)` reconstructs with `UUID()`/default color.
- **§5.5** — open `Modules/DiceRPG/Model/DieModel.swift:70-79` (the `RawDie(.number(2)).roll()` inside `name(for:)`) and `Modules/DiceRPG/Game/Detail/DieViewerView.swift:20` (called directly from `body`).
- **§5.7** — open `Modules/DiceRPG/Model/RawDieCounter.swift:29-36`; trace that `init(text:)` for `"0d6"` sets `count = 0`, then `roll()` builds `1...0`.
- **§5.9** — open `Modules/GameRPG/GameViews/OverlayGameLayout.swift:50-51` to see the `if !hideDice && ...` guard that makes `RootDiceOverlay`'s ignored parameter currently harmless, then `Modules/DiceRPG/Game/RootDiceOverlay.swift:7-21` to confirm the property truly is never read.
- **§9.2** — open `Modules/DiceRPG/Resources/Localization+Extensions.swift:11-15` and any one call site in `EditController.swift` to see the redundant chained call.

If any finding doesn't reproduce when you visit the line, flag it with the specific reference and it'll be re-investigated.
