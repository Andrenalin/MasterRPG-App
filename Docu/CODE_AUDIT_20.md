# MasterRPG Code Audit

Generated 2026-09-30 (20th audit) against commit `4ad2a6ea` (`develop`). Scope: about 2,140 Swift files (~276k LOC, of which ~77k LOC are tests) across the MasterRPG (iOS/iPadOS/visionOS), MasterMac, MasterTV, RPGShare and DiceRollerWidget targets and 15 modules. Excluded: `Docu/`, `Snapshots/`, `Integrations/`, `.git`, `.build` and `DerivedData`. `Tests/` got quick reads only. The repo has no `Dead/` folder and no Metal code.

Every finding cites `path/to/file.swift:LINE` and recommends an action. No code was changed.

**Compiler ground truth.** I ran clean full Debug builds into fresh derived-data folders: Swift 6 mode, `SWIFT_STRICT_CONCURRENCY = complete`, toolchain `/Applications/Xcode-27b1.app` (the `xcode-select` default).

| Scheme / destination | Result | Swift warnings |
|---|---|---|
| MasterRPG, iOS Simulator (iPhone 17 Pro) | BUILD SUCCEEDED | 0 |
| MasterRPG, visionOS Simulator | BUILD SUCCEEDED | 0 |
| MasterMac, macOS | BUILD SUCCEEDED | 0 |
| MasterTV, tvOS Simulator | BUILD SUCCEEDED | 0 |

The only other diagnostics were "appintentsmetadataprocessor: Metadata extraction skipped" notices. No tests were run.

**Relationship to earlier audits.** CODE_AUDIT_19 (2026-09-29, base `6a7b5fa0`) was fixed in `e6f856e4`, `b191220f`, `b81664df`, `70b6b064`, `ad4be1b1`, `d77c3caf`, `c0803769` and `4ad2a6ea`. Five feature and fix commits were interleaved with them: `61176e5e` (dice color), `24396394` (sheet spacing), `52f2f531` (reconnect after master restart), `4427ea68` (lost browser games), `9fb4c845` (iCloud download errors, Bonjour losses, spinner) and `3e8e3741` (map action menu popover). This audit had three goals: (1) check the audit-19 fixes against the §13 status table for regressions and incomplete fixes, (2) review the interleaved commits, and (3) do a general sweep. Tags used:
- **[REGRESSION `sha`]**: that commit introduced the defect.
- **[INCOMPLETE FIX of CODE_AUDIT_19 §X.Y]**: an item marked fixed in audit 19 §13 that does not fully work.
- **[NEW `sha`]**: a defect in code added since audit 19.
- Accepted decisions are not reported again: the 4-digit join code, player overwrite by id, hex cells as entries, audit 19 §3.9 (SharePlay join on main; needs Instruments) and §5.10 (folder merge policy; needs a decision).

**How to read verification.** **[verified]** means I re-read the cited lines myself after an agent reported them (see §12). Findings without the tag were read by the reporting agent but not independently re-read; their line numbers are reliable and their severity is that agent's estimate, reviewed by me. "Plausible" means the code path is real but the runtime outcome needs a test or a device.

**Result in one line.** There are no Critical findings and one High one: duplicating an item whose file already has the duplicate's name deletes that file (§5.1). The main pattern is that the new file-handling code (file-to-file copy, create-before-delete, held peer bytes) still resolves *where* a file lives in more than one way. Deletes, copies and replacements can therefore act on the wrong path (§5.1, §5.3, §5.4, §5.9). Paused map sharing still leaks through three more send paths (§5.2).

---

## 1. Executive summary

Top items to address, in priority order:

1. **[High] Duplicating an item can delete the only copy of its file** — §5.1 — `Modules/CoreRPG/Controllable/EditControllable.swift:711-725`, `Modules/CoreRPG/Files/FileManager+Coordination.swift:69-78`. **[verified]** **[REGRESSION c0803769]**
2. **[Medium] Held peer bytes redirect `delete` and `move` to a temp copy, never expire, and are held without a hash check** — §5.3 — `Modules/CoreRPG/Files/FileUrlDataController.swift:188-224,251-275`, `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:205-219`. **[verified]** **[NEW 9fb4c845]**
3. **[Medium] Paused "Share Map" still leaks on player join, presentation replay and map repair** — §5.2 — `Modules/GameRPG/Controller/MasterController+ValueMessages.swift:149-163`, `MasterController+PresentationReplay.swift:87-103`, `MasterController+MapMessages.swift:320-356`. **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_19 §5.7]**
4. **[Medium] Replacing a photo from image data still deletes the old file before the new one exists** — §5.4 — `Modules/CoreRPG/Controllable/EditControllable.swift:727-750,668-674`. **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_19 §5.9]**
5. **[Medium] The LAN brute-force throttle, pending-handshake cap and handshake deadline all turn off if an accepted connection has no `remoteEndpoint`** — §6.1 — `Modules/GameRPG/Network/ConnectionThrottleTracker.swift:31-51`, `Modules/GameRPG/Master/MasterNetworkController.swift:382-409`. **[NEW b81664df]**
6. **[Medium] The Foundry JSON depth guard is still missing on map-wall and rule decodes from CoreData, the network and `.gmz` imports** — §6.3 — `Modules/CoreRPG/Foundry/FoundryRuleModels.swift:26-35`, `Modules/MapRPG/Model/MapWallModel.swift:128-145`. **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_19 §9.17]**
7. **[Medium] The remote-URL check is string-only: DNS names that resolve to private addresses (and redirects to them) pass** — §6.2 — `Modules/CoreRPG/Files/FileUrl.swift:213-280`, `Modules/CoreRPG/Files/GuardedRemoteDownload.swift:49-63`. **[INCOMPLETE FIX of CODE_AUDIT_19 §6.1]**
8. **[Medium] Pin health is shown by color alone and is missing from VoiceOver** — §8.1 — `Modules/MapRPG/Map/MapPinView.swift:145-155,239-264`.
9. **[Medium] The player-journal admission fingerprint is written twice, field for field** — §9.5 — `Modules/GameRPG/Controller/MasterController.swift:30-75`, `Modules/GameRPG/Network/SharePlayPlayerJournalAdmission.swift:44-92`.

---

## 2. Quick wins (≤30 min each)

- **Refuse to copy when the source and destination resolve to the same URL, and name the duplicate with `suggestedFileName`** — `Modules/CoreRPG/Controllable/EditControllable.swift:711-725` (§5.1).
- **Resolve the real file with `deviceUrl` in `delete` and `move`** — `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:212`, `FileUrlDataController+Manage.swift:22` (§5.3).
- **Mark the unsaved insert before `replace`** — `Modules/CoreRPG/Controllable/ItemControllable.swift:112-115` (§3.3).
- **Re-mark `mapsWithUnsharedStructure` when the 3D chain drops its update** — `Modules/GameRPG/Table3D/GameTableModel+Broadcast.swift:84` (§3.1).
- **Await `waitUntilConfigured()` in `play()`** — `Modules/AudioRPG/Controller/AudioController.swift:38-65` (§3.2).
- **Clamp decoded die side counts** — `Modules/DiceRPG/Model/RawDie.swift:167-186` (§5.10).
- **Localize the persistence banner** (bundle, de/th, plural) — `Modules/RolePlayGameKit/View/PersistenceIssueBanner.swift:32-50` (§8.2).
- **Delete `MapPinActionButtons`, the unused `usesGlassEffects` parameter and the orphaned `Sources/RPGShare/InfoPlist.xcstrings`** — §9.1, §9.13.
- **Route the six remaining entities through `EntitySummaryExport.plainText`** — §9.3.
- **Fix the stale doc comments** (ScenesManager, fan platforms, receive-loop lifetime, "file-scoped" helpers) — §9.1, §9.2, §3.9, §9.4.

---

## 3. Concurrency

The compiler reports zero concurrency warnings on all four platforms. Agent A confirmed the audit-19 §3.1–§3.4, §3.6–§3.8 and §3.10–§3.17 fixes against their §13 descriptions, and found the new structured Network API transport (§4.2) correct in its send loop, terminal-outcome handling, listener generations and teardown. The findings below are logic-level ordering, cancellation or lifetime gaps that the type checker cannot see.

### 3.1 Map-content ordering still has three gaps **[INCOMPLETE FIX of CODE_AUDIT_19 §3.12]**
- **Location:** `Modules/MapRPG/Map/RootGameMapViewer.swift:64-86` (unchained `Task` at `:73-77`); `Modules/MapRPG/Map/GameToolBar.swift:327-333` (reshare `Task`); `Modules/GameRPG/Table3D/GameTableModel+Broadcast.swift:81-95` (`guard let self` at `:84`)
- **What:** Three paths bypass the ordered sender:
  - The 2D resume path sends content and then state from a plain `Task`, with no chain.
  - The reshare button sends content outside `mapContentBroadcastTask`.
  - In 3D, a table model released while `networkMapContentUpdate` runs drops the update without re-marking `mapsWithUnsharedStructure`.
- **Why:** A pin edit right after resuming in 2D can overtake the content update and force a repair round trip. A reshare can land after a newer chained update. A 2D↔3D toggle (which builds a new model, audit 19 §5.17) right after a hex toggle can lose the structural update for good.
- **Action:** Send the 2D resume and the reshare through the same per-map ordered sender as `sendMapContent`. Re-insert the map id into `mapsWithUnsharedStructure` before returning at `:84`.
- **Severity:** Low

### 3.2 Some first-play paths still skip `waitUntilConfigured()` **[INCOMPLETE FIX of CODE_AUDIT_19 §3.5]**
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:38-65` (`toggle()` → `play()` at `:49`), `:472` (remote `.play`); `Modules/AudioRPG/Controller/GameController.swift:182-199`; `Modules/AudioRPG/Audio/AudioPlayPauseButton.swift:53`
- **What:** Only `preparePlay` awaits the configure task. On a player device, `loadPlaylist` prepares without playing. The master's `.playAudio` then reaches `togglePlay(id:)` for the current id, which goes straight to `play()`.
- **Why:** At game start, the first track can still begin under the default audio category: the ring switch mutes it and there is no long-form routing. This is the §3.5 bug on a different path.
- **Action:** Make `play()`, or one `startPlayback()` it delegates to, await the session's configuration, so every play path is covered.
- **Severity:** Low

### 3.3 `addNew` marks the unsaved insert after the flush **[verified]** **[NEW d77c3caf]**
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:112-115`; `Modules/CoreRPG/Persistence/CoreDataController.swift:106-117` (`commitInFlight`)
- **What:** `replace` flushes the insert into the shared context before `markUnsavedInsert` runs. A save by another module in that suspension commits the insert first. Nothing then removes the id from the unsaved set.
- **Why:** For the rest of the session, the sync-deletion diffs (`SyncDataControllable.swift:89-92`, `ItemControllable+Sync.swift:109-110`) skip that id. A deletion made on another device is ignored here, and the next local edit re-inserts the row everywhere.
- **Action:** Mark before `replace`, as the synchronous `replace(model:isInsert:)` path already does at `:196-199`.
- **Severity:** Low

