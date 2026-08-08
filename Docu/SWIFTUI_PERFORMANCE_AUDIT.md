# SwiftUI, Cache, and Concurrency Performance Audit

Date: 2026-07-25  
Project: MasterRPG  
Audit type: repository-wide code-first review with targeted Instruments instrumentation  
Runtime evidence status: simulator build verified; physical-device Release traces still required

## Executive summary

The static audit covered every production Swift file under `Modules`, `Sources`, and
`Integrations`, then deeply reviewed the high-risk SwiftUI, image/cache, Foundation
Models, RealityKit, weather animation, search, and SharePlay paths.

The strongest code-backed performance risks are:

1. Full images and thumbnails are retained twice: once in bounded `NSCache` instances
   and again in unbounded observable dictionaries. This can defeat eviction and
   invalidate many SwiftUI cache readers when any dictionary entry changes.
2. Photo decoding is explicitly performed by `@MainActor` functions. Large image
   decoding or file-backed image initialization can therefore contribute directly to
   frame stalls and hangs.
3. Every Foundation Models extraction snapshot maps the complete partial result into
   identity strings, removes the current generated batch, rebuilds every generated
   `SheetModel`, and appends the entire batch again.
4. The extraction task is unstructured and its handle is not retained, so
   `tearDown()` cannot cancel it.
5. RealityKit collision generation is wrapped in a detached task but explicitly moved
   back to `MainActor`; the expensive operation therefore remains a main-thread risk.
6. `AnyView` is part of the central `ViewControllable` protocol and is returned inside
   list rows, preventing SwiftUI from seeing a stable concrete view type at that
   boundary.
7. Five weather effects use animation-driven `TimelineView` rendering while visible.
   They respect accessibility settings but are not explicitly gated by scene phase or
   occlusion.

These are code-backed hypotheses, not measured costs. Do not start a broad refactor
until the repeatable trace scenarios below establish which paths dominate on the
oldest supported physical device.

## Scope and method

Static inventory:

- 1,658 production Swift files
- 1,153 files importing SwiftUI
- 906 `body: some View` implementations
- 834 view-type declarations matched by the structural scanner
- 173 `@Observable` declarations
- 85 SwiftUI `.task` modifiers
- 21 detached-task sites
- 107 `AnyView` references
- 9 `GeometryReader` references

Every production file was included in pattern and ownership scans. The deeper manual
review followed the paths with image decoding, caches, recursive trees, per-frame
rendering, model streaming, task creation/cancellation, and dynamic list content.

| Module | Swift files | SwiftUI files | View bodies | Task sites |
|---|---:|---:|---:|---:|
| AdventureRPG | 57 | 35 | 29 | 10 |
| AudioRPG | 62 | 38 | 29 | 28 |
| CharacterRPG | 58 | 37 | 31 | 11 |
| CoreRPG | 520 | 395 | 243 | 123 |
| DiceRPG | 80 | 56 | 46 | 22 |
| GameRPG | 178 | 132 | 141 | 87 |
| GeneratorRPG | 109 | 52 | 48 | 22 |
| MapRPG | 120 | 91 | 88 | 17 |
| PdfRPG | 54 | 33 | 24 | 14 |
| PhotoRPG | 63 | 41 | 32 | 16 |
| RolePlayGameKit | 61 | 50 | 54 | 27 |
| RuleRPG | 44 | 20 | 21 | 3 |
| SpaceRPG | 97 | 65 | 49 | 23 |
| TableRPG | 52 | 31 | 28 | 8 |
| WeatherRPG | 65 | 44 | 26 | 5 |

The project is configured for Swift 6, complete strict concurrency, and no default
main-actor isolation. The audit did not find a production `@Observable` reference type
missing explicit `@MainActor`; comments and preprocessor fragments were excluded from
that check.

## Findings

### P0 — duplicated, unbounded observable image retention

Evidence:

- `ObjectCache` bounds its `NSCache` to 2,500 objects and 256 MB:
  `Modules/CoreRPG/Cache/ObjectCache.swift:13`.
