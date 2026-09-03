# MasterRPG Code Audit — Round 10

Generated 2026-09-03. Scope: ~268,000 Swift LOC across 1,992 files, covering all 15 dynamic-framework modules (`AdventureRPG`, `AudioRPG`, `CharacterRPG`, `CoreRPG`, `DiceRPG`, `GameRPG`, `GeneratorRPG`, `MapRPG`, `PdfRPG`, `PhotoRPG`, `RolePlayGameKit`, `RuleRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG`) and the `MasterRPG`/`MasterMac`/`MasterTV`/`RPGShare`/`DiceRollerWidgetExtension` targets. No `Dead/` or archived directory exists in this repo, so nothing was excluded by convention — only `.git/`, `.build/`, and `xcuserdata/` were skipped.

**This is the tenth full-codebase pass.** `Docu/CODE_AUDIT_1.md` through `_9.md` (2026-08-07 → 2026-08-30) already covered the whole codebase nine times, plus seven scoped deep-dives, all remediated (see `Docu/CODE_AUDIT_9.md`'s own remediation table). Round 9's own executive summary reported **zero Critical findings** and a short list of High items, most fixed same-round (2026-08-24/29); a handful were **investigated and deliberately deferred** rather than fixed. This round:

1. Re-verified round 9's deferred/still-open items directly against current source (not trusted from the doc) — all six reproduce unchanged; see the table below.
2. Read, line by line, every file touched since round 9's fix commit (`21842079..HEAD`, 4 commits, 24 files — all visionOS Table3D/SpaceRPG capture-pipeline work) looking for regressions or fresh bugs. Found one fresh instance of an already-known SwiftUI anti-pattern; found no new bugs — every change in that diff is itself a well-reasoned, already-landed fix.
3. Ran a fresh, independent full-codebase sweep: three parallel agents (concurrency/API modernity, dead code/duplication, bugs/security/performance) plus a dedicated SwiftUI-expert pass, scoped to catch what nine prior rounds missed.

| Round 9 deferred/open item | This round | Where |
|---|---|---|
| §8.2 `itemSync`/`itemOrEmpty` subscribes to whole `itemData` dict | Confirmed unchanged | §8.1 |
| §9.1 10 of 12 `GameController`s duplicate `GenericGameController` | Confirmed unchanged (`wc -l` re-run) | §9.1 |
| §9.2 File-backed-module (Photo/Pdf/Space) triplication | Confirmed unchanged, line numbers re-verified | §9.2 |
| §9.3 AppIntent `Entity`/`EntityQuery` boilerplate ×12 | Confirmed unchanged | §9.3 |
| §9.10 `ID`/`URL` casing violations | Confirmed unchanged **and much larger than previously scoped** — see §9.4 | §9.4 |
| §7.3 Foundry system-package triple-parse (partial) | Confirmed `FoundryArtifactDetector.detect()` still runs its own separate parse | §7.4 |

**Compiler ground truth:** genuine full clean `xcodebuild build` (fresh, not incremental — confirmed via explicit `clean` first) of all four shipping targets plus the widget extension:
- `MasterRPG` (iOS Simulator, iPhone 17, iOS 27.0) — **BUILD SUCCEEDED**, zero real warnings.
- `MasterMac` (macOS 26) — **BUILD SUCCEEDED**, zero real warnings.
- `MasterTV` (tvOS 27 Simulator) — **BUILD SUCCEEDED**, zero real warnings.
- `DiceRollerWidgetExtension` (iOS Simulator) — **BUILD SUCCEEDED**, zero real warnings.

The only lines matching `warning:` in any log are two benign `appintentsmetadataprocessor: Metadata extraction skipped, no AppIntents.framework dependency found` build-tool notices — identical to every prior round, not a Swift diagnostic. A full-tree, semantically-verified sweep (not just grep) for every hard CLAUDE.md rule — `DispatchQueue.main.async`, `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject`/`@EnvironmentObject`, `Task.sleep(nanoseconds:)`, single-parameter `.onChange(of:)`, legacy `Formatter` subclasses, `String(format:)`, `.replacingOccurrences`, `.contains(` on user text, `.foregroundColor(`, `.tabItem(`, `UIScreen.main.bounds`, `NavigationView`, `ForEach(Array(...enumerated()))` — found **zero new violations** anywhere in the app. Zero `TODO`/`FIXME`/`HACK`/`XXX`/`#warning` markers and zero `#if false` blocks exist anywhere in the repo. Zero `try!`/`as!`/hardcoded secrets found repo-wide. All 14 `.xcdatamodeld` files were checked programmatically against the CloudKit optionality/default-value rule — zero violations.

Given this baseline, this round's genuinely new findings are concentrated in two places: (1) a tvOS-specific data-sync gap that's existed for a while but wasn't previously flagged, and (2) narrower concurrency/performance issues that survive Swift's strict-concurrency checker because they're logic races or wasted-work patterns, not data races.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made. Every Critical/High claim below was personally re-opened and confirmed by reading the cited lines before inclusion — see §12.

---

## 1. Executive summary

No Critical findings this round either — nothing found reaches the crash/data-loss/memory-corruption bar. Top items, in priority order:

1. **[High] tvOS silently ignores the user's "Store Database in iCloud" toggle — Core Data always boots local-only on Apple TV** — §5.1 — `Modules/RolePlayGameKit/Model/AppModel.swift:231`.
2. **[High] MasterTV and RPGShare entitlements lack the iCloud ubiquity-container capability, so their file-backed content never syncs** — §6.1 — `Resources/MasterTV-Debug.entitlements`, `Sources/RPGShare/RPGShare-Debug.entitlements`.
3. **[High, carried forward] Reading an item via `itemSync(for:)`/`itemOrEmpty(for:)` subscribes the caller to a module's entire `itemData` dictionary** — §8.1 — `Modules/CoreRPG/ItemList/ItemDataModel.swift:28`. Deliberately deferred in round 9; still open.
4. **[High, carried forward] Ten of twelve per-module `GameController`s still hand-duplicate `GenericGameController`'s core** — §9.1 — re-confirmed via direct line counts.
5. **[High, carried forward] File-backed-module (Photo/Pdf/Space) sync logic remains triplicated in `MasterController`/`PlayerController`** — §9.2 — deliberately deferred in round 9; still open.
6. **[Medium-High] `MasterController.resetPlayers()` has two independent, unsynchronized call paths that can interleave** — §3.1 — `Modules/GameRPG/Controller/MasterController.swift:581`, `:1068`, `:1132`; `Modules/GameRPG/Root/GameRootModel.swift:447`.
7. **[Medium] `ID`/`URL` casing violates the project's own `Id`/`Url` convention at ~460+ sites, including CoreRPG's own foundational `FilePersistenceController.fileURL`** — §9.4 — round 9 scoped this far narrower; this round's full sweep found a much larger footprint.
8. **[Medium] Table3D's viewport-pan gesture still triggers a full fog/board texture recomposite for a value the renderer's own doc comment says has no visual effect** — §7.1 — `Modules/GameRPG/Table3D/GameTableModel.swift:557-558,611`.
9. **[Medium] `PdfContentExtractor` constructs and prewarms a brand-new `LanguageModelSession` on every PDF page instead of reusing one** — §7.2 — `Modules/GeneratorRPG/BasicAI/Providers/PdfContentExtractor.swift:66-67`.
10. **[Medium, carried forward] AppIntent `Entity`/`EntityQuery` boilerplate is still hand-duplicated across all 12 modules** — §9.3 — deliberately deferred in round 9; still open.

---

## 2. Quick wins (≤30 min each)

- **Fix the "Databse Settings" typo** — `Modules/CoreRPG/FileViews/StorageOptionEditor.swift:68` — user-visible string in the shipping Settings screen. See §5 note.
- **Delete the dead `DecoderPool` actor** — `Modules/CoreRPG/CRDT/DecoderPool.swift:1-19` — pools nothing (`getDecoder()` returns `JSONDecoder()` fresh every call) and has zero references anywhere. See §9.5.
- **Delete two dead symbols left over from a tile-editor refactor** — `Modules/MapRPG/View/DisplayConfigEditor.swift:18` (`showTileEditor`) and `:168-170` (`saveTileCoordinates(_:)`) — neither is read anywhere; tile editing now routes through `MapEditorRoute.mapTileEditor`. See §9.6.
- **Delete the unused `formatValues(results:sumUp:modifier:)` helper** — `Modules/DiceRPG/Intent/RollSpecificDiceIntent.swift:67-87` — `perform()` builds its dialog a different way; this 21-line helper is never called. See §9.6.
- **Remove the two ungated `print()` calls in a test file** — `Tests/CoreRPGTests/LinkHighlightTextModelTests.swift:81,114-115` — debug leftovers, not assertions.
- **Name the magic 500ms capture-restart delay** — `Modules/SpaceRPG/Record/AppDataModel.swift:168` — extract `try? await Task.sleep(for: .milliseconds(500))`'s literal into a `private static let captureRestartDelay: Duration`, matching the codebase's own naming convention for tuned constants elsewhere in the same file.
- **Rename `shotID` → `shotId`** — `Modules/SpaceRPG/Record/ShotFileInfo.swift:21` — a single-line, zero-risk instance of the casing violation (§9.4), notable because the *function* on the same line (`parseShotId`) is already correctly cased.
- **Sync or delete the stale `AGENTS.md`** — see §9.7 — it duplicates `CLAUDE.md` with a wrong iCloud container identifier and numerous typos not present in `CLAUDE.md`.
- **Replace `CRDT.swift`'s three fresh `JSONEncoder()`/`JSONDecoder()` calls with the shared `JSONCoding.encoder`/`.decoder`** — `Modules/CoreRPG/CRDT/CRDT.swift:43,50,61` — no custom `outputFormatting` is used, so nothing blocks sharing; this is a hot, per-field, every-network-merge path. See §9.5.

---

## 3. Concurrency

### 3.1 `MasterController.resetPlayers()` has two independent, unsynchronized call paths that can interleave
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:581-634` (`resetPlayers()` implementation — several sequential `await send(...)` calls after snapshotting roster/control state); `:1068-1079` (`lostPlayer(for:)`, called directly from `Modules/GameRPG/Network/GameNetworkController.swift:260,371` on connection loss — **not** routed through `messagePipeline`); `:1132` (`process(_:)`, called only from inside `processMessages()`'s `messagePipeline`-drained loop, on a new player joining); `Modules/GameRPG/Root/GameRootModel.swift:447-456` (`sharingControlActions.update` schedules a third call via `scheduleNetworkAction`'s own independent serial task-chain, triggered when a GM toggles player visibility in Settings)
- **What:** `resetPlayers()` is reachable from three call sites with two different (and mutually unaware) serialization mechanisms: the `messagePipeline` actor serializes network-message-triggered calls against each other, and `scheduleNetworkAction`'s task-chain serializes Settings-triggered calls against each other — but nothing serializes the two mechanisms against one another, and `lostPlayer` bypasses both.
- **Why:** Both `resetPlayers()` and its two competing callers are correctly `@MainActor`-isolated, so Swift's strict-concurrency checker sees no violation — but `resetPlayers()` `await`s multiple times internally, and the MainActor is free to run a second, independently-triggered `resetPlayers()` call in between those awaits. A player joining/leaving at the same moment a GM toggles player visibility in Settings can produce two interleaved broadcast sequences, each computing its own stale snapshot — players can receive out-of-order or superseded map/pin/battle-round resets.
- **Action:** Route the Settings-driven call (`GameRootModel.swift:453`) and `lostPlayer`'s direct call through the same `messagePipeline` serialization the network-receive path already uses, so only one `resetPlayers()` broadcast sequence is ever in flight.
- **Severity:** Medium-High (a genuine, narrow-window logic race; no crash/data-loss, but a real GM/player state-consistency bug in a codebase whose own history shows this exact bug class recurring — see project memory on prior health-sync races).

### 3.2 Dead `#available(iOS 18, *)` branch below the deployment target
- **Location:** `Modules/CoreRPG/Navigator/Core/NavigationConfiguration.swift:80-84`
- **What:** `if #available(iOS 18, *) { executionDelay = min(max(0.3, executionDelay), 5.0) } else { executionDelay = min(max(0.7, executionDelay), 5.0) }` — iOS 18 is below this project's iOS 26.0 floor, so the `else` branch (the `0.7` floor) can never execute.
- **Why:** Dead code obscures the real effective default and can't be flagged by the compiler on its own (unlike a plain unreachable statement).
- **Action:** Collapse to just the `iOS 18` branch's `0.3` floor and delete the `else`. Note: this file is vendored third-party (`Navigator`/`NavigatorUI`, credited to "Michael Long") — if the project tracks upstream, prefer reporting this there over a local hand-edit.
- **Severity:** Medium

### 3.3 Redundant `@available` annotations at/below the deployment floor (no dead branch)
- **Location:** `Modules/CoreRPG/Navigator/Extensions/NavigationLink+Navigator.swift:40,102` (`@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)`); `Modules/CoreRPG/App/PlatformModifiers.swift:31,41,46` (`@available(iOS 26.0, macOS 26.0, tvOS 26.0, *)`)
- **What:** Both sets of annotations gate declarations at or below the current 26.0 deployment floor, so the checks are permanently true — inert, but (unlike §3.2) with no unreachable `#else` fallback attached.
- **Why:** Clutter that can mislead a reader into thinking older-OS support is still a live concern.
- **Action:** Remove the now-redundant `@available` attributes. `PlatformModifiers.swift` is project-owned; `NavigationLink+Navigator.swift` is vendored (same caveat as §3.2 — this specific citation was already flagged informationally in round 9 §4.5 and deliberately left alone as vendored code).
- **Severity:** Low

### 3.4 `Task.detached` fire-and-forget writes with no cancellation handling
- **Location:** `Modules/GameRPG/Network/GameJoinCodeModel.swift:77-79,130-132`
- **What:** `lastUsedMasterJoinCode`'s `didSet` and the shared `write(_:forKey:to:)` helper spawn `Task.detached(priority: .utility) { codeStorage.set/remove(...) }` with no stored task handle and no `withTaskCancellationHandler`.
- **Why:** Every other `Task.detached` use in the codebase (`MasterController.detachedGameData`, the Foundry VTT import readers, `SpaceRPG/Record/AppDataModel.cleanupTask`, `ResourceCache.load`) deliberately propagates cancellation. These two are the sole outliers — low real-world impact since the writes are tiny, idempotent Keychain calls, but an avoidable inconsistency.
- **Action:** Store the task handle or wrap in `withTaskCancellationHandler`, matching the rest of the codebase.
- **Severity:** Low

### 3.5 Test-only `@Observable` class missing `@MainActor`
- **Location:** `Tests/CoreRPGTests/SwiftDataControllerTests.swift:96-104` (`fileprivate final class TestModel: @unchecked Sendable`)
- **What:** `@Observable`, `@unchecked Sendable`, but no `@MainActor` — used to instantiate `SwiftDataController<TestModel, TestDataModel>` in two tests.
- **Why:** CLAUDE.md's `@MainActor`-on-`@Observable` mandate is stated without a test-code carve-out; this is test scaffolding, not a production bug.
- **Action:** Add `@MainActor` if the generic constraint allows it, or comment why the fixture is deliberately left non-isolated.
- **Severity:** Low

---

## 4. API modernity

This round's full grep/semantic sweep (see the report header) found **zero new violations** of any CLAUDE.md-mandated API-modernity rule — no raw `DispatchQueue`, no `ObservableObject`/`@Published`/`@StateObject`/`@EnvironmentObject` outside one justified exception, no `Task.sleep(nanoseconds:)`, no single-parameter `.onChange(of:)` (all ~268 call sites parsed programmatically), no legacy `Formatter` subclasses, no `String(format:)`, no `.replacingOccurrences`, no `.contains(` on user-facing text search (88 `localizedStandardContains` sites confirmed instead), no `.foregroundColor(`/`.tabItem(`/`UIScreen.main.bounds`/`NavigationView`/`ForEach(Array(...enumerated()))`, no stale `PHImageManager`-style PhotoKit completion-handler usage, no `UIApplication.shared.windows`. Continuation-wrapped APIs (`NSItemProvider`, `NWConnection.receiveMessage`) were individually checked against current Apple documentation and confirmed to have no native async replacement yet — not legacy debt.

### 4.1 `@ObservedObject` for Apple's `GroupStateObserver` — confirmed justified, informational only
- **Location:** `Modules/GameRPG/SetupViews/SharePlayButton.swift:20-22`
- **What:** `@ObservedObject private var groupStateObserver = GroupStateObserver()` — the sole `@ObservedObject`/`ObservableObject` usage anywhere in the app.
- **Why:** `GroupStateObserver` is an Apple-owned GroupActivities type conforming only to `ObservableObject`, with no `@Observable` alternative exposed by the SDK — exactly the "unavoidable/integration" exception CLAUDE.md itself carves out.
- **Action:** None required. Optionally wrap in a small `@MainActor @Observable` bridge republishing the Combine publisher, for stylistic consistency only.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 tvOS `AppModel` hardcodes `useCloudKit: false`, silently ignoring the visible Settings toggle
- **Location:** `Modules/RolePlayGameKit/Model/AppModel.swift:231` (`#if os(tvOS) ... self.databaseModel = databaseModelOverride ?? DataBaseModel(useCloudKit: false, currentActor: .mainApp)`) vs. `:249` (`#else` branch: `DataBaseModel(useCloudKit: settingsModel.useCloudKit, ...)`); toggle UI at `Modules/CoreRPG/FileViews/StorageOptionEditor.swift:23-63`, reachable on tvOS with no platform gate via `Modules/RolePlayGameKit/View/SettingsView.swift:60` and both `Modules/RolePlayGameKit/Route/RouteDestinationView.swift:59-62` and `ExtendedTabRouteDestinationView.swift:51-52` (only the neighboring `.generator` case has a `#if os(tvOS)` exclusion — `.settings` has none)
- **What:** Verified directly: the tvOS branch of `AppModel`'s Core Data setup is a hardcoded `false`, never reading `settingsModel.useCloudKit`. The "Store Database in iCloud" toggle itself is fully visible, interactive, and persists to `UserDefaults` (`AppSettingsModel.swift:142-145`) identically on every platform including tvOS — there is no tvOS-specific messaging or disabled state telling the user it won't take effect.
- **Why:** An Apple TV user can flip the toggle on, confirm the app-quit-and-relaunch alert `StorageOptionEditor` shows, relaunch — and nothing changes: Adventures/Characters/Maps created on iPhone/Mac never appear on Apple TV and vice versa, with no error surfaced anywhere. This silently defeats the app's central "multi-platform" sync promise on one of its four supported platforms.
- **Action:** Either read `settingsModel.useCloudKit` on tvOS like every other platform, or — if tvOS CloudKit sync is intentionally unsupported — hide/disable `StorageOptionEditor` under `#if !os(tvOS)` so the setting can't be toggled into a state the app doesn't honor.
- **Severity:** High

### 5.2 "Databse Settings" section-header typo
- **Location:** `Modules/CoreRPG/FileViews/StorageOptionEditor.swift:68`
- **What:** `Text("Databse Settings", bundle: .module)` misspells "Database."
- **Why:** User-visible in every localization catalog keyed off this source string, on a shipping Settings screen.
- **Action:** Fix the source string and regenerate/update the String Catalog entries. Quick win — see §2.
- **Severity:** Low

---

## 6. Security

Verified clean this round: no hardcoded secrets/API keys/bearer tokens/staging URLs anywhere in the repo; `JoinCodeStorage`/`GameJoinCodeModel` use correct Keychain APIs (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, off-main-actor writes, with a proper UserDefaults→Keychain migration path); the hand-rolled `FoundryZIPArchive` parser correctly rejects path traversal, ZIP64/symlink/multi-disk entries, and overflow, with CRC verification, and its sanitizer is invoked on every extraction path checked; all `Task.detached`/message-handling code in the local-network and SharePlay transport layers was read for injected-payload handling with no crash/corruption path found. The previously-flagged macOS Hardened Runtime exceptions (`com.apple.security.cs.allow-jit`, `.allow-unsigned-executable-memory`, noted in `Docu/xcode-security-audit-scratchpad.md`) were checked against the current entitlements files directly — both are **already removed** (per `Docu/xcode-security-settings.md`, dated 2026-07-17); the scratchpad note is stale and does not reproduce.

### 6.1 `MasterTV` and `RPGShare` entitlements omit the iCloud ubiquity-container capability
- **Location:** `Resources/MasterTV-Debug.entitlements`, `Resources/MasterTV-Release.entitlements`, `Sources/RPGShare/RPGShare-Debug.entitlements`, `Sources/RPGShare/RPGShare-Release.entitlements` (each declares only `com.apple.developer.icloud-services: [CloudKit]`) vs. `Resources/MasterRPG-Debug.entitlements`/`-Release.entitlements` and the `MasterRPG-Mac-*.entitlements` (each additionally declares `com.apple.developer.ubiquity-container-identifiers: [iCloud.de.andretrettin.gamemaster]` and `CloudDocuments` under `icloud-services`) — confirmed by reading all six files directly
- **What:** `FileManager.cloudURL` (`Modules/CoreRPG/App/AppGroup.swift:40`, `= FileManager.default.url(forUbiquityContainerIdentifier:)`) returns `nil` without this entitlement; `preferredRootUrl` (`AppGroup.swift:49-51`) falls back, in order, to the App Group container. Since AudioRPG/PdfRPG/PhotoRPG/SpaceRPG all route file storage through this fallback chain, every media file (photo/audio/PDF/3D object) on MasterTV — and independently of §5.1's Core Data gap — is written to a device-local App Group container that is never synced to any other device, rather than the shared iCloud Documents container every other platform uses.
- **Why:** Even if §5.1 were fixed so tvOS's Core Data *records* synced, the *files* those records reference (photos, PDFs, audio, 3D scans) would still never leave the Apple TV — a GM's map photo added on iPhone would show as a broken/missing reference on Apple TV, and vice versa.
- **Action:** Add `com.apple.developer.ubiquity-container-identifiers` and `CloudDocuments` to MasterTV's (and, if it manages files independently, RPGShare's) entitlements if cross-device file sync is intended on tvOS; otherwise document the limitation and gate the affected file-picker/viewer UI accordingly on tvOS.
- **Severity:** High

