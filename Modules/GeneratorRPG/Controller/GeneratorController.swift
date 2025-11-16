// @copyright André Trettin

#if !os(tvOS)

import RPGValues
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
    
    func append(_ content: LanguageModelSession.ResponseStream<CharacterGenModel>.Snapshot) {
        result = try? CharacterGenModel(content.rawContent)
        responses.append(content)
    }
    
    var campaign: CampaignGenModel.PartiallyGenerated?
}

struct GeneratorController: Sendable {
    @MainActor init(characterRoot: CharacterRootModel) {
        self.characterRoot = characterRoot
        self.model = GeneratorSessionModel()
    }
    
    let characterRoot: CharacterRootModel
    let model: GeneratorSessionModel
    let llm = SystemLanguageModel.default
    
    @MainActor func generate(from model: GeneratorModel) {
        let reference: CharacterGenModel = CharacterGenModel(name: "He-Man", information: "He-Man is a legendary hero from the Marvel Universe.", tags: ["Warrior", "Weapon Master", "Swordsman"], entries: [
            CharacterEntryGenModel(name: "Attributes", content: "", valueType: .text, groupedValues: CharacterGenModel(name: "Attributes", information: "The attributes of the character", tags: ["Values"], entries: [
            CharacterEntryGenModel(name: "BODY", content: "10", valueType: .number, groupedValues: nil),
            CharacterEntryGenModel(name: "MOBILITY", content: "8", valueType: .number, groupedValues: nil),
            CharacterEntryGenModel(name: "MIND", content: "4", valueType: .number, groupedValues: nil)
            ]))
        ])
        
        let session = LanguageModelSession {
        """
        You are a character generator assistant for a role play game. Use the reference character \(reference) to understand the sturcture of the response. 
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
        Task {
            do {
                let stream = model.session.streamResponse(
                    generating: CharacterGenModel.self,
                    includeSchemaInPrompt: false,
                    options: GenerationOptions()) {
                        "\(message)"
                    }
                
                for try await response in stream {
                    model.append(response)
                }
            } catch let error as LanguageModelSession.GenerationError {
                print(error.localizedDescription)
            } catch let error as LanguageModelSession.ToolCallError {
                print(error.tool)
            } catch {
                print(error.localizedDescription)
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
                self.model.campaign = partialResponse.content
            }
        } catch let error as LanguageModelSession.GenerationError {
            print(error.localizedDescription)
        } catch let error as LanguageModelSession.ToolCallError {
            print(error.tool)
        } catch {
            print(error.localizedDescription)
        }
    }
}

#endif
