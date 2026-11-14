# RolePlayGameKit audit (2026-11-14)

Read in full: every file in Model/, Route/, InApp/, Intent/, View/ (about 3.6k LOC), plus Import/Foundry/FoundryRuleImportModel, FoundryMediaNormalizer, FoundryVTTDomainMapper (+Assets, +Scenes, +DiceAndValues, +SharedHelpers, parts of +Documents/+Indexes), UniversalVTTDomainMapper, FoundryImportView and FoundryImportCommitProgressView (of 10,258 LOC total; +Rules and the second half of +Documents were skimmed only). The module is in good shape: no force unwraps/`try!`/GCD/`ObservableObject`/`AnyView`/`onTapGesture`/1-parameter `onChange` anywhere, `Tab` API and `ManagedNavigationStack` are used consistently, window-lock handling in Validate/Import/Example data is careful, and the Foundry mapper bounds all geometry. The real findings are one silent asset-drop bug in the Foundry path mapper, an unprotected Reset Data, a probably unreachable visionOS chain, unlocalized Foundry UI strings, and several small SwiftUI-style and dead-code items. No Critical or High finding survived verification.

### Foundry mapper truncates resource paths at `#` and `?` and silently drops colliding assets
- Category: Bug
- Location: Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+SharedHelpers.swift:212-220 (`canonicalResourcePath`); used by +Indexes.swift:27, +Assets.swift:32-34 (`createAsset` key and `stableID("asset#...")`), +Assets.swift:147
- What: `canonicalResourcePath` percent-decodes first and then cuts at `?` and `#`, and it is also applied to the package's own `logicalPath` (a zip entry path, not a URL). `FoundryMediaNormalizer.canonicalPath` was fixed for exactly this in CODE_AUDIT_21 §5.28 (cut first, decode second), but this sibling function was not, and the fix has a test only for the normalizer (`FoundryMediaNormalizerTests.swift:17`).
- Why: packaged files `tokens/Token #1.webp` and `tokens/Token #2.webp` both canonicalise to `tokens/Token`. `createAsset` keys `resourceIDs` and the stable asset id on that string, so the second file returns the first file's id and is never imported (`if let existing = resourceIDs[key] { return existing }`), with no warning; the index step reports them only as an "ambiguous path" for lookups. Every reference to the second token then points at the first image. Names with `#` or `?` are common in VTT token packs.
- Action: stop stripping query/fragment from `logicalPath` (strip only from references found inside documents, and cut before decoding as the normalizer does); make `createAsset` warn when two distinct resources collide; add a mapper-level test with `#` and `?` file names.
- Severity: Medium
- Status: NEW (incomplete fix of CODE_AUDIT_21 §5.28)

### Reset Data takes no data-mutation lock and its alert overstates what is deleted
- Category: Bug
- Location: Modules/RolePlayGameKit/View/SettingsView.swift:196-211; Modules/RolePlayGameKit/Model/AppModel.swift:318-320; Modules/AdventureRPG/Root/AdventureRootModel.swift:277-284; Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:44-80
- What: `AppModel.resetData()` runs `adventureRoot.resetData()` without `beginExclusiveDataMutation()` / `beginSaveDeferral()` (import, Validate/Repair and the example-data install all take both, see `DataMutationCoordinator` doc), and the alert says "all files in local and appCloud storage ... are removed" while `ItemControllable.resetData` only clears caches and bookmarks and batch-deletes rows (its own comment: "Will not remove files on reset Database").
- Why: Reset can be tapped while an import or Validate sheet is mid-run and interleaves a batch delete with that bulk writer's in-memory graph and its final save; the confirmation text promises a file deletion that does not happen (or the comment is stale). It is the app's most destructive action and gives no completion feedback.
- Action: take the exclusive-mutation token (show the busy message if refused) and defer saves around the reset; make alert text and behaviour agree; show a completion state.
- Severity: Medium
- Status: NEW