### 3.4 Statistics events recorded during `finishSession` are dropped without a log **[INCOMPLETE FIX of CODE_AUDIT_19 §3.17]**
- **Location:** `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:118-126,263-280`; `Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift:145`
- **What:** `activeSessionID` is cleared only after `await dataController.finishSession`. Fire-and-forget `record` tasks that run in that window queue events for a session that is already complete, and `recordEvents` skips them with a bare `continue`.
- **Why:** The last messages of a game can be lost with no trace, which is the half of §3.17 that is still open.
- **Action:** Freeze or clear the session id (or set a "closing" flag) before the final flush, and log skipped events.
- **Severity:** Low (plausible)

### 3.5 `Observations` loops hold `BrowserManager` strongly and depend on an explicit stop **[INCOMPLETE FIX of CODE_AUDIT_19 §3.11]**
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:424-433` (task stored at `MasterNetworkModel.swift:79`); `Modules/GameRPG/Player/PlayerNetworkController.swift:465-477` (`PlayerNetworkModel.swift:93`)
- **What:** `Observations({ browser.games })` and `Observations({ browser.removed })` capture `browser` strongly, and neither controller cancels the stored task on deinit.
- **Why:** A controller released without `stopStreaming()`/`stop()` leaves the loop suspended forever. That keeps the `BrowserManager` and its supervised Bonjour browse alive. It is the leak class §3.11 fixed for four other loops.
- **Action:** Capture the browser weakly in the closure and end the loop when it is gone, or cancel both tasks from an isolated deinit.
- **Severity:** Low (plausible)

### 3.6 After losing the master, a player adopts the master's new session id **[NEW 52f2f531]**
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift:302-310,427-432`
- **What:** `setUpListener()` refreshes the session id from the browser entry for the master's endpoint name while the player is already `.lost`.
- **Why:** Suppose the GM restarts the same adventure with a new join code. The player then takes the new session id but keeps its old passcode. The master redials it up to five times (`scheduleRedial`), every TLS handshake fails, and the player's throttle counts each one as an authentication failure. A new code was meant to mean a new session id precisely so the master would not dial such players.
- **Action:** Refresh the session id only while joining or connected, or accept a new id only when none was known.
- **Severity:** Low (plausible)

### 3.7 `HostingSessionStore` reads and writes the Keychain on the main actor **[NEW 52f2f531]**
- **Location:** `Modules/GameRPG/Master/HostingSessionStore.swift:38,54`; caller `Modules/GameRPG/Master/MasterNetworkController.swift:112`; storage `Modules/GameRPG/Network/JoinCodeStorage.swift:121,138-146`
- **What:** `SecItemCopyMatching` and `SecItemAdd` run synchronously inside `beginHosting`, although `GameJoinCodeModel.swift:75` deliberately moves the same storage off the main actor.
- **Why:** This causes a small main-thread stall each time hosting starts.
- **Action:** Resolve the session id in a `@concurrent` helper before starting the listener.
- **Severity:** Low

### 3.8 The held peer temp copy can go stale **[NEW 9fb4c845]**
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:215-224`; `Modules/CoreRPG/Files/PeerFileDataStore.swift:19-25`
- **What:** `heldPeerFileUrl` reads the bytes under the store lock but checks for and writes `tmp/peer-<id>` outside it. A concurrent `hold` of new bytes deletes the temp file between those steps, and the old bytes are written back.
- **Why:** PDF, 3D and audio readers, which need a URL, can keep showing an older version after the peer re-sent the file.
- **Action:** Name the temp file by content hash or generation, or do the check-and-write under the lock. See §5.3 for the lifetime issues of the same store.
- **Severity:** Low (plausible)

### 3.9 Comments still say the receive loop keeps the controllers alive **[NEW b81664df]**
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:203-205`; `Modules/GameRPG/Player/PlayerNetworkController.swift:262-263`
- **What:** Both comments justify an explicit `cancel()` because "the receive loop holds the controller strongly". Since §3.11/§4.2 the loop binds `self` only per message.
- **Why:** The cancel is still needed, but now because `cancel()` reports the loss. The stale reason will mislead the next refactor.
- **Action:** Reword both comments.
- **Severity:** Low

---

## 4. API modernity

Repo-wide scans found none of the following: `ObservableObject`, `@Published`, `@StateObject`, `withObservationTracking`, `DispatchQueue`, `Task.sleep(nanoseconds:)`, legacy `Formatter` subclasses, `String(format:)`, `replacingOccurrences`, `foregroundColor(`, one-parameter `onChange`, `NavigationView`, `UIScreen.main`, or `@available` guards below 26. Every `@Observable` class is `@MainActor`.

### 4.1 Runtime main-actor escape hatches that isolated conformances could replace **[INCOMPLETE FIX of CODE_AUDIT_19 §4.1]**
- **Location:**
  - 61 `assumeMainActorIsolated` sites in `nonisolated` conformances of `@MainActor` models, for example `Modules/AdventureRPG/Model/AdventureModel.swift` (6), `Modules/PdfRPG/Model/PdfModel.swift:102,113,171,181,241,271` and `Modules/DiceRPG/Model/DiceModel.swift` (5).
  - 14 `encodeOnMainActor` sites (`Modules/CoreRPG/Extensions/Encoder+MainActor.swift:25,32`).
  - 12 `@preconcurrency` conformances, one `IndexedEntityQuery` per module plus `Modules/AdventureRPG/Intent/AdventureEntity.swift:73,93`.
  - `@preconcurrency import`s at `Modules/GameRPG/Table3D/GroupActivityManager.swift:6` and `Modules/SpaceRPG/Record/ReconstructionProgressView.swift:9`.
- **What:** §4.1 moved only `ItemRowTreeModel` and `NavigatorKey` to SE-0470 isolated conformances. The same pattern repeats across the domain models, and `InferIsolatedConformances` is already enabled.
- **Why:** Each site traps at runtime, instead of failing to compile, when a caller is off the main actor.
- **Action:** Pilot `@MainActor` conformances on one module and let the compiler flag any real off-main use. Keep the helpers only where a framework calls synchronously off main. The async `IndexedEntityQuery` requirements probably need no `@preconcurrency`.
- **Severity:** Low

### 4.2 `Task.detached` where `@concurrent` is the idiom (9 sites)
- **Location:** `Modules/CoreRPG/App/CloudContainerCache.swift:53`; `Modules/CoreRPG/Controllable/ImportControllable.swift:145,152`; `Modules/CoreRPG/Controllable/ExportControllable.swift:225`; `Modules/DiceRPG/Controller/GameController+DiceResult.swift:235`; `Modules/GameRPG/Network/GameJoinCodeModel.swift:75`; `Modules/SpaceRPG/Record/AppDataModel.swift:330,422`; `Sources/MasterRPG/MasterRPGApp.swift:33`
- **What:** Each detached task only exists to leave the caller's actor. The rest of the codebase uses `Task { @concurrent in }` or `@concurrent` functions for this.
- **Why:** `Task.detached` also drops task-locals and priority inheritance. This is a consistency issue, not a bug.
- **Action:** Convert these to `@concurrent` functions or `Task { @concurrent in }`.
- **Severity:** Low

### 4.3 Closure-based notification observers and one `NSLock`
- **Location:** `NotificationCenter.addObserver(forName:object:queue:using:)` at `Modules/AudioRPG/Audio/AudioPlayerSession.swift:117,121,133`, `Modules/CoreRPG/App/CloudContainerCache.swift:46-56`, `Modules/CoreRPG/Persistence/ContextFlushLedger.swift:51-57`; `NSLock` at `Modules/PdfRPG/Pdf/PdfWrapperView.swift:120`
- **What:** The audio observers need `assumeMainActorIsolated` (`:128`). PDF search uses `NSLock`, while every other lock in the codebase is a `Mutex`.
- **Why:** Modernity and consistency.
- **Action:** Move the main-queue observers to typed `NotificationCenter` messages or `notifications(named:)`. Keep the ledger's synchronous observer, which must run on the saving queue. Switch the PDF lock to `Mutex`.
- **Severity:** Low

### 4.4 Fixed sleeps still used as synchronization
- **Location:** `Modules/RolePlayGameKit/Model/AppModel.swift:535-541` (the comment says "no fixed cross-window delay is needed" directly above one), `:553-557`, `:601-604`; `Modules/CoreRPG/Controllable/FolderListControllable.swift:332,344`; `Modules/PdfRPG/Pdf/PdfWrapperView.swift:67,181`; `Modules/GameRPG/GameViews/MasterGameScreen.swift:121`; `Modules/GameRPG/GameViews/PlayerGameScreen.swift:90`; `Modules/GameRPG/SetupViews/SelectedMasterView.swift:38`
- **What:** Fixed delays of 150 ms or more stand in for "the destination mounted" or "the item settled".
- **Why:** These race on slow devices, and one comment contradicts its own code.
- **Action:** Use the existing signals where they exist: the navigation replay (audit 19 §3.2), the destination's `.task`, or awaiting `addNew`. Otherwise fix the comment.
- **Severity:** Low

### 4.5 The peer-to-peer flag carried through `initialParameters` is unverified **[NEW b81664df]**
- **Location:** `Modules/GameRPG/Network/NWParameter+GameMaster.swift:16-22,62`
- **What:** `includePeerToPeer = true` is set on the initial `NWParameters`, and the builder then stacks the framer and TCP on top. The audit-19 §13 row for §4.2 notes that the two-device peer-to-peer check is still pending.
- **Why:** If the builder doesn't carry the flag over, joins fail only over peer-to-peer Wi-Fi (no shared access point), which the loopback tests can never show.
- **Action:** Add a unit test that the built parameters keep `includePeerToPeer`, then do the two-device check.
- **Severity:** Low (plausible)

