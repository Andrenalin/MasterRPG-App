# GeneratorRPG audit (2026-11-14)

Files read: BasicAI/Providers (Photo/Pdf/PdfContent/Table analyzers, fallback policy, page reader), BasicAI/Engine (ConversationEngine, limiter, token counting, context builder), BasicAI/Model + Errors + Configuration, Controller/GeneratorController + ConversationSessionModel, the Pdf/Table/Photo/Batch/Text extraction views, Intent/RunGeneratorIntent and management intents, SheetAIAssistant views, GeneratorRootModel/GeneratorModel/DataController, plus the PdfRPG/PhotoRPG call sites. Not every Route/Menu/Preview file was read line by line. About 7.0k LOC in the module. Health is good: earlier audits are visibly worked in, the PCC gate is sound, and the intent path fences untrusted text. The open items are mostly error mapping in the analyzers, unreviewed batch writes of model output, and duplicated plumbing.

### Photo analysis reports "Apple Intelligence is not available" for every fallback-class on-device error while PCC is disabled
- Category: Bug
- Location: Modules/GeneratorRPG/BasicAI/Providers/PhotoSummaryAnalyzer.swift:70-83
- What: when the on-device call throws an error the fallback policy maps to a reason (context too large, guardrail, rate limit, unsupported language), the code reaches `guard Self.isPrivateCloudComputeEnabled else { throw .modelUnavailable }`, discarding the reason and the original error.
- Why: `PRIVATE_CLOUD_COMPUTE_ENTITLED` is defined nowhere (grep of pbxproj/xcconfig/Package: no match), so this is the shipped configuration. A guardrail trip or rate limit on a perfectly available device shows "Apple Intelligence is not available. Photo analysis requires it." and the user is sent to Settings for nothing.
- Action: when PCC is off, rethrow the mapped on-device error (generationFailed with the error text, or a dedicated case carrying the `PhotoAnalysisFallbackReason.explanation`), keep `modelUnavailable` only for `.onDeviceUnavailable`/`.visionUnsupported`. Add a test with an injected failing on-device closure.
- Severity: Medium
- Status: NEW

### PCC entitlement gate is compile-time per module, not per host app
- Category: Security
- Location: Modules/GeneratorRPG/BasicAI/Providers/PhotoSummaryAnalyzer.swift:37-43, 117-124; Tests/GeneratorRPGTests/PhotoTagging/PhotoTagEvaluationTests.swift:47
- What: verified the gate holds today (flag undefined, `PrivateCloudComputeLanguageModel()` is only constructed behind `isPrivateCloudComputeEnabled`, the test short-circuits before constructing it). The residual risk is the design: one GeneratorRPG compilation flag covers MasterRPG, MasterMac and visionOS hosts whose entitlement files are separate (and split Debug/Release).
- Why: the day the flag is turned on for the module while one host/config lacks `com.apple.developer.private-cloud-compute`, constructing the model is a fatal error, not a throw, and only that host crashes, on the first photo that needs the fallback.
- Action: when enabling, add a runtime check of the entitlement (SecTaskCopyValueForEntitlement on macOS, embedded-profile check elsewhere) or inject the flag from the host, and add a build-time check that every host with the flag has the entitlement in both Debug and Release files.
- Severity: Low
- Status: NEW

### Model output is applied to many items without review in the batch flow, from unfenced untrusted text
- Category: Security
- Location: Modules/GeneratorRPG/View/BatchTextSummaryExtractionView.swift:232-251; BasicAI/Providers/TableSummaryAnalyzer.swift:60-72; View/TextSummaryExtractionFormatter.swift:14-28; BasicAI/Providers/PdfSummaryAnalyzer.swift:117-133; BasicAI/Engine/FoundationModelInputLimiter.swift:58
- What: entry names/contents (which can come from Foundry imports or shared campaigns), and PDF page text, are interpolated into the prompt with no fence and no marker stripping; the batch view then writes the model's title/description/tags straight into the items. The PDF page separator `--- Page N ---` is also forgeable by page text.
- Why: an imported entry saying "ignore the above, title this ...; tags: ..." can steer the title, description and tags of every selected item with no preview. The single-item views show a toggle form before applying, so only the batch path is unreviewed. `RunGeneratorIntent` already fences and strips markers (`GeneratorIntentPrompt`), so the module has two different standards.
- Action: move the untrusted text into a delimited block with marker stripping shared from `GeneratorIntentPrompt.withoutMarkers`, state in the instructions that it is material only, and either show a review step for the batch or limit the batch to name-if-empty plus tags with a count shown afterwards.
- Severity: Medium
- Status: NEW

