// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import SwiftUI
import CoreData
import PhotoRPG
import WeatherRPG
import CharacterRPG
import MapRPG
import AdventureRPG

/// Controller for saving content from the share extension using lightweight data operations
/// Mimics SaveAction behavior but uses Core Data directly without full root model infrastructure
@MainActor
public final class ShareExtensionSaveController {
    public init(databaseService: ShareExtensionDatabaseService) {
        self.databaseService = databaseService
    }

    public let databaseService: ShareExtensionDatabaseService

    // MARK: - Save Operations

    /// Saves content to the specified module
    /// Replicates SaveAction logic without using root models
    ///
    /// `images` holds the raw data of each shared image. The class lives in the module, not in the
    /// extension, so the save path can be unit-tested with a temporary store.
    /// See CODE_AUDIT_TestGaps §6.3.
    public func saveContent(
        to module: NetworkModules,
        name: String,
        text: String,
        images: [Data]
    ) async throws {
        guard let context = databaseService.context else {
            throw ShareExtensionError.contextNotAvailable
        }

        guard ShareExtensionError.canSave(to: module, imageCount: images.count) else {
            throw ShareExtensionError.noPhotoToSave
        }
        let photoController = ShareImportPhotoController()
        // The photo files are written to iCloud Drive before their items are saved. When
        // anything after that fails, they are removed again and the unsaved rows are dropped:
        // the files stayed behind with no item, and a second try saved rows for them.
        // See CODE_AUDIT_21 §5.27.
        var writtenFiles: [FileUrl] = []
        do {
            try await saveContent(
                to: module,
                name: name,
                text: text,
                images: images,
                context: context,
                photoController: photoController,
                writtenFiles: &writtenFiles
            )
        } catch {
            for file in writtenFiles {
                await photoController.removeFile(file)
            }
            await context.perform { context.rollback() }
            throw error
        }
    }

    private func saveContent(
        to module: NetworkModules,
        name: String,
        text: String,
        images: [Data],
        context: NSManagedObjectContext,
        photoController: ShareImportPhotoController,
        writtenFiles: inout [FileUrl]
    ) async throws {
        // Step 1: Save photos if we have any
        var photoIds: [UUID] = []
        var photoLinks: [String] = []

        for image in images {
            let added = try await photoController.addNewPhotoFile(context: context, data: image, name: name, text: text)
            writtenFiles.append(added.fileUrl)
            photoIds.append(added.photoId)
            photoLinks.append(added.link)
        }

        // Step 2: Save to the target module
        switch module {
        case .photo:
            break

        case .map:
            let mapDataController = MapDataController()
            await mapDataController.addNewMap(context: context, name: name, text: text, photoId: photoIds.first)

        case .adventure:
            let adventureDataController = AdventureDataController()
            await adventureDataController.addNewAdventure(context: context, name: name, text: text, photoIds: photoIds, photoLinks: photoLinks)

        case .weather:
            let weatherDataController = WeatherDataController()
            await weatherDataController.addNewWeather(context: context, name: name, text: text, photoId: photoIds.first)

        case .value:
            let characterDataController = CharacterDataController()
            await characterDataController.addNewValue(context: context, name: name, text: text, photoIds: photoIds)

        default:
            throw ShareExtensionError.moduleNotSupported
        }

        // Step 3: Save all changes to Core Data
        try await databaseService.save()

        Logger.bootStrap.info("Successfully saved content to \(module.rawValue)")
    }
}
