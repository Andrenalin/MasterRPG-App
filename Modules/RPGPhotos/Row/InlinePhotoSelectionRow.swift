// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct InlinePhotoSelectionRow: View {
    let editController: any EditControllable
    let photoId: Binding<UUID?>
    let entryId: UUID
    let showSelector: Binding<UUID?>

    @Environment(PhotoRoot.self) private var root

    var body: some View {
        LabeledContent {
            HStack {
                if let photoId = photoId.wrappedValue {
                    MainRow(model: root.itemController.itemOrEmpty(for: photoId), isSelected: false, cacheItemListModel: editController.cacheItemListModel)
                        .padding(.leading, 32)
                        .overlay(alignment: .topLeading) {
                            Image(systemName: "minus.circle.fill")
                                .imageScale(.large)
                                .padding(4)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .red)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                        }
                        .padding(.bottom)
                        .onTapGesture { removeItem() }
                }
                Spacer()
                
                Button {
                    withAnimation {
                        showSelector.wrappedValue = entryId
                    }
                } label: {
                    Label {
                        Text(photoId.wrappedValue == nil ? "Add" : "Change", bundle: .module)
                    } icon: {
                        Image(systemName: root.itemController.itemDataModel.networkModule.icon)
                    }
                }
            }
        } label: {
            Text("Photo", bundle: .module)
        }
    }
    
    func removeItem() {
        withAnimation {
            photoId.wrappedValue = nil
            editController.save(with: String(localized: "Remove Photo").localizedString)
        }
    }
}
