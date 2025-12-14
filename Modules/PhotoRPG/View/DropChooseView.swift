// @copyright André Trettin

import CoreRPG

import SwiftData
import SwiftUI

struct DropChooseView: View {
    let selectionModel: ItemSelectionModel
    
    @Environment(PhotoRootModel.self) private var root
    @Environment(\.appSizeMode) private var appSizeMode
    @Environment(\.navigator) private var navigator
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

    var body: some View {
        DropItemModuleArea(module: root.module, contentView: {
            Group {
                if let itemId = selectionModel.itemId, let item = root.itemController.itemSync(for: itemId), let cacheController = root.cacheController {
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
    
    private var emptyDrop: some View {
        Button {
            root.itemSelectionModel = selectionModel
#if os(macOS)
            openWindow(id: NetworkModules.photo.linkWindowId)
#else
            navigator.navigate(to: SelectionPhotoRoute.selection, method: .managedSheet)
#endif
        } label: {
            VStack {
                if showDrop {
                    Text("Drop \(root.module.title)", bundle: .module)
                    
                    Image(systemName: "square.and.arrow.down")
                        .imageScale(.large)
                }
                Text(chosseText, bundle: .module)
            }
            .padding(.horizontal, 12)
        }
        .contentShape(.rect)
    }
    
    private var chosseText: LocalizedStringKey {
#if os(macOS)
        "Open \(root.module.title)"
#else
        "Choose \(root.module.title)"
#endif
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
