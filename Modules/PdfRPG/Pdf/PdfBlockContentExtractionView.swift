// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import SwiftUI
import GeneratorRPG
import PDFKit

public struct PdfBlockContentExtractionView: View {

    @State private var controller = PdfBlockExtractorController()
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
    }

    // MARK: - Subviews

    private var extractButton: some View {
        Button {
            Task {
                let content = await controller.extractWithProgress(from: pdfDocument)
                print(content)
            }
        } label: {
            Label("Extract PDF Information", systemImage: NetworkModules.generator.icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var extractingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Analyzing PDF with Apple Intelligence...")
                .font(.headline)

//            let progress = controller.isExtracting
//            Text("\(progress)")
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Apple Intelligence Required")
                .font(.headline)

            Text("PDF content extraction requires Apple Intelligence, which is not available on this device.")
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

            Button("Dismiss") {
                controller.clearError()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#endif
