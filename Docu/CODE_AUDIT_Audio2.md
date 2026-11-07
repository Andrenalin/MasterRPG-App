# MasterRPG Code Audit — AudioRPG + Game Master/Player Controllers

Generated 2026-11-07. Scope: all of `Modules/AudioRPG/` (60 Swift files, ~6,530 LOC) and the game controllers `Modules/GameRPG/Controller/MasterController*.swift`, `PlayerController*.swift`, `PlayerControllerModel.swift` (42 files, ~5,890 LOC), with call-following into `GameRPG/Root`, `GameRPG/Network`, `GameRPG/SharePlay` and `CoreRPG` where a claim needed it. Prior audits (`Docu/CODE_AUDIT_Audio.md`, `Docu/CODE_AUDIT_Game.md`, `Docu/CODE_AUDIT_Network.md`) were cross-checked: items they fixed are not repeated, residuals are marked as such, and items code comments declare INTENDED / won't fix are not re-raised.

Compiler ground truth: a full `MasterRPG` build (Xcode MCP `BuildProject`, 2026-11-07) emitted **zero Swift warnings** in the audited files (the only two warnings are App Intents metadata notices). Every concurrency finding below is therefore something the compiler cannot see: ordering, reentrancy and lifecycle.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

---

## 1. Executive summary

Top items to address, in priority order:

