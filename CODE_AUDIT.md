# MasterRPG Code Audit

Generated 2026-11-18. Scope: every folder of the 15 modules in `Modules/` (1,935 Swift files, about 216k LOC), audited by four parallel read-only agents (CoreRPG; GameRPG; MapRPG + RolePlayGameKit + SpaceRPG + DiceRPG; the nine smaller modules). `Sources/`, `Tests/`, extension targets and `Resources/` were not audited. No directory is excluded by `CLAUDE.md`.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code was changed by this audit. The previous audit (`Docu/CODE_AUDIT_26.md`) is the baseline: items it lists as fixed are not repeated, and items still open are marked "still open from audit 26 §x".

**Method and limits.** Nothing was built or run. The container has no `xcodebuild`, so there is no compiler-warning list, and concurrency findings come from reading code. Findings marked "unverified" are reasoned from code only. The two High findings were re-checked by the author against the cited lines (§12). Raw per-module agent output (182 findings before grouping) was consolidated by root cause into the numbered findings below.

**Totals:** 0 Critical, 2 High, 32 Medium, and the rest Low (many Low items are grouped by root cause).

---

## 1. Executive summary

Top items, in priority order. No Critical findings survived verification.

1. **[High] Imported Foundry RollTables lose their ranges** — §5.1 — `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Documents.swift:403-418`. Ranged tables (for example d20 with 1-5, 6-15, 16-20) resolve to the wrong row or no row.
2. **[High] Observable image cache has a count limit only and no memory-pressure handling** — §7.1 — `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:247-300`. Browsing many large photos/maps can pin gigabytes and end in a jetsam kill.
3. **[Medium/Security] Proxy group events skip the size, timestamp and plausibility checks** — §6.1 — `Modules/GameRPG/Controller/MasterController+ProxyRouting.swift:36-113`. A lower-trust peer can poison the host's ordering baseline and push unvalidated payloads into SharePlay.
4. **[Medium/Security] Inbound byte budget is never tripped by a flood of tiny frames and costs quadratic main-actor time** — §6.2 — `Modules/GameRPG/SharePlay/SharePlayInboundByteBudget.swift:18-45`.
5. **[Medium/Security] Remote-download SSRF guard inspects the connected address only after the request was sent** — §6.3 — `Modules/CoreRPG/Files/GuardedRemoteDownload.swift:12-27,64-75`.
6. **[Medium/Security] Private campaign content is left in the temporary directory** — §6.4 — `Modules/CoreRPG/Files/FileUrlDataController.swift:366-374,481-531` and three more writers.
7. **[Medium] Game dice rows re-render each other (N x N)** — §7.3 — `Modules/CharacterRPG/View/EntryListDiceRow.swift`. Cause of the slow folder open reported earlier; mitigated on branch `claude/fix-dice-row-invalidation`, not yet on this branch.
8. **[Medium] Hex-map hot paths are quadratic at 20,000 cells** — §7.4 — `Modules/MapRPG/Controller/GameController+Metadata.swift:359-388`, `EditController.swift:300-303`.
9. **[Medium] "Convert to JPEG" can orphan the original file, replace a durable file with in-memory data, or clear the photo** — §5.2 — `Modules/PhotoRPG/Controller/EditController.swift:22-44`.
10. **[Medium] Reset Data / Import / Validate are not blocked while a game runs** — §5.3 — `Modules/RolePlayGameKit/View/SettingsView.swift:93-103,187-213` (unverified whether Settings is reachable during a game on every platform).

---

## 2. Quick wins (≤30 min each)

- **Fix the typo "exisiting"** in the empty-folder hint — `Modules/CoreRPG/LGViews/ItemRowsView.swift:69`, `Modules/CoreRPG/Resources/Localizable.xcstrings:2560`.
- **Swap the inverted "Roll" / "Roll & Share" titles** — `Modules/DiceRPG/View/DiceInline.swift:45,113-115` (verify against the strings catalog first).
- **Set `pdfUnavailable` when a PDF item has no file** — `Modules/PdfRPG/Root/ViewerRootView.swift:97-108`.
- **Remove the Morse sound on drag-enter** and return the real accept result — `Modules/CoreRPG/Files/FileDropDelegate.swift:21-45`.
- **Use `sanitizedFoundryText` for token pin names** — `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Scenes.swift` (`tokenPin`).
- **Compute the passcode check value only inside the debug log** — `Modules/GameRPG/Network/ListenerManager.swift:175-176`.
- **Hoist regexes to static lets** in the page-text limiter — `Modules/GeneratorRPG/BasicAI/Engine/UntrustedPromptText.swift:33,46-49`.
- **Delete the unreferenced helpers** listed in §9.2 (about 150 LOC).
- **Mark `participantsDescription` ids `.private`** and drop emoji from log text — `Modules/AudioRPG/Controller/AudioListenerCoordinator.swift:41,48,57`.
- **Rename `termineType` to `determineType`** (3 sites) — `Modules/CharacterRPG/Controller/EditController.swift:304,318`.
- **Replace `ProgressView().scaleEffect(1.5)` with `.controlSize(.large)`** — six sites, see §8.9.
- **Add `@ObservationIgnored` to controller bookkeeping** in `Modules/GameRPG/Controller/MasterControllerModel.swift:5-6,59-75`.
- **Set `showExporter = true` instead of `toggle()`** — `Modules/CoreRPG/FileViews/ExportProgressPanelView.swift:172`.
- **Clamp the lightning step** to 0.1 s like the storm — `Modules/WeatherRPG/Weather/Lightning.swift:96-98`.

---

## 3. Concurrency

### 3.1 Audio session is recorded as active even when activation failed
- **Location:** `Modules/AudioRPG/Controller/AudioPlayerSession.swift:105-111,186-194`
- **What:** `setActive(true)` logs and swallows its error, so the awaited change returns normally and `isActive` becomes true.
- **Why:** After a failure (phone call, another app holds the session) every later `play()` skips activation; playback stays silent until an interruption event resets the flag.
- **Action:** Make `setActive` report success, set `isActive` only on success, retry on the next play.
- **Severity:** Medium

### 3.2 Audio interruption-resume and removal bypass the ordering that the rest of the session relies on
- **Location:** `Modules/AudioRPG/Controller/AudioPlayerSession.swift:254-263` (resume calls `setActive()` directly instead of `enqueueSessionChange`); `Modules/AudioRPG/Controller/AudioController.swift:228-248` (`removeAudio` bumps `playbackGeneration` only when playing)
- **What:** One path skips the serialized change queue; the other leaves a pending `preparePlay` valid for a removed track.
- **Why:** A queued deactivate can run after the resume and leave the session inactive while the flag says active; a pending play can start on a cleared player.
- **Action:** Route the resume through the queue; bump the generation unconditionally when the removed id is current.
- **Severity:** Low

### 3.3 Statistics buffer has no cap and spawns a flush task per event once full
- **Location:** `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:49-52,152-168,188-200`
- **What:** `maximumBufferedEvents` only triggers a flush; every further `record` while the buffer is full starts another flush task, and the array grows during store failures.
- **Why:** A burst (a join with many map updates) creates dozens of chained tasks and unbounded memory.
- **Action:** One `isFlushScheduled` flag; drop the oldest events past a hard cap and log the count.
- **Severity:** Low

### 3.4 Networking deadline and reset tasks are untracked
- **Location:** `Modules/GameRPG/Master/MasterNetworkController+Listener.swift:86-96`; `MasterNetworkController+Browser.swift:119-130`; `MasterNetworkController.swift:187-201,227-251`
- **What:** Handshake and dial deadline tasks keep no handle and outlive `stopStreaming()`; `resetConnections()` defers `clearAllPending()` and the cancel loop to two fire-and-forget tasks, and `beginHosting` starts a new listener immediately after.
- **Why:** A late `clearAllPending()` can in theory wipe a new session's pending registration; shutdown order rests on scheduling luck.
- **Action:** Store the tasks per connection id and cancel them in `removeConnection`/`resetConnections`; await the reset inside one tracked task before hosting.
- **Severity:** Low

