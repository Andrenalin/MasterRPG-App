# MasterRPG Code Audit 22

Generated 2026-10-29 against `38393b789` (`develop`). Scope: all production Swift under `Modules/` and `Sources/` (~205k LOC, 15 modules, 5 targets). Tests were skimmed only. Read-only audit when written; the fixes are recorded in §13.

**Compiler ground truth.** Clean Debug builds into fresh derived-data folders (Xcode 27.2 RC): MasterRPG iOS Simulator, MasterRPG visionOS Simulator, MasterMac and MasterTV all succeeded with 0 Swift warnings. The only diagnostics were "appintentsmetadataprocessor: Metadata extraction skipped" notices. No tests were run.

**Method.** Six read-only agents (concurrency/API, dead code/duplication, CoreRPG, GameRPG, Map+Space+RolePlayGameKit+Sources, remaining modules). Tags: [NEW], [STILL OPEN from …], [INCOMPLETE FIX of …], [REGRESSION sha]. **[verified]** = I re-read the cited lines myself. Everything else is the reporting agent's reading; line numbers marked `~` must be re-opened before editing. Agents grepped earlier audits only partly, so every [NEW] tag needs a re-check against `Docu/CODE_AUDIT_*.md`.

**Limits of this audit:** the SwiftUI pass (§8) was completed against the SwiftUI-expert skill's correctness checklist with pattern scans over all ~1150 SwiftUI files plus targeted reads; no Instruments trace was recorded and no view was profiled. Only the High findings and a few Mediums were spot-verified (see §12); Low findings are grouped and some carry no individual line range.

---

## 1. Executive summary

1. **[High] Hidden pins' name, portrait id, character link and position reach players in every `.mapState`** — §6.1 — `Modules/MapRPG/Controller/GameController+Sync.swift:27-34` [verified].
2. **[High] The map package sent to players is not redacted** — §6.2 — `Modules/MapRPG/Controller/GameController.swift:346-370`, `Modules/CoreRPG/Controllable/GameControllable.swift:252-275` [verified].
3. **[High] Cross-module sheet links can recurse until stack overflow** — §5.1 — `Modules/CharacterRPG/Controller/SheetController.swift:84-90` and four sibling controllers [traced, not run].
4. **[High] iCloud folder scan skips unreadable subfolders silently, so their items look "removed" and are pre-selected for trashing** — §5.2 — `Modules/CoreRPG/Files/CloudFolderScan.swift:160-170` [verified].
5. **[High] Weather values decoded without bounds crash in `Int(Double)`** — §5.3 — `Modules/WeatherRPG/Model/WeatherModel.swift:68-71`, `View/WeatherViewer.swift:93-99` [verified].
6. **[Medium] Statistics recovery/prune act on sessions another device syncs in** — §5.4 — `Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift:9-26` [verified wiring].
7. **[Medium] Group events are relayed to all peers before size/plausibility checks** — §6.3.
8. **[Medium] Any player can request any library item by id** — §6.4 [STILL OPEN from CODE_AUDIT_17 §6.3].
9. **[Medium] Huge typed HP value traps in the battle card** — §5.5 — `Modules/CharacterRPG/Controller/GameController+EntryResolution.swift:201` [verified].
10. **[Medium] `BatteryMonitor` leaks observers/poll tasks per `BatteryView` init** — §3.1.

---

## 2. Quick wins (≤30 min)

- Clamp decoded weather values in `WeatherModel.init(from:)` (§5.3).
- Make the iCloud scan treat an unreadable subfolder as "scan incomplete" (§5.2).
- Start `BatteryMonitor` from `.onAppear` instead of `init` (§3.1).
- Clamp parsed battle numbers and quick-editor values; use saturating add/subtract (§5.5, §5.6).
- Filter before `prefix(20)` in `ItemEntityQuery.suggestedEntities` (§5.14).
- Delete ~20 unreferenced declarations and 4 preview-only views listed in §9.2.
- Remove 8 dead `import Combine` lines (§9.3).
- Drop 7 stale GameRPG localization keys, translate "Player Game Screen" (§9.8).
- Guard `Double.random(in: 50 ... size.width - 50)` in the weather lightning code (§5.12).

---

## 3. Concurrency

Agent A found the concurrency rules clean: no `DispatchQueue`/semaphore/`NSLock`/`Task.detached`; all 15 `@unchecked Sendable` types, 15 continuations and every `nonisolated(unsafe)` use were read and judged sound; all `@Observable` classes are `@MainActor`.

### 3.1 BatteryMonitor leaks one observer set / poll task per BatteryView init
- **Location:** `Modules/GameRPG/GameViews/BatteryView.swift:18, 40-52, 105-134`
- **What:** `@State private var monitor = BatteryMonitor()` runs `init()` on every struct init, and `init()` starts monitoring; only the instance SwiftUI keeps gets `stopMonitoring()` on disappear. [verified: code as described]
- **Why:** Discarded instances register NotificationCenter observers (iOS/visionOS) or start an endless 30 s poll (macOS) each time the parent body re-evaluates. Plausible; not observed at runtime.
- **Action:** Start monitoring in `.onAppear`/`.task` only; add an isolated deinit.
- **Severity:** Medium [INCOMPLETE FIX of CODE_AUDIT_2 §5.5]

