# MasterRPG Code Audit — uncommitted changes (post-audit-22 fixes)

Generated 2026-10-31 against `38393b789` (`develop`) plus the working tree. **Scope: the uncommitted diff only** — 122 files changed (+991 / −762), 7 new files (`SheetNumberLimit`, `SheetLinkGuard`, `WeatherLimits`, `LazyBox`, two test files, `Docu/CODE_AUDIT_22.md`), 11 pure renames into `Modules/CoreRPG/Intent/`. The diff is the implementation of the fixes recorded in `Docu/CODE_AUDIT_22.md` §13, so this audit asks one question: *are those fixes correct, complete and free of new regressions?* Code outside the diff was read only where a changed line depends on it.

**Compiler ground truth.** Clean Debug builds into fresh derived-data folders (Xcode 27.2): MasterRPG iOS Simulator **succeeded, 0 Swift warnings**; MasterMac **succeeded, 0 Swift warnings**; MasterTV (tvOS Simulator) and MasterRPG (visionOS Simulator) **succeeded, 0 Swift warnings** (the only diagnostics are the usual "appintentsmetadataprocessor: Metadata extraction skipped" notices). **No tests were run**, and the test targets were not compiled (the app schemes do not build them).

**Method.** I read the whole diff (3 900 lines) myself and re-opened the surrounding code for every behavioural claim. No sub-agents were used: the change set was small enough to read in full. **[verified]** = I opened the cited lines and confirmed the behaviour; **[unverified]** = reasoned from code, not run.

**Result in one line:** no Critical or High findings. The audit-22 fixes are sound in structure; the problems are one fix that silently does less than its comment says (§5.1), one shared-property change with side effects (§5.2), one security boundary that fails open (§6.1), and a test gap on the riskiest new logic (§10.1).

---

## 1. Executive summary

1. **[Medium] Sync's `apply` silently adds nothing when its re-scan fails, and reports success** — §5.1 — `Modules/CoreRPG/Controllable/CloudScanController.swift:57-75` [verified].
2. **[Medium] Player-package redaction fails open: the default of `ExportAudience.isPlayerPackage` is `false`** — §6.1 — `Modules/CoreRPG/Controllable/ExportControllable.swift:12-14, 387` [verified].
3. **[Medium] `MapEntryModel.rect` changed for a thumbnail fix, but two unrelated callers use it for hit testing** — §5.2 — `Modules/MapRPG/Model/MapEntryModel.swift:107-111`, `MapModel+Geometry.swift:235-237`, `View/AdditionalEntryRow.swift:44-45` [verified].
4. **[Medium] Hidden rooms still reach players with their name and geometry; hidden pins as blank shells** — §6.2 — `Modules/MapRPG/Model/MapSnapshot.swift:147-170` [verified]. Needs a design decision.
5. **[Medium] The player package still follows every link in a shown room's text and ships the linked map, audio, pdf, photo, dice and table items — players should receive only the map and its pin photos (the pin photos via the map request)** — §5.3 — `Modules/MapRPG/Controller/ExportController.swift:72-128` [verified].
6. **[Low] Calculator fix is partial: `1/3*3` is now 0.999999999999999, not 1, and no test pins the behaviour** — §5.4 — `Modules/CharacterRPG/Model/Calculator.swift:118-129` [verified by arithmetic].
7. **[Medium] The riskiest new logic has no tests** (apply-confirmation, player export, hidden-pin filter, `deleteAll(keeping:)`, link guard) — §10.1.
8. **[Low] `SheetLinkGuard` keeps its cycle stack in static state that is only correct while sheet building stays synchronous** — §3.1 — `Modules/CoreRPG/Sheet/SheetLinkGuard.swift:21-35` [verified].

---

## 2. Quick wins (≤30 min)

