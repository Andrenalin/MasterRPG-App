# MasterRPG Code Audit

Generated 2026-09-13. Scope: ~270,361 lines across 2,032 Swift files (no Metal kernels in this project) spanning 15 feature modules (AdventureRPG, AudioRPG, CharacterRPG, CoreRPG, DiceRPG, GameRPG, GeneratorRPG, MapRPG, PdfRPG, PhotoRPG, RolePlayGameKit, RuleRPG, SpaceRPG, TableRPG, WeatherRPG) and the app targets MasterRPG, MasterMac, MasterTV, RPGShare, DiceRollerWidgetExtension. `Docu/` (39 prior audit reports and design docs) is treated as reference, not re-audited — this report only records genuinely new findings in the current code.

This is the **13th** full/targeted audit round for this codebase (see `Docu/CODE_AUDIT_1.md` through `CODE_AUDIT_12.md` plus 8 targeted audits). The codebase is unusually mature as a result: a clean `xcodebuild clean build` of the `MasterRPG` scheme produced **zero Swift compiler warnings** under `SWIFT_STRICT_CONCURRENCY = complete`, and most categories this skill normally expects to find in bulk (dead code, `print()` hygiene, magic constants, legacy filenames, `TODO`s) came back confirmed-clean on direct inspection. The findings below are the genuine gaps that remain, plus three real bugs surfaced by close reading of the GameRPG master/player sync subsystem, which this round targeted specifically because of an uncommitted in-flight diff there.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

---

## 1. Executive summary

1. **[High] `toggleConnection` join flow can hang forever** — §3.1 — `Modules/GameRPG/Player/PlayerNetworkController.swift:76-95`. A double-tap/race on "Join" or an unhandled `NWConnection.State.waiting` permanently strands the join spinner with no error and no recovery short of a force-quit.
2. **[High] Force-unwrap after `await` suspension can crash `startMaster`** — §5.1 — `Modules/GameRPG/Root/GameRootModel.swift:613`. `gameModel.selectedAdventure!` is force-unwrapped after three intervening `await`s, even though a safe local (`id`) captured earlier is sitting unused.
3. **[High] Unbounded recursion in item/folder duplication** — §5.2 — `Modules/CharacterRPG/Controller/EditController.swift:311-326, 339-362`. No cycle/depth guard, unlike the sibling recursive walk in the very same file that already uses `RecursionLimits`.
4. **[High] CRDT merge silently drops a field on conflict** — §5.3 — `Modules/DiceRPG/Model/DiceModel.swift:431`, `Modules/MapRPG/Model/MapModel.swift:513`. `resultCategory`/`pinScale` always keep the receiver's own value in a merge, unlike every sibling field.
5. **[Medium] `GameTableView.swift` is two unrelated view implementations sharing one 1,031-line file** — §9.6.
6. **[Medium] `ItemRowView`, the app's highest-traffic list row, has no `Equatable`** — §8.4 — unlike its sibling rows in the same file.
7. **[Medium] `AnyView` erases the most-repeated per-entry row content in the app** — §8.8 — `Modules/CoreRPG/ItemList/EntryDataEditable.swift:42`, consumed 3×/row in `EntryEditRow.swift`.
8. **[Medium] Several 800-2,600 line files have no `MARK` organization to split along** — §9.9 — most notably `FoundryRuleModels.swift` (829 lines, 24 types, zero `MARK`s) and `FoundryImportView.swift` (866 lines, 14 view types, zero `MARK`s).
9. **[Low] `Id`/`Url` casing convention is ~90% adopted but has residual `ID`/`URL` spellings in the GameRPG network layer** — §4.1, §4.2 — including single structs that mix both spellings.
10. **[Quick wins available]** — §2 — three dead symbols, a typo in a shared `MARK`, ~9 mechanical shape-literal fixes, and two one-line safety fixes are all ≤30 minutes each with no architectural ripple.

---

## 2. Quick wins (≤30 min each)

- **Fix the `startMaster` force-unwrap** — `Modules/GameRPG/Root/GameRootModel.swift:613`. Replace `gameModel.selectedAdventure!` with the `id` local already bound at line 573. See §5.1.
- **Add a cancellation check to the dice widget-refresh task** — `Modules/DiceRPG/Controller/GameController.swift:609-620`. One `guard !Task.isCancelled` before `config.save()`. See §3.2.
- **Delete three dead symbols**: `FileControllable` protocol (`Modules/CoreRPG/Controllable/FileControllable.swift:1-7`), the unused `printViewChanges(content:)` overload (`Modules/CoreRPG/Debug/RainbowDebug.swift:20-27`), and the unreachable `FileLocation.url` case (`Modules/CoreRPG/Files/FileLocation.swift:5-23`). See §9.1-9.3.
- **Fix the shared `MARK` typo** — `Modules/CoreRPG/Controllable/EditControllable.swift:703`: `// MARK: - controller mantainence` → `// MARK: - Controller Maintenance`. Visible in every module's EditController jump bar. See §9.13.
- **Make `WeatherViewer`'s 5 gradient-stop arrays `static let`** — `Modules/WeatherRPG/View/WeatherViewer.swift:20-73`. They don't depend on instance state and are currently reallocated (40 `Gradient.Stop` literals) on every re-render of an actively-animating view. See §8.10.
- **Mechanically replace `RoundedRectangle(cornerRadius:)` with `.rect(cornerRadius:)`** at the ~9 call sites in §8.12 (several files already use the correct form elsewhere in the same file).

---

## 3. Concurrency

