// @copyright André Trettin

import SwiftUI

public struct ItemHeaderEditorView: View {
    /// Lets this view's own presentation animation finish before grabbing keyboard focus —
    /// focusing mid-transition reads as a glitch. See CODE_AUDIT §9.14.
    private static let autoFocusDelay: Duration = .milliseconds(100)
    public init(
        editControllable: any EditControllable,
        model: any ItemDataAccessable,
        module: NetworkModules,
        dismiss: @escaping () -> Void
    ) {
        self.editControllable = editControllable
        self.model = model
        self.module = module
        self.dismissAction = dismiss

        // Initialize @State properties with model values
        self._attributedName = State(initialValue: AttributedString(model.name))
        self._attributedInformation = State(initialValue: AttributedString(model.description))
        self._category = State(initialValue: model.category)
        self._tags = State(initialValue: model.tags)
    }

    let editControllable: any EditControllable
    let model: any ItemDataAccessable
    let module: NetworkModules
    let dismissAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    enum FocusField {
        case name
        case information
    }
    @FocusState private var currentFocus: FocusField?

    @State private var attributedName: AttributedString
    @State private var attributedInformation: AttributedString
    @State private var category: ItemListCategory
    @State private var tags: [String]

    private var isNameValid: Bool {
        !String(attributedName.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        GlassEffectContainerAll {
            ItemHeaderEditorCard(
                module: module,
                dismissAction: dismissAction,
                saveAction: saveChanges,
                isSaveEnabled: isNameValid,
                attributedName: $attributedName,
                attributedInformation: $attributedInformation,
                tags: $tags,
                currentFocus: $currentFocus
            )
        }
        .frame(maxWidth: 800)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background {
            Button {
                withAnimation(accessibilityReduceMotion ? nil : .default) {
                    dismissAction()
                }
            } label: {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .task {
#if !os(tvOS)
            try? await Task.sleep(for: Self.autoFocusDelay)
            currentFocus = .name
#endif
        }
#if os(macOS)
        .onKeyPress(.escape) {
            dismissAction()
            return .handled
        }
#endif
    }

    private func saveChanges() {
        let trimmedName = String(attributedName.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        editControllable.update(
            id: model.id,
            name: trimmedName,
            description: String(attributedInformation.characters),
            category: category,
            tags: tags,
            // The standalone item editor always persists, even while a game is
            // running — unlike in-game quick-edit surfaces, which stay memory-only.
            forceSave: true
        )

#if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
#endif

        dismissAction()
    }
}

private extension View {
    @ViewBuilder
    func itemHeaderEditorGlass(tint: Color) -> some View {
#if os(visionOS)
        self
#else
        glassEffectAll(
            .regular.tint(tint.opacity(0.18)),
            in: .rect(cornerRadius: 28, style: .continuous)
        )
#endif
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.2)
//
// Each gives SwiftUI its own diffing boundary, instead of the previous computed `some View`
// properties on `ItemHeaderEditorView` itself.

private struct ItemHeaderEditorCard: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency

    let module: NetworkModules
    let dismissAction: () -> Void
    let saveAction: () -> Void
    let isSaveEnabled: Bool

    @Binding var attributedName: AttributedString
    @Binding var attributedInformation: AttributedString
    @Binding var tags: [String]
    var currentFocus: FocusState<ItemHeaderEditorView.FocusField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ItemHeaderEditorHeaderRow(dismissAction: dismissAction, saveAction: saveAction, isSaveEnabled: isSaveEnabled)
            ItemHeaderEditorNameSection(attributedName: $attributedName, currentFocus: currentFocus)
            ItemHeaderEditorDescriptionSection(attributedInformation: $attributedInformation, currentFocus: currentFocus)
            ItemHeaderEditorTagsSection(tags: $tags)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(theme.panelColor.opacity(accessibilityReduceTransparency ? 1 : 0.58))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(theme.tint(for: module).opacity(0.45), lineWidth: 1)
        }
        .itemHeaderEditorGlass(tint: theme.background(for: module))
        .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
        .containerShape(.rect(cornerRadius: 28, style: .continuous))
    }
}

private struct ItemHeaderEditorHeaderRow: View {
    let dismissAction: () -> Void
    let saveAction: () -> Void
    let isSaveEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            GlassButton(action: dismissAction) {
                Label {
                    Text("Cancel", bundle: .module)
                } icon: {
                    Image(systemName: "xmark")
                }
                .labelStyle(.iconOnly)
            }
            .buttonSizing(.fitted)
            .buttonBorderShape(.circle)
            .controlSize(.large)
#if os(macOS)
            .keyboardShortcut(.cancelAction)
#endif

            Spacer(minLength: 0)

            GlassButton(isProminent: true, action: saveAction) {
                Label {
                    Text("Save", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark")
                }
                .labelStyle(.iconOnly)
            }
            .buttonSizing(.fitted)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .disabled(!isSaveEnabled)
        }
    }
}

private struct ItemHeaderEditorNameSection: View {
    @Binding var attributedName: AttributedString
    var currentFocus: FocusState<ItemHeaderEditorView.FocusField?>.Binding

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                AttributedTextEditorSurface(
                    text: $attributedName,
                    links: [],
                    minHeight: 44,
                    maxHeight: 44,
                    isFocused: currentFocus.wrappedValue == .name,
                    layout: .singleLine
                )
                .focused(currentFocus, equals: .name)
                .onSubmit {
                    currentFocus.wrappedValue = .information
                }
                .overlay(alignment: .leading) {
                    if attributedName.characters.isEmpty {
                        Text("Enter a name", bundle: .module)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .allowsHitTesting(false)
                    }
                }

                if !attributedName.characters.isEmpty {
                    Button {
                        attributedName = AttributedString("")
                    } label: {
                        Label {
                            Text("Clear name", bundle: .module)
                        } icon: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .labelStyle(.iconOnly)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(
            accessibilityReduceMotion ? nil : .snappy(duration: 0.2),
            value: attributedName.characters.isEmpty
        )
    }
}

private struct ItemHeaderEditorDescriptionSection: View {
    @Binding var attributedInformation: AttributedString
    var currentFocus: FocusState<ItemHeaderEditorView.FocusField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

#if os(tvOS)
            TextField(
                text: Binding(
                    get: { String(attributedInformation.characters) },
                    set: { attributedInformation = AttributedString($0) }
                ),
                prompt: Text("Insert a description", bundle: .module),
                axis: .vertical
            ) {
                Text("Description", bundle: .module)
            }
            .lineLimit(5...10)
            .frame(minHeight: 120, maxHeight: 200)
            .border(Color.accentColor.secondary)
            .padding(.bottom, 6)
            .focused(currentFocus, equals: .information)
#else
            AttributedTextEditorSurface(
                text: $attributedInformation,
                links: [],
                minHeight: 120,
                maxHeight: 200,
                isFocused: currentFocus.wrappedValue == .information
            )
            .focused(currentFocus, equals: .information)
#endif
        }
    }
}

private struct ItemHeaderEditorTagsSection: View {
    @Binding var tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)

            RemoveTagsEditor(tags: $tags)

            AddTagsEditor(tags: $tags)
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
        ),
        module: .space,
        dismiss: {}
    )
    .moduleTint(.space)
    .environment(AppSettingsModel.previewFixture())
}
