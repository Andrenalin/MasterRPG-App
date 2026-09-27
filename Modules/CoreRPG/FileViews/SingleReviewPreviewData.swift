// @copyright André Trettin

import SwiftUI

@MainActor @Observable
private final class PreviewItemModel {
    typealias Entry = EmtpyEntryViewModel

    nonisolated let id: UUID
    var name: String
    var category: ItemListCategory
    var description: String
    var tags: [String]
    var displayState: Int
    var isGroupHiddenToggle: Bool
    var entries: [EmtpyEntryViewModel]
    var fileUrl: FileUrl?
    var parentId: UUID?

    var isGroupHidden: Bool { isGroupHiddenToggle }

    nonisolated init(
        id: UUID = UUID(),
        name: String,
        category: ItemListCategory = .photo,
        description: String = "",
        tags: [String] = [],
        fileUrl: FileUrl? = nil,
        entries: [EmtpyEntryViewModel] = []
    ) {
        self.id = id
        self._name = name
        self._category = category
        self._description = description
        self._tags = tags
        self._displayState = 0
        self._isGroupHiddenToggle = false
        self._entries = entries
        self._fileUrl = fileUrl
        self._parentId = nil
    }

    subscript(entryId: UUID) -> EmtpyEntryViewModel {
        get { entries.first { $0.id == entryId } ?? .empty }
        set { entries = entries.map { $0.id == entryId ? newValue : $0 } }
    }

    nonisolated static var empty: PreviewItemModel { PreviewItemModel(name: "") }
    nonisolated static func empty(_ id: UUID) -> PreviewItemModel { PreviewItemModel(id: id, name: "") }
    nonisolated static var typeId: NetworkModules { .none }

    func copy() -> PreviewItemModel {
        PreviewItemModel(id: id, name: name, category: category, description: description, tags: tags, fileUrl: fileUrl, entries: entries)
    }

    func duplicate() -> PreviewItemModel { copy() }
    func filter(filter: String, includeEntries: Bool) -> Bool { true }
    func isEqual(other: PreviewItemModel) -> Bool { id == other.id }
    @MainActor func replace(with model: PreviewItemModel) -> Bool { false }
    nonisolated static func == (lhs: PreviewItemModel, rhs: PreviewItemModel) -> Bool { lhs.id == rhs.id }
}

extension SingleItemImportModel {
    static var preview: SingleItemImportModel {
        var bg = EmtpyEntryViewModel.empty
        bg.name = "Background"
        bg.content = "Born in Frosthold, trained as a border scout."
        var notes = EmtpyEntryViewModel.empty
        notes.name = "Notes"
        notes.content = "Knows the old password for the Black Keep."
        var bg2 = EmtpyEntryViewModel.empty
        bg2.name = "Background"
        bg2.content = "Born in Frosthold, now serving aboard The Dread."
        var ability = EmtpyEntryViewModel.empty
        ability.name = "Abilities"
        ability.content = "Mist step, shadow blend."

        let existingItem = PreviewItemModel(
            name: "Mara Venn",
            category: .photo,
            description: "A suspicious ranger.",
            tags: ["npc", "ranger", "suspicious"],
            entries: [bg, notes]
        )
        let importedItem = PreviewItemModel(
            name: "Mara Venn",
            category: .photo,
            description: "A loyal rogue who serves Captain Harl.",
            tags: ["loyal", "npc", "rogue"],
            fileUrl: FileUrl(fileId: UUID(), url: URL(filePath: "/portraits/mara.png"), location: .appCloud, module: "photo", relativeUrl: nil),
            entries: [bg2, ability]
        )
        var mergedBg = EmtpyEntryViewModel.empty
        mergedBg.name = "Background"
        mergedBg.content = "Born in Frosthold, now serving aboard The Dread."
        let mergedItem = PreviewItemModel(
            name: "Mara Venn",
            category: .photo,
            description: "A loyal rogue who serves Captain Harl.",
            tags: ["loyal", "npc", "ranger", "rogue", "suspicious"],
            fileUrl: importedItem.fileUrl,
            entries: [mergedBg, notes, ability]
        )
        let item = SingleReviewItem(existing: existingItem, imported: importedItem, merged: mergedItem)
        let model = SingleItemImportModel.from(item: item)
        model.references = [
            SingleReviewReference(itemName: "Black Keep", destination: ItemRowModel(itemId: UUID(), typeId: .adventure), status: .missing)
        ]
        return model
    }