### Batch apply appends the description on every run and replaces tags, as three separate edits
- Category: Bug
- Location: Modules/GeneratorRPG/View/BatchTextSummaryExtractionView.swift:240-251
- What: `applyResult` appends `result.description` to the existing description each time, replaces all existing tags, and issues three separate `editController.reset` calls.
- Why: running the batch twice on the same item duplicates the generated paragraph; curated tags are lost without a prompt; three resets mean three saves/undo steps and a window where a CloudKit sync can upload a half-applied item. Items with empty text are marked `.completed` without being analysed (line 218-221), which hides that nothing was done.
- Action: skip the append when the description already ends with the generated text (or replace a marked generated block), merge tags instead of replacing, apply in one edit, and show a distinct "skipped" status.
- Severity: Medium
- Status: NEW

### CancellationError and already-wrapped errors are re-wrapped as generationFailed in the PDF and table analyzers
- Category: Bug
- Location: Modules/GeneratorRPG/BasicAI/Providers/PdfSummaryAnalyzer.swift:76-87, 107-111; BasicAI/Providers/TableSummaryAnalyzer.swift:48-58
- What: in `PdfSummaryAnalyzer` the `throw .generationFailed(...)` at line 81 sits inside the `do`, so the generic `catch` at 109 wraps it again ("Failed to generate summary analysis: Failed to generate summary analysis: ..."); both analyzers also turn `CancellationError` into `generationFailed`, unlike `PhotoSummaryAnalyzer.mapped`.
- Why: cancelling a batch item shows a red "Failed ..." status instead of stopping quietly; the incomplete-stream message is doubled.
- Action: add `catch is CancellationError { throw }` first and `catch let error as PdfSummaryAnalysisError { throw error }`, as the photo analyzer does.
- Severity: Low
- Status: NEW

### Context-overflow recovery resets the shared session even when the caller was cancelled
- Category: Concurrency
- Location: Modules/GeneratorRPG/BasicAI/Engine/ConversationEngine.swift:283-296, 367-376
- What: any error in `generateConversationSummary` (including `CancellationError` from a superseded request) runs `createFreshSessionAfterOverflow()` before rethrowing.
- Why: the engine is shared by successive requests; a cancelled predecessor can replace `session` and bump `sessionCount` while the newer request is already streaming on the old session, so its transcript is dropped and the token meter resets.
- Action: rethrow `CancellationError` before touching the session, and only reset when the call is still the active one (reuse the streaming task id).
- Severity: Low
- Status: NEW

### Sliding window can start the kept transcript with an orphan response
- Category: Bug
- Location: Modules/GeneratorRPG/BasicAI/Engine/TranscriptTokenCounting.swift:155-181, 194-207
- What: both window builders keep a suffix of the conversation entries by count/budget without aligning to a prompt boundary.
- Why: the new `LanguageModelSession(transcript:)` may begin with a `.response` that has no prompt, which the framework may reject or which confuses the model. Unverified at runtime.
- Action: after choosing the suffix, drop leading non-prompt entries; add a unit test on a synthetic transcript.
- Severity: Low
- Status: NEW (unverified)

### Analyze buttons guard on a flag that is set inside the task they start
- Category: Bug
- Location: Modules/GeneratorRPG/View/PhotoSummaryAnalysisView.swift:129-139; View/PdfSummaryAnalysisView.swift:44-50; View/PdfContentExtractionView.swift:44-50; View/TableSummaryAnalysisView.swift:61-67
- What: `guard !model.isAnalyzing` is checked, then `analysisTask = Task { ... model.analyze... }` sets `isAnalyzing` only when the task body starts.
- Why: a Return key press plus a click in the same run-loop turn (the buttons have `.keyboardShortcut(.defaultAction)`) starts two analyses; the first task handle is overwritten so `onDisappear` cannot cancel it, and `onAnalysisCompleted` fires twice.
- Action: set `isAnalyzing` synchronously in the button action, or cancel the previous `analysisTask` before starting a new one.
- Severity: Low
- Status: NEW

### Same per-error switch copied into four places
- Category: Duplication
- Location: Modules/GeneratorRPG/BasicAI/Providers/PdfSummaryAnalyzer.swift:135-188; PdfContentExtractor.swift:174-224; TableSummaryAnalyzer.swift:81-122; BasicAI/Errors/FoundationModelsError.swift:8-30
- What: four `GenerationError` to message mappers with near-identical cases and drifting wording (PDF-specific text in two, generic in two); the photo analyzer has a fifth path (`mapped`).
- Why: a new `GenerationError` case or a localisation fix has to be made four times; the PDF text is wrong when the same mapper is reused for tables.
- Action: one mapper taking a subject noun, in `FoundationModelsErrorHandler`.
- Severity: Medium
- Status: NEW

