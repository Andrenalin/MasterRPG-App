// @copyright André Trettin

import Foundation
import FoundationModels

/// Summary analysis of PDF documents
///
/// **Property Order Optimized for Streaming UX:**
/// Properties are generated in declaration order. Most important properties come first
/// so users see title in ~0.2s instead of waiting for full generation (~2-3s).
/// This follows Foundation Models best practice for progressive UI updates.
@Generable(description: "Summary analysis with structured metadata from RPG rulebooks or adventure PDFs")
public struct PdfSummaryAnalysis: Equatable, Sendable, Identifiable {

    public var id: String { title + summary }

    @Guide(description: "The main title or name of the document")
    public var title: String

    @Guide(description: "A concise summary of the PDF content (2-3 sentences)")
    public var summary: String

    /// Decided before `documentKind`, so the model picks a kind from a fixed set instead of
    /// answering "what kind" with a genre or a vague word ("Fantasy", "Erlebnis", "Game"). It is
    /// also the fallback for the kind tag, see `kindTag(documentKind:category:genre:title:outputLanguage:)`.
    /// After `title` and `summary`: streaming other fields first trips the output guardrail.
    public var category: PdfDocumentCategory

    @Guide(
        description: """
        The kind of document in 1 or 2 words, written in the output language: the category made \
        exact, preferably with the word the document uses for itself on its first page. A noun for \
        the kind of document, never its genre, never its title or a name from it, never a generic \
        word such as "Game" or "Role-playing game" (or their translations).
        """
    )
    public var documentKind: String

    @Guide(
        description: """
        The genre of the game world in 1 or 2 words, written in the output language, for example \
        fantasy, science fiction, horror or post-apocalypse. Never the kind of document, never a \
        name, never the word "Genre".
        """
    )
    public var genre: String

    /// The free tags. Kind and genre come first in the stored tags, see `tags(category:documentKind:genre:tags:title:outputLanguage:)`.
    @Guide(
        description: """
        Short tags in the output language: first the main subject of the document as a concrete \
        noun, then specific places, peoples, creatures, factions or themes of this document. Not \
        the kind of document and not the genre again. \
        \(GeneratedTagRules.rules(extraGenericTags: ["Role-playing game"]))
        """,
        .count(PdfSummaryAnalysis.freeTagCountRange)
    )
    public var tags: [String]

    @Guide(description: "Important sections, chapters, or major divisions found in the document")
    public var sections: [PdfSection]

    public init(
        title: String,
        summary: String,
        category: PdfDocumentCategory = .otherSupplement,
        documentKind: String = "",
        genre: String = "",
        tags: [String],
        sections: [PdfSection]
    ) {
        self.title = title
        self.summary = summary
        self.category = category
        self.documentKind = documentKind
        self.genre = genre
        self.tags = tags
        self.sections = sections
    }
}

// MARK: - Tags

extension PdfSummaryAnalysis {
    /// Kind and genre take two of the five tag slots. One spare free tag fills a slot that
    /// `GeneratedTagRules.cleaned(_:title:)` drops; more spares pushed long PDFs over the context size.
    static let freeTagCountRange = (GeneratedTagRules.countRange.upperBound - 2)...(GeneratedTagRules.countRange.upperBound - 1)

    /// The stored tags: the kind, the genre, then the free tags, without title repeats, generic
    /// tags and duplicates, at most `GeneratedTagRules.countRange.upperBound`.
    /// - Parameter outputLanguage: the English name of the output language; `nil` while streaming,
    ///   then a missing or invalid kind is left out instead of replaced by the category's name.
    static func tags(
        category: PdfDocumentCategory?,
        documentKind: String?,
        genre: String?,
        tags: [String]?,
        title: String,
        outputLanguage: String?
    ) -> [String] {
        let kind = kindTag(
            documentKind: documentKind,
            category: category,
            genre: genre,
            title: title,
            outputLanguage: outputLanguage
        )
        return GeneratedTagRules.cleaned([kind, genre].compactMap { $0 } + (tags ?? []), title: title)
    }

    /// The model's own kind word ("Stadtbeschreibung", "Gasthaus" are more exact than a category),
    /// unless it is unusable: empty, a copied category value ("characterSheet", "adventure" in
    /// German output), camel case, generic, too long, or the title or genre again. Then the
    /// category's name in the output language.
    static func kindTag(
        documentKind: String?,
        category: PdfDocumentCategory?,
        genre: String?,
        title: String,
        outputLanguage: String?
    ) -> String? {
        let fallback = outputLanguage.flatMap { language in category.map { $0.name(in: language) } }
        guard let documentKind else { return fallback }
        let kind = GeneratedTagRules.withoutLabel(documentKind)
        let key = GeneratedTagRules.comparisonKey(kind)
        let categoryKeys = Set(PdfDocumentCategory.allCases.map { GeneratedTagRules.comparisonKey($0.rawValue) })
        let genericKeys = Set(GeneratedTagRules.everyDocumentTags.map(GeneratedTagRules.comparisonKey))
        let isUnusable = key.isEmpty
            || isCamelCase(kind)
            || categoryKeys.contains(key)
            || genericKeys.contains(key)
            || key.split(separator: " ").count > GeneratedTagRules.maximumWordsPerTag
            || key == GeneratedTagRules.comparisonKey(title)
            || key == GeneratedTagRules.comparisonKey(genre ?? "")
        return isUnusable ? fallback : kind
    }

