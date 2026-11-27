// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import Foundation
import Testing

@testable import GeneratorRPG

/// One character the evaluation runs on, with the language the result must be written in.
///
/// `entriesText` is built by `TextSummaryExtractionFormatter.formatCharacter`, the formatter the
/// Character extraction screen and batch use (through `CharacterSheetText`): the values with their
/// markdown links reduced to the labels, then the portrait photo's description and tags. Values
/// that are formulas over other values hold real links, so the stripping is exercised too.
struct CharacterSummaryFixture: Codable, Sendable, CustomTestStringConvertible {
    struct Entry: Codable, Sendable {
        let name: String
        let value: String
    }

    let name: String
    /// Passed to the analyzer as `outputLanguage`, e.g. "English" or "German".
    let outputLanguage: String
    /// The localized "Character" the app puts before the name: "Character" or "Charakter".
    let label: String
    /// The character's name as the user typed it. Empty for a character that still needs one.
    let characterName: String
    let entries: [Entry]
    var portraitDescription: String = ""
    var portraitTags: [String] = []
    let expectation: CharacterSummaryExpectation

    var testDescription: String { "\(name) (\(outputLanguage))" }

    var entriesText: String {
        TextSummaryExtractionFormatter.formatCharacter(
            title: label,
            name: characterName,
            entries: entries.map { ($0.name, $0.value) },
            portraitDescription: portraitDescription,
            portraitTags: portraitTags
        )
    }

    /// A link to another value of the character, as the sheet editor writes it.
    static func link(_ name: String) -> String {
        LinkBuilder.markdown(name: name, module: .value, itemId: linkItemId, entryId: linkEntryId)
    }

    private static let linkItemId = UUID(uuidString: "6B1D2C3E-4F50-4A61-8B72-9C83D4E5F607") ?? UUID()
    private static let linkEntryId = UUID(uuidString: "7C2E3D4F-5061-4B72-9C83-AD94E5F60718") ?? UUID()
}

// MARK: - Fixtures

extension CharacterSummaryFixture {
    /// Original characters written for this evaluation: player characters, NPCs, an animal and
    /// monsters, fantasy, science fiction and 1920s horror, named and unnamed, with and without a
    /// portrait, with and without a player, a race of the game's own world, German with German
    /// output and German with English output.
    static let all: [CharacterSummaryFixture] = [
        dwarfFighter, innkeeper, ashWyrm, goblinSkirmisher, freighterPilot,
        aerztinBerlin, fjordzwergWalfaenger, elvenRangerFromGerman, caveBear
    ]

    static let dwarfFighter = CharacterSummaryFixture(
        name: "Dwarf fighter (named player character)",
        outputLanguage: "English",
        label: "Character",
        characterName: "Brakka Ironvein",
        entries: [
            Entry(name: "Species", value: "Dwarf"),
            Entry(name: "Class", value: "Fighter"),
            Entry(name: "Level", value: "5"),
            Entry(name: "Strength", value: "17"),
            Entry(name: "Constitution", value: "16"),
            Entry(name: "Intelligence", value: "9"),
            Entry(name: "Hit Points", value: "\(link("Constitution"))+\(link("Level"))*10"),
            Entry(name: "Armor Class", value: "18"),
            Entry(name: "Weapon", value: "Warhammer of the Deep Halls, 1d8+3"),
            Entry(name: "Background", value: "A former mine guard who searches for the lost forge of her clan."),
            Entry(name: "Player", value: "Mara Lindqvist")
        ],
        expectation: CharacterSummaryExpectation(
            race: ["dwarf"],
            occupation: ["fighter", "warrior"],
            playerName: "Mara Lindqvist",
            traitConcepts: ["strong", "strength", "tough", "sturdy", "resilient", "endur", "armor", "hammer", "weapon", "forge", "clan", "loyal", "determined", "guard"],
            descriptionConcepts: ["dwarf", "fighter", "warrior", "forge", "clan", "mine"]
        )
    )

