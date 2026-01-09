// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

extension View {
    public func draggable(for module: NetworkModules, itemId: UUID, entryId: UUID?, name: String) -> some View {
        modifier(LinkDragViewModifier(itemId: itemId, entryId: entryId, module: module, name: name))
    }
    
    public func dropDestination(for module: NetworkModules, isEnabled: Bool = true, handler: @escaping (_ name: String, _ itenId: UUID, _ entryId: UUID?) -> Void) -> some View {
        modifier(LinkDropDestinationViewModifier(module: module, isEnabled: isEnabled, handler: handler))
    }
    
    public func dropDestination(for module: NetworkModules, handler: @escaping (_ name: String, _ itenId: UUID, _ entryId: UUID?) -> Void, isTargeted: @escaping (Bool) -> Void) -> some View {
        modifier(LinkDropDestinationTargetedViewModifier(module: module, handler: handler, isTargeted: isTargeted))
    }
}

struct LinkDragViewModifier: ViewModifier {
    let itemId: UUID
    let entryId: UUID?
    let module: NetworkModules
    let name: String
    
    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        switch module {
        case .adventure: content.draggable(LinkAdventureData(itemId: itemId, entryId: entryId, name: name))
        case .audio: content.draggable(LinkAudioData(itemId: itemId, entryId: entryId, name: name))
        case .value: content.draggable(LinkCharacterData(itemId: itemId, entryId: entryId, name: name))
        case .dice: content.draggable(LinkDiceData(itemId: itemId, entryId: entryId, name: name))
        case .map: content.draggable(LinkMapData(itemId: itemId, entryId: entryId, name: name))
        case .pdf: content.draggable(LinkPdfData(itemId: itemId, entryId: entryId, name: name))
        case .photo: content.draggable(LinkPhotoData(itemId: itemId, entryId: entryId, name: name))
        case .space: content.draggable(LinkSpaceData(itemId: itemId, entryId: entryId, name: name))
        case .table: content.draggable(LinkTableData(itemId: itemId, entryId: entryId, name: name))
        case .weather: content.draggable(LinkWeatherData(itemId: itemId, entryId: entryId, name: name))
        default: content.draggable(LinkEntryData(itemId: itemId, entryId: entryId, name: name, module: module))
        }
#endif
    }
}

struct LinkDropDestinationViewModifier: ViewModifier {
    let module: NetworkModules
    let isEnabled: Bool
    let handler: (_ name: String, _ itenId: UUID, _ entryId: UUID?) -> Void
    
    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        switch module {
        case .adventure: content.dropDestination(for: LinkAdventureData.self, isEnabled: isEnabled, action: linkAdventure(links:session:))
        case .audio: content.dropDestination(for: LinkAudioData.self, isEnabled: isEnabled, action: linkAudio(links:session:))
        case .value: content.dropDestination(for: LinkCharacterData.self, isEnabled: isEnabled, action: linkCharacter(links:session:))
        case .dice: content.dropDestination(for: LinkDiceData.self, isEnabled: isEnabled, action: linkDice(links:session:))
        case .map: content.dropDestination(for: LinkMapData.self, isEnabled: isEnabled, action: linkMap(links:session:))
        case .pdf: content.dropDestination(for: LinkPdfData.self, isEnabled: isEnabled, action: linkPdf(links:session:))
        case .photo: content.dropDestination(for: LinkPhotoData.self, isEnabled: isEnabled, action: linkPhoto(links:session:))
        case .space: content.dropDestination(for: LinkSpaceData.self, isEnabled: isEnabled, action: linkSpace(links:session:))
        case .table: content.dropDestination(for: LinkTableData.self, isEnabled: isEnabled, action: linkTable(links:session:))
        case .weather: content.dropDestination(for: LinkWeatherData.self, isEnabled: isEnabled, action: linkWeather(links:session:))
        default: content.dropDestination(for: LinkAdventureData.self, isEnabled: isEnabled, action: linkAdventure(links:session:))
        }
#endif
    }

