// @copyright André Trettin

import FoundationModels
import Playgrounds

#Playground {
    let instructions = """
            Your job is to create new role play adventure. The game master will ask you question about character, quest and backgrounds. 
            """
    let session = LanguageModelSession(instructions: instructions)

    let prompt = Prompt {
        "I need 7 dwarven brother. The first one is named Baergurn. All brother names should start with Baer-. Baergurn is the oldest and a fighter with a great Dwarven battleaxe. The yougest one called Baergunni and he is a healer and famous cook. Can you create the other brothers with their special abilities and background?"
    }
    let response = try await session.respond(to: prompt)
}
