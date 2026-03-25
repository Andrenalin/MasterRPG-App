// @copyright André Trettin

#if !os(tvOS)

import FoundationModels
import Foundation

@MainActor
final class GeneratorSessionModel {
    var session = LanguageModelSession()

    func set(session: LanguageModelSession) {
        self.session = session
    }

    var responses: [LanguageModelSession.ResponseStream<CharacterGenModel>.Snapshot] = []

    var result: CharacterGenModel?
    var characterChat: String?

    func append(_ content: LanguageModelSession.ResponseStream<CharacterGenModel>.Snapshot) {
        result = try? CharacterGenModel(content.rawContent)
        responses.append(content)
    }

    var campaign: CampaignGenModel.PartiallyGenerated?

    var extracted: BlockGenModel.PartiallyGenerated?

    // Error tracking
    var errorMessage: String?

    // Task management for cancellation
    var currentTask: Task<Void, Never>?

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
}

struct GeneratorController: Sendable {
    @MainActor init() {
        self.model = GeneratorSessionModel()
    }
    
    let model: GeneratorSessionModel
    let llm = SystemLanguageModel.default
    
    @MainActor func generate() {
//        let reference: CharacterGenModel = CharacterGenModel(name: "He-Man", information: "He-Man is a legendary hero from the Marvel Universe.", tags: ["Warrior", "Weapon Master", "Swordsman"], entries: [
//            CharacterEntryGenModel(name: "Attributes", content: "", valueType: .text, groupedValues: CharacterGenModel(name: "Attributes", information: "The attributes of the character", tags: ["Values"], entries: [
//                CharacterEntryGenModel(name: "BODY", content: "10", valueType: .number, groupedValues: nil),
//                CharacterEntryGenModel(name: "MOBILITY", content: "8", valueType: .number, groupedValues: nil),
//                CharacterEntryGenModel(name: "MIND", content: "4", valueType: .number, groupedValues: nil)
//            ]))
//        ])
        
        let session = LanguageModelSession {
        """
        You are an assistent to support a game master for a role play game. 
        """
        }
        self.model.set(session: session)
        session.prewarm()
    }
    
    @MainActor func generateAdventure(from model: GeneratorModel) {
        let instructions = """
                Your are an assistent to create new adventures for a RPG game.
                """
        //        let instructions = """
        //                Helfe dabei ein Abenteuer zu erstellen fuer ein Fantasy RPG.
        //                """
        let session = LanguageModelSession(instructions: instructions)
        
        self.model.set(session: session)
        session.prewarm()
    }
    
    @MainActor func request(message: String) {
        // Cancel any previous request
        model.cancel()

        model.currentTask = Task {
            do {
                let stream = model.session.streamResponse(
                    options: GenerationOptions()) {
                        "\(message)"
                    }

                for try await partialResponse in stream {
                    // Check for cancellation
                    try Task.checkCancellation()
                    self.model.characterChat = partialResponse.content
                }

                // Clear error on success
                model.errorMessage = nil
            } catch is CancellationError {
                // Clean cancellation - don't set error
                return
            } catch let error as LanguageModelSession.GenerationError {
                model.errorMessage = "Generation Error: \(error.localizedDescription)"
            } catch let error as LanguageModelSession.ToolCallError {
                model.errorMessage = "Tool Call Error: \(error.tool)"
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }
    
    @MainActor func requestAdventure(message: String) async {
        do {
            let prompt = Prompt {
                "\(message)"
            }

            let stream = model.session.streamResponse(to: prompt, generating: CampaignGenModel.self)

            for try await partialResponse in stream {
                // Check for cancellation
                try Task.checkCancellation()
                self.model.campaign = partialResponse.content
            }

            // Clear error on success
            model.errorMessage = nil
        } catch is CancellationError {
            // Clean cancellation
            return
        } catch let error as LanguageModelSession.GenerationError {
            model.errorMessage = "Generation Error: \(error.localizedDescription)"
        } catch let error as LanguageModelSession.ToolCallError {
            model.errorMessage = "Tool Call Error: \(error.tool)"
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
    
    
    @MainActor func generateExtractor(from model: GeneratorModel) {
        let instructions = """
                Your job is to identify the the type of text, and split into Adventure, Map, Character or Table related text blocks. 
                """
        let session = LanguageModelSession(instructions: instructions)
        
        self.model.set(session: session)
        session.prewarm()
    }
    
    @MainActor func requestExtraction(message: String) async {
        do {
            let prompt = Prompt {
                            "\(message)"
                        }

            let stream = model.session.streamResponse(to: prompt, generating: BlockGenModel.self)

            for try await partialResponse in stream {
                // Check for cancellation
                try Task.checkCancellation()
                self.model.extracted = partialResponse.content
            }

            // Clear error on success
            model.errorMessage = nil
        } catch is CancellationError {
            // Clean cancellation
            return
        } catch let error as LanguageModelSession.GenerationError {
            model.errorMessage = "Generation Error: \(error.localizedDescription)"
        } catch let error as LanguageModelSession.ToolCallError {
            model.errorMessage = "Tool Call Error: \(error.tool)"
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

}

#endif
