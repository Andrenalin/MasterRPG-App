// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResources
import PhotoRPG

public extension WeatherRootModel {
    @MainActor
    static let preview: WeatherRootModel = {
        let root = WeatherRootModel(tagController: .preview, photoRoot: PhotoFactory.root(tagController: .preview))
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let rootManagerReal = RootManager(adventureRoot: root, audioRoot: root, characterRoot: root, diceRoot: root, generatorRoot: root, mapRoot: root, pdfRoot: root, photoRoot: root.photoRoot, spaceRoot: root, tableRoot: root, weatherRoot: root)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.photoRoot.setUp(context: nil, batchContext: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.editController.setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: WeatherRootModel = {
        let root = WeatherRootModel.preview
        let importController = root.importController
        let editController = root.editController
#if DEBUG
        Task(priority: .userInitiated) {
            let bundle = RPGResources.Resources.bundle
            guard let url = bundle.url(forResource: RPGResources.Resources.exampleFirstData, withExtension: "gmz") else {
                print("url nil ")
                return
            }
            let task = importController.importUrl(from: url, withOverwrite: true)
            let _ = try? await task.value
            let id = await importController.itemController.itemDataModel.items[0]
            Task { @MainActor in
                editController.setCurrentItem(to: ItemRowTreeModel.previewWithData(id: id))
            }
        }
#endif
        return root
    }()
    
#if DEBUG
    @MainActor
    static func testRoot(photoRoot: PhotoRootModel) -> WeatherRootModel {
        let root = WeatherRootModel(tagController: .preview, photoRoot: photoRoot)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let rootManagerReal = RootManager(adventureRoot: root, audioRoot: root, characterRoot: root, diceRoot: root, generatorRoot: root, mapRoot: root, pdfRoot: root, photoRoot: root.photoRoot, spaceRoot: root, tableRoot: root, weatherRoot: root)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.photoRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        return root
    }
#endif
}

@MainActor
extension WeatherRootModel: RootExportControllable {
    public var linkControllable: LinkControllable {
        linkController
    }
}

extension WeatherModel {
    nonisolated static let previewId = fixtureID(1)

    static var `default`: WeatherModel {
        WeatherModel(
            id: previewId,
            name: "Storm",
            description: "Storm with rain and thunder in the night. This is the right weather for a typical horror scenario.",
            tags: ["Rain", "Storm", "Horror"],
            weatherUpdate: fixtureID(0x81),
            time: 0,
            cloudThickness: .ultra,
            stormType: .rain,
            rainAngle: 90,
            rainIntensity: 500,
            lightningFrequency: 60,
            lightningMaxBolts: 120,
            lightningForkProbability: 80,
            photoId: nil
        )
    }

    static var nice: WeatherModel {
        WeatherModel(
            id: fixtureID(2),
            name: "Sunny",
            description: "Nice weather with a few clouds.",
            tags: ["Sheep Clouds", "Sunny", "Normal"],
            weatherUpdate: fixtureID(0x82),
            time: 0,
            cloudThickness: .thin,
            stormType: .none,
            rainAngle: 0,
            rainIntensity: 10,
            lightningFrequency: 0,
            lightningMaxBolts: 0,
            lightningForkProbability: 0,
            photoId: nil
        )
    }

    static var snow: WeatherModel {
        WeatherModel(
            id: fixtureID(3),
            name: "Snow",
            description: "Snow storm in the mountains.",
            tags: ["Mountains", "Storm", "Snow"],
            weatherUpdate: fixtureID(0x83),
            time: 0,
            cloudThickness: .thick,
            stormType: .snow,
            rainAngle: -30,
            rainIntensity: 1_000,
            lightningFrequency: 0,
            lightningMaxBolts: 0,
            lightningForkProbability: 0,
            photoId: nil
        )
    }

    static var light: WeatherModel {
        WeatherModel(
            id: fixtureID(4),
            name: "Light",
            description: "Lightly cloudy but overall pleasant weather.",
            tags: ["Summer", "Day"],
            weatherUpdate: fixtureID(0x84),
            time: 12 * 60 * 60,
            cloudThickness: .light,
            stormType: .none,
            rainAngle: 0,
            rainIntensity: 10,
            lightningFrequency: 0,
            lightningMaxBolts: 0,
            lightningForkProbability: 0,
            photoId: nil
        )
    }

    static var regular: WeatherModel {
        WeatherModel(
            id: fixtureID(5),
            name: "Regular",
            description: "Some clouds but still dry weather.",
            tags: ["Summer", "Night"],
            weatherUpdate: fixtureID(0x85),
            time: 20 * 60 * 60,
            cloudThickness: .regular,
            stormType: .none,
            rainAngle: 0,
            rainIntensity: 100,
            lightningFrequency: 0,
            lightningMaxBolts: 0,
            lightningForkProbability: 0,
            photoId: nil
        )
    }

    static var heavy: WeatherModel {
        WeatherModel(
            id: fixtureID(6),
            name: "Heavy",
            description: "Heavy clouds with steady rain.",
            tags: ["Summer", "Night"],
            weatherUpdate: fixtureID(0x86),
            time: 17 * 60 * 60,
            cloudThickness: .thick,
            stormType: .rain,
            rainAngle: -10,
            rainIntensity: 200,
            lightningFrequency: 0,
            lightningMaxBolts: 0,
            lightningForkProbability: 0,
            photoId: nil
        )
    }

    static var snowRegular: WeatherModel {
        WeatherModel(
            id: fixtureID(7),
            name: "Regular Snow",
            description: "Heavy clouds with regular snow.",
            tags: ["Winter", "Night"],
            weatherUpdate: fixtureID(0x87),
            time: 20 * 60 * 60,
            cloudThickness: .thick,
            stormType: .snow,
            rainAngle: -10,
            rainIntensity: 200,
            lightningFrequency: 0,
            lightningMaxBolts: 0,
            lightningForkProbability: 0,
            photoId: nil
        )
    }

    static var thunder: WeatherModel {
        WeatherModel(
            id: fixtureID(8),
            name: "Thunder",
            description: "A powerful nighttime thunderstorm.",
            tags: ["Thunder", "Night"],
            weatherUpdate: fixtureID(0x88),
            time: 20 * 60 * 60,
            cloudThickness: .thick,
            stormType: .none,
            rainAngle: 0,
            rainIntensity: 200,
            lightningFrequency: 100,
            lightningMaxBolts: 2_000,
            lightningForkProbability: 100,
            photoId: nil
        )
    }

    @MainActor
    static var preview: WeatherModel {
        .default
    }

    nonisolated private static func fixtureID(_ value: UInt8) -> UUID {
        UUID(uuid: (0xB6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }
}

extension ItemRowTreeModel {
    static let preview = ItemRowTreeModel(itemId: WeatherModel.previewId, typeId: .weather)
    @MainActor
    static func previewWithData(id: UUID) -> ItemRowTreeModel {
        ItemRowTreeModel(itemId: id, entryId: nil, typeId: .weather)
    }
}

extension ItemController {
    @MainActor
    static var preview = WeatherRootModel.preview.itemController
}

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = WeatherRootModel.preview.editController
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static var preview = WeatherRootModel.preview.gameController
}

extension ImportController {
    @MainActor
    static var preview = WeatherRootModel.preview.importController
}

extension ExportController {
    @MainActor
    static var preview = WeatherRootModel.preview.exportController
}

extension ViewController {
    @MainActor
    static var preview = WeatherRootModel.preview.viewController
}

extension LinkController {
    @MainActor
    static var preview = WeatherRootModel.preview.linkController
}
