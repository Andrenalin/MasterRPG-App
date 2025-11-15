// @copyright André Trettin

import AndrenalinKit
import Foundation
import SwiftData
import SwiftUI

@Model 
public final class GeneratorDataModel {
    public init(itemId: UUID = UUID(), referenceId: UUID? = nil) {
        self.itemId = itemId
        self.displayState = 0

        self.referenceId = referenceId
    }

    @Attribute(.preserveValueOnDeletion)
    public var itemId: UUID = UUID()
    public var displayState: Int = 0
    
    enum GenType: Int, Equatable, Hashable, Sendable, Codable, CaseIterable, Identifiable {
        var id: Int {
            rawValue
        }
        
        case adventure = 0
        case character = 1
        
        var title: LocalizedStringKey {
            switch self {
            case .adventure: "Adventure"
            case .character: "Character"
            }
        }
    }
    var genType: GeneratorDataModel.GenType = GeneratorDataModel.GenType.adventure
    
    var referenceId: UUID?
    
    // MARK: Codable
    
    struct GeneratorDataModelCodable: Equatable, Hashable, Codable, Sendable {
        init(itemId: UUID = UUID(), referenceId: UUID?) {
            self.itemId = itemId
            self.referenceId = referenceId
        }
        var itemId: UUID = UUID()
        var referenceId: UUID?
    }
    
    convenience init(_ model: GeneratorDataModelCodable) {
        //let entries = model.entries.map { TableEntryDataModel($0) }
        self.init(itemId: model.itemId, referenceId: model.referenceId)
    }

    @MainActor
    var codableModel: GeneratorDataModelCodable {
        GeneratorDataModelCodable(
            itemId: itemId,
            referenceId: referenceId,
//            entries: entries.map {
//                $0.codableModel
//            },
        )
    }
    
    func replace(_ model: GeneratorDataModelCodable) {
        itemId = model.itemId
        referenceId = model.referenceId
//        entries = model.entries.map { TableEntryDataModel($0) }
    }
    
    func duplicate(newItemId: UUID) -> GeneratorDataModel {
        GeneratorDataModel(
            itemId: newItemId,
            referenceId: referenceId,
//            entries: entries.map { $0.duplicate(newItemId: newItemId, newEntryId: UUID()) }
        )
    }
}

extension GeneratorDataModel {
//    public var entries: [TableEntryDataModel] {
//        get {
//            guard let all = entries_ else { return [] }
//            return all.sorted { $0.index < $1.index }
//        }
//        set {
//            entries_ = newValue
//        }
//    }
//    
//    public subscript(id: UUID) -> TableEntryDataModel {
//        get { entries.first(where: { $0.entryId == id }) ?? TableEntryDataModel(itemId: itemId) }
//        set(newValue) {
//            guard let index = entries.firstIndex(where: { $0.entryId == id }) else { return }
//            entries[index] = newValue
//        }
//    }
}

extension GeneratorDataModel: ModelCachable {
    public static func newModel(for itemId: UUID) -> GeneratorDataModel {
        GeneratorDataModel(itemId: itemId)
    }
}

//extension TableDataModel: EntryEditModel {}
