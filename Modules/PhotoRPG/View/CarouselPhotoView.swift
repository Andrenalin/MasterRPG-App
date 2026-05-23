// @copyright André Trettin

import CoreRPG
import SwiftUI

struct CarouselPhotoView: View {
    let photoIds: ItemSelectionModel
    let selection: GroupItemSelectionModel
    
    @Environment(PhotoRootModel.self) private var root
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(\.navigator) private var navigator
    @Environment(ScenesManager.self) private var scenesManager

    enum SheetType: Identifiable {
        case selection
        var id: Self { self }
    }
    @State private var activeSheet: SheetType?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack {
                ForEach(photoIds.selection, id: \.self.itemId) { photoId in
                    itemView(itemId: photoId.itemId, selectedItemId: photoId.itemId)
                        .overlay(alignment: .topTrailing) {
                            Button(role: .destructive) {
                                withAnimation(.easeInOut) { photoIds.selection.removeAll(where: { $0 == photoId }) }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .imageScale(.large)
                                    .foregroundStyle(.white, .red, .red)
                            }
                            .borderLessTVBottonStyle()
                            .padding(4)
                            .contentShape(.circle)
#if !os(visionOS)
                            .glassEffect(.regular.interactive())
#endif
                        }
                }
                
                dropItemView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .environment(selection)
    }
}

private extension CarouselPhotoView {
    @ViewBuilder
    var dropItemView: some View {
        DropItemModuleArea(module: root.configurable.module, contentView: {
            areaButton
        }, dropAction: linkHandler(name:itemId:entryId:))
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
    
    var areaButton: some View {
        VStack {
            if appSizeModel.mode == .regular {
                Text("Drop \(root.configurable.module.title)", bundle: .module)
                
                Image(systemName: "square.and.arrow.down")
                    .imageScale(.large)
            }
            
            Button {
                #if os(macOS)
                scenesManager.openWindow(SceneId.sceneId(for: .photo))
                #else
                withAnimation(.easeInOut) { activeSheet = .selection }
                #endif
            } label: {
                VStack {
                    Text("Select", bundle: .module)
                    if appSizeModel.mode == .compact {
                        Text(root.configurable.module.title)
                        Image(systemName: "checkmark.circle")
                            .imageScale(.large)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 100)
        .frame(height: 100)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .selection:
                ManagedPresentationView {
                    SelectionRoute.mutliSelection
                        .environment(photoIds)
                }
            }
        }
    }
    
    func linkHandler(name: String, itemId: UUID, entryId: UUID?) {
        guard !photoIds.selection.contains(where: { $0.itemId == itemId }) else { return }
        withAnimation(.easeInOut) { photoIds.selection.append(WindowItemSelection(itemId: itemId)) }
    }
    
    func itemView(itemId: UUID, selectedItemId: UUID?) -> some View {
        Button {
            withAnimation(.easeInOut) { selection.selectedItem = selectedItemId }
        } label: {
            Group {
                if let cacheControllable = root.cacheControllable {
                    GroupedPhotoView(cacheController: cacheControllable, itemControllable: root.itemControllable, model: nil)
                }
            }
            .environment(GroupItemSelectionModel(selectedItem: itemId))
            .frame(height: 110)
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .dropDestination(for: root.configurable.module, handler: linkHandler(name:itemId:entryId:))
        .padding(1)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(PhotoRootModel.self) var root
    
    CarouselPhotoView(photoIds: ItemSelectionModel(selection: root.itemController.itemDataModel.items.map { WindowItemSelection(itemId: $0) }, isSingleSelection: false), selection: GroupItemSelectionModel())
}
