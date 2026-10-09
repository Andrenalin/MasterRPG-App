# MasterRPG Code Audit

Generated 2026-10-04 (21st audit) against commit `6af151cc` (`develop`). Scope: 2,157 Swift files (~280k LOC, of which ~82k LOC are tests) across the MasterRPG (iOS/iPadOS/visionOS), MasterMac, MasterTV, RPGShare and DiceRollerWidget targets and 15 modules. Excluded: `Docu/`, `Integrations/`, `.git`, `.build`, DerivedData and snapshot reference images. `Tests/` got quick reads only. The repo has no `Dead/` folder and no Metal code.

Every finding cites `path/to/file.swift:LINE` and recommends an action. No code was changed.

**Compiler ground truth.** Clean Debug builds into fresh derived-data folders: Swift 6 mode, `SWIFT_STRICT_CONCURRENCY = complete`, Xcode 27.1 (27A9269).

| Scheme / destination | Result | Swift warnings |
|---|---|---|
| MasterRPG, iOS Simulator | BUILD SUCCEEDED | 0 |
| MasterRPG, visionOS Simulator | BUILD SUCCEEDED | 0 |
| MasterMac, macOS | BUILD SUCCEEDED | 0 |
| MasterTV, tvOS Simulator | BUILD SUCCEEDED | 0 |

The only other diagnostics were "appintentsmetadataprocessor: Metadata extraction skipped" notices. No tests were run.

**Relationship to earlier audits.** CODE_AUDIT_20 (2026-09-30, base `4ad2a6ea`) was fixed in `6ae614fb`. `Docu/CODE_AUDIT_Folder.md` (2026-10-02) was fixed in `5ee4f91b`, `88541532`, `9e6b127d`, `861e5e56`, `920c1c53` and `6af151cc`. Feature commits in between: the map pin and needle popover rewrite (`76634bc0` … `79451c49`), violet dice (`d38dd5c2`), toolbar fixes for visionOS/iOS, and the snapshot-test rework (`5d61aaa7`). Tags used:
- **[REGRESSION `sha`]**: that commit introduced the defect.
- **[INCOMPLETE FIX of CODE_AUDIT_x §y]**: an item an earlier audit's status table marks fixed that does not fully work.
- **[STILL OPEN from CODE_AUDIT_x §y]**: reported before, not fixed, still present.
- **[NEW]**: not reported before.
- Accepted decisions are not reported again: the 4-digit join code, player overwrite of a GM character by id, peer import policy (Folder §6.1/§6.2), hex cells as entries, folder merge = union + child decides, Pdf bookmarks LWW, SharePlay `join()` on main, the 61 `assumeIsolated` sites (audit 20 §4.1) and sleeps that stand in for UI settling (audit 20 §4.4).

**How to read verification.** **[verified]** means I re-read the cited lines myself after an agent reported them (see §12). Findings without the tag were read by the reporting agent but not independently re-read; their line numbers are reliable and their severity is that agent's estimate, reviewed by me. "Plausible" means the code path is real but the runtime outcome needs a test or a device.

**Result in one line.** 85 findings: 1 Critical, 3 High, 34 Medium, 45 Low, 2 without a severity (§9.12 rates each file; §9.13 is empty). The Critical one is old code (`7e9a4439`, July) that no earlier audit caught: a user folder named "Documents" makes an item's file resolve to the whole module folder, and a delete then removes it (§5.1). The same resolver is the target of one High security finding (§6.1) and sits behind another High (§5.2). Nineteen findings are incomplete fixes of earlier audits and five are regressions from the last two remediation rounds, so the pattern from audits 19 and 20 continues: the fix lands at the cited site, not at every site with the same shape.

---

## 1. Executive summary

Top items to address, in priority order:

1. **[Critical] A folder named "Documents" makes item files resolve to the module folder** — §5.1 — `Modules/CoreRPG/Files/CloudDocumentController.swift:67-88`. Deleting or replacing such an item's file removes every file of that module in iCloud Drive.
2. **[High] Items trashed before confirmation are purged if the delete panel never disappears** — §5.29 — `Modules/CoreRPG/LGViews/ListRootContextMenu.swift:258-268`. Terminating the app with the panel open hard-deletes the unconfirmed items at the next launch.
3. **[High] `resetFile(data:)` overwrites or shares another item's file** — §5.2 — `Modules/CoreRPG/Controllable/EditControllable+File.swift:197-232`. Two equally named photos filled from the camera or library end up with one file.
4. **[High/Security] Imported file paths can resolve to the module root** — §6.1 — `Modules/CoreRPG/Files/FileUrl.swift:191-203`. A crafted import or game delivery turns a later delete into a module-folder delete.
5. **[Medium] Paused "Share Map" still leaks through map repair answers** — §5.4 — `Modules/GameRPG/Controller/MasterController+MapMessages.swift:138-152`. A joining or reconnecting player receives what the GM revealed privately.
6. **[Medium] The hosting session id becomes per-run when the Keychain is unreadable at prewarm** — §5.3 — `Modules/GameRPG/Master/HostingSessionStore.swift:40-49`. Players are not redialed after a master restart, the case the store exists for.
7. **[Medium/Security] Peer-reported dice values crash the receiver** — §6.7 — `Modules/DiceRPG/Controller/GameController+DiceResult.swift:115-121`. One participant can crash the GM and every player showing its dice.
8. **[Medium] The in-game hex-scale slider wipes revealed cells** — §5.19 — `Modules/MapRPG/Map/MapEditor.swift:139-145`. Touching the slider during a game hides every revealed hex.
9. **[Medium] PDF bookmarks store the page label but navigate by index** — §5.17 — `Modules/PdfRPG/Pdf/PdfWrapperView.swift:65-74`. Bookmarks open the wrong page in books with front-matter numbering.
10. **[Medium] The LAN outbound queue has no cap** — §6.3 — `Modules/GameRPG/Network/ConnectionController.swift:79`. One stalled player can grow the GM's memory until the game ends for everyone; open since audit 17.

---

## 2. Quick wins (≤30 min each)

These deliver outsized value relative to effort and have no architectural ripples.

- **Refuse to remove the module root or any directory in the file delete helpers** — `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:356-369`. A stopgap that closes the destructive half of §5.1 and §6.1 until the resolver is fixed.
- **Use `addingReportingOverflow` in `increasedFileName`** — `Modules/CoreRPG/Files/CloudDocumentController.swift:259-260`. Fixes §6.4.
- **Mark `isPrewarmed` only on `.found` or `.notFound`** — `Modules/GameRPG/Master/HostingSessionStore.swift:40-49`. Fixes §5.3.
- **Cancel and clear `syncBatchConsumer` in `setUp`** — `Modules/PhotoRPG/Root/PhotoRootModel.swift:104` and the other module roots. Fixes §3.1.
- **Apply the range lookup only when the occurrence has a dice** — `Modules/TableRPG/Controller/TableGenerationController.swift:232-236`. Fixes §5.18.
- **Restart a single track when repeat is on** — `Modules/AudioRPG/Controller/AudioController.swift:435`. Fixes §5.20.
- **Chain the operation in `TableReceiveSerializer.run`** — `Modules/TableRPG/Controller/GameController.swift:46-62`. Fixes §5.22.
- **Call `DiceConfiguration.recordLastRoll` from the app's `RollDiceIntent`** — `Modules/DiceRPG/Intent/DiceIntents.swift:42-45`. Fixes the write half of §5.23.
- **Scope the PDF selection notification to its own view** — `Modules/PdfRPG/Pdf/PdfContentView.swift:36`. Fixes §5.25.
- **Wrap the audio contribution import in its own `do/catch`** — `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:50-56`. Fixes §5.10.
- **Replace `Dictionary(uniqueKeysWithValues:)` with `uniquingKeysWith` at the ten cited sites** — §5.16, §6.8.
- **Give `MapPopoverButton` a fixed frame and `minimumHitArea()`** — `Modules/MapRPG/View/MapPopover.swift:265-275`. Fixes §8.1.
- **Teach `verify_localization.rb` the `.ruleModule` accessor and translate the four keys** — §8.2. Makes the check usable as a gate again.
- **Delete the dead generator cluster** — `Modules/GeneratorRPG/BasicAI/View/ChatInputView.swift`, `Modules/GeneratorRPG/Controller/AdventureGeneratorController.swift` (§9.1). About 360 lines.
- **Remove unused `import Combine`** — the nine files in §4.1.
- **Correct the five stale comments** — §9.10.
- **Add the missing expectation to `assigningNilCancelsCurrentTask`** — `Tests/GameRPGTests/SearchModelTests.swift:27-40` (§9.15).

---

## 3. Concurrency

The compiler is clean on all four platforms, so everything here is what strict concurrency cannot see: reentrancy across `await`, task lifetime, and `nonisolated async` code that runs on the main actor under approachable concurrency.

### 3.1 The sync-batch consumer stays bound to the first store's controller after a store swap **[verified]** **[REGRESSION 5ee4f91b]**
- **Location:** `Modules/CoreRPG/Controllable/SyncDataControllable.swift:58-71` (consumer), `:73-150` (`apply` uses the captured `dataControllable`); `Modules/CoreRPG/ItemList/ItemDataModel.swift:46-49`; `Modules/PhotoRPG/Root/PhotoRootModel.swift:86-107` (every module root has the same `setUp`); `Modules/RolePlayGameKit/View/DestinationReadyView.swift:32-38`; `Modules/CoreRPG/FileViews/StorageOptionEditor.swift:51-57`
- **What:** `startSyncConsumerIfNeeded()` starts one never-ending `for await` task per `ItemDataModel` and nothing cancels or replaces it (`syncBatchConsumer` has exactly two uses). The task captures the `SyncDataController` that started it. After a store swap, `setUp` builds a new controller on the new context but reuses the same `ItemDataModel`, so the old task keeps applying the new store's batches against the old store.
- **Why:** Inserts and updates fetched from the old store come back `nil`; a batch with deletions diffs memory against the old store's ids and removes items from the lists. Today the only in-process swap is the storage switch, which quits the app a moment later (`Darwin.exit(0)`), so the window is seconds and the damage is in memory only. It becomes a real data-visibility bug the day a store is swapped without a relaunch (store recovery, a non-quitting switch).
- **Action:** Tie the consumer to the controller generation: cancel and clear `syncBatchConsumer` in `setUp` next to `syncTask?.cancel()`, or have the loop resolve `itemDataModel.dataController` per batch instead of capturing `self`.
- **Severity:** Medium (reported as High; demoted because the only swap today is followed by a forced quit)

### 3.2 `startMaster` can be entered twice **[verified]** **[NEW]**
- **Location:** `Modules/GameRPG/Root/GameRoot.swift:316-356` (guard at `:318-321`, first real suspension at `:352`, `state = .started` at `:356`); `Modules/GameRPG/SetupViews/MasterStartView.swift:24-28`, `:63-71`
- **What:** The Start button spawns an untracked `Task` per tap and is not disabled while starting. `startMaster` treats `state != .stopped` as "toggle off", but only sets `.started` after `await adventureGameControllable.startGame(with:)`.
- **Why:** A second tap during that await runs a second full start: a new master id and a second `PlayerController`/`MasterController` pair. A second tap after `.started` calls `stopGame()`, so a double tap can start and immediately end the game.
- **Action:** Mark the transition synchronously before the first await (a starting state, as `startGame(to:mode:)` does), ignore re-entry while starting, and disable the button for the duration.
- **Severity:** Medium

### 3.3 A reconnect installs a live connection after `stop()` ran during its suspension **[NEW]**
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift:550-567` (`listenerNewConnection`), `:258-270` (`restart`), `:206-241` (`stop`), `:393-412`, `:451-456` (`markReadyIfCurrent`)
- **What:** `listenerNewConnection` checks `connectionState == .lost`, sets `.notReady`, then `restart` awaits `connectionThrottle.register` before installing the new `ConnectionController`. If `stop()` runs in that suspension, `restart` still installs and starts the controller on the stopped model, and `markReadyIfCurrent` accepts it because `stop()` left the state at `.notReady`.
- **Why:** A player who just left gets a ghost session: `isConnected` becomes true and the master sees the player as rejoined, with nothing owning the connection. The window is two actor hops wide.
- **Action:** Capture a generation (or `playerConnectionId`) before the first `await` and drop the connection, clearing its throttle entry, if it changed.
- **Severity:** Medium

### 3.4 `loadAndPlay` keeps going after its playlist load was discarded **[INCOMPLETE FIX of CODE_AUDIT_18 §3.7]**
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:254-268` (`loadAndPlay`), `:124-177` (`add`, discard at `:169-174`), `:293-311` (`preparePlay`), `:424-429` (`handleSharedAudio`)
- **What:** The generation guard in `add(audio:replace:)` discards a superseded load but returns `Void`. The unstored `Task` in `loadAndPlay` then continues with `model.set(currentId:)` and `preparePlay(id:)` for a track that is not in the playlist.
- **Why:** Tapping track A and then B quickly, with A's load finishing last: `currentItem` becomes nil while B is audible, the mini-player and next/previous break, and A is published as the shared audio id, so SharePlay peers are told the wrong track.
- **Action:** Have `add` return whether it committed, and store the task as cancel-then-replace; a superseded load must stop before `set(currentId:)`.
- **Severity:** Medium

### 3.5 A manual import review holds the data-mutation lock while its sheet is open **[REGRESSION 5ee4f91b]**
- **Location:** `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:164-174`; `Modules/CoreRPG/Import/DataMutationCoordinator.swift:53-59`; `Modules/CoreRPG/Controllable/SyncDataControllable.swift:62-68`; `Modules/CoreRPG/Controllable/GameControllable.swift:487-491`
- **What:** After a manual parse the session keeps the lock until Apply or Cancel. The Folder §3.5 fix made the sync consumer and `importNetwork` call the non-cancellable `waitUntilIdle()`.
- **Why:** While the review sheet is open, no CloudKit change is applied to memory, and every reveal or map package in a running game waits with no message. Unverified: whether the import sheet can be opened during a running game; the sync delay follows from the code.
- **Action:** Release the lock after the parse and re-take it for Apply (the apply already re-checks the library copy), or give waiters a timeout and a visible state.
- **Severity:** Medium

### 3.6 A detached file delete can remove a file a later import just chose to reuse **[INCOMPLETE FIX of CODE_AUDIT_20 §5.4]**
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:239-268` (`delete(_:)` spawns an unawaited `Task { @concurrent }`), `:299-312` (`importDestination` reuses an unreferenced file with an equal hash); `Modules/CoreRPG/Controllable/ItemControllable.swift:160-199`
- **What:** `ItemControllable.delete` removes the item from memory and then fires the unordered delete task. A concurrent import sees the file as unreferenced with a matching hash and returns the same path; the queued delete then removes it.
- **Why:** Deleting items and re-importing the same package soon after (a bulk delete queues one task per file behind the 4-slot coordination limiter) leaves imported items pointing at files that no longer exist. Plausible; needs a timing test.
- **Action:** Make the file deletion awaited and ordered through one serial file-mutation chain that `importDestination` and `createNewFileUrl` also pass, or re-check references at delete time.
- **Severity:** Medium

### 3.7 File I/O in `nonisolated async` file helpers runs on the main actor **[NEW]**
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:234-242` (`heldPeerFileUrl` atomic write), `:357-380` (`resolveProcessUrl`, unconditional `data.write` at `:370`), `:297-309`, `:98-121`; `Modules/CoreRPG/Files/FileBookmarkController.swift:115-154`; `Modules/CoreRPG/Persistence/FilePersistenceController.swift:96-109` (`loadData`/`saveData`/`removeData` are not `@concurrent`, unlike `load`/`save`/`remove` at `:35-90`). Main-actor callers: `Modules/CoreRPG/Controllable/ItemControllable+Viewer.swift:46-49`, `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:109-120`
- **What:** These functions are plain `async` on `Sendable` structs, so under approachable concurrency they run on their caller's actor. From `@MainActor` callers this writes the whole held-peer or staged file to a temp URL (rewritten on every call, with no exists check), resolves and creates security-scoped bookmarks, and queries iCloud download status, all on the main thread.
- **Why:** Opening a PDF, 3D model or audio item whose bytes are held in memory stalls the UI for a multi-megabyte synchronous write, up to the 256 MiB cap. Bookmark and ubiquitous-resource lookups are IPC that can block when iCloud is slow.
- **Action:** Mark the resolving and writing helpers `@concurrent` (or route them through `runOffCallerExecutor`), and skip the staged-bytes write when the temp copy already exists for that file id and content.
- **Severity:** Medium

### 3.8 All file-coordination slots can be held by iCloud waits that nobody cancels **[NEW]**
- **Location:** `Modules/CoreRPG/Files/FileManager+Coordination.swift:140-184`, `:324-365` (limit `min(4, cores-1)` at `:325`); `Modules/AudioRPG/Controller/AudioController.swift:121`, `:187-205`
- **What:** A coordinated read of an evicted iCloud file holds its limiter slot until the download finishes or the caller is cancelled. There is no timeout, and several callers are unstructured tasks that are never cancelled.
- **Why:** Offline or on a stalled iCloud, loading a playlist of evicted tracks occupies every slot. All other coordinated operations then queue behind them, including local-only imports, deletes and moves. Plausible; needs a device with evicted files.
- **Action:** Give download-waiting reads a deadline that cancels the coordinator, or reserve a slot for non-ubiquitous URLs.
- **Severity:** Medium

### 3.9 A pipeline reset on lost connection can start a second concurrent drain **[NEW]**
- **Location:** `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:62-69`; `Modules/GameRPG/Model/GameMessagePipeline.swift:184-203`, `:236-245`; `Modules/GameRPG/Controller/PlayerController+MessageProcessing.swift:307-384`
- **What:** `reset()` sets `processing = false` while a drain may be suspended inside `handle(...)`. The next enqueue starts a second drain; the first drain's `processed(...)` later clears `processing` under the second.
- **Why:** After a SharePlay master rebind, an old-session handler still importing a map can interleave with the first new-session messages. Plausible; needs a reset while a handler is suspended.
- **Action:** Give the pipeline a generation: `reset()` bumps it, `next()` refuses while a previous-generation event is unfinished, `processed` ignores stale generations.
- **Severity:** Low

