# Audit: Modules/MapRPG/Map (map canvas, editor, rooms, fog, pencil, hit testing, undo)

Read in full: all 48 files of `Modules/MapRPG/Map/` (8,803 LOC) except the two small scale sliders' previews, plus the call sites they depend on (`MapPinActionView`, `EditController` hex/addMonsters/rescale, `MapModel.isSame`, `MapSnapshot.redactedForNonMaster`, `MapModel+Geometry`). Cross-checked against Docu/CODE_AUDIT_Map.md, CODE_AUDIT_21 (§7.8 room canvas culling, §5.19 hex scale) and CODE_AUDIT_25 (§7.3 "no change"). Nothing here was built or run; the findings are from reading code. Overall health is good: no force unwraps on reachable paths, no GCD, no `ObservableObject`, no `AnyView`, no stray `print`, all `@Observable` classes are `@MainActor`, pure geometry (pencil RDP, popover, loupe, hex grid, fog tile planner) is defensive about non-finite input. The real problems are quadratic or per-entry work that only bites on large hex maps (up to 20,000 cells, `MapHexGridGeometry.maxCells`), one wrong-target bug for pin drops on hex maps, and a few small geometry/gesture edge cases.

### Room list resets are O(n²) in the number of entries (hex maps)
- Category: Performance
- Location: Modules/MapRPG/Map/MapEditorSession+Content.swift:36-47 (`resetEntries`: `entries.entries.first(where:)` per incoming entry); Modules/MapRPG/Map/MapEditorActionRouter.swift:155-162 (`synchronizeRooms` calls `setEntry` for every entry); Modules/MapRPG/Map/MapEntryViewer.swift:95-101 (`setEntry`: `firstIndex` + `roomNodes.first` + `reconcileNeedlePoints` per call); same pattern in `toggleRoomFocus` edit branch (MapEditorActionRouter.swift:175-181)
- What: `resetEntries` scans the whole current entry list once per incoming entry before it even checks `workingCopy`; `synchronizeRooms` rewrites every entry through `setEntry`, which does two linear searches and rebuilds that entry's needle models, whether or not the entry changed.
- Why: At the 20,000-cell cap that is about 2x10^8 UUID compares per `resetEntries` and about 4x10^8 per room toggle, on the main thread. On a player's phone `resetEntries` runs for every master map update that changes `map.entries` (every room reveal, via `MapEditor.handleExternalEntryChange`); on the GM it runs on every room double tap and focus toggle. Noticeable hitch on big hex maps, scales quadratically.
- Action: In `resetEntries` check `workingCopy` first (player and GM game mode have none) and build an id-to-entry dictionary once. In `synchronizeRooms` only call `setEntry` for entries that differ, or give `MapEntryViewerModel` an id-to-index dictionary / a bulk `apply(updates:)`. Same for the focus loop.
- Severity: Medium
- Status: NEW

### Passive room store builds needle models for every entry
- Category: Performance
- Location: Modules/MapRPG/Map/MapEntryViewer.swift:65-71 (init), :208-250 (`reconcileNeedlePoints(with:)`/`(for:)`), :129-134 (`selectNeedle` walks all models); consumers only on `editEntries` (MapEditorSession.swift:243-273, NeedleMapPin.swift:14, MapEditorOverlayLayer.swift:189)
- What: `MapEntryViewerModel` is used for both the passive room store and the single active edit room, but needle point models (`@MainActor @Observable` class per vertex) are created for all entries of both. Grep shows needle APIs are only ever called on `rooms.active`.
- Why: A 20,000-cell hex map allocates about 120,000 observable objects on every `resetEntries` of the passive store (map open, every external entry change, hex rescale, every edit-mode room toggle via `syncDisplayEntries`), in game mode too where no needle exists.
- Action: Make needle tracking opt-in (a flag on the store, on only for `rooms.active`), or lazily create needle models for the active entry only.
- Severity: Medium
- Status: NEW

