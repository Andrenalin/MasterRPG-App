// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

struct DropChooseView: View {
    let selectionModel: ItemSelectionModel
    
    @Environment(CharacterRootModel.self) private var root
    @Environment(\.appSizeMode) private var appSizeMode
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        DropItemModuleArea(module: root.module, contentView: {
            Group {
                if let model {
                    Text(model.name)
                    if let photoId = model.photoId {
                        root.viewController.thumbnailRowView(for: photoId)
                    }
                } else {
                    emptyDrop
                }
            }
            .frame(height: 128)
        }, dropAction: addLink(name:itemId:entryId:))
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
                withAnimation {
                    selectionModel.selection = []
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.white, .red, .red)
            }
#if !os(visionOS)
            .glassEffect()
#endif
            .opacity(selectionModel.itemId != nil ? 1.0 : 0.0)
        }
    }
    
    private var model: ValueModel? {
        guard let itemId = selectionModel.itemId else { return nil }
        return root.itemController.itemSync(for: itemId)
    }

    private var emptyDrop: some View {
        Button {
            root.itemSelectionModel = selectionModel
            navigator.navigate(to: SelectionCharacterRoute.selection, method: .managedSheet)
        } label: {
            VStack {
                if showDrop {
                    Text("Drop \(root.module.title)", bundle: .module)
                    
                    Image(systemName: "square.and.arrow.down")
                        .imageScale(.large)
                }
                Text("Choose \(root.module.title)", bundle: .module)
            }
            .padding(.horizontal, 12)
        }
    }
    
    private var showDrop: Bool {
        appSizeMode == .regular
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
