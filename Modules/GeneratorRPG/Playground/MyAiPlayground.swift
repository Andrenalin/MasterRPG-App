// @copyright André Trettin

import FoundationModels
import Playgrounds

#Playground {
    let model = SystemLanguageModel.default

        // The availability property provides detailed information on the model's state.
        switch model.availability {
            case .available:
                print("Foundation Models is available and ready to go!")

            case .unavailable(.deviceNotEligible):
                print("The model is not available on this device.")

            case .unavailable(.appleIntelligenceNotEnabled):
                print("Apple Intelligence is not enabled in Settings.")

            case .unavailable(.modelNotReady):
                print("The model is not ready yet. Please try again later.")

            case .unavailable(let other):
                print("The model is unavailable for an unknown reason.")
        }
    
    let instructions = """
            Your job is to create new role play adventure.
            """
    let session = LanguageModelSession(instructions: instructions)

    let useCharacter = true
    // The Prompt builder allows for conditional logic.
    let prompt = Prompt {
        "Generate a fantasy adventure in the world of DungeonSlayers."
        if useCharacter {
            "Include non player character per scenario"
        }
    }
    let response = try await session.respond(to: prompt,
                                             generating: CampaignGenModel.self)
}
