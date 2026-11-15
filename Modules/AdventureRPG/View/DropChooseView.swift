// @copyright André Trettin

import CoreRPG

import SwiftUI

private let dropAreaCornerRadius: CGFloat = 24
private let dropAreaHeight: CGFloat = 128
private let dropAreaShape: RoundedRectangle = .rect(cornerRadius: dropAreaCornerRadius, style: .continuous)

struct DropChooseView: View {
    let selectionModel: ItemSelectionModel

    @Environment(AdventureRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DropItemModuleArea(module: root.configurable.module, contentView: {
            VStack {
                if let model {
                    root.viewController.thumbnailRowView(for: model.id)
                        .clipShape(.rect(corners: .concentric))
                    Text(verbatim: model.name)
                } else {
                    EmptyDropButton(selectionModel: selectionModel)
                }
            }
            .frame(height: dropAreaHeight)
        }, dropAction: addLink(name:itemId:entryId:))
        .containerShape(.rect(cornerRadius: dropAreaCornerRadius))
        .background(Color.accentColor.tertiary, in: .rect(cornerRadius: dropAreaCornerRadius, style: .continuous))
        .overlay {
            dropAreaShape
                .stroke(Color.accentColor.secondary, lineWidth: 2)
        }
        .padding(1)
        .overlay(alignment: .topTrailing) {
            Button(role: .destructive) {
                withAnimation(reduceMotion ? nil : .default) {
                    selectionModel.selection = []
                }
            } label: {
                Label {
                    Text("Remove", bundle: .module)
                } icon: {
                    Image(systemName: "minus.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.white, .red, .red)
                }
                .labelStyle(.iconOnly)
            }
            .borderLessTVButtonStyle()
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.circle)
            .opacity(selectionModel.itemId != nil ? 1.0 : 0.0)
            .allowsHitTesting(selectionModel.itemId != nil)
            .accessibilityHidden(selectionModel.itemId == nil)
            .disabled(selectionModel.itemId == nil)
        }
    }

    private var model: AdventureModel? {
        guard let itemId = selectionModel.itemId else { return nil }
        return root.itemController.itemSync(for: itemId)
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
