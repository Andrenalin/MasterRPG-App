// @copyright André Trettin

import CoreRPG
import SwiftUI
import PDFKit

public struct PdfContentExtractionView: View {

    @State private var model = PdfContentExtractionModel()
    let pdfDocument: PDFDocument
    let onContentExtracted: ([BlockEntryGenModel]) -> Void
    
    public init(pdfDocument: PDFDocument, onContentExtracted: @escaping ([BlockEntryGenModel]) -> Void) {
        self.pdfDocument = pdfDocument
        self.onContentExtracted = onContentExtracted
    }

    public var body: some View {
        FoundationBasicView {
            VStack(spacing: 20) {
                if model.isExtracting {
                    extractingView
                } else {
                    extractButton
                }
                
                if let error = model.lastError {
                    errorView(error)
                }
            }
            .padding()
        }
    }

    // MARK: - Subviews

    private var extractButton: some View {
        Button {
            analyze()
        } label: {
            Label {
                Text("Extract PDF Text", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.generator.icon)
            }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func analyze() {
        guard !model.isExtracting else { return }
        Task {
            let content = await model.extractWithProgress(from: pdfDocument)
            onContentExtracted(content)
        }
    }


    private var extractingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Extracting PDF content with Apple Intelligence...", bundle: .module)
                .font(.headline)

            ProgressView(value: Double(model.resultModel.pageProgress.currentPage), total: Double(model.resultModel.pageProgress.totalPages)) {
                HStack {
                    Text("Page \(model.resultModel.pageProgress.currentPage)", bundle: .module)
                    Spacer()
                    Text("Total: \(model.resultModel.pageProgress.totalPages) pages", bundle: .module)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !model.resultModel.extractionProgress.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .contentTransition(.symbolEffect(.automatic))
                        Text("Extracted \(model.resultModel.extractionProgress.count) blocks", bundle: .module)
                            .font(.subheadline)
                    }

                    ForEach(model.resultModel.extractionProgress.prefix(3), id: \.stableID) { block in
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: block.title)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }

                    if model.resultModel.extractionProgress.count > 3 {
                        Text("... and \(model.resultModel.extractionProgress.count - 3) more", bundle: .module)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func errorView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)

            Text(verbatim: error)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                model.clearError()
            } label: {
                Text("Dismiss", bundle: .module)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    let document = PreviewAssetFixture.url(.pdf)
        .flatMap(PDFDocument.init(url:))
        ?? PDFDocument()
    PdfContentExtractionView(pdfDocument: document) { _ in }
}
