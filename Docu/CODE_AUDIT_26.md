# MasterRPG Code Audit 26

Generated 2026-11-14. Scope: all 15 modules under `Modules/` plus `Sources/` and `Resources/` (entitlements, Info.plists) — about 215k production LOC — audited by 21 area agents (CoreRPG and GameRPG and MapRPG split by folder, one agent per remaining module). Tests and the `RPGTabletopGameContent` SPM package were read only for test-gap checks. No `Dead/` or archive directory exists.

Findings cite `path/to/file.swift:LINE` (repo-relative). Items marked **[OPEN since CODE_AUDIT_N §x]** were found open in an earlier audit; everything else is new. Anything an earlier audit marked Fixed / By design / Won't fix, or that `Docu/CODE_AUDIT_25.md` §0 closed today, was not re-reported. The per-area working files with the agents' own summaries and "not audited" lists are in `Docu/CODE_AUDIT_26_Single/`.

**Totals:** 369 findings — 0 Critical, 9 High, 94 Medium, 266 Low. High and Medium items have the full template; Low items are compact one-liners (full text in the area files).

**Compiler ground truth:** a clean Debug build of MasterRPG for the generic iOS Simulator destination printed no Swift warnings (only `appintentsmetadataprocessor: Metadata extraction skipped`) but stopped at the RolePlayGameKit link step (`ld` failure with the generic destination); the same project built warning-free for iOS Simulator, iOS device, macOS, tvOS and visionOS earlier today with specific destinations. So the compiler list is empty and the concurrency section below rests on code reading.

**Method and confidence:** every finding comes from reading code; nothing was run or built by the agents. The 9 High findings were then re-checked by the lead by opening the cited lines (§12). Medium and Low findings carry the agents' own verification only; items they flagged "unverified" or "reasoned" are marked so in the text.

---

## 1. Executive summary

No Critical finding. The nine High findings were all re-read in the code by the lead; eight are user-hit bugs and most are small and local, the ninth (§6.1) needs a hostile imported package. In priority order:

1. **[High] Export and game reveal do not follow group entries (entry.adventureId)** — §5.3 — Modules/AdventureRPG/Controller/ExportController.swift:63-128 (BFS visit closure)
2. **[High] File replacement during a running game deletes the file the library item still references** — §5.1 — Modules/CoreRPG/Controllable/EditControllable+File.swift:131-187 (`replaceFile`, esp. 177-181), 239-280 (`writeFile`, 276-279)
3. **[High] Dice bag in the editor appends the same die (same id) on every tap** — §5.4 — Modules/DiceRPG/View/DiceBag.swift:11-22 (static catalog with fixed ids) and :56-60 (`root.editController.add(die: die, ...)`)
4. **[High] The compare option and value are never evaluated unless "Add dice" is on** — §5.5 — Modules/DiceRPG/Controller/GameController+DiceResult.swift:37 (`checked = sumResult > 0`) and :147-155 (`maxValuePerDice`)
5. **[High] `TableRollRange` reads "00" as 0, so d100 rows such as "96-00" never match rolls 97-100** — §5.2 — Modules/CoreRPG/Text/TableRollRange.swift:12-23 (consumers Modules/TableRPG/Controller/TableGenerationController.swift:241-254, Modules/Tabl
6. **[High] Weather-to-Photo link is registered under the Adventure module and is dropped by every link validation** — §5.6 — Modules/WeatherRPG/Model/WeatherModel.swift:208-219 (`changedLinkRegisterModels`, source `ItemRowModel(itemId: id, typeId: .adventure)`)
7. **[High] Time, rain intensity and rain angle sliders edit the live model and are never saved** — §5.7 — Modules/WeatherRPG/View/WeatherConditionEditor.swift:55-70 (`Slider(value: $model.time)`)
8. **[High] Lightning sliders save only when one change event jumps by 1 or more** — §5.8 — Modules/WeatherRPG/View/WeatherThunderEditor.swift:150-170 (`SignificantChangeModifier`), used at :95, :113, :131
9. **[High] Template inheritance resolution is exponential and unboundedly recursive (crash/hang on hostile system.json package)** — §6.1 — Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:456-476 (resolveTemplate), 418-453 (decode)
10. **[Medium] Map description and tags still ship to players unredacted** — §6.7 — Modules/MapRPG/Model/MapSnapshot.swift:154-190 (`redactedForNonMaster()` copies `description:` and `tags:` through unchanged, lines 168-170)
11. **[Medium] Per-player "show" toggle is enforced only on the receiving device** — §6.5 — Modules/GameRPG/Controller/PlayerController+MessageProcessing.swift:142-183
12. **[Medium] Tag register has no hydration-failure guard and can overwrite in-memory edits when it loads** — §5.9 — Modules/CoreRPG/Controllable/TagController.swift:26-60 (`setup`), 134-189 (`savePendingTags`)

Overall health is good: the agents' sweeps for GCD, `ObservableObject`, legacy formatters, `foregroundColor` and 1-parameter `onChange` came back clean in the areas that reported them (the remaining CLAUDE.md deviations are style items: hard-coded padding, `AnyView` in a few protocol surfaces, views built by helper methods), the network and import boundaries are well defended, and the older audit items the agents re-checked are fixed in code. What remains is concentrated in (a) the Weather and Dice editors, which lost the persistence/ID care the older modules got, (b) group/export edge cases in Adventure and Character, (c) hot-path performance on large hex maps and Foundry packages, and (d) preview fixtures and dead code that still ship in Release.

## 2. Quick wins (≤30 minutes each)

- §5.4 — give each added die a fresh id (`duplicate()`).
- §5.2 — read "00" as 100 for d100 rows.
- §5.6 — use `.weather` as the link source type and implement `linkRegisterModels`.
- §6.2 — add `_stats.lastModifiedBy` to the identity keys.
- §5.120 — compare the extension case-insensitively.
- §9.5 — delete the dead plumbing.
- §9.6 — delete the unreachable files after confirming the route.
- §9.20 — delete the model and its key monitor.
- §5.11 — do not cache a nil container.
- §5.33 — play one haptic per roll.
- §5.41 — take the data-mutation lock and fix the alert text.
- §9.2 — delete the unreferenced move functions.
- §5.70 — add the in-flight guard Add Folder has.
- §8.20 — add a confirmation.
- §5.47 — show an error instead of closing as if saved.

## 3. Concurrency

### 3.1 `createGameData(for:resultCategory:)` swaps the model's category across an await
- **Location:** Modules/DiceRPG/Controller/GameController.swift:184-198
- **What:** It reads `oldResultCategory`, writes the new category on the shared model, awaits `createGameData`, then writes the old one back.
- **Why:** Two overlapping calls for the same item (a share-to-all from `DiceInline` while a roll share runs, or two quick "Share to player" taps) interleave. The second call captures the first call's temporary category as "old" and restores it, so the temporary category stays on the model and is attached to later shares.
- **Action:** Pass the category into the export instead of mutating the model, or serialise per item.
- **Severity:** Medium   **Area:** DiceRPG   **Status:** Fixed 2026-11-15 — the category is a task-local `DiceShareOverride` read by the dice `ExportController.playerExportData` (player packages only); the shared model is never written. Test: `GameControllerTests.overlappingSharesExportTheirOwnResultCategory`.

### 3.2 visionOS manipulation subscriptions are stored in the view's own @State and capture the view value
- **Location:** Modules/SpaceRPG/Space/SpaceViewer.swift:58-59,640-680 (`manipulationBeganSubscription`/`manipulationEndedSubscription` closures use `self.isManipulating`, `self.handleManipulationEnded`, `self.tablePlacement`), 846-860 (`closeButtonAttachSubscription` closure uses `self`)
- **What:** The `EventSubscription` handles are kept in `@State` of `SpaceViewer`, while their closures capture `self` (the view struct, which holds the same `@State` storage box).
- **Why:** This is exactly the cycle CLAUDE.md warns about for the Table3D model (storage holds subscription, closure holds view copy, view copy holds the storage and with it `objectEntity`/`rootEntity`, i.e. the full USDZ entity). If RealityKit does not drop the handler when the scene is torn down, each open of the viewer on visionOS leaks the entity graph. The close-button subscription breaks its own cycle on the first update tick, the two manipulation ones never do. Not verified at runtime.
- **Action:** Move the gesture/placement state and the handlers into a small `@MainActor` reference type owned by `@State` (capture it weakly), or cancel and nil the subscriptions in `onDisappear`. Check with the memory graph that the entity deinits after closing the viewer.
- **Severity:** Medium   **Area:** SpaceRPG + TableRPG   **Status:** Fixed 2026-11-15 (manipulation subscriptions; not runtime-verified) — the two subscriptions capture only a `SpaceManipulationRelay` reference; the view installs its handlers in `onAppear` and clears them in `onDisappear`. The close-button one-shot subscription still captures the view but cancels itself on its first update tick, so it was left. Memory-graph check of the entity deinit on visionOS is still open.

### 3.L Low-severity items (14)

- **3.3 Memory-mapped source files are cached for the life of the reader** — Modules/CoreRPG/Foundry/FoundryVTTDataSource.swift:34, 118-143 — _CoreRPG Foundry/Sheet_. Read with `.alwaysMapped`-free semantics for files outside the app container (plain read or `F_NOCACHE` streaming), or drop the cache at the end of the import; re-stat size/modification date before re
  - **Status:** Fixed 2026-11-15 — `FoundryZIPArchive.SourceStamp` (size + modification date at open); `data(forPath:)` throws if the mapped source file changed. Reading the file whole was rejected (limit is 1 GiB). Test: `FoundrySourceStampTests`.
- **3.4 GameBundleBrowserModel: cancel then restart can clear the new download's state** — Modules/CoreRPG/FileViews/GameBundleBrowserModel.swift:66-92 — _CoreRPG UI 1_. Compare a per-download token before touching `downloadTask`/`status` in the completion.
  - **Status:** Fixed 2026-11-15 — per-download token; a finished or cancelled download touches `downloadTask`/`status` only while its token is current.
- **3.5 Thumbnail task defer matches on photo id, not on task identity** — Modules/GameRPG/Table3D/GameTableModel+PinThumbnails.swift:67-77, Modules/GameRPG/Table3D/GameTableProjection.swift:165- — _GameRPG Table3D_. Guard the defer with a per-load token (or compare the stored task identity) instead of the photo id. [[OPEN since CODE_AUDIT_3dTable §3.1, partial]]
  - **Status:** Fixed 2026-11-15 — `beginPinPhotoLoad` returns a per-load token that `loadPinThumbnail` presents; the defer clears bookkeeping only for its own token.
- **3.6 Pin-photo retry watchers are not cancelled in deinit** — Modules/GameRPG/Table3D/GameTableModel+PinThumbnails.swift:46-58, Modules/GameRPG/Table3D/GameTableModel.swift:241-250 — _GameRPG Table3D_. Cancel `pinPhotoRetryTasks.values` in `deinit` as well.
  - **Status:** Fixed 2026-11-15 — `pinPhotoRetryTasks` are cancelled in `deinit`.
- **3.7 `stop()` cancels only the newest `resetPlayers` task** — Modules/GameRPG/Controller/MasterController+Control.swift:31-35, 58-67 — _GameRPG Controllers_. Keep a generation counter (or cancel the whole chain) so every queued reset checks it.
  - **Status:** Fixed 2026-11-15 — `queuedResetPlayersTasks` holds every unfinished `resetPlayers` task; `stop()` cancels all of them.
- **3.8 `GameStatisticsModel.record(_:)` is declared async but only spawns an untracked task** — Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:129-138 — _GameRPG Views/Battle/Statistics_. Make it a synchronous `func` that appends to `pendingEvents` directly (it never needs to suspend) and drop the `await` at the call sites, which also removes the task allocation per game message.
  - **Status:** Fixed 2026-11-15 — `record(_:direction:origin:)` is synchronous (appends to `pendingEvents`; a full buffer starts a flush task); the `await` was dropped at all 10 call sites.
- **3.9 Fire-and-forget tasks without owner** — Modules/MapRPG/Controller/LinkController.swift:35-37 — _MapRPG rest_. Give the send chain a bounded wait or cancel it at game end; collect the validate tasks in the repair run so the run can await or cancel them.
  - **Status:** Fixed 2026-11-15 — link-action tasks run through the new `LinkActionTasks` (CoreRPG): owned, failures logged, `cancelAll()` called from `GameRoot.stopGame()`. Map share and validate tasks use it.
- **3.10 Older Adventure audit items that are still open in code** — Modules/AdventureRPG/Controller/LinkController.swift:68-70 — _AdventureRPG_. Decide won't-fix vs fix per item; the cheap one is `repairLinks` dispatch by module, and the `toggler` call can become `async` instead of an owned-nowhere Task. [[OPEN since CODE_AUDIT_Adventure §3.1, §3.3, §7.1, §8.1, §8.4, §9.9]]
  - **Status:** Partly fixed 2026-11-15 — §3.1 (toggler task → `LinkActionTasks`) and §7.1 (`repairLinks` dispatches by `link.module`). Not changed: §3.3 two-phase init, §8.1 `AnyView` (cross-module protocol), §8.4 route naming, §9.9 intent file merge — style/refactor items, left open on purpose.
- **3.11 `nonisolated(unsafe)` on Find-action query statics** — Modules/AdventureRPG/Intent/AdventureEntity.swift:134,160 — _AdventureRPG_. Make them `static var ...: QueryProperties { ..
  - **Status:** Fixed 2026-11-15 — `properties`/`sortingOptions` of `AdventureEntityQuery` are `nonisolated static var`s. `DiceEntity` and `CharacterEntity` have the same `nonisolated(unsafe)` pattern and were not in the finding; left as is.
- **3.12 `setInactive` and `setActive` run as unordered @concurrent tasks** — Modules/AudioRPG/Controller/AudioPlayerSession.swift:96-115, 151-168 — _AudioRPG_. Keep one serial chain (store the last session task and await it in `activate()`/`deactivate()`), or route both calls through a single actor.
  - **Status:** Fixed 2026-11-15 — `enqueueSessionChange(active:)` chains every `setActive`/`setInactive` behind the previous one.
- **3.13 Context-overflow recovery resets the shared session even when the caller was cancelled** — Modules/GeneratorRPG/BasicAI/Engine/ConversationEngine.swift:283-296, 367-376 — _GeneratorRPG_. rethrow `CancellationError` before touching the session, and only reset when the call is still the active one (reuse the streaming task id).
  - **Status:** Fixed 2026-11-15 — a cancelled call rethrows before the session is reset (a superseded call is cancelled by the engine, so this also covers "no longer the active one").
- **3.14 GeneratorTaskWait ignores cancellation of the waiter** — Modules/GeneratorRPG/Controller/GeneratorController.swift:455-473 — _GeneratorRPG_. wrap `gate.wait()` in `withTaskCancellationHandler` that opens the gate.
  - **Status:** Fixed 2026-11-15 — `gate.wait()` runs inside `withTaskCancellationHandler` that opens the gate.
- **3.15 Share-link toggle spawns an untracked Task and swallows errors** — Modules/PhotoRPG/Controller/LinkController.swift:25-33 — _PdfRPG + PhotoRPG_. Move the branch into one shared helper in CoreRPG (`standardToggleResult` neighbour) that surfaces the error through the existing toast mechanism. [[OPEN since CODE_AUDIT_Pdf §5.7] (Photo: NEW)]
  - **Status:** Fixed 2026-11-15 — Photo and Pdf share through `LinkActionTasks`, which logs the error instead of `try?`; Space, Table, Audio, Dice, Character share/toggle paths use it too. There is no toast mechanism in the code base, so the error is logged, not shown.
- **3.16 Quick-link controllers spawn unstructured Tasks; Rule's does nothing for the share command** — Modules/RuleRPG/Controller/LinkController.swift:107-113 — _RuleRPG + WeatherRPG_. Skip the Task for `.share` in Rule or implement it; make the toggle `async` or keep the Task handle. [Rule NEW; Weather [OPEN since CODE_AUDIT_Weather §3.3]]
  - **Status:** Fixed 2026-11-15 — Rule creates no task for `.share`; Weather and the shared `standardCommand`/`autoToggleAndRemoveAction` use `LinkActionTasks`.

## 4. API modernity

### 4.1 Foundry/VTT import UI and error strings are not localized
- **Location:** Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift:37-54 (`FoundryImportCategory.title`, shown by `Text(category.title)` at FoundryImportView.swift:219); FoundryImportView.swift:631-657 (`FoundryArtifactKind.title`, `ExternalImportDecision.title` used in `Button(decision.title)` and `Text(decision.title)`); FoundryRuleImportModel.swift:159,204,221,273,300,309,314,410 (`LoadState.failed(String)`, `commitError`, archive warnings); FoundryMediaNormalizer.swift:59-74 (`errorDescription`); all mapper `warnings` (e.g. FoundryVTTDomainMapper.swift:306-311, +DiceAndValues.swift:31-67, +Assets.swift:53)
- **What:** these are plain `String` literals passed to `Text(_:)`/`Button(_:)` string overloads (verbatim) or to `LocalizedError`; none appears in `Resources/Localizable.xcstrings` (grep for "Actors and characters", "Roll formula", "Another external import" finds nothing).
- **Why:** German and Thai users see English category names, the Skip/Merge/Replace decision picker, failure screens, and the whole warnings list on the review screen. CODE_AUDIT_21 §9.7 localized the CoreRPG import errors but not this module's.
- **Action:** use `String(localized:bundle: .module)` / `LocalizedStringResource` for titles and user-visible errors; for the dynamic mapper warnings introduce a small warning enum with localized formatting, or at least localize the fixed ones.
- **Severity:** Medium   **Area:** RolePlayGameKit   **Status:** Fixed 2026-11-15 — category, artifact-kind and decision titles, the import model's failure/commit/archive messages, `FoundryMediaNormalizationError` descriptions, geometry warnings and every fixed mapper warning are `String(localized:bundle: .module)`; 72 keys added to `RolePlayGameKit/Resources/Localizable.xcstrings` with German and (machine) Thai. Not localized: `package.diagnostics` messages (they come from CoreRPG's Foundry reader) and the "Foundry VTT" fallback title.

### 4.L Low-severity items (15)

- **4.2 Strings not localized through the module bundle** — Modules/CoreRPG/Controllable/ContextMenuMultiController.swift:30-36 — _CoreRPG Controllable/Import/Links_. Use `String(localized: "\(name) and \(count) more", bundle: .module)` with plural variations; use two localized keys for hide/show.
  - **Status:** Fixed 2026-11-15 — "<name> and <n> more" is localized (no plural variants: the English, German and Thai texts need none). The hide/show part of the finding is not in the cited lines; nothing to change there.
- **4.3 ItemHeaderEditorView: UIKit haptic and focus after a cancelled sleep** — Modules/CoreRPG/LGViews/ItemHeaderEditorView.swift:61-66, 88-91 — _CoreRPG UI 1_. `.sensoryFeedback(.success, trigger:)`; `guard !Task.isCancelled` after the sleep.
  - **Status:** Fixed 2026-11-15 — `.sensoryFeedback(.success, trigger:)`, `guard !Task.isCancelled` after the focus sleep. The editor now dismisses one `settleDelay` (100 ms) after saving so the haptic can play.
- **4.4 Double localization lookup: `String(localized:).localizedString`** — Modules/CoreRPG/Extensions/LocalizedStringKey+String.swift:11-15 — _CoreRPG UI 2_. Remove `.localizedString` after `String(localized:)` (107 sites), keep the extension only for raw keys.
  - **Status:** Fixed 2026-11-15 — `.localizedString` removed after `String(localized:bundle:)` at 112 sites in 29 files. Left: raw-key uses (`"Not checked".localizedString`, `"Added Monster".localizedString`) and the four `.localizedLowercase.localizedString` calls in `EditControllable`.
- **4.5 Menu title "<Module> Link" is not localized** — Modules/CoreRPG/Menu/LinkWindowCommandView.swift:9,28 — _CoreRPG UI 2_. Use a localized format string with `bundle: .module`.
  - **Status:** Fixed 2026-11-15 — "<Module> Link" and "New <title>" are localized format strings.
- **4.6 Global `UINavigationController` delegate hijack** — Modules/CoreRPG/Extensions/NavigationController+Back.swift:6-31 — _CoreRPG UI 2_. Re-test on iOS 26 without it; if still needed, scope it to the app's own navigation controllers.
  - **Status:** Not changed — the hack needs a device test on iOS 26 (swipe back with a hidden navigation bar) before it can go; no way to verify that here.
- **4.7 UIKit haptics instead of `sensoryFeedback`** — Modules/CoreRPG/EntryEditor/EntryEditorHeaderView.swift:43-45,82-84,110-114 — _CoreRPG UI 2_. Trigger from `isSaving` and a drop counter.
  - **Status:** Fixed 2026-11-15 — `.sensoryFeedback` driven by `isSaving` and two drop counters.
- **4.8 Hand-tracking scale controller: wrong log category and permission prompt on every table open** — Modules/GameRPG/Table3D/TableScaleGestureController.swift:66-83, Modules/GameRPG/Table3D/GameTableView+VisionOS.swift:32 — _GameRPG Table3D_. Use `Logger.gameTable`; check/handle `session.queryAuthorization` and skip silently when denied; consider starting hand tracking only on demand. [[OPEN since CODE_AUDIT_3dTable §5.13] (log category NEW)]
  - **Status:** Fixed 2026-11-15 — `Logger.gameTable`; `queryAuthorization` skips quietly when hand tracking is denied. On-demand start was not done.
- **4.9 "Unknown Player" is a hard-coded English string in the delivery log** — Modules/GameRPG/Controller/LogGameController.swift:254 — _GameRPG Controllers_. Use a localized string with `bundle: .module`.
  - **Status:** Fixed 2026-11-15 — "Unknown Player" is a localized string (de/th added).
- **4.10 Combine kept as a Task container; artwork task still unstructured** — Modules/AudioRPG/Controller/AudioController+Observation.swift:57-61 — _AudioRPG_. Store `[Task<Void, Never>]` in the model and bridge KVO through an `AsyncStream`; make the artwork load a `.task(id:)` body that awaits a `@concurrent` function. [[OPEN since CODE_AUDIT_Audio2 §3.7/§4.1; CODE_AUDIT_25 §4.1]]
  - **Status:** Fixed 2026-11-15 — the KVO publishers are an `AsyncStream` (`changes(of:on:)`, newest-8 buffer, deduplicated), the model stores `observationTasks`, Combine is gone from AudioRPG; the artwork load is awaited by the view's `.task(id:)`, so `artworkLoadTask`/`cancelArtworkLoad` are removed.
- **4.11 AnyView in four ViewControllable/EditControllable overrides** — Modules/CharacterRPG/Controller/ViewController.swift:13-26 — _CharacterRPG_. If the protocols are touched anyway, make them return `some View` via associated types or a type-erased wrapper owned by CoreRPG; otherwise leave.
  - **Status:** Not changed — the finding says to leave it unless the CoreRPG protocols are reworked.
- **4.12 UIKit leftovers in the scanner** — Modules/SpaceRPG/Record/ShotFileInfo.swift:12 — _SpaceRPG + TableRPG_. Remove the import; either call begin/end generating around the capture view or derive the rotation from the scene geometry.
  - **Status:** Fixed 2026-11-15 — unused `import UIKit` removed from `ShotFileInfo.swift` (device-only file, not compiled by the simulator builds). `CaptureOverlayView` and `ModelView` still use `UIDevice`/UIKit.
- **4.13 UTIs for `.gmz`/`.gms` are both exported and imported in the same plist** — Resources/Info.plist:130-188 vs :370-430 — _Sources + Resources_. Keep only the exported declarations for the app's own types; leave imported declarations for `org.universalvtt.map`.
  - **Status:** Fixed 2026-11-15 — the imported `gmz`/`gms` declarations are removed from Info.plist and InfoTV.plist (the exported ones stay); the empty imported array in InfoTV.plist went too.
- **4.14 tvOS and iOS targets carry keys and settings that belong to other platforms** — MasterRPG.xcodeproj/project.xcproj:1506-1512 — _Sources + Resources_. Trim per-target settings to the platform's real capabilities.
  - **Status:** Partly fixed 2026-11-15 — the macOS-only Desktop/Documents/Downloads folder usage keys are removed from the MasterRPG and MasterTV targets. Camera, photo library, document browser and open-in-place keys stay: removing them needs an App Store validation run.
- **4.15 tvOS has no `com.apple.developer.group-session` entitlement although GroupActivities code is compiled for it** — Resources/MasterTV-Debug.entitlements, Resources/MasterTV-Release.entitlements — _Sources + Resources_. Gate the SharePlay controllers with `#if !os(tvOS)` or add the entitlement deliberately. [[OPEN since CODE_AUDIT_17 §6.12] (unverified at runtime)]
  - **Status:** Fixed 2026-11-15 by gating, not by adding the entitlement — `RPGSharePlayController.supportsGroupSessions` is false on tvOS, so `startSharing` and `startSessionObserver` do nothing there (the activity is already not offered on Apple TV).
- **4.16 macOS entitlements use the iOS key name for push** — Resources/MasterRPG-Mac-Debug.entitlements:5-6, Resources/MasterRPG-Mac-Release.entitlements:5-6 — _Sources + Resources_. Confirm with a signed Release archive (`codesign -d --entitlements :-`) that the Mac build carries the macOS key; otherwise change the key in the Mac files.
  - **Status:** Fixed 2026-11-15 — a signed Debug Mac build carried no push entitlement at all with `aps-environment`; both Mac files now use `com.apple.developer.aps-environment` and the signed build shows it (development). The Release file (production) was not archived.

## 5. Bugs / logic errors

### 5.1 File replacement during a running game deletes the file the library item still references
- **Location:** Modules/CoreRPG/Controllable/EditControllable+File.swift:131-187 (`replaceFile`, esp. 177-181), 239-280 (`writeFile`, 276-279); callers without forceSave: Modules/CoreRPG/FileViews/FileReplacementConfirmation.swift:69, Modules/PhotoRPG/Controller/EditController.swift:73
- **What:** `replaceFile` / `writeFile` store the new `FileUrl` with `reset(fileUrl:itemId:)` (forceSave false), which in game mode lands in game memory only (`ItemControllable.replace` -> `replaceInGameMemory`), and then delete the old stored file via `deleteReplaced`; the "used elsewhere" check (`isFileUsedElsewhere(..., excluding: itemId)`) deliberately excludes the item itself, so the library copy that still points at the old file is not considered.
- **Why:** GM replaces a photo/PDF/3D file of an item in the editor while a game runs -> the new file is only in game memory, the old file is removed from disk/iCloud; when the game ends (game memory dropped) the library item references a deleted file (data loss). Only the Intents path passes `forceSave: true` (writeFile) and knows about this; `resetFile(url:)` has no forceSave parameter at all and FileImporterView/ItemDetailContentView/InlineImporterView do not gate on `isGameMode`. Not reproduced at runtime.
- **Action:** In game mode either persist the new file on the library item (`persistFileUrl`, as `copyFile` and `movedFileTree` already do) or skip deleting the old file until the library item references the new one; add a `forceSave` parameter to `resetFile(url:)`. Add a test with `isGameMode = true`.
- **Severity:** High   **Area:** CoreRPG Controllable/Import/Links
- **Status:** Fixed 2026-11-15 — `resetFile(url:)`/`replaceFile` take `forceSave` (default true), the reset happens before the delete, and every delete is guarded by `isStillReferencedByLibraryItem`, so a file the library item still points at is never removed during a game. `resetPhoto` persists too. Tests: `FileReplacementTests` (game mode).

### 5.2 `TableRollRange` reads "00" as 0, so d100 rows such as "96-00" never match rolls 97-100
- **Location:** Modules/CoreRPG/Text/TableRollRange.swift:12-23 (consumers Modules/TableRPG/Controller/TableGenerationController.swift:241-254, Modules/TableRPG/Controller/GameController.swift:139-148, Modules/CoreRPG/Links/QuickLinkScanner.swift:35)
- **What:** The selector is parsed into integers with `Int($0)`, so "00" becomes 0 and "96-00" becomes `0...96`. The d100 convention (and most printed/PDF tables) uses 00 for 100. Non-ASCII numerals (`isNumber` accepts "½", "²") are silently dropped by `compactMap`, which shifts the remaining values, and negative selectors ("-1 to 2") are not supported. There is no test for this type (grep of Tests finds none).
- **Why:** A rolled 97-100 on a "96-00" row finds no entry (the row only matches 0...96, which earlier rows already claim), so the roll result is empty in the live roll UI and in game mode for the most common table size. Imported tables from PDFs hit this directly.
- **Action:** Treat an all-zero token with length >= 2 as the die maximum (100, or 10 for "0" on a d10 if the table size is known); restrict digits to ASCII (`isASCII && isNumber`); add table-driven tests ("1-5", "96-00", "00", "7", en/em dash, "5 – 10", "*12*").
- **Severity:** High   **Area:** CoreRPG Foundry/Sheet
- **Status:** Fixed 2026-11-15 — an all-zero token of two or more zeros is the die maximum ("96-00" → 96...100, "00" → 100, "00-09" → 0...9); only ASCII digits count. New `TableRollRangeTests`.

### 5.3 Export and game reveal do not follow group entries (entry.adventureId)
- **Location:** Modules/AdventureRPG/Controller/ExportController.swift:63-128 (BFS visit closure); Modules/CoreRPG/ItemList/GroupableEntryEditing.swift:14-60 (how groups are created, entry content is only a copy of the description); Modules/CoreRPG/Controllable/GameControllable.swift:300 (reveal uses `exporting(ids:)`); compare Modules/CharacterRPG/Controller/ExportController.swift:70-72 (adds `entry.valueId` to the BFS)
- **What:** `exporting(itemIds:)` walks only links found in entry content and folder members; the hidden group adventure that an entry stands for (`adventureId`, created by addNewGroup/convertToGroup/moveIntoGroup) is never added, whereas Character does follow `valueId`.
- **Why:** Revealing or sharing a single adventure (game `createGameData`, single-item .gmz export, "send to player") ships the parent without its group children. On the receiving device `SheetController.entryNameDescription` (SheetController.swift:34-39) resolves the missing group to an empty model, so the group entry shows blank name and text. `exportingAll` is unaffected (groups are only groupHidden, not totalHidden) and `ExportControllerTests` only covers link-based children, which is why nothing caught it.
- **Action:** Add `entry.adventureId` (when it resolves via `itemSync`) to `childIds` in the visit closure, and add a test mirroring Character's group-export test (export one adventure with a group entry, expect the group id in the result).
- **Severity:** High   **Area:** AdventureRPG
- **Status:** Fixed 2026-11-15 — the BFS visit closure adds `entry.adventureId` when it resolves. Test `exportingFollowsGroupEntries`.

### 5.4 Dice bag in the editor appends the same die (same id) on every tap
- **Location:** Modules/DiceRPG/View/DiceBag.swift:11-22 (static catalog with fixed ids) and :56-60 (`root.editController.add(die: die, ...)`); Modules/DiceRPG/Controller/EditController.swift:14-19 (`editModel.dice.append(die)` with no `duplicate()`)
- **What:** `DiceBag` passes the catalog's static `DieModel` straight to `add(die:)`. Tapping "d20" three times (the usual way to build "3d20") puts three dice with one identical `id` into the model. `GameDiceBag` does it right (`generateDie` makes a new UUID); the intent path builds a fresh die.
- **Why:** Everything keys on die id: `ForEach(model.dice)` in `DiceViewer` (duplicate identities), `remove(die:)`/`resetDie`/`roll(die:)` use `firstIndex(where: id)` so tapping the second die removes, rolls or resets the first one, `GameController.resultColor`/`diceSuccess` look up by die id so all duplicates show the first die's success colours, and `DieViewerView`'s rotation reset writes into the first die. The duplicate ids only disappear after a reload because `DataController.dice(from:)` hands out new UUIDs (so the bug heals on relaunch or a CloudKit refresh, which hides it in testing). The CODE_AUDIT_Dice §7.2 fix (making the catalog `static`) made the ids stable across redraws, which also made repeated taps within a session collide.
- **Action:** In `DiceBag` (or `EditController.add(die:)`) store `die.duplicate()`/a fresh-id copy. Add a test that two `add(die:)` calls with the same input give distinct ids.
- **Severity:** High   **Area:** DiceRPG
- **Status:** Fixed 2026-11-15 — `EditController.add(die:)` stores `die.duplicate()` (fresh id), so the catalog die can be added any number of times. Test `addingTheSameCatalogDieTwiceKeepsDistinctIds`.

### 5.5 The compare option and value are never evaluated unless "Add dice" is on
- **Location:** Modules/DiceRPG/Controller/GameController+DiceResult.swift:37 (`checked = sumResult > 0`) and :147-155 (`maxValuePerDice`); Modules/DiceRPG/Dice/DiceOptionEditor.swift:26-32; Modules/DiceRPG/Model/DiceModel.swift:184-197 (`CompareValue.check(value:against:)`, no caller in Modules, Sources or Tests)
- **What:** `calculate` marks a roll as checked when the sum is above 0. `compareOption`/`compareValue` only act through `maxValuePerDice`, which returns the die maximum unless `addDiceEvery > 0` (the DSA-style "roll under per die" mode). The editor offers "Check for < <= >= >" with a value independently of "Add dice".
- **Why:** A d20 with "Check for <= 15" and no Add dice shows `...<=15 ∑12 ✅` for every roll: the result text, the checkmark in `DiceGameResult`/`DicePlayer`, the Quick Dice value button tint, the success/failure haptic, the widget's `checked` and the statistics event (`GameStatisticsController`) all say success. The git history shows `check(value:against:)` once existed for exactly this and was orphaned.
- **Action:** Decide the intended semantics. Either evaluate `compareOption.check(...)` against the sum (or per die) when `addDiceEvery == 0` and use it for `checked`, or hide the "Check for" section unless Add dice is active, then delete the dead method. Add a test with a compare-only dice (existing tests only cover the `addDiceEvery` set-up).
- **Severity:** High   **Area:** DiceRPG
- **Status:** Fixed 2026-11-15 — decision: compare the sum. New `GameController.isChecked(item:sum:)`: with `sumUp`, no Add dice and a Check-for option, `checked` is `compareOption.check(sum, compareValue)` (so `CompareValue.check` has a caller again); with Add dice (compare spent per die) or no option it stays `sum > 0`. Test `compareOptionDecidesTheCheckWithoutAddDice`.

### 5.6 Weather-to-Photo link is registered under the Adventure module and is dropped by every link validation
- **Location:** Modules/WeatherRPG/Model/WeatherModel.swift:208-219 (`changedLinkRegisterModels`, source `ItemRowModel(itemId: id, typeId: .adventure)`); no `linkRegisterModels` override, so the protocol default `[]` applies (Modules/CoreRPG/Links/LinkRegisterListModel.swift:117-118); consumers Modules/WeatherRPG/Controller/LinkController.swift:48 (`resetLinkRegister`), Modules/CoreRPG/Links/LinkRegisterController.swift:110, :133, Modules/CoreRPG/Controllable/LinkControllable.swift:322-327
- **What:** The source of the registered link names `.adventure` instead of `.weather` (copy-paste from AdventureModel), and `linkRegisterModels` (the full list used on first import, by `resetLinkRegister` and by `registerImportedLinks`) is not implemented, unlike `TableModel+Links.swift:7-9`.
- **Why:** `LinkRegisterController.used(for:)` resolves the source item in the Adventure module with a Weather id, gets nil and drops the row, so deleting or trashing a Photo shows no "used by Weather" warning. `repairLinks(for:)` calls the Adventure module's `validateLinks(on:)` with the Weather id, so a Weather whose Photo was deleted keeps a dangling `photoId`. `LinkController.validateLinks` ends in `resetLinkRegister(replacedItem)`, which clears the source's registered links and re-registers `[]`, so a Validate/Repair pass removes even a correctly registered Weather photo link. A weather imported from a file also never registers its photo.
- **Action:** Use `.weather` as the source type, add `linkRegisterModels` as `changedLinkRegisterModels(oldValue: .empty).added` like Table does, and let the next `validateLinks` pass re-register existing rows (the clear is keyed by source id, so rows saved with the wrong type are removed by it). Extend `Tests/WeatherRPGTests/LinkControllerTests.swift` to assert the source type and that `validateLinks` keeps a valid photo link.
- **Severity:** High   **Area:** RuleRPG + WeatherRPG
- **Status:** Fixed 2026-11-15 — source type is `.weather`, `linkRegisterModels` added (as Table). Test `photoLinkRegistersWithWeatherSource`.

### 5.7 Time, rain intensity and rain angle sliders edit the live model and are never saved
- **Location:** Modules/WeatherRPG/View/WeatherConditionEditor.swift:55-70 (`Slider(value: $model.time)`); Modules/WeatherRPG/View/WeatherStormEditor.swift:96-107 (`$model.rainIntensity`), :110-125 (`$model.rainAngle`); model source Modules/WeatherRPG/Route/WeatherRoute.swift:66 (`itemSync`, the stored instance)
- **What:** Three of the eight editable weather values bind a `@Bindable` slider straight to the stored `WeatherModel` and never call `EditController.save`; the other values (clouds, storm type, lightning, photo, direction) go through `EditIdentifierModel` and `editController.reset`. No other module binds a slider to a live model, and I found no autosave or observation-driven save in CoreRPG.
- **Why:** The change is visible at once, but it never goes through `replace(with:)`, so no Core Data write, no CloudKit sync, no `weatherUpdate` stamp, no undo and no game-memory/library separation (it edits the library item during a game). If nothing else is edited afterwards the value is lost on relaunch; if another property is saved later, `editModel(for:)` copies the mutated live item and persists the old slider edit by accident. Reasoned from code; please drag the Time slider, relaunch and compare.
- **Action:** Route the three sliders through `EditIdentifierModel` plus `editController.reset(...)` like the lightning sliders (add the missing `reset(time:)`, `reset(rainIntensity:)`, `reset(rainAngle:)` overloads), saving on the end of the drag.
- **Severity:** High   **Area:** RuleRPG + WeatherRPG
- **Status:** Fixed 2026-11-15 — time, rain intensity and rain angle edit an `EditIdentifierModel` draft and save through new `reset(time:)`/`reset(rainIntensity:)`/`reset(rainAngle:)` when the drag ends (the viewer updates at drag end, not live). Test `WeatherEditControllerTests`.

### 5.8 Lightning sliders save only when one change event jumps by 1 or more
- **Location:** Modules/WeatherRPG/View/WeatherThunderEditor.swift:150-170 (`SignificantChangeModifier`), used at :95, :113, :131
- **What:** `onChange(of:)` compares the previous event value with the new one and calls `editModel.save()` only if `abs(old - new) >= 1`, i.e. per event, not against the last saved value.
- **Why:** A normal drag of the Max Bolts slider (range 0-10, about 0.03 per point) or a slow drag of Frequency/Fork (0-100) produces deltas far below 1, so the new value is never saved; the slider shows the new value until the view resyncs, then snaps back to the stored one. Only fast swipes persist.
- **Action:** Save when the drag ends (`Slider(onEditingChanged:)`) or compare against the last saved value; use a step of 1 for the bolt count, which is a whole number anyway.
- **Severity:** High   **Area:** RuleRPG + WeatherRPG
- **Status:** Fixed 2026-11-15 — the lightning sliders save when the drag ends (`Slider` editing callback); `SignificantChangeModifier` removed; Max Bolts uses step 1. Test `WeatherEditControllerTests` (sub-1 changes persist).

### 5.9 Tag register has no hydration-failure guard and can overwrite in-memory edits when it loads
- **Location:** Modules/CoreRPG/Controllable/TagController.swift:26-60 (`setup`), 134-189 (`savePendingTags`)
- **What:** A failed or non-castable fetch in `setup` returns an empty dictionary (`catch { return [:] }`), so the in-memory tag table is empty and `savePendingTags` then treats every persisted row of an affected module as stale and deletes it (CloudKit-mirrored, so on all devices). `LinkRegisterController` got a `hydrationFailed` guard for exactly this (CODE_AUDIT_23 §5.12); `TagController` did not. The hydration also merges with `{ _, new in new }`, so persisted counts replace counts of tags added in memory before the fetch finished.
- **Why:** One transient fetch error followed by any tag edit wipes that module's tag suggestions on every device; counts drift after a slow first fetch. Rare, but silent and replicated.
- **Action:** Mirror the link register: track `hydrationFailed`, retry the fetch before saving, skip the save while it is failing; merge by adding persisted counts only for tags not touched in memory (or apply hydration before accepting edits).
- **Severity:** Medium   **Area:** CoreRPG Controllable/Import/Links

### 5.10 download(fileUrl:) passes a percent-encoded path as a file path
- **Location:** Modules/CoreRPG/Files/FileUrlDataController+Create.swift:511-519 (feeds CloudDocumentController.download(filePath:) at Modules/CoreRPG/Files/CloudDocumentController.swift:127-131 and fullUrl(filePath:) at :87-89); callers Modules/PdfRPG/Controller/ItemController.swift:43, Modules/CoreRPG/Controllable/ImageCacheControllable.swift:174
- **What:** `download(fileUrl:)` hands `fileUrl.rawUrl.absoluteString` (percent-encoded, e.g. `/Map%20Name.png`) to `fullUrl(filePath:)`, which splits it on `/` and calls `URL.append(path:)`, which encodes the `%` again.
- **Why:** Verified with a scratch program: `append(path: "Map%20Name%20%C3%A9.png")` yields a path whose file name literally contains `%20`. For any `.newCloud` file whose name has a space, accent, `#`, `?` or other encoded character, the explicit iCloud download request targets a non-existent file and throws (Pdf logs an error, the image cache swallows it with `try?`). Every other call site uses `path(percentEncoded: false)` or `pathComponents`. The later coordinated read still pulls the bytes, so the effect is a missing prefetch plus error logs, not data loss.
- **Action:** Resolve through `cloudDocumentController.fullUrl(fileUrl: fileUrl.rawUrl)` (decoded components) instead of the absolute string, and add a test with a name containing a space and a non-ASCII character (no test calls `download(fileUrl:)` today).
- **Severity:** Medium   **Area:** CoreRPG Files/Persistence/Model

### 5.11 CloudContainerCache caches a nil container for the whole session
- **Location:** Modules/CoreRPG/App/CloudContainerCache.swift:38-55; consumers Modules/CoreRPG/App/AppGroup.swift:80-82 (`preferredRootUrl`)
- **What:** When `ubiquityIdentityToken` is non-nil but `url(forUbiquityContainerIdentifier:)` returns nil (documented to happen while the container is still being provisioned, first launch after sign-in, or iCloud Drive off), `.resolved(nil)` is stored and only `NSUbiquityIdentityDidChange` invalidates it.
- **Why:** `preferredRootUrl` then falls back to the App Group container for the whole run. File-backed modules (Audio/Pdf/Photo/Space) look up their relative paths there, so iCloud files seem missing and new imports are written to a root that the next launch (with the container resolved) no longer reads. The token-less case is rightly cached (a sign-in posts the notification); the token-present case has no such signal.
- **Action:** Do not cache a nil result when an identity token exists (retry on the next read or after a short delay), or at least invalidate on `didBecomeActive`.
- **Severity:** Medium   **Area:** CoreRPG Files/Persistence/Model

### 5.12 Scene state is one value per SceneId although viewer windows are multi-instance
- **Location:** Modules/CoreRPG/ScenesManager/ScenesManager.swift:145-170, 218-233; Modules/CoreRPG/ScenesManager/Modifiers/SceneTrackerModifier.swift:44-76; Sources/MasterRPG/Window/WindowViewerList.swift:70-85
- **What:** `openWindow(_:selection:)` deliberately opens an extra window when the scene is already `.opened`, but `SceneStateBox` holds one state per `SceneId`, and every window's tracker writes it (`.onDisappear` -> `.closed`, scenePhase `.background` -> `.closed`).
- **Why:** Open two Photo viewer windows (same `viewerId`) and close one: the state becomes `.closed` while the other is still open. The menu toggle then shows "closed", and `openWindow(_:)` / `openWindow(for:)` open yet another window instead of treating the module as open. On macOS and iPadOS a background scene of one window flips the shared state the same way.
- **Action:** Count open windows per scene (increment on first `.active`, decrement on disappear) and derive `.opened/.closed` from the count, or key the trackers by a per-window token.
- **Severity:** Medium   **Area:** CoreRPG UI 1

### 5.13 CachePhotoView drops file changes during a load and can erase a cached image
- **Location:** Modules/CoreRPG/LGViews/CachePhotoView.swift:28-31, 69-93
- **What:** `initImage()` returns early while `isLoading`, so a `model.fileUrl` change during an in-flight load is ignored and nothing re-triggers afterwards; the load is an unstructured `Task(priority:)` that is not cancelled when the view disappears or the url changes; and `setCachedImage/Thumbnail(newImage, ...)` runs even when the load returned `nil`.
- **Why:** Replacing a photo's file (or a file becoming available) while the previous decode is running leaves the old or placeholder image until something else forces a reload. A transient `nil` result overwrites a good cached image, which `ThumbnailRowPhotoView` explicitly guards against ("A transient read/cancellation must not erase a thumbnail").
- **Action:** Use `.task(id: model.fileUrl)` like `ThumbnailRowPhotoView` (structured, cancelled and restarted on change) and only publish non-nil results.
- **Severity:** Medium   **Area:** CoreRPG UI 1

### 5.14 Tag search tokens are never applied to the search
- **Location:** Modules/CoreRPG/LGViewModifiers/SearchItemListViewModifier.swift:20-56; Modules/CoreRPG/Model/SearchModel.swift:19, 83-106; Modules/CoreRPG/Controllable/FolderListControllable.swift:69-99
- **What:** `selectedTokens` is read by nothing except this modifier (grep over Modules and Sources: no other consumer). The search pipeline receives only `searchModel.searchText`. Picking a tag suggestion appends a token and clears `searchFieldText` (and thereby `searchText`), and the pipeline has no `@`-prefix handling, so a typed `@dra` is searched as plain text and matches nothing.
- **Why:** The search field's prompt promises "Search or use @ for tags"; choosing a suggestion shows a token chip but the list is not filtered. Unverified at runtime, but the code path has no filter step. Removing one token of several does not refresh either (`guard selectedTokens.isEmpty`).
- **Action:** Decide: either feed `selectedTokens` into `searchRootControllable.results(text:)` (tag filter) and refresh on every token change, or remove the tokens, suggestions, `updateTagSuggestions` and the `@` prompt. Add a test for the chosen behaviour.
- **Severity:** Medium   **Area:** CoreRPG UI 1

### 5.15 `move(itemId:entryIds:)` replaces the entry list with only the ids it is given
- **Location:** Modules/CoreRPG/ItemList/EntryDataEditable.swift:362-367 (callers Modules/CoreRPG/Sheet/SheetRootModel+ContextMenu.swift:25,49)
- **What:** `item.entries = entryIds.compactMap { id in item.entries.first { $0.id == id } }` rebuilds the array from the ids the sheet passes. Any entry of the item that is not in `entryIds` (hidden or group-hidden entries the sheet does not list, or ids that failed to resolve) is dropped silently on a reorder, and the result is saved.
- **Why:** Data loss path on reorder if the sheet's entry list is ever a subset of the item's entries (not confirmed for every module; sheets that filter by search call `updateFilteredEntries` after, which suggests the list is complete today). The O(n^2) `first` lookup is also repeated per id.
- **Action:** Keep entries missing from `entryIds` (append them in their old relative order) and build a dictionary for the lookup; add a test with a hidden entry.
- **Severity:** Medium   **Area:** CoreRPG UI 2

### 5.16 Failed map photo load: state assignments are immediately undone and the load retries on every sync
- **Location:** Modules/GameRPG/Table3D/GameTableModel+MapSync.swift:124-134 (and `clearBoardImage` at Modules/GameRPG/Table3D/GameTableModel+Broadcast.swift:40-47)
- **What:** In the `image == nil` branch `currentPhotoId = photoId` and `currentPhotoVersion = metadata?.version` are set, then `clearBoardImage()` sets both back to `nil`; the intent ("remember which photo failed") is dead code.
- **Why:** `updateFogOfWar` sees `metadata?.version != currentPhotoVersion` and calls `loadMapPhoto` -> `fetchPhotoImage` again on every remote map update, pin move and fog toggle while the photo is missing (a player whose photo file has not arrived). Each retry is an async cache/disk lookup, and `fogSignature` stays `nil`.
- **Action:** Either drop the two dead assignments and document "retry on every sync" as intended, or keep the failed photo id/version after `clearBoardImage` (reorder) and retry only when the photo item changes, like `failedPinPhotos` does for pin photos.
- **Severity:** Medium   **Area:** GameRPG Table3D

### 5.17 Player-dice reset keys on display names and breaks with two players of the same name
- **Location:** Modules/DiceRPG/Controller/GameController.swift:290-301 (callee); Modules/GameRPG/Controller/MasterController+Control.swift:83-88 and Modules/GameRPG/Controller/PlayerController+Control.swift:86-87 (callers)
- **What:** `resetPlayerDice(to:)` does `names.compactMap { name in playerDice.first { $0.name == name } }`. `addGameDiceResult` deliberately keeps one die set per sender id so two players with the same name keep their own dice, but the next `resetPlayers()` (every roster change on the master; every master broadcast that is applied on a player) maps both "Alex" entries to the first die found.
- **Why:** With players A and B both named "Alex" the list becomes [dieB, dieB]: A's die is lost, B's appears twice with the same id (duplicate `ForEach` identity in `DicePlayer`), and `playerSupporterTiers`/`playerDiceSenders` are pruned for A's die. The callers also disagree on the list: the master excludes observers, the player passes every `controls` name (observers and hidden players included, plus the master's name), so the two devices prune differently.
- **Action:** Reset by sender id (`playerDiceSenders`) instead of by name, using the roster ids; make master and player build the same list. Add a test with two same-named players (`GameControllerTests` only covers distinct names).
- **Severity:** Medium   **Area:** GameRPG Controllers