### 3.5 Unstructured and fire-and-forget tasks without owners (grouped)
- **Location:** `Modules/MapRPG/Root/MapRootModel.swift:37-46` (map content send chain never cancelled on game stop); `Modules/MapRPG/Controller/GameController.swift:379-405` (`createMapGameData` retry loop never checks cancellation); `Modules/DiceRPG/Controller/GameController+PlayerDice.swift:120-129` (`shareRoll` task can resurrect dice after reset); `Modules/GameRPG/Root/GameRoot.swift:351-379` (unbounded serial action chain, see §7.16); `Modules/GeneratorRPG/Controller/GeneratorController.swift:170-214,467-489` (after the 5 s predecessor timeout a new request runs on the same session; helper task never cancelled); `Modules/CoreRPG/Persistence/DuplicateRowOrder.swift:51-53` (`Task.detached` ignores cancellation); `Modules/SpaceRPG/Space/SpaceViewer+Loading.swift:27,59-82,325-345` (no staleness check after the load `await`; close-button handler spawns a Task per frame); `Modules/MapRPG/Map/MapEditorCanvasGestures.swift:206-212` (pencil reset Task per stroke may discard the next stroke, unverified)
- **What:** Each starts work with no owner or cancellation path.
- **Why:** Work continues after the game stops or the view is gone; stale results can be applied.
- **Action:** Keep handles in the owning model, cancel them from the game-stop/teardown path, and check `Task.isCancelled` before applying results. Use `runOffCallerExecutor`/`@concurrent` instead of `Task.detached`.
- **Severity:** Low

### 3.6 Fixed-delay `Task.sleep` orders UI steps by time
- **Location:** `Modules/RolePlayGameKit/Model/AppModel.swift:472-475`; `Modules/RolePlayGameKit/View/DestinationReadyView.swift:49-51`; `TabRootView.swift:28-31`; `ValidateRepairView.swift:214-219`; `Modules/RolePlayGameKit/Model/AppModel+Routing.swift:116-149`; `Modules/PdfRPG/Pdf/PdfWrapperView.swift:68-71`
- **What:** `try? await Task.sleep` swallows cancellation (a cancelled task still navigates) and sequences steps by guess.
- **Why:** Fragile on slow devices; the 2-second "sheet still up" fallback masks a dismissal bug.
- **Action:** Drive each step from the state it waits for (route ready, scene phase, page-changed notification).
- **Severity:** Low

### 3.7 Object-capture scanner state machine runs in `didSet` with re-entrant assignments
- **Location:** `Modules/SpaceRPG/Record/AppDataModel.swift:52-60,354-393,434-482`; shot list: `AppDataModel.swift:451-453`, `CaptureFolderManager.swift:56-80`
- **What:** `reset()` assigns `state` from inside the `didSet`; correctness depends on two flags set before and consumed inside. The shot list loads in an untracked task with file I/O on the main actor and swallowed errors.
- **Why:** Fragile ordering; the "Captured images" counter can show 0.
- **Action:** Replace with an explicit `transition(to:)` method; list the folder in a `@concurrent` function and await it before reconstruction.
- **Severity:** Low

### 3.8 `nonisolated(unsafe)` statics on `DiceEntityQuery` (still open from audit 26 §3.11)
- **Location:** `Modules/DiceRPG/Intent/DiceEntity.swift:164,190`
- **What:** `properties` and `sortingOptions` opt out of strict concurrency.
- **Why:** No reason to; `AdventureEntityQuery` was already converted.
- **Action:** Convert as in `AdventureEntity`.
- **Severity:** Low

### 3.9 `BatteryMonitor` leaves battery monitoring on when released without `onDisappear`
- **Location:** `Modules/GameRPG/GameViews/BatteryView.swift:92-100,111-135,140-153`
- **What:** The monitor count is balanced only by an explicit `stopMonitoring()`; the class has no deinit cleanup.
- **Why:** A scene close leaves monitoring enabled for the process.
- **Action:** Add isolated-deinit cleanup.
- **Severity:** Low

---

## 4. API modernity

### 4.1 `UINavigationController` extension overrides `viewDidLoad` as a category (still open from audit 26 §4.6, new evidence)
- **Location:** `Modules/CoreRPG/Extensions/NavigationController+Back.swift:6-31`
- **What:** `override viewDidLoad` in an extension of an Objective-C class replaces UIKit's implementation; the gesture delegate methods return `viewControllers.count > 1` for every recognizer pair of every navigation controller in the process, including system sheets.
- **Why:** Undefined override semantics plus an app-wide gesture change; `CLAUDE.md` asks to avoid UIKit.
- **Action:** Remove the override; if the pop gesture must work with a hidden back button, handle it per controller and re-test on iOS 26 without it.
- **Severity:** Medium

### 4.2 English text is written into imported and generated items
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Documents.swift:312-326,414-415,433-437,521,530,543,550,561-562`; `FoundryVTTDomainMapper+DiceAndValues.swift:77-78`; `Modules/RuleRPG/Model/RuleModel+FoundryFactory.swift:116-122,140-155,172-174,239-259,312-316,356`
- **What:** Labels such as "Range:", "Weight:", "Drawn:", "Source (never executed)", "**Target:**" are plain Swift literals stored in the user's library.
- **Why:** German/Thai users get English structural text inside adventures, tables and rules that cannot be translated afterwards.
- **Action:** Use `String(localized:bundle:)` when generating, or store structured kinds and localize at render time.
- **Severity:** Medium

### 4.3 Localization gaps
- **Location:** `Modules/CoreRPG/Persistence/CloudKitAccountController.swift:22-37` (six status titles via `.localizedString` are not in the catalog); `Modules/CoreRPG/Resources/Localizable.xcstrings` (14 live keys without Thai, 456 unreviewed machine translations, six stale keys); `Modules/CoreRPG/Files/FileUrlViewModel.swift:1-31` ("Filename Unknown", "Path not set"); `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:84,106,117,206` and `GameStatisticsDashboardView.swift:286-294` (raw `localizedDescription` shown); `Modules/SpaceRPG/Record/ReconstructionProgressView.swift:37-48` (still open from audit 26 §8.35)
- **What:** Strings that bypass the catalog or show framework error text.
- **Why:** Mixed-language UI and unlocalizable text.
- **Action:** Return `LocalizedStringResource`/`String(localized:bundle:)`, add the missing keys, map errors to localized messages and log the underlying error.
- **Severity:** Low

### 4.4 Small API-hygiene items (grouped)
- **Location:** `Modules/CoreRPG/AppModels/AppSettingsModel.swift:55-211` (14 hand-written `didSet` write-backs; `value(forKey:)` KVC on `UserDefaults`); `Modules/CoreRPG/Stores/DebouncerModel.swift:16-34` (`Double` seconds next to a `Duration` API); `Modules/CoreRPG/Extensions/Image+AKImage.swift:112-141` (hard-coded 3x pixel scale); `Modules/CoreRPG/Parser/RegularExpressionParser.swift:6-45` (unbounded regex cache; bad pattern hidden in release); `Modules/GeneratorRPG/BasicAI/Engine/FoundationManager.swift:14-46` and five other direct `SystemLanguageModel.default.availability` checks (availability snapshot goes stale)
- **What:** Older or inconsistent API choices.
- **Why:** Extra edit sites per setting, wrong accessor, wasted pixels on 2x devices, stale AI availability.
- **Action:** Use `object(forKey:)` and a keys table; take `Duration`; take the pixel scale from the caller; cap the regex cache; read availability live through one helper.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Imported Foundry RollTables lose their ranges, so range tables cannot be rolled
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Documents.swift:389-421` (range only written as content text at 403-418); consumer `Modules/TableRPG/Controller/TableGenerationController.swift:247-258` with `Modules/CoreRPG/Text/TableRollRange.swift:14-34`
- **What:** `mapRollTable` sets the table to `.dice` but keeps the entry name as the result text and writes the Foundry `range` only as "Range: 1-5" in the content. The Table module reads ranges from the entry name and otherwise falls back to `entries[result - 1]`. Nothing parses "Range:".
- **Why:** A d20 table with three ranged rows rolls 17 and indexes entry 16, which does not exist; a roll of 7 returns the 7th row or a wrong one. Every imported ranged RollTable is silently wrong.
- **Action:** When the result has a numeric `range`, set the entry name to the selector (`"low-high"` or `"n"`) and keep the result text in the content; add a mapper test for a 3-row d20 table.
- **Severity:** High

### 5.2 "Convert to JPEG" can orphan the old file, replace a durable file with in-memory data, or clear the photo
- **Location:** `Modules/PhotoRPG/Controller/EditController.swift:22-44`; `Modules/CoreRPG/Files/FileUrl.swift:156-160`; `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:16-80`
- **What:** `convert` swaps the reference without disposing the replaced file; `createNewFileUrl` is called without `requireDurableStorage`, so a failed write yields a data-only `FileUrl` that replaces the stored one; a nil result is passed to `reset(fileUrl:)` and clears the photo; an encode failure returns silently.
- **Why:** Storage leak per conversion, possible loss of the only durable copy on a write error, and a button that silently does nothing.
- **Action:** Require durable storage, bail out and report on nil, route the replacement through the same disposal path as `resetFile`, show an error when no data could be produced.
- **Severity:** Medium

