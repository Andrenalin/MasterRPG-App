// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels

#if canImport(PDFKit)
import PDFKit
#endif

/// Foundation Models-based PDF content extractor for RPG documents
@MainActor
public final class FoundationModelsPdfContentExtractor: PdfContentExtracting, @unchecked Sendable {

    // MARK: - Configuration

    /// Maximum number of pages to process (to stay under 4096 token limit)
    private let maxPages: Int

    /// Maximum characters to extract (rough estimate: 3 chars per token, targeting ~3000 tokens for input)
    private let maxCharacters: Int

    /// Instructions for the model
    private let instructions: String

    // MARK: - Initialization

    public init(
        maxPages: Int = 15,
        maxCharacters: Int = 9000,
        instructions: String? = nil
    ) {
        self.maxPages = maxPages
        self.maxCharacters = maxCharacters
        self.instructions = instructions ?? Self.defaultInstructions
    }

    // MARK: - Public Methods

    public func extract(from pdfDocument: PDFDocument) async throws -> PdfExtractedContent {
        // Check model availability
        guard SystemLanguageModel.default.availability == .available else {
            throw PdfExtractionError.modelUnavailable
        }

        // Validate document
        guard pdfDocument.pageCount > 0 else {
            throw PdfExtractionError.emptyDocument
        }

        // Extract text from PDF
        let extractedText = try extractText(from: pdfDocument)

        guard !extractedText.isEmpty else {
            throw PdfExtractionError.textExtractionFailed
        }

        // Create session
        let session = LanguageModelSession(instructions: instructions)

        // Prewarm for faster generation
        session.prewarm()

        // Generate structured content
        do {
            let response = try await session.respond(
                to: buildPrompt(with: extractedText, pageCount: pdfDocument.pageCount),
                generating: PdfExtractedContent.self
            )

            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            throw PdfExtractionError.generationFailed(handleGenerationError(error))
        } catch {
            throw PdfExtractionError.generationFailed(error.localizedDescription)
        }
    }

    public func extractWithProgress(
        from pdfDocument: PDFDocument,
        onPartialContent: @MainActor @Sendable (PdfExtractedContent.PartiallyGenerated) -> Void
    ) async throws -> PdfExtractedContent {
        // Check model availability
        guard SystemLanguageModel.default.availability == .available else {
            throw PdfExtractionError.modelUnavailable
        }

        // Validate document
        guard pdfDocument.pageCount > 0 else {
            throw PdfExtractionError.emptyDocument
        }

        // Extract text from PDF
        let extractedText = try extractText(from: pdfDocument)

        guard !extractedText.isEmpty else {
            throw PdfExtractionError.textExtractionFailed
        }

        // Create session
        let session = LanguageModelSession(instructions: instructions)

        // Prewarm for faster generation
        session.prewarm()

        // Stream generation with progress updates
        do {
            let stream = session.streamResponse(
                to: buildPrompt(with: extractedText, pageCount: pdfDocument.pageCount),
                generating: PdfExtractedContent.self
            )

            var latestContent: PdfExtractedContent.PartiallyGenerated?

            for try await snapshot in stream {
                // Pass the partial content for progress updates
                latestContent = snapshot.content
                onPartialContent(snapshot.content)
            }

            guard let partial = latestContent,
                  let title = partial.title,
                  let summary = partial.summary,
                  let tags = partial.tags,
                  let partialSections = partial.sections else {
                throw PdfExtractionError.generationFailed("Streaming completed but no complete content received")
            }

            // Convert PartiallyGenerated sections to actual PdfSection instances
            let sections: [PdfSection] = partialSections.compactMap { partialSection in
                guard let heading = partialSection.heading,
                      let sectionSummary = partialSection.summary else {
                    return nil
                }
                return PdfSection(
                    heading: heading,
                    summary: sectionSummary,
                    pageNumber: partialSection.pageNumber ?? nil
                )
            }

            return PdfExtractedContent(
                title: title,
                summary: summary,
                tags: tags,
                sections: sections
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw PdfExtractionError.generationFailed(handleGenerationError(error))
        } catch {
            throw PdfExtractionError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Methods

    private func extractText(from pdfDocument: PDFDocument) throws -> String {
        let pageLimit = min(maxPages, pdfDocument.pageCount)
        var fullText = ""

        for pageIndex in 0..<pageLimit {
            guard let page = pdfDocument.page(at: pageIndex),
                  let pageText = page.string else {
                continue
            }

            // Add page marker for better section detection
            fullText += "--- Page \(pageIndex + 1) ---\n"
            fullText += pageText + "\n\n"
        }

        // Truncate if too long
        if fullText.count > maxCharacters {
            fullText = String(fullText.prefix(maxCharacters))
            // Add indication of truncation
            fullText += "\n\n[Content truncated due to length...]"
        }

        return fullText
    }

    private func buildPrompt(with text: String, pageCount: Int) -> String {
        """
        Extract structured information from this RPG PDF document.

        Total pages in document: \(pageCount)
        Content (first \(maxPages) pages):

        \(text)

        Analyze the content and extract:
        - The document title
        - A clear summary
        - Relevant RPG tags (genre, setting, system, etc.)
        - Major sections or chapters
        - The document type (rulebook, adventure, supplement, etc.)
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
    You are an expert at analyzing tabletop RPG documents including rulebooks, adventures, \
    campaigns, and supplements.

    Your task is to extract structured metadata that helps game masters quickly understand \
    and organize their RPG PDF library.

    Focus on:
    - Clear, descriptive titles
    - Concise but informative summaries
    - Relevant tags (game system, genre, setting, theme)
    - Major sections that help navigation

    Be precise and factual. Only extract information that is clearly present in the document.
    """
}

#endif
