# Code Audit — ImportControllable / ExportControllable usage

**Scope:** This audit is intentionally narrow, per the request: `Modules/CoreRPG/Controllable/ImportControllable.swift` and `Modules/CoreRPG/Controllable/ExportControllable.swift`, plus every conformer and call site — the ~28 per-module `ImportController`/`ExportController` types (all 14 modules), the shared infra they depend on (`GenericImportController`, `GenericExportController`, `ExportModel`, `RootControllable`, `ItemRootControllable`, `ItemModuleIds`, `ConvertController`, `ImportItemRepair`), the manual-review data model (`ImportReviewModels.swift`, `SingleReviewModels.swift` and its row views), the Fakes used by tests/previews, the SwiftUI surfaces that drive import/export (`AppImportView`, `AppExportView`, `ImportProgressPanelView`, `ExportProgressPanelView`, `ImportRouteDestinationView`), and the game-networking bridge (`GameControllable.createGameData`/`importNetwork`/`updateGame`). This is **not** a full-codebase audit — see §11.

Every file in this list was read directly (not sampled), and a clean `xcodebuild -scheme AdventureRPG clean build` (which pulls in CoreRPG and all leaf modules as dependencies) was run to get ground-truth compiler diagnostics for this code — see §3/§4.

---

## 1. Executive summary

1. **[High] Unbounded allocation from an untrusted per-item size field in the GMZ/GMS binary reader** — §6.1 — `Modules/CoreRPG/Controllable/ImportControllable.swift:748-755`
2. **[High] Export "save file" completion ignores its `Result`, so a cancelled or failed save is reported as a successful export** — §5.1 — `Modules/CoreRPG/FileViews/ExportProgressPanelView.swift:49-51`
3. **[Medium] Every network-triggered import re-scans the full local item list instead of the imported ids** — §7.1 — `Modules/CoreRPG/Controllable/ConvertController.swift:23-27`
4. **[Medium] Dead review-model types left in the public protocol file, superseded by a different implementation with different vocabulary** — §9.1 — `Modules/CoreRPG/Controllable/ImportControllable.swift:13-26`
5. **[Low] Stray character corrupts a diagnostic log string** — §2.1 — `Modules/CoreRPG/Controllable/ExportControllable.swift:157`
6. **[Low] Fake test double force-unwraps with no diagnostic, unlike the real implementation it stands in for** — §2.3 — `Modules/CoreRPG/Fake/FakeExportController.swift:14-17`

---

## 2. Quick wins

### 2.1 Stray `)` corrupts the "exporting not found" diagnostic log
- **Location:** `Modules/CoreRPG/Controllable/ExportControllable.swift:157`
- **What:** `"exporting not found \(id.uuidString))"` has an extra literal `)` immediately after the interpolated UUID closes, so every emitted log line reads `exporting not found 3F2A...-1234)` with a trailing stray paren.
- **Why:** Purely cosmetic, but it's the one diagnostic emitted when `bfsExportResults` can't resolve a seed/child id during export — exactly the line an engineer greps for when tracking down a "missing item on export" report, and a typo'd message erodes trust in the log.
- **Action:** Drop the extra `)`.
- **Severity:** Low

### 2.2 Dead commented-out modifier
- **Location:** `Modules/RolePlayGameKit/View/AppExportView.swift:14`
- **What:** `//.presentationDetents([.height(160)])` left commented out on the export panel's root view.
- **Why:** Dead code; a reader can't tell if it's a deliberate note-to-self or an accidental leftover from a revert.
- **Action:** Delete the line, or if the detent is genuinely still under consideration, replace it with a `// TODO:` comment explaining why it's off.
- **Severity:** Low

### 2.3 `FakeExportController.hubControllable` force-unwraps with no diagnostic
- **Location:** `Modules/CoreRPG/Fake/FakeExportController.swift:14-17`
- **What:** The fake's `hubControllable` getter is `_hubControllable!` — a bare force unwrap. The real `ExportModelBacked.hubControllable` (`Modules/CoreRPG/Controllable/ExportControllable.swift:36-44`) that every production conformer uses instead calls `preconditionFailure("\(module) export requires its Adventure export hub after setup.")`, which names the offending module in the crash log.
- **Why:** Any test or `#Preview` that constructs a `FakeExportController` without wiring `hubControllable` first (or accidentally uses `FakeExportController(...)` instead of the pre-wired `.fake` singleton) gets an unhelpful "Fatal error: Unexpectedly found nil" instead of a message pointing at the missing setup step.
- **Action:** Mirror the real implementation's `preconditionFailure` message instead of `!`.
- **Severity:** Low

