// @copyright André Trettin

import CoreRPG
import Foundation
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

@MainActor
struct SearchGlobalController {
    init(root: GameRoot, searchText: String = "") {
        self.root = root
        self.model = SearchModel(searchText: searchText)
    }
    
    let root: GameRoot
    let model: SearchModel

    func performSearch() async {
        // Cancel any ongoing search
        model.cancelSearch()

        guard !model.searchText.isEmpty else {
            model.results = [:]
            return
        }

        let searchTask = Task { @MainActor in
            model.isSearching = true
            defer { model.isSearching = false }

            // Small delay to debounce rapid typing — reuses CoreRPG's shared debounce constant
            // rather than a second, drifting copy of the same value. See CODE_AUDIT §9.14.
            try? await Task.sleep(for: ListSearchTiming.typingDebounce)

            guard !Task.isCancelled else { return }

            model.results = await searchAllItems()
        }

        model.setSearchTask(searchTask)
        await model.awaitCurrentSearch()
    }

    private func searchAllItems() async -> [NetworkModules: [SearchResult]] {
        var result: [NetworkModules: [SearchResult]] = [:]
        if !model.playerMode {
            result[.adventure] = await searchItems(in: root.adventureRoot.rootController)
            result[.map] = await searchItems(in: root.mapRoot.rootController)
            result[.weather] = await searchItems(in: root.weatherRoot.rootController)
        }
        result[.value] = await searchItems(in: root.characterRoot.rootController)
        result[.table] = await searchItems(in: root.tableRoot.rootController)
        if let ruleRoot = root.ruleRoot {
            result[.rule] = await searchItems(in: ruleRoot.rootController)
        }

        result[.audio] = await searchItems(in: root.audioRoot.rootController)
        result[.dice] = await searchItems(in: root.diceRoot.rootController)
        result[.pdf] = await searchItems(in: root.pdfRoot.rootController)
        result[.photo] = await searchItems(in: root.photoRoot.rootController)
        result[.space] = await searchItems(in: root.spaceRoot.rootController)

        return result
    }

    private func searchItems(in moduleRoot: ItemRootController) async -> [SearchResult] {
        await moduleRoot.searchControllable.globalSearchResults(searchText: model.searchText)
    }
}
