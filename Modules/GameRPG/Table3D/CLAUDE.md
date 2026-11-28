# 3D Game Table (`Modules/GameRPG/Table3D`)

Two implementations share one model (`GameTableModel`), `Board`/`BoardTextureRenderer`, `MapTableProjection`, `PinPawn` and `RoomHitArea`:
- **visionOS**: a volumetric TabletopKit table with seats, a pre-allocated dice pool per seat (`GameDice.swift`), SharePlay seat assignment (`TableSeatAssignment`) and pinch-to-scale.
- **iOS/macOS**: a camera-based RealityKit table (`GamePortable*`, `GameTableView+PlatformFlat`) showing map, fog and pins. It has **no dice or seats by design**. On macOS a bare mouse drag orbits the camera; on iOS it moves the table.

## Rules
- Every game-master edit is broadcast through `broadcastMapEdit(for:)`, which honours the "pause sharing" toggle (`isStreaming`). Only `sendMapUpdates()` (explicit "Refresh Shared Map") calls `broadcastMapState(for:)` directly.
- Fog/board renders go through `replaceFogOfWarTask()` / `handleMapChange` (cancel-then-replace). Never call the render pipeline directly from another module; use `refreshFogOfWar(isGameMaster:)`.
- A closure stored on the model must never capture a SwiftUI view value (its `@State` storage holds the model).
- Keep syncs idempotent: `PinPawn.update`, `RoomHitArea.update` and `applyDiceRoll` skip unchanged state because they run on every map sync (each TabletopKit action is a SharePlay message).
- On visionOS the 3D table is the game (`GameTablePresentationController`): the start window shows `GameTableLaunchView`, which opens the table (once per game, `GameTableAutoOpenPolicy`) and closes itself. The table window hosts the running game (`gameTableGameHost`: window requests; the game ends when the game stops; closing the table with the system button brings the start window back, which asks whether to quit, because visionOS cannot veto a window close) and `endGame()` opens the start window again. There is no 2D game screen and no Recover window on visionOS.
- Put decisions that don't need TabletopKit/RealityKit in pure types (`TableSeatAssignment`, `MapTableProjection`) so they can be unit-tested on iOS.
- visionOS-only test suites need the workaround in the `build-verify` skill.
