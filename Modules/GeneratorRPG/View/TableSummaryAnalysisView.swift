// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Runs on-device AI extraction on table entry text and streams progress updates.
/// Wraps `FoundationBasicView` so it handles model availability automatically.
public struct TableSummaryAnalysisView: View {

    @State private var model = TableSummaryAnalysisModel()
    @State private var selectedLanguage: OutputLanguage = OutputLanguage.forCurrentLocale()
    let entriesText: String
    let onAnalysisCompleted: (TableSummaryAnalysis) -> Void

    public init(entriesText: String, onAnalysisCompleted: @escaping (TableSummaryAnalysis) -> Void) {
        self.entriesText = entriesText
        self.onAnalysisCompleted = onAnalysisCompleted
    }

    public var body: some View {
        FoundationBasicView {
            VStack(spacing: 20) {
                if model.isAnalyzing {
                    analyzingView
                } else {
                    languagePicker
                    analyzeButton
                }

                if let error = model.lastError {
                    errorView(error)
                }
            }
            .padding()
        }
    }

    // MARK: - Subviews

    private var languagePicker: some View {
        HStack {
            Text("Output Language", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $selectedLanguage) {
                ForEach(OutputLanguage.supported) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
        }
        .padding(.horizontal, 4)
    }

    private var analyzeButton: some View {
        Button {
            analyze()
        } label: {
            Label {
                Text("Analyze Text Entries", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.generator.icon)
            }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Analyzing with Apple Intelligence...", bundle: .module)
                .font(.headline)

            if let progress = model.resultModel.analysisProgress {
                VStack(alignment: .leading, spacing: 8) {
                    progressRow(
                        ready: progress.title != nil,
                        label: "Title: \(progress.title ?? "<none>")"
                    )
                    progressRow(
                        ready: progress.description != nil,
                        label: progress.description == nil ? "Description ...." : "Description extracted"
                    )
                    progressRow(
                        ready: !(progress.tags?.isEmpty ?? true),
                        label: "Found \(progress.tags?.count ?? 0) tags"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func progressRow(ready: Bool, label: String) -> some View {
        HStack {
            Image(systemName: ready ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ready ? .green : .red)
                .contentTransition(.symbolEffect(.automatic))
            Text(label)
                .font(.subheadline)
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

    // MARK: - Actions

    private func analyze() {
        guard !model.isAnalyzing else { return }
        Task {
            if let content = await model.analyze(entriesText: entriesText, outputLanguage: selectedLanguage.englishName) {
                onAnalysisCompleted(content)
            }
        }
    }
}
