// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import RegexBuilder
import SwiftUI
import PhotoRPG
import AudioRPG
import DiceRPG
import PdfRPG
import TableRPG
import CharacterRPG

@MainActor @Observable
final class MapEditModel: Sendable {
    let selectionAudio: ItemSelectionModel = ItemSelectionModel()
    let selectionCharacter: ItemSelectionModel = ItemSelectionModel()
    let selectionDice: ItemSelectionModel = ItemSelectionModel()
    let selectionPdf: ItemSelectionModel = ItemSelectionModel()
    let selectionPhoto: ItemSelectionModel = ItemSelectionModel()
    let selectionTable: ItemSelectionModel = ItemSelectionModel()
}

struct EditController: Sendable {
    @MainActor init(root: MapRootModel, itemController: ItemController, linkRegisterControllable: LinkRegisterControllable) {
        self.root = root
        
        self.itemController = itemController
        self.linkRegisterControllable = linkRegisterControllable

        self.editorModel = ItemEditorModel()
        self.mapEditModel = MapEditModel()
    }

    let root: MapRootModel

    let itemController: ItemController
    let linkRegisterControllable: any LinkRegisterControllable

    let editorModel: ItemEditorModel
    let mapEditModel: MapEditModel
}

struct LinkMapModuleTransferable: LinkDataTransferable {
    let module: NetworkModules
    let itemId: UUID
    let entryId: UUID?
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .audioLink)
        CodableRepresentation(contentType: .characterLink)
        CodableRepresentation(contentType: .diceLink)
        CodableRepresentation(contentType: .mapLink)
        CodableRepresentation(contentType: .pdfLink)
        CodableRepresentation(contentType: .photoLink)
        CodableRepresentation(contentType: .tableLink)
    }
}

extension EditController: EntryDataEditable {
    typealias Model = MapModel
    
    var itemControllable: any ItemControllable {
        itemController
    }
    
    var fileUrlDataController: FileUrlDataController? {
        itemControllable.fileUrlDataController
    }
    
    public var linkModules: [NetworkModules] { [.audio, .value, .dice, .map, .pdf, .photo, .table] }
    
    public func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        EditorRoute.linkSelection(itemRowModel)
    }
    
    public func linkSelectionDestination(for module: NetworkModules) -> any NavigationDestination {
        switch module {
        case .dice:
            SelectionDiceRoute.selection
        default:
            SelectionTableRoute.selection
        }
    }

    public func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool {
        module == .audio || (module == .value && entryId == nil) || module == .dice || module == .map || module == .pdf || module == .photo || (module == .table && entryId == nil)
    }
    
    @MainActor public func add(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, destinationItemId: UUID, destinationEntryId: UUID) {
        guard canAddLink(module: module, entryId: entryId) else { return }
        
        switch module {
        case .audio, .dice, .map, .pdf, .photo, .table:
            addLinkInEntry(link: link, module: module, itemId: itemId, entryId: entryId, destinationItemId: destinationItemId, destinationEntryId: destinationEntryId)
        case .value:
            guard let editModel = editModel(for: destinationItemId) else { return }
            addMonsters(to: editModel, entryId: destinationEntryId, location: nil, monsters: [ItemRowModel(itemId: itemId, typeId: .value)], number: 1)
            save(updated: editModel, message: "Added Monster".localizedString)
            addLinkInEntry(link: link, module: module, itemId: itemId, entryId: entryId, destinationItemId: destinationItemId, destinationEntryId: destinationEntryId)
        default:
            return
        }
    }
    
    public var thumbnailEntryViewType: ThumbnailEntryViewType { .photo }
    public var additioanlEnrtryViewType: AdditionalEntryViewType { .custom }

    @MainActor public func additionalRowView(for entryId: UUID) -> AnyView {
        AnyView(AddtionalEntryRow(itemId: UUID(), entryId: entryId).equatable())
    }

    func create(name: String, content: String) -> MapEntryModel {
        MapEntryModel(id: UUID(), name: name, content: content, coordinates: [])
    }
        
    func editEntries(for item: MapModel) -> [MapEntryModel] {
        item.entries.filter { !$0.isHexGrid }
    }
}

// MARK: - New Editor Functions

extension EditController {
    @MainActor func add(photoId: UUID?, modelId: UUID) {
        guard var editModel = editModel(for: modelId) else { return }
        editModel.photoId = photoId
        save(updated: editModel, message: String(localized: "Change Photo").localizedString)
    }
}

