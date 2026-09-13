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
                } else {
                    // Reachable whenever the cache controller isn't set up
                    // yet — without this, the carousel showed a blank
                    // tappable capsule with no visual affordance. See
                    // CODE_AUDIT_13 §8.13.
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .environment(itemSelectionModel)
            .frame(height: 120)
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
                withAnimation(reduceMotion ? nil : .easeInOut) {
                    photoIds.selection.removeAll(where: { $0 == photoSelection })
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.white, .red, .red)
            }
            .accessibilityLabel(Text("Remove", bundle: .module))
            .frame(minWidth: 44, minHeight: 44)
            .borderLessTVBottonStyle()
            .padding(4)
            .contentShape(.circle)
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