    static let innkeeper = CharacterSummaryFixture(
        name: "Innkeeper (unnamed NPC)",
        outputLanguage: "English",
        label: "Character",
        characterName: "",
        entries: [
            Entry(name: "Role", value: "Innkeeper of the Crooked Lantern"),
            Entry(name: "Personality", value: "Loud, generous with ale, never forgets a debt."),
            Entry(name: "Wants", value: "To buy the empty mill and turn it into a brewery."),
            Entry(name: "Secret", value: "Hides stolen temple relics in the cellar for the thieves' guild."),
            Entry(name: "Knows", value: "Every rumor that passes through town."),
            Entry(name: "Speech", value: "Calls everyone 'friend' and laughs at her own jokes."),
            Entry(name: "Hit Points", value: "9")
        ],
        expectation: CharacterSummaryExpectation(
            race: ["human"],
            occupation: ["innkeeper", "tavern", "host", "barkeep", "landlady"],
            traitConcepts: ["generous", "loud", "secret", "smuggl", "fence", "thie", "gossip", "rumor", "informed", "ambitious", "debt", "relic", "brew", "jovial", "cheerful"],
            descriptionConcepts: ["innkeeper", "inn", "tavern", "lantern", "secret", "relic", "thie"],
            descriptiveNameTerms: ["innkeeper", "tavern", "lantern", "keeper", "host"]
        )
    )

    static let ashWyrm = CharacterSummaryFixture(
        name: "Ash wyrm (named monster)",
        outputLanguage: "English",
        label: "Character",
        characterName: "Ash Wyrm",
        entries: [
            Entry(name: "Type", value: "Huge dragon"),
            Entry(name: "Challenge", value: "11"),
            Entry(name: "Armor Class", value: "19"),
            Entry(name: "Hit Points", value: "200"),
            Entry(name: "Breath Weapon", value: "A 60 ft cone of burning ash, 3d10 fire damage, recharges on a 5 or 6."),
            Entry(name: "Bite", value: "+10 to hit, 2d10+6 piercing"),
            Entry(name: "Lair", value: "The caldera of a dormant volcano."),
            Entry(name: "Weakness", value: "Cold damage makes it sluggish for one round.")
        ],
        expectation: CharacterSummaryExpectation(
            race: ["dragon", "wyrm"],
            occupation: [],
            traitConcepts: ["fire", "ash", "breath", "volcan", "armor", "tough", "powerful", "durable", "cold", "bite"],
            descriptionConcepts: ["dragon", "wyrm", "volcan", "ash", "fire", "breath"]
        )
    )

    /// Almost only numbers: the analyzer has little prose to go on; the role is its occupation.
    static let goblinSkirmisher = CharacterSummaryFixture(
        name: "Goblin skirmisher (unnamed stat block)",
        outputLanguage: "English",
        label: "Character",
        characterName: "",
        entries: [
            Entry(name: "Type", value: "Small humanoid (goblinoid)"),
            Entry(name: "Role", value: "Skirmisher"),
            Entry(name: "Armor Class", value: "15"),
            Entry(name: "Hit Points", value: "7"),
            Entry(name: "Speed", value: "30 ft"),
            Entry(name: "Dexterity", value: "14"),
            Entry(name: "Scimitar", value: "+4 to hit, 1d6+2 slashing"),
            Entry(name: "Shortbow", value: "+4 to hit, range 80/320 ft, 1d6+2 piercing"),
            Entry(name: "Nimble Escape", value: "Disengage or hide as a bonus action.")
        ],
        expectation: CharacterSummaryExpectation(
            race: ["goblin"],
            occupation: ["skirmisher", "scout", "archer", "raider", "ambusher", "warrior"],
            traitConcepts: ["nimble", "agil", "stealth", "sneak", "escape", "hide", "evasive", "quick", "dexter", "bow", "archer", "ranged"],
            descriptionConcepts: ["goblin"],
            descriptiveNameTerms: ["goblin", "skirmisher", "goblinoid"]
        )
    )