- Fix the stale reference `ExportAudience.players` in the doc comment of `playerExportData` (§5.9) — `ExportControllable.swift:28`.
- Make `apply` return something other than `.synced(0,0,0,0)` when the re-scan failed, and correct the "Additions only need the files to be there" comment (§5.1).
- Add one assertion for `1/3*3` to `ValueEntryModelTests` so the §5.7 claim is pinned either way (§5.4).
- Remove the iOS/macOS duplicate of `attachments(of:)` in `ShareViewController.swift:57,71` (§9.3).
- `CloudFolderScan.files(below:)` is now used only by tests — mark it as such or point the tests at `listing(below:)` (§9.2).

---

## 3. Concurrency

### 3.1 `SheetLinkGuard` cycle stack is static mutable state
- **Location:** `Modules/CoreRPG/Sheet/SheetLinkGuard.swift:21-35`
- **What:** `building` is a `static var` on a `@MainActor` enum, inserted before and removed after the synchronous `sheet(...)` call.
- **Why:** Correct today because every module's `sheet(...)` is synchronous. If any module's sheet builder ever gains an `await`, two interleaved builds share one set and a legitimate link would be refused as a "cycle" (nil sheet, no error). Nothing in the type or its tests enforces the precondition.
- **Action:** Keep, but state the precondition in a test (a module sheet builder that suspends must fail it) or pass the stack down as a parameter instead of sharing it.
- **Severity:** Low

### 3.2 Reviewed without findings
`CancellableWait` in `RemoteDownloadsInFlight.swift` (finish-before-wait and cancel-before-wait both resolve correctly), the `Mutex<Progress?>` cancellation in `ItemProviderImporter.loadDataRepresentation`, `GameRoot.stopGameTaskToken` (token-owned clearing, no suspension between teardown end and clearing), and `isStartingGame` (set after the last suspension, cleared by `defer`).

---

## 4. API modernity

_No findings._ The diff moves in the right direction: `(name as NSString)` → `URL(filePath:)` in `CloudFolderScan`, `formatNumber` stays on `FormatStyle`, `Task.sleep(for:)` untouched, `Combine` imports removed from files that no longer use it (build confirms nothing needed them).

---

## 5. Bugs / logic errors

### 5.1 `apply` drops additions silently when the re-scan fails
- **Location:** `Modules/CoreRPG/Controllable/CloudScanController.swift:57-75`
- **What:** `apply` re-scans first; `confirmed` starts as an empty plan and is only filled when the re-scan returns `.plan`. If the re-scan returns `nil` (cancelled) or `.unreachable`, nothing is added, moved or trashed — yet the comment says "Additions only need the files to be there", and the method still returns `.synced(added: 0, folders: 0, moved: 0, trashed: 0)`.
- **Why:** The user taps Sync, sees a success state with zeros and has no hint that iCloud was unreachable at that moment. The comment and the code disagree about the intended behaviour. Smaller related point: the re-scan runs before `DataMutationCoordinator.begin()`, so the library can change between the check and the write (the `known` filter after `begin()` limits the damage to duplicates, not to wrong trashing).
- **Action:** Decide the intended behaviour. Either keep the additions from the old plan (matching the comment) or add a third `Outcome` such as "folder not reachable, nothing changed" and show it. Fix the comment either way.
- **Severity:** Medium
- **Note (verified OK):** the id comparison that the confirmation relies on is stable — `plan(...)` derives item and folder ids from module and path (`derivedId`, `CloudFolderScan.swift:~345`), so ids match across two scans.

### 5.2 `MapEntryModel.rect` is shared by three callers with different needs
- **Location:** `Modules/MapRPG/Model/MapEntryModel.swift:107-111`; callers `Modules/MapRPG/Controller/CacheController.swift:38` (thumbnail crop), `Modules/MapRPG/Model/MapModel+Geometry.swift:235-237` (hex-grid toggle), `Modules/MapRPG/View/AdditionalEntryRow.swift:44-45` (pin counter)
- **What:** The size grew from `size + 25` to `size + 50` so the thumbnail crop has a symmetric 25-pt margin. The same property decides which "story" rooms are switched on together with a hex grid (`intersects`) and which pins the row badge counts (`contains`).
- **Why:** Rooms within 25 pt of a hex grid's right/bottom edge now count as overlapping and are revealed with it; pins up to 25 pt outside a room's right/bottom edge now count in its badge. Both are silent behaviour changes in game-master-visible logic, made for a rendering fix, and no test covers `rect`.
- **Action:** Keep `rect` as it was and add a dedicated thumbnail rect (or pass the margin to `createThumbnail`). If the new geometry is wanted for the other two, say so and add tests.
- **Severity:** Medium

