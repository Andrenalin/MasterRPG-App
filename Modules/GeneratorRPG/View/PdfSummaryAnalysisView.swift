// @copyright André Trettin

import CoreRPG
import PDFKit
import SwiftUI

/// View for analyzing and displaying PDF summary
public struct PdfSummaryAnalysisView: View {

    @State private var model = PdfSummaryAnalysisModel()
    let pdfDocument: PDFDocument
    let onAnalysisCompleted: (PdfSummaryAnalysis) -> Void

    public init(pdfDocument: PDFDocument, onAnalysisCompleted: @escaping (PdfSummaryAnalysis) -> Void) {
        self.pdfDocument = pdfDocument
        self.onAnalysisCompleted = onAnalysisCompleted
    }

    public var body: some View {
        FoundationBasicView {
            VStack(spacing: 20) {
                if model.isAnalyzing {
                    analyzingView
                } else {
                    analyzeButton
                }
                
                if let error = model.lastError {
                    errorView(error)
                }
            }
            .padding()
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            analyze()
        }
    }

    // MARK: - Subviews

    private var analyzeButton: some View {
        Button {
            analyze()
        } label: {
            Label {
                Text("Analyze PDF Summary", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.generator.icon)
            }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func analyze() {
        guard !model.isAnalyzing else { return }
        Task {
            if let content = await model.analyzeWithProgress(from: pdfDocument) {
                onAnalysisCompleted(content)
            }
        }
    }

    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Analyzing PDF with Apple Intelligence...", bundle: .module)
                .font(.headline)

            ProgressView(value: Double(model.resultModel.pageProgress?.currentPage ?? 0), total: Double(model.resultModel.pageProgress?.totalPages ?? 1)) {
                HStack {
                    Text("Page \(model.resultModel.pageProgress?.currentPage ?? 0)", bundle: .module)
                    Spacer()
                    Text("Total: \(model.resultModel.pageProgress?.totalPages ?? 0) pages", bundle: .module)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let progress = model.resultModel.analysisProgress {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: progress.title == nil ? "xmark.circle" : "checkmark.circle.fill")
                            .foregroundStyle(progress.title == nil ? .red : .green)
                            .contentTransition(.symbolEffect(.automatic))
                        Text("Title: \(progress.title ?? "<none>")", bundle: .module)
                            .font(.subheadline)
                    }

                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(progress.summary == nil ? .red : .green)
                            .contentTransition(.symbolEffect(.automatic))
                        Text("Summary \(progress.summary == nil ? "...." : "extracted")", bundle: .module)
                            .font(.subheadline)
                    }

                    HStack {
                        Image(systemName: (progress.tags?.isEmpty ?? true) ? "xmark.circle" : "checkmark.circle.fill")
                            .foregroundStyle((progress.tags?.isEmpty ?? true) ? .red : .green)
                            .contentTransition(.symbolEffect(.automatic))

                        Text("Found \(progress.tags?.count ?? 0) tags", bundle: .module)
                            .font(.subheadline)
                    }

                    HStack {
                        Image(systemName: (progress.sections?.isEmpty ?? true) ? "xmark.circle" : "checkmark.circle.fill")
                            .foregroundStyle((progress.sections?.isEmpty ?? true) ? .red : .green)
                            .contentTransition(.symbolEffect(.automatic))

                        Text("Identified \(progress.sections?.count ?? 0) sections", bundle: .module)
                            .font(.subheadline)
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

#Preview("Summary Analysis View") {
    if let url = Bundle.main.url(forResource: "sample", withExtension: "pdf"),
       let pdfDocument = PDFDocument(url: url) {
        PdfSummaryAnalysisView(pdfDocument: pdfDocument) { content in
            print("Analyzed: \(content.title)")
        }
    } else {
        Text("No sample PDF available")
    }
}
