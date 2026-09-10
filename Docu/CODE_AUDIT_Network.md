# MasterRPG — PlayerController / MasterController / Network Communication Code Audit

Generated 2026-09-10. Scope: **68 Swift files, ~16,250 LOC** — the full master↔player message-handling and transport stack: every `MasterController+*.swift` and `PlayerController+*.swift` extension file plus the two root controllers (`Modules/GameRPG/Controller/*`), the low-level LAN transport (`Modules/GameRPG/Network/*`), the `Master`/`Player` network-controller bridges and `GameNetworkModel` wire model (`Modules/GameRPG/Master/*`, `Modules/GameRPG/Player/*`, `Modules/GameRPG/Model/GameNetworkModel*.swift`), and the full SharePlay/GroupActivities transport (`Modules/GameRPG/SharePlay/*`, `Modules/GameRPG/Table3D/GroupActivityManager.swift`). `Dead/` and any archived directories are excluded per repo convention; none were encountered in this scope.

This is a **follow-up, narrower-and-deeper** audit than `Docu/CODE_AUDIT_Game.md` (2026-08-22), which covered `MasterController.swift`/`PlayerController.swift` generically for concurrency/bugs/dead-code but explicitly listed "the network/transport layer proper — `ConnectionController`, `GameNetworkController`, `ListenerManager`, `JoinCodeStorage`, `SharePlay/*`" as **not audited**. This report closes that gap, and re-examines the controller layer itself through a single, specific lens the prior pass didn't apply: **can a message be silently lost, never processed, double-processed, or permanently stuck?** No code changes were made — this is read-only investigation.

Four parallel deep-read passes fed this report, one per architectural layer (Master-side message pipeline, Player-side message pipeline, LAN/Bonjour transport, SharePlay transport); every Critical claim and several High claims were independently re-verified by opening the cited lines. Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode.

---

> ## Fix-pass status (2026-09-10)
>
> All 24 findings below were reviewed and fixed, per the user's "fix all bug/findings" request. Summary:
>
> - ✅ **23 fixed outright** — §5.1, §5.3-§5.24.
> - 🟡 **1 partially fixed** — §5.2: the safe, self-contained half (a diagnostic warning logged when a stream actually expires incomplete, closing the "zero evidence this happened" gap) landed; the full bidirectional NACK/re-request protocol described in the finding was deliberately **not** attempted — it requires a new wire message type plus sender-side retention of already-sent chunk data for a grace window after send, a genuine cross-cutting protocol change to a file already at ~2,600 lines, that this pass judged too large and too unverifiable (no way to exercise real `GroupSessionMessenger` behavior in this environment) to bolt on safely in the same pass as everything else. Left as a scoped follow-up.
>
> Two of the fixes changed public-ish API shape and required matching test-file updates: `GameMessagePipeline.enqueue` now returns a `GameMessageEnqueueResult` enum instead of `Bool` (§5.14), and `SharePlayMapRecoveryTracker.shouldSuppressRecoveryRequest` gained a required `from participantId:` parameter (§5.4) — both updated at every call site, production and test. One new regression test was added per notable behavioral change (e.g. `queueFullRejectionIsDistinctFromDuplicate`, `requeueCurrentOnCancellationRestoresTheDequeuedEvent`, `mapRecoverySuppressionIsScopedToParticipant`).
>
> Full verification: a real (non-incremental) `xcodebuild build` of the `MasterRPG` scheme — **zero errors, zero warnings** — followed by `xcodebuild test -scheme MasterRPG -testPlan MasterRPG -only-testing:GameRPGTests`: **485 tests in 50 suites, 100% passing**, covering every module this pass touched (`CoreRPGTests` through `WeatherRPGTests` are also part of that plan and were exercised as collateral). The four `*SnapshotTests` targets and `MasterRPGUITests` were excluded from this run — not by choice but because `CoreRPGSnapshotTests` fails to compile in this environment for a reason unrelated to this pass (`Value of type 'some View' has no member 'navigationSceneRestorationEnabled'`, pre-existing, confirmed via `git diff` against files this pass never touched); the `MasterRPG` test plan already excludes all snapshot targets by design, which is what let the above 485-test run complete.

---

## 1. Executive summary

1. **[Critical] Ordinary game-state SharePlay messages (dice rolls, value/health updates, table changes, map pins) have no retry path and are silently dropped forever** under send-queue pressure or a single transient relay failure — §5.1 — `Modules/GameRPG/SharePlay/SharePlayDeferredDeliveryQueue.swift:244-269`, `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:1202-1324`.
2. **[High] Chunked SharePlay transport has no delivery acknowledgment** — a single package lost over the FaceTime relay just sits until a 120s timeout silently expires it, with no NACK or re-request — §5.2 — `Modules/GameRPG/SharePlay/SharePlayPackageReceiver.swift:160-178,219-225`.
3. **[High] LAN sends use `NWConnection`'s `.idempotent` completion**, so the app is never told a send failed mid-flight and can never selectively retry that specific message — §5.5 — `Modules/GameRPG/Network/ConnectionController.swift:92-106`.
4. **[High] A player's Map import/reveal failures are caught locally and swallowed** instead of propagating to the standard failure-ack + retry path every other module (Photo/Pdf/Space/Audio/Weather/Table) already uses — §5.19 — `Modules/GameRPG/Controller/PlayerController+Map.swift:103-122,140-149,215-225`.
5. **[High] A player relaying to its own downstream proxy-connected players stops relaying entirely** whenever the relaying device's own roster visibility or feature flags gate it out locally — the gate is checked before the forward, not instead of it — §5.20 — `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:285-354,397-411`.
6. **[High] A player's message-dedup memory is never cleared on reconnect** — replayed/rebuilt low-numbered messages after a master session restart can be silently treated as already-seen duplicates even though every other piece of per-connection state was just reset — §5.21 — `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:35-47`.
7. **[High] Messages rejected by transient, local-state gates are marked "processed" exactly like successfully-applied ones**, permanently blocking any later legitimate redelivery of that same message — §5.22 — `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:415-420`.
8. **[High] The LAN receive loop never detects a graceful peer half-close** — only hard transport errors — so a dead connection can sit open, silently swallowing further sends, until an OS-level keepalive eventually notices — §5.6 — `Modules/GameRPG/Network/ConnectionController.swift:185-216`.
9. **[High] The master's canonical Pdf/Photo/Space/Audio re-share handlers get no response at all** when the local export fails for any reason other than "item missing" (e.g. an undownloaded iCloud placeholder) — the requester is left waiting indefinitely — §5.12 — `Modules/GameRPG/Controller/MasterController+PdfMessages.swift:107-110` (+3 sibling modules).
10. **[High] Map full-package repair silently exhausts its 3 retries and answers the requester with nothing** on a persistent (non-transient) export failure — §5.11 — `Modules/GameRPG/Controller/MasterController+MapMessages.swift:205-242`.