### visionOS editor chain (ExtendedSplitBar and four files) appears unreachable
- Category: Dead code
- Location: Modules/RolePlayGameKit/View/ExtendedSplitBar.swift (86 LOC), ExtendedSplitWithDetailView.swift (60), SecondaryTabBar.swift (56), SecondaryTabBarExtButton.swift (53), BarButtonWithHoverEffectStyle.swift (46); only entry point is Route/RouteDestinationView.swift:35-37
- What: `ExtendedSplitBar` is only built for `RootRoute.editors` on visionOS, but nothing sends `.editors` there: `RootRoute.visionTabs` (Route/RootRoute.swift:115) has no `.editors`, `visionGameWindowActions` (WindowRouter.swift:160-178) never emits it, and the visionOS editor window uses `SplitEditorNavigation` with `visionEditorTabs`. `BarButtonWithHoverEffectStyle` has a single user (the secondary button). Only a snapshot test touches it. Marked unverified at runtime: a restored `SceneStorage("GameRoute")` from an older version could still hold `editors`.
- Why: about 300 LOC of visionOS-only UI to maintain, and the chain already diverges from its siblings: `limitedTabs` omits Pdfs (a restored `selectedExtendedModule == .pdfs` would show a blank ZStack), every tab is mounted at once and hidden with opacity (ExtendedSplitBar.swift:58-68), the inspector ignores `canShowInspector` (ExtendedSplitWithDetailView.swift:40 vs SplitWithDetailView.swift:35-56), and `colorScheme`/`navigator` environments and `contentView(tab:)` (ExtendedSplitBar.swift:10-11,43-50) are unused.
- Action: confirm on a visionOS device that `.editors` is never selected, then delete the chain and its snapshot block (and the `.editors` case in the visionOS branch of `RouteDestinationView`); if it is kept, render only the selected tab and reuse the gated inspector binding.
- Severity: Medium
- Status: NEW

### Foundry/VTT import UI and error strings are not localized
- Category: API
- Location: Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift:37-54 (`FoundryImportCategory.title`, shown by `Text(category.title)` at FoundryImportView.swift:219); FoundryImportView.swift:631-657 (`FoundryArtifactKind.title`, `ExternalImportDecision.title` used in `Button(decision.title)` and `Text(decision.title)`); FoundryRuleImportModel.swift:159,204,221,273,300,309,314,410 (`LoadState.failed(String)`, `commitError`, archive warnings); FoundryMediaNormalizer.swift:59-74 (`errorDescription`); all mapper `warnings` (e.g. FoundryVTTDomainMapper.swift:306-311, +DiceAndValues.swift:31-67, +Assets.swift:53)
- What: these are plain `String` literals passed to `Text(_:)`/`Button(_:)` string overloads (verbatim) or to `LocalizedError`; none appears in `Resources/Localizable.xcstrings` (grep for "Actors and characters", "Roll formula", "Another external import" finds nothing).
- Why: German and Thai users see English category names, the Skip/Merge/Replace decision picker, failure screens, and the whole warnings list on the review screen. CODE_AUDIT_21 §9.7 localized the CoreRPG import errors but not this module's.
- Action: use `String(localized:bundle: .module)` / `LocalizedStringResource` for titles and user-visible errors; for the dynamic mapper warnings introduce a small warning enum with localized formatting, or at least localize the fixed ones.
- Severity: Medium
- Status: NEW

### Foundry mapper compiles regular expressions per call
- Category: Performance
- Location: Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+SharedHelpers.swift:289-327 (`rewriteFoundryLinks`, called from `safeText`/`decodedFoundryText` for every description, entry and name), :405-419 (`simpleModifier`, builds an `NSRegularExpression` plus a Regex literal); FoundryVTTDomainMapper+DiceAndValues.swift:27-36 (two `NSRegularExpression`s per formula)
- What: each call rebuilds a link-type alternation pattern and parses it again.
- Why: a system or world package maps tens of thousands of strings on the main actor (the mapper is `@MainActor`, see the comment at FoundryVTTDomainMapper.swift:263-269); regex compilation dominates `rewriteFoundryLinks` even for strings that contain no `@`. CODE_AUDIT_25 §7.1 fixed the same pattern in `Calculator`.
- Action: hoist the expressions into static lets; return early in `rewriteFoundryLinks` when the text contains no `@`.
- Severity: Medium
- Status: NEW

