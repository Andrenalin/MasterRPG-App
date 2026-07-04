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
            for page in extractedText {
                // Report progress for current page
                await MainActor.run {
                    resultModel.pageProgress = PdfAnalysisProgress(currentPage: page.pageNumber, totalPages: pageLimit)
                }

                let session = LanguageModelSession(instructions: instructions)

                // Prewarm for faster generation
                session.prewarm()

                let response = try await session.respond(
                    to: buildPrompt(with: page.text, pageNumber: page.pageNumber, pageCount: pdfDocument.pageCount),
                    generating: [BlockEntryGenModel].self,
                    includeSchemaInPrompt: false
                )

                // Update extraction progress with accumulated blocks
                blocks.append(contentsOf: response.content)
                await MainActor.run {
                    resultModel.extractionProgress = blocks
                }
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
            return "PDF content is too large for processing. Try a smaller document or fewer pages."
        case .guardrailViolation:
            return "Content policy prevented extraction. The PDF may contain inappropriate content."
        case .unsupportedLanguageOrLocale:
            return "The PDF language is not supported by Apple Intelligence."
        case .assetsUnavailable(let reason):
            return "Model assets are unavailable: \(reason). Please ensure Apple Intelligence is fully downloaded."
        case .unsupportedGuide(let guide):
            return "PDF extraction schema contains unsupported constraint: \(guide). This is a developer error."
        case .decodingFailure(let reason):
            return "Failed to decode PDF content: \(reason). The document may have unusual formatting."
        case .rateLimited(let retryAfter):
            return "Rate limit exceeded. Please try again in \(retryAfter) seconds."
        case .concurrentRequests(let maxCount):
            return "Too many concurrent extraction requests. Maximum allowed: \(maxCount). Please wait for current extractions to complete."
        case .refusal(let reason, let category):
            return "Extraction refused: \(reason) (category: \(category)). The PDF content may violate content policies."
        @unknown default:
            return "An unexpected generation error occurred: \(error.localizedDescription)"
        }
    }

    // MARK: - Constants

    private static let defaultInstructions = """
    Your task is to extract the content. Do not summarize or change the text, except spelling, or if the text is missplaced. Don't change the content language!
    """
}

#endif