### 5.3 Reset Data, Import and Validate are not blocked while a game runs
- **Location:** `Modules/RolePlayGameKit/View/SettingsView.swift:93-103,187-213`; `Modules/RolePlayGameKit/Model/AppModel.swift:339-347`; `Modules/CoreRPG/Import/DataMutationCoordinator.swift`
- **What:** The exclusion token serialises bulk writers against each other but never checks `AppGameStateModel.isGameRunning`.
- **Why:** Clearing the database or repairing links while `ItemGameModel` references the same items leaves the live game with items that no longer exist, and `resetData` removes persisted games the GM may be resuming. Whether Settings is reachable during a running game on every platform was not verified.
- **Action:** Disable the three actions and make `begin()` refuse while a game is running, with an explanatory footer.
- **Severity:** Medium

### 5.4 Space transform broadcast loop decides once whether a network exists
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer+SharedPlacement.swift:183-193`; started from `SpaceViewer.swift:198-200`
- **What:** `sendTransformLoop` returns immediately when `networkActions == nil`, and the task is keyed only on `hasLoaded`.
- **Why:** If a game or SharePlay session starts after the immersive viewer opened, pose changes are never broadcast for that viewer's lifetime (visionOS; unverified on device).
- **Action:** Include `networkActions != nil` in the task id, or wait instead of returning.
- **Severity:** Medium

### 5.5 Percentile (d10 + d10) totals ignore the modifier and break under "reorder dice"
- **Location:** `Modules/DiceRPG/Controller/GameController+DiceResult.swift:65-90,203-227`
- **What:** The percent branch returns `ten * 10 + one` without `item.modifier`, while the inline text and compare check use it; the tens/ones dice are taken from the reordered list, which sorts by result.
- **Why:** A d100 roll with a bonus shows and shares the unmodified total; with reorder on, 3 and 7 can read as 73 or 37. Whether the editor prevents either combination is unverified.
- **Action:** Add the modifier in the percent branch and read the percent dice from the item's own order.
- **Severity:** Medium

### 5.6 Battle-copy removal never removes the game dice (still open from audit 26 §8.2, in part)
- **Location:** `Modules/CharacterRPG/Controller/GameController.swift:262-282,25-28`; `GameController+Dice.swift:74-77`
- **What:** `removeBattleCharacterCopies` nils the id maps but never calls `removeGameDice`; `resetGameDiceId(entryId:)` is unreferenced.
- **Why:** Each battle copy leaves one dice item per dice-linked entry in the dice game store until the game is reset.
- **Action:** Call `removeGameDice` for every id dropped from the map; delete the unused function.
- **Severity:** Medium

### 5.7 Several roots leak game dice or items (grouped)
- **Location:** `Modules/DiceRPG/Controller/GameController.swift:190-209` (virtual dice for table rolls never removed); `Modules/AdventureRPG/Controller/GameController.swift:71-77` (`focusDice` allocates a new dice per call)
- **What:** Dice created for a roll or focus are never released.
- **Why:** The game model and dice overlay grow for the length of the game.
- **Action:** Reuse one virtual dice per table occurrence/side count or remove it after sharing; remember and reuse the focus dice id.
- **Severity:** Low

### 5.8 Small logic errors in Game / Table / Pdf / Dice (grouped)
- **Location:** `Modules/GameRPG/Root/GameRootSetupView.swift:71-73` (missing `isStopping` guard that `GameRootView` has; unverified on device); `Modules/GameRPG/Table3D/GameBoard.swift:92-101` with `GameTableModel+MapSync.swift:117-123,192-195` (failed texture applied as gray plane and recorded as rendered); `Modules/TableRPG/Controller/TableGenerationController.swift:245-260` (positional fallback even when other rows are range-labelled); `Modules/PdfRPG/Root/ViewerRootView.swift:97-108` (item without a file shows a permanent spinner); `Modules/DiceRPG/View/DiceInline.swift:45,113-115` (Roll / Roll & Share titles look inverted, unverified); `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:475-494` (deferred timer not re-armed for an earlier deadline)
- **What:** Each is a narrow incorrect state or message.
- **Why:** Gray table that never retries, wrong table row instead of "no match", permanent spinner, misleading button text, up to about 3 s extra retry delay.
- **Action:** Fix per site as described in the quoted locations: guard on `isStopping`, treat texture failure as unapplied, restrict the positional fallback to tables without ranges, set the unavailable state, swap the titles, re-arm the timer.
- **Severity:** Low

### 5.9 Foundry import edge cases (grouped)
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Documents.swift:497-512` (adventure entry order follows Set iteration); `FoundryVTTDomainMapper+Scenes.swift` (`tokenPin` skips sanitizing; `initialLevel` precondition at 62-63 on untrusted data); `FoundryRuleImportModel.swift:226-229,253,260,297,315,324` (early exits leave `.committing` with no message)
- **What:** Random entry order across runs, raw token names, a trap on malformed packages in a future caller, a stuck commit screen.
- **Why:** Spurious merge diffs on re-import, markup on the map, crash risk, user stuck without explanation.
- **Action:** Sort the reference set, sanitize pin names, return optional from `initialLevel`, set `commitError` and return to review on every early exit.
- **Severity:** Low

### 5.10 Persistence edge cases (grouped)
- **Location:** `Modules/CoreRPG/Persistence/CoreDataChangeObserver.swift:55-61` (`precondition` traps on a second setup, also in release) and `84-101` (fabricated random UUIDs for unresolved ids); `CloudKitCoreDataPersistenceController.swift:42-49,110-113` and `CoreDataPersistenceController.swift:99-105,150-160` (store-folder creation failure is overwritten by the load result); `CloudKitCoreDataPersistenceController.swift:263-267` (`-allowCloudKitSync` honoured in release)
- **What:** Programmer assertions that become crashes, wrong error reported, a test switch that changes durability.
- **Why:** A recovery path can crash; a file-system error is shown as nothing or as a corrupt database.
- **Action:** Cancel and replace the old subscription; return early after folder failure; omit unresolvable ids; gate the argument under `#if DEBUG`.
- **Severity:** Low

### 5.11 Misc low-severity bugs (grouped)
- **Location:** `Modules/CharacterRPG/Controller/EditController.swift:287-297` (`addItemAsGroup` returns an item id where an entry id is expected); `Modules/CharacterRPG/Intent/ChangeCharacterValueIntent.swift:86-87,113` (whole amounts only; silent fallback to first match); `Modules/CharacterRPG/Model/ValueEntryModel.swift:97` ("Group" compared as English literal); `Modules/CharacterRPG/View/AdditionalEntryRow.swift:27,56` (random entry id defeats `==`); `Modules/MapRPG/Controller/GameController+Pins.swift:26` (random pin colour per recreate); `Modules/DiceRPG/Controller/DataController.swift:131-146` (die ids regenerated on every load); `Modules/WeatherRPG/Weather/Lightning.swift:96-98` (unclamped step); `Modules/WeatherRPG/Weather3D/WeatherTableEffect.swift:386-416` (failed texture remembered for the process); `Modules/CoreRPG/Controllable/SearchControllable.swift:332-360` (XOR row ids can collide); `Modules/CoreRPG/Tips/MasterRPGTips.swift:176-210` (debounce instead of throttle); `Modules/CoreRPG/Files/FileDropDelegate.swift:21-45` (sound on every drag, always reports success); `Modules/CoreRPG/FileViews/ExportProgressPanelView.swift:79-93,172` (failed export leaves its file; `toggle()`); `Modules/AudioRPG/Model/AudioModel.swift:187-191` (filter ignores tags/entries); `Modules/AudioRPG/Model/PlaylistItem.swift:40-44` (unplayable files accepted); `Modules/PdfRPG/Pdf/PdfWrapperView.swift:103-171,156` (stale coordinator `parent`, silent 1,000-match cap); `Modules/PhotoRPG/Controller/ItemController.swift:49-72` (drop import stops at the first failing type); `Modules/AdventureRPG/Controller/ExportController.swift:30-35` (`preconditionFailure` before setup)
- **What:** Independent small defects, each described in the quoted location.
- **Why:** Wrong ids/colours, lost user intent, silent partial results, avoidable crashes.
- **Action:** Fix per site; most are one- to five-line changes. Derive pin colours and die ids deterministically, return optionals instead of invented ids, clamp the step, honour `includeEntries`/tags, return empty and log instead of trapping.
- **Severity:** Low

