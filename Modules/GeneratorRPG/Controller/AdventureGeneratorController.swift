// @copyright André Trettin

#if !os(tvOS)

import FoundationModels
import Foundation

@Observable
@MainActor
final class AdventureSessionModel {
    var session = LanguageModelSession()

    func set(session: LanguageModelSession) {
        self.session = session
    }

    var responseErrorContent: String = ""
    var showError: Bool = false

    func dismissError() {
        showError = false
    }
    
    // chat
    var adventureChat: String?

    // extracting chat
    var extracted: [BlockEntryGenModel.PartiallyGenerated] = []

    // Task management for cancellation
    var currentTask: Task<Void, Never>?

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
    
    // token management
    var currentTokenCount: Int = 0
    var maxContextSize: Int = AppConfiguration.TokenManagement.defaultMaxTokens
    
    var tokenUsageFraction: Double {
        guard maxContextSize > 0 else { return 0 }
        return min(1.0, Double(currentTokenCount) / Double(maxContextSize))
    }
}

struct AdventureGeneratorController: Sendable {
    @MainActor init() {
        self.model = AdventureSessionModel()
    }
    
    let model: AdventureSessionModel
    let llm = SystemLanguageModel.default
    
    @MainActor func generate() {
        let session = LanguageModelSession {
        """
        You are an assistant to support a game master for creating a fictional game story.
        In the game you have NPC and players characters they have to talk to each other.
        Add connections to other possible outcomes or stories.
        Keep your answer precise except the game master needed a detailed version.
        """
        }
        self.model.set(session: session)
        session.prewarm()
    }
        
    @MainActor func request(message: String) {
        // Cancel any previous request
        model.cancel()

        model.currentTask = Task {
            do {
                let prompt = Prompt {
                    "\(message)"
                }
                let stream = model.session.streamResponse(to: prompt, options: GenerationOptions())

                for try await partialResponse in stream {
                    // Check for cancellation
                    try Task.checkCancellation()
                    self.model.adventureChat = partialResponse.content
                }

                // Clear error on success
                model.responseErrorContent = ""
            } catch is CancellationError {
                // Clean cancellation - don't set error
                return
            } catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .guardrailViolation(let context):
                    model.responseErrorContent = "Guardrail Violation: \(context.debugDescription)"
                case .decodingFailure(let context):
                    model.responseErrorContent = "Decoding Failure: \(context.debugDescription)"
                case .rateLimited(let context):
                    model.responseErrorContent = "Rate Limit exceeded: \(context.debugDescription)"
                case .exceededContextWindowSize(let context):
                    model.responseErrorContent = "Memory exceeded: \(context.debugDescription)"
                default:
                    model.responseErrorContent = "Other error: \(error.localizedDescription)"
                }
                if let failureReason = error.failureReason {
                    model.responseErrorContent += "\n\(failureReason)"
                }
                if let recoverySuggestion = error.recoverySuggestion {
                    model.responseErrorContent += "\n\(recoverySuggestion)"
                }
                model.showError = true
            } catch {
                model.responseErrorContent = error.localizedDescription
                model.showError = true
            }
        }
    }
}

#endif
