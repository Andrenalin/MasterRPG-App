# MasterRPG — 3D Game Table (`Modules/GameRPG/Table3D`) Code Audit

Generated 2026-09-20. Scope: the 31 Swift files (~5,560 LOC) in `Modules/GameRPG/Table3D/`, covering both implementations: the **visionOS** TabletopKit table (`GameSetup`, `GameRenderer`, `GameEquipment`, `GameObserver`, `GameInteraction`, `TableScaleGestureController`, `GameTableView+VisionOS`) and the **iOS/macOS** camera-based table (`GamePortableSetup`, `GamePortableRenderer`, `GamePortableEntities`, `GameTableView+PlatformFlat`), plus the shared model, projection, pin and toolbar code. Seams into other modules were read only where a Table3D finding depends on them (`RPGSharePlayController+TableCoordination`, `PlayerController+MapPresentation`, `GameToolBar*`, `MapEditorActionRouter`). No `Dead/` directory exists in this repo.

Findings cite `path:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; **no code was changed** (the only file written is this report).

**Method note.** `SKILL.md` asks for three parallel Explore agents. The module is small enough (~5.5k LOC) that I read every file in full myself instead, since excerpt-reading agents would have lowered review depth. Cross-module greps confirmed dead code and call sites. No finding is rated Critical because none of them, once opened at the cited lines, was a demonstrable crash, data-loss or memory-corruption bug.

**Compiler ground truth (Step 2).** Clean builds, fresh DerivedData:

| Platform | Scheme / destination | Result |
|---|---|---|
| iOS | `MasterRPG` · generic iOS Simulator | **Succeeded**, 0 Swift warnings |
| macOS | `MasterMac` · macOS | **Succeeded**, 0 Swift warnings |
| visionOS | `MasterRPG` · generic visionOS Simulator | **FAILED**, 1 error (see §5.3), 0 warnings in Table3D |

The only "warning" lines in any log are the AppIntents metadata notice. Because the visionOS build failed at type-check, SIL-level concurrency diagnostics (region isolation) did **not** run for the visionOS-only files. See §11.

---

## Resolution status (2026-09-20)

All findings were addressed in code unless listed under *Not changed*. iOS, macOS, visionOS and tvOS build with zero warnings; new unit tests cover seat assignment, projection maths, the streaming gate, hit-volume gating and drop snap-back (`Tests/GameRPGTests/TableSeatAssignmentTests.swift`, `GameTableProjectionTests.swift`, `GameTableControlTests.swift`).

**Notes that correct or refine the findings above**
- §5.3: fixing the `CoreRPG` import unmasked a second visionOS-only error (`RPGSharePlayController.swift`, `tasks` mutated from a `@Sendable` observation closure); both are fixed, and the visionOS build now runs the SIL diagnostics with 0 warnings.
- §5.1: a player can only exclude the master from the ranking once its SharePlay participant is pinned (first complete master broadcast). Before that the code reports a possible shared seat instead of staying silent. Seats are re-evaluated on every participant change.
- §9.2: `setAllRoomsShown` and `movePointerToMapCenter` are referenced by `GameTableControlTests`, so they were kept.
- §10.1: `GameTablePinPawnTests.swift` (visionOS only) was already stale before this work (calls `PinPawn(pin:)` and `pinLongPressed`, which no longer exist) and still needs a rewrite; it was not run.
- §6.3: verified. `GameController.updatePin` enforces on the master that a player only moves their own pin (or the visible pointer) and may only zoom/highlight visible foreign pins.

**Not changed (needs a decision or a device)**
- §5.13 hand-tracking/pinch resize: needs on-device verification that `HandTrackingProvider` delivers data in a volumetric window; `maxScale` (1.01) left as is.
- §7.8 hand-tracking loop / dice-signature array: judged negligible, left as is.
- §8.3 iOS/macOS have no dice or seats: intentional; now documented in `CLAUDE.md`.
- §9.4 the visionOS/portable `GameSetup`/`GameRenderer` twins remain separate; `Board` (and its renderer) is now shared.

---

## 1. Executive summary

No Critical items. Highest-impact findings, in priority order:

1. **[High] visionOS target does not compile at HEAD** — `Modules/GameRPG/SharePlay/RPGSharePlayController+TableCoordination.swift:16,23`. Introduced by `c931b6af`; the new file uses `Logger.sharePlay` without `import CoreRPG` (`#MemberImportVisibility`). §5.3.
2. **[High] "Pause sharing" toggle is ignored by the 3D table** — `GameTableModel+PinSelection.swift:107-239`, `GameTableModel+ToolBar.swift:79-140`. Every GM room/pin edit broadcasts even with `isStreaming == false`, so hidden rooms and pins reach players. §6.1.
3. **[High] Two players share a seat in a full 5-player party, with no warning** — `GameTableModel+Seating.swift:147-171`. The master occupies an index in the participant ranking, so the modulo wraps early. §5.1.
4. **[High] Probable retain cycle keeps the whole `GameTableModel`/TabletopKit game alive after the window closes** — `GameTableView+VisionOS.swift:425-428,457-460`. §5.2.
5. **[Medium] Every dice sync plays up to 6 roll sounds and sends 12 synced actions** — `GameObserver.swift:41-50`, `GameTableModel+Dice.swift:60-91`. §5.4 / §7.2.
6. **[Medium] 72 synchronous USDZ + audio loads on the main actor at table creation** — `GameSetup.swift:103-146`, `GameEquipment.swift:561-599,709-737`. §7.1.
7. **[Medium] Map-load cancellation can leave the previous map's image under the new map's fog** — `GameTableModel+MapSync.swift:84-131`. §5.5.
8. **[Medium] "Overflow" and "shared seat" notices promised by earlier audits are write-only state, never shown** — `GameTableModel.swift:61,118`. §5.7.
9. **[Medium] Any participant can toss any seat's dice (`seatControl: .any`)** — `GameSetup.swift:109-145`, `GameInteraction.swift:37-69`. §6.2.
10. **[Medium] Fog compositing is duplicated across platforms (and has already diverged), and runs on the main actor** — `GameEquipment.swift:178-320` vs `GamePortableEntities.swift:150-301`. §9.3 / §7.3.

---

## 2. Quick wins (≤30 min each)

