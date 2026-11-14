# GameRPG views, BattleRound, Statistics, Root, Browser, Search, SetupViews, Preview (audit 26)

Files read: all 38 BattleRound files (~3.7k LOC); Statistics controller/model/data/types/export plus the dashboard, filter, customization, all-sessions, schedule, dice and activity views (~4k LOC); Root/GameRoot.swift, GameRootView, GameRootSetupView, GameFactory; Browser/BrowserManager; Search (all 6); SetupViews (adventure/player/start/join-code/browser/proxy/portal views); GameCenter; Intent/GameIntents; GameViews: GameRootViewer, GameScreenModel(+MainTab), Master/PlayerGameScreen, OverlayGameMenu, OverlayGameLayout, IOSGameSidebarMenu, BattleRound* hosts, TablePlayers (all), QuickDice (all), BatteryView, join-code/elapsed/chrome-status/immersive-sync/window-toggle/table-window views. Overall health: very good. BattleRound has no logic bug I could trace (the three earlier BattleRound audits are visibly applied), Statistics persistence is careful (batched, retry, idempotent). The findings are mostly product-logic edges in Statistics/dashboard, one data-loss UX path in the Save-and-Quit flow, and cosmetic rule violations. No Critical or High.

### Dashboard hides its filters when the selected range has no games
- Category: Bug
- Location: Modules/GameRPG/Statistics/View/GameStatisticsDashboardView.swift:243-266 (filter only in the final `else`), Modules/GameRPG/Statistics/Model/GameStatisticsTypes.swift:234 (default `.lastSixMonths`), Modules/GameRPG/Statistics/View/GameStatisticsCustomizationView.swift (no range control)
- What: `GameStatisticsFilterView` is rendered only when `summary.sessionCount > 0`; with zero games in the range the dashboard shows the sample ("preview") dashboard instead, and the customization page has no date-range control.
- Why: A user whose last counted game is older than 6 months (or who picked "30 Days" and then did not play for a month) sees sample data as if they had none, and cannot widen the range to see their real statistics. The persisted configuration keeps the narrow range.
- Action: Show the filter bar above the placeholder whenever any stored game exists (or when the range is not `.allTime`), and use an "no games in this range" empty state instead of the sample dashboard in that case.
- Severity: Medium
- Status: NEW

### Remote dice timestamp is used as the event time and moves session/participant activity
- Category: Bug
- Location: Modules/GameRPG/Statistics/Controller/GameStatisticsController.swift:28 (`diceResult?.timestamp ?? occurredAt`), Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift:199-205, 207-208, 356-357, 28
- What: `occurredAt` of a dice event is taken from `DiceResultModel.timestamp`, which the roller's device sets from its own clock and which travels in the payload.
- Why: A peer with a skewed clock (or a crafted payload) with a future timestamp pushes `session.lastActivityAt` and `durationSeconds` into the future, makes `synchronizeParticipants` skip later (earlier-dated) updates for that sender (`date >= previousActivity` guard), and postpones launch recovery of an interrupted session (`date - lastActivity >= idleAge` stays false). The finish path recomputes duration from the real end date, so the visible damage is mostly limited to the roster/connected-time and interrupted sessions.
- Action: Clamp the event time to the local receipt time (`min(timestamp, occurredAt)`), or ignore the payload timestamp for session/participant bookkeeping.
- Severity: Medium
- Status: NEW

### Persisted dashboard configuration is not forward compatible
- Category: Bug
- Location: Modules/GameRPG/Statistics/Model/GameStatisticsTypes.swift:228-244, Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:64-69
- What: The configuration is stored as synthesized `Codable` JSON; `sectionOrder` is the saved array, and a decode failure silently falls back to `.default`.
- Why: Adding a `GameStatisticsSection` case later never shows it for existing users (`visibleSections` filters the saved order, nothing appends missing cases); adding a non-optional field, or removing/renumbering a case, makes the whole saved configuration fail to decode and resets the user's layout. No test pins this.
- Action: Add a custom `init(from:)` with `decodeIfPresent` defaults, drop unknown cases, and append sections missing from the saved order.
- Severity: Low
- Status: NEW