### 5.18 Version-mismatch notices are claimed once per app run, never reset between games
- **Location:** Modules/GameRPG/Network/GameNetworkControllerModel.swift:130-148, Modules/GameRPG/Network/GameNetworkController+PlayerDelegate.swift:48-66, Modules/GameRPG/Network/GameNetworkController.swift:147-166 (resets only `playerRoutes`), Modules/GameRPG/Root/GameRoot.swift:87-88 (controller created once per app run)
- **What:** `reportedMismatches`, `hasSentVersionNotice` and `versionNoticeConnectionIds` are never cleared; `stopGame()` only calls `model.playerRoutes.reset()`.
- **Why:** after the first "update the app" mismatch (or the first notice sent to a master), a second game in the same app run against an incompatible peer shows no alert and sends no notice, so the user sees a join that silently does nothing, which is exactly what the notice exists to prevent. `versionNoticeConnectionIds` also grows by one UUID per incompatible connection for the life of the process (tiny, but unbounded).
- **Action:** Clear the three claim sets in `GameNetworkController.stopGame()` (or on `startMasterGame`/`startPlayerGame`) next to `playerRoutes.reset()`.
- **Severity:** Medium   **Area:** GameRPG SharePlay/Network

### 5.19 Dashboard hides its filters when the selected range has no games
- **Location:** Modules/GameRPG/Statistics/View/GameStatisticsDashboardView.swift:243-266 (filter only in the final `else`), Modules/GameRPG/Statistics/Model/GameStatisticsTypes.swift:234 (default `.lastSixMonths`), Modules/GameRPG/Statistics/View/GameStatisticsCustomizationView.swift (no range control)
- **What:** `GameStatisticsFilterView` is rendered only when `summary.sessionCount > 0`; with zero games in the range the dashboard shows the sample ("preview") dashboard instead, and the customization page has no date-range control.
- **Why:** A user whose last counted game is older than 6 months (or who picked "30 Days" and then did not play for a month) sees sample data as if they had none, and cannot widen the range to see their real statistics. The persisted configuration keeps the narrow range.
- **Action:** Show the filter bar above the placeholder whenever any stored game exists (or when the range is not `.allTime`), and use an "no games in this range" empty state instead of the sample dashboard in that case.
- **Severity:** Medium   **Area:** GameRPG Views/Battle/Statistics

### 5.20 Remote dice timestamp is used as the event time and moves session/participant activity
- **Location:** Modules/GameRPG/Statistics/Controller/GameStatisticsController.swift:28 (`diceResult?.timestamp ?? occurredAt`), Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift:199-205, 207-208, 356-357, 28
- **What:** `occurredAt` of a dice event is taken from `DiceResultModel.timestamp`, which the roller's device sets from its own clock and which travels in the payload.
- **Why:** A peer with a skewed clock (or a crafted payload) with a future timestamp pushes `session.lastActivityAt` and `durationSeconds` into the future, makes `synchronizeParticipants` skip later (earlier-dated) updates for that sender (`date >= previousActivity` guard), and postpones launch recovery of an interrupted session (`date - lastActivity >= idleAge` stays false). The finish path recomputes duration from the real end date, so the visible damage is mostly limited to the roster/connected-time and interrupted sessions.
- **Action:** Clamp the event time to the local receipt time (`min(timestamp, occurredAt)`), or ignore the payload timestamp for session/participant bookkeeping.
- **Severity:** Medium   **Area:** GameRPG Views/Battle/Statistics

### 5.21 Cancelling or swipe-dismissing "Save and Quit" still quits the game
- **Location:** Modules/GameRPG/GameViews/MasterGameScreen.swift:49-60, 95-99 (`showExport` -> `endGame()`), Modules/CoreRPG/FileViews/ExportProgressPanelView.swift:59-62, 66-76 (Cancel calls `finishAction()`; `.onDisappear` cancels the export)
- **What:** `onChange(of: showExport)` ends the game whenever the export sheet closes, whatever the outcome; the sheet's Cancel button, a swipe-down dismissal, a failed export and a cancelled file mover all close it the same way.
- **Why:** A game master who picks "Save and Quit", then cancels the export (or the save dialog) because the destination was wrong, loses the running game and the unsaved game state without a further prompt. The alert's own "Cancel" is one step earlier and does not help here.
- **Action:** End the game only when the export finished successfully (`finishedAction` after `.finished`); on cancel or failure close the sheet and keep the game running. Decide whether a failed save should offer "Quit anyway".
- **Severity:** Medium   **Area:** GameRPG Views/Battle/Statistics

### 5.22 `entry(for:in:)` returns hex-grid cells, so pin drops on a hex map are attributed to a cell, not a room
- **Location:** Modules/MapRPG/Map/MapEditorSession+Content.swift:161-163; callers MapEditController+Pins.swift:50 (edit drop), MapEditor.swift:299 (game drop), MapEditorActionRouter.swift:337-343 (editor character action)
- **What:** `entries.roomNodes.last { $0.path.contains(location) }` also matches the hex cells (appended last, covering the whole map), so with a hex grid active the "room under the point" is always a cell. `addMonsters` in the same controller knows to skip hex cells (`!$0.isHexGrid`, MapEditController+Pins.swift:77), this lookup does not.
- **Why:** In the editor, `appendCharacterLinks` then writes the character link into the hex cell's `content` (MapEditController+Rooms.swift:128-158), not the room the pin sits in; hex cells get new ids on every rescale, so the link silently vanishes. The real room is never found on a hex map.
- **Action:** Skip `isHexGrid` nodes in `entry(for:in:)` (or add a second lookup for hex), prefer topmost non-hex room; add a test with a hex grid plus a room.
- **Severity:** Medium   **Area:** MapRPG Map

### 5.23 "Edit Tile" toolbar button opens the full map editor, and on macOS/visionOS does not select the map
- **Location:** Modules/MapRPG/View/EditTileButton.swift:12-25; compare Modules/MapRPG/View/MapEditorButton.swift:13-19 and Modules/MapRPG/View/DisplayConfigEditor.swift:188-194
- **What:** `EditTileButton` navigates to `MapEditorRoute.mapEditor(model.id)` (iOS/tvOS) and opens `.mapEditor` (macOS/visionOS), where the label and `DisplayConfigEditor` use `MapEditorRoute.mapTileEditor` and `.mapTileEditor`. On macOS/visionOS it also never sets `editController.editorModel.sheetEditorModel.itemId = model.id`, which `MapEditorButton` and `DisplayConfigEditor` both do before opening the window.
- **Why:** The button next to "Map Editor" in the detail toolbar is a second copy of the map editor button. On macOS and visionOS the window's `MapEditWindow` reads `sheetEditorModel.itemId`, so it shows whatever item was set last (or "No map item is selected"), which can be a different map than the one the user clicked.
- **Action:** Route to `mapTileEditor` / `.mapTileEditor` and set the item id exactly as `DisplayConfigEditor.TileCoordinatesView` does; better, make both call one shared helper.
- **Severity:** Medium   **Area:** MapRPG rest

