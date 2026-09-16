# MasterRPG — PhotoRPG Module Code Audit

Generated 2026-09-16. Scope: `Modules/PhotoRPG/` only — 63 Swift files, ~5,118 LOC, plus the `RPGPhoto` Core Data model. No `Dead/` or archived directory exists inside this module.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made. This module has clearly been through several prior audit passes (inline comments reference `CODE_AUDIT_9`, `_10`, `_13`), which shows in the results below: no Critical findings, and most categories are clean.

---

## 1. Executive summary

1. **[High] CRDT folder-merge produces non-deterministic entry order, breaking sync convergence** — §5.1 — `Modules/PhotoRPG/Model/PhotoModel.swift:123-133`
2. **[High] Shortcuts/Share export always declares the file as JPEG, even when the stored photo isn't** — §5.2 — `Modules/PhotoRPG/Intent/PhotoEntity.swift:64-73`
3. **[Medium] `PhotoDataController` name collides with the module's own `DataController` but does something unrelated** — §9.7 — `Modules/PhotoRPG/Controller/PhotoDataController.swift`
4. **[Medium] Unstructured `Task` in `fetchPhotoImage` doesn't propagate cancellation** — §3.1 — `Modules/PhotoRPG/Root/PhotoRootModel.swift:230-233`
5. **[Medium] Photo import/convert failures are silently swallowed with `try?`, no user feedback** — §5.3 — `Modules/PhotoRPG/Controller/EditController.swift:78-81` (+3 more sites)
6. **[Medium] Unstructured `Task` spawned on every RealityKit engine frame (~90Hz)** — §7.1 — `Modules/PhotoRPG/Space/ImagePresentationView.swift:57-61`
7. **[Medium] File-resolve fallback chain triplicated across the module** — §9.6 — `CacheController.swift:39-50,76-88` + `PhotoRootModel.swift:204-223`
8. **[Medium] `InlineImporterView.swift` (324 lines, largest in module) mixes reusable geometry math with view code** — §9.10
9. **[Low] Photo/campaign name logged at `.public` privacy** — §6.1 — `Modules/PhotoRPG/Controller/LinkController.swift:56`
10. **[Low] Seven dead-code items with zero call sites** (unused helper properties/methods + a fully-unused localization file) — §9.1–§9.5

---

## 2. Quick wins (≤30 min each)

- **Delete `PhotoRootModel.thumbnailSize`** — `Modules/PhotoRPG/Root/PhotoRootModel.swift:239`. Unused, and duplicates `CacheController.thumbnailTargetSize`.
- **Delete `PhotoRootModel.allPhotos(with:)` and `.requestImageCache(for:)`** — `Modules/PhotoRPG/Root/PhotoRootModel.swift:187-197`. Zero call sites repo-wide.
- **Delete `PhotoModel.hasPhoto`** — `Modules/PhotoRPG/Model/PhotoModel.swift:108-111`. Zero call sites.
- **Delete `RPGPhoto.entryOrNew(for:)`** — `Modules/PhotoRPG/Model/DataModel+Extensions.swift:16-18`. Dead wrapper; `DataController.applySnapshot` already calls the shared `childOrNew` directly.
- **Delete the dead `chooseText` property in `CarouselDropAreaView`** — `Modules/PhotoRPG/View/CarouselDropAreaView.swift:31-37`. `EmptyDropButton`'s own copy is the one actually rendered.
- **Delete `Resources/Localization+Extensions.swift`** — unused in this module; the file already follows the `bundle: .module` pattern everywhere else.
- **Fix the `mutliSelection` typo** — `Modules/PhotoRPG/Route/SelectionRoute.swift:8,20`, call site `Modules/PhotoRPG/View/EmptyDropButton.swift:20`.
- **Fix `.public` privacy on the photo-name log line** — `Modules/PhotoRPG/Controller/LinkController.swift:56`. Change to `.private`.
- **Replace the three hardcoded `"jpg"` literals** with `ModuleConfiguration().filenameExtension` — `Modules/PhotoRPG/Controller/PhotoDataController.swift:21,25,27`.

---

## 3. Concurrency

