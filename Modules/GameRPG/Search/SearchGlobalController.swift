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
        self.model = GlobalSearchModel(searchText: searchText)
    }

    let root: GameRoot
    let model: GlobalSearchModel

    func performSearch() async {
        guard model.hasSearch else {
            // Assigning nil still cancels any in-flight search via `currentTask`'s `didSet`.
            model.currentTask = nil
            model.results = [:]
            model.isSearching = false
            return
        }

        let searchTask = Task { @MainActor in
            model.isSearching = true
            // A superseded (cancelled) search leaves the flag to the search that replaced it, so
            // the spinner does not flicker off between two searches. See CODE_AUDIT_26 §5.90.
            defer { if !Task.isCancelled { model.isSearching = false } }

            // Small delay to debounce rapid typing — reuses CoreRPG's shared debounce constant
            // rather than a second, drifting copy of the same value. See CODE_AUDIT §9.14.
            try? await Task.sleep(for: ListSearchTiming.typingDebounce)

            guard !Task.isCancelled else { return }

            let results = if let levelQuery = model.levelQuery {
                await searchLevel(levelQuery)
            } else {
                await searchAllItems()
            }
            // The older term's results must not replace the newer term's.
            guard !Task.isCancelled else { return }
            model.results = results
        }

        // Assigning cancels any previous in-flight search via `didSet`.
        model.currentTask = searchTask
        await searchTask.value
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

    /// A level search ("level 4 adventures", "monsters for level 9") looks only at the modules
    /// with levels: adventures (not in player mode, as in the text search) and monsters.
    private func searchLevel(_ query: LevelSearchQuery) async -> [NetworkModules: [SearchResult]] {
        var result: [NetworkModules: [SearchResult]] = [:]
        if !model.playerMode {
            result[.adventure] = await root.adventureRoot.rootController.searchControllable.levelSearchResults(query: query)
        }
        result[.value] = await root.characterRoot.rootController.searchControllable.levelSearchResults(query: query)
        return result
    }

    private func searchItems(in moduleRoot: ItemRootController) async -> [SearchResult] {
        await moduleRoot.searchControllable.globalSearchResults(searchText: model.searchText)
    }
}
