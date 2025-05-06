// @copyright André Trettin

import SwiftUI
import AndrenalinKit

@Observable
final class ChangeChildModel {
    internal init(showChildLinkAlert: Bool = false, childId: UUID? = nil, entryId: UUID? = nil) {
        self.showChildLinkAlert = showChildLinkAlert
        self.childId = childId
        self.entryId = entryId
    }
    
    var showChildLinkAlert: Bool
    var childId: UUID?
    var entryId: UUID?
}

struct ChangeChildEditorViewModifier: ViewModifier {
    let editController: EditController
    let model: ChangeChildModel

    @Environment(ValueRoot.self) private var root

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .alert(Text("Item is used", bundle: .module), isPresented: $model.showChildLinkAlert) {
                Button(role: .destructive) {
                    guard let childId = model.childId, let entryId = model.entryId else { return }
                    editController.removeChild(childId: childId)
                    editController.addChild(childId: childId, into: entryId)
                } label: {
                    Text("Remove and add", bundle: .module)
                }

                Button {
                    guard let childId = model.childId, let entryId = model.entryId else { return }
                    Task {
                        await editController.copyAddChild(childId: childId, into: entryId)
                    }
                } label: {
                    Text("Copy and add", bundle: .module)
                }
            } message: {
                Text(message, bundle: .module)
            }
    }

    var noParent: LocalizedStringResource {
        "No Parent"
    }

    var notSet: LocalizedStringResource {
        "Not Set"
    }

    var message: LocalizedStringKey {
        let itemTitle: String
        let usedTitle: String
        if let childId = model.childId {
            let child = root.itemController.itemOrEmpty(for: childId)
            itemTitle = child.name
            if let parentId = child.parentId {
                let item = root.itemController.itemOrEmpty(for: parentId)
                usedTitle = "\(item.name) -- \(item.entries.first { $0.valueId == childId }?.name ?? "")"
            } else {
                usedTitle = String(localized: noParent).localizedString
            }
        } else {
            itemTitle = String(localized: notSet).localizedString
            usedTitle = String(localized: noParent).localizedString
        }
        return "The Item \"\(itemTitle)\" is already used in \"\(usedTitle)\" and cannot added as group item again. Do you want to remove it from the other character or item? Or you can copy the item and add."
    }
}

#Preview {
    Color.blue.modifier(
        ChangeChildEditorViewModifier(editController: .preview, model: ChangeChildModel(showChildLinkAlert: true, childId: nil, entryId: nil))
    )
    .environment(ValueRoot.previewWithData)
}
