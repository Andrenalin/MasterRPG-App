# MasterRPG Code Audit — WeatherRPG

Generated 2026-09-17. Scope: `Modules/WeatherRPG` only — 62 Swift files, ~4,504 LOC, across `Controller/`, `Intent/`, `Menu/`, `Model/`, `Resources/`, `Root/`, `Route/`, `View/`, `Weather/`. No excluded directories within this module (no `Dead/` or archive folder present here).

A clean `xcodebuild -scheme WeatherRPG clean build` produced **zero Swift compiler warnings** (Swift 6.3, `SWIFT_STRICT_CONCURRENCY = complete`, no default actor isolation), so this module has no outstanding compiler-flagged concurrency or deprecation debt — the findings below are things the compiler cannot catch: logic bugs, `@State`-ownership mistakes, duplication, and latent isolation-safety assumptions.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

---

## 1. Executive summary

1. **[High] Procedural particle-system state (clouds/lightning/storm) isn't boxed in `@State`, so animations reset on every weather-parameter edit** — §8.1 — `Modules/WeatherRPG/Weather/CloudsView.swift:17`, `LightningView.swift:12`, `StormView.swift:11`.
2. **[High] PDF export silently returns a "successful" URL even when PDF rendering fails** — §5.1 — `Modules/WeatherRPG/Intent/WeatherEntity.swift:68-80`.
3. **[Medium] `rainDirection` setter ignores its own `newValue` and is a no-op when `rainAngle == 0`** — §5.2 — `Modules/WeatherRPG/Model/WeatherModel.swift:130-133`.
4. **[Medium] `Array<Gradient.Stop>.interpolated` crashes (`fatalError`) on an empty array** — §5.3 — `Modules/WeatherRPG/Weather/Array-GradientStop.swift:11-14`.
5. **[Medium] `GameController.revealWeather` has no per-item serialization, risking a race on overlapping reveals** — §5.4 — `Modules/WeatherRPG/Controller/GameController.swift:117-139`.
6. **[Medium] `PreviewData` fixtures use out-of-range `time`/`lightningMaxBolts` values, making Previews unreliable for visual QA** — §5.5 — `Modules/WeatherRPG/Model/PreviewData.swift:69,120,139,158,177,196,202`.
7. **[Medium] `WeatherEntity` stores raw `@MainActor`-isolated `root`/`model` references, inconsistent with its own documented eager-capture pattern** — §3.1 — `Modules/WeatherRPG/Intent/WeatherEntity.swift:41-55`.
8. **[Medium] `WeatherModel`'s `nonisolated` protocol conformances rely on a runtime `MainActor.assumeIsolated` trap, not a compiler guarantee** — §3.2 — `Modules/WeatherRPG/Model/WeatherModel.swift:140-146,168-246,286-294,375-423`.
9. **[Medium] Gradient keyframe location schedule duplicated verbatim 5x in `WeatherViewer`** — §9.2 — `Modules/WeatherRPG/View/WeatherViewer.swift:20-73`.
10. **[Medium] `WeatherModel.swift` (436 LOC) mixes 6+ independently-testable concerns in one file** — §9.7 — `Modules/WeatherRPG/Model/WeatherModel.swift:1-436`.

No Critical findings — no crashes reachable via the current UI, no data loss, no secrets, no CloudKit-optionality violations. This module has evidently already been through prior audit rounds (multiple `CODE_AUDIT_N §m.n` doc-comments reference earlier fixes), and it shows.

---

## 2. Quick wins (≤30 min each)

- **Fix the `rainDirection` setter to honor `newValue`** — `Modules/WeatherRPG/Model/WeatherModel.swift:130-133`. One-line change; currently broken whenever `rainAngle == 0`. See §5.2.
- **Remove the duplicate `.frame(width: containerSize.width, height: containerSize.height)`** — `Modules/WeatherRPG/View/WeatherViewer.swift:120`. The identical modifier is already applied at line 110; the second call is a dead no-op. See §8.2.
- **Delete `WeatherRootModel.previewWithData`** — `Modules/WeatherRPG/Model/PreviewData.swift:29-30`. Byte-identical to `.preview`, zero call sites repo-wide. See §9.9.
- **Delete `WeatherModel.children`** — `Modules/WeatherRPG/Model/WeatherModel.swift:135-137`. Unreferenced anywhere in the repo. See §9.10.
- **Fix 2-space indentation in `Localization+Extensions.swift:6-8`** to match the file's own 4-space convention. See §9.13.
- **Switch `localizedCaseInsensitiveContains` to `localizedStandardContains`** — `Modules/WeatherRPG/Model/WeatherModel.swift:312-316` — matches the project's documented search convention. See §4.1.
- **Replace the `fatalError` in `Array<Gradient.Stop>.interpolated`** with a safe fallback color — `Modules/WeatherRPG/Weather/Array-GradientStop.swift:11-14`. See §5.3.
- **Guard the force-unwrapped `context.resolveSymbol(id:)!`** in the per-frame cloud render loop — `Modules/WeatherRPG/Weather/CloudsView.swift:33`. See §5.6.

---

