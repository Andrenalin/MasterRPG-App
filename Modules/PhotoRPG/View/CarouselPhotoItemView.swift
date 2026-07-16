// @copyright André Trettin

import CoreRPG
import SwiftUI

struct CarouselPhotoItemView: View {
    let photoSelection: WindowItemSelection
    let photoIds: ItemSelectionModel
    let groupSelection: GroupItemSelectionModel

    @Environment(PhotoRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var itemSelectionModel: GroupItemSelectionModel

    init(
        photoSelection: WindowItemSelection,
        photoIds: ItemSelectionModel,
        groupSelection: GroupItemSelectionModel
    ) {
        self.photoSelection = photoSelection
        self.photoIds = photoIds
        self.groupSelection = groupSelection
        _itemSelectionModel = State(
            wrappedValue: GroupItemSelectionModel(selectedItem: photoSelection.itemId)
        )
    }

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut) {
                groupSelection.selectedItem = photoSelection.itemId
            }
        } label: {
            Group {
                if let cacheControllable = root.cacheControllable {
                    GroupedPhotoView(
                        cacheController: cacheControllable,
                        itemControllable: root.itemControllable,
                        model: nil
                    )
                }
            }
            .environment(itemSelectionModel)
            .frame(height: 110)
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(verbatim: root.itemControllable.nameSync(itemId: photoSelection.itemId))
        )
        .accessibilityValue(
            groupSelection.selectedItem == photoSelection.itemId
                ? Text("Selected", bundle: .module)
                : Text("Not selected", bundle: .module)
        )
        .accessibilityAddTraits(
            groupSelection.selectedItem == photoSelection.itemId ? .isSelected : []
        )
        .dropDestination(
            for: root.configurable.module,
            handler: addLink(name:itemId:entryId:)
        )
        .padding(1)
        .overlay(alignment: .topTrailing) {
            Button(role: .destructive) {
                withAnimation(reduceMotion ? nil : .easeInOut) {
                    photoIds.selection.removeAll(where: { $0 == photoSelection })
                }
            } label: {
                Label {
                    Text("Remove", bundle: .module)
                } icon: {
                    Image(systemName: "minus.circle.fill")
                }
            }
            .labelStyle(.iconOnly)
            .imageScale(.large)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(.white, .red, .red)
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
        withAnimation(reduceMotion ? nil : .easeInOut) {
            photoIds.selection.append(WindowItemSelection(itemId: itemId))
        }
    }
}

#Preview(traits: .mockData) {
    CarouselPhotoItemView(
        photoSelection: WindowItemSelection(itemId: PhotoModel.previewId),
        photoIds: ItemSelectionModel(
            selection: [WindowItemSelection(itemId: PhotoModel.previewId)],
            isSingleSelection: false
        ),
        groupSelection: GroupItemSelectionModel()
    )
}