---

## 3. Concurrency

_No findings._ `xcodebuild -scheme AdventureRPG -destination 'platform=iOS Simulator,name=iPhone 17 Pro' clean build` (which compiles CoreRPG plus all 14 leaf modules as dependencies) completed with **zero warnings** in any of the files in scope — the only two warnings in the entire build log are unrelated `appintentsmetadataprocessor` "no AppIntents.framework dependency" notices from targets that don't use App Intents. The actor-isolation design in both target files (a non-`@MainActor` `Sendable` protocol with selectively `@MainActor`-annotated default methods, so the binary-stream parsing loop can run off the main actor while every model mutation hops on) is unusually well-documented in-line (e.g. `ImportControllable.swift:32-35`, `:162-164`, `:232-234`) and matches CLAUDE.md's Swift 6.3 / `SWIFT_STRICT_CONCURRENCY = complete` requirement without gaps found during this pass.

## 4. API modernity

_No findings._ No legacy `Formatter` subclasses, C-style formatting, `DispatchQueue`, `ObservableObject`, or deprecated SwiftUI APIs were found anywhere in the files read for this scope. `Date.now.formatted(.iso8601...)` (`ExportControllable.swift:89`), `.replacing(_:with:)` (`ImportControllable.swift:696-697`), and `URL.cachesDirectory` / `.appending(path:)` (`ExportControllable.swift:91-94`) are already used per the project's modern-Foundation conventions.

## 5. Bugs / logic errors

### 5.1 Export completion ignores the file-move `Result`
- **Location:** `Modules/CoreRPG/FileViews/ExportProgressPanelView.swift:49-51`
- **What:** `.fileMover(isPresented: $showExporter, file: saveUrl) { _ in outcome = .finished }` discards the `Result<URL, Error>` the system hands back and unconditionally sets `outcome = .finished`, regardless of whether the user cancelled the save-file sheet or the move actually failed.
- **Why:** `exportUrl(...)` writes the export to `URL.cachesDirectory` (`ExportControllable.swift:88-95`) — a location the OS can purge at any time — specifically so the file-mover sheet is the step that gives the user a durable copy. If that sheet is dismissed without saving (or the move errors), the UI still shows "Export is finished, N items are successfully exported," so the user has no signal that their save-game or exported campaign data was never actually written anywhere persistent. For a save-game export this is a real, silent data-loss risk. The sibling `ImportProgressPanelView`'s `.fileImporter` handler (`ImportProgressPanelView.swift:180-192`) unwraps its `Result` correctly and distinguishes cancellation from failure, which confirms this is an oversight rather than a considered asymmetry.
- **Action:** Switch on the completion's `Result`: on `.success` set `.finished`; on cancellation-shaped errors set `.cancelled`; otherwise set `.failed(error.localizedDescription)`, matching the pattern already used for `.fileImporter`.
- **Severity:** High

## 6. Security

