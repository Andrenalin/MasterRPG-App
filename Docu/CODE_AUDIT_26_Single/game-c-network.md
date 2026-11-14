Area: Modules/GameRPG/SharePlay (24 files) and Modules/GameRPG/Network (17 files), about 8.2k LOC, plus the transport-owning controllers they depend on (Master/MasterNetworkController*, Player/PlayerNetworkController*, Browser/BrowserManager, Master/HostingSessionStore, Model/GameLimits). Read in full: GameProtocol, ConnectionController, ListenerManager, NWParameter+GameMaster, ConnectionAttemptThrottle/ThrottleTracker, GamePlayerRoutes, GameJoinCodeModel, JoinCodeStorage, GameNetworkController (+Delivery, +MasterDelegate, +PlayerDelegate, +SharePlayDelegate, Model), ListenerRestartScheduler, RPGSharePlayController (+ChunkedTransport, +SessionLifecycle, +JournalAttachments), SharePlayPackageReceiver, SharePlaySingleQueuePackageSender, InboundByteBudget, DeferredDeliveryQueue, JournalLedger, JournalAddLimiter, JournalPublicationQueue, JournalLoadSequencer, AttachmentLoadRetry, GroupSessionCommandQueue, SessionCoordinators, MasterNetworkController (+Listener, +Browser), PlayerNetworkController (+Listener, +Browser), BrowserManager, HostingSessionStore. Overall health: very good. The boundary is well defended (100 MB frame cap checked in the framer and again on send, per-source pending-handshake and lockout throttle, 32-connection cap, handshake deadlines, outbound queue cap, per-sender SharePlay stream/byte quotas, session-generation guards on every async hop, continuations resumed exactly once). No Critical or High found; the findings below are residual gaps and cleanups. Nothing re-reported from CODE_AUDIT_Network / _Game_Shareplay / _JoinCode / _Reconnect / _25 that is marked fixed or by design (4-digit PSK, constant PSK identity, redial-on-matching-session-id handshake exposure, SharePlay master pinning, chunked overhead, trusted-player model were all treated as decided).

### LAN frames are fully decoded before any per-peer rate or byte budget applies
- Category: Security
- Location: Modules/GameRPG/Network/GameNetworkController+MasterDelegate.swift:28-39, Modules/GameRPG/Network/GameNetworkController+PlayerDelegate.swift:28-33, Modules/GameRPG/Model/GameMessagePipeline.swift:477-481, Modules/GameRPG/Network/GameProtocol.swift:41, Modules/GameRPG/Model/GameLimits.swift:14,45-47; contrast Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:530-536
- What: `masterReceived` decodes every LAN frame (up to 100 MB of base64 JSON) with `decodedOffMain` before `accepts` runs, and nothing limits how many bytes one connection may make the master decode per minute; SharePlay has exactly that guard (`SharePlayInboundByteBudget`, CODE_AUDIT_21 §6.5) but the LAN path never got the equivalent.
- Why: the framer buffers up to 100 MB per connection and `maximumConnections` is 32, and the `maximumQueuedBytes` (300 MB) limit only applies to the pipeline queue after decoding. An authenticated but misbehaving or buggy peer (or several at once) can send repeated 100 MB frames and make the GM allocate frame, decoded Data and model concurrently per connection (hundreds of MB each), a jetsam risk on iPad. Players are trusted by design, so the exploit needs a compromised or faulty client; the asymmetry with SharePlay is the point. Not verified at runtime.
- Action: Apply a per-connection inbound byte budget (reuse `SharePlayInboundByteBudget` keyed by connection id) in `ConnectionController.process` or `masterReceived` before decoding, and consider capping a player's frame at the size a player legitimately sends (player uploads are small; only the master sends large packages), e.g. a lower per-role frame limit on the master's listener side.
- Severity: Medium
- Status: NEW (related: CODE_AUDIT_15 "LAN frame cap" open item, frame cap itself since fixed)

### Version-mismatch notices are claimed once per app run, never reset between games
- Category: Bug
- Location: Modules/GameRPG/Network/GameNetworkControllerModel.swift:130-148, Modules/GameRPG/Network/GameNetworkController+PlayerDelegate.swift:48-66, Modules/GameRPG/Network/GameNetworkController.swift:147-166 (resets only `playerRoutes`), Modules/GameRPG/Root/GameRoot.swift:87-88 (controller created once per app run)
- What: `reportedMismatches`, `hasSentVersionNotice` and `versionNoticeConnectionIds` are never cleared; `stopGame()` only calls `model.playerRoutes.reset()`.
- Why: after the first "update the app" mismatch (or the first notice sent to a master), a second game in the same app run against an incompatible peer shows no alert and sends no notice, so the user sees a join that silently does nothing, which is exactly what the notice exists to prevent. `versionNoticeConnectionIds` also grows by one UUID per incompatible connection for the life of the process (tiny, but unbounded).
- Action: Clear the three claim sets in `GameNetworkController.stopGame()` (or on `startMasterGame`/`startPlayerGame`) next to `playerRoutes.reset()`.
- Severity: Medium
- Status: NEW

