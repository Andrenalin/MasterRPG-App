# Audit 26: CoreRPG UI part 1 (LGViews, LGViewModifiers, FileViews, Navigator, ScenesManager)

Scope: Modules/CoreRPG/{LGViews (41 files, 4.8k LOC), LGViewModifiers (6, 0.6k), FileViews (45, 4.6k), Navigator (27, 3.9k, a vendored copy of the Navigator library), ScenesManager (5, 0.7k)}, about 14.6k LOC. Read in full: all of ScenesManager, LGViewModifiers (all six), the large and risky LGViews (ListRootView, ListRootContextMenu, ListRowItemView, ItemRowsView, ItemRowView, ItemHeaderEditorView, ItemStateRestorationView, GameShareView, FileImporterView, EditorLinkView, GroupEditorView, CloudFolderScanView, AffectedLinkActionPanelView, PlayerReportRow, CachePhotoView, ThumbnailRowPhotoView and the small ones), FileViews (ImportProgressPanelView, ExportProgressPanelView, FileReplacementConfirmation, GameBundleBrowser*, SingleImportModels, ImporterFanView, ImportChooseUrlView, StorageOptionEditor), and Navigator core (Navigator, ManagedNavigationStack, ManagedPresentationView, NavigationSend, Operations, Presentation, Dismiss, SceneStorage, Action, EventLogging, URLHandler, LazyState). Grep sweeps over all five folders for every CLAUDE.md rule (onTapGesture, foregroundColor, cornerRadius, NavigationView, GeometryReader, ScrollViewReader, GCD, `Task.sleep(nanoseconds:)`, the ObservableObject family, legacy Formatters, `String(format:)`, hard-coded system font sizes, fontWeight, 1-parameter `onChange`, print, TODO/FIXME, `#if false`, `try!`, `as!`) were clean; AnyView occurs only inside the vendored Navigator. Overall health: very good. There are no Critical or High findings; what remains is state-model and cancellation edges, an inert tag-search feature, about 500 LOC of unused vendored Navigator code, and untested import-apply logic that lives inside a view.

### Scene state is one value per SceneId although viewer windows are multi-instance
- Category: Bug
- Location: Modules/CoreRPG/ScenesManager/ScenesManager.swift:145-170, 218-233; Modules/CoreRPG/ScenesManager/Modifiers/SceneTrackerModifier.swift:44-76; Sources/MasterRPG/Window/WindowViewerList.swift:70-85
- What: `openWindow(_:selection:)` deliberately opens an extra window when the scene is already `.opened`, but `SceneStateBox` holds one state per `SceneId`, and every window's tracker writes it (`.onDisappear` -> `.closed`, scenePhase `.background` -> `.closed`).
- Why: Open two Photo viewer windows (same `viewerId`) and close one: the state becomes `.closed` while the other is still open. The menu toggle then shows "closed", and `openWindow(_:)` / `openWindow(for:)` open yet another window instead of treating the module as open. On macOS and iPadOS a background scene of one window flips the shared state the same way.
- Action: Count open windows per scene (increment on first `.active`, decrement on disappear) and derive `.opened/.closed` from the count, or key the trackers by a per-window token.
- Severity: Medium
- Status: NEW

