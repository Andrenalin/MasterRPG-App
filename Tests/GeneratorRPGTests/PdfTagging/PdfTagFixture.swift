// @copyright André Trettin

#if !os(tvOS)

import Foundation
import PDFKit
import RPGResourcesDebug
import Testing

/// One PDF the tag evaluation runs on, with the language the tags must be written in.
struct PdfTagFixture: Sendable, CustomTestStringConvertible {
    enum Source: Sendable {
        case generated(pages: [String])
        case file(URL)
    }

    let name: String
    /// Passed to the analyzer as `outputLanguage`, e.g. "English" or "German".
    let outputLanguage: String
    let source: Source
    let expectation: PdfTagExpectation

    var testDescription: String { "\(name) (\(outputLanguage))" }

    func makeDocument() throws -> PDFDocument {
        switch source {
        case .generated(let pages):
            return try PdfTagFixtureRenderer.makeDocument(pages: pages)
        case .file(let url):
            guard let document = PDFDocument(url: url) else {
                throw PdfTagFixtureError.unreadableFile(url.lastPathComponent)
            }
            return document
        }
    }
}

enum PdfTagFixtureError: Error, CustomStringConvertible {
    case unreadableFile(String)

    var description: String {
        switch self {
        case .unreadableFile(let name): "Cannot open PDF fixture \(name)"
        }
    }
}

// MARK: - Generated fixtures

extension PdfTagFixture {
    /// Original texts written for this evaluation, one per genre. They are short on purpose: the
    /// analyzer only sends about 7,000 characters to the model anyway.
    static let generated: [PdfTagFixture] = [
        cryptOfTheAshKing, starlaneProtocol, whispersInBlackmoorFen, derFluchVonRabenstein
    ]

    static let cryptOfTheAshKing = PdfTagFixture(
        name: "Fantasy dungeon adventure",
        outputLanguage: "English",
        source: .generated(pages: [
            """
            THE CRYPT OF THE ASH KING
            A fantasy dungeon adventure for four to six characters of levels 3 to 5

            Introduction
            Beneath the ruined abbey of Saint Verran lies the tomb of Haldric, the Ash King, a tyrant who \
            burned three villages before his own knights sealed him in stone. Lately the villagers of \
            Greywater hear chanting under the floor, and the dead no longer stay in their graves. The player \
            characters are hired by the village elder to enter the crypt, find the source of the unrest and \
            bring back the Ember Crown before a necromancer wakes the king.

            How to use this adventure
            The adventure is a self-contained dungeon crawl with fourteen keyed rooms, three traps, two \
            optional side vaults and a final confrontation. Read-aloud text is set in italics. Monster \
            statistics are given at the end of each room entry for a medieval fantasy role-playing game.
            """,
            """
            Area 1: The Collapsed Nave
            Rubble blocks the old nave. Four skeletons in rusted mail rise when anyone steps on the sigil in \
            the floor. A successful search reveals a hidden stair leading down to the ossuary.

            Area 4: The Ossuary
            Thousands of bones are stacked in the walls. A poison needle trap guards the lever that opens the \
            sarcophagus hall. Characters who disarm it find a potion of healing and a silver holy symbol.

            Area 9: The Ash Throne
            Haldric sits on a throne of fused cinders, flanked by two wights. The Ember Crown glows on his \
            brow. The necromancer Mirela Dross hides behind a pillar and casts fear on the party. Treasure: \
            the Ember Crown, 600 gold pieces and a +1 longsword. Defeating the Ash King lifts the curse \
            from Greywater and ends the adventure.
            """
        ]),
        expectation: PdfTagExpectation(
            conceptGroups: [
                ["adventure", "dungeon", "module", "scenario"],
                ["fantasy", "medieval"],
                ["undead", "crypt", "tomb", "skeleton", "necromancer", "curse"]
            ],
            minimumMatchedGroups: 2
        )
    )

