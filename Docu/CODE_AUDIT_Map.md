# MapRPG Code Audit

Generated 2026-09-17. Scope: `Modules/MapRPG/` only — 97 Swift files, ~17,250 LOC, no `.metal` kernels. No `Dead/` or other archived directory exists under this module, so nothing was excluded on that basis. Other modules (CoreRPG, GameRPG, etc.) were read **read-only**, for comparison and call-site verification, but are not themselves in scope.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

**Headline result:** a clean full-module build (after touching every file to force recompilation) produced **zero compiler warnings** — this module is unusually disciplined about Swift 6 strict concurrency and API modernity, and it shows: almost every `@Observable` class is already correctly `@MainActor`-isolated, there is no `DispatchQueue` usage, no `ObservableObject` stragglers, and SwiftUI correctness-checklist violations (private `@State`, `ForEach` identity, `.animation(value:)`) are absent throughout. The real findings cluster in two places instead: (1) one genuine, verified **Critical** privacy/security gap in the fog-of-war network payload, and (2) a family of near-identical logic (hex-grid math, pin placement, bounding-box computation) independently reimplemented 2-6 times across `EditController`, `MapEditController`, and `MapEditorModel` — which also produced one real, verified logic bug.

---

## 1. Executive summary

1. **[Critical] GM-only hidden content is broadcast to Player devices unfiltered** — §6.1 — `Modules/MapRPG/Model/MapSnapshot.swift:10-29`. Hidden room text, hidden-pin names/photos/character links are fully present in every live map push a Player receives; only client-side rendering hides them.
2. **[High] `preconditionFailure` crashes reachable from a real CloudKit-merge race** — §5.2 — `Modules/MapRPG/Model/DataModel+Extensions.swift:31-79`. A concurrent delete during CloudKit sync can nil out `managedObjectContext` mid-merge and crash the process in Release.
3. **[High] Hex-grid placement math is duplicated verbatim across two controllers** — §9.2 — `Controller/EditController.swift:408-452` vs `Map/MapEditController.swift:535-580`. Already visibly drifted stylistically between the two copies.
4. **[Medium] Bulk pin auto-placement drifts diagonally instead of laying out in a row** — §5.1 — `Map/MapEditController.swift:468-479`. A `CGPoint + CGFloat` operator adds the offset to both axes, not just X.
5. **[Medium] `MapModel`'s `Equatable`/`Hashable`/merge conformances trade a compile-time isolation guarantee for a runtime trap** — §3.2 — `Model/MapModel.swift:404-746`.
6. **[Medium] Pin-cascade placement and monster-spawn batching are triplicated** — §9.3/§9.4 — across `EditController.swift`, `MapEditController.swift`, `MapEditorModel.swift`.
7. **[Medium] `[CGPoint]` bounding-box computation is reimplemented six times** — §9.6 — spans `Model/`, `Map/`, and `View/`.
8. **[Medium] `MapModel`'s image-rotation math reimplements `CoreRPG.ViewportGeometry`** — §9.7 — `Model/MapModel.swift:276-356`.
9. **[Medium] Per-pin `BattleRoundModel` lookups run on the live render path** — §7.1 — `Map/MapPinView.swift:445-462`, compounding an existing O(n) scan into an effective O(n²) per canvas redraw during battle.
10. **[Medium] Two dead, legacy-API code paths and one dead ~90-line codegen family** — §9.1/§9.9 — `Extensions/UIImage+Crop.swift:28-45`, `Model/PreviewData.swift`.

---

## 2. Quick wins (≤30 min each)

- **Fix the German-spelling user-facing string** — `Controller/EditController.swift:336`. `String(localized: "Updated pin from charakter", ...)` → "character"; this seeds the base localization catalog.
- **Fix the `Addtional`→`Additional` typo** — `View/AddtionalEntryRow.swift` (struct + file name), referenced from `Controller/EditController.swift:103`, `View/InlineRowViewer.swift:30`, and a generated snapshot-test name; rename and regenerate via `Scripts/generate_snapshot_tests.rb`.
- **Swap `localizedCaseInsensitiveContains` → `localizedStandardContains`** — `Model/MapPinModel.swift:203`, `Model/MapModel.swift:630`. `MapEntryModel.filter(with:)` already does this correctly; CLAUDE.md mandates it for user-typed search filtering.
- **Delete the dead `generateModel()`/`generateUUID()`/`generateCoords()`/`generatePoints()` codegen family** — `Model/PreviewData.swift:216-256, 355-374, 416-452`. ~90 lines, zero call sites anywhere in the repo.
- **Delete `AKImage.crop(in:)`** — `Extensions/UIImage+Crop.swift:28-45`. Unused, and uses the pre-`UIGraphicsImageRenderer` legacy pattern CLAUDE.md explicitly asks to avoid.
- **Delete the unused `MapEntryCacheImageMapper` actor** — `Controller/CacheController.swift:13-15`. Never referenced.
- **Log the swallowed Spotlight-indexing error** — `Intent/MapShortcutCatalog.swift:84`. `try? await CSSearchableIndex.default().indexAppEntities(entities)` silently drops failures; `OpenMapIntent.swift:50-52` already shows the logging pattern to match.
- **Replace `Circle()`/`Rectangle()`/`RoundedRectangle(cornerRadius:)` struct instances with static member lookup** (`.circle`, `.rect`, `.rect(cornerRadius:)`) — 11 sites across `Map/NeedleMapPin.swift`, `Map/MapEditor.swift`, `Map/MapEditorCanvas.swift`, `Map/EditMapToolBar.swift`, `Map/MapPinView.swift`, `Map/MapEditorOverlayLayer.swift`, `View/DisplayConfigEditor.swift`.

