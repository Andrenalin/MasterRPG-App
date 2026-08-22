# MasterRPG — GameControllers Area Code Audit

Generated 2026-08-22. Scope: the "GameControllers area" — 35 Swift files, ~12,700 LOC — `Modules/GameRPG/Controller/*` (MasterController, PlayerController + 11 extension files, LogGameController, PlayerControllerModel, ViewController, PreviewData), every per-module `GameController.swift` (Dice, Map + 4 extensions, Character, Space, Audio, Table, Pdf, Photo, Weather, Adventure, Rule, Generator), `CoreRPG/Controllable/GenericGameController.swift` + `Fake/FakeGameController.swift`, and `GameRPG/BattleRound/BattleRoundController.swift`. `Dead/` and any archived directories are excluded per repo convention; none were encountered in this scope.

A real (non-incremental) `xcodebuild` of the `GameRPGTests` scheme confirmed this scope compiles with **zero warnings**. That is a genuinely clean result — see §11 for what a clean compile does and doesn't tell you — and it means the concurrency findings below are all things the compiler's strict-concurrency mode does not catch, not warnings it already flagged.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made. Three parallel review passes fed this report (concurrency/API modernity, dead code/duplication, bugs/security/performance); overlapping findings from more than one pass are merged and noted.

---

## 1. Executive summary

1. **[Critical] `battleInitiative(from:)` traps on an out-of-range value — verified** — §5.1 — `Modules/GameRPG/BattleRound/BattleRoundController.swift:342-352`. A duplicated copy of a helper that exists correctly elsewhere dropped its `Int`-range guard; a large-but-finite initiative value (a fat-fingered number, or a huge computed Character value) crashes the app via `Int(value)`.
2. **[High/Security] Any admitted player can rewrite and persist another player's Character** — §6.1 — `Modules/GameRPG/Controller/MasterController.swift:2013-2077`. Ownership is checked only against the sender's self-declared `characterId`, which every peer already knows from map pin data.
3. **[High/Security] A peer's audio package is imported and re-broadcast with no baseline check** — §6.2 — `Modules/GameRPG/Controller/MasterController.swift:1296-1310`. Every sibling module (Photo/Pdf/Space) defends the master's canonical copy first; Audio does not.
4. **[High] The map content fingerprint is not health-invariant** — §5.2 — `Modules/MapRPG/Model/MapUpdatePayload.swift:82-95`. Every HP change silently changes `mapContentVersion`, which causes players' own pin moves to be rejected by the master mid-combat and forces a full map re-sync per hit-point change.
5. **[High] Grouped/nested Character values never sync from player to master** — §5.3 — `Modules/GameRPG/Controller/PlayerController.swift:172-188`. Value updates only resolve top-level entries; most tracked HP fields live inside a group, per the codebase's own doc comment.
6. **[High] Two battle-round mutations bypass the shared broadcast helper** — §5.4 — `Modules/GameRPG/BattleRound/BattleRoundController.swift:289-340`. The same bug class fixed for `nextAttacker()`/`nextRound()` (see project memory) recurs at two untouched call sites.
7. **[High] MasterController/PlayerController's network receive entry points silently lose `@MainActor` isolation** — §3.1 — multiple sites, root cause at `Modules/GameRPG/Network/GameNetworkControllerModel.swift:10-138`. Confirmed against the project's actual `SWIFT_APPROACHABLE_CONCURRENCY = YES` build setting.
8. **[High] Package export/import runs synchronously on the main actor** — §3.5 — `MasterController.swift:628-677, 1618-1648` and four `PlayerController+*.swift` sites. Multi-megabyte map/PDF transfers stall the UI; the `await`s look offloaded but aren't.
9. **[High] Ten of twelve per-module `GameController`s duplicate `GenericGameController`'s core, and the copies have already drifted** — §9.1 — `Modules/CoreRPG/Controllable/GenericGameController.swift:13-48` vs. ten module files.
10. **[High] `MasterController.swift` is 2,692 lines with three ~140-line near-identical handlers buried inside it** — §9.3 / §9.6 — `MasterController.swift:1706-2314`. The player-side equivalent already splits the same responsibilities across eleven files.

---

## 2. Quick wins (≤30 min each)

- **Add the missing `Int`-range guard to `battleInitiative(from:)`** — `Modules/GameRPG/BattleRound/BattleRoundController.swift:346-351`. Copy the two extra conditions (`value >= Double(Int.min), value <= Double(Int.max)`) already present in `Modules/MapRPG/Controller/GameController+Metadata.swift:280-284`. This is the immediate fix for §5.1; the full de-duplication is a separate, larger action.
- **Wrap `GamePreviewModuleRoots.init`'s `preconditionFailure` in `#if DEBUG`** — `Modules/GameRPG/Controller/PreviewData.swift:304-317`. It's the one unconditional trap in scope shipping in release builds.
- **Fix the misplaced `await`** — `Modules/MapRPG/Controller/GameController+Pins.swift:200`. Change `await result.append(...)` to `result.append(await ...)` so the suspension point is where it belongs.
- **Switch the two `applyHealthPercent` logs from `.public` to `.private`** — `Modules/MapRPG/Controller/GameController+Metadata.swift:267,273`. `GameController+Battle.swift:511-513` already documents this exact privacy policy for the same data; these two lines are the outlier.
- **Replace `String(data:encoding:)`/`.data(using:)` with the non-optional modern initializers** — `Modules/MapRPG/Controller/GameController+MapSync.swift:15,34`. `String(decoding:as:)` / `Data(_.utf8)` removes a spurious optional on a hot path.
- **Hoist the five function-local deferred-buffer caps to `private static let`** — `Modules/GameRPG/Controller/PlayerControllerModel.swift:251,309,367,431,489`. `MasterControllerModel`'s three equivalents already do this (`MasterController.swift:150,161,163`); match the convention.
- **Drop the redundant `: Sendable` from `@MainActor final class` declarations** — 11 sites listed in §3 note / §4.3. Global-actor isolation already implies `Sendable`; the explicit conformance obscures where it's actually load-bearing.
- **Replace `deferMapPin`'s ad-hoc `JSONDecoder()` with the shared `MapPinModel.decodeData(of:)` helper** — `Modules/GameRPG/Controller/PlayerControllerModel.swift:465`. See §9.19.

---

## 3. Concurrency

### 3.1 Delegate-witness entry points silently lose `@MainActor` isolation
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:842-910, 954-965, 967-980, 1229-1238, 2320-2343`; `Modules/GameRPG/Controller/PlayerController.swift:624-631, 643-651, 653-671, 673-779`; `Modules/GameRPG/Controller/PlayerController+ProxyDelegate.swift:9-27`; protocols at `Modules/GameRPG/Network/GameNetworkControllerModel.swift:10-18, 33-77, 124-138`
- **What:** `MasterNetworkStoreDelegate`, `PlayerNetworkStoreDelegate`, and the proxy-controller delegates are declared `Sendable & AnyObject` with `async` requirements but no `@MainActor`. `MasterController`/`PlayerController` are `@MainActor` classes conforming to them. **Verified:** the project's `MasterRPG.xcodeproj/project.pbxproj` sets `SWIFT_APPROACHABLE_CONCURRENCY = YES` on the GameRPG target (alongside `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_VERSION = 6.0`). Under that setting, `async` witnesses of a nonisolated protocol requirement become `nonisolated(nonsending)` and inherit the *caller's* executor rather than the conforming type's — for the LAN path that caller is the `ConnectionController` actor, not the main actor.
- **Why:** Every `await` inside these witness bodies is a genuine cross-actor suspension, so multi-step authentication/teardown logic that reads as one atomic `@MainActor` block is actually interleavable by other inbound connections. In-code comments asserting "this is already a same-actor synchronous read" do not hold for this family of methods.
- **Action:** Make the isolation explicit — annotate each witness `@MainActor`, or mark the protocol requirements themselves `@MainActor` — so the receive surface has one documented isolation domain instead of one inherited from whichever transport actor called in.
- **Severity:** High

### 3.2 `lostPlayer(for:)` tears down player state across nine independent actor hops
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:967-980`
- **What:** Because this method is one of the non-isolated witnesses in §3.1, each of the nine cleanup calls (`gameModel.remove`, six per-module `removePlayerReport`/`remove*Reports`, `root.gameModel.remove(playerId:)`, `resetPlayers()`) is an independent main-actor hop instead of one transaction.
- **Why:** A message on another connection can be processed between any two hops and observe a half-removed player — present in some modules' availability matrices, absent from others.
- **Action:** Collapse the removal into one `@MainActor` helper (mirroring `applyMasterBroadcastAndResetPlayers`/`resetForLostConnection`) called with a single `await`.
- **Severity:** Medium