### Statistics reload fetches every event of every session on the shared context
- Category: Performance
- Location: Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift:215-258 and 150-168, Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:303-335, 460-475
- What: `fetchDataSet` materialises all events and participants of all matching sessions as snapshots; it runs on each filter change (`.task(id: configuration)`), after each game, on pull to refresh, and a second time all-time for achievements. `recordEvents` additionally runs one duplicate-check `count` fetch per event (up to 100 per batch).
- Why: The context is the app's shared background context, so a long history (tens of thousands of events) blocks other modules' saves while it loads; the aggregates only need counts and sums.
- Action: Aggregate with `NSExpression`/grouped fetches (count and sum by kind/outcome/module/origin), and do the duplicate check with one `deduplicationKey IN %@` fetch per batch.
- Severity: Low
- Status: NEW

### `reload()` has an if/else whose two branches are identical
- Category: Dead code
- Location: Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:320-328
- What: Both branches assign `summary = newSummary`.
- Why: Looks like a leftover of an observation-avoidance optimisation that no longer exists; misleads readers and compares large arrays for nothing.
- Action: Assign once, or restore the intended "only publish when changed" using `GameStatisticsSummary: Equatable`.
- Severity: Low
- Status: NEW

### `lastCompletedSessionID` is written but never read
- Category: Dead code
- Location: Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:28, 292, 397
- What: Published property with no reader in Modules, Sources or Tests (grep verified).
- Why: Dead state; also points at a session that `pruneShortSessions` may have just deleted (line 295).
- Action: Remove it.
- Severity: Low
- Status: NEW

### Battle Round window shortcuts take over Command-Right in the HP and initiative text fields
- Category: SwiftUI
- Location: Modules/GameRPG/BattleRound/BattleRoundWindowToolbar.swift:25-41 (macOS), field in Modules/GameRPG/BattleRound/BattleAttackerConfigRows.swift:96-112
- What: Next Turn is bound to Command-Right and Next Round to Command-Option-Right, window-wide, while the cards contain editable number fields.
- Why: In a text field Command-Right is "move to end of line"; a toolbar key equivalent is normally matched first, so pressing it while editing HP advances the turn (and broadcasts). Unverified on device.
- Action: Pick a combination that is not a text-editing command (for example Command-Return / Option-Command-Return) or disable the shortcut while a field is focused.
- Severity: Low
- Status: NEW

### Config rows commit on every focus loss, even when nothing changed
- Category: Bug
- Location: Modules/GameRPG/BattleRound/BattleAttackerConfigRows.swift:114-117, 163-179
- What: `commit()` runs when focus leaves the field regardless of whether the text was edited, and calls `setInitiative` / `setHitPoints` with the parsed value.
- Why: For hit points that is a write into the Character entry plus a broadcast attempt (deduplicated by the log) each time the GM merely tabs through the field; for a linked entry the write goes through the delta path. Unverified whether the setters no-op on equal values.
- Action: Compare the parsed value with `currentValue` and return early when equal.
- Severity: Low
- Status: NEW

### Hard-coded paddings in the roll strip
- Category: SwiftUI
- Location: Modules/GameRPG/BattleRound/BattleRollResults.swift:27, 56-57
- What: `HStack(spacing: 3)`, `.padding(.horizontal, 5)`, `.padding(.vertical, 2)` next to the existing `BattleRoundSpacing` scale.
- Why: CLAUDE.md asks to avoid literal spacing; the rest of BattleRound uses the scale.
- Action: Use `BattleRoundSpacing.extraTight/tight`.
- Severity: Low
- Status: NEW

