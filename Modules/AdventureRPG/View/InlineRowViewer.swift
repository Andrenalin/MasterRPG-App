// @copyright André Trettin

import CoreRPG
import MapRPG
import PhotoRPG
import SpaceRPG
import SwiftUI
import WeatherRPG
import DiceRPG
import PdfRPG

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    
    @Environment(AdventureRootModel.self) private var root
    
    var body: some View {
        switch source.typeId {
        case .dice:
            root.diceRoot.viewController.rowViewer(source: source)
        case .map:
            root.mapRoot.viewController.rowViewer(source: source)
        case .pdf:
            root.pdfRoot.viewController.rowViewer(source: source)
        case .space:
            root.spaceRoot.viewController.rowViewer(source: source)
        case .weather:
            root.weatherRoot.viewController.rowViewer(source: source)
        default:
            root.photoRoot.viewController.photoRow(root: root.photoRoot, for: source.itemId)
        }
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .photo))
}
