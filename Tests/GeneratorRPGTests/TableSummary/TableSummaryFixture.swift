// @copyright André Trettin

#if !os(tvOS)

import Foundation
import Testing

@testable import GeneratorRPG

/// One table the evaluation runs on, with the language the title, description and tags must be
/// written in. The entries go through the same formatter as the app's extraction screen.
struct TableSummaryFixture: Codable, Sendable, CustomTestStringConvertible {
    struct Entry: Codable, Sendable {
        let name: String
        let content: String
    }

    let name: String
    /// Passed to the analyzer as `outputLanguage`, e.g. "English" or "German".
    let outputLanguage: String
    /// The table's name as the user typed it. Empty for a table that still needs a title, which is
    /// the usual reason to run the extraction.
    let tableName: String
    let entries: [Entry]
    let expectation: TableSummaryExpectation

    var testDescription: String { "\(name) (\(outputLanguage))" }

    var entriesText: String {
        TextSummaryExtractionFormatter.formatEntries(
            title: "Table",
            name: tableName,
            entries: entries.map { ($0.name, $0.content) }
        )
    }
}

// MARK: - Fixtures

extension TableSummaryFixture {
    /// Original tables written for this evaluation: different genres and kinds of table, named and
    /// unnamed, German with German output and German with English output (the analyzer must write
    /// in the requested language regardless of the input).
    static let all: [TableSummaryFixture] = [
        forestEncounters, treasureHoard, docksideGossip, sanityBreakdowns,
        tavernenGeruechte, wildmagiePatzer, mountainWeatherFromGerman
    ]

