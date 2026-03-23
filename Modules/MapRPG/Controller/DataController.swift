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
            relationshipKeyPaths: [
                "entryModels",
                "entryModels.coordinateModels",
                "mapPinModels",
                "mapPinModels.location",
                "displayConfig",
                "displayConfig.tileCoordinateModels"
            ]
        )
        self.token = token
    }

    let dataController: CoreDataController<MapModel, RPGMap>
    let token: String
}

extension DataController: CoreDataPersistable {
    // MARK: model -> viewlmodel

    func mapViewModel(_ model: RPGMap, token: String) -> MapModel {
        MapModel(
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

    // MARK: viewmodel -> model

    func mapModel(_ viewModel: MapModel, into model: RPGMap) {
        model.uuid <=> viewModel.id
        model.name <=> viewModel.name_.rawValue
        model.information <=> viewModel.description_.rawValue
        model.tags <=> viewModel.tags_.rawValue
        model.mapCategory <=> viewModel.category_.rawValue
        model.displayState <=> Int32(viewModel.displayState)
        unequalSet(lhs: &model.entriesUpdate, rhs: viewModel.entries_.$update.rawValue) {
            model.entryModels = viewModel.entries.enumerated().map {
                let entry = model.entryOrNew(for: $1.id)
                self.map($1, into: entry, index: $0)
                return entry
            }
        }
        unequalSet(lhs: &model.displayConfigUpdate, rhs: viewModel.displayConfig_.$update.rawValue) {
            let displayConfig = model.displyConfigOrNew(for: viewModel.id)
            self.map(viewModel.displayConfig, into: displayConfig)
            model.displayConfig = displayConfig
        }
        unequalSet(lhs: &model.mapUpdate, rhs: viewModel.photoId_.$update.rawValue) {
            model.photoUUID = viewModel.photoId
            model.width = viewModel.width
            model.height = viewModel.height
        }
        unequalSet(lhs: &model.mapPinsUpdate, rhs: viewModel.mapPins_.$update.rawValue) {
            model.mapPinModels = viewModel.mapPins.enumerated().map {
                let entry = model.mapPinOrNew(for: $1.id)
                self.map($1, into: entry, index: $0)
                return entry
            }
        }
        model.pinScale <=> viewModel.pinScale
        model.hexMapScale <=> viewModel.hexMapScale_.rawValue
        model.parentId <=> viewModel.parentId
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
            model.coordinateModels = viewModel.coordinates.enumerated().map {
                let coordinate = model.coordinateOrNew(for: UUID())
                self.map($1, into: coordinate, index: $0)
                return coordinate
            }
        }
    }

    private func map(_ viewModel: CGPoint, into model: RPGPosition, index: Int) {
        model.uuid = UUID()
        model.xPos = viewModel.x
        model.yPos = viewModel.y
        model.index = Int16(index)
    }

    private func map(_ viewModel: DisplayConfigModel, into model: RPGDisplayConfig) {
        model.uuid = viewModel.id
        model.color = JSONString.encode(value: CodableColor(viewModel.color)) ?? ""

        model.borderColor = JSONString.encode(value: CodableColor(viewModel.borderColor))
        model.borderThickness = viewModel.borderThickness
        model.tileCoordinateModels = viewModel.tileCoordinates.enumerated().map {
            let coordinate = model.coordinateOrNew(for: UUID())
            map($1, into: coordinate, index: $0)
            return coordinate
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