### 5.3 The player package still follows room-text links; players should get only the map and its pin photos
- **Location:** `Modules/MapRPG/Controller/ExportController.swift:72-128` (link loop at `:91-128`, pin photos at `:81-84`, player-pin photos at `:141-146`); receiving side `Modules/GameRPG/Controller/PlayerController+MapPresentation.swift:77-92`
- **What:** The first version of this finding was framed as "a revealed room's linked items may be missing on the player". The intended design is the opposite: a player never receives items linked from a room's text (photo, character, audio, pdf, dice, table, another map). The only item a player needs is a pin's `photoId`, and that arrives through the map request (`requestMissingMapImages`, once per photo per connection). The diff narrows the link loop to *shown* rooms (`exportedEntries`) but keeps it. So for a player package the exporter still adds, for every shown room, linked audio, dice, pdf, photo and table items to the package, and — through the breadth-first walk — every linked **map**, each of which then exports its own links and pins. Characters are already skipped in game mode (`!isGameMode`).
- **Why:** A shown room that links a PDF, a music track or another map causes the game master's device to push those files and that map to every player, although none of it was shown to them. A linked map is the worst case: a whole second map package, with its own pin photos, reaches players without the master revealing it. It also makes the package larger and slower on SharePlay, where size already matters. Because players are not meant to receive link targets, the reveal-time concern from the first version does not arise.
- **Action:** For a player package skip the link loop entirely (no links of any module, including `.map`) and keep only: the map's background photo, the pin photos of shown pins and the player pins' photos. Decide whether the shown pins' photos should stay in the package at all or come only from the map request, as described; if only from the request, drop the `exportedPins` photo collection too. Keep the loop unchanged for Save Game and library export (the `ExportAudience` flag already distinguishes them). Add a test: a map with a shown room linking another map, an audio and a pdf must export exactly the map and its photos through `createGameData`.
- **Severity:** Medium
- **Related:** §6.1 (the same flag decides this), §6.2 (what else in the package is more than a player needs).

### 5.4 Calculator fix is partial and untested
- **Location:** `Modules/CharacterRPG/Model/Calculator.swift:118-129`
- **What:** Intermediate results are now formatted with up to 15 fraction digits instead of 3. `1/3` becomes `0.333333333333333`, times 3 is `0.999999999999999` — closer than `0.999`, but still not 1. The audit-22 status table calls §5.7 "Fixed" for the calculator.
- **Why:** A sheet formula such as `HP/3*3` still differs from `HP` by 1e-15, which matters wherever the result is compared with `==` or floored. The root cause (re-parsing text between steps) is unchanged. No test was added for this file in the diff.
- **Action:** Either carry `Double` between steps instead of text, or round the final result to a sensible precision (e.g. 12 digits) in `calculate`. Add the `1/3*3` and `0.1+0.2` cases to the existing tests.
- **Severity:** Low

