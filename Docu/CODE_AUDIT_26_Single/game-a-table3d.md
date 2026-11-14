Area: Modules/GameRPG/Table3D (47 Swift files, ~7.3k LOC). I read every file in full or near full, except `GameTableModel+PinThumbnails` internals beyond the load path and the pure dice-layout helpers (`TableSeatDice`, `TableGuestDice` skimmed). I also read the memory notes (table3d-pin-geometry, tabletopkit-dice-rest, attachment-enable crash) and Docu/CODE_AUDIT_3dTable.md. The module is in good health: the CLAUDE.md rules for this module are respected (every GM edit goes through `broadcastMapEdit`/`broadcastMapContentEdit`, only `sendMapUpdates` calls `broadcastMapState` directly; fog goes through `replaceFogOfWarTask`; no closure stored on the model captures a view; `PinPawn.update`/`RoomHitArea.update`/`updateDieSlot` skip unchanged state; pure types exist and are tested). No GCD, no `nonisolated(unsafe)`, no `@unchecked Sendable`, no `ObservableObject`. The one real finding is a privacy gap in the visionOS dice mirroring; everything else is Medium/Low. All CODE_AUDIT_3dTable.md items I re-checked (dead `Utils3D` helpers, `movePointerToMapCenter`/`setAllRoomsShown`, `tableID` casing, thumbnail `defer`, toss sound on parked dice) are fixed.

### Table dice ignore the "share master/player dice" options
- Category: Security
- Location: Modules/GameRPG/Table3D/GameTableModel+Dice.swift:32-78 (`applyDiceRoll`), Modules/GameRPG/Table3D/GameTableView+VisionOS.swift:312-315, 465-476 (`applyFocusedDice`), Modules/GameRPG/Table3D/TableDiceResultRules.swift:80-90, Modules/GameRPG/Table3D/GameDiceResultPopover.swift:60-67
- What: Only the result popover consults `features.diceMaster`/`features.dicePlayers`; the dice themselves (value and orientation) are written to the TabletopKit state of the seat and synced to every participant without any feature check (`grep features Table3D` finds only the popover gate).
- Why: With "Share master dice with other players" off, a GM on Vision Pro who rolls a focused dice set still lands the dice face up on seat 0 of every player's table. The same holds for the "Share player dice" option between players at different seats. The 2D overlay, the network path (`PlayerController+Dice`) and the guest-seat path (`guestRolls`, already filtered at receive) honour the options, so this is an inconsistent leak of intentionally hidden GM rolls.
- Action: Decide the intended semantics (ask the user). Either mirror the GM/player dice onto the table only when the matching option is on (and park/unrolled-mask them otherwise, e.g. publish `TableDieValue.unrolled` face-up 1 plus no popover), or document that table dice are always public and relabel the options. Add a test on the pure decision in `TableDiceResultRules`.
- Severity: High
- Status: NEW

### Failed map photo load: state assignments are immediately undone and the load retries on every sync
- Category: Bug
- Location: Modules/GameRPG/Table3D/GameTableModel+MapSync.swift:124-134 (and `clearBoardImage` at Modules/GameRPG/Table3D/GameTableModel+Broadcast.swift:40-47)
- What: In the `image == nil` branch `currentPhotoId = photoId` and `currentPhotoVersion = metadata?.version` are set, then `clearBoardImage()` sets both back to `nil`; the intent ("remember which photo failed") is dead code.
- Why: `updateFogOfWar` sees `metadata?.version != currentPhotoVersion` and calls `loadMapPhoto` -> `fetchPhotoImage` again on every remote map update, pin move and fog toggle while the photo is missing (a player whose photo file has not arrived). Each retry is an async cache/disk lookup, and `fogSignature` stays `nil`.
- Action: Either drop the two dead assignments and document "retry on every sync" as intended, or keep the failed photo id/version after `clearBoardImage` (reorder) and retry only when the photo item changes, like `failedPinPhotos` does for pin photos.
- Severity: Medium
- Status: NEW

