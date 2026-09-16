# MasterRPG Code Audit — SpaceRPG Module

Generated 2026-09-16. Scope: `Modules/SpaceRPG/` only (91 Swift files, ~8,195 LOC, 0 Metal kernels) — the 3D Object Capture / reconstruction module, heavily adapted from Apple's "Guided Capture" Object Capture sample under this project's `@Observable`/MVC architecture. No directories were excluded (no `Dead/` or archive folder exists under this module).

A full clean build of the `SpaceRPG` scheme (`xcodebuild -scheme SpaceRPG clean build`) produced **zero real compiler warnings** — the module is already warning-clean under Swift 6 / `SWIFT_STRICT_CONCURRENCY = complete`. All findings below come from manual reading of every file in the module (not grep-only), cross-checked against `MasterRPG.xcodeproj/project.pbxproj` and `Resources/Info.plist` where cited.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

---

## 1. Executive summary

1. **[High] Reconstruction failure leaves a permanently blank, stuck screen** — §5.1 — `Modules/SpaceRPG/Record/AppDataModel.swift:387-394`. If `startReconstruction()` throws, `state` never leaves `.prepareToReconstruct`, no error is shown, and the only way out is to force-quit.
2. **[High] `PhotogrammetrySession.process(requests:)` throw is silently swallowed** — §5.2 — `Modules/SpaceRPG/Record/ReconstructionProgressView.swift:91-95`. The reconstruction UI can hang at 0% indefinitely with no error state.
3. **[High] `@State` seeded from `preopen` never re-applies after first creation** — §5.6 — `Modules/SpaceRPG/View/InlineImporterView.swift:106-119`. The importer's own code comment asserts behavior that SwiftUI's `@State` semantics don't actually provide.
4. **[High] 3D Space viewing is completely non-functional on tvOS** — §8.2 — `Modules/SpaceRPG/Space/SpaceViewer.swift:7` (whole file gated `#if !os(tvOS)`), confirmed `MasterTV` links `SpaceRPG.framework` via `project.pbxproj:5932-5936`. Apple TV players silently see nothing where a 3D model should render.
5. **[High] Raw capture photos sit in a file-shared, iCloud-backed-up folder with no crash-recovery cleanup** — §6.1 — `Modules/SpaceRPG/Record/CaptureFolderManager.swift:204-207`, `Resources/Info.plist:116-117` (`UIFileSharingEnabled = true`).
6. **[High] `View.if()` reimplements CoreRPG's `applyIf`, already used elsewhere in this same module** — §8.1 — `Modules/SpaceRPG/Record/OnboardingButtonView.swift:122-130`.
7. **[High] `SpaceShortcutCatalog`'s App Shortcuts are fully implemented but never registered** — §9.3 — `Modules/SpaceRPG/Intent/SpaceShortcutCatalog.swift:10-75`; matches the build log's "No AppShortcuts found — Skipping" for this framework.
8. **[Medium] `scanFolderManager` implicitly-unwrapped optional force-accessed at 3+ sites** — §3.1 — `Modules/SpaceRPG/Record/AppDataModel.swift:48`, `CaptureFilesButton.swift:38`.
9. **[Medium] `CaptureFolderManager.shots`/`loadShots()` dead code duplicates a blocking re-implementation in `ProgressBarView`** — §7.1 / §9.2 — `Modules/SpaceRPG/Record/ProgressBarView.swift:30-39` vs `CaptureFolderManager.swift:31,57-81`.
10. **[Medium] `SpaceViewer.swift` (1086 lines) is the module's largest file by 2.3×** — §9.4 — clear, low-risk split proposal along existing `// MARK:` boundaries.

---

## 2. Quick wins (≤30 min each)

- **Delete `CaptureOverlayView.VisualEffectView`** — `Modules/SpaceRPG/Record/CaptureOverlayView+Buttons.swift:44-48`. Unused `UIViewRepresentable`, superseded by `.ultraThinMaterial`. See §9.1.
- **Delete `CaptureFolderManager.heicImageUrl(in:id:)`** — `Modules/SpaceRPG/Record/CaptureFolderManager.swift:118-129`. No call sites. See §9.1.
- **Delete `SpaceEntity.thumbnailRepresentationData`** — `Modules/SpaceRPG/Intent/SpaceEntity+Image.swift:14-18`. No call sites. See §9.1.
- **Remove unused `import PDFKit`** — `Modules/SpaceRPG/Intent/SpaceEntity.swift:10`. Copy-paste leftover from PdfRPG. See §9.1.
- **Remove unused `import Combine`** — 4 files: `TimedMessageList.swift:10`, `ShotFileInfo.swift:10`, `OnboardingStateMachine.swift:11`, `CaptureFolderManager.swift:11`. See §4.3.
- **Rename `fileURL` → `fileUrl`** — `Modules/SpaceRPG/Record/ShotFileInfo.swift:16,20`. The only `Id`/`Url`-casing violation in the module. See §4.2.
- **Hoist 4 constant dictionaries to `static let`** — `Modules/SpaceRPG/Record/OnboardingTutorialView.swift:88-152`. See §7.3.
- **Replace `fatalError`/`precondition` with graceful guards** — `AppDataModel.swift:207-212`, `ReconstructionProgressView.swift:84`. Both currently unreachable but fragile. See §3.4, §5.3.

---

## 3. Concurrency

### 3.1 `scanFolderManager` implicitly-unwrapped optional force-accessed at multiple sites
- **Location:** `Modules/SpaceRPG/Record/AppDataModel.swift:48` (`private(set) var scanFolderManager: CaptureFolderManager!`); force-accessed at `AppDataModel.swift:299,403` and `Modules/SpaceRPG/Record/CaptureFilesButton.swift:38` (`appModel.scanFolderManager.rootScanFolder`)
- **What:** `scanFolderManager` is typed as an IUO and is force-unwrapped (directly or via non-optional-returning properties) at several call sites, relying on state-machine invariants rather than the type system.
- **Why:** Any future state-machine change, or `CaptureFilesButton` staying visible one frame after a cancel/reset nils the model, turns this into an unrecoverable crash. `Scanner3DRootView.swift:75` already shows the safe pattern (`if let folderManager = appModel.scanFolderManager`) is available but not used consistently.
- **Action:** Make `scanFolderManager` a plain `CaptureFolderManager?` and thread an explicit guard/early-return through each access site, matching `Scanner3DRootView`'s existing safe pattern.
- **Severity:** Medium

