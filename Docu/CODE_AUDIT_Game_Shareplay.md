# MasterRPG SharePlay & Game Message Code Audit

Generated 2026-11-09. Scope: **~105 Swift files, ~17,000 LOC** — the complete game-message stack and the SharePlay transport:

- `Modules/GameRPG/SharePlay/*` (17 files), `Modules/GameRPG/Table3D/GroupActivityManager.swift`, `Table3D/GameTableModel+Seating.swift`, `SetupViews/SharePlayButton.swift`
- `Modules/GameRPG/Network/*` (16 files: LAN transport, framer, listener, throttles, join code, delivery, controller delegates)
- `Modules/GameRPG/Model/*` (message envelope, pipeline, sequence gates, limits), `Modules/GameRPG/Master/*`, `Modules/GameRPG/Player/*`
- `Modules/GameRPG/Controller/*` (every `MasterController+*` and `PlayerController+*` extension, `PendingMapUpdateQueue`, `LogGameController`, `FileBackedModuleAccess`)
- `Modules/CoreRPG/Model/NetworkCodableDataType.swift`, and how `GameRoot`/`GameRootModel` start and stop the stack.

`Dead/` does not exist; nothing was excluded. This is a **fresh pass** over a stack that has been audited many times (`Docu/CODE_AUDIT_Network.md`, `CODE_AUDIT_22.md`, `CODE_AUDIT_Game.md`, `GAME_MESSAGE_COMMUNICATION_FLOW_REVIEW.md`, …). Agents were told to skip anything already fixed and to report earlier fixes only when the current code shows them incomplete or regressed; those items are tagged **(regression / incomplete fix of …)**. The 2026-10-11 decision stands: the file protocol is a simple 2.6-style request/answer flow, and the removed routing / admission / repair machinery is **not** recommended back anywhere in this report.

Findings cite `path/to/file.swift:LINE`. No code was changed; this is the only file written.

**Method.** Four parallel deep-read passes (concurrency + API modernity; dead code / duplication; SharePlay transport bugs; game-message-layer bugs) plus a clean compiler build. Build ground truth: a clean `xcodebuild clean build` of the `MasterRPG` scheme for iOS Simulator **succeeded with zero Swift compiler warnings and zero errors** (only the `appintentsmetadataprocessor` "no AppIntents.framework dependency" tooling note). Concurrency findings below are therefore *semantic* (interleavings, ownership, cancellation), not compiler-driven.

**Severity result.** 0 Critical, 3 High, ~30 Medium, the rest Low. No Critical was found: nothing in scope can corrupt memory or leak data across trust boundaries beyond what "players are trusted" already accepts. The three Highs were each re-verified by opening the cited lines (see §12).

---

## 1. Executive summary

1. **[High] The master's message drain runs inside whichever peer's receive task enqueued first — cancelling that peer's task (disconnect) silently drops another peer's in-hand message and blocks that peer's own socket** — §3.1 — `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:150-180,229-257`, `Model/GameMessagePipeline.swift:204-211`. *(incomplete fix of CODE_AUDIT_16 §3.2 / Network §5.15)*
2. **[High] LAN frames are never size-checked on the send side** — the 100 MB limit is enforced only by the receiving framer, so a shown item above ~75 MB (base64 in JSON) kills the player's connection every time it is requested — §5.1 — `Modules/GameRPG/Network/GameProtocol.swift:50-74,98-107`, `ConnectionController.swift:171-195`.
3. **[High] Deferred-delivery promotion busy-loops on the main actor while the Messenger queue is full** (retry entry whose time has passed + full queue → zero-delay reschedule + a warning log per iteration) — §5.2 — `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:386-438`. *(regression of CODE_AUDIT_Network §5.3 fix)*
4. **[Medium] Journal attachments are fully loaded into memory before the size check; every player also downloads every other player's uploads** — §6.2, §7.1 — `Modules/GameRPG/SharePlay/RPGSharePlayController+JournalAttachments.swift:224-250`, `Network/GameNetworkController+SharePlayDelegate.swift:31-36`.
5. **[Medium] Any SharePlay participant can impersonate the master to other players** (authority comes from message fields, not the Messenger participant) and wedge their counters/presentations — §6.1 — `Modules/GameRPG/Controller/PlayerController+MessageProcessing.swift:43-84`, `PlayerControllerModel.swift:82-144`.
6. **[Medium] A master that restarts / rejoins under a new participant keeps stale counters on players** — its restarted broadcasts are dropped until its counter passes the old high-water mark — §5.3 — `Modules/GameRPG/Controller/PlayerController+MessageProcessing.swift:76-84`.
7. **[Medium] Journal → Messenger fallback cannot carry 47–100 MB assets**, so they are lost silently; a slow-but-successful Journal add is discarded — §5.11 — `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:91-177`.
8. **[Medium] Asset requests the master cannot serve (iCloud placeholder, export error) get no answer**, unlike the player side which sends `.failed` — requester waits forever — §5.5 — `Modules/GameRPG/Controller/MasterController+FileMessageSupport.swift:61-64`, `+AudioMessages.swift:37-40`.
9. **[Medium] A hung Journal `remove`/`add` permanently disables the Journal path (per module or process-wide) until relaunch** — §3.2 — `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift:166-172,340-360,521-583`. *(incomplete fix of CODE_AUDIT_21 §3.11)*
10. **[Medium] A pending audio play has no deadline and waits for receipts from every listed player — ghosts and evicted-log acks stall the GM's music** — §5.7, §5.6, §5.8 — `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:149-214`, `LogGameController.swift:26,133-135`.

---

## 2. Quick wins (≤30 min each)

- **Delete five empty `#if os(macOS) / #else / #endif` blocks** — `Controller/PlayerController.swift:6-8`, `PlayerController+Control.swift:9-11`, `PlayerController+NetworkStoreDelegate.swift:11-13`, `PlayerController+MessageProcessing.swift:6-8`, `PlayerController+SendMessages.swift:8-10` (all under `Modules/GameRPG/`). §9.14.
- **Key `SharePlayJournalAddLimiter` by publication slot, not module** — one argument change at `SharePlay/RPGSharePlayController+ChunkedTransport.swift:57-59,73-77,85-89,121-122`. §5.10.
- **Log decode/encode failures** (source participant, stream id, byte count) — `SharePlay/RPGSharePlayController+SessionLifecycle.swift:352-357`, `+ChunkedTransport.swift:243-256,460-470`, `Model/GameMessagePipeline.swift:359-361`. §5.19.
- **Remove `@preconcurrency import TabletopKit`** — `Table3D/GroupActivityManager.swift:6` (other Table3D files compile without it). §3.14.
- **Remove `@unknown default` on the project's own `NetworkModules` enum** — `Controller/PlayerController+Dispatch.swift:38-40`. §4.2.
- **Make `PlayerController+Dispatch.response(...)` a plain `@MainActor`/sync method** — `Controller/PlayerController+Dispatch.swift:55-57`. §3.13.
- **Store the `tasks[UUID()]` journal drain under a fixed key** — `SharePlay/RPGSharePlayController+JournalAttachments.swift:38-52`. §3.11.
- **Remove a sender's entry when its inbound budget returns to zero** — `SharePlay/SharePlayInboundByteBudget.swift:13-37`. §7.5.
- **Fix comments naming deleted types** (`SharePlayPlayerJournalAdmission`, `SharePlayMapRecoveryTracker`) — `Network/PhysicalIdentityDenylist.swift:10-18`, `Network/ConnectionAttemptThrottle.swift:42-47`; and the stale `withObservationTracking` doc in `SharePlay/GameShareStateModel.swift:6-10`. §9.13.
- **`Date()` → `.now` for `startGameTime`** — `Root/GameRootModel.swift:68`. §4.3.
- **Make `GroupActivityManager.tabletopGame` a `let`** — `Table3D/GroupActivityManager.swift:8-23`. §9.17.
- **Reject envelopes with `counter <= 0` from remote peers** (or derive a key without the counter) — `Model/GameMessagePipeline.swift:105-108,222-223`. §5.27.

---

## 3. Concurrency

Ground truth: zero compiler warnings under Swift 6 / `SWIFT_STRICT_CONCURRENCY=complete`. Grep also shows no `DispatchQueue`, `Timer`, `nonisolated(unsafe)`, `ObservableObject`, `Task.sleep(nanoseconds:)`; every `@Observable` in scope is `@MainActor`; all timeouts use `ContinuousClock`/`Duration`. The findings below are interleaving and ownership problems the compiler cannot see.

### 3.1 Shared message drain is owned by a cancellable peer receive task
- **Location:** `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:150-180` and `:229-257`; `Modules/GameRPG/Controller/PlayerController+MessageProcessing.swift:230-291`; `Modules/GameRPG/Model/GameMessagePipeline.swift:204-211`; `Modules/GameRPG/Network/ConnectionController.swift:215-222,287-303`; `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:345-372`
- **What:** `received(_:origin:)` enqueues into the shared `GameMessagePipeline` and then runs `processMessages()` inline in the caller's task; the first transport task to find the pipeline idle drains *every* peer's events. For LAN that task is one connection's receive loop, for SharePlay the session message task.
- **Why:** Interleaving: peer A's receive loop is draining; B's asset request is dequeued and `handle` awaits a multi-MB `createGameData`; A disconnects and `teardown` cancels A's receive task; B's in-flight `handle` throws `CancellationError`, `process` returns `false` (`:251-252`), `processed(success:false)` drops B's event with no answer. B is healthy but its request is never served. Only the `Task.isCancelled` check *before* `process` (`:172-176`) requeues; a cancellation *during* `process` does not. Independently, while A's task drains B's and C's backlog, A's own socket is not read, so the "slow delegate holds back the peer" design (`ConnectionController.swift:285-286`) holds back the wrong peer. A SharePlay `reset()` has the same effect on LAN events sitting in the SharePlay task's drain.
- **Action:** Give the drain a single owner: a long-lived worker task held by the controller (the pattern `drainSendOperations` already uses), cancelled only by stop/reset of the game. Producers only enqueue and signal; transport cancellation then only stops receiving, and `handOffBacklog` becomes unnecessary. This moves where the loop runs; it is not routing/admission machinery.
- **Severity:** High *(regression / incomplete fix of CODE_AUDIT_16 §3.2 and CODE_AUDIT_Network §5.15 — those fixed stranding, not ownership)*
- **Status: fixed 2026-11-09.** `GameMessagePipeline` owns the drain worker (`submit(_:prefix:kind:drain:)`); only `cancelAll()` cancels it. A producer waits only for its own message (per-peer backpressure kept; stops waiting on its own cancellation; released by `reset()`/`cancelAll()`; a handler submitting to a pipeline it already runs in does not wait, via a task-local). `handOffBacklog` and the per-controller hand-offs are gone (§3.8); a worker that ends with messages left is replaced by `drainEnded`. Tests: `GameMessagePipelineDrainOwnershipTests`. §3.10's Messenger-loop part is not done.