### 6.1 Unbounded allocation from an attacker/corruption-controlled size field
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:748-755` (`InputStream.readData(size:)`), reached from `:149-150` (the main item-parsing loop in `importStream`) and `:570-571` (`skip(itemCount:from:importModel:)`)
- **What:** `readData(size:)` does `var readBuffer = [UInt8](repeating: 0, count: size)` **before** validating `size` against anything — it comes straight from `readItemHeader()` → `readCounter()`, which reconstructs an arbitrary unsigned 32-bit value (up to ~4.29 billion) directly from 4 stream bytes with no upper bound check anywhere in the read path.
- **Why:** This is the parser for both (a) user-picked `.gmz`/`.gms` files (`performImport(from:)`, reachable via `ImportProgressPanelView`'s `.fileImporter`/`ImportRouteDestinationView`) and (b) **live game-networking payloads**: `GameControllable.importNetwork(from data: Data, ...)` (`Modules/CoreRPG/Controllable/GameControllable.swift:386-393`) wraps a peer-received `Data` blob in exactly this same `InputStream` → `importStream` path, and is called from every `PlayerController+*.swift` reveal/update handler (e.g. `PlayerController+Audio.swift:21,31`, `PlayerController+Photo.swift:60,91`, `PlayerController+Dice.swift:24,29`) whenever a player device receives a broadcast from the master over SharePlay or Bonjour. A single corrupted or maliciously-crafted 4-byte size field in an import file, or in a network message from another session participant, triggers an up-front allocation attempt of up to ~4 GB **before** the subsequent `read(...)` call has a chance to fail with `.notEnoughData` — on a memory-constrained iOS/visionOS device this is a reliable way to crash the app (jetsam/OOM), independent of whether the underlying stream actually contains that many bytes.
- **Action:** Cap `size` against a sane maximum (e.g. the known total remaining bytes for a file-backed stream, or a fixed ceiling like a few dozen MB for a single item/file blob) before allocating, and throw `.notEnoughData`/a new "size too large" error instead of allocating first.
- **Severity:** High

## 7. Performance

### 7.1 Post-import repair scans every item in the module instead of just the imported ones
- **Location:** `Modules/CoreRPG/Controllable/ConvertController.swift:23-27` (`repairItems`), invoked from `Modules/CoreRPG/Controllable/ImportControllable.swift:217-220`
- **What:** `repairImportedItems(reportModel:importedIds:)` iterates `itemController.itemDataModel.items` (**every item currently in the module**) and skips each one with `guard repairIds?.contains(itemId) ?? true else { continue }`, rather than iterating `importedIds` directly and looking each one up.
- **Why:** This runs after **every** non-manual, non-`gameMemoryOnly` import — which includes ordinary `.merge`/`.overwrite` file imports **and every live game-networking sync**, since `GameControllable.importNetwork(from:)` calls the exact same `importStream` path with `gameMemoryOnly: false` by default. For a long-running campaign with a large Character or Map module (hundreds of NPCs, monsters, or pins), a single-item network update (e.g. a health-bar change or a pin reveal during combat) forces an O(*total items in the module*) `Set.contains` scan just to find the one or two ids that actually changed. Each check is cheap in isolation, but this repeats on every networked message during active play, on the hot path the team has already had to optimize once (see the `battle-round-health-sync-on-turn-advance` fix).
- **Action:** When `repairIds` is non-nil, iterate `repairIds` directly (it's already a `Set<UUID>`) and look up each item via `itemSync(for:)`, instead of scanning the full `itemDataModel.items` list.
- **Severity:** Medium

## 8. SwiftUI / UI

No additional SwiftUI-specific findings beyond the correctness issue already covered in §5.1 (categorized under Bugs because the root cause is discarding a `Result`, not a SwiftUI API misuse). The two progress panels (`ImportProgressPanelView`, `ExportProgressPanelView`) otherwise follow the project's conventions: `@State`-owned `@Observable` models, `NavigationStack` + `navigationDestination`-free `.toolbar` actions, `.task(id:)` for the parse lifecycle, and an explicit `ImportMutationSession` object to serialize begin/end/cancel instead of ad hoc booleans.

## 9. Dead code / duplication / refactor

### 9.1 `ImportReviewItem` / `ImportResolution` are dead, superseded by a differently-named live implementation
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:13-26`
- **What:** `public enum ImportResolution { case old, new, merge }` and `public struct ImportReviewItem` (with its captured `applyResolution` closure) have zero references anywhere else in the codebase. The manual-review pipeline that's actually wired up (`ItemDataImportModel.pendingModules: [NetworkModules: [ImportReviewItemModel]]` at `:48`, populated by `recordManualReview`/`appendDeletionReviewItem`, and consumed by `Modules/CoreRPG/FileViews/ImportReviewModels.swift` and `SingleReviewModels.swift`) uses a completely different type, `ImportReviewItemModel`, with a differently-named decision enum (`SingleReviewDecision`: `.merge`/`.existing`/`.imported`) that doesn't share a case name with the dead `ImportResolution` (`.old`/`.new`/`.merge`).
- **Why:** These are public API surface in the file that defines the whole import subsystem's vocabulary — a maintainer skimming `ImportControllable.swift` for "what does a review item look like" will find this dead pair first (it's declared before the protocol) and could build against it, or be confused about which decision vocabulary (`old/new/merge` vs. `existing/imported/merge`) is current.
- **Action:** Delete `ImportResolution` and `ImportReviewItem`. If they were staged for a future review-UI redesign, a code comment saying so (and pointing at the tracking issue) would be less costly than leaving unreferenced public API in place.
- **Severity:** Medium