### `entry(for:in:)` returns hex-grid cells, so pin drops on a hex map are attributed to a cell, not a room
- Category: Bug
- Location: Modules/MapRPG/Map/MapEditorSession+Content.swift:161-163; callers MapEditController+Pins.swift:50 (edit drop), MapEditor.swift:299 (game drop), MapEditorActionRouter.swift:337-343 (editor character action)
- What: `entries.roomNodes.last { $0.path.contains(location) }` also matches the hex cells (appended last, covering the whole map), so with a hex grid active the "room under the point" is always a cell. `addMonsters` in the same controller knows to skip hex cells (`!$0.isHexGrid`, MapEditController+Pins.swift:77), this lookup does not.
- Why: In the editor, `appendCharacterLinks` then writes the character link into the hex cell's `content` (MapEditController+Rooms.swift:128-158), not the room the pin sits in; hex cells get new ids on every rescale, so the link silently vanishes. The real room is never found on a hex map.
- Action: Skip `isHexGrid` nodes in `entry(for:in:)` (or add a second lookup for hex), prefer topmost non-hex room; add a test with a hex grid plus a room.
- Severity: Medium
- Status: NEW

### Room hit layer creates one gesture view per room with no culling
- Category: Performance
- Location: Modules/MapRPG/Map/MapRoomCanvas.swift:196-212 (`MapRoomHitLayer`), :214-262 (`MapRoomHitTarget`); enabled by MapEditorSession.swift:113-124
- What: `ForEach(rooms.roomNodes)` builds a filled `Path` view, `contentShape`, a high-priority double-tap/long-press gesture, the viewport gesture modifier and three accessibility modifiers/actions for every room, including all hex cells.
- Why: Up to 20,000 such views are instantiated whenever the GM game surface or editor with no active room opens or entries are reset. The Canvas layer was culled in CODE_AUDIT_21 §7.8, the hit layer was explicitly left unchanged.
- Action: Cull to the visible rect (like `visibleContentRect`), or replace per-room views by one hit-test surface that resolves the room from the tap location through the existing path list (and offers the accessibility actions for the nearest rooms only).
- Severity: Medium
- Status: [OPEN since CODE_AUDIT_21 §7.8]

### Room culling pass still walks every node and recomputes `boundingRect` per frame
- Category: Performance
- Location: Modules/MapRPG/Map/MapRoomCanvas.swift:78-91 (`orderedSnapshots`), Modules/MapRPG/Map/MapEntryViewer.swift:18 (`bounds` is a computed `path.boundingRect`)
- What: The body filter runs for all nodes on every transform change; each iteration reads `node.bounds` (walks the path) and, through `@Observable`, registers observation on that node's `path`.
- Why: This is the cost CODE_AUDIT_25 §7.3 marked "no change" because culling exists; the culling itself is still O(n) with a path walk and an observation registration per node (20k on a hex map) on every pan/zoom frame, plus a second filter for `.fog`/`shown + hidden` arrays.
- Action: Store `bounds` as a stored property computed once in `makePath`/`update`, mark the node list `@ObservationIgnored` for the canvas read or snapshot it once per entry change, and optionally bucket nodes in a coarse grid for the visible query.
- Severity: Low
- Status: NEW (refinement of CODE_AUDIT_25 §7.3)

### Fog tiles are drawn for the whole room, not the visible part
- Category: Performance
- Location: Modules/MapRPG/Map/MapRoomCanvas.swift:146-169 (`drawFog` tile loops), :330-397 (`MapFogTilePlanner`, cap 4,096 tiles per room)
- What: Culling is per room; a large hidden room that is partly visible still issues up to 4,096 `layer.draw(symbol)` calls inside a clip layer per frame.
- Why: While panning a big player-side hidden room, each frame draws every tile of the room although most are off screen.
- Action: Intersect the column/row origins with the visible content rect before drawing (keep `MapFogTileBudget.allowsTiling` on the full bounds so 2D and 3D still agree).
- Severity: Low
- Status: NEW

### Hex scale slider in the editor rebuilds the whole grid on every tick and drops revealed state
- Category: Performance
- Location: Modules/MapRPG/Map/HexMapScaleView.swift:65-70 (`onChange(of: model.hexScale)` calls `onScaleChanged` for every value); Modules/MapRPG/Map/MapEditController+HexGrid.swift:41-60 (`updateHexScale`: `grid`, `replaceGrid`, `syncDisplayEntries`); toggle path :19-33
- What: The game toolbar defers the rebuild to slider release (`hexScaleCommit`, CODE_AUDIT_21 §5.19), the editor's `HexMapScaleView` still regenerates up to 20,000 entries and reconciles all room nodes per tick. The editor path also does not call `carryingRevealedArea`, so cells revealed in the editor (cells can be toggled there) are hidden again on every scale change, unlike the game path in `EditController.createHexMap`.
- Why: Main-thread stalls while dragging the slider on big grids; inconsistent behaviour between editor and game rebuild.
- Action: Rebuild on release (`onScaleEditingChanged(false)`) and keep the live value only in the slider; use `carryingRevealedArea` in `MapEditController.updateHexScale`/`toggleHexMap`.
- Severity: Medium
- Status: NEW (editor-side remainder of CODE_AUDIT_21 §5.19)

