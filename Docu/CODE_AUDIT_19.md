# MasterRPG Code Audit

Generated 2026-09-29 (19th audit) against commit `6a7b5fa0` (`develop` and `3.0-618` point at the same commit). Scope: 2,109 Swift files (~273k LOC, of which ~77k LOC are tests) across the MasterRPG (iOS/iPadOS/visionOS), MasterMac, MasterTV, RPGShare and DiceRollerWidget targets and 15 modules. `Docu/`, `Snapshots/`, `Integrations/`, `.git`, `.build` and `DerivedData` are excluded; `Tests/` got quick reads only. There is no `Dead/` folder and no Metal code.

Every finding cites `path/to/file.swift:LINE` and recommends an action. No code was changed.

**Ground truth (compiler).** Clean full Debug builds into fresh derived-data folders, Swift 6 mode, `SWIFT_STRICT_CONCURRENCY = complete`, toolchain `/Applications/Xcode-27b1.app` (the `xcode-select` default on this machine):

| Scheme / destination | Result | Swift warnings |
|---|---|---|
| MasterRPG, iOS Simulator | BUILD SUCCEEDED | 0 |
| MasterRPG, visionOS Simulator | BUILD SUCCEEDED | 0 |
| MasterMac, macOS | BUILD SUCCEEDED | 0 |
| MasterTV, tvOS Simulator | BUILD SUCCEEDED | 0 |

The only other diagnostics were "appintentsmetadataprocessor: Metadata extraction skipped" tool notices. The visionOS build failure reported in CODE_AUDIT_18 §5.1 is fixed. No tests were run.

**Relationship to earlier audits.** CODE_AUDIT_18 (2026-09-26, base `9156df35`) was remediated in 26 commits between `bcf27384` and `2b882f8b`. After that, 14 feature commits followed (`95ddb1c2` … `6a7b5fa0`: 3D tile fog, map-size repair, 2D/3D toggle, join code, pause-sharing for 2D, dead-defender handling, text stack-overflow fix, inline dice refresh, and others). This audit had three goals: (1) check the audit-18 fix pass for regressions and incomplete fixes, (2) review the new feature commits, and (3) do a general sweep. The tags used:
- **[REGRESSION `sha`]**: that commit introduced the defect.
- **[INCOMPLETE FIX of CODE_AUDIT_18 §X.Y]**: an item marked fixed that does not fully work.
- **[NEW `sha`]**: a defect in feature work since audit 18.
- *(still open, CODE_AUDIT_18 §X.Y)*: an item audit 18 deferred by decision, noted once.
- Items with a "won't fix"/"accepted risk" decision (player overwrite by id, 4-digit join code, hex cells as entries) are not reported again.

**How to read verification.** **[verified]** means I re-read the cited lines myself after an agent reported them (see §12). Findings without the tag were read by the reporting agent but not independently re-read. Treat their line numbers as reliable and their severity as that agent's estimate. Corrections to agent reports are listed at the end of §12.

**Result in one line.** No Critical findings. There are two High findings: a rolled-back Foundry/UniversalVTT import can still be committed to the store (§5.1), and the new "Fix Map Size to Photo" button can zero or distort a map (§5.2). The main pattern is that the audit-18 §5.3 fix (re-queue flushed edits on rollback) creates three new persistence hazards (§3.4, §5.1, §5.3), and nothing surfaces them to the user (§5.13). The new pause-sharing for 2D maps is bypassed by battle, health and roster rebroadcasts (§5.7).

---

## 1. Executive summary

Top items to address, in priority order:

1. **[High] A rolled-back external import can still commit its items, which point at deleted attachments** — §5.1 — `Modules/CoreRPG/Persistence/CoreDataController.swift:87-95,152-156`, `Modules/CoreRPG/Import/ExternalImportReviewSession.swift:302-318`. **[verified]** **[REGRESSION 9b40de42]**
2. **[High] "Fix Map Size to Photo" zeroes the map while the photo is loading, and distorts rotated maps** — §5.2 — `Modules/MapRPG/Map/MapEditController+PhotoSize.swift:15-52`. **[verified]** **[NEW c9afb6f6]**
3. **[Medium] Paused "Share Map" is bypassed by battle, health and roster rebroadcasts** — §5.7 — `Modules/GameRPG/BattleRound/BattleRoundController.swift:390-405`, `MasterController+MapMessages.swift:179-195`, `MasterController+Control.swift:120`. **[verified]**
4. **[Medium] A recurring save error now stalls every module's persistence for the whole session, silently** — §5.3 — `Modules/CoreRPG/Persistence/CoreDataController.swift:87-95,224-242`. **[REGRESSION 9b40de42]**
5. **[Medium] A re-queued older snapshot can overwrite a newer committed edit** — §3.4 — `Modules/CoreRPG/Persistence/CoreDataController.swift:33-38,86-95,184-222`. **[REGRESSION 9b40de42]**
6. **[Medium] Direct context writes (`addNew`, `delete`, `batchReplace`) are still lost on a rollback** — §5.4 — `Modules/CoreRPG/Persistence/CoreDataController.swift:152-156,274-318`. **[INCOMPLETE FIX of §5.3]**
7. **[Medium] The remote-URL check accepts the expanded IPv6 loopback address (SSRF)** — §6.1 — `Modules/CoreRPG/Files/FileUrl.swift:199-238`. **[verified]** **[INCOMPLETE FIX of §6.5]**
8. **[Medium] Replacing an item's file deletes the old file before the new one exists** — §5.9 — `Modules/CoreRPG/Controllable/EditControllable.swift:647-686`. **[verified]**
9. **[Medium] Stale Bonjour removals fail a fresh LAN join** — §3.1 — `Modules/GameRPG/Player/PlayerNetworkController.swift:448-460`. **[verified]** **[REGRESSION 477ebf3a]**
10. **[Medium] A dead defender is highlighted again on the next turn** — §5.8 — `Modules/MapRPG/Controller/GameController+Metadata.swift:306-321`. **[verified]** **[NEW 25a7b71b]**

---

## 2. Quick wins (≤30 min each)

- **Hide the "Fix Map Size" button unless the photo has a positive size, and compare with the resolver's tolerance** — `Modules/MapRPG/Map/MapEditController+PhotoSize.swift:15-19` (§5.2).
- **Call `removePendingOperations(for:)` in `deleteForExternalImport`** — `Modules/CoreRPG/Controllable/ItemControllable.swift:279-291` (§5.1).
- **Filter dead combatants out of the highlight set** — `Modules/MapRPG/Controller/GameController+Metadata.swift:312-314` (§5.8).
- **Use `$1` for the second die** — `Modules/DiceRPG/Controller/GameController.swift:566` (§5.15).
- **Accept the legacy `three` key on decode** — `Modules/DiceRPG/Model/RawDie.swift:170-186` (§5.14).
- **Parse IP literals with `IPv6Address`/`IPv4Address` and check the bytes** — `Modules/CoreRPG/Files/FileUrl.swift:209-223` (§6.1).
- **Route the share extension's image download through `GuardedRemoteDownload`** — `Sources/RPGShare/ItemProviderImporter.swift:154-164` (§6.2).
- **Drain `takeRemoved()` before starting the removal loop** — `Modules/GameRPG/Player/PlayerNetworkController.swift:448-460` (§3.1).
- **Keep the original timestamp when re-stashing a navigation send** — `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:420,457` (§3.2).
- **Gate "Open in Window" on `supportsMultipleWindows`** — `Modules/CoreRPG/Model/OpenFileWindowModel.swift:96-108` (§5.16).
- **Hide the player report row when `!isShareable`** — `Modules/CoreRPG/LGViews/GameShareView.swift:32-36` (§8.1).
- **Delete the empty extensions, orphaned helpers and unused CoreDataController APIs** — §9.1, §9.2, §9.3.
- **Rename the five new `URL`-suffixed members to `Url`** — §9.10.

---

## 3. Concurrency

The compiler reports zero concurrency warnings on all four platforms. Every finding below is a logic-level ordering, cancellation or lifetime issue that the type checker cannot see. The agent's clean scans found no `DispatchQueue` outside the NWConnection/NWListener bridges, no `ObservableObject`/`@Published`/`@StateObject`, no `withObservationTracking`, and no `@Observable` class without `@MainActor`.

### 3.1 Stale Bonjour removals fail a fresh LAN join **[verified]** **[REGRESSION 477ebf3a]**
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift:448-460` (armed at `:151,:158`; failure path `:350-372`); `Modules/GameRPG/Browser/BrowserManager.swift:173-183`
- **What:** The new `Observations({ browser.removed })` loop yields the current value on its first iteration, so removals that accumulated while the player was only browsing are handled immediately after the join starts.
- **Why:** If one of those removals is the master's endpoint (for example, the GM restarted hosting while the player watched the list), `lostConnection(for:)` runs while the connection is still `.notReady`, and the join fails at once with `.unreachable`. The old one-shot tracking only reacted to changes made after it was armed.
- **Action:** Drain `takeRemoved()` (or skip the first yielded value) before entering the loop, so the join reacts only to removals that happen after it started.
- **Severity:** Medium

### 3.2 Unconsumed navigation sends re-stash with a fresh timestamp and replay on any receiver mount **[verified]** **[REGRESSION e56974aa]**
- **Location:** `Modules/CoreRPG/Navigator/Core/NavigationSend.swift:371-373,416-423,454-478`; callers `Modules/RolePlayGameKit/Model/AppModel.swift:627-631`, `Modules/RolePlayGameKit/Route/WindowRouter.swift:185-189`
- **What:** `replayUndeliveredSends()` runs from the `.task` of every `onNavigationReceive` modifier, whatever type that modifier handles. A replayed send that nobody consumes goes back into the stash through `isolated deinit` with a new `.now` timestamp.
- **Why:** The 5 s lifetime restarts on every replay, so a route that nothing handles can keep circulating and fire much later when an unrelated receiver mounts. The result is a surprise navigation instead of a dropped one.
- **Action:** Keep the original timestamp (or an attempt count) when re-stashing, and replay only entries whose first value matches the mounting receiver's type.
- **Severity:** Medium

### 3.3 `timeControlStatus` observed through Combine `.values` can drop the final state **[verified]** **[REGRESSION 47e68687]**
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:316-321`
- **What:** The KVO publisher bridged with `.values` has demand only while the main-actor loop is waiting. KVO publishers do not buffer, so a change that arrives before the loop resumes is lost. The old `sink` had unlimited demand.
- **Why:** In a quick sequence such as waitingToPlay → playing, `isPlaying` can stay on the intermediate value, and the play/pause UI shows the wrong state.
- **Action:** Treat each element only as a wake-up and read `player.timeControlStatus` live, or add a buffer stage before `.values`.
- **Severity:** Medium

