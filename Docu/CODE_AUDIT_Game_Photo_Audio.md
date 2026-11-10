# Code Audit: Audio vs Photo game messages (SharePlay delivery speed)

_Date: 2026-11-09 · Scope: how the game master sends an Audio item and a Photo item to players, and why Audio is slow over SharePlay while Photo is fast. Read-only audit; nothing was changed._

**Short answer:** yes, the two paths differ. Both put the file in the SharePlay **Journal**. But every Journal add has a **10-second timeout** (`RPGSharePlayController.journalAddTimeout`). A photo upload usually finishes inside it. An audio track is several times larger, so it usually doesn't. Then the audio package falls back to the chunked **Messenger** path, which is much slower. That path sends 64 KB chunks one at a time, Base64-encodes the bytes twice, and holds up every other game message behind it. Meanwhile the timed-out Journal upload keeps running and competes for the same upload bandwidth. Audio also adds costs that Photo doesn't have: an uncached re-export of the file for every player's request, run on the master's message pipeline; a "wait until every player has the file" gate before playback; and a prefetch that can remove the track a slow player is still downloading.

---

## 1. Executive summary

1. **[High] The 10 s Journal add timeout pushes large audio packages onto Messenger.** §7.1, `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:176`, `RPGSharePlayController+ChunkedTransport.swift:96-152`
2. **[High] A timed-out add keeps uploading and blocks the audio slot.** The bytes go up twice, and every later audio package uses Messenger until the hidden add returns. §7.2, `SharePlayJournalAddLimiter.swift:137-148, 164-213`
3. **[High] A large package on Messenger holds up the play command.** All Messenger traffic shares one FIFO queue, so `.playAudio`, receipts and map updates wait behind a multi-MB audio upload. §7.3, `RPGSharePlayController+ChunkedTransport.swift:385-432`
4. **[High] Each player's asset request triggers a full, uncached audio export on the master's message pipeline.** Photo answers the same request from the package cache. §7.4, `MasterController+AudioMessages.swift:38-45` vs `MasterController+FileMessageSupport.swift:73-80`
5. **[High] Prefetching the next track can cancel a slow player's download of the current track.** The Journal holds one audio attachment, the abort is silent, and the track is never sent again. §5.1, `MasterController+AudioMessages.swift:375-398`, `RPGSharePlayController+JournalAttachments.swift:276-284`
6. **[Medium] A failed audio Journal load drops the player at once.** The comments say the master sends it again. §5.2, `PlayerController+NetworkStoreDelegate.swift:128-141`, `MasterController+AudioMessages.swift:276-286`
7. **[Medium] Audio waits for every player, then a 20 s deadline, then a master round trip before playback starts.** A photo shows on each device as soon as it arrives. §7.6, `MasterController+AudioMessages.swift:134-206, 292-300`
8. **[Medium] Audio is never cached as a package.** Every show, play, retry and prefetch exports the file again. §7.5, `MasterController+Show.swift:162-164`, `MasterController+AudioMessages.swift:354-359`

### Photo vs Audio at a glance

| Step | Photo | Audio |
|---|---|---|
| Master message | `.reveal` via `show(for:)` | `.store` per required track via `deliverAudio`; `.playAudio` after the receipts |
| Journal publication policy | `.latestWins` (a newer reveal replaces a waiting one) | `.fifo` (`.store`), queued one after another in the audio slot |
| Typical package size | ~0.3–5 MB | ~3–30 MB per track |
| Journal add within 10 s | usually yes | often no, so it falls back to Messenger (§7.1) |
| Master answer to the player's request | `cachedPackage` (memory) | `createGameData` (full export, uncached and not coalesced) on the pipeline (§7.4) |
| When the player sees or hears it | on arrival | after **all** receipts or the 20 s deadline, plus `.ok` → master → `.playAudio`, plus AVPlayer coordination (§7.6) |
| Slot replacement while loading | intended (newer photo wins) | prefetch replaces a track that is still needed (§5.1) |
| Journal load failure | player asks for it again | player reports `.failed`, master gives up on that player (§5.2) |

---

## 2. Quick wins