    /// "characterSheet": a lowercase letter directly followed by an uppercase one inside a word.
    private static func isCamelCase(_ text: String) -> Bool {
        zip(text, text.dropFirst()).contains { $0.isLowercase && $1.isUppercase }
    }
}

/// What kind of RPG document a PDF is. Steers `PdfSummaryAnalysis.documentKind` and is its
/// fallback, written in the output language by `name(in:)`.
@Generable(
    description: """
    The kind of RPG document: adventure (a scenario or dungeon to play through), rulebook (game \
    rules), characterSheet (the sheet of one character with name, attributes and skills), \
    placeDescription (a city, region, island, building, shop or temple), inn (one inn, tavern or \
    restaurant), peopleOrCulture (a people, culture or faction), creatureCollection (monsters or \
    beasts), itemCollection (equipment, herbs, potions, spells or treasure), map, or otherSupplement
    """
)
public enum PdfDocumentCategory: String, CaseIterable, Equatable, Sendable {
    case adventure
    case rulebook
    case characterSheet
    case placeDescription
    case inn
    case peopleOrCulture
    case creatureCollection
    case itemCollection
    case map
    case otherSupplement

    /// The tag of the category in `outputLanguage` (the English name of an `OutputLanguage`),
    /// English for a language without its own names.
    func name(in outputLanguage: String) -> String {
        let names = Self.names[self] ?? []
        let index = MapPlaceKind.languages.firstIndex(of: outputLanguage) ?? 0
        return names.indices.contains(index) ? names[index] : rawValue
    }

    /// In the order of `MapPlaceKind.languages`.
    private static let names: [PdfDocumentCategory: [String]] = [
        .adventure: ["Adventure", "Abenteuer", "Aventure", "Aventura", "Avventura", "Aventura", "Avontuur", "Przygoda", "冒険"],
        .rulebook: ["Rulebook", "Regelwerk", "Livre de règles", "Libro de reglas", "Regolamento", "Livro de regras", "Regelboek", "Podręcznik zasad", "ルールブック"],
        .characterSheet: ["Character sheet", "Charakterbogen", "Fiche de personnage", "Hoja de personaje", "Scheda del personaggio", "Ficha de personagem", "Karakterblad", "Karta postaci", "キャラクターシート"],
        .placeDescription: ["Location", "Schauplatz", "Lieu", "Lugar", "Luogo", "Local", "Locatie", "Lokacja", "舞台"],
        .inn: ["Inn", "Gasthaus", "Auberge", "Posada", "Locanda", "Estalagem", "Herberg", "Karczma", "宿屋"],
        .peopleOrCulture: ["People", "Volk", "Peuple", "Pueblo", "Popolo", "Povo", "Volk", "Lud", "種族"],
        .creatureCollection: ["Bestiary", "Bestiarium", "Bestiaire", "Bestiario", "Bestiario", "Bestiário", "Bestiarium", "Bestiariusz", "モンスター図鑑"],
        .itemCollection: ["Equipment", "Ausrüstung", "Équipement", "Equipo", "Equipaggiamento", "Equipamento", "Uitrusting", "Ekwipunek", "装備"],
        .map: ["Map", "Karte", "Carte", "Mapa", "Mappa", "Mapa", "Kaart", "Mapa", "地図"],
        .otherSupplement: ["Supplement", "Ergänzung", "Supplément", "Suplemento", "Supplemento", "Suplemento", "Supplement", "Dodatek", "サプリメント"]
    ]
}

/// A section or chapter within the PDF
@Generable(description: "A major section or chapter in the PDF document")
public struct PdfSection: Equatable, Sendable, Identifiable {

    public var id: String { heading + (pageNumber.map { "\($0)" } ?? "") }

    @Guide(description: "The section heading or chapter title")
    public var heading: String

    @Guide(description: "A brief summary of what this section covers")
    public var summary: String

    @Guide(description: "The approximate page number where this section starts, if identifiable")
    public var pageNumber: Int?

    public init(heading: String, summary: String, pageNumber: Int? = nil) {
        self.heading = heading
        self.summary = summary
        self.pageNumber = pageNumber
    }
}

/// Progress information for page-by-page analysis
public struct PdfAnalysisProgress: Equatable, Sendable {
    public let currentPage: Int
    public let totalPages: Int

    public init(currentPage: Int, totalPages: Int) {
        self.currentPage = currentPage
        self.totalPages = totalPages
    }
}
