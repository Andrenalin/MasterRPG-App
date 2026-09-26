// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Runs on-device AI extraction on table entry text and streams progress updates.
/// Wraps `FoundationBasicView` so it handles model availability automatically.
public struct TableSummaryAnalysisView: View {

    @State private var model = TableSummaryAnalysisModel()
    @State private var selectedLanguage: OutputLanguage = OutputLanguage.forCurrentLocale()
    /// Owned so dismissing the sheet cancels the on-device model work instead of leaving it
    /// running (and writing results) in the background. See CODE_AUDIT_18 §3.6.
    @State private var analysisTask: Task<Void, Never>?
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
                    AnalyzingView(model: model)
                } else {
                    OutputLanguagePickerView(selectedLanguage: $selectedLanguage)
                        .padding(.horizontal, 4)
                    AnalyzeButtonView(action: analyze)
                }

                if let error = model.lastError {
                    errorView(error)
                }
            }
            .padding()
        }
        .onDisappear { analysisTask?.cancel() }
    }

    // MARK: - Subviews

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
        .clipShape(.rect(cornerRadius: 8))
    }

    // MARK: - Actions

    private func analyze() {
        guard !model.isAnalyzing else { return }
        analysisTask = Task {
            let content = await model.analyze(entriesText: entriesText, outputLanguage: selectedLanguage.englishName)
            guard !Task.isCancelled, let content else { return }
            onAnalysisCompleted(content)
        }
    }
}

private struct AnalyzeButtonView: View {
    let action: () -> Void

    var body: some View {
        Button {
            action()
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
}

private struct AnalyzingView: View {
    let model: TableSummaryAnalysisModel

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Analyzing with Apple Intelligence...", bundle: .module)
                .font(.headline)

            if let progress = model.resultModel.analysisProgress {
                VStack(alignment: .leading, spacing: 8) {
                    if let title = progress.title {
                        progressRow(
                            ready: true,
                            label: LocalizedStringResource("Title: \(title)", bundle: .module)
                        )
                    } else {
                        progressRow(
                            ready: false,
                            label: LocalizedStringResource("Title unavailable", bundle: .module)
                        )
                    }
                    progressRow(
                        ready: progress.description != nil,
                        label: progress.description == nil
                            ? LocalizedStringResource("Description pending", bundle: .module)
                            : LocalizedStringResource("Description extracted", bundle: .module)
                    )
                    progressRow(
                        ready: !(progress.tags?.isEmpty ?? true),
                        label: LocalizedStringResource(
                            "Found \(progress.tags?.count ?? 0) tags",
                            bundle: .module
                        )
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))
            }
        }
    }

    private func progressRow(ready: Bool, label: LocalizedStringResource) -> some View {
        HStack {
            Image(systemName: ready ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ready ? .green : .red)
                .contentTransition(.symbolEffect(.automatic))
            Text(label)
                .font(.subheadline)
        }
    }
}

#Preview {
    TableSummaryAnalysisView(entriesText: "A ruined watchtower overlooks the northern road.") { _ in }
}