- **Add `import CoreRPG`** to `RPGSharePlayController+TableCoordination.swift` (top of file, lines 4-7) to unbreak the visionOS build (§5.3).
- **Guard the toss sound on `action.value != 0`** in `GameObserver.actionIsPending` (`GameObserver.swift:41-50`) so parking a die is silent (§5.4).
- **Guard the `defer` in `loadPinThumbnail`** so it only clears `pendingThumbnailTasks[pinId]` when the entry is its own task (`GameTableModel+PinThumbnails.swift:23-28`) (§3.1).
- **Fix `Die.makeFallbackEntity`**: `generateBox(size: 140)` is 140 *metres* because `Die` is never scaled (`GameEquipment.swift:774-782`) (§5.10).
- **Delete unused `Utils3D.swift` helpers** — `Double.lerp`, `Point2D.lerp/+`, `Pose2D.lerp/*`, `transformPoint` have no call sites; only `simd_float4x4.translation` and `Pose3D.cursorTransform` are used (§9.2).
- **Delete unused symbols**: `GameTableRealityView` typealias (`GameTableView+PlatformFlat.swift:118`), `GameTableModel.movePointerToMapCenter` / `setAllRoomsShown` (`GameTableModel+ToolBar.swift:97-129`), portable `GameRenderer.applyScale/placeTable` (`GamePortableRenderer.swift:51-57`), `Die.playTossSound` unless wired (§9.2).
- **Drop the ignored `panOffset` parameter** from both `Board.updateMap` implementations and both fog renderers (`GameEquipment.swift:93,178-186`, `GamePortableEntities.swift:63-70,155-162`) (§9.1).
- **Correct stale doc**: `GameTableModel.swift:107-113` says the table has "currently 2" non-master seats and "the 4th table side is reserved for the shared die/deck". `PlayerSeat.seatPoses` defines 5 player seats (`GameEquipment.swift:352-365`) (§9.6).
- **Rename `EquipmentIdentifier.tableID`** to `tableId` (`GameEquipment.swift:19,35,621,743`) per the project's `Id` casing rule (§4.3).
- **Replace `Date.now` in `StaleGestureTracker`** with `ContinuousClock` (`StaleGestureTracker.swift:22,33`) (§4.1).

---

## 3. Concurrency

The module is otherwise disciplined: `@MainActor` on every model/controller, no `DispatchQueue`, `Task.sleep(nanoseconds:)`, `nonisolated(unsafe)`, `@unchecked Sendable` or `Task.detached` (grep-verified), and a single-slot `replaceTask` pattern for fog/map tasks. The items below are the exceptions.

### 3.1 Superseded thumbnail task erases its successor's tracking entry
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+PinThumbnails.swift:22-28,57-60`; spawned in `GameTableProjection.swift:203-209`
- **What:** `loadPinThumbnail`'s `defer` unconditionally does `pendingThumbnailTasks[pinId] = nil`. `trackThumbnailTask` cancels the *old* task and stores the *new* one. When the old task finishes/cancels later, its `defer` wipes the new task's entry.
- **Why:** The new task is no longer cancellable by a later supersede or by `GameTableModel`'s `isolated deinit` (`GameTableModel.swift:183-185`), so a load can outlive its model or race a still-newer photo. The `pendingPinPhotoIds` half of the same `defer` is correctly guarded (`== photoId`); the tasks half is not.
- **Action:** Mirror the existing guard: only clear the slot if it still holds this task (e.g. carry a token, or compare the stored task identity).
- **Severity:** Medium

### 3.2 `updateFogOfWar` is called directly from another module, bypassing the documented choke point
- **Location:** `Modules/GameRPG/Controller/PlayerController+MapPresentation.swift:106` → `GameTableModel+MapSync.swift:162`
- **What:** `GameTableModel` documents `replaceFogOfWarTask` as the *only* entry point for fog recomposites (`GameTableModel.swift:136-141`, `GameTableModel+MapSync.swift:143-149`). `refreshMapVisuals` calls the internal `updateFogOfWar(isGameMaster:)` directly.
- **Why:** That call is not cancellable and can interleave with the model's own `fogOfWarTask`/`mapChangeTask`. It also writes `self.isGameMaster` from a controller-supplied value (§3.5).
- **Action:** Route it through `replaceFogOfWarTask` (or a public `refreshFog()` wrapper) and make `updateFogOfWar` `private`.
- **Severity:** Medium

### 3.3 `waitForFirstRenderedFrame` holds a single continuation slot
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+RenderingReadiness.swift:31-45`; storage `GameTableModel.swift:49-51`
- **What:** A second concurrent call overwrites `pendingRenderWaitContinuation`, so the first continuation is never resumed and its subscription is orphaned.
- **Why:** Currently only one `.task` calls it (`GameTableView+VisionOS.swift:202-205`), so this is latent. A window re-appearing while the first wait is still pending would hang that earlier task forever.
- **Action:** Resume any existing continuation before storing a new one, or make the wait re-entrant-safe by design.
- **Severity:** Low