### 3.2 Hung Journal `remove`/`add` calls permanently disable the Journal path
- **Location:** `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift:166-172,340-360 (esp. 344,356),521-583`; `SharePlay/SharePlayDeferredDeliveryQueue.swift:27-62`; `SharePlay/RPGSharePlayController+ChunkedTransport.swift:186-190`; `SharePlay/SharePlayJournalAddLimiter.swift:39-41,63-66,119-127`
- **What:** `scheduleObsoleteCleanup` awaits one unbounded `remove(attachment)` and clears `emergencyCleanupTasks[module]` only when it returns; `cancelAll` keeps the entry on purpose; `retryUntilRemoved` counts only *returned* failures; hung adds stay in the limiter (global cap 16); `RPGSharePlay.store` is a process-wide singleton.
- **Why:** The code itself documents that a system Journal removal may ignore cancellation. If one `journal.remove` never returns (e.g. session invalidated mid-call) that module is rejected from the Journal in every later session until relaunch; after 8 hung removals every Journal publication is rejected; after 16 hung adds every module returns `.unavailable`. Everything then falls back to Messenger, where anything above ~47 MB is undeliverable (§5.11).
- **Action:** Race every system add/remove against a deadline, as `SharePlayAttachmentLoadRetry.load(deadline:)` already does for loads; release the reservation/emergency slot on timeout; scope reservations and the per-module flag to the session generation so `cancelAll` frees them.
- **Severity:** Medium *(incomplete fix of CODE_AUDIT_21 §3.11)*
- **Status: fixed 2026-11-09.** Every cleanup `remove` is raced against `cleanupDeadline` (30 s) and cancellation (`removeBounded`); a hung call is given up and its reservation/emergency slot freed. `cancelAll()` forgets cleanup tasks and resets the reservation count (no longer carried over). A late add of a reset session gets its own `obsoleteCleanupTasks` slot that does not gate `enqueue`. `SharePlayJournalAddLimiter` counts hung adds of ended sessions apart (`maxObsoleteAttempts` 8). Receive side: `loadMetadata` in the sequential snapshot drain now has a 20 s deadline. Tests: `SharePlayJournalHangTests`. Not changed: a hung add still quarantines that module for the rest of its session (Messenger fallback); join-batch loads still run one after the other (see §5.13 area).

### 3.3 GroupSession `join()`/`leave()` run on a detached task through an `@unchecked Sendable` box
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:501-542` (`SessionBox` `:507-509`, `Task.detached` `:517-527`)
- **What:** A non-Sendable `GroupSession` is smuggled to a detached task while the main actor subscribes to `$state`/`$activeParticipants` and reads the session concurrently.
- **Why:** The `@unchecked` justification (internal thread-safety of `GroupSession`) is undocumented; a race inside system code is invisible to TSan. The ordering of join vs leave itself is correct (`GroupSessionCommandQueue`, CODE_AUDIT_24 §3.1 is fixed).
- **Action:** Document next to the box why it runs off-main (presumably a blocking XPC call) and that it was verified, or call join/leave on the main actor where all other session access happens and measure the hitch.
- **Severity:** Low
- **Status: documented 2026-11-09, no behaviour change.** `SessionBox` now states why it is `@unchecked` (assumption: `join()`/`leave()` are serialised by the framework and only the command queue calls them off-main) and that this cannot be verified with TSan. No test possible. Open: decide whether to call both on the main actor.

### 3.4 Join-code Keychain flush holds a `Mutex` across `SecItem` I/O while the main actor waits on it
- **Location:** `Modules/GameRPG/Network/GameJoinCodeModel.swift:83-85,303-328`; callers `Controller/MasterController+Control.swift:20-21`, `Controller/PlayerController+Control.swift:23-24`
- **What:** `flush(to:)` holds `writeLock` for the whole loop of synchronous Keychain writes; `flushPendingWrites()` is called on the main actor right before hosting/joining.
- **Why:** If a debounced background flush is mid-write, tapping Host/Join blocks the main thread on the lock (Keychain goes over XPC; tens to hundreds of ms, more after first unlock) and then performs its own synchronous I/O — a visible stall.
- **Action:** Hold the lock only to take the pending snapshot; serialise writes on one non-main executor (the existing `@concurrent` chain) and `await` the flush from the host/join path.
- **Severity:** Low
- **Status: fixed 2026-11-09.** `flushPendingWrites()` is `async` and runs the Keychain loop in a `@concurrent` task; Host/Join `await` it, so the main actor never waits on the write lock or the I/O. Test: `GameJoinCodeModelTests.flushDoesNotWriteOnTheMainThread`.

### 3.5 Keychain reads on the main actor in model init and session-id lookup
- **Location:** `Modules/GameRPG/Network/GameJoinCodeModel.swift:35-44`; `Modules/GameRPG/Master/HostingSessionStore.swift:60-103`; prewarm fired untracked at `Master/MasterNetworkController.swift:86`, synchronous use in `beginHosting` (~`:115`)
- **What:** `GameJoinCodeModel.init` does four synchronous Keychain loads plus a UserDefaults migration on main; `sessionId(forPasscode:)` falls back to a synchronous Keychain read when the fire-and-forget prewarm has not finished — exactly the case when hosting starts right after launch.
- **Why:** File/XPC I/O on main during start; the discarded prewarm task turns a race into a stall.
- **Action:** Load off-main and publish; store the prewarm task and `await` it in `beginHosting`.
- **Severity:** Low
- **Status: partly fixed 2026-11-09.** The prewarm task is stored (`hostingSessionPrewarmTask`); `startMasterGame` and `startProxyServer` `await waitForHostingSessionReady()` before hosting, so `sessionId(forPasscode:)` no longer falls back to a main-thread Keychain read. Tests: `HostingSessionPrewarmTests`. **Not changed:** `GameJoinCodeModel.init` still loads synchronously; loading off-main would make the join codes provisional at launch — needs a decision.

### 3.6 Shared audio export is neither cancellable nor safely de-duplicated
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:301-312` (callers `:276-296`, `:164-169`)
- **What:** `audioPackage(for:)` wraps `createGameData` in an unstructured `Task` and awaits `task.value`; every waiter's `defer` clears `audioPackageTasks[id]` unconditionally.
- **Why:** Cancelling a caller does not end its wait (a cancelled caller still waits for a multi-MB read). Interleaving: waiter 1 clears; waiter 3 starts export T2; waiter 2 (a joiner of T1) clears T2's entry; waiter 4 starts a duplicate export — the dedup is defeated.
- **Action:** Clear the entry only if it still holds the same task; wrap the wait in a cancellation handler that cancels the shared task when the last waiter leaves.
- **Severity:** Low
- **Status: fixed 2026-11-09.** New `SharedWorkCoalescer` (main actor): one run per key, per-waiter cancellation, the last waiter leaving cancels the work, and a run removes only its own entry (identity by run id). `audioPackage(for:)` uses it. Tests: `SharedWorkCoalescerTests`.

### 3.7 A session yielded by `sessions()` is dropped without `leave()` on cancellation paths
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:181-182,207-208; 131-134`
- **What:** `configureGroupSession` returns on `Task.isCancelled` after awaiting teardown, and the observer loop returns when `canConfigure` fails; the freshly yielded session is neither joined nor left.
- **Why:** The system keeps an unjoined, un-left session pending; the FaceTime UI may keep offering the activity and the next `sessions()` iteration may not yield it again. Only during shutdown/replacement.
- **Action:** Call `leave()` on a yielded-but-never-configured session on those early returns.
- **Severity:** Low
- **Status: fixed 2026-11-09 (no unit test).** `configureGroupSession` calls `leave()` on the yielded session at both cancellation returns, unless it is the session already in use (`leaveUnconfiguredSession`). The observer loop's `canConfigure` return already left the session. A `GroupSession` cannot be created in a test.

### 3.8 Untracked fire-and-forget tasks
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:86` (prewarm), `:205,:212-216,:406-412,:535-541`; `Network/ConnectionController.swift:145,190`; `Model/GameMessagePipeline.swift:210` (`handOffBacklog`); `SharePlay/SharePlaySingleQueuePackageSender.swift:120`; `SharePlay/SharePlayJournalAddLimiter.swift:108`
- **What:** Each was judged individually: handshake/dial deadlines (weak self, state re-check), short cancel hops, `onCancel` hops required by `withTaskCancellationHandler`, and bounded connection tasks are fine. The problems are the discarded prewarm task (§3.5) and `handOffBacklog`, which spawns an unowned drain that a game stop cannot cancel.
- **Why:** Untracked tasks outlive stop/reset and escape cancellation.
- **Action:** Store the prewarm task; remove `handOffBacklog` together with the §3.1 fix; leave the rest.
- **Severity:** Low
- **Status: fixed 2026-11-09** together with §3.1 (`handOffBacklog` removed) and §3.5 (prewarm task stored).

### 3.9 `try?` on proxy character export hides cancellation
- **Location:** `Modules/GameRPG/Controller/MasterController+ProxyDelegate.swift:20-24`
- **What:** `try? await createGameData` turns `CancellationError` into `nil`, indistinguishable from "no character data", and the function continues with sends.
- **Why:** After a cancelled proxy replay the code cannot tell cancellation from absence. Harmless today (only skips a send).
- **Action:** `do/catch`; return on `CancellationError`, log other errors.
- **Severity:** Low
- **Status: fixed 2026-11-09.** `do/catch`: `CancellationError` returns (plus a `checkCancellation` after the export), other errors are logged. Guard test `cancelledProxyReadyDoesNotSendCharacter` — it does not fail on the old code, because the old `try?` also ended without a send (the audit calls it harmless).