### No tests for app-level routing, window routing, database setup, or Validate/Repair locking
- Category: Test gap
- Location: Modules/RolePlayGameKit/Model/AppModel+Routing.swift:84-99 (external-route dedupe), :189-209 (layout restore); Route/WindowRouter.swift (per-role action lists, including recursion between `forwardToOtherWindow` and `routeToModule`); Model/DataBaseModel.swift:117-160; View/ValidateRepairView.swift:44-66; Route/RootURLHandler.swift
- What: the only RolePlayGameKit-named tests cover InAppController, the Foundry mapper and snapshots (grep of Tests/ for `WindowRouter`, `routeToModule`, `admitsExternalRoute`, `DataBaseModel`, `ValidateRepairController` finds nothing).
- Why: these are the most regression-prone cross-platform branches (macOS/visionOS/iOS conditionals, buffered routes, the error state that is never reset); regressions in this area have repeatedly shipped (CODE_AUDIT_18 §3.17, Since_3.0.1 §5.16).
- Action: add pure tests for `WindowRouter.actions(for:)` per role/platform, `admitsExternalRoute`, `DataBaseModel` error/recovery transitions with an injected persistence stub, and `startWithExclusiveDataAccess` refusing while the coordinator is held.
- Severity: Medium
- Status: NEW

### Database error state is never cleared and `canRecover` is dead
- Category: Bug
- Location: Modules/RolePlayGameKit/Model/DataBaseModel.swift:62-64,117-160 (`canRecover` set at :147, read nowhere in Modules/ or Sources/)
- What: `finishSetup()` sets `hasError`, `errorMessage` and `canRecover` on failure; the `.none` branch never resets them.
- Why: after `deleteDatabase()` succeeds, `hasError` stays true (the init screen only disappears because the route flips to `.ready`); a later non-migration failure keeps a stale `canRecover == true`. Any second window reading `hasError` shows the error screen over a healthy database.
- Action: reset the three fields at the top of `finishSetup()`; delete `canRecover` or use it to hide the Delete button for unrecoverable errors.
- Severity: Low
- Status: NEW

### First-launch example-data install failure has no retry
- Category: Bug
- Location: Modules/RolePlayGameKit/View/DestinationReadyView.swift:72-86
- What: `firstLaunch = false` is written before `installExampleData` runs; on failure (for example another import holds the lock, or the bundle file is missing) the user only sees the failure alert, and the first-launch prompt never returns. Settings has no "install example data" entry.
- Why: a first-time user whose install fails starts with an empty app and no obvious way to get the example data.
- Action: set `firstLaunch = false` only after success (or expose "Install example data" in Settings).
- Severity: Low
- Status: NEW

### Launch cleanup deletes hidden items without the data-mutation lock
- Category: Bug
- Location: Modules/RolePlayGameKit/View/DestinationReadyView.swift:39-52; Modules/RolePlayGameKit/Model/AppModel.swift:327-333; Modules/CoreRPG/Controllable/ItemRootControllable.swift:55-62
- What: five seconds after the ready view appears, `cleanDatabase()` runs `itemDataCleanup()` (deletes every `isHidden` item in all modules) and `removeLeftoverGameFiles()` for every module without `beginExclusiveDataMutation()`; the task restarts each time the view re-appears (macOS opens it in more than one window, and `initialRouteType` toggles on CloudKit switch).
- Why: a bulk delete that runs concurrently with a user's import, Validate run, or a game started within those seconds; every other bulk writer is excluded by the coordinator. Not reproduced, so the race is plausible rather than proven.
- Action: take the coordinator token (skip the pass when busy or when a game is running) and run it once per launch, not per view appearance.
- Severity: Low
- Status: NEW

