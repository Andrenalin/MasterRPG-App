# MasterRPG — Join Code, Keychain & Bonjour Connection Audit

Generated 2026-09-21. **Scope: narrow and deep** — everything that touches the LAN join secret, its storage and the Bonjour discovery / connect / reconnect path, plus the views that expose it. Read-only; no code was changed.

**Files in scope (all read in full):**
- Join code & Keychain: `Modules/GameRPG/Network/GameJoinCodeModel.swift`, `JoinCodeStorage.swift`, `ConnectionAttemptThrottle.swift`, `ConnectionThrottleTracker.swift`, `NWParameter+GameMaster.swift`
- Bonjour / connection: `Modules/GameRPG/Browser/BrowserManager.swift`, `GameServiceType.swift`, `Network/ListenerManager.swift`, `Network/ConnectionController.swift`, `Player/PlayerNetworkController.swift` (+Model), `Master/MasterNetworkController.swift` (+Model), `Resources/Info.plist` / `InfoTV.plist`
- Views & wiring: `Browser/BrowserRowView.swift`, `SetupViews/{BrowserView,SearchProxyView,GameJoinCode*,SelectedAdventureView,SelectedPlayerView}.swift`, `GameViews/{GameJoinCodeRevealButton,GameToolbarContent,OverlayGameMenu,IOSGameOverlayControlField,IOSGameConnectionStatusView,GameChromeStatusPresentation,GameRootViewer}.swift`, `Root/GameRoot.swift`, `Controller/{Master,Player}Controller+Control.swift`, `RolePlayGameKit/View/SettingsView.swift`
- Tests: `Tests/GameRPGTests/{ConnectionAttemptThrottle,MasterNetworkController,PlayerNetworkController}Tests.swift`

**Relationship to earlier audits.** This subsystem has been audited before (`Docu/CODE_AUDIT_15.md` §6, `CODE_AUDIT_16.md` §3.7–3.9/§5.6/§6.2/§6.5, `CODE_AUDIT_Reconnect.md`, `CODE_AUDIT_Network.md`). Items already fixed were spot-checked and still hold (handshake deadline, `.failed`/`.cancelled` de-duplication, stale-cancellation guards, verified-write migration). Findings below are either **new**, or **still open** and marked *(still open — Audit N §x)* where new evidence changes the picture.

**Compiler ground truth (Step 2).** `xcodebuild -workspace MasterRPG.xcworkspace -scheme RolePlayGameKit` (iOS Simulator, iPhone 17 Pro, Debug; there is no standalone `GameRPG` scheme) ran 1,390 Swift compile steps and produced **zero Swift compiler warnings and zero Swift errors**. The build did **not finish**: the link step failed in `RuleRPG` and `SpaceRPG` with `Undefined symbols … CoreRPG.DatabaseReadiness.wait()` — the known stale-`EagerLinkingTBDs` symptom from a dirty tree with new public `CoreRPG` API (see memory note; a clean build resolves it), not a defect in audited code. No clean build was run. Consequently there is no concurrency-warning list to cross-reference; §3 is from reading.

**Severity outcome.** No finding met the **Critical** bar (crash / data loss / memory corruption / credential exposure). The 4-digit-PSK and Bonjour-DoS items were the candidates; both were re-traced and kept at **High** because they expose or disrupt a game session, not credentials or persistent data (§12).

---

## 1. Executive summary

1. **[High] The fallback (reconnect) listener is one-shot: the first inbound TCP connection — before any authentication — discards the listener, and if that connection then fails the player is fully stopped and never re-advertises** — §5.1 — `Modules/GameRPG/Player/PlayerNetworkController.swift:412-435,240-269,168-194`.
2. **[High] A Game Master dials every device advertising `_gamemasterplayer._tcp` on the LAN, including other groups' players** — so an unrelated master (or scanner) can trigger §5.1 for someone else's session — §5.2 — `Modules/GameRPG/Master/MasterNetworkController.swift:316-333,368-377`.
3. **[High] A failed listener or browser is never recovered; a listener failure silently drops every live player** — §5.3 — `Modules/GameRPG/Network/ListenerManager.swift:108-122`, `Master/MasterNetworkController.swift:122-148,234-236`, `Browser/BrowserManager.swift:108-116`.
4. **[High] The 4-digit join code can be recovered offline, and two automatic-dial paths hand an attacker a crackable handshake without any sniffing** *(still open — Audit 15 §6.1 / Audit 16 §6.5)* — §6.1 — `Network/NWParameter+GameMaster.swift:45-83`, `Master/MasterNetworkController.swift:368-377`, `Browser/BrowserRowView.swift:24-29`.
5. **[High] Unauthenticated Bonjour advertisements can fill the master's 32 connection slots and block every join** — §6.2 — `Master/MasterNetworkController.swift:242-246,355-377`.
6. **[Medium] Keychain read errors are treated as "no code" and silently regenerate the code players were told; write failures are dropped** *(still open — Audit 16 §5.6, partly)* — §5.5 — `Network/JoinCodeStorage.swift:28-40`, `Network/GameJoinCodeModel.swift:111-127,170-184`.
7. **[Medium] The code shown to players can differ from the code the running listener uses after "Reset Join Codes"** — §5.8 — `Root/GameRoot.swift:110-118`, `RolePlayGameKit/View/SettingsView.swift:147-149`, `Master/MasterNetworkModel.swift:42-46`.
8. **[Medium] Non-ASCII digits (Arabic-Indic, fractions, superscripts) pass code validation but derive a different PSK** — verified by script — §5.7 — `Network/GameJoinCodeModel.swift:148-150`, `SetupViews/GameJoinCodeOTPField.swift:33-38`.
9. **[Medium] Master redial to a lost player has no retry policy, backoff or connect deadline** — §5.4 — `Master/MasterNetworkController.swift:291-300,337-353,368-377`.
10. **[Medium] Joining gives no progress state and every failure reason collapses into "re-enter the code"** — §8.1, §8.2 — `Browser/BrowserRowView.swift:24-33,82-103,112-120`.

---

## 2. Quick wins (≤30 min each)