    static let starlaneProtocol = PdfTagFixture(
        name: "Science fiction rulebook",
        outputLanguage: "English",
        source: .generated(pages: [
            """
            STARLANE PROTOCOL
            Core Rulebook - a tabletop role-playing game of smugglers, mercenaries and rogue AIs

            Chapter 1: Playing the Game
            In Starlane Protocol the players take the roles of a freighter crew working the lawless edge of \
            the Outer Colonies. One player is the Director and describes the galaxy; the others play crew \
            members. Whenever the outcome of an action is uncertain, roll percentile dice (d100) and try \
            to roll equal to or under your skill rating.

            Chapter 2: Creating a Crew Member
            Choose an origin (Spacer, Corporate, Colonist or Synthetic), distribute points between the \
            attributes Reflex, Intellect, Presence and Grit, and pick three skills such as Piloting, \
            Hacking or Firearms. Characters may install cyberware at the cost of Humanity.
            """,
            """
            Chapter 5: Starship Combat
            Ship combat is played in rounds. Each round the pilot, gunner and engineer take one action: \
            evade, fire weapons or reroute power. Shields absorb damage first, then hull points. A ship \
            reduced to zero hull is adrift and its reactor may breach.

            Chapter 7: The Director's Toolkit
            Advice for running sessions, a table for generating alien planets, rules for faction reputation \
            and a bestiary of void predators, mercenary androids and hostile corporate security drones. \
            Appendix: character sheet, ship sheet and a quick-reference page for all d100 modifiers.
            """
        ]),
        expectation: PdfTagExpectation(
            conceptGroups: [
                ["rulebook", "rules", "core rules", "system", "game system"],
                ["sci-fi", "science fiction", "space", "starship", "futuristic"],
                ["d100", "percentile", "dice", "skill", "combat"]
            ],
            minimumMatchedGroups: 2
        )
    )

    static let whispersInBlackmoorFen = PdfTagFixture(
        name: "Gothic horror investigation",
        outputLanguage: "English",
        source: .generated(pages: [
            """
            WHISPERS IN BLACKMOOR FEN
            A gothic horror investigation scenario for three to five investigators, set in 1893

            Background
            The village of Blackmoor Fen has lost eleven children in one winter. The constable calls it \
            wolves; the vicar will not leave his church. The investigators arrive by the evening train \
            to examine the disappearances for a London newspaper. What they uncover is an ancient cult \
            that feeds a sleeping thing beneath the peat bog.

            Running the horror
            Each investigator has a Sanity score. Witnessing the unnatural forces a Sanity check; failure \
            causes fear, nightmares and eventually madness. Clues are found by questioning villagers, \
            searching the vicarage and reading the diary of Doctor Ambrose Pell.
            """,
            """
            The Investigation
            Clue 1: muddy handprints on the inside of the vicarage windows. Clue 2: a hymn book whose \
            pages are filled with a language no scholar can read. Clue 3: the church bells ring at night \
            without a ringer. Each clue lowers the cult's hold on the village and raises the dread.

            The Finale
            In the crypt under the bog chapel the investigators face the cult's high priest and the \
            thing he serves. They can banish it with the ritual from the diary, flee, or gain forbidden \
            power at the price of their sanity. Several endings are provided.
            """
        ]),
        expectation: PdfTagExpectation(
            conceptGroups: [
                ["horror", "gothic", "cosmic", "cthulhu", "occult", "cult"],
                ["investigation", "mystery", "detective", "investigator"],
                ["sanity", "madness", "fear", "victorian", "1890s"]
            ],
            minimumMatchedGroups: 2
        )
    )

