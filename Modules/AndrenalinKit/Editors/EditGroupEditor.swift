// @copyright André Trettin

import SwiftUI

public struct EditGroupEditor<Model, ItemDataController: ItemControllable, ItemEditController: EditControllable, RowView: View>: View where Model == ItemDataController.Model, Model == ItemEditController.Model {
    public init(editGroupController: EditGroupController<ItemDataController, ItemEditController>, isPresented: Binding<Bool>, @ViewBuilder rowView: @escaping (Model) -> RowView) {
        self.editGroupController = editGroupController
        self._isPresented = isPresented
        self.rowView = rowView
    }

    let editGroupController: EditGroupController<ItemDataController, ItemEditController>
    let rowView: (Model) -> RowView
    @Binding var isPresented: Bool
        
    public var body: some View {
        NavigationStack {
            formView
        }
#if os(macOS)
        .padding()
#endif
    }

    private var formView: some View {
        Form {
            EditGroupHeaderEditor(editGroupController: editGroupController)

#if os(macOS)
            ScrollView {
                sectionView
            }
#else
            sectionView
#endif
        }
#if os(macOS)
        .listStyle(.inset)
        .alternatingRowBackgrounds(.enabled)
#endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                ModalPresentCloseButton(isPresented: $isPresented)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        await editGroupController.save()
                        isPresented.toggle()
                    }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
            }
        }
    }

    private var sectionView: some View {
        Section {
            ForEach(editGroupController.selections) { item in
                if let model = editGroupController.model(for: item.model.itemId) {
                    rowView(model)
                }
            }
        } header: {
            Text("\(editGroupController.selections.count) Item")
                .frame(maxWidth: .infinity)
                .font(.headline)
        }
    }
}

struct EditGroupHeaderEditor<Model, ItemDataController: ItemControllable, ItemEditController: EditControllable>: View where Model == ItemDataController.Model, Model == ItemEditController.Model {
    let editGroupController: EditGroupController<ItemDataController, ItemEditController>

    var body: some View {
        Section {
#if os(macOS)
            HStack {
                NameItemEditor(editController: editGroupController)
                    .frame(maxWidth: .infinity, alignment: .leading)

                CategoryItemEditor(editController: editGroupController, allCategories: editGroupController.itemControllable.itemDataModel.categoryTags + [.all])
                    .labelsHidden()
                    .fixedSize()

                ToggleHiddenEditor(editController: editGroupController, bundle: .module)
                    .labelsHidden()
                Text("Hidden", bundle: .module)
            }
#else
            NameItemEditor(editController: editGroupController)

            CategoryItemEditor(editController: editGroupController, allCategories: editGroupController.itemControllable.itemDataModel.categoryTags + [.all])
#endif
            TagsItemEditor(editController: editGroupController, module: editGroupController.itemControllable.itemDataModel.networkModule)

#if !os(macOS)
            ToggleHiddenEditor(editController: editGroupController, bundle: .module)
#endif

            DescriptionItemEditor(editController: editGroupController)

        } header: {
            Text("Group Editor", bundle: .module)
                .frame(maxWidth: .infinity)
                .font(.headline)
                .hideKeyboardView(show: true)
        }
    }
}