- Scale `journalAddTimeout` with the attachment size, or give Audio/Pdf/Space a longer timeout like the load deadline already does (`RPGSharePlayController+JournalAttachments.swift:22-27`). See §7.1.
- Serve audio asset requests through `cachedPackage` (or at least the `audioPackages` coalescer), like `handleFileBackedMessage` does. See §7.4.
- In the `noLongerCurrent` branch for audio, report the load failure to the master, or treat it as a failure the master can retry. See §5.1.
- Fix the two stale comments in §9.2.

---

## 3. Concurrency

_Compiler ground truth:_ an iOS Simulator build of `MasterRPG` (2026-11-09) reported **no warnings** in the audited files (GameRPG `SharePlay/`, the Master/Player Audio, Photo and file-support controllers, and AudioRPG/PhotoRPG `Controller/`). The build may have been incremental, so files that weren't recompiled would not have reported warnings. Both findings below are design-level, not compiler diagnostics.

### 3.1 The timed-out Journal add is not cancellable but still counts as a failure
- **Location:** `Modules/GameRPG/SharePlay/SharePlayJournalAddLimiter.swift:137-148`, `RPGSharePlayController+ChunkedTransport.swift:137-142`
- **What:** On timeout the limiter cancels the add task and resumes the caller with `.timedOut`. `GroupSessionJournal.add` ignores cancellation, so the system upload keeps running while the caller has already started the Messenger fallback.
- **Why:** Two uploads of the same bytes overlap, and the late attachment is then removed (`discardLateValue` → `removeJournalAttachment`). The upload was wasted, and it slowed down the Messenger copy while both ran. This is the concurrency side of §7.2.
- **Action:** Treat a timed-out add of a package that Messenger *can* carry the way the code already treats one Messenger cannot (`exceedsMessenger`, lines 104-110): keep waiting, and adopt the late attachment instead of sending the bytes a second way.
- **Severity:** Medium

### 3.2 The asset-request export holds the master's serial message pipeline
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:38-45`, `MasterController+NetworkStoreDelegate.swift:230-255`
- **What:** `handle(_:origin:)` runs inside the master's pipeline drain worker. For an audio asset request it awaits `createGameData`, a `@concurrent` export of the whole file. The work is off the main actor, but the pipeline waits for it.
- **Why:** Every message behind it in the pipeline waits too, including other players' `.ok` receipts, which are what start the pending play. See §7.4 for the impact.
- **Action:** Answer from a cache (§7.4), or start the export in its own task and answer when it is done, as `startAudioDelivery` already does for the push path (`MasterController+AudioMessages.swift:212-217`).
- **Severity:** Medium

---

## 4. API modernity

_No findings._ The audited paths already use `Task.sleep(for:)`, `ContinuousClock`, `@concurrent`, `Mutex` and `FormatStyle`.

---

## 5. Bugs / logic errors

### 5.1 Prefetching the next track removes the current track while a player is still loading it
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:375-398`, `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift:311-319`, `Modules/GameRPG/SharePlay/RPGSharePlayController+JournalAttachments.swift:276-284`
- **What:** The Journal keeps one attachment per slot, and every track of an audio item uses the same `.audio` slot. When a track starts on the master's device (which can happen after the 20 s deadline while a slow player is still downloading), `prefetchNextAudio` publishes the next track. The queue commits it and removes the previous attachment. The slow player's `isStillWanted` poll then fails, and the load ends with `noLongerCurrent`. That branch only logs "replaced while loading; skipped": it calls neither `handleFileLoadFailure` nor sends a request.
- **Why:** The player never gets the current track. The master keeps it in `lateAudioPlayers` and never sends that track again: the ledger's `displaced` rule refuses a re-upload for the same show, and an audio player doesn't send asset requests from the Journal path. The player stays silent until the GM plays something new.
- **Action:** Give a prefetch a slot of its own (as was done for playlists), or hold the prefetch until every player who still lacks the current track has reported or been abandoned. Also, for audio, turn `noLongerCurrent` into the same `.failed` report the deadline branch sends, so the master knows.
- **Severity:** High