### 3.10 Session teardown waits without limit for in-flight callbacks; the Messenger receive loop is serialised behind full message processing
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:181,199-207,286-292,364-369`; `SharePlay/RPGSharePlayController.swift:252-257,288-293`
- **What:** `handleUpdate` awaits the player's full `processMessages()` (including imports); a replacement `configureGroupSession` awaits `waitUntilIdle` with no timeout; meanwhile the 120 s receiver expiry keeps running.
- **Why:** A slow or hung callback delays or wedges reconnection to a new session, and long processing stalls reassembly for all participants so partial streams whose remaining chunks are already buffered can expire.
- **Action:** Bound the teardown wait with a timeout and continue after logging; hand completed messages to the pipeline without awaiting their processing inside the Messenger loop (compatible with the single-owner drain of §3.1).
- **Severity:** Low
- **Status: partly fixed 2026-11-09.** `SharePlaySessionCallbackCoordinator.waitUntilIdle(sessionId:timeout:)` gives up after 10 s (logs, returns `false`) and both teardown closures use it, so a hung delegate callback cannot wedge the reconnection. Tests: `SharePlayLifecycleAuditTests`. **Not changed:** the Messenger receive loop still awaits `processMessages()` — that await is the backpressure, and the pipeline caps would drop messages instead.

### 3.11 `tasks` dictionary gains an entry for every Journal drain episode
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+JournalAttachments.swift:38-52`; `SharePlay/RPGSharePlayController.swift:497`
- **What:** Each new drain task is stored under a fresh `UUID` and never removed when it finishes.
- **Why:** Finished handles accumulate for the whole session, one per idle→busy Journal transition. Small but unbounded.
- **Action:** Store under a fixed key (as `trackSessionTask(_:key:)` supports) or remove on completion.
- **Severity:** Low
- **Status: fixed 2026-11-09.** The drain task is stored under `journalDrainTaskKey` via `trackSessionTask`. Test: `SharePlayLifecycleAuditTests.journalDrainEpisodesDoNotAccumulateTaskHandles`.

### 3.12 Journal metadata loads run serially with no deadline
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+JournalAttachments.swift:65-85`; `SharePlay/RPGSharePlayController.swift:498-501`
- **What:** `handle()` awaits `loadMetadata` for each uncached attachment in sequence inside the single drain task.
- **Why:** If one metadata load stalls, no later snapshot is processed — contradicting the drain's stated goal that a hung load cannot keep later publications from being looked at. *(reasoned from code; not reproduced)*
- **Action:** Wrap metadata loads in the same deadline race used for byte loads.
- **Severity:** Low
- **Status: fixed 2026-11-09** with §3.2 (`loadMetadata` deadline, 20 s). Join-batch loads still run one after the other.

### 3.13 `nonisolated async` response builder adds only an executor hop
- **Location:** `Modules/GameRPG/Controller/PlayerController+Dispatch.swift:55-57`
- **What:** Under approachable concurrency a `nonisolated async` function runs on its caller and immediately awaits main-actor state.
- **Why:** Suggests off-main work that does not happen and costs an extra hop.
- **Action:** Make it a plain `@MainActor` or synchronous method.
- **Severity:** Low
- **Status: fixed 2026-11-09.** `PlayerController.response(for:isSuccess:requestData:)` is a synchronous main-actor method; the `await`s at the call sites are gone. Covered by the existing `response` tests in `GameMessageCorrectnessRegressionTests`.

### 3.14 Unneeded `@preconcurrency import TabletopKit`
- **Location:** `Modules/GameRPG/Table3D/GroupActivityManager.swift:6`
- **What:** The only file importing TabletopKit with `@preconcurrency`; the other Table3D files import it plainly and compile under complete checking.
- **Why:** Suppresses Sendable diagnostics for this file and can hide a real crossing.
- **Action:** Remove the attribute and fix any diagnostic that appears.
- **Severity:** Low
- **Status: fixed 2026-11-09.** `@preconcurrency` removed from `GroupActivityManager.swift`; the visionOS build has no new diagnostics.

---

## 4. API modernity

No deprecated APIs, closure-based variants with async equivalents, legacy `Formatter`s, `String(format:)`, `DispatchQueue`, or sub-deployment-target `@available` guards were found in scope. LAN transport is the structured `NetworkConnection`/`NetworkListener` API by design (since 2026-09-29); the framer still uses `NWProtocolFramer` as that API requires.

### 4.1 Wire enums decode strictly — adding one case silently drops the envelope on older peers
- **Location:** `Modules/CoreRPG/Model/NetworkCodableDataType.swift:63`; `Modules/GameRPG/Model/GameNetworkModel.swift:114,199-200`
- **What:** `NetworkModules`, `RPGMessageType`, `RPGMessageActionType` have no unknown-case fallback (`senderPlatform` does, `:205-208`).
- **Why:** A case added without bumping `currentVersion` makes a mixed-version game fail with a decode error and no user-visible version message (see §5.9).
- **Action:** Treat any case addition as a `currentVersion` bump (documented beside the enums), or decode unknown cases to an explicit `.unknown` the dispatcher ignores.
- **Severity:** Low
- **Status: fixed 2026-11-09 (first option of the action).** The rule is written beside `NetworkModules`, `RPGMessageType`, `RPGMessageActionType` and `GameNetworkModel.currentVersion`: any case change is a version bump. `WireContractTests` pins the raw values of all three enums together with the version, so a case added without a bump fails the build. It also pins that an unknown case or another version is dropped. **Not done:** a decode fallback to `.unknown` — it would need every exhaustive switch to handle it (and conflicts with §4.2), and the version check already refuses an older peer explicitly.

### 4.2 `@unknown default` on the project's own module enum
- **Location:** `Modules/GameRPG/Controller/PlayerController+Dispatch.swift:38-40`
- **What:** `@unknown default` on `NetworkModules`, compiled from source in this project (not a resilient SDK enum).
- **Why:** Hides the exhaustiveness error that should force handling when a module is added; the unknown-case risk belongs at decode time (§4.1).
- **Action:** Switch exhaustively with no default.
- **Severity:** Low
- **Status: fixed 2026-11-09.** `@unknown default` removed; the switch over `NetworkModules` is exhaustive, so a new module is a compile error here. The compiler is the test.

### 4.3 `Date()` for game start time
- **Location:** `Modules/GameRPG/Root/GameRootModel.swift:68`
- **What:** `startGameTime` initialised with `Date()`.
- **Why:** Style; if it feeds elapsed-time math rather than display, a `ContinuousClock.Instant` is immune to wall-clock changes.
- **Action:** Use `.now`; use `ContinuousClock` if it feeds durations.
- **Severity:** Low
- **Status: fixed 2026-11-09, no test.** `Date.now` in the property default. `startGameTime` stays a wall-clock `Date`: it is shown as a date and given to the statistics session, and `GameRoot` sets it again at game start. A default value of `Date.now` has nothing to assert.

---

## 5. Bugs / logic errors

### 5.1 Outbound LAN frames are never checked against the receiver's frame limit
- **Location:** `Modules/GameRPG/Network/GameProtocol.swift:50-74` (send), `:98-107` (receive); `Network/ConnectionController.swift:171-195`; `Master/MasterNetworkController.swift:242-266`; `Model/GameLimits.swift:13`; `Modules/CoreRPG/App/ByteLimits.swift:21`
- **What:** `GameLimits.maximumMessageBytes` (100 MB) is enforced only by the *receiving* framer, which fails the connection with `EMSGSIZE`; `handleOutput`, `ConnectionController.send` and `sendOrdered` never compare the encoded size to it. The only send-side limit is the outbound queue total (`maximumOutboundQueuedBytes`, `ConnectionController.swift:186`), which deliberately always admits one frame of any size. Source files may be up to 256 MiB (`ByteLimits.maximumSourceFileBytes`); base64 inside the JSON envelope inflates by ~4/3, so any file above ~75 MB produces a frame the player rejects.
- **Why:** The player's connection dies on every such frame. After reconnecting, late-joiner replay (`MasterController+PresentationReplay.swift`) shows the same item again, the player requests the asset, and the master sends the same oversized frame again — a repeat loop for as long as the item is on screen *(loop inferred from the replay design; the framer rejection and missing send check were verified)*. Every other message to that player is lost each cycle, and the master gets no signal that size is the cause.
- **Action:** Check the encoded size against the shared maximum before queuing for LAN; answer an oversized asset with `.failed` ("too large for LAN") instead of sending; derive send-side and receive-side limits from the one constant.
- **Severity:** High

### 5.2 Deferred-delivery promotion busy-loops on the main actor while the send queue is full
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:386-415` (esp. `:403-411`), `:417-438` (esp. `:423-436`), warning log at `:303-315`
- **What:** When the deferred head is a retry entry whose `retryNotBefore` has passed and `enqueueChunkedSend(allowDeferral:false)` fails on the 16-operation or byte budget, `promoteDeferredDeliveries` calls `scheduleDeferredPromotionIfNeeded()`. The timer task cleared `deferredPromotionTask` just before promoting, so a new task is created with a zero-or-negative delay, skips the sleep, and promotes again at once.
- **Why:** A small event fails, gets a 1 s retry, and that second passes while a ~47 MB Messenger transfer plus a few operations fill the queue: the main actor runs a task-creation/promotion loop for the whole transfer (often tens of seconds), each iteration logging "Chunked queue full: ignored message". Each hop yields to the main loop so the UI is not frozen, but CPU/battery drain, jank and a flooded unified log result. No test covers "head ready + queue full". It is the §5.3 fix of CODE_AUDIT_Network, which added this unconditional reschedule.
- **Action:** On the capacity-failure path do not reschedule against an already-passed deadline: rely on `drainSendOperations` calling promote after each completed operation, or schedule a minimum back-off (the next retry step). Log the "ignored" warning only when `allowDeferral` is true. Add a unit test for head-ready + queue-full.
- **Severity:** High *(regression of CODE_AUDIT_Network §5.3 fix)*

