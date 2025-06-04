// @copyright André Trettin

import SwiftUI

public protocol CategoryTextRepresentable: Equatable, Hashable, Identifiable {
    var title: String { get }
}

@MainActor @Observable
final class CategoryEditModel {
    init(selection: ItemListCategory = .all) {
        self.selection = selection
    }

    var selection: ItemListCategory
}

struct CategoryItemEditor: View {
    init(editController: any EditControllable, allCategories: [ItemListCategory], title: LocalizedStringKey = "Category") {
        self.editController = editController
        self.allCategories = allCategories
        self.title = title
    }

    let editController: any EditControllable
    let allCategories: [ItemListCategory]
    let title: LocalizedStringKey

    var body: some View {
        let _ = Self._printChanges()
        @Bindable var model = editController.editorModel.categoryEditModel
        LabeledContent {
            Picker(selection: $model.selection) {
                ForEach(allCategories) { category in
                    Text(category.title)
                        .tag(category)
                }
            } label: {
                Text(title, bundle: .module)
            }
            .labelsHidden()
            .pickerStyle(.automatic)
            .tint(Color.accentColor)
        } label: {
            Text(title, bundle: .module)
        }
        .onChange(of: model.selection) {
            editController.reset(category: model.selection)
        }
        .onChange(of: editController.model.category) {
            guard editController.editorModel.currentItemId != nil else { return }
            editController.editorModel.categoryEditModel.selection <=> editController.model.category
        }
    }
}
