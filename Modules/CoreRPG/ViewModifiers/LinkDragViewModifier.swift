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

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        switch module {
        case .adventure: draggable(content, tag: AdventureLinkTag.self)
        case .audio: draggable(content, tag: AudioLinkTag.self)
        case .value: draggable(content, tag: CharacterLinkTag.self)
        case .dice: draggable(content, tag: DiceLinkTag.self)
        case .map: draggable(content, tag: MapLinkTag.self)
        case .pdf: draggable(content, tag: PdfLinkTag.self)
        case .photo: draggable(content, tag: PhotoLinkTag.self)
        case .rule: draggable(content, tag: RuleLinkTag.self)
        case .space: draggable(content, tag: SpaceLinkTag.self)
        case .table: draggable(content, tag: TableLinkTag.self)
        case .weather: draggable(content, tag: WeatherLinkTag.self)
        default:
            content.draggable(LinkEntryData(itemId: itemId, entryId: entryId, name: name, module: module, isMove: isMove)) { preview() }
        }
#endif
    }

#if !os(tvOS)
    private func draggable<Tag: LinkModuleTag>(_ content: Content, tag: Tag.Type) -> some View {
        content.draggable(ModuleLinkData<Tag>(itemId: itemId, entryId: entryId, name: name, isMove: isMove)) { preview() }
    }
#endif
}

struct LinkDragViewModifier: ViewModifier {
    let itemId: UUID
    let entryId: UUID?
    let module: NetworkModules
    let name: String
    let isMove: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        switch module {
        case .adventure: draggable(content, tag: AdventureLinkTag.self)
        case .audio: draggable(content, tag: AudioLinkTag.self)
        case .value: draggable(content, tag: CharacterLinkTag.self)
        case .dice: draggable(content, tag: DiceLinkTag.self)
        case .map: draggable(content, tag: MapLinkTag.self)
        case .pdf: draggable(content, tag: PdfLinkTag.self)
        case .photo: draggable(content, tag: PhotoLinkTag.self)
        case .rule: draggable(content, tag: RuleLinkTag.self)
        case .space: draggable(content, tag: SpaceLinkTag.self)
        case .table: draggable(content, tag: TableLinkTag.self)
        case .weather: draggable(content, tag: WeatherLinkTag.self)
        default:
            content.draggable(LinkEntryData(itemId: itemId, entryId: entryId, name: name, module: module, isMove: isMove))
        }
#endif
    }

#if !os(tvOS)
    private func draggable<Tag: LinkModuleTag>(_ content: Content, tag: Tag.Type) -> some View {
        content.draggable(ModuleLinkData<Tag>(itemId: itemId, entryId: entryId, name: name, isMove: isMove))
    }
#endif
}

struct LinkDropDestinationViewModifier: ViewModifier {
    let module: NetworkModules
    let isEnabled: Bool
    let handler: (_ name: String, _ itenId: UUID, _ entryId: UUID?) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        switch module {
        case .adventure: dropDestination(content, tag: AdventureLinkTag.self)
        case .audio: dropDestination(content, tag: AudioLinkTag.self)
        case .value: dropDestination(content, tag: CharacterLinkTag.self)
        case .dice: dropDestination(content, tag: DiceLinkTag.self)
        case .map: dropDestination(content, tag: MapLinkTag.self)
        case .pdf: dropDestination(content, tag: PdfLinkTag.self)
        case .photo: dropDestination(content, tag: PhotoLinkTag.self)
        case .rule: dropDestination(content, tag: RuleLinkTag.self)
        case .space: dropDestination(content, tag: SpaceLinkTag.self)
        case .table: dropDestination(content, tag: TableLinkTag.self)
        case .weather: dropDestination(content, tag: WeatherLinkTag.self)
        default:
            content.dropDestination(for: LinkEntryData.self, isEnabled: isEnabled, action: link(links:session:))
        }
#endif
    }

#if !os(tvOS)
    private func dropDestination<Tag: LinkModuleTag>(_ content: Content, tag: Tag.Type) -> some View {
        content.dropDestination(for: ModuleLinkData<Tag>.self, isEnabled: isEnabled, action: link(links:session:))
    }

    private func link<Link: LinkDataTransferable>(links: [Link], session: DropSession) {
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

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        switch module {
        case .adventure: dropDestination(content, tag: AdventureLinkTag.self)
        case .audio: dropDestination(content, tag: AudioLinkTag.self)
        case .value: dropDestination(content, tag: CharacterLinkTag.self)
        case .dice: dropDestination(content, tag: DiceLinkTag.self)
        case .map: dropDestination(content, tag: MapLinkTag.self)
        case .pdf: dropDestination(content, tag: PdfLinkTag.self)
        case .photo: dropDestination(content, tag: PhotoLinkTag.self)
        case .rule: dropDestination(content, tag: RuleLinkTag.self)
        case .space: dropDestination(content, tag: SpaceLinkTag.self)
        case .table: dropDestination(content, tag: TableLinkTag.self)
        case .weather: dropDestination(content, tag: WeatherLinkTag.self)
        default:
            content.dropDestination(for: LinkEntryData.self, action: link(links:location:), isTargeted: isTargeted)
        }
#endif
    }

#if !os(tvOS)
    private func dropDestination<Tag: LinkModuleTag>(_ content: Content, tag: Tag.Type) -> some View {
        content.dropDestination(for: ModuleLinkData<Tag>.self, action: link(links:location:), isTargeted: isTargeted)
    }

    private func link<Link: LinkDataTransferable>(links: [Link], location: CGPoint) -> Bool {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
        return true
    }
#endif
}