### 5.5 `GeneratorController.request` can wait forever on a predecessor
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:169, 208-209`
- **What:** The new request awaits `previousTask?.value` before sending. If the cancelled predecessor is stuck in a stream that does not honour cancellation, the new request never starts and `isLoading` stays true.
- **Why:** Trades "already responding" errors for a possible silent hang.
- **Action:** Bound the wait (race it against a short timeout) or surface a state the user can cancel.
- **Severity:** Low

### 5.6 Interrupted-session recovery now leaves a crashed game invisible for up to 24 h
- **Location:** `Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift:16-30`
- **What:** `recoverInterruptedSessions` skips sessions idle for less than 24 h, so another device's live session is not completed. The summary predicates use `isComplete == YES` (lines ~223, 266, 305).
- **Why:** The price of the §5.4 fix: a game cut off by a crash or force-quit does not appear in statistics until a launch happens a day later. That is a sensible trade, but it is only documented in the code comment, not in what the user sees.
- **Action:** Accept; optionally recover immediately when the session's originating device is this device (needs a device id on the session).
- **Severity:** Low

### 5.7 `discardUnsavedStatistics` is unproven for pending deletes
- **Location:** `Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift:444-455`
- **What:** After a failed save, inserted statistics objects are deleted and updated/deleted ones get `refresh(_, mergeChanges: false)`. Whether `refresh` un-does a *pending delete* of the object is not guaranteed by the API contract.
- **Why:** If it does not, a retry after a failed `deleteAll` would still carry the deletes. Only the insert path is clearly correct.
- **Action:** Add a test with an injected save failure covering both an unsaved insert and an unsaved delete; if the delete case fails, use `context.undo`-style handling or re-fetch.
- **Severity:** Low [unverified]

### 5.8 `SheetLinkGuard` expands a cycle once more than needed
- **Location:** `Modules/CoreRPG/Sheet/SheetLinkGuard.swift:29-32`
- **What:** The item whose sheet is being built at the top level is not registered. Character A → Map M → A builds A's sheet a second time inside M before A→M is refused.
- **Why:** One duplicate nested sheet is shown for a cyclic link instead of none. Harmless for the stack-overflow fix; slightly odd output.
- **Action:** Register the root item at the entry point of sheet building, or accept and document.
- **Severity:** Low

### 5.9 Stale doc comment names a type that does not exist
- **Location:** `Modules/CoreRPG/Controllable/ExportControllable.swift:28`
- **What:** "Only called inside `ExportAudience.players`" — the flag is `ExportAudience.isPlayerPackage`.
- **Why:** Misleads the next person who looks for the symbol.
- **Action:** Correct the comment.
- **Severity:** Low

### 5.10 Imported rule text keeps visible backslashes outside markdown rendering
- **Location:** `Modules/RuleRPG/Model/RuleModel+FoundryFactory.swift:182-194` (`inert`)
- **What:** Imported values are escaped with backslashes and zero-width spaces before being put into markdown. The in-app renderer (`AttributedString(markdown:)`) hides the backslashes.
- **Why:** The raw content is also what search matches against and what intents/excerpts return. A Foundry path such as `system.abilities.dex_mod` is stored as `dex\_mod` and is not found by searching `dex_mod`; plain-text consumers show the backslash.
- **Action:** Acceptable for metadata fields; if search over these values matters, normalise (strip `\` and U+200B) in the search index.
- **Severity:** Low

### 5.11 A second `startGame` returns silently
- **Location:** `Modules/GameRPG/Root/GameRoot.swift:421-423`
- **What:** The new `isStartingGame` guard returns without any signal.
- **Why:** Correct for the double-tap, but an intent calling start while the UI is starting reports success with no game of its own.
- **Action:** Return a result or log the dropped call.
- **Severity:** Low

---

## 6. Security

### 6.1 Player-package redaction fails open
- **Location:** `Modules/CoreRPG/Controllable/ExportControllable.swift:12-14, 384-390`; `Modules/CoreRPG/Controllable/GameControllable.swift:252-275`
- **What:** The redaction is switched on by a task-local that `createGameData` sets to `true`; the default is `false`, and `playerExportData` returns `nil` (= unredacted) in the protocol-extension default. I checked the export path for anything that would drop the task-local — no `Task.detached`, `DispatchQueue` or `runOffCallerExecutor` appears in `ExportControllable`, `GameControllable` or the module `ExportController`s — so **today it propagates correctly** [verified by grep]. The unredacted state is simply the default.
- **Why:** A security boundary whose failure mode is "everything leaks". A future `Task.detached` or off-executor hop in the export chain, or a new code path that calls `rootExportController.export` for players without `createGameData` (today only `createGameData` and Save Game do), silently ships the game master's hidden rooms and pins again — and no test would notice.
- **Action:** Invert the default for the network path: pass the audience explicitly as a parameter of `export`, or make the task-local an enum whose default is `.unspecified` and have `encodedForExport` refuse to run the map exporter when it is unspecified. Add a test that exports a map with a hidden pin through `createGameData` and asserts the bytes contain neither its name nor its location.
- **Severity:** Medium

### 6.2 Hidden rooms keep their name and geometry in the player package; hidden pins remain as shells
- **Location:** `Modules/MapRPG/Model/MapSnapshot.swift:147-170`, used by `Modules/MapRPG/Controller/ExportController.swift:56-62`
- **What:** For hidden rooms only `content` is cleared; `name`, coordinates and `isHexGrid` stay. Hidden pins stay in the list with name, photo, character, position, players and health cleared. The live `.mapState` now omits hidden pins entirely, so the two paths are inconsistent.
- **Why:** A player inspecting the package can learn that a room called "Treasure Vault" exists, its outline, and how many hidden pins there are. Whether that is acceptable (rooms are needed for the fog mask) is a design choice the code does not state.
- **Action:** Ask the game master's-view owner: clear `name` of hidden rooms, and filter hidden pins out of the exported list as the live path does. Geometry can stay if the fog renderer needs it.
- **Severity:** Medium (design decision)
- **Note (verified OK):** `MapModel.version` is derived from `hexMapScale + pinScale` only (`MapModel+Sync.swift:182`), so the redacted package and the master's stored map report the same version — no re-request loop.

### 6.3 Group-event cap — reviewed without findings
`maximumGroupEventPayloadBytes` (256 KiB) is applied in `isPlayerGroupEvent` before relay; the new test covers at-limit and over-limit for pin, dice and space events. Dice roll events carry a full dice model, a few KB in practice.

---

## 7. Performance

### 7.1 `apply` now walks and hashes the folder twice per tap
- **Location:** `Modules/CoreRPG/Controllable/CloudScanController.swift:57-60`
- **What:** `apply` runs a full `scan()` (folder walk plus hash candidates) and `newItemHashes` (hash of every new file) before writing.
- **Why:** On a large iCloud folder the Sync button now takes about as long as opening the sheet did. The work is off the main actor (`@concurrent`), so the UI stays responsive, but there is no progress state for the second pass.
- **Action:** Accept, or show the existing scanning state while `apply` re-checks.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 Reduce-motion handling is applied in one view only
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerMiniBarView.swift:47-52, 68-73, 93-103`
- **What:** The three `withAnimation` calls of the mini bar now respect Reduce Motion via `.default.reduced(if:)`; other unconditional `withAnimation` calls in the same module (e.g. `QuickEditorButtonView`) do not.
- **Why:** Inconsistent accessibility behaviour between neighbouring controls.
- **Action:** Apply the same helper in `QuickEditorButtonView` and the other `withAnimation` sites you touch next.
- **Severity:** Low

