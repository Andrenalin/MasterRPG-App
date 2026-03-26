// @copyright André Trettin

#if !os(tvOS)

import Foundation
import CoreGraphics
import GeneratorRPG
import CoreRPG

/// Extension to apply extracted PDF content to PdfModel
extension PdfModel {

    /// Applies extracted content to update the model's metadata
    /// - Parameters:
    ///   - content: The extracted PDF content
    ///   - updateExisting: If true, only updates empty fields. If false, overwrites all fields.
    public func applyExtractedContent(_ content: PdfExtractedContent, updateExisting: Bool = false) {
        // Update name if empty or forcing update
        if updateExisting || name.isEmpty {
            name = content.title
        }

        // Update description if empty or forcing update
        if updateExisting || description.isEmpty {
            description = content.summary
        }

        // Update tags if empty or forcing update
        if updateExisting || tags.isEmpty {
            tags = content.tags
        }

        // Map document type to category
        if updateExisting || category == .pdf {
            category = mapDocumentTypeToCategory(content.documentType)
        }

        // Create entries from sections if enabled
        if !content.sections.isEmpty {
            appendSectionsAsEntries(content.sections, replaceExisting: !updateExisting)
        }
    }

    /// Maps the extracted document type to an appropriate ItemListCategory
    private func mapDocumentTypeToCategory(_ documentType: DocumentType) -> ItemListCategory {
        switch documentType {
        case .rulebook:
            return .pdf  // Rulebook is a PDF category
        case .adventure:
            return .adventure
        case .campaign:
            return .scenario  // Campaign maps to scenario
        case .supplement:
            return .pdf
        case .characterSheet:
            return .pdf  // Character sheets are PDFs
        case .map:
            return .map
        case .reference:
            return .pdf  // Reference is a PDF
        case .other:
            return .pdf
        }
    }

    /// Appends sections as PDF entries
    private func appendSectionsAsEntries(_ sections: [PdfSection], replaceExisting: Bool) {
        var newEntries: [PdfEntryModel] = []

        for section in sections {
            let pageNumberString = section.pageNumber.map { String($0) } ?? ""
            let entry = PdfEntryModel(
                id: UUID(),
                name: section.heading,
                content: section.summary,
                pageNumber: pageNumberString,
                bounds: .zero,
                displayState: 0
            )
            newEntries.append(entry)
        }

        if replaceExisting {
            entries = newEntries
        } else {
            entries.append(contentsOf: newEntries)
        }
    }
}

/// Helper method to create a PdfModel from extracted content
extension PdfModel {

    /// Creates a new PdfModel from extracted PDF content
    /// - Parameters:
    ///   - content: The extracted content
    ///   - fileUrl: The file URL for the PDF
    ///   - category: Optional category override (defaults to mapped category from document type)
    /// - Returns: A new PdfModel populated with the extracted data
    public static func from(
        extractedContent content: PdfExtractedContent,
        fileUrl: FileUrl?,
        category: ItemListCategory? = nil
    ) -> PdfModel {
        let model = PdfModel(
            id: UUID(),
            name: content.title,
            description: content.summary,
            tags: content.tags,
            category: category ?? mapDocumentTypeToCategory(content.documentType),
            displayState: 0,
            fileUrl: fileUrl,
            entries: [],
            parentId: nil
        )

        // Add sections as entries
        for section in content.sections {
            let pageNumberString = section.pageNumber.map { String($0) } ?? ""
            let entry = PdfEntryModel(
                id: UUID(),
                name: section.heading,
                content: section.summary,
                pageNumber: pageNumberString,
                bounds: .zero,
                displayState: 0
            )
            model.entries.append(entry)
        }

        return model
    }

    private static func mapDocumentTypeToCategory(_ documentType: DocumentType) -> ItemListCategory {
        switch documentType {
        case .rulebook:
            return .pdf  // Rulebook is a PDF category
        case .adventure:
            return .adventure
        case .campaign:
            return .scenario  // Campaign maps to scenario
        case .supplement:
            return .pdf
        case .characterSheet:
            return .pdf  // Character sheets are PDFs
        case .map:
            return .map
        case .reference:
            return .pdf  // Reference is a PDF
        case .other:
            return .pdf
        }
    }
}

#endif
