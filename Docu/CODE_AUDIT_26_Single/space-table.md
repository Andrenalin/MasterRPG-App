# Audit 26: SpaceRPG + TableRPG

Combined ~14.4k LOC (TableRPG 5,983, SpaceRPG 8,459). TableRPG was read in full for Controller/, Model/ (TableModel, entries, generation model, session store), Root/TableRootModel, Intent/Roll+Management, and the generation views. TableRPG is in good shape: nearly all CODE_AUDIT_Table findings (range check, shared `TableRollRange`, table-link recursion in `collectLinks`, receive serializer, Set lookups in `SheetController`) are fixed in the current code; zero force unwraps/GCD/ObservableObject. Remaining issues are in the multiplayer dice-result path and the outcome-editor state machine.

### Player dice result is applied to the generation tree without checking the pending-roll state
- Category: Bug
- Location: Modules/TableRPG/Model/TableGenerationSessionStore.swift:23-49; caller Modules/GameRPG/Controller/MasterController+DiceMessages.swift:58-66; pending state set at Modules/TableRPG/View/TableGenerationOccurrenceHeaderView.swift:172-176
- What: `consume(category:diceResult:)` applies any incoming result for a registered session/occurrence via `controller.apply`, never checking `occurrence.isAwaitingPlayerRoll` or `awaitingPlayerId` (which the header sets exactly for this purpose).
- Why: With "Share to all", every player's roll re-applies and re-selects the entry (last roll wins); a player who re-rolls, or whose roll arrives after the GM rolled locally/reset/cancelled, silently changes the GM's already decided table result and rebuilds the child tree (discarding nested choices).
- Action: Accept a result only while the occurrence is awaiting a roll and (if `awaitingPlayerId != nil`) the sender matches; otherwise treat it as a plain dice-log entry (return false). This needs the sender id passed through `addResult`.
- Severity: Medium
- Status: NEW

### "Edit as Sheet" transition beat can leave the panel in an inconsistent state
- Category: Bug
- Location: Modules/TableRPG/View/TableGenerationEditAsSheetButton.swift:55-62; Modules/TableRPG/View/TableGenerationPanelView.swift:34-40,45-50; Modules/TableRPG/View/TableGenerationRootView.swift:99-101
- What: `toggle()` creates the session synchronously, then an uncancelled `Task` sets `model.isEditingOutcomeSheet = true` after 0.5 s without re-checking the session still exists or the view is still alive.
- Why: During the beat the occurrence list is still interactive. A selection/hide/reset (all call `discardOutcomeSession`, which clears the session and flag) followed by the delayed `isEditingOutcomeSheet = true` yields editing flag true with `outcomeEditingSession == nil`: the panel shows the occurrence list, yet the footer shows the Save/Share button (it keys off the flag only) and `save()` silently returns on its `guard let session`.
- Action: In the Task re-check `model.outcomeEditingSession != nil` (and cancellation) before setting the flag, or disable the list during the beat; derive the footer's visibility from "flag and session" together.
- Severity: Low
- Status: NEW

### Save/Send of the outcome fail silently and Save can discard the outcome
- Category: Bug
- Location: Modules/TableRPG/View/TableGenerationRootView.swift:112-128 (`save`, nil branch calls `closeSession()`), 145-164 (`send`, early `return` in the guard)
- What: If `addOutcomeToCharacter` returns nil (root manager missing, Character conformer created nothing) the panel just closes, losing the edited outcome with no message; if the `SheetItemTransfer` cannot be built/encoded in `send`, nothing happens at all.
- Why: The GM believes the result was saved/sent; the edited text is gone after closing.
- Action: Keep the panel open and set `model.errorMessage` on both failures (the error label already exists in the occurrence list).
- Severity: Low
- Status: NEW

### Preview/mock fixtures compiled into Release
- Category: Dead code
- Location: Modules/TableRPG/Model/PreviewData.swift:1-342 (only `testRoot` is in `#if DEBUG`), Modules/TableRPG/Model/MockData.swift, Modules/TableRPG/Model/TableGenerationPreviewData.swift
- What: ~500 LOC of sample tables and preview roots are not DEBUG-gated (MockData also imports SwiftData).
- Why: Binary size and the CLAUDE.md convention (`Preview` folder, `#if DEBUG`); `RolePlayGameKit` does not reference them.
- Action: Wrap in `#if DEBUG` and move to a `Preview/` folder. Check tests use `testRoot` only.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_Table §7.3]