extension EditController {
    @MainActor
    func resetImageSize(photoId: UUID, updateModel: MapModel, save: Bool = false) async {
        if let (image, degrees) = await root.photoRoot.fetchPhotoImage(for: photoId, useGame: false) {
            let size = image.size
            updateModel.resetImage(with: photoId, size: size, degrees: degrees)
            if save {
                itemController.replace(model: updateModel, isInsert: false, shouldRepairLinks: false)
            }
        }
    }
    
    @MainActor
    func generateQuickMap(name: String, photoId: UUID) async -> UUID? {
        if let itemId = itemController.itemDataModel.items.first(where: { itemController.itemSync(for: $0)?.name == name && itemController.itemSync(for: $0)?.photoId == photoId }) {
            return itemId
        }
        let createMap = MapModel(id: UUID(), name: name, degrees: 0)
        await resetImageSize(photoId: photoId, updateModel: createMap)
        createHexMap(model: createMap, hexMapScale: 0)

        itemController.replace(model:createMap, isInsert: true, shouldRepairLinks: true)
        return createMap.id
    }

    @MainActor func validateBeforeSave(model: MapModel) {
        let validateModel = model
        Task {
            for entry in validateModel.entries {
                if itemController.itemSync(for: validateModel.id)?[entry.id].coordinates != entry.coordinates {
                    await root.cacheController?.remove(itemId: entry.id)
                }
            }
        }
    }
}

// MARK: - Edit Pins

extension EditController {
    @MainActor func addNewPin(at index: Int? = nil, itemId: UUID) -> MapEntryModel.ID {
        let pin = MapPinModel(id: UUID(), name: String(localized: "New Pin").localizedString, color: .random, photoId: nil, location: .zero, size: .normal, isShown: true, players: [], timeInterval: 0)
        add(pin: pin, at: index, itemId: itemId)
        return pin.id
    }

    @MainActor func add(pin: MapPinModel, at index: Int? = nil, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        add(pin: pin, at: index, to: editModel)
    }

    @MainActor func add(pin: MapPinModel, at index: Int? = nil, to model: MapModel) {
        let validatedIndex: Int
        if let index {
            validatedIndex = min(max(0, index), model.mapPins.count)
        } else {
            validatedIndex = model.mapPins.count
        }
        model.mapPins.insert(pin, at: validatedIndex)
        save(updated: model, message: String(localized: "Added pin").localizedString)
    }

    @MainActor
    func copy(pinIds: [UUID], itemId: UUID) {
        pinIds.forEach { copy(pinId: $0, itemId: itemId) }
    }

    @MainActor
    func copy(pinId: UUID, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        let duplicate = editModel[MapPinId.id, pinId].duplicate()
        editModel.mapPins.append(duplicate)
        let name = String(duplicate.name.prefix(16))
        save(updated: editModel, message: String(localized: "Copy pin \(name)").localizedString)
    }

    @MainActor
    func remove(pinIds: [UUID], itemId: UUID) {
        pinIds.forEach { remove(pinId: $0, itemId: itemId) }
    }

    @MainActor
    func remove(pinId: UUID, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        guard let index = editModel.mapPins.firstIndex(where: { $0.id == pinId }) else { return }
        editModel.mapPins.remove(at: index)
        save(updated: editModel, message: String(localized: "Remove pin").localizedString)
    }

    @MainActor
    func move(pinId: UUID, up: Bool, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        guard let index = editModel.mapPins.firstIndex(where: { $0.id == pinId }) else { return }
        if up {
            guard index > 0 else { return }
            editModel.mapPins.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
        } else {
            guard index < editModel.mapPins.count - 1 else { return }
            editModel.mapPins.move(fromOffsets: IndexSet(integer: index + 1), toOffset: index)
        }
        let title = up ? String(localized: "Move pin up") : String(localized: "Move pin down")
        save(with: title.localizedString)
    }
    
    @MainActor
    func move(pinFrom: IndexSet, to: Array<UUID>.Index, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        editModel.mapPins.move(fromOffsets: pinFrom, toOffset: to)
        save(with: String(localized: "Reorder pins").localizedString)
    }

    @MainActor
    func replacePinData(pinId: UUID, with valueId: UUID, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        let name = root.characterRoot.linkController.name(for: valueId)
        let photoId = root.characterRoot.valueGameControllable.imageIds(for: valueId).randomElement()
        var pin = editModel[MapPinId.id, pinId]
        pin.name = name
        pin.photoId = photoId
        editModel[MapPinId.id, pinId] = pin
        save(with: String(localized: "Updated pin from charakter").localizedString)
    }
}

// MARK: - Quick & Special Editors

