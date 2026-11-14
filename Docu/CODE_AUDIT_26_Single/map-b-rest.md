Area: Modules/MapRPG excluding Map/ (88 Swift files, about 11.5k LOC). Read in full: Model (MapSnapshot, MapWallModel, MapPinModel, MapEntryModel, MapUpdatePayload, MapModel and its four extensions, MapPhotoPopoverModel, MapPinPhotoSharing, DataModel+Extensions), every Controller (GameController and its +Pins, +Metadata, +Battle, +BattleSync, +Sync, +TemporaryMap, +Demo; ExportController, EditController, DataController, ViewController, LinkController, SheetController, CacheController, ItemController), all of BattleRound/ (model, turns, roster, rolls, network, settings, card presentation), Root/, Route/, Intent/, Extensions/ and the views that matter (pin action menu and view, popover, photo popover, display-config editors, row views). Overall health: very good. The compiler-clean rules in CLAUDE.md hold across the area (no onTapGesture, GeometryReader, foregroundColor, DispatchQueue, print, try!, force casts, unchecked Sendable). Player-facing redaction is consistent: one rule (`MapPinModel.isVisibleToPlayers(hiddenBy:)`) drives the live content update, the player package, `.mapState`, `missingMapImages`, the full-screen pin photo and the battle-round active pin; hidden pins are left out, hidden rooms lose name and text, walls lose secret doors and raw metadata, and `healthPercent` and session pins stay out of persistence. The findings below are therefore mostly one remaining redaction field, one wrong-destination bug, performance and dead code. Old audits (CODE_AUDIT_Map, BattleRound 1-3, 22/22a/23/24/25) were consulted; nothing marked Fixed/By design is repeated.