### 8.2 `QuickEditorButtonView` generic constraint tightened
- **Location:** `Modules/CoreRPG/Buttons/QuickEditorButtonView.swift:5`
- **What:** `Value: Numeric` became `Value: Numeric & Comparable` on a `public` type.
- **Why:** Source-breaking for a caller with a non-comparable numeric type; all in-repo callers use `Int`/`Double`, so no break here (the build passes).
- **Action:** None needed unless the type is used outside the repo.
- **Severity:** Low

### 8.3 Reviewed without findings
`LazyBox` in `CloudsView`/`StarsView`/`StormView` (discarded `State` initial values no longer build the heavy object; mutation happens in the same `Canvas` pass as before), `ColoredEditRowViewModifier` (contrast-aware opacity), `CloudFolderScanModel.selectedPlan` (now cached on selection change instead of recomputed per body), `DetailSelectionEditorView` (per-map replacement filter).

---

## 9. Dead code / duplication / refactor

### 9.1 `entryHit` consolidation is incomplete
- **Location:** `Modules/CoreRPG/Controllable/SearchControllable.swift:248-275`
- **What:** The shared `entryHit` replaced five copies of the entry-hit construction; 15 other `SearchResult(` constructions remain in the modules.
- **Why:** Expected — the others build item hits, not entry hits. Listed so nobody assumes the duplication is gone.
- **Action:** None.
- **Severity:** Low

