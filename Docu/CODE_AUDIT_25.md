# MasterRPG Code Audit

Generated 2026-11-14. Scope: ~2,410 Swift files (~314k LOC including tests; ~215k LOC production in `Modules/` and `Sources/`) across the MasterRPG, MasterMac, MasterTV, RPGShare and DiceRollerWidgetExtension targets and 15 feature/framework modules. No `Dead/` or archive directory exists. `Tests/` and `Resources/RPGTabletopGameContent` (SPM) are excluded from the deep review.

Findings cite `path/to/file.swift:LINE` (relative to the repo root; `Modules/...` prefixes are kept) so you can jump straight to them in Xcode. Each item has a recommended action; no code was changed. The repo has had 40+ earlier audits (`Docu/CODE_AUDIT_*.md`); items those audits decided as won't-fix / by-design were not re-reported. Items marked **[OPEN]** are still open in an earlier audit.

**Compiler ground truth (clean builds, Debug, fresh DerivedData):** `MasterRPG` (iOS Simulator), `MasterMac` (macOS) and `MasterTV` (tvOS Simulator) all report `BUILD SUCCEEDED` with **zero Swift compiler warnings**. The only tool output is `appintentsmetadataprocessor: Metadata extraction skipped` (§4.2). `MasterRPG` for visionOS, the widget extension and `RPGShare` were not built separately.

**Headline:** no Critical and no High finding survived verification. The codebase is in very good shape; the remaining items are two data-exposure/data-integrity edge cases (§5.1, §6.1), a handful of robustness and performance items, and a large body of known, deliberate-but-costly duplication (§9).

---

## 0. Status

Updated 2026-11-14. Scope decision: targeted fixes only; the multi-module refactors stay open (§9.1–9.3, §9.7, §9.8, §9.12). Findings not listed are open. Builds: MasterRPG (iOS Simulator and iOS device without signing), MasterMac, MasterTV and visionOS all succeed. The MasterRPG test plan passes in full.

| § | Status | Fix | Tests |
|---|---|---|---|
| 3.1 | Fixed | `ObjectCache.removeFromDisk`, `loadImageFromDisk` and `saveImageToDisk` are `@concurrent nonisolated` async, so disk and JPEG work no longer runs inside the actor that serves memory hits. | Existing `ImageCacheController` tests |
| 3.2 | Fixed | New `KeepAwakeModel` (`Modules/CoreRPG/Model/KeepAwakeModel.swift`) counts owners (`.game`, `.capture`, `.reconstruction`). `GameRoot`, `CapturePrimaryView` and `ReconstructionPrimaryView` use it. | `KeepAwakeModelTests` |
| 3.3 | By design | Doc comment on `runAtDefaultPriority` only. | None |
| 5.1 | Fixed | `CloudDocumentController.createNameUrl` copies without replacing and retries with the next free name on `.fileWriteFileExists` (50 attempts). | `PickerImportNameRaceTests` (incl. concurrent same-name picks) |
| 5.2 | Fixed | `FileManager.moveItem(coordinatingAccessFrom:to:createParentFolder:)`, used by both `CloudDocumentController.move` functions. | None (needs coordinated iCloud access) |
| 5.3 / 5.4 | Fixed | `ValueEntryModel.calculate(on:)` formats decimals through `Calculator.formatNumber`. New `truncatedInt(_:)` is used by the `valueDecimal` setter. | `ValueEntryModelTests` |
| 5.5 | Fixed | `dropLast()` in `CloudDocumentController.init` and `FileBookmarkController.name(from:)`. | `PickerImportNameRaceTests` |
| 5.6 | Won't fix | The delayed toggle is a 100 ms task in a stateless struct. | None |
| 6.1 | Fixed | `MapWallModel.redactedForPlayers()` turns a secret door into a plain closed wall and drops `rawMetadata`; `MapSnapshot.redactedForNonMaster()` maps walls through it. | `MapWallRedactionTests` |
| 6.2 | Fixed | `PhotoAnalysisImage.thumbnail` decodes through `ImageDownsampler.downsampledImage`, so it has the declared-size guard. | `PhotoAnalysisFallbackPolicyTests.declaredOverLimitIsRejected` (real 16,384 x 1 and 16,385 x 1 PNGs) |
| 6.3 | Fixed | `GameBundleBrowserModel.download` uses `GuardedRemoteDownload` with `ByteLimits.maximumSourceFileBytes`. | None (needs network) |
| 6.4 | Kept | `UIFileSharingEnabled` stays, by decision. | n/a |
| 6.5 | Fixed | Scheme kept, as decided. The parser was already defensive; its behaviour is now pinned. | `DeeplinkParsingTests` |
| 7.1 | Fixed | `Calculator` regexes are four static lets built by `makeRegex(symbol:allowLeadingPlus:)`. | Existing `Calculator` tests |
| 7.2 | Fixed | `ItemControllable.libraryFolder(named:in:)` is a single pass that picks the smallest id. | Existing folder tests |
| 7.3 | No change | `MapRoomCanvas` already culls to the visible rect (CODE_AUDIT_21 §7.8). | n/a |
| 7.4 | Not reproducible | No recency arrays found. | n/a |
| 8.1 | Fixed | `AffectedLinkActionPanelView` uses `count { }` and `!contains { }`. The `LinkItemListView` filter stays. | None |
| 8.3 | Fixed | `AudioPlayerBarViewModel.artworkImage` decodes through `ImageDownsampler` (max 1024 px). | `AudioArtworkDecodeTests` |
| 9.4 | Fixed (36 of 43) | The audit's count of 43 was right; the "at least 10 sites" in §9.4 was an undercount. 36 `displayState ==/!= totalHidden` sites now use `isHidden`. Three `entry.displayState` sites (`IntentEntityText` x2, `ChangeCharacterValueIntent`) stay raw because entry types have no `isHidden`. | Existing tests |
| 9.5 | Fixed | `checkFolders`, `validateLinks` and `itemDataCleanup` are requirements of `ItemRootControllable`; `ModuleFolderRepairable` and `AdventureModuleRoot` are typealiases of it. | Existing tests |
| 9.6 | Fixed | New `DeterministicUUID` (`.v5`, `.v8`, `uuid(bytes:)`), used by `FoundryRuleIdentity`, `LinkRegisterModel.occurrenceId`, `CloudFolderScan.derivedId` and `FileUrl.reviewThumbnailKey`. Stored ids keep their values. | `DeterministicUUIDTests` (golden values) |
| 9.9 | Fixed | `LinkControllable.repairingOwnModuleLinks`, used by the Audio, Dice, Pdf, Photo and Space `repairLinks`. | Existing tests |
| 9.10 | Fixed | Deleted 11 unreferenced view files, `OptionKeyPressedButton`, and their snapshot-test blocks (7 files). | n/a |
| 9.11 | Fixed (partly) | Removed `markFileAvailableToCurrentPlayers` and the three module wrappers, `networkMapGeneration`, and `SharePlayDeferredDeliveryQueue.isEvent`. The test-only `addGroup` stays. | n/a |
| 9.14 / 9.15 | Fixed | `Logger.subsystem` falls back to `de.AndreTrettin.GameMaster`; removed `Logger.widget` and `rainbowDebug()`. `Color.random` is not a duplicate (the other is a `ShapeStyle` extension). | n/a |
| 9.16 | Fixed | `PeerFileDataStore.temporaryCopyPrefix` and `temporaryCopyName(of:)`; `journalAttachmentLoadDeadline` uses `GameLimits.SharePlay.journalAddMaximumTimeout`. | Existing tests |

