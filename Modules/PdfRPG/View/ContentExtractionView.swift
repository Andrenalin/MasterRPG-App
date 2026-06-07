// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import GeneratorRPG
import SwiftUI
import PDFKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ContentExtractionView: View {
    let itemId: UUID

    @Environment(PdfRootModel.self) private var root
    @Environment(\.navigator) private var navigator

    @State private var viewState: ViewState = .loading

    var body: some View {
        contentView
            .navigationTitle(Text("PDF Extractor", bundle: .module))
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
                        Button {
                            copyToClipboard()
                        } label: {
                            Label {
                                Text("Copy", bundle: .module)
                            } icon: {
                                Image(systemName: "doc.on.clipboard")
                            }
                        }
                        .accessibilityLabel(Text("Copy blocks to clipboard", bundle: .module))
                        .accessibilityHint(Text("Copies the extracted content blocks as text to the clipboard", bundle: .module))
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
            ContentBlocksView(content: content)
        case .unavailable:
            unavailableView
        }
    }

    private var loadingView: some View {
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

    private var unavailableView: some View {
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

    // MARK: - Actions

    private func loadPDF() async {
        guard let document = await root.itemController.pdfDocument(for: itemId) else {
            viewState = .unavailable
            return
        }
        viewState = .extracting(document)
    }

    private func copyToClipboard() {
        guard case .extracted(let content) = viewState else {
            return
        }

        var text = ""
        for block in content {
            text += block.title + "\n"
            text += block.content + "\n"
            text += "\n"
        }

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    // MARK: - ViewState

    private enum ViewState {
        case loading
        case extracting(PDFDocument)
        case extracted([BlockEntryGenModel])
        case unavailable
    }
}
#endif