### 3.3 `accepts(_:origin:)` splits sender authentication across four suspension points
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:843, 885, 895, 904`
- **What:** The master-id read, connection→sender binding, Journal-admission record, and Journal correlation check are four separate main-actor hops inside one security decision.
- **Why:** Two concurrent inbound connections can interleave between the identity binding and the Journal admission — a check-then-act window in the function whose job is authenticating an inbound envelope.
- **Action:** Move the whole decision into one `@MainActor` function on `MasterControllerModel` that returns a single verdict.
- **Severity:** Medium

### 3.4 PlayerController's SharePlay validators validate and mutate across suspension points
- **Location:** `Modules/GameRPG/Controller/PlayerController.swift:673-693, 695-712, 714-729, 757-779`
- **What:** `acceptsSharePlayPeerMessage`, `didAcceptSharePlayMasterState`, and `sharePlayFileLoadFailed` each split their read/mutate logic across 2-3 independent main-actor hops.
- **Why:** The transport commits an immutable participant→player binding based on these verdicts; a roster or master-state update landing between hops can make the committed binding disagree with the state that authorized it.
- **Action:** Fold each validator into one `@MainActor` helper returning the complete verdict, matching the existing `applyMasterBroadcastAndResetPlayers` pattern.
- **Severity:** Medium

### 3.5 Network package export/import runs synchronously on the main actor
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:628-643, 662-677, 1618-1648`; `Modules/GameRPG/Controller/PlayerController+Map.swift:98-117, 209-224`; `PlayerController+Photo.swift:91`; `PlayerController+Pdf.swift:100-104`; `PlayerController+Space.swift:114`; `Modules/TableRPG/Controller/GameController.swift:169-173`; `Modules/AudioRPG/Controller/GameController.swift:167-189`
- **What:** `createGameData`/`createMapGameData`/`updateGame`/`importNetwork` are `nonisolated async` protocol members, so per §3.1's mechanism they run on the caller's (main) actor. Every call site here is a `@MainActor` controller method, so stream assembly and per-item decode of multi-megabyte packages happen on the main thread — unlike the file-URL import path, which correctly uses `Task.detached`.
- **Why:** Revealing a map or receiving a package stalls the UI for the transfer's full serialization time; the `await`s create a false impression the work is already offloaded.
- **Action:** Give these entry points an explicit off-main execution domain (`@concurrent`, or route through a detached task as `importUrl` already does), keeping only the final model mutation on the main actor.
- **Severity:** High

### 3.6 `diceUpdateWidget` performs UserDefaults JSON I/O and a WidgetCenter reload on the main actor
- **Location:** `Modules/DiceRPG/Controller/GameController.swift:592-609`
- **What:** Declared `nonisolated ... async` and fired from a `Task { }` inside `@MainActor roll(die:for:)`; per §3.1's mechanism it inherits main-actor isolation and runs `DiceConfiguration.loadFromUserDefaults()`, `.save()`, and `WidgetCenter.shared.reloadTimelines` synchronously on the UI thread.
- **Why:** `nonisolated` reads as "off the main thread" here but isn't — every dice roll does synchronous defaults serialization on the UI thread, via an unstructured `Task` that `stopGame()` can neither retain nor cancel.
- **Action:** Mark the function `@concurrent` (or move its body into a detached task) and hold the task in a cancellable slot the way `sendCharacterTask`/`proxyFocusTask` are held.
- **Severity:** Medium

### 3.7 Dice roll network send is an untracked fire-and-forget `Task`
- **Location:** `Modules/DiceRPG/Controller/GameController.swift:319-343`
- **What:** `rollDice` wraps its broadcast in a bare, unstored `Task { }` (line 327), and for unsynced rolls wraps the whole roll in a second `Task { @MainActor in try? await Task.sleep(...); rollFunction() }` (line 338) where `try?` discards cancellation and rolls anyway.
- **Why:** Neither task can be stopped by `GameRoot.cancelOwnedTasks()` or participate in the app's serialized network-action ordering; two rapid rolls can broadcast out of order, and a roll issued during teardown still fires.
- **Action:** Make `rollDice` `async` so callers await the broadcast through the existing serialized network-action chain; replace `try? await Task.sleep` + unconditional continuation with a `do/catch` that returns on `CancellationError`.
- **Severity:** Medium

### 3.8 Message-pipeline cancellation policy disagrees between Master and Player, and both silently drop the backlog
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:1007-1012, 1061-1091`; `Modules/GameRPG/Controller/PlayerController.swift:1003-1044`
- **What:** `MasterController.processMessages` keeps looping after a `CancellationError`, so `Task.checkCancellation()` fails immediately for each remaining queued event and the whole backlog is dequeued and dropped in a tight loop. `PlayerController.processMessages` instead `return`s immediately (line 1034), leaving its backlog enqueued with nothing scheduled to drain it until unrelated traffic arrives.
- **Why:** In both cases, already-accepted game messages (map state, pins, battle rounds) vanish with no `.failed` response or log, and the two controllers disagree about what cancellation means.
- **Action:** Pick one policy for both — stop draining on cancellation and either retain the un-processed events for the next drain, or have `stop()` explicitly clear the pipeline — so cancellation never silently consumes accepted messages.
- **Severity:** Medium

### 3.9 `show(for:)`'s "already sent" guard doesn't cover the suspension it's meant to protect
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:628-643`
- **What:** `hasSentGameItem(...)` is read, `createGameData(...)` suspends for the full package export, and only afterward is `markSentGameItem(...)` written — while the receive path's `handlePhoto`/`handlePdf`/`handleSpace` can mark the same item sent during that same window.
- **Why:** Both paths can independently decide to publish the full payload for the same item/version, duplicating a multi-megabyte broadcast. The outcome is idempotent, so this is a bandwidth cost, not corruption.
- **Action:** Reserve the item/version in `sentGameItems` before awaiting the export, rolling the reservation back on failure.
- **Severity:** Low

### 3.10 `proxyFocusTask` survives a lost connection and can mutate state on a torn-down session
- **Location:** `Modules/GameRPG/Controller/PlayerControllerModel.swift:1020-1039` (`resetForLostConnection`); task defined at `Modules/GameRPG/Controller/PlayerController+ProxyDelegate.swift:61-94`
- **What:** `resetForLostConnection` cancels `sendCharacterTask` but not `proxyFocusTask`, even though `PlayerController.stop()` (`PlayerController.swift:78-83`) cancels both.
- **Why:** The task sleeps one second, then writes `root.gameModel.selectedCharacter = characterId`. After a proxy disconnect, the user's selected Character can be silently overwritten by the dead session's late completion.
- **Action:** Cancel and clear `proxyFocusTask`/`proxyFocusTaskId` in `resetForLostConnection` alongside `sendCharacterTask`.
- **Severity:** Low

### 3.11 `PlayerController.stop()` never tears down its own `proxyMasterController`
- **Location:** `Modules/GameRPG/Controller/PlayerController.swift:34-53` (creation), `:75-101` (`stop`)
- **What:** A non-GM `PlayerController` holds a strong `MasterController(root: root, asProxy: true)`, but `stop()` never calls `proxyMasterController?.stop()`.
- **Why:** That controller's `messagePipeline.cancelAll()` never runs and its session state is never reset — it holds `root` strongly until deallocation, keeping the whole `GameRoot` graph alive past teardown. (Delegate registrations are `weak`, so this is teardown asymmetry, not a permanent retain cycle.)
- **Action:** `await proxyMasterController?.stop()` in `PlayerController.stop()`, before `root.networkProxyStore.stopGame()`.
- **Severity:** Low

---

## 4. API modernity

### 4.1 Internal transport callbacks still use completion-style delegate protocols
- **Location:** `Modules/GameRPG/Controller/PlayerController+ProxyDelegate.swift:8-27`; `Modules/GameRPG/Network/GameNetworkControllerModel.swift:10-138`
- **What:** `PlayerNetworkProxyControllerDelegate` and the `Master`/`PlayerNetworkStoreDelegate` families are purely internal protocols (no UIKit/Network.framework shape requires this) mixing pure notifications (`ready`, `receivedProxy`) with synchronous-style verdicts (`accepts`, `isLocalSharePlayTarget`).
- **Why:** The notification half is a natural `AsyncStream` of events — which would also resolve §3.1 by giving the controller one well-defined isolation domain instead of one inherited per-call.
- **Action:** Keep the verdict callbacks as a small, explicitly `@MainActor` protocol; replace the notification half with an `AsyncStream<GameTransportEvent>` consumed from one task.
- **Severity:** Low

### 4.2 Audio playback API returns a discarded `Task`, silently swallowing failures
- **Location:** `Modules/AudioRPG/Controller/GameController.swift:10, 22, 224-236, 307-310`; `Modules/GameRPG/Controller/MasterController.swift:1405`; `Modules/GameRPG/Controller/PlayerController+Audio.swift:56`
- **What:** `AudioGameStoreable.play(id:shouldPlay:)`/`play(with:)` return `Task<Void, Error>` — a pre-async/await API shape — and both call sites write `let _ = await ….play(with: data).result`, discarding the `Result` including any thrown error.
- **Why:** A failed playlist load or playback start is silently swallowed on both master and player: no log, no retry, no `.failed` response.
- **Action:** Change the protocol to `func play(...) async throws` and have both call sites handle or log the thrown error.
- **Severity:** Medium

