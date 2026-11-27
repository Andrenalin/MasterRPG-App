// @copyright André Trettin

import Foundation
import FoundationModels

/// The kind of place a map shows. It is always the first tag of a map, written in the output
/// language by `name(in:)`, so maps can be sorted by their kind (all caves, all cities) in any
/// language. A fixed list: as free text the model wrote "Dungeon Map", "Cave Layout" or nothing.
@Generable(description: "The kind of place the map shows")
enum MapPlaceKind: String, CaseIterable, Sendable, Equatable {
    case world
    case country
    case city
    case village
    case building
    case fortress
    case temple
    case dungeon
    case cave
    case crypt
    case sewer
    case mine
    case ruins
    case forest
    case jungle
    case swamp
    case desert
    case plains
    case mountains
    case tundra
    case coast
    case island
    case sea
    case ship
    case spaceship
    case spaceStation

    /// What each kind covers, for the model's instructions: one line per kind, so the model can
    /// match the photo's words ("castle", "inn", "grove") to a kind.
    static var instructionList: String {
        allCases.map { "- \($0.rawValue): \($0.covers)" }.joined(separator: "\n")
    }

    private var covers: String {
        switch self {
        case .world: "a whole world, planet or continent"
        case .country: "a kingdom, country, land, province or region with several places"
        case .city: "a city or town, its streets, districts or harbor"
        case .village: "a village, hamlet or farmstead"
        case .building: "a single house, inn, tavern, shop, manor, palace, tower, academy or other building"
        case .fortress: "a castle, keep, fort, citadel, stronghold or walled camp"
        case .temple: "a temple, church, chapel, shrine, monastery or abbey above ground"
        case .dungeon: "an underground complex built by people: halls, cells, vaults, traps"
        case .cave: "natural caves, caverns, grottos or an underdark"
        case .crypt: "a crypt, tomb, catacomb, mausoleum or graveyard"
        case .sewer: "sewers, drains, cisterns or tunnels below a city"
        case .mine: "a mine, quarry or dig site"
        case .ruins: "ruins of a fallen building or city"
        case .forest: "a forest, wood, grove or glade"
        case .jungle: "a jungle or rainforest"
        case .swamp: "a swamp, marsh, bog or fen"
        case .desert: "a desert, dunes, oasis or wasteland"
        case .plains: "plains, grassland, steppe, fields, hills or a battlefield in the open"
        case .mountains: "mountains, a pass, cliffs, a volcano or a high valley"
        case .tundra: "snow, ice, a glacier or tundra"
        case .coast: "a coast, beach, bay or river bank"
        case .island: "an island or archipelago"
        case .sea: "the open sea, a lake or an underwater place"
        case .ship: "a ship or boat on water (sailing ship, galley, riverboat) or an airship, its decks"
        case .spaceship: "a spaceship, starship, space freighter or shuttle of science fiction, its decks"
        case .spaceStation: "a space station, orbital base or moon base"
        }
    }

    /// The tag of the kind in `outputLanguage` (the English name of an `OutputLanguage`), English
    /// for a language without its own names.
    func name(in outputLanguage: String) -> String {
        let names = Self.names[self] ?? []
        let index = Self.languages.firstIndex(of: outputLanguage) ?? 0
        return names.indices.contains(index) ? names[index] : rawValue.capitalized
    }

    /// The order of the names in `names`: the English names of `OutputLanguage.supported`.
    static let languages = ["English", "German", "French", "Spanish", "Italian", "Portuguese", "Dutch", "Polish", "Japanese"]