### 3.1 Unstructured priority-boosted `Task` discards structured cancellation
- **Location:** `Modules/PhotoRPG/Root/PhotoRootModel.swift:230-233`
- **What:** `fetchPhotoImage(for:useGame:)` wraps `editController.loadImage(...)` in a new unstructured `Task(priority: .userInitiated) { ... }`, awaits `.result`, then discards that return value and re-reads the image from the cache.
- **Why:** An unstructured `Task` is not automatically cancelled when the enclosing async function's own task is cancelled (e.g. SwiftUI's `.task(id:)` cancelling on rapid photo navigation), so a cancelled caller still leaves the priority-boosted decode/iCloud-download running to completion in the background. The wrapping also adds nothing over calling `loadImage` directly except priority elevation, and the task's own result is thrown away.
- **Action:** Call `await editController.loadImage(...)` directly and use its return value, or if priority elevation is genuinely needed, retain the task handle and cancel it via `withTaskCancellationHandler` when the caller is cancelled.
- **Severity:** Medium

Everything else checked for this section came back clean, confirmed by direct reading (not just grep): all 4 `@Observable` classes in the module (`PhotoModel`, `GameToolBarModel`, `PhotoRootModel`, `ImagePresentationModel`) are correctly `@MainActor`-annotated; no `nonisolated(unsafe)`, `Task.detached`, `NSLock`/`OperationQueue`/`DispatchSemaphore`, `@unchecked Sendable`, or completion-handler PhotoKit usage anywhere in the module. The one `withCheckedThrowingContinuation` (`Controller/ItemController.swift:53-61`, wrapping `NSItemProvider.loadDataRepresentation`) has no async equivalent and is legitimate. `PhotoModel`'s `nonisolated` `Equatable`/`Comparable`/`ItemDiffComparable` conformances use a documented `assumeMainActorIsolated { }` helper — an established, module-wide pattern, not a local issue. `CacheController.decodedImage` correctly uses `@concurrent` to move CPU-bound decode off the main actor.

---

## 4. API modernity

_No findings._ Confirmed by direct reading: zero occurrences of `DateFormatter`/`NumberFormatter`/`MeasurementFormatter`, `replacingOccurrences`, string-based Documents-dir construction, `Task.sleep(nanoseconds:)`, `DispatchQueue`, `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject`/`@EnvironmentObject`, single-parameter `onChange(of:)`, `cornerRadius()`, `foregroundColor()`, or `tabItem()`. `UIImagePickerController` in `CaptureImagePicker.swift` is retained deliberately — no async/`PhotosPicker`/`PHPickerViewController` equivalent supports live camera capture.

---

## 5. Bugs / logic errors

