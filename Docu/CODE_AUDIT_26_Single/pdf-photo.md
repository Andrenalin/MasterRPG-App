# PdfRPG + PhotoRPG audit (2026-11-14) -- PARTIAL, being extended

Files read so far: all of Modules/PdfRPG (Controller, Model, Pdf, Root, Route, View, Intent, Menu) and, of Modules/PhotoRPG, Controller, Model, ShareImport. Photo views/Photo/Space/Root/Intent still in progress. The old CODE_AUDIT_Pdf / CODE_AUDIT_Photo reports are essentially all fixed in code (entry search, MainActor decode, download error, equatable row, repaired uuid, privacy, JPEG export are gone); remaining findings are narrower. Overall health: good.

### PdfRPG keeps private repairedUuid clones of the shared CoreRPG helper
- Category: Duplication
- Location: Modules/PdfRPG/Controller/DataController.swift:43-58 (shared helper: Modules/CoreRPG/Persistence/ManagedObject+RepairedUuid.swift:12, used by Modules/PhotoRPG/Controller/DataController.swift:24,35,64)
- What: Two private overloads repeat the shared `repairedUuid(of:at:)` logic (and a second log string).
- Why: Fixes to the shared helper (logging, persistence of the repair) will not reach Pdf.
- Action: Delete the clones and call `repairedUuid(of:at: \.uuid)` like Photo.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_25 §9.2]

### Pdf viewer does not reload when the item's file is replaced in place
- Category: Bug
- Location: Modules/PdfRPG/Root/ViewerRootView.swift:90-111 (task), Modules/PdfRPG/Pdf/PdfSearchModel.swift:30-36, Modules/CoreRPG/Controllable/ItemControllable.swift:243-250
- What: The load runs in `.task(id: model)` where `model` is a class instance that `ItemControllable.replace` mutates in place (`original.replace(with:)`), so the id never compares unequal; and even when it reloads, `pdfDoc` is `@ObservationIgnored` and `pdfId` (the only observed trigger for a new `PDFView`) is unchanged, so the displayed `PDFView` keeps the old document.
- Why: Replacing the file of a PDF that is open (second window on macOS/visionOS, shared game PDF updated by the GM, sync from another device) leaves the old pages on screen until the viewer is reopened. Unverified at runtime.
- Action: Key the task and the `.id` on `model.version` / `fileUrl_.update` instead of the reference, and make the document change an observed state change.
- Severity: Medium
- Status: NEW (unverified at runtime)

### PdfWrapperView.updateView mutates observable state during the SwiftUI update pass
- Category: SwiftUI
- Location: Modules/PdfRPG/Pdf/PdfWrapperView.swift:99-113
- What: `updateView` (called from updateUIView/updateNSView) sets `searchModel.isSearching = true`, an observed property read by `ViewerRootView.body` (Modules/PdfRPG/Root/ViewerRootView.swift:41).
- Why: Writing observed state from inside the update pass can produce "modifying state during view update" runtime warnings and a second update cycle; behaviour is not guaranteed.
- Action: Start the find from `.onChange(of: searchModel.searchText)` / a `.task(id:)` in the SwiftUI view instead of in `updateView`.
- Severity: Low
- Status: NEW (unverified at runtime)

### Search highlights stay on the page after a search is dismissed
- Category: Bug
- Location: Modules/PdfRPG/Pdf/SearchBar.swift:20-26, Modules/PdfRPG/Pdf/PdfWrapperView.swift:152-155
- What: Leaving search only does `searchModel.matches = []`; `pdfView.highlightedSelections`, `currentIndex` and `setSearchMatch` are never reset.
- Why: The yellow match highlights remain until the viewer is recreated.
- Action: Clear the highlights (via a `clearSearch` closure/the stored `pdfView`) when `isSearching` ends and reset `currentIndex`.
- Severity: Low
- Status: NEW

### Share-link toggle spawns an untracked Task and swallows errors
- Category: Concurrency
- Location: Modules/PhotoRPG/Controller/LinkController.swift:25-33 (try? swallow), Modules/PdfRPG/Controller/LinkController.swift:23-34 (logged but untracked)
- What: `Task { ... }` is unowned; Photo discards the `createGameData` error with `try?`, Pdf only logs.
- Why: A failed share (file not downloaded) gives the GM no feedback; the two modules' copies have already drifted.
- Action: Move the branch into one shared helper in CoreRPG (`standardToggleResult` neighbour) that surfaces the error through the existing toast mechanism.
- Severity: Low
- Status: [OPEN since CODE_AUDIT_Pdf §5.7] (Photo: NEW)

