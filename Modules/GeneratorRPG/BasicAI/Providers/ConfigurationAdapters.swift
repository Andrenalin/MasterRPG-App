import Foundation
import FoundationModels

extension FoundationLabModelUseCase {
    public var foundationModelsValue: SystemLanguageModel.UseCase {
        switch self {
        case .general:
            return .general
        }
    }
}

extension GuardrailsConfiguration {
    public var foundationModelsValue: SystemLanguageModel.Guardrails {
        switch self {
        case .default:
            return .default
        case .permissiveContentTransformations:
            return .permissiveContentTransformations
        }
    }
}

extension GenerationOptionsConfiguration.SamplingMode {
    var foundationModelsValue: GenerationOptions.SamplingMode {
        switch self {
        case .greedy:
            return .greedy
        case .randomTop(let top, let seed):
            return .random(top: top, seed: seed)
        case .randomProbabilityThreshold(let threshold, let seed):
            return .random(probabilityThreshold: threshold, seed: seed)
        }
    }
}

extension GenerationOptionsConfiguration {
    var foundationModelsValue: GenerationOptions {
        GenerationOptions(
            sampling: sampling?.foundationModelsValue,
            temperature: temperature,
            maximumResponseTokens: maximumResponseTokens
        )
    }
}