### 5.1 CRDT folder-merge produces non-deterministic entry order across devices
- **Location:** `Modules/PhotoRPG/Model/PhotoModel.swift:123-133` (the `.folder` branch of `merge(_:)`); root cause in `Modules/PhotoRPG/Model/PhotoEntryModel.swift:20-23`
- **What:** When merging a folder-category `PhotoModel`, entries are deduplicated via `Set(entries.map(\.id)).union(...)` and then "sorted" by `$0.name.localizedCompare($1.name)` — but `PhotoEntryModel.name` is a hardcoded constant getter that always returns `"Photo"`, so the sort is a no-op and the resulting order is whatever order `Set<UUID>` happened to iterate in.
- **Why:** `Set` iteration order depends on the process's randomized hash seed, so two devices (Master/Player) merging identical underlying entries can end up with different `entries` array order. `PhotoModel.isSame(_:)` (`Model/PhotoModel.swift:153-170`) compares entries by index (`entries.enumerated().allSatisfy { entry == other.entries[index] }`), so this makes two objectively-identical photo folders compare as "different" forever — defeating CRDT convergence and causing repeated, unnecessary re-syncs/broadcasts of the same folder during a live game session.
- **Action:** Give `PhotoEntryModel` a stable, meaningful sort key (e.g. the referenced photo's own name, or a persisted insertion index) instead of sorting by a constant string, or sort the merged array by `id` for determinism.
- **Severity:** High
- **Note:** the identical `Set(...).union(...).sorted { $0.name... }` pattern (with an equally-constant `.name` — `"Track"` for `AudioEntryModel`, `"Space Model"` for `SpaceEntryModel`) exists in `AudioRPG/Model/AudioModel.swift:127-138` and `SpaceRPG/Model/SpaceModel.swift` and is almost certainly the same bug there — outside this audit's scope, flagged for a follow-up sweep.

### 5.2 PhotoEntity Shortcuts export always claims JPEG even when the stored file isn't JPEG
- **Location:** `Modules/PhotoRPG/Intent/PhotoEntity.swift:64-73`
- **What:** The `Transferable`/App Intents export hard-declares the exported file's UTType as `.jpeg` in `FileRepresentation(exportedContentType: .jpeg)` regardless of the actual bytes at `loadableUrl(itemId:)`.
- **Why:** Not every import path converts to JPEG — `InlineImporterView`'s `.fileImporter` (`Photo/InlineImporterView.swift:220-224`) and Image Playground import (`:231-238`) call `resetFile(url:itemId:)` directly with no JPEG conversion, and `EditController.isNotJpegPhoto(itemId:)` (`Controller/EditController.swift:46-50`) plus the user-facing "Convert to JPEG" button (`View/ConvertImageEditor.swift`) exist specifically because non-JPEG stored photos are an expected, common state. Handing Shortcuts/Share Sheet/drag-out consumers a file whose real format (PNG/HEIC/TIFF/etc.) doesn't match the declared `.jpeg` UTI can cause the receiving app/automation to reject or mis-decode the file.
- **Action:** Derive `exportedContentType` from the stored file's actual UTType/extension (e.g. via `FileUrl.fileExtension`) instead of the fixed `.jpeg` constant.
- **Severity:** High

### 5.3 Photo import/convert failures are silently swallowed with no user-facing feedback
- **Location:** `Modules/PhotoRPG/Controller/EditController.swift:78-81` (`resetPhoto` → `try? await resetFile(...)`); `Modules/PhotoRPG/View/ConvertImageEditor.swift:12-15` (`try? await root.editController.convert(itemId:)`); `Modules/PhotoRPG/Photo/InlineImporterView.swift:220-224, 231-238, 240-248, 263-270` (file importer, Image Playground, PhotosPicker, macOS drag-drop)
- **What:** Every user-initiated photo import path (camera, Photos library, Files, macOS drag-drop) and the manual "Convert to JPEG" action discards any thrown error via `try?` / `guard let ... else { return }`, with no error state, toast, or alert surfaced to the UI.
- **Why:** If the write/convert genuinely fails (disk full, iCloud container unavailable, corrupt data, decode failure), the user sees no photo appear and no explanation — indistinguishable from a slow load.
- **Action:** Surface a user-visible error (alert/toast) or at minimum log the discarded error at all four sites, mirroring the `imageError` state pattern already used in `AsyncImageViewer.swift` for load failures.
- **Severity:** Medium

### 5.4 Force-unwrapped URL literal (benign, but inconsistent with project style)
- **Location:** `Modules/PhotoRPG/Controller/PhotoDataController.swift:21`
- **What:** `let fileUrl = URL(string: "/")!.appending(component: "\(name).jpg")` force-unwraps `URL(string: "/")`.
- **Why:** The literal `"/"` will always parse successfully, so this isn't a real crash risk today (the adjacent comment explains it replaced a worse prior force-unwrap on the user-supplied `name`) — but it's the only remaining force-unwrap in the module outside `#Preview` code, and violates the project's "avoid force unwraps" convention.
- **Action:** Replace with a non-force-unwrap construction (e.g. `guard let base = URL(string: "/") else { ... }`) for consistency.
- **Severity:** Low

---

## 6. Security

### 6.1 Photo/campaign content logged at public privacy
- **Location:** `Modules/PhotoRPG/Controller/LinkController.swift:56`
- **What:** `Logger.linkController.info("Photo: \(replacedItem.name, privacy: .public) will be replaced from repairing links.")` logs the photo's user-authored name at `.public` privacy.
- **Why:** Unlike the module's other log statements (which log UUIDs or system error descriptions at `.public`), this logs actual user/campaign content into the system log, readable via Console.app/sysdiagnose by anyone with device access.
- **Action:** Change the privacy annotation to `.private`, or drop the name from the log message.
- **Severity:** Low

No other security issues found: no hardcoded secrets/tokens/API keys anywhere in the module (grepped for `Bearer`, `apiKey`, `secret`, `Authorization`, base64 blobs). Every `RPGPhoto`/`RPGPhotoEntry` Core Data attribute has a default value or is optional, and both relationships (`entries`/`photo`) are optional — compliant with the project's `NSPersistentCloudKitContainer` requirements. `PhotosPicker`-based import needs no explicit Photos-library authorization handling (the modern picker API is sandboxed and doesn't require it).

