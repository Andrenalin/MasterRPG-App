# MasterRPG Code Audit 23

Generated 2026-10-31 against `bf749c86d` (`main`). Scope: all production Swift under `Modules/` and `Sources/` (~204k LOC, 15 modules, 5 targets, 1848 non-test files). Tests were only read to confirm usage. Read-only audit: no code was changed; the report is this file.

**Compiler ground truth.** Clean Debug builds into fresh derived-data folders (Xcode 27.2): MasterRPG iOS Simulator, MasterMac, MasterTV (tvOS Simulator) and MasterRPG visionOS Simulator all **succeeded with 0 Swift warnings**. The only diagnostics were "appintentsmetadataprocessor: Metadata extraction skipped" notices. No tests were run and the test targets were not compiled.

**Method.** Seven read-only agents (concurrency/API modernity, dead code/duplication, CoreRPG+RuleRPG, GameRPG, Map+Space+RolePlayGameKit+Generator+Sources, the eight item modules, SwiftUI pass). Each also reviewed `git diff 38393b789 HEAD` for its area (the audit-22 fixes plus 6 later commits). Tags: [NEW], [STILL OPEN from …], [INCOMPLETE FIX of …], [REGRESSION sha]. Evidence markers: **[verified]** = I re-read the cited lines myself and the behaviour follows from them; **[traced]** = I followed the call path in source but did not run it; **[reasoned]** = the reporting agent's reading, not re-opened by me. Line numbers marked `~` must be re-opened before editing. Every [NEW] tag was checked by the agents against `Docu/CODE_AUDIT_*.md`, but only partly; re-grep before filing.