### 3.10 Generator tasks report a cancelled extraction as an error, and a superseded request clears the newer preview **[NEW]**
- **Location:** `Modules/GeneratorRPG/Controller/GeneratorController.swift:227-238`, `:252-253`, `:346-363`, `:114-121`; `Modules/GeneratorRPG/Controller/AdventureGeneratorController.swift:89-93`, `:188-229`
- **What:** `request()` handles `CancellationError` but calls `rootModel.updateAIPreview(nil)` without comparing `currentGeneration`. Both `extract` implementations route a cancelled stream into the generic `catch`, which sets `showError = true`.
- **Why:** Sending a second prompt removes the new request's placeholder preview until its first partial arrives. Closing the assistant during an extraction can leave an error alert on the reused session model. The alert depends on FoundationModels throwing `CancellationError`, which needs a runtime check; the missing guards are certain.
- **Action:** Add a cancellation branch to both `extract` tasks and gate every catch-side UI write on the task's generation, as the success path already does.
- **Severity:** Low

### 3.11 Journal attachment cleanup retries without an attempt bound **[NEW]**
- **Location:** `Modules/GameRPG/SharePlay/SharePlayDeferredDeliveryQueue.swift:20-48`; `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift:462-501`; `Modules/GameRPG/SharePlay/SharePlayJournalAddLimiter.swift:189-203`; `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:355-379`
- **What:** `retryUntilRemoved` stops only on success, cancellation or `isObsolete`. A permanently failing `journal.remove` is retried every 5 s for the whole session.
- **Why:** Each stuck cleanup holds one of 8 cleanup reservations. After 8, every journal publication is rejected and all file content falls back to the chunked Messenger path for the rest of the session. Plausible.
- **Action:** Cap the attempts (or total time), then release the reservation and record the attachment as abandoned.
- **Severity:** Low

---

## 4. API modernity

The mechanical rules are clean. Zero occurrences in `Modules/` and `Sources/` of: `ObservableObject`, `@Published`, `@StateObject`/`@ObservedObject`/`@EnvironmentObject`, `DispatchQueue`/`DispatchSemaphore`/`DispatchGroup`, `Task.detached`, `NSLock`, `DateFormatter`/`NumberFormatter`/`MeasurementFormatter`, `String(format:)`, `Task.sleep(nanoseconds:)`, `replacingOccurrences(of:)`, `UIScreen.main`, `.foregroundColor()`, SwiftUI `.cornerRadius()`, `tabItem`, `NavigationView`, 1-parameter `onChange`, `showsIndicators:`, `ScrollViewReader`, `GeometryReader` (only `GeometryReader3D`), computed `some View` properties. All 66 availability guards are for 26.1, 26.4 or 27, so there are no dead branches. All ten `@unchecked Sendable` types and all twelve continuation sites were checked and are sound.

### 4.1 `import Combine` left in files that use no Combine API **[NEW]**
- **Location:** 30 files import Combine. Not using it: `Modules/GameRPG/Root/GameRoot.swift:5`; `Modules/CoreRPG/Files/FileUrlDataController.swift:3`, `+Create.swift:3`, `+Manage.swift:3`; `Modules/CoreRPG/Persistence/CoreDataController.swift:3`, `PersistentHistoryTrackerManager.swift:3`, `RpgSpotlightIndexerDelegate.swift:4`; `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:6`, `+JournalAttachments.swift:6`
- **What:** Real Combine use is down to `CoreDataChangeObserver.swift:33`, `:54` (`sink`), `AudioController.swift:357-361` (KVO publisher), `.values` on system `@Published` projections in `RPGSharePlayController.swift:803`, `+SessionLifecycle.swift:247`, `:308`, `+TableCoordination.swift:48`, and `AudioPlayerModel.swift:61-67` (`AnyCancellable` as a cancel box). The other imports are residue.
- **Why:** It misstates the dependency surface against the project's rule and makes the remaining real uses harder to find.
- **Action:** Remove the import wherever the file compiles without it.
- **Severity:** Low

### 4.2 Older URL path APIs still in use **[NEW]**
- **Location:** `url.path`: `Modules/CoreRPG/Cache/ObjectCache.swift:49`, `:55`, `:88`; `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:42`; `CoreDataPersistenceController.swift:148`; `Modules/CoreRPG/Files/FileManager+Coordination.swift:12`; `Modules/CoreRPG/Import/ExternalImportSourceRegistry.swift:139`, `+Matching.swift:307`; `Modules/SpaceRPG/Record/CaptureFolderManager.swift:155`; `Modules/CoreRPG/Foundry/FoundryVTTDataSource.swift:96-97`, `:116`, `:129`, `:132`. `appendPathComponent`: `Modules/CoreRPG/Persistence/FilePersistenceController.swift:122`. `.relativePath` passed as a file-system path: 6 sites, e.g. `FilePersistenceController.swift:42`, `:139`, `FileUrlDataController.swift:187`, `:206`
- **What:** These use `URL.path`, `appendPathComponent` and `relativePath` where the project rule asks for `path(percentEncoded: false)` and `appending(path:)`.
- **Why:** `relativePath` in a `fileExists` check silently gives the wrong answer for a URL built relative to a base.
- **Action:** Replace with `path(percentEncoded: false)` and `appending(path:)`.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 A folder named "Documents" makes item files resolve to the module folder, and delete or replace then removes every file of the module **[verified]** **[NEW]**
- **Location:** `Modules/CoreRPG/Files/CloudDocumentController.swift:67-88` (strip at `:74-76`, fallback at `:86`), `:195-222` (`move(url:newName:)` stores `<folder names>/<name>.<ext>`), `:308` (`documentDirName = "Documents"`); `Modules/CoreRPG/Files/FileUrlDataController.swift:314-323` (`deviceUrl` for `.newCloud`); `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:239-268` (`delete`), `:273-291` (`storedLocation`), `:341-347` (`deleteReplaced`); `Modules/CoreRPG/Files/FileManager+Coordination.swift:26-32` (`removeItem`, no directory guard); `Modules/CoreRPG/Controllable/EditControllable+File.swift:15-25` (`folderPath`), `:60-86` (`moveFileToFolderPath`), `:138`
- **What:** `fullUrl(fileUrl:)` treats any path component equal to `Documents` as the container's Documents directory and drops it plus the next component. Files inside a user folder are stored with the folder names as their relative path. For a folder item named "Documents" the stored path is `Documents/Rules.pdf`, which reduces to zero components, so `fullUrl(fileUrl:)` returns the module folder itself. The write side (`fullUrl(filePath:)`) does not strip, so the file really lands in `<module>/Documents/Rules.pdf`; only the read, delete and replace side resolves to the module folder. The same happens at any depth (`Campaign/Documents/Rules.pdf`). With a subfolder (`Documents/Maps/x.pdf`) the path resolves to `<module>/x.pdf`, a different file.
- **Why:** A user creates a folder called "Documents" in Pdf, Photo, Audio or Space and adds or moves an item into it. The item's file stops opening. When that item is deleted (trash purge) or its file is replaced, `removeItem` runs on the module folder and deletes every file of that module in iCloud Drive, on all devices. "Documents" is an ordinary folder name for a PDF library. Reproduced for the path resolution with a scratch script; not executed in the app.
- **Action:** Strip the container prefix only when the URL is absolute and its prefix is the real container root, never by component name. Make both `fullUrl` builders fail (return nil) on an empty or uncontained result, and make every remove refuse a target that is the module root or a directory. Add a test with a folder named "Documents".
- **Severity:** Critical

### 5.2 `resetFile(data:)` writes to `<item name>.<ext>` without a free-name check, so it overwrites or shares another item's file **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_20 §5.4]**
- **Location:** `Modules/CoreRPG/Controllable/EditControllable+File.swift:197-232` (name at `:214-220`); `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:33-58`; `Modules/CoreRPG/Files/CloudDocumentController.swift:115-125` (plain `data.write(to:)`); `Modules/CoreRPG/Controllable/ItemControllable.swift:194-199`; caller `Modules/PhotoRPG/Controller/EditController.swift:65-68` from `Modules/PhotoRPG/Photo/InlineImporterView.swift:177-183`
- **What:** `writeFile(data:)` builds `/<folder>/<item name>.<ext>` and calls `createNewFileUrl`. If a file with the same bytes is there it is reused, so two items share one file. Otherwise it is overwritten. Nothing checks whether another item references that path, unlike `importDestination` and `copyFile`. The write is also not atomic, so a failed in-place replacement truncates the old photo although the §5.4 fix says the old file is kept.
- **Why:** Item names are not unique. Photo "Goblin" owns `Goblin.jpg`; a second photo named "Goblin" in the same folder gets its image from the camera, the photo library or Image Playground and replaces the first photo's file. Deleting either item later deletes the shared file. A new, unnamed item is safe (`NewData-<uuid>`), so this needs two equally named items.
- **Action:** Pick the destination with `suggestedFileName` unless the path is the item's own current file, write atomically, and skip the file delete in `ItemControllable.delete` when another library item references the same stored location.
- **Severity:** High

### 5.3 The hosting session id becomes per-run when the Keychain is unreadable at prewarm **[verified]** **[REGRESSION 6ae614fb]**
- **Location:** `Modules/GameRPG/Master/HostingSessionStore.swift:40-49` (`prewarm`), `:51-88` (`sessionId(forPasscode:proxy:)`); `Modules/GameRPG/Master/MasterNetworkController.swift:86`; accessibility class `Modules/GameRPG/Network/JoinCodeStorage.swift:145`
- **What:** `prewarm()` sets `isPrewarmed = true` even when `storage.read` returned `.unavailable`. `sessionId(forPasscode:proxy:)` then treats a memory miss as "none stored", skips the Keychain, mints a new UUID and writes it over the stored one. Before the audit-20 §3.7 change the read happened at hosting time, when the device is unlocked.
- **Why:** If the process starts while the device is locked (the entry is `WhenUnlockedThisDeviceOnly`), the next hosted game advertises a new session id, and players still advertising the old id are never redialed. That is the exact case the store exists for. Unverified: which launch paths construct `MasterNetworkController` while locked.
- **Action:** Mark as prewarmed per key and only on `.found` or `.notFound`; on `.unavailable` fall through to the synchronous read at hosting time.
- **Severity:** Medium

### 5.4 Paused "Share Map" still leaks through map repair answers **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_20 §5.2]**
- **Location:** `Modules/GameRPG/Controller/MasterController+MapMessages.swift:138-152` (data-less `.update/.generic` request returns `networkMapContentUpdate` with no gate), `:70`, `:84-91`, `:126-127` (`recovery.full` sent or returned), `:407-414`; sent on by `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:289-309`
- **What:** `mayShareMapState(for:)` gates only the trailing content and state sends of the `.reveal` branch. The `.update/.generic` branch returns the live content update unconditionally, and the `.reveal` branches still send `recovery.full` while paused.
- **Why:** The GM pauses sharing and reveals a room privately. A player joins or reconnects, its `requestMapContent` is answered, and the private state arrives. Verified for the `.update/.generic` path; whether `recovery.full` serialises the live game map or the stored item was not traced.
- **Action:** Put the gate in one master-side "answer map request" function. While paused, answer with the last-shared snapshot or `.failed` and mark `mapsWithUnsharedStructure`. Add a repair-request case to `BattleRoundPausedSharingTests`.
- **Severity:** Medium

### 5.5 A Character import failure makes the player re-upload its package on every master message **[INCOMPLETE FIX of CODE_AUDIT_Network §5.24]**
- **Location:** `Modules/GameRPG/Controller/PlayerController+Value.swift:14-29`; `Modules/GameRPG/Controller/PlayerController+MessageProcessing.swift:289-305`; `Modules/GameRPG/Controller/PlayerController+Character.swift:13-28`, `:36-61`; `Modules/GameRPG/Controller/MasterController+ValueMessages.swift:67-81`, `:95-110`
- **What:** On the master's `.failed`, the player clears `hasSendPlayer`. `forwardToProxyClients` calls `scheduleSendCharacter()` for every later non-acknowledgement message; the master requests the package, the player exports and sends it, the import fails again. There is no attempt counter and no backoff.
- **Why:** If the import fails persistently (corrupt package, disk full), each map-state broadcast in a battle triggers another full Character upload. Over SharePlay that fills the 16-operation send queue.
- **Action:** Count failures per Character version, retry with a growing delay, stop after a few attempts, and tell the player the Character was not accepted.
- **Severity:** Medium

### 5.6 SharePlay deferred queue: key collisions, a single retry, and an ignored result **[INCOMPLETE FIX of CODE_AUDIT_Network §5.1]**
- **Location:** `Modules/GameRPG/SharePlay/SharePlayDeferredDeliveryQueue.swift:135-140`, `:236-238`, `:301-306`; `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:467-484`; `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:741`; discarded results at `Modules/GameRPG/Network/GameNetworkController.swift:226-234`, `:249`, `:273` and `GameNetworkController+MasterDelegate.swift:65`
- **What:** The `.event` key is (session, participant, module, counter) with no sender id. The master relays LAN players' messages with their own counters, which all start at 1, so two deferred events with the same module and counter replace each other. A retryable failure is retried once, then dropped with a log. No caller reads the `Bool` from `sendData`.
- **Why:** While a large chunked transfer saturates the send queue, two LAN players' dice rolls with equal counters collapse into one for SharePlay participants.
- **Action:** Add the sender id to the event key, allow more than one retry with backoff, and log or flag a `false` result in `sendPlayer`.
- **Severity:** Medium

### 5.7 Duplicate-row repair picks the survivor by object-ID URI, which differs per device **[NEW]**
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:432-467` (`:442-452`, `:459-461`), `:472-499`; `Modules/CoreRPG/Links/LinkRegisterController.swift:181-192`; `Modules/CoreRPG/Controllable/TagController.swift:141-151`; `Modules/CoreRPG/Controllable/SyncDataControllable.swift:118-128`
- **What:** `fetchAndDelete` keeps the row with the lowest `objectID.uriRepresentation()` and deletes the rest; `fetchId` keeps whichever row the fetch returned first. The comments say this makes two devices keep the same row, but an object-ID URI contains the local store UUID and a local primary key.
- **Why:** The same package imported on two devices gives each device two rows with one uuid. If both run the repair before receiving the other's deletion, each deletes the other's CloudKit record and the item disappears on both. Plausible; unverified how often both repair before the first deletion syncs.
- **Action:** Choose the survivor by data that is equal on every device (newest CRDT clock, then a content digest), or merge the rows.
- **Severity:** Medium

### 5.8 Export writes file blocks of any size, import rejects blocks over 512 MiB **[NEW]**
- **Location:** `Modules/CoreRPG/Controllable/ExportControllable.swift:377-403` (`:388-391`); `Modules/CoreRPG/Model/ItemDataExportModel.swift:55-60`; `Modules/CoreRPG/Controllable/ImportControllable.swift:249-251`, `:299-305`, `:789-790`, `:1011-1016`
- **What:** `appendFile` only requires the size to fit `UInt32`. `readData(size:)` throws `notEnoughData` above `maxSingleBlockSize`, a framing error that aborts the import; `skip` reads through `readData` too.
- **Why:** One attached PDF, audio or USDZ over 512 MiB makes every export a backup that stops importing at that item, and the export reported success.
- **Action:** Apply one limit on both sides: refuse or report the item at export, or stream large blocks to disk on import.
- **Severity:** Medium

### 5.9 Only the latest pre-handshake value update per sender is kept **[INCOMPLETE FIX of CODE_AUDIT_Network §5.18]**
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:140-146`, `:171-180`; `Modules/GameRPG/Controller/MasterController+ValueMessages.swift:32-41`, `:60-65`
- **What:** `pendingValueUpdatesAwaitingOwnership` holds one model per sender. Updates are per entry, so a later update to another entry overwrites the held one.
- **Why:** A player who changes hit points and then another value before the join handshake lands keeps only the second on the master.
- **Action:** Key the buffer by (sender, entryId) with a small cap and replay in counter order.
- **Severity:** Low

### 5.10 An audio contribution import failure still gets no answer **[INCOMPLETE FIX of CODE_AUDIT_Network §5.12]**
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:50-56`; `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:314-318`
- **What:** `updateGame` is called inside the `catch ItemGameStorableError.itemMissing` body. A throw there is not caught by the sibling `catch` that sends `.failed`; it reaches the generic catch, which only logs.
- **Why:** A player sharing a new audio item the master cannot import waits with no result.
- **Action:** Wrap the import in its own `do/catch` that sends the same targeted `.failed`.
- **Severity:** Low

### 5.11 Hand interaction only rolls the local d20s **[NEW]**
- **Location:** `Modules/GameRPG/Table3D/GameInteraction.swift:43-51`, `:54-63`, `:71-77`; `Modules/GameRPG/Table3D/GameTableModel+Dice.swift:113-123`, `:132-137`; `Modules/GameRPG/Table3D/GameTableModel+DiceResults.swift:102-120`, `:207-238`
- **What:** The three interaction callbacks handle `Die20` only. A d6 can be picked up but is never tossed or rolled. The GM can toss a guest-seat d20; it gets a random value, `guestDice` then returns `nil` on the value mismatch, and the guest's result popover stays hidden until the next guest roll.
- **Why:** A player dragging a d6 sees the old result reappear as if it had been rolled; a GM touching a guest die removes that guest's result from every table. Plausible; TabletopKit's behaviour for a dragged cube without a toss is unverified.
- **Action:** Handle `Die` in the three callbacks. Reject interactions on guest-seat dice or re-run `syncGuestDice()` after such a toss.
- **Severity:** Low

### 5.12 Guest-seat membership is keyed by display name and never reset **[NEW 79451c49]**
- **Location:** `Modules/GameRPG/Root/GameRootModel.swift:34`, `:345-352`; `Modules/GameRPG/Root/GameRoot.swift:502-524`; `Modules/GameRPG/Table3D/GameTableView+VisionOS.swift:468-479`
- **What:** `tableGuestNames` is updated only on a dice roll, keyed by `senderName`, and is not cleared on stop or when a player leaves.
- **Why:** Two players with the same name on different platforms flip the guest flag on each roll, and a name from an earlier game stays a guest.
- **Action:** Key by sender id, drop the entry in `lostPlayer`, and clear the set in `performStopGame`.
- **Severity:** Low

### 5.13 External import cleanup resolves files through `url(for:)` **[INCOMPLETE FIX of CODE_AUDIT_20 §5.3]**
- **Location:** `Modules/CoreRPG/Import/ExternalImportReviewSession+Internals.swift:398-415`; `Modules/CoreRPG/Import/ExternalImportReviewSession.swift:282-295`
- **What:** `deleteCreatedFile` is used for created files and for the previous file an attachment superseded. It goes through `url(for:)` (held peer copy first, then the bookmark), where `delete(_:)` and `storedLocation` deliberately never remove `.icloud`/`.other` references. Nothing checks whether another item uses the superseded file.
- **Why:** Re-importing a source over an item whose file is a legacy `.icloud` or `.other` reference deletes the user's original file outside the app's storage.
- **Action:** Remove superseded files with `deleteReplaced(_:keeping:)` and created files by `storedLocation`, with the same "used elsewhere" check as `settleImportedFile`.
- **Severity:** Low

### 5.14 Game-delivered files: no durable cleanup list, a non-durable write can be persisted, and the replaced file stays **[INCOMPLETE FIX of CODE_AUDIT_Folder §5.26]**
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:13-18` (`gameMemoryFiles`, in memory only); `Modules/CoreRPG/Controllable/ImportControllable.swift:570-578`, `:836-856`; `Modules/CoreRPG/Controllable/ItemControllable.swift:260-277`; `Modules/CoreRPG/Controllable/GameControllable.swift:221-230`, `:436-447`; `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:299-324`
- **What:** Three gaps, reported by two reviewers:
  - Files written for game deliveries and saved-game loads are tracked only in memory. If the app is killed before `reset()`, the list is gone; because `importDestination` now takes the next free name, each such session leaves another `name-N` copy in iCloud.
  - `addFile` requires durable storage only when `forceSave` is true. A `save: true` reveal imports with `forceSave: false`, keeps the in-memory fallback on a write error, and `persistFromGame` then stores that `FileUrl` in the library.
  - `persistFromGame` writes a new file reference to the library and nothing removes the file the library item had before.