---

## 6. Security

### 6.1 Proxy group events skip the size, timestamp and plausibility checks that player events get
- **Location:** `Modules/GameRPG/Controller/MasterController+ProxyRouting.swift:36-50,83-113`; `PlayerController+SendMessages.swift:149-177`; contrast `Modules/GameRPG/Model/GameNetworkModel+Shape.swift:103-113` and `MasterController+NetworkStoreDelegate.swift:101-115`
- **What:** A player's dice/pin/Space event must pass `isPlayerGroupEvent` (role, 256 KiB cap, timestamp). A proxy has role `.proxy`, so only shape is checked; the host then applies the event, takes the proxy's timestamp as the last-wins baseline, and publishes it to SharePlay before validation.
- **Why:** A proxy joins with the four-digit code, so it is a lower-trust peer than the host, yet a far-future timestamp can lock the host's Space transform baseline and an oversized or implausible payload is applied locally and relayed.
- **Action:** Run the same shape gate for proxies, clamp the relayed timestamp, check dice plausibility before recording, and add tests with an oversized payload and a future timestamp from a proxy.
- **Severity:** Medium

### 6.2 LAN/SharePlay inbound byte budget keeps one record per frame and is never tripped by small frames
- **Location:** `Modules/GameRPG/SharePlay/SharePlayInboundByteBudget.swift:18-45`; `Modules/GameRPG/Network/GameNetworkControllerModel.swift:159-165`; `GameNetworkController+MasterDelegate.swift:31-34`
- **What:** `admit` appends a record per frame, then filters every sender, reduces the history and copies the array, on the main actor. The limit is bytes only (512 MiB / 60 s).
- **Why:** A flood of tiny frames from one connected peer costs quadratic main-actor time and unbounded memory without ever reaching the byte limit.
- **Action:** Use fixed time buckets or a running sum with an expiry queue; add a per-connection frame-rate ceiling and drop or disconnect offenders; share one implementation across LAN, Messenger and Journal-load budgets.
- **Severity:** Medium

### 6.3 Remote-download SSRF guard checks the connected address only after the request was made
- **Location:** `Modules/CoreRPG/Files/GuardedRemoteDownload.swift:12-27,64-75`
- **What:** The download starts for any URL that looks public; the connected addresses are inspected in `didFinishCollecting` and a private one only discards the file. Cleartext `http` is allowed by the URL check. The URL can come from an imported package.
- **Why:** A package can make a player's device send a GET to a LAN or loopback address (router admin, local service) via DNS rebinding or redirect; the response is discarded but the side effect is done.
- **Action:** Resolve and refuse private addresses before connecting (connect through Network.framework with the vetted address), keep the post-hoc check as defence in depth, refuse `http` for imported references.
- **Severity:** Medium

### 6.4 Private campaign content is left in the temporary directory
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:366-374,481-531`; `Modules/CoreRPG/Intent/EntitySummaryExport.swift:44-50`; `Modules/CoreRPG/FileViews/GameBundleBrowserModel.swift:100-107`; `Modules/CoreRPG/FileViews/ExportProgressPanelView.swift:79-93`
- **What:** Staged file copies (up to 256 MiB), summary PDFs, downloaded bundles and failed exports are written to `URL.temporaryDirectory` and nothing removes them (`PeerFileDataStore.removeTemporaryCopy` only matches `peer-`). The summary-PDF doc comment says the text "must not outlive the export".
- **Why:** The OS empties the folder only when it chooses, so large duplicates accumulate and the stated privacy promise is not kept.
- **Action:** Add one launch-time and game-end sweep owned by CoreRPG (by prefix/age), delete the summary PDF and bundle after use, remove `saveUrl` on every non-finished export outcome.
- **Severity:** Medium

### 6.5 `PdfContentExtractor` sends PDF page text without the untrusted-material fence (still open from audit 26 §6.9, in part)
- **Location:** `Modules/GeneratorRPG/BasicAI/Providers/PdfContentExtractor.swift:89,102,144-174`
- **What:** The summary analyzers fence the text; the block-extraction path interpolates `page.text` unfenced, adds no untrusted-material instruction and does not strip markers.
- **Why:** A hostile PDF page can steer the extracted blocks; impact is limited to the review screen, but the module now has two standards.
- **Action:** Fence each page, add the instruction, and add a test next to `UntrustedPromptTextTests`.
- **Severity:** Medium

### 6.6 Smaller trust-boundary and privacy items (grouped)
- **Location:** `Modules/GameRPG/Network/GameProtocol.swift:55,144-179` (`baseAddress!` x2 on the wire parser; length cast can trap at 4 GiB; unused `Codable` conformance); `Modules/GameRPG/Network/ListenerManager.swift:175-176` (passcode check value computed eagerly in release, discloses 4 bits of the code in private logs); `Modules/DiceRPG/Widget/DiceConfiguration.swift:193-222,234-247` (full dice snapshot including notes stored in the App Group on every roll); `Modules/CoreRPG/Widget/ContentWidgetSnapshot.swift:44-63` (item names written to shared defaults for the Lock Screen, undocumented); `Modules/AudioRPG/Controller/AudioListenerCoordinator.swift:41,48,57` (participant ids logged `.public`); `Modules/PdfRPG/Controller/EditController.swift:107-129` (AI sections applied uncapped, with link markup); `Modules/GeneratorRPG/BasicAI/Providers/PdfPageTextReader.swift:14-16` (`PDFDocument` marked Sendable on an unenforced "private document only" rule)
- **What:** Narrow gaps at trust boundaries.
- **Why:** Robustness of the most security-sensitive parser, GM notes copied into a shared container, session metadata at public privacy level, model output turned into live links.
- **Action:** Clamp the length and guard the pointer; compute the check value inside the debug log; persist only the compact widget snapshot; mark ids `.private`; cap sections and strip link markers; document or enforce the document rule.
- **Severity:** Low

---

## 7. Performance

### 7.1 Observable image cache has a count limit only and no memory-pressure handling
- **Location:** `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:247-300` (`imageCountLimit = 120`); fed by `Modules/CoreRPG/LGViews/CachePhotoView.swift:82-93` (`highResolution` defaults to true) and `Modules/PhotoRPG/Photo/AsyncThumbnail.swift:155-160`; decode cap `Modules/CoreRPG/Extensions/Image+AKImage.swift:230,296-304`
- **What:** Besides the `NSCache`-backed `ObjectCache` (256 MiB cost cap), every opened full-resolution image is also held in a plain strong dictionary evicted only by count. Images are decoded immediately and may reach 8192 px (about 268 MB square, about 48 MB for 12 MP). A search of `Modules` and `Sources` finds no memory-warning or memory-pressure handling.
- **Why:** The byte cap in `ObjectCache` is bypassed because the observable copy is a second strong owner; 120 x 48 MB is about 5.7 GB in the worst case, which ends in a jetsam kill on phones and iPads. Reasoned from code, not measured.
- **Action:** Give the cache a byte budget (pixels x 4, LRU until under budget), drop full-image entries when the detail view disappears or on memory pressure, keep thumbnails in the count-limited layer.
- **Severity:** High

### 7.2 `ObservableImageCache` is one observable dictionary per kind, so every thumbnail load invalidates every visible row
- **Location:** `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:255-264,278-296`; readers `Modules/CoreRPG/LGViews/ThumbnailRowPhotoView.swift:47-49`, `CachePhotoView.swift:42-46`
- **What:** Observation tracks the property, not the key; each `setThumbnail` re-runs the body of every row that read any thumbnail. `touch` also does a linear `removeAll` per set.
- **Why:** N rows loading N thumbnails cause N x N body evaluations; large Photo grids hitch while thumbnails stream in.
- **Action:** One small `@Observable` box (or version counter) per id; an ordered structure for the LRU.
- **Severity:** Medium

### 7.3 Game dice rows re-render each other when one creates its dice
- **Location:** `Modules/CharacterRPG/View/EntryListDiceRow.swift`; `Modules/CharacterRPG/Controller/GameController.swift:10-29`; `GameController+Dice.swift:51-72`; shared model `Modules/CoreRPG/Controllable/ItemGameModel.swift:16-22`
- **What:** After audit 26 §8.2 moved dice creation out of `body` into a per-row `.task`, each task writes the shared game item/dice dictionaries, which invalidates every dice row (N writes x N rows). Each row body also does a linear `gameItem(for:)[entryId]` lookup.
- **Why:** Opening a folder or sheet with many dice entries slowed the folder and game views.
- **Action:** Branch `claude/fix-dice-row-invalidation` splits the row so only a cheap outer body re-runs and the heavy dice view is skipped while its id is unchanged. A further step is to create a folder's dice in one batched write or make the id maps `@ObservationIgnored` with a per-entry observable box. Profile with Instruments before and after.
- **Severity:** Medium

### 7.4 Hex-map hot paths do a linear id search per entry (quadratic at 20,000 cells)
- **Location:** `Modules/MapRPG/Controller/GameController+Metadata.swift:359-388`; `GameController+Sync.swift:28-34`; `Modules/MapRPG/Controller/EditController.swift:300-303`; `Modules/MapRPG/Model/MapModel.swift:293-297`
- **What:** `updateMap` scans `entries` once per token of the state message (every entry, hex cells included); `validateBeforeSave` calls the linear subscript per entry.
- **Why:** About 2x10^8 UUID comparisons on the main actor per state message and per editor save on large hex maps; the message itself is about 900 KB.
- **Action:** Build an id-to-index dictionary once per apply/validate; send only entries that differ from the default or send a delta.
- **Severity:** Medium

### 7.5 `MapEditor` observes the whole `entries` and `mapPins` arrays
- **Location:** `Modules/MapRPG/Map/MapEditor.swift:114-122`
- **What:** `.onChange(of:)` reads the full CRDT-wrapped arrays in the body; any room or pin change invalidates the whole editor and triggers an element-wise compare.
- **Why:** Toggling one room costs a full body pass plus an O(n) compare (unverified by profiling).
- **Action:** Observe a version counter or update stamp from the session instead.
- **Severity:** Medium

### 7.6 Whole Foundry mapping pass runs on the main actor, including the privacy sanitize
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift:176-199,214,250-258`; caller `FoundryRuleImportModel.swift:183-189`
- **What:** The mapper is `@MainActor`; the constructor runs the sanitizer (deep filtered copy) before the first checkpoint, and yielding every 16 units only interleaves.
- **Why:** A world with tens of thousands of documents stalls the UI and any running game.
- **Action:** Move sanitize and pure projection steps into `@concurrent` functions over `Sendable` value types; build `@MainActor` models in batches.
- **Severity:** Medium