---

## 2. Quick wins (≤30 min each)

- **Have the `.cancelled` connection-state case cancel the still-running receive task** (mirror what `cancel()` already does) — `Modules/GameRPG/Network/ConnectionController.swift:168-170` vs. `:78-82`. Prevents a pending receive callback from re-entering `process()`/`connectionFailed()` after teardown was already reported. See §5.9.
- **Call `scheduleDeferredPromotionIfNeeded()` on the capacity-guard-fail path of `promoteDeferredDeliveries`** for symmetry with the sibling "not ready yet" branch a few lines above — `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:1518-1537`. Cheap defense-in-depth against a future stuck deferred item. See §5.3.
- **Call `framer.markFailed(error:)` in `GameProtocol.handleOutput`'s body-write `catch`** instead of only logging, so a body-write failure fails the connection cleanly instead of potentially desyncing frame boundaries — `Modules/GameRPG/Network/GameProtocol.swift:50-66`. See §5.10.
- **Give `GameMessagePipeline.enqueue`'s capacity-exhausted path a distinct result from its true-duplicate path** (it already has the natural place to do this — `SharePlayDeferredDeliveryQueue.swift`'s own `SharePlayDeferredDeliveryAdmission` enum is the right pattern to copy) — `Modules/GameRPG/Model/GameMessagePipeline.swift:133-141`. Removes a standing "silent data loss looks identical to a log-noise duplicate" trap. See §5.14.

---

## 3. Concurrency

_No dedicated findings in this pass._ Each of the four reviews was explicitly briefed to check concurrency-flavored causes of message loss (unretained `Task { }` fire-and-forget sends, actor-isolation races on delegate callbacks, Task-cancellation swallowing in-flight work) as part of the lost-message hunt, not as a separate category. Two results worth recording here even though they're filed as logic bugs in §5 because the loss is the headline, not the concurrency mechanism:

- §5.3 (SharePlay deferred-promotion capacity race) and the cancellation-discard pattern in §5.15 are the only places a `Task`/cancellation interaction was found to plausibly (not confirmed reachable) affect message delivery.
- All other `Task { ... }` call sites checked across all four layers were confirmed retained in tracked properties or dictionaries that the relevant `reset()`/`cancelAll()` walks — no unretained fire-and-forget sends were found.
- `Docu/CODE_AUDIT_Game.md §3.1`'s previously-fixed delegate-witness `@MainActor`-isolation bug (the receive entry points in `GameNetworkControllerModel.swift`) was re-checked in passing here and remains fixed; nothing in this scope reintroduces that pattern.
- The build compiles with **zero warnings** in this scope (`xcodebuild -scheme MasterRPG build`, 2026-09-10) — but the build reused a warm `DerivedData` cache (0 `CompileSwift` invocations logged), so this is *not* a verified fresh clean-compile for this specific scope; treat it as corroborating, not conclusive. See §11.

## 4. API modernity

_No dedicated findings in this pass._ Out of scope by design — `Docu/CODE_AUDIT_Game.md §4` already covers API modernity for the controller layer, and this pass's four briefs were scoped specifically to message-loss correctness rather than deprecation sweeps. Nothing encountered along the way stood out as a modernity issue independent of a correctness finding already listed in §5.

---

## 5. Bugs / logic errors — message loss & correctness

### SharePlay transport

### 5.1 Ordinary SharePlay game-state messages have no retry path and are silently dropped forever
- **Location:** `Modules/GameRPG/SharePlay/SharePlayDeferredDeliveryQueue.swift:244-269` (`Key.key(for:)`, root cause); `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:1202-1324` (`enqueueChunkedSend`, both the capacity-exhausted branch ~1307-1322 and the post-send retryable-failure branch ~1288-1305); every LAN/SharePlay send call site in `Modules/GameRPG/Network/GameNetworkController.swift:213-217,221,236,291,305` discards the `Bool` result.
- **What:** `key(for:)` returns `nil` for any `GameNetworkModel` that isn't an audio/weather targeted repair or a file-backed presentation — i.e. every `.value` update, dice roll, health/character sync, table update, map pin, etc. — so `deferredDeliveryQueue.enqueue(...)` unconditionally answers `.rejectedSaturated` for these types, both when the local 16-outstanding-send/byte-budget cap is hit and when an actual `sendChunked` call returns `.retryableFailure`.
- **Why:** Under ordinary send-queue saturation (a busy combat round, one large chunked transfer throttling everything behind it) or a single transient `GroupSessionMessenger.send` failure — which the SharePlay transport is architecturally prone to, per `[[shareplay-architecture-constraints]]` — any non-file/non-repair game-state message is permanently, silently discarded (logged only, `Bool` result unread by every caller). Personally verified by reading `key(for:)` and `enqueueChunkedSend` end to end: there is no code path that admits a `.value`/dice/table message into the retry queue.
- **Action:** Extend `SharePlayDeferredDeliveryQueue.key(for:)` (or add a parallel bounded FIFO) to admit ordinary game-state messages instead of unconditionally rejecting them, and have at least one caller act on a `false` `sendData`/enqueue result.
- **Severity:** Critical

