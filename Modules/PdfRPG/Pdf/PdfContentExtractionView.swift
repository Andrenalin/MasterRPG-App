// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import GeneratorRPG
import PDFKit
import SwiftUI

/// View for extracting and displaying PDF content metadata
public struct PdfContentExtractionView: View {

    @State private var controller = PdfContentExtractorController()
    let pdfDocument: PDFDocument
    let onContentExtracted: (PdfExtractedContent) -> Void

    public init(pdfDocument: PDFDocument, onContentExtracted: @escaping (PdfExtractedContent) -> Void) {
        self.pdfDocument = pdfDocument
        self.onContentExtracted = onContentExtracted
    }

    public var body: some View {
        VStack(spacing: 20) {
            if !controller.isModelAvailable {
                unavailableView
            } else if controller.isExtracting {
                extractingView
            } else {
                extractButton
            }

            if let error = controller.lastError {
                errorView(error)
            }
        }
        .padding()
        .onAppear {
            controller.checkModelAvailability()
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            extracting()
        }
    }

    // MARK: - Subviews

    private var extractButton: some View {
        Button {
            guard controller.isExtracting else { return }
            extracting()
        } label: {
            Label {
                Text("Extract PDF Information", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.generator.icon)
            }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
    
    private func extracting() {
        Task {
            if let content = await controller.extractWithProgress(from: pdfDocument) {
                onContentExtracted(content)
            }
        }
    }

    private var extractingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Analyzing PDF with Apple Intelligence...", bundle: .module)
                .font(.headline)

            if let progress = controller.extractionProgress {
                VStack(alignment: .leading, spacing: 8) {
                    if let title = progress.title {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Title: \(title)", bundle: .module)
                                .font(.subheadline)
                        }
                    }

                    if progress.summary != nil {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Summary extracted", bundle: .module)
                                .font(.subheadline)
                        }
                    }

                    if let tags = progress.tags, !tags.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Found \(tags.count) tags", bundle: .module)
                                .font(.subheadline)
                        }
                    }

                    if let sections = progress.sections, !sections.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Identified \(sections.count) sections", bundle: .module)
                                .font(.subheadline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Apple Intelligence Required", bundle: .module)
                .font(.headline)

            Text("PDF content extraction requires Apple Intelligence, which is not available on this device.", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func errorView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                controller.clearError()
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

#Preview("Extraction View") {
    if let url = Bundle.main.url(forResource: "sample", withExtension: "pdf"),
       let pdfDocument = PDFDocument(url: url) {
        PdfContentExtractionView(pdfDocument: pdfDocument) { content in
            print("Extracted: \(content.title)")
        }
    } else {
        Text("No sample PDF available")
    }
}

#endif
