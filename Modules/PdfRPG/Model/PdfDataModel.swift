// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model 
public final class PdfDataModel {
    init(itemId: UUID = UUID(), entries: [PdfEntryDataModel] = []) {
        self.itemId = itemId
        self.entries = entries
    }
    
    @Attribute(.preserveValueOnDeletion)
    public var itemId: UUID = UUID()
    public var displayState: Int = 0

    @Relationship(deleteRule: .cascade) private var entries_: [PdfEntryDataModel]? = []

    // MARK: - Codable
    
    struct PdfDataModelCodable: Equatable, Hashable, Codable, Sendable {
        init(itemId: UUID = UUID(), entries: [PdfEntryDataModel.PdfEntryDataModelCodable] = []) {
            self.itemId = itemId
            self.entries = entries
        }
        var itemId: UUID = UUID()
        var entries: [PdfEntryDataModel.PdfEntryDataModelCodable]
    }
    
    convenience init(_ model: PdfDataModelCodable) {
        let entries = model.entries.map { PdfEntryDataModel($0) }
        self.init(itemId: model.itemId, entries: entries)
    }
    
    var codableModel: PdfDataModelCodable {
        PdfDataModelCodable(
            itemId: itemId,
            entries: entries.map {
                $0.codableModel
            }
        )
    }
    
    func replace(_ model: PdfDataModelCodable) {
        itemId = model.itemId
        entries = model.entries.map { PdfEntryDataModel($0) }
    }
    
    func duplicate(newItemId: UUID) -> PdfDataModel {
        PdfDataModel(
            itemId: newItemId,
            entries: entries.map { $0.duplicate(newItemId: newItemId, newEntryId: UUID()) }
        )
    }
}

extension PdfDataModel {
    public var entries: [PdfEntryDataModel] {
        get {
            guard let all = entries_ else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries_ = newValue
        }
    }

    public subscript(id: UUID) -> PdfEntryDataModel {
        get { entries.first(where: { $0.entryId == id }) ?? PdfEntryDataModel(itemId: itemId) }
        set(newValue) {
            guard let index = entries.firstIndex(where: { $0.entryId == id }) else { return }
            entries[index] = newValue
        }
    }
}

extension PdfDataModel: ModelCachable {
    public static func newModel(for itemId: UUID) -> PdfDataModel {
        PdfDataModel(itemId: itemId)
    }
}

extension PdfDataModel: EntryEditModel {}