### 5.3 A master that rejoins under a new participant keeps stale sequence state on players
- **Location:** `Modules/GameRPG/Controller/PlayerController+MessageProcessing.swift:76-84`; `Controller/PlayerControllerModel.swift:82-87,136-144`; `Controller/PlayerController+NetworkStoreDelegate.swift:25-26`; `Controller/MasterControllerModel.swift:14`
- **What:** Sequence state is cleared only when the old master participant's *leave* is observed (`removeSharePlayMasterParticipant` → `resetForLostConnection(preservingSharePlayRebind:true)`). If the new participant's first message arrives before that leave, the `.changed` branch only calls `ready()`; `lastMasterStateCounters` (keyed by `masterId`, which stays the same across restarts because the session id is kept per join code) and `lastPresentation` survive, while the restarted master counts from 1 (`messageCounter = 1`).
- **Why:** Until the new counter passes the old high-water mark, players ignore its config/controls/roster and drop its presentations as stale — in practice players stay on the old screen after the GM restarts the app mid-SharePlay.
- **Action:** On `.changed`, reset the master-state sequence, list sequence and presentation order exactly as the leave path does.
- **Severity:** Medium

### 5.4 After a non-audio Journal attachment fails to load, the player never asks again
- **Location:** `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:122-143`; `Model/GameMessagePipeline.swift:105-108,166-182`; `Tests/GameRPGTests/PlayerControllerTests.swift:230-257`
- **What:** `sharePlayFileLoadFailed` feeds the metadata (no data, same counter, type/subType, data id/type/version, target) back through `receivedProcess(model, origin:.file)`. Every part of the dedup key matches the reference already processed, so the pipeline drops it as a duplicate and no re-request goes out. Only audio has a separate path, and the existing test covers only audio.
- **Why:** A photo, PDF, map or Space package whose Journal transfer failed stays missing on that player for the rest of the session, with no error shown.
- **Action:** Turn a load failure into an explicit local re-request (or a distinct event kind that is not de-duplicated); add a photo/map test.
- **Severity:** Medium

### 5.5 Asset requests the master cannot serve get no answer
- **Location:** `Modules/GameRPG/Controller/MasterController+FileMessageSupport.swift:61-64`; `Controller/MasterController+AudioMessages.swift:37-40`; `Controller/MasterController+NetworkStoreDelegate.swift:251-257`
- **What:** If the master's file is not local (iCloud placeholder or evicted), the asset-request handlers return `nil` and send nothing; any other error thrown in `process` is logged and returns `false` without a `.failed` answer. The player side does send `.failed` in the same situation (`PlayerController+MessageProcessing.swift:281-289`).
- **Why:** Under request/answer, a missing answer is the one outcome the requester cannot tell from slowness: the player shows a loading state indefinitely and never falls back or retries.
- **Action:** Always answer — `.failed` for a non-local file or export/processing error — so the player can mark the item unavailable and retry later.
- **Severity:** Medium

### 5.6 `.file`-origin messages bypass route binding and the `isBound` roster check
- **Location:** `Modules/GameRPG/Network/GamePlayerRoutes.swift:21-23,53-56`; `Controller/MasterController+NetworkStoreDelegate.swift:194,210-214,310-317`; `Network/GameNetworkController+SharePlayDelegate.swift:126-145`
- **What:** The ghost-player fix depends on `isBound`, but the `.file` origin always passes both the origin binding and `isBound`. A Journal attachment that arrives late — after its player left — or that names another `sender.id` adds a roster entry with no route, and value-update ownership then trusts that `sender.id`.
- **Why:** Ghost entries come back on SharePlay, the case CODE_AUDIT_23 §5.4 was meant to fix; they also feed §5.7 (a ghost never sends a receipt).
- **Action:** Bind `.file` events to the Journal attachment's originating participant the same way Messenger events are bound; apply `isBound` before adding to the roster.
- **Severity:** Medium *(incomplete fix of CODE_AUDIT_23 §5.4)*

### 5.7 A pending audio play has no deadline and needs a receipt from every listed player
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:149-158,205-214`
- **What:** `startPendingAudioPlay` starts only when `missingPlayers` is empty, i.e. a receipt from every `currentPlayers` entry.
- **Why:** Ghosts (§5.6), players whose ack was evicted from the log (§5.8), and players stuck on a failed/unanswered request (§5.5) each block the GM's music for the whole table; the GM sees a play that never starts.
- **Action:** Add a deadline after which the play starts for the ready players; late answerers join the music already playing.
- **Severity:** Medium

### 5.8 Late acks are lost once the 300-entry UI log has evicted their row
- **Location:** `Modules/GameRPG/Controller/LogGameController.swift:26,133-135`; `Controller/MasterController+NetworkStoreDelegate.swift:223-227,263-272`
- **What:** Delivery receipts are correlated through `logData`, the display log capped at 300 entries.
- **Why:** In a busy session the row for a large asset can be evicted before its `.ok` arrives; the ack is then "uncorrelated" and dropped, so availability lists and audio receipts are never recorded and the master keeps resending assets the player holds. A UI-retention setting controls protocol correctness.
- **Action:** Correlate acks through a small dedicated pending-request table (counter + target, with deadline), separate from the display log.
- **Severity:** Medium

### 5.9 A wire-version mismatch is silent — both sides look connected
- **Location:** `Modules/GameRPG/Model/GameNetworkModel.swift:189-210`; `Model/GameMessagePipeline.swift:349-357`; `Network/GameNetworkController+MasterDelegate.swift:29-32`; `Network/GameNetworkController+PlayerDelegate.swift:29-32`
- **What:** Only envelope version 3 decodes; any other version throws `UnsupportedVersion`, which is only logged, and the message is dropped on both sides while the PSK handshake still succeeds.
- **Why:** A player on an older/newer App Store build joins, appears connected, and receives nothing; neither user is told to update — hard-to-diagnose support reports.
- **Action:** On an unsupported version, answer with a minimal versioned "incompatible" message (or close with a specific reason) and show "update the app" on both sides.
- **Severity:** Medium

### 5.10 Journal add limiter is keyed by module, so an audio playlist and its first track always collide
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:57-59,73-77,85-89,121-122`; `SharePlay/SharePlayJournalAddLimiter.swift:63-66`
- **What:** Publications are serialised per `SharePlayJournalSlot` (the playlist has its own slot) but `journalAddLimiter.run(for: moduleKey, scope: sessionId)` allows one add per *module*; the two slot workers run concurrently and the second gets `.unavailable`.
- **Why:** Showing a playlist with its first track — the case the separate slot exists for — makes the second publication log "Journal bypass" and broadcast through Messenger to everyone, including those who already hold it; a package over ~47 MB is lost. A quarantined (timed-out) add in one audio slot also blocks the other.
- **Action:** Key the limiter by the slot, the same key the publication queue uses.
- **Severity:** Medium

### 5.11 Journal → Messenger fallback cannot carry 47–100 MB assets; a slow-but-successful Journal add is discarded
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:91-99,117-130,157-161,167-177`; `SharePlay/SharePlayDeferredDeliveryQueue.swift:71-78`; `SharePlay/SharePlayJournalPublicationQueue.swift:113,197-206`; `SharePlay/RPGSharePlayController.swift:529`
- **What:** Journal admission allows up to 100 MB (`GameLimits.maximumMessageBytes`), with that budget shared across *all* slots. Every failure path (`.rejected` budget/emergency slot, `.failed`, `.timedOut` after 10 s, `.unavailable`) falls back to `enqueueChunkedSend`, which refuses anything above ~47.25 MB raw, yet `publishAsset` still returns `.sentByMessenger`. On `.timedOut`, an add that later succeeds is removed by `discardLateValue`.
- **Why:** A 60 MB PDF revealed while another module's add is outstanding, or whose add takes >10 s, reaches no participant: the Journal copy is deleted, Messenger drops it, and the ledger slot is freed (no re-upload until the next show). For assets up to 47 MB the same timeout instead double-delivers, broadcasting to participants that already hold the file.
- **Action:** Return `.unavailable` (and log a loss) when the fallback enqueue fails; budget Journal bytes per slot rather than globally; for assets above the Messenger limit let a timed-out add commit instead of removing it.
- **Severity:** Medium

### 5.12 Strictly serial Messenger queue: small control messages wait behind a large transfer, then overflow
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:303-315,337-384`; `SharePlay/SharePlaySingleQueuePackageSender.swift:84-86,158-212`; `SharePlay/SharePlayDeferredDeliveryQueue.swift:170-178,240-253`
- **What:** Each operation's full multi-package send completes before the next starts (16 outstanding, then a 32-entry deferred queue, then rejection; events evict deferred *presentations*, which are dropped not merged). No package send has a timeout.
- **Why:** During a 40 MB Messenger fallback, dice rolls, HP updates and pin moves sit queued for the whole transfer; a busy round overflows and loses messages including the GM's latest reveal for a module; a `messenger.send` that never returns stalls all outbound SharePlay traffic. The receiver already reassembles interleaved streams per UUID, so strict serialisation is not needed for correctness.
- **Action:** Add a priority lane (or interleave single-package messages between chunks of a large stream), a per-package send timeout, and never let an event evict a module's only deferred presentation.
- **Severity:** Medium

### 5.13 Journal load retry gives up after ~3 s while an upload is still in progress
- **Location:** `Modules/GameRPG/SharePlay/SharePlayDeferredDeliveryQueue.swift:356-399` (defaults `:357-361`); `SharePlay/RPGSharePlayController+JournalAttachments.swift:224-241,278-296`; `SharePlay/SharePlayJournalLedger.swift:65-85`
- **What:** The outer deadline is 30–180 s but the inner `SharePlayAttachmentLoadRetry.load` makes only four attempts (250 ms, 1 s, 2 s); a load that throws `uploadInProgress` fails after ~3.25 s, becomes retryable only "on the next snapshot", and the resulting recovery request is answered `.alreadyPublished` — i.e. with nothing.
- **Why:** For a large GM upload every player starts loading immediately, fails within seconds, and gets no file until a later Journal change or a re-show more than 60 s later. *(reasoned from code; not reproduced)*
- **Action:** Keep retrying with back-off inside the deadline race for as long as `isStillWanted` holds, instead of the fixed short inner list.
- **Severity:** Medium