---

## 5. Bugs / logic errors

Agent C confirmed the audit-19 §5.1, §5.4–§5.6, §5.8, §5.11–§5.18 fixes against §13. It also traced sequence merging with `isDeletion` in a single flush and found it correct.

### 5.1 Duplicating an item can delete the only copy of its file **[verified]** **[REGRESSION c0803769]**
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:711-725` (`resetFile(copying:)`), caller `:512-521`; `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:86-115` (`copyFile`); `Modules/CoreRPG/Files/CloudDocumentController.swift:157-159`; `Modules/CoreRPG/Files/FileManager+Coordination.swift:69-78` (`copyReplacingItem`); `Modules/CoreRPG/Model/ItemListable.swift:53-57` (`duplicateName`)
- **What:** The duplicate's file path is "<folder>/<item name>.<ext>", where the name is "<original> Copy". No unique-name check is made. `copyReplacingItem` removes any file at the destination (`:73-75`) before `copyItem` from the source (`:76`).
- **Why:** A file keeps its name when its item is renamed, so the source and destination can be the same file. Example:
  1. Duplicate "Goblin". The copy's file is "Goblin Copy.jpg".
  2. Delete the original and rename the copy back to "Goblin".
  3. Duplicate it again. The destination is "Goblin Copy.jpg", which is the source itself.

  The source is removed, the copy fails, and the item's only file is gone. That failure is reported in the banner, but the file can't be recovered. The old code read the bytes first and reused a same-hash file, so it survived this case.

  Overwriting a *different* same-named file already happened before this change, for example duplicating "Goblin" while an edited "Goblin Copy" exists. That replaces the other item's file, and both items then share it.
- **Action:** Name the destination with `suggestedFileName`, as the picker copy (`CloudDocumentController.move`) does. Refuse the copy when the source and destination resolve to the same URL. Never replace an existing destination during a duplicate. Add a regression test for the rename-then-duplicate sequence.
- **Severity:** High

### 5.2 Paused "Share Map" still leaks on player join, presentation replay and map repair **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_19 §5.7]**
- **Location:** `Modules/GameRPG/Controller/MasterController+ValueMessages.swift:78,115,149-163` (`publishCurrentMapAfterPlayerPinChange`); `Modules/GameRPG/Controller/MasterController+PresentationReplay.swift:87-103` (`replayCurrentPresentation`); `Modules/GameRPG/Controller/MasterController+MapMessages.swift:320-356` (repair bundle, state at `:345`)
- **What:** The §5.7 fix gates the battle, health and roster sends on `isMapStreaming`, but three paths don't check it: the character-sync republish, the replay to a newly ready peer, and the repair recovery bundle. Each sends `networkMapContentUpdate` plus the full `networkMapUpdate`, which carries every room's shown and focus state and every pin.
- **Why:** The GM pauses sharing and reveals a room privately. A player then joins or reconnects, or re-sends their character (which runs the character sync and the `ready(for:)` replay), or a player requests a repair. Any of these sends the private reveal. The roster gate that §5.7 added for the join flow is bypassed by the join flow's own follow-up sends.
- **Action:** While paused, send the last-shared snapshot (or only the non-map payload) from all three paths, and mark the map in `mapsWithUnsharedStructure`. This is the "route every GM map send through one gate" recommendation from audit 19 §10.3. Extend `BattleRoundPausedSharingTests` with a join and a replay while paused.
- **Severity:** Medium

### 5.3 Held peer bytes redirect `delete` and `move` to a temp copy, never expire, and are held without a hash check **[verified]** **[NEW 9fb4c845]**
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:188-203` (`hasDownloadedData`, the only release), `:210-212` (`holdPeerData`), `:251-254,271-275` (both `url(for:)` overloads short-circuit to the held copy), `:244` (`loadData`); `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:88` (`copyFile`), `:205-219` (`delete` resolves through `url(for:)` at `:212`); `Modules/CoreRPG/Files/FileUrlDataController+Manage.swift:22` (`move`); `Modules/CoreRPG/Controllable/ImportControllable.swift:676-682` (hold), `:722-727` (no-hash branch)
- **What:** When a game peer delivers a file that isn't downloaded from iCloud on this device, the bytes are held in a process-wide store. Every reader goes through that store first, including `delete`, `move` and `copyFile`. The bytes are released only when some later `hasDownloadedData` call sees the iCloud file downloaded; nothing clears them at game end. When the existing reference has no content hash, `reusableExistingFileUrl` reuses it and holds the peer's bytes without comparing them.
- **Why:** For an item whose file was delivered by a peer in this run:
  - Deleting it removes only `tmp/peer-<id>` and the bookmark. The real iCloud Drive file is orphaned.
  - Renaming or moving it moves the temp copy into Documents, leaving the original behind as a duplicate.
  - Export, duplicate and viewers read the master's bytes, which may differ from the player's own file, instead of the iCloud file.
  - Every multi-MB map, audio or USDZ delivery stays in RAM for the whole process when offline.
- **Action:**
  - Consult the held bytes only on game read paths. Use `deviceUrl` in `delete`, `move`, `copyFile` and export, and drop the entry on delete.
  - Clear the store when the game ends, and give it a byte budget.
  - Hold bytes only when the hash matches or the item is game-memory only.
- **Severity:** Medium

### 5.4 Replacing a photo from image data still deletes the old file before the new one exists **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_19 §5.9]**
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:727-750` (`resetFile(data:)` calls `resetFile(url: nil)` at `:730`), `:668-674` (fire-and-forget delete); `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:205-219` (detached delete task), `:17-80` (`createNewFileUrl`); callers `Modules/PhotoRPG/Controller/EditController.swift:78-81`, `Modules/PhotoRPG/Photo/InlineImporterView.swift:236`
- **What:** Only `resetFile(url:)` became create-before-delete. `resetFile(data:)` still starts an unawaited delete of the old file and clears the reference, then writes the new file under "<item name>.jpg", usually the same path.
- **Why:**
  - If the write fails, `createNewFileUrl` falls back to memory-only data after the old photo is already gone.
  - If the detached delete runs after the write, it removes the new photo.
  - With identical bytes, `createNewFileUrl` reuses the old path (`:36-45`) and the delete then removes it.

  In each case the item ends up pointing at a missing file on every device.
- **Action:** Route it through the same create-then-`deleteReplaced` flow as `resetFile(url:)`, and skip the delete when the old and new paths are equal.
- **Severity:** Medium

### 5.5 Save-error quarantine never matches child rows, so the retry cap discards unrelated edits **[INCOMPLETE FIX of CODE_AUDIT_19 §5.3]**
- **Location:** `Modules/CoreRPG/Persistence/ContextFlushLedger.swift:108-126` (`failingItemIds`); `Modules/CoreRPG/Persistence/CoreDataController.swift:126-145`; `Modules/CharacterRPG/Model/DataModel+Extensions.swift:7-9`; `Modules/MapRPG/Model/DataModel+Extensions.swift:8-11`
- **What:** `failingItemIds` reads the failing object's own `uuid`. Child entities (`RPGValueEntry`, `RPGMapEntry`, `RPGMapPin`, `RPGValuePhoto`) have their own ids, which never equal the parent item's operation id.
- **Why:** An invalid child never quarantines its item. Every rollback then increments `rollbackCount` on every in-flight operation in every module, so after four failed saves, innocent edits in flight are discarded along with the bad one. The banner shows them only as a count.
- **Action:** Map a failing child to its owning item through the relationship. Count rollbacks only for the failing module or ids.
- **Severity:** Low (plausible)

### 5.6 A full reconciliation now runs mid-session and replaces live models **[NEW d77c3caf]**
- **Location:** `Modules/CoreRPG/Controllable/SyncDataControllable.swift:81-146`; `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:102-129`; `Modules/CoreRPG/Controllable/ItemControllable.swift:371-373`
- **What:** `fetchUpdates()` → `updates(_:)` replaces every item instance with a freshly fetched one and does not touch the link register, unlike `mergeUpdates`. It used to run only at launch; the §5.11 fix now also runs it after any failed `fetchIds` or `fetch(id:)`.
- **Why:** Views and editors holding the old `@Observable` instance stop updating. An edit that is queued but not yet flushed is reverted in memory while the queue still writes it, and "used by" links go stale.
- **Action:** Reconcile only ids (inserts and deletions) and route existing ids through `mergeUpdates`, or skip ids with queued or in-flight operations.
- **Severity:** Low (plausible)

### 5.7 The flush's existence check ignores unsaved inserts and deletes **[verified]** **[NEW d77c3caf]**
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:388-396` (`existingUUIDsInContext`), `:249-290` (flush), `:217-220,346-349` (`delete`/`replace` now flush without saving)
- **What:** The check uses `.dictionaryResultType`, which Core Data documents as reflecting only the store and never pending changes. Before d77c3caf, direct `replace` used a managed-object fetch, which does see pending inserts.
- **Why:** A second flush for an id whose insert is still unsaved creates a second row with the same uuid. Both rows export to CloudKit, and duplicate repair keeps whichever has the lower object URI. An update after an unsaved delete is silently dropped. The window is narrow: `addNew` saves right after its flush.
- **Action:** Include the context's `insertedObjects` and `deletedObjects` in the check, inside the same `perform`.
- **Severity:** Low

### 5.8 Equal `(clock, actor)` pairs make two devices diverge **[NEW d77c3caf]**
- **Location:** `Modules/CoreRPG/CRDT/LWWRegister.swift:47-61,99-102,147`
- **What:** A local write takes `max(now, stored.nextUp)`, and `selfId` is decoded from the register, so every device writes with the same actor id. Two devices whose clocks are behind a stored clock `S` both write exactly `S.nextUp`. At `greatestFiniteMagnitude`, the write keeps `S` itself.
- **Why:** With equal `(clock, actor)`, the merge picks the remote value on both sides, so the replicas swap values and never converge. The §5.5 change removed the bound that used to make this rare.
- **Action:** Stamp local writes with this device's actor id instead of the decoded one, or add a deterministic tie-break on the value. Treat a stored clock at the maximum as clamped.
- **Severity:** Low (plausible)