## 3. Concurrency

### 3.1 `WeatherEntity` stores raw `@MainActor`-isolated mutable references despite its own doc comment warning against exactly that
- **Location:** `Modules/WeatherRPG/Intent/WeatherEntity.swift:41-55`
- **What:** `WeatherEntity` (an `IndexedEntity`/`AppEntity` consumed by AppIntents, Spotlight indexing, and Siri donation — all of which can run off the main actor) stores `var root: WeatherRootModel` and `var model: WeatherModel` directly as struct properties, even though the adjacent comment states "Display fields are captured eagerly: entity properties are nonisolated, the @MainActor model must not be read from them," and the type already snapshots `storedName`/`storedDescription` specifically to avoid touching the `@MainActor` model from a nonisolated context.
- **Why:** `root`/`model` are references to mutable, `@MainActor`-isolated classes; if any nonisolated AppIntents/CoreSpotlight machinery (indexing, hashing, equality, background donation) ever reads through these stored properties instead of the eagerly-captured fields, it reintroduces the exact hazard the eager-capture pattern exists to avoid — the mitigation is applied inconsistently within the same type.
- **Action:** Either eagerly snapshot every field the entity needs and drop the stored `root`/`model` references, or explicitly document/enforce (e.g. via a wrapper type) that `root`/`model` must only ever be touched from `@MainActor` call sites within this file.
- **Severity:** Medium

### 3.2 `WeatherModel`'s `nonisolated` protocol conformances rely on a runtime `MainActor.assumeIsolated` trap, not a compiler guarantee
- **Location:** `Modules/WeatherRPG/Model/WeatherModel.swift:140-146` (`<`), `168-206` (`merge`), `208-245` (`isSame`), `286-293` (`duplicate`), `397-422` (`encode(to:)`), all routed through `assumeMainActorIsolated` (`Modules/CoreRPG/Concurrency/MainActorIsolationAssumption.swift`); `encode(to:)` additionally goes through `Encoder.encodeOnMainActor` (`Modules/CoreRPG/Extensions/Encoder+MainActor.swift`), whose own doc admits it is "safe only because every real call site pre-hops to MainActor" and internally uses `nonisolated(unsafe) let encoder = self`.
- **What:** `Comparable.<`, `Equatable`/`Hashable` support, `merge`, `isSame`, `duplicate`, and `Codable.encode(to:)` are declared `nonisolated` (required by their protocol conformances) but their bodies read `@MainActor`-isolated stored properties by asserting `MainActor.assumeIsolated` rather than being statically confined to `@MainActor`.
- **Why:** Not compiler-checked — if a future caller anywhere in the app (e.g. a background `Task` doing `array.sorted()` on `[WeatherModel]`, hashing into a `Set` off the main actor, or a background JSON encode) invokes any of these, the app traps at runtime instead of failing to build. Current call sites in `CoreRPG` (`ItemControllable.merge`, `mergeUpdates`, `ExportControllable.encoded`) are all correctly `@MainActor`-hopped today, but nothing in `WeatherModel.swift` itself enforces that invariant — it must be re-verified by hand for every new caller.
- **Action:** Keep using the centralized `assumeMainActorIsolated` helper (better than each model hand-rolling `nonisolated(unsafe)`), but consider debug-only tracing/assertions at that single chokepoint so violations are caught in CI/tests before they reach a user's device as a runtime trap.
- **Severity:** Medium

### 3.3 Unstructured `Task { }` with no cancellation handling
- **Location:** `Modules/WeatherRPG/Controller/LinkController.swift:24-27` (inside `toggleTextLink`)
- **What:** `Task { await shareResult?.networkActions?.shareId(gameController.share(id: itemId)) }` is spawned with its handle discarded and no `.cancel()` path if the caller (a text-link tap handler) goes away before the share call completes.
- **Why:** Unstructured, uncancelled tasks can outlive the view/controller that created them; low-risk here (a single short `await`), but it's the only such pattern in the module and sets a precedent that's easy to copy into a larger-blast-radius spot.
- **Action:** Store the `Task` handle and cancel it on disappearance, or convert `toggleTextLink` into an `async` API so the caller can await the share call directly instead of firing it off unstructured.
- **Severity:** Low

---

## 4. API modernity

### 4.1 User-input search filter uses `localizedCaseInsensitiveContains` instead of `localizedStandardContains`
- **Location:** `Modules/WeatherRPG/Model/WeatherModel.swift:312-316`
- **What:** The item search/filter predicate matches user-typed search text against `name`/`description` with `localizedCaseInsensitiveContains`.
- **Why:** `localizedStandardContains` is the project's documented convention for user-facing search matching (adds diacritic-insensitivity and matches system search behavior); this isn't the raw `contains()` anti-pattern, but it's a step behind the modern idiom used elsewhere.
- **Action:** Switch to `name.localizedStandardContains(filter) || description.localizedStandardContains(filter)`.
- **Severity:** Low