### 9.2 `CloudFolderScan.files(below:)` is test-only now
- **Location:** `Modules/CoreRPG/Files/CloudFolderScan.swift:205`
- **What:** The only callers are `Tests/CoreRPGTests/CloudFolderScanTests.swift:97,111,116`.
- **Why:** A production wrapper kept alive by tests.
- **Action:** Point the tests at `listing(below:)` and delete it.
- **Severity:** Low

### 9.3 `attachments(of:)` duplicated for iOS and macOS
- **Location:** `Sources/RPGShare/ShareViewController.swift:57, 71`
- **What:** Two identical private helpers in the two platform classes.
- **Why:** Drift risk.
- **Action:** One file-private free function above the `#if`.
- **Severity:** Low

### 9.4 Dead code removed — verified safe
`existingUUIDsInContext`, `resetSelectedGameMaster`, `RouteActions.tabId`, `KnownRoutes.mainTabId`, the `rollHistory` key, the `migrationKey`, stale string-catalog entries and the TV plist's mis-placed entitlement keys: no remaining reference in `Modules`, `Sources` or `Tests` (grep), and the iOS and macOS builds pass. `fetch` was removed from `UIBackgroundModes`: no `BGTaskScheduler`/`performFetch` use exists in the code [verified by grep].

---

## 10. Cross-cutting recommendations

### 10.1 Test the new logic that carries the risk
The diff adds tests for `SheetNumberLimit`, `WeatherLimits`, the group-event cap and the idle-recovery age. It adds **none** for: `CloudScanController.apply`'s confirmation filter (§5.1), `playerExportData` / `ExportAudience` (§6.1), `pinsVisibleToPlayers` (the changed existing test only flips two `isShown` flags), `deleteAll(keeping:)` and `discardUnsavedStatistics` (§5.7), `SheetLinkGuard` (§3.1, §5.8), `MapEntryModel.rect` (§5.2), `Calculator.formatNumber` (§5.4), `RuleModel.inert`, `CaptureFolderManager` stale-scan cleanup, the new map scale of walls/pointer. The first three are the ones whose failure is silent and user-visible.
- **Severity:** Medium

### 10.2 Security redaction should fail closed
See §6.1. The same pattern — "default = full data, redaction opt-in" — also describes `MapSnapshot.redactedForNonMaster` (callers must remember to call it). Prefer APIs where the network-bound type cannot be built without the redaction step.

### 10.3 Keep behaviour changes out of shared properties
§5.2 is the second time in this codebase a shared computed property was changed for one consumer (compare the earlier `URL.commandKey` regression that misread entry-scoped table links). A review checklist item — "who else reads this property?" — would have caught it.

---

## 11. What was NOT audited

- Anything outside the uncommitted diff, except lines a changed line depends on.
- Only Debug builds were made; Release-only compilation differences (e.g. `#if DEBUG` code) are not covered.
- **Tests were not run and test targets were not compiled.** `GameStatisticsDataControllerTests`, `GameMessageShapeTests` and `WeatherRPG` tests were edited in the diff; whether they pass is unknown. The known-failing family in the project memory is unchanged.
- Runtime behaviour of everything marked [unverified] (§5.7), in particular two-device checks of thumbnail alignment on rotated maps, the cloud-folder sync with an unreadable subfolder, and the SharePlay path with the 256 KiB cap.
- String-catalog wording and German/Thai translations; the three new strings were only checked for presence.
- Xcode project/pbxproj changes: none are in the diff (file moves into `Modules/CoreRPG/Intent/` are folder-based).
- Instruments traces; no profiling was done.

---

## 12. Verification

No Critical or High findings. The Medium claims were verified as follows.