    /// A portrait with a description and tags after the values.
    static let freighterPilot = CharacterSummaryFixture(
        name: "Freighter pilot (named, with portrait)",
        outputLanguage: "English",
        label: "Character",
        characterName: "Rook Vashti",
        entries: [
            Entry(name: "Role", value: "Freighter pilot and part-time smuggler"),
            Entry(name: "Ship", value: "The Rusty Comet, a light freighter with hidden cargo bays"),
            Entry(name: "Reflexes", value: "4"),
            Entry(name: "Piloting", value: "\(link("Reflexes"))+3"),
            Entry(name: "Cybernetics", value: "Neural jack for direct ship control"),
            Entry(name: "Debt", value: "Owes 40,000 credits to the Saffron Syndicate."),
            Entry(name: "Blaster", value: "2d6")
        ],
        portraitDescription: "A woman in her thirties in a worn flight jacket, a cybernetic jack behind her ear, leaning against the landing gear of a battered freighter.",
        portraitTags: ["Pilot", "Spaceport", "Cyberpunk"],
        expectation: CharacterSummaryExpectation(
            race: ["human"],
            occupation: ["pilot", "smuggler"],
            traitConcepts: ["ace", "pilot", "reflex", "cybernetic", "neural", "debt", "indebted", "daring", "smuggl", "hidden", "quick"],
            descriptionConcepts: ["pilot", "smuggl", "freighter", "ship", "debt", "syndicate"]
        )
    )

    static let aerztinBerlin = CharacterSummaryFixture(
        name: "Ärztin im Berlin der 1920er",
        outputLanguage: "German",
        label: "Charakter",
        characterName: "Dr. Helene Barth",
        entries: [
            Entry(name: "Beruf", value: "Ärztin an der Charité"),
            Entry(name: "Epoche", value: "1920er Jahre, Berlin"),
            Entry(name: "Konstitution", value: "60"),
            Entry(name: "Größe", value: "55"),
            Entry(name: "Trefferpunkte", value: "(\(link("Konstitution"))+\(link("Größe")))/10"),
            Entry(name: "Stabilität", value: "58"),
            Entry(name: "Fertigkeiten", value: "Medizin 70, Erste Hilfe 60, Okkultismus 25"),
            Entry(name: "Hintergrund", value: "Behandelte einen Patienten, der von einem Kult in der Kanalisation sprach, und ist seitdem auf der Suche nach ihm.")
        ],
        expectation: CharacterSummaryExpectation(
            race: ["mensch"],
            occupation: ["ärztin", "arzt", "medizin"],
            traitConcepts: ["medizin", "heil", "erste hilfe", "okkult", "neugier", "entschlossen", "mutig", "wissbegierig", "kult", "ermittl", "hartnäckig"],
            descriptionConcepts: ["ärztin", "arzt", "kult", "berlin", "charité", "patient"],
            forbiddenTerms: ["doctor", "physician", "investigator", "cult", "female", "human"]
        )
    )

    /// A race of the game's own world: it stays "Fjordzwerg", it is not turned into "Zwerg".
    static let fjordzwergWalfaenger = CharacterSummaryFixture(
        name: "Fjordzwerg Walfänger (eigenes Volk)",
        outputLanguage: "German",
        label: "Charakter",
        characterName: "Harald Eisbart",
        entries: [
            Entry(name: "Volk", value: "Fjordzwerg"),
            Entry(name: "Beruf", value: "Walfänger"),
            Entry(name: "Stärke", value: "18"),
            Entry(name: "Geschick", value: "11"),
            Entry(name: "Seefahrt", value: "\(link("Geschick"))+6"),
            Entry(name: "Waffe", value: "Schwere Harpune, 2W6"),
            Entry(name: "Hintergrund", value: "Verlor sein Schiff im Sturm an eine Seeschlange und schwor ihr Rache.")
        ],
        portraitDescription: "Ein bärtiger Zwerg im Ölzeug steht mit einer Harpune am Bug eines Walfangschiffs.",
        portraitTags: ["Zwerg", "Harpune", "Meer"],
        expectation: CharacterSummaryExpectation(
            race: ["fjordzwerg"],
            occupation: ["walfänger", "walfang", "harpunier", "seefahrer", "seemann"],
            traitConcepts: ["stark", "kräftig", "rache", "rachsüchtig", "harpune", "see", "sturm", "entschlossen", "unerbittlich", "zäh"],
            descriptionConcepts: ["fjordzwerg", "zwerg", "walfänger", "walfang", "seeschlange", "rache", "harpune"],
            forbiddenTerms: ["dwarf", "whaler", "sailor", "revenge", "strong"]
        )
    )

