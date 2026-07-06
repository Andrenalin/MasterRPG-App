// @copyright André Trettin

#if canImport(Testing) && !os(tvOS)
import CoreRPG
import Foundation
import Testing

@testable import GeneratorRPG

@MainActor
struct GeneratorControllerTests {
    @Test func generatorSessionStateAndSetup() async throws {
        let sut = GeneratorController()
        let model = GeneratorModel(id: UUID(), name: "Seed", displayState: 0, genType: .extractor)

        #expect(sut.model.responses.isEmpty)
        #expect(sut.model.result == nil)
        #expect(sut.model.characterChat == nil)
        #expect(sut.model.campaign == nil)
        #expect(sut.model.extracted == nil)
        #expect(sut.model.errorMessage == nil)

        sut.model.currentTask = Task { }
        sut.model.cancel()
        #expect(sut.model.currentTask == nil)

        sut.generate()
        sut.generateAdventure(from: model)
        sut.generateExtractor(from: model)
    }

    @Test func adventureSessionConfigurationAndResetState() async throws {
        let sut = AdventureGeneratorController()
        let model = sut.model

        #expect(model.tokenUsageFraction == 0)
        model.currentTokenCount = 50
        model.maxContextSize = 100
        #expect(model.tokenUsageFraction == 0.5)
        model.maxContextSize = 0
        #expect(model.tokenUsageFraction == 0)

        #expect(model.currentGuardrails() == .default)
        model.usePermissiveGuardrails = true
        #expect(model.currentGuardrails() == .permissiveContentTransformations)

        #expect(model.generationOptions.sampling == nil)
        model.SamplingStrategyConfiguration = .greedy
        #expect(model.generationOptions.sampling == .greedy)

        model.SamplingStrategyConfiguration = .sampling
        model.useFixedSeed = false
        model.topKSamplingValue = 24
        #expect(model.generationOptions.sampling == .randomTop(24, seed: nil))

        model.useFixedSeed = true
        let seededOptions = model.generationOptions
        #expect(seededOptions == model.generationOptions)

        model.showError = true
        model.dismissError()
        #expect(model.showError == false)

        model.currentTask = Task { }
        model.cancel()
        #expect(model.currentTask == nil)

        model.isLoading = true
        model.responseErrorContent = "Boom"
        model.showError = true
        sut.clearChat()
        #expect(model.isLoading == false)
        #expect(model.responseErrorContent.isEmpty)
        #expect(model.showError == false)

        await sut.generate()
        sut.generateExtractor()
        sut.tearDown()
    }
}
#endif
