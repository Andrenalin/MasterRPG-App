// @copyright André Trettin

#if !os(tvOS)

import FoundationModels
import Foundation

@MainActor
final class AdventureSessionModel {
    var session = LanguageModelSession()
    
    func set(session: LanguageModelSession) {
        self.session = session
    }
    
    var responses: [LanguageModelSession.ResponseStream<CharacterGenModel>.Snapshot] = []
    var adventureChat: String?
    
    var responseErrorContent: String = ""
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
        The game usually have NPC that are interacting with players characters.
        Ensure to come up with 3-5 possiblities for a question so a game master can choose.
        Add connections to other possible outcomes or stories. 
        Keep your answer pricse except the game master needed a detailed version.
        """
        }
        self.model.set(session: session)
        session.prewarm()
    }
        
    @MainActor func request(message: String) {
        Task {
            do {
                let stream = model.session.streamResponse(options: GenerationOptions()) {
                    "\(message)"
                }
                
                for try await partialResponse in stream {
                    self.model.adventureChat = partialResponse.content
                }
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
            } catch {
                model.responseErrorContent = error.localizedDescription
            }
        }
    }
}

#endif