    private static let names: [MapPlaceKind: [String]] = [
        .world: ["World", "Welt", "Monde", "Mundo", "Mondo", "Mundo", "Wereld", "Świat", "世界"],
        .country: ["Country", "Land", "Pays", "País", "Paese", "País", "Land", "Kraj", "国"],
        .city: ["City", "Stadt", "Ville", "Ciudad", "Città", "Cidade", "Stad", "Miasto", "都市"],
        .village: ["Village", "Dorf", "Village", "Aldea", "Villaggio", "Aldeia", "Dorp", "Wieś", "村"],
        .building: ["Building", "Gebäude", "Bâtiment", "Edificio", "Edificio", "Edifício", "Gebouw", "Budynek", "建物"],
        .fortress: ["Fortress", "Festung", "Forteresse", "Fortaleza", "Fortezza", "Fortaleza", "Vesting", "Twierdza", "要塞"],
        .temple: ["Temple", "Tempel", "Temple", "Templo", "Tempio", "Templo", "Tempel", "Świątynia", "神殿"],
        .dungeon: ["Dungeon", "Dungeon", "Donjon", "Mazmorra", "Sotterraneo", "Masmorra", "Kerker", "Loch", "ダンジョン"],
        .cave: ["Cave", "Höhle", "Grotte", "Cueva", "Grotta", "Caverna", "Grot", "Jaskinia", "洞窟"],
        .crypt: ["Crypt", "Gruft", "Crypte", "Cripta", "Cripta", "Cripta", "Crypte", "Krypta", "地下墓所"],
        .sewer: ["Sewer", "Kanalisation", "Égouts", "Alcantarillado", "Fogne", "Esgoto", "Riool", "Kanały", "下水道"],
        .mine: ["Mine", "Bergwerk", "Mine", "Mina", "Miniera", "Mina", "Mijn", "Kopalnia", "鉱山"],
        .ruins: ["Ruins", "Ruinen", "Ruines", "Ruinas", "Rovine", "Ruínas", "Ruïnes", "Ruiny", "遺跡"],
        .forest: ["Forest", "Wald", "Forêt", "Bosque", "Foresta", "Floresta", "Bos", "Las", "森"],
        .jungle: ["Jungle", "Dschungel", "Jungle", "Selva", "Giungla", "Selva", "Jungle", "Dżungla", "ジャングル"],
        .swamp: ["Swamp", "Sumpf", "Marais", "Pantano", "Palude", "Pântano", "Moeras", "Bagno", "沼地"],
        .desert: ["Desert", "Wüste", "Désert", "Desierto", "Deserto", "Deserto", "Woestijn", "Pustynia", "砂漠"],
        .plains: ["Plains", "Ebene", "Plaine", "Llanura", "Pianura", "Planície", "Vlakte", "Równina", "平原"],
        .mountains: ["Mountains", "Gebirge", "Montagnes", "Montañas", "Montagne", "Montanhas", "Gebergte", "Góry", "山岳"],
        .tundra: ["Tundra", "Eiswüste", "Toundra", "Tundra", "Tundra", "Tundra", "Toendra", "Tundra", "ツンドラ"],
        .coast: ["Coast", "Küste", "Côte", "Costa", "Costa", "Costa", "Kust", "Wybrzeże", "海岸"],
        .island: ["Island", "Insel", "Île", "Isla", "Isola", "Ilha", "Eiland", "Wyspa", "島"],
        .sea: ["Sea", "Meer", "Mer", "Mar", "Mare", "Mar", "Zee", "Morze", "海"],
        .ship: ["Ship", "Schiff", "Navire", "Barco", "Nave", "Navio", "Schip", "Statek", "船"],
        .spaceship: ["Spaceship", "Raumschiff", "Vaisseau spatial", "Nave espacial", "Astronave", "Nave espacial", "Ruimteschip", "Statek kosmiczny", "宇宙船"],
        .spaceStation: ["Space Station", "Raumstation", "Station spatiale", "Estación espacial", "Stazione spaziale", "Estação espacial", "Ruimtestation", "Stacja kosmiczna", "宇宙ステーション"]
    ]
}

/// What the model writes for a map: its rooms plus the description and tags of the map's photo.
/// The kind is generated before the tags, so the content tags do not spend a slot on it, and after
/// the title and description, so they are streamed first.
@Generable(description: "Extracted title, description, kind of place and tags of a role-playing game map")
struct MapSummaryGeneration: Equatable, Sendable {

    @Guide(
        description: """
        A title of 2 to 6 words in the output language that names the place: its own name when \
        the map has one, otherwise what the place is, for example "Crypt beneath the Chapel" or \
        "Blackwater Keep". No sentence, no period, no label before it. Never the words map, plan, \
        layout or rooms.
        """
    )
    var title: String

    @Guide(
        description: """
        One or two sentences in the output language about the place itself: what kind of place it \
        is and what is special about it. Never call it a map, a table, entries or a list. Do not \
        use the words \(GeneratedTagRules.bannedWordsText).
        """
    )
    var description: String

    @Guide(description: "The kind of place that fits best, decided by the map photo's description and tags first, then by the rooms")
    var kind: MapPlaceKind

    @Guide(
        description: GeneratedTagRules.guideDescription(
            contents: """
            Not the kind of place. They name what is special in this place: its specific places, \
            creatures, people, factions, items or themes, and the genre when the photo names one. \
            Never the words map, plan, layout or rooms.
            """,
            extraGenericTags: MapSummaryGeneration.genericTags
        ),
        .count(MapSummaryGeneration.contentTagRange)
    )
    var tags: [String]