**Open or not done:** §4.1 Combine leftovers (the `CoreDataChangeObserver` threading contract is delicate and the change is style only); §4.2 (`LM_FILTER_WARNINGS=YES` on the resource targets did not silence the tool line, so it was reverted); §9.13 Simple*/Fake* sets; §9.17 compat paths; §9.18 Navigator API; §9.19 naming drift; §9.1–9.3, §9.7, §9.8, §9.12 (refactors, out of the agreed scope).

---

## 1. Executive summary

Top items to address, in priority order (no item reaches Critical or High):

1. **[Medium/Security] Map player package ships GM wall data unredacted** — §6.1 — `Modules/MapRPG/Model/MapSnapshot.swift:154-190`. `redactedForNonMaster()` filters entries and pins but passes `walls` (including secret doors) through, so every player's device holds them.
2. **[Medium/Bug] Picker import can overwrite another item's file on a name race** — §5.1 — `Modules/CoreRPG/Files/CloudDocumentController.swift:132-147`, `FileManager+Coordination.swift:61-67`. A name is reserved with `suggestedFileName`, then copied with a replacing write.
3. **[Medium/Concurrency] `ObjectCache` actor does disk I/O and JPEG work inside the actor that serves memory hits** — §3.1 — `Modules/CoreRPG/Cache/ObjectCache.swift:47-66`. One slow read stalls every module's image cache. Open since CODE_AUDIT_12 §3.2.
4. **[Medium/Bug] Idle-timer flag has no ownership count** — §3.2 — `Modules/GameRPG/Root/GameRoot.swift:466,543,551,670`, `Modules/SpaceRPG/Record/CapturePrimaryView.swift:64-67`. Leaving a capture screen re-enables auto-lock under a running game.
5. **[Medium/Security] Photo-analysis thumbnailer lacks the decode-bomb guard that the shared downsampler has** — §6.2 — `Modules/GeneratorRPG/BasicAI/Providers/PhotoSummaryAnalyzer.swift:190-250`.
6. **[Medium/Maintainability] ~126 near-identical per-module files (~4k LOC)** — §9.1 — `Modules/*RPG/**` (Route, RootView/RootModel, Snapshot, DataModel+Extensions, SheetController, …). **[OPEN]** since audit 15.
7. **[Medium/Maintainability] `DataController` snapshot mapping copied 12 times** — §9.2 — one module already has private clones of a helper (`Modules/PdfRPG/Controller/DataController.swift:43-58`). **[OPEN]**.
8. **[Medium/Layering] ~19 feature-to-feature import edges across ~100 files** — §9.8 — Map imports 8 other modules, Character 5, Table 3.
9. **[Medium/Maintainability] 32 production files over 500 LOC, 16 functions over 120 lines** — §9.12 — e.g. `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift` (1282), `Modules/SpaceRPG/Space/SpaceViewer.swift` (1212).
10. **[Medium/Dead code] ~400 LOC of unreferenced views and ~54 dead or test-only members** — §9.10, §9.11.

---

## 2. Quick wins (≤30 min each)

- **Delete unreferenced views** — `Modules/CoreRPG/TabNavigation/ContentUnavailable.swift` (`SplitContentUnavailable`, duplicate of the live LGViews copy), `ColorSchemeSettingView.swift` (superseded by `ThemeSettingsView`; zero references), `BottomSafety` (zero references). See §9.10.
- **Replace `Bundle.main.bundleIdentifier!`** — `Modules/CoreRPG/Debug/Logging.swift:7` with a constant fallback; a nil bundle id in a test host or tool target would trap. §9.14.
- **Turn off App Intents metadata extraction on the two resource-only frameworks** (`RPGResources`, `RPGResourcesDebug`) — removes the only two build-tool warnings. §4.2.
- **Remove or define `VIEW_DEBUG`** — `Modules/CoreRPG/Debug/RainbowDebug.swift:13` is a permanent no-op; `Color.random` is declared twice. §9.15.
- **Name the `"peer-"` temp-file prefix once** — `Modules/CoreRPG/Files/PeerFileDataStore.swift:94`, `Modules/CoreRPG/Files/FileUrlDataController.swift:338`. §9.16.
- **Route the photo analyzer through `ImageDownsampler.downsampledImage`** — §6.2.
- **Switch the ~10 raw `displayState == totalHidden…` compares to the existing `isHidden`** — §9.4.
- **Move the `.gmz` download onto `GuardedRemoteDownload`** — `Modules/CoreRPG/FileViews/GameBundleBrowserModel.swift:90-102`. §6.3.