---

## 7. Performance

### 7.1 Unstructured `Task` spawned on every RealityKit engine frame for spatial image sync
- **Location:** `Modules/PhotoRPG/Space/ImagePresentationView.swift:57-61`
- **What:** `content.subscribe(to: SceneEvents.Update.self) { _ in Task { @MainActor in syncPresentation() } }` creates a brand-new `Task` on every RealityKit per-frame engine tick (~90Hz on visionOS) purely to hop onto MainActor.
- **Why:** `syncPresentation()` itself is cheap, but allocating and scheduling a fresh unstructured `Task` up to 90 times/second for the lifetime of the space window is avoidable overhead. The extensive doc comment above explains *why* the subscription exists (a RealityKit-engine-timing workaround) but not why a fresh `Task` per frame is needed just to reach MainActor.
- **Action:** Consider a single long-lived `AsyncStream`/actor hop, or gate the per-frame work so a new `Task` is only spawned when the cached bounds actually changed.
- **Severity:** Medium

No other performance issues found: no per-frame `CIContext` allocation, no repeated JPEG/HEIC re-encoding during pinch-zoom/pan (gesture updates operate on cached `AKImage`/geometry transforms, not re-decoded data), no full-resolution decode where ImageIO downsampling would do (`CacheController.downsampledSource`/`PhotoRootModel.fetchPhotoThumbnailSource` already use `AKImage.downsampledThumbnail`), and no synchronous PhotoKit/file I/O on the main actor (`CacheController.decodedImage` is explicitly `@concurrent`).

---

## 8. SwiftUI / UI

_No findings._ The module's SwiftUI surfaces (`View/`, `Photo/`, `Space/`, `Root/ViewerRootView.swift`) were reviewed in full against the SwiftUI Expert Skill's correctness checklist and latest-API list. This code already reflects several completed prior audit passes: leaf views used in `ForEach`/carousel contexts (`InlineImporterView`, `InlineRowViewer`) explicitly conform to `Equatable` with hand-written `==` that documents why each stored property is included; repeatedly-rendered subviews were already extracted out of computed `some View` properties into dedicated `View` structs (see the "Extracted subviews (CODE_AUDIT §8.3)" comments in `AsyncThumbnail.swift` and `InlineImporterView.swift`) to give SwiftUI its own diffing boundary; `ForEach` uses stable `UUID`-based identity, never indices (`CarouselPhotoView.swift:13`); modern `onGeometryChange(for:action:)` replaces `GeometryReader` where only a size read is needed (`ViewerRootView.swift:97-101`); accessibility labels/hints/values/custom actions are present throughout the image viewer and carousel views; `reduceMotion` is consistently checked before every `withAnimation`. No `@State` was found declared on a value owned by a parent, no missing `private` on `@State`, and no soft-deprecated API usage.

---

## 9. Dead code / duplication / refactor

Checked and confirmed clean: zero `TODO`/`FIXME`/`HACK`/`XXX`/`#warning` markers and zero `#if false` blocks anywhere in the module. Every `RPGPhoto`/`RPGPhotoEntry` Core Data attribute is consumed by `DataController`'s snapshot mapper — no stale schema fields.

### 9.1 Dead code: unused `chooseText` duplicate in `CarouselDropAreaView`
- **Location:** `Modules/PhotoRPG/View/CarouselDropAreaView.swift:31-37` (live duplicate at `Modules/PhotoRPG/View/EmptyDropButton.swift:37-43`)
- **What:** `CarouselDropAreaView.chooseText` is declared but never referenced in the file's body — the body renders `EmptyDropButton`, which has its own copy of the same computed property.
- **Action:** Delete the dead property from `CarouselDropAreaView.swift`.
- **Severity:** Low

