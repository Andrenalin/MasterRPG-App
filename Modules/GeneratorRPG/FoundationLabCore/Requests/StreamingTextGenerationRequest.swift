import Foundation
import FoundationModels

struct StreamingTextGenerationRequest: CapabilityRequest, Sendable {
    public let prompt: String
    public let systemPrompt: String?
    public let modelUseCase: FoundationLabModelUseCase
    let guardrails: GuardrailsConfiguration?
    public let generationOptions: GenerationOptionsConfiguration?
    public let context: CapabilityInvocationContext

    init(
        prompt: String,
        systemPrompt: String? = nil,
        modelUseCase: FoundationLabModelUseCase = .general,
        guardrails: GuardrailsConfiguration? = nil,
        generationOptions: GenerationOptionsConfiguration? = nil,
        context: CapabilityInvocationContext
    ) {
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.modelUseCase = modelUseCase
        self.guardrails = guardrails
        self.generationOptions = generationOptions
        self.context = context
    }
}
