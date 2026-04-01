// @copyright André Trettin

import CoreRPG
import SwiftUI
import PDFKit

public struct PdfContentExtractionView: View {

    @State private var model = PdfContentExtractionModel()
    let pdfDocument: PDFDocument
    let onContentExtracted: ([BlockGenModel]) -> Void

    @State private var extractionText = ""
    
    @State private var extractedBlock: [BlockGenModel] = []
    
    public init(pdfDocument: PDFDocument, onContentExtracted: @escaping ([BlockGenModel]) -> Void) {
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
            Task {
                let content = await model.extractWithProgress(from: pdfDocument)
                extractedBlock = content
                onContentExtracted(content)
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

            Text(extractionText)
        }
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