### 5.24 Cover-tile preview ignores the photo rotation and races on map switch
- **Location:** Modules/MapRPG/View/DisplayConfigEditor.swift:79-92 (`loadTileImage`)
- **What:** `let (fullImage, _) = ... fetchPhotoImage(...)` discards the rotation, then crops `tileCoordinates.bounds` out of the unrotated bitmap. Tile coordinates are canvas coordinates (EditController.rescaleCoordinates comment "the cover tile is a piece of the map image"; `CacheController.createThumbnail` rotates the source by `degrees` for the same reason). The load runs in an untracked `Task { }`, so a slow result for map A can assign `tileImage` after the editor switched to map B (`onChange(of: model.id)` reloads, but nothing cancels the older task). It decodes the full-size photo for a 120x80 preview and fetches with `useGame: true` in the library editor.
- **Why:** On a rotated map the thumbnail shows another area than the tile; after a fast switch it can show the wrong map's tile.
- **Action:** Use `.task(id:)` (auto-cancel), rotate through the same helper as `CacheController` (or use the thumbnail source, `useGame: false`), and downsample.
- **Severity:** Medium   **Area:** MapRPG rest

### 5.25 Adventure `diceId` is never exported
- **Location:** Modules/AdventureRPG/Controller/ExportController.swift:63-76 (photoId and tablePlayers handled, diceId not); compare Modules/CharacterRPG/Controller/ExportController.swift:50-52 and Modules/MapRPG/Controller/ExportController.swift:65,111
- **What:** `item.diceId` is not collected into `diceIds`; the dice only travels when it is also linked in entry text.
- **Why:** A single-adventure .gmz or shared package arrives with a `diceId` pointing at nothing, and `validateLinks` later clears it (LinkController.swift:116-120), so the GM's attached dice is silently lost on the receiving device. (For the players audience it may be deliberately GM-only; the code does not say.)
- **Action:** Insert `item.diceId` (after `validateLink`) into `diceIds`, skipping it when `ExportAudience.current == .players` if it is meant to be GM-only; document the decision.
- **Severity:** Medium   **Area:** AdventureRPG