- **§5.1** — `Modules/CoreRPG/Controllable/CloudScanController.swift`, lines 57-75: `confirmed` is initialised empty at line 65 and only assigned inside `if case let .plan(currentPlan)? = current`; the comment at line 64 says additions only need the files; the method returns `.synced` at the end regardless. Ids stable: `CloudFolderScan.swift` `plan(...)` uses `derivedId(module:path:isFolder:)` for new folders and items.
- **§5.2** — `MapEntryModel.swift:107-111` (`size + 50`); `MapModel+Geometry.swift:235-237` (`rect.intersects` over other rooms in `toggle`); `AdditionalEntryRow.swift:44-45` (`entryRect.contains($0.location)`).
- **§5.3** — `ExportController.swift` (Map): lines 72-75 filter `exportedPins`/`exportedEntries` by `isShown` only when `ExportAudience.isPlayerPackage`; lines 91-128 still run `LinkReplaceController.links(for:)` over the remaining entries and insert audio, dice, pdf, photo and table ids and append `.map` links to `childIds` (the breadth-first walk then exports those maps); only `.value` is skipped in game mode (line 128). `PlayerController+MapPresentation.swift:77-92` requests pin photos only. The design statement (players get no link targets, only pin photos via the map request) is from the project owner.
- **§5.4** — arithmetic: `1/3` formatted at 15 fraction digits is `0.333333333333333`; `× 3` is `0.999999999999999`; `Calculator.calculate` returns that value parsed back (`Calculator.swift:30`).
- **§6.1** — `ExportControllable.swift:12-14` (`@TaskLocal ... isPlayerPackage = false`), `:80-82` (default `playerExportData` returns `nil`), `:384-390` (`encodedForExport`); `GameControllable.swift:270-275` (`withValue(true)`). grep for `Task.detached|DispatchQueue|runOffCallerExecutor` in `Modules/CoreRPG/Controllable`, `Modules/CoreRPG/Files` and the module `ExportController`s returned nothing in the export path.
- **§6.2** — `MapSnapshot.swift:147-170`: entries get only `content = ""`; pins get name, photo, character, location, players, dead/highlight and health cleared but stay in the list; `GameController+Sync.swift:27-50` omits hidden pins from `.mapState`.
- **§10.1** — `git status` lists only `Tests/CoreRPGTests/SheetNumberLimitTests.swift` and `Tests/WeatherRPGTests/WeatherLimitsTests.swift` as new tests; the modified tests are `GameMessageShapeTests`, `GameStatisticsDataControllerTests`, `CharacterValueChangeTests`, `EditControllerTests`, `MapRPGTests/GameControllerTests`, `WeatherRPGTests/DataControllerTests`.

**Reviewed and sound:** statistics attribute names in `deleteAll(keeping:)` (`sessionID` on events and participants, `uuid` on sessions — match `GameStatistics.xcdatamodel`); `MapModel.version` unaffected by redaction; BatteryMonitor has a single construction site (`BatteryView.swift:18`) and the view starts and stops it; `TabbarPlacement` now honours its parameter (its only caller passes `.sidebar`, so behaviour on iOS 27 is unchanged); `TableGenerationController` cap counts the occurrence tree correctly (children of the occurrence being rebuilt are excluded); the `maxOccurrenceCount` check sits in `rebuildChildren`, which is the only place children are created after the first roll.

---

## 13. Fix status

Fixed 2026-10-31 after the findings above. Design decisions by the project owner: §5.1 show "not reachable" and apply nothing; §5.3 the player package carries the map and its background only, pin photos come through the map request; §6.2 clear hidden room names and leave hidden pins out of the package; §5.4 carry exact `Double` values between calculator steps.

