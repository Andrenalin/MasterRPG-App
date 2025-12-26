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
    var contentLinks: [UUID: LinkReplaceController] = [:]
    
    let photoSelectionModel = SelectionModel(id: UUID(), filter: .map)
    let pdfSelectionModel = SelectionModel(id: UUID(), filter: .all)
    
    let selectionAudio: ItemSelectionModel = ItemSelectionModel()
    let selectionCharacter: ItemSelectionModel = ItemSelectionModel()
    let selectionDice: ItemSelectionModel = ItemSelectionModel()
    let selectionPdf: ItemSelectionModel = ItemSelectionModel()
    let selectionPhoto: ItemSelectionModel = ItemSelectionModel()
    let selectionTable: ItemSelectionModel = ItemSelectionModel()

    func resetCurrentModel() {
        contentLinks = [:]
    }
}

struct EditController: Sendable {
    @MainActor init(root: MapRootModel, itemController: ItemController, linkRegisterControllable: LinkRegisterControllable, currentListItem: ItemRowTreeModel?, currentModel: (ModelType)?) {
        self.root = root
        
        self.itemController = itemController
        self.linkRegisterControllable = linkRegisterControllable

        self.editorModel = ItemEditorModel(currentListItem: currentListItem, currentModel: currentModel)
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
    
    public func linkSelectionDestination(for entryId: UUID) -> any NavigationDestination {
        EditorRoute.linkSelection(entryId)
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
    
    @MainActor public func add(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, destinationEntryId: UUID) {
        guard canAddLink(module: module, entryId: entryId) else { return }
        
        switch module {
        case .audio, .dice, .map, .pdf, .photo, .table:
            addLinkInEntry(link: link, module: module, itemId: itemId, entryId: entryId, destinationEntryId: destinationEntryId)
        case .value:
            addMonsters(to: model, entryId: destinationEntryId, location: nil, monsters: [ItemRowModel(itemId: itemId, typeId: .value)], number: 1)
            addLinkInEntry(link: link, module: module, itemId: itemId, entryId: entryId, destinationEntryId: destinationEntryId)
        default:
            return
        }
    }
    
    public var thumbnailEntryViewType: ThumbnailEntryViewType { .photo }
    public var additioanlEnrtryViewType: AdditionalEntryViewType { .custom }

    @MainActor public func additionalRowView(for entryId: UUID) -> AnyView {
        AnyView(AddtionalEntryRow(entryId: entryId).equatable())
    }

    func create(name: String, content: String) -> MapEntryModel {
        MapEntryModel(id: UUID(), name: name, content: content, coordinates: [])
    }
    
    @MainActor
    func resetCurrentModel() {
        mapEditModel.resetCurrentModel()
    }
    
    @MainActor func didSetModel() {
        guard let id = editorModel.currentItemId else { return }
        
        if mapEditModel.photoSelectionModel.id != id {
            mapEditModel.photoSelectionModel.id = id
            if mapEditModel.photoSelectionModel.currentValue != model.photoId {
                mapEditModel.photoSelectionModel.currentValue = model.photoId
            }
        }
        if mapEditModel.pdfSelectionModel.id != id {
            mapEditModel.pdfSelectionModel.id = id
        }
    }
    
    func editEntries(for item: MapModel) -> [MapEntryModel] {
        item.entries.filter { !$0.isHexGrid }
    }
    
    @MainActor
    func submitChanges() {
        mapEditModel.resetCurrentModel()
    }
}

// MARK: - New Editor Functions

extension EditController {
    @MainActor func add(photoId: UUID?) {
        model.photoId = photoId
        save(with: String(localized: "Change Photo").localizedString)
    }
}

extension EditController {
    @MainActor 
    func selection(for module: NetworkModules) -> [ItemRowModel] {
        guard module == .photo else { return [] }
        if let id = model.photoId {
            return [ItemRowModel(itemId: id, typeId: .photo)]
        }
        return []
    }

    @MainActor
    func toggle(for module: NetworkModules, itemRowModel: ItemRowModel) async {
        guard module == .photo else { return }
        await resetImageSize(photoId: itemRowModel.itemId, updateModel: model)
        save(with: String(localized: "Change Photo").localizedString)
    }

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
        if model.name == name && model.photoId == photoId {
            return model.id
        }
        if let itemId = itemController.itemDataModel.items.first(where: { itemController.itemSync(for: $0)?.name == name && itemController.itemSync(for: $0)?.photoId == photoId }) {
            return itemId
        }
        let createMap = MapModel(id: UUID(), name: name, degrees: 0)
        await resetImageSize(photoId: photoId, updateModel: createMap)
        createHexMap(model: createMap, hexMapScale: 0)

        itemController.replace(model:createMap, isInsert: true, shouldRepairLinks: true)
        return createMap.id
    }

    @MainActor func validateBeforeSave() {
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

// MARK: - Selection

extension EditController {
    @MainActor
    func selectedPinPhoto(for pinId: UUID) -> [ItemRowModel] {
        if let photoId = model[MapPinId.id, pinId].photoId {
            return [ItemRowModel(itemId: photoId, typeId: .photo)]
        }
        return []
    }
    
    @MainActor
    func toggleSelectedPinPhoto(for pinId: UUID, selection: ItemRowModel) {
        if model[MapPinId.id, pinId].name.isEmpty {
            model[MapPinId.id, pinId].name = root.photoRoot.itemControllable.nameSync(itemId: selection.itemId)
        }
        model[MapPinId.id, pinId].photoId = selection.itemId
        save(with: String(localized: "Change pin photo").localizedString)
    }
}

// MARK: - Link Editor

extension EditController {
    @MainActor func contentEditLink(for entryId: UUID) -> LinkReplaceController {
        guard let controller = mapEditModel.contentLinks[entryId] else {
            let controller = LinkReplaceController {
                model[entryId].content
            } setter: {
                update(entryId: entryId, content: $0)
            }
            mapEditModel.contentLinks[entryId] = controller
            return controller
        }
        return controller
    }
    
    @MainActor
    func updateContent(_ content: String, for entryId: UUID) {
        if let contentLink = mapEditModel.contentLinks[entryId] {
            contentLink.editValue.wrappedValue = content
        } else {
            update(entryId: entryId, content: content)
        }
        save(with: String(localized: "Add link").localizedString)
    }
    
    @MainActor func update(entryId: UUID, content: String) {
        model[entryId].content = content
        editorModel.cacheItemListModel.reset(cacheType: .content, itemId: entryId, text: content)
        editorModel.cacheItemListModel.reset(cacheType: .row, itemId: entryId, text: model[entryId].textLinkContent)
    }
}

// MARK: - Edit Pins

extension EditController {
    @MainActor
    func addNewPin(at index: Int? = nil) -> MapEntryModel.ID {
        let pin = MapPinModel(id: UUID(), name: String(localized: "New Pin").localizedString, color: .random, photoId: nil, location: .zero, size: .normal, isShown: true, players: [], timeInterval: 0)
        add(pin: pin, at: index)
        editorModel.activateDetailEditMode = false
        return pin.id
    }

    @MainActor
    func add(pin: MapPinModel, at index: Int? = nil) {
        add(pin: pin, at: index, to: model)
    }

    func add(pin: MapPinModel, at index: Int? = nil, to model: MapModel) {
        let validatedIndex: Int
        if let index {
            validatedIndex = min(max(0, index), model.mapPins.count)
        } else {
            validatedIndex = model.mapPins.count
        }
        model.mapPins.insert(pin, at: validatedIndex)
    }

    @MainActor
    func copy(pinIds: [UUID]) {
        pinIds.forEach { copy(pinId: $0, shouldSave: false) }
        save(with: String(localized: "Copy pins").localizedString)
    }

    @MainActor
    func copy(pinId: UUID, shouldSave: Bool = true) {
        let duplicate = model[MapPinId.id, pinId].duplicate()
        model.mapPins.append(duplicate)
        if shouldSave {
            let name = String(duplicate.name.prefix(16))
            save(with: String(localized: "Copy pin \(name)").localizedString)
        }
    }

    @MainActor
    func remove(pinIds: [UUID]) {
        pinIds.forEach { remove(pinId: $0, shouldSave: false) }
        save(with: String(localized: "Remove pins").localizedString)
    }

    @MainActor
    func remove(pinId: UUID, shouldSave: Bool = true) {
        guard let index = model.mapPins.firstIndex(where: { $0.id == pinId }) else { return }
        model.mapPins.remove(at: index)
        if shouldSave {
            save(with: String(localized: "Remove pin").localizedString)
        }
    }

    @MainActor
    func move(pinId: UUID, up: Bool) {
        guard let index = model.mapPins.firstIndex(where: { $0.id == pinId }) else { return }
        if up {
            guard index > 0 else { return }
            model.mapPins.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
        } else {
            guard index < model.mapPins.count - 1 else { return }
            model.mapPins.move(fromOffsets: IndexSet(integer: index + 1), toOffset: index)
        }
        let title = up ? String(localized: "Move pin up") : String(localized: "Move pin down")
        save(with: title.localizedString)
    }
    
    @MainActor
    func move(pinFrom: IndexSet, to: Array<UUID>.Index) {
        model.mapPins.move(fromOffsets: pinFrom, toOffset: to)
        save(with: String(localized: "Reorder pins").localizedString)
    }

    @MainActor
    func replacePinData(pinId: UUID, with valueId: UUID) {
        let name = root.characterRoot.linkController.name(for: valueId)
        let photoId = root.characterRoot.valueGameControllable.imageIds(for: valueId).randomElement()
        var pin = model[MapPinId.id, pinId]
        pin.name = name
        pin.photoId = photoId
        model[MapPinId.id, pinId] = pin
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
    func addMonsters(to entryId: UUID?, monsters: [ItemRowModel], number: Int) {
        addMonsters(to: model, entryId: entryId, location: nil, monsters: monsters, number: number)
    }

    @MainActor
    private func addMonsters(to model: MapModel, entryId: UUID?, location: CGPoint?, monsters: [ItemRowModel], number: Int) {
        //let values = monsters.map { root.characterRoot.linkController.generateLink(model: $0) }.joined(separator: ", ")

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
    func isHexMap(for externalModel: MapModel? = nil) -> Bool {
        let checkModel = externalModel ?? model
        return checkModel.entries.contains(where: { $0.isHexGrid })
    }

    @MainActor
    func toggleHexMap(for externalModel: MapModel? = nil) -> Bool {
        let isHexGrid = isHexMap(for: externalModel)
        if isHexGrid {
            if let externalModel {
                externalModel.entries.removeAll { $0.isHexGrid }
                externalModel.hexMapScale = 0
            } else {
                model.entries.removeAll { $0.isHexGrid }
                save(with: String(localized: "Remove hexgrid").localizedString)
            }
        } else {
            if let externalModel {
                createHexMap(model: externalModel, hexMapScale: max(0, externalModel.hexMapScale))
            } else {
                createHexMap(hexMapScale: max(0, model.hexMapScale))
            }
        }
        return !isHexGrid
    }

    @MainActor
    func createHexMap(hexMapScale: Double = 0) {
        createHexMap(model: model, hexMapScale: hexMapScale)
    }

    @MainActor
    func createHexMap(model: MapModel, hexMapScale: Double = 0) {
        let size = initHexGridSize(model: model, size: hexMapScale)
        model.hexMapScale = size
        let entries = calculateGrid(for: size, in: CGRect(origin: .zero, size: CGSize(width: model.width, height: model.height)))
        replaceHexGrid(entries: entries, in: model)
        if model.id == self.model.id {
            save(with: String(localized: "Change to hexgrid").localizedString)
        }
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

    // MARK: Generate Values
    @MainActor
    func generateValues() async {
        var parentId: UUID?
        let text = model.description
        for link in LinkReplaceController.links(for: text) {
            guard link.module == .table else { return }

            parentId = await root.characterRoot.linkController.generateItem(for: model.name, parentId: nil, tableId: link.itemId, entryId: link.entryId)
        }
        if parentId == nil {
            parentId = await root.characterRoot.linkController.generateItem(for: model.name, parentId: nil, tableId: nil, entryId: nil)
        }
        for entry in model.entries {
            let text = entry.content
            for link in LinkReplaceController.links(for: text) {
                guard link.module == .table else { return }
                _ = await root.characterRoot.linkController.generateItem(for: entry.name, parentId: parentId, tableId: link.itemId, entryId: link.entryId)
            }
        }
    }
}

extension EditController {
    @MainActor
    func merge(entries: [MapEntryModel], recoverEntries: [ItemRowModel]?) async -> [ItemRowModel] {
        let item = model
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
