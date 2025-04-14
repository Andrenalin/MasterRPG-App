// @copyright André Trettin

import SwiftUI

public protocol CategoryTextRepresentable: Equatable, Hashable, Identifiable {
    var title: String { get }
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
        LabeledContent {
            Picker(selection: categoryBinding) {
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
    }
    
    var categoryBinding: Binding<ItemListCategory> {
        Binding {
            editController.model.category
        } set: {
            editController.reset(category: $0)
        }
    }
}