### Foundry import state is lost when the user flips the Import segment
- Category: SwiftUI
- Location: Modules/RolePlayGameKit/View/AppImportView.swift:48-72; Import/Foundry/FoundryImportView.swift:13-16,87-90
- What: `FoundryImportView` owns its `FoundryImportModel` in `@State` and sits inside a `switch`; selecting the MasterRPG segment destroys it, and `onDisappear` cancels the preparation task.
- Why: a prepared review (potentially minutes of mapping) is thrown away by one tap, and the pending-URL handoff has already been consumed (`appModel.pendingVTTImportURL = nil`), so the user must pick the file again.
- Action: keep both sections mounted (opacity/`allowsHitTesting`) or hoist the model into `AppImportView`; at minimum disable the picker outside `.notStarted`/`.preflight`.
- Severity: Low
- Status: NEW

### Views built by private methods instead of View structs; one dispatcher computed property
- Category: SwiftUI
- Location: Modules/RolePlayGameKit/View/SplitNavigation.swift:170-201 (`pageTab`, `tabView`, `contentView`, `splitWithDetail`); View/TabSidebar.swift:76-82; View/ExtendedTabBar.swift:97-106; View/ExtendedSplitBar.swift:76-83; Route/ExtendedTabRouteDestinationView.swift:34-72 (`@ViewBuilder private var content`); View/SecondaryTabBarExtButton.swift:31-37
- What: CLAUDE.md says not to break views up with computed properties; these are the method/property variants.
- Why: style-rule violation; they also hide identity boundaries.
- Action: extract small `View` structs (leave `pageTab`, which returns `TabContent`).
- Severity: Low
- Status: NEW

### Dead members and unused environment reads in navigation views
- Category: Dead code
- Location: View/SplitNavigation.swift:52-54, View/SplitVisionNavigation.swift:79-81, View/SplitEditorNavigation.swift:96-98 (`selectedModule` computed properties with no reader); View/ExtendedTabBar.swift:10 (`colorScheme` unused); View/ExtendedSplitBar.swift:10-11,43-50
- What: unreferenced computed properties, methods and `@Environment` reads (grep inside the module and Sources/).
- Why: each unused `@Environment(\.colorScheme)` still subscribes the bar to theme changes.
- Action: delete.
- Severity: Low
- Status: NEW

### Editor window tab selection is not restored
- Category: Bug
- Location: Modules/RolePlayGameKit/View/SplitEditorNavigation.swift:8,28-35
- What: `storedTab` is a plain `@State` (default `.pdfs`) feeding `syncOptionalState`, while the Game-window siblings use `@SceneStorage`.
- Why: the macOS/visionOS editor window reopens on the default module after relaunch, and the `@State` write-back does nothing useful.
- Action: use a `@SceneStorage` with an editor-specific key, or drop the sync if restoration is intentionally off.
- Severity: Low
- Status: NEW

### Persisted sidebar customization ID has a typo
- Category: Bug
- Location: Modules/RolePlayGameKit/View/SplitNavigation.swift:125
- What: `.customizationID("Tab.Libaray")` while the other sections are spelled correctly.
- Why: the string is written into the `MasterRPGCustomization` AppStorage; renaming it later resets that section's saved visibility, so it only gets costlier to fix.
- Action: fix once and accept the one-time reset, or document it as frozen.
- Severity: Low
- Status: NEW