### 3.4 `handleMapChange` awaits an unstructured task; caller cancellation is not propagated and a superseded call returns as "done"
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+MapSync.swift:28-43,45-93`
- **What:** `handleMapChange` returns `await replaceMapChangeTask(...).value`. The inner `Task` does not inherit cancellation from the caller (the SwiftUI `.task(id:)`), and if a newer call cancels it the awaiter returns normally without work having been applied.
- **Why:** Callers such as `initializeGameIfNeeded` (`GameTableView+VisionOS.swift:468-472`, `GameTableView+PlatformFlat.swift:108-112`) proceed to `syncPawnsWithMapPins()` as if the map were loaded.
- **Action:** Have `handleMapChange` observe `Task.isCancelled` / report whether its own request won; or await the newest task in a loop.
- **Severity:** Low

### 3.5 Role state (`isGameMaster`) has three independent writers
- **Location:** `GameTableModel+MapSync.swift:46-47,163`; `GameTableView+VisionOS.swift:555-559`; `GameTableView+PlatformFlat.swift:80-84,100-104`
- **What:** `performMapChange` and `updateFogOfWar` overwrite `self.isGameMaster` from their parameter, while the views set it separately from `gameConfig.isMaster`. `performMapChange` writes it *before* the cancellation checks, so a superseded request still mutates it.
- **Why:** All current callers pass the same value, so it is consistent today, but permission-gating (`canMovePin`, every `toggleSelected…`) reads this one flag.
- **Action:** Set role once (from `configureSessionState`) and pass it by reading the model, not by parameter.
- **Severity:** Low

---

## 4. API modernity

### 4.1 Wall-clock `Date.now` used for gesture timeouts
- **Location:** `Modules/GameRPG/Table3D/StaleGestureTracker.swift:22,33`
- **What:** Staleness is computed from `Date.now`.
- **Why:** A wall-clock change (NTP/timezone/manual) can fake or hide staleness. `ContinuousClock` is the monotonic modern replacement.
- **Action:** Store a `ContinuousClock.Instant`.
- **Severity:** Low

### 4.2 Hard-coded stack spacing and padding
- **Location:** `GameTableView+VisionOS.swift:342,370`; `GamePinActionMenu.swift:26,74`; `GameTableView+VisionOS.swift:353`
- **What:** `VStack(spacing: 12)`, `.padding(.top, 12)`, `HStack(spacing: 12)`, `.padding(12)`, `HStack(spacing: 8)`.
- **Why:** `CLAUDE.md` says to avoid hard-coded padding/spacing unless requested.
- **Action:** Use default spacing/padding or shared design tokens.
- **Severity:** Low

### 4.3 `ID` casing on a public-facing identifier
- **Location:** `Modules/GameRPG/Table3D/GameEquipment.swift:19,35,621,743`
- **What:** `EquipmentIdentifier.tableID`.
- **Why:** Project convention is `Id`/`Url` (`CLAUDE.md`).
- **Action:** Rename to `tableId`.
- **Severity:** Low

### 4.4 Synchronous RealityKit/audio loads where async APIs exist
- **Location:** `Modules/GameRPG/Table3D/GameEquipment.swift:569,588-592,715,726-730`
- **What:** `Entity.load(named:in:)` and `AudioFileResource.load(named:from:in:)` (synchronous) inside `@MainActor` `init`s. `TableAssetFactory` already uses the async `Entity(named:in:)` (`TableAssetFactory.swift:23`).
- **Why:** Compiles cleanly (no deprecation warning), but blocks the main actor; see §7.1 for the cost.
- **Action:** Load once with the async API and clone (§7.1).
- **Severity:** Medium (tracked in §7.1)

### 4.5 `class` vs `final class` differs between platform twins
- **Location:** visionOS `GameSetup.swift:14`, `GameObserver.swift:9`, `GameRenderer.swift:12`, `GroupActivityManager.swift:9` (all non-final) vs iOS/macOS `GamePortableSetup.swift:12`, `GamePortableRenderer.swift:18` (`final`)
- **What:** Same type names, different finality.
- **Why:** Non-final `@MainActor` classes with no subclasses cost dispatch and mislead readers.
- **Action:** Mark visionOS types `final`.
- **Severity:** Low

### 4.6 `UIColor(Color)` conversions in render code
- **Location:** `GameEquipment.swift:280,283,291,293,297,306`; `GameTableEntities.swift:106,209,223`
- **What:** SwiftUI `Color` bridged to `UIColor`/`NSColor` for CoreGraphics and `UnlitMaterial`.
- **Why:** Acceptable for CGContext/RealityKit (no SwiftUI colour type accepted), but note `CLAUDE.md` warns against UIKit colours in SwiftUI. `Color`→`UIColor` also resolves against the *current* environment (dark mode), which can shift `.green`/`.red`.
- **Action:** Keep, but centralise in one platform-colour helper so resolution is consistent.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Full 5-player party: two players end up on the same seat, and no warning is raised
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+Seating.swift:143-173`; seat count `GameEquipment.swift:352-365`
- **What:** Seat index is `(localIndex % playerSeatCount) + 1` where `localIndex` is the participant's rank among **all** `activeParticipants` *including the master*. With master + 5 players there are 6 ranks (0…5) mapped onto 5 buckets, so ranks 0 and 5 both map to seat 1. Whenever the master's rank is 1–4 (4 of 6 orderings), both rank-0 and rank-5 players are players → shared seat/dice. `playerCount = sortedParticipants.count - 1 = 5` is not `> 5`, so `sharedSeatPlayerCount` stays `nil` and no log fires. The comment at lines 158-163 calls the miscount "harmless"; it is not.
- **Why:** Two players silently control the same 12 pooled dice, and each one's roll moves/overwrites the other's. Only a party of 6+ is flagged.
- **Action:** Exclude the master's participant from the ranking (the master identity is known via `gameConfig`/session metadata even if `activeParticipants` carries no marker), or rank players by their game id from the game model. Extract the mapping into a pure function so it can be unit-tested with participant-id lists (it is pure, unlike the TabletopKit calls around it).
- **Severity:** High

### 5.2 Model-held closure captures the SwiftUI view value → retain cycle through `@State` storage
- **Location:** `Modules/GameRPG/Table3D/GameTableView+VisionOS.swift:457-460` (also the re-assignment at `:425-428`); property `GameTableModel.swift:72`
- **What:** `game.applyFocusedDiceRollForLocalSeat = { [weak game] in … applyCurrentFocusedDiceRoll(to:) … }` — `applyCurrentFocusedDiceRoll` is an instance method, so the closure implicitly captures `self` (the `GameTableView` value). That value holds `@State game`/`activityManager`, whose storage boxes hold the model. Cycle: model → closure → view value → `@State` box → model. `[weak game]` only guards the parameter, not the implicit `self`.
- **Why:** After the volumetric window is dismissed and SwiftUI drops its own reference, the cycle keeps `GameTableModel`, `TabletopGame`, the RealityKit scene and `GroupActivityManager` alive. `GameTableModel`'s `isolated deinit` (observer/render-delegate removal, task cancellation) and `GroupActivityManager`'s `detachNetworkCoordinator()` (`GroupActivityManager.swift:20-22`) never run, so an old coordinated `TabletopGame` may remain attached to the SharePlay session when the window reopens. I have not run the Memory Graph; this is from reading the capture semantics.
- **Action:** Don't capture the view. Give the model a small handler object (or pass `root`/`DiceRoot` in) so the closure captures only reference-type dependencies. Confirm with Xcode's Memory Graph after closing/reopening the volume.
- **Severity:** High

### 5.3 visionOS build is broken at HEAD (outside Table3D, but blocks this table)
- **Location:** `Modules/GameRPG/SharePlay/RPGSharePlayController+TableCoordination.swift:16,23` (imports at `:4-7`)
- **What:** `error: static property 'sharePlay' is not available due to missing import of defining module 'CoreRPG' [#MemberImportVisibility]`. The file was created by `c931b6af` (RPGSharePlayController split) with `Combine`, `Foundation`, `GroupActivities`, `os.log` only.
- **Why:** `MasterRPG` cannot be built for visionOS, so none of the visionOS half of this audit could be compiler-verified for SIL-level diagnostics.
- **Action:** Add `import CoreRPG`. Then re-run the visionOS build and re-check for concurrency diagnostics in `GameObserver`, `GameInteraction`, `GroupActivityManager` (the `@preconcurrency` imports).
- **Severity:** High

