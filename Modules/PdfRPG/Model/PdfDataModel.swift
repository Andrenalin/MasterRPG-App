// @copyright André Trettin

import CodableModel
import CoreRPG
import Foundation
import SwiftData
import CoreGraphics

@Model @CodableModel
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
}
