// @copyright André Trettin

import CryptoKit
import Foundation

// The document type inference tables, split out of FoundryVTTImportReader.swift. See CODE_AUDIT_29 §9.9.

extension FoundryDocumentType {
    static func inferred(from value: String?) -> Self {
        guard let value else { return .unknown }
        let key = value.lowercased().filter { $0.isLetter || $0.isNumber }
        return canonicalTypes[key] ?? .unknown
    }

    static func inferred(fromCollectionName value: String) -> Self {
        let key = value.lowercased().filter { $0.isLetter || $0.isNumber }
        if let exact = collectionTypes[key] { return exact }
        let tokens = value.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if tokens.first == "fvtt", tokens.count > 1 {
            let exportedType = inferred(from: tokens[1])
            if exportedType != .unknown { return exportedType }
        }
        return inferred(from: value)
    }

    static func inferred(fromCollectionName value: String, embeddedIn parent: Self?) -> Self {
        let key = value.lowercased().filter { $0.isLetter || $0.isNumber }
        if parent == .cards, key == "cards" { return .card }
        if parent == .playlist, key == "sounds" { return .playlistSound }
        if (parent == .scene || parent == .level), key == "sounds" { return .ambientSound }
        if parent == .scene, key == "levels" { return .level }
        return inferred(fromCollectionName: value)
    }

    static func inferred(from raw: FoundryJSONValue, fallback: Self) -> Self {
        let candidates = [
            raw["documentName"]?.stringValue,
            raw["documentType"]?.stringValue,
            raw.value(at: "_stats.documentName")?.stringValue,
        ]
        for candidate in candidates {
            let type = inferred(from: candidate)
            if type != .unknown { return type }
        }
        let explicitType = inferred(from: raw["type"]?.stringValue)
        if explicitType != .unknown { return explicitType }
        if fallback != .unknown { return fallback }
        guard let object = raw.objectValue else { return .unknown }
        if object["tokens"] != nil || object["walls"] != nil || object["background"] != nil { return .scene }
        if object["pages"] != nil { return .journalEntry }
        if object["results"] != nil && (object["formula"] != nil || object["replacement"] != nil) { return .rollTable }
        if object["sounds"] != nil && object["mode"] != nil { return .playlist }
        if object["cards"] != nil && (object["drawn"] != nil || object["pile"] != nil) { return .cards }
        if object["combatants"] != nil && object["round"] != nil { return .combat }
        if object["items"] != nil && object["system"] != nil { return .actor }
        return .unknown
    }

    static let canonicalTypes: [String: Self] = [
        "actor": .actor, "item": .item, "scene": .scene, "level": .level,
        "journalentry": .journalEntry, "journalentrypage": .journalEntryPage,
        "rolltable": .rollTable, "tableresult": .tableResult,
        "playlist": .playlist, "playlistsound": .playlistSound,
        "cards": .cards, "card": .card, "adventure": .adventure,
        "folder": .folder, "activeeffect": .activeEffect,
        "token": .token, "tokendocument": .token,
        "wall": .wall, "walldocument": .wall,
        "ambientlight": .ambientLight, "ambientlightdocument": .ambientLight,
        "ambientsound": .ambientSound, "ambientsounddocument": .ambientSound,
        "tile": .tile, "tiledocument": .tile,
        "drawing": .drawing, "drawingdocument": .drawing,
        "note": .note, "notedocument": .note,
        "region": .region, "regiondocument": .region,
        "combat": .combat, "combatant": .combatant,
        "macro": .macro, "chatmessage": .chatMessage, "message": .chatMessage,
        "user": .user,
    ]

    static let collectionTypes: [String: Self] = canonicalTypes.merging([
        "actors": .actor, "items": .item, "scenes": .scene, "levels": .level,
        "journal": .journalEntry, "journals": .journalEntry,
        "journalentries": .journalEntry, "pages": .journalEntryPage,
        "tables": .rollTable, "rolltables": .rollTable, "results": .tableResult,
        "playlists": .playlist, "sounds": .playlistSound,
        "cards": .cards, "carddocuments": .card,
        "adventures": .adventure, "folders": .folder,
        "effects": .activeEffect,
        "tokens": .token, "walls": .wall, "lights": .ambientLight,
        "ambientsounds": .ambientSound, "soundsdocuments": .ambientSound,
        "tiles": .tile, "drawings": .drawing, "notes": .note, "regions": .region,
        "combats": .combat, "combatants": .combatant,
        "macros": .macro, "messages": .chatMessage, "chatmessages": .chatMessage,
        "users": .user,
    ], uniquingKeysWith: { _, new in new })
}