### 3.1 `toggleConnection` join flow can be permanently stranded (two independent root causes)
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift:76-95` (`toggleConnection(to:passcode:)`), `:100-103` (`resolvePendingConnection`), `:105-119` (`stop()`), `:163-227` (delegate callbacks); `Modules/GameRPG/Network/ConnectionController.swift:182-210` (`stateChanged`); reachable from `Modules/GameRPG/Browser/BrowserRowView.swift:24-32,82-99` and `Modules/GameRPG/Root/GameRootModel.swift:635-687` (`startGame` has no reentrancy guard, unlike the coalescing `stopGame()`/`awaitInFlightStop()` at `:729-747`).
- **What:** Verified by tracing the actual interleaving: (a) `toggleConnection` sets `networkModel.playerConnectionId` *before* it awaits `start(model:)`, and only sets `pendingJoinContinuation` *after* that await returns — so a second concurrent call in that window sees the guard fail, calls `stop()` (a no-op on the still-nil continuation), and tears down the first call's connection state; when the first call finally sets its own continuation afterward, nothing is left that will ever resume it, because `isCurrentConnection(id)` no longer matches once `stop()` has run. (b) Independently, `ConnectionController.stateChanged(_:)`'s switch only reacts to `.ready`, `.failed`, and `.cancelled` — `NWConnection.State.waiting` (Local Network permission not yet granted, unreachable/firewalled peer, no usable path) falls into `default: break` and is never reported to the delegate at all.
- **Why:** Either path leaves the `await` in `toggleConnection` — and everything chained onto it (`GameNetworkController.startPlayerGame`, `GameRootModel.startGame`, the `BrowserRowView.connect(joinCode:)` UI `Task`) — suspended forever with no error surfaced and no way back to the code-entry sheet, recoverable only by force-quitting or (by accident) tapping another join row, which triggers `stop()` as an unrelated side effect. This is a regression risk specific to the current uncommitted diff, which turned `toggleConnection` from fire-and-forget into a blocking continuation-based call without adding a reentrancy guard or a terminal case for `.waiting`.
- **Action:** (a) Give `PlayerNetworkController` an explicit "join in flight" guard — reject or coalesce a second `toggleConnection` call while `pendingJoinContinuation != nil` (or an in-flight join is otherwise detectable), and coalesce `GameRootModel.startGame` the same way `stopGame`/`awaitInFlightStop` already coalesce teardown. (b) Add a `.waiting(let error)` case to `stateChanged` that reports failure after a bounded delay/attempt count, or wrap the continuation in `toggleConnection` with a timeout race that resolves `false` if no terminal state arrives in a few seconds.
- **Severity:** High

### 3.2 Dice widget-refresh task doesn't check cancellation, letting a stale roll win the save race
- **Location:** `Modules/DiceRPG/Controller/GameController.swift:598-608` (task cancel + reassign) and `:609-620` (`diceUpdateWidget(diceResult:)`)
- **What:** The detached widget-refresh task is cancelled and replaced on every dice roll, but the `nonisolated` `diceUpdateWidget(diceResult:)` body it runs never checks `Task.isCancelled` — cancelling the old task only stops new bookkeeping, not the in-flight `DiceConfiguration.save()`/`DiceWidgetReloader.reloadDiceWidgets()` call already running.
- **Why:** On a rapid sequence of rolls, an older roll's widget-configuration write can complete after a newer one and overwrite the newer roll's saved result, so the Home Screen/Lock Screen dice widget can show a stale result despite correct in-app state.
- **Action:** Add `guard !Task.isCancelled` inside `diceUpdateWidget(diceResult:)` before the `config.save()` write, or serialize the write behind a small actor that only applies the latest submitted result.
- **Severity:** Low

### 3.3 Inconsistent explicit `@MainActor` annotation on `Task {}` literals in the highest-risk file
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:2062-2098` (`participantTask`), `:2101-2126` (`messageTask`), `:2133-2140` (`journalTask`), `:2003-2061` (`stateTask`), `:1862-1900` (`joinTask`) — all plain `Task { [weak self] in ... }` — versus the explicit `Task { @MainActor [weak self] in ... }` style used elsewhere in the same class (`:498, :736, :795, :844, :1524, :1586`).
- **What:** Roughly half of this file's unstructured `Task {}` literals calling into `@MainActor`-isolated members of `self` omit the explicit `@MainActor` annotation, relying on isolation inferred from the enclosing `@MainActor` context; the other half spell it out.
- **Why:** Functionally identical today, but the inconsistency means a future edit that moves one of these closures into a `nonisolated` helper or protocol default could silently lose `@MainActor` isolation and surface only as a runtime data race rather than a compile error — in the single largest, highest-risk file in the audit scope (2,635 lines).
- **Action:** Add the explicit `@MainActor` annotation to the five sites listed for consistency with the rest of the file.
- **Severity:** Low

---

## 4. API modernity

_Overall: this project's adoption of its own modernity rules is unusually thorough. A direct search confirmed **zero** hits for `Task.sleep(nanoseconds:)`, `DispatchSemaphore`, `Thread.sleep`, `.sync {`, `UIScreen.main`, `DateFormatter`/`NumberFormatter`/`MeasurementFormatter`, `String(format:)`, `.replacingOccurrences`, `.foregroundColor()`, `.tabItem()`, `.fontWeight(.bold)`, `ObservableObject`/`@Published`/`@StateObject` in app code, and dead `@available` guards below the 26.0 deployment target. The findings below are the real residue._

### 4.1 Residual `ID` suffix naming in the GameRPG network/message layer
- **Location:** `Modules/GameRPG/Network/GameRelayAdmission.swift:12-13,46,92,113,201`; `Modules/GameRPG/Network/SharePlayPlayerJournalAdmission.swift:10-11,95,320`; `Modules/GameRPG/Model/GameNetworkModel.swift:109`; `Modules/GameRPG/Model/LogGameModel.swift:18,65`; `Modules/GameRPG/Model/GameMessagePipeline.swift:61`; `Modules/GameRPG/Controller/LogGameController.swift:81,145,234`; `Modules/GameRPG/Controller/MasterController.swift:93,325,348,388,401,411,421` (confirmed: `messageID` at line 93 coexists with `senderId` at line 26 in the same struct); plus roughly 1,780 further `xxxID` identifiers across CoreRPG/GameRPG/RolePlayGameKit/RuleRPG/MapRPG (excluding `UUID` type-name hits).
- **What:** Core, purely-internal network/message identifiers (`senderID`→ mostly already `senderId`, but `messageID`, `participantID`, `sessionID`, `folderID`, `packageID`, `entryID`, `fileID`) still use the `ID` (all-caps) suffix, coexisting with correctly-cased `Id` siblings in the same structs.
- **Why:** The project has explicitly adopted the `Id`/`Url` casing convention (already the majority form: ~15,577 `xxxId` vs. ~1,799 real `xxxID` hits) — this is a specific inconsistency in the exact network/message hot-path code this round scrutinized, not a stray typo.
- **Action:** Rename the `ID`-suffixed properties/parameters to `Id` across GameRPG's network/message layer, module by module, verifying the final count mechanically (a prior audit round found a "0 remaining" claim on this exact convention turned out incomplete — record a raw grep count in the fix commit, not a sampled read).
- **Severity:** Low