    /// Checks that the output language is respected for a non-English source and request.
    static let derFluchVonRabenstein = PdfTagFixture(
        name: "German fantasy adventure",
        outputLanguage: "German",
        source: .generated(pages: [
            """
            DER FLUCH VON RABENSTEIN
            Ein Fantasy-Abenteuer für drei bis fünf Helden der Stufen 2 bis 4

            Einleitung
            Die Burg Rabenstein thront seit Jahrhunderten über dem Dorf Eschenau. Seit dem Tod der alten \
            Gräfin geht dort ein Geist um, und die Bauern verlieren Vieh und Kinder an die Nacht. Der \
            Bürgermeister bittet die Helden, die Burg zu betreten, das Geheimnis der Gräfin zu lüften und \
            den Fluch zu brechen, bevor der Winter beginnt.

            Hinweise für den Spielleiter
            Das Abenteuer besteht aus zwölf Räumen, zwei Fallen und einem Rätsel. Die Werte aller Gegner \
            sind für ein klassisches Mittelalter-Rollenspiel angegeben.
            """,
            """
            Die Burg
            Im Torhaus lauern zwei Skelettwachen. Im Rittersaal erscheint der Geist der Gräfin und stellt \
            ein Rätsel; wer es löst, erhält den Schlüssel zum Verlies. Im Verlies wartet ein Vampir, der \
            die Gräfin einst verriet. Schatz: ein silberner Dolch, 300 Goldstücke und ein Zaubertrank.

            Das Ende
            Zerstören die Helden das Medaillon der Gräfin, ist der Fluch gebrochen und das Dorf Eschenau \
            wieder sicher.
            """
        ]),
        expectation: PdfTagExpectation(
            conceptGroups: [
                ["abenteuer", "szenario", "modul"],
                ["fantasy", "mittelalter"],
                ["fluch", "burg", "geist", "vampir", "untot", "spuk"]
            ],
            minimumMatchedGroups: 2,
            forbiddenTerms: ["adventure", "curse", "castle", "ghost", "dungeon"]
        )
    )
}

// MARK: - Bundled PDFs

extension PdfTagFixture {
    /// Real PDFs from the `TestPdfs` folder of `RPGResourcesDebug`, so they are in the test bundle
    /// on CI too. Expectations are written from what the analyzer actually reads: roughly the first
    /// 7,000 characters. A PDF in the folder without an entry here is not evaluated; an entry
    /// without a PDF fails `PdfTagEvaluatorTests.bundledPdfsArePresent`.
    static let bundled: [PdfTagFixture] = bundledExpectations.compactMap { entry in
        guard let url = bundledPdfUrl(named: entry.file) else {
            return nil
        }
        return PdfTagFixture(
            name: entry.file,
            outputLanguage: entry.outputLanguage,
            source: .file(url),
            expectation: entry.expectation
        )
    }

    struct BundledExpectation {
        let file: String
        let outputLanguage: String
        let expectation: PdfTagExpectation
    }

