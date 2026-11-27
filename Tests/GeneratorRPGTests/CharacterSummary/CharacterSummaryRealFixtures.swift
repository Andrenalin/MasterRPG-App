// @copyright André Trettin

#if !os(tvOS)

import Foundation

@testable import GeneratorRPG

// MARK: - Real examples

/// Characters copied from the app with the Debug button "Copy Analysis Input" on the Extract
/// Information screen: the exact text the analysis reads, groups expanded. Real players' names are
/// replaced with invented ones; everything else stays as copied. The expected tags are the user's.
extension CharacterSummaryFixture {
    static let real: [CharacterSummaryFixture] = [adalbertUnheil, aquaterKaempfer, anaja]

    /// A long German sheet in groups (Basiswerte, Kampfwerte, Talente, Zauber …) with formulas,
    /// a culture next to the race ("Volk (Narrländer): Gnom") and an empty portrait description.
    /// Before groups were expanded the analysis only saw the group labels and never "Gnom".
    /// Expected tags: Gnom (or Narrländer), Schwarzmagier, Arkane Explosion, the player.
    static let adalbertUnheil = CharacterSummaryFixture(
        name: "Adalbert Unheil (real, gnome black mage in groups)",
        outputLanguage: "German",
        label: "Charakter",
        characterName: "Adalbert Unheil",
        entries: [
            Entry(name: "Basiswerte", value: ""),
            Entry(name: "Spieler", value: "Torben Albrecht"),
            Entry(name: "Volk (Narrländer)", value: "Gnom"),
            Entry(name: "Klasse", value: "Zauberwirker Schwarzmagier"),
            Entry(name: "Stufe", value: "11"),
            Entry(name: "LP", value: "0"),
            Entry(name: "TP", value: "0"),
            Entry(name: "Erfahrungspunkte", value: "5690"),
            Entry(name: "Kampfwerte", value: ""),
            Entry(name: "Lebenskraft", value: "Körper KÖR+Härte HÄ+10|-5"),
            Entry(name: "Abwehr", value: "Körper KÖR+Härte HÄ+ GesamtPA"),
            Entry(name: "Ini", value: "Agilität  AGI+Bewegung BE"),
            Entry(name: "Laufen", value: "Agilität  AGI/2+1"),
            Entry(name: "Schlagen", value: "Körper KÖR+Stärke ST"),
            Entry(name: "Schiessen", value: "Agilität  AGI+Geschick GE+Schütze"),
            Entry(name: "Zaubern", value: "Geist GEI+Aura AU-PA +Ei-Zaubern"),
            Entry(name: "Zielzauber", value: "Geist GEI+Geschick GE-PA+Schütze"),
            Entry(name: "Waffen", value: ""),
            Entry(name: "Dolch", value: ""),
            Entry(name: "Dolch", value: "Schlagen +WB+mag WB"),
            Entry(name: "Initiative", value: "Ini+1+mag WB"),
            Entry(name: "Gegnerabwehr GA", value: "0-mag WB"),
            Entry(name: "WB", value: "1"),
            Entry(name: "mag WB", value: "0"),
            Entry(name: "Waffenlos", value: "Schlagen"),
            Entry(name: "Dolch mag", value: ""),
            Entry(name: "Dolch", value: "Schlagen+WB+mag WB"),
            Entry(name: "Initiative", value: "Ini+1+mag WB"),
            Entry(name: "Gegnerabwehr GA", value: "0-mag WB"),
            Entry(name: "WB", value: "1"),
            Entry(name: "mag WB", value: "1"),
            Entry(name: "Talente", value: ""),
            Entry(name: "Alchemie", value: "1"),
            Entry(name: "Arkane Explosion", value: "3"),
            Entry(name: "Blitzmacher", value: "2"),
            Entry(name: "Diener der Dunkelheit", value: "2"),
            Entry(name: "Einbetten", value: "1"),
            Entry(name: "Feuermagier", value: "1"),
            Entry(name: "Ich muß weg", value: "1"),
            Entry(name: "Schlachtruf", value: "1"),
            Entry(name: "Schütze", value: "3"),
            Entry(name: "Sensenspötter", value: "0"),
            Entry(name: "Wahrnehmung", value: "1"),
            Entry(name: "Wissensgebiet Allgemein", value: "0"),
            Entry(name: "Wissensgebiet Rel Hefrach", value: "1"),
            Entry(name: "Wissensgebiet Rel Snarrk'Izz", value: "1"),
            Entry(name: "Wissensgebiet Seefahrt", value: "3"),
            Entry(name: "Zaubermacht", value: "3"),
            Entry(name: "Abklingendes Blut", value: "1"),
            Entry(name: "Finanzen", value: ""),
            Entry(name: "Gold GM", value: "0"),
            Entry(name: "Silber SM", value: "0"),
            Entry(name: "Kupfer KM", value: "3"),
            Entry(name: "Edelsteine Wert", value: "0"),
            Entry(name: "Gegenstände", value: ""),
            Entry(name: "Wundersames Ei", value: ""),
            Entry(name: "Ei-KÖR", value: "2"),
            Entry(name: "Ei-Zaubern", value: "2"),
            Entry(name: "Besonderes", value: "Zauberei-Feuerball"),
            Entry(name: "Item", value: "Feuerstein & Zunder"),
            Entry(name: "Item", value: "0 Dietriche"),
            Entry(name: "Item", value: "0 Tagesrationen"),
            Entry(name: "Zauber", value: ""),
            Entry(name: "Blitz", value: "Zielzauber+3"),
            Entry(name: "Feuerstrahl", value: "1+Zielzauber+Feuermagier"),
            Entry(name: "Feuerball", value: "3+Zielzauber+Feuermagier"),
            Entry(name: "Flammenklinge", value: "Zielzauber+Feuermagier"),
            Entry(name: "Kettenblitz", value: "Zielzauber+3"),
            Entry(name: "Öffnen", value: "Zaubern-SW"),
            Entry(name: "Putzteufel", value: "Zaubern"),
            Entry(name: "Stolpern", value: "Zielzauber-(AGI+AU)/2)"),
            Entry(name: "Verlangsamen", value: "Zaubern-(KÖR+AU)/2"),
            Entry(name: "Wächter", value: "Zaubern"),
            Entry(name: "Magische Rüstung", value: "Zaubern"),
            Entry(name: "Aktiver Kampf", value: ""),
            Entry(name: "Gegnergröße", value: "0"),
            Entry(name: "Bonus", value: "0"),
            Entry(name: "Gegnerabwehr", value: "0"),
            Entry(name: "Slayerpunkte", value: ""),
            Entry(name: "1 SP", value: ""),
            Entry(name: "2 SP", value: "I"),
            Entry(name: "3 SP", value: ""),
            Entry(name: "Zauber", value: "Feuerstrahl")
        ],
        portraitDescription: "Charakterbild von Adalbert",
        portraitTags: ["Character", "CHARAKTER", "DS"],
        expectation: CharacterSummaryExpectation(
            race: ["gnom", "narrländer", "narrlaender"],
            occupation: ["schwarzmagier", "zauberwirker", "magier", "zauberer", "hexer"],
            playerName: "Torben Albrecht",
            traitConcepts: ["arkan", "explosion", "feuer", "flamm", "blitz", "zaubermacht", "dunkel", "schütze", "seefahrt", "alchemie"],
            descriptionConcepts: ["gnom", "magier", "zauber", "feuer", "blitz", "dunkel", "arkan"],
            forbiddenTerms: ["wizard", "black mage", "dark mage", "sorcerer", "player"]
        )
    )