### 7.7 Remote sync fetches one row per id, and a deletion batch materialises every row
- **Location:** `Modules/CoreRPG/Controllable/SyncDataControllable.swift:75-150`; `Modules/CoreRPG/Persistence/CoreDataController.swift:234-239,479-507`; `CoreDataSnapshotPersistable.swift:60-64,85-87`
- **What:** Each inserted/updated id is one `fetch(id:)`; `fetchIds()` fetches managed objects to return a `Set<UUID>`.
- **Why:** A first CloudKit import arrives as thousands of ids and causes thousands of sequential main-actor hops; one remote delete costs a full-module row load.
- **Action:** Add a chunked `fetch(ids:)`; make `fetchIds()` a dictionary-result fetch of `uuid` only.
- **Severity:** Medium

### 7.8 Sheet search filters the whole tree synchronously on every keystroke
- **Location:** `Modules/CoreRPG/Sheet/SheetRootModel.swift:146-166`; `SheetRootModel+Search.swift:29-34`; `SheetModel.swift:90-118`
- **What:** Each change runs `localizedStandardContains` over every entry's name and description on the main actor, plus a full state-save pass when a search starts. List searches debounce and run asynchronously; the sheet does not.
- **Why:** Rule compendia and generated tables with thousands of entries stall typing.
- **Action:** Debounce through the existing `DebouncerModel`/`ListSearchTiming`, match on a snapshot off the main actor, apply visibility in one pass.
- **Severity:** Medium

### 7.9 A static cache pins the full board photo and its bitmap after the 3D table is gone
- **Location:** `Modules/GameRPG/Table3D/GameTableEntities.swift:26-42`; `GameBoard.swift:130-134,187`; `GameTableModel.swift:248-257`
- **What:** `GameTableImage.cachedBoardImage` is a `@MainActor static var` cleared only by `Board.clearMap()`; leaving the table does not clear it.
- **Why:** The strong source keeps the full photo alive and the converted image is up to 64 MB for the rest of the app run; with two macOS table windows the single slot is shared.
- **Action:** Hold the cache on the table model or board, or clear it in the model's deinit; store only the `CGImage` plus a key.
- **Severity:** Medium

### 7.10 One RealityKit hit entity per map entry and an O(entries) pass on every pin sync
- **Location:** `Modules/GameRPG/Table3D/GameTableProjection.swift:114-149,262-270`; `GameTableEntities.swift:398-450`
- **What:** `syncRooms` creates a `RoomHitArea` (collision, input target, hover, accessibility) for every entry including hex cells and re-walks all of them on every pin sync.
- **Why:** A hex map yields thousands of accessibility elements and collision shapes and a sync that touches each although one pin changed.
- **Action:** Skip `syncRooms` when only pins changed (room signature); use one board-level hit area for hex maps; give accessibility only to named rooms.
- **Severity:** Medium

### 7.11 Every wire message becomes a CloudKit-synced statistics row
- **Location:** `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:110-168`; `Controller/GameStatisticsController.swift:22-60,156-172`; `Controller/GameStatisticsDataController.swift:128-196`; model contents (all entities `syncable`)
- **What:** `record(_:)` runs for every incoming and outgoing `GameNetworkModel`, acks and map updates included, each becoming a row of about 25 attributes.
- **Why:** A four-hour game produces tens of thousands of CloudKit-synced rows; every reload fetches them all.
- **Action:** Persist only the kinds the dashboard reads and aggregate byte/module/network counters per session; keep message-level rows in `#if DEBUG` or a non-synced store.
- **Severity:** Medium

