# MasterRPG Code Audit — BattleRound / Map GameController / Network

Generated 2026-08-21. Scope: ~14,000 Swift LOC across 64 files spanning three subsystems the user asked for explicitly:

- **BattleRound** — `Modules/GameRPG/BattleRound/` (30 view + controller files) and `Modules/MapRPG/BattleRound/` (4 model files)
- **Map `GameController`** — `Modules/MapRPG/Controller/GameController.swift` + its `+Battle`/`+Pins`/`+MapSync`/`+Metadata` extensions
- **Network communications** — `Modules/GameRPG/Network/`, `Master/`, `Player/`, `SharePlay/`, `Model/GameNetworkModel.swift`, `Model/RPGMessageType.swift` (local-network `Network.framework` P2P stack and GroupActivities/SharePlay)

No `Dead/` or other archived directory exists in this repo. Test targets (`Tests/`) were scanned lightly for coverage context only, not deeply reviewed.

A clean `xcodebuild` of the `GameRPGTests` and `MapRPG` schemes for iOS Simulator produced **zero compiler warnings** anywhere in this scope — the concurrency and modernity findings below come entirely from manual review, not compiler ground truth.

This is a previously-audited, actively-maintained codebase (git history shows several prior "fixed: audit N.N" commits, and in-code comments cite specific past `CODE_AUDIT §` items such as the message-length cap, connection-attempt throttling, and Keychain-backed join codes — all confirmed still correctly in place). Findings here reflect what a fresh, scoped pass over exactly the subsystems requested turned up on top of that existing baseline.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action.

---

## 0. Fix status (2026-08-21)

All findings below were addressed in this pass except the two noted as deliberately skipped and the three noted as partial, each with its reasoning. Verified via `xcodebuild build` after every batch of changes (all green) and a full `xcodebuild test -scheme GameRPGTests` run: all 59 directly relevant tests pass (`BattleRoundControllerTests`, `BattleRoundModelTests`, `ConnectionAttemptThrottleTests`, `MasterNetworkControllerTests`, `PlayerNetworkControllerTests`, `GameNetworkModelVersionTests`, `SharePlayPackageTransportTests`, `MasterPlayerControllerTests`, `GameMessageCorrectnessRegressionTests`, `WeatherMessageFlowTests`, `NetworkStoreTests`, `InAppControllerTests`, etc.). 117 SwiftUI snapshot-comparison tests fail, but this is a pre-existing environmental baseline mismatch, not a regression — the failures span modules never touched in this pass (e.g. `RolePlayGameKitGeneratedPreviewSnapshotTests`, `GameStatistics*` charts) exactly as heavily as `GameRPG`'s own views.

- **§3.1** — Fixed. `ListenerServerController.run()` now loops the keep-alive sleep indefinitely instead of returning after one fixed duration.
- **§3.2** — Fixed. `ConnectionAttemptThrottle` now measures against `ContinuousClock` (injectable `at now:` for tests), not `Date`.
- **§3.3** — Partial. `GameJoinCodeModel`'s Keychain **writes** now run off the main actor (`Task.detached`). The initial **read** at `init()` stays synchronous — deferring it would mean the UI briefly shows an empty/placeholder join code, a real behavior change too risky to make blind for a Low-severity finding. Documented in the code.
- **§3.4** — Reviewed, no change. `@preconcurrency import GroupActivities` still appears required given the framework's current annotations; left as a periodic-recheck item per the finding's own suggested action.
- **§4.1** — Deliberately skipped. Renaming `messageID`/`senderID`/`participantID`/`masterID`/`targetID` → `Id` casing touches ~80+ occurrences across `GameNetworkModel.swift` and `GameNetworkController.swift`, including compound identifiers (`trustedMasterRelayParticipantID`, `ownerParticipantBySender`, etc.) that a blanket rename could inconsistently handle, and `GameNetworkModel`'s `CodingKeys` raw values would need explicit pinning (`case messageId = "messageID"`) to avoid silently changing the wire format between app versions. Given this is a Low-severity, purely cosmetic finding touching the core network protocol's identifiers, the risk/reward didn't justify a blind mechanical rename in this pass — flagging for a dedicated follow-up instead.
- **§4.2** — Fixed. Unused `import Combine` removed from `SharePlayPackageSender.swift`/`SharePlayPackageReceiver.swift`; `GameShareStateModel`'s `PassthroughSubject` replaced with the same recursive `withObservationTracking` pattern already used by `MasterNetworkController`/`PlayerNetworkController`.
- **§5.1** — Fixed. `PlayerNetworkController.listenerNewConnection` now explicitly cancels a dropped connection outside the reconnect branch.
- **§5.2** — Fixed. `.battleRound` updates now defer and retry on a generation mismatch, mirroring `.mapPin`'s existing `deferMapPin`/`retryDeferredMapPins` pattern (`PlayerControllerModel.queueBattleRoundUpdate`/`retryDeferredBattleRoundUpdate`).
- **§5.3** — Fixed. Both force-unwraps in `NWParameter+GameMaster.swift`'s `tlsOptions(passcode:)` replaced with `guard`/`assertionFailure`.
- **§6.1** — Fixed. `BattleRoundController.recordDiceResult` now verifies the resolved combatant is either the master's own roll or one `senderId` is actually authorized for, before trusting `resultCategory`.
- **§6.2** — Fixed. `lastUsedMasterJoinCode` moved from `UserDefaults` to the same Keychain-backed `JoinCodeStorage` as `masterCode`/`playerCode` (added `remove(forKey:)` to the protocol for the nil case).
- **§6.3** — Fixed. Battle-health debug logging in `GameController+Battle.swift` switched from `.public` to `.private`.
- **§6.4** — Fixed. `ConnectionAttemptThrottle.sources` now evicts the least-recently-active entry once tracked sources exceed a bound (256).
- **§7.1** — Partial. The per-combatant debug log now only fires when a health value actually persists a change (was unconditional every tick) — the bulk of the logging overhead this finding cites. The `healthPercent(for:)` recompute itself was left untouched: this exact subsystem has a documented history of subtle regressions (see in-code references to prior health-sync bugs), and speculative dependency-tracking to skip the recompute carried real risk for a Medium-severity perf finding without dedicated test coverage to validate it.
- **§8.1** — Fixed. `addRow` extracted from a computed property into `BattleRoundPatternAddRow: View`.
- **§8.2** — Fixed. Added `.accessibilityAction` "Move Earlier/Later in Turn Order" entries as a non-drag equivalent for VoiceOver/Switch Control.
- **§8.3** — Fixed. `BattleParticipantColumn` is now `Equatable` with `.equatable()` at its three call sites.
- **§8.4** — Partial. Introduced `BattleRoundSpacing` and applied it everywhere a padding/spacing value already repeated ≥2× across files (the actual duplication). Genuine one-off fine-tuning values (e.g. `.padding(.top, 20)` vs. `.padding(.top, 18)` between the wide/compact layouts) were deliberately left as literals — there's nothing to deduplicate there, and inventing shared names for them would misrepresent one-off tuning as a shared design decision.
- **§9.2** — Fixed. Six `NetworkCodableDataType(type: .map, …)` call sites now go through a shared `GameController.mapNetworkData(id:generation:data:)` factory.
- **§9.3** — Fixed. `updatePinIfCurrentGeneration` and `applyBattleRoundUpdate` now share one `isCurrentGeneration(_:for:)` guard.
- **§9.4** — Fixed. Added `mutatedPinState(itemId:pinId:mutation:)` (returns the pin) alongside the existing `updatePinState` (returns `Bool`) as a **distinctly-named** function rather than an overload — an overload differing only in a trailing-closure label proved ambiguous at existing call sites (caught by a real build failure during this pass). Pointer timestamp bumps now go through a shared `GameController.bumpedTimeInterval(from:)`.
- **§9.5** — Fixed. Added `BattleRoundController.authorizedMapId`; 13 of the 15 cited guards now collapse to it (the other two — `start()` and `moveEntries`Guard — have a genuinely different shape and were left as direct `isMaster` checks rather than forcing a mismatched abstraction).
- **§9.6** — Fixed. Extracted `retryUntilRemoved(delays:isObsolete:sleep:remove:finish:)`, used by all three former hand-rolled retry loops, preserving the original's before/after `isObsolete` double-check exactly.
- **§9.7** — Fixed. Extracted `ConnectionThrottleTracker` (wraps `ConnectionAttemptThrottle` + pending-sources bookkeeping); both `MasterNetworkController` and `PlayerNetworkController` now hold one instance instead of hand-rolling the lifecycle.
- **§9.8** — Left as-is per the finding's own recommended action ("only worth it if a third such box appears").
- **§9.9** — Fixed. Added `BattleRoundCardLayoutContext`; both card layouts now take one `context:` parameter instead of 6 separate properties.
- **§9.10** — Fixed for 4 of 6 files via physical split (verified compiling at each step): `SharePlayJournalPublicationQueue.swift` → 3 files (`SharePlayJournalPublicationQueue.swift`, `SharePlayJournalAddLimiter.swift`, `SharePlayDeferredDeliveryQueue.swift`); `GameNetworkController.swift` → 3 files (core controller + `GameRelayAdmission.swift` + `SharePlayPlayerJournalAdmission.swift`); `BattleRoundModel.swift` → 2 files (class + `BattleRoundTypes.swift`); `GameNetworkModel.swift` → 4 files (envelope model + `GameNetworkModel+RoutingPolicy.swift` + `GameNetworkModelV1.swift` + `GameMessagePipeline.swift`). `GameController+Battle.swift` and `RPGSharePlayController.swift` got `// MARK:` section dividers only (both already flagged as an acceptable fallback by the finding itself) — physically splitting `RPGSharePlayController.swift` (2,509 lines, never fully read end-to-end in this pass) risked missing a `private`/`fileprivate` cross-reference in code this size without a much larger, dedicated pass. `routeSharePlayUpdate`'s internal 182-line breakdown (the finding's secondary recommendation) was not attempted for the same reason.
- **§9.11** — Fixed. `receivedPacakges` → `receivedPackages` (+ 7 test references), `resetConntections` → `resetConnections`, `SharePlayPackageSender.swift` renamed to `SharePlaySingleQueuePackageSender.swift`.
- **§9.12** — Fixed. Named the 24h listener keep-alive interval and the join-code length (`codeLength = 4`, used by both `randomCode()` and `isValidCode(_:)`).

