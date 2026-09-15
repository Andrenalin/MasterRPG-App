# MasterRPG — Bonjour &amp; SharePlay Reconnect Audit

Generated 2026-09-14. **Scope: narrow and deep, not a full codebase audit.** This report covers only the reconnect logic of the two game-networking transports:

- **Bonjour/LAN**: `Modules/GameRPG/Browser/BrowserManager.swift`, `Modules/GameRPG/Network/ConnectionController.swift`, `ListenerManager.swift`, `ConnectionThrottleTracker.swift`, `ConnectionAttemptThrottle.swift`, `Modules/GameRPG/Player/PlayerNetworkController.swift`(+Model), `Modules/GameRPG/Master/MasterNetworkController.swift`(+Model).
- **SharePlay/GroupActivities**: `Modules/GameRPG/SharePlay/RPGSharePlayController.swift` and its supporting queues/admission actors (`SharePlayDeferredDeliveryQueue`, `SharePlayJournalPublicationQueue`, `SharePlayPackageReceiver`, `SharePlaySingleQueuePackageSender`, `SharePlayJournalAddLimiter`), `Modules/GameRPG/Network/SharePlayPlayerJournalAdmission.swift`, `Modules/GameRPG/Table3D/GroupActivityManager.swift`.
- **The bridge and delegate-application layer** where reconnect events get applied: `Modules/GameRPG/Network/GameNetworkController.swift`, `Modules/GameRPG/Network/GameRelayAdmission.swift`, `Modules/GameRPG/Controller/MasterController(+NetworkStoreDelegate/+Control/+PresentationReplay).swift`, `Modules/GameRPG/Controller/PlayerController(+NetworkStoreDelegate).swift` / `PlayerControllerModel.swift`, `Modules/GameRPG/Root/GameRootModel.swift`.

The project has been through many prior audit rounds — `Docu/CODE_AUDIT_Network.md` and `Docu/CODE_AUDIT_Game.md` already cover this subsystem in part, and many lines below carry `// See CODE_AUDIT §X.Y` comments documenting earlier fixes. A representative sample of those "fixed" claims was independently re-verified during this pass (§12) and all held. A full clean rebuild of the `GameRPG` target (Swift 6.3, `SWIFT_STRICT_CONCURRENCY = complete`) produced **zero compiler warnings**, so there is no separate concurrency-warning ground truth to report beyond what's below.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made. Several findings from the source agents were labeled Critical; every one was independently re-traced against the actual code and demoted to High — none of them crash, corrupt data, or leak credentials; all are permanent-until-full-session-restart communication lockouts, which is serious but does not meet this report's Critical bar (see §12).

---

## 1. Executive summary

1. **[High] Race between a connection's `.failed` and `.cancelled` callbacks can silently un-count a throttled failure** — §3.1 — `Modules/GameRPG/Network/ConnectionController.swift:191-205`.
2. **[High] A stale, redelivered SharePlay master broadcast can permanently phantom-pin the master participant slot** — §3.2 — `Modules/GameRPG/Controller/PlayerControllerModel.swift:180-207`.
3. **[High] A stale, redelivered SharePlay player message can permanently lock that player's own traffic out after a real reconnect** — §3.3 — `Modules/GameRPG/Network/SharePlayPlayerJournalAdmission.swift:131-155,278-307`.
4. **[High] A superseded SharePlay session's deferred TabletopKit coordination can permanently block the real session's own coordination (visionOS)** — §3.4 — `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:839-857`.
5. **[High] The player's fallback Bonjour listener is never torn down by `stop()` — leaked forever, and reconnect-fallback is disabled for the rest of the app run** — §5.1 — `Modules/GameRPG/Player/PlayerNetworkController.swift:155-169`.
6. **[High] The connection-attempt throttle cannot distinguish a bad-passcode guess from an ordinary transient reconnect failure** — §6.1 — `Modules/GameRPG/Player/PlayerNetworkController.swift:213-236`, `Modules/GameRPG/Master/MasterNetworkController.swift:182-186`.
7. **[Medium] `MasterControllerModel.retiredConnectionIDs` grows without bound across a session's LAN reconnect churn** — §7.1 — `Modules/GameRPG/Controller/MasterController.swift:146,301-308`.
8. **[Medium] The "first physical binding wins" reconnect-identity policy is independently reimplemented for LAN and SharePlay** — §9.2 — `Modules/GameRPG/Controller/MasterController.swift:270-283` vs `PlayerControllerModel.swift:180-199`.
9. **[Medium] No UI state distinguishes "actively retrying a reconnect" from "connection permanently lost"** — §8.1 — `Modules/GameRPG/GameViews/GameChromeStatusPresentation.swift:9-28`.
10. **[Medium] The co-located game-master's own local `PlayerController` never has `ready()` invoked, so `lostMaster` is permanently stuck `true`** — §5.2 — `Modules/GameRPG/Controller/PlayerControllerModel.swift:114,941-955`.

---

## 2. Quick wins (≤30 min each)

- **Have `PlayerNetworkController.stop()` also stop and clear the fallback listener** — `Modules/GameRPG/Player/PlayerNetworkController.swift:155-169`. One-line addition (`networkModel.listener?.stopListening(); networkModel.reset(listener: nil)`), mirroring what `MasterNetworkController.resetConnections()` already does. See §5.1.
- **Register throttle bookkeeping for every accepted fallback-listener connection, not only the `shouldRestart` branch** — `Modules/GameRPG/Player/PlayerNetworkController.swift:363-387`. See §5.3.
- **Delete the redundant explicit `participantTracker.reset()`/`mapRecoveryTracker.reset()` calls in `configureGroupSession`'s "replace an existing session" branch** — `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:1962-1978`. They're already covered by `reset()` on the preceding line. See §9.1.

