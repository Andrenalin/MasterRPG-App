// @copyright André Trettin

import SwiftUI

public struct AddTagsEditor: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// With a `tagController`, the editor suggests the module's existing tags below the field while
    /// it has focus: the most used ones before anything is typed, then the ones matching the text.
    public init(tags: Binding<[String]>, prompt: LocalizedStringKey = "New tag", tagController: TagController? = nil, module: NetworkModules = .none) {
        self._tags = tags
        self.prompt = prompt
        self.tagController = tagController
        self.module = module
    }

    @Binding var tags: [String]
    let prompt: LocalizedStringKey
    let tagController: TagController?
    let module: NetworkModules

    @FocusState private var focusState: Bool
    @State private var currentTag: String = ""

    public var body: some View {
        let suggestions = visibleSuggestions
        VStack(alignment: .leading) {
            AddTagInputView(
                currentTag: $currentTag,
                focusState: $focusState,
                prompt: prompt,
                addCurrentTag: addCurrentTag
            )

            if !suggestions.isEmpty {
                TagSuggestionsRow(suggestions: suggestions, select: addSuggestion)
                    .transition(.opacity)
            }
        }
        .animation(accessibilityReduceMotion ? nil : .snappy, value: suggestions)
    }

    private var visibleSuggestions: [TagSuggestion] {
#if !os(tvOS)
        // Like a keyboard's suggestion bar, only while typing a tag. tvOS keeps them: moving the
        // focus to a suggestion takes it away from the field.
        guard focusState else { return [] }
#endif
        return tagController?.suggestions(module: module, search: currentTag, excluding: tags) ?? []
    }
}

/// The existing tags offered for the field; tapping one adds it.
private struct TagSuggestionsRow: View {
    let suggestions: [TagSuggestion]
    let select: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(suggestions) { suggestion in
                    TagSuggestionButton(suggestion: suggestion, select: select)
                }
            }
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct TagSuggestionButton: View {
    let suggestion: TagSuggestion
    let select: (String) -> Void

    var body: some View {
        Button {
            select(suggestion.title)
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: suggestion.title)
                    .bold()
                    .textCase(.uppercase)
                Text(suggestion.count, format: .number)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.tint.opacity(0.22), in: .capsule)
            .overlay {
                Capsule().strokeBorder(.tint.opacity(0.5), lineWidth: 1)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add tag \(suggestion.title)", bundle: .module))
        .accessibilityValue(Text("Used \(suggestion.count) times", bundle: .module))
    }
}

private struct AddTagInputView: View {
    @Environment(\.appTheme) private var theme

    @Binding var currentTag: String
    var focusState: FocusState<Bool>.Binding
    let prompt: LocalizedStringKey
    let addCurrentTag: () -> Void

    var body: some View {
        GlassEffectContainerAll {
            HStack(spacing: 12) {
                TextField(text: $currentTag, prompt: Text(prompt, bundle: .module)) {
                    Text("Tag", bundle: .module)
                }
#if os(iOS) || os(visionOS)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled()
                .focused(focusState)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background {
                    Capsule()
                        .fill(theme.panelColor.opacity(0.42))
                }
                .addTagInputGlass()
                .onSubmit {
                    addCurrentTag()
                    focusState.wrappedValue = true
                }

                GlassButton(isProminent: true, action: addCurrentTag) {
                    Label {
                        Text("Add tag", bundle: .module)
                    } icon: {
                        Image(systemName: "plus")
                    }
                    .labelStyle(.iconOnly)
                }
                .buttonSizing(.fitted)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(currentTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private extension AddTagsEditor {
    /// Takes the suggestion over as the typed text and adds it like Return would.
    func addSuggestion(_ title: String) {
        currentTag = title
        addCurrentTag()
        focusState = true
    }

    func addCurrentTag() {
        // Trimmed before the empty and duplicate checks, so " dungeon" and "DUNGEON" are one tag and
        // blank input adds nothing. See CODE_AUDIT_26 §5.77.
        let tag = currentTag.trimmingCharacters(in: .whitespacesAndNewlines).localizedUppercase
        guard !tag.isEmpty else {
            currentTag = ""
            return
        }
        guard !tags.contains(where: { $0 == tag }) else {
            currentTag = ""
            return
        }
        var updatedTags = tags
        updatedTags.append(tag)
        updatedTags = updatedTags.sorted(by: { $0.localizedCompare($1) == .orderedAscending })
        withAnimation(accessibilityReduceMotion ? nil : .bouncy(duration: 0.5, extraBounce: 0.4)) {
            tags = updatedTags
            currentTag = ""
        }
    }
}

private extension View {
    @ViewBuilder
    func addTagInputGlass() -> some View {
#if os(visionOS)
        self
#else
        glassEffectAll(.regular.interactive(), in: .capsule)
#endif
    }
}

#Preview {
    @Previewable @State var tags = ["Dungeon"]
    AddTagsEditor(tags: $tags)
        .padding()
}