    /// The content tags; the kind tag makes the total `GeneratedTagRules.countRange`.
    static let contentTagRange = (GeneratedTagRules.countRange.lowerBound - 1)...(GeneratedTagRules.countRange.upperBound - 1)

    /// Words that name the form of a map, not its content.
    static let genericTags = ["Map", "Rooms", "Layout", "Floor Plan"]

    /// Whole words that name a map, a plan or its rooms in the output languages. A title or tag
    /// loses them ("Dungeon Map" becomes "Dungeon"); a tag that keeps one inside is dropped.
    static let formWords: Set<String> = [
        "map", "maps", "layout", "floorplan", "rooms",
        "karte", "karten", "landkarte", "grundriss", "raume",
        "carte", "cartes", "plan", "plans",
        "mapa", "mapas", "plano", "planta",
        "mappa", "mappe", "pianta",
        "kaart", "kaarten", "plattegrond",
        "mapy"
    ]

    /// Form words without spaces before them (Japanese).
    static let formSuffixes = ["マップ", "地図", "の地図"]

    /// Words that join a leading form word to the place: "Map of …", "Carte du …", "Karte der …".
    private static let connectors: Set<String> = [
        "of", "the", "der", "des", "die", "von", "du", "de", "la", "le", "les", "del", "della", "dello",
        "di", "do", "da", "dos", "das", "van", "het", "z", "ze"
    ]

    /// `text` without the form words at its start or end, and with "of"/"du"/... after a leading
    /// one. `keepInnerFormWords == false` returns `""` when one is still inside (a tag is dropped).
    static func withoutFormWords(_ text: String, keepInnerFormWords: Bool) -> String {
        // "Floor Plan" and "Deck Plan" are one form word: neither "Floor" nor "Deck" may stay.
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing(/(?i)\b(floor|deck|site) ?plans?\b/, with: "map")
        for suffix in formSuffixes.sorted(by: { $0.count > $1.count }) where trimmed.hasSuffix(suffix) {
            trimmed = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        var words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        while let last = words.last, isFormWord(last) {
            words.removeLast()
        }
        if let first = words.first, isFormWord(first) {
            words.removeFirst()
            while let next = words.first, connectors.contains(normalized(next)) {
                words.removeFirst()
            }
        }
        if words.contains(where: isFormWord) {
            guard keepInnerFormWords else { return "" }
            words.removeAll(where: isFormWord)
        }
        return words.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ":-–—,;").union(.whitespaces))
    }

    /// The title as it is stored: without form words; the kind's name when nothing else is left.
    static func cleanedTitle(_ title: String, kind: MapPlaceKind?, outputLanguage: String) -> String {
        let cleaned = withoutFormWords(title, keepInnerFormWords: true)
        guard cleaned.isEmpty, let kind else { return cleaned }
        return kind.name(in: outputLanguage)
    }

    /// The kind's tag first, then the content tags without form words, the title and the kind in
    /// another language, cleaned like every generated tag list.
    static func tags(kind: MapPlaceKind?, contentTags: [String]?, title: String, outputLanguage: String) -> [String] {
        let titleKey = normalized(title)
        // The kind in any language: a photo tag "Wald" copied next to the kind "Forest".
        let kindKeys = Set((kind.map { kind in MapPlaceKind.languages.map { kind.name(in: $0) } } ?? []).map(normalized))
        let content = (contentTags ?? [])
            .map { withoutFormWords(GeneratedTagRules.withoutLabel($0), keepInnerFormWords: false) }
            .filter { !$0.isEmpty && normalized($0) != titleKey && !kindKeys.contains(normalized($0)) }
        return GeneratedTagRules.cleaned((kind.map { [$0.name(in: outputLanguage)] } ?? []) + content)
    }

    private static func isFormWord(_ word: String) -> Bool {
        formWords.contains(normalized(word))
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber || $0 == " " }
            .trimmingCharacters(in: .whitespaces)
    }
}

extension TableSummaryAnalysisProgress {
    /// A map's progress: the cleaned title, and the tags once the kind is known.
    init(_ partial: MapSummaryGeneration.PartiallyGenerated, outputLanguage: String) {
        let title = partial.title.map { MapSummaryGeneration.cleanedTitle($0, kind: nil, outputLanguage: outputLanguage) }
        let tags = MapSummaryGeneration.tags(kind: partial.kind, contentTags: partial.tags, title: title ?? "", outputLanguage: outputLanguage)
        self.title = title
        self.description = partial.description
        self.tags = tags.isEmpty ? nil : tags
    }
}