### Dead "use PDF selection / text extracted" plumbing between the PDF viewer and four quick editors
- Category: Dead code
- Location: Modules/PdfRPG/Root/ViewerRootView.swift:15,26,30 (`onTextExtracted` stored, never called); Modules/PdfRPG/Controller/ViewController.swift:30-32; Modules/PdfRPG/View/DetailFolderListView.swift:33; Modules/PdfRPG/Model/PdfViewerActions.swift:1-52 (no `@Environment(\.pdfViewerActions)` reader exists); writers: Modules/AdventureRPG/View/QuickEntryEditor.swift:34,49, Modules/CharacterRPG/View/QuickEntryEditor.swift:36,51, Modules/MapRPG/View/QuickEntryEditor.swift:33,46, Modules/TableRPG/View/QuickEntryEditor.swift:34
- What: Both consumers (`onTextExtracted?(...)` and the `pdfViewerActions` reader) were removed in 34b71c2cd; the parameter, the environment key and the closures in the quick editors (`usePdfSelection(selection:)`) remain and nothing invokes them.
- Why: The editors look like they can pull text out of a PDF into an entry, but selecting text in the viewer does nothing there (the selection only feeds the bookmark bar); misleading code and an API users may assume works.
- Action: Either restore the call (e.g. offer "use selection" from `PdfContentView`'s selection) or delete the parameter, `PdfViewerActions` and the four editor closures.
- Severity: Medium
- Status: NEW

### "Convert to JPEG" runs the JPEG encode on the main actor and re-encodes from the 8192 px capped decode
- Category: Performance
- Location: Modules/PhotoRPG/Controller/EditController.swift:20-31 (`@MainActor convert`), Modules/CoreRPG/Extensions/Image+AKImage.swift:230,244 (decode cap)
- What: `convert(itemId:)` is `@MainActor`, takes the cached full image (decoded with `maximumDecodedPixelSize = 8192`) and calls `jpegData(compressionQuality:)` inline; the import paths encode off-main (`@concurrent encodedJPEG`, CODE_AUDIT_21 §7.10), this one was missed.
- Why: A large PNG/HEIC/TIFF hitches the UI during the encode, and a source wider than 8192 px is permanently downscaled by the conversion (the original file is replaced) without telling the user.
- Action: Encode through the same `@concurrent` helper, and convert from the original data/URL (or refuse/warn) instead of the capped cache image.
- Severity: Medium
- Status: NEW

### isNotJpegPhoto is case-sensitive, so ordinary .JPG/.JPEG photos are offered "Convert to JPEG"
- Category: Bug
- Location: Modules/PhotoRPG/Controller/EditController.swift:33-37, Modules/CoreRPG/Files/FileUrl.swift:177-179 (`fileExtension` returns `pathExtension` unchanged), Modules/PhotoRPG/View/ConvertImageEditor.swift:10
- What: The check compares the raw extension to "jpg" / "jpeg"; the file import keeps the picked file name (`IMG_0001.JPG`).
- Why: Camera/Files JPEGs with upper-case extensions show the convert action; running it re-encodes a JPEG lossy and (see above) can downscale it.
- Action: Compare lowercased, and also accept `jpe`; better, decide from the content type of the stored file.
- Severity: Low
- Status: NEW

### PhotoEntity data export PNG-encodes the full cached image
- Category: Performance
- Location: Modules/PhotoRPG/Intent/PhotoEntity+Image.swift:12-17, Modules/PhotoRPG/Intent/PhotoEntity.swift:110-112
- What: The `.image` DataRepresentation returns `pngRepresentationData()` of the cached full-size image (up to 8192 px, tens of MB as PNG), and only if the image is already in the memory cache (`photo(for:)` never loads it).
- Why: Share/Shortcuts/drag consumers choosing this representation either get a multi-second, very large PNG or `AKImageEncodingError` for a photo that is simply not cached, although the FileRepresentation above resolves the real file.
- Action: Drop the data representation (the file representation covers images) or load the file data and return it as-is; do not encode on demand.
- Severity: Low
- Status: NEW

### ImagePresentationView tears down its per-frame sync on onDisappear but only sets it up in make
- Category: Bug
- Location: Modules/PhotoRPG/Space/ImagePresentationView.swift:73-96 (setup in `make`), 112-120 (teardown in `.onDisappear`)
- What: The `SceneEvents.Update` subscription, coalescing stream, sync task and `model.foregroundEntity` are created once in `RealityView.make`, but `.onDisappear` cancels them; nothing recreates them when the view appears again without a new `make`.
- Why: If the view disappears and reappears without being rebuilt (a tab/ornament/scene change inside the window), the window stops being re-fitted every frame and the weather/foreground attachment is never placed again (`placeForeground` returns early with `foregroundEntity == nil`). visionOS only, unverified on device. Also `frameSyncContinuation` / `sceneUpdateSubscription` are written to `@State` directly in `make`, while `cacheAvailableBounds` documents that this pattern warns, and a second `make` overwrites the old task without cancelling it.
- Action: Move set-up into `.onAppear`/a `.task` paired with the teardown, or tie teardown to the RealityView's own lifetime; cancel the previous task before replacing it.
- Severity: Medium
- Status: NEW (unverified on device)

### Dead environment and members in SelectionBar and ViewerRootView
- Category: Dead code
- Location: Modules/PdfRPG/Pdf/SelectionBar.swift:16-20 (`root`, `colorScheme`, `dismiss`, `reduceMotion` unused in `SelectionBar`), Modules/PdfRPG/Root/ViewerRootView.swift:21 (`navigator` unused in `ViewerRootView`), Modules/PhotoRPG/Model/PhotoEntryModel.swift:44-46 (`filter(with:) -> true`, no caller)
- What: Environment values read but never used cause re-evaluation for no reason (`colorScheme`/`dismiss` change on appearance switch); the Photo entry filter always returns true and is never called.
- Why: Noise and needless invalidation, and a copy of the exact "always matches" shape that was a High bug in Pdf (CODE_AUDIT_Pdf §5.1) if someone starts calling it.
- Action: Remove the unused properties; delete or implement the Photo entry filter.
- Severity: Low
- Status: NEW

### Test gaps for the file-backed paths
- Category: Test gap
- Location: Tests/PdfRPGTests, Tests/PhotoRPGTests
- What: No test covers `ItemController.pdfDocument(for:)` (download failure, cancellation, off-main decode), `PdfWrapperView.Coordinator` search hand-off (stale end-of-scan handling), `EditController.convert`/`isNotJpegPhoto`/`resetPhoto(data:)` (grep finds no reference), or `ShareImportPhotoController.fileName` outside FolderAuditPhotoTests.
- Why: These carry the most recent concurrency fixes (CODE_AUDIT_18/21/23) and are exactly where the findings above sit.
- Action: Add tests for convert (extension case, size cap), non-image data to `resetPhoto(data:)` returning false, and a fake `FileUrlDataController` for `pdfDocument(for:)` cancellation.
- Severity: Low
- Status: NEW

### AsyncThumbnailLoadKey comment is stale, FileUrl equality no longer compares data
- Category: Refactor
- Location: Modules/PhotoRPG/Photo/AsyncThumbnail.swift:62-64 vs Modules/CoreRPG/Files/FileUrl.swift:64-75
- What: The doc says `FileUrl`'s synthesized equality compares inline `Data`; `FileUrl.==` explicitly excludes `data`. `AsyncImageViewerLoadKey` (Photo/AsyncImageViewer.swift:129-133) holds the full `FileUrl` where the thumbnail key uses a field-wise key.
- Why: Misleading rationale for two different key styles in one module.
- Action: Update the comment and use one key type for both views.
- Severity: Low
- Status: NEW

Not audited in this area: Localizable.xcstrings contents, Core Data model files (RPGPdf/RPGPhoto .xcdatamodel), MockData.swift / PreviewData.swift fixtures, Menu/*Commands.swift, DetailEditorView / DetailListView / DetailFolderListView layout details in PdfRPG, Photo DetailFolderListView, the CoreRPG shared infrastructure (FileUrlDataController, GenericEditController, ImageCacheControllable) beyond the cited lines, runtime behaviour on visionOS/macOS (all findings marked unverified are static reading only).