### 4.3 Redundant and inconsistent `Sendable` conformance declarations
- **Location:** Redundant on `@MainActor final class`: `MasterController.swift:18,454`; `PlayerController.swift:23`; `PlayerControllerModel.swift:15`; `DiceRPG/Controller/GameController.swift:11`; `MapRPG/Controller/GameController.swift:12`; `CharacterRPG/Controller/GameController.swift:11`; `SpaceRPG/Controller/GameController.swift:7`; `PdfRPG/Controller/GameController.swift:7`; `PhotoRPG/Controller/GameController.swift:7`; `WeatherRPG/Controller/GameController.swift:9`; `TableRPG/Controller/GameController.swift:17`. Missing on the module-specific protocols: `MapRPG/Controller/GameController.swift:77`, `DiceRPG/Controller/GameController.swift:28`, `AudioRPG/Controller/GameController.swift:9`, `PhotoRPG/Controller/GameController.swift:45`, `TableRPG/Controller/GameController.swift:7`, `CharacterRPG/Controller/GameController.swift:38`, `AdventureRPG/Controller/GameController.swift:17` (present on `SpaceRPG/Controller/GameController.swift:158`, `PdfRPG/Controller/GameController.swift:45`, `WeatherRPG/Controller/GameController.swift:22`)
- **What:** `@MainActor` classes redundantly declare `: Sendable` (global-actor isolation already implies it), while 7 of the 10 module-specific game protocols omit `: Sendable` that their siblings declare.
- **Why:** The redundant declarations obscure where Sendability reasoning is actually load-bearing; the missing ones are a trap for any future `any MapGameStorable`-only property, which would become a non-`Sendable` existential.
- **Action:** Drop `: Sendable` from the `@MainActor` classes; add it to the seven protocols missing it, for a uniform family.
- **Severity:** Low

### 4.4 Legacy optional-returning `String`/`Data` bridging on a hot path
- **Location:** `Modules/MapRPG/Controller/GameController+MapSync.swift:15, 34`
- **What:** `String(data: mapData, encoding: .utf8)` and `.data(using: .utf8)` are used for the map-state wire text, both returning optionals that require guarding.
- **Why:** `String(decoding:as: UTF8.self)` and `Data(_.utf8)` are non-failing and remove a spurious optional path from a per-update code path.
- **Action:** Switch both sites to the non-optional initializers.
- **Severity:** Low

### 4.5 `PresentationIntent` is the only nested payload struct in its file not `Sendable`
- **Location:** `Modules/GameRPG/Controller/PlayerControllerModel.swift:52-59`
- **What:** Its ten sibling nested types in the same file (lines 16-76) are all declared `Sendable`; `PresentationIntent` is a bare `private struct`.
- **Why:** Currently inert (all stored properties are `Sendable` scalars), but the inconsistency reads as a deliberate non-transferability that isn't intended.
- **Action:** Add `Sendable` for consistency.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 `battleInitiative(from:)` traps on a large-but-finite value — verified
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundController.swift:342-352` (buggy copy), reached from `assignValueEntry` at `:290-335`; correct original at `Modules/MapRPG/Controller/GameController+Metadata.swift:276-286`
- **What:** **Personally verified by reading both files.** The MapRPG original guards `value.isFinite, value >= Double(Int.min), value <= Double(Int.max)` before `Int(value)`. The GameRPG copy (created because the MapRPG version is `internal` to MapRPG and not exposed on `MapGameStorable`) guards only `value.isFinite`, then calls `max(1, Int(value))` unguarded.
- **Why:** `Int(_: Double)` traps at runtime for a finite value outside `Int`'s range. `assignValueEntry` reaches this with a string from `gameEntryDisplayValue` — the display value of *any* Character entry the GM drags onto a combatant's initiative slot. An ordinary typo (a very large number) or a formula-driven value crashes the app instantly; this needs no adversarial input.
- **Action:** Immediate fix: copy the missing range guard (see §2 Quick wins). Structural fix: promote the MapRPG implementation onto `MapGameStorable` (or a shared CoreRPG numeric-parsing helper) and delete the GameRPG copy — this is also the duplication root cause tracked in §9.
- **Severity:** Critical

### 5.2 Map content fingerprint is not invariant under health changes — verified
- **Location:** `Modules/MapRPG/Model/MapUpdatePayload.swift:82-95` (`CanonicalMapContent.init`); consumers at `Modules/MapRPG/Controller/GameController+Metadata.swift:36-61` and `Modules/GameRPG/Controller/PlayerController+Map.swift:264-292`
- **What:** **Personally verified.** `CanonicalMapContent.init` neutralizes `location`, `isShown`, `size`, `timeInterval`, `isZoom`, `isDead`, and `isHighlighted` before hashing each pin — but not `healthPercent`. `mapContentVersion` therefore changes on every `synchronizeBattleDefenders` health write.
- **Why:** Two concrete regressions: (1) `isCurrentGeneration` compares the master's live (health-inclusive) generation against a player's last-stamped *authoritative* generation, so a player's own pin move is rejected by the master in the window after any HP edit; (2) `.mapState`'s `hasMapContentVersion` gate treats each HP change as a structural update, forcing a full `requestMapContent` round trip and complete snapshot resend per hit-point change during combat.
- **Action:** Add `canonicalPin.healthPercent = nil` to the neutralization block, next to the other runtime-only fields. Add a regression test asserting `mapContentVersion(for:)` is invariant under a health-only pin mutation.
- **Severity:** High

### 5.3 Grouped/nested Character value updates from a player are silently dropped
- **Location:** `Modules/GameRPG/Controller/PlayerController.swift:172-188`; `Modules/CharacterRPG/Controller/GameController.swift:410-413`
- **What:** The sender guard requires `message.id == playerCharacterId`, and `applyGameValueEntryUpdate` resolves the target entry with a top-level-only `character.entries.firstIndex(where:)`. Neither the producer (`EditController.gameValueEntryUpdate`) nor the applier descends through `groupId`/`valueId` nesting the way `gameEntry(characterId:entryId:)` in the same file explicitly does.
- **Why:** The file's own doc comment states HP and other tracked values are "frequently grouped, not top-level." For those Characters, a player's live HP edit never reaches the master — no error, no retry, no log — while `healthPercent(for:)` *does* read through the group, so the GM's health rings and the broadcast `pin.healthPercent` stay permanently stale. Same shape as the player-character-sync gaps fixed 2026-08-21, at an untouched site.
- **Action:** Resolve the entry through `gameEntryPath`/`gameEntry(characterId:entryId:)`; send the root Character id plus a path (or group id + root id) in `GameValueEntryUpdate`; mirror the descent in `applyGameValueEntryUpdate`. Log and return failure instead of `nil` when an update can't be applied.
- **Severity:** High

### 5.4 Two battle-round mutations change health inputs without broadcasting
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundController.swift:289-335` (`assignValueEntry`), `:337-340` (`refreshConfiguredValues`); shared broadcaster at `:363-378`
- **What:** `assignValueEntry(kind: .hitPoints)` sets `hitPointsEntryId` — the sole input to `healthPercent(for:)` — without broadcasting. `refreshConfiguredValues()` runs `resolveBattleConfiguredValues(remap: true)`, which writes `pin.healthPercent` via `applyHealthPercent`, also without broadcasting. Both also guard on `model.mapId` rather than the `authorizedMapId` every other mutator uses.
- **Why:** The exact bug class fixed for `nextAttacker()`/`nextRound()`: the GM drags a value onto a combatant's HP slot (or taps refresh), the master's own view updates from the live lookup, but players and the 2D map keep the stale ring until unrelated traffic happens to broadcast. The `model.mapId` vs. `authorizedMapId` divergence means the master-only invariant is enforced by accident (an empty player-side `combatants` array), not by the guard that documents it.
- **Action:** Route both through `broadcast(mapId:)` after a successful mutation; switch both to `guard let mapId = authorizedMapId`.
- **Severity:** High

### 5.5 `Dictionary(uniqueKeysWithValues:)` traps on network-derived collections — verified one site
- **Location:** `Modules/GameRPG/Controller/LogGameController.swift:35, 165, 236`; `Modules/MapRPG/Model/MapSnapshot.swift:87`; `Modules/MapRPG/BattleRound/BattleRoundModel.swift:326`
- **What:** **Personally verified** `LogGameController.swift:236` (`recipientSnapshot`): `Dictionary(uniqueKeysWithValues: controls.map { ($0.id, $0.show) })`, where `controls` is `gameModel.gameControl.controls`, assigned verbatim from the master's broadcast `GameMasterStateModel` with no duplicate-id check. The other four sites follow the same shape over `state.players`/`mapPins` from decoded network payloads.
- **Why:** This is a hard runtime trap on any duplicate key. `recipientSnapshot` runs inside `MasterController.send` on *every* outgoing message; on a proxy-hosting player device, `controls` came straight off the wire from the real master, so a malformed or hostile master crashes every relaying player. The other four trap once a prior import has written duplicate pin/player ids.
- **Action:** Replace all five with `Dictionary(_:uniquingKeysWith:)` (last-wins), or de-duplicate by id at the ingress points (`applyMasterBroadcast`, `MapSnapshot.apply`, `updateMap(for:with:)`).
- **Severity:** Medium

