// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AnimatedMap: View {
    let itemId: UUID
    let image: AKImage
    let date: Date
    let size: CGSize

    @Environment(MapRootModel.self) private var root

    @State private var entryId = UUID()
    @State private var dropPinModel = DropPinModel()

    var body: some View {
        VStack(alignment: .center) {
            DisplayMapViewer(image: image, itemId: itemId, entryId: $entryId, size: size)
                .environment(dropPinModel)
        }
        .onChange(of: date, initial: false) {
            Task { @MainActor in
                withAnimation { entryId = randomEntries() }
            }
        }
    }

    private func randomEntries() -> UUID {
        let count = root.itemController.itemOrEmpty(for: itemId).entries.count
        guard count > 0 else { return UUID() }
        if count == 1 {
            return root.itemController.itemOrEmpty(for: itemId).entries[0].id
        }
        return root.itemController.itemOrEmpty(for: itemId).entries[Int.random(in: 0..<count)].id
    }
}