    static let forestEncounters = TableSummaryFixture(
        name: "Forest encounters",
        outputLanguage: "English",
        tableName: "",
        entries: [
            Entry(name: "1 Wolf pack", content: "Four hungry wolves circle the party at dusk."),
            Entry(name: "2 Lost merchant", content: "A merchant with a broken wagon offers a discount for help."),
            Entry(name: "3 Giant spider", content: "A spider the size of a pony drops from the canopy."),
            Entry(name: "4 Rangers' camp", content: "Two rangers share their fire and warn of goblins to the north."),
            Entry(name: "5 Fairy ring", content: "A ring of mushrooms hums with magic; stepping inside teleports the party."),
            Entry(name: "6 Bandit ambush", content: "Six bandits demand a toll of 10 gold pieces each."),
            Entry(name: "7 Treant", content: "An ancient treant asks the party to stop the loggers."),
            Entry(name: "8 Nothing", content: "The forest is quiet. Birds sing.")
        ],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["encounter", "random encounter"],
                    ["forest", "wilderness", "woods", "wilds"],
                    ["fantasy", "monster", "creature", "bandit", "wolf"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["encounter", "forest", "woods", "wilderness", "wilds"]],
            descriptionConcepts: [["encounter", "forest", "woods", "wilderness", "creature", "monster"]]
        )
    )

    static let treasureHoard = TableSummaryFixture(
        name: "Treasure hoard",
        outputLanguage: "English",
        tableName: "",
        entries: [
            Entry(name: "01-20 Coins", content: "A leather purse with 3d6 x 10 silver pieces."),
            Entry(name: "21-35 Gems", content: "Two uncut garnets worth 50 gold pieces each."),
            Entry(name: "36-50 Silver chalice", content: "An engraved chalice from a lost temple, worth 75 gold pieces."),
            Entry(name: "51-65 Potion of healing", content: "A red potion in a stoppered vial."),
            Entry(name: "66-75 Spell scroll", content: "A scroll with one first level spell."),
            Entry(name: "76-85 Longsword +1", content: "A well balanced blade with a faint blue glow."),
            Entry(name: "86-95 Cursed ring", content: "A gold ring that tightens around the finger and cannot be removed."),
            Entry(name: "96-00 Dragon scale", content: "A palm sized scale that is warm to the touch and resists fire.")
        ],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["treasure", "loot", "hoard", "reward"],
                    ["magic", "item", "potion", "scroll", "gem", "coin", "weapon", "ring", "chalice", "cursed", "valuable"],
                    ["fantasy", "dungeon"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["treasure", "loot", "hoard", "reward", "item", "booty"]],
            descriptionConcepts: [["treasure", "loot", "hoard", "reward", "item", "gem", "coin", "magic"]]
        )
    )

    static let docksideGossip = TableSummaryFixture(
        name: "Starport rumors (named)",
        outputLanguage: "English",
        tableName: "Dockside Gossip",
        entries: [
            Entry(name: "1", content: "The freighter Maren Dawn left port with no crew listed on the manifest."),
            Entry(name: "2", content: "Customs has a new scanner that spots hidden cargo bays."),
            Entry(name: "3", content: "A corporate recruiter pays well for pilots who ask no questions."),
            Entry(name: "4", content: "The station AI locked a whole deck last night and nobody knows why."),
            Entry(name: "5", content: "Smugglers use the abandoned refinery on the third moon as a drop."),
            Entry(name: "6", content: "A cyberware clinic in sector nine installs illegal military hardware."),
            Entry(name: "7", content: "Somebody is buying every hyperdrive coil in the outer colonies.")
        ],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["rumor", "rumour", "gossip", "hook", "lead"],
                    ["sci-fi", "science fiction", "space", "starport", "station", "cyberpunk", "outer colonies"],
                    ["smuggl", "crew", "freighter", "pilot", "corporate"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["rumor", "rumour", "gossip", "dock", "starport", "port", "space", "station"]],
            descriptionConcepts: [["rumor", "rumour", "gossip", "dock", "port", "station", "space", "smuggl"]]
        )
    )

    static let sanityBreakdowns = TableSummaryFixture(
        name: "Horror sanity breakdowns",
        outputLanguage: "English",
        tableName: "",
        entries: [
            Entry(name: "1 Hysterical laughter", content: "The character laughs uncontrollably for 1d4 rounds and cannot act."),
            Entry(name: "2 Paranoia", content: "The character believes an ally is a cultist and refuses to turn their back on them."),
            Entry(name: "3 Phobia", content: "The character gains a phobia of the thing that caused the stress, such as the dark or the sea."),
            Entry(name: "4 Catatonia", content: "The character stares into nothing and does not respond until shaken."),
            Entry(name: "5 Flight", content: "The character runs screaming from the scene and hides for an hour."),
            Entry(name: "6 Hallucinations", content: "The character hears whispers and sees shapes that are not there."),
            Entry(name: "7 Obsession", content: "The character fixates on the forbidden book and tries to read it again.")
        ],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["sanity", "madness", "insanity", "mental", "fear", "stress", "breakdown", "phobia"],
                    ["horror", "cosmic", "lovecraft", "cthulhu", "cult", "eldritch", "gothic"]
                ],
                minimumMatchedGroups: 1
            ),
            titleConcepts: [["sanity", "madness", "insanity", "breakdown", "fear", "mental", "horror", "phobia", "psychological", "trauma", "stress"]],
            descriptionConcepts: [["sanity", "madness", "insanity", "breakdown", "fear", "mental", "horror", "stress", "phobia", "psychological", "trauma"]]
        )
    )

    static let tavernenGeruechte = TableSummaryFixture(
        name: "Tavernengerüchte",
        outputLanguage: "German",
        tableName: "",
        entries: [
            Entry(name: "1", content: "Der Müller soll nachts mit einem Fremden in der Kapelle gesehen worden sein."),
            Entry(name: "2", content: "Im alten Steinbruch heulen seit dem Neumond Wölfe, die zu groß für Wölfe sind."),
            Entry(name: "3", content: "Der Graf zahlt hundert Goldstücke für den Kopf des Räuberhauptmanns."),
            Entry(name: "4", content: "Die Wirtin braut ihr Bier angeblich mit Wasser aus dem verfluchten Brunnen."),
            Entry(name: "5", content: "Ein Zwerg verkauft auf dem Markt Karten zu einer vergessenen Mine."),
            Entry(name: "6", content: "Die Stadtwache sucht einen Dieb, der den Schlüssel zum Archiv gestohlen hat."),
            Entry(name: "7", content: "Auf der Landstraße verschwinden Händler, ohne dass jemals Wagen gefunden werden.")
        ],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["gerücht", "geruecht", "gerüchte", "tratsch", "klatsch", "hinweis", "abenteueraufhänger"],
                    ["kapelle", "steinbruch", "wolf", "wölfe", "graf", "räuber", "brunnen", "zwerg", "mine", "stadtwache", "dieb", "taverne", "dorf"],
                    ["fantasy", "mittelalter", "abenteuer"]
                ],
                minimumMatchedGroups: 1
            ),
            titleConcepts: [["gerücht", "tratsch", "klatsch", "taverne", "schenke", "wirtshaus", "gasthaus"]],
            descriptionConcepts: [["gerücht", "tratsch", "klatsch", "behauptung", "taverne", "schenke", "wirtshaus", "gasthaus", "dorf"]],
            forbiddenTerms: ["rumor", "rumour", "gossip", "adventure", "hook"]
        )
    )

    static let wildmagiePatzer = TableSummaryFixture(
        name: "Wildmagie-Patzer",
        outputLanguage: "German",
        tableName: "",
        entries: [
            Entry(name: "1", content: "Der Zauberer wird für eine Minute blau und leuchtet im Dunkeln."),
            Entry(name: "2", content: "Ein Schwarm Schmetterlinge bricht aus dem Mund des Zauberers hervor."),
            Entry(name: "3", content: "Alle Waffen im Umkreis von drei Metern werden zu Butter."),
            Entry(name: "4", content: "Der Zauberer schwebt zehn Runden lang einen Meter über dem Boden."),
            Entry(name: "5", content: "Ein zufälliges Mitglied der Gruppe tauscht den Platz mit dem Zauberer."),
            Entry(name: "6", content: "Eine Illusion eines tanzenden Drachen erscheint und verschwindet nach einer Minute."),
            Entry(name: "7", content: "Der Zauber misslingt, und der Zauberer vergisst seinen Namen bis zur nächsten Rast.")
        ],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["magie", "zauber", "wildmagie", "arkan"],
                    ["patzer", "chaos", "zufall", "fehlschlag", "effekt", "misslingen"],
                    ["fantasy", "regel", "würfel"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["magie", "magisch", "zauber", "wildmagie", "patzer", "chaos"]],
            descriptionConcepts: [["magie", "magisch", "zauber", "wildmagie", "patzer", "chaos", "effekt"]],
            forbiddenTerms: ["wild magic", "surge", "spell", "magic", "mishap"]
        )
    )

    /// German entries, English output: the instructions say the output is written in the requested
    /// language regardless of the input language.
    static let mountainWeatherFromGerman = TableSummaryFixture(
        name: "Hochgebirgswetter (German entries)",
        outputLanguage: "English",
        tableName: "",
        entries: [
            Entry(name: "1 Klarer Himmel", content: "Die Sicht reicht bis zum Horizont, die Luft ist eisig und trocken."),
            Entry(name: "2 Nebel", content: "Dichter Nebel verringert die Sicht auf zehn Meter; Orientierung ist schwierig."),
            Entry(name: "3 Schneesturm", content: "Heulender Wind und Neuschnee halbieren das Reisetempo."),
            Entry(name: "4 Lawine", content: "Am Hang löst sich ein Schneebrett und verschüttet den Pfad."),
            Entry(name: "5 Hagelschauer", content: "Eiskörner prasseln nieder; die Gruppe sucht besser Schutz."),
            Entry(name: "6 Föhn", content: "Ein warmer Fallwind lässt den Schnee tauen und macht die Reisenden müde."),
            Entry(name: "7 Gewitter", content: "Blitze schlagen in die Grate; Metallrüstungen sind gefährlich.")
        ],
        expectation: TableSummaryExpectation(
            tags: PdfTagExpectation(
                conceptGroups: [
                    ["weather", "climate", "storm", "blizzard", "snow"],
                    ["mountain", "alpine", "highland", "high altitude", "peaks"],
                    ["travel", "survival", "hazard", "wilderness", "exploration"]
                ],
                minimumMatchedGroups: 2
            ),
            titleConcepts: [["weather", "storm", "blizzard", "snow", "climate"]],
            descriptionConcepts: [["weather", "storm", "blizzard", "snow", "climate", "mountain", "atmospheric"]],
            forbiddenTerms: ["Wetter", "Schnee", "Gebirge", "Sturm", "Nebel"]
        )
    )
}

#endif
