// @copyright André Trettin

import CoreRPG
import CoreData
import Foundation

/// Factory for creating minimal module controllers needed by the share extension
/// Unlike AppModel, this only creates what's actually needed for the save operation
@MainActor
public final class ShareExtensionModuleFactory {
    
    private let context: NSManagedObjectContext
    
    public init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Item Creation
    
    /// Creates a new item in the specified module without loading the full RootModel
    public func createItem(
        in module: NetworkModules,
        name: String,
        content: ShareContent
    ) async throws -> UUID {
        
        let itemId = UUID()
        
        switch module {
        case .photo:
            try await createPhotoItem(id: itemId, name: name, images: content.images)
            
        case .pdf:
            try await createPdfItem(id: itemId, name: name, data: content.data)
            
        case .audio:
            try await createAudioItem(id: itemId, name: name, data: content.data)
            
        case .adventure:
            try await createAdventureItem(id: itemId, name: name, text: content.text)
            
        case .dice:
            try await createDiceItem(id: itemId, name: name, text: content.text)
            
        case .table:
            try await createTableItem(id: itemId, name: name, text: content.text)
            
        default:
            throw ShareExtensionError.moduleNotSupported
        }
        
        return itemId
    }
    
    // MARK: - Private Item Creators
    
    private func createPhotoItem(id: UUID, name: String, images: [Data]) async throws {
        try await context.perform {
            // Create Item entity
//            let item = Item(context: self.context)
//            item.id = id
//            item.name = name
//            item.typeId = NetworkModules.photo.rawValue
//            item.created = Date()
//            item.modified = Date()
//            
//            // Create Photo-specific data
//            for (index, imageData) in images.enumerated() {
//                let photo = Photo(context: self.context)
//                photo.id = UUID()
//                photo.imageData = imageData
//                photo.order = Int32(index)
//                photo.item = item
//            }
        }
    }
    
    private func createPdfItem(id: UUID, name: String, data: Data?) async throws {
        try await context.perform {
//            let item = Item(context: self.context)
//            item.id = id
//            item.name = name
//            item.typeId = NetworkModules.pdf.rawValue
//            item.created = Date()
//            item.modified = Date()
//            
//            if let data {
//                let pdfData = PdfData(context: self.context)
//                pdfData.id = UUID()
//                pdfData.data = data
//                pdfData.item = item
//            }
        }
    }
    
    private func createAudioItem(id: UUID, name: String, data: Data?) async throws {
        try await context.perform {
//            let item = Item(context: self.context)
//            item.id = id
//            item.name = name
//            item.typeId = NetworkModules.audio.rawValue
//            item.created = Date()
//            item.modified = Date()
//            
//            if let data {
//                let audioData = AudioData(context: self.context)
//                audioData.id = UUID()
//                audioData.data = data
//                audioData.item = item
//            }
        }
    }
    
    private func createAdventureItem(id: UUID, name: String, text: String?) async throws {
        try await context.perform {
//            let item = Item(context: self.context)
//            item.id = id
//            item.name = name
//            item.typeId = NetworkModules.adventure.rawValue
//            item.created = Date()
//            item.modified = Date()
//            
//            if let text, !text.isEmpty {
//                let entry = Entry(context: self.context)
//                entry.id = UUID()
//                entry.text = text
//                entry.order = 0
//                entry.created = Date()
//                entry.item = item
//            }
        }
    }
    
    private func createDiceItem(id: UUID, name: String, text: String?) async throws {
        try await context.perform {
//            let item = Item(context: self.context)
//            item.id = id
//            item.name = name
//            item.typeId = NetworkModules.dice.rawValue
//            item.created = Date()
//            item.modified = Date()
//            
//            // Create default dice configuration
//            if let text {
//                let entry = Entry(context: self.context)
//                entry.id = UUID()
//                entry.text = text
//                entry.order = 0
//                entry.created = Date()
//                entry.item = item
//            }
        }
    }
    
    private func createTableItem(id: UUID, name: String, text: String?) async throws {
        try await context.perform {
//            let item = Item(context: self.context)
//            item.id = id
//            item.name = name
//            item.typeId = NetworkModules.table.rawValue
//            item.created = Date()
//            item.modified = Date()
//            
//            if let text {
//                // Parse table data if needed
//                let entry = Entry(context: self.context)
//                entry.id = UUID()
//                entry.text = text
//                entry.order = 0
//                entry.created = Date()
//                entry.item = item
//            }
        }
    }
}

// MARK: - Share Content Model

public struct ShareContent {
    public var text: String?
    public var images: [Data] = []
    public var data: Data?
    
    public init(text: String? = nil, images: [Data] = [], data: Data? = nil) {
        self.text = text
        self.images = images
        self.data = data
    }
}
