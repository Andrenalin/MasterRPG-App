// @copyright André Trettin

import SwiftUI

public struct AddTagsEditor: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.appTheme) private var theme

    public init(tags: Binding<[String]>, prompt: LocalizedStringKey = "New tag") {
        self._tags = tags
        self.prompt = prompt
    }

    @Binding var tags: [String]
    let prompt: LocalizedStringKey

    @FocusState private var focusState: Bool
    @State private var currentTag: String = ""

    public var body: some View {
        addTagView
    }
}

private extension AddTagsEditor {
    var addTagView: some View {
        GlassEffectContainerAll {
            HStack(spacing: 12) {
                TextField(text: $currentTag, prompt: Text(prompt, bundle: .module)) {
                    Text("Tag", bundle: .module)
                }
#if os(iOS) || os(visionOS)
                .autocapitalization(.none)
                .textContentType(.name)
#endif
                .disableAutocorrection(true)
                .focused($focusState)
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
                    focusState = true
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
                .disabled(currentTag.isEmpty)
            }
        }
    }

    func addCurrentTag() {
        let tag = currentTag.localizedUppercase
        guard !tags.contains(where: { $0 == tag }) else { return }
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
