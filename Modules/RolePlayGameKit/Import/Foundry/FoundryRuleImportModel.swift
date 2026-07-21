// @copyright André Trettin

import AdventureRPG
import CoreRPG
import Foundation
import Observation

@MainActor @Observable
final class FoundryImportModel {
    enum LoadState: Equatable {
        case notStarted
        case loading
        case preflight
        case preparingReview
        case review
        case committing
        case completed
        case failed(String)
    }

    private(set) var loadState = LoadState.notStarted
    private(set) var selectedURL: URL?
    private(set) var selectionID = UUID()
    private(set) var artifact: FoundryArtifact?
    private(set) var package: FoundryVTTImportPackage?
    private(set) var universalVTT: UniversalVTTDocument?
    private(set) var mappedImport: FoundryMappedImport?
    private(set) var reviewSession: ExternalImportReviewSession?
    private(set) var result: ExternalImportResult?
    private(set) var sourceResolution: ExternalImportSourceResolution?
    private(set) var selectedSourceScopeID: UUID?
    private(set) var archiveWarning: String?
    private(set) var commitError: String?
    private(set) var isSourceSelectionLocked = false
    var selectedCategories = FoundryImportCategory.privacySafeDefaults

    var canPrepareReview: Bool { selectedSourceScopeID != nil }

    var canChooseAnotherSource: Bool {
        switch loadState {
        case .preflight, .review, .completed, .failed:
            true
        case .notStarted, .loading, .preparingReview, .committing:
            false
        }
    }

    @ObservationIgnored private let detector: FoundryArtifactDetector
    @ObservationIgnored private let reader: FoundryVTTImportReader
    @ObservationIgnored private let universalReader: UniversalVTTReader
    @ObservationIgnored private let archiveStore: FoundryImportArchiveStore
    @ObservationIgnored private let sourceRegistry: ExternalImportSourceRegistry
    @ObservationIgnored private var sourceDescriptor: ExternalImportSourceDescriptor?

    init(
        detector: FoundryArtifactDetector = FoundryArtifactDetector(),
        reader: FoundryVTTImportReader = FoundryVTTImportReader(),
        universalReader: UniversalVTTReader = UniversalVTTReader(),
        archiveStore: FoundryImportArchiveStore = FoundryImportArchiveStore(),
        sourceRegistry: ExternalImportSourceRegistry = .shared
    ) {
        self.detector = detector
        self.reader = reader
        self.universalReader = universalReader
        self.archiveStore = archiveStore
        self.sourceRegistry = sourceRegistry
    }

    @discardableResult
    func select(url: URL) -> Bool {
        guard !isSourceSelectionLocked else { return false }
        selectedURL = url
        selectionID = UUID()
        artifact = nil
        package = nil
        universalVTT = nil
        mappedImport = nil
        reviewSession = nil
        result = nil
        sourceResolution = nil
        selectedSourceScopeID = nil
        sourceDescriptor = nil
        archiveWarning = nil
        commitError = nil
        selectedCategories = FoundryImportCategory.privacySafeDefaults
        return true
    }