### 5.14 One sender can evict other participants' in-progress streams by filling the shared byte budget
- **Location:** `Modules/GameRPG/SharePlay/SharePlayPackageReceiver.swift:59-62,131-136,145-147,212-237` (esp. `:229-232`)
- **What:** The per-source cap limits stream *count* only; when a source with nothing else evictable needs cumulative bytes, `evictLeastRecentlyActiveStream` falls back to the pool of all sources.
- **Why:** Three concurrent large streams, or one participant growing a single 64 MB stream, silently evict the GM's partly received transfer; there is no NACK so it never arrives. Contradicts the doc claim that a flood cannot evict anyone else's transfer.
- **Action:** Give each source a byte quota; when the requesting source has nothing of its own to evict, reject its chunk.
- **Severity:** Low *(incomplete fix of CODE_AUDIT_16 §6.4)*

### 5.15 visionOS: a closed table stays alive in the seat task; coordination is keyed on a reusable `ObjectIdentifier`
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+TableCoordination.swift:47-65`; `SharePlay/RPGSharePlayController.swift:481-485,698-705`; `Table3D/GroupActivityManager.swift:20-22`
- **What:** The session-scoped seat task captures `gameTableModel` strongly, so a closed volume's TabletopKit/RealityKit graph lives until session reset; the "already coordinated" guard compares the `ObjectIdentifier` of a weakly held `TabletopGame`.
- **Why:** Memory held for the rest of the session; once the capture is made weak, a reopened table allocated at a reused address would match the stale identifier and never be coordinated, so its seats would not sync.
- **Action:** Capture the model weakly; clear `coordinatedTabletopGame` when the game detaches, or key the guard on a UUID stored on the model.
- **Severity:** Low

### 5.16 Targeted sends to a departed participant are retried as transient failures, re-encoding the payload each time
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:229-233`; `SharePlay/SharePlaySingleQueuePackageSender.swift:214-235`; `SharePlay/RPGSharePlayController+ChunkedTransport.swift:243,284-301,535-551`
- **What:** `participantNotActive` goes through package retries, becomes `.retryableFailure`, is deferred up to three more times, and each attempt re-encodes the model to Base64.
- **Why:** An answer for a player who just left costs up to four full encodes of up to 47 MB plus seven failed sends.
- **Action:** Treat `participantNotActive` as terminal; optionally cache encoded bytes across retries.
- **Severity:** Low

### 5.17 Deferred queue promotes only the head — a retry entry not yet due blocks ready entries behind it
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:386-395,417-421`; `SharePlay/SharePlayDeferredDeliveryQueue.swift:191-194,268-273`
- **What:** Promotion and scheduling look only at `first`; a head with a 4 s back-off holds back entries deferred only for capacity.
- **Why:** Ready messages are delayed by unrelated back-offs; repairs inserted ahead of presentations can still sit behind a delayed event.
- **Action:** Promote the earliest *ready* entry (FIFO among ready) and schedule the timer for the minimum `retryNotBefore`.
- **Severity:** Low

### 5.18 A whole-message retry re-broadcasts after newer messages
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:284-301`
- **What:** After a mid-stream failure the entire message is resent under a new stream id to everyone, behind messages sent meanwhile.
- **Why:** Participants that already completed it receive it again (counter dedup absorbs that at a bandwidth cost); state-type updates (pin/table) can be applied after a newer update. Presentations are protected by the player's counter check. *(reasoned)*
- **Action:** Drop the retry for state updates if a newer message for the same entity was already sent, or document that receivers must order by a version.
- **Severity:** Low

### 5.19 Messages that fail to encode or decode are dropped without a log
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:352-357`; `SharePlay/RPGSharePlayController+ChunkedTransport.swift:243-256,460-470`; `Model/GameMessagePipeline.swift:359-361`
- **What:** A nil from `decodedMessage` after full reassembly is skipped silently; an encode failure only records `.failed` in the transport log; `encodeData` uses `try?` and the caller silently sends nothing.
- **Why:** A complete 64 MB message — or a model with a non-finite `Double` — disappears with no evidence, making version-skew and corruption bugs undiagnosable from device logs.
- **Action:** Log a warning with source participant, stream id, byte count and the error identifier.
- **Severity:** Low

### 5.20 SharePlay activates only if the device is eligible at the moment the game starts
- **Location:** `Modules/GameRPG/Network/GameNetworkController.swift:106-116,134-137`; `SharePlay/RPGSharePlayController.swift:596-603`
- **What:** `joinGame()`/`startSharing` run only when `canActivateSharePlay` is true at start; nothing reacts when eligibility changes during a game.
- **Why:** If the GM starts the game and then starts (or restarts) a FaceTime call, SharePlay never activates until the game restarts.
- **Action:** While a master game runs, observe eligibility and offer/perform activation when it turns true.
- **Severity:** Low

### 5.21 With player dice turned off, every player answers every group roll with `.failed`
- **Location:** `Modules/GameRPG/Controller/PlayerController+Dice.swift:20-26`; `Controller/PlayerController+MessageProcessing.swift:281-289`
- **What:** The dice feature gate throws, including for other players' group rolls received via SharePlay or a proxy; the generic catch sends `.failed` upstream for each.
- **Why:** For every roll the master receives (N−1) `.failed` messages, flooding the log/statistics and looking like real rejections.
- **Action:** Treat a locally gated roll as "not applied" (no answer); send `.failed` only for requests addressed to this device.
- **Severity:** Low

### 5.22 Messages rejected only by local policy are forwarded to proxy clients again on every redelivery
- **Location:** `Modules/GameRPG/Controller/PlayerController+MessageProcessing.swift:151-157,173-178,252-254`
- **What:** `.rejectLocallyOnly` forwards to proxy clients and then marks `processed(success:false)`, so it stays eligible to run again.
- **Why:** When SharePlay and LAN both deliver the envelope (or a replay), proxy mirrors get duplicate dice rolls / pin moves.
- **Action:** Record "forwarded" independently of "applied" so forwarding happens once per key.
- **Severity:** Low

### 5.23 `requeueCurrentOnCancellation` removes the pending key, so a duplicate can be queued meanwhile
- **Location:** `Modules/GameRPG/Model/GameMessagePipeline.swift:275-287`
- **What:** The event is put back at the head but its pending key is removed.
- **Why:** Until reprocessed, a duplicate (dual transport, replay) passes dedup and is queued too; non-idempotent updates (dice, value deltas) apply twice.
- **Action:** Keep the pending key while the event is back in the queue.
- **Severity:** Low

### 5.24 `MasterSequenceGate` accepts any session switch, including a late message of an earlier session
- **Location:** `Modules/GameRPG/Model/MasterSequenceGate.swift:15-19`
- **What:** A message with a different session always replaces the stored session/counter.
- **Why:** A delayed message from before a master restart can flip the gate back to the old session; the next real message then counts as a switch, applying stale state briefly.
- **Action:** Accept a switch only to a newer session (start time) or after the transport reported a reconnect.
- **Severity:** Low

### 5.25 Stopping a game clears the config before the controllers stop
- **Location:** `Modules/GameRPG/Root/GameRoot.swift:612-640`
- **What:** `performStopGame` sets `gameConfig = .empty` before `masterController.stop()` and network teardown.
- **Why:** A message built or sent in between (a pending audio receipt, a debounced value update) goes out under the empty/random master id; a player that was not yet told about the stop may adopt it.
- **Action:** Stop controllers and transports first, then reset the config.
- **Severity:** Low

### 5.26 Group events with timestamps >300 s in the future are dropped silently
- **Location:** `Modules/GameRPG/Model/GameNetworkModel+Shape.swift:70-83`
- **What:** `isPlayerGroupEvent` depends on a skew check of the sender-provided timestamp.
- **Why:** A player whose clock is >300 s ahead (manual time, tvOS) has every roll, pin move and Space transform dropped with only a debug log.
- **Action:** Use receive time for the skew decision, or log at warning level and surface "clock out of sync".
- **Severity:** Low

### 5.27 Envelopes with `counter <= 0` skip de-duplication and relay reservation
- **Location:** `Modules/GameRPG/Model/GameMessagePipeline.swift:105-108,222-223`; `Controller/MasterController+NetworkStoreDelegate.swift:93-112`
- **What:** No dedup key is formed for counter ≤ 0.
- **Why:** A buggy or malicious peer can resend the same group event with counter 0; the master processes and relays every copy to all players — N× amplification.
- **Action:** Reject counter ≤ 0 from remote peers (only local/synthetic events use 0), or derive a key without the counter.
- **Severity:** Low

### 5.28 A targeted message to a player with no route is sent to everyone; small answers to `.file` requests go through the Journal
- **Location:** `Modules/GameRPG/Network/GameNetworkController+Delivery.swift:92-95,105-111`
- **What:** `sendPlayer(_:toPlayer:)` falls back to broadcast when the target has no route; an answer to a `.file`-origin request always goes through `publishAsset` even when it carries no asset (ack, value, list).
- **Why:** One-recipient answers (Character rejection, value packages, companion data) reach the whole session, filtered only by each receiver's `targetId` check; control answers become slower Journal attachments retained in the Journal history.
- **Action:** Drop (and log) a targeted message whose target has no route; use `publishAsset` only for `carriesAsset` data and Messenger for the rest.
- **Severity:** Low

### 5.29 Presentation counters are assigned before the export await, so a later show can overtake an earlier one
- **Location:** `Modules/GameRPG/Controller/MasterController+Messaging.swift:63-72,223-257,262-342`; `Network/GameNetworkController+Delivery.swift:32-64`
- **What:** The counter is assigned, then the package export is awaited; a large Map followed by a small Photo can reach the wire in reverse counter order.
- **Why:** The player tolerates it by design (stale presentations discarded at `PlayerController+MessageProcessing.swift:181-197`); the only cost is bandwidth for the discarded large package. Recorded so nobody "fixes" it with ordering machinery.
- **Action:** Optionally skip sending a package whose presentation is already superseded.
- **Severity:** Low

### 5.30 On a player, Stop Game leaves the session but keeps all session state live until `.invalidated` arrives
- **Location:** `Modules/GameRPG/Network/GameNetworkController.swift:141-153`; `SharePlay/RPGSharePlayController+SessionLifecycle.swift:278-293,345-372`
- **What:** The player path only calls `leaveGroupSession()`, unlike the master path which calls `reset()`.
- **Why:** Messenger, send queue, deferred retries and Journal loads (up to 180 s) keep running; inbound messages keep routing to whatever `playerDelegate` exists; a quick restart can receive the old session's traffic and its late lost-connection teardown. *(reasoned)*
- **Action:** Call `reset()` on the player stop path too, reporting teardown first if the delegate needs it.
- **Severity:** Low

---

## 6. Security

Players are trusted (peer import policy gaps are won't-fix, CODE_AUDIT_Folder §6.1/§6.2), so the items below are about one trusted-but-buggy/malicious participant wedging, spoofing or exhausting *other* devices. Nothing was found that exposes secrets: 147 `privacy: .public` log uses were checked and none expose a join code, passcode, PSK or endpoint; names and error descriptions are `.private`; join codes/session ids live in the Keychain.

### 6.1 Any SharePlay participant can impersonate the master to other players
- **Location:** `Modules/GameRPG/Controller/PlayerController+MessageProcessing.swift:43-63,68-84,195`; `Controller/PlayerControllerModel.swift:82-87,95-101,136-144`; `Network/GameNetworkController+SharePlayDelegate.swift:71-124`
- **What:** On SharePlay a player accepts master authority from fields inside the message (`sender.isMaster`, `sender.id == config.master.id`, `masterId`); every participant learns these from master broadcasts. The Messenger participant id is only recorded (`noteSharePlayMasterParticipant`), never used to reject a message.
- **Why:** A forged master message returns `.changed` and triggers `ready()` (the victim re-sends availability lists and Character, once per forged message); with a very large counter it makes `shouldApplyMasterState` refuse every later real master state; it sets `lastPresentation` so `isCurrentPresentation` rejects every real presentation as stale. One participant can freeze what the others see until they lose the connection, and `ready()` becomes an amplifier.
- **Action:** Once the master participant is known, accept master-claiming messages only from it; treat a different participant as a rejoin only after the previous master was seen leaving (or require a fresh full broadcast at counter 1); cap how far a counter may jump; rate-limit the `ready()` re-announce. (Same participant-vs-claim reconciliation as §5.3.)
- **Severity:** Medium

### 6.2 Journal attachments are fully loaded before the size check
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+JournalAttachments.swift:224-250`; `Network/GameNetworkController+SharePlayDelegate.swift:31-36`
- **What:** `attachment.load(Data.self)` materialises the whole blob (`:232`) and only then compares to `GameLimits.maximumMessageBytes` (`:247`); `shouldLoadFile` returns `true` for any non-master sender, so the GM loads every player attachment unconditionally.
- **Why:** A participant publishing a multi-GB attachment makes the GM's device — and every other player's, see §7.1 — allocate all of it; on iPad/Vision Pro that can trigger a jetsam kill mid-game. Messenger, by contrast, has stream, cumulative and per-minute caps.
- **Action:** Reject before loading using a declared size in the metadata (missing/oversized declaration = reject); add the per-sender byte budget Messenger already has.
- **Severity:** Medium *(incomplete fix of CODE_AUDIT_23 §6.5)*

