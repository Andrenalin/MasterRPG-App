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
    
    public var itemId: UUID = UUID()
    var diceId: UUID?
    
    @Relationship(deleteRule: .cascade) private var entries_: [TableEntryDataModel]? = []
    
    // MARK: Codable
    
    struct TableDataModelCodable: Equatable, Hashable, Codable, Sendable {
        init(itemId: UUID = UUID(), diceId: UUID?, entries: [TableEntryDataModel.TableEntryDataModelCodable] = []) {
            self.itemId = itemId
            self.diceId = diceId
            self.entries = entries
        }
        var itemId: UUID = UUID()
        var diceId: UUID?
        var entries: [TableEntryDataModel.TableEntryDataModelCodable] = []
    }
    
    convenience init(_ model: TableDataModelCodable) {
        self.init(itemId: model.itemId, diceId: model.diceId, entries: [])
        self.entries = model.entries.map { TableEntryDataModel($0) }
    }
    
    var codableModel: TableDataModelCodable {
        TableDataModelCodable(
            itemId: itemId,
            diceId: diceId,
            entries: entries.map {
                $0.codableModel
            }
        )
    }
    
    func replace(_ model: TableDataModelCodable) {
        itemId = model.itemId
        diceId = model.diceId
        entries = model.entries.map { TableEntryDataModel($0) }
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
