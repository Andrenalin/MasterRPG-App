// @copyright André Trettin

#if !os(tvOS)

import CoreGraphics
import CoreRPG
import SwiftUI

/// Batch AI extraction for photos: analyzes the selected photos one after the other, one photo
/// being enough to start.
///
/// Apply rules: the name, description and tags follow `BatchSummaryMerge` (name filled when empty,
/// description and tags replaced), like the other batch extractions. Like the single photo
/// analysis (`PhotoSummaryAnalysisView`) it does not require the on-device model: a photo it
/// cannot analyze goes to Private Cloud Compute when the person allowed that.
@available(anyAppleOS 27.0, *)
public struct BatchPhotoSummaryExtractionView: View {

    /// Loads the photo of an item as a bounded image, `nil` when it is not available (no file,
    /// not downloaded, not decodable).
    public typealias ImageLoader = @MainActor (_ itemId: UUID) async -> CGImage?

    let module: NetworkModules
    let ids: [UUID]
    let itemController: any ItemControllable
    let editController: any EditControllable
    let loadImage: ImageLoader

    @State private var selectedLanguage: OutputLanguage = .forCurrentLocale()
    @State private var consent = PhotoCloudConsent.stored()
    @State private var statuses: [UUID: BatchItemStatus] = [:]
    @State private var isRunning = false
    /// What the batch changed, shown when it has run.
    @State private var summary = BatchPdfRunSummary()
    @State private var hasRun = false
    /// Owned so Cancel/dismiss stops the batch instead of it continuing to analyze and write into
    /// items after the sheet is gone.
    @State private var batchTask: Task<Void, Never>?

    @Environment(\.dismiss) private var dismiss

    public init(
        module: NetworkModules,
        ids: [UUID],
        itemController: any ItemControllable,
        editController: any EditControllable,
        loadImage: @escaping ImageLoader
    ) {
        self.module = module
        self.ids = ids
        self.itemController = itemController
        self.editController = editController
        self.loadImage = loadImage
    }

    public var body: some View {
        NavigationStack {
            List {
                if !hasRun {
                    Section {
                        OutputLanguagePickerView(selectedLanguage: $selectedLanguage)
                        if PhotoSummaryAnalyzer.isPrivateCloudComputeEnabled {
                            PhotoCloudConsentToggle(consent: $consent)
                        }
                    } footer: {
                        Text(
                            "Start replaces the description and the tags of the selected photos with generated ones. A name is only filled in when it is empty.",
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
                if hasRun, !isRunning {
                    Section {
                        Text(
                            "Updated ^[\(summary.changedItems) item](inflect: true): \(summary.filledNames) names filled, \(summary.replacedDescriptions) descriptions replaced, \(summary.replacedTags) tags replaced.",
                            bundle: .module
                        )
                    }
                }
            }
            .themedListSurface()
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
            skippedText: LocalizedStringResource("Skipped: photo not available", bundle: .module)
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
        let analyzer = PhotoSummaryAnalyzer()
        let consent = consent
        let language = selectedLanguage.englishName
        await BatchItemRunner.run(ids: ids, setStatus: { statuses[$0] = $1 }) { id in
            guard let image = await loadImage(id) else { return .skipped }
            let output = try await analyzer.analyze(image: image, outputLanguage: language, cloudConsent: consent)
            try Task.checkCancellation()
            applyResult(output.analysis, to: id)
            return .completed
        }
    }

    private func applyResult(_ result: PhotoSummaryAnalysis, to itemId: UUID) {
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
        summary.record(change, addedBookmarks: 0)
    }
}

@available(anyAppleOS 27.0, *)
#Preview(traits: .mockData) {
    BatchPhotoSummaryExtractionView(
        module: .photo,
        ids: [GeneratorModel.previewId],
        itemController: GeneratorRootModel.preview.itemController,
        editController: GeneratorRootModel.preview.editController,
        loadImage: { _ in nil }
    )
}

#endif
