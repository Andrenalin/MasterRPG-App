// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

extension View {
    func draggable<Preview: View>(for module: NetworkModules, itemId: UUID, entryId: UUID?, name: String, isMove: Bool = false, @ViewBuilder preview: @escaping () -> Preview) -> some View {
        modifier(LinkDragViewModifierPreview(itemId: itemId, entryId: entryId, module: module, name: name, isMove: isMove, preview: preview))
    }

    // Convenience overload for call sites that don't need a custom drag preview
    public func draggable(for module: NetworkModules, itemId: UUID, entryId: UUID?, name: String, isMove: Bool = false) -> some View {
        modifier(LinkDragViewModifier(itemId: itemId, entryId: entryId, module: module, name: name, isMove: isMove))
    }

    public func dropDestination(for module: NetworkModules, isEnabled: Bool = true, handler: @escaping (_ name: String, _ itenId: UUID, _ entryId: UUID?) -> Void) -> some View {
        modifier(LinkDropDestinationViewModifier(module: module, isEnabled: isEnabled, handler: handler))
    }
    
    public func dropDestination(for module: NetworkModules, handler: @escaping (_ name: String, _ itenId: UUID, _ entryId: UUID?) -> Void, isTargeted: @escaping (Bool) -> Void) -> some View {
        modifier(LinkDropDestinationTargetedViewModifier(module: module, handler: handler, isTargeted: isTargeted))
    }
}

struct LinkDragViewModifierPreview<Preview: View>: ViewModifier {
    let itemId: UUID
    let entryId: UUID?
    let module: NetworkModules
    let name: String
    let isMove: Bool
    let preview: () -> Preview

    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        switch module {
        case .adventure: content.draggable(LinkAdventureData(itemId: itemId, entryId: entryId, name: name, isMove: isMove)) { preview() }
        case .audio: content.draggable(LinkAudioData(itemId: itemId, entryId: entryId, name: name, isMove: isMove)) { preview() }
        case .value: content.draggable(LinkCharacterData(itemId: itemId, entryId: entryId, name: name, isMove: isMove)) { preview() }
        case .dice: content.draggable(LinkDiceData(itemId: itemId, entryId: entryId, name: name, isMove: isMove)) { preview() }
        case .map: content.draggable(LinkMapData(itemId: itemId, entryId: entryId, name: name, isMove: isMove)) { preview() }
        case .pdf: content.draggable(LinkPdfData(itemId: itemId, entryId: entryId, name: name, isMove: isMove)) { preview() }
        case .photo: content.draggable(LinkPhotoData(itemId: itemId, entryId: entryId, name: name, isMove: isMove)) { preview() }
        case .rule: content.draggable(LinkRuleData(itemId: itemId, entryId: entryId, name: name, isMove: isMove)) { preview() }
        case .space: content.draggable(LinkSpaceData(itemId: itemId, entryId: entryId, name: name, isMove: isMove)) { preview() }
        case .table: content.draggable(LinkTableData(itemId: itemId, entryId: entryId, name: name, isMove: isMove)) { preview() }
        case .weather: content.draggable(LinkWeatherData(itemId: itemId, entryId: entryId, name: name, isMove: isMove)) { preview() }
        default: content.draggable(LinkEntryData(itemId: itemId, entryId: entryId, name: name, module: module, isMove: isMove)) { preview() }
        }
#endif
    }
}

struct LinkDragViewModifier: ViewModifier {
    let itemId: UUID
    let entryId: UUID?
    let module: NetworkModules
    let name: String
    let isMove: Bool

    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        switch module {
        case .adventure: content.draggable(LinkAdventureData(itemId: itemId, entryId: entryId, name: name, isMove: isMove))
        case .audio: content.draggable(LinkAudioData(itemId: itemId, entryId: entryId, name: name, isMove: isMove))
        case .value: content.draggable(LinkCharacterData(itemId: itemId, entryId: entryId, name: name, isMove: isMove))
        case .dice: content.draggable(LinkDiceData(itemId: itemId, entryId: entryId, name: name, isMove: isMove))
        case .map: content.draggable(LinkMapData(itemId: itemId, entryId: entryId, name: name, isMove: isMove))
        case .pdf: content.draggable(LinkPdfData(itemId: itemId, entryId: entryId, name: name, isMove: isMove))
        case .photo: content.draggable(LinkPhotoData(itemId: itemId, entryId: entryId, name: name, isMove: isMove))
        case .rule: content.draggable(LinkRuleData(itemId: itemId, entryId: entryId, name: name, isMove: isMove))
        case .space: content.draggable(LinkSpaceData(itemId: itemId, entryId: entryId, name: name, isMove: isMove))
        case .table: content.draggable(LinkTableData(itemId: itemId, entryId: entryId, name: name, isMove: isMove))
        case .weather: content.draggable(LinkWeatherData(itemId: itemId, entryId: entryId, name: name, isMove: isMove))
        default: content.draggable(LinkEntryData(itemId: itemId, entryId: entryId, name: name, module: module, isMove: isMove))
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
        case .rule: content.dropDestination(for: LinkRuleData.self, isEnabled: isEnabled, action: linkRule(links:session:))
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

    func linkRule(links: [LinkRuleData], session: DropSession) {
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
        case .rule: content.dropDestination(for: LinkRuleData.self, action: linkRule(links:location:), isTargeted: isTargeted)
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

    func linkRule(links: [LinkRuleData], location: CGPoint) -> Bool {
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