### 3.2 Smaller concurrency items (Low)
- `RemoteDownloadsInFlight` wait is not cancellable despite its comment — `Modules/CoreRPG/Files/RemoteDownloadsInFlight.swift:19-35`.
- `GameRoot.stopGame` clears `stopGameTask` without an ownership token — `Modules/GameRPG/Root/GameRoot.swift:517-535`.
- `ItemProviderImporter.loadDataRepresentation` ignores cancellation — `Sources/RPGShare/ItemProviderImporter.swift:258-268`.
- PDFKit find: stale end-of-scan notification can drain the new scan — `Modules/PdfRPG/Pdf/PdfWrapperView.swift:139-175`.
- `GameRoot.startGame` has no re-entrancy guard (Medium, plausible) — `Modules/GameRPG/Root/GameRoot.swift:419-478`.
- `GeneratorController` re-sends before the cancelled stream ends — `Modules/GeneratorRPG/Controller/GeneratorController.swift`.
- Intent join polls every 250 ms — `Modules/GameRPG/Intent/GameIntents.swift:216-225`.
- Synchronous RealityKit loads on the main actor — `Modules/GameRPG/Table3D/GameDice.swift:25-45`.

---

## 4. API modernity

Clean for every CLAUDE.md rule except the following (all Low): UIKit haptics in SwiftUI views (`EntryEditorHeaderView.swift:34,73,102`, `ItemHeaderEditorView.swift:89`); NSString bridging in new sync code (`CloudFolderScan.swift:22,197`); 102 `.padding(<n>)`, 277 numeric stack spacings and 165 numeric frames (guideline deviation, many intentional); `defaultTabBarPlacementAll` ignores its argument (`Modules/CoreRPG/Platform/TabbarPlacement.swift:6-20`); search highlight is diacritic-sensitive while the filter is not (`Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift:256-259`).

---

## 5. Bugs / logic errors

### 5.1 Cross-module sheet links have no cycle guard
- **Location:** `Modules/CharacterRPG/Controller/SheetController.swift:84-90`; `Modules/MapRPG/Controller/SheetController.swift:44-58`; Table, Audio and Rule siblings; Adventure passes `moduleDepth + 1` and is not affected.
- **What:** A link to another module's item calls that module's public `sheet(...)` with `moduleDepth: 0`; with `isEditor == false` the child is not folded, and Character's `visited` set restarts empty at each hop. No other level cap exists in the sheet controllers. `isSheetLink` is simply `command == nil`.
- **Why:** An NPC entry linking a map whose room entry links the same NPC recurses until the stack overflows when the viewer/game sheet is built. Traced statically, not run.
- **Action:** One shared depth/visited guard carried across modules; share the link-to-sheet resolution.
- **Severity:** High [INCOMPLETE FIX of CODE_AUDIT_Character §5.1]

### 5.2 iCloud folder scan: unreadable subfolder → items "removed"
- **Location:** `Modules/CoreRPG/Files/CloudFolderScan.swift:160-170, 330-335`; `Modules/CoreRPG/Controllable/CloudScanController.swift:38-43, 63-67`
- **What:** Only a failed listing of the module root returns `nil`; a failed subfolder is `continue`d and the result is treated as complete. [verified]
- **Why:** Items with files in that folder land in `removals`, which are selected by default (`CloudFolderScanModel.swift:21-24`, [verified]) and trashed on Sync; the "most files missing" warning needs ≥3 removals and a majority.
- **Action:** Track unreadable folders and exclude their items (or fail the scan); make removals opt-in or always confirm with the count.
- **Severity:** High (default-selected removals alone: Medium) [REGRESSION 27d877a06]

### 5.3 Weather parameters are unbounded
- **Location:** `Modules/WeatherRPG/Model/WeatherModel.swift:68-71`; `View/WeatherViewer.swift:93-99`; `Weather/Storm.swift:43` [verified]
- **What:** `rainIntensity`, `lightningMaxBolts`, `lightningForkProbability` decode as plain `Double`; the viewer uses `Int(Double)` and `0 ..< strength`.
- **Why:** NaN/inf/huge/negative values from an import or peer trap; 1e300 becomes inf in the `Float` store and crashes on every open. The editor sliders are bounded, imports and peers are not.
- **Action:** Clamp on decode and on load; saturate the conversions.
- **Severity:** High [NEW]

### 5.4 Statistics recovery/prune act on sessions of other devices
- **Location:** `Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift:9-26`; `Model/GameStatisticsModel.swift:72-88, 406-426`; container wiring `Modules/RolePlayGameKit/Model/DataBaseModel.swift:39` and `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:52-70` [verified]
- **What:** At launch `recoverInterruptedSessions` completes every `isComplete == NO` row, then `pruneShortSessions` (added 2026-10-29) deletes completed sessions under 15 minutes or of observer/proxy role. The GameRPG bundle is merged into the single CloudKit container and all three statistics entities are `syncable="YES"`, so with iCloud storage on these rows sync between the user's devices.
- **Why:** Device B launches while device A is mid-game: A's synced, still-open session is completed by B's recovery and, if under 15 minutes old, deleted by prune; the change syncs back, and A's `recordEvents` then skips the "completed" session. A's game statistics are lost or truncated. Within one device the repair is safe (`activeSessionID` is only completed by `finishSession`). The recovery half predates the prune, the deletion half is new.
- **Action:** Scope recovery and prune to sessions this device owns (device/install id on the session) or add a minimum idle age before a foreign open session is touched.
- **Severity:** Medium [NEW, introduced by the 2026-10-29 prune]