    static var previewConflictingEntries: SingleItemImportModel {
        var existingHistory = EmtpyEntryViewModel.empty
        existingHistory.name = "History"
        existingHistory.content = "Founded in the third age by refugees from the Sunken Isles, Thornwall grew from a fishing village into a trade fortress. Its eastern gate has never been breached in four centuries of recorded conflict."

        var existingNPCs = EmtpyEntryViewModel.empty
        existingNPCs.name = "Key NPCs"
        existingNPCs.content = "Mayor Brynn Holt - pragmatic, bribeable. Captain Sera - loyal to the crown above all else. The Fence known only as Dusty - last seen near the harbour, whereabouts now unknown."

        var existingSecrets = EmtpyEntryViewModel.empty
        existingSecrets.name = "Secrets"
        existingSecrets.content = "A hidden passage beneath the granary connects to the old smugglers' dock. Only the mayor and Dusty know its exact location. The passage floods at high tide."

        var existingOverview = EmtpyEntryViewModel.empty
        existingOverview.name = "Overview"
        existingOverview.content = "Thornwall stands at the junction of the Ashen coast and the inland trade road, a modest but strategically vital settlement that has remained neutral for four generations."
        var importedOverview = existingOverview
        importedOverview.content = "Thornwall is a chokepoint. Whoever controls its amber flow controls the northern economy. The Guild knows this. So does the Crown."

        var existingFactions = EmtpyEntryViewModel.empty
        existingFactions.name = "Factions"
        existingFactions.content = "Amber Merchants' Guild (dominant), Fisher's Brotherhood (declining since the new dock taxes), The Watch (formally neutral, unofficially bought by the Guild over the past two years)."

        var existingEconomy = EmtpyEntryViewModel.empty
        existingEconomy.name = "Economy"
        existingEconomy.content = "Primary exports: amber, salted fish, timber. The amber trade accounts for nearly 60% of all town revenue. A blocked sea lane could destabilise the entire settlement within weeks."

        var importedRumors = EmtpyEntryViewModel.empty
        importedRumors.name = "Rumors"
        importedRumors.content = "Locals whisper that the mayor sold passage rights to a Thieves' Guild convoy last season. The harbour tax records were allegedly altered to conceal three shipments of untaxed amber."

        var importedEvents = EmtpyEntryViewModel.empty
        importedEvents.name = "Recent Events"
        importedEvents.content = "A fire destroyed the western warehouse district three weeks ago. No cause was officially determined. Six bodies recovered; two remain unidentified. Guild marks were found on the salvage."

        var importedTradeRoutes = EmtpyEntryViewModel.empty
        importedTradeRoutes.name = "Trade Routes"
        importedTradeRoutes.content = "Three overland routes connect Thornwall to the interior. The southern road through Mirewood is fastest but now subject to Guild tolls. The coastal path is longer but avoids all checkpoints."

        var importedMilitary = EmtpyEntryViewModel.empty
        importedMilitary.name = "Military Presence"
        importedMilitary.content = "Twelve Watch soldiers nominally under the mayor's command. Six mercenaries recently hired by the Merchants' Guild. No naval force - the harbour is entirely undefended from the sea."

        var importedDangers = EmtpyEntryViewModel.empty
        importedDangers.name = "Dangers"
        importedDangers.content = "Thieves' Guild expansion. Potential arson if the mayor fails to cooperate. Unknown buyer for stolen amber manifests. At least one Guild informant is embedded inside The Watch."

        let existingItem = PreviewItemModel(
            name: "Thornwall",
            category: .photo,
            description: "A fortified coastal trade town on the edge of the Ashen Reach. Known for amber trade and political neutrality - though neither may last much longer given the Guild pressure building from the south.",
            tags: ["location", "town", "coastal", "trade"],
            entries: [existingOverview, existingHistory, existingNPCs, existingSecrets, existingFactions, existingEconomy]
        )
        let importedItem = PreviewItemModel(
            name: "Thornwall",
            category: .photo,
            description: "Trade hub on the Ashen Reach. Recent unrest and suspicious fires suggest the mayor's neutrality has been compromised. Thieves' Guild operatives are moving in from the south road.",
            tags: ["conflict", "guild", "location", "town"],
            entries: [importedOverview, importedRumors, importedEvents, importedTradeRoutes, importedMilitary, importedDangers]
        )
        let mergedItem = PreviewItemModel(
            name: "Thornwall",
            category: .photo,
            description: "A fortified coastal trade town on the edge of the Ashen Reach. Known for amber trade and political neutrality - though neither may last much longer given the Guild pressure building from the south.",
            tags: ["coastal", "conflict", "guild", "location", "town", "trade"],
            entries: [importedOverview, existingHistory, existingNPCs, existingSecrets, existingFactions, existingEconomy,
                      importedRumors, importedEvents, importedTradeRoutes, importedMilitary, importedDangers]
        )
        let reviewItem = SingleReviewItem(existing: existingItem, imported: importedItem, merged: mergedItem)
        let model = SingleItemImportModel.from(item: reviewItem)
        model.references = [
            SingleReviewReference(itemName: "Ashen Reach Region", destination: ItemRowModel(itemId: UUID(), typeId: .map), status: .resolved),
            SingleReviewReference(itemName: "The Mayor's Ledger", destination: ItemRowModel(itemId: UUID(), typeId: .adventure), status: .pendingImport),
            SingleReviewReference(itemName: "Brynn Holt", destination: ItemRowModel(itemId: UUID(), typeId: .value), status: .resolved)
        ]
        return model
    }
}

#Preview("Single Review Accordion") {
    NavigationStack { SingleItemReviewAccordionView(model: .previewConflictingEntries) }
}

extension PreviewItemModel: nonisolated Equatable {}
extension PreviewItemModel: nonisolated ItemDataAccessable {}
