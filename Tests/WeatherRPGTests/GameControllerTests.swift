// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import PhotoRPG
@testable import WeatherRPG

@MainActor
struct GameControllerTests {
    @Test("Weather package version follows its settings and its linked Photo")
    func packageVersionTracksLinkedPhoto() async throws {
        // Given
        let photoRoot = PhotoRootModel.testRoot()
        let root = WeatherRootModel.testRoot(photoRoot: photoRoot)
        let sut = root.gameController
        let photoId = UUID()
        let weatherId = UUID()
        let noPhotoWeatherId = UUID()
        let missingPhotoWeatherId = UUID()
        let firstData = Data("first-photo".utf8)
        let firstHash = FileUrl.contentHash(of: firstData)
        let firstURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).jpg")
        try firstData.write(to: firstURL)
        defer { try? FileManager.default.removeItem(at: firstURL) }
        let firstFile = FileUrl(
            fileId: UUID(),
            url: firstURL,
            location: .other,
            module: NetworkModules.photo.token,
            relativeUrl: nil
        )
        let photo = PhotoModel(id: photoId, name: "Sky", fileUrl: firstFile)
        photoRoot.itemController.replace(model: photo, isInsert: true)
        root.itemController.replace(
            model: Self.weather(id: weatherId, photoId: photoId),
            isInsert: true
        )
        root.itemController.replace(
            model: Self.weather(id: noPhotoWeatherId, photoId: nil),
            isInsert: true
        )
        root.itemController.replace(
            model: Self.weather(id: missingPhotoWeatherId, photoId: UUID()),
            isInsert: true
        )
        // When
        let firstVersion = await sut.weatherVersion(for: weatherId)
        let backfilledPhoto = photoRoot.itemController.itemOrEmpty(for: photoId)
        let firstReference = await sut.shareWeather(id: weatherId)
        let exportIds = root.exportController.exporting(
            itemIds: ItemModuleIds(ids: [weatherId], module: .weather)
        )
        let firstFullPackage = try await sut.createWeatherGameData(for: weatherId)
        backfilledPhoto.fileUrl = FileUrl(
            fileId: UUID(),
            url: URL.temporaryDirectory.appending(path: "relocated.jpg"),
            location: .local,
            module: NetworkModules.photo.token,
            relativeUrl: nil,
            contentHash: firstHash
        )
        let relocatedVersion = await sut.weatherVersion(for: weatherId)
        backfilledPhoto.fileUrl = FileUrl(
            fileId: UUID(),
            url: URL.temporaryDirectory.appending(path: "replacement.jpg"),
            location: .other,
            module: NetworkModules.photo.token,
            relativeUrl: nil,
            contentHash: FileUrl.contentHash(of: Data("replacement-photo".utf8))
        )
        let replacementVersion = await sut.weatherVersion(for: weatherId)
        let noPhotoVersion = await sut.weatherVersion(for: noPhotoWeatherId)
        let missingPhotoVersion = await sut.weatherVersion(for: missingPhotoWeatherId)

