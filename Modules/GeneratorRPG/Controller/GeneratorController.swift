// @copyright André Trettin

#if !os(tvOS)

import CharacterRPG
import FoundationModels
import Foundation

@MainActor
final class GeneratorSessionModel {
    var session = LanguageModelSession()
    
    func set(session: LanguageModelSession) {
        self.session = session
    }
    
    var responses: [LanguageModelSession.ResponseStream<CharacterDataModel.GenValue>.Snapshot] = []
    
    var result: CharacterDataModel.GenValue?
    
    func append(_ content: LanguageModelSession.ResponseStream<CharacterDataModel.GenValue>.Snapshot) {
        result = try? CharacterDataModel.GenValue(content.rawContent)
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
    
    @MainActor func generate(from model: GeneratorDataModel) {
        let reference: CharacterDataModel.GenValue? = characterRoot.generable(id: model.referenceId)
        
        let session = LanguageModelSession {
        """
        You are a character generator assistant for a role play game. Use the reference character \(reference) to understand the sturcture of the response. 
        """
        }
        self.model.set(session: session)
        session.prewarm()
    }
    
    @MainActor func generateAdventure(from model: GeneratorDataModel) {
//        let instructions = """
//                Your are an assistent to create new adventures for a RPG game.
//                """
        let instructions = """
                Helfe dabei ein Abenteuer zu erstellen fuer ein Fantasy RPG.
                """
        let session = LanguageModelSession(instructions: instructions)
        
        self.model.set(session: session)
        session.prewarm()
    }
    
    @MainActor func request(message: String) {
        Task {
            do {
                let stream = model.session.streamResponse(
                    generating: CharacterDataModel.GenValue.self,
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
//                            "Give it a fun title and description."
//                            "Here is an example of the desired format, but don't copy its content:"
//                            Itinerary.exampleTripToJapan
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
