// @copyright André Trettin

import SwiftUI

public struct HeaderEditor: View {
    public init(editController: any EditControllable) {
        self.editController = editController
    }

    let editController: any EditControllable

    public var body: some View {
        let _ = Self._printChanges()
        Section {
#if os(macOS)
            HStack {
                NameItemEditor(editController: editController)
                    .frame(maxWidth: .infinity, alignment: .leading)

                CategoryItemEditor(editController: editController, allCategories: editController.itemControllable.itemDataModel.categoryTags)
                    .labelsHidden()
                    .fixedSize()

                HiddenToggleEditor(editController: editController)
                    .labelsHidden()
            }
#else
            NameItemEditor(editController: editController)

            CategoryItemEditor(editController: editController, allCategories: editController.itemControllable.itemDataModel.categoryTags)
#endif
            TagsItemEditor(editController: editController, module: editController.itemControllable.config.module)

#if !os(macOS)
            HiddenToggleEditor(editController: editController)
#endif

            DescriptionItemEditor(editController: editController)
        } header: {
#if !os(macOS)
            Text(verbatim: "")
                .frame(maxWidth: .infinity)
                .font(.headline)
                .hideKeyboardView(show: true)
#endif
        }
    }
}