### 6.3 A player can make the master show any master-library item by id
- **Location:** `Modules/GameRPG/Controller/MasterController+FileMessageSupport.swift:106-122`; `Controller/FileBackedModuleAccess.swift:83`; generic contribution path in `Controller/MasterController+AudioMessages.swift`
- **What:** `showPlayerContribution` takes a bare reference from a player and calls `show(for:)` on the master's copy if sharing is enabled for that module; PDF sharing is always on (`isSharingEnabled` returns true). The reference is not checked against items the player owns or was told about.
- **Why:** Any id a player has seen (a master availability list, an earlier presentation) makes the GM screen and every player switch to that item — a presentation hijack that can push GM-only prep material (a once-listed PDF or photo) to the table. Not an import gap.
- **Action:** Accept a player "show" only for items in that player's announced availability or that it just contributed; put PDF behind a real feature flag like the other modules.
- **Severity:** Medium

### 6.4 The player's fallback listener accepts any code holder as master during reconnect
- **Location:** `Modules/GameRPG/Network/PlayerNetworkController.swift:267-292,576-606`; `Controller/PlayerController+NetworkStoreDelegate.swift:57`
- **What:** After the master connection drops the player resets the master pin (`master.type = .notSet`) and its fallback listener accepts any PSK-authenticated connection; the first self-consistent master broadcast becomes the authority. The PSK identity is constant and the key derives from the 4-digit code.
- **Why:** During every reconnect window any other player at the table (who knows the code) can become that player's master. A new angle on the open join-code decision; the previous master id is not used as a preference.
- **Action:** Keep the previous master id while reconnecting and accept only it from the fallback listener unless the user explicitly re-joins.
- **Severity:** Low

### 6.5 The player's fallback listener throttles only per source endpoint
- **Location:** `Modules/GameRPG/Network/PlayerNetworkController.swift:576-606`
- **What:** The connection-attempt throttle is per source, with no overall cap on concurrent pending handshakes.
- **Why:** A device cycling source ports can keep a (weaker, e.g. tvOS) player busy with PSK handshakes during its reconnect window; low impact.
- **Action:** Add an overall cap on concurrent pending handshakes.
- **Severity:** Low

---

## 7. Performance

### 7.1 Every player downloads every other player's Journal contribution, then discards it; late joiners load them first, one at a time
- **Location:** `Modules/GameRPG/Network/GameNetworkController+SharePlayDelegate.swift:31-36` (`shouldLoadFile` `true` for any non-master sender), `:138-144` (dropped because `masterDelegate` is nil); `SharePlay/RPGSharePlayController+JournalAttachments.swift:118-127,154-173,178-180,302-319`
- **What:** On a player device non-master attachments are fully loaded and then thrown away in `routeSharePlayFileUpdate`. The first snapshot with loads (the late-join batch) loads strictly in sequence with the master's attachments sorted last; a later publication of any item in that batch waits for the whole batch task.
- **Why:** Traffic over the FaceTime relay grows with N² (join-time portrait photos, contributed files); a late joiner sees the master's current map/photo only after all of those loads finish or hit their 30–180 s deadlines.
- **Action:** On a device without a master delegate answer `false` for non-master attachments; in the join batch skip attachments the device will not route and key later waits per item, not on the whole batch.
- **Severity:** Medium

### 7.2 The master rebuilds the full package for every player's request
- **Location:** `Modules/GameRPG/Controller/MasterController+MapMessages.swift:43-63`; `Controller/MasterController+FileMessageSupport.swift:55-80`; asset-answer path in `MasterController+WeatherMessages.swift`
- **What:** When a map is shown each player requests the package and each request runs a full export inside the serial master pipeline; SharePlay `publishAsset` de-duplicates only after the export finished.
- **Why:** With N players a large map is exported N times in a row, and every other master message (pins, dice, acks) waits behind them — lag exactly when the GM switches scenes.
- **Action:** Cache the most recent exported package per (item, version) for the duration of a presentation and reuse it for every requester; an edit changes the version and invalidates it.
- **Severity:** Medium

### 7.3 Per-chunk overhead and ~3× peak memory on large SharePlay receives
- **Location:** `Modules/GameRPG/SharePlay/SharePlayPackageReceiver.swift:15-22,30-31,85-90,256-282`; `SharePlay/RPGSharePlayController+ChunkedTransport.swift:460-470`; `Root/GameRootModel.swift:86-92`
- **What:** The chunks, the reassembled `Data` and the Base64-decoded model coexist (~190 MB for a max-size message); `SharePlayPackageReceiver`/`PackageMessageList` are `@Observable` and mutated for every 64 KB chunk though no view observes them; `scheduleNextExpiration` cancels and recreates a sleeping task per chunk (~1,000 per 64 MB stream); `GameRootModel`'s private counters are observable too.
- **Why:** Memory pressure on constrained devices plus avoidable observation-registrar and main-actor task churn during large transfers.
- **Action:** Release chunks while reassembling (or decode from the chunk sequence); drop `@Observable` or mark internals `@ObservationIgnored`; use one long-lived expiry loop that sleeps until the earliest deadline.
- **Severity:** Low

### 7.4 Each received LAN frame takes four actor hops through `DelegateBox` actors
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:8-26`; `Player/PlayerNetworkController.swift:8-26`
- **What:** connection actor → box actor → main → box → main, only to hold a weak delegate reference.
- **Why:** Added latency per frame for no isolation benefit.
- **Action:** Store the weak delegate on a `@MainActor` holder or pass a `@MainActor @Sendable` closure capturing weak self.
- **Severity:** Low

### 7.5 Inbound byte budget keeps an entry for every sender that ever sent
- **Location:** `Modules/GameRPG/SharePlay/SharePlayInboundByteBudget.swift:13-37`
- **What:** Entries are cleared only on reset, not when a sender's count returns to zero.
- **Why:** Map grows by one entry per participant in a long session; negligible, hygiene.
- **Action:** Remove an entry when its count reaches zero.
- **Severity:** Low

---

## 8. SwiftUI / UI

_No findings._ The scope is transport/controller code; the only SwiftUI in scope is `SetupViews/SharePlayButton.swift`, which was read and judged OK. The `swiftui-expert-skill` pass was therefore not run. (Two UI-adjacent consequences are recorded elsewhere: silent version mismatch §5.9, and "clock out of sync" §5.26.)

---

## 9. Dead code / duplication / refactor

Clean results first: **zero** `TODO/FIXME/HACK/XXX/#warning`, **zero** `#if false`, zero commented-out code blocks, zero `print/debugPrint/NSLog` in scope.

### 9.1 Journal publication queue: public retire/supersede/current API is only used by tests
- **Location:** `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift:274-338`
- **What:** `currentAttachment(for:)`, `supersedePresentation(for:)`, `retireCurrentAttachment(for:priority:remove:)` each have a `NetworkModules` and a `SharePlayJournalSlot` overload (six entry points); only `SharePlayPackageTransportTests` (lines 1054, 1097, 1105, 1137, 1212, 1213) and `SharePlayJournalLedgerTests` (293-303) call them.
- **Why:** ~65 lines of public surface exist only to be tested and keep retire/supersede looking like live features.
- **Action:** Remove the six entry points, keep the internal `currentAttachments` bookkeeping, and rewrite the tests through `enqueue`/`cancelAll`.
- **Severity:** Medium