### 5.26 Group entry edits write the raw entry name into the group item
- **Location:** Modules/AdventureRPG/Controller/EditController.swift:95-103 (`update(itemId:entryId:name:content:forceSave:)`); compare Modules/CharacterRPG/Controller/EditController.swift:310-313 (`name.withoutLink()`) and Modules/CoreRPG/ItemList/GroupableEntryEditing.swift:49 (also strips)
- **What:** For an entry with `adventureId`, `reset(name: name, itemId: adventureId)` is called with the unstripped `name`, while every other group path (convertToGroup, Character's update) uses `withoutLink()`. The sheet presents group entry names as `adventure.url(linkNumber: 0)` (SheetController.swift:35), i.e. a markdown link.
- **Why:** If the editor hands that link text back as `name`, the group adventure's own name becomes `[Name](RPG://ADVENTURES/...)`, a self-referencing link in its title, in lists and in Spotlight. Not reproduced; there is no test of `update` on a group entry in AdventureRPGTests.
- **Action:** Use `name.withoutLink()` for the group item (as Character does) and add a test with a group entry whose name carries the link form.
- **Severity:** Medium   **Area:** AdventureRPG

### 5.27 `diceId` merges by direction instead of by timestamp
- **Location:** Modules/AdventureRPG/Model/AdventureModel.swift:95 (`public var diceId: UUID?`), :204 (`diceId: other.diceId`), :313 (`diceId <=> model.diceId`); compare Modules/TableRPG/Model/TableModel.swift:186 (`diceId_` is a CRDT there)
- **What:** `photoId`, `name`, `tags`, `tablePlayers` merge as LWW registers, but `diceId` (like `displayState`, `parentId`, `groupId`) is a plain value that always takes `other`'s side in `merge`.
- **Why:** With two devices, an older copy arriving as `other` reverts the dice the GM just set or cleared on the newer device; which side wins depends on import direction, not on who edited last.
- **Action:** Make `diceId` a `CRDT<UUID?>` (decode with an epoch-stamped default like `noTablePlayers` for old files and add a nullable Core Data column or reuse the existing string), or document that it is intentionally last-importer-wins.
- **Severity:** Medium   **Area:** AdventureRPG

### 5.28 Play link on a playlist item outside a game stops the music and plays nothing
- **Location:** Modules/AudioRPG/Controller/LinkController.swift:37-41, Modules/AudioRPG/Controller/AudioController.swift:201-221
- **What:** The non-game branch of the `play` link calls `audioController.loadAndPlay(id:)`, which loads only the item's own file; a playlist item has `fileUrl == nil` and its tracks are its entries.
- **Why:** `add(audio:replace: true)` empties the playlist, replaces the AVPlayer item with nil and clears Now Playing; `set(currentId:)` then finds nothing and `preparePlay` bails. Tapping the play link of a playlist (folder-like audio item) in an adventure text silences the current music and starts nothing. The game branch (`requestPlay`) and the row/toolbar buttons (`playItem` -> `GameController.play`) resolve playlists, so only this path is wrong.
- **Action:** Route the link through `AudioRootModel.toggleItem`/`playItem` (or `GameController.play`) instead of `loadAndPlay`; additionally make `add(replace:)` keep the running player when `requests` is empty.
- **Severity:** Medium   **Area:** AudioRPG

### 5.29 Intent start and playlist-row removal ignore the "can control game audio" gate
- **Location:** Modules/AudioRPG/Root/AudioRootModel+Playback.swift:135-141 (`startPlayback`), 159-164 (`remove`); every other entry point folds in `IntentGameContext.canControlGameAudio()` (lines 18, 50, 64, 83, 110, 122, 147)
- **What:** `startPlayback(id:isGameRunning:networkActions:)` (used by `PlayAudioIntent.playFromIntent`) and `remove(id:...)` use the raw `isGameRunning` flag.
- **Why:** On a player device with audio sharing off the game drops the player's play command (doc on `canControlGameAudio`, CODE_AUDIT_Audio2 §5.14), so "Play <audio>" through Siri/Shortcuts does nothing while the dialog still answers "Playing ...". The pause that `remove` sends is dropped the same way.
- **Action:** Apply the same `&& IntentGameContext.canControlGameAudio()` fold at the top of both functions (and add a case to `AudioIntentGameTests`).
- **Severity:** Medium   **Area:** AudioRPG

### 5.30 Group-item repair keeps the first referencing entry, not the owner named by groupId
- **Location:** Modules/CharacterRPG/Controller/EditController+Repair.swift:165-196 (owner choice 170-177, stripping other owners 192-195, `removeOld` 198-213); the only test is Tests/CharacterRPGTests/ConvertControllerRepairTests.swift:601-624
- **What:** `repairGroupItemConstraints` sets `groupItem.groupId = owners.first` (first item in `itemDataModel.items` order with an entry whose `valueId` is the group) and clears the `valueId` of every other owner, without preferring the owner already recorded in `groupItem.groupId`.
- **Why:** If two Characters reference one group item (CloudKit merge, import, duplicate bug) and the real owner (matching `groupId`) is not first in item order, "Validate Folders" moves the group to the other character and removes the group entry from the real owner's sheet. The user loses a group row from the sheet they built, and the outcome depends on list order. The existing test is titled "non-authoritative owner" but passes only because the real owner is created first.
- **Action:** When `groupItem.groupId` is one of `owners`, keep it and strip the others; fall back to `owners.first` only otherwise. Add a test where the `groupId` owner comes second in item order.
- **Severity:** Medium   **Area:** CharacterRPG

### 5.31 Share-extension characters get photos but no portrait
- **Location:** Modules/CharacterRPG/Controller/CharacterDataController.swift:10-25 (`model.photos = photoIds`, `photoId` never set); consumers use `photoId`: Modules/CharacterRPG/Controller/SheetController.swift:42, View/ThumbnailPhotoRow.swift:14, Controller/GameController.swift:202; caller Sources/RPGShare/ShareExtensionSaveController.swift:102-103; test Tests/CharacterRPGTests/DataControllerTests.swift:132-153 asserts `photos` only
- **What:** A Character created from the share sheet stores the shared images in `photos` but leaves the portrait `photoId` nil, whereas the module's own rule (`EditController.add(selection:)`) is that the portrait is the first photo. The Map share path passes `photoIds.first` as its photo.
- **Why:** The new character shows no thumbnail, no portrait in the sheet and no player-pin photo until a manual photo edit or a Validate Folders run (`repairPhotoList`) fixes it.
- **Action:** Set `model.photoId = photoIds.first` in `addNewValue` and extend the test to assert it.
- **Severity:** Medium   **Area:** CharacterRPG

### 5.32 A d3 built from text or a number is `.number(3)`, not `.three`
- **Location:** Modules/DiceRPG/Model/RawDie.swift:143-164 (`Sides.sides(_:)` has no `case 3`), against :195 (decoder maps 3 to `.three`); callers Modules/DiceRPG/Controller/DataController.swift:147, Modules/DiceRPG/Model/DieModel.swift:210, Modules/DiceRPG/Model/DiceExpression.swift:57,68, Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+DiceAndValues.swift:57
- **What:** `RawDie(text: "d3")`, `.sides(3)` (Siri "3d3", widget, Foundry import) give `.number(3)`; the d3 from the bag and the JSON decoder is `.three`. They are not `==`.
- **Why:** After every Core Data reload (`dice(from:)` uses `RawDie(text:)`) a bag d3 turns into `.number(3)`, whose `colorCodes` is only `[.G]` and whose `name(for:)` returns the d20 image "D20G-1", so the die silently shows a d20 face. `RawDice.addDie` merges counters by `sides ==`, so "d3" from the editor plus "d3" from an expression is shown as "d3+d3". `DieModel.isSame` (die == die) reports a change between a local and a synced d3.
- **Action:** Add `case 3: return .three` to `sides(_:)` (or normalise in `RawDie.init`). Add a text -> RawDie -> text -> RawDie round trip test for every named side count.
- **Severity:** Medium   **Area:** DiceRPG

### 5.33 Roll haptic fires up to three times per roll and the first is always an error
- **Location:** Modules/DiceRPG/Game/Detail/DiceGameActionBar.swift:47-56; Modules/DiceRPG/Controller/GameController+PlayerDice.swift:86-113 (`rollDice` resets first, rolls 0.1 s later); Modules/DiceRPG/Game/Detail/DieViewerView.swift:54-65 (rotation reset 0.6 s later writes `dice` again)
- **What:** The `.onChange(of: gameItem.dice)` that drives `rollFeedbackCount` observes the whole `[DieModel]`. A roll changes it three times: `reset(for:)` (results cleared; `result.checked` is false for "not rolled"), the roll itself, and `DieViewerView`'s delayed `rotation = 0` write.
- **Why:** When the previous roll had results, every tap plays an error haptic at once, then the real outcome, then the same outcome again. The CODE_AUDIT_Dice §5.6 fix (watch `dice`) made the haptic fire, but on the wrong set of changes. Reading only; not device-verified.
- **Action:** Trigger the haptic from the roll itself (in the button action / `rollFunction` after the results exist) or compare `results` only and skip the all-empty state; ignore rotation-only changes.
- **Severity:** Medium   **Area:** DiceRPG

### 5.34 Tapping a single die replaces the dice's result category with a generic one
- **Location:** Modules/DiceRPG/Game/Detail/DiceRoll.swift:50-54 (`ResultCategory(id: itemId, module: .dice)`); Modules/DiceRPG/Controller/GameController.swift:172-182 (`createDiceResult` stores the category on the model); compare Modules/DiceRPG/Controller/GameController+PlayerDice.swift:118-124 (`shareRoll` keeps `resultCategory ?? item.resultCategory`)
- **What:** `DiceRoll.rollDice(_:)` hard-codes a `.dice` category and `createDiceResult` writes it into `item.resultCategory`. A dice linked from a character sheet had that character's category (set by `DiceInline`/Quick Dice through `rollDice(resultCategory:)`).
- **Why:** After one tap on an individual die in the overlay, later rolls of the whole set (which fall back to `item.resultCategory`) and the shared result are attributed to the dice module instead of the character. `ResultCategory` is what the table and battle round use to associate a roll with its participant (see DiceSnapshot.resultCategory doc), so initiative/health-style rolls stop landing on the character.
- **Action:** Use the same `shareRoll(of:networkActions:)` path as `rollDie(_:of:networkActions:)` (keeps the stored category) and do not overwrite `item.resultCategory` when none is passed.
- **Severity:** Medium   **Area:** DiceRPG

### 5.35 Rolling a library dice outside a game mutates the synced model
- **Location:** Modules/CoreRPG/Controllable/GenericGameController.swift:27-29 (`gameItem(for:)` falls back to the library item); Modules/DiceRPG/Controller/GameController+DiceResult.swift:213-243 (`reset(for:)`, `roll(die:for:)`); Modules/DiceRPG/View/DiceInline.swift:21-30; Modules/DiceRPG/Root/DetailRootView.swift:20-26; Modules/DiceRPG/Controller/LinkController.swift:18; Modules/DiceRPG/Intent/DiceIntents.swift:122-127
- **What:** With no game running, `DiceInline`, the Space-bar roll, roll links and the roll intents call `rollDice` on a dice that is not in `gameModel.itemData`, so `gameItem(for:)` returns the library `DiceModel` itself and the roll writes results and a random rotation into its `dice` (and thus a fresh `dice_.update` LWW stamp).
- **Why:** `DiceModel.merge` arbitrates every plain field (modifier, compare, coup, reroll, ...) by `mergedDice.update`. A roll made after another device's edit but before that edit syncs gives the local copy the newer stamp, so the remote change to modifier/coup/rerolls loses the merge. Roll results also appear in the dice list thumbnails and in `isSame` comparisons. Not verified end to end (depends on the offline timing), the mutation itself is verified by reading.
- **Action:** Roll on a game copy (`createGameDice`) or clear results without touching `dice_` (keep results outside the CRDT value); at minimum make the roll not bump the update marker.
- **Severity:** Medium   **Area:** DiceRPG

### 5.36 Photo analysis reports "Apple Intelligence is not available" for every fallback-class on-device error while PCC is disabled
- **Location:** Modules/GeneratorRPG/BasicAI/Providers/PhotoSummaryAnalyzer.swift:70-83
- **What:** when the on-device call throws an error the fallback policy maps to a reason (context too large, guardrail, rate limit, unsupported language), the code reaches `guard Self.isPrivateCloudComputeEnabled else { throw .modelUnavailable }`, discarding the reason and the original error.
- **Why:** `PRIVATE_CLOUD_COMPUTE_ENTITLED` is defined nowhere (grep of pbxproj/xcconfig/Package: no match), so this is the shipped configuration. A guardrail trip or rate limit on a perfectly available device shows "Apple Intelligence is not available. Photo analysis requires it." and the user is sent to Settings for nothing.
- **Action:** when PCC is off, rethrow the mapped on-device error (generationFailed with the error text, or a dedicated case carrying the `PhotoAnalysisFallbackReason.explanation`), keep `modelUnavailable` only for `.onDeviceUnavailable`/`.visionUnsupported`. Add a test with an injected failing on-device closure.
- **Severity:** Medium   **Area:** GeneratorRPG

### 5.37 Batch apply appends the description on every run and replaces tags, as three separate edits
- **Location:** Modules/GeneratorRPG/View/BatchTextSummaryExtractionView.swift:240-251
- **What:** `applyResult` appends `result.description` to the existing description each time, replaces all existing tags, and issues three separate `editController.reset` calls.
- **Why:** running the batch twice on the same item duplicates the generated paragraph; curated tags are lost without a prompt; three resets mean three saves/undo steps and a window where a CloudKit sync can upload a half-applied item. Items with empty text are marked `.completed` without being analysed (line 218-221), which hides that nothing was done.
- **Action:** skip the append when the description already ends with the generated text (or replace a marked generated block), merge tags instead of replacing, apply in one edit, and show a distinct "skipped" status.
- **Severity:** Medium   **Area:** GeneratorRPG

### 5.38 Pdf viewer does not reload when the item's file is replaced in place
- **Location:** Modules/PdfRPG/Root/ViewerRootView.swift:90-111 (task), Modules/PdfRPG/Pdf/PdfSearchModel.swift:30-36, Modules/CoreRPG/Controllable/ItemControllable.swift:243-250
- **What:** The load runs in `.task(id: model)` where `model` is a class instance that `ItemControllable.replace` mutates in place (`original.replace(with:)`), so the id never compares unequal; and even when it reloads, `pdfDoc` is `@ObservationIgnored` and `pdfId` (the only observed trigger for a new `PDFView`) is unchanged, so the displayed `PDFView` keeps the old document.
- **Why:** Replacing the file of a PDF that is open (second window on macOS/visionOS, shared game PDF updated by the GM, sync from another device) leaves the old pages on screen until the viewer is reopened. Unverified at runtime.
- **Action:** Key the task and the `.id` on `model.version` / `fileUrl_.update` instead of the reference, and make the document change an observed state change.
- **Severity:** Medium   **Area:** PdfRPG + PhotoRPG

### 5.39 ImagePresentationView tears down its per-frame sync on onDisappear but only sets it up in make
- **Location:** Modules/PhotoRPG/Space/ImagePresentationView.swift:73-96 (setup in `make`), 112-120 (teardown in `.onDisappear`)
- **What:** The `SceneEvents.Update` subscription, coalescing stream, sync task and `model.foregroundEntity` are created once in `RealityView.make`, but `.onDisappear` cancels them; nothing recreates them when the view appears again without a new `make`.
- **Why:** If the view disappears and reappears without being rebuilt (a tab/ornament/scene change inside the window), the window stops being re-fitted every frame and the weather/foreground attachment is never placed again (`placeForeground` returns early with `foregroundEntity == nil`). visionOS only, unverified on device. Also `frameSyncContinuation` / `sceneUpdateSubscription` are written to `@State` directly in `make`, while `cacheAvailableBounds` documents that this pattern warns, and a second `make` overwrites the old task without cancelling it.
- **Action:** Move set-up into `.onAppear`/a `.task` paired with the teardown, or tie teardown to the RealityView's own lifetime; cancel the previous task before replacing it.
- **Severity:** Medium   **Area:** PdfRPG + PhotoRPG

### 5.40 Foundry mapper truncates resource paths at `#` and `?` and silently drops colliding assets
- **Location:** Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+SharedHelpers.swift:212-220 (`canonicalResourcePath`); used by +Indexes.swift:27, +Assets.swift:32-34 (`createAsset` key and `stableID("asset#...")`), +Assets.swift:147
- **What:** `canonicalResourcePath` percent-decodes first and then cuts at `?` and `#`, and it is also applied to the package's own `logicalPath` (a zip entry path, not a URL). `FoundryMediaNormalizer.canonicalPath` was fixed for exactly this in CODE_AUDIT_21 §5.28 (cut first, decode second), but this sibling function was not, and the fix has a test only for the normalizer (`FoundryMediaNormalizerTests.swift:17`).
- **Why:** packaged files `tokens/Token #1.webp` and `tokens/Token #2.webp` both canonicalise to `tokens/Token`. `createAsset` keys `resourceIDs` and the stable asset id on that string, so the second file returns the first file's id and is never imported (`if let existing = resourceIDs[key] { return existing }`), with no warning; the index step reports them only as an "ambiguous path" for lookups. Every reference to the second token then points at the first image. Names with `#` or `?` are common in VTT token packs.
- **Action:** stop stripping query/fragment from `logicalPath` (strip only from references found inside documents, and cut before decoding as the normalizer does); make `createAsset` warn when two distinct resources collide; add a mapper-level test with `#` and `?` file names.
- **Severity:** Medium   **Area:** RolePlayGameKit

### 5.41 Reset Data takes no data-mutation lock and its alert overstates what is deleted
- **Location:** Modules/RolePlayGameKit/View/SettingsView.swift:196-211; Modules/RolePlayGameKit/Model/AppModel.swift:318-320; Modules/AdventureRPG/Root/AdventureRootModel.swift:277-284; Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:44-80
- **What:** `AppModel.resetData()` runs `adventureRoot.resetData()` without `beginExclusiveDataMutation()` / `beginSaveDeferral()` (import, Validate/Repair and the example-data install all take both, see `DataMutationCoordinator` doc), and the alert says "all files in local and appCloud storage ... are removed" while `ItemControllable.resetData` only clears caches and bookmarks and batch-deletes rows (its own comment: "Will not remove files on reset Database").
- **Why:** Reset can be tapped while an import or Validate sheet is mid-run and interleaves a batch delete with that bulk writer's in-memory graph and its final save; the confirmation text promises a file deletion that does not happen (or the comment is stale). It is the app's most destructive action and gives no completion feedback.
- **Action:** take the exclusive-mutation token (show the busy message if refused) and defer saves around the reset; make alert text and behaviour agree; show a completion state.
- **Severity:** Medium   **Area:** RolePlayGameKit

### 5.42 `replace(with:)` bumps `weatherUpdate` on every change, even when no weather value changed
- **Location:** Modules/WeatherRPG/Model/WeatherModel.swift:332 (`weatherUpdate_.wrappedValue = UUID()`), Modules/WeatherRPG/Model/WeatherModel+Sync.swift:8-30 (`merge` takes all weather fields from whichever side has the newer stamp), applied by Modules/CoreRPG/Controllable/ItemControllable.swift:250 and :745
- **What:** Every other field uses `<=>`, but the stamp is reassigned unconditionally in `replace`, so renaming, tagging, moving into a folder or applying a synced merge stamps "weather settings changed now".
- **Why:** The weather values (time, clouds, storm, lightning, photo) merge as one block by this stamp. A device that only renames an item from an older weather snapshot gets a newer stamp than another device's later weather edit, and on the next CloudKit merge its stale values win (lost update). Applying a synced model also re-stamps the in-memory copy, which is persisted with the next unrelated save.
- **Action:** Only bump the stamp when one of the weather fields actually differs from `model` (or adopt `model.weatherUpdate_` with `<=>` and let `EditController` stamp on weather edits).
- **Severity:** Medium   **Area:** RuleRPG + WeatherRPG

### 5.43 Quick editor: a new section moved above a same-named one produces two entries with the same id
- **Location:** Modules/RuleRPG/Controller/EditController.swift:97-140 (`mergeEntries`), called from :84-88 and :146-170; reorder at Modules/RuleRPG/View/RuleQuickEntryEditor.swift:27
- **What:** `mergeEntries` resolves each imported entry in one pass: id match first, then a name+kind+parent fallback against still-unmatched existing entries. A new entry processed before the existing entry it resembles takes that entry's identity through the fallback; the existing entry (same id) then finds no unmatched partner and is returned as is.
- **Why:** Add a section named "Notes" while a "Notes" section exists, drag the new one above the old one, Save: the result holds two entries with the existing id (new content under the old id, plus the old entry). Duplicate ids break `ForEach` identity, `item[entryId]`, link targets and `changedLinkRegisterModels` (the dictionaries keep the first). Any importer that hands entries in a different order than `existing` can hit it too.
- **Action:** Match by id for all imported entries first, then run the name fallback only for the leftovers against existing entries that no id match claimed; add a regression test for the reordered case.
- **Severity:** Medium   **Area:** RuleRPG + WeatherRPG

### 5.44 Player dice result is applied to the generation tree without checking the pending-roll state
- **Location:** Modules/TableRPG/Model/TableGenerationSessionStore.swift:23-49; caller Modules/GameRPG/Controller/MasterController+DiceMessages.swift:58-66; pending state set at Modules/TableRPG/View/TableGenerationOccurrenceHeaderView.swift:172-176
- **What:** `consume(category:diceResult:)` applies any incoming result for a registered session/occurrence via `controller.apply`, never checking `occurrence.isAwaitingPlayerRoll` or `awaitingPlayerId` (which the header sets exactly for this purpose).
- **Why:** With "Share to all", every player's roll re-applies and re-selects the entry (last roll wins); a player who re-rolls, or whose roll arrives after the GM rolled locally/reset/cancelled, silently changes the GM's already decided table result and rebuilds the child tree (discarding nested choices).
- **Action:** Accept a result only while the occurrence is awaiting a roll and (if `awaitingPlayerId != nil`) the sender matches; otherwise treat it as a plain dice-log entry (return false). This needs the sender id passed through `addResult`.
- **Severity:** Medium   **Area:** SpaceRPG + TableRPG

### 5.45 3D objects are still not shown on tvOS and the game-mode affordance is an invisible no-op
- **Location:** Modules/SpaceRPG/Controller/ViewController.swift:42-50 (tvOS `gameViewer`), Modules/SpaceRPG/View/SpaceQuickLook.swift:21-57 (`loader()` empty outside visionOS; `selected` never assigned, so `.quickLookPreview($selected)` can never present), Modules/SpaceRPG/Root/ViewerRootView.swift:14-18 (empty `VStack` on tvOS), Modules/SpaceRPG/Space/SpaceViewer.swift:7 (whole type `#if !os(tvOS)`)
- **What:** On Apple TV a revealed Space renders a 0.01-opacity, non-hit-testable button and nothing else; `SpaceQuickLook.selected`/`quickLookPreview` is dead state on every platform (the view is only instantiated for tvOS/visionOS).
- **Why:** A GM revealing a 3D object to a tvOS player shows a blank game screen with no explanation.
- **Action:** Decide the tvOS behaviour: either show an explicit "3D objects are not shown on Apple TV" state (and hide the affordance in `ViewerRootView`), or render the model preview via QuickLook/thumbnail. Remove the dead `selected` state.
- **Severity:** Medium   **Area:** SpaceRPG + TableRPG   **Status:** [OPEN since CODE_AUDIT_Space §8.2]

### 5.46 Share extension accepts files it cannot read and drops failures silently
- **Location:** Sources/RPGShare/Info.plist:9-16 (`NSExtensionActivationSupportsFileWithMaxCount` = 1); Sources/RPGShare/SharingView.swift:181-196 (`try?` on both loads); Sources/RPGShare/ItemProviderImporter.swift:24-31 (per-item failures only logged, remaining photos silently dropped when the 60 MiB budget is hit)
- **What:** Any single file (PDF, zip, audio, video) activates the extension, but only images and text are loaded; both `loadImages` and `loadTexts` errors are swallowed with `try?`, and per-image failures or the payload-budget `break` are only logged.
- **Why:** Sharing a PDF opens a normal-looking form with no preview and empty fields; the user can type a name and "Save" an Adventure/Character that contains none of what they shared. Sharing 8 photos where 3 fail or exceed the budget saves 5 without any notice.
- **Action:** Restrict the activation rule to what is handled (image/text predicate form), and when nothing could be loaded or some items were dropped, show a message ("N of M items could not be added") instead of an empty form.
- **Severity:** Medium   **Area:** Sources + Resources

### 5.47 Save to the Photo module with no images reports success and saves nothing
- **Location:** Sources/RPGShare/ShareExtensionSaveController.swift:86-87 (`case .photo: break`); Sources/RPGShare/SharingView.swift:259-268 (Save only requires a non-empty name); Sources/RPGShare/ModuleChooserView.swift:13 (`.photo` always selectable)
- **What:** With a text-only share (or after all image loads failed) and "Photo" selected, `saveContent` loops over zero images, hits `break`, saves an unchanged context and the extension closes as if it worked.
- **Why:** The shared text is silently lost; the user believes a photo item exists.
- **Action:** Disable Save (or hide `.photo`) while `images` is empty, or throw a "no photo to save" error.
- **Severity:** Medium   **Area:** Sources + Resources

### 5.48 Dice widget shows only the first die of a multi-dice roll
- **Location:** Sources/DiceRollerWidget/DiceRollerWidgetView.swift:153-195; Modules/DiceRPG/Widget/DiceConfiguration.swift:53-62 (`DiceWidgetDice.init(_ diceSnapshot:)` keeps `dice.first`'s sides and last face)
- **What:** A roll recorded from the app/Siri ("3d6+2") is reduced to one die image with the first die's face, while the accessibility value reads the sum.
- **Why:** The widget picture contradicts the roll (face 4 shown, total 14); the total is never shown visually in the small/medium layouts.
- **Action:** Show `lastRoll.sum` as text next to the die (and the notation as the name); keep the die image only for single-die rolls.
- **Severity:** Medium   **Area:** Sources + Resources

### 5.L Low-severity items (94)

- **5.49 Full reconciliation can drop an item added while it awaits** — Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:114-157 — _CoreRPG Controllable/Import/Links_. Re-read `dataControllable.unsavedInsertIds()` and the current `items` after the last suspension and union them into `updatedItems`.
- **5.50 `ItemGameModel.append/insert` are not idempotent** — Modules/CoreRPG/Controllable/GameControllable.swift:82-90, callers 214-219 — _CoreRPG Controllable/Import/Links_. Make `append`/`insert` skip an id that is already in `items` (and move to front for insert).
- **5.51 Imported file name derived with `replacing(ext, with: "")` removes every occurrence** — Modules/CoreRPG/Controllable/EditControllable+File.swift:162-164 — _CoreRPG Controllable/Import/Links_. Use `deletingPathExtension` (or `URL.deletingPathExtension().lastPathComponent`).
- **5.52 Import progress never reaches the total when items fail or are rejected** — Modules/CoreRPG/Controllable/ImportControllable.swift:280-289 — _CoreRPG Controllable/Import/Links_. Increment a processed counter (or `importedItems`) in the failure/rejection paths too.
- **5.53 Folder-entry merge order depends on the device locale** — Modules/CoreRPG/CRDT/FolderEntryMerge.swift:29-35 — _CoreRPG Controllable/Import/Links_. Sort by a locale-independent key (`name.compare(_, options: [.literal])` or the raw string, then `uuidString`).
- **5.54 `ImportItemRepair.normalizedTags` writes a localized title into persisted tags and can duplicate it** — Modules/CoreRPG/Controllable/ImportItemRepair.swift:20-23 — _CoreRPG Controllable/Import/Links_. Use a stable (non-localized) tag name or de-duplicate before sorting.
- **5.55 User text containing the expansion marker emoji is treated as markup** — Modules/CoreRPG/LinkRenderer/LinkHighLightLocations.swift:104-110 — _CoreRPG Controllable/Import/Links_. Use private-use or otherwise unlikely marker characters, or escape user occurrences on load.
- **5.56 Bookmark and store saves swallow write errors; a second process can overwrite the bookmark store** — Modules/CoreRPG/Persistence/FilePersistenceController.swift:82-92, Modules/CoreRPG/Files/FileDataController.swift:84-95, — _CoreRPG Files/Persistence/Model_. Return a result from `save` and keep `needsSave` set on failure with a `recordFileError`; re-read before write or give the extension a separate bookmark file.
- **5.57 Corrupt store backup overwrites the previous backup** — Modules/CoreRPG/Persistence/FilePersistenceController.swift:57-66 — _CoreRPG Files/Persistence/Model_. Use a timestamped suffix or keep the oldest.
- **5.58 KeepAwakeModel does nothing on native macOS** — Modules/CoreRPG/Model/KeepAwakeModel.swift:46-50 — _CoreRPG Files/Persistence/Model_. Decide; if wanted, hold a `ProcessInfo` `.idleDisplaySleepDisabled` activity while an owner is registered on macOS.
- **5.59 QuickDice slot defaults are never removed with their character** — Modules/CoreRPG/Model/QuickDiceSlotsModel.swift:46-80 — _CoreRPG Files/Persistence/Model_. Remove the key from the character purge path, or prune keys of unknown characters at launch.
- **5.60 Bridge size guard runs after the whole file was decoded and hashed** — Modules/CoreRPG/Foundry/FoundryVTTBridgeDecoding.swift:23 vs 57 — _CoreRPG Foundry/Sheet_. Move the guard before `decodeContents` and decide on one consistent limit for bridge files (document vs asset bytes budgeted separately).
- **5.61 One malformed bridge `assetReference` aborts the whole import** — Modules/CoreRPG/Foundry/FoundryVTTBridgeDecoding.swift:320-331, 437-447 — _CoreRPG Foundry/Sheet_. Downgrade to an `unresolved` resource plus a capped diagnostic instead of throwing.
- **5.62 Rows created while a search is active lose their expanded state (`lastIsShown` defaults to false)** — Modules/CoreRPG/Sheet/SheetModel.swift:~105-130 — _CoreRPG Foundry/Sheet_. Initialise `lastIsShown = isShown` when a row is appended (toggle/reconcile) or in `filter` when the row was not part of the saved snapshot.
- **5.63 Reorder/move index math counts non-entry rows that share `entries`** — Modules/CoreRPG/Sheet/SheetRootModel+ContextMenu.swift:12-30 — _CoreRPG Foundry/Sheet_. Compute positions only among rows that have an `entryId` (filter first, translate index back) or keep linked sheets in a separate array.
- **5.64 `removeEntry` updates the UI even if the edit controller could not remove the entry** — Modules/CoreRPG/Sheet/SheetRootModel+Editor.swift:6-24 — _CoreRPG Foundry/Sheet_. Only mutate the view model after the controller reports success; keep the AI draft on failure.
- **5.65 `EntryTextParser.removeLineBreaks` leaves a trailing space and drops real hyphens** — Modules/CoreRPG/Text/EntryTextParser.swift:78-110 — _CoreRPG Foundry/Sheet_. Join with single spaces and trim once at paragraph end; only drop the hyphen when the next line starts with a lowercase letter.
- **5.66 Export panel: unowned start task and file-mover cancel reported as failure** — Modules/CoreRPG/FileViews/ExportProgressPanelView.swift:36-62, 125-141, 181-184 — _CoreRPG UI 1_. Store the option-start task in `@State` and cancel it on disappear/cancel; map `CocoaError.userCancelled` from the mover to `.cancelled` and delete the temp file on cancel.
- **5.67 NavigationAction equality is the function name of its creator** — Modules/CoreRPG/Navigator/Core/NavigationAction.swift — _CoreRPG UI 1_. Include the sent value (or an explicit identity) in `name`/hash, or drop `Hashable` from the type and compare via a descriptor in tests.
- **5.68 Silent failures on share and file replacement** — Modules/CoreRPG/LGViews/GameShareView.swift:150-160 — _CoreRPG UI 1_. Return a result with an error from `resetFile`, show it through the existing `pickerError`/`importFailureAlert`; surface the share failure (row status or log).
- **5.69 Item generation does nothing on tvOS** — Modules/CoreRPG/LGViews/ItemGenerationPresentationModifier.swift:45-59 — _CoreRPG UI 1_. Return `isEnabled: false` on tvOS (or add the branch).
- **5.70 Add Item and Add Collection menu buttons lack the in-flight guard Add Folder got** — Modules/CoreRPG/Menu/AddItemButton.swift:11-19 — _CoreRPG UI 2_. Share one guarded helper for the three buttons (the donation and tip-refresh tail is also copied three times, so extract it together).
- **5.71 Default group helpers return a random UUID as if they had worked** — Modules/CoreRPG/ItemList/EntryDataEditable.swift:122-130 — _CoreRPG UI 2_. Return `UUID?` (nil on failure) and let callers skip.
- **5.72 `updateDefault` duplicate-link repair applies ranges of the original string to the edited string** — Modules/CoreRPG/ItemList/EntryDataEditable.swift:337-353 — _CoreRPG UI 2_. Resolve the n-th occurrence per link (iterate occurrences in order, build the result in one pass like `replacing(ranges:)`), and add a test with three duplicates.
- **5.73 `convertToGroup(existingItemId:)` does not take the item out of its folder** — Modules/CoreRPG/ItemList/GroupableEntryEditing.swift:36-43 — _CoreRPG UI 2_. Apply the same parent removal, or document why a hidden item may stay in its folder.
- **5.74 CloudKit "Synced" badge never expires** — Modules/CoreRPG/Views/CloudKitSyncStatusView.swift:37-48 — _CoreRPG UI 2_. Expire it from the model (reset state after a delay) or use `TimelineView`/`.task(id: lastSync)` with `Task.sleep(for:)`.
- **5.75 `removeWhiteBackground` reads the bitmap channels in the wrong order** — Modules/CoreRPG/Extensions/UIImage+clear.swift:15,33-36 — _CoreRPG UI 2_. Read B,G,R,A, move the loop to a `@concurrent` function.
- **5.76 Inspector row opens details through `showDetails.toggle()`** — Modules/CoreRPG/Inspector/InspectorRowView.swift:145 — _CoreRPG UI 2_. Use an optional destination binding (`navigationDestination(item:)` or a counter) instead of a toggled Bool.
- **5.77 Tag editor accepts blank and whitespace-padded tags** — Modules/CoreRPG/Editors/AddTagsEditor.swift:63-75,81-91 — _CoreRPG UI 2_. Trim whitespace and newlines before the empty and duplicate checks, disable the button on a trimmed-empty string, drop the content type.
- **5.78 `numericInput` filter edge cases** — Modules/CoreRPG/ViewModifiers/NumericViewModifier.swift:17-32 — _CoreRPG UI 2_. Validate with the same `FormatStyle` the submit handler uses and keep the previous text on a failed parse; allow "-" only as the first character.
- **5.79 GM "player" display mode still shows hidden pins and fogged monsters** — Modules/GameRPG/Table3D/GameTableProjection.swift:21-50 — _GameRPG Table3D_. Pass `renderIsGameMaster` to the pin filter (keep `hiddenForMaster` dimming off in that mode) and keep permission checks on the real role; add a test for the pin filter.
- **5.80 Same-named guests: group order tie-break is not stable** — Modules/GameRPG/Table3D/TableGuestDice.swift:44-48 — _GameRPG Table3D_. Carry the sender id in `TableGuestRoll` and use it as the final sort key.
- **5.81 Pin base colour in the photo plane is only applied at creation** — Modules/GameRPG/Table3D/GameTableEntities.swift:97-99 — _GameRPG Table3D_. Add `color` to `AppliedVisual` and re-tint the face when no photo is loaded.
- **5.82 Asset request for an arbitrary map id is answered and marks that map as unshared** — Modules/GameRPG/Controller/MasterController+MapMessages.swift:44-65, 162-166 — _GameRPG Controllers_. Compare the requested id with `mapRoot.gameControllable.gameModel.currentItemId` before calling `mayShareMapState` and `sendMapFollowUps`.
- **5.83 Informational notes are wiped by the first message the master sends** — Modules/GameRPG/Controller/LogGameController.swift:98-102, 143-164, 257-265 — _GameRPG Controllers_. Let `beginDeliverySession` keep rows whose session is the legacy one (or store the master's session id for notes), and add a test.
- **5.84 Late-join audio bookkeeping not cleared when a player disconnects** — Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:135-149 — _GameRPG Controllers_. Remove the id from `lateAudioPlayers` in both paths.
- **5.85 `process(_:)` checks the sender's route once, then awaits** — Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:189-257 — _GameRPG Controllers_. Re-check the route before the pin/binding side effects in `handleValue`, or run `lostPlayer`'s cleanup through the same pipeline.
- **5.86 Persisted dashboard configuration is not forward compatible** — Modules/GameRPG/Statistics/Model/GameStatisticsTypes.swift:228-244, Modules/GameRPG/Statistics/Model/GameStatisticsModel — _GameRPG Views/Battle/Statistics_. Add a custom `init(from:)` with `decodeIfPresent` defaults, drop unknown cases, and append sections missing from the saved order.
- **5.87 Config rows commit on every focus loss, even when nothing changed** — Modules/GameRPG/BattleRound/BattleAttackerConfigRows.swift:114-117, 163-179 — _GameRPG Views/Battle/Statistics_. Compare the parsed value with `currentValue` and return early when equal.
- **5.88 Dice and achievement statistics count every roll the device sees, not only the user's own** — Modules/GameRPG/Statistics/Controller/GameStatisticsController.swift:100-112, 20-22 — _GameRPG Views/Battle/Statistics_. Decide the meaning
- **5.89 Activity chart tooltip only appears on the first day of a week or month bucket** — Modules/GameRPG/Statistics/View/GameStatisticsActivityChart.swift:36-41, 61 — _GameRPG Views/Battle/Statistics_. Resolve the selection to the bucket with `calendar.dateInterval(of: granularity.calendarComponent, for: selectedDate)` (pass the granularity into the chart) or pick the nearest point.
- **5.90 Global search can show the results of an older search term and flicker its progress state** — Modules/GameRPG/Search/SearchGlobalController.swift:34-47 — _GameRPG Views/Battle/Statistics_. Check `Task.isCancelled` (or compare the searched text with `model.searchText`) before assigning results, and only clear `isSearching` if `model.currentTask` is still this task; wrap the inner task wi
- **5.91 Needle insert after the last point lands next to the first point** — Modules/MapRPG/Map/MapEntryViewer.swift:150-175 — _MapRPG Map_. For the wrap case use the midpoint of last and first and append at the end (index `count`), keeping the other indices unchanged; add a test.
- **5.92 Pencil stroke samples with the committed transform while the display uses the live gesture transform** — Modules/MapRPG/Map/MapEditorSession+Pencil.swift:34-47 — _MapRPG Map_. Convert with the live displayed transform (pass it into the gesture handler, or publish it on the session), or ignore finger viewport gestures while a pencil stroke is active.
- **5.93 Cancelled pencil or pin drags leave state behind** — Modules/MapRPG/Map/MapEditorCanvasGestures.swift:211-234 — _MapRPG Map_. Reset via `@GestureState`/`.updating` reset callback (`state` resets automatically) or observe `scenePhase`/gesture-cancel; derive "is moving" from a `@GestureState` Bool instead of `@State`.
- **5.94 `MapModel.version` is a sum of two scalars** — Modules/MapRPG/Model/MapModel+Sync.swift:185-191 — _MapRPG rest_. Document the weakness at the property (the comment only explains why `hashValue` was dropped) or fold `contentVersion` into it once the digest is cheap (see the performance finding).
- **5.95 Redaction stamps blanked room text as the newest CRDT write** — Modules/MapRPG/Model/MapSnapshot.swift:158-165 — _MapRPG rest_. Note the invariant at `redactedForNonMaster()` and test that a reveal after a blank package restores the text on the receive paths; or build the redacted entries without touching the CRDT stamp.
- **5.96 Global search treats entry-only matches as item matches** — Modules/AdventureRPG/Model/AdventureModel.swift:281-288 — _AdventureRPG_. Add `includeEntries` to the guard (`guard includeEntries, !specialCategory`), and fix Table the same way (outside this area).
- **5.97 `collectLinks` ignores item-level dice/characters and group children** — Modules/AdventureRPG/Controller/LinkController.swift:150-196 — _AdventureRPG_. Follow `adventureId` children under the existing visited set and add the item-level ids when `module` matches.
- **5.98 `validateLinks` does not check group entries** — Modules/AdventureRPG/Controller/LinkController.swift:106-148 — _AdventureRPG_. Remove or clear entries whose `adventureId` does not resolve, and report it in the validation model.
- **5.99 Failed or discarded playlist load leaves a stale `currentItem` pointing at a deleted track** — Modules/AudioRPG/Controller/AudioController.swift:147-199 — _AudioRPG_. Clear `currentItem` (and `isPlaying`-dependent UI state) inside `add(replace: true)` together with the playlist, as `removeAudio` already does for the current track.
- **5.100 Play failures are silent and the playback intents always answer "Playing"** — Modules/AudioRPG/Controller/GameController+Playback.swift:19-65, 72-99 — _AudioRPG_. Return a result (or throw `AudioEntityAssetUnavailableError`-style) from `loadPlaylist`/`play` when nothing could be loaded, and have the intents answer accordingly; optionally surface a banner in the
- **5.101 `isActive` stays true after the system deactivated the session on an interruption** — Modules/AudioRPG/Controller/AudioPlayerSession.swift:222-238, 78-84 — _AudioRPG_. Reset `isActive = false` on `.began` (the resume path already calls `setActive`).
- **5.102 Lock screen, Now Playing and player bar show the item's raw description as album/artist** — Modules/AudioRPG/Controller/AudioController.swift:171-179 — _AudioRPG_. Use the first line of `description.withoutLink()` (or plain text) with a length cap for the subtitle, keep the full text out of system Now Playing.
- **5.103 Play link label ignores which item is playing in a game** — Modules/AudioRPG/Controller/LinkController.swift:26-31 versus 38-40 — _AudioRPG_. Use `gameController.isPlayingPlaylist(id: itemId)` for `isPlaying` in the game branch.
- **5.104 Row play button never shows "playing" for a playlist item** — Modules/AudioRPG/Audio/AudioPlayPauseButton.swift:48-50, 41-44 — _AudioRPG_. Use `root.gameController.isPlayingPlaylist(id:)` for the icon and accessibility label.
- **5.105 `waitForSharing` can fire a play long after the tap** — Modules/AudioRPG/Audio/SharingActionView.swift:51, 60-67, 72-77 — _AudioRPG_. Clear the flag after a deadline, on disappear, and when another play/pause command is issued; or keep the pending play in the controller with an expiry.
- **5.106 Transferable file export labels every audio file as MPEG-4 audio** — Modules/AudioRPG/Intent/AudioEntity.swift:101-106 — _AudioRPG_. Derive the content type from the file's extension (`UTType(filenameExtension:)`) or export with `.audio`.
- **5.107 Validate Folders re-adds an item-level dice the user removed** — Modules/CharacterRPG/Root/CharacterRootModel.swift:296-301 — _CharacterRPG_. Drop the auto-assignment, or only do it for items that never had an item dice (needs a marker); at minimum document it as intended.
- **5.108 gameEntryDisplayValue formats non-integers with string interpolation** — Modules/CharacterRPG/Controller/GameController+EntryResolution.swift:172 — _CharacterRPG_. Use `Calculator.formatNumber(number)`.
- **5.109 `resetPlayerDice(to:)` maps by display name and can duplicate a player's dice** — Modules/DiceRPG/Controller/GameController.swift:289-301 — _DiceRPG_. Reset by sender id or de-duplicate by dice id; key `hiddenPlayers` by sender id.
- **5.110 A die keeps only its first 100 results, so the 101st tap silently does nothing** — Modules/DiceRPG/Model/DieModel.swift:54-65 — _DiceRPG_. Keep the suffix (`suffix(maximumResultCount)`) when bounding rolled results.
- **5.111 Typed values in the number editors bypass the slider ranges and `Int(Double)` can trap** — Modules/CoreRPG/Editors/TextIntEditor.swift:82-87 and Modules/CoreRPG/Editors/TextDoubleEditor.swift:~123-130 — _DiceRPG_. Clamp to the editor's `range` on submit; convert with `Int(exactly:)`/the existing `saturatingInt`; round the modifier to an integer in `reset(modifier:)`.
- **5.112 No upper bound on dice added through the editor or intents, but decoding keeps only 1,000** — Modules/DiceRPG/Controller/EditController.swift:14-19 — _DiceRPG_. Refuse `add(die:)` at the limit (UI disables the bag, intent returns a dialog).
- **5.113 Share menu in `DiceInline` swallows errors with `try?`** — Modules/DiceRPG/View/DiceInline.swift:46-47 and :56-58 — _DiceRPG_. Log the error (`Logger.linkController.error`) as the link path does.
- **5.114 CancellationError and already-wrapped errors are re-wrapped as generationFailed in the PDF and table analyzers** — Modules/GeneratorRPG/BasicAI/Providers/PdfSummaryAnalyzer.swift:76-87, 107-111 — _GeneratorRPG_. add `catch is CancellationError { throw }` first and `catch let error as PdfSummaryAnalysisError { throw error }`, as the photo analyzer does.
- **5.115 Sliding window can start the kept transcript with an orphan response** — Modules/GeneratorRPG/BasicAI/Engine/TranscriptTokenCounting.swift:155-181, 194-207 — _GeneratorRPG_. after choosing the suffix, drop leading non-prompt entries; add a unit test on a synthetic transcript.
- **5.116 Analyze buttons guard on a flag that is set inside the task they start** — Modules/GeneratorRPG/View/PhotoSummaryAnalysisView.swift:129-139 — _GeneratorRPG_. set `isAnalyzing` synchronously in the button action, or cancel the previous `analysisTask` before starting a new one.
- **5.117 Language instructions contradict the language override** — Modules/GeneratorRPG/BasicAI/Providers/PdfSummaryAnalyzer.swift:201 vs 58 — _GeneratorRPG_. drop the language sentence from the default instructions of the two analyzers that take an output language.
- **5.118 BlockEntryGenModel equality includes a random id** — Modules/GeneratorRPG/BasicAI/Model/BlockGenModel.swift:9-16 — _GeneratorRPG_. exclude id from `==` or derive id from content plus occurrence index.
- **5.119 Search highlights stay on the page after a search is dismissed** — Modules/PdfRPG/Pdf/SearchBar.swift:20-26, Modules/PdfRPG/Pdf/PdfWrapperView.swift:152-155 — _PdfRPG + PhotoRPG_. Clear the highlights (via a `clearSearch` closure/the stored `pdfView`) when `isSearching` ends and reset `currentIndex`.
- **5.120 isNotJpegPhoto is case-sensitive, so ordinary .JPG/.JPEG photos are offered "Convert to JPEG"** — Modules/PhotoRPG/Controller/EditController.swift:33-37, Modules/CoreRPG/Files/FileUrl.swift:177-179 — _PdfRPG + PhotoRPG_. Compare lowercased, and also accept `jpe`; better, decide from the content type of the stored file.
- **5.121 Database error state is never cleared and `canRecover` is dead** — Modules/RolePlayGameKit/Model/DataBaseModel.swift:62-64,117-160 — _RolePlayGameKit_. reset the three fields at the top of `finishSetup()`; delete `canRecover` or use it to hide the Delete button for unrecoverable errors.
- **5.122 First-launch example-data install failure has no retry** — Modules/RolePlayGameKit/View/DestinationReadyView.swift:72-86 — _RolePlayGameKit_. set `firstLaunch = false` only after success (or expose "Install example data" in Settings).
- **5.123 Launch cleanup deletes hidden items without the data-mutation lock** — Modules/RolePlayGameKit/View/DestinationReadyView.swift:39-52 — _RolePlayGameKit_. take the coordinator token (skip the pass when busy or when a game is running) and run it once per launch, not per view appearance.
- **5.124 Editor window tab selection is not restored** — Modules/RolePlayGameKit/View/SplitEditorNavigation.swift:8,28-35 — _RolePlayGameKit_. use a `@SceneStorage` with an editor-specific key, or drop the sync if restoration is intentionally off.
- **5.125 Persisted sidebar customization ID has a typo** — Modules/RolePlayGameKit/View/SplitNavigation.swift:125 — _RolePlayGameKit_. fix once and accept the one-time reset, or document it as frozen.
- **5.126 `inertCodeBlock` computes a meaningless fence length; dice formulas have no total cap** — Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+SharedHelpers.swift:349-361 — _RolePlayGameKit_. delete the reduce and start from 4; cap the total dice count per formula (for example 100) and keep the formula as text beyond it.
- **5.127 License-document detection matches the substring "ogl"** — Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:448-454 — _RolePlayGameKit_. match file stems (`license`, `licence`, `copying`, `ogl`, `notice`) as whole words on the last path component.
- **5.128 Unverified purchase result is not finished** — Modules/RolePlayGameKit/InApp/InAppModel.swift:157-158 — _RolePlayGameKit_. finish the unverified transaction in this branch too.
- **5.129 Navigate/Search intents route immediately instead of when ready** — Modules/RolePlayGameKit/Intent/NavigateIntent.swift:31-33 — _RolePlayGameKit_. use `routeToModuleWhenReady` in both intents.
- **5.130 Imported numbers are formatted with the device locale and rounded to 3 decimals** — Modules/RuleRPG/Model/RuleModel+FoundryFactory.swift:344-349 — _RuleRPG + WeatherRPG_. Format stored content with a fixed locale and full precision.
- **5.131 Cloud and star elements pile up at one edge after a long pause; Storm divides by the canvas width** — Modules/WeatherRPG/Weather/CloudGroup.swift:55-66 and Modules/WeatherRPG/Weather/StarField.swift:49-56 — _RuleRPG + WeatherRPG_. Clamp `delta` as Storm does, use `truncatingRemainder` for the wrap, and `guard size.width > 0` in `Storm.update`.
- **5.132 `ViewController.viewer` ignores its `configuration` argument** — Modules/WeatherRPG/Controller/ViewController.swift:73-75 — _RuleRPG + WeatherRPG_. Pass `configuration` through (and adjust `closeButton` only if intended).
- **5.133 `WeatherRootModel.setUp` keeps the old sync controller when called without a context** — Modules/WeatherRPG/Root/WeatherRootModel.swift:101-105 — _RuleRPG + WeatherRPG_. Set both to nil before the `if let` as Rule does.
- **5.134 "Edit as Sheet" transition beat can leave the panel in an inconsistent state** — Modules/TableRPG/View/TableGenerationEditAsSheetButton.swift:55-62 — _SpaceRPG + TableRPG_. In the Task re-check `model.outcomeEditingSession != nil` (and cancellation) before setting the flag, or disable the list during the beat; derive the footer's visibility from "flag and session" togeth
- **5.135 Save/Send of the outcome fail silently and Save can discard the outcome** — Modules/TableRPG/View/TableGenerationRootView.swift:112-128 — _SpaceRPG + TableRPG_. Keep the panel open and set `model.errorMessage` on both failures (the error label already exists in the occurrence list).
- **5.136 Window instance stays on "Moved to Immersive Space" after the handoff fails or the space closes** — Modules/SpaceRPG/Space/SpaceViewer.swift:465-485 — _SpaceRPG + TableRPG_. Reset `handedOffToImmersive` (and reload) when the immersive space closes or `openSpaceViewer` reports failure; the handoff model could publish the expiry.
- **5.137 Scan folders are named by the current second** — Modules/SpaceRPG/Record/CaptureFolderManager.swift:119 — _SpaceRPG + TableRPG_. Append a UUID (or a counter) to the folder name.
- **5.138 Initial name from shared text is empty when the text starts with whitespace and splits the whole text** — Sources/RPGShare/SharingView.swift:191-194 — _Sources + Resources_. Trim first and use `split(maxSplits: 1, whereSeparator:)`/`prefix(while:)` on the trimmed string; cap the name length.
- **5.139 Loading state has no Cancel while the sheet is non-dismissable, and the database is opened on the main actor** — Sources/RPGShare/ShareViewController.swift:27 — _Sources + Resources_. Show Cancel in the loading view; open the store off the main actor or at least let the UI render the spinner before the synchronous call.
- **5.140 Error view discards the user's input and offers only Close** — Sources/RPGShare/SharingView.swift:97-122, :218-230 — _Sources + Resources_. Show the error as an alert/banner over the form and keep the form editable.
- **5.141 macOS share extension is sandboxed without the outgoing-network entitlement but downloads remote files** — MasterRPG.xcodeproj/project.xcproj:1681-1684 — _Sources + Resources_. Either add the outgoing-network setting for the extension or remove the remote branches on macOS; enable hardened runtime for consistency.
- **5.142 Viewer windows open a random item id when no selection is passed** — Sources/MasterRPG/Window/WindowViewerList.swift:80 — _Sources + Resources_. Show a `ContentUnavailableView` for nil, like `TableGeneratorWindowContent` already does.

## 6. Security

### 6.1 Template inheritance resolution is exponential and unboundedly recursive (crash/hang on hostile system.json package)
- **Location:** Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:456-476 (resolveTemplate), 418-453 (decode)
- **What:** `resolveTemplate` recurses once per entry of a template's `templates` list with no memoisation, no depth cap and no `Task.checkCancellation()`; cycle detection only catches true cycles.
- **Why:** A tiny `template.json` where template t_i lists `[t_{i+1}, t_{i+1}]` (diamond chain, duplicates allowed) costs 2^n resolutions, so n=40 hangs the import in an uncancellable CPU loop. A plain chain t_0 -> t_1 -> ... -> t_5000 (non-cyclic, a few hundred KB of JSON, well under every size cap and under the 128 JSON-depth guard because the structure is flat) recurses 5000 frames deep on a Swift concurrency worker thread (512 KB stack) and can overflow the stack, which is a process crash, not a catchable error. Subtype resolution repeats the same work for every declared subtype.
- **Action:** Resolve templates iteratively or with a memo table keyed by template name (each template resolved once), cap inheritance depth (e.g. 32) and total template count, dedupe the `templates` list, and check cancellation in the loop.
- **Severity:** High   **Area:** CoreRPG Foundry/Sheet

### 6.2 sanitizer does not scrub `_stats.lastModifiedBy` (user id leaks when "include users" is off)
- **Location:** Modules/CoreRPG/Foundry/FoundryVTTArchiveSanitizer.swift:138-141 (identityKeys), 204-208
- **What:** `identityKeys` contains `modifiedby` and `createdby` but not `lastmodifiedby`; Foundry v11/v12 documents carry `_stats.lastModifiedBy` (a User id). Verified: no occurrence of `lastModifiedBy` anywhere in Modules/CoreRPG or Tests.
- **Why:** With `includingUsers == false` the archive that is persisted (and iCloud-synced as the RuleRPG hand-off) still contains the id of the Foundry user who last edited every document, contradicting the type's documented privacy boundary ("private ... user identifiers").
- **Action:** Add `lastmodifiedby` (and review `lastmodifiedbyid`/`updatedby`) to `identityKeys`; add a sanitizer test with a realistic `_stats` block.
- **Severity:** Medium   **Area:** CoreRPG Foundry/Sheet

### 6.3 UniversalVTT reader parses a file of up to 1 GiB into a JSON tree
- **Location:** Modules/CoreRPG/Foundry/UniversalVTTReader.swift:268-279, 289-313; Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:191-194
- **What:** `boundedData` allows `maximumArchiveSize` (1 GiB) although the only large legitimate member is a base64 image capped at 64 MiB decoded (~86 MB encoded); the entire file is decoded into `FoundryJSONValue` (every unknown field retained), and `resourceData` re-parses the whole file again just to fetch the image.
- **Why:** A `.dd2vtt` padded with a huge unused field is accepted and consumes several GiB; on iOS this is a jetsam kill. Each image fetch repeats the full parse.
- **Action:** Limit UVTT file size to about `maximumEntrySize * 4/3 + 8 MiB`; cache the decoded image bytes or file offset from preflight.
- **Severity:** Medium   **Area:** CoreRPG Foundry/Sheet

### 6.4 Table dice ignore the "share master/player dice" options
- **Location:** Modules/GameRPG/Table3D/GameTableModel+Dice.swift:32-78 (`applyDiceRoll`), Modules/GameRPG/Table3D/GameTableView+VisionOS.swift:312-315, 465-476 (`applyFocusedDice`), Modules/GameRPG/Table3D/TableDiceResultRules.swift:80-90, Modules/GameRPG/Table3D/GameDiceResultPopover.swift:60-67
- **What:** Only the result popover consults `features.diceMaster`/`features.dicePlayers`; the dice themselves (value and orientation) are written to the TabletopKit state of the seat and synced to every participant without any feature check (`grep features Table3D` finds only the popover gate).
- **Why:** With "Share master dice with other players" off, a GM on Vision Pro who rolls a focused dice set still lands the dice face up on seat 0 of every player's table. The same holds for the "Share player dice" option between players at different seats. The 2D overlay, the network path (`PlayerController+Dice`) and the guest-seat path (`guestRolls`, already filtered at receive) honour the options, so this is an inconsistent leak of intentionally hidden GM rolls. (Severity lowered from High after review: the options gate only the result popover; whether the table faces must also be hidden is a design decision for the owner.)
- **Action:** Decide the intended semantics (ask the user). Either mirror the GM/player dice onto the table only when the matching option is on (and park/unrolled-mask them otherwise, e.g. publish `TableDieValue.unrolled` face-up 1 plus no popover), or document that table dice are always public and relabel the options. Add a test on the pure decision in `TableDiceResultRules`.
- **Severity:** Medium   **Area:** GameRPG Table3D

### 6.5 Per-player "show" toggle is enforced only on the receiving device
- **Location:** Modules/GameRPG/Controller/PlayerController+MessageProcessing.swift:142-183; Modules/GameRPG/Controller/MasterController+Show.swift:140-150; Modules/GameRPG/Network/GameNetworkController+Delivery.swift:38-72
- **What:** The game master's sharing control (`controls[].show == false`) is checked only in the player's `applyPlayerGates`. The master builds `playersMissing` from `gameRoster.players` (not `controls`), `sendPresentation` sends the package to every missing connection, and `sendPlayer(data:)` broadcasts references and map state to everyone.
- **Why:** A player the GM has hidden still receives the bytes of every photo, PDF, 3D object, audio track and map (over the LAN socket or the SharePlay Journal); only an unmodified client refuses to apply them. Under the "players are trusted" policy this is tolerable, but the UI promises that the player is not shown the item, the data is on the device and in the Journal, and nothing in CODE_AUDIT_*.md or GAME_CONNECTIONS.md records the toggle as a client-side display gate.
- **Action:** Either leave hidden players out of `playersMissing` and of targeted/Journal sends (and deliver the pending content when they are switched on), or state in GAME_CONNECTIONS.md that the toggle is a display gate only.
- **Severity:** Medium   **Area:** GameRPG Controllers

### 6.6 LAN frames are fully decoded before any per-peer rate or byte budget applies
- **Location:** Modules/GameRPG/Network/GameNetworkController+MasterDelegate.swift:28-39, Modules/GameRPG/Network/GameNetworkController+PlayerDelegate.swift:28-33, Modules/GameRPG/Model/GameMessagePipeline.swift:477-481, Modules/GameRPG/Network/GameProtocol.swift:41, Modules/GameRPG/Model/GameLimits.swift:14,45-47; contrast Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:530-536
- **What:** `masterReceived` decodes every LAN frame (up to 100 MB of base64 JSON) with `decodedOffMain` before `accepts` runs, and nothing limits how many bytes one connection may make the master decode per minute; SharePlay has exactly that guard (`SharePlayInboundByteBudget`, CODE_AUDIT_21 §6.5) but the LAN path never got the equivalent.
- **Why:** the framer buffers up to 100 MB per connection and `maximumConnections` is 32, and the `maximumQueuedBytes` (300 MB) limit only applies to the pipeline queue after decoding. An authenticated but misbehaving or buggy peer (or several at once) can send repeated 100 MB frames and make the GM allocate frame, decoded Data and model concurrently per connection (hundreds of MB each), a jetsam risk on iPad. Players are trusted by design, so the exploit needs a compromised or faulty client; the asymmetry with SharePlay is the point. Not verified at runtime.
- **Action:** Apply a per-connection inbound byte budget (reuse `SharePlayInboundByteBudget` keyed by connection id) in `ConnectionController.process` or `masterReceived` before decoding, and consider capping a player's frame at the size a player legitimately sends (player uploads are small; only the master sends large packages), e.g. a lower per-role frame limit on the master's listener side.
- **Severity:** Medium   **Area:** GameRPG SharePlay/Network

### 6.7 Map description and tags still ship to players unredacted
- **Location:** Modules/MapRPG/Model/MapSnapshot.swift:154-190 (`redactedForNonMaster()` copies `description:` and `tags:` through unchanged, lines 168-170); Modules/MapRPG/Controller/ExportController.swift:56-60 (`playerExportData` applies the same snapshot); Modules/MapRPG/Model/MapUpdatePayload.swift:34-44
- **What:** CODE_AUDIT_25 §6.1 was fixed for walls only. The map-level `description` (the item's notes field) and `tags` are copied into every live content update and into every player package.
- **Why:** A game master who keeps spoilers or hints about secret rooms in the map description sends them to every player device. Whether a player UI renders the description is unverified, but the text is on the device and in the payload. `MapSnapshot`'s own doc comment says the point of the function is that GM-only data must not be present on a recipient's device. No test pins this (`MapWallRedactionTests`, `MapPinVisibilityTests` cover walls, pins and rooms only).
- **Action:** Blank `description` (and decide for `tags`) in `redactedForNonMaster()`, keep `name`, add a test next to `MapWallRedactionTests`. Follow the "excluded until explicitly allowed" recommendation of CODE_AUDIT_25 §10.5 so new `MapSnapshot` fields default to redacted.
- **Severity:** Medium   **Area:** MapRPG rest

### 6.8 A roll shares the whole DiceSnapshot (description, tags, entries) with every player
- **Location:** Modules/DiceRPG/Controller/GameController.swift:172-182 (`createDiceResult` builds `DiceResultModel` from `DiceSnapshot(item)`); Modules/DiceRPG/Model/DiceSnapshot.swift:7-40; Modules/DiceRPG/Controller/GameController+DiceResult.swift:12-14
- **What:** `DiceResultModel` carries the full snapshot, including `description_`, `tags_`, `entries_` and `parentId` of the GM's dice, and `shareRoll` broadcasts it (`.generic`, no target).
- **Why:** A game master's dice description is free text and may hold notes ("boss phase 2 damage, only if ..."). Players do not see it in the overlay (`addGameDiceResult` replaces the name with the player's name), but the data is on their devices and in the master's relayed messages. Receivers only need the dice, options and results.
- **Action:** Send a reduced snapshot for rolls (dice, options, resultCategory; blank description, tags, entries, parentId), or strip those fields in `DiceResultModel.init`.
- **Severity:** Medium   **Area:** DiceRPG

### 6.9 Model output is applied to many items without review in the batch flow, from unfenced untrusted text
- **Location:** Modules/GeneratorRPG/View/BatchTextSummaryExtractionView.swift:232-251; BasicAI/Providers/TableSummaryAnalyzer.swift:60-72; View/TextSummaryExtractionFormatter.swift:14-28; BasicAI/Providers/PdfSummaryAnalyzer.swift:117-133; BasicAI/Engine/FoundationModelInputLimiter.swift:58
- **What:** entry names/contents (which can come from Foundry imports or shared campaigns), and PDF page text, are interpolated into the prompt with no fence and no marker stripping; the batch view then writes the model's title/description/tags straight into the items. The PDF page separator `--- Page N ---` is also forgeable by page text.
- **Why:** an imported entry saying "ignore the above, title this ...; tags: ..." can steer the title, description and tags of every selected item with no preview. The single-item views show a toggle form before applying, so only the batch path is unreviewed. `RunGeneratorIntent` already fences and strips markers (`GeneratorIntentPrompt`), so the module has two different standards.
- **Action:** move the untrusted text into a delimited block with marker stripping shared from `GeneratorIntentPrompt.withoutMarkers`, state in the instructions that it is material only, and either show a review step for the batch or limit the batch to name-if-empty plus tags with a count shown afterwards.
- **Severity:** Medium   **Area:** GeneratorRPG

### 6.L Low-severity items (8)

- **6.10 Create intents read the whole IntentFile with no size cap** — Modules/CoreRPG/Intent/IntentEntityHelpers.swift:217-224 — _CoreRPG Files/Persistence/Model_. Reject files above `ByteLimits.maximumSourceFileBytes` with `IntentFileStoreError` (or a new size error) before reading the data.
- **6.11 Navigator event log is public in release and ignores its verbosity** — Modules/CoreRPG/Navigator/Core/NavigationEventLogging.swift:11-28 — _CoreRPG UI 1_. Use `.private` (or log only the case name) and gate the logger on DEBUG; pass the computed verbosity.
- **6.12 Journal load budget is bypassed by a sender that claims to be the game master** — Modules/GameRPG/SharePlay/RPGSharePlayController+JournalAttachments.swift:198-209, Modules/GameRPG/Network/GameNetworkCo — _GameRPG SharePlay/Network_. Either accept and document it next to `journalLoadBudget`, or count every load against the budget keyed by the attachment's authenticated source when the API exposes one.
- **6.13 Per-message cap does not bound the master's cumulative `playerReports`** — Modules/AudioRPG/Controller/GameController+Playback.swift:287-302, 322 — _AudioRPG_. Drop keys whose player array becomes empty and that are not in `itemDataModel.items`. [[OPEN since CODE_AUDIT_Audio2 §6.3] (capped per message only)]
- **6.14 PCC entitlement gate is compile-time per module, not per host app** — Modules/GeneratorRPG/BasicAI/Providers/PhotoSummaryAnalyzer.swift:37-43, 117-124 — _GeneratorRPG_. when enabling, add a runtime check of the entitlement (SecTaskCopyValueForEntitlement on macOS, embedded-profile check elsewhere) or inject the flag from the host, and add a build-time check that ever
- **6.15 In-app generator prompt does not fence the sheet index the way the intent does** — Modules/GeneratorRPG/Controller/GeneratorController.swift:431-446, 393-414 — _GeneratorRPG_. reuse the fence and `withoutMarkers` from `GeneratorIntentPrompt`.
- **6.16 Foundry value contents, names and description are not passed through `inert`** — Modules/RuleRPG/Model/RuleModel+FoundryFactory.swift:34 — _RuleRPG + WeatherRPG_. Run values, node names and descriptions through the same neutralizer (keeping paragraph breaks in descriptions), or document that only the structured sections are neutralized.
- **6.17 Content widgets publish GM-side names to the Home Screen** — Modules/CoreRPG/Widget/ContentWidgetSnapshot.swift:56-70 — _Sources + Resources_. Decide and document; at minimum honour `widgetRenderingMode`/`redactionReasons` (`.privacy`) and `Text(...).privacySensitive()` for the names.

## 7. Performance

### 7.1 Existence checks coordinate as full reads and can download evicted iCloud files
- **Location:** Modules/CoreRPG/Files/FileManager+Coordination.swift:8-16 (`fileExists(coordinatingAccessAt:)`); callers Modules/CoreRPG/Files/CloudDocumentController.swift:249-257 (`suggestedFileName`), Modules/CoreRPG/Files/FileUrlDataController+Create.swift:40, :375
- **What:** `fileExists` takes `NSFileCoordinator.coordinate(readingItemAt:options: [])` and even classifies itself as a "may wait for download" access (`mayWaitForDownloadOf: fileURL`). A plain read coordination on a not-downloaded iCloud item asks iCloud to materialize it; `.immediatelyAvailableMetadataOnly` is not used anywhere in the repo.
- **Why:** Importing or moving an item whose target name collides with an evicted file (a 200 MB audio or USDZ) probably downloads that file just to learn that the name is taken, and occupies a `.download` limiter slot (of 1-3) while it does so, which is the stall CODE_AUDIT_21 §3.8 worked around. Not verified on a device.
- **Action:** Pass `.immediatelyAvailableMetadataOnly` for the existence/directory-flag check (and keep the full read only where bytes are needed); verify with an evicted file on a device.
- **Severity:** Medium   **Area:** CoreRPG Files/Persistence/Model

### 7.2 Quadratic scans of the archive path list during collection discovery
- **Location:** Modules/CoreRPG/Foundry/FoundryVTTDecoder+CollectionDecoding.swift:28-37, 96-98; Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:546-550; Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:131-156
- **What:** For every collection spec / manifest pack the code filters the whole `source.paths` (up to 100 000 entries, with `lowercased()` per path) and `levelDBDirectories` does `specs.contains` per directory; `liveLevelDBPaths` does `source.paths.first` per spec.
- **Why:** A crafted ZIP with ~50 000 tiny valid `.ldb` files in distinct directories (or a manifest declaring many packs) costs specs x paths ~ 10^9-10^10 string operations; the work has only coarse cancellation points, so import appears hung for minutes. The 100 000 spec cap does not bound the product.
- **Action:** Build a directory -> [path] index once in `FoundryVTTDataSource` (and a lowercase-suffix index), look specs up in O(1); cap spec count to something realistic (e.g. 1 000).
- **Severity:** Medium   **Area:** CoreRPG Foundry/Sheet

### 7.3 Memory ceilings are sized for macOS but apply on iOS/tvOS/visionOS
- **Location:** Modules/CoreRPG/Foundry/FoundryRuleModels.swift:745-755 (defaults 1 GiB archive, 64 MiB entry, 512 MiB rule data/resource batch); Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:1241-1278 (bridge resource cache); Modules/CoreRPG/Foundry/FoundryVTTBridgeDecoding.swift:183-192, 293-318
- **What:** One `FoundryImportLimits.default` for all platforms; `FoundryJSONValue` trees of up to 512 MiB of JSON are built (typically 5-10x expansion, plus each document keeps its own `rawData` and every embedded document repeats the parent's nested array, plus the Sanitizer makes another full copy), the bridge resource cache keeps every decoded asset (up to 512 MiB) alive until the next preflight, and a bridge asset line transiently holds the 86 MB line copy + the JSON String + the decoded Data.
- **Why:** On an iPhone/Apple TV a large Foundry world import is killed by jetsam rather than rejected with `fileTooLarge`; the app loses the whole session. On macOS it is merely slow.
- **Action:** Platform-specific default limits (e.g. 128 MiB rule data, 128 MiB resource batch on iOS/tvOS/visionOS), drop the bridge resource cache after the commit finishes (or make it load assets on demand by file offset), and stream asset lines instead of materialising them as JSON strings.
- **Severity:** Medium   **Area:** CoreRPG Foundry/Sheet

### 7.4 HTML-to-text regexes are quadratic on unterminated tags and rebuilt on every call
- **Location:** Modules/CoreRPG/Foundry/FoundryTextDecoder.swift:23-41
- **What:** `(?is)<!--.*?-->` and `(?is)<\s*(script|style|template|noscript)\b[^>]*>.*?<\s*/\s*\1\s*>` are lazy scans that run to the end of input for every unterminated opener; the four `NSRegularExpression` objects are compiled on every `plainText` call.
- **Why:** A description field of a few MB made of repeated `<!--` or `<script>` without a closer takes O(n^2) (each opener scans to the end), and mapping of thousands of documents recompiles four patterns each time.
- **Action:** Hoist the expressions into static lets, and replace the two lazy patterns with a single linear scanner (find the opener, `range(of:)` for the closer once, stop if absent).
- **Severity:** Medium   **Area:** CoreRPG Foundry/Sheet

### 7.5 `decodeEntities` scans to end of string for every `&` without a semicolon
- **Location:** Modules/CoreRPG/Foundry/FoundryTextDecoder.swift:233-240
- **What:** `source[current...].firstIndex(of: ";")` is evaluated before the 34-character distance check, so each `&` is O(remaining length).
- **Why:** A text field consisting of many `&` and no `;` (also plausible in legitimate text such as "R&D & A&B" repeated) is O(n^2); 1 MB of `&` is 10^12 comparisons.
- **Action:** Search only a 34-character window (`source[current...].prefix(35)`).
- **Severity:** Medium   **Area:** CoreRPG Foundry/Sheet

### 7.6 `TableRootSheet` builds (and discards) a full `SheetRootModel` on every `init`
- **Location:** Modules/CoreRPG/Sheet/TableRootSheet.swift:21-45
- **What:** `_sheetRootModel = State(wrappedValue: SheetRootModel(...))` evaluates the model, and therefore `sheetControllable.sheet(...)` for the whole item tree, every time the parent re-evaluates its body, although `@State` only keeps the first value. The per-init comment explains why the external-model path cannot reset, but the non-external path pays full price on each re-render. `preconditionFailure` also crashes if `rootManager` is not set yet.
- **Why:** Opening a large Character/Table sheet in a sheet/window while the parent updates (game state, search, selection) rebuilds the complete sheet tree repeatedly on the main actor; this violates the "@State initialised from a passed value" rule in the brief.
- **Action:** Create the model lazily (`@State private var sheetRootModel: SheetRootModel?` created in `.task(id: itemId)` / `onAppear`, or make an owner type that builds it once), and replace the precondition with an empty-state view.
- **Severity:** Medium   **Area:** CoreRPG Foundry/Sheet

### 7.7 Quick editor recomputes `initialText` and deep-copies the model on every parent body pass
- **Location:** Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:57,108-112,23-24
- **What:** `initialText` (`editController.editEntries(for:)` plus `parser.format` over all entries) is evaluated in `body` only to hand a `let initialText: String` to `QuickEntryEditorContentView`, which reads it once in `onAppear` (line 296). `init` also builds a `TextEditModel` and calls `model.copy()` (deep copy of the item) every time the parent re-creates the view, although `@State` keeps only the first value.
- **Why:** Every `showHelp`/`showResult`/`showInspector` toggle and every parent update re-formats the whole table text and copies the model; large tables (hundreds of entries) make toggling the result pane sluggish.
- **Action:** Pass a closure evaluated in `onAppear`, and create the copy and the `TextEditModel` lazily (for example in `.task`/`onAppear` or through a small `@State` holder).
- **Severity:** Medium   **Area:** CoreRPG UI 2

### 7.8 A joining player's audio list delivers the pending track inside the serial master pipeline
- **Location:** Modules/GameRPG/Controller/MasterController+AudioMessages.swift:70-83 (also :289-310 `handleAudioDeliveryFailure`, :398-405 `showAudioStartItems`)
- **What:** The `.audioList` branch awaits `deliverPendingAudio(pending, to: [sender])`, which exports the track (`audioPackage`) and hands it to the transport, while still inside `process(_:)` of the pipeline's single worker. `startAudioDelivery` (:222) was added precisely so the delivery does not run in the master's action chain, but this path and the failure-retry path bypass it.
- **Why:** While the first export of a large track runs, every other player's receipts, asset requests and pin moves queue behind it (the queue holds 128 messages / 300 MB and then drops). It happens once per track version because the package is cached, but it lands exactly at join time, when the burst of lists and Character announcements arrives.
- **Action:** Route these two call sites through `startAudioDelivery`-style detached delivery (keeping the supersession checks), or at least do not await the export inside the handler.
- **Severity:** Medium   **Area:** GameRPG Controllers

### 7.9 Room list resets are O(n²) in the number of entries (hex maps)
- **Location:** Modules/MapRPG/Map/MapEditorSession+Content.swift:36-47 (`resetEntries`: `entries.entries.first(where:)` per incoming entry); Modules/MapRPG/Map/MapEditorActionRouter.swift:155-162 (`synchronizeRooms` calls `setEntry` for every entry); Modules/MapRPG/Map/MapEntryViewer.swift:95-101 (`setEntry`: `firstIndex` + `roomNodes.first` + `reconcileNeedlePoints` per call); same pattern in `toggleRoomFocus` edit branch (MapEditorActionRouter.swift:175-181)
- **What:** `resetEntries` scans the whole current entry list once per incoming entry before it even checks `workingCopy`; `synchronizeRooms` rewrites every entry through `setEntry`, which does two linear searches and rebuilds that entry's needle models, whether or not the entry changed.
- **Why:** At the 20,000-cell cap that is about 2x10^8 UUID compares per `resetEntries` and about 4x10^8 per room toggle, on the main thread. On a player's phone `resetEntries` runs for every master map update that changes `map.entries` (every room reveal, via `MapEditor.handleExternalEntryChange`); on the GM it runs on every room double tap and focus toggle. Noticeable hitch on big hex maps, scales quadratically.
- **Action:** In `resetEntries` check `workingCopy` first (player and GM game mode have none) and build an id-to-entry dictionary once. In `synchronizeRooms` only call `setEntry` for entries that differ, or give `MapEntryViewerModel` an id-to-index dictionary / a bulk `apply(updates:)`. Same for the focus loop.
- **Severity:** Medium   **Area:** MapRPG Map

### 7.10 Passive room store builds needle models for every entry
- **Location:** Modules/MapRPG/Map/MapEntryViewer.swift:65-71 (init), :208-250 (`reconcileNeedlePoints(with:)`/`(for:)`), :129-134 (`selectNeedle` walks all models); consumers only on `editEntries` (MapEditorSession.swift:243-273, NeedleMapPin.swift:14, MapEditorOverlayLayer.swift:189)
- **What:** `MapEntryViewerModel` is used for both the passive room store and the single active edit room, but needle point models (`@MainActor @Observable` class per vertex) are created for all entries of both. Grep shows needle APIs are only ever called on `rooms.active`.
- **Why:** A 20,000-cell hex map allocates about 120,000 observable objects on every `resetEntries` of the passive store (map open, every external entry change, hex rescale, every edit-mode room toggle via `syncDisplayEntries`), in game mode too where no needle exists.
- **Action:** Make needle tracking opt-in (a flag on the store, on only for `rooms.active`), or lazily create needle models for the active entry only.
- **Severity:** Medium   **Area:** MapRPG Map

### 7.11 Room hit layer creates one gesture view per room with no culling
- **Location:** Modules/MapRPG/Map/MapRoomCanvas.swift:196-212 (`MapRoomHitLayer`), :214-262 (`MapRoomHitTarget`); enabled by MapEditorSession.swift:113-124
- **What:** `ForEach(rooms.roomNodes)` builds a filled `Path` view, `contentShape`, a high-priority double-tap/long-press gesture, the viewport gesture modifier and three accessibility modifiers/actions for every room, including all hex cells.
- **Why:** Up to 20,000 such views are instantiated whenever the GM game surface or editor with no active room opens or entries are reset. The Canvas layer was culled in CODE_AUDIT_21 §7.8, the hit layer was explicitly left unchanged.
- **Action:** Cull to the visible rect (like `visibleContentRect`), or replace per-room views by one hit-test surface that resolves the room from the tap location through the existing path list (and offers the accessibility actions for the nearest rooms only).
- **Severity:** Medium   **Area:** MapRPG Map   **Status:** [OPEN since CODE_AUDIT_21 §7.8]

### 7.12 Hex scale slider in the editor rebuilds the whole grid on every tick and drops revealed state
- **Location:** Modules/MapRPG/Map/HexMapScaleView.swift:65-70 (`onChange(of: model.hexScale)` calls `onScaleChanged` for every value); Modules/MapRPG/Map/MapEditController+HexGrid.swift:41-60 (`updateHexScale`: `grid`, `replaceGrid`, `syncDisplayEntries`); toggle path :19-33
- **What:** The game toolbar defers the rebuild to slider release (`hexScaleCommit`, CODE_AUDIT_21 §5.19), the editor's `HexMapScaleView` still regenerates up to 20,000 entries and reconciles all room nodes per tick. The editor path also does not call `carryingRevealedArea`, so cells revealed in the editor (cells can be toggled there) are hidden again on every scale change, unlike the game path in `EditController.createHexMap`.
- **Why:** Main-thread stalls while dragging the slider on big grids; inconsistent behaviour between editor and game rebuild.
- **Action:** Rebuild on release (`onScaleEditingChanged(false)`) and keep the live value only in the slider; use `carryingRevealedArea` in `MapEditController.updateHexScale`/`toggleHexMap`.
- **Severity:** Medium   **Area:** MapRPG Map

### 7.13 Full map fingerprint (redact, JSON-encode, SHA-256) is rebuilt up to four times per content update and on every generation lookup without an authoritative record
- **Location:** Modules/MapRPG/Model/MapUpdatePayload.swift:34-44; Modules/MapRPG/Controller/GameController+Metadata.swift:42-53, 91-130, 134-146, 153-160; Modules/MapRPG/Controller/GameController.swift:317-319, 339-341, 405-412 (`networkMapContentUpdate`); Modules/CoreRPG/Model/StableVersionDigest.swift:17-26
- **What:** `MapUpdatePayload.init(model:)` always builds a snapshot, a fully redacted copy, then a canonical encoding and digest of the whole map. `mapContentVersion`, `packageCoreMetadata` (called twice per `stablePackageMetadata` attempt), `currentMapReference`, `currentMapContentUpdate` and `mapContentCapture` each construct it just to read `contentVersion`. One `networkMapContentUpdate` therefore does at least four builds (capture, two in `stablePackageMetadata`, one `packageCoreMetadata`), more on a retry. `networkGeneration(for:)` does one more per call when `authoritativeGenerations[itemId]` is missing (it is set to nil by `recordAuthoritativeGeneration` for any `.map` data without both versions), and is called for every mapState, pin and battle message.
- **Why:** All of it runs on the main actor. A hex-grid map carries hundreds to thousands of cells with six points each; every game-master edit, "Refresh Shared Map", and each player pin or battle message in the no-record case pays several full JSON encodes plus SHA-256 on the main thread. Unmeasured, but the work is structurally redundant (the redaction output is thrown away whenever only the version is needed).
- **Action:** Split a `static func contentVersion(of model:)` (no redaction, no payload) from the payload builder; compute it once per content update and pass it through `stablePackageMetadata` / the retry loop; cache it per model change token for `networkGeneration`.
- **Severity:** Medium   **Area:** MapRPG rest

### 7.14 Room thumbnails rotate and crop on the main actor, once per room
- **Location:** Modules/MapRPG/Controller/CacheController.swift:35-48; Modules/MapRPG/Extensions/UIImage+Crop.swift:7-28, 45-52
- **What:** `createThumbnail` is `@MainActor` (protocol requirement). For each room it fetches the photo thumbnail source (up to 1024 px), then `rotated(byDegrees:)` redraws the whole bitmap into a new CGContext before the crop, even for a 3x3 px room. A map with 40 visible rooms rotated by a non-zero angle does 40 full-bitmap redraws on the main actor.
- **Why:** Scrolling a room list of a rotated map stalls the main thread; maps with `degrees == 0` skip the redraw.
- **Action:** Crop first in canvas space using an inverse-rotated rect, or cache the rotated canvas image per map/photo version; run the CPU part `@concurrent`.
- **Severity:** Medium   **Area:** MapRPG rest

### 7.15 Sheet update rebuilds every entry's sheet on each change (quadratic lookups)
- **Location:** Modules/AdventureRPG/Controller/SheetController.swift:87-180 (`update`): `entryIds.contains` inside filter + `removeAll` (:124,129), `sheetModel.entries.first(where:)` per entry (~:135), and a full `sheet(entry:...)` projection per entry (:147) including `linksFrom` and cross-module `SheetLinkGuard` lookups
- **What:** Every call to `update` (runs on the main actor after each edit) is O(entries²) and re-materialises each entry's link sheets even when only one entry changed.
- **Why:** Adventures extracted from long PDFs have hundreds of entries; typing in one entry rebuilds all of them. Not measured.
- **Action:** Build a `[UUID: SheetModel]` dictionary and a `Set` of entry ids once, and project only entries whose content/links changed (or are new); profile with a 500-entry adventure first.
- **Severity:** Medium   **Area:** AdventureRPG

### 7.16 SheetController.update(entry:) re-projects each entry's whole subtree on every update, then updates it again
- **Location:** Modules/CharacterRPG/Controller/SheetController.swift:204-264 (full re-projection at 212, recursive `update` of children at 251-255); info logs at 141 and 184
- **What:** For every existing entry the update path calls `sheet(entry:)`, which rebuilds the entire group sub-value tree and all link sheets from scratch (plus `linkController.calculate` and `linksFrom` per entry), only to diff it against the existing model and then call `update(...)` on each matched child, which re-projects its own entries once more.
- **Why:** Each nesting level rebuilds everything below it, so a group-in-group sheet does O(depth x size) work on the main actor for every observed change (typing, dice roll, game sync). Each `update` also emits two `info` log lines with an emoji and a measured duration.
- **Action:** Project only name, description, editType, sheetType and the entry's inline dice for the entry itself and reconcile children by source id without building their subtrees; log at debug level or drop the timing.
- **Severity:** Medium   **Area:** CharacterRPG

### 7.17 Sheet screens build a GeneratorController (engine plus model session) inside `body`, before checking availability, and FIFO eviction can tear down a visible one
- **Location:** Modules/GeneratorRPG/View/SheetAIAssistantContext.swift:40-46; Root/GeneratorRootModel.swift:122-134
- **What:** `SheetAIAssistantPlacement.body` calls `generatorRoot?.generatorController(forItem:)` for every sheet screen, creating a `ConversationEngine`, `SystemLanguageModel`, `LanguageModelSession` and `FoundationManager` per item visited, and only then tests `availability`. The cache evicts first-in, first-out at 12 entries and calls `tearDown()` on the evicted one.
- **Why:** on a device without Apple Intelligence every visited sheet still allocates a session; on macOS/visionOS with several windows, the 13th distinct item evicts the oldest-created controller even if its window is still on screen and mid-generation, cancelling it silently.
- **Action:** check `SystemLanguageModel.default.availability` (cached once) before creating the controller, create it lazily when AI mode is first activated, and evict least-recently-used skipping controllers with `isLoading`/`isExtracting`.
- **Severity:** Medium   **Area:** GeneratorRPG

### 7.18 "Convert to JPEG" runs the JPEG encode on the main actor and re-encodes from the 8192 px capped decode
- **Location:** Modules/PhotoRPG/Controller/EditController.swift:20-31 (`@MainActor convert`), Modules/CoreRPG/Extensions/Image+AKImage.swift:230,244 (decode cap)
- **What:** `convert(itemId:)` is `@MainActor`, takes the cached full image (decoded with `maximumDecodedPixelSize = 8192`) and calls `jpegData(compressionQuality:)` inline; the import paths encode off-main (`@concurrent encodedJPEG`, CODE_AUDIT_21 §7.10), this one was missed.
- **Why:** A large PNG/HEIC/TIFF hitches the UI during the encode, and a source wider than 8192 px is permanently downscaled by the conversion (the original file is replaced) without telling the user.
- **Action:** Encode through the same `@concurrent` helper, and convert from the original data/URL (or refuse/warn) instead of the capped cache image.
- **Severity:** Medium   **Area:** PdfRPG + PhotoRPG

### 7.19 Foundry mapper compiles regular expressions per call
- **Location:** Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+SharedHelpers.swift:289-327 (`rewriteFoundryLinks`, called from `safeText`/`decodedFoundryText` for every description, entry and name), :405-419 (`simpleModifier`, builds an `NSRegularExpression` plus a Regex literal); FoundryVTTDomainMapper+DiceAndValues.swift:27-36 (two `NSRegularExpression`s per formula)
- **What:** each call rebuilds a link-type alternation pattern and parses it again.
- **Why:** a system or world package maps tens of thousands of strings on the main actor (the mapper is `@MainActor`, see the comment at FoundryVTTDomainMapper.swift:263-269); regex compilation dominates `rewriteFoundryLinks` even for strings that contain no `@`. CODE_AUDIT_25 §7.1 fixed the same pattern in `Calculator`.
- **Action:** hoist the expressions into static lets; return early in `rewriteFoundryLinks` when the text contains no `@`.
- **Severity:** Medium   **Area:** RolePlayGameKit

### 7.20 Idle weather layers keep redrawing at display rate
- **Location:** Modules/WeatherRPG/View/WeatherEffectLayers.swift:15-40, Modules/WeatherRPG/Weather/StarsView.swift:21-57, LightningView.swift:21-45, CloudsView.swift:35-60, Modules/WeatherRPG/Weather/StarField.swift:19-26
- **What:** `StarsView` is always in the stack and only faded with `.opacity(starOpacity)`; its star alpha is zero for time 0.33-0.78, yet its `TimelineView(.animation)` keeps drawing every frame, and `change(size:)` creates one star per 1000 pt^2 without a cap (about 2000 on a 1920x1080 tvOS screen, more in a large visionOS window), each blooming star copying the context and applying a blur. `LightningView` redraws a full-screen transparent fill and two blur-filter passes every frame when `frequency < 1` or while waiting; `CloudsView` runs its timeline with zero clouds.
- **Why:** In game mode (`useGame`) four animated canvases run continuously on a phone/TV/headset for effects that are invisible, which costs battery and frame time.
- **Action:** Do not instantiate `StarsView` while `starOpacity == 0`, pause the lightning timeline in `.waiting` state with no periodic trigger, skip `CloudsView` for `.none`, and cap the star count.
- **Severity:** Medium   **Area:** RuleRPG + WeatherRPG

### 7.21 Player packages carry the full lossless Foundry payload, and the version digest re-encodes it on every call
- **Location:** Modules/RuleRPG/Model/RuleModel.swift:234-238 (`version` = `StableVersionDigest.digest(CanonicalRuleContent)` incl. `sourcePayload`), :386-398 (`encode` writes `sourcePayload`); Modules/RuleRPG/Controller/ExportController.swift (no `playerExportData` override); Modules/CoreRPG/Controllable/ExportControllable.swift:395-402; Modules/CoreRPG/Controllable/GameControllable.swift:221, :318
- **What:** `RuleModel.version` JSON-encodes (sorted keys) and hashes the whole model including the raw `FoundryRuleDefinition`/document JSON each time it is asked, and the same payload is exported to players when a rule is revealed.
- **Why:** `hasItem(id:version:)` and the version lookup run on the main actor for every reveal/availability check, and a rule can carry hundreds of KB of raw JSON that players never see (the viewer shows only entries and metadata). It also ships the unprocessed source (unused fields) to every player over SharePlay/LAN, which is the slow channel documented in memory.
- **Action:** Override `playerExportData(for:)` to drop `sourcePayload`, and compute the version from the same player projection (master and player must agree, see GameControllable.swift:221); cache the version per edit counter if it stays hot.
- **Severity:** Medium   **Area:** RuleRPG + WeatherRPG

### 7.22 `mergeEntries` is O(imported x existing) and recomputes `withoutLink()` for every pair
- **Location:** Modules/RuleRPG/Controller/EditController.swift:107-123
- **What:** For each imported entry it scans `existing` for the id (linear) and always builds `hierarchyFallbackIndices`, even when the id matched, calling `existing[$0].name.withoutLink()` per candidate.
- **Why:** A Foundry rule projects up to about 500 value entries plus groups/effects; a quick-editor Save or re-import costs hundreds of thousands of string transforms on the main actor.
- **Action:** Index existing entries by id and by (name without link, kind, parentId) once; compute the fallback lazily only when the id lookup misses.
- **Severity:** Medium   **Area:** RuleRPG + WeatherRPG

### 7.23 Rule quick editor does O(n) tree work per row on every keystroke
- **Location:** Modules/RuleRPG/View/RuleQuickEntryEditor.swift:130-175 (`RuleQuickEntrySectionEditor.body`, `kindSelection`, `parentSelection`)
- **What:** Every row receives `$entries` for the whole array, so each keystroke in any field re-evaluates all row bodies; each does `entries.firstIndex` and `RuleEntryTree.validParentGroups` (builds a child map and walks descendants) and a Picker listing every group.
- **Why:** For an imported rule with a few hundred entries that is O(n^2) per keystroke and makes typing laggy on the main actor.
- **Action:** Compute the group list once in the parent (or lazily when a Picker opens), give each row an entry binding instead of the whole array, and keep tree validation in the setters.
- **Severity:** Medium   **Area:** RuleRPG + WeatherRPG

### 7.24 In-memory image paths bypass the size caps meant for the ~120 MB extension limit
- **Location:** Sources/RPGShare/ItemProviderImporter.swift:244-264 (`loadItem` returning `.data` from `Data`/`NSData`), :271-290 (`loadDataRepresentation` has no byte limit), :105-113 (`downsampledIfNeeded` only runs after the whole payload is in memory)
- **What:** The file/URL path is capped (`maximumSourceFileByteSize`, downsampled from disk), but a provider that hands over `Data` or an object that has to go through `loadDataRepresentation` loads the full original into memory before any check.
- **Why:** A host app that shares an image as data (browser long-press, some editors) with a 100+ MB original can get the extension jailed-killed; the share is lost with no message. CODE_AUDIT_18 §6.4 only closed the URL/file path.
- **Action:** Prefer `loadFileRepresentation` (a temporary file the importer already knows how to downsample from disk) for the data fallback, and check `Data.count` against the source cap before decoding.
- **Severity:** Medium   **Area:** Sources + Resources

### 7.25 Shared images are decoded at full resolution inside `body`, up to ten at once
- **Location:** Sources/RPGShare/PhotoSection.swift:20-35 (`AKImage(data:)` per cell in `body`); Sources/RPGShare/SharingView.swift:141 (`.animation(value: imageListModel.images)`)
- **What:** Each preview cell builds an `AKImage` from JPEG data of up to 4096 px (roughly 50 MB decoded each) every time the cell body runs, and `LazyHStack` keeps created cells alive; `ImageItem` is `Hashable` over its whole `Data`, so the animation `value:` compares megabytes of image data on each SharingView update.
- **Why:** The memory budget the importer works hard to respect can be spent by the preview alone; unverified on device, but 10 photos are explicitly allowed by the activation rule.
- **Action:** Create thumbnails once (ImageIO thumbnail at the display size) when the images are loaded and store them in `ImageItem`; animate on `images.map(\.id)`.
- **Severity:** Medium   **Area:** Sources + Resources

### 7.L Low-severity items (40)

- **7.26 Export id collection is quadratic for large folders** — Modules/CoreRPG/Controllable/ExportControllable.swift:126-141 — _CoreRPG Controllable/Import/Links_. Count children per folder once (dictionary of remaining ids) and keep a `queued` Set next to `checkIds`.
- **7.27 Folder membership sort looks up names per comparison** — Modules/CoreRPG/Controllable/EditControllable.swift:410-416 — _CoreRPG Controllable/Import/Links_. Map to (name, entry) once, or insert at the binary-search position.
- **7.28 Export fallback loads the whole finished export into memory** — Modules/CoreRPG/Controllable/ExportControllable.swift:292-297 — _CoreRPG Controllable/Import/Links_. Use `copyItem` after removing the destination, or stream with a FileHandle.
- **7.29 Link register: empty arrays stay in the dictionaries and hydration is quadratic per destination** — Modules/CoreRPG/Links/LinkRegisterListModel.swift:157-186 — _CoreRPG Controllable/Import/Links_. Keep a `Set` of occurrence ids per destination for the dedup check; remove a key when its array becomes empty.
- **7.30 `WallclockTimestamp.<` allocates two strings per comparison** — Modules/CoreRPG/CRDT/WallclockTimestamp.swift:104-106 — _CoreRPG Controllable/Import/Links_. Compare `(lhs.clock, lhs.actorId) < (rhs.clock, rhs.actorId)`.
- **7.31 Text renderer posts a Task on every draw pass** — Modules/CoreRPG/LinkRenderer/LinkHighlightTextRenderer.swift:95-97 — _CoreRPG Controllable/Import/Links_. Skip the task when the measurements equal the last published ones (compare before dispatching).
- **7.32 PeerFileDataStore.hold compares the whole old and new Data under its lock** — Modules/CoreRPG/Files/PeerFileDataStore.swift:55-62 — _CoreRPG Files/Persistence/Model_. Compare outside the lock (return both values) or use the generation/hash the caller already has.
- **7.33 suggestedFileName recurses with one coordinated check per collision** — Modules/CoreRPG/Files/CloudDocumentController.swift:249-257 — _CoreRPG Files/Persistence/Model_. List the folder once and pick the first free `name-N` in memory; keep the non-replacing copy as the race guard.
- **7.34 Bit-wise CRC-32C and per-byte Snappy copies make LevelDB reading slow** — Modules/CoreRPG/Foundry/FoundryLevelDBReader.swift:360-371 — _CoreRPG Foundry/Sheet_. Table-driven (or `__crc32cb` intrinsic) CRC32C over slices without copies; use `append(contentsOf:)` for non-overlapping Snappy copies.
- **7.35 Artifact detection parses whole JSON files twice with Foundation's object tree** — Modules/CoreRPG/Foundry/FoundryArtifactDetector.swift:107-111, 130-139 — _CoreRPG Foundry/Sheet_. Peek at a bounded prefix (e.g
- **7.36 `FoundryValueHierarchy.nodes(from: [FoundryRuleValue])` copies a whole dictionary per insert on wide levels** — Modules/CoreRPG/Foundry/FoundryValueHierarchy.swift:80-88 — _CoreRPG Foundry/Sheet_. Remove the entry from the dictionary before mutating (`children.removeValue`) or mutate through `children[component, default: NodeBuilder()].insert(...)`.
- **7.37 Asset-path collection allocates a byte array and a `URL` per string** — Modules/CoreRPG/Foundry/FoundryPackageResolution.swift:124-133, 141-142 — _CoreRPG Foundry/Sheet_. Fast-path: skip strings without `.` for the extension test and without `<` for the HTML scan, use `utf8` view search and `lastIndex(of: ".")` instead of `URL`; only build the path string lazily when a
- **7.38 Packaged resource resolution reads, inflates and hashes every referenced asset during preflight and counts duplicates** — Modules/CoreRPG/Foundry/FoundryPackageResolution.swift:243-272 — _CoreRPG Foundry/Sheet_. Cache hash/size per resolved package path, count each package path once, and consider hashing lazily from the ZIP central-directory CRC (already verified) with SHA-256 computed at commit time.
- **7.39 `FoundrySystemPackageReader.readResources` re-opens (re-hashes) the whole archive on every call** — Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:43-93 — _CoreRPG Foundry/Sheet_. Confirm callers; if unused remove `readResources`/`readResource`/`read(from:)` public surface (keep `read(reusingArchive:)`), otherwise use the shared cache.
- **7.40 `FoundryImportArchiveStore.archive(id:)` has no size cap and `save` checks size only after encoding** — Modules/CoreRPG/Foundry/FoundryImportArchive.swift:125-146 — _CoreRPG Foundry/Sheet_. Check `fileSize` before reading; estimate package size from the preflight statistics (raw bytes) before encoding.
- **7.41 Search resets every cached link model on each keystroke** — Modules/CoreRPG/Sheet/SheetRootModel+Search.swift:31-35 — _CoreRPG Foundry/Sheet_. Debounce (cancel-then-replace) the filter/reset, and only reset models whose row is visible or whose text contains the previous/new term.
- **7.42 `MasterRPGTips.refreshEligibility` walks every item of every module on the main actor after each add** — Modules/CoreRPG/Tips/MasterRPGTips.swift:196-264, called from Modules/CoreRPG/Sheet/SheetEntryAddButton.swift:24, Module — _CoreRPG Foundry/Sheet_. Skip the scan once all count-based tips are invalidated (`MasterRPGTipState` already knows), or maintain counters incrementally; at minimum early-exit when tips are disabled.
- **7.43 Move-into-group context menu computes candidates twice and is unbounded** — Modules/CoreRPG/LGViews/ListRootContextMenu.swift:337-401 — _CoreRPG UI 1_. Compute the list once, cap it, or use a searchable picker sheet.
- **7.44 `CacheItemListModel` is never pruned for removed entries and keys are built with string interpolation** — Modules/CoreRPG/ItemList/CacheItemListModel.swift:22-52 — _CoreRPG UI 2_. Key by a `struct { CacheType, UUID }`, drop entry ids when an entry is removed, and only reset visible models on search.
- **7.45 Slider drag saves on every tick** — Modules/CoreRPG/Editors/TextDoubleEditor.swift:92-95 — _CoreRPG UI 2_. Save on `onEditingChanged(false)` for the slider and on submit/focus loss for the field; keep onChange only for the toggle.
- **7.46 Unscaled `UIGraphicsImageRenderer` bake for oriented photos has no pixel cap on iOS/visionOS** — Modules/GameRPG/Table3D/GameTableEntities.swift:60-71 — _GameRPG Table3D_. Apply the same `maximumBitmapDimension` cap on UIKit platforms and render at the capped size.
- **7.47 Board texture composite input and `TextureResource` upload run on the main actor** — Modules/GameRPG/Table3D/GameBoard.swift:53-101, 176-215 — _GameRPG Table3D_. Cache the converted `CGImage` per (photo id, version, degrees) in the model (`currentMapImage` already identifies it) so fog toggles reuse it. [[OPEN since CODE_AUDIT_3dTable §7.3, partial]]
- **7.48 Every player's audio and file list triggers a broadcast of all lists** — Modules/GameRPG/Controller/MasterController+AudioMessages.swift:70-73, 113-117 — _GameRPG Controllers_. Coalesce per module with one pending broadcast task.
- **7.49 Journal metadata loading is sequential and unbounded per snapshot** — Modules/GameRPG/SharePlay/RPGSharePlayController+JournalAttachments.swift:76-103, 40-64 — _GameRPG SharePlay/Network_. Cap the entries processed per snapshot (for example the newest 16 by counter, or skip senders other than the master on player devices before loading metadata), or load the metadata of uncached attachm
- **7.50 Statistics reload fetches every event of every session on the shared context** — Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift:215-258 and 150-168, Modules/GameRPG/Statistics — _GameRPG Views/Battle/Statistics_. Aggregate with `NSExpression`/grouped fetches (count and sum by kind/outcome/module/origin), and do the duplicate check with one `deduplicationKey IN %@` fetch per batch.
- **7.51 Empty-game content ticks every second for a minute-resolution clock** — Modules/GameRPG/GameViews/GameRootViewer.swift:325-333 — _GameRPG Views/Battle/Statistics_. Reuse `GameElapsedTimerText`'s anchored one-minute timeline (or the view itself).
- **7.52 Room culling pass still walks every node and recomputes `boundingRect` per frame** — Modules/MapRPG/Map/MapRoomCanvas.swift:78-91 — _MapRPG Map_. Store `bounds` as a stored property computed once in `makePath`/`update`, mark the node list `@ObservationIgnored` for the canvas read or snapshot it once per entry change, and optionally bucket nodes
- **7.53 Fog tiles are drawn for the whole room, not the visible part** — Modules/MapRPG/Map/MapRoomCanvas.swift:146-169 — _MapRPG Map_. Intersect the column/row origins with the visible content rect before drawing (keep `MapFogTileBudget.allowsTiling` on the full bounds so 2D and 3D still agree).
- **7.54 Edit toolbar body does O(entries) work on every re-evaluation** — Modules/MapRPG/Map/EditMapToolBar.swift:296-304 — _MapRPG Map_. Derive `editEntries` once in the session (non-hex ids in order) and invalidate on entry-structure change; compute `sharedMapHasChanges` from the undo history's dirty flag or compare only when the refr
- **7.55 Undo history stores full map copies including the hex grid** — Modules/MapRPG/Map/MapEditorPinHistory.swift:8-19 — _MapRPG Map_. Exclude the regenerable hex grid from snapshots (store only its scale and revealed ids), or lower the depth when the entry count is large; avoid the second `copy()` in `record`.
- **7.56 Adding N monsters saves N times** — Modules/MapRPG/Controller/EditController.swift:366-372 — _MapRPG rest_. Append all pins to the model first and save once with a count in the message.
- **7.57 `changedLinkRegisterModels` is O(n²) over entries** — Modules/AdventureRPG/Model/AdventureModel.swift:126-165 — _AdventureRPG_. Index old and new entries once into dictionaries by id and iterate those.
- **7.58 Embedded artwork is decoded on the main actor** — Modules/AudioRPG/Model/AudioPlayerBarViewModel.swift:40-45, 74-79 — _AudioRPG_. Do the downsampling inside the `@concurrent` function and return a `CGImage`/Sendable result, building `Image` on the main actor.
- **7.59 `appIconImage()` rebuilt in every body evaluation** — Modules/AudioRPG/Audio/AudioPlayerTimelineView.swift:150, Modules/AudioRPG/Audio/AudioPlayerMiniBarView.swift:83, Module — _AudioRPG_. Cache the image in a static let (or in the view model once).
- **7.60 `hasAudio(itemId:)` walks the folder subtree inside view bodies** — Modules/AudioRPG/Controller/ItemController.swift:35-39 — _AudioRPG_. Compute lazily per folder (e.g
- **7.61 Result computation repeated several times per view body** — Modules/DiceRPG/Game/Detail/DiceGameResult.swift:49-66 — _DiceRPG_. Compute `result` once per row/body (`let result = ...`), and give `DieViewerView` a precomputed colour array per set instead of a per-die `diceSuccess` lookup.
- **7.62 PDF page text is read in full before the character cap** — Modules/GeneratorRPG/BasicAI/Providers/PdfPageTextReader.swift:26-38 — _GeneratorRPG_. stop reading once the budget is reached and cap each page string at `maxCharacters` right after reading.
- **7.63 PhotoEntity data export PNG-encodes the full cached image** — Modules/PhotoRPG/Intent/PhotoEntity+Image.swift:12-17, Modules/PhotoRPG/Intent/PhotoEntity.swift:110-112 — _PdfRPG + PhotoRPG_. Drop the data representation (the file representation covers images) or load the file data and return it as-is; do not encode on demand.
- **7.64 Generation tree flattened repeatedly inside view bodies** — Modules/TableRPG/Model/TableGenerationModel.swift:158-188 — _SpaceRPG + TableRPG_. Cache the flattened list/`selectedEntries` (invalidate in `rebuildChildren`/`select`) if profiling shows cost
- **7.65 Stale-scan cleanup runs synchronously on the main actor when the scanner model is first created** — Modules/SpaceRPG/Record/AppDataModel.swift:98-101 — _SpaceRPG + TableRPG_. Run the cleanup in a `@concurrent` background task (like `reset()` already does for the live folder).

## 8. SwiftUI / UI

### 8.1 Remove-badge buttons have no accessible "remove" semantics
- **Location:** Modules/CoreRPG/ViewModifiers/RemoveItemViewModifier.swift:20-36; use Modules/CoreRPG/Editors/RemoveTagsEditor.swift:30
- **What:** The whole content (for example the tag text) becomes the button label and the red minus badge is `accessibilityHidden(true)`; no label, hint or role says what the button does.
- **Why:** VoiceOver announces "DUNGEON, button" and activating it deletes the tag. Accessibility guideline violation on a destructive action.
- **Action:** Add an accessibility label/hint such as "Remove <content>" (needs the caller's title) and `role: .destructive`.
- **Severity:** Medium   **Area:** CoreRPG UI 2

### 8.2 Game dice instances are created and cached inside view `body`
- **Location:** Modules/CharacterRPG/View/EntryListDiceRow.swift:20; Modules/CharacterRPG/Controller/GameController+Dice.swift:12-49 (`cachedGameDice` writes `gameDiceModel.gameEntryDiceId` / `gameDiceId` and calls `createGameDice`, which calls `setGame(item:)` in DiceRPG/Controller/GameController.swift:235-242); Modules/CharacterRPG/View/InlineRowViewer.swift:44; Modules/GameRPG/GameViews/QuickDice/QuickDiceSlotView.swift:120
- **What:** `EntryListDiceRow.body` calls `gameDiceId(itemId:entryId:)`, which reads and then writes the `@Observable` `ValueGameModel` and inserts a new dice into the game item store the first time (and again whenever the dice template id changes).
- **Why:** Mutating observable state that the same body just read is the "modifying state during view update" pattern; it forces a second render pass and is order-dependent. When the entry's `diceId` changes, the old game dice stays in `gameModel.itemData` forever (only `removeBattleCharacterCopies` and `resetGameDiceId` clear the maps, neither deletes the dice item), so the game store grows with every re-link. CLAUDE.md asks for view logic in testable models.
- **Action:** Resolve or create the game dice outside `body` (on game start, on `diceId` change via `.task(id:)`/`onChange`, or in the controller when the entry is edited) and let `body` only read; delete the superseded game dice when the template id changes.
- **Severity:** Medium   **Area:** CharacterRPG

### 8.3 AdditionalEntryRow's Equatable ignores the entry and text model its body reads
- **Location:** Modules/CharacterRPG/View/AdditionalEntryRow.swift:6-83 (`==` at 80-82; icon from `entry` at 69-78); wrapped with `.equatable()` at Modules/CharacterRPG/Controller/EditController.swift:144; caller Modules/CoreRPG/LGViews/EntryEditRow.swift:43-59
- **What:** `==` compares only `entryId`, yet `typeIcon` is derived from the passed-in `entry` value and the body renders `textModel`.
- **Why:** When an entry's type changes (text to number to decimal, or to a group) the row's `entry` struct changes but the views compare equal, so SwiftUI keeps the old value and the type icon can stay stale until the row identity is recreated. The earlier audit fixed the same shape in `InlineRowViewer` (now compares `source` and `destination`) but this row only had its UUID fixed. Not reproduced at runtime.
- **Action:** Include `entry` (it is `Equatable`) and the identity of `textModel` in `==`, or read the type from the observed model instead of the passed value. Verify with the type picker.
- **Severity:** Medium   **Area:** CharacterRPG

### 8.4 Accessibility label of the content-widget count hides the number
- **Location:** Sources/DiceRollerWidget/ContentWidgets.swift:121-124
- **What:** `Text(totalCount, format: .number).accessibilityLabel(Text(countLabel))` replaces the content with the label "characters"/"adventures".
- **Why:** VoiceOver reads "characters" instead of "3 characters" for the medium widget.
- **Action:** Use the number as the value (`accessibilityValue`) or build one combined label "\(count) \(countLabel)".
- **Severity:** Medium   **Area:** Sources + Resources

### 8.L Low-severity items (31)

- **8.5 ItemGenerationControllable returns AnyView** — Modules/CoreRPG/Model/ItemGeneration.swift:119-124 — _CoreRPG Files/Persistence/Model_. Make the requirement return `some View` via an associated type or a generic container, or document why erasure is required.
- **8.6 Close button uses an image-only label; hard-coded spacing/margins in the table sheet** — Modules/CoreRPG/Sheet/TableRootSheet.swift:104-114 — _CoreRPG Foundry/Sheet_. `Button("Close", systemImage: "xmark.circle", action:)` with `.labelStyle(.iconOnly)`; use default spacing/margins or named constants (already done for the inset).
- **8.7 Navigator tree is mutated from `body`** — Modules/CoreRPG/Navigator/Views/ManagedNavigationStack.swift:152-155 — _CoreRPG UI 1_. Register the child once (`LazyState` thunk or `.task`/`onAppear`) and keep only the dismissible refresh in a change handler.
- **8.8 GroupEditorController (and its model) is created inside a route body** — Modules/CoreRPG/Route/InternalRoute.swift:33 — _CoreRPG UI 1_. Create the model once in `GroupEditorView` via `@State` (initialised from item controller and ids) and keep `GroupEditorController` for saving only.
- **8.9 Views split into helper functions instead of View structs (CLAUDE.md rule)** — LGViews/EditorLinkView.swift:97, 116, 129 — _CoreRPG UI 1_. Extract the larger ones (placeholder, thumbnail, picker row, share bar, add-item button) into small structs; share one thumbnail view between the two photo views.
- **8.10 EditorLinkView.init writes to the observable model** — Modules/CoreRPG/LGViews/EditorLinkView.swift:6-12 — _CoreRPG UI 1_. Apply the preselection once in `onAppear`/`task`; keep `init` free of side effects.
- **8.11 Item detail root swaps the whole view subtree when `showsBottomOverlayBar` flips** — Modules/CoreRPG/ItemDetail/ItemDetailRootView.swift:157-178 — _CoreRPG UI 2_. Keep one structure (always apply `safeAreaInset`/`overlay`, with a conditional inner content) so the identity is stable.
- **8.12 Image-only buttons use `Image` + `accessibilityLabel` instead of a `Label`** — Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:177-183,206-225 — _CoreRPG UI 2_. `Label` with `.labelStyle(.iconOnly)`, as the entry header buttons already do.
- **8.13 `AnyView` in protocol surface and sub-folder detail** — Modules/CoreRPG/ItemList/EntryDataEditable.swift:52,159 — _CoreRPG UI 2_. Return `some View` through an associated type or a `@ViewBuilder` on a generic container; accept as known debt if the existential protocol cannot change.
- **8.14 Chevron in inspector rows is hard-coded red** — Modules/CoreRPG/Inspector/InspectorRowView.swift:258 — _CoreRPG UI 2_. Use the theme tint or `.secondary`.
- **8.15 `TextIntEditor(value:)` and `ToggleEditor(value:)` build a new model, with a new id, on every parent body pass** — Modules/CoreRPG/Editors/TextDoubleEditor.swift:7-11 — _CoreRPG UI 2_. Keep the model in `@State` inside the editor (created once, binding re-attached), or give the binding variant a stable id (for example a fixed UUID).
- **8.16 `FlowLayout` falls back to a 10 pt width and reports the full proposed width** — Modules/CoreRPG/Layout/FlowLayout.swift:14,48 — _CoreRPG UI 2_. Treat an unspecified width as `.infinity`/the sum of widths and return the used width; add a cache for the per-subview sizes (computed twice per layout pass).
- **8.17 A throttled player gets no "locked out" feedback** — Modules/GameRPG/Master/MasterNetworkController+Listener.swift:66-70, Modules/GameRPG/Network/ConnectionAttemptThrottle.s — _GameRPG SharePlay/Network_. Optional: advertise a lockout hint in the player's failure (the player can count its own consecutive bad-code results and show "wait before retrying") instead of changing the master.
- **8.18 Battle Round window shortcuts take over Command-Right in the HP and initiative text fields** — Modules/GameRPG/BattleRound/BattleRoundWindowToolbar.swift:25-41 — _GameRPG Views/Battle/Statistics_. Pick a combination that is not a text-editing command (for example Command-Return / Option-Command-Return) or disable the shortcut while a field is focused.
- **8.19 Hard-coded paddings in the roll strip** — Modules/GameRPG/BattleRound/BattleRollResults.swift:27, 56-57 — _GameRPG Views/Battle/Statistics_. Use `BattleRoundSpacing.extraTight/tight`.
- **8.20 "Clear Saved Game" runs without confirmation** — Modules/GameRPG/SetupViews/SelectedAdventureView.swift:158-190 — _GameRPG Views/Battle/Statistics_. Add a confirmation dialog with a destructive role (the Battle Round "End" already follows this pattern).
- **8.21 Hard-coded paddings and spacings across GameViews, SetupViews and Statistics** — about 107 sites, for example Modules/GameRPG/SetupViews/SelectedAdventureView.swift:30-60, Modules/GameRPG/SetupViews/Se — _GameRPG Views/Battle/Statistics_. Introduce one small spacing scale for GameRPG (BattleRoundSpacing generalised) and `@ScaledMetric` for the fixed frames; do it opportunistically when the files are touched.
- **8.22 No scroll-wheel or keyboard zoom for the map on macOS** — Modules/MapRPG/Map/MapEditorCanvasGestures.swift:100-148 — _MapRPG Map_. Confirm menu/keyboard zoom commands exist for macOS; if not add `onScrollGesture`/`⌘+`/`⌘-` through `ViewportModel`.
- **8.23 Low-contrast white symbols on tinted pin-menu buttons** — Modules/MapRPG/View/MapPopover.swift:366-372 — _MapRPG rest_. Use a darker tint or a contrast-aware foreground, honor `colorSchemeContrast`.
- **8.24 Drop view style deviations (SwiftUI rules)** — Modules/AdventureRPG/View/DropChooseView.swift:32 — _AdventureRPG_. Fix opportunistically when the file is next touched. [[OPEN since CODE_AUDIT_Adventure §8.2] for the shape, rest NEW]
- **8.25 Minor style deviations** — Modules/AudioRPG/Audio/AudioPlayerTimelineView.swift:36 — _AudioRPG_. Fix opportunistically; leave the `AnyView` until the protocol changes.
- **8.26 `InlineRowViewer` equality ignores `destination`** — Modules/DiceRPG/View/InlineRowViewer.swift:22-24 — _DiceRPG_. Compare `destination` as well.
- **8.27 Views split via helper methods instead of View structs** — Modules/DiceRPG/Game/Detail/DicePlayer.swift:46-83 — _DiceRPG_. Extract `DicePlayerRow`, `DicePlayerButton`, `DiceBagRow`.
- **8.28 View-layer rule violations (CLAUDE.md)** — View/PdfSummaryAnalysisView.swift:52-70 — _GeneratorRPG_. one shared `AnalysisErrorBanner` struct, convert helpers to structs, drop hard-coded spacing, give the photo an accessibility label (item name).
- **8.29 PdfWrapperView.updateView mutates observable state during the SwiftUI update pass** — Modules/PdfRPG/Pdf/PdfWrapperView.swift:99-113 — _PdfRPG + PhotoRPG_. Start the find from `.onChange(of: searchModel.searchText)` / a `.task(id:)` in the SwiftUI view instead of in `updateView`.
- **8.30 Foundry import state is lost when the user flips the Import segment** — Modules/RolePlayGameKit/View/AppImportView.swift:48-72 — _RolePlayGameKit_. keep both sections mounted (opacity/`allowsHitTesting`) or hoist the model into `AppImportView`; at minimum disable the picker outside `.notStarted`/`.preflight`.
- **8.31 Views built by private methods instead of View structs; one dispatcher computed property** — Modules/RolePlayGameKit/View/SplitNavigation.swift:170-201 — _RolePlayGameKit_. extract small `View` structs (leave `pageTab`, which returns `TabContent`).
- **8.32 Style items: animated alert toggles, hard-coded spacing, tvOS placeholder wiring** — View/SettingsView.swift:146,161,188 — _RolePlayGameKit_. use default spacing and set flags directly; remove the pointless `#if`; give `RootManager` an optional generator root or use its dice-only initializer on tvOS.
- **8.33 English text baked into persisted rule content; one header not localized** — Modules/RuleRPG/View/RuleQuickEntryEditor.swift:~148 — _RuleRPG + WeatherRPG_. Use `Text("Untitled Section", bundle: .ruleModule)` in a label closure; decide whether the stored labels stay English by design and note it.
- **8.34 Accessibility "Rotate/Tilt" actions do nothing on iOS and macOS** — Modules/SpaceRPG/Space/SpaceViewer.swift:881-900 — _SpaceRPG + TableRPG_. Apply the same rotation to the entity on the other platforms (the entity is already normalized and centered), or drop the rotate actions and the yaw/pitch value there.
- **8.35 Raw `String(describing: error)` shown in the reconstruction/scanner alerts** — Modules/SpaceRPG/Record/ReconstructionProgressView.swift:74-78, Modules/SpaceRPG/Record/Scanner3DRootView.swift:94-98 — _SpaceRPG + TableRPG_. Map the known cases to localized messages and fall back to `localizedDescription`.

## 9. Dead code / duplication / refactor

### 9.1 Files over 500 LOC that split cleanly
- **Location:** Modules/CoreRPG/Controllable/ImportControllable.swift (1145), EditControllable.swift (1029), ItemControllable.swift (810), GameControllable.swift (550)
- **What:** ImportControllable holds the import model, `PeerImportPolicy`, the stream loop, manual-review logging (722-852, ~130 LOC of log-only diffing) and the `InputStream` framing extension (1067-1145). EditControllable mixes basic properties, groups, folder/collection membership (328-517), delete/duplicate/restore/remove (574-879) and undo. ItemControllable mixes CRUD with the whole game-to-library persistence set (`persistFromGame`, `persistMissingFolders`, `persistMembershipChange`, file settle helpers, 282-455). GameControllable carries `ItemGameModel` (6-148) next to the protocol.
- **Why:** The three files are the shared core of every module; each unrelated change touches a 1000-line file and its merge surface.
- **Action:** Move `PeerImportPolicy`/`ItemDataImportModel` and the `InputStream` extension to `ImportModels.swift`/`InputStream+GmzFraming.swift`, the review-log helpers to `ImportControllable+ReviewLog.swift`; split EditControllable into `+Folders`, `+Delete`, `+Undo` (EditControllable+File is the precedent); move the game persistence block to `ItemControllable+GamePersistence.swift`; move `ItemGameModel` to its own file.
- **Severity:** Medium   **Area:** CoreRPG Controllable/Import/Links

### 9.2 Legacy-migration move paths are unreferenced or test-only and use unsafe URL(string:) parsing
- **Location:** Modules/CoreRPG/Files/FileUrlDataController+Manage.swift:14-51 (`move(fileUrl:name:category:)`, no caller in Modules, Sources or Tests) and :53-73 (`move(fileUrl:from:to:)`, only Tests/CoreRPGTests/FileUrlDataControllerFileOperationTests.swift:432); Modules/CoreRPG/Files/CloudDocumentController.swift:166-173 (`move(sourceUrl:destinationFilename:)`), :187-206 (`move(url:newCategory:)`), :245-247 (static `suggestedFileName(for:filename:category:)`)
- **What:** Two public `FileUrlDataController.move` overloads and three `CloudDocumentController` helpers are not reached by production code.
- **Why:** About 110 LOC that look live but are not. They also carry bugs the live `move(url:newName:)` already fixed (CODE_AUDIT_21 §5.15): `URL(string: newPath)` / `URL(string: destinationName)` cut a name at `#` or `?` (verified: `URL(string: "cat/a#b.png").path == "cat/a"`), the `.icloud` branch copies with a replacing write and never calls `suggestedFileName` (overwrites a file at the same relative path), and the stored result has no leading slash unlike every other stored path. If someone revives them the old bugs return.
- **Action:** Delete the two unreferenced overloads, the category move and its CloudDocumentController helpers, and the one test (or rebuild the category move on `move(url:newName:)`).
- **Severity:** Medium   **Area:** CoreRPG Files/Persistence/Model

### 9.3 Production Table outcome editor is built from preview fixtures (Fake*) with a latent trap
- **Location:** Modules/CoreRPG/Simple/SimpleSheetEditingSession.swift:79-88,93; Modules/CoreRPG/Fake/FakeExportController.swift:17-25,27-29; Modules/CoreRPG/Fake/FakeFolderListController.swift:63; Modules/CoreRPG/Fake/FakeSearchController.swift:27; Modules/CoreRPG/Controllable/RootManager.swift:142
- **What:** `SimpleSheetEditingSession` (used by TableRPG outcome editing, `TableGenerationController+OutcomeEditing.swift:29`) wires `FakeExportController.fake`, `FakeGameController.fake`, `FakeImportController.fake`, `FakeFolderListController.fake`, `FakeSearchController.fake`, `FakeViewController()` and `RootManager.preview(fake:)` into a real `ItemRootController`. The Fake files are compiled in every configuration (partly by design, so preview declarations compile in Release; `PreviewAssetFixture` and `TestWait` do gate their heavy parts with `#if DEBUG`), so about 980 LOC of fixtures ship in Release, and the rest cannot be gated while Simple depends on them.
- **Why:** (a) `FakeExportController.hubControllable` calls `preconditionFailure` when no hub was set; the session never sets one, so any code path that reads `rootExportController`/`rootImportController` (Modules/CoreRPG/Controllable/ExportControllable.swift:100-108, protocol defaults that forward to the hub) on this root traps in Release (whether the sheet UI reaches them is not verified). (b) The `static let fake` singletons (`FakeFolderListController.fake` with its `FolderListModel`/`ListDisplayModel`/`CacheItemListModel`, `FakeSearchController.fake` with `SearchModel.preview()`, `FakeItemController.fake`) are one shared mutable instance for every session and for previews, so state leaks between two open outcome editors. (c) Preview/test code is invisible to reviewers as production surface.
- **Action:** Introduce small production `Null*`/`Inert*` conformers (export, game, import, folder list, search, view) owned by Simple, give each session its own instances, and then wrap `Fake/` in `#if DEBUG` (tests build Debug). Make the export stub's hub access non-trapping.
- **Severity:** Medium   **Area:** CoreRPG UI 2

### 9.4 Same per-error switch copied into four places
- **Location:** Modules/GeneratorRPG/BasicAI/Providers/PdfSummaryAnalyzer.swift:135-188; PdfContentExtractor.swift:174-224; TableSummaryAnalyzer.swift:81-122; BasicAI/Errors/FoundationModelsError.swift:8-30
- **What:** four `GenerationError` to message mappers with near-identical cases and drifting wording (PDF-specific text in two, generic in two); the photo analyzer has a fifth path (`mapped`).
- **Why:** a new `GenerationError` case or a localisation fix has to be made four times; the PDF text is wrong when the same mapper is reused for tables.
- **Action:** one mapper taking a subject noun, in `FoundationModelsErrorHandler`.
- **Severity:** Medium   **Area:** GeneratorRPG

### 9.5 Dead "use PDF selection / text extracted" plumbing between the PDF viewer and four quick editors
- **Location:** Modules/PdfRPG/Root/ViewerRootView.swift:15,26,30 (`onTextExtracted` stored, never called); Modules/PdfRPG/Controller/ViewController.swift:30-32; Modules/PdfRPG/View/DetailFolderListView.swift:33; Modules/PdfRPG/Model/PdfViewerActions.swift:1-52 (no `@Environment(\.pdfViewerActions)` reader exists); writers: Modules/AdventureRPG/View/QuickEntryEditor.swift:34,49, Modules/CharacterRPG/View/QuickEntryEditor.swift:36,51, Modules/MapRPG/View/QuickEntryEditor.swift:33,46, Modules/TableRPG/View/QuickEntryEditor.swift:34
- **What:** Both consumers (`onTextExtracted?(...)` and the `pdfViewerActions` reader) were removed in 34b71c2cd; the parameter, the environment key and the closures in the quick editors (`usePdfSelection(selection:)`) remain and nothing invokes them.
- **Why:** The editors look like they can pull text out of a PDF into an entry, but selecting text in the viewer does nothing there (the selection only feeds the bookmark bar); misleading code and an API users may assume works.
- **Action:** Either restore the call (e.g. offer "use selection" from `PdfContentView`'s selection) or delete the parameter, `PdfViewerActions` and the four editor closures.
- **Severity:** Medium   **Area:** PdfRPG + PhotoRPG

### 9.6 visionOS editor chain (ExtendedSplitBar and four files) appears unreachable
- **Location:** Modules/RolePlayGameKit/View/ExtendedSplitBar.swift (86 LOC), ExtendedSplitWithDetailView.swift (60), SecondaryTabBar.swift (56), SecondaryTabBarExtButton.swift (53), BarButtonWithHoverEffectStyle.swift (46); only entry point is Route/RouteDestinationView.swift:35-37
- **What:** `ExtendedSplitBar` is only built for `RootRoute.editors` on visionOS, but nothing sends `.editors` there: `RootRoute.visionTabs` (Route/RootRoute.swift:115) has no `.editors`, `visionGameWindowActions` (WindowRouter.swift:160-178) never emits it, and the visionOS editor window uses `SplitEditorNavigation` with `visionEditorTabs`. `BarButtonWithHoverEffectStyle` has a single user (the secondary button). Only a snapshot test touches it. Marked unverified at runtime: a restored `SceneStorage("GameRoute")` from an older version could still hold `editors`.
- **Why:** about 300 LOC of visionOS-only UI to maintain, and the chain already diverges from its siblings: `limitedTabs` omits Pdfs (a restored `selectedExtendedModule == .pdfs` would show a blank ZStack), every tab is mounted at once and hidden with opacity (ExtendedSplitBar.swift:58-68), the inspector ignores `canShowInspector` (ExtendedSplitWithDetailView.swift:40 vs SplitWithDetailView.swift:35-56), and `colorScheme`/`navigator` environments and `contentView(tab:)` (ExtendedSplitBar.swift:10-11,43-50) are unused.
- **Action:** confirm on a visionOS device that `.editors` is never selected, then delete the chain and its snapshot block (and the `.editors` case in the visionOS branch of `RouteDestinationView`); if it is kept, render only the selected tab and reuse the gated inspector binding.
- **Severity:** Medium   **Area:** RolePlayGameKit

### 9.7 SpaceViewer.swift is 1,212 lines with a 245-line `loadEntity`
- **Location:** Modules/SpaceRPG/Space/SpaceViewer.swift:16-1212 (`loadEntity` L549-~795)
- **What:** One file holds the shared-immersive sync engine (L207-434), window-to-immersive handoff (L435-546), entity loading plus gesture wiring (L549-~795), close-button attachment, and five private subviews.
- **Why:** Hard to reason about the platform `#if` matrix (visionOS window, visionOS immersive, iOS, macOS); the file's biggest function mixes parsing, interaction components, normalization and placement.
- **Action:** Split into `SpaceViewer+SharedPlacement.swift` (visionOS), `SpaceViewer+Handoff.swift` (visionOS), `SpaceViewer+Loading.swift` (extract `configureInteraction`, `normalizeScale`, `place` helpers out of `loadEntity`), and `SpaceViewerSubviews.swift`. Keep the stored properties in the main file.
- **Severity:** Medium   **Area:** SpaceRPG + TableRPG   **Status:** [OPEN since CODE_AUDIT_25 §9.12]

### 9.L Low-severity items (50)

- **9.8 Duplicated helpers** — Modules/CoreRPG/Controllable/SearchListController.swift:45-66 vs 126-147 — _CoreRPG Controllable/Import/Links_. Extract the folder branch to a shared function on `SearchControllable`; let `GenericGameController` adopt `ModuleGameControllable`'s defaults or move the helpers onto `ItemGameModel`.
- **9.9 Dead parameter and style-rule violations in link views** — Modules/CoreRPG/Links/DragOverlayViewModifier.swift:11,23-25 — _CoreRPG Controllable/Import/Links_. Remove `isMove` from the two overloads; use default padding; replace the `AnyView` returns with `some View`/generic or accept them as a documented erasure boundary.
- **9.10 CloudKitOperationCounter is a log-only counter with an unused parameter and a Task per save** — Modules/CoreRPG/Files/CloudDocumentController.swift:13-57 — _CoreRPG Files/Persistence/Model_. Replace with a `Mutex` counter (no Task, no actor hop), drop the `file:` parameter, log only the threshold crossing, or delete it.
- **9.11 LinkDataTransferable: eleven near-identical structs that ignore their module parameter** — Modules/CoreRPG/Model/LinkDataTransferable.swift:56-300 — _CoreRPG Files/Persistence/Model_. One generic struct (or a struct with a `contentType` per module) plus the `UTType` table; drop the dead parameter
- **9.12 Production Color.random lives in RainbowDebug.swift** — Modules/CoreRPG/Debug/RainbowDebug.swift:5-9 — _CoreRPG Files/Persistence/Model_. Move the single remaining `Color.random` out of Debug (or delete the ShapeStyle twin if unused) and delete RainbowDebug.swift.
- **9.13 Embedded-document mapping tables are duplicated and have already drifted (`.level` missing in sanitizer)** — Modules/CoreRPG/Foundry/FoundryVTTArchiveSanitizer.swift:284-304 vs Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift — _CoreRPG Foundry/Sheet_. Make one shared table (internal enum) used by both; add a test asserting the two agree.
- **9.14 `moveEntry(fromItemId:entryId:toItemId:afterEntry:)` parameter name promises an insertion position it does not honour** — Modules/CoreRPG/Sheet/SheetRootModel+ContextMenu.swift:60-70, call site :104-110 — _CoreRPG Foundry/Sheet_. Either pass the target entry id to the controller for positional insert or rename to `targetEntry`/drop the parameter.
- **9.15 Dead `rowColor(for:)` and the colour-scheme environment read in `SheetEntryView`** — Modules/CoreRPG/Sheet/SheetEntryView.swift:30 — _CoreRPG Foundry/Sheet_. Delete the method and the environment property.
- **9.16 Unused vendored Navigator features (about 500 LOC) still attached to every stack** — Modules/CoreRPG/Navigator/Protocols/Callback.swift — _CoreRPG UI 1_. Delete the listed files and members, the `scene:` initialisers and the modifier, and the `restorationKey` arguments [[OPEN since CODE_AUDIT_25 §9.18] (verified and made concrete)]
- **9.17 Duplicated add-link handler and unused environment value** — Modules/CoreRPG/LGViews/ItemRowsView.swift:13, 42-53 — _CoreRPG UI 1_. Move it into the list controller or a shared helper; remove the unused environment.
- **9.18 Preview fixtures compiled into release and a few fixed sizes** — Modules/CoreRPG/FileViews/ImportReviewPreviewData.swift — _CoreRPG UI 1_. Wrap the two fixtures in `#if DEBUG` (check the snapshot targets build Debug), use `@ScaledMetric` for the sizes and scale the fan radius with the button size.
- **9.19 Preview fixture injected in the production quick editor list** — Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:321 — _CoreRPG UI 2_. Remove the modifier.
- **9.20 Orphaned `OptionKeyDownModel` still installs a global key monitor on macOS** — Modules/CoreRPG/Extensions/PressedKeyDetection.swift:7-36 — _CoreRPG UI 2_. Delete the type, the AppModel property, the environment injection and the two test lines.
- **9.21 Dead leftovers inside the audited files** — Modules/CoreRPG/Rows/ColoredBackgroundRowModifier.swift — _CoreRPG UI 2_. Delete.
- **9.22 Detail screens duplicate helpers and use magic layout numbers** — Modules/CoreRPG/ItemDetail/ItemDetailRootView.swift:185-192,197-201 vs Modules/CoreRPG/ItemDetail/ItemDetailContentView. — _CoreRPG UI 2_. Pass the values down from Root, use `@ScaledMetric`.
- **9.23 Link drag and drop modifier: 11-way switch repeated four times and a mismatched default** — Modules/CoreRPG/ViewModifiers/LinkDragViewModifier.swift:37-50,66-79,93-106,189-202 and handlers 111-175,206-281 — _CoreRPG UI 2_. Table-drive the type mapping (a function returning the `Transferable` metatype/closure) and use one handler; make the drop default match the drag default (`LinkEntryData`) or disable the drop.
- **9.24 Share button is implemented twice** — Modules/CoreRPG/List/ShareListItemModifier.swift:41-71 vs Modules/CoreRPG/Views/SendFeedbackButton.swift:57-117 — _CoreRPG UI 2_. Make the feedback animation an option of one button view.
- **9.25 Oversized comment blocks narrate history** — Modules/GameRPG/Table3D/GameRenderer.swift:23-58, Modules/GameRPG/Table3D/GameTableView+VolumeSize.swift:7-60, Modules/G — _GameRPG Table3D_. Cut each to the current rule plus one line of why; move the ornament history into the commit log. [[OPEN since CODE_AUDIT_3dTable §9.6]

Not audited in this area: `TableSeatDice.swift` layout maths and `Tests/` internals (skimmed only); `RPGSharePlayController+TableCoordination.swift`, `WeatherTableEffect` and the MapRPG-side controllers the table calls (seams were read only to confirm contracts); visuals/gestures, TabletopKit synchronisation and attachment behaviour were reviewed from code only, nothing was run or built.]
- **9.26 Test-only and flag-disabled code kept in production** — Modules/GameRPG/Controller/LogGameController.swift:83-92 — _GameRPG Controllers_. Move the test-only members under `#if DEBUG` (as the neighbours are) and either delete the table-weather path or document the flag in GAME_CONNECTIONS.md with a removal date.
- **9.27 Dead observable state `stateText` and test-only counters in production types** — Modules/GameRPG/SharePlay/RPGSharePlayController.swift:82, Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifec — _GameRPG SharePlay/Network_. Delete `stateText` and its assignment (the `printState()` log line stays); mark the three counters `#if DEBUG` or leave with a comment that they are test affordances.
- **9.28 `GameNetworkController.stopGame` duplicates its two branches** — Modules/GameRPG/Network/GameNetworkController.swift:147-166 — _GameRPG SharePlay/Network_. Call `stopStreaming()` conditionally, then run one shared teardown sequence.
- **9.29 `reload()` has an if/else whose two branches are identical** — Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:320-328 — _GameRPG Views/Battle/Statistics_. Assign once, or restore the intended "only publish when changed" using `GameStatisticsSummary: Equatable`.
- **9.30 `lastCompletedSessionID` is written but never read** — Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:28, 292, 397 — _GameRPG Views/Battle/Statistics_. Remove it.
- **9.31 Preview fixtures are compiled into Release builds** — Modules/GameRPG/Preview/PreviewData.swift:18-113, Modules/GameRPG/Preview/MockData.swift:1-71 — _GameRPG Views/Battle/Statistics_. Wrap the Preview folder and the `preview()` extension in `#if DEBUG`; keep anything Tests need behind the same flag the test plan builds with, and build Release to confirm.
- **9.32 GameRoot.swift mixes six responsibilities in 809 lines** — Modules/GameRPG/Root/GameRoot.swift:1-809 — _GameRPG Views/Battle/Statistics_. Move the extensions to `GameRoot+Master.swift`, `GameRoot+Player.swift`, `GameRoot+Stop.swift`, `GameRoot+Demo.swift`, `GameRoot+Search.swift` (widen `private` to `fileprivate`-free internal where nee
- **9.33 Two views write the same `AppGameStateModel` fields on every game-state change** — Modules/GameRPG/Root/GameRootView.swift:14-26, Modules/GameRPG/Root/GameRootSetupView.swift:71-76 — _GameRPG Views/Battle/Statistics_. Keep the mapping in one place (a method on `GameRoot` or `AppGameStateModel`) and call it from one view.
- **9.34 Hard-coded slider ranges and icon sizes duplicate `MapEditorScaleRanges` / ignore Dynamic Type** — Modules/MapRPG/Map/GameToolBar.swift:252 — _MapRPG Map_. Use `MapEditorScaleRanges.pinScale/hexScale` in `GameToolBar`; use `@ScaledMetric` for the icon frames.
- **9.35 Unreferenced code with a latent bug: `EditController.replace(itemId:with:)`** — Modules/MapRPG/Controller/EditController.swift:521-533 — _MapRPG rest_. Delete.
- **9.36 Other unreferenced members** — Modules/MapRPG/Extensions/CGPoint+Relative.swift:1-9 — _MapRPG rest_. Delete the file and the three members.
- **9.37 Preview and mock fixtures compiled into Release** — Modules/MapRPG/BattleRound/BattleRoundPreviewData.swift — _MapRPG rest_. Wrap in `#if DEBUG` (or move to a `Preview/` folder) and keep the two GameRPG preview callers and the test under DEBUG; check that GameRPG's `#Preview` blocks still resolve. [[OPEN since CODE_AUDIT_25 §9.11] (fixtures compiled into Release)]
- **9.38 Preview and mock fixtures compile into Release** — Modules/AdventureRPG/Model/PreviewData.swift:17-42 and :70-195 — _AdventureRPG_. Wrap both files in `#if DEBUG` (the `#Preview` macros already compile out) and move them to Modules/AdventureRPG/Preview/; check that tests do not rely on them in Release.
- **9.39 `ViewController.diceSelection` is only referenced by a test** — Modules/AdventureRPG/Controller/ViewController.swift:48 — _AdventureRPG_. Delete it and its test line (and the Map/Table twins in their own audits).
- **9.40 Dead code and leftovers** — Modules/AudioRPG/Controller/ItemController.swift:41-48 — _AudioRPG_. Delete the first four and the unused environment value; remove `displayState` from `AudioEntryModel` or persist and merge it.
- **9.41 SearchController.result(item:) entry branch is unreachable** — Modules/CharacterRPG/Controller/SearchController.swift:42-45 — _CharacterRPG_. Delete the dead branch and the depth parameter, or, if entry search was intended for global search, call it for regular characters and add a test; fix the comment either way.
- **9.42 InlineRowViewer.diceSource mints a random entry id and can never remap** — Modules/CharacterRPG/View/InlineRowViewer.swift:35-37, 43-48 — _CharacterRPG_. Return `source` directly for the `entryId == nil` case and drop `diceSource`'s game lookup.
- **9.43 Preview and mock fixtures ship in Release and are duplicated** — Modules/CharacterRPG/Model/PreviewData.swift:10-270 — _CharacterRPG_. Wrap PreviewData/MockData in `#if DEBUG` per module (check that `#Preview` blocks and tests build) and build `preview` from `previewFixtures`.
- **9.44 Dead code** — `DiceModel.CompareValue.check(value:against:)` Modules/DiceRPG/Model/DiceModel.swift:184-197 — _DiceRPG_. Delete, or wire `check(value:)` in as part of the compare fix
- **9.45 DiceModel.swift is 712 lines** — Modules/DiceRPG/Model/DiceModel.swift — _DiceRPG_. Split along the existing MARK sections into `DiceModel.swift` (stored state and init), `DiceModel+Options.swift` (CompareValue, CoupFumbleOption, RerollOption), `DiceModel+Merge.swift` (merge/isSame/d [[OPEN since CODE_AUDIT_Dice §9.9]]
- **9.46 Preview fixtures still compile into Release** — Modules/DiceRPG/Model/PreviewData.swift:136-319 — _DiceRPG_. Give `DiceConfiguration.default` its own small default dice and gate the rest of the fixtures with `#if DEBUG`. [[OPEN since CODE_AUDIT_Dice §9.10]]
- **9.47 Dead code in the Generator module** — Modules/GeneratorRPG/BasicAI/Model/ChatMessage.swift:8 — _GeneratorRPG_. delete, or wire the settings to a UI on purpose; mark `public` helpers `internal`.
- **9.48 Prompt text for refine request is built with `String("...")` and is not localisable or bounded** — Modules/GeneratorRPG/View/SheetAIAssistantOverlayView.swift:151-157 — _GeneratorRPG_. drop the wrapper, trim the entry content before interpolation.
- **9.49 PdfRPG keeps private repairedUuid clones of the shared CoreRPG helper** — Modules/PdfRPG/Controller/DataController.swift:43-58 — _PdfRPG + PhotoRPG_. Delete the clones and call `repairedUuid(of:at: \.uuid)` like Photo. [[OPEN since CODE_AUDIT_25 §9.2]]
- **9.50 Dead environment and members in SelectionBar and ViewerRootView** — Modules/PdfRPG/Pdf/SelectionBar.swift:16-20 — _PdfRPG + PhotoRPG_. Remove the unused properties; delete or implement the Photo entry filter.
- **9.51 AsyncThumbnailLoadKey comment is stale, FileUrl equality no longer compares data** — Modules/PhotoRPG/Photo/AsyncThumbnail.swift:62-64 vs Modules/CoreRPG/Files/FileUrl.swift:64-75 — _PdfRPG + PhotoRPG_. Update the comment and use one key type for both views.
- **9.52 Dead members and unused environment reads in navigation views** — View/SplitNavigation.swift:52-54, View/SplitVisionNavigation.swift:79-81, View/SplitEditorNavigation.swift:96-98 — _RolePlayGameKit_. delete.
- **9.53 Unreferenced `EditController.reset(kind:itemId:entryId:)`** — Modules/RuleRPG/Controller/EditController.swift:168-176 — _RuleRPG + WeatherRPG_. Delete it.
- **9.54 Preview/mock fixtures compiled into Release** — Modules/TableRPG/Model/PreviewData.swift:1-342 — _SpaceRPG + TableRPG_. Wrap in `#if DEBUG` and move to a `Preview/` folder [[OPEN since CODE_AUDIT_Table §7.3]]
- **9.55 `GameController.entry(for:with:)` has no production caller** — Modules/TableRPG/Controller/GameController.swift:136-160 — _SpaceRPG + TableRPG_. Delete it and point the test at `matchingEntry`, or make `matchingEntry` the single shared function. [[OPEN since CODE_AUDIT_Table §5.8]]
- **9.56 Duplicated per-module window lists and widget helpers** — Sources/MasterRPG/Window/WindowViewerList.swift:25-77 — _Sources + Resources_. Share the content-widget helpers in one small type; collapse `supportedWidgetFamilies` to one array; table-drive the window lists where the root types allow (the typed `root` makes this hard, so low p
- **9.57 Dead code and CLAUDE.md style drift in the share extension and menus** — Sources/RPGShare/ModuleChooserView.swift:60-63 — _Sources + Resources_. Delete the unused members; extract the two view helpers into structs; use layout containers (`containerRelativeFrame`) instead of `size.width - 30`.

## 10. Cross-cutting recommendations and test gaps

Patterns worth applying repo-wide (each is backed by several findings in different areas):

1. **Gate preview and mock fixtures with `#if DEBUG`.** Fixtures that compile into Release were reported in AdventureRPG, CharacterRPG, DiceRPG, MapRPG, SpaceRPG/TableRPG, GameRPG, CoreRPG (UI 1 and 2) and `Sources/`. CLAUDE.md already says `Preview/` is `#if DEBUG`; the production Table outcome editor additionally depends on `Fake*` controllers (CoreRPG UI 2).
2. **Keep work and object creation out of `body`.** Dice instances (Character), `GeneratorController` (Generator), group editor controllers and Navigator tree mutations (CoreRPG UI 1), full-resolution image decodes (share extension), and repeated result/tree flattening (Dice, Table) all happen during view evaluation. Move them to `.task(id:)` or the owning model.
3. **One persistence rule for slider/stepper editors.** Weather sliders never save, the lightning sliders save on a per-event delta, while another CoreRPG editor saves on every tick. A shared "commit on edit end, debounce while dragging" helper would close all three.
4. **Make hot paths on large collections linear.** Hex maps (up to 20,000 cells) hit O(n²) room resets, per-room gesture views and repeated map fingerprints; Foundry imports hit quadratic scans, per-call regex compilation and macOS-sized memory ceilings on every platform; several `merge`/`update` helpers (Adventure, Character, Rule) are O(entries²). Cap or index once, and size limits per platform.
5. **Own every fire-and-forget `Task`.** Unowned or swallowed-error tasks appear in Audio, Pdf, Map, Rule and Character link controllers and in several views; give them an owner (model property or `.task`) and surface failures instead of `try?`.
6. **Test the state machines, not only the happy paths.** Untested risky logic named by the agents: game-mode file replacement, audio-session interruption handling, the map-change state machine and pin visibility in Table3D, table generation roll-state, Foundry importers, import review apply and the data-mutation lock, Validate/Repair locking, Generator window trimming and batch apply, and the share extension.
7. **Check module parity when one module gets a fix.** Several High/Medium bugs are a sibling of something already fixed elsewhere: Adventure export vs Character export (group entries), `TagController` vs `LinkRegisterController` (hydration guard), Weather vs the other modules (link source type, saving), PhotoRPG `Convert to JPEG` vs the shared image helpers.

### 10.1 Test gaps
- **Location:** Tests/ (no test covers `EditControllable.resetFile(url:)`/`writeFile` with `isGameMode == true`; `TagController.setup` failure path; `FolderEntryMerge` under a non-English locale; `ItemControllable.updates` racing an `addNew`)
- **What:** The risky paths of the findings above are untested (`Tests/PhotoRPGTests/FolderAuditPhotoTests.swift:121` is the only game-mode test touching files and covers moves).
- **Why:** Regressions in the shared core hit all 12 modules.
- **Action:** Add a CoreRPG test for file replacement in game mode (library item keeps a valid file), a tag hydration-failure test, and a locale-pinned folder merge test.
- **Severity:** Medium   **Area:** CoreRPG Controllable/Import/Links

### 10.2 Import apply, trash handling and the data-mutation lock live untested inside a view
- **Location:** Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:262-304 (`applyReview`), 372-451 (`finishReview`, `settleReviewFiles`, `apply`), 453-575 (`ImportMutationSession`)
- **What:** The 589-line view contains the whole review-apply pipeline (per item merge onto the changed library item, trash instead of delete, re-parenting of kept folder children, tag restore, folder repair), the file-settle step and the lock/save-deferral session as private statics and a private class; tests reference the view only through snapshot previews (Tests/CoreRPGSnapshotTests).
- **Why:** This is the path that writes users' library data and holds the `DataMutationCoordinator` lock. A regression (lock not released after cancel, deleted folder children lost, files not settled) cannot be caught by a unit test, and CLAUDE.md asks for view logic to be testable.
- **Action:** Move `ImportMutationSession` and the apply/finish/settle functions into an `ImportReviewApplyController` (stateless struct per the project's MVC) in CoreRPG/Controller or the same folder and cover: cancel while parsing, cancel while applying (release waits for the apply), apply when the lock is unavailable, deleted folder with kept children, reviewed file settle. The view then drops below 300 lines.
- **Severity:** Medium   **Area:** CoreRPG UI 1

### 10.3 Test gaps
- **Location:** Tests/GameRPGTests (TableSeatAssignmentTests, GameTableProjectionTests, BoardTextureRendererTests, TableSeatDiceTests, TableGuestDiceTests, TableDiceResultTests, TablePopoverSourceTests, GameTableControlTests, TableMessageFlowTests exist)
- **What:** Nothing covers `GameTableModel.performMapChange`/`loadMapPhoto` cancellation and failed-photo behaviour (the finding above), `PinPawn`/`syncPins` visibility filtering per role and display mode (GameTablePinPawnTests is visionOS only and, per CODE_AUDIT_3dTable 10.1, was already stale), the player-moves-own-pin rules in `canMovePin`, and the hidden-dice decision above.
- **Why:** These are the paths where regressions have occurred before (health colour, session pins, map reshow).
- **Action:** Extract the pin visibility filter from `syncPins` into a pure function and test it for player/GM/preview; test `canMovePin` and the map-change state machine with a stubbed photo loader.
- **Severity:** Medium   **Area:** GameRPG Table3D   **Status:** [OPEN since CODE_AUDIT_3dTable §10.1]

### 10.4 Test gaps on the risky controller paths
- **Location:** Tests/AdventureRPGTests (no hits for `duplicate(item`, `saveTablePlayers`, `tablePlayers(for`, group export, `update(itemId:entryId:` on a group entry, folder/collection duplication)
- **What:** `EditController.duplicate(item:)` with groups, folders and collections (EditController.swift:121-178), `GameController.saveTablePlayers` (GameController.swift:104-118, which rewrites link registers and mirrors into a loaded game copy), export of group/dice (see findings above), and `AdventureModel.merge` for folder entries are only covered indirectly or not at all (`GameControllerTests` ends at start/reset).
- **Why:** These carry data-loss potential (duplicate copies member ids, saveTablePlayers deliberately avoids a full library overwrite during a game).
- **Action:** Add tests: duplicate adventure with group entry (child copied, `groupId` and `adventureId` remapped), duplicate folder with sub-folder, saveTablePlayers during game mode (library updated, game copy session fields untouched, link register diffs), merge of two folder variants.
- **Severity:** Medium   **Area:** AdventureRPG

### 10.5 Audio-session state machine (interruption, route change, media-services reset) has no tests
- **Location:** Modules/AudioRPG/Controller/AudioPlayerSession.swift:201-247, Modules/AudioRPG/Controller/AudioController.swift:355-412, Modules/AudioRPG/Controller/MediaPlayerCoordinator.swift:94-117
- **What:** No test in Tests/ references `AudioPlayerSession`, `handleInterruption`, `resetMediaService` or `MediaPlayerCoordinator` (grep over Tests is empty); only the remote-command and transport layers are covered.
- **Why:** The interruption generation counters, `wasPlaying` hand-off, `isActive` bookkeeping, observer re-creation after a reset and the Now Playing throttle (`positionTolerance`) are exactly the code with await gaps and subtle ordering; the findings below were visible only by reading.
- **Action:** Make the delegate calls injectable (the delegate protocol already is) and test: began/ended with and without `.shouldResume`, a second `.began`, reset while playing; test `handlePlaybackChange` throttle with a fake clock.
- **Severity:** Medium   **Area:** AudioRPG

### 10.6 No tests for app-level routing, window routing, database setup, or Validate/Repair locking
- **Location:** Modules/RolePlayGameKit/Model/AppModel+Routing.swift:84-99 (external-route dedupe), :189-209 (layout restore); Route/WindowRouter.swift (per-role action lists, including recursion between `forwardToOtherWindow` and `routeToModule`); Model/DataBaseModel.swift:117-160; View/ValidateRepairView.swift:44-66; Route/RootURLHandler.swift
- **What:** the only RolePlayGameKit-named tests cover InAppController, the Foundry mapper and snapshots (grep of Tests/ for `WindowRouter`, `routeToModule`, `admitsExternalRoute`, `DataBaseModel`, `ValidateRepairController` finds nothing).
- **Why:** these are the most regression-prone cross-platform branches (macOS/visionOS/iOS conditionals, buffered routes, the error state that is never reset); regressions in this area have repeatedly shipped (CODE_AUDIT_18 §3.17, Since_3.0.1 §5.16).
- **Action:** add pure tests for `WindowRouter.actions(for:)` per role/platform, `admitsExternalRoute`, `DataBaseModel` error/recovery transitions with an injected persistence stub, and `startWithExclusiveDataAccess` refusing while the coordinator is held.
- **Severity:** Medium   **Area:** RolePlayGameKit

### 10.7 Test gaps for the risky Weather and Rule logic
- **Location:** Tests/WeatherRPGTests (no test touches `replace(with:)`/`weatherUpdate` semantics, `rainDirection` at zero angle, `linkRegisterModels`, or the `merge` stamp winner), Tests/RuleRPGTests (`mergeEntries` is tested for ordered input only; nothing for reordered or duplicate-named entries, `playerExport`, or the editor's save path)
- **What:** The behaviours behind the Weather link-register, stamp and slider findings, and the Rule reorder/duplicate-id case, have no test.
- **Why:** They are exactly the paths that regressed unnoticed.
- **Action:** Add tests with each fix: link source type survives `validateLinks`; a name-only `replace` keeps `weatherUpdate`; a reordered `mergeEntries` yields unique ids.
- **Severity:** Medium   **Area:** RuleRPG + WeatherRPG

### 10.L Low-severity items (14)

- **10.8 Persistence and file plumbing tests are missing for several risky pieces** — Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift:14-335 — _CoreRPG Files/Persistence/Model_. Extract the timestamp rules into pure functions with tests; add an in-memory store test for the change observer; test `ensureRemoteCache` with an injected downloader (the seam exists: `remoteFileDownl
- **10.9 Test gaps in the importers** — Tests/CoreRPGTests/Foundry — _CoreRPG Foundry/Sheet_. Add focused tests (with time limits) when fixing.
- **10.10 Test gaps (Sheet/Text)** — Tests/CoreRPGTests — _CoreRPG Foundry/Sheet_. Add focused table-driven tests with the fixes.
- **10.11 Test gap: no coverage found for the Simple session and EntryDataEditable defaults** — Modules/CoreRPG/Simple/SimpleSheetController.swift:73-112 — _CoreRPG UI 2_. Add tests for hidden entries on reorder/merge and three same-id links.
- **10.12 Test gap: Viewport geometry, theme contrast and numeric filter** — Modules/CoreRPG/Views/ViewportGeometry.swift — _CoreRPG UI 2_. Add golden-value tests (all four theme x contrast combinations keep the documented ratios; viewport resize/zoom anchors).
- **10.13 Test gaps** — Tests/GameRPGTests — _GameRPG Views/Battle/Statistics_. Add the four tests together with the fixes.
- **10.14 Test gaps** — Tests/MapRPGTests — _MapRPG Map_. Add tests for hex+room lookup, wrap insert midpoint, and a timing guard for `resetEntries` with a few thousand cells.
- **10.15 Test gaps** — Tests/MapRPGTests — _MapRPG rest_. Add the three tests alongside `MapPinVisibilityTests` / `MapWallRedactionTests`.
- **10.16 Test gaps** — Tests/CharacterRPGTests — _CharacterRPG_. Add the owner-order test with that fix; add the portrait assertion to `characterDataControllerCreatesTrimmedValue`.
- **10.17 Test gaps** — Tests/DiceRPGTests — _DiceRPG_. Add the five tests together with the fixes.
- **10.18 Untested risky logic: window trimming, overflow recovery, batch apply, prompt assembly** — Tests/GeneratorRPGTests — _GeneratorRPG_. extract `applyResult` and the window selection into pure functions and unit-test them; test `OneShotGate` for open-before-wait and double open.
- **10.19 Test gaps for the file-backed paths** — Tests/PdfRPGTests, Tests/PhotoRPGTests — _PdfRPG + PhotoRPG_. Add tests for convert (extension case, size cap), non-image data to `resetPhoto(data:)` returning false, and a fake `FileUrlDataController` for `pdfDocument(for:)` cancellation.
- **10.20 No tests for the SpaceViewer-adjacent state machine and scanner reset logic** — Tests/SpaceRPGTests — _SpaceRPG + TableRPG_. Extract the pure folder-cleanup decision (`hasModelFiles`, keep Models) and the finish/cancel transitions into types testable on the simulator; add `consume` tests when the awaiting check is added.
- **10.21 Test gap: share extension, content-widget snapshot and widget timeline have no tests** — Sources/RPGShare/ItemProviderImporter.swift — _Sources + Resources_. Move `ItemProviderImporter`'s pure static helpers and the name-derivation into a module (CoreRPG/PhotoRPG) and add tests for oversize, undecodable and zero-length data, and for `ContentWidgetSnapshot`

## 11. What was NOT audited

- Runtime behaviour: nothing was run, built (by the agents) or tested on a device. Findings marked "unverified" depend on device behaviour (iCloud eviction, visionOS entities, haptics, share-extension memory, Siri/intent routing).
- Third-party/vendored code beyond the Navigator folder's usage, SPM `RPGTabletopGameContent`, Metal (none present), the Xcode project file, schemes and build settings.
- Localization wording, App Store metadata, and Core Data model/migration files beyond what the persistence agent read.
- Per-area skipped files, as listed by each agent:

  - **CoreRPG Controllable/Import/Links:** Not audited in this area: view-level behaviour of FileViews/ItemList/EntryEditor (outside the listed folders), `SearchControllable+Inspector.swift` and `ViewControllable.swift`/`SheetControllable.swift`/`GenericItem*` (skimmed only), `LinkRegisterModel` consumers in other modules, the 12 module-specific `merge` implementations, runtime behaviour (nothing was run or built).
  - **CoreRPG Files/Persistence/Model:** Not audited in this area: Model files that are plain view models or value types read only by name or skimmed (SearchModel, ListDisplayModel, ItemSelectionModel, ChildEntryModel, TagFilterList, SearchResult, OpenFileWindowModel, GenerateMapAction, MapActions, SheetNumberLimit and similar small ones, about 1.5k LOC); the CloudKit schema and `.xcdatamodeld` files; runtime behaviour on a device (iCloud eviction, Spotligh
  - **CoreRPG Foundry/Sheet:** Not audited in this area: Settings theme views beyond a read of ThemeSettingsView/ThemeMiniature (decorative, no findings); Sheet leaf button views and preview fixtures (SheetEntry*Button, SheetEntryReview* views, SheetContextMenuView, SheetEntryConvertToGroupView) were only skimmed with pattern greps; Tips structs in MasterRPGTips+*.swift (declarative TipKit definitions); runtime behaviour of any finding marked unve
  - **CoreRPG UI 1:** Not audited in this area: the smaller FileViews review rows (Single*/ImportReview* row and badge views, about 25 files of 20-120 LOC), `SingleReviewModels.swift`/`ImportReviewModels.swift` and `ImportReviewSplitView`/`ImportReviewSheetDetailView` (skimmed by grep only for tasks, force unwraps and `ForEach` identity, no hits); LGViews `ThumbnailRowEmptyView`, `TwoLineTagView`, `TagDisplayView`, `MenuSelectionButtonVie
  - **CoreRPG UI 2:** Not audited in this area: - Fake model fixtures other than the ones named above (`FakeItemModel`, `FakeEntryModel`, `FakeEditController`, `FakeItemRootController`, `FakeLinkController`, `FakeLinkRegisterController`, `FakeSheetController`, `FakeImageCacheControllable`, `TestFixtures`, `ImportControllable+TestSupport`): skimmed only, they are preview/test doubles and no production use besides the Simple dependency was 
  - **GameRPG Table3D:** Not audited in this area: `TableSeatDice.swift` layout maths and `Tests/` internals (skimmed only); `RPGSharePlayController+TableCoordination.swift`, `WeatherTableEffect` and the MapRPG-side controllers the table calls (seams were read only to confirm contracts); visuals/gestures, TabletopKit synchronisation and attachment behaviour were reviewed from code only, nothing was run or built.
  - **GameRPG Controllers:** Not audited in this area: Modules/GameRPG/Network (transport, routes, throttles), SharePlay, Root, BattleRound, Table3D and the views (other areas); the module-side controllables the controllers call (MapRPG `networkMapUpdate`/`createMapGameData`, DiceRPG) were read only where a finding needed them; the files listed as not opened in the first paragraph.
  - **GameRPG SharePlay/Network:** Not audited in this area: SharePlayJournalPublication (types), RPGSharePlayController+TableCoordination, +VisionOSTemplate, GameActivityAssociation, GameShareStateModel, RPGActivity, PhysicalIdentityDenylist, BrowserRowView (UI), Network/GameJoinCodeModel's sync init Keychain reads (already open as a decision in the Shareplay audit), the TabletopKit/visionOS code paths (not buildable here), and runtime behaviour on d
  - **GameRPG Views/Battle/Statistics:** Not audited in this area: Modules/GameRPG/GameViews files not opened (OverlayMasterTabBar, OverlayPlayerTabBar, OverlayToolBar, MasterOverlayMenu, PlayerOverlayMenu, MasterSideMenu, PlayerSideMenu, MasterModuleWindow*, GameMainTab*, GameWindow*, GameScreenOrnaments, GameScreenLayer, GameTopOcclusion, IOSGameOverlay*, LogMessage*/LogRowsSection/LogSections, SharingOptionsSection, AttachmentSection, OnlyGameView, OnlyP
  - **MapRPG Map:** Not audited in this area: `Modules/MapRPG/Model`, `Controller`, `View` (only the pin action view and the parts of `EditController` that the Map folder calls), `BattleRound`, `Intent`; the 3D table consumers of `GameToolBarSession`; `ViewportModel`/`ViewportGeometry` internals in CoreRPG; runtime behaviour on device (no builds or profiling were run).
  - **MapRPG rest:** Not audited in this area: the Map/ folder (separate audit); view-layout details of `MapPinView` and canvas gestures; GameRPG-side callers of the MapGameStorable protocol beyond the grep checks above; runtime behavior (nothing was built or run); String-catalog completeness of the area's localization keys.
  - **AdventureRPG:** Not audited in this area: Resources (string catalogs, Core Data model file), runtime behaviour on devices (all findings are from reading; none reproduced), performance measurements, and the CoreRPG generics (GenericItemController, EntryDataEditable, FolderEntryMerge) beyond the parts quoted above.
  - **AudioRPG:** Not audited in this area: runtime behaviour on device (AirPlay routes, interruption recovery, Now Playing UI, visionOS ornaments); the CoreRPG pieces AudioRPG delegates to (`GenericEditController`, `GenericImportController`, `FileUrlDataController`, `ItemEntityQuery`, `ModuleLinkRootView`, `IntentGameContext` internals); GameRPG-side audio messaging (covered by CODE_AUDIT_Game_Photo_Audio and CODE_AUDIT_Audio2); the 
  - **CharacterRPG:** Not audited in this area: Resources/ string catalogs (translations), the CoreData model file, and CoreRPG generic implementations that the module delegates to (`GenericFolderListController`, `GenericImportController`, `EntryDataEditable` defaults, `ItemEntityQuery`); Calculator regex semantics beyond what the existing tests pin; App Intents behaviour at runtime (already covered by CODE_AUDIT_AppIntents*.md); runtime 
  - **DiceRPG:** Not audited in this area: the DiceRollerWidgetExtension sources under Sources/DiceRollerWidget (only the module-side `DiceConfiguration`/snapshot types were read), the Core Data model file and CloudKit schema, the localisation catalogs, snapshot tests, `Resources/` art assets, and the Quick Dice slot model and views that live outside Modules/DiceRPG (only the DiceRPG-side `QuickDiceRollButton`/`QuickDiceValueButton`/
  - **GeneratorRPG:** Not audited in this area: Route/, Menu/, Preview/MockData/PreviewData, Root list/detail views (DetailListView, SaveView, GeneratorRootView), Controller stubs (EditController, LinkController, ViewController, SheetController), GeneratorEntity/query indexing, Localization strings, and runtime behaviour of FoundationModels (nothing was run).
  - **PdfRPG + PhotoRPG:** Not audited in this area: Localizable.xcstrings contents, Core Data model files (RPGPdf/RPGPhoto .xcdatamodel), MockData.swift / PreviewData.swift fixtures, Menu/*Commands.swift, DetailEditorView / DetailListView / DetailFolderListView layout details in PdfRPG, Photo DetailFolderListView, the CoreRPG shared infrastructure (FileUrlDataController, GenericEditController, ImageCacheControllable) beyond the cited lines, r
  - **RolePlayGameKit:** Not audited in this area: the second half of Import/Foundry/FoundryVTTDomainMapper+Documents.swift (journals, tables, cards, adventures), FoundryVTTDomainMapper+Rules.swift and the folder-creation half of +Indexes.swift (skimmed by grep only: no force unwraps, no unchecked indexing); the Foundry reader/sanitizer types themselves live in CoreRPG; no runtime verification of any platform-specific path (macOS, visionOS, 
  - **RuleRPG + WeatherRPG:** Not audited in this area: visual/behavioural tuning of the particle math (cloud drift, star flicker, lightning bolt geometry, storm physics) beyond the bugs above; the Core Data models (`Rule.xcdatamodeld`, `Weather.xcdatamodeld`) and the localization catalogs' translations; the Foundry importer in CoreRPG (`FoundryVTTImportReader` and models, covered by the CoreRPG audits); RealityKit rendering was read but not run;
  - **SpaceRPG + TableRPG:** Not audited in this area: SpaceRPG Resources (Core Data model, localization catalogs, tutorial videos), Menu/Route files, the onboarding/tutorial/help views in Record/ (OnboardingStateMachine, OnboardingTutorialView, HelpPageView, TutorialVideoView, PlayerView beyond a skim), the second half of SpaceManagementIntents/SpaceEntity (covered by the AppIntents audits), TableRPG Resources, Menu/Route files, TableGeneration
  - **Sources + Resources:** Not audited in this area: the content of the module `Commands`/`Root` views referenced from the window lists, the localized string catalogs (AppShortcuts/InfoPlist/Localizable xcstrings), AccessoryDiceView.swift (skimmed for accessibility only), the RPGResources packages and Resources/RPGTabletopGameContent, asset catalogs, and the pbxproj-level target membership beyond the settings quoted above. Core Data store open

## 12. Verification

Each High finding was re-checked by the lead by opening the cited lines. "Confirmed" means the code does what the finding says when read; none was reproduced at runtime.

- **§5.3** — `Modules/AdventureRPG/Controller/ExportController.swift:63-128` — the BFS closure follows `photoId`, `tablePlayers`, `specialCategory` children and links in entry content, but never `entry.adventureId`; `Modules/CharacterRPG/Controller/ExportController.swift:62-76` does add `entry.valueId`. `GroupableEntryEditing.swift:36-52` shows a group entry's content is only a copy of the description. Confirmed as an asymmetry; not checked whether another expansion step adds group items before this closure runs.
- **§5.1** — `EditControllable+File.swift:166-181` creates the new file, calls `reset(fileUrl:itemId:)` (default `forceSave: false`, `EditControllable.swift:143-148`), then deletes the replaced file when `replaced == .delete` and `isFileUsedElsewhere(…, excluding: itemId)` is false; `writeFile` repeats this at 276-279. Confirmed that the delete does not depend on where the reference was saved; that a game-mode save leaves the library item pointing at the old URL rests on the project's game-copy design and the agent's trace, not on a run.
- **§5.4** — `DieModel` is a struct (`DieModel.swift:7`); `DiceBag.swift:13-21` builds the catalog once as `static let`, so each die has one fixed id; `DiceBag.swift:56-60` passes it to `EditController.add(die:)`, which only does `editModel.dice.append(die)` (`EditController.swift:14-19`). Remove/lookup by `die.id` then hits the first copy. Confirmed.
- **§5.5** — `GameController+DiceResult.swift:37` sets `result.checked = sumResult > 0`; `compareOption`/`compareValue` are used only in `maxValuePerDice` (guarded by `addDiceEvery > 0`, lines 147-155) and in `compareText` display (170). `CompareValue.check` has no caller in Modules, Sources or Tests (grep). Confirmed.
- **§5.2** — `Modules/CoreRPG/Text/TableRollRange.swift:12-23`: for "96-00", `values` is [96, 0], so the range is `min…max` = `0...96`; rolls 97-100 match no row. Confirmed.
- **§5.6** — `WeatherModel.swift:209` uses `ItemRowModel(itemId: id, typeId: .adventure)` as the source; grep finds no `linkRegisterModels` override in `Modules/WeatherRPG`, so the protocol default applies. Confirmed; the claim that every `validateLinks` wipes the registration was taken from the agent's trace of `resetLinkRegister`.
- **§5.7** — `WeatherConditionEditor.swift:54` binds `Slider(value: $model.time)` directly to the stored model; `WeatherStormEditor.swift:~100-107` does the same for rain angle/intensity; the only `editController.save` calls and `onChange` handlers in these views are for cloud thickness, storm type and rain direction. Confirmed; because other edits save the whole model, a slider change is persisted only when a later edit triggers a save.
- **§5.8** — `WeatherThunderEditor.swift:145-170`: `SignificantChangeModifier` compares `oldValue` and `newValue` of a single `onChange` event against `threshold = 1`; a slow drag delivers many sub-threshold deltas, so nothing is saved. Confirmed (the slider's step and range were not checked).
- **§6.1** — `FoundrySystemPackageReader.swift:456-476`: `resolveTemplate` guards cycles with a path `stack` but has no memo, depth cap or cancellation check, and recurses once per entry of `templates`; a template listing the same parent twice per level gives 2^n calls. Confirmed by reading. Needs the user to import a hostile package, so it is a robustness/DoS issue, not a remote exposure.

Downgraded during review: the Table3D "dice ignore the share options" finding (now Medium, §6.4).
