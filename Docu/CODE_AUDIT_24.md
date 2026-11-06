# MasterRPG Code Audit — new features since 3.0.1

Generated 2026-11-05 against `ac4249ad7` (`develop`). Read-only audit: no code was changed.

**Scope.** Every Swift change from tag `3.0.1` (2026-10-18) to `HEAD`: 70 commits, 610 files, +26.4k / −5.1k lines. Most of the range already has its own audits, so the work was split:

- **Deep pass** over everything after the last full audit (`bf749c86d`, `Docu/CODE_AUDIT_23.md`): 26 commits, 268 Swift files, +9.4k lines. Features: table players (Characters at the table), player pin control, player companions, battle opponents in all rounds, pin photo popover, photo/weather on the map, 3D table weather (switched off), 2D/visionOS weather window, macOS menu bar audio player, audio repeat-play fix and diagnostics, quick dice relocation/colors/tvOS removal, game-import folder dedup, visionOS GM dice, tvOS statistics/Game Center, chart fixes, SharePlay join off the main actor, and the audit-23 fix commit `15d8b4977`.
- **Regression pass** over the earlier part (`3.0.1..bf749c86d`): App Intents, Quick Dice, Quick Link, map resize, iCloud folder Sync, folder prune, duplicate repair. These were audited in `CODE_AUDIT_Since_3.0.1.md`, `CODE_AUDIT_AppIntents*.md`, `CODE_AUDIT_QuickDice.md`, `CODE_AUDIT_22.md`, `_22a.md` and `_23.md`. This audit only checks that those fixes still hold, and does not repeat their findings.

**Compiler ground truth.** Clean Debug builds into fresh derived-data folders: MasterRPG on the iOS Simulator (iPhone 18 Pro), MasterRPG on the visionOS Simulator, MasterMac and MasterTV (tvOS Simulator). All four **succeeded with 0 Swift warnings**. The only diagnostics were two `appintentsmetadataprocessor: Metadata extraction skipped` notes. So the concurrency section is based on reading the code, not on compiler warnings. No tests were run.

**Method.** Five read-only agents worked in parallel:

- A: concurrency and API.
- B: dead code and duplication.
- C1: table players, pin control, companions, battle, folder import and visionOS dice.
- C2: photo/weather on the map, audio, SharePlay, tvOS and Quick Dice.
- D: regressions from the fix commits.

I then did the SwiftUI pass myself and re-opened every High and Medium security or bug claim.

Evidence markers:

- **[verified]**: I read the cited lines and the behaviour follows from them.
- **[traced]**: the call path was followed in source but not run.
- **[reasoned]**: the reporting agent's reading.

Line numbers are HEAD lines.