### 5.9 `deleteReplaced` doesn't check that the old and new locations differ **[NEW d77c3caf]**
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:652-701`; `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:170-203,237-253`
- **What:** After a successful create, the old file is deleted by path. Only `isSameFile` stands in between, and it returns `false` whenever `resourceValues` throws.
- **Why:** If the new reference resolves to the old path (for example an in-module pick whose identifier lookup fails, or an old-style `.icloud` placeholder hiding the real name), the newly attached file is deleted.
- **Action:** Resolve both full URLs and skip the delete when they are equal. §5.1 and §5.4 need the same guard, so share one helper.
- **Severity:** Low (plausible)

### 5.10 A die with `Int.max` sides traps the reroll sort
- **Location:** `Modules/DiceRPG/Controller/GameController+DiceResult.swift:182-192`; `Modules/DiceRPG/Model/RawDie.swift:167-186`
- **What:** `WireShape.number(Int)` decodes any value from a peer or an import, and `die.max + 1` overflows. The §5.15 fix added the same expression for the second die.
- **Why:** An imported or peer-sent dice set crashes the app when reorder runs with the "max dice value" reroll option.
- **Action:** Clamp decoded side counts to a sane maximum at decode time.
- **Severity:** Low

### 5.11 A no-op save clears another module's save error from the banner **[INCOMPLETE FIX of CODE_AUDIT_19 §5.13]**
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:74-79`; `Modules/CoreRPG/Persistence/CoreDataController.swift:510-511`
- **What:** `saveCoreDataThrowing` returns early when the context has no changes, and the caller records that as a successful save.
- **Why:** Module A's save fails and re-queues. Module B's next autosave finds nothing to save and clears the banner, although A's edits are still pending and will fail again.
- **Action:** Clear the save error only after a save that actually committed, for example from `ContextFlushLedger.didCommit`.
- **Severity:** Low

---

## 6. Security

Agent C confirmed that the audit-19 §6.1 literal parsing refuses v4-mapped, expanded and compressed loopback, zone-stripped IPv6, short/hex/octal IPv4, `localhost.` and 224+. It also confirmed that §6.2's share-extension download is capped and checks redirects. Passcode, PSK and join-code logging is limited to lengths, a 4-bit HMAC nibble marked `.private`, or key names.

### 6.1 The LAN throttle, pending-handshake cap and handshake deadline turn off if `remoteEndpoint` is nil **[NEW b81664df]**
- **Location:** `Modules/GameRPG/Network/ConnectionThrottleTracker.swift:31-39` (`shouldAllow`: a nil source is always admitted), `:49-51` (`register`: a nil source is never registered), `:75-77` (`isPending`); `Modules/GameRPG/Master/MasterNetworkController.swift:382,387,402-409`; `Modules/GameRPG/Player/PlayerNetworkController.swift:261,540`
- **What:** The move from `NWConnection.endpoint` (non-optional) to `NetworkConnection.remoteEndpoint` (optional in the SDK interface) made every protection key on an optional value. Nothing checks that an accepted, not-yet-started connection has a `.hostPort` endpoint, and the comment at `:25` only asserts that it does.
- **Why:** If the endpoint is nil or not `.hostPort` at accept time, three protections turn off silently: the wrong-code lockout, the global pending-handshake cap, and the master's handshake deadline (`isPending` is always false). The accepted risk of the 4-digit join code (`NWParameter+GameMaster.swift:66-71`) depends on the lockout. The loopback tests never use a real accepted connection's endpoint.
- **Action:** In `TLSPasscodeHandshakeTests`, assert that an accepted connection's `remoteEndpoint` is a non-nil `.hostPort` before the first receive. Log an error on nil. If the endpoint only appears after start, register on the first state update, and key the handshake deadline on the controller id instead of the throttle entry.
- **Severity:** Medium (plausible; needs the test to confirm or clear)

### 6.2 The remote-host check is string-only, so DNS names and redirects to private addresses pass **[INCOMPLETE FIX of CODE_AUDIT_19 §6.1]**
- **Location:** `Modules/CoreRPG/Files/FileUrl.swift:213-280` (`isPublic` at `:259,270`); `Modules/CoreRPG/Files/GuardedRemoteDownload.swift:49-63`
- **What:** IP literals are now parsed correctly, but any hostname is accepted without resolution, and so is every redirect target. Also not refused: NAT64 `64:ff9b::/96`, Teredo `2001::/32`, `192.0.0.0/24` and `198.18.0.0/15`.
- **Why:** A peer-supplied or imported `.url` `FileUrl` whose host resolves to loopback or the LAN still passes `sanitizedForImport`, and `ensureRemoteCache` fetches from the device or LAN. Examples are wildcard DNS services that map a name to `127.0.0.1`, and DNS rebinding. This is the SSRF §6.1 set out to close.
- **Action:** After each transfer, check `URLSessionTaskTransactionMetrics.remoteAddress` for every hop and discard a private result (or resolve first and pin the address). Add the missing reserved ranges. This matches audit 19 §10.6: parse, don't pattern-match.
- **Severity:** Medium (plausible)

### 6.3 The Foundry JSON depth guard is missing on persisted, network and import decodes **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_19 §9.17]**
- **Location:** guard `Modules/CoreRPG/Foundry/FoundryRuleModels.swift:26-35` (enforced only when `userInfo[.masterRPGFoundryJSONDepth]` is set); `Modules/MapRPG/Model/MapWallModel.swift:75` (`rawMetadata: FoundryJSONValue?`), `:128-145` (`MapWallPersistenceCodec.decode` uses plain `JSONCoding.decoder`); `Modules/MapRPG/Model/MapModel.swift:80` (walls decoded inside `MapModel` for network and import); `Modules/RuleRPG/Model/RuleSourceModels.swift:63`; `Modules/CoreRPG/Controllable/ImportControllable.swift:216`
- **What:** Only the Foundry and UniversalVTT readers install the depth counter. Map walls and rule documents reach `FoundryJSONValue.init(from:)` from CoreData, peer payloads and `.gmz` imports through decoders without it. The audit-19 §13 row for §9.17 says "every `FoundryJSONValue` decode gets its depth guard", which is not the case.
- **Why:** A hostile peer or a crafted import with deeply nested wall metadata reaches the unbounded recursion that CODE_AUDIT §5.9 identified as a stack-overflow crash. Foundation's own parser depth limit may bound it; that isn't confirmed, and decoding on a secondary thread's smaller stack makes it riskier.
- **Action:** Enforce the depth inside `FoundryJSONValue` itself, for example with a default counter when none is supplied, or give every decoder that can reach `MapModel`/`RuleModel` the guard. Correct the §13 row. Add a test that decodes a deeply nested wall through `MapWallPersistenceCodec`.
- **Severity:** Medium

---

## 7. Performance

Audit 19's §7.1–§7.3 fixes were confirmed. In particular, the streamed content hash produces the same SHA-256/base64 value as the whole-file hash, so versions stay deterministic across devices. The unbounded peer-byte memory is covered in §5.3.

### 7.1 Formula evaluation inside every pin's body during battle
- **Location:** `Modules/MapRPG/Map/MapPinView.swift:110-115,151`; `Modules/MapRPG/Controller/GameController+BattleSync.swift:144-180`
- **What:** For each combatant pin, `healthPercent` runs two `calculatedValue` link/formula resolutions plus a debug log every time `MapPinContentView.body` runs.
- **Why:** The map canvas re-renders pins while dragging, zooming and on battle ticks, so parsing repeats on the main thread in a hot path.
- **Action:** Cache the percent per combatant in `BattleRoundModel`, updated when the linked entry changes. Or pass it into an `Equatable` leaf view.
- **Severity:** Low

### 7.2 The game timer re-renders every second for an hour:minute display
- **Location:** `Modules/GameRPG/GameViews/GameElapsedTimerText.swift:28-43`
- **What:** `TimelineView(.periodic(from: .now, by: 1))` drives a `.hourMinute` format. Since the §9.19 merge, the iOS copy also re-renders its glass capsule every second. The view has no accessibility label.
- **Why:** About 60× more updates than the display needs, and VoiceOver reads a bare "01:30".
- **Action:** Use `.everyMinute` or a 60-second period anchored to the start date. Add a localized "Game time" label.
- **Severity:** Low

### 7.3 `ImageViewer` builds a throwaway `ViewportModel` on every parent render
- **Location:** `Modules/PhotoRPG/Photo/ImageViewer.swift:19,76-84`
- **What:** `State(initialValue: ViewportModel(...))` in `init` allocates an `@Observable` model and computes `image.fixedSize` every time the struct is recreated. Only the first model is kept.
- **Why:** Wasted allocations on a view that re-renders during zoom and pan.
- **Action:** Make it an optional `@State` created in the existing `.onChange(of: imageViewportConfiguration, initial: true)` at `:121-123`.
- **Severity:** Low

### 7.4 `ConversationState` grouping widens chat-input invalidation **[NEW 4ad2a6ea]**
- **Location:** `Modules/GeneratorRPG/Controller/ConversationSessionModel.swift:42-53,79-86`; `Modules/GeneratorRPG/BasicAI/View/ChatInputView.swift:55,91`
- **What:** `isSummarizing` is now one field of a struct property, and `syncConversationState()` writes five fields separately (five mutations) on every engine state change.
- **Why:** `ChatInputView` re-renders on token-count, window and session changes it doesn't use, several times per sync. The cost is small because syncs happen per message.
- **Action:** Assign the whole struct once, guarded on equality, or keep `isSummarizing` as its own stored property.
- **Severity:** Low (plausible)

---

## 8. SwiftUI / UI

Agent D confirmed that the audit-19 §9.19 game-view merge preserves each side's behaviour: the player has no `NavigationStack`, and the side-panel chrome, ornaments, `restoreMainTab` and timer gating are unchanged. It also confirmed that the §5.16 "Open in Window" gating, the §5.17 display-mode retention and the §8.4 SharePlay button cleanup are correct. The rule sweep found no uses of `foregroundColor`, `tabItem`, one-parameter `onChange`, `NavigationView`, `.system(size:)`, `Array(x.enumerated())`, `showsIndicators:`, `ScrollViewReader` or `fontWeight(.bold)`. Every `GeometryReader` is `GeometryReader3D` on visionOS. The single `onTapGesture` needs its tap count.