    /// A short stat block (Dungeonslayers) with only numbers and gear, a name that is race plus
    /// class and no portrait description. User's decisions (2026-11-27):
    /// - the class in the name counts as named: occupation Kämpfer;
    /// - nothing on the sheet says sea or water, so no trait from world knowledge ("Meerbewohner");
    /// - traits are the highest value and the special feature, in the sheet's word: Schiessen and
    ///   Schuppen (not "Schuppenhaut"), not the ordinary weapons Speer or Dolch.
    static let aquaterKaempfer = CharacterSummaryFixture(
        name: "Aquater Kämpfer (real, short stat block)",
        outputLanguage: "German",
        label: "Charakter",
        characterName: "Aquater Kämpfer",
        entries: [
            Entry(name: "Ini", value: "12"),
            Entry(name: "Lebenskraft", value: "21"),
            Entry(name: "Abwehr", value: "12"),
            Entry(name: "Schlagen", value: "11"),
            Entry(name: "Schiessen", value: "14"),
            Entry(name: "Andere Werte", value: ""),
            Entry(name: "Laufen", value: "5,5"),
            Entry(name: "Speer (WB+1)", value: ""),
            Entry(name: "(Wurf-) Dolch (WB+1)", value: ""),
            Entry(name: "Schuppen (PA +1)", value: "")
        ],
        portraitTags: ["Character", "SEETEUFEL"],
        expectation: CharacterSummaryExpectation(
            race: ["aquater"],
            occupation: ["kämpfer", "krieger"],
            traitConcepts: ["schiessen", "schießen", "schuppen"],
            descriptionConcepts: ["aquater", "kämpfer", "speer", "schuppen", "schiess", "schieß", "dolch"],
            forbiddenTerms: ["fighter", "warrior", "spear", "scale", "player"],
            forbiddenTraitTerms: ["meer", "ozean", "wasser", "schuppenhaut", "speer", "dolch"]
        )
    )