### `GameController.entry(for:with:)` has no production caller
- Category: Dead code
- Location: Modules/TableRPG/Controller/GameController.swift:136-160; only Tests/TableRPGTests/GameControllerTests.swift:41-46 call it
- What: A second roll-resolution implementation kept only for tests (acknowledged in its comment), duplicating `TableGenerationController.matchingEntry`.
- Why: Two implementations can drift again (they already did once); the protocol comment in CoreRPG/Text/TableRollRange.swift:8 refers to it.
- Action: Delete it and point the test at `matchingEntry`, or make `matchingEntry` the single shared function.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_Table §5.8]

### Generation tree flattened repeatedly inside view bodies
- Category: Performance
- Location: Modules/TableRPG/Model/TableGenerationModel.swift:158-188 (`occurrences`, `canConfirm`, `isFullyDecided`, `currentOutcome`, `summary`, `currentSelections`), used from Modules/TableRPG/View/TableGenerationPanelView.swift:17-24; `selectedEntries` filter at TableGenerationModel.swift:104
- What: Each computed property re-flattens the whole tree and `selectedEntries` does an O(entries) filter; the panel body evaluates several of them per update (plus `occurrence.children.filter` per entry row).
- Why: Bounded by `maxOccurrenceCount = 500`, so only noticeable for big nested tables (hundreds of entries each); every selection change re-evaluates all of it.
- Action: Cache the flattened list/`selectedEntries` (invalidate in `rebuildChildren`/`select`) if profiling shows cost. Low priority.
- Severity: Low
- Status: NEW


SpaceRPG (8,459 LOC) was read for SpaceViewer.swift (all 1,212 lines), GameController/SpaceGameModel, SpaceHandoffModel, SpaceModel, SpaceRootModel, Data/Export/Link controllers, the scanner state machine (AppDataModel, CaptureFolderManager, Reconstruction*, Scanner3DRootView, CapturePrimaryView, CaptureOverlayView, ModelView, TimedMessageList), InlineImporterView, SpaceQuickLook, ViewerRootView and the first half of the intents. SpaceRPG is also in good shape: the previous audit's High items (reconstruction failure screen, swallowed `process` error, `@State` preopen seed, raw photos in Documents, `applyIf` duplicate) are fixed and the scan flow handles cancel/finish/orphaned sessions carefully. What remains is mostly platform gaps (tvOS), visionOS view-lifetime concerns, and the oversized viewer.

### 3D objects are still not shown on tvOS and the game-mode affordance is an invisible no-op
- Category: Bug
- Location: Modules/SpaceRPG/Controller/ViewController.swift:42-50 (tvOS `gameViewer`), Modules/SpaceRPG/View/SpaceQuickLook.swift:21-57 (`loader()` empty outside visionOS; `selected` never assigned, so `.quickLookPreview($selected)` can never present), Modules/SpaceRPG/Root/ViewerRootView.swift:14-18 (empty `VStack` on tvOS), Modules/SpaceRPG/Space/SpaceViewer.swift:7 (whole type `#if !os(tvOS)`)
- What: On Apple TV a revealed Space renders a 0.01-opacity, non-hit-testable button and nothing else; `SpaceQuickLook.selected`/`quickLookPreview` is dead state on every platform (the view is only instantiated for tvOS/visionOS).
- Why: A GM revealing a 3D object to a tvOS player shows a blank game screen with no explanation.
- Action: Decide the tvOS behaviour: either show an explicit "3D objects are not shown on Apple TV" state (and hide the affordance in `ViewerRootView`), or render the model preview via QuickLook/thumbnail. Remove the dead `selected` state.
- Severity: Medium
- Status: [OPEN since CODE_AUDIT_Space §8.2]

