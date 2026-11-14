# AudioRPG audit (2026-11-14)

Scope: all of Modules/AudioRPG (68 Swift files, 6,524 LOC) read in full except `PreviewData`/`MockData` fixtures (skimmed): controllers (AudioController, +Observation, AudioPlayerSession, MediaPlayerCoordinator, AudioListenerCoordinator, AudioTrackLoader, GameController, GameController+Playback, Data/Item/Export/Link/Sheet controllers), models, root models, all intents, and all views. Cross-checked against Docu/CODE_AUDIT_Audio.md, CODE_AUDIT_Audio2.md (§13 status), CODE_AUDIT_Game_Photo_Audio.md and CODE_AUDIT_25.md; nothing already marked Fixed / By design / Won't fix is re-reported. Overall health is good: no Critical or High finding survived verification. The playback core (generation counters, cancel-then-replace loads, ordered track loading, throttled Now Playing writes) is carefully built and every CLAUDE.md API rule checked (no GCD, no `foregroundColor`, no `onTapGesture`, no `GeometryReader`, no ObservableObject, `bundle: .module` everywhere) is respected. What is left is a handful of real behavioural gaps in less-travelled entry points (play link on a playlist, intent start/remove gating, stale UI state after a failed load), an untested audio-session state machine, and small dead-code/perf items.

### Play link on a playlist item outside a game stops the music and plays nothing
- Category: Bug
- Location: Modules/AudioRPG/Controller/LinkController.swift:37-41, Modules/AudioRPG/Controller/AudioController.swift:201-221
- What: The non-game branch of the `play` link calls `audioController.loadAndPlay(id:)`, which loads only the item's own file; a playlist item has `fileUrl == nil` and its tracks are its entries.
- Why: `add(audio:replace: true)` empties the playlist, replaces the AVPlayer item with nil and clears Now Playing; `set(currentId:)` then finds nothing and `preparePlay` bails. Tapping the play link of a playlist (folder-like audio item) in an adventure text silences the current music and starts nothing. The game branch (`requestPlay`) and the row/toolbar buttons (`playItem` -> `GameController.play`) resolve playlists, so only this path is wrong.
- Action: Route the link through `AudioRootModel.toggleItem`/`playItem` (or `GameController.play`) instead of `loadAndPlay`; additionally make `add(replace:)` keep the running player when `requests` is empty.
- Severity: Medium
- Status: NEW

### Intent start and playlist-row removal ignore the "can control game audio" gate
- Category: Bug
- Location: Modules/AudioRPG/Root/AudioRootModel+Playback.swift:135-141 (`startPlayback`), 159-164 (`remove`); every other entry point folds in `IntentGameContext.canControlGameAudio()` (lines 18, 50, 64, 83, 110, 122, 147)
- What: `startPlayback(id:isGameRunning:networkActions:)` (used by `PlayAudioIntent.playFromIntent`) and `remove(id:...)` use the raw `isGameRunning` flag.
- Why: On a player device with audio sharing off the game drops the player's play command (doc on `canControlGameAudio`, CODE_AUDIT_Audio2 §5.14), so "Play <audio>" through Siri/Shortcuts does nothing while the dialog still answers "Playing ...". The pause that `remove` sends is dropped the same way.
- Action: Apply the same `&& IntentGameContext.canControlGameAudio()` fold at the top of both functions (and add a case to `AudioIntentGameTests`).
- Severity: Medium
- Status: NEW

### Audio-session state machine (interruption, route change, media-services reset) has no tests
- Category: Test gap
- Location: Modules/AudioRPG/Controller/AudioPlayerSession.swift:201-247, Modules/AudioRPG/Controller/AudioController.swift:355-412, Modules/AudioRPG/Controller/MediaPlayerCoordinator.swift:94-117
- What: No test in Tests/ references `AudioPlayerSession`, `handleInterruption`, `resetMediaService` or `MediaPlayerCoordinator` (grep over Tests is empty); only the remote-command and transport layers are covered.
- Why: The interruption generation counters, `wasPlaying` hand-off, `isActive` bookkeeping, observer re-creation after a reset and the Now Playing throttle (`positionTolerance`) are exactly the code with await gaps and subtle ordering; the findings below were visible only by reading.
- Action: Make the delegate calls injectable (the delegate protocol already is) and test: began/ended with and without `.shouldResume`, a second `.began`, reset while playing; test `handlePlaybackChange` throttle with a fake clock.
- Severity: Medium
- Status: NEW

