// @copyright André Trettin

import CoreRPG

import SwiftData
import SwiftUI

struct DropChooseView: View {
    let selectionModel: ItemSelectionModel
    
    @Environment(PhotoRootModel.self) private var root
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(\.navigator) private var navigator
    @Environment(ScenesManager.self) private var scenesManager

    var body: some View {
        DropItemModuleArea(module: root.configurable.module, contentView: {
            Group {
                if let itemId = selectionModel.itemId, let item = root.itemController.itemSync(for: itemId), let cacheController = root.cacheController {
                    GroupedPhotoView(cacheController: cacheController, itemControllable: root.itemController, model: item)
                        .clipShape(.rect(corners: .concentric))
                        .environment(GroupItemSelectionModel())
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
            .borderLessTVBottonStyle()
            .padding(4)
            .contentShape(.circle)
            .glassEffectAll()
            .opacity(selectionModel.itemId != nil ? 1.0 : 0.0)
        }
    }
    
    private var emptyDrop: some View {
        Button {
            root.itemSelectionModel = selectionModel
#if os(macOS)
            scenesManager.openWindow(SceneId(rawValue: NetworkModules.photo.linkWindowId))
#else
            navigator.navigate(to: SelectionRoute.selection, method: .managedSheet)
#endif
        } label: {
            VStack {
                if showDrop {
                    Text("Drop \(root.configurable.module.title)", bundle: .module)
                    
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
        "Open \(root.configurable.module.title)"
#else
        "Choose \(root.configurable.module.title)"
#endif
    }

    private var showDrop: Bool {
        appSizeModel.mode == .regular
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