### GM "player" display mode still shows hidden pins and fogged monsters
- Category: Bug
- Location: Modules/GameRPG/Table3D/GameTableProjection.swift:21-50 (`syncPins`/`syncRooms` take `isGameMaster`), Modules/GameRPG/Table3D/GameTableModel+MapSync.swift:224-226 (`renderIsGameMaster`), Modules/GameRPG/Table3D/GameTableModel+PinSelection.swift:100-116 (`syncPawnsWithMapPins` passes `isGameMaster`)
- What: The board texture uses `renderIsGameMaster` (GM && displayMode != .player), but the pins and room hit volumes use the raw `isGameMaster`, so in the GM's "player" preview the fog is drawn as players see it while hidden pins (dimmed) and monsters inside fog stay visible.
- Why: The `displayMode` doc says it is "a rendering lens, how the board reads in another role"; the preview is therefore inconsistent and cannot be used to check what players see. Unverified against the 2D map's behaviour in the same mode.
- Action: Pass `renderIsGameMaster` to the pin filter (keep `hiddenForMaster` dimming off in that mode) and keep permission checks on the real role; add a test for the pin filter.
- Severity: Low
- Status: NEW

### Thumbnail task defer matches on photo id, not on task identity
- Category: Concurrency
- Location: Modules/GameRPG/Table3D/GameTableModel+PinThumbnails.swift:67-77, Modules/GameRPG/Table3D/GameTableProjection.swift:165-172 (`syncPawnsWithMapPins` cancels and later re-creates)
- What: When a pin is removed and re-added with the same photo, the cancelled old task still reaches its `defer`; `pendingPinPhotoIds[pinId] == photoId` is true for the new task's entry, so the old task clears the new task's `pendingPinPhotoIds` and `pendingThumbnailTasks` entries.
- Why: The new load becomes untracked (not cancellable by a later supersede or by `deinit`) and a following sync can start a duplicate load. Small window, harmless result (duplicate cache read), but the CODE_AUDIT_3dTable 3.1 fix is only partial.
- Action: Guard the defer with a per-load token (or compare the stored task identity) instead of the photo id.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_3dTable §3.1, partial]

### Pin-photo retry watchers are not cancelled in deinit
- Category: Concurrency
- Location: Modules/GameRPG/Table3D/GameTableModel+PinThumbnails.swift:46-58, Modules/GameRPG/Table3D/GameTableModel.swift:241-250 (`isolated deinit`)
- What: `deinit` cancels `pendingThumbnailTasks`, `fogOfWarTask` and `mapChangeTask`, but not `pinPhotoRetryTasks` (each is an `Observations` loop waiting for the photo item to change).
- Why: After a 2D<->3D toggle a model is released while watchers for pins with missing photos are still suspended; they hold only a weak `self` so nothing crashes, but the tasks and their observation registrations live until the photo item next changes (possibly never).
- Action: Cancel `pinPhotoRetryTasks.values` in `deinit` as well.
- Severity: Low
- Status: NEW

### Hand-tracking scale controller: wrong log category and permission prompt on every table open
- Category: API
- Location: Modules/GameRPG/Table3D/TableScaleGestureController.swift:66-83, Modules/GameRPG/Table3D/GameTableView+VisionOS.swift:325-327
- What: `start()` runs an `ARKitSession` with `HandTrackingProvider` for every table window, for every role, without checking authorization state first; both log lines use `Logger.sharePlay` although nothing is SharePlay related. The 3dTable audit's open item (5.13: maxScale 1.01 means the table cannot grow, hand tracking in a volume unverified) is unchanged.
- Why: A player who only wants to toss dice gets the hands-tracking permission prompt, and a denial is only logged. Logs end up in the wrong category when debugging.
- Action: Use `Logger.gameTable`; check/handle `session.queryAuthorization` and skip silently when denied; consider starting hand tracking only on demand.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_3dTable §5.13] (log category NEW)

### Same-named guests: group order tie-break is not stable
- Category: Bug
- Location: Modules/GameRPG/Table3D/TableGuestDice.swift:44-48
- What: Groups are ordered by `(name, dice.count)`; two guests with the same display name and the same number of dice compare equal, so their order (and thus which slots/positions each gets) depends on the input order of `sharedPlayerDice`, which is not the same on every device.
- Why: Every device must derive the same slot assignment because one device places the dice and all label them; with an equal key the popover can name the other guest on some devices. The view comment at Modules/GameRPG/Table3D/GameTableView+VisionOS.swift:492-493 says same-named guests keep their own dice, but the grouping does not carry the sender id.
- Action: Carry the sender id in `TableGuestRoll` and use it as the final sort key.
- Severity: Low
- Status: NEW