- **Why:** Orphan files accumulate and sync through iCloud. With a full container, a saved reveal points at a file that does not exist after relaunch.
- **Action:** Persist the pending-cleanup list (or sweep unreferenced files at launch), require durable storage before `persistFromGame`, and run the same settle step as a library import afterwards.
- **Severity:** Low

### 5.15 `move(url:newName:)` never detects an unchanged path, and names with `#`, `?` or `%` produce wrong file names **[verified]** **[NEW]**
- **Location:** `Modules/CoreRPG/Files/CloudDocumentController.swift:195-222` (`:198`, `:204-208`); `Modules/CoreRPG/Controllable/EditControllable+File.swift:15-25`, `:60-69`
- **What:** The guard compares `destination + ext` (no leading slash) with `url.path` (leading slash for every freshly created file), so it never matches; the file then collides with itself and is renamed `name-1`. The destination is parsed with `URL(string:)`, so `#` and `?` cut the path and `%41` is decoded.
- **Why:** Files are renamed for no reason and can land at the module root under the folder's name. No data is lost.
- **Action:** Compare normalised relative paths, and build the destination with `appending(component:)` per name.
- **Severity:** Low

### 5.16 Smaller data-path inconsistencies **[NEW]**
- **Location and what:**
  - `Modules/CoreRPG/CRDT/LWWRegister.swift:24-35`, `:83-86`, `:126-129`; `WallclockTimestamp.swift:87-89`, `:119-123` — a register whose clock is `greatestFiniteMagnitude` cannot be overwritten when the actor tie-break goes against the local device; the actor id lives in `UserDefaults`, which a device transfer copies **[INCOMPLETE FIX of CODE_AUDIT_20 §5.8]**.
  - `Modules/CoreRPG/Controllable/ItemControllable.swift:239-252` — `replace(isInsert: false, forceSave: true)` for an id not in the library adds it to memory but queues no database write, so it is gone after relaunch.
  - `Modules/CoreRPG/Persistence/FilePersistenceController.swift:36-66`, `:130-141` — `load()` runs `migrateOldFile` inside the same `do` as the read; a throwing move returns `[]` and the next save overwrites the bookmark store.
  - `Modules/GameRPG/GameCenter/GameCenterController.swift:90`; `Modules/GameRPG/SharePlay/RPGSharePlayController+JournalAttachments.swift:77-79`, `:223-229` — `Dictionary(uniqueKeysWithValues:)` over ids returned by GameKit and the group-session journal; a duplicate from either framework traps.
- **Why:** Each needs an unusual input (a crafted or maximal clock, a game-only item with a forced save, a failed migration, a framework returning duplicates), so all are plausible, not observed.
- **Action:** Clamp decoded clocks below the maximum and derive the actor per device; persist or skip the in-memory insert; treat a migration failure as non-fatal and still read the new file; use `Dictionary(_:uniquingKeysWith:)`.
- **Severity:** Low

### 5.17 PDF bookmarks store the page label but navigate by page index **[verified]** **[NEW]**
- **Location:** `Modules/PdfRPG/Pdf/PdfContentView.swift:38-42` (`page.label` passed to `createBookmark`); `Modules/PdfRPG/Pdf/PdfWrapperView.swift:65-74` (`Int(entry.pageLabel)` → `page(at: pageNo - 1)`)
- **What:** A bookmark is created with the page's label. Opening it converts that label to an `Int` and uses it as a zero-based index. `go(to:)` is also only called when the selection can be rebuilt from the stored bounds.
- **Why:** In a rulebook whose labels differ from physical pages (roman-numeral front matter, offset numbering, which is common in published rulebooks), a bookmark opens the wrong page or nothing.
- **Action:** Store the page index (`document.index(for:)`) and navigate by index; keep the label for display only. Navigate even when the selection cannot be rebuilt.
- **Severity:** Medium

### 5.18 List tables treat numeric entry names as roll ranges **[verified]** **[NEW]**
- **Location:** `Modules/TableRPG/Controller/TableGenerationController.swift:176-198` (`roll`), `:228-240` (`matchingEntry`); `Modules/TableRPG/Controller/TableRollRange.swift:13-23`; contrast `Modules/TableRPG/Controller/GameController.swift:139-158` (ranges only for `.dice`)
- **What:** For a table without a dice, `roll` draws `1...entries.count`, and `matchingEntry` first looks for an entry whose name parses as a range, for every table type. `selectorRange` reads a leading number from any name ("2 Wolves", "1d6 goblins" → 1...1).
- **Why:** In a list table with entries "2 Wolves", "5 Orcs", "A Dragon", a roll of 2 selects "2 Wolves", and "5 Orcs" can never be rolled.
- **Action:** Apply the range lookup only when the occurrence has a dice, as `GameController.entry(for:with:)` does.
- **Severity:** Medium

### 5.19 The in-game hex-scale slider rebuilds the whole grid on every tick and wipes revealed cells **[verified]** **[NEW]**
- **Location:** `Modules/MapRPG/Map/GameToolBar.swift:282` (slider bound to `model.hexScale`); `Modules/MapRPG/Map/MapEditor.swift:139-145`; `Modules/MapRPG/Controller/EditController.swift:363-368` (`createHexMap`); `Modules/MapRPG/Map/MapHexGridGeometry.swift:76-118`; contrast the editor's update/commit split at `Modules/MapRPG/Map/EditMapToolBar.swift:106-111`
- **What:** `MapEditor.onChange(of: session.hexScale)` calls `createHexMap` for each slider value outside edit mode. That removes all hex entries and appends new ones with fresh ids and default visibility.
- **Why:** Touching the slider during a game hides every hex the GM had revealed, and regenerates up to 20,000 entries per drag step on the main thread.
- **Action:** Commit on `onEditingChanged(false)` as the editor does, and carry the reveal state over by cell coordinate or ask before regridding.
- **Severity:** Medium

### 5.20 Repeat does nothing for a one-track playlist **[verified]** **[NEW]**
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:431-440`
- **What:** `resetPlaylist(complete:)` restarts only when `model.repeatPlayList, model.playList.count > 1`; otherwise it marks playback complete.
- **Why:** A GM looping a single ambient track with Repeat on hears it stop after one pass.
- **Action:** For a single item with repeat on, seek to zero and play.
- **Severity:** Medium

### 5.21 Finishing or failing a 3D scan restarts a capture session behind the UI, and the scan folder is deleted even if attaching failed **[NEW]**
- **Location:** `Modules/SpaceRPG/Record/AppDataModel.swift:115-117` (`endCapture`), `:319-345` (`reset`), `:386-397` (`.ready` → `scheduleStartNewCapture`), `:136-139` (`skipNextAutoRestart` set only by `cancelAndDismiss`); `Modules/SpaceRPG/Record/ReconstructionPrimaryView.swift:25-30`; `Modules/SpaceRPG/View/InlineImporterView.swift:115-135`
- **What:** After the model view's done action, `onCaptureFinished` runs `resetFile(url:)` (which reports no result) and then `endCapture()` → `.completed` → `reset()` → `.ready`. `reset()` removes the whole scan folder including the USDZ, and `.ready` schedules `startNewCapture()` 0.5 s later unless the Cancel button set the no-restart flag.
- **Why:** After a successful scan a new `ObjectCaptureSession` can start unseen with the camera on. If attaching failed, the only copy of the model is already gone. The state transitions are verified by reading; whether the cover stays up and whether the session holds the camera need a device.
- **Action:** Set the no-restart flag on completion and dismiss the cover. Delete the scan folder only after the file was attached, which needs `resetFile` to report success.
- **Severity:** Medium

### 5.22 `TableReceiveSerializer` does not serialize **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_Table §3.2]**
- **Location:** `Modules/TableRPG/Controller/GameController.swift:42-63`, `:167-171`
- **What:** `run` stores only a gate task that awaits the previous gate, then runs `operation()` outside it. The gate finishes at once, so a second call for the same `itemId` starts its operation while the first is still suspended.
- **Why:** Two deliveries of the same table interleave their import and merge exactly as before the fix.
- **Action:** Chain the operation itself: store a task that awaits the previous tail and then runs the operation, and await that task (the pattern `enqueueFileOperation` uses).
- **Severity:** Low

### 5.23 The app's `RollDiceIntent` is a second copy that overwrites the last roll without the newest-wins check **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_18 §3.19]**
- **Location:** `Modules/DiceRPG/Intent/DiceIntents.swift:12-51` (write at `:42-45`), `:76-100` (`IntentDiceType`); the widget's copy at `Sources/DiceRollerWidget/DiceRollerIntents.swift:10-55`, `:60-101`; the fix at `Modules/DiceRPG/Widget/DiceConfiguration.swift:211-231`
- **What:** The widget target imports DiceRPG yet declares its own `RollDiceIntent` and `IntentDiceType` with identical cases. The widget copy and the in-app roll use `DiceConfiguration.recordLastRoll`; the DiceRPG intent still does `loadFromUserDefaults()` → mutate → `save()` with no timestamp check.
- **Why:** A Shortcuts roll racing an app or widget roll can replace the newer result. The window is small. Reported as High by one reviewer and Low by another; the exposure is low, the drift is the real problem.
- **Action:** Route the DiceRPG intent through `recordLastRoll`, and keep one `IntentDiceType` and one roll-and-record helper for both intents.
- **Severity:** Low

### 5.24 Dice text paths bypass the bounds added for decoded dice **[INCOMPLETE FIX of CODE_AUDIT_20 §5.10]**
- **Location:** `Modules/DiceRPG/Model/RawDie.swift:56-64` (`init(text:)`, unclamped), `:187-196` (clamp only in `Sides.init(from:)`); `Modules/DiceRPG/Model/DieModel.swift:169` (`die.max + 1`); `Modules/DiceRPG/Controller/DataController.swift:129-145` (`components[0]` at `:141-142`); `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+DiceAndValues.swift:39-58`
- **What:** The audit-20 clamp (1,000,000 sides) sits only in the `Codable` decode. `RawDie(text:)` accepts any number that fits `Int`; it is used by the Core Data load path and by the Foundry formula mapper. `DieModel.roll` computes `die.max + 1` unconditionally. Separately, `die.split(separator: ":", maxSplits: 1)` omits empty parts, so a stored element of `":"` makes `components[0]` trap.
- **Why:** A Foundry formula such as `1d9223372036854775807` imports as a dice item that crashes the app each time it is rolled, and it reloads unclamped from Core Data.
- **Action:** Clamp in `Sides.sides(_:)` or `RawDie.init` so every construction path shares the bound, and guard `components.first`.
- **Severity:** Low

### 5.25 The PDF selection observer is not scoped to its own `PDFView` **[verified]** **[NEW]**
- **Location:** `Modules/PdfRPG/Pdf/PdfContentView.swift:35-47`; `Modules/PdfRPG/Pdf/SelectionBar.swift:87-93`
- **What:** `notifications(named: .PDFViewSelectionChanged)` is consumed without comparing `notification.object` to `searchModel.pdfView`. Any `PDFView`'s selection sets this view's `selectedEntry`.
- **Why:** With two PDF viewers alive (second window, link window), selecting text in one shows the bookmark bar in the other and can save a bookmark with another document's text and bounds. That two viewers are alive at once in a real layout is unverified.
- **Action:** Pass `object:` to the notification sequence or guard on identity.
- **Severity:** Low

### 5.26 App scene and URL wiring **[NEW]**
- **Location and what:**
  - `Sources/MasterTV/MasterTVApp.swift:9`; `Sources/MasterRPG/iOS/iOSSceneDelegate.swift:23`, `:53-68`; `Modules/RolePlayGameKit/Model/AppModel.swift:30` — the TV app owns `@State AppModel()`, while the shared scene delegate compiled into the TV target calls `AppModel.shared`, which lazily builds a second model graph whose database is never set up; routes park forever.
  - `Sources/MasterRPG/iOS/iOSSceneDelegate.swift:35-47`, `:53-57`; `Sources/MasterRPG/MasterRPGApp.swift:105`, `:138`; `Modules/RolePlayGameKit/Route/RootURLHandler.swift:40-46` — the scene delegate and the SwiftUI open-URL handler both call `RootURLHandler.handles`; imports are de-duplicated by URL, the ready-state module route is not.
  - `Sources/MasterRPG/iOS/iOSAppDelegate.swift:45-53`; `Resources/Info.plist:99-107` — `configurationForConnecting` builds a configuration with `name: nil` and sets the delegate class only for `.windowApplication`, so the Info.plist entry for the external non-interactive display role is not used.
- **Why:** `RPG://` links and continued activities do nothing on Apple TV; a widget or deep link may run its route twice; the external player window may never be created. The last two need a runtime check of what SwiftUI forwards.
- **Action:** Use one `AppModel` on tvOS, keep one URL entry point, and return the named configuration (or set the delegate class) for the external role.
- **Severity:** Low (Medium for the external display if confirmed)

### 5.27 Share extension gaps **[NEW]**
- **Location:** `Sources/RPGShare/ItemProviderImporter.swift:234-250`; `Sources/RPGShare/ShareExtensionSaveController.swift:45-77`; `Sources/RPGShare/ShareViewController.swift:64-67`
- **What:** `loadItem` handles `Data`, `String` and `URL` only, so a provider that vends an image object throws `noItems`. `saveContent` writes each photo file to iCloud and then creates the item and saves; a later failure leaves the files with no row. The macOS `viewDidLoad` returns without `completeRequest` when there are no attachments.
- **Why:** Sharing from a source that passes an image object shows no photo; a failed save leaves orphan files; an empty macOS share sheet has no way out. The image-object case needs a host that vends one.
- **Action:** Accept image objects (or use `loadDataRepresentation`), delete written files when the save throws, and complete the request on the macOS early return.
- **Severity:** Low

### 5.28 Smaller item-module issues **[NEW unless tagged]**
- **Location and what:**
  - `Modules/AudioRPG/Audio/AudioPlayerSession.swift:165-187`; `Modules/AudioRPG/Controller/AudioController.swift:357-365`, `:452-470` — "was playing" at interruption is read from a flag another async task sets, `endInterruption` toggles (and so can pause a player that already resumed), and a media-services reset never replaces `model.player`.
  - `Modules/RolePlayGameKit/Import/Foundry/FoundryMediaNormalizer.swift:136-140` — asset paths are percent-decoded before the query and fragment are stripped, so `Token%20%231.webp` is cut at `#` and dropped as unsupported media.
  - `Modules/GeneratorRPG/BasicAI/Providers/PdfContentExtractor.swift:100-125`; `Modules/GeneratorRPG/View/PdfContentExtractionView.swift:41-47` — per-page errors are only logged and an all-pages failure returns an empty array as success **[INCOMPLETE FIX of CODE_AUDIT_17 §5.20]**.
  - `Modules/GeneratorRPG/BasicAI/Engine/ConversationEngine.swift:273-300`, `:318-341` — overflow recovery sends the entire overflowing transcript to a new session to summarise it, which is likely to overflow again.
  - `Modules/SpaceRPG/Space/SpaceViewer.swift:578-582`, `:716-741` — `children.count > 0 || components.count > 0` is always true, so "The 3D model is empty" never shows, and a meshless USDZ is positioned from an empty bounding box.
  - `Modules/AdventureRPG/Intent/AppendAdventureSectionIntent.swift:29-44`, `CreateAdventureIntent.swift:31-49`, `StartAdventureGameIntent.swift:25-30` — no check that the target still exists or the name is non-empty, unlike `Modules/CharacterRPG/Intent/CharacterManagementIntents.swift:38-41`, `:89-99`.
  - `Modules/PhotoRPG/Photo/InlineImporterView.swift:94-110` — the photo picker's `selectedItem` is never cleared, so picking the same library photo again does nothing.
- **Why:** Each is a wrong or silent result in a secondary flow; the audio and 3D items need a device to confirm.
- **Action:** Record "was playing" from the player and call `play()`; strip query and fragment before decoding; report failed pages and throw when none succeeded; cap the summary input; test `visualBounds(...).isEmpty`; apply the Character intent pattern; reset `selectedItem` after use.
- **Severity:** Low

