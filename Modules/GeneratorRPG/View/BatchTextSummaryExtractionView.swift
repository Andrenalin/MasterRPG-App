// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import SwiftUI

private enum BatchItemStatus: Sendable {
    case pending
    case analyzing
    case completed
    case failed(String)
}

/// Batch AI-extraction view: processes multiple items sequentially using on-device AI.
/// Apply rules: title if name is empty, description appended, tags replaced.
public struct BatchTextSummaryExtractionView: View {

    let module: NetworkModules
    let ids: [UUID]
    let itemController: any ItemControllable
    let editController: any EditControllable

    @State private var selectedLanguage: OutputLanguage = .forCurrentLocale()
    @State private var statuses: [UUID: BatchItemStatus] = [:]
    @State private var isRunning = false
    @State private var resultModel = TableSummaryAnalyzerResultModel()

    @Environment(\.dismiss) private var dismiss

    public init(
        module: NetworkModules,
        ids: [UUID],
        itemController: any ItemControllable,
        editController: any EditControllable
    ) {
        self.module = module
        self.ids = ids
        self.itemController = itemController
        self.editController = editController
    }

    public var body: some View {
        NavigationStack {
            FoundationBasicView {
                List {
                    if !isRunning {
                        Section {
                            languagePicker
                        }
                    }
                    Section {
                        ForEach(ids, id: \.self) { id in
                            itemRow(for: id)
                        }
                    } header: {
                        Text("\(ids.count) Items", bundle: .module)
                    }
                    if let progress = resultModel.analysisProgress, isRunning {
                        analysisProgressSection(progress)
                    }
                }
            }
            .navigationTitle(Text("Extract Information", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Cancel", bundle: .module))
                    .disabled(isRunning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isRunning {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button {
                            runBatch()
                        } label: {
                            Label {
                                Text("Start", bundle: .module)
                            } icon: {
                                Image(systemName: "sparkles")
                            }
                        }
                        .disabled(ids.isEmpty)
                    }
                }
            }
            .tint(module.tint)
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
    }

    private func itemRow(for id: UUID) -> some View {
        let name = itemController.itemSync(for: id)?.name ?? ""
        let status = statuses[id] ?? .pending
        return HStack(spacing: 12) {
            statusIcon(for: status)
            Text(name.isEmpty ? id.uuidString : name)
            Spacer()
            statusLabel(for: status)
        }
    }

    @ViewBuilder
    private func statusIcon(for status: BatchItemStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .contentTransition(.symbolEffect(.automatic))
        case .analyzing:
            ProgressView()
                .scaleEffect(0.8) 
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .contentTransition(.symbolEffect(.automatic))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .contentTransition(.symbolEffect(.automatic))
        }
    }

    @ViewBuilder
    private func statusLabel(for status: BatchItemStatus) -> some View {
        switch status {
        case .pending:
            EmptyView()
        case .analyzing:
            EmptyView()
        case .completed:
            Text("Done", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let error):
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func analysisProgressSection(_ progress: TableSummaryAnalysisProgress) -> some View {
        Section {
            progressRow(ready: progress.title != nil, label: "Title: \(progress.title ?? "...")")
            progressRow(
                ready: progress.description != nil,
                label: progress.description == nil ? "Description..." : "Description extracted"
            )
            progressRow(ready: !(progress.tags?.isEmpty ?? true), label: "Found \(progress.tags?.count ?? 0) tags")
        } header: {
            Text("Analyzing...", bundle: .module)
        }
    }

    private func progressRow(ready: Bool, label: String) -> some View {
        HStack {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ready ? .green : .secondary)
                .contentTransition(.symbolEffect(.automatic))
            Text(label)
                .font(.subheadline)
        }
    }

    // MARK: - Actions

    private func runBatch() {
        guard !isRunning, !ids.isEmpty else { return }
        isRunning = true
        Task {
            await performBatch()
            isRunning = false
        }
    }

    private func performBatch() async {
        let analyzer = TableSummaryAnalyzer()
        for id in ids {
            let entriesText = await itemController.compactText(for: id)
            guard !entriesText.isEmpty else {
                statuses[id] = .completed
                continue
            }
            statuses[id] = .analyzing
            resultModel.analysisProgress = nil
            do {
                let result = try await analyzer.analyze(
                    entriesText: entriesText,
                    resultModel: resultModel,
                    outputLanguage: selectedLanguage.englishName
                )
                applyResult(result, to: id)
                statuses[id] = .completed
            } catch {
                statuses[id] = .failed(error.localizedDescription)
            }
        }
    }

    private func applyResult(_ result: TableSummaryAnalysis, to itemId: UUID) {
        if let item = itemController.itemSync(for: itemId),
           item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editController.reset(name: result.title, itemId: itemId)
        }
        let existing = itemController.itemSync(for: itemId)?.description ?? ""
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let newDescription = trimmed.isEmpty ? result.description : "\(trimmed)\n\n\(result.description)"
        editController.reset(description: newDescription, itemId: itemId)
        editController.reset(tags: result.tags, itemId: itemId)
    }
}

#Preview(traits: .mockData) {
    BatchTextSummaryExtractionView(
        module: .generator,
        ids: [GeneratorModel.previewId],
        itemController: GeneratorRootModel.preview.itemController,
        editController: GeneratorRootModel.preview.editController
    )
}

#endif