### Edit toolbar body does O(entries) work on every re-evaluation
- Category: Performance
- Location: Modules/MapRPG/Map/EditMapToolBar.swift:296-304 (`subtitleName`), :312-319 (`sharedMapHasChanges` runs `MapModel.isSame`, a deep compare of all entries and pins), :340-366 (`canIncrease`/`currentIndex` each filter the whole entry array through `EditController.editEntries(for:)`)
- What: Each toolbar body evaluation filters the full entry list (hex cells included) up to four times and, on a shared map, deep-compares the working copy with the saved map.
- Why: On a 20k-cell map this runs on every observed change of the working copy (each pencil room, needle commit, pin move), repeated filter allocations of the entire array.
- Action: Derive `editEntries` once in the session (non-hex ids in order) and invalidate on entry-structure change; compute `sharedMapHasChanges` from the undo history's dirty flag or compare only when the refresh button is visible.
- Severity: Low
- Status: NEW

### Undo history stores full map copies including the hex grid
- Category: Performance
- Location: Modules/MapRPG/Map/MapEditorPinHistory.swift:8-19 (`MapEditorSnapshot.init` copies the map), :48-56 (`record` compares snapshots then copies again), `maximumUndoDepth = 100`
- What: Each recorded step is a full `map.copy()` (two copies per `record`), and `snapshot != current` compares the complete map.
- Why: On a 20k-cell hex map every room toggle changes the entries array (copy-on-write of about 20k structs), so up to 100 retained snapshots can hold tens to hundreds of MB (estimate, not measured), and each mutation pays a full `==`.
- Action: Exclude the regenerable hex grid from snapshots (store only its scale and revealed ids), or lower the depth when the entry count is large; avoid the second `copy()` in `record`.
- Severity: Low
- Status: NEW (partly related to CODE_AUDIT_23 §7.3, which only added the depth limit)

### Needle insert after the last point lands next to the first point
- Category: Bug
- Location: Modules/MapRPG/Map/MapEntryViewer.swift:150-175 (`insertNeedle`, lines 157-165)
- What: When the selected point is the last vertex, the new point is placed at `coordinates[0] + (50, 50)` and inserted at index 0, instead of at the midpoint of the closing edge (last to first).
- Why: "Add Point" on the last vertex creates a spike near the first vertex (and shifts all indexes), while every other vertex inserts a midpoint. A user adding a point to the closing edge gets a shape change they did not ask for; with a tiny first-to-neighbour distance the new point can also land outside the room.
- Action: For the wrap case use the midpoint of last and first and append at the end (index `count`), keeping the other indices unchanged; add a test.
- Severity: Low
- Status: NEW

### Pencil stroke samples with the committed transform while the display uses the live gesture transform
- Category: Bug
- Location: Modules/MapRPG/Map/MapEditorSession+Pencil.swift:34-47 (`extendPencilStroke` uses `viewport.transform`/`contentPoint`), Modules/MapRPG/Map/MapPencilStrokeOverlay.swift:11-20 (draws with `displayedTransform`), Modules/MapRPG/Map/MapEditorCanvasGestures.swift:131-141
- What: Fingers keep panning and pinching while the pencil draws; that interaction lives in the `@GestureState` transform and is only committed on gesture end, but pencil points are converted with the committed transform.
- Why: If a finger pans or zooms during a stroke, the stored content-space points do not match what is on screen; the polygon applied at pen lift is displaced from the stroke the user saw.
- Action: Convert with the live displayed transform (pass it into the gesture handler, or publish it on the session), or ignore finger viewport gestures while a pencil stroke is active.
- Severity: Low
- Status: NEW (not device-verified; see memory note map-editor-pencil-room-drawing)