## 10. Cross-cutting recommendations

- **Validate size/count fields read from any binary or network stream before allocating.** §6.1 is the one instance actually exercised in this scope, but the same `readCounter()`-derived-size pattern is the template for any future wire-format addition to this file — worth a shared helper (`readData(size:maxAllowed:)`) that throws instead of allocating past a ceiling, so the safe behavior is the path of least resistance for the next person extending this format.
- **Audit other `Result`-discarding SwiftUI file-operation completions** (`.fileExporter`, `.fileMover`, `.fileImporter`) across the app for the same class of bug found in §5.1 — this scope only covered the two panels backing `ImportControllable`/`ExportControllable`, but the pattern (`{ _ in outcome = .finished }`) is easy to copy-paste into other file-based flows (PDF/Photo/Audio import pickers, etc.).
- **Prefer iterating the known-changed id set over the full item list** in any post-mutation "repair"/"revalidate" pass that's reachable from a per-message network hot path (§7.1) — the pattern of holding a `Set<UUID>` of exactly what changed and then scanning everything anyway shows up because the general-purpose `repairHiddenAndFolders` (whole-library) and the targeted `repairImportedItems` (import-only) paths share one loop; splitting the targeted path to iterate `repairIds` directly would fix this without touching the whole-library call site's behavior.

## 11. What was NOT audited

- The rest of the ~268k-line codebase outside the `ImportControllable`/`ExportControllable` usage graph — this was a scoped audit, not a full-codebase pass, so no claims are made about other subsystems (rendering, CoreData migrations, App Intents, widgets, SharePlay/Bonjour transport internals beyond the one call path traced in §6.1, etc.).
- The five `SingleReview*PropertyRow`/`SingleReviewLinkedPropertyRow`/`SingleReviewFilePropertyRow`/`SingleReviewReadOnlyPropertyRow`/`SingleReviewEntryPropertyRow` leaf views were spot-checked (`SingleReviewPropertyRow.swift`, `SingleReviewEntryRows.swift`) but not read line-by-line; no findings are claimed there beyond what's covered above.
- Test suites for import/export (`Tests/*RPGTests/{Import,Export}ControllerTests.swift`, `Tests/CoreRPGTests/ImportItemRepairTests.swift`) were located but their contents were not reviewed — this audit is about the production code, not test coverage.
- §6.1 was verified by reading the code, not by actually crafting a malformed file/network payload and reproducing a crash — the allocation-before-validation pattern is unambiguous from the source, but no dynamic repro was attempted.
- Algorithmic correctness of the CRDT-style `merge()`/`isSame()` implementations on individual model types (outside `ItemControllable`'s own `merge(with:forceMerge:)`) was out of scope — this audit traced the control flow through `ImportControllable`/`ExportControllable` and their direct dependents, not every `ItemDiffComparable` conformance in each of the 14 modules.
- RuleRPG's and Adventure's bespoke cross-module link-graph traversals in `exporting(itemIds:)` (`Modules/RuleRPG/Controller/ExportController.swift`, `Modules/AdventureRPG/Controller/ExportController.swift`) were read and manually traced for double-export/missed-export bugs (none found — the "collect everywhere, write once via each module stripping its own key in the fixed `additionalExport` chain" design holds up under inspection) but were not exercised with real data.

## 12. Verification

- **§6.1** — open `Modules/CoreRPG/Controllable/ImportControllable.swift`, lines 748-755: the allocation `[UInt8](repeating: 0, count: size)` occurs on line 749, one statement before `size` is checked against anything. Trace `size`'s origin at lines 149-150 and 570-571 to `readItemHeader()` (:731-733) → `readCounter()` (:735-746), which places no bound on the reconstructed `Int`. Trace the network-reachable call path at `Modules/CoreRPG/Controllable/GameControllable.swift:386-393` (`importNetwork`) and one concrete caller, `Modules/GameRPG/Controller/PlayerController+Audio.swift:21` and `:31`.
- **§5.1** — open `Modules/CoreRPG/FileViews/ExportProgressPanelView.swift`, lines 48-52: the `.fileMover` trailing closure's parameter is named `_`, so the `Result<URL, Error>` is discarded and `outcome = .finished` runs unconditionally. Compare with `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift`, lines 180-192, where the equivalent `.fileImporter` completion does `do { loadUrl = try result.get(); ... } catch is CancellationError { ... } catch { ... }`.
