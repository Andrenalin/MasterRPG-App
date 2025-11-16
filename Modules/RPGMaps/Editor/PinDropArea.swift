// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGPhotos

struct PinDropArea: View {
    let root: MapRootModel
    let editController: EditController

    @State private var dropBackgroundColor: Color = .clear
    @State private var dropForegroundColor: Color = .primary

    var body: some View {
        HStack(spacing: 16) {
            Text("Drop Links", bundle: .module)
                .padding(4)
                .foregroundStyle(dropForegroundColor)
                .background {
                    RoundedRectangle(cornerRadius: 8).fill(dropBackgroundColor)
                }
        }
#if !os(tvOS)
        .dropDestination(for: LinkData.self) { items, _ in
            guard let draggedLinkData = items.first else { return false }
            return drop(link: draggedLinkData)
        } isTargeted: { inDropArea in
            dropBackgroundColor = inDropArea ? .accentColor : .clear
            dropForegroundColor = inDropArea ? .white : .primary
        }
#endif
    }

    func drop(link: LinkData) -> Bool {
        switch link.module {
        case .photo:
            let pin = MapPinModel(id: UUID(), name: link.name.withoutLink(), photoId: link.itemId)
            withAnimation {
                editController.add(pin: pin)
                editController.save(with: String(localized: "Add pin").localizedString)
            }
        case .value:
            let pins = [ItemRowModel(itemId: link.itemId, typeId: link.module)]
            withAnimation {
                editController.addMonsters(to: nil, monsters: pins, number: 1)
                editController.save(with: String(localized: "Add monster").localizedString)
            }
        default:
            return false
        }
        return true
    }
}

struct PinImageDropArea: View {
    let root: MapRootModel
    let editController: EditController
    let pin: MapPinModel
    
    @State private var photoId: UUID?

    var body: some View {
        root.photoRoot.viewController.onMapView(root: root.photoRoot, photoId: photoId, color: pin.color, size: pin.size.size, isDragging: false, isSelected: false)
            .id(photoId)
            .onChange(of: editController.model[MapPinId.id, pin.id], initial: true) {
                withAnimation { photoId <=> editController.model[MapPinId.id, pin.id].photoId }
            }
#if !os(tvOS)
        .dropDestination(for: LinkData.self) { items, _ in
            guard let draggedLinkData = items.first else { return false }
            return drop(link: draggedLinkData)
        } isTargeted: { inDropArea in
        }
#endif
    }

    func drop(link: LinkData) -> Bool {
        switch link.module {
        case .photo:
            withAnimation {
                photoId = link.itemId
                editController.model[MapPinId.id, pin.id].photoId = link.itemId
                editController.save(with: String(localized: "Change pin photo").localizedString)
            }
        default:
            return false
        }
        return true
    }
}