- **Restrict join-code validation and the OTP filter to ASCII `0`–`9`** — `GameJoinCodeModel.swift:148-150`, `GameJoinCodeOTPField.swift:33-38`. See §5.7.
- **Read out join codes digit-by-digit for VoiceOver** on the four places that show one — `GameJoinCodeRevealButton.swift:69`, `GameJoinCodeSetupButton.swift:32-33,44`, `GameJoinCodeOTPField.swift:32`, `GameRootViewer.swift:276`. See §8.4.
- **Pass `isReconnecting` at the three call sites that omit it** — `GameToolbarContent.swift:63-67`, `OverlayGameMenu.swift:433-437`, `IOSGameConnectionStatusView.swift:18-21`. See §8.3.
- **Delete the never-assigned `BrowserManager.errorMessage` and the unused `NetworkState.tlsFailed` / `.connected`** (or wire them, §8.2) — `BrowserManager.swift:15-22,31`. See §9.1.
- **Log (privacy-safe) when `flush` fails to write or remove a code** — `GameJoinCodeModel.swift:177-183`. See §5.5.
- **Clear `PlayerNetworkModel.passcode` in `PlayerNetworkController.stop()`** — `Player/PlayerNetworkController.swift:168-194`. See §6.4.
- **Add unit tests for `GameJoinCodeModel` using the existing `init(defaults:codeStorage:)` seam** — see §9.3.

---

## 3. Concurrency

Compiler ground truth: zero Swift warnings (see preamble). The items below are design-level.

### 3.1 `PlayerNetworkController.restart(connection:)` replaces the controller without cancelling the old one
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift:211-217`; `Player/PlayerNetworkModel.swift:66-68`
- **What:** `reset(controller:)` only assigns; the replaced `ConnectionController` is never `cancel()`ed. Audit 16 §3.1 fixed exactly this on the master side (`resetConnections`), noting the receive loop holds the controller strongly so dropping the reference never reaches `deinit`.
- **Why:** When the Bonjour removal of the master's service is seen before the TCP connection errors (the normal order on a master shutdown), `lostConnection` marks the player lost but leaves the old socket up. After the master redials, the old `NWConnection` and its receive loop live on until TCP finally fails; its callbacks are ignored by `isCurrentConnection`, so this is a bounded leak, not corruption.
- **Action:** Cancel the previous controller (as `stop()` does) before installing the replacement, mirroring the master-side fix.
- **Severity:** Low

### 3.2 `BrowserManager`'s event loop has no run-generation guard (unlike `ListenerManager`)
- **Location:** `Modules/GameRPG/Browser/BrowserManager.swift:64-68` vs `Network/ListenerManager.swift:71-76`
- **What:** `ListenerManager` checks `runGeneration` before applying each event; `BrowserManager` applies `handleStateEvent` unconditionally (Audit 16 §3.8 added the guard only for the terminal `catch` blocks).
- **Why:** An event already dequeued when `stop()`/`start()` runs can overwrite `connectionState` or `games` of the newer run. Window is tiny; the inconsistency is the risk.
- **Action:** Apply the same generation check in the monitor loop.
- **Severity:** Low

### 3.3 Keychain writes are fire-and-forget on a detached task, with blocking IPC under a `Mutex`
- **Location:** `Modules/GameRPG/Network/GameJoinCodeModel.swift:60-67,161-186`
- **What:** Each change enqueues then spawns `Task.detached(priority: .utility)` that runs `flush`, which performs synchronous `SecItem*` IPC while holding `writeLock` on a cooperative-pool thread. Nothing awaits or observes completion.
- **Why:** (a) A code changed just before the app is suspended or killed may never reach the Keychain (the UI shows the new code, the next launch loads the old one). (b) Blocking IPC on the cooperative pool is discouraged. Ordering itself is correct (Audit 15 §3.13).
- **Action:** Perform Keychain calls from a dedicated serial executor or `@concurrent` function, surface the `Bool` result, and consider a synchronous flush on scene deactivation.
- **Severity:** Low

---

## 4. API modernity

### 4.1 Legacy callback-based `NWListener` / `NWConnection` alongside the new `NetworkBrowser`
- **Location:** `Modules/GameRPG/Network/ListenerManager.swift:151-186`, `Network/ConnectionController.swift:7-17,100-112,228-244`; contrast `Browser/BrowserManager.swift:188-202`
- **What:** Discovery uses the iOS 26 async `NetworkBrowser`; listening and connecting still wrap dispatch-queue callbacks in `AsyncStream`/`CheckedContinuation` bridges (`ConnectionAbstraction`, receive-loop continuation, run-forever sleep loop).
- **Why:** The bridges are where the lifecycle bugs in §3.1, §5.1 and §5.3 live. Structured `NetworkListener`/`NetworkConnection` would tie lifetime to task scope. Whether the custom TLS-PSK options and the `GameProtocol` framer are expressible in the new API was **not verified**.
- **Action:** Evaluate migrating listener/connection to the structured Network APIs once the PSK/framer question is answered; treat as a follow-up, not a prerequisite for the fixes below.
- **Severity:** Low

### 4.2 Old-style byte/`Data` conversions in the PSK and Keychain code
- **Location:** `Modules/GameRPG/Network/NWParameter+GameMaster.swift:53-57,85-93`; `Network/JoinCodeStorage.swift:44`
- **What:** `string.data(using: .unicode)`, `value.data(using: .utf8)` (optional-returning) and `withUnsafeBytes(of: &authenticationCode)` to build `DispatchData`.
- **Why:** Non-optional `Data(string.utf8)` / `Data(authenticationCode)` forms exist; `.unicode` also prepends a BOM to the PSK identity (harmless but surprising). Style only.
- **Action:** Use the non-optional forms; drop the unreachable `guard` branches.
- **Severity:** Low

### 4.3 Shape instances instead of static members
- **Location:** `Modules/GameRPG/SetupViews/GameJoinCodeOTPField.swift:74-77`; `SetupViews/GameJoinCodeSetupButton.swift:40`
- **What:** `RoundedRectangle(cornerRadius: 8).stroke(...)` and `Capsule().stroke(...)`.
- **Why:** Project rule prefers `.rect(cornerRadius:)` / `.capsule`.
- **Action:** Switch to static-member shapes.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 The fallback listener is one-shot, and a single unauthenticated connection permanently ends a player's reconnect
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift:412-435` (`listenerNewConnection`), `:240-269` (`failed`), `:273-291` (`lostConnection`), `:168-194` (`stop`), `:225-233` (`setUpListener`)
- **What:** While `.lost`, the player advertises a fallback Bonjour service. On the *first* accepted TCP connection `listenerNewConnection` calls `reset(listener: nil)` (line 418), which deallocates the `ListenerManager` and withdraws the advertisement — **before** the TLS-PSK handshake has run. The connection then becomes the "master" connection with state `.notReady` (line 421-424). If that handshake fails (wrong code, not the master, a scanner, a foreign master — see §5.2), `failed`'s `.notReady` branch (line 245-268) or `lostConnection`'s early-return branch (277-291) calls `stop()`. `stop()` clears `playerConnectionId`, model and controller; nothing ever calls `startPlayerServer()` again (its only caller is `lostConnection` after `markLostIfCurrent`).
- **Why:** One unauthenticated TCP connect (no valid code needed) to a lost player's listener ends its ability to be redialed for the rest of the session; the player sits at "Connection Lost" until the user manually rejoins. It also makes the player-side throttle (`connectionThrottle`, lines 35-42, 413) practically moot: only one connection is ever evaluated. Not covered by tests — `PlayerNetworkControllerTests.swift` has two tests, neither touches the listener path.
- **Action:** Keep the fallback listener alive until a connection *authenticates* (`readyConnection`), and on a failed handshake return to `.lost` and keep advertising rather than calling `stop()`. Retire the listener only on success or explicit stop.
- **Severity:** High

