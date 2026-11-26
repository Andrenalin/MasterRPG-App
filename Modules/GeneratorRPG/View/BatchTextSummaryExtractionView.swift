// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import SwiftUI

private enum BatchItemStatus: Sendable {
    case pending
    case analyzing
    case completed
    /// The item has no text to analyze; nothing was changed.
    case skipped
    case failed(String)
}

/// What the batch writes into an item from a generated summary. Pure, so it is tested.
///
/// The generated description and tags *replace* the existing ones, which is what the person asks
/// for when starting the batch (the dialog says so). The name is only filled when it is empty,
/// because a name is what other items and links show. Nothing is ever erased: an empty generated
/// description or an empty tag list leaves the item as it is. The output is bounded because the
/// text it was generated from can come from an import or a shared campaign. See CODE_AUDIT_26 §6.9.
enum BatchSummaryMerge {
    static let maximumTitleLength = 100
    static let maximumDescriptionLength = 500
    static let maximumGeneratedTags = GeneratedTagRules.countRange.upperBound
    static let maximumTagLength = 40

    struct Change: Equatable {
        /// The name to write, `nil` when the item already has one.
        var name: String?
        /// The description that replaces the existing one, `nil` when it would not change.
        var description: String?
        /// The tag list that replaces the existing one, `nil` when it would not change.
        var tags: [String]?

        var isEmpty: Bool { name == nil && description == nil && tags == nil }
    }

    static func change(
        existingName: String,
        existingDescription: String,
        existingTags: [String],
        generatedTitle: String,
        generatedDescription: String,
        generatedTags: [String]
    ) -> Change {
        var name: String?
        if existingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let title = String(generatedTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumTitleLength))
            if !title.isEmpty { name = title }
        }

        var description: String?
        let generated = String(generatedDescription.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumDescriptionLength))
        if !generated.isEmpty, generated != existingDescription.trimmingCharacters(in: .whitespacesAndNewlines) {
            description = generated
        }

        var tags: [String]?
        let replacement = boundedTags(generatedTags)
        if !replacement.isEmpty, Set(replacement) != Set(existingTags) {
            tags = replacement
        }
        return Change(name: name, description: description, tags: tags)
    }

    /// The generated tags without labels (`GeneratedTagRules.cleaned`), trimmed, not empty or
    /// oversized, at most `maximumGeneratedTags`.
    static func boundedTags(_ generated: [String]) -> [String] {
        // Oversized tags go first, so one of them does not use up one of the few slots.
        GeneratedTagRules.cleaned(
            generated.filter { GeneratedTagRules.withoutLabel($0).count <= maximumTagLength }
        )
    }
}

/// Batch AI-extraction view: processes multiple items sequentially using on-device AI.
/// Apply rules (see `BatchSummaryMerge`): the name is filled when empty; the description and the tags are replaced.
public struct BatchTextSummaryExtractionView: View {

    let module: NetworkModules
    let ids: [UUID]
    let itemController: any ItemControllable
    let editController: any EditControllable