### Failed or discarded playlist load leaves a stale `currentItem` pointing at a deleted track
- Category: Bug
- Location: Modules/AudioRPG/Controller/AudioController.swift:147-199 (`add(audio:replace:)`), 270-274 (`preparePlay`), Modules/AudioRPG/Controller/GameController+Playback.swift:86-91
- What: `add(replace: true)` empties `playList`, deletes the temp copies and empties the player, but never clears `model.currentItem`; the comment at GameController+Playback.swift:88-91 only patches the success path.
- Why: If the new load fails (offline iCloud file, failed copy) or is superseded, the player bar keeps showing the old title as "current" with an empty playlist: `currentIndex` is nil, prev/next/play are disabled, Now Playing is cleared, yet the title stays. `togglePlay`/`toggle` with that stale id then do nothing.
- Action: Clear `currentItem` (and `isPlaying`-dependent UI state) inside `add(replace: true)` together with the playlist, as `removeAudio` already does for the current track.
- Severity: Low
- Status: NEW

### Play failures are silent and the playback intents always answer "Playing"
- Category: Bug
- Location: Modules/AudioRPG/Controller/GameController+Playback.swift:19-65, 72-99 (`play`/`loadPlaylist` return Void; `play` is `throws` but nothing throws), Modules/AudioRPG/Intent/AudioPlaybackIntents.swift:44-45, 96-99, 125-126, Modules/AudioRPG/Root/AudioRootModel+Playback.swift:39-45
- What: `audioController.add(...)`'s `false`/empty result is dropped, `play` never reports it, `playItem` logs only thrown errors (there are none), and the intents build their dialog from the target name regardless of outcome.
- Why: Hands-free at the table (Siri, AirPods) an audio whose file is not downloadable offline plays nothing while the assistant says "Playing "<name>"". The in-app buttons give no hint either.
- Action: Return a result (or throw `AudioEntityAssetUnavailableError`-style) from `loadPlaylist`/`play` when nothing could be loaded, and have the intents answer accordingly; optionally surface a banner in the UI.
- Severity: Low
- Status: NEW

### `setInactive` and `setActive` run as unordered @concurrent tasks
- Category: Concurrency
- Location: Modules/AudioRPG/Controller/AudioPlayerSession.swift:96-115, 151-168
- What: `deactivate()` flips `isActive = false` and fires `Task { await setInactive() }`; a following `activate()` fires `setActive()` from another task. Both are `@concurrent`, so nothing orders them.
- Why: Track ends -> `advanceAfterTrackEnd(complete:)` deactivates; if the user taps Play within a few ms, `setActive(true)` can run before `setActive(false)`, leaving the session inactive while the model says `isActive == true` (so `needsActivation` is false for every later play).
- Action: Keep one serial chain (store the last session task and await it in `activate()`/`deactivate()`), or route both calls through a single actor.
- Severity: Low
- Status: NEW

### `isActive` stays true after the system deactivated the session on an interruption
- Category: Bug
- Location: Modules/AudioRPG/Controller/AudioPlayerSession.swift:222-238, 78-84
- What: On `.began` the system deactivates the session but `model.isActive` is kept; when the interruption ends without `.shouldResume` nothing re-activates.
- Why: The next user Play passes `needsActivation == false` and calls `player.play()` without `setActive(true)`; whether AVPlayer self-activates is system-dependent (not verified on device).
- Action: Reset `isActive = false` on `.began` (the resume path already calls `setActive`).
- Severity: Low
- Status: NEW (unverified on device)

### Lock screen, Now Playing and player bar show the item's raw description as album/artist
- Category: Bug
- Location: Modules/AudioRPG/Controller/AudioController.swift:171-179 (`subtitle: item.description`), Modules/AudioRPG/Controller/MediaPlayerCoordinator.swift:66, Modules/AudioRPG/Audio/SongInfoView.swift:21, Modules/AudioRPG/Audio/AudioPlayerMiniBarView.swift:98
- What: The subtitle of a `PlaylistItem` is the audio item's whole markdown description (including generated link syntax and GM notes added by `AddAudioNoteIntent`).
- Why: `MPMediaItemPropertyAlbumTitle` and the bar's second line then carry raw `[..](RPG://..)` text or multi-line notes; the lock screen/Control Center/AirPlay receivers show GM-side notes on the device that is playing.
- Action: Use the first line of `description.withoutLink()` (or plain text) with a length cap for the subtitle, keep the full text out of system Now Playing.
- Severity: Low
- Status: NEW