### 9.2 Dead code: `Resources/Localization+Extensions.swift` entirely unused
- **Location:** `Modules/PhotoRPG/Resources/Localization+Extensions.swift:1-15`
- **What:** `Bundle.localizedString(forKey:)` and `String.localizedString` are `internal` with zero call sites in `Modules/PhotoRPG`.
- **Why:** The module already uses the project-mandated `Text("...", bundle: .module)` / `String(localized:bundle:)` pattern everywhere, making this vestigial. The identical file is independently duplicated across ~11 other modules (PdfRPG, DiceRPG, WeatherRPG, AdventureRPG, GameRPG, CharacterRPG, GeneratorRPG, MapRPG, SpaceRPG, TableRPG, AudioRPG).
- **Action:** Delete from PhotoRPG. Consolidating the other copies (if any are actually used) is a separate, cross-module follow-up.
- **Severity:** Low

### 9.3 Dead code: unused `PhotoRootModel` members (`thumbnailSize`, `allPhotos(with:)`, `requestImageCache(for:)`)
- **Location:** `Modules/PhotoRPG/Root/PhotoRootModel.swift:187-197, 239`
- **What:** All three have zero call sites anywhere in the repo. `thumbnailSize` (`:239`, `CGSize(width: 64, height: 64)`) also silently duplicates the value actually used at `CacheController.thumbnailTargetSize` (`Controller/CacheController.swift:70`). `requestImageCache(for:)` is superseded in practice by `fetchPhotoThumbnailSource`/`fetchPhotoImage`, per its own doc comment's wording.
- **Action:** Delete all three, or confirm with the author whether any is meant for near-term use before removing.
- **Severity:** Low

### 9.4 Dead code: `PhotoModel.hasPhoto`
- **Location:** `Modules/PhotoRPG/Model/PhotoModel.swift:108-111`
- **What:** `var hasPhoto: Bool { fileUrl != nil }` has zero call sites; call sites like `DetailListView.swift:25` hand-inline the same `fileUrl != nil` check instead.
- **Action:** Delete, or use it in place of the hand-inlined checks.
- **Severity:** Low

### 9.5 Dead code: `RPGPhoto.entryOrNew(for:)`
- **Location:** `Modules/PhotoRPG/Model/DataModel+Extensions.swift:16-18`
- **What:** A one-line wrapper around the shared `childOrNew(_:in:)` with zero call sites — `DataController.applySnapshot` calls the shared `syncEntries`, which calls `childOrNew` directly, bypassing this wrapper entirely.
- **Why:** The identical dead pattern is duplicated in at least 9 sibling modules' own `DataModel+Extensions.swift` files.
- **Action:** Delete from PhotoRPG; flag the sibling-module copies for a follow-up sweep.
- **Severity:** Low

### 9.6 Duplicated helper: file-data resolution fallback chain repeated 3× within the module
- **Location:** `Modules/PhotoRPG/Controller/CacheController.swift:38-50` (`decodedImage`), `:76-88` (`downsampledSource`); `Modules/PhotoRPG/Root/PhotoRootModel.swift:203-223` (`fetchPhotoThumbnailSource`)
- **What:** All three methods independently implement the identical three-branch fallback — "use `fileUrl.data` if inline, else `fileUrlDataController.loadData(for:)`, else fall back to `.url(for:)` and decode from a file URL" — varying only in which `AKImage` decode call is applied to the resolved source.
- **Why:** Three near-verbatim ~10-13 line copies of nontrivial control flow means any future fix to the iCloud-availability/fallback logic must be applied in 3 places.
- **Action:** Extract a shared generic helper (e.g. on `FileUrlDataController`, parameterized by a decode closure) that all three call sites use.
- **Severity:** Medium

### 9.7 Naming collision: `PhotoDataController` vs `DataController`
- **Location:** `Modules/PhotoRPG/Controller/PhotoDataController.swift:1-37` vs `Modules/PhotoRPG/Controller/DataController.swift:1-88`
- **What:** Both structs live in `Controller/` with near-identical names but unrelated responsibilities. Per the project's documented architecture, `DataController` correctly fills the "mapper between domain model and database model" role. `PhotoDataController` is actually a standalone helper used only by the Share Extension (`Sources/RPGShare/ShareExtensionSaveController.swift`) to synthesize a new Photo item from raw shared `Data` — unrelated to `DataController`'s job.
- **Why:** Every other module's mapper is simply called `DataController`, so a reader naturally expects "PhotoDataController" to be PhotoRPG's own mapper — actively misleading.
- **Action:** Rename to something reflecting its actual purpose, e.g. `ShareImportPhotoController`.
- **Severity:** Medium

