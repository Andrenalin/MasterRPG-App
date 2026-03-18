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

public struct SearchRootView: View {
    public init(root: GameRoot, searchText: String = "") {
        self.root = root
        self._searchController = State(initialValue: SearchController(root: root, searchText: searchText))
    }

    let root: GameRoot

    @State private var searchController: SearchController

    public var body: some View {
        @Bindable var model = searchController.model
        NavigationSplitView {
            SearchListView(root: root, searchController: searchController)
        } detail: {
            SearchDetailView(root: root, searchController: searchController)
        }
    }
}

// MARK: - Preview

#Preview {
    SearchRootView(root: GameRoot.preview, searchText: "T")
}