### 5.2 Chunked SharePlay transport has no delivery acknowledgment — a lost chunk just expires silently
- **Location:** `Modules/GameRPG/SharePlay/SharePlayPackageReceiver.swift:160-178` (`pruneExpired`, no logging), `:219-225` (`removeStream`, no logging); `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:1594-1664` (`sendChunked` treats a non-throwing local `send()` as `.succeeded`).
- **What:** A successful local `GroupSessionMessenger.send()` call is treated as delivery success even though the relay can still drop an individual package after hand-off; on the receive side, a stream missing one chunk sits in `receivedPackages` until `expirationInterval` (120s), then `removeStream` silently deletes it — no NACK, no re-request, no log line even on expiry.
- **Why:** Any multi-chunk payload (map/photo/pdf/space transfer, or any Messenger-fallback send) that loses exactly one package never completes; the sender believes it already succeeded, and the receiver forgets it ever started receiving after 120s. The content simply never displays for that participant, with no automatic recovery.
- **Action:** Add a bounded receiver-side NACK (request the missing package indices, or a full resend) that fires before/at the expiration timeout, and log a warning when a stream actually expires incomplete.
- **Severity:** High

### 5.3 Deferred-delivery promotion can stall without a scheduled retry when it hits capacity mid-drain
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:1518-1537` (`promoteDeferredDeliveries`) vs. `:1539-1560` (`scheduleDeferredPromotionIfNeeded`).
- **What:** When re-enqueuing the head deferred item fails because capacity is still exhausted, `promoteDeferredDeliveries` just `return`s without scheduling a timed retry — unlike the sibling "not ready yet" branch a few lines above, which does.
- **Why:** Largely self-healing today (`drainSendOperations` re-invokes `promoteDeferredDeliveries()` after every subsequent send completes), so no concrete stuck-forever sequence was constructed against today's constants — but it's a real asymmetry that could wedge a deferred item if the drain loop ever ends at a moment capacity is still exhausted.
- **Action:** Call `scheduleDeferredPromotionIfNeeded()` on the capacity-guard-fail path too, for symmetry and defense in depth.
- **Severity:** Low

### 5.4 Map recovery-request suppression is keyed only by (map id, version), not by the requesting participant
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:536-608` (`SharePlayMapRecoveryTracker.shouldSuppressRecoveryRequest`, :574-596), call site `:2079-2082`.
- **What:** After the master successfully broadcasts a full map, any incoming `mapState` recovery request matching that map's id/version is unconditionally suppressed for 30 seconds, regardless of which participant sent it or whether that participant actually received the broadcast.
- **Why:** A player whose reassembly genuinely failed (see §5.2) and pings with an ordinary `mapState` request inside that window is silently ignored rather than re-served. Real-world impact depends on player-side logic eventually escalating to the un-suppressed `.store`/`.store` "transfer failure repair" shape (confirmed to exist and be exempt from this suppression) rather than only re-sending `mapState`.
- **Action:** Scope the suppression cache by requesting participant (or track per-participant delivery confirmation) instead of by map id/version alone.
- **Severity:** Low

### LAN / Bonjour transport

### 5.5 Fire-and-forget LAN sends give no delivery confirmation, retry, or backpressure
- **Location:** `Modules/GameRPG/Network/ConnectionController.swift:92-106` (`request`/`response`, both call `connection.send(..., completion: .idempotent)`, verified); consumed by `Modules/GameRPG/Master/MasterNetworkController.swift:144-176` (whose `Bool` return only reflects whether a `ConnectionController` is still in the local array, not whether bytes reached the peer) and `Modules/GameRPG/Player/PlayerNetworkController.swift:97-99`.
- **What:** Every outbound LAN message — including multi-hundred-MB map/photo/pdf/space payloads up to `GameProtocol.maximumMessageByteCount` — is sent with `.idempotent` completion, which per `Network.framework` semantics never invokes a completion handler, so the app is never told whether the write succeeded.
- **Why:** If the connection fails or is torn down mid-send (Wi-Fi hiccup, backgrounding, a peer walking out of range), that specific message is silently lost with zero signal to this layer; there is no outbound queue to requeue it against, so nothing above can selectively retry.
- **Action:** Use a completion handler (e.g. `.contentProcessed`) instead of `.idempotent`, and surface a per-send failure back through `ConnectionControllerDelegate` (or an explicit outbound queue) so the controller layer can requeue after reconnect.
- **Severity:** High

### 5.6 Receive loop never detects a graceful peer half-close, only hard transport errors
- **Location:** `Modules/GameRPG/Network/ConnectionController.swift:185-216` (`receiveLoop`/`process`, verified: `isComplete` is destructured as `_`; the "no `GameProtocol` framer metadata but `error == nil`" branch just logs and returns).
- **What:** When a peer's connection is gracefully closing, `receiveMessage` can complete with `(nil, finalContext, isComplete: true, error: nil)`. Because `process()` only special-cases `error != nil`, this path logs "Message is not from MasterRPG" and returns without calling `cancel()` — `receiveLoop` then re-arms and calls `receiveMessage` again.
- **Why:** This is a routine occurrence on every graceful disconnect (player quits, master stops a player, app backgrounds). Until the connection's own `.failed`/`.cancelled` state independently fires — bounded only by the OS TCP keepalive (`keepaliveIdle = 2` is set, but retry count/interval are left at OS defaults) — the delegate is never told this connection is dead, and any send issued into it in that window silently vanishes (compounded by §5.5).
- **Action:** Check `isComplete`/nil-content explicitly (the standard `NWConnection` idiom) and call `cancel()` immediately when the read side reports completion, instead of looping.
- **Severity:** High