- `ObservableImageCache` separately retains full images and thumbnails in two
  unbounded dictionaries:
  `Modules/CoreRPG/Controllable/ImageCacheControllable.swift:174`.
- Those observable dictionaries have no cost limit, count limit, memory-pressure
  handling, or bulk eviction policy.
- SwiftUI views synchronously read through the observable cache. A mutation to either
  stored dictionary can invalidate observers at the property level even when their
  requested UUID did not change.

Likely symptoms:

- memory growth while browsing many photo-backed modules;
- repeated thumbnail decoding after system pressure, while the observable layer still
  prevents actual reclamation;
- broad list-row invalidations after a single image becomes available.

Trace proof:

- Run the photo-cache scenario with SwiftUI, Allocations, VM Tracker, and the custom
  `CacheHit`/`CacheMiss` events.
- In the SwiftUI Cause & Effect graph, inspect whether setting one thumbnail causes
  unrelated thumbnail rows to update.
- Compare resident memory after 25, 100, and 250 unique photos, then navigate away and
  trigger memory pressure.

Proposed fix after proof:

- establish one cost-limited ownership layer for decoded images;
- expose per-key observable entries/tokens rather than observing whole dictionaries;
- clear or trim on memory-pressure notification;
- assign accurate pixel-cost values to `NSCache`.

### P0 — image decode is main-actor isolated

Evidence:

- `ImageCacheControllable` requires `createImage` and `createThumbnail` on
  `@MainActor`.
- `PhotoRPG/Controller/CacheController.swift:28` constructs `AKImage` from `Data` or a
  file inside `createImage`.
- `PhotoRPG/Controller/CacheController.swift:49` retrieves the full image and starts
  thumbnail generation from another main-actor function.

Awaiting data does not block the actor, but `AKImage(data:)` and
`AKImage(contentsOfFile:)` are synchronous decoding/construction boundaries.

Trace proof:

- Use uncached, high-resolution photos.
- Correlate `ImageDecode`, `FullImagePipeline`, and `ThumbnailGenerate` with Time
  Profiler, Main Thread, Hangs, and SwiftUI long body updates.
- A repeated second pass should show cache hits without `ImageDecode`.

Proposed fix after proof:

- downsample with Image I/O at the requested display size on a non-main executor;
- keep file reads and decompression away from `MainActor`;
- publish only the final immutable image/cache token on the main actor;
- avoid generating a 64-point thumbnail from an unnecessarily decoded full-resolution
  image.

### P1 — Foundation extraction rebuilds the complete generated subtree per partial