---

## 3. Concurrency

The clean iOS/macOS/tvOS builds show no concurrency warnings. All 10 `nonisolated(unsafe)` and 15 `@unchecked Sendable` sites were read: each is guarded by a `Mutex`/lock, immutable, or a documented/audited case (the six `nonisolated(unsafe) static` entity properties in the intents are the known App Intents pattern). No double-resumed or leaked continuations, locks held across `await`, or un-finished `AsyncStream`s were found in the sites read. GCD, `ObservableObject`, `@Published`, `try!`, `as!` and `fatalError` have zero hits in `Modules/` and `Sources/`.

### 3.1 `ObjectCache` serialises memory-cache hits behind disk I/O and JPEG work
- **Location:** `Modules/CoreRPG/Cache/ObjectCache.swift:47-66` (callers: `Modules/CoreRPG/Cache/ImageCacheController.swift:15-62`, `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:59-100`)
- **What:** `loadImageFromDisk`, `saveImageToDisk` and `removeFromDisk` do synchronous `Data(contentsOf:)`, `AKImage(data:)`, `jpegData` and atomic writes inside the same `actor` that serves `cachedObject` and `insertObject`.
- **Why:** One slow disk read or JPEG encode blocks every in-memory cache hit for all modules while it runs. Raised in CODE_AUDIT_12 §3.2; no later audit records a fix or a won't-fix.
- **Action:** Keep the actor for the `NSCache` only and move the three disk methods into `@concurrent` nonisolated functions or a separate disk-cache type.
- **Severity:** Medium

### 3.2 `isIdleTimerDisabled` is written by unrelated owners with no ownership count
- **Location:** `Modules/GameRPG/Root/GameRoot.swift:466,543,551,670`; `Modules/SpaceRPG/Record/CapturePrimaryView.swift:64-67`; `Modules/SpaceRPG/Record/ReconstructionPrimaryView.swift:40-43`
- **What:** The running game sets the flag `true` on start/join and `false` in `performStopGame`; the capture and reconstruction screens set it `true` on appear and unconditionally `false` on disappear.
- **Why:** Leaving a capture/reconstruction screen while a game runs re-enables auto-lock under the live game, and stopping a game does the same to a running capture. `GameRoot` (a model) also calls UIKit directly.
- **Action:** Add one main-actor keep-awake owner with a reference count that all call sites acquire and release.
- **Severity:** Medium

### 3.3 `Task.detached` helpers: waiter task not tied to caller cancellation; blocking lookup on a pool thread
- **Location:** `Modules/CoreRPG/Files/SecurityScopedAccess.swift:66-79` (`runAtDefaultPriority`); `Modules/CoreRPG/Persistence/DuplicateRowOrder.swift:51-53`
- **What:** `runAtDefaultPriority` starts two detached tasks (the work, and a forwarder of `task.value` into a continuation), so a cancelled caller stays suspended until the work returns. `DuplicateRowOrder.recordNames` runs a synchronous `lookUp` that waits on a CloudKit queue inside `Task.detached` with no cancellation handler.
- **Why:** Delays cancellation of image decodes; can block a cooperative-pool thread for as long as the CloudKit queue takes.
- **Action:** Document or tighten how cancellation reaches `work`; make `lookUp` a `@concurrent` function so the work stays structured and cancellable.
- **Severity:** Low

---

## 4. API modernity

The rules in `CLAUDE.md` are followed almost everywhere. Greps over `Modules/` and `Sources/` found zero real hits for `NavigationView` (the 8 textual hits are not uses), one-parameter `onChange`, `String(format:)`, `foregroundColor`, `fontWeight`, `font(.system(size:)`, `replacingOccurrences`, `UIScreen.main`, `ScrollViewReader`, `tabItem`, `Array(…enumerated())` and legacy `Formatter` subclasses. The remaining `GeometryReader` (`GameStatisticsDiceChart.swift:36`) needs a `ChartProxy`, the `.cornerRadius(5)` on line 25 of that file is the Charts API, and the single `onTapGesture` (`InspectorRowView.swift:74`) needs `count: 2` — all allowed by the house rules. Deployment target is 26.0, so the `#available` guards for 26.1/26.4/27 are live.

### 4.1 Combine leftovers where `AsyncStream` / `notifications(named:)` would match the rest of the code
- **Location:** `Modules/CoreRPG/Navigator/Core/Navigator.swift:120,246` and `NavigationSend.swift:101,381` (`PassthroughSubject` + `.onReceive`); `Modules/AudioRPG/Controller/AudioController+Observation.swift:58-60` and `Modules/AudioRPG/Model/AudioPlayerModel.swift:112-124` (Tasks wrapped in `AnyCancellable`); `Modules/CoreRPG/Persistence/CoreDataChangeObserver.swift:3,40-70` (publisher + `.sink` + `@unchecked Sendable` box)
- **What:** A Combine layer remains where a stored `Task` over an `AsyncStream` or notification sequence would match the rest of the code.
- **Why:** `CoreDataChangeObserver`'s `@unchecked Sendable` subscription box exists only to carry a Combine subscription; the `AnyCancellable`-wrapped Tasks are pure indirection. (GroupActivities' `$state.values` and AVPlayer KVO publishers are Apple APIs and are not part of this finding.)
- **Action:** Replace `Navigator.publisher` with an `AsyncStream`, use a plain task list on `AudioPlayerModel`, and iterate `NotificationCenter.notifications(named:object:)` in an owned task in `CoreDataChangeObserver`.
- **Severity:** Low

