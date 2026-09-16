# MasterRPG — AudioRPG Module Code Audit

Generated 2026-09-16. Scope: `Modules/AudioRPG/` only — 62 Swift files, ~5,266 LOC, plus the `RPGAudio` Core Data model. No `Dead/` or archived directory exists inside this module.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made. This module has clearly been through prior audit passes (inline comments reference `CODE_AUDIT §7.1`, `CODE_AUDIT_Game §4.2`, `§9.1`), which shows in the results below: **zero force-unwraps, zero `try!`/`as!`/`fatalError`, zero `print`/debug-logging leaks, zero TODO/FIXME markers, and a clean Swift 6 strict-concurrency build** (verified — see §3). Findings below are the real remaining issues.

---

## 1. Executive summary

1. **[High] `PlayListView` sends the wrong network action type, so other players never receive play/pause/delete requests during a live game** — §5.1 — `Modules/AudioRPG/Audio/PlayListView.swift:27,49`
2. **[High] `isPlaybackComplete` flag is never cleared, so pause/resume permanently restarts every track from 0:00 after any playlist finishes once** — §5.2 — `Modules/AudioRPG/Controller/AudioController.swift:44,204-216,334-343`
3. **[High] Deleting the current-but-paused track leaves the player pointed at a removed item, permanently breaking Next/Previous** — §5.3 — `Modules/AudioRPG/Controller/AudioController.swift:188-198`
4. **[High] `GameController`'s data-fallback path writes a `.mp4` extension on `.m4a`-encoded audio, diverging from `AudioController`'s equivalent path** — §9.2 — `Modules/AudioRPG/Controller/GameController.swift:181` (vs. `AudioController.swift:161`)
5. **[Medium] Timeline scrubber issues an unthrottled seek `Task` per drag frame at whole-second precision** — §7.1 — `Modules/AudioRPG/Controller/AudioController.swift:78-82`, `Modules/AudioRPG/Audio/AudioPlayerScrubberView.swift:26-32`
6. **[Medium] `AudioController`/`GameController` lack explicit `Sendable` conformance despite being stored in `Sendable`-conforming types** — §3.1 — `Modules/AudioRPG/Controller/AudioController.swift:10`, `Modules/AudioRPG/Controller/GameController.swift:30,42`
7. **[Medium] Playlist tracks load strictly sequentially instead of concurrently, multiplying per-track iCloud/copy latency by track count** — §7.2 — `Modules/AudioRPG/Controller/AudioController.swift:115-119`
8. **[Medium] `GameController.audioAsset(for:)` is unreferenced dead code missing the `@concurrent` safeguard its sibling relies on** — §9.1 — `Modules/AudioRPG/Controller/GameController.swift:155-189`
9. **[Medium] The same four App-Intent helper functions are duplicated verbatim across ~10 modules** — §9.3 — `Modules/AudioRPG/Intent/AudioManagementIntents.swift:147-184`
10. **[Low] `isScubberVisible` typo (missing "r") propagated to 9 call sites** — §8.1 — `Modules/AudioRPG/Audio/AudioPlayerBarViewModel.swift:16`

---

## 2. Quick wins (≤30 min each)

- **Fix the `.generic` → `.playAudio` action-type bug** — `Modules/AudioRPG/Audio/PlayListView.swift:27,49`. One-word change per call site; see §5.1.
- **Fix the `"mp4"` → `itemController.config.filenameExtension` mismatch** — `Modules/AudioRPG/Controller/GameController.swift:181`. Matches the already-correct sibling at `AudioController.swift:161`; see §9.2.
- **Delete `GameController.audioAsset(for:)`** — `Modules/AudioRPG/Controller/GameController.swift:155-189`. Zero call sites repo-wide; see §9.1.
- **Remove the dead `guard !models.isEmpty else { return }`** — `Modules/AudioRPG/Controller/AudioController.swift:178-179`. `models` is a single-element array literal and can never be empty; see §5.4.
- **Rename `isScubberVisible` → `isScrubberVisible`** — `Modules/AudioRPG/Audio/AudioPlayerBarViewModel.swift:16` + 9 references in `AudioPlayerTimelineView.swift`; see §8.1.
- **Fix "santity checks" comment typo** — `Modules/AudioRPG/Model/AudioModel.swift:161`.
- **Delete the dead commented-out Now Playing artwork line** — `Modules/AudioRPG/Audio/MediaPlayerManager.swift:42`. References an undefined `image`/`AKImage`; see §9.5.
- **Collapse the identical `#if os(macOS)`/`#else` branches** — `Modules/AudioRPG/Audio/AudioPlayerVolumeControl.swift:93-117`; see §9.6.
- **Replace the raw `!= 2` sentinel with `DisplayStateMask.totalHidden.rawValue`** — `Modules/AudioRPG/Controller/LinkController.swift:68`. The module's own `AudioRootModel.swift:186` already uses the named form for the identical check; see §8.4.
- **Rename `audioURL` → `audioUrl`** — `Modules/AudioRPG/Model/PreviewData.swift:106`. Sole `Url`-casing exception found in the module (preview-only, trivial); see §8.5.

---

## 3. Concurrency