### 5.29 Items trashed before confirmation are purged if the delete panel never gets to disappear **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_Folder §5.12]**
- **Location:** `Modules/CoreRPG/LGViews/ListRootContextMenu.swift:258-268` (mark, then open the panel); `Modules/CoreRPG/Controllable/EditControllable.swift:510-541` (`markCollectionItemsForRemoval` calls `markForDeletion` for every item and folder child); `Modules/CoreRPG/LGViews/AffectedLinkActionPanelView.swift:88-98` (the only undo is the panel's `.onDisappear`); `Modules/RolePlayGameKit/View/DestinationReadyView.swift:39-52` (`cleanDatabase()` five seconds after launch); per-module `itemDataCleanup()`, e.g. `Modules/PdfRPG/Root/PdfRootModel.swift:190-197`
- **What:** The fix kept "mark first, confirm later". Delete still sets every selected item and folder child to `totalHidden` before the panel opens, and restores them only in the panel's `onDisappear`. If the app is terminated while the sheet is open, `onDisappear` never runs, and the launch cleanup hard-deletes every trashed item, including the linked ones the panel offers to keep. A delete inside the first five seconds after launch has the same effect: the cleanup purges the unconfirmed items under the open panel.
- **Why:** Items the user never confirmed are permanently deleted with their files. Trigger: press Delete, leave the panel open, switch apps, and iOS terminates the app (or Cmd-Q on macOS). The call path is read end to end; that the trashed state reaches the store before termination was not run.
- **Action:** Mark only on Remove (the panel can list candidates without trashing them). Otherwise keep a persisted "pending confirmation" list that launch restores before `cleanDatabase()`, and skip the cleanup while a removal panel is open.
- **Severity:** High

### 5.30 A manual-review import cannot restore a trashed item, and opening a file defaults to manual review **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_Folder §5.20]**
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:527-542` (the merge branch restores), `:550-553` (the manual branch does not), `:618-627`; `Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:230-234`, `:412-434`; `Modules/CoreRPG/Controllable/ItemControllable.swift:378-386`
- **What:** `restoringTrashedItem` is applied only in `.merge`. In `.manual` the review is built from plain `mergeSync`, and `isSame` ignores `displayState`, so a trashed local item that otherwise equals the backup copy is skipped as "unchanged". If it differs, the default decision keeps the local trashed state. A file opened through `initialURL` forces manual mode. Choosing "imported" restores the item but does not re-add its tag counts.
- **Why:** Re-importing a backup by opening the file leaves deleted items in the trash, and they are purged at the next launch. The status table says a merge import restores them.
- **Action:** Apply the same restore rule when building and applying the manual review, and re-add tags on any restore.
- **Severity:** Medium

### 5.31 Smaller regressions from the folder-audit fixes
- **Location and what:**
  - `Modules/CoreRPG/LGViews/AffectedLinkActionPanelView.swift:88-98`; `Modules/CoreRPG/LGViews/ListRootContextMenu.swift:257-268` — the panel's `onDisappear` clears the one shared removal list, which a second Delete issued during the dismissal animation may already have replaced; the second batch then stays trashed with an empty panel **[NEW 88541532]**.
  - `Modules/CoreRPG/Controllable/EditControllable.swift:474-486`, `:948-964` — undo and redo of a library-scoped folder edit call `replace` with the default `forceSave: false`, so during a game they write game memory only while the library keeps the move **[NEW 88541532]**.
  - `Modules/CoreRPG/Controllable/ItemControllable.swift:239-251`, `:260-265`; `Modules/CoreRPG/Controllable/GameControllable.swift:443-446` — for an item new to the library, `persistFromGame` stores the game-memory instance itself as the library instance, so later memory-only updates mutate the library object in place **[NEW 88541532]**.
  - `Modules/CoreRPG/Controllable/ItemControllable.swift:160-193`; `Modules/CoreRPG/Controllable/SyncDataControllable.swift:118-128` — `delete` removes the item from memory before its awaits, so a sync "inserted" batch for the same id can re-add it during the delete **[NEW 5ee4f91b]**.
  - `Modules/CoreRPG/Menu/FolderPlacementMenu.swift` (`OpenFolderButton.init(root:)`, `CloseFolderButton.init(root:)`); `Modules/CoreRPG/Model/FolderListModel.swift:144-147` — the menu-bar Open Folder and Close Parent Folder now resolve by item id, the first row showing that item, where they used the selected row; a collection member has two rows **[REGRESSION 6af151cc]**.
- **Why:** Each needs an unusual sequence (two deletes within one dismissal, undo during a game, a sync batch inside a delete) or shows as a wrong menu state. None was run.
- **Action:** Give each panel presentation its own item list; route undo of a library edit through the library path; insert `model.copy()` in the no-library-copy branch; keep a short "deleting ids" set the sync paths skip; pass the selected row id from the menu-bar buttons.
- **Severity:** Low

---

## 6. Security

### 6.1 Imported file paths that resolve to the module root pass sanitising, and the containment fallback returns the module folder **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_Folder §6.3]**
- **Location:** `Modules/CoreRPG/Files/CloudDocumentController.swift:72-78`, `:86`, `:95`, `:291-293`; `Modules/CoreRPG/Files/FileUrl.swift:191-203` (`sanitizedForImport`); `Modules/CoreRPG/Controllable/ImportControllable.swift:464-468`; `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:239-268`, `:341-347`
- **What:** Same root cause as §5.1, reached from untrusted input. `sanitizedForImport` only rewrites paths with `.`/`..` or embedded slashes. A `.newCloud` path of `/`, `/Documents/x` or `Documents/<module>` passes unchanged and `fullUrl(fileUrl:)` returns the module folder. The Folder §6.3 fix (`920c1c53`) also returns `moduleUrl` when containment fails, so a rejected path becomes the most destructive target available. Commit `88541532` added two more sinks that remove whatever `storedLocation(of:)` returns: `settleImportedFile` → `deleteReplaced(_:keeping:)` and `removeStoredFile` (`Modules/CoreRPG/Controllable/ItemControllable.swift:358-372`).
- **Why:** A metadata-only item in a crafted `.gmz`, or a persisted game delivery, carries such a path. Deleting that item, replacing its file, or a second import carrying a file block for the same id then removes the module folder. Needs a crafted file or peer; the trigger afterwards is an ordinary delete or import.
- **Action:** Have both `fullUrl` builders return an optional and fail on an empty or uncontained result. Make `sanitizedForImport` relocate any path that does not end in a file name below the module root.
- **Severity:** High

### 6.2 A stalled unauthenticated LAN peer can hold a lost player's only reconnect slot **[NEW]**
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift:550-567` (`listenerNewConnection`), `:258-282` (`restart`, `enforceReconnectDeadline`), `:356-364` (`lostConnection` clears the throttle entry without a failure); `Modules/GameRPG/Master/MasterNetworkController.swift:507-523` (redial gives up after 5 attempts)
- **What:** The fallback listener takes the first TCP connection, sets `.notReady`, and drops every other connection for 15 s. A peer that never completes TLS is cancelled at the deadline through `lostConnection`, which clears its throttle entry, so no failure is recorded and it is re-admitted at once. The master's real dial is dropped meanwhile and stops after 5 attempts.
- **Why:** A player whose master restarted stays on "waiting for master" while any device on the Wi-Fi keeps one stalled connection open to the player's advertised service. Unverified: that the listener hands over a connection before TLS completes; the existing deadline code assumes it does.
- **Action:** Record a handshake-deadline expiry as a throttle failure for that source, and allow a small number of parallel pending reconnect handshakes, keeping the first that authenticates.
- **Severity:** Medium

### 6.3 The LAN outbound queue has no cap or backpressure **[STILL OPEN from CODE_AUDIT_17 §6.8]**
- **Location:** `Modules/GameRPG/Network/ConnectionController.swift:45-46`, `:79` (`AsyncStream.makeStream` with the default unbounded policy), `:167-177`, `:283-299`; `Modules/GameRPG/Master/MasterNetworkController.swift:242-266`
- **What:** `send` yields into an unbounded `AsyncStream`, and `sendOrdered` treats the yield as delivery. Each queued element retains the full encoded frame (up to 100 MB) until that connection's `connection.send` returns. Two reviewers reported this independently; the transport rewrite of 2026-09-29 changed its shape but not the gap.
- **Why:** One player on poor Wi-Fi, or a backgrounded device that still answers keepalives, makes the GM device retain every map, photo and PDF broadcast until jetsam ends the game for everyone. Plausible; how long `NetworkConnection.send` suspends on a full TCP window is unmeasured.
- **Action:** Bound queued bytes per connection. On overflow, cancel that connection so the player reconnects and is replayed, or have `sendOrdered` await a per-connection drain.
- **Severity:** Medium

### 6.4 A crafted file name ending in `-9223372036854775807` crashes the app when a name collision is resolved **[verified]** **[NEW]**
- **Location:** `Modules/CoreRPG/Files/CloudDocumentController.swift:230-240`, `:242-272` (`extractedNumber + 1` at `:259-260`); reached from `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:299-324`, `:144-149`; `Modules/CoreRPG/Controllable/ImportControllable.swift:836-840`
- **What:** `increasedFileName` parses the suffix after the last `-` as `Int` and adds 1 with a trapping `+`.
- **Why:** A `.gmz` or peer package with two items whose file path is `a-9223372036854775807.jpg` and different bytes: the second collides, the next name is requested, and the addition overflows. A picked file with that name does the same when one already exists.
- **Action:** Use `addingReportingOverflow` (or cap the parsed number) and fall back to appending `-1`.
- **Severity:** Medium

### 6.5 SharePlay packages are reassembled and decoded before the sender is authenticated **[NEW]**
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:347-373`; `Modules/GameRPG/SharePlay/SharePlayPackageReceiver.swift:96-106`; `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:771-781`
- **What:** Any participant's stream is accepted up to 64 MB (16 streams per source, 128 MB total). `decodedMessage` builds the `Data` and JSON-decodes it before `routeSharePlayUpdate` runs any role, roster or binding check. There is no per-source rate limit on completed packages.
- **Why:** A hostile participant in the call can make every device repeatedly allocate and decode 64 MB envelopes. Plausible; peak memory is unmeasured.
- **Action:** Reject streams from participants that are neither the pinned master nor bound players above a small cap, and add a per-source byte budget like `GameRelayAdmission.admitBytes`.
- **Severity:** Low

### 6.6 Bonjour browse results are processed without bounds **[NEW; dial-slot part STILL OPEN from CODE_AUDIT_JoinCode §6.2]**
- **Location:** `Modules/GameRPG/Browser/BrowserManager.swift:37`, `:205-214`; `Modules/GameRPG/Master/MasterNetworkController.swift:446-478`, `:559-562`
- **What:** `updateGames` does `games.firstIndex` per endpoint (quadratic, on the main actor) with no cap on `games`. `removed` is drained only by `PlayerNetworkController`; the master's browser never calls `takeRemoved()`, so it grows for the whole hosting session. An advertiser copying the public session id can still occupy the 8 outbound dial slots.
- **Why:** A device advertising thousands of services stalls the browse screen and the GM's main actor on every browse update.
- **Action:** Cap tracked services, index by name in a dictionary, and do not record `removed` on the master's browser.
- **Severity:** Low

### 6.7 Peer-reported dice values overflow the result math and crash the receiver **[verified]** **[NEW]**
- **Location:** `Modules/DiceRPG/Controller/GameController+DiceResult.swift:115-121` (`allResults.reduce(0) { $0 + $1 }`), `:62-66`, `:139`; `Modules/DiceRPG/Model/DiceModel.swift:368-378` (`applyResult(text:)` parses each value with `Int($0)`), `:84`; `Modules/DiceRPG/Model/DiceResultModel.swift:58-67` (`isPlausibleReport`); `Modules/DiceRPG/Controller/GameController.swift:102-130`; `Modules/DiceRPG/Game/Detail/DicePlayer.swift:75-88`, `:112-116`
- **What:** `isPlausibleReport` bounds the length of the values string, the dice count and the reported `sum`, but not the parsed per-die values. `DicePlayer` renders `resultColor` → `diceSuccess` → `fumble` → `matchesSpecialValue`, which sums the first results with a trapping `+`. The same unchecked arithmetic exists for a decoded reroll value and for `addDiceEvery * index`.
- **Why:** A participant sending a two-dice result with values `9223372036854775807|9223372036854775807` crashes the GM and every player that shows that player's dice. The DiceRPG path is verified; the GameRPG call sites were seen by grep only.
- **Action:** Clamp parsed per-die results to the die's maximum in `applyResult(text:)`, clamp `addDiceEvery` and reroll values at decode, and use the existing saturating helpers in the result math.
- **Severity:** Medium

### 6.8 `Dictionary(uniqueKeysWithValues:)` over entry ids that can repeat in peer or imported data **[NEW]**
- **Location:** `Modules/MapRPG/Map/MapEditorActionRouter.swift:121`; `Modules/MapRPG/Map/MapEntryViewer.swift:205`; `Modules/MapRPG/BattleRound/BattleRoundModel.swift:118-120`, `:145`; `Modules/PdfRPG/Model/PdfModel.swift:150`; `Modules/TableRPG/Model/TableGenerationModel.swift:41-43`; `Modules/RuleRPG/Model/RuleModel.swift:137-138` (see also §5.16 for the framework-id sites)
- **What:** All seven sites trap on a duplicate key. `Modules/MapRPG/Model/MapSnapshot.swift:84-91` already switched to `uniquingKeysWith` because it "can be built from a decoded network payload". No decode or import path de-duplicates entry ids.
- **Why:** A map, PDF, table or rule payload with two entries sharing an id crashes the receiver on the next reconcile or diff. No normal flow that produces duplicates was found; reachability is a crafted peer payload or import.
- **Action:** Use `uniquingKeysWith` at these sites, or de-duplicate entry ids once at decode and import.
- **Severity:** Low

### 6.9 Error text is still logged as public outside CoreRPG **[INCOMPLETE FIX of CODE_AUDIT_Folder §6.5]**
- **Location:** 68 sites, e.g. `Modules/PdfRPG/Controller/ItemController.swift:47`, `Modules/AudioRPG/Controller/AudioController.swift:208`, `:218`, `Modules/SpaceRPG/Space/SpaceViewer.swift:774`, `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:65`, `+SpaceMessages.swift:129`, `+PhotoMessages.swift:116`, `+PdfMessages.swift:115`, `+ValueMessages.swift:102`. By module: GameRPG 39, AudioRPG 7, PhotoRPG 4, SpaceRPG 3, PdfRPG 3, others 12. Also `Modules/GeneratorRPG/View/PdfSummaryAnalysisView.swift:180` (a user PDF's title) and `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:128`, `:176`
- **What:** The fix replaced `error.localizedDescription, privacy: .public` at 46 CoreRPG sites with `Error.logIdentifier`, but the helper is internal (`Modules/CoreRPG/Extensions/Error+Logging.swift:9`), so no other module can use it. The file-download, file-read and import failure logs in the other modules still publish the description.
- **Why:** Cocoa file errors include the user's file name or path, which is the reason given for the CoreRPG fix.
- **Action:** Make `logIdentifier` public and apply it at the 68 sites; make the PDF title private.
- **Severity:** Medium

### 6.10 Declared capabilities with no code behind them **[STILL OPEN from CODE_AUDIT_12 §6.2 for audio input; otherwise NEW]**
- **Location:** `Resources/MasterRPG-Debug.entitlements`, `MasterRPG-Release.entitlements`, `MasterRPG-Mac-Debug.entitlements`, `MasterRPG-Mac-Release.entitlements` (`com.apple.security.device.audio-input`); `MasterRPG.xcodeproj/project.pbxproj:7316` (`ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = YES`), `:6964-6965`, `:7606-7607`, `:8961-8962` (`NSSupportsLiveActivities`, `…FrequentUpdates`); `Resources/Info.plist:110-115` (`fetch`), `:430-437` (entitlement keys inside Info.plist); `Resources/InfoTV.plist:39-40`, `:95-98`
- **What:** No microphone API is used in `Modules` or `Sources`, yet all four app entitlement files keep audio input. Live Activities are declared for the iOS app, the TV app and the widget, but no file imports ActivityKit. `UIBackgroundModes` lists `fetch` with no `BGTaskScheduler` or fetch handler. The TV plist sets `CKSharingSupported` true while the TV app opens the store without CloudKit.
- **Why:** Unused capabilities draw App Review questions and widen the sandbox.
- **Action:** Remove the audio-input entitlement and build setting, the Live Activity keys, the `fetch` mode and the stray Info.plist keys; align `CKSharingSupported`.
- **Severity:** Low

---

## 7. Performance

### 7.1 The Folder §5.2/§5.26 file checks added per-item scans of the whole library **[REGRESSION 88541532]**
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:347-372` (`libraryFileUrls`); `Modules/CoreRPG/Files/FileUrlDataController+Create.swift:299-334` (`:305-307`, `:332-334`); `Modules/CoreRPG/Controllable/ImportControllable.swift:836-840`; `Modules/CoreRPG/Controllable/GameControllable.swift:221-230`; `Modules/CoreRPG/Controllable/FileVersionGameControllable.swift:193-209`
- **What:** Each imported file builds `libraryFileUrls()` twice and compares every entry with `normalizedPath`, which calls `resolvingSymlinksInPath()` (file-system calls). `removeGameMemoryFiles` does files × library. `localFileVersions` runs the file accessors once per library item. Together with §3.7 this work runs on the main actor.
- **Why:** Importing n files into a library of m file items costs about n × m symlink resolutions; a full backup restore or a game end with many deliveries blocks the UI. Cost not measured.
- **Action:** Build one set of normalised library paths per batch, and mark the file accessors `@concurrent`.
- **Severity:** Medium

### 7.2 Manual review builds entry lists with quadratic scans, partly only for a log line **[INCOMPLETE FIX of CODE_AUDIT_Folder §7.3]**
- **Location:** `Modules/CoreRPG/FileViews/SingleImportModels.swift:225-239`; `Modules/CoreRPG/Controllable/ImportControllable.swift:611-647`, `:742-771`
- **What:** `SingleItemImportModel.from` de-duplicates ids with `Array.contains` and then runs three `first(where:)` per entry. `entryDifferences` repeats the pattern to build a log string for every changed item.
- **Why:** Hex cells are stored as entries, so a map with a few thousand entries costs tens of millions of comparisons per item during a manual import parse.
- **Action:** Index entries by id once per item; build the log summary only when the log level is enabled.
- **Severity:** Low

### 7.3 SharePlay journal sends hash the full payload twice on the main actor **[NEW]**
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:24-49` (`journalAdmissionMetadata` at `:46`), `:78` (`journalMetadata`), `:127-129`, `:554-558`, `:598-611`; `Modules/GameRPG/Model/GameNetworkModel.swift:358-360`
- **What:** Both metadata functions compute SHA-256 over the whole attachment, synchronously inside the `@MainActor` `sendData`. The comment at `:75-77` says "hash once".
- **Why:** Each file-backed reveal (up to 100 MB) costs two digest passes on the main thread at the moment content is revealed.
- **Action:** Compute the digest once, off the main actor, and derive both metadata values from it.
- **Severity:** Low

### 7.4 A flush runs one fetch per queued operation, and link saves scan every link **[NEW]**
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:262-304` (`:277-290`), `:501-521`; `Modules/CoreRPG/Links/LinkRegisterController.swift:162-167`
- **What:** After the batched existence check, each update or delete calls `fetchCoreData(uuid:)`. `savePendingLinks` filters `model.items.values.joined()` on the main actor although `sourceItems` is indexed by source.
- **Why:** A bulk import of n items issues n single-row fetches inside one `perform` block.
- **Action:** Fetch the existing rows once with `uuid IN`, and read pending links from `sourceItems`.
- **Severity:** Low

### 7.5 Remote downloads leave their temp file behind and are not de-duplicated while in flight **[NEW]**
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController+Manage.swift:128-172` (`:144-171`); `Modules/CoreRPG/Files/GuardedRemoteDownload.swift:18-43`
- **What:** `ensureRemoteCache` copies the download to the cache and never removes the source temp file; concurrent callers for the same URL each download it.
- **Why:** Up to 256 MiB per remote item stays in `tmp` until the system clears it.
- **Action:** Move instead of copy, and keep one in-flight task per cache URL.
- **Severity:** Low

### 7.6 The list row cache is never pruned and keeps item models alive **[NEW]**
- **Location:** `Modules/CoreRPG/Model/FolderListModel.swift:40`, `:133-136`; `Modules/CoreRPG/Controllable/FolderListControllable+Search.swift:137-173`
- **What:** `cacheListModels` gains a row per id ever shown and only loses rows on a local delete; each row holds its domain model strongly.
- **Why:** Items removed by sync, import rollback or game end stay in memory for the life of the list model.
- **Action:** Drop cached rows that are not reachable from the rebuilt list.
- **Severity:** Low

### 7.7 Per-frame work in the 3D table with nothing to show **[NEW]**
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+DiceResults.swift:22-75`, `:84-97`; `Modules/GameRPG/Table3D/GameRenderer.swift:127-129`; `Modules/GameRPG/Table3D/GameTableModel+PinSelection.swift:62-86`; `Modules/GameRPG/Table3D/GameTableView+PlatformFlat.swift:368-378`
- **What:** `updateDiceResults` runs every frame: for each of 5 seats it looks up all 12 pool dice, builds two arrays and writes `diceRestingSince`, even when every die is parked. On iOS/macOS, while a pin is selected, each frame computes `visualBounds`, 8 corners and 8 projections.
- **Why:** About 60 snapshot lookups and 10+ array allocations per frame at 90 Hz for the whole session on Vision Pro. Frame cost not measured.
- **Action:** Skip a seat when its dice values and control state are unchanged since the last frame; reuse the corner and projection buffers.
- **Severity:** Low

### 7.8 The room and fog canvas redraws every room on each pan or zoom frame without culling **[NEW]**
- **Location:** `Modules/MapRPG/Map/MapRoomCanvas.swift:40-81` (`orderedSnapshots` rebuilt in `body`), `:130-170` (one clipped `drawLayer` per hidden room), `:215-235` (`MapRoomHitLayer`, one gesture view per room)
- **What:** The viewport transform is applied inside the synchronous `Canvas`, so each transform change re-runs `body`, maps and filters all room nodes twice, and draws every room. Nothing tests room bounds against the visible rectangle.
- **Why:** On a hex map (up to 20,000 cells) panning and zooming does that work on the main thread per frame. Frame cost not measured.
- **Action:** Cull by `bounds` against the visible content rect, cache the ordered snapshots on the room store, and hit-test hex cells by coordinate instead of one view per cell.
- **Severity:** Medium

### 7.9 `MapEditor.init` builds a full `MapEditorSession` on every parent render **[NEW]**
- **Location:** `Modules/MapRPG/Map/MapEditor.swift:23-33`; `Modules/MapRPG/Map/MapEditorSession.swift:124-186`
- **What:** `State(wrappedValue: MapEditorSession(...))` runs in `init`. The session creates a `ViewportModel`, a `MapPinViewModel`, a `MapRoomStore` over all entries and a `MapEditorHistory`; only the first instance is kept.
- **Why:** The same pattern as CODE_AUDIT_20 §7.3 with a far heavier object: on a hex map each parent re-render builds and discards thousands of room nodes.
- **Action:** Create the session once, lazily, with the small store used for `ImageViewer`.
- **Severity:** Low

### 7.10 Smaller main-actor and body work **[NEW]**
- **Location and what:**
  - `Modules/PhotoRPG/Photo/InlineImporterView.swift:94-110`, `:125-140`, `:177-183`; `Modules/PhotoRPG/Controller/EditController.swift:65-68` — library, camera and drop photos are re-encoded with `jpegData` at full resolution on the main actor with no pixel cap; the share extension and Foundry paths downsample.
  - `Modules/RolePlayGameKit/Import/Foundry/FoundryImportView.swift:510-523` — `ForEach(NetworkModules.allCases)` filters all batch items once per module on every body evaluation.
  - `Sources/DiceRollerWidget/DiceRollerProvider.swift:39`, `:47-57` — one timeline entry with policy `.never`, so the Smart Stack relevance computed from "seconds since the roll" never decays.
- **Why:** A 48 MP photo hitches the UI; a large Foundry package is scanned about 13 times per state change; the widget keeps its "recent roll" score until the next roll.
- **Action:** Use an off-main downsampling path; group items by module once when the review is prepared; add a second timeline entry at roll time + 300 s.
- **Severity:** Low

---

## 8. SwiftUI / UI

`Scripts/verify_accessibility.rb` passes across 1,819 production files. The findings below come from reading the views added since audit 20, a preview render, and the repo's localization check.

### 8.1 The new popover buttons are sized by their symbol and stay under 44 pt **[verified]** **[REGRESSION 987f8ae2 of the CODE_AUDIT_20 §8.4 fix]**
- **Location:** `Modules/MapRPG/View/MapPopover.swift:258-299` (`MapPopoverButton`: `.imageScale(.large)`, `.padding(8)`, `.contentShape(.circle)`, `.background(…, in: .circle)`); used by `Modules/MapRPG/View/MapPinActionMenu.swift:75-88` and `Modules/MapRPG/Map/MapEditorOverlayLayer.swift:186-207`
- **What:** The button has no fixed size and no `minimumHitArea()`. The audit-20 §8.4 fix gave the fan buttons a fixed size; the popover rewrite that replaced the fan dropped it again. In the rendered "Map popover row" preview the trash button is about 41 pt and the plus button about 38 pt.
- **Why:** The buttons in one panel differ in size, and both are below the 44 pt touch target on iOS. The red "Remove" action sits next to "Add" with an 8 pt gap.
- **Action:** Give the label a fixed square frame (a scaled metric of at least 44 pt on iOS) before the circle background, or apply the existing `minimumHitArea()` and a common frame.
- **Severity:** Medium

### 8.2 The localization check fails, mostly on false positives, and hides four real gaps **[verified]** **[NEW]**
- **Location:** `Scripts/verify_localization.rb` (exit 1, 55 issues). False positives: about 35 sites in `Modules/RuleRPG` that use `bundle: .ruleModule` (e.g. `Modules/RuleRPG/View/RuleMetadataEditor.swift:12-60`, `Modules/RuleRPG/Controller/EditController.swift:155-172`). Real: `Modules/CoreRPG/Resources/Localizable.xcstrings` keys `"%@"`, `"Convert to group"`, `"prepare group"` and `Modules/GameRPG/Resources/Localizable.xcstrings` key `""` have no complete German localization; 70 stale keys across 13 catalogs (GameRPG 18, `Resources/InfoTVPlist.xcstrings` 11, GeneratorRPG 9, AdventureRPG 6, CharacterRPG 5, RolePlayGameKit 5, CoreRPG 4, TableRPG 4, `Resources/Localizable.xcstrings` 3, MapRPG 2, DiceRPG 1, PdfRPG 1, PhotoRPG 1)
- **What:** The script accepts only `.module`, so the Rule module's own bundle accessor is reported at every site. With the check permanently red, the real findings in the same output go unnoticed.
- **Why:** "Convert to group" and "prepare group" are user-visible in the sheet editor and show in English for German users. A check that always fails cannot gate a commit.
- **Action:** Teach the script the `.ruleModule` spelling (or rename the accessor to `.module`), translate the four keys, and remove the stale keys.
- **Severity:** Low

### 8.3 App Intent entity type names are localized without a bundle **[NEW]**
- **Location:** `Modules/PdfRPG/Intent/PdfEntity.swift:15-16`, `Modules/DiceRPG/Intent/DiceEntity.swift:15-16`, `Modules/WeatherRPG/Intent/WeatherEntity.swift:15-16`, `Modules/AdventureRPG/Intent/AdventureEntity.swift:15-16`, `Modules/CharacterRPG/Intent/CharacterEntity.swift:15-16`, `Modules/PhotoRPG/Intent/PhotoEntity.swift:15-16`, `Modules/MapRPG/Intent/MapEntity.swift:15-16`, `Modules/SpaceRPG/Intent/SpaceEntity.swift:14-15`, `Modules/TableRPG/Intent/TableEntity.swift:15-16`, `Modules/AudioRPG/Intent/AudioEntity.swift:14-15`
- **What:** `TypeDisplayRepresentation(name: LocalizedStringResource("PDF"), numericFormat: …)` has no `bundle:`. The default is the main bundle, and neither `Resources/Localizable.xcstrings` nor `Resources/AppShortcuts.xcstrings` contains these keys; the translations exist only in the module catalogs.
- **Why:** Shortcuts and Siri may show the type names ("Character", "Weather", "3D objects") in English for German and Thai users. Needs a runtime check in Shortcuts: App Intents metadata extraction may resolve the framework bundle on its own.
- **Action:** Check the Shortcuts app in German. If the names are English, pass the module bundle to the resource.
- **Severity:** Low

### 8.4 Smaller issues in the new popover and importer views **[NEW]**
- **Location and what:**
  - `Modules/MapRPG/View/MapPinActionMenu.swift:20`, `:61`; `Modules/MapRPG/Map/MapEditorOverlayLayer.swift:192` — `GlassEffectContainerAll` wraps buttons that are deliberately flat ("no glass inside glass"), so the container has no glass children and does nothing.
  - `Modules/MapRPG/View/MapPopover.swift:113-139` — the dismissal modifier takes keyboard focus as soon as the panel appears (`.task { isFocused = true }`); selecting a pin while a text field has focus moves focus away from it. Plausible; check with a hardware keyboard.
  - `Modules/MapRPG/View/MapPinActionMenu.swift:98-119` — on macOS the pin photo is picked in another window, but the selection is held in `@State` of a modifier on the popover content; closing the popover (Escape, a click on the canvas) before choosing drops the selection silently. Unchanged from before the rewrite.
  - `Modules/CoreRPG/FileViews/ImporterFanView.swift:119-136`, `:141` — collapsed fan buttons are hidden with opacity and `allowsHitTesting(false)` but stay focusable for the keyboard and the tvOS focus engine; `buttonSize` is a fixed 32 pt.
  - `Modules/RolePlayGameKit/View/PersistenceIssueBanner.swift:22-29`, `:80` — VoiceOver is told only when `hasIssue` turns true, so a second issue arriving while the banner is visible is silent; the corner radius is a literal 12 instead of `ResolvedAppTheme.panelCornerRadius`.
  - `Modules/GameRPG/Table3D/GamePinActionMenu.swift:72`; `Modules/GameRPG/Table3D/GameDiceResultPopover.swift:89` — the new fade animations use `.animation(.default, value:)` without the Reduce Motion check the rest of the app applies (they are opacity fades, so the effect is small).
- **Why:** None loses data; each is a small accessibility or consistency gap in code added in the last week.
- **Action:** Remove the empty containers; request focus only when nothing else holds it; move the macOS photo selection state to the pin node; add `.disabled(!isExpanded)` to collapsed fan buttons; announce on a change of the headline or counts.
- **Severity:** Low

### 8.5 Hard-coded layout values remain the largest rule gap **[STILL OPEN from CODE_AUDIT_20 §8.10]**
- **Location:** 244 numeric `.padding(…)`, 306 numeric `spacing:` and 103 numeric `.frame(width:/height:)` calls in `Modules/` and `Sources/`. New since audit 20: the "half of the default padding" literal 8 at `Modules/MapRPG/View/MapPopover.swift:273`, `Modules/MapRPG/View/MapPinActionMenu.swift:21`, `:34`, `:56-57`, `:71`, `Modules/MapRPG/Map/MapEditorOverlayLayer.swift:193`, `:206`, `Modules/GameRPG/Table3D/GameDiceResultPopover.swift:71`
- **What:** The project rule asks to avoid hard-coded padding and spacing. The popover code repeats one literal in eight places with the same comment.
- **Why:** The value does not scale with Dynamic Type and has to be changed in eight places.
- **Action:** Name it once next to `MapPopoverGeometry.arrowLength` (or use a `@ScaledMetric`), and keep retiring the others opportunistically.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

Clean in `Modules/` and `Sources/`: no `TODO`, `FIXME`, `HACK`, `XXX` or `#warning`; no `print(`, `debugPrint(`, `NSLog(` or `dump(`; no commented-out Swift block of three or more lines; no storage-key literal used twice. The files added since audit 20 (`MapPopover*`, `MapPinActionMenu`, `GamePinActionMenu`, `GameDiceResultPopover`, `TablePopoverAnchor`, `TableGuestDice` and the rest) have no declaration without a use. Grep counts below are whole-word over `Modules Sources Tests`, excluding the vendored Navigator.

### 9.1 Dead generator cluster: `ChatInputView` → `AdventureGeneratorController` → `AdventureSessionModel` **[verified]** **[NEW]**
- **Location:** `Modules/GeneratorRPG/BasicAI/View/ChatInputView.swift:6-128`; `Modules/GeneratorRPG/Controller/AdventureGeneratorController.swift:9-233`; `clearChat()` at `AdventureGeneratorController.swift:147` and `Modules/GeneratorRPG/Controller/GeneratorController.swift:242`
- **What:** `ChatInputView` is referenced only by its own `#Preview` and one snapshot test, and it is the only user of `AdventureGeneratorController`. Both `clearChat()` functions have no caller.
- **Why:** About 360 lines ship that the app never runs, and audit 20 §9.8 spent effort sharing scaffolding with this dead type. The copy has drifted: it lacks the generation guard its live sibling has (see §3.10).
- **Action:** Delete the view, the controller, the session model and the snapshot test, then check whether `ConversationSessionModel` still needs to be a protocol.
- **Severity:** Medium

### 9.2 Twenty-two views and helpers are referenced only by their own `#Preview` and snapshot tests **[NEW]**
- **Location:** `Modules/CharacterRPG/View/AddGroupButton.swift`; `Modules/CoreRPG/Menu/AppCommands.swift:7` (`AltLinkWindowCommandView`); `Modules/CoreRPG/Extensions/AltOpenWindowButton.swift`; `Modules/MapRPG/Map/AnimatedMap.swift`; `Modules/CoreRPG/Views/AnimatorView.swift`; `Modules/GameRPG/GameViews/BattleRoundSidebarButton.swift`; `Modules/GeneratorRPG/BasicAI/View/CheckLanguageSupport.swift`; `Modules/CoreRPG/FileViews/FileBrowserPickerView.swift` (177 lines); `Modules/CoreRPG/Controllable/ViewControllableViews.swift:14` (`FileImporterViewWrapper`); `Modules/GameRPG/GameViews/GameToolBarButtonView.swift`; plus `GeneratedSheetEntryContextMenu`, `HeaderFooterContentScrollView` (197 lines), `IOSGameConnectionStatusView`, `ListChildShape`, `MeshAnimationView`, `ModalCloseOkButton`, `ModalPresentCloseButton`, `OverlayGameSideContent`, `RotatePhotoView`, `SelectedMasterView`, `TokenUsageBar`, and `DetailSectionRowViewModifier` with `ImageOverlayButtonStyle` (`Modules/CoreRPG/Buttons/OverlayButtonStyle.swift:5-30`)
- **What:** Each type name appears twice in production (its declaration and its own preview) and nowhere else on any platform. Eighteen also have a generated snapshot test.
- **Why:** About 1,460 lines ship unused, and the snapshot suite spends time on UI nobody sees.
- **Action:** Delete each view with its snapshot test. Check `AltOpenWindowButton` and `SelectedMasterView` first: audit 19 cites them as live examples.
- **Severity:** Medium

### 9.3 Unreferenced symbols left after the folder and import refactors **[NEW]**
- **Location:** (each has no reference besides its declaration)
  - `entryOrNew(for:)` ×8: `Modules/{Adventure,Audio,Dice,Pdf,Space,Table,Weather}RPG/Model/DataModel+Extensions.swift:16`, `Modules/MapRPG/Model/DataModel+Extensions.swift:19` (superseded by `childOrNew`, `Modules/CoreRPG/Persistence/CoreDataRelationship.swift:21-24`)
  - `listItems()` ×11 in the module root models, e.g. `Modules/AdventureRPG/Root/AdventureRootModel.swift:359`, `Modules/PhotoRPG/Root/PhotoRootModel+PhotoAccess.swift:43`
  - `sharePreview` ×11 in the `*Entity.swift` files; `thumbnailRepresentationData` in `Modules/PdfRPG/Intent/PdfEntity+Image.swift:13` and `Modules/PhotoRPG/Intent/PhotoEntity+Image.swift:14`
  - Protocol requirements with a default and no caller: `inlineEditRowViewer` (`Modules/CoreRPG/Controllable/ViewControllable.swift:65`, `:100`), `linkEntries(for:)` (`Modules/CoreRPG/Controllable/LinkControllable.swift:81`, `:339`)
  - `selectionTable` (`Modules/CharacterRPG/Controller/EditController.swift:18`, `Modules/MapRPG/Controller/EditController.swift:17`), `MapEditModel.selectionDice` (`Modules/MapRPG/Controller/EditController.swift:14`)
  - `tabId` (`Modules/RolePlayGameKit/Route/ExtendedTabRouteDestinationView.swift:21`), `RootRoute.allTabs` (`Modules/RolePlayGameKit/Route/RootRoute.swift:115`), `accountAvailable` (`Modules/RolePlayGameKit/Model/DataBaseModel.swift:65`)
  - `PdfEntryModel.createEntry(content:page:bounds:)` (`Modules/PdfRPG/Model/PdfEntryModel.swift:90`), `Flags.legacyNormal` (`Modules/MapRPG/Model/MapWallModel.swift:23`), `DisplayStateMask.nameHidden/.descriptionHidden/.otherHidden` (`Modules/CoreRPG/Model/ItemListable.swift:11-13`), `LinkExpandHighLightValues.italic` (`Modules/CoreRPG/LinkRenderer/LinkHighLightLocations.swift:103`), `AppPersistentActor.rpgWidget` (`Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift:12`)
- **What:** About 45 declarations nobody calls.
- **Why:** Dead API in 12 frameworks. The unused `DisplayStateMask` cases suggest bitmask semantics the code does not implement (§9.8).
- **Action:** Delete them. For `rpgWidget`, either have the widget open the store under that actor or drop the case.
- **Severity:** Low

### 9.4 Fake controllers are reachable from production, so the fakes cannot be gated **[verified]** **[STILL OPEN from CODE_AUDIT_17 §9.4]**
- **Location:** `Modules/CoreRPG/Simple/SimpleSheetEditingSession.swift:79-92`; caller `Modules/TableRPG/Controller/TableGenerationController+OutcomeEditing.swift:29`; `Modules/CoreRPG/Fake/*` (27 files, 1,392 lines); `Modules/CoreRPG/Model/LinkDataModel.swift:6`; `Modules/*/Model/MockData.swift` (13 files)
- **What:** The table-generation outcome editor builds its root from `FakeExportController`, `FakeGameController`, `FakeImportController`, `FakeFolderListController` ×2, `FakeSearchController`, `FakeViewController()` and `RootManager.preview(fake:)`. Across all modules, 59 Fake/Mock/Preview/TestFixtures files (5,851 lines) are compiled into release; 14 contain any `#if DEBUG`. The SwiftData `@Model LinkDataModel` exists only as the preview container schema and as `LinkDataModel.ID` at three sites.
- **Why:** Test doubles are a production dependency, so a change to a fake can alter shipped behaviour, and SwiftData is linked into 14 frameworks for previews.
- **Action:** Give `SimpleSheetEditingSession` real no-op controllers under `Simple/`. Then gate `Fake/`, `MockData` and `PreviewData` with `#if DEBUG`, and replace `LinkDataModel.ID` with `UUID`.
- **Severity:** Medium

### 9.5 Duplicated code that has drifted **[NEW]**
- **Locations:**
  - `Modules/GameRPG/Controller/PlayerController+Photo.swift:26-104` vs `PlayerController+Pdf.swift:14-112` and `PlayerController+Space.swift:22-135` (helpers at `PlayerControllerModel.swift:1058-1104`). PDF and Space drop a stale repair request when the master's baseline version changes, de-duplicate repair requests and re-show the item after a completed repair; Photo does none of the three. Whether that is a live bug (a photo revealed before its bytes arrive not being re-presented) was not traced on the master side.
  - `Modules/DiceRPG/Intent/DiceIntents.swift:12-100` vs `Sources/DiceRollerWidget/DiceRollerIntents.swift:10-101` (see §5.23).
  - Three ImageIO downsampling implementations: `Modules/CoreRPG/Extensions/Image+AKImage.swift:204-255`, `Sources/RPGShare/ItemProviderImporter.swift:129-205`, `Modules/RolePlayGameKit/Import/Foundry/FoundryMediaNormalizer.swift:160-215`. Only the Foundry copy checks the declared pixel dimensions before decoding.
  - Two byte-identical catalogs: `Sources/MasterRPG/AppShortcuts.xcstrings` (MasterRPG target) and `Resources/AppShortcuts.xcstrings` (MasterMac target).
- **Action:** Extract one file-presentation handler parameterised by module and decide deliberately whether Photo needs the repair bookkeeping; expose one CoreRPG downsampling helper with the header guard; keep one shortcuts catalog in both targets.
- **Severity:** Medium

### 9.6 One-typealias controller files remain **[INCOMPLETE FIX of CODE_AUDIT_Folder §9.5]**
- **Location:** `Modules/{Adventure,Audio,Dice,Generator,Map,Pdf,Photo,Rule,Space,Table,Weather}RPG/Controller/SearchController.swift` (11); `Modules/{Dice,Generator,Pdf}RPG/Controller/ExportController.swift` (3); `Modules/{Generator,Rule}RPG/Controller/GameController.swift` (2)
- **What:** The status table says the one-typealias files are now one `Controllers.swift` per module. Sixteen single-typealias files remain, and six of the twelve `Controllers.swift` files hold one typealias each.
- **Action:** Move the remaining typealiases into each module's `Controllers.swift`.
- **Severity:** Low

### 9.7 English-only import errors, "Ok"/"OK", and a Foundry-named registry path **[STILL OPEN from CODE_AUDIT_Folder §9.16, §9.17]**
- **Location:** `Modules/CoreRPG/Import/ExternalImport.swift:266-294`; `Modules/CoreRPG/Import/ExternalImportReviewSession+Internals.swift`; `Modules/CoreRPG/Foundry/FoundryRuleModels.swift` (`errorDescription` bodies); `Modules/CoreRPG/Import/ExternalImportSourceRegistry.swift:109` (`.appending(path: "foundry")`)
- **What:** The three files contain no `String(localized:)`. "Ok" (4 uses) and "OK" (10 uses) are both keys. The importer-neutral registry still stores under a Foundry path.
- **Why:** These error texts reach the import failure UI in English.
- **Action:** As the Folder audit recommended.
- **Severity:** Medium

### 9.8 Raw `displayState` literals remain **[STILL OPEN from CODE_AUDIT_Folder §9.12]**
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:307`, `:318`, `:592`; `Modules/CharacterRPG/Controller/EditController+Repair.swift:139`, `:181`; `Modules/CharacterRPG/Controller/LinkController.swift:152`; `Modules/PdfRPG/Controller/EditController.swift:111`; `Modules/AdventureRPG/Controller/DataController.swift:86`
- **What:** Whole-value writes of `0` and `1` to a field that `DisplayStateMask` treats as a bitmask (16 literal sites, 8 of them writes).
- **Why:** A whole-value write drops the other bits.
- **Action:** Use named helpers and settle on one semantics.
- **Severity:** Medium

### 9.9 Naming: misspellings and `ID`/`URL` casing **[STILL OPEN from CODE_AUDIT_Folder §9.15, CODE_AUDIT_20 §9.15]**
- **Location:** Misspelled: `additioanlEnrtryViewType` (`Modules/CoreRPG/ItemList/EntryDataEditable.swift:40`, `:142`), `EmtpyEntryViewModel` (`Modules/CoreRPG/ItemList/EntryDataAccessible.swift:39`), `oldFileUlr` (`Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:34-35`), `canRemoved` (`Modules/CoreRPG/LGViews/AffectedLinkActionPanelView.swift:43`), `firstLunchKey` (`Modules/CoreRPG/AppModels/AppSettingsModel.swift:238`). Casing, new since audit 20: `showRemoteURLImporter` (`Modules/CoreRPG/LGViews/FileImporterView.swift:20`, `Modules/PhotoRPG/Photo/InlineImporterView.swift:55`), `selectedSourceScopeID` (`Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:41`, `:158`), `newURL` (`Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:231`), `systemID` (`Modules/RuleRPG/View/RuleMetadataEditor.swift:23`)
- **What:** None of the misspelled symbols were renamed. 304 declarations use `ID`/`URL` casing; the densest files are the Foundry mapper and SharePlay admission files (`documentID` 13, `messageID` 12, `scopeID` 9, `parentID` 9).
- **Action:** Rename the new ones now; take the Foundry and SharePlay files in one rename pass. Keep the stored string `"FirstLunchMasterRPG"` and rename only the constant.
- **Severity:** Low

### 9.10 Comments that point at symbols that do not exist **[NEW]**
- **Location:** `Modules/GameRPG/Table3D/GameDiceResultPopover.swift:92` and `Modules/GameRPG/Table3D/GameDice.swift:235` name `GameEquipment.assignSeatsForSharePlay` (the function is `GameTableModel.assignSeatsForSharePlay`, `GameTableModel+Seating.swift:68`); `Modules/CharacterRPG/Controller/EditController.swift:225` and `Modules/CoreRPG/ItemList/EntryDataEditable.swift:53` name `SheetContextMenuView.moveOutOfGroupButton`; `Modules/CoreRPG/Controllable/SearchRootControllable.swift:10`, `:17` say "SwiftData"; `Modules/DiceRPG/Widget/DiceConfiguration.swift:211-213` says `recordLastRoll` is the one write path (§5.23); `Modules/CoreRPG/Persistence/CoreDataRelationship.swift:22-23` describes the dead `entryOrNew` wrappers
- **Action:** Correct the five references.
- **Severity:** Low

### 9.11 `Resources/Master3.icon` belongs to no target **[NEW]**
- **Location:** `Resources/Master3.icon` (732 KB); no hit for `Master3` or `.icon` in `MasterRPG.xcodeproj/project.pbxproj`
- **What:** The Icon Composer bundle is not referenced by the project; every app target uses `AppIcon` or the tvOS brand asset.
- **Action:** Add it to the targets if it is the intended icon; otherwise move it out of `Resources/`.
- **Severity:** Low

### 9.12 Oversized files (>500 LOC): 24, four grew since audit 20 **[STILL OPEN from CODE_AUDIT_Folder §9.13, CODE_AUDIT_20 §9.18]**
- **`Modules/CoreRPG/Controllable/ImportControllable.swift:1036`** (was 884) — split into models (`:7-155`), entry points (`:174-396`), item application (`:457-648`), manual-review diffing (`:649-777`), file handling (`:778-956`), stream reader (`:958-`). Severity: Medium.
- **`Modules/CoreRPG/Controllable/EditControllable.swift:975`** (was 866, although `EditControllable+File.swift` was split out) — move folder/collection (`:323-506`) and menu (`:544-846`) into extension files. Severity: Medium.
- **`Modules/CoreRPG/Controllable/ItemControllable.swift:615`** (was 398) — move the editing section (`:127-583`) into `ItemControllable+Editing.swift`. Severity: Medium.
- **`Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:573`** (was 429) — move `ImportMutationSession` (`:438-568`) and the example URL providers out of the view file. Severity: Medium.
- **`Modules/SpaceRPG/Space/SpaceViewer.swift:1197`** — move the seven private subviews (`:889-1197`) into `SpaceViewer+Subviews.swift`. Severity: Medium.
- **`Modules/RolePlayGameKit/Model/AppModel.swift:683`** (was 659) — move the routing extension (`:466-651`) into its own file. Severity: Low.
- Unchanged or within 15 lines: `FoundryVTTImportReader.swift` 1,282; `PlayerControllerModel.swift` 1,137; `RPGSharePlayController+ChunkedTransport.swift` 940; `RPGSharePlayController.swift` 934; `FoundryRuleModels.swift` 847; `FoundryImportView.swift` 712; `FoundrySystemPackageReader.swift` 705; `DiceModel.swift` 694; `GameRoot.swift` 672; `GameStatisticsTypes.swift` 620; `MasterController.swift` 618 (shrank from 666); `FoundryVTTDomainMapper+Documents.swift` 584; `CoreDataController.swift` 573; `UniversalVTTReader.swift` 573; `PlayerNetworkController.swift` 572; `MasterNetworkController.swift` 572; `SharePlayJournalPublicationQueue.swift` 555; `FoundryVTTArchiveSanitizer.swift` 501.

### 9.13 Unresolved TODOs / FIXMEs
_No findings._ There are no `TODO`, `FIXME`, `HACK`, `XXX` or `#warning` markers in `Modules/` or `Sources/`.

### 9.14 Magic constants: corner radii **[STILL OPEN from CODE_AUDIT_20 §9.17]**
- `cornerRadius: 28` at `Modules/CoreRPG/LGViews/ItemHeaderEditorView.swift` (4), `Modules/CoreRPG/EntryEditor/EntryEditorContent.swift` (4), `Modules/RolePlayGameKit/View/SecondaryTabBar.swift` (2), `BarButtonWithHoverEffectStyle.swift` (2), `UnavailableGlassOverlay.swift`, plus the new `MapPopoverGeometry.cornerRadius = 28` (`Modules/MapRPG/Map/MapPopoverGeometry.swift:37`) — the glass radius is defined in at least six places.
- `cornerRadius: 24` in the Photo and Dice carousel and drop views (19 sites); `cornerRadius: 8` (29 sites). In total 117 literals with 12 distinct values, against 14 uses of `ResolvedAppTheme.panelCornerRadius`.
- **Severity:** Low

### 9.15 Test hygiene **[NEW]**
- **Location:** `Tests/AdventureRPGTests/AppIntentTests.swift:34-58` (a 25-line commented-out test); `Tests/GameRPGTests/SearchModelTests.swift:27-40` (`assigningNilCancelsCurrentTask` awaits a task and asserts nothing; if cancellation regressed it would sleep 10 s and still pass)
- **Action:** Delete or move the commented test; add an expectation that the task was cancelled. There are no `.disabled`, `withKnownIssue` or `XCTSkip` uses.
- **Severity:** Low

### 9.16 Deferred items, current numbers only **[STILL OPEN from CODE_AUDIT_17 §9.7–9.9, CODE_AUDIT_20 §9.10, §9.18]**
- **Location:** `Modules/*/Controller/SyncDataController.swift` (12 files × 20 lines, differing in at most 2 lines); `Modules/*/Route/DetailRoute.swift` (9 files, 4 differing lines); `Modules/*/Intent/` (12 families, 5,822 lines); `Modules/*/Model/DataModel+Extensions.swift`; `Modules/CoreRPG/Model/LinkDataTransferable.swift:50-300` (12 structs differing in one content type); `Modules/GameRPG/Controller/PlayerControllerModel.swift` and `Modules/CoreRPG/Navigator/Core/NavigationSend.swift` (unsplit)
- **What:** Per-module boilerplate, App Intents families and Core Data mappers are unchanged in shape. Thirty production members are used only by tests, among them `addGroup` (`Modules/CoreRPG/Controllable/EditControllable.swift:291`), `startBattle`, `windowViewer`, `gameListView`, `toggleStreaming`.
- **Action:** None new. `SyncDataController` is the cheapest next generic (one entity parameter).
- **Severity:** Low

---

## 10. Cross-cutting recommendations

Patterns worth applying repo-wide rather than one finding at a time:

1. **Make the stored-file resolver able to fail, and never let it return a folder.** §5.1, §6.1, §5.2, §5.13, §5.14 and §5.15 all come from the same place: `fullUrl(fileUrl:)` always returns some URL, guesses the container prefix by component name, and falls back to the module folder. Audit 20 §10.1 asked for "one notion of where the file really is"; `storedLocation(of:)` now exists, but it inherits the resolver's guesses. Have both `fullUrl` builders return an optional, fail on an empty or uncontained path, and put one guard in front of every remove: the target is a file, strictly below the module root, and not referenced by another item.
2. **Stop mutating before deciding.** The Folder audit §10.2 recommended this and the delete panel still trashes first (§5.29, first bullet of §5.31), while the manual import review now holds a global lock for as long as its sheet is open (§3.5). The external import already has the right shape: stage, then commit.
3. **Put bounds in the type, not in one decode path.** Audit 20 §10.3 said this about the die side count; the clamp went into `Codable` only, and the text path, the peer result path and the file-name counter are still unbounded (§5.24, §6.7, §6.4, §6.8). A value that is validated in its initialiser cannot be constructed unvalidated.
4. **One gate for every map send, including answers.** This is the third audit in a row to find a path around the pause toggle (audit 19 §5.7, audit 20 §5.2, now §5.4). The gate belongs in the function that produces a map payload for a peer, not at its callers.
5. **Fix every copy, or delete the copies.** §5.23 (two `RollDiceIntent`s), §5.30 (merge branch fixed, manual branch not), §9.5 (Photo handler without the PDF and Space repair bookkeeping), §9.1 with §3.10 (a dead controller that lacks its sibling's guard) and §6.9 (a logging helper that is internal to one module) are the same event: a fix applied to one of several near-identical sites.
6. **Treat `nonisolated async` as "runs on my caller" in review.** Under approachable concurrency the file helpers, hashing and JPEG encoding in §3.7, §7.1, §7.3 and §7.10 run on the main actor. The compiler will not flag it. A grep for `nonisolated` and plain `async` functions on `Sendable` structs that touch `FileManager`, `Data(contentsOf:)`, `SHA256` or image encoding would list the candidates; mark them `@concurrent`.
7. **Verify a "Fixed" claim with a search, and keep the gates green.** Nineteen findings here are incomplete fixes. Audit 20 §10.5 already recommended grepping for the pattern before marking a finding fixed. The repo has the tools: `verify_accessibility.rb` passes, but `verify_localization.rb` has been red on false positives (§8.2), which is how four untranslated keys and 70 stale keys went unnoticed.

---

## 11. What was NOT audited

- `Docu/`, `Integrations/` (third party), `.git`, `.build`, DerivedData and snapshot reference images. `Modules/CoreRPG/Navigator/` (vendored NavigatorUI) only for obvious crashes.
- Runtime behaviour: no tests, UI tests, Instruments traces or on-device runs. Apart from four clean builds, one preview render (§8.1) and one scratch script reproducing the path arithmetic of §5.1, every finding comes from reading code. Claims marked plausible need a test or a device, in particular:
  - whether the trashed state is on disk when the app is terminated with the delete panel open (§5.29);
  - the timing windows of §3.3, §3.6, §3.8, §3.9 and the fourth bullet of §5.31;
  - how long `NetworkConnection.send` suspends on a full TCP window (§6.3), and whether an accepted connection is handed over before TLS completes (§6.2);
  - the 3D scan restart and camera state (§5.21), audio interruption ordering (§5.28), TabletopKit behaviour for dragged dice (§5.11);
  - whether Shortcuts resolves the entity type names from the framework bundle (§8.3);
  - the external-display scene and double URL routing (§5.26).
- CoreRPG files not read this round: `Foundry/FoundryVTTImportReader.swift`, `FoundrySystemPackageReader.swift`, `UniversalVTTReader.swift`, `FoundryVTTArchiveSanitizer.swift`, `FoundryVTTBridgeDecoding.swift`, `FoundryRuleModels.swift`, the LevelDB log and manifest readers, `Links/LinkReplaceController.swift`, `LinkRegisterListModel.swift`, most of `Sheet/*` and `ItemList/*`, `SearchControllable*.swift`, `ExternalImportSourceRegistry*.swift`. `ImportControllable.swift` got a targeted read, not a full one.
- GameRPG files not read in full: `GroupActivityManager.swift`, `GameTableModel+Viewport.swift`, `+RenderingReadiness.swift`, `PortableGame*.swift`, `TableScaleGestureController.swift`, `GameJoinCodeModel.swift`, `MasterController+ProxyRouting/ProxyDelegate/MessageDispatch/TableMessages/WeatherMessages/DiceMessages`, the player handlers beyond the cited regions, `GameStatisticsTypes.swift`, the statistics views, and `GameRoot.swift` outside lines 314-535.
- Item modules not covered: the RuleRPG importer and normaliser internals, WeatherRPG beyond its viewer, Character `SheetController` and `EditController` bodies, the map working-copy cancel and undo path, `Sources/MasterRPG/Window/*`, `visionOS/*`, `Menu/*`, the widget view files, `Modules/AudioRPG/Controller/GameController.swift`.
- Regression review gaps: no test file was opened, so whether an added test exercises its bug is unchecked. Not re-verified: Folder §3.12, §3.14, §3.16, §5.10, §5.11, §5.16, §5.28, §6.4, §7.1, §8.4, §8.5; audit 20 §3.4, §3.7 beyond §5.3 of this report, §4.2 (the nine `Task.detached` conversions were not compared for priority or capture), §5.5, §5.7, §6.2, §6.3, §7.2, §7.3 and its §8–§9.
- Algorithmic correctness of the Foundry, UniversalVTT and LevelDB parsers, the CRDT types beyond the clock rules, `MapPopoverGeometry` placement and RealityKit/TabletopKit scene math.
- Build settings and scheme configuration beyond the entitlement and Info.plist keys in §6.10; the internals of the `RPGTabletopGameContent` package; StoreKit and App Store Connect parity.
- `Tests/`: quick scan only (§9.15).
- Localization wording: only missing and stale keys were counted (§8.2).

---

## 12. Verification

To spot-check a finding, command-click its `path:line` reference in Xcode; it should land on the cited line. I re-read the following lines myself after the agents reported them.

- **§5.1** — `Modules/CoreRPG/Files/CloudDocumentController.swift` lines 67-88: `components.contains("Documents")` → `drop(while:)` → `dropFirst(2)`, then the `isContained` fallback returns `moduleUrl`. Lines 195-222: `move(url:newName:)` writes through `fullUrl(filePath:)` (which does not strip) and stores `<folder>/<name>.<ext>`. `FileUrlDataController.swift` lines 320-323: `.newCloud` resolves through `fullUrl(fileUrl:)`. `FileUrlDataController+Create.swift` lines 245-256: `delete` removes the resolved URL. `FileManager+Coordination.swift` lines 26-32: `removeItem` has no directory guard. A scratch script copying the resolver gave: `Documents/Rules.pdf` → `<module>`, `Campaign/Documents/Rules.pdf` → `<module>`, `Documents/Maps/x.pdf` → `<module>/x.pdf`, `Handouts/Rules.pdf` → `<module>/Handouts/Rules.pdf`. `git log -S` dates the strip to `7e9a4439` (2026-07-10). Not run in the app.
- **§6.1** — the same script: `/` → `<module>` and `/Documents/x` → `<module>`. `FileUrl.swift` lines 191-203 were read by the reporting agent, not by me.
- **§5.2** — `EditControllable+File.swift` lines 197-232: the destination is `/<folder>/<item name>.<ext>` with no uniqueness check; `FileUrlDataController+Create.swift` lines 35-58: an equal hash reuses the file, otherwise `write(data:to:)` overwrites. `PhotoModel.empty` has an empty name, so a new unnamed photo gets `NewData-<uuid>` and is safe; the collision needs two equally named items.
- **§5.29** — `ListRootContextMenu.swift` lines 258-268: `markCollectionItemsForRemoval` runs before `navigator.navigate(to: .removeAlert)`. `EditControllable.swift` lines 510-541: it calls `markForDeletion` per item. `AffectedLinkActionPanelView.swift` lines 88-98: the restore is in `.onDisappear`. `DestinationReadyView.swift` lines 48-51: `cleanDatabase()` after the 5 s delay. `PdfRootModel.swift` lines 190-197: the cleanup deletes every `totalHidden` item.
- **§5.3** — `HostingSessionStore.swift` lines 40-49: `isPrewarmed` is set after the loop regardless of the read result; lines 57-60: a prewarmed miss skips the Keychain read and falls through to a new UUID.
- **§5.4** — `MasterController+MapMessages.swift` lines 138-152: the `.generic` branch returns `networkMapContentUpdate` with no `mayShareMapState` check; lines 95-112 show the gate on the neighbouring sends.
- **§3.1** — `SyncDataControllable.swift` lines 58-71 and a grep for `syncBatchConsumer` (declaration plus these two uses). `StorageOptionEditor.swift` lines 51-57: the switch ends in `Darwin.exit(0)`, which is why this is Medium.
- **§3.2** — `GameRoot.swift` lines 316-356.
- **§6.4** — `CloudDocumentController.swift` lines 257-260: `extractedNumber + 1`; `Int("9223372036854775807")` parses.
- **§6.7** — `GameController+DiceResult.swift` lines 115-121; `DiceModel.swift` lines 368-378; `DiceResultModel.swift` lines 58-67.
- **§5.17, §5.18, §5.19, §5.20, §5.22, §5.23, §5.25, §5.30** — the cited lines in `PdfContentView.swift`, `PdfWrapperView.swift`, `TableGenerationController.swift`, `TableRollRange.swift`, `GameToolBar.swift`, `MapEditor.swift`, `AudioController.swift`, `TableRPG/Controller/GameController.swift`, `DiceIntents.swift` and `ImportControllable.swift` match the descriptions.
- **§8.1** — rendered the "Map popover row" preview of `MapPopover.swift` (iOS 27.1): the trash button measures about 41 pt, the plus button about 38 pt.
- **§8.2** — ran `ruby Scripts/verify_localization.rb` (exit 1, 55 issues) and `ruby Scripts/verify_accessibility.rb` (passed); read `RuleMetadataEditor.swift` lines 8-34 to confirm the `.ruleModule` sites are false positives.
- **§9.1, §9.4** — grep for `ChatInputView` and `AdventureGeneratorController` outside their own files: no hits. `SimpleSheetEditingSession.swift` lines 76-94 construct the fakes.
- **Clean builds** — the four `xcodebuild … clean build` logs were searched for `warning:` and `error:`; the only hits are appintentsmetadataprocessor notices.

**Corrections to agent reports:**
- §3.1 was reported as High. The only in-process store swap ends in a forced quit a moment later, so it is Medium.
- §5.23 was reported as High by one reviewer (drifted duplicate) and Low by another (small race window). The race is small, so it is Low; the duplication is listed in §9.5.
- §5.1 and §6.1 were reported as two findings by one reviewer and a third by another. They share one root cause; §5.1 is the user-reachable trigger and §6.1 the untrusted-input trigger.
- §6.3 was reported as new by two reviewers. It is the residual that audit 17 §6.8 already named.
- §8.1 was reported as Low with an estimate of about 36 pt. The render measures 38–41 pt and shows the buttons differ in size; with a destructive action 8 pt from its neighbour it is Medium.
- §5.12 and §5.14 were each reported twice and are merged.
- `Docu/CODE_AUDIT_Network.md` was briefed to the reviewers as unfixed. Its own header records a fix pass, and the re-check found 17 of its 24 findings fixed, with the rest changed in shape; the residuals are §5.5, §5.6, §5.9, §5.10 and §6.3 of this report. Two more are unchanged by design and not listed as findings: an incomplete SharePlay stream is logged on expiry with no re-request (Network §5.2, `Modules/GameRPG/SharePlay/SharePlayPackageReceiver.swift:180-200`), and a decode failure is logged without telling the sender (Network §5.8, `Modules/GameRPG/Model/GameMessagePipeline.swift:281-289`).

**Earlier fixes re-verified as correct.** Folder §3.1–3.4, §3.6–3.11, §3.15, §3.17, §3.18, §5.1, §5.3–5.9, §5.13–5.15, §5.17–5.19, §5.21, §5.23, §5.25, §5.27, §6.3 (traversal part), §7.2, §7.4, §8.1–8.3, §9.2–9.4, §9.6–9.10; audit 20 §3.1, §3.2, §3.3, §3.5, §3.6, §3.8, §4.3, §5.1, §5.6, §5.9, §5.11, §6.1, §7.1, §7.4; audit 19 §5.7, §3.13, §3.14. The twelve `FolderListController` files and the bespoke controllers collapsed into generics lost no differing override.

If a finding doesn't reproduce when you open its line, send me the section number and I'll re-investigate.

---

## 13. Remediation status (Critical, High and the §2 quick wins)

Fixed 2026-10-04 on `develop` (uncommitted at the time of writing). Scope of this round: the Critical finding, the three High findings and the seventeen quick wins of §2. Every fix is tagged `See CODE_AUDIT_21 §x.y` in the code. Findings not listed here are unchanged.

| § | Status | Fix |
|---|---|---|
| 5.1 | Fixed | `CloudDocumentController.fullUrl(fileUrl:)` and `fullUrl(filePath:)` return an optional and fail on a path that names no file below the module folder; neither falls back to the module folder. A stored (scheme-less) path is taken as it is, so a user folder named "Documents" resolves to `<module>/Documents/…`. Only an absolute file url is reduced: this device's module folder by exact prefix, another device's container by its `Documents` component. `nameUrl(fullUrl:)` uses the same rule. Existing items in a "Documents" folder need no migration: their file was always written to the path that now resolves. |
| 6.1 | Fixed | Same resolver. `FileUrl.sanitizedForImport` relocates a cloud or local path that would resolve to a storage folder (`/`, a bare `…/Documents/<module>`, `Documents` for `.local`). `createNewFileUrl` names such a file after its file id instead of failing; `importDestination` and `storedLocation` pass the `nil` on. |
| 2 (delete helpers) | Fixed | `FileManager.removeFile(coordinatingAccessAt:)` replaces `removeItem(coordinatingAccessAt:)` and refuses a folder. `removeFileLoggingFailure(at:)` is the one remover of stored files (`delete`, `deleteReplaced`, `removeStoredFile`, the legacy move) and also refuses anything not strictly below a file root of the app (module folder, legacy app-cloud and local folders, remote cache, temp). This also covers `.local`/`.appCloud` references that resolve to their root, which the audit did not list. |
| 5.2 | Fixed | `writeFile(data:)` asks `FileUrlDataController.writeDestination` for the path: the item's own current file is replaced in place unless another item shares it, any other taken name gets a numbered suffix. `CloudDocumentController.write` is atomic. `ItemControllable.isFileUsedElsewhere` keeps a shared file on item delete, file removal and both file replacements. |
| 5.29 | Fixed | Delete only collects (`collectionItemsForRemoval`) and the panel trashes on Remove (`confirmRemoval(of:keeping:)`: trash all candidates, restore the kept ones, in one step). Cancel, a swipe or a terminated app leave every item untouched; the launch cleanup finds nothing unconfirmed. The rows still leave the list when Delete is pressed and return on Cancel. |
| 6.4 | Fixed | `increasedFileName` uses `addingReportingOverflow`; a counter at `Int.max` is kept as part of the name and `-1` is appended. |
| 5.3 | Fixed | `HostingSessionStore` records prewarm per key and only for `.found` or `.notFound`; an unavailable read is repeated at hosting time. Also: an entry of this app run for another code now counts as newer than the Keychain, whose write may still be queued; the stale stored entry could come back (`differentCodeGetsNewSession` failed on that timing). |
| 3.1 | Fixed, differently | The sync consumer resolves `itemControllable.dataControllable` per batch. The proposed "cancel and clear `syncBatchConsumer` in `setUp`" would end the batch `AsyncStream` (a cancelled consumer terminates it), so no later consumer would receive anything. |
| 5.18 | Fixed | `matchingEntry` applies the range lookup only for `tableType == .dice`. Not `diceId != nil`: a dice table without an assigned dice still receives a player's roll (`consumesCategorizedPlayerResult`). |
| 5.20 | Fixed | A one-track playlist with Repeat on is prepared again, which plays it from the start. No test: it needs a playing `AVPlayer`. |
| 5.22 | Fixed | `TableReceiveSerializer.run` chains the operation itself and awaits that task. |
| 5.23 | Write half fixed | The app's `RollDiceIntent` records through `DiceConfiguration.recordLastRoll`. The two intents and the two `IntentDiceType` enums are still separate (§9.5). |
| 5.25 | Fixed | The selection observer ignores notifications whose object is not `searchModel.pdfView`. |
| 5.10 | Fixed | The import inside the `itemMissing` branch has its own `do/catch`; both failure paths answer through `reportFailedAudioContribution`. |
| 5.16, 6.8 | Fixed | `uniquingKeysWith` at the eleven cited lines (GameKit ids, journal attachment ids and dependencies, map, battle round, PDF, table generation, rule). The four remaining `uniqueKeysWithValues` uses build from app-owned values (ZIP paths are checked before, review candidates, the module order, preview fixtures). |
| 8.1 | Fixed | `MapPopoverButton` has one scaled diameter (44 pt on iOS, 36 pt on macOS); tvOS and visionOS keep the bordered style's own size. *Check the two panels on a device.* |
| 8.2 | Partly fixed | The script accepts `bundle: .ruleModule`. German and Thai added for `"%@"`, `"Convert to group"`, `"prepare group"`; the empty GameRPG key is gone with its source (`GameJoinCodeOTPField` uses a verbatim label). `Text("Recover")` names the main bundle. The check still fails on the 70 stale keys in 13 catalogs, which were not removed: a key that is only looked up dynamically would be lost. |
| 9.1 | Fixed | `ChatInputView`, `AdventureGeneratorController` with `AdventureSessionModel`, the snapshot test, `GeneratorController.clearChat()` and the then unused `ConversationEngine.clear()` are deleted. `ConversationSessionModel` is still a protocol with one conformer. |
| 4.1 | Fixed | `import Combine` removed from the nine files. |
| 9.10 | Fixed | The five references are corrected. |
| 9.15 | Partly fixed | `assigningNilCancelsCurrentTask` asserts the cancellation. The commented-out test in `AppIntentTests.swift` is unchanged. |

New tests: `UntrustedImportTests` (folder named "Documents", folder paths that do not resolve, absolute urls, import sanitising), `FileUrlDataControllerFileOperationTests` (delete inside "Documents", a folder reference deletes nothing, the remover refuses folders and foreign paths, write destination, shared file), `CloudDocumentControllerTests` (counter at `Int.max`), `FolderOperationAuditTests` (nothing trashed before Remove), `HostingSessionStoreTests` (locked Keychain at prewarm), `TableGenerationControllerTests` (list table by position).

Noticed while fixing, not changed: in the delete panel an item that is itself selected for removal and also links to another selected item is restored on Remove, because link rows count as kept (`restoredItems` in `AffectedLinkActionPanelView`). The behaviour is the same as before this round.

### 13.1 Remediation status of §3 (Concurrency)

Fixed 2026-10-08 on `develop` (uncommitted at the time of writing). Every fix is tagged `See CODE_AUDIT_21 §3.x` in the code. Verified with the MasterRPG test plan on an iOS simulator (2,141 passed, 0 failed; the 6 visionOS-only `GameTablePinPawnTests` do not run there) and builds for macOS, tvOS and visionOS.

| § | Status | Fix |
|---|---|---|
| 3.1 | Fixed in the first round | See the table above. |
| 3.2 | Fixed | `GameRoot.startMaster` sets `isStartingMaster` before its first suspension and ignores a call that arrives while it is set. `MasterStartView` sets its own flag in the button action (not in the task) and is disabled while starting, so a second tap that would land after `.started` no longer reaches `startMaster` and stops the game. No test: a real start brings up the listener and Bonjour. |
| 3.3 | Fixed | `PlayerNetworkController.stop()` bumps `stopGeneration`; `restart(connection:)` compares it after `connectionThrottle.register` and drops the connection, clearing its throttle entry without an outcome. Test `stopDuringReconnectAcceptDropsTheConnection` passes on both interleavings, so it only catches the old defect when the scheduler puts the stop into the suspension. |
| 3.4 | Fixed | `AudioController.add(audio:replace:)` returns whether it committed. `loadAndPlay` stores its task as cancel-then-replace (`AudioPlayerModel.loadAndPlayTask`) and stops on a discarded or cancelled load. The same shape existed at four more sites, which now stop as well: `GameController.play`, `GameController.loadPlaylist`, `SharingActionView` and `PlayToolbarButton`. |
| 3.5 | Fixed | The import session is released once the parse has finished, also for a manual import; Apply takes a new one (it already called `beginDataMutation()`), and shows "Import Unavailable" and keeps the review open when another operation holds the lock. The review sheet stays non-dismissible by swipe. Not tried in the app: the change is in a view with no unit test. |
| 3.6 | Fixed | New `PendingFileDeletions`: a deletion is findable under the canonical path of its file until it has finished. `ItemControllable.delete` announces it in the step that takes the item out of memory (the file delete itself only comes after the database delete), `importDestination` and `createNewFileUrl` wait for it before they reuse or write that path. A kept file (`keepingStoredFile`) withdraws the announcement. |
| 3.7 | Fixed | `@concurrent`: `heldPeerFileUrl`, `resolveProcessUrl`, `fileDownloaded`, `hasAccess`, `hasLocalData`, `hasDownloadedData`, the bookmark resolve and save in `FileBookmarkController`, and `loadData`/`saveData`/`removeData` in `FilePersistenceController`. The staged-bytes copy is named after the file id and content hash and is not written again when it is there with the full size. The `action` closure of `url(for:action:)` still runs where the caller is. |
| 3.8 | Fixed, by reserving a slot | `CoordinatedAccessLimiter` takes a slot kind: an access to an iCloud item whose current version is not on the device may use all slots but one, the last is kept for accesses that cannot wait for a download. The minimum number of slots went from 1 to 2 so that there is one to keep. No deadline was added: a legitimate large download would hit it, so a stalled download still holds its slot until its caller is cancelled, but it can no longer stop local file work. |
| 3.9 | Fixed | `GameMessagePipeline` has a generation. `reset()` and `cancelAll()` bump it and leave the in-hand event to its drain; `next()` returns nothing while an event of any generation is in hand; `processed` and `requeueCurrentOnCancellation` do nothing but release for an event of a reset session. Consequence: a handler that never returns now holds the pipeline, where a reset used to free it at the price of a second drain. |
| 3.10 | Fixed | `GeneratorController`: `extract` has a cancellation branch, and every catch-side UI write in `request` and `extract` is limited to the newest generation and to a task that was not cancelled. `AdventureGeneratorController` was deleted in the first round (§9.1). No test: it needs FoundationModels. |
| 3.11 | Fixed | `retryUntilRemoved` gives up after `SharePlayAttachmentLoadRetry.maximumCleanupAttempts` (24, about three minutes), logs the abandoned cleanup and calls `finish()`, which releases the reservation. |

New tests: `CoordinatedAccessLimiterTests` (4), `FileUrlDataControllerFileOperationTests` (import after delete, announced and withdrawn deletion, staged copy written once per content), `GameMessagePipelineTests` (reset with an event in hand, no requeue across a reset), `PlayerFallbackListenerTests` (stop during accept), `AudioControllerTests` (superseded load).

### 13.2 Remediation status of §4.2

Fixed 2026-10-08 on `develop` (uncommitted at the time of writing).

| § | Status | Fix |
|---|---|---|
| 4.2 | Fixed | `path(percentEncoded: false)` replaces `URL.path` at the cited lines and at three the audit did not list (`FoundryVTTImportReader.swift`, two source-cache keys; `CaptureFolderManager.swift`, the capture path), and replaces `relativePath` where it was passed as a file-system path (`FilePersistenceController`, `FileUrlDataController`, PhotoRPG `CacheController`). `append(path:)` replaces `appendPathComponent`. One site keeps the old form on purpose: the path alias of an import source is stored in the source index and compared with stored aliases, and `path(percentEncoded:)` keeps the trailing slash of a folder, so `ExternalImportSourceRegistry.pathAlias(of:)` removes it (test `folderPathAliasHasNoTrailingSlash`). Not changed: `FileUrlDataController.swift:81` uses `relativePath` as the text shown for a bookmarked folder, not as a file-system path. |

### 13.3 Remediation status of §5 (Bugs / logic errors)

Fixed 2026-10-08 on `develop` (uncommitted at the time of writing). §5.1, §5.2, §5.3, §5.10, §5.18, §5.20, §5.22, §5.25 and §5.29 were fixed in the first round (table above). Every fix is tagged `See CODE_AUDIT_21 §5.x` in the code. Three behaviours were decided by the project owner before the work: §5.4 (nothing until resume), §5.19 (on release, keep the revealed area) and §5.5 (an entry in the game log).

| § | Status | Fix |
|---|---|---|
| 5.4 | Fixed | One gate, `answersMapRequest`, in front of both request branches of `MasterController.handleMap`: while "Share Map" is paused a `.reveal` or data-less `.update/.generic` request is answered with `.failed` and the map is marked as having unshared structure. The full package is exported from the live game map, so it is withheld as well. The player retries with its own backoff and gets everything on resume. |
| 5.5 | Fixed | `PlayerControllerModel` counts the master's rejections per Character version: retry after 5 s, then 20 s, and after the third rejection the Character is no longer sent. A rejected version is looked at again every 60 s for a change, and a new connection resets the count. The player gets a line in the game log (`LogGameController.addNote`, new string in en/de/th). |
| 5.6 | Fixed | The deferred `.event` key includes the sender id. A retryable chunked failure is retried three times (1 s, 2 s, 4 s) instead of once. The five callers that ignored `sendData`'s result use `sendDataReportingLoss`, which logs a message the session neither sent nor kept. |
| 5.7 | Fixed | `DuplicateRowOrder` orders rows that share a uuid (or a tag, or a link) by their CloudKit record name, which is the same on every device; a row with no record yet sorts last. Used by `fetchAndDelete`, `fetchId` (which kept the first fetched row), `LinkRegisterController` and `TagController`. The object-ID URI is only the last tie-break. Not run against CloudKit. |
| 5.8 | Fixed, at export | `appendFile` leaves a file above the import's block limit (512 MiB) out and reports it like an unreadable file, so the backup stays importable and names what is missing. Import was not changed to stream larger blocks. |
| 5.9 | Fixed | The pre-handshake buffer holds the newest update per entry, at most 32 per sender, and replays them in counter order. |
| 5.11 | Fixed | The three interaction callbacks handle the d6 as well. `canControlDie` refuses the guest seat's dice for everyone, the game master included. *visionOS only; not run on a device.* |
| 5.12 | Fixed | Guests are kept by sender id (`tableGuests`), removed when the player leaves and cleared when the game stops. |
| 5.13 | Fixed | A created file is removed by its stored location. A superseded file is removed only when no library item references it, by stored location, and its bookmark is left alone. A `.icloud` or `.other` reference has no stored location, so the user's own file is never touched. |
| 5.14 | Fixed | (1) The list of game-memory files is also kept in `UserDefaults` per module; the launch cleanup removes what a previous run left behind. (2) A delivery that is stored (`policy == .persist`) imports with `requiresDurableFiles`, and `persistFromGame` refuses a file reference whose bytes never reached disk. (3) `persistFromGame` removes the file the library item had before, unless it is still referenced. |
| 5.15 | Fixed | `move(url:newName:)` splits the destination by `/` itself, compares resolved locations to detect an unchanged path, and returns the stored path built per component (`nameUrl`). |
| 5.16 | Fixed | Decoded clocks are capped at half the largest finite value, by a constant. The CRDT actor id is bound to the device: a marker (Keychain "this device only" on iOS, tvOS and visionOS; the hardware UUID on macOS) is stored with it, and a new id is created when the marker differs. An existing id is kept. `replace` for an id that is not in the library now always queues the database write. A failing migration of the old store file no longer ends the load. The `Dictionary` part was fixed in the first round. |
| 5.17 | Fixed, differently | No new stored field: a bookmark still stores its page label, and `PdfBookmarkPage` resolves the label to a page (the page that still holds the bookmarked text when labels repeat, else the first; a number as a position only when no page has that label). This also repairs existing bookmarks and needs no CloudKit schema change. The page is opened even when the selection cannot be rebuilt. |
| 5.19 | Fixed | The slider commits when it is released (`GameToolBarSession.commitHexScale()`, for the 2D map and the 3D table). `createHexMap` carries the revealed area over: a new cell starts shown when its centre lies in a cell that was shown. On the 3D table the slider used to store the scale without rebuilding the grid; it now rebuilds and broadcasts it. |
| 5.21 | Fixed | `resetFile(url:itemId:)` returns whether the file was attached. `AppDataModel.finishCapture(attached:)` sets the no-restart flag and the scanner dismisses itself. When attaching failed, the model's folder is kept and only photos and snapshots are removed. *Needs a device with object capture.* |
| 5.23 | Fixed, enums kept | Both intents call `DiceIntentRoll.rollAndRecord`. The two intents and their `IntentDiceType` enums stay separate declarations: App Intents metadata is extracted per target, and merging them needs an `AppIntentsPackage` setup and a check on a device. |
| 5.24 | Fixed | The side limit sits in `Sides.number()`, so text, code and decoded dice share it. `DataController.dice(from:)` guards the empty split. |
| 5.26 | Fixed | The TV app uses `AppModel.shared`. `RootURLHandler` asks `AppModel.admitsExternalRoute` in the ready state, so a link delivered by the scene delegate and by SwiftUI runs once. `configurationForConnecting` returns the "External Game View" configuration with the scene delegate for the external display role. *The external display needs a runtime check.* |
| 5.27 | Fixed | `loadItem` falls back to the provider's data representation for an object it does not know (an image object). A failed save removes the written photo files and rolls the context back. The macOS controller completes the request when there is nothing to share. |
| 5.28 | Fixed | Audio: the interruption uses the app's own play intent (`wantsPlayback`), resumes with `play()`, and a media-services reset replaces the player and its observers. Foundry: query and fragment are cut off before decoding. PDF extraction: failed pages are reported, and no page succeeding is an error. Overflow recovery summarises the newest 6,000 characters. The 3D viewer tests `visualBounds(...).isEmpty`. The three Adventure intents check the name and the target. The photo picker clears its selection. |
| 5.30 | Fixed | The manual branch applies `restoringTrashedItem` like the merge branch, and applying a review re-adds the tags of an item that leaves the trash. Opening a file still starts in manual review. |
| 5.31 | Fixed | (a) The removal panel only clears the list it was opened for. (b) Undo and redo of a library-scoped folder edit go through `persistMembershipChange`. (c) `persistFromGame` inserts a copy. (d) `ItemControllable.delete` keeps the id in `deletingIds` while it runs, and sync skips it. (e) The menu-bar Open Folder and Close Parent Folder use the selected row. |

New tests: `CodeAudit21BugFixTests` in GameRPGTests (Character rejections, log note, deferred event key, retry backoff, pending value updates) and CoreRPGTests (duplicate row order, persisted game-file list, file move, actor id, clock cap), `PdfBookmarkPageTests`, and cases in `MapMasterMessageFlowTests` (paused requests), `MapHexGridGeometryTests` (revealed area), `RawDiceLimitsTests` (side limit), `FoundryMediaNormalizerTests` (encoded `#`/`?`) and `TableGuestDiceTests` (guests by id).

Not covered by a test, and not run in the app: §5.7 against CloudKit, §5.11, §5.13, §5.21, §5.26, §5.27 and the audio, intent and viewer parts of §5.28.

Verification: the MasterRPG test plan on the iOS simulator (iPhone 18 Pro) passes with 1,950 test functions in 14 runs and no failure, after a clean build; MasterRPG for visionOS, MasterTV and MasterMac build from clean with no Swift warnings. `AudioControllerTests.interruptionsAndRouteChanges` was rewritten for the intent-based interruption handling of §5.28.

### 13.4 Remediation status of §6–§9 (Security, Performance, SwiftUI, Code quality)

Fixed 2026-10-08 on `main` (uncommitted at the time of writing). §6.1, §6.4, §6.8, §8.1, §9.1 and §9.10 were fixed in the first round (table above). Every fix is tagged `See CODE_AUDIT_21 §x.y` in the code. Four points were decided by the project owner before the work: §6.10 (remove the audio-input entitlement, the Live Activity keys and the stray plist keys; the `fetch` background mode stays), §9.2 (delete what is confirmed unused), §9.11 (`Master3.icon` is not used, delete it), and the large refactors (§9.4, §9.12, §9.14 and the full rename of §9.9) are not wanted.

| § | Status | Fix |
|---|---|---|
| 6.2 | Fixed | A reconnect attempt that has not finished its handshake after `GameLimits.reconnectHandshakeGrace` (3 s) is replaced by the next incoming connection, and an attempt that runs into its deadline counts as a failure for the connection throttle. |
| 6.3 | Fixed | `ConnectionController` counts the bytes it has queued. A frame that would take the queue over `GameLimits.maximumOutboundQueuedBytes` (three full messages) closes the connection as failed; the peer reconnects and is brought up to date. One frame always goes out, whatever its size. |
| 6.5 | Partly fixed | `SharePlayInboundByteBudget` gives each participant 512 MiB of reassembled packages per minute (the LAN relay's budget); a package over it is dropped before it is decoded. The package is still decoded before the sender's role is known: SharePlay has no authenticated role to check against at that point. |
| 6.6 | Partly fixed | `BrowserManager` tracks at most 256 services, looks entries up by name once per update, bounds the removed list, and the master's browser no longer collects removals. The dial-slot part (CODE_AUDIT_JoinCode §6.2) is unchanged. |
| 6.7 | Fixed | `DieModel.boundedResults` clamps every result to `0...die.max` and keeps at most 100, in the initialiser and in decoding. The sums in `GameController+DiceResult` and `DiceModel.maxValue` saturate. |
| 6.9 | Fixed | `Error.logIdentifier` (domain and code) is logged publicly and the description privately at the 67 sites outside CoreRPG. Journal error text, a PDF title, SharePlay session descriptions and the connection failure message are private as well. |
| 6.10 | Fixed as decided | Removed: `com.apple.security.device.audio-input` from the four app entitlement files with its build setting, the `NSSupportsLiveActivities` build settings, `CKSharingSupported` from `InfoTV.plist`, and the four entitlement keys that sat in `Info.plist`. The `fetch` background mode is kept. |
| 7.1 | Fixed | `isSameStoredFile` and the `isReferenced` check of `importDestination` compare the file name first and resolve paths only for a name that matches. |
| 7.2 | Fixed | The review entry lists are built from an index by id. `logManualReviewDifference` returns before it builds anything when the info log is off. |
| 7.3 | Partly fixed | The payload digest is computed once per send and handed to both admission checks. It is still computed on the main actor. |
| 7.4 | Fixed | `flushPendingOperations` fetches the existing rows once per flush (`existingRowsInContext`). `savePendingLinks` reads the links of the affected items only. |
| 7.5 | Fixed | `RemoteDownloadsInFlight` keeps one download per cache path; later callers wait for it. The temporary file is moved into the cache and removed in every case. |
| 7.6 | Fixed | `FolderListModel.pruneCache(isGone:)` drops rows whose item no longer exists whenever the filter is reset. |
| 7.7 | Open | Not changed. The per-frame subscription also drives the dice rest detection; taking it out needs a measurement on a Vision Pro. |
| 7.8 | Partly fixed | `MapPassiveRoomCanvas` draws only rooms that intersect the visible part of the map (`visibleContentRect`, grown by the stroke margin). The hit-test layer is unchanged. |
| 7.9 | Fixed | `MapEditor` holds its session in `LazyState`, so a parent render no longer builds one. |
| 7.10 | Fixed | A picked or dropped photo is decoded (bounded) and encoded off the main actor (`resetPhoto(data:itemId:)`). `FoundryImportView` groups its items once. The dice widget timeline has a second entry 300 s after the roll instead of a relevance that never ends. |
| 8.2 | Fixed, one file left | 76 stale keys that no code in their module can look up are removed, eleven of them keys of the views deleted for §9.2. `Create` in PdfRPG is marked `manual` (its only use is excluded on tvOS). `Scripts/verify_localization.rb` now fails only on `Resources/InfoTVPlist.xcstrings`: all eleven of its keys are stale and its name does not match the `InfoPlist` convention, so it is probably not used at all. Left for a decision. |
| 8.3 | Fixed, not verified at run time | The twelve entity type names are in the app's `Resources/Localizable.xcstrings` with the modules' German and Thai text, marked `manual`. Check one type name in Shortcuts with the device set to German. |
| 8.4 | Fixed except (c) | The popover takes keyboard focus only with a hardware keyboard (always on macOS). The importer fan's buttons are disabled while collapsed and scale with Dynamic Type. The persistence banner announces a new issue to VoiceOver once. The fades of the pin menu and the dice result popover respect Reduce Motion. The three nested glass containers are gone. (c), the selection state of the pin photo on macOS, is unchanged. |
| 8.5 | Partly fixed | `MapPopoverLayout.contentInset` names the inset at the eight popover sites, and the banner uses the theme's panel corner radius. The other hard-coded values stay (see §9.14). |
| 9.2 | Fixed | 21 files of views and helpers used only by their own preview are deleted, with `ImageOverlayButtonStyle` and the 19 generated snapshot tests. `MeshAnimationView` is kept: the snapshot generator uses its `meshAnimationEnabled` switch. |
| 9.3 | Fixed, four cases kept | 43 declarations are removed (`entryOrNew` ×8, `listItems()` ×11, `sharePreview` ×11, `thumbnailRepresentationData` ×2, `inlineEditRowViewer`, `linkEntries(for:)`, `selectionTable` ×2, `selectionDice`, `tabId`, `RootRoute.allTabs`, `accountAvailable`, `PdfEntryModel.createEntry`). Kept because their raw value can be in stored data or parsed text: `LinkExpandHighLightValues.italic`, `Flags.legacyNormal`, the three unused `DisplayStateMask` cases and `AppPersistentActor.rpgWidget`. |
| 9.4 | Not done | By decision. |
| 9.5 | Partly fixed | `ImageDownsampler` in CoreRPG is the one ImageIO downsampling call and holds the declared-size limits. The Foundry import and the share extension use it, and the share extension now refuses an image over the limits before decoding. The app's display decode (`AKImage.boundedDecode`) shares the downsampling call but not the limit: its callers fall back to a full decode on `nil`, and a user's own very large map would stop showing. One `AppShortcuts.xcstrings` (`Resources/`) is in both app targets. The dice intents were handled in §5.23. The Photo, PDF and Space presentation handlers are not merged, and whether Photo needs the repair bookkeeping was not traced. |
| 9.6 | Fixed | The sixteen files are gone; their typealiases are in each module's `Controllers.swift`. |
| 9.7 | Fixed, path kept | The 39 import error strings are localized (en, de, th), and "Ok" is "OK". The registry's `foundry` folder name is unchanged: it is a stored iCloud path, and renaming it would split the registry between app versions. |
| 9.8 | Fixed | The nine writes of a bare `0` or `1` use `DisplayStateMask.fullVisible` and `.groupHidden`. Previews, fixtures and the models' empty-value factories keep `displayState: 0`. |
| 9.9 | Small part fixed | Renamed: `additionalEntryViewType`, `EmptyEntryViewModel`, `oldFileUrl`, `canRemove`, `firstLaunchKey` (the stored key keeps `"FirstLunchMasterRPG"`), `showRemoteUrlImporter`, `selectedSourceScopeId`, `newUrl`. `systemID` is not renamed: it is a synthesized coding key of stored rule metadata, so the rename needs explicit coding keys. The rest of the `ID`/`URL` rename is not wanted. |
| 9.11 | Fixed | `Resources/Master3.icon` is deleted. |
| 9.12, 9.14 | Not done | By decision. |
| 9.15 | Fixed | The commented-out test is removed; a short note says why entity queries are not tested in process. |
| 9.16 | No action | As the finding says. |

New tests: `DieResultBoundsTests` (clamping, count, decoding), `SharePlayInboundByteBudgetTests`, `BrowserManagerLimitTests`, `ImageDownsamplerTests`, `ConnectionOutboundQueueTests` (a connection that is never started stands in for a peer that does not read), two cases in `MapRoomCanvasTests` (visible rectangle) and `stalledAttemptIsReplaced` in `PlayerFallbackListenerTests`.

Not covered by a test: §7.1–§7.4, §7.6, §7.9, §7.10 and the view changes of §8. None of the §8 changes and none of §6.10 was run in the app.

Verification: the MasterRPG test plan on the iOS simulator (iPhone 18 Pro) passes with 1,966 tests in 14 runs and no failure. `downloadsRemoteURLIntoCacheOnFirstUse` was changed for §7.5: it used to delete the downloaded file itself, which is now moved into the cache, and it asserts that instead. MasterRPG for iOS and visionOS, MasterTV and MasterMac build from clean with no Swift warnings. The renamed and removed public API needs a clean build once, and a from-scratch build can need a second pass (stale or half-written eager-linking stubs report undefined symbols or an unknown file type). `Scripts/verify_localization.rb` fails only on `Resources/InfoTVPlist.xcstrings`.