### Journal metadata loading is sequential and unbounded per snapshot
- Category: Performance
- Location: Modules/GameRPG/SharePlay/RPGSharePlayController+JournalAttachments.swift:76-103, 40-64
- What: `handle(_:sessionId:)` awaits `loadMetadata` one uncached attachment at a time (20 s deadline each) before it starts any load, and the number of attachments in a snapshot is not capped.
- Why: one participant (or a flaky CloudAsset) adding many attachments keeps every later snapshot, including the game master's real publication, behind N x 20 s on the single drain task. Normal use is at most one attachment per module slot (about 8), so this is a latent denial of service from a session participant, not a regular failure. Related to the open "serial join-batch loads" residual in the journal notes.
- Action: Cap the entries processed per snapshot (for example the newest 16 by counter, or skip senders other than the master on player devices before loading metadata), or load the metadata of uncached attachments concurrently with a task group.
- Severity: Low
- Status: NEW (residual of the journal-hung-system-calls note)

### Journal load budget is bypassed by a sender that claims to be the game master
- Category: Security
- Location: Modules/GameRPG/SharePlay/RPGSharePlayController+JournalAttachments.swift:198-209, Modules/GameRPG/Network/GameNetworkController+SharePlayDelegate.swift:37-50
- What: `countsAgainstBudget = !metadata.sender.isMaster` and `shouldLoadFile` on a player device only checks `message.sender.isMaster`; both trust the sender block of the attachment's developer metadata, which any participant writes.
- Why: on a player device a participant can label every attachment as master-sent and get unlimited whole-blob loads (up to Apple's 100 MB each) with no per-sender budget. This follows from the decided "no SharePlay master pinning as a security check" rule, so it is reported only to record that the load budget in §6.2 of CODE_AUDIT_Game_Shareplay protects the GM device but not player devices.
- Action: Either accept and document it next to `journalLoadBudget`, or count every load against the budget keyed by the attachment's authenticated source when the API exposes one.
- Severity: Low
- Status: NEW (consequence of a decided design; informational)

### Dead observable state `stateText` and test-only counters in production types
- Category: Dead code
- Location: Modules/GameRPG/SharePlay/RPGSharePlayController.swift:82, Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:310-312, Modules/GameRPG/SharePlay/SharePlayInboundByteBudget.swift:21, Modules/GameRPG/SharePlay/SharePlayJournalLoadSequencer.swift:35, Modules/GameRPG/SharePlay/SharePlayJournalAddLimiter.swift:52
- What: `stateText` is written on every session state change but read nowhere in Modules/, Sources/ or Tests/; `SharePlayInboundByteBudget.senderCount`, `SharePlayJournalLoadSequencer.activeItemCount` and `SharePlayJournalAddLimiter.activeCount` are read only by tests (PerformanceAuditTests, SharePlayPackageTransportTests).
- Why: `stateText` is a stored property of an `@Observable` class, so each write also fires observation for no observer; the test-only members are small API surface kept for tests.
- Action: Delete `stateText` and its assignment (the `printState()` log line stays); mark the three counters `#if DEBUG` or leave with a comment that they are test affordances.
- Severity: Low
- Status: NEW

### `GameNetworkController.stopGame` duplicates its two branches
- Category: Duplication
- Location: Modules/GameRPG/Network/GameNetworkController.swift:147-166
- What: the `isStreaming` and `else` branches both run `playerStore.stop()` and `sharePlayStore.reset()` (guarded by `!proxy`); only `masterStore.stopStreaming()` differs.
- Why: two copies of the same teardown can drift, and the long comment on one branch applies to both.
- Action: Call `stopStreaming()` conditionally, then run one shared teardown sequence.
- Severity: Low
- Status: NEW

### A throttled player gets no "locked out" feedback
- Category: SwiftUI
- Location: Modules/GameRPG/Master/MasterNetworkController+Listener.swift:66-70, Modules/GameRPG/Network/ConnectionAttemptThrottle.swift:47-50
- What: a connection from a locked-out source is closed with no signal, so a legitimate player who mistyped the code three times and then types the right one inside the 5 s to 300 s lockout sees only a generic timeout/unreachable message.
- Why: the join UI cannot tell "locked out" from "host unreachable", which makes the correct code look broken. Security behaviour itself is right.
- Action: Optional: advertise a lockout hint in the player's failure (the player can count its own consecutive bad-code results and show "wait before retrying") instead of changing the master.
- Severity: Low
- Status: NEW

Also read and found sound (no finding): SharePlayParticipantTracker, SharePlaySessionLifecycle, SharePlayStateSupersession, PhysicalIdentityDenylist, SharePlayJournalPublicationQueue, SharePlayAttachmentLoadRetry.

Not audited in this area: SharePlayJournalPublication (types), RPGSharePlayController+TableCoordination, +VisionOSTemplate, GameActivityAssociation, GameShareStateModel, RPGActivity, PhysicalIdentityDenylist, BrowserRowView (UI), Network/GameJoinCodeModel's sync init Keychain reads (already open as a decision in the Shareplay audit), the TabletopKit/visionOS code paths (not buildable here), and runtime behaviour on devices (no builds or tests were run).