### Language instructions contradict the language override
- Category: Bug
- Location: Modules/GeneratorRPG/BasicAI/Providers/PdfSummaryAnalyzer.swift:201 vs 58; TableSummaryAnalyzer.swift:129 vs 41; PdfContentExtractor.swift:225
- What: default instructions say "use document language. Don't change it" / "use the same language as the entries", then the code appends "All output must be written in <outputLanguage>".
- Why: the on-device model gets two conflicting rules; choosing another output language in the picker can be ignored (small model, last-rule bias is not guaranteed).
- Action: drop the language sentence from the default instructions of the two analyzers that take an output language.
- Severity: Low
- Status: NEW

### PDF page text is read in full before the character cap
- Category: Performance
- Location: Modules/GeneratorRPG/BasicAI/Providers/PdfPageTextReader.swift:26-38; BasicAI/Engine/FoundationModelInputLimiter.swift:50-62
- What: `page.string` of up to 40 pages is materialised completely, then cut to 7000 characters.
- Why: a crafted or text-heavy PDF (MBs per page) is allocated and counted (`String.count` is O(n)) before being thrown away.
- Action: stop reading once the budget is reached and cap each page string at `maxCharacters` right after reading.
- Severity: Low
- Status: NEW

### BlockEntryGenModel equality includes a random id
- Category: Bug
- Location: Modules/GeneratorRPG/BasicAI/Model/BlockGenModel.swift:9-16
- What: `Equatable, Identifiable` struct with `let id = UUID()`; synthesized `==` compares `id`, so two blocks with identical text are never equal, and `stableId` (title-content) used as ForEach id can collide.
- Why: `onChange(of:)`/diffing never settles for regenerated identical blocks; duplicate ForEach ids in `ExtractingView` for repeated headings.
- Action: exclude id from `==` or derive id from content plus occurrence index.
- Severity: Low
- Status: NEW

### GeneratorTaskWait ignores cancellation of the waiter
- Category: Concurrency
- Location: Modules/GeneratorRPG/Controller/GeneratorController.swift:455-473
- What: `end(of:timeout:)` awaits an uncancellable gate and starts two unstructured Tasks (timer and waiter) that are not tied to the caller.
- Why: if the new request is cancelled while waiting for its predecessor, it still waits up to 5 s; the helper Task keeps `task.value` alive until the predecessor ends.
- Action: wrap `gate.wait()` in `withTaskCancellationHandler` that opens the gate.
- Severity: Low
- Status: NEW

### View-layer rule violations (CLAUDE.md)
- Category: SwiftUI
- Location: View/PdfSummaryAnalysisView.swift:52-70 (`errorView` helper); View/PdfContentExtractionView.swift:52-70; View/TableSummaryAnalysisView.swift:41-57; View/BatchTextSummaryExtractionView.swift:139-224 (helper functions returning views); `.scaleEffect(1.5)`/`0.8` spinners; hard-coded stack spacing (spacing: 16/20/8/12) in the same files; View/PhotoSummaryAnalysisView.swift:26 `Image(decorative:)` for the photo being analysed
- What: views split via helper methods instead of View structs, the same error banner copied four times (`PhotoSummaryAnalysisView` has a private `ErrorBanner` struct that the others could use), hard-coded spacing, and the analysed photo hidden from VoiceOver.
- Why: breaks the project rules and duplicates code; the analysed photo has no accessibility label.
- Action: one shared `AnalysisErrorBanner` struct, convert helpers to structs, drop hard-coded spacing, give the photo an accessibility label (item name).
- Severity: Low
- Status: NEW

### Sheet screens build a GeneratorController (engine plus model session) inside `body`, before checking availability, and FIFO eviction can tear down a visible one
- Category: Performance
- Location: Modules/GeneratorRPG/View/SheetAIAssistantContext.swift:40-46; Root/GeneratorRootModel.swift:122-134
- What: `SheetAIAssistantPlacement.body` calls `generatorRoot?.generatorController(forItem:)` for every sheet screen, creating a `ConversationEngine`, `SystemLanguageModel`, `LanguageModelSession` and `FoundationManager` per item visited, and only then tests `availability`. The cache evicts first-in, first-out at 12 entries and calls `tearDown()` on the evicted one.
- Why: on a device without Apple Intelligence every visited sheet still allocates a session; on macOS/visionOS with several windows, the 13th distinct item evicts the oldest-created controller even if its window is still on screen and mid-generation, cancelling it silently.
- Action: check `SystemLanguageModel.default.availability` (cached once) before creating the controller, create it lazily when AI mode is first activated, and evict least-recently-used skipping controllers with `isLoading`/`isExtracting`.
- Severity: Medium
- Status: NEW