### Import apply, trash handling and the data-mutation lock live untested inside a view
- Category: Test gap
- Location: Modules/CoreRPG/FileViews/ImportProgressPanelView.swift:262-304 (`applyReview`), 372-451 (`finishReview`, `settleReviewFiles`, `apply`), 453-575 (`ImportMutationSession`)
- What: The 589-line view contains the whole review-apply pipeline (per item merge onto the changed library item, trash instead of delete, re-parenting of kept folder children, tag restore, folder repair), the file-settle step and the lock/save-deferral session as private statics and a private class; tests reference the view only through snapshot previews (Tests/CoreRPGSnapshotTests).
- Why: This is the path that writes users' library data and holds the `DataMutationCoordinator` lock. A regression (lock not released after cancel, deleted folder children lost, files not settled) cannot be caught by a unit test, and CLAUDE.md asks for view logic to be testable.
- Action: Move `ImportMutationSession` and the apply/finish/settle functions into an `ImportReviewApplyController` (stateless struct per the project's MVC) in CoreRPG/Controller or the same folder and cover: cancel while parsing, cancel while applying (release waits for the apply), apply when the lock is unavailable, deleted folder with kept children, reviewed file settle. The view then drops below 300 lines.
- Severity: Medium
- Status: NEW

### CachePhotoView drops file changes during a load and can erase a cached image
- Category: Bug
- Location: Modules/CoreRPG/LGViews/CachePhotoView.swift:28-31, 69-93
- What: `initImage()` returns early while `isLoading`, so a `model.fileUrl` change during an in-flight load is ignored and nothing re-triggers afterwards; the load is an unstructured `Task(priority:)` that is not cancelled when the view disappears or the url changes; and `setCachedImage/Thumbnail(newImage, ...)` runs even when the load returned `nil`.
- Why: Replacing a photo's file (or a file becoming available) while the previous decode is running leaves the old or placeholder image until something else forces a reload. A transient `nil` result overwrites a good cached image, which `ThumbnailRowPhotoView` explicitly guards against ("A transient read/cancellation must not erase a thumbnail").
- Action: Use `.task(id: model.fileUrl)` like `ThumbnailRowPhotoView` (structured, cancelled and restarted on change) and only publish non-nil results.
- Severity: Medium
- Status: NEW

### Tag search tokens are never applied to the search
- Category: Bug
- Location: Modules/CoreRPG/LGViewModifiers/SearchItemListViewModifier.swift:20-56; Modules/CoreRPG/Model/SearchModel.swift:19, 83-106; Modules/CoreRPG/Controllable/FolderListControllable.swift:69-99
- What: `selectedTokens` is read by nothing except this modifier (grep over Modules and Sources: no other consumer). The search pipeline receives only `searchModel.searchText`. Picking a tag suggestion appends a token and clears `searchFieldText` (and thereby `searchText`), and the pipeline has no `@`-prefix handling, so a typed `@dra` is searched as plain text and matches nothing.
- Why: The search field's prompt promises "Search or use @ for tags"; choosing a suggestion shows a token chip but the list is not filtered. Unverified at runtime, but the code path has no filter step. Removing one token of several does not refresh either (`guard selectedTokens.isEmpty`).
- Action: Decide: either feed `selectedTokens` into `searchRootControllable.results(text:)` (tag filter) and refresh on every token change, or remove the tokens, suggestions, `updateTagSuggestions` and the `@` prompt. Add a test for the chosen behaviour.
- Severity: Medium
- Status: NEW

### Unused vendored Navigator features (about 500 LOC) still attached to every stack
- Category: Dead code
- Location: Modules/CoreRPG/Navigator/Protocols/Callback.swift (71), Protocols/AsyncCallback.swift (56), Core/NavigationLocked.swift (67), Core/NavigationSceneStorage.swift (115), Core/NavigationProvidedDestination.swift (131), Views/NavigationProvidedView.swift (86); Modules/CoreRPG/Navigator/Views/ManagedNavigationStack.swift:71-83, 127, 168; Modules/CoreRPG/Navigator/Core/NavigationSend.swift:150, 173-196
- What: Grep over Modules, Sources and Tests shows zero users outside the Navigator folder (the provided-destination view appears only in a generated snapshot test) for `Callback`, `AsyncCallback`, `navigationLocked()` (so a lock is never taken and `isNavigationLocked` is always false, making the `throw navigationLocked` paths in `popAny`/`dismissAny` unreachable), `ManagedNavigationStack(scene:)`, `navigationSend`, `.pause`/`Navigator.resumableValues` (a static global), `navigationResume`, `dismissPresentedViews`, `isAnyChildPresenting`, `presentingSheetOrCover`. `NavigationSceneStorageModifier` is nevertheless applied to every stack: it adds a `@SceneStorage("NavigationSceneStorage.*")` and a `scenePhase` environment read per stack and does nothing because `name` is always nil. The `restorationKey` values in `Modules/RolePlayGameKit/Model/AppModel.swift:146-173` configure nothing.
- Why: Untested Codable restore logic and global state that looks live but is not; extra scenePhase invalidation per stack. Item selection restoration is done by `ItemStateRestorationView`, not here.
- Action: Delete the listed files and members, the `scene:` initialisers and the modifier, and the `restorationKey` arguments. This is the concrete list for CODE_AUDIT_25 §9.18.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_25 §9.18] (verified and made concrete)

