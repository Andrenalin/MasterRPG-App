// @copyright André Trettin

import CharacterRPG
import CoreRPG
import Foundation
#if !os(tvOS)
import GeneratorRPG
#endif
import PhotoRPG
import SwiftUI

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
    @MainActor init(root: MapRootModel, itemController: ItemController, linkController: LinkController, sheetController: SheetController, tagController: TagController) {
        self.root = root

        self.tagController = tagController
        self.itemController = itemController
        let sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        let editorModel = ItemEditorModel(sheetEditorModel: sheetEditorModel)
        self.editorModel = editorModel
        self.mapEditModel = MapEditModel()
    }

    let root: MapRootModel

    let itemController: ItemController
    let tagController: TagController
    let editorModel: ItemEditorModel
    let mapEditModel: MapEditModel
}

struct LinkMapModuleTransferable: LinkDataTransferable {
    let module: NetworkModules
    let itemId: UUID
    let entryId: UUID?
    let name: String
    let isMove: Bool

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

    public var linkModules: [NetworkModules] { [.audio, .value, .dice, .map, .pdf, .photo, .table] }
    
    public func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        MapEditorRoute.linkSelection(itemRowModel)
    }
    
    public func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool {
        // Split complex expression for faster type-checking
        let isValueWithoutEntry: Bool = (module == .value && entryId == nil)
        let isTableWithoutEntry: Bool = (module == .table && entryId == nil)
        let isSimpleModule: Bool = (module == .audio || module == .dice || module == .map || module == .pdf || module == .photo)

        return isSimpleModule || isValueWithoutEntry || isTableWithoutEntry
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
        MasterRPGTips.recordContentLinked()
    }
    
    public var thumbnailEntryViewType: ThumbnailEntryViewType { .photo }
    public var additioanlEnrtryViewType: AdditionalEntryViewType { .custom }

    @MainActor public func additionalRowView(for source: ItemRowModel, entry: any EntryDataAccessable, textModel: LinkHighlightTextModel?) -> AnyView {
        AnyView(AddtionalEntryRow(source: source, entry: entry).equatable())
    }

    func create(name: String, content: String) -> MapEntryModel {
        MapEntryModel(id: UUID(), name: name, content: content, coordinates: [])
    }
        
    func editEntries(for item: MapModel) -> [MapEntryModel] {
        item.entries.filter { !$0.isHexGrid }
    }
    
    public func quickEditorDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        MapEditorRoute.quickEditor(itemRowModel.itemId)
    }
}

// MARK: - AI Extraction

#if !os(tvOS)
extension EditController {
    @MainActor func applyExtractedContent(_ content: TableSummaryAnalysis, to itemId: UUID, selection: TextSummaryPropertySelection) {
        if selection.applyTitle {
            reset(name: content.title, itemId: itemId)
        }
        if selection.applyDescription {
            reset(description: content.description, itemId: itemId)
        }
        if selection.applyTags {
            reset(tags: content.tags, itemId: itemId)
        }
    }
}
#endif

// MARK: - New Editor Functions

extension EditController {
    @MainActor func add(photoId: UUID?, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.photoId = photoId
        save(updated: item, message: String(localized: "Change Photo", bundle: .module).localizedString)
    }
    
    @MainActor func reset(borderThickness: Double, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        let updatedBorderThickness: CGFloat = CGFloat(borderThickness)
        if item.displayConfig.borderThickness != updatedBorderThickness {
            item.displayConfig.borderThickness = updatedBorderThickness
            save(updated: item, message: String(localized: "Change border thickness", bundle: .module).localizedString)
        }
    }

    @MainActor func reset(hasBorder: Bool, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        if item.displayConfig.hasBorder != hasBorder {
            item.displayConfig.hasBorder = hasBorder
            save(updated: item, message: String(localized: "toggle border", bundle: .module).localizedString)
        }
    }

    @MainActor func reset(borderColor: Color, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        if item.displayConfig.border.color != borderColor {
            item.displayConfig.border.color = borderColor
            save(updated: item, message: String(localized: "Change border color", bundle: .module).localizedString)
        }
    }
    
    @MainActor func reset(coverColor: Color, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        if item.displayConfig.color != coverColor {
            item.displayConfig.color = coverColor
            save(updated: item, message: String(localized: "Change cover color", bundle: .module).localizedString)
        }
    }
    
