// @copyright André Trettin

import Foundation

/// Which array of a Foundry document holds which kind of embedded document. Read by the import
/// reader to extract the embedded documents and by the archive sanitizer to drop the arrays that
/// are already stored as documents, so the two always agree. See CODE_AUDIT_26 §9.13.
enum FoundryEmbeddedMappings {
    /// The arrays of one parent type. An adventure holds the world collections by name.
    static func mappings(for parentType: FoundryDocumentType) -> [String: FoundryDocumentType] {
        var mappings = standard[parentType] ?? [:]
        if parentType == .adventure {
            mappings.merge(adventure, uniquingKeysWith: { current, _ in current })
        }
        return mappings
    }

    static let standard: [FoundryDocumentType: [String: FoundryDocumentType]] = [
        .actor: ["items": .item, "effects": .activeEffect],
        .item: ["effects": .activeEffect],
        .scene: [
            "levels": .level, "tokens": .token, "walls": .wall, "lights": .ambientLight,
            "sounds": .ambientSound, "tiles": .tile, "drawings": .drawing,
            "notes": .note, "regions": .region,
        ],
        .level: [
            "tokens": .token, "walls": .wall, "lights": .ambientLight,
            "sounds": .ambientSound, "tiles": .tile, "drawings": .drawing,
            "notes": .note, "regions": .region,
        ],
        .journalEntry: ["pages": .journalEntryPage],
        .rollTable: ["results": .tableResult],
        .playlist: ["sounds": .playlistSound],
        .cards: ["cards": .card],
        .combat: ["combatants": .combatant],
    ]

    static let adventure: [String: FoundryDocumentType] = [
        "actors": .actor, "items": .item, "scenes": .scene,
        "journal": .journalEntry, "journals": .journalEntry,
        "journalEntries": .journalEntry, "tables": .rollTable,
        "rollTables": .rollTable, "playlists": .playlist, "cards": .cards,
        "combats": .combat, "macros": .macro, "folders": .folder,
    ]
}