### 5.2 The master dials every `_gamemasterplayer._tcp` advertiser on the LAN, with no scoping to its own session
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:87-89,316-333` (`refresh`), `:368-377` (`connectToPlayer`); `Browser/GameServiceType.swift:18-26`
- **What:** `startStreaming` always starts a `BrowserManager(serviceType: .master)`. `refresh(games:)` calls `connectToPlayer` for *every* endpoint the browser reports, using this master's own code. Nothing in the service name, TXT record or endpoint ties a fallback service to this game.
- **Why:** With two groups on one network (game café, convention, shared house, two tables) Master A dials Master B's lost players with A's code. The handshake fails, and because of §5.1 that permanently ends B's player's reconnect. The same auto-dial is the security exposure in §6.1 and the slot-exhaustion path in §6.2. Not runtime-verified across two real hosts; traced statically.
- **Action:** Scope reconnect advertisements to a session (for example a per-session identifier or a hash of it in the TXT record, ignored unless it matches) and dial only matching endpoints; combine with §5.1's "stay up on failure".
- **Severity:** High

### 5.3 A failed listener or browser is never recovered, and a listener failure drops every live player
- **Location:** `Modules/GameRPG/Network/ListenerManager.swift:108-122`; `Master/MasterNetworkController.swift:234-236` (`listenerCancelled` → `stopStreaming`), `:122-148` (`resetConnections`); `Player/PlayerNetworkController.swift:405-409`; `Browser/BrowserManager.swift:108-116`; `Master/MasterNetworkController.swift:316-322`
- **What:** `NWListener` `.failed` → `ListenerManager.handle` → `delegate.listenerCancelled()`. On the master that calls `stopStreaming()`, which cancels **all** connections, stops the browser and sets `isStreaming = false`. No code restarts the listener. `BrowserManager` `.browserStopped` only sets `.stopped`; `refresh` later nulls the master's `browserManager`. A repository search for `scenePhase`, `NWPathMonitor` and network-path handling under `Modules/GameRPG` finds none, and no view observes `isStreaming` or the browser's state.
- **Why:** Network.framework documents `.failed` as terminal for a listener/browser and expects the caller to recreate it. Conditions that produce it include mDNS service restarts and network transitions (behaviour on device not reproduced here). The result is a silent, session-ending failure on the GM's side: players fall back to §5.1's listeners, but the master's browser is gone so nobody redials, and the GM's UI shows no change.
- **Action:** Give listener and browser a supervised restart with backoff (recreate on `.failed`, keep connections that are still healthy), drive re-checks from scene activation and a path monitor, and surface `isStreaming`/browser state to the GM UI.
- **Severity:** High

### 5.4 Master redial has no retry policy, no backoff and no connect deadline
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:291-300` (observation watches only `games`), `:337-353` (`removeConnection` drops the endpoint from `browserConnections`), `:355-377`; `Network/ConnectionController.swift:181-218` (`.waiting` falls to `default`)
- **What:** A failed outbound dial removes its endpoint from `browserConnections`, but the only trigger for `refresh` is a change of `browserManager.games`. So a transient failure is not retried until some unrelated service appears or disappears; then *all* missing endpoints are redialed at once, unbounded, with no backoff or attempt cap. Conversely a dial stuck in `.preparing`/`.waiting` has no deadline (the 15 s deadline at `:265,270-280` covers inbound connections only) and pins its endpoint in `browserConnections` indefinitely.
- **Why:** A legitimate reconnect that races the player's listener coming up is dropped until incidental mDNS churn; a permanently failing endpoint is re-dialed on every churn.
- **Action:** Model each endpoint's dial as owned state with attempt count, exponential backoff, a connect deadline, and a cap; re-arm on failure rather than on `games` changes.
- **Severity:** Medium