### Cancelling or swipe-dismissing "Save and Quit" still quits the game
- Category: Bug
- Location: Modules/GameRPG/GameViews/MasterGameScreen.swift:49-60, 95-99 (`showExport` -> `endGame()`), Modules/CoreRPG/FileViews/ExportProgressPanelView.swift:59-62, 66-76 (Cancel calls `finishAction()`; `.onDisappear` cancels the export)
- What: `onChange(of: showExport)` ends the game whenever the export sheet closes, whatever the outcome; the sheet's Cancel button, a swipe-down dismissal, a failed export and a cancelled file mover all close it the same way.
- Why: A game master who picks "Save and Quit", then cancels the export (or the save dialog) because the destination was wrong, loses the running game and the unsaved game state without a further prompt. The alert's own "Cancel" is one step earlier and does not help here.
- Action: End the game only when the export finished successfully (`finishedAction` after `.finished`); on cancel or failure close the sheet and keep the game running. Decide whether a failed save should offer "Quit anyway".
- Severity: Medium
- Status: NEW

### Dice and achievement statistics count every roll the device sees, not only the user's own
- Category: Bug
- Location: Modules/GameRPG/Statistics/Controller/GameStatisticsController.swift:100-112, 20-22 (every `.dice` message becomes `.diceRolled`), Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift:243-247 (no actor filter when `direction == nil`), Modules/GameRPG/GameCenter/GameCenterController.swift:159-185 (achievements read the unfiltered summary), Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:206-263 (incoming events recorded)
- What: The game master records every player's incoming roll and a player records the other players' rolls; "Dice Rolls", "Criticals", "Fumbles" and the achievements Dice Initiate/Legend/Overlord, Critical Moment, Fortune's Favorite, Unlucky Hero and Cursed Dice are computed from all of them.
- Why: Personal-sounding achievements are earned by other people's dice (a game master with five players reaches "Dice Overlord" about six times faster); the dashboard label "Dice Rolls" is ambiguous. Intent is unclear: the Direction filter suggests this is known, but the default and the achievements do not use it.
- Action: Decide the meaning. Either count only events whose `actorId` is the local participant (add `actorId`/`isLocal` to the snapshot) for the highlights and achievements, or rename the highlight "Dice Rolls at the Table" and keep achievements on own rolls.
- Severity: Low
- Status: NEW

### Activity chart tooltip only appears on the first day of a week or month bucket
- Category: Bug
- Location: Modules/GameRPG/Statistics/View/GameStatisticsActivityChart.swift:36-41, 61
- What: The selected point is shown when `isDate(point.date, inSameDayAs: selectedDate)`, but with `.week` (the default) or `.month` granularity `point.date` is the bucket start and `chartXSelection` returns the date under the cursor.
- Why: The value label for a week or month only appears when the pointer is exactly on the bucket's first day; for the default granularity the selection looks broken.
- Action: Resolve the selection to the bucket with `calendar.dateInterval(of: granularity.calendarComponent, for: selectedDate)` (pass the granularity into the chart) or pick the nearest point.
- Severity: Low
- Status: NEW

### Global search can show the results of an older search term and flicker its progress state
- Category: Bug
- Location: Modules/GameRPG/Search/SearchGlobalController.swift:34-47 (defer resets `isSearching`; `model.results =` after the await has no cancellation check), Modules/GameRPG/Search/GlobalSearchModel.swift:36-38
- What: A cancelled search keeps running `searchAllItems()` (the module searches are not cancellation aware) and then assigns `model.results` unconditionally; its `defer` also sets `isSearching = false` after the newer search has set it to true.
- Why: Typing quickly can end with the previous term's results under the current term, and the progress view disappears while the newer search still runs. The outer `.task(id:)` cancellation also does not reach the inner unstructured `Task`.
- Action: Check `Task.isCancelled` (or compare the searched text with `model.searchText`) before assigning results, and only clear `isSearching` if `model.currentTask` is still this task; wrap the inner task with `withTaskCancellationHandler` or use `async let`-style structured work.
- Severity: Low
- Status: NEW