### Play link label ignores which item is playing in a game
- Category: Bug
- Location: Modules/AudioRPG/Controller/LinkController.swift:26-31 versus 38-40
- What: In a game the link text becomes "playing"/"pause" from `audioController.model.isPlaying` alone; the non-game branch (and `requestPlay`, which uses `isPlayingPlaylist`) checks that the item itself plays.
- Why: With another track playing, tapping the link of a different audio starts that audio (`shouldPlay: true`) but writes "pause" into the text, so the shared link state is wrong until the next toggle.
- Action: Use `gameController.isPlayingPlaylist(id: itemId)` for `isPlaying` in the game branch.
- Severity: Low
- Status: NEW

### Row play button never shows "playing" for a playlist item
- Category: Bug
- Location: Modules/AudioRPG/Audio/AudioPlayPauseButton.swift:48-50, 41-44
- What: `isCurrentlyPlaying` compares `currentId == itemId`; `currentId` is the active track, while a playlist item is the root (its own `fileUrl` is nil).
- Why: Playing a playlist from its row shows the "play" icon and label while it plays; tapping it does pause (via `isPlayingPlaylist`), so icon and behaviour disagree. The detail-view `SharingActionView.playIcon` already uses `isPlayingPlaylist`.
- Action: Use `root.gameController.isPlayingPlaylist(id:)` for the icon and accessibility label.
- Severity: Low
- Status: NEW

### `waitForSharing` can fire a play long after the tap
- Category: Bug
- Location: Modules/AudioRPG/Audio/SharingActionView.swift:51, 60-67, 72-77
- What: Tapping play while not all players hold the file sets `waitForSharing = true`; it is only cleared when `allReported` flips to true.
- Why: If the missing player never reports (leaves, fails) and a later, unrelated report/roster change makes `allReported` true, the audio starts for everyone without a fresh tap. There is no timeout and no reset on `onDisappear`/new share.
- Action: Clear the flag after a deadline, on disappear, and when another play/pause command is issued; or keep the pending play in the controller with an expiry.
- Severity: Low
- Status: NEW

### Embedded artwork is decoded on the main actor
- Category: Performance
- Location: Modules/AudioRPG/Model/AudioPlayerBarViewModel.swift:40-45, 74-79
- What: `loadAlbumArtwork` runs in a main-actor Task and `Self.artworkImage(from:)` (ImageIO thumbnail decode up to 1024 px) executes after the `@concurrent` data fetch, on the main actor.
- Why: Every track change decodes a JPEG/PNG thumbnail on the main thread (per visible bar: full bar, mini bar, toolbar popover each own a view model). Short hitches while skipping tracks with large embedded art. CODE_AUDIT_25 §8.3 fixed the size but not the thread.
- Action: Do the downsampling inside the `@concurrent` function and return a `CGImage`/Sendable result, building `Image` on the main actor.
- Severity: Low
- Status: NEW

### `appIconImage()` rebuilt in every body evaluation
- Category: Performance
- Location: Modules/AudioRPG/Audio/AudioPlayerTimelineView.swift:150, Modules/AudioRPG/Audio/AudioPlayerMiniBarView.swift:83, Modules/AudioRPG/Model/AudioPlayerBarViewModel.swift:87-103
- What: The fallback artwork reads the Info.plist icon dictionaries and creates a `UIImage` (or NSApplication icon) each time the content view re-evaluates (scrubber show/hide, artwork load, item change).
- Why: Needless plist/image work on the main thread during a hover/blur animation.
- Action: Cache the image in a static let (or in the view model once).
- Severity: Low
- Status: NEW

### `hasAudio(itemId:)` walks the folder subtree inside view bodies
- Category: Performance
- Location: Modules/AudioRPG/Controller/ItemController.swift:35-39; callers Modules/AudioRPG/Audio/AudioPlayPauseButton.swift:22, Modules/AudioRPG/Audio/SharingActionView.swift:90, Modules/AudioRPG/View/PlayToolbarButton.swift:27
- What: For folders/playlists `hasAudio` recurses over every descendant (depth-limited) each time a row's body runs.
- Why: A list of large folders pays an O(subtree) walk per row per invalidation (every `isPlaying` change invalidates the row button).
- Action: Compute lazily per folder (e.g. a cached flag keyed by item version) or read it from the list model once.
- Severity: Low
- Status: NEW

### Per-message cap does not bound the master's cumulative `playerReports`
- Category: Security
- Location: Modules/AudioRPG/Controller/GameController+Playback.swift:287-302, 322
- What: A player list adds up to 5,000 unknown item ids per message, and the loop re-assigns every existing key (including ones left as `[]`); keys are never pruned.
- Why: Repeated lists with fresh random ids grow the map without bound and every message costs O(keys). Trusted-player model, so Low.
- Action: Drop keys whose player array becomes empty and that are not in `itemDataModel.items`.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_Audio2 §6.3] (capped per message only)