### 5.5 Keychain read errors regenerate the code; write failures are dropped *(still open — Audit 16 §5.6, partly)*
- **Location:** `Modules/GameRPG/Network/JoinCodeStorage.swift:28-40`; `Network/GameJoinCodeModel.swift:111-127,132-146,170-184`
- **What:** `string(forKey:)` returns `nil` for every non-success status, so "item not found" and "keychain unavailable" are indistinguishable. `loadOrGenerate` then generates a fresh code, and (line 125) ignores the result of `set`. `flush` also ignores `set`'s `Bool` and `remove` has no result at all. Audit 16 recorded "do not regenerate on `errSecInteractionNotAllowed`" as not done.
- **Why:** Items are `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and `GameRoot` builds the model eagerly (`GameRoot.swift:38`). If the process starts while the keychain is locked (background launch after reboot or with the device locked — the app declares audio, fetch and remote-notification modes) the read fails, the model uses a new random code for that process, the existing item is not overwritten, and the next unlocked launch silently reverts to the older code — so a code already told to players stops working. Not reproduced on device. A failed `set`/`remove` in `flush` likewise leaves the UI and the store out of step with no signal.
- **Action:** Return a typed result (`found`/`notFound`/`unavailable`) from reads, generate only on `notFound`, retry or defer on `unavailable`, and log/surface write failures.
- **Severity:** Medium

### 5.6 macOS uses the legacy file-based keychain *(still open — Audit 16 §5.6, deliberately deferred)*
- **Location:** `Modules/GameRPG/Network/JoinCodeStorage.swift:29-35,45-49,57-60`
- **What:** No `kSecUseDataProtectionKeychain`, so on macOS items go to the legacy keychain, where `kSecAttrAccessible…ThisDeviceOnly` semantics and the "never syncs / excluded from backup" claim shown in Settings (`SettingsView.swift:170`) are not guaranteed the same way as on iOS. Behaviour on macOS was **not verified** here.
- **Why:** The privacy statement in Settings may not hold on Mac; legacy-keychain access can also prompt. Audit 16 declined the flag because it would orphan existing items — that concern is valid but solvable.
- **Action:** Add the data-protection flag with a one-time migration: read the legacy item, write it to the data-protection keychain, delete the legacy item only after a verified write.
- **Severity:** Medium

### 5.7 Non-ASCII digits pass validation but derive a different PSK
- **Location:** `Modules/GameRPG/Network/GameJoinCodeModel.swift:148-150`; `SetupViews/GameJoinCodeOTPField.swift:33-38`
- **What:** Both use `Character.isNumber`, which is true for Arabic-Indic digits, full-width digits, superscripts and fractions. A scratch test confirmed `"٤٨٢١"`, `"４８２１"`, `"½½½½"` and `"²²²²"` all satisfy `count == 4 && allSatisfy(\.isNumber)`, and that the HMAC-derived PSK for `"٤٨٢١"` differs from `"4821"`.
- **Why:** A Player using an Arabic or Persian numeric keypad (or pasting) enters what looks like the right code and is rejected as a wrong code; the failure also counts toward the master's throttle. Stored codes are validated the same way.
- **Action:** Accept only ASCII `0`–`9` in `isValidCode` and the field filter, or normalise via `wholeNumberValue` to ASCII before use.
- **Severity:** Medium

### 5.8 The displayed code can differ from the code the running listener uses
- **Location:** `Modules/GameRPG/Root/GameRoot.swift:110-118`; `RolePlayGameKit/View/SettingsView.swift:132-158`; `Master/MasterNetworkModel.swift:42-46`; `GameViews/GameJoinCodeRevealButton.swift:21`; `GameViews/GameRootViewer.swift:70,275-279`
- **What:** `ownJoinCode(isMaster:)` reads the *stored* code. The listener captured the code at `startStreaming` and deliberately keeps it (documented at `MasterNetworkModel.swift:42-46`). `resetJoinCodes()` has no "game running" guard and the alert text promises "Anyone using the old codes will need the new ones".
- **Why:** Resetting while hosting makes the reveal button and the empty-state screen show a code the listener does not accept, while the old code keeps working. New players fail to join with the code they were just shown. Whether Settings is reachable mid-game on every platform was not checked.
- **Action:** Show the session's captured code while a game runs, or block/defer reset until the session ends, and adjust the alert copy.
- **Severity:** Medium

### 5.9 "Last used Game Master code" is one global slot that is auto-tried against every host
- **Location:** `Modules/GameRPG/Browser/BrowserRowView.swift:24-29,77-80`; `Network/GameJoinCodeModel.swift:83-91`
- **What:** Tapping Connect on any Game Master with a saved code dials immediately with that code, without asking. The code is not tied to a host.
- **Why:** For any different GM the first attempt is a guaranteed TLS failure, which counts as one of the master's three allowed failures (`ConnectionAttemptThrottle.failureThreshold`), leaving two typos before a lockout. It also sends a handshake derived from GM A's code to an arbitrary advertiser (see §6.1). Design is documented in the throttle comment, but its costs are not.
- **Action:** Remember the code per host (service name plus a session identifier), and only auto-try for the host it was saved for.
- **Severity:** Medium

### 5.10 The Bonjour service name is the raw adventure title
- **Location:** `Modules/GameRPG/Root/GameRoot.swift:306-311`; `AdventureRPG/Root/AdventureRootModel.swift:334-336`; `Network/ListenerManager.swift:152-154`; `Browser/BrowserManager.swift:166-168`
- **What:** The advertised name is `adventureTitle` (user text, untrimmed, any length). DNS-SD instance names are limited to 63 UTF-8 bytes; whether `NWListener.Service` rejects or truncates a longer name was **not verified**. Separately, `BrowserGameModel.deviceName` cuts the name at the first `.`, so "Curse of Strahd Vol. 2" displays as "Curse of Strahd Vol", and two hosts differing only after a dot collapse together in `SearchProxyView.visibleProxyBrowsers` (`SearchProxyView.swift:80-86`).
- **Why:** If a long title makes the listener fail, it fails silently (§5.3) and the GM cannot host. The dot truncation is certain by reading: wrong labels and wrongly hidden proxy hosts.
- **Action:** Advertise a sanitized, byte-bounded name and carry the display title in the TXT record; drop the "prefix until dot" heuristic.
- **Severity:** Medium

### 5.11 The last-used code is saved from a view's `onChange`
- **Location:** `Modules/GameRPG/Browser/BrowserRowView.swift:63-69`, `:82-103`
- **What:** Saving a successful code depends on `isConnected` changing while this row is still on screen; `connect(joinCode:)` itself already knows the outcome (`root.gameModel.gameConfig.state == .started`).
- **Why:** If the row leaves the hierarchy first (navigation into the game), the code is not saved and the next join re-prompts. Timing was not reproduced.
- **Action:** Persist the code in `connect` after a confirmed start.
- **Severity:** Low

---

## 6. Security

### 6.1 The 4-digit TLS-PSK is recoverable offline, and two automatic dials hand out a crackable handshake *(still open — Audit 15 §6.1, Audit 16 §6.5)*
- **Location:** `Modules/GameRPG/Network/NWParameter+GameMaster.swift:45-83` (PSK = `HMAC-SHA256(key: code, "GameMaster")`, fixed identity, `TLS_PSK_WITH_AES_128_GCM_SHA256`); `Network/GameJoinCodeModel.swift:94-97,154`; `Master/MasterNetworkController.swift:368-377`; `Browser/BrowserRowView.swift:24-29`
- **What:** Plain TLS-PSK lets anyone holding one handshake test candidate PSKs offline; the keyspace is 10,000 and the derivation has no salt or work factor (10,000 derivations measured at 34 ms for the HMAC step alone). Audit 16 §6.5 describes the *passive* case. Two **active** paths need no sniffing: (a) the master automatically dials every `_gamemasterplayer._tcp` advertiser with its own code (§5.2), so an attacker who advertises that service receives the master's client handshake; (b) a Player tapping Connect on any advertiser of `_gamemastermaster._tcp` auto-sends the *saved* code's handshake (§5.9), so a rogue "master" learns the real GM's code.
- **Why:** The online throttle (3 failures → lockout) is irrelevant to offline recovery. With the code an attacker can join as a player and send state to the master, and the missing forward secrecy exposes recorded traffic. Kept at High, not Critical: it grants access to a game session on a shared LAN, not credentials or persisted data.
- **Action:** Treat as the pending product decision, but note it is now exploitable without eavesdropping. Options: a longer or alphanumeric code stretched with a KDF, a PSK suite with ephemeral key exchange, or a password-authenticated key exchange; independent of that, remove the automatic dial paths of §5.2/§5.9.
- **Severity:** High

### 6.2 Unauthenticated Bonjour advertisements can exhaust the master's connection slots
- **Location:** `Modules/GameRPG/Master/MasterNetworkController.swift:242-246` (inbound cap on `connections.count`), `:355-363` (`addNew`), `:368-377` (`connectToPlayer`), `:265,270-280` (deadline only on inbound)
- **What:** Outbound redials are appended to the same `connections` array the 32-connection cap counts, are not throttled or capped, and have no handshake deadline. An attacker registers 32+ `_gamemasterplayer._tcp` services that accept TCP and stall (or point at a blackhole); the master dials each and keeps the slots occupied.
- **Why:** Every legitimate join is then rejected with "connection limit reached" until the services vanish or the GM restarts streaming, with no message to the GM or the joiner. Advertising a Bonjour service needs no credentials. Not reproduced on hardware.
- **Action:** Cap outbound dials separately from inbound, apply the handshake deadline and throttle to outbound connects, and only dial session-scoped endpoints (§5.2).
- **Severity:** High

### 6.3 The connection-attempt throttle protects less than its documentation claims
- **Location:** `Modules/GameRPG/Network/ConnectionAttemptThrottle.swift:35,45-64,89-92`; `Network/ConnectionThrottleTracker.swift:30-38`; `Player/PlayerNetworkController.swift:35-42`
- **What:** It keys on the host string (IPv6 rotation and interface scopes create new keys); 257 sources evict the oldest, including a locked one; the failure count never decays; it does not cover outbound dials; and on the player it guards a listener that lives for exactly one connection (§5.1). Partly reported in Audit 16 §6.5.
- **Why:** It slows a single-address online guesser only. It should not be relied on as a substitute for a stronger secret.
- **Action:** Document its limits next to §6.1's decision, decay failure counts over time, and key on something less trivially rotated where the platform allows.
- **Severity:** Medium

### 6.4 Join secrets outlive their use in memory
- **Location:** `Modules/GameRPG/Player/PlayerNetworkModel.swift:47`; `Player/PlayerNetworkController.swift:168-194`; `Browser/BrowserRowView.swift:14-15,99-101`
- **What:** `PlayerNetworkModel.passcode` is never cleared by `stop()`; `enteredCode` remains in `@State` after a successful join.
- **Why:** Marginal on its own; it matters if the code later becomes a stronger secret. Confirmed positively: no `Logger` call in `Modules/GameRPG` logs a passcode.
- **Action:** Clear on stop and after a successful join.
- **Severity:** Low

### 6.5 Adventure title and character name are advertised in clear before any authentication
- **Location:** `Modules/GameRPG/Network/ListenerManager.swift:152-154`; `Root/GameRoot.swift:306-311`; `Player/PlayerNetworkController.swift:229`
- **What:** The Bonjour instance name (adventure title on the GM, character/device name on a fallback listener) plus a supporter-tier TXT record are visible to everyone on the LAN.
- **Why:** By design for discovery, but titles can be private or spoiler-bearing and device names are often real names (Audit 16 §6.7 covered the logging side only).
- **Action:** Mention it in the Local Network usage text or let the GM opt for a generic advertised name.
- **Severity:** Low

---

## 7. Performance

### 7.1 TCP keepalive after 2 s idle
- **Location:** `Modules/GameRPG/Network/NWParameter+GameMaster.swift:29-32`
- **What:** `keepaliveIdle = 2` with interval/count left at defaults (already noted as a detection-latency issue in `CODE_AUDIT_Network.md` §5.6).
- **Why:** A probe is triggered by every 2 s of receive idleness per connection, which keeps the radio active on idle sessions and costs battery on player devices. Not measured; the value comes from Apple's sample code.
- **Action:** Use a longer idle (tens of seconds) and set interval and count explicitly; rely on the application-level loss detection.
- **Severity:** Low

### 7.2 The player's Bonjour browser is started on appear and never stopped
- **Location:** `Modules/GameRPG/SetupViews/BrowserView.swift:41-44`; `SetupViews/SearchProxyView.swift:60-64`; `Player/PlayerNetworkController.swift:168-194`
- **What:** `start()` is called from `onAppear`; no `onDisappear` and no `stop()` of `browserManager`. It keeps browsing after the user leaves the setup screen and after a game ends.
- **Why:** Continuous mDNS browsing for the app's lifetime. Removal events are still needed while in a game (`checkForRemoval`), so the fix is to stop it when no game or setup screen needs it.
- **Action:** Tie browser lifetime to the setup screen and the active session.
- **Severity:** Low

### 7.3 Synchronous Keychain I/O on the main actor at `GameRoot` creation; previews and tests hit the real Keychain
- **Location:** `Modules/GameRPG/Root/GameRoot.swift:38`; `Network/GameJoinCodeModel.swift:29-35,111-127`
- **What:** `let gameJoinCodeModel = GameJoinCodeModel()` runs up to six `SecItem*` calls (three reads, up to three adds) at construction. The injectable `JoinCodeStorage` seam exists but `GameRoot` offers no way to supply it.
- **Why:** Main-thread IPC at launch; every preview and test that builds a `GameRoot` reads and may write the app's real service items.
- **Action:** Inject the model (or storage) into `GameRoot.init` with an in-memory default for previews and tests.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 No "connecting" state; the button reads "Disconnect from:" while the handshake is pending
- **Location:** `Modules/GameRPG/Browser/BrowserRowView.swift:24-33,112-120,145-147`; `Player/PlayerNetworkController.swift:77,116-121`
- **What:** `isConnected` is `playerConnectionId == model.id`, set *before* the handshake. For up to the 12 s join timeout the row says "Disconnect from: X" with no progress indicator, and a second tap cancels the attempt.
- **Why:** Users cannot tell connecting from connected, and a natural retap aborts the join and then triggers the re-prompt in §8.2.
- **Action:** Add an explicit connecting state (progress and disabled/"Cancel" label) driven by the join attempt, distinct from connected.
- **Severity:** Medium

### 8.2 Failures collapse into "re-enter the code"; browse failures are invisible
- **Location:** `Modules/GameRPG/Browser/BrowserRowView.swift:91-102`; `Browser/BrowserManager.swift:15-22,31,108-116`; `SetupViews/BrowserView.swift:28-33`
- **What:** Any unsuccessful join — bad code, throttle lockout (master cancels before TLS), 12 s timeout, unreachable host — reopens the code sheet with no message. `BrowserManager.errorMessage` is never set, `NetworkState.tlsFailed` never assigned, and `BrowserView` shows only "No hosted games found"; on `.browserStopped` the stale `games` list is kept.
- **Why:** A user who denied Local Network access sees an empty list forever with no hint; a locked-out or unreachable join looks like a typo.
- **Action:** Return a typed join outcome (`badCode`, `locked`, `unreachable`, `timedOut`) from the network layer, show it in the sheet, and show browser stopped/denied state with a Settings link; clear `games` when the browser stops.
- **Severity:** Medium

### 8.3 The "reconnecting" indicator is wired at one of four call sites *(partially fixed — Audit Reconnect §8.1)*
- **Location:** wired: `Modules/GameRPG/GameViews/IOSGameOverlayControlField.swift:18-29`; not wired: `GameViews/GameToolbarContent.swift:59-68`, `GameViews/OverlayGameMenu.swift:426-441`, `GameViews/IOSGameConnectionStatusView.swift:14-22`; init at `GameChromeStatusPresentation.swift:26-41`
- **What:** `isReconnecting` defaults to `false`, so the other three build the presentation without it and render `.localNetworkLost` during a real reconnect.
- **Why:** On macOS, visionOS and the overlay menu players see "Connection Lost" while recovery is in progress — exactly what the earlier fix set out to prevent.
- **Action:** Derive the reconnecting flag once (in `GameRoot` or the presentation) and remove the defaulted parameter so call sites cannot omit it.
- **Severity:** Medium

### 8.4 VoiceOver reads join codes as numbers
- **Location:** `Modules/GameRPG/GameViews/GameJoinCodeRevealButton.swift:69-72`; `SetupViews/GameJoinCodeSetupButton.swift:32-33,44`; `SetupViews/GameJoinCodeOTPField.swift:32`; `GameViews/GameRootViewer.swift:275-279`
- **What:** Codes are plain `Text`/`accessibilityValue(Text(code))`; a four-digit string is spoken as a quantity ("four thousand …").
- **Why:** The code exists to be read aloud and transcribed; digit-by-digit speech is the safe reading.
- **Action:** Apply spell-out speech (`speechSpellsOutCharacters()`) to code text and values.
- **Severity:** Medium

### 8.5 Fixed-size digit boxes and hard-coded metrics
- **Location:** `Modules/GameRPG/SetupViews/GameJoinCodeOTPField.swift:43-47,73`; `Browser/BrowserRowView.swift:167,195-196`; `SetupViews/GameJoinCodeSetupButton.swift:35-36,89`; `GameViews/GameJoinCodeRevealButton.swift:66,79`
- **What:** 40×48 box frames around a `.title2` digit, and hard-coded spacing/padding/min-widths (`spacing: 8/16/20`, `minWidth: 220/320`, `minHeight: 260`).
- **Why:** At accessibility Dynamic Type sizes the digit outgrows its box; the project guidance is to avoid hard-coded padding and spacing.
- **Action:** Size boxes from the type size (`ScaledMetric`/minimum sizes) and drop the fixed metrics where layout allows.
- **Severity:** Low

### 8.6 OTP input traits
- **Location:** `Modules/GameRPG/SetupViews/GameJoinCodeOTPField.swift:24-41`
- **What:** The hidden field sets `numberPad` on iOS/tvOS but no `.textContentType(.oneTimeCode)` and no `.autocorrectionDisabled()`. Tap-to-focus depends on the near-transparent field underneath (`opacity(0.02)`), and its focus ring is hidden. tvOS/macOS behaviour was not exercised.
- **Why:** Missed paste/autofill affordance; possible focus quirks.
- **Action:** Add the content type and test on tvOS and macOS.
- **Severity:** Low

### 8.7 `BrowserView` is not scrollable
- **Location:** `Modules/GameRPG/SetupViews/BrowserView.swift:22-40` (contrast `SearchProxyView.swift:16`)
- **What:** Rows sit in a plain `VStack` with no `ScrollView`.
- **Why:** Many hosts, or larger Dynamic Type, overflow with no way to reach the rest.
- **Action:** Wrap in a `ScrollView`.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Dead browser state
- **Location:** `Modules/GameRPG/Browser/BrowserManager.swift:15-22,31`
- **What:** `errorMessage` is never assigned; `NetworkState.tlsFailed` and `.connected` are never produced (repository search found no assignments); `BrowserManager` is only exercised through mocks.
- **Why:** Suggests unfinished error reporting (§8.2).
- **Action:** Wire them as part of §8.2 or delete them.
- **Severity:** Low

### 9.2 Duplicated init and migration code in `GameJoinCodeModel`
- **Location:** `Modules/GameRPG/Network/GameJoinCodeModel.swift:29-43,111-146`
- **What:** `init()` and `init(defaults:codeStorage:)` repeat the same three loads; `loadOrGenerate` and `loadLastUsedMasterJoinCode` repeat the read-validate-migrate sequence.
- **Why:** A fix for §5.5 must be applied in several places.
- **Action:** Make `init()` delegate to the injectable init and extract one "read/validate/migrate" helper.
- **Severity:** Low

### 9.3 Test coverage gaps
- **Location:** `Tests/GameRPGTests/` (a repository search of `Tests` and `Snapshots` for `JoinCode` returns nothing); `PlayerNetworkControllerTests.swift:13,45`
- **What:** No tests for `GameJoinCodeModel` (generation, validation, migration, the write buffer, `reset`), `KeychainJoinCodeStorage` or its fake, or ASCII-digit validation. `PlayerNetworkController`'s listener path (`listenerNewConnection`, `restart`, fallback stop) has no test; `BrowserManager` is only mocked.
- **Why:** §5.1, §5.5, §5.7 and §5.8 each sit in untested code.
- **Action:** Add tests with an in-memory `JoinCodeStorage` first (cheap), then listener-path tests using the existing `GameListenerMocks`.
- **Severity:** Medium

### 9.4 Service-type naming is inverted and duplicated in three places
- **Location:** `Modules/GameRPG/Browser/GameServiceType.swift:10-51`; `Resources/Info.plist:61-66`; `Resources/InfoTV.plist:48-53`
- **What:** Cases are named from the advertiser's perspective (`.player` is what the master publishes), documented in a comment; the four strings are also hard-coded in two plists with nothing enforcing agreement (Audit 16 §9 noted the general pattern).
- **Why:** Easy to invert at a call site; a typo breaks discovery without a compile error.
- **Action:** Rename to role-explicit cases and add a unit test that reads the plists.
- **Severity:** Low

### 9.5 Two copies of the "observe browser, re-arm, diff" pattern
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift:350-399`; `Master/MasterNetworkController.swift:290-333`
- **What:** Each re-implements `withObservationTracking` re-arming on `BrowserManager` output (`removed` vs `games`).
- **Why:** The re-arm ordering bug fixed in Audit Reconnect §3.5 is exactly what duplication invites; §5.4 needs a shared, event-driven source of endpoint changes.
- **Action:** Publish endpoint added/removed as an `AsyncStream` from `BrowserManager` and consume it in both controllers.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Give every reconnect endpoint an identity.** Scope fallback advertisements to a session so masters dial only their own players (fixes §5.2, most of §6.2, and removes the active harvest path in §6.1).
2. **Make the fallback listener outlive a bad connection.** A listener should be retired only by an authenticated success or an explicit stop (§5.1).
3. **One supervised network-lifecycle owner** for listener, browser and dials, with backoff, scene-activation and path-change triggers, and UI-visible state (§5.3, §5.4, §8.2).
4. **Typed outcomes from `ConnectionController` up to the UI** (`badCode`, `locked`, `unreachable`, `timedOut`) instead of `Bool` (§8.1, §8.2, §5.9).
5. **Decide the join-secret question once** — code length/format, KDF, PSK suite — and land it together with the automatic-dial removals (§6.1, §6.3, §5.7).
6. **Keychain result taxonomy plus dependency injection** through `GameRoot` so the storage is testable and failures are visible (§5.5, §5.6, §7.3, §9.3).