### 4.2 Two build-tool warnings from App Intents metadata extraction on resource-only frameworks
- **Location:** targets `RPGResourcesDebug` and `RPGResources` (under `Resources/`); clean-build log lines `appintentsmetadataprocessor … warning: Metadata extraction skipped, no AppIntents.framework dependency found`
- **What:** The warning is emitted once per resource-only framework.
- **Why:** These targets contain no intents, so the warning is noise that will hide a future real warning from the same tool.
- **Action:** Disable App Intents metadata extraction for these two targets only.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Picker import can overwrite another item's file on a name race
- **Location:** `Modules/CoreRPG/Files/CloudDocumentController.swift:132-147` (`createNameUrl`, `move(sourceUrl:destinationFilename:)`); `Modules/CoreRPG/Files/FileManager+Coordination.swift:61-67` (`copyItem` writes with `.forReplacing`); callers `FileUrlDataController+Create.swift:209`, `FileUrlDataController+Manage.swift:43`
- **What:** The destination name is reserved with `suggestedFileName` and then written in a separate step with a replacing coordinated copy, so nothing makes the name check and the write atomic.
- **Why:** If two picks (or a pick and a sync/import) resolve the same free name before either copy lands, the second write silently replaces the first item's bytes and deleting either item later deletes the file for both — the exact failure CODE_AUDIT_17 §5.4 fixed for the sequential case. Whether two picker imports can actually run concurrently was not verified.
- **Action:** Copy without replacing and retry with the next suggested name on collision, as `copyFile` already does.
- **Severity:** Medium

### 5.2 `CloudDocumentController.move` coordinates only the destination of the move
- **Location:** `Modules/CoreRPG/Files/CloudDocumentController.swift:172-240`
- **What:** The move path takes a coordinated write on the destination but not on the source.
- **Why:** For iCloud files another process (the iCloud daemon) can touch the source mid-move. Not reproduced.
- **Action:** Use a two-item coordinated write (source and destination), as `FileManager.moveItem(coordinatingAccessFrom:to:)` already does.
- **Severity:** Low

### 5.3 `ValueEntryModel.calculate` serialises decimals with string interpolation
- **Location:** `Modules/CharacterRPG/Model/ValueEntryModel.swift:199-212`
- **What:** A `Double` result is written as `"\(final)"`.
- **Why:** Very small or large values print in exponent form (`1e-05`) which the calculator parser cannot re-read.
- **Action:** Format with a fixed `FormatStyle` (non-grouping, bounded fraction digits) before storing.
- **Severity:** Low

### 5.4 `valueDecimal` setter converts with `Int(newValue)`
- **Location:** `Modules/CharacterRPG/Model/ValueEntryModel.swift:103-111`
- **What:** The setter builds an `Int` from a `Double`.
- **Why:** `Int(Double)` traps for NaN/infinity/out-of-range; likely unreachable from the UI but nothing guards it.
- **Action:** Use a clamping/`Int(exactly:)` conversion.
- **Severity:** Low

### 5.5 Empty module name would trap at `index(before:)`
- **Location:** `Modules/CoreRPG/Files/FileBookmarkController.swift:146`; `Modules/CoreRPG/Files/CloudDocumentController.swift:61`
- **What:** Both strip the last character of a module name with `module.index(before: module.endIndex)`.
- **Why:** An empty string traps. Inputs are module constants today, so this is a latent hazard only.
- **Action:** Use `dropLast()`.
- **Severity:** Low

### 5.6 `LinkController.toggleTextLink` starts an unowned sleep task
- **Location:** per-module `Controller/LinkController.swift` (reported at lines 37-45; e.g. `Modules/PdfRPG/Controller/LinkController.swift:16`), protocol at `Modules/CoreRPG/Controllable/LinkControllable.swift:63`
- **What:** A `Task` that sleeps is started and not stored or cancelled. Line numbers for the body were not re-verified.
- **Why:** The task outlives the view/model that started it and cannot be cancelled on teardown.
- **Action:** Store the task on the owning model and cancel it on teardown, or fold the delay into the caller's existing task.
- **Severity:** Low

---

## 6. Security

No hardcoded secrets, tokens or ATS exceptions were found; join-code/PSK handling and peer-import trust decisions are covered by earlier audits and were not reopened.

### 6.1 Map player package ships GM wall data unredacted
- **Location:** `Modules/MapRPG/Model/MapSnapshot.swift:154-190` (`walls: walls` passes through at line 176); `Modules/MapRPG/Model/MapWallModel.swift:44-47` (`DoorType.secret`); `Modules/MapRPG/Controller/ExportController.swift:56-60`
- **What:** `redactedForNonMaster()` hides unshown entry names/content and invisible pins, but `walls` (including secret doors), `description` and `tags` are copied into the player's snapshot as-is.
- **Why:** The function's own comment says the point is that fog-of-war data must not be present on a recipient's device. Secret-door geometry is exactly that kind of GM-only data. Whether any player UI reads walls is unverified (`MapCanvasGeometryResolver.swift:63` uses them for bounds), and players are treated as trusted peers, so exposure is limited.
- **Action:** Strip or filter walls (at least secret doors) and GM-only description/tags in the player redaction, and extend the redaction test.
- **Severity:** Medium

### 6.2 `PhotoAnalysisImage` thumbnailer lacks the decode-bomb guard
- **Location:** `Modules/GeneratorRPG/BasicAI/Providers/PhotoSummaryAnalyzer.swift:190-250`; shared helper with the guard at `Modules/CoreRPG/Extensions/Image+AKImage.swift:200-217`
- **What:** `PhotoAnalysisImage.thumbnail(from:maximumPixelSize:)` is a private copy of `ImageDownsampler.downsampledImage` but omits the `declaredSize(of:) != .overLimits` check added by CODE_AUDIT_23 §6.7.
- **Why:** An image declaring enormous dimensions is decoded for analysis instead of rejected (relevant for photos arriving from other devices or imports).
- **Action:** Route both `decode` overloads through the shared helper.
- **Severity:** Medium

