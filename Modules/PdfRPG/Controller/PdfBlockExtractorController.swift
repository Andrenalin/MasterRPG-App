// @copyright André Trettin

#if !os(tvOS)

import Foundation
import GeneratorRPG
import FoundationModels
import Observation

#if canImport(PDFKit)
import PDFKit
#endif

/// Controller for PDF block extraction in the PdfRPG module
@MainActor
@Observable
public final class PdfBlockExtractorController {

    // MARK: - Published Properties

    public private(set) var isExtracting: Bool = false
    public private(set) var extractedBlocks: [BlockGenModel] = []
    public private(set) var lastError: String?
    public private(set) var isModelAvailable: Bool = true

    // MARK: - Callback

    public var onTextExtracted: ((String) -> Void)?

    // MARK: - Private Properties

    private let useCase: ExtractPdfBlocksUseCase

    // MARK: - Initialization

    public init(useCase: ExtractPdfBlocksUseCase = ExtractPdfBlocksUseCase()) {
        self.useCase = useCase
        checkModelAvailability()
    }

    // MARK: - Public Methods

    /// Extracts blocks from a PDF document
    /// - Parameter pdfDocument: The PDF to analyze
    /// - Returns: Array of extracted blocks, or empty if extraction fails
//    public func extract(from pdfDocument: PDFDocument) async -> [BlockGenModel] {
//        guard isModelAvailable else {
//            lastError = "Apple Intelligence is not available on this device"
//            return []
//        }
//
//        isExtracting = true
//        extractedBlocks = []
//        lastError = nil
//
//        defer { isExtracting = false }
//
//        do {
//            let blocks = try await useCase.extract(from: pdfDocument)
//            extractedBlocks = blocks
//            return blocks
//        } catch {
//            lastError = error.localizedDescription
//            return []
//        }
//    }

    /// Extracts blocks with streaming progress updates
    /// - Parameter pdfDocument: The PDF to analyze
    /// - Returns: Final extracted blocks, or empty if extraction fails
    public func extractWithProgress(from pdfDocument: PDFDocument) async -> [BlockGenModel] {
        guard isModelAvailable else {
            lastError = "Apple Intelligence is not available on this device"
            return []
        }

        isExtracting = true
        extractedBlocks = []
        lastError = nil

        defer {
            isExtracting = false
        }

        do {
            let blocks = try await useCase.extractWithProgress(from: pdfDocument) { [weak self] partial in
                self?.extractedBlocks = partial
            }
            extractedBlocks = blocks

            // Trigger callback if set
            if !blocks.isEmpty {
                let text = convertToEntryText(blocks: blocks)
                onTextExtracted?(text)
            }

            return blocks
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    /// Extracts blocks from a PDF file URL
    /// - Parameter url: URL to the PDF file
    /// - Returns: Array of extracted blocks, or empty if extraction fails
//    public func extract(from url: URL) async -> [BlockGenModel] {
//        guard let pdfDocument = PDFDocument(url: url) else {
//            lastError = "Failed to load PDF from URL"
//            return []
//        }
//        return await extract(from: pdfDocument)
//    }

    /// Checks if the Foundation Models are available
    public func checkModelAvailability() {
        isModelAvailable = SystemLanguageModel.default.availability == .available
    }

    /// Clears the last error message
    public func clearError() {
        lastError = nil
    }

    /// Converts extracted blocks to table entries formatted text
    /// - Parameter blocks: The blocks to convert
    /// - Returns: Formatted text ready for the quick entry editor
    public func convertToEntryText(blocks: [BlockGenModel]) -> String {
        blocks.flatMap { block in
            block.entries.map { entry in
                "\(entry.title)\n\(entry.content)"
            }
        }.joined(separator: "\n\n")
    }
}

#endif
