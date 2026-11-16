// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public protocol LinkDataTransferable: Sendable, Codable, Transferable {
    var module: NetworkModules { get }
    var itemId: UUID { get }
    var entryId: UUID? { get }
    var name: String { get }
    var isMove: Bool { get }
}

extension LinkDataTransferable {
    public var linkRepresentation: String {
        LinkBuilder.markdown(name: name, module: module, itemId: itemId, entryId: entryId)
    }
    
}

extension UTType {
    public static var adventureLink: UTType { UTType(exportedAs: BundleIds.app("Link.Adventure")) }
    public static var audioLink: UTType { UTType(exportedAs: BundleIds.app("Link.Audio")) }
    public static var characterLink: UTType { UTType(exportedAs: BundleIds.app("Link.Character")) }
    public static var diceLink: UTType { UTType(exportedAs: BundleIds.app("Link.Dice")) }
    public static var mapLink: UTType { UTType(exportedAs: BundleIds.app("Link.Map")) }
    public static var pdfLink: UTType { UTType(exportedAs: BundleIds.app("Link.Pdf")) }
    public static var photoLink: UTType { UTType(exportedAs: BundleIds.app("Link.Photo")) }
    public static var ruleLink: UTType { UTType(exportedAs: BundleIds.app("Link.Rule")) }
    public static var spaceLink: UTType { UTType(exportedAs: BundleIds.app("Link.Space")) }
    public static var tableLink: UTType { UTType(exportedAs: BundleIds.app("Link.Table")) }
    public static var weatherLink: UTType { UTType(exportedAs: BundleIds.app("Link.Weather")) }
    
    public static var entryLink: UTType { UTType(exportedAs: BundleIds.app("Link.Entry")) }
}

/// Empty link transferable for modules that don't support entry editor
public struct EmptyLinkTransferable: LinkDataTransferable {
    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool
    
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

public struct LinkEntryData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String, module: NetworkModules, isMove: Bool = false) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
        self.module = module
        self.isMove = isMove
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .entryLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool
}

/// The module and the exported `UTType` of one kind of module link. See `ModuleLinkData`.
public protocol LinkModuleTag: Sendable {
    static var module: NetworkModules { get }
    static var contentType: UTType { get }
}

/// A dragged link to an item or entry of one module. The module is fixed by `Tag`, and each
/// module has its own `UTType`, so a drop target accepts only the links it can follow.
/// The per-module `Link…Data` names below are typealiases of this one type. The encoded form
/// (`module`, `itemId`, `entryId`, `name`, `isMove`) and the `UTType` identifiers are unchanged.
/// See CODE_AUDIT_26 §9.11.
public struct ModuleLinkData<Tag: LinkModuleTag>: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String, isMove: Bool = false) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
        self.module = Tag.module
        self.isMove = isMove
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: Tag.contentType)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool
}

public enum AdventureLinkTag: LinkModuleTag {
    public static var module: NetworkModules { .adventure }
    public static var contentType: UTType { .adventureLink }
}
public typealias LinkAdventureData = ModuleLinkData<AdventureLinkTag>

public enum AudioLinkTag: LinkModuleTag {
    public static var module: NetworkModules { .audio }
    public static var contentType: UTType { .audioLink }
}
public typealias LinkAudioData = ModuleLinkData<AudioLinkTag>

public enum CharacterLinkTag: LinkModuleTag {
    public static var module: NetworkModules { .value }
    public static var contentType: UTType { .characterLink }
}
public typealias LinkCharacterData = ModuleLinkData<CharacterLinkTag>

public enum DiceLinkTag: LinkModuleTag {
    public static var module: NetworkModules { .dice }
    public static var contentType: UTType { .diceLink }
}
public typealias LinkDiceData = ModuleLinkData<DiceLinkTag>

public enum MapLinkTag: LinkModuleTag {
    public static var module: NetworkModules { .map }
    public static var contentType: UTType { .mapLink }
}
public typealias LinkMapData = ModuleLinkData<MapLinkTag>

public enum PdfLinkTag: LinkModuleTag {
    public static var module: NetworkModules { .pdf }
    public static var contentType: UTType { .pdfLink }
}
public typealias LinkPdfData = ModuleLinkData<PdfLinkTag>

public enum PhotoLinkTag: LinkModuleTag {
    public static var module: NetworkModules { .photo }
    public static var contentType: UTType { .photoLink }
}
public typealias LinkPhotoData = ModuleLinkData<PhotoLinkTag>

public enum RuleLinkTag: LinkModuleTag {
    public static var module: NetworkModules { .rule }
    public static var contentType: UTType { .ruleLink }
}
public typealias LinkRuleData = ModuleLinkData<RuleLinkTag>

public enum SpaceLinkTag: LinkModuleTag {
    public static var module: NetworkModules { .space }
    public static var contentType: UTType { .spaceLink }
}
public typealias LinkSpaceData = ModuleLinkData<SpaceLinkTag>

public enum TableLinkTag: LinkModuleTag {
    public static var module: NetworkModules { .table }
    public static var contentType: UTType { .tableLink }
}
public typealias LinkTableData = ModuleLinkData<TableLinkTag>

public enum WeatherLinkTag: LinkModuleTag {
    public static var module: NetworkModules { .weather }
    public static var contentType: UTType { .weatherLink }
}
public typealias LinkWeatherData = ModuleLinkData<WeatherLinkTag>