### 3.4 A re-queued older snapshot can overwrite a newer committed edit **[REGRESSION 9b40de42]**
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:33-38,86-95,184-222`
- **What:** `restoreInFlight()` puts rolled-back operations at the front of the queue without checking whether a flush of the same module has already drained a newer operation for that id and is about to apply it.
- **Why:** Suppose module B has edit E1 in flight and E2 queued. A flush drains E2 and waits for `context.perform`. Meanwhile module A's save fails, and the rollback re-queues E1. E2 is applied and saved, and then the next flush applies E1: an older full snapshot committed over E2 and exported to CloudKit. Independent concurrent saves are common (intents, `addNew`, folder-list saves, `FileBookmarkController`, the periodic save).
- **Action:** Give each operation a per-id sequence number and drop a restored operation when a newer one for that id was queued or applied after it, or apply restored operations inside the same flush chain before any newer drain.
- **Severity:** Medium

### 3.5 Audio session category is now set in an unordered Task **[REGRESSION 4d4447e1]**
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerSession.swift:45-51,82-86`; caller `Modules/AudioRPG/Controller/AudioController.swift:257-259,289-304`
- **What:** `setCategory` moved into a fire-and-forget `Task { await configureAndActivate() }`, while `preparePlay` goes on to start playback on the main actor.
- **Why:** The first track after launch can start under the default category (silenced by the ring switch, no long-form routing) before `.playback` is applied.
- **Action:** Keep the `@concurrent` call but store its task and await it before the first `player.play()`.
- **Severity:** Low

### 3.6 Remote-change subscription now starts asynchronously **[REGRESSION 47e68687]**
- **Location:** `Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift:118-124`
- **What:** The Combine `sink` used to subscribe synchronously in `init`. `notifications(named:object:)` now registers only once an unstructured `Task` starts iterating, and no initial history pass runs.
- **Why:** A `NSPersistentStoreRemoteChange` posted right after the store loads (widget or share-extension writes, the first CloudKit import) can be missed, so those changes aren't merged until the next remote change.
- **Action:** Create the async sequence synchronously in `init` before starting the consumer, or schedule one history pass at startup.
- **Severity:** Low

### 3.7 `ContextFlushLedger` is keyed by object address and never torn down **[REGRESSION 9b40de42]**
- **Location:** `Modules/CoreRPG/Persistence/ContextFlushLedger.swift:22-49`
- **What:** Entries and the `NSManagedObjectContextDidSave` observer are keyed by `ObjectIdentifier(context)` and never removed. After a local↔CloudKit store swap, a new context at a reused address finds an existing observer and gets none of its own.
- **Why:** Whether `commitInFlight()` then fires depends on pointer reuse. If it doesn't, `unsavedInserts` is never cleared (remote deletions of those items are ignored) and a later rollback re-queues edits that were already saved.
- **Action:** Remove entries and observers in `CoreDataInitModel.stop()`, or key by a per-context token.
- **Severity:** Low

### 3.8 Cloud-root re-resolution is racy and not followed everywhere **[INCOMPLETE FIX of CODE_AUDIT_18 §3.3]**
- **Location:** `Modules/CoreRPG/App/CloudContainerCache.swift:19-27,35-49`; `Modules/CoreRPG/Import/ExternalImportSourceRegistry.swift:134-140`
- **What:** A resolve that started before `invalidate()` can write the old URL back afterwards. A read between `invalidate()` and the re-resolve blocks on `url(forUbiquityContainerIdentifier:)` on the calling thread. The registry captures `preferredRootUrl` once at init.
- **Why:** A stale container can stay cached after an iCloud identity change, the main thread can still block, and Foundry source indexes keep writing to the old root.
- **Action:** Add a generation counter that the resolver checks before storing, and make the registry resolve its directory lazily.
- **Severity:** Low

### 3.9 `GroupSession.join()` moved onto the main thread **[REGRESSION e56974aa]**
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:396-405`
- **What:** The removed comment said `join()` ran detached specifically to avoid blocking the main thread while the audio session is active (a SessionCore warning). It now runs synchronously on the main actor.
- **Why:** This may show up as a main-thread hang during a SharePlay join. It is plausible but not verified.
- **Action:** Profile a join with the Hangs instrument while audio is active. If it blocks, keep the main-actor ordering but call `join()` from a `@concurrent` helper that takes the session as `sending`.
- **Severity:** Low

### 3.10 `@preconcurrency import GroupActivities` is back on visionOS **[INCOMPLETE FIX of CODE_AUDIT_18 §3.8]**
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+VisionOSTemplate.swift:12` (crossing at `:24`)
- **What:** `4106925d` ("fixed: compile issue visionOS") re-added the attribute that §3.8 removed. The §3.8 status line only checked iOS.
- **Why:** The non-Sendable `SystemCoordinator` crossing is unchecked on the one platform that uses it.
- **Action:** Remove the attribute and fix the hidden diagnostic (keep the coordinator access main-actor isolated), then build visionOS.
- **Severity:** Low

### 3.11 `[weak self]` defeated by `guard let self` before long-lived loops
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:305-307`; `Modules/GameRPG/Root/GameRoot.swift:547-549`; `Modules/GameRPG/Network/ConnectionController.swift:236-238`; `Modules/GameRPG/Browser/BrowserManager.swift:77-79`
- **What:** Each task captures `self` weakly, then binds it strongly before a `for await`/`while` loop, holding the owner for the loop's whole lifetime.
- **Why:** The `isolated deinit` cleanups these types rely on never run unless `reset()`/`stop()`/`cancel()` is called explicitly, so a missed teardown leaks the controller along with its session or connection.
- **Action:** Re-bind `self` weakly inside each iteration, or move the loop body into a function that takes a weak owner.
- **Severity:** Low

### 3.12 3D structural map broadcast can be overtaken, and a hex toggle made while paused is never re-sent **[INCOMPLETE FIX of CODE_AUDIT_18 §5.19]**
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+Broadcast.swift:63-72`; `Modules/GameRPG/Table3D/GameTableModel+ToolBar.swift:66-86`; `Modules/MapRPG/Map/GameToolBar.swift:157-163`
- **What:** The content update and its follow-up map state go out from an unstructured `Task` after an `await`, so synchronous `broadcastMapEdit` calls made in between (a pin drag right after a hex toggle) go out first. While paused, the structural `.generic` update is suppressed, and resuming calls only `sendMapUpdates()` (`.mapState`).
- **Why:** Players receive map states that reference hex entries they don't have yet, which forces the rate-limited full-map repair §5.19 was meant to avoid. Two quick toggles can deliver the older content update last.
- **Action:** Send GM map broadcasts through one ordered chain (cancel-then-replace, like fog renders), mark the structure dirty while paused, and send the content update on resume.
- **Severity:** Low

### 3.13 Ordered LAN sends also serialize encoding, and the chain survives a reset **[REGRESSION 5cb9a929]**
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:55,231-250`
- **What:** Each send waits for the previous send's `encodedOffMain` before starting its own, and `outboundChain` is not cleared in `resetConnections()`.
- **Why:** Small latency-sensitive messages (pointer, pin) wait behind a multi-MB map encode, and a new hosting session's first send waits for the old session's tail.
- **Action:** Encode concurrently but hand frames to connections in sequence order, and clear the chain on reset.
- **Severity:** Low

### 3.14 Player→master path still sends a nil encoding as an empty frame **[INCOMPLETE FIX of CODE_AUDIT_18 §3.15]**
- **Location:** `Modules/GameRPG/Network/ConnectionController.swift:86-92,120-126` (the receiver treats it as EOF at `:272`); caller `Modules/GameRPG/Player/PlayerNetworkController.swift:239-241`
- **What:** Only `MasterNetworkController.sendOrdered` skips a nil encoding. `request`/`response` still pass `content?.encodeData()` straight to `connection.send`.
- **Why:** If a player message fails to encode, a zero-length frame makes the master drop that player as "peer closed".
- **Action:** Skip and log nil encodings inside `ConnectionController` so every path is covered.
- **Severity:** Low

### 3.15 Photo-drop cancellation can miss the `Progress` **[INCOMPLETE FIX of CODE_AUDIT_18 §4.3]**
- **Location:** `Modules/PhotoRPG/Controller/ItemController.swift:54-70`
- **What:** `onCancel` reads `progressBox.progress`, which is assigned only after `loadDataRepresentation` returns, and nothing re-checks `Task.isCancelled` after the assignment.
- **Why:** A cancel that arrives before the assignment is lost, and the load runs to completion.
- **Action:** Store a "cancelled" flag in the box that the assignment honours, or check `Task.isCancelled` right after storing the progress.
- **Severity:** Low

### 3.16 SpaceViewer table placement polls with `Task.sleep` and sets manipulation flags a turn late **[NEW 6a7b5fa0]**
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:247-277,657-664`
- **What:** `placeAboveTableIfNeeded` retries up to 10 times, 100 ms apart. `isManipulating`/`isMovedSinceTablePlacement` are set through `Task { @MainActor in … }` inside handlers that already run on the main actor.
- **Why:** Timing-based synchronization; a grab in the same turn as a placement attempt is not seen by the `!isManipulating` guard, so the object can snap out from under the user's hand.
- **Action:** Wait on a `SceneEvents.Update`, as `waitForFirstRenderedFrame` does, and set the flags directly in the handlers. Move the placement logic into a model (see §9.23).
- **Severity:** Low