### Map description and tags still ship to players unredacted
- Category: Security
- Location: Modules/MapRPG/Model/MapSnapshot.swift:154-190 (`redactedForNonMaster()` copies `description:` and `tags:` through unchanged, lines 168-170); Modules/MapRPG/Controller/ExportController.swift:56-60 (`playerExportData` applies the same snapshot); Modules/MapRPG/Model/MapUpdatePayload.swift:34-44
- What: CODE_AUDIT_25 §6.1 was fixed for walls only. The map-level `description` (the item's notes field) and `tags` are copied into every live content update and into every player package.
- Why: A game master who keeps spoilers or hints about secret rooms in the map description sends them to every player device. Whether a player UI renders the description is unverified, but the text is on the device and in the payload. `MapSnapshot`'s own doc comment says the point of the function is that GM-only data must not be present on a recipient's device. No test pins this (`MapWallRedactionTests`, `MapPinVisibilityTests` cover walls, pins and rooms only).
- Action: Blank `description` (and decide for `tags`) in `redactedForNonMaster()`, keep `name`, add a test next to `MapWallRedactionTests`. Follow the "excluded until explicitly allowed" recommendation of CODE_AUDIT_25 §10.5 so new `MapSnapshot` fields default to redacted.
- Severity: Medium
- Status: NEW

### "Edit Tile" toolbar button opens the full map editor, and on macOS/visionOS does not select the map
- Category: Bug
- Location: Modules/MapRPG/View/EditTileButton.swift:12-25; compare Modules/MapRPG/View/MapEditorButton.swift:13-19 and Modules/MapRPG/View/DisplayConfigEditor.swift:188-194
- What: `EditTileButton` navigates to `MapEditorRoute.mapEditor(model.id)` (iOS/tvOS) and opens `.mapEditor` (macOS/visionOS), where the label and `DisplayConfigEditor` use `MapEditorRoute.mapTileEditor` and `.mapTileEditor`. On macOS/visionOS it also never sets `editController.editorModel.sheetEditorModel.itemId = model.id`, which `MapEditorButton` and `DisplayConfigEditor` both do before opening the window.
- Why: The button next to "Map Editor" in the detail toolbar is a second copy of the map editor button. On macOS and visionOS the window's `MapEditWindow` reads `sheetEditorModel.itemId`, so it shows whatever item was set last (or "No map item is selected"), which can be a different map than the one the user clicked.
- Action: Route to `mapTileEditor` / `.mapTileEditor` and set the item id exactly as `DisplayConfigEditor.TileCoordinatesView` does; better, make both call one shared helper.
- Severity: Medium
- Status: NEW

### Full map fingerprint (redact, JSON-encode, SHA-256) is rebuilt up to four times per content update and on every generation lookup without an authoritative record
- Category: Performance
- Location: Modules/MapRPG/Model/MapUpdatePayload.swift:34-44; Modules/MapRPG/Controller/GameController+Metadata.swift:42-53, 91-130, 134-146, 153-160; Modules/MapRPG/Controller/GameController.swift:317-319, 339-341, 405-412 (`networkMapContentUpdate`); Modules/CoreRPG/Model/StableVersionDigest.swift:17-26
- What: `MapUpdatePayload.init(model:)` always builds a snapshot, a fully redacted copy, then a canonical encoding and digest of the whole map. `mapContentVersion`, `packageCoreMetadata` (called twice per `stablePackageMetadata` attempt), `currentMapReference`, `currentMapContentUpdate` and `mapContentCapture` each construct it just to read `contentVersion`. One `networkMapContentUpdate` therefore does at least four builds (capture, two in `stablePackageMetadata`, one `packageCoreMetadata`), more on a retry. `networkGeneration(for:)` does one more per call when `authoritativeGenerations[itemId]` is missing (it is set to nil by `recordAuthoritativeGeneration` for any `.map` data without both versions), and is called for every mapState, pin and battle message.
- Why: All of it runs on the main actor. A hex-grid map carries hundreds to thousands of cells with six points each; every game-master edit, "Refresh Shared Map", and each player pin or battle message in the no-record case pays several full JSON encodes plus SHA-256 on the main thread. Unmeasured, but the work is structurally redundant (the redaction output is thrown away whenever only the version is needed).
- Action: Split a `static func contentVersion(of model:)` (no redaction, no payload) from the payload builder; compute it once per content update and pass it through `stablePackageMetadata` / the retry loop; cache it per model change token for `networkGeneration`.
- Severity: Medium
- Status: NEW

### Cover-tile preview ignores the photo rotation and races on map switch
- Category: Bug
- Location: Modules/MapRPG/View/DisplayConfigEditor.swift:79-92 (`loadTileImage`)
- What: `let (fullImage, _) = ... fetchPhotoImage(...)` discards the rotation, then crops `tileCoordinates.bounds` out of the unrotated bitmap. Tile coordinates are canvas coordinates (EditController.rescaleCoordinates comment "the cover tile is a piece of the map image"; `CacheController.createThumbnail` rotates the source by `degrees` for the same reason). The load runs in an untracked `Task { }`, so a slow result for map A can assign `tileImage` after the editor switched to map B (`onChange(of: model.id)` reloads, but nothing cancels the older task). It decodes the full-size photo for a 120x80 preview and fetches with `useGame: true` in the library editor.
- Why: On a rotated map the thumbnail shows another area than the tile; after a fast switch it can show the wrong map's tile.
- Action: Use `.task(id:)` (auto-cancel), rotate through the same helper as `CacheController` (or use the thumbnail source, `useGame: false`), and downsample.
- Severity: Medium
- Status: NEW (rotation part unverified at runtime; read from code)

### Room thumbnails rotate and crop on the main actor, once per room
- Category: Performance
- Location: Modules/MapRPG/Controller/CacheController.swift:35-48; Modules/MapRPG/Extensions/UIImage+Crop.swift:7-28, 45-52
- What: `createThumbnail` is `@MainActor` (protocol requirement). For each room it fetches the photo thumbnail source (up to 1024 px), then `rotated(byDegrees:)` redraws the whole bitmap into a new CGContext before the crop, even for a 3x3 px room. A map with 40 visible rooms rotated by a non-zero angle does 40 full-bitmap redraws on the main actor.
- Why: Scrolling a room list of a rotated map stalls the main thread; maps with `degrees == 0` skip the redraw.
- Action: Crop first in canvas space using an inverse-rotated rect, or cache the rotated canvas image per map/photo version; run the CPU part `@concurrent`.
- Severity: Medium
- Status: NEW (not measured)

### Unreferenced code with a latent bug: `EditController.replace(itemId:with:)`
- Category: Dead code
- Location: Modules/MapRPG/Controller/EditController.swift:521-533
- What: No caller exists in Modules, Sources or Tests. If called it mutates the library instance from `itemSync` in place (no `save`, no copy) and pairs `model.entries` with the argument by position, although the editors pass rooms without hex cells.
- Why: Dead, and wrong if revived.
- Action: Delete.
- Severity: Low
- Status: NEW

### Other unreferenced members
- Category: Dead code
- Location: Modules/MapRPG/Extensions/CGPoint+Relative.swift:1-9 (`CGPoint.relative(to:)`, only its definition matches `relative(to`); Modules/MapRPG/Model/MapPinModel.swift:35-52 (`MapPinSize.text`, hard-coded English, never localized or read); Modules/MapRPG/Model/MapEntryModel.swift:18-27 (`MapDisplayMode.text`, same); Modules/MapRPG/View/DisplayConfigEditor.swift:8-9 (`navigator` and `scenesManager` environment values declared in `DisplayConfigEditor` itself, used only by the child view)
- What: Four members with no references across Modules/Sources/Tests (grep for `size.text`, `mode.text`, `relative(to`).
- Why: Dead surface; the two `text` properties would also ship untranslated strings if used.
- Action: Delete the file and the three members.
- Severity: Low
- Status: NEW

### Preview and mock fixtures compiled into Release
- Category: Dead code
- Location: Modules/MapRPG/BattleRound/BattleRoundPreviewData.swift (178 LOC, public, no `#if DEBUG`; used only by GameRPG previews and one test); Modules/MapRPG/Model/MockData.swift (imports SwiftData; used only by `#Preview`); Modules/MapRPG/Model/PreviewData.swift:12-35 (`MapRootModel.preview`, `previewFixture`, `MapModel.previewFixtures`, about 250 LOC outside the two `#if DEBUG` blocks)
- What: About 600 lines of fixtures and a SwiftData import ship in release builds; CLAUDE.md says the module `Preview` folder is `#if DEBUG`.
- Why: Binary size and public API surface; `BattleRoundPreviewData` is `public`.
- Action: Wrap in `#if DEBUG` (or move to a `Preview/` folder) and keep the two GameRPG preview callers and the test under DEBUG; check that GameRPG's `#Preview` blocks still resolve.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_25 §9.11] (fixtures compiled into Release)

### `MapModel.version` is a sum of two scalars
- Category: Bug
- Location: Modules/MapRPG/Model/MapModel+Sync.swift:185-191
- What: `version` is the bit pattern of `hexMapScale + pinScale`, so it does not change on any edit of rooms, pins, walls or photo, and two different pairs with the same sum (hex 2 + pin 1, hex 1 + pin 2) are equal. Real freshness lives in `assetVersion` / `contentVersion`.
- Why: Code that still compares only `NetworkCodableDataType.version` for a map (generic `hasItem(id:version:)` style checks, `createMapGameData`'s `base.version == after.version` guard, `isCurrentGeneration`) gets almost no protection from it. Today the extra fingerprints cover the Map paths, so this is a trap for new callers rather than a live defect.
- Action: Document the weakness at the property (the comment only explains why `hashValue` was dropped) or fold `contentVersion` into it once the digest is cheap (see the performance finding).
- Severity: Low
- Status: NEW

### Adding N monsters saves N times
- Category: Performance
- Location: Modules/MapRPG/Controller/EditController.swift:366-372 (`add(pin:at:to:)` saves per pin), 387-394 (`addMonsters` loops `add(pin:)`), 99-103 (`.value` link path saves once more)
- What: Each spawned pin calls `save(updated:message:)` separately: one undo entry, one library write and one CloudKit change per pin; "Add 20 goblins" does 20, and the `.value` link path adds a 21st.
- Why: Slow on large spawns, 20 undo steps for one user action.
- Action: Append all pins to the model first and save once with a count in the message.
- Severity: Low
- Status: NEW

### Redaction stamps blanked room text as the newest CRDT write
- Category: Bug
- Location: Modules/MapRPG/Model/MapSnapshot.swift:158-165 (`redacted.name = ""`, `redacted.content = ""` go through the `@CRDT` setters, which stamp now); Modules/MapRPG/Controller/ExportController.swift:56-60
- What: The blank value gets a fresh last-writer-wins timestamp, so it beats the real (older) text in any merge-mode import on a device that holds a copy of the map.
- Why: Safe today because the live receive path replaces (`apply(to:)`) and the map package imports with `ImportMode.overwrite`; any future merge-mode path (or a player who keeps the map in the library via `persistFromGame(authoritative: false)`) would keep rooms blank after a reveal.
- Action: Note the invariant at `redactedForNonMaster()` and test that a reveal after a blank package restores the text on the receive paths; or build the redacted entries without touching the CRDT stamp.
- Severity: Low
- Status: NEW

### Fire-and-forget tasks without owner
- Category: Concurrency
- Location: Modules/MapRPG/Controller/LinkController.swift:35-37 (share task), 88-90 (`resetImageSize(save: true)` for every map on Validate Links); Modules/MapRPG/Controller/EditController.swift:288-294 (documented cache invalidation); Modules/MapRPG/Root/MapRootModel.swift:25-32 (`enqueueMapContentSend` chain)
- What: Untracked `Task { }` blocks. The Validate Links one runs per map, is never cancelled, and its `itemController.replace(...)` goes to game memory only when it fires during a running game. `enqueueMapContentSend` awaits the previous send forever, so one hung `work` blocks every later content update for the session.
- Why: Cancel/teardown cannot stop them; a hang in one content send silently stops all later map updates.
- Action: Give the send chain a bounded wait or cancel it at game end; collect the validate tasks in the repair run so the run can await or cancel them.
- Severity: Low
- Status: NEW

### Low-contrast white symbols on tinted pin-menu buttons
- Category: SwiftUI
- Location: Modules/MapRPG/View/MapPopover.swift:366-372 (`.foregroundStyle(.white)` on `tint.opacity(0.7)` for `.mint`, `.teal`, `.gray`, `.orange`)
- What: Fixed white symbols over 70 percent tints of light colors, regardless of appearance or Increase Contrast.
- Why: Hard to read for the mint/orange actions; no accessibility adaptation.
- Action: Use a darker tint or a contrast-aware foreground, honor `colorSchemeContrast`.
- Severity: Low
- Status: NEW

### Test gaps
- Category: Test gap
- Location: Tests/MapRPGTests (no file for these)
- What: No test for redaction of map `description`/`tags`, for `networkBattleRoundUpdate` hiding the active pin when it is hidden (`GameController+BattleSync.swift:178-190`), or for `EditTileButton` routing.
- Why: These are the privacy-relevant branches that were added by audits 22a/23 without a pin on the exact behavior.
- Action: Add the three tests alongside `MapPinVisibilityTests` / `MapWallRedactionTests`.
- Severity: Low
- Status: NEW

Verified and left out (checked, no finding): `updatePin` authorization and coordinate/timestamp validation; `pinsVisibleToPlayers` and `pointerVisibleToPlayers`; `missingMapImages` visibility filter; `exporting(itemIds:)` for players (task-local `ExportAudience`, fail-open default only reachable from two entry points that both set it); `MapSnapshot.apply` runtime-state merge; `BattleRoundNetworkState` (no combatants or initiative leave the master; hidden active pin is nil-ed); battle turn state machine (`advanceTurn`, `removeCombatant`, `nextRound`) for dead combatants and empty rosters; `saveAll()` stripping live game pins (only reached from Save and Quit); persistence mapping (`healthPercent` never stored, `unequalSet` guards).

Not audited in this area: the Map/ folder (separate audit); view-layout details of `MapPinView` and canvas gestures; GameRPG-side callers of the MapGameStorable protocol beyond the grep checks above; runtime behavior (nothing was built or run); String-catalog completeness of the area's localization keys.