### 6.3 `GameBundleBrowserModel` downloads with `URLSession.shared` instead of the guarded downloader
- **Location:** `Modules/CoreRPG/FileViews/GameBundleBrowserModel.swift:90-102` (compare `Modules/CoreRPG/Files/GuardedRemoteDownload.swift:1-52`, used by `FileUrlDataController+Manage.swift:230`)
- **What:** The `.gmz` download has no byte cap, no redirect check and the shared session's multi-day resource timeout.
- **Why:** `GameBundleBrowserPolicy` pins the URL to one GitHub repository, so exposure is small; a very large LFS file is still written to disk before any size check, and a stalled transfer keeps its cache file for days.
- **Action:** Route it through `GuardedRemoteDownload.downloadWithResponse` with `ByteLimits.maximumSourceFileBytes` and keep the status check.
- **Severity:** Low

### 6.4 `UIFileSharingEnabled` is on for the iOS and tvOS apps
- **Location:** `Resources/Info.plist:117`, `Resources/InfoTV.plist:98`
- **What:** The app's Documents folder is exposed through Files/iTunes file sharing.
- **Why:** If any local-only game data, bookmarks or temp files live under Documents, users (and anyone with the unlocked device) can read or delete them. Intent unknown — it may be deliberate for import/export.
- **Action:** Confirm it is deliberate and document what lives in Documents; otherwise turn it off.
- **Severity:** Low

### 6.5 Generic `RPG://` URL scheme can collide with other apps
- **Location:** `Resources/Info.plist:48-50`, `Resources/InfoTV.plist:33-35`
- **What:** The custom scheme is the three letters `RPG`.
- **Why:** Another app registering the same scheme can intercept or spoof deep links; custom schemes have no ownership guarantee.
- **Action:** Prefer Universal Links, or at least a longer app-specific scheme, and validate every parameter handled from the URL.
- **Severity:** Low

---

## 7. Performance

### 7.1 `Calculator.apply` builds a new `Regex` per operator step
- **Location:** `Modules/CharacterRPG/Model/Calculator.swift:104`
- **What:** A `Regex` value is constructed on every operator application.
- **Why:** Repeated compilation on every character-sheet recalculation.
- **Action:** Hoist the regexes into static constants.
- **Severity:** Low

### 7.2 `persistMissingFolders` is O(items) per insert
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:328-400`
- **What:** Each insert scans the item list to find missing parent folders.
- **Why:** Bulk imports are quadratic in item count.
- **Action:** Build a folder-id set once per import batch.
- **Severity:** Low

### 7.3 `MapRoomCanvas.orderedSnapshots` iterates all room nodes on every frame
- **Location:** `Modules/MapRPG/Map/MapRoomCanvas.swift:41,80`
- **What:** The ordered snapshot list is recomputed in each draw pass.
- **Why:** Cost grows with room count on large maps while panning/zooming.
- **Action:** Cache the ordered list on the model and invalidate on room change.
- **Severity:** Low

### 7.4 O(n) recency updates in the image cache and `PeerFileDataStore`
- **Location:** `Modules/CoreRPG/Cache/` image cache; `Modules/CoreRPG/Files/PeerFileDataStore.swift`
- **What:** Both maintain recency order with array scans.
- **Why:** Linear cost per access on large caches.
- **Action:** Use an ordered dictionary or an access counter.
- **Severity:** Low

---

## 8. SwiftUI / UI

A targeted pass over the view layer found it clean against the correctness checklist: zero non-private `@State`, no `@FocusState` violations, no `.animation` without `value`, no `.indices`/`\.offset` identities on mutable data (the `id: \.self` uses are over enums, constants or small unique sets), no `font(.system(size:))`, and 190 explicit accessibility labels. `ForEach(…, id: \.self)` over `settings.names(for:)` (`Modules/GameRPG/BattleRound/BattleRoundSettingsView.swift:73`) assumes unique names — not verified.

### 8.1 Per-body filtering of full lists
- **Location:** `Modules/CoreRPG/Inspector/LinkItemListView.swift:184-186`; `Modules/CoreRPG/LGViews/AffectedLinkActionPanelView.swift:47,129`
- **What:** `body` filters the whole folder list (`listModel.list.filter { !$0.isEntryRow }`), and the removal panel filters `linkTree` several times per evaluation.
- **Why:** Linear work on every invalidation of the inspector list; negligible for small lists, noticeable for large libraries.
- **Action:** Derive the filtered array in the list model (cached/observed) or compute it once per body.
- **Severity:** Low

### 8.2 `AnyView` at module seams
- **Location:** `Modules/CoreRPG/Controllable/ViewControllable.swift:58-109` and the 10 per-module `Controller/ViewController.swift` files (72 uses); `Modules/CoreRPG/Navigator/Core/{NavigationModifiers.swift:109-127, NavigationDestination.swift:160-166, AnyNavigationDestination.swift:53}`; `Modules/CoreRPG/ItemList/EntryDataEditable.swift:52,159`; `Modules/CoreRPG/Sheet/SheetEntryView.swift:158`; `Modules/CoreRPG/ItemDetail/ItemDetailContentView.swift:106` (113 mentions in 23 files)
- **What:** Every factory on the cross-module `ViewControllable` protocol, the Navigator destination mapping and the per-entry `additionalRowView` return `AnyView`.
- **Why:** The protocol seam is structural and was accepted in CODE_AUDIT_11 §8.4, 14 §8.5, 15 §8.3, so it should not be reopened as a whole. The avoidable part: `additionalRowView` is implemented by only 2 of 11 modules and the other 9 return `AnyView(EmptyView())`, and it is called up to 3 times per row on the most repeated list row (CODE_AUDIT_13 §8.8).
- **Action:** If row performance is ever measured as a problem, replace `additionalRowView`/`thumbnailRowView` with a concrete wrapper view or an associated-type factory; leave the rest of the seam alone.
- **Severity:** Low

### 8.3 Full-size decode of audio artwork
- **Location:** `Modules/AudioRPG/Model/AudioPlayerBarViewModel.swift:65-77`
- **What:** Artwork bytes are decoded with `UIImage(data:)` / `NSImage(data:)` at native size.
- **Why:** Embedded artwork can be several thousand pixels wide while the player bar shows a small thumbnail; the shared `ImageDownsampler` exists for this.
- **Action:** Decode through `ImageDownsampler.downsampledImage`.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

No `#if false`, no TODO/FIXME/HACK/XXX/`#warning`, no `print`/`NSLog` outside DEBUG and no GCD were found in `Modules/` or `Sources/` (spot-checked).

