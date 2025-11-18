// @copyright André Trettin

#if !os(tvOS)

import FoundationModels
import Playgrounds
import Foundation

#Playground("Chat with out structure") {
//    let instructions = """
//            Your job is to create new role play adventure. The game master will ask you question about character, quest and backgrounds. 
//            """
    let instructions = """
            You are an assitent to support the game master for a fanatasy game. 
            """

    let session = LanguageModelSession(instructions: instructions)

//    let prompt = Prompt {
//        "I need 7 dwarven brother. The first one is named Baergurn. All brother names should start with Baer-. Baergurn is the oldest and a fighter with a great Dwarven battleaxe. The yougest one called Baergunni and he is a healer and famous cook. Can you create the other brothers with their special abilities and background?"
//    }

    let prompt = Prompt {
        "Give my some dwarven names and then names for pub where these drwaves could be."
    }

    do {
        let response = try await session.respond(to: prompt)
        print(response.content)
        
    } catch {
        if let error = error as? LanguageModelSession.GenerationError {
            print(error.localizedDescription)
        }
        print(error.localizedDescription)
    }
}


#Playground("Prompt Builder") {
    let instructions = """
            Your job is to identify the the type of text, and split into Adventure, Map, Character or Table related text blocks. 
            """
    let session = LanguageModelSession(instructions: instructions)

    let prompt = Prompt {
        """
        After meeting several obstacles in the
        marsh the PCs find the ruins of a tower atop
        a rocky hill. Only the foundations remain of
        the ruined tower. Inside the remains of the
        tower, footprints can clearly be seen (MIN
        + RE + 6) in the vicinity of several recently
        used fire pits and some food leftovers.
        A secret trapdoor, camouflaged by moss
        and netting, opens to a stairway (MIN + RE
        + 2) leading downwards.
        1. GUARDROOM Two drunken brigands snore
        heavily slumped over a table. There are 4
        wine bottles on the table only one is full,
        worth 1GP).
        2. EMPTY ROOM There is an apple on the floor.
        3. STOREROOM In this room there are 4 lengths
        of 10M rope, 2 lanterns, 8 bottles of lamp
        oil, a bucket, 12 applications of weapon
        paste in a wooden casket, 14 short swords,
        9 long swords and 12 daggers.
        4. BARRELS There are 4 barrels of beer here
        each worth 5GP and 2 barrels of wine, each
        worth 10 GP. On one of the barrels there is
        a crowbar worth 1GP.
        5. DOGS CHAMBER This chamber is locked from
        the outside. Inside the brigands keep 4
        bloodhounds (use Wolf stats). The animals
        begin to bark half a minute after the party
        enters the room.
        6. CARD GAME At a tarnished and shaky wooden
        table brigands play cards (1 for each party
        member). Each brigand is carrying d20 CP.
        In addition one has 2 six-sided dice.
        7. EMPTY ROOM Not used by the brigands.
"""
    }
    
    do {
        let stream = session.streamResponse(to: prompt, generating: BlockGenModel.self)

        for try await partialResponse in stream {
            print(partialResponse.content)
        }
        
    } catch let error as LanguageModelSession.GenerationError {
        print(error.localizedDescription)
    } catch let error as LanguageModelSession.ToolCallError {
        print(error.tool)
    } catch {
        print(error.localizedDescription)
    }

//    do {
//        let response = try await session.respond(to: prompt)
//    } catch {
//        print(error.localizedDescription)
//    }
}

#endif
