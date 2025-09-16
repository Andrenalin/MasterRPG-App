// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model 
public final class TableDataModel {
    public init(itemId: UUID = UUID(), diceId: UUID? = nil, entries: [TableEntryDataModel] = []) {
        self.itemId = itemId
        self.diceId = diceId
        self.entries = entries
    }

    @Attribute(.preserveValueOnDeletion)
    public var itemId: UUID = UUID()
    var diceId: UUID?
    
    @Relationship(deleteRule: .cascade) private var entries_: [TableEntryDataModel]? = []
    
    // MARK: Codable
    
    struct TableDataModelCodable: Equatable, Hashable, Codable, Sendable {
        init(itemId: UUID = UUID(), diceId: UUID?, entries: [TableEntryDataModel.TableEntryDataModelCodable] = [], links: [LinkDataModel.LinkDataModelCodable] = []) {
            self.itemId = itemId
            self.diceId = diceId
            self.entries = entries
            self.links = links
        }
        var itemId: UUID = UUID()
        var diceId: UUID?
        var entries: [TableEntryDataModel.TableEntryDataModelCodable] = []
        var links: [LinkDataModel.LinkDataModelCodable] = []
    }
    
    convenience init(_ model: TableDataModelCodable) {
        let entries = model.entries.map { TableEntryDataModel($0) }
        self.init(itemId: model.itemId, diceId: model.diceId, entries: entries)
    }

    @MainActor
    var codableModel: TableDataModelCodable {
        TableDataModelCodable(
            itemId: itemId,
            diceId: diceId,
            entries: entries.map {
                $0.codableModel
            },
            links: entries.flatMap {
                $0.links
            }
        )
    }
    
    func replace(_ model: TableDataModelCodable) {
        itemId = model.itemId
        diceId = model.diceId
        entries = model.entries.map { TableEntryDataModel($0) }
    }
    
    func duplicate(newItemId: UUID) -> TableDataModel {
        TableDataModel(
            itemId: newItemId,
            diceId: diceId,
            entries: entries.map { $0.duplicate(newItemId: newItemId, newEntryId: UUID()) }
        )
    }
}

extension TableDataModel {
    public var entries: [TableEntryDataModel] {
        get {
            guard let all = entries_ else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries_ = newValue
        }
    }
    
    public subscript(id: UUID) -> TableEntryDataModel {
        get { entries.first(where: { $0.entryId == id }) ?? TableEntryDataModel(itemId: itemId) }
        set(newValue) {
            guard let index = entries.firstIndex(where: { $0.entryId == id }) else { return }
            entries[index] = newValue
        }
    }
}

extension TableDataModel: EntryEditModel {}