### 5.6 `BattleRoundModel.networkSequence` is never reset on reconnect
- **Location:** `Modules/MapRPG/BattleRound/BattleRoundModel.swift:431-441, 526-538`; `Modules/GameRPG/Controller/PlayerControllerModel.swift:1020-1039`
- **What:** `applyRemoteState` rejects any state with `sequence <= networkSequence`, which is only zeroed by `reset()` at full `stopGame()`. `resetForLostConnection` clears every other per-domain sequence counter but not this one.
- **Why:** If the GM stops and restarts the game while a player's app stays running and rejoins, the master restarts at sequence 1 while the player still holds a higher value — every subsequent `.battleRound` update is silently rejected, freezing that player's turn/round UI on stale state with no recovery path.
- **Action:** Reset the local `battleRoundModel` (or at least `networkSequence`) inside `resetForLostConnection`, or accept a state whose `mapId` differs from the current one regardless of sequence.
- **Severity:** Medium

### 5.7 `gameEntryPath` walks the `groupId` chain with no depth limit
- **Location:** `Modules/CharacterRPG/Controller/GameController.swift:323-344`
- **What:** `while let ownerId = currentItem.groupId { … }` has no visited-set and no `RecursionLimits.maxValueLinkDepth` bound, unlike its neighboring traversals in the same file (lines 260, 308).
- **Why:** `groupId`/`valueId` are plain fields of a peer-supplied Character package (reachable via `updatePlayer(data:)` → `importNetwork`). A crafted cyclic pair loops forever on the main actor, hanging the GM's app the moment they interact with that Character in a battle context.
- **Action:** Add the same `RecursionLimits.maxValueLinkDepth` bound (or a visited `Set<UUID>`) used elsewhere in the file; return `nil` when exceeded.
- **Severity:** Medium

### 5.8 `BattleRoundController` holds `GameRoot` strongly, unlike its sibling controllers
- **Location:** `Modules/GameRPG/BattleRound/BattleRoundController.swift:15-17`; `Modules/GameRPG/Root/GameRootModel.swift:373-378`
- **What:** `GameRoot` stores `lazy var battleRoundController = BattleRoundController(root: self)`, and `BattleRoundController.root` is a strong `let`. `LogGameController.root` (`LogGameController.swift:18`) and `ViewController.root` (`ViewController.swift:7`) both use `weak var root` deliberately.
- **Why:** `MasterController.swift:466-471` documents the `GameRoot` cycles as "temporary," broken by `stopGame()` dropping the controllers — but this cycle is never dropped, leaking the whole module-root graph for every `GameRoot` meant to be released (including preview/test fixtures).
- **Action:** Make `root` `weak`/`unowned` here as the other two controllers already do, or store the controller as a resettable optional `performStopGame()` clears.
- **Severity:** Medium

### 5.9 `ViewController.root` is a force-unwrapped weak reference
- **Location:** `Modules/GameRPG/Controller/ViewController.swift:6-13`; compounded at `Modules/GameRPG/Root/GameRootModel.swift:347-350` (`unsafelyUnwrapped`)
- **What:** `weak var root: GameRoot!` combined with `root.logGameController` in `logWindow()` traps the moment the referenced `GameRoot` deallocates.
- **Why:** A weak reference is by definition allowed to become nil, so this is a crash waiting on teardown ordering — and force-unwraps outside unrecoverable situations are against the project's own Swift guidelines.
- **Action:** Declare `weak var root: GameRoot?`; have `logWindow()` return an explicit empty/placeholder view when nil.
- **Severity:** Medium

---

## 6. Security

### 6.1 Sender-declared `characterId` lets any admitted player rewrite and persist another participant's Character — verified shape
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:2013-2077` (`handleValue`); supporting: `Modules/GameRPG/Root/GameRootModel.swift:63-88, 245-263`
- **What:** **Personally verified.** `handleValue`'s only ownership check is `characterId == model.data.id`, where `characterId` comes from `model.sender.characterId` — a field the sender controls in the decoded envelope. `canApplyValueUpdate` adds only a per-(sender, character, entry) timestamp monotonicity check, never a sender→character binding. The `.store` branch (line 2069) calls `updatePlayer(data:)` — a **persisting** import (`forceSave: true`).
- **Why:** Every player already receives every pin's `characterId` over the wire (encoded in `.mapState`), so a peer knows the UUIDs of other players' Characters and the GM's battle-copy monsters. A malicious or compromised peer can therefore overwrite arbitrary entries (including HP) on another Character in the master's live memory via `.valueUpdate`, or push a full crafted Character package the master **persists** under that id. `GameRootModel.add(playerId:playerModel:)` also blindly overwrites the roster's `name`/`type`/`characterId` from the sender's own claim on every message, so the roster cannot be used as a cross-check either.
- **Action:** Bind `characterId` to the sender once at join (master-side), and reject any later message whose `sender.characterId` differs from the stored binding or names a Character another sender already owns. Stop letting `add(playerId:playerModel:)` mutate `characterId`/`type` after initial admission.
- **Severity:** High

### 6.2 Peer audio bytes are imported, persisted, and re-broadcast with no baseline check — verified
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:1296-1310`
- **What:** **Personally verified.** `handleAudio`'s `.update`/`.generic` branch calls `updateGame(data: model.data, hide: false, deep: false)` then `send(type: .reveal, subtype: .show, updated: model.data)`, guarded only by `features.audioSharing`. `hide: false` maps to a persisting policy, so the peer's package is written to the master's library.
- **Why:** Every sibling handler defends the master's canonical copy first — `handlePhoto`, `handlePdf`, and `handleSpace` all compare the sender's `effectiveAssetVersion` against the master's own baseline and only import on `ItemGameStorableError.itemMissing` (confirmed by direct comparison: `handlePdf`'s reveal branch at `MasterController.swift:1733-1746` computes `senderIsAvailable`/`matchesBaseline` before publishing; `handleAudio` has no equivalent). Any admitted player can replace the master's stored audio item at any id and have the master fan the bytes out to the whole session.
- **Action:** Mirror the photo/pdf/space shape: resolve the master baseline via `share(id:)`, import only on `.itemMissing`, otherwise re-publish the master's own `createGameData` package.
- **Severity:** High

### 6.3 Session-identifying data logged at `privacy: .public`
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:1035, 1089, 1258, 1281, 2465, 2504`; `Modules/GameRPG/Controller/PlayerController.swift:906, 939, 1036`; `Modules/GameRPG/Controller/PlayerController+Value.swift:121`; `Modules/MapRPG/Controller/GameController+Metadata.swift:267, 273` (verified — see §2 Quick wins)
- **What:** `GameNetworkModel.debugDescription` embeds `sender.name` and is logged `.public` at six MasterController sites and one PlayerController site; `PlayerController.swift:906` logs the entire `controls` array (every participant's id and display name) `.public`; `:939` logs `senderName` `.public`; `PlayerController+Value.swift:121` logs `characterId` `.public`. `GameController+Metadata.swift:267/273` log pin names and computed health `.public` — independently flagged by two of the three review passes.
- **Why:** `.public` os_log payloads persist in the unified log and are captured by any sysdiagnose, leaking participants' real display names and the full session roster outside the app's trust boundary. The `+Metadata.swift` sites directly contradict the sibling function's own stated policy — `synchronizeBattleDefenders` logs the identical kind of data `.private` (`GameController+Battle.swift:511-513`, documented as a prior audit fix) right next to these two, which use `.public`.
- **Action:** Switch all human-readable/gameplay content (`debugDescription`, `controls`, `senderName`, `characterId`, pin names, health values) to `privacy: .private`; reserve `.public` for enum tokens, counters, and genuinely non-identifying values.
- **Severity:** Medium

---

## 7. Performance

### 7.1 Per-message Core Data statistics write sits on the send/receive critical path
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:809-813, 1023, 1056, 1084`; `Modules/GameRPG/Controller/PlayerController.swift:453, 491, 539-543, 1026-1030`
- **What:** Every outgoing and incoming envelope awaits `root.statisticsModel.record(...)`, a `@MainActor` method performing a Core Data duplicate-check fetch plus insert before the transport even receives the payload.
- **Why:** Persistence latency is serialized into the latency of every game message, including small, latency-sensitive ones like `.mapPin` and `.spaceTransform`.
- **Action:** Make statistics recording a detached side effect (in-memory buffer flushed periodically, or fire without awaiting) so it can never delay a send.
- **Severity:** Medium

### 7.2 Availability-list builders scan the entire library with sequential per-item file checks on the main actor
- **Location:** `Modules/PhotoRPG/Controller/GameController.swift:184-200`; `Modules/PdfRPG/Controller/GameController.swift:189-205`; `Modules/SpaceRPG/Controller/GameController.swift:394-410`; `Modules/AudioRPG/Controller/GameController.swift:139-155, 247-271`; `Modules/MapRPG/Controller/GameController+Pins.swift:180-211`
- **What:** Each `local*Versions()`/`audioList`/`missingMapImages` is a `@MainActor async` loop over every item in the module, sequentially awaiting `fileUrlDataController.hasLocalData(for:)` (which may itself lazily backfill a content hash by reading file bytes) and `networkVersion(for:)` per item. Audio is worst-case: `hasLocalDatabaseAudioData` recurses through playlist entries, making it O(items × entries).
- **Why:** These run on every join/rejoin (`PlayerController.ready()`) and on every list exchange the master receives, so the main actor is repeatedly parked on file-system round trips proportional to library size before a player can participate.
- **Action:** Cache the per-item availability/version map, invalidated on item mutation, instead of rebuilding it per message; parallelize the scan with a `TaskGroup` off the main actor, applying the resulting snapshot in one main-actor step.
- **Severity:** Medium

