// @copyright André Trettin

import SwiftUI

struct FakeEditController: EditControllable {
    typealias Model = FakeItemModel
    
    var itemControllable: any ItemControllable
    var fileUrlDataController: FileUrlDataController?
    var tagController: TagController
    var linkRegisterController: LinkRegisterController

    var editorModel: ItemEditorModel

    var cacheItemListModel: CacheItemListModel

    @MainActor
    static let fake = FakeEditController(itemControllable: FakeItemController.fake, tagController: TagController(), linkRegisterController: LinkRegisterController(root: nil), editorModel: ItemEditorModel(sheetEditorModel: SheetEditorModel()), cacheItemListModel: CacheItemListModel())
}

extension FakeEditController: EntryDataEditable {
    var linkModules: [NetworkModules] {
        []
    }
    
    func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        InternalRoute.removeAlert
    }
    
    func quickEditorDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        InternalRoute.removeAlert
    }
    
    func create(name: String, content: String) -> FakeEntryModel {
        FakeEntryModel.empty
    }

    func merge(itemId: UUID, entries: [FakeEntryModel]) -> [FakeEntryModel] {
        entries
    }
    
    func merge(itemId: UUID, entries: [FakeEntryModel], recoverEntries: [ItemRowModel]?, forceSave: Bool) -> [ItemRowModel] {
        []
    }
}

extension SheetModel {
    /// A richly populated RPG character sheet for use in Xcode previews.
    @MainActor
    public static var previewFixture: SheetModel {
        let characterId = UUID.fixture1

        func leafEntry(name: String, description: String) -> SheetModel {
            SheetModel(
                source: ItemRowModel(itemId: characterId, entryId: UUID(), typeId: .adventure),
                name: name,
                description: description,
                entries: []
            )
        }

        let abilityScores = SheetModel(
            source: ItemRowModel(itemId: characterId, entryId: UUID.fixture2, typeId: .adventure),
            name: "Ability Scores",
            description: "",
            entries: [
                leafEntry(name: "STR", description: "18 (+4)"),
                leafEntry(name: "DEX", description: "12 (+1)"),
                leafEntry(name: "CON", description: "16 (+3)"),
                leafEntry(name: "INT", description: "10 (+0)"),
                leafEntry(name: "WIS", description: "14 (+2)"),
                leafEntry(name: "CHA", description: "17 (+3)")
            ]
        )

        let combat = SheetModel(
            source: ItemRowModel(itemId: characterId, entryId: UUID.fixture3, typeId: .adventure),
            name: "Combat",
            description: "",
            entries: [
                leafEntry(name: "Hit Points", description: "74 / 74"),
                leafEntry(name: "Armor Class", description: "18 (Plate Armor +1)"),
                leafEntry(name: "Speed", description: "30 ft."),
                leafEntry(name: "Initiative", description: "+1"),
                leafEntry(name: "Proficiency Bonus", description: "+3"),
                leafEntry(name: "Passive Perception", description: "14")
            ]
        )

        let background = leafEntry(
            name: "Background",
            description: "Noble — forsook family privilege after witnessing rampant corruption within the city guard. Driven by an unbreakable oath to protect the innocent and bring justice to the realm."
        )

        let equipment = SheetModel(
            source: ItemRowModel(itemId: characterId, entryId: UUID.fixture4, typeId: .adventure),
            name: "Equipment",
            description: "",
            entries: [
                leafEntry(name: "Holy Avenger", description: "Longsword (magical) · 1d8+6 slashing · +3 to attack and damage"),
                leafEntry(name: "Plate Armor +1", description: "AC 18 · Disadvantage on Stealth checks"),
                leafEntry(name: "Shield", description: "+2 AC"),
                leafEntry(name: "Pouch", description: "50 gp · Sending Stone · Healer's Kit (8 uses)")
            ]
        )

        let spells = SheetModel(
            source: ItemRowModel(itemId: characterId, entryId: UUID.fixture5, typeId: .adventure),
            name: "Spells & Abilities",
            description: "Spell Save DC 15 · Spell Attack +7 · Slots: 4 / 3 / 3 / 1",
            entries: [
                leafEntry(name: "Divine Smite", description: "On a hit, expend a spell slot to deal 2d8 additional radiant damage per slot level (max 5d8). Extra 1d8 vs undead and fiends."),
                leafEntry(name: "Lay on Hands", description: "40 healing points remaining. Cure one disease or neutralise one poison per 5 points spent."),
                leafEntry(name: "Aura of Protection", description: "Allies of your choice within 10 ft. add your Charisma modifier (+3) to all saving throws."),
                leafEntry(name: "Sacred Weapon", description: "Channel Divinity (1/rest): weapon becomes magical and gains +3 to attack rolls for 1 minute.")
            ]
        )

        return SheetModel(
            source: ItemRowModel(itemId: characterId, typeId: .adventure),
            level: 0,
            name: "Theron Ironheart",
            description: "Half-Elf Paladin · Level 8 · Lawful Good · Oath of Devotion",
            entries: [abilityScores, combat, background, equipment, spells]
        )
    }
}

extension SheetRootModel {
    @MainActor
    public static func previewFixture(
        root: any ItemRootControllable
    ) -> SheetRootModel {
        SheetRootModel(
            rootManager: root.rootManager ?? RootManager(anyRoot: root),
            linkControllable: root.linkControllable,
            sheetControllable: root.sheetControllable,
            sheetModel: .previewFixture,
            isEditor: true
        )
    }

    /// Compatibility spelling that now returns an isolated graph per access.
    @MainActor
    public static var fake: SheetRootModel {
        let root = ItemRootController.previewFixture()
        return previewFixture(root: root)
    }
}