### 5.5 Battle HP input traps
- `Modules/GameRPG/BattleRound/BattleNumberInput.swift:11-25`, `BattleRoundController.swift:121-135`, `Modules/CharacterRPG/Controller/GameController+EntryResolution.swift:181-214` (trap near :201). A typed `9223372036854775807` reaches `Int(Double)`. Clamp at input. **Medium** [NEW]

### 5.6 Other numeric overflow
- Quick editor `+`/`-` on `Int.max` (`Modules/CoreRPG/Buttons/QuickEditorButtonView.swift`; `DiceQuickEditor.swift`) — Medium. `ChangeCharacterValueIntent` clamp incomplete for formula-backed entries — Medium [INCOMPLETE FIX of CODE_AUDIT_Since_3.0.1 §5.17].

### 5.7 Table / dice / calculator correctness (Medium)
- GM table roll ignores percent dice, modifiers and rerolls and disagrees with the player path (`DiceRootModel.roll(diceId:)`, `TableGenerationController.swift`).
- No total-node cap in random table generation (exponential occurrence tree; `RollTableIntent` runs it on the main actor).
- Calculator rounds every intermediate result to 3 decimals (`Modules/CharacterRPG/Model/Calculator.swift`).

### 5.8 PDF / AI summary (Medium + Low)
- AI summary numbers pages by array position after dropping empty pages, bookmarks store labels (Medium). Prompt claims "first 40 pages" while ~7000 characters are sent; token budget is character-based.

### 5.9 Map / Space (Medium)
- `mergeExternalEntries` drops uncommitted working-copy entries (`Modules/MapRPG/Map/MapEditController+Sync.swift:19-36`).
- Retained failed-attach scans live under Caches and are deleted by `cleanupStaleScans` (`Modules/SpaceRPG/Record/AppDataModel.swift:95-101, 355-385`) [INCOMPLETE FIX of CODE_AUDIT_21 §5.21].
- Room thumbnail crop ignores rotation / 8192 px cap (`MapRPG/Controller/CacheController.swift:29-41`).
- Share extension imports only the first item (`Sources/RPGShare/ShareViewController.swift:22-26`).

### 5.10 Statistics (Low)
- Failed save leaves inserted rows pending, so retry inserts twice (`GameStatisticsModel.swift:193-231`).
- "Full Party" achievement reads only the 10 newest sessions (`GameCenterController.swift:163,180`; `GameStatisticsController.swift:134`).
- `deleteAll` during a running game ends statistics for it (`GameStatisticsModel.swift:391-404`).

### 5.11 iCloud scan follow-ups (Medium/Low) [REGRESSION 27d877a06]
- Plan applied without revalidation of removals/moves (`CloudScanController.swift:46-70`).
- Scan-created items carry no content hash, so renames look like delete+add.
- Deterministic ids make two devices insert the same row (duplicates until repair).
- Apply loop and listing run on the main actor (Low); `isCloud(url:)` prefix check without path boundary (Low).

### 5.12 Other Low
- Audio: empty playlist wipes the queue; removing the playing item leaves Now Playing/AVPlayerItem; scrubber seeks to stale value; list recomputes on main actor.
- Dice: stale `itemData` after player roll; caps (100 dice / 1e6 sum) enforced only on the master; `DiceSnapshot` decode unbounded.
- Map: `MapEntryModel.rect` pads only top/left; `degrees` not persisted; pending `PhotoReplacement` is global; `validateLinks` can overwrite newer edits; rescale ignores walls/pointers.
- Entry type auto-detection turns "5-10" / "3/4" text into number entries.
- Weather lightning random range traps below 100 pt width.
- Character link resolution is exponential on fan-out graphs (depth 10 only).
- `copyReplacingItem` is remove-then-copy [STILL OPEN from CODE_AUDIT_19 §7.1]; `removeEmptyDirectory` ignores only `.DS_Store`.

### 5.13 Switching local ↔ iCloud store moves no data (Low, documented in UI)
- `Modules/CoreRPG/FileViews/StorageOptionEditor.swift:56-77`.

### 5.14 Intent entity suggestions
- `suggestedEntities` takes `prefix(20)` before filtering (`Modules/CoreRPG/Controllable/ItemEntityQuery.swift`, Low).

---

## 6. Security

### 6.1 Hidden pin data in every live `.mapState`
- **Location:** `Modules/MapRPG/Controller/GameController+Sync.swift:27-34` (`mapUpdateResult` encodes `[pointer] + model.mapPins`); `Modules/MapRPG/Model/MapPinModel.swift:125-139` (`encode` always writes name, photoId, characterId, location) [verified]
- **What:** `redactedForNonMaster()` is applied only to the content update (`MapUpdatePayload.swift:34`); the live state text is built from the unredacted pins.
- **Why:** Players receive name, portrait id, linked character id and position of hidden pins on every GM edit and join; the leaked `photoId` also feeds §6.4. Needs a debugger/console/disk to read.
- **Action:** Build the player-bound state from a redacted copy (blank or omit `!isShown` pins); keep GM views on full data.
- **Severity:** High [INCOMPLETE FIX of CODE_AUDIT_Map §6.1]