### 3.17 Statistics retry re-queues committed events and loses them at session end **[INCOMPLETE FIX of CODE_AUDIT_18 §3.10]**
- **Location:** `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:183-215,232-240`; `Modules/GameRPG/Statistics/Controller/GameStatisticsDataController.swift:146`
- **What:** The whole batch is re-queued when `checkpointSession` fails, even though `recordEvents` already succeeded. No retry is scheduled, and `recordEvents` skips events whose session is already complete.
- **Why:** Events with an empty `deduplicationKey` are inserted twice, and events re-queued by the final flush are dropped without a log.
- **Action:** Re-queue only the step that failed, schedule the retry, and retry before marking the session complete.
- **Severity:** Low

---

## 4. API modernity

### 4.1 Isolation escape hatches that Swift 6.2 features can replace
- **Location:** `Modules/CoreRPG/ItemList/ItemRowTreeModel.swift:52,78`; `Modules/CoreRPG/Navigator/Core/Navigator.swift:349-350`; `Modules/CoreRPG/Persistence/CoreDataChangeObserver.swift:22-25`
- **What:** `@preconcurrency Codable/Equatable/Hashable/EnvironmentKey` conformances sit on `@MainActor` types, and an `@unchecked Sendable` class guards a mutable `observer` with a precondition.
- **Why:** The `@preconcurrency` conformances trade compile-time checks for runtime isolation traps, and the unchecked class depends on a call-once convention.
- **Action:** Use isolated conformances (SE-0470) and back `observer` with a `Mutex`, dropping `@unchecked`.
- **Severity:** Low

### 4.2 NWConnection/NWListener still bridged through DispatchQueues *(still open, CODE_AUDIT_18 §4.5, deferred by decision)*
- **Location:** `Modules/GameRPG/Network/ConnectionController.swift:39`; `Modules/GameRPG/Network/ListenerManager.swift:170`
- **What:** These are the only two remaining `DispatchQueue`s in the code base.
- **Why:** A move to structured Network APIs remains a transport rewrite.
- **Action:** Leave deferred; revisit together with the §9.7/§9.11 network refactors from audit 18.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 A rolled-back external import can still commit its new items, pointing at attachments the rollback already deleted **[verified]** **[REGRESSION 9b40de42]**
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:87-95` (`restoreInFlight`), `:152-156` (`delete(uuid:)`), `:224-242` (`save()` rollback); `Modules/CoreRPG/Import/ExternalImportReviewSession.swift:279,302-318`; `Modules/CoreRPG/Import/ExternalImportReviewSession+Internals.swift:361-379`; `Modules/CoreRPG/Controllable/ItemControllable.swift:279-291`; `Modules/AdventureRPG/Root/AdventureRootModel.swift:309-325`
- **What:** When the import's consolidated save fails, the rollback re-queues every flushed operation, including the import's inserts. The review session's rollback then calls `deleteForExternalImport`, which removes the item from memory and asks Core Data to delete a row that no longer exists, but never removes the re-queued insert.
- **Why:** The session then deletes the new attachment files and runs `consolidatedSave()` again (line 314). That flush applies the re-queued inserts and commits them. The UI reports "import rolled back", yet the items are persisted, exported to CloudKit, reference deleted files, and reappear after relaunch.
- **Action:** Call `removePendingOperations(for:)` for every rolled-back inserted id (inside `deleteForExternalImport` or the rollback loop), or keep import operations out of the re-queue once the session decides to roll back. Add a test that fails the first consolidated save.
- **Severity:** High

### 5.2 "Fix Map Size to Photo" zeroes the map while the photo is loading, and distorts rotated maps **[verified]** **[NEW c9afb6f6]**
- **Location:** `Modules/MapRPG/Map/MapEditController+PhotoSize.swift:15-19` (check), `:33-52` (repair), `:57-64` (`realPhotoSize`); `Modules/MapRPG/Map/RootCanvasMap.swift:35,106` (empty placeholder image); `Modules/MapRPG/Model/MapModel+Geometry.swift:37-53`; `Modules/MapRPG/Map/EditMapToolBar.swift:229-236,314-316`; `Modules/MapRPG/Map/EditMapToolBarButtons.swift:234-250`
- **What:** There are three separate defects:
  - `RootCanvasMap` shows an empty `AKImage()` (size 0×0) while the photo loads, or permanently when the photo file is unavailable. `realPhotoSize` returns that zero size unchanged, so `isMapSizeOutOfSyncWithPhoto` is true and the button appears. Tapping it calls `resetImage(size: .zero)`, which sets the map's width and height to 0: `resetEntryGeometry` bails out on zero, but the canvas size has already been written.
  - The stored map size is already rotated (`rotatedContentSize`), but `realPhotoSize` aspect-matches the *unrotated* photo against it and passes the result back into `resetImage`, which rotates it again. Example: a 90° map stored at 4000×2000 with a 1000×2000 photo becomes a 1000×2000 canvas, scaling x by 1 and y by 0.25, so every room, pin, wall and tile crop is distorted. For any rotation that isn't a multiple of 90° the button never goes away.
  - The doc comment promises `MapCanvasGeometryResolver`'s aspect tolerance, but the check uses exact `!=`, so maps whose logical size legitimately differs from the photo's pixel size show the button too.
- **Why:** One tap on a visible toolbar button corrupts the map geometry. The change is undoable in the editor, but it is saved and broadcast if the GM doesn't notice.
- **Action:** Return "in sync" unless the photo size is finite and positive. Compare and repair in unrotated image space, reuse the resolver's aspect-error helper and tolerance instead of a second copy, and add tests for 0°/90°/45°.
- **Severity:** High

### 5.3 A recurring save error now stalls every module's persistence for the whole session, silently **[REGRESSION 9b40de42]**
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:73-95,224-242`; `Modules/CoreRPG/Persistence/ContextFlushLedger.swift:52-57,70-76`; `Modules/CoreRPG/Controllable/ItemControllable.swift:410-445`
- **What:** Every failed save re-queues all modules' flushed operations in front of the queue, with no attempt count and no way to isolate the operation that keeps failing.
- **Why:** With a persistent error (disk full, store I/O, one invalid object), each autosave re-applies the same operations and fails again, so no module ever commits. Before the fix only the failing batch was lost. Now every edit since the first failure is lost at quit, and nothing tells the user (§5.13).
- **Action:** Cap retries per operation or batch, then quarantine the failing module's operations and surface the error.
- **Severity:** Medium

### 5.4 Writes that go straight into the context are still lost on a rollback **[INCOMPLETE FIX of CODE_AUDIT_18 §5.3]**
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:152-156,274-318`; `Modules/CoreRPG/Controllable/ItemControllable.swift:103-122,128-164`
- **What:** `addNew` (`replace(id:)`), `delete(uuid:)` and `batchReplace` write directly into the shared context. Only queued operations are recorded by `markInFlight`.
- **Why:** If another module's failed save rolls back before the next save, a deletion is undone on disk but not in memory, so the item reappears after relaunch and the deletion never reaches CloudKit. A new item from `addNew` loses its insert, and the next sync-deletion diff removes it from memory.
- **Action:** Route deletes and direct inserts through the pending-operation queue (add a delete operation type), or record them in the ledger.
- **Severity:** Medium

### 5.5 Last-writer-wins merges reject edits from a device whose clock runs more than a day fast, and replicas diverge **[REGRESSION 94f77e43]**
- **Location:** `Modules/CoreRPG/CRDT/LWWRegister.swift:47-49,101-112`; `Modules/CoreRPG/CRDT/WallclockTimestamp.swift:45-63`
- **What:** `isAdmissible` compares the incoming clock against the *merging* device's "now + 1 day", and an inadmissible atom always loses to the local one.
- **Why:** A device with a fast clock has every edit rejected by the others while keeping its own value, so replicas diverge while the skew lasts. Once real time catches up, a re-sent stale atom can overwrite newer edits. The result depends on each replica's local time at merge, which is exactly the non-convergence the fix meant to remove.
- **Action:** Use one deterministic rule that doesn't depend on local time: clamp the clock on the authoring device when writing, and order beyond-skew atoms by (clamped clock, actor id).
- **Severity:** Medium

### 5.6 When the master replies `.failed` to a map repair, the player's repair stays pending forever **[INCOMPLETE FIX of CODE_AUDIT_18 §6.1]**
- **Location:** `Modules/GameRPG/Controller/MasterController+MapMessages.swift:248-253,274-283,311-315`; `Modules/GameRPG/Controller/PlayerController+Map.swift:21`; `Modules/GameRPG/Controller/PlayerControllerModel.swift:848-871`
- **What:** The master now answers `.failed` when a player already has two deferred repairs, or when an export fails. The player ignores map `.failed` responses and never clears `pendingMapRepairs`.
- **Why:** A player who (re)joins with three or more maps needing repair, or who hits one export failure, never sends another request for that generation, because `beginMapRepair` coalesces the identical pending repair. The map stays broken until the GM changes its generation.
- **Action:** On a map `.failed`, supersede the pending repair or schedule a bounded retry, or have the master defer the request instead of refusing it.
- **Severity:** Medium

### 5.7 Paused "Share Map" is bypassed by battle, health and roster rebroadcasts **[verified]** (made visible by 321f8318)
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundController.swift:390-405`; `Modules/GameRPG/Controller/MasterController+MapMessages.swift:179-195`; `Modules/GameRPG/Controller/MasterController+Control.swift:110-120`
- **What:** `321f8318` makes 2D room reveals, focus, pins and pointer honour `isStreaming`. These three master paths still send the full `networkMapUpdate(for:)` as `.mapState` without checking `mapRoot.rootModel.isMapStreaming`, and that payload carries every entry's `isShown`/`focused` and all pins.
- **Why:** The GM pauses sharing and reveals a room privately. The next "Next attacker", "mark dead", player health change or player join leaks the reveal to every player. This breaks the CLAUDE.md rule that only `sendMapUpdates()` bypasses the pause.
- **Action:** While paused, send only the battle-round payload (or a state built from the last-shared snapshot), and add a test that pauses, reveals, then advances the turn.
- **Severity:** Medium