    func loadSelectedArtifact() async {
        guard let requestedURL = selectedURL else { return }
        let requestedSelectionID = selectionID
        loadState = .loading
        do {
            let detector = detector
            let detectionTask = Task.detached(priority: .userInitiated) {
                let hasAccess = requestedURL.startAccessingSecurityScopedResource()
                defer { if hasAccess { requestedURL.stopAccessingSecurityScopedResource() } }
                return try detector.detect(at: requestedURL)
            }
            let detected = try await withTaskCancellationHandler {
                try await detectionTask.value
            } onCancel: {
                detectionTask.cancel()
            }
            try Task.checkCancellation()
            guard selectionID == requestedSelectionID, selectedURL == requestedURL else { return }
            artifact = detected
            switch detected.kind {
            case .universalVTT:
                universalVTT = try await universalReader.read(from: requestedURL)
                package = nil
            case .unknown:
                throw FoundryImportError.unsupportedSource
            default:
                package = try await reader.read(from: requestedURL)
                universalVTT = nil
            }
            try Task.checkCancellation()
            guard selectionID == requestedSelectionID, selectedURL == requestedURL else { return }
            let descriptor = makeSourceDescriptor(sourceURL: requestedURL)
            let archiveEntries: [ExternalImportSourceEntry]
            do {
                archiveEntries = try await archiveStore.sourceRegistryEntries()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                archiveEntries = []
            }
            let resolution = try await sourceRegistry.resolve(
                descriptor,
                fallbackEntries: archiveEntries
            )
            try Task.checkCancellation()
            guard selectionID == requestedSelectionID, selectedURL == requestedURL else { return }
            sourceDescriptor = descriptor
            sourceResolution = resolution
            switch resolution {
            case .resolved(let scopeID):
                selectedSourceScopeID = scopeID
            case .requiresSelection:
                selectedSourceScopeID = nil
            }
            loadState = .preflight
        } catch is CancellationError {
            guard selectionID == requestedSelectionID else { return }
            loadState = .notStarted
        } catch {
            guard selectionID == requestedSelectionID else { return }
            loadState = .failed(error.localizedDescription)
        }
    }

    func prepareReview(rootManager: RootManager) async {
        guard let selectedURL, sourceDescriptor != nil, let selectedSourceScopeID else {
            loadState = .failed("Choose whether this file updates an existing import or creates a new source.")
            return
        }
        let requestedSelectionID = selectionID
        loadState = .preparingReview
        commitError = nil
        do {
            try Task.checkCancellation()
            guard selectionID == requestedSelectionID, self.selectedURL == selectedURL else { return }
            if let package {
                let resourceLoader: FoundryResourceLoader = { [reader, selectedURL] resource in
                    try await reader.resourceData(for: resource, from: selectedURL).data
                }
                let mapped = try await FoundryVTTDomainMapper().map(
                    package: package,
                    sourceURL: selectedURL,
                    sourceScopeID: selectedSourceScopeID,
                    selectedCategories: selectedCategories,
                    resourceLoader: resourceLoader
                )
                let session = ExternalImportReviewSession(batch: mapped.batch)
                try await session.preflightConflicts(rootManager: rootManager)
                try Task.checkCancellation()
                guard selectionID == requestedSelectionID, self.selectedURL == selectedURL else { return }
                mappedImport = mapped
                reviewSession = session
                loadState = .review
            } else if let universalVTT {
                let resourceLoader: FoundryResourceLoader = { [universalReader, selectedURL] resource in
                    try await universalReader.resourceData(for: resource, from: selectedURL).data
                }
                let mapped = try await UniversalVTTDomainMapper().map(
                    document: universalVTT,
                    sourceURL: selectedURL,
                    sourceScopeID: selectedSourceScopeID,
                    resourceLoader: resourceLoader
                )
                let session = ExternalImportReviewSession(batch: mapped.batch)
                try await session.preflightConflicts(rootManager: rootManager)
                try Task.checkCancellation()
                guard selectionID == requestedSelectionID, self.selectedURL == selectedURL else { return }
                mappedImport = mapped
                reviewSession = session
                loadState = .review
            } else {
                loadState = .failed("The selected VTT source is no longer available.")
            }
        } catch is CancellationError {
            guard selectionID == requestedSelectionID else { return }
            loadState = .preflight
        } catch {
            guard selectionID == requestedSelectionID else { return }
            loadState = .failed(error.localizedDescription)
        }
    }