### 9.2 Test affordances living in production types
- **Location:** `Modules/GameRPG/Controller/LogGameController.swift:32-37,66-70,163-169,184-189`; `Controller/MasterController+MapMessages.swift:20-32`; `Controller/MasterController+AudioMessages.swift:171-179`; `Master/HostingSessionStore.swift:105-109`; `Controller/PlayerControllerModel.swift:50-55`; `SharePlay/SharePlayJournalLedger.swift:61-63` (`publication(for:)`)
- **What:** ~12 members are documented "Test affordance"/"(for tests)"; production reads their counterparts instead. `maxPlayers` and `logModels` have no production reference at all.
- **Why:** Production surface grows only for tests and the audit-reference comments hide that it is dead for the app.
- **Action:** Move to `#if DEBUG` or a test-support extension; have tests call `CharacterRejectionPolicy` and the `origin:` overload directly; delete pass-throughs.
- **Severity:** Low

### 9.3 Preview and mock fixtures compile into release builds and sit in the wrong folders
- **Location:** `Modules/GameRPG/Controller/PreviewData.swift:1-319`; `Modules/GameRPG/Model/MockData.swift:1-71`
- **What:** A 319-line fixture file in `Controller/` and a 71-line `PreviewModifier` in `Model/`, neither under `#if DEBUG`.
- **Why:** Preview support ships in the release framework and blurs the MVC folder rule.
- **Action:** Move to a `Preview/` folder or wrap in `#if DEBUG`, matching other modules' `MockData`.
- **Severity:** Low

### 9.4 Space-transform stamping and local-apply logic is copied between master and player send paths
- **Location:** `Modules/GameRPG/Controller/MasterController+Messaging.swift:198-211,288-304,316-325`; `Controller/PlayerController+SendMessages.swift:62-64,122-134,148-160`
- **What:** Both `send` functions compute a causal timestamp for `.update/.spaceTransform` on a `.space` item, bail on `nil`, then optimistically `applySpaceTransform` with the stamped envelope; the master also re-wraps the player's payload in `game(message:)`.
- **Why:** "Stamp causally, apply locally, ignore if rejected" lives in two places; a Space ordering change must be made twice.
- **Action:** A small helper on the Space controllable ("prepare outgoing transform" + apply-after-envelope); both paths call it; keep the master-only canonical re-wrap in the master.
- **Severity:** Medium

### 9.5 Group-event shape is checked three times with slightly different rules
- **Location:** `Modules/GameRPG/Controller/PlayerController+SendMessages.swift:176-186`; `Model/GameNetworkModel+Shape.swift:32-42,60-83`; `Controller/MasterController+ProxyRouting.swift:30,37-93`
- **What:** `relayProxyGroupEvent` spells "dice roll, mapPin/Map, spaceTransform/Space" like `isPlayerGroupEvent`; `processAsProxy` re-tests the same three cases, each ending in an identical relay call; the proxy router also spells `.audioList || .photoList || .pdfList || .spaceList` (190-character condition) although the Shape file holds the canonical list-subtype set (and the proxy copy checks only subtype, not subtype+item-type).
- **Why:** A fourth group event or list module means edits in several places.
- **Action:** Express the group-event kind once (an enum derived from the shape) used by the relay filter and the proxy router with one relay tail; add a subtype-only `isReportList` next to `isReportListEnvelope`.
- **Severity:** Medium

### 9.6 `RPGMessageActionType.screen` is never sent
- **Location:** `Modules/CoreRPG/Model/RPGMessageActionType.swift:9`; `Modules/GameRPG/Controller/MasterController+ProxyRouting.swift:30`
- **What:** `screen = 300` has no producer in `Modules/` or `Sources/`; non-test references are the debug description and the proxy drop filter.
- **Why:** A wire value from removed screen-routing machinery implying unsupported behaviour.
- **Action:** Keep the raw value reserved for decoding old peers, drop the proxy special case and mark it deprecated (or remove it if no compatibility is wanted).
- **Severity:** Low

### 9.7 Audio delivery retry is configured to zero retries, leaving dead branches
- **Location:** `Modules/GameRPG/Controller/MasterControllerModel.swift:28-33,172-182`
- **What:** `maximumAudioDeliveryRetries = 0`, so `recordAudioDeliveryFailure` always returns `false` and `isAudioDeliveryAbandoned` is true after the first failure.
- **Why:** Counter, key type and retry-branch callers are machinery for a switched-off behaviour.
- **Action:** Collapse to a "failed once, give up" set per item+player, or document the constant as an intentional knob.
- **Severity:** Low

### 9.8 Master and player listener-restart logic is the same pattern written twice
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:345-369,373`; `Player/PlayerNetworkController.swift:555-573`
- **What:** Both do "check attempt, take `GameLimits.networkRestartDelay(forAttempt:)`, increment, cancel old task, sleep, restart if state matches"; the master also resets on a healthy run via a local 120 s `listenerHealthyDuration`, the player does not.
- **Why:** Backoff/health-reset rules can drift; the constant lives outside `GameLimits`.
- **Action:** Extract a `ListenerRestartScheduler` value type owning the counter, healthy-run reset, delay and cancel-and-replace task; move the constant to `GameLimits`.
- **Severity:** Medium

### 9.9 Player Table/Weather handlers repeat the reveal/store skeleton of `handleFileBackedMessage`
- **Location:** `Modules/GameRPG/Controller/PlayerController+Table.swift:8-52`; `PlayerController+Weather.swift:8-65`; `PlayerController+FileSupport.swift:15-58`
- **What:** All guard on acknowledgements and master sender, switch on `.reveal/.store/.update`, ask the module whether the item is held, and answer `response(isSuccess:true, requestData:…)`; the file-backed one already takes hooks.
- **Why:** The "held or request it" protocol has three implementations; a fix to the ok/request decision must be found three times.
- **Action:** Generalise into a "held item" handler parameterised by hold check and reveal/store receivers; Table and Weather keep only their special cases.
- **Severity:** Medium

### 9.10 `configureGroupSession` is 256 lines
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:175-430`
- **What:** One function sets up five concurrent streams inline (state, participants, messages, journal attachments, join) plus TabletopKit deferral and logging.
- **Why:** The only function over 100 lines in scope; the loops are independent but cannot be read or tested alone.
- **Action:** One `makeXTask(groupSession:sessionId:)` builder per stream; keep `configureGroupSession` as the orchestrator.
- **Severity:** Medium

### 9.11 Oversized SharePlay files
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift` (730), `+ChunkedTransport.swift` (661), `SharePlayJournalPublicationQueue.swift` (614), `+SessionLifecycle.swift` (542), `SharePlayDeferredDeliveryQueue.swift` (509)
- **What:** Five files exceed 500 lines; `RPGSharePlayController.swift:17` explicitly keeps one file "given the size" and uses MARKs (`20`, `53`, `418`).
- **Why:** Support types (lines 20-417) dominate the controller file; the queue files hold several unrelated types each.
- **Action:** Move the types between MARK 53 and 418 into their own files; split the publication queue at its MARKs (Slot, policy/admission, completion bookkeeping, queue); split the deferred queue into queue, retry-loop helpers and budget.
- **Severity:** Medium

### 9.12 Oversized network and message files with mixed concerns
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift` (622, MARKs `257,340,490,547`), `Master/MasterNetworkController.swift` (572, MARKs `95,220,269,312,421`), `Controller/MasterController+Messaging.swift:30-330`, `Controller/PlayerController+MessageProcessing.swift:105-201` (`prepareForProcessing`, 97 lines), `Controller/MasterController+PresentationReplay.swift:18-109`, `Controller/MasterController+ValueMessages.swift:12-102`
- **What:** Both controllers already have extension-style MARK sections; `+Messaging` holds show, replay, version bookkeeping, player-message entry and both `send` overloads (~70-line `send`); `prepareForProcessing` interleaves counter, feature, sender and statistics gates.
- **Why:** Hard to navigate; the Space duplication (§9.4) is buried in `send`; a new feature flag edits the middle of a long function.
- **Action:** Move the delegate/listener/browser extensions into `+ConnectionDelegate`/`+Listener`/`+Browser`; split `+Messaging` into `+Show`, `+PlayerMessages`, `+Send`; turn the gates into an ordered list of named predicates.
- **Severity:** Low

### 9.13 Constants and size ceilings scattered outside `GameLimits` and inconsistent with it
- **Location:** `Modules/GameRPG/SharePlay/SharePlaySingleQueuePackageSender.swift:79-86`; `SharePlayInboundByteBudget.swift:15-16`; `SharePlayPackageReceiver.swift:41`; `RPGSharePlayController.swift:529-533`; `+JournalAttachments.swift:24-25,215`; `Network/ConnectionThrottleTracker.swift:55-57`; `Network/ConnectionAttemptThrottle.swift:25-38`; `Master/MasterNetworkController.swift:316-320,373,523`; `Player/PlayerNetworkController.swift:77`; delay arrays at `SharePlayDeferredDeliveryQueue.swift:357-371`
- **What:** ~30 limits and timeouts are defined per type. `GameLimits.swift:7-30` states limits "must stay identical wherever they are enforced" yet holds only some; the SharePlay ceilings (64 MB message, 128 MB outstanding, 512 MiB per-sender inbound) are not derived from `maximumMessageBytes` (100 MB) or `maximumQueuedBytes` (300 MB); the 250 ms/1 s/2 s delays appear as two near-identical arrays.
- **Why:** The relationships (a transport must admit at least one `maximumMessageBytes`; cf. §5.1, §5.11) are not enforced anywhere, so changing one value can silently break another.
- **Action:** Group by area in `GameLimits` (`SharePlay`, `LAN`, `Throttle`), express SharePlay ceilings as functions of `maximumMessageBytes`, add one test asserting the relationships.
- **Severity:** Medium

### 9.14 Empty platform conditionals in five PlayerController files
- **Location:** `Modules/GameRPG/Controller/PlayerController.swift:6-8`, `PlayerController+Control.swift:9-11`, `PlayerController+NetworkStoreDelegate.swift:11-13`, `PlayerController+MessageProcessing.swift:6-8`, `PlayerController+SendMessages.swift:8-10`
- **What:** Each holds an empty `#if os(macOS) / #else / #endif` block (5 instances).
- **Why:** Leftovers of removed platform code suggesting a split that no longer exists.
- **Action:** Delete all five.
- **Severity:** Low