### 3.2 `@preconcurrency import RealityKit` isolated to one file
- **Location:** `Modules/SpaceRPG/Record/ReconstructionProgressView.swift:9`
- **What:** This is the only file in the module importing RealityKit with `@preconcurrency`; `SpaceViewer.swift` and others import it plainly.
- **Why:** Since the build is otherwise 100% warning-clean, this attribute is actively suppressing Sendability diagnostics for `PhotogrammetrySession.Output`/`PointCloud` crossing into a `.task`/`@State` boundary, rather than being vestigial — worth confirming it's still needed against the iOS 26 RealityKit SDK.
- **Action:** Verify whether `@preconcurrency` is still required; if so, add a short comment explaining why (matching this module's pattern of documenting non-obvious workarounds).
- **Severity:** Low

### 3.3 AsyncSequence error silently collapsed into end-of-stream
- **Location:** `Modules/SpaceRPG/Record/UntilProcessingCompleteFilter.swift:36-39` (`guard let nextElement = try? await iterator.next() else { completed = true; return nil }`)
- **What:** Any error thrown by the underlying `PhotogrammetrySession.Outputs` iterator is discarded via `try?` and treated identically to a clean end-of-stream.
- **Why:** A real pipeline failure is indistinguishable from normal completion to `ReconstructionProgressView`'s `for await` consumer, which just stops silently with no error surfaced (compounds with §5.2).
- **Action:** Propagate the error from `next()` instead of collapsing it to `nil`, or capture it into a side channel the consumer can check.
- **Severity:** Medium

### 3.4 Force-unwraps and a `fatalError` verified safe today, but fragile
- **Location:** `Modules/SpaceRPG/Record/AppDataModel+Orbit.swift:31` (`Self.allCases.firstIndex(of: self)!`); `Modules/SpaceRPG/Record/PlayerView.swift:168-175` (`AVPlayerLayer!` IUO computed property, re-cast on every access); `Modules/SpaceRPG/Record/AppDataModel.swift:207-212` (`fatalError("Logic error")` in `attachListeners()`, guarded correctly today by its only caller at `AppDataModel.swift:32-40`'s `didSet`)
- **What:** All three were individually traced and confirmed unreachable under the current call graph (self is always a member of its own `CaseIterable.allCases`; `AVPlayerView.layerClass` guarantees the cast; `attachListeners()`'s only caller already checks non-nil immediately before calling it).
- **Why:** No live bug, but all three rely on an invariant enforced by a separate function rather than the type system — a future refactor that adds a second call path would silently reintroduce a crash.
- **Action:** No urgent action. Optionally: `guard`-based non-fatal handling in `Orbit.next()`; cache the `AVPlayerLayer` cast once in `PlayerView`; pass the just-set session into `attachListeners(_:)` as a parameter to remove the internal `fatalError` entirely.
- **Severity:** Low

---

## 4. API modernity

### 4.1 Legacy `NSLocalizedString` mixed with modern `String(localized:)`, including within the same struct
- **Location:** 9 files use `NSLocalizedString(_:bundle:value:comment:)`: `AppDataModel.swift:441-468`, `FeedbackMessages.swift:23-55`, `BoundingBoxGuidanceView.swift:34-54`, `ProgressBarView.swift:94-113`, `ReconstructionTitleView.swift:17-22`, `ReconstructionProgressView.swift:156-213`, `CaptureOverlayView+LocalizedString.swift`, `OnboardingButtonView+LocalizedString.swift`, `OnboardingTutorialView+LocalizedString.swift` — the last of which uses `NSLocalizedString` for `tooFewImagesTitle` (line 13) and `String(localized:bundle:comment:)` for `tooFewImagesDetailText` five lines later (line 24).
- **What:** Carryover from Apple's Combine/UIKit-era sample; other parts of the same module (`SpaceModel.swift:178`, `InlineImporterView.swift:24-28`) already use the modern API.
- **Why:** `NSLocalizedString` doesn't participate in Xcode 26's String Catalog extraction the same way; the in-file split proves this isn't a deliberate per-context choice.
- **Action:** Migrate all 9 files' call sites to `String(localized:bundle:comment:)`. Low risk — pure sample carryover.
- **Severity:** Low

### 4.2 `Url` naming-convention violation
- **Location:** `Modules/SpaceRPG/Record/ShotFileInfo.swift:16,20` (`let fileURL: URL`)
- **What:** The only identifier in the module using `URL` casing instead of this repo's mandated `Url` (e.g. `SpaceModel.fileUrl` elsewhere in the same module already gets this right).
- **Why:** Direct CLAUDE.md naming-convention violation.
- **Action:** Rename to `fileUrl` (2 use sites in the same small file).
- **Severity:** Low

### 4.3 Dead `Combine` imports
- **Location:** `Modules/SpaceRPG/Record/TimedMessageList.swift:10`, `ShotFileInfo.swift:10`, `OnboardingStateMachine.swift:11`, `CaptureFolderManager.swift:11`
- **What:** Four files `import Combine` with zero Combine-type usage (confirmed via module-wide grep).
- **Why:** Leftover from adapting Apple's Combine-based sample to `@Observable`; unnecessary framework dependency per file.
- **Action:** Remove the four imports.
- **Severity:** Low

### 4.4 `LocString` vs `LocalizedString` naming split for the same concept
- **Location:** `Modules/SpaceRPG/Record/AppDataModel.swift:437-468` (`enum LocString`) vs `CaptureOverlayView+LocalizedString.swift`, `OnboardingButtonView+LocalizedString.swift`, `OnboardingTutorialView+LocalizedString.swift`, `ProgressBarView.swift:93` (all `struct LocalizedString`)
- **What:** One central localization container is named `LocString` while four per-view containers doing the same job are named `LocalizedString`; `LocString.bundleForLocalizedStrings` is referenced across files, so the name is load-bearing.
- **Why:** Confusing when scanning the module — two synonymous names for the same role.
- **Action:** Rename `LocString` to something distinguishing its role (e.g. `SharedLocalizedString`), keeping `bundleForLocalizedStrings` accessible.
- **Severity:** Low

### 4.5 Business-logic constant stored inside a localization-named type
- **Location:** `Modules/SpaceRPG/Record/AppDataModel.swift:437-438` (`enum LocString { static let minNumImages = 10 ... }`)
- **What:** `minNumImages`, a plain capture-flow threshold unrelated to localized text, lives inside `LocString`.
- **Why:** Misleading organization — a reader looking for capture thresholds wouldn't look in a "LocString" type.
- **Action:** Move `minNumImages` into a small `CaptureConstants` enum alongside the other capture thresholds noted in §9.8.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Reconstruction-init failure leaves a permanently blank, stuck screen
- **Location:** `Modules/SpaceRPG/Record/AppDataModel.swift:387-394` (root cause, verified by direct read); manifests at `Modules/SpaceRPG/Record/Scanner3DRootView.swift:33-35,64-72`
- **What:** `performStateTransition(.prepareToReconstruct)` calls `try startReconstruction()`; its `catch` block only logs `"Reconstructing failed!"` and never calls `switchToErrorState(error:)` or otherwise changes `state`, unlike every other failure path in this file.
- **Why:** `state` stays at `.prepareToReconstruct`, which `Scanner3DRootView`'s `showProgressView`/`onChange(of: appModel.state)` treat as neither "capturing" nor "show progress/sheet" nor "failed" — the view renders an empty `VStack` with `showErrorAlert` never firing and no button on screen. The user's only recovery is force-quitting the app.
- **Action:** In the `catch` block at `AppDataModel.swift:392-394`, call `switchToErrorState(error: error)` exactly like the other failure paths in this file do.
- **Severity:** High

### 5.2 `PhotogrammetrySession.process(requests:)` throw silently swallowed mid-reconstruction
- **Location:** `Modules/SpaceRPG/Record/ReconstructionProgressView.swift:91-95`
- **What:** `try session.process(requests: [.modelFile(url: outputFile)])` is wrapped in a `do/catch` that only logs; execution falls through into `for await output in outputs` regardless of whether `process` actually started.
- **Why:** If `process(requests:)` throws (disk full, bad input directory), no request is running, so `outputs` may never emit `.processingComplete`/`.requestError`. The progress UI is stuck at 0% indefinitely with no error state, and the visible Cancel button calls `cancel()` on a session with nothing in flight.
- **Action:** On catch, set `gotError = true` / `error = <the catch error>` (the same fields `.requestError` already sets) and `return` instead of falling through.
- **Severity:** High

### 5.3 `precondition()` trap used as a state-invariant check
- **Location:** `Modules/SpaceRPG/Record/ReconstructionProgressView.swift:84`
- **What:** `.task { precondition(appModel.state == .reconstructing); ... }` traps — in Release builds too — if this view's task ever runs while `appModel.state` isn't exactly `.reconstructing`.
- **Why:** Not reachable under the current call graph, but `AppDataModel.swift:239-246`'s own comment explicitly argues against this exact style ("Graceful failures rather than `preconditionFailure`... should surface an error state instead of crashing the whole app"). A future state-machine change or additional presentation call site would crash instead of degrading.
- **Action:** Replace with `guard appModel.state == .reconstructing else { <log + set error state>; return }`, matching the pattern already used elsewhere in this module.
- **Severity:** Medium

### 5.4 `PhotogrammetrySession` never explicitly cancelled on abnormal teardown
- **Location:** `Modules/SpaceRPG/Record/ReconstructionProgressView.swift:83-100` (only the Cancel button calls `session.cancel()`); `Modules/SpaceRPG/Record/AppDataModel.swift:324` (`reset()` only nils the reference)
- **What:** If the hosting `.task` is torn down some other way (e.g. the stuck-state bug in §5.1/§5.2, or a future navigation change), nothing tells the still-live session to stop — `reset()` only drops the Swift reference.
- **Why:** A dropped-but-not-cancelled `PhotogrammetrySession` can keep consuming CPU/GPU/battery for the whole multi-minute reconstruction with no user-visible indication.
- **Action:** Call `photogrammetrySession?.cancel()` explicitly inside `reset()` before nilling it out.
- **Severity:** Medium

### 5.5 Spotlight-indexing failure after a successful data mutation reported as a full intent failure
- **Location:** `Modules/SpaceRPG/Intent/SpaceManagementIntents.swift:40-44` (`CreateSpaceIntent`), `:86-88` (`AddSpaceNoteIntent`), `:131-133` (`DeleteSpaceIntent`)
- **What:** In all three intents, the data mutation (`itemController.replace`/`editController.reset`/`editController.delete` + `save()`) is committed first; the following un-caught `try await indexIntentEntities(...)`/`deleteIntentEntities(...)` call can throw and fail the whole `perform()`.
- **Why:** A CoreSpotlight hiccup makes Siri/Shortcuts report a successful create/edit/delete as failed — a retry can create duplicates or attempt to delete an already-deleted item.
- **Action:** Wrap the Spotlight calls in `try?` (or a local do/catch that only logs) so an indexing failure doesn't override an already-successful mutation's result.
- **Severity:** Medium

### 5.6 `@State` seeded from a parameter never re-applies after first creation
- **Location:** `Modules/SpaceRPG/View/InlineImporterView.swift:106-119` (init seeds `@State private var isExpanded` from `preopen` via `State(wrappedValue:)`); claim asserted at `:96-101`
- **What:** `InlineImporterContentView.init` seeds `isExpanded` from `preopen`, but `InlineImporterView.body` (lines 86-94) recreates this child on every re-render at the same tree position with no `.id()`, so SwiftUI preserves the existing `@State` storage and never re-applies a changed `preopen`.
- **Why:** The type's own `Equatable` conformance comment (lines 97-101) explicitly claims `preopen` "drive[s] stored state (`isExpanded`'s seed...) that must update when they change for the same `itemId`" — but per SwiftUI's documented `@State` semantics this does not happen; `.equatable()` only controls whether `body` re-runs, not whether `@State` re-seeds. A `preopen` flip for an already-materialized importer (same `itemId`) will not expand/collapse it as intended.
- **Action:** Force identity reset on `preopen` change (e.g. `.id(preopen)` on the child) or drive `isExpanded` via `.onChange(of: preopen)` instead of only seeding it in `init`.
- **Severity:** High

### 5.7 Pending immersive-space handoff entity can be retained indefinitely
- **Location:** `Modules/SpaceRPG/Space/SpaceHandoffModel.swift:31-48`
- **What:** `handOff(itemId:entity:)` detaches an `Entity` and stores it in `pending`, released only by a matching `takePending(for:)` from the immersive space's `loadEntity`, or overwritten by the next handoff.
- **Why:** If the immersive space is never opened after a handoff (e.g. `openSpaceViewer` fails or the user backs out early), the detached entity's full USDZ mesh/texture data is retained with no owner until the next handoff overwrites it.
- **Action:** Add a timeout or an explicit "handoff cancelled" callback that clears `pending` if the immersive space doesn't claim it within a bounded window.
- **Severity:** Low

### 5.8 Silent failure of the player "share" network action
- **Location:** `Modules/SpaceRPG/Controller/LinkController.swift:22-31`
- **What:** `toggleTextLink`'s `.share` handling does `if let result = try? await gameController.createGameData(for: itemId) { ... }` — `try?` discards any thrown error with no logging and no user-facing feedback.
- **Why:** If generating game data fails (e.g. the file isn't downloaded from iCloud yet), the player who tapped "share" gets no indication anything went wrong.
- **Action:** Log the error at minimum, and surface a transient failure message via the existing feedback/message mechanism.
- **Severity:** Low

### 5.9 `currentItemId ?? UUID()` fallback routes "nothing selected" through the "not found" path
- **Location:** `Modules/SpaceRPG/Controller/ViewController.swift:45,48,51`
- **What:** `gameViewer(root:)` uses `root.gameController.gameModel.currentItemId ?? UUID()` whenever `currentItemId` is `nil`.
- **Why:** A freshly generated random `UUID()` can never match a real item, always resolving to the "item not found" empty state instead of an explicit "nothing currently active" state — making the two causes indistinguishable in logs/error UI.
- **Action:** Make "no current item" an explicit branch instead of routing a bogus UUID through the normal load path.
- **Severity:** Low

---

## 6. Security

### 6.1 Raw capture photos sit in a file-shared, iCloud-backed-up folder for the whole capture+reconstruction lifetime, with no crash-recovery cleanup
- **Location:** `Modules/SpaceRPG/Record/CaptureFolderManager.swift:204-207` (`rootScansFolder()` returns `URL.documentsDirectory.appending(path: "Scans/")`); `Resources/Info.plist:116-117` (`UIFileSharingEnabled = true`, verified); `Modules/SpaceRPG/Record/AppDataModel.swift:307-332` (`reset()` is the only cleanup path)
- **What:** Every capture session's raw HEIC photos (and, transiently, the finished USDZ) are written under `Documents/Scans/<timestamp>/`; `UIFileSharingEnabled` is `true` app-wide, exposing this folder via Finder/Files-app file sharing and including it in iCloud/device backups. No startup sweep anywhere in the module removes stale `Scans/` subfolders left behind by a crash or force-quit mid-capture.
- **Why:** Photos of a user's real tabletop/miniatures/room are user-extractable and backed up for as long as a scan is mid-flow (minutes), or indefinitely if the app is killed mid-flow, since nothing revisits `Documents/Scans/` on next launch.
- **Action:** Move capture work-in-progress to a non-file-shared, non-backed-up location (`URL.cachesDirectory` with `NSURLIsExcludedFromBackupKey`, or the App Group container), and add a one-time startup sweep that deletes leftover `Scans/*` subfolders from a previous run.
- **Severity:** High

---

## 7. Performance

### 7.1 Blocking synchronous FileManager call in a SwiftUI computed property, duplicating unused dead code
- **Location:** `Modules/SpaceRPG/Record/ProgressBarView.swift:30-39` (`numOfImages`, calling `FileManager.default.contentsOfDirectory` synchronously, invoked at lines 64 and 68 — recomputed on every body evaluation) vs `Modules/SpaceRPG/Record/CaptureFolderManager.swift:31,57-81` (`shots`/`loadShots()`, built for exactly this purpose but never called — see §9.2)
- **What:** `ProgressBarView.numOfImages` re-implements "count HEIC files in the images folder" via blocking disk I/O inside a computed property, hardcoding `"HEIC"` again instead of reusing an existing constant, while `CaptureFolderManager` already has unused plumbing for this.
- **Why:** Repeated synchronous directory listing on the main actor during `ReconstructionProgressView`'s live progress-stream updates can visibly hitch the reconstruction screen, especially with hundreds of shots.
- **Action:** Wire `CaptureFolderManager.loadShots()` to run when entering `.viewing`/reconstruction states and have `ProgressBarView` read `appModel.scanFolderManager.shots.count` instead of hitting the filesystem itself.
- **Severity:** Medium

### 7.2 `Bundle.module.url` filesystem lookup performed inline during body evaluation
- **Location:** `Modules/SpaceRPG/Record/CaptureOverlayView.swift:44-48` (inline in `body`'s `if shouldShowTutorial` branch); `Modules/SpaceRPG/Record/OnboardingTutorialView.swift:102-110` (`tutorialUrl` computed property)
- **What:** Both call `Bundle.module.url(forResource:withExtension:)` — a filesystem lookup — directly during body evaluation rather than caching the resolved URL once.
- **Why:** `CaptureOverlayView`'s body re-evaluates frequently during an active capture session, redoing this I/O unnecessarily on every re-render while `shouldShowTutorial` is true.
- **Action:** Resolve the video URL once (cached on the model or a lazily-computed stored property keyed on the inputs that actually change it) instead of re-resolving per body pass.
- **Severity:** Medium

### 7.3 Instance-level constant dictionaries reallocated on every view init
- **Location:** `Modules/SpaceRPG/Record/OnboardingTutorialView.swift:88-93,95-100,120-133,139-152` (`onboardingStateToTutorialNameMapOnIphone`, `onboardingStateToTutorialNameMapOnIpad`, `onboardingStateToTitleMap`, `onboardingStateTodetailTextMap`)
- **What:** Four dictionary literals mapping `OnboardingState` to strings are declared as instance `private let` properties, rebuilt every time the view is re-initialized (i.e. on every onboarding-state transition from the parent).
- **Why:** These maps have compile-time-constant content with no dependency on instance state; rebuilding them per-init is unnecessary allocation.
- **Action:** Hoist all four to `static let`.
- **Severity:** Low

### 7.4 Missing `Equatable` on hot, frequently re-rendering leaf views
- **Location:** `Modules/SpaceRPG/Record/ReconstructionProgressView.swift:13`, `ProgressBarView.swift:14`, `CircularProgressView.swift:9`, `FeedbackView.swift:14`
- **What:** None of these views conform to `Equatable`/use `.equatable()`, unlike `InlineImporterView`/`InlineRowViewer` elsewhere in the same module, which already adopt exactly this pattern with a documented rationale.
- **Why:** These are the module's actual hot/timer-driven update paths (reconstruction progress polling, live capture feedback) — good candidates for the optimization already proven out elsewhere in this module.
- **Action:** Adopt `Equatable` (with a custom `==` excluding closure/reference properties, as `InlineImporterView` already models) and apply `.equatable()` at call sites.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 `View.if()` conditional modifier reimplements CoreRPG's `applyIf`, already used elsewhere in this module
- **Location:** `Modules/SpaceRPG/Record/OnboardingButtonView.swift:122-130` (definition), used at `Modules/SpaceRPG/Record/OnboardingCreateButton.swift:48`
- **What:** A bare `extension View { func \`if\`(...) }` is defined here, functionally identical to `CoreRPG/ViewModifiers/IfModifier.swift`'s `applyIf(_:transform:)` — which `SpaceRPG` itself already calls in `Space/SpaceViewer.swift:145,1006` and `Root/ViewerRootView.swift:23`. It's also the documented SwiftUI anti-pattern of branching between two different view subtrees based on a condition, which risks view-identity/animation surprises if the condition ever becomes dynamic.
- **Why:** Two conditional-view-modifier spellings coexist in the same module, risking future divergence, and needlessly widens the module's `View` namespace.
- **Action:** Delete the local `if` extension; change the one call site to `.applyIf(shouldApplyBackground)` from CoreRPG.
- **Severity:** High

### 8.2 3D Space viewing is completely non-functional on tvOS
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:7-1086` (entire type gated `#if !os(tvOS)`, no fallback); `Modules/SpaceRPG/Root/ViewerRootView.swift:15-21` (body is empty on tvOS); `Modules/SpaceRPG/View/SpaceQuickLook.swift:35-58` (`loader()` is an empty function outside visionOS); `Modules/SpaceRPG/Controller/ViewController.swift:43-46` (`gameViewer` on tvOS renders `SpaceQuickLook`, which does nothing there); verified `MasterTV` links `SpaceRPG.framework` via `MasterRPG.xcodeproj/project.pbxproj:3465` (`PBXTargetDependency` `8E8F02552ED1873B00A0A6F7`) `→ :5932-5936` (target = SpaceRPG)
- **What:** Every tvOS code path meant to show a 3D model — the in-game viewer, the generic item viewer, and `SpaceQuickLook` — ends up doing nothing, since `SpaceViewer` (the only thing that loads/renders a USDZ) doesn't exist on tvOS at all.
- **Why:** Apple TV players can never see a Space item during gameplay or in the item detail screen — a silent no-op with no error message and no static fallback.
- **Action:** Either implement a tvOS-appropriate fallback (e.g. a static `ImageRenderer` snapshot of the model, since tvOS has no AR/RealityKit capture-viewing story) with an explicit "not supported on Apple TV" state, or explicitly hide the "open 3D object" affordance on tvOS instead of silently failing.
- **Severity:** High

### 8.3 Method-based view decomposition instead of a `View` struct
- **Location:** `Modules/SpaceRPG/View/InlineImporterView.swift:192-219` (`private func button(type:) -> some View`, called 3× in `body`)
- **What:** A private function returning `some View` factors out the three fan-out buttons instead of a dedicated `View` struct.
- **Why:** CLAUDE.md explicitly requires extracting into `View` structs rather than functions/computed properties; a function-based extraction still folds into the parent's single diffing unit.
- **Action:** Extract `button(type:)` into an `ImporterFanButton: View` struct.
- **Severity:** Medium

### 8.4 `errorView` helper not extracted despite the file's own established convention
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:464-479` (`private func errorView(message:) -> some View`), used at lines 93, 117
- **What:** Every other piece of `SpaceViewer`'s UI was deliberately pulled into standalone `View` structs (per the file's own header comment, specifically to stop unrelated body changes from re-evaluating everything) — except this one function-based helper.
- **Why:** `errorView` re-evaluates as part of `SpaceViewer`'s own body, undermining the diffing-boundary goal the rest of the file was refactored for.
- **Action:** Extract into `private struct SpaceViewerErrorView: View` alongside the other extracted subviews.
- **Severity:** Low

### 8.5 Manual `colorScheme` branching reimplements semantic adaptive color, duplicated across 3 files
- **Location:** `Modules/SpaceRPG/Record/CircularProgressView.swift:19` (`colorScheme == .light ? .black : .white`), `OnboardingCreateButton.swift:35` (same), `OnboardingView.swift:26` (`Color(colorScheme == .light ? .white : .black)`)
- **What:** Three views read `@Environment(\.colorScheme)` and manually branch `.black`/`.white` to fake dark-mode adaptivity, rather than sharing one helper.
- **Why:** Duplicates what semantic colors (`.primary`, `Color(.systemBackground)`) already provide, and won't track increased-contrast or custom accessibility color schemes correctly; a future dark-mode tint change needs updating in three places.
- **Action:** Replace all three with `.primary`/`Color(.systemBackground)` (or a single shared adaptive helper if a non-semantic look is intentional).
- **Severity:** Medium

### 8.6 Hardcoded UIKit appearance colors don't adapt to dark mode
- **Location:** `Modules/SpaceRPG/Record/HelpPageView.swift:43-46`
- **What:** `.onAppear` sets `UIPageControl.appearance().currentPageIndicatorTintColor = .black` and `.pageIndicatorTintColor = .lightGray` unconditionally.
- **Why:** Raw UIKit colors set outside SwiftUI's color system (also violates "avoid UIKit colors in SwiftUI code"); in dark mode the black page-indicator dot becomes invisible against a dark background.
- **Action:** Drive from `colorScheme`, or use semantic `UIColor.label`/`.tertiaryLabel` instead of fixed black/lightGray.
- **Severity:** Medium

### 8.7 Raw non-semantic color for an icon-only close button
- **Location:** `Modules/SpaceRPG/Record/HelpPageView.swift:32`
- **What:** The close button's `xmark.circle.fill` uses `.foregroundStyle(Color(white: 0.7, opacity: 0.5))` while the sibling "Capture Help" text in the same `HStack` correctly uses `.foregroundStyle(.secondary)`.
- **Why:** A raw gray/opacity literal doesn't track dark mode, increased contrast, or tint customization.
- **Action:** Replace with `.foregroundStyle(.secondary)` (or `.tertiary`).
- **Severity:** Low

### 8.8 `UIDevice.current.userInterfaceIdiom == .pad` duplicated 6× across 3 files instead of size classes
- **Location:** `Modules/SpaceRPG/Record/CaptureOverlayView.swift:46`, `OnboardingCreateButton.swift:55`, `OnboardingTutorialView.swift:73-74,104` (6 occurrences total)
- **What:** The same UIKit idiom check is repeated 6 times to branch layout/video-asset choice, even though `CaptureOverlayView` already separately reads `@Environment(\.horizontalSizeClass)` one line away for a related layout decision.
- **Why:** Violates "avoid UIKit unless requested"; two different "is this iPad-ish" mechanisms in the same view will drift — e.g. Split View/Stage Manager on a compact-width iPad is `.pad` idiom but not `.regular` size class.
- **Action:** Consolidate on `@Environment(\.horizontalSizeClass)` and drop the `UIDevice` checks, or centralize the idiom check in one shared computed property if UIKit is genuinely required for the video-asset naming.
- **Severity:** Medium

### 8.9 Two independent tutorial-video-name resolution systems
- **Location:** `Modules/SpaceRPG/Record/AppDataModel+Orbit.swift:52-65` (`Orbit.feedbackVideoName(for:isObjectFlippable:)`) vs `OnboardingTutorialView.swift:83-107` (dictionaries keyed by `OnboardingState` + a separate `UIDevice` check)
- **What:** Both resolve the same family of bundled video asset names (`ScanPasses-iPhone/iPad-FixedHeight-*`) for iPad vs iPhone via two unrelated mechanisms.
- **Why:** Easy for one to be updated (e.g. a renamed asset) without the other.
- **Action:** Consolidate into one video-name resolver keyed on a single state representation.
- **Severity:** Low

### 8.10 `AnyView` usage at a `View`-erasure protocol boundary
- **Location:** `Modules/SpaceRPG/Controller/ViewController.swift:15-16,19-20,23-24`
- **What:** `fileImporterView`/`rowViewer` wrap `InlineImporterView`/`InlineRowViewer` in `AnyView` before returning them — the only `AnyView` usage in the module.
- **Why:** Appears required to satisfy a shared cross-module `ViewControllable` protocol return type, not casual type-erasure — flagged for confirmation rather than as a clear defect.
- **Action:** Confirm whether the protocol return type could use `some View` instead; if the protocol boundary genuinely requires erasure, no action needed.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Unused code to delete outright
- `Modules/SpaceRPG/Record/CaptureOverlayView+Buttons.swift:44-48` — `VisualEffectView: UIViewRepresentable`, superseded by `.ultraThinMaterial`, zero instantiations.
- `Modules/SpaceRPG/Record/CaptureFolderManager.swift:118-129` — `static func heicImageUrl(in:id:)`, no call sites.
- `Modules/SpaceRPG/Intent/SpaceEntity+Image.swift:14-18` — `thumbnailRepresentationData`, no call sites (only `imageRepresentationData` is used).
- `Modules/SpaceRPG/Intent/SpaceEntity.swift:10` — `import PDFKit`, no PDFKit symbol referenced anywhere in the file (copy-adapted from PdfRPG's equivalent).
- **Severity:** Low (each is isolated, zero-risk to remove)

### 9.2 `CaptureFolderManager.shots`/`loadShots()` — dead snapshot-gallery feature
- **Location:** `Modules/SpaceRPG/Record/CaptureFolderManager.swift:31` (`shots` property), `:57-81` (`loadShots()`)
- **What:** Populates `shots: [ShotFileInfo]` by scanning the images folder, but nothing in the module calls `loadShots()` or reads `shots`; `CaptureFilesButton` instead opens a raw `DocumentBrowser` over the whole scan folder.
- **Why:** Dead disk-scanning code inherited from Apple's sample that also duplicates (worse: synchronously, on the main actor) the logic in `ProgressBarView.numOfImages` (§7.1).
- **Action:** Either wire it up to feed `ProgressBarView.numOfImages` (recommended, fixes §7.1 too), or delete `shots`/`loadShots()` and `ShotFileInfo.swift` if a shot-review gallery is intentionally out of scope.
- **Severity:** Medium

### 9.3 `SpaceShortcutCatalog`'s App Shortcuts implemented but never registered
- **Location:** `Modules/SpaceRPG/Intent/SpaceShortcutCatalog.swift:10-75` (`all`, `open`, `create`, `addNote`, `search`, `delete`)
- **What:** A full `[AppShortcut]` catalog with Siri phrases is defined, but `Sources/MasterRPG/MasterRPGShortcuts.swift` (the app's actual `AppShortcutsProvider`) only imports `AdventureRPG` and `DiceRPG` and hand-declares those inline — it never imports `SpaceRPG` or references this catalog. Only `SpaceShortcutCatalog.reindexAll(root:)` is used (from the Spotlight indexer).
- **Why:** This is exactly what the build log's "No AppShortcuts found — Skipping" for the SpaceRPG framework means: none of the Siri phrases or the Shortcuts-app tile for 3D Objects are ever surfaced, even though the underlying `AppIntent`s are fully implemented and reachable manually via the Shortcuts editor. Note: this is a systemic, repo-wide gap (11 other modules have an identical unused `*ShortcutCatalog.swift`), not SpaceRPG-specific, and it's a missing integration rather than a crash/data-loss/security issue — scored below Critical accordingly.
- **Action:** Add `import SpaceRPG` to `MasterRPGShortcuts.swift` and splice `SpaceShortcutCatalog.all` into its `appShortcuts` body, matching the other modules' inline style (or refactor to aggregate every module's catalog generically, as a repo-wide fix).
- **Severity:** High

### 9.4 `SpaceViewer.swift` (1086 lines) — split proposal
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift` (whole file)
- **What:** One file holds the visionOS SharePlay transform-sync engine (194-364), window→immersive handoff (366-462), entity loading/gesture wiring (464-812), and 4 extracted subviews (814-1086), all delimited by existing `// MARK:` comments.
- **Why:** At 1086 lines it's the largest file in the module by 2.3× (next is `AppDataModel.swift` at 470); the four concerns are already independently comprehensible, making this a low-risk split.
- **Action:** Extract into `SpaceViewer+SharePlaySync.swift`, `SpaceViewer+Handoff.swift`, `SpaceViewer+EntityLoading.swift`, and `SpaceViewer+Subviews.swift`, leaving the `struct SpaceViewer` declaration and `body` (1-192) in the main file.
- **Severity:** Medium

### 9.5 `AppDataModel.swift` — further split along an existing convention
- **Location:** `Modules/SpaceRPG/Record/AppDataModel.swift` (whole file)
- **What:** `AppDataModel+Orbit.swift`/`+State.swift` already carve out enums, but the file still carries capture-session lifecycle (239-332), the state-transition table (`performStateTransition`, 373-416 — the most-frequently-touched chunk), and an unrelated `LocString` localization enum (437-468).
- **Why:** The existing `+Orbit`/`+State` convention shows the team already intends to decompose this type, but the largest, most state-machine-relevant piece was left in the main file.
- **Action:** Extract `performStateTransition`/`onStateChanged`/`switchToErrorState`/`reset` into `AppDataModel+Transitions.swift`, and `LocString` into `AppDataModel+LocalizedString.swift` (matching the naming convention used elsewhere in `Record/`; see also §4.4/§4.5 for the `LocString` renaming/reorganization).
- **Severity:** Low

### 9.6 Magic literal `2` instead of the module's own named `DisplayStateMask`
- **Location:** `Modules/SpaceRPG/Controller/LinkController.swift:48` (`inspectedItem.displayState != 2`) vs `Modules/SpaceRPG/Root/SpaceRootModel.swift:204` (`model.displayState == DisplayStateMask.totalHidden.rawValue`) in the same module
- **What:** `LinkController.swift` compares against the raw literal `2`, while `SpaceRootModel.swift` in the same module correctly spells the identical check via `DisplayStateMask.totalHidden`.
- **Why:** Internal inconsistency within SpaceRPG itself. (Repo-wide grep shows the literal-`2` form is the dominant pattern across ~20 other modules' `LinkController`/`ExportController`/`EditController` files — a systemic issue, flagged here only for the SpaceRPG instance.)
- **Action:** Replace `!= 2` with `!isHidden` or `!= DisplayStateMask.totalHidden.rawValue`.
- **Severity:** Low

### 9.7 `SpaceHandoffModel.swift` filed outside `Model/`
- **Location:** `Modules/SpaceRPG/Space/SpaceHandoffModel.swift` (whole file)
- **What:** An `@Observable @MainActor` state model, but filed under `Space/` alongside RealityKit view code rather than `Model/`, where `SpaceModel.swift`/`SpaceEntryModel.swift`/`SpaceTransformModel.swift`/`SpaceSnapshot.swift` live.
- **Why:** Minor deviation from the documented folder convention — may be intentional given it holds a live RealityKit `Entity` (not Codable/persisted like the other `Model/` types), so this is a judgment call.
- **Action:** Consider moving to `Model/` for consistency, or leave as-is if "tightly coupled to one View, not persisted" is a valid reason to co-locate.
- **Severity:** Low

### 9.8 Ad-hoc magic constants
- **Location:** `Modules/SpaceRPG/Space/SpaceViewer.swift:382` (`> 0.15` handoff threshold), `:640-648` (`targetSize: Float = isImmersiveSpace ? 1.0 : 0.5`, `maxBase > 0.0001`), `:912-941` (repeated `0.1`, `.pi/6`, `.pi/12` accessibility rotate/move steps) — inconsistent with the same file's own precedent of naming comparable values (`transformBroadcastThrottle`, `remoteTransformEaseDuration`, lines 292-301); `Modules/SpaceRPG/Record/AppDataModel.swift:168` (`Task.sleep(for: .milliseconds(500))` camera-teardown delay, extensively commented as a precisely-tuned value but still a bare literal)
- **What:** Tuned thresholds/step sizes and one specifically-fragile delay are bare literals despite the surrounding files already extracting comparable values into named constants.
- **Why:** A reader can't tell whether these are load-bearing tuned values (they are, per the comments) or incidental; the 500ms delay in particular risks being silently changed by an unrelated edit, reintroducing the camera-teardown race its comment describes.
- **Action:** Promote each to a named `private static let` alongside the existing ones in `SpaceViewer.swift`, and extract `AppDataModel.swift:168`'s delay to `private static let cameraTeardownDelay: Duration = .milliseconds(500)`.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Consolidate on `Scanner3DRootView.swift:75`'s safe `if let folderManager = ...` pattern everywhere `scanFolderManager` is touched**, rather than force-unwrapping. This single change would close §3.1 and the `CaptureFilesButton.swift:38` site together.
2. **Adopt a single reconstruction-failure path.** §5.1, §5.2, and §3.3 are three independent places in the same pipeline (`AppDataModel.performStateTransition`, `ReconstructionProgressView.process`, `UntilProcessingCompleteFilter`) where a thrown/swallowed error fails to reach `switchToErrorState`. A single "any reconstruction-path error routes through `switchToErrorState`" convention, enforced once, would fix all three at the root.
3. **This module still carries several Apple-sample carryovers that never got fully adapted** to this project's conventions: `NSLocalizedString` (§4.1), `Combine` imports (§4.3), `View.if()` duplicating `applyIf` (§8.9), and the unused `shots`/`loadShots()` gallery plumbing (§9.2). Treating "finish adapting the Guided Capture sample" as one pass would resolve all of these together rather than piecemeal.
4. **The `SpaceShortcutCatalog` gap (§9.3) is repo-wide**, not SpaceRPG-specific — worth a follow-up audit item at the `Sources/MasterRPG/MasterRPGShortcuts.swift` level covering all 12 modules' catalogs, rather than fixing SpaceRPG's alone.
5. **`SpaceViewer.swift`'s existing subview-extraction pattern (§8.4) and `Equatable`/`.equatable()` pattern (§7.4) are both already proven out elsewhere in this module** (`InlineImporterView`, `InlineRowViewer`, `SpaceViewer`'s own subviews) — apply them consistently to the remaining hot views rather than introducing a new approach.

---

## 11. What was NOT audited

- Every other module in the repo (`AdventureRPG`, `AudioRPG`, `CharacterRPG`, `CoreRPG`, `DiceRPG`, `GameRPG`, `GeneratorRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `RuleRPG`, `TableRPG`, `WeatherRPG`, `RolePlayGameKit`) — out of scope by request. Several findings above note where a SpaceRPG-local issue is actually a repo-wide pattern (§8.9's `applyIf`, §9.3's `ShortcutCatalog`, §9.6's magic `2`); those are flagged for awareness, not fixed here.
- Algorithmic correctness of the RealityKit/PhotogrammetrySession pipeline itself (mesh reconstruction quality, texture baking) — Apple framework internals, treated as a black box.
- `Modules/SpaceRPG/Resources/Model.xcdatamodeld/RPGSpace.xcdatamodel` — Core Data schema structure was not opened; only source-level `SpaceModel`/`SpaceEntryModel` mapping code was reviewed.
- `Tests/SpaceRPGTests/` — used only for cross-reference (checking whether types are exercised), not a coverage or quality review.
- Localization wording/translation correctness in the String Catalogs — only API modernity (`NSLocalizedString` vs `String(localized:)`) was assessed.
- Build settings, scheme configuration, and the rest of `MasterRPG.xcodeproj/project.pbxproj` beyond the specific target-dependency lookups cited in §8.10 and §9.3.
- `Modules/SpaceRPG/Resources/Scan/*.mp4` tutorial video asset content/quality.
- Third-party/system framework internals (RealityKit, PhotogrammetrySession, AVFoundation, CoreSpotlight) — treated as black boxes; only this module's usage of them was reviewed.
- Instruments-based performance profiling — findings in §7 are static-analysis observations (blocking calls, per-init allocation), not measured hitches.
- macOS/visionOS-specific manual QA (RealityView rendering, SharePlay multi-device sync behavior) — reviewed at the source level only, not run on-device.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line.

- **§5.1** — open `Modules/SpaceRPG/Record/AppDataModel.swift`, lines 387-394. Confirm the `catch` block only logs and does not call `switchToErrorState` or change `state`; cross-check `Scanner3DRootView.swift` lines 33-35 (`showProgressView`) and 64-71 (`onChange`) show no branch for `.prepareToReconstruct`.
- **§5.2** — open `Modules/SpaceRPG/Record/ReconstructionProgressView.swift`, lines 91-99. Confirm the `catch` only logs and execution falls through into the `for await` loop unconditionally.
- **§5.6** — open `Modules/SpaceRPG/View/InlineImporterView.swift`, lines 96-101 and 106-119. Read the code comment's claim against `InlineImporterContentView.init`'s `State(wrappedValue: preopen)` and confirm no `.id()` modifier exists at the call site (lines 86-94) to force identity reset.
- **§6.1** — open `Resources/Info.plist`, lines 116-117, confirm `UIFileSharingEnabled` is `true`; then `Modules/SpaceRPG/Record/CaptureFolderManager.swift`, lines 204-207, confirm the folder is under `URL.documentsDirectory`.
- **§8.1** — open `Modules/SpaceRPG/Record/OnboardingButtonView.swift`, lines 122-130, and compare against `CoreRPG`'s `IfModifier.swift` `applyIf` definition; then grep `Modules/SpaceRPG/Space/SpaceViewer.swift` for `.applyIf(` (lines 145, 1006) to confirm the module already uses the shared helper elsewhere.
- **§8.2** — open `Modules/SpaceRPG/Space/SpaceViewer.swift` line 7 (`#if !os(tvOS)`) and its matching `#endif` at end of file; then `MasterRPG.xcodeproj/project.pbxproj` line 3465 (dependency id in `MasterTV`'s `dependencies` list) and line 5932 (that id's `target = ... /* SpaceRPG */`).
- **§9.3** — open `Modules/SpaceRPG/Intent/SpaceShortcutCatalog.swift` lines 10-75, then `Sources/MasterRPG/MasterRPGShortcuts.swift` and confirm no `import SpaceRPG` or reference to `SpaceShortcutCatalog` exists.

If any finding doesn't reproduce when you visit the line, ping me with the specific reference and I'll re-investigate.