### visionOS manipulation subscriptions are stored in the view's own @State and capture the view value
- Category: Concurrency
- Location: Modules/SpaceRPG/Space/SpaceViewer.swift:58-59,640-680 (`manipulationBeganSubscription`/`manipulationEndedSubscription` closures use `self.isManipulating`, `self.handleManipulationEnded`, `self.tablePlacement`), 846-860 (`closeButtonAttachSubscription` closure uses `self`)
- What: The `EventSubscription` handles are kept in `@State` of `SpaceViewer`, while their closures capture `self` (the view struct, which holds the same `@State` storage box).
- Why: This is exactly the cycle CLAUDE.md warns about for the Table3D model (storage holds subscription, closure holds view copy, view copy holds the storage and with it `objectEntity`/`rootEntity`, i.e. the full USDZ entity). If RealityKit does not drop the handler when the scene is torn down, each open of the viewer on visionOS leaks the entity graph. The close-button subscription breaks its own cycle on the first update tick, the two manipulation ones never do. Not verified at runtime.
- Action: Move the gesture/placement state and the handlers into a small `@MainActor` reference type owned by `@State` (capture it weakly), or cancel and nil the subscriptions in `onDisappear`. Check with the memory graph that the entity deinits after closing the viewer.
- Severity: Medium
- Status: NEW

### SpaceViewer.swift is 1,212 lines with a 245-line `loadEntity`
- Category: Refactor
- Location: Modules/SpaceRPG/Space/SpaceViewer.swift:16-1212 (`loadEntity` L549-~795)
- What: One file holds the shared-immersive sync engine (L207-434), window-to-immersive handoff (L435-546), entity loading plus gesture wiring (L549-~795), close-button attachment, and five private subviews.
- Why: Hard to reason about the platform `#if` matrix (visionOS window, visionOS immersive, iOS, macOS); the file's biggest function mixes parsing, interaction components, normalization and placement.
- Action: Split into `SpaceViewer+SharedPlacement.swift` (visionOS), `SpaceViewer+Handoff.swift` (visionOS), `SpaceViewer+Loading.swift` (extract `configureInteraction`, `normalizeScale`, `place` helpers out of `loadEntity`), and `SpaceViewerSubviews.swift`. Keep the stored properties in the main file.
- Severity: Medium
- Status: [OPEN since CODE_AUDIT_25 §9.12]

### Window instance stays on "Moved to Immersive Space" after the handoff fails or the space closes
- Category: Bug
- Location: Modules/SpaceRPG/Space/SpaceViewer.swift:465-485 (`moveToImmersiveSpace` sets `handedOffToImmersive = true`, nils `objectEntity`/`rootEntity`, ignores the result of `openSpaceViewer`)
- What: The one-way flag is never reset; if the immersive space fails to open, is dismissed, or the entity expires (30 s in `SpaceHandoffModel`), the embedded viewer keeps showing the placeholder.
- Why: The user must navigate away and back to see the preview again; the entity was already detached so it cannot recover on its own. Not verified on a device.
- Action: Reset `handedOffToImmersive` (and reload) when the immersive space closes or `openSpaceViewer` reports failure; the handoff model could publish the expiry.
- Severity: Low
- Status: NEW

### Accessibility "Rotate/Tilt" actions do nothing on iOS and macOS
- Category: SwiftUI
- Location: Modules/SpaceRPG/Space/SpaceViewer.swift:881-900 (`rotate` applies the rotation only under `#if os(visionOS)`), 978-1070 (`SpaceViewerContentView` actions from L1031 and "Yaw/pitch" accessibility value)
- What: On iOS/macOS the orbit camera drives the view; `rotate(yawDelta:pitchDelta:)` only changes `yaw`/`pitch` state and the spoken value, never the entity or camera.
- Why: VoiceOver / Switch Control users hear a changing yaw value but the object does not move; the advertised actions are misleading.
- Action: Apply the same rotation to the entity on the other platforms (the entity is already normalized and centered), or drop the rotate actions and the yaw/pitch value there.
- Severity: Low
- Status: NEW

### Stale-scan cleanup runs synchronously on the main actor when the scanner model is first created
- Category: Performance
- Location: Modules/SpaceRPG/Record/AppDataModel.swift:98-101 (`init` calls `CaptureFolderManager.cleanupStaleScans()`), Modules/SpaceRPG/Record/CaptureFolderManager.swift:197-215
- What: `contentsOfDirectory` and `removeItem` of left-over capture folders (hundreds of HEIC photos plus snapshots) run on the main thread while the scanner screen is opening (`AppDataModel.instance` is first touched from `Scanner3DRootView`).
- Why: After a crash or force quit with a large capture the first scanner open hitches for the duration of the deletion.
- Action: Run the cleanup in a `@concurrent` background task (like `reset()` already does for the live folder).
- Severity: Low
- Status: NEW