### 5.4 Toss sound plays for every dice-pool update, including "park" moves; d6 never plays one
- **Location:** `Modules/GameRPG/Table3D/GameObserver.swift:41-50`; producers `GameTableModel+Dice.swift:60-91`; `GameEquipment.swift:649-653,765-771`
- **What:** `actionIsPending` plays `Die20.playTossSound()` for *any* `UpdateEquipmentAction<DieState>`. `applyDiceRoll` submits an update for all six D20 slots (active ones and parking ones with `value: 0`). Result: rolling one d20 yields ~6 overlapping sounds, five emitting from the off-table park point (-5,-5). `applyDiceRoll(.empty)` on window open (`GameTableView+VisionOS.swift:430,479`) plays six with no roll at all. `Die.playTossSound` (d6) has no call site.
- **Why:** Wrong audio feedback on every focus change/roll; d6 rolls are silent.
- **Action:** Ignore updates whose new value is `0` (parking) or whose old/new snapshot values are unchanged; call `Die.playTossSound` for `Die` equipment, or delete it if silence is intended.
- **Severity:** Medium

### 5.5 A cancelled map load leaves `currentMapId`/`currentPhotoId` advanced while the image is still the old map's
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+MapSync.swift:84-91,95-131`
- **What:** `performMapChange` sets `currentMapId` (line 84) and `loadMapPhoto` sets `currentPhotoId` (line 96) before awaiting the image fetch (line 112). If the request is cancelled at `:113` (each `refreshCurrentMap`/mapState refresh cancels the previous one), `currentMapImage`/`currentPhotoVersion`/`currentMapDegrees` still describe the *previous* map. The next request sees `mapChanged == false`, `mapModel.photoId == currentPhotoId`, and — if the two photos share `version` and `degrees` — `photoChanged == false` with a non-nil `currentMapImage`, so it takes the fog-only branch and composites the **old image under the new map's rooms**.
- **Why:** Wrong board image on the table (until the photo version changes). It needs equal `version`/`degrees` between the two photos, so it is conditional, but map switch followed by an immediate mapState refresh is the normal sequence.
- **Action:** Commit `currentMapId`/`currentPhotoId` together with the image/version/degrees only after a successful, non-cancelled load (or clear the image when starting a load for a different photo).
- **Severity:** Medium

### 5.6 Pin-scale slider does not resize the 3D pins until an unrelated sync
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+ToolBar.swift:32-35`; slider in `Modules/MapRPG/Map/GameToolBar.swift:236`; size read in `GameTableProjection.swift:48-52`
- **What:** `pinScale`'s setter only writes `currentMapModel()?.pinScale`. Pawn size is computed in `syncPins` (`pointsToMeters`), and nothing observes `pinScale` to trigger it. Neither table view has an `onChange` for it.
- **Why:** The shared toolbar's slider looks inert on the 3D table until some other action re-syncs pawns. Marked for on-device confirmation.
- **Action:** Call `syncPawnsWithMapPins()` from the `pinScale`/`hexScale` setters (or observe the map and re-sync).
- **Severity:** Medium

### 5.7 "Dice overflow" and "shared seat" notices exist only as write-only state
- **Location:** `Modules/GameRPG/Table3D/GameTableModel.swift:61,118`; writes at `GameTableModel+Dice.swift:94`, `GameTableModel+Seating.swift:123,133,149,165,170`
- **What:** Earlier audits (`CODE_AUDIT §5.1/§5.2`, quoted in the doc comments) say `GameTableView` will surface "N results not shown on table" and a shared-seat notice. Grep shows **no reader** of `diceOverflowCount` or `sharedSeatPlayerCount` anywhere in the repo.
- **Why:** The silent-drop and silent-seat-sharing behaviours those audits flagged are still silent to the user.
- **Action:** Render both in the ornament (visionOS) or remove the state. Combine with §5.1.
- **Severity:** Medium