---

## 1. Executive summary

1. **[High/Security] Dice rolls can be attributed to a combatant the sender doesn't control** — §6.1 — `Modules/GameRPG/BattleRound/BattleRoundController.swift:243-270`. A player-controlled network payload field (`resultCategory.id`) is trusted ahead of the sender's authenticated identity, letting a buggy/malicious client misattribute a roll to any other combatant.
2. **[High] Battle-round state updates have no resync path on a version mismatch** — §5.2 — `Modules/MapRPG/Controller/GameController+Battle.swift:553-567`. Unlike the sibling `.mapPin` route, a generation mismatch silently drops the update with no defer/retry, leaving a player's turn-order UI stale until an unrelated future broadcast happens to realign.
3. **[High] Combatant drag-to-reorder has no VoiceOver-accessible alternative** — §8.2 — `Modules/GameRPG/BattleRound/BattleRoundList.swift:38-54`. Reordering the turn order is entirely drag-gesture-based with no accessibility actions or List-based fallback — a total feature gap for VoiceOver/Switch Control users.
4. **[High] `RPGSharePlayController.swift` is 2,509 lines with zero internal navigation** — §9.10 — the single largest file in scope, mixing session lifecycle, chunked transport, and Journal admission with no `// MARK:` sections.
5. **[Medium/Security] The last-used join code is still stored in UserDefaults, not Keychain** — §6.2 — `Modules/GameRPG/Network/GameJoinCodeModel.swift:65-77`. An active authentication secret sits outside the Keychain protection its sibling codes were moved into under a prior audit item.
6. **[Medium] A dropped fallback-listener connection is never explicitly closed** — §5.1 — `Modules/GameRPG/Player/PlayerNetworkController.swift:272-287`. A reconnecting peer can silently stall waiting on an OS-level timeout instead of an explicit close.
7. **[Medium] `ConnectionAttemptThrottle` uses wall-clock `Date` instead of the codebase's own `ContinuousClock` convention** — §3.2 — a device clock change can shorten or extend an active anti-brute-force lockout.
8. **[Medium] Every battle action recomputes and logs every combatant's health, regardless of what changed** — §7.1 — `Modules/MapRPG/Controller/GameController+Battle.swift:452-465`.
9. **[Medium] The `isMaster` authorization guard is hand-copied 15 times in `BattleRoundController`** — §9.5 — a single missed copy on a future 16th method would be a real authorization bug with no compiler backstop.
10. **[Medium] The "current generation" validation guard is duplicated between the pin-update and battle-round-update paths** — §9.3 — the same six-condition check must be kept byte-for-byte in sync by hand in two files.

---

## 2. Quick wins (≤30 min each)