### 8.1 Pin health is shown by color alone and is missing from VoiceOver
- **Location:** `Modules/MapRPG/Map/MapPinView.swift:145-155` (health ring), `:239-264` (accessibility value)
- **What:** The ring encodes remaining HP only by gray/green/orange/red (`MapPinModel.healthBorderColor`). The accessibility value covers shown, dead, highlighted and active attacker, but not health.
- **Why:** A red/green colorblind game master can't tell wounded from healthy pins, and VoiceOver users get no health information in battle. `accessibilityDifferentiateWithoutColor` is not honoured.
- **Action:** Add the rounded health percent to the pin's accessibility value. When "differentiate without color" is on, add a non-color cue such as ring length or a small badge. The 3D pins share the same color rule.
- **Severity:** Medium

### 8.2 The persistence banner is not localized **[NEW d77c3caf]**
- **Location:** `Modules/RolePlayGameKit/View/PersistenceIssueBanner.swift:32-36,50`; `Modules/RolePlayGameKit/Resources/Localizable.xcstrings:88-90,347-349,658-660`
- **What:**
  - `Button("Dismiss", systemImage:action:)` resolves against the main bundle, not `bundle: .module`. It is the only non-preview control title in Modules without one.
  - The three new catalog entries have no German or Thai translation.
  - `%lld edits were discarded…` has no plural variant.
  - The headline says "Changes could not be saved" even when only a file attach failed.
- **Why:** German and Thai users, including VoiceOver users, see English in the one place that reports data loss. English shows "1 edits". A failed attach is misdescribed.
- **Action:** Build the button label with `Text(…, bundle: .module)`, translate the keys with a one/other plural, and pick the headline from the issue that is set.
- **Severity:** Low

### 8.3 The persistence banner ignores Reduce Motion and is never announced **[NEW d77c3caf]**
- **Location:** `Modules/RolePlayGameKit/View/PersistenceIssueBanner.swift:13-19`
- **What:** The move and opacity transition always animates. Nothing posts an accessibility announcement when an issue appears.
- **Why:** Other game chrome gates its animation on Reduce Motion. A VoiceOver user is never told that edits failed or were discarded.
- **Action:** Skip the animation under Reduce Motion, and post an announcement when `hasIssue` becomes true.
- **Severity:** Low

### 8.4 Pin fan buttons lost their fixed size and their tvOS button style **[REGRESSION 3e8e3741]**
- **Location:** `Modules/MapRPG/View/MapPinActionMenu.swift:215-255` (button at `:224-226`, appearance at `:243-253`); `Modules/MapRPG/Map/MapOverlayFanGeometry.swift:132-133`
- **What:** The old fan button was framed to `MapAdaptiveFanGeometry.buttonSize` (48 pt) and used the TV button style. The new button is sized by `.imageScale(.large).padding(8)`, with `.bordered` circle chrome on visionOS, and uses `.plain` plus interactive glass on tvOS. The fan still spaces its buttons for 48 pt.
- **Why:** On tvOS (larger default font) and visionOS (bordered insets), buttons can exceed 48 pt, overlap in the fan and break the edge-inset math. On tvOS, focus feedback now depends on the glass effect alone.
- **Action:** Restore the fixed frame for the fan variant, or feed the measured size into the fan geometry. Check focus visibility on a tvOS simulator.
- **Severity:** Low (plausible)

### 8.5 The custom map popover has no keyboard dismissal and nests glass inside glass **[NEW 3e8e3741]**
- **Location:** `Modules/MapRPG/View/MapPinActionMenu.swift:39-52` (panel glass), `:145-157,248-252` (interactive glass buttons inside it)
- **What:** The panel is drawn in viewport space rather than as a system popover. MapRPG has no Escape or `onExitCommand` handler, and the glass panel contains interactive-glass buttons.
- **Why:** On macOS and on iPad with a keyboard, a system popover closes with Esc; this one needs a canvas click. Nested glass goes against the Liquid Glass guidance and reduces legibility.
- **Action:** Add an Escape path that clears the expanded pin. Use unglassed buttons inside the glass panel.
- **Severity:** Low

### 8.6 The white spinner can vanish on a focused tvOS button, and the capsule clip cuts off focus effects **[NEW 9fb4c845]**
- **Location:** `Modules/GameRPG/Browser/BrowserRowView.swift:47-51,64-65`
- **What:** `ProgressView().tint(.white)` sits on a `.borderedProminent` button that is also compiled for tvOS, and the button is then clipped with `.clipShape(.capsule)`.
- **Why:** A focused prominent tvOS button turns light, so the white spinner disappears exactly while "Connecting…" is shown. The clip also cuts off the focus lift, the shadow and the macOS focus ring.
- **Action:** Tint the spinner white only on iOS. Replace the clip with `.buttonBorderShape(.capsule)`.
- **Severity:** Low (plausible)

### 8.7 The player report row still covers the content and takes its taps **[INCOMPLETE FIX of CODE_AUDIT_19 §8.1]**
- **Location:** `Modules/CoreRPG/LGViews/GameShareView.swift:32-39,101-118`
- **What:** The row is now hidden when `!isShareable` and sits on a material capsule. It is still a top-trailing overlay with hit testing enabled and hard-coded 6/2 padding.
- **Why:** A tap on any control in the content's top-trailing corner hits the caption instead, and the fixed padding doesn't scale with Dynamic Type.
- **Action:** Disable hit testing on the informational row, or reserve space with `safeAreaInset(edge: .top)`. Use default padding.
- **Severity:** Low

### 8.8 The full-screen lightning `Button` can take focus on tvOS
- **Location:** `Modules/WeatherRPG/Weather/LightningView.swift:26-50` (used from `WeatherViewer.swift:91`)
- **What:** The whole weather canvas is wrapped in a `.plain` `Button` that is hidden from accessibility but still focusable, with no tvOS gate.
- **Why:** The focus engine can land on an invisible full-screen control on Apple TV and trap navigation.
- **Action:** Drop the wrapper on tvOS, or make it non-focusable. Lightning stays reachable through the viewer's accessibility action.
- **Severity:** Low (plausible)

### 8.9 `ForEach(id: \.self)` over import warnings that can repeat
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryImportView.swift:497`
- **What:** Rows are keyed by the warning string, and Foundry imports often produce identical warnings.
- **Why:** Duplicate ids give undefined row identity: dropped or misanimated rows, plus a runtime warning.
- **Action:** Iterate the enumerated prefix keyed by offset (the list is static), or dedupe the warnings with counts.
- **Severity:** Low

### 8.10 Project-rule violations in views
- **Location:**
  - Computed-property subviews: `Modules/GameRPG/GameViews/TabSecondGameView.swift:23-37` (new in 4ad2a6ea), `Modules/CoreRPG/FileViews/SingleReviewFilePropertyRow.swift:93`.
  - UIKit/AppKit colors in SwiftUI: `Modules/SpaceRPG/Record/OnboardingView.swift:25`, `Modules/CoreRPG/Platform/Color+Background.swift:9,11`.
  - Image-only `Button` labels: `Modules/TableRPG/View/TableGenerationEditAsSheetButton.swift:28`, `TableGenerationFooterView.swift:18`, `TableGenerationSaveSendButton.swift:38`. These have an accessibility label, so they break the rule but don't leave a VoiceOver gap.
  - Hard-coded `.padding(N)`: 241. Hard-coded `spacing: N`: 302. New since audit 19: `MapPinActionMenu.swift:146,226`, `GameElapsedTimerText.swift:38-39`, `GameShareView.swift:112-113`, `SheetEntryView.swift` (`spacing: 4`, 24396394), `TableSheetView.swift:37`.
  - `AnyView`: 118, nearly all from `ViewControllable` protocol returns (accepted earlier).
- **What:** These go against CLAUDE.md's SwiftUI rules.
- **Why:** Consistency. Hard-coded spacing doesn't adapt to Dynamic Type or platform metrics.
- **Action:** Extract `GameModuleListPanel` from `TabSecondGameView`. Use `.background`-style semantic styles instead of the UIKit colors. Give the three table buttons a text label. Stop adding new hard-coded paddings; retire the existing ones opportunistically.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

Agent B diffed every split file's declarations in 4ad2a6ea against the originals and found no dropped members. It diffed every modified `.xcstrings`: 170 keys were removed, and none is produced at runtime (checked as literal, prefix and interpolation). It found the JSON coder strategies unchanged, every storage key's string value unchanged, and `BundleIds.legacyProduct` identical to the old literals. It found no `#if false`, TODO/FIXME/HACK or `#warning`, and no `print`, `debugPrint`, `dump` or `NSLog`, in `Modules/` or `Sources/`.

### 9.1 `MapPinActionButtons` orphaned, `usesGlassEffects` dead, fan doc names the wrong platforms **[NEW 3e8e3741]**
- **Location:** `Modules/MapRPG/View/MapPinActionButtons.swift:6-80` (used only by its preview and `Tests/MapRPGSnapshotTests/MapRPGDynamicPreviewSnapshotTests.swift:244-262`); `Modules/MapRPG/View/MapPinActionView.swift:92` (`usesGlassEffects`, never read); `Modules/MapRPG/View/MapPinActionMenu.swift:168-170` (doc says "macOS, tvOS and visionOS"; `MapEditorOverlayLayer.swift:88-114` uses the fan only on tvOS and visionOS)
- **What:** The popover rewrite deleted the only production users, and the new `MapPinActionMenuButton` duplicates the button body.
- **Why:** About 80 dead lines, a snapshot test of UI nobody sees, and a misleading platform comment.
- **Action:** Delete the view, its snapshot and the parameter, and fix the comment.
- **Severity:** Low

### 9.2 `ScenesManager`'s header still documents the deleted APIs **[INCOMPLETE FIX of CODE_AUDIT_19 §9.15]**
- **Location:** `Modules/CoreRPG/ScenesManager/ScenesManager.swift:18,32-35,45-56`
- **What:** The type doc still describes event suppression and shows examples calling `toggleImmersiveSpace()`, `suppressEvents` and `unsuppressEvents`.
- **Why:** A caller following the doc won't compile.
- **Action:** Trim the doc to the remaining API.
- **Severity:** Low

### 9.3 Six entities still hard-code the English plain-text export **[INCOMPLETE FIX of CODE_AUDIT_19 §9.4]**
- **Location:** `Modules/AudioRPG/Intent/AudioEntity.swift:76-82`, `Modules/DiceRPG/Intent/DiceEntity.swift:89-95`, `Modules/GeneratorRPG/Intent/GeneratorEntity.swift:60-66`, `Modules/PdfRPG/Intent/PdfEntity.swift:79-85`, `Modules/PhotoRPG/Intent/PhotoEntity.swift:83-89`, `Modules/SpaceRPG/Intent/SpaceEntity.swift:78-84`; helper `Modules/CoreRPG/Intent/EntitySummaryExport.swift:41-51`
- **What:** Only five modules call the localized `EntitySummaryExport.plainText`. These six keep a copied English literal.
- **Why:** The Shortcuts and share export is English-only in German and Thai for six modules, and the same block exists six times.
- **Action:** Route all six through the shared helper.
- **Severity:** Low