### 9.8 Naming typo: `mutliSelection` enum case
- **Location:** `Modules/PhotoRPG/Route/SelectionRoute.swift:8, :20`; call site `Modules/PhotoRPG/View/EmptyDropButton.swift:20`
- **What:** `SelectionRoute.mutliSelection` is a transposed-letter misspelling of "multiSelection."
- **Action:** Rename to `multiSelection` (2 declaration sites + 1 call site).
- **Severity:** Low

### 9.9 Magic string: `"jpg"` extension hardcoded 3× instead of referencing config
- **Location:** `Modules/PhotoRPG/Controller/PhotoDataController.swift:21, :25, :27`; canonical value at `Modules/PhotoRPG/Root/ModuleConfiguration.swift:13`
- **What:** `addNewPhoto` hardcodes the literal `"jpg"` three times instead of reading `ModuleConfiguration().filenameExtension`, the module's actual single source of truth.
- **Why:** If the module's file-extension policy ever changes, this function silently drifts out of sync.
- **Action:** Replace the three literals with a reference to `ModuleConfiguration().filenameExtension`.
- **Severity:** Low

### 9.10 Oversized files (4)
- **`Modules/PhotoRPG/Photo/InlineImporterView.swift:1-324`** (largest in module) — the `PhotoImporterButtonType` enum (`:15-95`) is an 80-line, self-contained, non-SwiftUI data type (icon/label/duration/fan-out-offset trigonometry for the 5 importer buttons) with nothing to do with view rendering. Extract to `Photo/PhotoImporterButtonType.swift`. Severity: Medium.
- **`Modules/PhotoRPG/Model/PhotoModel.swift:1-310`** — the `Codable` extension (CodingKeys + `encode(to:)`, `:266-297`) is a self-contained ~30-line block, already delimited by its own `// MARK:`. Extract to `PhotoModel+Codable.swift`. Severity: Low.
- **`Modules/PhotoRPG/Photo/ImageViewer.swift:1-290`** — the `#if !os(tvOS)` gesture-session extension (`:217-275`) is a separable, platform-conditional ~58-line chunk already marked with its own `// MARK: - Gesture session`. Extract to `ImageViewer+Gestures.swift`. Severity: Low.
- **`Modules/PhotoRPG/Root/PhotoRootModel.swift:1-265`** — the trailing `// Other` extension (`:186-265`, ~80 lines: photo-access API surface) is separable from the constructor/property bulk of the class. Extract to `PhotoRootModel+PhotoAccess.swift`. (Shrinks below 250 lines once the dead members in §9.3 are removed, but still reads as a distinct API surface.) Severity: Low.

### 9.11 False-positive naming suspects resolved (no action needed)
- **Location:** `Modules/PhotoRPG/Controller/FolderListController.swift`, `Modules/PhotoRPG/View/DetailFolderListView.swift`
- **What:** Both matched a `*dead*/*old*/*legacy*` naming grep only because "Folder" contains the substring "old" (F-**old**-er). Both are live, actively-used code: `FolderListController` is instantiated twice in `PhotoRootModel.swift`; `DetailFolderListView` is the body of `DetailListView`.
- **Severity:** Low (informational only)

---

## 10. Cross-cutting recommendations

1. **CRDT entry-name placeholders break merge determinism app-wide, not just in PhotoRPG.** §5.1's root cause (a hardcoded `EntryDataAccessable.name` used as a sort key during merge) is very likely replicated in `AudioRPG/Model/AudioModel.swift` and `SpaceRPG/Model/SpaceModel.swift`. Worth a dedicated sweep across all modules whose entry model has a constant `name`.
2. **A handful of dead single-module helper types (`entryOrNew`, `Localization+Extensions.swift`) are copy-pasted per-module boilerplate that nobody calls.** Rather than clean up module-by-module, a repo-wide grep for these exact symbol/file names across `Modules/*/Model/DataModel+Extensions.swift` and `Modules/*/Resources/Localization+Extensions.swift` would likely clear a consistent, low-risk chunk of dead code in one pass.
3. **The "extract into its own file at N-line threshold" pattern is already established in this module** (see the `CODE_AUDIT §8.3`-referenced subview extractions). Applying the same discipline to the 4 files in §9.10 is a mechanical, low-risk follow-up.
4. **Error-swallowing via bare `try?` on user-initiated actions (§5.3) is a UX gap, not a correctness bug** — worth checking whether sibling modules' importers (Pdf, Audio, Space) have the same silent-failure shape, since they likely share similar import call patterns.

