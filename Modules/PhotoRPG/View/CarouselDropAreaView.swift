// @copyright André Trettin

import CoreRPG
import SwiftUI

struct CarouselDropAreaView: View {
    let photoIds: ItemSelectionModel

    @Environment(PhotoRootModel.self) private var root
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSheet = false

    var body: some View {
        DropItemModuleArea(module: root.configurable.module) {
            EmptyDropButton(selectionModel: photoIds)
                .frame(height: 128)
        } dropAction: { _, itemId, _ in
            addLink(itemId: itemId)
        }
        .containerShape(.rect(cornerRadius: 20))
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.accentColor.tertiary)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.accentColor.secondary, lineWidth: 2)
        }
        .padding(1)
#if !os(macOS)
        .sheet(isPresented: $showSheet) {
            ManagedPresentationView {
                ManagedNavigationStack {
                    SelectionRoute.mutliSelection
                }
            }
            .environment(photoIds)
        }
#endif
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
