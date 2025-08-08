// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData
import CoreGraphics

@Model
public final class PdfBookmarkDataModel {
    init(id: UUID = UUID(), index: Int = 0, name: String = "", content: String = "", bounds: CGRect = .zero, pageLabel: String = "", parent: PdfDataModel? = nil) {
        self.id = id
        self.index = index
        self.name = name
        self.content = content
        self.bounds = bounds
        self.pageLabel = pageLabel
        self.parent = parent
    }
    
    @Attribute(.preserveValueOnDeletion)
    public var id: UUID = UUID()
    var index: Int = 0
    public var name: String = ""
    var content: String = ""

    var bounds: CGRect {
        get { JSONString.decode(text: bounds_) ?? .zero }
        set { bounds_ = JSONString.encode(value: newValue) ?? "" }
    }
    private var bounds_: String = ""

    var pageLabel: String = ""
    var parent: PdfDataModel?
    
}
