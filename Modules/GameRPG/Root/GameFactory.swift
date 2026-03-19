// @copyright André Trettin

import AudioRPG
import CharacterRPG
import CoreRPG
import DiceRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import SwiftData
import SwiftUI
import WeatherRPG

public enum GameFactory {
    @MainActor public static func rootSearchView(root: GameRoot) -> some View {
        SearchRootView(root: root)
    }
        
    @MainActor @ViewBuilder public static func detailSearchView(root: GameRoot) -> some View {
        SearchDetailView(root: root, searchController: root.searchController)
    }
}