A clean `xcodebuild -scheme AudioRPG clean build` (Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, confirmed via `-showBuildSettings`) produced **zero Swift compiler warnings or errors** — only two unrelated `appintentsmetadataprocessor` tooling notes ("Metadata extraction skipped, no AppIntents.framework dependency found"), expected when building the framework target in isolation from its hosting app. This is the canonical ground truth for this section: AudioRPG's declared concurrency surface currently compiles clean under the project's strictest settings. A full-module grep also confirmed **zero** occurrences of `DispatchQueue`, `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject`/`@EnvironmentObject`, `Task.sleep(nanoseconds:)`, legacy `Formatter` subclasses, `Task.detached`, `nonisolated(unsafe)`, sub-26 `@available` guards, and `NSMetadataQuery`. All `@Observable` classes (`AudioModel`, `AudioPlayerModel`, `AudioPlayerBarViewModel`, `AudioListenerCoordinator`, `AudioRootModel`) are correctly `@MainActor`-annotated.

### 3.1 `AudioController`/`GameController` lack explicit `Sendable` despite being stored in `Sendable`-conforming types
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerModel.swift:7-8` (contrast); `Modules/AudioRPG/Controller/AudioController.swift:10` (`final class AudioController`, no conformance); `Modules/AudioRPG/Controller/GameController.swift:30,42` (`struct GameController: Sendable` storing `let audioController: AudioController`); `Modules/AudioRPG/Controller/LinkController.swift:8,10`
- **What:** `AudioController` is a plain `final class` with no `Sendable` conformance, yet it is stored as `let audioController: AudioController` inside `GameController: Sendable` and `LinkController: Sendable`, and conforms to `AudioPlayerSessionDelegate: Sendable`/`RemoteCommandHandler: AnyObject, Sendable`. The sibling type in the same file family, `AudioPlayerSessionModel`, does this correctly (`@MainActor final class AudioPlayerSessionModel: Sendable`).
- **Why:** Verified empirically — a clean build under the project's actual Swift 6 language-mode settings does **not** currently flag this (no Sendable diagnostic appears anywhere in the build log for `AudioController.swift`), so this is not an active or imminent build break as such. It is, however, an inconsistency against the project's own established pattern (`AudioPlayerSessionModel: Sendable`) and leaves the guarantee implicit rather than compiler-checked — a future refactor that changes how these types are consumed could silently lose safety with no warning.
- **Action:** Add explicit `Sendable` conformance to `AudioPlayerModel` and `AudioController` (both are legal since each is effectively MainActor-isolated) purely for consistency and defense-in-depth, not because the build currently requires it.
- **Severity:** Medium *(downgraded from a subagent's initial High — the "future hard build error" framing did not hold up against an actual clean-build test; see verification note)*.

### 3.2 `AudioEntity` Sendable gap papered over with `@preconcurrency`
- **Location:** `Modules/AudioRPG/Intent/AudioEntity.swift:11-54, 98-119`
- **What:** `AudioEntity` stores `var root: AudioRootModel` and `var model: AudioModel` — both non-Sendable `@MainActor` classes — directly as struct properties, and `AudioEntityQuery`'s conformance to `IndexedEntityQuery` is declared `@preconcurrency` to suppress the resulting diagnostic.
- **Why:** AppIntents/CoreSpotlight indexing (`reindexEntities`, `reindexAllEntities`, `entities(for:)`) can invoke entity machinery from contexts the compiler can't prove are main-actor-confined; `@preconcurrency` hides the warning instead of proving safety. The type already demonstrates the fix pattern itself — `storedName`/`storedDescription` are eagerly captured as plain Sendable strings specifically to avoid touching the `@MainActor` model from nonisolated entity properties — but `root`/`model` aren't given the same treatment.
- **Action:** Drop the stored `root`/`model` references (or wrap access through a Sendable accessor) so `AudioEntity` doesn't need `@preconcurrency` to satisfy `IndexedEntityQuery`.
- **Severity:** Medium

### 3.3 Combine used for player observation alongside modern `Observations` in the same controller
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:250-284` (Combine) vs. `:312-325` (`Observations`)
- **What:** `observePlayback()` subscribes to `model.player.publisher(for: \.timeControlStatus)` and `NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)` via Combine (`.sink`, `Set<AnyCancellable>`), each manually hopping back with `Task { @MainActor [weak self] in ... }` — in the same file where `observeSharedAudio()` uses the modern `Observations` async-sequence API.
- **Why:** Mixes two reactive paradigms in one controller, contrary to the project's async/await-first direction, and requires more manual actor-hopping boilerplate per event than the `Observations`-based sibling right below it.
- **Action:** Replace both Combine subscriptions with `AsyncSequence` equivalents (`Observations` over `player.timeControlStatus`, `NotificationCenter.notifications(named:)` for end-of-item), consistent with `observeSharedAudio()`.
- **Severity:** Medium