---

## 11. What was NOT audited

- **SharePlay path** (`Modules/GameRPG/SharePlay/`), which has its own join model; covered by `CODE_AUDIT_Network.md` and `CODE_AUDIT_Reconnect.md`.
- **`GameProtocol` framing, `GameMessagePipeline` and `MasterController`/`PlayerController` state handling** beyond the control entry points.
- **On-device behaviour:** no packet capture, no two-host test, no Local Network permission flow, no keychain behaviour while locked or on macOS, no Instruments/battery measurement. The PSK finding is by protocol reasoning plus a timing of the HMAC step; the Bonjour findings are by static tracing.
- **tvOS focus and remote-control behaviour** of the code-entry field, and visionOS.
- **A completed clean build:** the link step failed on the stale-`EagerLinkingTBDs` issue; Swift compile output was clean.
- **Localization wording** and the Tips (`MasterRPGTips*`) that mention join codes.
- Items in earlier audits already marked fixed were spot-checked, not re-derived.

---

## 12. Verification

No Critical findings were assigned. Evidence for each High:

- **§5.1** — open `Modules/GameRPG/Player/PlayerNetworkController.swift`, lines `418` (`networkModel.reset(listener: nil)` before any handshake), `420-424` (state set to `.notReady`, connection restarted), then `245-268` (`.notReady` failure → `resolvePendingConnection(false)` and `stop(connection:)`) and `168-194` (`stop()` tears everything down). Then confirm the only caller of `startPlayerServer()` is line `298` in `lostConnection`, reachable only via `markLostIfCurrent` (`327-333`, requires `playerConnectionId != nil`, which `stop()` has just cleared). `PlayerNetworkControllerTests.swift` contains two tests, lines `13` and `45`.
- **§5.2** — open `Modules/GameRPG/Master/MasterNetworkController.swift`, lines `87-88` (browser for `.master` started on every `startStreaming`), `316-333` (`refresh` dials every endpoint not in `browserConnections`, no filter), `368-377` (`connectToPlayer` uses `networkModel.passcode`). Then `Browser/GameServiceType.swift:23-26` confirming `.master` = the players' fallback service.
- **§5.3** — open `Modules/GameRPG/Network/ListenerManager.swift`, lines `112-115` (`.failed` → `delegate.listenerCancelled()`), `Master/MasterNetworkController.swift`, lines `234-236` and `122-148` (`resetConnections` cancels all connections, stops the browser, no restart), `Browser/BrowserManager.swift`, lines `114-116`. Run `grep -rn "scenePhase\|NWPathMonitor" Modules/GameRPG` — no hits.
- **§6.1** — open `Modules/GameRPG/Network/NWParameter+GameMaster.swift`, lines `52-53` (HMAC keyed by the code over a constant), `67` (constant identity), `71` (`TLS_PSK_WITH_AES_128_GCM_SHA256`); `Network/GameJoinCodeModel.swift`, lines `94-97,154` (10^4 space). Active path (a): `Master/MasterNetworkController.swift:316-333,368-377`; path (b): `Browser/BrowserRowView.swift:27-29,77-80`. The scratch measurement (10^4 HMAC derivations = 34 ms) was run in the session scratchpad.
- **§6.2** — open `Modules/GameRPG/Master/MasterNetworkController.swift`, lines `242-246` (cap uses `networkModel.connections.count`), `355-357` (`addNew` appends to `connections` for outbound dials too), `368-377` (`connectToPlayer` has no count check), `265` and `270-280` (deadline armed only in `listenerNewConnection`).
- **Medium items spot-checked:** §5.7 by scratch script (four non-ASCII strings validated `true`; PSK bytes differ from the ASCII equivalent); §8.3 by `grep -rn "isReconnecting" Modules` (one call site passes it); §9.3 by `grep -rn "JoinCode" Tests Snapshots` (no hits).