### Navigator tree is mutated from `body`
- Category: SwiftUI
- Location: Modules/CoreRPG/Navigator/Views/ManagedNavigationStack.swift:152-155; Modules/CoreRPG/Navigator/Views/ManagedPresentationView.swift:74-76; Modules/CoreRPG/Navigator/Core/Navigator.swift:233-256
- What: `CreateNavigationStack.body` and `ManagedPresentationView.body` run `parent.addChild(navigator, dismissible:)` on every evaluation, which writes observed properties (`child.isPresented`, `parent.isPresenting`) and `root._current` while SwiftUI computes the view.
- Why: Writing an `@Observable` property that other views read, from inside `body`, can produce "modifying state during view update" warnings and extra update passes. It works today because the writes are idempotent after the first call.
- Action: Register the child once (`LazyState` thunk or `.task`/`onAppear`) and keep only the dismissible refresh in a change handler.
- Severity: Low
- Status: NEW

### GroupEditorController (and its model) is created inside a route body
- Category: SwiftUI
- Location: Modules/CoreRPG/Route/InternalRoute.swift:33 (call site); Modules/CoreRPG/LGViews/GroupEditorView.swift:28-34, 150-155
- What: `GroupEditorView` does not own its `GroupEditorModel`; `InternalRouteDestinationView.body` builds a new `GroupEditorController` (which runs `processEditorModel` and creates a fresh `GroupEditorModel`) every time the body is evaluated.
- Why: Any re-evaluation of the route body while the sheet is open (environment change, observable read in the body) replaces the model and silently discards the name/description/tags the user has typed. This is the same bug class that `DetailFolderControllerReader` already fixed for the detail list (CODE_AUDIT_Folder §8.1).
- Action: Create the model once in `GroupEditorView` via `@State` (initialised from item controller and ids) and keep `GroupEditorController` for saving only.
- Severity: Low
- Status: NEW

### Export panel: unowned start task and file-mover cancel reported as failure
- Category: Bug
- Location: Modules/CoreRPG/FileViews/ExportProgressPanelView.swift:36-62, 125-141, 181-184
- What: With options shown, "Start export" runs `Task { await startExport() }`, which is not cancelled by `.onDisappear` (the comment at line 41 says an export must not outlive its UI) and sets `exportTask` only after a 0.5 s presentation delay, so Cancel or a swipe-down inside that window cancels nothing and the export still runs. Separately, the `fileMover` callback maps only `CancellationError` to `.cancelled`; a user cancelling the system mover returns a failure (Cocoa userCancelled), so it shows as "failed" with the system error text and the temp export file stays behind.
- Why: A detached export with no UI owner (small window) and a misleading error after a normal cancel. The mover behaviour is likely rather than verified on every platform.
- Action: Store the option-start task in `@State` and cancel it on disappear/cancel; map `CocoaError.userCancelled` from the mover to `.cancelled` and delete the temp file on cancel.
- Severity: Low
- Status: NEW

### Views split into helper functions instead of View structs (CLAUDE.md rule)
- Category: SwiftUI
- Location: LGViews/EditorLinkView.swift:97, 116, 129; LGViews/CachePhotoView.swift:43, 52; LGViews/ThumbnailRowPhotoView.swift:51, 58; LGViews/GameShareView.swift:96; LGViewModifiers/ToolbarItemListViewModifier.swift:82, 99; FileViews/SingleReviewFilePropertyRow.swift:94; FileViews/SingleReviewLinkedPropertyRow.swift:79, 102; FileViews/ImportReviewSheetDetailView.swift:76 (13 sites)
- What: Parts of a view are factored into `func ... -> some View` helpers rather than separate `View` structs.
- Why: The project rule forbids breaking views up this way; helpers share the parent's diffing boundary. `CachePhotoView` and `ThumbnailRowPhotoView` also duplicate the `imageView`/`placeHolder`/loading logic.
- Action: Extract the larger ones (placeholder, thumbnail, picker row, share bar, add-item button) into small structs; share one thumbnail view between the two photo views.
- Severity: Low
- Status: NEW

