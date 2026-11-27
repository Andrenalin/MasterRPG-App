// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import Foundation
import Testing

@testable import GeneratorRPG

/// The modules whose "Extract Information" runs the generic text analysis
/// (`TextSummaryAnalyzers.analyzer(for:)`) and that this evaluation covers.
enum ModuleSummaryKind: String, Codable, Sendable, CaseIterable {
    case adventure
    case map

    var module: NetworkModules {
        switch self {
        case .adventure: .adventure
        case .map: .map
        }
    }

    /// The label `compactText(for:)` writes before the item's name (the English module title).
    var textTitle: String {
        switch self {
        case .adventure: "Adventure"
        case .map: "Map"
        }
    }

    /// Prefix of the metric names, so Adventure and Map results stay apart in the report.
    var metricPrefix: String {
        switch self {
        case .adventure: "Adventure"
        case .map: "Map"
        }
    }
}

/// One adventure or map the evaluation runs on, with the language the title, description and tags
/// must be written in. Adventure entries are scenes and chapters, map entries are rooms. The text is
/// built like the app builds it: "<Module>: <name>", then "- name: content" per entry with markdown
/// links reduced to their labels (`compactText(for:)` for adventures); a map adds its photo's
/// description and tags (`TextSummaryExtractionFormatter.formatMap`, as `MapSheetText` does).
struct ModuleSummaryFixture: Codable, Sendable, CustomTestStringConvertible {
    struct Entry: Codable, Sendable {
        let name: String
        /// May contain markdown links (`[Label](rpg://...)`) like real entries; only the label reaches the model.
        let content: String
    }

    let kind: ModuleSummaryKind
    let name: String
    /// Passed to the analyzer as `outputLanguage`, e.g. "English" or "German".
    let outputLanguage: String
    /// The item's name as the user typed it. Empty for an item that still needs a title.
    let itemName: String
    let entries: [Entry]
    /// The map photo's description, as the photo analysis or the user wrote it. Empty for
    /// adventures and for maps whose photo has none.
    var photoDescription = ""
    /// The map photo's tags. Empty for adventures and for maps whose photo has none.
    var photoTags: [String] = []
    /// The kinds of place a map's first tag may name (`MapPlaceKind`), written in `outputLanguage`.
    /// Empty for adventures.
    var mapKinds: [MapPlaceKind] = []
    let expectation: TableSummaryExpectation

    var testDescription: String { "\(kind.textTitle) \(name) (\(outputLanguage))" }

    var entriesText: String {
        switch kind {
        case .adventure:
            TextSummaryExtractionFormatter.formatEntries(
                title: kind.textTitle,
                name: itemName,
                entries: entries.map { ($0.name.withoutLink(), $0.content.withoutLink()) }
            )
        case .map:
            TextSummaryExtractionFormatter.formatMap(
                title: kind.textTitle,
                name: itemName,
                entries: entries.map { ($0.name, $0.content) },
                photoDescription: photoDescription,
                photoTags: photoTags
            )
        }
    }

    static func all(for kind: ModuleSummaryKind) -> [ModuleSummaryFixture] {
        switch kind {
        case .adventure: adventures
        case .map: maps
        }
    }
}

// MARK: - Links

private enum FixtureLink {
    /// A link like the ones the app writes into entries (`rpg://MODULE/kind/itemId`); fixed ids keep
    /// the fixtures deterministic.
    static func character(_ label: String, _ id: Int) -> String { link(label, module: "CHARACTER", id: id) }
    static func map(_ label: String, _ id: Int) -> String { link(label, module: "MAP", id: id) }
    static func table(_ label: String, _ id: Int) -> String { link(label, module: "TABLE", id: id) }
    static func photo(_ label: String, _ id: Int) -> String { link(label, module: "PHOTO", id: id) }