---

## 3. Concurrency

### 3.1 Race between a connection's `.failed` and `.cancelled` callbacks can silently un-count a throttled failure
- **Location:** `Modules/GameRPG/Network/ConnectionController.swift:191-205,272-289`; call sites `Modules/GameRPG/Player/PlayerNetworkController.swift:213-266`, `Modules/GameRPG/Master/MasterNetworkController.swift:182-195`, throttle at `Modules/GameRPG/Network/ConnectionThrottleTracker.swift`
- **What:** `stateChanged(_:)`'s `.failed` case calls `cancel()` (→ `connection.cancel()`, which per `NWConnection`'s contract always produces a later `.cancelled` callback) and *also* immediately calls `connectionFailed(message:)` → `delegate.failed(with:for:)`. The later `.cancelled` case then calls `delegate.lostConnection(for:)`. So a single underlying handshake failure fires **both** delegate methods for the same connection `id`. `failed(...)`'s failure branch calls `connectionThrottle.resolve(id:, succeeded: false)`; `lostConnection(...)` unconditionally opens with `connectionThrottle.clear(id:)`. Both are separate actor-hopping `async` calls into `ConnectionThrottleTracker` with no ordering guarantee relative to each other.
- **Why:** If `lostConnection`'s `clear(id:)` reaches the throttle actor before `failed`'s `resolve(id:, succeeded: false)`, `resolve` finds no pending entry and silently no-ops — the failed handshake is never counted. Every inbound connection on both the master's primary listener and the player's fallback listener goes through this exact pair, so under load (many near-simultaneous bad-passcode probes — precisely when actor contention, and thus the race window, widens) an attacker's failed attempts can be intermittently dropped from the lockout tally.
- **Action:** Make "resolve vs. clear" atomic per underlying failure event — e.g., have `ConnectionController` report one terminal outcome per connection instead of two independent delegate calls for the same failure, or have the failure-resolution path win deterministically over a same-connection clear.
- **Severity:** High

