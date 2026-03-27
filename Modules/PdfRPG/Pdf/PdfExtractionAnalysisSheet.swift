// @copyright André Trettin

#if !os(tvOS)
import SwiftUI
import GeneratorRPG

#if canImport(PDFKit)
import PDFKit
#endif

/// Sheet view for PDF analysis with AI extraction
struct PdfExtractionAnalysisSheet: View {
    let pdfDocument: PDFDocument?
    let onDismiss: () -> Void
    let onContentExtracted: (PdfExtractedContent) -> Void

    init(
        pdfDocument: PDFDocument?,
        onDismiss: @escaping () -> Void,
        onContentExtracted: @escaping (PdfExtractedContent) -> Void
    ) {
        self.pdfDocument = pdfDocument
        self.onDismiss = onDismiss
        self.onContentExtracted = onContentExtracted
    }

    var body: some View {
        NavigationStack {
            Group {
                if let pdfDocument {
                    PdfContentExtractionView(pdfDocument: pdfDocument) { content in
                        onContentExtracted(content)
                        onDismiss()
                    }
                } else {
                    ContentUnavailableView(
                        "PDF Not Available",
                        systemImage: "doc.questionmark",
                        description: Text("The PDF file could not be loaded.")
                    )
                }
            }
            .navigationTitle("AI PDF Analysis")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onDismiss()
                    }
                }
            }
        }
    }
}

#endif
