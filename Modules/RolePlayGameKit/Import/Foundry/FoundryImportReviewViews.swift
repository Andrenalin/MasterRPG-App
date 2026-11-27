// @copyright André Trettin

import CoreRPG
import SwiftUI
import UniformTypeIdentifiers

// The preflight and review subviews, split out of FoundryImportView.swift. See CODE_AUDIT_29 §9.9.

struct FoundryPreflightView: View {
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
                        model.chooseExistingSource(scopeId: entry.scopeId)
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
                                Text(entry.scopeId.uuidString)
                                    .font(.caption2)
                                    .monospaced()
                                    .foregroundStyle(.tertiary)
                                Text(entry.lastImportedAt, format: .dateTime)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.selectedSourceScopeId == entry.scopeId {
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
                        if case .requiresSelection(_, let proposedScopeId) = model.sourceResolution,
                           model.selectedSourceScopeId == proposedScopeId {
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
            if let url = model.selectedUrl {
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
                    Text(package.manifest?.title ?? model.selectedUrl?.lastPathComponent ?? "Foundry VTT")
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

struct FoundryExternalImportReviewView: View {
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
                    // Keyed by position: Foundry imports often repeat the same warning.
                    ForEach(mappedImport.batch.warnings.prefix(20).enumerated(), id: \.offset) { _, warning in
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

            // Grouped once per body. The filter ran over every batch item once per module,
            // about thirteen passes over a large package on each state change.
            // See CODE_AUDIT_21 §7.10.
            let itemsByModule = Dictionary(grouping: mappedImport.batch.items.filter { !$0.isAuxiliary }, by: \.module)
            ForEach(NetworkModules.allCases, id: \.self) { module in
                let moduleItems = itemsByModule[module] ?? []
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

private extension FoundryArtifactKind {
    var title: String {
        switch self {
        case .systemPackage: String(localized: "Foundry system package", bundle: .module)
        case .modulePackage: String(localized: "Foundry module package", bundle: .module)
        case .worldPackage: String(localized: "Foundry world package", bundle: .module)
        case .exportedDocument: String(localized: "Foundry JSON document", bundle: .module)
        case .documentDatabase: String(localized: "Foundry document database", bundle: .module)
        case .universalVTT: String(localized: "Universal VTT map", bundle: .module)
        case .masterRPGBridge: String(localized: "MasterRPG Foundry bridge", bundle: .module)
        case .unknown: String(localized: "Unknown", bundle: .module)
        }
    }
}

private extension ExternalImportDecision {
    var title: String {
        switch self {
        case .skip: String(localized: "Skip", bundle: .module)
        case .merge: String(localized: "Merge", bundle: .module)
        case .replace: String(localized: "Replace", bundle: .module)
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