### Combine kept as a Task container; artwork task still unstructured
- Category: API
- Location: Modules/AudioRPG/Controller/AudioController+Observation.swift:57-61 (and `import Combine`, `.buffer`, `publisher(for:)` at 26-44), Modules/AudioRPG/Model/AudioPlayerModel.swift:112-129, Modules/AudioRPG/Model/AudioPlayerBarViewModel.swift:40, Modules/AudioRPG/Audio/AudioPlayerTimelineView.swift:87-89
- What: Tasks are wrapped in `AnyCancellable`s only to reuse `Set<AnyCancellable>`; KVO is bridged via Combine publishers; artwork loads start an unstructured Task from `.task(id:)`.
- Why: CLAUDE.md prefers Swift-native concurrency; the artwork task is cancelled on disappear so the leak risk is small.
- Action: Store `[Task<Void, Never>]` in the model and bridge KVO through an `AsyncStream`; make the artwork load a `.task(id:)` body that awaits a `@concurrent` function.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_Audio2 §3.7/§4.1; CODE_AUDIT_25 §4.1]

### Transferable file export labels every audio file as MPEG-4 audio
- Category: Bug
- Location: Modules/AudioRPG/Intent/AudioEntity.swift:101-106
- What: `FileRepresentation(exportedContentType: .mpeg4Audio)` is returned for whatever file the item holds (module accepts `.audio`: mp3, wav, aiff, flac, ...).
- Why: Shortcuts/Share targets that trust the declared type may mis-handle an mp3/wav delivered as `.mpeg4Audio`.
- Action: Derive the content type from the file's extension (`UTType(filenameExtension:)`) or export with `.audio`.
- Severity: Low
- Status: NEW

### Dead code and leftovers
- Category: Dead code
- Location: Modules/AudioRPG/Controller/ItemController.swift:41-48 (`audioList(itemId:)` has no caller anywhere in Modules/Sources/Tests); Modules/AudioRPG/Resources/Localization+Extensions.swift:5-15 (`Bundle.localizedString(forKey:)`, `String.localizedString` unused in AudioRPG); Modules/AudioRPG/Audio/PlayerTime.swift:13,23 (`remainingText` never read); Modules/AudioRPG/Model/AudioPlayerModel.swift:17-19 (`currentTime` read only by GameRPG tests of another type); Modules/AudioRPG/Audio/AudioPlayerMiniBarView.swift:14 (`tabViewBottomAccessoryPlacement` declared on the outer view, never used, causes extra invalidation); Modules/AudioRPG/Model/AudioEntryModel.swift:16 (`displayState` is encoded on the wire but never persisted by `DataController.map`, and dropped by `merge`/`duplicate`)
- What: Unreferenced members/state (verified by grep across Modules, Sources, Tests).
- Why: Noise and a misleading field (`AudioEntryModel.displayState` suggests per-entry hiding that does not survive a save).
- Action: Delete the first four and the unused environment value; remove `displayState` from `AudioEntryModel` or persist and merge it.
- Severity: Low
- Status: NEW

### Minor style deviations
- Category: SwiftUI
- Location: Modules/AudioRPG/Audio/AudioPlayerTimelineView.swift:36 (mis-indented `AudioPlayerTimelineLayersView(`), Modules/AudioRPG/Audio/AudioPlayerVolumeControl.swift:67 (`Rectangle()` instead of `.rect`), Modules/AudioRPG/Audio/RoutePickerView.swift:24 (`.systemTeal` UIKit colour), Modules/AudioRPG/Model/AudioEntryModel.swift:21 (hard-coded unlocalised "Track" as entry name), Modules/AudioRPG/Controller/ViewController.swift:16-29 (`AnyView`, mandated by `ViewControllable`)
- What: Small deviations from CLAUDE.md that the compiler does not flag.
- Why: Consistency; the "Track" string would be shown untranslated if a generic list ever renders `EntryDataAccessible.name`.
- Action: Fix opportunistically; leave the `AnyView` until the protocol changes.
- Severity: Low
- Status: NEW

Not audited in this area: runtime behaviour on device (AirPlay routes, interruption recovery, Now Playing UI, visionOS ornaments); the CoreRPG pieces AudioRPG delegates to (`GenericEditController`, `GenericImportController`, `FileUrlDataController`, `ItemEntityQuery`, `ModuleLinkRootView`, `IntentGameContext` internals); GameRPG-side audio messaging (covered by CODE_AUDIT_Game_Photo_Audio and CODE_AUDIT_Audio2); the Preview/Mock fixtures (project-wide convention) and snapshot tests; localization catalog completeness.
