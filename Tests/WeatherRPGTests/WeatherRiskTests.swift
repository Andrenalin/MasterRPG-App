// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import WeatherRPG

/// CODE_AUDIT_26 §10.7: stamp, slider direction, link-register and merge behaviour of Weather.
@MainActor
@Suite("Weather risks")
struct WeatherRiskTests {
    private func makeWeather(rainAngle: Double = 30, photoId: UUID? = nil) -> WeatherModel {
        WeatherModel(
            id: UUID(),
            name: "Storm",
            description: "",
            tags: [],
            time: 100,
            cloudThickness: .none,
            stormType: .rain,
            rainAngle: rainAngle,
            rainIntensity: 12,
            lightningFrequency: 50,
            lightningMaxBolts: 23,
            lightningForkProbability: 99,
            photoId: photoId
        )
    }

    // MARK: - replace(with:) and the weather stamp

    @Test("A rename keeps the weather stamp")
    func renameKeepsWeatherUpdate() {
        let model = makeWeather()
        let stamp = model.weatherUpdate_.wrappedValue
        let renamed = model.copy()
        renamed.name = "Renamed"

        #expect(model.replace(with: renamed))

        #expect(model.name == "Renamed")
        #expect(model.weatherUpdate_.wrappedValue == stamp)
    }

    @Test("A changed weather value moves the weather stamp")
    func weatherChangeMovesWeatherUpdate() {
        let model = makeWeather()
        let stamp = model.weatherUpdate_.wrappedValue
        let changed = model.copy()
        changed.rainIntensity = 80

        #expect(model.replace(with: changed))

        #expect(model.rainIntensity == 80)
        #expect(model.weatherUpdate_.wrappedValue != stamp)
    }

    @Test("Replacing with an equal model changes nothing")
    func equalReplaceIsNoOp() {
        let model = makeWeather()
        #expect(model.replace(with: model.copy()) == false)
    }

    // MARK: - rainDirection

    @Test("The rain direction toggle works at a zero angle")
    func rainDirectionAtZeroAngle() {
        let model = makeWeather(rainAngle: 0)
        #expect(model.rainDirection)

        model.rainDirection = false
        #expect(model.rainAngle < 0)
        #expect(model.rainDirection == false)

        model.rainDirection = true
        #expect(model.rainAngle > 0)
        #expect(model.rainDirection)
    }

    @Test("Flipping the direction keeps the magnitude")
    func rainDirectionKeepsMagnitude() {
        let model = makeWeather(rainAngle: 25)

        model.rainDirection = false

        #expect(model.rainAngle == -25)
    }

    // MARK: - Link register

    @Test("A photo becomes a link register entry from the weather")
    func linkRegisterContainsPhoto() {
        let photoId = UUID()
        let model = makeWeather(photoId: photoId)

        let registered = model.linkRegisterModels

        #expect(registered.count == 1)
        #expect(registered.first?.source.itemId == model.id)
        #expect(registered.first?.source.typeId == .weather)
        #expect(registered.first?.destination.itemId == photoId)
        #expect(registered.first?.destination.typeId == .photo)
    }

    @Test("Changing the photo removes the old link and adds the new one")
    func changedPhotoDiff() {
        let oldPhoto = UUID()
        let newPhoto = UUID()
        let old = makeWeather(photoId: oldPhoto)
        let new = old.copy()
        new.photoId = newPhoto

        let diff = new.changedLinkRegisterModels(oldValue: old)

        #expect(diff.added.map(\.destination.itemId) == [newPhoto])
        #expect(diff.removed.map(\.destination.itemId) == [oldPhoto])
    }

    @Test("A weather without a photo registers nothing")
    func noPhotoNoLinks() {
        #expect(makeWeather().linkRegisterModels.isEmpty)
    }

    // MARK: - merge

    @Test("Merging converges on both devices after a weather edit on one")
    func mergeConvergesAfterWeatherEdit() {
        let base = makeWeather()
        let local = base.copy()
        let remote = base.copy()
        let edited = remote.copy()
        edited.rainIntensity = 77
        _ = remote.replace(with: edited)

        let localMerged = local.merge(remote)
        let remoteMerged = remote.merge(local)

        #expect(localMerged.rainIntensity == remoteMerged.rainIntensity)
        #expect(localMerged.weatherUpdate_.wrappedValue == remoteMerged.weatherUpdate_.wrappedValue)
    }

    @Test("A rename on one device and a weather edit on the other both survive the merge")
    func mergeKeepsRenameAndWeatherEdit() {
        let base = makeWeather()
        let renaming = base.copy()
        let renamed = renaming.copy()
        renamed.name = "Renamed"
        _ = renaming.replace(with: renamed)

        let editing = base.copy()
        let edited = editing.copy()
        edited.rainIntensity = 77
        _ = editing.replace(with: edited)

        let merged = renaming.merge(editing)

        #expect(merged.rainIntensity == 77)
        #expect(merged.name == "Renamed")
    }
}
#endif