### 7.12 Every `SpaceViewer` re-evaluates on every transform of every item
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:189-197`; `Modules/SpaceRPG/Controller/GameController.swift:17,58-73`
- **What:** The `onChange` argument reads the observable `transformStates` dictionary, which changes at 20 Hz while anyone drags.
- **Why:** Needless body passes for unrelated items (unverified by profile).
- **Action:** A per-item observable object, or an ignored dictionary plus a per-item stamp.
- **Severity:** Medium

### 7.13 Game audio availability list awaits one file check per item, sequentially
- **Location:** `Modules/AudioRPG/Controller/GameController+Playback.swift:249-272`; `GameController.swift:100-110`
- **What:** `hasDownloadedDataWithoutFetching` is awaited one by one inside a `@MainActor` function.
- **Why:** With hundreds of items (and iCloud-evicted files) the list sent when a player joins takes the sum of all checks.
- **Action:** Check in bounded parallel groups or cache availability per file version.
- **Severity:** Medium

### 7.14 Every playlist track is copied in full to the temp folder before it can play
- **Location:** `Modules/AudioRPG/Controller/AudioTrackLoader.swift:67-106,128-138`
- **What:** Even local, downloaded files are duplicated into `temporaryDirectory/AudioTracks`; the folder is wiped once per launch.
- **Why:** 100+ MB tracks double disk use and delay the first note; if the OS purges the folder mid-run the stored URL is dead and nothing re-copies it.
- **Action:** Hand `AVURLAsset` a coordinated/bookmarked URL for local files; copy only evicted or remote files; revalidate before `replaceCurrentItem`.
- **Severity:** Medium

### 7.15 Two full-transcript token counts run around every chat turn
- **Location:** `Modules/GeneratorRPG/BasicAI/Engine/ConversationEngine.swift:82-91,110-116,158-168,192-195`; `TranscriptTokenCounting.swift:65-97`
- **What:** The whole transcript is tokenized through the model before sending and again after the response; the sliding-window search adds more calls.
- **Why:** Latency grows with the transcript on every message.
- **Action:** Reuse the post-response count for the pre-send check and call the model-backed count only near the threshold.
- **Severity:** Medium

### 7.16 Lower-severity performance items (grouped)
- **Location:** `Modules/GameRPG/Root/GameRoot.swift:351-379` (unbounded serial action chain, no latest-wins coalescing); `Modules/GameRPG/Controller/MasterControllerModel.swift:5-6,59-75` (100 MB package cache in observed properties); `MasterController+DiceMessages.swift:41,45,60` (a dice roll decoded up to five times); `Modules/CoreRPG/Files/FileUrlDataController.swift:20-22,48-56` (game-memory list re-encoded on every append); `Modules/CoreRPG/ItemList/ItemDataModel.swift:93-130` (linear lookups on delete/rename); `Modules/CoreRPG/Links/LinkRegisterController.swift:205-216` (no fetch index on the link table); `Modules/CoreRPG/Widget/ContentWidgetSnapshot.swift:44-63` (O(n) casts per edit burst); `Modules/CoreRPG/Cache/ImageCacheController.swift:25-28` (shared disk namespace, no size cap, alpha lost in JPEG thumbnails); `Modules/CoreRPG/App/AppExitNotificationsViewModifier.swift:17-55` (full save once a minute per window); `Modules/CharacterRPG/Model/Calculator.swift` and `ValueEntryModel.swift:139-203` (Locale allocated and value string re-split per access); `EditController+Repair.swift:16-23` (copies every character to read entries); `Modules/WeatherRPG/Weather/StormView.swift:46-70` (rain re-seeded on every slider tick); `Modules/GeneratorRPG/BasicAI/Engine/UntrustedPromptText.swift:33,46-49` and `FoundationModelInputLimiter.swift:14-57` (regex per line, `count` per page); `PdfContentExtractor.swift:89-103` (wasted prewarm); `Modules/PhotoRPG/Photo/ImageViewer.swift:34-138` and `AsyncThumbnail.swift:19-103` (geometry and load keys rebuilt per body), `InlineImporterView.swift:97-118` (full original loaded as `Data`); `Modules/RuleRPG/Model/RuleEntryTree.swift:171-225` (child map rebuilt per removed group); `Modules/TableRPG/Controller/TableGenerationController.swift:285-335` (occurrence count per link); `Modules/DiceRPG/Controller/GameController+DiceResult.swift:239-246` (AVPlayerItem per roll); `Modules/MapRPG/Extensions/UIImage+Crop.swift:6-33` (unbounded rotated context)
- **What:** Each is a bounded inefficiency that matters at large item counts or during bursts.
- **Why:** Hitches during imports, slider drags, joins and bulk deletes.
- **Action:** Coalesce latest-wins actions, decode once, batch persistence, add the index (lightweight migration), cache static values, derive keys inside `.task(id:)`, load picker data to a file and check declared size first.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 `applyIf` changes view identity when its condition flips
- **Location:** `Modules/CoreRPG/ViewModifiers/IfModifier.swift:11-17`; dynamic sites `Modules/CoreRPG/Sheet/TableSheetView.swift:20-22`, `Buttons/ImageOverlayButton.swift:56-61`, `LinkRenderer/LinkHighlightTextView.swift:31`, `Sheet/SheetView.swift:127,201-206,280`, `Buttons/InlineEditorView.swift:147`; about 20 call sites in CoreRPG and 10 elsewhere
- **What:** The if/else produces conditional content, so flipping the condition replaces the subtree and resets `@State`, scroll position, focus and tasks.
- **Why:** Toggling the search bar rebuilds the whole scrolling sheet and loses scroll position; `ImageOverlayButton` is recreated when it becomes enabled.
- **Action:** Use value-based modifiers for the dynamic sites, leave the constant ones, document the restriction (consider renaming to `applyIfStatic`).
- **Severity:** Medium

### 8.2 Game-bundle browser creates a `WebPage` and starts a network load on every parent re-evaluation
- **Location:** `Modules/CoreRPG/FileViews/GameBundleBrowserView.swift:12`; `GameBundleBrowserModel.swift:26-33`; `ImportInformationSection.swift:28-30`
- **What:** `@State private var model = GameBundleBrowserModel()` evaluates its initial value each time the struct is created; the initializer creates the page and calls `load`. The sheet content is rebuilt whenever the parent body runs (it takes a closure).
- **Why:** Each rebuild allocates a WebKit page and fires a request while the sheet is open.
- **Action:** Create the model lazily with `LazyState`, or hold it in the presenting view and start the load on first appearance.
- **Severity:** Medium

### 8.3 `AnyView` remains at about 54 sites in the per-module `ViewController`/`EditController` surface (still open from audit 26 §3.10, §8.1, §9.9; kept on purpose)
- **Location:** `Modules/{Character,Audio,Table,Weather,Photo,Adventure,Pdf,Map,Space,Dice}RPG/Controller/ViewController.swift`; `TableGenerationViewController.swift`; `Modules/CharacterRPG/Controller/EditController.swift:143-145`; `Modules/MapRPG/Controller/EditController.swift:121-122`; `Modules/CoreRPG/ItemList/EntryDataEditable.swift:52-55`; `Modules/CoreRPG/Navigator` mapped views
- **What:** `ViewControllable` requires `AnyView` return types.
- **Why:** `CLAUDE.md` says avoid `AnyView` unless required; here it is a protocol-design choice that loses diffing.
- **Action:** Decide once: redesign with associated types or `@ViewBuilder` closures, or document the exception in `CLAUDE.md`.
- **Severity:** Low

### 8.4 Icon-only buttons instead of `Button(title, systemImage:)`
- **Location:** `Modules/MapRPG/Map/EditMapToolBarButtons.swift` (11 sites), `GameToolBar.swift` (9 sites; line 214 has no label), `ChooseMapPinsButton.swift:34`, `HexMapScaleView.swift:47`, `View/DisplayConfigEditor.swift:173`; `Modules/GeneratorRPG/View/BatchTextSummaryExtractionView.swift:143-150`; `Modules/PhotoRPG/View/DropChooseView.swift:41-47`, `CarouselPhotoItemView.swift:85`; `Modules/CharacterRPG/View/DropChooseView.swift:46`; `Modules/AudioRPG/Audio/AudioPlayPauseButton.swift:25-30`, `SharingActionView.swift:96-98`, `MenuBarAudioPlayerView.swift:136`
- **What:** About 30 buttons use `label: { Image(systemName:) }` with only an accessibility label; the "Refresh Shared Map" button hides itself with opacity instead of being removed.
- **Why:** Menus, Voice Control and tvOS focus labels miss the title.
- **Action:** `Button(title, systemImage:)` or `Label` with `.labelStyle(.iconOnly)`; replace the opacity hack with a conditional.
- **Severity:** Low

### 8.5 Hard-coded padding, spacing and frame sizes (still open from audit 26 §8.21)
- **Location:** about 220 sites: MapRPG 14, SpaceRPG 21, DiceRPG 43, RolePlayGameKit 6, the nine small modules about 96 padding/spacing plus 32 frames (for example `Modules/AudioRPG/Audio/AudioPlayerVolumeControl.swift:37-62`, `Modules/PdfRPG/Pdf/PdfContentView.swift:115`), GameRPG about 107, `Modules/GameRPG/GameViews/GameRootViewer.swift:222-223,342`
- **What:** Fixed numbers instead of system defaults or `@ScaledMetric`.
- **Why:** `CLAUDE.md` rule; accessibility sizes do not scale.
- **Action:** Replace opportunistically with defaults where visually equal.
- **Severity:** Low

### 8.6 Fixed-size controls ignore Dynamic Type
- **Location:** `Modules/CoreRPG/Editors/TextIntEditor.swift:39`; `EntryEditor/EntryContentEditor.swift:20`; `LGViews/ItemHeaderEditorView.swift:397`; `LGViews/GroupEditorView.swift:256,269`; `EntryEditor/TextEditorLinkView.swift:23`; `Settings/ThemeSettingsView.swift:46`; `LGViews/GridLabelView.swift:30-45`; `Modules/DiceRPG/Game/Detail/DieViewerView.swift:81-106`, `DiceRoll.swift:18-36`; `Modules/SpaceRPG/Space/SpaceViewerSubviews.swift:283-303`; `Modules/PdfRPG/Pdf/PdfContentView.swift:90-115`
- **What:** Absolute widths, heights and icon sizes. The PDF thumbnail strip also sizes its frame by page count (a 1,000-page PDF gets a 100,000 pt frame).
- **Why:** Truncated values and cramped editors at accessibility sizes.
- **Action:** `@ScaledMetric`, flexible frames with `fixedSize`/line limits; let `PDFThumbnailView` size itself.
- **Severity:** Low

### 8.7 Static member lookup and helper methods instead of view structs
- **Location:** `Modules/GameRPG/GameViews/QuickDice/QuickDiceSlotView.swift:37,129-130`; `OverlayGameLayout.swift:169,183`; `Modules/GameRPG/SetupViews/*` (OTP field, setup buttons, backdrop, start views); `BattleRound/BattleParticipantColumn.swift:67`; `Search/SearchListView.swift:68,97,108`; `GameViews/GameRootViewer.swift:155,176`; `GameJoinCodeRevealButton.swift:39`; `Modules/DiceRPG/Game/Detail` (`Circle()`)
- **What:** `RoundedRectangle(cornerRadius:)`/`Circle()`/`Capsule()` instances where `.rect(cornerRadius:)`, `.circle`, `.capsule` exist; parameterised `@ViewBuilder` methods where small `View` structs belong.
- **Why:** `CLAUDE.md` rules; structs also give SwiftUI a diffing boundary.
- **Action:** Replace when the files are touched; extract `digitBox` and `QuickDiceEntrySlotView.content` first.
- **Severity:** Low

### 8.8 Foreground colours hard-coded on arbitrary backgrounds
- **Location:** `Modules/CoreRPG/Rows/ColoredEditRowModifier.swift`, `ColoredTagRowModifier.swift`; `Modules/CoreRPG/LGViews/GridLabelView.swift:30-45`; `Modules/SpaceRPG/Record/ReconstructionProgressView.swift:74-79`; `Modules/GeneratorRPG/View/PdfSummaryAnalysisView.swift:113-124` (red checkmark for "pending")
- **What:** Fixed white/black/blue text instead of a colour derived from the background or theme tokens.
- **Why:** Contrast depends on the caller's colour; a red checkmark reads as success-with-error.
- **Action:** Derive foreground from luminance or use contrast-checked theme tokens; one shared progress-row view.
- **Severity:** Low

### 8.9 `ProgressView` enlarged with `.scaleEffect(1.5)`
- **Location:** `Modules/PhotoRPG/Photo/AsyncImageViewer.swift:44`; `Modules/PdfRPG/Root/ViewerRootView.swift:43`; `Modules/PdfRPG/View/PdfExtractionSharedViews.swift:13`; `Modules/GeneratorRPG/View/PdfSummaryAnalysisView.swift:84`, `TableSummaryAnalysisView.swift:85`, `PdfContentExtractionView.swift:76`, `BatchTextSummaryExtractionView.swift:154,196`
- **What:** Transform scaling.
- **Why:** Blurry and does not change layout size.
- **Action:** `.controlSize(.large)`.
- **Severity:** Low

### 8.10 Work with side effects inside view bodies or draw closures
- **Location:** `Modules/GeneratorRPG/View/SheetAIAssistantContext.swift:41-55` with `GeneratorRootModel.swift:150-182` (body creates and caches controllers and may tear others down); `Modules/WeatherRPG/Weather/LightningView.swift:39-42`, `StormView.swift:27-29`, `StarsView.swift:27-28` (simulation advanced in `Canvas` closures); `Modules/GameRPG/Table3D/GameTableView+PlatformFlat.swift:44-96` (two tasks map the first map twice); `Modules/SpaceRPG/Space/SpaceViewerSubviews.swift:261-264` (empty `update` closure); `Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:16-34` (private lazy box that traps on re-entrant read)
- **What:** Work is tied to body evaluation count.
- **Why:** A body or draw closure may run more than once per update; a controller teardown can cancel generation in another window.
- **Action:** Create controllers in `.task`/`onAppear`; advance simulations from the timeline date; let one task drive map changes; remove the empty closure; use `LazyState`.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Dead folder-bookmark loader still starts a task at launch for every file module
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:11,126-150`; `FileUrlViewModel.swift:1-31`; `FileBookmarkController.swift:150-158`
- **What:** `init` starts a task resolving stored folder bookmarks into `FileUrlDataModel.folders`; nothing reads `folders` and nothing ever saves a folder bookmark (`saveBookmark` callers use `folder: false`).
- **Why:** A launch-time task and bookmark IPC per file module for a feature that does not exist.
- **Action:** Delete `folders`, `loadFolderBookmarks`, `FileUrlViewModel`, the `folder:` parameters and the test asserting `folders().isEmpty`.
- **Severity:** Medium

### 9.2 Unreferenced symbols (verified by reference counts)
- **Location:** `Modules/CoreRPG/Files/FileManager+Coordination.swift:120-143` (`copyReplacingItem`); `Modules/CoreRPG/Model/LinkDataTransferable.swift:113-167` (six typealiases); `Modules/CoreRPG/Navigator/Protocols/NavigationViewRouting.swift:23-47` and three Navigator helpers; `Modules/MapRPG/Extensions/UIImage+Crop.swift:6-33,86-121`; `Modules/SpaceRPG/View/SpaceQuickLook.swift:11-12,32-46` (dead `dismiss` and empty loader off visionOS); `Modules/GameRPG/Network/GameProtocol.swift:9-14` (`.version`, `.error`); `Modules/CharacterRPG/Controller/GameController+Dice.swift:74-77` (`resetGameDiceId(entryId:)`); `Modules/AudioRPG/Model/AudioPlayerModel.swift:16-18` (`currentTime`); `Modules/PdfRPG/Root/ViewerRootView.swift:15,25-30` and callers (`onTextExtracted` plumbing, still open from audit 26 §9.5); `Modules/RolePlayGameKit/View/AppImportView.swift:69-73` (constant `isSelected: true`); `Modules/RolePlayGameKit/Model/ShareExtensionDatabaseService.swift` (unused error case)
- **What:** Types and methods with no caller.
- **Why:** Dead surface that looks live.
- **Action:** Delete after confirming witnesses (keep protocol witnesses).
- **Severity:** Low

### 9.3 Root model, item controller and data-mapper boilerplate is copied into every module
- **Location:** `Modules/AudioRPG/Root/AudioRootModel.swift:8-116`; `Modules/PdfRPG/Root/PdfRootModel.swift:13-112`; same pattern in Photo, Weather, Rule, Generator; `Modules/PhotoRPG/Controller/ItemController.swift:12-36` and `PdfRPG/Controller/ItemController.swift:12-36` (identical struct); per-module `DataController.swift` and `ViewController.swift`
- **What:** About 100 lines of controller construction and the same `setUp` body in each module.
- **Why:** A root-wiring change must be made nine times; copies already differ in small details.
- **Action:** A generic module root builder in CoreRPG that produces the shared controller graph from the module configuration.
- **Severity:** Medium

### 9.4 Other duplication
- **Location:** `Modules/{Photo,Character,Adventure,Dice}RPG/View/EmptyDropButton.swift` and `DropChooseView.swift`; `Modules/AdventureRPG/Controller/ExportController.swift:54-168` (ten validate-and-insert blocks, mapping written twice); `Modules/WeatherRPG/View/WeatherThunderEditor.swift`, `WeatherConditionEditor.swift`, `WeatherStormEditor.swift` (slider sync pattern x8); `Modules/GeneratorRPG/View` (three near-identical analysis views); `Modules/GameRPG/Table3D/GameTableModel+Dice.swift:74-108` (seven identical die arms); `Modules/RolePlayGameKit/Model/AppModel+Routing.swift:116-149` (identical navigation helpers); `Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:16-34` (second lazy-state mechanism); `GameRootSetupView`/`GameRootView` app-state mapping (audit 26 §9.33)
- **What:** Near-verbatim copies.
- **Why:** UI fixes must be applied in each copy.
- **Action:** One parameterised component per case (`EmptyDropButton(module:)`, a keyed export table, a generic slider row, a die dispatch table).
- **Severity:** Low

### 9.5 Oversized files (>500 LOC)
- **`Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:1282`** — eleven unrelated types; split along its MARK sections (decoder, manifest, collection discovery, document decoder, type inference, validation, source caches). Also `FoundryRuleModels.swift` (849), `FoundrySystemPackageReader.swift` (736), `UniversalVTTReader.swift` (583), `FoundryVTTBridgeDecoding.swift` (507). Severity: Medium.
- **`Modules/CoreRPG/Controllable/ImportControllable.swift:765`**, **`Persistence/CoreDataController.swift:636`** (move `CoreDataModel`/`PendingOperation` and debug logging out) — Low.
- **GameRPG:** `SharePlay/RPGSharePlayController+ChunkedTransport.swift:746`, `+SessionLifecycle.swift:567`, `SharePlayJournalPublicationQueue.swift:522`, `Statistics/Model/GameStatisticsTypes.swift:699`, `Statistics/Controller/GameStatisticsDataController.swift:541`, `Controller/MasterController+AudioMessages.swift:568`, `Model/GameMessagePipeline.swift:506` — Low.
- **Map/Kit:** `MapRPG/Controller/GameController+Pins.swift:656`, `EditController.swift:522`, `Map/MapRoomCanvas.swift:550`, `RolePlayGameKit/Import/Foundry/FoundryImportView.swift:715`, `FoundryVTTDomainMapper+Documents.swift:584`, `Model/AppModel.swift:529` — Low.
- **Generator:** `Controller/GeneratorController.swift:520` — Low.

### 9.6 Vendored Navigator code has no cleanup (still open from audit 26 §3)
- **Location:** `Modules/CoreRPG/Navigator` (21 files, 3,150 LOC); doc comments with `@StateObject` samples at `NavigationModifiers.swift:15,47,77`
- **What:** Only a fraction of the API is referenced; example comments teach banned patterns.
- **Why:** About 3k lines the team keeps compiling under Swift 6.
- **Action:** Trim to the used subset and delete the examples.
- **Severity:** Low

### 9.7 Preview fixtures compile into Release (still open from audit 26 §9.31)
- **Location:** `Modules/GameRPG/Preview/PreviewData.swift:18-113,306`; `MockData.swift:1-71` (imports SwiftData); `BattleRound/BattleRoundController.swift:458-466`; `Modules/CoreRPG` Fake fixtures
- **What:** Fixtures and a `preconditionFailure` stay in production builds because `#Preview` blocks reference them.
- **Why:** Binary size and an extra framework.
- **Action:** Wrap fixtures and previews in `#if DEBUG`; move `preview()` into `Preview/`.
- **Severity:** Low

### 9.8 `ID`/`URL` casing drifts from the project convention
- **Location:** `Modules/CoreRPG/Foundry` (about 220 identifiers), `Import` (about 146), `Files` (about 89), `Persistence` (about 46), `Settings` (`themeID`, `AppThemeID`)
- **What:** `CLAUDE.md` fixes `Id`/`Url`; these folders use `ID`/`URL`.
- **Why:** Two spellings; search and rename tools miss half.
- **Action:** Mechanical rename per folder (Foundry first); keep SDK names such as `objectID`.
- **Severity:** Low

### 9.9 Naming, stale comments and magic constants (grouped)
- **Location:** `Modules/CharacterRPG/Controller/EditController.swift:304,318` (`termineType`); `Modules/GameRPG/Table3D/GameTableModel.swift:65-68` (stale "only d20 and d6"); `Modules/MapRPG/Extensions/UIImage+Crop.swift` (file name vs types); `Modules/GeneratorRPG/Intent/RunGeneratorIntent.swift:52-53,67` (shadowed `progress`); `Modules/RolePlayGameKit/Model/AppModel.swift:47-51,236-248` (no-op `#if os(tvOS)`, tvOS generator aliased to adventure root); `Modules/CoreRPG/Extensions/Image+AKImage.swift` (3.0 scale); `Modules/PdfRPG/Pdf/PdfWrapperView.swift` (0.25 s, 1,000 matches); `Modules/AudioRPG` log emoji prefixes
- **What:** Misspellings, stale comments, unnamed constants.
- **Why:** Searchability and misleading text.
- **Action:** Rename and name the constants when touching the files.
- **Severity:** Low

### 9.10 Unresolved TODO/FIXME/HACK markers and `#if false` blocks
- **Location:** none found in any of the 15 modules (all four agents swept for `TODO`, `FIXME`, `HACK`, `#if false`, `print(`).
- **What:** No markers; `print()` calls are absent.
- **Why:** Reported for completeness.
- **Action:** None.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Per-key observation instead of whole-dictionary observation.** §7.2, §7.3, §7.12 and the `ItemGameModel` dictionaries all share one pattern: an `@Observable` dictionary or array read by many rows, so any write re-evaluates every reader. Decide on one idiom (a small per-id observable box or version counter, or `@ObservationIgnored` storage plus an explicit stamp) and apply it to the image cache, game dice maps, Space transforms and item game data. Profile with the SwiftUI Instruments template before and after.
2. **Move writes out of `body`, but check what the replacement write invalidates.** Audit 26 §8.2 correctly moved dice creation into `.task`, which revealed the fan-out in §7.3. For every "no writes in body" fix, confirm the new write site does not hit state that many views read.
3. **One temp-file and cache hygiene owner in CoreRPG.** §6.4, §5.2, §7.1, §7.14 and the disk image cache all lack a lifecycle. A single launch/game-end sweep plus byte budgets for caches would close several findings at once.
4. **Treat every network peer role consistently.** §6.1 and §6.2 show that new roles (proxy) or new entry points (LAN frames) can bypass checks that existed for the original path. Route all inbound events through one validation function parameterised by role, with tests per role.
5. **Large-map and large-library scaling.** §7.4, §7.5, §7.10, §7.7, §7.8 and §7.11 are linear scans or per-item rows that were fine at hundreds of items and fail at the documented maximums (20,000 hex cells, thousands of items). Add an id-to-index map where `[T]` is the store, batch persistence, and add a performance test with a 20k-cell map and a 10k-item library.
6. **Locale-neutral stored content.** §4.2 and parts of §4.3 write English into the user's library. Store structure, localize at render time.
7. **Decide the `AnyView` policy.** 54+ sites are kept on purpose; either redesign `ViewControllable` or document the exception in `CLAUDE.md` so every audit stops re-reporting it.
8. **Reduce module-root copy/paste.** §9.3 and §9.4 mean wiring changes are made nine times; a builder in CoreRPG pays back on the next audit round.

---

## 11. What was NOT audited

- `Sources/` (app targets, `RPGShare`, widget and share extensions), `Tests/`, `TestPlans/`, `Resources/` entitlements and Info.plist files, the `RPGTabletopGameContent` package.
- Compiler warnings: no build was possible (Linux container, no `xcodebuild`). The concurrency section is from reading code only; no Step-2 warning list exists.
- A separate SwiftUI-expert pass: the four module agents covered SwiftUI rules from `CLAUDE.md` (category D), but a dedicated `swiftui-expert-skill` review with Instruments traces was not run. Section 7.3 and §7.2 need a trace to confirm.
- Instruments profiling, memory measurement (§7.1 is reasoned from code), and on-device behaviour (visionOS, SharePlay, CloudKit sync).
- Files only grepped, not read line by line (listed in each agent's coverage notes): in CoreRPG, Foundry (except `FoundryZIPArchive`), Navigator, Import (except one session), Sheet rows and context menus, Inspector, ItemDetail, Theme, Settings, most Controllable import/export/edit files, `CloudDocumentController`, `CloudFolderScan`; in GameRPG, die geometry/mesh files, most SharePlay journal files, `PlayerController+*` extensions, BattleRound views, most GameViews and SetupViews, Statistics views; in MapRPG, about 40 `Map/` files including `MapEditorSession*`, most `Model/`, `View/` and other controllers; in RolePlayGameKit, 20 view files and most Foundry mapper files; in SpaceRPG, about 30 `Record/` files; in the nine small modules, Weather views, Table views, most Intents, Photo Space views, and Character link/sheet/export controllers.
- Algorithmic correctness of the Foundry importers, CRDT merge logic, dice and table generation beyond the cited lines, TabletopKit/RealityKit rendering, and FoundationModels output quality.
- Build settings, scheme configuration and Xcode project structure.
- Localization wording (only missing/unlocalized strings were noted).
- Preview fixtures (`PreviewData`, `MockData`).

---

## 12. Verification

No Critical findings were assigned. Both High findings were re-checked by opening the cited lines.

- **§5.1** — open `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+Documents.swift`, lines `403-418`: the `range` is joined into the string "Range: …" and appended to `entry.content`, while `entry.name` stays the sanitized result text. Then open `Modules/CoreRPG/Text/TableRollRange.swift`, lines `14-34`: `selectorRange(for:)` parses only a leading numeric selector from the name, and `Modules/TableRPG/Controller/TableGenerationController.swift`, lines `247-258`, falls back to `entries[result - 1]`. A repository search finds `"Range:"` only at the mapper line (`FoundryVTTDomainMapper+Documents.swift:414`), so nothing reads the content text.
- **§7.1** — open `Modules/CoreRPG/Controllable/ImageCacheControllable.swift`, lines `247-286`: `imageCache` is a plain `[UUID: AKImage]` with `imageCountLimit = 120` and eviction by count only (`evictLeastRecentlyUsed(... limit:)`), no byte accounting. A search for `didReceiveMemoryWarning`, `memoryWarning` and `DispatchSource.makeMemoryPressure` in `Modules` and `Sources` returns no hits (the agent's search; the author's rerun covered those three terms). The 268 MB / 48 MB per-image figures come from the 8192 px decode cap in `Image+AKImage.swift` and are worst-case estimates, not measurements.

Medium findings that rest on a single reading of the code (not re-opened by the author): §6.1, §6.2, §6.3, §6.4, §5.2, §5.3 and §5.4. §5.3, §5.4 and §5.5 are marked unverified because they depend on platform reachability or editor constraints that were not checked.

If any finding doesn't reproduce when you visit the line, ping me with the specific reference and I'll re-investigate.