### 6.2 Map package for players is unredacted
- **Location:** `Modules/MapRPG/Controller/GameController.swift:346-370`; `Modules/CoreRPG/Controllable/GameControllable.swift:252-275`; callers `Modules/GameRPG/Controller/MasterController+MapMessages.swift:51`, `MasterController+Messaging.swift:161`; `Modules/MapRPG/Controller/ExportController.swift:63-71` [verified]
- **What:** The reveal/show path exports the full item via `rootExportController.export` with no redaction; the exporter adds every pin's photo regardless of `isShown`.
- **Why:** Hidden room text and hidden pin data are in the package a player device receives.
- **Action:** Apply the same non-master redaction to the exported item and filter pin photos by `isShown`.
- **Severity:** High [INCOMPLETE FIX of CODE_AUDIT_Map §6.1]

### 6.3 Player group events relayed before validation
- `Modules/GameRPG/Network/GameNetworkController+MasterDelegate.swift:35-62`; `+SharePlayDelegate.swift:93-101`; `GameNetworkModel+Shape.swift:55-68`. Shape-only check, payload up to 100 MB relayed to all peers; `GameRelayAdmission` from CODE_AUDIT_18 §6.2 no longer exists. Cap payload per kind inside the shape predicate (without reviving an admission layer). **Medium** [INCOMPLETE FIX of CODE_AUDIT_18 §6.2]

### 6.4 Asset requests answered for any item id
- `MasterController+{Photo,Pdf,Space,Dice,Map}Messages.swift` (~:32-36; Map :44-61). Serve only ids in a per-game presented set. **Medium** [STILL OPEN from CODE_AUDIT_17 §6.3]

### 6.5 Low
- Generator prompt marker stripping is single-pass (`RunGeneratorIntent.swift`, no tools configured so impact is content only).
- Foundry import inserts unescaped strings into markdown (`RuleModel+FoundryFactory.swift`).
- `SpaceViewer` loads untrusted USDZ on the main actor with no size cap (Medium, `SpaceViewer.swift:564-600, 685-710`).
- Info.plist: `UIBackgroundModes` includes `fetch` with no fetch handler found; `InfoTV.plist` carries macOS sandbox keys; confirm privacy-manifest coverage for the extensions.
- Unverified StoreKit transactions are never finished (`InAppModel.swift:95-105`).

---

## 7. Performance

- Statistics: every event is stored and synced; launch/finish fetch all events; per-event dedup count fetch without a matching index (Medium, plausible, not measured) — `GameStatisticsDataController.swift:121-155, 202-245`.
- Large hex grids: quadratic rebuild and one observable needle model per vertex (Medium) — `MapEditorSession+Content.swift:29-95`, `MapRoomCanvas.swift:80-93, 244-264`.
- Every GM edit sends the full map state, no coalescing (Low) — `GameTableModel+Broadcast.swift:54-59`.
- Intent entity queries and Spotlight reindex build every entity on the main actor (Low).
- Weather views allocate their animation state per parent re-evaluation (§8.1, Medium).
- Sync sheet recomputes the restricted plan in `body` (Low); `DiceConfiguration` writes the full snapshot to App Group defaults per roll (Low).

---

## 8. SwiftUI / UI

Full pass against the SwiftUI-expert skill (state, identity, composition, performance, accessibility, localization, animation, environment, charts). Method: checklist scans over all of `Modules/` and `Sources/` (non-test), then reading every hit that was not obviously benign. The CLAUDE.md view rules are followed (see §4); no `ObservableObject`, `GeometryReader`, `ScrollViewReader`, `tabItem`, one-parameter `onChange` or `AnyView` outside the accepted `ViewControllable` returns. The scan results that came back clean are listed in §8.3 so the next audit does not repeat them.

### 8.1 Weather views allocate their animation state on every parent re-evaluation
- **Location:** `Modules/WeatherRPG/Weather/StormView.swift:50-55`; same pattern `CloudsView.swift:12-17`, `StarsView.swift:11-13`, `LightningView.swift:~91` [verified for StormView]
- **What:** `State(initialValue: Storm(...))` in `init` runs the `Storm` initializer (one `StormDrop` object per unit of `strength`, plus an image lookup) every time `WeatherViewer.body` re-evaluates, then SwiftUI keeps only the first instance and discards the new one. The file's own comment says the state is kept across re-evaluations, which is true for the stored value but not for the allocation.
- **Why:** While a weather slider is dragged, up to 1000 `StormDrop` objects are created and thrown away per frame of editing. Not measured. Together with §5.3, `strength` is also unbounded.
- **Action:** Build the storm lazily (create it in `.onAppear`/`.task` or on the first `onChange`), or cap `strength` to the slider range; apply the same to the clouds and lightning views.
- **Severity:** Medium [NEW]