---

## 13. Remediation status (2026-09-21)

**Verification.** A clean `GameRPGTests` build-for-testing (iOS Simulator, iPhone 17 Pro), plus `MasterMac` (macOS) and `MasterTV` (Apple TV simulator) builds, succeeded with **zero Swift warnings or errors**. 49 targeted tests pass (the new suites plus the existing `MasterNetworkController`, `PlayerNetworkController` and `ConnectionAttemptThrottle` suites). The full `GameRPGTests` run has 590 passing cases and 117 failures, **all in the `*SnapshotTests` suites** (the same count `CODE_AUDIT_Reconnect.md` recorded as pre-existing, environment-dependent image comparisons; not individually re-verified against a pre-change run). visionOS was not built (no simulator installed). Nothing was exercised on device: no two-host, locked-keychain, macOS-keychain or Local Network permission runs.

**Fixed:**
- **§3.1** — `restart(connection:)` cancels the replaced controller.
- **§3.2** — `BrowserManager` drops events from superseded runs (generation-guarded monitor inside a supervising task).
- **§3.3 (partly)** — `flushPendingWrites()` makes a just-changed code durable before hosting/joining; failed writes are logged and re-queued. Not changed: the blocking Keychain IPC still runs on a detached task.
- **§4.2 (Keychain only)** — `Data(value.utf8)`. The PSK identity encoding was deliberately left alone: it is sent on the wire and changing it would break compatibility.
- **§5.1** — the fallback listener stays up until a connection authenticates; a failed attempt returns the player to waiting (listener kept or recreated); one attempt at a time; 15 s handshake deadline on reconnect attempts.
- **§5.2** — every listener advertises a per-hosting-run `session` TXT value; a master only dials reconnect services carrying its own session; players advertise the session they joined. *Caveat: a player on an older app version advertises no session and will not be redialed by a new master.*
- **§5.3** — a failed master listener no longer ends hosting: connections are kept and the listener is recreated with backoff (status `.restarting`, then `.failed` after repeated failures) and shown on the master's status icon. A failed player fallback listener is recreated. `BrowserManager` restarts itself with backoff. Both re-check when the app becomes active (`GameRootViewer` → `GameRoot.applicationBecameActive()`).
- **§5.4** — failed redials retry with 2/4/8/16/30 s pauses, at most 5 attempts per endpoint; a 15 s connect deadline covers outbound dials.
- **§5.5** — reads return `found` / `notFound` / `unavailable`; an unreadable keychain never generates or overwrites a code, and `refreshFromStorage()` resolves it later (run before hosting/joining and on activation).
- **§5.6** — macOS uses the data-protection keychain, reads legacy items as a fallback, migrates after a verified write, and falls back to the legacy keychain if the data-protection one is unavailable to the build. *Not verified on a Mac in a shipping signature.*
- **§5.7** — codes are ASCII digits only; typed/pasted input is normalised to ASCII.
- **§5.8** — the reveal button and empty-state screen show the running listener's code while hosting.
- **§5.9** — the remembered code is stored with the host that accepted it and only auto-tried for that host. A previously saved code (no host) is not replayed once; the user re-enters it.
- **§5.10** — advertised names are trimmed and cut to 63 UTF-8 bytes; the display name is no longer truncated at the first dot.
- **§5.11** — the accepted code is saved in `connect` once the game has started.
- **§6.2** — outbound dials have their own cap (8) and do not use the 32 inbound slots. *An attacker who copies the public session id can still occupy the 8 outbound slots, but can no longer block joins.*
- **§6.3 (partly)** — failure counts decay after 10 minutes, locked sources are evicted last, IPv6 sources are keyed by /64. Still bypassable by an attacker with many IPv4 addresses.
- **§6.4** — the passcode and session are cleared in `stop()`; the entered code is cleared after a join.
- **§7.1** — keepalive: 15 s idle, 5 s interval, 3 probes.
- **§7.2** — the player's browser stops when the setup screen disappears, unless a join or session is active.
- **§7.3** — `GameRoot` takes the join-code model as a parameter; an `InMemoryJoinCodeStorage` exists for previews and tests. (`GameRoot` still defaults to the real Keychain, and its previews were not switched over.)
- **§8.1** — a "Connecting to …" state with a progress indicator; tapping it cancels.
- **§8.2** — the join failure reason (`badCode` / `unreachable` / `timedOut`) is recorded and shown in the code sheet; the browser exposes its error and a "Local Network access denied" flag, shown in `BrowserView` / `SearchProxyView`.
- **§8.3** — `isReconnecting` is passed at all four sites.
- **§8.4** — join codes are read digit by digit.
- **§8.5 (partly)** — digit boxes scale with Dynamic Type. Other fixed paddings/min-widths were left.
- **§8.6** — `oneTimeCode` content type and autocorrection off on the code field.
- **§9.1** — removed the unused `NetworkState.tlsFailed`/`.connected`; `errorMessage` is now used.
- **§9.2** — `init()` delegates to the injectable initialiser; storage handling shares helpers.
- **§9.3** — new `GameJoinCodeModelTests`, `PlayerFallbackListenerTests`, `NetworkDiscoveryNamingTests`, plus master (listener restart, session scoping, outbound cap) and throttle (decay, eviction, IPv6 key) tests.
- **§9.4 (partly)** — a test now checks that every service type is declared in both Info.plists. The inverted case naming was not changed.