### 4.2 Residual `URL` suffix naming outside the Foundry import subtree
- **Location:** `Modules/RolePlayGameKit/Model/AppModel.swift:45,54,57`; `Modules/CoreRPG/Cache/ObjectCache.swift:80,84,89`; `Modules/CoreRPG/App/AppGroup.swift:38,49` (confirmed: `groupURL`/`cloudURL` alongside the correctly-cased `preferredRootUrl` in the same file); `Modules/CoreRPG/Widget/ContentWidgetSnapshot.swift:62,66`; `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:59,225` (mixes `initialURL`/`newURL` with `loadUrl`/`proposedUrl` in the same `onChange` closure); `Modules/CoreRPG/LGViews/FileImporterView.swift:122,141`; `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:86,91,92`; `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:33,38,39` (18 files total outside the Foundry import subtree; ~389 `xxxURL` vs. ~1,105 already-correct `xxxUrl`).
- **What:** A minority but non-trivial set of `URL`-typed properties/locals still use the `URL` suffix instead of the project's adopted `Url` convention.
- **Why:** Same rationale as §4.1 — an explicit, largely-adopted convention with visible leftover inconsistency, including within single statements.
- **Action:** Rename the remaining `xxxURL` identifiers to `xxxUrl`. Exclude identifiers inside `Modules/**/Import/Foundry/**` and `Modules/CoreRPG/Foundry/**` (e.g. `sourceURL`, `fileURL`) from this pass — those plausibly mirror the external Foundry VTT/Universal VTT JSON schema's own field names; confirm intent before renaming those.
- **Severity:** Low

### 4.3 `SharePlayButton` wraps a system type with no `@Observable` replacement (informational)
- **Location:** `Modules/GameRPG/SetupViews/SharePlayButton.swift:20-21`
- **What:** `@ObservedObject private var groupStateObserver = GroupStateObserver()` — Apple's `GroupActivities.GroupStateObserver` still conforms to `ObservableObject`, with no `@Observable`-based replacement in the current SDKs.
- **Why:** This is the only surviving `@ObservedObject`/`@Published`/`@StateObject` in the app's own code, and it isn't actionable — it wraps a system type.
- **Action:** No action required. If desired purely for consistency, wrap `GroupStateObserver` in a small `@MainActor @Observable` adapter mirroring the pattern already used for a Combine publisher at `RPGSharePlayController.swift:754-756`.
- **Severity:** Low (informational)

---

## 5. Bugs / logic errors

### 5.1 Force-unwrap of `selectedAdventure` after intervening `await` suspension points
- **Location:** `Modules/GameRPG/Root/GameRootModel.swift:613`, contrasted with the safe local `id` bound at line 573
- **What:** `startMaster(supporterTier:)` safely binds `guard let id = gameModel.selectedAdventure else { return }` at line 573, but at line 613 — after the `await`s at lines 601 (`adventureRoot.adventureGameControllable.startGame(with:)`), 610 (`beginStatisticsSession`), and 612 (`gameModel.masterController?.start()`) — it force-unwraps `gameModel.selectedAdventure!` again instead of reusing `id`.
- **Why:** `GameRootModel` is `@MainActor`; each `await` yields the actor to other queued MainActor work. If any concurrent call (e.g. the adventure picker resetting the selection) sets `gameModel.selectedAdventure` back to `nil` during one of those suspensions, line 613 crashes.
- **Action:** Replace `gameModel.selectedAdventure!` with the `id` local already captured at line 573.
- **Severity:** High