1. **[High] A newer play or a pause never supersedes an older pending audio play** — §5.1 — `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:115-150`. A track the GM asked for earlier (waiting on a player's upload) later starts on every device and replaces the music the GM chose since.
2. **[High] Players that leave and rejoin are locked out of their own Character** — §5.2 — `Modules/GameRPG/Controller/MasterController.swift:111-120, 158-169`. `characterOwnership` survives the departure while the rejoin gets a new sender id; the Character never binds again and the player gets no error.
3. **[High] Audio availability lists start iCloud downloads of the whole audio library** — §7.1 — `Modules/AudioRPG/Controller/GameController.swift:332-356`. Every player join and every master list broadcast asks iCloud to download every evicted audio file.
4. **[High] "Play" on the already-loaded audio silences the player** — §5.3 — `Modules/AudioRPG/Audio/SharingActionView.swift:74-82`, `Modules/AudioRPG/View/DetailEditorToolBarButtons.swift:16-21`. The bug `GameController.play` documents and works around is still present at these two call sites.
5. **[Medium] A player whose import fails blocks the shared play for everyone, forever** — §5.4 — `MasterController+AudioMessages.swift:35`. Audio `.failed` acks are dropped; no timeout or give-up.
6. **[Medium] Tapping a playlist row during a game replaces every device's playlist with that one track** — §5.5 — `Modules/AudioRPG/Root/AudioRootModel+Playback.swift:11-17`.
7. **[Medium] Players' Repeat toggle loops independently of the GM** — §5.6 — `Modules/AudioRPG/Controller/AudioController.swift:382-396`. The code comment claims the opposite.
8. **[Medium] GM network actions queue behind whole audio exports** — §7.4 / §7.3 — `Modules/GameRPG/Root/GameRoot.swift:299-314`. A large audio share delays map shows, dice and pauses, and the same file is re-exported into memory for every delivery.
9. **[Medium] The audio session is activated at game start and never deactivated** — §5.10 — `Modules/AudioRPG/Audio/AudioPlayerSession.swift:103-117`. It interrupts other apps' audio even if no game audio plays, and never lets them resume.
10. **[Medium] The playback UI is written four times and the copies already disagree; the full player is dead code with no game routing** — §8.2 / §9.1. As a result, no live screen offers an AirPlay route picker (§8.1).

---

## 2. Quick wins (≤30 min each)

- **Clear retry state wherever a pending play is cleared** — `MasterController+AudioMessages.swift:117, 146-147`. Cancel `audioPlayRetryTasks[id]` and reset attempts (§3.6).
- **Remove the departed sender's `characterOwnership` entry in `forget(playerId:)`** — `MasterController.swift:158-169`. This removes most of §5.2.
- **Re-check `wantsPlayback` in the deferred `play()` task** — `AudioController.swift:38-41` (§3.3).
- **Clear `wantsPlayback` when an interruption ends without `.shouldResume`** — `AudioPlayerSession.swift:167-182` (§5.12).
- **Make the two "Play" buttons call `set(currentId:)` + `preparePlay` after the replacing `add`**, as `GameController.play` does — `SharingActionView.swift:77-78`, `DetailEditorToolBarButtons.swift:19-20` (§5.3).
- **Delete `AudioPlayerView`, `PlayListView` and their snapshot test**, and decide where `RoutePickerView` goes (§9.1, §8.1).
- **Fix the four stale comments that state wrong invariants** — `GameController.swift:358-359`, `AudioController.swift:90-91, 384-385`, `MasterController.swift:277-286` (§9.13, §9.14).
- **Drop `.allowsHitTesting(true)` (×4), the unused `reduceMotion` and the duplicate `#if !os(tvOS)` gates** around `VolumeSlider` (§8.5).
- **Pass `bundle: .module` for the Play/Pause label** — `AudioPlayerPlaybackControls.swift:41-44` (§8.4).
- **Remove the `_printChanges` debug hook** — `Modules/AudioRPG/View/DetailFolderListView.swift:22` (§8.7).
- **Remove the dead `(.store, .screen, .game)` observer allowance** — `MasterController+NetworkStoreDelegate.swift:318` (§6.5).
- **Remove unused `Combine` / `GroupActivities` imports** from `AudioController.swift:5-6` (§4.1).

---

## 3. Concurrency

### 3.1 Pending-play loops iterate a stale dictionary copy across awaits
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:143-150` (`startCompletePendingAudioPlays`), `:65-68` (`.audioList` delivery loop)
- **What:** `for (id, data) in gameModel.pendingAudioPlays` iterates a value copy and awaits `broadcastAudioPlay` / `deliverPendingAudio` per element. With a co-located player, that await includes the local player loading the whole playlist.
- **Why:** The message pipeline and the `scheduleNetworkAction` chain interleave on the main actor at those awaits. A pause processed in between (`pendingAudioPlays[B] = nil` plus a broadcast pause) is followed by the stale loop re-broadcasting play B, or exporting B again.
- **Action:** Before each element, re-read `gameModel.pendingAudioPlays[id]` and skip it if it was removed or replaced (or pop entries from the live dictionary). This becomes moot if §5.1's single-slot design is adopted.
- **Severity:** Medium

### 3.2 Loop-replay and prefetch handlers bypass the ordered network-action chain
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:80-86, 213-219`; `Modules/GameRPG/Root/GameRoot.swift:299-315`
- **What:** The handlers installed on the audio model start bare `Task { await self?.requestAudioPlay(...) }` / `prefetchNextAudio(...)` calls instead of going through `scheduleNetworkAction`, and `stop()` cannot cancel them.
- **Why:** A loop replay that fires as the GM taps pause can be ordered after the pause and restart the playlist for everyone. A prefetch export can still run after `stop()` against a torn-down session.
- **Action:** Enqueue both through `GameRoot.scheduleNetworkAction`, which orders them with the GM's actions and is torn down with the game, or keep the tasks and cancel them in `stop()`.
- **Severity:** Medium

### 3.3 A pause does not cancel a pending load-and-play or a deferred `play()`
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:31-48` (deferred `play()`), `:268-287, 314-342` (`loadAndPlay`/`preparePlay`); `Modules/AudioRPG/Controller/GameController.swift:203-239`; `Modules/AudioRPG/Root/AudioRootModel+Playback.swift:84-91`
- **What:** `pause()` only clears `wantsPlayback` and pauses the player. The deferred `Task` in `play()` (line 38-41), `loadAndPlayTask`, and `GameController.play(_:)` (`await add` → `preparePlay(triggerPlay: true)`) all call `player.play()` after their awaits without re-checking.
- **Why:** Outside a game, "Hey Siri, play X" followed by a lock-screen or intent pause while an iCloud track is still copying starts the music anyway. The same happens on the first play after launch while the session is still configuring. In a game the serial pipelines mostly prevent this.
- **Action:** Keep a playback "intent generation" on `AudioPlayerModel`. Have `pause()` bump it, and have every resume path check it (or `wantsPlayback`) after each await before calling `player.play()`.
- **Severity:** Medium

### 3.4 Resuming after an interruption can play during a newer interruption (residual of CODE_AUDIT_Audio §3.6)
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerSession.swift:167-182` (also 150-165, 184-189)
- **What:** The `.shouldResume` branch spawns an unstructured `Task` that awaits `setActive()` (`@concurrent`, blocking) and then calls `endInterruption(wasPlaying:)` → `play()`. Nothing checks whether a new `.began` arrived meanwhile. The route-change and media-reset handlers hop through further unordered Tasks.
- **Why:** A quick end/begin pair (Siri, then a call) resumes music in the middle of the second interruption.
- **Action:** Keep an interruption generation on the session model and check it after `setActive()` before resuming. Make the route and reset handlers `@MainActor` so they act synchronously.
- **Severity:** Medium

### 3.5 `skip(to:)` is nonisolated for a reason that no longer exists, so seeks land late
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:90-104`; callers `Modules/AudioRPG/Controller/GameController.swift:235-238, 253, 293-295`
- **What:** The comment says the scrubber stores `skip(to:)` as a `@Sendable` closure, but every caller is `@MainActor` (the scrubber's `onSeek` is `@MainActor (Double) -> Void` and goes through `root.seek`). Each seek still hops through `Task { @MainActor }`.
- **Why:** In `GameController.play(_:)` the seek is scheduled after `preparePlay` has already called `player.play()`, so a positioned start plays briefly from 0:00 on every device.
- **Action:** Make `skip(to:)` `@MainActor` and replace `seekTask` directly. Seek before `play()` when a position is given, and fix the comment.
- **Severity:** Medium

### 3.6 Audio play retry tasks outlive the play they were scheduled for
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:115-119, 143-150, 236-256`; `Modules/GameRPG/Controller/MasterController.swift:277-287`
- **What:**
  - Completing a pending play clears `audioPlayRetryAttempts[id]` but not `audioPlayRetryTasks[id]`.
  - The pause branch (line 117) clears neither.
  - A retry scheduled by a `deliverPendingAudio` still in flight when `stop()` runs is never cancelled.
- **Why:** A leftover retry wakes 5 s later, finds a newer pending play of the same id and re-exports and re-uploads the package. Attempt counts carry over between unrelated plays of the same item.
- **Action:** Wherever a pending entry is removed (completion, pause, supersession, player-left, stop), also cancel and remove its retry task and reset its attempts, in one helper.
- **Severity:** Low

### 3.7 Artwork loading inside `.task(id:)` is still an unstructured Task (residual of CODE_AUDIT_Audio §3.7)
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerTimelineView.swift:100-105, 139-144`; `Modules/AudioRPG/Audio/AudioPlayerMiniBarView.swift:33-38`; `Modules/AudioRPG/Audio/AudioPlayerBarViewModel.swift:30-44`
- **What:** `.task(id:)` calls a synchronous method that spawns `artworkLoadTask`, so SwiftUI's own cancellation has nothing to cancel; `onDisappear` cancels it by hand. The image is decoded on the main actor (`artworkImage(from:)`).
- **Why:** This duplicates lifecycle handling `.task` already provides, and decoding large embedded artwork on the main actor can hitch.
- **Action:** Make `loadAlbumArtwork` `async` and await it directly in `.task(id:)`, decoding off the main actor. Then drop `cancelArtworkLoad`.
- **Severity:** Low

### 3.8 Fire-and-forget share Tasks can be reordered after later user actions
- **Location:** `Modules/AudioRPG/Controller/LinkController.swift:32-34, 44-46`; `Modules/AudioRPG/Audio/SharingActionView.swift:118-127`
- **What:** `Task { await networkActions?.shareId(gameController.share(id:)) }` awaits `networkVersion` before enqueuing into `scheduleNetworkAction`. A play tapped right afterwards is enqueued synchronously and can run first.
- **Why:** Share and play can be inverted, causing an extra request/answer round trip or a play command sent ahead of its presentation.
- **Action:** Enqueue one scheduled action that computes the share reference inside the ordered chain.
- **Severity:** Low

### 3.9 `observeSharedAudio` reacts to its own local writes
- **Location:** `Modules/AudioRPG/Controller/AudioController+Observation.swift:113-133`; `Modules/AudioRPG/Audio/AudioListenerCoordinator.swift:62-66`
- **What:** `sharedAudioId` is written only locally, in `coordinatePlayback(of:)`, right after `currentItem` is set. The handler therefore does nothing unless `currentItem` changes before the async `Observations` delivery. In that case it calls `add(audio:[item], replace: true)`, which empties the player and selects nothing.
- **Why:** In normal use it is dead code; in the rare race it replaces the playlist with one unselected track and silence.
- **Action:** Remove the observer, or limit it to a real remote signal and have it select and prepare the track it loads.
- **Severity:** Low

### 3.10 `CoordinatorDelegate` uses `@unchecked Sendable` unnecessarily
- **Location:** `Modules/AudioRPG/Audio/AudioListenerCoordinator.swift:68-71`
- **What:** The comment says `@unchecked` is needed "because NSObject is not Sendable". A `final` `NSObject` subclass whose only stored property is an immutable `Mutex` can conform to `Sendable` with checking.
- **Why:** An unneeded escape hatch hides future data races from the compiler.
- **Action:** Switch to checked `Sendable` and fix the comment.
- **Severity:** Low

---

## 4. API modernity

### 4.1 Combine kept only as a KVO bridge and a Task container (residual of CODE_AUDIT_Audio §3.3)
- **Location:** `Modules/AudioRPG/Controller/AudioController+Observation.swift:26-61`; `Modules/AudioRPG/Audio/AudioPlayerModel.swift:88-103`; `Modules/AudioRPG/Controller/AudioController.swift:5-6`
- **What:** `subscriptions: Set<AnyCancellable>` only wraps `Task.cancel()`, and `publisher(for:)` plus `.buffer` is used just to obtain an async sequence. `subscriptions` and `timeObserver` are observed properties, and `AudioController.swift` imports Combine and GroupActivities without using them.
- **Why:** It adds a second reactive paradigm and observation bookkeeping for no benefit.
- **Action:** Store `[Task<Void, Never>]` as `@ObservationIgnored`, bridge KVO with an `AsyncStream` over `observe(\.timeControlStatus)`, mark `timeObserver` `@ObservationIgnored`, and drop the unused imports.
- **Severity:** Low

### 4.2 macOS Now Playing: `playbackState` is never set and toggle-play/pause is unhandled
- **Location:** `Modules/AudioRPG/Audio/MediaPlayerManager.swift:70-81, 84-129`
- **What:** `MPNowPlayingInfoCenter.playbackState` is never assigned (grep finds no `playbackState` in AudioRPG), and `togglePlayPauseCommand` has no target.
- **Why:** On macOS the system cannot derive playback state from an audio session, so Control Center and the menu bar Now Playing show the wrong state, and the keyboard play/pause media key may not reach the app.
- **Action:** Set `playbackState` on play, pause and end under `#if os(macOS)`, and register a `togglePlayPauseCommand` target that maps to `RemoteCommand.play`/`.pause` (so it still goes through `routeRemoteCommand` in a game).
- **Severity:** Medium

---

## 5. Bugs / logic errors

### 5.1 A newer play or a pause never supersedes an older pending audio play
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:115-129` (`requestAudioPlay`), `:143-150` (`startCompletePendingAudioPlays`), `:21-33` (`.ok` handler), `:165-166` (comment); `Modules/AudioRPG/Controller/GameController.swift:438-442` (`requestPause`)
- **What:** `pendingAudioPlays` is keyed per item id. A play only replaces the pending entry for its own id, and a pause clears only the entry for `playingRootId`, which is the playlist already loaded, not the pending one. When nothing is loaded yet, `requestPause()` returns `nil` and nothing is sent. Every `.ok` then starts every pending play whose players are complete, in dictionary/ack order.
- **Why:** The game has a single audio stream. The GM plays A, which waits on a player's upload, and then plays B, which everyone has. B starts, and seconds later the upload ack for A makes `startCompletePendingAudioPlays` broadcast A, so every device switches to A. Pressing pause while A is pending doesn't stop it either. The comment at line 165 ("A pause or a newer play replaced this one") assumes a supersession that doesn't exist.
- **Action:** Keep a single "latest requested play" slot on `MasterControllerModel`. Any new play replaces it and any pause clears it, together with its retry state (§3.6).
- **Severity:** High

### 5.2 Players that leave and rejoin are locked out of their own Character
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:57, 111-120, 134-137, 158-169`; `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:131-145`; `Modules/GameRPG/Controller/MasterController+ValueMessages.swift:56-64`; `Modules/GameRPG/Root/GameRoot.swift:476-487`; `Modules/GameRPG/Controller/PlayerController+Character.swift:67-70`
- **What:** `characterOwnership` is cleared only by `resetCharacterOwnership()` in `stop()`. `lostPlayer` → `forget(playerId:)` never removes the departed sender's binding, but every `startGame` mints a new sender id (`PlayerGameModel(id: UUID())`, GameRoot.swift:477, 487).
- **Why:** A player who stops and rejoins, or relaunches the app, sends the join handshake with a new sender id. `bindCharacterOwnership` (line 112) finds the old id still bound to the same Character and returns `false`, and the guard returns `nil` without a `.failed`. The player latches `hasSendPlayer` (Character.swift:70) and never retries. Their `.valueUpdate`s are deferred forever, and `isCharacterBound` keeps the Character blocked as a companion. A reconnect that keeps the same id is not affected. This is separate from the intended open claim policy in CODE_AUDIT_17 §6.1.
- **Action:** Remove the sender's binding in `forget(playerId:)` (and the proxy-loss path), and answer a refused bind with `.failed` so the player can report or retry.
- **Severity:** High

### 5.3 "Play" on the already-loaded audio silences the player
- **Location:** `Modules/AudioRPG/Audio/SharingActionView.swift:74-82`; `Modules/AudioRPG/View/DetailEditorToolBarButtons.swift:16-21`; compare `Modules/AudioRPG/Controller/GameController.swift:227-235` and `Modules/AudioRPG/Controller/AudioController.swift:50-79, 130-146`
- **What:** Both buttons call `add(audio:replace: true)` and then `togglePlay(id: list.first?.id)`. `add(replace:)` empties the playlist, calls `replaceCurrentItem(with: nil)` and keeps `currentItem`. When the first track is the current one, `togglePlay` falls through to `toggle()`, which then either:
  - calls `play()` on a nil player item, or
  - calls `pause()`, if KVO has not yet reported the stop.
- **Why:** Tapping Play on the audio that is loaded or playing, in the detail toolbar or the inline row, stops the music. The UI keeps a `currentItem` with no playlist index, so next and previous are disabled. `GameController.play` documents this exact failure at lines 231-233 and works around it; these two call sites never got the fix.
- **Action:** Route both buttons through one controller entry point that, after the replacing `add`, explicitly calls `set(currentId:)` and `preparePlay(triggerPlay: true)` (see §9.2).
- **Severity:** High

### 5.4 A player whose import fails blocks the shared play for everyone, with no timeout
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:35, 115-129, 156-168`; `Modules/GameRPG/Controller/PlayerController+Audio.swift:30-44`; `Modules/GameRPG/Controller/PlayerController+Dispatch.swift:76-81`; `Modules/GameRPG/Controller/PlayerController+MessageProcessing.swift:315-322`
- **What:** A player that received the package but still cannot use it answers `.failed`. The master returns `nil` for every audio `.failed` (line 35) and does not retry or give up on that player. The only retry (`scheduleAudioPlayRetry`) runs when the master's own export fails.
- **Why:** The pending play stays in `pendingAudioPlays` indefinitely, so nobody hears it until the GM hides that player or pauses, and the GM gets no feedback about which player is stuck.
- **Action:** On an audio `.failed`, retry delivery to that player a bounded number of times, then start without them and surface the problem in the player report row.
- **Severity:** Medium

### 5.5 Tapping a playlist row during a game replaces every device's playlist with that one track
- **Location:** `Modules/AudioRPG/Audio/MenuBarAudioPlayerView.swift:208-210` (live, macOS); `Modules/AudioRPG/Audio/PlayListView.swift:25-27` (dead, §9.1); `Modules/AudioRPG/Root/AudioRootModel+Playback.swift:11-17`; `Modules/AudioRPG/Controller/GameController.swift:203-239, 423-429`
- **What:** Playlist rows call `playOrRequest(id: track.id)`, which sends `requestPlay(id: trackId)`, an `AudioPlayRequest` whose root is the track and whose `trackId` is `nil`.
- **Why:** On receipt, `play(_:)` skips the loaded-playlist branch (line 218, it needs a `trackId`) and runs `add(audio: fetchPlaylist(id: trackId), replace: true)`, which is just that track. The rest of the playlist, next/previous and the loop are gone on every device. The user meant to skip within the playlist (`requestTrack`).
- **Action:** In a game, send `requestTrack(trackId)` from a playlist row when the track belongs to the loaded playlist, and keep `requestPlay` for library rows.
- **Severity:** Medium

### 5.6 Players' Repeat toggle loops independently of the GM
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:382-396`; `Modules/AudioRPG/Audio/AudioPlayerRepeatButton.swift:19-22`; `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:80-86`
- **What:** `repeatPlayList` is a per-device toggle, and only the GM installs a `loopReplayHandler` (line 81 guard). On a player with Repeat on, `resetPlaylist` takes the local `togglePlay(id: first.id)` / `preparePlay` branch (lines 387-395).
- **Why:** If the GM doesn't repeat, that player loops alone. If both repeat, the player restarts twice: its own loop, then the GM's replay command. The comment at lines 384-385 ("the players do not loop on their own") is therefore false. The mini bar shows the Repeat button to players (`AudioPlayerMiniBarView.swift:103`).
- **Action:** While a game runs on a player device, ignore `repeatPlayList` in `resetPlaylist` (or hide or disable the button) so only the GM's loop command restarts playback.
- **Severity:** Medium

### 5.7 A player falls silent when its next track arrives after the current one ends
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:378-403`; `Modules/AudioRPG/Controller/GameController.swift:264-282`; `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:200-209`
- **What:** Players advance locally at track end, within the tracks that have arrived. If the prefetched next track hasn't arrived, `resetPlaylist` marks the playlist complete and clears `wantsPlayback`. `syncLoadedPlaylist` / `itemArrived` later only appends and sorts; it never resumes.
- **Why:** With short tracks or the slower SharePlay relay, a player stops while the GM and the others continue.
- **Action:** When a track arrives and the device stopped at the end of the arrived tracks while that root is still the GM's current playlist, resume at the arrived track. Alternatively, have the GM send an explicit track command on each advance.
- **Severity:** Medium (timing-dependent; plausible, not reproduced)

### 5.8 The co-located GM player applies authoritative audio lists to the master's own report model
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:94-97`; `Modules/GameRPG/Network/GameNetworkController+Delivery.swift:15-21`; `Modules/GameRPG/Controller/PlayerController+Audio.swift:47-48, 78-90`; `Modules/AudioRPG/Controller/GameController.swift:369-377`
- **What:** The master's `.audioList` broadcast also reaches the co-located local player. It applies the list authoritatively to the same `ItemGameModel.playerReports` that the master writes, and `applyAudioList` has no `asGameMaster` guard.
- **Why:** When the local player's pipeline is busy (copying a playlist), the snapshot can land after newer acks and erase them. The master then thinks players lack files, re-delivers whole packages, and share buttons revert. This is the same class of bug as the fixed co-located Map re-import.
- **Action:** Skip `applyAudioList` on a co-located player (`gameModel.asGameMaster`); the master is already authoritative on that device.
- **Severity:** Medium (plausible; ordering-dependent)

### 5.9 A media-services reset silently ends SharePlay audio coordination
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:356-374, 434-450`; `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:533-534, 623-628`; `Modules/GameRPG/Root/GameRoot.swift:411, 493`
- **What:** `resetMediaService()` replaces `model.player` and creates a new `AudioListenerCoordinator`. `sharePlayStore.setup(audioCoordinator:)` runs only at game start, and the SharePlay controller holds the old coordinator weakly.
- **Why:** After a media-server reset during a SharePlay game, the new player's `playbackCoordinator` is never passed to `coordinateWithSession`. SharePlay players only prepare and rely on the coordinator to start, so they hear nothing for the rest of the session, with no error.
- **Action:** After the engine is re-initialized, notify the game (a callback or an observable coordinator property) so it runs `coordinateWithSession` again on the new coordinator.
- **Severity:** Medium (resets are rare)

### 5.10 The audio session is activated at game start and never deactivated
- **Location:** `Modules/AudioRPG/Root/AudioRootModel.swift:181-185`; `Modules/GameRPG/Root/GameRoot.swift:411, 493`; `Modules/AudioRPG/Audio/AudioPlayerSession.swift:50-56, 103-117`
- **What:** Reading `audioCoordinatorPlayback` at game start calls `prewarm()`, which sets the `.playback`/`.longFormAudio` category and calls `setActive(true)`. No path ever calls `setActive(false, options: .notifyOthersOnDeactivation)`; grep finds only `setActive(true)` at line 113.
- **Why:** Starting a game as GM or player interrupts the user's Music or podcast even if no game audio ever plays, and that audio is never told it may resume.
- **Action:** Configure the category at prewarm but activate on the first real play. Deactivate with `.notifyOthersOnDeactivation` when playback ends or the game stops.
- **Severity:** Medium

### 5.11 Pending-play delivery exports without the iCloud availability check
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:174-186, 191-209`; contrast `:37-41` and `Modules/GameRPG/Controller/MasterController+Messaging.swift:188-190`
- **What:** `deliverAudio` calls `createGameData(for:)` directly, while asset requests and `show()` first check `hasLocalAudioData`.
- **Why:** For an evicted iCloud file, the content-hash backfill and the export do a coordinated read that waits for the download. That stalls the master's pipeline or the GM's action chain, possibly indefinitely while offline (see §7.4).
- **Action:** Check availability in `deliverAudio` and the prefetch path first. When the file is missing, trigger the download for that one file and schedule the bounded retry instead of blocking.
- **Severity:** Medium (plausible; not reproduced)

### 5.12 A seek after an interruption that ended without resuming makes everyone play
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:418-429`; `Modules/AudioRPG/Audio/AudioPlayerSession.swift:167-182`; `Modules/AudioRPG/Controller/GameController.swift:454-459`
- **What:** `beginInterruption` pauses but keeps `wantsPlayback == true` by design. When the interruption ends without `.shouldResume`, nothing clears it.
- **Why:** The GM's device shows paused, but `requestSeek` builds `shouldPlay: model.wantsPlayback`, so scrubbing resumes playback on every device.
- **Action:** Clear `wantsPlayback` when an interruption ends without `.shouldResume`.
- **Severity:** Low

### 5.13 Audio availability reports ignore the item version
- **Location:** `Modules/AudioRPG/Controller/GameController.swift:108-115, 141-144`; `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:21-26`; `Modules/GameRPG/Controller/PlayerController+Dispatch.swift:87-93`
- **What:** Audio acks carry no version, and reports are plain player-id sets. Photo, Pdf and Space compare against a master version.
- **Why:** After the GM replaces an audio file during a game, players still count as having it, and the play starts with old bytes on their side.
- **Action:** Track a master version per audio item, as the other file modules do (`setMasterVersion`), and invalidate reports when it changes.
- **Severity:** Low

### 5.14 A player's transport controls silently do nothing when audio sharing is off
- **Location:** `Modules/AudioRPG/Root/AudioRootModel+Playback.swift:22-33, 40-57`; `Modules/GameRPG/Controller/PlayerController+SendMessages.swift:85-87`; `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:50-51`
- **What:** In a game, a player's in-app, lock-screen and AirPods play, pause and skip are routed to the master. `PlayerController.game` drops them when `audioSharing` is off, while the remote command still reports `.success`.
- **Why:** Players cannot even pause the music on their own device, and get no feedback.
- **Action:** When audio sharing is off, apply transport commands locally on a player (or disable the controls).
- **Severity:** Low

### 5.15 In-game and out-of-game playlists contain different tracks
- **Location:** `Modules/AudioRPG/Controller/GameController.swift:170-190` (`fetchPlaylist`); `Modules/AudioRPG/Controller/ItemController.swift:35-48` (`audioList`/`hasAudio`)
- **What:**
  - `fetchPlaylist` walks the entries of any item (via `audioId`, with a seen set), includes a folder's own file, and has no depth limit.
  - `ItemController.audioList` walks only special-category folders (via `childId`) with `FolderTreeDepthLimit`, and skips the folder's own file.
- **Why:** The same item plays a different track list in and out of a game, and the game walk lacks the depth guard used elsewhere.
- **Action:** Use one playlist definition with the depth limit for both paths (see §9.2).
- **Severity:** Low

### 5.16 Now Playing keeps showing a track that was dropped
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:131-146, 324-329`
- **What:** `add(replace:)` and the failed-load branch of `preparePlay` set the player item to `nil` without calling `MediaPlayerCoordinator.handleItemChange(item: nil, …)`.
- **Why:** The lock screen and Control Center keep showing, and offering controls for, a track that no longer plays.
- **Action:** Clear Now Playing info wherever the current item is dropped.
- **Severity:** Low

### 5.17 Mute/unmute restores a stale volume
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerBarViewModel.swift:18, 81-88`; `Modules/AudioRPG/Audio/AudioPlayerBarView.swift:13`; `Modules/AudioRPG/Audio/AudioPlayerMiniBarView.swift:18`
- **What:** `previousVolume` lives on a per-view `@State` view model; each bar and mini bar has its own instance, and the value defaults to `0.25`. `isMuted` is just `volume == 0`.
- **Why:** If you drag the slider to 0, or mute in one surface, and then unmute in another, the volume jumps to `0.25` instead of the level before muting.
- **Action:** Keep the pre-mute volume on `AudioPlayerModel` next to `volume`.
- **Severity:** Low

---

## 6. Security

Players are trusted at join (PIN / GM approval / SharePlay call) per the project's documented policy, and peer import gaps are won't-fix (CODE_AUDIT_Folder §6.1/§6.2). The items below are flagged because they go beyond import policy; trust-model-dependent ones say so.

### 6.1 Any SharePlay participant can impersonate the game master to other players
- **Location:** `Modules/GameRPG/Network/GameNetworkController+SharePlayDelegate.swift:64-77, 119-128`; `Modules/GameRPG/Controller/PlayerController+MessageProcessing.swift:57-108`; `Modules/GameRPG/Controller/PlayerControllerModel.swift:119-125`
- **What:** On a player device, any Messenger or Journal envelope with `sender.isMaster` and the publicly visible master id is accepted. A different participant id simply re-pins the "master participant" (`.changed`), which calls `ready()` again.
- **Why:** A modified client in the FaceTime call can play or pause audio, reveal or store content into other players' libraries, and flip the pin back and forth. The earlier departed-id denylist (CODE_AUDIT_Reconnect §3.2) no longer exists.
- **Action:** Pin the master participant once (session originator or first broadcast) and reject master envelopes from any other participant instead of re-pinning.
- **Severity:** Medium (trust-model dependent)

### 6.2 Players can enumerate and download every audio item in the GM's library
- **Location:** `Modules/AudioRPG/Controller/GameController.swift:332-344`; `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:37-41, 50-60`; `Modules/CoreRPG/Controllable/GameControllable.swift:190-196`
- **What:** The authoritative audio list keys `players` by every library audio id. An asset request, or a `.playAudio` request, for any id the master holds is answered or shared with no check that the item was ever used in this game; `hasItem(id:version: 0)` even appends it to the game model.
- **Why:** Any connected player can pull the GM's whole private audio library, and with audio sharing on can force any library audio onto every device. The list payload also grows with the library on every broadcast.
- **Action:** List only ids that are in the game (shown or delivered), and answer asset or play requests only for those ids.
- **Severity:** Medium (trust-model dependent)

### 6.3 Player-reported audio ids grow the master's report map without bound
- **Location:** `Modules/AudioRPG/Controller/GameController.swift:337-343, 378-389`
- **What:** The non-authoritative `applyAudioList` inserts every id a player lists into `playerReports`. Every later `audioList(allPlayers: true)` iterates those keys, checks their files and broadcasts all of them.
- **Why:** A buggy or modified player can inflate master memory, per-broadcast work and every player's payload.
- **Action:** Ignore reported ids the master doesn't hold, and cap the list size (see `GameLimits`).
- **Severity:** Low

### 6.4 Counter 0 bypasses the list ordering gates
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:171-180` (and the Photo/Pdf/Space copies to 229); `Modules/GameRPG/Controller/PlayerControllerModel.swift:146-153, 182-186`
- **What:** `canApply*List` always accepts counter 0 and never records it, although no legitimate sender uses 0 (both sides count from 1).
- **Why:** On the master this only lets a peer rewrite its own entry. On players, a counter-0 "authoritative" list, delivered via §6.1 or a replay, overwrites all reports regardless of order.
- **Action:** Reject counter 0 for list messages (fold into §9.3's shared tracker).
- **Severity:** Low

### 6.5 Observer filter still admits the removed `.screen` upload
- **Location:** `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:318`; `Modules/GameRPG/Controller/MasterController+GameMessages.swift:20-28`; `Modules/CoreRPG/Model/RPGMessageActionType.swift:9`
- **What:** `normalizedObserverMessage` still admits `(.store, .screen, .game)` with a payload, although the screenshot feature was removed (CODE_AUDIT_Game §9.17) and nothing sends `.screen`.
- **Why:** This is a dead exception in a security filter: it accepts observer-uploaded bytes that nothing reads.
- **Action:** Remove the tuple, and the enum case if wire compatibility allows.
- **Severity:** Low

### 6.6 Character id logged with inconsistent privacy
- **Location:** `Modules/GameRPG/Controller/MasterController+ValueMessages.swift:149` (`.public`); `Modules/GameRPG/Controller/PlayerController+Value.swift:38, 45` and `Modules/GameRPG/Controller/PlayerController+Character.swift:75` (`.private`)
- **What:** The master logs `characterId` as public, while the player logs the same id as private. All other in-scope logging keeps names, paths and descriptions private.
- **Why:** Mixed policy for the same identifier.
- **Action:** Use `.private` on both sides.
- **Severity:** Low

---

## 7. Performance

### 7.1 Audio availability lists start iCloud downloads of the whole audio library
- **Location:** `Modules/AudioRPG/Controller/GameController.swift:154-161, 332-356`; `Modules/CoreRPG/Files/FileUrlDataController.swift:265-281, 315-326`; callers `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:30-32, 61-63, 94-97`, `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:75-83`
- **What:** `audioList(allPlayers:)` awaits `hasLocalDatabaseAudioData` for every item in `itemController.itemDataModel.items` (plus report keys), serially. That calls `hasDownloadedData` → `isDownloadedOrLocal`, which calls `FileManager.startDownloadingUbiquitousItem` for every evicted file (line 321).
- **Why:** A player's `ready()` and every master `broadcastAudioList` (each player list, each completed share) ask iCloud to download the user's entire evicted audio library. That can mean gigabytes of storage and cellular data. The serial per-item `@concurrent` hops also make each broadcast slower as the library grows. This side effect came with the switch to `hasDownloadedData`; the scan cost alone was CODE_AUDIT_Game §7.2. The same pattern exists for photo/pdf/space lists in `Modules/CoreRPG/Controllable/FileVersionGameControllable.swift` (~195-208).
- **Action:**
  - Add a side-effect-free "is downloaded" check (resource values only) for library-wide scans, and start downloads only for items actually played or shared.
  - Run the checks in a bounded TaskGroup or from a cached availability set.
- **Severity:** High

### 7.2 Every track of a playlist is copied before the first plays, and every loop does it again
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:128-191, 195-235, 382-387`; `Modules/AudioRPG/Controller/GameController.swift:215-239, 304-313`
- **What:** `add(audio:replace:)` copies every track to a temp file and loads its duration, 3 at a time, before returning, and `play`/`loadPlaylist` await it before `preparePlay`. A loop replay is sent without `trackId`, so it takes the full-reload path, which deletes and re-copies every file on every device.
- **Why:**
  - A large playlist, or one with evicted iCloud tracks, delays the first note.
  - The player's serial pipeline is blocked meanwhile, so a following pause waits.
  - On the GM device the co-located player's drain blocks the action chain.
  - `PlayAudioIntent` can exceed App Intent time limits.
- **Action:** Load and start the start track first, then append the rest in a background task guarded by `playListGeneration`. Make a loop replay of the loaded playlist restart in place.
- **Severity:** Medium

### 7.3 The same audio is re-exported into memory for every delivery, with no in-flight dedupe
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:65-68, 156-187, 203-209, 236-256`; `Modules/CoreRPG/Controllable/GameControllable.swift:270-286`; `Modules/GameRPG/Network/GameNetworkController+Delivery.swift:50-58`
- **What:** Each `deliverAudio` call exports the whole file into an in-memory `Data` and re-encodes it, even while an identical delivery is still running. It runs once per joining player's list, retry, prefetch, repeated play tap and asset request.
- **Why:** Peak memory is about 2× or more the file size per concurrent delivery, and multi-MB transfers to the same players are duplicated, which hurts most over the slower SharePlay relay.
- **Action:** Track in-flight deliveries per item (await the running one), and reuse one prepared package for all recipients.
- **Severity:** Medium

### 7.4 The GM's serialized network actions wait behind a whole audio export and send
- **Location:** `Modules/GameRPG/Root/GameRoot.swift:229-238, 299-314`; `Modules/GameRPG/Controller/MasterController+Messaging.swift:216-218`; `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:115-129, 156-187`
- **What:** The `.playAudio` game action runs `requestAudioPlay`, which awaits the full export and hand-off of every missing item inside the single `scheduleNetworkAction` chain (`previous?.value` at line 303).
- **Why:** Every later GM action, such as showing a map, rolling dice or pausing, is held until a large audio file has been exported and queued.
- **Action:** Record the pending play and return, then run the delivery in its own tracked task outside the action chain. Combine this with §7.3's dedupe and §3.6's cancellation.
- **Severity:** Medium

### 7.5 Now Playing info is rewritten every second
- **Location:** `Modules/AudioRPG/Controller/AudioController+Observation.swift:82-105`; `Modules/AudioRPG/Audio/MediaPlayerManager.swift:70-81`
- **What:** The 1-second periodic time observer rebuilds and writes the whole `nowPlayingInfo` dictionary on every tick.
- **Why:** The system extrapolates position from elapsed time and rate, so the per-second writes are unnecessary cross-process traffic.
- **Action:** Update Now Playing only on item, rate or seek changes, and keep the 1 s tick for the in-app `playerTime`.
- **Severity:** Low

### 7.6 A player exports the whole audio file just to share a reference
- **Location:** `Modules/AudioRPG/Audio/SharingActionView.swift:117-127`; `Modules/GameRPG/Controller/PlayerController+SendMessages.swift:70-77, 98-104`
- **What:** The player share path always runs `createGameData`, a full export into memory whose errors `try?` swallows, even when the master already has the item and only the reference would be sent.
- **Why:** It wastes memory and time on large files, and a failed export silently does nothing.
- **Action:** Check whether the master already has the item first, export only when bytes are needed, and surface export errors.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 No live surface offers an AirPlay route picker
- **Location:** `Modules/AudioRPG/Audio/RoutePickerView.swift:1-35` (only used at `Modules/AudioRPG/Audio/AudioPlayerView.swift:64`)
- **What:** `RoutePickerView` (`AVRoutePickerView`) is only placed in `AudioPlayerView`, which nothing instantiates (§9.1). No other `AVRoutePickerView` exists in Modules or Sources.
- **Why:** The app declares the airplay background mode, but users can reach AirPlay only through Control Center, not from the game toolbar player, the mini bar or the player bar.
- **Action:** Add `RoutePickerView` to `AudioPlayerBarView` / `ToolbarAudioPlayerPopoverView` on iOS and visionOS, or delete it along with `AudioPlayerView` if that's intended.
- **Severity:** Low

### 8.2 Transport, repeat and title UI is written four times, and the copies disagree
- **Location:** `Modules/AudioRPG/Audio/MenuBarAudioPlayerView.swift:47-52, 63-143`; `Modules/AudioRPG/Audio/AudioPlayerPlaybackControls.swift:20-71`; `Modules/AudioRPG/Audio/AudioPlayerMiniBarView.swift:51-108`; `Modules/AudioRPG/Audio/AudioPlayerView.swift:80-85, 111-186`; `Modules/AudioRPG/Audio/AudioPlayerRepeatButton.swift:13-43`
- **What:** Previous, play/pause, next and repeat are hand-built in four views. The menu bar and `AudioPlayerView` rebuild repeat even though `AudioPlayerRepeatButton` exists, and the "No song currently loaded" title helper is copied verbatim.
- **Why:** The copies already diverge:
  - Play is disabled on `playList.isEmpty` in PlaybackControls:52 and MiniBar:85, but on `currentId == nil` in MenuBar:101.
  - Next is labelled "Next" in MiniBar:92 and "Next Track" elsewhere.
  - The dead `AudioPlayerView` skips the game routing entirely.
- **Action:** Extract shared `AudioTransportButton(kind:)` and `AudioCurrentTitle` views that take their size and style from the caller, and reuse `AudioPlayerRepeatButton`.
- **Severity:** Medium

### 8.3 `AudioPlayPauseButton` sends a game command it can never send, and has its own play logic
- **Location:** `Modules/AudioRPG/Audio/AudioPlayPauseButton.swift:20-22, 41-63`
- **What:** The button only renders when `isGameRunning != true` (line 22), yet its action calls `networkActions?.game(requestPlay…)` with a comment saying it broadcasts. Outside a game, `GameRoot.networkActions.game` finds no controller and does nothing (`Modules/GameRPG/Root/GameRoot.swift:229-238`). The rest is a hand-written decision tree that duplicates `playOrRequest` / `togglePlay`.
- **Why:** The dead call and comment mislead readers, and the extra code path is a fifth variant of "play this item" (§9.2).
- **Action:** Remove the broadcast and comment, and call the shared play entry point.
- **Severity:** Low

### 8.4 Play/Pause label is not resolved from the module bundle
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerPlaybackControls.swift:41-44`
- **What:** `Label(isPlaying ? "Pause" : "Play", systemImage:)` looks the key up in the main bundle. Every sibling uses `Text("…", bundle: .module)`.
- **Why:** It breaks the project rule that module views use `bundle: .module`, so the localization depends on the app's own catalog. Also check that the ternary-literal keys at `AudioPlayerMiniBarView.swift:73` and `AudioPlayerVolumeControl.swift:46` are extracted into the module catalog.
- **Action:** Use the `Label { Text(…, bundle: .module) } icon:` form, with one literal per branch.
- **Severity:** Low

### 8.5 Redundant tvOS gating and no-op modifiers in the volume and bar views
- **Location:** `Modules/AudioRPG/Audio/VolumeSlider.swift:14-16`; `Modules/AudioRPG/Audio/AudioPlayerVolumeControl.swift:29-39`; `Modules/AudioRPG/Audio/PlayerVolumeView.swift:12, 30-53`; `Modules/AudioRPG/Audio/ToolbarVolumeSliderView.swift:10-16`; `Modules/AudioRPG/Audio/AudioPlayerBarView.swift:22, 28, 32, 38`
- **What:**
  - `VolumeSlider` already renders `EmptyView` on tvOS, yet every caller also wraps it in `#if !os(tvOS)`.
  - `.allowsHitTesting(true)` is applied four times with "Ensure touches are registered" comments; it is the default and does nothing.
  - `PlayerVolumeView.reduceMotion` is never read.
  - `volumeChangeView()` is a view-returning function, which the project's SwiftUI rules disallow.
- **Why:** Noise, plus comments that claim an effect the code doesn't have.
- **Action:** Keep the tvOS gate only inside `VolumeSlider`, delete the no-ops and the unused environment value, and turn `volumeChangeView` into a subview struct.
- **Severity:** Low

### 8.6 Timeline iPad and Mac subviews are near-duplicates, and the "Mac" one also runs on tvOS and visionOS
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerTimelineView.swift:36-51, 74-107, 110-146`
- **What:** Both subviews repeat the same two overlays, the `.task(id:)` artwork load and the `.onDisappear` cancel; only the tap-versus-hover trigger differs. The `#else` branch makes `AudioPlayerTimelineMacView` the visionOS and tvOS view as well.
- **Why:** The lifecycle code is duplicated, and the name misleads.
- **Action:** Write one timeline view with a platform-specific reveal modifier, named by behaviour (for example `HoverRevealTimeline`).
- **Severity:** Low

### 8.7 Debug view-change printing in a production list body
- **Location:** `Modules/AudioRPG/View/DetailFolderListView.swift:22`
- **What:** `let _ = Self.printViewChangesOnlyInDebug()` calls `_printChanges()` on every body evaluation in DEBUG builds. It is the only print-like call in scope.
- **Why:** It floods the debug console on a frequently re-rendered list.
- **Action:** Remove it, or put it behind an opt-in debug flag.
- **Severity:** Low

### 8.8 `currentTime` reads `AVPlayer` directly and is not observation-tracked
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerModel.swift:15-17`; readers `Modules/AudioRPG/Audio/MenuBarAudioPlayerView.swift:154`, `Modules/AudioRPG/Audio/AudioPlayerTimelineView.swift:182, 208`
- **What:** `AudioPlayerModel.currentTime` is a computed `player.currentTime().seconds`. Views refresh only because they also happen to read `playerTime`, which the 1 s observer updates.
- **Why:** This is an implicit coupling: a view that reads only `currentTime` would freeze, and a paused seek updates the scrubber only on the next tick.
- **Action:** Expose the elapsed seconds through `playerTime` (already updated per tick and on seek) and have views read only that.
- **Severity:** Low

### 8.9 `PlayerVolumeView` frames itself to its own measured size
- **Location:** `Modules/AudioRPG/Audio/PlayerVolumeView.swift:11, 37, 41-49, 55-61`
- **What:** The popover content is `.fixedSize()`, measured with `onGeometryChange` into `sharingSize`, then framed to that same size. The initial `200×64` guess, the `160` width and the `+8` offset are hard-coded.
- **Why:** The measure-then-frame loop adds a layout pass and briefly mis-positions the overlay on first show, and the fixed width ignores Dynamic Type.
- **Action:** Drop the self-framing and use `@ScaledMetric` for the width, as `MenuBarAudioPlayerView` does.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

No `#if false` blocks, commented-out code blocks, `print`/`debugPrint` calls or TODO/FIXME/HACK markers were found in the audited scope.

### 9.1 Files to delete outright
- `Modules/AudioRPG/Audio/AudioPlayerView.swift` (245 LOC). It is used only by its own `#Preview` and `Tests/AudioRPGSnapshotTests/AudioRPGGeneratedPreviewSnapshotTests.swift:58-62`. Its prev/next/seek controls (lines 115, 151, 223) bypass the game routing.
- `Modules/AudioRPG/Audio/PlayListView.swift` (63 LOC). It is used only from `AudioPlayerView`.
- `Modules/AudioRPG/Audio/RoutePickerView.swift` (35 LOC). Delete it, or wire it in per §8.1.
- Also update the doc comment at `Modules/AudioRPG/Audio/MenuBarAudioPlayerView.swift:10-12`, which says `AudioPlayerView` "stays as it is for the other platforms".
- **Severity:** Medium (~340 LOC removed; removes a drifted, game-unsafe copy)

### 9.2 "Play this item" is implemented five ways, with two playlist walkers
- **Locations:**
  - `Modules/AudioRPG/Audio/SharingActionView.swift:74-82` and `Modules/AudioRPG/View/DetailEditorToolBarButtons.swift:16-21` (verbatim copies; §5.3)
  - `Modules/AudioRPG/Root/DetailRootView.swift:16-20` (no playlist expansion)
  - `Modules/AudioRPG/Audio/AudioPlayPauseButton.swift:41-63` (§8.3)
  - `Modules/AudioRPG/Controller/LinkController.swift:37-40`
  - walkers `Modules/AudioRPG/Controller/ItemController.swift:35-48` vs `Modules/AudioRPG/Controller/GameController.swift:170-190` (§5.15)
- **Why:** The same user intent gives different results depending on the button. For example, the space-bar action on a folder plays nothing because `DetailRootView` never expands the playlist, while the toolbar button plays it.
- **Action:** Keep one playlist resolver in `ItemController` and one `AudioRootModel.playItem(id:)` entry point (`startPlayback` is nearly that already), and route every call site through it.
- **Severity:** Medium

### 9.3 `MasterControllerModel` repeats the list-sequence tracker four times
- **Locations:** `Modules/GameRPG/Controller/MasterController.swift:46-49, 159-162, 171-229`; `Modules/GameRPG/Controller/MasterController+Control.swift:51-54`; `Modules/GameRPG/Controller/PlayerControllerModel.swift:42-45, 146-186, 425-428`
- **What:** `canApply/record/reset{Audio,Photo,Pdf,Space}List` and their four dictionaries are copied verbatim, including the inline `counter >= 0 / > 0 / > last` rule. The player model has another four pairs.
- **Action:** Introduce a `ListSequenceTracker` value type keyed by `NetworkModules` (canApply/record/forget/reset), use one instance per model, and apply §6.4 there once.
- **Severity:** Medium

### 9.4 Per-module list, ack and handler bodies are copy-pasted for Photo, Pdf, Space and Audio
- **Locations:**
  - Master: `MasterController+PhotoMessages.swift:20-78`, `+PdfMessages.swift:20-76`, `+SpaceMessages.swift:20-38, 89-112`, `+AudioMessages.swift:21-34, 99-111, 156-168, 191-198, 203-209`
  - Player: `PlayerController+Photo.swift:21-27, 42-58, 93-105`, `+Pdf.swift:16-22, 37-54, 62-74`, `+Space.swift:24-30, 48-61, 96-108`, `+Audio.swift:78-90`
- **What:** The handlers differ only by module accessor. Master `applyAudioList` re-implements `applyFileList` (`MasterController+FileMessageSupport.swift:59-72`).
- **Why:** The copies are already drifting: the Pdf `.generic` branch has no feature gate, while Photo, Space and Audio do.
- **Action:** Introduce a `FileBackedModuleAccess` (setMasterVersion, markAvailable, list, applyList, sequence key, feature flag) resolved from `NetworkModules`, with generic master and player handlers. Audio and Space keep their extra cases.
- **Severity:** Medium

### 9.5 Routing switches over file-backed modules are duplicated across controller files
- **Locations:** `Modules/GameRPG/Controller/MasterController+Messaging.swift:132-145, 149-167, 175-196`; `MasterController+ProxyRouting.swift:177-189`; `MasterController+NetworkStoreDelegate.swift:85-89, 135-140, 314-317`; `PlayerController+SendMessages.swift:52-77`
- **What:** Seven switches over photo, pdf, space and audio have identical case bodies, and the same four `(.update, .xList, .x)` tuples appear twice. `root.fileBackedGameModules` exists but none of these switches use it.
- **Action:** Drive them from §9.4's module access, and keep the list-envelope tuples in one static set.
- **Severity:** Medium

### 9.6 `GameController` repeats its own playlist-load sequence
- **Locations:** `Modules/AudioRPG/Controller/GameController.swift:218-224` vs `319-328`; `227-235` vs `305-312`
- **What:** The isLoaded → sync → contains check and the add → setRoot → set(currentId:) → preparePlay sequence each appear twice, differing only in `triggerPlay`.
- **Why:** The race-sensitive load sequence exists in two copies, and CODE_AUDIT_21 §3.4 fixed only one of them.
- **Action:** Have `play(_:)` call `loadPlaylist(id:trackId:triggerPlay:)` and extract the shared check.
- **Severity:** Low

### 9.7 `hasLocalAudioData` duplicates `hasLocalFileData`
- **Locations:** `Modules/AudioRPG/Controller/GameController.swift:44-45, 150-152`; `Modules/GameRPG/Controller/PlayerController+Audio.swift:36-37`; `Modules/GameRPG/Controller/PlayerController+Photo.swift:88-91`; `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:39`
- **What:** The protocol requirement only forwards to `hasLocalFileData`, which makes Audio the odd case at call sites that already use the generic check. PlayerController+Audio's `.store` branch also inlines `holdsFile(of:in:)`, whose shared helper lives in the Photo file.
- **Action:** Remove the requirement, call `hasLocalFileData`/`holdsFile` directly, and move `holdsFile` to a shared file such as `PlayerController+FileSupport.swift`.
- **Severity:** Low

### 9.8 Unreachable guards and duplicated branch tails in `PlayerController+Audio`
- **Locations:** `Modules/GameRPG/Controller/PlayerController+Audio.swift:18, 50, 79, 26-29, 41-44`
- **What:** Line 18 already returns unless `sender.isMaster`, so the same checks at lines 50 and 79 can never fail. The `.reveal` and `.store` branches end with the same three statements.
- **Action:** Remove the redundant guards and extract a private `acceptAudio(_:)` helper.
- **Severity:** Low

### 9.9 Write-only or test-only state
- **Locations:** `Modules/GameRPG/Controller/MasterController.swift:29, 293` (`MasterControllerModel.asProxy`, never read); `Modules/GameRPG/Controller/PlayerControllerModel.swift:39, 95-97` (`messageCounter`, read only by tests); `Modules/AudioRPG/Model/AudioModel.swift:95-96` (`players`); `Modules/CoreRPG/Controllable/GameControllable.swift:7-9` (`ItemGameReportable`, never used as a constraint)
- **Action:** Delete them, or move test-only state behind a test hook.
- **Severity:** Low

### 9.10 Dead parameters, overloads and stubs
- **Locations:**
  - `Modules/AudioRPG/Controller/GameController.swift:195-198`: `play(id: UUID?)` gets `nil` only from tests.
  - `Modules/AudioRPG/Controller/AudioController.swift:67`: `triggerPlay` is `false` only in tests.
  - `Modules/AudioRPG/Controller/AudioController.swift:290-292`: `removeAudio` calls `togglePlay()` to mean pause.
  - `Modules/AudioRPG/Controller/ViewController.swift:45-47`: the `gameView(root:)` stub ignores `root` and is called only from a test (prior CODE_AUDIT_Audio §9.9, still present).
  - `Modules/AudioRPG/View/InlineRowViewer.swift:8`: `destination` is never read.
  - `Modules/GameRPG/Controller/PlayerController+Dispatch.swift:28, 56-58`: `handleAdventure` always returns `nil`.
  - `Modules/GameRPG/Controller/MasterController+MessageDispatch.swift:20-28`: an overload with a single caller.
- **Action:** Narrow each API to what is used and inline the single-caller overloads.
- **Severity:** Low

### 9.11 Root and controller boilerplate is verbatim across modules
- **Locations:** `Modules/AudioRPG/Root/AudioRootModel.swift:187-199`; `Modules/AudioRPG/Controller/SyncDataController.swift:7-20`; `Modules/AudioRPG/Root/LinkRootView.swift:6-15`; `Modules/AudioRPG/Model/DataModel+Extensions.swift:17-36`
- **What:**
  - `itemDataCleanup()` and `checkFolders(reportModel:)` are byte-identical in Pdf, Photo, Space and Weather, and `itemDataCleanup` is `async throws` but never throws.
  - SyncDataController differs only by entity across 12 modules.
  - LinkRootView is identical to Pdf, Photo and Space.
  - `attributeSet()` round-trips strings through `CRDT(wrappedValue:)` for nothing.
- **Action:**
  - Add default implementations on the CoreRPG protocol and drop the `throws`.
  - Make SyncDataController a generic CoreRPG type.
  - Simplify `attributeSet()`.
- **Severity:** Medium

### 9.12 Receive-pipeline boilerplate is duplicated between Master and Player
- **Locations:** `Modules/GameRPG/Controller/MasterController+NetworkStoreDelegate.swift:147-157, 167-181, 209-214, 345-354`; `Modules/GameRPG/Controller/PlayerController+MessageProcessing.swift:38-51, 265-269, 309-313`
- **What:**
  - The `enqueue`-result switch with four log lines appears three times.
  - The player inlines the hand-off block that master has as `handOffBacklog()`.
  - `received` → `receivedProcess` → `receivedProcess` are pure trampolines.
- **Action:** Add `GameMessagePipeline.enqueueAndLog(_:prefix:)` and a shared hand-off helper, and remove the trampolines.
- **Severity:** Low

### 9.13 Stale comments in AudioRPG that state wrong invariants
- **Locations:**
  - `Modules/AudioRPG/Controller/AudioController.swift:90-91`: the `@Sendable` scrubber closure no longer exists (§3.5).
  - `Modules/AudioRPG/Controller/AudioController.swift:294-296`: says the temp filename is "stable per item", but every load creates a unique file.
  - `Modules/AudioRPG/Controller/AudioController.swift:384-385`: says players never loop on their own (§5.6).
  - `Modules/AudioRPG/Controller/GameController.swift:10-12`: describes a `Task<Void, Error>` return; the requirement is now `async throws`.
  - `Modules/AudioRPG/Controller/GameController.swift:358-359`: says callers check the whole playlist and that `allPlayersReported` asks for every track, but lines 92-94 and 148-149 say only the item and its first track.
  - `Modules/AudioRPG/Audio/MediaPlayerManager.swift:28-29`: says `handleItemChange` runs every second; that is `handlePlaybackChange`.
- **Action:** Rewrite each comment to match current behaviour, or delete it.
- **Severity:** Low

### 9.14 Stale comments in the GameRPG controllers name symbols that no longer exist
- **Locations:**
  - `Modules/GameRPG/Controller/MasterController.swift:261-275`: speaks of "three independent call sites" (there are now seven) and names `GameRootModel.sharingControlActions`, which is gone.
  - `Modules/GameRPG/Controller/MasterController.swift:277-286`: names `fulfillPendingAudioPlay` and `continuePendingAudioPlays()`; the current symbols are `deliverPendingAudio` and `startCompletePendingAudioPlays`.
  - `Modules/GameRPG/Controller/MasterController+FileMessageSupport.swift:79`: lists the callers but omits AudioMessages:49.
  - `Modules/GameRPG/Controller/PlayerController+MessageProcessing.swift:259-260`: calls the loop the "only caller", but `receivedProcess` also calls it.
  - Two comments reference `deliveryMessagesByWireID`, which no longer exists.
- **Why:** These are the ordering rationales future fixes will rely on.
- **Action:** Update them to the current symbols.
- **Severity:** Low

### 9.15 Oversized files that mix responsibilities
- **`Modules/AudioRPG/Controller/GameController.swift` (503 LOC).** It mixes the `AudioGameStorable` protocol, report tracking, playlist resolution, play-command application, list exchange, command builders and two wire structs. Split into `AudioGameStorable.swift`, `GameController+Reports.swift`, `GameController+Playback.swift` and `AudioPlayRequest.swift`. Severity: Medium.
- **`Modules/AudioRPG/Controller/AudioController.swift` (478 LOC).** Extract lines 110-266 as an `AudioTrackLoader` that can be unit-tested. Severity: Medium.
- **`Modules/GameRPG/Controller/MasterController.swift` (312 LOC).** Most of it is `MasterControllerModel`; move that to `MasterControllerModel.swift`. Severity: Low.
- **`Modules/GameRPG/Controller/PlayerControllerModel.swift` (445 LOC).** Split out `PendingMapUpdateQueue` (lines 204-304) and a `CharacterRejectionPolicy` (lines 351-398). Severity: Medium.

### 9.16 Files named after something else, and types in the wrong folder
- **Locations:** `Modules/AudioRPG/Audio/MediaPlayerManager.swift:15-27`; `Modules/AudioRPG/Audio/PlayerTime.swift:6-9, 34-60`; `Modules/AudioRPG/View/DetailEditorToolBarButtons.swift:11`; `Modules/AudioRPG/Audio/AudioPlayerModel.swift`; `Modules/AudioRPG/Audio/AudioPlayerSession.swift`
- **What:**
  - No `MediaPlayerManager` type exists; the file holds `RemoteCommand` and `MediaPlayerCoordinator`.
  - `PlayerTime.swift` also holds `PlaylistItem`.
  - `DetailEditorToolBarButtons.swift` holds `PlayToolbarButton`.
  - `Audio/` mixes models and controllers with views, against the documented Controller/Model/View layout.
- **Action:** Rename the files after their main type, and move the models and controllers into `Model/` and `Controller/`.
- **Severity:** Low

### 9.17 Naming inconsistencies
- **Locations:**
  - `Modules/AudioRPG/Controller/AudioController.swift:82, 92, 378`: `skip(to:)` seeks, `skipToCurrentItem` is `AudioRootModel.skip(offsetBy:)`, and `resetPlaylist(complete:)` advances to the next track.
  - `Modules/GameRPG/Controller/MasterController.swift:28`: `deliverySessionID` breaks the `Id` convention.
  - `Modules/GameRPG/Controller/PlayerControllerModel.swift:55`: `hasSendPlayer` should be `hasSentPlayer`.
  - `Modules/GameRPG/Controller/PlayerController+Audio.swift:107` vs `PlayerController+Photo.swift:113`: the `masterId` parameter receives the player's own id for audio.
  - `PlaylistItem.artist` holds the item description.
- **Action:** Rename to `seek(to:)`, `skip(offsetBy:)`, `advanceAfterTrackEnd`, `deliverySessionId`, `hasSentPlayer`, `localDeviceId` and `subtitle`.
- **Severity:** Low

### 9.18 Unused imports in the Master/Player controller extensions
- **Locations:** `Modules/GameRPG/Controller/MasterController+PhotoMessages.swift:3-15`, `+PdfMessages.swift:3-15`, `+SpaceMessages.swift:3-15`, `+FileMessageSupport.swift:3-15`, `+GameMessages.swift:3-15`, `+MessageDispatch.swift:3-15`; `PlayerController.swift:16-20`, `+MessageProcessing.swift:16-20`, `+SendMessages.swift:16-20`
- **What:** Most extension files import all ten feature frameworks plus os.log and use at most one; several PlayerController files import AppKit or UIKit without using either.
- **Action:** Trim each file to what it uses (found by a per-file symbol grep; confirm with a build).
- **Severity:** Low

### 9.19 Magic constants
- **Default volume `0.25`** at `Modules/AudioRPG/Audio/AudioPlayerModel.swift:18` and `Modules/AudioRPG/Audio/AudioPlayerBarViewModel.swift:18` (prior §9.10, still present).
- **Speaker-icon thresholds `0.33/0.66`** at `Modules/AudioRPG/Audio/AudioPlayerVolumeControl.swift:80-88`. That check also tests `isMuted || volume == 0`, the same condition twice.
- **KVO buffer `8` (twice), the 1 s observer interval and `preferredTimescale: 600`** at `Modules/AudioRPG/Controller/AudioController+Observation.swift:28, 39, 84` and `Modules/AudioRPG/Controller/AudioController.swift:101`.
- **`0.001` duration fallback** at `Modules/AudioRPG/Audio/AudioPlayerView.swift:243`.
- **Scrubber `minWidth 38` (twice)** at `Modules/AudioRPG/Audio/AudioPlayerScrubberView.swift:28, 56`.
- **Character back-off `5 * (1 << 2n)`** at `Modules/GameRPG/Controller/PlayerControllerModel.swift:357-360`.
- **Popover geometry** at `Modules/AudioRPG/Audio/PlayerVolumeView.swift:11, 37, 57-59`.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Make "the game's current audio" one piece of state on the master.** §5.1, §3.1, §3.6, §5.4, §7.3 and §7.4 come from the same design: pending plays, retries and deliveries are each tracked per item id with independent tasks. A single `GameAudioState` on `MasterControllerModel` would fix them together. It would hold the latest requested play, its delivery task and its retry state, plus a per-player failure count. Any new play or pause replaces or clears it, and `forget(playerId:)` / `stop()` tear it down in one call.
2. **Give every UI surface one playback entry point.** §5.3, §5.5, §8.2, §8.3, §9.2 and §9.1 all exist because views call `AudioController` directly or hand-roll their own decisions. Route every view through `AudioRootModel+Playback`:
   - extend it with `playItem(id:)` and `playTrack(id:)`;
   - have it decide between game and local, and between track and root;
   - forbid views from calling `audioController.togglePlay` / `skip(to:)` directly.
3. **Separate "is it here?" from "fetch it".** §7.1 and §5.11 come from `hasDownloadedData`, which has a download side effect, being used for availability scans. Add a side-effect-free query in `FileUrlDataController`. Use it for every list/report scan in CoreRPG `FileVersionGameControllable` as well as AudioRPG, and start downloads only for items being played or shared.
4. **Clean up per-player state on leave in one place.** §5.2, §3.6 and parts of §6.3 exist because each per-player structure (`characterOwnership`, list counters, pending value updates, report maps, retry state) has its own reset path. One `MasterControllerModel.forget(playerId:)` that every structure registers with would prevent the next one from being missed.
5. **Track the user's play intent with a generation counter.** §3.3, §3.4, §5.12 and §3.5 are "resume after an await without re-checking" bugs. A `playbackGeneration` on `AudioPlayerModel` would close all of them. Bump it on pause, interruption begin and replace, and check it after every await in play paths.
6. **Collapse the file-backed module copies.** §9.3, §9.4, §9.5 and §9.7 together account for roughly 40 near-identical methods across Master/Player. A `FileBackedModuleAccess` table keyed by `NetworkModules` would turn adding a module, or fixing a counter rule such as §6.4, into a one-place change.

---

## 11. What was NOT audited

- `Modules/GameRPG` outside `Controller/Master*` and `Controller/Player*`: Network transport, SharePlay controller internals, Table3D, BattleRound, ExternalScreen and GameViews were read only where a finding's trace passed through them.
- `CoreRPG` beyond the cited lines (`FileUrlDataController`, `GameControllable`, `FileVersionGameControllable`).
- The AudioRPG App Intents (`Intent/`) got only a light pass for playback ordering (§3.3, §7.2); intent metadata, entities and Spotlight indexing were not re-audited (see `Docu/CODE_AUDIT_AppIntents*.md`).
- CoreData model, migrations and CloudKit schema of the Audio entity.
- Tests (`Tests/AudioRPGTests`, `Tests/AudioRPGSnapshotTests`, GameRPG tests): used only for cross-referencing symbol usage, with no coverage review.
- Runtime behaviour: nothing was run on a device or simulator. §5.7, §5.8, §5.11 and the SharePlay items (§5.9, §6.1) are code-trace findings marked plausible. The macOS Now Playing behaviour (§4.2) and the audio-session interruption of other apps (§5.10) should be confirmed on a device.
- Compiler warnings were captured for the `MasterRPG` scheme only; the `MasterMac` and `MasterTV` schemes were not built for this audit.
- Localization and string catalogs (beyond §8.4), accessibility audits with VoiceOver, and build settings.

---

## 12. Verification

The High findings were opened and traced by hand during the audit; the lines below prove each claim.

- **§5.1:** open `Modules/GameRPG/Controller/MasterController+AudioMessages.swift`.
  - Line 122 writes `pendingAudioPlays[data.id]` only for the requested id, and line 117 clears only that id on a pause.
  - Lines 144-148 broadcast every complete pending entry.
  - Line 26 runs that loop on every `.ok`.
  - Line 166's comment assumes a newer play would have removed the entry; nothing does that for a different id.
- **§5.2:** open `Modules/GameRPG/Controller/MasterController.swift`.
  - Lines 158-169 (`forget`) don't touch `characterOwnership` (line 57).
  - Line 112 rejects a new sender for an already-bound Character.
  - In `Modules/GameRPG/Root/GameRoot.swift:476-477, 487` each `startGame` mints `PlayerGameModel(id: UUID())`.
  - The only clear is `MasterController+Control.swift:50` in `stop()`.
- **§5.3:**
  - `Modules/AudioRPG/Controller/AudioController.swift:131-146` (`add(replace:)`) clears the playlist and player item but not `currentItem`.
  - `:66-79`: `togglePlay(id:)` with `id == currentId` falls to `toggle()` → `play()` on an empty player.
  - The callers are `Modules/AudioRPG/Audio/SharingActionView.swift:77-78` and `Modules/AudioRPG/View/DetailEditorToolBarButtons.swift:19-20`.
  - Compare the documented workaround at `Modules/AudioRPG/Controller/GameController.swift:231-235`.
- **§7.1:**
  - `Modules/AudioRPG/Controller/GameController.swift:337-339, 347-348` loops over all `itemDataModel.items` and awaits `hasLocalDatabaseAudioData`, which (lines 155-161) calls `hasDownloadedData`.
  - `Modules/CoreRPG/Files/FileUrlDataController.swift:271-273` calls `isDownloadedOrLocal`.
  - Line 321 there calls `startDownloadingUbiquitousItem` for every evicted file.

Medium findings that were also checked against the code:

- **§5.5:** `Modules/AudioRPG/Root/AudioRootModel+Playback.swift:13` and `Modules/AudioRPG/Controller/GameController.swift:428` (`AudioPlayRequest(id: id, …)` has no `trackId`), with the reload at `:218, 227`.
- **§5.6:** `Modules/AudioRPG/Controller/AudioController.swift:383-395`. The local branch runs whenever `loopReplayHandler` is `nil`, which it always is on a player (`MasterController+AudioMessages.swift:81`).
- **§5.10:** `grep -rn setActive Modules/AudioRPG` finds only `setActive(true)` (`AudioPlayerSession.swift:113`).
- **§8.1 / §9.1:** `grep -rlw "AudioPlayerView\|PlayListView\|RoutePickerView" Modules Sources` returns only their own files and `MenuBarAudioPlayerView.swift`'s doc comment.

If any finding doesn't reproduce when you visit the line, send me its §-number and I'll investigate it again.

---

## 13. Fix status (2026-11-07)

Builds: MasterRPG (iOS, visionOS), MasterMac, MasterTV succeed. AudioRPGTests, CoreRPGTests and GameRPGTests pass except `AudioPlaylistGameFlowTests` "A player that joins later…", which fails intermittently on the unchanged baseline too. Nothing was run on a device.

**Fixed:** §3.1, §3.2, §3.3, §3.4, §3.5, §3.6, §3.9, §3.10, §4.2, §5.1–§5.12, §5.14–§5.17, §6.3 (capped, not filtered), §6.5, §6.6, §7.1, §7.2, §7.3 (in-flight dedupe), §7.4, §7.5, §8.1, §8.3, §8.4, §8.5, §8.7, §9.1, §9.2 (play entry points), §9.13, §9.14 (the listed comments), parts of §9.19.

**Refactor batch (same day, with tests):** §5.13, §7.6, §8.2, §8.6, §8.8, §8.9, §9.3–§9.12 and §9.15–§9.18 are done unless noted below. Builds: MasterRPG (iOS, visionOS), MasterMac and MasterTV succeed; the full MasterRPG test run passes except the same intermittent "A player that joins later…" test (the SharePlay "receiver expires abandoned streams" test and a few audio flow tests also flaked under parallel load but pass alone).

- §5.13: `ItemGameModel.recordMasterVersion` drops a player's reports when the master's version of an item changes; the master records its version before a play and ignores a receipt for another version. Audio receipts now keep their version (`PlayerController.response`).
- §7.6: the audio share button sends only the reference; `PlayerController.shareFile` exports when the master lacks the item, and logs a failed export.
- §8.2: shared `AudioTransportButton(kind:)` replaces the three hand-built copies (play is disabled on an empty playlist everywhere, "Next Track" everywhere, hints everywhere); the menu bar reuses `AudioPlayerRepeatButton`. No `AudioCurrentTitle` was needed: the title helper only existed in the deleted `AudioPlayerView`.
- §8.6: one `AudioPlayerTimelineLayersView` with a tap trigger (iOS) and a hover modifier (macOS, visionOS).
- §8.8: views read `playerTime.elapsedSeconds`; a seek updates it at once.
- §8.9: `PlayerVolumeView` no longer measures itself; an alignment guide places the popover.
- §9.3: `ListSequenceTracker`. §9.4/§9.5: `FileBackedModuleAccess` with generic master/player handlers for Photo, Pdf and Space and the routing switches driven from it (Pdf has no sharing flag, as before); `GameNetworkModel.isReportListEnvelope`.
- §9.6: `play(_:)` and the loaders share `loadPlaylist(id:list:…)`. §9.7: `hasLocalAudioData` removed, `holdsFile` in `PlayerController+FileSupport.swift`. §9.8: `acceptAudio(_:)`.
- §9.9: `MasterControllerModel.asProxy`, `PlayerControllerModel.messageCounter`, `ItemGameReportable` and the models' `players` removed. §9.10: dead overloads, parameters and `gameView(root:)` stubs removed (`InlineRowViewer.destination` of the Audio module too).
- §9.11: shared `itemDataCleanup`/`checkFolders`/`validateLinks` on `ItemRootControllable` (Character keeps its own `checkFolders`), `EntitySyncDataController`, `ModuleLinkRootView` (Rule and Table keep their own link views, which differ), simplified `attributeSet()`.
- §9.12: `GameMessagePipeline.enqueueAndLog` and `handOffBacklog`; the master's `received`/`receivedProcess` trampolines are gone (the player's `receivedProcess(_:fromProxy:)` stays, its tests and callers use it).
- §9.15: `AudioGameStorable.swift`, `GameController+Playback.swift`, `AudioPlayRequest.swift`, `AudioTrackLoader` (tested), `MasterControllerModel.swift`, `PendingMapUpdateQueue`, `CharacterRejectionPolicy` (both tested).
- §9.16: `MediaPlayerCoordinator.swift`, `PlaylistItem.swift`, `PlayToolbarButton.swift`; models and controllers moved out of `Audio/`.
- §9.17: `seek(to:)` (async one: `seekAndWait(to:)`), `skip(offsetBy:)`, `advanceAfterTrackEnd`, `deliverySessionId`, `hasSentPlayer`, `localDeviceId`, `PlaylistItem.subtitle`.
- §9.18: the feature-framework, `os.log`, AppKit and UIKit imports of the Master/Player extension files are trimmed to what the build needs.

**Not done:**
- §3.7, §3.8, §4.1 (Combine KVO bridge; only the unused imports and `@ObservationIgnored` went), §6.1, §6.2, §6.4 (the test fixtures send counter 0).
- §6.1 and §6.2 also need a decision first. Audio is not part of `FileBackedModuleAccess` (its master handler has the pending-play logic); the `LinkRootView` of Rule and Table was not unified.
- Nothing was run on a device; the new UI (transport buttons, timeline, volume popover) was only built, not looked at.