#if !os(tvOS)
    @MainActor func linkAdventure(links: [LinkAdventureData], session: DropSession) {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
    }
    
    func linkAudio(links: [LinkAudioData], session: DropSession) {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
    }
    
    func linkCharacter(links: [LinkCharacterData], session: DropSession) {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
    }
    
    func linkDice(links: [LinkDiceData], session: DropSession) {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
    }
    
    func linkMap(links: [LinkMapData], session: DropSession) {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
    }
    
    func linkPdf(links: [LinkPdfData], session: DropSession) {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
    }
    
    func linkPhoto(links: [LinkPhotoData], session: DropSession) {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
    }
    
    func linkSpace(links: [LinkSpaceData], session: DropSession) {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
    }
    
    func linkTable(links: [LinkTableData], session: DropSession) {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
    }
    
    func linkWeather(links: [LinkWeatherData], session: DropSession) {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
    }
#endif
}


struct LinkDropDestinationTargetedViewModifier: ViewModifier {
    let module: NetworkModules
    let handler: (_ name: String, _ itenId: UUID, _ entryId: UUID?) -> Void
    let isTargeted: (Bool) -> Void
    
    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        switch module {
        case .adventure: content.dropDestination(for: LinkAdventureData.self, action: linkAdventure(links:location:), isTargeted: isTargeted)
        case .audio: content.dropDestination(for: LinkAudioData.self, action: linkAudio(links:location:), isTargeted: isTargeted)
        case .value: content.dropDestination(for: LinkCharacterData.self, action: linkCharacter(links:location:), isTargeted: isTargeted)
        case .dice: content.dropDestination(for: LinkDiceData.self, action: linkDice(links:location:), isTargeted: isTargeted)
        case .map: content.dropDestination(for: LinkMapData.self, action: linkMap(links:location:), isTargeted: isTargeted)
        case .pdf: content.dropDestination(for: LinkPdfData.self, action: linkPdf(links:location:), isTargeted: isTargeted)
        case .photo: content.dropDestination(for: LinkPhotoData.self, action: linkPhoto(links:location:), isTargeted: isTargeted)
        case .space: content.dropDestination(for: LinkSpaceData.self, action: linkSpace(links:location:), isTargeted: isTargeted)
        case .table: content.dropDestination(for: LinkTableData.self, action: linkTable(links:location:), isTargeted: isTargeted)
        case .weather: content.dropDestination(for: LinkWeatherData.self, action: linkWeather(links:location:), isTargeted: isTargeted)
        default: content.dropDestination(for: LinkAdventureData.self, action: linkAdventure(links:location:), isTargeted: isTargeted)
        }
#endif
    }
    
    @MainActor func linkAdventure(links: [LinkAdventureData], location: CGPoint) -> Bool {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
        return true
    }
    
    func linkAudio(links: [LinkAudioData], location: CGPoint) -> Bool {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
        return true
    }
    
    func linkCharacter(links: [LinkCharacterData], location: CGPoint) -> Bool {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
        return true
    }
    
    func linkDice(links: [LinkDiceData], location: CGPoint) -> Bool {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
        return true
    }
    
    func linkMap(links: [LinkMapData], location: CGPoint) -> Bool {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
        return true
    }
    
    func linkPdf(links: [LinkPdfData], location: CGPoint) -> Bool {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
        return true
    }
    
    func linkPhoto(links: [LinkPhotoData], location: CGPoint) -> Bool {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
        return true
    }
    
    func linkSpace(links: [LinkSpaceData], location: CGPoint) -> Bool {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
        return true
    }
    
    func linkTable(links: [LinkTableData], location: CGPoint) -> Bool {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
        return true
    }
    
    func linkWeather(links: [LinkWeatherData], location: CGPoint) -> Bool {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
        return true
    }
}
