// @copyright André Trettin

import Foundation
import FoundationModels
import PDFKit

/// Foundation Models-based PDF summary analyzer for RPG documents
struct PdfSummaryAnalyzer: Sendable {

    /// Maximum number of pages to process (to stay under 4096 token limit)
    private let maxPages: Int
    /// Maximum characters to extract (rough estimate: 3 chars per token, targeting ~3000 tokens for input)
    private let maxCharacters: Int
    /// Instructions for the model
    private let instructions: String

    // MARK: - Initialization

    init(
        maxPages: Int = 40,
        maxCharacters: Int = 7000,
        instructions: String? = nil
    ) {
        self.maxPages = maxPages
        self.maxCharacters = maxCharacters
        self.instructions = instructions ?? Self.defaultInstructions
    }

    func analyzeWithProgress(from pdfDocument: PDFDocument, resultModel: PdfSummaryAnalyzyerResultModel, outputLanguage: String = "English") async throws -> PdfSummaryAnalysis {
        // Check model availability
        guard SystemLanguageModel.default.availability == .available else {
            throw PdfSummaryAnalysisError.modelUnavailable
        }

        // Validate document
        guard pdfDocument.pageCount > 0 else {
            throw PdfSummaryAnalysisError.emptyDocument
        }

        let pageLimit = min(maxPages, pdfDocument.pageCount)
        let pageTexts = extractPageTexts(from: pdfDocument, pageLimit: pageLimit)
        let limitedText = FoundationModelInputLimiter.limitedCombinedText(
            pages: pageTexts,
            maxPages: maxPages,
            maxCharacters: maxCharacters
        )

        guard !limitedText.isEmpty else {
            throw PdfSummaryAnalysisError.textExtractionFailed
        }

        await MainActor.run {
            resultModel.pageProgress = PdfAnalysisProgress(currentPage: pageLimit, totalPages: pageLimit)
        }

        do {
            let activeInstructions = instructions + "\nIMPORTANT: All output must be written in \(outputLanguage), regardless of the input language."
            let session = LanguageModelSession(instructions: activeInstructions)
            session.prewarm()

            let stream = session.streamResponse(
                to: buildPrompt(with: limitedText, pageCount: pdfDocument.pageCount, outputLanguage: outputLanguage),
                generating: PdfSummaryAnalysis.self
            )

            var latestContent: PdfSummaryAnalysis.PartiallyGenerated?

            for try await snapshot in stream {
                let content = snapshot.content
                latestContent = content
                let progress = PdfSummaryAnalysisProgress(content)
                await MainActor.run {
                    resultModel.analysisProgress = progress
                }
            }

            guard let partial = latestContent,
                  let title = partial.title,
                  let summary = partial.summary,
                  let tags = partial.tags,
                  let partialSections = partial.sections else {
                throw PdfSummaryAnalysisError.generationFailed("Streaming completed but no complete content received")
            }

            let sections: [PdfSection] = partialSections.compactMap { partialSection -> PdfSection? in
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

    private func buildPrompt(with text: String, pageCount: Int, outputLanguage: String) -> String {
        """
        Analyze and summarize this RPG PDF document.
        Output language: \(outputLanguage)

        Total pages in document: \(pageCount)
        Content (first \(maxPages) pages):

        \(text)

        Provide in \(outputLanguage) a structured summary analysis including:
        - The document title
        - A clear summary
        - Relevant RPG tags (genre, setting, system, etc.)
        - Major sections or chapters
        - The document type (rulebook, adventure, supplement, etc.)
        """
    }

    private func extractPageTexts(from pdfDocument: PDFDocument, pageLimit: Int) -> [String] {
        var pages: [String] = []
        pages.reserveCapacity(pageLimit)

        for pageIndex in 0..<pageLimit {
            guard let page = pdfDocument.page(at: pageIndex),
                  let pageText = page.string,
                  !pageText.isEmpty else {
                continue
            }
            pages.append(pageText)
        }

        return pages
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
    Be precise and factual, use document language. Don't change it.
    """
}
