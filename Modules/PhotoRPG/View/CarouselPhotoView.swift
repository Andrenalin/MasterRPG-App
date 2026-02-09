// @copyright André Trettin

import CoreRPG
import SwiftUI

struct CarouselPhotoView: View {
    let photoIds: ItemSelectionModel
    let selection: GroupItemSelectionModel
    
    @Environment(PhotoRootModel.self) private var root
    
    @Environment(\.appSizeMode) private var appSizeMode
    @Environment(\.navigator) private var navigator
    
    @State private var showSelection = false
    
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
            if appSizeMode == .regular {
                Text("Drop \(root.configurable.module.title)", bundle: .module)
                
                Image(systemName: "square.and.arrow.down")
                    .imageScale(.large)
            }
            Button {
                withAnimation(.easeInOut) { showSelection.toggle() }
                //navigator.navigate(to: SelectionModuleRoute.selection, method: .managedSheet)
            } label: {
                VStack {
                    Text("Select", bundle: .module)
                    if appSizeMode == .compact {
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
        .sheet(isPresented: $showSelection) {
            SelectionModuleRoute.selection
                .environment(root.rootController)
                .environment(photoIds)
        }
    }
    
    func linkHandler(name: String, itemId: UUID, entryId: UUID?) {
        guard !photoIds.selection.contains(where: { $0.itemId == itemId }) else { return }
        withAnimation(.easeInOut) { photoIds.selection.append(WindowItemSelection(itemId: itemId)) }
    }
    
    func itemView(itemId: UUID, selectedItemId: UUID?) -> some View {
        Group {
            if let cacheControllable = root.cacheControllable {
                GroupedPhotoView(cacheController: cacheControllable, itemControllable: root.itemControllable, model: nil)
            }
        }
        .environment(GroupItemSelectionModel(selectedItem: itemId))
        .frame(height: 110)
        .onTapGesture {
            withAnimation(.easeInOut) { selection.selectedItem = selectedItemId }
        }
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
        .dropDestination(for: root.configurable.module, handler: linkHandler(name:itemId:entryId:))
        .padding(1)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(PhotoRootModel.self) var root
    
    CarouselPhotoView(photoIds: ItemSelectionModel(selection: root.itemController.itemDataModel.items.map { WindowItemSelection(itemId: $0) }, isSingleSelection: false), selection: GroupItemSelectionModel())
}