### 8.2 Accessibility and layout (Low)
Icon-only buttons are labelled; `.fixedSize()` in 3 places (`MapPopover.swift:40,74`, `SecondaryTabBar.swift:18`); the map canvas hit layer has no accessibility representation, so VoiceOver cannot select rooms; widget recommendation string "Standard Dice Roller" not localized (`DiceRollerProvider.swift:62-65`); 129 `printViewChangesOnlyInDebug()` calls in view bodies; `State(initialValue:)` copy-in in `ItemHeaderEditorView` is an intentional editor draft (a remote edit arriving during editing is overwritten on save — not filed).

### 8.3 Skill checklist: scanned and clean (no finding)
- **State:** no non-`private` `@State`; the only non-private `@FocusState` hits are `@Previewable` preview locals. Every `State(initialValue:)`/`State(wrappedValue:)` seed in `init` was read: editor drafts (`ItemHeaderEditorView`, `ValuePickerEditor`), one-time scroll/expand seeds and preview fixtures are intentional; only the weather views allocate heavy objects there (§8.1). `MeshAnimationView` seeds 25 random colours, which is negligible, and honours Reduce Motion.
- **Identity:** no `.indices`/`\.offset`/`hashValue`/`UUID()` identities in `ForEach`; the one `\.offset` use (`FoundryImportView.swift:498`) is documented as intentional (repeating warnings). 38 `id: \.self` uses are enums, constant literals or ids; `BattleRoundSettingsView` pattern names are de-duplicated on add (`BattleRoundSettingsModel.addName`, `MapRPG/BattleRound/BattleRoundSettingsModel.swift:53-64`). `ProConListView` (Apple sample code, device-only) uses `\.self` on strings; harmless there.
- **Animation:** every `.animation` call carries `value:`; 145 files read `accessibilityReduceMotion`; all repeating animations (weather, mesh) honour it.
- **Environment:** `@Entry`/key defaults are stable constants; closure-carrying environment values (`RouteActions`, `PdfViewerActions`, `MapActions`, `SharingFeatureActions`) are wrapped with an explicit identity so they do not invalidate every reader — a deliberate design, documented in `EnvironmentActionIdentity.swift`.
- **Localization:** no `Text`/`Label`/`Button`/`Section`/`Toggle`/`Picker` literal or `.navigationTitle`/`.accessibilityLabel`/`.help`/`.alert` literal without `bundle: .module` in `Modules/` (the two hits, `StorageOptionEditor.swift:93` and `GameScreenLayer.swift:51`, are `#Preview` content); no `String(localized:)` without a bundle.
- **Body work:** a scan of every `var body` for sort/filter/group/decode/regex found only cheap or already-fixed cases (`FoundryImportView.swift:513` groups once per body, fixed in CODE_AUDIT_21 §7.10; it re-evaluates only on its own state change).
- **Accessibility of custom gestures:** pins expose Move Left/Right/Up/Down, Open Pin Actions and a toggle action (`MapPinView.swift:176-205`); photo and space viewers carry labels/actions. Open gaps are the ones in §8.2.
- **Charts:** six `Charts` views; marks carry `accessibilityLabel`/`accessibilityValue`. No audio-graph descriptor, which is optional.
- **Other:** one `onTapGesture` (`InspectorRowView.swift:73`, needs `count: 2`, with accessibility actions beside it); one `.cornerRadius` (`GameStatisticsDiceChart.swift:25`) is `ChartContent.cornerRadius`, not the deprecated `View` modifier; no fixed `.font(.system(size:))`; 32 `ScaledMetric` uses; horizontal `ScrollView` + `HStack` + `ForEach` strips (dice bags, battle strips) are short lists; `printViewChangesOnlyInDebug()` is `#if DEBUG`.

### 8.4 Fixed white text on translucent system colours (Low)
- **Location:** `Modules/CoreRPG/Rows/ColoredEditRowModifier.swift:12-21`; callers `GridLabelView.swift:52`, `DiceQuickEditor.swift:83`, `PlayListView.swift:43`; similar `.foregroundStyle(.white)` over materials in `Modules/SpaceRPG/Record/*` and `BattleParticipantColumn.swift:51-55`
- **What:** `rowEditColor` forces `.white` text on `backgroundColor.opacity(0.7)`, including `.teal`, `.blue` or a caller-supplied colour. The effective background is the 70 % colour blended with whatever sits under the row.
- **Why:** In light appearance, teal at 70 % over a light surface gives white text well under 4.5:1 contrast; Increase Contrast is not consulted. Plausible from the colour values, not measured; the space capture overlays sit on camera/dark content and are fine.
- **Action:** Use the same colour-scheme-contrast environment value the map canvas already reads (`colorSchemeContrast`) to raise the fill opacity, or pick the text colour from the resolved fill.
- **Severity:** Low [NEW]