---

## 3. Concurrency

### 3.1 Unnecessary `Task` wrapping synchronous main-actor work
- **Location:** `Modules/MapRPG/Map/AnimatedMap.swift:36-40`
- **What:** `.onChange(of: date, initial: false) { Task { withAnimation { entryId = randomEntries() } } }` spawns a `Task` even though `randomEntries()` is synchronous and nothing inside `await`s.
- **Why:** The view body/`onChange` already runs on the main actor; the `Task` adds a pointless scheduling hop and misleadingly signals async work to future readers.
- **Action:** Drop the `Task { }` wrapper and call `withAnimation { entryId = randomEntries() }` directly inside the `onChange` closure.
- **Severity:** Low

### 3.2 `MapModel`'s Equatable/Hashable/Comparable/merge conformances rely on a runtime isolation trap
- **Location:** `Modules/MapRPG/Model/MapModel.swift:404-411` (`Comparable <`), `:482-525` (`merge(_:)`), `:527-574` (`isSame`/`version`), `:735-746` (`==`/`hash(into:)`)
- **What:** `MapModel` conforms `nonisolated` to `Equatable`, `Hashable`, `Comparable`, and `ItemDiffComparable`, but the bodies of `==`, `merge`, and `isSame` reach the class's `@MainActor`-isolated stored properties through an `assumeMainActorIsolated { … }` helper (a `MainActor.assumeIsolated`-style trust-the-caller wrapper).
- **Why:** Because the conformances themselves are declared `nonisolated`, nothing at compile time stops a future background-context call (e.g. from a Core Data background `context.perform` block, or a `.sorted()`/`Set` operation run off-main) — it would compile cleanly and then hit a runtime precondition failure instead of a compile-time isolation error. No in-module call site currently misuses this, but the safety guarantee is deliberately weakened repo-wide (see project memory: all 11 module models use this MainActor-model pattern).
- **Action:** Either keep the pattern but document/audit every call site as MainActor-only (true today), or replace the `nonisolated` protocol conformances with `@MainActor`-gated equivalent methods so a stray background call fails to compile instead of crashing at runtime.
- **Severity:** Medium

---

## 4. API modernity

### 4.1 User-input filtering bypasses `localizedStandardContains()`
- **Location:** `Modules/MapRPG/Model/MapPinModel.swift:203`, `Modules/MapRPG/Model/MapModel.swift:630`
- **What:** Both filter user-typed search text with `localizedCaseInsensitiveContains(filter)` instead of `localizedStandardContains()`.
- **Why:** CLAUDE.md mandates `localizedStandardContains()` for user-input filtering (word-boundary/diacritic-insensitive matching); the sibling `MapEntryModel.filter(with:)` (`MapEntryModel.swift:148`) already does it correctly, so these two are inconsistent with the rest of the module.
- **Action:** Replace both call sites with `localizedStandardContains`.
- **Severity:** Medium

