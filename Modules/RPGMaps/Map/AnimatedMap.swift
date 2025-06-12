// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AnimatedMap: View {
    let editController: EditController
    let image: AKImage
    let date: Date
    let size: CGSize

    @Environment(MapRoot.self) private var root

    @State private var entryId = UUID()
    @State private var dropPinModel = DropPinModel()

    var body: some View {
        @Bindable var model = editController.model

        VStack(alignment: .center) {
            DisplayMapViewer(editController: editController, image: image, itemId: model.id, entryId: $entryId, size: size)
                .environment(dropPinModel)
        }
        .onChange(of: date, initial: false) {
            Task { @MainActor in
                withAnimation { entryId = randomEntries() }
            }
        }
    }

    private func randomEntries() -> UUID {
        let count = editController.model.entries.count
        guard count > 0 else { return UUID() }
        if count == 1 {
            return editController.model.entries[0].id
        }
        return editController.model.entries[Int.random(in: 0..<count)].id
    }
}
