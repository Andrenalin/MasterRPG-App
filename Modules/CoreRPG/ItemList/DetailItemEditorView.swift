// @copyright André Trettin

import SwiftData
import SwiftUI

public struct ItemHeaderEditorView: View {
    public init(editControllable: any EditControllable, model: ItemDataModel) {
        self.editControllable = editControllable
        self.model = model
        _name = State(wrappedValue: model.name)
        _category = State(wrappedValue: model.category)
        _tags = State(wrappedValue: model.tags)
        _information = State(wrappedValue: model.information)
    }
    
    let editControllable: EditControllable
    let model: ItemDataModel
    
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
                        editControllable.update(model: model, name: name, information: information, category: category, tags: tags)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
}

private extension ItemHeaderEditorView {
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
                Text("Tags", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                RemoveTagsEditor(tags: $tags)
                    .offset(y: -8)
            }
        }
    }
    
    private var isEqual: Bool {
        model.name == name &&
        model.information == information &&
        model.category == category &&
        model.tags == tags
    }
}