### 8.5 Default `withAnimation` ignores Reduce Motion in the audio mini bar (Low)
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerMiniBarView.swift:50, 69, 100`
- **What:** Play/skip/hide wrap state changes in plain `withAnimation { }` while the rest of the app routes through the reduce-motion helpers (`Animation.reduced(if:)`, `reduceMotion ? nil : …`).
- **Why:** The transitions are small (bar show/hide, title swap), so the effect is minor; it is the only motion path in the audio module without the check.
- **Action:** Use the shared reduced-motion animation helper for these three calls.
- **Severity:** Low [NEW]

---

## 9. Dead code / duplication / refactor

### 9.1 Duplicated entry-hit `SearchResult` construction (Medium)
Ten copies in `SearchControllable*.swift`, `SearchListController.swift` and CharacterRPG `SearchController.swift`; the Character copy fixes relevance at 100.

### 9.2 Unreferenced code (Low)
About 20 declarations (list in agent B's report: `existingUUIDsInContext`, `endCapture`, four `SceneId` cases, `RouteActions.tabId`, `mainTabId`, `DiceKeys.rollHistory`, `migrationKey`, `activityIdentifier`, `resetSelectedGameMaster`, `addNewPhoto`, `rpgSpotlightIndexer`, `GeneratorCommands`, never-constructed statistic event cases); preview-only views `GameConnectionStatusIndicatorView`, `DisplayMapViewer`, `ItemDetailPreview`, `OptionKeyPressedButton` (+ its global key monitor); dead chat-UI remains in GeneratorRPG (~120 lines).

### 9.3 Dead `import Combine` in 8 files (Low)

### 9.4 Stored relative-url and file-name building duplicated, three drifted sanitizers (Medium)
`FileUrl.swift:238-242`, `CloudFolderScan.swift:28-32`, `EditControllable+File.swift:207-261`, `CloudDocumentController.swift:102`, `ShareImportPhotoController.swift:36` (stores `file:///x` shape).

### 9.5 Other duplication (Low)
Root model `init`/`setUp` copied across 12 modules; name-based UUID derivation ×3; JPEG encode ×2 and ad-hoc `JSONEncoder` ×4 instead of `JSONCoding`; `DropChooseView` ×4 drifted; 44 pt / 800×600 literals; byte-size caps defined in ~6 places and disagreeing (`GameLimits` 100 MB vs SharePlay 64 MB / 47 MB raw).

### 9.6 Organization (Low)
11 intent-support files in CoreRPG `Controllable/` instead of `Intent/`; tvOS `GeneratorRootModel` stub shares a name with the real type; stale "Fix #N" review comments in RolePlayGameKit.

### 9.7 Oversized files / long functions (Low) [STILL OPEN from CODE_AUDIT_21 §9.12, owner declined big refactors]
`ImportControllable.swift` 1068, `EditControllable.swift` 1022, `ItemControllable.swift` 710, `GameRoot.swift` 710, `PlayerNetworkController.swift` 622; functions >150 lines listed in agent B's report (e.g. `GameTableView+VisionOS.swift:45`, `ExternalImportReviewSession.swift:86`).

### 9.8 Localization check fails with 19 issues (Low) [STILL OPEN from CODE_AUDIT_21 §8.2]
11 stale `InfoTVPlist` keys, 7 stale GameRPG keys, "Player Game Screen" untranslated; the script's bundle/`stringSet` hits are false positives.

---

## 10. Cross-cutting recommendations

1. **Redaction at the send boundary.** Three of the five Highs are the same pattern (data built from the full model, role-blind). Put one recipient-role-aware redaction step in front of every player-bound map payload, including the package export.
2. **Fix at every site of the same shape.** §6.1/§6.2 and §5.1 repeat the earlier pattern: the fix landed at one call site, not at all of them.
3. **Clamp numeric input and decoded values once** (`DiceValueLimit`-style) instead of per field; §5.3, §5.5, §5.6 are the same root cause.
4. **Sync-era invariants:** any cleanup that deletes rows (statistics prune, folder prune, cloud scan removals) should be scoped to this device's data or revalidated at apply time.

---

## 11. What was NOT audited

Instruments traces and view-invalidation profiling (§8 is a static pass, so §8.1 and the `body`-work findings are unmeasured); visionOS/tvOS focus-engine behaviour; `Tests/` beyond skimming; Core Data/CloudKit schema migration beyond the cloud-scan commit; performance profiling; build settings and scheme structure; third-party/SPM internals (RPGTabletopGameContent); localization wording; Metal (none in repo); runtime behaviour of every Medium/Low finding.

---

## 12. Verification

