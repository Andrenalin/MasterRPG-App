// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AnimatedMap: View {
    init(
        itemId: UUID,
        image: AKImage,
        date: Date,
        size: CGSize,
        initialEntryId: UUID = UUID()
    ) {
        self.itemId = itemId
        self.image = image
        self.date = date
        self.size = size
        self._entryId = State(wrappedValue: initialEntryId)
    }

    let itemId: UUID
    let image: AKImage
    let date: Date
    let size: CGSize

    @Environment(MapRootModel.self) private var root

    @State private var entryId: UUID
    @State private var dropPinModel = DropPinModel()

    var body: some View {
        VStack(alignment: .center) {
            DisplayMapViewer(image: image, itemId: itemId, entryId: $entryId, size: size)
                .environment(dropPinModel)
        }
        .onChange(of: date, initial: false) {
            Task {
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

#Preview(traits: .mockData) {
    AnimatedMap(
        itemId: MapModel.previewId,
        image: AKImage(),
        date: Date(timeIntervalSince1970: 1_700_000_000),
        size: CGSize(width: 320, height: 240),
        initialEntryId: MapEntryModel.previewId
    )
}
