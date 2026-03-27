// @copyright André Trettin

#if !os(tvOS)
import SwiftUI

#if canImport(PDFKit)
import PDFKit
#endif

/// A button that triggers PDF content extraction with AI
struct PdfExtractionButton: View {
    let itemId: UUID
    let isSpecialCategory: Bool
    let hasUrl: Bool
    let onTap: (PDFDocument?) async -> Void

    @Environment(\.pdfItemController) private var itemController

    init(
        itemId: UUID,
        isSpecialCategory: Bool,
        hasUrl: Bool,
        onTap: @escaping (PDFDocument?) async -> Void
    ) {
        self.itemId = itemId
        self.isSpecialCategory = isSpecialCategory
        self.hasUrl = hasUrl
        self.onTap = onTap
    }

    var body: some View {
        if hasUrl && !isSpecialCategory {
            Button {
                Task {
                    let pdfDocument = await itemController?.pdfDocument(for: itemId)
                    await onTap(pdfDocument)
                }
            } label: {
                Label("Extract PDF Information with AI", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Environment key for accessing ItemController
private struct PdfItemControllerKey: EnvironmentKey {
    static let defaultValue: ItemController? = nil
}

extension EnvironmentValues {
    var pdfItemController: ItemController? {
        get { self[PdfItemControllerKey.self] }
        set { self[PdfItemControllerKey.self] = newValue }
    }
}

#endif
