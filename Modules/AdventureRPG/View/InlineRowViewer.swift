// @copyright André Trettin

import CoreRPG
import AudioRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import SwiftUI
import WeatherRPG
import TableRPG
import CharacterRPG

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(AdventureRootModel.self) private var root
    
    var body: some View {
        switch module {
        case .audio:
            root.audioRoot.viewController.rowViewer(source: source, destination: destination)
        case .dice:
            root.diceRoot.viewController.rowViewer(source: source, destination: destination)
        case .map:
            root.mapRoot.viewController.rowViewer(source: source, destination: destination)
        case .pdf:
            root.pdfRoot.viewController.rowViewer(source: source, destination: destination)
        case .photo:
            root.photoRoot.viewController.photoRow(root: root.photoRoot, for: source.itemId)
        case .space:
            root.spaceRoot.viewController.rowViewer(source: source, destination: destination)
        case .table:
            root.tableRoot.viewController.rowViewer(source: source, destination: destination)
        case .value:
            root.characterRoot.viewController.rowViewer(source: source, destination: destination)
        case .weather:
            root.weatherRoot.viewController.rowViewer(source: source, destination: destination)
        default:
            EmptyView()
        }
    }
    
    var module: NetworkModules {
        destination.typeId == .adventure ? source.typeId : destination.typeId
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .photo), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