        // Then
        #expect(backfilledPhoto.fileUrl?.contentHash != nil)
        #expect(firstReference.type == .weather)
        #expect(firstReference.version == firstVersion)
        #expect(firstReference.data == nil)
        #expect(firstFullPackage.version == firstVersion)
        #expect(firstFullPackage.data != nil)
        #expect(exportIds.ids[.photo]?.contains(photoId) == true)
        #expect(relocatedVersion == firstVersion)
        #expect(replacementVersion != firstVersion)
        #expect(noPhotoVersion == missingPhotoVersion, "a missing Photo counts like no Photo")
        #expect(noPhotoVersion != firstVersion)
    }

    @Test("Editing a Weather changes its package version, a rename does not")
    func editingWeatherChangesVersion() async throws {
        // Given
        let root = WeatherRootModel.testRoot(photoRoot: PhotoRootModel.testRoot())
        let sut = root.gameController
        let weatherId = UUID()
        let weather = Self.weather(id: weatherId, photoId: nil)
        root.itemController.replace(model: weather, isInsert: true)
        let before = await sut.weatherVersion(for: weatherId)

        // When
        weather.name = "Renamed storm"
        let afterRename = await sut.weatherVersion(for: weatherId)
        weather.rainIntensity = 80
        let afterEdit = await sut.weatherVersion(for: weatherId)
        weather.stormType = .snow
        let afterSnow = await sut.weatherVersion(for: weatherId)

        // Then
        #expect(afterRename == before)
        #expect(afterEdit != before)
        #expect(afterSnow != afterEdit)
        #expect(before != 0)
    }

    @Test("Full Weather reveal stays in game memory and enables later id-only reveal")
    func fullRevealIsMemoryOnlyAndMakesWeatherCurrent() async throws {
        // Given
        let masterPhotoRoot = PhotoRootModel.testRoot()
        let masterRoot = WeatherRootModel.testRoot(photoRoot: masterPhotoRoot)
        let weatherId = UUID()
        masterRoot.itemController.replace(
            model: Self.weather(id: weatherId, photoId: nil),
            isInsert: true
        )
        let fullPackage = try await masterRoot.gameController.createWeatherGameData(for: weatherId)

        let playerPhotoRoot = PhotoRootModel.testRoot()
        let playerRoot = WeatherRootModel.testRoot(photoRoot: playerPhotoRoot)
        let sut = playerRoot.gameController
        playerRoot.itemController.itemDataModel.resetGame(start: true)
        playerPhotoRoot.itemController.itemDataModel.resetGame(start: true)
        let idOnly = NetworkCodableDataType(
            id: weatherId,
            type: .weather,
            version: fullPackage.version
        )

        // When
        let missingBeforeImport = try await sut.revealWeather(itemId: weatherId, data: idOnly)
        let imported = try await sut.revealWeather(itemId: weatherId, data: fullPackage)
        let reusedFromMemory = try await sut.revealWeather(itemId: weatherId, data: idOnly)

        // Then
        #expect(!missingBeforeImport)
        #expect(imported)
        #expect(reusedFromMemory)
        #expect(sut.isWeatherAvailable(itemId: weatherId, version: fullPackage.version))
        #expect(sut.gameModel.currentItemId == weatherId)
        #expect(sut.gameModel.itemData[weatherId] is WeatherModel)
        #expect(playerRoot.itemController.itemDataModel.itemData[weatherId] == nil)
        #expect(fullPackage.version != 0)
    }

    @Test("A newer Weather package that arrives during a reveal is imported, not dropped (CODE_AUDIT §3.1)")
    func newerPackageIsNotDroppedByRunningReveal() async throws {
        // Given
        let masterRoot = WeatherRootModel.testRoot(photoRoot: PhotoRootModel.testRoot())
        let weatherId = UUID()
        let weather = Self.weather(id: weatherId, photoId: nil)
        masterRoot.itemController.replace(model: weather, isInsert: true)
        let oldPackage = try await masterRoot.gameController.createWeatherGameData(for: weatherId)
        weather.rainIntensity = 90
        let newPackage = try await masterRoot.gameController.createWeatherGameData(for: weatherId)
        try #require(oldPackage.version != newPackage.version, "the edit must produce a new version")

        let playerRoot = WeatherRootModel.testRoot(photoRoot: PhotoRootModel.testRoot())
        let sut = playerRoot.gameController
        playerRoot.itemController.itemDataModel.resetGame(start: true)

        // When
        async let first = sut.revealWeather(itemId: weatherId, data: oldPackage)
        async let second = sut.revealWeather(itemId: weatherId, data: newPackage)
        _ = try await (first, second)

        // Then
        #expect(sut.isWeatherAvailable(itemId: weatherId, version: newPackage.version))
    }

    @Test("Weather availability requires the exact package version and resets with the game")
    func availabilityIsVersionedAndSessionScoped() async throws {
        // Given
        let root = WeatherRootModel.testRoot(photoRoot: PhotoRootModel.testRoot())
        let sut = root.gameController
        let weatherId = UUID()
        let weather = Self.weather(id: weatherId, photoId: nil)
        sut.setGame(item: weather, itemId: weatherId)

        // When
        sut.markWeatherAvailable(itemId: weatherId, version: 42)

        // Then
        #expect(sut.isWeatherAvailable(itemId: weatherId, version: 42))
        #expect(!sut.isWeatherAvailable(itemId: weatherId, version: 41))

        // When
        await sut.reset()

        // Then
        #expect(!sut.isWeatherAvailable(itemId: weatherId, version: 42))
        #expect(sut.weatherGameModel.availableVersions.isEmpty)
        #expect(sut.gameModel.itemData.isEmpty)
    }
}

private extension GameControllerTests {
    static func weather(id: UUID, photoId: UUID?) -> WeatherModel {
        WeatherModel(
            id: id,
            name: "Storm",
            description: "A storm",
            tags: [],
            weatherUpdate: UUID(),
            time: 0,
            cloudThickness: .thick,
            stormType: .rain,
            rainAngle: 0,
            rainIntensity: 50,
            lightningFrequency: 10,
            lightningMaxBolts: 2,
            lightningForkProbability: 25,
            photoId: photoId
        )
    }
}
#endif