### 5.7 `GameRelayAdmission`'s 512-entry dedup window can let a delayed SharePlay retry re-relay as a duplicate
- **Location:** `Modules/GameRPG/Network/GameRelayAdmission.swift:21-53` (`admit(_:)`, ring-buffer eviction at :41-45, `limit: Int = 512`).
- **What:** De-duplicates a bridged LAN/SharePlay message by `(senderID, messageID, hasData)` in a count-capped, oldest-evicted-first set with no time-based component.
- **Why:** `GroupSessionMessenger` can redeliver a message well after the fact (e.g. after a participant reconnects). If 512+ other relay-eligible messages were admitted in the interim — plausible in a long, active session — the original key has already been evicted, so the late retry is treated as new and gets relayed a second time onto LAN/SharePlay.
- **Action:** Key eviction off a bounded time window in addition to (or instead of) count, so a legitimately-delayed retry is still recognized as a duplicate.
- **Severity:** Medium

### 5.8 Envelopes that don't fit any of the three decode shapes are dropped silently with no diagnostics
- **Location:** `Modules/GameRPG/Model/GameNetworkModel.swift:201-250` (`init(from:)`, the final fallback at :238-249 is unguarded by `try?`, unlike the V1 shim attempt at :228); swallowed at `Modules/GameRPG/Model/GameMessagePipeline.swift:216-224` (`decodeData(of:)`), surfacing only as a debug log via `GameNetworkController.masterReceived`/`playerReceived` (`Modules/GameRPG/Network/GameNetworkController.swift:272-276,329-333`).
- **What:** Decoding tries, in order: current v2 shape, a `try?`-guarded V1 shim, then an unguarded dev-layout shape; any wire payload matching none of the three throws out of `init(from:)` and is swallowed into one log line.
- **Why:** The receiver has no way to tell the sender its message was rejected, no way to surface a version-mismatch signal to the user, and no retry path — the message is gone with only a log line as evidence.
- **Action:** Distinguish "recognized-but-malformed" from "wrong version" in the catch path, and consider notifying the delegate of a decode failure distinct from a validly-decoded-but-rejected message.
- **Severity:** Medium

