// @copyright André Trettin

import CoreRPG
import Foundation
import Synchronization
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration) {
        self.config = config

        self.itemDataModel = ItemDataModel()
        self.collectionCategory = config.collectionCategory
        
        let fileUrlDataController = FileUrlDataController(config: config)
        self.cacheController = CacheController(fileUrlDataController: fileUrlDataController)
        self.fileUrlDataController = fileUrlDataController
    }

    var cacheController: CacheController?
    let config: ModuleConfigurable
    let collectionCategory: ItemListCategory
    var fileUrlDataController: FileUrlDataController?
    let itemDataModel: ItemDataModel
}

extension ItemController: ItemControllable {
    typealias Model = PhotoModel

    var cacheControllable: ImageCacheControllable? { cacheController }
    @MainActor var dataControllable: (any DataPersistenceControllable)? { itemDataModel.dataController }
}

extension ItemController {
#if os(macOS)
    static let importImageTypes = AKImage.imageTypes.compactMap { UTType($0) }

    /// Imports image data dropped from an external device (e.g. Image Capture, Photos, or a
    /// Finder window backed by a camera/SD card/external drive) via drag-and-drop — the Mac-only
    /// counterpart to the iOS Camera/Photos-library pickers `InlineImporterView` already offers.
    ///
    /// Modernized from a completion-handler `loadDataRepresentation` callback (wrapped in a
    /// hand-rolled `Task { @MainActor in ... }` hop) to `async throws`, matching the idiom in
    /// `Sources/RPGShare/ItemProviderImporter.swift`. See CODE_AUDIT §4.2.
    static func importImageFromProviders(_ itemProviders: [NSItemProvider]) async throws -> Data? {
        guard let provider = itemProviders.first else { return nil }
        for type in importImageTypes {
            let typeIdentifier = type.identifier
            guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else { continue }
            // `loadDataRepresentation` has no async overload (it returns a `Progress`); the load
            // is cancelled through that progress when the calling task is. See CODE_AUDIT_18 §4.3.
            let progressBox = ProgressBox()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let progress = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: data)
                        }
                    }
                    progressBox.store(progress)
                }
            } onCancel: {
                progressBox.cancel()
            }
        }
        return nil
    }

    /// Holds the load's `Progress` so the cancellation handler can reach it. A cancel that
    /// arrives before the progress is stored is remembered and applied on `store`, instead of
    /// being lost. See CODE_AUDIT_19 §3.15.
    private final class ProgressBox: Sendable {
        private struct State {
            var progress: Progress?
            var isCancelled = false
        }

        private let storage = Mutex(State())

        func store(_ progress: Progress) {
            let cancelNow = storage.withLock { state -> Bool in
                state.progress = progress
                return state.isCancelled
            }
            if cancelNow { progress.cancel() }
        }

        func cancel() {
            let progress = storage.withLock { state -> Progress? in
                state.isCancelled = true
                return state.progress
            }
            progress?.cancel()
        }
    }
#endif
}