### 9.4 File splits widened access and left stale "file-scoped" comments **[REGRESSION 4ad2a6ea]**
- **Location:** `Modules/CoreRPG/Sheet/SheetEntryView.swift:122-128,144-150` (the internal free functions `resolvedViewController` and `resolvedRowViewer`, with comments saying "kept file-scoped" and "below"); `Modules/CoreRPG/Views/ViewportGeometry.swift:429-464` (`CGFloat`/`CGSize`/`CGPoint` extensions now module-wide); `Modules/DiceRPG/Controller/GameController.swift:24` (`diceUpdateWidgetTask` was `fileprivate`); the `FileUrlDataController` stored properties
- **What:** Moving members across files required `private` → internal, which put two global free functions and CoreGraphics extensions into CoreRPG's namespace.
- **Why:** Namespace pollution and comments that contradict the code.
- **Action:** Move the free functions into a `SheetRootModel` extension or an enum namespace. Update the comments. See §9.9 for the geometry helpers.
- **Severity:** Low

### 9.5 The player-journal admission fingerprint is written twice, field for field
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:30-75` (`PlayerJournalAdmission`); `Modules/GameRPG/Network/SharePlayPlayerJournalAdmission.swift:44-92` (`Fingerprint`)
- **What:** Both files contain the same 20-field projection of `GameNetworkModel`, including the recomputed journal digest. The SharePlay copy also uses `ID` casing (`:46,47,56,95`).
- **Why:** A message field added to only one copy makes the LAN and SharePlay admission checks disagree about whether two messages are the same, which silently drops or double-applies player journal entries.
- **Action:** Extract one `GameNetworkModel.JournalFingerprint` and use it in both places. Fix the casing.
- **Severity:** Medium

### 9.6 `LinkReplaceController.links` and `linksRepair` are near-copies with an unused parameter
- **Location:** `Modules/CoreRPG/Links/LinkReplaceController.swift:10-45` vs `:48-116`; the unused `linkControllable` parameter at `:48`; callers `Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift:71,135`
- **What:** After §9.18 unified the parser, its consumer still carries four copies of the numbering and repair loop.
- **Why:** A numbering fix needs four edits.
- **Action:** Factor out one numbering and repair helper, and drop the parameter.
- **Severity:** Low

### 9.7 Near-identical Extended layout restoration modifiers
- **Location:** `Modules/RolePlayGameKit/View/ExtendedSplitBar.swift:42-64`; `Modules/RolePlayGameKit/View/ExtendedTabBar.swift:66-84`
- **What:** Two private modifiers share the same scene-storage key and the same sync logic. The split variant adds one extra `onChange`.
- **Why:** Restore behaviour must be changed twice.
- **Action:** Use one modifier with a flag.
- **Severity:** Low

### 9.8 Session-model scaffolding is still copied between the generator controllers **[INCOMPLETE FIX of CODE_AUDIT_19 §9.16]**
- **Location:** `Modules/GeneratorRPG/Controller/AdventureGeneratorController.swift:11-58`; `Modules/GeneratorRPG/Controller/GeneratorController.swift:14-60`
- **What:** `lastItemId`, `isLoading`, the error state with `dismissError()`, and the two task/cancel pairs are still verbatim copies.
- **Why:** The same fix-twice risk §9.16 targeted, now smaller.
- **Action:** Move them into `ConversationSessionModel` as requirements with default implementations.
- **Severity:** Low

### 9.9 CoreGraphics validity helpers duplicated across modules
- **Location:** `Modules/CoreRPG/Views/ViewportGeometry.swift:446-464`; `Modules/MapRPG/Map/MapOverlayGeometryHelpers.swift:9-13`; `Modules/MapRPG/Extensions/CGGeometry+MapRPG.swift:9-13`; `Modules/PhotoRPG/Photo/ImageViewportGeometry.swift:125-133`; `Modules/MapRPG/Map/MapPopoverGeometry.swift:128-141`
- **What:** "Finite and positive size" and "finite point" are each written three or four times under different names.
- **Why:** Drift in the NaN and infinity guards that protect the viewport math.
- **Action:** Make the CoreRPG helpers public and delete the module copies.
- **Severity:** Low

### 9.10 Production members used only by tests (18)
- **Location:** `Modules/CoreRPG/Sheet/SheetSearchContext.swift:11-35` (whole public class; its doc claims game windows use it); `Modules/GameRPG/Network/JoinCodeStorage.swift:159-161` (`InMemoryJoinCodeStorage`); `Modules/AdventureRPG/Controller/EditController.swift:352`; `Modules/AudioRPG/Controller/ViewController.swift:67`; `Modules/DiceRPG/Controller/ViewController.swift:87,109`; `Modules/CoreRPG/Sheet/SheetRootModel+Selection.swift:90`; `Modules/CoreRPG/Links/LinkRegisterController.swift:87`; `Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift:117`; `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift:232`; `Modules/MapRPG/Map/MapRoomCanvas.swift:330`; plus 6 more
- **What:** A whole-word search over `Modules/` and `Sources/` finds only each member's declaration. §9.22 searched with tests included, so it missed these.
- **Why:** Tests exercise code the app never runs, and dead API ships in the frameworks.
- **Action:** Delete them, or move the test doubles into the test targets. Where a test covers real logic, point it at the production path.
- **Severity:** Low

### 9.11 `ItemRowTreeModel`'s hand-written `Codable` looks unused
- **Location:** `Modules/CoreRPG/ItemList/ItemRowTreeModel.swift:29-70`
- **What:** Nothing encodes or decodes an `ItemRowTreeModel`, in production or tests.
- **Why:** About 40 lines of upkeep: §9.22 had to edit its coding keys.
- **Action:** Drop the conformance and let the compiler confirm.
- **Severity:** Low (plausible)

### 9.12 Other user-facing strings without German or Thai translations
- **Location:** `Modules/GameRPG/Browser/BrowserRowView.swift:133,182-184`; `Modules/GameRPG/SetupViews/BrowserView.swift:68,72`; `Modules/GameRPG/SetupViews/SharePlayButton.swift:30` (the banner's keys are in §8.2)
- **What:** The join-code error texts and the SharePlay button string have empty de/th entries.
- **Why:** German and Thai users see English in the join flow.
- **Action:** Translate them.
- **Severity:** Low

### 9.13 Orphaned share-extension string catalog
- **Location:** `Sources/RPGShare/InfoPlist.xcstrings`; the target uses `Sources/RPGShare/Resources/InfoPlist.xcstrings` (`MasterRPG.xcodeproj/project.pbxproj:219,2519,2545-2551`)
- **What:** A second catalog with app-level keys (camera, local network, document types) sits in the extension folder but belongs to no target.
- **Why:** Translators maintain a file that never ships.
- **Action:** Delete it.
- **Severity:** Low

### 9.14 Network byte budgets still use decimal literals **[INCOMPLETE FIX of CODE_AUDIT_19 §9.7]**
- **Location:** `Modules/GameRPG/SharePlay/SharePlaySingleQueuePackageSender.swift:84-85`; `Modules/GameRPG/SharePlay/SharePlayDeferredDeliveryQueue.swift:57`; `Modules/GameRPG/Model/GameLimits.swift:12,16`
- **What:** `128_000_000`, `64_000_000`, `1_000_000`, `100_000_000` and `300_000_000` are decimal MB, while the rest of the codebase now uses `ByteUnit` MiB.
- **Why:** Mixed units make the budgets easy to misread or mismatch.
- **Action:** Add a decimal `ByteUnit` case and use it, or document why these limits differ.
- **Severity:** Low

### 9.15 Naming drift
- **Location:** `Modules/CoreRPG/Import/ExternalImportSourceRegistry.swift:14-15,102-107` (`explicitDirectoryURL`, new in e6f856e4); `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:23-24` (`selectedURL`, `selectionID`); `Modules/GameRPG/Network/SharePlayPlayerJournalAdmission.swift:46,47,56,95`; `Tests/CoreRPGTests/LinkHighlightTextModelTests.swift:95` (`hightLightAndBold`); `Modules/GameRPG/Table3D/GamePortableSetup.swift`, `GamePortableRenderer.swift` (files still named `GamePortable*` while the types are `PortableGame*`)
- **What:** New or leftover names break the `Id`/`Url` convention, and the §9.9 type renames left their file names behind.
- **Why:** Search becomes unreliable and the drift continues.
- **Action:** Include these in the next rename pass.
- **Severity:** Low

### 9.16 Commented-out `#if DEBUG` in `TestFixtures`
- **Location:** `Modules/CoreRPG/Fake/TestFixtures.swift:5,51`
- **What:** `//#if DEBUG` … `//#endif`. The fixtures ship in release builds because production `#Preview`s use them.
- **Why:** The comment misleads readers into thinking the fixtures are debug-only.
- **Action:** Delete the two lines, or explain why the file isn't gated.
- **Severity:** Low

### 9.17 Magic panel corner radius repeated 14 times
- **Location:** `Modules/GameRPG/GameViews/GameSidePanelModifier.swift:48,70`, `OverlayGameMenu.swift:130,185`, `OnlyPlayerGameView.swift:23`, `BattleRoundSideOverlay.swift:41`, `Modules/CoreRPG/EntryEditor/TextEditorLinkView.swift:110,114,123`, `Modules/CoreRPG/FileViews/SingleReviewDecisionCardsView.swift:32,34`, and others
- **What:** `14` is the panel radius everywhere, with no named constant, including in the new shared `gameSidePanel` modifier.
- **Why:** A theme change needs 14 edits.
- **Action:** Name it once, for example on `AppTheme`.
- **Severity:** Low