### 7.3 Table transfer deep-copies the entire persisted library on every received package
- **Location:** `Modules/TableRPG/Controller/GameController.swift:161, 197-203, 213-221`
- **What:** `receiveTable` unconditionally calls `persistentTableCopies()`, which maps *every* id in the library through `itemSync(for:)?.copy()`, plus two more full-library dictionary rebuilds (`tableObjectIdentities()`, `newlyImportedTables()`) — all synchronously on the main actor for one incoming table.
- **Why:** Only the ids actually present in the imported package are used afterward, so the cost scales with the whole Table library rather than with the one table being received, on the UI thread, during a live presentation.
- **Action:** Compute `importedTables` first, then copy only `persistentTables` for those ids; move the copy work off the main actor.
- **Severity:** Medium

### 7.4 `GameMessagePipeline.messages` is an unbounded inbound queue
- **Location:** `Modules/GameRPG/Model/GameMessagePipeline.swift:112-134`
- **What:** `recentKeys` is capped at 256, but `messages` grows without limit, and each element retains a full `GameNetworkModel` — megabytes for map/photo/pdf/space packages.
- **Why:** Any producer faster than the main-actor consumer (a SharePlay journal burst, or a peer sending distinct-counter payloads on purpose) accumulates full payloads in memory; there is no per-sender rate or depth limit.
- **Action:** Cap `messages` (e.g. 128) with drop-oldest or refuse-past-cap, mirroring the `recentKeys` FIFO already in this file; consider a per-sender depth budget.
- **Severity:** Medium

### 7.5 `gameModel.logs`/`logData` grow for the whole session with no eviction
- **Location:** `Modules/GameRPG/Controller/LogGameController.swift:101-128`; `Modules/GameRPG/Root/GameRootModel.swift:41-42, 47`
- **What:** `addMessage` appends one `LogGameModel` per outgoing master message, unconditionally logging every `.mapState`/`.mapPin`/`.battleRound`; the arrays are only cleared when the session id changes. `GameRootModel.latestValueUpdateTimestamps` has the same unbounded shape, growable by a peer sending many distinct `entryId`s.
- **Why:** A long session produces thousands of entries even though the UI only renders 25 at a time. The sibling `deliveryMessagesByWireID` right next to this code is deliberately capped at 256 ("per CODE_AUDIT §5.20" — a prior fix); the log itself was left unbounded.
- **Action:** Apply the same bounded-FIFO treatment already used for `deliveryMessagesByWireID`: cap `logs`/`logData` at a few hundred entries with oldest-eviction; bound `latestValueUpdateTimestamps` per sender.
- **Severity:** Medium

### 7.6 `mapContentVersion` rebuilds and SHA-256s the full map snapshot on every call, with no memoization
- **Location:** `Modules/MapRPG/Controller/GameController+Metadata.swift:36-46, 84-122`; `Modules/MapRPG/Controller/GameController.swift:293-296, 381-402`; `Modules/MapRPG/Model/MapUpdatePayload.swift:21-30, 136-145`
- **What:** `mapContentVersion` builds a full `MapSnapshot` (copying every pin/entry/wall), then a `CanonicalMapContent` (a second copy plus two sorts), then a sorted-key JSON encode and SHA-256 — synchronously on the main actor. `networkGeneration` calls it whenever `authoritativeGeneration` is nil, which is the master's normal steady state.
- **Why:** The multiplier compounds: `stablePackageMetadata` calls this twice per attempt × 3 attempts; `networkMapContentUpdate` adds another full snapshot+encode and a third call per attempt — up to ~24 full snapshot+hash builds for one structural update. `isCurrentGeneration` (§5.2) runs this once per *inbound* `.mapPin`, so several players moving pins makes the master re-hash the entire map several times a second.
- **Action:** Cache the fingerprint on `MapGameModel`, keyed by a cheap mutation counter invalidated in `mutatedPinState`/`updateMap`/`MapSnapshot.apply`; at minimum, have `stablePackageMetadata`/`networkMapContentUpdate` reuse one capture instead of recomputing per validation step.
- **Severity:** Medium

