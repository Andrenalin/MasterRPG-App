// @copyright André Trettin

import SwiftData
import SwiftUI

public struct DetailItemEditorView<Model: Identifiable, EditController: EditControllable>: View where Model == EditController.Model {
    public init(model: Model, editController: EditController, nameKeyPath: KeyPath<Model, String>, categoryKeyPath: KeyPath<Model, ItemListCategory>, tagsKeyPath: KeyPath<Model, [String]>, descriptionKeyPath: KeyPath<Model, String>) {
        self.model = model
        self.editController = editController
        self.nameKeyPath = nameKeyPath
        self.categoryKeyPath = categoryKeyPath
        self.tagsKeyPath = tagsKeyPath
        self.descriptionKeyPath = descriptionKeyPath
        _name = State(wrappedValue: model[keyPath: nameKeyPath])
        _category = State(wrappedValue: model[keyPath: categoryKeyPath])
        _tags = State(wrappedValue: model[keyPath: tagsKeyPath])
        _information = State(wrappedValue: model[keyPath: descriptionKeyPath])
    }
    
    let model: Model
    let editController: EditController
    let nameKeyPath: KeyPath<Model, String>
    let descriptionKeyPath: KeyPath<Model, String>
    let categoryKeyPath: KeyPath<Model, ItemListCategory>
    let tagsKeyPath: KeyPath<Model, [String]>
    
    @Environment(\.dismiss) private var dismiss
    
    enum FocusField {
        case name
        case information
    }
    @FocusState private var currentFocus: FocusField?
    
    @State private var name: String
    @State private var information: String
    @State private var category: ItemListCategory
    @State private var tags: [String]
    
    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 4) {
                nameSection
                descriptionSection
                categoryTagsSection
                
                AddTagsEditor(tags: $tags)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        withAnimation { dismiss() }
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        editController.update(model: model, name: name, information: information, category: category, tags: tags)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
}

private extension DetailItemEditorView {
    @ViewBuilder
    private var nameSection: some View {
        Text("Name")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        
        HStack {
            TextField(text: $name, prompt: Text("Enter a name")) {
                Text("Name")
            }
            .focused($currentFocus, equals: .name)

            Button {
                name = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .opacity(name.isEmpty ? 0: 1)
            .contentTransition(.symbolEffect(.automatic))
        }
        .padding(.bottom, 6)
    }
    
    @ViewBuilder
    var descriptionSection: some View {
        Text("Description")
            .font(.caption)
            .foregroundStyle(.secondary)
#if os(tvOS)
        TextField(text: $information, prompt: Text("Insert a description"), axis: .vertical) {
            Text("Description")
        }
        .frame(minHeight: 120, maxHeight: 200)
        .border(Color.accentColor.secondary)
        .padding(.bottom, 6)
        .focused($currentFocus, equals: .information)
#else
        TextEditor(text: $information)
            .frame(minHeight: 120, maxHeight: 200)
            .border(Color.accentColor.secondary)
            .padding(.bottom, 6)
            .focused($currentFocus, equals: .information)
#endif
    }
    
    @ViewBuilder
    var categoryTagsSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text("Category")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Category", selection: $category) {
                    ForEach(ItemListCategory.allCases, id: \.self) { cat in
                        Text(cat.title)
                            .tag(cat)
                    }
                }
                .pickerStyle(.menu)
            }
            
            VStack(alignment: .leading) {
                Text("Tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                RemoveTagsEditor(tags: $tags)
                    .offset(y: -8)
            }
        }
    }
    
    private var isEqual: Bool {
        model[keyPath: nameKeyPath] == name &&
        model[keyPath: descriptionKeyPath] == information &&
        model[keyPath: categoryKeyPath] == category &&
        model[keyPath: tagsKeyPath] == tags
    }
}
