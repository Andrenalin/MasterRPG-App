// @copyright André Trettin

import CoreRPG
import SwiftUI

struct CarouselPhotoView: View {
    let photoIds: ItemSelectionModel
    let selection: GroupItemSelectionModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack {
                ForEach(photoIds.selection, id: \.self.itemId) { photoSelection in
                    CarouselPhotoItemView(
                        photoSelection: photoSelection,
                        photoIds: photoIds,
                        groupSelection: selection
                    )
                }

                CarouselDropAreaView(photoIds: photoIds)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .environment(selection)
    }
}

// MARK: - Photo Item

private struct CarouselPhotoItemView: View {
    let photoSelection: WindowItemSelection
    let photoIds: ItemSelectionModel
    let groupSelection: GroupItemSelectionModel

    @Environment(PhotoRootModel.self) private var root
    @State private var itemSelectionModel: GroupItemSelectionModel

    init(photoSelection: WindowItemSelection, photoIds: ItemSelectionModel, groupSelection: GroupItemSelectionModel) {
        self.photoSelection = photoSelection
        self.photoIds = photoIds
        self.groupSelection = groupSelection
        _itemSelectionModel = State(wrappedValue: GroupItemSelectionModel(selectedItem: photoSelection.itemId))
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut) { groupSelection.selectedItem = photoSelection.itemId }
        } label: {
            Group {
                if let cacheControllable = root.cacheControllable {
                    GroupedPhotoView(cacheController: cacheControllable, itemControllable: root.itemControllable, model: nil)
                }
            }
            .environment(itemSelectionModel)
            .frame(height: 110)
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .dropDestination(for: root.configurable.module, handler: addLink(name:itemId:entryId:))
        .padding(1)
        .overlay(alignment: .topTrailing) {
            Button(role: .destructive) {
                withAnimation(.easeInOut) {
                    photoIds.selection.removeAll(where: { $0 == photoSelection })
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.white, .red, .red)
            }
            .accessibilityLabel(Text("Remove", bundle: .module))
            .borderLessTVBottonStyle()
            .padding(4)
            .contentShape(.circle)
#if !os(visionOS)
            .glassEffect(.regular.interactive())
#endif
        }
    }

    private func addLink(name: String, itemId: UUID, entryId: UUID?) {
        guard !photoIds.selection.contains(where: { $0.itemId == itemId }) else { return }
        withAnimation(.easeInOut) { photoIds.selection.append(WindowItemSelection(itemId: itemId)) }
    }
}

// MARK: - Drop Area

private struct CarouselDropAreaView: View {
    let photoIds: ItemSelectionModel

    @Environment(PhotoRootModel.self) private var root
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(ScenesManager.self) private var scenesManager

    @State private var showSheet = false

    var body: some View {
        DropItemModuleArea(module: root.configurable.module, contentView: {
            areaContent
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
    }

    private var areaContent: some View {
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
                withAnimation(.easeInOut) { showSheet = true }
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
        .sheet(isPresented: $showSheet) {
            ManagedPresentationView {
                SelectionRoute.mutliSelection
                    .environment(photoIds)
            }
        }
    }

    private func addLink(name: String, itemId: UUID, entryId: UUID?) {
        guard !photoIds.selection.contains(where: { $0.itemId == itemId }) else { return }
        withAnimation(.easeInOut) { photoIds.selection.append(WindowItemSelection(itemId: itemId)) }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(PhotoRootModel.self) var root

    CarouselPhotoView(photoIds: ItemSelectionModel(selection: root.itemController.itemDataModel.items.map { WindowItemSelection(itemId: $0) }, isSingleSelection: false), selection: GroupItemSelectionModel())
}