**Result in one line:** one High privacy leak (a game master's private photo of a hidden pin reaches players through the late-joiner replay and the external screen). Four Medium security gaps in the new peer-facing features: the pin-photo visibility predicate, companion pin ids, companion Character overwrite, and unsanitized folder `fileUrl`s. A cluster of Medium bugs around the repurposed `isZoom` flag and table-player pin handover. No Critical findings. Every audit-23 fix that was checked still holds, with three incomplete edges (§5.11–§5.13).

---

## 1. Executive summary

1. **[High] A photo the game master opens privately (from a hidden pin) becomes the shared screen state: the late-joiner replay reveals it and the external TV screen shows it** — §6.1 — `Modules/GameRPG/Controller/MasterController+PresentationReplay.swift:23-49`, `Modules/GameRPG/Controller/PlayerController+MapPhoto.swift:88-100,138-166` [verified].
2. **[Medium] Sharing a pin photo full screen uses `pin.isShown` instead of the audit-23 §6.1 predicate and ignores "pause sharing", so a monster's name, position and photo in a fogged room go to every player** — §6.2 — `Modules/MapRPG/Map/MapEditorOverlayLayer.swift:95`, `Modules/GameRPG/Table3D/GameTableModel+PinPhoto.swift:88` [verified].
3. **[Medium] A player chooses its companions' pin ids; the master never checks them for collisions, so a player can take over, move and later delete any pin on the map (e.g. a monster)** — §6.3 — `Modules/MapRPG/Controller/GameController+Pins.swift:12-65`, `Modules/CoreRPG/Model/TablePlayerModel.swift:43-78` [verified].
4. **[Medium] Folder items in a player's package skip `FileUrl.sanitizedForImport` since `a0d0a80d8`, and are force-saved into the game master's library** — §6.5 — `Modules/CoreRPG/Controllable/ImportControllable.swift:314-317` [verified].
5. **[Medium] A companion package can permanently merge over any of the game master's Characters (NPCs, table players)** — §6.4 — `Modules/GameRPG/Controller/MasterController+ValueMessages.swift:128-161` [verified]. Needs a user decision.
6. **[Medium] The master still accepts `isZoom` from player pin moves, although `isZoom` now means "the game master shares this photo with everyone"** — §5.3 — `Modules/MapRPG/Controller/GameController+Pins.swift:230-237` [verified].
7. **[Medium] A stale `isZoom` survives map switches and Save Game: a later share silently does nothing in 2D, and the 3D table pops the photo up on its own** — §5.4 — `Modules/MapRPG/Controller/GameController+Pins.swift:432-446`, `Modules/GameRPG/Table3D/GameTableModel+PinPhoto.swift:96-121` [traced].
8. **[Medium] When a player takes over a table player (or a companion/table player is switched off), the Character's pin is replaced by one with a new id: its position is lost, and a running battle keeps a ghost combatant** — §5.1 — `Modules/GameRPG/Controller/MasterController+Control.swift:99-119` [traced].
9. **[Medium] After a lost connection the map photo popover stays up and its Close button does nothing** — §5.2 — `Modules/GameRPG/Controller/PlayerControllerModel.swift:414`, `PlayerController+MapPhoto.swift:106-108` [verified].
10. **[Medium] SharePlay `join()` now runs off the main actor through an `@unchecked Sendable` wrapper and can overlap `reset()`'s `leave()` on the same `GroupSession`** — §3.1 — `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:385-411,499-511` [verified].

---

## 2. Quick wins (≤30 min)

- Ignore `isZoom` in player `.mapPin` updates on the master and on receivers; fix the stale comment (§5.3).
- Base `isShared` on `isPinVisibleToPlayers` and `isMapStreaming` at both full-screen sites (§6.2).
- Run `sanitizedForImport` on peer folder items before `admitPeerFolders` (§6.5).
- Clear `root.mapRoot.photoPopover.photo` wherever `mapPhoto.reset()` runs on the player side (§5.2).
- Cancel and clear `pendingRollTasks` in `DiceGameModel.reset()` (§3.7).
- In `LinkRegisterController.savePendingLinks`, subtract only the snapshot instead of `removeAll()` (§3.8).
- Move the `boldRange` update into the matched branch of the link renderer (§5.14).
- Gate `handleTableWeather` / `GameTableWeatherSync` on the same flag as the send side (§9.1).
- Store the two `AudioListenerCoordinator` tasks and cancel them in an isolated `deinit`, or put the block behind `#if DEBUG` (§3.6).
- Delete `ControlSharingView`, its snapshot test and its three catalog keys (§9.2).
- Add the Thai value for the MapRPG key "Photo" (§8.4).
- Delete `MapPhotoPresentation.presents(_:itemId:)`, `WeatherSceneConfiguration.isEmpty` and `MapPhotoMode: CaseIterable` (§9.3).

---

## 3. Concurrency

The four clean builds produced no Swift concurrency warnings. All new `@Observable` classes are `@MainActor`. No `DispatchQueue`, `Task.sleep(nanoseconds:)` or `nonisolated(unsafe)` was added, and no closure stored on a Table3D model captures a view. The findings below come from reading the code.

### 3.1 GroupSession `join()` moved off the main actor behind `@unchecked Sendable`
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+SessionLifecycle.swift:385-411` (join task), `:499-511` (`OffMainGroupSession`); races with `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:618-621` (`reset()` calls `groupSession?.leave()`)
- **What:** Commit `a913ce600` wraps the non-Sendable `GroupSession<RPGActivity>` in an `@unchecked Sendable` struct and calls `join()`/`leave()` from `@concurrent` functions. Meanwhile `reset()` calls `leave()` on the main actor without waiting for an in-flight join.
- **Why:** Cancelling the join task does not stop a `join()` already running on the concurrent executor. A reset during a join therefore runs `leave()` and `join()` at the same time on an object Apple does not mark thread-safe. That is the race CODE_AUDIT_18 §3.8 removed. The "the SharePlay service serializes them" claim in the doc comment is not documented by Apple.
- **Action:** Give the session one owner that runs `join()` and every `leave()` in order (a small serial actor, or a stored join task that `reset()` awaits before leaving). Drop the `@unchecked Sendable` wrapper. Keep the off-main execution only if the audio-session hang is reproducible.
- **Severity:** Medium [verified]

### 3.2 Table-player, pin-controller and companion updates fire unowned Tasks outside the ordered network queue
- **Location:** `Modules/GameRPG/Root/GameRoot+TablePlayers.swift:16-19, 31-34, 76-79`; compare `Modules/GameRPG/Root/GameRoot.swift:247-255` (`sharingControlActions` uses `scheduleNetworkAction`) and `:289-322` (`cancelOwnedTasks`)
- **What:** `updateTablePlayers`, `setPinController` and `updateCompanions` each start `Task { await masterController?.resetPlayers() }` (or `announceCompanions()`), hold the controller strongly, and are neither stored nor ordered.
- **Why:** A toggle made just before Stop Game still runs `resetPlayers` after `stop()`. A toggle made during `show()` can interleave its map sends with the reveal sequence that `scheduleNetworkAction` exists to keep in order.
- **Action:** Route all three through `scheduleNetworkAction`, like the sharing toggle, and capture the controller weakly.
- **Severity:** Low [verified]

### 3.3 Map-photo full-screen tasks race: an older `setCurrent` can finish last
- **Location:** `Modules/GameRPG/Controller/PlayerController+MapPhoto.swift:141-156`; `Modules/CoreRPG/Controllable/GameControllable.swift:201-209`
- **What:** Every `.fullScreen` apply starts an untracked task that awaits `makeCurrent` → `setCurrent(itemId:)`. The guard after the await skips `showFullScreen`, but the stale task has already inserted or moved its item to the front.
- **Why:** If the game master opens A and then quickly B full screen and A's fetch finishes last, the photo module's current item is A while the presentation is B. The viewer shows A. A task still in flight at game stop can insert into the reset game model.
- **Action:** Keep one stored `mapPhotoMakeCurrentTask` on `PlayerControllerModel`. Cancel it before starting the next and in `uninstallMapPhotoActions`, and re-check the presentation before mutating the module.
- **Severity:** Low [reasoned]

### 3.4 `replayMapPhoto` sends a stale item reveal after its awaits
- **Location:** `Modules/GameRPG/Controller/MasterController+MapPhoto.swift:47-71`; receiver `Modules/GameRPG/Controller/PlayerController+MapPhoto.swift:175-184`
- **What:** The presentation is read once. Several awaits follow (`shareMap`, `sendMapFollowUps`, `share`), and then the reveal of the old `presentation.itemId` is sent. The replay does not run through `scheduleNetworkAction`.
- **Why:** A player who becomes ready while the game master switches from photo A to B gets B's presentation and then A's reveal, which clears B's popover and shows A.
- **Action:** Re-read `mapPhoto` after the awaits and skip the reveal if it changed, or serialize the replay with the game master's photo broadcasts.
- **Severity:** Low [reasoned]

### 3.5 Relay de-duplication (`mayRelay`) is check-then-act across awaits
- **Location:** `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:97-114`; `Modules/GameRPG/Network/GameNetworkController+MasterDelegate.swift:42-60`; `Modules/GameRPG/Network/GameNetworkController+SharePlayDelegate.swift:95-100`
- **What:** `mayRelay` asks `messagePipeline.hasSeen` (an actor). The key is only recorded later in `received(...)`, after the relay's own awaits.
- **Why:** Two copies of one group event that are processed concurrently both pass `hasSeen` and are both relayed. This weakens the audit-23 §6.4 "a repeated event is not multiplied" fix.
- **Action:** Reserve the key atomically in the pipeline actor (check and insert in one call) before relaying.
- **Severity:** Low [reasoned]

### 3.6 Audio coordination diagnostics: unowned tasks that pile up per media-services reset
- **Location:** `Modules/AudioRPG/Audio/AudioListenerCoordinator.swift:20-50`; created at `Modules/AudioRPG/Controller/AudioController.swift:358` (every `initAudioSessionEngine`, including the media-services reset)
- **What:** Two `for await … NotificationCenter.notifications` loops are started in `init`. They are not stored and not cancelled, and they hold the coordinator strongly. They end only on the next notification after `self` is gone.
- **Why:** Every media-services reset leaves two more parked tasks and duplicate log lines. This is leftover bug-hunt logging (commit `ac4249ad7`) with no lifetime management.
- **Action:** Store the tasks and cancel them in an isolated `deinit` (as `WeatherTableEffect` does), or gate the block with `#if DEBUG` and remove it once the audio failure is found. Keep the `.error` "Track failed to load" observer.
- **Severity:** Low [verified]

### 3.7 `pendingRollTasks` is never cancelled at game teardown
- **Location:** `Modules/DiceRPG/Controller/GameController.swift:25-35, 99-100`; `Modules/DiceRPG/Controller/GameController+PlayerDice.swift:94-112`
- **What:** The per-dice-set delayed roll is cancelled only by the next roll of the same set. `reset()` does not touch it.
- **Why:** A roll started within 100 ms of Stop Game still runs `roll` + `shareRoll` after teardown, which CODE_AUDIT_Game §3.7 rules out.
- **Action:** Cancel and clear `pendingRollTasks` in `DiceGameModel.reset()`.
- **Severity:** Low [reasoned by agent, code path read]

### 3.8 Link-register save drops link edits made during the hydration retry
- **Location:** `Modules/CoreRPG/Links/LinkRegisterController.swift:172-185` (`savePendingLinks`), `:66-86` (re-hydration)
- **What:** `affectedIds` is read before `await setup(context:)?.value`, and `pendingAffectedSourceIds.removeAll()` runs after it. Ids that `register`/`deregister` inserted during the await are therefore cleared without being saved. This is new with the audit-23 §5.12 retry.
- **Why:** After a failed first hydration, link edits made during the retry stay stale on disk and in CloudKit until the item is edited again. The retry also appends stored rows over post-launch edits, so a link removed in the meantime can come back.
- **Action:** Subtract only the snapshot, or take it after the retry. When re-hydrating, skip stored rows for sources already pending.
- **Severity:** Low [verified ordering; the resurrection part is reasoned]

### 3.9 3D weather textures are decoded and uploaded synchronously on the main actor
- **Location:** `Modules/WeatherRPG/Weather3D/WeatherTableEffect.swift:311-332` (`WeatherTextures.texture`), called from `:194`, `:241`; driven by `Modules/GameRPG/Table3D/GameTableModel+Weather.swift:106-115`
- **What:** `Image.loadImage(name:)` and the synchronous `TextureResource(image:…)` run on the main actor the first time each of up to 10 textures is needed.
- **Why:** The first weather shown on a 3D table would hitch the UI and the RealityKit frame. This is latent while the feature is off (§9.1).
- **Action:** Preload the textures with the async `TextureResource` initializer when the table is created, or build the emitters after an async load that `removeWeather()` cancels.
- **Severity:** Low [verified]

---

## 4. API modernity

No deprecated APIs were added. In the changed code there are no legacy `Formatter`s, `String(format:)`, `replacingOccurrences`, `foregroundColor`, `cornerRadius()`, `tabItem`, `NavigationView`, `ObservableObject`/`@Published`, 1-parameter `onChange` or `onTapGesture`. The one new `GeometryReader` (`GameStatisticsDiceChart`) is Apple's documented `ChartProxy.plotFrame` pattern. There is no new `ID`/`URL` naming drift.

### 4.1 `AnyView` weather picture installed on a MapRPG model from a controller
- **Location:** `Modules/MapRPG/Model/MapPhotoPopoverModel.swift:60-62`; `Modules/GameRPG/Controller/PlayerController+MapPhoto.swift:8, 34-37`
- **What:** `itemPicture: (@MainActor (MapPhotoPopoverItem) -> AnyView)?` type-erases the animated weather viewer. `PlayerController` imports SwiftUI to install it.
- **Why:** CLAUDE.md says to avoid `AnyView`. It also loses view identity for an animated view inside a popover that re-renders while the map pans, and a controller now builds views.
- **Action:** Provide the picture from the GameRPG view layer (for example through an environment value set in `GameRootViewer`, a `@ViewBuilder` factory with an opaque result), and keep `PlayerController` free of SwiftUI.
- **Severity:** Low [verified]

### 4.2 Hard-coded spacing, padding, sizes and shape instances in new views
- **Location:**
  - `Modules/AudioRPG/Audio/MenuBarAudioPlayerView.swift:15, 22, 61, 74, 98, 115, 131, 180, 187, 248-250`
  - `Modules/GameRPG/GameViews/TablePlayers/TablePlayersView.swift:571`
  - `Modules/MapRPG/View/MapPinPhotoPopover.swift:34-42, 192-195`
  - `Modules/CoreRPG/Buttons/QuickEditorButtonView.swift:48` (`Rectangle()`), `:96-104`
  - `Modules/DiceRPG/Game/Editor/DiceQuickEditor.swift:78-93`
  - `Modules/GameRPG/GameViews/QuickDice/QuickDiceToggleField.swift:17, 24`
  - `Modules/GameRPG/GameViews/OverlayGameLayout.swift:97, 151-160`
- **What:** The new views use literal stack spacing and padding (2, 4, 6, 8, 12, 20), fixed sizes (the 320-wide menu bar player, the 280/360/480 `photoSide`, the 300/420 quick editor), unnamed theme opacities (0.14, 0.35, 0.5) and `Rectangle()` where `.rect` exists. On macOS the quick-dice toggle adds the 4 pt bottom inset twice (`quickDiceBottomInset` plus `valueFor(macOS: 4)`), and the trailing padding has an unexplained `+ 2` in two branches.
- **Why:** CLAUDE.md asks for no hard-coded padding or spacing and for static member lookup. The fixed photo side does not scale with Dynamic Type.
- **Action:** Name the quick-dice insets once in `GameScreenModel`. Use `@ScaledMetric` for `photoSide` and the menu bar control sizes. Name the theme opacities on `ResolvedAppTheme`. Use `.contentShape(.rect)`.
- **Severity:** Low [verified]

---

## 5. Bugs / logic errors

### 5.1 Pin handover between a table player, a joining player and a companion loses position and leaves a ghost combatant
- **Location:** `Modules/GameRPG/Controller/MasterController+Control.swift:99-119`; `Modules/MapRPG/Controller/GameController+Pins.swift:43-65, 129-137`; `Modules/MapRPG/BattleRound/BattleRoundModel+Roster.swift:43-75`; `Modules/MapRPG/BattleRound/BattleRoundModel+Turns.swift:24-38`
- **What:** The table player's pin (id T) and the joining player's pin (id P) are different pins for the same Character. `resetPlayerPins` deletes T and creates P, which `placePlayerPinsInFirstRoom` puts into the first room. Nothing carries the location over or re-keys the battle roster.
- **Why:** If a player joins mid-battle with the Character of table player T, T's pin vanishes but its combatant, turn entry and possibly `activeAttackerId` remain. They point to a missing pin, so health and highlight no-op. P stands in the first room with `healthPercent` nil and no turn. The same happens when P leaves, when the game master disables or removes a table player, and when a player removes a companion.
- **Action:** When the pin for a Character moves from one id to another, copy location, map and flags from the old pin and re-key the combatant (pin id and `retainedPlayerCombatants`). Otherwise drop the combatant explicitly and broadcast the change.
- **Severity:** Medium [traced]

### 5.2 After a lost connection the map photo popover is stuck and Close does nothing
- **Location:** `Modules/GameRPG/Controller/PlayerControllerModel.swift:414` (`mapPhoto.reset()` in `resetForLostConnection`); `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:36-40`; `Modules/GameRPG/Controller/PlayerController+MapPhoto.swift:106-108, 125-129`
- **What:** The lost-connection reset clears `mapPhoto` but not `root.mapRoot.photoPopover.photo`, which only `uninstallMapPhotoActions` and `applyMapPhotoMode` clear.
- **Why:** The popover stays on the 2D map and the 3D table. Close and Escape call `requestMapPhotoMode`, which returns at `guard let presentation` (line 107). After reconnecting, nothing clears it until the next photo presentation or the end of the game.
- **Action:** Clear the popover wherever the player resets `mapPhoto`, or have `requestMapPhotoMode` call `applyMapPhotoMode()` (which clears it) when there is no presentation.
- **Severity:** Medium [verified]

### 5.3 The master still accepts `isZoom` from player pin updates
- **Location:** `Modules/MapRPG/Controller/GameController+Pins.swift:230-237`; semantics changed by `5058f597d` (`setPinPhotoShown`, `:431-445`)
- **What:** `updatePin(itemId:data:playerId:)` copies `incomingPin.isZoom` for any visible pin ("Zoom and highlight are the only shared interactions…"). Since the photo popover replaced zoom, `isZoom` means "the game master shows this pin's photo to everyone", and only `setPinPhotoShown` should write it.
- **Why:** Two cases:
  - A player's own pin move carries its local `isZoom` with a newer timestamp. A stale `false` closes the game master's shared photo. A stale `true` reopens it or leaves two pins flagged, which breaks "one photo at a time".
  - An older build (with the zoom toggle) or a modified client can open a photo popover on every device.
- **Action:** On the master and on receivers, keep the current `isZoom` for non-master senders and leave it out of the "changed" check. Fix the comment. Add a test that a player pin move cannot change `isZoom`.
- **Severity:** Medium [verified]

### 5.4 A stale `isZoom` makes the next share fail silently in 2D and pops the photo up on 3D tables
- **Location:** `Modules/MapRPG/Controller/GameController+Pins.swift:432-446`; `Modules/MapRPG/Map/MapEditorActionRouter.swift:73-90, 264-268`; `Modules/GameRPG/Table3D/GameTableModel+MapSync.swift:84-86`; `Modules/GameRPG/Table3D/GameTableModel+PinPhoto.swift:96-121`; `Modules/MapRPG/View/MapPinPhotoPopover.swift:25-31`
- **What:** `isZoom` stays `true` in the game copy of a map after the map is left or the pin is hidden, and Save Game exports it (it is `Codable`; Core Data does not store it). 2D reacts only to a change of the flag. The 3D table resets `sharedPhotoPinIds` on every map change and treats any flagged pin on first sync as a new share.
- **Why:** The game master shares a photo, switches maps and comes back. In 2D, double-tapping that pin calls `setPinPhotoShown(shown: true)`, nothing changes, and nothing is broadcast, so players never see the photo while the game master thinks it is shared. On every 3D table the popover opens as soon as the map loads, or when a fogged pin's room is revealed.
- **Action:** Clear `isZoom` on all pins when a map stops being shown and when a pin is hidden. Strip it in `saveAll`/export, as was done for `healthPercent`. Use the same first-sync rule in 2D and 3D (see §9.4).
- **Severity:** Medium [traced; the Save Game path is reasoned]

### 5.5 Companions are not delivered in several cases, and the master shows "Waiting for the Character" with no retry
- **Location:** `Modules/GameRPG/Controller/PlayerController+Character.swift:20-28, 36-64, 76-96`; `Modules/GameRPG/Controller/PlayerController+Value.swift:46-53`; `Modules/GameRPG/Root/GameRoot+TablePlayers.swift:47-57, 65-80`; `Modules/GameRPG/Controller/MasterController+ValueMessages.swift:150-157`
- **What:** Companion references go out only inside `sendCharacter`, which has several gaps:
  - It returns early when the player has no own Character or `mayAnnounceCharacter` refuses it.
  - Package requests are answered only with an own `characterId`.
  - `announceCompanions` does nothing while a send task is running, and that task then latches `hasSendPlayer = true` with the old companion list.
  - A failed companion import on the master sends no `.failed` back.
  - `storeCompanions` needs `selectedCharacter`, so companions of a player without a Character are not saved.
- **Why:** A player who adds a companion while the join announcement is still running, or who joined without a Character, leaves that companion as "Waiting for the Character" on the master with no pin, until the next edit or reconnect.
- **Action:** Send and answer for companion references independently of the own Character. Track a "dirty" generation that `announceCompanions` bumps, and re-run the send if it changed while running. Report failed companion imports. Alternatively, hide the Companions panel for a player without a Character.
- **Severity:** Medium [traced; the "join without a Character" precondition is reasoned]

### 5.6 A shared pin-photo full screen sends no reveal, so a player without the photo stays on the map
- **Location:** `Modules/GameRPG/Controller/PlayerController+MapPhoto.swift:62-68, 73-87`; `Modules/GameRPG/Controller/PlayerController+Photo.swift:42-56`
- **What:** The game master's shared full screen sends only `.photoPresentation`. On a player, `makeCurrent` fails when the photo is not held, and the later `.store` of that photo never checks for a waiting presentation. The late-joiner replay does send a reveal, so the two paths behave differently.
- **Why:** A player whose pin-photo request is still in flight, or failed, does not see what everyone else sees.
- **Action:** Send the item's reveal after the presentation, as the replay does, or apply a waiting presentation when the photo arrives.
- **Severity:** Low [verified]

### 5.7 visionOS opens the photo window before the photo is current or held
- **Location:** `Modules/GameRPG/GameViews/GameRootViewer.swift:107-114`; `Modules/GameRPG/Model/MapPhotoPresentation.swift:145-150`
- **What:** `fullScreenRequest` is incremented in `applyMaster`/`presentLocal`, before `makeCurrent` succeeds. The `onChange` then opens `imageSpaceViewer` for `presentation.itemId`.
- **Why:** A presentation for a photo the player does not hold opens an empty or failing spatial window.
- **Action:** Increment the request in `showFullScreen(_:)`, after the item is current.
- **Severity:** Low [verified]

### 5.8 First-room placement stacks new pins on existing ones and ignores whether the room is revealed
- **Location:** `Modules/MapRPG/Controller/GameController+Pins.swift:153-176`; `Modules/MapRPG/Map/MapPinPlacement.swift:50-67`
- **What:** `placePlayerPinsInFirstRoom` cascades only the pins it is placing now, always starting at the room's `leftCenter`. It takes the first room with coordinates, shown or not, and the diagonal cascade has no bound.
- **Why:** A third player, a table player or a companion added later lands exactly on the first player's unmoved pin. With many pins (8 companions per player plus table players) the cascade leaves the room or the map. Player pins appear inside a hidden first room.
- **Action:** Skip occupied spots, wrap rows inside the room's bounds, and prefer the first shown room.
- **Severity:** Low [verified]

### 5.9 Table players that fail to decode become an empty list stamped "now"
- **Location:** `Modules/AdventureRPG/Controller/DataController.swift:34, 60-62`; `Modules/CoreRPG/CRDT/CRDT.swift:49-54`; `Modules/AdventureRPG/Model/AdventureModel.swift:116-118`
- **What:** `CRDT(string:defaultValue:)` falls back to a fresh `LWWRegister([])` with the current time and a random actor. The epoch-stamped `noTablePlayers` default applies only when the attribute is nil.
- **Why:** A device that cannot decode the stored JSON (corrupt, or a future `TablePlayerModel` shape) writes "empty, now" on its next save of that adventure. CloudKit carries it to every device, where it wins over the real list.
- **Action:** On a decode failure use `noTablePlayers` and keep the raw string instead of writing it back.
- **Severity:** Low [verified]

### 5.10 visionOS guest-seat dice decide "game master" by display name
- **Location:** `Modules/GameRPG/Table3D/GameTableView+VisionOS.swift:488-500`; `Modules/GameRPG/Root/GameRootModel.swift:368-385`; `Modules/GameRPG/Table3D/TableGuestDice.swift:44-62`
- **What:** `isGameMaster: dice.name == masterName`. Guests are matched through `tableGuestNames` by name, although `tableGuests` is keyed by sender id.
- **Why:** A player named like the game master gets the game master's dice-visibility rule. Two guests with the same name share one dice slot.
- **Action:** Carry the sender id on shared rolls and match the game master and guests by id.
- **Severity:** Low [verified]

### 5.11 iCloud folder Sync checks game mode only before its suspensions [INCOMPLETE FIX of audit 23 §5.7]
- **Location:** `Modules/CoreRPG/Controllable/CloudScanController.swift:61-104` (guard at :64, awaits at :66-71, writes from :91); `Modules/AdventureRPG/Root/AdventureRootModel.swift:339-344`
- **What:** `apply` checks `isGameMode` once, then awaits hashing and a re-scan before it writes.
- **Why:** A game started meanwhile (another Mac window, or joining) produces the half-synced library §5.7 describes: inserts are force-saved, while folder repairs and removals go to game memory only.
- **Action:** Re-check `isGameMode` after the last await, or make game start refuse or wait while a mutation token is held.
- **Severity:** Low [reasoned]

### 5.12 The bookmark store still overwrites an undecodable entry [INCOMPLETE FIX of audit 23 §5.5]
- **Location:** `Modules/CoreRPG/Files/FileBookmarkController.swift:72-95, 108-114`; `Modules/CoreRPG/Files/FileDataController.swift:84-91`
- **What:** The bookmark store is one wrapper row per id. When that row fails to decode, `read(id:)` returns nil, the bookmarks start empty, and the next `save()` writes a fresh row with the same id. `kept` drops the undecodable original.
- **Why:** The "keep undecodable entries" fix does not protect this store. A changed `Bookmarks` shape still loses every `.other`/`.icloud` bookmark of the module on the next pick or removal.
- **Action:** Treat an id in `undecodable` as a failed fetch (not marked fetched, never saved over), or back up the raw row first.
- **Severity:** Low [traced]

### 5.13 Toggling a link still uses first-end pairing; the renderer uses nesting depth [INCOMPLETE FIX of audit 23 §5.1]
- **Location:** `Modules/CoreRPG/LinkRenderer/String+Link.swift:29-50` (`findEndRange`) vs `Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift:244-261` (`matchingEndRange`)
- **What:** `toggleLink` pairs markers with a first-end heuristic and returns nil when the inserted text holds a lone "➡️".
- **Why:** Such a link cannot be collapsed: each tap inserts the expansion again, and the renderer shows the raw markers. No crash.
- **Action:** Use one depth-based pairing helper for both sites, and add a toggle test with a lone marker.
- **Severity:** Low [reasoned]

### 5.14 A lone "➡️" inside bold text disappears from the rendered text [NEW from `15d8b4977`]
- **Location:** `Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift:155-185` (bold reset at :159-161, unbalanced branch at :182-185), `:195-201`
- **What:** `boldRange` is moved past the marker before the match is known. The unbalanced branch only sets `lastIndex`, so the bold end appends from after the marker.
- **Why:** "**a ➡️ b**" renders without the marker. Display only; the stored text is unchanged.
- **Action:** Move the `boldRange` update into the matched branch.
- **Severity:** Low [traced]

---

## 6. Security

Players are trusted for content (the peer import policy gaps in CODE_AUDIT_Folder §6.1/§6.2 are won't-fix). Two rules still apply, and these findings break them: the master decides what players may see (fog, hidden pins, pause sharing), and a player only controls pins it owns.

The following were checked and hold:

- `.photoPresentation` and `.tableWeather` are master-only, and every player handler checks `sender.isMaster`.
- Observer pin moves go through `isControlled`.
- Sender ids are bound to their connection.
- `pinControllers` and `tablePlayers` are cleared in `stop()`.

### 6.1 A game master's private photo of a hidden pin leaks through the late-joiner replay and the external screen
- **Location:** `Modules/GameRPG/Controller/PlayerController+MapPhoto.swift:88-100` (`presentLocal`), `:138-166` (`makeCurrent` + `showFullScreen` → `setGameUpdateType(.photo)`, `presentPhoto`); `Modules/GameRPG/Controller/MasterController+MapPhoto.swift:47-54` (`replayMapPhoto` returns `false` for `isLocal`); `Modules/GameRPG/Controller/MasterController+PresentationReplay.swift:23-49` (`.photo` case reveals `photoRoot…currentItemId`); `Modules/GameRPG/ExternalScreen/ExternalGameRootView.swift:18-19`; `Modules/CoreRPG/Controllable/GameControllable.swift:30-32, 201-209`
- **What:** The "local" path for a hidden pin's photo only skips the broadcast. It still makes that photo the photo module's current item (`currentItemId` is `gameItems.first`) and sets the co-located controller's `gameUpdateType` to `.photo`. That is the same state the replay and the external display read.
- **Why:**
  - The game master opens a hidden monster's photo full screen. `replayMapPhoto` declines because `isLocal` is true, so the regular replay runs and sends a `.reveal` of the hidden photo to every player who joins or reconnects. The player then requests and receives the package.
  - The external AirPlay/TV screen renders `GameRootViewer` from the same `PlayerController`, so it shows the photo full screen to the table.
  - After "Show on Map", the external map shows it in the popover.
- **Action:** Keep game-master-only presentations out of the shared screen state: show them in a separate local viewer, or exclude `isLocal` from `replayCurrentPresentation` (replay the map instead) and have the external screen ignore `isLocal` presentations. Add a test: local photo open → peer `ready(for:)` → no photo reveal.
- **Severity:** High [verified; external screen traced]

### 6.2 Shared pin-photo full screen bypasses the fog predicate and "pause sharing"
- **Location:** `Modules/MapRPG/Map/MapEditorOverlayLayer.swift:88-98` (line 95); `Modules/GameRPG/Table3D/GameTableModel+PinPhoto.swift:86-91` (line 88); double-tap sites `Modules/MapRPG/Map/MapEditorActionRouter.swift:266`, `GameTableModel+PinPhoto.swift:25`; payload `Modules/MapRPG/Model/MapPhotoPopoverModel.swift:89-101`; broadcast `Modules/GameRPG/Root/GameRoot.swift:276-281`, `MasterController+MapPhoto.swift:56-69`
- **What:** `isShared = isGameMaster && pin.isShown` skips audit-23 §6.1's `MapModel.isPinVisibleToPlayers`. `scheduleMapPhotoBroadcast` does not check `isMapStreaming`. The presentation carries `title: pin.name` and `anchor: pin.location`.
- **Why:** The game master opens the popover of a shown monster inside a fogged room and taps Full Screen. Every player gets the monster's name and exact position, which `mapState` and the map package deliberately withhold. Players who already hold the photo see it, and late joiners get it through the replay. With "Share Map" paused, a newly added pin's photo, name and position go out the same way. This contradicts audit-23 §13's "one predicate" claim.
- **Action:** Base `isShared` and both double-tap sites on `currentMap.isPinVisibleToPlayers(pin)` and `isMapStreaming`; otherwise use the local path (once §6.1 is fixed). Optionally have the master refuse a presentation whose anchor pin is not visible to players.
- **Severity:** Medium [verified]

### 6.3 Companion pin ids are chosen by the player and never checked for collisions
- **Location:** `Modules/GameRPG/Root/GameRootModel.swift:117-122`; `Modules/CoreRPG/Model/TablePlayerModel.swift:43-66` (`pinPlayers` skips only roster ids), `:69-78` (`companionOwners`), `:96-106` (`claimant`); `Modules/MapRPG/Controller/GameController+Pins.swift:12-40` (`setPlayerPin` applies player metadata to *any* pin with that id on every live map), `:43-65` (`resetPlayerPins` removes any `isPlayer` pin not in the roster); `Modules/GameRPG/Controller/MasterController+Control.swift:99-115`
- **What:** A companion's `TablePlayerModel.id` comes from the player's message and becomes the pin id. Nothing checks it against existing pins, table players or other players' companions.
- **Why:** Players learn visible pin ids from `mapState` and companion ids from the roster echo.
  - **Monster pin:** a companion declared with a monster pin's id turns that pin into a player pin (`isPlayer = true`, new name and photo), and `companionOwners` gives the player control to move it. When the companion is removed, `resetPlayerPins` deletes the monster from every live map, and `saveAll` drops it too because it strips player pins.
  - **Other pins:** the same works against a table player's id or another player's companion, whichever comes first in the roster.
  - **Side effects:** `ForEach(companions)` gets duplicate ids, and the game master's panel shows a table player as "Pin on the map" without a pin.
- **Action:** On the master, derive companion pin ids itself (from owner id and companion id), or refuse ids that clash with roster ids, table players, other companions or any pin on a live map. `setPlayerPin` must only update pins that already are player pins, and `resetPlayerPins` must only remove those.
- **Severity:** Medium (needs a modified client) [verified]

### 6.4 A companion package can merge over any of the game master's Characters
- **Location:** `Modules/GameRPG/Controller/MasterController+ValueMessages.swift:128-161` (`companionCharacterId`, `handleCompanionStore`); `Modules/CoreRPG/Controllable/ImportControllable.swift:73-83` (`admit` with `primaryItemId`); `Modules/CharacterRPG/Controller/GameController+Sync.swift:54-58` (`forceSave: true`); `Modules/AdventureRPG/Controller/ExportController.swift:72-76`
- **What:** `companionCharacterId` refuses only Characters a roster player plays or that are bound to a sender. The import then admits the companion as the primary item even though it already exists on the master, and saves it with `forceSave`.
- **Why:** A player who names a game master NPC or table-player Character as a companion merges its copy into the game master's library permanently, up to 8 per player. This can happen innocently, because adventure exports now include table-player Characters, so a player may hold an older copy. The companion also takes the table player's pin (companions rank first). This extends the CODE_AUDIT_17 §6.1 won't-fix ("a player's own Character") to arbitrary Characters.
- **Action (needs a decision):** limit the primary-item override to Characters this sender introduced; or exclude the adventure's table players and linked Characters; or ask the game master to confirm.
- **Severity:** Medium [verified]

### 6.5 Peer folder items skip `FileUrl.sanitizedForImport` [REGRESSION `a0d0a80d8`]
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:314-317` (folders branch off before `prepareDecodedItem`), `:531-543` (the only `sanitizedForImport` call, line 534), `:545-558` (`admitPeerFolders`), `:365-370`; deletion `Modules/CoreRPG/Controllable/ItemControllable.swift:173, 206-215`
- **What:** Since the folder-dedup commit, a folder item in a player's package goes to `admitPeerFolders` and `applyImportedItem` without `prepareDecodedItem`, the step that strips `..` segments, moves non-public URLs into app storage and checks remote hosts.
- **Why:** A crafted folder with a traversal or private-host `fileUrl` is force-saved into the game master's library. Deleting that folder with its files later hands the raw `fileUrl` to `FileUrlDataController.delete`. CODE_AUDIT_15 §5.1 closed this class of bug for every other item type.
- **Action:** Sanitize folder items (the `fileUrl` part of `prepareDecodedItem`) before they are held for admission.
- **Severity:** Medium [verified skip and delete path; not traced: whether file resolution at delete time re-sanitizes]

### 6.6 New peer-supplied fields have weaker size bounds
- **Location:** `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:319-323`; `Modules/GameRPG/Controller/MasterController+MapMessages.swift:126-150`; `Modules/GameRPG/Model/GameNetworkModel+Shape.swift:57-70`; `Modules/GameRPG/Model/GameNetworkModel.swift:63-64`; `Modules/CoreRPG/Model/GameModel.swift:124`
- **What:** An observer's `(.update, .mapPin, .map)` is not a group event, so the 256 KiB group-event cap and `acceptsEventTimestamp` do not apply; it is decoded on the main actor up to the 100 MB frame limit. `companions` is decoded in full before it is cut to 8.
- **Why:** A connected observer or player can make the master decode very large payloads on the main actor with every message.
- **Action:** Apply the group-event cap and timestamp check to observer pin moves. Reject a roster entry with more than `maximumCompanions` before decoding it in full.
- **Severity:** Low [verified]

---

## 7. Performance

### 7.1 The plain spatial photo window does foreground work every frame
- **Location:** `Modules/PhotoRPG/Space/ImagePresentationView.swift:64-68, 148-153, 189-205`
- **What:** The `Foreground == EmptyView` variant still creates the attachment, and `syncPresentation` calls `placeForeground` on every `SceneEvents.Update`, which computes `visualBounds(relativeTo: nil)`.
- **Why:** The normal photo window (no weather) pays for a bounds traversal at about 90 Hz.
- **Action:** Skip the attachment and `placeForeground` when there is no foreground, and place it only when the bounds change.
- **Severity:** Low [verified]

### 7.2 Peer folder admission does a lookup per candidate inside a search
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:546-558` (`admitPeerFolders`), `:993-1015` (`peerFolder`)
- **What:** `peerFolder` (an `itemSync` lookup) runs inside `folders.first(where:)` for every candidate.
- **Why:** O(n²) lookups per peer package, bounded by the 256-item cap. Cheap to remove.
- **Action:** Build the `(item, folder)` pairs once (see §9.11).
- **Severity:** Low [reasoned]

The 3D weather's per-map work while the feature is off is covered in §9.1, and the first-use texture decode in §3.9.

---

## 8. SwiftUI / UI

The new views are in good shape against the SwiftUI checklist:

- `@State` is private.
- `@Observable` models are owned with `@State`.
- `ForEach` ids are stable (except the duplicate-id case caused by §6.3).
- Every `.animation` has a `value:`.
- Reduce Motion is honoured, including the weather layers, which pause their `TimelineView`s, and the 3D lightning, which honours Dim Flashing Lights.
- Every new `Text` passes `bundle: .module`.
- Icon-only buttons carry text labels.

### 8.1 `TablePlayersView` fixes its role and model at `init`
- **Location:** `Modules/GameRPG/GameViews/TablePlayers/TablePlayersView.swift:17-22`
- **What:** `isMaster` and the `@State` model (table players or companions) are chosen once from `root` in `init`.
- **Why:** This works because the popover rebuilds the view on each presentation, but it is an undocumented one-time seed: reusing the view elsewhere (a window, a persistent panel) would keep the wrong list after a role change.
- **Action:** Document the one-time seed, or key the view with `.id(isMaster)` at the call site.
- **Severity:** Low [verified]

### 8.2 Two empty-thumbnail looks with a literal corner radius
- **Location:** `Modules/CharacterRPG/View/PlayerAvatarView.swift:18-24`; `Modules/CoreRPG/LGViews/ThumbnailRowEmptyView.swift:14-24`; `Modules/AudioRPG/Audio/MenuBarAudioPlayerView.swift:250`
- **What:** Both placeholders, added in this range, draw an SF Symbol in an `imageHeight` square with `cornerRadius: 12`. The menu bar row uses a literal radius of 6.
- **Why:** The two looks will drift apart, and the radius bypasses `ResolvedAppTheme.elementCornerRadius` (the rule applied in Since_3.0.1 §8.1).
- **Action:** Give `ThumbnailRowEmptyView` a symbol parameter, use it from `PlayerAvatarView`, and use the theme radius.
- **Severity:** Low [verified]

### 8.3 A weather popover without a title gets an empty accessibility label
- **Location:** `Modules/MapRPG/View/MapPinPhotoPopover.swift:80-95`
- **What:** For a weather, `name` falls back to `""` when `item.title` is nil, and the picture gets `.accessibilityLabel(Text(verbatim: ""))`.
- **Why:** VoiceOver announces nothing for the popover's main content when the weather has no name, or when the title did not arrive.
- **Action:** Fall back to the localized word "Weather".
- **Severity:** Low [verified]

### 8.4 A new MapRPG key has no Thai translation
- **Location:** `Modules/MapRPG/View/MapPinPhotoPopover.swift:90` (`Text("Photo", bundle: .module)`); `Modules/MapRPG/Resources/Localizable.xcstrings` key "Photo"
- **What:** The key has `de` but no `th`. All other new single-line keys that were checked have both. Multi-line strings were not checked.
- **Why:** Thai VoiceOver users hear English.
- **Action:** Add the `th` value.
- **Severity:** Low [verified]

---

## 9. Dead code / duplication / refactor

No new TODO/FIXME/`#if false`, commented-out code, `print` calls, or log lines that put user content at `.public` were added. The removed zoom feature (`MapPinButtonType.zoom` and its strings) was removed cleanly.

### 9.1 3D table weather is switched off only on the game master's send path
- **Location:** flag `Modules/GameRPG/Controller/MasterController+TableWeather.swift:14-16` (checked at :20, :31, :50); still active: `Modules/GameRPG/Table3D/GameTableModel.swift:107-109, 244`, `GameTableModel+Weather.swift:13-129`, `GameTableView+PlatformFlat.swift:62`, `GameTableView+VisionOS.swift:299`, `Modules/GameRPG/Controller/PlayerController+Weather.swift:16-20`, `PlayerController+TableWeather.swift:12-35`, `GameTableToolbar.swift:29-66`, `Modules/CoreRPG/Model/RPGMessageActionType.swift:31-34`, `Modules/WeatherRPG/Weather3D/*` (~610 lines), `Modules/WeatherRPG/Root/WeatherRootModel.swift:203-209`; misplaced reset `PlayerController+MapPhoto.swift:46-47`
- **What:** `isTableWeatherEnabled = false` gates only `showTableWeather`, `clearTableWeather` and `replayTableWeather`. Everything else still runs:
  - every table still creates a `WeatherTableEffect`;
  - `GameTableWeatherSync` still runs on every map, size and rotation change;
  - players still decode and apply `.update/.tableWeather`;
  - the "Clear Weather" button and the wire case still ship.
- **Why:** About 1,000 lines (plus tests) ship and cost per-map work but can never show anything, by design. A master on a build from `1a737a455` to `0955ea6ea`, where the feature was on, can still put the effect on players' tables, and nobody can clear it.
- **Action:** Move the flag to one shared GameRPG feature constant and gate the send, receive and render sides with it (`attachWeather`, `GameTableWeatherSync`, `handleTableWeather`, the toolbar button, the tests' `.enabled(if:)`). Or move the slice to a branch and keep wire case 18 reserved. Move `tableWeather.reset()` out of `uninstallMapPhotoActions()` into the game-end reset.
- **Severity:** Medium [verified]

### 9.2 `ControlSharingView` is dead since the Players panel replaced it
- **Location:** `Modules/CoreRPG/Buttons/ControlSharingView.swift:54-182, 188-198`; `Tests/CoreRPGSnapshotTests/CoreRPGDynamicPreviewSnapshotTests.swift:12-23`
- **What:** Its only production caller (`IOSGameOverlayControlField`) now uses `TablePlayersButton`. Only its preview and a generated snapshot test use it. Its catalog keys "Share", "Sharing Controls" and "Toggle sharing filter options" remain.
- **Why:** About 130 lines of dead public UI, and a snapshot baseline for code the app never runs.
- **Action:** Delete the view, its two private modifiers, the snapshot test and its reference image, and the keys. Keep `SharingControlActions`, `SharingControlModel` and the environment key.
- **Severity:** Low [verified]

### 9.3 Smaller unused or test-only members added in this range
- **Location:** `Modules/GameRPG/Model/MapPhotoPresentation.swift:126-129` (`presents`, no caller), `:80-84` (`popover`, tests only), `:12` (`CaseIterable` unused); `Modules/WeatherRPG/Weather3D/WeatherSceneConfiguration.swift:125-128` (`isEmpty`); `Modules/WeatherRPG/Weather3D/WeatherTableEffect.swift:38-41` (`isShowing`, tests only); `Modules/GameRPG/GameViews/IOSGameDiceToggleButtonField.swift:8-21` (generic wrapper now used once)
- **What:** API surface with no production caller.
- **Why:** It implies behaviour nothing relies on.
- **Action:** Delete or inline it.
- **Severity:** Low [verified]

### 9.4 Pin-photo share rules are written twice, for 2D and 3D
- **Location:** `Modules/MapRPG/Map/MapEditorActionRouter.swift:73-89, 261-274` vs `Modules/GameRPG/Table3D/GameTableModel+PinPhoto.swift:18-41, 69-75, 86-91`; `Modules/MapRPG/Map/MapEditorOverlayLayer.swift:88-99`
- **What:** The same rules appear on both sides: "show = photoPinId != pinId; share if isShown || isZoom", "clear the flag on dismiss" and "isShared = isGameMaster && isShown". So does the first-sync handling of `isZoom`, which already differs (§5.4).
- **Why:** This is the root of the drift behind §5.4 and §6.2: a fix has to land twice.
- **Action:** Put the decisions in one pure MapRPG type (next to `MapPinPhotoSharing`) that returns local/shared/flag changes for a double tap, a dismiss, a full screen and a first sync. Have both surfaces apply its result, and unit-test it.
- **Severity:** Medium [verified]

### 9.5 Three copies of the 3D table popover anchor/projection plumbing
- **Location:**
  - `Modules/GameRPG/Table3D/GameTableModel+PinPhoto.swift:134-187` vs `GameTableModel+PinSelection.swift:38-84`
  - register/height/detach triples in `GameTableModel+PinPhoto.swift:149-161`, `GameTableModel+MapPhoto.swift:68-80` and `GameTableModel+PinThumbnails.swift:91-105`
  - `Modules/GameRPG/Table3D/GamePinActionMenu.swift:15-89, 94-194`
  - `GameTableView+VisionOS.swift:83-114, 334-335`
- **What:** The pin menu, pin photo and map photo popovers each repeat the same pieces: anchor show/hide, a projected `TablePinMenuSource` with `differsVisibly`, register/height/detach, and the attachment view with the same `onGeometryChange` height report. `mapPhotoSource` stores a photo id in `TablePinMenuSource.pinId`.
- **Why:** About 200 near-identical lines. Each new popover adds another copy, and the type name no longer fits what it holds.
- **Action:** Introduce one `TablePopover` (anchor, source, attachment id) keyed by kind, with one register/update/detach path and one generic attachment view. Rename the source type to `TablePopoverSource(id:frame:)`.
- **Severity:** Medium [verified]

### 9.6 MapPopover wrappers and the one-point source rectangle are copied
- **Location:** `Modules/MapRPG/Controller/ViewController.swift:188-275` (four new `game{Pin,Map}Photo{Popover,Attachment}`); `Modules/MapRPG/Map/MapEditorOverlayLayer.swift:199-216, 247-264, 280`; `Modules/GameRPG/Table3D/GameTableModel+MapPhoto.swift:96-99`
- **What:** Each wrapper rebuilds `MapPopover` with the same viewport, environment and frame. The "1×1 rect around a point" helper is written twice.
- **Why:** Boilerplate that grows with every popover kind.
- **Action:** Use one generic popover entry point and one attachment entry point, and reuse `MapPhotoPopoverSource.rectangle`.
- **Severity:** Low [verified]

### 9.7 The "newer master change" ordering is implemented twice
- **Location:** `Modules/GameRPG/Model/MapPhotoPresentation.swift:56-59, 73, 89-101` vs `Modules/GameRPG/Model/TableWeather.swift:30-33, 39, 50-61`; counters `Modules/GameRPG/Controller/MasterController.swift:42-46, 140-150`
- **What:** Each state has an identical private `MasterOrder` (session id plus sequence), the same `applyMaster` guard and its own counter.
- **Why:** A restart or session fix has to be made twice.
- **Action:** Extract one `MasterSequenceGate` value and one sequence source keyed by presentation kind.
- **Severity:** Low [verified]

### 9.8 The macOS menu bar player copies the playlist and transport decisions
- **Location:** `Modules/AudioRPG/Audio/MenuBarAudioPlayerView.swift:79-84, 203-208, 229-235` vs `Modules/AudioRPG/Audio/AudioPlayerView.swift:130-134` and `Modules/AudioRPG/Audio/PlayListView.swift:24-28, 47-52`
- **What:** The view-level rules now live in three views (plus `AudioPlayPauseButton` and `SharingActionView`): "in a game send `requestPlay`, else toggle" and "deleting the playing item in a game sends `requestPlay` first". Durations are formatted two ways.
- **Why:** This is view logic against CLAUDE.md's "logic into view models", and a game-mode audio fix has to be made in every copy.
- **Action:** Add `playOrRequest(id:…)` and `remove(id:…)` to `AudioController` (or a small `AudioPlaybackActions`), call them from all views, and use one duration format.
- **Severity:** Medium [verified]

### 9.9 `TablePlayersView` repeats its row layout three times and copies the Logs window sections
- **Location:** `Modules/GameRPG/GameViews/TablePlayers/TablePlayersView.swift:239-286, 339-378, 382-425`; `:154-156` vs `Modules/GameRPG/GameViews/LogMessageList.swift:19-21`; `:227-236` vs `Modules/CoreRPG/Buttons/SendControlView.swift:16-20`
- **What:** Three row types each resolve the name and status and build the same avatar + name + status + toggle row. The master list re-composes the Logs window's three sections. "Toggle sharing for a player" is written per surface.
- **Why:** Layout and status rules drift between the rows, and changes to the Logs sections need two edits.
- **Action:** Use one row view with slots for the per-kind extras and one `LogSections` view for both surfaces. Move `setSharing` next to `sharingControlActions` in `GameRoot`.
- **Severity:** Low [verified]

### 9.10 The companion handshake copies the player-Character handshake
- **Location:** `Modules/GameRPG/Controller/MasterController+ValueMessages.swift:143-159` vs `:73-104`; `Modules/GameRPG/Controller/PlayerController+Character.swift:82-96` vs `:50-60`
- **What:** The steps (version compare → peer import policy → `updatePlayer` → `recordPeerImport` → log) are written twice, and the copies already differ: companions send no `.failed` reply.
- **Why:** Two copies of a security-relevant import path. The difference feeds §5.5 and §6.4.
- **Action:** Extract one `importPeerCharacter` and one `shareCharacterReference`, and decide explicitly whether companions get the `.failed` reply.
- **Severity:** Low [verified]

### 9.11 Peer folder admission overlaps the game-mode folder stripping; stale security doc
- **Location:** `Modules/CoreRPG/Controllable/ImportControllable.swift:99-118` (`admitFolders`), `:546-558`, `:993-1015` vs `:1016-1041`; doc `:41-47`
- **What:** `isFolderImport` and `shouldDeferGameModeFolderImport` test the same category, and `keepingEntries` and `gameModeImportedItem` both filter entries by child id. The `PeerImportPolicy` doc still says existing-item entries are stripped "only in game memory", but `admitFolders` now strips them in library imports too.
- **Why:** Two filters that can disagree, the quadratic pass in §7.2, and a misleading note on a security boundary.
- **Action:** Use one `folder(_:keepingChildIds:)` helper for both paths, build the pairs once, and rewrite the doc. Combine this with §6.5.
- **Severity:** Low [verified overlap and doc]

### 9.12 The 3D weather has its own copies of the 2D weather tables
- **Location:** `Modules/WeatherRPG/Weather3D/WeatherSceneConfiguration.swift:140-160` vs `Modules/WeatherRPG/Weather/CloudGroup.swift:28-60`; `Modules/WeatherRPG/Weather3D/LightningBoltPath.swift:20-80` vs `Modules/WeatherRPG/Weather/Lightning.swift:18-90`; inline tuning numbers in `WeatherTableEffect.swift:92, 138-255`
- **What:** The 3D path keeps its own cloud count and opacity per thickness and its own bolt and fork generator. About 30 particle and light tuning values are inline, next to a named constants block.
- **Why:** Tuning the 2D look silently diverges from the table. This is low priority while the feature is off.
- **Action:** When reviving 3D weather, derive both looks from one per-thickness table, share the jitter and fork constants, and move the inline values into the constants block.
- **Severity:** Low [verified]

### 9.13 The Players button's role gate and the round button chrome are repeated
- **Location:** `Modules/GameRPG/GameViews/GameToolbarContent.swift:53-54`; `IOSGameOverlayControlField.swift:38-41`; `PlayerSideMenu.swift:28-35`; `MasterSideMenu.swift:13-24`; `QuickDice/QuickDiceToggleField.swift:13-26`
- **What:** `isMaster || gameType == .player` is written three times. The visionOS button chrome is copied in both side menus, and the round-glass chrome twice in `QuickDiceToggleField`.
- **Why:** Changing who sees the panel, or the button look, needs edits in several files.
- **Action:** Add `GameRoot.offersTablePlayers` next to `offersQuickDice`, and one `RoundGameControlStyle` modifier.
- **Severity:** Low [verified]

### 9.14 Oversized new and grown files
- **Location:**
  - `Modules/GameRPG/GameViews/TablePlayers/TablePlayersView.swift` (579, new)
  - `Modules/MapRPG/Map/MapEditorOverlayLayer.swift` (515, +173)
  - `Modules/GameRPG/Table3D/GameTableView+VisionOS.swift` (527)
  - `Modules/AudioRPG/Controller/AudioController.swift` (586)
  - `Modules/CoreRPG/Controllable/ImportControllable.swift` (1154) and `Modules/GameRPG/Root/GameRoot.swift` (763), both already in audit-23 §9.6 and still growing
- **What:** Files over 500 lines.
- **Why:** Merge conflicts and type-check cost, and the duplication in §9.9 is hidden inside the first one.
- **Action:**
  - Split `TablePlayersView` into panel+header, master list, companions list, pin-controller views, row parts and the button.
  - Move `MapEditorOverlayLayer` photo layers (`:177-282`) to `MapEditorPhotoLayers.swift`.
  - Move `AudioController` observation and logging (`:371-440`) to an extension file.
  - Move peer folder admission to `PeerImportPolicy+Folders.swift`.
- **Severity:** Low [verified]

### 9.15 `isZoom` and the "zoomed" pin layer now mean "photo shown to everyone"
- **Location:** `Modules/MapRPG/Model/MapPinModel.swift:98, 134, 153, 173`; `Modules/MapRPG/Map/MapPinViewModel.swift:108-121, 165-166, 375-376, 421-427`; `Modules/MapRPG/Map/MapEditorCanvasPins.swift:8-12, 45`; `Modules/GameRPG/Table3D/GameTableModel+PinPhoto.swift:25, 73, 99`
- **What:** The flag (32 uses), `zoomedPinNodes` and `MapPinLayerKind.zoomed` kept their names. Shared-photo pins still render in a separate top layer.
- **Why:** The misleading name contributed to §5.3. The raised layer is probably no longer intended.
- **Action:** Rename the Swift property to `isPhotoShared` and keep `isZoom` as the coding key for wire compatibility. Remove or rename the zoomed layer.
- **Severity:** Low [verified]

### 9.16 Model and logic types in View folders
- **Location:** `Modules/GameRPG/GameViews/TablePlayers/TablePlayersModel.swift`; `Modules/MapRPG/View/MapPinPhotoPopover.swift:16-43` (`MapPinPhotoSharing`)
- **What:** An `@Observable` model sits in a view folder, and a pure decision enum (with a layout constant) sits in a view file.
- **Why:** This breaks the module folder convention (Model / Controller / View).
- **Action:** Move them to `GameRPG/Model/` and `MapRPG/Model/MapPinPhotoSharing.swift`, and move `photoSide` to `MapPhotoPanelLayout`.
- **Severity:** Low [verified]

---

## 10. Cross-cutting recommendations

1. **One "may players see this" gate for everything that leaves the master.** `mapState`, the map package and `missingMapImages` use `isPinVisibleToPlayers`. The new photo paths use `pin.isShown`, ignore `isMapStreaming`, and let "local" state leak into shared state (§6.1, §6.2). Route every master-originated presentation (photo, weather, pin photo, replay, external screen) through one predicate that combines visibility, pause sharing and `isLocal`.
2. **The master derives ids for peer-declared things.** Peers should never name pin ids or primary items that the master then trusts (§6.3, §6.4). Compose ids from the sender id, and admit only items the sender introduced.
3. **Session-only flags are never persisted or exported.** `isZoom` should follow the `healthPercent` rule: cleared when its context ends, stripped from Save Game, and writable only by the master (§5.3, §5.4).
4. **2D/3D decisions in pure, shared types.** The CLAUDE.md rule ("decisions that don't need TabletopKit/RealityKit go in pure types") was not followed for pin photo sharing and popover placement (§9.4, §9.5). Both drift bugs (§5.4, §6.2) come from that.
5. **Every task is owned.** New `Task {}` sites in GameRoot, PlayerController and the audio diagnostics are fire-and-forget (§3.2, §3.3, §3.6, §3.7). Store them, cancel them in `stop()`/`reset()`/`deinit`, and route network-affecting ones through `scheduleNetworkAction`.
6. **Feature flags gate send, receive and render.** A flag in one controller leaves the rest of the feature live (§9.1).
7. **Pin identity across handovers.** A Character can move between table player, joined player and companion. Treat "same Character, new pin id" as a migration (location, battle roster) rather than delete plus create (§5.1).

---

## 11. What was NOT audited

- **Runtime behaviour.** Nothing was run: no tests, no simulator, no device. That leaves out SharePlay, LAN, the external screen, the visionOS table and the macOS menu bar extra. Findings marked [traced] or [reasoned] are code readings.
- **The earlier part of the range (`3.0.1..bf749c86d`).** It was only checked for regressions of the fixes recorded in `CODE_AUDIT_Since_3.0.1.md` §0, `CODE_AUDIT_QuickDice.md` §0 and `CODE_AUDIT_23.md` §13, plus data-loss risks in iCloud Sync, folder prune and duplicate repair. App Intents were not re-audited (three audits in `Docu/CODE_AUDIT_AppIntents*.md`).
- **Tests.** Test code was read only to confirm usage. Coverage of the new features was not assessed.
- **Instruments.** No Instruments traces were recorded. Performance findings are static.
- **Localization.** Only the presence of `bundle: .module` and of de/th values for single-line keys was checked, not the wording.
- **Build settings, schemes, entitlements and the CloudKit schema.** The new optional table-players attribute needs a schema deploy, as noted in project memory, and this was not verified.
- **Third-party and SPM content.** RPGTabletopGameContent and Apple frameworks are treated as black boxes.
- **Open findings of earlier audits.** Items such as audit 23 §7.x and §9.7-9.18 and Since_3.0.1 §8.2 are not repeated here.

---

## 12. Verification

The High and Medium findings, with the lines that prove them:

- **§6.1** — `PlayerController+MapPhoto.swift:88-100`: `presentLocal`, no broadcast. `:138-166`: `.fullScreen` → `makeCurrent` → `showFullScreen` → `setGameUpdateType(.photo)` and `presentPhoto`. `GameControllable.swift:30-32`: `currentItemId` is `gameItems.first`, and `:201-209` `setCurrent` moves the item to the front. `MasterController+MapPhoto.swift:47-54`: `guard … !state.isLocal … else { return false }`. `MasterController+PresentationReplay.swift:23-49`: falls through to `case .photo`, which shares `photoRoot.gameControllable.gameModel.currentItemId`. `ExternalGameRootView.swift:18-19`: the external screen renders `GameRootViewer` with `root.gameModel.playerController`.
- **§6.2** — `MapEditorOverlayLayer.swift:95` and `GameTableModel+PinPhoto.swift:88`: `let isShared = isGameMaster && pin.isShown`. `MapModel+Geometry.swift:30-41`: `isPinVisibleToPlayers` also excludes non-player pins in unrevealed rooms. `MapPhotoPopoverModel.swift:89-101`: the payload carries `anchor: pin.location` and `title: pin.name`.
- **§6.3** — `GameController+Pins.swift:33-38`: the live-map loop applies `applyPlayerMetadata` to any pin whose id matches, without checking `isPlayer`. `TablePlayerModel.swift:50-56`: `pinPlayers` skips only roster ids and Character ids. `:69-78`: `companionOwners` maps the companion id to its owner.
- **§6.4** — `MasterController+ValueMessages.swift:128-161` and `ImportControllable.swift:73-83`, as cited (agent-verified, paths re-read).
- **§6.5** — `ImportControllable.swift:314-317`: `if peerPolicy != nil, await itemControllable.isFolderImport(newItem) { peerFolderItems.append(newItem); continue }` runs before `prepareDecodedItem`. `:534` is the only `sanitizedForImport` call.
- **§5.1** — `MasterController+Control.swift:99-119` and `GameController+Pins.swift:43-65`: `resetPlayerPins` removes player pins not in the roster and appends the new id's pin. No battle roster call follows.
- **§5.2** — `PlayerControllerModel.swift:414`: `mapPhoto.reset()`, while the popover is cleared only at `PlayerController+MapPhoto.swift:44, 128, 142, 158, 207`. `:106-108`: `requestMapPhotoMode` returns when there is no presentation.
- **§5.3** — `GameController+Pins.swift:230-237`: `authorizedPin.isZoom = incomingPin.isZoom`, and `isZoom` is part of the "changed" check.
- **§5.4** — `GameController+Pins.swift:432-446` (`setPinPhotoShown` returns without a change) and `GameTableModel+PinPhoto.swift:96-121` (a first sync treats a flagged pin as a new share).
- **§5.5** — `PlayerController+Character.swift:20-28`: `scheduleSendCharacter` returns while a task exists. `:61-64` latches `hasSendPlayer`.
- **§3.1** — `RPGSharePlayController+SessionLifecycle.swift:394-405`: the join task awaits `sessionToJoin.join()`. `:499-511`: `OffMainGroupSession: @unchecked Sendable` with `@concurrent join()`/`leave()`. `RPGSharePlayController+ChunkedTransport.swift:618-621`: `reset()` calls `groupSession?.leave()` directly.
- **§9.1** — `MasterController+TableWeather.swift:14-16`: `nonisolated static let isTableWeatherEnabled = false`, checked only in the three master functions. `PlayerController+TableWeather.swift:12-35` has no check.
- **§9.4, §9.5, §9.8** — duplicated blocks at the cited line pairs (agent-verified).

**Earlier fixes confirmed at HEAD** (no regression by later commits):

- **Audit 23:**
  - §5.1: depth pairing, no trap; §5.13 and §5.14 are edges of it.
  - §5.2: `isShown` is in the content fingerprint, and content is sent before `mapState`.
  - §5.3: battle clones deep-copy value groups.
  - §5.4: routes are bound before the queue.
  - §5.5: except §5.12.
  - §5.6: a failed delete withdraws and resets.
  - §5.7: except §5.11.
  - §5.10, §5.11, §5.24.
  - §6.1 for `mapState`, the package and `missingMapImages`; the new gap is §6.2.
  - §6.2.
  - §6.4: dedup and gating cover the new message types, with the race in §3.5.
- **Since_3.0.1 §0:** §5.12, §5.13 and §5.14 hold.
- **QuickDice §0:**
  - §5.4 and §5.8 hold: values ≤ 0 are rejected and values are clamped.
  - §8.2 and §8.7 hold: 44 pt hit areas, kept by `ThemedQuickStepButtonStyle`.
  - §9.2 holds with tvOS forced off.
- **iCloud Sync (`27d877a06`), folder prune (`e5a5f051d`) and duplicate repair (`d08817d5b`):** no data-loss path found.
  - `.icloud` placeholders are mapped and not hashed.
  - Paths are compared with `canonicalPath`.
  - Removals start deselected and go to the trash.
  - The prune stays below the module folder and counts placeholders as content.
  - The duplicate winner is deterministic (CloudKit record name).