### 5.8 Failed/ignored pin drop leaves the pawn where it was dropped
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+PinSelection.swift:75-79,103-119`
- **What:** `pinDragChanged` moves the pawn entity directly. `pinDragEnded` returns early if there is no map/image (`:77-79`), or if `movePointer`/`movePin` returns `false` (`:104,114-118`), without calling `syncPawnsWithMapPins()` to snap it back.
- **Why:** The pawn stays at the released position while the model still holds the old location — visible to the local user, and a subsequent sync can jump it.
- **Action:** Always resync pawns on drag end (success or failure).
- **Severity:** Medium

### 5.9 On iOS/macOS, dragging the map does nothing while a room is focused
- **Location:** `Modules/GameRPG/Table3D/GameTableView+PlatformFlat.swift:260-290`; no-op pan at `GameTableModel+Viewport.swift:63-71`
- **What:** `boardDragGesture` decides "pan viewport vs. move table" from `focusedRoomId != nil`. Panning has had no rendering effect since `boardFocusRect` stopped cropping, so with any room focused the one-finger drag on the map is swallowed (it is in a `.highPriorityGesture` chain) and does nothing, while without a focused room it moves the table.
- **Why:** Inconsistent, confusing input; also blocks camera orbit for that touch (§8.2).
- **Action:** Remove the pan branch (§9.1) so board drags always move the table.
- **Severity:** Medium

### 5.10 Fallback `Die` mesh is 140 metres wide
- **Location:** `Modules/GameRPG/Table3D/GameEquipment.swift:774-782` (used by `:714-721`); representation `:738`
- **What:** `Die20`'s fallback (`generateSphere(radius: 80)`) is sized for its `0.00025` scale (`:581-583`). `Die` never applies a scale, so `generateBox(size: 140)` renders at 140 m and `representation = .cube(height: extents.x)` is 140 m for toss physics.
- **Why:** Only reached on a packaging failure, but that is exactly the path the fallback exists for; the "degrade gracefully" goal is not met.
- **Action:** Size the box in metres (~0.07 m) or apply the same scale factor.
- **Severity:** Low

### 5.11 Asset-load failure is permanent for the session
- **Location:** `Modules/GameRPG/Table3D/GameRenderer.swift:76-88`; `GamePortableRenderer.swift:40-49`
- **What:** `didLoadAssets = true` is set *before* the `try await`, so a failed `makePlainWoodTable()` is logged once and never retried; pins and the map plane then float with no table.
- **Why:** Transient failure becomes permanent until the model is recreated.
- **Action:** Set the flag only on success (or retry once).
- **Severity:** Low

### 5.12 Player fallback re-claim can take the master's seat
- **Location:** `Modules/GameRPG/Table3D/GameObserver.swift:52-59`
- **What:** For a non-master whose seat becomes `nil` (with `canAutoClaimSeat`), the fallback is `claimAnySeat()`, which may return seat 0 if the master hasn't claimed yet, contradicting the "seat 0 is master" contract in `assignSeatsForSharePlay`.
- **Why:** Plausible seat-0 collision on reconnect; not reproduced.
- **Action:** Re-run the deterministic assignment (`assignSeatsForSharePlay`) instead of `claimAnySeat()`.
- **Severity:** Low

### 5.13 Pinch-to-resize can only shrink the table; hand tracking may not deliver in a volume
- **Location:** `Modules/GameRPG/Table3D/TableScaleGestureController.swift:25,46,65-84`; started at `GameTableView+VisionOS.swift:393-395`
- **What:** `maxScale = 1.01` (0.4…1.01), so the gesture is effectively shrink-only. Separately, `ARKitSession` `HandTrackingProvider` data is generally only delivered while the app has an open `ImmersiveSpace`; this table is a volumetric window in the Shared Space. `NSHandsTrackingUsageDescription` is present in the build settings (`project.pbxproj:8983,9053`).
- **Why:** The feature may be a silent no-op in production. I could not confirm on device, so treat as "verify".
- **Action:** Verify on device that anchor updates arrive in the volume; if not, replace with a SwiftUI `MagnifyGesture` on the `RealityView`.
- **Severity:** Medium (unverified)

---

## 6. Security

### 6.1 The GM's "pause sharing" toggle is ignored by the 3D table; hidden content is broadcast anyway
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+PinSelection.swift:107,109,121,123,168,170,178,200,210,217,224,238-239`; `GameTableModel+ToolBar.swift:79,93,107,114,128,140`; only honoured at `GameTableModel+Viewport.swift:122`
- **What:** `GameTableModel.isStreaming` (declared `GameTableModel.swift:91`; toggled by the shared `GameToolBar`, `GameToolBar.swift:156-160`) is documented as "the game master can still pause broadcasting toolbar-driven edits". The 2D editor honours it (`MapEditorActionRouter.swift:333,349`). The 3D model calls `broadcastMapState` unconditionally in every mutation, and reads `isStreaming` only in `syncAfterExternalEdit`.
- **Why:** A GM who switches sharing off to reveal a room, move a monster or unhide a pin privately still sends that state to every player immediately — a spoiler leak on the exact feature meant to prevent it.
- **Action:** Funnel all GM broadcasts through one `broadcastIfStreaming(mapId:)` helper (explicit "Refresh Shared Map"/`sendMapUpdates` bypasses it, as the protocol doc says). Add a test that toggling a room with `isStreaming == false` sends nothing.
- **Severity:** High

