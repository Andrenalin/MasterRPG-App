# MasterRPG Code Audit

Generated 2026-09-09. Scope: ~269,000 Swift LOC across ~2,032 files (0 Metal kernels), spanning the `MasterRPG`/`MasterMac`/`MasterTV`/`RPGShare`/`DiceRollerWidgetExtension` app targets and the 15 `Modules/*RPG` Swift Package modules (AdventureRPG, AudioRPG, CharacterRPG, CoreRPG, DiceRPG, GameRPG, GeneratorRPG, MapRPG, PdfRPG, PhotoRPG, RolePlayGameKit, RuleRPG, SpaceRPG, TableRPG, WeatherRPG). `.git/`, `.build/`, DerivedData, `Snapshots/` (image test fixtures), and `Docu/` (historical audit reports — reference only) are excluded. Test targets got a light scan, not a deep review.

This is round ~12 of a recurring audit process (`Docu/CODE_AUDIT_1.md` through `CODE_AUDIT_11.md`, plus several topic-specific reports, already exist and have driven 25+ fix commits). The codebase is consequently very disciplined: a clean `xcodebuild clean build` of the `MasterRPG` scheme produced **zero real Swift compiler warnings** (only two benign `appintentsmetadataprocessor` tooling notices for resource-only frameworks). Findings below are what survived that baseline, not restated prior-audit items — a few explicitly re-verify claims from `CODE_AUDIT_11.md` that turned out to be incomplete.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made. **§8 (SwiftUI/UI) is incomplete** — see the note there and in §11.

---

## 1. Executive summary

Top items to address, in priority order:

1. **[High] Always-true condition silently downgrades Decimal entries to Number** — §5.2 — `Modules/CharacterRPG/Controller/EditController.swift:184-186,199-203`. Linking Dice or a Value to any `.decimal` entry silently discards its decimal semantics on every use.
2. **[High] PlayerNetworkController never stops its Bonjour/Network browser** — §5.1 — `Modules/GameRPG/Player/PlayerNetworkController.swift:82-95`. Once a player opens "join game," Bonjour discovery keeps running (battery + network drain) for the rest of the app session, even after leaving/joining a game.
3. **[High] `Url`-suffix casing convention violated at 59 sites** — §9.1 — contradicts `CODE_AUDIT_11.md`'s explicit "0 remaining" close-out, including in foundational files like `AppGroup.swift`.
4. **[Medium] Unguarded recursion in `duplicateSubValue`** — §5.3 — `Modules/CharacterRPG/Controller/EditController.swift:338-362`. Every sibling graph-walk in this codebase has a cycle/depth guard; this one doesn't, so a cyclic value graph (e.g. from a pre-repair CloudKit merge) can stack-overflow instead of failing gracefully.
5. **[Medium] Remote (http/https) linked-file downloads have no size cap** — §6.1 — `Modules/CoreRPG/Files/FileUrlDataController.swift:555-634`. Every other ingestion path in the app enforces a byte-count ceiling; this one doesn't.
6. **[Medium] Microphone permission and audio-input entitlement declared but never implemented** — §6.2 — no `AVAudioRecorder`/`AVAudioEngine`/`SFSpeechRecognizer` usage anywhere in product code; App Review / user-trust risk for an unused sensitive permission.
7. **[Medium] `Id`-suffix casing still violated at 219 sites** — §9.2 — the prior audit's fix commit addressed roughly 40 of the ~258 sites it flagged.
8. **[Medium] `ObjectCache` actor performs blocking synchronous disk I/O on its own executor** — §3.2 — `Modules/CoreRPG/Cache/ObjectCache.swift:47-76`, serializing every concurrent cache read/write behind disk I/O despite an unused async alternative already existing in the same file.
9. **[Medium] PhotoRPG thumbnail generation decodes images on the Main Actor** — §7.1 — `Modules/PhotoRPG/Controller/CacheController.swift:76-88`, missing the `@concurrent` pattern its own sibling function already uses for exactly this class of bug.
10. **[Medium] `ScenesManager.swift` — 555 lines, 5 responsibilities, zero `MARK` dividers** — §9.12 — the one large file in the codebase without even the intermediate signposting step other oversized files already got.

---

## 2. Quick wins (≤30 min each)

- **Fix the tautology** — `Modules/CharacterRPG/Controller/EditController.swift:184,199`. Change `entry.type != .number || entry.type != .decimal` to `&&` at both sites (§5.2).
- **Stop the leaked browser** — `Modules/GameRPG/Player/PlayerNetworkController.swift:82-95`. Add `browserManager.stop()` to `stop()`, mirroring `MasterNetworkController.stopStreaming()` (§5.1).
- **Delete `AppToolBarAppearenceViewModifier.swift`** — confirmed zero call sites anywhere in the tree (§9.5).
- **Delete the dead `VisualEffectView`** — `Modules/SpaceRPG/Record/CaptureOverlayView+Buttons.swift:44-48`, superseded by `VisualEffectRoundedCorner` in the same file (§9.7).
- **Delete `SheetRowGeometryID`** — `Modules/CoreRPG/Sheet/SheetRootModel.swift:12-15`, zero remaining uses (§9.6).
- **Remove 7 stale commented-out modifier lines** — one-liners in `EditMapToolBar.swift`, `ToolbarItemListViewModifier.swift`, `ItemEditorForegroundView.swift`, `HeaderFooterContentScrollView.swift` (×2); decide whether the duplicated `.gameOverlayTabBarView` comment in `OnlyGameView.swift`/`OnlyPlayerGameView.swift` should come back or go (§9.8).

---

## 3. Concurrency