No other API-modernity issues found: no `DispatchQueue`, no `Task.sleep(nanoseconds:)`, no legacy `Formatter` subclasses, no `String(format:)`, no `replacingOccurrences`, no `foregroundColor`/`cornerRadius`/`tabItem()`/`GeometryReader`/`ScrollViewReader`, no single-parameter `onChange(of:)`, no `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject`/`@EnvironmentObject`, and every `@available(iOS X, *)` guard targets iOS 27 (above the 26 baseline, correctly gating AppIntents `SyncableEntity`/`IndexedEntityQuery` APIs that ship later — see `WeatherEntity.swift:108-129`).

---

## 5. Bugs / logic errors

### 5.1 PDF export silently reports success even when PDF context creation fails
- **Location:** `Modules/WeatherRPG/Intent/WeatherEntity.swift:58-93` (specifically the `guard`/`return` at 71-73 vs. the outer `return .init(url)` at 80)
- **What:** In the `Transferable` `FileRepresentation(exportedContentType: .pdf)` closure, `renderer.render { size, renderer in guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return } ... }` only returns from the *inner* rendering closure when `CGContext` creation fails; execution then falls through to `return .init(url)` in the outer closure regardless. **Verified**: read the full file — the `guard`'s `return` exits only the closure passed to `renderer.render(_:)`, not the enclosing `FileRepresentation` closure.
- **Why:** Any downstream consumer of this `Transferable` (Share Sheet, Shortcuts, Spotlight/AppIntents export, drag-and-drop) receives a "successful" file reference pointing at a missing or stale file. `CGContext(url:mediaBox:_:)` can fail (invalid path characters, disk full, sandbox/permission issues), so this is reachable, not purely theoretical.
- **Action:** Track success/failure of the inner render (e.g. a local flag set right before `pdf.closePDF()`) and throw/return an error from the outer closure when it's false, instead of unconditionally returning `.init(url)`.
- **Severity:** High

### 5.2 `rainDirection` setter ignores its own new value
- **Location:** `Modules/WeatherRPG/Model/WeatherModel.swift:130-133`
- **What:** `var rainDirection: Bool { get { rainAngle >= 0 } set { rainAngle *= -1 } }` — the setter never reads `newValue`; it unconditionally flips the sign of `rainAngle`. **Verified** by reading the file directly.
- **Why:** The only call site (`WeatherStormEditor.swift:56-67`) guards with `if value != item.rainDirection` before assigning, which coincidentally makes "flip sign" behave like "set to newValue" for a boolean toggle — but it's fragile: any future caller doing `model.rainDirection = someAbsoluteValue` without that pre-check silently does the wrong thing. It's also already broken today for `rainAngle == 0` (the default on the "nice"/"light"/"regular" presets): `0 * -1 == 0`, so toggling direction on those items is a no-op and the UI can never flip that item's rain to negative.
- **Action:** Implement the setter to honor `newValue`, e.g. `set { rainAngle = newValue ? abs(rainAngle) : -abs(rainAngle) }`.
- **Severity:** Medium