    static let bundledExpectations: [BundledExpectation] = [
        BundledExpectation(
            file: "Angriff auf das Wurzelnest.pdf",
            outputLanguage: "German",
            expectation: PdfTagExpectation(
                conceptGroups: [
                    ["abenteuer", "dungeon", "szenario"],
                    ["ratte", "ratten", "kult", "knochen"]
                ],
                forbiddenTerms: ["adventure", "rats"]
            )
        ),
        BundledExpectation(
            file: "Botho Phillip zu Eulenburg.pdf",
            outputLanguage: "German",
            expectation: PdfTagExpectation(
                conceptGroups: [
                    ["cthulhu", "lovecraft", "horror"],
                    ["charakterbogen", "charakter", "spielerbogen", "bogen"]
                ],
                forbiddenTerms: ["character sheet"]
            )
        ),
        BundledExpectation(
            file: "Brigands of Lyrkenfenn - D2G1.pdf",
            outputLanguage: "English",
            expectation: PdfTagExpectation(
                conceptGroups: [
                    ["adventure", "dungeon", "scenario"],
                    ["brigand", "bandit", "outlaw"],
                    ["tower", "ruin", "marsh", "swamp"]
                ],
                minimumMatchedGroups: 2
            )
        ),
        BundledExpectation(
            file: "Caera Krautwerk.pdf",
            outputLanguage: "German",
            expectation: PdfTagExpectation(
                conceptGroups: [
                    ["kräuter", "kraut", "pflanzen", "alchemie"],
                    ["gift", "heil", "trank", "wirkung"]
                ],
                forbiddenTerms: ["herbs"]
            )
        ),
        BundledExpectation(
            file: "Der Rostige Schüssel.pdf",
            outputLanguage: "German",
            expectation: PdfTagExpectation(
                conceptGroups: [
                    ["postapokalyp", "apokalyp", "endzeit", "gammaslayers", "strahl"],
                    ["abenteuer", "szenario", "vorschau"],
                    ["rasthof", "gasthaus", "schlüssel"]
                ],
                minimumMatchedGroups: 2,
                forbiddenTerms: ["adventure", "post-apocalyptic"]
            )
        ),
        BundledExpectation(
            file: "Die Räuber von Lyrkenfenn.pdf",
            outputLanguage: "German",
            expectation: PdfTagExpectation(
                conceptGroups: [
                    ["abenteuer", "dungeon", "szenario"],
                    ["räuber", "bande", "banditen"],
                    ["turm", "ruine", "sumpf"]
                ],
                minimumMatchedGroups: 2,
                forbiddenTerms: ["adventure", "brigand"]
            )
        ),
        BundledExpectation(
            file: "Gammaslayers.pdf",
            outputLanguage: "German",
            expectation: PdfTagExpectation(
                conceptGroups: [
                    ["rollenspiel", "regelwerk", "regeln", "grundregel"],
                    ["gammaslayers", "postapokalyp", "apokalyp", "science", "mutant", "endzeit"]
                ],
                minimumMatchedGroups: 1
            )
        ),
        BundledExpectation(
            file: "Regeln von Caera.pdf",
            outputLanguage: "German",
            expectation: PdfTagExpectation(
                conceptGroups: [
                    ["regel", "regelwerk", "regeln", "spielregeln"],
                    ["caera", "dungeonslayers", "fantasy"]
                ],
                minimumMatchedGroups: 1
            )
        ),
        BundledExpectation(
            file: "Sturmelfen.pdf",
            outputLanguage: "German",
            expectation: PdfTagExpectation(
                conceptGroups: [
                    ["elf", "elfen", "volk", "coladri"],
                    ["sturm", "hefrach", "insel", "valen coladris"]
                ],
                forbiddenTerms: ["elves", "storm"]
            )
        ),
        BundledExpectation(
            file: "Valen Coladris.pdf",
            outputLanguage: "German",
            expectation: PdfTagExpectation(
                conceptGroups: [
                    ["stadt", "viertel", "hafen"],
                    ["valen coladris", "coladri", "sturmelfen", "insel"]
                ],
                forbiddenTerms: ["city", "island"]
            )
        ),
        BundledExpectation(
            file: "Zum blauen Wunder - Feinschmecker Gasthaus.pdf",
            outputLanguage: "German",
            expectation: PdfTagExpectation(
                conceptGroups: [
                    ["gasthaus", "gaststätte", "wirtshaus", "taverne", "restaurant", "feinschmecker"],
                    ["essen", "menü", "speise", "küche", "kulinar", "gastronom", "köstlich", "gericht"]
                ],
                forbiddenTerms: ["inn", "restaurant menu"]
            )
        )
    ]

    /// Finds a bundled PDF by file name. Names are compared in composed Unicode form because the
    /// bundle can store "Schüssel" decomposed.
    static func bundledPdfUrl(named file: String) -> URL? {
        let wanted = file.precomposedStringWithCanonicalMapping
        return ResourcesDebug.testPdfUrls.first {
            $0.lastPathComponent.precomposedStringWithCanonicalMapping == wanted
        }
    }
}

#endif