- **Explicitly `.cancel()` the dropped connection** in the `!shouldRestart` branch of `PlayerNetworkController.listenerNewConnection` — `Modules/GameRPG/Player/PlayerNetworkController.swift:272-287` — mirrors the explicit cancel two lines above it for the throttled-source case. See §5.1.
- **Fix two symbol typos**: `receivedPacakges` → `receivedPackages` (`Modules/GameRPG/SharePlay/SharePlayPackageReceiver.swift:53,71,113,144,182,221` + 7 test references) and `resetConntections` → `resetConnections` (`Modules/GameRPG/Master/MasterNetworkController.swift:79,94,109,121`). See §9.11.
- **Rename `SharePlayPackageSender.swift`** to `SharePlaySingleQueuePackageSender.swift` to match its actual type name. See §9.11.
- **Remove two unused `import Combine` statements** — `Modules/GameRPG/SharePlay/SharePlayPackageSender.swift:3`, `Modules/GameRPG/SharePlay/SharePlayPackageReceiver.swift:3`. See §4.2.
- **Name two magic constants**: the 24-hour listener keep-alive sleep (`Modules/GameRPG/Network/ListenerManager.swift:151`) and the join-code length `4` duplicated between `randomCode()` and `isValidCode(_:)` (`Modules/GameRPG/Network/GameJoinCodeModel.swift:80-83,102-103`). See §9.12.
- **Switch battle-health debug logging from `.public` to `.private`** — `Modules/MapRPG/Controller/GameController+Battle.swift:454-457,498-533` — matches the privacy posture already used for comparable data elsewhere in the same file set (`RPGSharePlayController.swift:774`). See §6.3.
- **Extract the `addRow` computed property** in `BattleRoundSettingsView.swift:72-101` into a proper `BattleRoundPatternAddRow: View` struct, per the project's own no-computed-property-view-decomposition rule. See §8.1.

---

## 3. Concurrency

### 3.1 Listener silently stops accepting connections after 24 hours with no error signal
- **Location:** `Modules/GameRPG/Network/ListenerManager.swift:130-155` (`ListenerServerController.run()`), `:73-83` (`ListenerManager.startListening()`)
- **What:** `run()` stays alive only via `try await Task.sleep(for: .seconds(24*60*60))`. When that sleep elapses normally (not cancelled), the function returns; its `defer` calls `listener.cancel()` and `continuation.finish()` synchronously, so no `ListenerEvent` (`.cancelled`/`.failed`) is ever yielded through the `AsyncStream` before it finishes.
- **Why:** After exactly 24 hours of continuous hosting, the Bonjour listener stops advertising and accepting connections, but `ListenerManager.state` and the UI keep showing whatever state was last set — a marathon session or a device left in host mode looks fine while silently no longer joinable, and `listenerCancelled()` never fires to let the app react.
- **Action:** Replace the fixed-duration "run forever" idiom with one that either loops the sleep indefinitely on normal completion or ties listener lifetime purely to `onCancel`, and ensure a normal (non-throwing) return from `run()` still surfaces a terminal event to `ListenerManager`.
- **Severity:** Medium

### 3.2 `ConnectionAttemptThrottle` lockout uses wall-clock `Date` instead of the codebase's own monotonic-clock convention
- **Location:** `Modules/GameRPG/Network/ConnectionAttemptThrottle.swift:18-49`
- **What:** `State.lockedUntil` is computed and compared using `Date.now`/`Date.addingTimeInterval`, whereas the sibling `SharePlayMapRecoveryTracker` in `RPGSharePlayController.swift:532-599` explicitly uses `ContinuousClock` "so wall-clock changes cannot extend or shorten the suppression window."
- **Why:** A device clock change (manual adjustment, NTP sync, DST/timezone jump) while a lockout is active can instantly expire an active passcode-guessing lockout or freeze it far longer than intended — undermining the exact anti-brute-force protection this actor exists to provide.
- **Action:** Switch to `ContinuousClock`/`ContinuousClock.Instant` for `lockedUntil`, matching the pattern and stated rationale already used elsewhere in this same module.
- **Severity:** Medium

### 3.3 Synchronous Keychain I/O runs directly on `@MainActor` during launch and every code edit
- **Location:** `Modules/GameRPG/Network/GameJoinCodeModel.swift:28-34,51-63,85-100`; `Modules/GameRPG/Network/JoinCodeStorage.swift:19-56`
- **What:** `GameJoinCodeModel` is `@MainActor`; its `init()` and both codes' `didSet` observers call straight through to `KeychainJoinCodeStorage`, which performs blocking `SecItemCopyMatching`/`SecItemAdd`/`SecItemUpdate` calls synchronously with no async offload.
- **Why:** Every app launch blocks the main thread on two synchronous Keychain reads before the first frame renders, and every join-code edit in Settings blocks the main thread on a Keychain write. Apple does not guarantee Keychain access is instant (e.g., immediately post-boot before first unlock), so this is a real, if low-probability, main-thread stall.
- **Action:** Move the Keychain calls off the main actor (e.g. a `nonisolated`/background-executed storage call awaited from `init`/`didSet`) so `@MainActor` only ever holds the already-resolved `String` values.
- **Severity:** Low