### `inertCodeBlock` computes a meaningless fence length; dice formulas have no total cap
- Category: Bug
- Location: Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper+SharedHelpers.swift:349-361; FoundryVTTDomainMapper+DiceAndValues.swift:38-60
- What: `longestBacktickRun` is built with `reduce(0) { longest, _ in max(longest, 1) }`, which yields 0 or 1, never the real run length; the following `while source.contains(fence)` loop is what makes the result correct. Separately, the dice limit is 100 per term, but a formula with many terms (`100d6+100d6+...`, only a few KB) builds an unbounded `[DieModel]`.
- Why: the first is misleading dead logic in a security-relevant helper (macro text must not escape its fence); the second lets a crafted world file allocate tens of thousands of dice.
- Action: delete the reduce and start from 4; cap the total dice count per formula (for example 100) and keep the formula as text beyond it.
- Severity: Low
- Status: NEW

### License-document detection matches the substring "ogl"
- Category: Bug
- Location: Modules/RolePlayGameKit/Import/Foundry/FoundryRuleImportModel.swift:448-454
- What: `path.localizedStandardContains("ogl")` marks any text resource whose path contains "ogl" (Catalog, Dialog, Goblin, Dialogue...) as a license document.
- Why: unrelated package files are shown as "Safety and licensing" disclosure groups with their full text in the preflight list.
- Action: match file stems (`license`, `licence`, `copying`, `ogl`, `notice`) as whole words on the last path component.
- Severity: Low
- Status: NEW

### Unverified purchase result is not finished
- Category: Bug
- Location: Modules/RolePlayGameKit/InApp/InAppModel.swift:157-158
- What: `handlePurchaseResult` shows "could not be verified" for `.success(.unverified)` but does not call `finish()` on the transaction, unlike the `Transaction.updates` path (:102-109, CODE_AUDIT_22 §6.5).
- Why: the unfinished transaction is redelivered at every launch until `updates` finishes it.
- Action: finish the unverified transaction in this branch too.
- Severity: Low
- Status: NEW

### Navigate/Search intents route immediately instead of when ready
- Category: Bug
- Location: Modules/RolePlayGameKit/Intent/NavigateIntent.swift:31-33; Intent/SearchInAppIntent.swift:29-33 vs Model/AppModel+Routing.swift:70-82
- What: both call `routeToModule` directly, bypassing `routeToModuleWhenReady`, which defers until `initialRouteType == .ready` and de-duplicates.
- Why: on a cold foreground launch the window may be opened before the scene registered its actions (`ScenesManager.setActions` runs in `onAppear`); the navigator buffers the route, but window opening is lost on macOS/visionOS. Unverified at runtime.
- Action: use `routeToModuleWhenReady` in both intents.
- Severity: Low
- Status: NEW

### Style items: animated alert toggles, hard-coded spacing, tvOS placeholder wiring
- Category: SwiftUI
- Location: View/SettingsView.swift:146,161,188 (`withAnimation { flag.toggle() }` around alerts); View/DatabaseInitializationView.swift:20,79; View/ExtendedTabBar.swift:26; View/SplitVisionNavigation.swift:51,73; View/SplitEditorNavigation.swift:68,90 (literal spacing/padding); Model/AppModel.swift:48-52 (identical `#if os(tvOS)` and `#else` declarations), :244 (`generatorRoot: adventureRoot` on tvOS)
- What: CLAUDE.md says to avoid hard-coded padding/spacing; alert flags need no animation (and no reduce-motion check); the tvOS `RootManager` is fed the adventure root as its generator root.
- Why: minor; on tvOS any maintenance loop over `RootManager` visits the adventure root twice.
- Action: use default spacing and set flags directly; remove the pointless `#if`; give `RootManager` an optional generator root or use its dice-only initializer on tvOS.
- Severity: Low
- Status: NEW

Not audited in this area: the second half of Import/Foundry/FoundryVTTDomainMapper+Documents.swift (journals, tables, cards, adventures), FoundryVTTDomainMapper+Rules.swift and the folder-creation half of +Indexes.swift (skimmed by grep only: no force unwraps, no unchecked indexing); the Foundry reader/sanitizer types themselves live in CoreRPG; no runtime verification of any platform-specific path (macOS, visionOS, tvOS).