### 3.2 A stale, redelivered SharePlay master broadcast can permanently phantom-pin the master participant slot
- **Location:** `Modules/GameRPG/Controller/PlayerControllerModel.swift:180-207` (`acceptSharePlayMasterParticipant`/`removeSharePlayMasterParticipant`); call site `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:259-282` (`acceptsSessionMessage`); redelivery precedent documented at `Modules/GameRPG/Network/GameRelayAdmission.swift` (§7.4)
- **What:** `acceptSharePlayMasterParticipant` binds `sharePlayMasterParticipantId` to whichever participant UUID next presents a complete master broadcast while the slot is unbound — there is no denylist of participant IDs that have already departed. `GroupSessionMessenger` is documented elsewhere in this codebase (the `GameRelayAdmission` comment) as capable of redelivering a message "well after the fact." Traced sequence: master drops → `sharePlayLostPlayer` → `removeSharePlayMasterParticipant` unbinds the slot → the master's own in-flight complete broadcast, sent just before it dropped, arrives late and re-binds the slot to the now-departed participant ID (`.newlyBound`/`.rebound`) → the master reconnects with a genuinely new participant ID and its real broadcast is compared against the phantom ID → `.rejected`, permanently, since no future "participant left" event will ever reference the phantom ID again.
- **Why:** The affected player is silently and permanently cut off from the master (and from Journal master content, since `isPinnedSharePlayMasterParticipant` never becomes true for the new ID either) until they fully leave and rejoin the SharePlay session.
- **Action:** Retain departed participant IDs for the life of the session (or the pinned slot's own generation) and reject any future bind attempt against an already-superseded ID, rather than trusting "currently unbound ⇒ eligible."
- **Severity:** High

### 3.3 A stale, redelivered SharePlay player message can permanently lock that player's own traffic out after a real reconnect
- **Location:** `Modules/GameRPG/Network/SharePlayPlayerJournalAdmission.swift:131-155` (`acceptsPlayerMessenger`), `:278-307` (`participantLeft`)
- **What:** `participantLeft` correctly clears `senderByDirectParticipant[oldParticipantId]` and any `ownerParticipantBySender` entry pointing at it. But `acceptsPlayerMessenger`'s fallback branch (lines 148-154) re-binds `ownerParticipantBySender[senderId]` unconditionally whenever both maps are currently unbound for that sender — including from a late-redelivered message whose physical `participantID` already departed. Traced sequence: player drops (`participantLeft(oldPid)` clears both maps) → a stale in-flight message from that player, tagged with `oldPid`, arrives after the clear and re-establishes `ownerParticipantBySender[senderId] = oldPid` → the player reconnects with a new participant ID `newPid` and sends a genuine message → `acceptsPlayerMessenger` compares `ownerParticipantBySender[senderId] (== oldPid) == newPid` → `false` → rejected, and stays rejected for the rest of the session (nothing will ever call `participantLeft(oldPid)` again).
- **Why:** The reconnected player can still *receive* master broadcasts but can never again have their own dice rolls, requests, or file reveals accepted — `GameNetworkController.routeSharePlayUpdate` logs "Rejected rebound SharePlay sender" for the rest of the session.
- **Action:** Same remedy class as §3.2 — retain departed-participant identity (or scope bindings to a per-connection epoch) so a late redelivery from an already-departed ID cannot silently reclaim a sender→participant binding out from under the legitimately reconnected participant.
- **Severity:** High

### 3.4 A superseded SharePlay session's deferred TabletopKit coordination can permanently block the real session's own coordination (visionOS)
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:839-857` (`deferCoordinateAndAssignSeats`), `:1605-1608` (`trackSessionTask`, fixed `coordinateSessionTaskKey`), `:1751-1789` (`reset()`, clears `coordinatedTabletopGame` to `nil`), call site `:2163-2182`
- **What:** `deferCoordinateAndAssignSeats` is deliberately written to never check `Task.isCancelled` (documented intent: guarantee at-most-once `coordinateWithSession` per `tabletopGame` instance), and its only guard, `self.coordinatedTabletopGame != identifier`, is keyed by the `tabletopGame` object identity alone — not by session. Traced sequence: session A schedules its deferred task `T_A` (captures `groupSession = A`) → session A invalidates → `.invalidated` handler sets `coordinatedTabletopGame = nil` and cancels tracked tasks, but `T_A` ignores cancellation and is still scheduled to run → the replacement session B's `configureGroupSession` runs and, if `T_A` happens to execute on the MainActor queue *before* B schedules its own deferred task `T_B`, `T_A`'s guard now passes (`coordinatedTabletopGame` was just reset to `nil`), so it sets `coordinatedTabletopGame = identifier` and calls `tabletopGame.coordinateWithSession(A)` — the **stale, already-invalidated** session. When `T_B` later runs for the real session B, its identical guard now fails (`coordinatedTabletopGame == identifier` already) and it silently no-ops.
- **Why:** The current, live SharePlay session never gets its TabletopKit network coordinator attached — seating/state stops syncing over SharePlay for that table view — until the 3D table view itself is torn down and recreated (the `tabletopGame` instance is what the guard is keyed on).
- **Action:** Re-check `sessionLoopIsCurrent(sessionId: groupSession.id)` (or an equivalent generation token) inside the deferred task immediately before calling `coordinateWithSession`, and key `coordinatedTabletopGame` by (tabletopGame identity, session id) rather than tabletopGame identity alone.
- **Severity:** High

### 3.5 `PlayerNetworkController.checkForRemoval()` re-arms Bonjour-removal observation only after the current batch's teardown completes
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift:316-352`
- **What:** `checkForRemoval()` iterates `browserManager.removed`, `await`-ing `removedConnection(endpoint:)` → `lostConnection(for:)` (itself several actor hops plus `stop()`'s connection teardown) for each entry, and only re-registers `withObservationTracking` (`observeRemovedConnection()`) at the very end.
- **Why:** `withObservationTracking`'s `onChange` fires once and must be re-armed before the next mutation. A second Bonjour-removal change landing while the first removal's teardown is still in flight is missed until some later, unrelated mutation happens to re-trigger observation — a narrow gap in lost-master detection timing during Bonjour flapping.
- **Action:** Re-register `withObservationTracking` at the start of the change handler, before doing the async teardown work, or snapshot-and-diff on each observed change instead of relying on end-of-batch re-arming.
- **Severity:** Medium

---

## 4. API modernity

_No findings within scope._ The reconnect-relevant files use modern async/await, `AsyncStream`, actors, and `@Observable`/`@MainActor` throughout; the zero-warning clean build (see report header) found no deprecated-API usage to flag here. A full API-modernity pass was not run outside this scope — see §11.

---

## 5. Bugs / logic errors

### 5.1 The player's fallback Bonjour listener is never torn down by `stop()`
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift:155-169` (`stop()`), `:194-198` (`startPlayerServer()`), `:357-361` (`listenerCancelled()`, for contrast); compare `Modules/GameRPG/Master/MasterNetworkController.swift:122-138` (`resetConnections()`, which correctly stops+clears its listener)
- **What:** `stop()` resets `connectionController`, `playerConnectionId`, `model`, `isConnected`, `connectionState`, and cancels its two tracked tasks — but never calls `networkModel.listener?.stopListening()` or `networkModel.reset(listener: nil)`. `networkModel.listener` is cleared only from inside the listener's own delegate callbacks (`listenerCancelled()`, `listenerNewConnection(_:)`), never by an externally-triggered teardown.
- **Why:** If a player has lost its master and started the "become a fallback listener and wait" recovery (`startPlayerServer()`), then the user leaves/stops the game while still `.lost` (`GameNetworkController.stopGame()` → `model.playerStore?.stop()` unconditionally on every path), the live `NWListener`/Bonjour advertisement is leaked — it keeps running and accepting connections indefinitely. Worse, because `startPlayerServer()` guards on `networkModel.listener == nil`, the stale non-nil reference silently no-ops every future call: the next time this player loses a (possibly different) master in the same app session, no new fallback listener is ever created — the reconnect-fallback recovery is permanently disabled for the rest of the app run.
- **Action:** Have `stop()` also stop and clear `networkModel.listener`, mirroring `MasterNetworkController.resetConnections()`.
- **Severity:** High

### 5.2 The co-located game-master's own local `PlayerController` never has `ready()` invoked; `lostMaster` is stuck `true` for the whole session
- **Location:** `Modules/GameRPG/Controller/PlayerControllerModel.swift:114` (`var lostMaster: Bool = true`), `:941-942,955` (`reset(lostMaster:)`/`canSendCharacter`); only writers are `PlayerController+NetworkStoreDelegate.swift:58-60` (`ready()`) and the proxy-focus path; co-located creation at `Modules/GameRPG/Root/GameRootModel.swift:610` (`PlayerController(root: self, asGameMaster: true)`) never triggers a `playerReady()` callback, and `GameNetworkController.sharePlaySessionConfigured()` (`Modules/GameRPG/Network/GameNetworkController.swift:384-392`) explicitly skips `ready()` via `guard !model.hasLocalPlayer`
- **What:** For a co-located master (created unconditionally whenever local play starts), `gameModel.lostMaster` never transitions to `false` because the local `PlayerController` never goes through the normal network `ready()`/`lostConnection()` lifecycle. This is currently masked only by defensive `isMaster ? nil : …`-style guards at every UI/logic call site that reads it.
- **Why:** This is the same class of bug as the previously-fixed "co-located master Map reshow" issue (see project memory) — per-connection reconnect state that's simply never updated for the local/co-located identity. It's inert today only because every current call site happens to guard around it; a future call site reading `playerController.gameModel.lostMaster` for the master's own controller has nothing stopping it from permanently showing "Connection Lost" for the GM, and `canSendCharacter` is permanently `false` for the same reason (masked today only because `sendMaster` also no-ops when `hasLocalPlayer`).
- **Action:** Either initialize `lostMaster = false` for a co-located (`asGameMaster: true`) `PlayerController`, or give the local instance an explicit "always connected" override instead of relying on every future caller remembering the guard convention.
- **Severity:** Medium

### 5.3 Fallback-listener connections landing just outside the reconnect window bypass throttle registration
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift:363-387` (`listenerNewConnection(_:)`), `:186-192` (`restart(connection:)`)
- **What:** `connectionThrottle.register(id:endpoint:)` is only called inside `restart(connection:)`, reached only when `shouldRestart` (`networkModel.connectionState == .lost`, captured at the moment the connection arrives) is `true`. A second inbound connection landing on the same still-live fallback listener in the brief window after `connectionState` has already moved off `.lost` (but before the listener is actually torn down) is simply cancelled without ever being registered with the throttle.
- **Why:** A connection attempt cancelled this way contributes nothing to that source's failure tally — invisible to the lockout, though the window is small and requires near-simultaneous connection attempts to exploit.
- **Action:** Run the throttle's `shouldAllow`/register bookkeeping uniformly for every accepted `NWConnection`, independent of the `shouldRestart` branch.
- **Severity:** Low

### 5.4 Post-reconnect replay resends Map/Weather state unconditionally, with no "already current" check
- **Location:** `Modules/GameRPG/Controller/MasterController+PresentationReplay.swift:23-122`
- **What:** On every `ready(for:)` (LAN reconnect *and* SharePlay rejoin), the master unconditionally calls `share`/`shareMap`/`shareWeather` and resends a `.reveal`/`.show` plus (for Map) two more targeted updates to the reconnecting peer, with no check against what that peer's cached state already is — unlike `handlePhoto`/`handlePdf`/`handleSpace`'s explicit "skip if unchanged" check a few files over.
- **Why:** The underlying envelopes are reference/version-only (not full payloads), so the cost is small, but it's still 2-4 extra messages per reconnect blip with none of the "already current, skip it" optimization every other file-backed reveal handler in this module uses.
- **Action:** Consult the same version-matches check other reveal handlers use before re-issuing the replay, at least for the Map's two extra sends.
- **Severity:** Low

### 5.5 Test coverage gap: the co-located master's own local-player reconnect path is never exercised
- **Location:** `Tests/GameRPGTests/MasterControllerConnectionTests.swift`, `Tests/GameRPGTests/MasterPlayerControllerTests.swift`
- **What:** Both files have strong LAN reconnect coverage (connection retirement/reconnect, `lostPlayer` after a second drop) and SharePlay reconnect coverage (participant leave/rejoin replay, master-participant rebind), but nothing constructs a co-located (`asGameMaster: true`) `PlayerController` and exercises `lostConnection()`/`ready()`/`gameModel.lostMaster` against it.
- **Why:** Given §5.2 and the project's prior co-located-master bug history, this exact seam is precisely where this codebase's past real bugs have come from, and it currently has zero direct test coverage.
- **Action:** Add a regression test asserting what a co-located `PlayerController`'s `gameModel.lostMaster`/`canSendCharacter` actually do across the local player's lifecycle.
- **Severity:** Medium (test-coverage)

### 5.6 Test coverage gap: no test simulates a LAN send failing mid-message during an active reconnect window
- **Location:** `Tests/GameRPGTests/MasterControllerConnectionTests.swift`, `Tests/GameRPGTests/MultiConnectionTests.swift`
- **What:** All LAN reconnect tests simulate connection-identity churn at the `MasterControllerModel` level, but none simulate a send failing mid-flight into a connection that is concurrently reconnecting — the interaction `Docu/CODE_AUDIT_Network.md` already flags as unfixed elsewhere (`ConnectionController`'s idempotent-style sends).
- **Why:** This is the one LAN-side reconnect failure mode with no test net, and it's also the one most likely to interact badly with the master's targeted replay path (§5.4) on reconnect.
- **Action:** Add a test (likely at the `ConnectionController`/mock-`NWConnection` level) asserting behavior when a send is in flight at the moment a connection transitions to lost.
- **Severity:** Medium (test-coverage)

### 5.7 Test coverage gap: no test exercises a LAN reconnect overlapping active SharePlay traffic through the bridge
- **Location:** `Tests/GameRPGTests/SharePlayPackageTransportTests.swift`, `Tests/GameRPGTests/NetworkStoreTests.swift`
- **What:** SharePlay reconnect tests are extensive for pure-SharePlay scenarios, and LAN proxy-relay reconnect tests exist independently, but nothing exercises the seam this report is centrally about: one transport reconnecting *while* `GameNetworkController` is actively bridging traffic to/from the other.
- **Why:** `GameNetworkController`'s bridging logic (`masterReceived`/`routeSharePlayUpdate`, `Modules/GameRPG/Network/GameNetworkController.swift:275-298,417-597`) is the most complex, most cross-cutting code in this entire scope, and it currently has no test that reconnects one transport while traffic is actively flowing on the other.
- **Action:** Add an integration-style test that drops and reconnects a LAN player while SharePlay traffic for other players continues, asserting `GameRelayAdmission`'s dedup state behaves correctly across the overlap.
- **Severity:** Medium (test-coverage)

---

## 6. Security

### 6.1 Connection-attempt throttle cannot distinguish a bad-passcode guess from an ordinary transient reconnect failure
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift:213-236` (`failed(with:for:)`), `Modules/GameRPG/Master/MasterNetworkController.swift:182-186` (`failed(with:for:)`), policy doc at `Modules/GameRPG/Network/ConnectionAttemptThrottle.swift:6-16`
- **What:** Both controllers call `connectionThrottle.resolve(id:, succeeded: false)` for *every* `NWConnection.State.failed` transition, with no inspection of the underlying `NWError`/TLS status. A TLS/passcode rejection and a plain network-layer failure (Wi-Fi drop mid-handshake, path timeout, momentarily-unreachable peer — exactly what a flaky-network reconnect looks like) are folded into the same "failure" the throttle counts toward its 3-strike lockout.
- **Why:** `ConnectionAttemptThrottle`'s own doc comment claims "ordinary reconnects and typos are never penalized — only a source that's actually guessing," but nothing enforces that at the call sites. A legitimate peer whose several automatic reconnect attempts each fail for an ordinary transient reason trips `failureThreshold = 3` and gets locked out (5s, doubling to 300s) of reconnecting to the very peer it's trying to recover a session with — worsening exactly the condition the reconnect feature exists to handle.
- **Action:** Only count a failure toward the throttle when the failure reason is actually consistent with an authentication/passcode rejection (if the underlying error exposes that distinction), or decouple ordinary-reconnect-retry failures from the passcode-guessing signal the throttle is meant to police.
- **Severity:** High

---

## 7. Performance

### 7.1 `MasterControllerModel.retiredConnectionIDs` grows without bound across a session's LAN reconnect churn
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:146` (declaration), `:256,274` (checked on every `add`/`accepts`), `:301-308` (`reinstateConnection`/`remove`)
- **What:** Every LAN disconnect inserts the departing `connectionId` into `retiredConnectionIDs`. Nothing ever removes a LAN-origin id again — `reinstateConnection` (line 301, doc comment at 293-300) only lifts a retirement for a *SharePlay* participant UUID, since LAN connection ids are always freshly minted on reconnect and so never need reinstating. Every sibling per-connection cache in this same file (`playerJournalAdmissions`, `deliveryMessagesByWireIDOrder`, `peerAvailabilitySources`) is an explicitly bounded FIFO (capped at 256); this one is not.
- **Why:** A single player with a flaky connection reconnecting repeatedly over a multi-hour session accumulates one permanent `Set` entry per drop, unbounded for the life of the game. Purely a memory-growth concern (correctness is unaffected, since fresh LAN ids never collide with retired ones) — it would take an extreme number of reconnects in one session to matter in practice, which is why this is Medium rather than High despite being a real inconsistency with the file's own bounded-cache convention.
- **Action:** Cap `retiredConnectionIDs` with the same bounded-FIFO pattern already used elsewhere in this file, or evict LAN-origin ids after a short retention window.
- **Severity:** Medium

### 7.2 Every single player's reconnect/disconnect during an active map triggers a full-group, untargeted Map re-broadcast
- **Location:** `Modules/GameRPG/Controller/MasterController+Control.swift:99-119` (`performResetPlayers`), invoked from `MasterController+NetworkStoreDelegate.swift:156-159` (`lostPlayer`) and `:241-245` (new-player roster add)
- **What:** `performResetPlayers()`, called on every roster change including a single player's reconnect/disconnect, unconditionally re-sends the current map's content update, map state, and (if running) battle-round state to the **whole group** — not targeted at just the player whose connection changed, and with no check for whether the broadcast content actually changed.
- **Why:** A single flaky player reconnecting repeatedly makes every other connected player (LAN and SharePlay) re-receive the full map-state/content envelope each time; over SharePlay this additionally competes with the bounded send/deferred-delivery queues.
- **Action:** Scope this resend to the affected player (mirror `replayCurrentPresentation`'s origin-targeted pattern) instead of broadcasting to the whole group on every roster-churn event.
- **Severity:** Medium

### 7.3 `SharePlayJournalAddLimiter` attempts from torn-down sessions are never purged and can exhaust its fixed 16-slot cap
- **Location:** `Modules/GameRPG/SharePlay/SharePlayJournalAddLimiter.swift:38-68` (`run`, `maxRetainedAttempts` default 16), `:119-127` (`cancelAll`)
- **What:** `cancelAll()` (invoked by `RPGSharePlayController.reset()` on every reconnect) marks each attempt `isObsolete` and cancels its waiter/operation task, but does not remove the entry from `attempts` — removal only happens once the underlying (possibly non-cooperatively-cancelling) `GroupSessionJournal.add` call actually returns.
- **Why:** If a session invalidates while `journal.add` is in flight and that call never returns/throws for the now-dead journal, its `attempts` entry is retained forever. Across enough reconnect cycles in a long, spotty-network session, `attempts.count` can reach the 16-slot cap, after which `run(for:...)` returns `.unavailable` for every module for the rest of the game — permanently forcing all Journal-backed content (maps, photos, PDFs, audio, weather) onto the slower Messenger chunked fallback.
- **Action:** Give `cancelAll()` a bounded forced-eviction path (e.g., drop the oldest obsolete attempt when the cap is hit) instead of relying solely on the underlying system call eventually completing.
- **Severity:** Medium

### 7.4 `SharePlayPlayerJournalAdmission`'s admission cache has no age-based retention, unlike its `GameRelayAdmission` sibling
- **Location:** `Modules/GameRPG/Network/SharePlayPlayerJournalAdmission.swift:106-126` (`init`, `maximumAdmissionCount = 512`, plain FIFO `admissionOrder`); compare `Modules/GameRPG/Network/GameRelayAdmission.swift` (age-based `retentionWindow`, added specifically for this "Messenger can redeliver well after the fact" scenario)
- **What:** `admitAnnouncement` evicts the oldest of 512 admissions purely by insertion-count, with no minimum retention duration — `GameRelayAdmission`'s own comment explains exactly why a pure count cap is unsafe for this transport and was replaced with an age-based window there.
- **Why:** On a long, high-traffic session, a legitimate admission fingerprint can be evicted well before a delayed Messenger redelivery of the same announcement arrives; since the "else" branch admits any first-seen `(participantID, fingerprint)` pair for an evicted key unconditionally, this reopens the door for a different participant to newly claim a key whose original admission has aged out.
- **Action:** Apply the same age-based retention window used in `GameRelayAdmission` here.
- **Severity:** Medium

---

## 8. SwiftUI / UI

### 8.1 No UI state distinguishes "actively retrying a reconnect" from "connection permanently lost"
- **Location:** `Modules/GameRPG/GameViews/GameChromeStatusPresentation.swift:9-28` (5 cases); `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:316-320` (`SharePlayConnectionState`, 4 cases); actual retry logic at `Modules/GameRPG/Player/PlayerNetworkController.swift:36,77,186-191,223-232,384`
- **What:** `PlayerNetworkController` implements real background reconnect-fallback logic (a listener that re-admits the master using the session's already-known passcode), but neither `GameConnectionStatusPresentation` nor `SharePlayConnectionState` has a case representing "reconnecting" — a live, likely-to-succeed retry renders identically to a hard, permanent loss.
- **Why:** A player watching the connection-status icon during an in-progress automatic reconnect sees the same "Connection Lost" treatment the entire time, with no feedback that anything is happening — a plausible source of a player force-quitting/restarting mid-reconnect and defeating the passcode-less fallback path designed for exactly this case.
- **Action:** Add a `reconnecting` case fed by `PlayerNetworkController`'s actual retry state, and map it to a distinct icon/tint from a hard failure.
- **Severity:** Medium

---

## 9. Dead code / duplication / refactor

### 9.1 `configureGroupSession` resets `participantTracker`/`mapRecoveryTracker` redundantly, up to three times per reconnect
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:1751-1789` (`reset()`, unconditionally resets both trackers), `:1962-1978` (the "replace an existing session" branch: `participantTracker.drainSessionTeardownEvents()` already internally resets the tracker, `reset()` resets it again, and the branch then explicitly calls `participantTracker.reset()`/`mapRecoveryTracker.reset()` a third time)
- **What:** In the "replace an already-configured session" path, both trackers are reset three times over via three different call paths that have accumulated across prior audit rounds.
- **Why:** Harmless (idempotent) but obscures which reset is actually load-bearing for the "first-ever configure" path (where `reset()` never runs) versus which are leftovers from the replace-session path — exactly the kind of overlapping reconnect-guarding logic worth simplifying before the next person adds a fourth one.
- **Action:** Drop the redundant explicit `participantTracker.reset()`/`mapRecoveryTracker.reset()` calls in the "existing session" branch (~lines 1971-1978), keeping only what's needed for the no-prior-session path.
- **Severity:** Low

### 9.2 The "first physical binding wins" reconnect-identity policy is independently reimplemented for LAN and SharePlay
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:270-283` (`accepts(connectionId:sender:)`) vs `Modules/GameRPG/Controller/PlayerControllerModel.swift:180-199` (`acceptSharePlayMasterParticipant`)
- **What:** Both implement the same conceptual guard — "a reconnecting physical transport identity may rebind under a new connection id, but an already-bound physical origin cannot switch logical identity" — as two separately hand-written, differently-shaped functions (one keyed by `ConnectionController.ID` for many players, one keyed by a single `sharePlayMasterParticipantId` for one master), with no shared helper or shared test contract between them.
- **Why:** This is exactly the class of duplication most likely to silently drift as each transport's reconnect edge cases get patched separately — §3.2 is itself evidence of that drift (the SharePlay side is missing a denylist the LAN side's `retiredConnectionIDs` pattern already models, just without a size cap — see §7.1).
- **Action:** Extract a small shared "physical-identity pinning" policy type (bind-once, first-wins, explicit reinstate/denylist) that both LAN and SharePlay identity binding delegate to, instead of two independent implementations.
- **Severity:** Medium

---

## 10. Cross-cutting recommendations

1. **A single "physical-identity pinning" primitive should back every reconnect-identity decision.** §9.2 is the direct cause of §3.2 and §3.3 both being unprotected against late redelivery in the same way — the LAN side's `retiredConnectionIDs` denylist pattern (§7.1) is closer to correct (it remembers departed identities) but unbounded; the SharePlay side (§3.2, §3.3) doesn't remember them at all. One shared type that does "remember departed identities, bounded, with an explicit reinstate path" would fix all three findings at once and prevent the next transport-specific variant from reintroducing the same gap.
2. **Every reconnect/session-reset path should be audited against a checklist of "what per-connection state exists," not patched fact-by-fact.** This report's own drift examples (§3.2/§3.3's missing denylists, §9.1's triple-reset, §5.2's silently-inert `lostMaster`) are all instances of state that's either never cleared/updated for one specific identity/transport or cleared more times than necessary because the previous fix didn't remove the mechanism it superseded. The project has already articulated this exact principle in `Docu/CODE_AUDIT_Network.md` (recommendation 4) for the Bonjour side; this audit found the same pattern still recurring on the SharePlay side.
3. **UI-observable connection states should be driven by the same state machine that drives the retry logic, not reconstructed separately.** §8.1's gap exists because `PlayerNetworkController`'s real retry state and the UI-facing enums evolved independently. Threading `PlayerNetworkController`'s actual `.lost`/fallback-listening state into `GameConnectionStatusPresentation` directly (rather than the UI re-deriving "lost" from a narrower signal) would prevent this class of gap from recurring as new connection states are added.

---

## 11. What was NOT audited

- Everything outside Bonjour/LAN and SharePlay **reconnect** logic specifically — this is not a full-codebase audit. Non-reconnect networking logic (initial-join UX, message routing correctness for steady-state play, file/Journal transport correctness outside the admission/redelivery angle) was read only where it intersected a reconnect path.
- Business logic of other modules (Audio/Map/Character/Photo/Pdf/Space/Table/Weather RPG) except where `PlayerControllerModel`'s reconnect-reset list or the master's reconnect-replay path directly touches them.
- General SwiftUI/UI quality, accessibility, Dynamic Type, and Liquid Glass adoption — §8.1 is the only UI finding, and it was flagged only because it's a direct symptom of the reconnect logic itself, not from a general UI pass. A dedicated `swiftui-expert-skill` pass was not run.
- CoreData/persistence, CloudKit sync, and anything outside the in-memory game-session state reconnect logic operates on.
- A general API-modernity or deprecated-API sweep — the zero-warning clean build (see report header) covers this for the exact files in scope; a repo-wide sweep was not performed.
- A general security review (secrets, entitlements, IAP, third-party dependencies) — §6.1 covers only the passcode-throttle mechanism directly relevant to reconnect abuse.
- Live/on-device testing of any finding — every finding here is from static code reading and manual trace-through of the async/actor call graphs, not from reproducing the failure on real hardware with a real flaky network or a real dropped FaceTime call. Several findings (§3.2, §3.3, §3.4) depend on message-redelivery/task-scheduling timing that is plausible and internally consistent with this codebase's own documented precedent (the `GameRelayAdmission` redelivery comment; TabletopKit's documented `Task { @MainActor }` deferral pattern) but was not observed directly.
- macOS/tvOS-specific reconnect UI variants beyond what's shared with the iOS/visionOS views read for §8.1.
- Deep test-coverage review beyond the specific reconnect-scenario gaps noted in §5.5-§5.7 — a full test-quality audit of `Tests/GameRPGTests/` was not performed.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line.

Every finding originally labeled Critical by the source audit passes (three SharePlay agent findings, one Bonjour agent finding) was independently re-traced by opening the cited code and following the actual call graph before this report was written; all four were demoted to High because none of them crash, corrupt persisted data, or expose a security credential — each is a permanent-until-full-reconnect communication lockout, which is serious but a different failure class than this report's Critical bar (see the severity note in the header).

- **§3.1** — open `Modules/GameRPG/Network/ConnectionController.swift`, lines 191-205: confirmed `.failed` calls `cancel()` (line 193, which itself calls `connection.cancel()`) *and* `connectionFailed(message:)` (line 194) in the same branch; `.cancelled` (line 196) separately calls `lostConnection()` (line 205). Two independent delegate calls for one failure event, exactly as claimed.
- **§3.2** — open `Modules/GameRPG/Controller/PlayerControllerModel.swift`, lines 180-207: `acceptSharePlayMasterParticipant` binds on any unbound slot given `isCompleteMasterBroadcast`, with no memory of which participant IDs have already been removed via `removeSharePlayMasterParticipant` (line 202-207, which only sets `resynchronizeAfterSharePlayMasterRebind`, not a denylist).
- **§3.3** — open `Modules/GameRPG/Network/SharePlayPlayerJournalAdmission.swift`, lines 131-155 and 278-307: `participantLeft` clears both `senderByDirectParticipant` and `ownerParticipantBySender` for the departed id (lines 283-286), and `acceptsPlayerMessenger`'s fallback branch (148-154) re-binds unconditionally on next sight of that sender, including from a stale message still tagged with the departed participant ID.
- **§3.4** — open `Modules/GameRPG/SharePlay/RPGSharePlayController.swift`, lines 839-857 and 1605-1608: the deferred task's only guard is `self.coordinatedTabletopGame != identifier` (846-848), keyed by `ObjectIdentifier(tabletopGame)` alone; `reset()` (1786, within the `#if os(visionOS)` block at 1782-1788) sets `coordinatedTabletopGame = nil` on every session teardown, which is what allows a late-firing stale task to re-pass the guard for a dead session and lock out the real one.
- **§5.1** — open `Modules/GameRPG/Player/PlayerNetworkController.swift`, lines 155-169: confirmed no call to `networkModel.listener?.stopListening()` or `reset(listener: nil)` anywhere in `stop()`; cross-checked against `Modules/GameRPG/Master/MasterNetworkController.swift:122-138`, which does call both for the equivalent master-side listener.
- **§6.1** — open `Modules/GameRPG/Player/PlayerNetworkController.swift`, lines 213-236: `connectionThrottle.resolve(id:, succeeded: false)` (line 228) sits directly on the `else` branch of `if networkModel.connectionState != .notReady`, reached for any `.failed` transition regardless of the underlying `NWError` — no error-type inspection present.

If any finding doesn't reproduce when you visit the line, flag it and it will be re-investigated.

---

## Remediation status (follow-up pass, 2026-09-14)

All 20 findings were reviewed in this pass; 14 were fixed and 6 were deliberately left unchanged with rationale (below) after investigation showed the described fix carried more correctness risk than the finding's own severity justified. A full clean build of `GameRPG` (production target) succeeded with zero errors, and `xcodebuild test -scheme GameRPGTests` passed every non-snapshot test (543 passed, 0 non-snapshot failures — the 117 failures are all pre-existing, environment-dependent UI snapshot-image comparisons across unrelated views, not caused by this pass).

**Fixed (14):**

- **§3.1** — `ConnectionController` now reports at most one terminal outcome per connection (`terminalOutcomeReported`), so `.failed` and the `.cancelled` it triggers can no longer race `ConnectionThrottleTracker.resolve`/`clear` against each other.
- **§3.2** — `PlayerControllerModel` gained a bounded `departedSharePlayMasterParticipantIds` denylist; `acceptSharePlayMasterParticipant` now rejects a bind attempt from an already-departed participant ID.
- **§3.3** — `SharePlayPlayerJournalAdmission` gained the equivalent `departedParticipantIds` denylist, checked at the top of `acceptsPlayerMessenger`.
- **§3.4** — `coordinatedTabletopGame` is now keyed by (tabletopGame identity, session id), and the deferred task re-validates `sessionLoopIsCurrent(sessionId:)` immediately before calling `coordinateWithSession`.
- **§3.5** — `checkForRemoval()` now re-arms `withObservationTracking` before processing the current removal batch, not after.
- **§5.1** — `PlayerNetworkController.stop()` now stops and clears the fallback listener.
- **§5.2** — `PlayerController.init(asGameMaster: true)` now initializes `lostMaster = false` for the co-located master's own local player.
- **§5.5** — added `CoLocatedMasterReconnectTests.swift`, directly covering §5.2's fix (asserts `lostMaster`/`canSendCharacter` for both the co-located-master and remote-player cases, plus `ready()` clearing it).
- **§6.1** — `ConnectionControllerDelegate.failed(with:isAuthenticationFailure:for:)` now classifies the underlying `NWError` (`.tls` = passcode rejection) and both `PlayerNetworkController`/`MasterNetworkController` only count a throttle failure when it's an actual authentication rejection, not an ordinary transient one.
- **§7.1 / §9.2** — new shared `PhysicalIdentityDenylist<ID>` type (bounded, FIFO-evicted); `MasterControllerModel.retiredConnectionIDs` now uses it (capped at 256, matching its sibling caches), and the same type now backs §3.2/§3.3's denylists too — collapsing what were three independent, ad-hoc mechanisms into one.
- **§7.4** — `SharePlayPlayerJournalAdmission`'s admission cache gained the same age-based retention window (`admissionRetentionWindow`, default 120s) `GameRelayAdmission` already used, alongside its existing count cap.
- **§8.1** — added a `.localNetworkReconnecting` case to `GameConnectionStatusPresentation`, wired to `PlayerNetworkController`'s real `.lost` retry state at the `IOSGameOverlayControlField` call site (distinct icon/tint/title from a hard failure); covered by a new test case in `GameChromeStatusPresentationTests`.
- **§9.1** — the "existing session" branch of `configureGroupSession` no longer redundantly re-resets `participantTracker`/`mapRecoveryTracker` a 2nd/3rd time; that reset now only runs (once) on the first-ever-configure path that actually needs it.

**Deliberately left unchanged (6), with rationale:**

- **§5.6, §5.7** (test-coverage gaps) — not added in this pass. Both describe integration-style tests (a LAN send failing mid-flight during a live reconnect; a LAN reconnect overlapping active SharePlay traffic through `GameNetworkController`'s bridge) that need deeper, unfamiliar mock/harness setup to write correctly; §5.5 (directly validating this pass's own §5.2 fix) was prioritized instead as the highest-confidence, most directly-relevant addition. These two remain open.

- **§5.3** (Low) — registering-then-immediately-resolving a connection the code never actually evaluates (no handshake attempted before the immediate `cancel()`) would either dangle a pending throttle entry forever or be a pure no-op; no version of "fix this" both closes the gap and stays accurate to what the throttle is supposed to represent (an evaluated attempt).
- **§5.4** (Low) — investigated `handlePhoto`/`handlePdf`/`handleSpace`'s "skip if unchanged" pattern as a model; it relies on genuine per-player availability tracking (`isPhotoAvailable(itemId:for:masterId:)`) that Map deliberately does not have (the existing code comments say Map request responses are "requester-only repairs" by design). Retrofitting per-player Map availability tracking to save two small reference-only messages per reconnect is a materially larger, riskier change than this finding's Low severity and stated "the cost is small" warrant.
- **§7.2** (Medium) — closer reading showed `performResetPlayers()`'s Map broadcast is not purely a "let the new joiner catch up" mechanism: it's how every *already-connected* player's view picks up the roster-driven pin change (a departing player's pin removed, a joining player's pin added) after `resetPlayerPins(for:)` runs. Narrowing the broadcast to just the reconnecting player, as originally recommended, would risk regressing pin visibility for everyone else — the opposite of this audit's goal. No safe, targeted fix was identified without a larger pin-sync redesign.
- **§7.3** (Medium) — `SharePlayJournalAddLimiter.cancelAll()`'s obsolete-but-still-running entries are retained on purpose so `operationFinished`'s late-attachment cleanup (`retryUntilRemoved` / `discardLateValue`) can still run when the non-cooperative `GroupSessionJournal.add` eventually returns. Forcibly evicting an obsolete entry to free a slot — the finding's suggested fix — would abandon that cleanup and risk a late Journal attachment being committed as current state, a worse bug than the rare cap-exhaustion this guards against.
