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

    public func extract(from pdfDocument: PDFDocument) async throws -> [BlockGenModel] {
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

        // Generate structured blocks
        do {
            let response = try await session.respond(
                to: buildPrompt(with: extractedText, pageCount: pdfDocument.pageCount),
                generating: [BlockGenModel].self
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
        onPartialBlocks: @MainActor @Sendable ([BlockGenModel]) -> Void
    ) async throws -> [BlockGenModel] {
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

        // Generate without streaming for array types
        // Note: Foundation Models streaming for arrays doesn't provide complete objects incrementally
        do {
            let response = try await session.respond(
                to: buildPrompt(with: extractedText, pageCount: pdfDocument.pageCount),
                generating: [BlockGenModel].self
            )

            // Call onPartialBlocks once with the final result
            onPartialBlocks(response.content)
            return response.content
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
        Extract structured content blocks from this RPG PDF document.

        Total pages in document: \(pageCount)
        Content (first \(maxPages) pages):

        \(text)

        Analyze the content and extract structured blocks. Each block should be categorized as:
        - adventure: scenarios, quests, storylines, plot hooks
        - map: locations, rooms, dungeons, areas, regions
        - character: NPCs, monsters, creatures, stat blocks
        - table: random tables, loot tables, encounter tables, roll tables

        For each block:
        1. Extract a clear, descriptive name
        2. Provide helpful information/summary
        3. Add relevant tags
        4. Identify the category (adventure/map/character/table)
        5. Break into smaller entries (scenarios for adventures, rooms for maps, values for characters, rows for tables)

        Focus on extracting content that would be useful for game masters during play.
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
    You are an expert at analyzing tabletop RPG documents and extracting structured, \
    playable content that game masters can use at the table.

    Your task is to identify distinct blocks of content (adventures, maps, characters, tables) \
    and break them into smaller, manageable entries.

    Focus on:
    - Clear identification of content type (adventure/map/character/table)
    - Meaningful names and descriptions
    - Useful breakdowns (scenarios, rooms, stat blocks, table rows)
    - Accurate categorization

    Be precise and extract only clearly defined, usable content.
    """
}

#endif