### 3.1 NSItemProvider continuation wrappers ignore task cancellation
- **Location:** `Modules/PhotoRPG/Controller/ItemController.swift:53-61` (`importImageFromProviders`), `Sources/RPGShare/ItemProviderImporter.swift:180-206` (`loadItem`)
- **What:** Both wrap `NSItemProvider.loadDataRepresentation(forTypeIdentifier:completionHandler:)` / `loadItem(forTypeIdentifier:completionHandler:)` in `withCheckedThrowingContinuation` with no `withTaskCancellationHandler`, discarding the `Progress` object these completion-handler APIs return specifically for cancellation.
- **Why:** If the enclosing `Task` is cancelled mid-load (e.g. user backs out of an import), the continuation isn't resumed early and the underlying `Progress` is never cancelled — the suspended task leaks until the (possibly slow, e.g. iCloud Photos) load completes on its own.
- **Action:** Wrap both in `withTaskCancellationHandler`, capturing the returned `Progress` and calling `.cancel()` in `onCancel`.
- **Severity:** Medium

### 3.2 ObjectCache actor performs blocking synchronous disk I/O on its own executor
- **Location:** `Modules/CoreRPG/Cache/ObjectCache.swift:47-76` (`removeFromDisk`, `loadImageFromDisk`, `saveImageToDisk`), called from `Modules/CoreRPG/Cache/ImageCacheController.swift:25-41`
- **What:** These actor-isolated methods call `FileManager.default.fileExists`/`removeItem`/`Data(contentsOf:)`/`data.write(to:)` synchronously, directly inside the actor's own isolated methods, even though an async `loadImageFromDiskAsync` alternative already exists in the same file but isn't used by this hot path.
- **Why:** `ObjectCache` is a shared, app-wide image cache actor; every synchronous disk read/write serializes behind its executor, blocking every other concurrent cache operation for the duration of disk I/O.
- **Action:** Route `removeFromDisk`/`loadImageFromDisk`/`saveImageToDisk` through the same off-actor pattern `loadImageFromDiskAsync` already uses.
- **Severity:** Medium

### 3.3 Dice widget-update task ignores cancellation, can leave a stale roll displayed
- **Location:** `Modules/DiceRPG/Controller/GameController.swift:600-619`
- **What:** `roll(die:for:)` calls `diceGameModel.diceUpdateWidgetTask?.cancel()` before assigning a new `Task.detached`, but `diceUpdateWidget(diceResult:)` never checks `Task.isCancelled`.
- **Why:** `.cancel()` only flips the flag; the "cancelled" task still runs to completion and writes its (now stale) `DiceConfiguration`/reloads the widget. Two rapid consecutive rolls race with no ordering guarantee, so the older roll's write can land after the newer one's, briefly showing an outdated result on the Home Screen/Lock Screen widget.
- **Action:** Check `Task.isCancelled` at the top of `diceUpdateWidget(diceResult:)` and bail out before writing.
- **Severity:** Low

### 3.4 GameJoinCodeModel performs synchronous Keychain I/O on the main actor at init
- **Location:** `Modules/GameRPG/Network/GameJoinCodeModel.swift:28-42` (both `init`s call `loadOrGenerate`/`loadLastUsedMasterJoinCode` directly), `:105-138` (both read/write the Keychain synchronously); contrast with `:140-152` (`write(_:forKey:to:)`, deliberately wrapped in `Task.detached` "so the write happens off the main actor rather than blocking it during a live UI edit").
- **What:** `GameJoinCodeModel` (a `@MainActor` class, constructed as a stored property of `GameRoot`) reads and — on first launch, or when migrating a legacy `UserDefaults` code — writes to the Keychain synchronously inside `init()`, on the main actor, unlike every other write path in the same file.
- **Why:** This is exactly the "blocking work on the main actor" pattern the join-code storage design otherwise avoids — the one place it doesn't apply is the common path (every game-mode entry, every first-run/migration) that runs on init.
- **Action:** Route the initial load/generate-and-store path through the same `Task.detached` pattern as `write(_:forKey:to:)`, or perform the initial Keychain access before construction.
- **Severity:** Low

---

## 4. API modernity