---

## 11. What was NOT audited

- Every other module (`AdventureRPG`, `AudioRPG`, `CharacterRPG`, `DiceRPG`, `MapRPG`, `SpaceRPG`, `TableRPG`, `WeatherRPG`, `RuleRPG`, `CoreRPG`, `GeneratorRPG`, `GameRPG`, `RolePlayGameKit`) — scope was `Modules/PhotoRPG/` only, per the request. Findings that reference sibling-module duplication (§5.1's note, §9.2, §9.5) were spotted incidentally via grep, not independently verified in those modules.
- The `Sources/RPGShare` share-extension target's own code, beyond confirming it's `PhotoDataController`'s only caller (§9.7).
- Compiler warnings: a full `xcodebuild` of the `MasterRPG` scheme succeeded with **zero warnings** overall (including PhotoRPG), so there was no compiler-warning corpus to trace — this module's concurrency correctness was verified entirely by manual reading against Swift 6 strict-concurrency rules, not warning triage.
- Algorithmic correctness of the viewport/gesture geometry math (`ImageViewportGeometry.swift`, `ImageViewer`'s zoom/pan transforms) — read for structure and concurrency, not verified against expected pixel-level output.
- Build settings, scheme configuration, entitlements, and Xcode project structure beyond what's visible in source.
- Third-party/SPM dependency internals (`CoreRPG`'s `AKImage`, `FileUrlDataController`, `ImageCacheControllableStorage` etc. were treated as black boxes with their documented contracts).
- Test coverage — no PhotoRPG-specific test target was located/reviewed in this pass.
- Localization wording quality — only presence/absence of the `bundle: .module` pattern was checked, not translation correctness.
- Instruments/runtime profiling — performance findings are static-analysis based (allocation patterns, per-frame Task counts), not measured via a `.trace` capture.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line.

- **§5.1** — open `Modules/PhotoRPG/Model/PhotoModel.swift`, lines 128-133: confirm the `.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }` call, then open `Modules/PhotoRPG/Model/PhotoEntryModel.swift`, lines 20-23: confirm `var name: String { get { "Photo" } set {} }` — the sort key is provably constant.
- **§5.2** — open `Modules/PhotoRPG/Intent/PhotoEntity.swift`, line 68: confirm `FileRepresentation(exportedContentType: .jpeg)` has no branch on the actual file's extension/UTType.
- **§3.1** — open `Modules/PhotoRPG/Root/PhotoRootModel.swift`, lines 230-233: confirm the unstructured `Task(priority: .userInitiated) { ... }` followed by `_ = await loaderTask.result` and a separate cache re-read.
- **§7.1** — open `Modules/PhotoRPG/Space/ImagePresentationView.swift`, lines 57-61: confirm `content.subscribe(to: SceneEvents.Update.self) { _ in Task { @MainActor in syncPresentation() } }` inside the `RealityView`'s `make` closure (fires per-frame, not per-SwiftUI-update).
- **§9.6** — open `Modules/PhotoRPG/Controller/CacheController.swift` lines 39-50 and 76-88, then `Modules/PhotoRPG/Root/PhotoRootModel.swift` lines 204-223: confirm the same `if let data = fileUrl.data { ... } else if let data = try? await fileUrlDataController.loadData(...) { ... } else { fileUrlDataController.url(for:) { ... } }` shape in all three.
- **§9.7** — open `Modules/PhotoRPG/Controller/PhotoDataController.swift` and `Modules/PhotoRPG/Controller/DataController.swift`: confirm the two types' actual responsibilities diverge from what their names suggest.

If any finding doesn't reproduce when you visit the line, flag it and it'll be re-investigated.