### 7.7 Every roster change and Character sync re-broadcasts the full map structural snapshot
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:560-579` (`resetPlayers`), `:2083-2097` (`publishCurrentMapAfterPlayerPinChange`)
- **What:** Both send a complete, untargeted `networkMapContentUpdate` (every pin/entry/wall) plus a full `networkMapUpdate` to the whole group whenever a player is added/removed or a Character package finishes syncing.
- **Why:** The information that actually changed is one player pin's metadata. With N players joining or reconnecting (which re-runs the Character handshake), the master pushes N complete map snapshots to every participant over SharePlay's slower FaceTime relay, and churns the §7.6 fingerprint each time.
- **Action:** Target the send at the joining player where possible; coalesce repeated roster/Character-sync republishes within a short window instead of one full pair per event.
- **Severity:** Medium

---

## 8. SwiftUI / UI

_No findings — this audit's scope was `Modules/GameRPG/Controller/*` and the per-module `GameController.swift`/`GenericGameController` files plus `BattleRoundController`. No SwiftUI view files were in scope; see §11._

---

## 9. Dead code / duplication / refactor

Note on scope: a targeted read (not just grep) found **no** `TODO`/`FIXME`/`HACK`/`XXX`/`#warning` markers, `#if false` blocks, or commented-out code anywhere in these 35 files — worth recording as a positive, since the skill's checklist asks for it explicitly. The `print()`/pre-scan hit in `GameController+Metadata.swift` was a false positive (`MapAssetFingerprint(` matching the substring `print(`); there are zero `print()`/`debugPrint()` calls in scope — all diagnostics go through `Logger` with (mostly) explicit privacy annotations, see §6.3 for the exceptions.

### 9.1 `GenericGameController` is adopted by only 2 of 12 modules — 10 verbatim copies of its core have already drifted
- **Location:** `Modules/CoreRPG/Controllable/GenericGameController.swift:13-48` vs. `Modules/AdventureRPG/Controller/GameController.swift:39-64`, `AudioRPG/Controller/GameController.swift:47-70`, `CharacterRPG/Controller/GameController.swift:128-199`, `DiceRPG/Controller/GameController.swift:65-83`, `MapRPG/Controller/GameController.swift:244-264`, `PdfRPG/Controller/GameController.swift:78-98`, `PhotoRPG/Controller/GameController.swift:73-93`, `SpaceRPG/Controller/GameController.swift:207-227`, `TableRPG/Controller/GameController.swift:59-79`, `WeatherRPG/Controller/GameController.swift:52-72`
- **What:** `gameItem(for:)`, `setGame(item:itemId:)`, `currentItem()`, and the `itemControllable`/`exportControllable` bridge are copy-pasted into all ten remaining per-module `GameController`s; only RuleRPG and GeneratorRPG use the generic via an 8-line `typealias`. Each of the ten has genuine additional behavior, so a bare whole-type `typealias` isn't viable for them — but the shared core is still duplicated ten times.
- **Why:** The copies have already drifted: `GenericGameController.setGame` uses `gameModel.items.contains(itemId)` while the bespoke copies use the older `firstIndex(where:) != nil`; DiceRPG's copy omits `currentItem()` entirely.
- **Action:** Extract the shared core into an inheritable form — a `ModuleGameControllable` protocol with default implementations, or have each bespoke controller hold a `GenericGameController` and forward to it — then delete the ten copies. Add `currentItem()` to DiceRPG in the process.
- **Severity:** High

### 9.2 `PhotoRPG` and `PdfRPG` `GameController.swift` are near-verbatim duplicates of each other (~200 lines each)
- **Location:** `Modules/PhotoRPG/Controller/GameController.swift:6-228`; `Modules/PdfRPG/Controller/GameController.swift:6-233`; a third, less exact copy at `Modules/SpaceRPG/Controller/GameController.swift:22-44, 234-434`
- **What:** `PhotoGameModel`/`PdfGameModel` are byte-for-byte identical apart from the type name (including a shared comment). The `PhotoGameControllable`/`PdfGameControllable` conformances (`*List`, `apply*List`, `masterVersion`, `reportedVersion`, `setMasterVersion`, `isXAvailable`, `markXAvailable`, `markXAvailableToCurrentPlayers`, `removeXReports`, `localXVersions`, `hasLocalDatabaseXData`, `rebuildPlayerReports`) and the `*ListRequest` structs are line-for-line identical modulo the module name.
- **Why:** ~200 lines duplicated with no mechanism keeping them in sync; SpaceRPG is a third copy of the same ledger (with transform state genuinely added). Any bug fix to the availability ledger needs three applications.
- **Action:** Extract a generic `PlayerVersionLedger` model plus a `FileAvailabilityGameControllable` protocol with default implementations, parameterized by `NetworkModules` case and item type. Photo/Pdf become thin conformances; Space keeps only its transform-specific additions.
- **Severity:** High

### 9.3 `MasterController.handlePhoto`/`handlePdf`/`handleSpace` are three near-identical ~140-line handlers
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:1706-1848` (`handlePdf`), `:1850-1992` (`handlePhoto`), `:2120-2314` (`handleSpace`)
- **What:** All three share the same shape (`.ok` → set version + mark available; `.assetRequest` → export; `.reveal` → build reference, compare `senderIsAvailable`/`matchesBaseline`, republish or forward; `.store`/`.update` → apply + rebroadcast), down to a cross-referencing comment ("Mirror handlePhoto/handleSpace's `.itemMissing` import fallback").
- **Why:** The copies have already drifted in ways that look accidental: `handlePhoto`'s `.assetRequest` branch omits the `hasLocalFileData` guard both `handlePdf` (line 1728) and `handleSpace` (line 2142) apply; `handlePhoto`'s `.store` case (lines 1949-1950) omits the same guard `handlePdf` has (line 1805). See also §6.2 — `handleAudio` is the fourth, most divergent copy of this same shape, missing the baseline check entirely.
- **Action:** Extract one generic `handleFileBackedModule(_:controllable:availability:featureEnabled:)`, then have the four handlers (including Audio) pass their module-specific policy. Resolve the `hasLocalFileData` divergence deliberately in the process.
- **Severity:** High

### 9.4 `PlayerController.sharePhoto`/`sharePdf`/`shareSpace` are three near-identical ~55-line methods
- **Location:** `Modules/GameRPG/Controller/PlayerController.swift:214-271, 273-329, 331-388`
- **What:** Identical structure — fetch baseline, compute `senderIsAvailable`/`matchesBaseline`, build one of three envelope types, send, conditionally `markXAvailableToCurrentPlayers`. Differs only by module root and `shareSpace`'s extra feature guard.
- **Why:** ~110 duplicated lines paired directly with the equally duplicated master-side handlers in §9.3; the two sides must be kept in lockstep by hand.
- **Action:** Once the `FileAvailabilityGameControllable` protocol from §9.2 exists, collapse into one `shareFileBackedItem(_:controllable:updateType:featureEnabled:)`.
- **Severity:** High

### 9.5 `PlayerController+Photo/+Pdf/+Space` duplicate the deferred-reveal state machine three times
- **Location:** `Modules/GameRPG/Controller/PlayerController+Photo.swift:8-12, 137-198`; `PlayerController+Pdf.swift:8-12, 144-199`; `PlayerController+Space.swift:8-12, 189-246`; model side: `Modules/GameRPG/Controller/PlayerControllerModel.swift:16-29, 245-284, 303-342, 361-402`
- **What:** Three private `PlayerXRevealValidation` enums, three `playerXRevealValidation(for:)` functions, and three `retryDeferredXReveals(from:)` loops with identical control flow; three identical `DeferredXRevealKey` structs and three structurally identical capped-FIFO deferral stores (cap 32 each).
- **Why:** The largest single duplication cluster in the player path (~250 lines across five files), and it has already drifted: `+Photo`'s `.reveal` failure branch (lines 79-88) doesn't gate on the first-request set that `+Pdf` (84-85) and `+Space` (100-101) both do; `+Pdf`'s `.store` returns `nil` on failure (120) where `+Space` sends a repair request (131-133).
- **Action:** Generify the deferral store into one `DeferredRevealStore` keyed by `(module, masterId, senderId)`; extract one `handleFileBackedReveal` in a shared `PlayerController+FileModule.swift` taking the availability controllable, module case, and completion closure. Reconcile the three divergent failure branches explicitly.
- **Severity:** High

### 9.6 `MasterController.swift` is 2,692 lines and, uniquely among the controllers, has no extension files
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:1-2692`
- **What:** One file holds `MasterControllerModel` (17-451), lifecycle (496-588), send/envelope construction (590-837), the `MasterNetworkStoreDelegate` conformance and admission policy (839-1239), nine per-module handlers plus dispatch (1241-2315), the entire proxy-host routing layer (2317-2564), and presentation replay (2566-2692).
- **Why:** The player-side equivalent splits the identical responsibilities across eleven `PlayerController+X.swift` files; the asymmetry is the direct cause of §9.3's three near-identical handlers sitting 400 lines apart in one file rather than in comparable, separately-reviewable files.
- **Action:** Split along the file's own `// MARK:` boundaries: `MasterControllerModel.swift` (17-451, has an exact precedent in `PlayerControllerModel.swift`), `MasterController+Send.swift` (590-837), `MasterController+NetworkDelegate.swift` (839-1239), one `MasterController+X.swift` per module (1241-2315), `MasterController+Proxy.swift` (2317-2564), `MasterController+Replay.swift` (2566-2692).
- **Severity:** High

### 9.7 `PlayerController.swift` (1,045 lines) mixes lifecycle, the three duplicated share methods, and the whole receive pipeline
- **Location:** `Modules/GameRPG/Controller/PlayerController.swift:1-1045`
- **What:** Despite eleven existing extension files, the base file still carries lifecycle (57-157), the three §9.4 share methods (214-388), generic send (390-461), proxy relay (463-577), journal predicates (579-593), the full `PlayerNetworkStoreDelegate` conformance including SharePlay admission (623-801), session authority (806-856), and the message pipeline (858-1044).
- **Why:** The receive/admission pipeline — the most safety-critical code in the module, deciding which envelopes may mutate state — is buried under unrelated send-side code.
- **Action:** Extract `PlayerController+Sharing.swift` (214-388, or delete per §9.4), `PlayerController+SharePlayDelegate.swift` (623-801), `PlayerController+Pipeline.swift` (806-1044), leaving lifecycle and send in the base file.
- **Severity:** High

### 9.8 `PlayerControllerModel.swift` (1,040 lines) holds five unrelated state machines in one `@Observable` type
- **Location:** `Modules/GameRPG/Controller/PlayerControllerModel.swift:1-1040`
- **What:** One class owns the SharePlay master-participant binding (100-208), four list-sequence gates (210-359), three deferred-reveal stores plus space transforms and map pins (245-515), the presentation-intent causal-ordering machine (517-714), and the entire map repair/pending-update state (716-936).
- **Why:** Sixty-plus stored properties on one `@Observable` class means every mutation invalidates observers of all of them; the presentation-intent logic (517-710) is self-contained and independently testable today.
- **Action:** Extract `PresentationIntentTracker` (517-714) and `MapRepairState` (716-936) as composed types; collapse the deferral stores per §9.5. Target well under 500 lines for the residual model.
- **Severity:** High

### 9.9 `PlayerController+Map.swift` (698 lines) contains four distinct responsibilities
- **Location:** `Modules/GameRPG/Controller/PlayerController+Map.swift:1-698`
- **What:** The `handleMap` dispatcher (15-330, with a ~180-line `.reveal` branch spanning six levels of nested conditionals across four independent generation dimensions), the local-master short-circuit (341-367), content-update application (369-469), repair request construction (487-578), and pin/battle-round deferral replay (580-697).
- **Why:** `handleMap`'s `.reveal` case is the hardest-to-follow control flow in scope.
- **Action:** Split into `PlayerController+Map.swift` (dispatch + `.update`), `PlayerController+MapReveal.swift` (the `.reveal`/`.store` branches, decomposed into named `revealedFullPayload`/`revealedReference` helpers), and `PlayerController+MapRepair.swift` (`requestFullMap`, `requestMapContent`, `completeMapRepairIfSatisfied`, `applyPendingX`, the retry-deferred helpers).
- **Severity:** High

### 9.10 Duplicated per-module sequence-gate triplets — 8 copies across two model types
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:375-433, 435-450` (audio/photo/pdf/space + a fifth space-transform variant); `Modules/GameRPG/Controller/PlayerControllerModel.swift:210-359`
- **What:** `canApplyXList(from:counter:)`/`recordXList(counter:from:)`/`resetXListSequence()` written out four times in each model with identical bodies apart from which dictionary they touch.
- **Why:** ~150 lines of pure boilerplate; every new file-backed module adds three more methods to two models plus a `stop()`/`resetForLostConnection` line.
- **Action:** Introduce one `CounterSequenceGate` value type and store `[NetworkModules: CounterSequenceGate]`, collapsing the reset-chain calls into a loop.
- **Severity:** Medium

### 9.11 Duplicated `applyXList` helpers — 8 copies, 4 on each controller
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:1321-1333, 1835-1848, 1979-1992, 2301-2314`; `PlayerController+Audio.swift:69-81`, `+Photo.swift:122-135`, `+Pdf.swift:129-142`, `+Space.swift:174-187`
- **What:** Every one is the same five-line admission guard (sender check, `canApplyXList`, apply) followed by `recordXList` and `return true`.
- **Why:** Eight copies of one admission policy; any change (e.g. adding a role check) must be replicated eight times.
- **Action:** One shared generic helper per controller, parameterized by the availability controllable and the §9.10 gate.
- **Severity:** Medium

### 9.12 Clock-skew policy defined three times with two different spellings of the same 300 seconds
- **Location:** `Modules/GameRPG/Model/GameNetworkModel+RoutingPolicy.swift:15`; `Modules/SpaceRPG/Controller/GameController.swift:8`; `Modules/MapRPG/Controller/GameController+Metadata.swift:13`
- **What:** Three independently-declared constants encoding the identical "reject events more than five minutes in the future" rule.
- **Why:** A change to the tolerated skew silently applies to only one of pins, transforms, or envelopes.
- **Action:** Declare one `NetworkTimestampPolicy.maximumFutureSkew` in CoreRPG; reference it from all three sites.
- **Severity:** Medium

### 9.13 Two independent retry budgets for the same map-export stability problem compound into 27 attempts
- **Location:** `Modules/MapRPG/Controller/GameController+Metadata.swift:14, 85`; `Modules/MapRPG/Controller/GameController.swift:357, 382`; `Modules/GameRPG/Controller/MasterController.swift:465, 1618-1648`
- **What:** `stableMapRecoveryBundle` loops up to 3× calling `createMapGameData` (loops up to 3×) calling `stablePackageMetadata` (loops up to 3×) — built from two separately-named constants that happen to share a value.
- **Why:** The effective retry budget is an emergent product of three nested loops, invisible at any single site.
- **Action:** Name the composed budget explicitly, or flatten to one retry level.
- **Severity:** Medium

### 9.14 Unnamed magic constants in DiceRPG and AudioRPG game controllers
- **Location:** `Modules/DiceRPG/Controller/GameController.swift:581, 348, 370`; `Modules/AudioRPG/Controller/GameController.swift:73`
- **What:** `audioPlayer.volume = 0.33`; two switch statements selecting among `9`/`6` sound-file variants that must stay in sync with the hard-coded `RawDie.roll(.number(...))` counts; `guard deep < 10` as an unnamed audio-playlist recursion cap, sitting beside other guards in the same file that use a `visited: Set<UUID>` cycle guard instead.
- **Why:** The sound-variant count and the switch arm count are two encodings of one fact that will silently desync; the recursion cap is an unnamed peer of the codebase's own `RecursionLimits` convention (see §5.7).
- **Action:** Name `diceSoundVolume`; index sound resources by array + `RawDie.roll(.number(array.count))` instead of a hand-matched switch; move `deep < 10` behind a named `RecursionLimits` case, or switch to the `visited` set the rest of the file uses.
- **Severity:** Medium

### 9.15 `DiceRPG/GameController.swift` (610 lines) mixes networking, audio playback, and dice arithmetic
- **Location:** `Modules/DiceRPG/Controller/GameController.swift:1-610`
- **What:** One file holds `DiceGameModel` (including an `AVPlayer`), the network `DiceGameStorable` conformance, player-dice visibility queries, roll orchestration + sound selection, and the entire pure dice-arithmetic engine (`calculate`, `sumResult`, `coup`, `fumble`, `diceSuccess`, `maxValuePerDice`, `reorder`, `resultText`).
- **Why:** The arithmetic engine is pure and deterministic but cannot be tested or reused without the whole networked, `AVPlayer`-holding controller.
- **Action:** Extract `GameController+Result.swift` (the arithmetic), `GameController+Roll.swift` (roll + sound), `GameController+PlayerDice.swift` (visibility queries).
- **Severity:** Medium

### 9.16 `MapRPG/GameController+Battle.swift` (591 lines) is a fifth file that itself needs splitting
- **Location:** `Modules/MapRPG/Controller/GameController+Battle.swift:1-591`
- **What:** The file's own header comment records that a physical split was previously considered and rejected in favor of `// MARK:` dividers. It now spans combatant lifecycle, turn/initiative, rolls and value entries, the defender/health sync (including five `Logger.debug` calls), and network apply/export.
- **Why:** At 591 lines with four unrelated concerns, and given the health-sync section is the most-churned code in MapRPG (three separate entries in project memory), the earlier "MARK dividers are enough" call no longer holds.
- **Action:** Revisit the split: `+BattleLifecycle.swift`, `+BattleValues.swift`, `+BattleHealth.swift`, `+BattleNetwork.swift`. The cross-referencing comments survive a file split unchanged.
- **Severity:** Medium

### 9.17 Player screen-sharing is a complete write-only path with no reader
- **Location:** `Modules/GameRPG/Controller/LogGameController.swift:57-62, 328-332`; fed by `:148-152` and `MasterController.swift:1449-1452`; stored in `Modules/GameRPG/Root/GameRootModel.swift:43`
- **What:** `.screen` messages are received, decoded, and stored into `playerScreens` on every master. Repo-wide grep confirms neither `LogGameController.players` nor `PlayerScreenModel` is referenced anywhere outside its own declaration — not even in tests, apart from one assertion reading `playerScreens` itself.
- **Why:** A live network receive path and a growing per-player screenshot `Data` store feed a feature with no UI — unbounded memory held for nothing.
- **Action:** Either wire `LogGameController.players` into a view, or delete `players`, `PlayerScreenModel`, `updateScreen`, `GameRootModel.playerScreens`, and short-circuit `MasterController.handleGame`.
- **Severity:** Medium

### 9.18 "All game modules" enumerated by hand at four sites
- **Location:** `Modules/AdventureRPG/Controller/GameController.swift:89-101` (9 roots); `Modules/GameRPG/Controller/MasterController.swift:535-546, 967-980` (6 roots each); `Modules/GameRPG/Controller/PlayerController.swift:146-156` (6 roots, plus a repeated identical expression computed 6 times at lines 148-153)
- **What:** Four hand-maintained lists of module roots doing the same per-module operation.
- **Why:** Adding a 13th module means remembering four unrelated sites; omitting one silently leaks per-module state between sessions — the exact class of bug `resetGameState()` exists to prevent.
- **Action:** Expose an ordered `[any GameControllable]` collection on the root manager and iterate it at all four sites; hoist `PlayerController.resetPlayers`'s repeated expression into one `let`.
- **Severity:** Medium

### 9.19 `deferMapPin` decodes with a fresh `JSONDecoder` instead of the module's shared decode helper
- **Location:** `Modules/GameRPG/Controller/PlayerControllerModel.swift:465`
- **What:** `try? JSONDecoder().decode(MapPinModel.self, from: data)` allocates a decoder per deferred pin on the main actor, where the rest of the codebase uses `MapPinModel.decodeData(of:)` (e.g. `Modules/MapRPG/Controller/GameController+Pins.swift:100`).
- **Why:** Duplicates the `MessageMapper` decoding convention, bypassing any shared configuration and adding a per-message allocation during pin bursts.
- **Action:** Replace with `MapPinModel.decodeData(of:)`. (Also listed as a quick win — see §2.)
- **Severity:** Low

### 9.20 Five deferred-buffer caps declared as function-local `let`, breaking the file's own convention
- **Location:** `Modules/GameRPG/Controller/PlayerControllerModel.swift:251, 309, 367, 431, 489`
- **What:** `maximumDeferredPhotoReveals`/`PdfReveals`/`SpaceReveals` (32 each), `maximumDeferredSpaceTransforms`/`MapPins` (64 each) are declared inside the functions that use them, where `MasterControllerModel`'s three equivalents (`MasterController.swift:150, 161, 163`) are `private static let`.
- **Why:** Function-local caps are invisible to an auditor checking memory bounds and untestable in isolation.
- **Action:** Hoist all five to `private static let`. (Also listed as a quick win — see §2.)
- **Severity:** Low

### 9.21 `GameControllable.updateGame(data:subtype:)` and its only implementation are unreachable
- **Location:** `Modules/CoreRPG/Controllable/GameControllable.swift:141, 170` (requirement + empty default); `Modules/SpaceRPG/Controller/GameController.swift:389-392` (implementation)
- **What:** A repo-wide grep for call sites passing `subtype:` to `updateGame` returns only the three declarations. SpaceRPG's implementation forwards to `applySpaceTransform(data:counter:)`, but both real call sites (`MasterController.swift:701-714`, `PlayerController+Space.swift:158-162`) call `applySpaceTransform` directly instead.
- **Why:** A dead extension point on a protocol conformed to by twelve types, plus a dead override that looks like a live routing hook.
- **Action:** Delete the protocol requirement, its default implementation, and SpaceRPG's override; fold the two-argument `applySpaceTransform` overload into the timestamped one with a defaulted parameter.
- **Severity:** Low

### 9.22 Test-only API surface on production controllers
- **Location:** `Modules/GameRPG/Controller/LogGameController.swift:28-31, 64-67, 130-134, 163-167`; `MasterController.swift:222-227, 367-369, 1454-1462`; `PlayerController.swift:587-589`
- **What:** Eight members referenced only from `Tests/`, with production code using an alternative in each case (`logRows` vs. `logModels`, `updateMessage(messageID:player:)` vs. the counter variant, `handleMap(_:origin:)` vs. the `connectionId` overload, `usesFileJournal(for:)` vs. the three-argument form). Two are already documented as test affordances; six are not.
- **Why:** Readers can't tell which entry points the running app actually uses.
- **Action:** Either document each as a test affordance (matching the existing documented pair), or replace the undocumented shims with direct calls in the tests and delete them.
- **Severity:** Low

### 9.23 `CharacterRPG` has two copy-pasted `gameDiceId` methods differing only in dictionary key
- **Location:** `Modules/CharacterRPG/Controller/GameController.swift:149-169, 172-189`
- **What:** `gameDiceId(itemId:entryId:)` and `gameDiceId(itemId:diceId:)` share an identical 14-line body differing only in the dictionary key used.
- **Why:** Two copies of the same caching protocol for the `ValueGameModel` dictionaries; a fix to the invalidation rule needs both.
- **Action:** Extract `private func cachedGameDice(key: UUID, diceId: UUID) -> UUID?` and have both call it.
- **Severity:** Low

### 9.24 Extension-file naming convention broken by three GameRPG files
- **Location:** `Modules/GameRPG/Controller/PlayerController+Handling.swift:1-141`; `PlayerController+ProxyDelegate.swift:1-95`; `PlayerController+Value.swift:66-124`
- **What:** Nine `PlayerController+X.swift` files are named for their module. Three break the pattern: `+Handling` holds both the `handle` dispatcher and response-envelope construction; `+ProxyDelegate` holds the delegate conformance, proxy Value handling, *and* proxy-focus task machinery; `+Value` holds a "Send Character" section (66-124) that is outbound lifecycle, not `.value` handling.
- **Why:** Contributors can't predict which file a given behavior lives in — which is how `handleValue` (`+Value.swift:10`) ended up dispatching to `handleProxyValue` in a different file.
- **Action:** Rename/re-split to `PlayerController+Dispatch.swift`, `PlayerController+Proxy.swift`; move "Send Character" into `PlayerController+Character.swift` or the base lifecycle section.
- **Severity:** Low

### 9.25 `MapRPG/GameController+MapSync.swift`'s name doesn't describe its contents
- **Location:** `Modules/MapRPG/Controller/GameController+MapSync.swift:1-68`
- **What:** Holds genuine sync code (`updateMap(for:with:)`, `mapUpdateResult`, `networkMapUpdate`, `networkPin`) but also `saveAll()` (persistence/export) and `demoNextMap(itemId:restart:)` (a demo-mode driver). "Map" is also redundant inside MapRPG's own `GameController`.
- **Why:** `saveAll` is the only export path for a live game's map state and isn't discoverable under a "MapSync" filename; demo-only code sits beside production sync logic.
- **Action:** Rename to `GameController+Sync.swift`; move `saveAll` to `+Metadata.swift` (or a new `+Export.swift`) and `demoNextMap` to `+Demo.swift`.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Introduce a shared "file-backed module" abstraction.** §9.1, §9.2, §9.3, §9.4, §9.5, §9.10, and §9.11 are all facets of the same gap: Photo/Pdf/Space/Table (and partially Audio) each hand-roll the same availability-ledger, admission-guard, and deferred-reveal machinery. A `FileAvailabilityGameControllable` protocol plus a generic `handleFileBackedModule`/`shareFileBackedItem` pair would collapse roughly 700 duplicated lines into shared code — and would have prevented §6.2 (audio's missing baseline check) by construction, since the shared helper would apply the same defensive check to every module automatically.
2. **Make the network receive-path isolation explicit.** §3.1-§3.4 all stem from one root cause: delegate protocols without `@MainActor` conformance losing their expected isolation under `SWIFT_APPROACHABLE_CONCURRENCY = YES`. Annotating the protocol requirements `@MainActor` (or every witness) fixes all four at once and removes the need for the in-code comments currently asserting an isolation guarantee the compiler doesn't enforce.
3. **Split the four multi-thousand-line controller files along their existing `// MARK:` boundaries.** §9.6-§9.9, §9.15, §9.16 — the codebase already uses this convention consistently on the player side (eleven `PlayerController+X.swift` files); the master side and two module `GameController`s haven't caught up. This isn't a rewrite, just extracting already-marked sections into files.
4. **Establish one bounded-FIFO helper for in-memory session buffers.** §7.4, §7.5, and the `deliveryMessagesByWireID` precedent they should have followed all need the same fix: a small `BoundedFIFO<Key, Value>` type used consistently instead of ad hoc caps applied to some buffers and not others.
5. **Audit `os_log` privacy annotations for consistency across sibling functions.** §6.3 shows the same category of data (pin names, health values, participant identity) logged at different privacy levels in adjacent functions that clearly intended the same policy — a single pass specifically for this would likely find more than the sites listed here.

---

## 11. What was NOT audited

- Everything outside the 35-file scope listed at the top of this report: `GameRPG/GameViews/*`, `BattleRound/*` (views), `SetupViews/*`, `Statistics/*`, `Table3D/*`, `Search/*`, `Browser/*`, `GameCenter/*`, `ExternalScreen/*` — SwiftUI view code was entirely out of scope for this pass (see §8).
- The network/transport layer proper — `ConnectionController`, `GameNetworkController`, `ListenerManager`, `JoinCodeStorage`, `SharePlay/*` — except where directly called from an in-scope controller and cited above (e.g. `ConnectionController` as the actor referenced in §3.1).
- Non-`GameController` code in every other module (`EditController`, `ItemController`, `DataController`, `SyncDataController`, etc.) except where read for cross-reference, such as `LinkController.calculate` and `RecursionLimits` (§5.7).
- Algorithmic correctness of dice/battle math beyond the specific bug in §5.1.
- Xcode project/build settings, beyond confirming the `SWIFT_APPROACHABLE_CONCURRENCY`/`SWIFT_STRICT_CONCURRENCY`/`SWIFT_VERSION` values needed to verify §3.1's premise.
- Third-party SPM dependency internals (`RPGTabletopGameContent`, `swift-syntax`, `swift-snapshot-testing`, etc.).
- Test coverage or correctness — `Tests/GameRPGTests/*` and the per-module `GameControllerTests.swift` files exist and were referenced (e.g. §9.22) but not reviewed for correctness or coverage gaps.
- Localization and string catalogs.
- Performance profiling via Instruments — the findings in §7 are code-pattern-based (what the code does on paper), not measured from a trace.
- A clean, warning-free compile (confirmed for this scope) does not mean concurrency-safe: Swift's strict-concurrency checker verifies data-race freedom for code it can see, not the higher-level protocol/actor-isolation semantics under `SWIFT_APPROACHABLE_CONCURRENCY` documented in §3.1, nor logic bugs, security trust boundaries, or performance — that's what this report's manual findings are for.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference — it should land on the cited line.

Personally re-opened and confirmed during this audit (beyond what each finding's own citation already provides):

- **§5.1** (Critical) — opened `Modules/GameRPG/BattleRound/BattleRoundController.swift:342-352` and `Modules/MapRPG/Controller/GameController+Metadata.swift:276-286` side by side. Confirmed: the GameRPG copy is missing the `value >= Double(Int.min), value <= Double(Int.max)` guard the MapRPG original has. `Int(_: Double)` traps on an out-of-range finite value — this is standard, documented Swift behavior, not a hypothetical.
- **§5.2** — opened `Modules/MapRPG/Model/MapUpdatePayload.swift:69-102`. Confirmed `CanonicalMapContent.init`'s pin-neutralization block resets seven runtime fields but not `healthPercent`.
- **§5.5** — opened `Modules/GameRPG/Controller/LogGameController.swift:225-244`. Confirmed `recipientSnapshot` calls `Dictionary(uniqueKeysWithValues: controls.map { ($0.id, $0.show) })` with `controls` sourced from `gameModel.gameControl.controls`.
- **§6.1** — opened `Modules/GameRPG/Controller/MasterController.swift:2005-2077`. Confirmed `handleValue`'s ownership check is `characterId == model.data.id` against the sender-declared `model.sender.characterId`, with no independent binding lookup, and that the `.store` branch reaches a persisting `updatePlayer(data:)` call.
- **§6.2** — opened `Modules/GameRPG/Controller/MasterController.swift:1270-1310` and, for comparison, `:1706-1730`. Confirmed `handleAudio`'s update path calls `updateGame`+`send` with only a feature-flag guard, where `handlePdf`'s equivalent path requires `hasLocalFileData` first.
- **§3.1** — ran `grep` against `MasterRPG.xcodeproj/project.pbxproj` and confirmed `SWIFT_APPROACHABLE_CONCURRENCY = YES` alongside `SWIFT_STRICT_CONCURRENCY = complete` and `SWIFT_VERSION = 6.0` on the relevant build configurations; confirmed `MasterNetworkStoreDelegate`/`PlayerNetworkStoreDelegate` in `Modules/GameRPG/Network/GameNetworkControllerModel.swift:10-40` are declared `Sendable & AnyObject` with no `@MainActor`.

For every other High finding, the location, line range, and code shape as described were taken from the originating review pass's citation and cross-checked for internal consistency (e.g. §9.3's claim about `handlePhoto` missing a guard `handlePdf` has was directly visible in the same `handlePdf` excerpt opened for §6.2's verification). If any finding doesn't reproduce when you visit the line, flag the specific reference and it will be re-investigated.
