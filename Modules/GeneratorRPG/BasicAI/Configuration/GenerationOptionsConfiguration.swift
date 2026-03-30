import Foundation

struct GenerationOptionsConfiguration: Sendable, Hashable, Codable {
    enum SamplingMode: Sendable, Hashable, Codable {
        case greedy
        case randomTop(Int, seed: UInt64? = nil)
        case randomProbabilityThreshold(Double, seed: UInt64? = nil)
    }

    let sampling: SamplingMode?
    let temperature: Double?
    let maximumResponseTokens: Int?

    init(
        sampling: SamplingMode? = nil,
        temperature: Double? = nil,
        maximumResponseTokens: Int? = nil
    ) {
        self.sampling = sampling
        self.temperature = temperature
        self.maximumResponseTokens = maximumResponseTokens
    }
}
