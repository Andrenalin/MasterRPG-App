// @copyright André Trettin

import CoreRPG
import SwiftUI
import AdventureRPG
import MapRPG
import TableRPG
import AudioRPG
import CharacterRPG
import PdfRPG
import DiceRPG
import PhotoRPG
import WeatherRPG
import SpaceRPG

struct SearchDetailView: View {
    let root: GameRoot
    let searchController: SearchController
    
    @Environment(\.navigator) private var navigator
    
    public var body: some View {
        @Bindable var model = searchController.model
        if let selection = model.selection {
            Group {
                switch selection.module {
                case .adventure: root.adventureRoot.viewController.inlineViewer(root: root.adventureRoot, with: selection.itemId)
                case .audio: root.audioRoot.viewController.inlineViewer(root: root.audioRoot, with: selection.itemId)
                case .dice: root.diceRoot.viewController.inlineViewer(root: root.diceRoot, with: selection.itemId)
                case .map: root.mapRoot.viewController.inlineViewer(root: root.mapRoot, with: selection.itemId)
                case .pdf: root.pdfRoot.viewController.inlineViewer(root: root.pdfRoot, with: selection.itemId, entryId: selection.entryId, withoutBookmark: true)
                case .photo: root.photoRoot.viewController.inlineViewer(root: root.photoRoot, with: selection.itemId)
                case .space: root.spaceRoot.viewController.inlineViewer(root: root.spaceRoot, with: selection.itemId)
                case .table: root.tableRoot.viewController.inlineViewer(root: root.tableRoot, with: selection.itemId)
                case .value: root.characterRoot.viewController.inlineViewer(root: root.characterRoot, with: selection.itemId)
                case .weather: root.weatherRoot.viewController.inlineViewer(root: root.weatherRoot, with: selection.itemId)
                default: EmptyView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        navigator.perform(route: KnownRoutes.route(module: selection.module, itemId: selection.itemId, entryId: selection.entryId))
                    } label: {
                        Image(systemName: selection.module.icon)
                    }
                    .foregroundStyle(selection.module.tint)
                }
            }
            .id(selection.id)
        } else {
            ContentUnavailableView {
                Label {
                    Text("No Selection", bundle: .module)
                } icon: {
                    Image(systemName: "magnifyingglass")
                }
            } description: {
                Text("Select a search result to view details", bundle: .module)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SearchDetailView(root: GameRoot.preview, searchController: SearchController(root: GameRoot.preview, searchText: "Test"))
}
