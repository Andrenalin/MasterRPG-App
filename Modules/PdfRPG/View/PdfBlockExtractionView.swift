// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import GeneratorRPG
import SwiftUI
import PDFKit

struct PdfBlockExtractionView: View {
    let itemId: UUID

    @Environment(PdfRootModel.self) private var root
    @Environment(\.navigator) private var navigator

    @State private var propertySelection = PdfPropertySelection()
    @State private var viewState: ViewState = .loading

    var body: some View {
        contentView
            .navigationTitle("PDF Extractor")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        navigator.back()
                    } label: {
                        Label {
                            Text("Cancel", bundle: .module)
                        } icon: {
                            Image(systemName: "xmark")
                        }
                    }
                    .accessibilityLabel(Text("Cancel PDF extraction", bundle: .module))
                    .accessibilityHint("Closes the extraction view without applying changes")
                }

                if case .extracted = viewState {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm) {
                            applyAndClose()
                        } label: {
                            Label {
                                Text("Apply", bundle: .module)
                            } icon: {
                                Image(systemName: "checkmark")
                            }
                        }
                        .disabled(!propertySelection.hasAnySelected)
                        .accessibilityLabel("Apply selected properties")
                        .accessibilityHint("Applies the selected properties to the PDF and closes")
                    }
                }
            }
            .task {
                await loadPDF()
            }
    }

    // MARK: - View Components

    @ViewBuilder
    private var contentView: some View {
        switch viewState {
        case .loading:
            loadingView
        case .extracting(let document):
            PdfContentExtractionView(pdfDocument: document) { content in
                viewState = .extracted(content)
            }
        case .extracted(let content):
            ExtractedPdfContentView(
                content: content,
                selectedProperties: $propertySelection
            )
        case .unavailable:
            unavailableView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading PDF...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading PDF document")
    }

    private var unavailableView: some View {
        ContentUnavailableView(
            "PDF Not Available",
            systemImage: "doc.questionmark",
            description: Text("The PDF file could not be loaded.")
        )
        .accessibilityLabel("PDF unavailable")
        .accessibilityHint("The PDF file could not be loaded")
    }

    // MARK: - Actions

    private func loadPDF() async {
        guard let document = await root.itemController.pdfDocument(for: itemId) else {
            viewState = .unavailable
            return
        }
        viewState = .extracting(document)
    }

    private func applyAndClose() {
        guard case .extracted(let content) = viewState, propertySelection.hasAnySelected else {
            navigator.back()
            return
        }

        root.editController.applyExtractedContent(content, to: itemId, selection: propertySelection)
        navigator.back()
    }

    // MARK: - ViewState

    private enum ViewState {
        case loading
        case extracting(PDFDocument)
        case extracted(PdfExtractedContent)
        case unavailable
    }
}
#endif