### 3.4 `@preconcurrency import GroupActivities` suppresses Sendable checking across the largest file in scope
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:8`
- **What:** The whole 2,509-line file imports `GroupActivities` with `@preconcurrency`, silencing strict-concurrency/Sendable diagnostics for every GroupActivities type (`GroupSession`, `GroupSessionMessenger`, `GroupSessionJournal`, `SystemCoordinator`, etc.) crossing an isolation boundary here.
- **Why:** Likely necessary given GroupActivities' current annotations, but it means the "zero warnings" baseline for this file includes an unknown amount of suppressed checking rather than proven-safe checking on those specific boundary crossings.
- **Action:** Periodically re-check (e.g. on SDK upgrades) whether `@preconcurrency` can be dropped now that the deployment target is iOS/macOS 26+, to regain compiler-verified Sendable checking here.
- **Severity:** Low

---

## 4. API modernity

### 4.1 `Id`/`ID` naming convention drift in newer message-identity code
- **Location:** `Modules/GameRPG/Model/GameNetworkModel.swift:109,112,120,126`; `Modules/GameRPG/Network/GameNetworkController.swift:9-11,53-76,178-181,212-266,300-347`
- **What:** The project convention is `Id`/`Url` casing (`itemId`, matching `masterId`/`targetId` in the same struct), but `GameNetworkModel.messageID`/`replyToMessageID` and the newer SharePlay-admission plumbing in `GameNetworkController.swift` (`senderID`, `participantID`, `targetID`, `masterID`) consistently use `ID` casing for the same kind of identifier — even when copying from a correctly-cased source (`model.masterId` → `Fingerprint.masterID`).
- **Why:** Inconsistent casing for the same concept within one file — and within a single initializer — increases the chance of a typo'd cross-reference and makes call sites harder to scan/autocomplete consistently.
- **Action:** Rename to the project's `Id` convention across both files; wire format is unaffected since `CodingKeys` can retain the existing JSON key strings.
- **Severity:** Low

### 4.2 Residual/inconsistent Combine usage in an otherwise Observation-only subsystem
- **Location:** `Modules/GameRPG/SharePlay/SharePlayPackageSender.swift:3` (unused `import Combine`); `Modules/GameRPG/SharePlay/SharePlayPackageReceiver.swift:3` (same); `Modules/GameRPG/SharePlay/GameShareStateModel.swift:5,28-31` (`PassthroughSubject`/`AnyPublisher` used where `withObservationTracking` is the established pattern)
- **What:** Two files retain a dead `import Combine`. A third hand-rolls a Combine `PassthroughSubject`/`AnyPublisher` pair purely to notify one consumer of an `@Observable` property change — duplicating what `withObservationTracking` already does elsewhere in this exact module set (`MasterNetworkController.observeConnections()`, `PlayerNetworkController.observeRemovedConnection()`).
- **Why:** Dead imports are noise; the `PassthroughSubject` is an extra dependency and an extra place a change notification can be missed or duplicated, for a need the codebase has a proven pattern for already.
- **Action:** Remove the two unused imports; replace `GameShareStateModel`'s Combine plumbing with the same `withObservationTracking`-based pattern used by the Master/Player network controllers.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Fallback listener drops an in-flight connection without explicit close
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift:272-287`
- **What:** When a connection arrives on the player's reconnect-fallback listener but `networkModel.connectionState != .lost` at that instant, `shouldRestart` is false and the incoming `NWConnection` is never used, never `.cancel()`'d, and never handed to a delegate — it simply falls out of scope. `networkModel.reset(listener: nil)` (called unconditionally just above, for both branches) also drops the only strong reference to the `ListenerManager` that accepted it, leaving cleanup entirely to ARC deinit and `ListenerManager`'s `isolated deinit`, neither of which sends an explicit close/reset back to the peer.
- **Why:** A peer reconnecting at the exact moment this device's state moves off `.lost` gets no explicit response on that attempt and must wait out its own OS-level connect timeout before it can be told the attempt failed and retry — a silent, if bounded, reconnect stall with no diagnostic signal on either side.
- **Action:** In the `!shouldRestart` branch, explicitly call `connection.cancel()` before returning, mirroring the explicit cancel already done for the throttled-source branch two lines above it.
- **Severity:** Medium