    func commit(appModel: AppModel) async {
        guard let reviewSession, let mappedImport, let selectedURL, let sourceDescriptor,
              let selectedSourceScopeID,
              let claimIntent = sourceClaimIntent(for: selectedSourceScopeID) else { return }
        let requestedSelectionID = selectionID
        guard let importToken = appModel.beginExternalImport() else {
            commitError = "Another external import is currently committing. Wait for it to finish and try again."
            return
        }
        isSourceSelectionLocked = true
        loadState = .committing
        commitError = nil
        let saveDeferral = appModel.beginSaveDeferral()
        defer {
            appModel.endSaveDeferral(saveDeferral)
            appModel.endExternalImport(importToken)
            isSourceSelectionLocked = false
        }
        do {
            let archiveEntries: [ExternalImportSourceEntry]
            do {
                archiveEntries = try await archiveStore.sourceRegistryEntries()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                archiveEntries = []
            }
            guard isCurrentSelection(requestedSelectionID, url: selectedURL) else { return }
            let claimResult = try await sourceRegistry.claim(
                claimIntent,
                descriptor: sourceDescriptor,
                fallbackEntries: archiveEntries
            )
            try Task.checkCancellation()
            guard isCurrentSelection(requestedSelectionID, url: selectedURL) else { return }
            switch claimResult {
            case .claimed(let claimedScopeID):
                guard claimedScopeID == selectedSourceScopeID else {
                    await remapReview(
                        to: claimedScopeID,
                        rootManager: appModel.root
                    )
                    return
                }
            case .requiresRemapping(let canonicalScopeID):
                await remapReview(
                    to: canonicalScopeID,
                    rootManager: appModel.root
                )
                return
            case .requiresSelection(let existing, let proposedScopeID):
                self.mappedImport = nil
                self.reviewSession = nil
                sourceResolution = .requiresSelection(
                    existing: existing,
                    proposedScopeID: proposedScopeID
                )
                self.selectedSourceScopeID = nil
                commitError = "Source identity changed while this review was open. Choose its identity and prepare the review again."
                loadState = .preflight
                return
            }

            let result = try await reviewSession.commit(
                rootManager: appModel.root,
                consolidatedSave: { [adventureRoot = appModel.adventureRoot] in
                    try await adventureRoot.saveExternalImport()
                }
            )
            guard isCurrentSelection(requestedSelectionID, url: selectedURL) else { return }
            self.result = result
            let archive = FoundryImportArchive(
                id: mappedImport.archiveID,
                sourceScopeID: selectedSourceScopeID,
                sourceFormat: sourceDescriptor.format,
                sourceSemanticKey: sourceDescriptor.semanticKey,
                sourceFileName: selectedURL.lastPathComponent,
                package: mappedImport.archivePackage,
                mappings: selectedMappings(from: mappedImport, session: reviewSession),
                warnings: mappedImport.batch.warnings
            )
            do {
                try await archiveStore.save(archive)
            } catch {
                appendArchiveWarning("The RPG data was imported, but its RuleRPG source archive could not be saved: \(error.localizedDescription)")
            }
            guard isCurrentSelection(requestedSelectionID, url: selectedURL) else { return }
            do {
                try await sourceRegistry.register(
                    scopeID: selectedSourceScopeID,
                    descriptor: sourceDescriptor
                )
            } catch {
                appendArchiveWarning("The RPG data was imported, but its source identity could not be finalized: \(error.localizedDescription)")
            }
            guard isCurrentSelection(requestedSelectionID, url: selectedURL) else { return }
            loadState = .completed
        } catch is CancellationError {
            commitError = "Import was cancelled and its changes were rolled back."
            loadState = .review
        } catch {
            commitError = error.localizedDescription
            loadState = .review
        }
    }