### 3.4 Closure-based `NotificationCenter` API for `AVAudioSession` lifecycle events
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerSession.swift:90-115`
- **What:** `registerSessionNotifications()` uses `NotificationCenter.addObserver(forName:object:queue:)` (closure/token API) for route-change, interruption, and media-services-reset notifications, storing tokens in `audioSessionObservers` for manual `removeObserver` cleanup.
- **Why:** This is the pre-async-sequence `NotificationCenter` pattern; it also forces hand-rolled observer-token bookkeeping that the async-sequence API eliminates.
- **Action:** Replace with structured `Task { for await note in NotificationCenter.default.notifications(named:) { ... } }` loops, one per event stream, cancelled together on teardown instead of manually removed.
- **Severity:** Medium

### 3.5 Playback started as a side effect of a plain (non-`.task`) view-builder function
- **Location:** `Modules/AudioRPG/Controller/ViewController.swift:52-77` (`viewAudioPlayer`, `menuAudioPlayer`)
- **What:** Both functions fire `Task { try await root.gameController.play(id: id, shouldPlay: true) }` immediately before returning `AudioPlayerView()`/`AudioPlayerBarView()`. An inline comment already acknowledges this is "fire-and-forget from this synchronous view builder, same as before" and cross-references a prior audit (`CODE_AUDIT_Game §4.2`).
- **Why:** Because this is a plain function (not a `.task(id:)` view modifier), the `Task` is (re-)spawned every time the function is called from a view's `body`, which can re-trigger a play request on every re-render or navigation, and nothing cancels the in-flight `await` if the caller navigates away first. This is a known, previously-flagged tradeoff (not a new discovery) and already has error handling (`do`/`catch`/`Logger`) rather than a silent failure — verified by reading the surrounding code, which is why this is rated below the subagent's initial High.
- **Action:** Move the play request into a `.task(id: id)` modifier on the returned view (or on a wrapping view) so it fires once per identity and is cancelled automatically when the view disappears, if `ViewControllable`'s protocol shape can be adjusted to allow it; otherwise leave as an accepted architectural tradeoff.
- **Severity:** Medium *(downgraded from a subagent's initial High — confirmed via reading the code that this is an already-documented, error-handled, pre-existing tradeoff rather than a fresh silent-failure bug)*.

### 3.6 Interruption/route-change/media-reset handlers spawn independent, unordered Tasks
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerSession.swift:117-154`
- **What:** `handleRouteChange`, the `.shouldResume` branch of `handleInterruption`, and `handleMediaServicesReset` each spawn their own bare `Task { ... }` into the delegate, with no ordering relationship between them.
- **Why:** AVAudioSession can post these notifications in a fast burst (e.g., a call ending while headphones simultaneously disconnect); since each handler's `Task` runs independently, completion order isn't guaranteed to match posting order, which can leave `isPlaying`/session state inconsistent with the actual final device state.
- **Action:** Route session-lifecycle handling through a single serial point (an actor, or a merged `AsyncStream`) so these events are applied in the order `AVAudioSession` posted them.
- **Severity:** Low

### 3.7 `.task(id:)` doesn't actually cancel the artwork-loading Task on view disappearance
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerTimelineView.swift:106-108,144-146`; `Modules/AudioRPG/Audio/AudioPlayerBarViewModel.swift:21-37`
- **What:** `.task(id: currentItem?.id) { viewModel.loadAlbumArtwork(for: currentItem) }` calls a synchronous method that internally spawns its own unstructured `artworkLoadTask`; the `.task` closure itself returns instantly, so SwiftUI has nothing in-flight to cancel.
- **Why:** `artworkLoadTask` is only cancelled the next time `loadAlbumArtwork` is called (i.e., on the next track change), not when the hosting view goes off-screen, so artwork loading for a track no longer visible can keep running.
- **Action:** Cancel `artworkLoadTask` in `onDisappear`, or make `loadAlbumArtwork` itself `async` and call it directly inside the `.task(id:)` closure so SwiftUI's built-in cancellation propagates.
- **Severity:** Low

---

## 4. API modernity

_No findings beyond what's covered in §3._ A full-module grep found no lingering `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject`/`@EnvironmentObject`, no `DispatchQueue`, no legacy `Formatter` subclasses (time formatting already correctly uses `Duration.TimeFormatStyle` in `PlayerTime`/`AudioPlayerScrubberView`), no `Task.sleep(nanoseconds:)`, and no sub-26 `@available` guards. The module has no direct iCloud/`NSMetadataQuery` code of its own — it delegates entirely to `CoreRPG`'s shared `FileUrlDataController`.

---

## 5. Bugs / logic errors

### 5.1 `PlayListView` sends the wrong network action type, so other players never receive play/pause/delete requests
- **Location:** `Modules/AudioRPG/Audio/PlayListView.swift:27,49`
- **What:** Both buttons in the playlist row (toggle-play, and the "stop while playing" branch of the destructive delete button) call `networkActions?.game(root.gameController.requestPlay(id: audio.id), .generic, nil)` when a game is running. Every other call site producing the identical `requestPlay(id:)` payload (`Audio/AudioPlayPauseButton.swift:43`, `Audio/SharingActionView.swift:29,38`, `Controller/LinkController.swift:29`) uses `.playAudio` instead. Confirmed by reading the file directly.
- **Why:** `MasterController+Messaging.swift:181` only routes an audio message through `requestAudioPlay(message)` when `actionType == .playAudio`; `MasterController+AudioMessages.swift:72` (player→master inbound handler) and `PlayerController+Audio.swift:43-70` (`.update` switch) both hit `default: break` for anything else. Sending `.generic` here means the master never processes the request and other players never get told to start/stop — a GM toggling or deleting a track from this specific list during a live session leaves everyone else's audio silently out of sync.
- **Action:** Change both call sites to `.playAudio`, matching every other `requestPlay(id:)` caller in the module.
- **Severity:** High

### 5.2 `isPlaybackComplete` is never cleared, permanently breaking pause/resume after any playlist finishes naturally
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:38-52` (`toggle()`), `:204-216` (`preparePlay`), `:334-343` (`resetPlaylist`); `Modules/AudioRPG/Audio/AudioPlayerModel.swift:23`
- **What:** `resetPlaylist(complete:)` sets `model.isPlaybackComplete = true` when the last track of a non-repeating playlist ends. `toggle()` checks this flag to decide "restart from 0" vs. "resume" — but nothing clears it back to `false` except a full playlist reload (`add(audio:replace: true)`). Track-to-track skipping (`togglePlay(id:)`) never clears it either. Confirmed by reading `preparePlay` and `togglePlay` — neither resets the flag.
- **Why:** Once any track finishes naturally with repeat off (the `AudioPlayerModel.repeatPlayList` default), every subsequent play/pause cycle for the rest of the session takes the "restart from 0" branch (`preparePlay` → `replaceCurrentItem()`, which builds a fresh `AVPlayerItem` and seeks to the start) instead of resuming from the paused position — for any track, not just the one that completed. Easily reachable: let a background-music playlist finish once, then pause/resume — playback always restarts from the beginning.
- **Action:** Clear `model.isPlaybackComplete = false` at the top of `preparePlay(id:)`, or whenever `togglePlay(id:)` selects a track, not only on full-playlist replace.
- **Severity:** High