### Dead code in the Generator module
- Category: Dead code
- Location: Modules/GeneratorRPG/BasicAI/Model/ChatMessage.swift:8 (no other reference in the repo); Model/CharacterGenModel.swift:8-64 (`CharacterGenModel`/`CharacterEntryGenModel`, referenced only by their own file); Controller/ConversationSessionModel.swift:7-37 (`samplingStrategy`, `useFixedSeed`, `topKSamplingValue`, `usePermissiveGuardrails` are never set outside the struct, so options are always default and guardrails always `.default`; with them `SamplingStrategyConfiguration`, `GenerationOptionsConfiguration.randomProbabilityThreshold/temperature`); BasicAI/Engine/FoundationManager.swift:12,46-48 (`isLanguageSupported`, `checkLanguageSupport` unused); BasicAI/Errors/PdfSummaryAnalysisError.swift:10 (`contentTooLarge` never thrown); BasicAI/Engine/ConversationEngine.swift:74-82 (`prewarm(withPromptPrefix:)`, no caller); BasicAI/Engine/FoundationModelInputLimiter.swift:68-87 (`limitedPageTexts`, used by one test only); BasicAI/Engine/TranscriptTokenCounting.swift (`foundationLabEstimatedTokenCount` public API on `Transcript.Entry`/`Segment` used only internally)
- What: about 250 lines of unreferenced types and settings verified by repo-wide grep over Modules, Sources and Tests.
- Why: `CharacterGenModel` is a `@Generable` schema that reads like a feature (character generation) that does not exist; the sampling/guardrail settings suggest user options that are not wired to any UI.
- Action: delete, or wire the settings to a UI on purpose; mark `public` helpers `internal`.
- Severity: Low
- Status: NEW

### Untested risky logic: window trimming, overflow recovery, batch apply, prompt assembly
- Category: Test gap
- Location: Tests/GeneratorRPGTests (only `GeneratorRPGTests.swift` covers the limiter; `GeneratorIntentPromptTests` covers the intent prompt)
- What: no tests for `foundationLabEntriesWithinTokenBudget`/binary search, `ConversationEngine.recoverFromContextOverflow`, `GeneratorController.prompt/compactSheetIndex`, `BatchTextSummaryExtractionView.applyResult`, `GeneratorTaskWait`/`OneShotGate`, `PdfSummaryAnalyzer` error mapping.
- Why: these hold the open findings above (orphan response, session reset on cancel, duplicate append, double wrapping); pure parts can be tested without a model.
- Action: extract `applyResult` and the window selection into pure functions and unit-test them; test `OneShotGate` for open-before-wait and double open.
- Severity: Low
- Status: NEW

### In-app generator prompt does not fence the sheet index the way the intent does
- Category: Security
- Location: Modules/GeneratorRPG/Controller/GeneratorController.swift:431-446, 393-414; View/SheetAIAssistantOverlayView.swift:151-159
- What: entry names (possibly imported) go into the prompt as plain "Existing sheet entries" text, and "Refine and expand" pastes a whole entry's content into the request; there are no markers and no marker stripping.
- Why: output only lands in a preview the user accepts, and the instructions are not widened (CODE_AUDIT §6.3 handled the trust channel), so impact is low; the intent path's `<generator>` fence is the better standard.
- Action: reuse the fence and `withoutMarkers` from `GeneratorIntentPrompt`.
- Severity: Low
- Status: NEW

### Prompt text for refine request is built with `String("...")` and is not localisable or bounded
- Category: Refactor
- Location: Modules/GeneratorRPG/View/SheetAIAssistantOverlayView.swift:151-157
- What: `String("Refine and expand the story around '\(name)'...")` wraps an interpolated literal in a pointless `String(...)`; content is only bounded later by `prompt(for:)`'s 2800-character cap.
- Why: cosmetic; the early trim would also keep the progress/telemetry `count` honest.
- Action: drop the wrapper, trim the entry content before interpolation.
- Severity: Low
- Status: NEW

Prompt-injection and PCC summary for the brief: (1) PCC is off in every shipped configuration and no code path constructs `PrivateCloudComputeLanguageModel` without the flag (verified, including tests); (2) imported PDF text, table entries and Foundry-derived entry names reach the model unfenced in the PDF, table, batch and in-app chat paths, but only the batch path writes the output without a review step, and the model has no tools, so the realistic impact is wrong titles/tags/descriptions, not data exfiltration; (3) the photo path sends an image only, with fixed instructions, so no text injection route other than text rendered inside the picture (OCR-style injection, same low impact); (4) the cloud-consent choice is global and sticky (`UserDefaults` key `photoAnalysisCloudConsent`), not per photo, which matters once PCC is enabled because GM-only handouts are sent with the same consent (design decision to confirm then).

Not audited in this area: Route/, Menu/, Preview/MockData/PreviewData, Root list/detail views (DetailListView, SaveView, GeneratorRootView), Controller stubs (EditController, LinkController, ViewController, SheetController), GeneratorEntity/query indexing, Localization strings, and runtime behaviour of FoundationModels (nothing was run).