    private static func link(_ label: String, module: String, id: Int) -> String {
        let digits = String(id)
        let uuid = "00000000-0000-0000-0000-" + String(repeating: "0", count: max(12 - digits.count, 0)) + digits
        return "[\(label)](rpg://\(module)/1/\(uuid))"
    }
}

// MARK: - Adventures

extension ModuleSummaryFixture {
    /// Original adventures written for this evaluation: horror, sci-fi heist (named), German with
    /// German output, German with English output.
    static let adventures: [ModuleSummaryFixture] = [
        drownedLighthouse, glassOrchidHeist, fluchVonRabenstein, collapsedMineFromGerman
    ]

    static let drownedLighthouse = ModuleSummaryFixture(
        kind: .adventure,
        name: "Drowned lighthouse",
        outputLanguage: "English",
        itemName: "",
        entries: [
            Entry(name: "Hook", content: "The harbor master of Saltmere hires the party: the lighthouse has been dark for three nights and two fishing boats ran aground."),
            Entry(name: "Arrival in Saltmere", content: "The fishing village is hostile and silent. \(FixtureLink.character("Widow Hesk", 1)) claims her husband walked into the sea singing."),
            Entry(name: "The keeper's diary", content: "In the cottage the party finds the diary of \(FixtureLink.character("Keeper Aldous", 2)). His last pages describe voices in the tide."),
            Entry(name: "The lighthouse", content: "Seaweed covers the spiral stairs. See \(FixtureLink.map("Lighthouse", 3)). At the top, the lamp has been smashed from inside."),
            Entry(name: "The drowned cult", content: "Villagers wearing kelp crowns meet in a sea cave at low tide and offer sailors to something beneath the waves."),
            Entry(name: "Finale", content: "The party must relight the lamp before the high tide brings the drowned ones ashore. Roll on \(FixtureLink.table("Tide Horrors", 4)) each round.")
        ],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["mystery", "investigation", "horror", "haunt"],
                    ["lighthouse", "coast", "sea", "harbor", "harbour", "fishing village", "village", "saltmere"],
                    ["cult", "drowned", "undead", "ritual", "tide"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["lighthouse", "saltmere", "drowned", "tide", "sea", "cult", "dark"]],
            descriptionConcepts: [["lighthouse", "saltmere", "village", "cult", "drowned", "sea", "tide", "investigat"]]
        )
    )

    static let glassOrchidHeist = ModuleSummaryFixture(
        kind: .adventure,
        name: "Casino station heist (named)",
        outputLanguage: "English",
        itemName: "Operation Glass Orchid",
        entries: [
            Entry(name: "Briefing", content: "\(FixtureLink.character("Fixer Ines Varga", 11)) offers the crew a fortune to steal the Glass Orchid, a data core kept in the vault of the orbital casino Halcyon."),
            Entry(name: "Casing the station", content: "The crew poses as high rollers, maps the guard rotations and learns that the vault opens only during the shift change."),
            Entry(name: "Getting in", content: "A bribed croupier, forged invitations or a spacewalk along the hull. See \(FixtureLink.map("Halcyon Deck 3", 12))."),
            Entry(name: "The vault", content: "Laser grids, a security AI named WARDEN and a pressure plate floor protect the core."),
            Entry(name: "Double cross", content: "Varga sells the crew out to the casino's corporate owners once the core is out of the vault."),
            Entry(name: "Escape", content: "A chase through the docking ring to the stolen shuttle while station security closes the airlocks.")
        ],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["heist", "robbery", "theft", "infiltration", "stealth"],
                    ["sci-fi", "science fiction", "space", "station", "orbital", "cyberpunk"],
                    ["casino", "vault", "corporate", "double cross", "betrayal", "halcyon", "glass orchid"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["glass orchid", "orchid", "heist", "casino", "halcyon"]],
            descriptionConcepts: [["heist", "steal", "theft", "robbery", "casino", "vault", "station", "glass orchid", "data core"]]
        )
    )

    static let fluchVonRabenstein = ModuleSummaryFixture(
        kind: .adventure,
        name: "Fluch von Rabenstein",
        outputLanguage: "German",
        itemName: "",
        entries: [
            Entry(name: "Einstieg", content: "Im Dorf Rabenstein verdorren seit dem letzten Vollmond die Felder, und die Kinder haben Albträume von einer Frau in Schwarz."),
            Entry(name: "Der Dorfschulze", content: "\(FixtureLink.character("Schulze Berthold", 21)) bittet die Helden um Hilfe und verschweigt, dass er die alte Kräuterfrau vertrieben hat."),
            Entry(name: "Die Kräuterfrau", content: "Im Moor lebt \(FixtureLink.character("Mutter Ilsabe", 22)). Sie hat den Fluch nicht gesprochen, kennt aber den Weg zur Burgruine."),
            Entry(name: "Die Burgruine", content: "In der Gruft der Ruine liegt die verfluchte Gräfin, deren Grab beim Steinraub geschändet wurde. Siehe \(FixtureLink.map("Burgruine Rabenstein", 23))."),
            Entry(name: "Showdown", content: "Die Helden müssen die geraubten Grabsteine zurückbringen oder den Geist der Gräfin im Kampf bannen."),
            Entry(name: "Ausklang", content: "Wird der Fluch gebrochen, tragen die Felder wieder Frucht und das Dorf feiert ein Erntefest.")
        ],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["fluch", "verflucht", "geist", "spuk", "untot"],
                    ["dorf", "burgruine", "ruine", "moor", "gruft", "burg", "rabenstein"],
                    ["horror", "grusel", "fantasy", "mittelalter", "dark fantasy", "detektiv", "ermittlung", "geheimnis"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["fluch", "rabenstein", "gräfin", "geist", "ruine", "verflucht"]],
            descriptionConcepts: [["fluch", "rabenstein", "dorf", "gräfin", "geist", "ruine", "verflucht"]],
            forbiddenTerms: ["curse", "village", "ghost", "countess", "adventure"]
        )
    )

    /// German entries, English output: the instructions say the output is written in the requested
    /// language regardless of the input language.
    static let collapsedMineFromGerman = ModuleSummaryFixture(
        kind: .adventure,
        name: "Eingestürzte Mine (German entries)",
        outputLanguage: "English",
        itemName: "",
        entries: [
            Entry(name: "Auftrag", content: "Die Zwergenfamilie Eisenbart bittet die Gruppe, sieben verschüttete Bergleute aus der Silbermine zu retten."),
            Entry(name: "Der Abstieg", content: "Der Hauptschacht ist eingestürzt; die Gruppe klettert durch alte Lüftungsschächte. Siehe \(FixtureLink.map("Silbermine", 31))."),
            Entry(name: "Giftige Gase", content: "In den tiefen Stollen sammelt sich Grubengas; jede offene Flamme kann eine Explosion auslösen."),
            Entry(name: "Die Ursache", content: "Kein Unglück: Ein Felsenwurm hat sich durch die Stützbalken gefressen und lauert in einer Kaverne."),
            Entry(name: "Die Bergleute", content: "Die Verschütteten haben sich hinter einer Steinwand verbarrikadiert, \(FixtureLink.character("Vorarbeiterin Brunhild", 32)) ist verletzt."),
            Entry(name: "Rückweg", content: "Mit den Geretteten muss die Gruppe vor dem nächsten Einsturz zurück an die Oberfläche.")
        ],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["rescue", "mine", "mining", "cave-in", "collapse", "trapped miners", "miners"],
                    ["dwarf", "dwarven", "underground", "tunnel", "cavern", "silver"],
                    ["monster", "worm", "rock worm", "hazard", "gas", "fantasy", "dungeon"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["mine", "rescue", "miner", "collapse", "cave-in", "depths", "silver", "worm", "tunnel", "underground"]],
            descriptionConcepts: [["mine", "rescue", "miner", "collapse", "trapped", "dwar", "silver", "worm"]],
            forbiddenTerms: ["Zwerg", "Rettung", "Bergleute", "Stollen", "Grubengas"]
        )
    )
}