### 5.2 An audio Journal-load failure abandons the player immediately
- **Location:** `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:128-141`, `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:276-286`
- **What:** The player's comment says the master must learn of the failure "to send it again a bounded number of times and then go on without this player". The master's `handleAudioDeliveryFailure` calls `abandonAudioDelivery` on the first `.failed` and starts the play without that player. Nothing resends.
- **Why:** On SharePlay, one slow or failed Journal load (180 s deadline) permanently costs that player the track. A photo player in the same situation sends an asset request instead and gets the file.
- **Action:** Pick one rule. Either retry once through Messenger or the Journal (the ledger allows it for a newer counter) before abandoning, or fix the player comment to match the actual behaviour.
- **Severity:** Medium

### 5.3 The asset-request answer after a Journal fallback can broadcast the whole file again over Messenger
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+ChunkedTransport.swift:181-190`, `SharePlayJournalLedger.swift:85-97, 133-141`, `GameNetworkController+Delivery.swift:93-99`
- **What:** `journalUploadFailed` calls `ledger.uploadFailed`, which frees the slot. A request that reaches the master after that point (a busy pipeline makes this likely, see §3.2) gets a fresh export, and `publishAsset` → `shouldUpload` returns `true` again. The add limiter is still quarantined, so the result is `.unavailable`, and a second full chunked broadcast goes to every participant.
- **Why:** The file goes out over Messenger twice, a ~1.8× expanded multi-MB payload each time. It also holds up the queue for longer (§7.3).
- **Action:** After a Messenger fallback, keep the ledger entry marked "delivered by Messenger for counter N" instead of clearing it, so a request for the same show is answered with `.alreadyPublished`.
- **Severity:** Medium

### 5.4 Audio deliveries can't be superseded while their package is built
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:345-347`
- **What:** `show(for:)` passes `isSuperseded` to `sendPresentation`, but `deliverAudio` doesn't. If the GM pauses or picks another audio while a large track is exporting, that track is still uploaded. `deliverPendingAudio` only checks whether the play is still pending *after* `deliverAudio` returns (line 321).
- **Why:** This uploads a stale multi-MB package into the shared audio slot, delaying the new play's package (FIFO, §7.2) and possibly replacing it.
- **Action:** Pass an `isSuperseded` closure that checks `gameModel.pendingAudioPlays[data.id] == nil` (and the prefetch task's cancellation).
- **Severity:** Low

---

## 6. Security

_No findings._ Inbound byte budgets (`SharePlayInboundByteBudget`, `journalLoadBudget`) and size caps apply equally to both modules.

---

## 7. Performance

### 7.1 Every module gets the same 10 s Journal add timeout, so audio falls back to Messenger
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:176`, `RPGSharePlayController+ChunkedTransport.swift:96-100, 137-142, 150-151`
- **What:** `journalAddTimeout = .seconds(10)` applies to every add, whatever its size. On timeout, a package Messenger can carry (≤ ~47 MB raw) goes to `journalUploadFailed`, then `enqueueChunkedSend`. The *load* side already accepts that large modules take longer (`journalAttachmentLoadDeadline`: 180 s for Audio/Pdf/Space vs 30 s otherwise, `RPGSharePlayController+JournalAttachments.swift:22-27`). The add side doesn't.
- **Why:** This is the main reason Audio is slow and Photo is fast. A 1–3 MB photo uploads in under 10 s, so it stays on the Journal (a CloudAsset made for large blobs). A 10–20 MB track over a typical home uplink through the FaceTime relay does not, so it ends up on the far slower Messenger path (§7.3). Look for `Journal ⌛: message … timed out adding audio attachment` followed by `Chunked: message …, packages N` in the master's `sharePlay` log to confirm on device.
- **Action:** Make the add timeout depend on size, e.g. a floor plus bytes ÷ an assumed minimum uplink rate, or reuse the per-module load deadline. Prefer waiting for the Journal over falling back for packages above a few MB.
- **Severity:** High
- **Status:** Fixed 2026-11-10. `GameLimits.SharePlay.journalAddTimeout(forByteCount:)` = 10 s + bytes ÷ 250 KiB/s, capped at 180 s (the audio load deadline). Used at `RPGSharePlayController+ChunkedTransport.swift:99`; pinned in `GameLimitsRelationshipTests`. Not measured on device. §7.2 and §3.1 (adopting a late add instead of falling back) remain open.

### 7.2 A timed-out add blocks the audio slot and uploads the bytes twice
- **Location:** `Modules/GameRPG/SharePlay/SharePlayJournalAddLimiter.swift:69-74, 164-213`, `RPGSharePlayController+ChunkedTransport.swift:143-144`
- **What:** The limiter keeps the timed-out attempt under its key `(slot, session)` until the system add returns. Until then, every `run(for: .audio …)` returns `.unavailable` ("Journal bypass … quarantined add"), and that package also goes over Messenger. Meanwhile the hidden add is still uploading the same bytes.
- **Why:** After the first large track times out, the next ones (the pending play's other start items, the prefetched next track, a replay) all take the slow path. They also share upload bandwidth with the leftover Journal upload. Photos seldom time out, so the photo slot is rarely blocked.
- **Action:** Covered by §3.1 / §7.1: don't fall back for packages that would finish on the Journal with a realistic deadline. If the fallback stays, adopt the late attachment instead of removing it, and lift the block as soon as it returns.
- **Severity:** High
- **Status:** Fixed 2026-11-10 together with §7.1. A package of 3 MB or more (`GameLimits.SharePlay.journalWaitInsteadOfFallbackBytes`) no longer falls back to Messenger when its add times out: it keeps waiting and adopts the late attachment (`waitsForLateAdd` in `RPGSharePlayController+ChunkedTransport.swift`), so the bytes go up once. The limiter lifts its block as soon as the add returns. Smaller packages still fall back. Residual: if a large add outlives even the scaled timeout, the next add in that slot is still `.unavailable` and uses Messenger. Not device-verified.

### 7.3 Messenger fallback: small chunks sent one at a time, double Base64, one shared queue
- **Location:** `Modules/GameRPG/SharePlay/SharePlaySingleQueuePackageSender.swift:91, 97-98, 173-227`, `RPGSharePlayController+ChunkedTransport.swift:385-432, 495-499`, `RPGSharePlayController+SessionLifecycle.swift:199-207`
- **What:**
  - The `GameNetworkModel` is JSON-encoded (the file bytes become Base64, ×4/3).
  - It is split into 64 KB `PackageMessage`s, whose `data: Data` field `GroupSessionMessenger` JSON-encodes again (Base64 a second time, ×4/3). About 1.78× the file size goes over the wire.
  - Each package is awaited before the next one is sent, with a 200 ms pause every 60 packages.
  - All Messenger traffic of the session (`pendingSendOperations` → one `packageSender`) is a single FIFO queue.
- **Why:** A 15 MB track is ~27 MB on the wire in ~420 strictly sequential sends. While it is on the queue, the master's other Messenger messages wait behind it, including the `.playAudio` command that starts the music (§7.6), receipts, map pin moves and dice. A prefetch of the next track can therefore delay the *current* play command. Photo packages rarely reach this queue.
- **Action:** Keep large packages off Messenger (§7.1). If a fallback is still needed, give small control messages their own queue or priority ahead of package streams, and send the payload as raw `Data` chunks (not a Codable struct with a `Data` field) to avoid the second Base64 pass.
- **Severity:** High

### 7.4 Audio asset requests run an uncached, uncoalesced export on the master pipeline
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:38-45` vs `Modules/GameRPG/Controller/MasterController+FileMessageSupport.swift:73-80`, `MasterController+PackageCache.swift:28-40`; player side `PlayerController+Audio.swift:27-36`
- **What:** On SharePlay the `.store` reference arrives over Messenger long before the Journal attachment. The player can't hold the file yet, so it answers with an asset request (`requestData: true`). Photo answers that request with `cachedPackage` (filled by the `show` that just exported it). Audio calls `root.audioRoot.gameControllable.createGameData(for:)` directly: no package cache, and not even the `audioPackages` coalescer that `deliverAudio` uses (lines 354-359). The answer then usually hits `publishAsset` → `.alreadyPublished` and is thrown away.
- **Why:** With N SharePlay players, the master reads and serialises the whole track N extra times, one after another, on its message pipeline (§3.2). The `.ok` receipts that release the pending play queue up behind those exports. This cost is specific to Audio.
- **Action:** Route audio asset requests through the same `cachedPackage(module:itemId:controllable:)` as the file-backed modules (fingerprint: `networkVersion`), and have `deliverAudio` fill that cache. Consider skipping the request on SharePlay while a Journal publication for that counter is expected (the player already handles a failed load separately).
- **Severity:** High

### 7.5 No package cache for Audio: every show, play, retry and prefetch exports again
- **Location:** `Modules/GameRPG/Controller/MasterController+Show.swift:162-164`, `MasterController+AudioMessages.swift:337-347, 354-359, 417-435`
- **What:** `createGameData(for:)` caches Map, Weather and every file-backed module, but goes straight to `createGameData` for `.audio`. `audioPackages` (`SharedWorkCoalescer`) only joins exports that run *at the same time*. The bounded retry (every 5 s, up to 5 times), a replay of the playlist loop, and a re-show each read the full file again.
- **Why:** This is repeated multi-MB disk reads and memory spikes on the master for content that hasn't changed. Photo avoids it through `MasterPackageCache`.
- **Action:** Use `cachedPackage` for Audio too, keyed by `networkVersion`. Check that `MasterPackageCache`'s size bound fits audio-sized entries, or cache only the most recent track.
- **Severity:** Medium

### 7.6 Audio adds a "wait for everyone" gate and an extra round trip that Photo doesn't have
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:134-206, 292-300`, `MasterController.swift:60`, `PlayerController+Audio.swift:45-65`, `Modules/AudioRPG/Controller/AudioListenerCoordinator.swift:35-52`
- **What:** A photo shows on each player's device the moment its bytes arrive. An audio play first collects a `.ok` from every player who lacked the track (or waits for the 20 s `audioPlayDeadline`). Only then does the master broadcast `.playAudio`, over the Messenger queue of §7.3. On SharePlay a player then only calls `loadPlaylist`, and the `AVPlayerPlaybackCoordinator` starts playback with the master. The coordinator can itself wait for participants that aren't ready.
- **Why:** The time until audio is heard is the slowest player's download plus two Messenger hops plus coordinator readiness. Even with equal transfer speed, Audio *feels* slower than Photo. This is mostly by design (synchronised music), but it adds to §7.1–§7.4.
- **Action:** Keep the gate, but shorten what's in front of it (§7.1–§7.4). Consider starting the play for ready players once the *first* receipt is in and the rest join through `joinRunningAudioPlay`, which already exists. Check the `🎧 Coordinated playback suspended locally` diagnostics to see whether coordination adds noticeable delay.
- **Severity:** Medium

---

## 8. SwiftUI / UI

_No findings._ No SwiftUI views are on the audited message paths.

---

## 9. Dead code / duplication / refactor

### 9.1 Audio duplicates the file-backed handler without its package cache
- **Location:** `Modules/GameRPG/Controller/MasterController+AudioMessages.swift:11-83` vs `MasterController+FileMessageSupport.swift:56-96`; `FileBackedModuleAccess.swift:9-12`
- **What:** Audio deliberately keeps its own handler because of pending plays (CODE_AUDIT_Audio2 §9.4). But its `.ok`, `.failed`, asset-request, list and `.generic` branches copy `handleFileBackedMessage`, and the copy has drifted: no `cachedPackage` (§7.4), and a different failure policy (§5.2).
- **Why:** The differences that make Audio slower live exactly in this copied code.
- **Action:** Pull the asset-request branch (the `hasLocalFileData` guard plus `cachedPackage`) into one shared helper used by both handlers. Keep only the pending-play parts audio-specific.
- **Severity:** Medium

### 9.2 Stale comments
- **Location:** `Modules/GameRPG/Controller/PlayerController+NetworkStoreDelegate.swift:129-133` (promises a bounded resend that doesn't exist, see §5.2); `Modules/GameRPG/Controller/MasterController+FileMessageSupport.swift:32-34` (says three callers, but Photo, Pdf and Space all go through `handleFileBackedMessage` now)
- **What:** The comments describe behaviour the code doesn't have.
- **Why:** They mislead the next person debugging this exact slowness.
- **Action:** Update them along with the fixes above.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

- **Size-aware deadlines everywhere on SharePlay.** The add timeout (§7.1), the 20 s audio-play deadline and the 180 s load deadline should come from one function of byte count, kept in `GameLimits.SharePlay` next to the other ceilings and pinned by `GameLimitsRelationshipTests`.
- **One package cache for every module that exports a file.** Map, Weather, Photo, Pdf and Space use `MasterPackageCache`; Audio should too (§7.4, §7.5).
- **Messenger is for control traffic.** Large payloads should reach Messenger only as a last resort, and never ahead of small messages (§7.3).
- **One slot is one item.** Anything that publishes a *different* item into a slot another device may still be loading needs either its own slot (as the playlist got) or a "still needed" check (§5.1).
- **Confirm on device before tuning.** The master log already records everything needed: `Journal: … add of X returned … after Y`, `Journal ⌛`, `Journal bypass`, `Chunked: … packages N`, and on the player `Journal ✓: received … (rate/s)`. One audio play and one photo show from the same session will confirm §7.1–§7.3.

---

## 11. What was NOT audited

- The LAN (Bonjour) transport for Audio vs Photo. Only SharePlay was in scope, and both modules send one framed package per connection there.
- Pdf, Space, Map and Weather delivery, except where they share code with Photo.
- Runtime behaviour of `GroupSessionJournal.add`, in particular whether it returns only after the upload has finished. §7.1 assumes it does, as the code's own timeout handling also does. Nothing was measured on device.
- How long `AVPlayerPlaybackCoordinator` waits for participants (§7.6) was not measured.
- The AudioRPG playback engine (`AudioController`, playlist loading) beyond the game-message entry points.
- Export format internals (`rootExportController.export`) and `MasterPackageCache` eviction bounds.
- Test coverage of these paths.

---

## 12. Verification

- **§7.1:** open `Modules/GameRPG/SharePlay/RPGSharePlayController.swift:176` (`journalAddTimeout = .seconds(10)`). Then `RPGSharePlayController+ChunkedTransport.swift:96-100` (the timeout is passed to the limiter), lines 137-142 (on `.timedOut`, only a package `exceedsMessenger` avoids the fallback), and line 151 (`journalUploadFailed` → `enqueueChunkedSend`, lines 182-189). Compare with `RPGSharePlayController+JournalAttachments.swift:22-27`, where the load deadline is 180 s for `.audio`.
- **§7.2:** `SharePlayJournalAddLimiter.swift:71-74` (`attempts[attemptKey] == nil` or `.unavailable`). Lines 137-148: on timeout the attempt stays in `attempts`. Lines 164-213: it is removed only once the system add returns, after late cleanup. `RPGSharePlayController+ChunkedTransport.swift:143-144`: `.unavailable` takes the Messenger fallback.
- **§7.3:** `SharePlaySingleQueuePackageSender.swift:91` (64,000-byte packages), lines 97-98 (200 ms every 60 packages), and lines 203-226 (each `sendWithRetry` awaited in turn). `SharePlayMessages.swift:5-17`: `PackageMessage.data: Data` is Codable, so it is Base64 a second time. `RPGSharePlayController+ChunkedTransport.swift:385-432`: one `pendingSendOperations` FIFO drained by a single task.
- **§7.4:** `MasterController+AudioMessages.swift:44` calls `root.audioRoot.gameControllable.createGameData(for:)` directly, while `MasterController+FileMessageSupport.swift:79` calls `cachedPackage(...)`. `PlayerController+Audio.swift:30-34`: a `.store` without data returns `requestData: true`. `GameNetworkController+Delivery.swift:67-71`: the Journal publication is queued before the Messenger reference is sent.
- **§5.1:** `MasterController+AudioMessages.swift:388-396` (the track-start handler publishes the next track). `SharePlayJournalPublicationQueue.swift:311-319` (the commit replaces the slot's attachment and schedules removal of the old one). `RPGSharePlayController+JournalAttachments.swift:231-234` (`isStillWanted` checks `currentJournalAttachmentIds`) and lines 276-284 (`noLongerCurrent` returns without any delegate call). `SharePlayJournalLedger.swift:90-93` (a displaced show is not uploaded again for the same counter).
