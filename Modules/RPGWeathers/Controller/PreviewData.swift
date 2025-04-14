// @copyright André Trettin

import AndrenalinKit
import Foundation
import RPGResources
import RPGPhotos

public extension WeatherRoot {
    @MainActor
    static let preview: WeatherRoot = {
        let root = WeatherRoot(context: nil, photoRoot: .preview)
        root.photoRoot.setRootControllable(root)
        root.setRootControllable(root)
        root.editController(type: .main).setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: WeatherRoot = {
        let root = WeatherRoot.preview
        let importController = root.importController
        let editController = root.editController(type: .main)
#if DEBUG
        Task.detached(priority: .userInitiated) {
            let bundle = Resources.bundle
            guard let url = bundle.url(forResource: Resources.exampleFirstData, withExtension: "gmz") else {
                print("url nil ")
                return
            }
            let task = importController.importUrl(from: url, withOverwrite: true)
            let _ = try await task.value
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
    static func testRoot(photoRoot: PhotoRoot) -> WeatherRoot {
        let root = WeatherRoot(context: nil, photoRoot: photoRoot)
        root.setRootControllable(root)
        return root
    }
#endif

    @MainActor
    static let linkRegisterController = FakeLinkRegisterController()
}

extension WeatherRoot: RootControllable {
    public var linkControllable: LinkControllable {
        linkController
    }

    @MainActor
    public var linkRegisterControllable: LinkRegisterControllable {
        WeatherRoot.linkRegisterController
    }
    
    public var gameExportControllable: any ExportControllable {
        gameController.exportController
    }
    public var gameImportControllable: any ImportControllable {
        gameController.importController
    }
}

extension WeatherModel {
    static let uuid = UUID()

    static var `default`: WeatherModel {
        WeatherModel(id: uuid, name: "Storm", description: "Strom with Rain and Thunder in the night. This is the right weather for a typical horror scenario.", tags: ["Rain", "Storm", "Horror"], time: 0.0, cloudThickness: .ultra, stormType: .rain, rainAngle: 90, rainIntensity: 500.0, lightningFrequency: 60, lightningMaxBolts: 120, lightningForkProbability: 80, photoId: nil)
    }

    static var nice: WeatherModel {
        WeatherModel(id: UUID(), name: "Sunny", description: "A nice weather with a few clouds", tags: ["Sheep Clouds", "Sunny", "Normal"], time: 0.0, cloudThickness: .thin, stormType: .none, rainAngle: 0, rainIntensity: 10, lightningFrequency: 0, lightningMaxBolts: 0, lightningForkProbability: 0, photoId: nil)
    }

    static var snow: WeatherModel {
        WeatherModel(id: UUID(), name: "Snow", description: "Snow Strom in the mountains", tags: ["Montains", "Storm", "Snow"], time: 0.0, cloudThickness: .thick, stormType: .snow, rainAngle: -30, rainIntensity: 1000.0, lightningFrequency: 0, lightningMaxBolts: 0, lightningForkProbability: 0, photoId: nil)
    }

    static var light: WeatherModel {
        WeatherModel(id: UUID(), name: "Light", description: "Light cloudy but overall nice weather", tags: ["Sommer", "Day"], time: 12 * 60 * 60, cloudThickness: .light, stormType: .none, rainAngle: 0, rainIntensity: 10, lightningFrequency: 0, lightningMaxBolts: 0, lightningForkProbability: 0, photoId: nil)
    }

    static var regular: WeatherModel {
        WeatherModel(id: UUID(), name: "Regular", description: "Some clouds but still dry weather", tags: ["Sommer", "Night"], time: 20 * 60 * 60, cloudThickness: .regular, stormType: .none, rainAngle: 0, rainIntensity: 100, lightningFrequency: 0, lightningMaxBolts: 0, lightningForkProbability: 0, photoId: nil)
    }

    static var heavy: WeatherModel {
        WeatherModel(id: UUID(), name: "Heavy", description: "Heavy clouds but still mostly weather", tags: ["Sommer", "Night"], time: 17 * 60 * 60, cloudThickness: .thick, stormType: .rain, rainAngle: -10, rainIntensity: 200, lightningFrequency: 0, lightningMaxBolts: 0, lightningForkProbability: 0, photoId: nil)
    }

    static var snowRegular: WeatherModel {
        WeatherModel(id: UUID(), name: "Regular Snow", description: "Heavy clouds but still mostly weather", tags: ["Winter", "Night"], time: 20 * 60 * 60, cloudThickness: .thick, stormType: .snow, rainAngle: -10, rainIntensity: 200, lightningFrequency: 0, lightningMaxBolts: 0, lightningForkProbability: 0, photoId: nil)
    }

    static var thunder: WeatherModel {
        WeatherModel(id: UUID(), name: "Thunder", description: "A cloud thunder storm", tags: ["Thunder", "Night"], time: 20 * 60 * 60, cloudThickness: .thick, stormType: .none, rainAngle: 0, rainIntensity: 200, lightningFrequency: 100, lightningMaxBolts: 2000, lightningForkProbability: 100, photoId: nil)
    }
}

// MARK: Preview - Test
extension WeatherModel {
    static let previewId = UUID()
    @MainActor
    static let preview = WeatherRoot.previewWithData.editController(type: .main).model
}

extension ItemRowTreeModel {
    static let preview = ItemRowTreeModel(itemId: WeatherModel.snow.id, typeId: .weather)
    @MainActor
    static func previewWithData(id: UUID) -> ItemRowTreeModel {
        ItemRowTreeModel(itemId: id, entryId: nil, typeId: .weather)
    }
}

extension ItemController {
    @MainActor
    static var preview = WeatherRoot.preview.itemController
}

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = WeatherRoot.preview.editController(type: .main)
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static var preview = WeatherRoot.preview.gameController
}

extension ImportController {
    @MainActor
    static var preview = WeatherRoot.preview.importController
}

extension ExportController {
    @MainActor
    static var preview = WeatherRoot.preview.exportController
}

extension ListController {
    @MainActor
    static let previewTabId = UUID()
    
    @MainActor
    static var preview = WeatherRoot.preview.listController(tabId: previewTabId)
}

extension ListModel {
    @MainActor
    static var preview = ListController.preview.model
}

extension ViewController {
    @MainActor
    static var preview = WeatherRoot.preview.viewController
}

extension LinkController {
    @MainActor
    static var preview = WeatherRoot.preview.linkController
}
