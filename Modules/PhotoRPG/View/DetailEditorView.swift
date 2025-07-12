// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailEditorView: View {
    let model: PhotoDataModel
    let dismiss: () -> Void
    
    // Editor working copy
    @State private var name: String
    @State private var information: String
    @State private var category: ItemListCategory
    @State private var tags: [String]
    @State private var newTag: String = ""
    @State private var degrees: Double
    @State private var url: URL?
    @State private var entriesCount: Int
    
    init(model: PhotoDataModel, dismiss: @escaping () -> Void) {
        self.model = model
        _name = State(initialValue: model.name)
        _information = State(initialValue: model.information)
        _category = State(initialValue: model.category)
        _tags = State(initialValue: model.tags)
        _degrees = State(initialValue: model.degrees)
        _url = State(initialValue: model.url)
        _entriesCount = State(initialValue: model.entries?.count ?? 0)
        self.dismiss = dismiss
    }
    
    enum FocusField {
        case name
        case information
    }
    
    @FocusState private var currentFocus: FocusField?
    
    var body: some View {
        VStack(spacing: 0) {
//            PlainPhotoView(model: model, ratio: .fit)
//                .frame(height: 128)
//                .frame(maxWidth: .infinity)
//        Form {
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
                    Text("Information")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $information)
                        .frame(minHeight: 120, maxHeight: 200)
                        .border(Color.accentColor.secondary)
                        .padding(.bottom, 6)
                        .focused($currentFocus, equals: .information)
                    //Divider()
                    
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
                            
                            TagsItemEditor(tags: $tags)
                        }
                    }
                    
                    Divider()

                    Picker("Degrees", selection: $degrees) {
                        Text("0°").tag(0.0)
                        Text("90°").tag(90.0)
                        Text("180°").tag(180.0)
                        Text("270°").tag(270.0)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 6)
                    
                }
                .padding()
            }
            .fixedSize(horizontal: false, vertical: true)
            .keyboardAvoiding(height: 12)
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
            
            ToolbarItem(placement: .bottomBar) {
                Button {
                    model.name = name
                    model.information = information
                    model.category = category
                    model.tags = tags
                    model.degrees = degrees
                    model.url = url
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isEqual)
            }
        }
    }
    
    private var isEqual: Bool {
        model.name == name &&
        model.information == information &&
        model.category == category &&
        model.tags == tags &&
        model.degrees == degrees &&
        model.url == url
    }
    
    private func addNewTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        newTag = ""
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
        entries: nil
    )
    return DetailEditorView(model: sampleModel) { }
        .environment(SearchModel.preview)
        .environment(DeviceRotationModel())
        .environment(PhotoRootModel())
        .environment(CacheItemListModel())
}