extension EditController {
    // MARK: monster
    @MainActor
    func addMonsters(map: MapModel, entryId: UUID?, location: CGPoint?, monsters: [ItemRowModel], number: Int) {
        addMonsters(to: map, entryId: entryId, location: location, monsters: monsters, number: number)
    }

    @MainActor
    private func addMonsters(to model: MapModel, entryId: UUID?, location: CGPoint?, monsters: [ItemRowModel], number: Int) {
        let pinNumber = min(max(1, number), 25)
        
        var pins: [MapPinModel] = []
        for _ in 0..<pinNumber {
            pins.append(contentsOf: monsters.map { monster in
                MapPinModel(id: UUID(), name: root.characterRoot.linkController.name(for: monster.itemId), color: .random, photoId: root.characterRoot.valueGameControllable.imageIds(for: monster.itemId).randomElement(), location: location ?? .zero, size: .normal, isShown: true)
            })
        }

        if let entryId {
            //model[entryId].content.append(values)
            if location == nil {
                pins = calculateLocations(model: model, for: pins, entryId: entryId)
            }
        }
        pins.forEach { pin in
            add(pin: pin, to: model)
        }
    }

    private func calculateLocations(model: MapModel, for pins: [MapPinModel], entryId: UUID) -> [MapPinModel] {
        let pinScale = model.pinScale
        let entry = model[entryId]
        var leftCenter = CGPoint(x: entry.xOffset + entry.size.width / 4, y: entry.yOffset + entry.size.height / 2)
        return pins.map { pin in
            var changedPin = pin
            if changedPin.location == .zero {
                changedPin.location = leftCenter
                leftCenter = leftCenter + changedPin.size.size.width * pinScale + 5
            }
            return changedPin
        }
    }

    // MARK: HexGrid
    @MainActor
    func isHexMap(for item: MapModel) -> Bool {
        item.entries.contains(where: { $0.isHexGrid })
    }

    @MainActor
    func toggleHexMap(for item: MapModel) -> Bool {
        let isHexGrid = isHexMap(for: item)
        if isHexGrid {
            item.entries.removeAll { $0.isHexGrid }
            item.hexMapScale = 0
        } else {
                createHexMap(model: item, hexMapScale: max(0, item.hexMapScale))
        }
        return !isHexGrid
    }

    @MainActor
    func createHexMap(model: MapModel, hexMapScale: Double = 0) {
        let size = initHexGridSize(model: model, size: hexMapScale)
        model.hexMapScale = size
        let entries = calculateGrid(for: size, in: CGRect(origin: .zero, size: CGSize(width: model.width, height: model.height)))
        replaceHexGrid(entries: entries, in: model)
    }

    @MainActor
    private func initHexGridSize(model: MapModel, size: Double) -> Double {
        guard size < 10 else { return size }
        let wScale = model.width / (12 * sqrt(3))
        let hScale = model.height / (12 * (3/2))
        return max(wScale, hScale)
    }

    @MainActor
    private func replaceHexGrid(entries: [MapEntryModel], in model: MapModel) {
        model.entries.removeAll(where: { $0.isHexGrid })
        model.entries.append(contentsOf: entries)
    }

    private func calculateGrid(for size: Double, in rectSize: CGRect) -> [MapEntryModel] {
        let hexWidth = sqrt(3) * size
        let hexHeight = 2 * size
        let columns = Int((rectSize.width + (hexWidth / 2)) / hexWidth) + 1
        let rows = Int((rectSize.height + size / 2) / (3 * size / 2)) + 1

        var hexa: [MapEntryModel] = []
        for row in 0 ..< rows {
            let offsetY = Double(row) * hexHeight - (Double(row) * size / 2)
            let offsetRow = ((row % 2) != 0) ? -(hexWidth / 2) : 0
            for col in 0 ..< columns {
                let offsetX = Double(col) * hexWidth + offsetRow
                let coordinates = calculateHex(at: CGPoint(x: offsetX, y: offsetY), maxPoint: CGPoint(x: rectSize.width, y: rectSize.height), size: size)
                hexa.append(MapEntryModel(id: UUID(), name: "\(col) - \(row)", content: "", coordinates: coordinates, isHexGrid: true, displayState: DisplayStateMask.groupHidden.rawValue))
            }
        }
        return hexa
    }

