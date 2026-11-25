// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

extension View {
    func draggable<Preview: View>(for module: NetworkModules, itemId: UUID, entryId: UUID?, name: String, isMove: Bool = false, @ViewBuilder preview: @escaping () -> Preview) -> some View {
        modifier(LinkTransferViewModifier(module: module, role: .drag(itemId: itemId, entryId: entryId, name: name, isMove: isMove, preview: preview, isEnabled: true)))
    }

    // Convenience overload for call sites that don't need a custom drag preview
    public func draggable(for module: NetworkModules, itemId: UUID, entryId: UUID?, name: String, isMove: Bool = false, isEnabled: Bool = true) -> some View {
        modifier(LinkTransferViewModifier<EmptyView>(module: module, role: .drag(itemId: itemId, entryId: entryId, name: name, isMove: isMove, preview: nil, isEnabled: isEnabled)))
    }

    public func dropDestination(for module: NetworkModules, isEnabled: Bool = true, handler: @escaping (_ name: String, _ itenId: UUID, _ entryId: UUID?) -> Void) -> some View {
        modifier(LinkTransferViewModifier<EmptyView>(module: module, role: .drop(isEnabled: isEnabled, handler: handler)))
    }
    
    public func dropDestination(for module: NetworkModules, handler: @escaping (_ name: String, _ itenId: UUID, _ entryId: UUID?) -> Void, isTargeted: @escaping (Bool) -> Void) -> some View {
        modifier(LinkTransferViewModifier<EmptyView>(module: module, role: .targetedDrop(handler: handler, isTargeted: isTargeted)))
    }
}

/// Drag source or drop destination of a module's link. The module decides the link type
/// (`ModuleLinkData<Tag>`, one `UTType` per module); a module without a tag uses the generic
/// `LinkEntryData`. The module table is the one `switch` in `body`, and one generic helper builds
/// the drag or drop for a link type. See CODE_AUDIT_28 §9.5.
struct LinkTransferViewModifier<Preview: View>: ViewModifier {
    typealias Handler = (_ name: String, _ itemId: UUID, _ entryId: UUID?) -> Void

    enum Role {
        case drag(itemId: UUID, entryId: UUID?, name: String, isMove: Bool, preview: (() -> Preview)?, isEnabled: Bool)
        case drop(isEnabled: Bool, handler: Handler)
        case targetedDrop(handler: Handler, isTargeted: (Bool) -> Void)
    }

    let module: NetworkModules
    let role: Role

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        switch module {
        case .adventure: transfer(content, tag: AdventureLinkTag.self)
        case .audio: transfer(content, tag: AudioLinkTag.self)
        case .value: transfer(content, tag: CharacterLinkTag.self)
        case .dice: transfer(content, tag: DiceLinkTag.self)
        case .map: transfer(content, tag: MapLinkTag.self)
        case .pdf: transfer(content, tag: PdfLinkTag.self)
        case .photo: transfer(content, tag: PhotoLinkTag.self)
        case .rule: transfer(content, tag: RuleLinkTag.self)
        case .space: transfer(content, tag: SpaceLinkTag.self)
        case .table: transfer(content, tag: TableLinkTag.self)
        case .weather: transfer(content, tag: WeatherLinkTag.self)
        default:
            transfer(content) { itemId, entryId, name, isMove in
                LinkEntryData(itemId: itemId, entryId: entryId, name: name, module: module, isMove: isMove)
            }
        }
#endif
    }

#if !os(tvOS)
    private func transfer<Tag: LinkModuleTag>(_ content: Content, tag: Tag.Type) -> some View {
        transfer(content) { itemId, entryId, name, isMove in
            ModuleLinkData<Tag>(itemId: itemId, entryId: entryId, name: name, isMove: isMove)
        }
    }

    /// `make` builds the dragged link; for a drop only its type matters.
    @ViewBuilder
    private func transfer<Link: LinkDataTransferable>(
        _ content: Content,
        make: @escaping (_ itemId: UUID, _ entryId: UUID?, _ name: String, _ isMove: Bool) -> Link
    ) -> some View {
        switch role {
        case let .drag(itemId, entryId, name, isMove, preview, isEnabled):
            if !isEnabled {
                content
            } else if let preview {
                content.draggable(make(itemId, entryId, name, isMove)) { preview() }
            } else {
                content.draggable(make(itemId, entryId, name, isMove))
            }
        case let .drop(isEnabled, handler):
            content.dropDestination(for: Link.self, isEnabled: isEnabled) { links, _ in
                follow(links, handler: handler)
            }
        case let .targetedDrop(handler, isTargeted):
            content.dropDestination(for: Link.self, action: { links, _ in
                follow(links, handler: handler)
                return true
            }, isTargeted: isTargeted)
        }
    }

    private func follow<Link: LinkDataTransferable>(_ links: [Link], handler: Handler) {
        links.forEach { link in
            withAnimation { handler(link.name, link.itemId, link.entryId) }
        }
    }
#endif
}
