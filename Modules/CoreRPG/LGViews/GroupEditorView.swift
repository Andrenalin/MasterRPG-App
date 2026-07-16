// @copyright André Trettin

import SwiftUI

@Observable @MainActor
final class GroupEditorModel {
    internal init(namePlaceHolder: String, descriptionPlaceHolder: String, tagsPlaceHolder: String) {
        self.namePlaceHolder = namePlaceHolder
        self.descriptionPlaceHolder = descriptionPlaceHolder
        self.tagsPlaceHolder = tagsPlaceHolder
    }
    
    var name: String = ""
    var namePlaceHolder: String
    var description: String = ""
    var descriptionPlaceHolder: String
    var tags: [String] = []
    var tagsPlaceHolder: String
}

struct GroupEditorController {
    @MainActor init(itemController: any ItemControllable, editController: any EditControllable, ids: [UUID]) {
        self.itemController = itemController
        self.editController = editController
        self.ids = ids
        self.model = GroupEditorController.processEditorModel(itemController: itemController, ids: ids)
    }
    
    let itemController: any ItemControllable
    let editController: any EditControllable
    let ids: [UUID]
    
    let model: GroupEditorModel
    
    @MainActor static func processEditorModel(itemController: any ItemControllable, ids: [UUID]) -> GroupEditorModel {
        var name: String?
        var nameIsDifferent = false
        var description: String?
        var descriptionIsDifferent = false
        var tags: [String]?
        var tagsIsDifferent = false

        for itemId in ids {
            guard let model = itemController.itemSync(for: itemId) else { continue }
            if !nameIsDifferent && name == nil {
                name = model.name
            } else if !nameIsDifferent && name != model.name {
                nameIsDifferent = true
                name = nil
            }
            
            if !descriptionIsDifferent && description == nil {
                description = model.description
            } else if !descriptionIsDifferent && description != model.description {
                descriptionIsDifferent = true
                description = nil
            }

            if !tagsIsDifferent && tags == nil {
                tags = model.tags
            } else if !tagsIsDifferent && tags != model.tags {
                tagsIsDifferent = true
                tags = nil
            }
        }
        
        return GroupEditorModel(namePlaceHolder: name ?? String(localized: "Different Names", bundle: .module).localizedString, descriptionPlaceHolder: description ?? String(localized: "Different Descriptions", bundle: .module).localizedString, tagsPlaceHolder: tags?.joined(separator: " ") ?? String(localized: "Different Tags", bundle: .module).localizedString)
    }
    
    @MainActor func save() {
        guard !model.name.isEmpty && model.name != model.namePlaceHolder ||
                !model.description.isEmpty && model.description != model.descriptionPlaceHolder ||
                !model.tags.isEmpty && model.tags.joined(separator: " ") != model.tagsPlaceHolder else { return }
        for itemId in ids {
            if !model.name.isEmpty {
                editController.reset(name: model.name, itemId: itemId)
            }

            if !model.description.isEmpty {
                editController.reset(description: model.description, itemId: itemId)
            }
            
            if !model.tags.isEmpty {
                editController.reset(tags: model.tags, itemId: itemId)
            }
        }
    }
}

struct GroupEditorView: View {
    let groupEditorController: GroupEditorController
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    
    enum FocusField {
        case name
        case information
    }
    @FocusState private var currentFocus: FocusField?

    var body: some View {
        @Bindable var model = groupEditorController.model
        
        NavigationStack {
            VStack(alignment: .leading, spacing: 4) {
                nameSection
                descriptionSection
                categoryTagsSection
                
                AddTagsEditor(tags: $model.tags)
            }
            .padding()
            .padding(.bottom, 32)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        withAnimation(accessibilityReduceMotion ? nil : .default) { dismiss() }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Cancel", bundle: .module))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        groupEditorController.save()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(Text("Save", bundle: .module))
                }
            }
        }
    }
}

#Preview {
    GroupEditorView(
        groupEditorController: GroupEditorController(
            itemController: FakeItemController.fake,
            editController: FakeEditController.fake,
            ids: [UUID()]
        )
    )
}

private extension GroupEditorView {
    @ViewBuilder private var nameSection: some View {
        @Bindable var model = groupEditorController.model
        
        Text("Name", bundle: .module)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        
        HStack {
            TextField(text: $model.name, prompt: Text(model.namePlaceHolder)) {
                Text("Name", bundle: .module)
            }
            .focused($currentFocus, equals: .name)

            Button {
                withAnimation(accessibilityReduceMotion ? nil : .default) { model.name = "" }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 44, minHeight: 44)
            .disabled(model.name.isEmpty)
            .opacity(model.name.isEmpty ? 0: 1)
            .accessibilityHidden(model.name.isEmpty)
            .accessibilityLabel(Text("Clear name", bundle: .module))
            .contentTransition(.symbolEffect(.automatic))
        }
        .padding(.bottom, 6)
    }
    
    @ViewBuilder var descriptionSection: some View {
        @Bindable var model = groupEditorController.model
        
        Text("Description", bundle: .module)
            .font(.caption)
            .foregroundStyle(.secondary)
#if os(tvOS)
        TextField(text: $model.description, prompt: Text(model.descriptionPlaceHolder), axis: .vertical) {
            Text("Description", bundle: .module)
        }
        .frame(minHeight: 120, maxHeight: 200)
        .overlay {
            if model.description.isEmpty && currentFocus != .information {
                Text(model.descriptionPlaceHolder)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(4)
        .border(Color.accentColor.secondary)
        .padding(.bottom, 6)
        .focused($currentFocus, equals: .information)
#else
        TextEditor(text: $model.description)
            .frame(minHeight: 120, maxHeight: 200)
            .overlay {
                if model.description.isEmpty && currentFocus != .information {
                    Text(model.descriptionPlaceHolder)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
            .border(Color.accentColor.secondary)
            .padding(.bottom, 6)
            .focused($currentFocus, equals: .information)
#endif
    }
    
    @ViewBuilder var categoryTagsSection: some View {
        @Bindable var model = groupEditorController.model

        VStack(alignment: .leading) {
            HStack {
                Text("Tags", bundle: .module)

                if model.tags.isEmpty {
                    Text(model.tagsPlaceHolder)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            RemoveTagsEditor(tags: $model.tags)
                .offset(y: -8)
        }
    }
}
