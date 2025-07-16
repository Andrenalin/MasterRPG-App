// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailEditorView: View {
    let model: PhotoDataModel
    let dismiss: () -> Void
    
    @Environment(PhotoRootModel.self) private var rootModel
    
    // Editor working copy
    @State private var name: String
    @State private var information: String
    @State private var category: ItemListCategory
    @State private var tags: [String]
    @State private var degrees: Double
    
    init(model: PhotoDataModel, dismiss: @escaping () -> Void) {
        self.model = model
        _name = State(initialValue: model.name)
        _information = State(initialValue: model.information)
        _category = State(initialValue: model.category)
        _tags = State(initialValue: model.tags)
        _degrees = State(initialValue: model.degrees)
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
                    TextEditor(text: $information)
                        .frame(minHeight: 120, maxHeight: 200)
                        .border(Color.accentColor.secondary)
                        .padding(.bottom, 6)
                        .focused($currentFocus, equals: .information)
                    
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

                    Picker("Degrees", selection: $degrees) {
                        Text("0°").tag(0.0)
                        Text("90°").tag(90.0)
                        Text("180°").tag(180.0)
                        Text("270°").tag(270.0)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 6)
                    
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
                rootModel.editController.update(model: model, name: name, information: information, category: category, tags: tags, degrees: degrees)
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
        degrees = model.degrees
    }
    
    private var isEqual: Bool {
        model.name == name &&
        model.information == information &&
        model.category == category &&
        model.tags == tags &&
        model.degrees == degrees
    }
}

#Preview {
    let sampleModel = PhotoDataModel(
        id: UUID(),
        name: "Sunset Beach",
        information: "A photo taken at sunset.",
        category: .photo,
        tags: ["beach","summer","sunset"],
        displayState: 1,
        degrees: 0,
        url: URL(string: "https://example.com/photo.jpg"),
        entries: []
    )
    return DetailEditorView(model: sampleModel) { }
        .environment(SearchModel.preview)
        .environment(DeviceRotationModel())
        .environment(PhotoRootModel())
        .environment(CacheItemListModel())
}
