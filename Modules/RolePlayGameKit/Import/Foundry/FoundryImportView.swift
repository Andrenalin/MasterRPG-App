// @copyright André Trettin

import CoreRPG
import SwiftUI
import UniformTypeIdentifiers

struct FoundryImportView: View {
    @Environment(\.navigator) private var navigator

    let appModel: AppModel
    let isSelected: Bool

    @State private var model = FoundryImportModel()
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
            .task(id: model.selectionID) {
                await model.loadSelectedArtifact()
            }
            .task(id: appModel.pendingVTTImportURL) {
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
              let pendingURL = appModel.pendingVTTImportURL,
              model.select(url: pendingURL) else { return }
        appModel.pendingVTTImportURL = nil
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

private struct FoundryPreflightView: View {
    @Bindable var model: FoundryImportModel
    let prepare: () -> Void

    var body: some View {
        List {
            FoundrySourceSummarySection(model: model)
            FoundrySourceIdentitySection(model: model)

            if model.package != nil {
                Section {
                    ForEach(FoundryImportCategory.allCases) { category in
                        Toggle(isOn: Binding(
                            get: { model.selectedCategories.contains(category) },
                            set: { _ in model.toggle(category) }
                        )) {
                            VStack(alignment: .leading) {
                                Text(category.title)
                                if category == .chat {
                                    Text("May contain private, blind, or whispered messages. When disabled, chat is also excluded from the RuleRPG archive.", bundle: .module)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if category == .users {
                                    Text("When disabled, User documents and common ownership identifiers are removed from the RuleRPG archive.", bundle: .module)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Content", bundle: .module)
                }
            }

            FoundryImportReportSection(model: model)

            Section {
                Text("Foundry rules are imported into the Rules library as editable entries, while original fields remain in a versioned source archive. Disabled chat, users, and common ownership identifiers are removed for privacy.", bundle: .module)
                    .foregroundStyle(.secondary)
            } header: {
                Text("RuleRPG", bundle: .module)
            }

            Section {
                Button {
                    prepare()
                } label: {
                    Label {
                        Text("Prepare import review", bundle: .module)
                    } icon: {
                        Image(systemName: "checklist")
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!model.canPrepareReview)

                if !model.canPrepareReview {
                    Text("Choose a source identity above before preparing the review.", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .themedListSurface()
    }

}

private struct FoundrySourceIdentitySection: View {
    @Bindable var model: FoundryImportModel

    var body: some View {
        if case .requiresSelection(let existing, _) = model.sourceResolution {
            Section {
                Text("This looks like a copied or moved source. Choose whether to update a previous import or keep it separate.", bundle: .module)
                    .foregroundStyle(.secondary)
                ForEach(existing) { entry in
                    Button {
                        model.chooseExistingSource(scopeID: entry.scopeID)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Update existing import", bundle: .module)
                                Text(entry.lastKnownPathAlias)
                                    .font(.caption)
                                    .monospaced()
                                    .foregroundStyle(.secondary)
                                if let semanticKey = entry.semanticKey {
                                    Text(semanticKey)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(entry.scopeID.uuidString)
                                    .font(.caption2)
                                    .monospaced()
                                    .foregroundStyle(.tertiary)
                                Text(entry.lastImportedAt, format: .dateTime)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.selectedSourceScopeID == entry.scopeID {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                    }
                }
                Button {
                    model.chooseNewSource()
                } label: {
                    HStack {
                        Text("Import as a new source", bundle: .module)
                        Spacer()
                        if case .requiresSelection(_, let proposedScopeID) = model.sourceResolution,
                           model.selectedSourceScopeID == proposedScopeID {
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                }
            } header: {
                Text("Source identity", bundle: .module)
            }
        }
    }
}

private struct FoundrySourceSummarySection: View {
    let model: FoundryImportModel

    var body: some View {
        Section {
            if let url = model.selectedURL {
                LabeledContent {
                    Text(url.lastPathComponent)
                } label: {
                    Text("Source", bundle: .module)
                }
            }
            if let artifact = model.artifact {
                LabeledContent {
                    Text(artifact.kind.title)
                } label: {
                    Text("Format", bundle: .module)
                }
            }
            if let package = model.package {
                LabeledContent {
                    Text(package.manifest?.title ?? model.selectedURL?.lastPathComponent ?? "Foundry VTT")
                } label: {
                    Text("Package", bundle: .module)
                }
                LabeledContent {
                    Text(package.statistics.topLevelDocumentCount + package.statistics.embeddedDocumentCount, format: .number)
                } label: {
                    Text("Documents", bundle: .module)
                }
                LabeledContent {
                    Text(package.resources.count, format: .number)
                } label: {
                    Text("Asset references", bundle: .module)
                }
                if let rulePackage = package.rulePackage {
                    LabeledContent {
                        Text(rulePackage.ruleCount, format: .number)
                    } label: {
                        Text("Normalized rules", bundle: .module)
                    }
                }
            } else if let universalVTT = model.universalVTT {
                LabeledContent {
                    Text(universalVTT.lineOfSight.count + universalVTT.objectsLineOfSight.count, format: .number)
                } label: {
                    Text("Wall paths", bundle: .module)
                }
                LabeledContent {
                    Text(universalVTT.portals.count, format: .number)
                } label: {
                    Text("Portals", bundle: .module)
                }
                LabeledContent {
                    Text(universalVTT.lights.count, format: .number)
                } label: {
                    Text("Lights retained", bundle: .module)
                }
            }
        } header: {
            Text("Preflight", bundle: .module)
        }
    }
}

private struct FoundryImportReportSection: View {
    let model: FoundryImportModel

    var body: some View {
        Section {
            Label {
                Text("Only import content and assets you are licensed to use or redistribute.", bundle: .module)
            } icon: {
                Image(systemName: "checkmark.shield")
            }
            if let package = model.package {
                if model.unresolvedResourceCount > 0 {
                    Label {
                        Text(
                            "\(model.unresolvedResourceCount.formatted()) assets are remote, installation-relative, or missing and will not be fetched automatically.",
                            bundle: .module
                        )
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                }
                ForEach(model.licenseDocuments) { document in
#if os(tvOS)
                    VStack(alignment: .leading) {
                        Text(document.path)
                            .bold()
                        Text(document.content)
                    }
#else
                    DisclosureGroup(document.path) {
                        Text(document.content)
                            .textSelection(.enabled)
                    }
#endif
                }
                ForEach(package.diagnostics) { diagnostic in
                    Label {
                        Text(diagnostic.message)
                    } icon: {
                        Image(systemName: diagnostic.severity == .warning ? "exclamationmark.triangle" : "info.circle")
                    }
                }
            }
        } header: {
            Text("Safety and licensing", bundle: .module)
        }
    }
}

private struct FoundryExternalImportReviewView: View {
    let mappedImport: FoundryMappedImport
    let session: ExternalImportReviewSession
    let commitError: String?
    let commit: () -> Void
    @State private var showReplaceAllConfirmation = false

    var body: some View {
        List {
            Section {
                LabeledContent {
                    Text(mappedImport.batch.items.count, format: .number)
                } label: {
                    Text("Projected items", bundle: .module)
                }
                LabeledContent {
                    Text(mappedImport.rawOnlyDocumentCount, format: .number)
                } label: {
                    Text("Raw-only records", bundle: .module)
                }
                LabeledContent {
                    Text(mappedImport.missingResources.count, format: .number)
                } label: {
                    Text("Unavailable assets", bundle: .module)
                }
                LabeledContent {
                    Text(mappedImport.unsupportedResources.count, format: .number)
                } label: {
                    Text("Unprojected asset types", bundle: .module)
                }
                Menu {
                    ForEach(ExternalImportDecision.allCases, id: \.self) { decision in
                        Button(decision.title) {
                            if decision == .replace {
                                showReplaceAllConfirmation = true
                            } else {
                                session.setDecisionForAll(decision)
                            }
                        }
                    }
                } label: {
                    Label {
                        Text("Set all decisions", bundle: .module)
                    } icon: {
                        Image(systemName: "checklist")
                    }
                }
            } header: {
                Text("Review", bundle: .module)
            }

            if !mappedImport.batch.warnings.isEmpty {
                Section {
                    ForEach(mappedImport.batch.warnings.prefix(20), id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                    }
                    if mappedImport.batch.warnings.count > 20 {
                        Text("\((mappedImport.batch.warnings.count - 20).formatted()) additional warnings are retained in the RuleRPG archive.", bundle: .module)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Import warnings", bundle: .module)
                }
            }

            ForEach(NetworkModules.allCases, id: \.self) { module in
                let moduleItems = mappedImport.batch.items.filter {
                    $0.module == module && !$0.isAuxiliary
                }
                if !moduleItems.isEmpty {
                    Section {
                        ForEach(moduleItems) { item in
                            FoundryImportDecisionRow(item: item, session: session)
                        }
                    } header: {
                        Label(module.title, systemImage: module.icon)
                    }
                }
            }

            if let commitError {
                Section {
                    Label(commitError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(action: commit) {
                    Label {
                        Text("Import selected items", bundle: .module)
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
        .themedListSurface()
        .alert(
            Text("Replace every existing item?", bundle: .module),
            isPresented: $showReplaceAllConfirmation
        ) {
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
            Button(
                String(localized: "Replace all", bundle: .module),
                role: .destructive
            ) {
                session.setDecisionForAll(.replace)
            }
        } message: {
            Text("Replace discards local fields for every matching imported item. This does not delete items outside this partial import.", bundle: .module)
        }
    }
}

private struct FoundryImportDecisionRow: View {
    let item: ExternalImportBatchItem
    let session: ExternalImportReviewSession

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.name)
                if let status = session.conflictStatus(for: item) {
                    Text(status.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !item.warnings.isEmpty {
                    Text(item.warnings.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker(String(localized: "Decision", bundle: .module), selection: Binding(
                get: { session.decision(for: item) },
                set: { session.setDecision($0, for: item) }
            )) {
                ForEach(ExternalImportDecision.allCases, id: \.self) { decision in
                    Text(decision.title).tag(decision)
                }
            }
            .labelsHidden()
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

private extension FoundryArtifactKind {
    var title: String {
        switch self {
        case .systemPackage: "Foundry system package"
        case .modulePackage: "Foundry module package"
        case .worldPackage: "Foundry world package"
        case .exportedDocument: "Foundry JSON document"
        case .documentDatabase: "Foundry document database"
        case .universalVTT: "Universal VTT map"
        case .masterRPGBridge: "MasterRPG Foundry bridge"
        case .unknown: "Unknown"
        }
    }
}

private extension ExternalImportDecision {
    var title: String {
        switch self {
        case .skip: "Skip"
        case .merge: "Merge"
        case .replace: "Replace"
        }
    }
}

private extension ExternalImportConflictStatus {
    var title: String {
        switch self {
        case .new: String(localized: "New", bundle: .module)
        case .unchanged: String(localized: "Already up to date", bundle: .module)
        case .changed: String(localized: "Changes existing item", bundle: .module)
        }
    }
}

#Preview("Foundry import") {
    FoundryImportView(appModel: .preview, isSelected: true)
}