### 5.8 A dead defender is highlighted again on the next turn **[verified]** **[NEW 25a7b71b]**
- **Location:** `Modules/MapRPG/Controller/GameController+Metadata.swift:306-321`; `Modules/MapRPG/Controller/GameController+Battle.swift:278-306`; `Modules/MapRPG/BattleRound/BattleRoundModel+Turns.swift:190-240`
- **What:** `setBattleCombatantDead` clears the dead pin's highlight, but `synchronize(pins:)` only recomputes `defenderIds` for the *active* entry. When another attacker becomes active, `applyActiveBattleHighlights` highlights that entry's stored `defenderIds` without checking `isDead`.
- **Why:** A targets M, B kills M, and when A's turn comes round M is highlighted again and broadcast to every player, which is the behaviour the commit meant to prevent. `nextRound()` can also activate a dead first combatant.
- **Action:** Exclude dead combatants from the highlight set (or remove the dead id from every entry's `defenderIds` in `setBattleCombatantDead`), skip dead attackers when advancing, and add a "kill a defender, then advance" test.
- **Severity:** Medium

### 5.9 Replacing an item's file deletes the old attachment before the new one exists **[verified]**
- **Location:** `Modules/CoreRPG/Controllable/EditControllable.swift:647-686` (delete at `:658-661`, create at `:677-685`); `Modules/CoreRPG/Files/FileUrlDataController.swift:413-438`
- **What:** `resetFile(url:)` deletes the existing file and clears `fileUrl` before `createFileUrl`. On failure it only sets `lastPersistenceError`, which nothing reads. The delete is also fire-and-forget and later calls `removeBookmark(fileId:)` with the same id the new bookmark is saved under.
- **Why:** A failed replacement (iCloud copy error, scope failure, oversized file) permanently removes the old PDF/audio/3D file on every device and leaves the item without a file, silently. The late bookmark removal can also remove the new file's bookmark.
- **Action:** Create the new file first, delete the old one only after that succeeds, and key the bookmark removal to the old path.
- **Severity:** Medium

### 5.10 Folder-entry merge policy differs between Adventure and the nine other modules
- **Location:** `Modules/AdventureRPG/Model/AdventureModel.swift:157-183` (last-write-wins, with a comment that the union "silently resurrected a deletion"); `Modules/CoreRPG/CRDT/FolderEntryMerge.swift:10-39` and its 10 callers (e.g. `Modules/AudioRPG/Model/AudioModel.swift:132`, `Modules/MapRPG/Model/MapModel+Sync.swift:106`)
- **What:** `749b19f0` consolidated the union merge into one helper. Adventure deliberately rejects the union because, without tombstones, it resurrects children deleted offline.
- **Why:** The known resurrection bug is fixed in one module out of ten, and the shared helper doesn't document the trade-off.
- **Action:** Choose one policy (tombstones, or last-write-wins like Adventure), apply it in `FolderEntryMerge`, and document it there.
- **Severity:** Medium

### 5.11 A throwing `fetchIds` discards the whole sync batch **[INCOMPLETE FIX of CODE_AUDIT_18 §5.2]**
- **Location:** `Modules/CoreRPG/Controllable/SyncDataControllable.swift:63-115` (throw at `:78`, comment at `:109-111`)
- **What:** A `fetchIds()` error skips the insert and update loops of the same notification. The comment's "the next notification will retry" is wrong, because later notifications carry only their own ids.
- **Why:** Remote inserts and updates in that batch are missing from memory until relaunch. A later local edit of one of those items queues a stale snapshot that overwrites the remote edit.
- **Action:** Skip only the deletion diff on failure, still apply inserts and updates, and schedule a full reconciliation.
- **Severity:** Low

### 5.12 A full reconciliation drops unsaved local items from the item list **[INCOMPLETE FIX of CODE_AUDIT_18 §5.2]**
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable.swift:447-472` (`resetItems` at `:470`); `Modules/CoreRPG/ItemList/ItemDataModel.swift:70-72`
- **What:** `updates(_:)` keeps unsaved inserts out of `deletedIds`, but then replaces `items` with only the fetched ids.
- **Why:** An item created during launch or a store swap stays in `itemData` but disappears from lists, exports and link lookups until relaunch. Users may recreate it, which produces duplicates.
- **Action:** Append the retained unsaved-insert ids before calling `resetItems`.
- **Severity:** Low

### 5.13 Persistence failures are recorded but never shown, and sibling flushes clear them **[verified]**
- **Location:** `Modules/CoreRPG/ItemList/ItemDataModel.swift:25`; `Modules/CoreRPG/Controllable/ItemControllable.swift:416-443`; `Modules/CoreRPG/Controllable/EditControllable.swift:684`
- **What:** `lastPersistenceError` has no readers in `Modules/` or `Sources/`, and every successful flush resets it to nil.
- **Why:** Every "surface the error" fix from earlier audits is invisible, which is what turns §5.3, §5.4 and §5.9 into silent data loss.
- **Action:** Observe it in a root view or banner, and clear it only after a successful save, not a flush.
- **Severity:** Low (it raises the impact of the Medium items above)

### 5.14 A d3 written by builds `c2d185f2`…`354e3893` no longer decodes **[verified]** **[REGRESSION 354e3893]**
- **Location:** `Modules/DiceRPG/Model/RawDie.swift:167-201`
- **What:** `WireShape` has no `three` case, so the synthesized `{"three":{}}` form that builds wrote between 2026-09-22 and 2026-09-26 throws on decode.
- **Why:** Dev/TestFlight devices that saved or exported a d3 in that window fail to decode those dice sets or characters, via CloudKit rows or LAN/SharePlay payloads.
- **Action:** Accept a legacy `three` key on decode and keep writing `.number(3)`.
- **Severity:** Low

### 5.15 The dice reorder comparator uses the first die's maximum for the second die **[verified]**
- **Location:** `Modules/DiceRPG/Controller/GameController.swift:564-567`
- **What:** The second reroll branch computes the value from `$0.die.max` instead of `$1.die.max`.
- **Why:** With mixed-sided dice and a `maxDiceValue` reroll option, results sort wrongly and the comparator is inconsistent, which affects the reordered dice and percent-dice sums built from them.
- **Action:** Use the second element.
- **Severity:** Low

### 5.16 "Open in Window" is shown on iPhones that can't open windows **[NEW 5704e4c3]**
- **Location:** `Modules/CoreRPG/Model/OpenFileWindowModel.swift:96-108`
- **What:** The iPad-idiom check was replaced by `horizontalSizeClass == .regular`.
- **Why:** Plus and Pro Max iPhones in landscape show the button, but `openWindow` does nothing and the scene state is left at `.opening`. An iPad in compact Split View loses the button.
- **Action:** Gate on `supportsMultipleWindows`, as `AltOpenWindowButton` already does.
- **Severity:** Low

### 5.17 Each 2D↔3D toggle builds a fresh table model, which resets the toolbar state **[NEW ed476284]**
- **Location:** `Modules/GameRPG/Table3D/GameTableView+PlatformFlat.swift:70-101`; `Modules/GameRPG/Table3D/GameTableModel.swift:88-96`
- **What:** With the retained model gone, every switch to 3D starts at `displayMode = .master`, `lastPinScale = 1`, `lastHexScale = 0`, `lastIsHexMap = false`.
- **Why:** The GM's player/reader preview is lost on every toggle, and `canReshare` turns true for any map with a non-default pin scale or a hex grid, so an unnecessary reshare prompt appears.
- **Action:** Seed the new model's display mode and reshare baseline from the map root's current values.
- **Severity:** Low

### 5.18 The 3D fog tile lattice drifts from the 2D lattice **[NEW a9cd8411]**
- **Location:** `Modules/GameRPG/Table3D/GameBoard.swift:365-397`
- **What:** The tile's pixel rect is snapped outward with `.integral`, and the snapped size becomes the repeat period. 2D repeats at the exact tile width and falls back to solid fog above 4,096 tiles per room; 3D has no such cap.
- **Why:** On large maps rendered to the 2048 texture, the 3D pattern slides against the 2D one after a few repeats, tiles carry slivers of neighbouring pixels (seams), and tiny tiles show tiled fog in 3D but solid fog in 2D.
- **Action:** Keep the unsnapped period (draw the crop into the exact tile rect) and mirror the 2D tile-count fallback.
- **Severity:** Low

---

## 6. Security

### 6.1 The remote-URL check accepts the expanded IPv6 loopback address and leading-zero IPv4 **[verified]** **[INCOMPLETE FIX of CODE_AUDIT_18 §6.5]**
- **Location:** `Modules/CoreRPG/Files/FileUrl.swift:199-238` (IPv6 at `:209-215`, dotted quad at `:216-223`); used at `:162` and by `GuardedRemoteDownload` for redirects
- **What:** The IPv6 branch compares string prefixes, so `[0:0:0:0:0:0:0:1]` or `[0::1]` counts as public. The dotted-quad branch parses `0177.0.0.1` as decimal 177.0.0.1.
- **Why:** A peer-supplied or imported `.url` FileUrl passes sanitisation and `ensureRemoteCache` fetches it, which is SSRF against services on the device or LAN. The expanded IPv6 form is definitely loopback. Whether the resolver treats `0177` as octal (as `inet_aton` does, and as the code already assumes for `127.1`) is not confirmed.
- **Action:** Parse literals with Network's `IPv6Address`/`IPv4Address` and classify the parsed bytes, and treat any label with a leading `0` as numeric.
- **Severity:** Medium

### 6.2 The share extension still downloads remote images uncapped and without redirect checks **[INCOMPLETE FIX of CODE_AUDIT_18 §6.4]**
- **Location:** `Sources/RPGShare/ItemProviderImporter.swift:154-164`
- **What:** `imageData(from:)` still uses `URLSession.shared.download(from:)`. Only the text path (`:253`) moved to `GuardedRemoteDownload`.
- **Why:** A shared web URL can stream an unbounded body to the extension's disk before the 256 MB size check runs, and redirects are not validated.
- **Action:** Use `GuardedRemoteDownload` with `maximumSourceFileByteSize` here too.
- **Severity:** Low

---

## 7. Performance

### 7.1 Picking or duplicating a file reads the whole file into memory
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:362-373`; `Modules/CoreRPG/Files/FileManager+Coordination.swift:57-63`; `Modules/CoreRPG/Controllable/EditControllable.swift:512-517`
- **What:** `createFileUrl` hashes the picked file via `Data(contentsOf:)`, and duplication loads the whole file. Neither path has a size cap.
- **Why:** Attaching or duplicating a large audio, USDZ or PDF file spikes memory and can get the app jetsammed on iOS or visionOS. The duplicate path also swallows failures with `try?`, so the copy silently ends up without a file.
- **Action:** Hash in a streamed loop (chunked `FileHandle` + incremental SHA-256), copy file-to-file for duplicates, and report failures.
- **Severity:** Medium

### 7.2 Each player fog render snapshots the whole board texture to crop one tile **[NEW a9cd8411]**
- **Location:** `Modules/GameRPG/Table3D/GameBoard.swift:292-296,365-397` (`makeImage()` at `:387`)
- **What:** The whole board context is snapshotted just to crop the tile, and the cropped `CGImage` keeps the full backing store alive through the render.
- **Why:** Every fog re-render allocates an extra full-texture copy (~16 MB at 2048², ~64 MB at 4096²), causing memory spikes and hitches during frequent map syncs.
- **Action:** Crop from the source photo `CGImage`, mapped to canvas space, instead.
- **Severity:** Low

### 7.3 Audio temp copies pile up **[REGRESSION 4d4447e1]**
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:192-194,201-203,212-216`
- **What:** Each load writes a uniquely named temp file. A load that fails after the copy, and every copy still present at exit, is never removed. The old stable names overwrote each other.
- **Why:** Temp storage grows with every playlist load until the OS purges it.
- **Action:** Remove the temp file when loading fails, and clear an app-specific temp subfolder at launch or game end.
- **Severity:** Low

---

## 8. SwiftUI / UI

The rule sweep against CLAUDE.md is clean: no `foregroundColor`, `tabItem`, one-parameter `onChange`, `Task.sleep(nanoseconds:)`, `UIScreen.main`, `NavigationView` (the matches are the Navigator library's own type names), `String(format:)`, legacy `Formatter`s, `replacingOccurrences`, `showsIndicators: false`, `ScrollViewReader` or `Array(x.enumerated())`. The one `.cornerRadius` is a Charts `SectorMark` modifier, which is correct. The one `onTapGesture` uses `count: 2`, which the rule allows. The audit-18 §8 fixes (44 pt hit shapes, injected SharePlay eligibility, `@ScaledMetric` toolbar icons, occurrence-keyed `ForEach`, lazily built table-generation model) were reviewed and look correct.

### 8.1 Player report row ignores `isShareable` and draws over the content **[NEW a9cd8411]**
- **Location:** `Modules/CoreRPG/LGViews/GameShareView.swift:32-36,90-97`
- **What:** The report row is an unpadded `.overlay(alignment: .topTrailing)` and is shown whenever statuses exist, even when `isShareable == false`.
- **Why:** A photo embedded in a Map (whose share button `b0ebf6db` hides) still shows player names if it was shared elsewhere. The caption also draws on top of the photo or text with no background, which hurts legibility and contrast.
- **Action:** Hide the row when `!isShareable`, and give it a background or reserved space.
- **Severity:** Low

### 8.2 "Fix Map Size" toolbar button: icon-only label and an always-present `ToolbarItem` **[NEW c9afb6f6]**
- **Location:** `Modules/MapRPG/Map/EditMapToolBarButtons.swift:234-250`; `Modules/MapRPG/Map/EditMapToolBar.swift:229-236`
- **What:** The label is an `Image` with `.accessibilityLabel`, rather than the `Button(_:systemImage:action:)` form CLAUDE.md requires. The `ToolbarItem` is always declared, and its content is empty when the button is hidden.
- **Why:** There is no visible text for label-style toolbars or the macOS customisation sheet, and an empty bottom-bar item can leave a spacing gap in the Liquid Glass toolbar group.
- **Action:** Use the titled-button form, and declare the `ToolbarItem` conditionally.
- **Severity:** Low

### 8.3 `LinkHighlightTextView.plainText` resolves its runtime key without `bundle: .module` **[NEW f0b463b1]**
- **Location:** `Modules/CoreRPG/LinkRenderer/LinkHighlightTextView.swift:48-62`
- **What:** The stack-overflow fix builds one flat `LocalizedStringKey` from N interpolated `Text`s and passes it to `Text(_:)` without a bundle, so SwiftUI looks up a synthetic `%@%@…` key in the main bundle's tables.
- **Why:** The code is correct today (the key never exists, so it falls through), but it breaks the module-bundle convention and does an extra table lookup on every re-render of long rule texts.
- **Action:** Pass `bundle: .module` (or use a verbatim concatenation path), and keep the new flat structure.
- **Severity:** Low

### 8.4 `GameSharePlayButton`'s eligible branch is unreachable
- **Location:** `Modules/GameRPG/SetupViews/SharePlayButton.swift:30-40,77-89`
- **What:** The wrapper hides the button (opacity 0, no hit testing) exactly when `canActivateSharePlay` is true, so the `activity.activate()` branch inside `SharePlayButton` never runs from this entry point.
- **Why:** Dead UI logic that suggests a behaviour the setup screen doesn't have.
- **Action:** Decide whether the setup screen should start SharePlay directly when eligible. If not, drop the branch and pass only the ineligible configuration.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

The general sweep is clean: no `#if false`, no TODO/FIXME/HACK/`#warning`, no `print`/`debugPrint`/`dump`/`NSLog` outside `#if DEBUG`, no commented-out code, and no pbxproj references to missing files. The `80ee1fdd` renames changed no Codable or persisted keys.

### 9.1 Orphaned helpers and empty extensions left by the member removal **[INCOMPLETE FIX of CODE_AUDIT_18 §9.3, f8ee0775]**
- **Location:** Empty extensions: `Modules/CoreRPG/Buttons/BorderLessTVButtonStyleViewModifier.swift:29-30`, `Modules/CoreRPG/ItemList/ItemListActions.swift:5-6`, `Modules/CoreRPG/EntryEditor/EntryEditorHeaderView.swift:108-109`, `Modules/CoreRPG/Sheet/SheetModel.swift:180-181`, `Modules/MapRPG/Map/ChooseMapPinsButton.swift:70-74`, `Modules/CoreRPG/Platform/GlasseffectAll.swift` (empty file). Orphaned helpers: `SwitchTVToggleStyleViewModifier` (`BorderLessTVButtonStyleViewModifier.swift:32-41`), `AddNewTypeValueKey` (`ItemListActions.swift:8-10`), `TextContentTypeAll` and its modifier (`Modules/CoreRPG/Platform/TextFieldAll.swift:12-14,51-76`), `LinkReplaceController.linkDetailModels(for:)` (`Modules/CoreRPG/Links/LinkReplaceController.swift:142-159`).
- **What:** Removing the callers left their enclosing extensions empty and orphaned the helpers they used. `git grep -w` finds only the declarations.
- **Why:** About 70 dead lines, plus a doc comment that describes an API which no longer exists.
- **Action:** Delete them.
- **Severity:** Low

### 9.2 Snapshot-based CoreDataController batch/fetch APIs have no callers **[INCOMPLETE FIX of CODE_AUDIT_18 §9.4]**
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift:286-318` (`batchReplace(snapshots:…)`), `:369-391` (`batchExists`), `:471-475` (`fetch(uuid:)`); stale doc at `:182`
- **What:** §9.4 kept these as "the snapshot twins that are used", but none of them has a caller.
- **Why:** `fetch(uuid:)` returns a non-Sendable `NSManagedObject` from an async context, which is the hazard §9.4 set out to remove.
- **Action:** Delete all three and update the doc comment.
- **Severity:** Low

### 9.3 Leftover `WeatherEntityPdfRenderingError` **[INCOMPLETE FIX of CODE_AUDIT_18 §9.14]**
- **Location:** `Modules/WeatherRPG/Intent/WeatherEntity.swift:56-58`
- **What:** The type survived `e9d18da0`, which moved PDF rendering into `EntitySummaryExport`.
- **Why:** A dead type with a misleading doc comment.
- **Action:** Delete it.
- **Severity:** Low

### 9.4 The shared plain-text export dropped the German and Thai translations **[REGRESSION e9d18da0]**
- **Location:** `Modules/CoreRPG/Intent/EntitySummaryExport.swift:41-48`; orphaned key `Modules/TableRPG/Resources/Localizable.xcstrings:695`
- **What:** Table and Weather used localized "Name"/"Description" labels. The shared `plainText` hard-codes English.
- **Why:** The Shortcuts/share text export became English-only in de and th.
- **Action:** Localize the labels in CoreRPG's catalog, carry over the existing translations, and drop the stale TableRPG key.
- **Severity:** Low

### 9.5 Stale String Catalog keys
- **Location:** "Extract Information" in `Modules/AdventureRPG/Resources/Localizable.xcstrings:516`, `Modules/MapRPG/Resources/Localizable.xcstrings:1010`, `Modules/PdfRPG/Resources/Localizable.xcstrings:669`, `Modules/TableRPG/Resources/Localizable.xcstrings:626`. Overall 202 keys are marked stale, and 133 of them match no Swift literal: GeneratorRPG 54, GameRPG 30, CoreRPG 16, MapRPG 12, DiceRPG 7, CharacterRPG 4, RolePlayGameKit 3, TableRPG 3. Also `Resources/InfoPlist.xcstrings:526,574` (microphone and speech usage descriptions with no remaining API use).
- **What:** Translations for strings that no code produces.
- **Why:** Ongoing translator cost and noise.
- **Action:** Check the 133 against runtime-built keys, then prune in Xcode's catalog editor.
- **Severity:** Low

### 9.6 `BundleIds` misses a fifth identifier spelling **[INCOMPLETE FIX of CODE_AUDIT_18 §9.17]**
- **Location:** `Modules/CoreRPG/App/UTType+RPGDocuments.swift:7,10`; `Modules/CoreRPG/App/UserActivity.swift:10`; doc at `Modules/CoreRPG/App/BundleIds.swift:5-9`
- **What:** The exported document UTTypes and the user-activity type are still `de.AndreTrettin.GameMaster.*` literals, which `BundleIdsTests` doesn't pin, and the doc claims there are four spellings.
- **Why:** These are persisted, registered identifiers: an accidental edit breaks document opening and Handoff.
- **Action:** Add a legacy-product prefix (or at least pin the three literals in tests) and fix the doc.
- **Severity:** Low

### 9.7 Byte-size literals not moved to `ByteUnit` **[INCOMPLETE FIX of CODE_AUDIT_18 §9.17]**
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:841,865`; `Modules/GameRPG/Network/GameRelayAdmission.swift:43`; `Modules/GameRPG/Network/SharePlayPlayerJournalAdmission.swift:140`; `Sources/RPGShare/ItemProviderImporter.swift:196,198,202`
- **What:** Seven limits are still written as `N * 1_024 * 1_024`.
- **Why:** The two styles are still mixed after the fix.
- **Action:** Express them with `ByteUnit.mebibyte`.
- **Severity:** Low

### 9.8 Storage keys still hand-written, and the visionOS route key contradicts the documented contract **[INCOMPLETE FIX of CODE_AUDIT_18 §9.17]**
- **Location:** `Modules/RolePlayGameKit/View/SplitVisionNavigation.swift:96` (`"GameRoute"`); `Modules/RolePlayGameKit/View/ExtendedSplitBar.swift:43`, `ExtendedTabBar.swift:67` (`"ExtendedTabRoute"` twice); `Modules/GameRPG/SetupViews/SelectedMasterView.swift:10`, `SelectedPlayerView.swift:11`; `Modules/GameRPG/Model/GameLimits.swift:42-45`
- **What:** `RootRoute.sceneStorageKey` says every root layout uses it, but visionOS stores under `"GameRoute"`. Other keys are duplicated literals.
- **Why:** A typo in a duplicated literal silently loses persisted UI state.
- **Action:** Centralise the remaining keys and document the visionOS key as intentional. Do not rename it, because existing state is stored under it.
- **Severity:** Low

### 9.9 Misspelled symbols and duplicate class names remain **[INCOMPLETE FIX of CODE_AUDIT_18 §9.16]**
- **Location:** `hightlight` (`Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift:259`, 8 hits), `repariedText` (same file `:70`), `repairCharacterContrains` (`Modules/CharacterRPG/Controller/EditController+Repair.swift:11`, 15 hits), `networtData` (`Modules/GameRPG/Controller/MasterController+Messaging.swift:198`, 24 hits), `listnerBuilder` (`Modules/GameRPG/Master/MasterNetworkController.swift:32`), `destiantionItemId` (`Modules/CoreRPG/Model/EditorLinkModel.swift:141`), `displyConfigOrNew` (`Modules/MapRPG/Model/DataModel+Extensions.swift:33`), `uppperBound` (`Modules/CoreRPG/Editors/TextIntEditor.swift:12`), `extened` (`Modules/RolePlayGameKit/View/ExtendedTabBar.swift:43`), `feebackToAdd` (`Modules/SpaceRPG/Record/AppDataModel.swift:376`), `onboardingStateTodetailTextMap` (`Modules/SpaceRPG/Record/OnboardingTutorialView.swift:147`); `var SamplingStrategyConfiguration: SamplingStrategyConfiguration` (`Modules/GeneratorRPG/Controller/GeneratorController.swift:83`, `AdventureGeneratorController.swift:68`); `GameSetup`/`GameRenderer` declared twice under `#if` (`GamePortableSetup.swift:12`/`GameSetup.swift:14`, `GamePortableRenderer.swift:18`/`GameRenderer.swift:12`).
- **What:** The rename pass missed these. None of them is a Codable key.
- **Why:** Search becomes unreliable, and two classes sharing one name make cross-platform edits error-prone.
- **Action:** One more mechanical rename commit; name the iOS/macOS types `PortableGameSetup`/`PortableGameRenderer`.
- **Severity:** Low

### 9.10 New `URL`-suffixed names added by the remediation itself **[REGRESSION c2e4aff9]**
- **Location:** `Modules/CoreRPG/Files/FileUrl.swift:199,240`; `Modules/CoreRPG/Files/FileUrlDataController.swift:625`; `Modules/CoreRPG/Files/GuardedRemoteDownload.swift:49`; `Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:100`
- **What:** `isPublicRemoteFileURL`, `isSupportedRemoteFileURL`, `temporaryURL` and `requestedURL` break the project's `Url` convention.
- **Why:** This is new drift on top of the deferred mass rename.
- **Action:** Rename these now; they are small and not persisted.
- **Severity:** Low

### 9.11 Dead 3D-table toolbar actions and a duplicated pointer-centring routine
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+ToolBar.swift:111-156` (`setAllRoomsShown`, `togglePointerVisibility`, `movePointerToMapCenter`, `addMonstersAtMapCenter`); `Modules/GameRPG/Table3D/GameTableModel+Viewport.swift:26-34` (`syncAfterExternalEdit`); `Modules/MapRPG/Controller/GameController.swift:113`, `GameController+Pins.swift:309`; duplicate inline logic `Modules/MapRPG/Map/GameToolBar.swift:135-141,216-222`
- **What:** None of these has a production caller. Three are exercised only by `Tests/GameRPGTests/GameTableControlTests.swift`.
- **Why:** The tests exercise code the UI never runs, so a bug in the real `GameToolBar` path would go uncaught.
- **Action:** Delete the dead methods, or route `GameToolBar` through one shared routine and point the tests at it.
- **Severity:** Low

### 9.12 Share-view and join-code leftovers **[NEW a9cd8411]**
- **Location:** `Modules/CoreRPG/LGViews/GameShareView.swift:113-126` (unused `playerReportAttributedString(status:)`), `:135-138` (its logic copied inline), `:163` (unused `Identifiable`); `Modules/GameRPG/SetupViews/GameJoinCodeField.swift:22-29` (single-child `VStack`)
- **What:** An unused helper duplicates the list builder's body; the stack lost its other child when the title was removed. The commit also left 13 whitespace-only lines.
- **Why:** Dead and duplicated code in a view that is still changing.
- **Action:** Have the list builder call the per-status helper, drop the conformance and the stack, and strip the whitespace.
- **Severity:** Low

### 9.13 Map-editor canvas resolution and diagnostic logging duplicated **[NEW c9afb6f6]**
- **Location:** `Modules/MapRPG/Map/MapEditorSession.swift:138-149`; `Modules/MapRPG/Map/MapEditorSession+Viewport.swift:34-45`
- **What:** Identical `MapCanvasGeometryResolver.resolve` calls, each followed by a six-line debug log that was added to chase the macOS 2× bug (fixed at the source in `7cbd7d86`).
- **Why:** Leftover debugging code, copied twice.
- **Action:** Extract one canvas-size helper, and keep at most one log.
- **Severity:** Low

### 9.14 `GameTableModel` session wiring written twice
- **Location:** `Modules/GameRPG/Table3D/GameTableView+PlatformFlat.swift:89-93`; `Modules/GameRPG/Table3D/GameTableView+VisionOS.swift:443-447`
- **What:** The same `networkActions`/`isGameMaster`/`playerPinId` setup is copied into both tables.
- **Why:** A change to who counts as GM or which pin is the player's must be made twice. CLAUDE.md asks for shared decisions on the model.
- **Action:** Add a `configureSession(from:)` method on `GameTableModel`.
- **Severity:** Low

### 9.15 ScenesManager event suppression, generic immersive toggle and `ModuleRouting` are dead
- **Location:** `Modules/CoreRPG/ScenesManager/ScenesManager.swift:186-286,385-416`; `Modules/CoreRPG/ScenesManager/SceneId.swift:45-51`; `Modules/CoreRPG/ScenesManager/ModuleRouting.swift:19-31`
- **What:** Nothing suppresses events, so `areEventsSuppressed` (read at `SceneTrackerModifier.swift:69,76`) always returns false. `toggleImmersiveSpace` opens an `"ImmersiveSpace"` id that no scene declares.
- **Why:** About 140 dead lines in a 570-line file, including a toggle that would fail if anyone called it.
- **Action:** Delete them.
- **Severity:** Low

### 9.16 Generation options and token tracking copied between the two generator controllers
- **Location:** `Modules/GeneratorRPG/Controller/AdventureGeneratorController.swift:66-123`; `Modules/GeneratorRPG/Controller/GeneratorController.swift:82-138`
- **What:** About 56 identical lines covering sampling strategy, seed, guardrails, token usage, `syncConversationState` and `fetchContextSize`. This is the largest duplicated block found.
- **Why:** Fixes already had to be made twice (CODE_AUDIT_18 §5.20).
- **Action:** Extract a shared conversation/options state type owned by both controllers.
- **Severity:** Medium

### 9.17 JSON coder configurations repeated, including the Foundry depth guard
- **Location:** Sorted-keys encoders: `Modules/CoreRPG/Model/StableVersionDigest.swift:19-20`, `Modules/MapRPG/Model/MapUpdatePayload.swift:50-51`, `Modules/MapRPG/Model/MapWallModel.swift:149-153`. ISO-8601 + sorted keys: `Modules/CoreRPG/Foundry/FoundryImportArchive.swift:126-128,218-219`, `Modules/CoreRPG/Import/ExternalImportSourceRegistry.swift:259-260,269-271`. Depth-limited decoders: `Modules/CoreRPG/Foundry/FoundryPackageResolution.swift:64-70`, `Modules/CoreRPG/Foundry/UniversalVTTReader.swift:281-289`, `FoundryImportArchive.swift:224-225`.
- **What:** The same configurations are written 3, 2 and 3 times.
- **Why:** The depth guard protects against stack-overflow crashes on hostile input; if one copy drifts, that path is exposed again.
- **Action:** Add the shared configurations to `JSONCoding`, and have `UniversalVTTReader` call `FoundryJSONDecoding.decodeSource`.
- **Severity:** Low

### 9.18 `ReferenceScanner` parse functions are four near-copies
- **Location:** `Modules/CoreRPG/Links/ReferenceScanner.swift:32-109`
- **What:** The four `parseUrls…` functions differ only in regex groups and stride, and one of them doesn't log parse failures.
- **Why:** A link-grammar change needs four edits, and one copy already behaves differently.
- **Action:** Use one parser, or one Swift `Regex` with optional groups.
- **Severity:** Low

### 9.19 Game-master and player game views are near-identical pairs
- **Location:** `Modules/GameRPG/GameViews/TabSecondGameView.swift` / `TabPlayerSecondGameView.swift`; `GameElapsedTimerText.swift` / `IOSGameElapsedTimerText.swift`; `MasterGameScreen.swift` / `PlayerGameScreen.swift`; `TabGameView.swift` / `TabPlayerGameView.swift`
- **What:** The variants are copied files rather than one parameterised view.
- **Why:** Layout fixes must be applied to each pair.
- **Action:** Merge the second-tab and timer pairs first, then extract shared scaffolding from the screen pairs.
- **Severity:** Low

### 9.20 `recoverFromError` copied between the two persistence controllers
- **Location:** `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:139-158`; `Modules/CoreRPG/Persistence/CoreDataPersistenceController.swift:209-228`
- **What:** The two copies are identical, and `setupContext` shares its first ~15 lines.
- **Why:** Store recovery can diverge between the iCloud and local stores.
- **Action:** Move both into a shared helper.
- **Severity:** Low

### 9.21 Tip eligibility flags duplicate the TipKit rules and are used only by tests
- **Location:** `Modules/CoreRPG/Tips/MasterRPGTips.swift:48-78`; rules in `MasterRPGTips+Onboarding.swift:38-123`, `+GameSetup.swift:26-112`, `+FeatureDiscovery.swift:29-110`
- **What:** Eight `shouldShow*` properties hand-copy the `#Rule` conditions and appear only in `Tests/CoreRPGTests/MasterRPGTipEligibilityTests.swift`.
- **Why:** The tests check a copy of the rules, so a change to a real rule still passes.
- **Action:** Derive the rules from shared predicates, or delete the copies and test the rule inputs.
- **Severity:** Low

### 9.22 Other members with a single occurrence
- **Location:** `Modules/CoreRPG/Sheet/SheetModel.swift:70,72`; `Modules/DiceRPG/Model/DiceModel.swift:380-382`; `Modules/CoreRPG/Files/CloudDocumentController.swift:52-54`; `Modules/CoreRPG/ItemList/ItemRowTreeModel.swift:13-14`; `Modules/GeneratorRPG/BasicAI/Model/PdfSummaryAnalysis.swift:69-72`; `Sources/MasterRPG/iOS/iOSSceneDelegate.swift:13`; `Modules/CoreRPG/Fake/TestFixtures.swift:21`
- **What:** `git grep -w` returns only the declaration for each.
- **Why:** Leftover API surface.
- **Action:** Delete them in one pass and let the compiler confirm.
- **Severity:** Low

### 9.23 Oversized files (>500 LOC) not already deferred, and a deferred file that grew
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift` (694), `Modules/CoreRPG/FileViews/SingleReviewModels.swift` (665), `Modules/CoreRPG/Sheet/SheetEntryView.swift` (636), `Modules/DiceRPG/Controller/GameController.swift` (634), `Modules/CoreRPG/Import/ExternalImportSourceRegistry.swift` (633), `Modules/MapRPG/Controller/GameController+Battle.swift` (603), `Modules/CoreRPG/Controllable/ItemControllable.swift` (601), `Modules/CoreRPG/Views/ViewportGeometry.swift` (588), `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift` (579), `Modules/CoreRPG/ScenesManager/ScenesManager.swift` (570; §9.15 removes ~140). The deferred `Modules/SpaceRPG/Space/SpaceViewer.swift` grew from 1,119 to 1,205 LOC with `6a7b5fa0`'s placement logic (`:241-302`).
- **What:** None of these has a split planned, and new logic keeps landing in a view.
- **Why:** Harder review and testing. The SpaceViewer growth goes against CLAUDE.md's "view logic into models".
- **Action:** Split along the existing MARK/extension boundaries; move SpaceViewer's table placement into a model first.
- **Severity:** Low

### 9.24 tvOS and macOS targets carry visionOS-only usage descriptions **[NEW c9afb6f6]**
- **Location:** `MasterRPG.xcodeproj/project.pbxproj:7336,7342,7410,7416` (MasterMac), `:7607,7613,7658,7664` (MasterTV); `Resources/InfoTVPlist.xcstrings:182,278`
- **What:** `NSHandsTrackingUsageDescription` and `NSWorldSensingUsageDescription` were moved into build settings rather than dropped. Their texts disagree ("roll dice" on tvOS, "resize the table" elsewhere), and nothing uses world sensing.
- **Why:** Dead configuration and a misleading purpose string for App Review.
- **Action:** Remove both keys from MasterMac and MasterTV, and drop world sensing everywhere unless it is planned.
- **Severity:** Low

### 9.25 Types and files in the wrong place *(partly still open, CODE_AUDIT_18 §9.16)*
- **Location:** `Modules/GameRPG/Table3D/StaleGestureTracker.swift:34-57` (hosts `replaceTask` and `RoomActionCoordinator`; `staleGestureTimeout` lives on the coordinator but only the tracker uses it); `Modules/CoreRPG/Model/OpenFileWindowModel.swift:52,75` (view types in Model/); `Modules/CoreRPG/Persistence/CloudKitSyncStatusView.swift`; `autoFocusDelay` declared twice (`Modules/CoreRPG/EntryEditor/EntryEditorContent.swift:10`, `Modules/CoreRPG/LGViews/ItemHeaderEditorView.swift:8`)
- **What:** Types and constants live in files and folders that don't match their role.
- **Why:** They are hard to find, which invites more duplicates.
- **Action:** Move them as described and share one `autoFocusDelay`.
- **Severity:** Low

### 9.26 Test gaps in the new and fixed code
- **Location:** fixed sleeps as synchronisation: `Tests/CharacterRPGTests/LinkControllerTests.swift:491-602` (9 sites, new in `3157aed1`), `Tests/GameRPGTests/SearchModelTests.swift:47-145` (8), 31 sites in 15 files in total; symmetric tile fixture: `Tests/GameRPGTests/BoardTextureRendererTests.swift:69-94`; no test references `fixMapSizeToPhoto`/`realPhotoSize` (§5.2) or the import-rollback re-save (§5.1)
- **What:** Tests wait 100 ms for observation-driven updates. The tile test uses a uniformly coloured quadrant, so a flipped or phase-shifted tile gives the same pixels. The two High findings have no coverage.
- **Why:** Flaky under load or TSan (consistent with the known GameRPGTests TSan batch crashes), and the new tiling and map-repair logic is effectively untested.
- **Action:** Await conditions (`confirmation`, an `Observations` sequence with a timeout) instead of sleeping, use an asymmetric tile and a non-multiple room size, and add regression tests for §5.1, §5.2 and §5.8.
- **Severity:** Low

### 9.27 Comment contradicts the `isShareable` source **[NEW b0ebf6db]**
- **Location:** `Modules/CoreRPG/Sheet/SheetEntryView.swift:288-292`
- **What:** The comment says `entryModel.source.typeId` decides shareability, but the code passes `inlineSheet.isShareable`, which only MapRPG's `createPhotoInline` sets.
- **Why:** A future edit might "fix" the code to match the comment.
- **Action:** Correct the comment.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Make persistence failures visible before hardening them further.** §5.3, §5.4 and §5.9 are silent because `lastPersistenceError` has no reader (§5.13). A root-level banner that observes it (cleared only on a successful save) turns each future persistence bug from silent loss into a visible, reportable failure.
2. **Give pending operations an identity and an order.** §3.4, §5.1, §5.3 and §5.4 all stem from re-queueing snapshots without knowing whether a newer write or a deliberate removal superseded them. A per-id sequence number plus a delete operation type in the same queue would let restore, remove and flush reason about the same facts.
3. **Route every GM map send through one gate.** CLAUDE.md already states the rule (only `sendMapUpdates()` bypasses pause). §5.7 and §3.12 show that battle, health, roster and structural sends each build their own `.mapState`. Have one master-side function own "send map state / content for map X", honour `isMapStreaming`, and keep ordering.
4. **Use deterministic rules for anything replicated.** §5.5 (skew rejection that depends on local time) and §5.10 (union vs last-write-wins folder merges) are both cases where two devices can disagree forever. Prefer rules that depend only on the data (clamped clock plus actor id; tombstones).
5. **For each new async sequence, check its first element and its subscription time.** §3.1 (`Observations` yields the current value), §3.3 (`.values` has no buffer) and §3.6 (subscription starts late) all come from the same audit-18 migration away from Combine sinks and `withObservationTracking`. Check each converted site for all three behaviours.
6. **Parse, don't pattern-match, untrusted identifiers.** §6.1 is the third round of string-matching fixes to the private-host check. Use Network's address types for IP literals, as the platform already does.
7. **Add a regression test with every High fix.** Neither High finding in this audit has test coverage (§9.26), and several audit-18 fixes regressed within a day. A failing test first would have caught §5.1 and §5.14.

---

## 11. What was NOT audited

- `Docu/`, `Snapshots/`, `Integrations/` (third-party), `.git`, `.build`, `DerivedData`.
- Runtime behaviour: no tests, UI tests, Instruments traces or on-device runs. These claims come from reading code and should be confirmed on a device: whether the resolver treats leading-zero IPv4 as octal (§6.1), the SharePlay join hang (§3.9), and the Liquid Glass toolbar gap from an empty item (§8.2).
- Algorithmic correctness of the Foundry/UniversalVTT/LevelDB parsers, CRDT types beyond the clock rules, and RealityKit/TabletopKit scene maths beyond the new tiling, gesture and placement code.
- The 24 findings in `Docu/CODE_AUDIT_Network.md`: only audit-18 network fixes and new code were re-checked.
- Build settings and scheme configuration, apart from the usage-description keys in §9.24; the `RPGTabletopGameContent` SPM package internals.
- `Tests/`: quick scan only (§9.26).
- StoreKit configuration and App Store Connect parity.
- Localization wording; only stale and missing keys were counted (§9.4, §9.5).
- Localization and asset content of the 344 dice image sets.

---

## 12. Verification

Spot-check pattern: in Xcode, command-click the `path:line` reference in the report; it should land on the cited line. I re-read the following myself after the agents reported them (or found them myself).

- **§5.1** — `Modules/CoreRPG/Persistence/CoreDataController.swift` lines 87-95 (`restoreInFlight` → `restorePendingOperations` inserts at the front), 224-242 (`save()` catch → `rollbackRestoringFlushedOperations`), 152-156 (`delete(uuid:)` only calls `deleteCoreData(id:save:false)`, whose `guard let object = fetchCoreData(uuid:)` at line 501 fails for a rolled-back row, and no `removePendingOperations`). `Modules/CoreRPG/Controllable/ItemControllable.swift` lines 279-291 (`deleteForExternalImport`). `Modules/CoreRPG/Import/ExternalImportReviewSession.swift` lines 302-318 (rollback, then a second `consolidatedSave()`, which is `AdventureRootModel.saveExternalImport` at lines 309-325 and flushes every module).
- **§5.2** — `Modules/MapRPG/Map/RootCanvasMap.swift` lines 35 and 106 (`AKImage()` while loading or unavailable). `MapEditController+PhotoSize.swift` lines 57-64 (`realPhotoSize` returns `photoSize` unchanged when it isn't positive), 15-19 (exact `!=`), 33-40 (`resetImage(size: realSize, …)`). `MapModel+Geometry.swift` lines 37-47 (width/height written from `rotatedContentSize(size, …)` before `resetEntryGeometry` returns early on a zero size). The rotation part (double rotation) is the agent's worked example, consistent with lines 41-44.
- **§5.7** — `Modules/GameRPG/BattleRound/BattleRoundController.swift` lines 390-405, `MasterController+MapMessages.swift` lines 179-195, `MasterController+Control.swift` line 120: none checks `isMapStreaming` (its only readers are `GameTableModel.swift:82`, `MapEditorSession.swift:65` and `MapRootModel.swift:24`).
- **§5.8** — `GameController+Metadata.swift` lines 312-320 (highlight set from `defenders(for: entry)`, no `isDead` filter); `BattleRoundModel+Turns.swift` lines 214-223 (only the active entry's `defenderIds` is recomputed).
- **§5.9** — `EditControllable.swift` lines 658-661 (delete before create) and 677-685 (on failure only `lastPersistenceError` is set).
- **§5.13** — `git grep -n lastPersistenceError -- Modules Sources` shows only writes (`EditControllable.swift:684`, `ItemControllable.swift:416-443`) and the declaration.
- **§6.1** — `FileUrl.swift` lines 209-215 (string-prefix IPv6 classification) and 216-223 (`Int(label)` parses `0177` as 177).
- **§3.1** — `PlayerNetworkController.swift` line 453 (`Observations({ browser.removed })`); `BrowserManager.swift` lines 173-183 (`removed` accumulates until `takeRemoved()`).
- **§3.2** — `NavigationSend.swift` lines 372 (replay from every receiver's `.task`), 420 (re-stash in `deinit`), 457 (`.now` timestamp).
- **§3.3** — `AudioController.swift` line 317 (`publisher(for: \.timeControlStatus).removeDuplicates().values`).
- **§5.14** — `RawDie.swift` lines 170-186: `WireShape` has no `three` case.
- **§5.15** — `Modules/DiceRPG/Controller/GameController.swift` line 566 uses `$0` in the second-die branch.
- **Clean builds** — logs of the four `xcodebuild … build` runs were grepped for `warning:`/`error:`; the only hits are the appintentsmetadataprocessor notices.

**Corrections to agent reports:**
- One agent cited §5.15 as `DiceGameController.swift` and said the file had been renamed during the review. The file is still `Modules/DiceRPG/Controller/GameController.swift`, and the working tree was unchanged (`git status` was clean at `6a7b5fa0` throughout; only the checked-out branch name changed from `3.0-618` to `develop`, both at the same commit).
- I checked whether the §7.1 change that made `createGameData` `@concurrent` could now trap in `Encoder.encodeOnMainActor` (`Modules/CoreRPG/Extensions/Encoder+MainActor.swift:20-37`). It can't have regressed: the removed `detachedGameData` wrapper already ran these exports off the main actor, so the isolation is unchanged. Not reported.
- One agent's "remote-download cap may not fire during transfer" concern was dropped as unproven: the post-download size check enforces the cap anyway.

If any finding doesn't reproduce when you visit the line, send me the specific reference and I'll re-investigate.

---

## 13. Remediation status (§3.1–§3.17)

Fixed 2026-09-29 on `develop` (uncommitted at the time of writing). Every fix is tagged `See CODE_AUDIT_19 §3.x` in the code.

| § | Status | Fix |
|---|---|---|
| 3.1 | Fixed | `toggleConnection(to:passcode:)` drains `takeRemoved()` before the join starts, so the `Observations` loop's first value holds only removals made during the join. |
| 3.2 | Fixed | A replayed send carries its first stash time (`NavigationSendValues.firstStashedAt`) and is re-stashed with it, so the 5 s lifetime no longer restarts. `replayUndeliveredSends(for:)` replays only sends whose first value matches the mounting receiver's type. |
| 3.3 | Fixed | `timeControlStatus` publisher gets a `.buffer(size: 8, prefetch: .keepFull, whenFull: .dropOldest)` stage, and each element is only a wake-up: the loop reads `player.timeControlStatus` live. |
| 3.4 | Fixed | `CoreDataModel` stamps each queued operation with a sequence number and records the newest drained sequence per id. `restorePendingOperations` drops an operation superseded by a newer drained one, and the flush's per-id merge picks the highest sequence. Tests: `Tests/CoreRPGTests/CoreDataModelSequenceTests.swift`. |
| 3.5 | Fixed | `AudioPlayerSession` keeps the configure task; `preparePlay` awaits `waitUntilConfigured()` before the first `play()`. |
| 3.6 | Fixed | The remote-change sequence is created synchronously in `init`, and one history pass is scheduled at startup. |
| 3.7 | Fixed | `ContextFlushLedger.unregister(_:)` runs from `CoreDataInitModel.stop()`; `register` also detects a reused address through a weak context reference and drops the stale entry and observer. |
| 3.8 | Fixed | `CloudContainerCache` has a generation counter that a resolve checks before storing. `ExternalImportSourceRegistry` resolves its default directory on each use. The main-thread block on a read right after `invalidate()` remains (same as the first read at launch). |
| 3.9 | Not changed | Needs the Hangs instrument during a SharePlay join with audio active. The suggested `@concurrent` + `sending` helper does not apply as-is: the session is still referenced by `groupSession` and the main-actor state/participant tasks, so it cannot be `sending`. |
| 3.10 | Fixed | `@preconcurrency` removed. The one hidden diagnostic (`systemCoordinator` getter sending the non-Sendable `GroupSession` off the main actor) is handled by a `@concurrent` lookup through a private `@unchecked Sendable` box, scoped to that single read. visionOS builds with 0 warnings. |
| 3.11 | Fixed | SharePlay participant loop re-binds `self` per element. `ConnectionController` waits for each message holding only the `NWConnection`. `BrowserManager`'s supervisor loop lives in the task and uses `self?` between awaits. The demo loop in `GameRoot` binds `self` per step (`demoRoundSteps` / `performDemoStep`), never across the paced sleeps. |
| 3.12 | Fixed | `GameTableModel.sendMapContent(for:force:)` chains content updates in order and ends each with a live map state. While one is pending for a map, `broadcastMapEdit` leaves the state to it. A structural edit made while paused marks the map in `RootModel.mapsWithUnsharedStructure`; the resume/refresh send in 3D (`sendMapUpdates`) and in 2D (`RootGameMapViewer.sendMapUpdates`) pushes the content update first. |
| 3.13 | Fixed | Encoding starts right away in its own task; only the hand-off to the connections is chained. `resetConnections()` clears `outboundChain`. |
| 3.14 | Fixed | `ConnectionController.send(content:context:)` skips and logs a nil encoding, covering every send path. |
| 3.15 | Fixed | `ProgressBox` remembers a cancel that arrives before the `Progress` is stored and applies it in `store(_:)`. |
| 3.16 | Partly fixed | Placement retries once per `SceneEvents.Update` (new `SceneUpdateWaiter`, up to 90 frames) instead of `Task.sleep`. `isManipulating`/`isMovedSinceTablePlacement` are set directly in the handlers. Moving the placement logic into a model (§9.23) is not done. |
| 3.17 | Fixed | Only the failed step is re-queued (a failed checkpoint no longer re-inserts saved events). A failed flush schedules a retry. `finishSession` retries pending writes before marking the session complete and logs whatever is still dropped. |