    @MainActor func reset(tileCoordinates: [CGPoint], itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        if item.displayConfig.tileCoordinates != tileCoordinates {
            item.displayConfig.tileCoordinates = tileCoordinates
            save(updated: item, message: String(localized: "Change tile coordinates", bundle: .module).localizedString)
        }
    }
}

extension EditController {
    @MainActor
    func resetImageSize(photoId: UUID, updateModel: MapModel, save: Bool = false) async {
        if let (image, degrees) = await root.photoRoot.fetchPhotoImage(for: photoId, useGame: false) {
            let size = image.size
            updateModel.resetImage(with: photoId, size: size, degrees: degrees)
            if save {
                itemController.replace(model: updateModel, isInsert: false)
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

        itemController.replace(model:createMap, isInsert: true)
        return createMap.id
    }

    @MainActor func validateBeforeSave(model: MapModel) {
        let itemId = model.id
        let changedEntryIds = model.entries.compactMap { entry in
            itemController.itemOrEmpty(for: itemId)[entry.id].coordinates != entry.coordinates ? entry.id : nil
        }
        // Intentionally fire-and-forget: `validateBeforeSave` is a synchronous protocol
        // hook called right before `saveChanges`, and this is just room-thumbnail cache
        // invalidation — a render reading the cache in the brief window before this Task
        // completes can show a stale thumbnail, which self-corrects on the next redraw.
        // Not worth making the whole save path `async` for. See CODE_AUDIT_EditItem §3.5.
        Task {
            for entryId in changedEntryIds {
                await root.cacheController?.remove(itemId: entryId)
            }
        }
    }
}

// MARK: - Entry Boundary Rescaling

extension EditController {
    /// Largest x extent of all room coordinates relative to the map width, clamped at 1.0 (map image boundary).
    @MainActor func maxWidthRatio(for model: MapModel) -> Double {
        maxRatio(in: model, dimension: model.width) { $0.x }
    }

    /// Largest y extent of all room coordinates relative to the map height, clamped at 1.0 (map image boundary).
    @MainActor func maxHeightRatio(for model: MapModel) -> Double {
        maxRatio(in: model, dimension: model.height) { $0.y }
    }

    /// True when a room coordinate falls outside the map's stored width or height — the
    /// persisted map size is out of sync with its overlay content (rooms/pins render
    /// beyond the map image). `maxWidthRatio`/`maxHeightRatio` clamp at 1.0 and so can't
    /// surface this by themselves; this is the dedicated detection the boundary-fix
    /// sliders key their visibility off of.
    @MainActor func isMapSizeOutOfSync(for model: MapModel) -> Bool {
        exceedsDimension(in: model, dimension: model.width) { $0.x }
            || exceedsDimension(in: model, dimension: model.height) { $0.y }
    }

    @MainActor func rescale(maxWidthRatio: Double, in model: MapModel) {
        rescaleCoordinates(in: model, ratio: maxWidthRatio, dimension: model.width, axis: \.x)
    }

    @MainActor func rescale(maxHeightRatio: Double, in model: MapModel) {
        rescaleCoordinates(in: model, ratio: maxHeightRatio, dimension: model.height, axis: \.y)
    }

    @MainActor private func maxRatio(in model: MapModel, dimension: CGFloat, value: (CGPoint) -> CGFloat) -> Double {
        guard dimension > 0 else { return 1.0 }
        let maxValue = editEntries(for: model)
            .flatMap { $0.coordinates }
            .map(value)
            .max() ?? 0
        guard maxValue > 0 else { return 1.0 }
        return min(1.0, maxValue / dimension)
    }

    @MainActor private func exceedsDimension(in model: MapModel, dimension: CGFloat, value: (CGPoint) -> CGFloat) -> Bool {
        guard dimension > 0 else { return false }
        let maxValue = editEntries(for: model)
            .flatMap { $0.coordinates }
            .map(value)
            .max() ?? 0
        return maxValue > dimension
    }

    @MainActor private func rescaleCoordinates(in model: MapModel, ratio: Double, dimension: CGFloat, axis: WritableKeyPath<CGPoint, CGFloat>) {
        guard dimension > 0, ratio > 0 else { return }
        let currentMax = editEntries(for: model)
            .flatMap { $0.coordinates }
            .map { $0[keyPath: axis] }
            .max() ?? 0
        guard currentMax > 0 else { return }

        // Scale from the real extent, so entries beyond the image boundary shrink back into it.
        let factor = (ratio * dimension) / currentMax
        guard factor != 1.0 else { return }

        model.entries = model.entries.map { entry in
            guard !entry.isHexGrid else { return entry }
            var scaledEntry = entry
            scaledEntry.coordinates = scaledEntry.coordinates.map { point in
                var scaledPoint = point
                scaledPoint[keyPath: axis] = scaledPoint[keyPath: axis] * factor
                return scaledPoint
            }
            return scaledEntry
        }
        // Pins follow the rooms they are placed in, same as resetEntrySize
        model.mapPins = model.mapPins.map { pin in
            var scaledPin = pin
            scaledPin.location[keyPath: axis] = scaledPin.location[keyPath: axis] * factor
            return scaledPin
        }
    }
}

// MARK: - Edit Pins

extension EditController {
    @MainActor func add(pin: MapPinModel, at index: Int? = nil, to model: MapModel) {
        let validatedIndex: Int
        if let index {
            validatedIndex = min(max(0, index), model.mapPins.count)
        } else {
            validatedIndex = model.mapPins.count
        }
        model.mapPins.insert(pin, at: validatedIndex)
        save(updated: model, message: String(localized: "Added pin", bundle: .module).localizedString)
    }

}

// MARK: - Monster

extension EditController {
    @MainActor func addMonsters(map: MapModel, entryId: UUID?, location: CGPoint?, monsters: [ItemRowModel], number: Int) {
        addMonsters(to: map, entryId: entryId, location: location, monsters: monsters, number: number)
    }

    @MainActor private func addMonsters(to model: MapModel, entryId: UUID?, location: CGPoint?, monsters: [ItemRowModel], number: Int) {
        var pins = MapPinPlacement.spawnPins(monsters: monsters, count: number, location: location, characterRoot: root.characterRoot)

        if let entryId, location == nil {
            pins = MapPinPlacement.cascade(pins: pins, in: model[entryId], pinScale: model.pinScale)
        }
        pins.forEach { pin in
            add(pin: pin, to: model)
        }
    }
}

// MARK: - HexGrid

extension EditController {
    @MainActor func isHexMap(for item: MapModel) -> Bool {
        item.entries.contains(where: { $0.isHexGrid })
    }

    @MainActor func toggleHexMap(for item: MapModel) -> Bool {
        let isHexGrid = isHexMap(for: item)
        if isHexGrid {
            item.entries.removeAll { $0.isHexGrid }
            item.hexMapScale = 0
        } else {
                createHexMap(model: item, hexMapScale: max(0, item.hexMapScale))
        }
        return !isHexGrid
    }

    @MainActor func createHexMap(model: MapModel, hexMapScale: Double = 0) {
        let size = MapHexGridGeometry.initialSize(for: model, requestedSize: hexMapScale)
        model.hexMapScale = size
        let entries = MapHexGridGeometry.grid(for: size, in: CGRect(origin: .zero, size: CGSize(width: model.width, height: model.height)))
        MapHexGridGeometry.replaceGrid(entries, in: model)
    }
}

extension EditController {
    @MainActor func merge(itemId: UUID, entries: [MapEntryModel]) -> [MapEntryModel] {
        guard let item = editModel(for: itemId) else { return entries }
        return entries.map { entry in
            var foundEntry = item.entries.first(where: { $0.name == entry.name })
            foundEntry?.content = entry.content
            return foundEntry ?? entry
        }
    }

    /// `forceSave` is intentionally not threaded through: map changes made while a
    /// game is running must always stay in game memory, even when this is invoked
    /// from the standalone item editor — matching every other mutation in this
    /// controller (e.g. `addMonsters`), which relies on the same `isGameMode` gate.
    @MainActor func merge(itemId: UUID, entries: [MapEntryModel], recoverEntries: [ItemRowModel]?, forceSave: Bool) -> [ItemRowModel] {
        guard let item = editModel(for: itemId) else { return [] }
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
            if !linkRegisterController.used(for: itemRowModel).isEmpty {
                effectedLinks = false
                break;
            }
        }
        if recoverEntries != nil || effectedLinks {
            if let recoverEntries {
                newEntries.append(contentsOf: recoverEntries.compactMap { $0.entryId }.map { item[$0] })
            }
            item.entries = newEntries
            save(updated: item, message: String(localized: "Entries replaced", bundle: .module).localizedString)
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
}
