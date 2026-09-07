// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import GeneratorRPG
import SwiftUI
import PDFKit

struct SummaryAnalysisView: View {
    let itemId: UUID

    @Environment(PdfRootModel.self) private var root
    @Environment(\.navigator) private var navigator

    @State private var propertySelection = PdfPropertySelection()
    @State private var viewState: ViewState = .loading

    var body: some View {
        ContentView(viewState: $viewState, propertySelection: $propertySelection)
            .navigationTitle(Text("PDF Analysis", bundle: .module))
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
                    .accessibilityHint(Text("Closes the extraction view without applying changes", bundle: .module))
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
                        .accessibilityLabel(Text("Apply selected properties", bundle: .module))
                        .accessibilityHint(Text("Applies the selected properties to the PDF and closes", bundle: .module))
                    }
                }
            }
            .task {
                await loadPDF()
            }
            .moduleTint(root.config.module)
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

    fileprivate enum ViewState {
        case loading
        case extracting(PDFDocument)
        case extracted(PdfSummaryAnalysis)
        case unavailable
    }
}

private struct ContentView: View {
    @Binding var viewState: SummaryAnalysisView.ViewState
    @Binding var propertySelection: PdfPropertySelection

    var body: some View {
        switch viewState {
        case .loading:
            LoadingView()
        case .extracting(let document):
            PdfSummaryAnalysisView(pdfDocument: document) { content in
                viewState = .extracted(content)
            }
        case .extracted(let content):
            SummaryPdfUpdateView(
                content: content,
                selectedProperties: $propertySelection
            )
        case .unavailable:
            UnavailableView()
        }
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading PDF...", bundle: .module)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Loading PDF document", bundle: .module))
    }
}

private struct UnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("PDF Not Available", bundle: .module)
            } icon: {
                Image(systemName: "doc.questionmark")
            }
        } description: {
            Text("The PDF file could not be loaded.", bundle: .module)
        }
        .accessibilityLabel(Text("PDF unavailable", bundle: .module))
        .accessibilityHint(Text("The PDF file could not be loaded", bundle: .module))
    }
}
#endif

#if !os(tvOS)
    #Preview(traits: .mockData) {
        SummaryAnalysisView(itemId: PdfModel.previewId)
    }
#endif
