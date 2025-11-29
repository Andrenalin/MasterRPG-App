// @copyright André Trettin

import CoreRPG
import SwiftUI
import AudioRPG
import WeatherRPG
import CharacterRPG
import TableRPG
import SpaceRPG
import PhotoRPG
import PdfRPG
import MapRPG
import DiceRPG

struct AdventureDropArea: View {
    let root: AdventureRootModel
    let editController: EditController
    let entryId: AdventureEntryModel.ID

    @State private var dropBackgroundColor: Color = .clear
    @State private var dropForegroundColor: Color = .primary
    @State private var selectedId: UUID?

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
        var content = editController.model[entryId].content
        switch link.module {
        case .adventure:
            content = root.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
        case .audio:
            content = root.audioRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
        case .dice:
            content = root.diceRoot.linkController.generateLinks(itemId: link.itemId, into: content)
        case .map:
            content = root.mapRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
        case .pdf:
            content = root.pdfRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
        case .photo:
            content = root.photoRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
        case .space:
            content = root.spaceRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
        case .table:
            content = root.tableRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
        case .value:
            content = root.characterRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
        case .weather:
            content = root.weatherRoot.linkController.generateLinks(itemId: link.itemId, into: content)
        default:
            return false
        }
        withAnimation {
            editController.model[entryId].content = content
            editController.save(with: String(localized: "Add link").localizedString)
        }
        return true
    }
}