**Not done:**
- **§4.1** — migrating listener/connection to the structured Network APIs: needs a check that custom TLS-PSK and the `GameProtocol` framer exist there; a larger change.
- **§4.3** — the `.stroke` shapes were left as instances.
- **§6.1** — the join secret itself (code length/format, KDF, PSK suite, or PAKE) is still a product decision. What changed: the master no longer dials other sessions' services, and a saved code is only sent to the host that accepted it. An attacker can still copy a public session id or host name, so **offline recovery of the 4-digit code remains open**.
- **§6.5** — advertised names are by design.
- **§8.7** — `BrowserView` is still not scrollable (layout risk in its parents; not tested).
- **§9.5** — the duplicated browser-observation pattern.

**Follow-ups for you:**
- Six new UI strings are not yet in `Modules/GameRPG/Resources/Localizable.xcstrings` (English fallback until added/translated): "Connecting to: %@", "That code was not accepted. Check it and try again.", "Couldn't reach the host. Wait a few seconds and try again.", "The host did not respond in time. Make sure Local Network access is allowed, then try again.", "Local Network access is turned off for MasterRPG. Turn it on in Settings to find games.", "Searching for games was interrupted. Trying again…".
- The Settings alert still says anyone using old codes needs the new ones; a game already running keeps its old code until it ends (the displayed code now matches it).