### 6.2 Any participant can toss any seat's dice, including the GM's
- **Location:** `Modules/GameRPG/Table3D/GameSetup.swift:109-145`; `GameInteraction.swift:37-69,82-88`; `GameTableModel+Dice.swift:109-120`
- **What:** All pool dice use `seatControl: .any` (documented as a workaround for seat-restricted equipment not rendering). `onTossStart` picks `Int.random(in: 1...20)` and syncs it; `tossDieForAccessibility` does the same by die id. Dice are draggable by anyone at any seat.
- **Why:** A player can re-roll or displace another player's — or the GM's — mirrored roll. The values are visual mirrors of character-sheet rolls rather than authoritative results, so this is integrity/griefing rather than a cheat vector, but it is the table's main interactive object.
- **Action:** Restrict toss/drag to the owning seat, or at least to owner + GM, once the rendering problem behind `.any` is understood (`.restricted` per seat with the local player's seat).
- **Severity:** Medium

### 6.3 Permission checks are client-side only
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+PinThumbnails.swift:65-71`; `GameTableModel+PinSelection.swift:59,77`
- **What:** `canMovePin` and the `isGameMaster` guards decide who may move/toggle; a modified client can send any `.mapPin` message.
- **Why:** Real enforcement must be on the receiving side (`MasterController+MapMessages`), which I did not audit.
- **Action:** Confirm the master validates that a player message only mutates that player's own pin (and the visible pointer).
- **Severity:** Low (unverified)

---

## 7. Performance

### 7.1 72 synchronous USDZ and audio loads on the main actor at table creation
- **Location:** `Modules/GameRPG/Table3D/GameSetup.swift:103-146`; `GameEquipment.swift:561-599,709-737`; created from `GameTableModel.init` (`GameTableModel.swift:165-181`)
- **What:** 6 seats × (6 `Die20` + 6 `Die`) = 72 dice, each doing a synchronous `Entity.load(named:)`, an `AudioFileResource.load`, `prepareAudio` and `SpatialAudioComponent()`.
- **Why:** A multi-hundred-ms main-actor stall when the volume opens (needs Instruments; RealityKit may cache the file, but the entity cloning and audio setup still run 72 times), plus 72 audio playback controllers.
- **Action:** Load the die prototypes and both audio resources once (async), then `clone(recursive:)` per slot and share the `AudioFileResource`. Consider lazy pool growth if `TableSetup` constraints allow.
- **Severity:** Medium

### 7.2 `applyDiceRoll` re-submits all 12 slot updates every time, even for slots already in the target state
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+Dice.swift:60-91`; triggered from `GameTableView+VisionOS.swift:389-392,430,479` and `GameObserver.swift:74-78`
- **What:** Every focus change, roll, window open and seat-claim callback issues six D20 + six D6 `addAction`s, including parking already-parked dice.
- **Why:** Each is a synced TabletopKit action over SharePlay (routed through the FaceTime relay, per project notes), plus the sound in §5.4. Six participants opening the window sends ~72 redundant actions.
- **Action:** Diff against the current snapshot (`value`/`pose`) and only submit changed slots.
- **Severity:** Medium

### 7.3 Board texture composite (and `TextureResource` build) runs on the main actor
- **Location:** `Modules/GameRPG/Table3D/GameEquipment.swift:178-320` (`@MainActor`), `:143-157`; `GamePortableEntities.swift:154-300`
- **What:** The CoreGraphics compose (up to 2048² px) and texture creation happen synchronously on the main actor for every fog-affecting change. The code's own comment (`GameEquipment.swift:199-201`) records that an earlier 3× scale "stalled room toggles on the main actor".
- **Why:** Room toggles and reveals hitch the UI, worst on large maps or iPhone.
- **Action:** Render the `CGImage` off the main actor (CGContext drawing is thread-safe; pass only value-type inputs), then create the `TextureResource` on the main actor. The existing `renderSignature` already avoids redundant renders.
- **Severity:** Medium

### 7.4 `RoomHitArea` collision hulls are rebuilt for every room on every pawn sync
- **Location:** `Modules/GameRPG/Table3D/GameTableProjection.swift:133-142`; `GameTableEntities.swift:313-334`
- **What:** `syncRooms` calls `area.update` → `generateConvex(from:)` and a fresh `CollisionComponent` for *every* room on *every* `syncPawnsWithMapPins()`. The doc says "Always rebuilds", but the projection is constant now that the board never crops.
- **Why:** Every pin drop, highlight, battle-round tick and network mapState pays this for all rooms.
- **Action:** Cache a `(coordinates, planeSize)` signature per area and skip when unchanged.
- **Severity:** Medium

### 7.5 Failed thumbnail loads retry on every sync
- **Location:** `Modules/GameRPG/Table3D/GameTableProjection.swift:83-85,203-209`; `GameTableModel+PinThumbnails.swift:22-47`
- **What:** When a load ends without setting `pawn.loadedPhotoId` (missing photo/thumbnail), the `defer` clears `pendingPinPhotoIds`, so the next `syncPins` schedules a new `Task` (cache lookup, `itemControllable.item(for:)`, thumbnail generation) — on every mapState, drag or battle tick.
- **Why:** Unbounded retry churn for any pin whose photo is unavailable.
- **Action:** Record a failed `(pinId, photoId)` and don't retry until the pin's `photoId` changes (or back off).
- **Severity:** Medium

### 7.6 `PinPawn.update` allocates materials and components on every sync
- **Location:** `Modules/GameRPG/Table3D/GameTableEntities.swift:208-233,258-263`
- **What:** New `UnlitMaterial`s for base and ring, `OpacityComponent` set/remove, and `AccessibilityComponent` re-set per pin per sync, with no change detection (only size is diffed).
- **Why:** With dozens of monsters and syncs fired from ~10 call sites (`syncPawnsWithMapPins` fan-in, incl. every viewport pan), this is steady garbage and needless RealityKit component churn.
- **Action:** Cache last applied `(healthColor, ringColor, dead, opacity, name/value)` and skip identical updates.
- **Severity:** Low

### 7.7 The whole `table_assembly` USDZ is loaded just to borrow one material
- **Location:** `Modules/GameRPG/Table3D/TableAssetFactory.swift:19-48`
- **What:** `makePlainWoodTable` loads the full decorative table entity, takes the first material, and discards the mesh. The borrowed material was UV-mapped for the original mesh, not for `generateBox`.
- **Why:** Memory/time cost per model creation for a cosmetic; wood texture may stretch on the generated box.
- **Action:** Cache the material once per process, or ship a dedicated wood material asset.
- **Severity:** Low

### 7.8 Hand-tracking loop and dice signature do per-frame/per-body work
- **Location:** `Modules/GameRPG/Table3D/TableScaleGestureController.swift:78-80`; `GameTableView+VisionOS.swift:547-553`
- **What:** `processHandAnchor` runs on the main actor for every hand update; `focusedDiceSignature` builds an `[Int]` on each view-body evaluation for `onChange`.
- **Why:** Small but continuous main-actor work.
- **Action:** Throttle hand updates; compute the signature in the model/controller and observe that.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 Pin action menu may overflow on iPhone
- **Location:** `Modules/GameRPG/Table3D/GamePinActionMenu.swift:26-75`; overlay `GameTableView+PlatformFlat.swift:222-225`
- **What:** Up to six round buttons in a single `HStack`, no `ScrollView`/wrapping, pinned to the bottom of a full-screen `RealityView`.
- **Why:** Likely clipped or squeezed in iPhone portrait or with large accessibility sizes. Not run on device.
- **Action:** Use `ViewThatFits`/`ScrollView(.horizontal)` or a two-row layout.
- **Severity:** Low (verify)

### 8.2 macOS/iOS: all one-finger/mouse drags are captured, so the camera cannot be orbited
- **Location:** `Modules/GameRPG/Table3D/GameTableView+PlatformFlat.swift:171-210`
- **What:** `.realityViewCameraControls(.orbit)` is kept for pinch-zoom/rotate, but a `.highPriorityGesture` chain (pin → board → table-move) claims every drag. On macOS a mouse drag can therefore never orbit; only wheel/pinch zoom remains (unverified).
- **Why:** Limits the "3D" value on Mac; the table-move-only interaction is also scaled by a hand-tuned `0.001` (`:346`), not derived from the camera.
- **Action:** Bind orbit to a modifier key/secondary button on macOS or add explicit camera controls; also add Mac menu commands (the module has no `Menu/` entries for the table).
- **Severity:** Medium

### 8.3 iOS/macOS table has no dice or seats (visionOS-only feature)
- **Location:** `Modules/GameRPG/Table3D/GameTableModel+Dice.swift:18-122`, `GameTableModel+Seating.swift:19-186` are all `#if os(visionOS)`; toolbar `GameTableView+VisionOS.swift:367`
- **What:** The dice bar, dice pool and seating exist only on visionOS; the flat table shows map, fog and pins.
- **Why:** By design, but undocumented in `CLAUDE.md`, and the doc comments imply parity.
- **Action:** Document the intended parity matrix; if dice mirroring is wanted on iOS/macOS, it needs a non-TabletopKit implementation.
- **Severity:** Low (info)

### 8.4 Room hit volumes exist for players and absorb input they cannot act on
- **Location:** `Modules/GameRPG/Table3D/GameTableProjection.swift:118-148`; actions gated in `GameTableModel+ToolBar.swift:74-94`
- **What:** `syncRooms` builds `InputTargetComponent` volumes for every role. Player double-tap/long-press on a fog region runs `toggleRoomVisibility/Focus`, which silently returns for non-masters.
- **Why:** Silent dead taps; also a non-master could interact with `HoverEffectComponent` highlights on rooms they cannot use.
- **Action:** Skip `syncRooms` (or omit `InputTargetComponent`/hover) when `!isGameMaster`.
- **Severity:** Low

### 8.5 Accessibility: pins, rooms and dice are labelled; the board and fog state are not
- **Location:** `Modules/GameRPG/Table3D/GameTableEntities.swift:145-152,300-306`; `GameEquipment.swift:627-632,746-751`; board `GameEquipment.swift:43-83`
- **What:** Good coverage of pins/rooms/dice (labels, values, activate/custom actions, localized via `.module`). The map plane and pointer have no accessibility element or summary (hidden vs. shown room count, current map name).
- **Why:** A VoiceOver user cannot discover what map is shown.
- **Action:** Add a single accessibility element on the board with the map name and room counts.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Vestigial viewport-pan pipeline (still wired end-to-end, does nothing visible)
- **Locations:** `GameTableModel.swift:153-162` (`manualViewportOffset`, `lastFocusedRoomId`); `GameTableModel+Viewport.swift:32-34,49-54,56-112` (`boardFocusRect` ignores `entries` and `panOffset`; two `panViewport` methods); `GameTableView+VisionOS.swift:103-111,236-253`; `GameTableView+PlatformFlat.swift:131-139,260-290`; `panOffset` parameter through `GameEquipment.swift:93,178-186`, `GamePortableEntities.swift:63-70,155-162`, `GameTableProjection.swift:21,118,152-165`; `renderSignature` doc `GameTableModel+MapSync.swift:216-223`.
- **What:** The docs repeatedly say the 3D board "never crops/zooms", that the pan "has no rendering effect", and that it is "kept so the gesture itself doesn't need touching". It still allocates gesture state, `StaleGestureTracker`s, a projection, and a `syncPawnsWithMapPins()` per drag, and on iOS/macOS it steals the drag (§5.9).
- **Action:** Delete the whole chain; simplify `boardFocusRect` to a constant and drop `panOffset`/`viewportPan` parameters.
- **Severity:** Medium

### 9.2 Unreferenced code
- `Utils3D.swift:8-47` — `Double.lerp`, `Point2D.lerp/+`, `Pose2D.lerp/*`, `transformPoint` (Apple-sample leftovers; no call sites).
- `GameEquipment.swift:765-771` — `Die.playTossSound` (never called; see §5.4).
- `GameInteraction.swift:91-100` — `onPhaseEnded` is a no-op after an early return.
- `GameTableView+PlatformFlat.swift:118` — `GameTableRealityView` typealias (0 references).
- `GameTableModel+ToolBar.swift:97-129` — `setAllRoomsShown`, `movePointerToMapCenter` (0 references); `:27-30` `isPointing` setter is `{}`.
- `GamePortableRenderer.swift:51-57` — `applyScale`, `placeTable` (visionOS-only callers).
- **Severity:** Low (≈120 LOC removed)

### 9.3 Fog/board compositing is implemented twice and has already diverged
- **Locations:** `GameEquipment.swift:93-159,178-320` vs `GamePortableEntities.swift:63-132,150-301`; plane fit-box math also in `GameTableProjection.swift:288-299`
- **What:** Two ~130-line CG renderers and three copies of the fit-box calculation. Divergences today: visionOS uses `image.fixedSize`, portable uses `image.size` (with a comment explaining why); visionOS draws fog as `black` when `displayConfig` is nil, portable draws nothing; visionOS `updateMap` bails when the map's stored `width/height` is 0 (`GameEquipment.swift:102-105`), portable falls back to the image size (`:71-80`); different pre-filtering of entries.
- **Why:** The nil-`displayConfig` case is unreachable today (`MapModel.displayConfig` is non-optional and both callers pass it), but nothing prevents it becoming a player-side fog leak on iOS/macOS. Every fix must be made twice.
- **Action:** Extract one shared `BoardTextureRenderer` and one `MapTableProjection.fitBox`; keep only entity/material application per platform. Cover with a pure-Swift test that renders a fixture map on iOS Simulator.
- **Severity:** Medium

### 9.4 Two parallel type families under `#if`
- **Location:** `GameSetup`/`GameRenderer`/`Board` exist twice (visionOS: `GameSetup.swift`, `GameRenderer.swift`, `GameEquipment.swift`; iOS/macOS: `GamePortable*.swift`).
- **What:** Same names, different shapes (§4.5); the visionOS `Board` lives inside the 784-line `GameEquipment.swift` with seats and dice.
- **Action:** Introduce a small shared protocol/base for what `GameTableModel` and `GameProjection` need, and move each `Board` to its own file.
- **Severity:** Medium

### 9.5 Oversized files (>500 LOC)
- **`GameEquipment.swift:784`** — split into `Board` (visionOS), `PlayerSeat` + layout, and `Dice` (`Die`, `Die20`, `DiceComponent`, parked pose).
- **`GameTableView+VisionOS.swift:596`** — move `GameTableView` sizing statics, gesture chain and ornament stack into small `View`/modifier types; the 130-line comment block on `.task` is design history and belongs in `Docu/`.
- **Severity:** Medium

### 9.6 Doc comments narrate change history, are misplaced, or are stale
- **Locations:** `GameTableModel+Seating.swift:51-75` (25-line "Removed 2026-08-23" block attached to nothing); `:93-109` (`assignSeatsForSharePlay`'s doc sits above `claimSeatIfNeeded`, leaving `assignSeatsForSharePlay` undocumented); `GameTableModel.swift:107-113` ("currently 2" seats vs 5); many `See CODE_AUDIT §x.y` references whose numbering is ambiguous (files are `Docu/CODE_AUDIT_9.md`, `_10`, …).
- **Action:** Keep the invariant, drop the history; reference `Docu/CODE_AUDIT_N.md` explicitly.
- **Severity:** Low

### 9.7 Unresolved TODOs / FIXMEs
_No findings._ `grep` for `TODO|FIXME|HACK|XXX|#warning|#if false` in Table3D returned nothing.

### 9.8 Magic constants
- `2_048` texture cap: `GameEquipment.swift:203` and `GamePortableEntities.swift:152`.
- Fog line widths `8`/`10`: `GameEquipment.swift:284,309`, `GamePortableEntities.swift:271,292` (in canvas points, so they scale with map size).
- `0.00025` die scale: `GameEquipment.swift:581-583,613`.
- Hit-test coupling `±0.004` / `-0.006`: `GameTableEntities.swift:324` vs `GameEquipment.swift:90` / `GamePortableEntities.swift:61`.
- `0.09` menu offset `GameTableModel+PinSelection.swift:49`; `4.0` zoom `GameTableEntities.swift:201`; `(-5,-5)` park pose `GameEquipment.swift:485`; dice spacing `0.15` `GameEquipment.swift:433`; `tableMoveScale` `0.001`.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Extract pure logic so it can be tested off-device.** Seat assignment (§5.1), dice layout (`PlayerSeat.diceLayout`), `MapTableProjection`, and the fog renderer (§9.3) are pure functions currently interleaved with TabletopKit/RealityKit calls. Existing tests (`Tests/GameRPGTests/GameTableControlTests.swift`, `GameTablePinPawnTests.swift`) cover some pawn/control behaviour; the seat-collision and streaming-gate bugs slipped through because those paths have no unit-level seam.
2. **One broadcast funnel for the GM.** §6.1 exists because ~20 call sites each decide whether to send. A single `broadcastIfStreaming` (and a lint/test that no other file calls `networkActions?.game(…, .mapState, …)` from Table3D) prevents recurrence.
3. **Never capture a `View` value in a model-held closure.** §5.2 (and the accessibility-subscription closures at `GameTableView+PlatformFlat.swift:396-413`, `GameTableView+VisionOS.swift:138-155`, which are only unwound by `onDisappear`) all depend on the view being torn down cleanly. Pass reference-type dependencies or a handler object.
4. **Make syncs idempotent and diff-based.** §7.2, §7.4, §7.6 and §7.5 are all "write everything on every sync". A last-applied-state cache per pawn/room/die makes the fan-in from ten call sites safe.
5. **Finish or delete features.** §5.7 (notices), §9.1 (viewport pan), §9.2 (dead helpers) and the unreachable `displayConfig` fallback are half-states left by earlier audit passes. Prefer deletion to "kept so it doesn't need touching".
6. **Keep the two platform implementations from drifting.** §9.3/§9.4 — one shared core with thin platform adapters, plus a parity checklist in `CLAUDE.md`.
7. **Move design-history prose into `Docu/`** (§9.6): the code should state invariants; the debugging saga (TabletopKit crash root causes, clearance measurements) is valuable but belongs in a doc.

---

## 11. What was NOT audited

- **visionOS SIL-level concurrency diagnostics** — the visionOS build fails (§5.3) before those passes run. Re-audit `GameObserver`, `GameInteraction`, `GroupActivityManager`, `TableScaleGestureController` after the build is fixed.
- **TabletopKit / RealityKit / ARKit internals** and on-device behaviour: toss physics, shared-simulation join, hand-tracking delivery inside a volume (§5.13), hover effects, texture memory.
- **SharePlay/network internals.** `RPGSharePlayController*`, `MasterController*`, `PlayerController*` were read only at the seams cited; see `Docu/CODE_AUDIT_Network.md` for that surface. Receive-side permission validation (§6.3) is unverified.
- **`MapRPG` internals** (`GameToolBar`, `MapEditorActionRouter`, `MapModel`) — read only for the contract Table3D depends on.
- **`Resources/RPGTabletopGameContent`** (USDZ/Reality Composer Pro assets) and `Tests/` beyond name-matching (no deep coverage review; snapshot tests not opened).
- **Instruments/performance profiling** — §7 items are inferred from code, not measured.
- **Runtime UX on iPhone/iPad/Mac** — §8.1/§8.2 are from reading the gesture and layout code; no simulator runs.
- **Build settings, entitlements, Info.plist** beyond confirming `NSHandsTrackingUsageDescription` exists.
- **Localization wording** — strings use `.module` bundle correctly, but catalogue completeness was not assessed.
- **tvOS** — Table3D is `#if os(iOS) || os(macOS) || os(visionOS)` and excluded from `MasterTV`.

---

## 12. Verification

Open Xcode, command-click each `path:line` — it should land on the cited line. Every High and every Medium that carries a behavioural claim is listed. (No Critical findings were assigned, so no Critical was propagated unverified.)

- **§5.3** — open `Modules/GameRPG/SharePlay/RPGSharePlayController+TableCoordination.swift`, lines `4-7` (imports, no `CoreRPG`) and `16`, `23` (`Logger.sharePlay`). Build `MasterRPG` for visionOS Simulator to reproduce.
- **§5.1** — open `Modules/GameRPG/Table3D/GameTableModel+Seating.swift`, lines `143-173`: `localIndex` is the index in the sorted list that includes the master (`145-147`); `seatIndex = (localIndex % playerSeatCount) + 1` (`157`); `playerCount = count - 1` (`163`) is compared with `>` (`164`). Then `GameEquipment.swift:352-365` shows 6 poses → `playerSeatCount == 5`.
- **§6.1** — open `GameTableModel+PinSelection.swift:107,109,121,123,168,170,178,200,210,217,224,238-239` and `GameTableModel+ToolBar.swift:79,93,107,114,128,140`: none check `isStreaming`. Compare `GameTableModel+Viewport.swift:122` (only check) and `Modules/MapRPG/Map/MapEditorActionRouter.swift:333,349` (2D checks it).
- **§5.2** — open `GameTableView+VisionOS.swift:457-460`: closure body calls `applyCurrentFocusedDiceRoll(to:)` (a method on the view struct → implicit `self` capture); `:96-98` shows `@State game`/`activityManager`; property stored on the model at `GameTableModel.swift:72`.
- **§5.4** — open `GameObserver.swift:41-50` (no value check) and `GameTableModel+Dice.swift:60-91` (parking updates issued for all six D20 slots).
- **§5.5** — open `GameTableModel+MapSync.swift:84` (`currentMapId` set), `:96` (`currentPhotoId` set), `:112-113` (await + cancellation return), `:124-131` (image/version committed only after).
- **§5.6** — open `GameTableModel+ToolBar.swift:32-35` (setter mutates the model only) and grep `pinScale` in `Table3D/` for the absence of a re-sync trigger.
- **§5.7** — grep `diceOverflowCount|sharedSeatPlayerCount` across `Modules`: only assignments (`GameTableModel+Dice.swift:94`, `GameTableModel+Seating.swift:123,133,149,165,170`).
- **§5.9** — open `GameTableView+PlatformFlat.swift:264-276` (`pansViewport` from `focusedRoomId`) and `GameTableModel+Viewport.swift:63-71` (`manualViewportOffset` written; nothing reads it for rendering).
- **§6.2** — open `GameSetup.swift:109-145` (`seatControl` left at `.any`) and `GameInteraction.swift:82-88` (random result applied to any tossed `Die20`).
- **§7.1** — open `GameSetup.swift:127-143` (loop creating `Die20`/`Die` per slot per seat) and `GameEquipment.swift:569,588-592`.
- **§7.2** — open `GameTableModel+Dice.swift:60-91`.
- **§7.4** — open `GameTableProjection.swift:133-137` and `GameTableEntities.swift:313-316`.
- **§9.3** — open `GameEquipment.swift:102-105,193-197,291` versus `GamePortableEntities.swift:71-80,254,273-283`.

If any finding doesn't reproduce when you visit the line, ping me with the specific reference and I'll re-investigate.
