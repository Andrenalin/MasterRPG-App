// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData
import CoreGraphics

@Model 
public final class PdfDataModel {
    init(id: UUID = UUID(), itemId: UUID, index: Int = 0, name: String = "", content: String = "", bounds: CGRect = .zero, pageLabel: String = "") {
        self.id = id
        self.itemId = itemId
        self.index = index
        self.name = name
        self.content = content
        self.bounds = bounds
        self.pageLabel = pageLabel
    }
    
    @Attribute(.preserveValueOnDeletion)
    public var id: UUID = UUID()
    public var itemId: UUID = UUID()
    var index: Int = 0
    public var name: String = ""
    var content: String = ""

    var bounds: CGRect {
        get { JSONString.decode(text: bounds_) ?? .zero }
        set { bounds_ = JSONString.encode(value: newValue) ?? "" }
    }
    private var bounds_: String = ""

    var pageLabel: String = ""
    
    // MARK: - Codable
    
    struct PdfDataModelCodable: Equatable, Hashable, Codable, Sendable {
        init(id: UUID = UUID(), itemId: UUID = UUID(), index: Int = 0, name: String = "", content: String = "", bounds: CGRect, pageLabel: String = "") {
            self.id = id
            self.itemId = itemId
            self.index = index
            self.name = name
            self.content = content
            self.bounds = bounds
            self.pageLabel = pageLabel
        }
        var id: UUID = UUID()
        var itemId: UUID = UUID()
        var index: Int = 0
        var name: String = ""
        var content: String = ""
        var bounds: CGRect
        var pageLabel: String = ""
    }
    
    convenience init(_ model: PdfDataModelCodable) {
        self.init(id: model.id, itemId: model.itemId, index: model.index, name: model.name, content: model.content, bounds: model.bounds, pageLabel: model.pageLabel)
    }
    
    var codableModel: PdfDataModelCodable {
        PdfDataModelCodable(
            id: id,
            itemId: itemId,
            index: index,
            name: name,
            content: content,
            bounds: bounds,
            pageLabel: pageLabel
        )
    }
    
    func replace(_ model: PdfDataModelCodable) {
        id = model.id
        itemId = model.itemId
        index = model.index
        name = model.name
        content = model.content
        bounds = model.bounds
        pageLabel = model.pageLabel
    }
}
