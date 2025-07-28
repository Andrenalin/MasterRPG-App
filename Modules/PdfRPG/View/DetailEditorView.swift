// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailEditorView: View {
    let model: PdfDataModel
    let dismiss: () -> Void
    
    @Environment(PdfRootModel.self) private var root
    
    // Editor working copy
    @State private var name: String
    @State private var information: String
    @State private var category: ItemListCategory
    @State private var tags: [String]
    
    init(model: PdfDataModel, dismiss: @escaping () -> Void) {
        self.model = model
        _name = State(initialValue: model.name)
        _information = State(initialValue: model.information)
        _category = State(initialValue: model.category)
        _tags = State(initialValue: model.tags)
        self.dismiss = dismiss
    }
    
    enum FocusField {
        case name
        case information
    }
    
    @FocusState private var currentFocus: FocusField?
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    
                    // Name
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
                    
                    // Information
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
                    
                    HStack(alignment: .top) {
                        VStack(alignment: .leading) {
                            // Category
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
                            // Tags
                            Text("Tags")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            RemoveTagsEditor(tags: $tags)
                                .offset(y: -8)
                        }
                    }
                    
                    AddTagsEditor(tags: $tags)
                    
                    Divider()
                 
                    actionToolbarView
                        .padding(.top)
                }
                .padding()
            }
            .fixedSize(horizontal: false, vertical: true)
            .keyboardAvoiding(height: 12)
        }
    }
    
    private var actionToolbarView: some View {
        HStack {
            GlassButton {
                reset()
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            
            Spacer()
            
            GlassButton(isProminent: !isEqual) {
                root.editController.update(model: model, name: name, information: information, category: category, tags: tags)
                dismiss()
            } label: {
                Image(systemName: "checkmark")
            }
            .disabled(isEqual)
        }
    }
    
    private func reset() {
        name =  model.name
        information = model.information
        category = model.category
        tags = model.tags
    }
    
    private var isEqual: Bool {
        model.name == name &&
        model.information == information &&
        model.category == category &&
        model.tags == tags
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PdfDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    DetailEditorView(model: models[0]) { }
        .environment(SearchModel.preview(modelContext: modelContext, module: PdfDataModel.typeId))
        .environment(DeviceRotationModel())
        .environment(PdfRootModel(modelContext: modelContext))
        .environment(CacheItemListModel())
}