### 13.1 Follow-up: joining failed even with the right code (2026-09-21)

**Symptom:** the code sheet reappears after about 12 s; the master logs `unknown PSK identity` (`-9864`).

**Cause (found with a loopback handshake test, not by reading):** the PSK identity was encoded with `String.data(using: .unicode)`, i.e. UTF-16 with a BOM. ASCII in UTF-16 is full of NUL bytes, and the TLS stack compares the received identity as a C string, so `"GameMaster"` was cut at its first NUL and never matched the configured identity. Even client and server in the same process, with the same code, failed. The bug pre-dates this remediation: it entered with the CODE_AUDIT_15 §6.2 fix (`5cf436d5`), which replaced the identity's accidental bytes with a well-defined but non-matching encoding. The earlier "fixed" verdict on §6.2 was wrong about the on-the-wire result; that fix had no handshake test.

**Fix:** `NWParameter+GameMaster.swift` encodes the identity as UTF-8. New `TLSPasscodeHandshakeTests` run real loopback handshakes: the same code connects, a different code fails with `-9820 bad MAC` (not on the identity).

**Second finding from the same run:** a rejected handshake surfaces as `.waiting(.tls)`, never `.failed`, so a wrong code never reached the delegate and only ended as a 12 s timeout (shown as "timed out" rather than "code not accepted"). `ConnectionController` now treats `.waiting(.tls)` as a terminal authentication failure; other waiting reasons stay transient. Covered by `wrongCodeIsReportedAsAuthenticationFailure` and `rightCodeBecomesReady`.

**Compatibility:** the identity bytes change on the wire, so an app version with the old identity cannot join a version with the new one. That already held between the pre-§6.2 build and the §6.2 build; all devices in a game need this build.
