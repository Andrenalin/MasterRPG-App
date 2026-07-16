// @copyright André Trettin

import SwiftData
import SwiftUI

public struct ItemHeaderEditorView: View {
    public init(
        editControllable: any EditControllable,
        model: any ItemDataAccessable,
        needsNavigationStack: Bool = true
    ) {
        self.editControllable = editControllable
        self.model = model
        self.needsNavigationStack = needsNavigationStack
        
        // Initialize @State properties with model values
        self._name = State(initialValue: model.name)
        self._information = State(initialValue: model.description)
        self._category = State(initialValue: model.category)
        self._tags = State(initialValue: model.tags)
    }

    let editControllable: any EditControllable
    let model: any ItemDataAccessable
    let needsNavigationStack: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    enum FocusField {
        case name
        case information
    }
    @FocusState private var currentFocus: FocusField?

    @State private var name: String
    @State private var information: String
    @State private var category: ItemListCategory
    @State private var tags: [String]
    @State private var isDirty: Bool = false
    
    private var isNameValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var shouldWrapInNavigationStack: Bool {
        needsNavigationStack && valueFor(iOS: true, macOS: false, tvOS: false, visionOS: true)
    }

    public var body: some View {
        editorContent.managedNavigationStack(wrapping: shouldWrapInNavigationStack)
    }
    
    private var editorContent: some View {
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
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(Text("Cancel", bundle: .module))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    saveChanges()
                } label: {
                    Image(systemName: "checkmark")
                }
                .disabled(!isNameValid)
                .accessibilityLabel(Text("Save", bundle: .module))
            }
        }
        .animation(accessibilityReduceMotion ? nil : .snappy, value: currentFocus)
        .onAppear {
#if !os(tvOS)
            currentFocus = .name
#endif
        }
        .onChange(of: name) { isDirty = true }
        .onChange(of: information) { isDirty = true }
        .onChange(of: category) { isDirty = true }
        .onChange(of: tags) { isDirty = true }
        .interactiveDismissDisabled(isDirty)
#if os(macOS)
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
#endif
        .resetAppColorScheme()
    }
    
    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        editControllable.update(
            id: model.id,
            name: trimmedName,
            description: information,
            category: category,
            tags: tags
        )
        
#if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
#endif
        
        dismiss()
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
            .onSubmit {
                currentFocus = .information
            }
            .submitLabel(.next)
#if os(iOS) || os(visionOS)
            .padding(.horizontal, 6)
            .padding(.vertical, valueFor(iOS: 8, macOS: 0, tvOS: 0, visionOS: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(currentFocus == .name ? Color.accentColor.opacity(0.7) : Color.secondary, lineWidth: currentFocus == .name ? 4 : 1)
            }
#endif

            Button {
                name = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 44, minHeight: 44)
            .disabled(name.isEmpty)
            .opacity(name.isEmpty ? 0 : 1)
            .accessibilityHidden(name.isEmpty)
            .accessibilityLabel(Text("Clear name", bundle: .module))
            .contentTransition(.symbolEffect(.automatic))
        }
        .padding(.bottom, 6)
    }
    
    @ViewBuilder
    private var descriptionEditor: some View {
#if os(tvOS)
        TextField(
            text: $information,
            prompt: Text("Insert a description", bundle: .module),
            axis: .vertical
        ) {
            Text("Description", bundle: .module)
        }
        .lineLimit(5...10)
#else
        TextEditor(text: $information)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
#endif
    }
    
    @ViewBuilder
    var descriptionSection: some View {
        Text("Description", bundle: .module)
            .font(.caption)
            .foregroundStyle(.secondary)
        
        descriptionEditor
            .frame(minHeight: 120, maxHeight: 200)
            .focused($currentFocus, equals: .information)
            .padding(.horizontal, 2)
            .padding(.vertical, valueFor(iOS: 0, macOS: 8, tvOS: 0, visionOS: 0))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(currentFocus == .information ? Color.accentColor.opacity(0.7) : Color.secondary, lineWidth: currentFocus == .information ? 4 : 1)
            }
            .padding(.bottom, 6)
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
}

#Preview("Item Header Editor") {
    ItemHeaderEditorView(
        editControllable: FakeEditController.fake,
        model: FakeItemModel(
            id: .fixture1,
            name: "Ancient Map",
            category: .album,
            description: "A weathered map showing the road to the lost keep.",
            tags: ["Map", "Quest"]
        )
    )
    .tint(NetworkModules.space.tint)
    .environment(AppSettingsModel.previewFixture())
}