### Scan folders are named by the current second
- Category: Bug
- Location: Modules/SpaceRPG/Record/CaptureFolderManager.swift:119 (`Date().formatted(.iso8601)`), 38-52 (init fails if `Images/` exists)
- What: Two captures started within the same second resolve to the same directory; `createDirectoryRecursively(imagesFolder)` then fails ("already exists") and `CaptureFolderManager.init` returns nil, so the session does not start; a background removal of the previous scan with that name could also delete the new folder.
- Why: Cancel and immediately re-open (the model waits only 500 ms in `scheduleStartNewCapture`) can hit this; rare but silent.
- Action: Append a UUID (or a counter) to the folder name.
- Severity: Low
- Status: NEW

### UIKit leftovers in the scanner
- Category: API
- Location: Modules/SpaceRPG/Record/ShotFileInfo.swift:12 (`import UIKit`, unused), Modules/SpaceRPG/Record/CaptureOverlayView.swift:25,122-127 (`UIDevice.current.orientation`; `beginGeneratingDeviceOrientationNotifications()` is never called anywhere in the repo)
- What: The unused import violates the "avoid UIKit" rule; the orientation tracking relies on UIKit having device-orientation generation enabled elsewhere, otherwise `orientation` stays `.unknown` and the counter/feedback never rotate in landscape.
- Why: Rotated capture HUD elements may be wrong in landscape; unverified (UIKit usually turns generation on for rotating hosts).
- Action: Remove the import; either call begin/end generating around the capture view or derive the rotation from the scene geometry.
- Severity: Low
- Status: NEW

### Raw `String(describing: error)` shown in the reconstruction/scanner alerts
- Category: SwiftUI
- Location: Modules/SpaceRPG/Record/ReconstructionProgressView.swift:74-78, Modules/SpaceRPG/Record/Scanner3DRootView.swift:94-98
- What: Alerts titled "Failed: ..." interpolate the Swift enum dump of the underlying `ObjectCaptureSession.Error` / `PhotogrammetrySession.Error`.
- Why: Not localizable or readable for users (e.g. `cancelled`, `insufficientStorage`).
- Action: Map the known cases to localized messages and fall back to `localizedDescription`.
- Severity: Low
- Status: NEW

### No tests for the SpaceViewer-adjacent state machine and scanner reset logic
- Category: Test gap
- Location: Tests/SpaceRPGTests (no coverage of `AppDataModel.performStateTransition`/`reset`/`finishCapture(attached:)`, `CaptureFolderManager.cleanupStaleScans`); Tests/TableRPGTests/TableGenerationControllerTests.swift:597 (only the happy path of `consume`, no stale/second-player/awaiting cases)
- What: The scanner state machine is iOS-device only (`#if os(iOS) && !targetEnvironment(simulator)`) so it cannot run in the simulator tests, and the multiplayer dice consume rules above are untested.
- Why: The most intricate recent fixes (keep-model-on-failure, skip-auto-restart) have no regression tests.
- Action: Extract the pure folder-cleanup decision (`hasModelFiles`, keep Models) and the finish/cancel transitions into types testable on the simulator; add `consume` tests when the awaiting check is added.
- Severity: Low
- Status: NEW

Not audited in this area: SpaceRPG Resources (Core Data model, localization catalogs, tutorial videos), Menu/Route files, the onboarding/tutorial/help views in Record/ (OnboardingStateMachine, OnboardingTutorialView, HelpPageView, TutorialVideoView, PlayerView beyond a skim), the second half of SpaceManagementIntents/SpaceEntity (covered by the AppIntents audits), TableRPG Resources, Menu/Route files, TableGenerationHeader/Layout/Result views, TableRPG intent files other than RollTableIntent, and the CoreRPG helpers they call (`TableRollRange`, `GenericEditController`, `FileVersionGameControllable`). No runtime verification was possible (read-only).