### EditorLinkView.init writes to the observable model
- Category: SwiftUI
- Location: Modules/CoreRPG/LGViews/EditorLinkView.swift:6-12
- What: `init` assigns `editorLinkModel.preselectedModule = selectedModule`, so the model is mutated each time a parent re-evaluates and constructs the view.
- Why: A side effect in view construction runs on every parent update, not once, and can overwrite a value changed since with the parent's stale `selectedModule` (the `onAppear` then re-applies the preselection).
- Action: Apply the preselection once in `onAppear`/`task`; keep `init` free of side effects.
- Severity: Low
- Status: NEW

### ItemHeaderEditorView: UIKit haptic and focus after a cancelled sleep
- Category: API
- Location: Modules/CoreRPG/LGViews/ItemHeaderEditorView.swift:61-66, 88-91
- What: `UINotificationFeedbackGenerator` is used directly (CLAUDE.md: avoid UIKit, use `.sensoryFeedback`), and the focus task does `try? await Task.sleep` then sets `currentFocus = .name` even if the sleep was cancelled.
- Why: Rule violation (minor); a quickly dismissed editor still writes focus state.
- Action: `.sensoryFeedback(.success, trigger:)`; `guard !Task.isCancelled` after the sleep.
- Severity: Low
- Status: NEW

### NavigationAction equality is the function name of its creator
- Category: Bug
- Location: Modules/CoreRPG/Navigator/Core/NavigationAction.swift (`init(_ name: String = #function ...)`, `==`/`hash` on `name` only; `send(_:)`, `with(navigator:perform:)`, `popAll(in:)`, `action(handler:)`)
- What: Two actions built by the same factory compare equal whatever they carry (`.send(RootRoute.game) == .send(RootRoute.search)`, since both are named `send(_:)`).
- Why: `[NavigationAction]` from `WindowRouter` cannot be compared or deduplicated meaningfully, `onChange(of: [NavigationAction])` in `navigationSend(values:)` would miss changes, and any future unit test of `WindowRouter` (currently no test references it) using `==` would pass for wrong routes.
- Action: Include the sent value (or an explicit identity) in `name`/hash, or drop `Hashable` from the type and compare via a descriptor in tests.
- Severity: Low
- Status: NEW

### Navigator event log is public in release and ignores its verbosity
- Category: Security
- Location: Modules/CoreRPG/Navigator/Core/NavigationEventLogging.swift:11-28; Modules/RolePlayGameKit/Model/AppModel.swift:277-279
- What: Every push, present, send and receive event is logged through `Logger.bootStrap.info("\(event.description, privacy: .public)")` in all builds; the description interpolates the route enum, including item ids and text-carrying routes. Also `log` computes a `verbosity` but always passes `.info` to the event.
- Why: Item ids and route payloads land in the unified log as public data (sysdiagnose) and every navigation builds the description string. Low impact since ids are random UUIDs.
- Action: Use `.private` (or log only the case name) and gate the logger on DEBUG; pass the computed verbosity.
- Severity: Low
- Status: NEW

### Move-into-group context menu computes candidates twice and is unbounded
- Category: Performance
- Location: Modules/CoreRPG/LGViews/ListRootContextMenu.swift:337-401
- What: `MoveIntoGroupMenu` evaluates `hasCandidates` and then `candidates` (each walking every item calling `canMoveIntoGroup`, the second also `itemSync` and a localized sort) and builds one `Button` per candidate.
- Why: For a module with hundreds of items a context-menu open does two O(n) passes and produces a very long menu.
- Action: Compute the list once, cap it, or use a searchable picker sheet.
- Severity: Low
- Status: NEW

### Duplicated add-link handler and unused environment value
- Category: Duplication
- Location: Modules/CoreRPG/LGViews/ItemRowsView.swift:13, 42-53; Modules/CoreRPG/LGViews/ListRowItemView.swift:157-169
- What: `addLink(name:itemId:entryId:)` is copied verbatim; `ItemRowsView` declares `@Environment(\.appTheme) theme` it never reads.
- Why: Two copies to keep in sync (the comment already cites one fix, CODE_AUDIT_Folder §5.29, that had to land in both).
- Action: Move it into the list controller or a shared helper; remove the unused environment.
- Severity: Low
- Status: NEW