### 5.2 `applyBattleRoundUpdate` has no reconciliation path, unlike the sibling `.mapPin` flow
- **Location:** `Modules/MapRPG/Controller/GameController+Battle.swift:553-567`; `Modules/GameRPG/Controller/PlayerController+Map.swift:294-311,582-611,615-` (`applyPlayerMapPin`/`deferMapPin`/`retryDeferredMapPins`)
- **What:** `applyBattleRoundUpdate` gates on an exact match (`data.version == generation.version && data.assetVersion == ... && data.contentVersion == ...` against the player's last-recorded `authoritativeGeneration`) before even decoding the inner `BattleRoundNetworkState`, and its only caller (the `.battleRound` case in `PlayerController+Map.swift:307-311`) does nothing but `return nil` on failure. The sibling `.mapPin` path in the same file handles the identical generation-mismatch case by returning `.awaitingMapGeneration`, which is explicitly queued via `gameModel.deferMapPin(model)` and replayed by `retryDeferredMapPins(itemId:)` once a matching `.mapState` lands (verified: no equivalent defer/retry exists anywhere for `.battleRound`).
- **Why:** `.battleRound` and `.mapState` are broadcast independently from the same tick (`BattleRoundController.broadcast(mapId:)`). If the accompanying `.mapState` for that tick hasn't yet applied on a given player's device — its own asset/content-version fallback can itself trigger an async `requestFullMap`/`requestMapContent` round trip — or the two arrive out of order across different SharePlay transports, that player's recorded generation won't yet match what `.battleRound` was generated against, and that specific round-counter/active-attacker update is silently dropped with no retry. The player's turn-order UI then shows a stale active attacker/round number until an unrelated future action happens to broadcast a `.mapState` that resyncs it.
- **Action:** Add the same defer/retry pattern already used for `.mapPin`: on a generation mismatch, retain the pending `BattleRoundNetworkState` payload keyed by `mapId` and replay it from the same place `retryDeferredMapPins` is invoked once `.mapState` successfully applies.
- **Severity:** High

### 5.3 Hardcoded PSK/TLS force-unwraps on constant values
- **Location:** `Modules/GameRPG/Network/NWParameter+GameMaster.swift:59-64`
- **What:** `stringToDispatchData("GameMaster")!` and `tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!` are force-unwrapped, immediately adjacent to a comment (lines 48-51) explaining that a *different* force-unwrap in the same function was deliberately removed in favor of `Data(passcode.utf8)`.
- **Why:** Both values are effectively always non-nil today (hardcoded literal/constant, not attacker-controlled), but they sit on the connection-establishing security path for every LAN connection. A future edit to either literal would crash instead of failing the connection gracefully — exactly the class of risk the neighboring refactor a few lines above was written to eliminate, and this is the only place in the entire scope using `!` at all.
- **Action:** Replace both with explicit `guard`/`assertionFailure`-style handling consistent with the discipline already applied a few lines above in the same function.
- **Severity:** Low

---

## 6. Security

### 6.1 `recordDiceResult` attributes rolls via player-controlled `resultCategory` with no ownership check
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundController.swift:243-270`; `Modules/GameRPG/Controller/MasterController.swift:1409-1431` (`handleDice`, the network-message entry point)
- **What:** `characterCombatant` is resolved purely from `diceResult.diceModel.resultCategory.id` matched against any eligible combatant's `gameCharacterId`/`sourceCharacterId` (lines 250-256), and that match takes priority over the `senderId`-derived `playerCombatant` fallback (lines 262-263). Verified at the call site: `handleDice` passes `senderId: model.sender.id` — an authenticated, connection-bound identity (`MasterController.accepts(_:origin:)` robustly binds one connection to one sender, no bypass found) — but `resultCategory` itself comes from `model.data.data`, the message *payload*, which is set entirely client-side when a roll is initiated and is never independently checked against the sender's identity.
- **Why:** A modified or buggy player client can set `resultCategory` to any other combatant's `gameCharacterId`/`sourceCharacterId` — values every player already sees over the wire in ordinary map/battle broadcasts — and have that roll recorded against a combatant it doesn't own: another player's character, or an NPC/monster only the master should control. This corrupts the shared initiative/roll history visible to the whole table.
- **Action:** Before trusting `characterCombatant`, verify the resolved combatant is either the master's own local roll (`isMaster == true`) or that `senderId` matches a player authorized for that specific combatant (`characterCombatant.isPlayer && (characterCombatant.pinId == senderId || characterCombatant.pin.players.contains(senderId))`), falling back to the existing `playerCombatant` resolution otherwise.
- **Severity:** High

### 6.2 `lastUsedMasterJoinCode` stored in UserDefaults, unlike its sibling join codes
- **Location:** `Modules/GameRPG/Network/GameJoinCodeModel.swift:65-77`
- **What:** `masterCode`/`playerCode` (this device's own advertised codes) were moved to Keychain under a prior audit item, using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` specifically so they're excluded from unencrypted local device backups. `lastUsedMasterJoinCode` — the code this device used to successfully join *another* device's game, auto-retried on the next "Connect" tap — is still persisted via plain `UserDefaults`, with an in-code rationale that it's "not a secret this device presents."
- **Why:** It remains a live authentication secret: the exact 4-digit code currently granting access to someone else's running game session, and under the same threat model that justified moving the sibling codes off UserDefaults, it stays eligible for inclusion in unencrypted local device backups for as long as it's remembered.
- **Action:** Move it into the same `JoinCodeStorage`/Keychain mechanism as `masterCode`/`playerCode` (a third key on `KeychainJoinCodeStorage`), or explicitly document the accepted residual exposure if the short practical lifetime is judged acceptable.
- **Severity:** Medium

### 6.3 Battle-health debug logging uses `.public` for in-game character/pin data
- **Location:** `Modules/MapRPG/Controller/GameController+Battle.swift:454-457,498-533`
- **What:** `synchronizeBattleDefenders` and `healthPercent(for:)` log combatant/pin names, the resolved hit-points entry's name/raw value string, and computed health percentages with `privacy: .public` on every master tick while a battle runs — for every combatant, every time. Comparable in-game content elsewhere in the same file set is deliberately `.private` (e.g. `RPGSharePlayController.swift:774`).
- **Why:** `.public` fields are retained in full in device logs collected via Console.app/sysdiagnose with no debugging profile required, unlike `.private` fields which are redacted by default. Not PII, but it's live gameplay content leaking into system logs more broadly than necessary, and inconsistent with the privacy posture used elsewhere for comparable data.
- **Action:** Switch these debug-only logs to `privacy: .private`, or gate them behind a debug-only flag.
- **Severity:** Low

### 6.4 `ConnectionAttemptThrottle.sources` grows without bound or expiry
- **Location:** `Modules/GameRPG/Network/ConnectionAttemptThrottle.swift:17-55`
- **What:** `sources: [String: State]` accumulates one entry per distinct source that ever calls `recordFailure(source:)`, pruned only by a matching `recordSuccess(source:)`. A source that fails once or twice (below the 3-strike threshold) and never authenticates successfully — a network scanner, a misconfigured device, someone who gives up after a typo — leaves a permanent entry for the life of the hosting session.
- **Why:** On a long-running or frequently-restarted session on a busy network (venue Wi-Fi, convention), this dictionary — which exists specifically to defend against unauthenticated connection attempts — can itself grow unboundedly from those same attempts, a minor but real memory-growth concern with no cap or eviction.
- **Action:** Add a bound (max tracked sources, evicting oldest) or a time-based expiry sweep, mirroring the bounded/evicting patterns already used elsewhere in this module (e.g. `GameRelayAdmission`, `SharePlayPlayerJournalAdmission`).
- **Severity:** Low

---

## 7. Performance

### 7.1 `broadcast(mapId:)` recomputes every combatant's health percent on every battle action
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundController.swift:350-364`; `Modules/MapRPG/Controller/GameController+Battle.swift:398-468` (`synchronizeBattleDefenders`, its final loop at 452-465)
- **What:** Every mutating entry point on `BattleRoundController` (`start`, `end`, `activateAttacker`, `nextAttacker`, `nextRound`, `addCombatant`, `removeCombatant`, `setDead`, `assignCharacter`) funnels through `broadcast(mapId:)`, which unconditionally calls `synchronizeBattleDefenders`. Its final loop iterates every combatant and calls `healthPercent(for:)` — a `gameEntry` lookup plus `calculatedValue` link-resolution that can recursively walk chained formula entries — and emits one `.public` debug log line per combatant, regardless of whether the triggering action (e.g. simply advancing to the next attacker) could possibly have changed anyone's HP.
- **Why:** For a battle with many combatants and/or complex linked-value formulas, every turn/round advance pays the full HP-recompute-and-log cost for the entire roster instead of just the combatants whose underlying values actually changed — avoidable synchronous `@MainActor` work on every single battle action during a live session.
- **Action:** Track which combatants' linked hit-points entries have actually changed since the last sync (e.g. via existing `ValueModel.entries` observation) and limit the recompute/log loop to those, or throttle the full-roster recompute to a lower cadence than "every action" while keeping the cheaper highlight/defender-sync logic on the fast path.
- **Severity:** Medium

---

## 8. SwiftUI / UI

### 8.1 View decomposed via a computed property instead of a `View` struct
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundSettingsView.swift:72-101` (`BattleRoundPatternSection.addRow`)
- **What:** `addRow` is a `private var addRow: some View { ... }` computed property containing a full `HStack` with a `TextField`, two `Button`s, and a `.battleLinkCharacterDropDestination` modifier — a genuine subview's worth of content, organized as a computed property rather than the project's mandated separate `View` struct.
- **Why:** The project rule ("Do not break views up using computed properties; place them into new View structs instead") exists specifically to preserve SwiftUI's per-type diffing/identity — a computed property gets re-evaluated as part of its parent's body with none of the independent-update benefits a real `View` struct gets.
- **Action:** Extract into `BattleRoundPatternAddRow: View`, taking `kind`/`settings`/`controller`/`screenModel` (or just the pieces it needs) as stored properties.
- **Severity:** Medium

### 8.2 Combatant drag-to-reorder has no VoiceOver-accessible alternative
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundList.swift:38-54`
- **What:** Reordering the turn order is implemented purely via `.draggable`/`.dropDestination(for: String.self)` on each `BattleRoundCard` inside a plain `ForEach` (not a `List` with `.onMove`, which VoiceOver supports natively via Edit-mode reordering). No `.accessibilityAction` (e.g. "Move Up"/"Move Down") is attached anywhere in the file or its card subviews.
- **Why:** A VoiceOver or Switch Control user has no way to reorder combatants at all through this UI — the "Drag to reorder" label at the top of the list (line 22-33) describes a capability that is entirely unavailable to them. This is a total, not partial, feature gap for that user population.
- **Action:** Add custom `.accessibilityAction(named:)` entries (e.g. "Move earlier in turn order" / "Move later") on each card that call `controller.moveEntries(_:_:)` with the same semantics as the drag handler, or migrate the list to `List` + `.onMove` if the surrounding layout allows it.
- **Severity:** High

### 8.3 Missing `Equatable` on hot leaf views one level below the existing optimization
- **Location:** `Modules/GameRPG/BattleRound/BattleParticipantColumn.swift` (whole file); call sites at `Modules/GameRPG/BattleRound/BattleDefenderStrip.swift:29-40`, `BattleRoundWideCardLayout.swift:20-29`, `BattleRoundCompactCardLayout.swift:21-30`
- **What:** `BattleRoundCard` is already `Equatable` with `.equatable()` applied at its `ForEach` call site in `BattleRoundList.swift:39-46` specifically because it's "re-rendered on every live Battle Round tick" (per its own doc comment). `BattleParticipantColumn` — the attacker/defender row rendered multiple times inside every card — has no equivalent `Equatable` conformance or `.equatable()` at its own call sites.
- **Why:** Because `BattleRoundCard`'s equality check is at whole-card granularity, any single defender's HP or roll changing forces SwiftUI to re-diff the entire card's body — the rank badge, attacker column, and every sibling defender — even though only one participant's displayed data actually changed. This is the same performance concern the codebase already solved one level up, just not carried down to the next level of the tree.
- **Action:** Add `Equatable` to `BattleParticipantColumn` (comparing `presentation`, `isActive`, `tint`, and `controller.root` identity, excluding the three closures as `BattleRoundCard` already does) and apply `.equatable()` at its three call sites.
- **Severity:** Medium

### 8.4 Pervasive hard-coded padding/spacing literals
- **Location:** Representative sample — `Modules/GameRPG/BattleRound/BattleRoundHeader.swift:41-42`, `BattleRollResults.swift:17-18`, `BattleRoundCompactCounter.swift:17-18`, `BattleRoundAnnouncementCounter.swift:26`, `BattleRankBadge.swift:13,15` — dozens more instances across nearly every file in the folder
- **What:** Virtually every view in this scope specifies numeric padding/spacing literals directly (`.padding(.horizontal, 16)`, `spacing: 12`, `spacing: 4`, `padding(8)`, etc.) rather than referencing a shared spacing scale.
- **Why:** The project's own rule is to avoid hard-coded padding/spacing values, and with no design-token system evident anywhere in this scope, every visual-rhythm adjustment has to be found and changed literal-by-literal across dozens of files.
- **Action:** This is a systemic, codebase-wide gap rather than a per-file bug — treat as one cross-cutting item (see §10) rather than fixing file-by-file: introduce a small spacing-token enum/namespace (e.g. `Spacing.small = 4`, `.medium = 8`, `.large = 16`) and adopt it incrementally as files are touched.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

This subsystem is unusually clean for a mature, multi-year codebase: **zero** `#if false` blocks, zero commented-out code blocks, zero `TODO`/`FIXME`/`HACK`/`XXX`/`#warning` markers, zero raw `print()`/`NSLog()` calls (the `Logger`/`os.log` convention is used consistently throughout), and zero unreferenced `private` symbols were found anywhere in scope.

### 9.1 Files to delete outright
_No findings — no stale, unreferenced, or `#if false`'d files exist in this scope._

### 9.2 Duplicated `NetworkCodableDataType(type: .map, …)` construction
- **Locations:** `Modules/MapRPG/Controller/GameController.swift:319-327`; `GameController+Metadata.swift:103-112,115-125`; `GameController+MapSync.swift:29-39,42-52`; `GameController+Battle.swift:537-551`
- **What:** Six separate functions each build a `NetworkCodableDataType` literal with `type: .map` and the same `version`/`assetVersion`/`contentVersion` triple, differing only in the payload and which source supplies the three version fields (three intentionally read `mapGameModel.authoritativeGeneration(for:)`; three intentionally bypass it for package-export paths).
- **Action:** Extract one private factory (e.g. `func mapNetworkData(for itemId: UUID, generation: MapGameModel.AuthoritativeGeneration, data: Data?) -> NetworkCodableDataType`) and have all six call sites pass in whichever generation source they already compute; document at each call site why it does or doesn't use `networkGeneration(for:)`.
- **Severity:** Medium

### 9.3 Duplicated "current generation" validation guard
- **Locations:** `Modules/MapRPG/Controller/GameController+Pins.swift:161-177` (`updatePinIfCurrentGeneration`) vs. `GameController+Battle.swift:553-567` (`applyBattleRoundUpdate`)
- **What:** Both independently compute `networkGeneration(for: itemId)` and run the identical six-condition guard before doing their own type-specific work.
- **Action:** Extract `private func isCurrentGeneration(_ data: NetworkCodableDataType, for itemId: UUID) -> Bool` next to `networkGeneration(for:)` in `GameController+Metadata.swift`, and have both call sites use it. (Note: fixing §5.2's missing reconciliation path is a good moment to do this extraction at the same time.)
- **Severity:** Medium

### 9.4 Pin timestamp-bump-and-write idiom reimplemented instead of reusing `updatePinState`
- **Locations:** `Modules/MapRPG/Controller/GameController+Battle.swift:101-111,124-138,334-344`; canonical helper at `GameController+Metadata.swift:322-340` (`updatePinState`); related inline duplication at `GameController+Pins.swift:274-279,283-289`
- **What:** `updatePinState(itemId:pinId:mutation:)` already exists to "mutate → bump `timeInterval` → write back → sync `playerPins` if needed" as one unit, and is used correctly by `movePin`/`togglePin`/`zoomPin`/`toggleDeadPin`/`resizePin`/`toggleHighlightPin`. Three sites in `GameController+Battle.swift` (`makeBattleCombatant`, `clearBattleHighlights`, `assignBattleCharacter`) hand-roll the identical four-line tail instead.
- **Action:** Add an overload `@discardableResult func updatePinState(itemId:pinId:mutation:) -> MapPinModel?` returning the mutated pin (the three Battle sites need the value back, which the existing `Bool`-returning version doesn't provide), and route all three through it. Factor the pointer sites' one-line bump into a small `TimeInterval.bumped(from:)` helper.
- **Severity:** Medium

### 9.5 `guard root.gameModel.gameConfig.isMaster` preamble repeated 15 times
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundController.swift:25,61,72,85,98,109,115,129,140,151,167,185,199,211,226`
- **What:** Every mutating method on `BattleRoundController` — the codebase's own documented "single mutation entry point" for battle state — opens with a hand-copied `guard root.gameModel.gameConfig.isMaster, let mapId = model.mapId ... else { return false }`.
- **Why:** A missed `isMaster` check here would be a real authorization bug (a player mutating battle state that should be master-only), and 15 hand-copied guards give no compiler-enforced guarantee that a future 16th method includes it.
- **Action:** Add `private var authorizedMapId: UUID? { root.gameModel.gameConfig.isMaster ? model.mapId : nil }` and collapse each guard to `guard let mapId = authorizedMapId else { return false }`, preserving each method's additional clauses.
- **Severity:** Medium

### 9.6 Retry-loop skeleton duplicated three times in `SharePlayJournalPublicationQueue.swift`
- **Location:** `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift:457-487` (`scheduleCleanup`), `498-527` (`scheduleEmergencyCleanup`), `~741-801` (inline cleanup task in the deferred-add-attempt handler)
- **What:** All three implement the same fetch-delays / `while !Task.isCancelled` / attempt-remove / sleep-with-backoff / clamp-retry-index shape; the first two are near byte-identical, the third adds an `isObsolete` short-circuit.
- **Action:** Extract `private func retryUntilRemoved(_ attachment: Attachment, delays: [Duration], isObsolete: (() -> Bool)? = nil, remove: @escaping @MainActor (Attachment) async -> Bool, finish: @escaping () -> Void) async` and have all three call it.
- **Severity:** Medium

### 9.7 Connection-throttle bookkeeping duplicated between Master and Player network controllers
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:35-39,179-227`; `Modules/GameRPG/Player/PlayerNetworkController.swift:37-41,114-116,142-160,176-186,274`
- **What:** Both independently declare `connectionThrottle`/`pendingConnectionSources` and hand-implement the identical register/record-failure/record-success/clear lifecycle at each call site.
- **Why:** This is the mirror-image implementation of the exact anti-brute-force feature a prior audit item added; keeping the bookkeeping duplicated means a future correctness fix to this security-relevant logic must be reapplied and reverified in two places.
- **Action:** Extract a small `ConnectionThrottleTracker` wrapping `ConnectionAttemptThrottle` + the pending-sources dictionary with `register(id:source:)`/`recordFailure(id:)`/`recordSuccess(id:)`/`clear(id:)`/`shouldAllow(source:)`; have both controllers hold one instance. Good opportunity to apply §3.2's `ContinuousClock` fix in the same pass.
- **Severity:** Medium

### 9.8 `MasterNetworkControllerDelegateBox` / `PlayerNetworkControllerDelegateBox` structural duplication
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:8-25`; `Modules/GameRPG/Player/PlayerNetworkController.swift:8-25`
- **What:** Two nearly-identical `actor` types exist purely to hold a `weak` delegate and forward each protocol method as an `async` call.
- **Action:** Low priority — a generic `actor WeakDelegateBox<Delegate: AnyObject>` is only worth it if a third such box appears; otherwise each box's forwarded signatures genuinely differ enough to leave as-is.
- **Severity:** Low

### 9.9 `BattleRoundCompactCardLayout`/`BattleRoundWideCardLayout` share their entire property list
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundCompactCardLayout.swift:6-12,16-30,46-54`; `BattleRoundWideCardLayout.swift:6-12,16-29,39-47`
- **What:** Both declare the identical 6 stored properties and construct the same four subviews with the same argument lists; only the surrounding `HStack`/`VStack` arrangement differs (which is the legitimate, intentional divergence per the module's layout-switching design).
- **Action:** Bundle the 6 shared properties into one `BattleRoundCardLayoutContext` struct both layouts take as a single parameter, so a future added field is declared once instead of twice.
- **Severity:** Low

### 9.10 Oversized files (>500 LOC)
- **`Modules/GameRPG/SharePlay/RPGSharePlayController.swift` — 2,509 lines.** Zero `// MARK:` sections across the whole file. ~600 lines of standalone helper types precede the class; the class + extensions then mix session lifecycle, chunked-message transport, and Journal attachment handling in one continuous body. Split along the visible seams: keep core lifecycle in this file; move pre-class helpers to `RPGSharePlayControllerSupport.swift`; move the transport extension to `RPGSharePlayController+Transport.swift`; move Journal handling to `RPGSharePlayController+Journal.swift`. **Severity: High** (this is the file most likely to hide a hard-to-spot bug on a future edit, given its size and total lack of navigation aids).
- **`Modules/GameRPG/Network/GameNetworkController.swift` — 1,156 lines.** The class itself already uses `// MARK:` well, but ~500 lines ahead of it are two unrelated, independently-testable admission/dedup actors (`GameRelayAdmission`, `SharePlayPlayerJournalAdmission`) that belong in their own files; the 182-line `routeSharePlayUpdate` (897-1079) should also be broken into named steps. Severity: Medium.
- **`Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift` — 1,086 lines.** Already cleanly `// MARK:`-divided into 5 independent, generic types with no cross-references — a low-risk, mechanical split at the existing section boundaries into 3 files. Severity: Medium.
- **`Modules/GameRPG/Model/GameNetworkModel.swift` — 1,023 lines.** Only one `// MARK:` in the whole file; a ~300-line routing/audience-policy extension (367-671) — arguably the most worth isolating and unit-testing — is currently indistinguishable in the outline view from the surrounding plain data-model code. Split into the envelope model, the routing-policy extension, the V1 wire-compat shim, and the message pipeline actor. Severity: Medium.
- **`Modules/MapRPG/BattleRound/BattleRoundModel.swift` — 635 lines.** First 124 lines are plain value types unrelated to the `@Observable` class that follows; the class itself has no section markers separating lifecycle/turn-progression/combatant-mutation/rolls/network-sync. Move the value types to `BattleRoundTypes.swift`; add `// MARK:` sections (or further per-concern extension files, mirroring the `GameController+*` split already used one module over). Severity: Medium.
- **`Modules/MapRPG/Controller/GameController+Battle.swift` — 575 lines.** Borderline; five distinguishable concerns (combatant lifecycle, turn/initiative, rolls & values, defender/health sync, network apply/export) with no `// MARK:` dividers. At minimum add section markers; split `synchronizeBattleDefenders`/`healthPercent` into `GameController+BattleSync.swift` if the file grows further. Severity: Low.

### 9.11 Naming typos & filename mismatch
- `receivedPacakges` → `receivedPackages` — `Modules/GameRPG/SharePlay/SharePlayPackageReceiver.swift:53,71,113,144,182,221` (plus 7 references in `Tests/GameRPGTests/SharePlayPackageTransportTests.swift`, since it's `private(set)`).
- `resetConntections` → `resetConnections` — `Modules/GameRPG/Master/MasterNetworkController.swift:79,94,109,121` (private, single-file rename), plus a prose reference in a comment at `Modules/GameRPG/Network/ConnectionController.swift:50`.
- `SharePlayPackageSender.swift`'s primary type is actually `SharePlaySingleQueuePackageSender` (`Modules/GameRPG/SharePlay/SharePlayPackageSender.swift:16`) — rename the file to match.
- **Severity:** Low (all three are mechanical, low-risk renames)

### 9.12 Magic constants
- `24*60*60` inline in `Task.sleep(for: .seconds(24*60*60))` — `Modules/GameRPG/Network/ListenerManager.swift:151` — every other timing constant in this scope is a named `static let`; this is the one exception.
- Join-code length `4` duplicated between `randomCode()`'s zero-padding logic and `isValidCode(_:)`'s length check — `Modules/GameRPG/Network/GameJoinCodeModel.swift:80-83,102-103` — worth a shared `codeLength` constant especially since lengthening the code is the residual anti-brute-force gap noted in a prior audit item.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Formalize the "generation must match exactly, else defer and retry" pattern as a shared, reusable mechanism.** Right now `.mapPin` has defer/retry (`awaitingMapGeneration`/`deferMapPin`/`retryDeferredMapPins`) and `.battleRound` doesn't (§5.2), while the *validation guard itself* is independently duplicated between the two paths (§9.3). Fixing both at once — extracting the guard **and** giving it a generic defer/retry companion any future subtype can opt into — closes the current gap and prevents the next new subtype from repeating the same omission.
2. **Extract a shared `ConnectionThrottleTracker`.** §9.7 (duplicated bookkeeping) and §3.2 (wrong clock type) both live in the same security-relevant code, hand-copied across Master and Player. One extraction fixes both findings simultaneously and gives this anti-brute-force mechanism exactly one implementation to audit going forward.
3. **Adopt `// MARK:` sections and file-splitting consistently across the module's largest files.** Five of the six oversized-file findings in §9.10 are otherwise well-written files that are simply hard to navigate; `SharePlayJournalPublicationQueue.swift`'s already-clean section boundaries show this doesn't require re-architecting, just drawing file boundaries where the sections already are.
4. **Introduce a small spacing/design-token system for SwiftUI views**, starting with BattleRound (§8.4) where the gap is most visible, per the project's own stated (but currently unenforced) rule against hard-coded padding/spacing.
5. **When touching any of the `guard isMaster`/authorization-adjacent code** (§9.5, §6.1), prefer a shape the compiler can help enforce (a computed property, a wrapper type) over hand-copied guard clauses — this is a pattern where a single missed copy is a real security regression, not just a style nit.

---

## 11. What was NOT audited

- Every other `GameRPG` subdirectory not explicitly in scope: `Statistics/`, `GameCenter/`, `ExternalScreen/`, `SetupViews/`, `Search/`, `Browser/`, `Table3D/`, `Root/`, and the wider `GameViews/` (only `BattleRoundWindowView.swift`/`BattleRoundSideOverlay.swift`/`GameToolbarContent.swift`'s embedding of BattleRound views was noted in passing, not reviewed for their own correctness).
- Every other `MapRPG/Controller` file besides the `GameController*` family: `CacheController`, `DataController`, `EditController`, `ExportController`, `FolderListController`, `ImportController`, `ItemController`, `LinkController`, `MapDataController`, `SearchController`, `SheetController`, `SyncDataController`, `ViewController`.
- `MasterController.swift` and `PlayerController*.swift` beyond the specific call sites cited for verification (`handleDice`, `applyPlayerMapPin`/`retryDeferredMapPins`, `game(message:actionType:playerId:)`) — these are large files serving many modules beyond BattleRound/Map, and a full pass over them was out of scope.
- Core Data / CloudKit sync itself (`NSPersistentCloudKitContainer` merge behavior) — out of scope; this audit covers only the live in-session network protocol.
- Algorithmic correctness of GroupActivities/SharePlay's own framework behavior — treated as a black box; only this app's usage of it was reviewed.
- Build settings, scheme configuration, and Xcode project structure beyond what's visible in the two schemes built for warning capture.
- Third-party SPM dependency internals (`RPGTabletopGameContent`, `swift-syntax`, `xctest-dynamic-overlay`, `swift-snapshot-testing`, `swift-custom-dump`).
- **Test coverage depth.** A directory scan found substantial existing test coverage directly relevant to this scope (`BattleRoundControllerTests`, `BattleRoundModelTests`, `BattleRoundDiceAttributionTests`, `GameNetworkModelVersionTests`, `ConnectionAttemptThrottleTests`, `MasterNetworkControllerTests`, `PlayerNetworkControllerTests`, and more) — this is a positive signal, but no line-coverage analysis or test-quality review was performed. Notably, `BattleRoundDiceAttributionTests` exists and is worth checking against §6.1 specifically — it may already partially exercise this path.
- Localization string wording and correctness (all strings observed use `bundle: .module` correctly per project convention; wording itself wasn't assessed).
- Instruments profiling / hitches — §7.1's performance finding is based on static code reading, not a captured trace.
- Other platforms' (MasterMac, MasterTV) target-specific entitlements and conditional-compilation branches beyond what's visible inline as `#if os(...)` in the files reviewed.

---

## 12. Verification

For the three High-severity findings, here's what was independently confirmed by opening the cited lines (all three were personally re-verified, not just taken from the background agents' reports):

- **§6.1** — open `Modules/GameRPG/BattleRound/BattleRoundController.swift`, lines 243-270, alongside `Modules/GameRPG/Controller/MasterController.swift`, lines 1409-1431. Confirm `recordDiceResult`'s `characterCombatant` (resolved from `diceResult.diceModel.resultCategory.id`) is checked *before* — and takes priority over — the `senderId`-derived `playerCombatant` fallback at line 262-263, with no check that `characterCombatant` actually belongs to `senderId`. Then confirm at `MasterController.swift:1425-1430` that `senderId`/`isMaster` come from `model.sender` (authenticated) while `diceResult` is decoded from `model.data.data` (the unauthenticated payload) two lines below.
- **§5.2** — open `Modules/MapRPG/Controller/GameController+Battle.swift`, lines 553-567, and compare against `Modules/GameRPG/Controller/PlayerController+Map.swift`, lines 294-311 and 582-611. Confirm the `.mapPin` case flows through `applyPlayerMapPin`, which returns `.awaitingMapGeneration` on a mismatch (line 584/591) and is queued via `deferMapPin`/`retryDeferredMapPins` — and confirm the `.battleRound` case (line 307-311) has no equivalent branch, just `return nil` on `applyBattleRoundUpdate` failure.
- **§8.2** — open `Modules/GameRPG/BattleRound/BattleRoundList.swift`, lines 20-83. Confirm the `.draggable`/`.dropDestination` pair is the only reordering mechanism (lines 50-53) and that no `.accessibilityAction` modifier appears anywhere in this file or in `BattleRoundCard.swift`/`BattleParticipantColumn.swift`.

If any finding doesn't reproduce when you visit the line, flag it and it'll be re-investigated.
