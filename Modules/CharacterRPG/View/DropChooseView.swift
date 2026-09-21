// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DropChooseView: View {
    let selectionModel: ItemSelectionModel

    @Environment(CharacterRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cornerRadius: CGFloat = 24
    private static let contentHeight: CGFloat = 128
    private static let borderWidth: CGFloat = 2

    private var cornerShape: some Shape {
        .rect(cornerRadius: Self.cornerRadius, style: .continuous)
    }

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
            .frame(height: Self.contentHeight)
        }, dropAction: addLink(name:itemId:entryId:))
        .containerShape(.rect(cornerRadius: Self.cornerRadius))
        .background {
            cornerShape.fill(Color.accentColor.tertiary)
        }
        .overlay {
            cornerShape.stroke(Color.accentColor.secondary, lineWidth: Self.borderWidth)
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
            .borderLessTVButtonStyle()
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.circle)
            .opacity(selectionModel.itemId != nil ? 1.0 : 0.0)
            .allowsHitTesting(selectionModel.itemId != nil)
            .accessibilityHidden(selectionModel.itemId == nil)
        }
    }

    private var model: ValueModel? {
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
