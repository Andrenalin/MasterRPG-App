// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels
import PDFKit

/// Foundation Models-based PDF block extractor for table/adventure content
struct PdfContentExtractor: Sendable {

    // MARK: - Configuration

    /// Maximum number of pages to process
    private let maxPages: Int

    /// Maximum characters to extract (targeting ~3000 tokens for input)
    private let maxCharacters: Int

    /// Instructions for the model
    private let instructions: String

    // MARK: - Initialization

    public init(
        maxPages: Int = 20,
        maxCharacters: Int = 7000,
        instructions: String? = nil
    ) {
        self.maxPages = maxPages
        self.maxCharacters = maxCharacters
        self.instructions = instructions ?? Self.defaultInstructions
    }

    public func extractWithProgress(
        from pdfDocument: PDFDocument,
        resultModel: PdfContentExtractionResultModel
    ) async throws -> [BlockEntryGenModel] {
        // Check model availability
        guard SystemLanguageModel.default.availability == .available else {
            throw PdfSummaryAnalysisError.modelUnavailable
        }

        // Validate document
        guard pdfDocument.pageCount > 0 else {
            throw PdfSummaryAnalysisError.emptyDocument
        }

        let pageLimit = min(maxPages, pdfDocument.pageCount)

        // Extract text from PDF
        let extractedText = try extractText(from: pdfDocument, pageLimit: pageLimit)

        guard !extractedText.isEmpty else {
            throw PdfSummaryAnalysisError.textExtractionFailed
        }

        // Generate without streaming for array types
        // Note: Foundation Models streaming for arrays doesn't provide complete objects incrementally
        do {
            var blocks: [BlockEntryGenModel] = []

            // Each page deliberately gets its own fresh session rather than
            // reusing one across the whole PDF: Apple's on-device model has a
            // 4096-token context window *per session* (TN3193, "Managing the
            // on-device foundation model's context window"), and that
            // window is shared by every prior prompt/response in a session's
            // transcript. Reusing one session across up to `maxPages` pages
            // (each up to `maxCharacters` ≈ 1750+ tokens of input, plus the
            // generated schema/output) would very quickly exceed that
            // budget and start throwing `.exceededContextWindowSize` on
            // pages that succeed today — TN3193's own guidance for a task
            // like this is exactly the opposite: split it across multiple
            // sessions. What *was* genuinely wasteful is `prewarm()`
            // ("preload... within a few seconds" of an expected need) being
            // called immediately before the very `respond(to:)` it's meant
            // to prepare for, with nothing to overlap. Instead, the *next*
            // page's session is created and prewarmed while the *current*
            // page's response is still generating, so its warm-up is hidden
            // behind real work instead of adding pure serial latency to
            // every page. See CODE_AUDIT_10 §7.2.
            var upcomingSession = LanguageModelSession(instructions: instructions)
            upcomingSession.prewarm()

            for page in extractedText {
                // Report progress for current page. `setPageProgress` is itself `@MainActor`
                // — `await` alone hops there, no `MainActor.run` wrapper needed (a cross-actor
                // property *write*, unlike a read, can't compose as `await obj.property = value`).
                await resultModel.setPageProgress(PdfAnalysisProgress(currentPage: page.pageNumber, totalPages: pageLimit))

                let session = upcomingSession
                upcomingSession = LanguageModelSession(instructions: instructions)
                upcomingSession.prewarm()

                let response = try await session.respond(
                    to: buildPrompt(with: page.text, pageNumber: page.pageNumber, pageCount: pdfDocument.pageCount),
                    generating: [BlockEntryGenModel].self,
                    includeSchemaInPrompt: false
                )

                // Update extraction progress with accumulated blocks
                blocks.append(contentsOf: response.content)
                await resultModel.setExtractionProgress(blocks)
            }
            return blocks
        } catch let error as LanguageModelSession.GenerationError {
            throw PdfSummaryAnalysisError.generationFailed(handleGenerationError(error))
        } catch {
            throw PdfSummaryAnalysisError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Methods

    private func extractText(from pdfDocument: PDFDocument, pageLimit: Int) throws -> [FoundationModelInputLimiter.PageText] {
        var result: [FoundationModelInputLimiter.PageText] = []
        result.reserveCapacity(pageLimit)

        for pageIndex in 0..<pageLimit {
            guard let page = pdfDocument.page(at: pageIndex),
                  let pageText = page.string,
                  !pageText.isEmpty else {
                continue
            }

            let limited = FoundationModelInputLimiter.limitedText(pageText, maxCharacters: maxCharacters)
            result.append(
                FoundationModelInputLimiter.PageText(
                    pageNumber: pageIndex + 1,
                    text: limited,
                    wasTruncated: limited != pageText
                )
            )
        }

        return result
    }

    private func buildPrompt(with text: String, pageNumber: Int, pageCount: Int) -> String {
        """
        Extract structured content blocks from this PDF document.
        This is page \(pageNumber) from \(pageCount)
        
        \(text)
        """
    }

    private func handleGenerationError(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize:
            return String(
                localized: "PDF content is too large for processing. Try a smaller document or fewer pages.",
                bundle: .module
            )
        case .guardrailViolation:
            return String(
                localized: "Content policy prevented extraction. The PDF may contain inappropriate content.",
                bundle: .module
            )
        case .unsupportedLanguageOrLocale:
            return String(
                localized: "The PDF language is not supported by Apple Intelligence.",
                bundle: .module
            )
        case .assetsUnavailable(let reason):
            return String(
                localized: "Model assets are unavailable: \(String(describing: reason)). Please ensure Apple Intelligence is fully downloaded.",
                bundle: .module
            )
        case .unsupportedGuide(let guide):
            return String(
                localized: "PDF extraction schema contains unsupported constraint: \(String(describing: guide)). This is a developer error.",
                bundle: .module
            )
        case .decodingFailure(let reason):
            return String(
                localized: "Failed to decode PDF content: \(String(describing: reason)). The document may have unusual formatting.",
                bundle: .module
            )
        case .rateLimited(let retryAfter):
            return String(
                localized: "Rate limit exceeded. Please try again in \(String(describing: retryAfter)) seconds.",
                bundle: .module
            )
        case .concurrentRequests(let maxCount):
            return String(
                localized: "Too many concurrent extraction requests. Maximum allowed: \(String(describing: maxCount)). Please wait for current extractions to complete.",
                bundle: .module
            )
        case .refusal(let reason, let category):
            return String(
                localized: "Extraction refused: \(String(describing: reason)) (category: \(String(describing: category))). The PDF content may violate content policies.",
                bundle: .module
            )
        @unknown default:
            return String(
                localized: "An unexpected generation error occurred: \(error.localizedDescription)",
                bundle: .module
            )
        }
    }

    // MARK: - Constants

    private static let defaultInstructions = """
    Your task is to extract the content. Do not summarize or change the text, except spelling, or if the text is missplaced. Don't change the content language!
    """
}

#endif