### 9.18 Fixes keep landing in the largest files
- **Location:** `Modules/GameRPG/Controller/PlayerControllerModel.swift` (1,065 → 1,137 lines); `Modules/CoreRPG/Controllable/EditControllable.swift` (827 → 866); `Modules/CoreRPG/Controllable/ImportControllable.swift` (866 → 884); `Modules/CoreRPG/Navigator/Core/NavigationSend.swift` (479 → 502, now over 500); `Modules/GameRPG/Master/MasterNetworkController.swift` (549 → 562); `Modules/GameRPG/Player/PlayerNetworkController.swift` (544 → 560). All compared with `6a7b5fa0`.
- **What:** New fixes grow the biggest files instead of going into new extensions.
- **Why:** Harder reviews, and the §9.23 split effort erodes.
- **Action:** Split `PlayerControllerModel` (the map-repair retry state from d77c3caf) and `EditControllable` (the file-replacement functions behind §5.1, §5.4 and §5.9, as `EditControllable+File.swift`) along their MARK boundaries.
- **Severity:** Low

### 9.19 Test gaps in the new and fixed code
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:652-750` (file replacement and duplication; §13 notes that §5.9 is "not unit-tested"); `Modules/CoreRPG/Controllable/SyncDataControllable.swift:81-146` (§5.11 "not unit-tested"); `Tests/GameRPGTests/TLSPasscodeHandshakeTests` (no endpoint assertion, §6.1); `Tests/GameRPGTests/BattleRoundPausedSharingTests` (no join or replay case, §5.2)
- **What:** The code behind this audit's High and Medium findings has no test coverage for the failing scenario.
- **Why:** §5.1 and §5.4 are both file-path bugs that a temp-directory test would catch. Audit 19 §10.7 asked for a regression test with every High fix.
- **Action:** Add a temp-directory `FileUrlDataController` test fixture and cover duplicate, rename-then-duplicate and replace-from-data. Add the endpoint assertion and the paused-join case.
- **Severity:** Medium

---

## 10. Cross-cutting recommendations

1. **Give file operations one notion of "where the file really is".** §5.1, §5.3, §5.4 and §5.9 each resolve a file's location differently:
   - by name when copying;
   - through the held peer copy in `url(for:)`;
   - by path in `deleteReplaced`;
   - through a detached delete that races the write.

   Add one resolver for the real on-device URL, used by every mutating operation (delete, move, copy, replace). Keep the held peer bytes a read-only overlay for game viewers. Put one "same file?" check (resolved URL equality) in front of every delete and replace.
2. **Finish routing every GM map send through one gate.** Audit 19 §10.3 recommended this, but the §5.7 fix gated three call sites instead. §5.2 found three more, and §3.1 found two more unordered senders. A single master-side "send map X" function that honours pause, ordering and `mapsWithUnsharedStructure` would close all of them and make the next caller safe by construction.
3. **Put guards inside the type they protect, not in its callers.** The Foundry depth guard (§6.3), the die side-count bound (§5.10) and the remote-host check (§6.2) all rely on each caller or decoder remembering to opt in. Validation inside `FoundryJSONValue`, `RawDie` and the download path itself cannot be forgotten.
4. **Security checks that key on optional data should fail closed.** §6.1 admits and never registers a connection whose endpoint is nil. A throttle or deadline should treat a missing key as a single shared bucket, or refuse, not skip enforcement.
5. **Verify §13 claims with a search, not only against the listed sites.** Five of this audit's incomplete fixes are cases where §13 describes the fix as universal ("every decode", "every play path", "every send") but only the originally cited call sites changed: §3.2, §5.2, §6.3, §9.3 and §9.14. Before marking a finding fixed, grep for the pattern it names.

---

## 11. What was NOT audited

- `Docu/`, `Snapshots/`, `Integrations/` (third party), `.git`, `.build`, `DerivedData`.
- Runtime behaviour: no tests, UI tests, Instruments traces or on-device runs. These claims come from reading code and should be confirmed with a test or a device:
  - whether an accepted `NetworkConnection` has a `remoteEndpoint` before it starts (§6.1);
  - whether peer-to-peer Wi-Fi survives the parameters builder (§4.5);
  - whether Foundation's JSON parser bounds `FoundryJSONValue` recursion (§6.3);
  - tvOS focus appearance (§8.4, §8.6, §8.8).
- Algorithmic correctness of the Foundry, UniversalVTT and LevelDB parsers, the CRDT types beyond the clock rules, and RealityKit/TabletopKit scene math.
- The 24 findings in `Docu/CODE_AUDIT_Network.md`: only code changed since audit 19 was re-checked.
- Build settings and scheme configuration, apart from the Info.plist usage keys removed in §9.24 of audit 19, and the internals of the `RPGTabletopGameContent` SPM package.
- `Tests/`: quick scan only (§9.19).
- StoreKit configuration and App Store Connect parity; entitlements beyond what audit 19 checked.
- Localization wording: only missing translations were counted (§8.2, §9.3, §9.12).

---

## 12. Verification

To spot-check a finding, command-click its `path:line` reference in Xcode; it should land on the cited line. I re-read the following lines myself after the agents reported them.

- **§5.1** — `Modules/CoreRPG/Controllable/EditControllable.swift` lines 711-725: the destination is `"<item name>.<ext>"` in the parent folder, with no uniqueness check. `Modules/CoreRPG/Files/CloudDocumentController.swift` lines 157-159: `copy(from:to:)` calls `copyReplacingItem`. `Modules/CoreRPG/Files/FileManager+Coordination.swift` lines 73-76: `removeItem(at: writeURL)` runs before `copyItem(at: readURL, …)`, so equal URLs delete the source. `git show 6a7b5fa0:Modules/CoreRPG/Controllable/EditControllable.swift` lines 512-516: the old path read the bytes with `loadData` first and went through `createNewFileUrl`, whose same-hash check (`FileUrlDataController+Create.swift:36-45`) reused the existing file.
- **§5.2** — `MasterController+ValueMessages.swift` lines 149-163 and `MasterController+PresentationReplay.swift` lines 87-103 send `networkMapContentUpdate` and `networkMapUpdate` unconditionally. The only `isMapStreaming` checks in GameRPG are `MasterController+Control.swift:111`, `MasterController+MapMessages.swift:182` and `BattleRoundController.swift:399`.
- **§5.3** — `FileUrlDataController.swift` lines 251-254 and 271-275: both `url(for:)` overloads return the held temp copy first. `FileUrlDataController+Create.swift` line 212: `delete` resolves through `url(for:)` and then removes the bookmark. `PeerFileDataStore.swift` has no clear-all, and `remove` is called only from `hasDownloadedData` (`FileUrlDataController.swift:199`). `ImportControllable.swift` lines 722-727: the no-hash branch returns the existing reference without comparing bytes.
- **§5.4** — `EditControllable.swift` line 730: `resetFile(data:)` calls `resetFile(url: nil)`. Lines 668-674: that path calls `fileUrlDataController.delete` (a detached `Task`, `FileUrlDataController+Create.swift:209`) and clears the reference before the new bytes are written.
- **§5.7** — `CoreDataController.swift` lines 388-396 use `.dictionaryResultType`, which Core Data documents as ignoring pending changes. Lines 346-349: `replace` now queues and flushes without saving. `addNew` saves right after (`ItemControllable.swift:122-123`), which is why this stays Low.
- **§3.3** — `ItemControllable.swift` lines 112-115: `try await dataControllable?.replace(...)` comes before `markUnsavedInsert`. The synchronous path at lines 196-199 marks it right after queueing, without an intervening flush.
- **§6.3** — `FoundryRuleModels.swift` lines 26-35: the depth check applies only when `decoder.userInfo[.masterRPGFoundryJSONDepth]` is present. `MapWallModel.swift` lines 128-145 decode with the plain `JSONCoding.decoder`.
- **§6.1** — `ConnectionThrottleTracker.swift` lines 31-33 (a nil source returns `true`) and 49-51 (a nil source is not registered). The SDK interface (`Network.swiftinterface`, `NetworkConnection`) declares `remoteEndpoint: NWEndpoint?`. Whether it is nil at accept time is **not** verified.
- **Clean builds** — The logs of the four `xcodebuild … build` runs were searched for `warning:`/`error:`. The only hits are appintentsmetadataprocessor notices. The first iOS attempt failed only because the destination didn't match by name, and it was re-run by simulator id.

**Corrections to agent reports:**
- §5.1 was reported as a regression covering both cases (source equals destination, and overwriting another item's same-named copy). Comparing with `6a7b5fa0` shows the overwrite case already existed: the old `createNewFileUrl` path also wrote to the same name. Only the source-equals-destination deletion is new, so the finding is scoped to that.
- §5.7 was reported with a broad duplicate-row scenario. `addNew` saves right after its flush and `resetModel(with:)` queues no write, so the window is narrow; it stays Low.
- Two agents each reported §3.3 and the held-peer-bytes issue (§5.3 and §3.8); they are merged.

If a finding doesn't reproduce when you open its line, send me the section number and I'll re-investigate.

---

## 13. Remediation status (§3.1–§3.9, §4.1–§4.5, §5.1–§5.11, §6.1–§6.3, §7.1–§7.4, §8.1–§8.10, §9.1–§9.19)

Fixed 2026-10-01 on `develop` (uncommitted at the time of writing). Every fix is tagged `See CODE_AUDIT_20 §x.y` in the code. Items that are only partly fixed or not changed say why. Following §10.5 of this audit, each "fixed" claim was checked by searching for the pattern it names, not only the cited sites.

| § | Status | Fix |
|---|---|---|
| 3.1 | Fixed | One shared chain, `RootModel.enqueueMapContentSend`, orders every GM map-content send. The 2D resume, the "Refresh Shared Map" button and the 3D table (`sendMapContent`) all use it. A table model released while its update is pending re-marks `mapsWithUnsharedStructure`. |
| 3.2 | Fixed | `AudioController.play()` is the one play path: while `AudioPlayerSession.isConfiguring`, it waits for `waitUntilConfigured()` before playing; otherwise it plays synchronously, as before. Covers `toggle()`, the remote `.play`, `AudioPlayPauseButton` and `preparePlay`. |
| 3.3 | Fixed | `addNew` calls `markUnsavedInsert` before `replace`, so a commit by another module during the flush clears the mark. |
| 3.4 | Fixed | `GameStatisticsModel` sets `isClosingSession` once the final flush is done. Events recorded after that are logged and dropped instead of queueing for a completed session, and `recordEvents` logs the events it skips. |
| 3.5 | Fixed | Both `Observations` sequences are `Observations.untilFinished` over a weakly captured `BrowserManager`; the tasks hold neither the browser nor the controller strongly. |
| 3.6 | Fixed | `refreshMasterSessionId()` returns while the player is `.lost` and already knows a session id. |
| 3.7 | Fixed | `HostingSessionStore.prewarm()` reads the stored sessions off the main actor (called from `MasterNetworkController.init`); a miss afterwards means "none stored" without a Keychain read. The Keychain write runs in an ordered `@concurrent` task (`waitForStoredWrites()` for tests). |
| 3.8 | Fixed | `PeerFileDataStore.snapshot(for:)` returns the bytes and a generation under one lock; the temp copy is named `peer-<id>-<generation>`, so a replaced hold can never be shadowed by a stale file. |
| 3.9 | Fixed | Both comments reworded. |
| 4.1 | Not changed | A pilot needs the compiler's verdict on each of 61 `assumeMainActorIsolated` sites and 12 `@preconcurrency` conformances, and a runtime check that no framework calls them off the main actor. Not safe to do without running the app. |
| 4.2 | Fixed | All nine `Task.detached` sites are now `Task(priority:) { @concurrent in … }` (the remaining mentions of `Task.detached` in `Modules/` and `Sources/` are comments). |
| 4.3 | Partly fixed | The three AVAudioSession observers are `notifications(named:)` sequences on the main actor, with no `assumeMainActorIsolated`. The PDF search buffer is a `Mutex`. `CloudContainerCache` and `ContextFlushLedger` keep their synchronous observers on purpose (they must run on the posting thread). |
| 4.4 | Partly fixed | The contradictory comment in `presentVTTImport` is corrected. The other delays stand in for UI settling (list scroll, window mount, PDF navigation) and need a device to replace safely. |
| 4.5 | Partly fixed | `GameNetworkParametersTests` asserts `includePeerToPeer` and the keepalive on the initial parameters. The builder's output is opaque, so the two-device peer-to-peer check is still needed. |
| 5.1 | Fixed | `copyFile` takes a unique destination name (`suggestedFileName`, never replaces), refuses a destination that is the source, and reads the file through `deviceUrl`. `copyReplacingItem` also returns when read and write URLs are the same file. Tests: `FileUrlDataControllerFileOperationTests`. |
| 5.2 | Fixed | `MasterController.mayShareMapState(for:)` is the gate: the character-sync republish, the presentation replay, the repair bundle and the fresh-recovery send skip content and state while paused and mark the map in `mapsWithUnsharedStructure`. Test: `BattleRoundPausedSharingTests.joinReplayAndRepairHonourPausedSharing`. |
| 5.3 | Fixed | Mutating operations (`delete`, `move(name:category:)`, `copyFile`) resolve through `deviceUrl`; `delete` drops the held bytes. The store is process-wide, bounded to 256 MiB (oldest first) and emptied by `GameRoot.performStopGame`. The bytes are still held without a hash comparison when the item has no content hash: that case cannot be verified without the iCloud download, and the overlay is read-only and ends with the game. |
| 5.4 | Fixed | `resetFile(data:)` writes the new file first with `requireDurableStorage`, then deletes the old one with `deleteReplaced(_:keeping:)`; a write failure throws and keeps the old file. |
| 5.5 | Fixed | `failingItemIds` walks to-one relationships whose inverse is to-many up to the owning item. With the failing items identified, only they are blamed: other operations keep their retry budget. |
| 5.6 | Fixed | `updates(_:)` merges ids that are already loaded (`mergeUpdates`) and only creates instances for new ids. |
| 5.7 | Fixed | `existingUUIDsInContext` adds the context's unsaved inserted objects and removes its deleted ones. |
| 5.8 | Fixed | `LWWActorID.local` (an install-wide id kept in `UserDefaults`) stamps every local write, so two devices never tie at the same clock. |
| 5.9 | Fixed | `storedLocation(of:)` is the one notion of where a file lives; `deleteReplaced(_:keeping:)` and `isSameStoredFile` compare resolved locations. Used by §5.1 and §5.4. |
| 5.10 | Fixed | Decoded side counts are clamped to `RawDie.Sides.maximumDecodedSides` (1,000,000). |
| 5.11 | Fixed | `ItemControllable.save()` no longer clears the banner's save error. `ContextFlushLedger.didCommit` does, only when a save committed and no module still has operations a failed save rolled back. |
| 6.1 | Fixed | A connection without a usable endpoint is throttled under one shared source (`ConnectionThrottleTracker.unknownSource`), so the lockout, the pending cap and the handshake deadline still apply. Tests: `missingEndpointFailsClosed`, `acceptedConnectionHasRemoteEndpoint`. |
| 6.2 | Partly fixed | The reserved ranges (NAT64, Teredo, documentation, `192.0.0.0/24`, `198.18.0.0/15`) are refused. After each download the connected addresses (`URLSessionTaskTransactionMetrics.remoteAddress`, every hop) are checked, and a private one discards the file. The request itself is still sent: pinning the resolved address would need a custom resolver. |
| 6.3 | Fixed | `FoundryJSONValue.init(from:)` bounds its own nesting through the coding-path length when no counter is installed. Test: `MapWallModelTests.deeplyNestedWallMetadataIsRejectedWithoutADepthCounter`. CODE_AUDIT_19 §13 is corrected. |
| 7.1 | Fixed | The pin ring is its own view (`MapPinHealthRing`), so the formula is resolved only when its inputs or the linked values change. |
| 7.2 | Fixed | `TimelineView(.periodic(from: startDate, by: 60))`, and a localized "Game Time" label with a spoken duration. |
| 7.3 | Fixed | `ImageViewer` creates its `ViewportModel` once, on first read, through a small store; the `init` no longer builds one. |
| 7.4 | Fixed | `ConversationState` is `Equatable`; `syncConversationState()` assigns it once, and only when it changed. |
| 8.1 | Fixed | The accessibility value announces the health percent; under "Differentiate Without Color" the ring is solid, dashed or dotted by band (`MapPinModel.healthRingDash`). The 3D pins keep the color rule only. |
| 8.2 | Fixed | The dismiss button uses the module bundle; the keys have German and Thai translations and a one/other plural; the headline follows the issue ("A file could not be attached"). |
| 8.3 | Fixed | Reduce Motion skips the move transition and the animation; VoiceOver gets an announcement when an issue appears. |
| 8.4 | Fixed | A fan button keeps `MapAdaptiveFanGeometry.buttonSize`; tvOS uses the `.glass` button style with a circle border. *Check focus visibility on a tvOS simulator.* |
| 8.5 | Fixed | Escape closes the popover (focus-based `onKeyPress`); the buttons inside the glass panel are flat tinted circles. |
| 8.6 | Fixed | The spinner is white only on iOS; `.buttonBorderShape(.capsule)` replaces the clip. |
| 8.7 | Fixed | The report row ignores hit testing and uses scaled insets. |
| 8.8 | Fixed | The lightning button is `.focusable(false)`. |
| 8.9 | Fixed | The warnings are keyed by position. |
| 8.10 | Partly fixed | `GameModuleListPanel` replaces the computed view; the thumbnail property is gone; `Color.adaptiveBackground` is removed in favour of `.background`; the three Table round buttons have text labels; the onboarding background is semantic. New hard-coded paddings remain to be retired opportunistically. |
| 9.1 | Fixed | `MapPinActionButtons`, its snapshot test and `usesGlassEffects` are deleted; the fan doc names tvOS and visionOS. |
| 9.2 | Fixed | The `ScenesManager` header documents only the remaining API. |
| 9.3 | Fixed | All six entities use `EntitySummaryExport.plainText`. |
| 9.4 | Partly fixed | The two free functions are `SheetRowResolver` statics and the comments are corrected. The CoreGraphics helpers are consolidated (§9.9). Other widened members (`diceUpdateWidgetTask`, `FileUrlDataController` stored properties) are unchanged. |
| 9.5 | Fixed | `GameNetworkModel.JournalFingerprint` is the one projection, used by the LAN master and the SharePlay admission. The wider `ID`/`Id` clean-up of that file is left to the next rename pass. |
| 9.6 | Fixed | One `numberedLinks` loop behind `links(for:)` and `linksRepair(for:)`; the unused parameter is gone. |
| 9.7 | Fixed | One `ExtendedTabRestorationModifier` (`selectsMapsOnEditors` for the split layout). |
| 9.8 | Fixed | `dismissError()`, `cancel()` and `cancelExtraction()` are `ConversationSessionModel` defaults; the stored properties are protocol requirements. |
| 9.9 | Fixed | CoreRPG's `CGSize.isValidViewportSize`/`validViewportSize`/`isFinite` and `CGPoint.isFinite` are public and used by MapRPG and PhotoRPG; the module copies are removed (`isFiniteAndPositive` forwards). |
| 9.10 | Partly fixed | Removed: `SheetSearchContext`, `viewCompactDice`, `menuAudioPlayer`, `collectPhotos`, `isInlineEditing`, `recordEvent`; `InMemoryJoinCodeStorage` moved to the test target. Kept because their tests assert real behaviour: `isUsed(link:)`, `currentAttachment(for:)`, `coverageDepth(at:)`, `resetUsedLink`, `gameDiceHeight`, and the others not named in the audit. |
| 9.11 | Fixed | `ItemRowTreeModel`'s hand-written `Codable` is removed. |
| 9.12 | Fixed | German and Thai for the seven join-flow strings. |
| 9.13 | Fixed | The orphaned catalog is deleted. |
| 9.14 | Fixed | `ByteUnit.megabyte` (decimal) and `100 * ByteUnit.megabyte` etc. at the five sites; values unchanged. |
| 9.15 | Partly fixed | `explicitDirectoryUrl`, `selectedUrl`, `selectionId`, `highlightAndBold` and the two `PortableGame*` file names are renamed. The `ID` casing inside `SharePlayPlayerJournalAdmission` (`participantID` and friends) is unchanged. |
| 9.16 | Fixed | The commented-out `#if DEBUG` lines are removed and the reason is documented. |
| 9.17 | Fixed | `ResolvedAppTheme.panelCornerRadius` is used at the 14 listed sites. |
| 9.18 | Partly fixed | The file-replacement functions are in `EditControllable+File.swift`. `PlayerControllerModel` and `NavigationSend` are not split: that is a move of stateful code with access-control changes, and is better done as its own change. |
| 9.19 | Fixed | New tests: `FileUrlDataControllerFileOperationTests` (duplicate, rename-then-duplicate, delete with held bytes, replace guard, store budget), the endpoint assertion, the paused-join gate, the deep-nested wall. |