| § | Status | What changed |
|---|--------|--------------|
| 3.1 | Documented | `SheetLinkGuard` states its precondition (synchronous sheet builders) in its doc comment. No code change: a test would need a full `RootManager`. |
| 5.1 | Fixed | `CloudScanController.apply` returns the new outcome `.unreachable` when the re-scan fails and applies nothing; the sync sheet shows its existing "iCloud folder not available" state. Comment corrected. New test: a file that went away after the plan was shown is not added (`FolderAuditPhotoTests`). |
| 5.2 | Fixed | `MapEntryModel.rect` is back to its old geometry; the thumbnail crop uses the new `thumbnailRect` (`CacheController`). Test `rectAndThumbnailRect`. |
| 5.3 | Fixed | In a player package the Map exporter no longer follows room-text links (maps, audio, pdf, photo, dice, table) and no longer collects pin or player-pin photos; only the background photo remains. Save Game and library export are unchanged. Tests: `exportingForPlayersSkipsLinks`, `ExportAudienceTests`. |
| 5.4 | Fixed | Calculator steps keep 17 significant digits (exact for a `Double`); the final result is rounded to 15 significant digits. `1/3*3` is 1, `0.1+0.2` is 0.3. Test `calculateKeepsPrecision`. |
| 5.5 | Fixed | `GeneratorController.request` waits for a cancelled predecessor for at most 5 seconds (`GeneratorTaskWait`). |
| 5.6 | Accepted | The 24 h recovery age stays; it is documented in the code and in this report. |
| 5.7 | Fixed | `discardUnsavedStatistics` now calls `processPendingChanges()`; tests show a pending insert is dropped and a pending delete undone (`discardsUnsavedStatistics`). `hasChanges` stays true after a refresh, so the test asserts the three change sets instead. |
| 5.8 | Documented | The unregistered root item is described in the `SheetLinkGuard` doc comment; no code change. |
| 5.9 | Fixed | Stale `ExportAudience.players` comment corrected (the type is now an enum with `.owner` and `.players`). |
| 5.10 | Accepted | Escaped imported rule text stays escaped; it only affects metadata fields. Test `importedTextIsInert` pins the escaping. |
| 5.11 | Fixed | A dropped second `startGame` is logged. |
| 6.1 | Partly fixed | `ExportAudience` is an enum (`.owner` / `.players`). The network overload `export(itemIds:into:)` now sets `.players` itself, besides `createGameData`, so any path that builds a package through the network entry point is redacted. The default stays `.owner`: the export panel resolves its ids from the UI outside any export (`InternalRoute.export`) and would otherwise lose items. A new path that bypasses both entry points is still unredacted. `ExportAudienceTests` also documents that a `Task.detached` drops the audience. |
| 6.2 | Fixed | `MapSnapshot.redactedForNonMaster` clears hidden room names as well as text and leaves hidden pins out, for the package and the live content update. Test `playerExportDataIsRedacted`; `pinsVisibleToPlayers` test for the live map state. |
| 7.1 | Accepted | The second folder walk in `apply` stays; the work is off the main actor. |
| 8.1 | Fixed | `QuickEditorButtonView` respects Reduce Motion. |
| 8.2 | No change | Constraint tightening has no caller outside the repo. |
| 9.1 | No change | The remaining `SearchResult(` sites build item hits, not entry hits. |
| 9.2 | Fixed | `CloudFolderScan.files(below:)` removed; the tests use `listing(below:)`. |
| 9.3 | Fixed | One file-level `shareAttachments(of:)` in `ShareViewController.swift` for iOS and macOS. |
| 10.1 | Fixed (partly) | New tests for apply confirmation, player export, redaction, hidden-pin filter, `deleteAll(keeping:)`, `discardUnsavedStatistics`, `rect`/`thumbnailRect`, calculator precision, `inert`, `ExportAudience`. Still without tests: `SheetLinkGuard` (needs a full `RootManager`), `CaptureFolderManager` stale-scan cleanup, the wall/pointer scaling in the map editor. |
| 10.2 | See 6.1 | |
| 10.3 | No code | Review habit. |

**Verification:** iOS test run of the CoreRPG, Character, Map, Rule, Photo and Weather test targets plus the GameRPG classes that build player packages (`MasterPlayerControllerTests`, `MapMasterMessageFlowTests`, `PlayerControllerTests`, `SavedGameRoundTripTests`, `SimpleFileFlowTests`, statistics, message shape): all passed. Full GameRPG and the remaining test targets were not run.
