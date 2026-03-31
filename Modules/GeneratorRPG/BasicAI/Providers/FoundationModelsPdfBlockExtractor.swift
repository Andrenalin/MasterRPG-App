// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels

#if canImport(PDFKit)
import PDFKit
#endif

/// Foundation Models-based PDF block extractor for table/adventure content
@MainActor
public final class FoundationModelsPdfBlockExtractor: PdfBlockExtracting, @unchecked Sendable {

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
        maxCharacters: Int = 12000,
        instructions: String? = nil
    ) {
        self.maxPages = maxPages
        self.maxCharacters = maxCharacters
        self.instructions = instructions ?? Self.defaultInstructions
    }

    // MARK: - Public Methods

//    public func extract(from pdfDocument: PDFDocument) async throws -> [BlockGenModel] {
//        // Check model availability
//        guard SystemLanguageModel.default.availability == .available else {
//            throw PdfExtractionError.modelUnavailable
//        }
//
//        // Validate document
//        guard pdfDocument.pageCount > 0 else {
//            throw PdfExtractionError.emptyDocument
//        }
//
//        // Extract text from PDF
//        let extractedText = try extractText(from: pdfDocument)
//
//        guard !extractedText.isEmpty else {
//            throw PdfExtractionError.textExtractionFailed
//        }
//
//        // Create session
//        let session = LanguageModelSession(instructions: instructions)
//
//        // Prewarm for faster generation
//        session.prewarm()
//
//        // Generate structured blocks
//        do {
//            let response = try await session.respond(
//                to: buildPrompt(with: extractedText, pageCount: pdfDocument.pageCount),
//                generating: [BlockGenModel].self
//            )
//
//            return response.content
//        } catch let error as LanguageModelSession.GenerationError {
//            throw PdfExtractionError.generationFailed(handleGenerationError(error))
//        } catch {
//            throw PdfExtractionError.generationFailed(error.localizedDescription)
//        }
//    }

    public func extractWithProgress(
        from pdfDocument: PDFDocument,
        onPartialBlocks: @MainActor @Sendable ([BlockGenModel]) -> Void
    ) async throws -> [BlockGenModel] {
        // Check model availability
        guard SystemLanguageModel.default.availability == .available else {
            throw PdfSummaryAnalysisError.modelUnavailable
        }

        // Validate document
        guard pdfDocument.pageCount > 0 else {
            throw PdfSummaryAnalysisError.emptyDocument
        }

        // Extract text from PDF
        let extractedText = try extractText(from: pdfDocument)

        guard !extractedText.isEmpty else {
            throw PdfSummaryAnalysisError.textExtractionFailed
        }

        // Create session

        // Generate without streaming for array types
        // Note: Foundation Models streaming for arrays doesn't provide complete objects incrementally
        do {
            var blocks: [BlockGenModel] = []
            for (index, text) in extractedText.enumerated() {
                let session = LanguageModelSession(instructions: instructions)

                // Prewarm for faster generation
                session.prewarm()

                let response = try await session.respond(
                    to: buildPrompt(with: text, pageNumber: index + 1, pageCount: pdfDocument.pageCount),
                    generating: [BlockGenModel].self,
                    includeSchemaInPrompt: false
                )
                
                // Call onPartialBlocks once with the final result
                onPartialBlocks(response.content)
                
                blocks.append(contentsOf: response.content)
            }
            return blocks
        } catch let error as LanguageModelSession.GenerationError {
            throw PdfSummaryAnalysisError.generationFailed(handleGenerationError(error))
        } catch {
            throw PdfSummaryAnalysisError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Methods

    private func extractText(from pdfDocument: PDFDocument) throws -> [String] {
        var result: [String] = []
        var fullText = ""

        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex),
                  let pageText = page.string else {
                continue
            }

            // Add page marker for better section detection
            fullText += "--- Page \(pageIndex + 1) ---\n"
            fullText += pageText + "\n\n"
            result.append(fullText)
            fullText = ""
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
    Your task is to extract the contents. Do not summarize or change the text, except spelling or broken text.
    """
}

#endif
