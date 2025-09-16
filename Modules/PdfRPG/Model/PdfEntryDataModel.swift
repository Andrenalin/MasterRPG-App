// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData
import CoreGraphics

@Model 
public final class PdfEntryDataModel {
    init(
        itemId: UUID,
        entryId: UUID = UUID(),
        index: Int = 0,
        name: String = "",
        content: String = "",
        bounds: CGRect = .zero,
        pageLabel: String = "",
        parent: PdfDataModel? = nil
    ) {
        self.itemId = itemId
        self.entryId = entryId
        self.index = index
        self.name = name
        self.content = content
        self.bounds = bounds
        self.pageLabel = pageLabel
        self.parent = parent
    }

    public var itemId: UUID = UUID()

    @Attribute(.preserveValueOnDeletion)
    public var entryId: UUID = UUID()
    public var index: Int = 0
    public var name: String = ""
    public var content: String = ""

    var bounds: CGRect {
        get { JSONString.decode(text: bounds_) ?? .zero }
        set { bounds_ = JSONString.encode(value: newValue) ?? "" }
    }
    private var bounds_: String = ""

    var pageLabel: String = ""

    //@CodableIgnored
    var parent: PdfDataModel? = nil

    // MARK: - Codable
    
    struct PdfEntryDataModelCodable: Equatable, Hashable, Codable, Sendable {
        init(itemId: UUID = UUID(), entryId: UUID = UUID(), index: Int = 0, name: String = "", content: String = "", bounds: CGRect, pageLabel: String = "") {
            self.itemId = itemId
            self.entryId = entryId
            self.index = index
            self.name = name
            self.content = content
            self.bounds = bounds
            self.pageLabel = pageLabel
        }
        var itemId: UUID = UUID()
        var entryId: UUID = UUID()
        var index: Int = 0
        var name: String = ""
        var content: String = ""
        var bounds: CGRect
        var pageLabel: String = ""
    }
    
    convenience init(_ model: PdfEntryDataModelCodable) {
        self.init(
            itemId: model.itemId,
            entryId: model.entryId,
            index: model.index,
            name: model.name,
            content: model.content,
            bounds: model.bounds,
            pageLabel: model.pageLabel
        )
    }
    
    var codableModel: PdfEntryDataModelCodable {
        PdfEntryDataModelCodable(
            itemId: itemId,
            entryId: entryId,
            index: index,
            name: name,
            content: content,
            bounds: bounds,
            pageLabel: pageLabel
        )
    }
    
    func replace(_ model: PdfEntryDataModelCodable) {
        itemId = model.itemId
        entryId = model.entryId
        index = model.index
        name = model.name
        content = model.content
        bounds = model.bounds
        pageLabel = model.pageLabel
    }
}

extension PdfEntryDataModel: EntryPersistentModel {
    public func duplicate(name: String, index: Int) -> PdfEntryDataModel {
        PdfEntryDataModel(
            itemId: itemId,
            entryId: UUID(),
            index: index,
            name: name,
            content: content,
            bounds: bounds,
            pageLabel: pageLabel
        )
    }
}
