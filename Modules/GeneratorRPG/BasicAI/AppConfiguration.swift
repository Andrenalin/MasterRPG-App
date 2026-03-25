// @copyright André Trettin

import Foundation
import FoundationModels
import SwiftUI

/// Centralized configuration constants for the app
enum AppConfiguration {
    /// Token management configuration
    enum TokenManagement {
        /// Fallback maximum tokens when dynamic context size is unavailable
        static let defaultMaxTokens = 4096

        /// Threshold percentage (0.0-1.0) at which to start applying sliding window
        static let windowThreshold = 0.75

        /// Target window size in tokens after applying sliding window
        static let targetWindowSize = 2000

        /// Fetches the real context size from the model when available,
        /// falling back to the default of 4096.
        static func contextSize(
            for model: SystemLanguageModel = .default
        ) async -> Int {
            #if compiler(>=6.3)
            return model.contextSize
            #else
            return defaultMaxTokens
            #endif
        }

        static func contextSize(
            modelUseCase: FoundationLabModelUseCase = .general,
            guardrails: FoundationLabGuardrails = .default
        ) async -> Int {
            let model = SystemLanguageModel(
                useCase: modelUseCase.foundationModelsValue,
                guardrails: guardrails.foundationModelsValue
            )
            return await contextSize(for: model)
        }
    }
}

extension Color {
// MARK: - Background Colors
static var adaptiveBackground: Color {
    #if os(iOS)
    Color(UIColor.systemBackground)
    #elseif os(macOS)
    Color(NSColor.windowBackgroundColor)
    #else
    Color(.systemBackground)
    #endif
}
}