### 5.3 `Array<Gradient.Stop>.interpolated` crashes the app on an empty array
- **Location:** `Modules/WeatherRPG/Weather/Array-GradientStop.swift:11-14`
- **What:** `guard let initialStop = first else { fatalError("Attempted to read color from empty stop array.") }` — a hard crash instead of a graceful fallback.
- **Why:** All current call sites (`WeatherViewer`'s static gradient-stop arrays) are non-empty literals, so it isn't reachable today, but it's a landmine: any future refactor that computes stops dynamically (e.g. from a theme or user configuration) and produces an empty array crashes the whole app in production.
- **Action:** Replace `fatalError` with a safe fallback (e.g. return `.clear`/`.black` and log), consistent with how `Image.bundleImage(name:)` in the same module already handles its own "missing resource" case gracefully.
- **Severity:** Medium

### 5.4 Possible non-atomic race in `GameController.revealWeather` across overlapping reveals for the same item
- **Location:** `Modules/WeatherRPG/Controller/GameController.swift:117-139`
- **What:** `revealWeather(itemId:data:)` performs several independently-awaited steps — check `isWeatherAvailable`, then (on miss) `updateGame(...)`, then `hasWeatherModel`, then `markWeatherAvailable`, then `setCurrent` — with no lock/serialization guarding the whole sequence for a given `itemId`.
- **Why:** If two `revealWeather` calls for the same `itemId` (e.g. a stale retransmit plus a newer update arriving close together over SharePlay/local network) interleave, both could pass the initial `isWeatherAvailable` check as `false` and both proceed concurrently; whichever finishes last "wins" the recorded `availableVersions[itemId]`, and `setCurrent` could run with a model state that doesn't match the version just marked available. Speculative — depends on whether the caller already serializes reveals per item — but the function itself provides no such guarantee.
- **Action:** If the network/game layer doesn't already serialize incoming reveals per `itemId`, add per-item serialization here (e.g. an actor-backed in-flight-request map, or re-check `isWeatherAvailable` immediately after `updateGame` returns before trusting `data.version`).
- **Severity:** Medium

### 5.5 Preview/mock weather fixtures use values far outside the fields' real (UI-enforced) ranges
- **Location:** `Modules/WeatherRPG/Model/PreviewData.swift:69` (`lightningMaxBolts: 120`), `:120,139,158,177,196` (`time:` set to raw seconds-of-day: 43200/72000/61200), `:202` (`lightningMaxBolts: 2_000`)
- **What:** `WeatherModel.time` is used everywhere as a `0...1` fraction of a day (`WeatherConditionEditor`'s time slider is range `0...1`; both `WeatherConditionEditor.formattedTime` and `WeatherViewer.accessibilitySummary` compute `model.time * 24 * 60 * 60`; gradient interpolation stop `location`s are all `0...1`). `lightningMaxBolts` is edited via `Slider(value:, in: 0...10)` in `WeatherThunderEditor.swift:112`. Several `PreviewData` fixtures instead set `time` to raw seconds-of-day and `lightningMaxBolts` to 120/2000.
- **Why:** These out-of-range values make Xcode Previews for `WeatherConditionEditor`/`WeatherThunderEditor`/`WeatherViewer`/`OverlayViewer` unreliable for visual QA: the time-based gradient interpolation clamps to its end stop (always shows "midnight" colors, nonsensical formatted time), and the lightning system is seeded with a bolt count far beyond what the real editor UI allows a user to configure. Strongly suggests a stale unit assumption (seconds-of-day vs. fraction-of-day) left over from a prior refactor.
- **Action:** Update the fixtures to use `0...1` fractions for `time` (e.g. `12/24.0` for noon) and `0...10` for `lightningMaxBolts`, matching the ranges the real editors enforce.
- **Severity:** Medium

### 5.6 Force-unwrapped Canvas symbol lookup in per-frame cloud rendering
- **Location:** `Modules/WeatherRPG/Weather/CloudsView.swift:33`
- **What:** `let cloudImage = context.resolveSymbol(id: "cloud\(cloud.imageNumber)")!` force-unwraps the resolved symbol every frame for every cloud. **Verified** by reading the file: `Cloud.imageNumber` is `i % 8` (`CloudGroup.swift:63`) and the `symbols:` closure registers exactly `"cloud0"..."cloud7"` (lines 40-45).
- **Why:** Currently safe because the two literals (`% 8` and the `0..<8` symbol range) happen to agree, but nothing compiler-enforces that link; a future edit to either one reintroduces a crash in a hot per-frame path.
- **Action:** Use a `guard let ... else { continue }` (skipping that cloud) instead of force-unwrapping, or derive both the modulo and the symbol range from one shared constant.
- **Severity:** Low

### 5.7 `Color.getComponents()` silently returns transparent-black on colorspace conversion failure
- **Location:** `Modules/WeatherRPG/Weather/Color-Interpolation.swift:11-25`
- **What:** On macOS, `NSColor(self).usingColorSpace(.sRGB)` can return `nil`; the code does `nsColor?.getRed(...)` and simply skips filling `red/green/blue/alpha`, which stay at their initialized `0` values (fully transparent black). On iOS/tvOS/visionOS, `UIColor(self).getRed(...)` returns a discarded `Bool`, so a conversion failure is likewise silently ignored.
- **Why:** `interpolated(to:amount:)` (used throughout the gradient/tint pipeline in `WeatherViewer`/`CloudsView`) would silently interpolate toward/from black instead of the intended color if any palette `Color` ever fails sRGB conversion, producing an unexplained black flash with no diagnostic.
- **Action:** Check the conversion result and log (or fall back to a known-safe default color) when it fails, instead of silently zero-filling the components.
- **Severity:** Low

---

## 6. Security

_No findings._ No hardcoded secrets/tokens (`Bearer`/`apiKey`/`secret`/`Authorization` all absent), no external network calls (module is offline/local-only, as expected for in-game weather), no PII or device-identifying data in `ExportController`/`ImportController` paths, and the Core Data model (`Weather.xcdatamodeld`) has no CloudKit-optionality violations — non-optional attributes carry default values and both relationships are marked optional. `LinkController`'s only cross-module link is a display-only `photoId` reference, so there's no formula/derived-value link-resolution path analogous to the project's known "health values not resolving through links" bug class.

---

## 7. Performance

_No standalone findings beyond §8.1._ The `@State`-ownership defect in §8.1 is both a correctness bug (visible animation reset) and a performance issue (wasted per-edit reallocation of the entire cloud/lightning/storm particle system); it is written up once there rather than duplicated here. No other per-frame allocation, `CIContext`-lifecycle, synchronous main-thread fetch, or unhoisted view-body work was found in this module.

---

## 8. SwiftUI / UI

### 8.1 Procedural particle-system state loses continuity on every SwiftUI re-render
- **Location:** `Modules/WeatherRPG/Weather/CloudsView.swift:11-19` (`let cloudGroup: CloudGroup`, built in `init`), `Modules/WeatherRPG/Weather/LightningView.swift:10-13,64-73` (`var lightning: Lightning`, built in `init`), `Modules/WeatherRPG/Weather/StormView.swift:10-11,37-39` (`let storm: Storm`, built in `init`) — contrast with `Modules/WeatherRPG/Weather/StarsView.swift:11-16`, which correctly wraps the equivalent state in `@State private var starField: StarField`.
- **What:** `CloudGroup`, `Lightning`, and `Storm` are reference types stored as plain (non-`@State`) properties on their owning `View` structs and (re)constructed inside each view's `init`. **Verified** by reading all four files directly: `StarsView` is the only one of the four that boxes its particle-system object in `@State`.
- **Why:** `WeatherViewer.body` (`Modules/WeatherRPG/View/WeatherViewer.swift:80-146`) reads `model.cloudThickness`, `model.stormType`, `model.rainAngle`, `model.rainIntensity`, `model.lightningFrequency`, `model.lightningMaxBolts`, `model.lightningForkProbability`, and `model.time` directly off the shared `@Observable WeatherModel`. Any change to any of those properties — e.g. dragging a slider in `WeatherStormEditor`/`WeatherThunderEditor`/`WeatherConditionEditor` while a live preview of the *same* model instance is showing, the normal edit workflow reachable from `DetailFolderListView.swift` — re-evaluates `WeatherViewer.body`, constructing brand-new `CloudsView`/`LightningView`/`StormView` struct values. Because their particle-system objects aren't boxed in `@State`, each reconstruction discards all in-flight animation state and reallocates a fresh, newly-randomized particle set — visible as a jarring reset/stutter on every parameter edit, and wasted CPU/allocation work. It also means the manual lightning-trigger accessibility action (`lightningTrigger` in `WeatherViewer.swift:17`) resets clouds and storm too, though only lightning should be affected.
- **Action:** Box `cloudGroup`, `lightning`, and `storm` in `@State` (seeded once via `State(initialValue:)` in `init`, matching `StarsView`'s existing pattern) so the particle systems persist across `WeatherViewer.body` re-evaluations and only their "input" parameters (tint, thickness, direction, frequency, etc.) get applied to the existing instance.
- **Severity:** High

### 8.2 Duplicate no-op `.frame(width:height:)` modifier in `WeatherViewer`
- **Location:** `Modules/WeatherRPG/View/WeatherViewer.swift:110` and `:120`
- **What:** `.frame(width: containerSize.width, height: containerSize.height)` is applied twice on the same view chain — once right after the `ZStack`, and again right after the `.background { LinearGradient(...) }` block, with nothing in between that could change the frame. **Verified** by reading the file.
- **Why:** The second `.frame` call is a redundant no-op layout pass that could confuse a future reader into thinking the background changes the frame.
- **Action:** Remove the second `.frame(...)` at line 120 (the one at line 110 already covers everything after it, including the `.background` modifier).
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Files to delete outright
_None._ No `#if false` blocks (zero grep hits), no `*OLD*`/`*_v1*`/`*Legacy*`/`*Deprecated*`-named files (the only substring matches were false positives inside "**Fold**er"), and no orphaned files — `MockData.swift`/`PreviewData.swift` are confirmed live (used by 12+ `#Preview` call sites and by `WeatherRPGTests`/`WeatherRPGSnapshotTests`/cross-module tests).

### 9.2 Gradient keyframe location schedule duplicated verbatim 5x
- **Locations:** `Modules/WeatherRPG/View/WeatherViewer.swift:20-73` (`backgroundTopStops`, `backgroundBottomStops`, `cloudTopStops`, `cloudBottomStops`, `starStops`)
- **What:** All five arrays hard-code the identical 8-value "time of day" location schedule `[0, 0.25, 0.33, 0.38, 0.7, 0.78, 0.82, 1]`, differing only in the colors plugged in. **Verified** by reading the file directly.
- **Why:** Five independent copies of the same keyframe schedule; a future tweak to day/night timing (e.g. moving sunrise) requires editing 5 arrays in lockstep, and nothing enforces they stay in sync. The literals themselves are also unnamed magic constants — hard to tell what "0.33"/"0.38" mean without cross-referencing `Color-Custom.swift`.
- **Action:** Extract a shared `static let dayKeyframeLocations: [Double]` (with named constants for each transition point, e.g. `sunriseStart = 0.33`) plus a small builder that zips locations with a per-array color list, so each of the 5 stop arrays is built from one source of truth.
- **Severity:** Medium

### 9.3 `previewFixture(...)` and `testRoot(...)` duplicate 6 lines of root-wiring boilerplate verbatim
- **Location:** `Modules/WeatherRPG/Model/PreviewData.swift:12-27` and `:34-42`
- **What:** Both functions construct `WeatherRootModel`, a fake `RootManager`, call `setUp` twice, and call `photoRoot.setUp` — 6 identical lines — before diverging (one inserts model fixtures, the other returns immediately).
- **Why:** Any change to the root-wiring sequence must be made in two places; the two functions have already partially drifted in intent, making it easy to miss one on the next edit.
- **Action:** Factor the shared 6 lines into a private `makeWiredRoot(photoRoot:) -> WeatherRootModel` used by both.
- **Severity:** Low

### 9.4 Size-tracking `Color.clear.overlay { WeatherViewer }` + `.onGeometryChange` snippet repeated 3x
- **Locations:** `Modules/WeatherRPG/Root/ViewerRootView.swift:21-31`, `Modules/WeatherRPG/View/InlineRowViewer.swift:30-38`, `Modules/WeatherRPG/View/OverlayViewer.swift:21-33`
- **What:** All three views repeat the identical ~8-line pattern wrapping `WeatherViewer` in `Color.clear.overlay { ... }` with `.onGeometryChange(for: CGSize.self)` tracking `containerSize`.
- **Why:** Pure UI-composition duplication (not module-template boilerplate) — a bug fix (e.g. debouncing) must be applied 3x.
- **Action:** Extract a reusable `WeatherViewerContainer` view (or a `.measuredSize($binding)` `ViewModifier`) wrapping `WeatherViewer` + the geometry-tracking overlay once.
- **Severity:** Low

### 9.5 Section-header block duplicated verbatim 4x across the editor views
- **Locations:** `Modules/WeatherRPG/View/WeatherPhotoEditor.swift:26-33`, `WeatherConditionEditor.swift:23-30`, `WeatherStormEditor.swift:29-36`, `WeatherThunderEditor.swift:26-33`
- **What:** All four `Section(header:)` closures repeat the exact block: `#if os(macOS) Divider().padding(.top) #endif` followed by a centered `Text(...).font(.headline)`.
- **Why:** No shared `SectionHeaderView` helper exists anywhere in the repo — this header is hand-copied 4 times within this one module.
- **Action:** Extract a `WeatherSectionHeader(title: LocalizedStringKey)` view (or a `.centeredSectionHeader(_:bundle:)` modifier) used by all four editors.
- **Severity:** Low

### 9.6 Per-field "sync EditIdentifierModel from model, save via EditController" boilerplate repeated 5-6x
- **Locations:** `Modules/WeatherRPG/View/WeatherConditionEditor.swift:39-44` (`syncCloudModel`), `WeatherStormEditor.swift:49-67` (`syncStormModel`, `syncDirectionModel`), `WeatherThunderEditor.swift:54-73` (`syncFrequencyModel`, `syncMaxBoltsModel`, `syncForkModel`)
- **What:** Each is a 3-4 line wrapper calling `xEditModel.reset(valueId:value:) { itemId, value in editController.reset(x:itemId:) }`.
- **Why:** `EditController.reset(keyPath:value:itemId:message:)` is already a generic helper, so the duplication here is thin, but the "sync on appear + save via keypath-specific reset call" shape is copy-pasted 5-6 times with only the property name changed.
- **Action:** Low priority — consider a small generic `syncEdit<Value: Equatable>(_ editModel:keyPath:model:editController:)` helper only if a 6th field is added; current form is already fairly minimal and type-safe.
- **Severity:** Low

### 9.7 `WeatherModel.swift` is the largest file in the module and mixes 6+ concerns
- **Location:** `Modules/WeatherRPG/Model/WeatherModel.swift:1-436`
- **What:** Single file contains the `@Observable` class + 3 initializers, plain computed extensions, `ItemLinkRegistable`, `ItemDiffComparable` (`merge`/`isSame`), `reviewProperties`, `ItemDuplicatable`, `ItemDataAccessable`, `Codable`, and `Equatable`/`Hashable`.
- **Why:** At 436 lines it's already the biggest model in this small module and larger than comparable "simple" models in sibling modules (AudioModel 302, PdfModel 289, SpaceModel 301) — each extension is independently testable/reviewable and the file mixes CRDT plumbing, sync logic, and SwiftUI-facing review metadata in one place.
- **Action:** Split along the existing `extension` boundaries, e.g. `WeatherModel.swift` (class + init + accessors), `WeatherModel+Sync.swift` (`ItemDiffComparable`), `WeatherModel+Codable.swift`, `WeatherModel+ItemDataAccessable.swift`, `WeatherModel+ReviewProperties.swift`. Purely mechanical, low risk.
- **Severity:** Medium

### 9.8 `PreviewData.swift` approaching the 300-line threshold, mixes root-fixture wiring with 8 weather presets and per-controller preview accessors
- **Location:** `Modules/WeatherRPG/Model/PreviewData.swift:1-268`
- **What:** File mixes `WeatherRootModel` preview/test-root construction (7-51), 8 near-identical `WeatherModel` static fixtures (56-206), and several unrelated `extension ItemController/EditController/GameController/... { static var preview }` one-liners (231-268).
- **Why:** Not urgent at 268 lines, but three unrelated concerns live in one file.
- **Action:** If touched again, split into `WeatherRootModel+Preview.swift`, `WeatherModel+Fixtures.swift`, and `ControllerPreviews.swift`. Low priority since it's under the 300-line trigger.
- **Severity:** Low

### 9.9 `WeatherRootModel.previewWithData` is a 100%-unused duplicate of `.preview`
- **Location:** `Modules/WeatherRPG/Model/PreviewData.swift:29-30`
- **What:** `static var previewWithData: WeatherRootModel { previewFixture() }` has the exact same body as `static var preview: WeatherRootModel { previewFixture() }` (line 8-9).
- **Why:** Repo-wide grep for `WeatherRootModel.previewWithData` finds zero call sites — every caller uses `.preview` instead. Sibling modules (e.g. PdfRPG) do use their own `previewWithData` from real call sites, so this looks like copy-paste leftover specific to WeatherRPG.
- **Action:** Delete `previewWithData`, or if it's meant to signal "explicitly non-empty" somewhere, use it there and delete the redundant one.
- **Severity:** Low

### 9.10 `WeatherModel.children` computed property is unreferenced
- **Location:** `Modules/WeatherRPG/Model/WeatherModel.swift:135-137`
- **What:** `var children: [WeatherModel] { [self] }`. **Verified**: not a protocol requirement (no conformance requires `children`), and repo-wide grep finds zero call sites.
- **Why:** A sibling module (`MapModel.children`, MapRPG — out of scope) has the identical unused pattern, suggesting this was copy-pasted without ever being wired up.
- **Action:** Remove, or add a comment explaining why it's kept if it's meant to support a not-yet-built tree-walk feature.
- **Severity:** Low

### 9.11 `RPGWeather.entryOrNew(for:)` is defined but never called
- **Location:** `Modules/WeatherRPG/Model/DataModel+Extensions.swift:16-18`
- **What:** `func entryOrNew(for uuid: UUID) -> RPGWeatherEntry { childOrNew(uuid, in: entriesModel) }` — no call site anywhere in the repo.
- **Why:** Systemic, not WeatherRPG-specific — every sibling module (AdventureRPG, CharacterRPG, MapRPG, SpaceRPG, TableRPG, AudioRPG, DiceRPG, PdfRPG) has an identically-unused `entryOrNew` from the same shared template.
- **Action:** Confirm with the team whether this backs a planned Core Data lookup; if not, remove from the shared per-module template (coordinate across modules rather than deleting only here).
- **Severity:** Low

### 9.12 Mixed file-header attribution convention: project copyright vs. ported tutorial headers
- **Location:** All 15 files in `Modules/WeatherRPG/Weather/` (e.g. `Cloud.swift:1-6`, `Color-Custom.swift:1-6`, `StarsView.swift:1-6`) vs. every other file in the module (e.g. `Model/WeatherModel.swift:1`)
- **What:** Every file outside `Weather/` starts with `// @copyright André Trettin`; every file inside `Weather/` instead has a `// Created by Paul Hudson on <date>` header, evidently adapted from a public "Hacking with Swift" weather-effects sample.
- **Why:** Inconsistent file-header convention; more importantly, if this code was adapted from a public tutorial without a tracked license grant, that's a licensing question worth confirming with the project owner, separate from pure code style.
- **Action:** Either keep the original attribution (common and expected when adapting tutorial code under a compatible license) and add a short folder-level note on provenance, or normalize the header if the code has diverged enough to be considered original. Confirm license terms are tracked somewhere in the repo.
- **Severity:** Low (Medium if license compliance isn't already tracked elsewhere — recommend the project owner confirm)

### 9.13 Inconsistent indentation in `Localization+Extensions.swift`
- **Location:** `Modules/WeatherRPG/Resources/Localization+Extensions.swift:6-8`
- **What:** The `Bundle.localizedString(forKey:)` extension body uses 2-space indentation while the rest of the same 15-line file uses 4-space indentation.
- **Why:** Minor but visible inline inconsistency, likely to trip up an auto-formatter if one is later added.
- **Action:** Reformat lines 6-8 to 4-space indentation.
- **Severity:** Low

### 9.14 Unnamed animation/physics tuning constants in `Lightning.swift`
- **Location:** `Modules/WeatherRPG/Weather/Lightning.swift:43` (`delta * 800` bolt growth speed), `:50-51` (`Double.random(in: -10...10)` jitter), `:60` (fork angle spread), `:69` (`flashOpacity = 0.6`), `:72` (`bolt.width *= 1.5`), `:81` (`delta * 15` fade rate)
- **What:** Six distinct "feel" tuning literals control bolt speed, jitter, fork angle, flash brightness, and fade rate, none named.
- **Why:** These are exactly the values a designer/engineer will want to tweak; today that means hunting through `update(date:in:)`'s control flow for bare numeric literals.
- **Action:** Lift into named `private static let` constants on `Lightning` (e.g. `boltGrowthSpeed`, `jitterRange`, `forkAngleSpread`, `flashOpacity`, `strikeWidthGrowth`, `fadeRate`). Lower priority for `Storm`/`StormDrop`/`CloudGroup`/`StarField`, whose random ranges are already grouped per-case and reasonably self-documenting.
- **Severity:** Low

### 9.15 Hardcoded cloud-image count "8" duplicated in two places
- **Location:** `Modules/WeatherRPG/Weather/CloudGroup.swift:63` (`i % 8`), `Modules/WeatherRPG/Weather/CloudsView.swift:41` (`ForEach(0..<8, id: \.self)`)
- **What:** The bundle asset count (`cloud0`...`cloud7`) is duplicated as a bare literal in two places that must stay in sync (this is also the root cause underlying §5.6).
- **Why:** If a `cloud8` asset is ever added/removed, both sites need updating and nothing enforces they match.
- **Action:** Add `static let cloudImageCount = 8` and reference it from both `CloudGroup.init` and `CloudsView.body`.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Adopt `@State`-boxed particle-system ownership everywhere in `Weather/`.** `StarsView` already demonstrates the correct pattern (§8.1); `CloudsView`, `LightningView`, and `StormView` should follow it so live-editing weather parameters doesn't visibly reset the animation.
2. **Centralize the day/night keyframe schedule.** Five `Gradient.Stop` arrays in `WeatherViewer` (§9.2) and several unnamed literals in `Lightning.swift` (§9.14) point at the same underlying gap: animation/interpolation tuning values live as bare numeric literals scattered through the file instead of one named, documented source of truth.
3. **Split `WeatherModel.swift` along its existing extension boundaries now** (§9.7), before it grows further — the same file-per-concern convention is already used elsewhere in the codebase, and this is a purely mechanical, low-risk change.
4. **The `assumeMainActorIsolated` chokepoint (§3.2) is well-centralized but has zero compiler enforcement.** Since this pattern is shared across all modules (not just WeatherRPG), consider adding debug-only assertions or a lightweight runtime trace at that single helper rather than relying on manual verification of every new call site, repo-wide.
5. **`PreviewData` fixtures should be range-validated against their editors.** §5.5's out-of-range `time`/`lightningMaxBolts` values suggest preview fixtures silently drifted from the ranges their own editor UIs enforce; a lightweight `#if DEBUG` assertion in the fixture initializer (checking against the same bounds the sliders use) would catch this class of drift automatically in the future.

---

## 11. What was NOT audited

- All other modules (AdventureRPG, AudioRPG, CharacterRPG, DiceRPG, MapRPG, PdfRPG, PhotoRPG, SpaceRPG, TableRPG, RuleRPG, CoreRPG, GeneratorRPG, GameRPG, RolePlayGameKit) — grepped only to confirm WeatherRPG doesn't duplicate their logic or leave dead code they reference.
- Algorithmic/visual correctness of the procedural particle-generation math (cloud drift, star flicker, lightning fork geometry, storm-drop physics) beyond the specific bugs found — "does it look right" tuning is out of scope.
- `Weather.xcdatamodeld` schema design beyond the CloudKit-optionality check performed for §6.
- Build settings, scheme configuration, Xcode project structure beyond the shared `WeatherRPG` scheme used to capture the compiler-warning baseline.
- Third-party SPM dependency internals (none are WeatherRPG-specific; the module has no direct third-party dependencies).
- Test coverage under `Tests/WeatherRPGTests/` and `Tests/WeatherRPGSnapshotTests/` — confirmed these consume `PreviewData`/`MockData` (so those files aren't dead), but no deep coverage review was performed.
- Localization wording/translation correctness — only the presence of `bundle: .module` usage was checked.
- Performance profiling via Instruments — §8.1's cost was reasoned about from the code, not measured with a trace.
- Entitlements — this module has no entitlements file of its own; the app-level App Group/iCloud container entitlements were not re-reviewed here.
- Xcode Previews were not visually rendered (no `RenderPreview` pass); §5.5's finding was derived from reading the ranges enforced by editor code, not from opening the canvas.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line.

- **§5.1** — open `Modules/WeatherRPG/Intent/WeatherEntity.swift`, lines 68-80. The `guard let pdf = CGContext(...) else { return }` at line 71-73 exits only the closure passed to `renderer.render(_:)`; the outer `FileRepresentation` closure falls through to `return .init(url)` at line 80 unconditionally.
- **§5.2** — open `Modules/WeatherRPG/Model/WeatherModel.swift`, lines 130-133. The `rainDirection` setter body is `rainAngle *= -1`; `newValue` never appears in the setter.
- **§8.1** — compare `Modules/WeatherRPG/Weather/CloudsView.swift:17` (`let cloudGroup: CloudGroup`) against `Modules/WeatherRPG/Weather/StarsView.swift:16` (`@State private var starField: StarField`) — the working pattern sits right next to the broken one within the same folder.
- **§9.2** — open `Modules/WeatherRPG/View/WeatherViewer.swift`, lines 20-73. All five `Gradient.Stop` arrays (`backgroundTopStops`, `backgroundBottomStops`, `cloudTopStops`, `cloudBottomStops`, `starStops`) use the identical `location:` sequence `0, 0.25, 0.33, 0.38, 0.7, 0.78, 0.82, 1`.
- **§8.2** — open `Modules/WeatherRPG/View/WeatherViewer.swift`, lines 110 and 120. Both are `.frame(width: containerSize.width, height: containerSize.height)` with no frame-affecting modifier between them.
- **§5.6** — open `Modules/WeatherRPG/Weather/CloudsView.swift:33` (force-unwrap) alongside `CloudGroup.swift:63` (`i % 8`) and `CloudsView.swift:41` (`0..<8` symbol registration) — the three sites must stay numerically in sync with nothing enforcing it.

If any finding doesn't reproduce when you visit the line, flag the specific reference for re-investigation.