### Cancelled pencil or pin drags leave state behind
- Category: Bug
- Location: Modules/MapRPG/Map/MapEditorCanvasGestures.swift:211-234 (`drawGesture` has no cancel path; the stroke is cleared only in `onEnded` or the next `beginPencilStroke`); Modules/MapRPG/View/MapPinActionView.swift:94,137-145 (`isMoving` set in `onChanged`, cleared only in `onEnded`)
- What: `onEnded` is not called when the system cancels a gesture (palm rejection, alert, scene change). The pencil overlay keeps the half stroke visible, and `isMoving` stays `true`, so the next pin drag skips `model.beginMove()` (the action menu does not collapse).
- Why: Minor visual and UX stale state.
- Action: Reset via `@GestureState`/`.updating` reset callback (`state` resets automatically) or observe `scenePhase`/gesture-cancel; derive "is moving" from a `@GestureState` Bool instead of `@State`.
- Severity: Low
- Status: NEW

### Hard-coded slider ranges and icon sizes duplicate `MapEditorScaleRanges` / ignore Dynamic Type
- Category: Duplication
- Location: Modules/MapRPG/Map/GameToolBar.swift:252 (`0.5 ... 3.5`), :302 (`20 ... 200`) vs MapEditorScaleRanges.swift:11-13; fixed `.frame(width: 24, height: 24)` icons at EditMapToolBar.swift:84,86, HexMapScaleView.swift:45, ChooseMapPinsButton.swift:35 (the other game-toolbar buttons use `@ScaledMetric iconSize`)
- What: The shared ranges file says it is the single place to tune, but the game toolbar repeats the literals; four icon frames do not scale with Dynamic Type.
- Why: Ranges can drift between editor and game toolbar; CLAUDE.md asks for Dynamic Type.
- Action: Use `MapEditorScaleRanges.pinScale/hexScale` in `GameToolBar`; use `@ScaledMetric` for the icon frames.
- Severity: Low
- Status: NEW

### No scroll-wheel or keyboard zoom for the map on macOS
- Category: SwiftUI
- Location: Modules/MapRPG/Map/MapEditorCanvasGestures.swift:100-148 (only `MagnifyGesture` + `DragGesture` + double tap), MapEditorCanvas.swift (no `onScrollWheel`/key handling)
- What: Pan/zoom is gesture-only; a macOS user with a mouse (no trackpad) can only drag and double click.
- Why: Mouse users on macOS cannot zoom stepwise; unverified whether a command in `Menu/` supplies it.
- Action: Confirm menu/keyboard zoom commands exist for macOS; if not add `onScrollGesture`/`⌘+`/`⌘-` through `ViewportModel`.
- Severity: Low
- Status: NEW (unverified)

### Test gaps
- Category: Test gap
- Location: Tests/MapRPGTests (no test covers `MapEntryViewerModel.insertNeedle` wrap case, `MapEditorSession.entry(for:in:)` with a hex grid, `synchronizeRooms`/`resetEntries` at scale, or the hit layer)
- What: The risky logic above has no direct tests (needle insert only appears in MapEditControllerTileTests and MapEditorUndoTests for the non-wrap case).
- Why: Both bugs above would have been caught by one hex-plus-room fixture.
- Action: Add tests for hex+room lookup, wrap insert midpoint, and a timing guard for `resetEntries` with a few thousand cells.
- Severity: Low
- Status: NEW

Checked and found fine (no finding): hex-grid row/column math and clamping (`MapHexGridGeometry`), `carryingRevealedArea` raster bounds, fog tile planner overflow guards, pencil RDP (iterative, closed-loop split), popover and loupe placement math, viewport gesture composition (two interaction planes share one `GestureState`, content plane maps its anchor through `viewportAnchor`), the `exclusively(before:)` room double-tap/long-press combos, `MapEditorHistory` trimming, auto-commit/discard flow, player data redaction in `MapSnapshot.redactedForNonMaster` (pins in unrevealed rooms and hidden room text are stripped before sending, so pins hidden under the fog canvas are not reachable by players).

Not audited in this area: `Modules/MapRPG/Model`, `Controller`, `View` (only the pin action view and the parts of `EditController` that the Map folder calls), `BattleRound`, `Intent`; the 3D table consumers of `GameToolBarSession`; `ViewportModel`/`ViewportGeometry` internals in CoreRPG; runtime behaviour on device (no builds or profiling were run).