    @State private var selectedLanguage: OutputLanguage = .forCurrentLocale()
    @State private var statuses: [UUID: BatchItemStatus] = [:]
    @State private var isRunning = false
    /// What the batch changed, shown when it has run.
    @State private var changedItems = 0
    @State private var filledNames = 0
    @State private var replacedDescriptions = 0
    @State private var replacedTags = 0
    @State private var hasRun = false
    /// Owned so Cancel/dismiss stops the batch instead of it continuing to analyze and
    /// write into items after the sheet is gone. See CODE_AUDIT_18 §3.6.
    @State private var batchTask: Task<Void, Never>?
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
                    if !hasRun {
                        Section {
                            OutputLanguagePickerView(selectedLanguage: $selectedLanguage)
                        } footer: {
                            Text(
                                "Start replaces the description and the tags of the selected items with generated ones. A name is only filled in when it is empty.",
                                bundle: .module
                            )
                        }
                    }
                    Section {
                        ForEach(ids, id: \.self) { id in
                            itemRow(for: id)
                        }
                    } header: {
                        Text("^[\(ids.count) Item](inflect: true)", bundle: .module)
                    }
                    if let progress = resultModel.analysisProgress, isRunning {
                        analysisProgressSection(progress)
                    }
                    if hasRun, !isRunning {
                        Section {
                            Text(
                                "Updated \(changedItems) items: \(filledNames) names filled, \(replacedDescriptions) descriptions replaced, \(replacedTags) tags replaced.",
                                bundle: .module
                            )
                        }
                    }
                }
                .themedListSurface()
            }
            .navigationTitle(Text("Extract Information", bundle: .module))
            .toolbar {
                if hasRun, !isRunning {
                    // Finished: one OK replaces Cancel and Start, so the dialog does not look like
                    // it is back at the start.
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("OK", bundle: .module)
                        }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            batchTask?.cancel()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(Text("Cancel", bundle: .module))
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
            }
            .moduleTint(module)
        }
        #if os(macOS)
        // A macOS sheet is as large as its content, and a `List` has no intrinsic height, so
        // without a size the sheet collapsed to its title bar and hid the language picker and the
        // item list, however many items were selected.
        .frame(minWidth: 480, idealWidth: 520, minHeight: 360, idealHeight: 520)
        #endif
        .onDisappear { batchTask?.cancel() }
    }

    // MARK: - Subviews

    private func itemRow(for id: UUID) -> some View {
        let name = itemController.itemSync(for: id)?.name ?? ""
        let status = statuses[id] ?? .pending
        return HStack(spacing: 12) {
            statusIcon(for: status)
            Text(verbatim: name.isEmpty ? id.uuidString : name)
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
        case .skipped:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
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
        case .skipped:
            Text("Skipped: no text to analyze", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let error):
            Text(verbatim: error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func analysisProgressSection(_ progress: TableSummaryAnalysisProgress) -> some View {
        Section {
            if let title = progress.title {
                progressRow(
                    ready: true,
                    label: LocalizedStringResource("Title: \(title)", bundle: .module)
                )
            } else {
                progressRow(
                    ready: false,
                    label: LocalizedStringResource("Title pending", bundle: .module)
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
        } header: {
            Text("Analyzing...", bundle: .module)
        }
    }

    private func progressRow(ready: Bool, label: LocalizedStringResource) -> some View {
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
        hasRun = true
        changedItems = 0
        filledNames = 0
        replacedDescriptions = 0
        replacedTags = 0
        batchTask = Task {
            await performBatch()
            isRunning = false
        }
    }

    private func performBatch() async {
        let analyzer = TableSummaryAnalyzer()
        for id in ids {
            guard !Task.isCancelled else { return }
            let entriesText = await itemController.compactText(for: id)
            guard !entriesText.isEmpty else {
                statuses[id] = .skipped
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
                guard !Task.isCancelled else { return }
                applyResult(result, to: id)
                statuses[id] = .completed
            } catch {
                statuses[id] = .failed(error.localizedDescription)
            }
        }
    }

    private func applyResult(_ result: TableSummaryAnalysis, to itemId: UUID) {
        guard let item = itemController.itemSync(for: itemId) else { return }
        let change = BatchSummaryMerge.change(
            existingName: item.name,
            existingDescription: item.description,
            existingTags: item.tags,
            generatedTitle: result.title,
            generatedDescription: result.description,
            generatedTags: result.tags
        )
        guard !change.isEmpty else { return }
        editController.reset(name: change.name, description: change.description, tags: change.tags, itemId: itemId)
        changedItems += 1
        if change.name != nil { filledNames += 1 }
        if change.description != nil { replacedDescriptions += 1 }
        if change.tags != nil { replacedTags += 1 }
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