- **§6.1** — opened `Modules/MapRPG/Controller/GameController+Sync.swift:27-34` and `Modules/MapRPG/Model/MapPinModel.swift:125-139`: `mapUpdateResult` encodes all `model.mapPins`, `encode` writes name/photoId/characterId unconditionally.
- **§6.2** — opened `Modules/MapRPG/Controller/GameController.swift:346-370` and `Modules/CoreRPG/Controllable/GameControllable.swift:252-275`: package built by `export` without redaction; grep shows `redactedForNonMaster` only in `MapUpdatePayload.swift:34` and its definition.
- **§5.2** — opened `CloudFolderScan.swift:150-175, 320-340`, `CloudFolderScanModel.swift:15-30, 55-90`, `CloudScanController.swift:30-75`: subfolder failure `continue`s, `deselected` starts empty, `apply` trashes `plan.removals`.
- **§5.3** — opened `WeatherModel.swift:68-71`, `WeatherViewer.swift:93-99`, `Storm.swift:43`: unbounded decode, `Int(Double)`, `0 ..< strength`.
- **§5.1** — opened `CharacterRPG/Controller/SheetController.swift:1-110`, `MapRPG/Controller/SheetController.swift:1-66`, `SimpleSheetController.swift`, `LinkRegisterListModel.swift:84-86`: traced only, not executed.
- **§5.5** — opened `BattleNumberInput.swift:8-26` (`Int(asciiMinus)` accepts any Int) and `GameController+EntryResolution.swift:181-214`: `Double(Int.max)` is 2^63, `modifier == modifier.rounded()` holds, `Int(modifier)` at :201 traps for an out-of-range value.
- **§8.1** — opened `StormView.swift:8-66` and `Storm.swift:30-45`: `State(initialValue: Storm(...))` in `init`, drop loop in `Storm.init`.
- **§3.1** — opened `BatteryView.swift:10-140`: `init()` starts monitoring, disappear stops only the kept instance.
- **§5.4** — opened the model XML (`syncable="YES"` ×3), `DataBaseModel.swift:39` (GameRPG bundle in the merged model) and `CloudKitCoreDataPersistenceController.swift:52-70` (one CloudKit container for the merged model): statistics rows sync. The two-device interleaving itself was traced, not run.
- **§8.3–§8.5** — scan scripts and outputs in the session scratchpad (`s2.sh`–`s5.sh`, `body.awk`); opened `MapPinActionView.swift:1-190`, `MapPinView.swift:176-205` (grep), `BattleRoundSettingsModel.swift:1-90`, `MeshAnimationView.swift:1-66`, `ColoredEditRowModifier.swift:1-21`, `FoundryImportView.swift:440-560`, `GameStatisticsDiceChart.swift:1-60`. §8.4 and §8.5 are read from the code only; neither was rendered or run.
- **Build ground truth** — logs in the session scratchpad (`build-ios.log`, `build-visionos.log`, `build-macos.log`, `build-tvos.log`).

---

## 13. Status after the fixes (2026-10-30)

Everything is uncommitted on `develop`. "Fixed" means the code is changed and the four schemes build; the runtime result is listed under Verification below. §9.7 was excluded on request.