---

## 7. Performance

### 7.1 Table3D viewport-pan gesture triggers a full fog/board recomposite for a value the code's own doc comment says has no visual effect
- **Location:** `Modules/GameRPG/Table3D/GameTableModel.swift:544-566` (`renderSignature` folds `viewportPan.x`/`.y` into its cache-invalidation hash), `:583-585` (`boardFocusRect(entries:imageSize:panOffset:)` — parameter literally named `panOffset _` and ignored, always returns the full-canvas rect), `:605-613` (`panViewport(by:)`, whose own doc comment reads: *"No longer has any rendering effect (`boardFocusRect` never crops)... kept, along with the gesture that drives it, rather than ripping the pan gesture out entirely"* — yet still mutates `manualViewportOffset` and calls `replaceFogOfWarTask(isGameMaster:)` on every drag)
- **What:** Confirmed by direct read: the 3D board deliberately never crops/zooms (per `boardFocusRect`'s own doc), and the same file's own comment on `panViewport(by:)` already acknowledges panning has "no longer" any rendering effect — but the code wasn't fully cleaned up to match: `renderSignature` still busts its cache on every pan-delta change, and `panViewport(by:)` still unconditionally triggers a full `replaceFogOfWarTask` (a `Canvas`+`ImageRenderer` composite at up to 2048px, on the main actor, plus a `TextureResource` re-upload).
- **Why:** Every pan-and-release on the 3D table's currently-focused room recomputes and re-uploads a texture that is byte-for-byte identical to the one already showing — wasted CPU/GPU work and a main-actor stall on a gesture the developers already know is visually inert.
- **Action:** Drop `viewportPan` from `renderSignature`'s hash (it has no rendering effect for the 3D board), and/or have `panViewport(by:)` skip `replaceFogOfWarTask` entirely now that `boardFocusRect` never uses the offset.
- **Severity:** Medium

### 7.2 `PdfContentExtractor` constructs and prewarms a new `LanguageModelSession` per PDF page
- **Location:** `Modules/GeneratorRPG/BasicAI/Providers/PdfContentExtractor.swift:60-75` (`for page in extractedText { let session = LanguageModelSession(instructions: instructions); session.prewarm(); ... await session.respond(...) }`)
- **What:** Confirmed by direct read: a brand-new session is created and `prewarm()`'d on every loop iteration, then `respond(to:)` is awaited immediately after — `prewarm()` provides no latency benefit when called with no overlapping work directly before its own use.
- **Why:** Each of up to 20 pages (the default `maxPages`) pays full session-initialization overhead instead of reusing one session across the whole extraction, unlike the single-session pattern `PdfSummaryAnalyzer`/`TableSummaryAnalyzer` already use elsewhere in the same module.
- **Action:** Create one `LanguageModelSession` (one `prewarm()` call) before the loop and reuse it for every page's `respond(to:)`, unless per-page context isolation is a deliberate, documented requirement.
- **Severity:** Medium

### 7.3 `RuleEntryTree.nodes` builds the hierarchy with an O(n²) scan
- **Location:** `Modules/RuleRPG/Controller/RuleEntryTree.swift:143-154`
- **What:** `nodes(parentID:visited:)` calls `entries.compactMap` (a full linear scan) once per node, recursively — O(n²) total for a tree of n entries.
- **Why:** A large rule/compendium import (hundreds of entries, as Foundry system imports can produce) re-scans the full entry array at every tree level, unnecessary CPU work that grows quadratically with rule-set size.
- **Action:** Pre-group entries into a `[UUID?: [RuleEntryModel]]` dictionary by parent id once, then have `nodes` look up children by key.
- **Severity:** Low

### 7.4 System-package Foundry imports still parse the same archive twice — `FoundryArtifactDetector.detect()`'s separate pre-check unchanged since round 9
- **Location:** `Modules/CoreRPG/Foundry/FoundryArtifactDetector.swift:35,74` vs. the now-shared `FoundryVTTImportReader.swift`/`FoundrySystemPackageReader.swift` decode path round 9 §7.3 already consolidated
- **What:** Round 9 fixed the two back-to-back parses *inside* `FoundryVTTImportReader.read(from:)` itself (down from up to 3 parses to up to 2), but explicitly left `FoundryArtifactDetector.detect()` unfixed — it's called separately, earlier, by `FoundryRuleImportModel`, often with user interaction in between, so sharing its parse would need a cache spanning two independently-lived types.
- **Why:** Confirmed still present and still a deliberate deferral (round 9's own write-up cites the staleness/retention risk as disproportionate for a Medium finding) — carried forward here as confirmation the deferral still stands, not a new discovery.
- **Action:** As round 9 recommended: a URL+mtime-keyed cache spanning `detect()` and `read(from:)`, only if this becomes a measured hot path.
- **Severity:** Medium (deferred)

---

## 8. SwiftUI / UI

### 8.1 Reading an item via `itemSync(for:)`/`itemOrEmpty(for:)` subscribes the caller to a module's entire `itemData` dictionary — carried forward, confirmed unchanged
- **Location:** `Modules/CoreRPG/ItemList/ItemDataModel.swift:28` (`public var itemData: [UUID: ModelType] = [:]`, a plain `@Observable`-tracked dictionary); `Modules/CoreRPG/Controllable/ItemControllable.swift:473-480` (`itemSync`/`itemOrEmpty` subscript directly into it); representative call sites: `Modules/CharacterRPG/View/EntryListDiceRow.swift`, `InlineRowViewer.swift`, `ThumbnailPhotoRow.swift`, `Modules/CoreRPG/LGViews/EntryEditRow.swift`, `Modules/PhotoRPG/View/CarouselPhotoItemView.swift`
- **What:** Swift's Observation framework tracks a dictionary-typed `@Observable` property at whole-property granularity, not per-key — reading any single key inside a view's `body` subscribes that view to the *entire* dictionary.
- **Why:** Editing any one item in a module re-invalidates every other open row/editor for that module, even for a completely unrelated item id. Round 9 investigated a fix and deliberately deferred it: the correct fix touches a shared protocol signature (`ViewController.rowViewer(source:destination:)`) dispatched across all ~12 feature modules, a materially larger change than it first appears.
- **Action:** As round 9 recommended: have these call sites receive an already-resolved model reference from their parent, instead of re-resolving via the shared dictionary inside each row's own `body`. Full technical detail in `Docu/CODE_AUDIT_9.md` §8.2.
- **Severity:** High (deferred, still open)

### 8.2 Fresh instance of "view decomposed via computed property instead of a `View` struct" added since round 9
- **Location:** `Modules/GameRPG/Table3D/GameTableView.swift:162-171` (`@ViewBuilder private var windowOpenButton: some View`)
- **What:** This property was added in the post-round-9 diff (commit range `21842079..HEAD`) as part of a table-ornament reorganization. Round 9 §8.1 flagged ~150 pre-existing instances of exactly this CLAUDE.md-banned pattern ("Do not break views up using computed properties; place them into new View structs instead") as High severity, given the pattern's measured cost on hot, frequently-re-evaluated editor components; round 9 fixed 5 of those files and explicitly left the rest.
- **Why:** A small, ~10-line computed property sharing `GameTableView`'s own invalidation boundary is lower-impact here than round 9's flagged numeric-editor family (this is a top-level game screen, not a hot leaf editor row) — but it's a fresh addition of a pattern the team has already spent effort eliminating elsewhere, worth catching before it accumulates the way the original ~150 did.
- **Action:** Extract into a small `WindowOpenButton: View` struct taking `root`/`gameModel` as inputs, matching the extraction pattern round 9's §8.1 fix already established (e.g. `ItemHeaderEditorNameSection`).
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Ten of twelve per-module `GameController`s still hand-duplicate `GenericGameController`'s core — carried forward, confirmed unchanged
- **Location:** `Modules/CoreRPG/Controllable/GenericGameController.swift` (85 lines, the shared default) vs., re-confirmed by direct `wc -l` this round: `Modules/DiceRPG/Controller/GameController.swift` (614 lines), `CharacterRPG/Controller/GameController.swift` (512), `SpaceRPG/Controller/GameController.swift` (415), `MapRPG/Controller/GameController.swift` (430) — vs. `RuleRPG/Controller/GameController.swift` and `GeneratorRPG/Controller/GameController.swift` (8 lines each, both a one-line `typealias` to `GenericGameController`)
- **What:** Unchanged since round 8/9 — only Rule/Generator have migrated to the generic base.
- **Why:** A bug fix or protocol change to the shared game-sync contract must be manually verified against up to four independently-evolved copies — exactly the class of drift this codebase's own history shows causes GM/player sync bugs.
- **Action:** Audit whether Dice/Character/Space/Map's `GameController`s can be re-expressed as thin overrides of `GenericGameController`, keeping only genuinely module-specific logic (e.g. Dice's roll-result handling) as overrides. Full prior analysis in `Docu/CODE_AUDIT_9.md` §9.1 / `Docu/CODE_AUDIT_Game.md` §9.1.
- **Severity:** High (carried forward, still open — persisted across 9+ prior audit rounds)

### 9.2 File-backed-module sync logic remains triplicated across Photo/Pdf/Space — carried forward, confirmed unchanged
- **Location:** `Modules/GameRPG/Controller/MasterController.swift:1861-2004` (`handlePdf`), `:2005-2148` (`handlePhoto`), `:2282-2478` (`handleSpace`) — three near-identical ~140-line handlers, line numbers re-verified this round; `Modules/GameRPG/Controller/PlayerController.swift:216-274` (`sharePhoto`), `:275-332` (`sharePdf`), `:333-388` (`shareSpace`) — same triplicated structure
- **What:** Explicitly deferred by `Docu/CODE_AUDIT_Game.md`'s 2026-08-22 fix pass ("real work, disproportionate risk for the remaining budget") and re-confirmed present, unchanged, by round 9 and again this round — `MasterController.swift` was not among the 24 files touched since round 9's fix commit.
- **Why:** ~200+ lines of version-ledger/availability logic and three ~140-line message handlers duplicated with no mechanism keeping the copies in sync — exactly the kind of file-availability logic implicated in this app's documented history of GM/player sync bugs.
- **Action:** Extract a generic `PlayerVersionLedger`/`FileAvailabilityGameControllable` protocol parameterized by `NetworkModules`, and one `handleFileBackedModule(_:controllable:availability:featureEnabled:)` helper for the three Master-side handlers, as `Docu/CODE_AUDIT_Game.md` originally recommended.
- **Severity:** High (carried forward, still open)

### 9.3 AppIntent `Entity`/`EntityQuery` boilerplate still duplicated 12× — carried forward, confirmed unchanged
- **Location:** `Modules/{Pdf,Photo,Space,Audio,Character,Rule,Dice,Generator,Map,Table,Weather,Adventure}RPG/Intent/*Entity.swift`, ~170-220 lines each (spot-checked `DiceEntity.swift` at 213 lines and `CharacterEntity.swift` at 176 lines this round — near-identical `EntityQuery`/`IndexedEntity`/`SyncableEntity` conformances differing only in type names)
- **What:** No shared generic CoreRPG base exists; each module hand-copies the same `EntityQuery`/`IndexedEntity` boilerplate.
- **Why:** Round 9 investigated and deliberately deferred a fix — Apple's `AppIntents` framework has real generic/associated-type constraints that risk a subtle Siri/Shortcuts/Spotlight regression a plain `xcodebuild build` wouldn't catch, needing device-level verification outside a static audit's scope.
- **Action:** Pull `EntityQuery`/`IndexedEntity` conformance into a shared generic CoreRPG base, verified against a real device/simulator's Siri/Shortcuts/Spotlight surface, not just a compile check.
- **Severity:** Medium (carried forward, deliberately deferred)

### 9.4 Widespread `ID`/`URL` casing violates the project's `Id`/`Url` convention — carried forward and substantially expanded in scope
- **Location (representative, ~460+ total occurrences across the app, per this round's full sweep — round 9 §9.10 scoped only two subsystems by name):**
  - `Modules/CoreRPG/Persistence/FilePersistenceController.swift:117,121` (`fileURL`/`oldFileURL`) — CoreRPG's own foundational file-persistence type uses the exact wrong-cased name CLAUDE.md cites as its counter-example.
  - `Modules/CoreRPG/Sheet/SheetModel.swift:70,224,225,227,284` (`generatedBatchID`, `rootItemID`, `parentModelID`, `selectedModelID`, `lastAcceptedEntryID`) — a whole shared model file.
  - `Modules/GameRPG/Statistics/Model/GameStatisticsTypes.swift:244-316,441-444` (~13 properties, e.g. `characterID`, `adventureID`, `participantID`) — systematic across the file.
  - `Modules/GameRPG/Controller/MasterController.swift:147-150,237,351,887-888,1249-1260` (`deliverySessionID`, `existingPlayerID`, `messageID`, `wireID`, `deliveryID`) — mixed with correctly-cased `Id` parameters elsewhere in the *same* 2856-line file.
  - `Modules/SpaceRPG/Record/ShotFileInfo.swift:21` — `shotID` bound from the already-correctly-named `parseShotId(url:)`.
  - Round 9's originally-cited subsystems (`FoundryVTTImportReader.swift`, `RuleEntryTree.swift`, `GameNetworkModel.swift`/`GameRelayAdmission.swift`, `RootURLHandler.swift`) remain unchanged and are folded into this total.
  - Full breakdown: ~271 `var`/`let ...ID` declarations across 55 files (185 outside Foundry/VTT import code, i.e. in first-party domain/controller/model code) and ~56 `var`/`let ...URL` declarations across ~35 files (39 outside Foundry code); function/parameter labels add roughly 175 more occurrences.
- **What:** A repo-wide, word-boundary-aware grep (not a substring match) for `ID`/`URL`-suffixed `var`/`let`/parameter declarations.
- **Why:** Round 9 scoped this to two subsystems (Foundry import + GameRPG networking) and deferred a rename there, reasoning the wire-format/Codable risk didn't justify a blind mechanical sweep. This round's full-repo pass shows the violation is not confined to those two subsystems — it recurs in foundational, first-party CoreRPG types with no wire-format risk at all (`FilePersistenceController`, `SheetModel`), which changes the risk calculus for at least a partial fix.
- **Action:** Prioritize a compiler-assisted rename for the wire-format-risk-free sites first (`FilePersistenceController`, `SheetModel`, `GameStatisticsTypes` — plain Swift properties, no `CodingKeys`/Core Data attribute-name entanglement to worry about, unlike round 9's §9.11 `sessionID` fix which needed exactly this care). Leave the Foundry-import and GameRPG-networking wire-format subsystems deferred, per round 9's existing reasoning.
- **Severity:** Medium (carried forward, larger confirmed footprint)

### 9.5 Two small, low-risk CoreRPG cleanups
- **Location:** `Modules/CoreRPG/CRDT/DecoderPool.swift:1-19` (dead actor — `getDecoder()` returns `JSONDecoder()` fresh every call, no actual pooling, zero references anywhere); `Modules/CoreRPG/CRDT/CRDT.swift:43,50,61` (`restore(from:)`, `converter(initialValue:defaultValue:)`, and the `rawValue` getter each allocate fresh `JSONEncoder()`/`JSONDecoder()` instead of the shared `JSONCoding.encoder`/`.decoder`, with no documented reason unlike sibling files that explain their custom-instance need)
- **What/Why:** `@CRDT` wraps individual fields on model types synced across every network merge/import — exactly the hot, repeatedly-called path the project's own `JSONCoding.swift` doc comment says should use the shared instances.
- **Action:** Delete `DecoderPool.swift`; replace the three fresh instances in `CRDT.swift` with `JSONCoding.decoder`/`.encoder`. Quick win — see §2.
- **Severity:** Low

### 9.6 Two dead symbols left over from refactors
- **Location:** `Modules/MapRPG/View/DisplayConfigEditor.swift:18` (`@State private var showTileEditor = false`) and `:168-170` (`saveTileCoordinates(_:)`); `Modules/DiceRPG/Intent/RollSpecificDiceIntent.swift:67-87` (`formatValues(results:sumUp:modifier:)`)
- **What:** None of the three symbols are read/written/called anywhere else — verified by grep. Tile editing now routes through a separate `MapEditorRoute.mapTileEditor` screen; the dice-intent dialog is now built directly via a `switch` in `perform()`.
- **Action:** Delete all three. Quick win — see §2.
- **Severity:** Low

### 9.7 `AGENTS.md` has drifted from `CLAUDE.md` and contains a wrong iCloud container identifier
- **Location:** `/AGENTS.md:156` (`iCloud Container: iCloud.de.andretrettin.MasterRPG`) vs. `/CLAUDE.md`'s equivalent line and every actual entitlements file (`Resources/*.entitlements`, `Sources/RPGShare/*.entitlements`), all of which use `iCloud.de.andretrettin.gamemaster` — confirmed by direct read of all six entitlements files
- **What:** `AGENTS.md` is a near-duplicate of `CLAUDE.md` (both provide "guidance to Claude Code... in this repository") that has fallen out of sync: besides the wrong container identifier, it has numerous typos absent from `CLAUDE.md` (`manipluate`, `groupes`, `Moduls`, `layoput`, `Sturcture`, `Intentm`, `Shrotcuts`, `LOcalaizations`) and is missing `CLAUDE.md`'s newer sections (naming-convention note, `Xcode MCP` tool guidance is present in both but `AGENTS.md` lacks the Id/Url casing rule entirely).
- **Why:** Both files are read as project instructions by AI coding agents; a stale, wrong identifier in one of the two active instruction files risks an agent editing entitlements or documentation based on incorrect information, and the missing casing rule in `AGENTS.md` means an agent that happens to load it instead of `CLAUDE.md` won't know about the Id/Url convention this very report spends §9.4 on.
- **Action:** Either delete `AGENTS.md` if `CLAUDE.md` is the sole source of truth, or resync it (correct the container identifier, fix the typos, add the missing casing rule) and establish which file is authoritative going forward. Quick win — see §2.
- **Severity:** Low

### 9.8 `RuleRPG` module is fully wired into the app but entirely absent from `CLAUDE.md`'s "Key Modules" documentation
- **Location:** `CLAUDE.md` "Key Modules" section (no `RuleRPG` entry, in either this file or `AGENTS.md`); actual wiring confirmed at `Modules/RolePlayGameKit/Route/RouteDestinationView.swift:56`, `WindowRouter.swift`, `ExtendedTabRouteDestinationView.swift:45`, `Modules/RolePlayGameKit/Model/AppModel.swift`, `Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift` (projects Foundry rule compendiums into "an editable RuleRPG hierarchy"), `Sources/MasterRPG/MasterRPGSpotlightIndexer.swift`, `Sources/MasterRPG/Menu/MenuCommandList.swift`, plus a linked `RuleRPG.framework` and `RuleRPGTests` target in `MasterRPG.xcodeproj`
- **What:** RuleRPG (44 Swift files, the full Controller/Intent/Menu/Model/Resources/Root/Route/View structure like every documented module) is a live, first-class item type imported by AdventureRPG, GameRPG, and RolePlayGameKit — as deeply integrated as any documented module — yet undocumented. Independently confirmed compliant with the project's `@MainActor` mandate (this round's concurrency agent read every `@Observable` declaration and controller in the module).
- **Why:** A developer or AI agent reading `CLAUDE.md` to understand the module map would not discover RuleRPG exists.
- **Action:** Add a "RuleRPG" entry to `CLAUDE.md`'s Key Modules list, e.g. "RuleRPG: manages an editable, importable rules/compendium hierarchy normalized from sources like Foundry VTT system packages; linked from AdventureRPG, GameRPG search/logging, and RolePlayGameKit navigation."
- **Severity:** Low

### 9.9 Oversized files (>1000 lines) — split proposals
- **`Modules/GameRPG/Controller/MasterController.swift` (2856 lines):** Lines 1-1353 are the session/delivery-tracking core (`MasterControllerModel`, `Control`, `Send Messages`, `MasterNetworkStoreDelegate`); 1354-2479 is one `extension MasterController` dispatching to 9 independent per-domain-module handlers (`handleAudio`, `handleDice`, `handleGame`, `handleMap`, `handlePdf`, `handlePhoto`, `handleTable`, `handleValue`, `handleWeather`, `handleSpace`); 2481-2832 is the already-MARK-delimited "Proxy host routing" block. **Action:** extract each `handleX` block into its own `MasterController+XMessages.swift` extension file (mechanical, low-risk — pure extensions, no stored properties). **Severity:** Low.
- **`Modules/RolePlayGameKit/Import/Foundry/FoundryVTTDomainMapper.swift` (2602 lines):** Already cleanly MARK-delimited into 7 `private extension FoundryMappingState` blocks ("Indexes and folders," "Rules," "Assets," "Document dispatch," "Scene conversion," "Dice and values," "Shared conversion helpers"). **Action:** move each block into its own file named after its MARK title — the lowest-risk of the oversized files to split, since each is self-contained. **Severity:** Low.
- **`Modules/GameRPG/SharePlay/RPGSharePlayController.swift` (2595 lines):** This file's own header already documents that a prior audit (§9.10) considered and *rejected* a physical split given the cross-references a full split would need to untangle — not re-proposed here. The one exception: the trailing `extension RPGSharePlayController` at lines 2534-2595 ("visionOS spatial template configuration") is fully self-contained, platform-gated, and wasn't part of the original split-rejection's stated concern. **Action:** optionally extract only that ~60-line block into `RPGSharePlayController+SpatialTemplate.swift`. **Severity:** Low.
- **`Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift` (2494 lines):** Unlike the DomainMapper file, has zero `// MARK:` dividers across 25 private/internal types, including a wholly separate `.mrpgfoundry` "Bridge" format decoder (`FoundryBridgeDecoder` + 4 supporting types, ~480 lines at 2015-2494) mixed in with the native Foundry VTT pipeline. **Action:** add MARK dividers first, then split out the self-contained Bridge decoder into its own file at minimum. **Severity:** Low.
- **`Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift` (1235 lines):** Same bag-of-private-types pattern as above, smaller scale (11 private types, no MARK separation). **Action:** split into `+DataSource.swift`, `+TemplateAndCompendiumDecoding.swift`, `+ReferenceAndAssetResolution.swift`. **Severity:** Low.
- **`Modules/GameRPG/Table3D/GameTableModel.swift` (1199 lines):** Unlike the Foundry files, its 9 MARK sections are inside one class body with stored properties interleaved throughout rather than concentrated at the top (e.g. `fogOfWarTask`/`mapChangeTask` live inside the "Map Sync & Fog of War" section). **Action:** consolidate stored properties to the top of the class first (a real prerequisite the other files don't need), then convert each MARK section into its own `extension` file. **Severity:** Low.

### 9.10 Cross-platform duplication inside a single file
- **Location:** `Modules/GameRPG/Table3D/GameTableView.swift:93-626` (visionOS `struct GameTableView: View`) vs. `:639-1089` (a *second*, iOS/macOS `struct GameTableView: View` in the same file)
- **What:** `performRoomAction(_:)` (135-138 and 791-794), `isViewportPanStale()` (143-146 and 799-802), and their backing state (`viewportPanLastUpdate`, `roomActionTask`, `staleGestureTimeout`) are byte-for-byte identical between the two platform-specific struct bodies — confirmed by diffing the two ranges directly.
- **Why:** None of this is platform-specific (pure task-cancellation/staleness bookkeeping); a tuning change made to one copy and not the other silently diverges behavior between platforms.
- **Action:** Extract a small reusable value type (e.g. `StaleGestureTracker`) and a free helper, used via composition from both platform structs instead of duplicating the 4 members verbatim.
- **Severity:** Medium

### 9.11 Three `DetailFolderListView.swift` files independently re-implement the same bottom-overlay-bar workaround
- **Location:** `Modules/AudioRPG/View/DetailFolderListView.swift:20-25`, `Modules/WeatherRPG/View/DetailFolderListView.swift:25-30`, `Modules/DiceRPG/View/DetailFolderListView.swift:24-29` (the other 8 modules' `DetailFolderListView.swift` files were diffed pairwise and confirmed to be legitimate thin wiring around the shared `DetailFolderList` component — not a duplication problem)
- **What:** All three carry an identical multi-line comment explaining why they bypass the shared `DetailFolderList`, then independently implement the same `ItemDetailRootView { editor }` + `safeAreaInset(edge: .bottom)` + `.overlay(alignment: .bottom)` + `.openFileWindowOverlay(...)` stack.
- **Why:** The same stacking-order-sensitive divergence is now maintained three times independently; a future fix to the overlay-ordering behavior must be applied in three places.
- **Action:** Extract a shared parameter (e.g. `ItemDetailRootView(..., bottomOverlayBar: { ... })`) that inserts the bar between the editor and the file-window overlay, then delete the three bespoke copies.
- **Severity:** Medium

### 9.12 Smaller duplication: thumbnail creation and preview-data loading
- **Location:** `Modules/PdfRPG/Controller/CacheController.swift:18-30` vs. `Modules/SpaceRPG/Controller/CacheController.swift:14-29` (near-identical 5-line `createThumbnail(for:item:)` bodies, differing only in a size constant and one boolean flag); `Modules/AdventureRPG/Model/PreviewData.swift:45-56`, `CharacterRPG/Model/PreviewData.swift:42-53`, `DiceRPG/Model/PreviewData.swift:48-59`, `GeneratorRPG/Model/PreviewData.swift:36-47`, `MapRPG/Model/PreviewData.swift:47-58` (5 near-identical `#if DEBUG` "load example `.gmz`" boilerplate blocks)
- **What/Why:** Small, low-risk consolidation opportunities — `ImageCacheControllable`'s own doc comment asserts `createThumbnail`'s body is "genuinely module-specific," which is no longer true for these two modules specifically.
- **Action:** Add a default `ImageCacheControllable` implementation parameterized by `thumbnailSize`/`removeWhiteBackground` for the first; extract a shared `PreviewData.loadExampleData(into:)` `#if DEBUG` helper in CoreRPG for the second.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **The per-module boilerplate genericization has now persisted across 10 full audit rounds for `GameController` (§9.1) and 9+ rounds for AppIntent `Entity` types (§9.3).** This remains the single highest-leverage mechanical refactor available in the codebase, and its persistence across this many rounds — in a codebase that otherwise remediates findings same-day or next-day (see the remediation table in `Docu/CODE_AUDIT_9.md`) — suggests it needs to be explicitly budgeted as its own project rather than opportunistically picked up.
2. **§9.4's expanded `ID`/`URL` casing footprint changes the risk calculus round 9 used to defer it.** Round 9 deferred a rename because the two subsystems it found (Foundry import, GameRPG networking) carry wire-format/Codable risk. This round found the violation is at least as common in plain, wire-format-risk-free Swift properties (`FilePersistenceController`, `SheetModel`, `GameStatisticsTypes`) — a compiler-assisted rename of just those is far lower-risk than the originally-scoped subsystems and could ship independently of the harder, still-deferred wire-format half.
3. **Two of this round's three genuinely new findings (§5.1, §6.1) are both about tvOS silently not honoring the app's cross-device sync promise, through two independent mechanisms (Core Data flag, file entitlement).** Given both compound into the same user-visible symptom ("my data doesn't show up on Apple TV"), they're worth fixing — or explicitly documenting as an accepted tvOS limitation — together rather than as two separate tickets.
4. **Apply the cancel-then-replace-with-generation-token pattern to `resetPlayers()` (§3.1) the way `fogOfWarTask`/`mapChangeTask` already do elsewhere in `GameRPG`.** This is the same class of "properly-MainActor-isolated but still logically racy across an `await`" bug this codebase's own history shows recurring (see prior health-sync and map-change races, both fixed with exactly this pattern) — `resetPlayers()` is the one remaining unfixed instance identified so far.
5. **This round found meaningfully fewer new issues than round 9 did relative to round 8**, and every new item required deep, specific verification rather than a broad grep turning up violations — a sign the sweep-based full-codebase-audit approach is reaching diminishing returns for this codebase's general code quality. Future rounds may get more value from narrower, subsystem-scoped deep-dives (as `Docu/CODE_AUDIT_Game.md`, `_BattleRound.md`, etc. already demonstrated) than from repeating the same full-repo sweep.

---

## 11. What was NOT audited

- **Algorithmic correctness** of the Foundry VTT domain-mapping logic, 3D/RealityKit rendering math, and CRDT merge semantics — structural/duplication/dead-code/concurrency aspects only were reviewed.
- **Build settings, scheme configuration, and Xcode project structure** beyond what's visible via the five schemes built for this round's warning capture (`MasterRPG`, `MasterMac`, `MasterTV`, `DiceRollerWidgetExtension`; `RPGShare` was not independently built this round).
- **Third-party SPM dependency internals** (`swift-custom-dump`, `swift-syntax`, `swift-snapshot-testing`, `xctest-dynamic-overlay`) and the vendored `NavigatorUI` package, beyond the two `@available`/dead-branch citations in §3.2/§3.3.
- **Deep test-coverage assessment.** `Tests/` was scanned for dead-code cross-references and print-statement hygiene, not reviewed for coverage gaps or test quality. Known pre-existing test failures (a `ConverterController` re-hide test, a `FileUrl` double-path test, a cloud read-back family, and a `GameRPGTests` TSan crash) were not re-investigated — tracked separately as known, non-regressions.
- **Localization wording quality** — `Docu/LOCALIZATION_ACCESSIBILITY_AUDIT.md` (2026-07-16) exists as a dedicated prior pass and was not re-run; this round's SwiftUI pass only did a fast structural sweep (hardcoded font sizes, hardcoded colors) and found nothing new.
- **Performance profiling via Instruments.** §7's findings are based on static source reading (in two cases, confirmed against the code's own doc comments describing the exact waste), not captured traces.
- **StoreKit 2 / IAP** — not independently re-checked this round; round 9 spot-checked it and found correct, modern API usage.
- **Full re-verification of all findings across the 16 prior `Docu/CODE_AUDIT_*.md` documents.** This round re-verified the specific items round 9 marked deferred/still-open (see the table at the top) rather than re-opening every historical line.
- **Entitlements files beyond the ubiquity-container gap in §6.1** — not otherwise re-reviewed (e.g. the Debug/Release entitlement-pair split itself, already tracked in project memory, was not re-audited).
- **visionOS/tvOS/macOS platform-conditional branches** beyond what surfaced incidentally in files read for other findings, and beyond the post-round-9 diff (which was read in full).

---

## 12. Verification

- **§3.1** — open `Modules/GameRPG/Controller/MasterController.swift:581-634` (`resetPlayers`), then `:1068-1079` (`lostPlayer`, confirm it's called directly from `Modules/GameRPG/Network/GameNetworkController.swift:260,371`, not through `messagePipeline`), then `:1120-1134` (`process(_:)`'s call inside the `messagePipeline`-drained loop). Cross-check `Modules/GameRPG/Root/GameRootModel.swift:447-456` and confirm `scheduleNetworkAction` (`:471-483`) is a separate serial chain with no shared lock against `messagePipeline`.
- **§5.1** — open `Modules/RolePlayGameKit/Model/AppModel.swift:229-249`; confirm the `#if os(tvOS)` branch (line 231) hardcodes `useCloudKit: false` while the `#else` branch (line 249) reads `settingsModel.useCloudKit`. Then open `Modules/RolePlayGameKit/Route/RouteDestinationView.swift:59-62` and confirm `.settings` has no `#if os(tvOS)` exclusion (contrast with `.generator` at lines 43-48, which does).
- **§6.1** — open `Resources/MasterTV-Debug.entitlements` and `Resources/MasterRPG-Debug.entitlements` side by side; confirm the former lacks `com.apple.developer.ubiquity-container-identifiers` and `CloudDocuments` (present in the latter). Then open `Modules/CoreRPG/App/AppGroup.swift:40,49-51` and confirm `preferredRootUrl` falls back to `groupURL` when `cloudURL` is `nil`.
- **§7.1** — open `Modules/GameRPG/Table3D/GameTableModel.swift:557-558` (confirm `renderSignature` hashes `viewportPan.x`/`.y`), `:583-585` (confirm `boardFocusRect`'s `panOffset` parameter is named `_` and unused), and `:605-613` (read `panViewport(by:)`'s own doc comment, then confirm the function body still calls `replaceFogOfWarTask`).
- **§7.2** — open `Modules/GeneratorRPG/BasicAI/Providers/PdfContentExtractor.swift:60-75`; confirm `LanguageModelSession(instructions:)` and `.prewarm()` are both inside the `for page in extractedText` loop.
- **§8.1** — open `Modules/CoreRPG/ItemList/ItemDataModel.swift:28`; confirm `itemData` is a plain `[UUID: ModelType]` on an `@Observable` class. Full verification detail already in `Docu/CODE_AUDIT_9.md` §12.
- **§9.1** — `wc -l` the six cited `GameController.swift` files; confirm Rule/Generator are 8-line typealiases and Dice/Character/Space/Map are 400-600+ lines each.
- **§9.2** — open `Modules/GameRPG/Controller/MasterController.swift:1861,2005,2282` and confirm `handlePdf`/`handlePhoto`/`handleSpace` start at those lines with near-identical bodies; open `PlayerController.swift:216,275,333` for the player-side triplication.
- **§9.4** — open `Modules/CoreRPG/Persistence/FilePersistenceController.swift:117,121`; confirm `fileURL`/`oldFileURL` casing. Open `Modules/CoreRPG/Sheet/SheetModel.swift:70,224,225,227,284` for the second example.

If any finding doesn't reproduce when you visit the line, flag it with the specific reference and it'll be re-investigated in the next round.