### Silent failures on share and file replacement
- Category: Bug
- Location: Modules/CoreRPG/LGViews/GameShareView.swift:150-160; Modules/CoreRPG/LGViews/FileImporterView.swift:59-63, 153-160; Modules/CoreRPG/FileViews/FileReplacementConfirmation.swift:65-71
- What: A player share uses `try? await createGameData(for:)` in an unowned `Task`; the file importer ignores the `Bool` that `resetFile` returns, which is `false` for both a cancelled replacement and a failed one.
- Why: A failed share or a failed picked/URL import gives no feedback, although picker failures are reported (the code comments mention that a failed pick "looked like nothing happened").
- Action: Return a result with an error from `resetFile`, show it through the existing `pickerError`/`importFailureAlert`; surface the share failure (row status or log).
- Severity: Low
- Status: NEW

### GameBundleBrowserModel: cancel then restart can clear the new download's state
- Category: Concurrency
- Location: Modules/CoreRPG/FileViews/GameBundleBrowserModel.swift:66-92
- What: `cancelDownload()` sets `downloadTask = nil` but the cancelled task's completion block still runs `downloadTask = nil` and, for the cancellation error, `status = .idle`.
- Why: If the person cancels and starts another download right away, the old task's tail wipes the new task reference and the `.downloading` status (the new download still finishes, but the UI shows idle and a third start is allowed).
- Action: Compare a per-download token before touching `downloadTask`/`status` in the completion.
- Severity: Low
- Status: NEW

### Preview fixtures compiled into release and a few fixed sizes
- Category: Refactor
- Location: Modules/CoreRPG/FileViews/ImportReviewPreviewData.swift (39 LOC), FileViews/SingleReviewPreviewData.swift (197 LOC); LGViews/GridLabelView.swift:36-39; LGViews/CachePhotoView.swift:26, 55-60; FileViews/ImporterFanView.swift:140-143
- What: Two preview fixture files are not `#if DEBUG` (CLAUDE.md: fixtures in `#if DEBUG`); `GridLabelView` fixes its icon at 50x50, `CachePhotoView` its placeholder at 105x105 with `scaleEffect(2.0)`, and `ImporterFanLayout.radius` (120) does not scale with Dynamic Type while the fan buttons do (`@ScaledMetric`).
- Why: About 240 LOC of preview-only code in the release binary; at large Dynamic Type the fan buttons overlap and icons stay small.
- Action: Wrap the two fixtures in `#if DEBUG` (check the snapshot targets build Debug), use `@ScaledMetric` for the sizes and scale the fan radius with the button size.
- Severity: Low
- Status: NEW

### Item generation does nothing on tvOS
- Category: Bug
- Location: Modules/CoreRPG/LGViews/ItemGenerationPresentationModifier.swift:45-59
- What: `present(itemId:)` handles macOS/visionOS (window) and iOS (overlay) but has no tvOS branch, while `isEnabled` is still `root.generationControllable != nil`, so a "Generate" button/menu entry would be shown and inert.
- Why: Only reachable if a generation controllable exists on tvOS (Table); unverified. Dead button if so.
- Action: Return `isEnabled: false` on tvOS (or add the branch).
- Severity: Low
- Status: NEW

Not audited in this area: the smaller FileViews review rows (Single*/ImportReview* row and badge views, about 25 files of 20-120 LOC), `SingleReviewModels.swift`/`ImportReviewModels.swift` and `ImportReviewSplitView`/`ImportReviewSheetDetailView` (skimmed by grep only for tasks, force unwraps and `ForEach` identity, no hits); LGViews `ThumbnailRowEmptyView`, `TwoLineTagView`, `TagDisplayView`, `MenuSelectionButtonView`, `NavigationColumnFocus`; Navigator `AnyNavigationDestination`, `NavigationDestination`, `NavigationModifiers`, `NavigationConfiguration`, `NavigationFind`, `NavigationRoutes`, `NavigationProvidedDestination` internals (skimmed). No code was run; the `fileMover` cancel behaviour, tag-token inertness at runtime and tvOS generation reachability are code-reading conclusions only.
