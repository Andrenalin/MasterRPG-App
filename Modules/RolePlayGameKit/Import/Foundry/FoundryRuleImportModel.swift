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
        case finalizing
        case completed
        case failed(String)
    }

    private(set) var loadState = LoadState.notStarted
    private(set) var selectedUrl: URL?
    private(set) var selectionId = UUID()
    private(set) var artifact: FoundryArtifact?
    private(set) var package: FoundryVTTImportPackage? {
        didSet {
            licenseDocuments = package?.textResources.filter(\.isLicenseDocument) ?? []
            unresolvedResourceCount = package?.resources.count { $0.location != .packaged } ?? 0
        }
    }
    /// The package's license documents, filtered once when the package changes instead of on every
    /// view body evaluation. See CODE_AUDIT_17 §8.5.
    private(set) var licenseDocuments: [FoundryPackageTextResource] = []
    private(set) var unresolvedResourceCount = 0
    private(set) var universalVTT: UniversalVTTDocument?
    private(set) var mappedImport: FoundryMappedImport?
    private(set) var reviewSession: ExternalImportReviewSession?
    private(set) var result: ExternalImportResult?
    private(set) var sourceResolution: ExternalImportSourceResolution?
    private(set) var selectedSourceScopeId: UUID?
    private(set) var archiveWarning: String?
    private(set) var commitError: String?
    private(set) var isSourceSelectionLocked = false
    var selectedCategories = FoundryImportCategory.privacySafeDefaults

    var canPrepareReview: Bool { selectedSourceScopeId != nil }

    /// True while the import reads, prepares or writes; the import source picker stays put then, as
    /// leaving the Foundry page cancels its tasks. See CODE_AUDIT_26 §8.30.
    var isWorking: Bool {
        switch loadState {
        case .loading, .preparingReview, .committing, .finalizing:
            true
        case .notStarted, .preflight, .review, .completed, .failed:
            false
        }
    }

    var canChooseAnotherSource: Bool {
        switch loadState {
        case .preflight, .review, .completed, .failed:
            true
        case .notStarted, .loading, .preparingReview, .committing, .finalizing:
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
        selectedUrl = url
        selectionId = UUID()
        artifact = nil
        package = nil
        universalVTT = nil
        mappedImport = nil
        reviewSession = nil
        result = nil
        sourceResolution = nil
        selectedSourceScopeId = nil
        sourceDescriptor = nil
        archiveWarning = nil
        commitError = nil
        selectedCategories = FoundryImportCategory.privacySafeDefaults
        return true
    }

    func loadSelectedArtifact() async {
        guard let requestedUrl = selectedUrl else { return }
        let requestedSelectionId = selectionId
        loadState = .loading
        do {
            let detector = detector
            // Structured and scope-balanced; cancellation propagates. See CODE_AUDIT_18 §4.4.
            let detected = try await requestedUrl.withSecurityScopedAccess { url in
                try detector.detect(at: url)
            }
            try Task.checkCancellation()
            guard selectionId == requestedSelectionId, selectedUrl == requestedUrl else { return }
            artifact = detected
            switch detected.kind {
            case .universalVTT:
                universalVTT = try await universalReader.read(from: requestedUrl)
                package = nil
            case .unknown:
                throw FoundryImportError.unsupportedSource
            default:
                package = try await reader.read(from: requestedUrl)
                universalVTT = nil
            }
            try Task.checkCancellation()
            guard selectionId == requestedSelectionId, selectedUrl == requestedUrl else { return }
            let descriptor = makeSourceDescriptor(sourceURL: requestedUrl)
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
            guard selectionId == requestedSelectionId, selectedUrl == requestedUrl else { return }
            sourceDescriptor = descriptor
            sourceResolution = resolution
            switch resolution {
            case .resolved(let scopeID):
                selectedSourceScopeId = scopeID
            case .requiresSelection:
                selectedSourceScopeId = nil
            }
            loadState = .preflight
        } catch is CancellationError {
            guard selectionId == requestedSelectionId else { return }
            loadState = .notStarted
        } catch {
            guard selectionId == requestedSelectionId else { return }
            loadState = .failed(error.localizedDescription)
        }
    }

    func prepareReview(rootManager: RootManager) async {
        guard let selectedUrl, sourceDescriptor != nil, let selectedSourceScopeId else {
            loadState = .failed(String(localized: "Choose whether this file updates an existing import or creates a new source.", bundle: .module))
            return
        }
        let requestedSelectionId = selectionId
        loadState = .preparingReview
        commitError = nil
        do {
            try Task.checkCancellation()
            guard selectionId == requestedSelectionId, self.selectedUrl == selectedUrl else { return }
            if let package {
                let resourceLoader: FoundryResourceLoader = { [reader, selectedUrl] resource in
                    try await reader.resourceData(for: resource, from: selectedUrl).data
                }
                let mapped = try await FoundryVTTDomainMapper().map(
                    package: package,
                    sourceURL: selectedUrl,
                    sourceScopeID: selectedSourceScopeId,
                    selectedCategories: selectedCategories,
                    resourceLoader: resourceLoader
                )
                let session = ExternalImportReviewSession(batch: mapped.batch)
                try await session.preflightConflicts(rootManager: rootManager)
                try Task.checkCancellation()
                guard selectionId == requestedSelectionId, self.selectedUrl == selectedUrl else { return }
                mappedImport = mapped
                reviewSession = session
                loadState = .review
            } else if let universalVTT {
                let resourceLoader: FoundryResourceLoader = { [universalReader, selectedUrl] resource in
                    try await universalReader.resourceData(for: resource, from: selectedUrl).data
                }
                let mapped = try await UniversalVTTDomainMapper().map(
                    document: universalVTT,
                    sourceURL: selectedUrl,
                    sourceScopeID: selectedSourceScopeId,
                    resourceLoader: resourceLoader
                )
                let session = ExternalImportReviewSession(batch: mapped.batch)
                try await session.preflightConflicts(rootManager: rootManager)
                try Task.checkCancellation()
                guard selectionId == requestedSelectionId, self.selectedUrl == selectedUrl else { return }
                mappedImport = mapped
                reviewSession = session
                loadState = .review
            } else {
                loadState = .failed(String(localized: "The selected VTT source is no longer available.", bundle: .module))
            }
        } catch is CancellationError {
            guard selectionId == requestedSelectionId else { return }
            loadState = .preflight
        } catch {
            guard selectionId == requestedSelectionId else { return }
            loadState = .failed(error.localizedDescription)
        }
    }

    func commit(appModel: AppModel) async {
        guard let reviewSession, let mappedImport, let selectedUrl, let sourceDescriptor,
              let selectedSourceScopeId,
              let claimIntent = sourceClaimIntent(for: selectedSourceScopeId) else { return }
        let requestedSelectionId = selectionId
        guard let importToken = appModel.beginExternalImport() else {
            commitError = String(localized: "Another external import is currently committing. Wait for it to finish and try again.", bundle: .module)
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
            guard isCurrentSelection(requestedSelectionId, url: selectedUrl) else { return }
            let claimResult = try await sourceRegistry.claim(
                claimIntent,
                descriptor: sourceDescriptor,
                fallbackEntries: archiveEntries
            )
            try Task.checkCancellation()
            guard isCurrentSelection(requestedSelectionId, url: selectedUrl) else { return }
            switch claimResult {
            case .claimed(let claimedScopeID):
                guard claimedScopeID == selectedSourceScopeId else {
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
                self.selectedSourceScopeId = nil
                commitError = String(localized: "Source identity changed while this review was open. Choose its identity and prepare the review again.", bundle: .module)
                loadState = .preflight
                return
            }

            let result = try await reviewSession.commit(
                rootManager: appModel.root,
                consolidatedSave: { [adventureRoot = appModel.adventureRoot] in
                    try await adventureRoot.saveExternalImport()
                }
            )
            // The assets were read for the commit; do not keep them until the next preflight.
            await reader.releaseCachedSources()
            guard isCurrentSelection(requestedSelectionId, url: selectedUrl) else { return }
            self.result = result
            loadState = .finalizing
            let archive = FoundryImportArchive(
                id: mappedImport.archiveID,
                sourceScopeID: selectedSourceScopeId,
                sourceFormat: sourceDescriptor.format,
                sourceSemanticKey: sourceDescriptor.semanticKey,
                sourceFileName: selectedUrl.lastPathComponent,
                package: mappedImport.archivePackage,
                mappings: selectedMappings(from: mappedImport, session: reviewSession),
                warnings: mappedImport.batch.warnings
            )
            do {
                try await archiveStore.save(archive)
            } catch {
                appendArchiveWarning(String(localized: "The RPG data was imported, but its RuleRPG source archive could not be saved: \(error.localizedDescription)", bundle: .module))
            }
            guard isCurrentSelection(requestedSelectionId, url: selectedUrl) else { return }
            do {
                try await sourceRegistry.register(
                    scopeID: selectedSourceScopeId,
                    descriptor: sourceDescriptor
                )
            } catch {
                appendArchiveWarning(String(localized: "The RPG data was imported, but its source identity could not be finalized: \(error.localizedDescription)", bundle: .module))
            }
            guard isCurrentSelection(requestedSelectionId, url: selectedUrl) else { return }
            loadState = .completed
        } catch is CancellationError {
            commitError = String(localized: "Import was cancelled and its changes were rolled back.", bundle: .module)
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
        selectedSourceScopeId = scopeID
    }

    func chooseNewSource() {
        guard case .requiresSelection(_, let proposedScopeID) = sourceResolution else { return }
        selectedSourceScopeId = proposedScopeID
    }

    func reportSelectionError(_ error: any Error) {
        guard !isSourceSelectionLocked else { return }
        selectedUrl = nil
        selectionId = UUID()
        artifact = nil
        package = nil
        universalVTT = nil
        mappedImport = nil
        reviewSession = nil
        result = nil
        sourceResolution = nil
        selectedSourceScopeId = nil
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
        selectionId == expectedSelectionID && selectedUrl == url
    }

    private func remapReview(to canonicalScopeID: UUID, rootManager: RootManager) async {
        mappedImport = nil
        reviewSession = nil
        sourceResolution = .resolved(scopeID: canonicalScopeID)
        selectedSourceScopeId = canonicalScopeID
        loadState = .preflight
        await prepareReview(rootManager: rootManager)
        if loadState == .review {
            commitError = String(localized: "This source was claimed by another import while the review was open. Its IDs were remapped to the canonical source; review the changes and commit again.", bundle: .module)
        }
    }

    private func selectedMappings(
        from mappedImport: FoundryMappedImport,
        session: ExternalImportReviewSession
    ) -> [FoundryImportMapping] {
        struct Destination: Hashable {
            let module: NetworkModules
            let itemId: UUID
        }

        let selected = Set(session.batch.items.compactMap { item -> Destination? in
            guard session.decision(for: item) != .skip else { return nil }
            return Destination(module: item.module, itemId: item.id)
        })
        return mappedImport.mappings.compactMap { mapping in
            let references = mapping.references.filter {
                selected.contains(Destination(module: $0.module, itemId: $0.itemId))
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

extension FoundryPackageTextResource {
    var isLicenseDocument: Bool {
        // Whole words of the last path component ("OGL.txt", "LICENSE-2.0.md"), not a substring:
        // "ogl" also sits in "Goblin" and "Mogli". See CODE_AUDIT_26 §5.127.
        let name = path.split(separator: "/").last.map(String.init) ?? path
        let words = name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        let licenseWords: Set = ["license", "licenses", "licence", "copying", "ogl", "notice"]
        return words.contains { licenseWords.contains($0) }
    }
}

