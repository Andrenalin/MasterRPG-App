// @copyright André Trettin

import SwiftUI

/// The route's group editor. The model is created once (`LazyState`), so the route body, which
/// runs on every pass of the presenting view, does not rebuild it and lose the user's typing.
/// See CODE_AUDIT_26 §8.8.
struct GroupEditorRouteView: View {
    let itemController: any ItemControllable
    let editController: any EditControllable
    let ids: [UUID]
    @LazyState private var model: GroupEditorModel

    init(itemController: any ItemControllable, editController: any EditControllable, ids: [UUID]) {
        self.itemController = itemController
        self.editController = editController
        self.ids = ids
        _model = LazyState(wrappedValue: GroupEditorController.processEditorModel(itemController: itemController, ids: ids))
    }

    var body: some View {
        GroupEditorView(groupEditorController: GroupEditorController(
            itemController: itemController,
            editController: editController,
            ids: ids,
            model: model
        ))
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
                NameSectionView(groupEditorController: groupEditorController, currentFocus: $currentFocus)
                DescriptionSectionView(groupEditorController: groupEditorController, currentFocus: $currentFocus)
                CategoryTagsSectionView(groupEditorController: groupEditorController)

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

private struct NameSectionView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let groupEditorController: GroupEditorController
    var currentFocus: FocusState<GroupEditorView.FocusField?>.Binding

    var body: some View {
        @Bindable var model = groupEditorController.model

        Text("Name", bundle: .module)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

        HStack {
            TextField(text: $model.name, prompt: Text(model.namePlaceHolder)) {
                Text("Name", bundle: .module)
            }
            .focused(currentFocus, equals: .name)

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
}

private struct DescriptionSectionView: View {
    let groupEditorController: GroupEditorController
    var currentFocus: FocusState<GroupEditorView.FocusField?>.Binding

    var body: some View {
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
            if model.description.isEmpty && currentFocus.wrappedValue != .information {
                Text(model.descriptionPlaceHolder)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(4)
        .border(Color.accentColor.secondary)
        .padding(.bottom, 6)
        .focused(currentFocus, equals: .information)
#else
        TextEditor(text: $model.description)
            .frame(minHeight: 120, maxHeight: 200)
            .overlay {
                if model.description.isEmpty && currentFocus.wrappedValue != .information {
                    Text(model.descriptionPlaceHolder)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
            .border(Color.accentColor.secondary)
            .padding(.bottom, 6)
            .focused(currentFocus, equals: .information)
#endif
    }
}

private struct CategoryTagsSectionView: View {
    let groupEditorController: GroupEditorController

    var body: some View {
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