    /// German values with English output, as a German user who picks English output sees it.
    static let elvenRangerFromGerman = CharacterSummaryFixture(
        name: "Elfische Waldläuferin (German values, unnamed)",
        outputLanguage: "English",
        label: "Charakter",
        characterName: "",
        entries: [
            Entry(name: "Volk", value: "Elfe"),
            Entry(name: "Klasse", value: "Waldläuferin"),
            Entry(name: "Geschicklichkeit", value: "18"),
            Entry(name: "Stärke", value: "10"),
            Entry(name: "Initiative", value: "\(link("Geschicklichkeit"))+2"),
            Entry(name: "Waffe", value: "Langbogen, 1W8 Stichschaden"),
            Entry(name: "Begleiter", value: "Ein grauer Wolf namens Asche"),
            Entry(name: "Auftrag", value: "Bewacht die Grenze des Nebelwaldes gegen Orks aus dem Norden."),
            Entry(name: "Spieler", value: "Jonas Reuter")
        ],
        expectation: CharacterSummaryExpectation(
            race: ["elf", "elven"],
            occupation: ["ranger"],
            playerName: "Jonas Reuter",
            traitConcepts: ["archer", "archery", "bow", "marksman", "dexter", "agil", "nimble", "wolf", "companion", "beast", "guard", "watchful", "vigilant", "quick"],
            descriptionConcepts: ["ranger", "elf", "elven", "forest", "wolf", "border", "orc"],
            descriptiveNameTerms: ["ranger", "elf", "elven", "forest", "warden", "guardian"],
            // "Nebelwald" is the forest's name, which may stay as it is, like "Fjordzwerg".
            forbiddenTerms: ["Waldläufer", "Elfe", "Bogen", "Grenze", "weiblich"]
        )
    )

    /// An animal: the race is the animal's name ("Brown bear", "Cave bear"), and with no class,
    /// occupation or role on the sheet the occupation stays empty.
    static let caveBear = CharacterSummaryFixture(
        name: "Cave bear (animal, unnamed)",
        outputLanguage: "English",
        label: "Character",
        characterName: "",
        entries: [
            Entry(name: "Size", value: "Large"),
            Entry(name: "Strength", value: "19"),
            Entry(name: "Dexterity", value: "10"),
            Entry(name: "Hit Points", value: "42"),
            Entry(name: "Bite", value: "+6 to hit, 1d8+4 piercing"),
            Entry(name: "Claws", value: "+6 to hit, 2d6+4 slashing"),
            Entry(name: "Keen Smell", value: "Advantage on Perception checks that rely on smell."),
            Entry(name: "Habitat", value: "Caves high in the mountains."),
            Entry(name: "Behavior", value: "Defends its cubs fiercely and attacks anyone who comes too close to the den.")
        ],
        portraitDescription: "A huge brown bear rearing up at the mouth of a dark cave, snow on its fur.",
        portraitTags: ["Bear", "Cave", "Mountains"],
        expectation: CharacterSummaryExpectation(
            race: ["bear"],
            occupation: [],
            traitConcepts: ["strong", "strength", "powerful", "smell", "scent", "keen", "protective", "fierce", "claw", "bite", "territorial", "mountain", "cave"],
            descriptionConcepts: ["bear"],
            descriptiveNameTerms: ["bear", "cave", "grizzly"]
        )
    )
}

#endif
