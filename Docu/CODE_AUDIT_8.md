# MasterRPG Code Audit — Round 8

Generated 2026-08-20. Scope: ~267,300 Swift LOC across ~1,986 files, covering all 15 dynamic-framework modules (`AdventureRPG`, `AudioRPG`, `CharacterRPG`, `CoreRPG`, `DiceRPG`, `GameRPG`, `GeneratorRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `RolePlayGameKit`, `RuleRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG`) and the `MasterRPG`/`MasterMac`/`MasterTV`/`RPGShare`/`DiceRollerWidgetExtension` targets. No `Dead/` or archived directory exists in this repo, so nothing was excluded by convention — only `.git/`, `.build/`, `DerivedData/`, and `xcuserdata/` were skipped.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

**Compiler ground truth:** a genuine full clean `xcodebuild build` (fresh `-derivedDataPath`, not incremental) of the `MasterRPG` scheme against the iPhone 17 Pro Simulator, iOS 26 SDK, under `SWIFT_STRICT_CONCURRENCY = complete` / Swift 6 language mode: **BUILD SUCCEEDED with zero real warnings** — the only two log lines matching `warning:` are benign `appintentsmetadataprocessor: Metadata extraction skipped, no AppIntents.framework dependency found` notices, unrelated to source code. Identical to every prior pass.

**Context on findings volume — this is a notably clean round.** This repo carries seven prior audit passes (`Docu/CODE_AUDIT_1.md` through `_7.md`). Both of round 7's Critical findings were independently confirmed fixed before this round's agents even launched (the Share Extension no longer touches `AppModel.shared`; the 3D Scanner now threads an `itemId` all the way to `editController.resetFile`). Three parallel deep-read passes then re-verified **every single still-open finding from round 7** against current source — not against the old report's text — plus a dedicated SwiftUI-focused pass over the surfaces reworked since round 7. The result: of round 7's ~30 bug/security/performance findings, **~24 are now confirmed fixed**; of its 7 concurrency findings, 2 are fully fixed and the rest downgraded; of its 17 dead-code/duplication findings, 8 are fully fixed and 8 remain open. **Zero Critical or High findings survived this round** — every finding below is Medium or Low. A large drag/move/zoom/rotate rework of the 3D game table (`GameRPG/Table3D/*`), new game-window UI, and a `Sheet`/search rework landed since round 7 was written; all three agents and the SwiftUI pass gave that code extra scrutiny as unaudited territory, and it held up well — the previously-flagged untracked fog-of-war `Task`s are now exemplary (cancel-then-replace with staleness guards), though one sibling gesture-state variable was found still missing the same guard (§5.1).

---

## 1. Executive summary

Top items to address, in priority order (none rise above Medium this round):

1. **[Medium] Table-move drag state can wedge, causing a visible table snap after an interrupted gesture** — §5.1 — `Modules/GameRPG/Table3D/GameTableView.swift:548,701,728,737-745`.
2. **[Medium] Sheet "add entry"/"add group" buttons animate unconditionally, ignoring Reduce Motion** — §8.1 — `Modules/CoreRPG/Sheet/SheetEntryAddButton.swift:15`, `SheetEntryAddGroupButton.swift:14`.
3. **[Medium] Player display name logged at `.public` privacy on hot SharePlay send paths** — §6.1 — `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:774,838`.
4. **[Medium] System-package Foundry imports still parse the same archive up to 3x** — §7.1 — `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:90-152` and 3 other files.
5. **[Medium] Duplicated fixed 0.6s window-prep delay, still unresolved since round 7** — §5.2 — `Modules/GameRPG/GameViews/MasterGameScreen.swift:149`, `PlayerGameScreen.swift:118`.
6. **[Medium] No generation-id guard against a stale AI partial-stream write racing a newer request** — §3.5 — `Modules/GeneratorRPG/Controller/GeneratorController.swift:230-294,307-402`.
7. **[Medium] Master*/Player* GameRPG view-pair duplication has spread to the new window-button views** — §9.6 — `Modules/GameRPG/GameViews/MasterGameWindowButtonView.swift` vs `PlayerGameWindowButtonView.swift`.
8. **[Medium] A third hand-copied "which modules get a window button" list was introduced by the new side menu** — §9.7 — `Modules/GameRPG/GameViews/GameTableSideMenu.swift:28-35`.
9. **[Medium] ~130 lines of real hand-tracking gesture code are dead and unreachable** — §9.8 — `Modules/DiceRPG/Space/HandTrackingModel.swift:110-176,178-246`.
10. **[Medium] 52 files still exceed 500 lines; none have been split since round 1** — §9.13.

---

## 2. Quick wins (≤30 min each)

- **Gate `withAnimation` on `accessibilityReduceMotion` in both Sheet add buttons** — §8.1 — `Modules/CoreRPG/Sheet/SheetEntryAddButton.swift:15`, `SheetEntryAddGroupButton.swift:14`; every sibling file in the same folder already does this.
- **Delete the two commented-out `//scenesManager.dismissWindow(SceneId.game)` / `//scenesManager.openWindow(SceneId.game)` lines** — §9.17 — `Modules/GameRPG/GameViews/GameTableWindowButton.swift:78,95`.
- **Delete the 4 unused `GameMetrics` constants** (`smallHeight`, `boardHeight`, `playerAreaSize`, `playerHandSize`) — §9.9 — `Modules/GameRPG/Table3D/GameMetrics.swift:25-28`; zero call sites anywhere.
- **Delete the leftover commented `.dodecahedron(...)` line and the commented `.scrollTargetLayout()` line** — §9.17 — `Modules/GameRPG/Table3D/GameEquipment.swift:516`, `Modules/CoreRPG/Sheet/TableSheetView.swift:35`.
- **Store and cancel the `delayedTask` result in `SheetRootModel`'s two `moveEntry`/`moveEntryOutOfGroup` call sites** — §9.15 — `Modules/CoreRPG/Sheet/SheetRootModel.swift:928,947`; every other call site of this helper already does.
- **Remove the two `MainActor.run` wrappers in already-`@MainActor` `MasterController` code** — §3.4 — `Modules/GameRPG/Controller/MasterController.swift:532-535,1150-1163`.

---

## 3. Concurrency

A full-tree grep for every hard CLAUDE.md rule (`DispatchQueue.main.async`/`.asyncAfter`, `ObservableObject`/`@Published`, `Task.sleep(nanoseconds:)`, `DateFormatter`/`NumberFormatter`, `String(format:)`) returned zero genuine hits — unchanged from every prior pass. Round 7's `@unchecked Sendable` (`FoundryJSONDepthCounter`) and missing-`[weak self]` (`GeneratorSessionModel.init`) findings are both confirmed **fixed**.

### 3.1 Actor-hopping TOCTOU race in `FileDataController` delete/replace
- **Location:** `Modules/CoreRPG/Files/FileDataController.swift:106-122`, reachable via `Modules/CoreRPG/Files/FileBookmarkController.swift:34-54`
- **What:** `delete(id:)`/`replace(data:)` still do `await model.data.firstIndex(where:)` and then a *separate* awaited actor call to mutate at that index, rather than one atomic operation.
- **Why:** `FileBookmarkModel.save()` (the only production caller) is itself reentrant (multiple `await` points), so a rapid second `changeBookmarks`/`removeBookmark` call can interleave between the captured index and the mutation, silently losing/overwriting a concurrent bookmark write.
- **Action:** Fold the read-then-mutate into one actor-isolated method (e.g. `removeIfPresent(id:)`) so no other call can interleave.
- **Severity:** Medium

### 3.2 Blocking `context.performAndWait` inside async actor methods
- **Location:** `Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift:183` (`process()`), `:248` (`merge(...)`)
- **What:** Both still call Core Data's synchronous, blocking `performAndWait` from inside `async` actor methods instead of `await context.perform`.
- **Why:** Blocks a cooperative-pool worker thread until Core Data's own context queue runs the block; the `viewContext.performAndWait` case specifically blocks a background actor's thread on the main-queue-bound view context, risking pool starvation under a burst of CloudKit remote-change notifications.
- **Action:** Replace both with `try await backgroundContext.perform { ... }` / `await viewContext.perform { ... }`.
- **Severity:** Medium

### 3.3 Raw `MainActor.assumeIsolated` bypassing the shared audited helper — grew to 5 sites
- **Location:** `Modules/CoreRPG/Navigator/Core/Navigator.swift:232-240`, `NavigationLocked.swift:50-61`, `NavigationProvidedDestination.swift:111-126`, `NavigationSend.swift:417-426` (all vendored `deinit`s), plus `Modules/AudioRPG/Audio/AudioPlayerSession.swift:104` (inside an `.interruptionNotification` observer closure — new since round 7)
- **What:** All five call `MainActor.assumeIsolated { ... }` directly instead of routing through `Modules/CoreRPG/Concurrency/MainActorIsolationAssumption.swift`'s `assumeMainActorIsolated(_:)`, which is otherwise correctly and widely adopted (14+ files).
- **Why:** The shared helper's own doc comment states its purpose is being "the single place to find, audit, or harden... every site relying on this contract" — these five bypass it, so a future hardening pass won't cover them.
- **Action:** Route all five through `assumeMainActorIsolated(_:)`; the three Navigator/NavigationSend sites are vendored third-party source, so this may need a small local wrapper rather than editing vendored code directly.
- **Severity:** Low

### 3.4 Redundant `await MainActor.run` inside already-`@MainActor` code
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:532-535` (`resetPlayers()`), `:1150-1163` (`recordDeliveryReceipt(_:)`)
- **What:** Both methods are on `@MainActor final class MasterController` yet still wrap plain synchronous reads in `await MainActor.run { ... }`.
- **Why:** Pure overhead — an unnecessary actor-hop on `MasterController`'s hottest receive path (`recordDeliveryReceipt` runs on every incoming `.ok` acknowledgement) — plus reader confusion about whether a real actor crossing is happening.
- **Action:** Remove both wrappers; inline the closures' bodies directly.
- **Severity:** Low

### 3.5 No generation-id guard against a stale AI partial-stream write racing a newer request
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:230-294` (`request(message:rootModel:)`), `:307-402` (`extract(message:rootModel:...)`); `Modules/GeneratorRPG/BasicAI/Engine/ConversationEngine.swift:209-241` (`streamResponse`)
- **What:** The round-7 mitigation moved into `ConversationEngine.streamResponse`, which now cancels the previous `activeStreamingTask` before starting a new one (mirroring `GameTableModel.fogOfWarTask`'s cancel-then-replace pattern). There is still no explicit generation/epoch token compared inside `onPartialResponse` (or `extract`'s stream loop) before writing into `rootModel`/`model.streamingResponse` — correctness depends entirely on the underlying `LanguageModelSession.streamResponse` sequence observing `Task.isCancelled` promptly on an element already in flight.
- **Why:** A rapid second `request(message:)`/`extract(message:)` call (e.g. the user edits and resends before the first reply finishes) can let one more stale partial from the *old* stream land after the new request's first partial — a momentary flicker of stale AI-preview text. Narrower blast radius than round 7's characterization thanks to the cancel-before-start step, but not eliminated.
- **Action:** Add a monotonically increasing generation counter on `GeneratorSessionModel`, capture it at the start of `request`/`extract`, and guard every partial-write with `guard capturedGeneration == model.currentGeneration else { return }`.
- **Severity:** Medium

---

## 4. API modernity

Deployment target is iOS/iPadOS/tvOS/visionOS/macOS 26.0 across the board — no back-compat surface. A full-tree grep for every hard CLAUDE.md/SwiftUI rule (`replacingOccurrences`, `UIScreen.main`, `NavigationView`, single-parameter `.onChange`, `.foregroundColor()`, `.cornerRadius()`, `.tabItem()`, non-localized `.contains()` on search text) returned zero genuine hits.

### 4.1 `NSItemProvider` completion-handler APIs wrapped in continuations where native `async throws` equivalents exist
- **Location:** `Modules/PhotoRPG/Controller/ItemController.swift:48-64` (`importImageFromProviders`), `Sources/RPGShare/ItemProviderImporter.swift:180-210` (`loadItem`)
- **What:** Both wrap `NSItemProvider`'s old completion-handler APIs in `withCheckedThrowingContinuation`, even though `NSItemProvider` has shipped native `async throws` equivalents since iOS 16/macOS 13 — well below this app's 26.0 floor. `ItemController.swift`'s own doc comment even cites having modernized a *different*, nearby completion-handler call in the same file without doing the same two lines below it.
- **Why:** Pure legacy debt at this deployment target; the hand-rolled continuation plumbing is unnecessary.
- **Action:** Replace both with the native `async throws` `NSItemProvider` APIs.
- **Severity:** Low

### 4.2 Vendored `@available` guards below the 26.0 deployment floor
- **Location:** `Modules/CoreRPG/Navigator/Extensions/NavigationLink+Navigator.swift:40,102`
- **What:** `@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)` guards on two `NavigationLink` initializers.
- **Why:** Dead conditionals at this app's actual floor, but this is vendored third-party source (`NavigatorUI`), not app-authored code.
- **Action:** No action needed unless the vendored package is forked/patched. Informational only.
- **Severity:** Low

---

## 5. Bugs / logic errors

Round 7's §5.2-§5.21 (20 items) were re-verified against current source, reading the actual reworked Table3D/GeneratorController code rather than trusting old line numbers. **18 of 20 are confirmed fixed** — the 3D Scanner `itemId` now threads all the way to `editController.resetFile`; `GameRootModel`'s `stopGameTask` reentrancy guard, the `.onDisappear` → `endGame()` teardown path, the `fogOfWarTask`/`roomActionTask` cancel-then-replace pattern, the Foundry cycle guard and cooperative checkpointing, the bounded `deliveryMessagesByWireID`, and the Hand Tracking authorization-revoked handler are all live in current source. Only two carry forward, both below.

### 5.1 Table-move drag state can wedge and cause a visible table snap
- **Location:** `Modules/GameRPG/Table3D/GameTableView.swift:548` (`tableMoveLastTranslation` declaration), `:701` and `:728` (reset-on-`.onEnded` sites), `:737-745` (`applyTableMoveDelta`)
- **What:** `tableMoveLastTranslation` — used by `tableMoveGesture`/`boardDragGesture`'s table-move branch to compute per-frame deltas from `DragGesture`'s cumulative `translation` — is only ever reset inside each gesture's own `.onEnded`, with no staleness/timeout guard. Its sibling `viewportPanStart`/`viewportPanLastUpdate` pair in the same struct (lines 533-543) has exactly this guard, added specifically because "`.onEnded` may never be delivered (system interruption, window backgrounding mid-drag)."
- **Why:** If a table-move drag's `.onEnded` is ever not delivered, `tableMoveLastTranslation` stays stuck at a large non-zero value. The next unrelated table-move gesture's first `.onChanged` then computes a delta against that stale value, applying a large, wrong one-frame jump to `game.renderer.root.position` — a visible snap of the whole table. Same bug class round 7's §5.10 already fixed for the sibling pan gesture, just left unguarded here.
- **Action:** Apply the same staleness-timeout pattern already used for `viewportPanStart`/`viewportPanLastUpdate` to `tableMoveLastTranslation` (track a last-update timestamp and reset when stale before computing a new delta).
- **Severity:** Medium

### 5.2 Duplicated fixed 0.6s window-prep delay, still unresolved
- **Location:** `Modules/GameRPG/GameViews/MasterGameScreen.swift:147-149`, `Modules/GameRPG/GameViews/PlayerGameScreen.swift:116-118`
- **What:** `prepareWindows()` in both screens still starts with an unconditional `try await Task.sleep(for: .seconds(0.6))` before opening the adventure/character viewer window on visionOS, byte-identical between the two files.
- **Why:** A hardcoded delay is a timing guess, not a guarantee — it can race scene readiness on a loaded system or add needless latency on a fast one.
- **Action:** Replace the fixed sleep with an actual readiness signal from `ScenesManager` if available; extract into one shared location both screens call into (also fixes the duplication — see §9.6).
- **Severity:** Medium

---

## 6. Security

Round 7's §6.1 (Foundry image pixel cap), §6.2 (JSON nesting-depth guard), §6.3 (Share Extension image size cap), §6.5 (peer endpoint logging), and §6.7 (unused `aps-environment` entitlement) are all confirmed **fixed**.

### 6.1 Player display name still logged at `.public` privacy on hot SharePlay send paths
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:774,838`; `Modules/GameRPG/Model/GameNetworkModel.swift:988-990` (`debugDescription` interpolates `sender.name`)
- **What:** Round 7's highest-volume site (`ImportControllable.swift`'s diff logging) is now correctly `.private`, but two `Logger.sharePlay.debug(...)` calls in `sendData(...)` and the journal publication closure still log `gameNetworkModel.debugDescription`/`prepared.model.debugDescription` at `privacy: .public` — and `debugDescription` embeds the player's chosen display name via `sender.name`. Verified: `sendData(...)` runs on essentially every outgoing/journaled SharePlay message during live play, not a rare debug trace.
- **Why:** `.public` privacy opts the string out of unified-logging's default redaction, so a player's chosen display name persists in plaintext in Console.app output/sysdiagnose pulled from any participant's device.
- **Action:** Change these two interpolations to `privacy: .private`, matching the fix already applied to the import-review path and `PlayerNetworkController.swift`'s endpoint logging.
- **Severity:** Medium

### 6.2 Local-network join code stored in plain `UserDefaults`; no Keychain use anywhere
- **Location:** `Modules/GameRPG/Network/GameJoinCodeModel.swift:26-56`
- **What:** Re-verified unchanged from round 7: `masterCode`/`playerCode` — gating the TLS-PSK Bonjour handshake — are generated and persisted via plain `UserDefaults.standard`. A repo-wide search still finds zero `Keychain`/`kSecClass` usage anywhere.
- **Why:** `UserDefaults` is unencrypted app-sandbox storage included in unencrypted local device backups — weaker than Keychain for a value gating network trust between devices.
- **Action:** Consider moving join codes into Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` if/when this area is next touched.
- **Severity:** Low

---

## 7. Performance

Round 7's §7.1 (per-resource Foundry ZIP reopening, fixed via `FoundryZIPDataSourceCache`) and §7.3 (linear `pinPawns` scan, fixed via `cachedDragPawn`) are confirmed **fixed**.

### 7.1 System-package Foundry imports still parse the same archive up to 3 times
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:90-152` (`loadSelectedArtifact`); `Modules/CoreRPG/Foundry/FoundryArtifactDetector.swift:35,74` (`detect(at:)` builds its own `FoundryZIPArchive` from a fresh `Data(contentsOf:)` read); `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:20,44` (`read(from:)` decodes via the cache, then separately constructs `FoundrySystemPackageReader`); `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:17-36` (builds its own independent data source, not sharing the cache)
- **What:** §7.1's per-*resource* re-parsing was fixed, but this coarser-grained triple-parse for the whole-archive "system package" import path was not: `detect()` fully parses the ZIP central directory once independently, `FoundryVTTDecoder.decode()` parses it again (via the cache), and `FoundrySystemPackageReader.read()` parses it a third time through a completely separate, uncached data source.
- **Why:** For the common "import a Foundry system package" flow, this still multiplies disk I/O and ZIP central-directory parsing up to 3x on every import, scaling with archive size (up to 1GiB).
- **Action:** Either have `FoundryArtifactDetector`/`FoundrySystemPackageReader` accept an already-opened data source (or share `FoundryZIPDataSourceCache`), or have `FoundryVTTImportReader.read(from:)` pass its already-parsed data source into `FoundrySystemPackageReader` instead of letting it reopen the file independently.
- **Severity:** Medium

### 7.2 `focusedDiceSignature` recomputed on every SwiftUI body evaluation
- **Location:** `Modules/GameRPG/Table3D/GameTableView.swift:384-390`
- **What:** This computed property (`diceModel.dice.flatMap { [$0.die.max] + $0.result }`) is still evaluated fresh on every body pass purely to feed an `.onChange(of:)` equality check.
- **Why:** Flattens every result array on every body evaluation regardless of whether anything dice-related changed — an avoidable allocation on a view already doing meaningful per-frame-adjacent RealityView work.
- **Action:** Derive the signature only when the underlying dice model's result actually changes (an `@Observable`-tracked cached signature) rather than recomputing on every body evaluation.
- **Severity:** Low

---

## 8. SwiftUI / UI

A dedicated pass over the SwiftUI surfaces reworked since round 7 (`GameRPG/Table3D`, `GameRPG/GameViews`, `CoreRPG/Sheet`) found this code to be uniformly high quality: leaf views correctly adopt `Equatable` where they have no `@Environment` dependency (`SheetEntryGeneratedSelectionBorder`, `SheetEntrySelectionBorder`), gesture-driven `@State` is `private` throughout, every `.animation`/`withAnimation` call gates on `accessibilityReduceMotion` except the one pair below, `ForEach` uses stable model-id identity everywhere sampled, and view bodies are consistently extracted into dedicated `View` structs rather than computed properties on a monolithic type. Round 7's §8.3/§8.4 (`.toggle()` misuse, fixed-height icon frames) are confirmed fixed.

### 8.1 Sheet "add entry"/"add group" buttons animate unconditionally, ignoring Reduce Motion
- **Location:** `Modules/CoreRPG/Sheet/SheetEntryAddButton.swift:15` (`withAnimation { ... }`), `Modules/CoreRPG/Sheet/SheetEntryAddGroupButton.swift:14` (`withAnimation { ... }`)
- **What:** Both call plain `withAnimation { ... }` with no `accessibilityReduceMotion` check. Every other `withAnimation`/`.animation` call in the same `CoreRPG/Sheet/` folder gates on it: `InlineSheetSearchControl.swift:43,87`, `SheetEntryView.swift:92-94,255`, `SheetEntryReviewButton.swift:27`, `SheetView.swift:114`, `TableSheetView.swift:33,40` — all independently verified to correctly write `accessibilityReduceMotion ? nil : ...`.
- **Why:** Round 7's §9.8 found "add entry" duplicated 4x with an inconsistent Reduce Motion gap in 2 of the 4 copies; the fix consolidated all 4 into these two shared components (good — the duplication is gone), but the accessibility gap itself survived the merge into the now-single call site. Every module's "add entry"/"add group" action still animates unconditionally for Reduce Motion users.
- **Action:** Add `@Environment(\.accessibilityReduceMotion)` to both button views and gate their `withAnimation` calls, matching the rest of the folder.
- **Severity:** Medium

---

## 9. Dead code / duplication / refactor

Round 7's §9.1 (dead code block), §9.9 (hand-rolled debounce), §9.10 (`JSONEncoder`/`JSONDecoder` stragglers in `GameStatisticsModel`), §9.12 (`NetworkNodel` typo), §9.14 (wrong MARK protocol name), and §9.15 (misplaced `ScenesManager.SceneState` extension) are all confirmed **fixed**. §9.13 (`NSRegularExpression`/`Regex` inconsistency) was resolved by removal rather than migration — the file no longer contains any `Regex` literal, just 4 legacy `NSRegularExpression` sites, no longer inconsistent within one function.

### 9.1 App Intents `Entity`/`EntityQuery` boilerplate still duplicated 12x
- **Location:** `Modules/{Pdf,Photo,Space,Audio,Character,Rule,Dice,Generator,Map,Table,Weather,Adventure}RPG/Intent/*Entity.swift`, all 172 lines each (e.g. `Modules/PdfRPG/Intent/PdfEntity.swift` vs `Modules/PhotoRPG/Intent/PhotoEntity.swift`)
- **What:** Diffing any two still shows only type-name/string swaps; no shared generic base exists anywhere in CoreRPG.
- **Action:** Pull `EntityQuery` conformance into a shared generic CoreRPG base.
- **Severity:** Medium

### 9.2 Per-module `ImportController.swift`/`ExportController.swift` byte-identical across 10+ modules
- **Location:** `Modules/{Audio,Character,Dice,Generator,Map,Pdf,Photo,Space,Table,Weather}RPG/Controller/ImportController.swift` (19 lines each, byte-identical); `Modules/{Dice,Generator,Pdf}RPG/Controller/ExportController.swift` (20 lines each, byte-identical)
- **What:** `struct ImportController: Sendable { let itemController: ItemController; let editController: EditController }` still hand-copied into 11 modules. `AdventureRPG`'s and `RuleRPG`'s remain legitimately bespoke.
- **Action:** Generic `GenericImportController<Item, Edit>`/`GenericExportController` in CoreRPG.
- **Severity:** Medium

### 9.3 Per-module `ItemController`/small-tier `GameController` near-identical (typealias-only diffs)
- **Location:** `Modules/{Weather,Adventure,Generator}RPG/Controller/ItemController.swift` (23-24 lines); `Modules/{Generator,Rule}RPG/Controller/GameController.swift` (40/43 lines)
- **What:** Diffs are still typealias-only plus incidental whitespace/brace-style differences.
- **Action:** Same generic-base treatment as §9.2.
- **Severity:** Low

### 9.4 `FolderListController.swift` near-identical across all 12 modules
- **Location:** `Modules/{Adventure,Audio,Character,Dice,Generator,Map,Pdf,Photo,Rule,Space,Table,Weather}RPG/Controller/FolderListController.swift` (38-40 lines each, e.g. `Modules/AdventureRPG/Controller/FolderListController.swift`)
- **What:** Still identical `FolderListControllable` conformance with only `Route`-enum names swapped; 5 of 12 still carry an unused `import SwiftData` the other 7 don't.
- **Action:** Move `copy(listModel:)` into a CoreRPG protocol-extension default.
- **Severity:** Low

### 9.5 Dead `import SwiftData` — 43 non-test files (was 42 in round 7)
- **Location:** `Modules/RolePlayGameKit/Model/AppModel.swift`, `PdfRPG/Root/PdfRootModel.swift`, `FolderListController.swift`/`DropChooseView.swift`/`RootModel.swift`/`RootFactory.swift` across Pdf/Space/Audio/Map/Photo/Dice/Adventure/Character/Generator/Table RPG, plus several `CoreRPG/{Controllable,LGViews,Model,Fake,EntryEditor}` files — 57 non-test files import SwiftData repo-wide; 43 reference no SwiftData symbol at all.
- **Action:** Strip the dead import from all 43.
- **Severity:** Low

### 9.6 Master*/Player* GameRPG view pairs still duplicated — pattern spread to new files
- **Location:** `Modules/GameRPG/GameViews/MasterGameScreen.swift` (209 lines) vs `PlayerGameScreen.swift` (185 lines); `MasterOverlayMenu.swift` vs `PlayerOverlayMenu.swift`; **new since round 7:** `MasterGameWindowButtonView.swift` (73 lines) vs `PlayerGameWindowButtonView.swift` (74 lines)
- **What:** The visionOS ornament scaffold, `endGame()`, and the 0.6s window-prep delay (§5.2) remain hand-mirrored between `MasterGameScreen`/`PlayerGameScreen`. The new `MasterGameWindowButtonView`/`PlayerGameWindowButtonView` pair duplicates its entire view body — label, `GameWindowButtonAppearance` modifier, `.help`/`.accessibilityValue`, `gameWindowScene` computed property — differing only in `isMaster`, the stored property (`adventureId` vs `root`), and Player's extra `.disabled(...)`. The actual open/close *logic* was correctly extracted into the new `GameWindowToggle` enum (both views just call `GameWindowToggle.open/close`), so only the SwiftUI view scaffold repeats the pattern.
- **Why:** New code repeating a shape already flagged as a refactor candidate elsewhere in the same file family; a change to the toggle button now needs hand-syncing across two files.
- **Action:** Merge into one `GameWindowButtonView`-style component parameterized by `isMaster`/`itemId` — `GameTableSideMenu` (see §9.7) already sets a working precedent for merging Master/Player into one file with an `isMaster` flag.
- **Severity:** Medium

### 9.7 A third hand-copied "which modules get a window button" list, introduced by the new `GameTableSideMenu`
- **Location:** `Modules/GameRPG/GameViews/GameTableSideMenu.swift:28-35` (`masterModules`/`playerModules`) vs `Modules/GameRPG/GameViews/MasterModuleWindowMenu.swift:10-22` (`modules`) vs `Modules/GameRPG/GameViews/PlayerSideMenu.swift:10-17` (`modules`)
- **What:** `GameTableSideMenu`'s own doc comment admits it: "Mirrors `MasterModuleWindowMenu.modules`, minus `.game`" and "Mirrors `PlayerSideMenu.modules`" — its `playerModules` array is byte-identical to `PlayerSideMenu.modules`.
- **Why:** A third hand-synchronized copy of the same list; adding/removing a module now requires updating three files, and the lists have already drifted in element order across the three copies.
- **Action:** Hoist the master/player window-menu module lists into one shared static (e.g. on `NetworkModules` itself) that all three views read from.
- **Severity:** Medium

### 9.8 Dead hand-tracking gesture methods — ~130 lines of real code, unreachable
- **Location:** `Modules/DiceRPG/Space/HandTrackingModel.swift:110-176` (`computeTransformOfUserPerformedHeartGesture()`), `:178-246` (`computeTransformOfUserPerformedGrabingDiceGesture()`)
- **What:** Both methods guard on tracked hand joints, then hit a large `/* ... */` block comment containing the actual heart-gesture/grab-gesture transform math, followed by an unconditional `return nil`. Neither method has any call site anywhere in the repo.
- **Why:** ~130 lines of real, non-trivial gesture-recognition code sit dead and unreachable — the same "raw block comment, not `#if false`, evades grep-only sweeps" shape round 7 flagged for `GeneratorController.swift`, just a fresh instance.
- **Action:** Delete both methods if the heart/grab gestures are abandoned, or finish wiring them up and un-comment the real logic if the feature is still wanted.
- **Severity:** Medium

### 9.9 `GameMetrics` — four declared constants with zero call sites
- **Location:** `Modules/GameRPG/Table3D/GameMetrics.swift:25-28` (`smallHeight`, `boardHeight`, `playerAreaSize`, `playerHandSize`)
- **What:** Leftovers from the pre-rework table layout — no reference anywhere outside their own declaration.
- **Action:** Delete all four. Quick win — see §2.
- **Severity:** Low

### 9.10 Duplicated pin-drag boilerplate between visionOS and iOS/macOS halves of `GameTableView`
- **Location:** `Modules/GameRPG/Table3D/GameTableView.swift:128-143` (visionOS `RealityView` gesture, inline) vs `:648-663` (`pinDragGesture` computed property, iOS/macOS half of the same file)
- **What:** Both guard the pin component/parent, compute a table-relative position, and call `game.pinDragChanged`/`pinDragEnded` — identical control flow, differing only in how position is derived.
- **Action:** Factor the guard+dispatch into a shared helper taking a position-resolver closure, letting each platform supply only its own position computation.
- **Severity:** Low

### 9.11 Duplicated `GameRenderer`/`GamePortableRenderer` boilerplate across platform variants
- **Location:** `Modules/GameRPG/Table3D/GameRenderer.swift:74-84` (`applyScale`/`placeTable`, visionOS) vs `Modules/GameRPG/Table3D/GamePortableRenderer.swift:51-57` (same methods, iOS/macOS)
- **What:** Byte-identical `applyScale(_:)` and near-identical `placeTable(bottomY:)`/`loadAssets()` bodies, compiled exclusively via `#if os(...)` so never in the same build.
- **Action:** Low priority given the platform split is otherwise justified (TabletopKit vs. plain RealityKit); worth a shared protocol default only if a third variant is ever added.
- **Severity:** Low

### 9.12 New near-duplicate focus/scroll `.onChange` block from the Sheet rework
- **Location:** `Modules/CoreRPG/Sheet/SheetView.swift:99-108` vs `Modules/CoreRPG/Sheet/SheetEntryView.swift:67-75`
- **What:** Both attach an identical `.onChange(of: focusedEntryId.wrappedValue)` pattern — guard the focused id matches this row, conditionally call `rootModel.setSelected(...)`, then `rootModel.setScrollEntryId(...)` — introduced together in the same rework, with near-verbatim matching doc comments.
- **Why:** Two files now have to stay hand-synchronized for any future change to focus/scroll/selection sequencing.
- **Action:** Extract a shared `rootModel.handleFocusActivation(source:entryId:currentId:)`-style helper on `SheetRootModel` that both call sites invoke.
- **Severity:** Low

### 9.13 Oversized files (>500 lines) — 52 non-test files, unchanged since round 1
- **Location (current sizes):** `Modules/GameRPG/Controller/MasterController.swift` 2666 lines; `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift` 2602; `Modules/GameRPG/SharePlay/RPGSharePlayController.swift` 2492 (still zero `// MARK:` comments in the whole file); `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift` 2471; `Modules/GameRPG/Table3D/GameTableModel.swift` 1150 (grew from ~1026 pre-rework); `Modules/CoreRPG/Sheet/SheetRootModel.swift` 1014.
- **What:** 52 non-test files exceed 500 lines (round 7 counted 53 — essentially no progress). `MasterController.swift` still has only 5 MARK sections for 2666 lines.
- **Action:** Mechanical splits along existing MARK seams, prioritizing already-sectioned files.
- **Severity:** Medium (well-sectioned files) / Low (rest)

### 9.14 Ad-hoc `Task.sleep` magic constants — grew to 83 (was 72 in round 7)
- **Location:** repo-wide; distribution includes `.milliseconds(100)` ×7, `.seconds(0.25)` ×5, `.milliseconds(50)` ×5, `.seconds(1)` ×4, `.seconds(0.6)` ×3 (§5.2), `.seconds(0.5)` ×3, plus ~15 more distinct one-off literals.
- **What:** Still no shared vocabulary beyond the two named exceptions (`SharePlayPackageSender.throttleInMilliSeconds`, persistent-history's `initialCleanupDelay`); the Table3D/Sheet reworks added more.
- **Action:** Hoist to named constants opportunistically as files are touched.
- **Severity:** Low

### 9.15 `delayedTask` result discarded, breaking the established cancel-then-replace contract
- **Location:** `Modules/CoreRPG/Sheet/SheetRootModel.swift:928` (`moveEntry(_:in:into:)`), `:947` (`moveEntryOutOfGroup(_:in:parent:)`)
- **What:** Both discard the `Task` returned by `delayedTask(.milliseconds(100)) { ... }`, unlike every other call site of this helper (`AppIntentContentInvalidator.swift`, `NavigationSend.swift`, `TimedMessageList.swift`), which all store the task and let a new call cancel the previous one — `delayedTask`'s own doc comment states callers must do this themselves.
- **Why:** Currently harmless because the deferred `updateParent(parentModel)` call is idempotent, but rapidly moving multiple entries spawns multiple untracked, uncancelled delayed calls, silently violating a pattern this codebase otherwise treats as a hard rule.
- **Action:** Store the returned task in a `SheetRootModel` property and cancel the previous one before assigning a new one. Quick win — see §2.
- **Severity:** Low

### 9.16 Commented-out AppIntentTests block — unchanged, deliberately tracked
- **Location:** `Tests/AdventureRPGTests/AppIntentTests.swift:34-58`
- **What:** Same 25-line commented `@Test` with the same documented crash rationale as round 7.
- **Action:** Unchanged — eventually move to an out-of-process `AppIntentsTesting` target.
- **Severity:** Low

### 9.17 Small dead-code cleanup group
- **Location:** `Modules/GameRPG/GameViews/GameTableWindowButton.swift:78,95` (commented-out `dismissWindow(SceneId.game)`/`openWindow(SceneId.game)` lines, superseded by `pushWindow`/`GameWindowToggle`); `Modules/GameRPG/Table3D/GameEquipment.swift:516` (commented `.dodecahedron(...)` alternative beside the live `.icosahedron(...)` line); `Modules/CoreRPG/Sheet/TableSheetView.swift:35` (commented `.scrollTargetLayout()`, left behind after switching to `ScrollPosition`-based scroll-to-entry)
- **What:** Three small leftover commented-out lines, none explained by a surrounding comment for why they're kept rather than deleted.
- **Action:** Delete all three, or add a one-line comment if any is a deliberate "don't re-add this" marker. Quick win — see §2.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **The per-module boilerplate genericization (§9.1-§9.4) has now persisted across 8 audit rounds.** `ImportController`/`ExportController`/`ItemController`/`FolderListController`/App-Intents-`Entity` are all the same shape, hand-copied 10-12 times each, and none have been consolidated despite being flagged every round. This is the single highest-leverage refactor left in the codebase — a few generic CoreRPG base types would eliminate hundreds of near-duplicate lines in one pass and make future module additions cheaper.
2. **Apply the cancel-then-replace-with-staleness-timeout pattern uniformly.** `fogOfWarTask`/`roomActionTask` and `viewportPanStart`/`viewportPanLastUpdate` demonstrate this pattern works well and is already the house style for gesture state that might never see `.onEnded`. §5.1's `tableMoveLastTranslation` is the one sibling that still lacks it — worth a quick sweep for any other un-guarded gesture-state variable following the same shape.
3. **When merging a duplicated Master/Player view pair, follow `GameTableSideMenu`'s own precedent** (§9.6, §9.7) — it already merges Master/Player into one file behind an `isMaster` flag. Apply the same shape to `MasterGameScreen`/`PlayerGameScreen`, `MasterOverlayMenu`/`PlayerOverlayMenu`, and the new `MasterGameWindowButtonView`/`PlayerGameWindowButtonView`.
4. **Route every remaining raw `MainActor.assumeIsolated` call (§3.3) through the existing `assumeMainActorIsolated` helper** — the helper exists specifically so hardening work has one place to land; five call sites currently bypass its own stated purpose.

---

## 11. What was NOT audited

- Algorithmic correctness of the Foundry VTT domain-mapping logic itself (`FoundryVTTDomainMapper.swift`) — only structural/duplication/dead-code aspects were reviewed, not whether the mapping is semantically correct against Foundry's data model.
- Build settings, scheme configuration, Xcode project structure beyond what's visible via shared schemes and build settings.
- Third-party dependency internals — the vendored `NavigatorUI` package (`Modules/CoreRPG/Navigator/`) was treated as a black box except where its `deinit`s were cited for §3.3; RealityKit/TabletopKit/GroupActivities/FoundationModels framework internals are Apple black boxes.
- Deep test-coverage assessment. `Tests/` was scanned for markers (TODO/FIXME, commented-out tests) but not reviewed for coverage gaps or test quality.
- Localization wording — the audit can note untranslated strings but did not assess translation quality; `Resources/InfoPlist.xcstrings` was not reviewed (it shows as locally modified in git status but outside this audit's scope).
- Performance profiling via Instruments. This audit identifies *potential* hot paths (per-body recomputation, repeated ZIP parsing) from source reading, not measured traces.
- StoreKit 2 product configuration (`InAppModel.swift`/`InAppView.swift`) was confirmed to use correct, modern APIs (`Product`/`Transaction`/`AppStore.sync()`) with no code-level bugs found, but App Store Connect product catalog alignment was not checked.
- Metal shader correctness — no `.metal` files exist in this repo (confirmed via full-tree search), so this is not applicable rather than skipped.
- Entitlements files were spot-checked only for the specific items already flagged (RPGShare's `aps-environment`, confirmed removed); a full per-target entitlements review against each target's actual capability usage was not performed.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line.

- **§5.1** — open `Modules/GameRPG/Table3D/GameTableView.swift`, lines 533-543 and 548. Compare `viewportPanStart`/`viewportPanLastUpdate` (has a staleness guard, `isViewportPanStale()`) against `tableMoveLastTranslation` (declared at 548, reset only at 701/728, no staleness check anywhere in `applyTableMoveDelta` at 737-745).
- **§6.1** — open `Modules/GameRPG/SharePlay/RPGSharePlayController.swift`, lines 774 and 838; both interpolate `.debugDescription` at `privacy: .public`. Then open `Modules/GameRPG/Model/GameNetworkModel.swift:988-990` and confirm `debugDescription` interpolates `sender.name`.
- **§7.1** — open `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:17-36` and confirm it constructs its own `FoundryPackageDataSource` rather than accepting one from a caller or the shared cache.
- **§8.1** — open `Modules/CoreRPG/Sheet/SheetEntryAddButton.swift:15` and `SheetEntryAddGroupButton.swift:14`; compare against `Modules/CoreRPG/Sheet/TableSheetView.swift:40` (`withAnimation(accessibilityReduceMotion ? nil : .smooth, ...)`) in the same folder.
- **§9.6** — open `Modules/GameRPG/GameViews/MasterGameWindowButtonView.swift` and `PlayerGameWindowButtonView.swift` side by side; the bodies are ~90% identical.
- **§9.7** — open `Modules/GameRPG/GameViews/GameTableSideMenu.swift:28-35` and read its own doc comment citing `MasterModuleWindowMenu.modules`/`PlayerSideMenu.modules` as the arrays it mirrors.
- **§9.8** — open `Modules/DiceRPG/Space/HandTrackingModel.swift:110-176`; the method body is a guard clause followed by a large block comment and `return nil`. Grep the repo for either method name to confirm zero call sites.
- **§9.13** — run `find . -name "*.swift" -not -path "./.git/*" -not -path "*/Tests/*" -exec wc -l {} \; | awk '$1>500' | wc -l` — returns 52.

If any finding doesn't reproduce when you visit the line, flag it with the specific reference and it'll be re-investigated in the next round.