### 5.9 `.cancelled` state handler doesn't cancel the still-running receive loop
- **Location:** `Modules/GameRPG/Network/ConnectionController.swift:163-174` (`stateChanged`'s `.failed`/`.cancelled` cases) vs. `:78-82` (`cancel()`, the only place that nils `receiveTask`).
- **What:** Teardown via `.cancelled`/`.failed` calls `connection.cancel()`, but nothing cancels `receiveTask`, so the in-flight `receiveMessage` callback fires once more with a cancellation error, and `process()` treats it as a fresh failure, calling `connectionFailed()` again.
- **Why:** Every teardown can emit a duplicate `failed`/`lostConnection` delegate call for the same event. Currently fully absorbed by `MasterNetworkController`'s already-removed no-op check and `PlayerNetworkController`'s current-connection guards (traced and confirmed), so no user-visible loss results today — but any future/third-party delegate conformer without equivalent idempotency would double-process a single disconnect.
- **Action:** Have `.cancelled` also call `receiveTask?.cancel(); receiveTask = nil`, mirroring `cancel()`.
- **Severity:** Low

### 5.10 `GameProtocol.handleOutput` swallows a body-write failure after the header is already committed
- **Location:** `Modules/GameRPG/Network/GameProtocol.swift:50-66`.
- **What:** The length-prefixed header is written unconditionally, then the body write is wrapped in a `do/catch` that only logs — it never calls `framer.markFailed(error:)`.
- **Why:** If the body write ever fails after the header already went out, the receiver's framer has already been told to expect `header.length` body bytes; a short/failed body write with no defensive recovery could desync framing for every subsequent frame on that connection. This mirrors Apple's own sample framer code and `messageLength` is derived from the same outbound message, so it's expected to be effectively unreachable in normal operation, but the catch offers no recovery if it ever is hit.
- **Action:** Call `framer.markFailed(error:)` on catch instead of only logging.
- **Severity:** Low

### Master-side message pipeline

### 5.11 Map full-package repair can exhaust its retries and answer the requester with nothing
- **Location:** `Modules/GameRPG/Controller/MasterController+MapMessages.swift:205-242` (`stableMapRecoveryBundle`, the blanket `catch { continue }` at :220-225 and the terminal throw at :241); swallowed by the generic `catch` at `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:280-286`.
- **What:** `stableMapRecoveryBundle` retries `createMapGameData` up to 3 times on *any* error, not only the "edit crossed the capture window" case its comment describes — an undownloaded iCloud background image would fail identically every attempt. Once exhausted, the throw is logged and converted to `return false`; no response of any kind reaches the requester.
- **Why:** A player's map-repair/reveal request can be answered with total silence whenever the export error is persistent rather than transient, and the master never retries again once the underlying condition resolves — recovery depends entirely on an unverified client-side timeout/retry.
- **Action:** Distinguish "transient generation race" (retry) from other export failures (send an explicit `.failed` response immediately) instead of always retrying blind and then going silent.
- **Severity:** High

### 5.12 Reveal-path canonical-package export failures are swallowed with only a log line — no retry, no requester feedback
- **Location:** `Modules/GameRPG/Controller/MasterController+PdfMessages.swift:107-110`; `MasterController+PhotoMessages.swift:108-111`; `MasterController+SpaceMessages.swift:121-124`; `MasterController+AudioMessages.swift:54-56` (all four are the final `catch { Logger...error(...) }` in each module's mismatched-baseline reveal handling).
- **What:** When `createGameData(for:)` throws anything other than `ItemGameStorableError.itemMissing`, all four file-backed handlers log and return with no response and no retry scheduled.
- **Why:** A player asking the master to re-share its canonical PDF/Photo/Space/Audio gets no answer at all if the master's local copy isn't actually materialized yet — a plausible iCloud-Drive state for exactly these modules per the app's own architecture — and the request is a dead end until an unrelated future event happens to retrigger it.
- **Action:** On a non-`itemMissing` export failure, send an explicit `.failed` response (or requeue the export) instead of only logging.
- **Severity:** High

### 5.13 A pending audio-play transfer can stall permanently after one export failure
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:108-143` (`fulfillPendingAudioPlay`, `catch` at :139-142).
- **What:** If `createGameData(for:)` throws while preparing a missing player's copy of a pending audio track, `audioTransferPlayers[id]` is rolled back but `pendingAudioPlays[id]` is left in place — nothing schedules another attempt.
- **Why:** `continuePendingAudioPlays()` is only called from `handleAudio`'s `.ok` branch (an unrelated player's ack) and `performResetPlayers()` (roster changes). If the export keeps failing for a reason unrelated to those triggers, the queued play never reaches the missing player(s) for the rest of the session.
- **Action:** Add an explicit retry/backoff for a failed `fulfillPendingAudioPlay` attempt instead of relying entirely on incidental triggers.
- **Severity:** Medium

### 5.14 `GameMessagePipeline` queue overflow silently drops new messages, misreported as a duplicate — shared by both master and player
- **Location:** `Modules/GameRPG/Model/GameMessagePipeline.swift:133-141` (`enqueue`, root cause — returns `false` identically for "already seen" and "queue at `maximumQueuedMessages` (128)"); consumed by `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:182-188,424-433` and `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:205-208` — both callers log the failure as `"Duplicate ignored"` regardless of which case it was.
- **What:** `enqueue`'s capacity guard and its true-duplicate guard return through the same `Bool`, and every caller's log/drop behavior treats them identically.
- **Why:** Under a burst exceeding 128 queued events (the file's own comment names a SharePlay journal burst as the motivating case for the cap) on either the master or the player side, a genuinely new, non-duplicate message is silently discarded with no signal to the sender and no way to tell from logs that it wasn't actually a duplicate.
- **Action:** Give `enqueue` a distinct result for "queue full" vs. "duplicate" (mirror `SharePlayDeferredDeliveryAdmission`'s enum pattern, already used elsewhere in this codebase), log them differently, and consider real backpressure instead of a silent drop.
- **Severity:** Medium

### 5.15 `processMessages()` can discard the one message it already dequeued on cancellation
- **Location:** `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:190-205` (`processMessages`) and `Modules/GameRPG/Model/GameMessagePipeline.swift:143-160` (`next()`/`processed(success:)`); the same pattern also exists at `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:415-456`.
- **What:** `next()` unconditionally dequeues before `processMessages()`'s `guard !Task.isCancelled` runs; when the guard trips, `processed(success: false)` is called but never re-inserts the already-dequeued event, only clears pending-key bookkeeping.
- **Why:** If the ambient Task is cancelled between `next()` and the cancellation check, the one message currently in hand is lost with no retry — contradicting the code's own inline comment that "the pipeline retains any still-queued events for the next real trigger to resume" (true only for events not yet pulled off the queue). Appears to be a shared, deliberate policy across master and player rather than a fresh regression, but the guarantee is inaccurate for that one in-flight message on both sides.
- **Action:** Check `Task.isCancelled` before calling `next()`, or have `next()`/`processed` push the in-hand event back onto the front of the queue when cancelled.
- **Severity:** Medium

### 5.16 A Player Journal file attachment is rejected forever if it beats its Messenger admission metadata
- **Location:** `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:83-88` (`accepts`, `origin == .file` branch); `Modules/GameRPG/Controller/MasterController.swift:302-336` (`admitPlayerJournalMetadata`/`acceptsPlayerJournal`).
- **What:** A player's file-backed (Photo/Pdf/Space) SharePlay Journal attachment is accepted only if a matching `PlayerJournalAdmission` was already recorded from a separately-delivered Messenger metadata message; there is no buffering of an unmatched file event and no re-check once a later admission arrives.
- **Why:** GroupSessionJournal attachments and GroupSessionMessenger messages are independent channels with no cross-channel ordering guarantee. If the (typically large, async-loaded) attachment's delivery callback fires before the small admission message is processed, the attachment is permanently lost for the master. Reachability depends on Apple framework delivery-order behavior this review could not directly verify — treat as plausible rather than confirmed.
- **Action:** Buffer a file event that fails admission (keyed by sender+messageId) for a short window and re-check it when a matching admission arrives afterward, instead of dropping it outright.
- **Severity:** Medium

### 5.17 Value-entry updates use a strict wall-clock tie-break that can drop a legitimate edit
- **Location:** `Modules/GameRPG/Controller/MasterController+ValueMessages.swift:21-42` (specifically the `canApplyValueUpdate` call at :33); root cause `Modules/GameRPG/Root/GameRootModel.swift:256-274`.
- **What:** `canApplyValueUpdate` requires strict `timestamp > previous` using wall-clock time, unlike every sibling per-item sequencing gate in this file set (`canApplyAudioList`/`canApplyPhotoList`/`canApplyPdfList`/`canApplySpaceList`/`canApplySpaceTransform`), which all key off the monotonic `counter` instead.
- **Why:** Two legitimate, back-to-back edits to the same Character value entry with an identical or non-increasing `Date.now` timestamp (clock coalescing, or a system clock adjustment) cause the second edit to fail the guard and be silently dropped — `handleValue` returns `nil` either way, so the player has no indication their edit didn't apply.
- **Action:** Key this gate off `model.counter` like its siblings, or at minimum use `>=` with a secondary tie-breaker.
- **Severity:** Medium

### 5.18 A value update can race the character-join handshake with no re-check once it lands
- **Location:** `Modules/GameRPG/Controller/MasterController+ValueMessages.swift:21-30` (`isCharacterOwnershipAuthorized` guard).
- **What:** A `.valueUpdate` is accepted only if `isCharacterOwnershipAuthorized` already has a binding recorded from a prior join-handshake `.store` message; there is no buffering/replay of a `.valueUpdate` that arrives first.
- **Why:** If a player's `.valueUpdate` is processed before that same player's Character-sync bootstrap message — plausible across a mixed proxy/SharePlay/LAN transport with no cross-message ordering guarantee — the edit is silently dropped with no re-check once the join handshake completes moments later.
- **Action:** Hold the value update briefly when ownership isn't yet established (or re-derive/apply it once `bindCharacterOwnership` succeeds) instead of discarding it.
- **Severity:** Medium

### Player-side message pipeline

### 5.19 Map import/reveal failures are swallowed locally, bypassing the ack/retry mechanism entirely
- **Location:** `Modules/GameRPG/Controller/PlayerController+Map.swift:103-122,140-149,215-225`.
- **What:** Three separate `do { try await ...updateGame/reveal(...) } catch { Logger...; return nil }` blocks inside `handleMap` catch the throw locally instead of letting it propagate.
- **Why:** Every other module (Photo, Pdf, Space, Audio, Weather, Table) lets the same throwing calls propagate to `processMessages()`'s own catch (`PlayerController+NetworkStoreDelegate.swift:447-454`), which sends a `.failed` ack upstream and marks the message retry-eligible. Map's local catch does neither: no failure ack reaches the master, no repair is requested, and the outer pipeline still marks the message permanently handled. If this happens while answering a pending `pendingMapRepairs` entry, that repair is never completed or superseded — the player's map can get stuck broken for that map until a full disconnect/reconnect, with no visible cause.
- **Action:** Let the throw propagate from these three sites (drop the local `do/catch`) so the standard outer failure-ack + retry-eligible path handles it, matching every other module.
- **Severity:** High

### 5.20 Proxy relay forwarding is gated on the hub device's own roster/feature state
- **Location:** `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:285-354` (gates, verified), `:397-411` (forwarding — only reached if the gates above pass); `Modules/GameRPG/Controller/PlayerController+Control.swift:32-35` (a plain `.player` device also starts its own relay).
- **What:** The `controls.contains(where: { $0.id == localId && $0.show == true })` check (:314) and the per-feature `acceptsPlayer*` check (:349) both `return false` before the function ever reaches the `networkProxyStore.sendPlayer(data: forwarded)` relay call. Both are skipped only when `gameModel.gameType == .proxy`, not for a regular `.player`-type device that happens to also be relaying for others downstream.
- **Why:** Personally verified: if this hub player's own `controls` entry currently reads `show == false` (e.g. the GM temporarily benches that one player), or a feature flag momentarily doesn't apply to the hub's own identity, every message this hub would otherwise relay to its own downstream proxy-connected players is dropped — even though those downstream players' own identities and roster state are entirely unaffected.
- **Action:** Evaluate `controls`/feature gating only to decide *local* application, and still forward the message to `networkProxyStore.sendPlayer` independent of whether local processing was gated out.
- **Severity:** High

### 5.21 `GameMessagePipeline`'s dedup memory is never cleared on lost-connection/reconnect
- **Location:** `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:35-47` (`resetForLostConnection`, verified: resets `gameModel`, `spaceRoot`, `battleRoundModel` sequencing but never touches `messagePipeline`); `Modules/GameRPG/Model/GameMessagePipeline.swift:112-190` (`recentKeySet`, cleared only by `cancelAll()`/`reset()`); `Modules/GameRPG/Controller/PlayerController+Control.swift:44` (`cancelAll()` is only called from `stop()`, a full teardown, verified).
- **What:** `resetForLostConnection` resets every module-level sequencing/dedup counter but never calls `messagePipeline.cancelAll()`/`.reset()`; that actor's up-to-256-entry `recentKeySet` survives across a dropped connection or a SharePlay master rebind.
- **Why:** `GameMessageKey` has no session-generation nonce — it's built purely from message fields. If the same master identity restarts its session (a fresh `MasterController.messageCounter` starting at 1) while this player reconnects without getting a new `PlayerController` — a plausible reconnect path, and exactly the scenario SharePlay's Journal catch-up/replay is designed to re-deliver for a rejoining participant — the replayed low-numbered messages can collide with keys this device still remembers from before the drop and get silently dropped as duplicates, even though every module-level state needed to apply them was just wiped by the same reconnect.
- **Action:** Clear (or targeted-invalidate) `messagePipeline`'s dedup memory as part of `resetForLostConnection`, alongside the other per-connection state it already resets.
- **Severity:** High

### 5.22 Gated-but-never-applied messages are marked "processed" the same as successfully handled ones
- **Location:** `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:415-420` (`processMessages`'s `guard await prepareForProcessing(event) else { await messagePipeline.processed(success: true); continue }`), `:285-354` (the gates, which can fail for transient, mutable-state reasons); `Modules/GameRPG/Model/GameMessagePipeline.swift:151-160` (`processed`/`remember`).
- **What:** Every `false` return from `prepareForProcessing` — regardless of cause — is treated identically to a successfully-applied message and permanently remembered as a dedup key. Contrast the genuine-processing-failure catch a few lines below, which deliberately uses `processed(success: false)` so a retry isn't blocked.
- **Why:** Some of these gate failures are about mutable local state, not message validity (this device's own `controls` visibility, a feature flag momentarily off — see §5.20). If the same message is ever redelivered once the transient condition resolves (a transport-level retry, or a SharePlay Journal replay), it's now indistinguishable from an already-applied message and dropped forever for the session, even though it was never actually applied.
- **Action:** Distinguish permanent rejections (wrong target, genuinely stale presentation) from transient/state-dependent ones (controls visibility, feature gates) and call `processed(success: false)` for the latter.
- **Severity:** High

### 5.23 Deferred Photo/Pdf/Space reveal replays swallow their own failures with no repair re-request
- **Location:** `Modules/GameRPG/Controller/PlayerController+Photo.swift:176-198` (catch at :191-195); `PlayerController+Pdf.swift:179-199` (catch at :194-196); `PlayerController+Space.swift:224-246` (catch at :239-243).
- **What:** `retryDeferred{Photo,Pdf,Space}Reveals` removes the item from the deferred buffer *first*, then calls the corresponding handler inside a `do/catch` that only logs on failure.
- **Why:** Unlike the primary receive path, a failure here sends no ack (success or failure) upstream and issues no repair request — the item is simply gone, and since it was already removed from the deferred buffer, nothing will surface it again unless an unrelated future message happens to re-trigger it.
- **Action:** On failure, fall back to the same repair-request path the primary handlers use (or re-defer/re-queue) instead of only logging.
- **Severity:** Medium

### 5.24 Character/Value store handshake has no handling for a master failure ack
- **Location:** `Modules/GameRPG/Controller/PlayerController+Value.swift:9-39` (`handleValue` only reacts to `.addItem` or a matching master `.update/.store`; every other subtype, including `.failed`, falls through to `return nil`); `Modules/GameRPG/Controller/PlayerController+Character.swift:36-68` (`sendCharacter()` sends and unconditionally sets `hasSendPlayer = true` without waiting for or reacting to any ack).
- **What:** The player announces its Character fire-and-forget and immediately marks itself as having done so; if the master's import throws (`MasterController+ValueMessages.swift:83`'s `updatePlayer(data:)` call is unguarded locally, so a `.failed` ack is a reachable outcome), the player has no code path that reacts to it.
- **Why:** `canSendCharacter` (`!hasSendPlayer && !lostMaster`) stays false for the rest of the session once set, so the player's Character is never re-announced after a master-side import failure — it only recovers via a full reconnect cycle, with no user-visible indication anything went wrong.
- **Action:** Have `handleValue` recognize a `.failed` ack for the Character-store handshake and clear `hasSendPlayer` (or otherwise reschedule `sendCharacter()`).
- **Severity:** Medium

---

## 6. Security

_No dedicated findings in this pass._ Security was not this pass's brief. `Docu/CODE_AUDIT_Game.md §6` covers the neighboring ownership-authorization surface (character hijack, audio baseline trust) in `MasterController.swift`/`PlayerController.swift` and reports those items already fixed. §5.7 (`GameRelayAdmission`'s dedup window) and §5.8 (silent decode-failure drops) both touch replay/parsing behavior but are filed as correctness rather than security findings — neither was found to cross a trust boundary.

## 7. Performance

_No dedicated findings in this pass._ Out of scope by design. `[[shareplay-architecture-constraints]]` already documents that GroupActivities/SharePlay is inherently slower than LAN by routing through the FaceTime relay — several §5 findings (5.1, 5.2) describe correctness failure modes of that same architectural reality, not new performance findings.

## 8. SwiftUI / UI

_No findings — out of scope._ This audit's file list contains no SwiftUI view code; it is entirely controller/model/transport layer.

## 9. Dead code / duplication / refactor

_No dedicated findings in this pass._ One structural observation is folded into §10 instead of listed separately here: the master-side and player-side `processMessages()` drain loops (§5.15) independently hand-roll the same dequeue/cancellation-check ordering, and `GameMessagePipeline.enqueue`'s capacity-vs-duplicate ambiguity (§5.14) is a single shared-infrastructure root cause manifesting at two call sites — both are refactor opportunities as much as bugs.

---

## 10. Cross-cutting recommendations

1. **Give every admission/enqueue API a result type that distinguishes "rejected because already seen" from "rejected because full/gated/transient."** `SharePlayDeferredDeliveryQueue`'s own `SharePlayDeferredDeliveryAdmission` enum is the right pattern and already exists in this codebase — `GameMessagePipeline.enqueue` (§5.14) should be brought in line with it rather than reusing a bare `Bool` for both cases.
2. **A request that expects a reply must always get one, even on the failure path.** §5.11, §5.12, §5.16, and §5.24 are four independent instances of the same shape: an internal error is logged and the function returns, but nothing sends the requester an explicit `.failed`/error response. A shared helper ("respond-or-fail") at the dispatch layer would close this whole class at once.
3. **A message rejected for transient/local-state reasons must never be recorded as "processed."** §5.14, §5.15, and §5.22 all conflate "permanently invalid" with "temporarily can't apply right now" in their bookkeeping. The dedup/ack layer needs a three-way outcome (applied / transiently-rejected-retry-ok / permanently-rejected), not the current two-way applied/not-applied.
4. **Every reconnect/session-reset path must clear every piece of per-connection state, not just the ones a given bug report happened to touch.** §5.21 is a dedup-memory instance of exactly the class of bug the project has hit before (see `[[colocated-master-map-reshow-fix]]`, `[[cross-device-version-determinism]]`) — a small enumerated "what must `resetForLostConnection` touch" checklist, kept next to the function, would make future additions (a new per-connection cache) less likely to be missed the same way.
5. **SharePlay's ordinary game-state path needs the same retry infrastructure its file/repair path already has.** §5.1 is the single highest-value fix in this report — the retry/deferred machinery already exists and works correctly for file-backed and repair traffic; it just needs to admit the far more common ordinary-message traffic too.
6. **LAN sends need a completion signal.** §5.5 and §5.6 compound each other: `.idempotent` sends give no per-message failure signal, and the receive loop doesn't notice a graceful close either — together, a LAN connection can go quietly dead while the app keeps writing into it. Fixing the completion handler (§5.5) is the bigger win, but both should move together since a completion handler's failure path is also the natural place to call `cancel()`.

---

## 11. What was NOT audited

- **All SwiftUI/UI code**: `GameRPG/GameViews/*`, `SetupViews/*`, `Statistics/*`, `Table3D/*` (beyond `GroupActivityManager.swift`'s message-bridging role), `BattleRound/*` views, `Search/*`, `Browser/*`, `GameCenter/*`, `ExternalScreen/*`.
- **General concurrency and API-modernity sweep** of this scope — `Docu/CODE_AUDIT_Game.md` already did this for the controller-layer files it covered; this pass only checked concurrency *as a cause of message loss*, not exhaustively.
- **Security deep-dive** of this scope (trust boundaries, auth, injection) — see §6.
- **Performance profiling** via Instruments — see §7.
- **Algorithmic correctness** of dice/battle math, presentation-ordering math, or map-generation logic beyond the specific message-delivery bugs cited.
- **Test coverage assessment** — `Tests/GameRPGTests/*` files relevant to this scope (`NetworkStoreTests.swift`, `PlayerControllerTests.swift`, `MasterControllerConnectionTests.swift`, `MasterPlayerControllerTests.swift`, `PlayerMasterControllerTests.swift`, `SharePlayPackageTransportTests.swift`, `Mocks/NetworkStoreMocks.swift`) were skimmed for reachability context only, not reviewed for coverage gaps.
- **A verified fresh clean compile of this exact scope.** The build captured for §3 reused a warm `DerivedData` cache (0 `CompileSwift` invocations logged) and reported zero warnings, but that does not confirm every file in this scope was actually recompiled under current settings — treat it as corroborating evidence only.
- **`GroupActivityManager.swift`'s visionOS/TabletopKit rendering itself** — only its message-bridging into the shared `RPGSharePlayController` pipeline was checked, not the TabletopKit-specific rendering/interaction code.
- **Cross-reference against `Docu/CODE_AUDIT_12.md`** (untracked, in progress at the time of this audit) was done only for the Network-transport layer's own findings, to avoid duplication; the other three layers were not cross-checked against it.
- **Localization and string catalogs.**
- **Third-party dependency internals** (`swift-syntax`, `swift-snapshot-testing`, `RPGTabletopGameContent`, etc.).

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference — it should land on the cited line.

Personally re-opened and confirmed during this audit, beyond each finding's own citation:

- **§5.1** (Critical) — opened `Modules/GameRPG/SharePlay/SharePlayDeferredDeliveryQueue.swift:150-269` and `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:1202-1324` side by side. Confirmed: `key(for:)` returns `nil` for any model that is not an audio/weather targeted repair and not `isFileBackedPresentation`/`isPlayerFilePresentationEvent`; `enqueue` unconditionally answers `.rejectedSaturated` for a `nil` key (line 166) regardless of actual capacity; both call sites in `enqueueChunkedSend` (the capacity-exhausted fallback at ~1307-1322 and the retryable-failure branch at ~1288-1305) route through this same `enqueue`, so an ordinary `.value`/dice/table message has no path into the retry queue.
- **§5.5** — opened `Modules/GameRPG/Network/ConnectionController.swift:92-106`. Confirmed both `request(type:encodedContent:)` and `response(type:encodedContent:)` call `connection.send(..., completion: .idempotent)`.
- **§5.6** — opened `Modules/GameRPG/Network/ConnectionController.swift:185-216`. Confirmed `receiveLoop`'s continuation resumes `error == nil` even when the framer-metadata cast fails, and `process()`'s guard-else branch only calls `cancel()`/`connectionFailed()` when `error != nil` — a graceful half-close (nil content, nil error, no framer metadata) falls through to a bare `return`, and the loop re-arms.
- **§5.20** — opened `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:280-413`. Confirmed the `controls`/`show` guard (line 314) and the per-feature `accepts*` guard (line 349) both `return false` before the function reaches the `networkProxyStore.sendPlayer(data: forwarded)` call at line 408; neither guard is bypassed for a plain `.player`-type device (only `.proxy`/`.observer` skip it).
- **§5.21** — opened `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:1-48` and grepped `cancelAll`/`reset`/`messagePipeline` across `GameMessagePipeline.swift` and `PlayerController+Control.swift`. Confirmed `resetForLostConnection` resets `gameModel`, `spaceRoot.resetSpaceTransforms()`, and `battleRoundModel.resetNetworkSequence()` but never references `messagePipeline`; the only `cancelAll()` call site is `PlayerController+Control.swift:44`, inside `stop()`.

If any finding doesn't reproduce when you visit the line, flag the specific reference and it will be re-investigated.