**Result in one line:** four High findings (a renderer trap on unbalanced link markers, the fog-of-war leak of shown monsters, a room reveal that does not resend its text, and battle clones that share their template's value groups); every concurrency and modernity rule in `CLAUDE.md` is clean except the Id/Url naming drift; no Critical findings.

---

## 1. Executive summary

1. **[High] An unbalanced "➡️" in any entry text traps the link renderer on every render, and the text syncs to other devices** — §5.1 — `Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift:163-177` [verified].
2. **[High] Shown monster pins inside unrevealed (fogged) rooms are sent to players with name, portrait, character link and position** — §6.1 — `Modules/MapRPG/Controller/GameController+Sync.swift:42`, `Modules/MapRPG/Model/MapSnapshot.swift:161` [verified].
3. **[High] Revealing a room on its own does not resend the room's name and text, so players see a blank room** — §5.2 — `Modules/MapRPG/Model/MapUpdatePayload.swift:116-131`, `Modules/GameRPG/Controller/MasterController+Messaging.swift:106-112` [traced, not run].
4. **[High] Battle clones of one character share the template's value-group items, so damage to one goblin hits all of them** — §5.3 — `Modules/CharacterRPG/Controller/GameController.swift:201-210`, `Model/ValueEntryModel.swift:214-216` [traced, not run].
5. **[Medium] Item delete removes the item's stored file even when the database delete failed** — §5.6 — `Modules/CoreRPG/Controllable/ItemControllable.swift:192-214` [verified].
6. **[Medium] A failed bookmark-store read becomes "empty", and the next save overwrites the whole store** — §5.5 — `Modules/CoreRPG/Persistence/FilePersistenceController.swift:48-72`.
7. **[Medium] Messages queued from a player that already disconnected re-add a ghost roster entry** — §5.4 — `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift`.
8. **[Medium] One player can make the master relay a 100 MB `.playAudio` payload to every player and hold it for ~25 s** — §6.3 — `Modules/GameRPG/Controller/MasterController+AudioMessages.swift`.
9. **[Medium] iCloud folder Sync during a running game persists new items but trashes/repairs folders in game memory only** — §5.7 — `Modules/CoreRPG/Controllable/CloudScanController.swift:77-98`.
10. **[Medium] Photo decode paths never apply the declared-size limits and fall back to an unbounded full decode** — §6.8 — `Modules/CoreRPG/Extensions/Image+AKImage.swift:226-336`.

---

## 2. Quick wins (≤30 min)

- Replace the two unconditional `endRanges.removeFirst()` calls with a guarded pop; treat an unmatched begin marker as plain text (§5.1).
- Use `.contains(.shouldResume)` in `AudioPlayerSession.handleInterruption` (§4.2).
- Delete `HideKeyboardView` and its `show:` overload (§9.1).
- Clamp the Storm rain `delta` to ~0.1 s (§5.17).
- Pause audio on any `.oldDeviceUnavailable`, not only wired headphones (§5.18).
- Add outcome words to the dice-result `accessibilityValue` in the app and the widget (§8.2, §8.3).
- Return the resolved bookmark URL when the stale-bookmark refresh fails (§5.25).
- Key `AsyncThumbnail` on `fileId`/`contentHash`/`hasInlineData` instead of the whole `FileUrl` (§7.14).
- Gate the low-battery `symbolEffect` on Reduce Motion (§8.4).
- Fix the stale comment in `BatteryMonitor` and ref-count the global monitoring flag (§3.4).

---

## 3. Concurrency

The concurrency sweep found the rules clean: no `DispatchQueue`, `Task.sleep(nanoseconds:)`, locks across `await`, one justified `Task.detached` (`DuplicateRowOrder.swift:52`); all 15 `@unchecked Sendable` types, 17 continuations, every `Mutex`/`OSAllocatedUnfairLock` and every `nonisolated(unsafe)` use were read and judged sound; every `@Observable` class is `@MainActor`; every `AsyncStream` has a finish path. Findings below are state-machine and lifetime issues, all Low.

### 3.1 `GameRoot` start flows do not re-validate after their suspensions and are not mutually exclusive
- **Location:** `Modules/GameRPG/Root/GameRoot.swift:339-398` (`startMaster`, the suspension at ~380), `:415-480` (`startGame`), `:519-541` (`stopGame`).
- **What:** `stopGame` does not wait for or cancel an in-progress start; `startMaster` continues after its `await` and unconditionally builds controllers and sets `.started`. `startGame` and `startMaster` use separate flags (`isStartingGame`, `isStartingMaster`), and `startMaster` treats any non-`.stopped` state as "toggle off".
- **Why:** A fast Start then Stop, or a stop during a slow join, leaves a ghost `.started` game, an orphan statistics session and `isIdleTimerDisabled = true` after teardown. A Siri `JoinGameIntent` racing a UI master start can tear down the other. Window is narrow. [reasoned]
- **Action:** One shared start token/`isStarting` state; re-check it and `state` after each `await`; make `stopGame` bump or await it.
- **Severity:** Low
- **Tag:** [INCOMPLETE FIX of CODE_AUDIT_21 §3.2 / CODE_AUDIT_22 §3.2] (they guard re-entry of the same entry point only)

### 3.2 `RemoteDownloadsInFlight` never cancels the shared download when its last waiter leaves
- **Location:** `Modules/CoreRPG/Files/RemoteDownloadsInFlight.swift:17-55`; `Modules/CoreRPG/Files/GuardedRemoteDownload.swift` (uses `URLSession.shared`).
- **What:** The shared download is an unstructured `Task` with no waiter count; every later caller joins the first one. `URLSession.shared`'s resource timeout is 7 days.
- **Why:** If all callers are cancelled the download (up to 256 MiB) still runs to completion; a slow-drip host holds the cache path for every reader.
- **Action:** Count waiters under the lock and cancel at zero; use a dedicated session with `timeoutIntervalForResource` of ~60-120 s.
- **Severity:** Low
- **Tag:** [NEW] (22 §3.2 fixed the waiter side only)

### 3.3 `GeneratorTaskWait` leaves unstructured tasks behind
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift` (`GeneratorTaskWait.end`, `OneShotGate`, ~451-504).
- **What:** `end(of:timeout:)` starts two unstructured `Task`s; the one awaiting `task.value` is never cancelled, and after the 5 s timeout the next request proceeds on the shared session while the predecessor may still drain it.
- **Why:** Bounded leak; a request after the timeout can still hit "already responding" and surface an error alert. [reasoned]
- **Action:** Race with a task group and cancel the loser; rebuild the session on timeout.
- **Severity:** Low
- **Tag:** [NEW] (follow-up to CODE_AUDIT_22a §5.5)

### 3.4 `BatteryMonitor` toggles a process-wide flag per instance
- **Location:** `Modules/GameRPG/GameViews/BatteryView.swift:110, 143`, comment at `:43-48`; two `BatteryView()` sites: `GameToolbarContent.swift:77`, `IOSGameOverlayControlField.swift:49`.
- **What:** Each monitor's `stopMonitoring()` sets `UIDevice.current.isBatteryMonitoringEnabled = false` even if another live `BatteryView` still needs it; the comment claims `@MainActor` deinit cannot touch isolated state (`isolated deinit` is used elsewhere).
- **Why:** When one view disappears the other stops receiving battery updates. [reasoned]
- **Action:** Reference-count monitoring (shared monitor or counter); use `isolated deinit`; fix the comment.
- **Severity:** Low
- **Tag:** [NEW] (the init leak of 22 §3.1 is fixed)

### 3.5 `CloudKitOperationCounter` counts local file reads as "CloudKit operations"
- **Location:** `Modules/CoreRPG/Files/CloudDocumentController.swift:~12-55`, `Files/FileUrlDataController.swift:329`, `Persistence/CoreDataController.swift:550-555` (hand-rolled fire-and-forget `Task`). 25 `recordOperation` call sites.
- **What:** Every file read hops to an actor and logs; `warningThreshold` is 1000 per 24 h.
- **Why:** Browsing 1000 thumbnails logs a false "check for a sync loop" warning and adds per-read overhead.
- **Action:** Count only writes/saves; drop the `loadData` site or keep it under `#if DEBUG`; route the save path through the shared `trackOperation(_:)` helper.
- **Severity:** Low
- **Tag:** [INCOMPLETE FIX of CODE_AUDIT_CoreData §9.2], [STILL OPEN from CODE_AUDIT_EditItem §3.4] for the `CoreDataController` site

### 3.6 iCloud Sync `apply` takes its pre-lock snapshot before the exclusion lock
- **Location:** `Modules/CoreRPG/Controllable/CloudScanController.swift:53-60`.
- **What:** `current = await scan()` and `hashes = await newItemHashes(...)` run before `DataMutationCoordinator.begin()`.
- **Why:** An item the user re-pointed to another file in that window can still be trashed from the old "file missing" picture; this is the case the 22a revalidation was meant to close. [reasoned]
- **Action:** Take the token first and re-read `cloudScanExistingItems()` after the lock, or re-check each removal just before trashing.
- **Severity:** Low
- **Tag:** [INCOMPLETE FIX of CODE_AUDIT_22 §5.11 / 22a §5.1]

---

## 4. API modernity

No deprecated AVFoundation/PhotoKit/Foundation APIs found (`AVAsset.duration`, `NSSearchPathForDirectoriesInDomains`, `NavigationView`, `.alert(isPresented:)` all absent). Deployment targets are 26.0, so `#available` guards for 26.1-27.1 are live, not stale. The 114 `AnyView` uses are the accepted `ViewControllable` returns (CODE_AUDIT_20).

### 4.1 `ID`/`URL` identifier casing still widespread
- **Location:** ~257 declarations; densest in `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper*.swift`, `Modules/CoreRPG/Foundry/*`, `Modules/CoreRPG/Import/ExternalImport*`, `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift`, `Modules/GameRPG/Controller/LogGameController.swift`, `PreviewData.swift`. Names: `documentID`, `scopeID`, `parentID`, `sessionID`, `sourceURL`, `systemID`, `masterRPGID`.
- **What:** `CLAUDE.md` requires `Id`/`Url`.
- **Why:** Convention drift. Some are synthesized Codable keys (`systemID`, per audit 21), so renames need explicit `CodingKeys`.
- **Action:** Dedicated rename pass, Foundry mapper first; add `CodingKeys` where the name is persisted.
- **Severity:** Low
- **Tag:** [STILL OPEN from CODE_AUDIT_21 §9.9] (down from 304)

### 4.2 `handleInterruption` compares an `OptionSet` with `==`
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerSession.swift:172-173`.
- **What:** `AVAudioSession.InterruptionOptions(rawValue: optionsRaw) == .shouldResume` fails if the system adds another option bit.
- **Why:** Playback silently would not resume after an interruption.
- **Action:** Use `.contains(.shouldResume)`.
- **Severity:** Low
- **Tag:** [NEW]

### 4.3 UIKit appearance proxy mutated from a SwiftUI view
- **Location:** `Modules/SpaceRPG/Record/HelpPageView.swift:47-48` (`UIPageControl.appearance()`).
- **What:** Global appearance change from a view callback.
- **Why:** Leaks styling into every `UIPageControl` in the process; no per-view SwiftUI equivalent for the page `TabView`.
- **Action:** Scope it or document the exception.
- **Severity:** Low
- **Tag:** [NEW]

### 4.4 `nonisolated(unsafe)` on `UserDefaults`
- **Location:** `Modules/CoreRPG/Model/QuickDiceSlotsModel.swift:45`.
- **What:** Comment says `UserDefaults` is not `Sendable` in this SDK; the agent could not confirm that from the headers.
- **Why:** An unnecessary escape hatch if the SDK now marks it `Sendable`.
- **Action:** Try removing it on the next toolchain bump.
- **Severity:** Low
- **Tag:** [NEW]

---

## 5. Bugs / logic errors

### 5.1 An unbalanced "➡️" traps the link text renderer
- **Location:** `Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift:163-167` and `:175-177` (`components(for:range:…)`); markers defined at `LinkRenderer/LinkHighLightLocations.swift:99-105`.
- **What:** On a begin marker the code does `var endRanges = text.ranges(of: "⬅️")…; var endRange = endRanges.first; endRanges.removeFirst()`, and the same pair again inside `for beginRange in beginRanges`. `Array.removeFirst()` on an empty array is a precondition trap.
- **Why:** "➡️" (U+27A1 U+FE0F) is typed from the emoji keyboard. A note "➡️ north corridor" with no later "⬅️" traps at line 167. "➡️ a ➡️ b ⬅️" (two begins, one end) traps at line 177. `containsStructuredFormatting` is true for any text containing either marker, and `linksRepair` only renumbers link numbers, so nothing strips or balances markers on save, import or peer receive. The text crashes the view on every render and syncs through CloudKit, so one note can take the item out of use. The existing tests only cover balanced text. [verified: lines read; trap traced, not run]
- **Action:** Pop the first end range only when the array is non-empty (both sites); treat a begin marker with no end as plain text; add tests for a lone "➡️", "➡️ … ➡️ … ⬅️" and a lone "⬅️"; optionally strip/escape the markers from user-typed text.
- **Severity:** High
- **Tag:** [NEW] (code predates audit 22; CODE_AUDIT_Link noted this state machine was "not exhaustively traced" for malformed input)

### 5.2 Revealing a room alone does not resend its text
- **Location:** `Modules/MapRPG/Model/MapUpdatePayload.swift:116-131` (`CanonicalMapEntry`, no `isShown`) and `:26-37` (`contentVersion` built from the unredacted `fullSnapshot`); `Modules/GameRPG/Controller/MasterController+Messaging.swift:106-112`, `:286-289` (`sendMapContentIfChanged`); `Modules/MapRPG/Controller/GameController+Metadata.swift:44-54`; test `Tests/GameRPGTests/MasterPlayerControllerTests.swift:385-402`.
- **What:** Hidden rooms go out with blank name and content (`MapSnapshot.swift:150-160`). The content update is sent only when `contentVersion` differs from the last one sent, but the fingerprint covers name, content, coordinates, hex flag and the library `displayState`, not the room's `isShown`. The comment on `MapUpdatePayload.init` says a reveal "still registers as a version change", but nothing in the fingerprint backs that up.
- **Why:** A pure reveal sends only the `.mapState` flags, so players show the room with no name or text until a join, reconnect, reshow or another structural edit resends the content. The existing test passes only because it also appends two pins, which changes the digest. 22a made this more visible by blanking the room name as well. [traced, not run]
- **Action:** Include each room's reveal state in the content fingerprint (or send the content update on a reveal toggle); add a test that reveals one room with no other edit.
- **Severity:** High
- **Tag:** [INCOMPLETE FIX of CODE_AUDIT_Map §6.1 / CODE_AUDIT_22a §6.2]

### 5.3 Battle clones share the template's value-group items
- **Location:** `Modules/CharacterRPG/Controller/GameController.swift:201-210` (`createBattleCharacterCopy`), `Model/ValueModel.swift:194-206` (`cloned`, `duplicateWithoutCopy`), `Model/ValueEntryModel.swift:214-216` (`duplicate()` keeps `valueId`), `Controller/GameController+EntryResolution.swift:186-200, 263-305` (`gameEntryOwnerId`, `gameMemoryCopy`). Callers: `Modules/MapRPG/Controller/GameController+Battle.swift:106, 377`, `Modules/GameRPG/BattleRound/BattleRoundController.swift:112-126`.
- **What:** The clone is `source.duplicateWithoutCopy()`, which re-ids only the clone's own entries; each duplicated entry keeps `valueId`, so group entries still point at the template's group item. `setGameEntryCurrentNumber` resolves the owner with `gameEntryOwnerId` and writes into `gameMemoryCopy(for: ownerId)`.
- **Why:** When HP or initiative lives in a linked value group (the common case per the code comments), damage to goblin #1 changes goblin #2…n and the template's game copy, because they all share that group's game-memory copy. `BattleRoundControllerTests` covers a group-nested HP entry but never two clones of one template. No caller deep-copies groups. [traced, not run]
- **Action:** Deep-copy value groups (new group items with remapped `valueId`/`groupId`) when creating a battle copy and remove them in `removeBattleCharacterCopies`; add a two-clone test with HP in a group.
- **Severity:** High
- **Tag:** [NEW]

### 5.4 Ghost player re-added after disconnect
- **Location:** `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift` (`process(_:)`, `lostPlayer(for:)`); `Network/GamePlayerRoutes.swift`; `Model/GameMessagePipeline.swift`.
- **What:** `accepts()` checks the route only at enqueue time, but `lostPlayer` removes the route and roster entry without touching the pipeline. Queued events from that connection (up to 128) are still processed, and `process` calls `root.gameModel.add(playerId:…)` for any non-master sender with `role != .notSet`, then `resetPlayers()`.
- **Why:** A player that sends a burst and drops leaves a roster/control entry with no connection behind it; `allPlayersReported` and audio `missingPlayers` never complete, and the stale roster is broadcast to every player. [agent grepped for a per-origin purge or process-time route check and found none]
- **Action:** Re-check the sender's route/participant binding at process time, or purge queued events by origin in `lostPlayer`; never let a processed message create a roster entry.
- **Severity:** Medium
- **Tag:** [NEW]

### 5.5 Bookmark store: a failed file read becomes "empty" and the next save overwrites the file
- **Location:** `Modules/CoreRPG/Persistence/FilePersistenceController.swift:48-72`; `Files/FileDataController.swift:60-71`; `Files/FileBookmarkController.swift:56-66`.
- **What:** In `load()` only a JSON decode failure moves the file aside as `.corrupt`; a throwing `Data(contentsOf:)` falls to the outer `catch`, which logs and returns `[]`. `fetch` then decodes with `try?` and drops failures; `fetchIfNeeded` marks `didFetch = true` with empty dictionaries. The next `changeBookmarks`/`removeBookmark` rewrites the store with only the new entry.
- **Why:** A transient read error (App Group file unreadable before first unlock, an IO error) or a changed `Bookmarks` shape loses every user-picked `.other`/`.icloud` file bookmark of the module on the next pick/removal; files turn "missing". This is the read-error half of the audit-15 §5.5 fix.
- **Action:** Distinguish "absent" from "read failed" (throw/retry, do not mark fetched); keep a `.corrupt` copy before overwriting; do not drop undecodable entries while the file is also rewritten.
- **Severity:** Medium
- **Tag:** [INCOMPLETE FIX of CODE_AUDIT_15 §5.5]

### 5.6 Item delete removes the item's file even when the database delete failed
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:192-214`.
- **What:** The `do { try await dataControllable?.delete(id:) } catch { recordPersistenceFailure(...) }` block only records the error; the code then runs `fileUrlDataController.delete(fileUrl, …)` whenever `withFileData` is true.
- **Why:** The item has already left memory (`resetModel(id:)` runs first). If the row delete throws (flush failure, disk full) the row survives on disk and in CloudKit and reappears at next launch or sync, but its iCloud/local file is gone and cannot be recovered through the app. [verified: lines 192-214; failing save not run]
- **Action:** Delete the file only after the database delete succeeded; on failure withdraw the announced deletion and restore the item in memory (or at least keep the file).
- **Severity:** Medium
- **Tag:** [NEW]

### 5.7 iCloud folder Sync during a running game: trashing and folder repair become game-memory-only
- **Location:** `Modules/CoreRPG/Controllable/CloudScanController.swift:77-98`; `ItemControllable+CloudScan.swift` (inserts use `forceSave: true`); `EditControllable.confirmRemoval`/`markForDeletion`/`repairFolders` (default `forceSave: false`); `ItemControllable.swift:233-236` (`replace()` guard).
- **What:** `apply` persists inserts/moves with `forceSave: true`, then calls `repairFolders` and `confirmRemoval`, which go through `save(updated:)` with `forceSave: false`; with `isGameMode == true` that becomes `replaceInGameMemory`. `CloudFolderScanView`/`InternalRoute.cloudFolderScan` have no game-mode guard.
- **Why:** If the GM taps Sync mid-game, new items are persisted but their parent folder entries and the selected removals live in game memory only and are lost at game end, leaving the library half-synced. [reasoned: not confirmed that the Sync menu is reachable in game]
- **Action:** Disable Sync while `isGameMode`, or use library-scope saves in `apply`.
- **Severity:** Medium
- **Tag:** [NEW] (introduced with 27d877a06)

### 5.8 Delete panel lists, then trashes, stale folder entries pointing at items that live elsewhere
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:526-553` (`collectionItemsForRemoval`, children built at ~537-541), `:559-564` (`confirmRemoval`); compare `delete(itemId:visited:)` at `:608-610`, which checks `child.parentId == item.id`.
- **What:** `collectChildren` uses every `model.entries` child of a folder without checking `parentId`; `repairFolders`/`restore` already treat entries for moved items as stale.
- **Why:** A folder with a stale entry (left by a move, CloudKit merge or import) offers an unrelated item from another folder in the Delete panel; accepting the default selection trashes it. Also reused by `trashIntentItems` (Siri/Shortcuts) which has no panel.
- **Action:** Filter children with `itemSync(for:noGame:)?.parentId == folder.id`, the rule `delete`, `movedFileTree` and `duplicateFolderMembers` use.
- **Severity:** Medium
- **Tag:** [NEW] (CODE_AUDIT_21 §5.29 fixed the confirmation flow, not the collection rule)

### 5.9 A failed track load resumes the previously loaded track while the UI shows nothing selected
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift` — `add(audio:replace:)` :84-137, `preparePlay` :310-327, `replaceCurrentItem` :329-336; callers `Modules/AudioRPG/Controller/GameController.swift:254-260`, `loadAndPlay` :262-281.
- **What:** `add(replace: true)` empties the playlist and deletes the playing track's temp copy but never touches `model.player`. If the new load yields no `PlaylistItem` (offline dataless iCloud file, failed coordinated copy), `add` still returns `true`; `togglePlay` sets `currentItem` to nil, `replaceCurrentItem()` early-returns, and `preparePlay` calls `model.player.play()` on the stale `AVPlayerItem`.
- **Why:** The previous track plays with no current item, no now-playing info and no playlist. [traced from quoted guard/flow]
- **Action:** Return `false` from `add` when nothing loaded; in `preparePlay` bail out (or clear the player item) when `currentItem` is nil; replace the player item as part of a replacement.
- **Severity:** Medium
- **Tag:** [NEW]

### 5.10 `model.uuid ?? UUID()` still mints unstable identities in seven modules
- **Location:** `Modules/{Adventure,Audio,Character,Dice,Photo,Table,Weather}RPG/Controller/DataController.swift` — item ids: Adventure :23, Audio :25, Character :23, Dice :23, Photo :23, Table :23, Weather :23; entry ids: Adventure :82, Audio :77-78, Character :94, Dice :155-156, Photo :78-79, Table :76, Weather :92-93; file ids `fileId: model.uuid ?? UUID()` in Audio :31, Photo :30.
- **What:** Only PdfRPG got `repairedUuid(for:)`; the others re-randomize a nil `uuid` on every mapping call.
- **Why:** CloudKit-optional attributes can be nil mid-merge; the same managed object then gets a different domain id per snapshot pass → duplicated/orphaned items, entries that never diff-match, and a wrong `FileUrl.fileId` that breaks Audio/Photo file lookup.
- **Action:** One shared "log, assign and persist once" helper used by all DataControllers, entry mappers included.
- **Severity:** Medium
- **Tag:** [STILL OPEN from CODE_AUDIT_Pdf §5.4 / CODE_AUDIT_Table §5.5; Pdf-only fix]

### 5.11 Character links written into room text name the monsters and persist outside the editor commit
- **Location:** `Modules/MapRPG/Map/MapEditController+Rooms.swift:101-156` (`appendCharacterLinks`; :133 `content += …`, :150 `editController.save`); callers `MapEditController+Pins.swift:79`, `MapEditorActionRouter.swift:286`; `MapEditController+Sync.swift:19-40` (`mergeExternalEntries`, :28-29 re-appends a locally deleted room).
- **What:** Adding or choosing a pin character appends `[<Character name>](RPG://VALUES/…)` to the room content and saves the stored map while the editor has an uncommitted working copy.
- **Why:** Once the room is revealed its text goes to players and names every monster in it (even pins that stay hidden). The save bypasses the editor's commit/undo, and the resulting external-map update re-appends any room the user deleted locally. [verified for the append and save lines; resurrection reasoned]
- **Action:** Keep character links out of player-visible room text (GM-only field) or at least skip hidden pins; do not persist the stored map from inside an editor mutation; make the external merge honour local deletions.
- **Severity:** Medium
- **Tag:** [NEW]; the resurrection part is [STILL OPEN from CODE_AUDIT_22 §5.9]

### 5.12 Link register: a failed `setup` fetch rehydrates an empty register and the next save deletes persisted link rows
- **Location:** `Modules/CoreRPG/Links/LinkRegisterController.swift:36-60` (fetch `catch` returns `[]`), `savePendingLinks` :178-240.
- **What:** The upsert deletes persisted rows for the affected source ids that are not in the in-memory register; after a failed rehydration the register is empty.
- **Why:** Editing item A persists only A's changed links and deletes A's other stored link rows; the "used by" index and link validation lose references until each item is re-saved. [reasoned]
- **Action:** Keep a `didHydrate` flag; on failure retry or skip persistence/deletion.
- **Severity:** Low
- **Tag:** [NEW]

### 5.13 Hex-grid carry-over can trap on huge imported coordinates
- **Location:** `Modules/MapRPG/Map/MapHexGridGeometry.swift:132-134` (`Int((value / rasterSize).rounded(.down))`).
- **What:** Corners are checked finite, not bounded.
- **Why:** An imported `.gmz`/VTT map with `isHexGrid` entries at ~1e300 crashes on a hex-scale change (trapping `Int(Double)`). [reasoned]
- **Action:** Use `Int(exactly:)` with a clamp, or reject coordinates beyond a map-size bound.
- **Severity:** Low
- **Tag:** [NEW]

### 5.14 Quick double roll doubles a dice result
- **Location:** `Modules/DiceRPG/Controller/GameController+PlayerDice.swift:~86-107` (`rollDice`, `localRollStartDelay` 0.1 s), `GameController+DiceResult.swift:~230-243` (`roll(die:for:)`), `Model/DieModel.swift` (`roll(resetResults: false)`).
- **What:** `reset(for:)` runs immediately but the roll runs 0.1 s later in a `Task`, and `roll(die: nil, …)` appends results.
- **Why:** A second `rollDice` within 100 ms (double tap, tap plus Siri) lets both tasks fire; each die holds two results and `sumResult` adds both (a d20 can sum 2-40). [reasoned]
- **Action:** Reset inside `roll(die:for:)`, or cancel the earlier pending roll task per `itemId`.
- **Severity:** Low
- **Tag:** [NEW]

### 5.15 `"|"` split is plain in six places but link-aware in one
- **Location:** plain `split(separator: "|")` in `Modules/CharacterRPG/Controller/GameController+EntryResolution.swift:199`, `EditController+InlineEditor.swift:28, 77, 95`, `Model/ValueEntryModel.swift:119-124, 168`; link-aware `baseText(of:)` only in `gameValueBaseAndCurrent` (:240).
- **What:** The write paths cut a base like `[Max|HP](RPG://VALUES/…)` at the pipe inside the link name.
- **Why:** Writing a modifier turns `entry.value` into `"[Max|5"`, destroying the link and formula (battle HP write and inline editor). Needs a link name containing `|`, which is rare.
- **Action:** Use `baseText(of:)` (move it to `ValueEntryModel`) at every base/modifier split.
- **Severity:** Low
- **Tag:** [NEW]

### 5.16 Number text round trip has locale and exponent gaps
- **Location:** `Modules/CharacterRPG/Controller/EditController.swift:302-335` (`termineType`, `parseInteger`, `parseDouble` use `Locale.current`) vs `Model/Calculator.swift` (`en_US`); `EditController+InlineEditor.swift:79`, `ValueEntryModel.swift:104, 110, 164` (`"\(Double)"` interpolation).
- **What:** The classifier uses the device locale, the evaluator and parser use `en_US`; `"\(Double)"` yields `1e-05`/`1e+16`.
- **Why:** With a German locale `"3,5"` is classified `.decimal` and stored as-is but `Calculator` parses it as `en_US` (outcome not confirmed). A decimal change producing `1e-05` becomes `base|1e-05`, which the calculator regex cannot parse → sheet shows `0 Error`. [reasoned]
- **Action:** Normalize to `en_US` on input and store with a fixed-notation format style, as `Calculator.formatNumber` does.
- **Severity:** Low
- **Tag:** [NEW]

### 5.17 Storm rain disappears for seconds after a long pause
- **Location:** `Modules/WeatherRPG/Weather/Storm.swift:48-71`.
- **What:** `delta = date − lastUpdate` is unclamped and the wrap subtracts only 1.4 once per frame (`CloudGroup`/`StarField` re-wrap in one step).
- **Why:** After the app returns from the background `delta` can be minutes; drops take ~10-60 s of frames to re-enter. [reasoned]
- **Action:** Clamp `delta` to ~0.1 s or wrap with `truncatingRemainder`.
- **Severity:** Low
- **Tag:** [NEW]

### 5.18 Only wired headphones pause audio on route loss
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerSession.swift:~160-175` (`handleRouteChange`).
- **What:** Pauses only when `previousOutput.portType == .headphones`, and only checks `outputs.first`.
- **Why:** Disconnecting AirPods, a Bluetooth speaker or USB audio does not pause; ambience then plays from the phone speaker at the table.
- **Action:** Pause on any `.oldDeviceUnavailable` or loss of a non-built-in output.
- **Severity:** Low
- **Tag:** [STILL OPEN from CODE_AUDIT_17 §5.25]

### 5.19 Table generation: occurrence cap reported as a "cycle", and a failed nested roll is cleared
- **Location:** `Modules/TableRPG/Controller/TableGenerationController.swift:~202-220, ~300-312` (`rebuildChildren`, `roll`/`apply`).
- **What:** A link skipped by `maxOccurrenceCount` (500) is appended to `ignoredCycleNames`; `roll` clears `model.errorMessage` first, so a later successful sibling erases an earlier "Roll N does not match…" error.
- **Why:** A big generation looks complete while parts never rolled and the user is not told 500 was hit.
- **Action:** Separate `truncatedLinkNames` and message; accumulate errors during `autoRoll`.
- **Severity:** Low
- **Tag:** [NEW]

### 5.20 Decoded dice/option lists have no count bound; `RawDieCounter.roll()` is unbounded
- **Location:** `Modules/DiceRPG/Model/DiceModel.swift:62-84`, `DiceSnapshot.swift:182-196`, `Controller/DataController.swift:107-148`; `Model/RawDieCounter.swift:15-25`.
- **What:** Modifier, compare value and results are bounded, but the number of dice and option arrays is not; `addDiceEvery` is unclamped in `DiceModel.init(from:)` unlike `DiceSnapshot`. `RawDieCounter.roll()` loops `abs(count)` times and `abs(Int.min)` traps (not reachable today: `DiceExpression` caps at 100).
- **Why:** A peer package or `.gmz` with millions of dice makes one roll allocate and animate all of them; `DieModel.roll` loops up to `die.max + 1` times with an O(R) `contains`.
- **Action:** Clamp dice and option arrays at decode; clamp `addDiceEvery` in both decoders; clamp inside `RawDieCounter.roll()`.
- **Severity:** Low
- **Tag:** [NEW]

### 5.21 Character repair rewrites group items on every run
- **Location:** `Modules/CharacterRPG/Controller/EditController+Repair.swift:~170-190` (`repairGroupItemConstraints`), `Root/CharacterRootModel.swift:~243-270` (`checkFolders`).
- **What:** Always sets `parentId = nil` and saves every group item without a changed check; per group entry always `reset(tags: [])`, `removePhotos`, `displayState <=> 1; save`. A group whose owner is not yet synced (`valueIdOwners` skips `totalHidden` owners) is promoted to a visible top-level item.
- **Why:** Every validate/repair run moves CRDT clocks and syncs unchanged data via CloudKit; repair during a partial sync can leave a permanent visible top-level character.
- **Action:** Save only when a field changed; treat "owner not found" as pending until first sync completes.
- **Severity:** Low
- **Tag:** [NEW]

### 5.22 Indefinite (NaN) duration not handled everywhere; media-service reset loses the SharePlay id
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:~407-416` (`updateCurrentTime`), `~531` (`resetMediaService`); `Audio/AudioPlayerTimelineView.swift:189-192`.
- **What:** `ProgressView(value:total: max(totalDuration, 1))` — `max(NaN, 1)` is NaN; non-finite durations reach now-playing. `resetMediaService` builds a new `AudioListenerCoordinator` and calls `replaceCurrentItem()` without `coordinatePlayback(of:)`.
- **Why:** `ProgressView` warns/renders wrongly before duration loads; after a media reset `identifierFor` returns a random UUID so the SharePlay shared-audio id is wrong.
- **Action:** Filter non-finite durations; call `coordinatePlayback(of:)` before `replaceCurrentItem()` in the reset path.
- **Severity:** Low
- **Tag:** [NEW] (scrubber NaN fixed in CODE_AUDIT_17 §5.25; the timeline bar was missed)

### 5.23 Core Data model edited in place (Map `degrees`)
- **Location:** `Modules/MapRPG/Resources/Model.xcdatamodeld/RPGMap.xcdatamodel/contents` (new optional `degrees`); single model version.
- **What:** An optional attribute was added to the shipped model with no new model version; earlier map-model commits did the same.
- **Why:** An existing store may fail automatic lightweight migration if the old model is not in the bundle. Not exercised (also CODE_AUDIT_CoreData §9.4). [reasoned]
- **Action:** Add a versioned model or test opening a store from the previous release.
- **Severity:** Low
- **Tag:** [NEW]

### 5.24 Table3D pawn photo sync is not idempotent
- **Location:** `Modules/GameRPG/Table3D/GameTableProjection.swift` (`syncPins`), `GameTableEntities.swift` (`PinPawn`), `GameTableModel+PinThumbnails.swift`.
- **What:** `syncPins` updates a pawn only when `loadedPhotoId != pin.photoId, let photoId`, so a removed photo keeps the old texture; `loadPinThumbnail` sets `loadedPhotoId` even when `TextureResource` creation failed (`try?`), so it is never retried; `failedPinPhotoIds`/`pendingPinPhotoIds` are not pruned for removed pins; `pinDragChanged` caches a pawn a mid-drag `syncPins` may remove; A→B→A loads can clear the new load's bookkeeping.
- **Why:** Stale or missing pin pictures on the 3D table and small bookkeeping leaks. [reasoned]
- **Action:** Reset the texture when `photoId` becomes nil; set `loadedPhotoId` only on success; prune sets with pins; key bookkeeping by a load token.
- **Severity:** Low
- **Tag:** [NEW]

### 5.25 Smaller file-write and bookmark items
- **Location:** `Modules/CoreRPG/Persistence/FilePersistenceController.swift:112-115` (`saveData`), `Files/FileManager+Coordination.swift:162-168` (`write(_:coordinatingAccessTo:)`, no caller found), `Files/FileBookmarkController.swift:132-137`.
- **What:** (1) External data files are written non-atomically. (2) In `loadBookmark`, if a stale bookmark's re-save throws, the `catch` returns `nil` although `url` already resolved.
- **Why:** A kill or full disk leaves truncated external data; a usable bookmark is treated as missing.
- **Action:** `.atomic` writes; return the resolved `url` even when the refresh fails.
- **Severity:** Low
- **Tag:** [NEW]

### 5.26 PDF search keeps every match and publishes partial results on a stale end notification
- **Location:** `Modules/PdfRPG/Pdf/PdfWrapperView.swift:~140-190`.
- **What:** `pendingMatches` is unbounded and every match is highlighted and re-assigned on each next/previous step; after the audit-22 change (no drain) the stale end of a cancelled scan reads the new scan's partial buffer, clears `isSearching` and publishes partial matches.
- **Why:** A one-letter query on a 600-page PDF can retain tens of thousands of `PDFSelection`s; the spinner drops early.
- **Action:** Cap matches (~1000) with a "more" indicator; ignore end notifications from a stale scan generation.
- **Severity:** Low
- **Tag:** [NEW]

### 5.27 Spotlight re-index version gating and failure handling
- **Location:** `Modules/CoreRPG/Persistence/RpgSpotlightIndexerDelegate.swift:59-79`; call sites `CloudKitCoreDataPersistenceController.swift:152-154`, `CoreDataPersistenceController.swift:224-226`.
- **What:** `deleteSpotlightIndex()` runs once per `indexVersion` bump with the version stored in `UserDefaults.standard`; a thrown error is swallowed and retried next launch; `Task { await startIndexing() }` is fire-and-forget per store (re)creation.
- **Why:** A store swap runs this on both delegates, and a persistent failure re-runs every launch; the `.standard` suite ignores the App Group. No data loss.
- **Action:** Log the failure; one shared guard so two controllers cannot delete the index twice in one launch.
- **Severity:** Low
- **Tag:** [NEW]

---

## 6. Security

Keychain join-code storage (`WhenUnlockedThisDeviceOnly`), passcode logging, the framer length bound, outbound queue cap, stalled-peer drop, per-source throttle, SharePlay package receiver caps, Foundry ZIP/LevelDB/Snappy readers, `CloudDocumentController` path checks, `GuardedRemoteDownload` and all entitlements/Info.plist were examined and found sound. No hardcoded secrets or Keychain misuse found. Accepted from earlier audits and not re-reported: PSK offline brute force, public session-id lure, any-id asset requests (22 §6.4), SharePlay master pinning removal.

### 6.1 Shown pins inside unrevealed rooms are sent to players
- **Location:** `Modules/MapRPG/Controller/GameController+Sync.swift:42` (`pinsVisibleToPlayers`: `model.mapPins.filter(\.isShown)`), `Modules/MapRPG/Model/MapSnapshot.swift:161` (`redactedForNonMaster`), `Modules/MapRPG/Controller/GameController+Pins.swift:198` (`missingMapImages`); `Modules/MapRPG/Map/MapPinPlacement.swift:39`. The client-side rule: `Modules/GameRPG/Table3D/GameTableProjection.swift:44, 189`, `Modules/MapRPG/Model/MapModel+Geometry.swift:22-24`.
- **What:** Both server-side redactions drop a pin only when `!isShown`. Pins created by drop or "add monsters" are `isShown: true`, so a monster placed in an unrevealed room goes out. The client hides non-player pins whose location lies in a hidden room (`isLocationHiddenForPlayers`) and the 3D table explicitly treats fog as hiding monsters — but the master still sends them.
- **Why:** The `.mapState` and the map package carry name, `photoId`, `characterId`, `location` and `healthPercent` of those pins, and `missingMapImages` requests their photos. A modified client or anyone inspecting traffic sees monsters behind fog before the GM reveals the room. This is the same class as 22 §6.1. [verified: filter lines read; whether fog is meant to hide shown monsters is inferred from the client rule and should be confirmed by the design owner]
- **Action:** Treat "hidden" as `!isShown` OR (`!isPlayer` and the location lies in an unrevealed room) in `pinsVisibleToPlayers`, `redactedForNonMaster` and the photo-request path; re-evaluate when a room is revealed so those pins and photos go out then.
- **Severity:** High
- **Tag:** [INCOMPLETE FIX of CODE_AUDIT_22 §6.1 / CODE_AUDIT_22a §6.2]

### 6.2 Smaller redaction leftovers in player-bound state
- **Location:** `Modules/MapRPG/Controller/GameController+Sync.swift:33` (pointer), `Modules/MapRPG/BattleRound/BattleRoundModel+Network.swift:29-38` (`activePinId`), `Modules/MapRPG/Model/MapSnapshot.swift:161-176` (map `description`/`tags`, background photo).
- **What:** The pointer is always in `.mapState` with its position even when hidden; `activePinId` can name a hidden pin; map description and tags are in the player package.
- **Why:** Low-grade leaks (players learn an unseen token is acting). Room geometry/background photo were accepted in 22a §6.2.
- **Action:** Blank the pointer location while hidden; send `nil` for `activePinId` when that pin is not visible; decide whether the description is GM-only.
- **Severity:** Low
- **Tag:** [NEW]; room geometry part [STILL OPEN from CODE_AUDIT_22a §6.2], accepted

### 6.3 Player `.playAudio` payload relayed and retained without a bound
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift` (`handleAudio` `.playAudio` → `requestAudioPlay`, `broadcastAudioPlay`, `pendingAudioPlays`, `scheduleAudioPlayRetry`; `maxAudioPlayRetryAttempts` = 5).
- **What:** `.playAudio` from any player is gated only by `features.audioSharing`, with no role or size check. The master stores the whole payload in `pendingAudioPlays[data.id]` (peer-supplied key) and re-broadcasts the player's `NetworkCodableDataType` including `data.data` (up to 100 MB) to all players.
- **Why:** One player can make the master send up to 100 MB to N players and hold it ~25 s (5 retries × 5 s; unknown ids always have missing players). Not a group event, so the 256 KiB cap does not apply.
- **Action:** Validate the request, then rebuild the outgoing message from the parsed `AudioPlayRequest` instead of relaying the blob; cap size and pending entries per sender.
- **Severity:** Medium
- **Tag:** [NEW]

### 6.4 Group events relayed before the master validates them
- **Location:** `Modules/GameRPG/Network/GameNetworkController+MasterDelegate.swift` (`masterReceived`); `GameNetworkController+SharePlayDelegate.swift` (`routeSharePlayUpdate`); `Controller/MasterController+DiceMessages.swift` (`isPlausibleReport`, `dicePlayers` gate); `Controller/PlayerController+Dice.swift`.
- **What:** The 256 KiB size cap exists now, but plausibility, feature gate and pin/space validity still run after the relay; receivers do not re-check plausibility; duplicate events (same counter) are relayed again because dedup happens only inside the pipeline.
- **Why:** A modified client can make the master forward implausible dice reports or events for disabled features to every player, and duplicates multiply traffic. [reasoned from call order]
- **Action:** Validate and dedup before relaying, or relay only what the master accepted; have receivers re-check plausibility.
- **Severity:** Medium
- **Tag:** [STILL OPEN from CODE_AUDIT_22 §6.3 (partial)]

### 6.5 SharePlay Journal attachments have no receive-side size cap
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+JournalAttachments.swift`.
- **What:** `attachment.load(Data.self)` is not checked against `GameLimits.maximumMessageBytes` and the Journal path has no per-sender byte budget (the Messenger path has `inboundByteBudget`); `handle()` calls `loadMetadata` for every attachment on every snapshot before `journalLedger.shouldProcess`.
- **Why:** A participant can attach oversized blobs that every device loads; cost grows through the session. [reasoned]
- **Action:** Cap size before loading, give the Journal path the Messenger's per-sender budget, check the ledger first or cache metadata per attachment id.
- **Severity:** Low
- **Tag:** [NEW]

### 6.6 A shared web URL is downloaded in full before the MIME check
- **Location:** `Sources/RPGShare/ItemProviderImporter.swift:23` (`permissibleTypes = [.image, .url]`), `:159-175`, `:92-98`.
- **What:** Any provider conforming to `public.url` is an image candidate; the URL is fetched with `allowsPrivateHosts: true` up to 256 MB and only afterwards `response.mimeType?.hasPrefix("image/")` is checked. Separately, an `image/*` response of ≤ 8 MiB is passed through without checking it decodes and stored as a Photo.
- **Why:** Sharing a link or page from another app triggers a GET the user did not ask for (private hosts, one-shot links) and can burn up to 256 MB of disk/time in the extension before rejecting a non-image.
- **Action:** Fetch remote URLs only when the provider also conforms to an image type; reject by response headers before saving the body; verify with `CGImageSource` before accepting raw bytes.
- **Severity:** Medium
- **Tag:** [NEW]
- **Verified:** lines 23 and 167-173 read by the agent

### 6.7 Photo decode paths never apply the declared-size limits
- **Location:** `Modules/CoreRPG/Extensions/Image+AKImage.swift:226-336` (`boundedDecode`, `downsampledThumbnail*`), `Modules/PhotoRPG/Controller/CacheController.swift:45-46`, `PhotoRPG/Controller/EditController.swift:88`, `FileUrlDataController+ImageResolve.swift`.
- **What:** `ImageDownsampler` defines `maximumDeclaredDimension` (16384) and `maximumDeclaredPixelCount` (150 MP) but only the Foundry importer calls `declaredSize(of:)`. Photo display/thumbnail/import skip it and fall back to `AKImage(data:)` / `AKImage(contentsOfFile:)` on a nil result.
- **Why:** A 30000×30000 PNG (dropped file, share extension, peer-sent photo) reaches ImageIO without the header guard; if `boundedDecode` returns nil the fallback decodes at native size, and `importedJPEG` forces that via `jpegData` (~3.6 GB at 4 B/px). CODE_AUDIT_21 §9.5 asked for one helper with the header guard.
- **Action:** Call `declaredSize(of:)` inside the shared helper (`.overLimits` → nil) and drop the `?? AKImage(data:)` fallback for over-limit/unknown sizes.
- **Severity:** Medium
- **Tag:** [INCOMPLETE FIX of CODE_AUDIT_21 §9.5]
- **Verified:** `CacheController.swift:45` `AKImage.boundedDecode(from: $0) ?? AKImage(data: $0)`; `declaredSize` referenced only in `FoundryMediaNormalizer.swift:171`

### 6.8 Foundry markdown escaping (`inert`) leaves newline and heading/list injection open
- **Location:** `Modules/RuleRPG/Model/RuleModel+FoundryFactory.swift:182-194`; call sites `:116-122`, `:137`, `:153`, `:204-236`.
- **What:** `inert` escapes only `\ * _` and backtick and splits `](` and `://`; a value containing `\n` can start a new line such as `# heading`, `> quote`, `- **x**`, `[x]: ref` or `<tag>`.
- **Why:** Hostile Foundry content can forge list rows or headings in the Effects/Values sections; it cannot create a link because `://` is split. Mostly fidelity.
- **Action:** Collapse `\n`/`\r` in `inert` and escape leading `#>-+[<`.
- **Severity:** Low
- **Tag:** [INCOMPLETE FIX of CODE_AUDIT_22 §6.5]

### 6.9 Privacy manifest missing for the extensions
- **Location:** `Resources/PrivacyInfo.xcprivacy` is the only one; `Sources/DiceRollerWidget` (`DiceRollerProvider.swift`, App Group `UserDefaults`) and `Sources/RPGShare` (file timestamp APIs via CoreRPG) have none.
- **What:** The manifest is listed in three Resources phases only.
- **Why:** Required-reason API use in the extension bundles is undeclared; App Store processing may flag it.
- **Action:** Add manifests to both extension targets or confirm the app's manifest covers them.
- **Severity:** Low
- **Tag:** [STILL OPEN from CODE_AUDIT_22 §13 (row 6.5)]

### 6.10 Intents: `JoinGameIntent` code parameter, `NextTurn`/`EndBattle` without authentication
- **Location:** `Modules/GameRPG/Intent/`.
- **What:** `JoinGameIntent` accepts the join code as a parameter so a Shortcut could loop over codes; `NextTurn` and `EndBattle` require no unlock.
- **Why:** The code loop is limited by the per-source throttle; the others are trivial gameplay actions on the master's own device. [reasoned]
- **Action:** Document the choice or require unlock.
- **Severity:** Low
- **Tag:** [NEW]

---

## 7. Performance

### 7.1 Statistics: one event row per message, unindexed dedup lookup, whole-table reads
- **Location:** `Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift` (`recordEvents`, `fetchDataSet`); `Statistics/Model/GameStatisticsModel.swift` (`reportAchievements`, `finishSession`, `setUp`); `Resources/GameStatistics.xcdatamodeld`.
- **What:** Every in/out message becomes a CloudKit-synced Core Data event row with no retention. `recordEvents` runs a `context.count` fetch on `sessionID == %@ AND deduplicationKey == %@` per event with no index on `deduplicationKey`; `reportAchievements` calls `fetchDataSet(interval: nil, …)`, loading all events of all completed sessions after every `finishSession` and at `setUp`.
- **Why:** Insert cost grows with session size (quadratic per session); rows accumulate forever; the whole-history fetch slows each session and runs through `databaseModel.context` on the main actor (main-queue context not confirmed).
- **Action:** Index `deduplicationKey` (or keep an in-memory key set per session) and dedup within the batch; aggregate events into per-session rows or prune; make `reportAchievements` incremental and off the main context.
- **Severity:** Medium
- **Tag:** [NEW]

### 7.2 Sync hashes the full content of every new file in series, with no progress and no size bound
- **Location:** `Modules/CoreRPG/Controllable/CloudScanController.swift:100-104` (`newItemHashes`), `:44`; `Files/CloudFolderScan.swift:238-250`.
- **What:** The 22 §5.11 fix makes `apply` call `CloudFolderScan.hashes(of:)`, a serial loop of coordinated full reads, before `DataMutationCoordinator.begin()`.
- **Why:** The first Sync of a module folder with thousands of audio/PDF/USDZ files (GBs) reads every byte with no progress or cancel hint; coordinated reads of partially evicted files can block on iCloud download slots.
- **Action:** Hash lazily (on first use or in the background after insert), or cap per-file size/count and hash with bounded concurrency and progress.
- **Severity:** Medium
- **Tag:** [NEW] (introduced by the 22 §5.11 fix; not reviewed in 22a)

### 7.3 Map editor undo history is unbounded and each step copies the map
- **Location:** `Modules/MapRPG/Map/MapEditorPinHistory.swift:33-70` (`record`, `undoStack`), `MapEditController.swift:85-97`.
- **What:** Every mutation appends a full `MapModel.copy()`, runs `snapshot != current` (full equality) and copies again for `current`; no depth cap.
- **Why:** On a hex-grid map (up to 20,000 cells) each pin drag or vertex edit copies the entries array and compares O(n) on the main actor; memory grows with every edit. [reasoned]
- **Action:** Cap the stack (50-100), store diffs/changed arrays, compare with a version counter.
- **Severity:** Medium
- **Tag:** [NEW]

### 7.4 PDF thumbnail strip is sized to the full page count, defeating `PDFThumbnailView` virtualization
- **Location:** `Modules/PdfRPG/Pdf/PdfContentView.swift:96-110`, `ThumbnailPdfView.swift`.
- **What:** `PDFThumbnailView` is wrapped in a SwiftUI `ScrollView` and framed to `(pageCount + 1) * thumbnailSize`, so its own scroll view shows all content.
- **Why:** Every page's thumbnail cell is created up front (a 600-page rulebook: ~600 thumbnails, ~150 MB at 3×). [reasoned: frame arithmetic in the file, collection-view behaviour inferred]
- **Action:** Give the thumbnail view the viewport size and let it scroll itself.
- **Severity:** Medium
- **Tag:** [NEW]

### 7.5 Share extension decodes full-size images in `body` and has no total text cap
- **Location:** `Sources/RPGShare/PhotoSection.swift:24` (`AKImage(data:)` in the `ForEach` row); `ItemProviderImporter.swift:208-210` (`maximumDownsampledPixelDimension = 4_096`, up to 60 MiB total); text path `:55-76`, `:216-234`; `SharingView.swift:189-194`.
- **What:** Images are kept as JPEG up to 4096 px per side and re-decoded on each body evaluation; `.text(String)`/`.data` items are unbounded and file/URL texts are capped at 5 MiB each with no sum, joined into one edit field.
- **Why:** One square 4096 px bitmap is ~67 MB; two visible ones plus the import peak exceed the ~120 MB extension limit and the share is killed. Several large texts can exhaust memory or freeze the editor. [reasoned]
- **Action:** Build a ~1024 px preview thumbnail once at import (ImageIO), keep the full data only for saving; cap the total characters like `maximumTotalImagePayloadSize`.
- **Severity:** Medium
- **Tag:** [NEW]

### 7.6 Image cache cost counted in points, and disk decode runs inside the actor
- **Location:** `Modules/CoreRPG/Cache/ImageCacheController.swift:31` (`Int(object.size.width * object.size.height * 4)`), `Cache/ObjectCache.swift:11-92`.
- **What:** `totalCostLimit` is 256 MiB but cost uses `size` in points (up to 9× undercount on 3× devices); the `ObjectCache` actor does disk reads and `AKImage(data:)` inside `loadImageFromDisk`, blocking in-memory hits behind a slow decode.
- **Why:** Photo/map/space lists can hold ~1-2 GB of bitmaps before eviction (jetsam risk on iPhone); scrolling stalls behind a decode.
- **Action:** Use pixel dimensions for cost; move disk read/decode to a `@concurrent` helper.
- **Severity:** Low (Medium on iPhone with large libraries)
- **Tag:** [NEW]

### 7.7 Fog/boundary canvas walks every room on each pan or zoom frame
- **Location:** `Modules/MapRPG/Map/MapRoomCanvas.swift:80-95` (`orderedSnapshots`), `MapEntryViewer.swift:18` (`path.boundingRect` uncached).
- **What:** The 21 §7.8 fix culls drawing, but `body` still iterates all room nodes and recomputes `boundingRect` for each.
- **Why:** A 20,000-cell hex map costs ~20k bounding boxes per frame and ~20k observation dependencies. [reasoned]
- **Action:** Cache bounds in `MapRoomNode`; spatial index for the visible-rect query; one aggregate for visibility.
- **Severity:** Low
- **Tag:** [NEW] (partial follow-up to CODE_AUDIT_21 §7.8)

### 7.8 Per-room thumbnail rotation on the main actor
- **Location:** `Modules/MapRPG/Controller/CacheController.swift:29-42`, `Extensions/UIImage+Crop.swift:6-33, 66-70`.
- **What:** Each room thumbnail redraws the whole (≤1024 px) image rotated when `degrees != 0`, then crops; `createThumbnail` is `@MainActor`.
- **Why:** A rotated map with many rooms repeats a 4-8 MB CGContext draw per room on the main thread.
- **Action:** Rotate once per photo or crop first, then rotate; run off the main actor.
- **Severity:** Low
- **Tag:** [NEW]

### 7.9 Quadratic scans on large folders and imports
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:270-273` (`!missing.contains(childId)` per child), `ItemControllable.swift:408-426` (`libraryFileUrls` rebuilds an n-element array per call, called from `addFile`, `settleImportedFile`, `isFileUsedElsewhere`), `Links/QuickLinkScanner.swift:88-101` (`replacements.contains`/`protectedRanges.contains` per match, main actor).
- **What:** `repairFolders` is O(m²) per batch folder; importing/deleting n file items costs n × library-size array builds.
- **Why:** A 5,000-file import into one folder costs tens of millions of operations on the main actor. Timing not measured.
- **Action:** `Set` for `missing`; one `[name: [FileUrl]]` index per batch; interval/`IndexSet` overlap checks in the quick linker.
- **Severity:** Low
- **Tag:** [STILL OPEN from CODE_AUDIT_21 §7.1] for `libraryFileUrls`; rest [NEW]

### 7.10 Roster churn triggers a full map/state rebroadcast
- **Location:** `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift` (`resetPlayers()` from `process` and `lostPlayer`).
- **What:** Every join/leave sends the full map content and state to all players.
- **Why:** Reconnect flapping at an N-player table multiplies large package traffic.
- **Action:** Send the roster delta; send full content only to the newly joined player.
- **Severity:** Low
- **Tag:** [NEW]

### 7.11 Statistics record path: one unstructured Task per message; unbounded interval splitting
- **Location:** `Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift` (`pendingEvents`), `GameStatisticsController.swift` (`splitInterval`).
- **What:** `statistics.record` spawns a `Task` per message and `pendingEvents` can grow while flushes are slow; `splitInterval` loops per hour/day bucket across [start, end].
- **Why:** Memory growth in a message flood; a bogus long session span (clock jump) causes a huge loop. [reasoned]
- **Action:** One `AsyncStream` consumer for recording; cap bucket count or session span.
- **Severity:** Low
- **Tag:** [NEW]

### 7.12 `audioList` is O(items × playlist depth) with file-status checks on the main actor
- **Location:** `Modules/AudioRPG/Controller/GameController.swift:~194-215` (`audioList`, `hasLocalDatabaseAudioData`).
- **What:** For every library item it awaits a recursive playlist check; each node calls `hasDownloadedData` (filesystem/ubiquity query); members are checked as members and again as items.
- **Why:** ~1000 tracks and many playlists issue thousands of file-status calls on `@MainActor` when players join or resync. [reasoned]
- **Action:** Memoize per item within one call and build one id→downloaded map.
- **Severity:** Low
- **Tag:** [NEW]

### 7.13 Sheet `update` rebuilds each entry's whole subtree on every update
- **Location:** `Modules/CharacterRPG/Controller/SheetController.swift:~169-182`.
- **What:** `update(entry:)` rebuilds the projection from scratch (nested groups and cross-module sheets via `SheetLinkGuard`) just to diff name and description, then recurses into the existing child's `update`.
- **Why:** O(subtree × group depth) per entry per update. [reasoned]
- **Action:** Project only the entry's own name/description/type and direct child identity; let `update` recurse.
- **Severity:** Low
- **Tag:** [NEW]

### 7.14 `AsyncThumbnail` load key contains the whole `FileUrl` including inline `Data`
- **Location:** `Modules/PhotoRPG/Photo/AsyncThumbnail.swift:~69-78, 100-106`.
- **What:** `AsyncThumbnailLoadKey.fileUrl` is a `FileUrl?` whose synthesized `Equatable` compares `data`; equality runs in `body` and for `.task(id:)`.
- **Why:** Inline-data photos (a player's received photos) compare megabytes per body pass. [reasoned]
- **Action:** Key on `fileId`, `contentHash` and `hasInlineData`.
- **Severity:** Low
- **Tag:** [NEW]

### 7.15 Reveal-added-row modifier maps the whole list on every change
- **Location:** `Modules/CoreRPG/LGViews/ListRootView.swift:249` (`.onChange(of: listModel.list.map(\.id))`).
- **What:** Allocates an id array and does an O(n) `==` per list mutation in a modifier that only matters while `pendingRevealItemId != nil`.
- **Why:** Cost grows with collection size on every search keystroke or sync update. Not measured.
- **Action:** Observe a cheap token (count plus generation counter) or act only while a reveal is pending.
- **Severity:** Low
- **Tag:** [NEW]

---

## 8. SwiftUI / UI

The SwiftUI layer is clean against `CLAUDE.md`: 0 hits for `foregroundColor`, `tabItem`, 1-parameter `onChange`, `Task.sleep(nanoseconds:)`, `UIScreen.main`, `fontWeight(.bold)`, `ScrollViewReader`, `Array(…enumerated())`, `showsIndicators`, `.font(.system(size:))`, `NavigationView`; `.animation` always carries `value:`; no `UUID()`/index ids in `ForEach`; the ~60 `State(initialValue:)` sites are previews/drafts/one-shots; image-only buttons all carry labels. Accepted exceptions: `.cornerRadius(5)` is the Charts `SectorMark` API; `onTapGesture(count: 2)` in `InspectorRowView.swift:73`; 4 `UIGraphicsImageRenderer` sites are image-to-image processing (`Image+AKImage.swift:144`, `GameTableEntities.swift:68`); 11 UIColor/NSColor uses are conversions. The 22 §13 "map canvas VoiceOver" open item looks fixed (`MapRoomCanvas.swift:288-300`).

### 8.1 Hidden panels and controls use `opacity(0)` + `allowsHitTesting(false)` instead of `.disabled`
- **Location:** `Modules/GameRPG/GameViews/OnlyGameView.swift:23-28`, `OnlyPlayerGameView.swift:23-29`; `Modules/MapRPG/Map/HexMapScaleView.swift:75-78`, `MaxSizeScaleView.swift:61-64`, `PinScaleView.swift:38-41`, `GameToolBar.swift:41-44`; `Modules/CoreRPG/LGViewModifiers/ToolbarItemListViewModifier.swift:203-206`; `Modules/PdfRPG/View/DetailEditorView.swift:39-41`, `Modules/AudioRPG/View/DetailEditorView.swift:32-34`; `Modules/GameRPG/SetupViews/SharePlayButton.swift:30-33`; four `DropChooseView.swift` copies (Adventure :44-52, Character :49-57, Photo :44-53, Dice :44-52). ~15 sites.
- **What:** A control is "hidden" with opacity 0 + hit testing off + `accessibilityHidden` but stays in the hierarchy.
- **Why:** It remains in the keyboard focus loop (macOS Full Keyboard Access/Tab, iPad hardware keyboard) and, not verified, tvOS focus/Switch Control; an invisible Remove/Close/scale button or a whole game panel can take focus and fire on Return/Space.
- **Action:** Add `.disabled(hidden)` or drop the view conditionally (`ToolbarItemListViewModifier` has a real reason to keep it in the tree; `.disabled` still works there).
- **Severity:** Medium
- **Tag:** [NEW]

### 8.2 Dice result outcome conveyed by green/red only, in a fixed 44 pt circle
- **Location:** `Modules/DiceRPG/Game/Detail/DieViewerView.swift:35-47`, `:82-85` (`color(for:)`), `:87-92` (`accessibilityValue`).
- **What:** Success/failure per roll is green vs red on a translucent circle; the accessibility value lists only numbers; text is `.font(.title)` in `.frame(width: 44, height: 44)`.
- **Why:** The outcome is lost for VoiceOver and colour-blind users; 3-digit results (d100) and larger Dynamic Type clip.
- **Action:** Add "success"/"failure" to the accessibility value, a symbol/shape cue (honour `accessibilityDifferentiateWithoutColor`), `ScaledMetric`/`minimumScaleFactor` for the bubble.
- **Severity:** Medium
- **Tag:** [NEW]

### 8.3 Widget roll result: coup/fumble is colour-only
- **Location:** `Sources/DiceRollerWidget/DiceRollerWidgetView.swift:161-186` (`DiceResultView`), `:217-229` (`resultColor`).
- **What:** Green/red/blue tint encodes coup/fumble/rolled; `.accessibilityValue` is `"\(result.sum)"` and `.accessibilityElement(children: .ignore)` hides the rest; in tinted mode the circle is dropped.
- **Why:** The outcome is invisible to VoiceOver and in accented/tinted widgets.
- **Action:** Put the outcome in label/value and show an icon (star/triangle/check as in `RollSpecificDiceIntent.swift:160-185`).
- **Severity:** Low
- **Tag:** [NEW]

### 8.4 Plain `withAnimation` and slide transitions ignore Reduce Motion
- **Location:** 115 plain `withAnimation` calls in ~48 files, ~40 with no reduce-motion check: `Modules/CoreRPG/ViewModifiers/LinkDragViewModifier.swift` (22), `GeneratorRPG/Controller/GeneratorController.swift` (10), `MapRPG/View/MapPinActionMenu.swift` (4), `CoreRPG/EntryEditor/QuickEntryEditorView.swift` (4), `RolePlayGameKit/View/SettingsView.swift` (3), `MapRPG/View/QuickEntryEditor.swift` (3), `CoreRPG/Sheet/SheetContextMenuView.swift` (3), `CoreRPG/LGViews/EditorLinkView.swift` (3), `TableRPG/View/TableGenerationHeaderView.swift:~30`, `CoreRPG/Menu/UndoButton.swift`/`RedoButton.swift`, `CoreRPG/LGViews/ListRowItemView.swift`, `ItemRowsView.swift:46`. Transitions without alternative: `GameRPG/GameViews/PlayerOverlayMenu.swift`, `MasterOverlayMenu.swift`, `BattleRound/BattleRoundList.swift`, `CoreRPG/Sheet/SheetEntryRowViews.swift`, `SheetEntryReviewAlternativesView.swift`, `CoreRPG/ItemDetail/ItemFileImporterView.swift`, `TableRPG/View/TableGenerationPanelView.swift`. Repeating effects: `GameRPG/GameViews/BatteryView.swift:28` (`symbolEffect(.pulse, options: .repeating)`), `CoreRPG/Views/FlipView.swift:53,58`, `DiceRPG/View/ThumbnailDice.swift:15`.
- **What:** These bypass the shared `Animation.reduced(if:)` helper (`CoreRPG/Extensions/Animation+ReducedMotion.swift`); 22 §8.3's claim that all repeating animations honour Reduce Motion is not quite true.
- **Why:** List insert/remove springs, move transitions and the low-battery pulse still run with Reduce Motion on.
- **Action:** Route through `reduced(if:)` or a `withReducedAnimation` wrapper, starting with user-driven list/sheet mutations; swap to `.opacity` transitions; gate `isActive` on `!reduceMotion`.
- **Severity:** Low
- **Tag:** [NEW] (extends CODE_AUDIT_22 §8.5)

### 8.5 Audio playback controls: Reduce Motion fix incomplete, small targets
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerPlaybackControls.swift:19, 33, 51` (plain `withAnimation`), `:26, :58` (32×32 prev/next with `.buttonStyle(.plain)`), `:44` (play 44×44).
- **What:** 22 §13 marked §8.5 fixed in `AudioPlayerMiniBarView` and called it "the only motion path in the audio module"; this sibling still uses plain `withAnimation`; `.font(.title3)` sits inside a fixed 32 pt frame.
- **Why:** Reduce Motion ignored on the main player bar; targets under 44 pt; large Dynamic Type clips the glyph.
- **Action:** `reduced(if:)`; `minWidth/minHeight: 44` or `ScaledMetric`.
- **Severity:** Low
- **Tag:** [INCOMPLETE FIX of CODE_AUDIT_22 §8.5/§13]

### 8.6 Small tap targets in the map editor and detail overlay
- **Location:** `Modules/MapRPG/Map/EditMapToolBar.swift:83-86` (and ~57), `HexMapScaleView.swift:45`, `ChooseMapPinsButton.swift:35` (24 + `padding(8)` = 40); `Modules/CoreRPG/ItemDetail/ItemDetailContentView.swift:108-118` (xmark button ~30 pt, `.transition(.move(edge: .bottom))` at :124, `.asAnyView()` at :106 inside `body`).
- **What:** `.frame(width: 24, height: 24)` is applied outside a `.buttonStyle(.bordered)` Button (derived from code, not rendered); the overlay close button is a bare 8 pt-padded glyph.
- **Why:** Sub-44 pt targets; a bordered button squeezed into 24 pt may clip its chrome on iPhone.
- **Action:** Remove the fixed outer frame; use `minWidth/minHeight: 44` and `ScaledMetric` icon sizing; opacity transition under Reduce Motion.
- **Severity:** Low (verify on device)
- **Tag:** [NEW]

### 8.7 `ListRowItemView ==` compares an always-equal value and omits `leadingPadding`
- **Location:** `Modules/CoreRPG/LGViews/ListRowItemView.swift:28-33`; `ItemRowsView.swift:56-59`.
- **What:** `isSelected` is computed from the same live `listModel` reference on both sides, so that term is always true; the stored `leadingPadding` (12 vs 8 in selection mode) is not compared.
- **Why:** The inset likely stays stale until the row is recreated (cosmetic, 4 pt); the comparison misleads readers. [reasoned]
- **Action:** Drop `isSelected` from `==`; include `leadingPadding` or read `isSelectionMode` inside the row.
- **Severity:** Low
- **Tag:** [NEW]

---

## 9. Dead code / duplication / refactor

### 9.1 Dead UIKit responder-chain keyboard dismiss (`HideKeyboardView`)
- **Location:** `Modules/CoreRPG/Views/HideKeyboardView.swift:29`; only reference is `hideKeyboardView(show:)` at `Modules/CoreRPG/Views/HideKeyboardFocusView.swift:6-11`, which has no callers; a snapshot test touches the view.
- **What:** An unused UIKit path next to the live `@FocusState` version (`hideKeyboardView(enabled:focusedField:)`, used by `Sources/RPGShare/SharingInput.swift:35`).
- **Why:** Dead code using an old pattern.
- **Action:** Delete `HideKeyboardView`, the `show:` overload and the snapshot test.
- **Severity:** Low
- **Tag:** [NEW]

### 9.2 `Die20.restingOrientation` and `Die6.restingOrientation` are dead, with a measured normals table
- **Location:** `Modules/GameRPG/Table3D/GameDice.swift:94-~135`, `:139-~215` (`faceNormals`, used only by the D20 method), `:279-~330`.
- **What:** Neither method has a caller; the only other references are comments (`GameInteraction.swift:69`, and `GameDice.swift:219, 302`). [verified: grep for `restingOrientation` finds only the two declarations and comments]
- **Why:** About 150 lines, including a hand-measured 20-entry mesh table, in a file that must track the 3D assets.
- **Action:** Delete both methods and `faceNormals`, or wire them back in if the toss path should use them.
- **Severity:** Medium
- **Tag:** [NEW] (symbol last cited in CODE_AUDIT_2)

### 9.3 Per-module boilerplate families are still copied
- **Location (current counts):** `Intent/*ManagementIntents.swift` ×10 (2,300 lines, ~70% identical after renaming; `PdfManagementIntents.swift:36-80` is the template); `Controller/GameController.swift` ×10 (Pdf vs Space 98%); `Controller/DataController.swift` ×10 (Photo vs Audio 98%); `Controller/ExportController.swift` ×8 (91%); `Controller/LinkController.swift` ×10 (90%); `View/DetailListView.swift` ×11 (95%); `View/DetailFolderListView.swift` ×10 (96%); `View/EmptyDropButton.swift` ×4 (100%); `View/DropChooseView.swift` ×4 (84%); `View/QuickEntryEditor.swift` ×4 (94%); `Resources/BundleModule.swift` ×11; `Controller/SyncDataController.swift` ×10; `Root/LinkRootView.swift` ×10; `Root/*RootModel.swift` init/setUp ×12; `Intent/*IntentSupport.swift` ×11.
- **What:** The same files are copied with a module-name swap.
- **Why:** A routing, bundle or intent change touches 10-12 files; the copies have already drifted (§9.4, §5.10).
- **Action:** Follow audit 17's order: one generic CoreRPG helper for bundle/localization, `DetailRoute`, `FolderListController`, `SyncDataController`, then shared intent bodies. Do `EmptyDropButton`, `DropChooseView` and `QuickEntryEditor` now (4 exact copies).
- **Severity:** Medium
- **Tag:** [STILL OPEN from CODE_AUDIT_15 §9.14 and CODE_AUDIT_18 §9.13, deferred]

### 9.4 `PlayerController+Photo/Pdf/Space` remain three near-copies that have diverged
- **Location:** `Modules/GameRPG/Controller/PlayerController+Photo.swift` (108 lines), `+Pdf.swift` (86), `+Space.swift` (120).
- **What:** After renaming, Pdf and Space still differ in 56 lines; Photo has its own `presentX`/`holdsFile` flow the other two lack.
- **Why:** Every fix must be made three times, and a repair-handling gap in one copy goes unnoticed. Whether Photo's missing repair bookkeeping is a live bug was not traced.
- **Action:** Extract one file-presentation handler parameterised by module and decide on purpose which repair behaviour all three get.
- **Severity:** Medium
- **Tag:** [STILL OPEN from CODE_AUDIT_21 §9.5]

### 9.5 Fakes, MockData and PreviewData still ship in release builds
- **Location:** `Modules/CoreRPG/Fake/` (22 files, 980 lines, 19 without `#if DEBUG`); `Modules/*/Model/MockData.swift` ×13 (811 lines, 0 gated); `PreviewData.swift` ×13 (3,005 lines, 12 gated); `Modules/CoreRPG/Simple/SimpleSheetEditingSession.swift:79-80` builds production objects from `FakeExportController` and `FakeGameController`; `TestFixtures.swift:5` documents "not gated".
- **What:** Test doubles are a production dependency.
- **Why:** A fake change can alter shipped behaviour, and SwiftData is linked into 14 frameworks (`MockData`, `LinkDataModel`) for previews only.
- **Action:** Give `SimpleSheetEditingSession` real no-op controllers, then gate `Fake/`, `MockData` and `PreviewData` with `#if DEBUG`.
- **Severity:** Medium
- **Tag:** [STILL OPEN from CODE_AUDIT_21 §9.4]

### 9.6 Oversized files (15 above 600 lines) with concrete splits
- **Location and split:**
  - `Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift` (1282): `FoundryVTTDecoder` `:249-628`, `FoundryVTTDocumentDecoder` `:635-862`, key/embedded/known-fields helpers `:863-1146`, validators and the two cache actors `:1147-` each to their own file.
  - `Modules/SpaceRPG/Space/SpaceViewer.swift` (1212): `loadEntity` extension `:538-909` and six private subviews `:910-1212` → `SpaceViewer+Loading.swift`, `+Subviews.swift`.
  - `Modules/CoreRPG/Controllable/ImportControllable.swift` (1068): state/models `:7-165`, entry points `:185-416`, item application `:476-675`, manual-review diffing `:676-807`, file handling `:808-928`, stream reader `:990-`.
  - `Modules/CoreRPG/Controllable/EditControllable.swift` (1022): folder/collection `:327-566`, menu `:567-873`, maintenance/undo `:887-` → `+Folder`, `+Menu`, `+Maintenance`.
  - `Modules/CoreRPG/Foundry/FoundryRuleModels.swift` (847): JSON value/coding `:11-216` and manifests `:217-340` apart from rule/schema types `:438-` and `FoundryRuleIdentity` `:701-`.
  - `Modules/GameRPG/Root/GameRoot.swift` (720): the five extensions mark the seams (`:306`, `:338`, `:403`, `:584`, `:684`).
  - `Modules/RolePlayGameKit/Import/Foundry/FoundryImportView.swift` (714): nine private section views `:173-675`.
  - `Modules/GameRPG/SharePlay/RPGSharePlayController.swift` (713): lifecycle/token/coordinator value types `:23-415` leave the controller `:416-`.
  - `Modules/CoreRPG/Controllable/ItemControllable.swift` (710): editing extension `:129-678`.
  - `Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift` (705): decoders `:307-640`.
  - `Modules/DiceRPG/Model/DiceModel.swift` (694): `Codable` `:626-682`, `ItemDataAccessible` `:523-625`.
  - `Modules/CoreRPG/Persistence/CoreDataController.swift` (642): `CoreDataModel` `:16-178`.
  - `Modules/GameRPG/Statistics/Model/GameStatisticsTypes.swift` (632): enums `:8-232`.
  - `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift` (630): sender vs receiver.
  - `Modules/GameRPG/Player/PlayerNetworkController.swift` (622): six extensions → three files.
- **What:** The 15 files over 600 lines.
- **Why:** Merge conflicts, slow type-checking; the largest files keep growing.
- **Action:** Mechanical extension-file moves only; do the four CoreRPG `Controllable/` files first.
- **Severity:** Medium
- **Tag:** [STILL OPEN from CODE_AUDIT_21 §9.12 and CODE_AUDIT_22 §9.7]

### 9.7 Generator conversation remnants are still dead
- **Location:** `Modules/GeneratorRPG/BasicAI/Engine/ConversationEngine.swift:113-134` (`sendMessage`), `:255-266` (`respond(to:generationOptions:)`), `:139-142` and `:306-307` (`ResponseMode.oneShot`); `FoundationManager.swift:15`, `:49-51` (`isLanguageSupported`, `checkLanguageSupport`); `Modules/GeneratorRPG/Controller/ConversationSessionModel.swift:50-53` (`tokenUsageFraction`), `:60-80`.
- **What:** The chat view and controller were deleted but their engine entry points have no caller; `ConversationSessionModel` has a single conformer (`GeneratorSessionModel`).
- **Why:** ~70 lines of live-looking API; a mode switch only one mode uses.
- **Action:** Delete the four members, drop `ResponseMode` and the `responseMode:` parameter, fold the protocol into `GeneratorSessionModel`.
- **Severity:** Low
- **Tag:** [INCOMPLETE FIX of CODE_AUDIT_21 §9.1]

### 9.8 Dead master-side forwarding chain for "available to current players"
- **Location:** `Modules/CoreRPG/Controllable/FileVersionGameControllable.swift:140` (`markFileAvailableToCurrentPlayers`); forwarders and protocol requirements `Modules/PhotoRPG/Controller/GameController.swift:15, 45`, `Modules/PdfRPG/Controller/GameController.swift:20, 52`, `Modules/SpaceRPG/Controller/GameController.swift:144, 192`; `Modules/MapRPG/Controller/GameController.swift:224` and `GameController+Sync.swift:74` (`networkMapGeneration`).
- **What:** Each name is declared (protocol plus implementation) and never called.
- **Why:** Dead protocol surface in four modules that obscures the Photo/Pdf/Space version-ledger flow.
- **Action:** Delete the 3 protocol requirements, 3 forwarders, the CoreRPG helper and `networkMapGeneration`.
- **Severity:** Low
- **Tag:** [NEW]

### 9.9 Smaller unreferenced declarations that remain
- **Location:** `Modules/CoreRPG/Model/ItemListable.swift:10-12` (`DisplayStateMask.nameHidden`, `.descriptionHidden`, `.otherHidden`); `CoreRPG/LinkRenderer/LinkHighLightLocations.swift:103` (`.italic`); `CoreRPG/Persistence/PersistentHistoryTrackerManager.swift:11` (`AppPersistentActor.rpgWidget`); `MapRPG/Model/MapWallModel.swift:23` (`Flags.legacyNormal`); `SpaceRPG/Record/AppDataModel.swift:115` (`endCapture()`); `GameRPG/Statistics/Model/GameStatisticsTypes.swift:60` (`participantJoined`); `GameRPG/SharePlay/RPGActivity.swift:17` (`activityIdentifier`); `GeneratorRPG/Menu/GeneratorCommands.swift:11` (documented as kept); `PhotoRPG/Controller/ShareImportPhotoController.swift:16` (`addNewPhoto`, public API kept).
- **What:** Nine declarations with no reference at all.
- **Why:** The unused `DisplayStateMask` cases suggest bitmask semantics the code does not implement.
- **Action:** Delete them; `participantJoined` has an implicit Int16 raw value, so give the other cases explicit values before removing it.
- **Severity:** Low
- **Tag:** [STILL OPEN from CODE_AUDIT_21 §9.3 and CODE_AUDIT_22 §9.2]

### 9.10 Production members used only by tests
- **Location:** `Modules/CharacterRPG/Model/ValueModel.swift:119` (`quickEditEntries`), `CoreRPG/Files/CloudFolderScan.swift:102` (`selectableIds`), `DiceRPG/Controller/ViewController.swift:136` (`gameDiceHeight`), `GameRPG/Controller/LogGameController.swift:68` (`maxPlayers`), `MapRPG/Map/NeedleMapPin.swift:135` (`updateCoordinate`), `GameRPG/SharePlay/SharePlaySingleQueuePackageSender.swift:80` (`encodedMessageSizeLimit`), `GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift:239` (`supersedePresentation`), `GeneratorRPG/BasicAI/Engine/FoundationModelInputLimiter.swift:68` (`limitedPageTexts`), `CoreRPG/Import/ExternalImportSourceRegistry.swift:97` (`allEntries`).
- **What:** No production caller; tests are the only users. `quickEditEntries` is not even persisted.
- **Why:** The tests cover code the app never runs.
- **Action:** Delete each with its test, or switch the test to the production path; decide whether `quickEditEntries` should be persisted.
- **Severity:** Low
- **Tag:** [STILL OPEN from CODE_AUDIT_20 §9.10]

### 9.11 Unused imports
- **Location:** Combine (5): `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:6`, `RPGSharePlayController+SessionLifecycle.swift:6`, `RPGSharePlayController+TableCoordination.swift:4`, `GameRPG/Table3D/GameTableModel+RenderingReadiness.swift:13`, `GameRPG/Root/GameRootModel.swift:5`. `os` (1): `SpaceRPG/Record/CaptureOverlayView+Buttons.swift:14`. AppKit (16 files, no `NS*` symbol): `CoreRPG/Cache/ImageCacheController.swift`, `CoreRPG/Controllable/ExportControllable.swift`, `CoreRPG/Fake/PreviewAssetFixture.swift`, `CoreRPG/Fake/FakeImageCacheControllable.swift`, six `GameRPG/Controller/PlayerController*.swift`, `GameRPG/Table3D/{PortableGameRenderer,GameTableProjection,TableAssetFactory}.swift`, `PhotoRPG/Controller/{EditController,CacheController}.swift`, `PhotoRPG/Root/PhotoRootModel+PhotoAccess.swift`, `MapRPG/Extensions/UIImage+Crop.swift`. UniformTypeIdentifiers (~15 files with no `UTType` use): the six `RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper*.swift`, `Pdf/Space/AudioRPG/Controller/ItemController.swift`, `CoreRPG/Files/FileUrlDataController+Create.swift`, `CoreRPG/App/PlatformModifiers.swift`, `CoreRPG/ViewModifiers/LinkDragViewModifier.swift`, `Sources/RPGShare/{ShareViewController,SharingView}.swift`.
- **What:** Imports with no symbol from that framework in the file. The AppKit and UTType lists come from a text scan; confirm each with a build.
- **Why:** Noise and weaker module-dependency signals.
- **Action:** Remove them and build all four platforms.
- **Severity:** Low
- **Tag:** [INCOMPLETE FIX of CODE_AUDIT_22 §9.3] for Combine; [NEW] for the rest

### 9.12 103 redundant `.localizedString` lookups and 10 copies of the helper
- **Location:** Calls: `Modules/CoreRPG/Controllable/EditControllable.swift` (23), `CoreRPG/ItemList/EntryDataEditable.swift` (14), `CharacterRPG/Controller/EditController*.swift` (22), `MapRPG/Controller/EditController.swift` (9), others. Copies of the helper: `Modules/{Adventure,Audio,Character,Generator,Map,Pdf,Space,Table,Weather}RPG/Resources/Localization+Extensions.swift` and `CoreRPG/Extensions/LocalizedStringKey+String.swift`.
- **What:** `String(localized: "X", bundle: .module).localizedString` looks up the already-resolved text a second time as a key. Only 7 uses are real key lookups (`CloudKitAccountController.swift:25-35`, `MapRPG/Controller/EditController.swift:103`).
- **Why:** A wasted lookup at 103 sites; a same-named `String.localizedString` in each module means a wrong-bundle call compiles silently.
- **Action:** Drop the suffix at the 103 sites; keep one CoreRPG helper (or none) for the 7 real lookups.
- **Severity:** Low
- **Tag:** [STILL OPEN from CODE_AUDIT_16 §9.13] for the copies; the double lookup is [NEW]

### 9.13 Smaller verbatim duplicates (12 or more identical non-blank lines)
- **Location:** `Modules/MapRPG/Controller/SheetController.swift` vs `Modules/AdventureRPG/Controller/SheetController.swift` (21 windows); `TableRPG/Route/DetailRoute.swift` vs `AdventureRPG/Route/DetailRoute.swift` (11); `CoreRPG/FileViews/SingleReviewPropertyRow.swift` vs `SingleReviewReadOnlyPropertyRow.swift` (10); `PhotoRPG/Model/PhotoModel.swift` vs `SpaceRPG/Model/SpaceModel.swift` (8); `CharacterRPG/Model/ValueModel+LinkRegister.swift` vs `TableRPG/Model/TableModel+Links.swift` (4); `MapRPG/Model/MapModel+Sync.swift` vs `AdventureRPG/Model/AdventureModel.swift` (4); `CoreRPG/Settings/ColorSchemeSettingView.swift` vs `ThemeSettingsView.swift`; `CoreRPG/Editors/TextDoubleEditor.swift` vs `TextIntEditor.swift`; `DiceRPG/Model/DiceModel.swift` vs `DiceSnapshot.swift` (7).
- **What:** Copy-pasted blocks inside or across modules.
- **Why:** Lockstep edits and drift when one side is fixed.
- **Action:** Extract shared helpers or generics per pair; start with the two CoreRPG pairs.
- **Severity:** Low
- **Tag:** [NEW]

### 9.14 Functions of 120 lines or more
- **Location:** `Modules/CoreRPG/Import/ExternalImportReviewSession.swift:86` (`commit`, ~254), `GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:175` (`configureGroupSession`, ~251), `SpaceRPG/Space/SpaceViewer.swift:549` (`loadEntity`, ~244), `MapRPG/Map/EditMapToolBar.swift:32` (`body(content:)` of a `ViewModifier`, ~235), `CoreRPG/Foundry/FoundryVTTBridgeDecoding.swift:205` (`decodeContents`, ~195) and `:18` (~147), `CoreRPG/Foundry/FoundrySystemPackageReader.swift:110` (~160), `MapRPG/Controller/GameController.swift:84` (~156), `CoreRPG/Controllable/ImportControllable.swift:210` (`importStream`, ~156), `CoreRPG/Foundry/FoundryVTTImportReader.swift:443` (~141); 13 in total. Lengths from a brace-indent scan, approximate.
- **What:** 13 functions above 120 lines; `EditMapToolBar.body` is a 235-line view body.
- **Why:** Hard to test; the view body violates "view logic into view models".
- **Action:** Split into named steps; turn the toolbar modifier into sub-`View` structs.
- **Severity:** Low
- **Tag:** [STILL OPEN from CODE_AUDIT_22 §9.7]

### 9.15 Entity type names are localized without a bundle
- **Location:** `LocalizedStringResource("PDF")` and siblings at lines 14-15 of `Modules/{Pdf,Dice,Weather,Adventure,Character,Photo,Map,Space,Table,Audio}RPG/Intent/*Entity.swift`.
- **What:** Ten `TypeDisplayRepresentation` names have no `bundle:`.
- **Why:** Siri and Shortcuts may show English type names to German and Thai users; never runtime-checked.
- **Action:** Check Shortcuts in German; if English shows, pass the module bundle.
- **Severity:** Low
- **Tag:** [STILL OPEN from CODE_AUDIT_21 §8.3]

### 9.16 Thai coverage is unchecked and the localization script is still red
- **Location:** `Scripts/verify_localization.rb` (exits 1 with 12 issues: 11 `AppShortcuts.xcstrings` keys that are `stringSet` false positives, plus `Modules/GameRPG/Resources/Localizable.xcstrings` key `"%@"`). Keys with no `th` entry (92): GameRPG 28, TableRPG 13, CoreRPG 11, MapRPG 11, DiceRPG 8, RolePlayGameKit 7, CharacterRPG 4, PhotoRPG 4, AdventureRPG 2, PdfRPG 2, SpaceRPG 1, `Resources/Localizable.xcstrings` 1. `Resources/AppShortcuts.xcstrings` "Play a movie in ${applicationName}" has only an `en` stringSet in state `new`.
- **What:** The script checks German only, so Thai gaps never surface; the AppShortcuts false positives keep it red.
- **Why:** Thai users see English in up to ~85 places (some keys are format-only like `"%@, %@"`); a permanently red check gates nothing.
- **Action:** Teach the script `stringSet` and Thai; translate the real gaps; mark format-only keys as not to be translated.
- **Severity:** Low
- **Tag:** [STILL OPEN from CODE_AUDIT_22 §9.8] for the red script; Thai coverage is [NEW]

### 9.17 Magic constants and hard-coded layout values
- **Location:** Constants: `Modules/RolePlayGameKit/View/ValidateRepairView.swift:215` (`.seconds(2)`), `CoreRPG/App/AppIntentContentInvalidator.swift:26` (`.seconds(1)`), `GameRPG/SharePlay/RPGSharePlayController+JournalAttachments.swift:23-24` (`.seconds(120)`/`.seconds(30)`), `GameRPG/SharePlay/SharePlayPackageReceiver.swift:41` (`.seconds(120)`), `GameRPG/Controller/PlayerControllerModel.swift:315` (`5 * (1 << (2 * …))` backoff), `CoreRPG/Controllable/ExportControllable.swift:431` and `CoreRPG/Files/FileUrl.swift:101` (`1 << 20`, although `ByteUnit.mebibyte` exists and `ImportControllable.swift:1067` uses it), `CoreRPG/Foundry/FoundryRuleModels.swift:761-763` and `RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift:74` (four separate `1_000_000` limits). Layout: 394 numeric `.padding(n)`/`spacing: n` and 200 numeric `.frame(width:/height:)` literals, 77 uses of `44` near frame/size code (audit 21 §8.5 counted 550 padding/spacing and 103 frame).
- **What:** Timeouts, backoff and size limits are written inline; layout values are hard-coded.
- **Why:** The same limit lives in more than one place and can drift; layout values do not scale with Dynamic Type and the 44 pt hit-area literal is repeated.
- **Action:** Name each constant next to its owner and use `ByteUnit.mebibyte`; name a hit-area constant (or use `MinimumHitAreaModifier`) and a `@ScaledMetric` spacing set; retire the rest opportunistically.
- **Severity:** Low
- **Tag:** [NEW] for the constants; layout [STILL OPEN from CODE_AUDIT_21 §8.5]

### 9.18 SwiftUI rule leftovers
- **Location:** `Modules/GameRPG/Statistics/View/GameStatisticsDiceChart.swift:25` (`.cornerRadius(5)` — the SwiftUI-expert pass identified this as the Charts `SectorMark` API, so it is likely acceptable), `Modules/CoreRPG/Extensions/Image+AKImage.swift:142-144` and `Modules/GameRPG/Table3D/GameTableEntities.swift:65-68` (`UIGraphicsImageRenderer`).
- **What:** Two `UIGraphicsImageRenderer` users (image-to-image processing with a platform alias); the `cornerRadius` hit is a Charts API.
- **Why:** `CLAUDE.md` prefers `ImageRenderer` for rendering SwiftUI views; these paths render images, not views.
- **Action:** Check whether `ImageRenderer` suits the two crop paths; otherwise document the exception.
- **Severity:** Low
- **Tag:** [NEW]

**Swept and found clean:** no `TODO`/`FIXME`/`HACK`/`XXX`/`#warning`, no `#if false`, no commented-out code, no files named Old/Legacy/Deprecated/_v1; `print(` appears only in two doc comments (`SceneTrackerModifier.swift:25-26`, `:106-108`); no `NSLog`/`dump`/`debugPrint`; no `privacy: .public` on error text; no module `Text`/`String(localized:)`/`.localized(` without `bundle:` apart from `StorageOptionEditor.swift`, one preview in `MinimumHitAreaModifier.swift` and one `Label` in `GameScreenLayer.swift`; zero stale catalog keys; audit 21's misspelled symbols and preview-only views are gone.

---

## 10. Cross-cutting recommendations

- **Redaction as one predicate.** §6.1, §6.2 and §5.2 are the same family: "what may a player see" is re-implemented in the live `mapState`, the map package, the photo-request path, the content fingerprint and the client. One shared `isVisibleToPlayers(pin)` / `revealState` source used by all five would have prevented all three.
- **Fingerprints must cover every input that changes what is sent.** `contentVersion` ignores room visibility (§5.2) and the comment describing the guarantee is not enforced by a test. Add a test per redaction rule that flips only that field.
- **Fix "log and continue" persistence paths at the source.** §5.5, §5.6 and §5.12 all treat a failed read/delete as success and then act destructively on the empty result. A project rule: after a failed load, never mark a store as fetched and never write back.
- **Shared decode helper with the header guard** (§6.7) and a shared "assign and persist a missing uuid" helper (§5.10) were both asked for in earlier audits and exist only partly.
- **Test the clone/instance boundary.** §5.3 passes every existing test because none instantiates two copies of one template.
- **Reduce Motion / Differentiate Without Color as helpers, not per-site checks** (§8.2-§8.5): one `withReducedAnimation` and one outcome-cue view.
- **Rule compliance is otherwise strong:** the full `CLAUDE.md` rule sweep is clean except Id/Url casing (§4.1), so the next audit can skip those greps.

---

## 11. What was NOT audited

- No Instruments trace was recorded and no view was profiled; all performance findings are code-reading estimates.
- No tests were run and the test targets were not compiled; test files were read only to check coverage claims.
- Runtime behaviour on device (SharePlay, iCloud placeholder files, audio route changes, visionOS focus, tvOS focus) was not exercised; findings marked [reasoned] or [traced] are not reproduced.
- Foundry mapper internals (`FoundryVTTDomainMapper*`), remaining `SpaceViewer` visionOS paths and the Mac/TV app shells were not reviewed in depth.
- Third-party/SPM content (RPGTabletopGameContent, vendored Navigator) is treated as a black box.
- Localization correctness (wording) and string-catalog completeness beyond spot checks.
- Snapshot baselines under `Snapshots/` and the generated snapshot test suites.

---

## 12. Verification

Findings I re-opened and traced myself:

- **§5.1** — open `Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift` lines 141-178: `var endRange = endRanges.first; endRanges.removeFirst()` (166-167) and `endRange = endRanges.first; endRanges.removeFirst()` (176-177) are unconditional; `LinkReplaceController.linksRepair` (`Links/LinkReplaceController.swift:17-20`) only renumbers links; markers are the plain emoji at `LinkHighLightLocations.swift:99-101`. Trap traced, not run.
- **§5.2** — open `MapRPG/Model/MapUpdatePayload.swift` lines 16-37 (`contentVersion` digest over `CanonicalMapContent(…fullSnapshot)`), 116-131 (`CanonicalMapEntry` has id/name/content/coordinates/isHexGrid/displayState but no `isShown`); `MapRPG/Model/MapSnapshot.swift:150-160` blanks hidden-room name/content; `MasterController+Messaging.swift:106-112` sends content only when the version differs from `sentMapContentVersions`; `displayState` is the library `DisplayStateMask`, not room visibility (`MapRPG/Controller/DataController.swift:42`, `MapEntryModel.swift:32`). Not run.
- **§5.3** — open `CharacterRPG/Controller/GameController.swift:201-210` (`source.duplicateWithoutCopy()`), `Model/ValueModel.swift:194-196` (`entries.map { $0.duplicate() }`), `Model/ValueEntryModel.swift:214-216` (`valueId: valueId` kept), `Controller/GameController+EntryResolution.swift:262-280` (`gameEntryOwnerId` follows `entry.valueId`), `:297-306` (`gameMemoryCopy`); callers `MapRPG/Controller/GameController+Battle.swift:106, 377` do not deep-copy groups. Not run.
- **§5.6** — open `CoreRPG/Controllable/ItemControllable.swift:192-214`: the `catch` at 194-196 only records the failure and the file delete at 201-213 runs regardless.
- **§6.1** — open `MapRPG/Controller/GameController+Sync.swift:42` (`model.mapPins.filter(\.isShown)`), `MapRPG/Model/MapSnapshot.swift:161` (`mapPins.wrappedValue.filter(\.isShown)`), `MapRPG/Controller/GameController+Pins.swift:198`; versus `GameRPG/Table3D/GameTableProjection.swift:44, 189` and `MapRPG/Model/MapModel+Geometry.swift:23-25`.
- **Compiler** — builds in `/private/tmp/claude-501/-Users-andrenalin-Developer-gamemaster/45c31fe7-6efc-414b-a967-74df3b10e721/scratchpad/builds/{ios,mac,tv,vision}.log`: four `** BUILD SUCCEEDED **`, only `appintentsmetadataprocessor` notices.

Medium and lower findings are the reporting agents' readings unless marked above; each carries the agent's own `[reasoned]`/quoted-line note where given. Re-open the cited lines before editing.

---

## 13. Status after the fixes (2026-11-01)

Everything is uncommitted on `main`. "Fixed" means the code is changed and the four schemes (iOS, macOS, tvOS, visionOS) build; the runtime result is under Verification below. Decisions taken with the user: §6.1 hide a shown non-player pin that sits in an unrevealed room until the room is revealed; §5.11 append character links only for shown pins, to the editor's working copy, with no stored-map save, and the external merge honours local room deletions; §5.7 iCloud folder Sync is disabled in game mode. Scope: bugs, security, performance, UI and cheap dead-code cleanup. Not done on purpose: §4.1 Id/Url rename, §9.3/§9.4 deduplication, §9.6 file splits, §9.14 long functions, §9.5 Fake/Mock gating, §9.16 Thai/localization script, §9.17 magic constants and layout values.

| § | Status | What was done |
|---|--------|---------------|
| 5.1 | Fixed | Link-marker pairing matches begin/end by nesting depth; an unbalanced begin marker stays plain text. Test `unbalancedMarkersDoNotTrap`. |
| 6.1, 5.2 | Fixed | One predicate `isPinVisibleToPlayers` (shown, and for a non-player pin not covered by a hidden room) is used by the live `mapState`, the map package and the photo-request path. `isShown` of a room is part of the content fingerprint, so revealing a room re-sends the content. Two existing tests were updated for the new semantics (a room's `isShown` is no longer volatile; the live-state test uses a visible pin). |
| 5.3 | Fixed | Battle clones deep-copy value groups (`battleGroupCopyIds`) and remove them with the clone. Test `battleClonesDoNotShareValueGroups`. |
| 5.4 | Fixed | Queued messages of an origin that is no longer bound are dropped. |
| 5.5, 5.25 | Fixed | Failed bookmark/file-store reads are not treated as empty: no `didFetch`, no write-back, undecodable entries kept; the resolved URL is returned if the stale refresh fails; saves are atomic. |
| 5.6 | Fixed | A failed database delete keeps the file and restores the model. |
| 5.7, 3.6 | Fixed | Sync is off in game mode (handler and `apply`); `apply` scans after taking the mutation lock; hashing of new files is capped at 200 files. |
| 5.8 | Fixed | A collection removal only takes children whose `parentId` is the collection. |
| 5.9, 5.22 | Fixed | Audio replace/load failures clear the player item; non-finite durations are guarded; media-service reset coordinates playback. |
| 5.10 | Fixed | `repairedUuid(of:at:)` assigns and persists a missing uuid once; used by every module DataController except Pdf and the optional DisplayConfig site. |
| 5.11 | Fixed | See decisions above. |
| 5.12 | Fixed | A failed link-register hydration is retried and never clears the pending ids. |
| 5.13 | Fixed | Hex raster index is clamped. |
| 5.14 | Fixed | A pending dice roll task per item is cancelled by the next roll. |
| 5.15, 5.16 | Fixed (locale change unverified at runtime) | Base text and modifier text use shared helpers; pipes inside brackets do not split; numbers format with a fixed `en_US` notation. |
| 5.17, 5.18, 4.2 | Fixed | Storm delta clamp; pause on any non-built-in output loss; `.contains(.shouldResume)`. |
| 5.19 | Fixed | Table generation names the links cut by the size limit and keeps the first error. New de/th string. |
| 5.20 | Fixed | Decoded dice/option counts are bounded; `RawDieCounter.roll()` clamps its loop. |
| 5.21 | Mostly fixed | Repair/check passes save only on a change. Not changed: "owner not found" stays pending until the first sync. |
| 5.23 | Accepted | Core Data model is edited in place, per the project decision. |
| 5.24 | Fixed | Pin photo texture is cleared when the photo is removed, the loaded id is set only on success, bookkeeping of removed pins is pruned. |
| 5.26 | Fixed | PDF find caps matches at 1000 and ignores a stale end notification. Not added: a "more matches" indicator. |
| 5.27 | Fixed | One spotlight index reset per launch; failures are logged. |
| 6.2 | Partly | A hidden pointer is blanked and a battle's active pin is dropped when hidden. Not decided: map description/tags for players. |
| 6.3 | Fixed | `.playAudio` is sanitized (size, id, rebuilt payload) and needs the item on the master. |
| 6.4 | Mostly fixed | The master checks a message before relaying it (dedup, dice feature gate and plausibility, space transform); players re-check dice reports. Not added: pin validity beyond the space transform. |
| 6.5 | Partly | Journal metadata cached and pruned; payloads over the message limit skipped. Not added: per-sender byte budget. |
| 6.6, 6.7 | Fixed | Share extension fetches only image URLs and rejects undecodable/over-limit data; photo decode applies the declared-size limits, with `AKImage.decodedImage`. |
| 6.8 | Fixed | Foundry text is one line and a leading block marker is escaped. Test `importedTextStaysOnOneLine`. |
| 6.9 | Fixed | `PrivacyInfo.xcprivacy` added to the widget (synchronized folder) and to RPGShare (project file edited by new object ids). |
| 6.10 | Documented | The choices are written on the three intents; no code change. |
| 7.3 | Fixed | Map editor undo is capped at 100 steps. |
| 7.6 | Fixed (cost only) | Image cache cost uses pixels. The decode still runs inside the cache actor. |
| 7.9 | Partly | `repairFolders` uses a set for `missing`. Not changed: `libraryFileUrls`, quick linker. |
| 7.14, 7.15 | Fixed | `AsyncThumbnail` keys on file id, location and content hash; the list-reveal observer maps ids only while a reveal is pending. |
| 7.1, 7.2, 7.4, 7.5, 7.7, 7.8, 7.10-7.13 | Open | Larger or unmeasured; 7.2 only has the cap from 3.6. |
| 8.1 | Fixed | `.disabled` added at the 14 hidden-control sites listed (the decorative `allowsHitTesting(false)` overlays are unchanged). |
| 8.2, 8.3 | Fixed | The die's accessibility value names success/failure (new de/th strings), the widget shows a coup/fumble symbol and says it; the die text shrinks instead of clipping. |
| 8.4 | Partly | Battery pulse honours Reduce Motion. The ~40 plain `withAnimation` sites are open. |
| 8.5 | Fixed | Audio controls use `reduced(if:)` and 44 pt minimum targets. |
| 8.6 | Open | Needs a look on device. |
| 8.7 | Fixed | `ListRowItemView ==` compares `leadingPadding` instead of the always-equal selection. |
| 3.1 | Fixed | `stopGame` bumps a generation that both start flows check after their suspensions; a master start and a join exclude each other. |
| 3.2 | Fixed | Shared downloads are cancelled when the last waiter leaves; downloads use a session with a 300 s resource timeout. |
| 3.3 | Open | The predecessor wait cannot be cancelled (`Task.value`); needs a redesign of the session handling. |
| 3.4 | Fixed | Battery monitoring is reference-counted. |
| 3.5 | Fixed (reads) | The file-read and name-suggestion sites no longer count. The `CoreDataController` fire-and-forget site is unchanged. |
| 4.3 | Documented | The page-control appearance proxy is a deliberate exception. |
| 4.4 | Not possible | Removing `nonisolated(unsafe)` fails to compile: `UserDefaults` is not `Sendable` in this SDK. The comment now says so. |
| 9.1, 9.2 | Fixed | `HideKeyboardView`, its `show:` overload and its generated snapshot test are deleted; `restingOrientation` of both dice and `faceNormals` are deleted. |
| 9.11 | Partly | Unused `Combine` in `GameRootModel` and `os` in `CaptureOverlayView+Buttons` removed. `GameTableModel+RenderingReadiness` and the SharePlay files need Combine. AppKit and UniformTypeIdentifiers imports not touched. |
| 9.7-9.10, 9.12, 9.13, 9.15, 9.18 | Open | Not started. |

**Verification (2026-11-01).** Clean builds of MasterRPG (iOS Simulator, visionOS Simulator) and MasterMac, MasterTV all succeed. Module test targets on the iPhone 18 Pro simulator pass: CoreRPG, Character, Dice, Table, Rule, Audio, Photo, Weather, Map (262), Game (609), Generator, Pdf, Space, Adventure. Three existing tests encoded the old redaction behaviour and were changed with the fix: a room's `isShown` is part of the content fingerprint (`GameControllerTests`), and the live-state and battle-broadcast tests now use a visible pin or a revealed room (`BattleRoundControllerRuleTests`, `BattleRoundInputAndBroadcastTests`). Not run: the snapshot suites, UI tests, and anything on device (SharePlay, iCloud, audio route changes, visionOS table). The privacy manifests and the German formatting change (§5.16) are not checked at runtime.
