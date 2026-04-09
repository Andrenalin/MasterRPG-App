// @copyright André Trettin

import CoreRPG
import RolePlayGameKit
import Foundation
import os.log
import SwiftUI
import CoreData
import PhotoRPG

/// Controller for saving content from the share extension using lightweight data operations
/// Mimics SaveAction behavior but uses Core Data directly without full root model infrastructure
@MainActor
final class ShareExtensionSaveController {
    init(databaseService: ShareExtensionDatabaseService) {
        self.databaseService = databaseService
    }
    
    let databaseService: ShareExtensionDatabaseService
    
    // MARK: - Save Operations
    
    /// Saves content to the specified module
    /// Replicates SaveAction logic without using root models
    func saveContent(
        to module: NetworkModules,
        name: String,
        text: String,
        images: [ImageItem]
    ) async throws {
        guard let context = databaseService.context else {
            throw ShareExtensionError.contextNotAvailable
        }
        
        // Step 1: Save photos if we have any
        var photoIds: [UUID] = []
        var photoLinks: [String] = []
        
        let photoController = PhotoDataController()
        
        for (index, image) in images.enumerated() {
            let (photoId, link) = await photoController.addNewPhoto(context: context, data: image.imageData, name: name, text: text)
            photoIds.append(photoId)
            photoLinks.append(link)
        }
        
        // Step 2: Save to the target module
        switch module {
        case .photo:
            break
            
        case .map:
            break
        case .adventure:
            break
        case .weather:
            break
        case .value:
            break
            
        default:
            throw ShareExtensionError.moduleNotSupported
        }
        
        // Step 3: Save all changes to Core Data
        try await databaseService.save()
        
        Logger.bootStrap.info("Successfully saved content to \(module.rawValue)")
    }
}