### 5.3 Deleting the current-but-paused track leaves the player pointed at a removed item
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:188-198` (`removeAudio`); `Modules/AudioRPG/Audio/AudioPlayerModel.swift:26-31` (`currentItem`/`currentIndex`)
- **What:** `removeAudio(id:)` only pauses if `model.currentId == id && model.isPlaying`; if the current track is merely paused (not playing), it deletes the track's temp file from disk and removes it from `playList` without touching `model.currentItem`. Confirmed: `currentItem` is a stored property, and `currentIndex` is computed as `playList.firstIndex(of: currentItem)` — so once the item is gone from `playList`, `currentIndex` becomes permanently `nil`.
- **Why:** `hasNext`/`hasPrev` both derive from `currentIndex` and permanently return `false`, so Next/Previous silently stop working until the user explicitly picks a new track. Additionally, the backing temp file is unlinked while `model.player`'s `AVPlayerItem` may still reference it, so resuming that stale item can fail with no error observation anywhere in the module.
- **Action:** When removing the currently-selected item, also clear/reassign `model.currentItem` (and stop the player) instead of leaving it pointing at a row no longer in `playList`.
- **Severity:** High

### 5.4 Dead validity guard in `loadAndPlay(id:)`
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:177-179`
- **What:** `let models = [itemController.itemOrEmpty(for: id)]; guard !models.isEmpty else { return }` — `models` is a single-element array literal and can never be empty, so the guard can never fail.
- **Why:** Reads as if it validates the item exists, but `itemOrEmpty` never returns nil (it falls back to an empty model), so a genuinely-missing item silently proceeds to load an empty placeholder instead of being caught here — the guard gives false confidence.
- **Action:** Remove the dead guard, or check `itemController.itemSync(for: id) != nil` if the intent was to bail out on a truly missing item.
- **Severity:** Low

---

## 6. Security

