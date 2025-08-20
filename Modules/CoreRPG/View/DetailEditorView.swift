// @copyright André Trettin

import SwiftData
import SwiftUI

public struct DetailItemEditorView<Model: Identifiable, EditController: OldEditControllable>: View where Model == EditController.Model {
    public init(model: Model, editController: EditController, name: KeyPath<Model, String>, category: KeyPath<Model, ItemListCategory>, tags: KeyPath<Model, [String]>, description: KeyPath<Model, String>) {
        self.model = model
        self.editController = editController
        self.nameKeyPath = name
        self.categoryKeyPath = category
        self.tagsKeyPath = tags
        self.descriptionKeyPath = description
        _name = State(wrappedValue: model[keyPath: name])
        _category = State(wrappedValue: model[keyPath: category])
        _tags = State(wrappedValue: model[keyPath: tags])
        _information = State(wrappedValue: model[keyPath: description])
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
            .padding(.bottom, 32)
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
        Text("Name", bundle: .module)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        
        HStack {
            TextField(text: $name, prompt: Text("Enter a name", bundle: .module)) {
                Text("Name", bundle: .module)
            }
            .focused($currentFocus, equals: .name)

            Button {
                withAnimation { name = "" }
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
        Text("Description", bundle: .module)
            .font(.caption)
            .foregroundStyle(.secondary)
#if os(tvOS)
        TextField(text: $information, prompt: Text("Insert a description", bundle: .module), axis: .vertical) {
            Text("Description", bundle: .module)
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
                Text("Category", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(selection: $category) {
                    ForEach(ItemListCategory.allCases, id: \.self) { cat in
                        Text(cat.title)
                            .tag(cat)
                    }
                } label: {
                    Text("Category", bundle: .module)
                }
                .pickerStyle(.menu)
            }
            
            VStack(alignment: .leading) {
                Text("Tags", bundle: .module)
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
