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
import RuleRPG
import WeatherRPG
import SpaceRPG

struct SearchDetailView: View {
    let root: GameRoot
    let navigator: Navigator

    @Environment(\.routeActions) private var routeActions

    public var body: some View {
        @Bindable var model = root.searchController.model
        if let selection = model.selection {
            Group {
                switch selection.module {
                case .adventure: root.adventureRoot.viewController.viewer(root: root.adventureRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: false, addToolbar: true, isGame: false))
                case .audio: root.audioRoot.viewController.viewer(root: root.audioRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: false, addToolbar: true, isGame: false))
                case .dice: root.diceRoot.viewController.viewer(root: root.diceRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: false, addToolbar: true, isGame: false))
                case .map: root.mapRoot.viewController.viewer(root: root.mapRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: false, addToolbar: true, isGame: false))
                case .pdf: root.pdfRoot.viewController.viewer(root: root.pdfRoot, itemId: selection.itemId, entryId: selection.entryId, configuration: ViewerConfiguration(closeButton: false, addToolbar: true, isGame: false))
                case .photo: root.photoRoot.viewController.viewer(root: root.photoRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: false, addToolbar: true, isGame: false))
                case .rule:
                    if let ruleRoot = root.ruleRoot {
                        ruleRoot.viewController.viewer(root: ruleRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: false, addToolbar: true, isGame: false))
                    }
                case .space: root.spaceRoot.viewController.viewer(root: root.spaceRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: false, addToolbar: true, isGame: false))
                case .table: root.tableRoot.viewController.viewer(root: root.tableRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: false, addToolbar: true, isGame: false))
                case .value: root.characterRoot.viewController.viewer(root: root.characterRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: false, addToolbar: true, isGame: false))
                case .weather: root.weatherRoot.viewController.viewer(root: root.weatherRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: false, addToolbar: true, isGame: false))
                default: EmptyView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        routeActions.routePage(selection.module, selection.itemId, selection.entryId)
                    } label: {
                        Image(systemName: selection.module.icon)
                    }
                    .accessibilityLabel(Text(selection.module.localizedTitle))
#if os(macOS)
                    .foregroundStyle(selection.module.tint)
#else
                    .tint(selection.module.tint)
#endif
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
    SearchDetailView(root: GameRoot.preview, navigator: Navigator(configuration: NavigationConfiguration()))
}
