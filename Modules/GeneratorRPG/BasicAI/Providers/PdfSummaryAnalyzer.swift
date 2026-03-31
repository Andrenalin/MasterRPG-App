// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels

#if canImport(PDFKit)
import PDFKit
#endif

/// Foundation Models-based PDF summary analyzer for RPG documents
@MainActor
public final class PdfSummaryAnalyzer: PdfSummaryAnalyzing, @unchecked Sendable {

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

    public func analyzeWithProgress(
        from pdfDocument: PDFDocument,
        onPartialContent: @MainActor @Sendable (PdfSummaryAnalysis.PartiallyGenerated) -> Void
    ) async throws -> PdfSummaryAnalysis {
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
        let session = LanguageModelSession(instructions: instructions)

        // Prewarm for faster generation
        session.prewarm()

        // Stream generation with progress updates
        do {
            let stream = session.streamResponse(
                to: buildPrompt(with: extractedText, pageCount: pdfDocument.pageCount),
                generating: PdfSummaryAnalysis.self
            )

            var latestContent: PdfSummaryAnalysis.PartiallyGenerated?

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
                throw PdfSummaryAnalysisError.generationFailed("Streaming completed but no complete content received")
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

            return PdfSummaryAnalysis(
                title: title,
                summary: summary,
                tags: tags,
                sections: sections
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw PdfSummaryAnalysisError.generationFailed(handleGenerationError(error))
        } catch {
            throw PdfSummaryAnalysisError.generationFailed(error.localizedDescription)
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
        Analyze and summarize this RPG PDF document.

        Total pages in document: \(pageCount)
        Content (first \(maxPages) pages):

        \(text)

        Provide structured summary analysis including:
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
            return "Content policy prevented analysis. The PDF may contain inappropriate content."
        case .unsupportedLanguageOrLocale:
            return "The PDF language is not supported by Apple Intelligence."
        case .assetsUnavailable(let reason):
            return "Model assets are unavailable: \(reason). Please ensure Apple Intelligence is fully downloaded."
        case .unsupportedGuide(let guide):
            return "PDF summary schema contains unsupported constraint: \(guide). This is a developer error."
        case .decodingFailure(let reason):
            return "Failed to decode PDF summary: \(reason). The document may have unusual formatting."
        case .rateLimited(let retryAfter):
            return "Rate limit exceeded. Please try again in \(retryAfter) seconds."
        case .concurrentRequests(let maxCount):
            return "Too many concurrent analysis requests. Maximum allowed: \(maxCount). Please wait for current analyses to complete."
        case .refusal(let reason, let category):
            return "Analysis refused: \(reason) (category: \(category)). The PDF content may violate content policies."
        @unknown default:
            return "An unexpected generation error occurred: \(error.localizedDescription)"
        }
    }

    // MARK: - Constants

    private static let defaultInstructions = """
    Analyze and summarize RPG documents (rulebooks, adventures, supplements).
    Provide clear titles, concise summaries, relevant tags, and major sections.
    Be precise and factual.
    """
}

#endif
