// @copyright André Trettin

import CoreRPG

import SwiftData
import SwiftUI

struct PhotoDropChooseView: View {
    let model: ItemSelectionModel
    
    @Environment(PhotoRootModel.self) private var root
    @Environment(\.appSizeMode) private var appSizeMode
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        DropItemModuleArea(module: root.module, contentView: {
            Group {
                if let itemId = model.itemId, let item = root.itemController.itemSync(for: itemId), let cacheController = root.cacheController {
                    GroupedPhotoView(cacheController: cacheController, itemControllable: root.itemController, model: item)
                        .clipShape(.rect(corners: .concentric))
                } else {
                    emptyDrop
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
                withAnimation {
                    model.selection = []
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.white, .red, .red)
            }
#if !os(visionOS)
            .glassEffect()
#endif
            .opacity(model.itemId != nil ? 1.0 : 0.0)
        }
    }
    
    private var emptyDrop: some View {
        Button {
            root.itemSelectionModel = model
            navigator.navigate(to: SelectionPhotoRoute.selection, method: .managedSheet)
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
        .contentShape(.rect)
    }
    
    private var showDrop: Bool {
        appSizeMode == .regular
    }
    
    private func addLink(name: String, itemId: UUID, entryId: UUID?) {
        model.selection = [WindowItemSelection(itemId: itemId, entryId: entryId)]
    }
}

#Preview(traits: .mockData) {
    PhotoDropChooseView(model: ItemSelectionModel())
}
