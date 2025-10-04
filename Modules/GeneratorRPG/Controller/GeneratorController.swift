// @copyright André Trettin

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
}
