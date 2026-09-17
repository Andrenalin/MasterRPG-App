// @copyright André Trettin

import CoreRPG

import SwiftUI

struct DropChooseView: View {
    let selectionModel: ItemSelectionModel

    @Environment(DiceRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DropItemModuleArea(module: root.configurable.module, contentView: {
            Group {
                if let model {
                    DiceViewer(model: model, isEditor: false)
                        .fixedSize()
                        .frame(minWidth: 128)
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
                withAnimation(Animation.default.reduced(if: reduceMotion)) {
                    selectionModel.selection = []
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.white, .red, .red)
            }
            .accessibilityLabel(Text("Remove", bundle: .module))
            .borderLessTVBottonStyle()
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.circle)
            .opacity(selectionModel.itemId != nil ? 1.0 : 0.0)
            .allowsHitTesting(selectionModel.itemId != nil)
            .accessibilityHidden(selectionModel.itemId == nil)
        }
    }

    private var model: DiceModel? {
        guard let itemId = selectionModel.itemId else { return nil }
        return root.itemController.itemSync(for: itemId)
    }

    private func addLink(name: String, itemId: UUID, entryId: UUID?) {
        selectionModel.selection = [WindowItemSelection(itemId: itemId, entryId: entryId)]
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        DropChooseView(selectionModel: ItemSelectionModel(selection: [WindowItemSelection(itemId: DiceModel.previewId)]))
    }
}