    func toggle(_ category: FoundryImportCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    func chooseExistingSource(scopeID: UUID) {
        guard case .requiresSelection(let existing, _) = sourceResolution,
              existing.contains(where: { $0.scopeID == scopeID }) else { return }
        selectedSourceScopeID = scopeID
    }

    func chooseNewSource() {
        guard case .requiresSelection(_, let proposedScopeID) = sourceResolution else { return }
        selectedSourceScopeID = proposedScopeID
    }

    func reportSelectionError(_ error: any Error) {
        guard !isSourceSelectionLocked else { return }
        selectedURL = nil
        selectionID = UUID()
        artifact = nil
        package = nil
        universalVTT = nil
        mappedImport = nil
        reviewSession = nil
        result = nil
        sourceResolution = nil
        selectedSourceScopeID = nil
        sourceDescriptor = nil
        loadState = .failed(error.localizedDescription)
    }

    private func makeSourceDescriptor(sourceURL: URL) -> ExternalImportSourceDescriptor {
        if let package {
            let semanticKey = package.manifest.map { "\(package.kind.rawValue):\($0.id)" }
            let instanceID = package.manifest?.rawData.value(at: "source.instanceID")?.stringValue
                .flatMap(UUID.init(uuidString:))
            let matchPolicy: ExternalImportSemanticMatchPolicy = switch package.kind {
            case .system, .module: .automatic
            case .world, .exportedDocument, .documentCollection: .requiresConfirmation
            }
            return ExternalImportSourceDescriptor(
                format: "foundry-\(package.kind.rawValue)",
                semanticKey: semanticKey,
                intrinsicScopeID: instanceID,
                sourceURL: sourceURL,
                contentHash: package.sourceSHA256,
                semanticMatchPolicy: matchPolicy
            )
        }
        return ExternalImportSourceDescriptor(
            format: "universal-vtt",
            sourceURL: sourceURL,
            contentHash: universalVTT?.sourceSHA256
        )
    }

    private func sourceClaimIntent(for scopeID: UUID) -> ExternalImportSourceClaimIntent? {
        switch sourceResolution {
        case .resolved(let resolvedScopeID):
            guard resolvedScopeID == scopeID else { return nil }
            return .resolved(scopeID: scopeID)
        case .requiresSelection(let existing, let proposedScopeID):
            if existing.contains(where: { $0.scopeID == scopeID }) {
                return .selectedExisting(scopeID: scopeID)
            }
            guard proposedScopeID == scopeID else { return nil }
            return .selectedNew(scopeID: scopeID)
        case nil:
            return nil
        }
    }

    private func isCurrentSelection(_ expectedSelectionID: UUID, url: URL) -> Bool {
        selectionID == expectedSelectionID && selectedURL == url
    }

    private func remapReview(to canonicalScopeID: UUID, rootManager: RootManager) async {
        mappedImport = nil
        reviewSession = nil
        sourceResolution = .resolved(scopeID: canonicalScopeID)
        selectedSourceScopeID = canonicalScopeID
        loadState = .preflight
        await prepareReview(rootManager: rootManager)
        if loadState == .review {
            commitError = "This source was claimed by another import while the review was open. Its IDs were remapped to the canonical source; review the changes and commit again."
        }
    }

    private func selectedMappings(
        from mappedImport: FoundryMappedImport,
        session: ExternalImportReviewSession
    ) -> [FoundryImportMapping] {
        struct Destination: Hashable {
            let module: NetworkModules
            let itemID: UUID
        }

        let selected = Set(session.batch.items.compactMap { item -> Destination? in
            guard session.decision(for: item) != .skip else { return nil }
            return Destination(module: item.module, itemID: item.id)
        })
        return mappedImport.mappings.compactMap { mapping in
            let references = mapping.references.filter {
                selected.contains(Destination(module: $0.module, itemID: $0.itemID))
            }
            guard !references.isEmpty else { return nil }
            return FoundryImportMapping(
                foundryIdentifier: mapping.foundryIdentifier,
                references: references
            )
        }
    }

    private func appendArchiveWarning(_ warning: String) {
        if let archiveWarning {
            self.archiveWarning = "\(archiveWarning)\n\n\(warning)"
        } else {
            archiveWarning = warning
        }
    }
}