_No findings._ The audit explicitly checked for legacy `Formatter` subclasses (none found), dead `@available` guards below the iOS 26 deployment target (none — every gate targets a genuinely future OS version), lingering `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject` (only 2 non-test hits, both verified legitimate: a doc-comment code example, and a required wrapper around Apple's `GroupStateObserver` from GroupActivities, which has no `@Observable` equivalent), `DispatchQueue` usage (zero in product code), legacy locking primitives (zero — actors and `Synchronization.Mutex` throughout), and StoreKit (already StoreKit 2 / async). See §12 for the verification trail.

---

## 5. Bugs / logic errors

### 5.1 PlayerNetworkController never stops its Bonjour/Network browser
- **Location:** `Modules/GameRPG/Player/PlayerNetworkController.swift:82-95` (`stop()`); contrast with the correct pattern at `Modules/GameRPG/Master/MasterNetworkController.swift:107-128` (`resetConnections()`, which calls `browserManager?.stop()`); `browserManager.start()` triggered from `Modules/GameRPG/SetupViews/SearchProxyView.swift:60-61` and `Modules/GameRPG/SetupViews/BrowserView.swift:42`
- **What:** `PlayerNetworkController.stop()` tears down the connection controller and its tasks but never calls `browserManager.stop()`; `browserManager` is a `let` created once in `init` and started directly by the setup views. Verified: no call site anywhere in `Modules/GameRPG` calls `.stop()` on the player-side `browserManager`.
- **Why:** `GameNetworkController`/`PlayerNetworkController` are created once in `GameRoot.init()` and never recreated, so once a user opens the "join game" screen, the underlying Bonjour browser's unstructured tasks keep running for the rest of the app session — even after joining a game or calling `GameNetworkController.stopGame()` — continuously draining battery and sending discovery traffic. The Master side correctly stops and nils its own `browserManager`, confirming this is an asymmetric oversight, not intentional design.
- **Action:** Call `browserManager.stop()` from `PlayerNetworkController.stop()`, mirroring `MasterNetworkController.stopStreaming()`.
- **Severity:** High

### 5.2 Always-true condition silently downgrades Decimal entries to Number when linking Dice or Value
- **Location:** `Modules/CharacterRPG/Controller/EditController.swift:184-186` (Dice case), `:199-203` (Value case)
- **What:** `if entry.type != .number || entry.type != .decimal { entry.type = .number }` — since `entry.type` can never equal both `.number` and `.decimal` simultaneously, at least one side of the `||` is always true, so the body always runs. Verified by reading both sites directly.
- **Why:** Every time a user adds a Dice link or a Value link to an entry that currently holds `.decimal` (e.g. a fractional stat), its type is silently forced to `.number`, discarding the decimal semantics the surrounding code clearly intended to preserve (the check explicitly names both `.number` and `.decimal` as "already fine" cases). This is a real, easily reproducible data-integrity bug reachable through ordinary character-sheet editing.
- **Action:** Change `||` to `&&` (De Morgan) so the type is only overwritten when it is neither `.number` nor `.decimal`.
- **Severity:** High

### 5.3 Unguarded recursion when duplicating nested Value entries
- **Location:** `Modules/CharacterRPG/Controller/EditController.swift:338-362` (`duplicateSubValue`, recurses via `subValueIds.forEach { duplicateSubValue(id: $0, ...) }` with no visited-set or depth cap — verified by reading the function).
- **What:** Unlike every other place in this codebase that walks a value/group graph — `EditController.gameValueEntryUpdate` (same file, uses `RecursionLimits.maxValueLinkDepth`), `LinkController.calculate` (depth-limited), `CharacterRPG/Controller/GameController.gameEntryPath` (explicitly depth-limited per its own prior-audit comment), and `RuleEntryTree` (explicit cycle detection) — `duplicateSubValue` has no equivalent guard.
- **Why:** If a group/sub-value graph is ever cyclic (e.g. via a CloudKit merge landing before `repairCharacterContrains()` runs), duplicating that item recurses without bound and can crash with a stack overflow instead of failing gracefully.
- **Action:** Add the same visited-ID-set or `RecursionLimits.maxValueLinkDepth` guard this file already uses one function away.
- **Severity:** Medium

### 5.4 `.unsafelyUnwrapped` used for GameRoot's core controllers instead of a safer alternative
- **Location:** `Modules/GameRPG/Root/GameRootModel.swift:366-369` (`_viewController.unsafelyUnwrapped`), `:371-374` (`_logGameController.unsafelyUnwrapped`)
- **What:** `_viewController`/`_logGameController` are `Optional`-typed stored properties set exactly once at the end of `GameRoot.init()` (because each needs `self`), then exposed as non-optional via `.unsafelyUnwrapped`. Neither property is ever reassigned to `nil` anywhere in the file.
- **Why:** Safe today, but unlike a plain `!` (which always traps cleanly, in both Debug and Release), `.unsafelyUnwrapped` skips the nil-check in Release builds entirely — if a future change (a `reset()`, a test harness, a deinit path) ever sets either property back to `nil`, the result is silent undefined behavior in production instead of a diagnosable crash. These aren't per-frame accessors, so there's no measurable performance benefit being traded for that risk, and it runs against the project's own "avoid force unwraps unless unrecoverable" house rule.
- **Action:** Replace with a regular `!`, or restructure via a factory/two-phase-init helper that returns a fully non-optional `GameRoot`.
- **Severity:** Low

---

## 6. Security

### 6.1 Remote (http/https) file linking has no size cap
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:555-592` (`ensureRemoteCache`), `:627-634` (`downloadRemoteFile`, plain `URLSession.shared.download(from:)`); triggered from `createFileUrl(fileId:url:module:category:contentHash:)` at `:323-335`
- **What:** When a user links a remote URL as a file (Audio/PDF/Photo/Space "link by URL" flow), the bytes are downloaded with no `Content-Length`/byte-count cap and no explicit timeout override.
- **Why:** Every other ingestion path in this codebase (the hand-written Foundry ZIP reader, LevelDB table reader, `ExternalImport`'s attachment loader) enforces an explicit `FoundryImportLimits`/`expectedByteCount` ceiling before or while pulling bytes. This one path bypasses that discipline entirely, so a large or slow-to-respond host can make the app buffer an unbounded amount of data to disk/memory with no user-facing progress cap.
- **Action:** Enforce a maximum byte count (check `Content-Length` up front and/or cap bytes read while downloading), consistent with the size limits used everywhere else in the file-import pipeline.
- **Severity:** Medium

### 6.2 Microphone permission and audio-input entitlement declared but never implemented
- **Location:** `MasterRPG.xcodeproj/project.pbxproj:7359,7435,8986,9056` (`INFOPLIST_KEY_NSMicrophoneUsageDescription`); `Resources/MasterRPG-Debug.entitlements`, `MasterRPG-Release.entitlements`, `MasterRPG-Mac-Debug.entitlements`, `MasterRPG-Mac-Release.entitlements` (`com.apple.security.device.audio-input`)
- **What:** The app declares `NSMicrophoneUsageDescription` ("...to listen to your voice commands for the AI chat assistant") and the audio-input entitlement on iOS and macOS, but a repo-wide search found zero usages of `AVAudioRecorder`, `AVAudioEngine`, `AVAudioApplication`/`requestRecordPermission`, or `SFSpeechRecognizer` anywhere in product code — including in `GeneratorRPG`, the AI chat module the description references.
- **Why:** App Review can question — and users can be alarmed by — a privacy permission prompt/entitlement for a capability the app doesn't use; it's also unnecessary attack/audit surface. This also confirms `GeneratorRPG` makes no server calls and is genuinely on-device-only, so the microphone declaration reads as a stale leftover from a removed or not-yet-built voice-input feature.
- **Action:** Either remove `NSMicrophoneUsageDescription`/`com.apple.security.device.audio-input` until voice input actually ships, or confirm the feature exists elsewhere and wire in the missing permission-request code.
- **Severity:** Medium

---

## 7. Performance

### 7.1 PhotoRPG thumbnail generation decodes images directly on the Main Actor
- **Location:** `Modules/PhotoRPG/Controller/CacheController.swift:76-88` (`downsampledSource`, lines 79 & 82), `Modules/PhotoRPG/Root/PhotoRootModel.swift:203-223` (`fetchPhotoThumbnailSource`, lines 212 & 214)
- **What:** Both `@MainActor` functions call the synchronous, non-`async` `AKImage.downsampledThumbnail(from:maxPixelSize:)` (ImageIO decode) directly inline. Verified: `downsampledSource` is `@MainActor` and its two `data`-branch calls have no `await`.
- **Why:** This blocks the Main Actor for the ImageIO downsample's duration. The codebase's own sibling full-resolution path (`CacheController.decodedImage`) is explicitly marked `@concurrent` with a comment citing exactly this class of bug — this thumbnail path was evidently missed. Map backgrounds/character portraits can be several MB, so this can visibly hitch the UI during list scrolling or bulk thumbnail generation.
- **Action:** Route these two branches through the same off-main `@concurrent` pattern as `decodedImage`.
- **Severity:** Medium

### 7.2 InlineImporterView decodes full-resolution images on the Main Actor
- **Location:** `Modules/PhotoRPG/Photo/InlineImporterView.swift:176-184` (PhotosPicker `.onChange`), `:199-206` (macOS `.onDrop`)
- **What:** `Task { ...; await update(id: id, image: AKImage(data: data)) }` — since these `Task {}` literals are created inside SwiftUI view-modifier closures (an implicitly Main-Actor context), the un-downsampled `AKImage(data:)` full decode runs on the Main Actor once the `await` resumes.
- **Why:** A full-resolution photo from Photos, a Finder drag, or Image Playground can be several MB; decoding it inline on the Main Actor can cause a visible stall right when the user picks/drops a photo.
- **Action:** Decode off the Main Actor (the same `@concurrent` pattern as `CacheController.decodedImage`) before calling `update(id:image:)`.
- **Severity:** Medium

### 7.3 GameStatisticsController.summary() aggregates the entire dataset synchronously on the main actor
- **Location:** `Modules/GameRPG/Statistics/Controller/GameStatisticsController.swift:86-134` (`summary`, ~8 sequential O(n) passes: filter/map/sorted/`Dictionary(grouping:)`); called from `Modules/GameRPG/Statistics/Model/GameStatisticsModel.swift:183-214` (`reload()`) and `:299-314` (`reportAchievements()`)
- **What:** `GameStatisticsModel` is `@MainActor`; `reportAchievements()` fetches with `interval: nil` (full lifetime history) and `dateRange = .allTime`, then calls the plain, non-actor-isolated `summary(...)` directly, so the whole multi-pass aggregation runs synchronously on the main thread. `reportAchievements()` runs from `finishSession()` — i.e. every time a GM ends a game.
- **Why:** For a long-running campaign (the UI itself offers an "All Time" range), this can add up to a real, repeatable UI hitch at a natural interaction point (ending a session) — other comparable bulk work in this codebase (`RPGSharePlayController.encodedData`/`decodedMessage`) is deliberately marked `@concurrent` to avoid exactly this.
- **Action:** Move `summary(from:configuration:calendar:)` off the main actor (mark it `nonisolated`/`@concurrent`, or wrap the call in `Task.detached`), matching the existing pattern for comparable bulk work.
- **Severity:** Medium

---

## 8. SwiftUI / UI

**Incomplete this round.** The dedicated `swiftui-expert-skill` pass over `Views/` and shared UI helpers was launched (fanning out across the 15 modules' view layers plus `CoreRPG`'s shared UI) but every sub-pass failed mid-run with an HTTP 429 (the Claude Code account's monthly spend/rate limit) before returning findings. A single manual spot-check of `Modules/MapRPG/Map/MapPinView.swift` (a 622-line, previously-flagged-as-unMARKed file) found no issues — pin interaction state is already routed through a dedicated `@MainActor @Observable` node class rather than raw view-local state, which is the pattern this pass would have been checking for.

**Action:** Re-run the `swiftui-expert-skill` pass (scoped per module, to keep each run small enough to survive) once the account's usage limit resets, then fold its findings into this section. See §11.

---

## 9. Dead code / duplication / refactor

### 9.1 `Url`-suffix casing convention violated at 59 sites — contradicts prior audit's "0 remaining" close-out
- **Location:** `Modules/CoreRPG/App/AppGroup.swift:38,49` (`groupURL`, `cloudURL` — verified directly), `Modules/CoreRPG/Cache/ObjectCache.swift:80,84,89`, `Modules/RolePlayGameKit/Model/AppModel.swift:45,54,57`, `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift:235`, `Modules/CoreRPG/Foundry/FoundryImportArchive.swift:117,144,208`, and 47 more sites across 26 files.
- **What:** CLAUDE.md mandates `Url` casing (`fileUrl`, not `fileURL`); `CODE_AUDIT_11.md` §9.11 stated the equivalent violation was "fully fixed repo-wide ... (0 remaining)" — a fresh `\b(var|let|func)\s+\w*URL\b` sweep finds 59 live violations today (count independently reproduced), including in foundational files like `AppGroup.swift` that define the app's iCloud/App-Group container paths.
- **Why:** Either this was never actually 0 (the prior verification pass used too narrow a pattern) or it regressed since; either way the documented convention is violated at meaningfully larger scale than the last report believed.
- **Action:** Re-run a comprehensive sweep, fix the plain-Swift-property subset first (low-risk), and treat Foundry/Codable wire-adjacent properties as a separate, careful pass (renaming a `CodingKeys`-backed property is safe; renaming the wire key itself is not).
- **Severity:** High

### 9.2 `Id`-suffix casing still violated at 219 sites
- **Location:** `Modules/GameRPG/Model/GameMessagePipeline.swift:60-65` (`messageID` beside correctly-cased `senderId`), `Modules/GameRPG/Model/GameNetworkModel.swift:109,112` (`messageID`/`replyToMessageID`, wire-format fields with a hand-written `CodingKeys` at `:177-197`), `Modules/GameRPG/Controller/MasterController.swift:147-148,366`, `Modules/CoreRPG/Import/ExternalImport.swift:29,79,137,143,313`, `Modules/CoreRPG/AppModels/AppSettingsModel.swift:74,214`, plus 100 more sites concentrated in `Modules/RolePlayGameKit/Import/Foundry/*`.
- **What:** 219 `var`/`let`/`func` declarations still end in `ID` (119 outside the Foundry-import tree, 100 inside it), down from `CODE_AUDIT_11.md`'s ~258 — commit `726451fd` ("fixed: ID to Id for many caller sites") addressed only a partial subset despite touching 35 files.
- **Why:** Style/consistency debt that compounds; the highest-value/highest-risk remainder sits in `GameNetworkModel`/`GameMessagePipeline` (the wire-protocol layer this project has repeatedly had sync bugs in), where a careless rename without checking each type's `Codable` story could silently change JSON keys.
- **Action:** Continue the low-risk-first sweep for the 119 non-Foundry sites (most are plain structs/UUIDs with no `CodingKeys`), then handle `GameNetworkModel`/Foundry-import sites in one careful pass — `GameNetworkModel` already has a hand-written `CodingKeys`, so its Swift property can safely be renamed without touching the wire string.
- **Severity:** Medium

### 9.3 Text-emphasis animation renderer/transition scaffolding built but never wired to any view
- **Location:** `Modules/CoreRPG/Text/OnboardingEmphasisAttribute.swift:7-87` (`OnboardingAppearanceEffectRenderer`, a full `TextRenderer`/`Animatable` implementation) and `:95-143` (`OnboardingTextTransition`, `OnboardingNameTransition`); consuming site `Modules/CoreRPG/LinkRenderer/LinkHighlightTextView.swift:29`
- **What:** `OnboardingEmphasisAttribute` is genuinely applied to text (`LinkHighlightTextModel.swift:281`), but the renderer meant to animate it is never passed to `.textRenderer(...)` anywhere, and `OnboardingTextTransition`'s only reference is commented out at `LinkHighlightTextView.swift:29`; `OnboardingNameTransition` has zero references at all.
- **Why:** Same shape as a pattern the prior audit already found and removed elsewhere — an attribute is set but the effect meant to render it is inert, so the intended emphasis animation silently never fires.
- **Action:** Either wire `OnboardingAppearanceEffectRenderer` into `LinkHighlightTextView.body`, or delete the ~110 lines of dead renderer/transition code if the effect was abandoned.
- **Severity:** Medium

### 9.4 `SheetSearchContext` — entire `@Observable` class has zero references
- **Location:** `Modules/CoreRPG/Sheet/SheetSearchContext.swift:1-35`
- **What:** A complete `@MainActor @Observable public final class SheetSearchContext` with `attachResults`/`detachResults`/`query` — verified via corpus-wide identifier search to have zero uses outside its own declaration.
- **Why:** Dead public API that reads as load-bearing (documented as coordinating search across Game windows) but isn't connected to anything.
- **Action:** Confirm whether cross-window search-field decoupling is still planned; wire it in or delete the file.
- **Severity:** Medium

### 9.5 `AppToolBarAppearenceViewModifier.swift` — unused, misspelled, and bypasses SwiftUI for direct UIKit appearance proxies
- **Location:** `Modules/CoreRPG/App/AppToolBarAppearenceViewModifier.swift:1-31`
- **What:** `appToolBarAppearence(color:)`/`AppToolBarAppearenceViewModifier` ("Appearence" misspelled throughout) has zero call sites anywhere in the tree, and its body reaches straight into `UITabBarAppearance`/`UIBlurEffect`/`UIColor`/`UITextField.appearance()`.
- **Why:** Dead file; if ever revived by copy-paste the typo would propagate into a second public symbol name.
- **Action:** Delete the file; reintroduce with correct spelling if tab-bar appearance customization is still wanted.
- **Severity:** Low

### 9.6 `SheetRowGeometryID` — orphaned enum, contradicting prior audit's explicit "should stay" verification
- **Location:** `Modules/CoreRPG/Sheet/SheetRootModel.swift:12-15`
- **What:** `CODE_AUDIT_11.md` §9.1 deleted the unused sibling `SheetRowGeometryMatch` but explicitly kept `SheetRowGeometryID` as "genuinely used and should stay." A fresh corpus-wide search today finds zero uses of `SheetRowGeometryID` or either of its cases anywhere but the declaration.
- **Why:** Either it lost its last caller since that audit or the prior verification was already wrong; either way it's dead now.
- **Action:** Delete, or re-wire into `matchedGeometryEffect(id:)` if the row-transition feature it was meant for still exists.
- **Severity:** Low

### 9.7 `VisualEffectView` — dead UIKit blur wrapper in vendored Apple sample code
- **Location:** `Modules/SpaceRPG/Record/CaptureOverlayView+Buttons.swift:44-48`
- **What:** `CaptureOverlayView.VisualEffectView: UIViewRepresentable` (wrapping `UIVisualEffectView`) has zero instantiations; its sibling `VisualEffectRoundedCorner` (`:31-42`, using `.background(.ultraThinMaterial, ...)`) is the one actually used, having superseded it with a SwiftUI-native equivalent.
- **Why:** Dead code, and also the kind of direct-UIKit usage in SwiftUI code CLAUDE.md asks to avoid — now provably unnecessary since the modern replacement already ships in the same file.
- **Action:** Delete lines 44-48.
- **Severity:** Low

### 9.8 Stale commented-out modifier lines left behind after UI changes
- **Location:** `Modules/MapRPG/Map/EditMapToolBar.swift:127` (`//.sheet(isPresented: $showPinSelection)`, beside the `.fullScreenCover` that replaced it), `Modules/GameRPG/GameViews/OnlyGameView.swift:23` and `Modules/GameRPG/GameViews/OnlyPlayerGameView.swift:22` (identical `//.gameOverlayTabBarView(value: NetworkModules.game)` in both files), `Modules/CoreRPG/LGViewModifiers/ToolbarItemListViewModifier.swift:127` (`//.popoverTip(MasterRPGTips.organizeContent)`), `Modules/CoreRPG/ItemDetail/ItemEditorForegroundView.swift:83` (`//.scrollTargetLayout()`), `Modules/CoreRPG/LGViews/HeaderFooterContentScrollView.swift:163,184` (`//.glassEffect(.regular.interactive())`, in `#Preview` code)
- **What:** 7 single-line commented-out SwiftUI modifier calls across 7 files — no `#if false` blocks exist anywhere in the codebase (confirmed repo-wide), but this smaller pattern of one-line residue wasn't caught by that check.
- **Why:** Ambiguous intent (reverted experiment vs. paused feature) left in source; the duplicated `.gameOverlayTabBarView` line in two files suggests a real feature toggle that should either come back or be removed cleanly.
- **Action:** Delete the `EditMapToolBar`/`ToolbarItemListViewModifier`/`ItemEditorForegroundView`/`HeaderFooterContentScrollView` lines outright; decide whether `.gameOverlayTabBarView` should return to both game views or be deleted from both.
- **Severity:** Low

### 9.9 CGImageDestination JPEG-encode boilerplate duplicated verbatim across two targets
- **Location:** `Modules/RolePlayGameKit/Import/Foundry/FoundryMediaNormalizer.swift:159-238` (`makeJPEG(from:)`) vs. `Sources/RPGShare/ItemProviderImporter.swift:122-152` (`downsampledIfNeeded(_:)`)
- **What:** Both independently hand-roll the same `CGImageDestinationCreateWithData` → `CGImageDestinationAddImage` → `CGImageDestinationFinalize` → `Data` sequence (both already correctly use the shared `JPEGQuality` named-constant tiers, but the ImageIO plumbing is copy-pasted).
- **Why:** A future JPEG-encoding bugfix (e.g. orientation-metadata handling, which `FoundryMediaNormalizer` does and `ItemProviderImporter` doesn't) has to be re-applied by hand in both places.
- **Action:** Extract a shared `CGImage.jpegData(compressionQuality:orientation:) -> Data?` helper into `CoreRPG`'s existing `Image+AKImage.swift`, used by both.
- **Severity:** Medium

### 9.10 `PreviewData.swift` bootstrap-loader duplicated verbatim across 5 modules
- **Location:** `Modules/DiceRPG/Model/PreviewData.swift:47-63`, `Modules/AdventureRPG/Model/PreviewData.swift:44-58`, `Modules/CharacterRPG/Model/PreviewData.swift:41-51`, `Modules/GeneratorRPG/Model/PreviewData.swift:35-49`, `Modules/MapRPG/Model/PreviewData.swift:46-59`
- **What:** The prior audit flagged a duplicated `print` string here and it's since been fixed and `#if DEBUG`-wrapped, but the entire ~15-line `.gmz`-bundle-load-and-import `Task` block around it is still copy-pasted 5 times, unchanged.
- **Why:** The actual duplication the prior audit was pointing at (not just the print string) remains; any fix to preview-fixture loading must be applied 5 times.
- **Action:** Extract the shared `Task { ... importUrl(from:) ... }` bootstrap into one CoreRPG preview-fixture helper parameterized by root model type.
- **Severity:** Low

### 9.11 Admission/dedup byte-limits set as inline default-parameter literals instead of named constants
- **Location:** `Modules/GameRPG/Network/GameRelayAdmission.swift:26` (`limit: Int = 512`), `:94-98` (`maximumEventCount = 32`, `maximumEventByteCount = 64 * 1_024`, `maximumTotalByteCount = 512 * 1_024`); `Modules/GameRPG/Network/SharePlayPlayerJournalAdmission.swift:118-121` (`maximumAdmissionCount = 512`, `maximumPendingCount = 16`, `maximumPendingByteCount = 64 * 1_024 * 1_024`)
- **What:** These tuning knobs live as bare literal default-argument values, unlike `Modules/GameRPG/SharePlay/SharePlaySingleQueuePackageSender.swift:78-85`, which hoists the same category of values into commented `nonisolated static let` constants.
- **Why:** Inconsistent with this project's own established pattern for exactly this kind of value in the same subsystem; harder to locate/tune from one place, and undocumented (no comment explains why 512/64KB/512KB/64MB were chosen).
- **Action:** Hoist into named `static let` constants alongside each type, matching `SharePlaySingleQueuePackageSender`'s convention.
- **Severity:** Low

### 9.12 `ScenesManager.swift` — 555-line class, zero `MARK` dividers, five distinct responsibilities
- **Location:** `Modules/CoreRPG/ScenesManager/ScenesManager.swift:58-555`
- **What:** One `@MainActor @Observable public final class ScenesManager` handles window open/dismiss actions (`:103-137`), per-scene state tracking (`:156-216`), event suppression (`:216-291`), immersive-space state (`:379-421`), and Space-viewer presentation (`:421-533`) — with no `MARK` comments anywhere, unlike every other large file in the codebase.
- **Why:** Hardest of the oversized files to navigate cold, since even the "add MARK dividers first" intermediate step the prior audit recommended for similar files hasn't happened here.
- **Action:** Add `MARK` dividers for the 5 sections above, then split into `ScenesManager+Windows.swift`, `+SceneState.swift`, `+ImmersiveSpace.swift`, `+SpaceViewer.swift`, mirroring the extension-per-file pattern already used for `MasterController`/`GameTableModel`.
- **Severity:** Medium

### 9.13 `GameNetworkController.swift` — 673 lines, already has clean `MARK` boundaries ready to split
- **Location:** `Modules/GameRPG/Network/GameNetworkController.swift:55` (Static builders), `:125` (Control), `:181` (Master send), `:253` (MasterNetworkControllerDelegate), `:298` (Player send), `:310` (PlayerNetworkControllerDelegate), `:342-659` (SharePlayControllerDelegate, the largest section), `:659` (Utility)
- **What:** Same "already organized, just not split" situation the prior audit found in `MasterController`/`GameTableModel` (both since split into per-topic files) — this file wasn't caught in that pass.
- **Why:** Mechanical, low-risk extraction opportunity along boundaries that already exist.
- **Action:** Split along the 7 `MARK` sections, e.g. `GameNetworkController+SharePlayDelegate.swift` for the largest.
- **Severity:** Low

### 9.14 `SingleReviewModels.swift` — 670 lines, ~10 `@Observable` model classes, zero `MARK` dividers
- **Location:** `Modules/CoreRPG/FileViews/SingleReviewModels.swift:64-402` (`SingleReviewItem`, `SingleReviewEntry`, `SingleReviewItemProperty`, `SingleReviewEntryProperty`, `SingleReviewReference`, `SingleItemImportModel`, `SingleEntryImportModel`, plus 2 enums)
- **What:** The single-item-import-review flow's entire model layer lives in one undifferentiated file with no internal signposting.
- **Why:** Harder to locate a specific model's logic than necessary.
- **Action:** Split into `SingleReviewKind+Decision.swift`, `SingleReviewItem+Entry.swift`, `SingleItemImportModel.swift`, `SingleEntryImportModel.swift`.
- **Severity:** Low

### 9.15 Additional oversized files (>500 lines) not covered by any prior audit round
- **Location (representative):** `Modules/RolePlayGameKit/Model/AppModel.swift` (658, partial MARKs), `Modules/GameRPG/SharePlay/SharePlayJournalPublicationQueue.swift` (555, 4 MARKs), `Modules/MapRPG/BattleRound/BattleRoundModel.swift` (551), `Modules/MapRPG/Map/EditMapToolBar.swift` (540), `Modules/CharacterRPG/Model/ValueModel.swift` (520, only 1 MARK), `Modules/CoreRPG/Persistence/CoreDataController.swift` (519, 6 MARKs already present), `Modules/CoreRPG/Files/FileUrlDataController.swift` (640, 2 MARKs), `Modules/MapRPG/Map/MapPinView.swift` (622), `Modules/CoreRPG/Views/ViewportGeometry.swift` (593)
- **What:** 33 files now exceed 500 lines outside this app's previously-known top-12 hot-spot list — 6 were already generically name-dropped in a prior audit round's "not individually reviewed" bullet, the other 27 have not appeared in any prior audit.
- **Why:** Total oversized-file surface area is larger than any single audit round has captured; most already have partial `MARK` structure so splitting is mechanical once prioritized.
- **Action:** Triage in a follow-up pass, starting with files that have zero/minimal `MARK` coverage (`ValueModel.swift`, `MapPinView.swift`, `ViewportGeometry.swift`) since those need dividers added before a split is safe.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **The "main-actor-blocking synchronous work" pattern keeps recurring at the edges.** §3.2, §3.4, §7.1, and §7.2 are all the same root cause in different files: a `@MainActor`/actor-isolated function calls a synchronous, potentially-slow primitive (disk I/O, ImageIO decode, Keychain access) directly instead of routing through the `@concurrent` / `Task.detached` pattern this codebase already established elsewhere for exactly this class of bug. Since the pattern is well-established in the sibling code each of these findings sits next to, a targeted grep for synchronous `FileManager`/`Data(contentsOf:)`/`AKImage.downsampled*`/`SecItem*` calls inside `@MainActor` or actor-isolated function bodies (not just the 4 sites found here) would likely surface a few more before they're user-visible.
2. **Casing-convention "done" claims need a mechanical check, not just a spot-check.** §9.1 and §9.2 both show a prior audit closing out a naming-convention item that turned out to be incomplete (one claimed literally "0 remaining" and wasn't). A small script (or even a documented one-line `grep -rEn '\b(var|let|func)\s+\w*(ID|URL)\b'` with the known-safe framework-API exclusions listed) run and its *raw count* — not a sampled read — recorded in the fix commit would prevent this from recurring a third time.
3. **Oversized files with existing `MARK` boundaries are the cheapest wins in §9.** §9.13's `GameNetworkController.swift` and several files in §9.15 already have the signposting a split needs; prioritize those over the files that need `MARK`s added first (§9.12, §9.14, and the `ValueModel.swift`/`MapPinView.swift`/`ViewportGeometry.swift` group in §9.15).
4. **"Attribute applied but its renderer never wired in" is a recurring failure shape.** §9.3 is the same shape as scaffolding the prior audit already found and deleted elsewhere. When adding a new `TextAttribute`/`TextRenderer` pair (or similar apply-then-render split), add a lightweight snapshot test asserting the renderer is actually attached via `.textRenderer(...)` somewhere reachable, so an abandoned wiring step fails a test instead of sitting silently dead.

---

## 11. What was NOT audited

- `Dead/` — doesn't exist in this repo (nothing archived to exclude beyond the standard build directories below).
- `.git/`, `.build/`, DerivedData, `Snapshots/` (image test fixtures), `Docu/` (historical audit reports — read as reference, not re-audited).
- **§8 SwiftUI/UI is incomplete.** The dedicated `swiftui-expert-skill` pass (7 parallel sub-passes covering all 15 modules' `View/` directories plus shared `CoreRPG` UI) failed entirely mid-run when the Claude Code account hit its monthly spend/rate limit (HTTP 429, reset noted as 12:00 Europe/Berlin). Only one manual spot-check (`MapPinView.swift`) was done directly, and it was clean. This is the single largest gap in this report — re-run the pass (ideally scoped per-module, to keep each run small) once the limit resets.
- Algorithmic correctness of the RealityKit/Table3D rendering pipeline and `MapOverlayGeometry`/room-layer geometry math — surface-level only, no deep geometric proof.
- Build settings, scheme configuration, and Xcode project structure beyond what's visible in shared schemes and the entitlements/Info.plist keys cited in §6.2.
- Third-party SPM dependency internals (`swift-syntax`, `xctest-dynamic-overlay`, `swift-snapshot-testing`, `swift-custom-dump`, the local `RPGTabletopGameContent` package) — treated as black boxes.
- Deep test-coverage assessment. Test targets were scanned lightly (TODO/print/size checks only); some individual test files are themselves very large (`Tests/GameRPGTests/SharePlayPackageTransportTests.swift` at 4,082 lines, `Tests/GameRPGTests/MasterPlayerControllerTests.swift` at 2,267) and were not read in full.
- Localization wording/correctness — string catalogs exist per module but translation quality wasn't assessed.
- Performance profiling via Instruments — the audit identified *potential* hot paths (§7) from static reading only; no `.trace` was recorded.
- The Foundry VTT ZIP reader's path-traversal/zip-slip and decompression-bomb guards were checked and confirmed present (`Modules/CoreRPG/Foundry/FoundryZIPArchive.swift`) but not fuzz-tested against adversarial archives.
- The full corpus of 6,553 raw `\b[a-zA-Z_]+ID\b` regex hits behind §9.2's 219-site count was not individually triaged — the agent verified the reduced count via whole-corpus identifier-frequency analysis excluding framework symbols (`objectID`, `NSManagedObjectID`, `CKRecord.ID`, etc.), but a residual few framework-adjacent false positives are possible within the 219.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line.

For the High findings (no Critical findings emerged this round), here are the lines that prove the claim, each independently re-opened and confirmed during this audit (not just trusted from agent output):

- **§5.2** — open `Modules/CharacterRPG/Controller/EditController.swift`, lines 184 and 199. Both read `if entry.type != .number || entry.type != .decimal { entry.type = .number }` — an `Optional<EntryType>`/`EntryType` value cannot equal two different cases at once, so this `||` condition cannot ever evaluate false; the body always executes.
- **§5.1** — open `Modules/GameRPG/Player/PlayerNetworkController.swift`, lines 82-95 (`stop()`): no `browserManager.stop()` call anywhere in the function body. Compare `Modules/GameRPG/Master/MasterNetworkController.swift`, line 124 (`networkModel.browserManager?.stop()` inside `resetConnections()`), confirming the master side does this correctly and the player side is the asymmetric gap. A repo-wide grep for `.browserManager.stop(` inside `Modules/GameRPG` returns zero player-side hits, against two player-side `.browserManager.start()` call sites (`SearchProxyView.swift:60-61`, `BrowserView.swift:42`).
- **§9.1** — a fresh `grep -rEc '\b(var|let|func)\s+\w*URL\b' Modules Sources` sums to 59, matching the finding's count; `Modules/CoreRPG/App/AppGroup.swift` lines 38 and 49 confirmed as `static let groupURL` / `static let cloudURL`.
- **§5.3** — open `Modules/CharacterRPG/Controller/EditController.swift`, lines 338-362: `duplicateSubValue(id:withCopy:)` calls itself inside `subValueIds.forEach { duplicateSubValue(id: $0, ...) }` with no depth counter or visited-ID set anywhere in the function.
- **§7.1** — open `Modules/PhotoRPG/Controller/CacheController.swift`, lines 76-88: `downsampledSource(for:item:)` is declared `@MainActor`; lines 79 and 82 call `AKImage.downsampledThumbnail(from:maxPixelSize:)` with no `await` in front of it, confirming a synchronous decode inside a Main-Actor-isolated function.

If any finding doesn't reproduce when you visit the line, flag it and I'll re-investigate.
