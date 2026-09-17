# MasterRPG — PdfRPG Module Code Audit

Generated 2026-09-17. Scope: `Modules/PdfRPG/` only — 54 Swift files, ~4177 LOC (Controller/, Intent/, Menu/, Model/, Resources/, Root/, Route/, View/, Pdf/). No directories excluded (no `Dead/` or archive folder exists under this module). This module has clearly been through prior audit rounds already — most files carry `// See CODE_AUDIT_* §n.n` comments documenting previously-fixed issues — so findings here are generally residual/narrower than a first-pass audit would surface.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made. Every Critical/High claim below was personally opened and verified against the source (including the CoreRPG shared infrastructure PdfRPG depends on) before being included — see §12.

---

## 1. Executive summary

1. **[High] Entry-level PDF bookmark/content search always matches, silently broken** — §5.1 — `Modules/PdfRPG/Model/PdfEntryModel.swift:62-64`. Any PDF with at least one bookmark matches every search string.
2. **[High] PDF documents decoded synchronously on the MainActor** — §7.1 — `Modules/PdfRPG/Controller/ItemController.swift:38-47`. Opening a large rulebook PDF blocks the UI thread.
3. **[High] Concurrent bookmark edits can be silently dropped on CRDT merge** — §5.2 — `Modules/PdfRPG/Model/PdfModel.swift:117-144`. Whole-array last-writer-wins instead of the per-id union the code already uses for folders.
4. **[High] Primary PDF viewer has no failure state; iCloud download errors are silently swallowed** — §5.3 — `Modules/PdfRPG/Controller/ItemController.swift:39-46`, `Root/ViewerRootView.swift:88-106`. Spins forever instead of showing the `.unavailable` state its sibling views already have.
5. **[High] `InlineRowViewer`'s custom `Equatable` defeats `@Observable` staleness tracking** — §8.1 — `Modules/PdfRPG/View/InlineRowViewer.swift:64-66`. Inline PDF references can go stale indefinitely.
6. **[High] CoreData `uuid` fallback mints a fresh random identity instead of failing loudly** — §5.4 — `Modules/PdfRPG/Controller/DataController.swift:24,30,77`. Risks duplicated/orphaned items on a transient nil (which the project's own CloudKit-optionality rule makes a real possibility).
7. **[Medium] Duplicated Loading/Unavailable/loadPDF scaffolding across two extraction views** — §9.2 — already caused a real copy-paste accessibility bug, §8.2.
8. **[Medium] `SheetController` duplicates its own `SheetModel`-construction helper instead of calling it** — §9.3.
9. **[Medium] `createBookmark(itemId:)`'s parameter is actually used as the entry's own id** — §5.8 — invites a future caller to pass a real item id and corrupt entry lookups.
10. **[Medium] Search filtering uses `localizedCaseInsensitiveContains` instead of the project-mandated `localizedStandardContains`** — §4.1.

---

## 2. Quick wins (≤30 min each)

- **Fix the entry-search bug** — `Model/PdfEntryModel.swift:62-64` — one-line logic fix, see §5.1.
- **Remove dead commented-out import** — `Pdf/PdfSearchModel.swift:3` (`//import CoreRPG`) — see §9.4.
- **Remove Xcode code-completion placeholder token** — `Pdf/SelectionBar.swift:73` (`/*@START_MENU_TOKEN@*/2/*@END_MENU_TOKEN@*/`) — see §8.5.
- **Remove dead `@Environment(\.dismiss)` property** — `Root/ViewerRootView.swift:21`, never read — see §8.3.
- **Fix copy-paste accessibility strings** — `View/SummaryAnalysisView.swift:33-34` say "extraction" instead of "analysis" — see §8.2.
- **Replace the stray force-unwrap in a ternary** — `Route/DetailRoute.swift:18` — see §5.6.
- **Add explicit `: Sendable`** to `Controller/SheetController.swift:6-8` for consistency with sibling controllers — see §9.6.
- **Swap `localizedCaseInsensitiveContains` → `localizedStandardContains`** at `Model/PdfModel.swift:192` and `Model/PdfEntryModel.swift:58-59` — see §4.1 (do alongside the §5.1 fix, same code path).
- **Remove the unused synchronous `PdfWrapperView.init(url:...)`** — `Pdf/PdfWrapperView.swift:33-38`, dead and reintroduces a main-thread decode if ever wired up — see §5.9.
- **Rename `createBookmark`'s `itemId` parameter** to `id`/`entryId` — `Controller/EditController.swift:62-70` — see §5.8.

---

## 3. Concurrency

### 3.1 Unchecked, module-wide Sendable conformance on PDFKit types
- **Location:** `Modules/PdfRPG/Pdf/PdfWrapperView.swift:20-21`
- **What:** `extension PDFDocument: @unchecked @retroactive Sendable {}` and the same for `PDFSelection` retroactively force these NSObject-based PDFKit types to conform to `Sendable`, module-wide.
- **Why:** PDFDocument/PDFSelection are not documented thread-safe by Apple; `@unchecked` removes all compiler protection against these values being captured/mutated from multiple isolation domains, and the conformance isn't scoped to safe call paths only.
- **Action:** Confine PDFDocument/PDFSelection strictly to `@MainActor` call paths (this audit found no violation today — see §12) or replace the blanket conformance with a narrower wrapper type that only exposes actor-isolated access.
- **Severity:** Medium

### 3.2 Data race risk in PDFKit find-delegate callback (previously reviewed, still unenforced)
- **Location:** `Modules/PdfRPG/Pdf/PdfWrapperView.swift:122-174` (`Coordinator` class), specifically `pendingMatches` (line 129), `didMatchString(_:)` (140-143)
- **What:** `Coordinator` is a plain `NSObject` (no actor isolation) whose `pendingMatches` array is mutated inside `didMatchString(_:)`, a `PDFDocumentDelegate` callback that PDFKit invokes off the main thread during `beginFindString(_:withOptions:)` — per the file's own comment (lines 125-128, citing a prior `CODE_AUDIT_9 §5.4`).
- **Why:** The safety argument ("no two matches for the same search arrive concurrently") is documented in a comment, not enforced by the compiler — a real data race under Swift 6 strict concurrency if that PDFKit delivery guarantee ever changes. This was already assessed once; flagging again because the underlying risk (an unenforced invariant) is still present, not because it's a new finding.
- **Action:** If revisited, isolate `Coordinator`'s mutable state behind an actor or hop to `@MainActor` inside `didMatchString(_:)` itself. Otherwise, no action needed beyond the existing documentation.
- **Severity:** Low

### 3.3 Redundant Task wrapping inside code already on the MainActor
- **Location:** `Modules/PdfRPG/Pdf/PdfWrapperView.swift:82-84` (`Task { @MainActor in searchModel.pdfView = pdfView }` inside the already-`@MainActor` `makeView()`)
- **What:** Creates an extra unstructured `Task` for a synchronous assignment that could run inline, since `makeView()` is already `@MainActor`.
- **Why:** Unnecessary Task creation adds scheduling overhead and defers a write that `updateView` may read on the very next SwiftUI cycle — a latent ordering hazard.
- **Action:** Assign `searchModel.pdfView = pdfView` directly; drop the `Task` wrapper.
- **Severity:** Low

### 3.4 Uncancellable nested Task keeps decoding a PDF after the viewer is dismissed
- **Location:** `Modules/PdfRPG/Root/ViewerRootView.swift:94-105`
- **What:** `.onChange(of: model, initial: true)` opens an outer `Task { let pdfTask = Task { await root.itemController.pdfDocument(for: id) }; let doc = await pdfTask.value; ... }`. Neither Task is structured (no `.task {}`, `async let`, or `TaskGroup`), so dismissing/navigating away from the view does not cancel either one, and the inner Task exists only to be immediately awaited — it adds a scheduling hop with no concurrency benefit.
- **Why:** A dismissed viewer keeps decoding the PDF (itself a heavyweight MainActor operation — see §7.1) in the background for no reason, wasting main-thread time on work nobody will see.
- **Action:** Replace the nested `Task { Task { ... } }` with a single Task calling `await root.itemController.pdfDocument(for: id)` directly, and consider switching `.onChange` + manual Task to a lifecycle-scoped `.task(id: model.id)` so dismissal cancels it automatically.
- **Severity:** Medium

---

## 4. API modernity

### 4.1 Search filtering uses `localizedCaseInsensitiveContains` instead of the mandated `localizedStandardContains`
- **Location:** `Modules/PdfRPG/Model/PdfModel.swift:192`; `Modules/PdfRPG/Model/PdfEntryModel.swift:58-59`
- **What:** Both the item-level filter (`PdfModel.filter(filter:includeEntries:)`, live code path) and the entry-level `filter(_:selectedTags:)` use `.localizedCaseInsensitiveContains(filter)`.
- **Why:** Project `CLAUDE.md` explicitly mandates `localizedStandardContains()` for all user-input text filtering — it additionally normalizes diacritics/whitespace/numeric ordering, not just case — and sibling module `TableEntryModel` already does this correctly for the identically-shaped case, so PdfRPG's search behaves inconsistently with the rest of the app.
- **Action:** Replace both call sites with `.localizedStandardContains(filter)`; do this alongside the §5.1 fix since it touches the same code paths.
- **Severity:** Medium

### 4.2 Combine-based NotificationCenter subscription instead of a modern async sequence
- **Location:** `Modules/PdfRPG/Pdf/PdfContentView.swift:39-49`
- **What:** `.onReceive(NotificationCenter.default.publisher(for: .PDFViewSelectionChanged))` uses the Combine-publisher bridge rather than `NotificationCenter.default.notifications(named:)` consumed via `for await`/`.task`.
- **Why:** Minor modernity gap given the project's stated preference for async/await over closure/publisher-based APIs when an async equivalent exists; a scoped `.task` also cancels more precisely than a Combine subscription.
- **Action:** Consider `.task { for await note in NotificationCenter.default.notifications(named: .PDFViewSelectionChanged) { ... } }`.
- **Severity:** Low

### 4.3 "Pdf" vs "PDF" capitalization inconsistency in App Intents / Siri surfaces
- **Location:** `Modules/PdfRPG/Intent/OpenPdfIntent.swift:12,14`; `Modules/PdfRPG/Intent/PdfShortcutCatalog.swift:28`; `Modules/PdfRPG/Intent/PdfEntity.swift:15-16` — vs. the consistently-capitalized `Modules/PdfRPG/Intent/PdfManagementIntents.swift:11,55,61,93,112`
- **What:** `OpenPdfIntent.title = "Open Pdf"`, its parameter title "Pdf", and the dialog "Which pdf?" use lowercase "df", while every other Siri/Shortcuts string in the module ("Create PDF", "Delete PDF", "Search PDFs") capitalizes the acronym correctly, per Apple HIG convention. `Resources/Localizable.xcstrings` now carries near-duplicate keys purely from this inconsistency (both `'Pdf'`/`'PDF'` and `'Which pdf?'`/`'Which PDF?'` coexist).
- **Why:** Looks unpolished in Shortcuts/Siri surfaces and bloats the localization catalog with near-duplicate strings that will drift in translation.
- **Action:** Change `OpenPdfIntent.swift:12,14` and `PdfShortcutCatalog.swift:28` to "PDF" consistently, then remove the now-orphaned lowercase entries from `Localizable.xcstrings`.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Entry-level PDF search always matches — bookmark/content search is non-functional
- **Location:** `Modules/PdfRPG/Model/PdfEntryModel.swift:62-64` (`func filter(with search: String) -> Bool { true }`); called from `Modules/PdfRPG/Model/PdfModel.swift:190-197`, specifically line 195 (`entries.contains { $0.filter(with: filter) }`)
- **What:** `PdfEntryModel.filter(with:)` is hard-coded to return `true` regardless of the search text. It's the exact method `PdfModel.filter(filter:includeEntries:)` calls to decide whether a PDF's bookmarks match a search query.
- **Why:** Any PDF with at least one bookmark/entry matches every search string once its own name/description don't match — entry-content search is completely non-functional. `PdfEntryModel.filter(_:selectedTags:)` (lines 57-60) already contains correct name/content matching logic but is never called from this path.
- **Action:** Replace `filter(with:)`'s body with real matching (`search.isEmpty || name.localizedStandardContains(search) || content.localizedStandardContains(search)`, mirroring `TableEntryModel.filter(with:)`), or have `PdfModel.filter` call the existing `filter(_:selectedTags:)` method instead.
- **Severity:** High
- **Verified:** yes — see §12.

### 5.2 Concurrent bookmark edits can be silently dropped on CRDT merge
- **Location:** `Modules/PdfRPG/Model/PdfModel.swift:117-144`, specifically the `else` branch at line 129; root-cause helper `Modules/CoreRPG/CRDT/CRDTDataUpdate.swift:30-34`
- **What:** `PdfModel.merge()` has two branches for `entries`: for `.folder` category it does an explicit id-based union (lines 122-127, `Set(entries.map(\.id)).union(...)`), but for every other category — i.e. an actual PDF item with bookmarks — it instead does `mergedEntries = entries_.merged(other: other.entries_)`, which resolves to `CRDTDataUpdate.merged()`: a last-writer-wins register over the *entire* `[PdfEntryModel]` array (confirmed: it picks either `_value` or `other._value` wholesale, based on which side's `update` UUID wins), not a per-entry merge.
- **Why:** If two devices each independently add a different bookmark to the same PDF before syncing, the merge picks one side's whole array and the other side's addition is discarded with no conflict surfaced — silent data loss. The `.folder` branch a few lines above is direct in-code evidence the author already knew whole-array LWW isn't safe here, but the fix wasn't applied to the default case.
- **Action:** Apply the same id-based union used for `.folder` unconditionally to `entries`, or give it a proper per-element merge instead of `CRDTDataUpdate.merged()`.
- **Severity:** High
- **Verified:** yes — see §12.

### 5.3 Primary PDF viewer has no failure state; iCloud download errors are silently swallowed
- **Location:** Root cause: `Modules/PdfRPG/Controller/ItemController.swift:39-46` (`try? await fileUrlDataController?.download(fileUrl: fileUrl)` discards the error unconditionally, including `CancellationError`); surfaced at `Modules/PdfRPG/Root/ViewerRootView.swift:88-106` and `Modules/PdfRPG/Pdf/PdfContentView.swift:23-33` (the `else` branch shows an unconditional `ProgressView()` with no failure/unavailable path)
- **What:** `pdfDocument(for:)` discards any iCloud-download error via `try?`; on failure it just returns `nil`. The primary reading flow (`ViewerRootView`/`PdfContentView`) has no `.unavailable`-style state to react to that `nil` — unlike `ContentExtractionView`/`SummaryAnalysisView`, which model an explicit `.unavailable` case with a proper `ContentUnavailableView` for the identical `pdfDocument(for:)` call (confirmed: `ContentExtractionView.swift:70-76` sets `viewState = .unavailable` on nil, rendered at 143-157).
- **Why:** A user opening a PDF whose iCloud download fails (offline, quota, conflict) sees an indefinite spinner with no explanation and no retry affordance in the app's main viewing surface, while the AI-extraction/analysis sheets handle the identical failure gracefully. The swallowed error also means a cancelled load (e.g. user backs out mid-download) isn't detected — the code proceeds to try resolving a URL anyway rather than bailing out.
- **Action:** Give `ViewerRootView`/`PdfContentView` the same loading/unavailable state machine already used in `ContentExtractionView`/`SummaryAnalysisView`; log (rather than silently swallow) the download error; check `Task.isCancelled` after the `try?` before proceeding.
- **Severity:** High
- **Verified:** yes — see §12.

### 5.4 CoreData `uuid` fallback mints a fresh random identity instead of failing loudly
- **Location:** `Modules/PdfRPG/Controller/DataController.swift:24, 30, 77`
- **What:** `mapSnapshot` and the entry mapper use `model.uuid ?? UUID()` three times (item id, fileId, and entry id) as the domain model's identity. Per this project's own CloudKit rule, Core Data attributes synced via `NSPersistentCloudKitContainer` must be optional, so `uuid` can legitimately be `nil` mid-merge.
- **Why:** Since `id` is the entire basis for item identity/diffing/CRDT matching in `ItemController`, a transient nil `uuid` causes the *same* managed object to be mapped to a *different* random domain id on separate snapshot passes — manifesting as a duplicated or silently-orphaned PDF item rather than a debuggable, loud failure.
- **Action:** Treat a nil `uuid` as a data-integrity condition to log/repair once (e.g. assign and persist a stable id back onto the managed object), not re-randomize on every map call.
- **Severity:** High
- **Verified:** yes — see §12. Note: this `?? UUID()` pattern is likely repeated in sibling modules' `DataController`s too — worth a repo-wide pass (see §10).

### 5.5 `PdfModel.isSame()` compares `entries` positionally instead of by id
- **Location:** `Modules/PdfRPG/Model/PdfModel.swift:146-162`, specifically lines 156-159
- **What:** After confirming equal counts, `entries.enumerated().allSatisfy { index, entry in entry == other.entries[index] }` assumes both arrays are in identical order rather than comparing as a keyed set.
- **Why:** Two entry-sets that are semantically identical but differently ordered (possible since only the `.folder` merge branch canonically re-sorts — see §5.2) are reported as different, triggering spurious "changed" detection and extra saves/sync churn. Currently low-likelihood since bookmarks are append-only with no reorder UI, but fragile, and would compound with §5.2 once fixed.
- **Action:** Compare `entries` as an id-keyed dictionary/set rather than positionally.
- **Severity:** Low

### 5.6 Stray force-unwrap inside a ternary
- **Location:** `Modules/PdfRPG/Route/DetailRoute.swift:18`
- **What:** `"...\(entryId == nil ? "" : "/\(entryId!.uuidString)")"` force-unwraps `entryId` inside the "not nil" branch of a ternary that just tested it.
- **Why:** Logically safe today, but project `CLAUDE.md` explicitly asks to avoid force unwraps even when provably safe — it's fragile to future edits of the ternary condition.
- **Action:** Rewrite as `entryId.map { "/\($0.uuidString)" } ?? ""`.
- **Severity:** Low

### 5.7 Unmanaged fire-and-forget Task swallows share/game-data errors
- **Location:** `Modules/PdfRPG/Controller/LinkController.swift:23-31`
- **What:** `toggleTextLink` spawns an untracked `Task { ... }` that either calls `shareResult.networkActions?.shareId(...)` or `try? await gameController.createGameData(for: itemId)`; the Task is never stored or tied to caller lifetime, and `createGameData`'s error is discarded via `try?`.
- **Why:** If `createGameData` throws (e.g. missing/undownloaded file), the share action silently does nothing — no error surfaces to the player/GM, and there's no cancellation if the underlying view disappears before the Task completes.
- **Action:** Tie the Task to the view's lifetime (e.g. `.task {}`) and surface `createGameData` failures through the existing error/toast mechanism instead of `try?`.
- **Severity:** Medium

### 5.8 `createBookmark`'s `itemId` parameter is actually used as the entry's own id
- **Location:** `Modules/PdfRPG/Controller/EditController.swift:62-70`; sole call site `Modules/PdfRPG/Pdf/PdfContentView.swift:45`
- **What:** `func createBookmark(itemId: UUID, content: String, page: String, bounds: CGRect) -> PdfEntryModel` builds `PdfEntryModel(id: itemId, ...)` — the `itemId` parameter becomes the *entry's own* `id`, not a reference to the PDF item it belongs to. The sole call site passes a fresh, unrelated `UUID()` (`root.editController.createBookmark(itemId: UUID(), ...)`), which happens to work only because of this mismatch.
- **Why:** The name strongly implies "the id of the PDF item this bookmark belongs to" — exactly how every other method on this controller uses that parameter name (e.g. `addBookmark(itemId:entry:)`). A future caller reasonably passing the real PDF item's id would silently create a bookmark whose id collides with the parent item's id, corrupting `PdfModel.subscript(id:)` lookups.
- **Action:** Rename the parameter to `id` (or `entryId`), e.g. `func createBookmark(id: UUID = UUID(), content:page:bounds:)`.
- **Severity:** Medium

### 5.9 Dead code: unused synchronous URL-based `PdfWrapperView` initializer
- **Location:** `Modules/PdfRPG/Pdf/PdfWrapperView.swift:33-38`
- **What:** `init(url:entry:horizontal:searchModel:)` performs `PDFDocument(url: url)` synchronously but is never called anywhere in the repo (verified via repo-wide grep); only `init(showing:)` (fed a pre-loaded `PDFDocument`) is used, from `PdfContentView.swift:24`.
- **Why:** Dead code adds maintenance surface, and if ever wired up by a future change it would reintroduce a synchronous main-thread PDF decode identical to §7.1.
- **Action:** Remove the unused initializer, or route it through an async decode path if a real use case exists.
- **Severity:** Low

---

## 6. Security

### 6.1 User-authored PDF name logged at public privacy level
- **Location:** `Modules/PdfRPG/Controller/LinkController.swift:70`
- **What:** `Logger.linkController.info("Pdf: \(replacedItem.name, privacy: .public) will be replaced from repairing links.")` logs the item's user-chosen name at `.public` privacy — the only such instance in the module (the module's other `privacy: .public` use, `Intent/OpenPdfIntent.swift:50`, logs a system `error.localizedDescription`, which is fine).
- **Why:** User-authored content (which could include real names/personal notes in a homebrew PDF title) ends up unredacted in device diagnostic logs/sysdiagnoses, unlike the default Apple redaction behavior.
- **Action:** Use default/`.private` privacy for the name interpolation.
- **Severity:** Low

No hardcoded secrets/tokens, no path-traversal-prone filename handling (import is fully generic via shared CoreRPG infrastructure), and no other PII/sensitive-data logging were found in this module.

---

## 7. Performance

### 7.1 PDF documents decoded synchronously on the MainActor
- **Location:** `Modules/PdfRPG/Controller/ItemController.swift:38-47` (`pdfDocument(for:)`); call sites at `Root/ViewerRootView.swift:94-105`, `View/ContentExtractionView.swift:70-76`, `View/SummaryAnalysisView.swift:62-68`
- **What:** `fileUrlDataController` is `@MainActor @Observable` (`Modules/CoreRPG/Files/FileUrlDataController.swift:11`), and `pdfDocument(for:)` calls its synchronous-closure overload of `url(for:action:)` (`FileUrlDataController.swift:215`, distinct from the `async`-closure overload at line 186), which invokes the action closure — containing `PDFDocument(url: url)` — inline, on the MainActor, with no hop to a background thread.
- **Why:** Every PDF open/analysis (viewer appearing, AI extraction, AI summary) fully parses the PDF on the main thread; for a large multi-hundred-page rulebook this is a real, user-visible hitch/freeze, not a theoretical concern.
- **Action:** Use the `async throws -> T?` closure overload (line 186) with the `PDFDocument(url:)` decode itself wrapped to actually run off the MainActor (e.g. a background-actor helper), rather than the synchronous-closure overload.
- **Severity:** High
- **Verified:** yes — see §12.

---

## 8. SwiftUI / UI

### 8.1 `InlineRowViewer`'s custom `Equatable` defeats `@Observable` staleness tracking
- **Location:** `Modules/PdfRPG/View/InlineRowViewer.swift:6-66` (computed `model` at 52-54; `Equatable` at 64-66); wired via `Modules/PdfRPG/Controller/ViewController.swift:15,19` (`.equatable()`)
- **What:** `ViewController.rowViewer(...)` wraps `InlineRowViewer` in `.equatable()`, and the view's `static func == { lhs.source == rhs.source }` compares only the `ItemRowModel` (itemId/entryId/typeId) — never `sourceModel` or the live `PdfModel`'s name/description/thumbnail.
- **Why:** `.equatable()` short-circuits *before* `body` is invoked, so if the referenced PDF is renamed, re-thumbnailed, or otherwise edited elsewhere while an inline reference to it is on-screen (e.g. a link to a PDF embedded in a Character sheet), the row keeps showing stale content indefinitely — `@Observable`'s access-tracking never gets a chance to run because `body` never re-executes.
- **Action:** Fold a content-derived value (e.g. the resolved model's `isSame`/hash) into the equality check, or drop `.equatable()` here since `PdfModel` already drives its own diffing.
- **Severity:** High
- **Verified:** yes — see §12.

### 8.2 Copy-paste accessibility text bug in `SummaryAnalysisView`
- **Location:** `Modules/PdfRPG/View/SummaryAnalysisView.swift:33-34`
- **What:** `.accessibilityLabel(Text("Cancel PDF extraction", ...))` / `.accessibilityHint(Text("Closes the extraction view without applying changes", ...))` — but this view's `navigationTitle` is "PDF Analysis" (line 21) and has nothing to do with the "extraction" flow (that's `ContentExtractionView`); these strings were clearly copy-pasted from `ContentExtractionView.swift:43-44` without updating the wording.
- **Why:** VoiceOver users navigating the Analysis sheet hear a description of the wrong feature — a real (if minor) accessibility defect, and a direct symptom of the duplicated scaffolding in §9.2.
- **Action:** Change to "Cancel PDF analysis" / "Closes the analysis view without applying changes" — or fix once, centrally, per §9.2.
- **Severity:** Low

### 8.3 Dead `@Environment(\.dismiss)` property
- **Location:** `Modules/PdfRPG/Root/ViewerRootView.swift:21`
- **What:** `ViewerRootView` declares `@Environment(\.dismiss) private var dismiss` but never reads it in `body`; the actual dismiss action is wired through `dismissAction`/`CloseButtonView`'s own separate `@Environment(\.dismiss)` (line 125).
- **Why:** Dead code that could mislead a future maintainer into thinking `ViewerRootView` itself performs dismissal.
- **Action:** Remove the unused property.
- **Severity:** Low

### 8.4 Unnamed magic numbers for PDFKit zoom/thumbnail tuning
- **Location:** `Modules/PdfRPG/Pdf/PdfWrapperView.swift:65-66` (`minScaleFactor = 0.25`, `maxScaleFactor = 5.0`); `Modules/PdfRPG/Pdf/PdfContentView.swift:87,91` (`CGSize(width: 54, height: 75)`, `CGSize(width: 71, height: 100)`); `Modules/PdfRPG/Pdf/ThumbnailPdfView.swift:29` (`UIEdgeInsets(top: 10, left: 5, bottom: 10, right: 5)`); `Modules/PdfRPG/View/InlineRowViewer.swift:25,27,31` (corner radius `24` repeated 3× in one view)
- **What:** Several PDFKit zoom bounds, thumbnail pixel sizes, and a repeated corner-radius value are inline literals rather than named constants.
- **Why:** Makes intent non-obvious and invites drift if changed in only one of the three `InlineRowViewer` spots.
- **Action:** Promote to named `static let` constants near their use — the module already does this correctly for `PdfWrapperView.pdfViewNavigationDelay`; extend that pattern here.
- **Severity:** Low

### 8.5 Xcode code-completion placeholder token left in shipped code
- **Location:** `Modules/PdfRPG/Pdf/SelectionBar.swift:73`
- **What:** `.lineLimit(/*@START_MENU_TOKEN@*/2/*@END_MENU_TOKEN@*/)` — Xcode's internal code-snippet placeholder syntax, accidentally left in after autocompletion.
- **Why:** Harmless at compile time but a visible copy-paste/hygiene artifact.
- **Action:** Simplify to `.lineLimit(2)`.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Files to delete outright
_No findings._ No `#if false` blocks, no `_OLD`/`Legacy`/`Deprecated`-named files, no fully-disabled files were found in this module. Two filenames (`FolderListController.swift`, `DetailFolderListView.swift`) matched a preliminary "legacy" substring grep but were verified as current, correct, non-legacy code (thin wrappers around shared CoreRPG generics).

### 9.2 Near-identical Loading/Unavailable/loadPDF scaffolding duplicated across two extraction views
- **Locations:** `Modules/PdfRPG/View/ContentExtractionView.swift:70-76` (`loadPDF`), `128-141` (`LoadingView`), `143-157` (`UnavailableView`), `33-45` (Cancel toolbar item) vs. `Modules/PdfRPG/View/SummaryAnalysisView.swift:62-68`, `113-126`, `128-142`, `23-35`
- **What:** `LoadingView` and `UnavailableView` are word-for-word identical private structs in both files; `loadPDF()` bodies are structurally identical; the Cancel `ToolbarItem` is near-identical.
- **Why:** Any future tweak (loading copy, retry affordance, accessibility wording) has to be made twice and can silently diverge — it already has, see §8.2.
- **Action:** Extract `PdfLoadingView`/`PdfUnavailableView` (and optionally a small `loadPdfDocument(root:itemId:) async -> PDFDocument?` helper) into a shared file, e.g. `View/PdfExtractionSharedViews.swift`, and have both views consume it.
- **Severity:** Medium

### 9.3 Duplicated `SheetModel`-construction logic in `SheetController`
- **Location:** `Modules/PdfRPG/Controller/SheetController.swift:26-39` (`sheetEntries`) vs. `41-51` (`sheetEntry`)
- **What:** `sheetEntries(root:itemId:level:moduleDepth:)` builds a `SheetModel` inline inside its `.map` closure instead of calling the already-existing, near-identical private helper `sheetEntry(itemId:entry:level:)`.
- **Why:** Two near-verbatim implementations of the same construction logic in the same file; a future field addition to `SheetModel` construction would need to be made twice and could easily drift.
- **Action:** Replace the `.map` body with a call to `sheetEntry(itemId:entry:level:)`.
- **Severity:** Medium

### 9.4 Dead commented-out import
- **Location:** `Modules/PdfRPG/Pdf/PdfSearchModel.swift:3`
- **What:** `//import CoreRPG` — a disabled import left in place; the file compiles fine without it.
- **Why:** Minor dead-code residue.
- **Action:** Delete the line.
- **Severity:** Low

### 9.5 Oversized files (only two in the module, both borderline)
- **`Modules/PdfRPG/Model/PdfModel.swift:280`** — one `@Observable` class plus 7 protocol-conformance extensions (Comparable, ItemLinkRegistable, ItemDiffComparable, ItemDuplicatable, ItemDataAccessable, Codable, Equatable/Hashable), each cohesive and matching the pattern used by sibling module models. Optional split: `PdfModel.swift` (core), `PdfModel+Merging.swift`, `PdfModel+Codable.swift`.
- **`Modules/PdfRPG/Root/PdfRootModel.swift:207`** — construction wiring (~13 controllers) plus the public `ItemRootControllable` API surface in one file; matches the RootModel pattern documented in `CLAUDE.md` and is likely consistent with every other module's RootModel size.
- **Severity:** Low (both — organization is consistent with the rest of the codebase; split is cosmetic, not corrective)

### 9.6 Inconsistent explicit `Sendable` declaration among sibling controllers
- **Location:** `Modules/PdfRPG/Controller/SheetController.swift:6-8`
- **What:** `struct SheetController` has no explicit `Sendable` conformance, while its sibling controllers in the same module (`CacheController`, `GameController`, `LinkController`, `ItemController`, `SyncDataController`) all explicitly declare `: Sendable`.
- **Why:** Relies on implicit Sendable synthesis rather than the pattern the rest of the module follows, making it easy to accidentally break Sendability later without a compiler diagnostic pointing at an explicit conformance.
- **Action:** Add `: Sendable` explicitly to `SheetController`.
- **Severity:** Low

### 9.7 `PreviewData.previewEmpty`/`previewEmptyId` fixtures reached only indirectly
- **Location:** `Modules/PdfRPG/Model/PreviewData.swift:100-134`
- **What:** Unlike sibling modules (e.g. `PhotoModel.previewEmptyId`), which are referenced by name from other views'/tests' previews to specifically exercise the "no file attached" state, PdfRPG's `previewEmpty`/`previewEmptyId` are only reached transitively via `previewFixtures` — no `#Preview` or test in this module targets the empty-PDF state by name.
- **Why:** Not dead code, but means no preview/test specifically verifies UI behavior for a PDF item with no attached file (e.g. `View/DetailEditorView.swift:30`'s "No file is set" branch has no direct preview target).
- **Action:** Optional — add a preview/test that explicitly targets `PdfModel.previewEmptyId`, mirroring PhotoRPG's pattern.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **The `model.uuid ?? UUID()` fallback pattern (§5.4) is probably repeat across every module's `DataController`, not unique to PdfRPG.** Since the project's own CloudKit rule requires optional Core Data attributes, a transient nil is an expected occurrence project-wide, not a PdfRPG-specific edge case. Worth a dedicated, repo-wide audit of every `DataController.mapSnapshot`/entry-mapper for the same silent-re-randomization pattern, with a shared fix (log + stable-repair) applied once.
2. **The `.folder`-vs-default CRDT merge split (§5.2) is a pattern worth checking in sibling modules with similar "grouped item with child entries" shapes** (Table, Character) — anywhere a model merges a child-entries array with `CRDTDataUpdate.merged()` instead of an id-keyed union is exposed to the same silent-data-loss class of bug this audit already found fixed for `.folder` but not for the default case here.
3. **`.equatable()` wrapping (§8.1) should be paired with equality that actually reflects what's rendered.** If other modules have an equivalent `InlineRowViewer`/`rowViewer` pattern, they're worth the same check — an `Equatable` conformance that only compares routing identity (source/destination ids) rather than the resolved model content will always understate what should trigger a re-render.
4. **Shared "Loading/Unavailable" scaffolding (§9.2) is a good candidate for a CoreRPG-level helper**, not just a PdfRPG-local extraction — if other modules' AI-extraction/analysis views have the same shape, a single `View/AIFeatureLoadingScaffold.swift` in CoreRPG would prevent this class of copy-paste drift (§8.2) everywhere at once.

---

## 11. What was NOT audited

- All other modules (AdventureRPG, AudioRPG, CharacterRPG, DiceRPG, MapRPG, PhotoRPG, SpaceRPG, TableRPG, WeatherRPG, RuleRPG, GameRPG, RolePlayGameKit) — referenced only where PdfRPG imports/compares against them for context (e.g. `TableEntryModel.filter(with:)` as a correct-pattern reference in §5.1/§4.1).
- CoreRPG shared infrastructure (`FileUrlDataController`, `CRDTDataUpdate`, `CoreDataController`, `GenericEditController`, etc.) — read only as needed to verify specific PdfRPG call sites (§5.2, §5.4, §7.1), not exhaustively audited in its own right. A dedicated CoreRPG audit would likely surface more of the same root causes affecting every module at once (see §10).
- Algorithmic correctness of PDFKit's own rendering/search/selection internals — treated as a black box; only PdfRPG's usage of the API surface was reviewed.
- The `Resources/Model.xcdatamodeld/RPGPdf.xcdatamodel` Core Data schema file itself — not opened directly; only inferred from `DataController`'s mapping code.
- Build settings, scheme configuration, Xcode project structure — beyond what's visible in the shared scheme used to attempt a compiler-warning capture (see note below).
- Test coverage for PdfRPG — no `Tests/` files under this module's scope were opened as part of this audit; only production code.
- Localization wording/translation quality — `Localizable.xcstrings` was spot-checked for structural issues (duplicate/stale keys, §4.3) but not reviewed for translation accuracy.
- Performance profiling via Instruments — §7.1's MainActor-decode finding is based on static code reading (confirmed actor isolation via the type/method declarations), not a captured trace.
- **Compiler warning capture did not complete for this module**: an initial `xcodebuild` attempt hit a stale-linker error unrelated to PdfRPG (a `CoreRPG` `Animation.reduced` symbol), which cleared after a scheme clean+rebuild; a subsequent attempt to isolate PdfRPG-specific warnings returned no compile tasks for the module (incremental build caching), and a full from-scratch CLI rebuild hit an unrelated destination-resolution error. Concurrency/API-modernity findings in this report are therefore based entirely on direct code reading (all 54 files read in full by the audit agents), not on compiler diagnostics — treat §3/§4 as thorough but not compiler-cross-checked.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line.

- **§5.1** — open `Modules/PdfRPG/Model/PdfEntryModel.swift`, lines 62-64: `public func filter(with search: String) -> Bool { true }`. Cross-check `Modules/PdfRPG/Model/PdfModel.swift`, lines 194-196: `entries.contains { $0.filter(with: filter) }` — the only caller. Confirmed hardcoded `true`.
- **§7.1** — open `Modules/PdfRPG/Controller/ItemController.swift`, lines 39-46: the synchronous-closure `url(for:action:) { url -> PDFDocument? in ... PDFDocument(url: url) }`. Cross-check `Modules/CoreRPG/Files/FileUrlDataController.swift` line 11 (`@MainActor @Observable`) and line 215 (the sync-closure `url<T>(for:action: (URL?) throws -> T?)` overload, not the `async`-closure one at line 186). Confirmed inline MainActor decode.
- **§5.2** — open `Modules/PdfRPG/Model/PdfModel.swift`, lines 117-144: the `if mergedCategory.wrappedValue == .folder` id-union branch (122-127) vs. the `else` branch (129) calling `entries_.merged(other: other.entries_)`. Cross-check `Modules/CoreRPG/CRDT/CRDTDataUpdate.swift`, lines 30-34: `merged(other:)` returns `newUpdate.wrappedValue == update ? _value : other._value` — whole-value LWW, confirmed no per-element merge.
- **§5.3** — open `Modules/PdfRPG/Controller/ItemController.swift` line 41 (`try? await fileUrlDataController?.download(...)`) and `Modules/PdfRPG/Pdf/PdfContentView.swift` lines 23-33 (no `.unavailable` branch, just an unconditional `ProgressView()`). Cross-check `Modules/PdfRPG/View/ContentExtractionView.swift` lines 70-76 and 143-157, which do have the `.unavailable` case + `UnavailableView`. Confirmed the asymmetry.
- **§5.4** — open `Modules/PdfRPG/Controller/DataController.swift`, lines 24, 30, and 77: `model.uuid ?? UUID()` appears three times mapping CoreData → domain model.
- **§8.1** — open `Modules/PdfRPG/View/InlineRowViewer.swift`, lines 64-66: `static func == (lhs: Self, rhs: Self) -> Bool { lhs.source == rhs.source }`. Cross-check `Modules/PdfRPG/Controller/ViewController.swift` lines 15 and 19: both `rowViewer(...)` overloads wrap the view in `.equatable()`. Confirmed `sourceModel`/live model content is excluded from the comparison.

If any finding doesn't reproduce when you visit the line, flag the specific reference for re-investigation.