### "Clear Saved Game" runs without confirmation
- Category: SwiftUI
- Location: Modules/GameRPG/SetupViews/SelectedAdventureView.swift:158-190
- What: The button calls `adventureGameControllable.resetGame()` directly, drops every module's staged game copy and files, and is not marked destructive.
- Why: One mis-tap on the setup card discards an imported saved game that took a file picker and import to create.
- Action: Add a confirmation dialog with a destructive role (the Battle Round "End" already follows this pattern).
- Severity: Low
- Status: NEW

### Empty-game content ticks every second for a minute-resolution clock
- Category: Performance
- Location: Modules/GameRPG/GameViews/GameRootViewer.swift:325-333 (`TimelineView(.periodic(from: .now, by: 1))`)
- What: The elapsed time is formatted `hourMinute` but redrawn every second; `GameElapsedTimerText` already uses a 60 s timeline anchored to the start date.
- Why: 59 of 60 body evaluations are wasted while the game screen is empty (the whole time before a map is shown).
- Action: Reuse `GameElapsedTimerText`'s anchored one-minute timeline (or the view itself).
- Severity: Low
- Status: NEW

### Preview fixtures are compiled into Release builds
- Category: Refactor
- Location: Modules/GameRPG/Preview/PreviewData.swift:18-113, Modules/GameRPG/Preview/MockData.swift:1-71 (`import SwiftData`, no `#if DEBUG`), Modules/GameRPG/BattleRound/BattleRoundController.swift:458-466 (`static func preview()` in the production file)
- What: `GameRoot.preview`, `previewFixture`, the `MockData` preview modifier and `BattleRoundController.preview()` have no `#if DEBUG`, although CLAUDE.md describes the Preview folder as `#if DEBUG` fixtures.
- Why: About 400 LOC of fixture code and a SwiftData import ship in the app; `previewFixture()` builds whole module roots. Tests and previews in this module use them, so gating needs the Release-build check noted in the earlier fixture audit.
- Action: Wrap the Preview folder and the `preview()` extension in `#if DEBUG`; keep anything Tests need behind the same flag the test plan builds with, and build Release to confirm.
- Severity: Low
- Status: NEW

### GameRoot.swift mixes six responsibilities in 809 lines
- Category: Refactor
- Location: Modules/GameRPG/Root/GameRoot.swift:1-809 (properties and network-action queue 18-361, selection helpers 363-393, `startMaster` 395-467, player start/join/stop 469-669, demo loop 671-769, search helper 771-809)
- What: One file holds the root, its network-action scheduler, master and player start/stop state machines, the auto-playing demo and the module lookup.
- Why: The start/stop generation logic (`isStartingGame`, `isStartingMaster`, `stopGeneration`, `stopGameTask`) is the riskiest code in the module and is hard to review next to unrelated demo and search code; private members force everything to stay together.
- Action: Move the extensions to `GameRoot+Master.swift`, `GameRoot+Player.swift`, `GameRoot+Stop.swift`, `GameRoot+Demo.swift`, `GameRoot+Search.swift` (widen `private` to `fileprivate`-free internal where needed) and keep the stored state in `GameRoot.swift`.
- Severity: Low
- Status: NEW

### Hard-coded paddings and spacings across GameViews, SetupViews and Statistics
- Category: SwiftUI
- Location: about 107 sites, for example Modules/GameRPG/SetupViews/SelectedAdventureView.swift:30-60, Modules/GameRPG/SetupViews/SelectedPlayerView.swift:30-55, Modules/GameRPG/GameViews/GameScreenOrnaments.swift, Modules/GameRPG/GameViews/RoundGameControlStyle.swift, Modules/GameRPG/GameViews/GameRootViewer.swift:178-180, 340-345, Modules/GameRPG/Statistics/View/GameStatisticsDiceChart.swift:51 (fixed 280/420 heights), Modules/GameRPG/BattleRound/BattleRollResults.swift:27, 56-57
- What: Literal `spacing:`/`.padding(n)`/`.frame(width:)` values where CLAUDE.md asks to avoid them; BattleRound has a `BattleRoundSpacing` scale, the rest of the module has none.
- Why: Style-rule violation; fixed chart heights and the 120 pt portal circle do not follow Dynamic Type.
- Action: Introduce one small spacing scale for GameRPG (BattleRoundSpacing generalised) and `@ScaledMetric` for the fixed frames; do it opportunistically when the files are touched.
- Severity: Low
- Status: NEW

