// @copyright André Trettin

import CoreRPG
import SwiftUI

struct CarouselDropAreaView: View {
    let photoIds: ItemSelectionModel

    @Environment(PhotoRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DropItemModuleArea(module: root.configurable.module) {
            EmptyDropButton(selectionModel: photoIds)
                .frame(height: 120)
        } dropAction: { _, itemId, _ in
            addLink(itemId: itemId)
        }
        .containerShape(.rect(cornerRadius: 24))
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.accentColor.tertiary)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.accentColor.secondary, lineWidth: 2)
        }
        .padding(1)
    }

    private var chooseText: LocalizedStringKey {
#if os(macOS)
        "Open \(root.configurable.module.title)"
#else
        "Choose \(root.configurable.module.title)"
#endif
    }

    private func addLink(itemId: UUID) {
        guard !photoIds.selection.contains(where: { $0.itemId == itemId }) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut) {
            photoIds.selection.append(WindowItemSelection(itemId: itemId))
        }
    }
}

#Preview(traits: .mockData) {
    CarouselDropAreaView(photoIds: ItemSelectionModel(isSingleSelection: false))
}