### 5.2 Unbounded recursion in item/folder duplication (no cycle or depth guard)
- **Location:** `Modules/CharacterRPG/Controller/EditController.swift:311-326` (`duplicateFolderEntries`) and `:339-362` (`duplicateSubValue`); contrast with the guarded recursive walk at `:113-126` (`gameValueEntryUpdate`, using `RecursionLimits.maxValueLinkDepth`) in the same file.
- **What:** Both `duplicateFolderEntries(of:newParentId:)` and `duplicateSubValue(id:withCopy:)` recurse into child items/folders (`entry.childId`, `item.duplicateSubValueIds()`) with no cycle-detection or depth limit.
- **Why:** If the item/value graph or folder-membership graph ever contains a cycle — a plausible outcome of a merge/import bug or a race between two devices editing folder membership concurrently via CloudKit sync — duplicating that item recurses indefinitely and crashes with a stack overflow instead of failing gracefully, a hazard class the codebase's own `RecursionLimits` pattern already anticipates elsewhere in this exact file.
- **Action:** Thread a depth counter or `visited: Set<UUID>` through both recursive functions and bail out (returning what's been produced so far) once a previously-seen id is encountered or `RecursionLimits.maxValueLinkDepth` is exceeded.
- **Severity:** High

### 5.3 CRDT `merge()` silently drops `resultCategory`/`pinScale` on conflict
- **Location:** `Modules/DiceRPG/Model/DiceModel.swift:407-437` (`merge(_:)`, line 431: `resultCategory: resultCategory`) and `Modules/MapRPG/Model/MapModel.swift:483-521` (`merge(_:)`, line 513: `pinScale: pinScale`).
- **What:** Confirmed by reading both full `merge()` functions: every other non-CRDT scalar field is deliberately arbitrated (`isLeftDice ? self... : other...` in `DiceModel`, or unconditionally `other.scale`/`other.degrees`/`other.displayState`/`other.parentId` in `MapModel`), but `resultCategory` and `pinScale` always keep the receiver's own (`self`) value and never take `other`'s — even though both are real, persisted, `Codable`, `isSame`-compared fields (`DiceModel.swift:475`, `MapModel.swift:544`), not per-device UI state.
- **Why:** Whichever side calls `.merge()` as the receiver silently discards the peer's incoming `resultCategory`/`pinScale` change during a CloudKit merge conflict. `pinScale` in particular controls on-map pin sizing, and `MapEditorSession.canReshare` (`MapEditorModel.swift:45-49`) already treats `pinScale` drift as something requiring reconciliation/reshare with players — a silently-dropped merge means that reconciliation can regress, reproducing the class of "map pin state" desync this app has a documented multi-round history of debugging (see `[[map-pin-health-highlight-attacker-3d-colors]]`, `[[battle-round-health-sync-on-turn-advance]]` in prior session memory).
- **Action:** Wire `resultCategory`/`pinScale` into the same conflict-resolution scheme as their sibling fields (tie to the same `isLeftDice` comparison, or take `other`'s value the way `scale`/`degrees` do).
- **Severity:** High

---

## 6. Security

No new security findings this round. The following were specifically re-checked and confirmed sound (not regressed):

- **Zip-slip / decompression-bomb guards** — `Modules/CoreRPG/Foundry/FoundryZIPArchive.swift`: path-traversal rejection (`..`, absolute paths, drive letters, backslashes, NUL bytes), size/count ceilings (`maximumEntrySize`, `maximumRuleDataSize`, `maximumArchiveSize`, `maximumDocumentCount`), ZIP64/multi-disk/encrypted-archive rejection, and post-inflate size/CRC verification are all present and unweakened since the prior audit confirmed them.
- **No hardcoded secrets/tokens** — a targeted grep for `Bearer`, `apiKey`, `secret`, `Authorization`, and suspicious base64 blobs across `Modules/`/`Sources/` returned nothing beyond expected framework/entitlement key names.
- **No `UserDefaults` credential storage** — zero `UserDefaults.standard` usage anywhere in `Modules/`.
- **Debug logging hygiene** — all 26 `print()` calls in the codebase are already behind `#if DEBUG`, and none contain tokens, usernames, or network payloads (re-verified per file; see §9.14).

---

## 7. Performance

No new non-UI performance findings this round beyond what's captured under SwiftUI/UI (§8), which covers the specific rendering-hot-path issues this audit surfaced (per-render allocations, missing `Equatable`, `AnyView` erasure on the highest-traffic rows). Deep performance profiling (Instruments `.trace` capture) was out of scope for this round — see `Docu/SWIFTUI_PERFORMANCE_AUDIT.md` for the last dedicated pass, and §11 below.

---

## 8. SwiftUI / UI

### 8.1 Computed-property views instead of `View` structs — `OverlayGameMenu`
- **Location:** `Modules/GameRPG/GameViews/OverlayGameMenu.swift:39-333`
- **What:** The entire per-platform menu (`visionProMenu`, `macMenu`, `tvMenu`, `titleView`, `closeFieldView`, `closeView`, `enlargerView`, `secondOptionView`, `toolIconView`, `toolIconMacViewMaster/Player`, `toolIconIOSViewMaster/Player`, `wifiView` — 11 pieces) is built as computed properties, violating the project's "extract subviews into new `View` structs" rule.
- **Why:** SwiftUI can't independently diff/cache these fragments — any state read by any one of them invalidates the entire parent body/type-check graph, and the file is hard to navigate or preview in isolation.
- **Action:** Split each computed `some View` property into its own `private struct ...: View`, passing only the data/bindings it needs.
- **Severity:** Medium

### 8.2 Computed-property views instead of `View` structs — `QuickEntryEditorView`
- **Location:** `Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:99-335`
- **What:** Nine view fragments (`contentView`, `entryListView`, `editorView`, `secondaryActionMenu`, `pdfButton`, `removeLineBreak`, `showInspectorButton`, `showHelpButton`, `showResultButton`) are computed properties instead of `View` structs, in a widely-used shared editor component.
- **Why:** Same diffing/testability cost as §8.1, but in a component instantiated across every module's entry editors.
- **Action:** Extract each into a dedicated `View` struct with explicit parameters.
- **Severity:** Medium

### 8.3 The same computed-property-view pattern recurs across ~30 more files
- **Location:** `Modules/GameRPG/SetupViews/SelectedAdventureView.swift:87-173`, `Modules/GameRPG/SetupViews/SelectedPlayerView.swift:91-135`, `Modules/CoreRPG/Views/GroupBoxTV.swift:32-73`, `Modules/CoreRPG/FileViews/ExportProgressPanelView.swift:123-172`, `Modules/CoreRPG/EntryEditor/EntryEditorHeaderView.swift:32-108`, `Modules/CoreRPG/Inspector/LinkItemListView.swift:150`, `Modules/CoreRPG/Buttons/GlassButton.swift:50-56`, plus ~20 more (`MasterStartView.swift`, `GameJoinCodeSetupButton.swift`, `SingleReviewFilePropertyRow.swift`, `InspectorRowView.swift`, `QuickEditorDoubleView.swift`/`QuickEditorIntView.swift`, `ImageOverlayButton.swift`, `ToolbarItemListViewModifier.swift`, `ModuleInspectorView.swift`).
- **What:** The same "view built as a computed property" pattern, at 1-2 instances per file.
- **Why:** Cumulatively the most common SwiftUI-rule violation in the codebase.
- **Action:** Sweep converting `private var x: some View { }` properties into `private struct`s; prioritize §8.1/§8.2 first (largest offenders).
- **Severity:** Low (Medium in aggregate)

### 8.4 `ItemRowView` — the app's highest-traffic list row — has no `Equatable`
- **Location:** `Modules/CoreRPG/LGViews/ItemRowView.swift:5-69`
- **What:** Confirmed: `ItemRowView`, the generic row rendered by every module's item list (Adventures, Characters, Maps, Tables, etc.), has no `Equatable` conformance or `.equatable()` call site, unlike sibling rows in the same directory (`NameItemNewRow`, confirmed `Equatable` at `NameItemNewRow.swift:5`; `DescriptionItemNewRow`, `ListRowItemView`) which already do this.
- **Why:** Without `Equatable`, every row re-diffs its full body (icon, name, tag, share, description sub-rows) whenever any unrelated state the parent list observes changes — on the single most-repeated row type in the app.
- **Action:** Conform `ItemRowView` to `Equatable` (comparing `model.id`/version, `isSelected`, `listDisplayModel.displayMode`) and call `.equatable()` at its list call sites, mirroring `NameItemNewRow`/`DescriptionItemNewRow`.
- **Severity:** Medium

### 8.5 `SearchResultRow` missing `Equatable`, plus an inline controller lookup in `body`
- **Location:** `Modules/GameRPG/Search/SearchResultRow.swift:16-54`
- **What:** No `Equatable` conformance; recomputes `root.rootController(for: result.module)` directly in `body` on every render.
- **Why:** Search results re-render on every keystroke; without equatability every keystroke re-diffs every visible row's full body including the module/controller lookup.
- **Action:** Hoist the lookup into a stored `let` computed once at construction (or pass `module` down from `SearchListView`) and conform `SearchResultRow` to `Equatable`.
- **Severity:** Medium

### 8.6 Table-generation rows missing `Equatable`
- **Location:** `Modules/TableRPG/View/TableGenerationEntryRow.swift:6-138` and `Modules/TableRPG/View/TableGenerationOccurrenceView.swift:6`
- **What:** Neither `ForEach` row type has `Equatable`, unlike `BattleRoundCard`/`BattleParticipantColumn` in GameRPG which use the identical row shape with `.equatable()`.
- **Why:** Table generation re-renders on every roll/selection change; without equatability all rows re-diff even when only one entry's selection changed.
- **Action:** Add `Equatable` comparing each row's identity and rendered fields; call `.equatable()` from the parent `ForEach`.
- **Severity:** Low

### 8.7 `BrowserRowView` missing `Equatable`
- **Location:** `Modules/GameRPG/Browser/BrowserRowView.swift:6-140`
- **What:** The nearby-game browser row has no `Equatable` conformance.
- **Why:** Lower severity given small LAN/Bonjour peer counts, but the row still re-diffs its full label/icon/sheet content on every unrelated `BrowserManager` update.
- **Action:** Add `Equatable` comparing `model` and the two connection-state booleans it reads.
- **Severity:** Low

### 8.8 `AnyView` erases the most-repeated per-entry row content in the app
- **Location:** `Modules/CoreRPG/ItemList/EntryDataEditable.swift:42` (protocol requirement, confirmed) and its ~14 module-specific conformances (e.g. `Modules/CharacterRPG/View/AddtionalEntryRow.swift`, `Modules/MapRPG/View/AddtionalEntryRow.swift`), consumed 3×/row-render at `Modules/CoreRPG/LGViews/EntryEditRow.swift:39,45,55` (confirmed).
- **What:** `additionalRowView(for:entry:textModel:) -> AnyView` type-erases every module's custom per-entry row content, called up to 3 times per row render inside `EntryEditRow`, which is itself instantiated once per visible entry in every module's detail list.
- **Why:** `AnyView` disables structural diffing for this subtree on the single most-repeated row type in the app, forcing a full re-render of the erased content on every parent update instead of a cheap identity-preserving diff.
- **Action:** Replace the `AnyView`-returning protocol requirement with a `@ViewBuilder` requirement so each conforming type's concrete view type is preserved through to the renderer.
- **Severity:** Medium

### 8.9 `EntryEditRow` recomputes its link-highlighting model on every body evaluation
- **Location:** `Modules/CoreRPG/LGViews/EntryEditRow.swift:67-69` (confirmed)
- **What:** The `linkTextModel` computed property calls `editController.linkTextModel(...)` (resolving the link controller, parsing entry content for embedded links) fresh on every body evaluation of every visible entry row, rather than being cached and invalidated only when `entry.content` changes.
- **Why:** Link-highlighting/parsing work runs on every re-render of every row in every module's entry list, not just when the underlying text actually changes.
- **Action:** Cache the built `LinkHighlightTextModel` in `@State`, updated via `onChange(of: entry.content)` — the same pattern already used in `Modules/TableRPG/View/TableGenerationEntryRow.swift:118-120`.
- **Severity:** Medium

### 8.10 `WeatherViewer` reallocates 40 gradient-stop literals per view instantiation
- **Location:** `Modules/WeatherRPG/View/WeatherViewer.swift:20-73`
- **What:** Five `[Gradient.Stop]` arrays (`backgroundTopStops`, `backgroundBottomStops`, `cloudTopStops`, `cloudBottomStops`, `starStops` — 40 `Gradient.Stop` literals total) are plain instance `let` properties initialized inline, reallocated on every construction of a new `WeatherViewer` value, even though none depend on `model`/`size`/any instance state.
- **Why:** `WeatherViewer` is driven by an actively-animating `@State` (`lightningTrigger`) and rendered continuously during weather effects/gameplay — this reallocates 40 constant structs per frame-adjacent re-render for no reason.
- **Action:** Make all five arrays `static let` constants so they're computed once per process.
- **Severity:** Medium

### 8.11 `DiceInline` duplicates label markup and uses a non-static shape literal
- **Location:** `Modules/DiceRPG/View/DiceInline.swift:34-36` and `:93-96`
- **What:** The identical `Text(...).padding(4).foregroundStyle(.white).background { RoundedRectangle(cornerRadius: 8).fill(Color.accentColor) }` label style is duplicated between the plain-button and menu-button branches of `body`.
- **Why:** Minor style-guide violation (project rule: prefer `.rect(cornerRadius:)` over constructing shape instances) plus duplicated markup that will drift if one branch is restyled and not the other.
- **Action:** Factor the label into one small private view builder used by both branches; switch the shape literal to `.rect(cornerRadius: 8)`.
- **Severity:** Low

### 8.12 `RoundedRectangle(cornerRadius:)` instead of `.rect(cornerRadius:)` — recurring
- **Location:** `Modules/CoreRPG/Views/GroupBoxTV.swift:82`, `Modules/CoreRPG/LGViews/CachePhotoView.swift:47`, `Modules/GeneratorRPG/View/PdfSummaryAnalysisView.swift:71,165`, `Modules/GeneratorRPG/View/TableSummaryAnalysisView.swift:59,134`, `Modules/GeneratorRPG/View/PdfContentExtractionView.swift:66,141`, `Modules/MapRPG/View/DisplayConfigEditor.swift:173`, `Modules/PhotoRPG/View/CarouselPhotoItemView.swift:64,68` (9+ occurrences).
- **What:** `.clipShape(RoundedRectangle(cornerRadius: ...))` used instead of the project-preferred static-member form `.clipShape(.rect(cornerRadius: ...))`.
- **Why:** Explicit, repeated violation of the "prefer static member lookup to struct instances" rule; inconsistent even within single files (e.g. `DisplayConfigEditor.swift:31` correctly uses `.rect` while line 173 in the same file doesn't).
- **Action:** Replace each `RoundedRectangle(cornerRadius: x[, style: y])` shape literal used as a `Shape` argument with `.rect(cornerRadius: x[, style: y])`.
- **Severity:** Low
- **Note:** `Modules/GameRPG/Statistics/View/GameStatisticsDiceChart.swift:25` was initially flagged for the same issue by one audit pass but was verified during synthesis to be `SectorMark.cornerRadius(_:)` (a Swift Charts API, not a `View` modifier) — Charts has no `clipShape` equivalent, so this line is correct as written and is excluded from the count above. See §12.

### 8.13 `CarouselPhotoItemView` shows a blank tappable state when `cacheControllable` is `nil`
- **Location:** `Modules/PhotoRPG/View/CarouselPhotoItemView.swift:35-45`
- **What:** `GroupedPhotoView` is only constructed inside `if let cacheControllable = root.cacheControllable`; when `nil`, the surrounding `Button` renders an effectively empty `Group{}` label with no fallback content beyond the outer `.accessibilityLabel`.
- **Why:** On a reachable `nil` cache-controller state, the carousel shows a blank tappable capsule with no visual affordance for sighted users.
- **Action:** Add a placeholder (a system-image glyph or `ProgressView`) for the `cacheControllable == nil` branch.
- **Severity:** Low

### 8.14 `OverlayGameMenu`'s platform-gated subtrees can't be independently previewed
- **Location:** `Modules/GameRPG/GameViews/OverlayGameMenu.swift:19-20`
- **What:** The per-platform menu selection (`visionProMenu`/`macMenu`/`tvMenu`/`IOSGameOverlayMenu`) is chosen via `#if os(...)` compiled branches, so only one branch compiles per platform build target.
- **Why:** Visual regressions on non-building platforms (e.g. checking the Mac layout while building for iOS) are undiscoverable except by switching the whole scheme/destination.
- **Action:** Once split per §8.1, give each platform-specific menu subtree its own `#Preview` block.
- **Severity:** Low

_Follow-up needed (not fully read this round, given time budget): `Modules/RolePlayGameKit/View/DataBaseAppStoreAvailable.swift`, `DatabaseInitializationView.swift`, `AppImportView.swift` — these host the app's top-level navigation/database bootstrap and were only skimmed structurally. See §11._

---

## 9. Dead code / duplication / refactor

### 9.1 Dead protocol: `FileControllable`
- **Location:** `Modules/CoreRPG/Controllable/FileControllable.swift:1-7`
- **What:** `public protocol FileControllable: Sendable { var fileUrlDataController: FileUrlDataController { get } }` has zero conformers and zero usages anywhere in the repo.
- **Why:** Pure dead surface area; a future reader may assume some controller conforms to it and search fruitlessly.
- **Action:** Delete, or add a `// TODO(scope):` note if it's scaffolding for planned work.
- **Severity:** Low

### 9.2 Dead overload: `printViewChanges(content:)`
- **Location:** `Modules/CoreRPG/Debug/RainbowDebug.swift:20-27`
- **What:** The `@ViewBuilder` closure-taking overload of `View.printViewChanges` is never called anywhere; all 110+ call sites use the separate `Self.printViewChangesOnlyInDebug()` instead.
- **Why:** Two near-identical debug helpers exist side by side and only one is used.
- **Action:** Delete the unused overload; keep `printViewChangesOnlyInDebug()`.
- **Severity:** Low

### 9.3 Dead enum case: `FileLocation.url`
- **Location:** `Modules/CoreRPG/Files/FileLocation.swift:5-23`
- **What:** `FileLocation.url` (raw value 5) is defined but never constructed or matched against anywhere in the repo — `LocationFileManager.fileLocation(for:)` only ever returns `.appCloud`, `.local`, `.icloud`, or `.newCloud`.
- **Why:** An enum case that can never occur is dead branch weight every `switch` over `FileLocation` must still handle.
- **Action:** Confirm no persisted data still decodes raw value 5, then remove `.url`, or document why it's reserved.
- **Severity:** Low

### 9.4 Duplicated preview-fixture bootstrap logic across 5 modules
- **Location:** `Modules/DiceRPG/Model/PreviewData.swift:46-62`, `Modules/AdventureRPG/Model/PreviewData.swift:43-57`, `Modules/CharacterRPG/Model/PreviewData.swift:40-53`, `Modules/GeneratorRPG/Model/PreviewData.swift:34-51`, `Modules/MapRPG/Model/PreviewData.swift:45-61`
- **What:** Each module hand-rolls an identical ~15-line block loading `RPGResources.Resources.exampleFirstData`, importing it via `importController.importUrl(from:)`, differing only in the target root model type and 1-2 follow-up lines.
- **Why:** Near-verbatim (~90% identical) logic copy-pasted five times; a bug in the bundle-lookup/import sequence must be fixed in five places.
- **Action:** Extract a shared CoreRPG helper (e.g. `PreviewFixtureLoader.importFirstExample(into:)`) called by each module's `PreviewData.swift`.
- **Severity:** Low (Debug/preview-only, but 5x drift risk)

### 9.5 Duplicated `gameSheetRootModel` logic in `AdventureSheet`/`ReaderSheetView`
- **Location:** `Modules/AdventureRPG/View/AdventureSheet.swift:44-73` and `:112-141` (`ReaderSheetView`)
- **What:** The `gameSheetRootModel` computed property (lazily creates/reuses `SheetRootModel` for the live game sheet), doc-comment included, is duplicated verbatim between `AdventureSheet` and its own nested `ReaderSheetView`.
- **Why:** Any future fix to this reuse/seed logic must be made twice and the copies can drift.
- **Action:** Extract into one helper (an extension on `ItemEditorModel`/`AdventureRootModel`, or a free function) called from both sites.
- **Severity:** Low

### 9.6 `GameTableView.swift` — two unrelated view implementations sharing one 1,031-line file
- **Location:** `Modules/GameRPG/Table3D/GameTableView.swift:93-596` (visionOS `GameTableView`) vs. `:598-1031` (iOS/macOS `GameTableView`), gated by mutually-exclusive `#if os(visionOS)`/`#if os(iOS) || os(macOS)` blocks; no `MARK` comments anywhere in the file.
- **What:** Two entirely separate `public struct GameTableView: View` type definitions share only a filename; the file also has zero organizational `MARK`s despite containing `WindowOpenButton` and `GameTableRealityContent` as additional nested types.
- **Why:** Because the two halves are already textually disjoint, this is the easiest possible split in the audit — no cross-references to untangle.
- **Action:** Split into `GameTableView+VisionOS.swift` (lines 1-596) and `GameTableView+PlatformFlat.swift` (lines 598-1031).
- **Severity:** Medium

### 9.7 Per-module `DataController` boilerplate duplicated across 12 modules
- **Location:** `Modules/PdfRPG/Controller/DataController.swift`, `Modules/AudioRPG/Controller/DataController.swift`, and 10 other `Modules/*/Controller/DataController.swift` files (85-256 lines each)
- **What:** Every module's `DataController` wraps `CoreDataController<Model, EntityType>` with an identical init/`token`/`dataController` property shape and identically-shaped `mapSnapshot`/`applySnapshot`/`makeModel`/`makeSnapshot` stubs — largely expected structural duplication (each module's field mapping must differ), but the surrounding init/token boilerplate isn't captured by any shared base the way `LinkController`/`ImportController` already route through `LinkControllable`/`GenericImportController`.
- **Why:** Low-priority: the field-mapping logic must stay module-specific, but the wrapper boilerplate could be shared.
- **Action:** Consider a small shared base providing the init/token boilerplate, leaving only field-mapping methods per module.
- **Severity:** Low

### 9.8 `RPGSharePlayController.swift` (2,635 lines) — largest file in the repo, split previously deferred
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift`
- **What:** Already documents (lines 16-18) that `MARK` dividers were chosen over a physical split in a prior audit round, given cross-reference untangling cost. 8 `MARK` sections exist: delegate protocol, session/activation types, controller state & setup, send/chunked transport, session lifecycle, journal attachment handling, visionOS spatial config.
- **Why:** At 2,635 lines this remains the single largest file in the repo; worth re-evaluating now that sections are clearly delineated.
- **Action:** Re-evaluate splitting along the existing `MARK` boundaries into same-type `extension` files (`+Transport.swift`, `+Lifecycle.swift`, `+Journal.swift`, `+VisionOSSpatial.swift`); verify access levels before committing.
- **Severity:** Low (re-flagged only because size persisted since the prior assessment)

### 9.9 Large files with rich `MARK` sections that already give clean split boundaries
- **Location:** `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift` (2,552 lines, 30 `MARK`s) and `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift` (1,265 lines, 15 `MARK`s); `Modules/GameRPG/Controller/PlayerControllerModel.swift` (1,048 lines, **zero** `MARK`s — the largest unmarked file in the repo); `Modules/CoreRPG/Import/ExternalImport.swift` (1,023 lines, 9 `MARK`s, one section — "Review Session" — spanning ~640 of them).
- **What:** Each has natural extraction seams: `FoundryVTTImportReader`'s ~480-line "Bridge Decoding" section (2069-2552); `PlayerControllerModel`'s implicit grouping by domain (photo/pdf/space deferred-reveal state, SharePlay master-participant bookkeeping, sequence counters — 50+ stored properties, currently ungrouped); `ExternalImport`'s dominant "Review Session" type.
- **Why:** These are the largest non-generated files after §9.8; splitting them meaningfully reduces per-file cognitive load.
- **Action:** `FoundryVTTImportReader.swift` → orchestration + `+DocumentAssembly.swift` + `+DataSourceAndCaching.swift` + `+BridgeDecoding.swift`. `PlayerControllerModel.swift` → add `MARK`s first (Sequence Counters, SharePlay Master Participant, Map State, Media Deferred Reveals), then split along them. `ExternalImport.swift` → extract "Review Session" into `ExternalImportReviewSession.swift`.
- **Severity:** Medium

### 9.10 `FoundryRuleModels.swift` and `FoundryImportView.swift` — large files with zero `MARK` organization
- **Location:** `Modules/CoreRPG/Foundry/FoundryRuleModels.swift` (829 lines, 24 separate `Codable` types, 0 `MARK`s); `Modules/RolePlayGameKit/Import/Foundry/FoundryImportView.swift` (866 lines, 14 separate SwiftUI view/enum types, 0 `MARK`s).
- **What:** Both grow via the "one file per feature area" pattern with no section headers at all, unlike the similarly-large files in §9.9.
- **Why:** No `MARK` dividers in an 800+ line file with a dozen-plus unrelated top-level types makes it hard to jump to the right type.
- **Action:** `FoundryRuleModels.swift` → split into `FoundryManifestModels.swift`, `FoundryRuleContentModels.swift`, `FoundryImportDiagnosticModels.swift`. `FoundryImportView.swift` → split into `FoundryImportView.swift` (top-level + start/preflight), `FoundryImportReviewViews.swift`, `FoundryImportProgressViews.swift`.
- **Severity:** Medium

### 9.11 Minor/optional split candidates
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift` (965 lines, only 2 `MARK`s covering ~1/3 of the file); `Modules/MapRPG/Map/MapEditorModel.swift` (715 lines, 13 `MARK`s, already reasonably organized); `Modules/GameRPG/Root/GameRootModel.swift` (901 lines, 5 `MARK`s, already reasonably organized).
- **What:** `SpaceViewer.swift` needs `MARK`s added to its unmarked ~600 lines before a split makes sense; the other two are already navigable and splitting is optional (e.g. `GameRootModel`'s "Demo" section at :779-863 into its own `#if DEBUG`-gated file).
- **Action:** Add `MARK`s to `SpaceViewer.swift` first; treat the other two as optional.
- **Severity:** Low

### 9.12 Stale-filename / regression checks — confirmed clean
- **Location:** repo-wide
- **What:** A targeted search for `*_OLD*`, `Old_*`, `*_v1*`/`*_v2*`, `*Legacy*`, `*Deprecated*`, `.orig`/`.bak`/`copy` filenames returned zero matches. A spot-check of the `Generic*Controller` typealiases (a prior audit's genericization fix target) confirmed all conformances across 11-12 modules still resolve correctly with no orphaned declarations. `#if false` blocks: zero hits repo-wide; a heuristic scan for long comment blocks (148 candidates) sampled and confirmed to be prose rationale, not disabled code.
- **Action:** None — recorded to confirm no regression on these prior-audit fix targets.
- **Severity:** Low (informational)

### 9.13 `MARK` typo in a shared, widely-referenced file
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:703`
- **What:** `// MARK: - controller mantainence` (typo: "mantainence"→"maintenance"; inconsistent casing vs. sibling Title-Case `MARK`s).
- **Why:** This shared file is referenced by every module's `EditController`; the typo is visible in Xcode's jump bar for all 11+ conformers.
- **Action:** Fix to `// MARK: - Controller Maintenance`.
- **Severity:** Low

### 9.14 `print()` hygiene and magic constants — confirmed clean
- **Location:** repo-wide
- **What:** All 26 `print()` calls in `Modules`/`Sources` are already wrapped in `#if DEBUG`/`#endif` (re-verified per-file: `ControlSharingView.swift:195`, `HeaderContentScrollView.swift:122`, `NavigationConfiguration.swift:73`, `RemoveItemViewModifier.swift:41,48`, `PdfSummaryAnalysisView.swift:176`, `MyAiPlayground.swift` ×8, all 5 `PreviewData.swift` files) and none contain sensitive data. `Task.sleep` calls (5 total) all use named parameters, not inline literals; Bonjour service-type strings are centralized in `GameServiceType.swift`; list-search timing constants are centralized in `ListSearchTiming.swift`; zero `TODO`/`FIXME`/`HACK`/`XXX`/`#warning` markers anywhere in the codebase.
- **Action:** None — confirmed clean; do not re-flag without new evidence.
- **Severity:** Low (informational)

---

## 10. Cross-cutting recommendations

1. **A single-slot continuation that isn't guarded against reentrancy is a recurring hazard shape.** §3.1's root cause — an `await`-based handshake that stores its resolver in one `var` with no lock or waiter queue — is exactly the pattern the codebase already solved correctly elsewhere (`SharePlaySessionCallbackCoordinator.waitUntilIdle` at `RPGSharePlayController.swift:236-244` uses an array of waiters). Any future "make a fire-and-forget call block on its real outcome" refactor (the exact motivation behind the currently-uncommitted `toggleConnection` diff) should copy that array-of-continuations pattern rather than a single optional, and should audit whether every terminal state the underlying API can report (including easy-to-forget ones like `NWConnection.State.waiting`) is actually wired to resolve it.
2. **Recursive tree/graph walks need `RecursionLimits` applied uniformly, not selectively.** §5.2 is the second time a prior-audit-established safety pattern (depth/cycle guarding) was found missing on a sibling function in the same file that already uses it correctly. A short checklist item in code review — "does this new recursive walk over item/entry/folder relationships have a depth or visited-set guard?" — would catch this class before merge, since the codebase's own CloudKit-merge model makes cycles in these graphs a real (if rare) possibility, not just a theoretical one.
3. **`merge()` functions should be checked for full field coverage, not spot-checked.** §5.3 found two fields, in two different modules' otherwise-correct CRDT merge implementations, that never take the incoming side's value. A lightweight test that reflects over each `Model`'s stored properties and asserts every one is referenced somewhere in `merge()`'s return-value construction (or is explicitly allow-listed as intentionally receiver-only, like per-device UI state) would catch this mechanically rather than relying on a manual reading pass to notice an omission in a 30-field initializer call.
4. **The "extract subviews into `View` structs" and "add `Equatable` to hot list rows" rules exist in `CLAUDE.md` but aren't mechanically enforced.** §8.1-§8.9 collectively show this is the single most common category of rule violation in the codebase. A periodic grep (`private var \w+:\s*some View\b` inside `body`-containing files; `struct \w+Row.*: View\b` without a following `, Equatable`) run as part of the audit cadence would catch regressions and new instances without needing a full SwiftUI-expert pass every time.
5. **The `Id`/`Url` casing convention is ~90% adopted; finish it in one scripted pass.** §4.1/§4.2 show the remaining gap is concentrated in specific areas (GameRPG's network/message layer, and a handful of CoreRPG persistence/cache files) rather than spread evenly — a targeted rename pass on those files, with the final count recorded mechanically (not sampled) in the fix commit, would close this out the way a prior audit round's similar cleanup did for the bulk of the codebase.

---

## 11. What was NOT audited

- `Docu/` (39 historical audit reports and design docs) — read as reference for context, not re-audited.
- `.git/`, `.build/`, DerivedData, `Snapshots/` (image test fixtures).
- Algorithmic correctness of the RealityKit/Table3D rendering pipeline (`GameTableView.swift`, `GameEquipment.swift`, `GameRenderer.swift`) and `MapOverlayGeometry`/room-layer geometry math — surface-level only, no deep geometric proof.
- Build settings, scheme configuration, and Xcode project structure beyond what's visible in the shared `MasterRPG` scheme (a clean `xcodebuild clean build` was run and produced 0 Swift warnings — see the report header — but per-target build-setting review was not performed).
- Third-party SPM dependency internals (`swift-syntax`, `swift-snapshot-testing`, `xctest-dynamic-overlay`, `swift-custom-dump`, the local `RPGTabletopGameContent` package) — treated as black boxes.
- Deep test-coverage assessment. Several test files are themselves very large and were not read in full: `Tests/GameRPGTests/SharePlayPackageTransportTests.swift` (4,130 lines), `Tests/GameRPGTests/MasterPlayerControllerTests.swift` (2,267 lines), `Tests/GameRPGTests/NetworkStoreTests.swift` (2,000 lines), `Tests/CoreRPGSnapshotTests/CoreRPGGeneratedPreviewSnapshotTests.swift` (1,950 lines).
- Localization wording/correctness — string catalogs exist per module but translation quality wasn't assessed.
- Performance profiling via Instruments — no `.trace` was recorded this round; see `Docu/SWIFTUI_PERFORMANCE_AUDIT.md` for the last dedicated pass and §7 above.
- `Modules/RolePlayGameKit/View/DataBaseAppStoreAvailable.swift`, `DatabaseInitializationView.swift`, and `AppImportView.swift` — the app's top-level navigation/database bootstrap views were only skimmed structurally given the time budget for the SwiftUI pass; flagged for a follow-up read.
- The Core Data `.xcdatamodeld` was not directly opened this round to re-verify CloudKit optionality rules (all relationships optional, scalar properties defaulted) — no CloudKit-schema-related bug surfaced organically, but this wasn't independently checked as its own task.
- Per-target entitlements file consistency (App Group id, iCloud container id across MasterRPG/MasterTV/RPGShare) — not independently re-verified this round beyond what surfaced incidentally; a prior audit (`Docu/CODE_AUDIT_...`, see git history around the `app-store-aps-environment-entitlements` work) covered this in more depth.
- The full corpus of `~1,780` residual `xxxID` and `~389` residual `xxxURL` identifiers behind §4.1/§4.2 was not triaged one-by-one; counts are grep-based whole-corpus estimates, not individually verified line-by-line.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line.

For the High findings, here are the lines that prove the claim, each personally re-opened and traced during synthesis (not just trusted from agent output):

- **§3.1** — open `Modules/GameRPG/Player/PlayerNetworkController.swift`, lines 76-95 (`toggleConnection`) and 100-119 (`resolvePendingConnection`/`stop()`). Confirmed: `networkModel.playerConnectionId` is set at line 86, *before* the `await start(model:)` at line 88; `pendingJoinContinuation` is only set at lines 92-94, *after* that `await` returns. A second call arriving during that window sees the guard at line 78 fail (since `playerConnectionId` is already non-nil) and calls `stop()`, whose `resolvePendingConnection(success: false)` at that moment is a no-op (the first call's continuation doesn't exist yet) — but `stop()`'s later `networkModel.connectionController = nil` (line 114) means that when the first call's eventual `.cancelled` callback arrives, `isCurrentConnection(id)` (`ConnectionController.swift`... `PlayerNetworkController.swift:239-241`) returns false, so `lostConnection(for:)`'s `markLostIfCurrent` guard at line 209 fails and the continuation is never resumed. Separately confirmed: `ConnectionController.swift:182-210`'s `stateChanged` switch has no case for `.waiting`, only `default: break`.
- **§5.1** — open `Modules/GameRPG/Root/GameRootModel.swift`, line 573 (`guard let id = gameModel.selectedAdventure else { return }`) through line 613 (`gameModel.selectedAdventure!`). Confirmed three `await`s (601, 610, 612) sit between the safe binding and the force-unwrap, with no re-guard.
- **§5.2** — open `Modules/CharacterRPG/Controller/EditController.swift`, lines 311-326 (`duplicateFolderEntries`, self-recursive at line 322 with no depth/visited tracking) and lines 339-362 (`duplicateSubValue`, self-recursive inside the `forEach` at line 353). Confirmed by contrast with lines 113-126 in the same file, which threads a `depth` counter checked against `RecursionLimits.maxValueLinkDepth` for a structurally similar walk.
- **§5.3** — open `Modules/DiceRPG/Model/DiceModel.swift`, line 431 (`resultCategory: resultCategory`) inside `merge(_:)` (lines 407-437) — every sibling field in the same initializer call uses `isLeftDice ? ... : other....` except this one. Open `Modules/MapRPG/Model/MapModel.swift`, line 513 (`pinScale: pinScale`) inside `merge(_:)` (lines 483-521) — every sibling field uses `other.X` or a `.merged(other:)` CRDT call except this one.
- **Caught false positive, not included above:** one audit pass flagged `Modules/GameRPG/Statistics/View/GameStatisticsDiceChart.swift:25`'s `.cornerRadius(5)` as a `View`-modifier violation; opening the file shows it's applied to a Swift Charts `SectorMark` (line 20-24), where `.cornerRadius(_:)` is the correct, only API for rounding pie-slice corners — there is no `clipShape` equivalent for a Chart mark. Dropped from §8.12's count. This is exactly the kind of claim this audit step exists to catch before it reaches the report.

If any finding doesn't reproduce when you visit the line, flag it and I'll re-investigate.