### 4.2 Struct-shape instances instead of static member lookup
- **Location:** `Modules/MapRPG/Map/NeedleMapPin.swift:262,312,343`; `Map/MapEditor.swift:315`; `Map/MapEditorCanvas.swift:181`; `Map/EditMapToolBar.swift:656`; `Map/MapPinView.swift:478,496,515`; `Map/MapEditorOverlayLayer.swift:279`; `View/DisplayConfigEditor.swift:176`
- **What:** `Circle()`, `Rectangle()`, and `RoundedRectangle(cornerRadius: 8)` are constructed as explicit struct instances rather than through `.circle`, `.rect`, `.rect(cornerRadius:)`.
- **Why:** CLAUDE.md explicitly calls out this exact preference (`.circle` over `Circle()`) as a repo-wide rule; these 11 sites are the only places in the module that don't follow it.
- **Action:** Replace each with the equivalent static member wherever the call site accepts `some Shape`/`ShapeStyle`.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Bulk pin auto-placement drifts diagonally instead of laying out horizontally
- **Location:** `Modules/MapRPG/Map/MapEditController.swift:468-479` (`calculatePinLocations`); `Controller/EditController.swift:368-380` (`calculateLocations`); `Map/MapEditorModel.swift:302-317` (`resetPlayerAndPins`) — see also the duplication finding at §9.3
- **What:** All three implementations space out newly-dropped pins via `leftCenter = leftCenter + updated.size.size.width * scale + 5`. `CGPoint + CGFloat` (verified at `Modules/CoreRPG/Extensions/CGPoint+Operators.swift:22-24`) adds the scalar to **both** x and y, so each successive pin's Y coordinate also creeps downward even though the intent (per the `leftCenter` name and the room-left-edge starting point) is a horizontal-only row.
- **Why:** Dropping several monsters at once (e.g. via the character picker, capped at 25 — see §9's magic-constants item) produces pins that walk diagonally down-and-right instead of forming a row, and for a large batch can push pins outside the room polygon or off-canvas.
- **Action:** Use an explicit x-only offset (`CGPoint(x: leftCenter.x + delta, y: leftCenter.y)`) at all three sites; fix once when consolidating the triplicated function per §9.3.
- **Severity:** Medium

### 5.2 `preconditionFailure` crashes reachable from a CoreData/CloudKit background-sync race
- **Location:** `Modules/MapRPG/Model/DataModel+Extensions.swift:31-39` (`RPGMap.displyConfigOrNew`), `:48-53` (`RPGMapEntry.newCoordinate`), `:62-67` (`RPGDisplayConfig.newCoordinate`), `:70-79` (`RPGMapPin.coordinateOrNew`); called from `Modules/MapRPG/Controller/DataController.swift:60-102` (`@Sendable func applySnapshot(_:into:)`, explicitly marked "context queue" — i.e. not guaranteed main-actor)
- **What:** Each helper calls `preconditionFailure(...)` (compiled into Release, unlike `assert`) if `managedObjectContext` is `nil` when a new child managed object needs to be created.
- **Why:** If the parent managed object is deleted — e.g. by a concurrent CloudKit merge from another device, or a cascade delete — in the narrow window between being fetched and one of these closures running, `managedObjectContext` becomes `nil` and the entire app crashes instead of the sync simply skipping or retrying that record. This is a real, live-session risk for an app whose core feature is multi-device CloudKit sync during a shared game session.
- **Action:** Replace `preconditionFailure` with a graceful bail-out (skip the object, log, and let the next sync pass reconcile it); reserve `preconditionFailure` for invariants that truly cannot occur from timing.
- **Severity:** High

### 5.3 Swallowed Spotlight indexing error
- **Location:** `Modules/MapRPG/Intent/MapShortcutCatalog.swift:84`
- **What:** `try? await CSSearchableIndex.default().indexAppEntities(entities)` discards any indexing failure with no logging.
- **Why:** Silent failure makes it impossible to diagnose why Map items stop appearing in Spotlight/Siri search without attaching a debugger.
- **Action:** Log the error on the `catch` path instead of `try?`, matching the pattern already used at `OpenMapIntent.swift:50-52`.
- **Severity:** Low

---

## 6. Security

### 6.1 GM-only hidden content is broadcast to Player devices unfiltered
- **Location:** `Modules/MapRPG/Model/MapSnapshot.swift:10-29` (no visibility filtering in the struct or its `init(_ model:)`); `Modules/MapRPG/Model/MapUpdatePayload.swift:20-29` (wraps the raw snapshot as the wire payload — only strips *runtime* battle/position state for fingerprinting, not visibility); `Modules/MapRPG/Controller/GameController.swift:326-395` (`shareMap`, `createMapGameData`, `networkMapContentUpdate`) and `Controller/GameController+Metadata.swift:125-174` (`mapContentCapture`, `currentMapReference`, `currentMapContentUpdate` — all build `MapUpdatePayload(model: item)` directly from the live model with **no recipient-role parameter**); `Controller/GameController+Pins.swift:180-203` (`missingMapImages` proactively fetches Photo bytes for every pin's `photoId`, including hidden pins, with no `isShown` check)
- **What:** The full "map content update" package — sent on initial map share to players and on every "Refresh Shared Map" push (`Map/EditMapToolBar.swift:583-591`) — serializes every `MapEntryModel.content` (room/DM notes text) and every `MapPinModel` (name, location, photoId, characterId) regardless of `entry.isShown`/`pin.isShown`. Verified by reading the full call chain: none of `shareMap`/`createMapGameData`/`networkMapContentUpdate`/`mapContentCapture`/`currentMapReference`/`currentMapContentUpdate` take a role or recipient parameter, and a repo-wide grep for their call sites shows they're invoked exclusively from `GameRPG`'s `MasterController+*.swift` files (the GM-device-to-player broadcast path) with no intervening filter. Client-side, hiding is purely cosmetic — confirmed at `Map/MapEditorCanvas.swift:600-603` (`MapPinLayerItem.isVisible` only gates *rendering*) and `Map/MapPinView.swift:477-481` (an `if !pin.isShown` overlay is drawn on top of, not instead of, the pin's already-fetched photo). `MapSnapshot.apply(to:)` (`MapSnapshot.swift:82-138`) then persists this into the player's own `MapModel`, so it's not even transient — it lands in the player's local CoreData store.
- **Why:** This is exactly the scenario the module exists to prevent. A player can read GM secrets (trap descriptions, hidden-monster stats and portraits, room notes) before the GM ever reveals them — via the Console app, a jailbroken/simulator device, or simply inspecting on-disk CoreData records — defeating the entire fog-of-war feature.
- **Action:** Before serializing a `MapSnapshot`/`MapUpdatePayload` for a non-master recipient, strip `content` on any `MapEntryModel` where `isShown == false` and strip/omit `name`/`photoId`/`characterId` on any `MapPinModel` where `isShown == false`. This requires threading an explicit recipient-role parameter into `createMapGameData(for:)`/`networkMapContentUpdate(for:)`/`shareMap(id:)` — the `MasterController` call sites already know whether the peer is master or player. `missingMapImages` must skip photo IDs belonging to hidden pins. The master's own device still needs the full data, so this redaction applies only to the outbound player-directed payload, never to the master's local `MapModel`.
- **Severity:** Critical

---

## 7. Performance

### 7.1 `BattleRoundModel` O(n) lookups run repeatedly, including from the per-pin render path
- **Location:** `Modules/MapRPG/BattleRound/BattleRoundModel.swift:85-99` (`combatant(id:)`, `combatant(pinId:)` — linear `first(where:)` scans); called from `synchronize(pins:additionalDefenders:)` (`:320-368`) and `sortEntries()` (`:468-484`), **and** from `Modules/MapRPG/Map/MapPinView.swift:445-462` (`MapPinContentView.isActiveBattleAttacker` and `.healthPercent`, both computed properties evaluated on every render of `MapPinContentView.body`)
- **What:** Every combatant/entry lookup is an O(n) scan, and it's not confined to background sync logic — `MapPinContentView`'s `body` (a per-pin SwiftUI view, one instance per pin on the map) calls `battleRoundModel.combatant(pinId:)` on every redraw to compute its health-ring color and attacker highlight.
- **Why:** During a running battle with N pins, a full canvas redraw (e.g. panning, zooming, or any single pin update) triggers up to N pin views each doing an O(n) scan — effectively O(n²) work per redraw. Not currently a measurable problem at the module's typical battle sizes (a handful to a couple dozen combatants), but it's on the live-play render path, which is more redraw-sensitive than the module's other O(n²) sync-path occurrences.
- **Action:** Maintain an `[UUID: Int]` (or `[UUID: Combatant]`) index dictionary on `BattleRoundModel`, invalidated on roster mutation, and have both the sync path and `MapPinContentView` read through it instead of scanning.
- **Severity:** Medium

---

## 8. SwiftUI / UI

_No correctness-checklist violations found._ A targeted pass over `Map/`, `View/`, `Root/`, and `BattleRound/` found: every `@State` is `private`; no `ForEach` keyed by `.indices`/`\.offset`; every `.animation(...)` call includes its `value:` parameter (`Map/NeedleMapPin.swift:317`, `Map/EditMapToolBar.swift:134`, `Map/GameToolBar.swift:42,115`, `Map/MapPinView.swift:521`, `View/DisplayConfigEditor.swift:38`); no bare `GeometryReader`; no `.fontWeight()` or hardcoded `.font(.system(size:))` usage. `MapPinView.swift` already extracts a separate `MapPinContentView` specifically to give SwiftUI its own diffing boundary (in-code comment references a prior "CODE_AUDIT §8.3"), indicating this module has already been through at least one SwiftUI-focused hardening pass. The one performance-relevant finding surfaced during this pass is filed under §7.1 (a per-pin render-path O(n) lookup), since it's a data-layer cost rather than a SwiftUI-pattern misuse.

---

## 9. Dead code / duplication / refactor

### 9.1 Dead, legacy-API image cropping code
- **Location:** `Modules/MapRPG/Extensions/UIImage+Crop.swift:28-45` (`AKImage.crop(in:)`, non-macOS branch)
- **What:** Uses `UIGraphicsBeginImageContextWithOptions`/`UIGraphicsGetCurrentContext`/`UIGraphicsGetImageFromCurrentImageContext`/`UIGraphicsEndImageContext()` — the pre-`UIGraphicsImageRenderer` legacy pattern. A repo-wide grep for `.crop(in:` found zero call sites; only the sibling `cropping(to:)` in the same file is actually used (by `CacheController.swift:43` and `DisplayConfigEditor.swift:97,101`).
- **Why:** Dead code that also happens to model the exact pattern CLAUDE.md asks to avoid ("always prefer `ImageRenderer` to `UIGraphicsImageRenderer`") — if copied as a starting point for new code, it propagates the wrong pattern.
- **Action:** Delete `crop(in:)`.
- **Severity:** Medium

### 9.2 Hex-grid math duplicated verbatim across two controllers
- **Location:** `Modules/MapRPG/Controller/EditController.swift:408-452` (`initHexGridSize`, `replaceHexGrid`, `calculateGrid`, `calculateHex`) and `Modules/MapRPG/Map/MapEditController.swift:535-580` (same four functions)
- **What:** Identical hex-width/height formulas, row/column counts, and six-corner hex-vertex calculation, one copy per controller. Verified side-by-side: `EditController`'s copy uses non-idiomatic `UpperCamelCase` locals (`Point1`...`Point6`), while `MapEditController`'s copy was refactored to a `clamp` closure with an array literal — the two copies have already drifted stylistically.
- **Why:** A grid-density or clamping change must be made in two places, and they're already out of sync stylistically, which is a leading indicator they'll drift functionally too.
- **Action:** Extract the four functions into one shared type (e.g. `MapHexGridGeometry`), have both controllers call it; this also resolves the `Point1...Point6` naming issue automatically by keeping only the cleaner copy.
- **Severity:** High

### 9.3 Pin cascade-placement algorithm duplicated three times
- **Location:** `Controller/EditController.swift:368-380` (`calculateLocations`), `Map/MapEditController.swift:468-479` (`calculatePinLocations`), `Map/MapEditorModel.swift:302-317` (`MapEditorSession.resetPlayerAndPins`)
- **What:** All three compute the same "start at `entry.xOffset + width/4, yOffset + height/2`, cascade each pin right by `pin.size.width * pinScale + 5`" placement — see the real bug this produces at §5.1.
- **Why:** The `+ 5` spacing and `width/4`/`height/2` offsets are unnamed and duplicated three times; any layout tweak must be applied in three places or silently diverges.
- **Action:** Extract to one static helper (e.g. `MapPinPlacement.cascade(pins:in:pinScale:)`); name the spacing/offset constants while doing so (see §9's magic-constants note below). Fixes §5.1 in the same pass.
- **Severity:** Medium

### 9.4 `addMonsters` pin-batch construction duplicated
- **Location:** `Controller/EditController.swift:342-366` and `Map/MapEditController.swift:438-466`
- **What:** Both build up to 25 `MapPinModel`s from an `[ItemRowModel]` of monsters (capped via `min(max(1, number), 25)`), assigning name/photo/color from `characterRoot`, then delegate to the (also-duplicated) placement helper above. `EditController`'s copy additionally has a dead commented-out line (`//model[entryId].content.append(values)`) at line 358.
- **Why:** The same monster-spawn rule, including the unexplained cap of 25, is implemented twice — one operates on the committed model, one on the editor's working copy — making it easy for the two paths to diverge further.
- **Action:** Factor the pin-construction loop into one shared static function parameterized on the target `MapModel`; keep only the persistence step (`save` vs `commitPinMutation`) distinct per caller. Remove the dead commented-out line.
- **Severity:** Medium

### 9.5 Duplicate size/rect validity checks
- **Location:** `Map/MapEditorModel.swift:564-569` (`MapEditorSession.isValidSize`) and `:709-714` (`MapCanvasGeometryResolver.isValid`) — same file; plus a third near-identical `isFiniteAndPositive` on `CGRect` at `Map/MapOverlayGeometry.swift:801-808`
- **What:** Three `isFinite && isFinite && >0 && >0`-style checks with different names, two of them in the same file.
- **Why:** Pure copy/paste; CoreRPG's `ViewportGeometry` already models this concept for the rotation math (see §9.7) — worth reusing rather than reinventing a third time.
- **Action:** Consolidate into one shared `CGSize`/`CGRect` validity helper.
- **Severity:** Medium

### 9.6 Bounding-box-from-points reimplemented six times
- **Location:** `Model/MapEntryModel.swift:90-112` (four separate O(n) passes for `xOffset`/`yOffset`/`width`/`height`), `Map/MapEditorModel.swift:684-699` (`overlayBounds`), `Map/MapOverlayGeometry.swift:449-467` (`centersBounds`) and `:428-447` (`framesBounds`), `View/DisplayConfigEditor.swift:87-93` (`loadTileImage`), `Map/MapRoomCanvas.swift:182-198` (`tileRectangle`)
- **What:** Six independent implementations of "compute min/max x and y across `[CGPoint]`, build a `CGRect`" — some via `.map{}.min()/.max()`, some via manual accumulation.
- **Why:** No shared `[CGPoint].bounds`/`CGRect(boundsOf:)` utility exists despite the pattern recurring across Model, Map, and View layers; `MapEntryModel` additionally does four separate O(n) passes instead of one.
- **Action:** Add one `extension Array where Element == CGPoint { var bounds: CGRect? }` (e.g. in `Extensions/CGPoint+Relative.swift`), replace all six call sites, and fold `MapEntryModel`'s four passes into one.
- **Severity:** Medium

### 9.7 `MapModel`'s rotation geometry reimplements `CoreRPG.ViewportGeometry`
- **Location:** `Model/MapModel.swift:276-356` (`canvasSize`, `imageSize`, `contentPointFromRotation`, `rotatedPoint`) vs `Modules/CoreRPG/Views/ViewportGeometry.swift:296-368` (`normalize`, `rotatedContentSize`, `rotatedPoint(fromContent:)`, `contentPoint(fromRotated:)`)
- **What:** `MapModel`'s four private statics hand-roll cardinal-angle (0/90/180/270) fast paths for the same rotation trigonometry `ViewportGeometry` already performs generically, falling back to `ViewportGeometry` only for non-cardinal angles.
- **Why:** Two independent implementations of rotation math that must stay numerically consistent — a future change to `ViewportGeometry`'s rotation convention won't automatically apply here.
- **Action:** If the cardinal-angle fast path is worth keeping for precision, move it into `ViewportGeometry` itself rather than keeping a second copy local to `MapModel`.
- **Severity:** Medium

### 9.8 `DisplayConfigEditor` reimplements the existing cross-platform cropping helper
- **Location:** `View/DisplayConfigEditor.swift:95-104` vs `Extensions/UIImage+Crop.swift:8-26` (`AKImage.cropping(to:)`)
- **What:** `loadTileImage()` hand-writes the same `#if os(macOS) ... cgImage(forProposedRect:) ... #else ... cgImage?.cropping ... #endif` branch that `AKImage.cropping(to:)` already encapsulates, then wraps the result back into a fresh platform image instead of using the `AKImage` it already has.
- **Why:** Exactly the cross-platform-cropping duplication the extension exists to prevent.
- **Action:** Replace the `#if os(macOS)/#else` block with `fullImage.cropping(to: tileRect)`.
- **Severity:** Medium

### 9.9 Dead ~90-line preview/fixture codegen family
- **Location:** `Model/PreviewData.swift:216-256` (`MapModel.generateModel/generateUUID/generateEntries`), `:355-374` (`MapEntryModel.generateModel/generateCoords`), `:416-424` (`DisplayConfigModel.testViewModel`), `:426-440` (`DisplayConfigModel.generateModel/generatePoints`), `:442-452` (`DisplayBorderViewModel.generateModel`)
- **What:** These print Swift source-literal representations of a model instance — a hand-run codegen tool for building fixtures. A repo-wide grep for `generateModel()` found zero call sites anywhere, including Scripts/ and Tests/. The rest of `PreviewData.swift` (`MapRootModel.preview`, `MapModel.preview*`, `MapEntryModel.preview*`, `MapPinModel.previewPins`) **is** actively used by `#Preview` blocks and `Tests/MapRPGSnapshotTests/` — only this specific pocket is dead.
- **Why:** ~90 lines of confirmed-unreachable code sitting inside an otherwise-live fixture file, easy to miss during cleanup.
- **Action:** Delete the `generateModel`/`generateUUID`/`generateEntries`/`generateCoords`/`generatePoints`/`testViewModel` members. If the codegen tool itself is worth keeping, move it to a `Scripts/` utility instead of shipping it in the module.
- **Severity:** Medium

### 9.10 Duplicated timestamp-bump logic bypasses the shared helper
- **Location:** `Map/MapEditorModel.swift:613-616` (`updatePointer`) and `Map/MapPinView.swift:245-248` (`MapPinViewModel.move`)
- **What:** Both reimplement `max(Date.now.timeIntervalSince1970, previous.nextUp)` inline instead of calling `GameController.bumpedTimeInterval(from:)` (`Controller/GameController+Metadata.swift:201-203`), which the rest of the codebase already centralized for this exact idiom (its own in-code comment references a prior "CODE_AUDIT §9.4").
- **Why:** A future change to the monotonic-timestamp policy (e.g. clock-skew handling) would need to be made in three places instead of one.
- **Action:** Expose `bumpedTimeInterval` more broadly and call it from both sites instead of reimplementing.
- **Severity:** Low

### 9.11 Dead unused actor
- **Location:** `Controller/CacheController.swift:13-15`
- **What:** `actor MapEntryCacheImageMapper { var entryToItem: [UUID: UUID] = [:] }` is declared but never referenced anywhere else in the module.
- **Why:** Dead code adds maintenance surface and can mislead readers into thinking it's part of the live cache-isolation design.
- **Action:** Remove it, or wire it into `CacheController`'s thumbnail work if it was meant to back that.
- **Severity:** Low

### 9.12 File name doesn't match its primary type
- **Location:** `Map/MapEditorModel.swift`
- **What:** The file's only two types are `MapEditorSession` (the `@MainActor @Observable` class — the bulk of the file) and `MapCanvasGeometryResolver`. No type named `MapEditorModel` exists anywhere in the module.
- **Why:** Hard to locate the type by filename, especially since "Model" suggests it holds domain types (`MapModel`/`MapEntryModel`) rather than editor/session state.
- **Action:** Rename the file to `MapEditorSession.swift` (and split out `MapCanvasGeometryResolver` per the oversized-file proposal below, since it has no dependency on `MapEditorSession` at all).
- **Severity:** Medium

### 9.13 Oversized files (>500 LOC) — split proposals
- **`Map/MapOverlayGeometry.swift` (821)** — already has three clean MARK-delimited sections (Needle Drag Geometry, Adaptive Fan Placement, Loupe Geometry). Split into `MapOverlayGeometry.swift` (needle drag + shared private `CGPoint`/`CGRect` helpers), `MapOverlayFanGeometry.swift`, `MapOverlayLoupeGeometry.swift` — hoist the shared private extensions (lines 783-821) into a small internal file first since more than one section depends on them. Severity: Medium.
- **`Model/MapModel.swift` (746)** — split into `MapModel.swift` (class body/inits/stored properties), `MapModel+Geometry.swift` (rotation math + toggle/focused), `MapModel+Sync.swift` (`ItemLinkRegistable`/`ItemDiffComparable` merge/isSame/version), `MapModel+DataAccess.swift` (`ItemDuplicatable`/`ItemReferencable`/`ItemDataAccessable`), `MapModel+Codable.swift` (`Codable`/`Equatable`/`Hashable`). Severity: Medium.
- **`Map/MapEditorModel.swift` (715)** — see §9.12; split `MapEditorSession` into `MapEditorSession.swift` (init/dependencies/pin-selection routing), `MapEditorSession+Toolbar.swift`, `MapEditorSession+Content.swift` (Entries/Pins Management), `MapEditorSession+Viewport.swift` (zoom/viewport-fit), and move `MapCanvasGeometryResolver` to its own file. Severity: Medium.
- **`Map/EditMapToolBar.swift` (664)** — already MARK-divided (`// MARK: - Extracted subviews (CODE_AUDIT §8.3)` at line 383). Move everything after that MARK into `EditMapToolBarButtons.swift`. Severity: Medium.
- **`Map/MapEditorCanvas.swift` (660)** — split into `MapEditorCanvas.swift` (core canvas/coordinate-space/transform types), `MapEditorCanvasGestures.swift` (gesture types), `MapEditorCanvasLayers.swift` (compositing layer views), `MapEditorCanvasPins.swift` (pin-layer views). Severity: Medium.
- **`Map/MapPinView.swift` (641)** — mixes an `@Observable` model layer (`MapPinInteractionEvent`, `MapPinNode`, `MapPinViewModel`, ~350 lines of non-SwiftUI logic) with the actual `View`. Move the model layer to `Map/MapPinViewModel.swift`; keep `MapPinView.swift` as the pure View file. Severity: Medium.
- **`Map/MapEditController.swift` (641)** — already MARK-divided into 8 sections. Split into `MapEditController.swift` (Working Copy Lifecycle + History), `+Tile.swift`, `+Sync.swift`, `+Pins.swift` (incl. Add Monsters), `+Rooms.swift`, `+HexGrid.swift` (see §9.2 dedup first), `+Boundary.swift`. Severity: Medium.
- **`Controller/GameController+Battle.swift` (591)** — carries an explicit in-file note that a prior audit already considered and deliberately rejected a physical split here, given how much cross-referencing commentary ties the health-sync sections together; respect that decision. If still wanted, the least-coupled section (Network apply/export, lines 553-591) could move to `GameController+BattleNetwork.swift` without disturbing the health-sync block. Severity: Low.
- **`BattleRound/BattleRoundModel.swift` (551)** — already MARK-divided. Split into `BattleRoundModel.swift` (core + Combatant lookups — consider adding the index dictionary from §7.1 here), `+Roster.swift`, `+Turns.swift` (incl. `synchronize`), `+Rolls.swift`, `+Network.swift`. Severity: Medium.
- **`Controller/EditController.swift` (510)** — already MARK-divided into 7 sections. Move the HexGrid section out entirely once §9.2 is resolved; split Entry Boundary Rescaling → `+Boundary.swift` and Monster/Pins → `+Pins.swift`. Severity: Medium.

### 9.14 Unnamed magic constants
- **Pin-cascade spacing/offset** (`width/4`, `height/2`, `+5`) — `Controller/EditController.swift:371`, `Map/MapEditController.swift:470`, `Map/MapEditorModel.swift:305-313` — name alongside the §9.3 consolidation (e.g. `entryInsetFraction`, `interPinGap`).
- **Monster-spawn cap of 25** — `Controller/EditController.swift:348`, `Map/MapEditController.swift:443` — name alongside the §9.4 consolidation (e.g. `maximumMonstersPerDrop`).
- **Hex-grid default sizing** (`12 * sqrt(3)`, `12 * 3/2`) — `Controller/EditController.swift:409-411`, `Map/MapEditController.swift:536-539` — name alongside the §9.2 consolidation (e.g. `defaultHexesAcrossShortSide`).
- **Scattered scale-slider ranges** — `Map/PinScaleView.swift:25` (`0.5...3.5`), `Map/MaxSizeScaleView.swift:32,49` (`0.1...1.0`), `Map/HexMapScaleView.swift:64` (`20...200`) — no visible relationship between the three; colocate in one `MapEditorScaleRanges` namespace.
- **Accessibility move distance and dead-mark inset ratio** — `Map/MapPinView.swift:564-575` (unnamed `10`pt VoiceOver move step, ×4) and `:508` (unnamed `0.24` inset ratio for the dead-pin X mark).
- *(For reference: `Map/MapOverlayGeometry.swift` and `Controller/CacheController.swift` already name their constants well — `buttonSize`, `minimumCenterSpacing`, `edgeInset`, `thumbnailMaxPixelSize` — use as the in-repo style reference.)*
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Consolidate `EditController` and `MapEditController`'s parallel pin/hex logic.** These two controllers independently reimplement hex-grid math (§9.2), monster-spawn batching (§9.4), and pin cascade-placement (§9.3) — and the placement duplication is exactly where the one verified logic bug lives (§5.1). A single shared "pin placement / hex grid" service used by both controllers fixes four findings in one pass and removes the risk of the two copies drifting further apart than they already have.
2. **Add a recipient-role-aware redaction boundary before any further networked map-payload work.** The pattern found in §6.1 — building `MapUpdatePayload`/`MapSnapshot` directly from the full live `MapModel` with no notion of "who is this going to" — is the single most consequential gap in the module. Any future feature that adds new sync payloads for MapRPG should go through an explicit redaction step from day one rather than needing this fix retrofitted again.
3. **Promote the recurring `[CGPoint]` bounds/validity helpers (§9.5, §9.6) into CoreRPG.** The same category of fix already exists for `ViewportGeometry`'s rotation math (§9.7) but wasn't reused for the simpler bounding-box case — worth doing both in the same pass since they're adjacent geometry utilities.
4. **This module's own prior audit remarks (§8, §9.10, §9.4's `GameController+Battle.swift` note) show that targeted, documented fixes stick** — several of today's findings are things a previous pass explicitly touched and left well-reasoned inline comments about. Continuing that practice (cite the fix's audit section number in-code) is worth keeping as the module's convention.

---

## 11. What was NOT audited

- Every module other than `Modules/MapRPG/` — `CoreRPG`, `GameRPG`, `CharacterRPG`, `PhotoRPG`, etc. were read **only** where needed to verify a MapRPG-side claim (e.g. confirming no filtering layer exists in `GameRPG`'s `MasterController` before it calls into MapRPG's `GameController`, or comparing `MapModel`'s rotation math against `CoreRPG.ViewportGeometry`). No findings were filed against their own code.
- Algorithmic correctness of the hex-grid/fan-placement/loupe trigonometry in `MapOverlayGeometry.swift`, beyond spot-checking for duplication and the one confirmed `CGPoint + CGFloat` operator bug (§5.1). Deep numerical verification of the geometry formulas themselves is out of scope.
- Xcode project/build settings, scheme configuration, entitlements files beyond what CLAUDE.md already documents.
- Third-party SPM dependency internals (`RPGTabletopGameContent`, `swift-snapshot-testing`, `swift-custom-dump`, etc.) — treated as black boxes.
- Deep test-coverage review. `Tests/MapRPGSnapshotTests/` and `Tests/MapRPGTests/` (referenced from `PreviewData.swift`) were confirmed to exist and consume the module's fixtures, but individual test cases were not reviewed line-by-line.
- Localization wording quality — only the incidental "charakter" typo (§2) was caught; no systematic translation review was performed, and the `.xcstrings` catalogs were not audited.
- Instruments profiling. Performance findings (§7.1, and the split proposals in §9.13) are from static reading, not a captured trace — no `.trace` file was recorded as part of this audit.
- `GameRPG`'s `MasterController`/`PlayerController` internals — only their call sites *into* MapRPG's `GameController` were inspected, to confirm no filtering layer exists there that would mitigate §6.1. Their own logic (SharePlay/Bonjour transport, message chunking, ack/retry) is a separate module's audit.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line.

- **§6.1** (Critical) — open `Modules/MapRPG/Model/MapSnapshot.swift:10-29` (no `isShown` filtering anywhere in the struct or `init(_ model:)`); `Modules/MapRPG/Controller/GameController+Metadata.swift:125-144` (`mapContentCapture` builds `MapUpdatePayload(model: item)` directly from the live model, no role parameter); `Modules/MapRPG/Controller/GameController.swift:326-395` (`shareMap`/`createMapGameData`/`networkMapContentUpdate` signatures, no recipient-role parameter); `Modules/MapRPG/Controller/GameController+Pins.swift:180-203` (`missingMapImages` — line 186 takes `model.mapPins.compactMap { $0.photoId }` with no `isShown` filter); `Modules/MapRPG/Map/MapEditorCanvas.swift:600-603` (`isVisible` is a pure render-suppression check, not a data filter). All confirmed by direct reading plus a repo-wide grep (`shareMap(id:|createMapGameData(for:|networkMapContentUpdate(for:|missingMapImages(itemId:`) showing every caller lives in `Modules/GameRPG/Controller/MasterController+*.swift` with no filtering in between.
- **§5.2** (High) — open `Modules/MapRPG/Model/DataModel+Extensions.swift:31-79` (four `preconditionFailure` sites) and `Modules/MapRPG/Controller/DataController.swift:60-102` (`@Sendable func applySnapshot(_:into:)`, explicitly commented "context queue"). Confirmed the crash paths are reachable from the CloudKit-merge apply pipeline, not just from a programmer-error path.
- **§9.2** (High) — open `Modules/MapRPG/Controller/EditController.swift:408-452` and `Modules/MapRPG/Map/MapEditController.swift:535-580` side by side; confirmed near-identical hex math with `Point1...Point6` naming in one copy and a `clamp` closure in the other.
- **§5.1** — open `Modules/CoreRPG/Extensions/CGPoint+Operators.swift:22-24` (`static func + (lhs: CGPoint, rhs: CGFloat)` adds the scalar to both `x` and `y`) and `Modules/MapRPG/Map/MapEditController.swift:468-479` (`leftCenter = leftCenter + updated.size.size.width * model.pinScale + 5`, which resolves through that operator). Confirmed the Y coordinate drifts on every cascaded pin.

If any finding doesn't reproduce when you visit the line, flag the specific reference for re-investigation.