    private func calculateHex(at offset: CGPoint, maxPoint: CGPoint, size: Double) -> [CGPoint] {
        let width = sqrt(3) * size
        let height = 2 * size

        let Point1 = CGPoint(x: min(max(offset.x, 0), maxPoint.x), y: min(max(offset.y, 0), maxPoint.y))
        let Point2 = CGPoint(x: min(max(offset.x + width / 2, 0), maxPoint.x), y: min(max(offset.y - height / 4, 0), maxPoint.y))
        let Point3 = CGPoint(x: min(max(offset.x + width, 0), maxPoint.x), y: min(max(offset.y, 0), maxPoint.y))
        let Point4 = CGPoint(x: min(max(offset.x + width, 0), maxPoint.x), y: min(max(offset.y + size, 0), maxPoint.y))
        let Point5 = CGPoint(x: min(max(offset.x + width / 2, 0), maxPoint.x), y: min(max(offset.y + 3 * height / 4, 0), maxPoint.y))
        let Point6 = CGPoint(x: min(max(offset.x, 0), maxPoint.x), y: min(max(offset.y + size, 0), maxPoint.y))

        return [Point1, Point2, Point3, Point4, Point5, Point6]
    }
}

extension EditController {
    @MainActor func merge(modelId: UUID, entries: [MapEntryModel], recoverEntries: [ItemRowModel]?) async -> [ItemRowModel] {
        guard let item = editModel(for: modelId) else { return [] }
        var newEntries = entries.map { entry in
            var foundEntry = item.entries.first(where: { $0.name == entry.name })
            foundEntry?.content = entry.content
            return foundEntry ?? entry
        }
        let removedIds = Set(item.entries.map { $0.id }).subtracting(newEntries.map { $0.id })
        let module = itemController.config.module
        let itemRowModels = removedIds.map { ItemRowModel(itemId: item.id, entryId: $0, typeId: module) }

        var effectedLinks = true
        for itemRowModel in itemRowModels {
            if !itemController.usedLinks(for: itemRowModel).isEmpty {
                effectedLinks = false
                break;
            }
        }
        if recoverEntries != nil || effectedLinks {
            if let recoverEntries {
                newEntries.append(contentsOf: recoverEntries.compactMap { $0.entryId }.map { item[$0] })
            }
            item.entries = newEntries
            save(with: String(localized: "Entries replaced").localizedString)
            return []
        }
        return itemRowModels
    }

    @MainActor
    func replace(itemId: UUID, with entries: [MapEntryModel]) {
        guard let model = itemController.itemSync(for: itemId) else { return }
        model.entries.enumerated().forEach { index, entry in
            guard index < entries.count else { return }
            let linkEntry = entries[index]
            guard entry.content != linkEntry.content else { return }
            var replacedEntry = entry
            replacedEntry.content = linkEntry.content
            model[replacedEntry.id] = replacedEntry
        }
    }

    @MainActor
    func scan(itemId: UUID, with anotherIds: [UUID]?, module: NetworkModules, caseInsensitive: Bool, words: Bool) -> [MapEntryModel] {
        guard let anotherIds else {
            let otherEntries: [LinkEntryModel]
            switch module {
            case .dice:
                otherEntries = root.diceRoot.linkController.link(for: .table)
            case .table:
                otherEntries = root.tableRoot.linkController.link(for: .map)
            case .value:
                otherEntries = root.characterRoot.linkController.link(for: .map)
            default:
                otherEntries = root.linkController.link(for: .map)
            }
            return scan(itemId: itemId, with: otherEntries, caseInsensitive: caseInsensitive, words: words)
        }

        let otherEntries: [LinkEntryModel] = anotherIds.flatMap { anotherId in
            switch module {
            case .dice:
                return root.diceRoot.linkController.linkEntries(for: anotherId)
            case .map:
                return root.linkController.linkEntries(for: anotherId)
            case .table:
                return root.tableRoot.linkController.linkEntries(for: anotherId)
            case .value:
                return root.characterRoot.linkController.linkEntries(for: anotherId)
            default:
                return []
            }
        }
        return scan(itemId: itemId, with: otherEntries, caseInsensitive: caseInsensitive, words: words)
    }

    @MainActor
    func scan(itemId: UUID, with linkEntries: [LinkEntryModel], caseInsensitive: Bool, words: Bool) -> [MapEntryModel] {
        guard let entries = itemController.itemSync(for: itemId)?.entries else { return [] }
        return entries.map { entry in
            var replacedEntry = entry
            linkEntries.forEach { linkEntry in
                replacedEntry = scanReplace(entry: replacedEntry, linkEntry: linkEntry, getLink: { $0.content }, setLink: { var result = $1; result.content = $0; return result }, caseInsensitive: caseInsensitive, words: words)
            }
            return replacedEntry
        }
    }
}
