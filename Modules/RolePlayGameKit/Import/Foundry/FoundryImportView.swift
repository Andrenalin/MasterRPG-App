// @copyright André Trettin

import CoreRPG
import SwiftUI
import UniformTypeIdentifiers

struct FoundryImportView: View {
    @Environment(\.navigator) private var navigator

    let appModel: AppModel
    let isSelected: Bool
    /// Owned by the import page, so flipping the import source does not drop a prepared review.
    let model: FoundryImportModel

    @State private var showFileImporter = false
    @State private var preparationTask: Task<Void, Never>?
    @State private var commitTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                switch model.loadState {
                case .notStarted:
                    FoundryImportStartView { showFileImporter = true }
                case .loading:
                    ProgressView {
                        Text("Inspecting VTT source", bundle: .module)
                    }
                case .preflight:
                    FoundryPreflightView(model: model, prepare: startPreparation)
                case .preparingReview:
                    ProgressView {
                        Text("Preparing import review", bundle: .module)
                    }
                case .review:
                    if let mappedImport = model.mappedImport, let session = model.reviewSession {
                        FoundryExternalImportReviewView(
                            mappedImport: mappedImport,
                            session: session,
                            commitError: model.commitError
                        ) {
                            startCommit()
                        }
                    }
                case .committing:
                    FoundryImportCommitProgressView(session: model.reviewSession)
                case .finalizing:
                    FoundryImportCommitProgressView(
                        session: model.reviewSession,
                        isSavingSourceArchive: true
                    )
                case .completed:
                    FoundryImportCompletedView(
                        result: model.result,
                        archiveWarning: model.archiveWarning
                    ) {
                        navigator.dismiss()
                    }
                case .failed(let message):
                    FoundryImportFailureView(message: message) { showFileImporter = true }
                }
            }
            .navigationTitle(Text("Import VTT", bundle: .module))
            .navigationBarTitleDisplayModeAll(.inline)
            .task(id: model.selectionId) {
                await model.loadSelectedArtifact()
            }
            .task(id: appModel.pendingVTTImportUrl) {
                consumePendingVTTImportWhenAvailable()
            }
            .onChange(of: appModel.isExclusiveDataMutationActive) { _, isActive in
                guard !isActive else { return }
                consumePendingVTTImportWhenAvailable()
            }
            .onChange(of: isSelected) { _, isSelected in
                guard isSelected else { return }
                consumePendingVTTImportWhenAvailable()
            }
            .onChange(of: model.isSourceSelectionLocked) { _, isLocked in
                guard !isLocked else { return }
                consumePendingVTTImportWhenAvailable()
            }
            .interactiveDismissDisabled(
                model.loadState == .preparingReview
                    || model.loadState == .committing
                    || model.loadState == .finalizing
            )
            .onDisappear {
                preparationTask?.cancel()
                commitTask?.cancel()
            }
#if !os(tvOS)
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.data, .folder]
            ) { result in
                do {
                    model.select(url: try result.get())
                } catch is CancellationError {
                    return
                } catch let error as CocoaError where error.code == .userCancelled {
                    return
                } catch {
                    model.reportSelectionError(error)
                }
            }
#endif
            .toolbar {
                if model.loadState != .finalizing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) {
                            if model.loadState == .committing {
                                commitTask?.cancel()
                            } else if model.loadState == .preparingReview {
                                preparationTask?.cancel()
                                navigator.dismiss()
                            } else {
                                navigator.dismiss()
                            }
                        } label: {
                            Label {
                                Text("Cancel", bundle: .module)
                            } icon: {
                                Image(systemName: "xmark")
                            }
                        }
                    }
                }
                if model.canChooseAnotherSource {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label {
                                Text("Choose another source", bundle: .module)
                            } icon: {
                                Image(systemName: "doc.badge.plus")
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .themedSurface()
        }
        .themedSurface()
    }

    private func startCommit() {
        guard commitTask == nil else { return }
        commitTask = Task { @MainActor in
            await model.commit(appModel: appModel)
            commitTask = nil
        }
    }

    private func consumePendingVTTImportWhenAvailable() {
        guard isSelected,
              !appModel.isExclusiveDataMutationActive,
              let pendingUrl = appModel.pendingVTTImportUrl,
              model.select(url: pendingUrl) else { return }
        appModel.pendingVTTImportUrl = nil
    }

    private func startPreparation() {
        guard preparationTask == nil else { return }
        preparationTask = Task { @MainActor in
            await model.prepareReview(rootManager: appModel.root)
            preparationTask = nil
        }
    }
}

private struct FoundryImportStartView: View {
    let choosePackage: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Import a virtual tabletop", bundle: .module)
            } icon: {
                Image(systemName: "square.grid.3x3.square")
            }
        } description: {
            Text("Choose a Foundry system, module, world, Adventure, JSON export, database, MasterRPG bridge export, or Universal VTT map.", bundle: .module)
        } actions: {
#if !os(tvOS)
            Button(action: choosePackage) {
                Label {
                    Text("Choose VTT source", bundle: .module)
                } icon: {
                    Image(systemName: "doc.zipper")
                }
            }
            .buttonStyle(.borderedProminent)
#else
            Text("VTT file import is not available on Apple TV.", bundle: .module)
#endif
        }
    }
}

private struct FoundryImportCompletedView: View {
    let result: ExternalImportResult?
    let archiveWarning: String?
    let done: () -> Void

    var body: some View {
        List {
            Section {
                Label {
                    Text("VTT import completed", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
                if let result {
                    LabeledContent(
                        String(localized: "Inserted", bundle: .module),
                        value: result.insertedItemCount.formatted()
                    )
                    LabeledContent(
                        String(localized: "Merged", bundle: .module),
                        value: result.mergedItemCount.formatted()
                    )
                    LabeledContent(
                        String(localized: "Replaced", bundle: .module),
                        value: result.replacedItemCount.formatted()
                    )
                    LabeledContent(
                        String(localized: "Unchanged", bundle: .module),
                        value: result.unchangedItemCount.formatted()
                    )
                    LabeledContent(
                        String(localized: "Skipped", bundle: .module),
                        value: result.skippedItemCount.formatted()
                    )
                    LabeledContent(
                        String(localized: "Assets installed", bundle: .module),
                        value: result.installedAttachmentCount.formatted()
                    )
                }
            }
            if let archiveWarning {
                Section {
                    Label(archiveWarning, systemImage: "exclamationmark.triangle")
                }
            }
            Section {
                Button(String(localized: "Done", bundle: .module), action: done)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .themedListSurface()
    }
}

private struct FoundryImportFailureView: View {
    let message: String
    let chooseAnother: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("VTT import failed", bundle: .module)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        } description: {
            Text(message)
        } actions: {
            Button(action: chooseAnother) {
                Label {
                    Text("Choose another source", bundle: .module)
                } icon: {
                    Image(systemName: "doc.badge.plus")
                }
            }
        }
    }
}

#Preview("Foundry import") {
    FoundryImportView(appModel: .preview, isSelected: true, model: FoundryImportModel())
}