| § | Status | What was done |
|---|--------|---------------|
| 3.1 | Fixed | `BatteryMonitor.init()` no longer starts monitoring (the view's `.onAppear` does); the macOS poll loop ends when the task is cancelled or the monitor is gone. |
| 3.2 | Partly | Fixed: `RemoteDownloadsInFlight` waiters stop on cancellation (continuation resumed by the download or by the cancel); `GameRoot.stopGame` clears its task by token from inside the teardown; `GameRoot.startGame` has a re-entrancy guard; `ItemProviderImporter.loadDataRepresentation` cancels its `Progress`; PDFKit find keeps the current scan's matches instead of draining them, so a stale end notification cannot take the new scan's matches; `GeneratorController.request` waits for the cancelled predecessor. Not changed: intent join poll (bounded to 10 s, `Observations` would need a task group over main-actor classes), synchronous RealityKit loads (already cached per die type; `Entity.load` has no async variant that keeps the TabletopKit setup order). |
| 4 | Partly | Fixed: `defaultTabBarPlacementAll` passes its argument; search highlight is diacritic-insensitive like the filter; NSString bridging in `CloudFolderScan` replaced by `URL`. Not changed: UIKit haptics (a `.sensoryFeedback` trigger does not fire when the view is dismissed in the same transaction, which both call sites do) and the numeric padding/spacing literals (many intentional). |
| 5.1 | Fixed | `SheetLinkGuard` (module + item stack) in all six sheet controllers. |
| 5.2 | Fixed | Unreadable subfolders are reported and their items left alone; removals start deselected; the sheet says nothing is trashed unless selected. |
| 5.3 | Fixed | `WeatherLimits` clamps at decode, snapshot and view; lightning start range is guarded. |
| 5.4 | Fixed (decision: idle age only) | Recovery closes only sessions idle for 24 h (`interruptedSessionIdleAge`); no schema change, no device id. |
| 5.5, 5.6 | Fixed | `SheetNumberLimit` (±1e12) in the battle input, HP adjust, inline editor, entry resolution, quick editors and `ChangeCharacterValueIntent`. |
| 5.7 | Fixed | Dice: a roll rolls a copy and sums it; table generation caps link occurrences at 500; calculator formats without grouping and with up to 15 digits. |
| 5.8 | Fixed | The PDF summary prompt carries real page numbers; the page label is mapped back from the physical page. |
| 5.9 | Fixed | External entry merge removes only entries that were in the external baseline; retained failed-attach scans keep their `Models` folder (only photos/snapshots are cleared); room thumbnails are rotated by the photo's degrees before the crop and the scale uses the longest edge (EXIF orientation, 8192 px cap); the share extension reads every input item. |
| 5.10 | Fixed | A failed statistics save drops its own pending rows (no `rollback()`, the context is shared); "Full Party" reads `largestPartySize` over all counted sessions; `deleteAll` keeps the running session. |
| 5.11 | Mostly fixed | Apply lists the folder again and drops removals/moves/additions that no longer hold; scan-created items carry a content hash; `isCloud(url:)` uses the path-boundary check. Accepted: deterministic ids across devices (the folder repair from d08817d5b removes the duplicates); apply/listing on the main actor (listing and hashing are `@concurrent`, only the model writes run there). |
| 5.12 | Mostly fixed | Fixed: lightning range; entry type detection (only a plain number becomes a number entry, "5-10", "3/4" stay text); group search in `GameController+EntryResolution` visits each group once; `copyReplacingItem` copies beside the target and swaps; `removeEmptyDirectory` ignores `.DS_Store`, `.localized`, `._*`; audio: removing the current item clears player and Now Playing, scrubber seeks from the thumb (an empty replacement still clears the queue: two existing tests define a replacement that way); dice snapshot decode bounds modifier, compare value and `addDiceEvery`; map: rect margin on all sides, pending photo replacement only shows on its map, `resetImageSize` writes onto the current map, rescale moves walls and pointer. Not changed: dice stale `itemData` and master-only caps (needs a player-side check design), map `degrees` is derived from the photo and recomputed on load (no schema change), list recompute on the main actor. |
| 5.13 | Accepted | Documented in the UI; no code. |
| 5.14 | Fixed | The limit counts included results. |
| 6.1, 6.2 | Fixed | Player-bound state and the package are role-aware: hidden pins are left out of `.mapState`; the package uses `ExportAudience.isPlayerPackage` (a task-local set only in `createGameData`, because Save Game also runs in game mode) to redact the map and to skip hidden pins' photos and characters. |
| 6.3 | Fixed | Group event payloads are capped at 256 KiB in the shape predicate. |
| 6.4 | Won't fix (decision) | Players are trusted peers in this app; asset requests stay open. |
| 6.5 | Mostly fixed | Fixed: generator marker stripping runs to a fixpoint; Foundry text is escaped and split so it cannot form markdown or app links; `SpaceViewer` refuses files above the 256 MiB source limit; `fetch` background mode and the macOS sandbox keys in `InfoTV.plist` removed; unverified StoreKit transactions are finished. Not changed: USDZ parsing still runs on the main actor (RealityKit). The privacy-manifest check for the extensions is open. |
| 7 | Partly | The sync sheet caches its restricted plan. Open (unmeasured): statistics fetch/index, hex grid rebuild, map-state coalescing, intent/Spotlight build on the main actor, per-roll App Group write (two small JSON writes). |
| 8.1 | Fixed | `LazyBox` for storm, clouds and stars. |
| 8.2 | Partly | Widget recommendation is localized. Open: map canvas VoiceOver representation. |
| 8.4, 8.5 | Fixed | `rowEditColor` raises the fill opacity in light mode and with Increase Contrast; the mini bar uses `reduced(if:)`. |
| 9.1 | Fixed | `SearchControllable.entryHit` replaces 6 of the copies (CoreRPG ×5, Character ×1); the remaining ones differ in score or shape. |
| 9.2 | Partly | Removed `existingUUIDsInContext`, `RouteActions.tabId`, `KnownRoutes.mainTabId`, `DiceKeys.rollHistory`, `migrationKey`, `resetSelectedGameMaster`. Kept `activityIdentifier` (matches the Info.plist literal), `addNewPhoto` (public API), `rpgSpotlightIndexer`, `GeneratorCommands`, the preview-only views and the chat UI remains. |
| 9.3 | Fixed | 8 dead `import Combine` removed (3 more files use `Cancellable`). |
| 9.4, 9.5 | Not done | The three sanitizers produce different file names; unifying them changes names on disk and in iCloud, so it needs its own change with migration tests. |
| 9.6 | Fixed | The 11 intent-support files moved to `CoreRPG/Intent/`; stale "Fix #N" comments reworded; the tvOS `GeneratorRootModel` stub is documented (the names never meet, the real one is not built for tvOS). |
| 9.7 | Excluded | On request. |
| 9.8 | Fixed | Stale catalog keys removed (11 in `InfoTVPlist`, 7 in GameRPG); "Player Game Screen" translated. `Scripts/verify_localization.rb` still reports `%@` in GameRPG and the AppShortcuts phrases (false positives, see CODE_AUDIT_21 §8.2). |

**Verification.** MasterRPG for iOS Simulator, macOS (MasterMac), tvOS (MasterTV, generic simulator destination) and visionOS (generic simulator destination) build. The MasterRPG test plan on the iOS simulator (iPhone 18 Pro) passes (`** TEST SUCCEEDED **`) after three test updates: `DataControllerTests.replaceFetchUpdateAndDelete` (Weather) used `time: 3600` and `lightningMaxBolts: 120`, outside the sliders' ranges, which `WeatherLimits` now clamps; `staleMapStatePreservesOnlyOptimisticPlayerFields` used a hidden authoritative player pin, which the master no longer sends; `CharacterValueChangeTests` expects `SheetNumberLimit`. New tests: `GameMessageShapeTests.oversizedGroupEvent`, `GameStatisticsDataControllerTests.keepsRecentlyActiveSessionOpen`, `SheetNumberLimitTests`, `WeatherLimitsTests`, and three type-detection cases in `EditControllerTests`. Not run: anything on a device or in the visionOS/macOS/tvOS test plans; the UI changes (§5.2 sheet text, §5.9 thumbnail rotation, §8.4 row fill, §8.5) were not rendered; the thumbnail rotation direction is derived from `rotationEffect` and has not been compared against a rotated map.