_No findings._ Verified via grep: no hardcoded secrets/API keys/tokens (`Bearer`, `apiKey`, `secret`, `Authorization`), no auth-token storage in the module. The `RPGAudio` Core Data model (`Resources/Model.xcdatamodeld/RPGAudio.xcdatamodel/contents`) is CloudKit-compliant — every non-optional attribute has a `defaultValueString` and both relationships (`entries`, `audio`) are `optional="YES"`. Preview/mock fixtures (`PreviewData.swift`, `MockData.swift`) are unguarded by `#if DEBUG` and ship in Release builds, but this is a project-wide convention (every module's `PreviewData.swift` follows the same pattern) and a repo-wide grep confirmed no production code path calls into them — see §9.7 for the note, not flagged as a security issue.

---

## 7. Performance

### 7.1 Timeline scrubber issues an unthrottled seek `Task` per drag frame at whole-second precision
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:78-82` (`skip(to:)`); `Modules/AudioRPG/Audio/AudioPlayerScrubberView.swift:26-32`
- **What:** `AudioPlayerScrubberView`'s `Slider` binds `get`/`set` directly with no `onEditingChanged`, so `onSeek` (→ `audioController.skip(to:)`) fires on every continuous drag delta, each call spawning a new unstructured `Task` calling `model.player.seek(to:)`. The `CMTime` is built with `CMTimeScale(1)` — i.e. 1 unit per second — so any fractional-second offset is truncated to the nearest whole second. Contrast with `AudioPlayerView`'s separate scrubber (`Audio/AudioPlayerView.swift:228-235`), which correctly gates the seek to `onEditingChanged`'s release event.
- **Why:** Dragging the bar-timeline scrubber allocates and enqueues dozens of Tasks per second with no debouncing, and every resulting seek snaps to whole-second granularity regardless of actual drag position — a real, always-reproducible precision loss plus needless churn in a user-interactive hot path.
- **Action:** Debounce/coalesce `skip(to:)` calls (only seek on `onEditingChanged` completion, or cancel the previous seek `Task` before starting a new one), and use a finer `preferredTimescale` (e.g. 600 or `CMTimeScale(NSEC_PER_SEC)`).
- **Severity:** Medium

### 7.2 Playlist tracks load strictly sequentially with no concurrency
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:115-119` (`add(audio:replace:)`)
- **What:** `for request in requests { guard let playItem = await audioAsset(for: request) else { continue } ... }` awaits each track's file-copy + duration-load one at a time, even though `audioAsset(for:)` is specifically marked `@concurrent` to run off the main actor.
- **Why:** Loading a whole folder/collection as a playlist pays the full per-track iCloud-download/copy/duration-load latency multiplied by track count before the playlist becomes playable, with no user-visible progress.
- **Action:** Fan the requests out with a `TaskGroup` (bounded concurrency if needed), reassembling results in original order before appending to `model.playList`.
- **Severity:** Medium

### 7.3 `assumeMainActorIsolated` runtime traps bridge nonisolated protocol conformances throughout `AudioModel`
- **Location:** `Modules/AudioRPG/Model/AudioModel.swift:108-112` (`Comparable <`), `:121-125` (`merge`), `:152-167` (`isSame`), `:177-182` (`duplicate`), `:268-272` (`Codable.encode`), `:292-296` (`Equatable ==`)
- **What:** All of `AudioModel`'s nonisolated protocol conformances funnel through `assumeMainActorIsolated { ... }`, documented as safe purely because "all real call sites are on the MainActor."
- **Why:** This converts a compile-time isolation guarantee into a runtime assumption — any future caller of `==`, `<`, `encode(to:)`, `.sorted()`, etc. from a background context (a background Core Data merge, an off-main import/decode path) will trap the process instead of failing to build. This is a maintainability/latent-risk concern rather than a currently-observed crash.
- **Action:** Keep this pattern's call sites under close review during future refactors; where feasible (especially `encode`/`isSame`/`merge`, exercised by import/export/sync code), thread the MainActor context explicitly instead of asserting it after the fact.
- **Severity:** Medium

---

## 8. SwiftUI / UI

### 8.1 `isScubberVisible` typo (missing "r") used throughout
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerBarViewModel.swift:16`, referenced 9× in `Modules/AudioRPG/Audio/AudioPlayerTimelineView.swift` (lines 60, 66, 124, 140, 162, 168, 172, 182, 205)
- **What:** Property should be `isScrubberVisible`; the typo is consistent across every use site.
- **Why:** Misspelled identifiers reduce searchability/readability and have already propagated to 9 more places.
- **Action:** Rename to `isScrubberVisible` — a simple project-wide rename within this module; no external module references it.
- **Severity:** Low

### 8.2 Volume slider UI reimplemented 4 times
- **Location:** `Modules/AudioRPG/Audio/ToolbarVolumeSliderView.swift:13-19`, `Modules/AudioRPG/Audio/PlayerVolumeView.swift:36-42`, `Modules/AudioRPG/Audio/AudioPlayerVolumeControl.swift:32-40`, `Modules/AudioRPG/Audio/AudioPlayerView.swift:98-104`
- **What:** Four separate `Slider(value: ..., in: 0...1)` volume controls exist, each with its own icon choice ("speaker.fill"/"speaker.wave.3.fill" vs "speaker"/"speaker.wave.3" vs none) and no shared component. A near-identical duplication exists for the variable-speaker-icon volume button between `ToolbarVolumeButtonView.swift:10-25` and the private `PlayerVolumeButtonView` in `PlayerVolumeView.swift:73-101`.
- **Why:** Any future change (accessibility label wording, haptics, range clamping) needs to be replicated four times; the icon inconsistency between variants is a small but visible UI inconsistency.
- **Action:** Factor a single `VolumeSlider` view and a single `VariableVolumeButton` view (icon/label as parameters); update all call sites.
- **Severity:** Low

### 8.3 `AudioPlayerMiniBarView` doesn't reuse the loaded album artwork
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerMiniBarView.swift:79-121` (compare `Modules/AudioRPG/Audio/AudioPlayerTimelineView.swift:150-174`, which uses `AlbumArtworkView` + `viewModel.albumArtwork`)
- **What:** The mini bar's "now playing" tile always renders a static gray `RoundedRectangle` + generic "music.note" icon, never the real album artwork that `AudioPlayerBarViewModel.loadAlbumArtwork` already loads and that the full bar/timeline view displays.
- **Why:** Inconsistent presentation of the same state between the two "bar" UIs, likely an oversight since the mini bar predates or wasn't updated alongside the artwork feature.
- **Action:** Reuse `AlbumArtworkView(artwork: viewModel.albumArtwork, ...)` here too, or confirm intentional simplification for the compact layout.
- **Severity:** Low

### 8.4 Un-named CoreData `displayState` sentinel value
- **Location:** `Modules/AudioRPG/Controller/LinkController.swift:68` (`inspectedItem.displayState != 2`)
- **What:** Raw literal `2` is used for the "totally hidden" display state, even though `DisplayStateMask.totalHidden.rawValue` (`CoreRPG/Model/ItemListable.swift:36`) already names this exact value — and AudioRPG's own `AudioRootModel.swift:186` already uses the named form for the same check.
- **Why:** Inconsistent within the module itself. This exact pattern is also repeated across ~15 other modules (PdfRPG, WeatherRPG, CharacterRPG, MapRPG, TableRPG, AdventureRPG, PhotoRPG, DiceRPG, CoreRPG), so it's a systemic smell across the app — flagging the AudioRPG occurrence as the in-scope instance.
- **Action:** Replace with `DisplayStateMask.totalHidden.rawValue` in `LinkController.swift:68` at minimum; a repo-wide follow-up is outside this audit's scope.
- **Severity:** Low

### 8.5 Minor naming/formatting inconsistencies
- **Location:** `Modules/AudioRPG/Model/PreviewData.swift:106` (`audioURL` instead of `audioUrl` — the sole `Url`-casing exception found in the module, preview-only); `Modules/AudioRPG/Model/AudioModel.swift:161` ("santity checks" comment typo); `PreviewData.swift:139` (extension's closing brace over-indented); `AudioCommands.swift:5-6`, `AudioFactory.swift:3-4`, `RoutePickerView.swift:6-7` (stray double blank lines after imports); `Route/AudioRoute.swift:52-54`, `Route/AudioDetailRoute.swift:50-53` (`switch case` over-indented by one level inside `detail()`)
- **What:** Small, scattered whitespace/spelling slips.
- **Why:** Cosmetic; harmless but inconsistent with the rest of each file's formatting.
- **Action:** Fix on next touch of these files; not worth a dedicated pass.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 `GameController.audioAsset(for:)` is dead code missing the `@concurrent` safeguard its sibling relies on
- **Location:** `Modules/AudioRPG/Controller/GameController.swift:155-189`
- **What:** This method is never called anywhere in the repository (verified via repo-wide grep for `audioAsset`) and is not part of the `AudioGameStoreable` protocol. It duplicates the file-copy/asset-loading pattern in `AudioController.audioAsset(for:)` (`Controller/AudioController.swift:126-169`), but unlike that method it is not marked `@concurrent`.
- **Why:** Dead code adds maintenance burden, and per this module's own documented rule (`AudioController.swift:124-126`: "`@concurrent`: file copies and asset loading must not run on the main actor"), this unmarked twin would block the main actor with synchronous file I/O the moment anyone calls it from `GameController`'s otherwise-`@MainActor` surface.
- **Action:** Delete the method, or mark it `@concurrent` to match its sibling if it's meant to be resurrected.
- **Severity:** Medium

### 9.2 Duplicated temp-file asset-loading logic between `AudioController` and `GameController`
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift:126-169` and `Modules/AudioRPG/Controller/GameController.swift:155-189`
- **What:** Both `audioAsset(for:)` implementations do "download via `FileUrlDataController` → copy/write to `URL.temporaryDirectory` keyed by id → `PlaylistItem.loading(...)`" with only minor differences (direct file copy vs. `ResourceCache`, id-vs-request struct). The `GameController` path's data-fallback branch hardcodes `.appendingPathExtension("mp4")` (line 181) instead of `itemController.config.filenameExtension` (which `AudioController.swift:161` correctly uses, and which resolves to `"m4a"` per `ModuleConfiguration.swift:13`).
- **Why:** The extension mismatch means the `GameController` path (network/game playback) can hand `AVURLAsset` a `.mp4`-named file containing `.m4a`-encoded audio data, risking load/format failures that would never repro through the `AudioController` path — a direct consequence of the logic being hand-duplicated instead of shared. Any future fix (retry policy, cache key scheme, error handling) currently has to be applied twice.
- **Action:** Fix the immediate extension bug by matching `AudioController`'s implementation (see §2 quick win); longer-term, extract a single `AudioAssetLoader` used by both controllers, taking a `(id, title, artist, fileUrl)` request and the shared `FileUrlDataController`/extension so there's one code path to fix. (Note: §9.1 recommends simply deleting the `GameController` copy since it's unreferenced — if deleted, this duplication finding is resolved as a side effect.)
- **Severity:** High (the extension-mismatch symptom); Medium (the underlying duplication, once the immediate bug is fixed)

### 9.3 The same four App-Intent helper functions are duplicated verbatim across ~10 modules
- **Location:** `Modules/AudioRPG/Intent/AudioManagementIntents.swift:147-184` (`intentPlainText`, `appendingIntentText`, `indexIntentEntities`, `deleteIntentEntities`)
- **What:** Byte-for-byte identical private helpers exist in AudioRPG plus PdfRPG, PhotoRPG, TableRPG, SpaceRPG, DiceRPG, WeatherRPG, CharacterRPG, GeneratorRPG, MapRPG's `*ManagementIntents.swift` files (confirmed via diff — zero differences).
- **Why:** Ten copies of the same Spotlight-indexing/text-append/App-Intents-deletion logic; any bug fix has to be repeated ten times, and has been kept in sync by hand so far, which won't scale.
- **Action:** Move these four functions into `CoreRPG` (e.g. an `IntentSupport` file) as generic helpers, and have all ten modules' Intent files call the shared versions. AudioRPG's copy is cited here as the representative in-scope instance; the actual fix should be applied module-wide, outside this audit's direct scope.
- **Severity:** Medium

### 9.4 Duplicated time-formatting helper
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerScrubberView.swift:71-80` (duplicate of `Modules/AudioRPG/Audio/PlayerTime.swift:24-31`)
- **What:** `AudioPlayerScrubberView.formatTime(_:)` reimplements `PlayerTime.formatted(time:)` almost line-for-line, but hardcodes the hour threshold as literal `3600` instead of using `PlayerTime.swift`'s already-named `TimeConstant.secsPerHour`.
- **Why:** Two independent implementations of the same formatting rule will drift — one already uses a named constant, the other a magic number.
- **Action:** Make `PlayerTime.formatted(time:)` (or `TimeConstant`) internal instead of private and call it from `AudioPlayerScrubberView`, deleting the local `formatTime`.
- **Severity:** Low

### 9.5 Commented-out Now Playing artwork line (incomplete feature)
- **Location:** `Modules/AudioRPG/Audio/MediaPlayerManager.swift:42`
- **What:** `// nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(...)` — dead commented-out code referencing an undefined `image`/`AKImage`.
- **Why:** Album artwork is loaded and displayed in-app (`AudioPlayerBarViewModel.loadAlbumArtwork`, `AlbumArtworkView`) but never surfaced to the system Now Playing / Lock Screen / CarPlay UI — this commented line is the fossil of that gap, and `AKImage` isn't a type used anywhere else in the module.
- **Action:** Either wire real artwork into `MPNowPlayingInfoPropertyArtwork` using the already-loaded `AudioPlayerBarViewModel.albumArtwork`, or delete the dead line.
- **Severity:** Low

### 9.6 `#if os(macOS)`/`#else` branches with byte-identical bodies
- **Location:** `Modules/AudioRPG/Audio/AudioPlayerVolumeControl.swift:93-117`
- **What:** `handleVolumeButtonTap()`'s macOS branch (94-104) and its `#else` branch (105-116) contain exactly the same code, differing only in the explanatory comments above each.
- **Why:** The platform split does nothing at runtime — either an intended macOS-only behavior was never implemented, or the conditional is vestigial; a reader will reasonably assume the branches differ when they don't.
- **Action:** Collapse into one unconditional block, or implement the actually-different macOS behavior the comment describes.
- **Severity:** Low

### 9.7 Preview/test fixtures ship unguarded in Release builds (project-wide convention, not a new issue)
- **Location:** `Modules/AudioRPG/Model/PreviewData.swift:1-174` (only `testRoot()` at :35-45 is `#if DEBUG`-gated); `Modules/AudioRPG/Model/MockData.swift:1-56`
- **What:** `AudioRootModel.preview`, `.previewWithData`, `AudioModel.previewFixtures`, `PlaylistItem.previewFixtures`, etc. are `public`/internal API with no `#if DEBUG` guard, so they compile into and ship inside Release builds.
- **Why:** This is a project-wide convention — every other module's `PreviewData.swift` (Pdf/Dice/Weather/Adventure/Photo/Map/Space/Table/Character) follows the identical unguarded pattern — and a repo-wide grep confirms nothing in production (non-Preview, non-Test) code paths calls into `AudioRootModel.preview`/`previewFixtures`, so there's no functional leak, only extra dead code/public surface area shipped to users.
- **Action:** No action required to match project convention. If minimizing binary size/API surface is ever a goal, wrap these in `#if DEBUG` module-wide — a repo-wide decision, not an AudioRPG-specific fix.
- **Severity:** Low

### 9.8 `AudioController`/`GameController` mix several responsibilities each
- **Location:** `Modules/AudioRPG/Controller/AudioController.swift` (399 lines), `Modules/AudioRPG/Controller/GameController.swift` (331 lines)
- **What:** Neither crosses 500 lines, but `AudioController` combines playback transport, playlist/asset loading, `AVAudioSession` delegate handling, and `MPRemoteCommandCenter` command routing in one type (mitigated by `// MARK:` extensions). `GameController` combines multiplayer report-tracking, asset loading (duplicate of `AudioController`'s, see §9.2), and two network-wire `Codable` structs defined at file scope.
- **Why:** Both are readable today thanks to good `// MARK:` sectioning and prior audit cleanup, but the asset-loading logic in particular is what caused the duplication/extension-mismatch bug in §9.2 — a symptom of living in the "wrong" file rather than a shared loader type.
- **Action:** No urgent split needed, but when addressing §9.2, pull the asset-loading logic (and the wire types) into their own file(s) rather than growing either controller further.
- **Severity:** Low

### 9.9 Identical `gameView(root:)` stub duplicated across modules
- **Location:** `Modules/AudioRPG/Controller/ViewController.swift:45-47`
- **What:** `gameView(root: AudioRootModel) -> some View { LinkRootView(type: .inspector, itemSelectionModel: ItemSelectionModel()) }` ignores its `root` parameter entirely; PdfRPG's and DiceRPG's `ViewController.gameView(root:)` are identical modulo the parameter type.
- **Why:** Confirms this is boilerplate that could be a `CoreRPG` protocol default rather than hand-copied per module; also worth double-checking it isn't a placeholder that was meant to use `root` (e.g. to scope the inspector to the current audio item) and never got filled in.
- **Action:** If intentional, generalize as a default implementation in `ViewControllable`; if not, verify against `ItemSelectionModel`/inspector requirements for Audio specifically.
- **Severity:** Low

### 9.10 Magic constants worth naming
- **Location:** `"MasterRPG"` artist string repeated 4× (`MediaPlayerManager.swift:41`, `AudioController.swift:110`, `GameController.swift:173,183`); default volume `0.25` duplicated independently (`AudioPlayerModel.swift:17` and `AudioPlayerBarViewModel.swift:18`); unnamed volume thresholds `0.33`/`0.66` for speaker-icon selection (`AudioPlayerVolumeControl.swift:84,86`, despite the file already having a `Constants` enum for other values)
- **What:** Ad-hoc literals repeated or left unnamed where a shared constant already exists nearby or would prevent silent divergence.
- **Why:** A rename/branding decision or a change to "the" default unmute volume requires touching multiple independently-maintained literals and is easy to miss one.
- **Action:** Extract `static let defaultArtistName`, tie the two volume defaults to one source, and add named thresholds to the existing `Constants` enum.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Establish one shared audio-asset-loading helper in `CoreRPG` or a dedicated file, used by both `AudioController` and `GameController`.** §9.1, §9.2, and §9.8 are all facets of the same root cause: the file-copy/temp-file/`PlaylistItem.loading` pattern was hand-duplicated between the two controllers, and the duplication is exactly why the two paths have already drifted (the `.mp4`/`.m4a` extension bug). A single loader type, parameterized by request and taking the shared `FileUrlDataController` + `filenameExtension`, removes the drift risk permanently rather than just fixing today's instance of it.
2. **Standardize on `AsyncSequence`/`Observations` for all reactive plumbing in this module.** §3.3 and §3.4 both show Combine or closure-token `NotificationCenter` living next to modern async-sequence code that already proves the pattern works here (`observeSharedAudio()`). Migrating the remaining two call sites removes the last mixed-paradigm code in the module.
3. **When storing an object behind a `Sendable`-conforming container (struct or protocol requirement), declare the object's own `Sendable` conformance explicitly rather than relying on it compiling clean today.** §3.1 compiles fine under current Swift 6 settings, but explicit conformance costs nothing and matches the module's own established pattern (`AudioPlayerSessionModel: Sendable`) — worth adopting as a habit before a future Swift toolchain or refactor changes what's accepted.
4. **The `~10-module Intent-helper duplication (§9.3) and the repo-wide `displayState != 2` magic-number pattern (§8.4) are both instances of the same organizational gap: per-module copies of logic that belongs in `CoreRPG`.** AudioRPG's instances are flagged here as the representative in-scope examples; a follow-up sweep across all affected modules (tracked separately, outside this audit) would resolve both at the root.

---

## 11. What was NOT audited

- Every other module (`AdventureRPG`, `CharacterRPG`, `DiceRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG`, `RuleRPG`, `CoreRPG`, `GeneratorRPG`, `GameRPG`, `RolePlayGameKit`) — grepped only to confirm cross-module duplication claims (§9.3, §9.9), never audited in their own right.
- `MasterRPG`/`MasterMac`/`MasterTV`/`DiceRollerWidgetExtension` app targets and their entitlements — not opened.
- Algorithmic correctness of AVFoundation's own playback/timing behavior — treated as a black box; only this module's usage of it was reviewed.
- Build settings / Xcode project structure beyond the `AudioRPG` scheme's own build settings (checked only `SWIFT_STRICT_CONCURRENCY`/`SWIFT_VERSION`/`SWIFT_APPROACHABLE_CONCURRENCY` via `-showBuildSettings`).
- Third-party SPM dependency internals (none are direct AudioRPG dependencies beyond what CoreRPG already brings in).
- `AudioRPGSnapshotTests` — not opened; only a directory-listing-level acknowledgment that a test target exists. No test-coverage assessment was performed.
- Localization/string-catalog correctness — not assessed beyond confirming `Text(..., bundle: .module)` usage patterns are present.
- Performance profiling via Instruments — not performed; findings in §7 are static-analysis judgments (allocation patterns, sequential vs. concurrent awaits), not measured traces.
- SharePlay/`GroupActivities`/network-layer correctness beyond what's directly visible inside `Modules/AudioRPG/` (the `MasterController`/`PlayerController` routing referenced in §5.1 was read only far enough to confirm the `.generic` vs `.playAudio` dispatch bug, not audited end-to-end — a separate `CODE_AUDIT_Network.md` already exists for that layer).

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line.

- **§5.1** — open `Modules/AudioRPG/Audio/PlayListView.swift`, lines 27 and 49. Confirm both read `.generic` where every other `requestPlay(id:)` call site in the module (`AudioPlayPauseButton.swift:43`, `SharingActionView.swift:29,38`, `LinkController.swift:29`) uses `.playAudio`.
- **§5.2** — open `Modules/AudioRPG/Controller/AudioController.swift`, lines 38-52 (`toggle()`) and 202-216 (`preparePlay`). Confirm `preparePlay` never sets `model.isPlaybackComplete = false`, and that `resetPlaylist` (lines 334-343) is the only writer, setting it `true`.
- **§5.3** — open `Modules/AudioRPG/Controller/AudioController.swift`, lines 188-198, alongside `Modules/AudioRPG/Audio/AudioPlayerModel.swift`, lines 26-31. Confirm `removeAudio` has no `else` branch clearing `model.currentItem` when the removed item was paused-but-current, and that `currentIndex` is computed from `currentItem` via `playList.firstIndex(of:)`.
- **§9.2 (extension mismatch)** — open `Modules/AudioRPG/Controller/GameController.swift`, line 181 (`"mp4"`) side-by-side with `Modules/AudioRPG/Controller/AudioController.swift`, line 161 (`itemController.config.filenameExtension`).
- **§3 (clean concurrency build)** — this was verified directly in this session via `xcodebuild -scheme AudioRPG -destination 'platform=iOS Simulator,id=<sim>' clean build`, confirmed `** BUILD SUCCEEDED **` with zero Swift compiler warnings, and via `-showBuildSettings` confirming `EFFECTIVE_SWIFT_VERSION = 6`, `SWIFT_STRICT_CONCURRENCY = complete`.

If any finding doesn't reproduce when you visit the line, flag it with the specific reference for re-investigation.