### Unscaled `UIGraphicsImageRenderer` bake for oriented photos has no pixel cap on iOS/visionOS
- Category: Performance
- Location: Modules/GameRPG/Table3D/GameTableEntities.swift:60-71 (`GameTableImage.cgImage`)
- What: For a non-`.up` `UIImage` the orientation is baked at full `size * scale` with no maximum, while the macOS branch caps at 4096 px; it runs on the main actor for the board (`BoardTextureInput.init`) and for each pin thumbnail.
- Why: A 12k x 9k camera photo allocates a ~430 MB bitmap on the main thread when the map is loaded. The cache normally downsamples, so this depends on what `fetchPhotoImage` returns (unverified).
- Action: Apply the same `maximumBitmapDimension` cap on UIKit platforms and render at the capped size.
- Severity: Low
- Status: NEW

### Board texture composite input and `TextureResource` upload run on the main actor
- Category: Performance
- Location: Modules/GameRPG/Table3D/GameBoard.swift:53-101, 176-215
- What: Only `BoardTextureRenderer.render` is `@concurrent`; `BoardTextureInput.init` (CGImage conversion/orientation bake, colour conversion for each map sync) and the mipmapped `TextureResource` creation still run on the main actor (the latter is awaited).
- Why: A fog toggle on a large map costs a main-thread image conversion each time. Known from CODE_AUDIT_3dTable 7.3; the render itself was moved off, the conversion was not.
- Action: Cache the converted `CGImage` per (photo id, version, degrees) in the model (`currentMapImage` already identifies it) so fog toggles reuse it.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_3dTable §7.3, partial]

### Pin base colour in the photo plane is only applied at creation
- Category: Bug
- Location: Modules/GameRPG/Table3D/GameTableEntities.swift:97-99 (creation), 262-272 (`AppliedVisual` without `pin.color`), 313-318 (`clearPhotoTexture`)
- What: `AppliedVisual` does not include `pin.color`, and the photo-plane tint is set from `pin.color` only in `init` and `clearPhotoTexture`; a pin whose colour is edited while the table is open keeps the old tint (also the entity name `Pin-<name>` is not renamed).
- Why: Rarely hit (colour edits happen in the map editor), cosmetic.
- Action: Add `color` to `AppliedVisual` and re-tint the face when no photo is loaded.
- Severity: Low
- Status: NEW

### Test gaps
- Category: Test gap
- Location: Tests/GameRPGTests (TableSeatAssignmentTests, GameTableProjectionTests, BoardTextureRendererTests, TableSeatDiceTests, TableGuestDiceTests, TableDiceResultTests, TablePopoverSourceTests, GameTableControlTests, TableMessageFlowTests exist)
- What: Nothing covers `GameTableModel.performMapChange`/`loadMapPhoto` cancellation and failed-photo behaviour (the finding above), `PinPawn`/`syncPins` visibility filtering per role and display mode (GameTablePinPawnTests is visionOS only and, per CODE_AUDIT_3dTable 10.1, was already stale), the player-moves-own-pin rules in `canMovePin`, and the hidden-dice decision above.
- Why: These are the paths where regressions have occurred before (health colour, session pins, map reshow).
- Action: Extract the pin visibility filter from `syncPins` into a pure function and test it for player/GM/preview; test `canMovePin` and the map-change state machine with a stubbed photo loader.
- Severity: Medium
- Status: [OPEN since CODE_AUDIT_3dTable §10.1]

### Oversized comment blocks narrate history
- Category: Refactor
- Location: Modules/GameRPG/Table3D/GameRenderer.swift:23-58, Modules/GameRPG/Table3D/GameTableView+VolumeSize.swift:7-60, Modules/GameRPG/Table3D/GameDice.swift:60-84, Modules/GameRPG/Table3D/GameTableView+VisionOS.swift:204-254, 416-450
- What: Many doc comments are 20-50 lines of change history ("an earlier version of this...", "tightened from 0.5 m") rather than current constraints. `GameTableView+VisionOS.swift` is 531 lines, of which ~35% comments.
- Why: Hard to read, and stale details drift (the 3dTable audit 9.6 flagged the same).
- Action: Cut each to the current rule plus one line of why; move the ornament history into the commit log.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_3dTable §9.6]

Not audited in this area: `TableSeatDice.swift` layout maths and `Tests/` internals (skimmed only); `RPGSharePlayController+TableCoordination.swift`, `WeatherTableEffect` and the MapRPG-side controllers the table calls (seams were read only to confirm contracts); visuals/gestures, TabletopKit synchronisation and attachment behaviour were reviewed from code only, nothing was run or built.