### 9.1 Per-module boilerplate families still copied **[OPEN, audits 15/16/17/18/21/23]**
- **Locations:** all under `Modules/*RPG/` — DetailRoute, SelectionRoute, `<M>Route`, `<M>RootView`/`RootModel`, `*Snapshot`, DataModel+Extensions, BundleModule, Localization+Extensions, EmptyDropButton, ThumbnailPhotoRow, QuickEntryEditor, SheetController, MockData, Detail*View
- **What:** 126 files are ≥0.9 similar to a sibling module's file after module-name normalisation, about 4k raw LOC.
- **Why:** Every fix has to be repeated per module and copies drift.
- **Action:** Extract generic bases/protocol extensions into CoreRPG (as already done for `ItemControllable`, `EditControllable`, `ImportControllable`, `FileBackedModuleAccess`), family by family, starting with Route and Snapshot.
- **Severity:** Medium

### 9.2 `DataController` snapshot mapping copied 12 times **[OPEN, 15 §9.12]**
- **Location:** `Modules/*RPG/Controller/DataController.swift`; private `repairedUuid` clones at `Modules/PdfRPG/Controller/DataController.swift:43-58`
- **What:** The domain-to-Core-Data mapping skeleton is repeated per module, and Pdf has private clones of a shared helper.
- **Why:** Mapper fixes (CloudKit optionality, UUID repair) must be applied 12 times.
- **Action:** Extract the shared mapping/repair steps and delete the Pdf clones.
- **Severity:** Medium

### 9.3 Intents boilerplate is ~6.9k LOC across 12 `Intent/` folders **[OPEN, 15 §9.14]**
- **Location:** `Modules/*RPG/Intent/`
- **What:** Entities, queries, open/create intents are near-identical per module (shared bodies already live in `CoreRPG ItemIntentSupport`).
- **Why:** Maintenance cost; App Intents constraints limit how generic this can get.
- **Action:** Keep own `perform`/metadata per intent as decided, but share entity/query scaffolding where the framework allows.
- **Severity:** Medium

### 9.4 Raw `displayState == totalHidden.rawValue` instead of `isHidden`
- **Location:** at least 10 sites, e.g. `Modules/CoreRPG/Controllable/ItemControllable.swift:547`, `ImportControllable.swift:597`, `EditControllable.swift`, per-module `LinkController`/`ExportController`; the helper is `ItemListable.swift:34`
- **What:** The hidden check is open-coded though a helper exists. (The audit agent counted 43 with broader patterns; 10 were confirmed with the literal pattern.)
- **Why:** The meaning of "hidden" can drift between sites.
- **Action:** Use `isHidden` everywhere.
- **Severity:** Low

### 9.5 `ModuleFolderRepairable` and `AdventureModuleRoot` duplicate methods that belong on `ItemRootControllable`
- **Location:** `Modules/RolePlayGameKit/Model/ModuleFolderRepairable.swift:23-58`; `Modules/CoreRPG/Controllable/ItemRootControllable.swift:44-66`
- **What:** Two protocols re-declare the same operations.
- **Why:** Adding a module means conforming to both.
- **Action:** Make the methods requirements (with default implementations) on `ItemRootControllable`.
- **Severity:** Medium

### 9.6 Name-based UUID derivation is hand-written four times
- **Location:** `Modules/CoreRPG/Foundry/FoundryRuleModels.swift:701`; `LinkRegisterListModel.swift:89`; `CloudFolderScan` (:144); `SingleReviewFilePropertyRow` (:161)
- **What:** Each site hashes a string into a UUID on its own.
- **Why:** Cross-device determinism is a hard requirement (never `hashValue`); four copies is four chances to differ.
- **Action:** One tested helper with a fixed, documented algorithm.
- **Severity:** Medium

### 9.7 ~8k LOC Foundry reader sits in CoreRPG but is used only by RolePlayGameKit and RuleRPG
- **Location:** `Modules/CoreRPG/Foundry/` (22 files)
- **What:** Import-specific parsing lives in the shared core module.
- **Why:** Every app target and module pays compile cost and the core module's boundary blurs.
- **Action:** Move it to RuleRPG or a dedicated import module.
- **Severity:** Medium

### 9.8 Feature-to-feature import edges
- **Location:** ~19 edges across ~100 files; Map imports 8 modules, Character 5, Table 3
- **What:** Modules import each other directly instead of going through CoreRPG/RolePlayGameKit.
- **Why:** Contradicts the documented architecture and makes the module graph cyclic-prone.
- **Action:** Resolve other modules through `rootManager.rootModel(for:)` the way RuleRPG's `LinkController` does.
- **Severity:** Medium

### 9.9 Link controllers: `repairLinks` verbatim in 5 modules, `validateLinks` tails in 8
- **Location:** `Modules/*RPG/Controller/LinkController.swift`; `standardToggleResult` used only by Photo and Space
- **What:** Copy-pasted link-repair/validation logic. Audit 15 §9.13 was closed "No change".
- **Why:** Link correctness fixes must be repeated.
- **Action:** Move the shared logic into a `LinkControllable` extension.
- **Severity:** Medium

