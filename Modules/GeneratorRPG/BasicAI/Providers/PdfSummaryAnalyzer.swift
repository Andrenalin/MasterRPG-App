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

    func analyzeWithProgress(from pdfDocument: PDFDocument, resultModel: PdfSummaryAnalyzerResultModel, outputLanguage: String = "English") async throws -> PdfSummaryAnalysis {
        try AnalyzerRunner.requireModel()

        // Validate document
        guard pdfDocument.pageCount > 0 else {
            throw PdfSummaryAnalysisError.emptyDocument
        }

        let pageLimit = min(maxPages, pdfDocument.pageCount)
        // Off the main actor, see `PdfPageTextReader` (CODE_AUDIT_18 §3.5).
        // Cleaned and without imprint pages, so the character budget goes to the content.
        let readPages = try await PdfPageTextReader.pages(
            of: .init(document: pdfDocument),
            pageLimit: pageLimit,
            maximumCharactersPerPage: maxCharacters,
            stopAfterCharacters: maxCharacters,
            cleansForAnalysis: true
        )
        let pageTexts = PdfAnalysisTextCleaner.contentPages(readPages)
            .map { (pageNumber: $0.pageNumber, text: $0.text) }
        let pageCount = pdfDocument.pageCount
        let limitedText = FoundationModelInputLimiter.limitedCombinedText(
            pages: pageTexts,
            maxPages: maxPages,
            maxCharacters: maxCharacters
        )

        guard !limitedText.isEmpty else {
            throw PdfSummaryAnalysisError.textExtractionFailed
        }

        await resultModel.setPageProgress(PdfAnalysisProgress(currentPage: pageLimit, totalPages: pageLimit))

        return try await AnalyzerRunner.run(subject: .pdfAnalysis) {
            let activeInstructions = instructions + "\nIMPORTANT: All output must be written in \(outputLanguage), regardless of the input language.\n" + UntrustedPromptText.instruction
            let session = LanguageModelSession(instructions: activeInstructions)
            session.prewarm()

            let stream = session.streamResponse(
                to: buildPrompt(with: limitedText, pageCount: pageCount, outputLanguage: outputLanguage),
                generating: PdfSummaryAnalysis.self
            )

            var latestContent: PdfSummaryAnalysis.PartiallyGenerated?

            for try await snapshot in stream {
                let content = snapshot.content
                latestContent = content
                let progress = PdfSummaryAnalysisProgress(content)
                await resultModel.setAnalysisProgress(progress)
            }

            guard let partial = latestContent,
                  let title = partial.title,
                  let summary = partial.summary,
                  let tags = partial.tags,
                  let partialSections = partial.sections else {
                throw PdfSummaryAnalysisError.generationFailed(
                    String(
                        localized: "Streaming completed but no complete content was received.",
                        bundle: .module
                    )
                )
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
                category: partial.category ?? .otherSupplement,
                documentKind: partial.documentKind ?? "",
                genre: partial.genre ?? "",
                tags: PdfSummaryAnalysis.tags(
                    category: partial.category,
                    documentKind: partial.documentKind,
                    genre: partial.genre,
                    tags: tags,
                    title: title,
                    outputLanguage: outputLanguage
                ),
                sections: sections
            )
        }

    }

    // MARK: - Private Methods

    private func buildPrompt(with text: String, pageCount: Int, outputLanguage: String) -> String {
        """
        Analyze and summarize this RPG PDF document.
        Output language: \(outputLanguage)

        Total pages in document: \(pageCount)
        Content (text of the first \(maxPages) pages, shortened to about \(maxCharacters) characters; each page starts with its page number):

        \(UntrustedPromptText.fenced(text))

        Provide in \(outputLanguage) a structured summary analysis including:
        - The document title
        - A clear summary
        - Its category, its kind of document and the genre of its game world, in \(outputLanguage)
        - \(PdfSummaryAnalysis.freeTagCountRange.lowerBound) to \(PdfSummaryAnalysis.freeTagCountRange.upperBound) specific tags in \(outputLanguage): its main subject, and its specific places, peoples, creatures or themes
        - Major sections or chapters
        """
    }

    // MARK: - Constants

    private static let defaultInstructions = """
    Analyze and summarize RPG documents (rulebooks, adventures, supplements).
    Provide clear titles, concise summaries, tags, and major sections.
    Name the kind of document and the genre of its game world as content words, never as labels. \
    Tags are \(PdfSummaryAnalysis.freeTagCountRange.lowerBound) to \(PdfSummaryAnalysis.freeTagCountRange.upperBound) \
    short keywords that tell this document apart from other RPG documents: its main subject, and \
    its named places, peoples, creatures, factions and central themes. \
    \(GeneratedTagRules.rules(extraGenericTags: ["Role-playing game"]))
    Be precise and factual.
    """
}