// MARK: - Maps

extension ModuleSummaryFixture {
    /// Original maps written for this evaluation: dungeon, named castle, spaceship deck, rooms with
    /// names only, German with German output and German with English output. Crypt and castle have
    /// no photo text (the extraction screen then shows its notice); the others carry the photo's
    /// description and tags like a photo the photo analysis has described.
    static let maps: [ModuleSummaryFixture] = [
        chapelCrypt, blackwaterKeep, freighterDeck, sewerNamesOnly, gasthausZumEber, elfenhainFromGerman,
        fenmoorSwamp, saltreachCity, koenigreichVarn
    ]

    static let chapelCrypt = ModuleSummaryFixture(
        kind: .map,
        name: "Crypt beneath a chapel",
        outputLanguage: "English",
        itemName: "",
        entries: [
            Entry(name: "1 Entrance stairs", content: "Worn steps lead down from a broken chapel floor. Cold air rises from below."),
            Entry(name: "2 Ossuary", content: "Old bones are stacked along the walls in neat patterns."),
            Entry(name: "3 Sarcophagus hall", content: "Six stone coffins; the lid of the largest has been moved."),
            Entry(name: "4 Flooded passage", content: "Knee deep black water hides a collapsed floor."),
            Entry(name: "5 Priest's tomb", content: "The resting place of \(FixtureLink.character("Father Mordren", 41)); his restless spirit guards a silver amulet."),
            Entry(name: "6 Secret shrine", content: "Behind a false wall an old altar holds 200 gold pieces and a cursed chalice.")
        ],
        mapKinds: [.crypt, .dungeon],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["crypt", "tomb", "catacomb", "ossuary", "dungeon", "burial"],
                    ["undead", "spirit", "skeleton", "ghost", "haunt", "bones"],
                    ["chapel", "temple", "shrine", "priest", "horror", "fantasy"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["crypt", "tomb", "catacomb", "ossuary", "chapel", "burial", "mordren"]],
            descriptionConcepts: [["crypt", "tomb", "catacomb", "ossuary", "chapel", "undead", "burial", "underground", "coffin"]]
        )
    )

    static let blackwaterKeep = ModuleSummaryFixture(
        kind: .map,
        name: "Castle (named)",
        outputLanguage: "English",
        itemName: "Blackwater Keep",
        entries: [
            Entry(name: "Gatehouse", content: "A portcullis and murder holes guard the only bridge across the moat."),
            Entry(name: "Courtyard", content: "Stables, a well and a training ground for the garrison."),
            Entry(name: "Great hall", content: "Banners of House Ashford hang above a long table. \(FixtureLink.character("Lord Ashford", 51)) holds court here."),
            Entry(name: "Barracks", content: "Bunks for thirty soldiers and a weapon rack."),
            Entry(name: "Armory", content: "Crossbows, spears and a locked chest with the castle's war chest."),
            Entry(name: "Dungeon cells", content: "Damp cells below the keep; one prisoner claims to be the rightful heir."),
            Entry(name: "North tower", content: "The wizard's study with a telescope and a view over the lake. \(FixtureLink.photo("Tower view", 52))")
        ],
        mapKinds: [.fortress],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["castle", "keep", "fortress", "stronghold", "citadel"],
                    ["garrison", "soldier", "lord", "noble", "house ashford", "ashford", "prisoner", "heir", "politic"],
                    ["medieval", "fantasy", "siege", "moat", "tower", "dungeon"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["blackwater", "castle", "keep", "fortress", "stronghold"]],
            descriptionConcepts: [["castle", "keep", "fortress", "stronghold", "blackwater", "ashford"]]
        )
    )

    static let freighterDeck = ModuleSummaryFixture(
        kind: .map,
        name: "Freighter deck",
        outputLanguage: "English",
        itemName: "",
        entries: [
            Entry(name: "Bridge", content: "Pilot and navigator seats facing a cracked viewport; the captain's console is password locked."),
            Entry(name: "Engineering", content: "The reactor hums too loud. Coolant leaks from a patched pipe."),
            Entry(name: "Cargo hold", content: "Forty sealed containers, one of them warm and scratching from inside."),
            Entry(name: "Med bay", content: "An autodoc and a cryo pod with a frozen stowaway."),
            Entry(name: "Crew quarters", content: "Six bunks, personal lockers and a hidden stash of contraband stims."),
            Entry(name: "Airlock", content: "The outer door's status light blinks red: someone overrode the safety lock.")
        ],
        photoDescription: "Top-down deck plan of a small cargo spaceship with a cockpit at the bow, a reactor at the stern and a large cargo bay in the middle.",
        photoTags: ["Spaceship", "Deck Plan", "Sci-Fi", "Cargo Bay"],
        mapKinds: [.spaceship],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["spaceship", "starship", "ship", "freighter", "vessel", "deck plan", "deck"],
                    ["sci-fi", "science fiction", "space", "cyberpunk"],
                    ["cargo", "crew", "reactor", "airlock", "contraband", "stowaway", "smuggl", "alien", "horror"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["freighter", "ship", "starship", "spaceship", "vessel", "deck", "cargo"]],
            descriptionConcepts: [["freighter", "ship", "starship", "spaceship", "vessel", "deck", "cargo", "crew"]]
        )
    )

    /// Many maps have rooms with names only; the model must still find a subject.
    static let sewerNamesOnly = ModuleSummaryFixture(
        kind: .map,
        name: "Sewer rooms with names only",
        outputLanguage: "English",
        itemName: "",
        entries: [
            Entry(name: "1 Storm drain outlet", content: ""),
            Entry(name: "2 Overflow cistern", content: ""),
            Entry(name: "3 Rat king's nest", content: ""),
            Entry(name: "4 Smugglers' landing", content: ""),
            Entry(name: "5 Collapsed sluice", content: ""),
            Entry(name: "6 Thieves' guild door", content: "")
        ],
        photoDescription: "Hand-drawn map of brick sewer tunnels below a city, with water channels, a round cistern and narrow walkways.",
        photoTags: ["Sewer", "Tunnels", "Underground", "City"],
        mapKinds: [.sewer],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["sewer", "underground", "cistern", "drain", "tunnel", "undercity"],
                    ["rats", "rat king", "smuggl", "thieves", "thief", "guild", "criminal"],
                    ["city", "urban", "dungeon", "fantasy"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["sewer", "undercity", "cistern", "drain", "tunnel", "underground", "rat king", "rats"]],
            descriptionConcepts: [["sewer", "undercity", "cistern", "drain", "tunnel", "underground"]]
        )
    )

    static let gasthausZumEber = ModuleSummaryFixture(
        kind: .map,
        name: "Gasthaus",
        outputLanguage: "German",
        itemName: "",
        entries: [
            Entry(name: "Schankraum", content: "Ein offener Kamin, sechs Tische und ein ausgestopfter Eberkopf über dem Tresen."),
            Entry(name: "Küche", content: "Hier kocht \(FixtureLink.character("Wirtin Gerlinde", 61)) Eintopf; eine Falltür führt in den Keller."),
            Entry(name: "Keller", content: "Bierfässer, Räucherwürste und ein zugemauerter Gang zu den alten Katakomben."),
            Entry(name: "Stall", content: "Platz für acht Pferde; der Stallbursche verkauft heimlich Informationen."),
            Entry(name: "Gästezimmer", content: "Vier einfache Zimmer im ersten Stock; in Zimmer drei schläft ein verwundeter Bote."),
            Entry(name: "Dachboden", content: "Staubige Kisten und ein Fenster, von dem aus man die ganze Dorfstraße sieht.")
        ],
        photoDescription: "Grundriss eines zweistöckigen Fachwerk-Gasthauses mit Schankraum, Küche, Stall und Gästezimmern.",
        photoTags: ["Gasthaus", "Grundriss", "Fachwerk", "Dorf"],
        mapKinds: [.building],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["gasthaus", "taverne", "wirtshaus", "schenke", "herberge", "gaststätte", "eber"],
                    ["dorf", "keller", "stall", "katakombe", "zimmer"],
                    ["fantasy", "mittelalter", "stadt", "treffpunkt", "rast"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["gasthaus", "taverne", "wirtshaus", "schenke", "herberge", "gaststätte", "eber"]],
            descriptionConcepts: [["gasthaus", "taverne", "wirtshaus", "schenke", "herberge", "gaststätte", "eber", "wirtin"]],
            forbiddenTerms: ["taproom", "cellar", "kitchen", "stable", "guest room"]
        )
    )

    /// German entries, English output.
    static let elfenhainFromGerman = ModuleSummaryFixture(
        kind: .map,
        name: "Elfenhain (German entries)",
        outputLanguage: "English",
        itemName: "",
        entries: [
            Entry(name: "Mondsteinbrücke", content: "Eine Brücke aus lebendem Holz, die nur bei Mondlicht sichtbar ist."),
            Entry(name: "Ratsbaum", content: "In der Krone einer uralten Eiche tagt der Rat der Elfen. \(FixtureLink.character("Hohepriesterin Aelwen", 71)) führt den Vorsitz."),
            Entry(name: "Quelle der Erinnerung", content: "Wer aus der Quelle trinkt, sieht einen Moment seiner Vergangenheit."),
            Entry(name: "Wächterring", content: "Steinerne Statuen von Hirschen erwachen, wenn Fremde den Hain ohne Erlaubnis betreten."),
            Entry(name: "Werkstatt der Bogner", content: "Elfenbögen und Pfeile mit Federn von Riesenadlern."),
            Entry(name: "Verbotener Garten", content: "Schwarze Rosen wachsen um das Grab eines verbannten Elfenprinzen.")
        ],
        photoDescription: "Farbige Karte eines Elfenhains im Wald mit einer riesigen Eiche in der Mitte, einem Bach und einer Brücke.",
        photoTags: ["Elfen", "Wald", "Hain", "Fantasy"],
        mapKinds: [.forest],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["elf", "elves", "elven", "fey", "fairy"],
                    ["grove", "forest", "woods", "glade", "sanctuary", "oak", "tree"],
                    ["fantasy", "magic", "druid", "nature", "council"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["elf", "elves", "elven", "grove", "forest", "glade", "fey", "sanctuary", "woods"]],
            descriptionConcepts: [["elf", "elves", "elven", "grove", "forest", "glade", "fey", "sanctuary", "woods"]],
            forbiddenTerms: ["Elfen", "Wald", "Brücke", "Quelle", "Ratsbaum"]
        )
    )
    /// Wilderness: the photo names the swamp, the locations only hint at it.
    static let fenmoorSwamp = ModuleSummaryFixture(
        kind: .map,
        name: "Swamp region",
        outputLanguage: "English",
        itemName: "Fenmoor",
        entries: [
            Entry(name: "Drowned village", content: "Rooftops rise from the black water; the lizardfolk use them as lookouts."),
            Entry(name: "Witch's hut", content: "A hut on stilts where \(FixtureLink.character("Old Mother Gloam", 81)) brews potions for a price."),
            Entry(name: "Will-o'-wisp trail", content: "Floating lights lead travelers away from the safe path."),
            Entry(name: "Lizardfolk camp", content: "Reed huts around a totem of a giant crocodile."),
            Entry(name: "Sunken shrine", content: "Half under water, an old shrine of a forgotten frog god."),
            Entry(name: "Ferry landing", content: "The only dry road out of the fen, guarded by a toll keeper.")
        ],
        photoDescription: "Painted overland map of a misty swamp with reed beds, winding channels, a drowned village and a ferry.",
        photoTags: ["Swamp", "Marsh", "Wilderness", "Fantasy"],
        mapKinds: [.swamp],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["swamp", "marsh", "fen", "bog", "wetland"],
                    ["lizardfolk", "witch", "wisp", "frog", "crocodile", "drowned"],
                    ["fantasy", "wilderness", "mist", "danger"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["fenmoor", "swamp", "marsh", "fen", "bog"]],
            descriptionConcepts: [["swamp", "marsh", "fen", "bog", "wetland", "fenmoor"]]
        )
    )
    /// A city map without a name; the districts must make it a city, not a building.
    static let saltreachCity = ModuleSummaryFixture(
        kind: .map,
        name: "Port city",
        outputLanguage: "English",
        itemName: "",
        entries: [
            Entry(name: "Harbor district", content: "Docks, warehouses and the fish market of Saltreach."),
            Entry(name: "Temple hill", content: "The great temple of the sea goddess looks over the bay."),
            Entry(name: "Old town", content: "Narrow alleys, taverns and the hidden hall of the thieves' guild."),
            Entry(name: "Merchant quarter", content: "Guild houses and the counting house of the Salt Company."),
            Entry(name: "City walls", content: "Three gates; the north gate is closed since the plague."),
            Entry(name: "Lighthouse", content: "A tall tower on the cliffs whose fire has gone out.")
        ],
        photoDescription: "Detailed city map of a walled port town on a bay with docks, a temple on a hill and a lighthouse.",
        photoTags: ["City", "Port", "Coast", "Medieval"],
        mapKinds: [.city],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["city", "town", "port", "harbor", "harbour"],
                    ["saltreach", "thieves", "guild", "merchant", "temple", "lighthouse", "plague", "docks"],
                    ["medieval", "fantasy", "coast", "bay", "trade", "sea"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["saltreach", "city", "town", "port", "harbor", "harbour"]],
            descriptionConcepts: [["saltreach", "city", "town", "port", "harbor", "harbour"]]
        )
    )
    /// A whole country, German output: the kind tag must be German ("Land").
    static let koenigreichVarn = ModuleSummaryFixture(
        kind: .map,
        name: "Königreich (German)",
        outputLanguage: "German",
        itemName: "Königreich Varn",
        entries: [
            Entry(name: "Hauptstadt Varnholm", content: "Sitz von \(FixtureLink.character("König Aldric", 91)) am großen Fluss."),
            Entry(name: "Eisenberge", content: "Die Zwergenminen im Norden liefern Eisen und Silber."),
            Entry(name: "Grauwald", content: "Ein dunkler Wald an der Ostgrenze, in dem Räuber hausen."),
            Entry(name: "Südmark", content: "Fruchtbare Felder und Dörfer, die dem König Getreide liefern."),
            Entry(name: "Grenzfeste Wolfstein", content: "Eine Burg, die den Pass gegen die Orks im Westen hält."),
            Entry(name: "Hafenstadt Möwenbucht", content: "Der einzige Seehafen des Reiches.")
        ],
        photoDescription: "Farbige Landkarte eines Königreichs mit Bergen im Norden, einem Fluss, Wäldern, Städten und einer Küste im Süden.",
        photoTags: ["Königreich", "Landkarte", "Fantasy", "Mittelalter"],
        mapKinds: [.country],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["königreich", "reich", "land", "varn"],
                    ["zwerg", "ork", "räuber", "könig", "aldric", "varnholm", "grenze"],
                    ["fantasy", "mittelalter", "berg", "fluss", "wald", "küste"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["varn", "königreich", "reich"]],
            descriptionConcepts: [["varn", "königreich", "reich", "land"]],
            forbiddenTerms: ["kingdom", "mountains", "forest", "country"]
        )
    )
}
#endif
