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
    
    var body: some View {
        VStack(spacing: 0) {
            PlainPhotoView(model: model, ratio: .fit)
                .frame(height: 128)
                .frame(maxWidth: .infinity)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    
                    // Name
                    Text("Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("Name", text: $name)
                        if !name.isEmpty {
                            Button {
                                name = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    Divider()
                    
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
                                        
                    // Degrees
//                    Text("Degrees")
//                        .font(.caption)
//                        .foregroundStyle(.secondary)
                    Picker("Degrees", selection: $degrees) {
                        Text("0°").tag(0.0)
                        Text("90°").tag(90.0)
                        Text("180°").tag(180.0)
                        Text("270°").tag(270.0)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 6)
                    Divider()
                    
                    // Information
                    Text("Information")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $information)
                        .frame(minHeight: 12)
                        .padding(.vertical, 6)
                }
                .padding(.horizontal)
            }
            
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }

                Spacer()
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
            .padding()
        }
        .padding()
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
