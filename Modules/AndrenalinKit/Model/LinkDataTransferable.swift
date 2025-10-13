//
//  LinkDataTransferable.swift
//  MasterRPG
//
//  Created by Andre Trettin on 13.10.25.
//


// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public protocol LinkDataTransferable: Sendable, Codable, Transferable {
    var module: NetworkModules { get }
    var itemId: UUID { get }
    var entryId: UUID? { get }
    var name: String { get }
}

extension LinkDataTransferable {
    var linkRepresentation: String {
        if let entryId {
            return "[\(name)](\(URL.appScheme)://\(module.token)/0/\(itemId)/\(entryId))"
        } else {
            return "[\(name)](\(URL.appScheme)://\(module.token)/0/\(itemId))"
        }
    }
    
    static func linkDataType(module: NetworkModules) -> any LinkDataTransferable {
        switch module {
        case .adventure: LinkAdventureData(itemId: UUID(), name: "")
        case .audio: LinkAudioData(itemId: UUID(), name: "")
        case .value: LinkCharacterData(itemId: UUID(), name: "")
        case .dice: LinkDiceData(itemId: UUID(), name: "")
        case .map: LinkMapData(itemId: UUID(), name: "")
        case .pdf: LinkPdfData(itemId: UUID(), name: "")
        case .photo: LinkPhotoData(itemId: UUID(), name: "")
        case .space: LinkSpaceData(itemId: UUID(), name: "")
        case .table: LinkTableData(itemId: UUID(), name: "")
        case .weather: LinkWeatherData(itemId: UUID(), name: "")
        default: LinkAdventureData(itemId: UUID(), name: "")
        }
    }
}

public struct LinkAdventureData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .adventure }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkAudioData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .audio }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkCharacterData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .value }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkDiceData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .dice }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkMapData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .map }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkPdfData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .pdf }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkPhotoData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .photo }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkSpaceData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .space }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkTableData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .table }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkWeatherData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .weather }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}