    /// A mage whose sheet and portrait name no race; the class is only in the portrait tag
    /// "MAGIERIN". The model sometimes made her an Elf, so a common race the text never names is
    /// replaced with Human in code (`verifiedRace`).
    /// User's tags: Mensch, Magierin, Magieresistent, Kettenblitz.
    static let anaja = CharacterSummaryFixture(
        name: "Anaja (real, mage without a race)",
        outputLanguage: "German",
        label: "Charakter",
        characterName: "Anaja",
        entries: [
            Entry(name: "Attribute", value: ""),
            Entry(name: "KÖR", value: "8"),
            Entry(name: "AGI", value: "5"),
            Entry(name: "GEI", value: "7"),
            Entry(name: "ST", value: "0"),
            Entry(name: "HÄ", value: "2"),
            Entry(name: "BE", value: "0"),
            Entry(name: "GE", value: "4"),
            Entry(name: "VE", value: "5"),
            Entry(name: "AU", value: "6"),
            Entry(name: "Kampfwerte", value: ""),
            Entry(name: "Lebenskraft", value: "KÖR+HÄ+10+80"),
            Entry(name: "Abwehr", value: "KÖR+HÄ+Gesamt PA+2"),
            Entry(name: "Ini", value: "AGI+BE"),
            Entry(name: "Laufen", value: "AGI/2+1-0.5"),
            Entry(name: "Schlagen", value: "KÖR+ST+Kämpfer"),
            Entry(name: "Schiessen", value: "AGI+GE+Schütze"),
            Entry(name: "Zauber", value: "GEI+VE+1"),
            Entry(name: "Zielzauber", value: "GEI+GE+Schütze-Gesamt nicht mag. PA+Zielzauber+Vertrauter+2"),
            Entry(name: "Rüstung", value: ""),
            Entry(name: "Gesamt PA", value: "Gesamt nicht mag. PA+Gesamt mag. PA"),
            Entry(name: "Gesamt nicht mag. PA", value: "Robe, runenbestickt"),
            Entry(name: "Gesamt mag. PA", value: "R Mag. PA+Schutzring"),
            Entry(name: "Magische Rüstung", value: ""),
            Entry(name: "Robe, runenbestickt", value: "0"),
            Entry(name: "R Mag. PA", value: "1"),
            Entry(name: "R Ini Malus", value: "0+R Mag. PA"),
            Entry(name: "R Laufen Malus", value: "0+R Mag. PA/2"),
            Entry(name: "Schutzring", value: "2"),
            Entry(name: "Waffen", value: ""),
            Entry(name: "Waffenlos", value: "Schlagen"),
            Entry(name: "Kampfstab", value: ""),
            Entry(name: "Kampfstab", value: "Schlagen+N WB+N mag WB"),
            Entry(name: "N WB", value: "1"),
            Entry(name: "N mag WB", value: "3"),
            Entry(name: "W Ini Bonus", value: "0+N mag WB"),
            Entry(name: "W GA Bonus", value: "0-N mag WB"),
            Entry(name: "Zielzauber", value: "4"),
            Entry(name: "Talente", value: ""),
            Entry(name: "Alchemie", value: "1"),
            Entry(name: "Bildung", value: "2"),
            Entry(name: "Heldenglück", value: "1"),
            Entry(name: "Instrument", value: "2"),
            Entry(name: "Kämpfer", value: "0"),
            Entry(name: "Magieresistent", value: "3"),
            Entry(name: "Schütze", value: "3"),
            Entry(name: "Verheerer", value: "2"),
            Entry(name: "Vertrauter", value: "1"),
            Entry(name: "Wechsler", value: "2"),
            Entry(name: "Zaubermacht", value: "2"),
            Entry(name: "Zauber", value: ""),
            Entry(name: "Duftnote", value: "Zauber"),
            Entry(name: "Frostwaffe", value: "Zielzauber"),
            Entry(name: "Giftschutz", value: "Zauber"),
            Entry(name: "Kettenblitz", value: "Zielzauber+3"),
            Entry(name: "Lichtpfeil", value: "Zielzauber+2"),
            Entry(name: "Netz", value: "Zielzauber"),
            Entry(name: "Rost", value: "Zielzauber"),
            Entry(name: "Schattenpfeil", value: "Zielzauber+2"),
            Entry(name: "Verborgenes sehen", value: "Zauber"),
            Entry(name: "Kampf", value: ""),
            Entry(name: "Allgemeiner Bonus", value: "0"),
            Entry(name: "Aktuelle LK", value: "Lebenskraft"),
            Entry(name: "Aktuelle Abwehr", value: "Abwehr+Allgemeiner Bonus"),
            Entry(name: "Anzahl Brutaler Hieb", value: "0"),
            Entry(name: "Kampfstab", value: "KÖR*Anzahl Brutaler Hieb+Allgemeiner BonusKampfstab"),
            Entry(name: "Anzahl Zaubermacht", value: "0"),
            Entry(name: "Giftschutz", value: "Giftschutz+GEI*Anzahl Zaubermacht+Allgemeiner Bonus"),
            Entry(name: "Kettenblitz", value: "GEI*Anzahl Zaubermacht+Allgemeiner BonusKettenblitz"),
            Entry(name: "Standard Abwehr", value: "Aktuelle Abwehr")
        ],
        portraitDescription: "Kampagne Die Hallen von Barcamar",
        portraitTags: ["BARCAMAR", "Character", "MAGIERIN"],
        expectation: CharacterSummaryExpectation(
            race: ["mensch"],
            occupation: ["magier"],
            traitConcepts: ["magieresist", "kettenblitz"],
            descriptionConcepts: ["magier", "zauber", "barcamar"],
            forbiddenTerms: ["wizard", "mage", "player"]
        )
    )
}

#endif
