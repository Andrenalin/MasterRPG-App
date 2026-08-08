// @copyright André Trettin

import CoreRPG

import SwiftData
import SwiftUI

struct DropChooseView: View {
    let selectionModel: ItemSelectionModel

    @Environment(PhotoRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DropItemModuleArea(module: root.configurable.module, contentView: {
            Group {
                if let itemId = selectionModel.itemId, let item = root.itemController.itemSync(for: itemId), let cacheController = root.cacheController {
                    GroupedPhotoView(cacheController: cacheController, itemControllable: root.itemController, model: item)
                        .clipShape(.rect(corners: .concentric))
                        .environment(GroupItemSelectionModel())
                } else {
                    EmptyDropButton(selectionModel: selectionModel)
                }
            }
            .frame(height: 128)
        }, dropAction: addLink(name:itemId:entryId:))
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
        .overlay(alignment: .topTrailing) {
            Button(role: .destructive) {
                withAnimation(reduceMotion ? nil : .default) {
                    selectionModel.selection = []
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.white, .red, .red)
            }
            .accessibilityLabel(Text("Remove", bundle: .module))
            .frame(minWidth: 44, minHeight: 44)
            .borderLessTVBottonStyle()
            .padding(4)
            .contentShape(.circle)
            .opacity(selectionModel.itemId != nil ? 1.0 : 0.0)
            .allowsHitTesting(selectionModel.itemId != nil)
            .accessibilityHidden(selectionModel.itemId == nil)
        }
    }

    private func addLink(name: String, itemId: UUID, entryId: UUID?) {
        selectionModel.selection = [WindowItemSelection(itemId: itemId, entryId: entryId)]
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        DropChooseView(selectionModel: ItemSelectionModel())
    }
}