### 9.10 Unreferenced views (~400 LOC)
- **Locations:** `Modules/CoreRPG/TabNavigation/ContentUnavailable.swift` (`SplitContentUnavailable`, duplicates the live LGViews copy); `ColorSchemeSettingView.swift` (zero references, superseded by `ThemeSettingsView`); `BottomSafety` (zero references); `FlipView`, `SendControlView`, `ModalCloseButton`, `ItemDetailPreview`, `GameConnectionStatusIndicatorView`, `DisplayMapViewer`, `CharacterGenView`, `OptionKeyPressedButton` (referenced only by their own file, previews or generated snapshot tests)
- **What:** Views nothing in production presents.
- **Why:** Dead code that still has to compile and be maintained.
- **Action:** Delete them (and their generated snapshot tests).
- **Severity:** Medium (clean-up; ~400 LOC removed)

### 9.11 About 24 dead and 30 test-only production members **[OPEN, 23 §9.7-10, 24 §9.3]**
- **Location:** includes the `markFileAvailableToCurrentPlayers` chain, `networkMapGeneration`, `SharePlayDeferredDeliveryQueue.isEvent` (`Modules/GameRPG/SharePlay/SharePlayDeferredDeliveryQueue.swift:289`, new), `EditControllable.addGroup`, unused `DisplayStateMask` cases, Generator remnants, Fake/Test helpers compiled into Release
- **What:** Members with no production caller.
- **Why:** Dead code misleads maintainers and ships in Release.
- **Action:** Delete the dead ones; move test-only helpers behind `#if DEBUG` or into the test target.
- **Severity:** Medium

### 9.12 Oversized files (>500 LOC) and functions
- 32 production files exceed 500 LOC. Largest: **`Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:1282`**, **`Modules/SpaceRPG/Space/SpaceViewer.swift:1212`**, **`Modules/CoreRPG/Controllable/ImportControllable.swift:1145`**, **`Modules/CoreRPG/Controllable/EditControllable.swift:1029`**, `FoundryRuleModels.swift:847`, `GameRoot.swift:817`, `ItemControllable.swift:804`, `RPGSharePlayController+ChunkedTransport.swift:746`, `FoundryImportView.swift:714`, `DiceModel.swift:712`. Split along the files' existing `MARK:` sections.
- 16 functions exceed 120 lines: `ExternalImportReviewSession.commit` (255), `SpaceViewer.loadEntity` (245), `EditMapToolBar.body` (242).
- God objects: `MapEditorSession` has 42 stored properties; `AppModel` and `GameTableModel` 52 each.
- **Severity:** Medium **[OPEN, 22 §9.7, 23 §9.6]**

### 9.13 Parallel no-op controller sets
- **Location:** `Modules/CoreRPG/` `Simple*` (8 files, 646 LOC) and `Fake*` (22 files, 980 LOC)
- **What:** Two parallel sets of stub controllers.
- **Why:** Double maintenance when a controller protocol changes.
- **Action:** Keep one set (preferably in a test-support target).
- **Severity:** Low

### 9.14 Logger scatter
- **Location:** `Modules/CoreRPG/Debug/Logging.swift:7` (`Bundle.main.bundleIdentifier!`); 16 `Logger` extensions outside `Logging.swift`; `Logger.widget` unused
- **What:** Mixed category casing, scattered definitions, a force-unwrap on the bundle id.
- **Why:** Hard to filter logs consistently; the force-unwrap traps if the bundle id is absent.
- **Action:** Centralise Logger definitions; use a constant fallback subsystem.
- **Severity:** Low

### 9.15 `rainbowDebug()` is a permanent no-op
- **Location:** `Modules/CoreRPG/Debug/RainbowDebug.swift:13` (`#if VIEW_DEBUG`, flag defined nowhere); `Color.random` declared twice
- **Action:** Define the flag in a Debug-only configuration or delete the helper; drop the duplicate extension.
- **Severity:** Low

### 9.16 Magic constants
- `"peer-"` temp-file prefix at `Modules/CoreRPG/Files/PeerFileDataStore.swift:94` and `FileUrlDataController.swift:338`.
- Timing constants split between `GameLimits` and 10 other files; the 180 s ceiling exists twice.
- Duration-to-seconds is computed 3 times; a non-localised `" s"` suffix at `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:668`.
- **Severity:** Low

### 9.17 Compat/migration paths with no recorded removal release
- **Location:** `Modules/MapRPG/Model/MapWallModel.swift:132-148`, `ValueModel.swift:58`, `GameJoinCodeModel.swift:205`, `BrowserManager.swift:292`, `FilePersistenceController.swift:159`, the `AppModel.navigator` alias, `MapEntryModel.preview`, the deprecated Navigator function
- **Action:** Record a removal version for each, delete those whose condition is already met.
- **Severity:** Low

### 9.18 Unused public Navigator API
- **Location:** `Modules/CoreRPG/Navigator/Core/Navigator.swift`, `NavigationSend.swift`, `NavigationLocked`, `AsyncCallback`
- **Action:** Delete unused public members.
- **Severity:** Low

### 9.19 Naming and folder drift
- `ColorSchemeSettingView`, `FoundryRuleImportModel`, hyphenated Weather files, `CoreFrameworkPackage`, `MyAppPackage`, observable models in `View/` folders, ad-hoc module folders outside the documented convention.
- **Severity:** Low

### 9.20 Unresolved TODOs / FIXMEs
_No findings._ (Zero `TODO|FIXME|HACK|XXX|#warning` hits in `Modules/` and `Sources/`.)

---

## 10. Cross-cutting recommendations

