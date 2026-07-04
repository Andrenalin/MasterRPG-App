// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData
import SwiftUI

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, batchContext: NSManagedObjectContext? = nil, token: String) {
        self.dataController = CoreDataController<MapModel, RPGMap>(
            context: context,
            batchContext: batchContext,
            // Core Data relationship names, not the Swift convenience wrappers
            // (entryModels etc.) — unknown key paths are silently ignored and
            // the prefetch never happens.
            relationshipKeyPaths: [
                "entries",
                "entries.coordinates",
                "mapPins",
                "mapPins.location",
                "displayConfig",
                "displayConfig.tileCoordinates"
            ]
        )
        self.token = token
    }

    let dataController: CoreDataController<MapModel, RPGMap>
    let token: String
}

extension DataController: CoreDataSnapshotPersistable {
    // MARK: managed object -> snapshot (context queue)

    @Sendable
    func mapSnapshot(_ model: RPGMap, token: String) -> MapSnapshot {
        MapSnapshot(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.mapCategory ?? "", defaultValue: ItemListCategory.dungeon),
            displayState: Int(model.displayState),
            entries: CRDTDataUpdate(wrappedValue: map(model.entryModels), update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())),
            displayConfig: CRDTDataUpdate(wrappedValue: map(model.displayConfig), update: CRDT(string: model.displayConfigUpdate ?? "", defaultValue: UUID())),
            photoId: CRDTDataUpdate(wrappedValue: model.photoUUID, update: CRDT(string: model.mapUpdate ?? "", defaultValue: UUID())),
            width: model.width,
            height: model.height,
            mapPins: CRDTDataUpdate(wrappedValue: map(model.mapPinModels), update: CRDT(string: model.mapPinsUpdate ?? "", defaultValue: UUID())),
            pinScale: model.pinScale,
            hexMapScale: CRDT(string: model.hexMapScale ?? "", defaultValue: 0.0),
            scale: 1,
            degrees: 0,
            parentId: model.parentId
        )
    }

    // MARK: snapshot -> managed object (context queue)

    @Sendable
    func applySnapshot(_ snapshot: MapSnapshot, into model: RPGMap) {
        model.uuid <=> snapshot.id
        model.name <=> snapshot.name.rawValue
        model.information <=> snapshot.description.rawValue
        model.tags <=> snapshot.tags.rawValue
        model.mapCategory <=> snapshot.category.rawValue
        model.displayState <=> Int32(snapshot.displayState)
        unequalSet(lhs: &model.entriesUpdate, rhs: snapshot.entries.$update.rawValue) {
            let oldEntries = model.entryModels
            let newEntries = snapshot.entries.wrappedValue.enumerated().map {
                let entry = model.entryOrNew(for: $1.id)
                self.map($1, into: entry, index: $0)
                return entry
            }
            model.entryModels = newEntries
            // The inverse rule is Nullify, so entries dropped from the relationship
            // would remain as orphaned rows (locally and in CloudKit) — delete them.
            // Deleting an entry cascades to its coordinates.
            let keptEntries = Set(newEntries.map(ObjectIdentifier.init))
            for entry in oldEntries where !keptEntries.contains(ObjectIdentifier(entry)) {
                model.managedObjectContext?.delete(entry)
            }
        }
        unequalSet(lhs: &model.displayConfigUpdate, rhs: snapshot.displayConfig.$update.rawValue) {
            let displayConfig = model.displyConfigOrNew(for: snapshot.id)
            self.map(snapshot.displayConfig.wrappedValue, into: displayConfig)
            model.displayConfig = displayConfig
        }
        unequalSet(lhs: &model.mapUpdate, rhs: snapshot.photoId.$update.rawValue) {
            model.photoUUID = snapshot.photoId.wrappedValue
            model.width = snapshot.width
            model.height = snapshot.height
        }
        unequalSet(lhs: &model.mapPinsUpdate, rhs: snapshot.mapPins.$update.rawValue) {
            let oldPins = model.mapPinModels
            let newPins = snapshot.mapPins.wrappedValue.enumerated().map {
                let entry = model.mapPinOrNew(for: $1.id)
                self.map($1, into: entry, index: $0)
                return entry
            }
            model.mapPinModels = newPins
            // The inverse rule is Nullify, so pins dropped from the relationship
            // would remain as orphaned rows (locally and in CloudKit) — delete them.
            // Deleting a pin cascades to its location.
            let keptPins = Set(newPins.map(ObjectIdentifier.init))
            for pin in oldPins where !keptPins.contains(ObjectIdentifier(pin)) {
                model.managedObjectContext?.delete(pin)
            }
        }
        model.pinScale <=> snapshot.pinScale
        model.hexMapScale <=> snapshot.hexMapScale.rawValue
        model.parentId <=> snapshot.parentId
    }


    // MARK: model <-> snapshot (MainActor)

    @MainActor
    func makeModel(from snapshot: MapSnapshot) -> MapModel {
        snapshot.makeModel()
    }

    @MainActor
    func makeSnapshot(from model: MapModel) -> MapSnapshot {
        MapSnapshot(model)
    }

    // MARK: - MapEntryModel

    private func map(_ model: [RPGMapEntry]) -> [MapEntryModel] {
        model.sorted { $0.index < $1.index }.map { map($0) }
    }

    private func map(_ model: RPGMapEntry) -> MapEntryModel {
        MapEntryModel(
            id: model.uuid ?? UUID(),
            name: CRDT(string: model.name ?? "", defaultValue: ""),
            content: CRDT(string: model.content ?? "", defaultValue: ""),
            coordinates: CRDTDataUpdate(wrappedValue: map(model.coordinateModels), update: CRDT(string: model.coordinatesUpdate ?? "", defaultValue: UUID())),
            isHexGrid: model.isHexGrid,
            isShown: model.isShown
        )
    }

    private func map(_ models: [RPGPosition]) -> [CGPoint] {
        models.sorted { $0.index < $1.index }.map { CGPoint(x: $0.xPos, y: $0.yPos) }
    }

    private func map(_ model: RPGDisplayConfig?) -> DisplayConfigModel {
        let color: CodableColor? = JSONString.decode(text: model?.color)
        return DisplayConfigModel(
            id: model?.uuid ?? UUID(),
            tileCoordinates: map(
                model?.tileCoordinateModels ?? []),
            color: color?.color ?? .black,
            border: map(border: model?.borderColor, thickness: model?.borderThickness ?? 0)
        )
    }

    private func map(border colorText: String?, thickness: CGFloat) -> DisplayBorderViewModel {
        guard let colorText else {
            return DisplayBorderViewModel(id: UUID(), thickness: 0)
        }
        let color: CodableColor? = JSONString.decode(text: colorText)

        return DisplayBorderViewModel(id: UUID(), thickness: thickness, color: color?.color ?? .clear)
    }

    private func map(_ model: [RPGMapPin]) -> [MapPinModel] {
        model.sorted { $0.index < $1.index }.map { map($0) }
    }

    private func map(_ model: RPGMapPin) -> MapPinModel {
        let color: CodableColor? = JSONString.decode(text: model.color)
        return MapPinModel(
            id: model.uuid ?? UUID(),
            name: model.name ?? "",
            color: color?.color ?? .red,
            photoId: model.photoUUID,
            location: CGPoint(x: model.location?.xPos ?? 0.0, y: model.location?.yPos ?? 0.0),
            size: MapPinModel.MapPinSize(rawValue: Int(model.size)) ?? .normal,
            isShown: model.isShown
        )
    }

    // MARK: viewmodel -> model

    private func map(_ viewModel: MapEntryModel, into model: RPGMapEntry, index: Int) {
        model.uuid = viewModel.id
        model.name = viewModel.$name.rawValue
        model.content = viewModel.$content.rawValue
        model.index = Int16(index)
        model.isHexGrid = viewModel.isHexGrid
        model.isShown = viewModel.isShown
        unequalSet(lhs: &model.coordinatesUpdate, rhs: viewModel.$coordinates.$update.rawValue) {
            // Positions carry no stable id (the old lookup passed a fresh UUID, so
            // every update created an all-new set and orphaned the previous rows via
            // the Nullify inverse). Reuse by index and delete the surplus instead.
            let oldCoordinates = model.coordinateModels
            model.coordinateModels = viewModel.coordinates.enumerated().map {
                let coordinate = $0 < oldCoordinates.count ? oldCoordinates[$0] : model.newCoordinate()
                self.map($1, into: coordinate, index: $0)
                return coordinate
            }
            for coordinate in oldCoordinates.dropFirst(viewModel.coordinates.count) {
                model.managedObjectContext?.delete(coordinate)
            }
        }
    }

    private func map(_ viewModel: CGPoint, into model: RPGPosition, index: Int) {
        // Keep the uuid stable on reused positions — rewriting it dirties every
        // row and forces a full CloudKit re-export of the whole coordinate set.
        if model.uuid == nil {
            model.uuid = UUID()
        }
        model.xPos = viewModel.x
        model.yPos = viewModel.y
        model.index = Int16(index)
    }

    private func map(_ viewModel: DisplayConfigModel, into model: RPGDisplayConfig) {
        model.uuid = viewModel.id
        model.color = JSONString.encode(value: CodableColor(viewModel.color)) ?? ""

        model.borderColor = JSONString.encode(value: CodableColor(viewModel.borderColor))
        model.borderThickness = viewModel.borderThickness
        // Same reuse-by-index pattern as entry coordinates — the old fresh-UUID
        // lookup orphaned the previous tile set on every update.
        let oldCoordinates = model.tileCoordinateModels
        model.tileCoordinateModels = viewModel.tileCoordinates.enumerated().map {
            let coordinate = $0 < oldCoordinates.count ? oldCoordinates[$0] : model.newCoordinate()
            map($1, into: coordinate, index: $0)
            return coordinate
        }
        for coordinate in oldCoordinates.dropFirst(viewModel.tileCoordinates.count) {
            model.managedObjectContext?.delete(coordinate)
        }
    }

    private func map(_ viewModel: MapPinModel, into model: RPGMapPin, index: Int) {
        model.uuid = viewModel.id
        model.name = viewModel.name
        model.color = JSONString.encode(value: CodableColor(viewModel.color)) ?? ""
        model.index = Int16(index)
        model.photoUUID = viewModel.photoId

        let coordinate = model.coordinateOrNew(for: UUID())
        map(viewModel.location, into: coordinate, index: 0)
        model.location = coordinate
        model.size = Int16(viewModel.size.rawValue)
        model.isShown = viewModel.isShown
    }
}
