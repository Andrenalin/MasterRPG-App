// @copyright André Trettin

import AdventureRPG
import CoreRPG
import SwiftUI

enum ImportRoute {
    case importGame
}

extension ImportRoute: NavigationDestination {
    var body: some View {
        ImportRouteDestinationView(route: self)
    }
}

struct ImportRouteDestinationView: View {
    let route: ImportRoute

    @Environment(AdventureRootModel.self) private var root

    @AppStorage("lastAdventureUUID", store: .standard)
    private var lastAdventureUUID: String = ""

    var body: some View {
        switch route {
        case .importGame:
            ImportProgressPanelView(importController: root.importControllable) { fileUrl in
                selectAdventureIfMatched(fileUrl: fileUrl)
            }
        }
    }

    // A save game's filename is "<adventure title>-<yyyyMMdd>.gms" (see ExportControllable.exportUrl).
    // If exactly one local adventure's name matches, make it the starting adventure.
    private func selectAdventureIfMatched(fileUrl: URL) {
        guard let title = adventureTitle(from: fileUrl), let adventureId = adventureId(named: title) else { return }
        lastAdventureUUID = adventureId.uuidString
    }

    private func adventureTitle(from fileUrl: URL) -> String? {
        let base = fileUrl.deletingPathExtension().lastPathComponent
        guard let separatorIndex = base.lastIndex(of: "-") else { return nil }
        let datePart = base[base.index(after: separatorIndex)...]
        guard datePart.count == 8, datePart.allSatisfy(\.isNumber) else { return nil }
        let title = base[base.startIndex..<separatorIndex]
        return title.isEmpty ? nil : String(title)
    }

    private func adventureId(named title: String) -> UUID? {
        let itemControllable = root.itemControllable
        let matches = itemControllable.itemDataModel.items.filter {
            itemControllable.nameSync(itemId: $0).localizedCaseInsensitiveCompare(title) == .orderedSame
        }
        return matches.count == 1 ? matches.first : nil
    }
}

#Preview(traits: .mockData) {
    ImportRouteDestinationView(route: .importGame)
}