1. **Finish the "generic in CoreRPG" migration.** §9.1, §9.2, §9.3, §9.5, §9.9 are one root cause: eleven parallel modules each carry copies of the same scaffolding. The partial success of `ItemControllable`/`EditControllable`/`FileBackedModuleAccess` shows the pattern works; pick one family per release and delete the copies.
2. **Enforce the module graph.** §9.7 and §9.8 together suggest a lightweight check (script or SPM-style dependency lint in CI) that fails when a feature module imports another feature module or CoreRPG imports a feature module.
3. **One owner for process-wide singletons of state.** §3.2 (idle timer) is the instance found; the same pattern (several unrelated writers to one global flag) is worth checking for audio session, screen brightness and orientation locks.
4. **Make "check then write" atomic wherever names/paths are reserved.** §5.1 and §5.2 are the same shape as earlier file-placement bugs; prefer create-exclusive/no-replace primitives with retry over a separate suggestion step.
5. **Redaction by construction, not by filter.** §6.1 follows a fixed-allowlist approach for player payloads: new fields added to `MapSnapshot` should default to excluded from the player copy until explicitly allowed.
6. **Reuse the guarded decoders/downloaders.** §6.2 and §6.3 are both "private copy of a hardened helper without its guard"; route all image decodes through `ImageDownsampler` and all remote downloads through `GuardedRemoteDownload`.

---

## 11. What was NOT audited

- `Tests/` — not reviewed (only used to check whether production symbols have non-test callers).
- `Resources/RPGTabletopGameContent` and all third-party SPM packages (swift-snapshot-testing, swift-syntax, swift-custom-dump, xctest-dynamic-overlay) — treated as black boxes.
- Build settings and Xcode project structure beyond reading deployment targets and schemes; the project file is the new JSON-format project.
- visionOS build of `MasterRPG`, the `DiceRollerWidgetExtension` and `RPGShare` targets were not compiled for this audit; their entitlements/Info.plist files were only spot-checked (`UIFileSharingEnabled`, URL scheme).
- Runtime behaviour: nothing was run on a device or simulator; all findings are from reading code and the compiler output. §5.1 reachability and §6.1 player-UI use of walls are explicitly unverified.
- Domain algorithms (RealityKit/TabletopKit table, fog-of-war rendering, Foundry importers' mapping rules, dice math) — only obvious issues surfaced.
- Localization and string catalogs, accessibility wording — not assessed (a previous `Docu/LOCALIZATION_ACCESSIBILITY_AUDIT.md` exists).
- The audit agents did not read every one of the ~215k production lines; coverage focused on the hot-spot files listed in the briefs (GameRPG transport/pipeline/controllers, CoreRPG controllables/persistence/files/Foundry, MapRPG pins/canvas, SpaceViewer, GeneratorRPG, DiceModel, RolePlayGameKit import) plus repo-wide greps. Findings in §5.2–§5.6, §7 and §9.1–§9.3, §9.9, §9.13, §9.17–§9.19 come from the agent reports and were **not** individually re-opened by me; line numbers there may be approximate.
- Not covered by this audit because earlier audits fixed or decided them: SharePlay/LAN transport and message-pipeline issues (CODE_AUDIT_Network, _Game_Shareplay, _Game_Photo_Audio), peer import policy gaps (won't-fix, trusted players), the 4-digit join code decision.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference — it should land on the cited line. No finding is Critical or High; the entries below are the Medium findings I opened and confirmed myself.

- **§6.1** — open `Modules/MapRPG/Model/MapSnapshot.swift`, lines `154-190`. `redactedForNonMaster()` rewrites `entries` and `mapPins`, but `walls: walls` is passed unchanged in the returned `MapSnapshot`; `description` and `tags` likewise.
- **§5.1** — open `Modules/CoreRPG/Files/CloudDocumentController.swift`, lines `132-147`: `suggestedFileName(for:filename:)` is awaited and then `move(sourceUrl:destinationFilename:)` copies in a second step; `Modules/CoreRPG/Files/FileManager+Coordination.swift`, lines `61-67`: the copy is coordinated with `writeOptions: .forReplacing`. The check and the write are separate steps. Concurrency of callers was not verified.
- **§3.1** — open `Modules/CoreRPG/Cache/ObjectCache.swift`, lines `47-66`: `loadImageFromDisk`, `saveImageToDisk`, `removeFromDisk` are plain synchronous methods on `public actor ObjectCache` (declared at line 12), next to `cachedObject`/`insertObject`.
- **§3.2** — grep `isIdleTimerDisabled`: `GameRoot.swift:466,543,551,670` (true/false for the game) and `CapturePrimaryView.swift:64,67`, `ReconstructionPrimaryView.swift:40,43` (true on appear, unconditional false on disappear) — eight writes, no counter.
- **§6.2** — compare `Modules/CoreRPG/Extensions/Image+AKImage.swift:206-217` (`guard declaredSize(of: source) != .overLimits`) with `Modules/GeneratorRPG/BasicAI/Providers/PhotoSummaryAnalyzer.swift`, the private `thumbnail(from:maximumPixelSize:)` near the end of `PhotoAnalysisImage` (lines ~190-250): no such guard before `CGImageSourceCreateThumbnailAtIndex`.
- **§9.4** — `grep -rn "displayState == .*totalHidden" Modules --include='*.swift'` returns 10 hits; `isHidden` exists at `ItemListable.swift:34`.
- **§9.10 / §9.15 / §9.14** — `ColorSchemeSettingView` and `BottomSafety` have no references outside their own files; `VIEW_DEBUG` appears only in `RainbowDebug.swift:13`; `Logging.swift:7` contains `Bundle.main.bundleIdentifier!`.
- **§6.4 / §6.5** — `Resources/Info.plist:117` (`UIFileSharingEnabled` true) and `:48-50` (`CFBundleURLSchemes` = `RPG`).

If any finding doesn't reproduce when you visit the line, tell me the specific reference and I'll re-investigate.