### 9.15 Leftover "repair" vocabulary from the removed repair machinery
- **Location:** `Modules/GameRPG/SharePlay/SharePlayDeferredDeliveryQueue.swift:128-135` (case `.repair`),`:329-331` (`isRepair`),`:220-240,268,300`; `Controller/MasterController+ProxyRouting.swift:132-134,207` (`proxyRepairData`); `SharePlay/SharePlayJournalLedger.swift:21-26`; `SharePlayJournalPublicationQueue.swift:31`; `Controller/PlayerController+Weather.swift:46`; `PlayerController+Map.swift:172`; `MasterController+NetworkStoreDelegate.swift:274` (24 occurrences)
- **What:** Answers to a participant's request are still called "repair" in names and comments.
- **Why:** The name implies the removed handshake and could invite rebuilding it.
- **Action:** Rename to "requested delivery"/"answer" (`.answer`, `isAnswer`, `proxyAnswerData`); update comments. Do not re-add any routing, admission or repair logic.
- **Severity:** Low

### 9.16 Stale and historical comments dominate doc comments
- **Location:** 294 `CODE_AUDIT*` references in scope, e.g. `Modules/GameRPG/Model/GameLimits.swift:7-60`, `SharePlay/SharePlayDeferredDeliveryQueue.swift:134-152`, `SharePlay/RPGSharePlayController+SessionLifecycle.swift:417-427`, `SharePlay/SharePlayJournalLedger.swift:18-32`; comments naming deleted types at `Network/PhysicalIdentityDenylist.swift:10-18` (`SharePlayPlayerJournalAdmission`) and `Network/ConnectionAttemptThrottle.swift:42-47` (`SharePlayMapRecoveryTracker`); wrong mechanism named at `SharePlay/GameShareStateModel.swift:6-10` (`withObservationTracking` vs the actual `Observations` sequence, `RPGSharePlayController.swift:614-631`)
- **What:** Many comments narrate history ("Before this case existed…") or point at audit sections instead of the current contract; some name types that no longer exist anywhere in `Modules/`, `Sources/` or `Tests/`.
- **Why:** Audit documents get archived; the narrative hides the current rule and points at removed machinery.
- **Action:** One short statement of the current rule per symbol; move history to git/audit docs; keep an audit reference only where the reason is not obvious.
- **Severity:** Low

### 9.17 `GroupActivityManager` is a wrapper whose only job is two calls
- **Location:** `Modules/GameRPG/Table3D/GroupActivityManager.swift:8-23`
- **What:** The visionOS-only `@Observable` class calls `sharePlayController.setup(...)` in `init` and `detachNetworkCoordinator()` in `deinit`; `tabletopGame` is a never-mutated `var`; its single user is `@State private var activityManager` in `GameTableView+VisionOS.swift:24`; its doc comment describes `RPGSharePlayController.setup`.
- **Why:** Object lifetime is used to run a side effect.
- **Action:** Make `tabletopGame` a `let`, or fold attach/detach into `RPGSharePlayController` called from the view lifecycle and delete the class.
- **Severity:** Low

### 9.18 Duplicated `SharePlayJournalSlot` / `NetworkModules` overload pairs in queue and ledger
- **Location:** `Modules/GameRPG/SharePlay/SharePlayJournalLedger.swift:61-139`; `SharePlayJournalPublicationQueue.swift:274-338`
- **What:** The ledger's five methods each repeat `module:isPlaylist:itemId:version:counter:` and rebuild the slot; the queue repeats every method for both key types.
- **Why:** `(module, isPlaylist)` *is* a slot; adding a slot dimension touches ~10 signatures.
- **Action:** Take a `SharePlayJournalSlot` (and an item/version key) everywhere; build it once at the `RPGSharePlayController` call site.
- **Severity:** Low

### 9.19 `.local` message origin is never produced, so its branches are dead
- **Location:** `Modules/GameRPG/Controller/PlayerController+MessageProcessing.swift:41,208,266,284`; `Network/GameNetworkController+Delivery.swift:96-100`; `Controller/PlayerController+NetworkStoreDelegate.swift:87-89`
- **What:** The co-located player receives through `.direct(nil)`, so nothing creates `.local`; its authority rule (masterId only), "don't forward" and "don't answer" rules never run.
- **Why:** Either those rules are needed and missing for the GM's own player (it answers upstream and forwards to proxies; statistics count local traffic as network traffic) or the branches are dead and misleading.
- **Action:** Decide: deliver the co-located player's messages as `.local`, or remove the branches.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

- **One owner per queue.** The message pipeline (§3.1), the Messenger send queue (§5.12) and the Journal add path (§3.2, §5.10) all have "work runs inside whoever happened to trigger it". Prefer long-lived, controller-owned worker tasks that are cancelled only by stop/reset; producers enqueue and signal.
- **Every system call that can hang gets a deadline.** `journal.add`, `journal.remove`, `messenger.send`, metadata loads and teardown waits (§3.2, §3.10, §3.12, §5.12). `SharePlayAttachmentLoadRetry.load(deadline:)` already has the right shape — reuse it.
- **Define transport ceilings once, as relationships.** One place that states message max, Journal budget, Messenger raw limit and LAN frame limit, plus a test that each transport can carry at least one maximum message *or* answers `.failed` (§5.1, §5.11, §9.13).
- **Always answer a request.** Under request/answer a missing answer is indistinguishable from slowness; make "no answer" an explicit code path (`.failed`/"unavailable") on the master side as it already is on the player side (§5.4, §5.5).
- **Bind identity to the transport, not the payload.** Sender id, master claim and `.file`-origin envelopes should be reconciled with the Messenger participant / Journal attachment origin (§5.6, §6.1).
- **Don't let UI retention drive protocol correctness** (§5.8): correlation state belongs in its own bounded table.
- **Log every drop.** Decode failure, encode failure, unsupported version, no-route targeted send, `.queueFull` — all currently silent or debug-only (§5.9, §5.19, §5.28).
- **Trim narrative comments** and keep the removed machinery's vocabulary out of the code (§9.15, §9.16).

---

## 11. What was NOT audited

- Module-specific content handlers beyond their message plumbing (Map/Photo/Pdf/Space/Audio/Weather/Table import/export internals, CRDT merge correctness) — see the per-module audits in `Docu/`.
- The Table3D rendering/TabletopKit/RealityKit code except `GroupActivityManager.swift` and `GameTableModel+Seating.swift` (see `Docu/CODE_AUDIT_3dTable.md`).
- GameRPG statistics, BattleRound, Browser, GameCenter, ExternalScreen, Search, SetupViews (other than `SharePlayButton`), and all other GameViews — none are part of the message/SharePlay stack.
- Apple's `GroupActivities`, `Network` and `TabletopKit` internals; the PSK/TLS handshake itself (accepted risk; the 4-digit join code remains an open product decision, CODE_AUDIT_15 §13).
- **Runtime verification.** No SharePlay session, FaceTime relay, real Journal, multi-device LAN game or Instruments trace was exercised in this environment. Findings marked *(reasoned)* or with an inferred consequence are code-reading conclusions; §5.1, §5.2, §3.1 had their key lines re-opened (see §12) but none were reproduced.
- Test coverage and tests-as-code (read only to learn intended behaviour); localization wording; build settings/entitlements.
- SwiftUI view quality (§8).
- Whether the iOS-Simulator-only clean build hides warnings that only appear for macOS, tvOS or visionOS slices (`#if os(...)` code, e.g. the visionOS-only `GroupActivityManager`, `+VisionOSTemplate`, `+TableCoordination`). Only the iOS Simulator build was run for compiler ground truth.

---

## 12. Verification

No Critical findings were assigned. Each High was verified by the reviewer opening the cited lines:

- **§3.1** — `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:150-180`: `received` awaits `processMessages()` in the caller's task; the `Task.isCancelled` guard (`:172-176`) requeues only when cancellation is seen *before* `process`. `:229-257`: a `CancellationError` thrown during `handle`/`send` is caught at `:251-252` and returns `false`, after which `processed(success:false)` (`:178`) clears the in-hand event without restoring it. `Model/GameMessagePipeline.swift:244-265`: `next()` removes the event; `processed` only clears bookkeeping (`requeueCurrentOnCancellation`, `:275-287`, is the sole restore path). `:204-211`: `handOffBacklog` confirms the drain is spawned from whichever task cancels.
- **§5.1** — `Modules/GameRPG/Network/GameProtocol.swift:50-74`: `handleOutput` builds the header from `messageLength` and writes the body with no comparison to `maximumMessageByteCount`; `:98-107`: the receive side fails the connection with `EMSGSIZE` above the limit. `Network/ConnectionController.swift:171-195`: the only outbound check compares `queuedOutboundBytes + content.count` to `maximumOutboundQueuedBytes` and only when `queuedOutboundBytes > 0` ("one frame always goes out, whatever its size"). `Model/GameLimits.swift:13,28` and `CoreRPG/App/ByteLimits.swift:21`: 100 MB frame limit vs 256 MiB source files; grep shows `maximumMessageBytes` is used on send only by the SharePlay paths (`SharePlayJournalPublicationQueue.swift:113`, `+JournalAttachments.swift:247`). The reconnect-loop consequence is inferred from the replay design, not reproduced.
- **§5.2** — `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:386-415`: on `enqueueChunkedSend(... allowDeferral:false)` failure, `scheduleDeferredPromotionIfNeeded()` is called (`:410`); `:417-438`: `deferredPromotionTask` is set to `nil` immediately before `promoteDeferredDeliveries()` (`:435-436`), the delay for a passed `retryNotBefore` is ≤ 0 so no sleep happens (`:426`), and each pass logs "Chunked queue full: ignored message" (`:313`) because `allowDeferral` is false. Each iteration hops through a new `@MainActor` task, so the main loop is not blocked — this is churn plus log flood, not a hard hang. Severity stays High as a regression with unbounded duration (the length of a full-queue transfer).

Medium findings cited as "verified" by the reviewer's reading: **§6.2** — `+JournalAttachments.swift:224-250` loads into `Data` (`:232`) before the size comparison (`:247`).

All other findings rest on the audit agents' line-level reads; where a failure was inferred rather than traced it is marked *(reasoned)* in the finding.