Evidence:`
This compounds model-stream frequency, array mapping, string allocation, observable
mutations, recursive sheet derivation, and SwiftUI invalidation.

Trace proof:

- Generate 1, 5, 20, and 50 blocks.
- Compare `FoundationExtraction` with each `GeneratedBlocksRebuild` interval.
- In SwiftUI Cause & Effect, inspect whether each partial snapshot invalidates the
  complete sheet tree.
- Record rebuild count, maximum rebuild duration, and main-thread utilization.

Proposed fix after proof:

- coalesce partial UI publication to a bounded cadence;
- observe a small generation revision instead of mapping all content into strings;
- update changed entries by stable ID rather than remove-and-recreate;
- perform final persistence once extraction transitions from active to finished.

### P1 — extraction task is not owned or cancelled

Evidence:

- `AdventureGeneratorController.swift:237` starts extraction.
- `AdventureGeneratorController.swift:242` creates an unstructured task and discards
  its handle.
- `AdventureGeneratorController.swift:161` cancels only the conversation engine and
  `model.currentTask`, not extraction.

Likely symptoms:

- extraction continues after the view disappears;
- late writes to the model cause unexpected view work;
- the task retains related session/controller state longer than intended.

Proposed fix:

- add a separate `extractionTask` handle to `AdventureSessionModel`;
- cancel and replace it on new extraction and in `tearDown()`;
- check cancellation inside the response loop before publishing each partial;
- consider view-owned structured work if the view lifetime should define ownership.

### P1 — collision generation still executes on the main actor

Evidence:

- `SpaceViewer.swift:383` creates a detached utility task.
- `SpaceViewer.swift:384` immediately calls `MainActor.run`.
- `SpaceViewer.swift:391` generates collision shapes inside that main-actor closure.

The detached wrapper does not move collision generation off the main actor. It also
creates work whose task handle is not retained.

Trace proof:

- Load small, medium, and complex USDZ assets.
- Correlate `CollisionShapeGeneration` with the Main Thread and Hangs tracks.
- Verify whether RealityKit offers a supported asynchronous preparation path for the
  exact SDK/API before changing executor ownership.

### P1 — type erasure at frequently repeated row boundaries

Evidence:

- `ViewControllable.swift:57` through `:65` uses `AnyView` for importers, sharing,
  thumbnails, row viewers, and inline row viewers.
- `ListRowItemView.swift:26` requests the type-erased thumbnail from inside a list row.
- `ThumbnailRowViewWrapper.swift:17` still calls a method returning `AnyView`; the
  wrapper does not restore the erased concrete type identity.

Trace proof:

- Profile fast scrolling through lists containing several thumbnail types.
- Inspect long body updates, hangs, and unexpected row recreation.
- Compare a small experimental concrete enum/generic route before committing to a
  cross-module protocol redesign.

### P2 — unbounded resource-data cache

`ResourceCache.swift:13` stores every loaded `Data` value in an unbounded dictionary.
In-flight task coalescing is good, but completed data has no cost/count limit or
automatic pressure response.

Trace with `ResourceCacheHit`, `ResourceCacheMiss`, `ResourceLoad`, Allocations, and VM
Tracker. If it materially grows, use a cost-limited cache or narrow the cache to
resources proven to benefit from reuse.

### P2 — continuous weather rendering while visible

`CloudsView`, `ResidueView`, `StarsView`, `StormView`, and `LightningView` use
`TimelineView(.animation...)`. Accessibility-driven pause behavior is present, which
is good. There is no explicit scene-phase/occlusion gate at these effect boundaries.

Trace with SwiftUI, Core Animation, Time Profiler, and Energy Log while the
`WeatherAnimationVisible` interval is open. Compare foreground visible, covered
window, background, reduced motion, and static editor states. Add scene-phase gating
only if the trace shows continued activity when animation is not useful.

### P2 — repeated derived collection work in view evaluation

Examples:

- `TableGenerationRootView.swift:192` and `:356` filter and localized-sort visible
  players; the result is referenced multiple times and once per occurrence.
- `GameShareView.swift:88` sorts statuses, then creates attributed and accessibility
  strings.
- `FoundryImportView.swift:417` (renamed from `FoundryRuleImportView.swift`, see CODE_AUDIT.md §8.5) filters text resources inline in `ForEach`; the
  866-line view has several additional filtered sections.
- `EffectedLinkActionPanelView.swift:37` and `:107` filter the same link tree for title
  and disabled state.
- `SearchProxyView.swift:61` filters games after building observer-name state.
- `GameStatisticsDiceChart.swift:48` derives `chartPoints`, which is used again for
  total and selection lookup.

Most collections may be small; measure before caching. When a trace confirms cost,
move derivation to the controller/model update boundary or compute once per smaller
subview input.

### P2 — conditional structural identity through `applyIf`

`IfModifier.swift:11` produces different view structures for the true and false
branches. This is often harmless for stable configuration, but selection/editor
conditions in `SheetEntryView.swift:109` and several `SheetView` rows can change
frequently and recreate stateful descendants.

Inspect row lifetime and dynamic-property churn in SwiftUI Instruments. Replace only
confirmed hot instances with inert modifier values or stable containers.

### P2 — map rendering is an important trace target, not a confirmed defect

Positive design evidence:

- `MapRoomCanvas.swift:26` enables asynchronous Canvas rendering.
- snapshot arrays isolate render input from live observable nodes;
- fog tiling is bounded;
- map-pin state is split into per-node observables and caches ordinary/zoom render
  layers.

Remaining trace targets are the multiple snapshot filter passes and fog drawing for
many hidden rooms during pan, zoom, and visibility changes. Use SwiftUI, Core
Animation, and Time Profiler before modifying the current bounded renderer.

## Positive concurrency and SwiftUI findings

- Actual production `@Observable` reference types are explicitly `@MainActor`.
- Thumbnail and full-image views generally use `.task(id:)`, cancellation checks, and
  ID-scoped loading rather than starting work directly in `body`.
- Most animations use a value-scoped modifier and honor reduced-motion settings.
- SharePlay journal publication is explicitly bounded to 16 outstanding publications,
  512 MB, and 8 cleanup reservations. Worker task handles are retained and cancelled.
- Foundry/file normalization paths generally await detached I/O and use cancellation
  handlers.
- Map Canvas rendering is already asynchronous and bounded.

## Added Instruments markers

Implementation:
`Modules/CoreRPG/Instrumentation/PerformanceTrace.swift`

- subsystem: `de.andretrettin.MasterRPG.performance`
- category: `pointsOfInterest`
- disabled path: guarded by `OSSignposter.isEnabled`
- interval handles are `Sendable`, allowing begin/end around awaited work
- no logging was inserted into SwiftUI `body`

| Marker | Type | Meaning |
|---|---|---|
| `AppInitialized` | event | app dependency setup completed |
| `ListSearch` | interval | root search and list rebuild |
| `DetailListSearch` | interval | scoped detail search and rebuild |
| `CacheHit` / `CacheMiss` | event | memory/disk image cache result with item, kind, and source |
| `FullImagePipeline` | interval | availability/download through full-image availability |
| `ThumbnailPipeline` | interval | memory/disk lookup through thumbnail creation |
| `ImageDecode` | interval | PhotoRPG synchronous image construction boundary |
| `ThumbnailGenerate` | interval | full-image acquisition, resize, disk save, and cache insert |
| `ResourceCacheHit` / `ResourceCacheMiss` | event | resource-data cache result |
| `ResourceLoad` | interval | uncached resource file load |
| `FoundationRequest` | event | conversation or extraction requested |
| `FoundationConversation` | interval | end-to-end conversational generation |
| `FoundationExtraction` | interval | structured block extraction stream |
| `GeneratedBlocksRebuild` | interval | rebuild of generated sheet entries for one partial |
| `SharePlayJournalPublish` | interval | one journal attachment publication |
| `CollisionShapeGeneration` | interval | synchronous RealityKit collision-shape generation |
| `WeatherAnimationVisible` | interval | continuously animated weather layer is active onscreen |
| `WeatherLightningTriggered` | event | manual/accessibility lightning action |

Named Swift tasks were added for:

- list search, refresh, and selection restoration;
- resource cache loads;
- Foundation context sizing, conversation, response streaming, and extraction;
- RealityKit collision generation;
- SharePlay journal publication.

## Instruments runbook

Use a Release or profiling configuration on a physical device representative of the
lowest-performance supported hardware. Simulator results remain useful for functional
marker checks but are not a performance baseline.

### Recording setup

1. In Xcode, choose **Product > Profile**.
2. Start with the **SwiftUI** template.
3. Add **os_signpost / Points of Interest** and filter subsystem
   `de.andretrettin.MasterRPG.performance`.
4. Add **Swift Tasks** and **Swift Actors** when diagnosing task/executor behavior.
5. For responsiveness, add **Time Profiler**, **Hangs**, and **Main Thread**.
6. For images/caches, add **Allocations**, **VM Tracker**, and **Leaks**.
7. For weather/map animation, add **Core Animation** and Energy instruments.
8. Record one isolated scenario per trace, with the same data and gestures each run.

In the SwiftUI instrument, start with Long View Body Updates and the Cause & Effect
graph. Orange/red body updates are investigation leads, not automatic defects. In
the Hangs instrument, prioritize contiguous main-thread work that crosses the
perceptible interaction threshold, especially intervals at or above 100 ms.

### Repeatable trace scenarios

| ID | Scenario | Steps | Expected markers | Primary evidence |
|---|---|---|---|---|
| S1 | Launch | cold-launch, wait for first usable editor | `AppInitialized` | launch CPU/main-thread work |
| S2 | List/search | open a 250+ row module, type 5 characters quickly, clear, select a detail | `ListSearch`, `DetailListSearch`; named search tasks | body duration, cancellations, list invalidation |
| S3 | Photo cold/warm | clear app cache, scroll 100 thumbnails, open five full images, repeat same pass | cache events, image/thumbnail pipeline intervals | decode stalls, hit ratio, memory slope |
| S4 | Foundation extraction | request 1, 5, 20, then 50 blocks; let each finish; dismiss one midway | Foundation and rebuild intervals; named tasks | partial count, rebuild duration, cancellation |
| S5 | Space | load three USDZ assets of increasing complexity and immediately orbit each | `CollisionShapeGeneration` | main-thread/hang correlation |
| S6 | SharePlay | send small and large journal-backed items to a joined peer | `SharePlayJournalPublish` | transfer latency, task suspension, retained bytes |
| S7 | Weather | display active rain/cloud/lightning for 30 seconds, cover/background, return | `WeatherAnimationVisible`, lightning event | FPS, CPU/GPU, energy while visible/hidden |
| S8 | Map | pan/zoom a map with many rooms, toggle fog visibility, reveal pins | no custom interval; use interaction timestamps | Canvas duration, frame pacing, fog cost |

For each scenario, record:

- device, OS, build configuration, dataset size;
- custom marker duration/count;
- longest SwiftUI body update and its view;
- main-thread utilization and longest hang;
- peak/residual memory;
- task cancellation or continued work after dismissal;
- before/after numbers for any experimental fix.

## Prioritized pickup plan

Do not combine these into one large change. Pick the first trace-proven item and keep
each benchmark independently reversible.

1. **Image ownership and eviction** — remove duplicate unbounded retention, introduce
   per-key observation, and measure memory/invalidation before and after.
2. **Decode/downsample pipeline** — move synchronous decode off `MainActor` and
   downsample to display size.
3. **Foundation publication cadence** — coalesce partials and update generated entries
   by stable ID.
4. **Extraction task ownership** — retain, replace, and cancel the extraction task.
5. **RealityKit collision preparation** — use a supported asynchronous path or
   explicitly document unavoidable main-actor cost and defer interaction.
6. **Concrete row-view routing** — prototype removal of `AnyView` for one thumbnail
   list before redesigning the protocol.
7. **Weather lifecycle gating** — pause animation for inactive/occluded scenes if S7
   proves offscreen work.
8. **Derived view data** — move only measured repeated filters/sorts to update
   boundaries.
9. **Resource cache limits** — apply cost/count limits based on S3/Allocations data.
10. **Conditional identity cleanup** — replace only `applyIf` branches shown by the
    Cause & Effect graph to recreate expensive rows.

## Verification performed

- XcodeBuildMCP build, install, and launch:
  - scheme: `MasterRPG`
  - configuration: Debug
  - destination: iPhone 17 Pro simulator
  - result: succeeded
  - diagnostics: 0 warnings, 0 errors
- Instrumentation compiles under the project’s Swift 6 complete strict-concurrency
  configuration.
- No performance behavior was intentionally changed; this pass adds observability and
  a fix backlog only.

## Apple references

- [OSSignposter](https://developer.apple.com/documentation/os/ossignposter)
- [Recording performance data](https://developer.apple.com/documentation/os/recording-performance-data)
- [Points of Interest log category](https://developer.apple.com/documentation/os/OSLog/Category/pointsOfInterest)
- [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)
- [Understanding hangs in your app](https://developer.apple.com/documentation/xcode/understanding-hangs-in-your-app)
- [Optimize SwiftUI performance with Instruments (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/306/)
- [Visualize and optimize Swift concurrency (WWDC22)](https://developer.apple.com/videos/play/wwdc2022/110350/)
- [Swift Task](https://developer.apple.com/documentation/swift/task/)
