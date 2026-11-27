// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import PDFKit
import SwiftUI

/// Batch AI extraction for PDFs: analyzes the selected PDFs one after the other on device.
///
/// Apply rules: the name, description and tags follow `BatchSummaryMerge` (name filled when empty,
/// description and tags replaced). The generated sections become bookmarks through `addBookmarks`,
/// which the PDF module implements so it can skip bookmarks that already exist.
public struct BatchPdfSummaryExtractionView: View {

    /// Loads the PDF of an item, `nil` when it is not available (no file, download failed).
    public typealias DocumentLoader = @MainActor (_ itemId: UUID) async -> PDFDocument?
    /// Adds the generated sections of an item as bookmarks and returns how many were added.
    public typealias BookmarkWriter = @MainActor (_ sections: [PdfSection], _ itemId: UUID, _ document: PDFDocument) -> Int

    let module: NetworkModules
    let ids: [UUID]
    let itemController: any ItemControllable
    let editController: any EditControllable
    let loadDocument: DocumentLoader
    let addBookmarks: BookmarkWriter

    @State private var selectedLanguage: OutputLanguage = .forCurrentLocale()
    @State private var statuses: [UUID: BatchItemStatus] = [:]
    @State private var isRunning = false
    /// What the batch changed, shown when it has run.
    @State private var summary = BatchPdfRunSummary()
    @State private var hasRun = false
    /// Owned so Cancel/dismiss stops the batch instead of it continuing to analyze and write into
    /// items after the sheet is gone.
    @State private var batchTask: Task<Void, Never>?
    @State private var resultModel = PdfSummaryAnalyzerResultModel()

    @Environment(\.dismiss) private var dismiss

    public init(
        module: NetworkModules,
        ids: [UUID],
        itemController: any ItemControllable,
        editController: any EditControllable,
        loadDocument: @escaping DocumentLoader,
        addBookmarks: @escaping BookmarkWriter
    ) {
        self.module = module
        self.ids = ids
        self.itemController = itemController
        self.editController = editController
        self.loadDocument = loadDocument
        self.addBookmarks = addBookmarks
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
                                "Start replaces the description and the tags of the selected PDFs with generated ones and adds the sections as bookmarks. A name is only filled in when it is empty; existing bookmarks are kept.",
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
                        BatchPdfProgressSection(progress: progress)
                    }
                    if hasRun, !isRunning {
                        Section {
                            Text(
                                "Updated ^[\(summary.changedItems) item](inflect: true): \(summary.filledNames) names filled, \(summary.replacedDescriptions) descriptions replaced, \(summary.replacedTags) tags replaced, \(summary.addedBookmarks) bookmarks added.",
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
        // A macOS sheet is as large as its content and a `List` has no intrinsic height.
        .frame(minWidth: 480, idealWidth: 520, minHeight: 360, idealHeight: 520)
        #endif
        .onDisappear { batchTask?.cancel() }
    }

    private func itemRow(for id: UUID) -> some View {
        BatchItemStatusRow(
            name: BatchItemRunner.displayName(itemController.itemSync(for: id)?.name),
            status: statuses[id] ?? .pending,
            skippedText: LocalizedStringResource("Skipped: PDF not available", bundle: .module)
        )
    }

    // MARK: - Actions

    private func runBatch() {
        guard !isRunning, !ids.isEmpty else { return }
        isRunning = true
        hasRun = true
        summary = BatchPdfRunSummary()
        batchTask = Task {
            await performBatch()
            isRunning = false
        }
    }

    private func performBatch() async {
        let analyzer = PdfSummaryAnalyzer()
        await BatchItemRunner.run(ids: ids, setStatus: { statuses[$0] = $1 }) { id in
            resultModel.analysisProgress = nil
            resultModel.pageProgress = nil
            guard let document = await loadDocument(id) else { return .skipped }
            let result = try await analyzer.analyzeWithProgress(
                from: document,
                resultModel: resultModel,
                outputLanguage: selectedLanguage.englishName
            )
            try Task.checkCancellation()
            applyResult(result, to: id, document: document)
            return .completed
        }
    }

    private func applyResult(_ result: PdfSummaryAnalysis, to itemId: UUID, document: PDFDocument) {
        guard let item = itemController.itemSync(for: itemId) else { return }
        let change = BatchSummaryMerge.change(
            existingName: item.name,
            existingDescription: item.description,
            existingTags: item.tags,
            generatedTitle: result.title,
            generatedDescription: result.summary,
            generatedTags: result.tags
        )
        if !change.isEmpty {
            editController.reset(name: change.name, description: change.description, tags: change.tags, itemId: itemId)
        }
        let added = result.sections.isEmpty ? 0 : addBookmarks(result.sections, itemId, document)
        summary.record(change, addedBookmarks: added)
    }
}

/// The counts the PDF and photo batches show when they have run (photos add no bookmarks). Pure, so it is tested.
struct BatchPdfRunSummary: Equatable {
    var changedItems = 0
    var filledNames = 0
    var replacedDescriptions = 0
    var replacedTags = 0
    var addedBookmarks = 0

    mutating func record(_ change: BatchSummaryMerge.Change, addedBookmarks added: Int) {
        guard !change.isEmpty || added > 0 else { return }
        changedItems += 1
        if change.name != nil { filledNames += 1 }
        if change.description != nil { replacedDescriptions += 1 }
        if change.tags != nil { replacedTags += 1 }
        addedBookmarks += added
    }
}

private struct BatchPdfProgressSection: View {
    let progress: PdfSummaryAnalysisProgress

    var body: some View {
        Section {
            if let title = progress.title {
                BatchProgressRow(ready: true, label: LocalizedStringResource("Title: \(title)", bundle: .module))
            } else {
                BatchProgressRow(ready: false, label: LocalizedStringResource("Title pending", bundle: .module))
            }
            BatchProgressRow(
                ready: progress.summary != nil,
                label: progress.summary == nil
                    ? LocalizedStringResource("Description pending", bundle: .module)
                    : LocalizedStringResource("Description extracted", bundle: .module)
            )
            BatchProgressRow(
                ready: !(progress.tags?.isEmpty ?? true),
                label: LocalizedStringResource("Found \(progress.tags?.count ?? 0) tags", bundle: .module)
            )
            BatchProgressRow(
                ready: !(progress.sections?.isEmpty ?? true),
                label: LocalizedStringResource("Found \(progress.sections?.count ?? 0) sections", bundle: .module)
            )
        } header: {
            Text("Analyzing...", bundle: .module)
        }
    }
}

#Preview(traits: .mockData) {
    BatchPdfSummaryExtractionView(
        module: .pdf,
        ids: [GeneratorModel.previewId],
        itemController: GeneratorRootModel.preview.itemController,
        editController: GeneratorRootModel.preview.editController,
        loadDocument: { _ in nil },
        addBookmarks: { _, _, _ in 0 }
    )
}

#endif