### Two views write the same `AppGameStateModel` fields on every game-state change
- Category: Duplication
- Location: Modules/GameRPG/Root/GameRootView.swift:14-26, Modules/GameRPG/Root/GameRootSetupView.swift:71-76
- What: Both views observe `gameConfig.state` and map it to `isGameRunning` and `gameModus` (one guards against equal values, the other assigns unconditionally).
- Why: Two writers for one derived value can drift (they already differ in the equality guards); an unconditional assignment re-invalidates every reader of `AppGameStateModel`.
- Action: Keep the mapping in one place (a method on `GameRoot` or `AppGameStateModel`) and call it from one view.
- Severity: Low
- Status: NEW

### `GameStatisticsModel.record(_:)` is declared async but only spawns an untracked task
- Category: Concurrency
- Location: Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:129-138
- What: `record` starts an unstructured `Task` with `[weak self]` and returns at once; ten call sites `await` it.
- Why: Not a bug today (the main-actor FIFO order and `isClosingSession` keep it correct, and it is deliberate per the doc comment), but the `async` signature promises ordering it does not give; an event recorded just before `finishSession` depends on task scheduling order.
- Action: Make it a synchronous `func` that appends to `pendingEvents` directly (it never needs to suspend) and drop the `await` at the call sites, which also removes the task allocation per game message.
- Severity: Low
- Status: NEW

### Test gaps
- Category: Test gap
- Location: Tests/GameRPGTests (Statistics and BattleRound areas)
- What: No test pins (a) a future-dated dice timestamp against `recordEvents`/`synchronizeParticipants`, (b) decoding an older saved `GameStatisticsDashboardConfiguration` after a section is added, (c) the dashboard state when the selected range has no sessions, (d) the Save-and-Quit cancel path.
- Why: These are the paths of the findings above; all are pure and cheap to test (the first two on the controller/model, (c) via a view model extraction).
- Action: Add the four tests together with the fixes.
- Severity: Low
- Status: NEW

Not audited in this area: Modules/GameRPG/GameViews files not opened (OverlayMasterTabBar, OverlayPlayerTabBar, OverlayToolBar, MasterOverlayMenu, PlayerOverlayMenu, MasterSideMenu, PlayerSideMenu, MasterModuleWindow*, GameMainTab*, GameWindow*, GameScreenOrnaments, GameScreenLayer, GameTopOcclusion, IOSGameOverlay*, LogMessage*/LogRowsSection/LogSections, SharingOptionsSection, AttachmentSection, OnlyGameView, OnlyPlayerGameView, TabGameView/TabPlayerGameView/TabSecondGameView, RoundGameControlStyle, JournalTransportStateImage, MapPhotoFullScreenControls, GameDiceToggleButton and persistence); SetupViews GameSetupRole*, GameSetupBackdrop, SupporterWelcomeCard, ImportRouteDestinationView, BrowserRowView; Root/GameRootModel, GameRoot+TablePlayers; Statistics views GameStatisticsPreviewHeader/PreviewSessions, CategoryBarChart, CountBarChart, NetworkChart, Customization row/inspector/sheet; Preview/PreviewData and MockData bodies (only header/gating checked); ExternalScreen. Nothing was built, run or rendered; the macOS Command-Right shortcut and the focus-commit write findings are unverified on device.
