// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import SwiftUI

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
    /// The text an item is analyzed from; `compactText(for:)` when `nil`. Character adds its
    /// portrait's description and tags this way, Map its map photo's.
    let entriesText: (@MainActor (UUID) async -> String)?

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
        editController: any EditControllable,
        entriesText: (@MainActor (UUID) async -> String)? = nil
    ) {
        self.module = module
        self.ids = ids
        self.itemController = itemController
        self.editController = editController
        self.entriesText = entriesText
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
                                "Updated ^[\(changedItems) item](inflect: true): \(filledNames) names filled, \(replacedDescriptions) descriptions replaced, \(replacedTags) tags replaced.",
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
        BatchItemStatusRow(
            name: BatchItemRunner.displayName(itemController.itemSync(for: id)?.name),
            status: statuses[id] ?? .pending,
            skippedText: LocalizedStringResource("Skipped: no text to analyze", bundle: .module)
        )
    }

    @ViewBuilder
    private func analysisProgressSection(_ progress: TableSummaryAnalysisProgress) -> some View {
        Section {
            if let title = progress.title {
                BatchProgressRow(
                    ready: true,
                    label: LocalizedStringResource("Title: \(title)", bundle: .module)
                )
            } else {
                BatchProgressRow(
                    ready: false,
                    label: LocalizedStringResource("Title pending", bundle: .module)
                )
            }
            BatchProgressRow(
                ready: progress.description != nil,
                label: progress.description == nil
                    ? LocalizedStringResource("Description pending", bundle: .module)
                    : LocalizedStringResource("Description extracted", bundle: .module)
            )
            BatchProgressRow(
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
        let analyzer = TextSummaryAnalyzers.analyzer(for: module)
        await BatchItemRunner.run(ids: ids, setStatus: { statuses[$0] = $1 }) { id in
            resultModel.analysisProgress = nil
            let entriesText = if let entriesText = self.entriesText {
                await entriesText(id)
            } else {
                await itemController.compactText(for: id)
            }
            guard !entriesText.isEmpty else { return .skipped }
            let result = try await analyzer.analyze(
                entriesText: entriesText,
                itemName: itemController.itemSync(for: id)?.name ?? "",
                resultModel: resultModel,
                outputLanguage: selectedLanguage.englishName
            )
            try Task.checkCancellation()
            applyResult(result, to: id)
            return .completed
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
        editController.reset(name: change.name, description: change.description, tags: change.tags, itemId: itemId, forceSave: true)
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
