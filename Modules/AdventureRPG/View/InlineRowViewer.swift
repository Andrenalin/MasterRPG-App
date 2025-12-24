// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI
import WeatherRPG

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    
    @Environment(AdventureRootModel.self) private var root
    
    var body: some View {
        if source.typeId == .photo {
            root.photoRoot.viewController.photoRow(root: root.photoRoot, for: source.itemId)
        }
        if source.typeId == .weather {
            root.weatherRoot.viewController.rowViewer(source: source)
        }
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .photo))
}
